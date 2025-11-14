---
title: "RocketMQ入门06：核心概念详解（下）- Topic、Queue、Tag、Key"
date: 2025-11-13T15:00:00+08:00
draft: false
tags: ["RocketMQ", "Topic", "Queue", "Tag", "消息模型"]
categories: ["技术"]
description: "深入理解 RocketMQ 的消息组织方式：Topic、Queue、Tag、Key 的设计理念、使用场景和最佳实践"
series: ["RocketMQ从入门到精通"]
weight: 6
stage: 1
stageTitle: "基础入门篇"
---

## 引言：消息的"地址系统"

如果把 RocketMQ 比作快递系统，那么：
- **Topic** 是省份（大的分类）
- **Queue** 是城市（负载均衡单元）
- **Tag** 是街道（消息过滤）
- **Key** 是门牌号（精确查找）

理解这套"地址系统"，才能高效地组织和管理消息。

## 一、Topic（主题）- 消息的逻辑分类

### 1.1 Topic 是什么？

```java
// Topic 是消息的一级分类，是逻辑概念
public class TopicConcept {

    // Topic 的本质：消息类型的逻辑分组
    String ORDER_TOPIC = "ORDER_TOPIC";           // 订单消息
    String PAYMENT_TOPIC = "PAYMENT_TOPIC";       // 支付消息
    String LOGISTICS_TOPIC = "LOGISTICS_TOPIC";   // 物流消息

    // 一个 Topic 包含多个 Queue
    class TopicStructure {
        String topicName;
        int readQueueNums = 4;   // 读队列数量
        int writeQueueNums = 4;  // 写队列数量
        int perm = 6;           // 权限：2-写 4-读 6-读写

        // Topic 在多个 Broker 上的分布
        Map<String/* brokerName */, List<MessageQueue>> brokerQueues;
    }
}
```

### 1.2 Topic 的设计原则

```java
public class TopicDesignPrinciples {

    // 原则1：按业务领域划分
    class BusinessDomain {
        // ✅ 推荐：清晰的业务边界
        String TRADE_TOPIC = "TRADE_TOPIC";
        String USER_TOPIC = "USER_TOPIC";
        String INVENTORY_TOPIC = "INVENTORY_TOPIC";

        // ❌ 不推荐：过于宽泛
        String ALL_MESSAGE_TOPIC = "ALL_MESSAGE_TOPIC";
    }

    // 原则2：考虑消息特性
    class MessageCharacteristics {
        // 按消息量级区分
        String HIGH_TPS_TOPIC = "LOG_TOPIC";        // 高吞吐
        String LOW_TPS_TOPIC = "ALERT_TOPIC";       // 低吞吐

        // 按消息大小区分
        String BIG_MSG_TOPIC = "FILE_TOPIC";        // 大消息
        String SMALL_MSG_TOPIC = "EVENT_TOPIC";     // 小消息

        // 按重要程度区分
        String CRITICAL_TOPIC = "PAYMENT_TOPIC";    // 核心业务
        String NORMAL_TOPIC = "STAT_TOPIC";         // 一般业务
    }

    // 原则3：隔离不同优先级
    class PriorityIsolation {
        // 不同优先级使用不同 Topic
        String ORDER_HIGH_PRIORITY = "ORDER_HIGH_TOPIC";
        String ORDER_NORMAL_PRIORITY = "ORDER_NORMAL_TOPIC";
        String ORDER_LOW_PRIORITY = "ORDER_LOW_TOPIC";
    }
}
```

### 1.3 Topic 创建和管理

```bash
# 自动创建（不推荐生产使用）
autoCreateTopicEnable=true
defaultTopicQueueNums=4

# 手动创建（推荐）
sh mqadmin updateTopic \
  -n localhost:9876 \
  -t ORDER_TOPIC \
  -c DefaultCluster \
  -r 8 \  # 读队列数量
  -w 8 \  # 写队列数量
  -p 6    # 权限

# 查看 Topic 列表
sh mqadmin topicList -n localhost:9876

# 查看 Topic 详情
sh mqadmin topicStatus -n localhost:9876 -t ORDER_TOPIC
```

## 二、Queue（队列）- 负载均衡的基本单元

### 2.1 Queue 的本质

