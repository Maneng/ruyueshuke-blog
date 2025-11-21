---
title: "Spring Cloud Alibaba深度集成"
date: 2025-11-21T16:27:00+08:00
draft: false
tags: ["Sentinel", "Spring Cloud Alibaba", "微服务"]
categories: ["技术"]
series: ["Sentinel从入门到精通"]
weight: 24
stage: 5
stageTitle: "框架集成篇"
description: "Sentinel在Spring Cloud Alibaba微服务体系中的完整应用"
---

## 微服务架构整体方案

```
┌─────────────┐
│   Nacos     │  ← 服务注册、配置中心
└─────────────┘
       ↓
┌─────────────┐
│  Gateway    │  ← 网关（Sentinel限流）
└─────────────┘
       ↓
┌─────────────┐
│ 订单服务     │  ← Sentinel流控、熔断
└─────────────┘
       ↓
┌─────────────┐
│ 商品服务     │  ← Sentinel流控、熔断
└─────────────┘
```

## 完整依赖配置

```xml
<dependencyManagement>
    <dependencies>
        <dependency>
            <groupId>com.alibaba.cloud</groupId>
            <artifactId>spring-cloud-alibaba-dependencies</artifactId>
            <version>2022.0.0.0</version>
            <type>pom</type>
            <scope>import</scope>
        </dependency>
    </dependencies>
</dependencyManagement>

<dependencies>
    <!-- Nacos服务发现 -->
    <dependency>
        <groupId>com.alibaba.cloud</groupId>
        <artifactId>spring-cloud-starter-alibaba-nacos-discovery</artifactId>
    </dependency>

    <!-- Nacos配置中心 -->
    <dependency>
        <groupId>com.alibaba.cloud</groupId>
        <artifactId>spring-cloud-starter-alibaba-nacos-config</artifactId>
    </dependency>

    <!-- Sentinel -->
    <dependency>
        <groupId>com.alibaba.cloud</groupId>
        <artifactId>spring-cloud-starter-alibaba-sentinel</artifactId>
    </dependency>

    <!-- OpenFeign -->
    <dependency>
        <groupId>org.springframework.cloud</groupId>
        <artifactId>spring-cloud-starter-openfeign</artifactId>
    </dependency>

    <!-- LoadBalancer -->
    <dependency>
        <groupId>org.springframework.cloud</groupId>
        <artifactId>spring-cloud-starter-loadbalancer</artifactId>
    </dependency>
</dependencies>
```

## Nacos + Sentinel配置

```yaml
spring:
  application:
    name: order-service
  cloud:
    # Nacos配置
    nacos:
      discovery:
        server-addr: localhost:8848
        namespace: dev
      config:
        server-addr: localhost:8848
        namespace: dev
        file-extension: yml

    # Sentinel配置
    sentinel:
      transport:
        dashboard: localhost:8080
      datasource:
        flow:
          nacos:
            server-addr: localhost:8848
            dataId: ${spring.application.name}-flow-rules
            groupId: SENTINEL_GROUP
            rule-type: flow
            namespace: dev
        degrade:
          nacos:
            server-addr: localhost:8848
            dataId: ${spring.application.name}-degrade-rules
            groupId: SENTINEL_GROUP
            rule-type: degrade
            namespace: dev

# Feign配置
feign:
  sentinel:
    enabled: true
  client:
    config:
      default:
        connectTimeout: 5000
        readTimeout: 5000
```

## 服务间调用保护

### 订单服务调用商品服务

```java
@FeignClient(
    name = "product-service",
    fallback = ProductServiceFallback.class,
    fallbackFactory = ProductServiceFallbackFactory.class
)
public interface ProductService {
    @GetMapping("/product/{id}")
    Product getProduct(@PathVariable Long id);
}

// Fallback实现
@Component
public class ProductServiceFallback implements ProductService {
    @Override
    public Product getProduct(Long id) {
        return Product.builder()
            .id(id)
            .name("商品服务暂时不可用")
            .price(0.0)
            .build();
    }
}

// FallbackFactory（可以获取异常信息）
@Component
public class ProductServiceFallbackFactory implements FallbackFactory<ProductService> {
    @Override
    public ProductService create(Throwable cause) {
        return new ProductService() {
            @Override
            public Product getProduct(Long id) {
                log.error("调用商品服务失败：{}", cause.getMessage());
                return Product.builder()
                    .id(id)
                    .name("商品服务异常：" + cause.getMessage())
                    .build();
            }
        };
    }
}
```

## 链路限流

### 场景：多个接口调用同一个服务

