---
title: "RocketMQ入门09：消费组机制 - 负载均衡与消息分发"
date: 2025-11-13T18:00:00+08:00
draft: false
tags: ["RocketMQ", "Consumer Group", "负载均衡", "Rebalance", "消费进度"]
categories: ["技术"]
description: "深入理解 RocketMQ 的消费组机制，包括 Rebalance 算法、消费进度管理、负载均衡策略等核心概念"
series: ["RocketMQ从入门到精通"]
weight: 9
stage: 1
stageTitle: "基础入门篇"
---

## 引言：一个精妙的协调机制

假设你经营一家餐厅，有10个服务员（Consumer），需要服务100桌客人（Message Queue）：
- 如何公平分配？每个服务员负责10桌？
- 如果有服务员请假，谁来接管他的桌子？
- 如果来了新服务员，如何重新分配？
- 如何记住每桌的服务进度？

这就是 RocketMQ Consumer Group 要解决的问题。

## 一、Consumer Group 核心概念

### 1.1 什么是 Consumer Group

```java
public class ConsumerGroupConcept {

    // Consumer Group 定义
    class ConsumerGroup {
        String groupName;                    // 组名（全局唯一）
        List<String> consumerIdList;        // 组内消费者列表
        SubscriptionData subscriptionData;   // 订阅信息
        ConsumeType consumeType;            // 消费模式
        MessageModel messageModel;           // 消息模式（集群/广播）
        ConsumeFromWhere consumeFromWhere;  // 从何处开始消费
    }

    // 核心规则
    class CoreRules {
        // 1. 同一 Group 内的 Consumer 订阅关系必须一致
        // 2. 同一 Group 内的 Consumer 均分消息
        // 3. 不同 Group 相互独立，都能收到全量消息
        // 4. Group 是消费进度管理的单位
    }
}
```

### 1.2 Consumer Group 的设计目标

```java
public class DesignGoals {

    // 目标1：负载均衡
    void loadBalancing() {
        // 10个 Queue，5个 Consumer
        // 每个 Consumer 负责 2个 Queue
        // 自动、公平、动态
    }

    // 目标2：高可用
    void highAvailability() {
        // Consumer 宕机，其他 Consumer 接管
        // 无消息丢失
        // 自动故障转移
    }

    // 目标3：水平扩展
    void horizontalScaling() {
        // 动态增加 Consumer
        // 自动重新分配
        // 无需停机
    }

    // 目标4：消费进度管理
    void progressManagement() {
        // 统一管理消费位点
        // 支持重置进度
        // 持久化存储
    }
}
```

## 二、Rebalance 机制详解

### 2.1 什么是 Rebalance

```java
public class RebalanceMechanism {

    // Rebalance：重新分配 Queue 给 Consumer
    class RebalanceDefinition {
        // 触发时机：
        // 1. Consumer 上线/下线
        // 2. Queue 数量变化
        // 3. 订阅关系变化

        // 目标：
        // 保证每个 Queue 只被一个 Consumer 消费
        // 尽可能均匀分配
    }

    // Rebalance 流程
    class RebalanceFlow {
        public void doRebalance() {
            // 1. 获取 Topic 的所有 Queue
            List<MessageQueue> mqAll = getTopicQueues(topic);

            // 2. 获取 Consumer Group 的所有 Consumer
            List<String> cidAll = getConsumerIdList(topic, group);

            // 3. 排序保证一致性
            Collections.sort(mqAll);
            Collections.sort(cidAll);

            // 4. 执行分配算法
            List<MessageQueue> allocateResult = strategy.allocate(
                consumerGroup,
                currentCID,
                mqAll,
                cidAll
            );

            // 5. 更新本地队列
            updateProcessQueueTable(allocateResult);
        }
    }
}
```

### 2.2 Rebalance 触发流程

```
Rebalance 触发流程：

Consumer 加入：
┌──────────┐      注册       ┌──────────┐
│Consumer1 │ ───────────────> │  Broker  │
└──────────┘                  └──────────┘
                                    │
                              通知其他Consumer
                                    ↓
┌──────────┐                  ┌──────────┐
│Consumer2 │ <──── Rebalance ─│Consumer3 │
└──────────┘                  └──────────┘

时间线：
T0: Consumer1 加入 Group
T1: Broker 通知所有 Consumer
T2: 所有 Consumer 开始 Rebalance
T3: 完成 Queue 重新分配
```

### 2.3 Rebalance 实现细节

