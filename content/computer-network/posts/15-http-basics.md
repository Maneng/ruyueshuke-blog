---
title: "HTTP协议基础：请求方法、状态码与头部详解"
date: 2025-11-21T17:20:00+08:00
draft: false
tags: ["计算机网络", "HTTP", "应用层协议", "RESTful"]
categories: ["技术"]
description: "深入理解HTTP协议基础，请求方法、状态码含义、请求头响应头、Cookie与Session机制"
series: ["计算机网络从入门到精通"]
weight: 15
stage: 3
stageTitle: "应用层协议篇"
---

## HTTP协议概述

**HTTP（HyperText Transfer Protocol）**：超文本传输协议

**核心特点**：
- 基于TCP（可靠传输）
- 无状态协议（每次请求独立）
- 请求-响应模式
- 文本协议（HTTP/1.x）

---

## HTTP请求方法

### 常用方法

| 方法 | 用途 | 是否幂等 | 是否安全 |
|------|------|---------|---------|
| **GET** | 获取资源 | ✅ 是 | ✅ 是 |
| **POST** | 创建资源/提交数据 | ❌ 否 | ❌ 否 |
| **PUT** | 更新资源（完整替换） | ✅ 是 | ❌ 否 |
| **PATCH** | 更新资源（部分修改） | ❌ 否 | ❌ 否 |
| **DELETE** | 删除资源 | ✅ 是 | ❌ 否 |
| **HEAD** | 获取响应头（不返回body） | ✅ 是 | ✅ 是 |
| **OPTIONS** | 查询支持的方法 | ✅ 是 | ✅ 是 |

**幂等性**：多次调用效果相同
**安全性**：不修改服务器状态

### RESTful API设计

```java
// 用户管理API
@RestController
@RequestMapping("/api/users")
public class UserController {

    // GET /api/users - 查询所有用户
    @GetMapping
    public List<User> listUsers() {
        return userService.findAll();
    }

    // GET /api/users/123 - 查询单个用户
    @GetMapping("/{id}")
    public User getUser(@PathVariable Long id) {
        return userService.findById(id);
    }

    // POST /api/users - 创建用户
    @PostMapping
    public User createUser(@RequestBody User user) {
        return userService.create(user);
    }

    // PUT /api/users/123 - 完整更新用户
    @PutMapping("/{id}")
    public User updateUser(@PathVariable Long id, @RequestBody User user) {
        return userService.update(id, user);
    }

    // PATCH /api/users/123 - 部分更新用户
    @PatchMapping("/{id}")
    public User patchUser(@PathVariable Long id, @RequestBody Map<String, Object> updates) {
        return userService.patch(id, updates);
    }

    // DELETE /api/users/123 - 删除用户
    @DeleteMapping("/{id}")
    public void deleteUser(@PathVariable Long id) {
        userService.delete(id);
    }
}
```

---

## HTTP状态码

### 分类

| 类别 | 含义 | 常见状态码 |
|------|------|-----------|
| **1xx** | 信息响应 | 100 Continue, 101 Switching Protocols |
| **2xx** | 成功 | 200 OK, 201 Created, 204 No Content |
| **3xx** | 重定向 | 301 Moved Permanently, 302 Found, 304 Not Modified |
| **4xx** | 客户端错误 | 400 Bad Request, 401 Unauthorized, 403 Forbidden, 404 Not Found |
| **5xx** | 服务器错误 | 500 Internal Server Error, 502 Bad Gateway, 503 Service Unavailable |

### 重要状态码详解

#### 200 OK
```http
HTTP/1.1 200 OK
Content-Type: application/json

{"id": 123, "name": "张三"}
```

#### 201 Created
```http
HTTP/1.1 201 Created
Location: /api/users/123

{"id": 123, "name": "张三"}
```

#### 204 No Content
```http
HTTP/1.1 204 No Content

# 删除成功，无返回内容
```

#### 301 vs 302
```
301 Moved Permanently：永久重定向（浏览器会缓存）
302 Found：临时重定向（不缓存）

示例：
旧网站 http://old.com → 301 → http://new.com
```

