---
title: "RocketMQ入门05：核心概念详解（上）- Producer、Consumer、Broker"
date: 2025-11-13T14:00:00+08:00
draft: false
tags: ["RocketMQ", "Producer", "Consumer", "Broker", "架构设计"]
categories: ["技术"]
description: "深入理解 RocketMQ 的三大核心组件：Producer、Consumer、Broker 的内部结构、工作原理和最佳实践"
series: ["RocketMQ从入门到精通"]
weight: 5
stage: 1
stageTitle: "基础入门篇"
---

## 引言：理解核心，掌握全局

如果把 RocketMQ 比作一个物流系统，那么：
- **Producer** 是发货方，负责打包发送包裹
- **Broker** 是物流中心，负责存储转运包裹
- **Consumer** 是收货方，负责签收处理包裹

理解这三个核心组件，就掌握了 RocketMQ 的精髓。

## 一、Producer（生产者）详解

### 1.1 Producer 架构

```java
// Producer 内部结构
public class ProducerArchitecture {
    // 核心组件
    private MQClientInstance clientInstance;     // 客户端实例
    private MQClientAPIImpl mqClientAPI;        // 通信层
    private TopicPublishInfo topicPublishInfo;  // 路由信息
    private SendMessageHook sendHook;           // 发送钩子
    private DefaultMQProducerImpl impl;         // 核心实现
}
```

```
Producer 内部架构：
┌──────────────────────────────────┐
│         应用程序                  │
├──────────────────────────────────┤
│      DefaultMQProducer           │ <- API 层
├──────────────────────────────────┤
│    DefaultMQProducerImpl         │ <- 核心实现
├──────────────────────────────────┤
│  ┌──────────┬─────────────────┐ │
│  │路由管理  │  消息发送器      │ │
│  ├──────────┼─────────────────┤ │
│  │故障规避  │  异步发送处理    │ │
│  ├──────────┼─────────────────┤ │
│  │负载均衡  │  事务消息处理    │ │
│  └──────────┴─────────────────┘ │
├──────────────────────────────────┤
│       Netty 通信层               │
└──────────────────────────────────┘
```

### 1.2 Producer 生命周期

```java
public class ProducerLifecycle {

    // 1. 创建阶段
    public void create() {
        DefaultMQProducer producer = new DefaultMQProducer("ProducerGroup");
        producer.setNamesrvAddr("localhost:9876");
        producer.setRetryTimesWhenSendFailed(3);  // 同步发送失败重试次数
        producer.setRetryTimesWhenSendAsyncFailed(2);  // 异步发送失败重试次数
        producer.setSendMsgTimeout(3000);  // 发送超时时间
    }

    // 2. 启动阶段
    public void start() throws MQClientException {
        producer.start();
        // 内部流程：
        // a. 检查配置
        // b. 获取 NameServer 地址
        // c. 启动定时任务（路由更新、心跳）
        // d. 启动消息发送线程池
        // e. 注册 Producer 到所有 Broker
    }

    // 3. 运行阶段
    public void running() throws Exception {
        // 获取路由信息
        TopicRouteData routeData = producer.getDefaultMQProducerImpl()
            .getmQClientFactory()
            .getMQClientAPIImpl()
            .getTopicRouteInfoFromNameServer("TopicTest", 3000);

        // 选择消息队列
        MessageQueue mq = selectMessageQueue(routeData);

        // 发送消息
        SendResult result = producer.send(message, mq);
    }

    // 4. 关闭阶段
    public void shutdown() {
        producer.shutdown();
        // 内部流程：
        // a. 注销 Producer
        // b. 关闭网络连接
        // c. 清理资源
        // d. 停止定时任务
    }
}
```

### 1.3 消息发送流程

```java
// 消息发送核心流程
public class SendMessageFlow {

    public SendResult sendMessage(Message msg) {
        // 1. 验证消息
        Validators.checkMessage(msg, producer);

        // 2. 获取路由信息
        TopicPublishInfo topicPublishInfo = tryToFindTopicPublishInfo(msg.getTopic());

        // 3. 选择消息队列（负载均衡）
        MessageQueue mq = selectOneMessageQueue(topicPublishInfo, lastBrokerName);

        // 4. 消息发送前处理
        msg.setBody(compress(msg.getBody()));  // 压缩
        msg.setProperty("UNIQ_KEY", MessageClientIDSetter.createUniqID());  // 唯一ID

        // 5. 发送消息
        SendResult sendResult = sendKernelImpl(
            msg,
            mq,
            communicationMode,  // SYNC, ASYNC, ONEWAY
            sendCallback,
            timeout
        );

        // 6. 发送后处理（钩子）
        if (hasSendMessageHook()) {
            sendMessageHook.sendMessageAfter(context);
        }

        return sendResult;
    }
}
```

