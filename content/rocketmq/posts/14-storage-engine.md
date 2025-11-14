---
title: "RocketMQ架构04：存储引擎深度剖析 - 高性能消息存储的奥秘"
date: 2025-11-13T23:00:00+08:00
draft: false
tags: ["RocketMQ", "存储引擎", "CommitLog", "ConsumeQueue", "MMAP"]
categories: ["技术"]
description: "深入剖析 RocketMQ 存储引擎的设计哲学，理解 CommitLog、ConsumeQueue、IndexFile 的巧妙设计"
series: ["RocketMQ从入门到精通"]
weight: 14
stage: 2
stageTitle: "架构原理篇"
---

## 引言：存储引擎的设计哲学

RocketMQ 的存储引擎是其高性能的核心。它用极简的设计实现了：

- **百万级 TPS**：单机支持百万级消息吞吐
- **毫秒级延迟**：消息存储延迟 < 1ms
- **TB 级存储**：单 Broker 可存储数 TB 消息
- **零数据丢失**：通过刷盘策略保证可靠性

今天我们从第一性原理出发，逐步理解这个存储引擎的巧妙设计。

---

## 一、为什么需要这样的存储模型？

### 1.1 传统数据库存储的问题

**方案1：为每个 Queue 建一张表**

```sql
-- TopicA 的 Queue0
CREATE TABLE topic_a_queue_0 (
    offset BIGINT PRIMARY KEY,
    message BLOB,
    store_time TIMESTAMP
);

-- TopicA 的 Queue1
CREATE TABLE topic_a_queue_1 (...);
...
```

**问题**：
```
1. 表数量爆炸：1000个Topic × 4个Queue = 4000张表
2. 随机写入：不同表的写入是随机I/O → 性能差
3. 数据分散：难以统一管理和备份
```

### 1.2 RocketMQ 的解决方案

**核心思想：写入集中化 + 读取索引化**

```
┌─────────────────────────────────────────────────┐
│            RocketMQ 存储模型                      │
├─────────────────────────────────────────────────┤
│                                                  │
│  所有消息 → 统一写入 CommitLog（顺序写）           │
│                      ↓                           │
│           异步构建 ConsumeQueue（索引）            │
│                      ↓                           │
│           Consumer 根据索引快速定位                │
│                                                  │
└─────────────────────────────────────────────────┘
```

**优势**：
1. **顺序写入**：CommitLog 是单文件顺序追加 → 高性能
2. **索引轻量**：ConsumeQueue 只存偏移量 → 占用空间小
3. **统一管理**：所有消息在一个文件中 → 易于备份和恢复

---

## 二、存储引擎三剑客

### 2.1 整体架构

```
┌──────────────────────────────────────────────────────┐
│                   消息存储架构                         │
├──────────────────────────────────────────────────────┤
│                                                       │
│   Producer                                            │
│      │                                                │
│      │ 1. 发送消息                                     │
│      ▼                                                │
│  ┌────────────────────────────────────────────┐      │
│  │          CommitLog（消息主存储）             │      │
│  │  - 所有消息顺序追加                          │      │
│  │  - 每个文件1GB（固定大小）                   │      │
│  │  - 文件名：起始偏移量                        │      │
│  │    00000000000000000000                     │      │
│  │    00000000001073741824                     │      │
│  └────────────────────────────────────────────┘      │
│              │                                        │
│              │ 2. 异步构建索引                         │
│              ▼                                        │
│  ┌────────────────────────────────────────────┐      │
│  │      ConsumeQueue（消费索引）                │      │
│  │  - 按 Topic-Queue 组织                       │      │
│  │  - 存储消息在 CommitLog 的位置               │      │
│  │  - 每条索引20字节                            │      │
│  │    [CommitLog Offset][Size][Tag HashCode]   │      │
│  └────────────────────────────────────────────┘      │
│              │                                        │
│              │ 3. 构建查询索引                         │
│              ▼                                        │
│  ┌────────────────────────────────────────────┐      │
│  │        IndexFile（查询索引）                 │      │
│  │  - 支持按 Key 查询消息                       │      │
│  │  - 支持按时间范围查询                        │      │
│  │  - Hash 索引结构                             │      │
│  └────────────────────────────────────────────┘      │
│              │                                        │
│              │ 4. 读取消息                            │
│              ▼                                        │
│          Consumer                                     │
│                                                       │
└──────────────────────────────────────────────────────┘
```

