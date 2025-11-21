---
title: "熔断恢复机制：半开状态详解"
date: 2025-11-20T15:45:00+08:00
draft: false
tags: ["Sentinel", "熔断恢复", "半开状态"]
categories: ["技术"]
series: ["Sentinel从入门到精通"]
weight: 15
stage: 3
stageTitle: "熔断降级篇"
description: "深入理解熔断器的半开状态和恢复机制"
---

## 引言：熔断器如何"自愈"？

在前面几篇文章中，我们学习了熔断的原理、策略和降级处理。我们知道，当依赖服务出现故障时，熔断器会**开启（Open）**，停止对服务的调用。

但问题来了：**熔断器什么时候恢复？**

如果依赖服务的故障已经修复了，熔断器还一直开启，那就失去了熔断的意义——我们不能让系统永久降级！

另一方面，如果熔断器贸然恢复，而依赖服务还没完全恢复，可能会再次被拖垮。

**Sentinel是如何优雅地解决这个两难问题的？**

答案就是：**半开状态（Half-Open）**。

---

## 熔断器的完整生命周期

### 三种状态回顾

我们在第12篇文章中学习过，熔断器有三种状态：

1. **关闭（Closed）**：正常状态，所有请求通过
2. **开启（Open）**：熔断状态，所有请求快速失败
3. **半开（Half-Open）**：探测状态，试探性地发送请求

### 状态转换流程

```
初始状态：Closed（关闭）
    ↓
检测到故障（慢调用/异常超过阈值）
    ↓
Closed → Open（开启）
    ↓
等待熔断时长（如10秒）
    ↓
Open → Half-Open（半开）
    ↓
发送探测请求
    ↓
探测请求成功？
    ├─ 是 → Half-Open → Closed（恢复正常）
    └─ 否 → Half-Open → Open（继续熔断）
```

**关键点**：

- 熔断器开启后，不会永久熔断
- 等待一段时间（`timeWindow`），自动进入半开状态
- 在半开状态下，只允许**一个**探测请求通过
- 根据探测请求的结果，决定是恢复还是继续熔断

---

## 半开状态的作用

### 为什么需要半开状态？

**问题1**：如果没有半开状态，熔断器开启后永不恢复
- 结果：服务永久降级，即使依赖服务已经恢复

**问题2**：如果熔断器直接恢复（Open → Closed）
- 结果：大量请求涌入，可能再次拖垮刚恢复的服务

**半开状态的作用**：

> 用**一个**探测请求试探依赖服务是否恢复，避免大量请求直接涌入。

就像"壮士试毒"——先派一个人尝试，安全了大家再上。

### 半开状态的特点

1. **只允许一个请求通过**：Sentinel会选择一个请求作为探测请求
2. **其他请求快速失败**：在探测期间，其他请求继续降级
3. **快速决策**：根据这一个请求的结果，立即决定后续策略

---

## 半开状态的触发条件

### 触发时机

半开状态的触发非常简单：**熔断时长到期**。

**配置参数**：

```java
DegradeRule rule = new DegradeRule();
rule.setResource("callRemoteService");
rule.setGrade(RuleConstant.DEGRADE_GRADE_RT);
rule.setCount(1000);
rule.setSlowRatioThreshold(0.5);
rule.setTimeWindow(10); // ← 熔断时长：10秒
```

**工作流程**：

1. **T0时刻**：检测到故障，熔断器开启（Open）
2. **T0 ~ T0+10s**：熔断器保持开启，所有请求快速失败
3. **T0+10s**：熔断时长到期，熔断器自动切换到半开（Half-Open）
4. **T0+10s+**：第一个请求通过，作为探测请求

### 时间轴示意图

```
时间轴：
0s        5s        10s       15s       20s
|---------|---------|---------|---------|
   Open     Open   Half-Open  Closed/Open
  (熔断)   (熔断)   (探测)    (恢复/继续)
   ❌        ❌        🔍        ✅/❌
```

---

## 探测请求的选择机制

### Sentinel如何选择探测请求？

Sentinel使用**原子操作**保证只有一个请求被选为探测请求。

**实现原理**（简化版）：

