---
title: "TMS运输计划与订单分配：从需求分析到执行落地"
date: 2025-11-21T10:00:00+08:00
draft: false
tags: ["TMS", "运输计划", "订单分配", "智能调度"]
categories: ["供应链系统"]
description: "深入解析运输计划制定流程和订单智能分配算法。从需求汇总到成本核算,从自动分配规则到手动干预机制,全面掌握TMS的计划与调度能力。"
weight: 3
stage: 1
stageTitle: "基础入门篇"
---

## 引言

运输计划和订单分配是TMS的核心功能,直接决定了运输成本和服务质量。一个优秀的运输计划系统,可以将运输成本降低20-30%,配送准时率提升至95%以上。

本文将深入探讨运输计划的制定流程、订单分配策略、智能算法应用,以及实战案例分析,帮助读者全面掌握TMS的计划与调度能力。

---

## 1. 运输计划制定

### 1.1 需求分析

运输计划的第一步是需求分析,即收集和分析待发货订单,为后续计划制定打下基础。

#### 订单汇总

**数据来源**：
- OMS推送的待发货订单
- WMS出库完成的待运输订单
- 手工录入的临时运输需求

**汇总维度**：
```sql
-- 按发货仓库+目的地城市+时效要求分组
SELECT
  warehouse_code,
  consignee_city,
  time_requirement,
  COUNT(*) as order_count,
  SUM(cargo_weight) as total_weight,
  SUM(cargo_volume) as total_volume
FROM transport_order
WHERE status = 'PENDING'
  AND created_time >= CURDATE()
GROUP BY warehouse_code, consignee_city, time_requirement
ORDER BY total_weight DESC;
```

**汇总结果示例**：
| 仓库 | 目的地 | 时效 | 订单数 | 总重量(kg) | 总体积(m³) |
|-----|-------|------|--------|-----------|----------|
| WH001 | 上海 | EXPRESS | 50 | 500 | 2.5 |
| WH001 | 广州 | STANDARD | 30 | 800 | 4.0 |
| WH002 | 北京 | URGENT | 10 | 100 | 0.5 |

#### 货物分析

**分析维度**：
1. **重量分布**：
   ```
   - 轻货(0-10kg): 60%
   - 中货(10-50kg): 30%
   - 重货(50kg+): 10%
   ```

2. **体积分布**：
   ```
   - 小件(0-0.1m³): 70%
   - 中件(0.1-0.5m³): 20%
   - 大件(0.5m³+): 10%
   ```

3. **特殊货物**：
   ```
   - 易碎品: 5%
   - 贵重物品: 3%
   - 危险品: 2%
   ```

**货物分析代码**：
```java
public class CargoAnalyzer {

    public CargoStatistics analyze(List<TransportOrder> orders) {
        CargoStatistics stats = new CargoStatistics();

        for (TransportOrder order : orders) {
            // 重量统计
            if (order.getCargoWeight().compareTo(new BigDecimal("10")) <= 0) {
                stats.incrementLightCargo();
            } else if (order.getCargoWeight().compareTo(new BigDecimal("50")) <= 0) {
                stats.incrementMediumCargo();
            } else {
                stats.incrementHeavyCargo();
            }

            // 特殊货物统计
            if ("FRAGILE".equals(order.getCargoType())) {
                stats.incrementFragile();
            } else if ("VALUABLE".equals(order.getCargoType())) {
                stats.incrementValuable();
            } else if ("DANGEROUS".equals(order.getCargoType())) {
                stats.incrementDangerous();
            }

            // 总重量、总体积
            stats.addTotalWeight(order.getCargoWeight());
            stats.addTotalVolume(order.getCargoVolume());
        }

        return stats;
    }
}
```

#### 时效要求

**时效分类**：
| 时效类型 | 承诺时间 | 比例 | 加价幅度 |
|---------|---------|-----|---------|
| STANDARD | 3-5天 | 60% | +0% |
| EXPRESS | 1-2天 | 30% | +20% |
| URGENT | 当日/次日 | 10% | +50% |