### 2.2 CommitLog：消息主存储

#### 文件结构

```
$HOME/store/commitlog/
├── 00000000000000000000      # 第1个文件（0-1GB）
├── 00000000001073741824      # 第2个文件（1GB-2GB）
├── 00000000002147483648      # 第3个文件（2GB-3GB）
└── ...

文件名 = 该文件第一条消息的物理偏移量
```

#### 消息存储格式

```
┌────────────────────────────────────────────┐
│         单条消息在 CommitLog 中的格式       │
├────────────────────────────────────────────┤
│ 字段                   大小      说明        │
├────────────────────────────────────────────┤
│ TOTALSIZE             4字节    消息总长度   │
│ MAGICCODE             4字节    魔数         │
│ BODYCRC               4字节    消息体CRC    │
│ QUEUEID               4字节    Queue ID     │
│ FLAG                  4字节    消息标志     │
│ QUEUEOFFSET           8字节    Queue 偏移   │
│ PHYSICALOFFSET        8字节    物理偏移     │
│ SYSFLAG               4字节    系统标志     │
│ BORNTIMESTAMP         8字节    生产时间     │
│ BORNHOST              8字节    生产者地址   │
│ STORETIMESTAMP        8字节    存储时间     │
│ STOREHOSTADDRESS      8字节    Broker地址   │
│ RECONSUMETIMES        4字节    重试次数     │
│ PreparedTransaction   8字节    事务偏移     │
│ BodyLength            4字节    消息体长度   │
│ Body                  变长     消息体       │
│ TopicLength           1字节    Topic长度    │
│ Topic                 变长     Topic名称    │
│ PropertiesLength      2字节    属性长度     │
│ Properties            变长     消息属性     │
└────────────────────────────────────────────┘
```

**示例**：一条消息的二进制表示

```
消息: "Hello RocketMQ"
Topic: "order-topic"
Tags: "create"

在 CommitLog 中存储为：
┌──────┬──────┬──────┬─────────┬──────────┐
│ 156  │magic │ CRC  │ ... ... │   Body   │
│(长度)│(固定)│(校验)│ (元数据) │"Hello..."│
└──────┴──────┴──────┴─────────┴──────────┘
```

### 2.3 ConsumeQueue：消费索引

#### 为什么需要 ConsumeQueue？

**问题**：Consumer 如何高效找到自己需要的消息？

```
方案1：遍历 CommitLog（❌）
- 太慢：需要扫描所有消息
- 无法过滤：无法按 Topic 过滤

方案2：建立索引（✅）
- ConsumeQueue 按 Topic-Queue 组织
- 每条索引只有20字节
- 快速定位到 CommitLog 的位置
```

#### 文件结构

```
$HOME/store/consumequeue/
└── TopicA/                   # Topic 名称
    ├── 0/                    # Queue ID
    │   ├── 00000000000000000000
    │   ├── 00000000000300000000
    │   └── ...
    ├── 1/
    │   └── ...
    └── ...
```

#### 索引格式

```
每条索引：20字节

┌──────────────────────────────────────┐
│   单条索引在 ConsumeQueue 中的格式    │
├──────────────────────────────────────┤
│ CommitLog Offset      8字节          │  ← 消息在 CommitLog 的位置
│ Size                  4字节          │  ← 消息大小
│ Tag HashCode          8字节          │  ← Tag 哈希值（用于过滤）
└──────────────────────────────────────┘
```

**示例**：TopicA Queue0 的索引

```
Index 0: [0000000000, 156, hash(create)]
Index 1: [0000000156, 200, hash(update)]
Index 2: [0000000356, 180, hash(delete)]
...

Consumer 消费流程：
1. 查 ConsumeQueue → 找到 CommitLog Offset
2. 读 CommitLog      → 获取完整消息
```

