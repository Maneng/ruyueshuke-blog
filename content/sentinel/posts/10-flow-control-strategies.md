---
title: "流控策略：直接、关联、链路三种模式"
date: 2025-01-21T15:30:00+08:00
draft: false
tags: ["Sentinel", "流控策略", "关联限流", "链路限流"]
categories: ["技术"]
series: ["Sentinel从入门到精通"]
weight: 10
stage: 2
stageTitle: "流量控制深入篇"
description: "理解3种流控策略的原理和使用场景，实现更灵活的限流方案"
---

## 引言：不同的限流粒度

前面我们学习了流控效果（快速失败、Warm Up、匀速排队），解决了"如何处理超出阈值的请求"。

但还有一个问题：**限流的目标是谁**？

**场景思考**：

```
场景1：订单查询接口被限流，应该影响订单创建吗？
场景2：同一个接口，从网关调用和从定时任务调用，限流阈值应该一样吗？
场景3：写接口压力大，是否应该限制读接口来保护写接口？
```

这些问题的答案，藏在Sentinel的**三种流控策略**中：
1. **直接**：直接限流当前资源
2. **关联**：关联资源达到阈值时，限流当前资源
3. **链路**：从特定入口调用时才限流

---

## 一、直接模式：最常用的限流策略

### 1.1 原理

**直接模式**：直接对当前资源进行限流，最简单直接。

```
资源A：限流阈值100

请求 → 资源A
         ↓
    QPS统计
         ↓
   超过100？
    ├─ Yes → 限流
    └─ No  → 通过
```

**特点**：
- ✅ 最常用（95%的场景）
- ✅ 简单直接
- ✅ 独立限流，不影响其他资源

### 1.2 配置方式

```java
FlowRule rule = new FlowRule();
rule.setResource("order_query");                      // 资源名称
rule.setGrade(RuleConstant.FLOW_GRADE_QPS);           // QPS限流
rule.setCount(100);                                    // 阈值100

// 流控策略：直接（默认，可省略）
rule.setStrategy(RuleConstant.STRATEGY_DIRECT);

FlowRuleManager.loadRules(Collections.singletonList(rule));
```

### 1.3 适用场景

**大多数API接口**：

```java
@RestController
public class OrderController {

    // 订单查询：直接限流
    @GetMapping("/api/order/{id}")
    @SentinelResource("order_query")
    public Result query(@PathVariable Long id) {
        Order order = orderService.getById(id);
        return Result.success(order);
    }

    // 订单创建：直接限流
    @PostMapping("/api/order/create")
    @SentinelResource("order_create")
    public Result create(@RequestBody OrderDTO dto) {
        Order order = orderService.create(dto);
        return Result.success(order);
    }
}

// 配置规则
FlowRule rule1 = new FlowRule();
rule1.setResource("order_query");
rule1.setCount(1000);  // 查询接口1000 QPS

FlowRule rule2 = new FlowRule();
rule2.setResource("order_create");
rule2.setCount(500);   // 创建接口500 QPS

FlowRuleManager.loadRules(Arrays.asList(rule1, rule2));
```

---

## 二、关联模式：保护关联资源

### 2.1 原理

**关联模式**：当**关联资源**达到阈值时，限流**当前资源**。

```
配置：
  当前资源：read（读接口）
  关联资源：write（写接口）
  阈值：write的QPS达到100时，限流read

工作流程：
  write的QPS < 100：read正常通过
  write的QPS ≥ 100：read开始被限流
```

**图示**：

```
read接口 ──┐
           ├─ 都访问同一个数据库
write接口 ─┘

当write接口QPS过高时：
  → 数据库压力大
  → 限流read接口
  → 保证write接口正常
```

### 2.2 配置方式

```java
FlowRule rule = new FlowRule();
rule.setResource("read");                             // 当前资源：read
rule.setGrade(RuleConstant.FLOW_GRADE_QPS);
rule.setCount(100);

// 流控策略：关联
rule.setStrategy(RuleConstant.STRATEGY_RELATE);
rule.setRefResource("write");                         // 关联资源：write

FlowRuleManager.loadRules(Collections.singletonList(rule));
```

