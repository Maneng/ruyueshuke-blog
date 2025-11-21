---
title: "限流算法：固定窗口、滑动窗口与令牌桶"
date: 2025-01-21T23:00:00+08:00
draft: false
tags: ["Redis", "限流", "滑动窗口", "令牌桶"]
categories: ["技术"]
description: "掌握Redis实现的多种限流算法，保护系统免受流量冲击，实现API限流、IP限流等场景"
weight: 29
stage: 3
stageTitle: "进阶特性篇"
---

## 限流算法对比

| 算法 | 实现难度 | 精确度 | 内存占用 | 适用场景 |
|------|---------|--------|---------|---------|
| **固定窗口** | 简单 | 低 | 低 | 粗粒度限流 |
| **滑动窗口** | 中等 | 高 | 中 | 精确限流 |
| **漏桶** | 中等 | 高 | 中 | 流量整形 |
| **令牌桶** | 复杂 | 高 | 中 | 允许突发 |

## 1. 固定窗口算法

**原理**：时间窗口内计数，超过限制则拒绝

```java
@Service
public class FixedWindowRateLimiter {
    @Autowired
    private RedisTemplate<String, String> redis;

    // 限流检查
    public boolean isAllowed(String key, int limit, int windowSeconds) {
        String counterKey = key + ":" + (System.currentTimeMillis() / 1000 / windowSeconds);

        Long current = redis.opsForValue().increment(counterKey);
        if (current == 1) {
            redis.expire(counterKey, windowSeconds, TimeUnit.SECONDS);
        }

        return current != null && current <= limit;
    }
}

// 使用示例
public boolean checkLimit(String userId) {
    return rateLimiter.isAllowed("api:user:" + userId, 100, 60);  // 每分钟100次
}
```

**问题**：临界问题
```
窗口1（00:00-00:59）：99次请求（00:58-00:59）
窗口2（01:00-01:59）：99次请求（01:00-01:01）
实际：2秒内198次请求（超限）
```

## 2. 滑动窗口算法（ZSet实现）

```java
@Service
public class SlidingWindowRateLimiter {
    @Autowired
    private RedisTemplate<String, String> redis;

    private static final String SCRIPT =
        "local key = KEYS[1] " +
        "local limit = tonumber(ARGV[1]) " +
        "local window = tonumber(ARGV[2]) " +
        "local now = tonumber(ARGV[3]) " +
        "local clearBefore = now - window * 1000 " +
        "redis.call('ZREMRANGEBYSCORE', key, 0, clearBefore) " +
        "local count = redis.call('ZCARD', key) " +
        "if count < limit then " +
        "  redis.call('ZADD', key, now, now) " +
        "  redis.call('EXPIRE', key, window) " +
        "  return 1 " +
        "else " +
        "  return 0 " +
        "end";

    public boolean isAllowed(String key, int limit, int windowSeconds) {
        long now = System.currentTimeMillis();
        Long result = redis.execute(
            RedisScript.of(SCRIPT, Long.class),
            Collections.singletonList(key),
            String.valueOf(limit),
            String.valueOf(windowSeconds),
            String.valueOf(now)
        );
        return result != null && result == 1;
    }
}
```

**优势**：精确控制，无临界问题

## 3. 令牌桶算法

```java
@Service
public class TokenBucketRateLimiter {
    @Autowired
    private RedisTemplate<String, String> redis;

    private static final String SCRIPT =
        "local key = KEYS[1] " +
        "local capacity = tonumber(ARGV[1]) " +
        "local rate = tonumber(ARGV[2]) " +
        "local now = tonumber(ARGV[3]) " +
        "local requested = tonumber(ARGV[4]) " +

        "local bucket = redis.call('HMGET', key, 'tokens', 'last_time') " +
        "local tokens = tonumber(bucket[1]) or capacity " +
        "local lastTime = tonumber(bucket[2]) or now " +

        "local deltaTime = math.max(0, now - lastTime) " +
        "local newTokens = math.min(capacity, tokens + deltaTime * rate / 1000) " +

        "if newTokens >= requested then " +
        "  redis.call('HMSET', key, 'tokens', newTokens - requested, 'last_time', now) " +
        "  redis.call('EXPIRE', key, 60) " +
        "  return 1 " +
        "else " +
        "  redis.call('HMSET', key, 'tokens', newTokens, 'last_time', now) " +
        "  redis.call('EXPIRE', key, 60) " +
        "  return 0 " +
        "end";

    // capacity: 桶容量, rate: 每秒产生令牌数
    public boolean isAllowed(String key, int capacity, double rate, int tokens) {
        long now = System.currentTimeMillis();
        Long result = redis.execute(
            RedisScript.of(SCRIPT, Long.class),
            Collections.singletonList(key),
            String.valueOf(capacity),
            String.valueOf(rate),
            String.valueOf(now),
            String.valueOf(tokens)
        );
        return result != null && result == 1;
    }
}

// 使用示例：桶容量100，每秒生成10个令牌
rateLimiter.isAllowed("api:" + apiKey, 100, 10, 1);
```

## 实战案例

### 案例1：API限流

