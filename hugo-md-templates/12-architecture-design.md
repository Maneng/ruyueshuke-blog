---
# ============================================================
# 架构设计模板
# 适用于：系统架构、技术选型、设计文档
# ============================================================

title: "XXX 系统架构设计：从0到1的架构演进"
date: 2025-10-01T20:00:00+08:00
draft: false

tags: ["架构设计", "系统设计", "技术选型", "微服务"]
categories: ["架构"]

description: "详细介绍XXX系统的架构设计思路、技术选型和实现方案"
---

## 项目概述

### 项目背景

**业务场景**：

XXX项目是为了解决YYY问题而设计的...

**核心目标**：

- 🎯 目标1：实现...功能
- 🎯 目标2：支撑...业务
- 🎯 目标3：提升...效率

**项目规模**：

| 维度 | 指标 |
|-----|------|
| **用户规模** | 预计日活XX万 |
| **数据规模** | 预计日增XX万条 |
| **并发量** | 峰值QPS XX万 |
| **团队规模** | XX人开发团队 |

### 业务需求

#### 功能需求

1. **核心功能**
   - 功能A：用户管理系统
   - 功能B：订单处理系统
   - 功能C：支付结算系统

2. **扩展功能**
   - 功能D：数据分析
   - 功能E：消息通知
   - 功能F：权限管理

#### 非功能需求

| 需求 | 指标 | 说明 |
|-----|------|------|
| **性能** | 响应时间 < 200ms | P99 |
| **可用性** | 99.95% | 年度可用性 |
| **并发** | 10000 QPS | 峰值支撑 |
| **扩展性** | 支持水平扩展 | 无状态设计 |
| **安全性** | 符合等保三级 | 数据加密 |

---

## 架构演进

### 阶段一：单体架构（MVP）

#### 架构图

```
┌─────────────────────────────┐
│      Monolithic App         │
│  ┌─────────────────────┐   │
│  │   Web Layer         │   │
│  ├─────────────────────┤   │
│  │   Service Layer     │   │
│  ├─────────────────────┤   │
│  │   Data Access Layer │   │
│  └─────────────────────┘   │
└──────────────┬──────────────┘
               │
        ┌──────▼──────┐
        │   Database   │
        └──────────────┘
```

#### 特点

**优点**：
- ✅ 架构简单，开发快速
- ✅ 部署方便，易于调试
- ✅ 适合快速验证业务

**缺点**：
- ❌ 代码耦合度高
- ❌ 扩展性差
- ❌ 技术栈受限

**适用场景**：
- MVP阶段
- 用户量 < 1万
- 团队 < 5人

### 阶段二：垂直拆分

#### 架构图

```
      ┌─────────────┐
      │ Load Balancer│
      └──────┬───────┘
      ┌──────┴───────┐
      │              │
┌─────▼───┐    ┌────▼────┐
│  Web    │    │  Admin  │
│  App    │    │  App    │
└────┬────┘    └────┬────┘
     │              │
     └──────┬───────┘
      ┌─────▼──────┐
      │  Database  │
      │   Master   │
      └─────┬──────┘
      ┌─────▼──────┐
      │  Database  │
      │   Slave    │
      └────────────┘
```

#### 特点

**改进**：
- ✅ 前后端分离
- ✅ 读写分离
- ✅ 支持水平扩展

**不足**：
- ❌ 仍是单体应用
- ❌ 数据库成为瓶颈

### 阶段三：微服务架构

#### 整体架构图

```
                  ┌──────────────┐
                  │   Client     │
                  └──────┬───────┘
                         │
                  ┌──────▼───────┐
                  │  API Gateway │
                  └──────┬───────┘
                         │
      ┌──────────────────┼──────────────────┐
      │                  │                  │
┌─────▼─────┐    ┌──────▼─────┐    ┌──────▼─────┐
│   User    │    │   Order    │    │  Payment   │
│  Service  │    │  Service   │    │  Service   │
└─────┬─────┘    └──────┬─────┘    └──────┬─────┘
      │                  │                  │
      └──────────────────┼──────────────────┘
                         │
                  ┌──────▼───────┐
                  │ Message Queue│
                  └──────────────┘
                         │
      ┌──────────────────┼──────────────────┐
      │                  │                  │
┌─────▼─────┐    ┌──────▼─────┐    ┌──────▼─────┐
│  MySQL    │    │   Redis    │    │   ES       │
└───────────┘    └────────────┘    └────────────┘
```

