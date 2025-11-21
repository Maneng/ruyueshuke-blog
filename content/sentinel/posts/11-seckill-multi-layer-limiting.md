---
title: "实战：电商秒杀系统的多层限流方案"
date: 2025-01-21T15:40:00+08:00
draft: false
tags: ["Sentinel", "秒杀系统", "多层限流", "实战案例"]
categories: ["技术"]
series: ["Sentinel从入门到精通"]
weight: 11
stage: 2
stageTitle: "流量控制深入篇"
description: "通过电商秒杀场景，学习如何设计和实现多层限流方案"
---

## 引言：秒杀系统的终极挑战

**2024年双11，某电商平台iPhone秒杀**：
- 库存：100台
- 参与人数：10万人
- 秒杀时间：10:00:00开始
- 预期流量：瞬间10万QPS

**不做限流的后果**：

```
10:00:00.000 - 10万请求同时到达
    ↓
数据库：100个连接池瞬间耗尽
    ↓
应用服务器：200个线程全部阻塞
    ↓
响应时间：从50ms飙升到30秒
    ↓
系统崩溃：所有接口无法响应
    ↓
用户体验：网站打不开，投诉无数
```

今天，我们将设计一个完整的秒杀系统限流方案，综合运用前面学到的所有知识。

---

## 一、场景分析

### 1.1 业务需求

```yaml
秒杀活动:
  商品: iPhone 15 Pro Max
  库存: 100台
  价格: 6999元（原价9999元）
  开始时间: 2024-11-11 10:00:00
  预计参与人数: 10万人

技术指标:
  系统容量: QPS 5000
  数据库连接: 100个
  应用线程池: 200个
  Redis: 10000 QPS
```

### 1.2 系统架构

```
用户（10万）
    ↓
CDN（静态资源）
    ↓
┌─────────────────────────────────┐
│ 第1层：网关限流                 │
│   - 总入口QPS：5000            │
│   - 限制单用户频率              │
└────────────┬────────────────────┘
             ↓
┌─────────────────────────────────┐
│ 第2层：接口限流                 │
│   - 秒杀接口：QPS 1000          │
│   - Warm Up预热                 │
└────────────┬────────────────────┘
             ↓
┌─────────────────────────────────┐
│ 第3层：热点限流                 │
│   - 商品维度：每个商品100 QPS   │
└────────────┬────────────────────┘
             ↓
┌─────────────────────────────────┐
│ 第4层：库存扣减限流             │
│   - 线程数限流：10个            │
│   - 匀速排队                    │
└────────────┬────────────────────┘
             ↓
      数据库（100个连接）
```

---

## 二、第1层：网关限流

### 2.1 网关层的职责

**目标**：
- 控制总入口流量
- 限制单个用户的请求频率
- 拦截恶意请求

**限流策略**：
```
1. 总QPS限流：5000
2. 单用户限流：每秒最多10次请求
3. IP黑名单：拦截恶意IP
```

### 2.2 Spring Cloud Gateway集成Sentinel

**依赖配置**：

```xml
<dependency>
    <groupId>com.alibaba.cloud</groupId>
    <artifactId>spring-cloud-starter-alibaba-sentinel</artifactId>
</dependency>

<dependency>
    <groupId>com.alibaba.cloud</groupId>
    <artifactId>spring-cloud-alibaba-sentinel-gateway</artifactId>
</dependency>
```

**网关配置**：

