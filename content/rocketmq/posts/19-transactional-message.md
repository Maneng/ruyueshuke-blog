---
title: "RocketMQ进阶01：事务消息原理与实现 - 分布式事务的终极方案"
date: 2025-11-14T04:00:00+08:00
draft: false
tags: ["RocketMQ", "事务消息", "分布式事务", "两阶段提交", "最终一致性"]
categories: ["技术"]
description: "深入剖析 RocketMQ 事务消息的实现原理，理解如何通过消息队列解决分布式事务问题"
series: ["RocketMQ从入门到精通"]
weight: 19
stage: 3
stageTitle: "进阶特性篇"
---

## 引言：分布式事务的困境

在分布式系统中，跨服务的事务一致性是一个经典难题：

**典型场景**：电商下单扣库存
```
订单服务：创建订单 ✅
库存服务：扣减库存 ❌（网络超时）

问题：订单已创建，但库存未扣减 → 数据不一致
```

RocketMQ 的事务消息提供了一种优雅的解决方案。

---

## 一、什么是事务消息？

### 1.1 核心概念

```
┌────────────────────────────────────────────┐
│         事务消息 vs 普通消息                │
├────────────────────────────────────────────┤
│                                             │
│  普通消息：                                  │
│  发送 → 立即可消费                          │
│                                             │
│  事务消息：                                  │
│  发送 → 暂不可消费（Half消息）               │
│       → 执行本地事务                        │
│       → 提交/回滚                           │
│       → 可消费/删除                         │
│                                             │
└────────────────────────────────────────────┘
```

### 1.2 应用场景

```
场景1：订单创建 + 扣库存
- 订单服务：创建订单（本地事务）
- 发送事务消息 → 库存服务扣库存

场景2：支付成功 + 积分增加
- 支付服务：记录支付（本地事务）
- 发送事务消息 → 积分服务增加积分

场景3：注册用户 + 发送邮件
- 用户服务：创建用户（本地事务）
- 发送事务消息 → 邮件服务发送欢迎邮件
```

---

## 二、事务消息原理

### 2.1 两阶段提交流程

```
┌────────────────────────────────────────────────────────┐
│              事务消息完整流程                           │
├────────────────────────────────────────────────────────┤
│                                                         │
│  Producer              Broker             Consumer     │
│     │                    │                   │         │
│     │ 1. 发送Half消息     │                   │         │
│     ├───────────────────▶│                   │         │
│     │                    │ 存储Half消息       │         │
│     │                    │ (不可消费)        │         │
│     │ 2. 返回成功         │                   │         │
│     ◀────────────────────┤                   │         │
│     │                    │                   │         │
│     │ 3. 执行本地事务     │                   │         │
│     │ (创建订单)         │                   │         │
│     │                    │                   │         │
│     │ 4. Commit/Rollback │                   │         │
│     ├───────────────────▶│                   │         │
│     │                    │                   │         │
│     │                    │ 如果Commit:       │         │
│     │                    │ - 转为正常消息     │         │
│     │                    │ - 可被消费         │         │
│     │                    ├──────────────────▶│         │
│     │                    │                   │ 5. 消费 │
│     │                    │                   │ (扣库存) │
│     │                    │                   │         │
│     │                    │ 如果Rollback:     │         │
│     │                    │ - 删除Half消息    │         │
│     │                    │ - 不可消费         │         │
│     │                    │                   │         │
└────────────────────────────────────────────────────────┘
```

### 2.2 事务回查机制

```
问题：Producer 执行完本地事务后，来不及发送 Commit 就宕机了怎么办？

解决：Broker 定期回查事务状态

┌────────────────────────────────────────────┐
│          事务回查流程                        │
├────────────────────────────────────────────┤
│                                             │
│  Broker                    Producer         │
│     │                         │             │
│     │ 1. 检测到超时的Half消息   │             │
│     │                         │             │
│     │ 2. 发起事务状态回查       │             │
│     ├────────────────────────▶│             │
│     │                         │             │
│     │                         │ 3. 查询本地  │
│     │                         │    事务状态  │
│     │                         │             │
│     │ 4. 返回事务状态          │             │
│     │ (COMMIT/ROLLBACK/       │             │
│     │  UNKNOWN)               │             │
│     ◀────────────────────────┤             │
│     │                         │             │
│     │ 5. 根据状态处理Half消息   │             │
│     │                         │             │
└────────────────────────────────────────────┘
```

---

## 三、代码实现

### 3.1 Producer 端实现

