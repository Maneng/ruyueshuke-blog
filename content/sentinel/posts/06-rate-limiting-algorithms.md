---
title: "限流算法原理：计数器、滑动窗口、令牌桶、漏桶"
date: 2025-01-21T14:50:00+08:00
draft: false
tags: ["Sentinel", "限流算法", "滑动窗口", "令牌桶"]
categories: ["技术"]
series: ["Sentinel从入门到精通"]
weight: 6
stage: 2
stageTitle: "流量控制深入篇"
description: "深入理解4种经典限流算法的原理、优缺点和适用场景"
---

## 引言：算法决定限流的精度

前面我们学会了使用Sentinel进行限流，只需要一行配置：

```java
rule.setCount(100);  // 每秒最多100次
```

但你有没有想过：Sentinel是**如何精确控制每秒100次**的？

- 如果100个请求在1秒的前0.01秒就全部到达，后面0.99秒怎么办？
- 如果1秒内有120个请求，是拒绝哪20个？前面的？后面的？
- 如果平时QPS是50，突然来了200的瞬间峰值，能否允许？

这些问题的答案，都隐藏在**限流算法**中。今天我们将深入理解4种经典限流算法，看看它们各自的特点和适用场景。

---

## 一、固定窗口计数器：最简单的限流算法

### 1.1 算法原理

固定窗口计数器是最直观的限流算法：

```
时间窗口：每秒钟
限流阈值：100次

秒钟：  0      1      2      3      4
       │─────│─────│─────│─────│─────│
计数： 0→100  0→50  0→120  0→80  0→100
结果： 全通过  全通过  拒20  全通过  全通过
```

**工作流程**：
1. 将时间划分为固定窗口（如1秒）
2. 每个窗口维护一个计数器
3. 请求到达时，计数器+1
4. 如果计数器超过阈值，拒绝请求
5. 窗口结束时，计数器归零

### 1.2 代码实现

```java
public class FixedWindowRateLimiter {
    private final int limit;           // 限流阈值
    private final long windowSize;      // 窗口大小（毫秒）
    private AtomicInteger counter;      // 当前窗口计数
    private long windowStartTime;       // 窗口开始时间

    public FixedWindowRateLimiter(int limit, long windowSize) {
        this.limit = limit;
        this.windowSize = windowSize;
        this.counter = new AtomicInteger(0);
        this.windowStartTime = System.currentTimeMillis();
    }

    public synchronized boolean tryAcquire() {
        long now = System.currentTimeMillis();

        // 判断是否需要重置窗口
        if (now - windowStartTime >= windowSize) {
            // 新窗口开始
            counter.set(0);
            windowStartTime = now;
        }

        // 判断是否超过限流阈值
        if (counter.get() < limit) {
            counter.incrementAndGet();
            return true;  // 通过
        } else {
            return false;  // 限流
        }
    }
}
```

**使用示例**：

```java
// 每秒最多10次
FixedWindowRateLimiter limiter = new FixedWindowRateLimiter(10, 1000);

for (int i = 0; i < 20; i++) {
    if (limiter.tryAcquire()) {
        System.out.println("请求" + i + "：通过");
    } else {
        System.out.println("请求" + i + "：被限流");
    }
    Thread.sleep(50);  // 每50ms一个请求
}
```

### 1.3 临界问题（致命缺陷）

固定窗口算法有一个**严重的临界问题**：

```
阈值：100次/秒

时间线：
第1秒：  0.0s ────────────────── 0.9s ──→ 1.0s
        0个请求                  100个请求  ← 第1秒的最后0.1秒

第2秒：  1.0s ──→ 1.1s ────────────────── 2.0s
        100个请求  ← 第2秒的最初0.1秒    0个请求

问题：在1.0s前后0.2秒内，通过了200个请求（是阈值的2倍！）
```

**图示**：

```
窗口1 (0-1s)           窗口2 (1-2s)
├─────────────┼────────┼────────┼─────────────┤
0s           0.9s    1.0s    1.1s           2.0s
              └─100个─┴─100个─┘
                  ↑ 0.2秒内200个请求！
```

**危害**：
- 瞬时流量可能达到阈值的**2倍**
- 对于严格的限流场景（如防止DB压垮），不可接受
- 攻击者可以利用这个漏洞绕过限流

### 1.4 优缺点总结

**优点**：
- ✅ 实现简单（10行代码）
- ✅ 性能高（只需要一个计数器）
- ✅ 内存占用小（O(1)）

