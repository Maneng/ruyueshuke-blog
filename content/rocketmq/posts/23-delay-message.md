---
title: "RocketMQ进阶05：延迟消息机制 - 定时任务的优雅实现"
date: 2025-11-14T08:00:00+08:00
draft: false
tags: ["RocketMQ", "延迟消息", "定时任务", "延迟队列"]
categories: ["技术"]
description: "深入理解RocketMQ延迟消息的实现原理和应用场景"
series: ["RocketMQ从入门到精通"]
weight: 23
stage: 3
stageTitle: "进阶特性篇"
---

## 引言：延迟消息的应用场景

典型场景：
- 订单超时自动取消（30分钟未支付）
- 定时推送消息（生日祝福）
- 延迟重试（失败后延迟重试）

## 延迟级别

RocketMQ支持18个延迟级别：
```
1s 5s 10s 30s 1m 2m 3m 4m 5m 6m 7m 8m 9m 10m 20m 30m 1h 2h
```

##实现原理

```java
// 发送延迟消息
Message msg = new Message("topic", "body".getBytes());
msg.setDelayTimeLevel(3);  // 延迟10秒
producer.send(msg);

// 原理：
// 1. 消息先发送到SCHEDULE_TOPIC_XXXX
// 2. 定时任务扫描到期消息
// 3. 投递到目标Topic
```

## 实战案例

```java
// 订单超时取消
public void createOrder(Order order) {
    // 1. 创建订单
    orderService.save(order);
    
    // 2. 发送延迟消息（30分钟）
    Message msg = new Message("order_timeout_topic",
        order.getId().toString().getBytes());
    msg.setDelayTimeLevel(16);  // 30分钟
    producer.send(msg);
}

// Consumer处理超时订单
@Override
public void onMessage(String orderId) {
    Order order = orderService.getById(orderId);
    if ("CREATED".equals(order.getStatus())) {
        // 仍未支付，取消订单
        orderService.cancel(orderId);
    }
}
```

---

**本文关键词**：`延迟消息` `定时任务` `订单超时` `延迟队列`
