---
title: "RocketMQ入门07：消息模型深入 - 点对点vs发布订阅"
date: 2025-11-13T16:00:00+08:00
draft: false
tags: ["RocketMQ", "消息模型", "点对点", "发布订阅", "架构设计"]
categories: ["技术"]
description: "深入理解消息队列的两种基本模型：点对点（P2P）和发布订阅（Pub/Sub），以及 RocketMQ 如何巧妙地统一这两种模型"
series: ["RocketMQ从入门到精通"]
weight: 7
stage: 1
stageTitle: "基础入门篇"
---

## 引言：一个模型，两种模式

传统消息系统通常要在两种模型中二选一：
- **JMS**：明确区分 Queue（点对点）和 Topic（发布订阅）
- **AMQP**：通过 Exchange 和 Binding 实现不同模式
- **Kafka**：只有 Topic，通过 Consumer Group 实现不同语义

而 RocketMQ 的独特之处在于：**用一套模型，同时支持两种模式**。

让我们深入理解这是如何实现的。

## 一、两种基本消息模型

### 1.1 点对点模型（Point-to-Point）

```java
public class P2PModel {

    // 点对点模型特征
    class Characteristics {
        // 1. 一条消息只能被一个消费者消费
        // 2. 消息被消费后从队列中删除
        // 3. 多个消费者竞争消息
        // 4. 适合任务分发场景
    }

    // 传统 JMS Queue 实现
    class TraditionalQueue {
        Queue<Message> queue = new LinkedBlockingQueue<>();

        // 生产者发送
        public void send(Message msg) {
            queue.offer(msg);
        }

        // 消费者接收（竞争）
        public Message receive() {
            return queue.poll();  // 取出即删除
        }
    }
}
```

```
点对点模型示意图：
         ┌──────────┐
Producer ──> Queue  ──> Consumer1 (获得消息)
         └──────────┘
                    ──> Consumer2 (没有获得)
                    ──> Consumer3 (没有获得)

特点：消息被其中一个消费者消费后，其他消费者无法再消费
```

### 1.2 发布订阅模型（Publish-Subscribe）

```java
public class PubSubModel {

    // 发布订阅模型特征
    class Characteristics {
        // 1. 一条消息可以被多个订阅者消费
        // 2. 每个订阅者都能收到完整消息副本
        // 3. 消息广播给所有订阅者
        // 4. 适合事件通知场景
    }

    // 传统 JMS Topic 实现
    class TraditionalTopic {
        List<Subscriber> subscribers = new ArrayList<>();

        // 发布消息
        public void publish(Message msg) {
            // 广播给所有订阅者
            for (Subscriber sub : subscribers) {
                sub.onMessage(msg.copy());
            }
        }

        // 订阅主题
        public void subscribe(Subscriber sub) {
            subscribers.add(sub);
        }
    }
}
```

```
发布订阅模型示意图：
                    ┌──> Consumer1 (收到消息)
         ┌────────┐ │
Producer ──> Topic ──┼──> Consumer2 (收到消息)
         └────────┘ │
                    └──> Consumer3 (收到消息)

特点：每个订阅者都能收到消息的完整副本
```

## 二、RocketMQ 的统一模型

### 2.1 核心设计：Consumer Group

```java
public class RocketMQModel {

    // RocketMQ 的秘密：通过 Consumer Group 实现两种模式
    class ConsumerGroup {
        String groupName;
        List<Consumer> consumers;
        ConsumeMode mode;  // 集群消费 or 广播消费
    }

    // 关键规则：
    // 1. 同一 Consumer Group 内的消费者【分摊】消息（点对点）
    // 2. 不同 Consumer Group 都能收到【全量】消息（发布订阅）
}
```

### 2.2 模式切换的魔法

