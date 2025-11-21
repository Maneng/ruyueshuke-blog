---
title: "集群流控的架构设计"
date: 2025-11-21T16:43:00+08:00
draft: false
tags: ["Sentinel", "集群流控", "架构设计"]
categories: ["技术"]
series: ["Sentinel从入门到精通"]
weight: 32
stage: 6
stageTitle: "架构原理篇"
description: "深入集群流控的架构设计和实现原理"
---

## 架构设计

```
┌────────────────────────────────┐
│      Token Server              │
│  ├─ TokenService (令牌服务)    │
│  ├─ FlowStatistics (统计)     │
│  └─ ClusterFlowRuleChecker     │
└────────┬───────────────────────┘
         │ Netty通信
    ┌────┴───┬────┬────┐
    ↓        ↓    ↓    ↓
Client1  Client2 Client3 Client4
```

## Token Server核心

### TokenService

```java
public class TokenService {
    // 资源ID → FlowRule
    private final Map<Long, FlowRule> ruleMap = new ConcurrentHashMap<>();

    // 资源ID → 统计数据
    private final Map<Long, ClusterMetric> metricMap = new ConcurrentHashMap<>();

    // 请求令牌
    public TokenResult requestToken(Long ruleId, int acquireCount, boolean prioritized) {
        if (ruleId == null) {
            return new TokenResult(TokenResultStatus.NO_RULE_EXISTS);
        }

        FlowRule rule = ruleMap.get(ruleId);
        if (rule == null) {
            return new TokenResult(TokenResultStatus.NO_RULE_EXISTS);
        }

        // 获取统计数据
        ClusterMetric metric = metricMap.computeIfAbsent(ruleId, k -> new ClusterMetric());

        // 检查是否允许通过
        boolean pass = canPass(rule, metric, acquireCount);

        if (pass) {
            metric.add(acquireCount);
            return new TokenResult(TokenResultStatus.OK);
        } else {
            return new TokenResult(TokenResultStatus.BLOCKED);
        }
    }

    private boolean canPass(FlowRule rule, ClusterMetric metric, int acquireCount) {
        double count = rule.getCount();
        long currentCount = metric.getCurrentCount();

        return currentCount + acquireCount <= count;
    }
}
```

### ClusterMetric

```java
public class ClusterMetric {
    private final LeapArray<MetricBucket> data;

    public ClusterMetric() {
        this.data = new BucketLeapArray(SampleCountProperty.SAMPLE_COUNT, IntervalProperty.INTERVAL);
    }

    public long getCurrentCount() {
        data.currentWindow();
        long pass = 0;
        List<MetricBucket> list = data.values();

        for (MetricBucket bucket : list) {
            pass += bucket.pass();
        }

        return pass;
    }

    public void add(int count) {
        WindowWrap<MetricBucket> wrap = data.currentWindow();
        wrap.value().addPass(count);
    }
}
```

## Token Client核心

### ClusterFlowChecker

```java
public class ClusterFlowChecker {

    public static TokenResult acquireClusterToken(FlowRule rule, int acquireCount, boolean prioritized) {
        // 获取集群客户端
        ClusterTokenClient client = TokenClientProvider.getClient();
        if (client == null) {
            // 客户端未初始化，降级为本地限流
            return null;
        }

        long flowId = rule.getClusterConfig().getFlowId();

        // 请求令牌
        TokenResult result = null;
        try {
            result = client.requestToken(flowId, acquireCount, prioritized);
        } catch (Exception ex) {
            // 请求失败，降级为本地限流
            RecordLog.warn("[ClusterFlowChecker] Request cluster token failed", ex);
        }

        return result;
    }
}
```

### TokenResult

```java
public class TokenResult {
    private Integer status;     // 状态码
    private int remaining;      // 剩余令牌
    private int waitInMs;       // 等待时间
    private Map<String, String> attachments;  // 附加信息

    public TokenResult(Integer status) {
        this.status = status;
    }

    public boolean isPass() {
        return status == TokenResultStatus.OK;
    }

    public boolean isBlocked() {
        return status == TokenResultStatus.BLOCKED;
    }

    public boolean shouldWait() {
        return status == TokenResultStatus.SHOULD_WAIT;
    }
}

public final class TokenResultStatus {
    public static final int OK = 0;
    public static final int BLOCKED = 1;
    public static final int SHOULD_WAIT = 2;
    public static final int NO_RULE_EXISTS = 3;
    public static final int BAD_REQUEST = 4;
    public static final int FAIL = 5;
}
```

## Netty通信

### Server端

