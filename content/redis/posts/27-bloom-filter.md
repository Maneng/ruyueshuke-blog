---
title: "布隆过滤器：缓存穿透的终极解决方案"
date: 2025-01-21T22:40:00+08:00
draft: false
tags: ["Redis", "布隆过滤器", "Bloom Filter", "缓存穿透"]
categories: ["技术"]
description: "掌握Redis布隆过滤器原理和实战应用，解决缓存穿透问题，实现高效去重判断，误判率可控"
weight: 27
stage: 3
stageTitle: "进阶特性篇"
---

## 什么是布隆过滤器？

**核心功能**：快速判断元素是否存在

**特点**：
- ✅ 空间效率极高（百万数据仅需1MB）
- ✅ 查询速度快（O(k)，k为hash函数个数）
- ❌ 存在误判（可能把不存在判断为存在）
- ❌ 无法删除元素

**判断逻辑**：
```
if (bloomFilter.contains(key)) {
    // 可能存在（需要进一步查询确认）
} else {
    // 一定不存在（可以直接返回）
}
```

## 原理

**数据结构**：位数组 + 多个hash函数

```
1. 添加元素"apple"
   hash1("apple") = 3 → bit[3] = 1
   hash2("apple") = 7 → bit[7] = 1
   hash3("apple") = 10 → bit[10] = 1

2. 判断元素是否存在
   if (bit[3] == 1 && bit[7] == 1 && bit[10] == 1) {
       return "可能存在";
   } else {
       return "一定不存在";
   }
```

**误判原因**：多个元素的hash值可能碰撞
```
hash1("apple") = 3, hash2("apple") = 7, hash3("apple") = 10
hash1("banana") = 3, hash2("banana") = 11, hash3("banana") = 15
hash1("cherry") = 7, hash2("cherry") = 10, hash3("cherry") = 20

查询"unknown"：hash1=3, hash2=7, hash3=10
→ 都是1 → 误判为存在（实际是apple的hash值）
```

## 使用Redisson实现

### 1. 添加依赖

```xml
<dependency>
    <groupId>org.redisson</groupId>
    <artifactId>redisson-spring-boot-starter</artifactId>
    <version>3.20.0</version>
</dependency>
```

### 2. 配置Redisson

```java
@Configuration
public class RedissonConfig {
    @Bean
    public RedissonClient redissonClient() {
        Config config = new Config();
        config.useSingleServer()
            .setAddress("redis://127.0.0.1:6379")
            .setPassword("yourpassword");
        return Redisson.create(config);
    }
}
```

### 3. 基础使用

```java
@Service
public class BloomFilterService {
    @Autowired
    private RedissonClient redisson;

    public void init() {
        RBloomFilter<String> bloomFilter = redisson.getBloomFilter("user:ids");

        // 初始化：预期元素100万，误判率0.01（1%）
        bloomFilter.tryInit(1000000L, 0.01);

        // 添加元素
        bloomFilter.add("user:1001");
        bloomFilter.add("user:1002");
    }

    public boolean mightExist(String userId) {
        RBloomFilter<String> bloomFilter = redisson.getBloomFilter("user:ids");
        return bloomFilter.contains(userId);
    }
}
```

## 实战案例

### 案例1：防止缓存穿透