```java
// Sentinel内部实现（简化）
public class CircuitBreaker {
    private volatile int state; // 0=Closed, 1=Open, 2=Half-Open
    private AtomicBoolean probing = new AtomicBoolean(false);

    public boolean tryPass() {
        // 1. 如果是关闭状态，直接通过
        if (state == CLOSED) {
            return true;
        }

        // 2. 如果是开启状态，检查是否到达恢复时间
        if (state == OPEN) {
            if (currentTime >= recoveryTime) {
                // 进入半开状态
                state = HALF_OPEN;
            } else {
                // 还在熔断时长内，拒绝
                return false;
            }
        }

        // 3. 如果是半开状态，只允许一个探测请求
        if (state == HALF_OPEN) {
            // CAS操作，保证只有一个线程能设置为true
            if (probing.compareAndSet(false, true)) {
                // 这个请求被选为探测请求
                return true;
            } else {
                // 其他请求继续熔断
                return false;
            }
        }

        return false;
    }
}
```

**关键技术**：

- `AtomicBoolean`：保证原子性，只有一个线程能成功设置
- `compareAndSet(false, true)`：CAS操作，线程安全

### 探测请求的特点

1. **第一个到达的请求**：不是随机选择，而是时间到期后第一个到达的请求
2. **只有一个**：通过CAS保证只有一个请求能通过
3. **其他请求继续降级**：在探测期间，其他请求仍然走降级逻辑

---

## 恢复与继续熔断的条件

### 恢复条件：探测请求成功

**定义"成功"**：

- **慢调用比例策略**：探测请求的响应时间 < 慢调用阈值
- **异常比例策略**：探测请求不抛异常
- **异常数策略**：探测请求不抛异常

**恢复流程**：

```
Half-Open（半开）
    ↓
探测请求成功
    ↓
state = CLOSED（关闭）
    ↓
后续所有请求正常通过
```

### 继续熔断的条件：探测请求失败

**定义"失败"**：

- **慢调用比例策略**：探测请求的响应时间 >= 慢调用阈值
- **异常比例策略**：探测请求抛异常
- **异常数策略**：探测请求抛异常

**继续熔断流程**：

```
Half-Open（半开）
    ↓
探测请求失败
    ↓
state = OPEN（开启）
    ↓
重新计时熔断时长（再等10秒）
    ↓
10秒后再次进入Half-Open
```

---

## 实战演示：模拟服务恢复过程

### 场景设计

模拟一个远程服务：
- **T0-T5秒**：服务故障，响应时间3秒
- **T5秒**：触发熔断，熔断器开启
- **T5-T15秒**：熔断期间，服务逐步恢复
- **T15秒**：熔断时长到期，进入半开状态
- **T15秒+**：探测请求成功，熔断器关闭

### 完整代码

```java
import com.alibaba.csp.sentinel.Entry;
import com.alibaba.csp.sentinel.SphU;
import com.alibaba.csp.sentinel.slots.block.BlockException;
import com.alibaba.csp.sentinel.slots.block.RuleConstant;
import com.alibaba.csp.sentinel.slots.block.degrade.DegradeRule;
import com.alibaba.csp.sentinel.slots.block.degrade.DegradeRuleManager;

import java.util.ArrayList;
import java.util.List;

public class HalfOpenDemo {

    private static volatile boolean serviceHealthy = false; // 模拟服务健康状态

    public static void main(String[] args) throws InterruptedException {
        initDegradeRule();

        // 启动一个线程，10秒后恢复服务
        new Thread(() -> {
            try {
                Thread.sleep(10000);
                serviceHealthy = true;
                System.out.println("\n⚠️  [10秒] 远程服务已恢复\n");
            } catch (InterruptedException e) {
                e.printStackTrace();
            }
        }).start();

        // 模拟持续调用
        for (int i = 0; i < 30; i++) {
            Thread.sleep(1000);
            System.out.println("\n--- 第" + (i + 1) + "秒 ---");
            callRemoteService();
        }
    }

    /**
     * 配置慢调用比例熔断规则
     */
    private static void initDegradeRule() {
        List<DegradeRule> rules = new ArrayList<>();
        DegradeRule rule = new DegradeRule();
        rule.setResource("callRemoteService");
        rule.setGrade(RuleConstant.DEGRADE_GRADE_RT);
        rule.setCount(500); // RT > 500ms算慢调用
        rule.setSlowRatioThreshold(0.6); // 慢调用比例60%
        rule.setMinRequestAmount(3);
        rule.setStatIntervalMs(10000);
        rule.setTimeWindow(10); // 熔断10秒
        rules.add(rule);
        DegradeRuleManager.loadRules(rules);
        System.out.println("✅ 熔断规则已加载：RT > 500ms，慢调用比例 > 60%，熔断10秒\n");
    }

    /**
     * 调用远程服务
     */
    private static void callRemoteService() {
        try (Entry entry = SphU.entry("callRemoteService")) {
            // 模拟调用
            if (serviceHealthy) {
                // 服务健康，响应50ms
                Thread.sleep(50);
                System.out.println("✅ 调用成功，响应时间：50ms");
            } else {
                // 服务故障，响应3秒
                Thread.sleep(3000);
                System.out.println("⚠️  调用成功，响应时间：3000ms（慢调用）");
            }
        } catch (BlockException e) {
            // 熔断降级
            System.out.println("🔴 熔断生效，快速失败");
        } catch (InterruptedException e) {
            e.printStackTrace();
        }
    }
}
```