#### 304 Not Modified
```http
# 客户端请求
GET /api/users/123
If-None-Match: "abc123"

# 服务器响应（资源未改变）
HTTP/1.1 304 Not Modified
ETag: "abc123"

# 客户端使用缓存
```

#### 401 vs 403
```
401 Unauthorized：未认证（需要登录）
403 Forbidden：已认证但无权限（权限不足）

示例：
未登录访问：401
普通用户访问管理员接口：403
```

#### 502 vs 503 vs 504
```
502 Bad Gateway：网关从上游服务器收到无效响应
503 Service Unavailable：服务暂时不可用（维护/过载）
504 Gateway Timeout：网关超时

微服务场景：
API网关 → 用户服务（宕机）→ 502
API网关 → 用户服务（超时）→ 504
用户服务主动拒绝（限流）→ 503
```

---

## HTTP请求头

### 常用请求头

| 请求头 | 作用 | 示例 |
|-------|------|------|
| **Host** | 指定服务器域名 | `Host: api.example.com` |
| **User-Agent** | 客户端信息 | `User-Agent: Mozilla/5.0...` |
| **Accept** | 可接受的响应类型 | `Accept: application/json` |
| **Content-Type** | 请求体类型 | `Content-Type: application/json` |
| **Authorization** | 认证信息 | `Authorization: Bearer <token>` |
| **Cookie** | 会话Cookie | `Cookie: sessionId=abc123` |
| **If-None-Match** | 条件请求（ETag） | `If-None-Match: "abc123"` |
| **Range** | 请求部分内容 | `Range: bytes=0-1023` |

### 微服务场景实战

```java
// Feign客户端添加请求头
@FeignClient(name = "user-service")
public interface UserClient {

    @GetMapping("/api/users/{id}")
    User getUser(@PathVariable Long id,
                 @RequestHeader("Authorization") String token,
                 @RequestHeader("X-Request-Id") String requestId);
}

// 全局请求拦截器
@Component
public class FeignRequestInterceptor implements RequestInterceptor {
    @Override
    public void apply(RequestTemplate template) {
        // 添加链路追踪ID
        template.header("X-Trace-Id", MDC.get("traceId"));

        // 添加租户ID（多租户场景）
        template.header("X-Tenant-Id", TenantContext.getTenantId());

        // 添加认证Token
        template.header("Authorization", "Bearer " + getToken());
    }
}
```

---

## HTTP响应头

### 常用响应头

| 响应头 | 作用 | 示例 |
|-------|------|------|
| **Content-Type** | 响应体类型 | `Content-Type: application/json; charset=utf-8` |
| **Content-Length** | 响应体长度 | `Content-Length: 1234` |
| **Cache-Control** | 缓存策略 | `Cache-Control: max-age=3600` |
| **ETag** | 资源版本标识 | `ETag: "abc123"` |
| **Location** | 重定向地址 | `Location: /api/users/123` |
| **Set-Cookie** | 设置Cookie | `Set-Cookie: sessionId=abc; HttpOnly` |
| **Access-Control-Allow-Origin** | CORS跨域 | `Access-Control-Allow-Origin: *` |

### Spring Boot响应头配置

```java
// 方式1：在Controller中设置
@GetMapping("/api/users/{id}")
public ResponseEntity<User> getUser(@PathVariable Long id) {
    User user = userService.findById(id);

    return ResponseEntity.ok()
        .header("X-Custom-Header", "custom-value")
        .eTag("\"" + user.getVersion() + "\"")  // ETag
        .cacheControl(CacheControl.maxAge(1, TimeUnit.HOURS))  // 缓存1小时
        .body(user);
}

// 方式2：全局响应拦截器
@Component
public class ResponseHeaderInterceptor implements HandlerInterceptor {
    @Override
    public void postHandle(HttpServletRequest request,
                          HttpServletResponse response,
                          Object handler,
                          ModelAndView modelAndView) {
        // 添加安全响应头
        response.setHeader("X-Content-Type-Options", "nosniff");
        response.setHeader("X-Frame-Options", "DENY");
        response.setHeader("X-XSS-Protection", "1; mode=block");
    }
}
```

