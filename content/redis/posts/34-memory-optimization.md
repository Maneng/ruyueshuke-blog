---
title: "内存优化实战：降低Redis内存占用"
date: 2025-01-21T23:50:00+08:00
draft: false
tags: ["Redis", "内存优化", "性能优化"]
categories: ["技术"]
description: "掌握Redis内存优化技巧，通过数据结构优化、编码选择、过期策略等手段，降低50%以上内存占用"
weight: 34
stage: 4
stageTitle: "生产实践篇"
---

## 内存分析

### 查看内存使用

```bash
# 内存统计
INFO memory

# 关键指标
used_memory: 1073741824  # 已使用内存（字节）
used_memory_human: 1.00G
used_memory_peak: 2147483648
maxmemory: 4294967296    # 最大内存限制

# 内存碎片率
mem_fragmentation_ratio: 1.20  # >1.5需要优化

# 查看key占用内存
MEMORY USAGE key
```

### Java内存分析

```java
@Component
public class MemoryAnalyzer {
    @Autowired
    private RedisTemplate<String, String> redis;

    public void analyze() {
        Properties info = redis.execute((RedisCallback<Properties>) connection ->
            connection.info("memory")
        );

        long usedMemory = Long.parseLong(info.getProperty("used_memory"));
        long maxMemory = Long.parseLong(info.getProperty("maxmemory"));
        double fragRatio = Double.parseDouble(info.getProperty("mem_fragmentation_ratio"));

        log.info("内存使用: {}MB / {}MB ({}%)",
            usedMemory / 1024 / 1024,
            maxMemory / 1024 / 1024,
            usedMemory * 100 / maxMemory);

        log.info("碎片率: {}", fragRatio);

        if (usedMemory > maxMemory * 0.9) {
            log.warn("内存使用超过90%，需要优化");
        }

        if (fragRatio > 1.5) {
            log.warn("内存碎片率过高，考虑重启Redis");
        }
    }

    // 分析TOP 100大key
    public List<KeyMemory> analyzeTopKeys() {
        List<KeyMemory> result = new ArrayList<>();
        ScanOptions options = ScanOptions.scanOptions().count(100).build();

        redis.execute((RedisCallback<Object>) connection -> {
            Cursor<byte[]> cursor = connection.scan(options);

            while (cursor.hasNext()) {
                String key = new String(cursor.next());
                Long size = connection.memoryUsage(key.getBytes());

                if (size != null && size > 10240) {  // > 10KB
                    KeyMemory km = new KeyMemory();
                    km.setKey(key);
                    km.setSize(size);
                    result.add(km);
                }
            }
            return null;
        });

        return result.stream()
            .sorted(Comparator.comparingLong(KeyMemory::getSize).reversed())
            .limit(100)
            .collect(Collectors.toList());
    }
}
```

## 优化策略

### 1. 选择合适的数据类型

```java
// ❌ 不好：String存储对象（JSON）
redis.opsForValue().set("user:1001",
    "{\"name\":\"Alice\",\"age\":25,\"city\":\"Beijing\"}");
// 占用：~100字节

// ✅ 好：Hash存储（小对象）
redis.opsForHash().put("user:1001", "name", "Alice");
redis.opsForHash().put("user:1001", "age", "25");
redis.opsForHash().put("user:1001", "city", "Beijing");
// 占用：~50字节，节省50%
```

### 2. 利用紧凑编码

```java
// Hash：保持ziplist编码
// 条件：字段数<512，值长度<64字节

public void setUserInfo(Long userId, Map<String, String> info) {
    String key = "user:" + userId;

    // 确保字段值简短
    Map<String, String> compactInfo = info.entrySet().stream()
        .filter(e -> e.getValue().length() < 64)  // 值<64字节
        .collect(Collectors.toMap(Map.Entry::getKey, Map.Entry::getValue));

    redis.opsForHash().putAll(key, compactInfo);

    // 验证编码
    String encoding = redis.execute((RedisCallback<String>) connection ->
        new String(connection.execute("OBJECT", "ENCODING".getBytes(), key.getBytes()))
    );
    log.info("编码: {}", encoding);  // 期望：ziplist或listpack
}

// 配置优化
// redis.conf
hash-max-ziplist-entries 512
hash-max-ziplist-value 64
```

