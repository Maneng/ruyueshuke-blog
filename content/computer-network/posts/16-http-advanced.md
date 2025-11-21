---
title: "HTTP协议进阶：Keep-Alive、缓存机制与内容协商"
date: 2025-11-20T17:30:00+08:00
draft: false
tags: ["计算机网络", "HTTP", "缓存", "Keep-Alive"]
categories: ["技术"]
description: "深入理解HTTP/1.1持久连接、缓存策略、内容协商机制，以及微服务场景的HTTP优化实践"
series: ["计算机网络从入门到精通"]
weight: 16
stage: 3
stageTitle: "应用层协议篇"
---

## HTTP/1.0 vs HTTP/1.1

### HTTP/1.0的问题

```
短连接（每次请求都要三次握手）：

客户端 → 服务器: SYN（握手）
客户端 ← 服务器: SYN-ACK
客户端 → 服务器: ACK
客户端 → 服务器: GET /index.html
客户端 ← 服务器: HTTP/1.0 200 OK
客户端 → 服务器: FIN（挥手）

下一个请求又要重新握手！
```

**问题**：
- 每个请求都要建立TCP连接（+1.5 RTT延迟）
- 频繁握手挥手，浪费资源
- 服务器TIME_WAIT状态过多

### HTTP/1.1的改进

**1. 持久连接（Keep-Alive）**：默认开启

```http
# HTTP/1.1请求
GET /api/users HTTP/1.1
Host: api.example.com
Connection: keep-alive

# HTTP/1.1响应
HTTP/1.1 200 OK
Connection: keep-alive
Keep-Alive: timeout=5, max=100
```

**一个TCP连接，多个HTTP请求**：
```
客户端 → 服务器: 三次握手
客户端 → 服务器: GET /api/users
客户端 ← 服务器: 200 OK
客户端 → 服务器: GET /api/orders  # 复用连接
客户端 ← 服务器: 200 OK
客户端 → 服务器: GET /api/products  # 复用连接
客户端 ← 服务器: 200 OK
...（5秒后无请求，关闭连接）
```

**2. 管道化（Pipelining）**：不等响应，连续发送请求

```
客户端连续发送：
GET /1.js
GET /2.js
GET /3.js

服务器按序响应：
200 OK (1.js)
200 OK (2.js)
200 OK (3.js)
```

**问题**：队头阻塞（第一个响应慢会阻塞后续）

---

## Keep-Alive连接池

### Spring RestTemplate连接池

```java
@Configuration
public class RestTemplateConfig {

    @Bean
    public RestTemplate restTemplate() {
        // 连接池配置
        PoolingHttpClientConnectionManager connectionManager =
            new PoolingHttpClientConnectionManager();
        connectionManager.setMaxTotal(200);  // 最大连接数
        connectionManager.setDefaultMaxPerRoute(20);  // 每个路由最大连接数

        // Keep-Alive配置
        HttpClient httpClient = HttpClients.custom()
            .setConnectionManager(connectionManager)
            .setKeepAliveStrategy((response, context) -> {
                // 服务器返回Keep-Alive头部则使用，否则默认30秒
                HeaderElementIterator it = new BasicHeaderElementIterator(
                    response.headerIterator(HTTP.CONN_KEEP_ALIVE));
                while (it.hasNext()) {
                    HeaderElement he = it.nextElement();
                    String param = he.getName();
                    String value = he.getValue();
                    if (value != null && param.equalsIgnoreCase("timeout")) {
                        return Long.parseLong(value) * 1000;
                    }
                }
                return 30 * 1000;  // 默认30秒
            })
            .build();

        HttpComponentsClientHttpRequestFactory factory =
            new HttpComponentsClientHttpRequestFactory(httpClient);
        factory.setConnectTimeout(5000);  // 连接超时5秒
        factory.setReadTimeout(10000);  // 读取超时10秒

        return new RestTemplate(factory);
    }
}
```

### Feign连接池

```yaml
# application.yml
feign:
  httpclient:
    enabled: true  # 启用Apache HttpClient
    max-connections: 200
    max-connections-per-route: 50
    connection-timeout: 5000
    connection-timer-repeat: 3000
  client:
    config:
      default:
        connectTimeout: 5000
        readTimeout: 10000
```

---

## HTTP缓存机制

### 缓存分类

**1. 强缓存**：不请求服务器，直接使用缓存

```http
# 响应头
Cache-Control: max-age=3600  # 缓存1小时
Expires: Wed, 21 Nov 2025 07:28:00 GMT  # 绝对过期时间（HTTP/1.0）
```

**2. 协商缓存**：请求服务器验证缓存是否有效