**缺点**：
- ❌ **临界问题**（致命缺陷）
- ❌ 窗口切换时流量突变
- ❌ 无法应对突发流量

**适用场景**：
- 对限流精度要求不高的场景
- 流量相对均匀的场景
- **不推荐在生产环境使用**

---

## 二、滑动窗口：Sentinel的选择

### 2.1 算法原理

滑动窗口算法解决了固定窗口的临界问题：

```
将1秒划分为10个小窗口（每个100ms）

时间：  0    0.1  0.2  0.3  0.4  0.5  0.6  0.7  0.8  0.9  1.0
窗口： ├───┼───┼───┼───┼───┼───┼───┼───┼───┼───┤
计数： 10   8    12   9    11   10   13   8    9    10

当前时间：0.85s
滑动窗口：过去1秒 = [0.85s - 1s, 0.85s]
包含的小窗口：[-0.15s, 0.85s] 的10个窗口
总计数 = 8 + 12 + 9 + 11 + 10 + 13 + 8 + 9 + 10 (部分) = 约95

判断：95 < 100，通过
```

**核心思想**：
- 窗口随着时间**滑动**，而不是跳跃
- 任意时刻的限流判断，都基于**过去1秒的实际请求数**
- 精度取决于小窗口的数量（Sentinel默认2个）

### 2.2 Sentinel的实现：LeapArray

Sentinel使用`LeapArray`实现滑动窗口：

```java
// Sentinel的滑动窗口配置
// 统计时间窗口：1秒
// 样本数：2个小窗口（每个500ms）

时间：    0        500ms      1000ms
窗口：   ├─────────┼─────────┤
索引：    bucket[0]  bucket[1]

当前时间：700ms
- 当前bucket：bucket[1] (500-1000ms)
- 过去1秒的统计：bucket[0] + bucket[1]

当前时间：1200ms
- 需要重置bucket[0]（因为已经过期）
- 当前bucket：bucket[0] (1000-1500ms)
- 过去1秒的统计：bucket[0] + bucket[1]
```

**简化实现**：

```java
public class SlidingWindowRateLimiter {
    private final int limit;              // 限流阈值
    private final int windowSize;         // 窗口大小（毫秒）
    private final int bucketNum;          // 小窗口数量
    private final AtomicInteger[] buckets; // 每个小窗口的计数器
    private final long[] bucketTime;      // 每个小窗口的时间戳

    public SlidingWindowRateLimiter(int limit, int windowSize, int bucketNum) {
        this.limit = limit;
        this.windowSize = windowSize;
        this.bucketNum = bucketNum;
        this.buckets = new AtomicInteger[bucketNum];
        this.bucketTime = new long[bucketNum];

        for (int i = 0; i < bucketNum; i++) {
            buckets[i] = new AtomicInteger(0);
            bucketTime[i] = 0;
        }
    }

    public synchronized boolean tryAcquire() {
        long now = System.currentTimeMillis();

        // 1. 计算当前应该在哪个bucket
        int bucketIndex = (int) ((now / (windowSize / bucketNum)) % bucketNum);

        // 2. 重置过期的bucket
        if (now - bucketTime[bucketIndex] >= windowSize) {
            buckets[bucketIndex].set(0);
            bucketTime[bucketIndex] = now;
        }

        // 3. 统计过去1秒的请求总数
        int totalCount = 0;
        for (int i = 0; i < bucketNum; i++) {
            if (now - bucketTime[i] < windowSize) {
                totalCount += buckets[i].get();
            }
        }

        // 4. 判断是否超过限流阈值
        if (totalCount < limit) {
            buckets[bucketIndex].incrementAndGet();
            return true;
        } else {
            return false;
        }
    }
}
```

### 2.3 滑动窗口 vs 固定窗口

**对比临界问题**：

```
固定窗口：
第1秒最后0.1s：100个请求 ✅
第2秒最初0.1s：100个请求 ✅
0.2s内总共：200个请求（阈值的2倍！）❌

滑动窗口：
时间1.05s时，统计过去1秒 = [0.05s, 1.05s]
  包含：第1秒的100个 + 第2秒前0.05s的50个 = 150个
  判断：150 > 100，拒绝后面的50个 ✅
```

**滑动窗口彻底解决了临界问题**。

### 2.4 优缺点总结

**优点**：
- ✅ **无临界问题**（核心优势）
- ✅ 限流更平滑
- ✅ 精度可调（增加小窗口数量）