```java
public class TokenServer {
    private final int port;
    private EventLoopGroup bossGroup;
    private EventLoopGroup workerGroup;

    public void start() throws Exception {
        bossGroup = new NioEventLoopGroup(1);
        workerGroup = new NioEventLoopGroup();

        ServerBootstrap b = new ServerBootstrap();
        b.group(bossGroup, workerGroup)
            .channel(NioServerSocketChannel.class)
            .childHandler(new ChannelInitializer<SocketChannel>() {
                @Override
                public void initChannel(SocketChannel ch) {
                    ch.pipeline()
                        .addLast(new Decoder())
                        .addLast(new Encoder())
                        .addLast(new TokenServerHandler());
                }
            });

        ChannelFuture f = b.bind(port).sync();
        f.channel().closeFuture().sync();
    }

    public void stop() {
        if (bossGroup != null) {
            bossGroup.shutdownGracefully();
        }
        if (workerGroup != null) {
            workerGroup.shutdownGracefully();
        }
    }
}

public class TokenServerHandler extends ChannelInboundHandlerAdapter {

    @Override
    public void channelRead(ChannelHandlerContext ctx, Object msg) {
        if (msg instanceof TokenRequest) {
            TokenRequest request = (TokenRequest) msg;

            // 请求令牌
            TokenResult result = TokenService.requestToken(
                request.getFlowId(),
                request.getAcquireCount(),
                request.isPriority()
            );

            // 响应
            TokenResponse response = new TokenResponse();
            response.setStatus(result.getStatus());
            response.setRemaining(result.getRemaining());
            ctx.writeAndFlush(response);
        }
    }
}
```

### Client端

```java
public class TokenClient {
    private EventLoopGroup group;
    private Bootstrap bootstrap;
    private Channel channel;

    public void start(String host, int port) throws Exception {
        group = new NioEventLoopGroup();
        bootstrap = new Bootstrap();
        bootstrap.group(group)
            .channel(NioSocketChannel.class)
            .handler(new ChannelInitializer<SocketChannel>() {
                @Override
                public void initChannel(SocketChannel ch) {
                    ch.pipeline()
                        .addLast(new Encoder())
                        .addLast(new Decoder())
                        .addLast(new TokenClientHandler());
                }
            });

        channel = bootstrap.connect(host, port).sync().channel();
    }

    public TokenResult requestToken(Long flowId, int acquireCount, boolean prioritized) {
        TokenRequest request = new TokenRequest();
        request.setFlowId(flowId);
        request.setAcquireCount(acquireCount);
        request.setPriority(prioritized);

        // 发送请求
        channel.writeAndFlush(request);

        // 等待响应（简化处理）
        return waitForResponse();
    }
}
```

## 失败降级

```java
public class ClusterFlowSlot extends AbstractLinkedProcessorSlot<DefaultNode> {

    @Override
    public void entry(Context context, ResourceWrapper resourceWrapper, DefaultNode node, int count, Object... args) throws Throwable {
        FlowRule rule = getRuleFor(resourceWrapper);

        if (rule != null && rule.isClusterMode()) {
            // 集群模式
            TokenResult result = ClusterFlowChecker.acquireClusterToken(rule, count, false);

            if (result == null || result.getStatus() == TokenResultStatus.FAIL) {
                // Token Server不可用，降级为本地限流
                fallbackToLocalOrPass(context, rule, node, count, args);
            } else if (result.isBlocked()) {
                // 集群限流拒绝
                throw new FlowException(resourceWrapper.getName(), rule);
            }
        } else {
            // 本地模式
            checkLocalFlow(context, resourceWrapper, node, count, args);
        }

        fireEntry(context, resourceWrapper, node, count, args);
    }

    private void fallbackToLocalOrPass(Context context, FlowRule rule, DefaultNode node, int count, Object... args) throws BlockException {
        if (rule.getClusterConfig().isFallbackToLocalWhenFail()) {
            // 降级为本地限流
            checkLocalFlow(context, null, node, count, args);
        } else {
            // 直接通过
            // Do nothing
        }
    }
}
```

## 动态切换

### Server选举

```java
public class ServerElection {
    private final NacosNamingService namingService;
    private volatile boolean isLeader = false;

    public void elect() {
        try {
            // 注册临时节点
            Instance instance = new Instance();
            instance.setIp(NetUtil.getLocalHost());
            instance.setPort(ClusterConstants.DEFAULT_TOKEN_SERVER_PORT);
            instance.setHealthy(true);
            instance.setWeight(1.0);

            namingService.registerInstance(
                ClusterConstants.TOKEN_SERVER_SERVICE_NAME,
                instance
            );

            // 监听节点变化
            namingService.subscribe(
                ClusterConstants.TOKEN_SERVER_SERVICE_NAME,
                event -> {
                    if (event instanceof NamingEvent) {
                        List<Instance> instances = ((NamingEvent) event).getInstances();
                        checkAndUpdateLeader(instances);
                    }
                }
            );

        } catch (Exception e) {
            RecordLog.warn("Election failed", e);
        }
    }

    private void checkAndUpdateLeader(List<Instance> instances) {
        if (instances.isEmpty()) {
            isLeader = false;
            return;
        }

        // 选择第一个实例为Leader
        Instance leader = instances.get(0);
        isLeader = isCurrentInstance(leader);

        if (isLeader) {
            startTokenServer();
        } else {
            stopTokenServer();
            connectToLeader(leader);
        }
    }
}
```

## 总结

集群流控架构核心：
1. **Token Server**：集中统计，分配令牌
2. **Token Client**：请求令牌，执行限流
3. **Netty通信**：高性能RPC通信
4. **失败降级**：Server不可用时降级为本地限流
5. **动态切换**：Server选举，自动切换

**关键设计**：
- 单点统计避免超限
- Netty异步通信提高性能
- 失败降级保证可用性
- 选举机制实现高可用

**性能优化**：
- Client连接复用
- 批量请求令牌
- 异步响应处理
- 本地缓存加速