```http
# 首次请求
GET /api/users/123

# 首次响应
HTTP/1.1 200 OK
ETag: "abc123"
Last-Modified: Wed, 21 Nov 2025 06:28:00 GMT

# 后续请求
GET /api/users/123
If-None-Match: "abc123"  # 或 If-Modified-Since

# 缓存有效
HTTP/1.1 304 Not Modified

# 缓存失效
HTTP/1.1 200 OK
ETag: "def456"
```

### Cache-Control指令

| 指令 | 作用 | 示例 |
|------|------|------|
| **max-age** | 缓存有效期（秒） | `max-age=3600` |
| **no-cache** | 必须验证缓存 | `no-cache` |
| **no-store** | 不缓存 | `no-store` |
| **private** | 仅客户端缓存 | `private` |
| **public** | 可被代理缓存 | `public` |
| **must-revalidate** | 过期必须验证 | `must-revalidate` |

### Spring Boot缓存配置

```java
@GetMapping("/api/users/{id}")
public ResponseEntity<User> getUser(@PathVariable Long id,
                                    @RequestHeader(value = "If-None-Match", required = false) String ifNoneMatch) {
    User user = userService.findById(id);

    // 计算ETag（基于版本号或MD5）
    String etag = "\"" + user.getVersion() + "\"";

    // 如果ETag匹配，返回304
    if (etag.equals(ifNoneMatch)) {
        return ResponseEntity.status(HttpStatus.NOT_MODIFIED).build();
    }

    // 返回200并设置缓存头
    return ResponseEntity.ok()
        .eTag(etag)
        .cacheControl(CacheControl.maxAge(10, TimeUnit.MINUTES))  // 缓存10分钟
        .body(user);
}

// 静态资源缓存
@Configuration
public class WebConfig implements WebMvcConfigurer {
    @Override
    public void addResourceHandlers(ResourceHandlerRegistry registry) {
        registry.addResourceHandler("/static/**")
            .addResourceLocations("classpath:/static/")
            .setCacheControl(CacheControl.maxAge(365, TimeUnit.DAYS));  // 缓存1年
    }
}
```

---

## 内容协商（Content Negotiation）

### Accept头部

```http
# 客户端请求JSON
GET /api/users/123
Accept: application/json

# 客户端请求XML
GET /api/users/123
Accept: application/xml

# 客户端请求HTML
GET /api/users/123
Accept: text/html
```

### Spring Boot内容协商

```java
@RestController
public class UserController {

    // 同一接口支持多种格式
    @GetMapping(value = "/api/users/{id}",
                produces = {MediaType.APPLICATION_JSON_VALUE,
                           MediaType.APPLICATION_XML_VALUE})
    public User getUser(@PathVariable Long id) {
        return userService.findById(id);
    }
}

// 配置XML支持
@Configuration
public class WebConfig {
    @Bean
    public HttpMessageConverter<Object> createXmlHttpMessageConverter() {
        return new MappingJackson2XmlHttpMessageConverter();
    }
}
```

### 压缩协商

```http
# 客户端请求
GET /api/users
Accept-Encoding: gzip, deflate, br

# 服务器响应（gzip压缩）
HTTP/1.1 200 OK
Content-Encoding: gzip
Content-Length: 1234  # 压缩后大小
```

**Spring Boot开启Gzip**：
```yaml
server:
  compression:
    enabled: true
    mime-types: application/json,application/xml,text/html,text/plain
    min-response-size: 1024  # 大于1KB才压缩
```

---

## 微服务HTTP优化实战

### 案例1：API网关缓存

```java
// Spring Cloud Gateway缓存过滤器
@Component
public class CacheFilter implements GlobalFilter, Ordered {

    @Autowired
    private RedisTemplate<String, String> redisTemplate;

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        ServerHttpRequest request = exchange.getRequest();

        // 只缓存GET请求
        if (!request.getMethod().equals(HttpMethod.GET)) {
            return chain.filter(exchange);
        }

        String cacheKey = "cache:" + request.getURI().toString();

        // 尝试从Redis获取缓存
        String cachedResponse = redisTemplate.opsForValue().get(cacheKey);
        if (cachedResponse != null) {
            // 返回缓存
            ServerHttpResponse response = exchange.getResponse();
            response.getHeaders().set("X-Cache", "HIT");
            response.getHeaders().setContentType(MediaType.APPLICATION_JSON);

            DataBuffer buffer = response.bufferFactory().wrap(cachedResponse.getBytes());
            return response.writeWith(Mono.just(buffer));
        }

        // 缓存未命中，继续请求后端
        return chain.filter(exchange).then(Mono.fromRunnable(() -> {
            // 将响应缓存到Redis（5分钟）
            redisTemplate.opsForValue().set(cacheKey, "response", 5, TimeUnit.MINUTES);
        }));
    }

    @Override
    public int getOrder() {
        return -50;
    }
}
```