**时效排序**：
- 紧急订单优先处理
- 承诺时间临近的订单优先
- 大客户订单优先

#### 成本预算

**成本构成**：
```
总成本 = 运输成本 + 仓储成本 + 人工成本 + 管理成本

运输成本 = 运费 + 燃油费 + 过路费
```

**预算计算**：
```java
public class BudgetCalculator {

    public BigDecimal calculateBudget(List<TransportOrder> orders) {
        BigDecimal totalBudget = BigDecimal.ZERO;

        for (TransportOrder order : orders) {
            // 预估运费(根据运费规则)
            BigDecimal freight = freightCalculator.calculate(order);

            // 燃油费(运费的10%)
            BigDecimal fuelCost = freight.multiply(new BigDecimal("0.1"));

            // 过路费(固定50元)
            BigDecimal tollCost = new BigDecimal("50");

            totalBudget = totalBudget.add(freight).add(fuelCost).add(tollCost);
        }

        return totalBudget;
    }
}
```

### 1.2 运力评估

运力评估是运输计划的关键环节,需要评估自有运力和承运商运力,确保有足够的运力满足需求。

#### 自有运力

**车辆可用性评估**：
```sql
-- 查询可用车辆
SELECT
  vehicle_no,
  vehicle_type,
  capacity_weight,
  capacity_volume,
  current_location
FROM vehicle
WHERE status = 'AVAILABLE'
  AND maintenance_status = 'NORMAL'
  AND vehicle_no NOT IN (
    -- 排除已被占用的车辆
    SELECT DISTINCT vehicle_no
    FROM waybill
    WHERE status IN ('PICKED_UP', 'IN_TRANSIT')
  )
ORDER BY capacity_weight DESC;
```

**司机可用性评估**：
```sql
-- 查询可用司机
SELECT
  driver_id,
  driver_name,
  driver_phone,
  current_location,
  work_hours_today
FROM driver
WHERE status = 'AVAILABLE'
  AND work_hours_today < 8  -- 工作时长不超过8小时
  AND license_expire_date > CURDATE()  -- 驾照未过期
ORDER BY work_hours_today ASC;
```

#### 承运商运力

**承运商评估维度**：
1. **服务区域覆盖**：
   - 是否覆盖目的地城市
   - 是否提供到门服务

2. **服务能力**：
   - 日均处理订单量
   - 车辆数量
   - 网点覆盖

3. **绩效表现**：
   - 准时率 ≥ 95%
   - 破损率 ≤ 0.5%
   - 客诉率 ≤ 1%

**承运商查询**：
```sql
-- 查询符合条件的承运商
SELECT
  c.carrier_id,
  c.carrier_name,
  c.carrier_type,
  c.performance_score,
  c.on_time_rate,
  c.damage_rate
FROM carrier c
WHERE c.status = 'ACTIVE'
  AND c.performance_score >= 80  -- 绩效评分≥80
  AND JSON_CONTAINS(c.service_area, '"上海市"')  -- 服务区域包含上海
ORDER BY c.performance_score DESC;
```

#### 运力缺口计算

**计算公式**：
```
运力需求 = 总重量 / 平均车辆载重
可用运力 = 自有车辆数 + 承运商车辆数
运力缺口 = 运力需求 - 可用运力
```

**代码实现**：
```java
public class CapacityGapCalculator {

    public int calculateGap(List<TransportOrder> orders,
                           List<Vehicle> ownVehicles,
                           List<Carrier> carriers) {

        // 计算总重量
        BigDecimal totalWeight = orders.stream()
            .map(TransportOrder::getCargoWeight)
            .reduce(BigDecimal.ZERO, BigDecimal::add);

        // 平均车辆载重(假设5吨)
        BigDecimal avgCapacity = new BigDecimal("5000");

        // 运力需求(辆)
        int demand = totalWeight.divide(avgCapacity, 0, RoundingMode.UP).intValue();

        // 可用运力
        int ownCapacity = ownVehicles.size();
        int carrierCapacity = carriers.stream()
            .mapToInt(c -> c.getVehicleCount())
            .sum();

        // 运力缺口
        int gap = demand - ownCapacity - carrierCapacity;

        return Math.max(gap, 0);  // 缺口≥0
    }
}
```

