---
title: "集群流控：跨实例的流量管理"
date: 2025-11-20T16:10:00+08:00
draft: false
tags: ["Sentinel", "集群流控", "分布式限流", "Token Server"]
categories: ["技术"]
series: ["Sentinel从入门到精通"]
weight: 20
stage: 4
stageTitle: "进阶特性篇"
description: "学习Sentinel的集群流控，实现跨实例的统一流量管理"
---

## 引言：当单机限流不够用时

假设你的订单服务部署了**3个实例**，每个实例配置了QPS限流1000：

```
实例1：QPS限流 1000
实例2：QPS限流 1000
实例3：QPS限流 1000
```

**问题来了**：整个订单服务的总QPS是多少？

答案：**3000 QPS**（每个实例1000）。

**但如果你的需求是"整个订单服务的总QPS不超过2000"呢？**

传统的单机限流无法实现！因为每个实例各自统计，无法感知其他实例的流量。

**这就是集群流控（Cluster Flow Control）要解决的问题。**

---

## 单机限流的局限性

### 问题1：无法精确控制总流量

**场景**：3个实例，期望总QPS 2000。

**单机限流配置**：

```java
FlowRule rule = new FlowRule();
rule.setResource("orderCreate");
rule.setCount(667); // 2000 / 3 ≈ 667
```

**问题**：

- 流量不均匀时，会导致总QPS超限
- 某个实例挂了，总QPS会降低

**示例**：

| 场景 | 实例1 QPS | 实例2 QPS | 实例3 QPS | 总QPS | 结果 |
|-----|----------|----------|----------|-------|-----|
| 流量均匀 | 666 | 666 | 666 | 1998 | ✅ 正常 |
| 流量不均 | 667 | 667 | 1000 | 2334 | ❌ 超限 |
| 实例3挂 | 667 | 667 | 0 | 1334 | ⚠️ 浪费 |

### 问题2：无法应对突发流量

**场景**：3个实例，某一秒流量全部打到实例1。

| 时刻 | 实例1 | 实例2 | 实例3 | 总QPS | 期望 |
|-----|-------|-------|-------|-------|-----|
| T0 | 667 ❌ | 0 | 0 | 667 | 2000 |
| T1 | 667 ❌ | 0 | 0 | 667 | 2000 |

实例1已经限流了，但实例2和实例3还有大量闲置容量。

### 问题3：扩缩容后需要调整规则

**场景**：从3个实例扩容到5个实例。

- 扩容前：每个实例667 QPS
- 扩容后：每个实例需要调整为400 QPS（2000 / 5）

**问题**：每次扩缩容都要手动调整限流规则，运维成本高。

---

## 集群流控的原理

### 核心思想

> 将限流的**统计和决策**集中到一个**Token Server**，各个实例作为**Token Client**向Token Server申请令牌。

**架构图**：

```
┌──────────────────────────────────────┐
│          Token Server                │
│    (集中统计，集中决策)                │
│                                      │
│  总QPS统计：1500 / 2000              │
│  令牌剩余：500                        │
└───┬──────────────┬──────────────┬───┘
    │              │              │
申请令牌  申请令牌  申请令牌
    │              │              │
┌───▼───┐      ┌───▼───┐      ┌───▼───┐
│实例1   │      │实例2   │      │实例3   │
│Token   │      │Token   │      │Token   │
│Client  │      │Client  │      │Client  │
└────────┘      └────────┘      └────────┘
```

### 工作流程

1. **请求到达实例1**
2. **实例1向Token Server申请令牌**
3. **Token Server检查总QPS**
   - 如果总QPS < 2000，分配令牌，允许通过
   - 如果总QPS >= 2000，拒绝令牌，限流拒绝
4. **实例1根据结果处理请求**

### 优势

| 单机限流 | 集群流控 |
|---------|---------|
| 每个实例独立统计 | 全局统一统计 |
| 无法精确控制总流量 | 精确控制总流量 |
| 流量不均时会超限 | 自动适应流量分布 |
| 扩缩容需要调整规则 | 扩缩容无需调整 |

---

## Token Server vs Token Client

