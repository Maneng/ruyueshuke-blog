---
title: "延迟队列实现：基于ZSet的定时任务"
date: 2025-01-21T22:50:00+08:00
draft: false
tags: ["Redis", "延迟队列", "定时任务", "ZSet"]
categories: ["技术"]
description: "基于Redis ZSet实现延迟队列，处理订单超时、消息延迟发送等场景，简单高效可靠"
weight: 28
stage: 3
stageTitle: "进阶特性篇"
---

## 延迟队列原理

**核心思想**：ZSet的score存储执行时间戳

```
ZADD delay_queue <timestamp> <task_id>

轮询：
1. ZRANGEBYSCORE delay_queue 0 <now> LIMIT 0 100
2. 取出到期任务
3. 执行任务
4. ZREM删除已执行任务
```

## 基础实现

```java
@Component
public class DelayQueue {
    @Autowired
    private RedisTemplate<String, String> redis;

    private static final String QUEUE_KEY = "delay:queue";

    // 添加延迟任务
    public void addTask(String taskId, long delaySeconds) {
        long executeTime = System.currentTimeMillis() + delaySeconds * 1000;
        redis.opsForZSet().add(QUEUE_KEY, taskId, executeTime);
    }

    // 拉取到期任务
    public Set<String> pollTasks() {
        long now = System.currentTimeMillis();
        Set<String> tasks = redis.opsForZSet()
            .rangeByScore(QUEUE_KEY, 0, now, 0, 100);

        if (tasks != null && !tasks.isEmpty()) {
            // 删除已拉取的任务
            redis.opsForZSet().removeRangeByScore(QUEUE_KEY, 0, now);
        }
        return tasks;
    }

    // 定时拉取
    @Scheduled(fixedRate = 1000)  // 每秒执行
    public void consumeTasks() {
        Set<String> tasks = pollTasks();
        if (tasks != null) {
            tasks.forEach(this::executeTask);
        }
    }

    private void executeTask(String taskId) {
        log.info("执行延迟任务: {}", taskId);
        // 任务执行逻辑
    }
}
```

## 实战案例

### 案例1：订单超时自动取消

```java
@Service
public class OrderTimeoutService {
    @Autowired
    private RedisTemplate<String, String> redis;
    @Autowired
    private OrderService orderService;

    private static final String QUEUE_KEY = "delay:order:timeout";
    private static final int TIMEOUT_MINUTES = 30;  // 30分钟超时

    // 创建订单时，添加超时任务
    public void createOrder(String orderNo) {
        orderService.create(orderNo);

        // 添加到延迟队列
        long executeTime = System.currentTimeMillis() + TIMEOUT_MINUTES * 60 * 1000;
        redis.opsForZSet().add(QUEUE_KEY, orderNo, executeTime);
    }

    // 支付成功时，取消超时任务
    public void payOrder(String orderNo) {
        orderService.pay(orderNo);

        // 从延迟队列移除
        redis.opsForZSet().remove(QUEUE_KEY, orderNo);
    }

    // 定时检查超时订单
    @Scheduled(fixedRate = 10000)  // 每10秒
    public void checkTimeout() {
        long now = System.currentTimeMillis();
        Set<String> timeoutOrders = redis.opsForZSet()
            .rangeByScore(QUEUE_KEY, 0, now, 0, 100);

        if (timeoutOrders != null) {
            for (String orderNo : timeoutOrders) {
                try {
                    // 取消订单
                    orderService.cancel(orderNo, "超时未支付");

                    // 从队列移除
                    redis.opsForZSet().remove(QUEUE_KEY, orderNo);

                    log.info("订单超时已取消: {}", orderNo);
                } catch (Exception e) {
                    log.error("取消订单失败: {}", orderNo, e);
                }
            }
        }
    }
}
```

### 案例2：消息定时发送

```java
@Service
public class ScheduledMessageService {
    @Autowired
    private RedisTemplate<String, String> redis;

    private static final String QUEUE_KEY = "delay:message";

    // 添加定时消息
    public void scheduleMessage(String messageId, String content, LocalDateTime sendTime) {
        // 存储消息内容
        redis.opsForValue().set("message:" + messageId, content, 7, TimeUnit.DAYS);

        // 添加到延迟队列
        long timestamp = sendTime.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli();
        redis.opsForZSet().add(QUEUE_KEY, messageId, timestamp);
    }

    @Scheduled(fixedRate = 5000)  // 每5秒
    public void sendScheduledMessages() {
        long now = System.currentTimeMillis();
        Set<String> messageIds = redis.opsForZSet()
            .rangeByScore(QUEUE_KEY, 0, now, 0, 50);

        if (messageIds != null) {
            for (String messageId : messageIds) {
                String content = redis.opsForValue().get("message:" + messageId);
                if (content != null) {
                    sendMessage(content);
                    redis.delete("message:" + messageId);
                }
                redis.opsForZSet().remove(QUEUE_KEY, messageId);
            }
        }
    }

    private void sendMessage(String content) {
        log.info("发送消息: {}", content);
        // 实际发送逻辑
    }
}
```

### 案例3：优惠券过期提醒

