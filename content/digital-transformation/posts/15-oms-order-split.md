---
title: "订单拆分与合并策略——复杂场景的处理逻辑"
date: 2026-01-29T17:10:00+08:00
draft: false
tags: ["OMS", "订单拆分", "订单合并", "策略引擎", "跨境电商"]
categories: ["数字化转型"]
description: "跨境电商订单处理中，拆单和合单是最复杂的逻辑之一。本文详解多仓拆单、预售拆单、合单发货等场景的处理策略和代码实现。"
series: ["跨境电商数字化转型指南"]
weight: 15
---

## 引言：为什么需要拆单和合单

**拆单场景**：
- 一个订单的商品分布在不同仓库，需要从多个仓库发货
- 部分商品有货，部分商品需要预售
- 订单重量超过物流限制，需要拆成多个包裹

**合单场景**：
- 同一客户短时间内下了多个订单，可以合并发货节省运费
- 促销活动中的凑单场景

**这些逻辑看似简单，但实现起来非常复杂**，涉及库存、物流、财务等多个方面。

---

## 一、订单模型设计

### 1.1 三层订单模型

```
┌─────────────────────────────────────────────────────┐
│                   原始订单                           │
│              (Source Order)                         │
│         客户下单时的原始订单                          │
└─────────────────────┬───────────────────────────────┘
                      │ 拆分/合并
                      ▼
┌─────────────────────────────────────────────────────┐
│                   履约订单                           │
│            (Fulfillment Order)                      │
│         实际执行发货的订单单元                        │
└─────────────────────┬───────────────────────────────┘
                      │ 下发
                      ▼
┌─────────────────────────────────────────────────────┐
│                   出库单                             │
│             (Outbound Order)                        │
│           WMS执行的出库指令                          │
└─────────────────────────────────────────────────────┘
```

### 1.2 数据模型

```java
/**
 * 原始订单
 */
@Data
public class SourceOrder {
    private String sourceOrderId;     // 原始订单号
    private String channelOrderId;    // 渠道订单号
    private String channel;           // 渠道
    private String buyerId;           // 买家ID
    private Address shippingAddress;  // 收货地址
    private List<SourceOrderItem> items; // 订单明细
    private Money totalAmount;        // 订单总额
    private OrderStatus status;       // 状态
}

/**
 * 履约订单
 */
@Data
public class FulfillmentOrder {
    private String fulfillmentOrderId; // 履约订单号
    private String sourceOrderId;      // 关联原始订单号
    private String warehouseId;        // 发货仓库
    private String carrierId;          // 承运商
    private Address shippingAddress;   // 收货地址
    private List<FulfillmentOrderItem> items; // 履约明细
    private Money shippingFee;         // 运费
    private FulfillmentStatus status;  // 状态
}

/**
 * 订单关系表
 */
@Data
public class OrderRelation {
    private String sourceOrderId;       // 原始订单号
    private String fulfillmentOrderId;  // 履约订单号
    private String relationType;        // 关系类型：SPLIT/MERGE
}
```

### 1.3 数据库设计

```sql
-- 原始订单表
CREATE TABLE t_source_order (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    source_order_id VARCHAR(32) NOT NULL,
    channel_order_id VARCHAR(64),
    channel VARCHAR(32),
    buyer_id VARCHAR(64),
    total_amount DECIMAL(12,2),
    currency VARCHAR(8),
    status VARCHAR(32),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_source_order_id (source_order_id)
);

-- 履约订单表
CREATE TABLE t_fulfillment_order (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    fulfillment_order_id VARCHAR(32) NOT NULL,
    source_order_id VARCHAR(32) NOT NULL,
    warehouse_id VARCHAR(32),
    carrier_id VARCHAR(32),
    shipping_fee DECIMAL(12,2),
    status VARCHAR(32),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_fulfillment_order_id (fulfillment_order_id),
    KEY idx_source_order_id (source_order_id)
);

-- 订单关系表
CREATE TABLE t_order_relation (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    source_order_id VARCHAR(32) NOT NULL,
    fulfillment_order_id VARCHAR(32) NOT NULL,
    relation_type VARCHAR(16) NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    KEY idx_source_order_id (source_order_id),
    KEY idx_fulfillment_order_id (fulfillment_order_id)
);
```

---

## 二、拆单策略

### 2.1 拆单场景分类

