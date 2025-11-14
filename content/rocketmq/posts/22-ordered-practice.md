---
title: "RocketMQ进阶04：顺序消息实战 - 订单状态流转的有序保证"
date: 2025-11-14T07:00:00+08:00
draft: false
tags: ["RocketMQ", "顺序消息", "订单系统", "状态机"]
categories: ["技术"]
description: "通过订单状态流转实战案例，掌握顺序消息在业务中的应用"
series: ["RocketMQ从入门到精通"]
weight: 22
stage: 3
stageTitle: "进阶特性篇"
---

## 引言：订单状态机

订单状态必须按照固定流程流转：
```
待支付 → 已支付 → 已发货 → 已完成
```

使用顺序消息保证状态流转的正确性。

## 实现代码

```java
// Producer：发送订单状态变更消息
public class OrderStatusProducer {
    public void changeStatus(Long orderId, String newStatus) {
        Message msg = new Message("order_status_topic",
            newStatus.getBytes());
        
        // 使用orderId作为orderKey，保证同一订单消息有序
        producer.send(msg, (mqs, msg1, arg) -> {
            int index = (int) (orderId % mqs.size());
            return mqs.get(index);
        }, orderId);
    }
}

// Consumer：顺序处理状态变更
@RocketMQMessageListener(
    topic = "order_status_topic",
    consumerGroup = "order_status_group",
    consumeMode = ConsumeMode.ORDERLY  // 顺序消费
)
public class OrderStatusConsumer implements RocketMQListener<String> {
    
    @Override
    public void onMessage(String newStatus) {
        // 验证状态流转合法性
        if (isValidTransition(currentStatus, newStatus)) {
            updateOrderStatus(orderId, newStatus);
        } else {
            log.error("非法状态流转");
        }
    }
}
```

## 核心要点

1. **orderKey选择**：使用orderId保证同一订单有序
2. **状态验证**：Consumer端验证状态流转合法性
3. **异常处理**：非法状态流转记录日志并告警

---

**本文关键词**：`顺序消息实战` `订单状态` `状态机` `有序流转`