```java
public class QueueConcept {

    // Queue 是 Topic 的物理分片
    class MessageQueue {
        private String topic;      // 所属 Topic
        private String brokerName; // 所在 Broker
        private int queueId;       // 队列 ID

        @Override
        public String toString() {
            // ORDER_TOPIC@broker-a@0
            return topic + "@" + brokerName + "@" + queueId;
        }
    }

    // Topic 与 Queue 的关系
    class TopicQueueRelation {
        // 1个 Topic = N 个 Queue
        // 例如：ORDER_TOPIC 有 8 个 Queue
        // broker-a: queue0, queue1, queue2, queue3
        // broker-b: queue0, queue1, queue2, queue3

        Map<String, Integer> distribution = new HashMap<>();
        {
            distribution.put("broker-a", 4);
            distribution.put("broker-b", 4);
            // Total: 8 Queues
        }
    }
}
```

### 2.2 Queue 的负载均衡

```java
public class QueueLoadBalance {

    // 生产者端：选择 Queue 发送
    public MessageQueue selectQueue() {
        List<MessageQueue> queues = getQueues("ORDER_TOPIC");

        // 策略1：轮询（默认）
        int index = sendWhichQueue.incrementAndGet() % queues.size();
        return queues.get(index);

        // 策略2：根据业务 Key 路由
        String orderId = "12345";
        int index = orderId.hashCode() % queues.size();
        return queues.get(index);

        // 策略3：最小延迟
        return selectQueueByLatency(queues);
    }

    // 消费者端：分配 Queue 消费
    public List<MessageQueue> allocateQueues() {
        // 假设：8个 Queue，3个 Consumer
        // Consumer0: queue0, queue1, queue2
        // Consumer1: queue3, queue4, queue5
        // Consumer2: queue6, queue7

        return AllocateStrategy.allocate(
            allQueues,
            currentConsumerId,
            allConsumerIds
        );
    }
}
```

### 2.3 Queue 数量设计

```java
public class QueueNumberDesign {

    // Queue 数量考虑因素
    class Factors {
        // 1. 并发度
        // Queue 数量 = 预期 TPS / 单 Queue TPS
        // 例如：10万 TPS / 1万 TPS = 10个 Queue

        // 2. Consumer 数量
        // Queue 数量 >= Consumer 数量
        // 否则有 Consumer 闲置

        // 3. Broker 数量
        // Queue 数量 = Broker 数量 × 单 Broker Queue 数
        // 例如：2个 Broker × 4 = 8个 Queue
    }

    // 动态调整 Queue 数量
    public void adjustQueueNumber() {
        // 增加 Queue（在线扩容）
        updateTopic("ORDER_TOPIC", readQueues=16, writeQueues=16);

        // 减少 Queue（需谨慎）
        // 1. 先减少写队列
        updateTopic("ORDER_TOPIC", readQueues=16, writeQueues=8);
        // 2. 等待消费完成
        waitForConsume();
        // 3. 再减少读队列
        updateTopic("ORDER_TOPIC", readQueues=8, writeQueues=8);
    }
}
```

## 三、Tag（标签）- 消息的二级分类

### 3.1 Tag 的作用

```java
public class TagUsage {

    // Tag 用于同一 Topic 下的消息细分
    public void sendWithTag() {
        // 订单 Topic 下的不同消息类型
        Message createOrder = new Message("ORDER_TOPIC", "CREATE", body);
        Message payOrder = new Message("ORDER_TOPIC", "PAY", body);
        Message cancelOrder = new Message("ORDER_TOPIC", "CANCEL", body);
        Message refundOrder = new Message("ORDER_TOPIC", "REFUND", body);
    }

    // Tag vs Topic 的选择
    class TagVsTopic {
        // 使用 Tag 的场景：
        // 1. 消息类型相关性强
        // 2. 需要统一管理
        // 3. 消费者可能订阅多种类型

        // ✅ 推荐：相关业务用 Tag 区分
        void goodPractice() {
            // 订单的不同状态用 Tag
            new Message("ORDER_TOPIC", "CREATED", body);
            new Message("ORDER_TOPIC", "PAID", body);
            new Message("ORDER_TOPIC", "SHIPPED", body);
        }

        // ❌ 不推荐：无关业务用同一 Topic
        void badPractice() {
            // 订单和用户混在一起
            new Message("BUSINESS_TOPIC", "ORDER_CREATE", body);
            new Message("BUSINESS_TOPIC", "USER_REGISTER", body);
        }
    }
}
```

### 3.2 Tag 过滤机制