### 2.4 IndexFile：查询索引

#### 应用场景

```
场景1：根据 Message Key 查询消息
- 订单系统：根据订单号查询消息
- 日志系统：根据请求ID查询日志

场景2：根据时间范围查询消息
- 问题排查：查询某个时间段的消息
- 数据分析：统计某段时间的消息量
```

#### 文件结构

```
$HOME/store/index/
├── 20251113120000000
├── 20251113130000000
└── ...

文件名 = 创建时间戳
```

#### Hash 索引结构

```
┌─────────────────────────────────────────┐
│         IndexFile 文件结构               │
├─────────────────────────────────────────┤
│ Header（40字节）                         │
│  - beginTimestamp（起始时间）            │
│  - endTimestamp（结束时间）              │
│  - indexCount（索引条数）                │
├─────────────────────────────────────────┤
│ Hash 槽（500万个，每个4字节）             │
│  - 存储索引链表的头指针                   │
├─────────────────────────────────────────┤
│ Index 条目（2000万个，每个20字节）        │
│  - keyHash（Key的哈希值）                │
│  - phyOffset（CommitLog 偏移）           │
│  - timeDiff（时间差）                    │
│  - nextIndex（链表下一个索引）            │
└─────────────────────────────────────────┘
```

**查询流程**：

```java
// 根据 Key 查询消息
String messageKey = "ORDER_12345";

// 1. 计算 Hash 槽位置
int slot = Math.abs(messageKey.hashCode()) % 5000000;

// 2. 获取链表头
int indexPos = hashSlot[slot];

// 3. 遍历链表
while (indexPos != 0) {
    IndexEntry entry = readIndexEntry(indexPos);
    if (entry.keyHash == messageKey.hashCode()) {
        // 4. 读取 CommitLog
        return readMessage(entry.phyOffset);
    }
    indexPos = entry.nextIndex;
}
```

---

## 三、消息写入全流程

### 3.1 流程图

```
Producer                     Broker
   │                           │
   │  1. 发送消息               │
   ├──────────────────────────▶│
   │                           │
   │                        ┌──▼────────────────┐
   │                        │ 2. 写入 CommitLog  │
   │                        │  - 顺序追加        │
   │                        │  - 返回物理偏移     │
   │                        └──┬────────────────┘
   │                           │
   │                        ┌──▼────────────────┐
   │                        │ 3. 分发事件        │
   │                        │  - 通知索引构建器   │
   │                        └──┬────────────────┘
   │                           │
   │                     ┌─────┴─────┐
   │                     ▼           ▼
   │            ┌────────────┐  ┌────────────┐
   │            │ 构建        │  │ 构建       │
   │            │ConsumeQueue│  │ IndexFile  │
   │            └────────────┘  └────────────┘
   │                           │
   │  4. 返回成功               │
   ◀───────────────────────────┤
```

### 3.2 代码解析

```java
// 简化的消息写入流程
public class CommitLog {

    // 消息写入主流程
    public PutMessageResult putMessage(MessageExtBrokerInner msg) {
        // 1. 获取当前映射文件
        MappedFile mappedFile = this.mappedFileQueue.getLastMappedFile();

        // 2. 序列化消息
        ByteBuffer msgBuffer = serializeMessage(msg);

        // 3. 写入内存映射文件
        AppendMessageResult result = mappedFile.appendMessage(msgBuffer);

        // 4. 返回结果（物理偏移、消息ID等）
        return new PutMessageResult(
            PutMessageStatus.PUT_OK,
            result
        );
    }

    // 异步构建索引
    class ReputMessageService extends ServiceThread {
        @Override
        public void run() {
            while (!this.isStopped()) {
                // 1. 从 CommitLog 读取消息
                SelectMappedBufferResult result = commitLog.getData(reputFromOffset);

                // 2. 解析消息
                DispatchRequest request = parseMessage(result);

                // 3. 分发给索引构建器
                doDispatch(request);  // → ConsumeQueue, IndexFile
            }
        }
    }
}
```

### 3.3 写入性能优化

#### 1️⃣ **批量写入**