### 案例2：服务间调用优化

```java
@Service
public class OptimizedOrderService {

    @Autowired
    private RestTemplate restTemplate;

    @Autowired
    private CacheManager cacheManager;

    // 使用Spring Cache缓存用户信息
    @Cacheable(value = "users", key = "#userId")
    public User getUserWithCache(Long userId) {
        return restTemplate.getForObject(
            "http://user-service/api/users/" + userId,
            User.class
        );
    }

    // 批量获取用户（减少HTTP请求次数）
    public Map<Long, User> getUsersBatch(List<Long> userIds) {
        // 一次HTTP请求获取多个用户
        String ids = userIds.stream()
            .map(String::valueOf)
            .collect(Collectors.joining(","));

        User[] users = restTemplate.getForObject(
            "http://user-service/api/users?ids=" + ids,
            User[].class
        );

        return Arrays.stream(users)
            .collect(Collectors.toMap(User::getId, u -> u));
    }

    // 并行请求（减少总延迟）
    public OrderDetail getOrderDetail(Long orderId) {
        Order order = orderRepository.findById(orderId);

        // 并行请求用户服务和产品服务
        CompletableFuture<User> userFuture = CompletableFuture.supplyAsync(() ->
            restTemplate.getForObject(
                "http://user-service/api/users/" + order.getUserId(),
                User.class
            ));

        CompletableFuture<Product> productFuture = CompletableFuture.supplyAsync(() ->
            restTemplate.getForObject(
                "http://product-service/api/products/" + order.getProductId(),
                Product.class
            ));

        // 等待所有请求完成
        CompletableFuture.allOf(userFuture, productFuture).join();

        return new OrderDetail(order, userFuture.join(), productFuture.join());
    }
}
```

### 案例3：HTTP连接监控

```java
@Component
public class HttpClientMetrics {

    @Autowired
    private MeterRegistry meterRegistry;

    @Bean
    public HttpClient monitoredHttpClient() {
        PoolingHttpClientConnectionManager connectionManager =
            new PoolingHttpClientConnectionManager();

        // 注册连接池监控指标
        connectionManager.setMaxTotal(200);
        connectionManager.setDefaultMaxPerRoute(20);

        meterRegistry.gauge("http.client.connections.max", connectionManager,
            cm -> cm.getTotalStats().getMax());
        meterRegistry.gauge("http.client.connections.available", connectionManager,
            cm -> cm.getTotalStats().getAvailable());
        meterRegistry.gauge("http.client.connections.leased", connectionManager,
            cm -> cm.getTotalStats().getLeased());
        meterRegistry.gauge("http.client.connections.pending", connectionManager,
            cm -> cm.getTotalStats().getPending());

        return HttpClients.custom()
            .setConnectionManager(connectionManager)
            .build();
    }
}
```

---

## Range请求（断点续传）

### 客户端请求部分内容

```http
# 请求文件的前1024字节
GET /files/large-file.zip
Range: bytes=0-1023

# 响应
HTTP/1.1 206 Partial Content
Content-Range: bytes 0-1023/102400  # 当前范围/总大小
Content-Length: 1024

[数据...]
```

### Spring Boot实现

```java
@GetMapping("/files/{filename}")
public ResponseEntity<Resource> downloadFile(@PathVariable String filename,
                                             @RequestHeader(value = "Range", required = false) String range) {
    Resource file = storageService.loadAsResource(filename);

    if (range == null) {
        // 完整下载
        return ResponseEntity.ok()
            .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"" + filename + "\"")
            .body(file);
    }

    // 解析Range: bytes=0-1023
    String[] parts = range.replace("bytes=", "").split("-");
    long start = Long.parseLong(parts[0]);
    long end = parts.length > 1 ? Long.parseLong(parts[1]) : file.contentLength() - 1;
    long contentLength = end - start + 1;

    // 返回部分内容
    return ResponseEntity.status(HttpStatus.PARTIAL_CONTENT)
        .header(HttpHeaders.CONTENT_RANGE,
            "bytes " + start + "-" + end + "/" + file.contentLength())
        .contentLength(contentLength)
        .body(new ByteArrayResource(readRange(file, start, end)));
}
```

---

## 总结

### 核心要点

1. **Keep-Alive**：HTTP/1.1默认持久连接，复用TCP连接
2. **连接池**：微服务必须配置连接池，避免频繁建立连接
3. **HTTP缓存**：强缓存（max-age）+ 协商缓存（ETag）
4. **内容协商**：Accept头部支持多种格式响应
5. **优化策略**：批量请求、并行请求、API网关缓存

### 下一篇预告

《HTTPS与TLS/SSL：加密通信与证书验证》