```java
public class TagFiltering {

    // 消费者订阅
    public void subscribeWithTag() throws Exception {
        DefaultMQPushConsumer consumer = new DefaultMQPushConsumer();

        // 订阅所有 Tag
        consumer.subscribe("ORDER_TOPIC", "*");

        // 订阅单个 Tag
        consumer.subscribe("ORDER_TOPIC", "CREATE");

        // 订阅多个 Tag（|| 分隔）
        consumer.subscribe("ORDER_TOPIC", "CREATE || PAY || CANCEL");

        // SQL92 表达式（需要 Broker 开启）
        consumer.subscribe("ORDER_TOPIC",
            MessageSelector.bySql("amount > 1000 AND type = 'GOLD'"));
    }

    // Tag 过滤原理
    class FilterPrinciple {
        // 1. Broker 端过滤（粗过滤）
        // 根据 Tag HashCode 快速过滤
        // 在 ConsumeQueue 中存储了 Tag HashCode

        // 2. Consumer 端过滤（精过滤）
        // 再次验证 Tag 字符串
        // 防止 Hash 冲突导致的误判

        public boolean filterMessage(MessageExt msg, String subscribeTags) {
            // Broker 端：HashCode 匹配
            long tagCode = msg.getTagsCode();
            if (!isMatched(tagCode, subscribeTagCodes)) {
                return false;
            }

            // Consumer 端：字符串匹配
            String msgTag = msg.getTags();
            return isTagMatched(msgTag, subscribeTags);
        }
    }
}
```

### 3.3 Tag 最佳实践

```java
public class TagBestPractices {

    // 1. Tag 命名规范
    class TagNaming {
        // 使用大写字母和下划线
        String GOOD_TAG = "ORDER_CREATED";

        // 避免特殊字符
        String BAD_TAG = "order-created@2023";  // 避免

        // 保持简短有意义
        String CONCISE = "PAY_SUCCESS";
        String VERBOSE = "ORDER_PAYMENT_SUCCESS_WITH_DISCOUNT";  // 太长
    }

    // 2. Tag 使用策略
    class TagStrategy {
        // 按业务流程设计
        String[] ORDER_FLOW = {
            "CREATED",     // 订单创建
            "PAID",        // 支付完成
            "SHIPPED",     // 已发货
            "RECEIVED",    // 已收货
            "COMPLETED"    // 已完成
        };

        // 按事件类型设计
        String[] EVENT_TYPE = {
            "INSERT",      // 新增
            "UPDATE",      // 更新
            "DELETE"       // 删除
        };
    }
}
```

## 四、Key - 消息的业务标识

### 4.1 Key 的用途

```java
public class KeyUsage {

    // Key 用于消息的业务标识和查询
    public void sendWithKey() {
        Message msg = new Message("ORDER_TOPIC", "CREATE", body);

        // 设置业务唯一标识
        msg.setKeys("ORDER_12345");

        // 设置多个 Key（空格分隔）
        msg.setKeys("ORDER_12345 USER_67890");

        producer.send(msg);
    }

    // Key 的主要用途
    class KeyPurpose {
        // 1. 消息查询
        void queryByKey() {
            // 通过 Key 查询消息
            QueryResult result =
                mqadmin.queryMsgByKey("ORDER_TOPIC", "ORDER_12345");
        }

        // 2. 去重判断
        void deduplication(String key) {
            if (processedKeys.contains(key)) {
                // 已处理，跳过
                return;
            }
            processMessage();
            processedKeys.add(key);
        }

        // 3. 业务追踪
        void traceOrder(String orderId) {
            // 追踪订单的所有消息
            List<Message> orderMessages =
                queryAllMessagesByKey(orderId);
        }
    }
}
```

### 4.2 Key 的索引机制

```java
public class KeyIndexing {

    // IndexFile 结构
    class IndexFile {
        // 通过 Key 建立索引
        // 存储格式：Key Hash -> Physical Offset

        private IndexHeader header;      // 文件头
        private SlotTable slotTable;    // Hash 槽
        private IndexLinkedList indexes; // 索引链表

        public void putKey(String key, long offset) {
            int keyHash = hash(key);
            int slotPos = keyHash % 500_0000;  // 500万个槽

            // 存储索引
            IndexItem item = new IndexItem();
            item.setKeyHash(keyHash);
            item.setPhyOffset(offset);
            item.setTimeDiff(storeTimestamp - beginTimestamp);

            // 处理 Hash 冲突（链表）
            item.setSlotValue(slotTable.get(slotPos));
            slotTable.put(slotPos, indexes.add(item));
        }
    }
}
```