```java
public class RebalanceImplementation {

    // Consumer 端 Rebalance 服务
    class RebalanceService extends ServiceThread {

        @Override
        public void run() {
            while (!this.isStopped()) {
                // 默认每 20 秒执行一次
                this.waitForRunning(20000);
                this.doRebalance();
            }
        }

        private void doRebalance() {
            // 对所有订阅的 Topic 执行 Rebalance
            for (Map.Entry<String, SubscriptionData> entry :
                 subscriptionInner.entrySet()) {
                String topic = entry.getKey();
                rebalanceByTopic(topic);
            }
        }

        private void rebalanceByTopic(String topic) {
            // 1. 获取 Topic 的队列信息
            Set<MessageQueue> mqSet = topicSubscribeInfoTable.get(topic);

            // 2. 获取同组的所有 Consumer ID
            List<String> cidAll = mQClientFactory.findConsumerIdList(
                topic, consumerGroup
            );

            // 3. 执行分配
            if (mqSet != null && cidAll != null) {
                AllocateMessageQueueStrategy strategy = this.allocateMessageQueueStrategy;

                List<MessageQueue> allocateResult = null;
                try {
                    allocateResult = strategy.allocate(
                        this.consumerGroup,
                        this.mQClientFactory.getClientId(),
                        new ArrayList<>(mqSet),
                        cidAll
                    );
                } catch (Throwable e) {
                    log.error("AllocateMessageQueueStrategy.allocate Exception", e);
                }

                // 4. 更新分配结果
                updateProcessQueueTableInRebalance(topic, allocateResult);
            }
        }
    }

    // 更新本地队列表
    private void updateProcessQueueTableInRebalance(String topic, List<MessageQueue> mqSet) {
        // 移除不再分配给自己的队列
        for (MessageQueue mq : processQueueTable.keySet()) {
            if (!mqSet.contains(mq)) {
                ProcessQueue pq = processQueueTable.remove(mq);
                if (pq != null) {
                    pq.setDropped(true);  // 标记为丢弃
                    log.info("Drop queue: {}", mq);
                }
            }
        }

        // 添加新分配的队列
        for (MessageQueue mq : mqSet) {
            if (!processQueueTable.containsKey(mq)) {
                ProcessQueue pq = new ProcessQueue();
                processQueueTable.put(mq, pq);

                // 创建拉取请求
                PullRequest pullRequest = new PullRequest();
                pullRequest.setMessageQueue(mq);
                pullRequest.setProcessQueue(pq);
                pullRequest.setNextOffset(computePullFromWhere(mq));

                // 立即执行拉取
                pullMessageService.executePullRequestImmediately(pullRequest);

                log.info("Add new queue: {}", mq);
            }
        }
    }
}
```

## 三、负载均衡策略

### 3.1 内置分配策略