### 1.3 方案制定

基于需求分析和运力评估,制定具体的运输方案。

#### 路线规划

**路线类型**：
1. **直达路线**：
   ```
   仓库 → 目的地
   适用：同城配送、短途运输
   ```

2. **中转路线**：
   ```
   仓库 → 中转站 → 目的地
   适用：跨省运输、长途运输
   ```

3. **多点配送路线**：
   ```
   仓库 → 客户A → 客户B → 客户C → 仓库
   适用：同区域多客户配送
   ```

**路线规划要素**：
- **起点**：发货仓库
- **终点**：收货地址
- **途经点**：中转站、配送点
- **预计里程**：通过地图API计算
- **预计时长**：考虑路况、休息时间

**调用地图API**：
```java
public class RoutePlanner {

    @Autowired
    private AmapApiClient amapClient;

    public Route planRoute(String origin, String destination) {
        // 调用高德地图路径规划API
        RouteResponse response = amapClient.driving(origin, destination);

        Route route = new Route();
        route.setDistance(response.getDistance());  // 距离(米)
        route.setDuration(response.getDuration());  // 时长(秒)
        route.setPath(response.getPolyline());      // 路径坐标

        return route;
    }
}
```

#### 车辆安排

**车辆选择原则**：
1. **载重匹配**：车辆载重 ≥ 货物重量
2. **体积匹配**：车厢体积 ≥ 货物体积
3. **类型匹配**：冷链货物→冷链车,危险品→危险品车
4. **距离优先**：选择距离发货地最近的车辆

**车辆分配算法**：
```java
public class VehicleAssigner {

    public Vehicle assignVehicle(TransportOrder order, List<Vehicle> vehicles) {
        return vehicles.stream()
            // 过滤：载重足够
            .filter(v -> v.getCapacityWeight().compareTo(order.getCargoWeight()) >= 0)
            // 过滤：体积足够
            .filter(v -> v.getCapacityVolume().compareTo(order.getCargoVolume()) >= 0)
            // 过滤：类型匹配
            .filter(v -> matchType(v, order))
            // 排序：距离最近
            .min(Comparator.comparing(v ->
                calculateDistance(v.getCurrentLocation(), order.getShipperAddress())
            ))
            .orElse(null);
    }

    private boolean matchType(Vehicle vehicle, TransportOrder order) {
        // 冷链货物必须用冷链车
        if ("COLD_CHAIN".equals(order.getCargoType())) {
            return "COLD_CHAIN".equals(vehicle.getVehicleType());
        }
        // 危险品必须用危险品车
        if ("DANGEROUS".equals(order.getCargoType())) {
            return "DANGEROUS".equals(vehicle.getVehicleType());
        }
        return true;
    }
}
```

#### 成本核算

**成本明细**：
```
1. 运费成本
   - 按运费规则计算

2. 燃油成本
   - 油耗(L/100km) × 里程(km) / 100 × 油价(元/L)
   示例: 30L/100km × 500km / 100 × 7元/L = 1050元

3. 过路费
   - 高速公路: 0.5元/km
   示例: 500km × 0.5元/km = 250元

4. 人工成本
   - 司机工资 / 月 / 平均车次
   示例: 8000元/月 / 20车次 = 400元/车次

5. 车辆折旧
   - 车辆价值 / 使用年限 / 年均车次
   示例: 200000元 / 5年 / 300车次 = 133元/车次
```