| 场景 | 触发条件 | 处理方式 |
|-----|---------|---------|
| 多仓拆单 | 商品分布在不同仓库 | 按仓库拆分 |
| 预售拆单 | 部分商品无货 | 有货先发，无货等待 |
| 超重拆单 | 包裹超过物流限重 | 按重量拆分 |
| 赠品拆单 | 赠品从不同仓库发 | 赠品单独发货 |
| 组合商品拆单 | 组合商品需要拆开 | 拆成单品发货 |

### 2.2 多仓拆单

**场景**：订单包含SKU-A和SKU-B，SKU-A在深圳仓，SKU-B在义乌仓

```java
@Service
public class MultiWarehouseSplitStrategy implements SplitStrategy {

    @Autowired
    private InventoryService inventoryService;

    @Override
    public String getStrategyType() {
        return "MULTI_WAREHOUSE";
    }

    @Override
    public List<FulfillmentOrder> split(SourceOrder sourceOrder) {
        // 1. 获取每个SKU的库存分布
        Map<String, List<InventoryInfo>> skuInventoryMap = new HashMap<>();
        for (SourceOrderItem item : sourceOrder.getItems()) {
            List<InventoryInfo> inventories = inventoryService.getInventory(item.getSkuId());
            skuInventoryMap.put(item.getSkuId(), inventories);
        }

        // 2. 为每个SKU选择最优仓库
        Map<String, String> skuWarehouseMap = selectWarehouse(sourceOrder, skuInventoryMap);

        // 3. 按仓库分组
        Map<String, List<SourceOrderItem>> warehouseItemsMap = new HashMap<>();
        for (SourceOrderItem item : sourceOrder.getItems()) {
            String warehouseId = skuWarehouseMap.get(item.getSkuId());
            warehouseItemsMap.computeIfAbsent(warehouseId, k -> new ArrayList<>()).add(item);
        }

        // 4. 生成履约订单
        List<FulfillmentOrder> result = new ArrayList<>();
        int seq = 1;
        for (Map.Entry<String, List<SourceOrderItem>> entry : warehouseItemsMap.entrySet()) {
            FulfillmentOrder fo = new FulfillmentOrder();
            fo.setFulfillmentOrderId(sourceOrder.getSourceOrderId() + "-" + seq++);
            fo.setSourceOrderId(sourceOrder.getSourceOrderId());
            fo.setWarehouseId(entry.getKey());
            fo.setShippingAddress(sourceOrder.getShippingAddress());
            fo.setItems(convertItems(entry.getValue()));
            result.add(fo);
        }

        return result;
    }

    /**
     * 选择仓库策略：就近发货
     */
    private Map<String, String> selectWarehouse(SourceOrder order,
            Map<String, List<InventoryInfo>> skuInventoryMap) {
        Map<String, String> result = new HashMap<>();
        Address address = order.getShippingAddress();

        for (Map.Entry<String, List<InventoryInfo>> entry : skuInventoryMap.entrySet()) {
            String skuId = entry.getKey();
            List<InventoryInfo> inventories = entry.getValue();

            // 过滤有库存的仓库
            List<InventoryInfo> available = inventories.stream()
                .filter(inv -> inv.getAvailableQty() > 0)
                .collect(Collectors.toList());

            if (available.isEmpty()) {
                throw new InsufficientInventoryException(skuId);
            }

            // 选择最近的仓库
            String nearestWarehouse = available.stream()
                .min(Comparator.comparingDouble(inv ->
                    calculateDistance(inv.getWarehouseId(), address)))
                .map(InventoryInfo::getWarehouseId)
                .orElseThrow();

            result.put(skuId, nearestWarehouse);
        }

        return result;
    }
}
```

### 2.3 预售拆单

**场景**：订单包含SKU-A（有货）和SKU-B（无货，预计7天后到货）