### 4.3 Key 设计建议

```java
public class KeyDesignSuggestions {

    // 1. Key 的选择
    class KeySelection {
        // ✅ 好的 Key：业务唯一标识
        String orderId = "ORDER_2023110901234";
        String userId = "USER_123456";
        String transactionId = "TXN_9876543210";

        // ❌ 不好的 Key：无业务含义
        String uuid = UUID.randomUUID().toString();
        String timestamp = String.valueOf(System.currentTimeMillis());
    }

    // 2. 复合 Key
    class CompositeKey {
        public String generateKey(Order order) {
            // 组合多个维度
            return String.format("%s_%s_%s",
                order.getOrderId(),
                order.getUserId(),
                order.getCreateTime()
            );
        }
    }

    // 3. Key 规范
    class KeySpecification {
        // 长度控制
        static final int MAX_KEY_LENGTH = 128;

        // 字符限制
        static final String KEY_PATTERN = "^[a-zA-Z0-9_-]+$";

        // 避免特殊字符
        public String sanitizeKey(String key) {
            return key.replaceAll("[^a-zA-Z0-9_-]", "_");
        }
    }
}
```

## 五、消息属性（Properties）

### 5.1 系统属性 vs 用户属性

```java
public class MessageProperties {

    // 系统属性（RocketMQ 内部使用）
    class SystemProperties {
        String UNIQ_KEY = "__UNIQ_KEY__";           // 消息唯一标识
        String MAX_OFFSET = "__MAX_OFFSET__";       // 最大偏移量
        String MIN_OFFSET = "__MIN_OFFSET__";       // 最小偏移量
        String TRANSACTION_ID = "__TRANSACTION_ID__"; // 事务ID
        String DELAY_LEVEL = "__DELAY_LEVEL__";     // 延迟级别
    }

    // 用户自定义属性
    public void setUserProperties() {
        Message msg = new Message("TOPIC", "TAG", body);

        // 添加业务属性
        msg.putUserProperty("orderType", "ONLINE");
        msg.putUserProperty("paymentMethod", "CREDIT_CARD");
        msg.putUserProperty("region", "EAST");
        msg.putUserProperty("vipLevel", "GOLD");

        // SQL92 过滤时使用
        consumer.subscribe("TOPIC",
            MessageSelector.bySql("vipLevel = 'GOLD' AND region = 'EAST'"));
    }
}
```

### 5.2 属性的应用场景

```java
public class PropertiesUseCases {

    // 1. 消息路由
    public void routeByProperty(Message msg) {
        String region = msg.getUserProperty("region");

        // 根据地区路由到不同集群
        if ("NORTH".equals(region)) {
            sendToNorthCluster(msg);
        } else {
            sendToSouthCluster(msg);
        }
    }

    // 2. 监控统计
    public void monitoring(Message msg) {
        // 统计不同类型订单
        String orderType = msg.getUserProperty("orderType");
        metrics.increment("order.count", "type", orderType);
    }

    // 3. 灰度发布
    public void grayRelease(Message msg) {
        msg.putUserProperty("version", "2.0");
        msg.putUserProperty("gray", "true");
        msg.putUserProperty("percentage", "10");  // 10% 流量
    }
}
```

## 六、组合使用示例

### 6.1 电商订单场景

```java
public class ECommerceExample {

    public void processOrder(Order order) {
        // Topic：按业务领域
        String topic = "ORDER_TOPIC";

        // Tag：按订单状态
        String tag = getOrderTag(order.getStatus());

        // Key：订单号（用于查询）
        String key = order.getOrderId();

        // 构造消息
        Message msg = new Message(topic, tag, key,
            JSON.toJSONBytes(order));

        // 添加属性（用于过滤和统计）
        msg.putUserProperty("userId", order.getUserId());
        msg.putUserProperty("amount", String.valueOf(order.getAmount()));
        msg.putUserProperty("payMethod", order.getPayMethod());
        msg.putUserProperty("orderType", order.getType());

        // 发送消息
        SendResult result = producer.send(msg);
    }

    private String getOrderTag(OrderStatus status) {
        switch (status) {
            case CREATED: return "ORDER_CREATED";
            case PAID: return "ORDER_PAID";
            case SHIPPED: return "ORDER_SHIPPED";
            case COMPLETED: return "ORDER_COMPLETED";
            case CANCELLED: return "ORDER_CANCELLED";
            default: return "ORDER_UNKNOWN";
        }
    }
}
```

