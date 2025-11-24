---
title: "RocketMQ生产04：消息丢失排查 - 全链路追踪与问题定位"
date: 2025-11-15T10:00:00+08:00
draft: false
tags: ["RocketMQ", "消息丢失", "问题排查", "全链路追踪"]
categories: ["技术"]
description: "系统化排查消息丢失问题，建立完整的消息可靠性保障机制"
series: ["RocketMQ从入门到精通"]
weight: 34
stage: 4
stageTitle: "生产实践篇"
---

## 引言：消息丢了怎么办？

凌晨接到告警："订单支付成功，但库存未扣减！"排查半天，发现是 RocketMQ 消息丢了。消息到底在哪个环节丢的？如何快速定位？如何避免再次发生？

**消息丢失的常见表现**：
- ❌ Producer 发送成功，Consumer 未收到
- ❌ Broker 重启后，部分消息消失
- ❌ Consumer 消费后，业务未执行
- ❌ 高峰期消息神秘失踪

**本文目标**：
- ✅ 理解消息丢失的所有可能环节
- ✅ 掌握全链路排查方法
- ✅ 建立消息可靠性保障机制
- ✅ 实现端到端消息追踪

---

## 一、消息丢失的三个环节

### 1.1 全链路示意图

```
┌──────────┐       ┌──────────┐       ┌──────────┐
│ Producer │  (1)  │  Broker  │  (2)  │ Consumer │
│          ├──────>│          ├──────>│          │
└──────────┘       └──────────┘       └──────────┘
    ⚠️               ⚠️                 ⚠️
 发送端丢失        存储端丢失        消费端丢失
```

**三个风险点**：
1. **Producer 发送丢失**：网络故障、未等待响应
2. **Broker 存储丢失**：异步刷盘、磁盘故障
3. **Consumer 消费丢失**：自动ACK、业务异常未重试

---

## 二、发送端丢失排查

### 2.1 同步发送 vs 异步发送

#### 2.1.1 同步发送（推荐）

```java
// ✅ 正确：等待发送结果
try {
    SendResult result = producer.send(message);
    if (result.getSendStatus() == SendStatus.SEND_OK) {
        log.info("发送成功，msgId={}", result.getMsgId());
    } else {
        log.error("发送失败，status={}", result.getSendStatus());
        // 重试或告警
    }
} catch (Exception e) {
    log.error("发送异常", e);
    // 异常处理：重试、记录数据库、告警
}
```

**关键点**：
- ✅ 必须检查 `SendStatus`
- ✅ 捕获异常并处理
- ✅ 记录发送失败的消息

---

#### 2.1.2 异步发送（易丢失）

```java
// ❌ 错误：不处理回调
producer.send(message, new SendCallback() {
    @Override
    public void onSuccess(SendResult result) {
        // 什么都不做，容易忽略失败
    }

    @Override
    public void onException(Throwable e) {
        // 未记录失败消息
    }
});

// ✅ 正确：处理回调
producer.send(message, new SendCallback() {
    @Override
    public void onSuccess(SendResult result) {
        log.info("异步发送成功，msgId={}", result.getMsgId());
        // 删除本地暂存记录
        messageService.deleteLocal(message.getKey());
    }

    @Override
    public void onException(Throwable e) {
        log.error("异步发送失败，key={}", message.getKey(), e);
        // 1. 记录到失败表
        failedMessageService.save(message);
        // 2. 告警
        alertService.sendAlert("消息发送失败");
        // 3. 定时任务重试
    }
});
```

---

### 2.2 Producer 配置检查

```java
DefaultMQProducer producer = new DefaultMQProducer("producer_group");

// ❌ 错误配置
producer.setSendMsgTimeout(1000);  // 超时时间太短，容易失败
producer.setRetryTimesWhenSendFailed(0);  // 不重试

// ✅ 正确配置
producer.setSendMsgTimeout(10000);  // 10秒超时（根据业务调整）
producer.setRetryTimesWhenSendFailed(3);  // 失败重试3次
producer.setRetryTimesWhenSendAsyncFailed(3);  // 异步发送失败重试
producer.setCompressMsgBodyOverHowMuch(4096);  // 消息压缩阈值
```

