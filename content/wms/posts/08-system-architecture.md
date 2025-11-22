---
title: "WMS系统架构设计"
date: 2025-11-22T16:00:00+08:00
draft: false
tags: ["WMS", "系统架构", "微服务", "技术选型"]
categories: ["技术"]
description: "深入理解WMS系统的技术架构设计，包括技术选型、模块设计、数据库设计和接口设计"
series: ["WMS从入门到精通"]
weight: 8
stage: 3
stageTitle: "架构进阶篇"
---

## 引言

本文讲解WMS系统的技术架构设计，包括技术选型、核心模块、数据库设计和系统集成。

---

## 1. 技术选型

### 1.1 语言与框架

**后端**：
- **Java + Spring Boot**（推荐）
  - ✅ 生态成熟、社区活跃
  - ✅ 微服务友好
  - ✅ 适合大型系统

- **C# + .NET Core**
  - ✅ 性能优秀
  - ✅ 企业级支持
  - ❌ Linux生态稍弱

- **Python + Django/Flask**
  - ✅ 开发快速
  - ❌ 性能较Java稍弱
  - 适用场景：中小型WMS

---

### 1.2 数据库选择

**关系型数据库**：
- **MySQL**（推荐）
  - ✅ 免费开源、性能好
  - ✅ 社区活跃
  - 适用：中小型WMS

- **PostgreSQL**
  - ✅ 功能强大、扩展性好
  - ✅ 支持JSON、全文检索
  - 适用：复杂查询场景

- **Oracle**
  - ✅ 性能强大、稳定性高
  - ❌ 商业授权、成本高
  - 适用：大型企业WMS

**NoSQL数据库**：
- **Redis**：缓存、库存计数器
- **MongoDB**：日志存储、大数据分析

---

### 1.3 消息队列

**RabbitMQ**：
- 用途：订单异步处理、库存同步
- 优点：简单易用、稳定可靠

**Kafka**：
- 用途：大数据流处理、日志采集
- 优点：高吞吐量、持久化

---

## 2. 系统架构

### 2.1 分层架构

```
┌─────────────────────────────────────┐
│       表示层 Presentation Layer     │
│  Web管理后台 + RF终端H5应用          │
└─────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────┐
│       业务层 Business Layer         │
│  入库、出库、库存、波次、任务调度    │
└─────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────┐
│       数据层 Data Layer             │
│  MySQL + Redis + MongoDB            │
└─────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────┐
│       集成层 Integration Layer      │
│  ERP、OMS、TMS API对接              │
└─────────────────────────────────────┘
```

---

### 2.2 微服务架构

```
┌──────────────────────────────────────┐
│         API Gateway（网关）          │
│   Spring Cloud Gateway / Kong        │
└──────────────────────────────────────┘
             ↓          ↓
    ┌────────────┐  ┌────────────┐
    │ 入库服务    │  │ 出库服务    │
    └────────────┘  └────────────┘
             ↓          ↓
    ┌────────────┐  ┌────────────┐
    │ 库存服务    │  │ 波次服务    │
    └────────────┘  └────────────┘
             ↓          ↓
    ┌────────────────────────────┐
    │      库存数据库 MySQL       │
    └────────────────────────────┘
```

**服务拆分原则**：
1. 按业务领域拆分（入库、出库、库存）
2. 单一职责：一个服务只做一件事
3. 服务自治：独立部署、独立数据库

---

## 3. 核心模块设计

### 3.1 入库模块

**核心类**：

```java
// 入库单实体
@Entity
@Table(name = "inbound_order")
public class InboundOrder {
    @Id
    private String orderNo;
    private String warehouseCode;
    private String supplierCode;
    private Date expectArrivalDate;
    private String status;  // 待收货、收货中、已完成

    @OneToMany(mappedBy = "inboundOrder")
    private List<InboundOrderDetail> details;
}

// 入库服务
@Service
public class InboundService {
    // 创建ASN
    public void createASN(InboundOrder order) { ... }

    // 收货
    public void receive(String orderNo, String skuCode, int qty) { ... }

    // 上架
    public void putaway(String orderNo, String skuCode, String locationCode) { ... }
}
```

---

### 3.2 出库模块

**波次生成逻辑**：

```java
@Service
public class WaveService {
    // 生成波次
    public Wave generateWave(List<OutboundOrder> orders) {
        Wave wave = new Wave();
        wave.setWaveNo("WAVE" + System.currentTimeMillis());

        // 合并订单，生成拣货任务
        Map<String, Integer> skuQtyMap = new HashMap<>();
        for (OutboundOrder order : orders) {
            for (OutboundOrderDetail detail : order.getDetails()) {
                String skuCode = detail.getSkuCode();
                int qty = detail.getOrderQty();
                skuQtyMap.put(skuCode, skuQtyMap.getOrDefault(skuCode, 0) + qty);
            }
        }

        // 创建拣货任务
        for (Map.Entry<String, Integer> entry : skuQtyMap.entrySet()) {
            PickTask task = new PickTask();
            task.setSkuCode(entry.getKey());
            task.setPickQty(entry.getValue());
            wave.addTask(task);
        }

        return wave;
    }
}
```

---

### 3.3 库存模块

**库存扣减（并发安全）**：