### 6.2 消费者订阅策略

```java
public class ConsumerStrategy {

    // 场景1：订阅所有订单消息
    class AllOrderConsumer {
        public void subscribe() {
            consumer.subscribe("ORDER_TOPIC", "*");
        }
    }

    // 场景2：只处理支付相关
    class PaymentConsumer {
        public void subscribe() {
            consumer.subscribe("ORDER_TOPIC", "ORDER_PAID || ORDER_REFUND");
        }
    }

    // 场景3：VIP 订单处理
    class VipOrderConsumer {
        public void subscribe() {
            consumer.subscribe("ORDER_TOPIC",
                MessageSelector.bySql("orderType = 'VIP' AND amount > 1000"));
        }
    }

    // 场景4：特定用户订单
    class UserOrderConsumer {
        public void consumeMessage(MessageExt msg) {
            String userId = msg.getUserProperty("userId");
            if ("VIP_USER_123".equals(userId)) {
                // 特殊处理 VIP 用户订单
                handleVipOrder(msg);
            } else {
                // 普通处理
                handleNormalOrder(msg);
            }
        }
    }
}
```

## 七、设计原则总结

### 7.1 层级设计原则

```
消息层级设计：
┌─────────────────────────────────┐
│          Topic                  │ <- 业务大类
├─────────────────────────────────┤
│      Queue1  Queue2  Queue3     │ <- 负载均衡
├─────────────────────────────────┤
│    Tag1    Tag2    Tag3        │ <- 消息子类
├─────────────────────────────────┤
│         Key (业务ID)            │ <- 消息标识
├─────────────────────────────────┤
│      Properties (属性)          │ <- 扩展信息
└─────────────────────────────────┘
```

### 7.2 最佳实践建议

```java
public class BestPractices {

    // 1. Topic 设计：粗粒度
    // 一个业务领域一个 Topic
    // 避免创建过多 Topic

    // 2. Queue 设计：适度
    // Queue 数量 = max(预期并发数, Consumer数量)
    // 一般 8-16 个即可

    // 3. Tag 设计：细粒度
    // 同一 Topic 下的不同消息类型
    // 便于消费者灵活订阅

    // 4. Key 设计：唯一性
    // 使用业务唯一标识
    // 便于消息追踪和查询

    // 5. Properties：扩展性
    // 存储额外的业务信息
    // 支持 SQL92 复杂过滤
}
```

## 八、常见问题

### 8.1 Topic 过多的问题

```java
// 问题：Topic 过多导致的影响
// 1. 路由信息膨胀
// 2. 内存占用增加
// 3. 管理复杂度上升

// 解决方案：合并相关 Topic，用 Tag 区分
// Before: USER_REGISTER_TOPIC, USER_UPDATE_TOPIC, USER_DELETE_TOPIC
// After: USER_TOPIC + Tags(REGISTER, UPDATE, DELETE)
```

### 8.2 Queue 数量不当

```java
// 问题：Queue 太少
// - Consumer 空闲
// - 并发度不够

// 问题：Queue 太多
// - 管理开销大
// - Rebalance 频繁

// 解决：动态调整
// 监控 Queue 积压和 Consumer 负载
// 根据实际情况调整 Queue 数量
```

## 九、总结

理解了 Topic、Queue、Tag、Key 这些核心概念，我们就掌握了 RocketMQ 的消息组织方式：

- **Topic**：业务领域的划分，粗粒度
- **Queue**：负载均衡的单元，适度即可
- **Tag**：消息类型的细分，灵活过滤
- **Key**：业务标识，方便追踪

合理使用这些概念，能让我们的消息系统更加清晰、高效、易维护。

## 下一篇预告

掌握了消息的组织方式，下一篇我们将深入探讨 RocketMQ 的消息模型：点对点模式 vs 发布订阅模式的实现原理和使用场景。

---

**实践练习**：

1. 设计一个电商系统的 Topic/Tag 结构
2. 计算你的业务场景需要多少 Queue
3. 思考什么样的业务字段适合做 Key

在实践中加深理解，我们下篇见！