**排查方法**：
```bash
# 1. 检查 Producer 配置
jinfo <producer-pid> | grep -i "rocketmq"

# 2. 查看发送失败日志
grep "send message failed" /var/log/app/producer.log

# 3. 统计发送失败率
# 通过监控指标（Prometheus）
rate(rocketmq_producer_send_failed_total[5m]) / rate(rocketmq_producer_send_total[5m]) * 100
```

---

### 2.3 网络故障排查

```bash
# 1. 检查 NameServer 连接
telnet 192.168.1.100 9876

# 2. 检查 Broker 连接
telnet 192.168.1.101 10911

# 3. 抓包分析（高级）
tcpdump -i eth0 -nn 'port 10911' -w rocketmq.pcap

# 4. 检查网络延迟
ping -c 100 192.168.1.101
# 平均延迟应 < 1ms（同机房）
```

---

## 三、存储端丢失排查

### 3.1 刷盘策略检查

#### 3.1.1 异步刷盘（默认，有丢失风险）

```properties
# broker.conf
flushDiskType=ASYNC_FLUSH  # 异步刷盘

# 风险：Broker 宕机时，内存中未刷盘的消息丢失
```

**排查步骤**：
```bash
# 1. 检查 Broker 配置
grep flushDiskType /opt/rocketmq/conf/broker.conf

# 2. 检查重启日志
grep "shutdown" /opt/rocketmq/logs/rocketmqlogs/broker.log

# 3. 对比重启前后的消息量
# 重启前
sh mqadmin statsAll -n 127.0.0.1:9876 > before.txt

# 重启后
sh mqadmin statsAll -n 127.0.0.1:9876 > after.txt

# 对比差异
diff before.txt after.txt
```

---

#### 3.1.2 同步刷盘（可靠，性能低）

```properties
# broker.conf
flushDiskType=SYNC_FLUSH  # 同步刷盘

# 优点：消息写入磁盘才返回成功，不丢失
# 缺点：性能降低 30-50%
```

**适用场景**：
- ✅ 金融支付消息
- ✅ 核心订单消息
- ❌ 日志、埋点等低重要性消息

---

### 3.2 主从同步检查

#### 3.2.1 同步复制 vs 异步复制

```properties
# Master 配置
brokerRole=SYNC_MASTER  # 同步复制（推荐）
# brokerRole=ASYNC_MASTER  # 异步复制（Master 宕机会丢消息）

# Slave 配置
brokerRole=SLAVE
```

**验证主从同步**：
```bash
# 1. 查看主从同步延迟
sh mqadmin brokerStatus -n 127.0.0.1:9876 -b 192.168.1.100:10911

# 2. 输出关键指标
# slaveAckOffset: Slave 已确认的偏移量
# masterPutWhere: Master 最新写入位置
# diff: masterPutWhere - slaveAckOffset（应接近0）

# 3. 如果 diff 持续增大，说明主从同步滞后
```

---

### 3.3 磁盘故障排查

```bash
# 1. 检查磁盘健康状态
smartctl -H /dev/sdb

# 2. 检查磁盘 I/O 错误
dmesg | grep -i "i/o error"

# 3. 检查文件系统
fsck -n /dev/sdb1  # -n 表示只检查不修复

# 4. 监控磁盘使用率
df -h /data/rocketmq/store

# 5. 查看 RocketMQ 存储日志
grep "disk full" /opt/rocketmq/logs/rocketmqlogs/store.log
```

**常见磁盘问题**：
- 磁盘满：消息写入失败
- 坏道：部分消息损坏
- I/O 超时：写入延迟高，触发超时

---

### 3.4 消息可查询性验证

