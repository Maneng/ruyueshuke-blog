---
title: "API设计最佳实践——RESTful接口规范"
date: 2026-02-04T14:00:00+08:00
draft: false
tags: ["API设计", "RESTful", "接口规范", "系统集成", "跨境电商"]
categories: ["数字化转型"]
description: "如何设计出优雅、易用、安全的API？本文详解RESTful设计原则、请求响应规范、版本管理、安全设计、文档规范，帮你打造企业级API标准。"
series: ["跨境电商数字化转型指南"]
weight: 26
---

## 引言：API是系统的门面

在多系统集成的架构中，**API是系统之间沟通的语言**。一个设计良好的API：
- 让调用方一看就懂，减少沟通成本
- 让维护方易于扩展，降低变更风险
- 让系统更加稳定，提升整体可靠性

**糟糕的API设计会带来什么问题？**
- 接口命名混乱，调用方需要反复确认
- 响应格式不统一，每个接口都要单独处理
- 版本管理缺失，升级时牵一发动全身
- 安全机制薄弱，容易被攻击或滥用

本文将系统性地介绍API设计的最佳实践，帮你建立企业级的API规范。

---

## 一、RESTful设计原则

### 1.1 什么是RESTful

REST（Representational State Transfer）是一种架构风格，核心思想是：
- **资源导向**：一切皆资源，用URL标识
- **统一接口**：用HTTP方法表示操作
- **无状态**：每次请求包含所有必要信息

### 1.2 资源命名规范

**规则1：使用名词复数**

```
✅ 正确
GET /api/v1/orders          # 订单列表
GET /api/v1/products        # 商品列表
GET /api/v1/warehouses      # 仓库列表

❌ 错误
GET /api/v1/getOrders       # 动词命名
GET /api/v1/order           # 单数形式
GET /api/v1/orderList       # 冗余后缀
```

**规则2：使用小写字母和连字符**

```
✅ 正确
GET /api/v1/order-items
GET /api/v1/shipping-addresses
GET /api/v1/purchase-orders

❌ 错误
GET /api/v1/orderItems      # 驼峰命名
GET /api/v1/order_items     # 下划线
GET /api/v1/OrderItems      # 大写字母
```

**规则3：层级关系用路径表示**

```
# 获取订单的明细
GET /api/v1/orders/{orderId}/items

# 获取仓库的库位
GET /api/v1/warehouses/{warehouseId}/locations

# 获取商品的SKU
GET /api/v1/products/{productId}/skus

# 最多3层，超过3层考虑拆分
❌ /api/v1/orders/{orderId}/items/{itemId}/packages/{packageId}/labels
✅ /api/v1/package-labels/{labelId}
```

**规则4：过滤、排序、分页用查询参数**

```
# 过滤
GET /api/v1/orders?status=PENDING&channel=AMAZON

# 排序
GET /api/v1/orders?sort=createdAt&order=desc

# 分页
GET /api/v1/orders?page=1&size=20

# 组合使用
GET /api/v1/orders?status=PENDING&sort=createdAt&order=desc&page=1&size=20
```

### 1.3 HTTP方法使用

| 方法 | 语义 | 幂等性 | 安全性 | 使用场景 |
|-----|-----|-------|-------|---------|
| GET | 查询 | ✅ | ✅ | 获取资源 |
| POST | 创建 | ❌ | ❌ | 新建资源 |
| PUT | 全量更新 | ✅ | ❌ | 替换资源 |
| PATCH | 部分更新 | ✅ | ❌ | 修改部分字段 |
| DELETE | 删除 | ✅ | ❌ | 删除资源 |

**实际应用示例**：

```
# 订单相关
GET    /api/v1/orders                    # 查询订单列表
GET    /api/v1/orders/{id}               # 查询单个订单
POST   /api/v1/orders                    # 创建订单
PUT    /api/v1/orders/{id}               # 全量更新订单
PATCH  /api/v1/orders/{id}               # 部分更新订单
DELETE /api/v1/orders/{id}               # 删除订单

# 订单操作（非CRUD操作用POST + 动词）
POST   /api/v1/orders/{id}/cancel        # 取消订单
POST   /api/v1/orders/{id}/confirm       # 确认订单
POST   /api/v1/orders/{id}/ship          # 发货
POST   /api/v1/orders/{id}/complete      # 完成订单
```

### 1.4 HTTP状态码规范

**成功状态码**：

| 状态码 | 含义 | 使用场景 |
|-------|-----|---------|
| 200 OK | 请求成功 | GET/PUT/PATCH/DELETE成功 |
| 201 Created | 资源已创建 | POST创建成功 |
| 204 No Content | 无返回内容 | DELETE成功，无需返回数据 |

**客户端错误**：

