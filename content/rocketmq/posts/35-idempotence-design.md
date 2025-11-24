---
title: "RocketMQ生产05：消息重复处理 - 幂等性设计的最佳实践"
date: 2025-11-15T11:00:00+08:00
draft: false
tags: ["RocketMQ", "幂等性", "重复消费", "分布式系统"]
categories: ["技术"]
description: "深入理解消息重复的根本原因，掌握幂等性设计的核心方法"
series: ["RocketMQ从入门到精通"]
weight: 35
stage: 4
stageTitle: "生产实践篇"
---

## 引言：重复消费的困扰

数据库里同一笔订单被创建了 3 次，库存被重复扣减，用户投诉"明明只买了 1 件，为什么扣了 3 件库存？"

**重复消费的常见表现**：
- ❌ 订单重复创建
- ❌ 积分重复发放
- ❌ 库存重复扣减
- ❌ 消息重复推送

**本文目标**：
- ✅ 理解消息重复的根本原因
- ✅ 掌握幂等性设计的核心方法
- ✅ 学习 5 种幂等性实现方案
- ✅ 构建完整的防重体系

---

## 一、消息重复的根本原因

### 1.1 RocketMQ 的 At Least Once 语义

RocketMQ 保证消息**至少投递一次**（At Least Once），但不保证**恰好一次**（Exactly Once）。

**为什么会重复？**

```
┌─────────┐         ┌─────────┐         ┌──────────┐
│Producer │         │ Broker  │         │ Consumer │
└────┬────┘         └────┬────┘         └────┬─────┘
     │                   │                   │
     │  1. 发送消息       │                   │
     ├──────────────────>│                   │
     │                   │                   │
     │  2. 存储成功       │                   │
     │<──────────────────┤                   │
     │                   │                   │
     │                   │  3. 推送消息       │
     │                   ├──────────────────>│
     │                   │                   │
     │                   │  4. 消费成功       │
     │                   │<──────────────────┤
     │                   │                   │
     │                   │  5. ACK确认        │
     │                   │<──X─────────────X─┤  网络故障，ACK 丢失
     │                   │                   │
     │                   │  6. 超时重推       │
     │                   ├──────────────────>│  重复消费！
     │                   │                   │
```

**重复的三大场景**：

1. **网络抖动**：Consumer 消费成功，但 ACK 未送达 Broker
2. **Consumer 重启**：消费一半重启，Offset 未及时提交
3. **Rebalance**：消费组负载均衡，消息被重新分配

---

### 1.2 重复的必然性

```
分布式系统 CAP 定理：
- Consistency（一致性）
- Availability（可用性）
- Partition tolerance（分区容错性）

RocketMQ 选择 AP（可用性 + 分区容错），牺牲了严格一致性。
→ 消息重复是分布式系统的必然产物
→ 幂等性是应用层的必备能力
```

---

## 二、幂等性的核心概念

### 2.1 什么是幂等性？

**定义**：同一个操作执行多次，结果与执行一次相同。

**数学表达**：
```
f(f(x)) = f(x)
```

**案例**：
- ✅ 幂等操作：设置用户状态为"已激活"（重复执行不影响）
- ❌ 非幂等操作：余额 +100（重复执行会多次增加）

---

### 2.2 幂等性的两个层次

| 层次 | 含义 | 实现方式 |
|------|------|---------|
| **业务幂等** | 业务结果幂等 | 数据库唯一索引、状态机 |
| **消息幂等** | 消息处理幂等 | 消息去重表、分布式锁 |

**推荐**：业务幂等 + 消息幂等双重保障

---

## 三、幂等性实现方案

### 3.1 方案1：数据库唯一索引（推荐）

#### 原理

利用数据库唯一约束，重复插入会报错。

#### 实现

```sql
-- 订单表
CREATE TABLE `t_order` (
  `id` BIGINT PRIMARY KEY AUTO_INCREMENT,
  `order_id` VARCHAR(64) NOT NULL COMMENT '订单号',
  `user_id` BIGINT NOT NULL,
  `amount` DECIMAL(10,2) NOT NULL,
  `status` VARCHAR(20) NOT NULL,
  `create_time` DATETIME NOT NULL,
  UNIQUE KEY `uk_order_id` (`order_id`)  -- 唯一索引
) ENGINE=InnoDB;
```

