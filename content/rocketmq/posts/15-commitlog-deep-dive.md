---
title: "RocketMQ架构05：CommitLog深度剖析 - 顺序写的艺术"
date: 2025-11-14T00:00:00+08:00
draft: false
tags: ["RocketMQ", "CommitLog", "MMAP", "零拷贝", "刷盘策略"]
categories: ["技术"]
description: "深入剖析 CommitLog 的实现细节，理解内存映射、刷盘策略、文件预热等核心技术"
series: ["RocketMQ从入门到精通"]
weight: 15
stage: 2
stageTitle: "架构原理篇"
---

## 引言：顺序写的魔力

CommitLog 是 RocketMQ 高性能的核心秘密。它用**顺序写**实现了：

- **单机 10 万+ TPS**：远超数据库的随机写
- **亚毫秒级延迟**：消息写入延迟 < 1ms
- **零拷贝读取**：MMAP 直接访问磁盘文件

今天我们从源码级别剖析 CommitLog 的实现细节。

---

## 一、为什么顺序写这么快？

### 1.1 随机写 vs 顺序写

```
┌──────────────────────────────────────────┐
│         磁盘写入性能对比                   │
├──────────────────────────────────────────┤
│                                           │
│  随机写（数据库）:                         │
│  ┌───┐    ┌───┐    ┌───┐                 │
│  │ A │ →  │ C │ →  │ B │                 │
│  └───┘    └───┘    └───┘                 │
│  磁盘块100  磁盘块500  磁盘块200            │
│                                           │
│  问题：                                    │
│  - 磁头需要频繁移动                        │
│  - IOPS 约 100-200/s                      │
│                                           │
├──────────────────────────────────────────┤
│                                           │
│  顺序写（RocketMQ）:                       │
│  ┌───┬───┬───┬───┬───┐                   │
│  │ A │ B │ C │ D │ E │ ...               │
│  └───┴───┴───┴───┴───┘                   │
│  CommitLog 文件                            │
│                                           │
│  优势：                                    │
│  - 磁头连续移动                            │
│  - 吞吐量 约 600MB/s（机械硬盘）           │
│  - 吞吐量 约 2GB/s（SSD）                  │
│                                           │
└──────────────────────────────────────────┘
```

**性能差距**：
```
随机写：100-200 IOPS
顺序写：10,000+ IOPS（提升 50-100 倍）
```

### 1.2 操作系统层面的优化

```
┌────────────────────────────────────────┐
│      OS 对顺序写的优化                  │
├────────────────────────────────────────┤
│ 1. PageCache 写合并                     │
│    - 多次小写合并为一次大写             │
│                                         │
│ 2. 预读（Read-ahead）                   │
│    - 检测到顺序写，预加载后续块         │
│                                         │
│ 3. I/O 调度器优化                       │
│    - 将顺序 I/O 请求优先处理            │
└────────────────────────────────────────┘
```

---

## 二、CommitLog 文件结构

### 2.1 文件命名与布局

```bash
$HOME/store/commitlog/
├── 00000000000000000000      # 文件1：0 ~ 1GB
├── 00000000001073741824      # 文件2：1GB ~ 2GB
├── 00000000002147483648      # 文件3：2GB ~ 3GB
└── ...

文件名 = 该文件第一条消息的物理偏移量（全局唯一）

文件大小：固定 1GB (1024 * 1024 * 1024 字节)
```

**为什么固定 1GB？**
```
1. 内存映射友好：1GB 适合 MMAP 映射
2. 文件管理简单：定长文件易于定位和管理
3. 删除粒度合适：不会太大也不会太小
```

### 2.2 消息在文件中的存储格式