### 1.4 负载均衡策略

```java
public class ProducerLoadBalance {

    // 默认策略：轮询 + 故障规避
    public MessageQueue selectOneMessageQueue(TopicPublishInfo tpInfo, String lastBrokerName) {
        // 启用故障规避
        if (this.sendLatencyFaultEnable) {
            // 1. 优先选择延迟小的 Broker
            for (int i = 0; i < tpInfo.getMessageQueueList().size(); i++) {
                int index = Math.abs(sendWhichQueue.incrementAndGet()) % queueSize;
                MessageQueue mq = tpInfo.getMessageQueueList().get(index);

                // 检查 Broker 是否可用
                if (latencyFaultTolerance.isAvailable(mq.getBrokerName())) {
                    // 避免连续发送到同一个 Broker
                    if (null == lastBrokerName || !mq.getBrokerName().equals(lastBrokerName)) {
                        return mq;
                    }
                }
            }

            // 2. 如果都不可用，选择延迟最小的
            MessageQueue mq = latencyFaultTolerance.pickOneAtLeast();
            return mq;
        }

        // 不启用故障规避：简单轮询
        return selectOneMessageQueue();
    }

    // 故障延迟统计
    class LatencyStats {
        // 根据发送耗时计算 Broker 不可用时长
        // 耗时：50ms,  100ms, 550ms,  1000ms, 2000ms,  3000ms,  15000ms
        // 规避：0ms,   0ms,   30s,    60s,    120s,    180s,    600s
        private final long[] latencyMax = {50L, 100L, 550L, 1000L, 2000L, 3000L, 15000L};
        private final long[] notAvailableDuration = {0L, 0L, 30000L, 60000L, 120000L, 180000L, 600000L};
    }
}
```

## 二、Consumer（消费者）详解

### 2.1 Consumer 架构

```
Consumer 内部架构：
┌──────────────────────────────────┐
│         应用程序                  │
├──────────────────────────────────┤
│    DefaultMQPushConsumer         │ <- Push 模式 API
│    DefaultMQPullConsumer         │ <- Pull 模式 API
├──────────────────────────────────┤
│  ┌──────────────────────────┐   │
│  │  消费者核心实现           │   │
│  ├──────────────────────────┤   │
│  │  Rebalance 负载均衡      │   │
│  │  ProcessQueue 处理队列   │   │
│  │  ConsumeMessageService   │   │
│  │  消费进度管理            │   │
│  └──────────────────────────┘   │
├──────────────────────────────────┤
│    PullMessage 长轮询服务        │
├──────────────────────────────────┤
│       Netty 通信层               │
└──────────────────────────────────┘
```

### 2.2 Push vs Pull 模式

```java
// Push 模式（推荐）
public class PushConsumerDemo {
    public void consume() throws Exception {
        DefaultMQPushConsumer consumer = new DefaultMQPushConsumer("ConsumerGroup");

        // Push 模式本质：长轮询拉取
        // 1. Consumer 主动拉取消息
        // 2. 如果没有消息，Broker hold 住请求
        // 3. 有新消息时，立即返回
        // 4. 看起来像是 Broker 推送

        consumer.registerMessageListener(new MessageListenerConcurrently() {
            @Override
            public ConsumeConcurrentlyStatus consumeMessage(
                List<MessageExt> messages,
                ConsumeConcurrentlyContext context) {
                // 处理消息
                return ConsumeConcurrentlyStatus.CONSUME_SUCCESS;
            }
        });

        consumer.start();
    }
}

// Pull 模式（特殊场景）
public class PullConsumerDemo {
    public void consume() throws Exception {
        DefaultMQPullConsumer consumer = new DefaultMQPullConsumer("ConsumerGroup");
        consumer.start();

        // 手动拉取消息
        Set<MessageQueue> mqs = consumer.fetchMessageQueuesInBalance("TopicTest");
        for (MessageQueue mq : mqs) {
            PullResult pullResult = consumer.pullBlockIfNotFound(
                mq,           // 消息队列
                null,         // 过滤表达式
                getOffset(mq), // 消费位点
                32            // 最大拉取数量
            );

            // 处理消息
            for (MessageExt msg : pullResult.getMsgFoundList()) {
                processMessage(msg);
            }

            // 更新消费位点
            updateOffset(mq, pullResult.getNextBeginOffset());
        }
    }
}
```

