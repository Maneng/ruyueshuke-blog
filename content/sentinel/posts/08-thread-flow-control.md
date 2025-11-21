---
title: "并发线程数限流：防止资源耗尽"
date: 2025-01-21T15:10:00+08:00
draft: false
tags: ["Sentinel", "线程数限流", "资源保护"]
categories: ["技术"]
series: ["Sentinel从入门到精通"]
weight: 8
stage: 2
stageTitle: "流量控制深入篇"
description: "学习并发线程数限流，防止慢接口导致资源耗尽"
---

## 引言：QPS限流不能解决所有问题

上一篇我们学习了QPS限流，它是最常用的限流方式。但有些场景下，QPS限流并不够用：

**场景：调用第三方支付API**

```java
// 配置：QPS限流 = 100
@GetMapping("/api/payment/query")
public Result queryPayment(@RequestParam String orderId) {
    Entry entry = SphU.entry("payment_query");

    // 调用第三方API（RT=2000ms，非常慢！）
    PaymentResult result = thirdPartyApi.query(orderId);

    entry.exit();
    return Result.success(result);
}
```

**问题分析**：

```
QPS = 100
RT = 2000ms（2秒）

需要的线程数 = QPS × RT = 100 × 2 = 200个线程

但Tomcat默认线程池只有200个！

结果：
  → 200个线程全部被占用
  → 其他接口无法响应
  → 系统"假死"
```

**核心问题**：**QPS限流只管数量，不管时间**。对于慢接口，即使QPS不高，也可能耗尽线程资源。

今天我们将学习**线程数限流**，专门应对这类场景。

---

## 一、线程数限流的原理

### 1.1 什么是线程数限流

**线程数限流**：限制同时处理某个资源的线程数量。

```
资源：payment_query
线程数限流：最多10个线程

第1-10个请求：线程1-10处理中
第11个请求：被限流（因为已经有10个线程在处理）
第1个请求处理完毕：线程1释放
第11个请求：可以被线程1处理
```

**图示**：

```
请求1  → 线程1 [处理中...2秒]
请求2  → 线程2 [处理中...2秒]
...
请求10 → 线程10 [处理中...2秒]
请求11 → ❌ 被限流（线程池满）
```

### 1.2 线程数限流 vs QPS限流

| 维度 | QPS限流 | 线程数限流 |
|------|---------|-----------|
| **关注点** | 请求数量 | 并发数量 |
| **计算方式** | 时间窗口内的请求总数 | 当前正在处理的请求数 |
| **适用场景** | 快速接口（RT<100ms） | 慢速接口（RT>1s） |
| **保护目标** | 防止流量过大 | 防止线程耗尽 |
| **限流时机** | 请求到达时 | 请求到达时 |

**核心区别**：

```
QPS限流：
  统计过去1秒的请求数
  如果≥阈值，拒绝新请求

线程数限流：
  统计当前正在处理的请求数
  如果≥阈值，拒绝新请求
```

---

## 二、配置线程数限流规则

### 2.1 编程方式配置

```java
import com.alibaba.csp.sentinel.slots.block.RuleConstant;
import com.alibaba.csp.sentinel.slots.block.flow.FlowRule;
import com.alibaba.csp.sentinel.slots.block.flow.FlowRuleManager;

public class ThreadFlowRuleInit {

    public static void initThreadFlowRules() {
        List<FlowRule> rules = new ArrayList<>();

        // 规则1：支付查询接口，线程数限流
        FlowRule rule1 = new FlowRule();
        rule1.setResource("payment_query");
        rule1.setGrade(RuleConstant.FLOW_GRADE_THREAD);  // 限流类型：线程数
        rule1.setCount(10);                               // 最多10个线程
        rules.add(rule1);

        // 规则2：报表导出接口，线程数限流（更少）
        FlowRule rule2 = new FlowRule();
        rule2.setResource("report_export");
        rule2.setGrade(RuleConstant.FLOW_GRADE_THREAD);
        rule2.setCount(5);                                // 最多5个线程（导出耗时长）
        rules.add(rule2);

        // 加载规则
        FlowRuleManager.loadRules(rules);
        System.out.println("线程数限流规则已加载");
    }
}
```

### 2.2 Dashboard配置

```
1. 打开Dashboard → 选择应用
2. 点击"流控规则" → "新增流控规则"
3. 配置：
   - 资源名：payment_query
   - 阈值类型：并发线程数
   - 单机阈值：10
4. 点击"新增"
```

### 2.3 注解方式配置

