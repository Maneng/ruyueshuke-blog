---
title: "键空间管理：过期策略与淘汰机制"
date: 2025-01-21T13:30:00+08:00
draft: false
tags: ["Redis", "过期策略", "内存淘汰", "TTL"]
categories: ["技术"]
description: "深入理解Redis的过期删除策略和内存淘汰机制。掌握8种淘汰策略的选择，避免内存溢出，保证系统稳定运行。"
weight: 8
stage: 1
stageTitle: "基础入门篇"
---

## 引言

前面我们学习了Redis的5大数据类型，知道如何存储数据。但有一个关键问题：

**Redis的内存是有限的，数据会一直增长，内存满了怎么办？**

这就涉及到两个核心机制：
1. **过期策略**：如何删除过期的键？
2. **淘汰策略**：内存不足时，删除哪些键？

理解这两个机制，是使用Redis的必修课。

## 一、为什么需要过期机制？

### 1.1 内存是有限的

假设你有一台8GB内存的Redis服务器：
- 缓存用户Session：每个100KB，1万在线用户 = 1GB
- 缓存商品详情：每个50KB，10万商品 = 5GB
- 缓存热点数据：2GB

**总需求**：1GB + 5GB + 2GB = 8GB（刚刚好）

但是：
- Session如果不过期，用户越来越多，内存会爆
- 过期商品不删除，占用空间
- 临时缓存不清理，内存泄漏

**结论**：必须有过期机制自动清理。

### 1.2 过期时间的设置

**EXPIRE命令族**：

```bash
# EXPIRE：设置秒级过期时间
127.0.0.1:6379> SET session:abc123 "user:1001"
OK
127.0.0.1:6379> EXPIRE session:abc123 3600
(integer) 1  # 1小时后过期

# EXPIREAT：设置到某个时间戳过期
127.0.0.1:6379> EXPIREAT session:abc123 1735689600
(integer) 1

# PEXPIRE：设置毫秒级过期时间
127.0.0.1:6379> PEXPIRE cache:hot 5000
(integer) 1  # 5秒后过期

# PEXPIREAT：毫秒级时间戳
127.0.0.1:6379> PEXPIREAT cache:hot 1735689600000
(integer) 1

# SET命令直接设置过期时间（推荐）
127.0.0.1:6379> SET cache:data "value" EX 60
OK

127.0.0.1:6379> SETEX cache:data 60 "value"
OK
```

**查看过期时间**：

```bash
# TTL：查看剩余秒数
127.0.0.1:6379> TTL session:abc123
(integer) 3456  # 还剩3456秒

# 返回值说明：
# > 0：剩余秒数
# -1：没有设置过期时间（永久）
# -2：键不存在或已过期

# PTTL：查看剩余毫秒数
127.0.0.1:6379> PTTL cache:hot
(integer) 4523  # 还剩4523毫秒
```

**取消过期时间**：

```bash
127.0.0.1:6379> PERSIST session:abc123
(integer) 1  # 成功取消

127.0.0.1:6379> TTL session:abc123
(integer) -1  # 变成永久
```

## 二、过期删除策略

### 2.1 三种删除策略

Redis使用**惰性删除 + 定期删除**的混合策略。

**1. 定时删除（不采用）**

```
原理：给每个键设置定时器，到期立即删除

优点：内存友好，到期立即释放
缺点：CPU不友好，大量定时器消耗CPU

Redis不采用这种策略！
```

**2. 惰性删除（被动）**

```
原理：不主动删除，等访问时才检查是否过期

优点：CPU友好，不需要额外开销
缺点：内存不友好，过期键可能长期占用内存

Redis采用！
```

**实现**：

```c
// 伪代码
def get(key):
    if key存在:
        if key已过期:
            删除key
            return null
        else:
            return value
    else:
        return null
```

**示例**：

```bash
127.0.0.1:6379> SET cache:data "value" EX 10
OK

# 10秒后，键还在内存中
127.0.0.1:6379> EXISTS cache:data
(integer) 1  # 还存在（惰性删除还没触发）

# 访问时才删除
127.0.0.1:6379> GET cache:data
(nil)  # 访问时发现过期，删除并返回nil

127.0.0.1:6379> EXISTS cache:data
(integer) 0  # 已删除
```

**3. 定期删除（主动）**

```
原理：每隔一段时间，随机抽查一批键，删除过期的

优点：平衡CPU和内存
缺点：难以确定删除频率和数量

Redis采用！
```

**实现（简化版）**：