### 运行效果

```
✅ 熔断规则已加载：RT > 500ms，慢调用比例 > 60%，熔断10秒

--- 第1秒 ---
⚠️  调用成功，响应时间：3000ms（慢调用）

--- 第2秒 ---
⚠️  调用成功，响应时间：3000ms（慢调用）

--- 第3秒 ---
⚠️  调用成功，响应时间：3000ms（慢调用）

--- 第4秒 ---  ← 慢调用比例达到60%，熔断器开启
⚠️  调用成功，响应时间：3000ms（慢调用）

--- 第5秒 ---
🔴 熔断生效，快速失败

--- 第6秒 ---
🔴 熔断生效，快速失败

--- 第7秒 ---
🔴 熔断生效，快速失败

--- 第8秒 ---
🔴 熔断生效，快速失败

--- 第9秒 ---
🔴 熔断生效，快速失败

--- 第10秒 ---
🔴 熔断生效，快速失败

⚠️  [10秒] 远程服务已恢复  ← 服务恢复

--- 第11秒 ---
🔴 熔断生效，快速失败

--- 第12秒 ---
🔴 熔断生效，快速失败

--- 第13秒 ---
🔴 熔断生效，快速失败

--- 第14秒 ---
🔴 熔断生效，快速失败

--- 第15秒 ---  ← 熔断时长10秒到期，进入半开状态
✅ 调用成功，响应时间：50ms  ← 探测请求成功

--- 第16秒 ---  ← 熔断器关闭，恢复正常
✅ 调用成功，响应时间：50ms

--- 第17秒 ---
✅ 调用成功，响应时间：50ms

--- 第18秒 ---
✅ 调用成功，响应时间：50ms

... 后续所有请求正常
```

### 关键时间点

| 时间点 | 状态 | 说明 |
|-------|-----|-----|
| 1-3秒 | Closed | 正常调用，但响应慢 |
| 4秒 | Closed → Open | 慢调用比例达到60%，触发熔断 |
| 5-14秒 | Open | 熔断期间，所有请求快速失败 |
| 15秒 | Open → Half-Open | 熔断时长到期，进入半开状态 |
| 15秒 | Half-Open → Closed | 探测请求成功，恢复正常 |
| 16秒+ | Closed | 所有请求正常通过 |

---

## 避免频繁抖动

### 什么是熔断抖动？

如果依赖服务**刚刚恢复**但还不稳定，可能会出现：

```
Closed → Open → Half-Open → Open → Half-Open → Open ...
```

这种频繁的状态切换称为**熔断抖动**，会导致：
- 用户体验不稳定（时好时坏）
- 依赖服务被反复冲击
- 监控告警频繁触发

### 如何避免抖动？

#### 1. 合理设置熔断时长

**原则**：熔断时长应该**大于故障恢复时间**。

```java
// 如果依赖服务通常需要30秒恢复，熔断时长应该设置为40-60秒
rule.setTimeWindow(40);
```

#### 2. 降低触发阈值的敏感度

```java
// 不要设置过低的阈值
rule.setSlowRatioThreshold(0.6); // 60%，留有余量
// 而不是
rule.setSlowRatioThreshold(0.3); // 30%，太敏感
```

#### 3. 增加最小请求数

```java
// 增加最小请求数，避免样本太少
rule.setMinRequestAmount(10); // 至少10个请求
// 而不是
rule.setMinRequestAmount(3); // 太少，容易误判
```

#### 4. 使用渐进式恢复