```java
public class AllocationStrategies {

    // 1. 平均分配策略（默认）
    class AllocateMessageQueueAveragely {
        /*
        示例：8个Queue，3个Consumer
        Consumer0: Q0, Q1, Q2
        Consumer1: Q3, Q4, Q5
        Consumer2: Q6, Q7
        */

        public List<MessageQueue> allocate(String group, String currentCID,
                                          List<MessageQueue> mqAll,
                                          List<String> cidAll) {
            int index = cidAll.indexOf(currentCID);
            int mod = mqAll.size() % cidAll.size();

            int averageSize = (mqAll.size() <= cidAll.size()) ? 1 :
                (mod > 0 && index < mod) ?
                mqAll.size() / cidAll.size() + 1 :
                mqAll.size() / cidAll.size();

            int startIndex = (mod > 0 && index < mod) ?
                index * averageSize :
                index * averageSize + mod;

            int range = Math.min(averageSize, mqAll.size() - startIndex);

            return mqAll.subList(startIndex, startIndex + range);
        }
    }

    // 2. 环形平均分配
    class AllocateMessageQueueAveragelyByCircle {
        /*
        示例：8个Queue，3个Consumer
        Consumer0: Q0, Q3, Q6
        Consumer1: Q1, Q4, Q7
        Consumer2: Q2, Q5
        */

        public List<MessageQueue> allocate(String group, String currentCID,
                                          List<MessageQueue> mqAll,
                                          List<String> cidAll) {
            int index = cidAll.indexOf(currentCID);
            List<MessageQueue> result = new ArrayList<>();

            for (int i = index; i < mqAll.size(); i += cidAll.size()) {
                result.add(mqAll.get(i));
            }

            return result;
        }
    }

    // 3. 一致性Hash分配
    class AllocateMessageQueueConsistentHash {
        /*
        使用一致性Hash算法
        优点：Consumer变化时，影响的Queue最少
        */

        private final int virtualNodeCnt;
        private final HashFunction hashFunc;

        public List<MessageQueue> allocate(String group, String currentCID,
                                          List<MessageQueue> mqAll,
                                          List<String> cidAll) {
            // 构建Hash环
            TreeMap<Long, String> hashRing = new TreeMap<>();
            for (String cid : cidAll) {
                for (int i = 0; i < virtualNodeCnt; i++) {
                    long hash = hashFunc.hash(cid + "#" + i);
                    hashRing.put(hash, cid);
                }
            }

            // 分配Queue
            List<MessageQueue> result = new ArrayList<>();
            for (MessageQueue mq : mqAll) {
                long hash = hashFunc.hash(mq.toString());
                Map.Entry<Long, String> entry = hashRing.ceilingEntry(hash);
                if (entry == null) {
                    entry = hashRing.firstEntry();
                }

                if (currentCID.equals(entry.getValue())) {
                    result.add(mq);
                }
            }

            return result;
        }
    }

    // 4. 机房就近分配
    class AllocateMessageQueueByMachineRoom {
        /*
        根据机房分配，优先同机房
        减少跨机房流量
        */

        public List<MessageQueue> allocate(String group, String currentCID,
                                          List<MessageQueue> mqAll,
                                          List<String> cidAll) {
            // 获取当前Consumer的机房
            String currentRoom = getMachineRoom(currentCID);

            // 同机房的Queue
            List<MessageQueue> sameRoomQueues = new ArrayList<>();
            // 其他机房的Queue
            List<MessageQueue> diffRoomQueues = new ArrayList<>();

            for (MessageQueue mq : mqAll) {
                if (currentRoom.equals(getMachineRoom(mq.getBrokerName()))) {
                    sameRoomQueues.add(mq);
                } else {
                    diffRoomQueues.add(mq);
                }
            }

            // 优先分配同机房Queue
            List<MessageQueue> result = new ArrayList<>();
            result.addAll(allocateQueues(sameRoomQueues, currentCID, cidAll));

            // 如果还需要更多Queue，分配其他机房的
            if (result.size() < getTargetQueueNum(mqAll.size(), cidAll.size())) {
                result.addAll(allocateQueues(diffRoomQueues, currentCID, cidAll));
            }

            return result;
        }
    }

    // 5. 自定义分配策略
    class CustomAllocationStrategy implements AllocateMessageQueueStrategy {

        @Override
        public List<MessageQueue> allocate(String group, String currentCID,
                                          List<MessageQueue> mqAll,
                                          List<String> cidAll) {
            // 根据业务需求自定义
            // 例如：VIP Consumer 分配更多Queue

            if (isVipConsumer(currentCID)) {
                // VIP分配60%的Queue
                return allocateForVip(mqAll, currentCID, cidAll);
            } else {
                // 普通Consumer平分剩余40%
                return allocateForNormal(mqAll, currentCID, cidAll);
            }
        }
    }
}
```

### 3.2 策略选择指南

```java
public class StrategySelectionGuide {

    public void selectStrategy() {
        DefaultMQPushConsumer consumer = new DefaultMQPushConsumer();

        // 场景1：默认场景
        // 使用平均分配，简单公平
        consumer.setAllocateMessageQueueStrategy(
            new AllocateMessageQueueAveragely()
        );

        // 场景2：Consumer频繁变动
        // 使用一致性Hash，减少重分配
        consumer.setAllocateMessageQueueStrategy(
            new AllocateMessageQueueConsistentHash()
        );

        // 场景3：多机房部署
        // 使用机房就近，减少跨机房流量
        consumer.setAllocateMessageQueueStrategy(
            new AllocateMessageQueueByMachineRoom()
        );

        // 场景4：特殊业务需求
        // 自定义策略
        consumer.setAllocateMessageQueueStrategy(
            new CustomAllocationStrategy()
        );
    }
}
```

## 四、消费进度管理

### 4.1 消费进度存储