### Token Server（令牌服务器）

**职责**：
- 接收各个Client的令牌申请
- 统计全局QPS
- 决策是否分配令牌

**部署方式**：

1. **嵌入模式**（Embedded）：
   - Token Server嵌入在某个实例中
   - 这个实例同时充当Token Server和Token Client
   - 优点：无需额外部署
   - 缺点：单点故障

2. **独立模式**（Standalone）：
   - Token Server独立部署
   - 所有实例都是Token Client
   - 优点：职责清晰，易于扩展
   - 缺点：需要额外部署

### Token Client（令牌客户端）

**职责**：
- 向Token Server申请令牌
- 根据申请结果决定是否放行请求

---

## 配置集群流控

### 第一步：添加依赖

```xml
<!-- Sentinel集群流控依赖 -->
<dependency>
    <groupId>com.alibaba.csp</groupId>
    <artifactId>sentinel-cluster-client-default</artifactId>
    <version>1.8.6</version>
</dependency>

<dependency>
    <groupId>com.alibaba.csp</groupId>
    <artifactId>sentinel-cluster-server-default</artifactId>
    <version>1.8.6</version>
</dependency>
```

### 第二步：配置Token Server

**选择一个实例作为Token Server**（如实例1）：

```java
import com.alibaba.csp.sentinel.cluster.server.EmbeddedClusterTokenServerProvider;
import com.alibaba.csp.sentinel.cluster.server.config.ClusterServerConfigManager;
import com.alibaba.csp.sentinel.cluster.server.config.ServerTransportConfig;

@Configuration
public class TokenServerConfig {

    @PostConstruct
    public void initTokenServer() {
        // 1. 配置Token Server传输层
        ServerTransportConfig config = new ServerTransportConfig();
        config.setIdleSeconds(600); // 连接空闲600秒
        config.setPort(9999); // Token Server端口
        ClusterServerConfigManager.loadGlobalTransportConfig(config);

        // 2. 启动嵌入式Token Server
        EmbeddedClusterTokenServerProvider.getServer().start();

        System.out.println("✅ Token Server已启动，端口：9999");
    }
}
```

### 第三步：配置Token Client

**其他实例配置为Token Client**（实例2、实例3）：

```java
import com.alibaba.csp.sentinel.cluster.client.config.ClusterClientAssignConfig;
import com.alibaba.csp.sentinel.cluster.client.config.ClusterClientConfig;
import com.alibaba.csp.sentinel.cluster.client.config.ClusterClientConfigManager;

@Configuration
public class TokenClientConfig {

    @PostConstruct
    public void initTokenClient() {
        // 1. 配置Token Client
        ClusterClientAssignConfig assignConfig = new ClusterClientAssignConfig();
        assignConfig.setServerHost("192.168.1.100"); // Token Server IP
        assignConfig.setServerPort(9999); // Token Server端口
        ClusterClientConfigManager.applyNewAssignConfig(assignConfig);

        // 2. 配置客户端通信
        ClusterClientConfig clientConfig = new ClusterClientConfig();
        clientConfig.setRequestTimeout(2000); // 请求超时2秒
        ClusterClientConfigManager.applyNewConfig(clientConfig);

        System.out.println("✅ Token Client已配置，连接到：192.168.1.100:9999");
    }
}
```

### 第四步：配置集群流控规则

```java
import com.alibaba.csp.sentinel.slots.block.flow.FlowRule;
import com.alibaba.csp.sentinel.slots.block.flow.FlowRuleManager;
import com.alibaba.csp.sentinel.slots.block.flow.param.ParamFlowClusterConfig;

@Configuration
public class ClusterFlowRuleConfig {

    @PostConstruct
    public void initClusterFlowRule() {
        List<FlowRule> rules = new ArrayList<>();

        FlowRule rule = new FlowRule();
        rule.setResource("orderCreate");
        rule.setGrade(RuleConstant.FLOW_GRADE_QPS);
        rule.setCount(2000); // 总QPS限流2000

        // 关键：启用集群模式
        rule.setClusterMode(true);

        // 配置集群参数
        ParamFlowClusterConfig clusterConfig = new ParamFlowClusterConfig();
        clusterConfig.setFlowId(1001L); // 规则ID（全局唯一）
        clusterConfig.setThresholdType(ClusterRuleConstant.FLOW_THRESHOLD_GLOBAL); // 全局阈值
        rule.setClusterConfig(clusterConfig);

        rules.add(rule);
        FlowRuleManager.loadRules(rules);

        System.out.println("✅ 集群流控规则已加载：总QPS 2000");
    }
}
```