```java
@Service
public class OrderService {

    @Autowired
    private OrderMapper orderMapper;

    /**
     * 幂等创建订单
     */
    public void createOrder(String orderId, Long userId, BigDecimal amount) {
        Order order = new Order();
        order.setOrderId(orderId);
        order.setUserId(userId);
        order.setAmount(amount);
        order.setStatus("CREATED");
        order.setCreateTime(new Date());

        try {
            orderMapper.insert(order);  // 插入
            log.info("订单创建成功，orderId={}", orderId);
        } catch (DuplicateKeyException e) {
            // 唯一索引冲突，说明订单已存在，幂等
            log.warn("订单已存在，跳过，orderId={}", orderId);
        }
    }
}

// Consumer 端
@Override
public ConsumeConcurrentlyStatus consumeMessage(List<MessageExt> msgs, ConsumeConcurrentlyContext context) {
    for (MessageExt msg : msgs) {
        String orderId = msg.getKeys();  // 消息 Key 作为订单号
        OrderDTO orderDTO = JSON.parseObject(msg.getBody(), OrderDTO.class);

        // 直接调用幂等方法
        orderService.createOrder(orderId, orderDTO.getUserId(), orderDTO.getAmount());
    }
    return ConsumeConcurrentlyStatus.CONSUME_SUCCESS;
}
```

**优点**：
- ✅ 简单高效，依赖数据库能力
- ✅ 强一致性保证
- ✅ 适合大部分场景

**缺点**：
- ❌ 依赖数据库，无法跨表幂等
- ❌ 唯一索引字段有限

---

### 3.2 方案2：分布式锁

#### 原理

在处理消息前，先获取分布式锁，保证同一时刻只有一个线程处理。

#### 实现（Redis 实现）

```java
@Service
public class IdempotentService {

    @Autowired
    private RedisTemplate<String, String> redisTemplate;

    /**
     * 基于 Redis 的分布式锁
     */
    public boolean tryLock(String lockKey, long expireSeconds) {
        Boolean success = redisTemplate.opsForValue()
            .setIfAbsent(lockKey, "LOCKED", expireSeconds, TimeUnit.SECONDS);
        return Boolean.TRUE.equals(success);
    }

    public void unlock(String lockKey) {
        redisTemplate.delete(lockKey);
    }
}

// Consumer 端
@Override
public ConsumeConcurrentlyStatus consumeMessage(List<MessageExt> msgs, ConsumeConcurrentlyContext context) {
    for (MessageExt msg : msgs) {
        String orderId = msg.getKeys();
        String lockKey = "order:lock:" + orderId;

        // 尝试获取锁
        if (!idempotentService.tryLock(lockKey, 10)) {
            log.warn("获取锁失败，可能正在处理，orderId={}", orderId);
            return ConsumeConcurrentlyStatus.RECONSUME_LATER;  // 稍后重试
        }

        try {
            // 处理业务
            orderService.createOrder(orderId, ...);
        } finally {
            // 释放锁
            idempotentService.unlock(lockKey);
        }
    }
    return ConsumeConcurrentlyStatus.CONSUME_SUCCESS;
}
```

**优化：Redisson 分布式锁**

```java
@Service
public class RedissonIdempotentService {

    @Autowired
    private RedissonClient redissonClient;

    public void processWithLock(String orderId, Runnable task) {
        String lockKey = "order:lock:" + orderId;
        RLock lock = redissonClient.getLock(lockKey);

        try {
            // 尝试加锁，最多等待 10 秒，锁自动过期时间 30 秒
            if (lock.tryLock(10, 30, TimeUnit.SECONDS)) {
                try {
                    task.run();  // 执行业务
                } finally {
                    lock.unlock();  // 释放锁
                }
            } else {
                log.warn("获取锁超时，orderId={}", orderId);
                throw new RuntimeException("获取锁超时");
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new RuntimeException("获取锁被中断");
        }
    }
}
```

**优点**：
- ✅ 跨表、跨库幂等
- ✅ 支持复杂业务场景

**缺点**：
- ❌ 依赖 Redis，增加复杂度
- ❌ 锁竞争可能影响性能
- ❌ 需处理锁过期、死锁问题

---

### 3.3 方案3：消息去重表

#### 原理

用专门的表记录已处理的消息 ID，处理前先查表判断。

#### 实现

```sql
-- 消息去重表
CREATE TABLE `t_message_consumed` (
  `id` BIGINT PRIMARY KEY AUTO_INCREMENT,
  `msg_id` VARCHAR(128) NOT NULL COMMENT '消息ID',
  `consumer_group` VARCHAR(128) NOT NULL COMMENT '消费组',
  `topic` VARCHAR(128) NOT NULL,
  `consume_time` DATETIME NOT NULL,
  `status` VARCHAR(20) NOT NULL COMMENT 'SUCCESS|FAILED',
  UNIQUE KEY `uk_msg_consumer` (`msg_id`, `consumer_group`)
) ENGINE=InnoDB;
```