```c
// 伪代码
def activeExpireCycle():
    for i in range(数据库数量):
        for j in range(20):  // 随机抽取20个键
            key = 随机获取一个设置了过期时间的键
            if key已过期:
                删除key
```

**Redis的定期删除策略**：
- 默认每秒执行10次（100ms一次）
- 每次随机抽取20个键检查
- 如果过期键超过25%，继续抽取
- 单次执行时间不超过25ms

### 2.2 过期删除的影响

**内存占用**：

```bash
# 设置100万个键，1秒过期
127.0.0.1:6379> DEBUG POPULATE 1000000 key 10
OK

# 1秒后，内存不会立即释放
127.0.0.1:6379> INFO memory
used_memory_human:256.00M  # 内存还在

# 访问或等待定期删除后，才会释放
```

**对性能的影响**：

```bash
# 定期删除在后台执行，对性能影响小
# 但如果过期键太多，会影响性能

# 查看过期键删除的统计
127.0.0.1:6379> INFO stats
expired_keys:12345  # 已删除的过期键数量
```

## 三、内存淘汰策略

### 3.1 为什么需要淘汰？

即使有过期删除，内存还是可能不够：
- 有些键没有设置过期时间
- 定期删除的速度赶不上写入速度
- 过期时间设置太长

**当内存达到上限时**，Redis会触发**内存淘汰策略**。

### 3.2 配置最大内存

```bash
# redis.conf配置
maxmemory 2gb

# 或者动态设置
127.0.0.1:6379> CONFIG SET maxmemory 2gb
OK

# 查看配置
127.0.0.1:6379> CONFIG GET maxmemory
1) "maxmemory"
2) "2147483648"
```

### 3.3 八种淘汰策略

**1. noeviction（默认，不推荐生产环境）**

```
策略：不淘汰任何键，内存满时拒绝写入

行为：
- 写入命令返回错误
- 读取命令正常执行

适用场景：
- 缓存不允许丢失
- 需要人工介入

缺点：
- 服务不可用
- 需要手动清理
```

```bash
127.0.0.1:6379> CONFIG SET maxmemory-policy noeviction
OK

# 内存满时
127.0.0.1:6379> SET newkey "value"
(error) OOM command not allowed when used memory > 'maxmemory'
```

**2. allkeys-lru（推荐，最常用）**

```
策略：从所有键中，淘汰最近最少使用（LRU）的键

行为：
- 访问过的键，标记时间戳
- 淘汰最久未访问的键

适用场景：
- 通用缓存场景
- 访问有热点分布

优点：
- 保留热点数据
- 淘汰冷数据
```

```bash
127.0.0.1:6379> CONFIG SET maxmemory-policy allkeys-lru
OK
```

**3. volatile-lru**

```
策略：从设置了过期时间的键中，淘汰LRU的键

行为：
- 只淘汰有过期时间的键
- 没有过期时间的键不受影响

适用场景：
- 缓存和持久数据混用
- 只想淘汰缓存，不想淘汰持久数据

注意：
- 如果没有键设置过期时间，行为同noeviction
```

**4. allkeys-random**

```
策略：从所有键中，随机淘汰

行为：
- 完全随机选择
- 不考虑访问频率

适用场景：
- 访问均匀，无热点
- 对淘汰无特殊要求

缺点：
- 可能淘汰热点数据
```

**5. volatile-random**

```
策略：从设置了过期时间的键中，随机淘汰

行为：
- 只随机淘汰有过期时间的键

适用场景：
- 同volatile-lru，但无热点分布
```

**6. volatile-ttl**

```
策略：从设置了过期时间的键中，淘汰TTL最小的键

行为：
- 优先淘汰即将过期的键

适用场景：
- 希望淘汰快过期的键
- 保留还有较长时间的缓存

优点：
- 提前清理即将过期的数据
```

**7. allkeys-lfu（Redis 4.0+，推荐）**

```
策略：从所有键中，淘汰访问频率最低的键

行为：
- 记录键的访问频率
- 淘汰最不常用的键

适用场景：
- 访问频率分布明显
- 比LRU更精准

优点：
- 比LRU更智能
- 能识别突发访问和长期冷数据
```

**8. volatile-lfu（Redis 4.0+）**

```
策略：从设置了过期时间的键中，淘汰LFU的键

行为：
- 只淘汰有过期时间的键
- 按访问频率排序

适用场景：
- 同volatile-lru，但更精准
```

### 3.4 LRU vs LFU

**LRU（Least Recently Used）**：最近最少使用

