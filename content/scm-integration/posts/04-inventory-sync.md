---
title: "库存数据实时同步：从最终一致性到强一致性"
date: 2025-11-22T18:00:00+08:00
draft: false
tags: ["库存同步", "数据一致性", "CDC", "消息队列"]
categories: ["供应链系统"]
description: "详细讲解库存数据在多系统间的同步方案。从主动推送到CDC捕获，从最终一致性到强一致性，全面掌握库存同步的核心技术。"
weight: 4
---

## 引言

库存数据是供应链的核心数据，需要在多个系统间实时同步。本文将探讨库存同步的技术方案和一致性保障。

---

## 1. 库存同步场景

### 1.1 OMS查询库存

```java
@Service
public class InventoryQueryService {

    @Autowired
    private InventoryCenterClient inventoryCenterClient;

    @Cacheable(value = "inventory", key = "#sku + ':' + #warehouseCode")
    public int queryStock(String sku, String warehouseCode) {
        return inventoryCenterClient.queryAvailableQty(sku, warehouseCode);
    }
}
```

### 1.2 WMS更新库存

```
入库 → 增加库存 → 推送到库存中心
出库 → 减少库存 → 推送到库存中心
盘点 → 调整库存 → 推送到库存中心
```

### 1.3 库存预占

```
OMS下单 → 预占库存
WMS出库 → 扣减库存
订单取消 → 释放库存
```

---

## 2. 同步技术方案

### 2.1 主动推送

**流程**：
```
WMS库存变化 → 发送MQ消息 → 库存中心消费更新
```

**优点**：
- 实时性高
- 数据准确

**缺点**：
- WMS需改造
- 增加耦合

**实现**：
```java
@Service
public class InventoryPushService {

    @Autowired
    private RocketMQTemplate mqTemplate;

    public void pushInventoryChange(InventoryTransaction transaction) {
        InventoryChangeMessage msg = new InventoryChangeMessage();
        msg.setSku(transaction.getSku());
        msg.setWarehouseCode(transaction.getWarehouseCode());
        msg.setQuantity(transaction.getQuantity());
        msg.setType(transaction.getType());

        mqTemplate.convertAndSend("inventory-topic:change", msg);
    }
}
```

### 2.2 被动拉取

**流程**：
```
库存中心定时拉取WMS库存 → 对比差异 → 更新
```

**优点**：
- WMS无改造
- 实现简单

**缺点**：
- 实时性差
- 轮询消耗资源

### 2.3 CDC（变更数据捕获）

**流程**：
```
Canal监听WMS数据库binlog → 推送到Kafka → 库存中心消费
```

**优点**：
- 无侵入
- 实时性高

**缺点**：
- 依赖binlog
- 配置复杂

**实现**：
```java
@Component
public class CanalConsumer {

    @KafkaListener(topics = "canal-inventory", groupId = "inventory-center")
    public void onMessage(ConsumerRecord<String, String> record) {
        String json = record.value();
        CanalMessage msg = JSON.parseObject(json, CanalMessage.class);

        if ("inventory".equals(msg.getTable())) {
            // 解析库存变更
            InventoryDTO inventory = parseInventory(msg.getData());

            // 更新库存中心
            inventoryService.syncFromWMS(inventory);
        }
    }
}
```

---

## 3. 一致性保障

### 3.1 最终一致性

**特点**：
- 允许短暂不一致
- 通过补偿机制最终一致

**实现**：
```java
@Component
public class InventoryReconciliationTask {

    @Scheduled(cron = "0 0 3 * * ?")  // 每天凌晨3点
    public void reconcile() {
        // 1. 从WMS全量拉取库存
        List<Inventory> wmsInventories = wmsService.getAllInventories();

        // 2. 对比库存中心数据
        for (Inventory wmsInv : wmsInventories) {
            Inventory centerInv = inventoryService.get(
                wmsInv.getSku(),
                wmsInv.getWarehouseCode()
            );

            if (!centerInv.equals(wmsInv)) {
                // 3. 差异修正
                inventoryService.syncFromWMS(wmsInv);

                log.warn("库存差异已修正: sku={}, wms={}, center={}",
                    wmsInv.getSku(), wmsInv.getAvailableQty(),
                    centerInv.getAvailableQty());
            }
        }
    }
}
```

### 3.2 强一致性

**分布式事务（Seata）**：
```java
@GlobalTransactional
public void createOrderAndReserveStock(Order order) {
    // 1. OMS创建订单
    orderService.create(order);

    // 2. 库存中心预占库存
    inventoryService.reserve(order.getSku(), order.getQuantity());
}
```

---

## 4. 性能优化

### 4.1 批量同步

```java
@Component
public class BatchSyncProcessor {

    private List<InventoryChangeMessage> buffer = new ArrayList<>();
    private final int BATCH_SIZE = 100;
    private final long BATCH_INTERVAL = 10000;  // 10秒

    public synchronized void add(InventoryChangeMessage msg) {
        buffer.add(msg);

        if (buffer.size() >= BATCH_SIZE) {
            flush();
        }
    }

    @Scheduled(fixedRate = 10000)
    public void flush() {
        if (buffer.isEmpty()) return;

        List<InventoryChangeMessage> toSync = new ArrayList<>(buffer);
        buffer.clear();

        // 批量同步
        inventoryService.batchSync(toSync);
    }
}
```

### 4.2 增量同步

```java
public void incrementalSync() {
    // 只同步变化的库存
    LocalDateTime lastSyncTime = getLastSyncTime();
    List<Inventory> changed = wmsService.getChangedSince(lastSyncTime);

    inventoryService.batchUpdate(changed);
}
```

---

## 5. 实战案例：淘宝的库存同步

**技术方案**：
- Canal CDC
- RocketMQ消息队列
- 实时同步+定时对账

**成果**：
- 同步延迟：<100ms
- 准确率：99.99%
- 日同步量：10亿+

---

## 6. 总结

库存同步是供应链集成的核心，需要平衡实时性和一致性。

**核心要点**：

1. **同步方案**：主动推送、被动拉取、CDC
2. **一致性**：最终一致性、强一致性
3. **性能优化**：批量同步、增量同步

下一篇将探讨分布式事务处理，敬请期待！
