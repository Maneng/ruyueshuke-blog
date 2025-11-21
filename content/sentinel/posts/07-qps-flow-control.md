---
title: "QPS限流：保护API的第一道防线"
date: 2025-01-21T15:00:00+08:00
draft: false
tags: ["Sentinel", "QPS限流", "接口保护"]
categories: ["技术"]
series: ["Sentinel从入门到精通"]
weight: 7
stage: 2
stageTitle: "流量控制深入篇"
description: "掌握基于QPS的限流规则配置，保护你的API接口"
---

## 引言：QPS限流是最常用的限流方式

上一篇我们深入理解了限流算法的原理，现在让我们回到实战：**如何用Sentinel保护你的API**？

答案是：**QPS限流**（Queries Per Second，每秒查询数）。

**为什么QPS限流最常用**？

```
指标对比：

QPS（每秒请求数）：
  ✅ 直观易懂
  ✅ 与业务指标对应
  ✅ 方便压测和监控

并发线程数：
  ❌ 不直观（多少算多？）
  ❌ 与业务指标不对应
  ❌ 难以设置合理阈值
```

今天我们将学习：QPS限流的配置方法、阈值设置技巧、压测验证、监控调优等实战内容。

---

## 一、QPS的概念与重要性

### 1.1 什么是QPS

**QPS（Queries Per Second）**：每秒查询数/请求数

```
1秒内收到100个请求 → QPS = 100
1秒内收到1000个请求 → QPS = 1000
```

**QPS与其他指标的关系**：

```
QPS = 总请求数 / 时间（秒）

并发数 = QPS × 平均响应时间（秒）
  例如：QPS=1000，RT=0.1s
  → 并发数 = 1000 × 0.1 = 100

吞吐量（TPS）：
  对于查询接口，TPS ≈ QPS
  对于事务接口，1个TPS可能包含多个QPS
```

### 1.2 为什么要限制QPS

**场景1：保护系统不被打垮**

```
系统极限：QPS = 5000
流量洪峰：QPS = 10000

不限流：
  → 响应时间从50ms变成5000ms
  → 线程池耗尽
  → 系统崩溃

限流到5000：
  → 拒绝5000个请求
  → 保证5000个请求正常响应（50ms）
  → 系统稳定
```

**场景2：公平分配资源**

```
用户A：正常调用，QPS=100
用户B：恶意爬虫，QPS=10000

不限流：
  → 用户B占用大量资源
  → 用户A的请求变慢甚至超时

限流：
  → 用户A：QPS=100（不受影响）
  → 用户B：QPS=1000（被限制）
```

---

## 二、配置QPS限流规则

### 2.1 编程方式配置

```java
import com.alibaba.csp.sentinel.slots.block.RuleConstant;
import com.alibaba.csp.sentinel.slots.block.flow.FlowRule;
import com.alibaba.csp.sentinel.slots.block.flow.FlowRuleManager;

import java.util.ArrayList;
import java.util.List;

public class FlowRuleInitializer {

    public static void initFlowRules() {
        List<FlowRule> rules = new ArrayList<>();

        // 规则1：订单查询接口，QPS限流
        FlowRule rule1 = new FlowRule();
        rule1.setResource("order_query");                    // 资源名称
        rule1.setGrade(RuleConstant.FLOW_GRADE_QPS);         // 限流类型：QPS
        rule1.setCount(100);                                  // QPS阈值：100
        rule1.setLimitApp("default");                         // 针对所有调用方
        rules.add(rule1);

        // 规则2：订单创建接口，QPS限流（更严格）
        FlowRule rule2 = new FlowRule();
        rule2.setResource("order_create");
        rule2.setGrade(RuleConstant.FLOW_GRADE_QPS);
        rule2.setCount(50);                                   // 写操作更严格
        rules.add(rule2);

        // 规则3：用户详情接口，QPS限流（更宽松）
        FlowRule rule3 = new FlowRule();
        rule3.setResource("user_detail");
        rule3.setGrade(RuleConstant.FLOW_GRADE_QPS);
        rule3.setCount(1000);                                 // 查询操作可以更高
        rules.add(rule3);

        // 加载规则
        FlowRuleManager.loadRules(rules);
        System.out.println("QPS限流规则已加载");
    }
}
```

