---
title: "库存预占与释放——防止超卖的核心机制"
date: 2026-01-29T17:40:00+08:00
draft: false
tags: ["OMS", "库存预占", "超卖", "并发控制", "跨境电商"]
categories: ["数字化转型"]
description: "超卖是电商系统的大忌。本文详解库存预占与释放的核心机制，包括库存模型、预占流程、并发控制、超卖处理，帮你构建防超卖的库存系统。"
series: ["跨境电商数字化转型指南"]
weight: 16
---

## 引言：超卖的代价

**超卖**：卖出的数量超过实际库存，导致无法发货。

**超卖的后果**：
- 客户投诉、差评
- 平台处罚（Amazon可能封店）
- 紧急采购成本高
- 品牌信誉受损

**防止超卖的核心：库存预占机制。**

---

## 一、库存模型设计

### 1.1 库存类型

```
┌─────────────────────────────────────────────────────┐
│                    库存类型                          │
├─────────────────────────────────────────────────────┤
│  实物库存 = WMS系统中的实际库存数量                   │
│                                                     │
│  可售库存 = 实物库存 - 预占库存 - 锁定库存            │
│                                                     │
│  预占库存 = 订单已预占但未发货的库存                  │
│                                                     │
│  锁定库存 = 因其他原因锁定的库存（盘点、质量问题等）   │
│                                                     │
│  在途库存 = 采购已下单但未入库的库存                  │
└─────────────────────────────────────────────────────┘
```

### 1.2 库存计算公式

```
可售库存 = 实物库存 - 预占库存 - 锁定库存

其中：
- 实物库存：从WMS同步
- 预占库存：OMS计算（订单预占）
- 锁定库存：手动锁定或系统锁定
```

### 1.3 数据模型

```sql
-- SKU库存汇总表（OMS）
CREATE TABLE t_sku_inventory (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    sku_id VARCHAR(32) NOT NULL COMMENT 'SKU编码',
    warehouse_id VARCHAR(32) NOT NULL COMMENT '仓库ID',

    physical_qty INT NOT NULL DEFAULT 0 COMMENT '实物库存（从WMS同步）',
    reserved_qty INT NOT NULL DEFAULT 0 COMMENT '预占库存',
    locked_qty INT NOT NULL DEFAULT 0 COMMENT '锁定库存',
    available_qty INT NOT NULL DEFAULT 0 COMMENT '可售库存（计算字段）',

    in_transit_qty INT NOT NULL DEFAULT 0 COMMENT '在途库存',

    version INT NOT NULL DEFAULT 0 COMMENT '乐观锁版本',
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY uk_sku_warehouse (sku_id, warehouse_id),
    KEY idx_sku_id (sku_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='SKU库存汇总表';

-- 库存预占明细表
CREATE TABLE t_inventory_reservation (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    reservation_id VARCHAR(32) NOT NULL COMMENT '预占ID',
    order_id VARCHAR(32) NOT NULL COMMENT '订单号',
    sku_id VARCHAR(32) NOT NULL COMMENT 'SKU编码',
    warehouse_id VARCHAR(32) NOT NULL COMMENT '仓库ID',

    reserved_qty INT NOT NULL COMMENT '预占数量',
    status VARCHAR(16) NOT NULL DEFAULT 'RESERVED' COMMENT '状态：RESERVED/RELEASED/DEDUCTED',

    reserved_at DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '预占时间',
    released_at DATETIME COMMENT '释放时间',

    UNIQUE KEY uk_reservation_id (reservation_id),
    KEY idx_order_id (order_id),
    KEY idx_sku_warehouse (sku_id, warehouse_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='库存预占明细表';
```

---

## 二、预占流程设计

### 2.1 预占时机

```
下单 ──> 支付 ──> 审核 ──> 拆单 ──> 下发WMS ──> 发货
  │                                    │
  └──────── 预占库存 ─────────────────>│
                                       │
                                  扣减库存
```

**两种预占策略**：

| 策略 | 预占时机 | 优点 | 缺点 |
|-----|---------|-----|-----|
| 下单预占 | 创建订单时 | 防止超卖更彻底 | 未支付订单占用库存 |
| 支付预占 | 支付成功后 | 库存利用率高 | 支付时可能库存不足 |

**推荐：支付成功后预占**（跨境电商通常是先付款后发货）

### 2.2 预占流程