```
┌─────────────────────────────────────────────┐
│        单条消息的完整存储格式                 │
├─────────────────────────────────────────────┤
│                                              │
│  消息头（固定部分）                           │
│  ┌────────────────────────────────┐         │
│  │ TOTALSIZE        (4字节)        │ 总长度  │
│  │ MAGICCODE        (4字节)        │ 魔数    │
│  │ BODYCRC          (4字节)        │ 校验和  │
│  │ QUEUEID          (4字节)        │ Queue   │
│  │ FLAG             (4字节)        │ 标志位  │
│  │ QUEUEOFFSET      (8字节)        │ Queue偏移│
│  │ PHYSICALOFFSET   (8字节)        │ 物理偏移│
│  │ SYSFLAG          (4字节)        │ 系统标志│
│  │ BORNTIMESTAMP    (8字节)        │ 生产时间│
│  │ BORNHOST         (8字节)        │ 生产者  │
│  │ STORETIMESTAMP   (8字节)        │ 存储时间│
│  │ STOREHOSTADDRESS (8字节)        │ Broker  │
│  │ RECONSUMETIMES   (4字节)        │ 重试次数│
│  │ PreparedTransaction (8字节)     │ 事务    │
│  └────────────────────────────────┘         │
│                                              │
│  消息体（变长部分）                           │
│  ┌────────────────────────────────┐         │
│  │ BodyLength       (4字节)        │         │
│  │ Body             (变长)         │ 消息内容│
│  └────────────────────────────────┘         │
│                                              │
│  Topic（变长）                               │
│  ┌────────────────────────────────┐         │
│  │ TopicLength      (1字节)        │         │
│  │ Topic            (变长)         │ Topic名 │
│  └────────────────────────────────┘         │
│                                              │
│  属性（变长）                                │
│  ┌────────────────────────────────┐         │
│  │ PropertiesLength (2字节)        │         │
│  │ Properties       (变长)         │ 扩展属性│
│  └────────────────────────────────┘         │
│                                              │
└─────────────────────────────────────────────┘

总大小 = 固定头(80字节) + Body + Topic + Properties
```

**实际示例**：

```
消息：
  Topic: "order-topic"
  Tags:  "create"
  Body:  "OrderId=12345"

存储格式（十六进制）：
00 00 00 9C          // TOTALSIZE = 156字节
DA AA 00 10          // MAGICCODE
12 34 56 78          // CRC
00 00 00 00          // QueueId = 0
00 00 00 00          // FLAG
... (其他字段)
00 00 00 0D          // BodyLength = 13
4F 72 64 65 72 ...   // Body = "OrderId=12345"
0B                   // TopicLength = 11
6F 72 64 65 72 ...   // Topic = "order-topic"
00 0C                // PropertiesLength = 12
54 41 47 53 ...      // Properties = "TAGS=create"
```

---

## 三、内存映射文件（MMAP）

### 3.1 什么是 MMAP？

```
┌────────────────────────────────────────────┐
│         传统 I/O（慢）                      │
├────────────────────────────────────────────┤
│                                             │
│  用户程序                                    │
│     ↓ write()                              │
│  用户缓冲区                                  │
│     ↓ 拷贝                                  │
│  内核缓冲区（PageCache）                     │
│     ↓ 刷盘                                  │
│  磁盘文件                                    │
│                                             │
│  问题：数据拷贝 2 次，用户态/内核态切换      │
└────────────────────────────────────────────┘

┌────────────────────────────────────────────┐
│         MMAP（快）                          │
├────────────────────────────────────────────┤
│                                             │
│  用户程序                                    │
│     ↓ 直接访问                              │
│  PageCache（内存映射区域）                   │
│     ↓ 刷盘                                  │
│  磁盘文件                                    │
│                                             │
│  优势：零拷贝，减少上下文切换                │
└────────────────────────────────────────────┘
```

### 3.2 RocketMQ 中的 MMAP 实现