---

## Cookie与Session

### Cookie工作原理

```
[首次请求]
客户端 → 服务器: GET /login
服务器 → 客户端: Set-Cookie: sessionId=abc123; Path=/; HttpOnly

[后续请求]
客户端 → 服务器: GET /api/users
                 Cookie: sessionId=abc123
服务器根据sessionId识别用户
```

### Cookie属性

| 属性 | 作用 | 示例 |
|------|------|------|
| **Expires** | 过期时间（绝对时间） | `Expires=Wed, 21 Oct 2025 07:28:00 GMT` |
| **Max-Age** | 有效期（秒） | `Max-Age=3600` |
| **Domain** | 作用域 | `Domain=.example.com` |
| **Path** | 路径 | `Path=/api` |
| **Secure** | 仅HTTPS | `Secure` |
| **HttpOnly** | 禁止JavaScript访问 | `HttpOnly` |
| **SameSite** | 防止CSRF | `SameSite=Strict` |

### Session管理（微服务）

**问题**：微服务场景Session共享

**方案1：Redis Session**
```yaml
# application.yml
spring:
  session:
    store-type: redis
  redis:
    host: localhost
    port: 6379
```

```java
// Spring Session自动管理
@RestController
public class AuthController {

    @PostMapping("/login")
    public void login(HttpSession session, @RequestBody LoginRequest req) {
        User user = authService.authenticate(req.getUsername(), req.getPassword());
        session.setAttribute("user", user);  // 存入Redis
    }

    @GetMapping("/profile")
    public User profile(HttpSession session) {
        return (User) session.getAttribute("user");  // 从Redis读取
    }
}
```

**方案2：JWT Token（推荐）**
```java
// 无状态认证，不需要Session
@PostMapping("/login")
public LoginResponse login(@RequestBody LoginRequest req) {
    User user = authService.authenticate(req.getUsername(), req.getPassword());

    // 生成JWT Token
    String token = jwtUtil.generateToken(user);

    return new LoginResponse(token);
}

@GetMapping("/profile")
public User profile(@RequestHeader("Authorization") String authHeader) {
    String token = authHeader.substring(7);  // 去掉 "Bearer "
    User user = jwtUtil.parseToken(token);
    return user;
}
```

---

## Content-Type详解

### 常见类型

| Content-Type | 用途 | 示例 |
|--------------|------|------|
| **application/json** | JSON数据 | `{"name": "张三"}` |
| **application/x-www-form-urlencoded** | 表单提交 | `name=%E5%BC%A0%E4%B8%89&age=20` |
| **multipart/form-data** | 文件上传 | 二进制数据 + 边界分隔 |
| **text/plain** | 纯文本 | `Hello World` |
| **text/html** | HTML | `<html>...</html>` |
| **application/xml** | XML | `<user><name>张三</name></user>` |

### 文件上传示例

```java
@PostMapping("/upload")
public UploadResponse uploadFile(@RequestParam("file") MultipartFile file) {
    // Content-Type: multipart/form-data; boundary=----WebKitFormBoundary

    String filename = file.getOriginalFilename();
    long size = file.getSize();
    String contentType = file.getContentType();

    // 保存文件
    String path = storageService.save(file);

    return new UploadResponse(path, filename, size);
}
```

---

## 微服务实战案例

### 案例1：API网关统一认证

```java
// Spring Cloud Gateway
@Component
public class AuthFilter implements GlobalFilter, Ordered {

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        ServerHttpRequest request = exchange.getRequest();

        // 1. 获取Token
        String token = request.getHeaders().getFirst("Authorization");
        if (token == null || !token.startsWith("Bearer ")) {
            return unauthorized(exchange, "缺少认证Token");
        }

        // 2. 验证Token
        try {
            JwtClaims claims = jwtUtil.parseToken(token.substring(7));

            // 3. 传递用户信息到下游服务
            ServerHttpRequest mutatedRequest = request.mutate()
                .header("X-User-Id", claims.getUserId())
                .header("X-Username", claims.getUsername())
                .build();

            return chain.filter(exchange.mutate().request(mutatedRequest).build());

        } catch (Exception e) {
            return unauthorized(exchange, "Token无效");
        }
    }

    private Mono<Void> unauthorized(ServerWebExchange exchange, String message) {
        ServerHttpResponse response = exchange.getResponse();
        response.setStatusCode(HttpStatus.UNAUTHORIZED);
        response.getHeaders().set("Content-Type", "application/json");

        String body = "{\"error\": \"" + message + "\"}";
        DataBuffer buffer = response.bufferFactory().wrap(body.getBytes());

        return response.writeWith(Mono.just(buffer));
    }

    @Override
    public int getOrder() {
        return -100;  // 高优先级
    }
}
```