```java
public class TransactionProducerExample {

    public static void main(String[] args) throws Exception {
        // 1. 创建事务消息生产者
        TransactionMQProducer producer = new TransactionMQProducer("transaction_producer_group");
        producer.setNamesrvAddr("localhost:9876");

        // 2. 设置事务监听器
        producer.setTransactionListener(new TransactionListener() {

            /**
             * 执行本地事务
             * @param msg 消息
             * @param arg 用户参数
             * @return 本地事务执行结果
             */
            @Override
            public LocalTransactionState executeLocalTransaction(Message msg, Object arg) {
                String orderId = new String(msg.getBody());
                System.out.println("执行本地事务，创建订单：" + orderId);

                try {
                    // 模拟创建订单
                    boolean success = createOrder(orderId);

                    if (success) {
                        // 本地事务成功 → Commit
                        System.out.println("订单创建成功，提交事务消息");
                        return LocalTransactionState.COMMIT_MESSAGE;
                    } else {
                        // 本地事务失败 → Rollback
                        System.out.println("订单创建失败，回滚事务消息");
                        return LocalTransactionState.ROLLBACK_MESSAGE;
                    }
                } catch (Exception e) {
                    // 异常 → 未知状态，等待回查
                    System.out.println("订单创建异常，等待回查：" + e.getMessage());
                    return LocalTransactionState.UNKNOW;
                }
            }

            /**
             * 事务状态回查
             * @param msg 消息
             * @return 事务状态
             */
            @Override
            public LocalTransactionState checkLocalTransaction(MessageExt msg) {
                String orderId = new String(msg.getBody());
                System.out.println("回查事务状态，订单ID：" + orderId);

                // 查询订单是否创建成功
                boolean exists = checkOrderExists(orderId);

                if (exists) {
                    // 订单存在 → Commit
                    System.out.println("订单已存在，提交事务消息");
                    return LocalTransactionState.COMMIT_MESSAGE;
                } else {
                    // 订单不存在 → Rollback
                    System.out.println("订单不存在，回滚事务消息");
                    return LocalTransactionState.ROLLBACK_MESSAGE;
                }
            }
        });

        // 3. 启动生产者
        producer.start();

        // 4. 发送事务消息
        String orderId = "ORDER_" + System.currentTimeMillis();
        Message msg = new Message(
            "order_topic",
            "create",
            orderId.getBytes()
        );

        TransactionSendResult sendResult = producer.sendMessageInTransaction(msg, null);
        System.out.println("发送结果：" + sendResult.getSendStatus());
        System.out.println("本地事务状态：" + sendResult.getLocalTransactionState());

        // 等待回查
        Thread.sleep(60000);

        producer.shutdown();
    }

    // 模拟创建订单
    private static boolean createOrder(String orderId) {
        // 实际业务逻辑：插入订单表
        System.out.println("INSERT INTO orders VALUES ('" + orderId + "', ...)");
        return true;  // 假设成功
    }

    // 检查订单是否存在
    private static boolean checkOrderExists(String orderId) {
        // 实际业务逻辑：查询订单表
        System.out.println("SELECT * FROM orders WHERE id = '" + orderId + "'");
        return true;  // 假设存在
    }
}
```

### 3.2 Consumer 端实现

```java
public class TransactionConsumerExample {

    public static void main(String[] args) throws Exception {
        // 1. 创建消费者
        DefaultMQPushConsumer consumer = new DefaultMQPushConsumer("inventory_consumer_group");
        consumer.setNamesrvAddr("localhost:9876");

        // 2. 订阅Topic
        consumer.subscribe("order_topic", "*");

        // 3. 注册消息监听器
        consumer.registerMessageListener(new MessageListenerConcurrently() {
            @Override
            public ConsumeConcurrentlyStatus consumeMessage(
                List<MessageExt> msgs,
                ConsumeConcurrentlyContext context
            ) {
                for (MessageExt msg : msgs) {
                    String orderId = new String(msg.getBody());
                    System.out.println("收到订单创建消息：" + orderId);

                    try {
                        // 扣减库存
                        boolean success = deductInventory(orderId);

                        if (success) {
                            System.out.println("库存扣减成功");
                            return ConsumeConcurrentlyStatus.CONSUME_SUCCESS;
                        } else {
                            System.out.println("库存扣减失败，重试");
                            return ConsumeConcurrentlyStatus.RECONSUME_LATER;
                        }
                    } catch (Exception e) {
                        System.out.println("库存扣减异常，重试：" + e.getMessage());
                        return ConsumeConcurrentlyStatus.RECONSUME_LATER;
                    }
                }
                return ConsumeConcurrentlyStatus.CONSUME_SUCCESS;
            }
        });

        // 4. 启动消费者
        consumer.start();
        System.out.println("库存服务启动成功");
    }

    // 扣减库存
    private static boolean deductInventory(String orderId) {
        // 实际业务逻辑：扣减库存
        System.out.println("UPDATE inventory SET stock = stock - 1 WHERE order_id = '" + orderId + "'");
        return true;
    }
}
```

