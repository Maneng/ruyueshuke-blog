---
title: "RocketMQ进阶08：流量控制机制 - 保护系统的最后防线"
date: 2025-11-14T11:00:00+08:00
draft: false
tags: ["RocketMQ", "流量控制", "限流", "背压"]
categories: ["技术"]
description: "理解RocketMQ的流量控制机制，保护系统稳定性"
series: ["RocketMQ从入门到精通"]
weight: 26
stage: 3
stageTitle: "进阶特性篇"
---

## 引言：为什么需要流量控制？

防止系统过载：
```
Consumer处理速度：100条/秒
消息生产速度：1000条/秒

结果：消息堆积 → 内存溢出 → 系统崩溃
```

## Producer端限流

```java
// 设置发送超时
producer.setSendMsgTimeout(3000);

// 异步发送队列大小限制
producer.setMaxMessageSize(4 * 1024 * 1024);  // 4MB
```

## Consumer端限流

```java
// 1. 限制拉取数量
consumer.setPullBatchSize(32);  // 每次最多拉32条

// 2. 限制并发消费线程
consumer.setConsumeThreadMin(20);
consumer.setConsumeThreadMax(20);

// 3. 限制消费速率
consumer.setPullInterval(100);  // 拉取间隔100ms
```

## Broker端流控

```
触发条件：
1. 内存使用超过85%
2. 消息堆积超过阈值
3. PageCache繁忙

流控动作：
- 拒绝Producer发送
- 降低Consumer拉取频率
```

---

**本文关键词**：`流量控制` `限流` `背压` `系统保护`
