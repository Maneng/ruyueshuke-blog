---
title: "履约路由与调度——智能选仓选物流"
date: 2026-01-29T17:50:00+08:00
draft: false
tags: ["OMS", "履约路由", "选仓策略", "物流选择", "跨境电商"]
categories: ["数字化转型"]
description: "订单应该从哪个仓库发货？用哪个物流？本文详解履约路由的核心逻辑，包括选仓策略、选物流策略、评分模型、规则引擎，帮你实现智能履约调度。"
series: ["跨境电商数字化转型指南"]
weight: 17
---

## 引言：履约路由的价值

**履约路由**：决定订单从哪个仓库发货、用哪个物流承运商。

**好的履约路由能带来**：
- 降低物流成本（选择最优物流）
- 提升时效（就近发货）
- 提高客户满意度
- 均衡仓库负载

**差的履约路由会导致**：
- 物流成本高
- 时效差
- 某些仓库爆仓，某些仓库闲置

---

## 一、履约路由架构

### 1.1 路由流程

```
订单 ──> 库存检查 ──> 选仓 ──> 选物流 ──> 生成履约单 ──> 下发WMS
           │          │         │
           │          │         │
           ▼          ▼         ▼
        有货仓库   最优仓库   最优物流
```

### 1.2 路由因素

| 因素 | 说明 | 权重 |
|-----|-----|-----|
| 库存 | 仓库是否有货 | 必要条件 |
| 距离 | 仓库到收货地的距离 | 影响时效 |
| 成本 | 物流费用 | 影响利润 |
| 时效 | 物流时效要求 | 影响体验 |
| 仓库负载 | 仓库当前处理能力 | 影响发货速度 |
| 承运商能力 | 承运商覆盖范围、服务质量 | 影响可选项 |

---

## 二、选仓策略

### 2.1 策略类型

| 策略 | 说明 | 适用场景 |
|-----|-----|---------|
| 就近发货 | 选择离收货地最近的仓库 | 时效优先 |
| 成本最优 | 选择物流成本最低的仓库 | 成本优先 |
| 库存均衡 | 优先选择库存多的仓库 | 均衡库存 |
| 负载均衡 | 优先选择负载低的仓库 | 均衡产能 |
| 综合评分 | 多因素加权评分 | 综合考虑 |

### 2.2 就近发货策略

```java
@Component
public class NearestWarehouseStrategy implements WarehouseStrategy {

    @Override
    public String getStrategyType() {
        return "NEAREST";
    }

    @Override
    public String selectWarehouse(Order order, List<WarehouseInventory> candidates) {
        Address destination = order.getShippingAddress();

        return candidates.stream()
            .filter(w -> w.getAvailableQty() >= getRequiredQty(order, w.getSkuId()))
            .min(Comparator.comparingDouble(w ->
                calculateDistance(w.getWarehouseId(), destination)))
            .map(WarehouseInventory::getWarehouseId)
            .orElseThrow(() -> new NoAvailableWarehouseException(order.getOrderId()));
    }

    /**
     * 计算仓库到目的地的距离
     * 简化版：使用经纬度计算直线距离
     */
    private double calculateDistance(String warehouseId, Address destination) {
        Warehouse warehouse = warehouseService.getWarehouse(warehouseId);
        double lat1 = warehouse.getLatitude();
        double lon1 = warehouse.getLongitude();
        double lat2 = getLatitude(destination);
        double lon2 = getLongitude(destination);

        // Haversine公式计算球面距离
        double R = 6371; // 地球半径（公里）
        double dLat = Math.toRadians(lat2 - lat1);
        double dLon = Math.toRadians(lon2 - lon1);
        double a = Math.sin(dLat/2) * Math.sin(dLat/2) +
                   Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) *
                   Math.sin(dLon/2) * Math.sin(dLon/2);
        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
        return R * c;
    }
}
```

### 2.3 成本最优策略