```bash
# 1. 按 msgId 查询消息
sh mqadmin queryMsgById -n 127.0.0.1:9876 -i "C0A8016400002A9F0000000000000000"

# 2. 按 Key 查询消息
sh mqadmin queryMsgByKey -n 127.0.0.1:9876 -t order_topic -k "ORDER_12345"

# 3. 按时间范围查询
sh mqadmin queryMsgByTime -n 127.0.0.1:9876 \
  -t order_topic \
  -b "2025-11-15 00:00:00" \
  -e "2025-11-15 23:59:59"

# 如果查不到，可能真的丢了
```

---

## 四、消费端丢失排查

### 4.1 自动ACK vs 手动ACK

#### 4.1.1 自动ACK（易丢失）

```java
// ❌ 错误：消费失败也返回 SUCCESS
@Override
public ConsumeConcurrentlyStatus consumeMessage(
    List<MessageExt> msgs,
    ConsumeConcurrentlyContext context) {

    for (MessageExt msg : msgs) {
        try {
            processMessage(msg);
        } catch (Exception e) {
            log.error("处理失败", e);
            // 吞掉异常，返回 SUCCESS
            // 消息被确认消费，无法重试，丢失！
        }
    }
    return ConsumeConcurrentlyStatus.CONSUME_SUCCESS;
}

// ✅ 正确：失败返回 RECONSUME_LATER
@Override
public ConsumeConcurrentlyStatus consumeMessage(
    List<MessageExt> msgs,
    ConsumeConcurrentlyContext context) {

    for (MessageExt msg : msgs) {
        try {
            processMessage(msg);
        } catch (Exception e) {
            log.error("处理失败，返回重试", e);
            return ConsumeConcurrentlyStatus.RECONSUME_LATER;  // 触发重试
        }
    }
    return ConsumeConcurrentlyStatus.CONSUME_SUCCESS;
}
```

---

### 4.2 消费幂等性检查

```java
// 问题：重复消费导致业务异常
@Override
public ConsumeConcurrentlyStatus consumeMessage(List<MessageExt> msgs, ConsumeConcurrentlyContext context) {
    for (MessageExt msg : msgs) {
        String orderId = msg.getKeys();

        // ❌ 错误：未做幂等性检查
        orderService.create(orderId);  // 重复消费会创建多个订单

        // ✅ 正确：幂等性检查
        if (orderService.exists(orderId)) {
            log.warn("订单已存在，跳过，orderId={}", orderId);
            return ConsumeConcurrentlyStatus.CONSUME_SUCCESS;
        }

        orderService.create(orderId);
    }
    return ConsumeConcurrentlyStatus.CONSUME_SUCCESS;
}
```

**幂等性实现方案**：
1. **数据库唯一索引**：`order_id` 字段设置唯一约束
2. **分布式锁**：消费前加锁，消费后释放
3. **消息表**：记录已消费的 `msgId`

---

### 4.3 消费进度检查

```bash
# 1. 查看消费进度
sh mqadmin consumerProgress -g order_consumer_group -n 127.0.0.1:9876

# 输出示例：
#Topic          Broker      QID  Broker Offset   Consumer Offset  Diff
#order_topic    broker-a    0    1000000          995000           5000
#order_topic    broker-a    1    1000000          1000000          0

# 2. 分析：
# Diff > 0：有消息堆积，Consumer 消费慢
# Diff = 0：消费正常
# Consumer Offset > Broker Offset：异常，可能配置错误

# 3. 查看消费组状态
sh mqadmin consumerStatus -g order_consumer_group -n 127.0.0.1:9876
```

---

### 4.4 死信队列检查

```bash
# 1. 查看死信队列
sh mqadmin consumerProgress -g order_consumer_group -n 127.0.0.1:9876 | grep "%DLQ%"

# 2. 查询死信消息
sh mqadmin queryMsgByKey -n 127.0.0.1:9876 \
  -t "%DLQ%order_consumer_group" \
  -k "ORDER_12345"

# 3. 分析死信原因
# - 消费异常超过16次
# - 业务代码BUG
# - 数据格式错误
```

