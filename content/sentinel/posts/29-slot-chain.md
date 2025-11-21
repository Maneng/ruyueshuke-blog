---
title: "责任链模式：ProcessorSlotChain详解"
date: 2025-11-21T16:37:00+08:00
draft: false
tags: ["Sentinel", "责任链模式", "SlotChain"]
categories: ["技术"]
series: ["Sentinel从入门到精通"]
weight: 29
stage: 6
stageTitle: "架构原理篇"
description: "深入理解Sentinel的责任链模式实现"
---

## Slot Chain架构

```
AbstractLinkedProcessorSlot (抽象类)
         ↓
ProcessorSlotChain (链)
         ↓
    ┌─────────┬─────────┬──────────┬──────────┐
    ↓         ↓         ↓          ↓          ↓
NodeSelector Cluster  Statistic  Flow    Degrade
   Slot       Slot      Slot      Slot      Slot
```

## 核心Slot详解

### 1. NodeSelectorSlot（节点选择）

**作用**：构建调用树，创建Context和DefaultNode。

```java
public class NodeSelectorSlot extends AbstractLinkedProcessorSlot<Object> {

    private volatile Map<String, DefaultNode> map = new HashMap<>(10);

    @Override
    public void entry(Context context, ResourceWrapper resourceWrapper, Object obj, int count, Object... args) throws Throwable {
        // 获取或创建DefaultNode
        DefaultNode node = map.get(context.getName());
        if (node == null) {
            synchronized (this) {
                node = map.get(context.getName());
                if (node == null) {
                    node = new DefaultNode(resourceWrapper, null);
                    map.put(context.getName(), node);
                }
            }
        }

        // 设置当前节点
        context.setCurNode(node);

        // 调用下一个Slot
        fireEntry(context, resourceWrapper, node, count, args);
    }
}
```

### 2. ClusterBuilderSlot（集群构建）

**作用**：创建ClusterNode，全局统计。

```java
public class ClusterBuilderSlot extends AbstractLinkedProcessorSlot<DefaultNode> {

    private static volatile Map<ResourceWrapper, ClusterNode> clusterNodeMap = new HashMap<>();

    @Override
    public void entry(Context context, ResourceWrapper resourceWrapper, DefaultNode node, int count, Object... args) throws Throwable {
        if (clusterNode == null) {
            synchronized (lock) {
                if (clusterNode == null) {
                    clusterNode = new ClusterNode(resourceWrapper.getName());
                    clusterNodeMap.put(node.getId(), clusterNode);
                }
            }
        }
        node.setClusterNode(clusterNode);

        // 构建调用树
        if (!"".equals(context.getOrigin())) {
            Node originNode = node.getClusterNode().getOrCreateOriginNode(context.getOrigin());
            context.getCurEntry().setOriginNode(originNode);
        }

        fireEntry(context, resourceWrapper, node, count, args);
    }
}
```

### 3. StatisticSlot（统计）

**作用**：实时统计通过、阻塞、异常、RT等指标。

```java
public class StatisticSlot extends AbstractLinkedProcessorSlot<DefaultNode> {

    @Override
    public void entry(Context context, ResourceWrapper resourceWrapper, DefaultNode node, int count, Object... args) throws Throwable {
        try {
            // 调用下一个Slot
            fireEntry(context, resourceWrapper, node, count, args);

            // 统计通过请求
            node.increaseThreadNum();
            node.addPassRequest(count);

            if (context.getCurEntry().getOriginNode() != null) {
                context.getCurEntry().getOriginNode().increaseThreadNum();
                context.getCurEntry().getOriginNode().addPassRequest(count);
            }

        } catch (BlockException e) {
            // 统计阻塞请求
            node.increaseBlockQps(count);
            if (context.getCurEntry().getOriginNode() != null) {
                context.getCurEntry().getOriginNode().increaseBlockQps(count);
            }
            throw e;
        }
    }

    @Override
    public void exit(Context context, ResourceWrapper resourceWrapper, int count, Object... args) {
        DefaultNode node = (DefaultNode) context.getCurNode();

        if (context.getCurEntry().getError() == null) {
            // 统计成功和RT
            long rt = TimeUtil.currentTimeMillis() - context.getCurEntry().getCreateTime();
            node.addRtAndSuccess(rt, count);
            node.decreaseThreadNum();

            if (context.getCurEntry().getOriginNode() != null) {
                context.getCurEntry().getOriginNode().addRtAndSuccess(rt, count);
                context.getCurEntry().getOriginNode().decreaseThreadNum();
            }
        } else {
            // 统计异常
            node.increaseExceptionQps(count);
        }

        fireExit(context, resourceWrapper, count, args);
    }
}
```