---

## 四、存储机制

### 4.1 Half消息存储

```java
// Half消息存储在特殊Topic中
public static final String SYSTEM_TRANSHALF_TOPIC = "RMQ_SYS_TRANS_HALF_TOPIC";

// 消息发送到Broker时
public PutMessageResult putMessage(MessageExtBrokerInner msgInner) {
    // 如果是事务消息
    if (MessageSysFlag.TRANSACTION_PREPARED_TYPE == tranType) {
        // 修改Topic为Half Topic
        msgInner.setTopic(SYSTEM_TRANSHALF_TOPIC);
        msgInner.setQueueId(0);
    }

    // 存储到CommitLog
    PutMessageResult result = this.commitLog.putMessage(msgInner);

    return result;
}
```

### 4.2 Op消息存储

```java
// Op消息用于标记Half消息的状态
public static final String SYSTEM_TRANSOP_TOPIC = "RMQ_SYS_TRANS_OP_HALF_TOPIC";

// Commit/Rollback时写入Op消息
public void putOpMessage(MessageExtBrokerInner msgInner, String opType) {
    msgInner.setTopic(SYSTEM_TRANSOP_TOPIC);
    msgInner.setBody(opType.getBytes());

    // 存储Op消息
    this.commitLog.putMessage(msgInner);
}

// Op消息的作用：
// 1. 记录Half消息已被Commit或Rollback
// 2. 避免重复回查
```

### 4.3 事务状态存储

```
Half消息 + Op消息 组合判断事务状态：

┌──────────────────────────────────────────┐
│         事务状态判断逻辑                  │
├──────────────────────────────────────────┤
│ Half消息存在 + Op消息不存在               │
│ → 事务未完成，需要回查                   │
│                                           │
│ Half消息存在 + Op消息=COMMIT              │
│ → 事务已提交，消息可消费                 │
│                                           │
│ Half消息存在 + Op消息=ROLLBACK            │
│ → 事务已回滚，消息已删除                 │
└──────────────────────────────────────────┘
```

---

## 五、回查机制实现

### 5.1 回查触发条件

```java
public class TransactionalMessageCheckService {

    // 回查配置
    private static final long TRANSACTION_TIMEOUT = 6000;  // 6秒超时
    private static final int MAX_CHECK_TIMES = 15;         // 最多回查15次

    // 定时扫描Half消息
    public void check() {
        try {
            // 1. 从Half Topic读取消息
            GetResult getResult = getHalfMsg(queueId, offset, nums);

            for (MessageExt msgExt : getResult.getMsg()) {
                // 2. 检查是否有对应的Op消息
                if (isOpMessageExist(msgExt)) {
                    continue;  // 已处理，跳过
                }

                // 3. 检查超时时间
                long currentTime = System.currentTimeMillis();
                long tranTime = msgExt.getStoreTimestamp();

                if (currentTime - tranTime < TRANSACTION_TIMEOUT) {
                    continue;  // 未超时，跳过
                }

                // 4. 检查回查次数
                int checkTimes = msgExt.getReconsumeTimes();
                if (checkTimes >= MAX_CHECK_TIMES) {
                    // 超过最大回查次数，强制回滚
                    this.resolveDiscardMsg(msgExt);
                    continue;
                }

                // 5. 发起回查
                this.sendCheckMessage(msgExt);
            }
        } catch (Exception e) {
            log.error("Check transaction error", e);
        }
    }

    // 发送回查请求
    private void sendCheckMessage(MessageExt msgExt) {
        // 构建回查请求
        CheckTransactionStateRequestHeader requestHeader =
            new CheckTransactionStateRequestHeader();
        requestHeader.setCommitLogOffset(msgExt.getCommitLogOffset());
        requestHeader.setTranStateTableOffset(msgExt.getQueueOffset());

        // 发送到Producer
        this.brokerController.getBroker2Client().checkProducerTransactionState(
            msgExt.getBornHostString(),
            requestHeader,
            msgExt
        );
    }
}
```

### 5.2 回查响应处理

