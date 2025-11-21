---
title: "Sentinel核心架构设计全景"
date: 2025-11-21T16:35:00+08:00
draft: false
tags: ["Sentinel", "架构设计", "核心原理"]
categories: ["技术"]
series: ["Sentinel从入门到精通"]
weight: 28
stage: 6
stageTitle: "架构原理篇"
description: "深入Sentinel核心架构，理解其设计思想"
---

## 整体架构

```
┌────────────────────────────────────────┐
│          Sentinel Client               │
├────────────────────────────────────────┤
│  API Layer (SphU/SphO/Entry)          │
├────────────────────────────────────────┤
│  Slot Chain (责任链模式)                │
│  ├─ NodeSelectorSlot                  │
│  ├─ ClusterBuilderSlot                │
│  ├─ StatisticSlot                     │
│  ├─ AuthoritySlot                     │
│  ├─ SystemSlot                        │
│  ├─ FlowSlot                          │
│  └─ DegradeSlot                       │
├────────────────────────────────────────┤
│  Metrics (滑动窗口统计)                 │
├────────────────────────────────────────┤
│  Rule Manager (规则管理)                │
└────────────────────────────────────────┘
```

## 核心组件

### 1. Entry（资源入口）

```java
public abstract class Entry implements AutoCloseable {
    private final long createTime;
    private Node curNode;
    private Node originNode;
    private Throwable error;

    protected Entry(ResourceWrapper resourceWrapper, ProcessorSlot<Object> chain, Context context) {
        this.resourceWrapper = resourceWrapper;
        this.chain = chain;
        this.context = context;
        this.createTime = TimeUtil.currentTimeMillis();
    }

    @Override
    public void close() {
        if (chain != null) {
            chain.exit(context, resourceWrapper, count, args);
        }
    }
}
```

**作用**：
- 代表一次资源调用
- 记录调用时间、统计数据
- 退出时清理资源

### 2. Context（调用上下文）

```java
public class Context {
    private final String name;
    private DefaultNode entranceNode;
    private Entry curEntry;
    private String origin = "";  // 调用来源

    public Context(DefaultNode entranceNode, String name) {
        this.name = name;
        this.entranceNode = entranceNode;
    }
}
```

**作用**：
- 标识调用链路
- 存储调用来源（用于授权规则）
- 维护调用栈

### 3. Node（统计节点）

```java
// 统计节点
public interface Node {
    long totalRequest();
    long blockRequest();
    long passRequest();
    long successRequest();
    long exceptionRequest();
    double passQps();
    double blockQps();
    double avgRt();
}

// 默认实现
public class StatisticNode implements Node {
    private transient Metric metric;  // 滑动窗口统计

    @Override
    public long totalRequest() {
        return metric.success() + metric.exception();
    }

    @Override
    public double passQps() {
        return metric.pass() / metric.getWindowIntervalInSec();
    }
}
```

**Node类型**：

| 类型 | 说明 | 用途 |
|-----|-----|-----|
| EntranceNode | 入口节点 | 每个Context一个 |
| DefaultNode | 默认节点 | 资源在调用链路中的统计节点 |
| ClusterNode | 集群节点 | 资源的全局统计节点 |

### 4. Slot（处理插槽）

责任链模式，每个Slot负责一种功能。

```java
public interface ProcessorSlot<T> {
    void entry(Context context, ResourceWrapper resourceWrapper, T param, int count, Object... args) throws Throwable;

    void fireEntry(Context context, ResourceWrapper resourceWrapper, Object obj, int count, Object... args) throws Throwable;

    void exit(Context context, ResourceWrapper resourceWrapper, int count, Object... args);

    void fireExit(Context context, ResourceWrapper resourceWrapper, int count, Object... args);
}
```

## 核心流程

### 调用流程

```java
public class SphU {
    public static Entry entry(String name) throws BlockException {
        return Env.sph.entry(name, EntryType.OUT, 1, OBJECTS0);
    }
}

// 实际执行
public class CtSph implements Sph {
    public Entry entry(ResourceWrapper resourceWrapper, int count, Object... args) throws BlockException {
        Context context = ContextUtil.getContext();
        if (context == null) {
            context = MyContextUtil.myEnter(Constants.CONTEXT_DEFAULT_NAME, "", resourceWrapper.getType());
        }

        Entry e = new CtEntry(resourceWrapper, chain, context);

        try {
            chain.entry(context, resourceWrapper, null, count, args);
        } catch (BlockException e1) {
            e.exit(count, args);
            throw e1;
        }

        return e;
    }
}
```

### Slot Chain执行顺序

```
请求进入
    ↓
1. NodeSelectorSlot: 构建调用树
    ↓
2. ClusterBuilderSlot: 构建ClusterNode
    ↓
3. StatisticSlot: 统计实时数据
    ↓
4. AuthoritySlot: 黑白名单检查
    ↓
5. SystemSlot: 系统保护检查
    ↓
6. FlowSlot: 流量控制检查
    ↓
7. DegradeSlot: 熔断降级检查
    ↓
业务逻辑执行
    ↓
StatisticSlot: 统计成功/失败
    ↓
请求结束
```