```java
@Configuration
public class GatewayConfig {

    @Bean
    public RouteLocator customRouteLocator(RouteLocatorBuilder builder) {
        return builder.routes()
            // 秒杀路由
            .route("seckill_route", r -> r
                .path("/api/seckill/**")
                .uri("lb://seckill-service"))
            .build();
    }

    @PostConstruct
    public void initGatewayRules() {
        Set<GatewayFlowRule> rules = new HashSet<>();

        // 规则1：总入口QPS限流
        GatewayFlowRule rule1 = new GatewayFlowRule("seckill_route")
            .setCount(5000)                              // 总QPS 5000
            .setIntervalSec(1);
        rules.add(rule1);

        // 规则2：单用户限流（基于参数）
        GatewayFlowRule rule2 = new GatewayFlowRule("seckill_route")
            .setCount(10)                                // 每个用户10 QPS
            .setIntervalSec(1)
            .setParamItem(new GatewayParamFlowItem()
                .setParseStrategy(SentinelGatewayConstants.PARAM_PARSE_STRATEGY_CLIENT_IP));
        rules.add(rule2);

        GatewayRuleManager.loadRules(rules);
    }

    @Bean
    public BlockRequestHandler blockRequestHandler() {
        return (exchange, t) -> {
            ServerHttpResponse response = exchange.getResponse();
            response.setStatusCode(HttpStatus.TOO_MANY_REQUESTS);
            response.getHeaders().setContentType(MediaType.APPLICATION_JSON);

            String message = "{\"code\":429,\"message\":\"系统繁忙，请稍后重试\"}";
            DataBuffer buffer = response.bufferFactory()
                .wrap(message.getBytes(StandardCharsets.UTF_8));

            return response.writeWith(Mono.just(buffer));
        };
    }
}
```

**效果**：
```
用户A：10:00:00 - 发送20个请求
  → 前10个通过
  → 后10个被限流（单用户限流）

10万用户同时请求：
  → 只有5000个请求进入后端（总QPS限流）
  → 其他95000个请求被网关拦截
```

---

## 三、第2层：秒杀接口限流

### 2.1 接口层的职责

**目标**：
- 保护秒杀接口
- 预热处理（Warm Up）
- 防止线程耗尽

**限流策略**：
```
1. QPS限流：1000
2. 线程数限流：50
3. Warm Up：5秒预热
```

### 2.2 秒杀接口实现

```java
@RestController
@RequestMapping("/api/seckill")
public class SeckillController {

    @Autowired
    private SeckillService seckillService;

    /**
     * 秒杀接口
     *
     * @param userId    用户ID
     * @param productId 商品ID
     */
    @PostMapping("/buy")
    @SentinelResource(value = "seckill_buy",
                      blockHandler = "handleSeckillBlock",
                      fallback = "handleSeckillFallback")
    public Result seckill(@RequestParam Long userId,
                          @RequestParam Long productId) {

        // 参数校验
        if (userId == null || productId == null) {
            return Result.fail("参数错误");
        }

        // 秒杀业务逻辑
        boolean success = seckillService.buy(userId, productId);

        if (success) {
            return Result.success("秒杀成功");
        } else {
            return Result.fail("商品已抢完");
        }
    }

    /**
     * 限流处理
     */
    public Result handleSeckillBlock(Long userId, Long productId,
                                     BlockException ex) {
        log.warn("秒杀限流: userId={}, productId={}", userId, productId);
        return Result.fail("系统繁忙，请稍后再试");
    }

    /**
     * 异常降级
     */
    public Result handleSeckillFallback(Long userId, Long productId,
                                        Throwable ex) {
        log.error("秒杀异常: userId={}, productId={}", userId, productId, ex);
        return Result.fail("系统异常，请稍后再试");
    }
}
```

### 2.3 接口限流规则

```java
@Configuration
public class SeckillFlowRuleConfig {

    @PostConstruct
    public void initSeckillFlowRules() {
        List<FlowRule> rules = new ArrayList<>();

        // 规则1：QPS限流 + Warm Up
        FlowRule rule1 = new FlowRule();
        rule1.setResource("seckill_buy");
        rule1.setGrade(RuleConstant.FLOW_GRADE_QPS);
        rule1.setCount(1000);                                   // QPS 1000

        // Warm Up：5秒预热（从333逐步到1000）
        rule1.setControlBehavior(RuleConstant.CONTROL_BEHAVIOR_WARM_UP);
        rule1.setWarmUpPeriodSec(5);
        rules.add(rule1);

        // 规则2：线程数限流
        FlowRule rule2 = new FlowRule();
        rule2.setResource("seckill_buy");
        rule2.setGrade(RuleConstant.FLOW_GRADE_THREAD);
        rule2.setCount(50);                                     // 最多50个线程
        rules.add(rule2);

        FlowRuleManager.loadRules(rules);
        log.info("秒杀接口限流规则已加载");
    }
}
```