```java
public class ModelSwitching {

    // 场景1：实现点对点模式
    public void p2pMode() {
        // 所有消费者使用【相同】的 Consumer Group
        String GROUP = "SAME_GROUP";

        Consumer consumer1 = new DefaultMQPushConsumer(GROUP);
        Consumer consumer2 = new DefaultMQPushConsumer(GROUP);
        Consumer consumer3 = new DefaultMQPushConsumer(GROUP);

        // 结果：消息被分摊消费，每条消息只被其中一个消费
    }

    // 场景2：实现发布订阅模式
    public void pubSubMode() {
        // 每个消费者使用【不同】的 Consumer Group
        Consumer consumer1 = new DefaultMQPushConsumer("GROUP_A");
        Consumer consumer2 = new DefaultMQPushConsumer("GROUP_B");
        Consumer consumer3 = new DefaultMQPushConsumer("GROUP_C");

        // 结果：每个 Group 都收到全量消息
    }

    // 场景3：混合模式
    public void mixedMode() {
        // 订单服务组（2个实例）
        Consumer order1 = new DefaultMQPushConsumer("ORDER_GROUP");
        Consumer order2 = new DefaultMQPushConsumer("ORDER_GROUP");

        // 库存服务组（3个实例）
        Consumer stock1 = new DefaultMQPushConsumer("STOCK_GROUP");
        Consumer stock2 = new DefaultMQPushConsumer("STOCK_GROUP");
        Consumer stock3 = new DefaultMQPushConsumer("STOCK_GROUP");

        // 结果：
        // - ORDER_GROUP 内部：order1 和 order2 分摊消息
        // - STOCK_GROUP 内部：stock1/2/3 分摊消息
        // - 两个 GROUP 之间：都能收到全量消息
    }
}
```

## 三、集群消费 vs 广播消费

### 3.1 集群消费（默认）

```java
public class ClusterConsumeMode {

    public void setup() {
        DefaultMQPushConsumer consumer = new DefaultMQPushConsumer("GROUP");

        // 设置集群消费模式（默认）
        consumer.setMessageModel(MessageModel.CLUSTERING);

        consumer.subscribe("TOPIC", "*");
    }

    // 集群消费特点
    class ClusteringCharacteristics {
        // 1. 同组内消费者分摊消息
        // 2. 消费进度存储在 Broker
        // 3. 支持消费失败重试
        // 4. 适合负载均衡场景
    }

    // 消费进度管理
    class ProgressManagement {
        // Broker 端统一管理消费进度
        // 路径：{ROCKETMQ_HOME}/store/config/consumerOffset.json
        {
            "offsetTable": {
                "TOPIC@GROUP": {
                    "0": 12345,  // Queue0 消费到 12345
                    "1": 23456,  // Queue1 消费到 23456
                    "2": 34567,  // Queue2 消费到 34567
                    "3": 45678   // Queue3 消费到 45678
                }
            }
        }
    }
}
```

```
集群消费示意图：
              Queue0 ──> Consumer1 ─┐
              Queue1 ──> Consumer1 ─┤
Topic ──>                           ├─> GROUP_A (共享进度)
              Queue2 ──> Consumer2 ─┤
              Queue3 ──> Consumer2 ─┘

GROUP_A 的消费进度存储在 Broker，所有成员共享
```

### 3.2 广播消费

```java
public class BroadcastConsumeMode {

    public void setup() {
        DefaultMQPushConsumer consumer = new DefaultMQPushConsumer("GROUP");

        // 设置广播消费模式
        consumer.setMessageModel(MessageModel.BROADCASTING);

        consumer.subscribe("TOPIC", "*");
    }

    // 广播消费特点
    class BroadcastingCharacteristics {
        // 1. 每个消费者都消费全量消息
        // 2. 消费进度存储在本地
        // 3. 不支持消费失败重试
        // 4. 适合本地缓存更新场景
    }

    // 消费进度管理
    class LocalProgress {
        // 本地文件存储消费进度
        // 路径：{user.home}/.rocketmq_offsets/{clientId}/{group}/offsets.json
        {
            "offsetTable": {
                "TOPIC": {
                    "0": 99999,  // 本实例 Queue0 进度
                    "1": 88888,  // 本实例 Queue1 进度
                    "2": 77777,  // 本实例 Queue2 进度
                    "3": 66666   // 本实例 Queue3 进度
                }
            }
        }
    }
}
```