### 案例2：服务间调用携带上下文

```java
// 订单服务调用用户服务
@Service
public class OrderService {

    @Autowired
    private RestTemplate restTemplate;

    public Order createOrder(CreateOrderRequest request) {
        // 1. 获取当前用户信息（从请求上下文）
        String userId = SecurityContextHolder.getContext().getAuthentication().getName();

        // 2. 调用用户服务
        HttpHeaders headers = new HttpHeaders();
        headers.set("Authorization", "Bearer " + getToken());
        headers.set("X-Request-Id", UUID.randomUUID().toString());
        headers.set("X-Trace-Id", MDC.get("traceId"));

        HttpEntity<Void> entity = new HttpEntity<>(headers);

        User user = restTemplate.exchange(
            "http://user-service/api/users/" + userId,
            HttpMethod.GET,
            entity,
            User.class
        ).getBody();

        // 3. 创建订单
        Order order = new Order();
        order.setUserId(user.getId());
        order.setUsername(user.getName());
        // ...

        return orderRepository.save(order);
    }
}
```

### 案例3：HTTP响应码最佳实践

```java
@RestControllerAdvice
public class GlobalExceptionHandler {

    // 业务异常 → 400 Bad Request
    @ExceptionHandler(BusinessException.class)
    public ResponseEntity<ErrorResponse> handleBusinessException(BusinessException e) {
        return ResponseEntity
            .badRequest()
            .body(new ErrorResponse(e.getCode(), e.getMessage()));
    }

    // 未认证 → 401 Unauthorized
    @ExceptionHandler(AuthenticationException.class)
    public ResponseEntity<ErrorResponse> handleAuthException(AuthenticationException e) {
        return ResponseEntity
            .status(HttpStatus.UNAUTHORIZED)
            .body(new ErrorResponse("AUTH_FAILED", "认证失败"));
    }

    // 无权限 → 403 Forbidden
    @ExceptionHandler(AccessDeniedException.class)
    public ResponseEntity<ErrorResponse> handleAccessDenied(AccessDeniedException e) {
        return ResponseEntity
            .status(HttpStatus.FORBIDDEN)
            .body(new ErrorResponse("ACCESS_DENIED", "权限不足"));
    }

    // 资源不存在 → 404 Not Found
    @ExceptionHandler(ResourceNotFoundException.class)
    public ResponseEntity<ErrorResponse> handleNotFound(ResourceNotFoundException e) {
        return ResponseEntity
            .status(HttpStatus.NOT_FOUND)
            .body(new ErrorResponse("NOT_FOUND", e.getMessage()));
    }

    // 服务异常 → 500 Internal Server Error
    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorResponse> handleException(Exception e) {
        log.error("服务异常", e);
        return ResponseEntity
            .status(HttpStatus.INTERNAL_SERVER_ERROR)
            .body(new ErrorResponse("INTERNAL_ERROR", "服务内部错误"));
    }
}
```

---

## 总结

### 核心要点

1. **HTTP请求方法**：GET（查询）、POST（创建）、PUT（更新）、DELETE（删除）
2. **HTTP状态码**：2xx成功、3xx重定向、4xx客户端错误、5xx服务器错误
3. **HTTP头部**：请求头携带元数据，响应头控制缓存、安全等
4. **Cookie与Session**：微服务推荐JWT Token无状态认证

### 下一篇预告

《HTTP协议进阶：Keep-Alive、缓存机制与内容协商》