---

## 技术架构

### 技术选型

#### 后端技术栈

| 技术 | 版本 | 用途 | 选型理由 |
|-----|------|------|---------|
| **Java** | 17 | 开发语言 | 生态成熟，性能优秀 |
| **Spring Boot** | 3.2 | 应用框架 | 开发效率高，社区活跃 |
| **Spring Cloud** | 2023.0 | 微服务框架 | 组件完善，易于集成 |
| **MySQL** | 8.0 | 关系数据库 | 成熟稳定，支持事务 |
| **Redis** | 7.0 | 缓存 | 性能高，数据结构丰富 |
| **RabbitMQ** | 3.12 | 消息队列 | 可靠性高，功能完善 |
| **Elasticsearch** | 8.0 | 搜索引擎 | 全文检索，日志分析 |

#### 前端技术栈

| 技术 | 版本 | 用途 |
|-----|------|------|
| **Vue.js** | 3.3 | 前端框架 |
| **TypeScript** | 5.0 | 类型系统 |
| **Element Plus** | 2.4 | UI组件库 |
| **Vite** | 4.0 | 构建工具 |

#### 基础设施

| 技术 | 用途 |
|-----|------|
| **Docker** | 容器化 |
| **Kubernetes** | 容器编排 |
| **Nginx** | 反向代理 |
| **Jenkins** | CI/CD |
| **Prometheus** | 监控 |
| **Grafana** | 可视化 |

### 技术选型对比

#### 消息队列选型

| 对比项 | RabbitMQ | RocketMQ | Kafka |
|-------|----------|----------|-------|
| **性能** | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **可靠性** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| **易用性** | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ |
| **社区** | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **场景** | 通用 | 电商/金融 | 大数据 |

**选择 RabbitMQ 的理由**：
- ✅ 可靠性高，支持事务
- ✅ 功能完善，插件丰富
- ✅ 易于运维
- ✅ 满足当前业务需求

---

## 核心模块设计

### 用户服务

#### 职责

- 用户注册、登录
- 用户信息管理
- 权限验证

#### 接口设计

```java
// 用户 API
POST   /api/v1/users              // 注册用户
POST   /api/v1/users/login        // 用户登录
GET    /api/v1/users/{id}         // 获取用户信息
PUT    /api/v1/users/{id}         // 更新用户信息
DELETE /api/v1/users/{id}         // 删除用户
GET    /api/v1/users/{id}/orders  // 获取用户订单
```

#### 数据模型

```sql
CREATE TABLE users (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(100) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    phone VARCHAR(20),
    status TINYINT DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_email (email),
    INDEX idx_phone (phone)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

#### 核心流程

**用户注册流程**：

```
用户提交注册信息
    ↓
验证邮箱/手机号格式
    ↓
检查邮箱/手机号是否已存在
    ↓
密码加密（BCrypt）
    ↓
保存到数据库
    ↓
发送欢迎邮件
    ↓
返回注册成功
```

### 订单服务

#### 职责

- 订单创建
- 订单查询
- 订单状态管理

#### 状态机设计

```
待支付 ──┐
         │
         ▼
      已支付 ──┐
         │     │
         ▼     ▼
      配送中  已取消
         │
         ▼
      已完成
```

#### 核心代码

```java
@Service
public class OrderService {

    @Autowired
    private OrderRepository orderRepository;

    @Autowired
    private ProductService productService;

    @Autowired
    private PaymentService paymentService;

