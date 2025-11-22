---
title: "库存预警与智能补货：从被动响应到主动预测"
date: 2025-11-22T12:00:00+08:00
draft: false
tags: ["库存预警", "智能补货", "自动化", "需求预测"]
categories: ["供应链系统"]
description: "详细讲解库存预警机制和智能补货算法。从库存下限预警到智能补货策略，从被动响应到主动预测，全面提升库存管理的自动化水平。"
weight: 3
---

## 引言

库存预警和智能补货是库存管理自动化的核心，可以避免缺货和积压，提升运营效率。本文将探讨预警机制设计和智能补货算法实现。

---

## 1. 库存预警机制

### 1.1 库存下限预警

**触发条件**：
```
当前库存 < 安全库存
```

**预警级别**：
```
黄色预警：50% < 当前库存/安全库存 < 100%
橙色预警：20% < 当前库存/安全库存 < 50%
红色预警：当前库存/安全库存 < 20%
```

**Java实现**：
```java
public class InventoryAlertService {

    public String checkAlert(Inventory inventory) {
        int currentQty = inventory.getAvailableQty();
        int safetyStock = inventory.getSafetyStock();

        if (safetyStock == 0) return "NONE";

        double ratio = (double) currentQty / safetyStock;

        if (ratio >= 1.0) {
            return "NONE";          // 无预警
        } else if (ratio >= 0.5) {
            return "YELLOW";        // 黄色预警
        } else if (ratio >= 0.2) {
            return "ORANGE";        // 橙色预警
        } else {
            return "RED";           // 红色预警
        }
    }

    @Scheduled(cron = "0 */30 * * * ?")  // 每30分钟检查一次
    public void checkInventoryAlerts() {
        List<Inventory> inventories = inventoryMapper.selectAll();

        for (Inventory inventory : inventories) {
            String alertLevel = checkAlert(inventory);

            if (!"NONE".equals(alertLevel)) {
                // 发送预警通知
                sendAlert(inventory, alertLevel);

                // 触发补货流程
                if ("RED".equals(alertLevel) || "ORANGE".equals(alertLevel)) {
                    triggerReplenishment(inventory);
                }
            }
        }
    }
}
```

### 1.2 库存上限预警

**触发条件**：
```
当前库存 > 最大库存
```

**问题**：
- 占用仓储空间
- 资金占用过多
- 可能积压呆滞

**Java实现**：
```java
public void checkOverstockAlert(Inventory inventory) {
    int currentQty = inventory.getAvailableQty();
    int maxStock = inventory.getMaxStock();

    if (currentQty > maxStock) {
        // 发送超库存预警
        AlertMessage alert = new AlertMessage();
        alert.setLevel("WARNING");
        alert.setMessage(String.format(
            "SKU %s 库存超标: 当前%d件, 最大%d件",
            inventory.getSku(), currentQty, maxStock
        ));
        alertService.send(alert);

        // 建议促销清仓
        promotionService.suggestPromotion(inventory.getSku());
    }
}
```

### 1.3 呆滞预警

**定义**：
- 一级预警：60天无销售
- 二级预警：90天无销售
- 三级预警：180天无销售

**Java实现**：
```java
public void checkSlowMovingAlert() {
    LocalDate today = LocalDate.now();

    // 查询所有SKU的最后销售日期
    List<InventoryWithLastSale> inventories = inventoryMapper.selectWithLastSaleDate();

    for (InventoryWithLastSale inventory : inventories) {
        if (inventory.getLastSaleDate() == null) continue;

        long daysSinceLastSale = ChronoUnit.DAYS.between(inventory.getLastSaleDate(), today);

        String alertLevel = null;
        if (daysSinceLastSale >= 180) {
            alertLevel = "LEVEL_3";    // 三级预警（死库存）
        } else if (daysSinceLastSale >= 90) {
            alertLevel = "LEVEL_2";    // 二级预警（呆滞库存）
        } else if (daysSinceLastSale >= 60) {
            alertLevel = "LEVEL_1";    // 一级预警（慢销库存）
        }

        if (alertLevel != null) {
            // 发送呆滞预警
            sendSlowMovingAlert(inventory, alertLevel, daysSinceLastSale);

            // 建议处理措施
            if ("LEVEL_3".equals(alertLevel)) {
                // 报废处理
                suggestDisposal(inventory);
            } else if ("LEVEL_2".equals(alertLevel)) {
                // 促销清仓
                suggestClearance(inventory);
            }
        }
    }
}
```

---

## 2. 智能补货算法