```java
@RestController
public class PaymentController {

    @GetMapping("/api/payment/query")
    @SentinelResource(value = "payment_query",
                      blockHandler = "handleBlock")
    public Result queryPayment(@RequestParam String orderId) {
        // 调用第三方API（慢接口）
        PaymentResult result = thirdPartyApi.query(orderId);
        return Result.success(result);
    }

    public Result handleBlock(String orderId, BlockException ex) {
        log.warn("支付查询被限流: orderId={}", orderId);
        return Result.fail("系统繁忙，请稍后重试");
    }
}
```

---

## 三、线程数限流的统计原理

### 3.1 Entry的计数机制

```java
// Sentinel的内部实现（简化版）
public class EntryCounter {
    private AtomicInteger activeThreadCount = new AtomicInteger(0);

    public boolean tryAcquire(int maxThread) {
        int current = activeThreadCount.get();
        if (current < maxThread) {
            activeThreadCount.incrementAndGet();  // 线程数+1
            return true;  // 通过
        } else {
            return false;  // 限流
        }
    }

    public void release() {
        activeThreadCount.decrementAndGet();  // 线程数-1
    }
}
```

**完整流程**：

```
1. 请求到达
     ↓
2. entry = SphU.entry("resource")
     ↓ 内部：activeThreadCount++
3. 判断：activeThreadCount ≤ maxThread ?
     ↓ Yes
4. 执行业务逻辑
     ↓
5. entry.exit()
     ↓ 内部：activeThreadCount--
6. 完成
```

### 3.2 为什么必须调用exit()

**场景：忘记调用exit()**

```java
Entry entry = SphU.entry("test");
// 业务逻辑
// 忘记调用 entry.exit()
```

**后果**：

```
第1个请求：activeThreadCount = 0 → 1（通过）
第2个请求：activeThreadCount = 1 → 2（通过）
...
第10个请求：activeThreadCount = 9 → 10（通过）
第11个请求：activeThreadCount = 10，拒绝！

问题：虽然前10个请求已经完成，但计数器没有减少
结果：后续所有请求都被限流（永久限流！）
```

**正确做法**：

```java
Entry entry = null;
try {
    entry = SphU.entry("test");
    // 业务逻辑
} finally {
    if (entry != null) {
        entry.exit();  // 必须在finally中调用
    }
}
```

---

## 四、适用场景与实战

### 4.1 场景1：调用慢速外部API

**背景**：
- 调用支付宝查询接口
- RT = 2000ms（2秒）
- QPS = 50

**问题分析**：

```
不限流：
  需要线程数 = QPS × RT = 50 × 2 = 100个
  Tomcat线程池200个 → 被占用50%
  其他接口受影响

QPS限流到50：
  依然需要100个线程
  问题没解决

线程数限流到20：
  最多20个线程处理支付查询
  其他180个线程可用
  ✅ 问题解决
```

**代码实现**：

```java
@Service
public class PaymentService {

    @SentinelResource(value = "payment_query",
                      blockHandler = "handleBlock")
    public PaymentResult queryPayment(String orderId) {
        // 调用支付宝API（慢接口，RT=2s）
        return alipayClient.query(orderId);
    }

    public PaymentResult handleBlock(String orderId, BlockException ex) {
        // 降级：返回"处理中"状态
        PaymentResult result = new PaymentResult();
        result.setStatus("PROCESSING");
        result.setMessage("查询处理中，请稍后再试");
        return result;
    }
}

// 配置线程数限流
FlowRule rule = new FlowRule();
rule.setResource("payment_query");
rule.setGrade(RuleConstant.FLOW_GRADE_THREAD);
rule.setCount(20);  // 最多20个线程
```

### 4.2 场景2：数据库慢查询

**背景**：
- 订单统计接口（复杂SQL）
- RT = 5000ms（5秒）
- QPS = 10

**问题分析**：

```
不限流：
  需要线程数 = 10 × 5 = 50个
  数据库连接池100个 → 被占用50%

线程数限流到10：
  最多10个并发查询
  数据库压力可控
  ✅ 保护数据库
```

**代码实现**：

```java
@RestController
public class ReportController {

    @GetMapping("/api/report/order-statistics")
    @SentinelResource(value = "order_statistics",
                      blockHandler = "handleBlock")
    public Result getStatistics(@RequestParam String startDate,
                                @RequestParam String endDate) {
        // 复杂SQL查询（慢查询，RT=5s）
        Statistics stats = reportService.calculateStatistics(startDate, endDate);
        return Result.success(stats);
    }

    public Result handleBlock(String startDate, String endDate, BlockException ex) {
        return Result.fail("报表生成中，请稍后查看");
    }
}

// 配置线程数限流
FlowRule rule = new FlowRule();
rule.setResource("order_statistics");
rule.setGrade(RuleConstant.FLOW_GRADE_THREAD);
rule.setCount(5);  // 最多5个线程（保护数据库）
```

