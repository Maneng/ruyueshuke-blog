---
title: 服务治理：注册发现、负载均衡与熔断降级
date: 2025-11-03T10:00:00+08:00
draft: false
tags:
  - 服务治理
  - 微服务
  - Nacos
  - Sentinel
  - 负载均衡
  - 熔断降级
  - Java
categories:
  - 技术
description: 深度剖析微服务治理的核心组件。掌握服务注册与发现、负载均衡策略、熔断降级机制，构建高可用的微服务系统。
series:
  - Java微服务架构第一性原理
weight: 5
---

## 引子：一次服务雪崩事故

2020年双11，某电商平台因评论服务故障导致整个系统瘫痪3小时，损失上亿。

**故障链路**：
```
用户下单 → 订单服务 → 评论服务（响应慢，20秒超时）
  → 订单服务线程池耗尽
  → 用户服务调用订单服务失败
  → 整个系统崩溃
```

**问题根源**：缺乏有效的服务治理机制

---

## 一、服务注册与发现

### 1.1 为什么需要服务注册中心？

**问题**：微服务架构下，服务IP动态变化

```
订单服务 → 库存服务（192.168.1.10:8080）

问题：
1. 库存服务重启，IP可能变化
2. 库存服务扩容，新增实例
3. 库存服务下线，需要摘除
```

**解决方案**：服务注册中心

```
订单服务 → 注册中心 → 获取库存服务列表
              ↓
         [192.168.1.10:8080,
          192.168.1.11:8080,
          192.168.1.12:8080]
```

### 1.2 Nacos服务注册与发现

**服务提供者：注册服务**

```java
/**
 * 库存服务：自动注册到Nacos
 */
@SpringBootApplication
@EnableDiscoveryClient
public class InventoryServiceApplication {
    public static void main(String[] args) {
        SpringApplication.run(InventoryServiceApplication.class, args);
    }
}
```

```yaml
# application.yml
spring:
  application:
    name: inventory-service  # 服务名
  cloud:
    nacos:
      discovery:
        server-addr: 127.0.0.1:8848
        namespace: dev
        group: DEFAULT_GROUP
```

**服务消费者：发现服务**

```java
/**
 * 订单服务：调用库存服务
 */
@Service
public class OrderService {

    @Autowired
    private DiscoveryClient discoveryClient;

    public void createOrder() {
        // 从注册中心获取库存服务实例列表
        List<ServiceInstance> instances = discoveryClient.getInstances("inventory-service");

        if (instances.isEmpty()) {
            throw new BusinessException("库存服务不可用");
        }

        // 选择一个实例（负载均衡）
        ServiceInstance instance = instances.get(0);
        String url = "http://" + instance.getHost() + ":" + instance.getPort();

        // 调用库存服务
        // ...
    }
}
```

### 1.3 AP vs CP模式

**AP模式（Nacos默认）**：
- **优势**：高可用，注册中心挂了服务仍可用（使用本地缓存）
- **劣势**：可能返回过期的服务列表

**CP模式（Consul）**：
- **优势**：强一致性，保证数据准确
- **劣势**：注册中心挂了，服务不可用

**选择**：互联网场景推荐AP模式

---

## 二、负载均衡

### 2.1 负载均衡算法

**1. 轮询（Round Robin）**

```java
public ServiceInstance choose(List<ServiceInstance> instances) {
    int index = counter.getAndIncrement() % instances.size();
    return instances.get(index);
}
```

**2. 随机（Random）**

```java
public ServiceInstance choose(List<ServiceInstance> instances) {
    int index = ThreadLocalRandom.current().nextInt(instances.size());
    return instances.get(index);
}
```

**3. 加权轮询（Weighted Round Robin）**

```java
public ServiceInstance choose(List<ServiceInstance> instances) {
    // 权重：instance1=5, instance2=3, instance3=2
    // 总权重：10
    // 概率：instance1=50%, instance2=30%, instance3=20%
    int totalWeight = instances.stream()
            .mapToInt(ServiceInstance::getWeight)
            .sum();

    int randomWeight = ThreadLocalRandom.current().nextInt(totalWeight);

    for (ServiceInstance instance : instances) {
        randomWeight -= instance.getWeight();
        if (randomWeight < 0) {
            return instance;
        }
    }

    return instances.get(0);
}
```

**4. 最小连接数（Least Connections）**

```java
public ServiceInstance choose(List<ServiceInstance> instances) {
    return instances.stream()
            .min(Comparator.comparingInt(ServiceInstance::getActiveConnections))
            .orElse(instances.get(0));
}
```

