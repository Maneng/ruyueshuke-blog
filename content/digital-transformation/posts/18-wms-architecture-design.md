---
title: "WMS仓储系统自研实战——架构设计与核心流程"
date: 2026-01-29T16:10:00+08:00
draft: false
tags: ["WMS", "仓储系统", "系统设计", "自研", "跨境电商"]
categories: ["数字化转型"]
description: "WMS是跨境电商仓储管理的核心系统，本文详解WMS的架构设计、库位管理、入库出库流程、拣货策略，帮你从0到1自研一套WMS仓储系统。"
series: ["跨境电商数字化转型指南"]
weight: 18
---

## 引言：WMS的重要性

**WMS（Warehouse Management System）是仓储执行的大脑**：

- 管理仓库内所有实物操作
- 直接影响发货效率和库存准确率
- 是OMS订单履约的执行者

**一个好的WMS系统，可以让仓库效率提升50%以上，库存准确率达到99.9%。**

---

## 一、WMS系统定位

### 1.1 WMS在系统矩阵中的位置

```
                    OMS
                     │
                     │ 出库指令
                     ▼
┌─────────────────────────────────────────────────────┐
│                     WMS                              │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐   │
│  │入库管理 │ │库位管理 │ │出库管理 │ │库存管理 │   │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘   │
└───────────────────────┬─────────────────────────────┘
                        │
                        │ 发货交接
                        ▼
                      TMS
```

### 1.2 WMS的核心职责

| 职责 | 说明 |
|-----|-----|
| 入库管理 | 收货、质检、上架 |
| 库位管理 | 库位分配、库存查询 |
| 出库管理 | 波次、拣货、复核、发货 |
| 库存管理 | 盘点、调拨、冻结 |
| 设备对接 | PDA、打印机、电子秤 |

### 1.3 WMS与OMS的边界

| 功能 | OMS | WMS |
|-----|-----|-----|
| 可售库存 | ✓ | |
| 实物库存 | | ✓ |
| 库位库存 | | ✓ |
| 订单拆分 | ✓ | |
| 波次生成 | | ✓ |
| 拣货执行 | | ✓ |

---

## 二、架构设计

### 2.1 整体架构

```
┌─────────────────────────────────────────────────────┐
│                    接入层                            │
│      OMS接口 │ ERP接口 │ PDA接口 │ 打印接口         │
└─────────────────────┬───────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────┐
│                   服务层                             │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐            │
│  │ 入库服务 │ │ 出库服务 │ │ 库存服务 │            │
│  └──────────┘ └──────────┘ └──────────┘            │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐            │
│  │ 库位服务 │ │ 波次服务 │ │ 策略引擎 │            │
│  └──────────┘ └──────────┘ └──────────┘            │
└─────────────────────┬───────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────┐
│                   数据层                             │
│        MySQL │ Redis │ RocketMQ                     │
└─────────────────────────────────────────────────────┘
```

### 2.2 核心服务说明

**入库服务**：
- ASN预约管理
- 到货登记
- 质检管理
- 上架任务

**出库服务**：
- 出库单管理
- 波次生成
- 拣货任务
- 复核发货

**库存服务**：
- 库存查询
- 库存变动
- 库存流水
- 盘点管理

**库位服务**：
- 库位管理
- 库位分配
- 库位推荐

**策略引擎**：
- 上架策略
- 拣货策略
- 波次策略

---

## 三、库位管理

### 3.1 库位体系设计

```
仓库（Warehouse）
  └── 库区（Zone）
        └── 巷道（Aisle）
              └── 货架（Rack）
                    └── 层（Level）
                          └── 库位（Location）
```

**库位编码规则**：
```
A-01-02-03-04
│  │  │  │  │
│  │  │  │  └── 列号（04）
│  │  │  └───── 层号（03）
│  │  └──────── 货架号（02）
│  └─────────── 巷道号（01）
└────────────── 库区（A）
```

### 3.2 库位类型

| 类型 | 说明 | 用途 |
|-----|-----|-----|
| 存储位 | 常规存储库位 | 存放商品 |
| 拣货位 | 拣货区库位 | 快速拣货 |
| 暂存位 | 临时存放 | 收货、发货暂存 |
| 不良品位 | 存放不良品 | 质检不合格品 |
| 退货位 | 存放退货 | 退货处理 |

