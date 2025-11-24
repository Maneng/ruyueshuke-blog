---
title: "RocketMQ云原生04：RocketMQ Streams - 轻量级流处理框架"
date: 2025-11-15T18:00:00+08:00
draft: false
tags: ["RocketMQ", "Streams", "流处理", "实时计算"]
categories: ["技术"]
description: "使用 RocketMQ Streams 实现轻量级流处理，无需额外组件"
series: ["RocketMQ从入门到精通"]
weight: 42
stage: 5
stageTitle: "云原生演进篇"
---

## 引言：流处理的简化之道

Flink/Spark Streaming：功能强大，但部署复杂，资源消耗大。

RocketMQ Streams：轻量级，与 RocketMQ 深度集成，开箱即用。

**本文目标**：
- 理解 RocketMQ Streams 核心概念
- 掌握流处理基本操作
- 实现实时数据分析
- 对比其他流处理框架

---

## 一、RocketMQ Streams 简介

### 1.1 什么是 RocketMQ Streams？

**定义**：基于 RocketMQ 的轻量级流处理框架，提供类似 Kafka Streams 的 API。

**架构**：
```
┌─────────────────────────────────────────┐
│      RocketMQ Streams Application       │
│                                         │
│  ┌──────────┐  ┌──────────┐  ┌───────┐ │
│  │  Source  │─>│ Process  │─>│ Sink  │ │
│  │(消费消息)│  │(转换处理)│  │(输出)  │ │
│  └────┬─────┘  └──────────┘  └───────┘ │
└───────┼─────────────────────────────────┘
        │
┌───────▼─────────────────────────────────┐
│          RocketMQ Cluster               │
│  ┌──────────┐  ┌──────────┐            │
│  │  Topic A │  │  Topic B │            │
│  └──────────┘  └──────────┘            │
└─────────────────────────────────────────┘
```

---

### 1.2 核心特性

| 特性 | RocketMQ Streams | Kafka Streams | Flink |
|------|-----------------|---------------|-------|
| **轻量级** | ✅ 极轻量 | ✅ 轻量 | ❌ 重量级 |
| **部署复杂度** | 低（无需额外组件） | 低 | 高 |
| **学习成本** | 低 | 中 | 高 |
| **状态管理** | 简单 | 中等 | 复杂 |
| **适用场景** | 简单流处理 | 中等复杂度 | 复杂流处理 |

---

## 二、快速开始

### 2.1 Maven 依赖

```xml
<dependency>
    <groupId>org.apache.rocketmq</groupId>
    <artifactId>rocketmq-streams</artifactId>
    <version>1.1.0</version>
</dependency>

<dependency>
    <groupId>org.apache.rocketmq</groupId>
    <artifactId>rocketmq-client</artifactId>
    <version>5.0.0</version>
</dependency>
```

---

### 2.2 第一个 Streams 应用

```java
import org.apache.rocketmq.streams.core.RocketMQStream;
import org.apache.rocketmq.streams.core.topology.TopologyBuilder;

public class WordCountExample {

    public static void main(String[] args) {
        // 1. 配置 RocketMQ 连接
        Properties properties = new Properties();
        properties.put("nameserver.address", "127.0.0.1:9876");
        properties.put("group.id", "stream_app_group");

        // 2. 创建 TopologyBuilder
        TopologyBuilder builder = new TopologyBuilder();

        // 3. 定义流处理逻辑
        builder
            // 从 Topic 读取消息
            .source("input_topic")

            // 分词
            .flatMap((key, value) -> {
                List<KeyValue<String, String>> result = new ArrayList<>();
                for (String word : value.toString().split(" ")) {
                    result.add(new KeyValue<>(word, "1"));
                }
                return result;
            })

            // 按单词分组计数
            .groupBy(kv -> kv.getKey())
            .count()

            // 输出到 Topic
            .to("output_topic");

        // 4. 启动 Streams 应用
        RocketMQStream stream = new RocketMQStream(builder.build(), properties);
        stream.start();

        System.out.println("Streams 应用已启动");
    }
}
```

---

## 三、核心操作

### 3.1 Source（数据源）

```java
// 从单个 Topic 读取
builder.source("input_topic")

// 从多个 Topic 读取
builder.source("topic1", "topic2", "topic3")

// 指定起始位置
builder.source("input_topic", ConsumeFromWhere.CONSUME_FROM_LAST_OFFSET)
```

