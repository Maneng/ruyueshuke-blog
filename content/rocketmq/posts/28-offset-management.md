---
title: "RocketMQ进阶10：消费进度管理 - Offset存储与重置策略"
date: 2025-11-14T13:00:00+08:00
draft: false
tags: ["RocketMQ", "Offset", "消费进度", "进度管理"]
categories: ["技术"]
description: "深入理解消费进度（Offset）的存储机制和管理策略"
series: ["RocketMQ从入门到精通"]
weight: 28
stage: 3
stageTitle: "进阶特性篇"
---

## 引言：什么是Offset？

Offset（偏移量）记录Consumer的消费进度：
```
Queue中的消息位置：0, 1, 2, 3, 4, 5...
Consumer已消费到：3
下次从4开始消费
```

## Offset存储方式

### 集群模式（Broker存储）

```java
// 自动提交（默认）
consumer.setConsumeFromWhere(ConsumeFromWhere.CONSUME_FROM_LAST_OFFSET);

// Offset存储在Broker端，多个Consumer共享进度
```

### 广播模式（本地存储）

```java
consumer.setMessageModel(MessageModel.BROADCASTING);

// Offset存储在本地文件，每个Consumer独立进度
```

## Offset提交机制

```java
// 1. 自动提交（默认）
// 消费成功后自动提交

// 2. 手动提交
consumer.setAutoCommit(false);
// 业务处理完成后手动提交
context.commitOffset();
```

## Offset重置

### 按时间重置

```bash
# 重置到1小时前
sh mqadmin resetOffsetByTime \
  -g consumerGroup \
  -t topic \
  -s -3600000
```

### 按位置重置

```bash
# 重置到最早
sh mqadmin resetOffsetByTime \
  -g consumerGroup \
  -t topic \
  -s -1

# 重置到最新
sh mqadmin resetOffsetByTime \
  -g consumerGroup \
  -t topic \
  -s 0
```

## 最佳实践

```
1. 集群模式用于分布式消费
2. 广播模式用于全量通知
3. 生产环境定期备份Offset
4. 重置Offset前务必评估影响
```

---

**本文关键词**：`Offset` `消费进度` `进度管理` `重置策略`

🎉 **恭喜！进阶特性篇全部完成！**

已完成：
- ✅ 事务消息（19-20）
- ✅ 顺序消息（21-22）
- ✅ 延迟消息（23）
- ✅ 批量消息（24）
- ✅ 重试与死信（25）
- ✅ 流量控制（26）
- ✅ 消息堆积（27）
- ✅ 进度管理（28）