## 规则管理

### RuleManager

```java
public class FlowRuleManager {
    private static final Map<String, List<FlowRule>> flowRules = new ConcurrentHashMap<>();

    private static final RulePropertyListener<List<FlowRule>> LISTENER = new RulePropertyListener<List<FlowRule>>() {
        @Override
        public synchronized void configLoad(List<FlowRule> value) {
            Map<String, List<FlowRule>> rules = new ConcurrentHashMap<>();
            for (FlowRule rule : value) {
                String resourceName = rule.getResource();
                rules.computeIfAbsent(resourceName, k -> new ArrayList<>()).add(rule);
            }
            flowRules.clear();
            flowRules.putAll(rules);
        }
    };

    public static void loadRules(List<FlowRule> rules) {
        LISTENER.configLoad(rules);
    }

    public static List<FlowRule> getRules(String resource) {
        return flowRules.get(resource);
    }
}
```

### 动态数据源

```java
public interface ReadableDataSource<S, T> {
    T loadConfig() throws Exception;
    SentinelProperty<T> getProperty();
}

public class NacosDataSource<T> extends AbstractDataSource<String, T> {
    private ConfigService configService;
    private String dataId;
    private String groupId;

    @Override
    public String readSource() throws Exception {
        return configService.getConfig(dataId, groupId, 3000);
    }

    private void initNacosListener() {
        configService.addListener(dataId, groupId, new Listener() {
            @Override
            public void receiveConfigInfo(String configInfo) {
                T newValue = NacosDataSource.this.parser.convert(configInfo);
                getProperty().updateValue(newValue);
            }
        });
    }
}
```

## 统计数据流转

```
请求到达
    ↓
StatisticSlot.entry()
    ↓
node.addPassRequest(1)  // 记录通过
    ↓
LeapArray (滑动窗口)
    ↓
更新当前窗口统计
    ↓
业务逻辑执行
    ↓
StatisticSlot.exit()
    ↓
node.addRtAndSuccess(rt, 1)  // 记录RT和成功
    ↓
更新统计数据
```

## 扩展点

### 自定义Slot

```java
public class CustomSlot extends AbstractLinkedProcessorSlot<DefaultNode> {

    @Override
    public void entry(Context context, ResourceWrapper resourceWrapper, DefaultNode node, int count, Object... args) throws Throwable {
        // 自定义逻辑
        System.out.println("Before: " + resourceWrapper.getName());

        // 调用下一个Slot
        fireEntry(context, resourceWrapper, node, count, args);

        System.out.println("After: " + resourceWrapper.getName());
    }

    @Override
    public void exit(Context context, ResourceWrapper resourceWrapper, int count, Object... args) {
        // 退出逻辑
        fireExit(context, resourceWrapper, count, args);
    }
}

// 注册自定义Slot
public class CustomSlotChainBuilder implements SlotChainBuilder {
    @Override
    public ProcessorSlotChain build() {
        ProcessorSlotChain chain = new DefaultProcessorSlotChain();
        chain.addLast(new NodeSelectorSlot());
        chain.addLast(new ClusterBuilderSlot());
        chain.addLast(new StatisticSlot());
        chain.addLast(new CustomSlot());  // 添加自定义Slot
        chain.addLast(new FlowSlot());
        chain.addLast(new DegradeSlot());
        return chain;
    }
}
```

### 自定义规则

```java
public class CustomRule extends AbstractRule {
    private String customField;

    public String getCustomField() {
        return customField;
    }

    public void setCustomField(String customField) {
        this.customField = customField;
    }
}

public class CustomRuleManager {
    private static final Map<String, List<CustomRule>> rules = new ConcurrentHashMap<>();

    public static void loadRules(List<CustomRule> newRules) {
        // 加载规则
    }

    public static List<CustomRule> getRules(String resource) {
        return rules.get(resource);
    }
}
```

## 设计模式

1. **责任链模式**：Slot Chain
2. **策略模式**：不同的流控效果、熔断策略
3. **模板方法**：AbstractRule、AbstractSlot
4. **观察者模式**：规则变更监听
5. **单例模式**：各种Manager

## 总结

Sentinel架构核心：
1. **Entry**：资源入口，代表一次调用
2. **Context**：调用上下文，标识链路
3. **Node**：统计节点，记录指标
4. **Slot Chain**：责任链，各司其职
5. **RuleManager**：规则管理，动态更新
6. **滑动窗口**：高效统计，实时计算

**设计亮点**：
- 责任链模式，易扩展
- 滑动窗口统计，高性能
- 动态数据源，实时更新
- 多维度统计，精确控制
