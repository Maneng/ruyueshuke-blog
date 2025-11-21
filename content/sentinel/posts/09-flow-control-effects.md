---
title: "流控效果：快速失败、Warm Up、匀速排队"
date: 2025-01-21T15:20:00+08:00
draft: false
tags: ["Sentinel", "流控效果", "Warm Up", "匀速排队"]
categories: ["技术"]
series: ["Sentinel从入门到精通"]
weight: 9
stage: 2
stageTitle: "流量控制深入篇"
description: "掌握3种流控效果的原理和使用场景，实现更精细的流量控制"
---

## 引言：限流后如何处理请求

前面我们学习了QPS限流和线程数限流，但都是简单的"超过阈值就拒绝"。实际场景中，我们可能需要更灵活的策略：

**场景1：系统刚启动，能直接承受高流量吗？**

```
系统冷启动：
  缓存为空、连接池未预热、JIT未优化
  → 直接放入100 QPS → 系统可能卡死

需要：预热（Warm Up）
  → 逐步增加流量，给系统预热时间
```

**场景2：突发流量能否平滑处理？**

```
消息队列消费：
  瞬间收到1000条消息
  → 快速失败：拒绝后面的消息
  → 匀速排队：排队等待，平滑处理
```

Sentinel提供了**三种流控效果**，满足不同场景需求：
1. **快速失败**（默认）：超过阈值直接拒绝
2. **Warm Up**（预热）：逐步增加流量
3. **匀速排队**：排队等待，平滑处理

---

## 一、快速失败：默认的流控效果

### 1.1 原理

**快速失败**是最简单直接的流控效果：

```
阈值：100 QPS

第1-100个请求：通过 ✅
第101个请求：拒绝 ❌（立即返回）
第102个请求：拒绝 ❌
...
下一秒：计数器重置，重新开始
```

**特点**：
- ✅ 简单直接
- ✅ 响应快（不等待）
- ✅ 保护系统（超过阈值立即拒绝）

### 1.2 配置方式

```java
FlowRule rule = new FlowRule();
rule.setResource("myResource");
rule.setGrade(RuleConstant.FLOW_GRADE_QPS);
rule.setCount(100);

// 流控效果：快速失败（默认，可省略）
rule.setControlBehavior(RuleConstant.CONTROL_BEHAVIOR_DEFAULT);

FlowRuleManager.loadRules(Collections.singletonList(rule));
```

### 1.3 适用场景

**场景1：普通API接口**

```java
@GetMapping("/api/user/{id}")
@SentinelResource(value = "user_query",
                  blockHandler = "handleBlock")
public Result getUser(@PathVariable Long id) {
    User user = userService.getById(id);
    return Result.success(user);
}

public Result handleBlock(Long id, BlockException ex) {
    return Result.fail("系统繁忙，请稍后重试");
}
```

**场景2：秒杀活动**

```java
// 秒杀接口，超过阈值直接拒绝
// 不允许等待（影响用户体验）
@PostMapping("/api/seckill/buy")
@SentinelResource(value = "seckill_buy",
                  blockHandler = "handleBlock")
public Result seckill(@RequestParam Long productId) {
    // 秒杀逻辑
    return Result.success();
}

public Result handleBlock(Long productId, BlockException ex) {
    return Result.fail("商品已抢完");
}
```

---

## 二、Warm Up：冷启动预热

### 2.1 原理

**Warm Up**（预热）模式：系统冷启动时，从一个较低的阈值开始，逐步增加到设定的阈值。

```
配置：
  最终阈值 = 1000 QPS
  预热时长 = 10秒
  冷启动因子 = 3（默认）

启动时的阈值 = 1000 / 3 = 333 QPS

时间线：
  0秒：阈值 = 333 QPS
  2秒：阈值 = 466 QPS
  4秒：阈值 = 600 QPS
  6秒：阈值 = 733 QPS
  8秒：阈值 = 866 QPS
  10秒：阈值 = 1000 QPS（最终阈值）
```

**图示**：