```java
// 生产者端批量发送
List<Message> messages = new ArrayList<>();
messages.add(new Message("TopicA", "Hello1".getBytes()));
messages.add(new Message("TopicA", "Hello2".getBytes()));
...
producer.send(messages);  // 一次网络调用发送多条

// Broker 端批量写入 CommitLog
// → 减少系统调用次数
```

#### 2️⃣ **内存映射文件（MMAP）**

```java
// 传统 I/O（慢）
FileOutputStream fos = new FileOutputStream("commitlog");
fos.write(data);  // 用户态 → 内核态拷贝

// MMAP（快）
MappedByteBuffer buffer = fileChannel.map(
    FileChannel.MapMode.READ_WRITE, 0, fileSize
);
buffer.put(data);  // 直接写入内存映射区域

// 优势：
// - 减少数据拷贝
// - 利用 OS PageCache
// - 支持零拷贝
```

#### 3️⃣ **预分配文件**

```java
// 启动时预分配文件，避免运行时分配
public void warmMappedFile() {
    byte[] bytes = new byte[1024 * 1024];  // 1MB
    for (long i = 0; i < fileSize; i += bytes.length) {
        mappedByteBuffer.put(bytes);
    }
}
```

---

## 四、消息读取全流程

### 4.1 Consumer 拉取消息

```
Consumer                    Broker
   │                          │
   │  1. PULL 请求             │
   │  (Topic, QueueId,        │
   │   Offset, MaxNum)        │
   ├─────────────────────────▶│
   │                          │
   │                       ┌──▼─────────────────┐
   │                       │ 2. 查 ConsumeQueue  │
   │                       │  - 根据 Offset 定位  │
   │                       │  - 获取消息位置列表  │
   │                       └──┬─────────────────┘
   │                          │
   │                       ┌──▼─────────────────┐
   │                       │ 3. 读 CommitLog     │
   │                       │  - 批量读取消息      │
   │                       │  - 过滤 Tag          │
   │                       └──┬─────────────────┘
   │                          │
   │  4. 返回消息              │
   ◀──────────────────────────┤
```

### 4.2 代码解析

```java
public class PullMessageProcessor implements NettyRequestProcessor {

    public RemotingCommand processRequest(ChannelHandlerContext ctx,
                                          RemotingCommand request) {
        // 1. 解析请求
        PullMessageRequestHeader requestHeader = parseHeader(request);

        // 2. 查询 ConsumeQueue
        ConsumeQueue consumeQueue = findConsumeQueue(
            requestHeader.getTopic(),
            requestHeader.getQueueId()
        );

        long offset = requestHeader.getQueueOffset();
        int maxMsgNums = requestHeader.getMaxMsgNums();

        // 3. 从 ConsumeQueue 读取索引
        GetMessageResult result = consumeQueue.getMessage(offset, maxMsgNums);

        // 4. 根据索引从 CommitLog 读取消息
        List<MessageExt> messages = new ArrayList<>();
        for (SelectMappedBufferResult bufferResult : result.getMessageList()) {
            // 解码消息
            MessageExt msg = MessageDecoder.decode(bufferResult.getByteBuffer());

            // 过滤 Tag
            if (messageFilter.isMatchedByConsumeQueue(msg, requestHeader)) {
                messages.add(msg);
            }
        }

        // 5. 返回消息
        return buildResponse(messages);
    }
}
```

### 4.3 读取性能优化

#### 1️⃣ **PageCache 预热**

```java
// 提前加载热点数据到 PageCache
public void warmUpPageCache() {
    // 读取最近的 ConsumeQueue
    for (int i = 0; i < 3; i++) {
        MappedFile file = consumeQueue.getMappedFileQueue().getLastMappedFile(i);
        if (file != null) {
            file.warmMappedFile();  // 预热
        }
    }
}
```

#### 2️⃣ **批量读取**

```java
// 一次读取多条消息
int maxMsgNums = 32;  // 默认一次拉取32条
GetMessageResult result = getMessage(offset, maxMsgNums);

// 优势：减少网络往返次数
```

---

## 五、文件管理与清理

### 5.1 文件生命周期