**5. 一致性哈希（Consistent Hashing）**

```java
public ServiceInstance choose(List<ServiceInstance> instances, String key) {
    int hash = key.hashCode();
    TreeMap<Integer, ServiceInstance> ring = buildHashRing(instances);
    Map.Entry<Integer, ServiceInstance> entry = ring.ceilingEntry(hash);
    return entry != null ? entry.getValue() : ring.firstEntry().getValue();
}
```

### 2.2 Spring Cloud LoadBalancer配置

```java
/**
 * 负载均衡配置
 */
@Configuration
public class LoadBalancerConfig {

    /**
     * 随机负载均衡
     */
    @Bean
    public ReactorLoadBalancer<ServiceInstance> randomLoadBalancer(
            Environment environment,
            LoadBalancerClientFactory loadBalancerClientFactory) {

        String name = environment.getProperty(LoadBalancerClientFactory.PROPERTY_NAME);

        return new RandomLoadBalancer(
            loadBalancerClientFactory.getLazyProvider(name, ServiceInstanceListSupplier.class),
            name
        );
    }
}
```

---

## 三、熔断降级

### 3.1 熔断器模式

**三种状态**：

```
关闭（Closed）→ 失败率达到阈值 → 开启（Open）
    ↑                                ↓
    └─────────────────────────── 半开启（Half-Open）
          部分请求成功
```

### 3.2 Sentinel熔断降级

**1. 配置熔断规则**

```java
/**
 * Sentinel配置
 */
@Configuration
public class SentinelConfig {

    @PostConstruct
    public void initRules() {
        // 熔断规则
        List<DegradeRule> rules = new ArrayList<>();

        DegradeRule rule = new DegradeRule("inventory-service")
                .setGrade(CircuitBreakerStrategy.ERROR_RATIO.getType())  // 异常比例
                .setCount(0.5)                // 异常比例阈值：50%
                .setTimeWindow(10)            // 熔断时长：10秒
                .setMinRequestAmount(10)      // 最小请求数：10
                .setStatIntervalMs(10000);    // 统计时长：10秒

        rules.add(rule);
        DegradeRuleManager.loadRules(rules);
    }
}
```

**2. 使用@SentinelResource注解**

```java
@Service
public class OrderService {

    @SentinelResource(
        value = "deductInventory",
        fallback = "deductInventoryFallback",
        blockHandler = "deductInventoryBlockHandler"
    )
    public boolean deductInventory(Long productId, Integer quantity) {
        // 调用库存服务
        return inventoryServiceClient.deduct(productId, quantity);
    }

    /**
     * 降级方法（业务异常时调用）
     */
    public boolean deductInventoryFallback(Long productId, Integer quantity, Throwable e) {
        log.error("库存扣减失败: {}", e.getMessage());
        return false;
    }

    /**
     * 熔断方法（限流或熔断时调用）
     */
    public boolean deductInventoryBlockHandler(Long productId, Integer quantity, BlockException e) {
        log.warn("库存服务熔断");
        return false;
    }
}
```

### 3.3 限流算法

**1. 令牌桶（Token Bucket）**

```java
public class TokenBucketLimiter {
    private final long capacity;      // 桶容量
    private final long rate;          // 令牌生成速率
    private long tokens;              // 当前令牌数
    private long lastRefillTime;      // 上次填充时间

    public synchronized boolean tryAcquire() {
        refill();

        if (tokens > 0) {
            tokens--;
            return true;
        }

        return false;
    }

    private void refill() {
        long now = System.currentTimeMillis();
        long tokensToAdd = (now - lastRefillTime) / 1000 * rate;

        if (tokensToAdd > 0) {
            tokens = Math.min(capacity, tokens + tokensToAdd);
            lastRefillTime = now;
        }
    }
}
```

**2. 漏桶（Leaky Bucket）**

```java
public class LeakyBucketLimiter {
    private final long capacity;      // 桶容量
    private final long rate;          // 漏水速率
    private long water;               // 当前水量
    private long lastLeakTime;        // 上次漏水时间

    public synchronized boolean tryAcquire() {
        leak();

        if (water < capacity) {
            water++;
            return true;
        }

        return false;
    }

    private void leak() {
        long now = System.currentTimeMillis();
        long leaked = (now - lastLeakTime) / 1000 * rate;

        if (leaked > 0) {
            water = Math.max(0, water - leaked);
            lastLeakTime = now;
        }
    }
}
```

