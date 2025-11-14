---
title: "RocketMQ架构07：网络通信模型与Remoting模块 - 基于Netty的高性能通信"
date: 2025-11-14T02:00:00+08:00
draft: false
tags: ["RocketMQ", "Remoting", "Netty", "网络通信", "请求处理器"]
categories: ["技术"]
description: "深入剖析 RocketMQ 的网络通信模型，理解 Remoting 模块如何基于 Netty 实现高性能通信"
series: ["RocketMQ从入门到精通"]
weight: 17
stage: 2
stageTitle: "架构原理篇"
---

## 引言：高性能通信的基石

RocketMQ 的网络通信模块（Remoting）是整个系统的神经网络，负责：

- **Producer → Broker**：发送消息
- **Consumer → Broker**：拉取消息
- **Broker → NameServer**：注册与心跳
- **Broker → Broker**：主从同步

今天我们深入剖析这个基于 Netty 的高性能通信模块。

---

## 一、Remoting 模块架构

### 1.1 整体架构

```
┌────────────────────────────────────────────────┐
│           Remoting 模块架构                     │
├────────────────────────────────────────────────┤
│                                                 │
│  ┌──────────────────────────────────────────┐  │
│  │         RemotingServer (服务端)          │  │
│  │  - NettyRemotingServer                   │  │
│  │  - 接收客户端请求                         │  │
│  └──────────────────────────────────────────┘  │
│                    ↕                            │
│  ┌──────────────────────────────────────────┐  │
│  │         RemotingClient (客户端)          │  │
│  │  - NettyRemotingClient                   │  │
│  │  - 发送请求到服务端                       │  │
│  └──────────────────────────────────────────┘  │
│                    ↕                            │
│  ┌──────────────────────────────────────────┐  │
│  │         Netty 网络层                      │  │
│  │  - EventLoopGroup                        │  │
│  │  - Channel Pipeline                      │  │
│  │  - 编解码器                               │  │
│  └──────────────────────────────────────────┘  │
│                                                 │
└────────────────────────────────────────────────┘
```

### 1.2 核心组件

```java
// 1. RemotingCommand - 通信协议对象
public class RemotingCommand {
    private int code;              // 请求/响应码
    private LanguageCode language; // 语言
    private int version;           // 版本
    private int opaque;            // 请求ID
    private int flag;              // 标志位
    private String remark;         // 备注
    private HashMap<String, String> extFields;  // 扩展字段
    private transient byte[] body; // 消息体
}

// 2. NettyRequestProcessor - 请求处理器
public interface NettyRequestProcessor {
    RemotingCommand processRequest(
        ChannelHandlerContext ctx,
        RemotingCommand request
    ) throws Exception;
}

// 3. ResponseFuture - 异步响应
public class ResponseFuture {
    private final int opaque;
    private final long timeoutMillis;
    private final InvokeCallback invokeCallback;
    private final CountDownLatch countDownLatch;
    private volatile RemotingCommand responseCommand;
}
```

---

## 二、请求类型与调用方式

### 2.1 三种调用方式

```
┌─────────────────────────────────────────────┐
│          三种调用方式对比                    │
├─────────────────────────────────────────────┤
│                                              │
│  1. 同步调用 (Sync)                          │
│  Client                    Server            │
│    │                         │               │
│    │ ──── Request ─────────▶ │               │
│    │ (阻塞等待)              │ Process       │
│    │                         │               │
│    │ ◀─── Response ──────── │               │
│    │                         │               │
│  特点：等待响应，吞吐量低                    │
│                                              │
├─────────────────────────────────────────────┤
│                                              │
│  2. 异步调用 (Async)                         │
│  Client                    Server            │
│    │                         │               │
│    │ ──── Request ─────────▶ │               │
│    │ (立即返回)              │ Process       │
│    │                         │               │
│    │ ◀─── Response ──────── │               │
│    │ (回调处理)              │               │
│                                              │
│  特点：非阻塞，吞吐量高                      │
│                                              │
├─────────────────────────────────────────────┤
│                                              │
│  3. 单向调用 (Oneway)                        │
│  Client                    Server            │
│    │                         │               │
│    │ ──── Request ─────────▶ │               │
│    │ (不等响应)              │ Process       │
│    │                         │               │
│                                              │
│  特点：无响应，最高吞吐量                    │
│                                              │
└─────────────────────────────────────────────┘
```

### 2.2 代码示例