```java
public class ConsumeProgressStorage {

    // 集群模式：进度存储在 Broker
    class ClusterModeProgress {
        // 存储位置：{ROCKETMQ_HOME}/store/config/consumerOffset.json

        /*
        {
            "offsetTable": {
                "ORDER_TOPIC@ORDER_GROUP": {
                    "0": 123456,  // Queue0 的消费进度
                    "1": 234567,  // Queue1 的消费进度
                    "2": 345678,  // Queue2 的消费进度
                    "3": 456789   // Queue3 的消费进度
                }
            }
        }
        */

        // Broker 端定期持久化（默认5秒）
        class ConsumerOffsetManager {
            private ConcurrentHashMap<String/* topic@group */,
                                    ConcurrentHashMap<Integer, Long>> offsetTable;

            public void commitOffset(String group, String topic, int queueId, long offset) {
                String key = topic + "@" + group;
                ConcurrentHashMap<Integer, Long> map = offsetTable.get(key);
                if (map != null) {
                    Long oldOffset = map.put(queueId, offset);
                    if (oldOffset == null || offset > oldOffset) {
                        // 更新成功
                    }
                }
            }
        }
    }

    // 广播模式：进度存储在本地
    class BroadcastModeProgress {
        // 存储位置：{user.home}/.rocketmq_offsets/{clientId}/{group}/offsets.json

        class LocalFileOffsetStore {
            private String storePath;
            private ConcurrentHashMap<MessageQueue, AtomicLong> offsetTable;

            public void persistAll() {
                // 持久化到本地文件
                String jsonString = JSON.toJSONString(offsetTable);
                MixAll.string2File(jsonString, storePath);
            }

            public void load() {
                // 从本地文件加载
                String content = MixAll.file2String(storePath);
                if (content != null) {
                    offsetTable = JSON.parseObject(content,
                        new TypeReference<ConcurrentHashMap<MessageQueue, AtomicLong>>(){});
                }
            }
        }
    }
}
```

### 4.2 消费进度提交

```java
public class ProgressCommit {

    // Consumer 端进度提交
    class ConsumerProgressCommit {

        // 定时提交（默认5秒）
        class ScheduledCommit {
            private ScheduledExecutorService scheduledExecutorService;

            public void start() {
                scheduledExecutorService.scheduleAtFixedRate(() -> {
                    try {
                        persistConsumerOffset();
                    } catch (Exception e) {
                        log.error("persistConsumerOffset error", e);
                    }
                }, 1000, 5000, TimeUnit.MILLISECONDS);
            }

            private void persistConsumerOffset() {
                for (Map.Entry<MessageQueue, ProcessQueue> entry :
                     processQueueTable.entrySet()) {
                    MessageQueue mq = entry.getKey();
                    ProcessQueue pq = entry.getValue();

                    if (pq.isDropped()) {
                        continue;
                    }

                    // 获取消费进度
                    long offset = pq.getConsumeOffset();

                    // 提交到 Broker
                    offsetStore.updateOffset(mq, offset, false);
                }

                // 批量提交
                offsetStore.persistAll();
            }
        }

        // 关闭时提交
        class ShutdownCommit {
            public void shutdown() {
                // 停止定时任务
                scheduledExecutorService.shutdown();

                // 最后一次提交
                persistConsumerOffset();

                // 等待提交完成
                offsetStore.persistAll();
            }
        }
    }
}
```

### 4.3 进度重置

```java
public class ProgressReset {

    // 重置消费进度的方式
    class ResetMethods {

        // 1. 通过管理工具重置
        void resetByAdmin() {
            // 重置到最早
            // sh mqadmin resetOffset -g GROUP -t TOPIC -o 0

            // 重置到最新
            // sh mqadmin resetOffset -g GROUP -t TOPIC -o -1

            // 重置到指定时间
            // sh mqadmin resetOffset -g GROUP -t TOPIC -o 2023-11-13#10:00:00
        }

        // 2. 通过代码重置
        void resetByCode() {
            DefaultMQPushConsumer consumer = new DefaultMQPushConsumer();

            // 设置从哪里开始消费
            consumer.setConsumeFromWhere(ConsumeFromWhere.CONSUME_FROM_FIRST_OFFSET);
            // CONSUME_FROM_FIRST_OFFSET: 从最早消息
            // CONSUME_FROM_LAST_OFFSET: 从最新消息
            // CONSUME_FROM_TIMESTAMP: 从指定时间

            // 设置消费时间点
            consumer.setConsumeTimestamp("2023-11-13 10:00:00");
        }

        // 3. 跳过堆积消息
        void skipBacklog() {
            // 获取最大偏移量
            long maxOffset = consumer.maxOffset(mq);

            // 更新到最大偏移量
            consumer.updateConsumeOffset(mq, maxOffset);
        }
    }
}
```