---

## 实战案例：订单服务集群流控

### 场景描述

订单服务部署3个实例，要求：
- 订单创建接口总QPS不超过2000
- 订单查询接口总QPS不超过5000

### 架构设计

```
                Token Server
              (实例1:9999)
                    ↓
       ┌────────────┼────────────┐
       ↓            ↓            ↓
    实例1         实例2         实例3
  (Server+Client) (Client)   (Client)
```

### 完整配置

#### 实例1（Token Server + Client）

```java
@Configuration
public class Instance1Config {

    @PostConstruct
    public void init() {
        // 1. 启动Token Server
        initTokenServer();

        // 2. 配置集群流控规则
        initClusterRules();
    }

    private void initTokenServer() {
        ServerTransportConfig config = new ServerTransportConfig();
        config.setPort(9999);
        ClusterServerConfigManager.loadGlobalTransportConfig(config);
        EmbeddedClusterTokenServerProvider.getServer().start();
        System.out.println("✅ Token Server已启动");
    }

    private void initClusterRules() {
        List<FlowRule> rules = new ArrayList<>();

        // 规则1：订单创建，总QPS 2000
        FlowRule createRule = new FlowRule();
        createRule.setResource("orderCreate");
        createRule.setGrade(RuleConstant.FLOW_GRADE_QPS);
        createRule.setCount(2000);
        createRule.setClusterMode(true);

        ParamFlowClusterConfig createConfig = new ParamFlowClusterConfig();
        createConfig.setFlowId(1001L);
        createConfig.setThresholdType(ClusterRuleConstant.FLOW_THRESHOLD_GLOBAL);
        createRule.setClusterConfig(createConfig);

        rules.add(createRule);

        // 规则2：订单查询，总QPS 5000
        FlowRule queryRule = new FlowRule();
        queryRule.setResource("orderQuery");
        queryRule.setGrade(RuleConstant.FLOW_GRADE_QPS);
        queryRule.setCount(5000);
        queryRule.setClusterMode(true);

        ParamFlowClusterConfig queryConfig = new ParamFlowClusterConfig();
        queryConfig.setFlowId(1002L);
        queryConfig.setThresholdType(ClusterRuleConstant.FLOW_THRESHOLD_GLOBAL);
        queryRule.setClusterConfig(queryConfig);

        rules.add(queryRule);

        FlowRuleManager.loadRules(rules);
        System.out.println("✅ 集群流控规则已加载");
    }
}
```

#### 实例2/3（Token Client）

```java
@Configuration
public class Instance2Config {

    @PostConstruct
    public void init() {
        // 配置Token Client
        ClusterClientAssignConfig assignConfig = new ClusterClientAssignConfig();
        assignConfig.setServerHost("192.168.1.100"); // 实例1的IP
        assignConfig.setServerPort(9999);
        ClusterClientConfigManager.applyNewAssignConfig(assignConfig);

        ClusterClientConfig clientConfig = new ClusterClientConfig();
        clientConfig.setRequestTimeout(2000);
        ClusterClientConfigManager.applyNewConfig(clientConfig);

        // 加载相同的流控规则
        initClusterRules();

        System.out.println("✅ Token Client已配置");
    }

    private void initClusterRules() {
        // 与实例1相同的规则配置
        // ...
    }
}
```

### 压测验证

```bash
# 同时压测3个实例
wrk -t10 -c500 -d60s http://192.168.1.100:8080/order/create &
wrk -t10 -c500 -d60s http://192.168.1.101:8080/order/create &
wrk -t10 -c500 -d60s http://192.168.1.102:8080/order/create &
```

**预期结果**：