```java
// 1. 同步调用
public RemotingCommand invokeSyncImpl(
    final Channel channel,
    final RemotingCommand request,
    final long timeoutMillis
) throws InterruptedException, RemotingSendRequestException, RemotingTimeoutException {

    final int opaque = request.getOpaque();

    try {
        // 创建 ResponseFuture
        final ResponseFuture responseFuture = new ResponseFuture(
            channel, opaque, timeoutMillis, null, null
        );
        this.responseTable.put(opaque, responseFuture);

        // 发送请求
        channel.writeAndFlush(request).addListener(new ChannelFutureListener() {
            @Override
            public void operationComplete(ChannelFuture f) throws Exception {
                if (f.isSuccess()) {
                    responseFuture.setSendRequestOK(true);
                    return;
                }
                responseFuture.setSendRequestOK(false);
                responseFuture.putResponse(null);
            }
        });

        // 阻塞等待响应
        RemotingCommand responseCommand = responseFuture.waitResponse(timeoutMillis);
        if (null == responseCommand) {
            if (responseFuture.isSendRequestOK()) {
                throw new RemotingTimeoutException();
            } else {
                throw new RemotingSendRequestException();
            }
        }

        return responseCommand;
    } finally {
        this.responseTable.remove(opaque);
    }
}

// 2. 异步调用
public void invokeAsyncImpl(
    final Channel channel,
    final RemotingCommand request,
    final long timeoutMillis,
    final InvokeCallback invokeCallback
) throws InterruptedException, RemotingTooMuchRequestException, RemotingSendRequestException {

    final int opaque = request.getOpaque();

    // 创建 ResponseFuture（带回调）
    final ResponseFuture responseFuture = new ResponseFuture(
        channel, opaque, timeoutMillis, invokeCallback, null
    );
    this.responseTable.put(opaque, responseFuture);

    // 发送请求
    channel.writeAndFlush(request).addListener(new ChannelFutureListener() {
        @Override
        public void operationComplete(ChannelFuture f) throws Exception {
            if (f.isSuccess()) {
                responseFuture.setSendRequestOK(true);
                return;
            }
            // 失败立即回调
            responseFuture.setSendRequestOK(false);
            responseFuture.putResponse(null);
            responseTable.remove(opaque);
            responseFuture.executeInvokeCallback();
        }
    });
}

// 3. 单向调用
public void invokeOnewayImpl(
    final Channel channel,
    final RemotingCommand request,
    final long timeoutMillis
) throws InterruptedException, RemotingTooMuchRequestException, RemotingSendRequestException {

    // 设置单向标志
    request.markOnewayRPC();

    // 直接发送，不等响应
    channel.writeAndFlush(request).addListener(new ChannelFutureListener() {
        @Override
        public void operationComplete(ChannelFuture f) throws Exception {
            if (!f.isSuccess()) {
                log.warn("send request failed. channel={}", channel);
            }
        }
    });
}
```

---

## 三、请求码与处理器映射

### 3.1 常见请求码

```java
public class RequestCode {
    // Producer 相关
    public static final int SEND_MESSAGE = 10;
    public static final int SEND_MESSAGE_V2 = 310;
    public static final int SEND_BATCH_MESSAGE = 320;

    // Consumer 相关
    public static final int PULL_MESSAGE = 11;
    public static final int QUERY_MESSAGE = 12;
    public static final int QUERY_MESSAGE_BY_KEY = 13;

    // Broker 相关
    public static final int REGISTER_BROKER = 103;
    public static final int UNREGISTER_BROKER = 104;
    public static final int HEART_BEAT = 34;

    // 管理相关
    public static final int GET_ALL_TOPIC_CONFIG = 21;
    public static final int UPDATE_BROKER_CONFIG = 25;
}
```

### 3.2 处理器注册

```java
public class BrokerController {

    public void registerProcessor() {
        // 1. 发送消息处理器
        SendMessageProcessor sendProcessor = new SendMessageProcessor(this);
        this.remotingServer.registerProcessor(
            RequestCode.SEND_MESSAGE,
            sendProcessor,
            this.sendMessageExecutor
        );

        // 2. 拉取消息处理器
        PullMessageProcessor pullProcessor = new PullMessageProcessor(this);
        this.remotingServer.registerProcessor(
            RequestCode.PULL_MESSAGE,
            pullProcessor,
            this.pullMessageExecutor
        );

        // 3. 查询消息处理器
        QueryMessageProcessor queryProcessor = new QueryMessageProcessor(this);
        this.remotingServer.registerProcessor(
            RequestCode.QUERY_MESSAGE,
            queryProcessor,
            this.queryMessageExecutor
        );

        // 4. 心跳处理器
        ClientManageProcessor clientManageProcessor = new ClientManageProcessor(this);
        this.remotingServer.registerProcessor(
            RequestCode.HEART_BEAT,
            clientManageProcessor,
            this.heartbeatExecutor
        );

        // 5. 默认处理器
        AdminBrokerProcessor adminProcessor = new AdminBrokerProcessor(this);
        this.remotingServer.registerDefaultProcessor(
            adminProcessor,
            this.adminBrokerExecutor
        );
    }
}
```