---

### 3.2 转换操作

#### 3.2.1 Map（一对一映射）

```java
builder
    .source("user_topic")
    .map((key, value) -> {
        User user = JSON.parseObject(value, User.class);
        return new KeyValue<>(user.getId(), user.getName().toUpperCase());
    });
```

---

#### 3.2.2 FlatMap（一对多映射）

```java
builder
    .source("sentence_topic")
    .flatMap((key, value) -> {
        List<KeyValue<String, Integer>> words = new ArrayList<>();
        for (String word : value.split(" ")) {
            words.add(new KeyValue<>(word, 1));
        }
        return words;
    });
```

---

#### 3.2.3 Filter（过滤）

```java
builder
    .source("order_topic")
    .filter((key, value) -> {
        Order order = JSON.parseObject(value, Order.class);
        return order.getAmount() > 100;  // 只保留金额 > 100 的订单
    });
```

---

### 3.3 聚合操作

#### 3.3.1 GroupBy + Count

```java
builder
    .source("click_topic")
    .map((key, value) -> {
        ClickEvent event = JSON.parseObject(value, ClickEvent.class);
        return new KeyValue<>(event.getUserId(), 1);
    })
    .groupBy(kv -> kv.getKey())
    .count()  // 统计每个用户的点击次数
    .to("click_count_topic");
```

---

#### 3.3.2 GroupBy + Sum

```java
builder
    .source("order_topic")
    .map((key, value) -> {
        Order order = JSON.parseObject(value, Order.class);
        return new KeyValue<>(order.getUserId(), order.getAmount());
    })
    .groupBy(kv -> kv.getKey())
    .sum()  // 统计每个用户的订单总金额
    .to("user_amount_topic");
```

---

### 3.4 窗口操作

#### 3.4.1 滚动窗口（Tumbling Window）

```java
builder
    .source("metric_topic")
    .groupBy(kv -> kv.getKey())
    .window(TumblingWindow.of(Duration.ofMinutes(5)))  // 5 分钟窗口
    .count()
    .to("metric_count_topic");
```

---

#### 3.4.2 滑动窗口（Sliding Window）

```java
builder
    .source("traffic_topic")
    .groupBy(kv -> kv.getKey())
    .window(SlidingWindow.of(
        Duration.ofMinutes(10),  // 窗口大小
        Duration.ofMinutes(1)    // 滑动步长
    ))
    .sum()
    .to("traffic_sum_topic");
```

---

### 3.5 Join 操作

```java
// Stream-Stream Join
RocketMQStream stream1 = builder.source("order_topic");
RocketMQStream stream2 = builder.source("payment_topic");

stream1
    .join(stream2,
        (order, payment) -> {
            // 关联订单和支付信息
            return new OrderPayment(order, payment);
        },
        JoinWindows.of(Duration.ofMinutes(5))  // 5 分钟时间窗口内关联
    )
    .to("order_payment_topic");
```

---

## 四、实战案例

### 4.1 实时订单金额统计

```java
/**
 * 需求：实时统计每分钟的订单总金额
 */
public class OrderAmountAggregation {

    public static void main(String[] args) {
        TopologyBuilder builder = new TopologyBuilder();

        builder
            // 1. 从订单 Topic 读取
            .source("order_topic")

            // 2. 解析订单，提取金额
            .map((key, value) -> {
                Order order = JSON.parseObject(value, Order.class);
                return new KeyValue<>("total", order.getAmount());
            })

            // 3. 按 key 分组（这里都是 "total"）
            .groupBy(kv -> kv.getKey())

            // 4. 1 分钟滚动窗口聚合
            .window(TumblingWindow.of(Duration.ofMinutes(1)))
            .reduce((v1, v2) -> v1 + v2)

            // 5. 输出结果
            .map((key, value) -> {
                Map<String, Object> result = new HashMap<>();
                result.put("minute", System.currentTimeMillis() / 60000);
                result.put("totalAmount", value);
                return new KeyValue<>(key, JSON.toJSONString(result));
            })
            .to("order_amount_stat_topic");

        // 启动
        Properties props = new Properties();
        props.put("nameserver.address", "127.0.0.1:9876");
        props.put("group.id", "order_amount_app");

        RocketMQStream stream = new RocketMQStream(builder.build(), props);
        stream.start();
    }
}
```

---

### 4.2 实时用户行为分析