### 2.3 消费者 Rebalance 机制

```java
public class ConsumerRebalance {

    // Rebalance 触发条件：
    // 1. Consumer 数量变化（上线/下线）
    // 2. Topic 的 Queue 数量变化
    // 3. 消费者订阅关系变化

    public void rebalanceProcess() {
        // 1. 获取 Topic 的所有 Queue
        Set<MessageQueue> mqSet = topicSubscribeInfoTable.get(topic);

        // 2. 获取消费组的所有 Consumer
        List<String> cidAll = findConsumerIdList(topic, consumerGroup);

        // 3. 排序（保证所有 Consumer 看到一致的视图）
        Collections.sort(mqAll);
        Collections.sort(cidAll);

        // 4. 分配策略
        AllocateMessageQueueStrategy strategy = getAllocateMessageQueueStrategy();
        List<MessageQueue> allocateResult = strategy.allocate(
            consumerGroup,
            currentCID,
            mqAll,
            cidAll
        );

        // 5. 更新本地队列
        updateProcessQueueTableInRebalance(topic, allocateResult);
    }

    // 分配策略示例：平均分配
    public class AllocateMessageQueueAveragely implements AllocateMessageQueueStrategy {
        public List<MessageQueue> allocate(
            String consumerGroup,
            String currentCID,
            List<MessageQueue> mqAll,
            List<String> cidAll) {

            int index = cidAll.indexOf(currentCID);
            int mod = mqAll.size() % cidAll.size();

            // 计算分配数量
            int averageSize = (mod > 0 && index < mod) ?
                mqAll.size() / cidAll.size() + 1 :
                mqAll.size() / cidAll.size();

            // 计算起始位置
            int startIndex = (mod > 0 && index < mod) ?
                index * averageSize :
                index * averageSize + mod;

            // 分配队列
            return mqAll.subList(startIndex, Math.min(startIndex + averageSize, mqAll.size()));
        }
    }
}
```

## 三、Broker 详解

### 3.1 Broker 架构

```
Broker 完整架构：
┌────────────────────────────────────────┐
│            客户端请求                   │
├────────────────────────────────────────┤
│         Remoting 通信层                │
├────────────────────────────────────────┤
│  ┌──────────────┬─────────────────┐   │
│  │ Processor    │  业务处理器      │   │
│  ├──────────────┼─────────────────┤   │
│  │SendMessage   │ 接收消息         │   │
│  │PullMessage   │ 拉取消息         │   │
│  │QueryMessage  │ 查询消息         │   │
│  │AdminRequest  │ 管理请求         │   │
│  └──────────────┴─────────────────┘   │
├────────────────────────────────────────┤
│         Store 存储层                   │
│  ┌──────────────────────────────┐     │
│  │   CommitLog（消息存储）       │     │
│  ├──────────────────────────────┤     │
│  │   ConsumeQueue（消费索引）    │     │
│  ├──────────────────────────────┤     │
│  │   IndexFile（消息索引）       │     │
│  └──────────────────────────────┘     │
├────────────────────────────────────────┤
│      HA 高可用模块                     │
├────────────────────────────────────────┤
│      Schedule 定时任务                 │
└────────────────────────────────────────┘
```

### 3.2 Broker 消息存储

