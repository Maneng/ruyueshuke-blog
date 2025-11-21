---
title: "慢查询优化：发现与解决性能瓶颈"
date: 2025-01-21T23:40:00+08:00
draft: false
tags: ["Redis", "慢查询", "性能优化"]
categories: ["技术"]
description: "掌握Redis慢查询日志分析，识别慢命令，优化查询性能，提升系统响应速度"
weight: 33
stage: 4
stageTitle: "生产实践篇"
---

## 慢查询配置

```bash
# 慢查询阈值（微秒），默认10000（10ms）
CONFIG SET slowlog-log-slower-than 10000

# 慢查询日志最大长度
CONFIG SET slowlog-max-len 128

# 持久化配置
# redis.conf
slowlog-log-slower-than 10000
slowlog-max-len 128
```

## 查看慢查询

```bash
# 获取所有慢查询
SLOWLOG GET [count]

# 获取慢查询数量
SLOWLOG LEN

# 清空慢查询
SLOWLOG RESET
```

**输出示例**：
```
redis> SLOWLOG GET 5
1) 1) (integer) 6      # 日志ID
   2) (integer) 1609459200  # 时间戳
   3) (integer) 12000   # 执行时间（微秒）
   4) 1) "KEYS"        # 命令
      2) "*"
   5) "127.0.0.1:50796"  # 客户端
   6) ""               # 客户端名称
```

## Java监控慢查询

```java
@Component
public class SlowQueryMonitor {
    @Autowired
    private RedisTemplate<String, String> redis;

    @Scheduled(fixedRate = 60000)  // 每分钟
    public void checkSlowQueries() {
        List<Object> slowlogs = redis.execute((RedisCallback<List<Object>>) connection ->
            connection.slowlogGet(100)
        );

        if (slowlogs != null && !slowlogs.isEmpty()) {
            for (Object log : slowlogs) {
                // 解析慢查询日志
                Map<String, Object> slowlog = parseSlowlog(log);

                long duration = (long) slowlog.get("duration");
                String command = (String) slowlog.get("command");

                // 告警阈值：超过50ms
                if (duration > 50000) {
                    log.warn("慢查询告警: command={}, duration={}ms",
                        command, duration / 1000);
                    // 发送告警
                    sendAlert(command, duration);
                }
            }

            // 清空已分析的慢查询
            redis.execute((RedisCallback<Void>) connection -> {
                connection.slowlogReset();
                return null;
            });
        }
    }

    private Map<String, Object> parseSlowlog(Object log) {
        // 解析慢查询日志格式
        return new HashMap<>();
    }

    private void sendAlert(String command, long duration) {
        // 发送告警（邮件/短信/钉钉）
    }
}
```

## 常见慢命令

### 1. KEYS命令

```bash
# ❌ 极慢：遍历所有key，O(N)
KEYS *
KEYS user:*

# ✅ 好：使用SCAN，渐进式遍历
SCAN 0 MATCH user:* COUNT 100
```

**Java替代方案**：
```java
public Set<String> scanKeys(String pattern) {
    Set<String> keys = new HashSet<>();
    ScanOptions options = ScanOptions.scanOptions()
        .match(pattern)
        .count(100)
        .build();

    redis.execute((RedisCallback<Object>) connection -> {
        Cursor<byte[]> cursor = connection.scan(options);
        while (cursor.hasNext()) {
            keys.add(new String(cursor.next()));
        }
        return null;
    });

    return keys;
}
```

### 2. FLUSHALL/FLUSHDB

```bash
# ❌ 慢：清空所有数据，阻塞
FLUSHALL

# ✅ 好：异步删除（Redis 4.0+）
FLUSHALL ASYNC
FLUSHDB ASYNC
```

### 3. SORT命令

```bash
# ❌ 慢：排序大量数据，O(N*log(N))
SORT mylist DESC LIMIT 0 10

# ✅ 好：使用ZSet代替List+SORT
ZADD ranking 100 "user1" 95 "user2"
ZREVRANGE ranking 0 9  # O(log(N)+M)
```

### 4. SMEMBERS/HGETALL

```bash
# ❌ 慢：返回所有元素，O(N)
SMEMBERS myset
HGETALL myhash

# ✅ 好：使用SSCAN/HSCAN
SSCAN myset 0 COUNT 100
HSCAN myhash 0 COUNT 100
```

### 5. SUNION/SINTER/SDIFF

```bash
# ❌ 慢：大集合运算，O(N)
SUNION set1 set2 set3

# ✅ 好：限制集合大小或异步计算
# 方案1：限制集合大小
SCARD set1  # 检查大小
# 方案2：使用Lua脚本分批计算
```

## 优化方案

### 1. 避免O(N)命令

```java
// ❌ 不好
public List<String> getAllKeys() {
    return redis.keys("*");  // O(N)
}

// ✅ 好
public Set<String> scanAllKeys() {
    Set<String> keys = new HashSet<>();
    ScanOptions options = ScanOptions.scanOptions().count(100).build();

    redis.execute((RedisCallback<Object>) connection -> {
        Cursor<byte[]> cursor = connection.scan(options);
        while (cursor.hasNext()) {
            keys.add(new String(cursor.next()));
        }
        return null;
    });

    return keys;
}
```

### 2. 使用Pipeline批量操作