**缺点**：
- ❌ 实现复杂（相对固定窗口）
- ❌ 内存占用大（O(n)，n为小窗口数量）
- ❌ 需要维护多个计数器

**适用场景**：
- 生产环境的标准选择
- 对限流精度有要求的场景
- Sentinel、Hystrix的默认实现

---

## 三、令牌桶：允许突发流量

### 3.1 算法原理

令牌桶算法引入了"令牌"的概念：

```
令牌桶（容量：100个令牌）
┌─────────────────────────────┐
│ 🪙 🪙 🪙 🪙 🪙 🪙 ... (100个) │  ← 令牌存储
└─────────────────────────────┘
        ↑           ↓
    以固定速率     请求消费令牌
    产生令牌      （1个请求=1个令牌）
  （100个/秒）
```

**工作流程**：
1. **令牌生产**：以固定速率（如100个/秒）往桶里放令牌
2. **令牌消费**：每个请求需要消费1个令牌
3. **有令牌**：请求通过，令牌数-1
4. **无令牌**：请求拒绝（或等待）
5. **桶满**：多余的令牌丢弃（桶容量限制）

**关键特性**：**允许突发流量**

```
场景：平时QPS=10，桶容量=100

第0-9秒：没有请求
  → 桶里积累了100个令牌（10个/秒 × 10秒）

第10秒：突然来了100个请求
  → 全部通过！（消耗100个令牌）

第11秒：又来了50个请求
  → 只通过10个（桶里只有10个新令牌）
```

### 3.2 Guava的实现：RateLimiter

```java
// 创建限流器：每秒100个令牌
RateLimiter limiter = RateLimiter.create(100);

// 方式1：阻塞等待（获取1个令牌）
limiter.acquire();  // 如果没有令牌，会阻塞等待
doSomething();

// 方式2：非阻塞（尝试获取令牌）
if (limiter.tryAcquire()) {
    doSomething();
} else {
    return "限流";
}

// 方式3：超时等待
if (limiter.tryAcquire(100, TimeUnit.MILLISECONDS)) {
    doSomething();
} else {
    return "超时，限流";
}
```

**简化实现**：

```java
public class TokenBucketRateLimiter {
    private final int capacity;      // 桶容量
    private final int refillRate;    // 令牌生成速率（个/秒）
    private AtomicInteger tokens;    // 当前令牌数
    private long lastRefillTime;     // 上次填充时间

    public TokenBucketRateLimiter(int capacity, int refillRate) {
        this.capacity = capacity;
        this.refillRate = refillRate;
        this.tokens = new AtomicInteger(capacity);  // 初始满
        this.lastRefillTime = System.currentTimeMillis();
    }

    public synchronized boolean tryAcquire() {
        // 1. 计算应该补充的令牌数
        long now = System.currentTimeMillis();
        long elapsedTime = now - lastRefillTime;
        int tokensToAdd = (int) (elapsedTime * refillRate / 1000);

        if (tokensToAdd > 0) {
            // 2. 补充令牌（不超过容量）
            int newTokens = Math.min(capacity, tokens.get() + tokensToAdd);
            tokens.set(newTokens);
            lastRefillTime = now;
        }

        // 3. 尝试获取令牌
        if (tokens.get() > 0) {
            tokens.decrementAndGet();
            return true;
        } else {
            return false;
        }
    }
}
```

### 3.3 令牌桶的应用场景

**场景1：API限流，允许短暂突发**

```
正常情况：QPS=100
配置：速率=100/秒，容量=200

第1秒：10个请求 → 通过，桶里积累了90个令牌
第2秒：10个请求 → 通过，桶里积累了180个令牌
第3秒：突然250个请求
  → 前200个通过（180积累+20新生成）
  → 后50个拒绝
```

**场景2：流量整形**

```
上游突发流量：1秒内1000个请求
令牌桶配置：速率=100/秒

效果：将1000个请求平滑到10秒处理完
```

### 3.4 优缺点总结

**优点**：
- ✅ **允许突发流量**（核心优势）
- ✅ 可以预存令牌
- ✅ 流量更平滑

**缺点**：
- ❌ 需要计算令牌生成
- ❌ 突发流量可能压垮下游
- ❌ 桶容量难以设置

**适用场景**：
- 允许短暂突发的场景
- 流量整形
- Google Guava RateLimiter

---

## 四、漏桶：绝对的流量平滑

### 4.1 算法原理

漏桶算法像一个漏水的桶：