**规则解读**：
- 当`write`的QPS达到100时
- 限流`read`接口
- 保护`write`接口的正常执行

### 2.3 适用场景

**场景1：保护写接口（最典型）**

```java
@RestController
public class ProductController {

    // 商品查询（读）
    @GetMapping("/api/product/{id}")
    @SentinelResource("product_read")
    public Result read(@PathVariable Long id) {
        Product product = productService.getById(id);
        return Result.success(product);
    }

    // 商品库存扣减（写）
    @PostMapping("/api/product/deduct-stock")
    @SentinelResource("product_write")
    public Result deductStock(@RequestParam Long id,
                              @RequestParam Integer quantity) {
        productService.deductStock(id, quantity);
        return Result.success();
    }
}

// 配置关联限流
FlowRule rule = new FlowRule();
rule.setResource("product_read");                     // 读接口
rule.setStrategy(RuleConstant.STRATEGY_RELATE);
rule.setRefResource("product_write");                 // 关联写接口
rule.setGrade(RuleConstant.FLOW_GRADE_QPS);
rule.setCount(500);                                   // write达到500时限流read

FlowRuleManager.loadRules(Collections.singletonList(rule));
```

**效果**：

```
正常情况：
  write QPS = 100
  read QPS = 1000
  → read正常通过

秒杀场景：
  write QPS = 600（超过阈值500）
  read QPS = 1000
  → read被限流
  → 保证write接口（扣库存）正常执行
```

**场景2：优先级保护**

```java
/**
 * 场景：数据库连接池有限（100个连接）
 *
 * 优先级：
 *   高优先级：order_pay（支付）
 *   低优先级：order_query（查询）
 *
 * 策略：当支付请求多时，限制查询请求
 */
@RestController
public class OrderController {

    @PostMapping("/api/order/pay")
    @SentinelResource("order_pay")
    public Result pay(@RequestParam Long orderId) {
        // 支付逻辑（高优先级）
        return orderService.pay(orderId);
    }

    @GetMapping("/api/order/query")
    @SentinelResource("order_query")
    public Result query(@RequestParam Long orderId) {
        // 查询逻辑（低优先级）
        return orderService.query(orderId);
    }
}

// 配置关联限流
FlowRule rule = new FlowRule();
rule.setResource("order_query");                      // 低优先级接口
rule.setStrategy(RuleConstant.STRATEGY_RELATE);
rule.setRefResource("order_pay");                     // 关联高优先级接口
rule.setCount(50);                                    // pay达到50时限流query

FlowRuleManager.loadRules(Collections.singletonList(rule));
```

**场景3：保护共享资源**

```java
/**
 * 场景：Redis缓存，读写都访问同一个Redis
 *
 * 问题：写操作会导致缓存失效，引发缓存穿透
 * 策略：当写操作多时，限制读操作
 */
@Service
public class CacheService {

    @SentinelResource("cache_read")
    public String read(String key) {
        return redisTemplate.opsForValue().get(key);
    }

    @SentinelResource("cache_write")
    public void write(String key, String value) {
        redisTemplate.opsForValue().set(key, value);
        // 写操作会导致缓存失效
    }
}

// 配置关联限流
FlowRule rule = new FlowRule();
rule.setResource("cache_read");
rule.setStrategy(RuleConstant.STRATEGY_RELATE);
rule.setRefResource("cache_write");
rule.setCount(1000);  // write达到1000时限流read
```

---

## 三、链路模式：针对来源限流

### 3.1 原理

**链路模式**：只对从**特定入口**调用的资源进行限流。

```
场景：
  资源：checkStock（检查库存）

  调用路径1：/api/order/create → checkStock
  调用路径2：/api/cart/add → checkStock

链路限流：
  只限制从 /api/order/create 调用的 checkStock
  从 /api/cart/add 调用的 checkStock 不受影响
```

**图示**：

```
入口1：order/create ──┐
                      ├─→ checkStock
入口2：cart/add ──────┘

配置：限制从 order/create 调用的 checkStock

结果：
  order/create → checkStock：受限流 ❌
  cart/add → checkStock：不受影响 ✅
```

### 3.2 配置方式