```
访问历史：A B C D A E

LRU链表：E → A → D → C → B
         ↑最近    ↑最久

淘汰B（最久未访问）

缺点：
- 偶尔访问一次的数据会"续命"
- 不能识别访问频率
```

**LFU（Least Frequently Used）**：最不常用

```
访问次数：
A: 100次
B: 2次
C: 50次
D: 1次

淘汰D（访问次数最少）

优点：
- 能识别长期冷数据
- 突发访问不会影响排序
```

**选择建议**：
- 一般场景：**allkeys-lru**
- 有明显冷热分布：**allkeys-lfu**
- 缓存+持久数据：**volatile-lru** 或 **volatile-lfu**

### 3.5 策略对比表

| 策略 | 范围 | 算法 | 适用场景 |
|------|------|------|---------|
| **noeviction** | - | 不淘汰 | 不允许丢失数据 |
| **allkeys-lru** | 所有键 | LRU | 通用缓存（推荐） |
| **allkeys-lfu** | 所有键 | LFU | 有明显热点 |
| **allkeys-random** | 所有键 | 随机 | 均匀访问 |
| **volatile-lru** | 有过期时间 | LRU | 缓存+持久数据 |
| **volatile-lfu** | 有过期时间 | LFU | 缓存+持久数据 |
| **volatile-random** | 有过期时间 | 随机 | 均匀访问 |
| **volatile-ttl** | 有过期时间 | TTL最小 | 提前清理 |

## 四、实战配置

### 4.1 推荐配置

**通用缓存场景**：

```conf
# redis.conf

# 最大内存：物理内存的70%
maxmemory 2gb

# 淘汰策略：LRU（最常用）
maxmemory-policy allkeys-lru

# LRU采样数量（越大越精确，但越慢）
maxmemory-samples 5
```

**缓存+持久数据场景**：

```conf
maxmemory 2gb
maxmemory-policy volatile-lru

# 确保缓存数据设置了过期时间
```

**高频访问场景（Redis 4.0+）**：

```conf
maxmemory 2gb
maxmemory-policy allkeys-lfu
maxmemory-samples 5

# LFU配置
lfu-log-factor 10       # 频率递增速度
lfu-decay-time 1        # 频率递减速度（分钟）
```

### 4.2 Java代码示例

**设置过期时间**：

```java
@Service
public class CacheService {

    @Autowired
    private RedisTemplate<String, Object> redis;

    // 设置缓存（带过期时间）
    public void setCache(String key, Object value, long timeout, TimeUnit unit) {
        redis.opsForValue().set(key, value, timeout, unit);
    }

    // 设置缓存（1小时过期）
    public void setCacheWithHourExpire(String key, Object value) {
        redis.opsForValue().set(key, value, 1, TimeUnit.HOURS);
    }

    // 获取缓存，自动续期
    public Object getCacheWithRefresh(String key, long timeout, TimeUnit unit) {
        Object value = redis.opsForValue().get(key);

        if (value != null) {
            // 访问时刷新过期时间
            redis.expire(key, timeout, unit);
        }

        return value;
    }

    // 查看剩余过期时间
    public Long getExpireTime(String key) {
        return redis.getExpire(key, TimeUnit.SECONDS);
    }

    // 设置永久
    public void persist(String key) {
        redis.persist(key);
    }
}
```

**过期时间抖动（防止缓存雪崩）**：

```java
// ❌ 不推荐：固定过期时间
redis.opsForValue().set(key, value, 3600, TimeUnit.SECONDS);

// ✅ 推荐：添加随机抖动
public void setCacheWithJitter(String key, Object value, long baseTimeout) {
    // 添加±10%的随机抖动
    long jitter = (long) (baseTimeout * 0.1 * Math.random());
    long timeout = baseTimeout + jitter - (long) (baseTimeout * 0.05);

    redis.opsForValue().set(key, value, timeout, TimeUnit.SECONDS);
}
```

### 4.3 监控和告警

**关键指标**：

```bash
# 查看内存使用
127.0.0.1:6379> INFO memory
used_memory_human:1.5G
maxmemory_human:2.0G
maxmemory_policy:allkeys-lru
mem_fragmentation_ratio:1.23

# 查看过期键统计
127.0.0.1:6379> INFO stats
expired_keys:123456          # 已删除过期键数量
evicted_keys:567             # 已淘汰键数量（内存不足）
keyspace_hits:1000000        # 命中次数
keyspace_misses:100000       # 未命中次数

# 命中率 = hits / (hits + misses)
命中率 = 1000000 / 1100000 = 90.9%
```