```java
// ❌ 不好：逐个查询，N次网络往返
public List<User> getUsers(List<Long> ids) {
    List<User> users = new ArrayList<>();
    for (Long id : ids) {
        User user = (User) redis.opsForValue().get("user:" + id);
        users.add(user);
    }
    return users;
}

// ✅ 好：Pipeline批量查询
public List<User> getUsersBatch(List<Long> ids) {
    List<String> keys = ids.stream()
        .map(id -> "user:" + id)
        .collect(Collectors.toList());

    List<Object> results = redis.executePipelined((RedisCallback<Object>) connection -> {
        for (String key : keys) {
            connection.get(key.getBytes());
        }
        return null;
    });

    return results.stream()
        .map(obj -> (User) obj)
        .collect(Collectors.toList());
}
```

### 3. 限制返回数量

```java
// ❌ 不好：返回全部
public Set<String> getAllMembers(String key) {
    return redis.opsForSet().members(key);  // 可能返回百万数据
}

// ✅ 好：分页返回
public Set<String> scanMembers(String key, int limit) {
    Set<String> result = new HashSet<>();
    ScanOptions options = ScanOptions.scanOptions().count(limit).build();

    redis.execute((RedisCallback<Object>) connection -> {
        Cursor<byte[]> cursor = connection.sScan(key.getBytes(), options);
        while (cursor.hasNext() && result.size() < limit) {
            result.add(new String(cursor.next()));
        }
        return null;
    });

    return result;
}
```

### 4. 使用合适的数据结构

```java
// ❌ 不好：List + SORT
redis.opsForList().rightPush("scores", "user1:100");
redis.opsForList().rightPush("scores", "user2:95");
// 查询TOP 10需要SORT命令，O(N*log(N))

// ✅ 好：使用ZSet
redis.opsForZSet().add("ranking", "user1", 100);
redis.opsForZSet().add("ranking", "user2", 95);
// 查询TOP 10，O(log(N)+M)
Set<Object> top10 = redis.opsForZSet().reverseRange("ranking", 0, 9);
```

## 命令复杂度速查

| 命令 | 复杂度 | 说明 |
|------|--------|------|
| **GET/SET/DEL** | O(1) | ✅ 快速 |
| **INCR/DECR** | O(1) | ✅ 快速 |
| **LPUSH/RPUSH/LPOP/RPOP** | O(1) | ✅ 快速 |
| **SADD/SREM/SISMEMBER** | O(1) | ✅ 快速 |
| **ZADD/ZREM/ZSCORE** | O(log(N)) | ✅ 较快 |
| **KEYS** | O(N) | ❌ 慢，禁用 |
| **SMEMBERS/HGETALL** | O(N) | ❌ 慢，用SCAN |
| **SORT** | O(N*log(N)) | ❌ 慢，用ZSet |
| **SUNION/SINTER** | O(N) | ❌ 慢，限制大小 |

## 监控指标

```java
@Component
public class RedisPerformanceMonitor {
    @Autowired
    private RedisTemplate<String, String> redis;

    @Scheduled(fixedRate = 60000)
    public void monitor() {
        Properties info = redis.execute((RedisCallback<Properties>) connection ->
            connection.info("stats")
        );

        // 1. QPS
        long totalCommands = Long.parseLong(info.getProperty("total_commands_processed"));
        long instantOps = Long.parseLong(info.getProperty("instantaneous_ops_per_sec"));
        log.info("Redis QPS: {}", instantOps);

        // 2. 慢查询数量
        Long slowlogLen = redis.execute((RedisCallback<Long>) connection ->
            connection.slowlogLen()
        );
        log.info("慢查询数量: {}", slowlogLen);

        if (slowlogLen > 100) {
            log.warn("慢查询过多，需要优化");
        }

        // 3. 延迟
        long start = System.currentTimeMillis();
        redis.opsForValue().get("health_check");
        long latency = System.currentTimeMillis() - start;
        log.info("Redis延迟: {}ms", latency);

        if (latency > 100) {
            log.warn("Redis延迟过高");
        }
    }
}
```

## 性能调优建议

1. **禁用危险命令**：
```conf
# redis.conf
rename-command FLUSHDB ""
rename-command FLUSHALL ""
rename-command KEYS ""
```

2. **开启慢查询日志**：
```conf
slowlog-log-slower-than 10000  # 10ms
slowlog-max-len 128
```

3. **使用Pipeline**：
```java
// 批量操作合并为一次网络往返
```

4. **合理设置超时**：
```java
RedisStandaloneConfiguration config = new RedisStandaloneConfiguration();
LettuceClientConfiguration clientConfig = LettuceClientConfiguration.builder()
    .commandTimeout(Duration.ofSeconds(5))  // 命令超时5秒
    .build();
```

5. **监控与告警**：
```java
// 定期检查慢查询
// 超过阈值发送告警
```

## 总结

**慢查询根源**：
- O(N)命令（KEYS、SMEMBERS）
- 大value操作
- 不合适的数据结构

**优化方法**：
- 用SCAN代替KEYS
- 用Pipeline批量操作
- 限制返回数量
- 使用合适的数据结构

**监控告警**：
- 定期检查慢查询日志
- 监控QPS、延迟
- 超过阈值告警
- 优化高频慢命令