| 实例 | 单机QPS | 限流次数 | 说明 |
|-----|---------|---------|-----|
| 实例1 | 800 | 200 | 总QPS控制在2000 |
| 实例2 | 700 | 300 |  |
| 实例3 | 500 | 500 |  |
| **总计** | **2000** | **1000** | ✅ 精确控制 |

---

## 高可用方案

### 问题：Token Server单点故障

如果Token Server挂了，所有实例都无法申请令牌，整个服务不可用。

### 解决方案1：自动降级

**配置**：

```java
ClusterClientConfig clientConfig = new ClusterClientConfig();
clientConfig.setRequestTimeout(2000);
clientConfig.setFallbackToLocalWhenFail(true); // ← 关键：失败时降级为本地限流
ClusterClientConfigManager.applyNewConfig(clientConfig);
```

**效果**：

- Token Server正常：使用集群流控
- Token Server挂了：**自动降级为单机限流**

### 解决方案2：Token Server高可用

**方案**：部署多个Token Server，通过选主机制选出一个活跃的Token Server。

```
┌─────────┐  ┌─────────┐  ┌─────────┐
│ Token   │  │ Token   │  │ Token   │
│ Server1 │  │ Server2 │  │ Server3 │
│ (主)    │  │ (备)    │  │ (备)    │
└────┬────┘  └─────────┘  └─────────┘
     │
选主（通过Nacos/ZooKeeper）
     │
┌────▼────────────────────────────┐
│      Token Client 集群           │
└─────────────────────────────────┘
```

**选主机制**：

- 使用Nacos、ZooKeeper、Consul等注册中心
- Token Server注册临时节点
- 客户端从注册中心获取当前主节点

---

## 集群流控 vs 单机限流

### 对比表格

| 维度 | 单机限流 | 集群流控 |
|-----|---------|---------|
| **统计粒度** | 单实例 | 全局 |
| **精确度** | 低（流量不均时） | 高 |
| **扩缩容** | 需要调整规则 | 无需调整 |
| **性能** | 高（本地决策） | 中（网络开销） |
| **复杂度** | 低 | 高（需要Token Server） |
| **可用性** | 高 | 中（依赖Token Server） |

### 使用建议

**使用集群流控**：

- 需要精确控制总流量
- 实例数量多（>5个）
- 流量分布不均匀

**使用单机限流**：

- 实例数量少（<3个）
- 流量分布均匀
- 对精确度要求不高

---

## 注意事项

### 1. Token Server的性能

**瓶颈**：Token Server需要处理所有实例的令牌申请，性能有上限。

**建议**：
- Token Server部署在高性能机器上
- 单个Token Server建议管理<50个实例
- 超过50个实例，考虑分组（不同应用用不同Token Server）

### 2. 网络延迟

**问题**：申请令牌需要网络通信，增加延迟（通常1-5ms）。

**优化**：
- Token Client与Token Server尽量在同一机房
- 设置合理的超时时间（1-2秒）
- 配置降级策略

### 3. 规则同步

**问题**：所有实例的集群流控规则必须一致。

**解决**：
- 使用配置中心（Nacos、Apollo）统一下发规则
- 或通过Sentinel Dashboard推送规则

---

## 总结

本文我们学习了Sentinel的集群流控：

1. **单机限流的局限性**：无法精确控制总流量，流量不均时会超限
2. **集群流控原理**：Token Server集中统计和决策，Token Client申请令牌
3. **Token Server vs Client**：嵌入模式和独立模式
4. **配置方法**：启动Token Server、配置Token Client、配置集群规则
5. **实战案例**：订单服务3个实例的集群流控
6. **高可用方案**：自动降级、Token Server多活

**核心要点**：

> 集群流控是Sentinel的"中央大脑"，它将分散的单机限流统一到Token Server，实现了跨实例的精确流量控制。

**下一篇预告**：

我们将学习**网关流控**：
- 为什么要在网关层做流控？
- Spring Cloud Gateway + Sentinel集成
- 网关层的限流、熔断、系统保护
- 参数限流和自定义限流

让我们一起探索统一流量入口的防护！