```java
@Service
public class UserService {
    @Autowired
    private RedissonClient redisson;
    @Autowired
    private RedisTemplate<String, Object> redis;
    @Autowired
    private UserMapper userMapper;

    private RBloomFilter<Long> userBloomFilter;

    @PostConstruct
    public void init() {
        userBloomFilter = redisson.getBloomFilter("user:bloom");
        userBloomFilter.tryInit(10000000L, 0.01);  // 1000万用户，1%误判率

        // 初始化：加载所有userId到布隆过滤器
        List<Long> userIds = userMapper.selectAllUserIds();
        userIds.forEach(userBloomFilter::add);
        log.info("布隆过滤器初始化完成，用户数: {}", userIds.size());
    }

    public User getUser(Long userId) {
        // 1. 布隆过滤器判断
        if (!userBloomFilter.contains(userId)) {
            log.info("用户不存在: {}", userId);
            return null;  // 一定不存在，直接返回
        }

        // 2. 查询Redis缓存
        String key = "user:" + userId;
        User user = (User) redis.opsForValue().get(key);
        if (user != null) {
            return user;
        }

        // 3. 查询数据库
        user = userMapper.selectById(userId);
        if (user != null) {
            redis.opsForValue().set(key, user, 3600, TimeUnit.SECONDS);
        } else {
            // 设置空值缓存（防止误判导致的穿透）
            redis.opsForValue().set(key, new User(), 60, TimeUnit.SECONDS);
        }

        return user;
    }

    // 新增用户时，同步到布隆过滤器
    public void createUser(User user) {
        userMapper.insert(user);
        userBloomFilter.add(user.getId());
    }
}
```

### 案例2：爬虫去重

```java
@Service
public class CrawlerService {
    @Autowired
    private RedissonClient redisson;

    private RBloomFilter<String> urlBloomFilter;

    @PostConstruct
    public void init() {
        urlBloomFilter = redisson.getBloomFilter("crawler:urls");
        urlBloomFilter.tryInit(100000000L, 0.001);  // 1亿URL，0.1%误判率
    }

    public boolean shouldCrawl(String url) {
        if (urlBloomFilter.contains(url)) {
            log.debug("URL已爬取: {}", url);
            return false;  // 可能已爬取
        }

        // 标记为已爬取
        urlBloomFilter.add(url);
        return true;
    }

    public void crawl(String url) {
        if (!shouldCrawl(url)) {
            return;
        }

        // 爬取逻辑
        log.info("开始爬取: {}", url);
        // ... 爬取网页内容
    }
}
```

### 案例3：邮件去重

```java
@Service
public class EmailService {
    @Autowired
    private RedissonClient redisson;

    public boolean sendEmail(String email, String content) {
        // 每日邮件去重
        String bloomKey = "email:sent:" + LocalDate.now();
        RBloomFilter<String> bloomFilter = redisson.getBloomFilter(bloomKey);

        if (!bloomFilter.isExists()) {
            bloomFilter.tryInit(1000000L, 0.01);
            bloomFilter.expire(2, TimeUnit.DAYS);
        }

        // 生成邮件指纹（email + content hash）
        String fingerprint = email + ":" + content.hashCode();

        if (bloomFilter.contains(fingerprint)) {
            log.warn("重复邮件，跳过发送: {}", email);
            return false;
        }

        // 发送邮件
        doSendEmail(email, content);

        // 记录已发送
        bloomFilter.add(fingerprint);
        return true;
    }

    private void doSendEmail(String email, String content) {
        // 实际发送逻辑
    }
}
```

### 案例4：推荐系统去重

```java
@Service
public class RecommendService {
    @Autowired
    private RedissonClient redisson;

    public List<Article> getRecommendations(Long userId) {
        String bloomKey = "recommend:history:" + userId;
        RBloomFilter<Long> historyBloom = redisson.getBloomFilter(bloomKey);

        if (!historyBloom.isExists()) {
            historyBloom.tryInit(10000L, 0.01);
            historyBloom.expire(30, TimeUnit.DAYS);
        }

        // 获取推荐列表
        List<Article> candidates = fetchCandidates(userId);

        // 过滤已推荐过的文章
        List<Article> result = candidates.stream()
            .filter(article -> !historyBloom.contains(article.getId()))
            .limit(20)
            .collect(Collectors.toList());

        // 记录已推荐
        result.forEach(article -> historyBloom.add(article.getId()));

        return result;
    }

    private List<Article> fetchCandidates(Long userId) {
        // 获取推荐候选
        return new ArrayList<>();
    }
}
```

## 误判率与内存

**公式**：
```
位数组大小(m) = -n * ln(p) / (ln(2)^2)
hash函数个数(k) = m / n * ln(2)

n: 预期元素数量
p: 误判率
```

