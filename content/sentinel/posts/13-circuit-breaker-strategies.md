---
title: "熔断策略：慢调用比例、异常比例、异常数"
date: 2025-11-21T15:35:00+08:00
draft: false
tags: ["Sentinel", "熔断策略", "降级规则"]
categories: ["技术"]
series: ["Sentinel从入门到精通"]
weight: 13
stage: 3
stageTitle: "熔断降级篇"
description: "掌握3种熔断策略的触发条件和配置方法"
---

## 引言：不同的"病症"需要不同的"药方"

在上一篇文章中，我们学习了熔断降级的原理和熔断器的状态机。我们知道，熔断的本质是**检测故障 → 快速失败 → 自动恢复**。

但问题来了：**如何判断依赖服务"生病"了？**

就像医生诊断疾病，需要看不同的指标：
- 体温高不高？（响应时间）
- 心率正常吗？（异常比例）
- 咳嗽了几声？（异常次数）

Sentinel也提供了**三种熔断策略**，分别针对不同的故障模式：

1. **慢调用比例**（Slow Request Ratio）：依赖服务变慢了
2. **异常比例**（Exception Ratio）：依赖服务频繁抛异常
3. **异常数**（Exception Count）：依赖服务在短时间内抛了太多异常

本文将深入讲解这三种策略的原理、配置方法和适用场景。

---

## 策略一：慢调用比例（Slow Request Ratio）

### 什么是慢调用？

**慢调用**是指**响应时间（RT）超过设定阈值的请求**。

例如：
- 设置慢调用阈值为1000ms
- 某个请求的响应时间是1200ms
- 这个请求就被认为是"慢调用"

### 慢调用比例的触发条件

**熔断触发条件**：在统计时长内，慢调用的比例超过设定阈值，且请求数达到最小请求数。

**公式**：

```
慢调用比例 = 慢调用数 / 总请求数

如果：慢调用比例 >= 设定阈值，且 总请求数 >= 最小请求数
则：触发熔断
```

**示例**：

- 统计时长：10秒
- 慢调用RT阈值：1000ms
- 慢调用比例阈值：50%
- 最小请求数：5

**场景1**：10秒内有10个请求，其中6个RT > 1000ms
- 慢调用比例 = 6/10 = 60% > 50% ✅
- 请求数 = 10 >= 5 ✅
- **结论：触发熔断**

**场景2**：10秒内有3个请求，其中2个RT > 1000ms
- 慢调用比例 = 2/3 = 67% > 50% ✅
- 请求数 = 3 < 5 ❌
- **结论：不触发熔断**（请求数太少，可能是偶发）

### 配置参数详解

```java
DegradeRule rule = new DegradeRule();
rule.setResource("callRemoteService");
rule.setGrade(RuleConstant.DEGRADE_GRADE_RT); // 策略：慢调用比例

// 核心参数
rule.setCount(1000); // 慢调用RT阈值：1000ms
rule.setSlowRatioThreshold(0.5); // 慢调用比例阈值：50%
rule.setMinRequestAmount(5); // 最小请求数：5
rule.setStatIntervalMs(10000); // 统计时长：10秒
rule.setTimeWindow(10); // 熔断时长：10秒
```

**参数说明**：

| 参数 | 含义 | 默认值 | 说明 |
|-----|-----|-------|-----|
| `count` | 慢调用RT阈值 | 无 | 单位毫秒，响应时间超过此值算慢调用 |
| `slowRatioThreshold` | 慢调用比例阈值 | 1.0 | 范围[0.0, 1.0]，0.5表示50% |
| `minRequestAmount` | 最小请求数 | 5 | 统计时长内至少要有多少请求 |
| `statIntervalMs` | 统计时长 | 1000 | 单位毫秒，统计窗口大小 |
| `timeWindow` | 熔断时长 | 无 | 单位秒，熔断后多久尝试恢复 |

### 适用场景

慢调用比例策略适合以下场景：

1. **数据库慢查询**
   - 症状：数据库负载高，查询变慢
   - 表现：接口响应时间从10ms飙升到3秒
   - 熔断效果：停止查询数据库，返回缓存数据

2. **外部API响应慢**
   - 症状：第三方服务响应慢（如支付、物流）
   - 表现：调用超时或响应时间过长
   - 熔断效果：停止调用，返回"服务繁忙，请稍后重试"

3. **网络抖动**
   - 症状：网络质量下降
   - 表现：请求偶尔超时
   - 熔断效果：避免大量请求阻塞

### 实战案例：保护数据库查询