### 4. AuthoritySlot（授权）

**作用**：黑白名单控制。

```java
public class AuthoritySlot extends AbstractLinkedProcessorSlot<DefaultNode> {

    @Override
    public void entry(Context context, ResourceWrapper resourceWrapper, DefaultNode node, int count, Object... args) throws Throwable {
        checkBlackWhiteAuthority(resourceWrapper, context);
        fireEntry(context, resourceWrapper, node, count, args);
    }

    void checkBlackWhiteAuthority(ResourceWrapper resource, Context context) throws AuthorityException {
        Map<String, Set<AuthorityRule>> authorityRules = AuthorityRuleManager.getAuthorityRules();

        if (authorityRules == null) {
            return;
        }

        Set<AuthorityRule> rules = authorityRules.get(resource.getName());
        if (rules == null) {
            return;
        }

        for (AuthorityRule rule : rules) {
            if (!AuthorityRuleChecker.passCheck(rule, context)) {
                throw new AuthorityException(resource.getName(), rule);
            }
        }
    }
}
```

### 5. SystemSlot（系统保护）

**作用**：系统级别保护（Load、CPU、RT）。

```java
public class SystemSlot extends AbstractLinkedProcessorSlot<DefaultNode> {

    @Override
    public void entry(Context context, ResourceWrapper resourceWrapper, DefaultNode node, int count, Object... args) throws Throwable {
        SystemRuleManager.checkSystem(resourceWrapper);
        fireEntry(context, resourceWrapper, node, count, args);
    }
}

public class SystemRuleManager {
    public static void checkSystem(ResourceWrapper resourceWrapper) throws BlockException {
        SystemRule rule = getSystemRule();
        if (rule == null) {
            return;
        }

        // 检查QPS
        if (rule.getQps() > 0) {
            double qps = Constants.ENTRY_NODE.passQps();
            if (qps > rule.getQps()) {
                throw new SystemBlockException(resourceWrapper.getName(), "qps");
            }
        }

        // 检查线程数
        if (rule.getMaxThread() > 0) {
            int currentThread = Constants.ENTRY_NODE.curThreadNum();
            if (currentThread > rule.getMaxThread()) {
                throw new SystemBlockException(resourceWrapper.getName(), "thread");
            }
        }

        // 检查Load
        if (rule.getHighestSystemLoad() > 0) {
            double currentLoad = getCurrentSystemAvgLoad();
            if (currentLoad > rule.getHighestSystemLoad()) {
                if (!checkBbr(currentLoad)) {
                    throw new SystemBlockException(resourceWrapper.getName(), "load");
                }
            }
        }
    }
}
```

### 6. FlowSlot（流控）

**作用**：流量控制。

```java
public class FlowSlot extends AbstractLinkedProcessorSlot<DefaultNode> {

    @Override
    public void entry(Context context, ResourceWrapper resourceWrapper, DefaultNode node, int count, Object... args) throws Throwable {
        checkFlow(resourceWrapper, context, node, count, args);
        fireEntry(context, resourceWrapper, node, count, args);
    }

    void checkFlow(ResourceWrapper resource, Context context, DefaultNode node, int count, Object... args) throws BlockException {
        List<FlowRule> rules = FlowRuleManager.getRules(resource.getName());
        if (rules != null) {
            for (FlowRule rule : rules) {
                if (!canPassCheck(rule, context, node, count)) {
                    throw new FlowException(resource.getName(), rule);
                }
            }
        }
    }
}
```

### 7. DegradeSlot（熔断）

**作用**：熔断降级。