### 3. 整数优化

```java
// ❌ 不好：字符串存储整数
redis.opsForValue().set("count", "12345");  // embstr编码，~20字节

// ✅ 好：整数存储
redis.opsForValue().set("count", 12345);  // int编码，8字节

// ✅ 更好：共享整数对象（0-9999）
redis.opsForValue().set("status", 1);  // 共享对象，0字节（不计redisObject）
```

### 4. 压缩value

```java
@Service
public class CompressedCacheService {
    @Autowired
    private RedisTemplate<String, byte[]> redis;

    // 存储大value时压缩
    public void setLarge(String key, String value) throws IOException {
        byte[] data = value.getBytes(StandardCharsets.UTF_8);

        if (data.length > 1024) {  // >1KB才压缩
            // Gzip压缩
            ByteArrayOutputStream bos = new ByteArrayOutputStream();
            try (GZIPOutputStream gzip = new GZIPOutputStream(bos)) {
                gzip.write(data);
            }
            byte[] compressed = bos.toByteArray();

            // 添加压缩标记
            byte[] withFlag = new byte[compressed.length + 1];
            withFlag[0] = 1;  // 压缩标记
            System.arraycopy(compressed, 0, withFlag, 1, compressed.length);

            redis.opsForValue().set(key, withFlag);

            log.info("压缩率: {}%", (1 - compressed.length * 1.0 / data.length) * 100);
        } else {
            // 不压缩
            byte[] withFlag = new byte[data.length + 1];
            withFlag[0] = 0;  // 未压缩标记
            System.arraycopy(data, 0, withFlag, 1, data.length);
            redis.opsForValue().set(key, withFlag);
        }
    }

    public String getLarge(String key) throws IOException {
        byte[] data = redis.opsForValue().get(key);
        if (data == null || data.length == 0) {
            return null;
        }

        byte flag = data[0];
        byte[] content = new byte[data.length - 1];
        System.arraycopy(data, 1, content, 0, content.length);

        if (flag == 1) {
            // 解压
            ByteArrayInputStream bis = new ByteArrayInputStream(content);
            ByteArrayOutputStream bos = new ByteArrayOutputStream();
            try (GZIPInputStream gzip = new GZIPInputStream(bis)) {
                byte[] buffer = new byte[1024];
                int len;
                while ((len = gzip.read(buffer)) > 0) {
                    bos.write(buffer, 0, len);
                }
            }
            return new String(bos.toByteArray(), StandardCharsets.UTF_8);
        } else {
            return new String(content, StandardCharsets.UTF_8);
        }
    }
}
```

### 5. 设置合理的过期时间

```java
// ❌ 不好：永不过期
redis.opsForValue().set("cache:data", data);

// ✅ 好：设置过期时间
redis.opsForValue().set("cache:data", data, 3600, TimeUnit.SECONDS);

// ✅ 更好：随机过期时间（防止雪崩）
int expire = 3600 + ThreadLocalRandom.current().nextInt(300);
redis.opsForValue().set("cache:data", data, expire, TimeUnit.SECONDS);
```

### 6. 定期清理过期数据

```java
@Component
public class CacheCleanup {
    @Autowired
    private RedisTemplate<String, String> redis;

    @Scheduled(cron = "0 0 2 * * ?")  // 每天凌晨2点
    public void cleanup() {
        // 清理超过30天的时间线数据
        long threshold = System.currentTimeMillis() - 30L * 24 * 3600 * 1000;

        Long removed = redis.opsForZSet().removeRangeByScore("timeline", 0, threshold);
        log.info("清理过期时间线数据: {} 条", removed);

        // 清理空Hash
        Set<String> hashKeys = redis.keys("user:*");
        if (hashKeys != null) {
            for (String key : hashKeys) {
                Long size = redis.opsForHash().size(key);
                if (size != null && size == 0) {
                    redis.delete(key);
                    log.info("删除空Hash: {}", key);
                }
            }
        }
    }
}
```