**死信消息处理**：
```java
// 监听死信队列
@RocketMQMessageListener(
    topic = "%DLQ%order_consumer_group",
    consumerGroup = "dlq_handler_group"
)
public class DLQHandler implements RocketMQListener<String> {
    @Override
    public void onMessage(String message) {
        log.error("死信消息：{}", message);

        // 1. 记录到数据库
        dlqMessageService.save(message);

        // 2. 告警
        alertService.sendAlert("发现死信消息");

        // 3. 人工介入处理
    }
}
```

---

## 五、全链路消息追踪

### 5.1 启用消息轨迹

#### 5.1.1 Broker 配置

```properties
# broker.conf
# 启用消息轨迹
traceTopicEnable=true

# 消息轨迹存储 Topic（默认）
msgTraceTopicName=RMQ_SYS_TRACE_TOPIC
```

#### 5.1.2 Producer 配置

```java
// 启用消息轨迹
DefaultMQProducer producer = new DefaultMQProducer("producer_group", true);  // 第二个参数启用轨迹
producer.setNamesrvAddr("127.0.0.1:9876");
producer.start();

// 发送消息时自动记录轨迹
Message msg = new Message("order_topic", "order_body".getBytes());
msg.setKeys("ORDER_12345");  // 设置 Key，方便追踪
producer.send(msg);
```

#### 5.1.3 Consumer 配置

```java
// 启用消息轨迹
DefaultMQPushConsumer consumer = new DefaultMQPushConsumer("consumer_group", true);  // 启用轨迹
consumer.subscribe("order_topic", "*");
consumer.registerMessageListener(new MessageListenerConcurrently() {
    @Override
    public ConsumeConcurrentlyStatus consumeMessage(
        List<MessageExt> msgs,
        ConsumeConcurrentlyContext context) {
        // 消费逻辑
        return ConsumeConcurrentlyStatus.CONSUME_SUCCESS;
    }
});
consumer.start();
```

---

### 5.2 查询消息轨迹

```bash
# 按 Key 查询消息轨迹
sh mqadmin queryMsgTraceById -n 127.0.0.1:9876 -k "ORDER_12345"

# 输出示例：
# ======== Trace Info ========
# MsgId: C0A8016400002A9F0000000000000000
# Keys: ORDER_12345
# Tags: null
# ProducerGroup: producer_group
# SendTime: 2025-11-15 10:00:00
# SendStatus: SEND_OK
# ConsumerGroup: consumer_group
# ConsumeTime: 2025-11-15 10:00:05
# ConsumeStatus: CONSUME_SUCCESS
# ConsumeRT: 5ms
```

**轨迹包含信息**：
- ✅ 消息发送时间、状态
- ✅ 消息存储位置（Broker、Queue）
- ✅ 消息消费时间、状态
- ✅ 消费耗时

---

### 5.3 自定义业务追踪

```java
// 在消息中添加追踪ID
public class TraceContext {
    private String traceId;  // 全局追踪ID
    private String spanId;   // 当前操作ID
    private String parentId; // 父操作ID
}

// Producer 端
String traceId = UUID.randomUUID().toString();
Message msg = new Message("order_topic", "body".getBytes());
msg.putUserProperty("traceId", traceId);
msg.putUserProperty("spanId", "send");
producer.send(msg);

log.info("[Trace] 发送消息, traceId={}, msgId={}", traceId, sendResult.getMsgId());

// Consumer 端
@Override
public ConsumeConcurrentlyStatus consumeMessage(List<MessageExt> msgs, ConsumeConcurrentlyContext context) {
    for (MessageExt msg : msgs) {
        String traceId = msg.getUserProperty("traceId");
        String parentSpanId = msg.getUserProperty("spanId");

        MDC.put("traceId", traceId);  // 放入 MDC，后续日志自动携带
        log.info("[Trace] 开始消费, traceId={}, msgId={}", traceId, msg.getMsgId());

        try {
            processMessage(msg);
            log.info("[Trace] 消费成功, traceId={}", traceId);
        } catch (Exception e) {
            log.error("[Trace] 消费失败, traceId={}", traceId, e);
        } finally {
            MDC.clear();
        }
    }
    return ConsumeConcurrentlyStatus.CONSUME_SUCCESS;
}
```