```
请求流入（不限速）
       ↓
    ┌─────┐
    │ 🌊 │  ← 请求在桶里排队
    │ 🌊 │
    │ 🌊 │
    └──┬──┘
       ↓
  以固定速率流出
  （100个/秒）
```

**工作流程**：
1. **请求入桶**：不限速，全部接收
2. **排队等待**：桶里的请求排队
3. **匀速流出**：以固定速率处理请求
4. **桶满**：拒绝新请求

**关键特性**：**绝对平滑的输出**

```
输入：不规则（突发）
     ││││    │││││     ││││

输出：绝对平滑（固定速率）
     │ │ │ │ │ │ │ │ │ │
```

### 4.2 漏桶 vs 令牌桶

| 维度 | 令牌桶 | 漏桶 |
|------|--------|------|
| **输入** | 不限制 | 不限制 |
| **输出** | 可突发 | 绝对平滑 |
| **排队** | 不支持 | 支持 |
| **适用** | 允许突发 | 流量整形 |

**图示对比**：

```
令牌桶：允许输出突发
输入：│││││││││││││││││││
输出：│││││        │││││

漏桶：输出绝对平滑
输入：│││││││││││││││││││
输出：│ │ │ │ │ │ │ │ │
```

### 4.3 Sentinel的匀速排队模式

Sentinel的"匀速排队"流控效果，就是漏桶算法的实现：

```java
FlowRule rule = new FlowRule();
rule.setResource("myResource");
rule.setGrade(RuleConstant.FLOW_GRADE_QPS);
rule.setCount(10);  // 每秒10个

// 关键：设置流控效果为匀速排队
rule.setControlBehavior(RuleConstant.CONTROL_BEHAVIOR_RATE_LIMITER);
rule.setMaxQueueingTimeMs(500);  // 最大排队时间500ms

FlowRuleManager.loadRules(Collections.singletonList(rule));
```

**效果**：

```
配置：10个/秒，间隔100ms

请求1：0ms    → 立即执行
请求2：10ms   → 等待90ms，在100ms执行
请求3：20ms   → 等待180ms，在200ms执行
请求4：100ms  → 立即执行
请求5：600ms  → 等待时间超过500ms，拒绝
```

### 4.4 优缺点总结

**优点**：
- ✅ **输出绝对平滑**（核心优势）
- ✅ 保护下游系统
- ✅ 适合流量整形

**缺点**：
- ❌ 无法应对突发流量
- ❌ 响应时间增加（排队等待）
- ❌ 用户体验差（等待）

**适用场景**：
- 写操作（数据库、消息队列）
- 下游承受能力有限
- 需要流量整形的场景

---

## 五、四种算法对比

### 5.1 对比表格

| 算法 | 复杂度 | 内存 | 精度 | 突发 | 平滑 | 适用场景 |
|------|--------|------|------|------|------|----------|
| **固定窗口** | 简单 | O(1) | 低 | ❌ | ❌ | 要求不高的场景 |
| **滑动窗口** | 中等 | O(n) | 高 | ❌ | ✅ | **生产标配** |
| **令牌桶** | 中等 | O(1) | 高 | ✅ | ✅ | 允许突发 |
| **漏桶** | 简单 | O(n) | 高 | ❌ | ✅✅ | 流量整形 |

### 5.2 应用场景对比

**场景1：API限流（首选滑动窗口）**

```
需求：每秒最多1000个请求
问题：流量不均匀，可能有突发

滑动窗口：
  ✅ 精确控制，无临界问题
  ✅ 实现相对简单
  ✅ Sentinel默认实现
```

**场景2：写数据库（首选漏桶）**

```
需求：保护数据库，防止写入过快
问题：上游流量突发，数据库承受不住

漏桶：
  ✅ 输出绝对平滑
  ✅ 保护下游系统
  ✅ Sentinel的匀速排队模式
```

**场景3：对外API（首选令牌桶）**

```
需求：允许正常用户的短暂突发
问题：用户体验，不能太严格

令牌桶：
  ✅ 允许短暂超过限流
  ✅ 用户体验好
  ✅ Google API的选择
```

### 5.3 生产环境的选择

**推荐组合**：

```
┌─────────────────────────────────┐
│ 第1层：网关（令牌桶）            │
│   允许短暂突发，用户体验好       │
├─────────────────────────────────┤
│ 第2层：应用（滑动窗口）          │
│   精确限流，保护应用本身         │
├─────────────────────────────────┤
│ 第3层：数据库写入（漏桶）        │
│   绝对平滑，保护数据库          │
└─────────────────────────────────┘
```