**效果**：

```
9:59:55 - 预热开始：阈值=333 QPS
10:00:00 - 秒杀开始：阈值逐步增加
10:00:01 - 阈值=466 QPS
10:00:02 - 阈值=600 QPS
10:00:03 - 阈值=733 QPS
10:00:04 - 阈值=866 QPS
10:00:05 - 阈值=1000 QPS（达到最大值）

同时：线程数不超过50个
```

---

## 四、第3层：热点参数限流

### 4.1 热点限流的必要性

**问题场景**：

```
商品A（iPhone）：100台库存，10万人抢
商品B（iPad）：1000台库存，1000人抢

如果只有接口级限流：
  总QPS = 1000
  商品A：可能占用900 QPS
  商品B：只有100 QPS
  → 商品B的用户体验差
```

**解决方案**：**热点参数限流**

```
规则：每个商品最多100 QPS

商品A：100 QPS
商品B：100 QPS
...
商品J：100 QPS

总QPS：1000（10个商品 × 100）
```

### 4.2 热点限流配置

```java
@Configuration
public class HotParamFlowRuleConfig {

    @PostConstruct
    public void initHotParamRules() {
        List<ParamFlowRule> rules = new ArrayList<>();

        // 热点参数规则：按商品ID限流
        ParamFlowRule rule = new ParamFlowRule("seckill_buy")
            .setParamIdx(1)                                     // 第2个参数（productId）
            .setCount(100)                                      // 每个商品100 QPS
            .setGrade(RuleConstant.FLOW_GRADE_QPS)
            .setDurationInSec(1);

        // 参数例外项：热门商品可以更高
        List<ParamFlowItem> items = new ArrayList<>();
        ParamFlowItem item1 = new ParamFlowItem()
            .setObject("1001")                                  // 商品ID=1001（iPhone）
            .setClassType(Long.class.getName())
            .setCount(500);                                     // 允许500 QPS
        items.add(item1);

        rule.setParamFlowItemList(items);
        rules.add(rule);

        ParamFlowRuleManager.loadRules(rules);
        log.info("热点参数限流规则已加载");
    }
}
```

**秒杀接口调整**：

```java
@PostMapping("/buy")
public Result seckill(@RequestParam Long userId,
                      @RequestParam Long productId) {

    Entry entry = null;
    try {
        // 热点参数限流：传入参数
        entry = SphU.entry("seckill_buy",
                           EntryType.IN,
                           1,
                           userId, productId);  // 传入参数

        // 秒杀业务逻辑
        boolean success = seckillService.buy(userId, productId);

        return success ?
            Result.success("秒杀成功") :
            Result.fail("商品已抢完");

    } catch (BlockException ex) {
        log.warn("热点限流: productId={}", productId);
        return Result.fail("系统繁忙，请稍后再试");

    } finally {
        if (entry != null) {
            entry.exit();
        }
    }
}
```

**效果**：

```
商品1001（iPhone）：QPS限流500
商品1002（iPad）：QPS限流100
商品1003（MacBook）：QPS限流100
...

总QPS：800（500 + 100 + 100 + ...）
```

---

## 五、第4层：库存扣减限流

### 5.1 库存扣减的挑战

**问题**：

```
1000个并发请求扣减库存：
  → 1000个数据库连接
  → 数据库压力过大
  → 响应变慢甚至超时
```