```java
import com.alibaba.csp.sentinel.Entry;
import com.alibaba.csp.sentinel.SphU;
import com.alibaba.csp.sentinel.slots.block.BlockException;
import com.alibaba.csp.sentinel.slots.block.RuleConstant;
import com.alibaba.csp.sentinel.slots.block.degrade.DegradeRule;
import com.alibaba.csp.sentinel.slots.block.degrade.DegradeRuleManager;

import java.util.ArrayList;
import java.util.List;

public class SlowCallDemo {

    public static void main(String[] args) throws InterruptedException {
        initDegradeRule();

        // 模拟调用
        for (int i = 0; i < 20; i++) {
            queryFromDatabase(i < 10); // 前10次正常，后10次慢查询
            Thread.sleep(300);
        }
    }

    /**
     * 配置慢调用比例熔断规则
     */
    private static void initDegradeRule() {
        List<DegradeRule> rules = new ArrayList<>();
        DegradeRule rule = new DegradeRule();
        rule.setResource("queryDatabase");
        rule.setGrade(RuleConstant.DEGRADE_GRADE_RT);
        rule.setCount(500); // RT超过500ms算慢调用
        rule.setSlowRatioThreshold(0.6); // 慢调用比例60%
        rule.setMinRequestAmount(5);
        rule.setStatIntervalMs(10000);
        rule.setTimeWindow(10);
        rules.add(rule);
        DegradeRuleManager.loadRules(rules);
        System.out.println("✅ 慢调用比例熔断规则已加载");
    }

    /**
     * 查询数据库
     */
    private static void queryFromDatabase(boolean isNormal) {
        try (Entry entry = SphU.entry("queryDatabase")) {
            if (isNormal) {
                Thread.sleep(50); // 正常查询50ms
                System.out.println("✅ 查询成功，耗时：50ms");
            } else {
                Thread.sleep(2000); // 慢查询2秒
                System.out.println("⚠️  查询成功，耗时：2000ms（慢查询）");
            }
        } catch (BlockException e) {
            // 熔断降级：返回缓存数据
            System.out.println("🔴 熔断生效，返回缓存数据");
        } catch (InterruptedException e) {
            e.printStackTrace();
        }
    }
}
```

---

## 策略二：异常比例（Exception Ratio）

### 什么是异常比例？

**异常比例**是指**抛出异常的请求占总请求数的比例**。

例如：
- 10秒内有100个请求
- 其中30个请求抛出异常
- 异常比例 = 30/100 = 30%

### 异常比例的触发条件

**熔断触发条件**：在统计时长内，异常比例超过设定阈值，且请求数达到最小请求数。

**公式**：

```
异常比例 = 异常请求数 / 总请求数

如果：异常比例 >= 设定阈值，且 总请求数 >= 最小请求数
则：触发熔断
```

### 什么样的异常会被统计？

Sentinel统计的异常包括：

1. **业务异常**：业务代码抛出的Exception
2. **运行时异常**：RuntimeException及其子类
3. **检查异常**：需要显式捕获的Exception

**但不包括**：

- `BlockException`：Sentinel自身的限流、熔断异常（不会被统计）
- `Error`：JVM错误（如OutOfMemoryError）

### 配置参数详解

```java
DegradeRule rule = new DegradeRule();
rule.setResource("callThirdPartyApi");
rule.setGrade(RuleConstant.DEGRADE_GRADE_EXCEPTION_RATIO); // 策略：异常比例

// 核心参数
rule.setCount(0.3); // 异常比例阈值：30%（注意这里是0.3而不是30）
rule.setMinRequestAmount(5); // 最小请求数：5
rule.setStatIntervalMs(10000); // 统计时长：10秒
rule.setTimeWindow(10); // 熔断时长：10秒
```

**参数说明**：

| 参数 | 含义 | 默认值 | 说明 |
|-----|-----|-------|-----|
| `count` | 异常比例阈值 | 无 | 范围[0.0, 1.0]，0.3表示30% |
| `minRequestAmount` | 最小请求数 | 5 | 统计时长内至少要有多少请求 |
| `statIntervalMs` | 统计时长 | 1000 | 单位毫秒 |
| `timeWindow` | 熔断时长 | 无 | 单位秒 |

### 适用场景

异常比例策略适合以下场景：

1. **第三方API不稳定**
   - 症状：第三方服务经常返回错误码或抛异常
   - 表现：接口调用频繁失败
   - 熔断效果：停止调用，避免浪费资源

2. **网络连接失败**
   - 症状：网络不稳定，连接经常超时
   - 表现：大量ConnectException、SocketTimeoutException
   - 熔断效果：快速失败，避免等待

