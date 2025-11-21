---
title: "Dubbo服务流控：RPC调用的保护"
date: 2025-11-20T16:29:00+08:00
draft: false
tags: ["Sentinel", "Dubbo", "RPC"]
categories: ["技术"]
series: ["Sentinel从入门到精通"]
weight: 25
stage: 5
stageTitle: "框架集成篇"
description: "学习Sentinel与Dubbo的集成，保护RPC调用"
---

## Dubbo + Sentinel集成

### 添加依赖

```xml
<!-- Dubbo -->
<dependency>
    <groupId>org.apache.dubbo</groupId>
    <artifactId>dubbo-spring-boot-starter</artifactId>
    <version>3.2.0</version>
</dependency>

<!-- Sentinel Dubbo适配器 -->
<dependency>
    <groupId>com.alibaba.csp</groupId>
    <artifactId>sentinel-apache-dubbo3-adapter</artifactId>
    <version>1.8.6</version>
</dependency>
```

### 配置文件

```yaml
dubbo:
  application:
    name: order-service
  registry:
    address: nacos://localhost:8848
  protocol:
    name: dubbo
    port: 20880
  consumer:
    timeout: 3000
    check: false

spring:
  cloud:
    sentinel:
      transport:
        dashboard: localhost:8080
```

## 服务提供者保护

### 定义接口

```java
public interface ProductService {
    Product getProduct(Long id);
    List<Product> listProducts(int page, int size);
}
```

### 实现类

```java
@DubboService
public class ProductServiceImpl implements ProductService {

    @Override
    @SentinelResource(value = "getProduct", blockHandler = "handleBlock")
    public Product getProduct(Long id) {
        return productDao.findById(id);
    }

    @Override
    @SentinelResource(value = "listProducts")
    public List<Product> listProducts(int page, int size) {
        return productDao.findAll(page, size);
    }

    public Product handleBlock(Long id, BlockException ex) {
        return Product.builder()
            .id(id)
            .name("商品服务限流")
            .build();
    }
}
```

### 配置限流规则

```java
@Configuration
public class ProviderSentinelConfig {

    @PostConstruct
    public void initRules() {
        List<FlowRule> rules = new ArrayList<>();

        // 保护getProduct接口
        FlowRule rule1 = new FlowRule();
        rule1.setResource("getProduct");
        rule1.setGrade(RuleConstant.FLOW_GRADE_QPS);
        rule1.setCount(1000);
        rules.add(rule1);

        // 保护listProducts接口
        FlowRule rule2 = new FlowRule();
        rule2.setResource("listProducts");
        rule2.setGrade(RuleConstant.FLOW_GRADE_QPS);
        rule2.setCount(500);
        rules.add(rule2);

        FlowRuleManager.loadRules(rules);
    }
}
```

## 服务消费者保护

### 引用服务

```java
@Service
public class OrderService {

    @DubboReference
    private ProductService productService;

    @SentinelResource(
        value = "createOrder",
        fallback = "handleFallback"
    )
    public Order createOrder(Long productId, int quantity) {
        // 调用Dubbo服务
        Product product = productService.getProduct(productId);

        Order order = new Order();
        order.setProductId(product.getId());
        order.setQuantity(quantity);
        return orderDao.save(order);
    }

    public Order handleFallback(Long productId, int quantity, Throwable ex) {
        log.error("订单创建失败", ex);
        throw new BusinessException("商品服务不可用");
    }
}
```

### 配置熔断规则

```java
@Configuration
public class ConsumerSentinelConfig {

    @PostConstruct
    public void initRules() {
        List<DegradeRule> rules = new ArrayList<>();

        DegradeRule rule = new DegradeRule();
        rule.setResource("com.example.ProductService:getProduct(java.lang.Long)");
        rule.setGrade(RuleConstant.DEGRADE_GRADE_RT);
        rule.setCount(1000);  // RT > 1秒
        rule.setSlowRatioThreshold(0.5);
        rule.setTimeWindow(10);
        rules.add(rule);

        DegradeRuleManager.loadRules(rules);
    }
}
```

## 基于来源限流

### 场景：不同消费者不同限流

```java
// 提供者配置
FlowRule rule = new FlowRule();
rule.setResource("getProduct");
rule.setGrade(RuleConstant.FLOW_GRADE_QPS);
rule.setCount(100);
rule.setLimitApp("order-service");  // 只对订单服务限流100
```

### 自定义来源解析

