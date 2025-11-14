---
title: "RocketMQ进阶02：事务消息实战 - 订单支付场景完整实现"
date: 2025-11-14T05:00:00+08:00
draft: false
tags: ["RocketMQ", "事务消息", "订单系统", "支付系统", "实战案例"]
categories: ["技术"]
description: "通过订单支付的完整案例，掌握事务消息在实际业务中的应用"
series: ["RocketMQ从入门到精通"]
weight: 20
stage: 3
stageTitle: "进阶特性篇"
---

## 引言：真实业务场景

**业务需求**：用户支付成功后，需要完成以下操作：
1. 支付服务：记录支付流水
2. 订单服务：更新订单状态
3. 积分服务：增加用户积分
4. 通知服务：发送支付成功短信

要求：**保证数据一致性**，支付成功后其他操作必须成功。

---

## 一、系统架构设计

### 1.1 整体架构

```
┌──────────────────────────────────────────────────────┐
│              订单支付系统架构                          │
├──────────────────────────────────────────────────────┤
│                                                       │
│  用户端                                               │
│    │                                                  │
│    │ 1. 发起支付请求                                   │
│    ▼                                                  │
│  ┌─────────────────────────────────────────────┐     │
│  │         支付服务（Producer）                 │     │
│  │  - 调用第三方支付                            │     │
│  │  - 记录支付流水（本地事务）                  │     │
│  │  - 发送事务消息                              │     │
│  └─────────────────────────────────────────────┘     │
│                   │                                   │
│                   │ 事务消息                          │
│                   ▼                                   │
│  ┌─────────────────────────────────────────────┐     │
│  │           RocketMQ Broker                   │     │
│  └─────────────────────────────────────────────┘     │
│           │              │              │             │
│           ▼              ▼              ▼             │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐     │
│  │ 订单服务   │  │ 积分服务   │  │ 通知服务   │     │
│  │ Consumer   │  │ Consumer   │  │ Consumer   │     │
│  │            │  │            │  │            │     │
│  │ 更新订单   │  │ 增加积分   │  │ 发送短信   │     │
│  │ 状态       │  │            │  │            │     │
│  └────────────┘  └────────────┘  └────────────┘     │
│                                                       │
└──────────────────────────────────────────────────────┘
```

### 1.2 消息流转

```
支付成功 → 发送Half消息 → 记录支付流水（本地事务）
                      ↓
               事务提交（Commit）
                      ↓
            消息变为可消费状态
                      ↓
        ┌─────────────┼─────────────┐
        ▼             ▼             ▼
    订单服务      积分服务      通知服务
    更新状态      增加积分      发送短信
```

---

## 二、代码实现

### 2.1 数据库设计

```sql
-- 支付流水表
CREATE TABLE payment_record (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    order_id VARCHAR(64) NOT NULL UNIQUE,
    user_id BIGINT NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    pay_time DATETIME NOT NULL,
    status VARCHAR(20) NOT NULL,  -- SUCCESS, FAILED
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_order_id (order_id)
);

-- 订单表
CREATE TABLE orders (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    order_id VARCHAR(64) NOT NULL UNIQUE,
    user_id BIGINT NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    status VARCHAR(20) NOT NULL,  -- CREATED, PAID, CANCELLED
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- 积分表
CREATE TABLE user_points (
    user_id BIGINT PRIMARY KEY,
    points INT NOT NULL DEFAULT 0,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);
```

### 2.2 支付服务实现

