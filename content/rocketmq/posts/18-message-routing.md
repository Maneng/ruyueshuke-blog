---
title: "RocketMQ架构08：消息路由与负载均衡 - 智能路由的奥秘"
date: 2025-11-14T03:00:00+08:00
draft: false
tags: ["RocketMQ", "消息路由", "负载均衡", "容错机制", "故障转移"]
categories: ["技术"]
description: "深入剖析 RocketMQ 的消息路由机制和负载均衡策略，理解如何实现高可用和性能优化"
series: ["RocketMQ从入门到精通"]
weight: 18
stage: 2
stageTitle: "架构原理篇"
---

## 引言：智能路由的艺术

RocketMQ 的路由系统就像交通指挥系统，负责：

- **Producer 找 Broker**：发送消息到哪个 Broker？
- **Consumer 找 Broker**：从哪个 Broker 拉取消息？
- **故障转移**：Broker 宕机后如何自动切换？
- **负载均衡**：如何均匀分配请求？

今天我们深入剖析这套智能路由系统的设计。

---

## 一、路由信息管理

### 1.1 路由表结构

```java
public class TopicRouteData {
    // Queue 数据列表
    private List<QueueData> queueDatas;

    // Broker 数据列表
    private List<BrokerData> brokerDatas;

    // 过滤服务器表
    private HashMap<String, List<String>> filterServerTable;
}

// Queue 数据
public class QueueData {
    private String brokerName;       // Broker 名称
    private int readQueueNums;       // 读队列数
    private int writeQueueNums;      // 写队列数
    private int perm;                // 权限
    private int topicSynFlag;        // 同步标志
}

// Broker 数据
public class BrokerData {
    private String cluster;          // 集群名
    private String brokerName;       // Broker 名称
    private HashMap<Long, String> brokerAddrs;  // Broker 地址表
    // Key: brokerId (0=Master, >0=Slave)
    // Value: broker 地址
}
```

**路由表示例**：

```json
{
  "queueDatas": [
    {
      "brokerName": "broker-a",
      "readQueueNums": 4,
      "writeQueueNums": 4,
      "perm": 6
    },
    {
      "brokerName": "broker-b",
      "readQueueNums": 4,
      "writeQueueNums": 4,
      "perm": 6
    }
  ],
  "brokerDatas": [
    {
      "cluster": "DefaultCluster",
      "brokerName": "broker-a",
      "brokerAddrs": {
        "0": "192.168.1.10:10911",  // Master
        "1": "192.168.1.11:10911"   // Slave
      }
    },
    {
      "cluster": "DefaultCluster",
      "brokerName": "broker-b",
      "brokerAddrs": {
        "0": "192.168.1.20:10911",
        "1": "192.168.1.21:10911"
      }
    }
  ]
}
```

### 1.2 路由发现流程

```
┌────────────────────────────────────────────┐
│         路由发现与更新流程                  │
├────────────────────────────────────────────┤
│                                             │
│  Producer/Consumer         NameServer      │
│        │                      │             │
│        │ 1. 启动时拉取路由     │             │
│        ├─────────────────────▶│             │
│        │                      │             │
│        │ 2. 返回路由信息       │             │
│        ◀─────────────────────┤             │
│        │                      │             │
│        │ 3. 定期更新路由       │             │
│        │    (默认30秒)        │             │
│        ├─────────────────────▶│             │
│        │                      │             │
│                                             │
│  Broker                    NameServer      │
│        │                      │             │
│        │ 1. 注册路由信息       │             │
│        ├─────────────────────▶│             │
│        │                      │             │
│        │ 2. 定期心跳           │             │
│        │    (每30秒)          │             │
│        ├─────────────────────▶│             │
│        │                      │             │
│        │ 3. 超时剔除           │             │
│        │    (120秒无心跳)     │             │
│                                             │
└────────────────────────────────────────────┘
```

### 1.3 路由更新代码