### 7. 拆分BigKey

```java
// ❌ 不好：单个大Hash
HSET user:1001 field1 val1 ... field10000 val10000  // 1MB

// ✅ 好：分片存储
@Service
public class ShardedHashService {
    private static final int SHARD_COUNT = 10;

    public void hset(String key, String field, String value) {
        int shard = Math.abs(field.hashCode()) % SHARD_COUNT;
        String shardKey = key + ":shard:" + shard;
        redis.opsForHash().put(shardKey, field, value);
    }

    public String hget(String key, String field) {
        int shard = Math.abs(field.hashCode()) % SHARD_COUNT;
        String shardKey = key + ":shard:" + shard;
        return (String) redis.opsForHash().get(shardKey, field);
    }
}
```

## 内存淘汰策略

```conf
# redis.conf

# 最大内存
maxmemory 4gb

# 淘汰策略
maxmemory-policy allkeys-lru

# 策略说明：
# noeviction: 不淘汰，内存满时写入报错
# allkeys-lru: 所有key，LRU淘汰
# volatile-lru: 有过期时间的key，LRU淘汰
# allkeys-lfu: 所有key，LFU淘汰（访问频率）
# volatile-lfu: 有过期时间的key，LFU淘汰
# allkeys-random: 所有key，随机淘汰
# volatile-random: 有过期时间的key，随机淘汰
# volatile-ttl: 有过期时间的key，TTL小的先淘汰

# LRU采样数量（越大越精确，但消耗CPU）
maxmemory-samples 5
```

## 监控告警

```java
@Component
public class MemoryMonitor {
    @Autowired
    private RedisTemplate<String, String> redis;

    @Scheduled(fixedRate = 300000)  // 每5分钟
    public void monitor() {
        Properties info = redis.execute((RedisCallback<Properties>) connection ->
            connection.info("memory")
        );

        long usedMemory = Long.parseLong(info.getProperty("used_memory"));
        long maxMemory = Long.parseLong(info.getProperty("maxmemory"));
        long evicted = Long.parseLong(info.getProperty("evicted_keys"));

        double usage = usedMemory * 100.0 / maxMemory;

        log.info("内存使用: {}%", String.format("%.2f", usage));

        // 告警：内存使用超过80%
        if (usage > 80) {
            log.warn("Redis内存使用超过80%，需要扩容或优化");
            sendAlert("Redis内存告警", String.format("当前使用%.2f%%", usage));
        }

        // 告警：淘汰key过多
        if (evicted > 1000) {
            log.warn("Redis淘汰key过多: {}", evicted);
            sendAlert("Redis淘汰告警", String.format("已淘汰%d个key", evicted));
        }
    }

    private void sendAlert(String title, String message) {
        // 发送告警
    }
}
```

## 内存优化清单

1. **数据结构**：
   - [ ] 小对象用Hash代替String+JSON
   - [ ] 整数直接存储，不用字符串
   - [ ] 保持紧凑编码（ziplist/intset）

2. **过期策略**：
   - [ ] 设置合理的过期时间
   - [ ] 过期时间随机化
   - [ ] 定期清理过期数据

3. **BigKey处理**：
   - [ ] 拆分大Hash/List/Set/ZSet
   - [ ] 压缩大value
   - [ ] 使用异步删除

4. **配置优化**：
   - [ ] 设置maxmemory
   - [ ] 选择合适的淘汰策略
   - [ ] 调整编码阈值

5. **监控**：
   - [ ] 监控内存使用率
   - [ ] 监控内存碎片率
   - [ ] 监控淘汰key数量
   - [ ] 分析BigKey

## 总结

**核心优化**：
- 选择合适的数据类型（Hash > String+JSON）
- 利用紧凑编码（ziplist/intset）
- 整数直接存储
- 压缩大value

**内存管理**：
- 设置过期时间
- 定期清理
- 拆分BigKey
- 配置淘汰策略

**监控告警**：
- 内存使用率
- 内存碎片率
- 淘汰key数量
- BigKey分析

**优化效果**：
- 合理优化可降低50%+内存占用
- 提升性能，降低成本
