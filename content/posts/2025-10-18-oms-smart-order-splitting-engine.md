---
title: "OMS订单系统：智能拆单规则引擎设计"
date: 2025-10-18T09:00:00+08:00
draft: false
tags: ["OMS", "订单系统", "规则引擎", "拆单算法", "供应链"]
categories: ["技术"]
description: "深度解析电商订单拆单的业务场景和技术实现，从硬编码到规则引擎的演进过程。包含Drools规则引擎集成、策略模式实践和拆单准确率优化方案。"
series: ["供应链系统实战"]
weight: 4
comments: true
---

## 引子：一个被拆成5单的订单

"用户下单买了3件商品，为什么最后拆成了5个包裹？客户投诉说运费太贵了！"

这是2023年春节后，客服经理的第一通投诉电话。我打开OMS系统查看：

**订单详情**：
- 商品A：2件（北京仓有1件，上海仓有3件）
- 商品B：1件（深圳仓有货）
- 商品C：1件（北京仓有货）

**系统拆单结果**：
1. 北京仓发货：商品A × 1
2. 上海仓发货：商品A × 1（本应2件）
3. 上海仓发货：商品A × 0（空单！）
4. 深圳仓发货：商品B × 1
5. 北京仓发货：商品C × 1

**问题分析**：
- 拆单逻辑错误：商品A应该合并发货
- 产生空单：浪费系统资源
- 运费激增：5个包裹 vs 最优2个包裹
- 客户体验差：收货5次，退货率上升

这个案例暴露了硬编码拆单逻辑的致命缺陷。经过2个月的重构，我们实现了：
- 拆单准确率：**65% → 98%**
- 平均拆单数：**2.8单 → 1.5单**
- 人工干预率：**15% → 3%**
- 拆单耗时：**500ms → 80ms**

这篇文章，就是那次规则引擎重构的完整技术总结。

---

## 业务场景：为什么需要拆单

### 常见拆单场景

#### 场景1：跨仓发货

```
订单包含：
  - 商品A：北京仓
  - 商品B：上海仓

拆单结果：
  - 子订单1：北京仓发商品A
  - 子订单2：上海仓发商品B
```

#### 场景2：部分有货

```
订单包含：商品A × 3件

库存情况：
  - 北京仓：2件
  - 上海仓：1件

拆单结果：
  - 子订单1：北京仓发2件
  - 子订单2：上海仓发1件
```

#### 场景3：物流限制

```
订单总重：35kg（单票限重30kg）

拆单结果：
  - 子订单1：20kg
  - 子订单2：15kg
```

#### 场景4：营销活动

```
订单包含：
  - 商品A：参加满减活动
  - 商品B：不参加活动

拆单结果：
  - 子订单1：商品A（享受满减）
  - 子订单2：商品B（正常发货）
```

---

## 拆单规则的复杂性

### 多维度规则冲突

**示例场景**：

```
订单：商品A × 2，商品B × 1

规则1（库存优先）：
  - 北京仓：A × 1, B × 1
  - 上海仓：A × 2
  → 拆2单：北京仓（A+B），上海仓（A）

规则2（物流成本优先）：
  - 同城配送便宜
  - 用户地址：北京
  → 拆2单：北京仓（A+B），上海仓（A）

规则3（时效优先）：
  - 北京仓距离近，1天达
  - 上海仓距离远，3天达
  → 全部北京仓发货（但库存不足！）

规则冲突！需要优先级排序。
```

### 规则变更频繁

- 双十一：优先就近仓库（降低物流压力）
- 618：优先大仓（提升打包效率）
- 日常：优先库龄高的商品（降低库存成本）

硬编码无法应对如此频繁的规则调整。

---

## 技术演进：从硬编码到规则引擎

### V1.0：硬编码（不堪回首）

```java
@Service
public class OrderSplitServiceV1 {

    public List<SubOrder> split(Order order) {
        List<SubOrder> result = new ArrayList<>();

        // 规则1：按仓库拆分
        for (OrderItem item : order.getItems()) {
            String warehouse = inventoryService.findWarehouse(item.getSku());

            SubOrder subOrder = findOrCreateSubOrder(result, warehouse);
            subOrder.addItem(item);
        }

        // 规则2：检查重量限制
        for (SubOrder subOrder : result) {
            if (subOrder.getTotalWeight() > 30.0) {
                // 继续拆分...
            }
        }

        // 规则3：检查满减活动
        // 规则4：检查...
        // ... 100行硬编码

        return result;
    }
}
```

**问题**：
- 规则耦合严重
- 新增规则需要改代码
- 测试困难
- 无法动态调整优先级

---

### V2.0：策略模式（略有改善）