3. **依赖服务部分故障**
   - 症状：依赖服务部分实例挂了
   - 表现：部分请求成功，部分请求失败
   - 熔断效果：等待故障实例恢复

### 实战案例：保护第三方API调用

```java
import com.alibaba.csp.sentinel.Entry;
import com.alibaba.csp.sentinel.SphU;
import com.alibaba.csp.sentinel.slots.block.BlockException;
import com.alibaba.csp.sentinel.slots.block.RuleConstant;
import com.alibaba.csp.sentinel.slots.block.degrade.DegradeRule;
import com.alibaba.csp.sentinel.slots.block.degrade.DegradeRuleManager;

import java.util.ArrayList;
import java.util.List;
import java.util.Random;

public class ExceptionRatioDemo {

    private static final Random RANDOM = new Random();

    public static void main(String[] args) throws InterruptedException {
        initDegradeRule();

        // 模拟调用：30%概率抛异常
        for (int i = 0; i < 20; i++) {
            callThirdPartyApi();
            Thread.sleep(300);
        }
    }

    /**
     * 配置异常比例熔断规则
     */
    private static void initDegradeRule() {
        List<DegradeRule> rules = new ArrayList<>();
        DegradeRule rule = new DegradeRule();
        rule.setResource("callThirdPartyApi");
        rule.setGrade(RuleConstant.DEGRADE_GRADE_EXCEPTION_RATIO);
        rule.setCount(0.3); // 异常比例30%
        rule.setMinRequestAmount(5);
        rule.setStatIntervalMs(10000);
        rule.setTimeWindow(10);
        rules.add(rule);
        DegradeRuleManager.loadRules(rules);
        System.out.println("✅ 异常比例熔断规则已加载");
    }

    /**
     * 调用第三方API
     */
    private static void callThirdPartyApi() {
        try (Entry entry = SphU.entry("callThirdPartyApi")) {
            // 模拟30%概率抛异常
            if (RANDOM.nextInt(100) < 40) { // 40%概率触发熔断
                throw new RuntimeException("第三方API返回错误");
            }
            System.out.println("✅ 调用成功");
        } catch (BlockException e) {
            // 熔断降级
            System.out.println("🔴 熔断生效，返回降级结果");
        } catch (Exception e) {
            System.out.println("❌ 调用失败：" + e.getMessage());
        }
    }
}
```

---

## 策略三：异常数（Exception Count）

### 什么是异常数？

**异常数**是指**在统计时长内，抛出异常的绝对次数**。

与异常比例不同，异常数不关心总请求数，只关心异常的绝对值。

### 异常数的触发条件

**熔断触发条件**：在统计时长内，异常数超过设定阈值，且请求数达到最小请求数。

**公式**：

```
如果：异常数 >= 设定阈值，且 总请求数 >= 最小请求数
则：触发熔断
```

**示例**：

- 统计时长：60秒
- 异常数阈值：10
- 最小请求数：5

**场景1**：60秒内有100个请求，其中15个抛异常
- 异常数 = 15 >= 10 ✅
- 请求数 = 100 >= 5 ✅
- **结论：触发熔断**

**场景2**：60秒内有20个请求，其中15个抛异常
- 异常数 = 15 >= 10 ✅
- 请求数 = 20 >= 5 ✅
- **结论：触发熔断**

### 配置参数详解

```java
DegradeRule rule = new DegradeRule();
rule.setResource("callPaymentApi");
rule.setGrade(RuleConstant.DEGRADE_GRADE_EXCEPTION_COUNT); // 策略：异常数

// 核心参数
rule.setCount(10); // 异常数阈值：10次
rule.setMinRequestAmount(5); // 最小请求数：5
rule.setStatIntervalMs(60000); // 统计时长：60秒（通常设置更长）
rule.setTimeWindow(10); // 熔断时长：10秒
```

**参数说明**：

| 参数 | 含义 | 默认值 | 说明 |
|-----|-----|-------|-----|
| `count` | 异常数阈值 | 无 | 整数，异常次数超过此值触发熔断 |
| `minRequestAmount` | 最小请求数 | 5 | 统计时长内至少要有多少请求 |
| `statIntervalMs` | 统计时长 | 1000 | 单位毫秒，**通常设置更长**（如60秒） |
| `timeWindow` | 熔断时长 | 无 | 单位秒 |

### 适用场景

异常数策略适合以下场景：

1. **低流量接口**
   - 特点：QPS很低（如每分钟几个请求）
   - 问题：异常比例不适用（总请求数太少）
   - 方案：设置异常数阈值，如10次/分钟

2. **对异常极度敏感**
   - 特点：任何异常都不能容忍
   - 场景：支付、金融、核心业务
   - 方案：设置很小的异常数阈值，如3次