**示例计算**：
```
n=100万, p=0.01（1%）
m = -1000000 * ln(0.01) / (ln(2)^2) ≈ 9585058 bits ≈ 1.14 MB
k = 9585058 / 1000000 * ln(2) ≈ 7 个hash函数
```

**对照表**：

| 元素数量 | 误判率 | 内存占用 | hash函数 |
|---------|--------|---------|---------|
| 100万 | 0.01 (1%) | 1.14 MB | 7 |
| 100万 | 0.001 (0.1%) | 1.71 MB | 10 |
| 1000万 | 0.01 (1%) | 11.4 MB | 7 |
| 1亿 | 0.01 (1%) | 114 MB | 7 |

## 最佳实践

### 1. 合理设置容量和误判率

```java
// 根据业务需求设置
// 用户数据：误判率可以高一点（0.01-0.05），节省内存
// 爬虫去重：误判率要低一点（0.001-0.01），避免重复爬取
bloomFilter.tryInit(expectedSize, 0.01);
```

### 2. 定期重建

```java
@Scheduled(cron = "0 0 2 * * ?")  // 每天凌晨2点
public void rebuildBloomFilter() {
    RBloomFilter<Long> oldFilter = redisson.getBloomFilter("user:bloom");
    RBloomFilter<Long> newFilter = redisson.getBloomFilter("user:bloom:new");

    // 初始化新过滤器
    newFilter.tryInit(10000000L, 0.01);

    // 加载所有userId
    List<Long> userIds = userMapper.selectAllUserIds();
    userIds.forEach(newFilter::add);

    // 原子替换
    oldFilter.delete();
    newFilter.rename("user:bloom");

    log.info("布隆过滤器重建完成");
}
```

### 3. 监控误判率

```java
@Component
public class BloomFilterMonitor {
    @Autowired
    private RedissonClient redisson;

    @Scheduled(fixedRate = 60000)  // 每分钟
    public void monitor() {
        RBloomFilter<Long> bloomFilter = redisson.getBloomFilter("user:bloom");

        long expectedInsertions = bloomFilter.getExpectedInsertions();
        long size = bloomFilter.count();
        double falseProbability = bloomFilter.getFalseProbability();

        log.info("布隆过滤器状态: 预期={}, 实际={}, 误判率={}",
            expectedInsertions, size, falseProbability);

        // 告警：实际大小超过预期
        if (size > expectedInsertions * 1.1) {
            log.warn("布隆过滤器容量不足，建议扩容");
        }
    }
}
```

### 4. 降级方案

```java
public User getUser(Long userId) {
    try {
        // 优先使用布隆过滤器
        if (!userBloomFilter.contains(userId)) {
            return null;
        }
    } catch (Exception e) {
        log.error("布隆过滤器查询失败，降级为直接查询", e);
        // 降级：跳过布隆过滤器
    }

    // 继续查询Redis和数据库
    return queryFromCacheOrDB(userId);
}
```

## 布隆过滤器 vs 其他方案

| 方案 | 内存 | 查询速度 | 精确性 | 删除 |
|------|------|---------|--------|------|
| **布隆过滤器** | 极低 | 极快 | 有误判 | ❌ |
| **Set** | 高 | 快 | 精确 | ✅ |
| **数据库** | 中 | 慢 | 精确 | ✅ |

**选择建议**：
- 数据量大（百万级）→ 布隆过滤器
- 需要精确判断 → Set或数据库
- 需要删除元素 → Set或数据库

## 总结

**核心价值**：
- 极低内存（100万数据1MB）
- 极快查询（O(k)）
- 防止缓存穿透

**典型场景**：
- 缓存穿透防护
- 爬虫URL去重
- 邮件/推送去重
- 推荐系统去重

**注意事项**：
- 存在误判（需要二次确认）
- 无法删除（考虑定期重建）
- 容量规划（预估好数据量）
- 降级方案（布隆过滤器不可用时）