**成本核算代码**：
```java
public class CostCalculator {

    public TransportCost calculate(TransportOrder order, Route route, Vehicle vehicle) {
        TransportCost cost = new TransportCost();

        // 1. 运费成本
        BigDecimal freight = freightCalculator.calculate(order);
        cost.setFreight(freight);

        // 2. 燃油成本
        BigDecimal fuelCost = calculateFuelCost(vehicle, route);
        cost.setFuelCost(fuelCost);

        // 3. 过路费
        BigDecimal tollCost = calculateTollCost(route);
        cost.setTollCost(tollCost);

        // 4. 人工成本
        BigDecimal laborCost = new BigDecimal("400");
        cost.setLaborCost(laborCost);

        // 5. 车辆折旧
        BigDecimal depreciationCost = new BigDecimal("133");
        cost.setDepreciationCost(depreciationCost);

        // 总成本
        BigDecimal totalCost = freight.add(fuelCost).add(tollCost)
            .add(laborCost).add(depreciationCost);
        cost.setTotalCost(totalCost);

        return cost;
    }

    private BigDecimal calculateFuelCost(Vehicle vehicle, Route route) {
        // 油耗(L/100km)
        BigDecimal fuelConsumption = vehicle.getFuelConsumption();
        // 里程(km)
        BigDecimal distance = new BigDecimal(route.getDistance()).divide(new BigDecimal("1000"));
        // 油价(元/L)
        BigDecimal fuelPrice = new BigDecimal("7");

        return fuelConsumption.multiply(distance).divide(new BigDecimal("100"))
            .multiply(fuelPrice);
    }

    private BigDecimal calculateTollCost(Route route) {
        // 高速公路里程(假设占总里程的80%)
        BigDecimal highwayDistance = new BigDecimal(route.getDistance())
            .divide(new BigDecimal("1000"))
            .multiply(new BigDecimal("0.8"));

        // 高速公路费率(0.5元/km)
        BigDecimal tollRate = new BigDecimal("0.5");

        return highwayDistance.multiply(tollRate);
    }
}
```

---

## 2. 订单分配策略

### 2.1 自动分配规则

自动分配是TMS提升效率的核心,通过预设规则自动将订单分配给合适的承运商。

#### 地理位置匹配

**规则**：
- 订单目的地必须在承运商服务区域内
- 优先选择覆盖范围最精准的承运商

**实现逻辑**：
```java
public class GeographicMatcher {

    public List<Carrier> matchByGeographic(TransportOrder order, List<Carrier> carriers) {
        String city = order.getConsigneeCity();

        return carriers.stream()
            // 过滤：服务区域包含目的地城市
            .filter(c -> {
                JSONArray serviceArea = JSON.parseArray(c.getServiceArea());
                return serviceArea.contains(city);
            })
            // 排序：精准匹配优先(直接覆盖该城市的排前面)
            .sorted((c1, c2) -> {
                boolean c1Direct = JSON.parseArray(c1.getServiceArea()).contains(city);
                boolean c2Direct = JSON.parseArray(c2.getServiceArea()).contains(city);
                return Boolean.compare(c2Direct, c1Direct);
            })
            .collect(Collectors.toList());
    }
}
```

#### 运力匹配

**规则**：
- 承运商可用运力 ≥ 订单需求
- 优先选择运力充足的承运商

**实现逻辑**：
```java
public class CapacityMatcher {

    public List<Carrier> matchByCapacity(TransportOrder order, List<Carrier> carriers) {
        BigDecimal requiredWeight = order.getCargoWeight();
        BigDecimal requiredVolume = order.getCargoVolume();

        return carriers.stream()
            // 过滤：载重足够
            .filter(c -> c.getAvailableCapacity().compareTo(requiredWeight) >= 0)
            // 排序：运力充足的优先
            .sorted(Comparator.comparing(Carrier::getAvailableCapacity).reversed())
            .collect(Collectors.toList());
    }
}
```

#### 时效匹配

**规则**：
- 承运商服务时效 ≤ 订单时效要求
- 优先选择时效最快的承运商

