---
title: "热Key与BigKey：发现、分析与解决方案"
date: 2025-01-21T23:30:00+08:00
draft: false
tags: ["Redis", "热Key", "BigKey", "性能优化"]
categories: ["技术"]
description: "掌握热Key和BigKey的识别方法、性能影响和解决方案，优化Redis性能，避免生产事故"
weight: 32
stage: 4
stageTitle: "生产实践篇"
---

## 热Key问题

**定义**：访问频率极高的key，导致单个Redis节点负载过高

**危害**：
- 单节点CPU 100%
- 网络带宽打满
- 影响其他key访问
- Cluster集群数据倾斜

### 发现热Key

#### 方法1：redis-cli --hotkeys

```bash
redis-cli --hotkeys
# 统计访问频率最高的key
```

#### 方法2：monitor命令

```bash
redis-cli monitor | head -n 100000 | awk '{print $4}' | sort | uniq -c | sort -rn | head -n 10
```

#### 方法3：代码统计

```java
@Aspect
@Component
public class RedisMonitorAspect {
    private ConcurrentHashMap<String, AtomicLong> accessCounter = new ConcurrentHashMap<>();

    @Around("execution(* org.springframework.data.redis.core.RedisTemplate.opsFor*(..))")
    public Object around(ProceedingJoinPoint pjp) throws Throwable {
        Object result = pjp.proceed();

        // 统计key访问次数
        if (result != null) {
            String key = extractKey(pjp);
            if (key != null) {
                accessCounter.computeIfAbsent(key, k -> new AtomicLong()).incrementAndGet();
            }
        }

        return result;
    }

    @Scheduled(fixedRate = 60000)  // 每分钟
    public void reportHotKeys() {
        List<Map.Entry<String, AtomicLong>> hotKeys = accessCounter.entrySet().stream()
            .sorted(Map.Entry.<String, AtomicLong>comparingByValue().reversed())
            .limit(10)
            .collect(Collectors.toList());

        log.info("热Key TOP 10: {}", hotKeys);

        // 清空统计
        accessCounter.clear();
    }
}
```

### 解决方案

#### 方案1：本地缓存

```java
@Service
public class ProductService {
    @Autowired
    private RedisTemplate<String, Object> redis;

    // 本地缓存热点数据
    private Cache<String, Product> localCache = Caffeine.newBuilder()
        .maximumSize(1000)
        .expireAfterWrite(5, TimeUnit.MINUTES)
        .build();

    public Product getProduct(Long productId) {
        String key = "product:" + productId;

        // 1. 本地缓存
        Product product = localCache.getIfPresent(key);
        if (product != null) {
            return product;
        }

        // 2. Redis
        product = (Product) redis.opsForValue().get(key);
        if (product != null) {
            localCache.put(key, product);
            return product;
        }

        // 3. DB
        product = productMapper.selectById(productId);
        if (product != null) {
            redis.opsForValue().set(key, product, 3600, TimeUnit.SECONDS);
            localCache.put(key, product);
        }

        return product;
    }
}
```

#### 方案2：热Key备份

```java
// 热Key复制多份，随机访问
public Object getHotKey(String key) {
    // 随机选择一个备份
    int index = ThreadLocalRandom.current().nextInt(10);
    String backupKey = key + ":backup:" + index;

    Object value = redis.opsForValue().get(backupKey);
    if (value != null) {
        return value;
    }

    // 备份不存在，查询原key
    value = redis.opsForValue().get(key);
    if (value != null) {
        // 更新备份
        redis.opsForValue().set(backupKey, value, 3600, TimeUnit.SECONDS);
    }

    return value;
}
```

#### 方案3：读写分离

```java
// 读从节点，写主节点
@Configuration
public class RedisConfig {
    @Bean
    public LettuceConnectionFactory writeConnectionFactory() {
        return new LettuceConnectionFactory(new RedisStandaloneConfiguration("master", 6379));
    }

    @Bean
    public LettuceConnectionFactory readConnectionFactory() {
        return new LettuceConnectionFactory(new RedisStandaloneConfiguration("slave", 6379));
    }
}
```