---

## 四、编解码协议

### 4.1 协议格式

```
┌─────────────────────────────────────────────┐
│         RocketMQ 通信协议格式                │
├─────────────────────────────────────────────┤
│                                              │
│  消息总长度（4字节）                         │
│  ┌──────────────────────────────┐           │
│  │ Total Length                 │           │
│  └──────────────────────────────┘           │
│                                              │
│  序列化类型 + 头部长度（4字节）              │
│  ┌──────────────────────────────┐           │
│  │ [1字节]  [3字节]             │           │
│  │ SerType  Header Length       │           │
│  └──────────────────────────────┘           │
│                                              │
│  头部数据（变长）                            │
│  ┌──────────────────────────────┐           │
│  │ Header Data                  │           │
│  │ (JSON 或 RocketMQ 私有格式)  │           │
│  └──────────────────────────────┘           │
│                                              │
│  消息体（变长）                              │
│  ┌──────────────────────────────┐           │
│  │ Body Data                    │           │
│  └──────────────────────────────┘           │
│                                              │
└─────────────────────────────────────────────┘
```

### 4.2 编码器实现

```java
public class NettyEncoder extends MessageToByteEncoder<RemotingCommand> {

    @Override
    public void encode(ChannelHandlerContext ctx, RemotingCommand remotingCommand, ByteBuf out)
        throws Exception {
        try {
            ByteBuffer header = remotingCommand.encodeHeader();
            out.writeBytes(header);

            byte[] body = remotingCommand.getBody();
            if (body != null) {
                out.writeBytes(body);
            }
        } catch (Exception e) {
            log.error("encode exception, " + RemotingHelper.parseChannelRemoteAddr(ctx.channel()), e);
            if (remotingCommand != null) {
                log.error(remotingCommand.toString());
            }
            RemotingUtil.closeChannel(ctx.channel());
        }
    }
}

// RemotingCommand 编码
public ByteBuffer encodeHeader() {
    return encodeHeader(this.body != null ? this.body.length : 0);
}

public ByteBuffer encodeHeader(final int bodyLength) {
    // 1. 计算总长度
    int length = 4; // 总长度字段本身

    // 2. 序列化头部
    byte[] headerData;
    headerData = this.headerEncode();

    length += headerData.length;
    length += bodyLength;

    // 3. 分配缓冲区
    ByteBuffer result = ByteBuffer.allocate(4 + length - bodyLength);

    // 4. 写入总长度
    result.putInt(length);

    // 5. 写入序列化类型 + 头部长度
    result.put(markProtocolType(headerData.length, SerializeType.JSON));

    // 6. 写入头部数据
    result.put(headerData);

    result.flip();

    return result;
}
```

---

## 五、线程模型

### 5.1 Netty 线程模型

```
┌─────────────────────────────────────────────┐
│         Netty Reactor 线程模型               │
├─────────────────────────────────────────────┤
│                                              │
│  Boss Group (1个线程)                        │
│  ┌──────────────────────────────┐           │
│  │  - 接收新连接                │           │
│  │  - 注册到 Worker Group       │           │
│  └──────────────────────────────┘           │
│             ↓                                │
│  Worker Group (多个线程)                     │
│  ┌──────────────────────────────┐           │
│  │  - I/O 读写                  │           │
│  │  - 编解码                    │           │
│  │  - 分发到业务线程池          │           │
│  └──────────────────────────────┘           │
│             ↓                                │
│  业务线程池 (可配置)                         │
│  ┌──────────────────────────────┐           │
│  │  - SendMessageExecutor       │           │
│  │  - PullMessageExecutor       │           │
│  │  - QueryMessageExecutor      │           │
│  │  - HeartbeatExecutor         │           │
│  └──────────────────────────────┘           │
│                                              │
└─────────────────────────────────────────────┘
```

### 5.2 线程池配置