## 五、Rebalance 过程中的问题

### 5.1 消息重复消费

```java
public class DuplicateConsumption {

    // 问题：Rebalance 导致消息重复
    class Problem {
        /*
        场景：
        1. Consumer1 正在处理 Queue1 的消息
        2. Rebalance 发生，Queue1 分配给 Consumer2
        3. Consumer1 还没提交进度就失去了 Queue1
        4. Consumer2 从旧进度开始消费，导致重复
        */
    }

    // 解决方案
    class Solution {

        // 1. 幂等消费
        class IdempotentConsumer {
            private Set<String> processedIds = new ConcurrentHashSet<>();

            public ConsumeStatus consumeMessage(List<MessageExt> msgs) {
                for (MessageExt msg : msgs) {
                    String bizId = msg.getKeys();  // 使用业务ID

                    if (!processedIds.add(bizId)) {
                        // 已处理，跳过
                        log.info("Message already processed: {}", bizId);
                        continue;
                    }

                    // 处理消息
                    processMessage(msg);
                }
                return ConsumeStatus.CONSUME_SUCCESS;
            }
        }

        // 2. 减少 Rebalance 频率
        class ReduceRebalance {
            void configure() {
                // 增加心跳间隔
                consumer.setHeartbeatBrokerInterval(30000);  // 30秒

                // 使用一致性Hash
                consumer.setAllocateMessageQueueStrategy(
                    new AllocateMessageQueueConsistentHash()
                );
            }
        }
    }
}
```

### 5.2 消费停顿

```java
public class ConsumePause {

    // 问题：Rebalance 期间消费暂停
    class Problem {
        /*
        Rebalance 过程：
        1. 停止当前消费
        2. 等待其他 Consumer Rebalance
        3. 重新分配Queue
        4. 恢复消费

        期间有短暂停顿
        */
    }

    // 优化方案
    class Optimization {

        // 1. 减少 Rebalance 时间
        void reduceRebalanceTime() {
            // 减少 Consumer 数量变化
            // 使用容器编排，批量上下线
        }

        // 2. 平滑迁移
        class SmoothMigration {
            void migrate() {
                // 先启动新 Consumer
                startNewConsumers();

                // 等待 Rebalance 完成
                Thread.sleep(30000);

                // 再停止旧 Consumer
                stopOldConsumers();
            }
        }

        // 3. 预分配策略
        void preAllocate() {
            // 预先规划好 Queue 分配
            // 使用自定义分配策略
            consumer.setAllocateMessageQueueStrategy(
                new StaticAllocationStrategy()
            );
        }
    }
}
```

## 六、监控和运维

### 6.1 消费组监控

```java
public class ConsumerGroupMonitoring {

    // 监控指标
    class Metrics {

        // 1. 消费进度监控
        void monitorProgress() {
            // 消费延迟
            long lag = maxOffset - consumerOffset;

            // 消费速度
            double tps = (currentOffset - lastOffset) / interval;

            // 预计消费完成时间
            double eta = lag / tps;
        }

        // 2. Rebalance 监控
        void monitorRebalance() {
            // Rebalance 次数
            int rebalanceCount;

            // Rebalance 耗时
            long rebalanceDuration;

            // Queue 分配变化
            Map<String, List<MessageQueue>> allocationHistory;
        }

        // 3. Consumer 健康度
        void monitorHealth() {
            // 在线 Consumer 数量
            int onlineConsumerCount;

            // 消费线程池状态
            ThreadPoolExecutor executor = getConsumeExecutor();
            int activeCount = executor.getActiveCount();
            int queueSize = executor.getQueue().size();
        }
    }

    // 运维命令
    class AdminCommands {

        // 查看消费进度
        void checkProgress() {
            // sh mqadmin consumerProgress -n localhost:9876 -g ORDER_GROUP
        }

        // 查看消费组列表
        void listConsumerGroups() {
            // sh mqadmin consumerGroupList -n localhost:9876
        }

        // 查看消费组详情
        void consumerGroupDetail() {
            // sh mqadmin consumerConnection -n localhost:9876 -g ORDER_GROUP
        }
    }
}
```

### 6.2 问题诊断