### 3.3 库位表设计

```sql
CREATE TABLE t_location (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    location_code VARCHAR(32) NOT NULL COMMENT '库位编码',
    warehouse_id VARCHAR(32) NOT NULL COMMENT '仓库ID',

    zone_code VARCHAR(8) COMMENT '库区',
    aisle_code VARCHAR(8) COMMENT '巷道',
    rack_code VARCHAR(8) COMMENT '货架',
    level_code VARCHAR(8) COMMENT '层',
    column_code VARCHAR(8) COMMENT '列',

    location_type VARCHAR(16) NOT NULL COMMENT '库位类型',
    status VARCHAR(16) NOT NULL DEFAULT 'EMPTY' COMMENT '状态',

    max_weight DECIMAL(10,2) COMMENT '最大承重(kg)',
    max_volume DECIMAL(10,2) COMMENT '最大体积(m³)',

    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,

    UNIQUE KEY uk_location_code (warehouse_id, location_code),
    KEY idx_zone (warehouse_id, zone_code),
    KEY idx_type_status (location_type, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='库位表';
```

---

## 四、入库流程

### 4.1 入库流程图

```
ASN预约 ──> 到货登记 ──> 质检 ──> 收货确认 ──> 上架
   │           │         │          │          │
   │           │         │          │          │
   ▼           ▼         ▼          ▼          ▼
创建ASN    扫码登记   质检判定   生成入库单  分配库位
                        │
                        ├── 合格 ──> 正常上架
                        │
                        └── 不合格 ──> 不良品处理
```

### 4.2 ASN预约

**ASN（Advance Shipping Notice）= 预到货通知**

```java
public class ASN {
    private String asnNo;           // ASN单号
    private String warehouseId;     // 仓库ID
    private String supplierId;      // 供应商ID
    private String poNo;            // 采购单号

    private Date expectedDate;      // 预计到货日期
    private List<ASNItem> items;    // 预约明细

    private ASNStatus status;       // 状态
}

public class ASNItem {
    private String skuId;           // SKU编码
    private Integer expectedQty;    // 预约数量
    private Integer receivedQty;    // 已收数量
}
```

### 4.3 上架策略

**策略1：就近上架**
```java
@Component
public class NearestLocationStrategy implements PutawayStrategy {
    @Override
    public String recommendLocation(String skuId, String warehouseId) {
        // 找到该SKU已有库存的库位附近的空库位
        List<String> existingLocations = inventoryService.getLocations(skuId);
        return locationService.findNearestEmpty(existingLocations);
    }
}
```

**策略2：分区上架**
```java
@Component
public class ZoneBasedStrategy implements PutawayStrategy {
    @Override
    public String recommendLocation(String skuId, String warehouseId) {
        // 根据SKU属性（品类、周转率）分配到对应库区
        SKU sku = skuService.getSku(skuId);
        String zone = determineZone(sku);
        return locationService.findEmptyInZone(zone);
    }
}
```

**策略3：ABC分区**
```java
// A区：高周转商品，靠近出库口
// B区：中周转商品
// C区：低周转商品，远离出库口
```

---

## 五、出库流程

### 5.1 出库流程图

```
出库指令 ──> 波次生成 ──> 拣货任务 ──> 拣货执行 ──> 复核 ──> 打包 ──> 发货
    │           │           │           │          │       │       │
    │           │           │           │          │       │       │
    ▼           ▼           ▼           ▼          ▼       ▼       ▼
接收OMS    按规则分波   分配拣货员   PDA扫码    扫码核对  称重打包  交接物流
```

### 5.2 波次策略

**什么是波次？**
- 将多个出库单合并成一个批次处理
- 提高拣货效率，减少行走距离

**波次策略**：

| 策略 | 说明 | 适用场景 |
|-----|-----|---------|
| 按承运商 | 同一物流的订单一波 | 物流交接时间固定 |
| 按时效 | 同一时效要求的一波 | 有时效要求 |
| 按库区 | 同一库区的订单一波 | 仓库较大 |
| 按订单类型 | 单品单件、多品多件分开 | 提高效率 |

**波次生成实现**：