```
QPS阈值
 1000 ┤                    ╱────────
      │                 ╱
  750 ┤              ╱
      │           ╱
  500 ┤        ╱
      │     ╱
  333 ┼────╱  ← 预热阶段
      └────┬────┬────┬────┬────┬───> 时间
          0    2    4    6    8   10秒
```

### 2.2 配置方式

```java
FlowRule rule = new FlowRule();
rule.setResource("myResource");
rule.setGrade(RuleConstant.FLOW_GRADE_QPS);
rule.setCount(1000);  // 最终阈值

// 流控效果：Warm Up
rule.setControlBehavior(RuleConstant.CONTROL_BEHAVIOR_WARM_UP);
rule.setWarmUpPeriodSec(10);  // 预热时长：10秒

FlowRuleManager.loadRules(Collections.singletonList(rule));
```

### 2.3 适用场景

**场景1：系统冷启动**

```java
/**
 * 系统刚启动时：
 * - 缓存为空
 * - 连接池未建立
 * - JIT未优化
 *
 * 如果直接承受1000 QPS，可能导致：
 * - 大量缓存穿透
 * - 数据库压力过大
 * - 系统响应变慢
 */
@GetMapping("/api/product/{id}")
@SentinelResource("product_query")
public Result getProduct(@PathVariable Long id) {
    // 先查缓存
    Product product = cacheService.get(id);
    if (product == null) {
        // 缓存未命中，查数据库
        product = productService.getById(id);
        cacheService.set(id, product);
    }
    return Result.success(product);
}

// 配置Warm Up
FlowRule rule = new FlowRule();
rule.setResource("product_query");
rule.setCount(1000);
rule.setControlBehavior(RuleConstant.CONTROL_BEHAVIOR_WARM_UP);
rule.setWarmUpPeriodSec(10);  // 给10秒预热时间
```

**场景2：定时任务触发的流量**

```java
/**
 * 场景：每天凌晨2点，定时任务触发大量订单统计
 *
 * 问题：瞬间大量请求涌入，可能压垮数据库
 * 解决：Warm Up，逐步增加流量
 */
@Scheduled(cron = "0 0 2 * * ?")
public void dailyStatistics() {
    List<Long> orderIds = orderService.getTodayOrders();

    for (Long orderId : orderIds) {
        Entry entry = null;
        try {
            entry = SphU.entry("order_statistics");
            // 统计逻辑
            statisticsService.calculate(orderId);
        } catch (BlockException ex) {
            // 限流了，稍后重试
            retryQueue.add(orderId);
        } finally {
            if (entry != null) {
                entry.exit();
            }
        }
    }
}

// 配置Warm Up
FlowRule rule = new FlowRule();
rule.setResource("order_statistics");
rule.setCount(500);
rule.setControlBehavior(RuleConstant.CONTROL_BEHAVIOR_WARM_UP);
rule.setWarmUpPeriodSec(30);  // 给30秒预热
```

**场景3：秒杀活动开始**

```java
/**
 * 秒杀活动10:00开始
 *
 * 9:59:55 - 大量用户刷新页面等待
 * 10:00:00 - 瞬间大量请求涌入
 *
 * Warm Up：避免瞬间流量冲击
 */
@PostMapping("/api/seckill/buy")
@SentinelResource("seckill_buy")
public Result seckill(@RequestParam Long productId) {
    // 秒杀逻辑
    return seckillService.buy(productId);
}

// 配置Warm Up
FlowRule rule = new FlowRule();
rule.setResource("seckill_buy");
rule.setCount(10000);  // 最终阈值10000
rule.setControlBehavior(RuleConstant.CONTROL_BEHAVIOR_WARM_UP);
rule.setWarmUpPeriodSec(5);  // 5秒预热到最大值
```

### 2.4 Warm Up的实现原理

**令牌桶算法的变种**：