    @Transactional
    public Order createOrder(OrderCreateRequest request) {
        // 1. 验证商品库存
        Product product = productService.getProduct(request.getProductId());
        if (product.getStock() < request.getQuantity()) {
            throw new InsufficientStockException();
        }

        // 2. 创建订单
        Order order = new Order();
        order.setUserId(request.getUserId());
        order.setProductId(request.getProductId());
        order.setQuantity(request.getQuantity());
        order.setTotalAmount(product.getPrice().multiply(
                new BigDecimal(request.getQuantity())));
        order.setStatus(OrderStatus.PENDING);

        // 3. 扣减库存
        productService.decreaseStock(product.getId(), request.getQuantity());

        // 4. 保存订单
        order = orderRepository.save(order);

        // 5. 发送订单创建事件
        eventPublisher.publishEvent(new OrderCreatedEvent(order));

        return order;
    }
}
```

### 支付服务

#### 支付流程

```
创建支付订单
    ↓
调用第三方支付
    ↓
等待支付回调
    ↓
验证签名
    ↓
更新订单状态
    ↓
发送支付成功通知
```

---

## 数据架构

### 数据分片

#### 分库分表策略

**用户表分片**：

```
按 user_id 哈希分16个库，每个库16张表

分库键：user_id % 16
分表键：user_id / 16 % 16

示例：
user_id = 1025
库：1025 % 16 = 1 → db_01
表：1025 / 16 % 16 = 0 → user_00
```

**订单表分片**：

```
按 order_id 范围分片

db_order_2024_01: 2024年1月订单
db_order_2024_02: 2024年2月订单
...
```

### 缓存策略

#### 多级缓存

```
请求
  ↓
本地缓存（Caffeine）
  ↓ Miss
分布式缓存（Redis）
  ↓ Miss
数据库（MySQL）
```

#### 缓存更新策略

```java
// Cache Aside 模式
public User getUser(Long userId) {
    // 1. 查询缓存
    String cacheKey = "user:" + userId;
    String cached = redisTemplate.opsForValue().get(cacheKey);

    if (cached != null) {
        return JSON.parseObject(cached, User.class);
    }

    // 2. 缓存未命中，查询数据库
    User user = userRepository.findById(userId)
        .orElseThrow(() -> new UserNotFoundException(userId));

    // 3. 写入缓存
    redisTemplate.opsForValue().set(
        cacheKey,
        JSON.toJSONString(user),
        Duration.ofHours(1)
    );

    return user;
}

public void updateUser(User user) {
    // 1. 更新数据库
    userRepository.save(user);

    // 2. 删除缓存（而不是更新）
    String cacheKey = "user:" + user.getId();
    redisTemplate.delete(cacheKey);
}
```

---

## 高可用设计

### 服务降级

```java
@Service
public class RecommendService {

    @Autowired
    private RemoteRecommendApi remoteApi;

    // 使用 Hystrix 或 Resilience4j
    @HystrixCommand(fallbackMethod = "getFallbackRecommend")
    public List<Product> getRecommend(Long userId) {
        return remoteApi.getRecommend(userId);
    }

    // 降级方法
    public List<Product> getFallbackRecommend(Long userId) {
        // 返回默认推荐或热门商品
        return productService.getHotProducts();
    }
}
```

### 限流策略

```java
// 使用 Guava RateLimiter
public class RateLimiterService {

    // 每秒1000个请求
    private RateLimiter rateLimiter = RateLimiter.create(1000.0);

    public boolean tryAcquire() {
        return rateLimiter.tryAcquire(100, TimeUnit.MILLISECONDS);
    }
}

// 在 Controller 中使用
@GetMapping("/api/products")
public List<Product> getProducts() {
    if (!rateLimiterService.tryAcquire()) {
        throw new RateLimitExceededException();
    }
    return productService.getProducts();
}
```

### 熔断机制

```yaml
# Resilience4j 配置
resilience4j:
  circuitbreaker:
    instances:
      productService:
        failureRateThreshold: 50        # 失败率达到50%时熔断
        waitDurationInOpenState: 60000  # 熔断后等待60秒
        slidingWindowSize: 10           # 滑动窗口大小