### 2.1 基于销售预测补货

**原理**：
- 预测未来N天销量
- 计算需补货量 = 预测销量 - 当前库存 + 安全库存

**移动平均法**：
```java
public BigDecimal forecastByMovingAverage(List<BigDecimal> history, int period) {
    if (history.size() < period) {
        return BigDecimal.ZERO;
    }

    // 取最近period天的平均值
    return history.stream()
        .skip(history.size() - period)
        .reduce(BigDecimal.ZERO, BigDecimal::add)
        .divide(BigDecimal.valueOf(period), 2, RoundingMode.HALF_UP);
}
```

**指数平滑法**：
```java
public BigDecimal forecastByExponentialSmoothing(List<BigDecimal> history, double alpha) {
    if (history.isEmpty()) return BigDecimal.ZERO;

    BigDecimal forecast = history.get(0);

    for (int i = 1; i < history.size(); i++) {
        BigDecimal actual = history.get(i);
        forecast = actual.multiply(BigDecimal.valueOf(alpha))
            .add(forecast.multiply(BigDecimal.valueOf(1 - alpha)));
    }

    return forecast;
}
```

### 2.2 基于库存周转补货

**原理**：
- 目标周转天数：30天
- 补货量 = 30天预测销量 - 当前库存

**Java实现**：
```java
public int calculateReplenishmentByTurnover(String sku, int targetTurnoverDays) {
    // 1. 获取日均销量
    BigDecimal dailySales = salesDataService.getDailyAverage(sku, 30);

    // 2. 计算目标库存
    int targetStock = dailySales.multiply(BigDecimal.valueOf(targetTurnoverDays))
        .setScale(0, RoundingMode.UP)
        .intValue();

    // 3. 获取当前库存
    int currentStock = inventoryService.getAvailableQty(sku);

    // 4. 计算补货量
    int replenishQty = targetStock - currentStock;

    return Math.max(replenishQty, 0);  // 不能为负数
}
```

### 2.3 基于ROP补货

**原理**：
- 当前库存 ≤ ROP时触发补货
- 补货量 = EOQ

**Java实现**：
```java
@Component
public class ROPReplenishmentService {

    public void checkAndReplenish() {
        List<Inventory> inventories = inventoryMapper.selectAll();

        for (Inventory inventory : inventories) {
            int currentQty = inventory.getAvailableQty();
            int rop = inventory.getReorderPoint();

            if (currentQty <= rop) {
                // 触发补货
                int eoq = calculateEOQ(inventory.getSku());
                createPurchaseOrder(inventory.getSku(), eoq);

                log.info("触发ROP补货: sku={}, currentQty={}, rop={}, replenishQty={}",
                    inventory.getSku(), currentQty, rop, eoq);
            }
        }
    }

    private int calculateEOQ(String sku) {
        // EOQ = √(2DS/H)
        ProductCost cost = productService.getCost(sku);
        BigDecimal annualDemand = salesDataService.getAnnualDemand(sku);
        BigDecimal orderingCost = new BigDecimal("500");  // 订货成本
        BigDecimal holdingCost = cost.getUnitCost().multiply(new BigDecimal("0.2"));  // 持有成本率20%

        BigDecimal eoq = BigDecimal.valueOf(Math.sqrt(
            2 * annualDemand.doubleValue() * orderingCost.doubleValue()
            / holdingCost.doubleValue()
        ));

        return eoq.setScale(0, RoundingMode.UP).intValue();
    }
}
```

---

## 3. 补货策略优化

### 3.1 最小起订量（MOQ）

**规则**：
```
实际补货量 = max(计算补货量, MOQ)
```

**Java实现**：
```java
public int adjustForMOQ(int calculatedQty, String sku) {
    Supplier supplier = supplierService.getSupplier(sku);
    int moq = supplier.getMinimumOrderQuantity();

    if (calculatedQty < moq) {
        log.info("补货量低于MOQ: calculated={}, moq={}, adjusted={}",
            calculatedQty, moq, moq);
        return moq;
    }

    return calculatedQty;
}
```

### 3.2 包装单位

**规则**：
- 向上取整至整箱
- 减少拆箱损耗

**Java实现**：
```java
public int adjustForPackingUnit(int calculatedQty, String sku) {
    Product product = productService.getProduct(sku);
    int packingUnit = product.getPackingUnit();  // 每箱数量

    // 向上取整至整箱
    int boxes = (int) Math.ceil((double) calculatedQty / packingUnit);
    int adjustedQty = boxes * packingUnit;

    log.info("调整为整箱: calculated={}, packingUnit={}, boxes={}, adjusted={}",
        calculatedQty, packingUnit, boxes, adjustedQty);

    return adjustedQty;
}
```