| 状态码 | 含义 | 使用场景 |
|-------|-----|---------|
| 400 Bad Request | 请求格式错误 | 参数校验失败、JSON格式错误 |
| 401 Unauthorized | 未认证 | 未登录、Token过期 |
| 403 Forbidden | 无权限 | 已认证但无权访问 |
| 404 Not Found | 资源不存在 | 订单不存在、商品不存在 |
| 409 Conflict | 资源冲突 | 重复创建、并发冲突 |
| 422 Unprocessable Entity | 业务校验失败 | 库存不足、余额不足 |
| 429 Too Many Requests | 请求过多 | 触发限流 |

**服务端错误**：

| 状态码 | 含义 | 使用场景 |
|-------|-----|---------|
| 500 Internal Server Error | 服务器内部错误 | 未捕获的异常 |
| 502 Bad Gateway | 网关错误 | 上游服务不可用 |
| 503 Service Unavailable | 服务不可用 | 服务维护中 |
| 504 Gateway Timeout | 网关超时 | 上游服务超时 |

---

## 二、请求响应规范

### 2.1 统一响应格式

**成功响应**：

```json
{
    "code": 0,
    "message": "success",
    "data": {
        "orderId": "ORD202402040001",
        "status": "PENDING",
        "totalAmount": 199.99,
        "currency": "USD"
    },
    "timestamp": 1707033600000,
    "traceId": "a1b2c3d4e5f6"
}
```

**列表响应（带分页）**：

```json
{
    "code": 0,
    "message": "success",
    "data": {
        "list": [
            {"orderId": "ORD001", "status": "PENDING"},
            {"orderId": "ORD002", "status": "SHIPPED"}
        ],
        "pagination": {
            "page": 1,
            "size": 20,
            "total": 156,
            "totalPages": 8
        }
    },
    "timestamp": 1707033600000,
    "traceId": "a1b2c3d4e5f6"
}
```

**错误响应**：

```json
{
    "code": 40001,
    "message": "库存不足",
    "data": null,
    "timestamp": 1707033600000,
    "traceId": "a1b2c3d4e5f6",
    "errors": [
        {
            "field": "quantity",
            "message": "SKU001库存不足，当前可用: 5，请求数量: 10"
        }
    ]
}
```

**Java实现**：

```java
/**
 * 统一响应结构
 */
@Data
public class ApiResponse<T> {
    private Integer code;
    private String message;
    private T data;
    private Long timestamp;
    private String traceId;
    private List<FieldError> errors;

    public static <T> ApiResponse<T> success(T data) {
        ApiResponse<T> response = new ApiResponse<>();
        response.setCode(0);
        response.setMessage("success");
        response.setData(data);
        response.setTimestamp(System.currentTimeMillis());
        response.setTraceId(TraceContext.getTraceId());
        return response;
    }

    public static <T> ApiResponse<T> error(Integer code, String message) {
        ApiResponse<T> response = new ApiResponse<>();
        response.setCode(code);
        response.setMessage(message);
        response.setTimestamp(System.currentTimeMillis());
        response.setTraceId(TraceContext.getTraceId());
        return response;
    }

    public static <T> ApiResponse<T> error(ErrorCode errorCode) {
        return error(errorCode.getCode(), errorCode.getMessage());
    }
}

/**
 * 分页响应
 */
@Data
public class PageResponse<T> {
    private List<T> list;
    private Pagination pagination;

    @Data
    public static class Pagination {
        private Integer page;
        private Integer size;
        private Long total;
        private Integer totalPages;
    }

    public static <T> PageResponse<T> of(Page<T> page) {
        PageResponse<T> response = new PageResponse<>();
        response.setList(page.getContent());

        Pagination pagination = new Pagination();
        pagination.setPage(page.getNumber() + 1);
        pagination.setSize(page.getSize());
        pagination.setTotal(page.getTotalElements());
        pagination.setTotalPages(page.getTotalPages());
        response.setPagination(pagination);

        return response;
    }
}

### 2.2 错误码设计

**错误码分层设计**：

```
错误码格式：XXYYYY
- XX: 模块代码（00-99）
- YYYY: 具体错误（0001-9999）

模块划分：
- 00: 通用错误
- 10: 订单模块
- 20: 库存模块
- 30: 商品模块
- 40: 用户模块
- 50: 支付模块
- 60: 物流模块
```

**错误码枚举**：

```java
public enum ErrorCode {
    // 通用错误 00xxxx
    SUCCESS(0, "success"),
    PARAM_ERROR(1001, "参数错误"),
    UNAUTHORIZED(1002, "未授权"),
    FORBIDDEN(1003, "无权限"),
    NOT_FOUND(1004, "资源不存在"),
    SYSTEM_ERROR(1005, "系统错误"),
    SERVICE_UNAVAILABLE(1006, "服务不可用"),
    RATE_LIMITED(1007, "请求过于频繁"),

    // 订单模块 10xxxx
    ORDER_NOT_FOUND(100001, "订单不存在"),
    ORDER_STATUS_INVALID(100002, "订单状态不允许此操作"),
    ORDER_ALREADY_PAID(100003, "订单已支付"),
    ORDER_ALREADY_CANCELLED(100004, "订单已取消"),
    ORDER_AMOUNT_MISMATCH(100005, "订单金额不匹配"),