**实现逻辑**：
```java
public class TimeRequirementMatcher {

    public List<Carrier> matchByTime(TransportOrder order, List<Carrier> carriers) {
        String timeReq = order.getTimeRequirement();

        return carriers.stream()
            // 过滤：时效满足
            .filter(c -> c.getSupportedTimeRequirements().contains(timeReq))
            // 排序：时效快的优先
            .sorted(Comparator.comparing(c -> getTimePriority(c.getFastestTimeRequirement())))
            .collect(Collectors.toList());
    }

    private int getTimePriority(String timeReq) {
        switch (timeReq) {
            case "URGENT": return 1;      // 极速
            case "EXPRESS": return 2;     // 快速
            case "STANDARD": return 3;    // 标准
            default: return 4;
        }
    }
}
```

#### 成本优先

**规则**：
- 选择运费最低的承运商
- 在满足时效前提下,成本最优

**实现逻辑**：
```java
public class CostOptimizer {

    public Carrier selectByCost(TransportOrder order, List<Carrier> carriers) {
        return carriers.stream()
            .min(Comparator.comparing(c -> {
                // 计算该承运商的运费
                FreightRule rule = freightRuleService.getRule(c.getCarrierId(), order);
                return freightCalculator.calculate(order, rule);
            }))
            .orElse(null);
    }
}
```

#### 服务质量优先

**规则**：
- 选择绩效评分最高的承运商
- 在满足成本前提下,质量最优

**实现逻辑**：
```java
public class QualityOptimizer {

    public Carrier selectByQuality(TransportOrder order, List<Carrier> carriers) {
        return carriers.stream()
            // 过滤：绩效评分≥80
            .filter(c -> c.getPerformanceScore().compareTo(new BigDecimal("80")) >= 0)
            // 排序：评分高的优先
            .max(Comparator.comparing(Carrier::getPerformanceScore))
            .orElse(null);
    }
}
```

### 2.2 综合分配算法

实际应用中,通常采用综合分配算法,平衡成本、时效、质量多个维度。

**评分模型**：
```
总评分 = 成本评分 × 40% + 时效评分 × 30% + 质量评分 × 30%

成本评分 = (最高运费 - 该承运商运费) / (最高运费 - 最低运费) × 100
时效评分 = 时效等级分数(极速:100,快速:80,标准:60)
质量评分 = 绩效评分(0-100)
```

**代码实现**：
```java
public class ComprehensiveAllocator {

    public Carrier allocate(TransportOrder order, List<Carrier> carriers) {
        // 计算每个承运商的评分
        Map<Carrier, BigDecimal> scoreMap = new HashMap<>();

        for (Carrier carrier : carriers) {
            BigDecimal score = calculateScore(order, carrier, carriers);
            scoreMap.put(carrier, score);
        }

        // 选择评分最高的承运商
        return scoreMap.entrySet().stream()
            .max(Map.Entry.comparingByValue())
            .map(Map.Entry::getKey)
            .orElse(null);
    }

    private BigDecimal calculateScore(TransportOrder order, Carrier carrier,
                                      List<Carrier> allCarriers) {

        // 1. 成本评分
        BigDecimal costScore = calculateCostScore(order, carrier, allCarriers);

        // 2. 时效评分
        BigDecimal timeScore = calculateTimeScore(carrier);

        // 3. 质量评分
        BigDecimal qualityScore = carrier.getPerformanceScore();

        // 综合评分
        return costScore.multiply(new BigDecimal("0.4"))
            .add(timeScore.multiply(new BigDecimal("0.3")))
            .add(qualityScore.multiply(new BigDecimal("0.3")));
    }

    private BigDecimal calculateCostScore(TransportOrder order, Carrier carrier,
                                          List<Carrier> allCarriers) {

        // 计算所有承运商的运费
        List<BigDecimal> freights = allCarriers.stream()
            .map(c -> {
                FreightRule rule = freightRuleService.getRule(c.getCarrierId(), order);
                return freightCalculator.calculate(order, rule);
            })
            .collect(Collectors.toList());

        BigDecimal maxFreight = freights.stream().max(BigDecimal::compareTo).orElse(BigDecimal.ZERO);
        BigDecimal minFreight = freights.stream().min(BigDecimal::compareTo).orElse(BigDecimal.ZERO);

        // 该承运商运费
        FreightRule rule = freightRuleService.getRule(carrier.getCarrierId(), order);
        BigDecimal thisFreight = freightCalculator.calculate(order, rule);

        // 成本评分
        if (maxFreight.equals(minFreight)) {
            return new BigDecimal("100");
        }

        return maxFreight.subtract(thisFreight)
            .divide(maxFreight.subtract(minFreight), 2, RoundingMode.HALF_UP)
            .multiply(new BigDecimal("100"));
    }

    private BigDecimal calculateTimeScore(Carrier carrier) {
        String fastestTime = carrier.getFastestTimeRequirement();
        switch (fastestTime) {
            case "URGENT": return new BigDecimal("100");
            case "EXPRESS": return new BigDecimal("80");
            case "STANDARD": return new BigDecimal("60");
            default: return BigDecimal.ZERO;
        }
    }
}
```