### 3.3 运输成本优化

**规则**：
- 凑整车/整柜
- 降低单位运输成本

**Java实现**：
```java
public int adjustForTransportCost(int calculatedQty, String sku) {
    TransportInfo transport = transportService.getInfo(sku);
    int fullTruckLoad = transport.getFullTruckLoad();  // 整车装载量

    double currentLoad = (double) calculatedQty / fullTruckLoad;

    // 如果接近整车（90%以上），凑整车
    if (currentLoad >= 0.9 && currentLoad < 1.0) {
        log.info("凑整车: calculated={}, fullTruckLoad={}, adjusted={}",
            calculatedQty, fullTruckLoad, fullTruckLoad);
        return fullTruckLoad;
    }

    return calculatedQty;
}
```

---

## 4. 综合补货系统

### 4.1 智能补货引擎

```java
@Service
public class IntelligentReplenishmentEngine {

    public ReplenishmentPlan generatePlan(String sku) {

        // 1. 预测未来30天销量
        BigDecimal forecast = forecastService.predict(sku, 30);

        // 2. 获取当前库存
        int currentStock = inventoryService.getAvailableQty(sku);

        // 3. 获取安全库存
        int safetyStock = inventoryService.getSafetyStock(sku);

        // 4. 计算基础补货量
        int baseQty = forecast.intValue() - currentStock + safetyStock;

        if (baseQty <= 0) {
            return null;  // 无需补货
        }

        // 5. 应用各种调整
        int adjustedQty = baseQty;
        adjustedQty = adjustForMOQ(adjustedQty, sku);
        adjustedQty = adjustForPackingUnit(adjustedQty, sku);
        adjustedQty = adjustForTransportCost(adjustedQty, sku);

        // 6. 生成补货计划
        ReplenishmentPlan plan = new ReplenishmentPlan();
        plan.setSku(sku);
        plan.setBaseQty(baseQty);
        plan.setFinalQty(adjustedQty);
        plan.setForecast(forecast);
        plan.setCurrentStock(currentStock);
        plan.setSafetyStock(safetyStock);

        return plan;
    }
}
```

### 4.2 自动下单

```java
@Component
public class AutoReplenishmentTask {

    @Autowired
    private IntelligentReplenishmentEngine engine;

    @Scheduled(cron = "0 0 3 * * ?")  // 每天凌晨3点
    public void autoReplenish() {
        log.info("开始自动补货");

        List<String> skus = productService.listAllActiveSku();

        for (String sku : skus) {
            try {
                // 生成补货计划
                ReplenishmentPlan plan = engine.generatePlan(sku);

                if (plan != null) {
                    // 创建采购订单
                    PurchaseOrder po = new PurchaseOrder();
                    po.setSku(sku);
                    po.setQuantity(plan.getFinalQty());
                    po.setSupplier(supplierService.getSupplier(sku));
                    po.setStatus("PENDING");

                    purchaseOrderService.create(po);

                    log.info("已创建补货订单: sku={}, qty={}", sku, plan.getFinalQty());
                }
            } catch (Exception e) {
                log.error("自动补货失败: sku={}", sku, e);
            }
        }

        log.info("自动补货完成");
    }
}
```

---

## 5. 实战案例：菜鸟网络的智能补货

### 5.1 业务背景

菜鸟网络管理全国数百个仓库，需要智能补货保证库存充足。

### 5.2 技术方案

**AI预测**：
- LSTM神经网络预测销量
- 考虑节假日、促销、天气等因素
- 预测准确率85%+

**多仓协同**：
- 全国库存可视化
- 智能调拨优化
- 就近补货

**自动化**：
- 每天自动生成补货计划
- 自动下单给供应商
- 异常自动预警

### 5.3 优化成果

- 缺货率降低60%
- 库存周转率提升35%
- 补货效率提升80%

---

## 6. 总结

库存预警和智能补货是库存管理自动化的核心，可以大幅提升效率。

**核心要点**：

1. **预警机制**：库存下限、上限、呆滞
2. **补货算法**：销售预测、库存周转、ROP
3. **策略优化**：MOQ、包装单位、运输成本
4. **自动化**：定时任务、自动下单

在下一篇文章中，我们将探讨库存周转分析与优化，敬请期待！

---

## 参考资料

- 菜鸟网络技术博客
- 《供应链管理》教材
- 《库存管理与控制》