```java
// 简化的Warm Up实现
public class WarmUpController {
    private final int maxQps;          // 最终阈值
    private final int warmUpPeriodSec; // 预热时长
    private final int coldFactor = 3;  // 冷启动因子

    private long startTime;            // 预热开始时间

    public boolean canPass() {
        long now = System.currentTimeMillis();
        long elapsed = (now - startTime) / 1000;  // 已预热时长

        // 计算当前阈值
        int currentThreshold;
        if (elapsed >= warmUpPeriodSec) {
            // 预热完成，使用最终阈值
            currentThreshold = maxQps;
        } else {
            // 预热中，线性增长
            int minQps = maxQps / coldFactor;
            currentThreshold = minQps +
                (int) ((maxQps - minQps) * elapsed / warmUpPeriodSec);
        }

        // 判断是否通过
        return currentQps < currentThreshold;
    }
}
```

---

## 三、匀速排队：流量整形

### 3.1 原理

**匀速排队**：将突发流量平均分散到一段时间内处理，类似漏桶算法。

```
配置：
  QPS = 10
  意味着：每100ms处理1个请求

时间线：
  0ms：   请求1 → 立即处理
  10ms：  请求2 → 等待90ms，在100ms处理
  20ms：  请求3 → 等待180ms，在200ms处理
  100ms： 请求4 → 立即处理
  110ms： 请求5 → 等待90ms，在200ms处理

效果：
  输入：不规则（突发）
  输出：绝对平滑（固定间隔）
```

**图示**：

```
请求到达（突发）：
││││││        ││││││

匀速处理（平滑）：
│ │ │ │ │ │ │ │ │ │
← 每100ms一个 →
```

### 3.2 配置方式

```java
FlowRule rule = new FlowRule();
rule.setResource("myResource");
rule.setGrade(RuleConstant.FLOW_GRADE_QPS);
rule.setCount(10);  // 每秒10个 = 每100ms一个

// 流控效果：匀速排队
rule.setControlBehavior(RuleConstant.CONTROL_BEHAVIOR_RATE_LIMITER);
rule.setMaxQueueingTimeMs(500);  // 最大排队时间500ms

FlowRuleManager.loadRules(Collections.singletonList(rule));
```

**核心参数**：
- `setCount(10)`：每秒10个请求
- `setMaxQueueingTimeMs(500)`：最大排队500ms
  - 如果等待时间超过500ms，直接拒绝

### 3.3 适用场景

**场景1：写数据库**

```java
/**
 * 场景：订单入库
 *
 * 问题：突发流量可能压垮数据库
 * 解决：匀速排队，平滑写入
 */
@PostMapping("/api/order/create")
@SentinelResource("order_create")
public Result createOrder(@RequestBody OrderDTO orderDTO) {
    Order order = orderService.create(orderDTO);
    return Result.success(order);
}

// 配置匀速排队
FlowRule rule = new FlowRule();
rule.setResource("order_create");
rule.setGrade(RuleConstant.FLOW_GRADE_QPS);
rule.setCount(100);  // 每秒100个，即每10ms一个

rule.setControlBehavior(RuleConstant.CONTROL_BEHAVIOR_RATE_LIMITER);
rule.setMaxQueueingTimeMs(1000);  // 最多排队1秒
```

**效果对比**：

```
快速失败模式：
  瞬间收到500个请求
  → 前100个立即处理
  → 后400个立即拒绝
  → 数据库瞬时压力大

匀速排队模式：
  瞬间收到500个请求
  → 前100个立即处理（1秒内）
  → 后100个排队处理（1-2秒）
  → 再后100个排队处理（2-3秒）
  → 最后200个等待时间超过1秒，拒绝
  → 数据库压力平滑
```

**场景2：消息队列消费**

```java
/**
 * 场景：消费MQ消息写入数据库
 *
 * 问题：消息突发到达，数据库压力过大
 * 解决：匀速消费，保护数据库
 */
@Component
public class OrderMessageConsumer {

    @RabbitListener(queues = "order.create.queue")
    public void consumeMessage(String message) {
        Entry entry = null;
        try {
            entry = SphU.entry("order_message_consume");

            // 解析消息
            OrderDTO orderDTO = JSON.parseObject(message, OrderDTO.class);

            // 写入数据库
            orderService.create(orderDTO);

        } catch (BlockException ex) {
            // 被限流，重新入队
            log.warn("消息消费被限流，重新入队: {}", message);
            // 手动ACK失败，消息会重新入队
            throw new AmqpRejectAndDontRequeueException("限流");

        } finally {
            if (entry != null) {
                entry.exit();
            }
        }
    }
}

// 配置匀速排队
FlowRule rule = new FlowRule();
rule.setResource("order_message_consume");
rule.setCount(50);  // 每秒50个，即每20ms一个

rule.setControlBehavior(RuleConstant.CONTROL_BEHAVIOR_RATE_LIMITER);
rule.setMaxQueueingTimeMs(2000);  // 最多排队2秒
```