```java
@Component
public class CostOptimalWarehouseStrategy implements WarehouseStrategy {

    @Override
    public String getStrategyType() {
        return "COST_OPTIMAL";
    }

    @Override
    public String selectWarehouse(Order order, List<WarehouseInventory> candidates) {
        Address destination = order.getShippingAddress();
        double totalWeight = calculateTotalWeight(order);

        return candidates.stream()
            .filter(w -> w.getAvailableQty() >= getRequiredQty(order, w.getSkuId()))
            .min(Comparator.comparingDouble(w ->
                calculateShippingCost(w.getWarehouseId(), destination, totalWeight)))
            .map(WarehouseInventory::getWarehouseId)
            .orElseThrow(() -> new NoAvailableWarehouseException(order.getOrderId()));
    }

    /**
     * 计算物流成本
     */
    private double calculateShippingCost(String warehouseId, Address destination, double weight) {
        // 获取该仓库可用的物流商
        List<Carrier> carriers = carrierService.getCarriersForWarehouse(warehouseId);

        // 计算每个物流商的费用，取最低
        return carriers.stream()
            .filter(c -> c.canDeliver(destination))
            .mapToDouble(c -> c.calculateFee(warehouseId, destination, weight))
            .min()
            .orElse(Double.MAX_VALUE);
    }
}
```

### 2.4 综合评分策略（推荐）

```java
@Component
public class ScoringWarehouseStrategy implements WarehouseStrategy {

    // 权重配置
    private static final double DISTANCE_WEIGHT = 0.3;
    private static final double COST_WEIGHT = 0.4;
    private static final double INVENTORY_WEIGHT = 0.2;
    private static final double LOAD_WEIGHT = 0.1;

    @Override
    public String getStrategyType() {
        return "SCORING";
    }

    @Override
    public String selectWarehouse(Order order, List<WarehouseInventory> candidates) {
        Address destination = order.getShippingAddress();

        // 过滤有库存的仓库
        List<WarehouseInventory> available = candidates.stream()
            .filter(w -> w.getAvailableQty() >= getRequiredQty(order, w.getSkuId()))
            .collect(Collectors.toList());

        if (available.isEmpty()) {
            throw new NoAvailableWarehouseException(order.getOrderId());
        }

        // 计算各维度的归一化值
        double maxDistance = available.stream()
            .mapToDouble(w -> calculateDistance(w.getWarehouseId(), destination))
            .max().orElse(1);
        double maxCost = available.stream()
            .mapToDouble(w -> calculateShippingCost(w.getWarehouseId(), destination, order))
            .max().orElse(1);
        double maxInventory = available.stream()
            .mapToDouble(WarehouseInventory::getAvailableQty)
            .max().orElse(1);
        double maxLoad = available.stream()
            .mapToDouble(w -> getWarehouseLoad(w.getWarehouseId()))
            .max().orElse(1);

        // 计算综合得分
        return available.stream()
            .max(Comparator.comparingDouble(w -> {
                double distanceScore = 1 - calculateDistance(w.getWarehouseId(), destination) / maxDistance;
                double costScore = 1 - calculateShippingCost(w.getWarehouseId(), destination, order) / maxCost;
                double inventoryScore = w.getAvailableQty() / maxInventory;
                double loadScore = 1 - getWarehouseLoad(w.getWarehouseId()) / maxLoad;

                return distanceScore * DISTANCE_WEIGHT +
                       costScore * COST_WEIGHT +
                       inventoryScore * INVENTORY_WEIGHT +
                       loadScore * LOAD_WEIGHT;
            }))
            .map(WarehouseInventory::getWarehouseId)
            .orElseThrow();
    }
}
```

---

## 三、选物流策略

### 3.1 物流选择因素

| 因素 | 说明 |
|-----|-----|
| 覆盖范围 | 物流商是否能送达目的地 |
| 时效 | 预计送达时间 |
| 费用 | 物流费用 |
| 服务质量 | 丢包率、破损率、投诉率 |
| 追踪能力 | 是否支持物流追踪 |

### 3.2 物流选择实现