```java
/**
 * 拆单策略接口
 */
public interface SplitStrategy {
    boolean match(Order order);
    List<SubOrder> execute(Order order);
    int getPriority();
}

/**
 * 策略1：按仓库拆分
 */
@Component
public class SplitByWarehouseStrategy implements SplitStrategy {

    @Override
    public boolean match(Order order) {
        return hasMultiWarehouse(order);
    }

    @Override
    public List<SubOrder> execute(Order order) {
        Map<String, List<OrderItem>> grouped =
            order.getItems().stream()
                .collect(Collectors.groupingBy(item ->
                    inventoryService.getWarehouse(item.getSku())));

        return grouped.entrySet().stream()
            .map(entry -> createSubOrder(order, entry.getKey(), entry.getValue()))
            .collect(Collectors.toList());
    }

    @Override
    public int getPriority() {
        return 100;  // 高优先级
    }
}

/**
 * 策略2：按重量拆分
 */
@Component
public class SplitByWeightStrategy implements SplitStrategy {

    private static final double MAX_WEIGHT = 30.0;

    @Override
    public boolean match(Order order) {
        return order.getTotalWeight() > MAX_WEIGHT;
    }

    @Override
    public List<SubOrder> execute(Order order) {
        List<SubOrder> result = new ArrayList<>();
        SubOrder currentSubOrder = new SubOrder();
        double currentWeight = 0.0;

        for (OrderItem item : order.getItems()) {
            double itemWeight = item.getWeight() * item.getQuantity();

            if (currentWeight + itemWeight > MAX_WEIGHT) {
                result.add(currentSubOrder);
                currentSubOrder = new SubOrder();
                currentWeight = 0.0;
            }

            currentSubOrder.addItem(item);
            currentWeight += itemWeight;
        }

        if (!currentSubOrder.isEmpty()) {
            result.add(currentSubOrder);
        }

        return result;
    }

    @Override
    public int getPriority() {
        return 90;  // 次优先级
    }
}

/**
 * 拆单引擎
 */
@Service
public class OrderSplitEngineV2 {

    @Autowired
    private List<SplitStrategy> strategies;

    public List<SubOrder> split(Order order) {
        // 按优先级排序
        strategies.sort(Comparator.comparing(SplitStrategy::getPriority).reversed());

        // 执行匹配的策略
        for (SplitStrategy strategy : strategies) {
            if (strategy.match(order)) {
                return strategy.execute(order);
            }
        }

        // 默认：不拆单
        return Collections.singletonList(new SubOrder(order));
    }
}
```

**改进**：
- 策略可插拔
- 优先级可配置
- 易于单元测试

**不足**：
- 策略之间无法组合
- 复杂规则仍需编码
- 业务人员无法直接配置

---

### V3.0：Drools规则引擎（终极方案）

#### Maven依赖

```xml
<dependency>
    <groupId>org.drools</groupId>
    <artifactId>drools-core</artifactId>
    <version>7.74.1.Final</version>
</dependency>
<dependency>
    <groupId>org.drools</groupId>
    <artifactId>drools-compiler</artifactId>
    <version>7.74.1.Final</version>
</dependency>
```

#### Drools规则文件

```drl
// split-rules.drl
package com.oms.rules

import com.oms.model.Order
import com.oms.model.SubOrder
import com.oms.service.InventoryService

global InventoryService inventoryService

// 规则1：跨仓拆单
rule "Split by Warehouse"
    salience 100  // 优先级
    when
        $order : Order(hasMultiWarehouse() == true)
    then
        System.out.println("触发规则：跨仓拆单");
        insert(new SplitResult("WAREHOUSE", $order));
end

// 规则2：重量超限拆单
rule "Split by Weight"
    salience 90
    when
        $order : Order(totalWeight > 30.0)
    then
        System.out.println("触发规则：重量超限拆单");
        insert(new SplitResult("WEIGHT", $order));
end

// 规则3：营销活动拆单
rule "Split by Promotion"
    salience 80
    when
        $order : Order(hasPromotion() == true)
    then
        System.out.println("触发规则：营销活动拆单");
        insert(new SplitResult("PROMOTION", $order));
end

// 规则4：库存不足拆单
rule "Split by Stock"
    salience 70
    when
        $order : Order()
        not (inventoryService.hasEnoughStock($order))
    then
        System.out.println("触发规则：库存不足拆单");
        insert(new SplitResult("STOCK", $order));
end
```

#### Drools引擎封装

```java
@Service
public class DroolsRuleService {

    private KieContainer kieContainer;

    @PostConstruct
    public void init() {
        KieServices kieServices = KieServices.Factory.get();
        kieContainer = kieServices.getKieClasspathContainer();
    }

    /**
     * 执行规则
     */
    public List<SplitResult> executeRules(Order order) {
        KieSession kieSession = kieContainer.newKieSession("split-rules");

        try {
            // 设置全局变量
            kieSession.setGlobal("inventoryService", inventoryService);

            // 插入事实
            kieSession.insert(order);

            // 触发规则
            int firedRules = kieSession.fireAllRules();
            log.info("触发了{}条规则", firedRules);

            // 获取结果
            Collection<?> results = kieSession.getObjects(
                new ClassObjectFilter(SplitResult.class));

            return results.stream()
                .map(obj -> (SplitResult) obj)
                .collect(Collectors.toList());

        } finally {
            kieSession.dispose();
        }
    }
}
```

#### 完整拆单服务