```
广播消费示意图：
              ┌─> Consumer1 (消费全部消息，独立进度)
              │
Topic ──> ────┼─> Consumer2 (消费全部消息，独立进度)
              │
              └─> Consumer3 (消费全部消息，独立进度)

每个 Consumer 独立维护自己的消费进度
```

## 四、消息分配策略

### 4.1 集群模式下的分配策略

```java
public class AllocationStrategy {

    // 1. 平均分配（默认）
    class AllocateMessageQueueAveragely {
        // 假设：4个Queue，2个Consumer
        // Consumer1: Queue0, Queue1
        // Consumer2: Queue2, Queue3

        // 假设：5个Queue，2个Consumer
        // Consumer1: Queue0, Queue1, Queue2
        // Consumer2: Queue3, Queue4
    }

    // 2. 环形分配
    class AllocateMessageQueueAveragelyByCircle {
        // 假设：5个Queue，2个Consumer
        // Consumer1: Queue0, Queue2, Queue4
        // Consumer2: Queue1, Queue3
    }

    // 3. 机房就近分配
    class AllocateMessageQueueByMachineRoom {
        // 根据 Consumer 和 Broker 的机房位置分配
        // 优先分配同机房的 Queue
    }

    // 4. 一致性Hash分配
    class AllocateMessageQueueConsistentHash {
        // 使用一致性Hash算法
        // Consumer 上下线对其他 Consumer 影响最小
    }

    // 5. 自定义分配
    class CustomAllocateStrategy implements AllocateMessageQueueStrategy {
        @Override
        public List<MessageQueue> allocate(
            String consumerGroup,
            String currentCID,
            List<MessageQueue> mqAll,
            List<String> cidAll) {

            // 自定义分配逻辑
            // 比如：VIP Consumer 分配更多 Queue
            if (isVipConsumer(currentCID)) {
                return allocateMoreQueues(mqAll, currentCID);
            }
            return allocateNormalQueues(mqAll, currentCID);
        }
    }
}
```

### 4.2 分配策略选择

```java
public class StrategySelection {

    public void selectStrategy() {
        DefaultMQPushConsumer consumer = new DefaultMQPushConsumer();

        // 设置分配策略
        consumer.setAllocateMessageQueueStrategy(
            new AllocateMessageQueueAveragely()
        );

        // 根据场景选择
        class ScenarioBasedSelection {
            // 场景1：消费者能力相同 → 平均分配
            // 场景2：跨机房部署 → 机房就近
            // 场景3：Consumer频繁上下线 → 一致性Hash
            // 场景4：Consumer能力不同 → 自定义策略
        }
    }
}
```

## 五、实战场景分析

### 5.1 订单处理系统

```java
public class OrderProcessingSystem {

    // 需求：订单需要被多个系统处理，但每个系统只处理一次

    // 订单服务（2个实例，负载均衡）
    class OrderService {
        void startConsumers() {
            // 使用相同 Group，实现负载均衡
            Consumer instance1 = createConsumer("ORDER_SERVICE_GROUP");
            Consumer instance2 = createConsumer("ORDER_SERVICE_GROUP");
            // 结果：订单在两个实例间负载均衡
        }
    }

    // 库存服务（3个实例，负载均衡）
    class StockService {
        void startConsumers() {
            // 使用相同 Group，实现负载均衡
            Consumer instance1 = createConsumer("STOCK_SERVICE_GROUP");
            Consumer instance2 = createConsumer("STOCK_SERVICE_GROUP");
            Consumer instance3 = createConsumer("STOCK_SERVICE_GROUP");
            // 结果：订单在三个实例间负载均衡
        }
    }

    // 积分服务（1个实例）
    class PointService {
        void startConsumer() {
            Consumer instance = createConsumer("POINT_SERVICE_GROUP");
            // 结果：所有订单都由这个实例处理
        }
    }

    // 效果：
    // 1. 每个订单被 ORDER_SERVICE_GROUP 处理一次
    // 2. 每个订单被 STOCK_SERVICE_GROUP 处理一次
    // 3. 每个订单被 POINT_SERVICE_GROUP 处理一次
}
```

