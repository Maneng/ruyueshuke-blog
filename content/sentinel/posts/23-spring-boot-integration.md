---
title: "Spring Boot集成最佳实践"
date: 2025-11-20T16:25:00+08:00
draft: false
tags: ["Sentinel", "Spring Boot", "集成"]
categories: ["技术"]
series: ["Sentinel从入门到精通"]
weight: 23
stage: 5
stageTitle: "框架集成篇"
description: "学习Sentinel与Spring Boot的完整集成方案"
---

## Spring Boot Starter快速集成

### 添加依赖

```xml
<dependency>
    <groupId>com.alibaba.cloud</groupId>
    <artifactId>spring-cloud-starter-alibaba-sentinel</artifactId>
    <version>2022.0.0.0</version>
</dependency>
```

### 配置文件

```yaml
spring:
  application:
    name: order-service
  cloud:
    sentinel:
      transport:
        dashboard: localhost:8080
        port: 8719
      eager: true  # 启动时立即初始化

      # Web限流
      filter:
        enabled: true
        url-patterns: /**

      # 数据源配置
      datasource:
        flow:
          nacos:
            server-addr: localhost:8848
            dataId: ${spring.application.name}-flow-rules
            groupId: SENTINEL_GROUP
            rule-type: flow
```

## @SentinelResource注解使用

### 基础用法

```java
@Service
public class OrderService {

    @SentinelResource(
        value = "createOrder",
        blockHandler = "handleBlock",
        fallback = "handleFallback"
    )
    public Order createOrder(OrderDTO dto) {
        return orderDao.save(dto);
    }

    // 限流/熔断处理
    public Order handleBlock(OrderDTO dto, BlockException ex) {
        throw new BusinessException("系统繁忙，请稍后重试");
    }

    // 业务异常处理
    public Order handleFallback(OrderDTO dto, Throwable ex) {
        log.error("创建订单失败", ex);
        throw new BusinessException("订单创建失败");
    }
}
```

### 异常类分离

```java
public class OrderBlockHandler {
    public static Order handleBlock(OrderDTO dto, BlockException ex) {
        return Order.builder().status("BLOCKED").build();
    }
}

public class OrderFallback {
    public static Order handleFallback(OrderDTO dto, Throwable ex) {
        return Order.builder().status("FALLBACK").build();
    }
}

@Service
public class OrderService {
    @SentinelResource(
        value = "createOrder",
        blockHandlerClass = OrderBlockHandler.class,
        blockHandler = "handleBlock",
        fallbackClass = OrderFallback.class,
        fallback = "handleFallback"
    )
    public Order createOrder(OrderDTO dto) {
        return orderDao.save(dto);
    }
}
```

## RestTemplate集成

```java
@Configuration
public class RestTemplateConfig {

    @Bean
    @SentinelRestTemplate(
        blockHandler = "handleBlock",
        blockHandlerClass = RestTemplateBlockHandler.class,
        fallback = "handleFallback",
        fallbackClass = RestTemplateFallback.class
    )
    public RestTemplate restTemplate() {
        return new RestTemplate();
    }
}
```

## Feign集成

### 添加依赖

```xml
<dependency>
    <groupId>com.alibaba.cloud</groupId>
    <artifactId>spring-cloud-starter-alibaba-sentinel</artifactId>
</dependency>
<dependency>
    <groupId>org.springframework.cloud</groupId>
    <artifactId>spring-cloud-starter-openfeign</artifactId>
</dependency>
```

### 配置

```yaml
feign:
  sentinel:
    enabled: true
```

### 使用

```java
@FeignClient(name = "product-service", fallback = ProductServiceFallback.class)
public interface ProductService {
    @GetMapping("/product/{id}")
    Product getProduct(@PathVariable Long id);
}

@Component
public class ProductServiceFallback implements ProductService {
    @Override
    public Product getProduct(Long id) {
        return Product.builder()
            .id(id)
            .name("商品服务暂时不可用")
            .build();
    }
}
```

## 全局异常处理

```java
@RestControllerAdvice
public class SentinelExceptionHandler {

    @ExceptionHandler(FlowException.class)
    public Result handleFlowException(FlowException e) {
        return Result.error(429, "请求过于频繁");
    }

    @ExceptionHandler(DegradeException.class)
    public Result handleDegradeException(DegradeException e) {
        return Result.error(503, "服务降级");
    }

    @ExceptionHandler(BlockException.class)
    public Result handleBlockException(BlockException e) {
        return Result.error(500, "系统保护");
    }
}
```

## 规则初始化

```java
@Configuration
public class SentinelRuleConfig {

    @PostConstruct
    public void initRules() {
        initFlowRules();
        initDegradeRules();
        initSystemRules();
    }

    private void initFlowRules() {
        List<FlowRule> rules = new ArrayList<>();

        FlowRule rule = new FlowRule();
        rule.setResource("createOrder");
        rule.setGrade(RuleConstant.FLOW_GRADE_QPS);
        rule.setCount(100);
        rules.add(rule);

        FlowRuleManager.loadRules(rules);
    }

    private void initDegradeRules() {
        List<DegradeRule> rules = new ArrayList<>();

        DegradeRule rule = new DegradeRule();
        rule.setResource("callProductService");
        rule.setGrade(RuleConstant.DEGRADE_GRADE_RT);
        rule.setCount(1000);
        rule.setSlowRatioThreshold(0.5);
        rules.add(rule);

        DegradeRuleManager.loadRules(rules);
    }

    private void initSystemRules() {
        List<SystemRule> rules = new ArrayList<>();

        SystemRule rule = new SystemRule();
        rule.setHighestCpuUsage(0.8);
        rules.add(rule);

        SystemRuleManager.loadRules(rules);
    }
}
```

## 完整实战案例

```java
@SpringBootApplication
@EnableFeignClients
public class OrderServiceApplication {
    public static void main(String[] args) {
        SpringApplication.run(OrderServiceApplication.class, args);
    }
}

@RestController
@RequestMapping("/order")
public class OrderController {

    @Autowired
    private OrderService orderService;

    @PostMapping("/create")
    @SentinelResource(value = "orderCreate", blockHandler = "handleBlock")
    public Result createOrder(@RequestBody OrderDTO dto) {
        Order order = orderService.createOrder(dto);
        return Result.success(order);
    }

    public Result handleBlock(OrderDTO dto, BlockException ex) {
        return Result.error(429, "订单创建繁忙，请稍后重试");
    }
}

@Service
public class OrderService {

    @Autowired
    private ProductService productService;

    @SentinelResource(value = "createOrderService", fallback = "handleFallback")
    public Order createOrder(OrderDTO dto) {
        // 调用商品服务
        Product product = productService.getProduct(dto.getProductId());

        // 创建订单
        Order order = new Order();
        order.setProductId(product.getId());
        order.setUserId(dto.getUserId());
        return orderDao.save(order);
    }

    public Order handleFallback(OrderDTO dto, Throwable ex) {
        log.error("订单创建失败", ex);
        throw new BusinessException("订单创建失败，请重试");
    }
}
```

## 总结

Spring Boot集成Sentinel的关键点：
1. 使用Spring Cloud Alibaba Starter快速集成
2. @SentinelResource注解保护业务方法
3. Feign自动支持熔断降级
4. 全局异常处理统一响应格式
5. 从Nacos动态加载规则