```java
// Broker 启动时初始化线程池
public class BrokerController {

    private void initialize() {
        // 1. 发送消息线程池
        this.sendMessageExecutor = new BrokerFixedThreadPoolExecutor(
            this.brokerConfig.getSendMessageThreadPoolNums(),  // 核心线程数：默认16
            this.brokerConfig.getSendMessageThreadPoolNums(),
            1000 * 60,
            TimeUnit.MILLISECONDS,
            this.sendThreadPoolQueue,
            new ThreadFactoryImpl("SendMessageThread_")
        );

        // 2. 拉取消息线程池
        this.pullMessageExecutor = new BrokerFixedThreadPoolExecutor(
            this.brokerConfig.getPullMessageThreadPoolNums(),  // 默认16+核心数
            this.brokerConfig.getPullMessageThreadPoolNums(),
            1000 * 60,
            TimeUnit.MILLISECONDS,
            this.pullThreadPoolQueue,
            new ThreadFactoryImpl("PullMessageThread_")
        );

        // 3. 查询消息线程池
        this.queryMessageExecutor = new BrokerFixedThreadPoolExecutor(
            this.brokerConfig.getQueryMessageThreadPoolNums(),  // 默认8+核心数
            this.brokerConfig.getQueryMessageThreadPoolNums(),
            1000 * 60,
            TimeUnit.MILLISECONDS,
            this.queryThreadPoolQueue,
            new ThreadFactoryImpl("QueryMessageThread_")
        );
    }
}

// 配置建议
# broker.conf
sendMessageThreadPoolNums=16            # 发送消息线程
pullMessageThreadPoolNums=32            # 拉取消息线程
queryMessageThreadPoolNums=16           # 查询消息线程
```

---

## 六、性能优化

### 6.1 零拷贝

```java
// 使用 FileRegion 实现零拷贝传输
public class TransferMsgByHeap {

    public void transferData(SelectMappedBufferResult selectMappedBufferResult,
                            Channel channel) {

        ByteBuffer byteBuffer = selectMappedBufferResult.getByteBuffer();

        // 方式1：堆内存传输（有拷贝）
        byte[] data = new byte[byteBuffer.remaining()];
        byteBuffer.get(data);
        channel.writeAndFlush(Unpooled.wrappedBuffer(data));

        // 方式2：零拷贝传输（推荐）
        FileRegion fileRegion = new DefaultFileRegion(
            selectMappedBufferResult.getMappedFile().getFileChannel(),
            selectMappedBufferResult.getStartOffset(),
            selectMappedBufferResult.getSize()
        );
        channel.writeAndFlush(fileRegion);
    }
}
```

### 6.2 批量发送

```java
// 生产者批量发送
DefaultMQProducer producer = new DefaultMQProducer("group");
producer.start();

List<Message> messages = new ArrayList<>();
for (int i = 0; i < 100; i++) {
    Message msg = new Message("Topic", "Tag", ("Hello" + i).getBytes());
    messages.add(msg);
}

// 一次网络调用发送100条
SendResult result = producer.send(messages);
```

### 6.3 连接复用

```java
// Client 连接池复用
public class NettyRemotingClient {

    // Channel 缓存表
    private final ConcurrentMap<String, ChannelWrapper> channelTables =
        new ConcurrentHashMap<>();

    // 获取或创建 Channel
    private Channel getAndCreateChannel(final String addr) throws InterruptedException {
        ChannelWrapper cw = this.channelTables.get(addr);
        if (cw != null && cw.isOK()) {
            return cw.getChannel();
        }

        return this.createChannel(addr);
    }

    // 优势：减少连接建立开销
}
```

---

## 七、总结与思考

### 7.1 核心要点

1. **Netty 基础**：RocketMQ 基于 Netty 构建网络通信
2. **三种调用**：同步、异步、单向，满足不同场景
3. **请求处理器**：请求码映射到具体处理器
4. **自定义协议**：高效的二进制协议
5. **线程模型**：Reactor + 业务线程池

### 7.2 思考题

1. **为什么需要三种调用方式？**
   - 提示：考虑性能和使用场景

2. **异步调用如何保证响应匹配？**
   - 提示：opaque（请求ID）

3. **如何优化网络通信性能？**
   - 提示：零拷贝、批量、连接复用

### 7.3 下一步学习

下一篇（最后一篇）我们将剖析 **消息路由与负载均衡**，完成架构原理篇！

---

**本文关键词**：`Remoting` `Netty` `网络通信` `请求处理器` `零拷贝`

**专题导航**：[上一篇：索引机制详解](/blog/rocketmq/posts/16-index-mechanism/) | [下一篇：消息路由与负载均衡](#)