```java
@Service
public class CouponReminderService {
    @Autowired
    private RedisTemplate<String, String> redis;

    private static final String QUEUE_KEY = "delay:coupon:reminder";

    // 发放优惠券时，设置提醒
    public void issueCoupon(String couponId, LocalDateTime expireTime) {
        // 过期前3天提醒
        long reminderTime = expireTime.minusDays(3)
            .atZone(ZoneId.systemDefault()).toInstant().toEpochMilli();

        redis.opsForZSet().add(QUEUE_KEY, couponId, reminderTime);
    }

    @Scheduled(fixedRate = 3600000)  // 每小时
    public void sendReminders() {
        long now = System.currentTimeMillis();
        Set<String> couponIds = redis.opsForZSet()
            .rangeByScore(QUEUE_KEY, 0, now);

        if (couponIds != null) {
            couponIds.forEach(couponId -> {
                sendReminder(couponId);
                redis.opsForZSet().remove(QUEUE_KEY, couponId);
            });
        }
    }

    private void sendReminder(String couponId) {
        log.info("发送优惠券过期提醒: {}", couponId);
        // 发送短信/推送通知
    }
}
```

## 可靠性保证

### 1. 防止重复消费（Lua脚本）

```java
private static final String POP_SCRIPT =
    "local tasks = redis.call('ZRANGEBYSCORE', KEYS[1], 0, ARGV[1], 'LIMIT', 0, ARGV[2]) " +
    "if #tasks > 0 then " +
    "  redis.call('ZREM', KEYS[1], unpack(tasks)) " +
    "  return tasks " +
    "else " +
    "  return {} " +
    "end";

public List<String> popTasks(int limit) {
    long now = System.currentTimeMillis();
    return redis.execute(
        RedisScript.of(POP_SCRIPT, List.class),
        Collections.singletonList(QUEUE_KEY),
        String.valueOf(now),
        String.valueOf(limit)
    );
}
```

### 2. 任务执行失败重试

```java
public void consumeTasks() {
    List<String> tasks = popTasks(100);

    for (String taskId : tasks) {
        try {
            executeTask(taskId);
        } catch (Exception e) {
            log.error("任务执行失败: {}", taskId, e);

            // 重新入队，延迟60秒后重试
            long retryTime = System.currentTimeMillis() + 60000;
            redis.opsForZSet().add(QUEUE_KEY, taskId, retryTime);
        }
    }
}
```

### 3. 限制重试次数

```java
public void executeWithRetry(String taskId) {
    String retryKey = "retry:" + taskId;
    Integer retryCount = (Integer) redis.opsForValue().get(retryKey);

    if (retryCount == null) {
        retryCount = 0;
    }

    if (retryCount >= 3) {
        log.error("任务重试次数超限: {}", taskId);
        // 转移到死信队列
        redis.opsForList().rightPush("dead_letter_queue", taskId);
        redis.delete(retryKey);
        return;
    }

    try {
        executeTask(taskId);
        redis.delete(retryKey);  // 执行成功，清除重试计数
    } catch (Exception e) {
        // 重试计数+1
        redis.opsForValue().increment(retryKey);
        redis.expire(retryKey, 1, TimeUnit.DAYS);

        // 重新入队
        long retryTime = System.currentTimeMillis() + (retryCount + 1) * 60000;
        redis.opsForZSet().add(QUEUE_KEY, taskId, retryTime);
    }
}
```

## 性能优化

### 1. 批量处理

```java
@Scheduled(fixedRate = 1000)
public void consumeTasks() {
    List<String> tasks = popTasks(100);  // 每次最多100个

    // 使用线程池并行处理
    tasks.forEach(taskId ->
        executor.submit(() -> executeTask(taskId))
    );
}
```

### 2. 多实例消费（分片）

```java
// 实例1消费shard0
// 实例2消费shard1
@Value("${app.shard.id}")
private int shardId;

public void addTask(String taskId, long delaySeconds) {
    int shard = Math.abs(taskId.hashCode()) % SHARD_COUNT;
    String queueKey = "delay:queue:shard:" + shard;

    long executeTime = System.currentTimeMillis() + delaySeconds * 1000;
    redis.opsForZSet().add(queueKey, taskId, executeTime);
}

@Scheduled(fixedRate = 1000)
public void consumeTasks() {
    String queueKey = "delay:queue:shard:" + shardId;
    // 消费分片队列
}
```

## 与其他方案对比

| 方案 | 精度 | 可靠性 | 复杂度 | 适用场景 |
|------|------|--------|--------|---------|
| **Redis ZSet** | 秒级 | 中 | 低 | 轻量级延迟任务 |
| **RabbitMQ延迟插件** | 毫秒级 | 高 | 中 | 消息队列场景 |
| **时间轮** | 毫秒级 | 中 | 高 | 高性能定时任务 |
| **ScheduledExecutorService** | 毫秒级 | 低 | 低 | 单机定时任务 |

## 总结

**核心优势**：
- 实现简单（ZSet + 定时拉取）
- 无需额外依赖
- 适合中小规模场景

**典型场景**：
- 订单超时取消
- 消息定时发送
- 优惠券过期提醒
- 定时任务调度

**注意事项**：
- 精度秒级（不适合毫秒级）
- 单点故障（Redis宕机）
- 大规模场景考虑分片
- 失败重试和死信队列