## BigKey问题

**定义**：占用内存过大的key
- String > 10KB
- List/Set/ZSet > 1万元素
- Hash > 1万字段

**危害**：
- 内存占用高
- 网络阻塞（大value传输）
- 删除慢（DEL命令阻塞）
- 主从同步慢

### 发现BigKey

#### 方法1：redis-cli --bigkeys

```bash
redis-cli --bigkeys

# 输出示例
[00.00%] Biggest string found so far 'user:1001' with 15360 bytes
[00.00%] Biggest list   found so far 'list:tasks' with 50000 items
[00.00%] Biggest hash   found so far 'hash:user:info' with 10000 fields
```

#### 方法2：MEMORY USAGE命令

```bash
MEMORY USAGE key

# 示例
redis> MEMORY USAGE mykey
(integer) 50000  # 字节
```

#### 方法3：扫描统计

```java
@Service
public class BigKeyScanner {
    @Autowired
    private RedisTemplate<String, String> redis;

    public List<BigKeyInfo> scan() {
        List<BigKeyInfo> bigKeys = new ArrayList<>();
        ScanOptions options = ScanOptions.scanOptions().count(100).build();

        redis.execute((RedisCallback<Object>) connection -> {
            Cursor<byte[]> cursor = connection.scan(options);

            while (cursor.hasNext()) {
                String key = new String(cursor.next());
                long size = getKeySize(key);

                if (size > 10240) {  // > 10KB
                    BigKeyInfo info = new BigKeyInfo();
                    info.setKey(key);
                    info.setSize(size);
                    bigKeys.add(info);
                }
            }

            return null;
        });

        return bigKeys.stream()
            .sorted(Comparator.comparingLong(BigKeyInfo::getSize).reversed())
            .limit(100)
            .collect(Collectors.toList());
    }

    private long getKeySize(String key) {
        return redis.execute((RedisCallback<Long>) connection ->
            connection.memoryUsage(key.getBytes())
        );
    }
}
```

### 解决方案

#### 方案1：拆分BigKey

```java
// ❌ 不好：单个大Hash
HSET user:1001 field1 value1 field2 value2 ... field10000 value10000

// ✅ 好：拆分为多个小Hash
@Service
public class UserService {
    private static final int SHARD_COUNT = 10;

    public void setUserField(Long userId, String field, String value) {
        int shard = Math.abs(field.hashCode()) % SHARD_COUNT;
        String key = "user:" + userId + ":shard:" + shard;
        redis.opsForHash().put(key, field, value);
    }

    public String getUserField(Long userId, String field) {
        int shard = Math.abs(field.hashCode()) % SHARD_COUNT;
        String key = "user:" + userId + ":shard:" + shard;
        return (String) redis.opsForHash().get(key, field);
    }
}
```

#### 方案2：压缩value

```java
@Service
public class CompressService {
    public void setCompressed(String key, Object value) throws IOException {
        // 序列化
        byte[] data = SerializationUtils.serialize(value);

        // Gzip压缩
        ByteArrayOutputStream bos = new ByteArrayOutputStream();
        try (GZIPOutputStream gzip = new GZIPOutputStream(bos)) {
            gzip.write(data);
        }

        byte[] compressed = bos.toByteArray();
        redis.opsForValue().set(key.getBytes(), compressed);

        log.info("压缩率: {}%", (1 - compressed.length * 1.0 / data.length) * 100);
    }

    public Object getCompressed(String key) throws IOException {
        byte[] compressed = redis.opsForValue().get(key.getBytes());
        if (compressed == null) {
            return null;
        }

        // Gzip解压
        ByteArrayInputStream bis = new ByteArrayInputStream(compressed);
        ByteArrayOutputStream bos = new ByteArrayOutputStream();
        try (GZIPInputStream gzip = new GZIPInputStream(bis)) {
            byte[] buffer = new byte[1024];
            int len;
            while ((len = gzip.read(buffer)) > 0) {
                bos.write(buffer, 0, len);
            }
        }

        return SerializationUtils.deserialize(bos.toByteArray());
    }
}
```

