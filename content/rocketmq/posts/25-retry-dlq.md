---
title: "RocketMQ进阶07：消息重试与死信队列 - 失败处理的最佳实践"
date: 2025-11-14T10:00:00+08:00
draft: false
tags: ["RocketMQ", "消息重试", "死信队列", "DLQ"]
categories: ["技术"]
description: "理解消息重试机制和死信队列的作用"
series: ["RocketMQ从入门到精通"]
weight: 25
stage: 3
stageTitle: "进阶特性篇"
---

## 引言：消费失败怎么办？

Consumer消费失败时，RocketMQ自动重试：
```
消费失败 → 延迟重试 → 多次重试 → 死信队列
```

## 重试机制

```java
@Override
public ConsumeConcurrentlyStatus consumeMessage(List<MessageExt> msgs) {
    try {
        // 处理消息
        return ConsumeConcurrentlyStatus.CONSUME_SUCCESS;
    } catch (Exception e) {
        // 返回RECONSUME_LATER触发重试
        return ConsumeConcurrentlyStatus.RECONSUME_LATER;
    }
}

// 重试间隔：10s, 30s, 1m, 2m, 3m...最多16次
```

## 死信队列

```
16次重试失败 → 进入死信队列（%DLQ%消费组名）
```

## 死信队列处理

```java
// 监听死信队列
@RocketMQMessageListener(
    topic = "%DLQ%my_consumer_group",
    consumerGroup = "dlq_handler_group"
)
public class DLQHandler implements RocketMQListener<String> {
    @Override
    public void onMessage(String msg) {
        // 人工处理或记录日志
        log.error("死信消息：{}", msg);
    }
}
```

---

**本文关键词**：`消息重试` `死信队列` `DLQ` `失败处理`
