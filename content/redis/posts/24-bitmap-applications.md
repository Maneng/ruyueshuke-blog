---
title: "Bitmap位图：节省内存的统计利器"
date: 2025-01-21T22:10:00+08:00
draft: false
tags: ["Redis", "Bitmap", "位图", "统计"]
categories: ["技术"]
description: "掌握Redis Bitmap的原理和应用，实现用户签到、在线统计、布尔标记等场景，1亿用户仅需12MB内存"
weight: 24
stage: 3
stageTitle: "进阶特性篇"
---

## Bitmap原理

**本质**：一串二进制位（0和1）
```
位图：[0][1][1][0][1][0][0][1]
索引：  0  1  2  3  4  5  6  7

1亿个位 = 1亿 bits = 12.5 MB
```

**优势**：
- 极致节省内存（1个用户1bit）
- 快速统计（位运算）

## 核心命令

```bash
# 设置位
SETBIT key offset value

# 获取位
GETBIT key offset

# 统计1的个数
BITCOUNT key [start end]

# 位运算
BITOP AND|OR|XOR|NOT destkey key [key ...]

# 查找第一个0或1
BITPOS key bit [start] [end]
```

## 实战案例

### 案例1：用户签到

```java
@Service
public class SignInService {
    @Autowired
    private RedisTemplate<String, Object> redis;

    // 签到
    public void signIn(Long userId, LocalDate date) {
        String key = "sign:" + userId + ":" + date.format(DateTimeFormatter.ofPattern("yyyyMM"));
        int offset = date.getDayOfMonth() - 1;
        redis.opsForValue().setBit(key, offset, true);
    }

    // 检查是否签到
    public boolean isSignedIn(Long userId, LocalDate date) {
        String key = "sign:" + userId + ":" + date.format(DateTimeFormatter.ofPattern("yyyyMM"));
        int offset = date.getDayOfMonth() - 1;
        return Boolean.TRUE.equals(redis.opsForValue().getBit(key, offset));
    }

    // 统计本月签到天数
    public Long countSignIn(Long userId, String month) {
        String key = "sign:" + userId + ":" + month;
        return redis.execute((RedisCallback<Long>) connection ->
            connection.bitCount(key.getBytes())
        );
    }

    // 连续签到天数
    public int getContinuousSignInDays(Long userId) {
        LocalDate today = LocalDate.now();
        String key = "sign:" + userId + ":" + today.format(DateTimeFormatter.ofPattern("yyyyMM"));

        int days = 0;
        for (int i = today.getDayOfMonth() - 1; i >= 0; i--) {
            Boolean signed = redis.opsForValue().getBit(key, i);
            if (Boolean.TRUE.equals(signed)) {
                days++;
            } else {
                break;
            }
        }
        return days;
    }
}
```

### 案例2：用户在线状态

```java
@Service
public class OnlineStatusService {
    @Autowired
    private RedisTemplate<String, Object> redis;

    // 设置用户在线
    public void setOnline(Long userId) {
        String key = "online:" + LocalDate.now();
        redis.opsForValue().setBit(key, userId, true);
        redis.expire(key, 2, TimeUnit.DAYS);
    }

    // 设置用户离线
    public void setOffline(Long userId) {
        String key = "online:" + LocalDate.now();
        redis.opsForValue().setBit(key, userId, false);
    }

    // 检查用户是否在线
    public boolean isOnline(Long userId) {
        String key = "online:" + LocalDate.now();
        return Boolean.TRUE.equals(redis.opsForValue().getBit(key, userId));
    }

    // 统计今日在线人数
    public Long countOnlineUsers() {
        String key = "online:" + LocalDate.now();
        return redis.execute((RedisCallback<Long>) connection ->
            connection.bitCount(key.getBytes())
        );
    }
}
```

### 案例3：用户标签系统

```java
@Service
public class UserTagService {
    @Autowired
    private RedisTemplate<String, Object> redis;

    // 标签定义
    private static final int TAG_VIP = 0;
    private static final int TAG_ACTIVE = 1;
    private static final int TAG_VERIFIED = 2;

    // 添加标签
    public void addTag(Long userId, int tagId) {
        String key = "user:tags:" + userId;
        redis.opsForValue().setBit(key, tagId, true);
    }

    // 移除标签
    public void removeTag(Long userId, int tagId) {
        String key = "user:tags:" + userId;
        redis.opsForValue().setBit(key, tagId, false);
    }

    // 检查标签
    public boolean hasTag(Long userId, int tagId) {
        String key = "user:tags:" + userId;
        return Boolean.TRUE.equals(redis.opsForValue().getBit(key, tagId));
    }

    // 查找VIP且活跃的用户
    public Set<Long> findVIPActiveUsers(Set<Long> userIds) {
        Set<Long> result = new HashSet<>();
        for (Long userId : userIds) {
            if (hasTag(userId, TAG_VIP) && hasTag(userId, TAG_ACTIVE)) {
                result.add(userId);
            }
        }
        return result;
    }
}
```