```java
@Service
public class OrderService {

    @Autowired
    private ProductService productService;

    // 接口1：创建订单
    @SentinelResource(value = "createOrder")
    public Order createOrder(Long productId) {
        // 调用商品服务
        getProductInfo(productId);
        return new Order();
    }

    // 接口2：查询订单
    @SentinelResource(value = "queryOrder")
    public Order queryOrder(Long orderId) {
        Order order = orderDao.findById(orderId);
        // 调用商品服务
        getProductInfo(order.getProductId());
        return order;
    }

    // 公共方法：获取商品信息
    @SentinelResource(value = "getProductInfo", blockHandler = "handleBlock")
    private Product getProductInfo(Long productId) {
        return productService.getProduct(productId);
    }

    private Product handleBlock(Long productId, BlockException ex) {
        return Product.builder().id(productId).name("商品信息获取受限").build();
    }
}
```

### 配置链路限流

```java
FlowRule rule = new FlowRule();
rule.setResource("getProductInfo");
rule.setGrade(RuleConstant.FLOW_GRADE_QPS);
rule.setCount(100);
rule.setStrategy(RuleConstant.STRATEGY_CHAIN);
rule.setRefResource("createOrder"); // 只对createOrder链路限流
FlowRuleManager.loadRules(Collections.singletonList(rule));
```

## 服务熔断配置

```yaml
# 在Nacos中配置
# order-service-degrade-rules
[
  {
    "resource": "product-service",
    "grade": 0,
    "count": 1000,
    "timeWindow": 10,
    "minRequestAmount": 5,
    "statIntervalMs": 10000,
    "slowRatioThreshold": 0.5
  },
  {
    "resource": "inventory-service",
    "grade": 1,
    "count": 0.3,
    "timeWindow": 10,
    "minRequestAmount": 5,
    "statIntervalMs": 10000
  }
]
```

## Gateway集成

```yaml
spring:
  cloud:
    gateway:
      routes:
        - id: order-service
          uri: lb://order-service
          predicates:
            - Path=/api/order/**
          filters:
            - StripPrefix=2

    sentinel:
      filter:
        enabled: false  # 禁用默认过滤器
      scg:
        fallback:
          mode: response
          response-status: 429
          response-body: '{"code":429,"message":"请求过于频繁"}'
```

## 监控集成

### 暴露监控端点

```yaml
management:
  endpoints:
    web:
      exposure:
        include: '*'
  endpoint:
    sentinel:
      enabled: true
```

### Prometheus集成

```xml
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>
```

```java
@Configuration
public class SentinelMetricsConfig {
    @PostConstruct
    public void init() {
        // 启用Sentinel指标导出
        MetricRegistry.getMetricRegistry()
            .addMetricProvider(new SentinelMetricProvider());
    }
}
```

## 完整微服务实战

### 订单服务

```java
@SpringBootApplication
@EnableDiscoveryClient
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
    @SentinelResource(value = "orderCreateApi", blockHandler = "handleBlock")
    public Result createOrder(@RequestBody OrderDTO dto) {
        Order order = orderService.createOrder(dto);
        return Result.success(order);
    }

    public Result handleBlock(OrderDTO dto, BlockException ex) {
        return Result.error(429, "订单创建繁忙");
    }
}

@Service
public class OrderService {

    @Autowired
    private ProductService productService;

    @Autowired
    private InventoryService inventoryService;

    @SentinelResource(value = "createOrder", fallback = "handleFallback")
    @Transactional
    public Order createOrder(OrderDTO dto) {
        // 1. 检查商品
        Product product = productService.getProduct(dto.getProductId());

        // 2. 检查库存
        boolean hasStock = inventoryService.checkStock(dto.getProductId(), dto.getQuantity());
        if (!hasStock) {
            throw new BusinessException("库存不足");
        }

        // 3. 扣减库存
        inventoryService.deductStock(dto.getProductId(), dto.getQuantity());

        // 4. 创建订单
        Order order = new Order();
        order.setProductId(product.getId());
        order.setQuantity(dto.getQuantity());
        order.setAmount(product.getPrice() * dto.getQuantity());
        return orderDao.save(order);
    }

    public Order handleFallback(OrderDTO dto, Throwable ex) {
        log.error("订单创建失败", ex);
        throw new BusinessException("系统繁忙，请稍后重试");
    }
}
```

## 总结

Spring Cloud Alibaba + Sentinel集成要点：
1. Nacos作为注册中心和配置中心
2. Feign自动支持Sentinel熔断
3. Gateway集成Sentinel网关流控
4. 链路限流实现精细化控制
5. 从Nacos动态加载规则
6. 完整的监控和告警体系