### 2.3 手动干预机制

自动分配虽然高效,但某些特殊场景需要人工干预。

#### 大客户优先

**规则**：
- VIP客户订单优先分配优质承运商
- 保证服务质量,不考虑成本

**实现**：
```java
public class VipOrderHandler {

    public Carrier handleVipOrder(TransportOrder order) {
        // 查询所有A级承运商
        List<Carrier> topCarriers = carrierService.listByGrade("A");

        // 选择绩效评分最高的
        return topCarriers.stream()
            .max(Comparator.comparing(Carrier::getPerformanceScore))
            .orElse(null);
    }
}
```

#### 紧急订单插队

**规则**：
- 紧急订单优先处理,打断当前计划
- 可能需要加急调度车辆

**实现**：
```java
public class UrgentOrderHandler {

    public void handleUrgentOrder(TransportOrder order) {
        // 标记为紧急
        order.setPriority("URGENT");

        // 立即分配承运商
        Carrier carrier = allocator.allocate(order, carrierService.listAll());

        // 推送到承运商系统(跳过批次,立即推送)
        carrierApiClient.pushOrder(carrier, order);

        // 通知运营人员
        notificationService.notifyOps("紧急订单已分配: " + order.getOrderNo());
    }
}
```

#### 问题订单人工分配

**问题订单类型**：
- 地址不详细(需要联系客户确认)
- 货物特殊(需要特殊处理)
- 承运商拒绝接单(需要重新分配)

**处理流程**：
```
1. 系统自动识别问题订单
2. 推送到人工处理队列
3. 运营人员审核处理
4. 手动分配承运商
5. 推送执行
```

---

## 3. 订单分配算法

### 3.1 贪心算法

**原理**：
每次选择当前最优解,不考虑全局最优。

**适用场景**：
- 订单量大(1000+)
- 实时性要求高(1秒内响应)
- 可接受次优解

**算法实现**：
```java
public class GreedyAllocator {

    public Map<Carrier, List<TransportOrder>> allocate(List<TransportOrder> orders,
                                                       List<Carrier> carriers) {

        Map<Carrier, List<TransportOrder>> allocation = new HashMap<>();

        for (TransportOrder order : orders) {
            // 为每个订单选择当前最优承运商
            Carrier bestCarrier = selectBestCarrier(order, carriers);

            allocation.computeIfAbsent(bestCarrier, k -> new ArrayList<>()).add(order);
        }

        return allocation;
    }

    private Carrier selectBestCarrier(TransportOrder order, List<Carrier> carriers) {
        return carriers.stream()
            .filter(c -> canServe(c, order))  // 过滤：能服务该订单
            .min(Comparator.comparing(c -> calculateCost(order, c)))  // 最小成本
            .orElse(null);
    }

    private boolean canServe(Carrier carrier, TransportOrder order) {
        // 1. 服务区域匹配
        if (!matchGeographic(carrier, order)) return false;
        // 2. 运力充足
        if (!matchCapacity(carrier, order)) return false;
        // 3. 时效匹配
        if (!matchTime(carrier, order)) return false;
        return true;
    }
}
```