#### 方案3：异步删除BigKey

```bash
# Redis 4.0+
UNLINK key  # 异步删除，不阻塞

# 或配置lazyfree
lazyfree-lazy-eviction yes
lazyfree-lazy-expire yes
lazyfree-lazy-server-del yes
```

```java
// Java代码
public void deleteBigKey(String key) {
    redis.unlink(key);  // 异步删除
}
```

#### 方案4：渐进式删除

```java
// 对于大List/Set/ZSet，分批删除
public void deleteBigList(String key) {
    long size = redis.opsForList().size(key);
    long batchSize = 100;

    while (size > 0) {
        // 每次删除100个元素
        redis.opsForList().trim(key, 0, size - batchSize - 1);
        size = redis.opsForList().size(key);
        Thread.sleep(10);  // 避免阻塞
    }

    // 最后删除key
    redis.delete(key);
}
```

## 监控与告警

```java
@Component
public class RedisHealthMonitor {
    @Autowired
    private RedisTemplate<String, String> redis;

    @Scheduled(fixedRate = 60000)  // 每分钟
    public void monitor() {
        // 1. 内存使用
        Properties info = redis.execute((RedisCallback<Properties>) connection ->
            connection.info("memory")
        );

        long usedMemory = Long.parseLong(info.getProperty("used_memory"));
        long maxMemory = Long.parseLong(info.getProperty("maxmemory"));

        if (usedMemory > maxMemory * 0.9) {
            log.warn("Redis内存使用超过90%: {}MB / {}MB",
                usedMemory / 1024 / 1024, maxMemory / 1024 / 1024);
            // 发送告警
        }

        // 2. BigKey告警
        List<BigKeyInfo> bigKeys = scanBigKeys();
        if (!bigKeys.isEmpty()) {
            log.warn("发现BigKey: {}", bigKeys);
            // 发送告警
        }

        // 3. 慢查询
        List<Object> slowlogs = redis.execute((RedisCallback<List<Object>>) connection ->
            connection.slowlogGet(10)
        );

        if (slowlogs != null && !slowlogs.isEmpty()) {
            log.warn("慢查询: {}", slowlogs);
        }
    }

    private List<BigKeyInfo> scanBigKeys() {
        // 实现BigKey扫描
        return new ArrayList<>();
    }
}
```

## 最佳实践

### 避免产生BigKey

1. **设计合理的数据结构**：
```java
// ❌ 不好
HSET user:info field1 value1 ... field10000 value10000

// ✅ 好：按类型拆分
HSET user:1001:basic name "Alice" age "25"
HSET user:1001:address city "Beijing" street "..."
```

2. **限制集合大小**：
```java
public void addToList(String key, String value) {
    redis.opsForList().rightPush(key, value);

    // 限制List大小
    Long size = redis.opsForList().size(key);
    if (size > 1000) {
        redis.opsForList().trim(key, -1000, -1);  // 只保留最后1000个
    }
}
```

3. **定期清理过期数据**：
```java
@Scheduled(cron = "0 0 2 * * ?")  // 每天凌晨2点
public void cleanExpiredData() {
    // 清理超过30天的数据
    long threshold = System.currentTimeMillis() - 30L * 24 * 3600 * 1000;
    redis.opsForZSet().removeRangeByScore("timeline", 0, threshold);
}
```

## 总结

**热Key**：
- 发现：monitor、--hotkeys、代码统计
- 解决：本地缓存、热Key备份、读写分离

**BigKey**：
- 发现：--bigkeys、MEMORY USAGE、扫描
- 解决：拆分、压缩、异步删除

**预防**：
- 合理设计数据结构
- 限制集合大小
- 定期清理数据
- 监控告警