**在应用启动时调用**：

```java
@SpringBootApplication
public class Application {

    public static void main(String[] args) {
        // 初始化限流规则
        FlowRuleInitializer.initFlowRules();

        // 启动应用
        SpringApplication.run(Application.class, args);
    }
}
```

### 2.2 Dashboard可视化配置

**步骤1：应用接入Dashboard**（参考第05篇）

**步骤2：触发资源调用**

```java
@RestController
@RequestMapping("/api/order")
public class OrderController {

    @GetMapping("/query")
    public Result queryOrder(@RequestParam Long orderId) {
        Entry entry = null;
        try {
            entry = SphU.entry("order_query");

            // 业务逻辑
            Order order = orderService.getById(orderId);
            return Result.success(order);

        } catch (BlockException ex) {
            return Result.fail("系统繁忙，请稍后重试");
        } finally {
            if (entry != null) {
                entry.exit();
            }
        }
    }
}
```

**步骤3：在Dashboard配置规则**

```
1. 打开Dashboard → 选择应用
2. 点击"流控规则" → "新增流控规则"
3. 配置：
   - 资源名：order_query
   - 阈值类型：QPS
   - 单机阈值：100
4. 点击"新增"
```

**规则立即生效**，无需重启应用。

### 2.3 注解方式配置

```java
@RestController
@RequestMapping("/api/order")
public class OrderController {

    @GetMapping("/query")
    @SentinelResource(value = "order_query",
                      blockHandler = "handleQueryBlock")
    public Result queryOrder(@RequestParam Long orderId) {
        Order order = orderService.getById(orderId);
        return Result.success(order);
    }

    // 限流处理方法
    public Result handleQueryBlock(Long orderId, BlockException ex) {
        log.warn("订单查询被限流: orderId={}", orderId);
        return Result.fail("系统繁忙，请稍后重试");
    }
}
```

**配置规则**（在Dashboard或配置文件中）：

```yaml
# application.yml
spring:
  cloud:
    sentinel:
      datasource:
        flow:
          nacos:
            server-addr: localhost:8848
            dataId: ${spring.application.name}-flow-rules
            groupId: SENTINEL_GROUP
            rule-type: flow
```

---

## 三、阈值设置技巧

### 3.1 如何确定合理的QPS阈值

**方法1：压测确定极限**

```bash
# 使用ab工具压测
ab -n 10000 -c 100 http://localhost:8080/api/order/query?orderId=123

# 输出：
# Requests per second: 1247.23 [#/sec]
# Time per request: 80.178 [ms]
```

**确定阈值**：

```
压测结果：极限QPS = 1247
安全系数：0.7-0.8（留有余量）
阈值设置：1247 × 0.8 = 998 ≈ 1000
```

**方法2：生产环境观察**

```
1. 先设置一个保守的值（如500）
2. 观察1-2周的实际QPS
3. 查看P99峰值QPS（如800）
4. 设置阈值 = P99 × 1.2 = 960 ≈ 1000
```

**方法3：计算理论值**

```
单机配置：
  - 4核CPU
  - 8G内存
  - 接口RT = 50ms

理论QPS计算：
  并发线程数 = 100（Tomcat默认）
  QPS = 并发数 / RT = 100 / 0.05 = 2000

实际设置：
  考虑GC、其他开销，打7折
  QPS阈值 = 2000 × 0.7 = 1400
```

### 3.2 不同接口的阈值策略

| 接口类型 | 建议阈值 | 理由 |
|---------|---------|------|
| **读接口** | 较高（1000-5000） | 响应快，可支持更高QPS |
| **写接口** | 较低（100-500） | 涉及数据库写入，保护数据库 |
| **复杂查询** | 极低（10-50） | RT长，防止线程耗尽 |
| **外部API调用** | 取决于对方限制 | 参考对方的限流策略 |

**示例配置**：

```java
// 订单查询（简单读）
rule.setResource("order_query");
rule.setCount(2000);

// 订单创建（写）
rule.setResource("order_create");
rule.setCount(500);

// 订单统计（复杂查询）
rule.setResource("order_statistics");
rule.setCount(50);

// 调用支付宝API（外部依赖）
rule.setResource("alipay_api");
rule.setCount(100);  // 参考支付宝的限流
```