```java
public class MappedFile {
    // 内存映射文件
    private MappedByteBuffer mappedByteBuffer;
    private FileChannel fileChannel;

    // 构造时创建 MMAP
    public MappedFile(String fileName, int fileSize) {
        File file = new File(fileName);
        this.fileChannel = new RandomAccessFile(file, "rw").getChannel();

        // 内存映射整个文件
        this.mappedByteBuffer = fileChannel.map(
            FileChannel.MapMode.READ_WRITE,  // 可读可写
            0,                                // 起始位置
            fileSize                          // 映射大小（1GB）
        );
    }

    // 追加消息（顺序写）
    public AppendMessageResult appendMessage(ByteBuffer msgBuffer) {
        // 获取当前写位置
        int currentPos = this.wrotePosition.get();

        // 直接写入映射内存
        this.mappedByteBuffer.position(currentPos);
        this.mappedByteBuffer.put(msgBuffer);

        // 更新写位置
        this.wrotePosition.addAndGet(msgBuffer.remaining());

        return new AppendMessageResult(AppendMessageStatus.PUT_OK);
    }

    // 读取消息（零拷贝）
    public SelectMappedBufferResult selectMappedBuffer(int pos, int size) {
        // 创建共享的 ByteBuffer（零拷贝）
        ByteBuffer byteBuffer = this.mappedByteBuffer.slice();
        byteBuffer.position(pos);
        ByteBuffer byteBufferNew = byteBuffer.slice();
        byteBufferNew.limit(size);

        return new SelectMappedBufferResult(byteBufferNew);
    }
}
```

### 3.3 MMAP 的优势与限制

**优势**：
```
1. 零拷贝：减少数据拷贝次数
2. 高性能：利用 OS 的 PageCache
3. 简化代码：像操作内存一样操作文件
```

**限制**：
```
1. 32位系统限制：最大映射 2GB（RocketMQ 要求64位系统）
2. 内存占用：映射大文件会占用虚拟内存地址空间
3. 刷盘时机：需要显式调用 force() 刷盘
```

---

## 四、刷盘策略

### 4.1 同步刷盘 vs 异步刷盘

```
┌──────────────────────────────────────────┐
│          同步刷盘（SYNC_FLUSH）           │
├──────────────────────────────────────────┤
│ Producer                  Broker         │
│    │                        │            │
│    │ 1. 发送消息             │            │
│    ├───────────────────────▶│            │
│    │                        │ 2. 写入内存 │
│    │                        │ 3. 刷盘     │
│    │                        │ (fsync)     │
│    │                        │ 4. 确认     │
│    │ 5. 返回成功             │            │
│    ◀────────────────────────┤            │
│                                           │
│ 优势：可靠性高（数据已持久化）             │
│ 劣势：性能低（每条消息都刷盘）             │
└──────────────────────────────────────────┘

┌──────────────────────────────────────────┐
│          异步刷盘（ASYNC_FLUSH）          │
├──────────────────────────────────────────┤
│ Producer                  Broker         │
│    │                        │            │
│    │ 1. 发送消息             │            │
│    ├───────────────────────▶│            │
│    │                        │ 2. 写入内存 │
│    │ 3. 返回成功             │ (PageCache) │
│    ◀────────────────────────┤            │
│    │                        │            │
│    │                        │ 后台线程    │
│    │                        │ 定期刷盘    │
│    │                        │ (500ms)     │
│                                           │
│ 优势：性能高（批量刷盘）                  │
│ 劣势：可靠性低（宕机可能丢失500ms数据）   │
└──────────────────────────────────────────┘
```

### 4.2 异步刷盘实现

```java
class FlushRealTimeService extends ServiceThread {
    // 刷盘间隔
    private static final int FLUSH_INTERVAL_MS = 500;

    @Override
    public void run() {
        while (!this.isStopped()) {
            try {
                // 等待刷盘信号或超时
                this.waitForRunning(FLUSH_INTERVAL_MS);

                // 执行刷盘
                long beginTime = System.currentTimeMillis();
                CommitLog.this.mappedFileQueue.flush(0);

                long storeTimestamp = CommitLog.this.mappedFileQueue.getStoreTimestamp();
                if (storeTimestamp > 0) {
                    // 更新 checkpoint
                    StoreCheckpoint.flush(storeTimestamp);
                }

                long eclipseTime = System.currentTimeMillis() - beginTime;
                if (eclipseTime > 500) {
                    log.warn("Flush data to disk costs {} ms", eclipseTime);
                }
            } catch (Exception e) {
                log.error("Flush service exception", e);
            }
        }
    }
}

// 刷盘操作
public boolean flush(int flushLeastPages) {
    boolean result = true;
    MappedFile mappedFile = findMappedFileByOffset(this.flushedWhere);

    if (mappedFile != null) {
        long storeTimestamp = mappedFile.getStoreTimestamp();
        // 调用 MMAP 的 force() 方法
        int offset = mappedFile.flush(flushLeastPages);

        this.flushedWhere = mappedFile.getFileFromOffset() + offset;
        result = true;
    }

    return result;
}
```