**优缺点**：
- ✅ 速度快：O(n×m),n=订单数,m=承运商数
- ✅ 实现简单
- ❌ 可能不是全局最优
- ❌ 承运商负载不均衡

### 3.2 遗传算法

**原理**：
模拟生物进化过程,通过选择、交叉、变异找到近似最优解。

**适用场景**：
- 订单量中等(100-1000)
- 对结果质量要求高
- 可接受较长计算时间(10秒内)

**算法步骤**：
```
1. 初始化种群
   - 随机生成N个分配方案(如100个)

2. 适应度评估
   - 计算每个方案的总成本
   - 成本越低,适应度越高

3. 选择
   - 保留适应度高的方案
   - 淘汰适应度低的方案

4. 交叉
   - 两个方案交换部分订单分配
   - 生成新方案

5. 变异
   - 随机改变某些订单的承运商分配

6. 迭代
   - 重复2-5步,直到收敛或达到最大迭代次数
```

**代码实现**：
```java
public class GeneticAllocator {

    private static final int POPULATION_SIZE = 100;  // 种群大小
    private static final int MAX_GENERATIONS = 50;    // 最大迭代次数
    private static final double MUTATION_RATE = 0.1;  // 变异概率

    public Map<Carrier, List<TransportOrder>> allocate(List<TransportOrder> orders,
                                                       List<Carrier> carriers) {

        // 1. 初始化种群
        List<Chromosome> population = initializePopulation(orders, carriers);

        // 2. 迭代优化
        for (int generation = 0; generation < MAX_GENERATIONS; generation++) {
            // 适应度评估
            evaluateFitness(population);

            // 选择
            List<Chromosome> selected = select(population);

            // 交叉
            List<Chromosome> offspring = crossover(selected);

            // 变异
            mutate(offspring);

            // 更新种群
            population = offspring;
        }

        // 3. 返回最优解
        Chromosome best = population.stream()
            .max(Comparator.comparing(Chromosome::getFitness))
            .orElse(null);

        return best != null ? best.getAllocation() : new HashMap<>();
    }

    private List<Chromosome> initializePopulation(List<TransportOrder> orders,
                                                 List<Carrier> carriers) {

        List<Chromosome> population = new ArrayList<>();

        for (int i = 0; i < POPULATION_SIZE; i++) {
            Chromosome chromosome = new Chromosome();
            Map<Carrier, List<TransportOrder>> allocation = new HashMap<>();

            // 随机分配
            for (TransportOrder order : orders) {
                Carrier randomCarrier = carriers.get(
                    ThreadLocalRandom.current().nextInt(carriers.size())
                );
                allocation.computeIfAbsent(randomCarrier, k -> new ArrayList<>()).add(order);
            }

            chromosome.setAllocation(allocation);
            population.add(chromosome);
        }

        return population;
    }

    private void evaluateFitness(List<Chromosome> population) {
        for (Chromosome chromosome : population) {
            // 适应度 = 1 / 总成本(成本越低,适应度越高)
            BigDecimal totalCost = calculateTotalCost(chromosome.getAllocation());
            double fitness = 1.0 / totalCost.doubleValue();
            chromosome.setFitness(fitness);
        }
    }

    private List<Chromosome> select(List<Chromosome> population) {
        // 轮盘赌选择
        double totalFitness = population.stream()
            .mapToDouble(Chromosome::getFitness)
            .sum();

        List<Chromosome> selected = new ArrayList<>();
        for (int i = 0; i < POPULATION_SIZE; i++) {
            double random = ThreadLocalRandom.current().nextDouble() * totalFitness;
            double sum = 0;

            for (Chromosome chromosome : population) {
                sum += chromosome.getFitness();
                if (sum >= random) {
                    selected.add(chromosome.clone());
                    break;
                }
            }
        }

        return selected;
    }

    private List<Chromosome> crossover(List<Chromosome> parents) {
        List<Chromosome> offspring = new ArrayList<>();

        for (int i = 0; i < parents.size(); i += 2) {
            if (i + 1 < parents.size()) {
                // 单点交叉
                Chromosome parent1 = parents.get(i);
                Chromosome parent2 = parents.get(i + 1);

                Chromosome child1 = new Chromosome();
                Chromosome child2 = new Chromosome();

                // 交叉逻辑(简化)
                // ... 省略具体实现

                offspring.add(child1);
                offspring.add(child2);
            } else {
                offspring.add(parents.get(i));
            }
        }

        return offspring;
    }

    private void mutate(List<Chromosome> population) {
        for (Chromosome chromosome : population) {
            if (ThreadLocalRandom.current().nextDouble() < MUTATION_RATE) {
                // 随机选择一个订单,改变其承运商分配
                // ... 省略具体实现
            }
        }
    }
}
```