```java
@Service
public class MessageDeduplicationService {

    @Autowired
    private MessageConsumedMapper mapper;

    /**
     * 检查消息是否已处理
     */
    public boolean isConsumed(String msgId, String consumerGroup) {
        MessageConsumed record = mapper.selectByMsgIdAndGroup(msgId, consumerGroup);
        return record != null && "SUCCESS".equals(record.getStatus());
    }

    /**
     * 记录消息已处理
     */
    @Transactional
    public void markConsumed(String msgId, String consumerGroup, String topic, String status) {
        MessageConsumed record = new MessageConsumed();
        record.setMsgId(msgId);
        record.setConsumerGroup(consumerGroup);
        record.setTopic(topic);
        record.setConsumeTime(new Date());
        record.setStatus(status);

        try {
            mapper.insert(record);
        } catch (DuplicateKeyException e) {
            log.warn("消息已记录，msgId={}", msgId);
        }
    }
}

// Consumer 端
@Override
public ConsumeConcurrentlyStatus consumeMessage(List<MessageExt> msgs, ConsumeConcurrentlyContext context) {
    for (MessageExt msg : msgs) {
        String msgId = msg.getMsgId();
        String consumerGroup = "order_consumer_group";

        // 1. 检查是否已消费
        if (deduplicationService.isConsumed(msgId, consumerGroup)) {
            log.warn("消息已消费，跳过，msgId={}", msgId);
            continue;
        }

        // 2. 处理业务
        try {
            orderService.createOrder(msg);

            // 3. 记录消费成功
            deduplicationService.markConsumed(msgId, consumerGroup, msg.getTopic(), "SUCCESS");

        } catch (Exception e) {
            log.error("处理失败，msgId={}", msgId, e);
            // 记录消费失败
            deduplicationService.markConsumed(msgId, consumerGroup, msg.getTopic(), "FAILED");
            return ConsumeConcurrentlyStatus.RECONSUME_LATER;
        }
    }
    return ConsumeConcurrentlyStatus.CONSUME_SUCCESS;
}
```

**优点**：
- ✅ 通用性强，适用所有场景
- ✅ 可追溯消费历史

**缺点**：
- ❌ 增加数据库写入压力
- ❌ 去重表数据量大，需定期清理

---

### 3.4 方案4：Redis Set 去重

#### 原理

使用 Redis Set 记录已处理的消息 ID，利用 Set 的唯一性特性。

#### 实现

```java
@Service
public class RedisDeduplicationService {

    @Autowired
    private RedisTemplate<String, String> redisTemplate;

    private static final String CONSUMED_KEY_PREFIX = "msg:consumed:";

    /**
     * 检查并标记消息已消费（原子操作）
     */
    public boolean checkAndMark(String msgId, long expireSeconds) {
        String key = CONSUMED_KEY_PREFIX + msgId;

        // SETNX：如果 key 不存在则设置，返回 true；存在则返回 false
        Boolean success = redisTemplate.opsForValue()
            .setIfAbsent(key, "1", expireSeconds, TimeUnit.SECONDS);

        return Boolean.TRUE.equals(success);
    }

    /**
     * 检查消息是否已消费
     */
    public boolean isConsumed(String msgId) {
        String key = CONSUMED_KEY_PREFIX + msgId;
        return Boolean.TRUE.equals(redisTemplate.hasKey(key));
    }
}

// Consumer 端
@Override
public ConsumeConcurrentlyStatus consumeMessage(List<MessageExt> msgs, ConsumeConcurrentlyContext context) {
    for (MessageExt msg : msgs) {
        String msgId = msg.getMsgId();

        // 原子检查并标记（防重复）
        if (!redisDeduplicationService.checkAndMark(msgId, 7 * 24 * 3600)) {
            log.warn("消息已消费，跳过，msgId={}", msgId);
            continue;
        }

        // 处理业务
        try {
            orderService.createOrder(msg);
        } catch (Exception e) {
            log.error("处理失败，msgId={}", msgId, e);
            // 删除标记，允许重试
            redisTemplate.delete(CONSUMED_KEY_PREFIX + msgId);
            return ConsumeConcurrentlyStatus.RECONSUME_LATER;
        }
    }
    return ConsumeConcurrentlyStatus.CONSUME_SUCCESS;
}
```