```java
public class BrokerStorage {

    // 1. CommitLog：消息主体存储
    class CommitLog {
        // 所有消息顺序写入
        // 单个文件默认 1GB
        // 文件名为起始偏移量
        private final MappedFileQueue mappedFileQueue;

        public PutMessageResult putMessage(MessageExtBrokerInner msg) {
            // 获取当前写入文件
            MappedFile mappedFile = mappedFileQueue.getLastMappedFile();

            // 写入消息
            AppendMessageResult result = mappedFile.appendMessage(msg, this.appendMessageCallback);

            // 刷盘策略
            handleDiskFlush(result, msg);

            // 主从同步
            handleHA(result, msg);

            return new PutMessageResult(PutMessageStatus.PUT_OK, result);
        }
    }

    // 2. ConsumeQueue：消费队列
    class ConsumeQueue {
        // 存储格式：8字节 CommitLog 偏移量 + 4字节消息大小 + 8字节 Tag HashCode
        // 单个文件 30W 条记录，约 5.72MB
        private final MappedFileQueue mappedFileQueue;

        public void putMessagePositionInfo(
            long offset,      // CommitLog 偏移量
            int size,        // 消息大小
            long tagsCode,   // Tag HashCode
            long cqOffset) { // ConsumeQueue 偏移量

            // 写入索引
            this.byteBufferIndex.putLong(offset);
            this.byteBufferIndex.putInt(size);
            this.byteBufferIndex.putLong(tagsCode);

            // 更新最大偏移量
            this.maxPhysicOffset = offset + size;
        }
    }

    // 3. IndexFile：消息索引
    class IndexFile {
        // 支持按 Key 或时间区间查询
        // 存储格式：Header(40B) + Slot(500W*4B) + Index(2000W*20B)
        // 单个文件约 400MB

        public void putKey(String key, long phyOffset, long storeTimestamp) {
            int keyHash = indexKeyHashMethod(key);
            int slotPos = keyHash % this.hashSlotNum;
            int absSlotPos = IndexHeader.INDEX_HEADER_SIZE + slotPos * hashSlotSize;

            // 存储索引
            // ...
        }
    }
}
```

### 3.3 Broker 刷盘机制

```java
public class FlushDiskStrategy {

    // 同步刷盘
    class SyncFlush {
        public void flush() {
            // 写入 PageCache 后立即刷盘
            // 优点：数据可靠性高
            // 缺点：性能差

            if (FlushDiskType.SYNC_FLUSH == defaultMessageStore.getMessageStoreConfig().getFlushDiskType()) {
                GroupCommitService service = (GroupCommitService) this.flushCommitLogService;

                // 等待刷盘完成
                boolean flushResult = service.waitForFlush(timeout);

                if (!flushResult) {
                    log.error("Sync flush timeout");
                    throw new RuntimeException("Flush timeout");
                }
            }
        }
    }

    // 异步刷盘（默认）
    class AsyncFlush {
        public void flush() {
            // 写入 PageCache 后立即返回
            // 后台线程定时刷盘
            // 优点：性能高
            // 缺点：可能丢失数据（机器宕机）

            // 定时刷盘（默认 500ms）
            this.scheduledExecutorService.scheduleAtFixedRate(new Runnable() {
                @Override
                public void run() {
                    // 刷盘条件：
                    // 1. 距上次刷盘超过 10s
                    // 2. 脏页超过 4 页
                    // 3. 收到关闭信号

                    if (System.currentTimeMillis() - lastFlushTime > 10000 ||
                        dirtyPages > 4) {
                        mappedFile.flush(0);
                        lastFlushTime = System.currentTimeMillis();
                        dirtyPages = 0;
                    }
                }
            }, 500, 500, TimeUnit.MILLISECONDS);
        }
    }
}
```

### 3.4 Broker 主从同步

```java
public class BrokerHA {

    // Master Broker
    class HAService {
        // 接受 Slave 连接
        private AcceptSocketService acceptSocketService;
        // 管理多个 Slave 连接
        private List<HAConnection> connectionList;

        public void start() {
            this.acceptSocketService.start();
            this.groupTransferService.start();
            this.haClient.start();
        }

        // 等待 Slave 同步
        public boolean waitForSlaveSync(long masterPutWhere) {
            // 同步复制模式
            if (messageStore.getMessageStoreConfig().getBrokerRole() == BrokerRole.SYNC_MASTER) {
                // 等待至少一个 Slave 同步完成
                for (HAConnection conn : connectionList) {
                    if (conn.getSlaveAckOffset() >= masterPutWhere) {
                        return true;
                    }
                }
                return false;
            }
            // 异步复制模式：直接返回
            return true;
        }
    }

    // Slave Broker
    class HAClient {
        private SocketChannel socketChannel;

        public void run() {
            while (!this.isStopped()) {
                try {
                    // 连接 Master
                    connectMaster();

                    // 上报同步进度
                    reportSlaveMaxOffset();

                    // 接收数据
                    boolean ok = processReadEvent();

                    // 处理数据
                    dispatchReadRequest();

                } catch (Exception e) {
                    log.error("HAClient error", e);
                }
            }
        }
    }
}
```

## 四、组件交互流程