**3. 滑动窗口（Sliding Window）**

```java
public class SlidingWindowLimiter {
    private final int windowSize;     // 窗口大小（秒）
    private final int limit;          // 限制数量
    private final Queue<Long> timestamps = new LinkedList<>();

    public synchronized boolean tryAcquire() {
        long now = System.currentTimeMillis();

        // 移除窗口外的时间戳
        while (!timestamps.isEmpty() && timestamps.peek() < now - windowSize * 1000) {
            timestamps.poll();
        }

        // 检查是否超限
        if (timestamps.size() < limit) {
            timestamps.offer(now);
            return true;
        }

        return false;
    }
}
```

---

## 四、API网关

### 4.1 网关的职责

1. **路由转发**：将请求路由到正确的服务
2. **认证授权**：统一的认证和授权
3. **限流熔断**：防止服务过载
4. **监控日志**：统一的监控和日志
5. **协议转换**：HTTP转gRPC

### 4.2 Spring Cloud Gateway配置

```yaml
spring:
  cloud:
    gateway:
      routes:
        # 订单服务路由
        - id: order-service
          uri: lb://order-service  # 负载均衡
          predicates:
            - Path=/api/orders/**
          filters:
            - StripPrefix=1        # 去掉/api前缀

        # 商品服务路由
        - id: product-service
          uri: lb://product-service
          predicates:
            - Path=/api/products/**
          filters:
            - StripPrefix=1
```

**自定义过滤器**：

```java
/**
 * 认证过滤器
 */
@Component
public class AuthFilter implements GlobalFilter, Ordered {

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        String token = exchange.getRequest().getHeaders().getFirst("Authorization");

        if (StringUtils.isEmpty(token)) {
            exchange.getResponse().setStatusCode(HttpStatus.UNAUTHORIZED);
            return exchange.getResponse().setComplete();
        }

        // 验证token
        if (!validateToken(token)) {
            exchange.getResponse().setStatusCode(HttpStatus.UNAUTHORIZED);
            return exchange.getResponse().setComplete();
        }

        return chain.filter(exchange);
    }

    @Override
    public int getOrder() {
        return -100;  // 优先级最高
    }

    private boolean validateToken(String token) {
        // TODO: 验证token逻辑
        return true;
    }
}
```

---

## 五、优雅上下线

### 5.1 优雅下线流程

```
1. 服务收到SIGTERM信号
2. 停止接收新请求
3. 等待现有请求处理完成（最多30秒）
4. 从注册中心注销服务
5. 关闭连接池、线程池
6. 退出进程
```

### 5.2 代码实现

```java
/**
 * 优雅下线
 */
@Component
public class GracefulShutdown implements ApplicationListener<ContextClosedEvent> {

    @Autowired
    private Connector connector;

    @Override
    public void onApplicationEvent(ContextClosedEvent event) {
        connector.pause();  // 停止接收新请求

        Executor executor = connector.getProtocolHandler().getExecutor();
        if (executor instanceof ThreadPoolExecutor) {
            try {
                ThreadPoolExecutor threadPoolExecutor = (ThreadPoolExecutor) executor;
                threadPoolExecutor.shutdown();

                // 等待现有请求处理完成（最多30秒）
                if (!threadPoolExecutor.awaitTermination(30, TimeUnit.SECONDS)) {
                    log.warn("线程池未能在30秒内关闭，强制关闭");
                    threadPoolExecutor.shutdownNow();
                }

            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
    }
}
```

---

## 六、总结

### 核心组件

1. **服务注册中心**：Nacos（AP模式）、Eureka、Consul
2. **负载均衡**：轮询、随机、加权、最小连接数、一致性哈希
3. **熔断降级**：Sentinel（异常比例、慢调用比例）
4. **限流**：令牌桶、漏桶、滑动窗口
5. **API网关**：Spring Cloud Gateway、Kong

### 最佳实践

1. ✅ **使用Nacos作为注册中心**（阿里系，生态成熟）
2. ✅ **使用Sentinel做熔断降级**（功能强大，UI友好）
3. ✅ **使用Spring Cloud Gateway做网关**（响应式，性能好）
4. ✅ **配置合理的超时时间**（连接超时5秒，读取超时10秒）
5. ✅ **实现优雅上下线**（避免请求丢失）

---

**参考资料**：
1. Nacos官方文档
2. Sentinel官方文档
3. Spring Cloud Gateway官方文档

**最后更新时间**：2025-11-03