**场景3：批量任务处理**

```java
/**
 * 场景：批量发送短信
 *
 * 问题：第三方API有限流，需要控制发送速度
 * 解决：匀速排队，避免被第三方限流
 */
public void sendSmsBatch(List<String> phones) {
    for (String phone : phones) {
        Entry entry = null;
        try {
            entry = SphU.entry("sms_send");

            // 调用第三方API发送短信
            smsClient.send(phone, "您的验证码是...");

        } catch (BlockException ex) {
            // 排队超时，稍后重试
            log.warn("短信发送被限流: {}", phone);
            retryQueue.add(phone);

        } finally {
            if (entry != null) {
                entry.exit();
            }
        }
    }
}

// 配置匀速排队
FlowRule rule = new FlowRule();
rule.setResource("sms_send");
rule.setCount(20);  // 每秒20条，即每50ms一条

rule.setControlBehavior(RuleConstant.CONTROL_BEHAVIOR_RATE_LIMITER);
rule.setMaxQueueingTimeMs(5000);  // 最多排队5秒
```

### 3.4 匀速排队的实现原理

**核心思想**：计算每个请求应该在什么时间执行

```java
// 简化的匀速排队实现
public class RateLimiterController {
    private final int maxQps;              // 每秒请求数
    private final long maxQueueingTimeMs;  // 最大排队时间
    private long lastPassedTime;           // 上次通过的时间

    public boolean canPass() {
        long now = System.currentTimeMillis();
        long interval = 1000 / maxQps;  // 每个请求的间隔时间

        // 计算期望通过时间
        long expectedTime = lastPassedTime + interval;

        // 如果还没到期望时间，计算需要等待的时间
        if (expectedTime > now) {
            long waitTime = expectedTime - now;

            // 如果等待时间超过阈值，拒绝
            if (waitTime > maxQueueingTimeMs) {
                return false;  // 拒绝
            }

            // 等待到期望时间
            try {
                Thread.sleep(waitTime);
            } catch (InterruptedException e) {
                return false;
            }

            lastPassedTime = expectedTime;
        } else {
            // 已经超过期望时间，立即通过
            lastPassedTime = now;
        }

        return true;  // 通过
    }
}
```

---

## 四、三种效果对比

### 4.1 对比表格

| 维度 | 快速失败 | Warm Up | 匀速排队 |
|------|---------|---------|---------|
| **处理方式** | 立即拒绝 | 逐步放行 | 排队等待 |
| **响应时间** | 快 | 快 | 慢（有等待） |
| **流量输出** | 突发 | 突发 | 平滑 |
| **适用场景** | 普通API | 冷启动 | 写操作、MQ |
| **用户体验** | 差（直接失败） | 中等 | 好（会等待） |
| **系统保护** | 强 | 强 | 强 |

### 4.2 流量曲线对比

```
输入流量（突发）：
QPS
200 ┤  ╱╲
    │ ╱  ╲
100 ┤╱    ╲___
    └────────────> 时间
    0  1s  2s  3s

快速失败：
    │▃▅▇
100 ┼───────────
    │
 50 ┤
    └────────────> 时间
    前1秒通过100，后面拒绝

Warm Up：
    │    ╱▃▅▇
100 ┼───────────
    │  ╱
 50 ┤╱
    └────────────> 时间
    逐步增加到100

匀速排队：
    │▁▁▁▁▁▁▁▁▁▁
100 ┼───────────
    │
 50 ┤
    └────────────> 时间
    绝对平滑输出
```

### 4.3 选择决策树