```java
// Producer 路由更新
public class MQClientInstance {

    // 更新单个 Topic 的路由信息
    public boolean updateTopicRouteInfoFromNameServer(final String topic) {
        try {
            // 1. 从 NameServer 获取路由信息
            TopicRouteData topicRouteData =
                this.mQClientAPIImpl.getTopicRouteInfoFromNameServer(topic, 1000 * 3);

            if (topicRouteData != null) {
                // 2. 对比路由是否变化
                TopicRouteData old = this.topicRouteTable.get(topic);
                boolean changed = topicRouteDataIsChange(old, topicRouteData);

                if (!changed) {
                    changed = this.isNeedUpdateTopicRouteInfo(topic);
                }

                if (changed) {
                    // 3. 更新 Producer 的路由表
                    for (Entry<String, MQProducerInner> entry : this.producerTable.entrySet()) {
                        MQProducerInner impl = entry.getValue();
                        if (impl != null) {
                            impl.updateTopicPublishInfo(topic, publishInfo);
                        }
                    }

                    // 4. 更新 Consumer 的路由表
                    for (Entry<String, MQConsumerInner> entry : this.consumerTable.entrySet()) {
                        MQConsumerInner impl = entry.getValue();
                        if (impl != null) {
                            impl.updateTopicSubscribeInfo(topic, subscribeInfo);
                        }
                    }

                    // 5. 更新本地缓存
                    this.topicRouteTable.put(topic, cloneTopicRouteData(topicRouteData));

                    log.info("topicRouteTable.put TopicRouteData[{}]", topic);
                }

                return true;
            }
        } catch (Exception e) {
            log.error("updateTopicRouteInfoFromNameServer Exception", e);
        }

        return false;
    }

    // 定时更新所有 Topic 的路由
    public void startScheduledTask() {
        this.scheduledExecutorService.scheduleAtFixedRate(new Runnable() {
            @Override
            public void run() {
                try {
                    MQClientInstance.this.updateTopicRouteInfoFromNameServer();
                } catch (Exception e) {
                    log.error("ScheduledTask updateTopicRouteInfoFromNameServer exception", e);
                }
            }
        }, 10, 30, TimeUnit.SECONDS);  // 每30秒更新一次
    }
}
```

---

## 二、Producer 负载均衡

### 2.1 Queue 选择策略

```java
public class TopicPublishInfo {
    // Queue 列表
    private List<MessageQueue> messageQueueList = new ArrayList<>();

    // 上次选择的 Queue 索引
    private volatile ThreadLocalIndex sendWhichQueue = new ThreadLocalIndex();

    // 轮询选择 Queue
    public MessageQueue selectOneMessageQueue() {
        int index = this.sendWhichQueue.incrementAndGet();
        int pos = Math.abs(index) % this.messageQueueList.size();
        if (pos < 0) {
            pos = 0;
        }
        return this.messageQueueList.get(pos);
    }

    // 故障规避选择 Queue
    public MessageQueue selectOneMessageQueue(final String lastBrokerName) {
        if (lastBrokerName == null) {
            return selectOneMessageQueue();
        } else {
            // 循环查找，跳过上次失败的 Broker
            for (int i = 0; i < this.messageQueueList.size(); i++) {
                int index = this.sendWhichQueue.incrementAndGet();
                int pos = Math.abs(index) % this.messageQueueList.size();
                if (pos < 0) {
                    pos = 0;
                }
                MessageQueue mq = this.messageQueueList.get(pos);

                // 跳过故障 Broker
                if (!mq.getBrokerName().equals(lastBrokerName)) {
                    return mq;
                }
            }
            // 如果所有 Broker 都故障，返回任意一个
            return selectOneMessageQueue();
        }
    }
}
```

### 2.2 故障延迟机制