```java
public class ProblemDiagnosis {

    // 常见问题诊断
    class CommonProblems {

        // 1. 消费速度慢
        void slowConsumption() {
            // 检查点：
            // - Consumer 数量是否足够
            // - 消费线程池是否饱和
            // - 单条消息处理时间
            // - 网络延迟

            // 解决：
            // - 增加 Consumer 实例
            // - 增加消费线程数
            // - 优化消费逻辑
            // - 批量消费
        }

        // 2. 消费不均衡
        void imbalancedConsumption() {
            // 检查点：
            // - Queue 分配是否均匀
            // - Consumer 处理能力是否一致
            // - 是否有热点 Queue

            // 解决：
            // - 调整分配策略
            // - 增加 Queue 数量
            // - 使用一致性 Hash
        }

        // 3. Rebalance 频繁
        void frequentRebalance() {
            // 检查点：
            // - Consumer 是否频繁上下线
            // - 网络是否稳定
            // - 心跳是否超时

            // 解决：
            // - 增加心跳间隔
            // - 优化部署策略
            // - 使用容器编排
        }
    }
}
```

## 七、最佳实践

### 7.1 Consumer Group 设计原则

```java
public class DesignPrinciples {

    // 1. 合理设置 Consumer 数量
    class ConsumerCount {
        void calculate() {
            // Consumer 数量 <= Queue 数量
            // 否则有 Consumer 空闲

            // 建议：
            int queueCount = 16;
            int consumerCount = Math.min(queueCount, 8);  // 不超过 Queue 数量
        }
    }

    // 2. 订阅关系一致性
    class SubscriptionConsistency {
        // 同一 Group 内所有 Consumer 必须：
        // - 订阅相同的 Topic
        // - 使用相同的 Tag 过滤
        // - 使用相同的消费模式

        // ❌ 错误示例
        void wrongExample() {
            // Consumer1
            consumer1.subscribe("TOPIC", "TagA");

            // Consumer2（同组但不同Tag）
            consumer2.subscribe("TOPIC", "TagB");  // 错误！
        }

        // ✅ 正确示例
        void correctExample() {
            // 所有 Consumer 订阅一致
            consumer.subscribe("TOPIC", "TagA || TagB");
        }
    }

    // 3. 消费进度管理
    class ProgressManagement {
        void bestPractice() {
            // 定期监控消费延迟
            monitorConsumerLag();

            // 设置合理的提交间隔
            consumer.setAutoCommitIntervalMillis(5000);

            // 优雅关闭
            Runtime.getRuntime().addShutdownHook(new Thread(() -> {
                consumer.shutdown();
            }));
        }
    }
}
```

### 7.2 性能优化

```java
public class PerformanceOptimization {

    // 1. 消费并发度调优
    void optimizeConcurrency() {
        // 根据消息处理时间调整
        consumer.setConsumeThreadMin(20);
        consumer.setConsumeThreadMax(64);

        // 批量消费
        consumer.setConsumeMessageBatchMaxSize(10);
    }

    // 2. 拉取优化
    void optimizePull() {
        // 拉取批次大小
        consumer.setPullBatchSize(32);

        // 拉取间隔（0表示不间断）
        consumer.setPullInterval(0);

        // 流控阈值
        consumer.setPullThresholdForQueue(1000);
    }

    // 3. Rebalance 优化
    void optimizeRebalance() {
        // 使用合适的分配策略
        consumer.setAllocateMessageQueueStrategy(
            new AllocateMessageQueueConsistentHash()
        );

        // 减少 Rebalance 触发
        consumer.setConsumeFromWhere(
            ConsumeFromWhere.CONSUME_FROM_LAST_OFFSET
        );
    }
}
```

## 八、总结

通过本篇，我们深入理解了：

1. **Consumer Group 机制**：如何实现负载均衡和高可用
2. **Rebalance 原理**：Queue 如何在 Consumer 间动态分配
3. **分配策略**：不同策略的特点和适用场景
4. **消费进度管理**：进度如何存储、提交和重置
5. **问题与优化**：常见问题的诊断和解决

Consumer Group 是 RocketMQ 的精髓之一，它用简单的概念实现了复杂的分布式协调。

## 下一篇预告

基础篇的最后一篇，我们将通过 SpringBoot 集成实战，把前面学到的知识串联起来，构建一个生产级的消息系统。

---

**思考与实践**：

1. 为什么同一 Consumer Group 内的订阅关系必须一致？
2. Rebalance 过程中如何保证消息不丢失？
3. 在你的业务中，应该选择哪种分配策略？

深入理解原理，才能更好地应用！