```
需要限流？
  ↓
是慢接口（RT>1s）或写操作？
  ├─ Yes → 匀速排队
  └─ No → 是冷启动场景？
      ├─ Yes → Warm Up
      └─ No → 快速失败
```

---

## 五、实战案例

### 5.1 综合案例：订单系统的多种流控效果

```java
@RestController
@RequestMapping("/api/order")
public class OrderController {

    /**
     * 订单查询：快速失败
     * - 查询接口，RT快
     * - 超过阈值直接拒绝
     */
    @GetMapping("/{id}")
    @SentinelResource("order_query")
    public Result query(@PathVariable Long id) {
        Order order = orderService.getById(id);
        return Result.success(order);
    }

    /**
     * 订单创建：匀速排队
     * - 写数据库，保护下游
     * - 允许短暂排队
     */
    @PostMapping("/create")
    @SentinelResource("order_create")
    public Result create(@RequestBody OrderDTO dto) {
        Order order = orderService.create(dto);
        return Result.success(order);
    }

    /**
     * 订单统计：Warm Up
     * - 复杂查询，冷启动慢
     * - 需要预热时间
     */
    @GetMapping("/statistics")
    @SentinelResource("order_statistics")
    public Result statistics(@RequestParam String startDate,
                              @RequestParam String endDate) {
        Statistics stats = orderService.statistics(startDate, endDate);
        return Result.success(stats);
    }
}

// 配置流控规则
@Configuration
public class SentinelConfig {

    @PostConstruct
    public void initFlowRules() {
        List<FlowRule> rules = new ArrayList<>();

        // 规则1：订单查询 - 快速失败
        FlowRule queryRule = new FlowRule();
        queryRule.setResource("order_query");
        queryRule.setGrade(RuleConstant.FLOW_GRADE_QPS);
        queryRule.setCount(1000);
        queryRule.setControlBehavior(RuleConstant.CONTROL_BEHAVIOR_DEFAULT);
        rules.add(queryRule);

        // 规则2：订单创建 - 匀速排队
        FlowRule createRule = new FlowRule();
        createRule.setResource("order_create");
        createRule.setGrade(RuleConstant.FLOW_GRADE_QPS);
        createRule.setCount(100);
        createRule.setControlBehavior(RuleConstant.CONTROL_BEHAVIOR_RATE_LIMITER);
        createRule.setMaxQueueingTimeMs(1000);
        rules.add(createRule);

        // 规则3：订单统计 - Warm Up
        FlowRule statsRule = new FlowRule();
        statsRule.setResource("order_statistics");
        statsRule.setGrade(RuleConstant.FLOW_GRADE_QPS);
        statsRule.setCount(50);
        statsRule.setControlBehavior(RuleConstant.CONTROL_BEHAVIOR_WARM_UP);
        statsRule.setWarmUpPeriodSec(30);
        rules.add(statsRule);

        FlowRuleManager.loadRules(rules);
    }
}
```

---

## 六、总结

**三种流控效果的核心特点**：

1. **快速失败**：超过阈值立即拒绝
   - 默认选择
   - 适合普通API接口

2. **Warm Up**：冷启动预热，逐步增加流量
   - 避免冷启动冲击
   - 适合系统启动、定时任务、秒杀开始

3. **匀速排队**：排队等待，平滑输出
   - 流量整形
   - 适合写操作、MQ消费、批量任务

**选择建议**：

| 场景 | 推荐效果 |
|------|---------|
| 普通查询API | 快速失败 |
| 系统冷启动 | Warm Up |
| 写数据库 | 匀速排队 |
| MQ消费 | 匀速排队 |
| 秒杀活动 | Warm Up |
| 批量任务 | 匀速排队 |

**下一篇预告**：《流控策略：直接、关联、链路三种模式》

我们将学习Sentinel的流控策略，如何实现关联限流？如何实现链路限流？

---

## 思考题

1. Warm Up和令牌桶算法有什么关系？
2. 匀速排队会阻塞线程吗？对性能有什么影响？
3. 如果系统永远不会冷启动（有预热脚本），还需要用Warm Up吗？

欢迎在评论区分享你的理解！