### 5.2 配置更新系统

```java
public class ConfigUpdateSystem {

    // 需求：配置更新需要通知所有服务实例

    class ConfigUpdateConsumer {
        void setup() {
            DefaultMQPushConsumer consumer = new DefaultMQPushConsumer("CONFIG_GROUP");

            // 使用广播模式
            consumer.setMessageModel(MessageModel.BROADCASTING);

            consumer.subscribe("CONFIG_UPDATE_TOPIC", "*");

            consumer.registerMessageListener((List<MessageExt> msgs, context) -> {
                for (MessageExt msg : msgs) {
                    // 更新本地配置
                    updateLocalConfig(new String(msg.getBody()));
                }
                return ConsumeConcurrentlyStatus.CONSUME_SUCCESS;
            });
        }
    }

    // 效果：
    // 1. 所有服务实例都收到配置更新
    // 2. 每个实例独立更新自己的配置
    // 3. 某个实例重启不影响其他实例
}
```

### 5.3 日志收集系统

```java
public class LogCollectionSystem {

    // 需求：大量日志需要收集，要求高吞吐

    class LogCollector {
        void setup() {
            // 创建多个消费者，使用同一个 Group
            String GROUP = "LOG_COLLECTOR_GROUP";

            // 部署10个消费者实例
            for (int i = 0; i < 10; i++) {
                DefaultMQPushConsumer consumer = new DefaultMQPushConsumer(GROUP);
                consumer.setConsumeThreadMin(20);
                consumer.setConsumeThreadMax(30);
                consumer.setPullBatchSize(64);  // 批量拉取

                consumer.subscribe("LOG_TOPIC", "*");
                consumer.start();
            }

            // 效果：
            // 1. 10个实例并行消费，提高吞吐量
            // 2. 自动负载均衡
            // 3. 某个实例故障，其他实例自动接管
        }
    }
}
```

## 六、模型对比与选择

### 6.1 不同MQ产品的模型对比

```
消息模型对比：
┌─────────────┬──────────────┬──────────────┬──────────────┐
│ 产品        │ 模型         │ 实现方式     │ 特点         │
├─────────────┼──────────────┼──────────────┼──────────────┤
│ RabbitMQ    │ AMQP         │ Exchange     │ 灵活但复杂   │
│ ActiveMQ    │ JMS          │ Queue/Topic  │ 标准但死板   │
│ Kafka       │ 发布订阅     │ Partition    │ 简单但单一   │
│ RocketMQ    │ 统一模型     │ ConsumerGroup│ 灵活且简单   │
└─────────────┴──────────────┴──────────────┴──────────────┘
```

### 6.2 选择建议

```java
public class ModelSelectionGuide {

    // 使用集群消费（点对点）的场景
    class UseClusterMode {
        // ✅ 任务分发
        // ✅ 负载均衡
        // ✅ 高可用（故障转移）
        // ✅ 需要消费确认和重试

        void example() {
            // 订单处理、支付处理、数据同步
        }
    }

    // 使用广播消费的场景
    class UseBroadcastMode {
        // ✅ 本地缓存更新
        // ✅ 配置刷新
        // ✅ 全量数据同步
        // ✅ 实时通知

        void example() {
            // 配置更新、缓存刷新、实时推送
        }
    }

    // 混合使用的场景
    class UseMixedMode {
        // 不同业务使用不同 Group
        // 同一业务的多实例使用相同 Group

        void example() {
            // 电商系统：订单服务组、库存服务组、积分服务组
            // 每个组内负载均衡，组间相互独立
        }
    }
}
```

## 七、高级特性

### 7.1 消费进度重置

