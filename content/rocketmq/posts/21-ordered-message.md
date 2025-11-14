---
title: "RocketMQ进阶03：顺序消息原理 - 局部有序与全局有序的设计权衡"
date: 2025-11-14T06:00:00+08:00
draft: false
tags: ["RocketMQ", "顺序消息", "FIFO", "消息顺序性"]
categories: ["技术"]
description: "深入理解RocketMQ顺序消息的实现原理，掌握局部有序和全局有序的使用场景"
series: ["RocketMQ从入门到精通"]
weight: 21
stage: 3
stageTitle: "进阶特性篇"
---

## 引言：为什么需要顺序消息？

**场景**：订单状态流转
```
创建订单 → 支付订单 → 发货 → 确认收货

如果消息乱序：
支付 → 创建 → 发货 ❌  业务错误
```

RocketMQ 提供顺序消息保证消息按照发送顺序消费。

---

## 一、顺序消息类型

### 1.1 全局有序 vs 局部有序

```
┌──────────────────────────────────────────────┐
│           全局有序（Global Order）            │
├──────────────────────────────────────────────┤
│ 特点：所有消息严格按照FIFO顺序                 │
│ 实现：单Queue + 单Consumer线程                │
│ 性能：低（吞吐量受限）                        │
│ 场景：极少使用                                │
│                                               │
│  Queue0: Msg1 → Msg2 → Msg3 → Msg4           │
│                                               │
└──────────────────────────────────────────────┘

┌──────────────────────────────────────────────┐
│          局部有序（Partition Order）          │
├──────────────────────────────────────────────┤
│ 特点：相同Key的消息有序                       │
│ 实现：相同Key路由到同一Queue                  │
│ 性能：高（并发消费）                          │
│ 场景：常用（订单、用户维度有序）              │
│                                               │
│  Queue0: Order1-Msg1 → Order1-Msg2           │
│  Queue1: Order2-Msg1 → Order2-Msg2           │
│  Queue2: Order3-Msg1 → Order3-Msg2           │
│                                               │
└──────────────────────────────────────────────┘
```

### 1.2 实现原理

```
Producer端保证：
1. 相同orderKey的消息发送到同一个Queue
2. 使用MessageQueueSelector选择Queue

Broker端保证：
1. 单个Queue内部FIFO存储
2. CommitLog顺序写

Consumer端保证：
1. 单个Queue只被一个Consumer实例消费
2. 单个Queue内的消息单线程顺序消费
```

---

## 二、代码实现

### 2.1 顺序发送

```java
public class OrderedProducer {

    public static void main(String[] args) throws Exception {
        DefaultMQProducer producer = new DefaultMQProducer("ordered_producer_group");
        producer.setNamesrvAddr("localhost:9876");
        producer.start();

        // 模拟订单消息
        List<OrderStep> orderSteps = buildOrders();

        for (OrderStep step : orderSteps) {
            Message msg = new Message(
                "order_topic",
                step.getTags(),
                step.toString().getBytes()
            );

            // 顺序发送：相同orderId的消息发送到同一个Queue
            SendResult sendResult = producer.send(
                msg,
                new MessageQueueSelector() {
                    @Override
                    public MessageQueue select(
                        List<MessageQueue> mqs,
                        Message msg,
                        Object arg
                    ) {
                        Long orderId = (Long) arg;
                        // Hash取模，确保相同orderId路由到同一Queue
                        int index = (int) (orderId % mqs.size());
                        return mqs.get(index);
                    }
                },
                step.getOrderId()  // orderKey
            );

            System.out.printf("发送：%s, Queue=%d%n",
                step, sendResult.getMessageQueue().getQueueId());
        }

        producer.shutdown();
    }

    // 构建订单步骤
    private static List<OrderStep> buildOrders() {
        List<OrderStep> steps = new ArrayList<>();

        // 订单1001
        steps.add(new OrderStep(1001L, "创建"));
        steps.add(new OrderStep(1001L, "支付"));
        steps.add(new OrderStep(1001L, "发货"));

        // 订单1002
        steps.add(new OrderStep(1002L, "创建"));
        steps.add(new OrderStep(1002L, "支付"));

        // 订单1003
        steps.add(new OrderStep(1003L, "创建"));

        return steps;
    }
}

class OrderStep {
    private Long orderId;
    private String status;

    public OrderStep(Long orderId, String status) {
        this.orderId = orderId;
        this.status = status;
    }

    public Long getOrderId() {
        return orderId;
    }

    public String getTags() {
        return status;
    }

    @Override
    public String toString() {
        return "Order=" + orderId + ", Status=" + status;
    }
}
```

### 2.2 顺序消费