---

## 六、消息可靠性保障方案

### 6.1 发送端保障

```java
@Service
public class ReliableMessageSender {

    @Autowired
    private DefaultMQProducer producer;

    @Autowired
    private MessageStoreService messageStoreService;  // 本地消息表

    /**
     * 可靠发送：本地消息表 + 定时补偿
     */
    @Transactional
    public void sendReliable(Message message) {
        // 1. 先存储到本地消息表（状态：待发送）
        LocalMessage localMsg = messageStoreService.save(message, MessageStatus.PENDING);

        // 2. 发送消息
        try {
            SendResult result = producer.send(message);
            if (result.getSendStatus() == SendStatus.SEND_OK) {
                // 3. 更新状态为已发送
                messageStoreService.updateStatus(localMsg.getId(), MessageStatus.SENT);
            } else {
                log.error("发送失败，status={}", result.getSendStatus());
            }
        } catch (Exception e) {
            log.error("发送异常", e);
            // 保持状态为 PENDING，由定时任务重试
        }
    }

    /**
     * 定时任务：补偿发送失败的消息
     */
    @Scheduled(fixedDelay = 60000)  // 每分钟执行一次
    public void retryPendingMessages() {
        List<LocalMessage> pendingMessages = messageStoreService.findPendingMessages();
        for (LocalMessage msg : pendingMessages) {
            try {
                Message rocketMQMsg = convertToMessage(msg);
                SendResult result = producer.send(rocketMQMsg);
                if (result.getSendStatus() == SendStatus.SEND_OK) {
                    messageStoreService.updateStatus(msg.getId(), MessageStatus.SENT);
                }
            } catch (Exception e) {
                log.error("补偿发送失败, msgId={}", msg.getId(), e);
            }
        }
    }
}
```

---

### 6.2 Broker 端保障

```properties
# broker.conf

# 1. 同步刷盘（核心消息）
flushDiskType=SYNC_FLUSH

# 2. 同步复制（高可用）
brokerRole=SYNC_MASTER

# 3. 自动创建 Topic（慎用）
autoCreateTopicEnable=false  # 禁用自动创建，避免误操作

# 4. 消息最大大小限制
maxMessageSize=4194304  # 4MB

# 5. 消息保留时间
fileReservedTime=72  # 72小时
```

---

### 6.3 Consumer 端保障

```java
@Service
public class ReliableMessageConsumer {

    @Autowired
    private ConsumedMessageService consumedMessageService;  // 消费记录表

    @Override
    public ConsumeConcurrentlyStatus consumeMessage(
        List<MessageExt> msgs,
        ConsumeConcurrentlyContext context) {

        for (MessageExt msg : msgs) {
            String msgId = msg.getMsgId();

            // 1. 幂等性检查
            if (consumedMessageService.isConsumed(msgId)) {
                log.warn("消息已消费，跳过，msgId={}", msgId);
                continue;
            }

            try {
                // 2. 业务处理
                processMessage(msg);

                // 3. 记录消费成功
                consumedMessageService.save(msgId, ConsumeStatus.SUCCESS);

            } catch (BusinessException e) {
                // 4. 业务异常：不重试
                log.error("业务异常，不重试，msgId={}", msgId, e);
                consumedMessageService.save(msgId, ConsumeStatus.FAILED);
                // 可选：发送到死信队列或告警

            } catch (Exception e) {
                // 5. 系统异常：重试
                log.error("系统异常，稍后重试，msgId={}", msgId, e);
                return ConsumeConcurrentlyStatus.RECONSUME_LATER;
            }
        }

        return ConsumeConcurrentlyStatus.CONSUME_SUCCESS;
    }
}
```

---

## 七、故障案例分析