**优点**：
- ✅ 性能高，Redis 速度快
- ✅ 自动过期，无需手动清理

**缺点**：
- ❌ 依赖 Redis，增加运维成本
- ❌ Redis 故障会影响防重

---

### 3.5 方案5：业务状态机

#### 原理

利用业务自身的状态流转，天然保证幂等性。

#### 实现

```java
// 订单状态机
public enum OrderStatus {
    CREATED,      // 已创建
    PAID,         // 已支付
    SHIPPED,      // 已发货
    COMPLETED,    // 已完成
    CANCELLED     // 已取消
}

@Service
public class OrderStateMachineService {

    @Autowired
    private OrderMapper orderMapper;

    /**
     * 支付订单（幂等）
     */
    @Transactional
    public boolean payOrder(String orderId) {
        Order order = orderMapper.selectByOrderId(orderId);

        if (order == null) {
            throw new RuntimeException("订单不存在");
        }

        // 状态检查：只有"已创建"状态才能支付
        if (order.getStatus() != OrderStatus.CREATED) {
            log.warn("订单状态不允许支付，orderId={}, status={}", orderId, order.getStatus());
            return false;  // 幂等返回
        }

        // 状态流转：CREATED → PAID
        int updated = orderMapper.updateStatus(orderId, OrderStatus.CREATED, OrderStatus.PAID);

        if (updated > 0) {
            log.info("订单支付成功，orderId={}", orderId);
            return true;
        } else {
            log.warn("订单状态已变更，支付失败，orderId={}", orderId);
            return false;
        }
    }
}

// Mapper 层（乐观锁）
@Update("UPDATE t_order SET status = #{newStatus}, update_time = NOW() " +
        "WHERE order_id = #{orderId} AND status = #{oldStatus}")
int updateStatus(@Param("orderId") String orderId,
                 @Param("oldStatus") OrderStatus oldStatus,
                 @Param("newStatus") OrderStatus newStatus);

// Consumer 端
@Override
public ConsumeConcurrentlyStatus consumeMessage(List<MessageExt> msgs, ConsumeConcurrentlyContext context) {
    for (MessageExt msg : msgs) {
        String orderId = msg.getKeys();

        // 幂等支付
        boolean success = orderStateMachineService.payOrder(orderId);

        if (!success) {
            log.warn("支付操作被忽略（幂等），orderId={}", orderId);
        }
    }
    return ConsumeConcurrentlyStatus.CONSUME_SUCCESS;
}
```

**优点**：
- ✅ 最优雅的幂等方案
- ✅ 无需额外存储
- ✅ 符合业务语义

**缺点**：
- ❌ 仅适用状态流转场景
- ❌ 需精心设计状态机

---

## 四、幂等性方案对比

| 方案 | 适用场景 | 性能 | 复杂度 | 推荐度 |
|------|---------|------|-------|--------|
| **数据库唯一索引** | 单表操作 | ⭐⭐⭐⭐ | ⭐ | ⭐⭐⭐⭐⭐ |
| **分布式锁** | 复杂业务、跨表 | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ |
| **消息去重表** | 通用场景 | ⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐ |
| **Redis Set** | 高并发场景 | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐ |
| **业务状态机** | 状态流转场景 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |

---

## 五、生产级幂等性框架

### 5.1 组合方案（推荐）

```java
@Service
public class IdempotentConsumerService {

    @Autowired
    private RedisDeduplicationService redisDedup;

    @Autowired
    private OrderService orderService;

    @Transactional
    public void consumeOrderMessage(MessageExt msg) {
        String msgId = msg.getMsgId();
        String orderId = msg.getKeys();

        // 1. 第一道防线：Redis 快速去重
        if (!redisDedup.checkAndMark(msgId, 7 * 24 * 3600)) {
            log.warn("[Redis去重] 消息已消费，msgId={}", msgId);
            return;
        }

        try {
            // 2. 第二道防线：数据库唯一索引
            orderService.createOrder(orderId, ...);

            log.info("订单创建成功，orderId={}, msgId={}", orderId, msgId);

        } catch (DuplicateKeyException e) {
            // 唯一索引冲突，幂等
            log.warn("[DB去重] 订单已存在，orderId={}, msgId={}", orderId, msgId);

        } catch (Exception e) {
            // 业务异常，删除 Redis 标记，允许重试
            redisDedup.remove(msgId);
            throw e;
        }
    }
}
```