```java
public class MQFaultStrategy {

    // Broker 故障延迟表
    private final ConcurrentHashMap<String, FaultItem> faultItemTable =
        new ConcurrentHashMap<>(16);

    // Broker 是否可用
    public boolean isAvailable(final String brokerName) {
        final FaultItem faultItem = this.faultItemTable.get(brokerName);
        if (faultItem != null) {
            return faultItem.isAvailable();
        }
        return true;
    }

    // 更新 Broker 故障信息
    public void updateFaultItem(final String brokerName, final long currentLatency,
                                boolean isolation) {
        FaultItem old = this.faultItemTable.get(brokerName);
        if (null == old) {
            final FaultItem faultItem = new FaultItem(brokerName);
            faultItem.setCurrentLatency(currentLatency);
            faultItem.setStartTimestamp(System.currentTimeMillis());
            old = this.faultItemTable.putIfAbsent(brokerName, faultItem);
            if (old != null) {
                old.setCurrentLatency(currentLatency);
                old.setStartTimestamp(System.currentTimeMillis());
            }
        } else {
            old.setCurrentLatency(currentLatency);
            old.setStartTimestamp(System.currentTimeMillis());
        }
    }

    // 选择可用的 MessageQueue
    public MessageQueue selectOneMessageQueue(final TopicPublishInfo tpInfo,
                                             final String lastBrokerName) {
        // 1. 启用故障延迟
        if (this.sendLatencyFaultEnable) {
            try {
                // 轮询选择
                int index = tpInfo.getSendWhichQueue().incrementAndGet();
                for (int i = 0; i < tpInfo.getMessageQueueList().size(); i++) {
                    int pos = Math.abs(index++) % tpInfo.getMessageQueueList().size();
                    MessageQueue mq = tpInfo.getMessageQueueList().get(pos);

                    // 检查 Broker 是否可用
                    if (isAvailable(mq.getBrokerName())) {
                        return mq;
                    }
                }

                // 如果没有可用的，选择延迟最小的
                final String notBestBroker = pickOneAtLeast();
                int writeQueueNums = tpInfo.getQueueIdByBroker(notBestBroker);
                if (writeQueueNums > 0) {
                    final MessageQueue mq = tpInfo.selectOneMessageQueue();
                    if (notBestBroker != null) {
                        mq.setBrokerName(notBestBroker);
                        mq.setQueueId(tpInfo.getSendWhichQueue().incrementAndGet() % writeQueueNums);
                    }
                    return mq;
                } else {
                    this.faultItemTable.remove(notBestBroker);
                }
            } catch (Exception e) {
                log.error("Error occurred when selecting message queue", e);
            }

            return tpInfo.selectOneMessageQueue();
        }

        // 2. 不启用故障延迟（默认）
        return tpInfo.selectOneMessageQueue(lastBrokerName);
    }
}
```

### 2.3 发送流程

```java
public class DefaultMQProducerImpl {

    // 发送消息（带重试）
    private SendResult sendDefaultImpl(
        Message msg,
        final CommunicationMode communicationMode,
        final SendCallback sendCallback,
        final long timeout
    ) throws MQClientException, RemotingException, MQBrokerException, InterruptedException {

        // 1. 获取路由信息
        TopicPublishInfo topicPublishInfo = this.tryToFindTopicPublishInfo(msg.getTopic());

        if (topicPublishInfo != null && topicPublishInfo.ok()) {
            boolean callTimeout = false;
            MessageQueue mq = null;
            Exception exception = null;
            SendResult sendResult = null;

            // 2. 重试次数
            int timesTotal = communicationMode == CommunicationMode.SYNC ? 1 + this.defaultMQProducer.getRetryTimesWhenSendFailed() : 1;

            int times = 0;
            String[] brokersSent = new String[timesTotal];

            // 3. 循环重试
            for (; times < timesTotal; times++) {
                String lastBrokerName = null == mq ? null : mq.getBrokerName();

                // 选择 MessageQueue（故障规避）
                MessageQueue mqSelected = this.selectOneMessageQueue(topicPublishInfo, lastBrokerName);
                if (mqSelected != null) {
                    mq = mqSelected;
                    brokersSent[times] = mq.getBrokerName();

                    try {
                        beginTimestampPrev = System.currentTimeMillis();

                        // 4. 发送消息
                        sendResult = this.sendKernelImpl(
                            msg,
                            mq,
                            communicationMode,
                            sendCallback,
                            topicPublishInfo,
                            timeout - costTime
                        );

                        endTimestamp = System.currentTimeMillis();

                        // 5. 更新故障延迟
                        this.updateFaultItem(mq.getBrokerName(), endTimestamp - beginTimestampPrev, false);

                        // 发送成功，直接返回
                        return sendResult;

                    } catch (RemotingException e) {
                        endTimestamp = System.currentTimeMillis();
                        this.updateFaultItem(mq.getBrokerName(), endTimestamp - beginTimestampPrev, true);
                        exception = e;
                        continue;
                    } catch (MQBrokerException e) {
                        endTimestamp = System.currentTimeMillis();
                        this.updateFaultItem(mq.getBrokerName(), endTimestamp - beginTimestampPrev, true);
                        exception = e;

                        // 某些异常不重试
                        if (!retryAnotherBrokerWhenNotStoreOK) {
                            throw e;
                        }
                        continue;
                    }
                } else {
                    break;
                }
            }

            // 6. 重试耗尽，抛出异常
            throw new MQClientException("Send failed", exception);
        }

        throw new MQClientException("No route info of this topic: " + msg.getTopic());
    }
}
```