**优缺点**：
- ✅ 接近全局最优
- ✅ 适用于复杂约束
- ❌ 计算时间长
- ❌ 参数调优困难

---

## 4. 实战案例：京东物流的订单分配

### 4.1 业务背景

京东物流每天处理1000万+订单,需要分配给：
- 自营车辆(青流计划)
- 第三方承运商(顺丰、三通一达等)

### 4.2 分配策略

**优先级**：
```
1. 自营订单 → 自营车辆(优先保障自营配送)
2. 大客户订单 → 优质承运商(保证服务质量)
3. 普通订单 → 成本最优承运商
4. 偏远地区 → 专线承运商
```

**AI算法**：
- 机器学习预测订单量
- 动态调整承运商运力配置
- 实时优化分配策略

### 4.3 技术架构

```
┌─────────────────────────────────────────┐
│          订单分配引擎                      │
├─────────────────────────────────────────┤
│                                         │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐ │
│  │规则引擎 │  │算法引擎 │  │AI引擎  │  │
│  └─────────┘  └─────────┘  └─────────┘ │
│       ↓            ↓            ↓       │
│  ┌─────────────────────────────────┐   │
│  │     分配决策(实时+批次)          │   │
│  └─────────────────────────────────┘   │
│                   ↓                     │
│  ┌─────────────────────────────────┐   │
│  │   推送到承运商系统(API/MQ)       │   │
│  └─────────────────────────────────┘   │
│                                         │
└─────────────────────────────────────────┘
```

### 4.4 优化成果

- **成本降低**：运输成本下降20%
- **效率提升**：分配耗时从10分钟降至1分钟
- **准时率提升**：配送准时率从90%提升至95%

---

## 5. 总结

本文深入探讨了TMS的运输计划制定和订单分配策略,为实际应用提供了完整的方法论和代码示例。

**核心要点**：

1. **运输计划制定**：
   - 需求分析：订单汇总、货物分析、时效要求、成本预算
   - 运力评估：自有运力、承运商运力、运力缺口
   - 方案制定：路线规划、车辆安排、成本核算

2. **订单分配策略**：
   - 自动分配规则：地理位置、运力、时效、成本、质量
   - 综合分配算法：平衡多维度,评分模型
   - 手动干预机制：大客户优先、紧急订单、问题订单

3. **分配算法**：
   - 贪心算法：速度快,适用于实时场景
   - 遗传算法：接近最优,适用于离线优化

在下一篇文章中,我们将深入探讨路线优化与算法实现,包括TSP、VRP经典问题的求解,敬请期待！

---

## 参考资料

- 京东物流技术白皮书
- 《运筹学》教材
- 《算法导论》
- 高德地图开放平台文档