```java
@Service
public class WaveService {

    public Wave createWave(List<OutboundOrder> orders, WaveStrategy strategy) {
        Wave wave = new Wave();
        wave.setWaveNo(generateWaveNo());

        // 按策略分组
        Map<String, List<OutboundOrder>> groups = strategy.group(orders);

        // 生成拣货任务
        List<PickTask> pickTasks = new ArrayList<>();
        for (List<OutboundOrder> group : groups.values()) {
            PickTask task = createPickTask(group);
            pickTasks.add(task);
        }

        wave.setPickTasks(pickTasks);
        return wave;
    }
}
```

### 5.3 拣货策略

**拣货模式**：

| 模式 | 说明 | 效率 | 适用场景 |
|-----|-----|-----|---------|
| 单单拣货 | 一次拣一个订单 | 低 | 订单量小 |
| 批量拣货 | 一次拣多个订单，再分拣 | 高 | 订单量大 |
| 边拣边分 | 拣货同时分到订单 | 中 | 中等订单量 |

**路径优化**：

```java
@Service
public class PickPathOptimizer {

    /**
     * S型路径优化
     * 按巷道顺序，奇数巷道从前往后，偶数巷道从后往前
     */
    public List<PickItem> optimizePath(List<PickItem> items) {
        // 按库位排序
        items.sort((a, b) -> {
            int aisleCompare = a.getAisle().compareTo(b.getAisle());
            if (aisleCompare != 0) return aisleCompare;

            // 奇数巷道正序，偶数巷道倒序
            int aisle = Integer.parseInt(a.getAisle());
            if (aisle % 2 == 1) {
                return a.getLocation().compareTo(b.getLocation());
            } else {
                return b.getLocation().compareTo(a.getLocation());
            }
        });

        return items;
    }
}
```

### 5.4 复核流程

**复核方式**：

| 方式 | 说明 | 准确率 |
|-----|-----|-------|
| 扫码复核 | 扫描商品条码核对 | 99.9% |
| 称重复核 | 比对重量 | 99% |
| 拍照复核 | 拍照留证 | 95% |

**扫码复核实现**：

```java
@Service
public class CheckService {

    public CheckResult check(String orderNo, String scannedBarcode) {
        OutboundOrder order = orderRepository.findByOrderNo(orderNo);

        // 查找匹配的商品
        OrderItem matchedItem = order.getItems().stream()
            .filter(item -> item.getBarcode().equals(scannedBarcode))
            .findFirst()
            .orElse(null);

        if (matchedItem == null) {
            return CheckResult.error("商品不在订单中");
        }

        // 更新已复核数量
        matchedItem.setCheckedQty(matchedItem.getCheckedQty() + 1);

        // 检查是否超量
        if (matchedItem.getCheckedQty() > matchedItem.getQuantity()) {
            return CheckResult.error("复核数量超出");
        }

        // 检查是否完成
        boolean allChecked = order.getItems().stream()
            .allMatch(item -> item.getCheckedQty().equals(item.getQuantity()));

        if (allChecked) {
            order.setStatus(OrderStatus.CHECKED);
            return CheckResult.complete();
        }

        return CheckResult.success(matchedItem);
    }
}
```

---

## 六、库存管理

### 6.1 库存模型

```sql
-- 库位库存表
CREATE TABLE t_location_inventory (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    warehouse_id VARCHAR(32) NOT NULL,
    location_code VARCHAR(32) NOT NULL,
    sku_id VARCHAR(32) NOT NULL,

    quantity INT NOT NULL DEFAULT 0 COMMENT '库存数量',
    locked_qty INT NOT NULL DEFAULT 0 COMMENT '锁定数量',

    batch_no VARCHAR(32) COMMENT '批次号',
    production_date DATE COMMENT '生产日期',
    expiry_date DATE COMMENT '过期日期',

    version INT NOT NULL DEFAULT 0,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY uk_location_sku (warehouse_id, location_code, sku_id, batch_no),
    KEY idx_sku (sku_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='库位库存表';

-- 库存流水表
CREATE TABLE t_inventory_transaction (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    transaction_no VARCHAR(32) NOT NULL,
    warehouse_id VARCHAR(32) NOT NULL,
    sku_id VARCHAR(32) NOT NULL,

    transaction_type VARCHAR(16) NOT NULL COMMENT '类型：IN/OUT/ADJUST',
    quantity INT NOT NULL COMMENT '变动数量',
    before_qty INT NOT NULL COMMENT '变动前数量',
    after_qty INT NOT NULL COMMENT '变动后数量',

    source_type VARCHAR(32) COMMENT '来源类型',
    source_no VARCHAR(32) COMMENT '来源单号',

    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,

    KEY idx_sku (sku_id),
    KEY idx_source (source_type, source_no)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='库存流水表';
```