```java
@Service
public class PaymentService {

    @Autowired
    private TransactionMQProducer transactionProducer;

    @Autowired
    private PaymentRecordMapper paymentRecordMapper;

    /**
     * 处理支付请求
     */
    public PaymentResult processPay(PaymentRequest request) {
        String orderId = request.getOrderId();
        BigDecimal amount = request.getAmount();

        // 1. 调用第三方支付接口
        ThirdPartyPayResult payResult = callThirdPartyPay(orderId, amount);

        if (!payResult.isSuccess()) {
            return PaymentResult.failed("支付失败：" + payResult.getMessage());
        }

        // 2. 构建事务消息
        PaymentEvent event = new PaymentEvent();
        event.setOrderId(orderId);
        event.setUserId(request.getUserId());
        event.setAmount(amount);
        event.setPayTime(new Date());

        Message message = new Message(
            "payment_success_topic",
            "pay",
            orderId,  // Key
            JSON.toJSONString(event).getBytes(StandardCharsets.UTF_8)
        );

        // 3. 发送事务消息
        try {
            TransactionSendResult sendResult = transactionProducer.sendMessageInTransaction(
                message,
                event  // 传递给executeLocalTransaction
            );

            if (sendResult.getLocalTransactionState() == LocalTransactionState.COMMIT_MESSAGE) {
                return PaymentResult.success("支付成功");
            } else {
                return PaymentResult.failed("支付记录失败");
            }
        } catch (Exception e) {
            log.error("发送事务消息失败", e);
            return PaymentResult.failed("系统异常");
        }
    }

    /**
     * 调用第三方支付（模拟）
     */
    private ThirdPartyPayResult callThirdPartyPay(String orderId, BigDecimal amount) {
        // 实际调用支付宝、微信等支付接口
        log.info("调用第三方支付：订单={}, 金额={}", orderId, amount);
        return ThirdPartyPayResult.success();
    }
}

/**
 * 事务消息监听器
 */
@Component
public class PaymentTransactionListener implements TransactionListener {

    @Autowired
    private PaymentRecordMapper paymentRecordMapper;

    /**
     * 执行本地事务：记录支付流水
     */
    @Override
    public LocalTransactionState executeLocalTransaction(Message msg, Object arg) {
        PaymentEvent event = (PaymentEvent) arg;
        String orderId = event.getOrderId();

        try {
            // 1. 插入支付记录
            PaymentRecord record = new PaymentRecord();
            record.setOrderId(orderId);
            record.setUserId(event.getUserId());
            record.setAmount(event.getAmount());
            record.setPayTime(event.getPayTime());
            record.setStatus("SUCCESS");

            int rows = paymentRecordMapper.insert(record);

            if (rows > 0) {
                log.info("支付记录成功：{}", orderId);
                return LocalTransactionState.COMMIT_MESSAGE;
            } else {
                log.error("支付记录失败：{}", orderId);
                return LocalTransactionState.ROLLBACK_MESSAGE;
            }

        } catch (DuplicateKeyException e) {
            // 重复记录，说明已经成功
            log.warn("支付记录重复：{}", orderId);
            return LocalTransactionState.COMMIT_MESSAGE;

        } catch (Exception e) {
            log.error("支付记录异常：{}", orderId, e);
            // 返回UNKNOW，等待回查
            return LocalTransactionState.UNKNOW;
        }
    }

    /**
     * 回查事务状态
     */
    @Override
    public LocalTransactionState checkLocalTransaction(MessageExt msg) {
        String orderId = msg.getKeys();

        try {
            // 查询支付记录是否存在
            PaymentRecord record = paymentRecordMapper.selectByOrderId(orderId);

            if (record != null && "SUCCESS".equals(record.getStatus())) {
                log.info("回查成功：支付记录存在，订单={}", orderId);
                return LocalTransactionState.COMMIT_MESSAGE;
            } else {
                log.warn("回查失败：支付记录不存在，订单={}", orderId);
                return LocalTransactionState.ROLLBACK_MESSAGE;
            }

        } catch (Exception e) {
            log.error("回查异常：{}", orderId, e);
            return LocalTransactionState.UNKNOW;
        }
    }
}
```

### 2.3 订单服务实现

```java
@Service
public class OrderConsumerService {

    @Autowired
    private OrderMapper orderMapper;

    /**
     * 消费支付成功消息
     */
    @RocketMQMessageListener(
        topic = "payment_success_topic",
        consumerGroup = "order_consumer_group"
    )
    public class OrderMessageListener implements RocketMQListener<String> {

        @Override
        public void onMessage(String message) {
            PaymentEvent event = JSON.parseObject(message, PaymentEvent.class);
            String orderId = event.getOrderId();

            log.info("收到支付成功消息：{}", orderId);

            try {
                // 1. 幂等性检查
                Order order = orderMapper.selectByOrderId(orderId);
                if (order == null) {
                    log.error("订单不存在：{}", orderId);
                    return;
                }

                if ("PAID".equals(order.getStatus())) {
                    log.warn("订单已支付，跳过处理：{}", orderId);
                    return;  // 幂等性保证
                }

                // 2. 更新订单状态
                order.setStatus("PAID");
                order.setUpdatedAt(new Date());

                int rows = orderMapper.updateById(order);

                if (rows > 0) {
                    log.info("订单状态更新成功：{}", orderId);
                } else {
                    log.error("订单状态更新失败：{}", orderId);
                    throw new RuntimeException("更新失败");
                }

            } catch (Exception e) {
                log.error("处理支付消息异常：{}", orderId, e);
                throw new RuntimeException(e);  // 触发重试
            }
        }
    }
}
```

### 2.4 积分服务实现

