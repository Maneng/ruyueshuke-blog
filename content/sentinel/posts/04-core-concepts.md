---
title: "核心概念详解：资源、规则、Context、Entry"
date: 2025-01-21T14:30:00+08:00
draft: false
tags: ["Sentinel", "核心概念", "资源", "规则"]
categories: ["技术"]
series: ["Sentinel从入门到精通"]
weight: 4
stage: 1
stageTitle: "基础入门篇"
description: "深入理解Sentinel的四大核心概念，建立正确的心智模型"
---

## 引言：为什么要理解核心概念

上一篇我们用20行代码实现了第一个Sentinel程序，是不是很简单？

但如果只停留在"会用"的层面，遇到复杂场景时你会发现：
- 为什么同一个资源名称，不同地方的限流会互相影响？
- 如何区分同一个接口的不同调用来源？
- Entry到底是什么？为什么必须调用exit()？
- Context有什么用？什么时候需要手动创建？

这些问题的答案，都藏在Sentinel的四大核心概念中：**资源（Resource）**、**规则（Rule）**、**上下文（Context）**、**入口（Entry）**。

理解了这些概念，你就掌握了Sentinel的"第一性原理"，可以灵活应对各种场景。

---

## 一、资源（Resource）：保护的目标

### 1.1 什么是资源

**资源是Sentinel保护的目标**，可以是任何你想保护的东西：

```
应用层面：
  ├─ 接口：/api/order/create
  ├─ 方法：OrderService.createOrder()
  ├─ 代码块：关键业务逻辑
  └─ URL：外部API调用

基础设施层面：
  ├─ 数据库连接
  ├─ Redis连接  ├─ 线程池
  └─ 消息队列
```

**核心理念**：只要是"有限的、需要保护的东西"，都可以定义为资源。

### 1.2 资源的定义方式

#### 方式1：编程方式（最灵活）

```java
Entry entry = null;
try {
    entry = SphU.entry("resourceName");
    // 受保护的代码
} catch (BlockException ex) {
    // 限流处理
} finally {
    if (entry != null) {
        entry.exit();
    }
}
```

**优点**：
- ✅ 灵活，可以保护任意代码块
- ✅ 可以传入自定义参数
- ✅ 性能最优（没有反射）

**缺点**：
- ❌ 代码侵入性强
- ❌ 需要手动管理Entry

#### 方式2：注解方式（最简洁）

```java
@SentinelResource(value = "getUserById",
                  blockHandler = "handleBlock")
public User getUserById(Long id) {
    return userMapper.selectById(id);
}

// 限流处理方法
public User handleBlock(Long id, BlockException ex) {
    return User.getDefault();
}
```

**优点**：
- ✅ 代码简洁，无侵入
- ✅ 自动管理Entry

**缺点**：
- ❌ 基于AOP，有反射开销
- ❌ blockHandler方法必须满足特定签名

#### 方式3：框架适配（最便捷）

```java
// Spring Cloud Gateway
@Bean
public RouteLocator customRouteLocator(RouteLocatorBuilder builder) {
    return builder.routes()
        .route("order_route", r -> r.path("/api/order/**")
            .uri("lb://order-service"))  // 自动作为资源
        .build();
}

// Dubbo
@DubboService  // 自动作为资源，资源名=接口名
public class OrderServiceImpl implements OrderService {
    // ...
}
```

**优点**：
- ✅ 零配置，自动适配
- ✅ 遵循框架规范

**缺点**：
- ❌ 灵活性受限于适配器

### 1.3 资源命名规范

**建议的命名规范**：

```java
// 接口资源：HTTP Method + URL
"GET:/api/order/{id}"
"POST:/api/order/create"

// 方法资源：类名.方法名
"com.example.OrderService.createOrder"
"OrderService.createOrder"  // 简化版

// RPC资源：接口名.方法名
"com.example.api.OrderService:createOrder"

// 数据库资源：表名.操作
"order_table:insert"
"order_table:select"
```

**命名原则**：
1. **唯一性**：同一资源在系统中只能有一个名称
2. **可读性**：一眼看出保护的是什么
3. **层次性**：用冒号或点分隔层级

---

## 二、规则（Rule）：保护的策略

### 2.1 规则的类型

Sentinel支持多种规则类型：

| 规则类型 | 作用 | 典型场景 |
|---------|------|---------|
| **FlowRule** | 流量控制 | 限制QPS、并发线程数 |
| **DegradeRule** | 熔断降级 | 慢调用、异常比例熔断 |
| **SystemRule** | 系统保护 | CPU、Load、RT自适应 |
| **AuthorityRule** | 授权规则 | 黑白名单 |
| **ParamFlowRule** | 热点参数限流 | 针对特定参数值限流 |