```java
public class DegradeSlot extends AbstractLinkedProcessorSlot<DefaultNode> {

    @Override
    public void entry(Context context, ResourceWrapper resourceWrapper, DefaultNode node, int count, Object... args) throws Throwable {
        performChecking(context, resourceWrapper);
        fireEntry(context, resourceWrapper, node, count, args);
    }

    void performChecking(Context context, ResourceWrapper r) throws BlockException {
        List<CircuitBreaker> circuitBreakers = DegradeRuleManager.getCircuitBreakers(r.getName());
        if (circuitBreakers == null || circuitBreakers.isEmpty()) {
            return;
        }

        for (CircuitBreaker cb : circuitBreakers) {
            if (!cb.tryPass(context)) {
                throw new DegradeException(r.getName(), cb);
            }
        }
    }
}
```

## Slot Chain构建

```java
public class DefaultSlotChainBuilder implements SlotChainBuilder {

    @Override
    public ProcessorSlotChain build() {
        ProcessorSlotChain chain = new DefaultProcessorSlotChain();

        // 按顺序添加Slot
        chain.addLast(new NodeSelectorSlot());
        chain.addLast(new ClusterBuilderSlot());
        chain.addLast(new LogSlot());
        chain.addLast(new StatisticSlot());
        chain.addLast(new AuthoritySlot());
        chain.addLast(new SystemSlot());
        chain.addLast(new FlowSlot());
        chain.addLast(new DegradeSlot());

        return chain;
    }
}
```

## 自定义Slot

### 日志Slot

```java
public class LogSlot extends AbstractLinkedProcessorSlot<DefaultNode> {

    @Override
    public void entry(Context context, ResourceWrapper resourceWrapper, DefaultNode node, int count, Object... args) throws Throwable {
        long start = System.currentTimeMillis();
        try {
            fireEntry(context, resourceWrapper, node, count, args);
        } catch (BlockException e) {
            log.warn("资源被拒绝：{}, 原因：{}", resourceWrapper.getName(), e.getRuleLimitApp());
            throw e;
        } finally {
            long cost = System.currentTimeMillis() - start;
            log.info("资源调用：{}, 耗时：{}ms", resourceWrapper.getName(), cost);
        }
    }

    @Override
    public void exit(Context context, ResourceWrapper resourceWrapper, int count, Object... args) {
        fireExit(context, resourceWrapper, count, args);
    }
}
```

### 限流预警Slot

```java
public class FlowAlertSlot extends AbstractLinkedProcessorSlot<DefaultNode> {

    private final AtomicLong blockCount = new AtomicLong(0);

    @Override
    public void entry(Context context, ResourceWrapper resourceWrapper, DefaultNode node, int count, Object... args) throws Throwable {
        try {
            fireEntry(context, resourceWrapper, node, count, args);
        } catch (FlowException e) {
            long currentBlock = blockCount.incrementAndGet();

            // 限流次数超过100次，发送告警
            if (currentBlock % 100 == 0) {
                sendAlert(resourceWrapper.getName(), currentBlock);
            }

            throw e;
        }
    }

    private void sendAlert(String resource, long blockCount) {
        log.warn("限流告警：资源 {} 已被限流 {} 次", resource, blockCount);
        // 发送钉钉、邮件等告警
    }
}
```

## Slot执行流程图

```
Entry
  ↓
NodeSelectorSlot.entry()    ← 构建调用树
  ↓
ClusterBuilderSlot.entry()  ← 创建ClusterNode
  ↓
StatisticSlot.entry()       ← 统计请求
  ↓
AuthoritySlot.entry()       ← 黑白名单检查
  ↓
SystemSlot.entry()          ← 系统保护检查
  ↓
FlowSlot.entry()            ← 流量控制检查
  ↓
DegradeSlot.entry()         ← 熔断降级检查
  ↓
业务逻辑执行
  ↓
StatisticSlot.exit()        ← 统计成功/失败/RT
  ↓
Exit
```

## 总结

Slot Chain的设计优势：
1. **职责单一**：每个Slot只负责一种功能
2. **易扩展**：添加新Slot无需修改现有代码
3. **解耦**：Slot之间独立，互不影响
4. **灵活**：可以自定义Slot顺序

**核心Slot职责**：
- NodeSelectorSlot：构建调用树
- ClusterBuilderSlot：全局统计
- StatisticSlot：实时统计
- AuthoritySlot：黑白名单
- SystemSlot：系统保护
- FlowSlot：流量控制
- DegradeSlot：熔断降级