**优势**：
- ✅ 双重保障，防重更可靠
- ✅ Redis 快速拦截，减轻数据库压力
- ✅ 数据库兜底，保证最终一致性

---

### 5.2 幂等性AOP切面

```java
/**
 * 幂等性注解
 */
@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
public @interface Idempotent {
    /**
     * 幂等类型
     */
    IdempotentType type() default IdempotentType.REDIS;

    /**
     * 过期时间（秒）
     */
    long expireSeconds() default 7 * 24 * 3600;
}

/**
 * 幂等性切面
 */
@Aspect
@Component
public class IdempotentAspect {

    @Autowired
    private RedisDeduplicationService redisDedup;

    @Around("@annotation(idempotent)")
    public Object around(ProceedingJoinPoint joinPoint, Idempotent idempotent) throws Throwable {
        // 获取方法参数中的 msgId
        Object[] args = joinPoint.getArgs();
        String msgId = extractMsgId(args);

        if (msgId == null) {
            throw new RuntimeException("无法提取 msgId");
        }

        // 幂等性检查
        if (!redisDedup.checkAndMark(msgId, idempotent.expireSeconds())) {
            log.warn("[幂等拦截] msgId={}", msgId);
            return null;  // 幂等，直接返回
        }

        try {
            // 执行业务方法
            return joinPoint.proceed();
        } catch (Exception e) {
            // 失败时删除标记，允许重试
            redisDedup.remove(msgId);
            throw e;
        }
    }

    private String extractMsgId(Object[] args) {
        for (Object arg : args) {
            if (arg instanceof MessageExt) {
                return ((MessageExt) arg).getMsgId();
            }
        }
        return null;
    }
}

// 使用示例
@Service
public class OrderConsumerService {

    @Idempotent(type = IdempotentType.REDIS, expireSeconds = 7 * 24 * 3600)
    public void processOrderMessage(MessageExt msg) {
        // 业务逻辑（自动幂等）
        orderService.createOrder(msg);
    }
}
```

---

## 六、常见问题

### Q1：msgId 可以作为幂等键吗？

**可以，但有限制**：
- ✅ 适用于同一消费组
- ❌ 不同消费组不能共用（msgId 相同，但业务逻辑不同）

**最佳实践**：
```java
// 推荐：消费组 + msgId
String idempotentKey = consumerGroup + ":" + msgId;

// 或：业务键（订单号）
String idempotentKey = "order:" + orderId;
```

---

### Q2：幂等性检查失败怎么办？

**场景**：Redis 故障，无法检查幂等性

**降级方案**：
```java
try {
    if (!redisDedup.checkAndMark(msgId, 3600)) {
        log.warn("消息已消费，msgId={}", msgId);
        return;
    }
} catch (Exception e) {
    log.error("Redis 故障，降级到数据库幂等", e);
    // 降级：直接依赖数据库唯一索引
}

// 继续业务处理（依赖数据库幂等）
orderService.createOrder(orderId, ...);
```

---

### Q3：幂等性标记何时清理？

**策略**：
1. **Redis**：设置过期时间（如 7 天）
2. **数据库去重表**：定时任务清理（如保留 30 天）

```sql
-- 清理 30 天前的记录
DELETE FROM t_message_consumed
WHERE consume_time < DATE_SUB(NOW(), INTERVAL 30 DAY)
LIMIT 10000;
```

---

## 七、总结

### 幂等性设计原则

```
1. 优先使用业务幂等（状态机）
2. 数据库唯一索引是基础保障
3. Redis 去重提升性能
4. 双重防护更可靠
5. 降级方案保证高可用
```

### 方案选择

| 场景 | 推荐方案 |
|------|---------|
| 单表操作 | 数据库唯一索引 |
| 状态流转 | 业务状态机 |
| 高并发 | Redis Set + 数据库唯一索引 |
| 复杂业务 | 分布式锁 + 消息去重表 |

### 防重检查清单

- [ ] 消息 Key 是否唯一且有业务含义
- [ ] 是否有数据库唯一索引保障
- [ ] 是否实现 Redis 快速去重
- [ ] 异常时是否清理幂等标记
- [ ] 是否有幂等性监控告警
- [ ] 是否有降级方案

---

**下一篇预告**：《高可用保障 - 多机房部署与故障演练》，我们将讲解如何构建高可用的 RocketMQ 集群，实现容灾备份。

**本文关键词**：`幂等性` `消息去重` `分布式锁` `状态机`