### 2.2 FlowRule详解（最常用）

```java
FlowRule rule = new FlowRule();

// 1. 资源名称（必填）
rule.setResource("orderService");

// 2. 限流类型（必填）
rule.setGrade(RuleConstant.FLOW_GRADE_QPS);  // QPS限流
// rule.setGrade(RuleConstant.FLOW_GRADE_THREAD);  // 线程数限流

// 3. 限流阈值（必填）
rule.setCount(100);  // 每秒100次 或 最多100个线程

// 4. 流控模式（可选，默认：直接）
rule.setStrategy(RuleConstant.STRATEGY_DIRECT);    // 直接限流
// rule.setStrategy(RuleConstant.STRATEGY_RELATE);    // 关联限流
// rule.setStrategy(RuleConstant.STRATEGY_CHAIN);     // 链路限流

// 5. 流控效果（可选，默认：快速失败）
rule.setControlBehavior(RuleConstant.CONTROL_BEHAVIOR_DEFAULT);  // 快速失败
// rule.setControlBehavior(RuleConstant.CONTROL_BEHAVIOR_WARM_UP);     // 预热
// rule.setControlBehavior(RuleConstant.CONTROL_BEHAVIOR_RATE_LIMITER); // 匀速排队

// 6. 其他参数
rule.setLimitApp("default");  // 来源应用（用于链路限流）
rule.setMaxQueueingTimeMs(500);  // 排队超时时间（匀速排队模式）
rule.setWarmUpPeriodSec(10);     // 预热时长（预热模式）
```

### 2.3 规则的加载与更新

#### 静态加载（硬编码）

```java
List<FlowRule> rules = new ArrayList<>();
rules.add(rule1);
rules.add(rule2);
FlowRuleManager.loadRules(rules);
```

**优点**：简单
**缺点**：修改需要重启服务

#### 动态加载（配置中心）

```java
// 从Nacos加载规则
ReadableDataSource<String, List<FlowRule>> flowRuleDataSource =
    new NacosDataSource<>(remoteAddress, groupId, dataId,
        source -> JSON.parseObject(source, new TypeReference<List<FlowRule>>() {}));
FlowRuleManager.register2Property(flowRuleDataSource.getProperty());
```

**优点**：实时生效，无需重启
**缺点**：需要配置中心

#### 规则更新时机

```
规则加载后
   ↓
立即生效（毫秒级）
   ↓
所有后续请求都会应用新规则
```

**注意**：规则更新不会影响正在执行的请求。

---

## 三、上下文（Context）：调用链路标识

### 3.1 Context的作用

Context用于标识**调用来源**和**调用链路**：

```
用户请求 A
    ↓
网关 (Context: gateway)
    ↓
订单服务.createOrder (Context: gateway)
    ├─ 查询库存 (Context: gateway → order.create)
    └─ 扣减库存 (Context: gateway → order.create)
```

**Context包含的信息**：
- **入口名称**（entryName）：当前上下文的标识
- **来源**（origin）：调用方的标识
- **调用链路**：从入口到当前资源的路径

### 3.2 默认Context

大多数情况下，Sentinel会自动创建Context，你不需要关心：

```java
// 自动创建名为 "sentinel_default_context" 的Context
Entry entry = SphU.entry("myResource");
```

### 3.3 手动创建Context

某些场景需要手动创建Context：

```java
// 场景1：区分不同的调用来源
ContextUtil.enter("order-create", "app-A");  // app-A调用
try {
    Entry entry = SphU.entry("createOrder");
    // 业务逻辑
    entry.exit();
} finally {
    ContextUtil.exit();  // 必须配对调用
}

ContextUtil.enter("order-create", "app-B");  // app-B调用
try {
    Entry entry = SphU.entry("createOrder");
    // 业务逻辑
    entry.exit();
} finally {
    ContextUtil.exit();
}
```

**应用场景**：
1. **多租户系统**：区分不同租户的调用
2. **灰度发布**：区分灰度流量和正常流量
3. **链路限流**：针对特定调用路径限流

### 3.4 Context与规则的关系

**链路模式限流**：

```java
// 规则：只限制从 "order-create" 上下文调用的 "checkStock"
FlowRule rule = new FlowRule();
rule.setResource("checkStock");
rule.setStrategy(RuleConstant.STRATEGY_CHAIN);
rule.setRefResource("order-create");  // 只限制这个调用路径
rule.setCount(10);
```