**解决方案**：

```
1. 线程数限流：最多10个线程同时扣减
2. 匀速排队：排队等待，平滑扣减
3. Redis预扣减：先扣Redis，再扣数据库
```

### 5.2 库存服务实现

```java
@Service
public class StockService {

    @Autowired
    private StockMapper stockMapper;

    @Autowired
    private RedisTemplate<String, Integer> redisTemplate;

    /**
     * 扣减库存（多层保护）
     */
    @SentinelResource(value = "stock_deduct",
                      blockHandler = "handleDeductBlock")
    public boolean deductStock(Long productId, Integer quantity) {

        String key = "stock:" + productId;

        // 第1步：Redis预扣减（快速失败）
        Long remaining = redisTemplate.opsForValue()
            .decrement(key, quantity);

        if (remaining == null || remaining < 0) {
            // 库存不足，回滚
            redisTemplate.opsForValue().increment(key, quantity);
            log.warn("Redis库存不足: productId={}", productId);
            return false;
        }

        // 第2步：数据库扣减（限流保护）
        Entry entry = null;
        try {
            entry = SphU.entry("stock_deduct");

            // 扣减数据库库存
            int affected = stockMapper.deductStock(productId, quantity);

            if (affected > 0) {
                log.info("库存扣减成功: productId={}, quantity={}",
                    productId, quantity);
                return true;
            } else {
                // 数据库扣减失败，回滚Redis
                redisTemplate.opsForValue().increment(key, quantity);
                log.warn("数据库库存不足: productId={}", productId);
                return false;
            }

        } catch (BlockException ex) {
            // 被限流，回滚Redis
            redisTemplate.opsForValue().increment(key, quantity);
            log.warn("库存扣减被限流: productId={}", productId);
            return false;

        } finally {
            if (entry != null) {
                entry.exit();
            }
        }
    }

    public boolean handleDeductBlock(Long productId, Integer quantity,
                                     BlockException ex) {
        log.warn("库存扣减限流: productId={}", productId);
        return false;
    }
}
```

### 5.3 库存扣减限流规则

```java
@Configuration
public class StockFlowRuleConfig {

    @PostConstruct
    public void initStockFlowRules() {
        List<FlowRule> rules = new ArrayList<>();

        // 规则1：线程数限流
        FlowRule rule1 = new FlowRule();
        rule1.setResource("stock_deduct");
        rule1.setGrade(RuleConstant.FLOW_GRADE_THREAD);
        rule1.setCount(10);                                     // 最多10个线程
        rules.add(rule1);

        // 规则2：QPS限流 + 匀速排队
        FlowRule rule2 = new FlowRule();
        rule2.setResource("stock_deduct");
        rule2.setGrade(RuleConstant.FLOW_GRADE_QPS);
        rule2.setCount(100);                                    // 每秒100次

        // 匀速排队：平滑扣减
        rule2.setControlBehavior(RuleConstant.CONTROL_BEHAVIOR_RATE_LIMITER);
        rule2.setMaxQueueingTimeMs(500);                        // 最多排队500ms
        rules.add(rule2);

        FlowRuleManager.loadRules(rules);
        log.info("库存扣减限流规则已加载");
    }
}
```

**效果**：

```
瞬间1000个扣库存请求：
  → Redis预扣减：快速完成
  → 数据库扣减：
      - 最多10个线程同时执行
      - 匀速处理，每10ms一个
      - 超过500ms的请求被拒绝

数据库压力：
  并发连接数：最多10个（而不是1000个）
  ✅ 数据库稳定
```

---

## 六、完整流程图