```java
@Service
public class PreSaleSplitStrategy implements SplitStrategy {

    @Override
    public String getStrategyType() {
        return "PRE_SALE";
    }

    @Override
    public List<FulfillmentOrder> split(SourceOrder sourceOrder) {
        // 1. 区分有货和无货商品
        List<SourceOrderItem> inStockItems = new ArrayList<>();
        List<SourceOrderItem> outOfStockItems = new ArrayList<>();

        for (SourceOrderItem item : sourceOrder.getItems()) {
            int availableQty = inventoryService.getAvailableQty(item.getSkuId());
            if (availableQty >= item.getQuantity()) {
                inStockItems.add(item);
            } else {
                outOfStockItems.add(item);
            }
        }

        List<FulfillmentOrder> result = new ArrayList<>();

        // 2. 有货商品立即发货
        if (!inStockItems.isEmpty()) {
            FulfillmentOrder fo = createFulfillmentOrder(
                sourceOrder, inStockItems, "IN_STOCK");
            fo.setStatus(FulfillmentStatus.PENDING_FULFILL);
            result.add(fo);
        }

        // 3. 无货商品等待到货
        if (!outOfStockItems.isEmpty()) {
            FulfillmentOrder fo = createFulfillmentOrder(
                sourceOrder, outOfStockItems, "PRE_SALE");
            fo.setStatus(FulfillmentStatus.WAITING_STOCK);
            result.add(fo);
        }

        return result;
    }
}
```

### 2.4 超重拆单

**场景**：订单总重量5kg，物流限重2kg

```java
@Service
public class OverweightSplitStrategy implements SplitStrategy {

    private static final double MAX_WEIGHT = 2000; // 2kg = 2000g

    @Override
    public String getStrategyType() {
        return "OVERWEIGHT";
    }

    @Override
    public List<FulfillmentOrder> split(SourceOrder sourceOrder) {
        // 1. 计算每个商品的重量
        List<ItemWithWeight> itemsWithWeight = sourceOrder.getItems().stream()
            .map(item -> {
                double weight = skuService.getWeight(item.getSkuId()) * item.getQuantity();
                return new ItemWithWeight(item, weight);
            })
            .collect(Collectors.toList());

        // 2. 装箱算法（首次适应递减算法）
        List<List<SourceOrderItem>> packages = packItems(itemsWithWeight);

        // 3. 生成履约订单
        List<FulfillmentOrder> result = new ArrayList<>();
        int seq = 1;
        for (List<SourceOrderItem> packageItems : packages) {
            FulfillmentOrder fo = createFulfillmentOrder(
                sourceOrder, packageItems, "PKG-" + seq++);
            result.add(fo);
        }

        return result;
    }

    /**
     * 装箱算法：首次适应递减
     */
    private List<List<SourceOrderItem>> packItems(List<ItemWithWeight> items) {
        // 按重量降序排序
        items.sort((a, b) -> Double.compare(b.weight, a.weight));

        List<List<SourceOrderItem>> packages = new ArrayList<>();
        List<Double> packageWeights = new ArrayList<>();

        for (ItemWithWeight item : items) {
            boolean packed = false;

            // 尝试放入现有包裹
            for (int i = 0; i < packages.size(); i++) {
                if (packageWeights.get(i) + item.weight <= MAX_WEIGHT) {
                    packages.get(i).add(item.item);
                    packageWeights.set(i, packageWeights.get(i) + item.weight);
                    packed = true;
                    break;
                }
            }

            // 需要新包裹
            if (!packed) {
                List<SourceOrderItem> newPackage = new ArrayList<>();
                newPackage.add(item.item);
                packages.add(newPackage);
                packageWeights.add(item.weight);
            }
        }

        return packages;
    }
}
```

---

## 三、合单策略

### 3.1 合单场景

| 场景 | 触发条件 | 收益 |
|-----|---------|-----|
| 同客户合单 | 同一客户短时间内多个订单 | 节省运费 |
| 同地址合单 | 不同客户但同一地址 | 节省运费 |
| 凑单合单 | 促销活动凑单 | 满足活动条件 |

### 3.2 同客户合单