```java
// Producer端处理回查请求
public class ClientRemotingProcessor implements NettyRequestProcessor {

    @Override
    public RemotingCommand processRequest(ChannelHandlerContext ctx,
                                         RemotingCommand request) {
        switch (request.getCode()) {
            case RequestCode.CHECK_TRANSACTION_STATE:
                return this.checkTransactionState(ctx, request);
            default:
                break;
        }
        return null;
    }

    // 回查事务状态
    private RemotingCommand checkTransactionState(ChannelHandlerContext ctx,
                                                  RemotingCommand request) {
        // 1. 解析请求
        CheckTransactionStateRequestHeader requestHeader =
            (CheckTransactionStateRequestHeader) request.decodeCommandCustomHeader(
                CheckTransactionStateRequestHeader.class);

        // 2. 获取消息
        MessageExt message = MessageDecoder.decode(request.getBody());

        // 3. 调用用户的TransactionListener
        TransactionListener transactionListener = this.getTransactionListener();
        if (transactionListener != null) {
            LocalTransactionState localTransactionState =
                transactionListener.checkLocalTransaction(message);

            // 4. 返回事务状态
            EndTransactionRequestHeader responseHeader =
                new EndTransactionRequestHeader();
            responseHeader.setTransactionId(requestHeader.getTransactionId());
            responseHeader.setCommitLogOffset(requestHeader.getCommitLogOffset());

            switch (localTransactionState) {
                case COMMIT_MESSAGE:
                    responseHeader.setCommitOrRollback(
                        MessageSysFlag.TRANSACTION_COMMIT_TYPE);
                    break;
                case ROLLBACK_MESSAGE:
                    responseHeader.setCommitOrRollback(
                        MessageSysFlag.TRANSACTION_ROLLBACK_TYPE);
                    break;
                case UNKNOW:
                    responseHeader.setCommitOrRollback(
                        MessageSysFlag.TRANSACTION_NOT_TYPE);
                    break;
            }

            // 5. 发送响应
            this.brokerController.getBroker2Client().endTransactionOneway(
                message.getBrokerAddr(),
                responseHeader,
                "Check transaction state from broker"
            );
        }

        return null;
    }
}
```

---

## 六、最佳实践

### 6.1 幂等性保证

```java
// 问题：消息可能被重复消费，如何保证幂等？

// 方案1：唯一键约束
public boolean deductInventory(String orderId) {
    try {
        // 使用orderId作为唯一键
        jdbcTemplate.update(
            "INSERT INTO inventory_log (order_id, status) VALUES (?, 'DEDUCTED')",
            orderId
        );

        // 扣减库存
        jdbcTemplate.update(
            "UPDATE inventory SET stock = stock - 1 WHERE product_id = ?",
            productId
        );

        return true;
    } catch (DuplicateKeyException e) {
        // 重复消费，直接返回成功
        return true;
    }
}

// 方案2：分布式锁
public boolean deductInventory(String orderId) {
    String lockKey = "inventory:lock:" + orderId;

    if (redisLock.tryLock(lockKey, 10, TimeUnit.SECONDS)) {
        try {
            // 检查是否已处理
            if (isProcessed(orderId)) {
                return true;
            }

            // 扣减库存
            updateInventory(orderId);

            // 标记已处理
            markAsProcessed(orderId);

            return true;
        } finally {
            redisLock.unlock(lockKey);
        }
    }

    return false;
}
```

### 6.2 异常处理

```java
@Override
public LocalTransactionState executeLocalTransaction(Message msg, Object arg) {
    try {
        // 执行本地事务
        executeBusinessLogic(msg);

        return LocalTransactionState.COMMIT_MESSAGE;

    } catch (BusinessException e) {
        // 业务异常 → 明确回滚
        log.error("Business exception, rollback transaction", e);
        return LocalTransactionState.ROLLBACK_MESSAGE;

    } catch (Exception e) {
        // 未知异常 → 返回UNKNOW，等待回查
        log.error("Unknown exception, wait for check", e);
        return LocalTransactionState.UNKNOW;
    }
}
```

### 6.3 性能优化

```properties
# Producer配置
# 事务回查最大次数
transactionCheckMax=15

# 回查间隔时间（毫秒）
transactionCheckInterval=6000

# 事务消息过期时间（小时）
transactionTimeOut=6

# 异步发送（提高吞吐量）
sendMsgTimeout=3000
retryTimesWhenSendFailed=2
```

---

## 七、总结与思考

### 7.1 核心要点

1. **两阶段提交**：Half消息 + 本地事务 + Commit/Rollback
2. **回查机制**：保证事务最终一致性
3. **存储设计**：Half Topic + Op Topic 组合判断状态
4. **幂等性**：Consumer端需要保证消息幂等处理

### 7.2 思考题

1. **为什么需要Op消息？**
   - 提示：避免重复回查

2. **回查次数用尽后怎么办？**
   - 提示：强制回滚或人工介入

3. **事务消息能保证100%可靠吗？**
   - 提示：考虑极端情况

### 7.3 下一步学习

下一篇我们将通过 **订单支付场景**，完整实战事务消息的应用！

---

**本文关键词**：`事务消息` `分布式事务` `两阶段提交` `最终一致性` `回查机制`

**专题导航**：[上一篇：消息路由与负载均衡](/blog/rocketmq/posts/18-message-routing/) | [下一篇：事务消息实战](#)