### 4.3 配置选择

```properties
# broker.conf

# 刷盘策略
flushDiskType=ASYNC_FLUSH      # 异步刷盘（默认，推荐）
# flushDiskType=SYNC_FLUSH     # 同步刷盘（高可靠场景）

# 异步刷盘参数
flushIntervalCommitLog=500     # 刷盘间隔（毫秒）
flushCommitLogLeastPages=4     # 至少累积多少页才刷盘
```

**性能对比**：

| 刷盘策略 | TPS | 延迟 | 适用场景 |
|---------|-----|------|---------|
| 同步刷盘 | ~5000 | 10-50ms | 金融、支付 |
| 异步刷盘 | ~100000 | <1ms | 日志、监控、一般业务 |

---

## 五、文件预热（Warm Up）

### 5.1 为什么需要预热？

```
问题：新创建的文件首次访问很慢

原因：
1. 缺页中断：首次访问触发 Page Fault
2. 文件空洞：稀疏文件需要分配实际磁盘块
3. TLB Miss：地址转换缓存未命中
```

### 5.2 预热策略

```java
public class MappedFile {

    // 文件预热
    public void warmMappedFile(FlushDiskType type, int pages) {
        ByteBuffer byteBuffer = this.mappedByteBuffer.slice();

        int flush = 0;
        long beginTime = System.currentTimeMillis();

        // 按页访问文件（每页 4KB）
        for (int i = 0, j = 0; i < fileSize; i += OS_PAGE_SIZE, j++) {
            byteBuffer.put(i, (byte) 0);

            // 每写入一定页数，刷盘一次
            if (type == FlushDiskType.SYNC_FLUSH) {
                if ((i / OS_PAGE_SIZE) - (flush / OS_PAGE_SIZE) >= pages) {
                    flush = i;
                    mappedByteBuffer.force();
                }
            }

            // 防止影响其他操作
            if (j % 1000 == 0) {
                Thread.sleep(0);  // 让出CPU
            }
        }

        // 最后刷盘
        if (type == FlushDiskType.SYNC_FLUSH) {
            mappedByteBuffer.force();
        }

        // mlock：锁定内存，防止被swap
        if (isWarmMapedFileEnable()) {
            mlock();
        }

        long eclipseTime = System.currentTimeMillis() - beginTime;
        log.info("Warm up file {} costs {} ms", fileName, eclipseTime);
    }

    // 锁定内存（防止被交换到磁盘）
    public void mlock() {
        final long address = ((DirectBuffer) mappedByteBuffer).address();
        Pointer pointer = new Pointer(address);

        // 调用系统 mlock
        int ret = LibC.INSTANCE.mlock(pointer, new NativeLong(fileSize));

        if (ret != 0) {
            log.warn("mlock {} failed", fileName);
        }
    }
}
```

**预热效果**：

```
不预热：首次写入 50-100ms
预热后：首次写入 <1ms（提升50-100倍）
```

---

## 六、消息写入全流程源码解析

### 6.1 完整写入流程