```java
@Service
@Slf4j
public class InventoryReservationService {

    @Autowired
    private SkuInventoryRepository inventoryRepository;

    @Autowired
    private InventoryReservationRepository reservationRepository;

    /**
     * 预占库存
     * @return 预占是否成功
     */
    @Transactional
    public boolean reserve(String orderId, List<ReserveItem> items) {
        List<InventoryReservation> reservations = new ArrayList<>();

        for (ReserveItem item : items) {
            // 1. 获取库存记录（加锁）
            SkuInventory inventory = inventoryRepository.findBySkuAndWarehouseForUpdate(
                item.getSkuId(), item.getWarehouseId());

            if (inventory == null) {
                log.warn("库存记录不存在: skuId={}, warehouseId={}",
                    item.getSkuId(), item.getWarehouseId());
                throw new InventoryNotFoundException(item.getSkuId());
            }

            // 2. 检查可售库存
            if (inventory.getAvailableQty() < item.getQuantity()) {
                log.warn("库存不足: skuId={}, available={}, required={}",
                    item.getSkuId(), inventory.getAvailableQty(), item.getQuantity());
                throw new InsufficientInventoryException(item.getSkuId(),
                    inventory.getAvailableQty(), item.getQuantity());
            }

            // 3. 扣减可售库存，增加预占库存
            inventory.setAvailableQty(inventory.getAvailableQty() - item.getQuantity());
            inventory.setReservedQty(inventory.getReservedQty() + item.getQuantity());
            inventoryRepository.save(inventory);

            // 4. 记录预占明细
            InventoryReservation reservation = new InventoryReservation();
            reservation.setReservationId(generateReservationId());
            reservation.setOrderId(orderId);
            reservation.setSkuId(item.getSkuId());
            reservation.setWarehouseId(item.getWarehouseId());
            reservation.setReservedQty(item.getQuantity());
            reservation.setStatus("RESERVED");
            reservations.add(reservation);
        }

        reservationRepository.saveAll(reservations);
        log.info("库存预占成功: orderId={}, items={}", orderId, items.size());
        return true;
    }
}
```

### 2.3 释放流程

**释放场景**：
- 订单取消
- 订单超时未支付
- 订单审核不通过

```java
/**
 * 释放库存
 */
@Transactional
public void release(String orderId) {
    // 1. 查询预占记录
    List<InventoryReservation> reservations = reservationRepository
        .findByOrderIdAndStatus(orderId, "RESERVED");

    if (reservations.isEmpty()) {
        log.warn("无预占记录: orderId={}", orderId);
        return;
    }

    for (InventoryReservation reservation : reservations) {
        // 2. 恢复库存
        SkuInventory inventory = inventoryRepository.findBySkuAndWarehouseForUpdate(
            reservation.getSkuId(), reservation.getWarehouseId());

        inventory.setAvailableQty(inventory.getAvailableQty() + reservation.getReservedQty());
        inventory.setReservedQty(inventory.getReservedQty() - reservation.getReservedQty());
        inventoryRepository.save(inventory);

        // 3. 更新预占状态
        reservation.setStatus("RELEASED");
        reservation.setReleasedAt(LocalDateTime.now());
    }

    reservationRepository.saveAll(reservations);
    log.info("库存释放成功: orderId={}, count={}", orderId, reservations.size());
}
```

### 2.4 扣减流程

**扣减时机**：WMS确认发货后

```java
/**
 * 扣减库存（发货后）
 */
@Transactional
public void deduct(String orderId) {
    List<InventoryReservation> reservations = reservationRepository
        .findByOrderIdAndStatus(orderId, "RESERVED");

    for (InventoryReservation reservation : reservations) {
        // 1. 扣减预占库存和实物库存
        SkuInventory inventory = inventoryRepository.findBySkuAndWarehouseForUpdate(
            reservation.getSkuId(), reservation.getWarehouseId());

        inventory.setReservedQty(inventory.getReservedQty() - reservation.getReservedQty());
        inventory.setPhysicalQty(inventory.getPhysicalQty() - reservation.getReservedQty());
        inventoryRepository.save(inventory);

        // 2. 更新预占状态
        reservation.setStatus("DEDUCTED");
    }

    reservationRepository.saveAll(reservations);
    log.info("库存扣减成功: orderId={}", orderId);
}
```

---

## 三、并发控制

### 3.1 并发问题

**场景**：同一SKU库存只剩1件，两个订单同时预占

```
时间线：
T1: 订单A读取库存 = 1
T2: 订单B读取库存 = 1
T3: 订单A预占成功，库存 = 0
T4: 订单B预占成功，库存 = -1  ← 超卖！
```