```java
@Aspect
@Component
public class RateLimitAspect {
    @Autowired
    private SlidingWindowRateLimiter rateLimiter;

    @Around("@annotation(rateLimit)")
    public Object around(ProceedingJoinPoint pjp, RateLimit rateLimit) throws Throwable {
        HttpServletRequest request =
            ((ServletRequestAttributes) RequestContextHolder.getRequestAttributes()).getRequest();

        String userId = request.getHeader("User-Id");
        String key = "ratelimit:" + rateLimit.key() + ":" + userId;

        if (!rateLimiter.isAllowed(key, rateLimit.limit(), rateLimit.window())) {
            throw new RateLimitException("请求过于频繁，请稍后再试");
        }

        return pjp.proceed();
    }
}

// 使用
@RateLimit(key = "getUserInfo", limit = 100, window = 60)
@GetMapping("/user/{id}")
public User getUserInfo(@PathVariable Long id) {
    return userService.getUser(id);
}
```

### 案例2：IP限流

```java
@Component
public class IPRateLimitInterceptor implements HandlerInterceptor {
    @Autowired
    private FixedWindowRateLimiter rateLimiter;

    @Override
    public boolean preHandle(HttpServletRequest request,
                           HttpServletResponse response,
                           Object handler) throws Exception {
        String ip = getClientIP(request);
        String key = "ip:limit:" + ip;

        if (!rateLimiter.isAllowed(key, 1000, 60)) {  // 每分钟1000次
            response.setStatus(429);  // Too Many Requests
            response.getWriter().write("访问过于频繁");
            return false;
        }

        return true;
    }

    private String getClientIP(HttpServletRequest request) {
        String ip = request.getHeader("X-Forwarded-For");
        if (ip == null || ip.isEmpty()) {
            ip = request.getRemoteAddr();
        }
        return ip;
    }
}
```

### 案例3：短信验证码限流

```java
@Service
public class SmsService {
    @Autowired
    private SlidingWindowRateLimiter rateLimiter;

    public void sendVerifyCode(String mobile) {
        // 1分钟内最多1次
        String minuteKey = "sms:limit:minute:" + mobile;
        if (!rateLimiter.isAllowed(minuteKey, 1, 60)) {
            throw new BusinessException("发送过于频繁，请1分钟后再试");
        }

        // 1小时内最多5次
        String hourKey = "sms:limit:hour:" + mobile;
        if (!rateLimiter.isAllowed(hourKey, 5, 3600)) {
            throw new BusinessException("发送过于频繁，请1小时后再试");
        }

        // 1天内最多10次
        String dayKey = "sms:limit:day:" + mobile;
        if (!rateLimiter.isAllowed(dayKey, 10, 86400)) {
            throw new BusinessException("今日发送次数已达上限");
        }

        // 发送短信
        doSendSms(mobile);
    }

    private void doSendSms(String mobile) {
        // 实际发送逻辑
    }
}
```

### 案例4：下载限流

```java
@Service
public class DownloadService {
    @Autowired
    private TokenBucketRateLimiter rateLimiter;

    public void downloadFile(String userId, String fileId) {
        String key = "download:limit:" + userId;

        // 令牌桶：容量100MB，速率10MB/s
        if (!rateLimiter.isAllowed(key, 100, 10, 1)) {
            throw new BusinessException("下载速度超限，请稍后再试");
        }

        // 下载文件
        doDownload(fileId);
    }

    private void doDownload(String fileId) {
        // 实际下载逻辑
    }
}
```

## 分布式限流

### Nginx + Lua

```lua
-- nginx.conf
location /api {
    access_by_lua_block {
        local redis = require "resty.redis"
        local red = redis:new()
        red:connect("127.0.0.1", 6379)

        local key = "ratelimit:" .. ngx.var.remote_addr
        local limit = 100
        local window = 60

        local count = red:incr(key)
        if count == 1 then
            red:expire(key, window)
        end

        if count > limit then
            ngx.status = 429
            ngx.say("Too Many Requests")
            return ngx.exit(429)
        end
    }

    proxy_pass http://backend;
}
```

## 监控与告警

```java
@Component
public class RateLimitMonitor {
    @Autowired
    private RedisTemplate<String, String> redis;

    @Scheduled(fixedRate = 60000)  // 每分钟
    public void monitor() {
        Set<String> keys = redis.keys("ratelimit:*");
        if (keys == null) return;

        Map<String, Long> stats = new HashMap<>();
        for (String key : keys) {
            Long count = redis.opsForValue().increment(key, 0);
            stats.put(key, count);
        }

        // 告警：某个key限流次数过高
        stats.forEach((key, count) -> {
            if (count > 10000) {
                log.warn("限流触发频繁: key={}, count={}", key, count);
                // 发送告警
            }
        });
    }
}
```

## 最佳实践

1. **根据场景选择算法**：
   - 简单限流 → 固定窗口
   - 精确限流 → 滑动窗口
   - 允许突发 → 令牌桶

2. **多级限流**：
   - IP级别：防止单个IP滥用
   - 用户级别：防止单个用户滥用
   - 全局级别：保护系统整体

3. **降级策略**：
   - Redis不可用时，使用本地限流
   - Guava RateLimiter作为降级

4. **监控告警**：
   - 监控限流触发频率
   - 告警异常流量
   - 分析限流日志

## 总结

**核心要点**：
- 固定窗口：简单，有临界问题
- 滑动窗口：精确，适合大多数场景
- 令牌桶：允许突发，适合流量整形

**典型场景**：
- API限流
- IP限流
- 短信/邮件限流
- 下载限速

**注意事项**：
- Lua脚本保证原子性
- 降级方案（Redis不可用）
- 监控限流触发情况
- 多级限流保护