```java
public class CommitLog {

    // 消息写入主入口
    public PutMessageResult putMessage(MessageExtBrokerInner msg) {
        // 1. 设置存储时间
        msg.setStoreTimestamp(System.currentTimeMillis());

        // 2. 计算消息 CRC
        msg.setBodyCRC(UtilAll.crc32(msg.getBody()));

        // 3. 获取当前 MappedFile
        MappedFile mappedFile = this.mappedFileQueue.getLastMappedFile();

        if (mappedFile == null || mappedFile.isFull()) {
            // 创建新文件
            mappedFile = this.mappedFileQueue.getLastMappedFile(0);
        }

        // 4. 追加消息到文件
        AppendMessageResult result = mappedFile.appendMessage(
            msg,
            this.appendMessageCallback
        );

        switch (result.getStatus()) {
            case PUT_OK:
                break;
            case END_OF_FILE:
                // 文件写满，重新获取
                mappedFile = this.mappedFileQueue.getLastMappedFile(0);
                result = mappedFile.appendMessage(msg, this.appendMessageCallback);
                break;
            case MESSAGE_SIZE_EXCEEDED:
            case PROPERTIES_SIZE_EXCEEDED:
                return new PutMessageResult(PutMessageStatus.MESSAGE_ILLEGAL, result);
            default:
                return new PutMessageResult(PutMessageStatus.UNKNOWN_ERROR, result);
        }

        // 5. 处理刷盘
        handleDiskFlush(result, msg);

        // 6. 处理主从同步
        handleHA(result, msg);

        return new PutMessageResult(PutMessageStatus.PUT_OK, result);
    }

    // 刷盘处理
    private void handleDiskFlush(AppendMessageResult result, MessageExt msg) {
        if (FlushDiskType.SYNC_FLUSH == this.defaultMessageStore.getFlushDiskType()) {
            // 同步刷盘
            final GroupCommitService service = this.groupCommitService;
            if (msg.isWaitStoreMsgOK()) {
                GroupCommitRequest request = new GroupCommitRequest(
                    result.getWroteOffset() + result.getWroteBytes()
                );
                service.putRequest(request);
                // 等待刷盘完成
                boolean flushOK = request.waitForFlush(
                    this.defaultMessageStore.getSyncFlushTimeout()
                );
                if (!flushOK) {
                    log.error("Sync flush timeout");
                }
            } else {
                service.wakeup();
            }
        } else {
            // 异步刷盘
            this.flushCommitLogService.wakeup();
        }
    }
}
```

### 6.2 消息序列化

```java
class DefaultAppendMessageCallback implements AppendMessageCallback {

    @Override
    public AppendMessageResult doAppend(
        final long fileFromOffset,
        final ByteBuffer byteBuffer,
        final int maxBlank,
        final MessageExtBrokerInner msgInner
    ) {
        // 当前文件写位置
        long wroteOffset = fileFromOffset + byteBuffer.position();

        // 计算各部分长度
        final byte[] topicData = msgInner.getTopic().getBytes();
        final int topicLength = topicData.length;

        final byte[] propertiesData = msgInner.getPropertiesString().getBytes();
        final int propertiesLength = propertiesData.length;

        final int msgLen = calMsgLength(
            msgInner.getBody().length,
            topicLength,
            propertiesLength
        );

        // 检查是否超出文件大小
        if ((byteBuffer.position() + msgLen) > maxBlank) {
            // 文件剩余空间不足，填充魔数
            byteBuffer.putInt(maxBlank);
            byteBuffer.putInt(BLANK_MAGIC_CODE);
            return new AppendMessageResult(AppendMessageStatus.END_OF_FILE);
        }

        // 开始序列化
        // 1. TOTALSIZE
        byteBuffer.putInt(msgLen);

        // 2. MAGICCODE
        byteBuffer.putInt(MESSAGE_MAGIC_CODE);

        // 3. BODYCRC
        byteBuffer.putInt(msgInner.getBodyCRC());

        // 4. QUEUEID
        byteBuffer.putInt(msgInner.getQueueId());

        // 5. FLAG
        byteBuffer.putInt(msgInner.getFlag());

        // 6. QUEUEOFFSET
        byteBuffer.putLong(queueOffset);

        // 7. PHYSICALOFFSET
        byteBuffer.putLong(wroteOffset);

        // 8. SYSFLAG
        byteBuffer.putInt(msgInner.getSysFlag());

        // 9. BORNTIMESTAMP
        byteBuffer.putLong(msgInner.getBornTimestamp());

        // 10. BORNHOST
        byteBuffer.put(msgInner.getBornHostBytes());

        // 11. STORETIMESTAMP
        byteBuffer.putLong(msgInner.getStoreTimestamp());

        // 12. STOREHOSTADDRESS
        byteBuffer.put(msgInner.getStoreHostBytes());

        // 13. RECONSUMETIMES
        byteBuffer.putInt(msgInner.getReconsumeTimes());

        // 14. Prepared Transaction Offset
        byteBuffer.putLong(msgInner.getPreparedTransactionOffset());

        // 15. BODY
        byteBuffer.putInt(msgInner.getBody().length);
        byteBuffer.put(msgInner.getBody());

        // 16. TOPIC
        byteBuffer.put((byte) topicLength);
        byteBuffer.put(topicData);

        // 17. PROPERTIES
        byteBuffer.putShort((short) propertiesLength);
        byteBuffer.put(propertiesData);

        return new AppendMessageResult(
            AppendMessageStatus.PUT_OK,
            wroteOffset,
            msgLen,
            msgInner.getMsgId()
        );
    }
}
```