### 3.2 解决方案

**方案1：数据库行锁（SELECT FOR UPDATE）**

```java
@Query("SELECT i FROM SkuInventory i WHERE i.skuId = :skuId AND i.warehouseId = :warehouseId")
@Lock(LockModeType.PESSIMISTIC_WRITE)
SkuInventory findBySkuAndWarehouseForUpdate(String skuId, String warehouseId);
```

优点：简单可靠
缺点：并发性能差

**方案2：乐观锁（版本号）**

```java
@Transactional
public boolean reserveWithOptimisticLock(String skuId, String warehouseId, int quantity) {
    int maxRetry = 3;
    for (int i = 0; i < maxRetry; i++) {
        SkuInventory inventory = inventoryRepository.findBySkuAndWarehouse(skuId, warehouseId);

        if (inventory.getAvailableQty() < quantity) {
            throw new InsufficientInventoryException(skuId);
        }

        // 使用版本号更新
        int updated = inventoryRepository.updateWithVersion(
            skuId, warehouseId,
            inventory.getAvailableQty() - quantity,
            inventory.getReservedQty() + quantity,
            inventory.getVersion()
        );

        if (updated > 0) {
            return true; // 更新成功
        }
        // 版本冲突，重试
    }
    throw new ConcurrentModificationException("库存更新冲突");
}

// Repository方法
@Modifying
@Query("UPDATE SkuInventory SET availableQty = :availableQty, reservedQty = :reservedQty, " +
       "version = version + 1 WHERE skuId = :skuId AND warehouseId = :warehouseId AND version = :version")
int updateWithVersion(String skuId, String warehouseId, int availableQty, int reservedQty, int version);
```

优点：并发性能好
缺点：需要重试机制

**方案3：Redis + Lua脚本（推荐）**

```java
@Service
public class RedisInventoryService {

    @Autowired
    private StringRedisTemplate redisTemplate;

    private static final String RESERVE_SCRIPT = """
        local key = KEYS[1]
        local quantity = tonumber(ARGV[1])
        local current = tonumber(redis.call('get', key) or 0)
        if current >= quantity then
            redis.call('decrby', key, quantity)
            return 1
        else
            return 0
        end
        """;

    /**
     * Redis预占库存
     */
    public boolean reserve(String skuId, String warehouseId, int quantity) {
        String key = "inventory:" + warehouseId + ":" + skuId;

        Long result = redisTemplate.execute(
            new DefaultRedisScript<>(RESERVE_SCRIPT, Long.class),
            List.of(key),
            String.valueOf(quantity)
        );

        return result != null && result == 1;
    }

    /**
     * Redis释放库存
     */
    public void release(String skuId, String warehouseId, int quantity) {
        String key = "inventory:" + warehouseId + ":" + skuId;
        redisTemplate.opsForValue().increment(key, quantity);
    }
}
```

优点：性能极高、原子性保证
缺点：需要保证Redis与数据库一致

### 3.3 推荐方案：Redis预占 + 数据库异步同步

```
┌─────────────────────────────────────────────────────┐
│                    预占流程                          │
├─────────────────────────────────────────────────────┤
│  1. Redis预占（Lua脚本，原子操作）                   │
│  2. 预占成功 → 发送MQ消息                           │
│  3. 消费者异步更新数据库                             │
└─────────────────────────────────────────────────────┘
```

```java
@Service
public class InventoryService {

    @Autowired
    private RedisInventoryService redisInventoryService;

    @Autowired
    private RocketMQTemplate rocketMQTemplate;

    /**
     * 预占库存（高并发场景）
     */
    public boolean reserve(String orderId, String skuId, String warehouseId, int quantity) {
        // 1. Redis预占
        boolean success = redisInventoryService.reserve(skuId, warehouseId, quantity);

        if (!success) {
            return false;
        }

        // 2. 发送异步消息，更新数据库
        InventoryReserveEvent event = new InventoryReserveEvent();
        event.setOrderId(orderId);
        event.setSkuId(skuId);
        event.setWarehouseId(warehouseId);
        event.setQuantity(quantity);
        event.setAction("RESERVE");

        rocketMQTemplate.asyncSend("inventory-reserve", event, new SendCallback() {
            @Override
            public void onSuccess(SendResult sendResult) {
                log.info("预占消息发送成功: orderId={}", orderId);
            }

            @Override
            public void onException(Throwable e) {
                log.error("预占消息发送失败，回滚Redis: orderId={}", orderId, e);
                redisInventoryService.release(skuId, warehouseId, quantity);
            }
        });

        return true;
    }
}
```