Sentinel目前不支持渐进式恢复（如每次放10%流量），但可以通过**多层熔断**实现类似效果：

```java
// 第一层：严格熔断
DegradeRule strictRule = new DegradeRule();
strictRule.setResource("callRemoteService");
strictRule.setSlowRatioThreshold(0.8); // 80%
strictRule.setTimeWindow(10);

// 第二层：宽松熔断
DegradeRule looseRule = new DegradeRule();
looseRule.setResource("callRemoteService");
looseRule.setSlowRatioThreshold(0.5); // 50%
looseRule.setTimeWindow(30); // 更长的恢复时间
```

---

## 半开状态的监控

### 如何知道熔断器进入了半开状态？

Sentinel没有直接提供半开状态的事件回调，但可以通过**日志**或**指标**监控。

#### 方法1：自定义SlotChain（高级）

```java
public class CircuitBreakerSlot extends AbstractLinkedProcessorSlot<DefaultNode> {

    @Override
    public void entry(Context context, ResourceWrapper resourceWrapper,
                      DefaultNode node, int count, boolean prioritized, Object... args)
            throws Throwable {
        // 在这里可以监控熔断器状态
        fireEntry(context, resourceWrapper, node, count, prioritized, args);
    }
}
```

#### 方法2：在降级方法中记录

```java
@SentinelResource(
    value = "callRemoteService",
    blockHandler = "handleBlock"
)
public String callRemoteService() {
    return remoteService.call();
}

public String handleBlock(BlockException ex) {
    if (ex instanceof DegradeException) {
        // 记录熔断事件
        logger.info("熔断器状态：熔断中");
    }
    return "降级数据";
}
```

#### 方法3：Sentinel Dashboard

在Sentinel Dashboard中可以看到**实时熔断状态**：

- 绿色：Closed（正常）
- 红色：Open（熔断）
- 黄色：Half-Open（半开，很短暂，不易观察到）

---

## 半开状态的最佳实践

### 1. 熔断时长设置

| 场景 | 推荐熔断时长 |
|-----|------------|
| 网络抖动 | 5-10秒 |
| 数据库慢查询 | 10-30秒 |
| 依赖服务重启 | 30-60秒 |
| 第三方API故障 | 60-120秒 |

### 2. 探测请求的最佳实践

- **保证探测请求的代表性**：不要对探测请求做特殊处理
- **记录探测结果**：方便排查问题
- **设置超时时间**：避免探测请求本身阻塞

### 3. 恢复后的流量控制

熔断器恢复后，可以结合**Warm Up**逐步提升流量：

```java
// 熔断规则
DegradeRule degradeRule = new DegradeRule();
degradeRule.setResource("callRemoteService");
degradeRule.setGrade(RuleConstant.DEGRADE_GRADE_RT);
degradeRule.setCount(1000);
degradeRule.setTimeWindow(10);

// 流控规则：Warm Up
FlowRule flowRule = new FlowRule();
flowRule.setResource("callRemoteService");
flowRule.setGrade(RuleConstant.FLOW_GRADE_QPS);
flowRule.setCount(100);
flowRule.setControlBehavior(RuleConstant.CONTROL_BEHAVIOR_WARM_UP);
flowRule.setWarmUpPeriodSec(30); // 30秒预热
```

---

## 总结

本文我们深入学习了熔断器的半开状态和恢复机制：

1. **半开状态的作用**：试探性地发送一个请求，判断服务是否恢复
2. **触发条件**：熔断时长到期后，自动进入半开状态
3. **探测请求选择**：通过CAS保证只有一个请求被选为探测请求
4. **恢复条件**：探测请求成功 → 熔断器关闭
5. **继续熔断**：探测请求失败 → 重新进入开启状态
6. **避免抖动**：合理设置熔断时长、阈值、最小请求数

**核心要点**：

> 半开状态是熔断器的"自愈机制"，它用最小的代价（一个探测请求）来判断依赖服务是否恢复，避免了"永久降级"和"流量冲击"两个极端。

**下一篇预告**：

我们将通过一个**完整的微服务调用链路案例**，学习如何防止服务雪崩：
- 场景：A → B → C，C故障导致全链路阻塞
- 问题分析：线程耗尽、连接池耗尽
- 解决方案：多层熔断、优雅降级
- 故障注入测试：如何验证熔断效果

敬请期待！