    // 库存模块 20xxxx
    INVENTORY_NOT_ENOUGH(200001, "库存不足"),
    INVENTORY_LOCKED(200002, "库存已锁定"),
    INVENTORY_SKU_NOT_FOUND(200003, "SKU不存在"),
    INVENTORY_WAREHOUSE_NOT_FOUND(200004, "仓库不存在"),

    // 商品模块 30xxxx
    PRODUCT_NOT_FOUND(300001, "商品不存在"),
    PRODUCT_OFF_SHELF(300002, "商品已下架"),
    PRODUCT_SKU_NOT_FOUND(300003, "SKU不存在"),

    // 用户模块 40xxxx
    USER_NOT_FOUND(400001, "用户不存在"),
    USER_PASSWORD_ERROR(400002, "密码错误"),
    USER_ACCOUNT_LOCKED(400003, "账户已锁定"),

    // 支付模块 50xxxx
    PAYMENT_FAILED(500001, "支付失败"),
    PAYMENT_TIMEOUT(500002, "支付超时"),
    PAYMENT_REFUND_FAILED(500003, "退款失败"),

    // 物流模块 60xxxx
    LOGISTICS_NOT_FOUND(600001, "物流单不存在"),
    LOGISTICS_TRACKING_FAILED(600002, "物流查询失败");

    private final Integer code;
    private final String message;

    ErrorCode(Integer code, String message) {
        this.code = code;
        this.message = message;
    }

    public Integer getCode() { return code; }
    public String getMessage() { return message; }
}
```

### 2.3 分页规范

**请求参数**：

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|-----|-----|-----|-------|-----|
| page | Integer | 否 | 1 | 页码，从1开始 |
| size | Integer | 否 | 20 | 每页条数，最大100 |
| sort | String | 否 | createdAt | 排序字段 |
| order | String | 否 | desc | 排序方向：asc/desc |

**分页请求DTO**：

```java
@Data
public class PageRequest {
    @Min(1)
    private Integer page = 1;

    @Min(1)
    @Max(100)
    private Integer size = 20;

    private String sort = "createdAt";

    @Pattern(regexp = "^(asc|desc)$")
    private String order = "desc";

    public Pageable toPageable() {
        Sort.Direction direction = "asc".equalsIgnoreCase(order)
            ? Sort.Direction.ASC : Sort.Direction.DESC;
        return org.springframework.data.domain.PageRequest.of(
            page - 1, size, Sort.by(direction, sort)
        );
    }
}
```

### 2.4 请求参数校验

**使用JSR-303注解**：

```java
@Data
public class CreateOrderRequest {

    @NotBlank(message = "渠道不能为空")
    @Size(max = 50, message = "渠道长度不能超过50")
    private String channel;

    @NotBlank(message = "客户ID不能为空")
    private String customerId;

    @NotEmpty(message = "订单明细不能为空")
    @Size(max = 100, message = "订单明细不能超过100条")
    @Valid
    private List<OrderItemRequest> items;

    @NotNull(message = "收货地址不能为空")
    @Valid
    private AddressRequest shippingAddress;

    @DecimalMin(value = "0.01", message = "订单金额必须大于0")
    @DecimalMax(value = "999999.99", message = "订单金额不能超过999999.99")
    private BigDecimal totalAmount;

    @Pattern(regexp = "^[A-Z]{3}$", message = "币种格式错误")
    private String currency = "USD";
}

@Data
public class OrderItemRequest {

    @NotBlank(message = "SKU不能为空")
    private String skuId;

    @NotNull(message = "数量不能为空")
    @Min(value = 1, message = "数量必须大于0")
    @Max(value = 9999, message = "数量不能超过9999")
    private Integer quantity;

    @DecimalMin(value = "0.01", message = "单价必须大于0")
    private BigDecimal unitPrice;
}
```

**全局异常处理**：

```java
@RestControllerAdvice
public class GlobalExceptionHandler {