```java
public class ConsumeProgressReset {

    // 重置消费进度的场景
    // 1. 需要重新消费历史消息
    // 2. 跳过大量积压消息
    // 3. 修复消费进度异常

    public void resetProgress() {
        // 方式1：通过管理工具
        // sh mqadmin resetOffset -n localhost:9876 -g GROUP -t TOPIC -o 0

        // 方式2：通过代码
        consumer.setConsumeFromWhere(ConsumeFromWhere.CONSUME_FROM_FIRST_OFFSET);
        // CONSUME_FROM_FIRST_OFFSET: 从最早消息开始
        // CONSUME_FROM_LAST_OFFSET: 从最新消息开始
        // CONSUME_FROM_TIMESTAMP: 从指定时间开始
    }
}
```

### 7.2 消费并行度调优

```java
public class ConsumerConcurrency {

    public void tuneConcurrency() {
        DefaultMQPushConsumer consumer = new DefaultMQPushConsumer();

        // 并发消费
        consumer.setConsumeThreadMin(20);   // 最小线程数
        consumer.setConsumeThreadMax(64);   // 最大线程数

        // 顺序消费（单线程）
        consumer.setConsumeThreadMax(1);

        // 批量消费
        consumer.setConsumeMessageBatchMaxSize(10);  // 批量大小
        consumer.setPullBatchSize(32);               // 拉取批量

        // 限流
        consumer.setPullThresholdForQueue(1000);     // 队列级别流控
        consumer.setPullThresholdForTopic(5000);     // Topic级别流控
    }
}
```

## 八、常见问题

### 8.1 消息重复消费

```java
// 问题：同一条消息被消费多次
// 原因：
// 1. 消费超时导致重试
// 2. Rebalance 导致重新分配
// 3. 消费者异常退出

// 解决方案：幂等处理
class IdempotentConsumer {
    private Set<String> processedMsgIds = new ConcurrentHashSet<>();

    public ConsumeConcurrentlyStatus consumeMessage(List<MessageExt> msgs) {
        for (MessageExt msg : msgs) {
            String msgId = msg.getMsgId();

            // 幂等检查
            if (!processedMsgIds.add(msgId)) {
                // 已处理过，跳过
                continue;
            }

            // 处理消息
            processMessage(msg);
        }
        return ConsumeConcurrentlyStatus.CONSUME_SUCCESS;
    }
}
```

### 8.2 消费不均衡

```java
// 问题：某些 Consumer 消费很多，某些很少
// 原因：
// 1. Queue 数量 < Consumer 数量
// 2. 消息分布不均
// 3. Consumer 处理能力不同

// 解决方案：
class BalanceSolution {
    void solution() {
        // 1. 调整 Queue 数量
        // Queue数量 >= Consumer数量

        // 2. 使用合适的分配策略
        consumer.setAllocateMessageQueueStrategy(
            new AllocateMessageQueueConsistentHash()
        );

        // 3. 监控并动态调整
        // 监控每个 Consumer 的消费TPS
        // 动态调整线程池大小
    }
}
```

## 九、总结

通过本篇，我们深入理解了：

1. **两种基本模型**：点对点 vs 发布订阅的本质区别
2. **RocketMQ 的创新**：通过 Consumer Group 统一两种模型
3. **集群 vs 广播**：两种消费模式的特点和适用场景
4. **实战应用**：如何根据业务选择合适的模型

RocketMQ 的消息模型设计充分体现了"简单即美"的设计哲学，用最简单的概念实现了最灵活的功能。

## 下一篇预告

理解了消息模型，下一篇我们将深入剖析消费模式：Push vs Pull 的实现原理，以及 RocketMQ 为什么选择"伪 Push"的设计。

---

**思考与实践**：

1. 为什么 RocketMQ 不像 JMS 那样明确区分 Queue 和 Topic？
2. 在你的业务场景中，哪些适合集群消费，哪些适合广播消费？
3. 如何设计 Consumer Group 来满足复杂的业务需求？

动手实践，在理解中成长！