3. **长时间窗口统计**
   - 特点：需要在更长的时间维度观察
   - 场景：慢接口、定时任务
   - 方案：设置60秒甚至更长的统计时长

### 实战案例：保护支付接口

```java
import com.alibaba.csp.sentinel.Entry;
import com.alibaba.csp.sentinel.SphU;
import com.alibaba.csp.sentinel.slots.block.BlockException;
import com.alibaba.csp.sentinel.slots.block.RuleConstant;
import com.alibaba.csp.sentinel.slots.block.degrade.DegradeRule;
import com.alibaba.csp.sentinel.slots.block.degrade.DegradeRuleManager;

import java.util.ArrayList;
import java.util.List;
import java.util.Random;

public class ExceptionCountDemo {

    private static final Random RANDOM = new Random();

    public static void main(String[] args) throws InterruptedException {
        initDegradeRule();

        // 模拟低流量调用：每秒1个请求，20%概率抛异常
        for (int i = 0; i < 20; i++) {
            callPaymentApi();
            Thread.sleep(1000);
        }
    }

    /**
     * 配置异常数熔断规则
     */
    private static void initDegradeRule() {
        List<DegradeRule> rules = new ArrayList<>();
        DegradeRule rule = new DegradeRule();
        rule.setResource("callPaymentApi");
        rule.setGrade(RuleConstant.DEGRADE_GRADE_EXCEPTION_COUNT);
        rule.setCount(5); // 异常数5次
        rule.setMinRequestAmount(3);
        rule.setStatIntervalMs(60000); // 60秒统计窗口
        rule.setTimeWindow(10);
        rules.add(rule);
        DegradeRuleManager.loadRules(rules);
        System.out.println("✅ 异常数熔断规则已加载");
    }

    /**
     * 调用支付API
     */
    private static void callPaymentApi() {
        try (Entry entry = SphU.entry("callPaymentApi")) {
            // 模拟20%概率抛异常
            if (RANDOM.nextInt(100) < 20) {
                throw new RuntimeException("支付失败");
            }
            System.out.println("✅ 支付成功");
        } catch (BlockException e) {
            // 熔断降级
            System.out.println("🔴 熔断生效，支付服务暂时不可用");
        } catch (Exception e) {
            System.out.println("❌ 支付失败：" + e.getMessage());
        }
    }
}
```

---

## 三种策略全面对比

### 对比表格

| 维度 | 慢调用比例 | 异常比例 | 异常数 |
|-----|----------|---------|-------|
| **判断指标** | 响应时间（RT） | 异常占比 | 异常绝对值 |
| **统计方式** | 比例 | 比例 | 绝对值 |
| **适用流量** | 中高流量 | 中高流量 | 低流量 |
| **统计时长** | 较短（10秒） | 较短（10秒） | 较长（60秒） |
| **典型场景** | 数据库慢查询 | 第三方API不稳定 | 低流量接口 |
| **敏感度** | 中 | 中 | 高 |
| **误判风险** | 低 | 低 | 中（流量低时） |

### 选择决策树

```
如何选择熔断策略？
    ↓
依赖服务的故障模式是什么？
    ├─ 响应变慢 → 慢调用比例
    ├─ 频繁抛异常 → 异常比例 或 异常数
    └─ 不确定 ↓
       接口的QPS是多少？
           ├─ QPS > 10 → 慢调用比例 或 异常比例
           └─ QPS < 10 → 异常数
```

### 实际案例对比

**案例1：查询商品详情接口**

- **故障模式**：数据库慢查询，响应时间从10ms升到3秒
- **QPS**：1000
- **选择策略**：慢调用比例
- **配置**：RT > 1秒算慢调用，慢调用比例 > 50%触发熔断

**案例2：调用第三方物流API**

- **故障模式**：物流服务不稳定，经常返回错误
- **QPS**：100
- **选择策略**：异常比例
- **配置**：异常比例 > 30%触发熔断

**案例3：调用支付回调接口**

- **故障模式**：偶尔调用失败
- **QPS**：1（低流量）
- **选择策略**：异常数
- **配置**：60秒内异常数 > 3触发熔断

---

## 配置参数最佳实践

### 1. 统计时长（statIntervalMs）

**建议**：

- **慢调用比例**：10秒
- **异常比例**：10秒
- **异常数**：60秒

**原因**：
- 比例策略需要足够的样本，10秒通常够用
- 异常数策略适合低流量，需要更长的时间窗口

### 2. 最小请求数（minRequestAmount）

**建议**：