---

## 三、Consumer 负载均衡

### 3.1 负载均衡策略

```java
public interface AllocateMessageQueueStrategy {
    /**
     * 分配队列
     * @param consumerGroup 消费组
     * @param currentCID 当前消费者ID
     * @param mqAll 所有队列
     * @param cidAll 所有消费者ID列表
     * @return 分配给当前消费者的队列列表
     */
    List<MessageQueue> allocate(
        final String consumerGroup,
        final String currentCID,
        final List<MessageQueue> mqAll,
        final List<String> cidAll
    );
}
```

#### 1️⃣ **平均分配策略**（默认）

```java
public class AllocateMessageQueueAveragely implements AllocateMessageQueueStrategy {

    @Override
    public List<MessageQueue> allocate(String consumerGroup, String currentCID,
                                      List<MessageQueue> mqAll, List<String> cidAll) {

        List<MessageQueue> result = new ArrayList<>();

        int index = cidAll.indexOf(currentCID);  // 当前消费者索引
        int mod = mqAll.size() % cidAll.size();  // 余数
        int averageSize =
            mqAll.size() <= cidAll.size() ? 1 : (mod > 0 && index < mod ? mqAll.size() / cidAll.size() + 1 : mqAll.size() / cidAll.size());

        int startIndex = (mod > 0 && index < mod) ? index * averageSize : index * averageSize + mod;
        int range = Math.min(averageSize, mqAll.size() - startIndex);

        for (int i = 0; i < range; i++) {
            result.add(mqAll.get((startIndex + i) % mqAll.size()));
        }

        return result;
    }
}
```

**示例**：
```
场景：8个Queue，3个Consumer

分配结果：
Consumer1: Q0, Q1, Q2  (3个)
Consumer2: Q3, Q4, Q5  (3个)
Consumer3: Q6, Q7      (2个)
```

#### 2️⃣ **环形分配策略**

```java
public class AllocateMessageQueueAveragelyByCircle implements AllocateMessageQueueStrategy {

    @Override
    public List<MessageQueue> allocate(String consumerGroup, String currentCID,
                                      List<MessageQueue> mqAll, List<String> cidAll) {

        List<MessageQueue> result = new ArrayList<>();

        int index = cidAll.indexOf(currentCID);

        // 环形分配
        for (int i = index; i < mqAll.size(); i++) {
            if (i % cidAll.size() == index) {
                result.add(mqAll.get(i));
            }
        }

        return result;
    }
}
```

**示例**：
```
场景：8个Queue，3个Consumer

分配结果：
Consumer1: Q0, Q3, Q6  (轮询)
Consumer2: Q1, Q4, Q7  (轮询)
Consumer3: Q2, Q5      (轮询)
```

### 3.2 Rebalance 机制

```
┌────────────────────────────────────────────┐
│        Consumer Rebalance 流程              │
├────────────────────────────────────────────┤
│                                             │
│  触发条件：                                  │
│  1. Consumer 数量变化（新增/下线）           │
│  2. Topic Queue 数量变化                    │
│  3. 定时触发（默认20秒）                    │
│                                             │
│  执行流程：                                  │
│  ┌──────────────────────────────┐          │
│  │ 1. 获取 Topic 的所有 Queue   │          │
│  └──────────────────────────────┘          │
│               ↓                             │
│  ┌──────────────────────────────┐          │
│  │ 2. 获取消费组的所有 Consumer │          │
│  └──────────────────────────────┘          │
│               ↓                             │
│  ┌──────────────────────────────┐          │
│  │ 3. 排序（确保一致性）        │          │
│  └──────────────────────────────┘          │
│               ↓                             │
│  ┌──────────────────────────────┐          │
│  │ 4. 执行分配策略              │          │
│  └──────────────────────────────┘          │
│               ↓                             │
│  ┌──────────────────────────────┐          │
│  │ 5. 更新本地 Queue 分配表     │          │
│  └──────────────────────────────┘          │
│               ↓                             │
│  ┌──────────────────────────────┐          │
│  │ 6. 停止多余的 PullRequest    │          │
│  │    启动新分配的 PullRequest  │          │
│  └──────────────────────────────┘          │
│                                             │
└────────────────────────────────────────────┘
```