```
┌────────────────────────────────────────┐
│          文件生命周期                    │
├────────────────────────────────────────┤
│ 1. 创建：预分配1GB空间                   │
│ 2. 写满：切换到新文件                    │
│ 3. 过期：超过保留时间（默认48小时）       │
│ 4. 删除：凌晨4点执行清理任务             │
└────────────────────────────────────────┘
```

### 5.2 清理策略

```properties
# Broker 配置
deleteWhen=04                 # 删除时间：凌晨4点
fileReservedTime=48           # 保留时间：48小时
diskMaxUsedSpaceRatio=75      # 磁盘使用率超过75%强制删除
```

### 5.3 清理流程

```java
class CleanCommitLogService {
    public void run() {
        // 1. 检查是否到达删除时间
        if (isTimeToDelete()) {
            // 2. 遍历所有文件
            for (MappedFile mappedFile : mappedFileQueue.getMappedFiles()) {
                // 3. 检查文件是否过期
                if (isFileExpired(mappedFile)) {
                    // 4. 删除文件
                    mappedFile.destroy();
                }
            }
        }

        // 5. 磁盘使用率检查
        if (getDiskUsage() > 75%) {
            // 强制删除最早的文件
            deleteOldestFile();
        }
    }
}
```

---

## 六、实战：存储引擎监控

### 6.1 关键指标

```bash
# 查看 CommitLog 存储情况
ls -lh $HOME/store/commitlog/

# 查看最大物理偏移量
cat $HOME/store/checkpoint

# 查看 ConsumeQueue 消费进度
cat $HOME/store/consumequeue/{topic}/{queueId}/00000000000000000000
```

### 6.2 监控脚本

```bash
#!/bin/bash
# 存储引擎健康检查

STORE_PATH="$HOME/store"

# 1. 检查 CommitLog 大小
commitlog_size=$(du -sh $STORE_PATH/commitlog | awk '{print $1}')
echo "CommitLog 大小: $commitlog_size"

# 2. 检查文件数量
file_count=$(ls -1 $STORE_PATH/commitlog/ | wc -l)
echo "CommitLog 文件数: $file_count"

# 3. 检查磁盘使用率
disk_usage=$(df -h $STORE_PATH | tail -1 | awk '{print $5}')
echo "磁盘使用率: $disk_usage"

# 4. 检查最新消息时间
latest_time=$(stat -f %Sm $STORE_PATH/commitlog/* | tail -1)
echo "最新消息时间: $latest_time"
```

---

## 七、总结与思考

### 7.1 核心要点

1. **CommitLog**：所有消息顺序写入，单文件1GB
2. **ConsumeQueue**：轻量级索引，按 Topic-Queue 组织
3. **IndexFile**：Hash 索引，支持 Key 和时间范围查询
4. **性能优化**：MMAP、顺序写、PageCache、批量操作
5. **文件管理**：定时清理过期文件，防止磁盘爆满

### 7.2 思考题

1. **为什么 CommitLog 文件大小固定为 1GB？**
   - 提示：考虑内存映射和文件管理

2. **ConsumeQueue 为什么只存20字节索引？**
   - 提示：思考存储空间和读取效率的权衡

3. **如果 PageCache 被清除会怎样？**
   - 提示：考虑读性能的影响

### 7.3 下一步学习

下一篇我们将详细剖析 **CommitLog 的实现细节**，包括：
- 内存映射文件的使用
- 刷盘策略
- 消息序列化格式

---

## 参考资料

- [RocketMQ 存储设计](https://github.com/apache/rocketmq/blob/master/docs/cn/design.md)
- [Linux MMAP 原理](https://man7.org/linux/man-pages/man2/mmap.2.html)
- [PageCache 机制详解](https://www.kernel.org/doc/html/latest/)

---

**本文关键词**：`RocketMQ` `存储引擎` `CommitLog` `ConsumeQueue` `IndexFile` `MMAP`

**专题导航**：[上一篇：Broker架构与核心组件](/blog/rocketmq/posts/13-broker-architecture/) | [下一篇：CommitLog深度剖析](#)