```java
public class DubboOriginParser implements RequestOriginParser {
    @Override
    public String parseOrigin(HttpServletRequest request) {
        // 从Dubbo上下文获取调用方应用名
        String application = RpcContext.getContext()
            .getAttachment("application");
        return application != null ? application : "unknown";
    }
}
```

## Dubbo Filter实现

Sentinel通过Dubbo Filter自动拦截，资源名格式：

**提供者侧**：
```
接口全限定名:方法名(参数类型)
示例：com.example.ProductService:getProduct(java.lang.Long)
```

**消费者侧**：
```
接口全限定名:方法名(参数类型)
示例：com.example.ProductService:getProduct(java.lang.Long)
```

## 完整实战案例

### 商品服务（Provider）

```java
@SpringBootApplication
@EnableDubbo
public class ProductServiceApplication {
    public static void main(String[] args) {
        SpringApplication.run(ProductServiceApplication.class, args);
    }
}

@DubboService(version = "1.0.0", timeout = 3000)
public class ProductServiceImpl implements ProductService {

    @Override
    @SentinelResource(value = "getProduct", blockHandler = "handleBlock")
    public Product getProduct(Long id) {
        return productDao.findById(id);
    }

    public Product handleBlock(Long id, BlockException ex) {
        log.warn("商品查询被限流：id={}", id);
        return Product.builder()
            .id(id)
            .name("商品查询繁忙")
            .build();
    }
}

@Configuration
public class ProductSentinelConfig {
    @PostConstruct
    public void initRules() {
        List<FlowRule> flowRules = new ArrayList<>();

        // 1. 总QPS限流
        FlowRule totalRule = new FlowRule();
        totalRule.setResource("com.example.ProductService:getProduct(java.lang.Long)");
        totalRule.setGrade(RuleConstant.FLOW_GRADE_QPS);
        totalRule.setCount(1000);
        flowRules.add(totalRule);

        // 2. 针对订单服务限流
        FlowRule orderRule = new FlowRule();
        orderRule.setResource("com.example.ProductService:getProduct(java.lang.Long)");
        orderRule.setGrade(RuleConstant.FLOW_GRADE_QPS);
        orderRule.setCount(500);
        orderRule.setLimitApp("order-service");
        flowRules.add(orderRule);

        FlowRuleManager.loadRules(flowRules);
    }
}
```

### 订单服务（Consumer）

```java
@SpringBootApplication
@EnableDubbo
public class OrderServiceApplication {
    public static void main(String[] args) {
        SpringApplication.run(OrderServiceApplication.class, args);
    }
}

@Service
public class OrderService {

    @DubboReference(version = "1.0.0", check = false)
    private ProductService productService;

    @SentinelResource(value = "createOrder", fallback = "createOrderFallback")
    public Order createOrder(Long productId, int quantity) {
        // 调用商品服务
        Product product = productService.getProduct(productId);

        Order order = new Order();
        order.setProductId(product.getId());
        order.setQuantity(quantity);
        return orderDao.save(order);
    }

    public Order createOrderFallback(Long productId, int quantity, Throwable ex) {
        log.error("创建订单失败", ex);
        throw new BusinessException("商品服务不可用，请稍后重试");
    }
}

@Configuration
public class OrderSentinelConfig {
    @PostConstruct
    public void initRules() {
        List<DegradeRule> rules = new ArrayList<>();

        // 对商品服务熔断
        DegradeRule rule = new DegradeRule();
        rule.setResource("com.example.ProductService:getProduct(java.lang.Long)");
        rule.setGrade(RuleConstant.DEGRADE_GRADE_RT);
        rule.setCount(1000);
        rule.setSlowRatioThreshold(0.5);
        rule.setTimeWindow(10);
        rules.add(rule);

        DegradeRuleManager.loadRules(rules);
    }
}
```

## Dubbo泛化调用保护

```java
ReferenceConfig<GenericService> reference = new ReferenceConfig<>();
reference.setInterface("com.example.ProductService");
reference.setGeneric("true");

GenericService genericService = reference.get();

@SentinelResource(value = "genericCall")
public Object callGeneric(String method, String[] paramTypes, Object[] args) {
    return genericService.$invoke(method, paramTypes, args);
}
```

## 总结

Dubbo + Sentinel集成要点：
1. 自动拦截Dubbo调用，无需手动埋点
2. 提供者限流保护服务端
3. 消费者熔断保护调用端
4. 支持基于来源的差异化限流
5. 资源名格式：接口:方法(参数)