**告警阈值**：

```java
@Component
public class RedisMonitor {

    @Scheduled(fixedRate = 60000)  // 每分钟检查
    public void checkMemoryUsage() {
        Properties info = redis.getRequiredConnectionFactory()
                               .getConnection()
                               .info("memory");

        long usedMemory = Long.parseLong(info.getProperty("used_memory"));
        long maxMemory = Long.parseLong(info.getProperty("maxmemory"));

        double usage = (double) usedMemory / maxMemory;

        // 告警：内存使用超过80%
        if (usage > 0.8) {
            log.error("Redis内存使用率过高: {}%", usage * 100);
            // 发送告警
            alertService.sendAlert("Redis内存告警", usage);
        }
    }

    @Scheduled(fixedRate = 300000)  // 每5分钟检查
    public void checkHitRate() {
        Properties info = redis.getRequiredConnectionFactory()
                               .getConnection()
                               .info("stats");

        long hits = Long.parseLong(info.getProperty("keyspace_hits"));
        long misses = Long.parseLong(info.getProperty("keyspace_misses"));

        double hitRate = (double) hits / (hits + misses);

        // 告警：命中率低于70%
        if (hitRate < 0.7) {
            log.warn("Redis命中率过低: {}%", hitRate * 100);
        }
    }
}
```

## 五、常见问题

### Q1: 设置过期时间后，会立即删除吗？

**不会**。Redis使用惰性删除+定期删除：
- 访问时才检查（惰性）
- 后台定期随机抽查（定期）

```bash
127.0.0.1:6379> SET key "value" EX 10
OK

# 10秒后，键可能还在内存中
127.0.0.1:6379> DEBUG OBJECT key
Value at:0x7f8b8c0a1234  # 还在内存中

# 访问时才删除
127.0.0.1:6379> GET key
(nil)
```

### Q2: volatile-*策略，如果没有键设置过期时间会怎样？

**行为同noeviction**，拒绝写入：

```bash
127.0.0.1:6379> CONFIG SET maxmemory-policy volatile-lru
OK

# 所有键都没有过期时间
127.0.0.1:6379> SET key1 "value"
OK
127.0.0.1:6379> SET key2 "value"
OK

# 内存满时，拒绝写入
127.0.0.1:6379> SET key3 "value"
(error) OOM command not allowed
```

### Q3: DEL命令会触发过期删除吗？

**不会**。DEL是立即删除：

```bash
127.0.0.1:6379> SET key "value" EX 3600
OK

127.0.0.1:6379> DEL key
(integer) 1  # 立即删除，不等过期
```

### Q4: RENAME会保留过期时间吗？

**会**：

```bash
127.0.0.1:6379> SET oldkey "value" EX 3600
OK

127.0.0.1:6379> TTL oldkey
(integer) 3590

127.0.0.1:6379> RENAME oldkey newkey
OK

127.0.0.1:6379> TTL newkey
(integer) 3585  # 过期时间保留
```

## 六、总结

### 核心要点

1. **过期删除策略**：惰性删除（访问时） + 定期删除（后台抽查）
2. **内存淘汰策略**：8种策略，推荐allkeys-lru或allkeys-lfu
3. **noeviction**：不淘汰，内存满时拒绝写入（不推荐生产环境）
4. **allkeys-lru**：从所有键淘汰，最常用
5. **volatile-lru**：只淘汰有过期时间的键，适合混合场景
6. **监控指标**：内存使用率、命中率、淘汰键数量

### 过期删除流程图

```
键过期
  ↓
惰性删除（被动）
  ├─ 访问时检查
  └─ 发现过期→删除

定期删除（主动）
  ├─ 每100ms执行
  ├─ 随机抽查20个键
  ├─ 过期率>25%→继续抽查
  └─ 单次≤25ms
```

### 淘汰策略选择指南

```
是否允许数据丢失？
├─ 否 → noeviction
└─ 是
    ↓
缓存+持久数据混用？
├─ 是 → volatile-lru / volatile-lfu
└─ 否 → allkeys-lru / allkeys-lfu
    ↓
有明显热点？
├─ 是 → allkeys-lfu
└─ 否 → allkeys-lru
```

### 下一步

理解了过期和淘汰机制后，下一篇我们将学习**RDB持久化**：
- RDB快照原理
- fork机制详解
- 数据备份与恢复

---

**思考题**：
1. 为什么Redis不使用定时删除？
2. 如果内存使用率一直很高，应该如何优化？
3. 什么场景下选择volatile-ttl策略？

下一篇见！