**步骤1：开启链路模式（重要！）**

```yaml
# application.yml
spring:
  cloud:
    sentinel:
      web-context-unify: false  # 关闭context整合，开启链路模式
```

或者通过代码：

```java
// 启动类
@SpringBootApplication
public class Application {
    public static void main(String[] args) {
        System.setProperty("csp.sentinel.web.context.unify", "false");
        SpringApplication.run(Application.class, args);
    }
}
```

**步骤2：配置链路规则**

```java
FlowRule rule = new FlowRule();
rule.setResource("checkStock");                       // 资源名称
rule.setGrade(RuleConstant.FLOW_GRADE_QPS);
rule.setCount(50);

// 流控策略：链路
rule.setStrategy(RuleConstant.STRATEGY_CHAIN);
rule.setRefResource("order_create");                  // 入口资源

FlowRuleManager.loadRules(Collections.singletonList(rule));
```

**规则解读**：
- 只限制从`order_create`调用的`checkStock`
- 其他路径调用的`checkStock`不受影响

### 3.3 适用场景

**场景1：区分不同的调用入口**

```java
@Service
public class StockService {

    /**
     * 检查库存（被多个地方调用）
     */
    @SentinelResource("checkStock")
    public boolean checkStock(Long productId, Integer quantity) {
        Integer stock = stockMapper.getStock(productId);
        return stock >= quantity;
    }
}

@RestController
public class OrderController {

    @Autowired
    private StockService stockService;

    /**
     * 订单创建（高频，需要限流）
     */
    @PostMapping("/api/order/create")
    @SentinelResource("order_create")
    public Result createOrder(@RequestBody OrderDTO dto) {
        // 调用checkStock
        boolean hasStock = stockService.checkStock(
            dto.getProductId(), dto.getQuantity());

        if (!hasStock) {
            return Result.fail("库存不足");
        }

        // 创建订单
        Order order = orderService.create(dto);
        return Result.success(order);
    }

    /**
     * 购物车添加（低频，不需要限流）
     */
    @PostMapping("/api/cart/add")
    @SentinelResource("cart_add")
    public Result addToCart(@RequestBody CartDTO dto) {
        // 同样调用checkStock
        boolean hasStock = stockService.checkStock(
            dto.getProductId(), dto.getQuantity());

        if (!hasStock) {
            return Result.fail("库存不足");
        }

        // 添加购物车
        cartService.add(dto);
        return Result.success();
    }
}

// 配置链路限流
FlowRule rule = new FlowRule();
rule.setResource("checkStock");
rule.setStrategy(RuleConstant.STRATEGY_CHAIN);
rule.setRefResource("order_create");  // 只限制从order_create调用的
rule.setCount(100);

FlowRuleManager.loadRules(Collections.singletonList(rule));
```

**效果**：

```
order_create → checkStock：
  QPS > 100 → 限流 ❌

cart_add → checkStock：
  不受影响 ✅
```

**场景2：区分不同的应用来源**

```java
/**
 * 场景：同一个服务被多个应用调用
 *
 * 应用A：内部管理系统（低优先级）
 * 应用B：用户端APP（高优先级）
 *
 * 策略：限制应用A的调用，保证应用B
 */
@RestController
public class UserController {

    @GetMapping("/api/user/{id}")
    @SentinelResource("user_query")
    public Result getUser(@PathVariable Long id) {
        User user = userService.getById(id);
        return Result.success(user);
    }
}

// 配置链路限流（针对不同来源）
FlowRule rule = new FlowRule();
rule.setResource("user_query");
rule.setLimitApp("admin-app");  // 只限制admin-app的调用
rule.setCount(100);

FlowRuleManager.loadRules(Collections.singletonList(rule));
```

---

## 四、三种策略对比

### 4.1 对比表格

| 维度 | 直接 | 关联 | 链路 |
|------|------|------|------|
| **限流目标** | 当前资源 | 当前资源 | 当前资源（特定入口） |
| **触发条件** | 当前资源达到阈值 | 关联资源达到阈值 | 入口资源达到阈值 |
| **典型场景** | 普通API | 读写分离、优先级 | 区分调用来源 |
| **配置复杂度** | 简单 | 中等 | 复杂 |
| **使用频率** | 95% | 4% | 1% |