```

---

## 监控告警

### 监控指标

#### 应用监控

| 指标 | 说明 | 阈值 |
|-----|------|------|
| **QPS** | 每秒请求数 | > 10000 告警 |
| **响应时间** | P99 响应时间 | > 500ms 告警 |
| **错误率** | 5xx 错误率 | > 1% 告警 |
| **CPU** | CPU 使用率 | > 80% 告警 |
| **内存** | 内存使用率 | > 85% 告警 |

#### 业务监控

- 订单创建成功率
- 支付成功率
- 用户活跃度
- 转化率

### 告警配置

```yaml
# Prometheus 告警规则
groups:
  - name: application
    rules:
      - alert: HighErrorRate
        expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.01
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High error rate detected"
          description: "Error rate is {{ $value }}%"

      - alert: SlowResponse
        expr: histogram_quantile(0.99, http_request_duration_seconds_bucket) > 0.5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Slow response time detected"
```

---

## 部署架构

### Kubernetes 部署

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-service
spec:
  replicas: 3
  selector:
    matchLabels:
      app: user-service
  template:
    metadata:
      labels:
        app: user-service
    spec:
      containers:
      - name: user-service
        image: user-service:v1.0.0
        ports:
        - containerPort: 8080
        env:
        - name: SPRING_PROFILES_ACTIVE
          value: "prod"
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
        livenessProbe:
          httpGet:
            path: /actuator/health
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /actuator/health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 5
```

---

## 安全设计

### 认证授权

```java
// JWT Token 生成
public String generateToken(User user) {
    Date now = new Date();
    Date expiration = new Date(now.getTime() + TOKEN_EXPIRATION);

    return Jwts.builder()
        .setSubject(user.getId().toString())
        .setIssuedAt(now)
        .setExpiration(expiration)
        .signWith(SignatureAlgorithm.HS512, SECRET_KEY)
        .compact();
}

// Token 验证
public Long getUserIdFromToken(String token) {
    Claims claims = Jwts.parser()
        .setSigningKey(SECRET_KEY)
        .parseClaimsJws(token)
        .getBody();

    return Long.parseLong(claims.getSubject());
}
```

### 数据加密

```java
// 敏感数据加密存储
public class EncryptionUtils {

    private static final String ALGORITHM = "AES";

    public static String encrypt(String data, String key) throws Exception {
        SecretKeySpec secretKey = new SecretKeySpec(key.getBytes(), ALGORITHM);
        Cipher cipher = Cipher.getInstance(ALGORITHM);
        cipher.init(Cipher.ENCRYPT_MODE, secretKey);
        byte[] encrypted = cipher.doFinal(data.getBytes());
        return Base64.getEncoder().encodeToString(encrypted);
    }

    public static String decrypt(String encryptedData, String key) throws Exception {
        SecretKeySpec secretKey = new SecretKeySpec(key.getBytes(), ALGORITHM);
        Cipher cipher = Cipher.getInstance(ALGORITHM);
        cipher.init(Cipher.DECRYPT_MODE, secretKey);
        byte[] decrypted = cipher.doFinal(Base64.getDecoder().decode(encryptedData));
        return new String(decrypted);
    }
}
```

---

## 总结

### 架构亮点

1. **微服务架构**：服务独立部署，易于扩展
2. **高可用设计**：多副本、熔断、降级
3. **性能优化**：多级缓存、数据分片
4. **安全保障**：认证授权、数据加密
5. **可观测性**：全链路监控、日志追踪

### 未来规划

- [ ] 引入服务网格（Service Mesh）
- [ ] 实现灰度发布
- [ ] 优化数据库性能
- [ ] 引入 AI 推荐算法
- [ ] 实现多云部署

---

## 参考资料

- [微服务架构设计模式](https://microservices.io/)
- [Spring Cloud 官方文档](https://spring.io/projects/spring-cloud)
- [Kubernetes 最佳实践](https://kubernetes.io/docs/concepts/)
- [阿里巴巴Java开发手册](https://github.com/alibaba/p3c)

---

**更新记录**：

- 2025-10-01：初始版本，完成整体架构设计
- 2025-10-15：补充监控告警和安全设计
- 2025-11-01：更新部署架构

> 💬 对架构设计有什么建议？欢迎在评论区讨论！