```
用户（10万）
    ↓
┌──────────────────────────────────────┐
│ CDN：静态资源缓存                    │
└──────────┬───────────────────────────┘
           ↓
┌──────────────────────────────────────┐
│ 第1层：网关限流                      │
│ ✓ 总QPS：5000                        │
│ ✓ 单用户：10 QPS                     │
│ ❌ 拒绝：95000个请求                 │
└──────────┬───────────────────────────┘
           ↓ 5000 QPS
┌──────────────────────────────────────┐
│ 第2层：接口限流                      │
│ ✓ QPS：1000（Warm Up）               │
│ ✓ 线程数：50                         │
│ ❌ 拒绝：4000个请求                  │
└──────────┬───────────────────────────┘
           ↓ 1000 QPS
┌──────────────────────────────────────┐
│ 第3层：热点限流                      │
│ ✓ 每个商品：100 QPS                 │
│ ✓ iPhone（热门）：500 QPS           │
│ ❌ 超过阈值的请求被拒绝              │
└──────────┬───────────────────────────┘
           ↓ 800 QPS
┌──────────────────────────────────────┐
│ Redis预扣减                          │
│ ✓ 快速失败（库存不足直接拒绝）      │
└──────────┬───────────────────────────┘
           ↓ 100 QPS（实际有库存的）
┌──────────────────────────────────────┐
│ 第4层：库存扣减限流                  │
│ ✓ 线程数：10                         │
│ ✓ 匀速排队：每10ms一个               │
│ ✓ 保护数据库                         │
└──────────┬───────────────────────────┘
           ↓ 100 个成功订单
      数据库（稳定）
```

---

## 七、压测与验证

### 7.1 压测工具

```bash
# 使用JMeter压测

# 线程组配置：
# - 线程数：10000
# - Ramp-Up：10秒
# - 循环次数：10

# HTTP请求：
# POST http://localhost:8080/api/seckill/buy
# 参数：userId=随机, productId=1001
```

### 7.2 监控指标

**Dashboard监控**：

```
网关层：
  总QPS：5000（稳定）
  拒绝QPS：95000（95%被拦截）

接口层：
  通过QPS：1000（Warm Up后稳定）
  线程数：50（不超过阈值）
  拒绝QPS：4000

热点层：
  商品1001：500 QPS
  其他商品：100 QPS/商品

库存扣减：
  线程数：10（稳定）
  QPS：100（匀速）
  数据库连接：10（远低于100的极限）

数据库：
  QPS：100（稳定）
  响应时间：50ms（正常）
  连接数：10/100（10%使用率）
```

### 7.3 验证结果

**成功指标**：

```
✅ 系统稳定：全程无宕机
✅ 响应正常：RT保持在50-100ms
✅ 库存准确：最终100台全部售出，无超卖
✅ 用户体验：成功用户响应快，失败用户提示友好
```

---

## 八、总结

**多层限流的核心思想**：

1. **层层过滤，逐级保护**
   - 网关：粗粒度，拦截大部分无效流量
   - 接口：中粒度，保护核心业务
   - 热点：细粒度，公平分配资源
   - 数据库：底线保护，确保稳定

2. **不同策略组合使用**
   - QPS限流：控制请求总数
   - 线程数限流：防止资源耗尽
   - Warm Up：应对冷启动
   - 匀速排队：保护下游
   - 热点限流：公平分配

3. **性能与保护的平衡**
   - 不是限流越严越好
   - 要在系统容量内尽可能服务更多用户
   - 合理设置阈值（压测确定）

**最佳实践**：

```
1. 多层防护：不依赖单一层面
2. 预热机制：避免冷启动冲击
3. Redis预扣减：快速失败
4. 匀速排队：保护数据库
5. 监控告警：实时观察
6. 降级预案：最坏情况应对
```

**第二阶段完成**！

下一阶段我们将学习**熔断降级**，这是另一个核心功能，用于应对服务雪崩场景。

---

## 思考题

1. 如果不做网关限流，直接在接口层限流可以吗？
2. Redis预扣减后，数据库扣减失败，如何保证一致性？
3. 如果秒杀活动有多个商品，如何动态调整每个商品的限流阈值？

欢迎在评论区分享你的思考！
