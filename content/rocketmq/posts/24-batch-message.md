---
title: "RocketMQ进阶06：批量消息优化 - 提升吞吐量的利器"
date: 2025-11-14T09:00:00+08:00
draft: false
tags: ["RocketMQ", "批量消息", "性能优化", "吞吐量"]
categories: ["技术"]
description: "掌握批量消息的使用方法，大幅提升系统吞吐量"
series: ["RocketMQ从入门到精通"]
weight: 24
stage: 3
stageTitle: "进阶特性篇"
---

## 引言：批量的力量

单条发送 vs 批量发送：
- 单条：1万TPS
- 批量：10万TPS（提升10倍）

## 批量发送

```java
List<Message> messages = new ArrayList<>();
for (int i = 0; i < 100; i++) {
    Message msg = new Message("topic", ("Msg" + i).getBytes());
    messages.add(msg);
}

// 批量发送（一次网络调用）
SendResult result = producer.send(messages);
```

## 批量大小限制

```
单批最大：4MB
建议：每批100-1000条消息
```

## 性能对比

| 方式 | TPS | 延迟 |
|------|-----|------|
| 单条发送 | 1万 | 5ms |
| 批量发送 | 10万 | 10ms |

---

**本文关键词**：`批量消息` `性能优化` `高吞吐量`