```java
@Service
public class OrderSplitServiceV3 {

    @Autowired
    private DroolsRuleService droolsRuleService;

    @Autowired
    private Map<String, SplitHandler> handlerMap;

    /**
     * V3.0：规则引擎驱动
     */
    public List<SubOrder> split(Order order) {
        // 1. 执行规则引擎
        List<SplitResult> results = droolsRuleService.executeRules(order);

        if (results.isEmpty()) {
            // 无需拆单
            return Collections.singletonList(new SubOrder(order));
        }

        // 2. 按优先级选择拆单策略
        SplitResult primaryResult = results.stream()
            .max(Comparator.comparing(SplitResult::getPriority))
            .orElseThrow();

        // 3. 执行具体拆单逻辑
        SplitHandler handler = handlerMap.get(primaryResult.getType());
        List<SubOrder> subOrders = handler.handle(order);

        // 4. 后处理：合并、校验
        return postProcess(subOrders);
    }

    /**
     * 后处理：合并同仓库订单
     */
    private List<SubOrder> postProcess(List<SubOrder> subOrders) {
        Map<String, SubOrder> merged = new LinkedHashMap<>();

        for (SubOrder subOrder : subOrders) {
            String warehouse = subOrder.getWarehouse();

            if (merged.containsKey(warehouse)) {
                // 合并
                merged.get(warehouse).mergeItems(subOrder.getItems());
            } else {
                merged.put(warehouse, subOrder);
            }
        }

        return new ArrayList<>(merged.values());
    }
}
```

---

## 生产优化

### 1. 规则版本管理

```java
@Service
public class RuleVersionService {

    /**
     * 动态加载规则文件
     */
    public KieContainer loadRules(String version) {
        KieServices kieServices = KieServices.Factory.get();
        KieFileSystem kfs = kieServices.newKieFileSystem();

        // 从数据库或配置中心加载规则
        String ruleContent = ruleRepository.findByVersion(version);

        kfs.write("src/main/resources/rules/split-rules-" + version + ".drl",
                  ruleContent);

        KieBuilder kieBuilder = kieServices.newKieBuilder(kfs);
        kieBuilder.buildAll();

        return kieServices.newKieContainer(
            kieBuilder.getKieModule().getReleaseId());
    }

    /**
     * AB测试：灰度规则
     */
    public String selectRuleVersion(Order order) {
        // 10%用户使用新规则
        if (order.getUserId() % 10 == 0) {
            return "v2.0";
        }
        return "v1.0";  // 稳定版本
    }
}
```

### 2. 性能监控

```java
@Aspect
@Component
public class SplitPerformanceAspect {

    @Around("execution(* com.oms.service.OrderSplitService.split(..))")
    public Object monitorPerformance(ProceedingJoinPoint joinPoint) throws Throwable {
        long startTime = System.currentTimeMillis();

        try {
            Object result = joinPoint.proceed();

            long duration = System.currentTimeMillis() - startTime;

            // 记录指标
            metricsService.record("order.split.duration", duration);

            if (duration > 500) {
                log.warn("拆单耗时过长：{}ms", duration);
            }

            return result;

        } catch (Exception e) {
            metricsService.increment("order.split.error");
            throw e;
        }
    }
}
```

---

## 效果数据与经验总结

### 上线效果

| 指标 | V1.0（硬编码） | V2.0（策略） | V3.0（规则引擎） | 总提升 |
|------|---------------|-------------|----------------|--------|
| 拆单准确率 | 65% | 85% | 98% | **50.8%** |
| 平均拆单数 | 2.8 | 2.0 | 1.5 | **46.4%** |
| 人工干预率 | 15% | 8% | 3% | **80%** |
| 拆单耗时 | 500ms | 200ms | 80ms | **84%** |

### 核心经验

#### ✅ DO

1. **规则外部化**：规则文件独立于代码，便于修改
2. **优先级明确**：用salience控制规则优先级
3. **小步迭代**：先用策略模式验证，再引入规则引擎
4. **AB测试**：新规则灰度发布，降低风险
5. **监控告警**：拆单异常率、耗时实时监控

#### ❌ DON'T

1. **不要过度设计**：规则不复杂时策略模式就够了
2. **不要忽略性能**：规则引擎有开销，需要缓存
3. **不要缺少测试**：每条规则都需要单元测试
4. **不要忽略兜底**：规则引擎失败时的降级方案

---

## 参考资料

- [Drools官方文档](https://docs.jboss.org/drools/)
- [规则引擎设计模式](https://martinfowler.com/bliki/RulesEngine.html)

---

## 系列文章

本文是《供应链系统实战》系列的第四篇：

- **第1篇**：渠道共享库存中心 - Redis分布式锁的生产实践 ✅
- **第2篇**：跨境电商关务系统 - 三单对碰的技术实现 ✅
- **第3篇**：WMS仓储系统 - 库位分配算法的演进之路 ✅
- **第4篇**：OMS订单系统 - 智能拆单规则引擎设计 ✅
- **第5篇**：供应链数据中台 - Flink实时计算架构实战（即将发布）

---

*如果这篇文章对你有帮助，欢迎在评论区分享你的OMS系统经验。*