### 6.2 库存变动

```java
@Service
@Transactional
public class InventoryTransactionService {

    public void addInventory(String warehouseId, String locationCode,
                            String skuId, int quantity, String sourceType, String sourceNo) {
        // 1. 更新库位库存
        LocationInventory inventory = inventoryRepository
            .findByLocation(warehouseId, locationCode, skuId);

        if (inventory == null) {
            inventory = new LocationInventory();
            inventory.setWarehouseId(warehouseId);
            inventory.setLocationCode(locationCode);
            inventory.setSkuId(skuId);
            inventory.setQuantity(0);
        }

        int beforeQty = inventory.getQuantity();
        inventory.setQuantity(beforeQty + quantity);
        inventoryRepository.save(inventory);

        // 2. 记录流水
        InventoryTransaction transaction = new InventoryTransaction();
        transaction.setTransactionNo(generateTransactionNo());
        transaction.setWarehouseId(warehouseId);
        transaction.setSkuId(skuId);
        transaction.setTransactionType("IN");
        transaction.setQuantity(quantity);
        transaction.setBeforeQty(beforeQty);
        transaction.setAfterQty(beforeQty + quantity);
        transaction.setSourceType(sourceType);
        transaction.setSourceNo(sourceNo);
        transactionRepository.save(transaction);

        // 3. 同步OMS可售库存
        omsClient.syncInventory(warehouseId, skuId, inventory.getQuantity());
    }
}
```

### 6.3 盘点管理

**盘点类型**：

| 类型 | 说明 | 频率 |
|-----|-----|-----|
| 全盘 | 盘点所有库存 | 年度 |
| 循环盘点 | 按计划轮流盘点 | 每日 |
| 动碰盘点 | 有变动时盘点 | 实时 |
| 抽盘 | 随机抽查 | 每周 |

---

## 七、性能优化

### 7.1 高并发场景

**库存扣减优化**：
```java
// 使用乐观锁防止并发问题
@Update("UPDATE t_location_inventory " +
        "SET quantity = quantity - #{qty}, version = version + 1 " +
        "WHERE id = #{id} AND version = #{version} AND quantity >= #{qty}")
int deductInventory(@Param("id") Long id,
                   @Param("qty") int qty,
                   @Param("version") int version);
```

**批量操作优化**：
```java
// 批量插入，减少数据库交互
@Insert("<script>" +
        "INSERT INTO t_inventory_transaction (...) VALUES " +
        "<foreach collection='list' item='item' separator=','>" +
        "(#{item.transactionNo}, ...)" +
        "</foreach>" +
        "</script>")
int batchInsert(@Param("list") List<InventoryTransaction> list);
```

### 7.2 数据库优化

- 库存表按仓库分表
- 流水表按月分表
- 历史数据定期归档

---

## 八、总结

### 8.1 WMS核心要点

1. **库位管理**：建立清晰的库位体系，支持多种库位类型
2. **入库流程**：ASN预约→到货→质检→上架，每步可追溯
3. **出库流程**：波次→拣货→复核→发货，提高效率
4. **库存准确**：实时记录流水，支持多种盘点方式
5. **策略灵活**：上架策略、拣货策略可配置

### 8.2 下一步

- [ ] 完成WMS核心模块开发
- [ ] 对接PDA设备
- [ ] 与OMS系统集成
- [ ] 上线试运行

---

> **系列文章导航**
>
> 本文是《跨境电商数字化转型指南》系列的第18篇
>
> - [x] 01-17. 前序文章
> - [x] 18. WMS仓储系统自研实战（本文）
> - [ ] 19. 入库管理详解
> - [ ] 20. 拣货策略优化