### 案例4：布隆过滤器（简化版）

```java
@Service
public class SimpleBloomFilter {
    @Autowired
    private RedisTemplate<String, Object> redis;

    private static final String KEY = "bloom_filter";
    private static final int BIT_SIZE = 10000000;  // 1000万位

    // 添加元素
    public void add(String element) {
        int hash1 = Math.abs(element.hashCode()) % BIT_SIZE;
        int hash2 = Math.abs((element + "salt").hashCode()) % BIT_SIZE;
        int hash3 = Math.abs((element + "salt2").hashCode()) % BIT_SIZE;

        redis.opsForValue().setBit(KEY, hash1, true);
        redis.opsForValue().setBit(KEY, hash2, true);
        redis.opsForValue().setBit(KEY, hash3, true);
    }

    // 检查元素是否存在
    public boolean mightExist(String element) {
        int hash1 = Math.abs(element.hashCode()) % BIT_SIZE;
        int hash2 = Math.abs((element + "salt").hashCode()) % BIT_SIZE;
        int hash3 = Math.abs((element + "salt2").hashCode()) % BIT_SIZE;

        return Boolean.TRUE.equals(redis.opsForValue().getBit(KEY, hash1))
            && Boolean.TRUE.equals(redis.opsForValue().getBit(KEY, hash2))
            && Boolean.TRUE.equals(redis.opsForValue().getBit(KEY, hash3));
    }
}
```

## 位运算操作

### 多日期统计

```bash
# 连续3天都签到的用户
BITOP AND result sign:202501 sign:202502 sign:202503
BITCOUNT result

# 3天内至少签到1次的用户
BITOP OR result sign:202501 sign:202502 sign:202503
BITCOUNT result
```

**Java实现**：
```java
// 连续N天都签到的用户数
public Long countContinuousSignIn(int days) {
    String[] keys = new String[days];
    LocalDate date = LocalDate.now();
    for (int i = 0; i < days; i++) {
        keys[i] = "sign:" + date.minusDays(i).format(DateTimeFormatter.ofPattern("yyyyMMdd"));
    }

    String resultKey = "sign:continuous:" + days;
    redis.opsForValue().bitOp(RedisStringCommands.BitOperation.AND, resultKey, keys);
    Long count = redis.execute((RedisCallback<Long>) connection ->
        connection.bitCount(resultKey.getBytes())
    );
    redis.delete(resultKey);
    return count;
}
```

## 内存占用分析

```
场景：1亿用户签到统计（31天）

方案1：Set存储
SET sign:20250101 {user1, user2, ...}
内存：1亿用户 * 8字节（Long） * 31天 = 23.2 GB

方案2：Bitmap存储
BITMAP sign:20250101 (1亿位)
内存：1亿位 / 8 = 12.5 MB * 31天 = 387.5 MB

节省：98.3%内存
```

## 最佳实践

### 1. 合理设置过期时间

```java
// 签到数据保留90天
String key = "sign:" + userId + ":" + month;
redis.opsForValue().setBit(key, offset, true);
redis.expire(key, 90, TimeUnit.DAYS);
```

### 2. 分片存储大Bitmap

```java
// 1亿用户，分100片，每片100万
public void setBit(Long userId, boolean value) {
    int shard = (int) (userId / 1000000);
    int offset = (int) (userId % 1000000);
    String key = "bitmap:shard:" + shard;
    redis.opsForValue().setBit(key, offset, value);
}
```

### 3. 预分配内存

```java
// 避免第一次SETBIT时大量内存分配
public void initBitmap(String key, long size) {
    // 设置最后一位，Redis会预分配内存
    redis.opsForValue().setBit(key, size - 1, false);
}
```

### 4. 批量操作优化

```java
// 使用Pipeline批量SETBIT
redis.executePipelined((RedisCallback<Object>) connection -> {
    for (int i = 0; i < 1000; i++) {
        connection.setBit(key.getBytes(), i, true);
    }
    return null;
});
```

## 注意事项

1. **offset限制**：最大2^32-1（512MB）
2. **内存开销**：稀疏bitmap浪费内存
3. **性能**：BITCOUNT在大bitmap上较慢
4. **原子性**：单个SETBIT是原子的，批量操作不是

## 总结

**核心价值**：
- 极致节省内存（1亿用户12.5MB）
- 快速统计（位运算）
- 适合布尔型数据

**典型场景**：
- 用户签到统计
- 在线状态管理
- 用户标签系统
- 去重统计

**适用条件**：
- 数据是布尔型（0/1）
- 数据稠密（大部分位都有值）
- 需要大量统计操作