**效果**：

```
调用路径1：order-create → checkStock  ← 受限流保护
调用路径2：order-query → checkStock   ← 不受影响
```

---

## 四、入口（Entry）：资源的持有者

### 4.1 Entry的本质

Entry代表**对资源的一次访问**，类似于：
- 数据库连接（Connection）
- 文件句柄（FileHandle）
- 锁（Lock）

**核心特征**：
1. **有限性**：数量有限，需要管理
2. **必须释放**：用完后必须归还
3. **不可共享**：一个Entry对应一次访问

### 4.2 Entry的生命周期

```
创建: entry = SphU.entry("resource")
  ↓
检查: 是否通过限流/熔断规则
  ↓
通过: 返回Entry对象
  |
  ├─ 使用: 执行业务逻辑
  ↓
释放: entry.exit()
  ↓
统计: 更新QPS、RT等指标
```

### 4.3 Entry的正确使用

#### 错误示例1：忘记exit()

```java
// ❌ 错误：没有释放Entry
Entry entry = SphU.entry("test");
// 业务逻辑
// 忘记调用 entry.exit()
```

**后果**：
- 资源泄漏
- 统计数据不准确
- 可能导致限流失效

#### 错误示例2：exit()没有在finally

```java
// ❌ 错误：业务逻辑抛异常时，exit()不会执行
Entry entry = SphU.entry("test");
doSomething();  // 如果这里抛异常
entry.exit();   // 永远不会执行
```

#### 正确示例

```java
// ✅ 正确：始终在finally中调用exit()
Entry entry = null;
try {
    entry = SphU.entry("test");
    doSomething();
} catch (BlockException ex) {
    // 限流处理
} catch (Exception ex) {
    // 业务异常处理
} finally {
    if (entry != null) {
        entry.exit();  // 确保一定会执行
    }
}
```

### 4.4 Entry的嵌套

Entry是可以嵌套的：

```java
Entry outerEntry = null;
Entry innerEntry = null;
try {
    outerEntry = SphU.entry("outer");

    try {
        innerEntry = SphU.entry("inner");
        // 业务逻辑
    } finally {
        if (innerEntry != null) {
            innerEntry.exit();  // 先释放内层
        }
    }
} finally {
    if (outerEntry != null) {
        outerEntry.exit();  // 再释放外层
    }
}
```

**释放顺序**：必须按照**后进先出**（栈的方式）。

---

## 五、四者关系：完整的工作流程

### 5.1 关系图解

```
┌─────────────────────────────────────────┐
│   1. 定义资源                            │
│   resource = "orderService"             │
└────────────────┬────────────────────────┘
                 ↓
┌─────────────────────────────────────────┐
│   2. 配置规则                            │
│   rule.setResource("orderService")      │
│   rule.setCount(100)                    │
└────────────────┬────────────────────────┘
                 ↓
┌─────────────────────────────────────────┐
│   3. 创建Context（可选）                 │
│   ContextUtil.enter("order-create")     │
└────────────────┬────────────────────────┘
                 ↓
┌─────────────────────────────────────────┐
│   4. 获取Entry                           │
│   entry = SphU.entry("orderService")    │
│   ├─ 检查规则                            │
│   ├─ 通过：返回Entry                     │
│   └─ 拒绝：抛出BlockException           │
└────────────────┬────────────────────────┘
                 ↓
┌─────────────────────────────────────────┐
│   5. 执行业务逻辑                        │
│   orderService.create(order)            │
└────────────────┬────────────────────────┘
                 ↓
┌─────────────────────────────────────────┐
│   6. 释放Entry                           │
│   entry.exit()                          │
│   ├─ 更新统计数据（QPS、RT）            │
│   └─ 释放资源                            │
└────────────────┬────────────────────────┘
                 ↓
┌─────────────────────────────────────────┐
│   7. 退出Context（如果手动创建）         │
│   ContextUtil.exit()                    │
└─────────────────────────────────────────┘
```

### 5.2 实战案例：订单服务