```java
@Service
public class PointsConsumerService {

    @Autowired
    private UserPointsMapper userPointsMapper;

    @Autowired
    private PointsRecordMapper pointsRecordMapper;

    /**
     * 消费支付成功消息，增加积分
     */
    @RocketMQMessageListener(
        topic = "payment_success_topic",
        consumerGroup = "points_consumer_group"
    )
    public class PointsMessageListener implements RocketMQListener<String> {

        @Override
        @Transactional
        public void onMessage(String message) {
            PaymentEvent event = JSON.parseObject(message, PaymentEvent.class);
            String orderId = event.getOrderId();
            Long userId = event.getUserId();

            log.info("收到支付成功消息，增加积分：用户={}, 订单={}", userId, orderId);

            try {
                // 1. 幂等性检查：是否已经增加过积分
                PointsRecord existing = pointsRecordMapper.selectByOrderId(orderId);
                if (existing != null) {
                    log.warn("积分已增加，跳过处理：{}", orderId);
                    return;
                }

                // 2. 计算积分（1元=1积分）
                int points = event.getAmount().intValue();

                // 3. 增加积分
                int rows = userPointsMapper.increasePoints(userId, points);
                if (rows == 0) {
                    // 用户不存在，创建记录
                    UserPoints userPoints = new UserPoints();
                    userPoints.setUserId(userId);
                    userPoints.setPoints(points);
                    userPointsMapper.insert(userPoints);
                }

                // 4. 记录积分变更
                PointsRecord record = new PointsRecord();
                record.setUserId(userId);
                record.setOrderId(orderId);
                record.setPoints(points);
                record.setReason("支付获得");
                pointsRecordMapper.insert(record);

                log.info("积分增加成功：用户={}, 积分={}", userId, points);

            } catch (DuplicateKeyException e) {
                // 重复处理，直接返回
                log.warn("积分记录重复：{}", orderId);

            } catch (Exception e) {
                log.error("积分增加异常：{}", orderId, e);
                throw new RuntimeException(e);
            }
        }
    }
}
```

---

## 三、测试验证

### 3.1 正常流程测试

```java
@SpringBootTest
public class PaymentTransactionTest {

    @Autowired
    private PaymentService paymentService;

    @Test
    public void testNormalPayment() throws InterruptedException {
        // 1. 发起支付
        PaymentRequest request = new PaymentRequest();
        request.setOrderId("ORDER_001");
        request.setUserId(10001L);
        request.setAmount(new BigDecimal("99.00"));

        PaymentResult result = paymentService.processPay(request);

        // 2. 验证支付结果
        assertTrue(result.isSuccess());

        // 3. 等待消息消费（实际生产环境通过监控确认）
        Thread.sleep(5000);

        // 4. 验证订单状态
        Order order = orderMapper.selectByOrderId("ORDER_001");
        assertEquals("PAID", order.getStatus());

        // 5. 验证积分
        UserPoints points = userPointsMapper.selectByUserId(10001L);
        assertTrue(points.getPoints() >= 99);
    }
}
```

### 3.2 异常场景测试

```java
@Test
public void testPaymentFailure() {
    // 场景1：支付失败
    // 预期：不记录支付流水，不发送消息

    // 场景2：记录支付流水失败
    // 预期：回滚消息，不通知下游服务

    // 场景3：Producer宕机
    // 预期：回查机制保证消息最终发送

    // 场景4：Consumer消费失败
    // 预期：自动重试，直到成功
}
```

---

## 四、最佳实践总结

### 4.1 关键要点

```
1. 幂等性设计
   - 使用唯一键约束
   - 消费前检查是否已处理
   - 数据库层面保证

2. 本地事务设计
   - 尽量简单
   - 避免远程调用
   - 快速返回

3. 回查逻辑设计
   - 通过数据库查询事务状态
   - 不依赖缓存
   - 保证幂等

4. 异常处理
   - 明确的Commit/Rollback
   - 未知异常返回UNKNOW
   - 记录详细日志
```

### 4.2 注意事项

```
❌ 避免：
- 本地事务中调用RPC
- 本地事务执行时间过长
- 回查逻辑依赖不可靠数据源

✅ 推荐：
- 本地事务只操作数据库
- 控制本地事务在1秒内
- 回查直接查询数据库
```

---

## 五、总结

本文通过订单支付场景，完整展示了事务消息的实战应用：

1. ✅ 支付服务：记录支付流水（本地事务）
2. ✅ 订单服务：更新订单状态（消息消费）
3. ✅ 积分服务：增加用户积分（消息消费）
4. ✅ 幂等性保证：防止重复处理
5. ✅ 异常处理：回查机制保证最终一致性

**下一步**：学习顺序消息，保证消息的有序性！

---

**本文关键词**：`事务消息实战` `订单支付` `幂等性` `最终一致性`

**专题导航**：[上一篇：事务消息原理](/blog/rocketmq/posts/19-transactional-message/) | [下一篇：顺序消息原理](#)
