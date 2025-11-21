---
title: "缓存三大问题：穿透、击穿、雪崩的解决方案"
date: 2025-01-21T23:20:00+08:00
draft: false
tags: ["Redis", "缓存穿透", "缓存击穿", "缓存雪崩"]
categories: ["技术"]
description: "深入理解缓存穿透、缓存击穿、缓存雪崩三大经典问题，掌握布隆过滤器、互斥锁、过期时间分散等解决方案"
weight: 31
stage: 4
stageTitle: "生产实践篇"
---

## 缓存穿透（Cache Penetration）

**定义**：查询不存在的数据，缓存和数据库都没有，每次请求都打到数据库

**场景**：恶意攻击，大量查询不存在的key

```
请求key="user:-1" → Redis没有 → DB没有 → 返回null
请求key="user:-2" → Redis没有 → DB没有 → 返回null
...大量请求直接打垮数据库
```

### 解决方案1：布隆过滤器

```java
@Service
public class UserService {
    @Autowired
    private RedissonClient redisson;
    @Autowired
    private UserMapper userMapper;

    private RBloomFilter<Long> userBloomFilter;

    @PostConstruct
    public void init() {
        userBloomFilter = redisson.getBloomFilter("user:bloom");
        userBloomFilter.tryInit(10000000L, 0.01);

        // 加载所有userId
        List<Long> userIds = userMapper.selectAllUserIds();
        userIds.forEach(userBloomFilter::add);
    }

    public User getUser(Long userId) {
        // 1. 布隆过滤器判断
        if (!userBloomFilter.contains(userId)) {
            return null;  // 一定不存在
        }

        // 2. 查询Redis
        String key = "user:" + userId;
        User user = (User) redis.opsForValue().get(key);
        if (user != null) {
            return user;
        }

        // 3. 查询数据库
        user = userMapper.selectById(userId);
        if (user != null) {
            redis.opsForValue().set(key, user, 3600, TimeUnit.SECONDS);
        }

        return user;
    }
}
```

### 解决方案2：缓存空值

```java
public User getUser(Long userId) {
    String key = "user:" + userId;

    // 1. 查询Redis
    User user = (User) redis.opsForValue().get(key);
    if (user != null) {
        if (user.getId() == null) {  // 空对象标记
            return null;
        }
        return user;
    }

    // 2. 查询数据库
    user = userMapper.selectById(userId);
    if (user != null) {
        redis.opsForValue().set(key, user, 3600, TimeUnit.SECONDS);
    } else {
        // 缓存空对象，防止穿透
        User emptyUser = new User();
        redis.opsForValue().set(key, emptyUser, 60, TimeUnit.SECONDS);  // 短期缓存
    }

    return user;
}
```

## 缓存击穿（Cache Breakdown）

**定义**：热点key过期瞬间，大量请求同时打到数据库

**场景**：热门商品、热点新闻的缓存过期

```
时间点T0：热点key过期
时间点T1：1000个请求同时到达
      → Redis全部未命中
      → 1000个请求全部查询数据库
      → 数据库压力激增
```

### 解决方案1：互斥锁

```java
public Product getProduct(Long productId) {
    String key = "product:" + productId;

    // 1. 查询缓存
    Product product = (Product) redis.opsForValue().get(key);
    if (product != null) {
        return product;
    }

    // 2. 缓存未命中，获取锁
    String lockKey = "lock:product:" + productId;
    String requestId = UUID.randomUUID().toString();

    try {
        // 尝试获取锁（SETNX）
        Boolean locked = redis.opsForValue()
            .setIfAbsent(lockKey, requestId, 10, TimeUnit.SECONDS);

        if (Boolean.TRUE.equals(locked)) {
            // 获取锁成功，查询数据库
            product = productMapper.selectById(productId);

            if (product != null) {
                redis.opsForValue().set(key, product, 3600, TimeUnit.SECONDS);
            }

            return product;
        } else {
            // 获取锁失败，等待后重试
            Thread.sleep(50);
            return getProduct(productId);  // 递归重试
        }
    } catch (InterruptedException e) {
        Thread.currentThread().interrupt();
        return null;
    } finally {
        // 释放锁（Lua脚本保证原子性）
        String script =
            "if redis.call('GET', KEYS[1]) == ARGV[1] then " +
            "  return redis.call('DEL', KEYS[1]) " +
            "else " +
            "  return 0 " +
            "end";
        redis.execute(
            RedisScript.of(script, Long.class),
            Collections.singletonList(lockKey),
            requestId
        );
    }
}
```