```java
public class OrderService {

    public Order createOrder(Order order) {
        // 1. 创建Context，标识调用来源
        ContextUtil.enter("order-create", "web-app");

        Entry entry = null;
        try {
            // 2. 获取Entry，资源名称="createOrder"
            entry = SphU.entry("createOrder");

            // 3. 执行业务逻辑
            // 3.1 检查库存（嵌套资源）
            checkStock(order);

            // 3.2 创建订单
            Order savedOrder = orderMapper.insert(order);

            // 3.3 扣减库存
            deductStock(order);

            return savedOrder;

        } catch (BlockException ex) {
            // 4. 限流处理
            log.warn("订单创建被限流: {}", order);
            throw new BusinessException("系统繁忙，请稍后重试");

        } finally {
            // 5. 释放Entry
            if (entry != null) {
                entry.exit();
            }

            // 6. 退出Context
            ContextUtil.exit();
        }
    }

    private void checkStock(Order order) {
        Entry entry = null;
        try {
            // 嵌套资源：checkStock
            entry = SphU.entry("checkStock");

            // 调用库存服务
            StockService.check(order.getProductId(), order.getQuantity());

        } catch (BlockException ex) {
            log.warn("库存检查被限流");
            throw new BusinessException("系统繁忙");
        } finally {
            if (entry != null) {
                entry.exit();
            }
        }
    }
}
```

**对应的限流规则**：

```java
// 规则1：订单创建，每秒最多100个
FlowRule rule1 = new FlowRule();
rule1.setResource("createOrder");
rule1.setGrade(RuleConstant.FLOW_GRADE_QPS);
rule1.setCount(100);

// 规则2：库存检查，每秒最多1000个（允许更高）
FlowRule rule2 = new FlowRule();
rule2.setResource("checkStock");
rule2.setGrade(RuleConstant.FLOW_GRADE_QPS);
rule2.setCount(1000);

// 规则3：链路模式，只限制从order-create调用的checkStock
FlowRule rule3 = new FlowRule();
rule3.setResource("checkStock");
rule3.setStrategy(RuleConstant.STRATEGY_CHAIN);
rule3.setRefResource("order-create");  // 只限制这个链路
rule3.setCount(500);

FlowRuleManager.loadRules(Arrays.asList(rule1, rule2, rule3));
```

---

## 六、常见问题

### 6.1 同一个资源名称被多处使用

**问题**：

```java
// 文件A
Entry entry = SphU.entry("myResource");

// 文件B（完全不同的业务）
Entry entry = SphU.entry("myResource");  // 同名
```

**后果**：共享限流规则，互相影响

**解决**：
- 方案1：使用不同的资源名称（推荐）
- 方案2：使用链路模式区分调用来源

### 6.2 Context没有配对调用

**问题**：

```java
ContextUtil.enter("test");
// 业务逻辑
// 忘记调用 ContextUtil.exit()
```

**后果**：Context泄漏，影响后续请求

**解决**：始终在finally中调用exit()

```java
ContextUtil.enter("test");
try {
    // 业务逻辑
} finally {
    ContextUtil.exit();  // 确保一定执行
}
```

### 6.3 Entry的释放顺序错误

**问题**：

```java
Entry entry1 = SphU.entry("resource1");
Entry entry2 = SphU.entry("resource2");

entry1.exit();  // ❌ 错误：应该先释放entry2
entry2.exit();
```

**后果**：统计数据混乱

**解决**：按照栈的顺序（后进先出）

```java
entry2.exit();  // ✅ 正确：先释放后创建的
entry1.exit();
```

---

## 七、总结

**四大核心概念**：

1. **资源（Resource）**：保护的目标
   - 可以是接口、方法、代码块
   - 通过唯一名称标识
   - 支持多种定义方式

2. **规则（Rule）**：保护的策略
   - FlowRule、DegradeRule、SystemRule等
   - 可动态加载、实时生效
   - 一个资源可配置多个规则

3. **上下文（Context）**：调用链路标识
   - 标识调用来源和路径
   - 支持链路限流
   - 大多数场景自动创建

4. **入口（Entry）**：资源的持有者
   - 代表一次资源访问
   - 必须在finally中释放
   - 支持嵌套使用

**心智模型**：

```
资源是"什么"（保护目标）
规则是"怎么保护"（策略）
Context是"谁在调用"（调用方标识）
Entry是"访问凭证"（一次访问的句柄）
```

**下一篇预告**：《Sentinel Dashboard：可视化流控管理》

我们将学习Sentinel的可视化控制台，通过Dashboard实时查看流量监控、配置限流规则，无需修改代码。

---

## 思考题

1. 一个资源可以配置多种类型的规则吗？（如既有FlowRule，又有DegradeRule）
2. Context和Entry的生命周期有什么关系？
3. 如果不调用entry.exit()，会一直占用资源吗？

欢迎在评论区分享你的理解！