---

## 四、故障转移

### 4.1 Broker 故障转移

```
场景：Master Broker 宕机

┌────────────────────────────────────────┐
│     自动故障转移流程                    │
├────────────────────────────────────────┤
│                                         │
│  1. Master 宕机                         │
│     ├─ 停止心跳                         │
│     └─ 无法处理请求                     │
│                                         │
│  2. NameServer 检测                     │
│     ├─ 120秒无心跳                      │
│     └─ 从路由表删除 Master              │
│                                         │
│  3. Producer/Consumer 更新路由          │
│     ├─ 下次路由更新获取新路由           │
│     └─ 自动切换到 Slave                 │
│                                         │
│  4. Slave 继续服务                      │
│     ├─ 提供消息拉取（只读）             │
│     └─ 无法接收新消息（只读）           │
│                                         │
└────────────────────────────────────────┘
```

**注意**：
- RocketMQ 4.x 不支持自动主从切换
- Slave 只能提供消费服务，不能接收新消息
- RocketMQ 5.x 支持 Raft 自动选主

### 4.2 Consumer 故障转移

```java
// Consumer 下线触发 Rebalance
public class RebalanceService extends ServiceThread {

    @Override
    public void run() {
        while (!this.isStopped()) {
            this.waitForRunning(waitInterval);
            this.mqClientFactory.doRebalance();
        }
    }
}

// Rebalance 实现
public boolean doRebalance(final boolean isOrder) {
    boolean balanced = true;

    // 遍历所有订阅的 Topic
    Map<String, SubscriptionData> subTable = this.getSubscriptionInner();
    if (subTable != null) {
        for (final Map.Entry<String, SubscriptionData> entry : subTable.entrySet()) {
            final String topic = entry.getKey();
            try {
                // 对每个 Topic 执行 Rebalance
                balanced = this.rebalanceByTopic(topic, isOrder);
            } catch (Throwable e) {
                log.error("rebalanceByTopic Exception", e);
            }
        }
    }

    this.truncateMessageQueueNotMyTopic();

    return balanced;
}
```

---

## 五、性能优化建议

### 5.1 Producer 配置

```properties
# Producer 配置优化
retryTimesWhenSendFailed=2          # 同步发送失败重试次数
retryTimesWhenSendAsyncFailed=2     # 异步发送失败重试次数
sendLatencyFaultEnable=true         # 启用延迟故障容错
```

### 5.2 Consumer 配置

```properties
# Consumer 配置优化
consumeThreadMin=20                 # 最小消费线程数
consumeThreadMax=64                 # 最大消费线程数
pullBatchSize=32                    # 批量拉取数量
allocateMessageQueueStrategy=       # 分配策略
  AllocateMessageQueueAveragely
```

---

## 六、总结

### 6.1 核心要点

1. **路由管理**：NameServer 集中管理路由信息
2. **Producer 负载均衡**：轮询选择 Queue + 故障规避
3. **Consumer 负载均衡**：多种分配策略 + Rebalance 机制
4. **故障转移**：自动检测故障 + 切换到可用节点

### 6.2 思考题

1. **为什么需要定时更新路由？**
   - 提示：动态感知 Broker 变化

2. **Rebalance 的缺点是什么？**
   - 提示：消息重复消费、消费暂停

3. **如何减少 Rebalance 频率？**
   - 提示：稳定 Consumer 数量

---

## 🎉 架构原理篇完结！

**恭喜！**你已经完成了 RocketMQ 架构原理篇的学习（11-18篇），掌握了：

✅ 整体架构设计
✅ NameServer 路由中心
✅ Broker 消息存储
✅ CommitLog 顺序写
✅ ConsumeQueue 索引
✅ Remoting 网络通信
✅ 消息路由与负载均衡

**下一阶段**：进阶特性篇，我们将学习事务消息、顺序消息、延迟消息等高级特性！

---

**本文关键词**：`消息路由` `负载均衡` `故障转移` `Rebalance`

**专题导航**：[上一篇：网络通信模型](/blog/rocketmq/posts/17-remoting-module/) | [下一篇：事务消息原理](#)