```java
@Service
public class CustomerMergeStrategy implements MergeStrategy {

    // 合单时间窗口：30分钟
    private static final int MERGE_WINDOW_MINUTES = 30;

    @Override
    public String getStrategyType() {
        return "SAME_CUSTOMER";
    }

    @Override
    public List<FulfillmentOrder> merge(List<SourceOrder> orders) {
        // 1. 按客户+地址分组
        Map<String, List<SourceOrder>> groupedOrders = orders.stream()
            .collect(Collectors.groupingBy(this::getMergeKey));

        List<FulfillmentOrder> result = new ArrayList<>();

        for (Map.Entry<String, List<SourceOrder>> entry : groupedOrders.entrySet()) {
            List<SourceOrder> customerOrders = entry.getValue();

            if (customerOrders.size() == 1) {
                // 单个订单，不需要合并
                result.add(createFulfillmentOrder(customerOrders.get(0)));
            } else {
                // 多个订单，检查是否可以合并
                List<SourceOrder> mergeable = filterMergeable(customerOrders);
                if (mergeable.size() > 1) {
                    result.add(mergeOrders(mergeable));
                } else {
                    // 不能合并，分别处理
                    for (SourceOrder order : customerOrders) {
                        result.add(createFulfillmentOrder(order));
                    }
                }
            }
        }

        return result;
    }

    private String getMergeKey(SourceOrder order) {
        // 客户ID + 地址哈希
        return order.getBuyerId() + "_" + hashAddress(order.getShippingAddress());
    }

    private List<SourceOrder> filterMergeable(List<SourceOrder> orders) {
        // 按下单时间排序
        orders.sort(Comparator.comparing(SourceOrder::getOrderTime));

        List<SourceOrder> mergeable = new ArrayList<>();
        LocalDateTime baseTime = orders.get(0).getOrderTime();

        for (SourceOrder order : orders) {
            // 在时间窗口内的订单可以合并
            if (Duration.between(baseTime, order.getOrderTime()).toMinutes() <= MERGE_WINDOW_MINUTES) {
                mergeable.add(order);
            }
        }

        return mergeable;
    }

    private FulfillmentOrder mergeOrders(List<SourceOrder> orders) {
        FulfillmentOrder fo = new FulfillmentOrder();
        fo.setFulfillmentOrderId(generateMergedOrderId(orders));

        // 合并商品明细
        List<FulfillmentOrderItem> allItems = new ArrayList<>();
        for (SourceOrder order : orders) {
            allItems.addAll(convertItems(order.getItems()));
        }
        fo.setItems(mergeItems(allItems)); // 合并相同SKU

        // 使用第一个订单的地址
        fo.setShippingAddress(orders.get(0).getShippingAddress());

        // 记录关系
        for (SourceOrder order : orders) {
            saveOrderRelation(order.getSourceOrderId(), fo.getFulfillmentOrderId(), "MERGE");
        }

        return fo;
    }

    /**
     * 合并相同SKU的明细
     */
    private List<FulfillmentOrderItem> mergeItems(List<FulfillmentOrderItem> items) {
        Map<String, FulfillmentOrderItem> mergedMap = new LinkedHashMap<>();

        for (FulfillmentOrderItem item : items) {
            String skuId = item.getSkuId();
            if (mergedMap.containsKey(skuId)) {
                FulfillmentOrderItem existing = mergedMap.get(skuId);
                existing.setQuantity(existing.getQuantity() + item.getQuantity());
            } else {
                mergedMap.put(skuId, item);
            }
        }

        return new ArrayList<>(mergedMap.values());
    }
}
```

---

## 四、策略引擎设计

### 4.1 策略引擎架构

```java
/**
 * 订单处理策略引擎
 */
@Service
public class OrderStrategyEngine {

    @Autowired
    private List<SplitStrategy> splitStrategies;

    @Autowired
    private List<MergeStrategy> mergeStrategies;

    @Autowired
    private StrategyConfigService configService;

    /**
     * 处理订单
     */
    public List<FulfillmentOrder> process(List<SourceOrder> orders) {
        // 1. 获取策略配置
        StrategyConfig config = configService.getConfig();

        // 2. 先执行合单策略
        List<SourceOrder> mergedOrders = orders;
        if (config.isMergeEnabled()) {
            mergedOrders = executeMergeStrategies(orders, config);
        }

        // 3. 再执行拆单策略
        List<FulfillmentOrder> result = new ArrayList<>();
        for (SourceOrder order : mergedOrders) {
            List<FulfillmentOrder> splitOrders = executeSplitStrategies(order, config);
            result.addAll(splitOrders);
        }

        return result;
    }

    private List<FulfillmentOrder> executeSplitStrategies(SourceOrder order, StrategyConfig config) {
        List<FulfillmentOrder> current = List.of(createFulfillmentOrder(order));

        // 按优先级执行拆单策略
        for (String strategyType : config.getSplitStrategyOrder()) {
            SplitStrategy strategy = findSplitStrategy(strategyType);
            if (strategy != null && strategy.shouldApply(order)) {
                List<FulfillmentOrder> newOrders = new ArrayList<>();
                for (FulfillmentOrder fo : current) {
                    newOrders.addAll(strategy.split(fo));
                }
                current = newOrders;
            }
        }

        return current;
    }
}
```

### 4.2 策略配置