```java
@Service
public class CarrierSelectionService {

    /**
     * 选择最优物流
     */
    public Carrier selectCarrier(String warehouseId, Address destination,
                                 double weight, String serviceLevel) {
        // 1. 获取仓库可用的物流商
        List<Carrier> carriers = carrierService.getCarriersForWarehouse(warehouseId);

        // 2. 过滤能送达的物流商
        List<Carrier> available = carriers.stream()
            .filter(c -> c.canDeliver(destination))
            .filter(c -> c.getMaxWeight() >= weight)
            .collect(Collectors.toList());

        if (available.isEmpty()) {
            throw new NoAvailableCarrierException(warehouseId, destination);
        }

        // 3. 根据服务等级选择
        switch (serviceLevel) {
            case "EXPRESS":
                // 时效优先
                return selectByTimeEfficiency(available, destination);
            case "ECONOMY":
                // 成本优先
                return selectByCost(available, warehouseId, destination, weight);
            default:
                // 综合评分
                return selectByScore(available, warehouseId, destination, weight);
        }
    }

    /**
     * 时效优先选择
     */
    private Carrier selectByTimeEfficiency(List<Carrier> carriers, Address destination) {
        return carriers.stream()
            .min(Comparator.comparingInt(c -> c.getEstimatedDays(destination)))
            .orElseThrow();
    }

    /**
     * 成本优先选择
     */
    private Carrier selectByCost(List<Carrier> carriers, String warehouseId,
                                 Address destination, double weight) {
        return carriers.stream()
            .min(Comparator.comparingDouble(c ->
                c.calculateFee(warehouseId, destination, weight)))
            .orElseThrow();
    }

    /**
     * 综合评分选择
     */
    private Carrier selectByScore(List<Carrier> carriers, String warehouseId,
                                  Address destination, double weight) {
        return carriers.stream()
            .max(Comparator.comparingDouble(c -> {
                double costScore = 100 - c.calculateFee(warehouseId, destination, weight);
                double timeScore = 100 - c.getEstimatedDays(destination) * 10;
                double qualityScore = c.getQualityScore(); // 0-100

                return costScore * 0.4 + timeScore * 0.3 + qualityScore * 0.3;
            }))
            .orElseThrow();
    }
}
```

---

## 四、规则引擎

### 4.1 规则配置

```sql
-- 路由规则表
CREATE TABLE t_routing_rule (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    rule_name VARCHAR(64) NOT NULL COMMENT '规则名称',
    rule_type VARCHAR(32) NOT NULL COMMENT '类型：WAREHOUSE/CARRIER',
    priority INT DEFAULT 0 COMMENT '优先级（越大越优先）',

    -- 条件
    condition_channel VARCHAR(32) COMMENT '渠道条件',
    condition_country VARCHAR(32) COMMENT '国家条件',
    condition_sku_category VARCHAR(32) COMMENT 'SKU分类条件',
    condition_weight_min DECIMAL(10,2) COMMENT '最小重量',
    condition_weight_max DECIMAL(10,2) COMMENT '最大重量',
    condition_amount_min DECIMAL(12,2) COMMENT '最小金额',

    -- 动作
    action_warehouse_id VARCHAR(32) COMMENT '指定仓库',
    action_carrier_id VARCHAR(32) COMMENT '指定物流',
    action_strategy VARCHAR(32) COMMENT '选择策略',

    enabled TINYINT DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,

    KEY idx_type_priority (rule_type, priority DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='路由规则表';

-- 示例规则
INSERT INTO t_routing_rule (rule_name, rule_type, priority, condition_country, action_warehouse_id) VALUES
('美国订单走美西仓', 'WAREHOUSE', 100, 'US', 'WH_US_WEST'),
('欧洲订单走德国仓', 'WAREHOUSE', 100, 'DE,FR,IT,ES', 'WH_DE');

INSERT INTO t_routing_rule (rule_name, rule_type, priority, condition_channel, action_carrier_id) VALUES
('Amazon订单用UPS', 'CARRIER', 100, 'AMAZON', 'UPS'),
('eBay订单用USPS', 'CARRIER', 90, 'EBAY', 'USPS');
```

### 4.2 规则引擎实现

```java
@Service
public class RoutingRuleEngine {

    @Autowired
    private RoutingRuleRepository ruleRepository;

    /**
     * 匹配仓库规则
     */
    public String matchWarehouseRule(Order order) {
        List<RoutingRule> rules = ruleRepository.findByTypeAndEnabled("WAREHOUSE", true);

        // 按优先级排序
        rules.sort(Comparator.comparingInt(RoutingRule::getPriority).reversed());

        for (RoutingRule rule : rules) {
            if (matchCondition(rule, order)) {
                if (rule.getActionWarehouseId() != null) {
                    return rule.getActionWarehouseId();
                }
                if (rule.getActionStrategy() != null) {
                    return rule.getActionStrategy(); // 返回策略名称
                }
            }
        }

        return "SCORING"; // 默认使用评分策略
    }

    /**
     * 匹配物流规则
     */
    public String matchCarrierRule(Order order, String warehouseId) {
        List<RoutingRule> rules = ruleRepository.findByTypeAndEnabled("CARRIER", true);
        rules.sort(Comparator.comparingInt(RoutingRule::getPriority).reversed());

        for (RoutingRule rule : rules) {
            if (matchCondition(rule, order)) {
                if (rule.getActionCarrierId() != null) {
                    return rule.getActionCarrierId();
                }
            }
        }

        return null; // 无匹配规则，使用默认策略
    }

    /**
     * 条件匹配
     */
    private boolean matchCondition(RoutingRule rule, Order order) {
        // 渠道匹配
        if (rule.getConditionChannel() != null &&
            !rule.getConditionChannel().contains(order.getChannel())) {
            return false;
        }

        // 国家匹配
        if (rule.getConditionCountry() != null) {
            String country = order.getShippingAddress().getCountryCode();
            if (!rule.getConditionCountry().contains(country)) {
                return false;
            }
        }

        // 重量匹配
        double weight = calculateWeight(order);
        if (rule.getConditionWeightMin() != null && weight < rule.getConditionWeightMin()) {
            return false;
        }
        if (rule.getConditionWeightMax() != null && weight > rule.getConditionWeightMax()) {
            return false;
        }

        // 金额匹配
        if (rule.getConditionAmountMin() != null &&
            order.getTotalAmount().compareTo(rule.getConditionAmountMin()) < 0) {
            return false;
        }

        return true;
    }
}
```