### 4.3 场景3：文件上传/下载

**背景**：
- 大文件下载接口
- RT = 10000ms（10秒）
- QPS = 5

**问题分析**：

```
不限流：
  需要线程数 = 5 × 10 = 50个
  带宽限制 + 内存占用

线程数限流到10：
  最多10个并发下载
  带宽可控，内存可控
  ✅ 系统稳定
```

**代码实现**：

```java
@RestController
public class FileController {

    @GetMapping("/api/file/download")
    @SentinelResource(value = "file_download",
                      blockHandler = "handleBlock")
    public void downloadFile(@RequestParam String fileId,
                             HttpServletResponse response) throws IOException {
        // 大文件下载（RT=10s）
        File file = fileService.getFile(fileId);

        response.setContentType("application/octet-stream");
        response.setHeader("Content-Disposition",
            "attachment; filename=" + file.getName());

        try (InputStream in = new FileInputStream(file);
             OutputStream out = response.getOutputStream()) {
            IOUtils.copy(in, out);
        }
    }

    public void handleBlock(String fileId, HttpServletResponse response,
                           BlockException ex) throws IOException {
        response.setStatus(503);
        response.getWriter().write("下载服务繁忙，请稍后重试");
    }
}

// 配置线程数限流
FlowRule rule = new FlowRule();
rule.setResource("file_download");
rule.setGrade(RuleConstant.FLOW_GRADE_THREAD);
rule.setCount(10);  // 最多10个并发下载
```

---

## 五、QPS限流 + 线程数限流组合

### 5.1 为什么需要组合使用

**单独使用的问题**：

```
只用QPS限流：
  ✅ 防止请求过多
  ❌ 慢接口会耗尽线程

只用线程数限流：
  ✅ 防止线程耗尽
  ❌ 快速请求可能过载
```

**组合使用的优势**：

```
QPS限流 + 线程数限流：
  第一道防线：QPS限流（控制请求总数）
  第二道防线：线程数限流（保护线程资源）
  双重保护 ✅
```

### 5.2 组合配置示例

```java
// 场景：第三方API调用
// RT = 1000ms
// 期望QPS = 100

// 规则1：QPS限流
FlowRule qpsRule = new FlowRule();
qpsRule.setResource("third_party_api");
qpsRule.setGrade(RuleConstant.FLOW_GRADE_QPS);
qpsRule.setCount(100);  // 每秒最多100个请求

// 规则2：线程数限流
FlowRule threadRule = new FlowRule();
threadRule.setResource("third_party_api");
threadRule.setGrade(RuleConstant.FLOW_GRADE_THREAD);
threadRule.setCount(50);  // 最多50个线程（QPS × RT × 0.5）

// 加载规则
FlowRuleManager.loadRules(Arrays.asList(qpsRule, threadRule));
```

**效果分析**：

```
正常情况（RT=1s）：
  QPS=100，需要100个线程
  → 线程数限流生效（限制到50个）
  → 实际QPS=50
  → ✅ 保护线程资源

异常情况（第三方API慢，RT=5s）：
  如果只有QPS限流：
    QPS=100，需要500个线程
    → ❌ 线程耗尽

  有线程数限流：
    QPS=100，但线程数限制50个
    → 实际QPS=10（50个线程 / 5秒）
    → ✅ 系统稳定
```

### 5.3 阈值计算公式

**线程数阈值的计算**：

```
线程数 = QPS × RT（秒）

保险系数：0.5-0.7（留有余量）

实际阈值 = QPS × RT × 保险系数
```

**示例**：

```
场景1：
  QPS = 100
  RT = 0.5s
  线程数 = 100 × 0.5 × 0.7 = 35

场景2：
  QPS = 50
  RT = 2s
  线程数 = 50 × 2 × 0.7 = 70

场景3：
  QPS = 10
  RT = 5s
  线程数 = 10 × 5 × 0.7 = 35
```

---

## 六、监控与调优

### 6.1 监控指标

**Dashboard监控**：

```
┌────────────────────────────────────────┐
│ 资源：payment_query                     │
├────────────────────────────────────────┤
│ 当前线程数：  8 / 10  ← 8个线程处理中  │
│ 通过QPS：     50                        │
│ 拒绝QPS：     5   ← 被线程数限流       │
│ RT（平均）：  2000ms                    │
└────────────────────────────────────────┘
```