### 案例1：Broker 宕机导致消息丢失

**故障现象**：
- Broker 突然宕机
- 重启后，最近 5 分钟的消息全部丢失
- 业务方投诉订单未处理

**排查过程**：
```bash
# 1. 查看 Broker 配置
grep flushDiskType /opt/rocketmq/conf/broker.conf
# 输出：flushDiskType=ASYNC_FLUSH  # 异步刷盘

# 2. 查看宕机原因
grep "OutOfMemoryError" /opt/rocketmq/logs/rocketmqlogs/broker.log
# 发现：堆内存溢出导致 Broker 崩溃

# 3. 对比宕机前后消息量
# 宕机前：Broker Offset = 1000000
# 重启后：Broker Offset = 995000
# 丢失：5000 条消息
```

**根因**：
- 异步刷盘 + 内存溢出 → 未刷盘的消息全部丢失

**解决方案**：
```properties
# 1. 核心业务改为同步刷盘
flushDiskType=SYNC_FLUSH

# 2. 增大 JVM 堆内存
-Xms16g -Xmx16g  →  -Xms32g -Xmx32g

# 3. 启用主从同步复制
brokerRole=SYNC_MASTER
```

---

### 案例2：Consumer 自动ACK 丢消息

**故障现象**：
- 订单支付成功消息已发送
- Consumer 日志显示"处理失败"
- 但消息未重试，业务未执行

**排查过程**：
```java
// 查看 Consumer 代码
@Override
public ConsumeConcurrentlyStatus consumeMessage(List<MessageExt> msgs, ConsumeConcurrentlyContext context) {
    for (MessageExt msg : msgs) {
        try {
            orderService.createOrder(msg);
        } catch (Exception e) {
            log.error("处理失败", e);
            // ❌ 问题：吞掉异常，返回 SUCCESS
        }
    }
    return ConsumeConcurrentlyStatus.CONSUME_SUCCESS;  // 消息被确认，无法重试
}
```

**根因**：
- 异常处理不当，消费失败也返回 SUCCESS

**解决方案**：
```java
@Override
public ConsumeConcurrentlyStatus consumeMessage(List<MessageExt> msgs, ConsumeConcurrentlyContext context) {
    for (MessageExt msg : msgs) {
        try {
            orderService.createOrder(msg);
        } catch (Exception e) {
            log.error("处理失败，返回重试", e);
            return ConsumeConcurrentlyStatus.RECONSUME_LATER;  // ✅ 触发重试
        }
    }
    return ConsumeConcurrentlyStatus.CONSUME_SUCCESS;
}
```

---

## 八、总结

### 消息丢失排查清单

**发送端**：
- [ ] 检查发送方式（同步/异步）
- [ ] 检查返回结果处理
- [ ] 检查重试配置
- [ ] 检查网络连接
- [ ] 检查发送超时设置

**存储端**：
- [ ] 检查刷盘策略（同步/异步）
- [ ] 检查主从同步模式
- [ ] 检查磁盘健康状态
- [ ] 检查磁盘空间
- [ ] 验证消息可查询性

**消费端**：
- [ ] 检查ACK机制
- [ ] 检查幂等性处理
- [ ] 检查消费进度
- [ ] 检查死信队列
- [ ] 检查异常处理逻辑

### 可靠性保障三板斧

```
1. 发送端：本地消息表 + 定时补偿
2. 存储端：同步刷盘 + 同步复制
3. 消费端：幂等性 + 失败重试 + 死信队列
```

### 追踪工具

```
1. RocketMQ 自带：消息轨迹（msgTrace）
2. 自定义追踪：traceId + MDC
3. 监控工具：Prometheus + Grafana
4. 日志分析：ELK
```

---

**下一篇预告**：《消息重复处理 - 幂等性设计的最佳实践》，我们将深入讲解如何设计幂等性方案，彻底解决重复消费问题。

**本文关键词**：`消息丢失` `全链路追踪` `故障排查` `可靠性保障`