### 4.2 场景选择

```
需要限流？
  ↓
是否需要保护其他资源？
  ├─ Yes → 关联模式
  │    （如：写接口压力大，限制读接口）
  │
  └─ No → 是否需要区分调用来源？
      ├─ Yes → 链路模式
      │    （如：只限制从A入口的调用）
      │
      └─ No → 直接模式（默认）
```

### 4.3 实战组合

**综合案例：电商商品服务**

```java
@RestController
public class ProductController {

    @Autowired
    private ProductService productService;
    @Autowired
    private StockService stockService;

    /**
     * 商品详情查询（读）
     * 策略：直接限流
     */
    @GetMapping("/api/product/{id}")
    @SentinelResource("product_query")
    public Result query(@PathVariable Long id) {
        Product product = productService.getById(id);
        return Result.success(product);
    }

    /**
     * 库存扣减（写）
     * 策略：直接限流
     */
    @PostMapping("/api/product/deduct-stock")
    @SentinelResource("product_deduct_stock")
    public Result deductStock(@RequestParam Long id,
                              @RequestParam Integer quantity) {
        boolean success = stockService.deduct(id, quantity);
        return Result.success(success);
    }

    /**
     * 订单创建
     * 策略：调用checkStock时使用链路限流
     */
    @PostMapping("/api/order/create")
    @SentinelResource("order_create")
    public Result createOrder(@RequestBody OrderDTO dto) {
        // 检查库存
        boolean hasStock = stockService.checkStock(
            dto.getProductId(), dto.getQuantity());

        if (!hasStock) {
            return Result.fail("库存不足");
        }

        Order order = orderService.create(dto);
        return Result.success(order);
    }
}

// 配置规则
@Configuration
public class SentinelConfig {

    @PostConstruct
    public void initFlowRules() {
        List<FlowRule> rules = new ArrayList<>();

        // 规则1：商品查询 - 直接限流
        FlowRule rule1 = new FlowRule();
        rule1.setResource("product_query");
        rule1.setStrategy(RuleConstant.STRATEGY_DIRECT);
        rule1.setCount(1000);
        rules.add(rule1);

        // 规则2：商品查询 - 关联限流（当库存扣减压力大时，限流查询）
        FlowRule rule2 = new FlowRule();
        rule2.setResource("product_query");
        rule2.setStrategy(RuleConstant.STRATEGY_RELATE);
        rule2.setRefResource("product_deduct_stock");
        rule2.setCount(500);
        rules.add(rule2);

        // 规则3：库存检查 - 链路限流（只限制从order_create调用的）
        FlowRule rule3 = new FlowRule();
        rule3.setResource("checkStock");
        rule3.setStrategy(RuleConstant.STRATEGY_CHAIN);
        rule3.setRefResource("order_create");
        rule3.setCount(100);
        rules.add(rule3);

        FlowRuleManager.loadRules(rules);
    }
}
```

---

## 五、总结

**三种流控策略的核心特点**：

1. **直接模式**：直接限流当前资源
   - 最常用（95%场景）
   - 简单直接

2. **关联模式**：关联资源达到阈值时限流当前资源
   - 保护写接口
   - 优先级控制
   - 保护共享资源

3. **链路模式**：只限制特定入口的调用
   - 区分调用来源
   - 细粒度控制
   - 配置复杂

**选择建议**：

| 场景 | 推荐策略 |
|------|---------|
| 普通API限流 | 直接 |
| 保护写接口 | 关联 |
| 读写分离 | 关联 |
| 优先级控制 | 关联 |
| 区分调用来源 | 链路 |
| 多应用调用 | 链路 |

**下一篇预告**：《实战：电商秒杀系统的多层限流方案》

我们将综合运用前面学到的所有知识，设计一个完整的秒杀系统限流方案，包括网关限流、接口限流、热点限流等。

---

## 思考题

1. 一个资源可以同时配置多种流控策略吗？
2. 关联限流和链路限流的根本区别是什么？
3. 链路模式为什么需要关闭context整合？

欢迎在评论区分享你的理解！