**关键指标**：

```
1. 当前线程数
   - 实时显示正在处理的线程数
   - 接近阈值 → 可能需要调整

2. 拒绝QPS
   - 被线程数限流的请求
   - 过高 → 阈值设置过低

3. RT（响应时间）
   - 平均响应时间
   - 升高 → 下游服务变慢
```

### 6.2 调优策略

**策略1：拒绝率过高 → 提高线程数阈值**

```
观察：
  线程数阈值：10
  当前线程数：10（一直满）
  拒绝QPS：20（拒绝率40%）

问题：阈值过低

调整：
  阈值：10 → 15
  观察拒绝率是否下降
```

**策略2：RT突然升高 → 下游服务有问题**

```
观察：
  RT：500ms → 5000ms（升高10倍）
  当前线程数：10（满）
  拒绝QPS：从0变成50

问题：下游服务变慢

调整：
  方案1：降低线程数（保护自己）
  方案2：启用熔断（后续章节讲解）
```

**策略3：线程数一直很低 → 阈值过高**

```
观察：
  线程数阈值：50
  当前线程数：最高5（很低）
  拒绝QPS：0

问题：阈值设置过高（浪费）

调整：
  阈值：50 → 10
  释放配置资源
```

---

## 七、常见问题

### 7.1 如何选择QPS限流还是线程数限流？

**决策树**：

```
接口RT < 100ms ?
  ├─ Yes → 使用QPS限流
  └─ No → RT > 1s ?
      ├─ Yes → 使用线程数限流
      └─ No → QPS限流 + 线程数限流
```

**具体场景**：

| 场景 | RT | 推荐方案 |
|------|----|---------|
| 查询接口（缓存） | 10ms | QPS限流 |
| 查询接口（数据库） | 50ms | QPS限流 |
| 复杂查询 | 500ms | QPS + 线程数 |
| 第三方API | 2000ms | 线程数限流 |
| 文件下载 | 10000ms | 线程数限流 |

### 7.2 线程数限流会阻塞吗？

**不会阻塞，直接拒绝**：

```java
Entry entry = SphU.entry("test");  // 不会阻塞
// 如果超过线程数阈值，直接抛出BlockException
```

**如果需要阻塞等待**：

```java
// 方式1：自己实现等待
while (true) {
    try {
        entry = SphU.entry("test");
        break;  // 获取成功
    } catch (BlockException ex) {
        Thread.sleep(100);  // 等待100ms重试
    }
}

// 方式2：使用Guava的RateLimiter（支持阻塞）
RateLimiter limiter = RateLimiter.create(10);
limiter.acquire();  // 阻塞等待
```

### 7.3 线程数限流与线程池的区别

**线程池**：
- 限制整个应用的线程数
- 所有接口共享
- 配置在Tomcat/Jetty层面

**线程数限流**：
- 限制单个资源的线程数
- 不同资源独立配置
- 配置在Sentinel层面

**对比**：

```
Tomcat线程池：200个
  ├─ 资源A（线程数限流：10个）
  ├─ 资源B（线程数限流：20个）
  ├─ 资源C（线程数限流：30个）
  └─ 其他资源：140个
```

---

## 八、总结

**线程数限流的核心要点**：

1. **适用场景**：慢接口（RT>1s）、外部API调用、文件上传下载
2. **原理**：统计当前正在处理的线程数，超过阈值拒绝
3. **与QPS区别**：关注并发数，不是请求数
4. **组合使用**：QPS限流+线程数限流，双重保护
5. **阈值计算**：线程数 = QPS × RT × 0.7

**最佳实践**：

```
1. 快速接口：只用QPS限流
2. 慢速接口：线程数限流为主
3. 组合使用：QPS限流（第一道防线）+ 线程数限流（第二道防线）
4. 监控调优：关注当前线程数、拒绝率、RT
5. 必须调用exit()：否则计数器永远不会减少
```

**下一篇预告**：《流控效果：快速失败、Warm Up、匀速排队》

我们将学习Sentinel的三种流控效果，它们有什么区别？什么时候用Warm Up？什么时候用匀速排队？

---

## 思考题

1. 如果QPS=100，RT=2s，线程数阈值应该设置多少？
2. 为什么慢接口更适合用线程数限流而不是QPS限流？
3. 线程数限流能防止数据库连接池耗尽吗？

欢迎在评论区分享你的理解！