### 解决方案2：热点数据永不过期

```java
public void setHotData(String key, Object value) {
    // 方式1：不设置过期时间
    redis.opsForValue().set(key, value);

    // 方式2：逻辑过期（推荐）
    CacheData cacheData = new CacheData();
    cacheData.setData(value);
    cacheData.setExpireTime(System.currentTimeMillis() + 3600000);  // 逻辑过期时间
    redis.opsForValue().set(key, cacheData);
}

public Object getHotData(String key) {
    CacheData cacheData = (CacheData) redis.opsForValue().get(key);
    if (cacheData == null) {
        return null;
    }

    // 检查逻辑过期
    if (cacheData.getExpireTime() < System.currentTimeMillis()) {
        // 已过期，异步刷新
        CompletableFuture.runAsync(() -> refreshCache(key));
    }

    return cacheData.getData();  // 返回旧数据（避免击穿）
}
```

### 解决方案3：提前刷新

```java
@Scheduled(fixedRate = 60000)  // 每分钟
public void refreshHotKeys() {
    // 热点key列表
    List<String> hotKeys = Arrays.asList("product:1001", "product:1002");

    for (String key : hotKeys) {
        Long ttl = redis.getExpire(key, TimeUnit.SECONDS);

        // 剩余时间<5分钟，提前刷新
        if (ttl != null && ttl < 300) {
            Object data = queryFromDB(key);
            redis.opsForValue().set(key, data, 3600, TimeUnit.SECONDS);
            log.info("提前刷新热点key: {}", key);
        }
    }
}
```

## 缓存雪崩（Cache Avalanche）

**定义**：大量key同时过期，所有请求打到数据库

**场景**：批量导入数据时设置相同的过期时间

```
时间点T0：1000个key同时过期
时间点T1：大量请求到达
      → Redis全部未命中
      → 数据库压力激增，可能宕机
```

### 解决方案1：过期时间随机化

```java
public void setCache(String key, Object value, int baseSeconds) {
    // 基础时间 + 随机时间（0-300秒）
    int randomSeconds = ThreadLocalRandom.current().nextInt(300);
    int expire = baseSeconds + randomSeconds;

    redis.opsForValue().set(key, value, expire, TimeUnit.SECONDS);
}

// 示例
public void batchSetCache(List<Product> products) {
    for (Product product : products) {
        String key = "product:" + product.getId();
        setCache(key, product, 3600);  // 3600 ± 300秒
    }
}
```

### 解决方案2：多级缓存

```java
@Service
public class MultiLevelCacheService {
    @Autowired
    private RedisTemplate<String, Object> redis;

    // 本地缓存（Caffeine）
    private Cache<String, Object> localCache = Caffeine.newBuilder()
        .maximumSize(10000)
        .expireAfterWrite(5, TimeUnit.MINUTES)
        .build();

    public Object get(String key) {
        // 1. 本地缓存
        Object value = localCache.getIfPresent(key);
        if (value != null) {
            return value;
        }

        // 2. Redis缓存
        value = redis.opsForValue().get(key);
        if (value != null) {
            localCache.put(key, value);
            return value;
        }

        // 3. 数据库
        value = queryFromDB(key);
        if (value != null) {
            redis.opsForValue().set(key, value, 3600, TimeUnit.SECONDS);
            localCache.put(key, value);
        }

        return value;
    }
}
```

### 解决方案3：限流降级