---

## 七、性能优化技巧

### 7.1 批量发送

```java
// 生产者批量发送
List<Message> messages = new ArrayList<>();
for (int i = 0; i < 100; i++) {
    messages.add(new Message("TopicA", ("Msg" + i).getBytes()));
}

// 一次网络调用发送100条
SendResult result = producer.send(messages);

// 性能提升：
// - 减少网络往返次数
// - 一次写入多条消息到 CommitLog
```

### 7.2 异步发送

```java
// 异步发送（不阻塞）
producer.send(message, new SendCallback() {
    @Override
    public void onSuccess(SendResult sendResult) {
        // 发送成功回调
    }

    @Override
    public void onException(Throwable e) {
        // 发送失败回调
    }
});

// 业务线程继续执行，不等待发送结果
// 性能提升：提高吞吐量
```

### 7.3 TransientStorePool（堆外内存池）

```java
// 启用堆外内存池（进一步优化性能）
# broker.conf
transientStorePoolEnable=true
transientStorePoolSize=5      # 池大小

// 原理：
// 1. 消息先写入堆外内存（DirectByteBuffer）
// 2. 后台线程批量提交到 PageCache
// 3. 再由 OS 刷盘

// 优势：
// - 减少锁竞争
// - 批量提交减少系统调用
```

---

## 八、监控与排查

### 8.1 关键指标

```bash
# 查看 CommitLog 写位置
cat /tmp/rocketmq/store/commitlog/00000000000000000000

# 查看刷盘位置
cat /tmp/rocketmq/store/checkpoint

# 监控刷盘延迟
tail -f logs/rocketmqlogs/broker.log | grep "flush"
```

### 8.2 常见问题排查

**问题1：消息写入慢**

```bash
# 检查磁盘 I/O
iostat -x 1

# 检查是否开启同步刷盘
grep flushDiskType conf/broker.conf

# 解决方案：
# 1. 改为异步刷盘（如果业务允许）
# 2. 使用 SSD
# 3. 启用 TransientStorePool
```

**问题2：内存占用高**

```bash
# 检查 MMAP 映射大小
cat /proc/$(pgrep -f BrokerStartup)/maps | grep commitlog

# 解决方案：
# 1. 调整文件保留时间
# 2. 及时删除过期文件
```

---

## 九、总结与思考

### 9.1 核心要点

1. **顺序写**：CommitLog 顺序追加，性能提升50-100倍
2. **MMAP**：内存映射文件，零拷贝读写
3. **刷盘策略**：同步/异步刷盘，性能与可靠性权衡
4. **文件预热**：消除首次访问延迟
5. **批量优化**：批量发送、批量刷盘

### 9.2 思考题

1. **为什么 RocketMQ 不使用数据库存储消息？**
   - 提示：顺序写 vs 随机写

2. **MMAP 适合所有场景吗？**
   - 提示：考虑文件大小和访问模式

3. **如何平衡性能和可靠性？**
   - 提示：刷盘策略 + 主从同步

### 9.3 下一步学习

下一篇我们将剖析 **ConsumeQueue 和 IndexFile**，理解索引机制如何加速消息检索。

---

## 参考资料

- [RocketMQ 存储设计文档](https://github.com/apache/rocketmq/blob/master/docs/cn/design.md)
- [Linux MMAP 详解](https://man7.org/linux/man-pages/man2/mmap.2.html)
- [零拷贝技术](https://www.ibm.com/docs/en/linux-on-systems)

---

**本文关键词**：`CommitLog` `顺序写` `MMAP` `刷盘策略` `文件预热`

**专题导航**：[上一篇：存储引擎深度剖析](/blog/rocketmq/posts/14-storage-engine/) | [下一篇：索引机制详解](#)