```java
/**
 * 策略配置
 */
@Data
public class StrategyConfig {
    // 是否启用合单
    private boolean mergeEnabled = true;

    // 合单时间窗口（分钟）
    private int mergeWindowMinutes = 30;

    // 拆单策略执行顺序
    private List<String> splitStrategyOrder = List.of(
        "MULTI_WAREHOUSE",  // 先按仓库拆
        "PRE_SALE",         // 再按预售拆
        "OVERWEIGHT"        // 最后按重量拆
    );

    // 最大包裹重量（克）
    private double maxPackageWeight = 2000;

    // 是否允许部分发货
    private boolean partialShipmentAllowed = true;
}
```

### 4.3 规则配置化

```sql
-- 策略规则表
CREATE TABLE t_strategy_rule (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    rule_name VARCHAR(64) NOT NULL,
    rule_type VARCHAR(32) NOT NULL,
    condition_expr TEXT,
    action_expr TEXT,
    priority INT DEFAULT 0,
    enabled TINYINT DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 示例规则
INSERT INTO t_strategy_rule (rule_name, rule_type, condition_expr, action_expr, priority) VALUES
('多仓拆单', 'SPLIT', 'items.warehouseCount > 1', 'SPLIT_BY_WAREHOUSE', 100),
('预售拆单', 'SPLIT', 'items.hasOutOfStock == true', 'SPLIT_BY_STOCK', 90),
('超重拆单', 'SPLIT', 'totalWeight > 2000', 'SPLIT_BY_WEIGHT', 80),
('同客户合单', 'MERGE', 'sameCustomer && timeDiff < 30', 'MERGE_BY_CUSTOMER', 100);
```

---

## 五、状态管理

### 5.1 拆单后的状态同步

```java
@Service
public class OrderStatusSyncService {

    /**
     * 履约订单状态变更时，同步原始订单状态
     */
    @Transactional
    public void onFulfillmentStatusChange(String fulfillmentOrderId, FulfillmentStatus newStatus) {
        // 1. 获取关联的原始订单
        List<String> sourceOrderIds = orderRelationRepository
            .findSourceOrderIds(fulfillmentOrderId);

        for (String sourceOrderId : sourceOrderIds) {
            // 2. 获取该原始订单的所有履约订单状态
            List<FulfillmentOrder> fulfillmentOrders = fulfillmentOrderRepository
                .findBySourceOrderId(sourceOrderId);

            // 3. 计算原始订单状态
            OrderStatus newSourceStatus = calculateSourceOrderStatus(fulfillmentOrders);

            // 4. 更新原始订单状态
            sourceOrderRepository.updateStatus(sourceOrderId, newSourceStatus);
        }
    }

    /**
     * 根据履约订单状态计算原始订单状态
     */
    private OrderStatus calculateSourceOrderStatus(List<FulfillmentOrder> fulfillmentOrders) {
        // 全部完成 -> 已完成
        if (fulfillmentOrders.stream().allMatch(fo ->
                fo.getStatus() == FulfillmentStatus.DELIVERED)) {
            return OrderStatus.COMPLETED;
        }

        // 全部发货 -> 已发货
        if (fulfillmentOrders.stream().allMatch(fo ->
                fo.getStatus() == FulfillmentStatus.SHIPPED ||
                fo.getStatus() == FulfillmentStatus.DELIVERED)) {
            return OrderStatus.SHIPPED;
        }

        // 部分发货 -> 部分发货
        if (fulfillmentOrders.stream().anyMatch(fo ->
                fo.getStatus() == FulfillmentStatus.SHIPPED)) {
            return OrderStatus.PARTIAL_SHIPPED;
        }

        // 其他 -> 履约中
        return OrderStatus.FULFILLING;
    }
}
```

---

## 六、总结

### 6.1 核心要点

1. **三层订单模型**：原始订单 → 履约订单 → 出库单
2. **拆单场景**：多仓、预售、超重、赠品
3. **合单场景**：同客户、同地址
4. **策略引擎**：可配置、可扩展
5. **状态同步**：履约订单状态变更同步到原始订单

### 6.2 实施建议

- 先实现多仓拆单（最常见）
- 再实现预售拆单（业务需要）
- 合单功能可以后期添加
- 策略配置化，便于调整

---

> **系列文章导航**
>
> 本文是《跨境电商数字化转型指南》系列的第15篇
>
> - [x] 01-14. 前序文章
> - [x] 15. 订单拆分与合并策略（本文）
> - [ ] 16. 库存预占与释放