```java
@Service
public class InventoryService {
    @Autowired
    private InventoryRepository inventoryRepo;

    @Transactional
    public boolean lockInventory(String skuCode, int qty) {
        // 悲观锁
        Inventory inventory = inventoryRepo.findBySkuCodeForUpdate(skuCode);

        if (inventory.getAvailableQty() < qty) {
            return false;  // 库存不足
        }

        // 扣减可用库存，增加锁定库存
        inventory.setAvailableQty(inventory.getAvailableQty() - qty);
        inventory.setLockedQty(inventory.getLockedQty() + qty);
        inventoryRepo.save(inventory);

        return true;
    }
}
```

---

## 4. 数据库设计

### 4.1 核心表结构

**已在第2篇文章中详细讲解，这里列出核心表**：

1. `warehouse` - 仓库表
2. `zone` - 库区表
3. `location` - 库位表
4. `sku` - 商品表
5. `inventory` - 库存表
6. `inbound_order` - 入库单主表
7. `inbound_order_detail` - 入库单明细表
8. `outbound_order` - 出库单主表
9. `outbound_order_detail` - 出库单明细表
10. `inventory_log` - 库存操作日志表

---

### 4.2 索引优化

```sql
-- 库存表索引
CREATE INDEX idx_inventory_sku ON inventory(sku_code);
CREATE INDEX idx_inventory_location ON inventory(location_code);
CREATE INDEX idx_inventory_batch ON inventory(batch_no);

-- 出库单明细表索引
CREATE INDEX idx_outbound_detail_order ON outbound_order_detail(order_no);
CREATE INDEX idx_outbound_detail_sku ON outbound_order_detail(sku_code);
```

---

### 4.3 分库分表策略

**分表场景**：
- 订单表：按月分表（`outbound_order_202511`、`outbound_order_202512`）
- 日志表：按月分表

**分库场景**：
- 按仓库分库（`wms_sh`、`wms_bj`）

---

## 5. 接口设计

### 5.1 RESTful API设计

**入库接口**：

```java
@RestController
@RequestMapping("/api/wms/inbound")
public class InboundController {
    // 创建ASN
    @PostMapping("/asn")
    public Result createASN(@RequestBody InboundOrder order) { ... }

    // 收货
    @PostMapping("/receive")
    public Result receive(@RequestBody ReceiveRequest request) { ... }

    // 上架
    @PostMapping("/putaway")
    public Result putaway(@RequestBody PutawayRequest request) { ... }
}
```

**出库接口**：

```java
@RestController
@RequestMapping("/api/wms/outbound")
public class OutboundController {
    // 创建出库单
    @PostMapping("/order")
    public Result createOrder(@RequestBody OutboundOrder order) { ... }

    // 生成波次
    @PostMapping("/wave")
    public Result generateWave(@RequestBody List<String> orderNos) { ... }

    // 拣货
    @PostMapping("/pick")
    public Result pick(@RequestBody PickRequest request) { ... }
}
```

---

### 5.2 幂等性设计

**问题**：网络抖动导致接口重复调用

**解决方案**：
```java
@Service
public class InboundService {
    @Autowired
    private RedisTemplate redisTemplate;

    public void receive(String orderNo, String skuCode, int qty, String requestId) {
        // 幂等性校验
        String key = "receive:" + requestId;
        if (redisTemplate.hasKey(key)) {
            throw new BusinessException("重复请求");
        }

        // 执行业务逻辑
        doReceive(orderNo, skuCode, qty);

        // 记录请求ID（过期时间24小时）
        redisTemplate.opsForValue().set(key, "1", 24, TimeUnit.HOURS);
    }
}
```

---

### 5.3 重试机制

**场景**：调用ERP接口失败

**解决方案**：
```java
@Service
public class ERPIntegrationService {
    private static final int MAX_RETRY = 3;

    public void syncInventory(Inventory inventory) {
        int retryCount = 0;
        while (retryCount < MAX_RETRY) {
            try {
                // 调用ERP API
                erpClient.updateInventory(inventory);
                return;
            } catch (Exception e) {
                retryCount++;
                if (retryCount >= MAX_RETRY) {
                    // 记录失败日志，人工处理
                    log.error("同步ERP失败", e);
                    throw e;
                }
                // 指数退避
                Thread.sleep((long) Math.pow(2, retryCount) * 1000);
            }
        }
    }
}
```

---

## 6. 性能优化

### 6.1 高并发场景

**问题**：双11大促，订单并发量10000单/秒

**优化方案**：

**1. 库存扣减优化**
```java
// 使用Redis计数器
public boolean lockInventory(String skuCode, int qty) {
    String key = "inventory:" + skuCode;
    Long available = redisTemplate.opsForValue().decrement(key, qty);

    if (available < 0) {
        // 回滚
        redisTemplate.opsForValue().increment(key, qty);
        return false;  // 库存不足
    }

    // 异步更新数据库
    asyncUpdateDB(skuCode, qty);
    return true;
}
```

**2. 数据库连接池优化**
```yaml
spring:
  datasource:
    hikari:
      maximum-pool-size: 50
      minimum-idle: 10
      connection-timeout: 30000
```

**3. 缓存策略**
```java
@Cacheable(value = "inventory", key = "#skuCode")
public Inventory getInventory(String skuCode) {
    return inventoryRepo.findBySkuCode(skuCode);
}
```

---

## 7. 总结

**WMS架构设计要点**：
1. **技术选型**：Java + Spring Boot + MySQL + Redis
2. **架构模式**：分层架构 / 微服务架构
3. **核心模块**：入库、出库、库存、波次
4. **性能优化**：Redis缓存、异步处理、连接池

**下一篇预告**：WMS生产实践与故障排查

---

**版权声明**：本文为原创文章，转载请注明出处。