```java
@Service
public class ProductService {
    @Autowired
    private SlidingWindowRateLimiter rateLimiter;

    public Product getProduct(Long productId) {
        // 限流：每秒最多1000个请求
        if (!rateLimiter.isAllowed("product:query", 1000, 1)) {
            // 降级：返回默认数据或提示
            return getDefaultProduct();
        }

        // 正常查询逻辑
        return queryProduct(productId);
    }

    private Product getDefaultProduct() {
        Product product = new Product();
        product.setName("商品加载中...");
        return product;
    }
}
```

### 解决方案4：Redis高可用

```
1. 主从+哨兵：
   - 主节点宕机，自动切换
   - 保证Redis服务可用

2. Cluster集群：
   - 数据分片，分散压力
   - 单节点故障不影响整体

3. 持久化：
   - RDB + AOF
   - 快速恢复数据
```

## 三大问题对比

| 问题 | 原因 | 影响 | 解决方案 |
|------|------|------|---------|
| **穿透** | 查询不存在的key | DB压力大 | 布隆过滤器、缓存空值 |
| **击穿** | 热点key过期 | DB瞬时压力大 | 互斥锁、永不过期 |
| **雪崩** | 大量key同时过期 | DB持续压力大 | 过期随机化、多级缓存 |

## 综合防护方案

```java
@Service
public class CacheProtectionService {
    @Autowired
    private RedisTemplate<String, Object> redis;
    @Autowired
    private RBloomFilter<String> bloomFilter;
    @Autowired
    private SlidingWindowRateLimiter rateLimiter;

    public Object safeGet(String key, Supplier<Object> dbQuery) {
        // 1. 限流（防雪崩）
        if (!rateLimiter.isAllowed("cache:query", 10000, 1)) {
            throw new BusinessException("系统繁忙，请稍后再试");
        }

        // 2. 布隆过滤器（防穿透）
        if (!bloomFilter.contains(key)) {
            return null;
        }

        // 3. 查询缓存
        Object value = redis.opsForValue().get(key);
        if (value != null) {
            if (value instanceof NullValue) {  // 空值缓存（防穿透）
                return null;
            }
            return value;
        }

        // 4. 互斥锁（防击穿）
        String lockKey = "lock:" + key;
        String requestId = UUID.randomUUID().toString();

        try {
            if (redis.opsForValue().setIfAbsent(lockKey, requestId, 10, TimeUnit.SECONDS)) {
                // 获取锁成功，查询数据库
                value = dbQuery.get();

                if (value != null) {
                    // 随机过期时间（防雪崩）
                    int expire = 3600 + ThreadLocalRandom.current().nextInt(300);
                    redis.opsForValue().set(key, value, expire, TimeUnit.SECONDS);
                } else {
                    // 缓存空值（防穿透）
                    redis.opsForValue().set(key, new NullValue(), 60, TimeUnit.SECONDS);
                }

                return value;
            } else {
                // 获取锁失败，等待后重试
                Thread.sleep(50);
                return safeGet(key, dbQuery);
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return null;
        } finally {
            releaseLock(lockKey, requestId);
        }
    }

    private void releaseLock(String key, String requestId) {
        // Lua脚本释放锁
        String script =
            "if redis.call('GET', KEYS[1]) == ARGV[1] then " +
            "  return redis.call('DEL', KEYS[1]) " +
            "else " +
            "  return 0 " +
            "end";
        redis.execute(
            RedisScript.of(script, Long.class),
            Collections.singletonList(key),
            requestId
        );
    }
}
```

## 总结

**穿透防护**：
- 布隆过滤器（推荐）
- 缓存空值

**击穿防护**：
- 互斥锁（推荐）
- 热点数据永不过期
- 提前刷新

**雪崩防护**：
- 过期时间随机化（必须）
- 多级缓存
- 限流降级
- Redis高可用

**综合方案**：
- 布隆过滤器 + 互斥锁 + 随机过期 + 限流
- 多级缓存 + Redis集群
- 监控告警 + 自动降级