### 3.3 阈值的动态调整

**场景1：活动期间临时提高**

```java
// 正常时期：QPS = 1000
FlowRule normalRule = new FlowRule();
normalRule.setResource("order_create");
normalRule.setCount(1000);

// 活动期间：QPS = 2000
FlowRule activityRule = new FlowRule();
activityRule.setResource("order_create");
activityRule.setCount(2000);

// 根据时间切换规则
if (isActivityTime()) {
    FlowRuleManager.loadRules(Collections.singletonList(activityRule));
} else {
    FlowRuleManager.loadRules(Collections.singletonList(normalRule));
}
```

**场景2：根据系统负载动态调整**

```java
// 监听系统负载
SystemLoad load = SystemLoadChecker.getCurrentLoad();

if (load.getCpu() > 0.8) {
    // CPU负载高，降低阈值
    rule.setCount(500);
} else if (load.getCpu() < 0.5) {
    // CPU负载低，提高阈值
    rule.setCount(2000);
} else {
    // 正常负载
    rule.setCount(1000);
}

FlowRuleManager.loadRules(Collections.singletonList(rule));
```

---

## 四、压测与验证

### 4.1 使用AB工具压测

**安装AB**：

```bash
# Mac
brew install httpd

# Ubuntu
sudo apt-get install apache2-utils

# 验证安装
ab -V
```

**基础压测**：

```bash
# -n：总请求数
# -c：并发数
ab -n 10000 -c 100 http://localhost:8080/api/order/query?orderId=123
```

**输出解读**：

```
Requests per second:    982.45 [#/sec] (mean)  ← 实际QPS
Time per request:       101.786 [ms] (mean)    ← 平均响应时间
Time per request:       1.018 [ms] (mean, across all concurrent requests)
Transfer rate:          195.23 [Kbytes/sec]

Percentage of requests served within a certain time (ms)
  50%     95
  66%    102
  75%    108
  80%    112
  90%    125
  95%    145
  98%    178
  99%    203
 100%    312 (longest request)
```

**验证限流效果**：

```bash
# 配置：QPS限流 = 100

# 压测：200 QPS
ab -n 2000 -c 20 -t 10 http://localhost:8080/api/order/query?orderId=123

# 预期结果：
# - 约1000个请求成功（100 QPS × 10秒）
# - 约1000个请求被限流（返回限流响应）
```

### 4.2 使用JMeter压测

**配置线程组**：

```
线程数：100
Ramp-Up时间：10秒
循环次数：100
```

**添加HTTP请求**：

```
服务器：localhost
端口：8080
路径：/api/order/query
参数：orderId=123
```

**添加监听器**：

```
- 查看结果树
- 聚合报告
- 图形结果
```

**运行并观察**：

```
样本数：10000
平均响应时间：105ms
吞吐量：952/sec  ← 实际QPS
错误率：10.2%    ← 被限流的请求比例
```

### 4.3 观察Dashboard实时监控

在压测过程中，打开Sentinel Dashboard：

```
实时监控：
  QPS：100  ← 稳定在阈值
  通过QPS：100
  拒绝QPS：50  ← 被限流的QPS

实时图表：
  ────────────────
  │ ▃▅▇▇▇▇▇▅▃  │  ← QPS曲线
  │────────────│
  0   5s   10s
```

---

## 五、监控与调优

### 5.1 监控指标

**核心指标**：

```
1. 通过QPS（passQPS）
   - 实际处理的请求数
   - 应该≤阈值

2. 拒绝QPS（blockQPS）
   - 被限流的请求数
   - 越低越好（说明阈值合理）

3. 成功QPS（successQPS）
   - 成功响应的请求数
   - 通过QPS - 异常QPS

4. 异常QPS（exceptionQPS）
   - 业务异常的请求数
   - 需要排查业务问题
```

**通过Dashboard查看**：

```
┌────────────────────────────────────────┐
│ 资源：order_query                       │
├────────────────────────────────────────┤
│ 通过QPS：    100 ↑                     │
│ 拒绝QPS：    15  ↑                     │
│ 异常QPS：    2   ↑                     │
│ RT（平均）： 52ms                       │
└────────────────────────────────────────┘
```