```java
public class OrderedConsumer {

    public static void main(String[] args) throws Exception {
        DefaultMQPushConsumer consumer = new DefaultMQPushConsumer("ordered_consumer_group");
        consumer.setNamesrvAddr("localhost:9876");
        consumer.subscribe("order_topic", "*");

        // 注册顺序消息监听器
        consumer.registerMessageListener(new MessageListenerOrderly() {

            @Override
            public ConsumeOrderlyStatus consumeMessage(
                List<MessageExt> msgs,
                ConsumeOrderlyContext context
            ) {
                // 单线程顺序消费
                for (MessageExt msg : msgs) {
                    System.out.printf(
                        "消费：Thread=%s, Queue=%d, Msg=%s%n",
                        Thread.currentThread().getName(),
                        msg.getQueueId(),
                        new String(msg.getBody())
                    );
                }

                return ConsumeOrderlyStatus.SUCCESS;
            }
        });

        consumer.start();
        System.out.println("顺序消费启动成功");
    }
}
```

**输出示例**：
```
发送：Order=1001, Status=创建, Queue=1
发送：Order=1001, Status=支付, Queue=1
发送：Order=1001, Status=发货, Queue=1
发送：Order=1002, Status=创建, Queue=2
发送：Order=1002, Status=支付, Queue=2

消费：Thread=ConsumeMessageThread_1, Queue=1, Msg=Order=1001, Status=创建
消费：Thread=ConsumeMessageThread_1, Queue=1, Msg=Order=1001, Status=支付
消费：Thread=ConsumeMessageThread_1, Queue=1, Msg=Order=1001, Status=发货
消费：Thread=ConsumeMessageThread_2, Queue=2, Msg=Order=1002, Status=创建
消费：Thread=ConsumeMessageThread_2, Queue=2, Msg=Order=1002, Status=支付
```

---

## 三、实现原理深度剖析

### 3.1 Queue级别锁机制

```java
public class MessageListenerOrderly {

    // 消费时对Queue加锁
    public ConsumeOrderlyStatus consumeMessage(
        List<MessageExt> msgs,
        ConsumeOrderlyContext context
    ) {
        // 1. 获取Queue锁（本地锁 + Broker锁）
        MessageQueue mq = context.getMessageQueue();
        Object lock = this.processQueueTable.get(mq);

        synchronized (lock) {  // Queue级别锁
            // 2. 顺序消费消息
            for (MessageExt msg : msgs) {
                // 处理消息
            }

            // 3. 提交消费进度
            this.updateOffset(mq, msgs);
        }

        return ConsumeOrderlyStatus.SUCCESS;
    }
}
```

### 3.2 Broker端分布式锁

```java
// Consumer启动时向Broker申请Queue锁
public class RebalanceImpl {

    public void lock(MessageQueue mq) {
        // 向Broker发送锁定请求
        Set<MessageQueue> lockedMqs =
            this.mQClientFactory.getMQClientAPIImpl().lockBatchMQ(
                brokerAddr,
                requestBody,
                1000
            );

        // 锁定成功，开始消费
        if (lockedMqs.contains(mq)) {
            processQueue.setLocked(true);
        }
    }
}
```

---

## 四、性能对比

| 对比项 | 顺序消息 | 普通消息 |
|-------|---------|---------|
| 吞吐量 | 低（单线程） | 高（多线程并发） |
| 延迟 | 略高 | 低 |
| 消费模式 | 串行 | 并行 |
| 适用场景 | 强顺序要求 | 高吞吐要求 |

---

## 五、最佳实践

### 5.1 选择合适的顺序级别

```
场景1：交易流水
- 需求：同一用户的交易有序
- 方案：局部有序（userId作为orderKey）

场景2：配置下发
- 需求：所有配置按时间顺序下发
- 方案：全局有序（单Queue）

场景3：日志采集
- 需求：无顺序要求
- 方案：普通消息（性能最高）
```

### 5.2 注意事项

```
❌ 避免：
- orderKey选择过于分散（导致Queue分布不均）
- orderKey选择过于集中（导致单Queue压力大）
- 消费逻辑耗时过长（阻塞后续消息）

✅ 推荐：
- orderKey选择均衡（如userId, orderId）
- 消费逻辑简单快速
- 异常处理完善（避免死循环）
```

---

## 六、总结

1. **局部有序**：相同Key消息有序，性能高，推荐使用
2. **全局有序**：所有消息有序，性能低，极少使用
3. **实现原理**：Queue级别锁 + 单线程消费
4. **性能权衡**：顺序性 vs 吞吐量

**下一篇**：通过订单状态流转案例，实战顺序消息！

---

**本文关键词**：`顺序消息` `局部有序` `全局有序` `FIFO` `Queue锁`

**专题导航**：[上一篇：事务消息实战](/blog/rocketmq/posts/20-transaction-practice/) | [下一篇：顺序消息实战](#)