---

## 四、超卖处理

### 4.1 超卖预警

```java
@Service
public class InventoryAlertService {

    /**
     * 库存预警检查
     */
    @Scheduled(fixedRate = 60000) // 每分钟检查
    public void checkInventoryAlert() {
        // 检查可售库存为负的SKU
        List<SkuInventory> negativeInventories = inventoryRepository.findByAvailableQtyLessThan(0);

        for (SkuInventory inv : negativeInventories) {
            log.error("发现超卖: skuId={}, warehouseId={}, availableQty={}",
                inv.getSkuId(), inv.getWarehouseId(), inv.getAvailableQty());

            // 发送告警
            alertService.sendUrgent("超卖告警",
                String.format("SKU %s 在仓库 %s 超卖，可售库存=%d",
                    inv.getSkuId(), inv.getWarehouseId(), inv.getAvailableQty()));
        }

        // 检查低库存SKU
        List<SkuInventory> lowInventories = inventoryRepository.findLowStock(10);
        for (SkuInventory inv : lowInventories) {
            alertService.send("低库存预警",
                String.format("SKU %s 库存不足，当前=%d", inv.getSkuId(), inv.getAvailableQty()));
        }
    }
}
```

### 4.2 超卖订单处理

```java
@Service
public class OversoldOrderHandler {

    /**
     * 处理超卖订单
     */
    public void handleOversoldOrder(String orderId) {
        Order order = orderRepository.findByOrderId(orderId);

        // 1. 标记订单为超卖
        order.setOversold(true);
        order.setStatus(OrderStatus.PENDING_STOCK);
        orderRepository.save(order);

        // 2. 通知采购紧急补货
        purchaseService.createUrgentPurchase(order);

        // 3. 通知客服
        customerServiceNotifier.notifyOversold(order);

        // 4. 如果无法补货，考虑取消订单
        // ...
    }
}
```

---

## 五、库存同步

### 5.1 WMS库存同步到OMS

```java
@Component
@RocketMQMessageListener(topic = "wms-inventory-sync", consumerGroup = "oms-inventory-consumer")
public class WmsInventorySyncConsumer implements RocketMQListener<WmsInventoryEvent> {

    @Override
    public void onMessage(WmsInventoryEvent event) {
        String skuId = event.getSkuId();
        String warehouseId = event.getWarehouseId();
        int wmsQty = event.getQuantity();

        // 更新OMS实物库存
        SkuInventory inventory = inventoryRepository.findBySkuAndWarehouse(skuId, warehouseId);
        if (inventory == null) {
            inventory = new SkuInventory();
            inventory.setSkuId(skuId);
            inventory.setWarehouseId(warehouseId);
        }

        int oldPhysicalQty = inventory.getPhysicalQty();
        inventory.setPhysicalQty(wmsQty);

        // 重新计算可售库存
        int availableQty = wmsQty - inventory.getReservedQty() - inventory.getLockedQty();
        inventory.setAvailableQty(availableQty);

        inventoryRepository.save(inventory);

        // 同步到Redis
        redisInventoryService.set(skuId, warehouseId, availableQty);

        log.info("库存同步完成: skuId={}, warehouseId={}, physical: {} -> {}, available={}",
            skuId, warehouseId, oldPhysicalQty, wmsQty, availableQty);
    }
}
```

---

## 六、总结

### 6.1 核心要点

1. **库存模型**：实物库存、可售库存、预占库存、锁定库存
2. **预占时机**：支付成功后预占
3. **并发控制**：Redis + Lua脚本保证原子性
4. **超卖处理**：预警机制 + 紧急补货
5. **库存同步**：WMS实时同步到OMS

### 6.2 防超卖检查清单

- [ ] 预占使用原子操作（Redis Lua或数据库锁）
- [ ] 预占失败要正确处理
- [ ] 订单取消要释放库存
- [ ] 发货后要扣减库存
- [ ] 建立库存预警机制
- [ ] 定期对账WMS和OMS库存

---

> **系列文章导航**
>
> 本文是《跨境电商数字化转型指南》系列的第16篇
>
> - [x] 13-15. OMS前序文章
> - [x] 16. 库存预占与释放（本文）
> - [ ] 17. 履约路由与调度