---

## 五、履约调度服务

### 5.1 完整调度流程

```java
@Service
@Slf4j
public class FulfillmentRoutingService {

    @Autowired
    private RoutingRuleEngine ruleEngine;

    @Autowired
    private Map<String, WarehouseStrategy> warehouseStrategies;

    @Autowired
    private CarrierSelectionService carrierSelectionService;

    /**
     * 订单履约路由
     */
    @Transactional
    public FulfillmentOrder route(Order order) {
        log.info("开始履约路由: orderId={}", order.getOrderId());

        // 1. 匹配仓库规则
        String warehouseResult = ruleEngine.matchWarehouseRule(order);
        String warehouseId;

        if (isWarehouseId(warehouseResult)) {
            // 规则指定了具体仓库
            warehouseId = warehouseResult;
            log.info("规则指定仓库: {}", warehouseId);
        } else {
            // 规则指定了策略，执行策略选仓
            WarehouseStrategy strategy = warehouseStrategies.get(warehouseResult);
            List<WarehouseInventory> candidates = getWarehouseCandidates(order);
            warehouseId = strategy.selectWarehouse(order, candidates);
            log.info("策略选仓: strategy={}, warehouse={}", warehouseResult, warehouseId);
        }

        // 2. 匹配物流规则
        String carrierId = ruleEngine.matchCarrierRule(order, warehouseId);
        if (carrierId == null) {
            // 无规则匹配，使用策略选物流
            Carrier carrier = carrierSelectionService.selectCarrier(
                warehouseId,
                order.getShippingAddress(),
                calculateWeight(order),
                order.getServiceLevel()
            );
            carrierId = carrier.getCarrierId();
        }
        log.info("选择物流: {}", carrierId);

        // 3. 创建履约订单
        FulfillmentOrder fulfillmentOrder = new FulfillmentOrder();
        fulfillmentOrder.setFulfillmentOrderId(generateFulfillmentOrderId());
        fulfillmentOrder.setSourceOrderId(order.getOrderId());
        fulfillmentOrder.setWarehouseId(warehouseId);
        fulfillmentOrder.setCarrierId(carrierId);
        fulfillmentOrder.setShippingAddress(order.getShippingAddress());
        fulfillmentOrder.setItems(convertItems(order.getItems()));
        fulfillmentOrder.setStatus(FulfillmentStatus.PENDING);

        fulfillmentOrderRepository.save(fulfillmentOrder);

        log.info("履约路由完成: orderId={}, fulfillmentOrderId={}, warehouse={}, carrier={}",
            order.getOrderId(), fulfillmentOrder.getFulfillmentOrderId(), warehouseId, carrierId);

        return fulfillmentOrder;
    }
}
```

---

## 六、总结

### 6.1 核心要点

1. **选仓策略**：就近、成本最优、综合评分
2. **选物流策略**：时效优先、成本优先、综合评分
3. **规则引擎**：支持灵活配置路由规则
4. **评分模型**：多因素加权，可调整权重

### 6.2 实施建议

- 先实现基础的就近发货策略
- 再实现规则引擎，支持特殊场景
- 最后实现综合评分策略
- 持续优化权重参数

---

> **系列文章导航**
>
> 本文是《跨境电商数字化转型指南》系列的第17篇
>
> - [x] 13-16. OMS前序文章
> - [x] 17. 履约路由与调度（本文）
> - OMS自研篇完结