    /**
     * 参数校验异常
     */
    @ExceptionHandler(MethodArgumentNotValidException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public ApiResponse<Void> handleValidationException(MethodArgumentNotValidException e) {
        List<FieldError> errors = e.getBindingResult().getFieldErrors().stream()
            .map(error -> new FieldError(error.getField(), error.getDefaultMessage()))
            .collect(Collectors.toList());

        ApiResponse<Void> response = ApiResponse.error(ErrorCode.PARAM_ERROR);
        response.setErrors(errors);
        return response;
    }

    /**
     * 业务异常
     */
    @ExceptionHandler(BusinessException.class)
    @ResponseStatus(HttpStatus.UNPROCESSABLE_ENTITY)
    public ApiResponse<Void> handleBusinessException(BusinessException e) {
        return ApiResponse.error(e.getCode(), e.getMessage());
    }

    /**
     * 资源不存在
     */
    @ExceptionHandler(ResourceNotFoundException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public ApiResponse<Void> handleNotFoundException(ResourceNotFoundException e) {
        return ApiResponse.error(ErrorCode.NOT_FOUND);
    }

    /**
     * 系统异常
     */
    @ExceptionHandler(Exception.class)
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    public ApiResponse<Void> handleException(Exception e) {
        log.error("系统异常", e);
        return ApiResponse.error(ErrorCode.SYSTEM_ERROR);
    }
}
```

---

## 三、版本管理

### 3.1 版本策略对比

| 策略 | 示例 | 优点 | 缺点 |
|-----|-----|-----|-----|
| URL版本 | /api/v1/orders | 直观、易缓存 | URL变化 |
| Header版本 | Accept: application/vnd.api.v1+json | URL不变 | 不直观 |
| 参数版本 | /api/orders?version=1 | 简单 | 不够RESTful |

**推荐：URL版本**，因为：
- 最直观，一眼看出版本
- 便于缓存和路由
- 便于监控和统计

### 3.2 版本升级策略

**版本生命周期**：

```
┌─────────────────────────────────────────────────────────────┐
│                      版本生命周期                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  v1 ──────────────────────────────────────────────────────► │
│      │ 发布 │    稳定期    │  废弃期  │ 下线 │              │
│      └──────┴──────────────┴──────────┴──────┘              │
│                                                             │
│  v2 ────────────────────────────────────────────────────►   │
│           │ 发布 │    稳定期    │  废弃期  │ 下线 │         │
│           └──────┴──────────────┴──────────┴──────┘         │
│                                                             │
│  时间线：                                                    │
│  ├────────┼────────┼────────┼────────┼────────┼────────►   │
│  0        3        6        9        12       15      月    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**版本管理规范**：

```java
/**
 * API版本管理
 */
public class ApiVersionPolicy {

    // 版本状态
    public enum VersionStatus {
        CURRENT,    // 当前版本
        DEPRECATED, // 已废弃（仍可用）
        RETIRED     // 已下线
    }

    // 版本信息
    public static final Map<String, VersionInfo> VERSIONS = Map.of(
        "v1", new VersionInfo("v1", VersionStatus.DEPRECATED,
            LocalDate.of(2024, 1, 1),  // 发布日期
            LocalDate.of(2024, 7, 1)), // 下线日期
        "v2", new VersionInfo("v2", VersionStatus.CURRENT,
            LocalDate.of(2024, 4, 1),
            null)
    );
}
```

**废弃版本响应头**：

```java
@Component
public class DeprecationInterceptor implements HandlerInterceptor {

    @Override
    public void postHandle(HttpServletRequest request, HttpServletResponse response,
                          Object handler, ModelAndView modelAndView) {
        String version = extractVersion(request.getRequestURI());
        VersionInfo info = ApiVersionPolicy.VERSIONS.get(version);

        if (info != null && info.getStatus() == VersionStatus.DEPRECATED) {
            response.setHeader("Deprecation", "true");
            response.setHeader("Sunset", info.getRetireDate().toString());
            response.setHeader("Link", "</api/v2>; rel=\"successor-version\"");
        }
    }
}
```

### 3.3 兼容性设计

**向后兼容的变更（不需要新版本）**：
- 新增可选字段
- 新增新的API端点
- 新增新的响应字段

**不兼容的变更（需要新版本）**：
- 删除或重命名字段
- 修改字段类型
- 修改必填/选填属性
- 修改业务逻辑

**兼容性设计示例**：

```java
// v1 响应
{
    "orderId": "ORD001",
    "status": "PENDING"
}

// v2 响应（兼容v1）
{
    "orderId": "ORD001",
    "status": "PENDING",
    "statusCode": 10,        // 新增字段
    "statusName": "待处理"   // 新增字段
}

// 使用@JsonInclude避免null字段
@Data
@JsonInclude(JsonInclude.Include.NON_NULL)
public class OrderResponse {
    private String orderId;
    private String status;
    private Integer statusCode;  // v2新增
    private String statusName;   // v2新增
}
```

---

## 四、安全设计

### 4.1 认证方式

**内部系统：API Key + 签名**

```
请求头：
Authorization: ApiKey ak_xxxxxxxxxxxx
X-Timestamp: 1707033600000
X-Nonce: abc123def456
X-Signature: sha256(timestamp + nonce + apiKey + body + secret)
```

**外部系统：OAuth 2.0 / JWT**

```
请求头：
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

### 4.2 签名验证实现

```java
/**
 * API签名工具
 */
public class ApiSignatureUtil {

    private static final long TIMESTAMP_TOLERANCE = 5 * 60 * 1000; // 5分钟

    /**
     * 生成签名
     */
    public static String sign(String timestamp, String nonce,
                             String apiKey, String body, String secret) {
        String content = timestamp + nonce + apiKey + body + secret;
        return DigestUtils.sha256Hex(content);
    }

    /**
     * 验证签名
     */
    public static boolean verify(SignatureParams params, String secret) {
        // 1. 验证时间戳（防重放攻击）
        long ts = Long.parseLong(params.getTimestamp());
        long now = System.currentTimeMillis();
        if (Math.abs(now - ts) > TIMESTAMP_TOLERANCE) {
            throw new AuthenticationException("时间戳已过期");
        }

        // 2. 验证nonce（防重放攻击）
        String nonceKey = "nonce:" + params.getNonce();
        if (redisTemplate.hasKey(nonceKey)) {
            throw new AuthenticationException("请求已处理");
        }
        redisTemplate.opsForValue().set(nonceKey, "1", 10, TimeUnit.MINUTES);

        // 3. 验证签名
        String expected = sign(params.getTimestamp(), params.getNonce(),
            params.getApiKey(), params.getBody(), secret);
        return expected.equals(params.getSignature());
    }
}

/**
 * 签名验证拦截器
 */
@Component
public class SignatureInterceptor implements HandlerInterceptor {

    @Autowired
    private ApiKeyService apiKeyService;

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response,
                            Object handler) throws Exception {
        // 获取请求头
        String apiKey = request.getHeader("Authorization").replace("ApiKey ", "");
        String timestamp = request.getHeader("X-Timestamp");
        String nonce = request.getHeader("X-Nonce");
        String signature = request.getHeader("X-Signature");

        // 获取请求体
        String body = getRequestBody(request);

        // 查询API密钥
        ApiKeyInfo keyInfo = apiKeyService.getByApiKey(apiKey);
        if (keyInfo == null) {
            throw new AuthenticationException("无效的API Key");
        }

        // 验证签名
        SignatureParams params = new SignatureParams(timestamp, nonce, apiKey, body, signature);
        if (!ApiSignatureUtil.verify(params, keyInfo.getSecret())) {
            throw new AuthenticationException("签名验证失败");
        }

        // 设置上下文
        ApiContext.setCurrentApiKey(keyInfo);
        return true;
    }
}

### 4.3 限流设计

**限流维度**：

| 维度 | 说明 | 示例 |
|-----|-----|-----|
| 全局限流 | 整个API的总QPS | 10000 QPS |
| 接口限流 | 单个接口的QPS | 创建订单 1000 QPS |
| 用户限流 | 单个用户的QPS | 每用户 100 QPS |
| IP限流 | 单个IP的QPS | 每IP 50 QPS |

**基于Redis的限流实现**：

```java
/**
 * 滑动窗口限流器
 */
@Component
public class RateLimiter {

    @Autowired
    private StringRedisTemplate redisTemplate;

    /**
     * 检查是否允许请求
     * @param key 限流key
     * @param limit 限制次数
     * @param windowSeconds 窗口时间（秒）
     */
    public boolean isAllowed(String key, int limit, int windowSeconds) {
        long now = System.currentTimeMillis();
        long windowStart = now - windowSeconds * 1000L;

        String redisKey = "rate_limit:" + key;

        // 使用Lua脚本保证原子性
        String script = """
            -- 移除窗口外的记录
            redis.call('ZREMRANGEBYSCORE', KEYS[1], 0, ARGV[1])
            -- 获取当前窗口内的请求数
            local count = redis.call('ZCARD', KEYS[1])
            if count < tonumber(ARGV[2]) then
                -- 添加当前请求
                redis.call('ZADD', KEYS[1], ARGV[3], ARGV[3])
                redis.call('EXPIRE', KEYS[1], ARGV[4])
                return 1
            else
                return 0
            end
            """;

        Long result = redisTemplate.execute(
            new DefaultRedisScript<>(script, Long.class),
            List.of(redisKey),
            String.valueOf(windowStart),
            String.valueOf(limit),
            String.valueOf(now),
            String.valueOf(windowSeconds)
        );

        return result != null && result == 1;
    }
}

/**
 * 限流注解
 */
@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
public @interface RateLimit {
    int limit() default 100;        // 限制次数
    int window() default 60;        // 窗口时间（秒）
    String key() default "";        // 限流key，支持SpEL
    LimitType type() default LimitType.IP;  // 限流类型
}

public enum LimitType {
    IP,         // 按IP限流
    USER,       // 按用户限流
    API_KEY,    // 按API Key限流
    GLOBAL      // 全局限流
}

/**
 * 限流切面
 */
@Aspect
@Component
public class RateLimitAspect {

    @Autowired
    private RateLimiter rateLimiter;

    @Around("@annotation(rateLimit)")
    public Object around(ProceedingJoinPoint point, RateLimit rateLimit) throws Throwable {
        String key = buildKey(point, rateLimit);

        if (!rateLimiter.isAllowed(key, rateLimit.limit(), rateLimit.window())) {
            throw new RateLimitException("请求过于频繁，请稍后重试");
        }

        return point.proceed();
    }

    private String buildKey(ProceedingJoinPoint point, RateLimit rateLimit) {
        String baseKey = point.getSignature().toShortString();

        return switch (rateLimit.type()) {
            case IP -> baseKey + ":" + RequestContext.getClientIp();
            case USER -> baseKey + ":" + SecurityContext.getCurrentUserId();
            case API_KEY -> baseKey + ":" + ApiContext.getCurrentApiKey();
            case GLOBAL -> baseKey;
        };
    }
}
```

**使用示例**：

```java
@RestController
@RequestMapping("/api/v1/orders")
public class OrderController {

    @PostMapping
    @RateLimit(limit = 100, window = 60, type = LimitType.API_KEY)
    public ApiResponse<OrderResponse> createOrder(@RequestBody CreateOrderRequest request) {
        // 创建订单
    }

    @GetMapping
    @RateLimit(limit = 1000, window = 60, type = LimitType.GLOBAL)
    public ApiResponse<PageResponse<OrderResponse>> listOrders(PageRequest pageRequest) {
        // 查询订单列表
    }
}
```

### 4.4 熔断降级

```java
/**
 * 使用Resilience4j实现熔断
 */
@Service
public class ExternalApiService {

    @CircuitBreaker(name = "logistics", fallbackMethod = "getTrackingFallback")
    @Retry(name = "logistics")
    @RateLimiter(name = "logistics")
    public TrackingInfo getTracking(String trackingNo) {
        return logisticsClient.getTracking(trackingNo);
    }

    /**
     * 降级方法
     */
    public TrackingInfo getTrackingFallback(String trackingNo, Exception e) {
        log.warn("物流查询降级: trackingNo={}, error={}", trackingNo, e.getMessage());

        // 返回缓存数据
        TrackingInfo cached = trackingCache.get(trackingNo);
        if (cached != null) {
            cached.setFromCache(true);
            return cached;
        }

        // 返回默认值
        TrackingInfo defaultInfo = new TrackingInfo();
        defaultInfo.setTrackingNo(trackingNo);
        defaultInfo.setStatus("UNKNOWN");
        defaultInfo.setMessage("物流信息暂时无法查询");
        return defaultInfo;
    }
}
```

**Resilience4j配置**：

```yaml
resilience4j:
  circuitbreaker:
    instances:
      logistics:
        slidingWindowSize: 10
        failureRateThreshold: 50
        waitDurationInOpenState: 30s
        permittedNumberOfCallsInHalfOpenState: 3
  retry:
    instances:
      logistics:
        maxAttempts: 3
        waitDuration: 1s
        retryExceptions:
          - java.io.IOException
          - java.net.SocketTimeoutException
  ratelimiter:
    instances:
      logistics:
        limitForPeriod: 100
        limitRefreshPeriod: 1s
        timeoutDuration: 0
```

---

## 五、文档规范

### 5.1 OpenAPI/Swagger规范

**使用SpringDoc生成文档**：

```java
@Configuration
public class OpenApiConfig {

    @Bean
    public OpenAPI customOpenAPI() {
        return new OpenAPI()
            .info(new Info()
                .title("跨境电商API")
                .version("v1.0")
                .description("跨境电商系统API文档")
                .contact(new Contact()
                    .name("技术团队")
                    .email("tech@example.com")))
            .addSecurityItem(new SecurityRequirement().addList("ApiKey"))
            .components(new Components()
                .addSecuritySchemes("ApiKey",
                    new SecurityScheme()
                        .type(SecurityScheme.Type.APIKEY)
                        .in(SecurityScheme.In.HEADER)
                        .name("Authorization")));
    }
}
```

**接口文档注解**：

```java
@RestController
@RequestMapping("/api/v1/orders")
@Tag(name = "订单管理", description = "订单的创建、查询、更新、取消等操作")
public class OrderController {

    @Operation(
        summary = "创建订单",
        description = "创建新订单，需要传入订单明细、收货地址等信息"
    )
    @ApiResponses({
        @ApiResponse(responseCode = "201", description = "创建成功",
            content = @Content(schema = @Schema(implementation = OrderResponse.class))),
        @ApiResponse(responseCode = "400", description = "参数错误"),
        @ApiResponse(responseCode = "422", description = "业务校验失败，如库存不足")
    })
    @PostMapping
    public ApiResponse<OrderResponse> createOrder(
        @RequestBody @Valid CreateOrderRequest request) {
        // ...
    }

    @Operation(summary = "查询订单列表")
    @Parameters({
        @Parameter(name = "status", description = "订单状态", example = "PENDING"),
        @Parameter(name = "channel", description = "销售渠道", example = "AMAZON"),
        @Parameter(name = "page", description = "页码", example = "1"),
        @Parameter(name = "size", description = "每页条数", example = "20")
    })
    @GetMapping
    public ApiResponse<PageResponse<OrderResponse>> listOrders(
        @RequestParam(required = false) String status,
        @RequestParam(required = false) String channel,
        @Valid PageRequest pageRequest) {
        // ...
    }

    @Operation(summary = "查询订单详情")
    @GetMapping("/{orderId}")
    public ApiResponse<OrderDetailResponse> getOrder(
        @Parameter(description = "订单ID", required = true)
        @PathVariable String orderId) {
        // ...
    }

    @Operation(summary = "取消订单")
    @PostMapping("/{orderId}/cancel")
    public ApiResponse<Void> cancelOrder(
        @PathVariable String orderId,
        @RequestBody CancelOrderRequest request) {
        // ...
    }
}
```

### 5.2 接口文档模板

**标准接口文档格式**：

```markdown
## 创建订单

### 基本信息

| 项目 | 说明 |
|-----|-----|
| 接口路径 | POST /api/v1/orders |
| 接口描述 | 创建新订单 |
| 认证方式 | API Key + 签名 |
| 限流规则 | 100次/分钟/API Key |

### 请求参数

#### Header参数

| 参数名 | 类型 | 必填 | 说明 |
|-------|-----|-----|-----|
| Authorization | String | 是 | API Key，格式：ApiKey xxx |
| X-Timestamp | String | 是 | 时间戳（毫秒） |
| X-Nonce | String | 是 | 随机字符串 |
| X-Signature | String | 是 | 签名 |

#### Body参数

| 参数名 | 类型 | 必填 | 说明 |
|-------|-----|-----|-----|
| channel | String | 是 | 销售渠道：AMAZON/EBAY/SHOPIFY |
| customerId | String | 是 | 客户ID |
| items | Array | 是 | 订单明细 |
| items[].skuId | String | 是 | SKU编码 |
| items[].quantity | Integer | 是 | 数量，1-9999 |
| items[].unitPrice | Decimal | 是 | 单价 |
| shippingAddress | Object | 是 | 收货地址 |
| totalAmount | Decimal | 是 | 订单总金额 |
| currency | String | 否 | 币种，默认USD |

### 请求示例

```json
{
    "channel": "AMAZON",
    "customerId": "CUST001",
    "items": [
        {
            "skuId": "SKU001",
            "quantity": 2,
            "unitPrice": 99.99
        }
    ],
    "shippingAddress": {
        "name": "John Doe",
        "phone": "+1-123-456-7890",
        "country": "US",
        "state": "CA",
        "city": "Los Angeles",
        "address1": "123 Main St",
        "zipCode": "90001"
    },
    "totalAmount": 199.98,
    "currency": "USD"
}
```

### 响应参数

| 参数名 | 类型 | 说明 |
|-------|-----|-----|
| code | Integer | 状态码，0表示成功 |
| message | String | 状态描述 |
| data.orderId | String | 订单ID |
| data.status | String | 订单状态 |
| data.createdAt | Long | 创建时间戳 |

### 响应示例

**成功响应**：

```json
{
    "code": 0,
    "message": "success",
    "data": {
        "orderId": "ORD202402040001",
        "status": "PENDING",
        "createdAt": 1707033600000
    },
    "timestamp": 1707033600000,
    "traceId": "a1b2c3d4e5f6"
}
```

**失败响应**：

```json
{
    "code": 200001,
    "message": "库存不足",
    "data": null,
    "timestamp": 1707033600000,
    "traceId": "a1b2c3d4e5f6",
    "errors": [
        {
            "field": "items[0].quantity",
            "message": "SKU001库存不足，当前可用: 1，请求数量: 2"
        }
    ]
}
```

### 错误码

| 错误码 | 说明 | 处理建议 |
|-------|-----|---------|
| 0 | 成功 | - |
| 1001 | 参数错误 | 检查请求参数 |
| 200001 | 库存不足 | 减少数量或更换SKU |
| 300002 | 商品已下架 | 更换商品 |
```

### 5.3 SDK生成

**使用OpenAPI Generator生成客户端SDK**：

```bash
# 生成Java SDK
openapi-generator generate \
  -i http://localhost:8080/v3/api-docs \
  -g java \
  -o ./sdk/java \
  --additional-properties=library=okhttp-gson

# 生成Python SDK
openapi-generator generate \
  -i http://localhost:8080/v3/api-docs \
  -g python \
  -o ./sdk/python
```

---

## 六、实战案例：订单API设计

### 6.1 完整的订单API

```java
@RestController
@RequestMapping("/api/v1/orders")
@Tag(name = "订单管理")
@Validated
public class OrderController {

    @Autowired
    private OrderService orderService;

    /**
     * 创建订单
     */
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    @RateLimit(limit = 100, window = 60, type = LimitType.API_KEY)
    public ApiResponse<OrderResponse> createOrder(
            @RequestBody @Valid CreateOrderRequest request) {
        Order order = orderService.createOrder(request);
        return ApiResponse.success(OrderResponse.from(order));
    }

    /**
     * 查询订单列表
     */
    @GetMapping
    public ApiResponse<PageResponse<OrderResponse>> listOrders(
            @RequestParam(required = false) String status,
            @RequestParam(required = false) String channel,
            @RequestParam(required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate startDate,
            @RequestParam(required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate endDate,
            @Valid PageRequest pageRequest) {

        OrderQuery query = OrderQuery.builder()
            .status(status)
            .channel(channel)
            .startDate(startDate)
            .endDate(endDate)
            .build();

        Page<Order> page = orderService.listOrders(query, pageRequest.toPageable());
        return ApiResponse.success(PageResponse.of(page.map(OrderResponse::from)));
    }

    /**
     * 查询订单详情
     */
    @GetMapping("/{orderId}")
    public ApiResponse<OrderDetailResponse> getOrder(@PathVariable String orderId) {
        Order order = orderService.getOrder(orderId);
        return ApiResponse.success(OrderDetailResponse.from(order));
    }

    /**
     * 更新订单
     */
    @PatchMapping("/{orderId}")
    public ApiResponse<OrderResponse> updateOrder(
            @PathVariable String orderId,
            @RequestBody @Valid UpdateOrderRequest request) {
        Order order = orderService.updateOrder(orderId, request);
        return ApiResponse.success(OrderResponse.from(order));
    }

    /**
     * 取消订单
     */
    @PostMapping("/{orderId}/cancel")
    public ApiResponse<Void> cancelOrder(
            @PathVariable String orderId,
            @RequestBody @Valid CancelOrderRequest request) {
        orderService.cancelOrder(orderId, request.getReason());
        return ApiResponse.success(null);
    }

    /**
     * 确认订单
     */
    @PostMapping("/{orderId}/confirm")
    public ApiResponse<OrderResponse> confirmOrder(@PathVariable String orderId) {
        Order order = orderService.confirmOrder(orderId);
        return ApiResponse.success(OrderResponse.from(order));
    }

    /**
     * 订单发货
     */
    @PostMapping("/{orderId}/ship")
    public ApiResponse<OrderResponse> shipOrder(
            @PathVariable String orderId,
            @RequestBody @Valid ShipOrderRequest request) {
        Order order = orderService.shipOrder(orderId, request);
        return ApiResponse.success(OrderResponse.from(order));
    }

    /**
     * 获取订单明细
     */
    @GetMapping("/{orderId}/items")
    public ApiResponse<List<OrderItemResponse>> getOrderItems(@PathVariable String orderId) {
        List<OrderItem> items = orderService.getOrderItems(orderId);
        return ApiResponse.success(items.stream()
            .map(OrderItemResponse::from)
            .collect(Collectors.toList()));
    }

    /**
     * 获取订单物流信息
     */
    @GetMapping("/{orderId}/tracking")
    public ApiResponse<TrackingResponse> getOrderTracking(@PathVariable String orderId) {
        TrackingInfo tracking = orderService.getOrderTracking(orderId);
        return ApiResponse.success(TrackingResponse.from(tracking));
    }
}
```

### 6.2 API设计检查清单

| 检查项 | 说明 | 状态 |
|-------|-----|-----|
| URL命名 | 使用名词复数、小写字母、连字符 | ✅ |
| HTTP方法 | 正确使用GET/POST/PUT/PATCH/DELETE | ✅ |
| 状态码 | 正确使用HTTP状态码 | ✅ |
| 响应格式 | 统一的响应结构 | ✅ |
| 错误处理 | 完善的错误码和错误信息 | ✅ |
| 参数校验 | 使用JSR-303注解校验 | ✅ |
| 版本管理 | URL版本号 | ✅ |
| 认证授权 | API Key + 签名 | ✅ |
| 限流保护 | 接口级别限流 | ✅ |
| 文档完善 | OpenAPI注解 | ✅ |

---

## 七、总结

### 7.1 核心要点

1. **RESTful设计**：资源导向、统一接口、无状态
2. **命名规范**：名词复数、小写连字符、层级路径
3. **响应规范**：统一格式、错误码分层、分页标准化
4. **版本管理**：URL版本、生命周期管理、兼容性设计
5. **安全设计**：认证授权、签名验证、限流熔断
6. **文档规范**：OpenAPI标准、完整示例、SDK生成

### 7.2 API设计原则

| 原则 | 说明 |
|-----|-----|
| 一致性 | 所有API遵循相同的规范 |
| 简洁性 | 接口设计简单直观 |
| 安全性 | 认证、授权、限流缺一不可 |
| 可扩展 | 预留扩展空间，向后兼容 |
| 可观测 | 日志、监控、追踪完善 |

### 7.3 下一步

- [ ] 制定团队API设计规范文档
- [ ] 搭建API网关统一管理
- [ ] 建立API审核流程
- [ ] 完善API监控告警

---

> **系列文章导航**
>
> 本文是《跨境电商数字化转型指南》系列的第26篇
>
> - [x] 25. 系统集成架构设计
> - [x] 26. API设计最佳实践（本文）
> - [ ] 27. 数据同步策略详解
> - [ ] 28. 异常处理与监控告警