### 5.2 调优策略

**策略1：拒绝QPS过高 → 提高阈值**

```
观察：
  通过QPS：100
  拒绝QPS：50（拒绝率33%）

问题：阈值设置过低

调整：
  阈值：100 → 150
  观察1周后再调整
```

**策略2：RT升高 → 降低阈值**

```
观察：
  QPS：100
  RT：50ms → 200ms（升高4倍）

问题：系统负载过高

调整：
  阈值：100 → 80
  释放系统压力
```

**策略3：错误率升高 → 排查业务问题**

```
观察：
  通过QPS：100
  异常QPS：20（错误率20%）

问题：业务逻辑有问题，不是限流问题

调整：
  排查业务代码
  可能是数据库慢查询、外部API超时等
```

### 5.3 告警配置

**基于Prometheus的告警**：

```yaml
# 告警规则
groups:
  - name: sentinel_alerts
    rules:
      # 限流率过高告警
      - alert: HighBlockRate
        expr: |
          rate(sentinel_block_qps[1m]) /
          rate(sentinel_pass_qps[1m]) > 0.1
        for: 5m
        annotations:
          summary: "资源 {{ $labels.resource }} 限流率过高"
          description: "限流率: {{ $value }}"

      # RT过高告警
      - alert: HighResponseTime
        expr: sentinel_avg_rt > 500
        for: 2m
        annotations:
          summary: "资源 {{ $labels.resource }} 响应时间过高"
          description: "RT: {{ $value }}ms"
```

---

## 六、实战案例

### 6.1 案例：保护订单查询接口

**背景**：
- 订单查询接口：`/api/order/query`
- 数据库查询，RT=80ms
- 系统极限：QPS=1000
- 正常流量：QPS=500

**方案设计**：

```java
// 1. 配置QPS限流
FlowRule rule = new FlowRule();
rule.setResource("order_query");
rule.setGrade(RuleConstant.FLOW_GRADE_QPS);
rule.setCount(800);  // 极限的80%

FlowRuleManager.loadRules(Collections.singletonList(rule));

// 2. 接口实现
@RestController
public class OrderController {

    @GetMapping("/api/order/query")
    public Result queryOrder(@RequestParam Long orderId) {
        Entry entry = null;
        try {
            entry = SphU.entry("order_query");

            // 查询订单
            Order order = orderService.getById(orderId);
            return Result.success(order);

        } catch (BlockException ex) {
            // 限流降级：返回缓存数据
            Order cachedOrder = cacheService.get(orderId);
            if (cachedOrder != null) {
                return Result.success(cachedOrder, "数据来自缓存");
            }
            return Result.fail("系统繁忙，请稍后重试");

        } finally {
            if (entry != null) {
                entry.exit();
            }
        }
    }
}
```

**效果验证**：

```bash
# 压测：1200 QPS
ab -n 12000 -c 120 -t 10 http://localhost:8080/api/order/query?orderId=123

# 结果：
# - 通过：8000个（800 QPS × 10秒）
# - 限流：4000个
# - 系统稳定，RT保持在80ms
```

---

## 七、总结

**QPS限流的核心要点**：

1. **配置方式**：编程、Dashboard、注解三种方式
2. **阈值设置**：压测确定、生产观察、计算理论值
3. **不同接口**：读高写低、复杂查询更低
4. **动态调整**：根据活动、负载动态调整
5. **监控调优**：通过QPS、拒绝QPS、RT、错误率

**最佳实践**：

```
1. 保守设置：初始阈值 = 极限QPS × 0.7
2. 逐步调整：观察1-2周后调整
3. 留有余量：不要设置到极限
4. 分级限流：网关、应用、数据库多层保护
5. 监控告警：设置合理的告警阈值
```

**下一篇预告**：《并发线程数限流：防止资源耗尽》

我们将学习另一种限流方式——线程数限流，它与QPS限流有什么区别？什么时候应该用线程数限流？

---

## 思考题

1. 如果系统极限是1000 QPS，阈值应该设置多少？为什么？
2. 限流后的请求，应该返回什么HTTP状态码？200、429还是503？
3. QPS限流能防止慢SQL导致的系统崩溃吗？

欢迎在评论区分享你的理解！