---

## 六、Sentinel的选择：为什么用滑动窗口

### 6.1 Sentinel的设计考量

Sentinel选择滑动窗口作为默认算法，主要原因：

**1. 精度与性能的平衡**

```
滑动窗口（2个小窗口）：
  内存：2个计数器
  精度：足够（临界问题影响<5%）
  性能：优秀（简单加法）
```

**2. 适配多种流控效果**

```
滑动窗口 + 快速失败 = 标准限流
滑动窗口 + 匀速排队 = 漏桶
滑动窗口 + Warm Up = 预热
```

**3. 统一的统计框架**

```
滑动窗口的数据结构（LeapArray）可以用于：
  - QPS统计
  - RT统计
  - 异常数统计
  - 线程数统计
```

### 6.2 Sentinel的LeapArray实现

```java
// 核心数据结构
public class LeapArray<T> {
    // 样本窗口数量（默认2）
    protected int sampleCount;
    // 总时间窗口（默认1000ms）
    protected int intervalInMs;
    // 每个小窗口的时间长度
    private int windowLengthInMs;
    // 存储数据的环形数组
    protected final AtomicReferenceArray<WindowWrap<T>> array;
}
```

**为什么默认只用2个小窗口**？

```
精度 vs 性能的权衡：

小窗口数=1（固定窗口）：
  性能：★★★★★
  精度：★ （有临界问题）

小窗口数=2（Sentinel默认）：
  性能：★★★★☆
  精度：★★★★☆（临界影响<5%）

小窗口数=10：
  性能：★★★☆☆
  精度：★★★★★（临界影响<0.5%）

小窗口数=100：
  性能：★★☆☆☆
  精度：★★★★★（临界影响<0.05%）
```

**Sentinel的选择：2个小窗口是最优解**。

---

## 七、总结

**四种算法的核心对比**：

1. **固定窗口**：简单但有致命的临界问题，**不推荐生产使用**
2. **滑动窗口**：精度与性能平衡，**Sentinel的默认选择**
3. **令牌桶**：允许突发流量，适合对外API
4. **漏桶**：输出绝对平滑，适合保护下游

**选择建议**：

| 场景 | 推荐算法 | 理由 |
|------|---------|------|
| 通用API限流 | 滑动窗口 | 精度高，无临界问题 |
| 对外开放API | 令牌桶 | 用户体验好 |
| 数据库写入 | 漏桶 | 保护下游 |
| 要求不高 | 固定窗口 | 简单高效（慎用） |

**Sentinel的实现**：
- 默认：滑动窗口（2个小窗口）
- 支持：匀速排队（漏桶）
- 支持：Warm Up（令牌桶的变种）

**下一篇预告**：《QPS限流：保护API的第一道防线》

我们将学习如何在Sentinel中配置QPS限流规则，包括阈值设置技巧、压测方法、监控调优等实战内容。

---

## 思考题

1. 如果你的系统QPS=100，使用固定窗口算法，临界问题最严重时瞬时QPS能达到多少？
2. 令牌桶和漏桶的根本区别是什么？（提示：谁控制速率）
3. Sentinel为什么不默认使用令牌桶算法？

欢迎在评论区分享你的理解！

---

## 附录：算法可视化对比

```
固定窗口（阈值=5）：
时间：  0      1      2      3
       │─────│─────│─────│─────│
请求：  0 5    0 8    0 3    0 5
通过：  5      5      3      5
拒绝：  0      3      0      0
问题：  第1-2秒边界可能10个请求

滑动窗口（阈值=5，2个小窗口）：
时间：  0    0.5   1    1.5   2
       ├────┼────┼────┼────┼────┤
请求：  3    2    4    4    1
通过：  5(3+2) 5(2+3) 5(4+1) 5
拒绝：  0      1      0      0
效果：  平滑，无临界问题

令牌桶（速率=5/秒，容量=10）：
时间：  0    1    2    3    4
请求：  0    0    0    0    15
令牌：  10   10   10   10   10
通过：  0    0    0    0    10
拒绝：  0    0    0    0    5
效果：  允许突发（10个）

漏桶（速率=5/秒，容量=10）：
时间：  0    0.2  0.4  0.6  0.8  1.0
请求：  15   0    0    0    0    0
排队：  10   10   9    8    7    6
处理：  0    1    1    1    1    1
拒绝：  5
效果：  匀速处理（0.2s一个）
```