- **高流量接口**（QPS > 100）：10-20
- **中流量接口**（QPS 10-100）：5-10
- **低流量接口**（QPS < 10）：3-5

**原因**：
- 避免因为偶发故障触发熔断
- 样本太少时统计不准确

### 3. 熔断时长（timeWindow）

**建议**：

- **短期故障**（如网络抖动）：5-10秒
- **中期故障**（如数据库慢查询）：10-30秒
- **长期故障**（如依赖服务重启）：30-60秒

**原则**：
- 熔断时长应该大于故障恢复时间
- 但也不能太长，避免影响用户体验

### 4. 阈值设置

**慢调用比例**：

```java
rule.setCount(1000); // RT阈值：根据接口SLA设置
rule.setSlowRatioThreshold(0.5); // 50%-80%之间
```

**异常比例**：

```java
rule.setCount(0.3); // 30%-50%之间
```

**异常数**：

```java
rule.setCount(5); // 根据接口重要性设置：核心接口3-5，非核心接口10-20
```

---

## 综合实战：多策略组合使用

在实际项目中，**可以为同一个资源配置多个熔断规则**（但通常不推荐，容易混淆）。

更好的做法是：**根据不同的依赖服务选择最合适的策略**。

### 示例：订单服务的熔断配置

```java
public class OrderServiceDegradeConfig {

    public static void init() {
        List<DegradeRule> rules = new ArrayList<>();

        // 1. 查询商品服务：慢调用比例
        DegradeRule productRule = new DegradeRule();
        productRule.setResource("callProductService");
        productRule.setGrade(RuleConstant.DEGRADE_GRADE_RT);
        productRule.setCount(500); // RT > 500ms
        productRule.setSlowRatioThreshold(0.6);
        productRule.setMinRequestAmount(10);
        productRule.setStatIntervalMs(10000);
        productRule.setTimeWindow(10);
        rules.add(productRule);

        // 2. 查询库存服务：慢调用比例
        DegradeRule inventoryRule = new DegradeRule();
        inventoryRule.setResource("callInventoryService");
        inventoryRule.setGrade(RuleConstant.DEGRADE_GRADE_RT);
        inventoryRule.setCount(800);
        inventoryRule.setSlowRatioThreshold(0.5);
        inventoryRule.setMinRequestAmount(10);
        inventoryRule.setStatIntervalMs(10000);
        inventoryRule.setTimeWindow(15);
        rules.add(inventoryRule);

        // 3. 调用支付API：异常比例
        DegradeRule paymentRule = new DegradeRule();
        paymentRule.setResource("callPaymentApi");
        paymentRule.setGrade(RuleConstant.DEGRADE_GRADE_EXCEPTION_RATIO);
        paymentRule.setCount(0.2); // 异常比例20%
        paymentRule.setMinRequestAmount(5);
        paymentRule.setStatIntervalMs(10000);
        paymentRule.setTimeWindow(20);
        rules.add(paymentRule);

        // 4. 发送短信：异常数（低流量）
        DegradeRule smsRule = new DegradeRule();
        smsRule.setResource("sendSms");
        smsRule.setGrade(RuleConstant.DEGRADE_GRADE_EXCEPTION_COUNT);
        smsRule.setCount(3); // 异常数3次
        smsRule.setMinRequestAmount(3);
        smsRule.setStatIntervalMs(60000); // 60秒
        smsRule.setTimeWindow(30);
        rules.add(smsRule);

        DegradeRuleManager.loadRules(rules);
        System.out.println("✅ 订单服务熔断规则已加载");
    }
}
```

---

## 总结

本文我们深入学习了Sentinel的三种熔断策略：

1. **慢调用比例**：依赖服务响应变慢
   - 判断指标：响应时间（RT）
   - 触发条件：慢调用比例超过阈值
   - 适用场景：数据库慢查询、外部API响应慢

2. **异常比例**：依赖服务频繁抛异常
   - 判断指标：异常占比
   - 触发条件：异常比例超过阈值
   - 适用场景：第三方API不稳定、网络连接失败

3. **异常数**：短时间内抛太多异常
   - 判断指标：异常绝对值
   - 触发条件：异常数超过阈值
   - 适用场景：低流量接口、对异常极度敏感

**配置要点**：

- 根据故障模式选择策略
- 根据流量大小调整参数
- 熔断时长应大于故障恢复时间
- 阈值设置要留有余量

**下一篇预告**：

我们将学习**如何自定义降级处理逻辑**：
- 默认降级处理的局限性
- 如何实现优雅降级
- 返回默认值、缓存数据、友好提示
- 降级事件的监控和告警

让降级不只是简单的失败，而是一种"优雅的后备方案"！