### 4.1 完整的消息流转

```
消息完整流转过程：
┌─────────────┐
│  Producer   │
└──────┬──────┘
       │ 1. Send Message
       ↓
┌─────────────┐
│ NameServer  │ <- 2. Get Route Info
└──────┬──────┘
       │ 3. Route Info
       ↓
┌─────────────┐
│   Broker    │
│ ┌─────────┐ │
│ │CommitLog│ │ <- 4. Store Message
│ └─────────┘ │
│ ┌─────────┐ │
│ │ConsumeQ │ │ <- 5. Build Index
│ └─────────┘ │
└──────┬──────┘
       │ 6. Pull Message
       ↓
┌─────────────┐
│  Consumer   │
└─────────────┘
```

### 4.2 心跳机制

```java
public class HeartbeatMechanism {

    // Producer/Consumer → Broker
    class ClientHeartbeat {
        // 每 30 秒发送一次心跳
        private final long heartbeatInterval = 30000;

        public void sendHeartbeatToAllBroker() {
            HeartbeatData heartbeatData = prepareHeartbeatData();

            for (Entry<String, HashMap<Long, String>> entry : brokerAddrTable.entrySet()) {
                String brokerName = entry.getKey();
                for (Entry<Long, String> innerEntry : entry.getValue().entrySet()) {
                    String addr = innerEntry.getValue();
                    // 发送心跳
                    this.mQClientAPIImpl.sendHearbeat(addr, heartbeatData, 3000);
                }
            }
        }
    }

    // Broker → NameServer
    class BrokerHeartbeat {
        // 每 30 秒注册一次
        private final long registerInterval = 30000;

        public void registerBrokerAll() {
            RegisterBrokerBody requestBody = new RegisterBrokerBody();
            requestBody.setTopicConfigSerializeWrapper(topicConfigWrapper);
            requestBody.setFilterServerList(filterServerList);

            // 注册到所有 NameServer
            for (String namesrvAddr : namesrvAddrList) {
                registerBroker(namesrvAddr, requestBody);
            }
        }
    }
}
```

## 五、配置优化建议

### 5.1 Producer 优化

```java
// 性能优化配置
producer.setSendMsgTimeout(3000);           // 发送超时
producer.setCompressMsgBodyOverHowmuch(4096); // 消息压缩阈值
producer.setMaxMessageSize(4 * 1024 * 1024);  // 最大消息大小
producer.setRetryTimesWhenSendFailed(2);      // 重试次数
producer.setSendLatencyFaultEnable(true);     // 故障规避
```

### 5.2 Consumer 优化

```java
// 消费优化配置
consumer.setConsumeThreadMin(20);           // 最小消费线程数
consumer.setConsumeThreadMax(64);           // 最大消费线程数
consumer.setConsumeMessageBatchMaxSize(1);  // 批量消费数量
consumer.setPullBatchSize(32);              // 批量拉取数量
consumer.setPullInterval(0);                // 拉取间隔
consumer.setConsumeConcurrentlyMaxSpan(2000); // 消费进度延迟阈值
```

### 5.3 Broker 优化

```properties
# broker.conf 优化配置
# 刷盘策略
flushDiskType=ASYNC_FLUSH
# 同步刷盘超时时间
syncFlushTimeout=5000
# 消息最大大小
maxMessageSize=65536
# 发送线程池大小
sendMessageThreadPoolNums=128
# 拉取线程池大小
pullMessageThreadPoolNums=128
# Broker 角色
brokerRole=ASYNC_MASTER
```

## 六、总结

通过本篇，我们深入理解了：

1. **Producer**：消息发送、负载均衡、故障规避
2. **Consumer**：Push/Pull 模式、Rebalance 机制、消费进度管理
3. **Broker**：消息存储、刷盘机制、主从同步

这三个组件协同工作，构成了 RocketMQ 的核心运行机制。

## 下一篇预告

掌握了 Producer、Consumer、Broker 后，下一篇我们将深入学习 Topic、Queue、Tag、Key 这些消息模型概念，理解 RocketMQ 如何组织和管理消息。

---

**深入思考**：

1. 为什么 RocketMQ 的 Push 模式本质是 Pull？这样设计的好处是什么？
2. Broker 的 CommitLog 为什么要设计成所有消息都写入同一个文件？
3. Consumer Rebalance 时如何保证消息不丢失、不重复？

欢迎在评论区分享你的理解！