```java
/**
 * 需求：识别 5 分钟内连续点击超过 100 次的用户（异常行为）
 */
public class AbnormalUserDetection {

    public static void main(String[] args) {
        TopologyBuilder builder = new TopologyBuilder();

        builder
            .source("click_topic")

            // 解析点击事件
            .map((key, value) -> {
                ClickEvent event = JSON.parseObject(value, ClickEvent.class);
                return new KeyValue<>(event.getUserId(), 1);
            })

            // 按用户分组
            .groupBy(kv -> kv.getKey())

            // 5 分钟滚动窗口计数
            .window(TumblingWindow.of(Duration.ofMinutes(5)))
            .count()

            // 过滤出异常用户
            .filter((userId, count) -> count > 100)

            // 告警
            .foreach((userId, count) -> {
                System.out.println("告警：用户 " + userId + " 5分钟内点击 " + count + " 次");
                // 发送告警消息
                alertService.sendAlert(userId, count);
            });

        RocketMQStream stream = new RocketMQStream(builder.build(), properties);
        stream.start();
    }
}
```

---

## 五、状态管理

### 5.1 本地状态存储

```java
// 配置本地状态存储
properties.put("state.dir", "/tmp/rocketmq-streams-state");

// 使用状态
builder
    .source("event_topic")
    .groupBy(kv -> kv.getKey())
    .aggregate(
        () -> 0,  // 初始值
        (key, newValue, aggValue) -> aggValue + newValue,  // 累加
        Materialized.as("event-count-store")  // 状态存储名称
    );
```

---

### 5.2 查询状态

```java
// 查询状态存储
ReadOnlyKeyValueStore<String, Long> store =
    stream.store("event-count-store", QueryableStoreTypes.keyValueStore());

Long count = store.get("user123");
System.out.println("用户 user123 的事件数：" + count);
```

---

## 六、最佳实践

### 6.1 性能优化

```java
// 1. 批量处理
properties.put("batch.size", 100);

// 2. 异步处理
properties.put("async.enabled", true);

// 3. 并行度配置
properties.put("parallelism", 4);
```

---

### 6.2 异常处理

```java
builder
    .source("input_topic")
    .map((key, value) -> {
        try {
            return process(value);
        } catch (Exception e) {
            // 记录错误日志
            logger.error("处理失败", e);
            // 发送到错误 Topic
            sendToErrorTopic(value, e);
            return null;
        }
    })
    .filter(Objects::nonNull);  // 过滤失败的消息
```

---

### 6.3 监控指标

```java
// 配置监控
properties.put("metrics.enabled", true);
properties.put("metrics.reporters", "org.apache.rocketmq.streams.metrics.PrometheusReporter");

// 暴露指标
// - streams_records_consumed_total
// - streams_records_produced_total
// - streams_process_latency_ms
```

---

## 七、与其他框架对比

| 对比项 | RocketMQ Streams | Kafka Streams | Flink |
|--------|-----------------|---------------|-------|
| **部署** | 无需额外组件 | 无需额外组件 | 需独立集群 |
| **状态后端** | 本地 RocksDB | 本地 RocksDB | 多种选择 |
| **Exactly-Once** | 支持 | 支持 | 支持 |
| **窗口类型** | 滚动/滑动 | 滚动/滑动/会话 | 全面支持 |
| **CEP 支持** | ❌ | ❌ | ✅ |
| **SQL 支持** | ❌ | ✅ | ✅ |
| **学习成本** | 低 | 中 | 高 |

**选择建议**：
- 简单流处理 → RocketMQ Streams
- 中等复杂度 → Kafka Streams
- 复杂流处理 → Flink

---

## 八、总结

### RocketMQ Streams 核心价值

```
1. 轻量级：无需额外组件
2. 易上手：API 简洁直观
3. 集成好：与 RocketMQ 深度集成
4. 够用：满足大部分流处理场景
```

### 适用场景

✅ **推荐使用**：
- 实时指标聚合
- 简单 ETL 任务
- 实时告警
- 用户行为分析

❌ **不推荐使用**：
- 复杂事件处理（CEP）
- 大规模状态管理
- 超低延迟要求（< 10ms）

---

**下一篇预告**：《EventBridge 事件总线 - 事件驱动架构实践》，探索事件驱动架构在微服务中的应用。

**本文关键词**：`RocketMQ Streams` `流处理` `实时计算` `轻量级`
