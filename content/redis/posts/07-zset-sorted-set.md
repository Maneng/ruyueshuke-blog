---
title: "ZSet有序集合：排行榜的终极方案"
date: 2025-01-21T13:00:00+08:00
draft: false
tags: ["Redis", "ZSet", "排行榜", "跳表"]
categories: ["技术"]
description: "ZSet是Redis最强大的数据类型，支持按分数排序的有序集合。深入理解跳表原理，实现游戏排行榜、热搜榜、延迟队列等复杂场景。"
weight: 7
stage: 1
stageTitle: "基础入门篇"
---

## 引言

前面我们学习了Set（无序、唯一），今天要学习**有序且唯一**的ZSet（Sorted Set）。

想象一下这些场景：
- 🏆 **游戏排行榜**：按分数从高到低排序，实时更新
- 🔥 **热搜榜**：按热度值排序，展示TOP 10
- ⏰ **延迟队列**：按时间戳排序，到期自动执行
- 💰 **按价格筛选**：查询1000-5000元的商品

这些场景的共同特点是：**需要排序、需要快速查询范围**。ZSet正是为此而生，它是Redis中**最强大、最复杂**的数据类型。

## 一、ZSet的本质

### 1.1 什么是ZSet？

ZSet（Sorted Set）是一个**按分数排序的有序集合**：

```
ZSet: {
  (member1, score1),
  (member2, score2),
  (member3, score3),
  ...
}

特点：
- 有序：按score从小到大排序
- 唯一：member不能重复
- 分数可重复：多个member可以有相同score
- 支持范围查询：按score或按排名查询
```

**示例**：

```bash
# 添加元素（member:score）
127.0.0.1:6379> ZADD leaderboard 100 "张三" 95 "李四" 92 "王五"
(integer) 3

# 按分数从低到高查询
127.0.0.1:6379> ZRANGE leaderboard 0 -1 WITHSCORES
1) "王五"
2) "92"
3) "李四"
4) "95"
5) "张三"
6) "100"

# 按分数从高到低查询
127.0.0.1:6379> ZREVRANGE leaderboard 0 -1 WITHSCORES
1) "张三"
2) "100"
3) "李四"
4) "95"
5) "王五"
6) "92"
```

### 1.2 ZSet vs Set

| 特性 | Set | ZSet |
|------|-----|------|
| **有序性** | 无序 | 有序（按score） |
| **唯一性** | 元素唯一 | 元素唯一 |
| **分数** | 无 | 有 |
| **范围查询** | 不支持 | 支持 |
| **排名查询** | 不支持 | 支持 |
| **时间复杂度** | O(1) | O(log n) |
| **适用场景** | 去重、标签 | 排行榜、范围查询 |

### 1.3 底层实现：跳表（Skiplist）

ZSet底层使用**跳表（Skiplist）+ 哈希表（Hashtable）**实现：

**跳表**：负责按score排序，支持范围查询
**哈希表**：负责按member查询score，O(1)时间复杂度

**跳表原理（简化版）**：

```
假设有序链表：1 → 3 → 5 → 7 → 9

普通链表查找7：需要遍历4个节点 O(n)

跳表：增加"高速公路"
Level 2:  1 ────────→ 7 ────────→ 9
Level 1:  1 ───→ 3 ───→ 7 ───→ 9
Level 0:  1 → 3 → 5 → 7 → 9

查找7：
1. Level 2: 1 → 7 （2步）
2. 找到！

时间复杂度：O(log n)
```

**为什么用跳表而不是红黑树？**
1. 实现简单，代码少
2. 范围查询效率高
3. 内存占用相对较小
4. 并发友好（局部修改）

### 1.4 编码方式

ZSet有两种底层编码：

**1. ziplist（压缩列表）** - 省内存

条件：
- 元素数量 < `zset-max-ziplist-entries`（默认128）
- 所有value长度 < `zset-max-ziplist-value`（默认64字节）

**2. skiplist + hashtable** - 高性能

条件：不满足ziplist条件时

**查看编码**：

```bash
127.0.0.1:6379> ZADD small 1 "a" 2 "b" 3 "c"
(integer) 3

127.0.0.1:6379> OBJECT ENCODING small
"ziplist"

# 添加大量数据后
127.0.0.1:6379> OBJECT ENCODING leaderboard
"skiplist"
```

## 二、ZSet命令全解析

### 2.1 添加和修改

**ZADD - 添加元素**

```bash
# 添加单个元素（score member）
127.0.0.1:6379> ZADD rank 100 "张三"
(integer) 1

# 添加多个元素
127.0.0.1:6379> ZADD rank 95 "李四" 92 "王五" 88 "赵六"
(integer) 3

# 更新已存在元素的score
127.0.0.1:6379> ZADD rank 105 "张三"
(integer) 0  # 0表示更新，1表示新增

# NX：仅当元素不存在时添加
127.0.0.1:6379> ZADD rank NX 90 "张三"
(integer) 0  # 失败，已存在

# XX：仅当元素存在时更新
127.0.0.1:6379> ZADD rank XX 110 "张三"
(integer) 0  # 成功更新

# GT：仅当新score大于当前score时更新
127.0.0.1:6379> ZADD rank GT 120 "张三"
(integer) 0  # 成功

# LT：仅当新score小于当前score时更新
127.0.0.1:6379> ZADD rank LT 115 "张三"
(integer) 0  # 成功
```

**ZINCRBY - 增加分数**

```bash
127.0.0.1:6379> ZINCRBY rank 10 "张三"
"125"  # 返回增加后的分数

127.0.0.1:6379> ZINCRBY rank -5 "张三"
"120"  # 可以减分

# 如果元素不存在，从0开始
127.0.0.1:6379> ZINCRBY rank 50 "新用户"
"50"
```

### 2.2 查询操作

**ZSCORE - 获取元素分数**

```bash
127.0.0.1:6379> ZSCORE rank "张三"
"120"

127.0.0.1:6379> ZSCORE rank "不存在"
(nil)
```

**ZCARD - 获取元素个数**

```bash
127.0.0.1:6379> ZCARD rank
(integer) 5
```

**ZCOUNT - 统计分数区间内的元素**

```bash
# 统计分数在90-100之间的元素个数
127.0.0.1:6379> ZCOUNT rank 90 100
(integer) 3

# 开区间：(90表示>90，(100表示<100
127.0.0.1:6379> ZCOUNT rank (90 (100
(integer) 2
```

**ZRANK/ZREVRANK - 获取排名**

```bash
# 正序排名（分数从低到高，排名从0开始）
127.0.0.1:6379> ZRANK rank "张三"
(integer) 4  # 排名第5（最高分）

# 逆序排名（分数从高到低）
127.0.0.1:6379> ZREVRANK rank "张三"
(integer) 0  # 排名第1（最高分）
```

### 2.3 范围查询（重要！）

**ZRANGE - 按排名范围查询（正序）**

```bash
# 查询排名0-2的元素（前3名）
127.0.0.1:6379> ZRANGE rank 0 2
1) "赵六"
2) "王五"
3) "李四"

# 带分数
127.0.0.1:6379> ZRANGE rank 0 2 WITHSCORES
1) "赵六"
2) "88"
3) "王五"
4) "92"
5) "李四"
6) "95"

# 查询全部
127.0.0.1:6379> ZRANGE rank 0 -1
```

**ZREVRANGE - 按排名范围查询（逆序）**

```bash
# 查询排名前3的元素（Top 3）
127.0.0.1:6379> ZREVRANGE rank 0 2 WITHSCORES
1) "张三"
2) "120"
3) "李四"
4) "95"
5) "王五"
6) "92"
```

**ZRANGEBYSCORE - 按分数范围查询（正序）**

```bash
# 查询分数90-100之间的元素
127.0.0.1:6379> ZRANGEBYSCORE rank 90 100
1) "王五"
2) "李四"

# 带分数
127.0.0.1:6379> ZRANGEBYSCORE rank 90 100 WITHSCORES
1) "王五"
2) "92"
3) "李四"
4) "95"

# 开区间：(90表示>90
127.0.0.1:6379> ZRANGEBYSCORE rank (90 100
1) "王五"
2) "李四"

# 限制返回数量：LIMIT offset count
127.0.0.1:6379> ZRANGEBYSCORE rank 0 200 LIMIT 0 3
1) "赵六"
2) "王五"
3) "李四"

# 正无穷和负无穷
127.0.0.1:6379> ZRANGEBYSCORE rank -inf +inf
# 查询全部元素
```

**ZREVRANGEBYSCORE - 按分数范围查询（逆序）**

```bash
# 查询分数100-90之间（注意：max在前，min在后）
127.0.0.1:6379> ZREVRANGEBYSCORE rank 100 90
1) "李四"
2) "王五"
```

### 2.4 删除操作

**ZREM - 删除元素**

```bash
# 删除单个元素
127.0.0.1:6379> ZREM rank "赵六"
(integer) 1

# 删除多个元素
127.0.0.1:6379> ZREM rank "王五" "李四"
(integer) 2
```

**ZREMRANGEBYRANK - 按排名范围删除**

```bash
# 删除排名0-1的元素（最低的2个）
127.0.0.1:6379> ZREMRANGEBYRANK rank 0 1
(integer) 2
```

**ZREMRANGEBYSCORE - 按分数范围删除**

```bash
# 删除分数90以下的元素
127.0.0.1:6379> ZREMRANGEBYSCORE rank -inf 90
(integer) 1
```

### 2.5 集合运算

**ZUNIONSTORE - 并集**

```bash
127.0.0.1:6379> ZADD zset1 1 "a" 2 "b" 3 "c"
(integer) 3

127.0.0.1:6379> ZADD zset2 2 "b" 4 "c" 5 "d"
(integer) 3

# 并集：相同元素的score相加
127.0.0.1:6379> ZUNIONSTORE result 2 zset1 zset2
(integer) 4

127.0.0.1:6379> ZRANGE result 0 -1 WITHSCORES
1) "a"
2) "1"
3) "b"
4) "4"   # 2+2
5) "d"
6) "5"
7) "c"
8) "7"   # 3+4
```

**ZINTERSTORE - 交集**

```bash
# 交集：只保留共同元素
127.0.0.1:6379> ZINTERSTORE common 2 zset1 zset2
(integer) 2

127.0.0.1:6379> ZRANGE common 0 -1 WITHSCORES
1) "b"
2) "4"
3) "c"
4) "7"
```

## 三、实战场景

### 场景1：游戏排行榜

**完整的排行榜系统**：

```java
@Service
public class LeaderboardService {

    private static final String LEADERBOARD_KEY = "game:leaderboard";

    // 提交分数
    public void submitScore(Long userId, int score) {
        redis.opsForZSet().add(LEADERBOARD_KEY,
                                String.valueOf(userId),
                                score);
    }

    // 增加分数
    public void addScore(Long userId, int delta) {
        redis.opsForZSet().incrementScore(LEADERBOARD_KEY,
                                           String.valueOf(userId),
                                           delta);
    }

    // 获取玩家分数
    public Integer getScore(Long userId) {
        Double score = redis.opsForZSet().score(LEADERBOARD_KEY,
                                                 String.valueOf(userId));
        return score != null ? score.intValue() : 0;
    }

    // 获取玩家排名（从1开始）
    public Long getRank(Long userId) {
        Long rank = redis.opsForZSet().reverseRank(LEADERBOARD_KEY,
                                                    String.valueOf(userId));
        return rank != null ? rank + 1 : null;
    }

    // 获取排行榜 Top N
    public List<Map<String, Object>> getTopN(int n) {
        Set<ZSetOperations.TypedTuple<String>> tuples =
                redis.opsForZSet().reverseRangeWithScores(LEADERBOARD_KEY,
                                                           0,
                                                           n - 1);

        List<Map<String, Object>> result = new ArrayList<>();
        int rank = 1;

        for (ZSetOperations.TypedTuple<String> tuple : tuples) {
            Map<String, Object> item = new HashMap<>();
            item.put("rank", rank++);
            item.put("userId", Long.valueOf(tuple.getValue()));
            item.put("score", tuple.getScore().intValue());
            result.add(item);
        }

        return result;
    }

    // 获取玩家周围的排名（前后各n个）
    public List<Map<String, Object>> getNearbyRank(Long userId, int n) {
        Long rank = redis.opsForZSet().reverseRank(LEADERBOARD_KEY,
                                                    String.valueOf(userId));

        if (rank == null) {
            return Collections.emptyList();
        }

        // 计算范围
        long start = Math.max(0, rank - n);
        long end = rank + n;

        Set<ZSetOperations.TypedTuple<String>> tuples =
                redis.opsForZSet().reverseRangeWithScores(LEADERBOARD_KEY,
                                                           start,
                                                           end);

        List<Map<String, Object>> result = new ArrayList<>();
        long currentRank = start + 1;

        for (ZSetOperations.TypedTuple<String> tuple : tuples) {
            Map<String, Object> item = new HashMap<>();
            item.put("rank", currentRank++);
            item.put("userId", Long.valueOf(tuple.getValue()));
            item.put("score", tuple.getScore().intValue());
            item.put("isMe", tuple.getValue().equals(String.valueOf(userId)));
            result.add(item);
        }

        return result;
    }

    // 按分数段查询玩家（查询90-100分的玩家）
    public List<Long> getPlayersByScore(int minScore, int maxScore) {
        Set<String> userIds = redis.opsForZSet().rangeByScore(LEADERBOARD_KEY,
                                                               minScore,
                                                               maxScore);

        return userIds.stream()
                .map(Long::valueOf)
                .collect(Collectors.toList());
    }

    // 清除排行榜底部玩家（只保留前10000名）
    public void cleanupLowRank() {
        Long total = redis.opsForZSet().zCard(LEADERBOARD_KEY);

        if (total > 10000) {
            redis.opsForZSet().removeRange(LEADERBOARD_KEY, 0, total - 10001);
        }
    }
}
```

### 场景2：热搜榜/trending

**实时热搜榜**：

```java
@Service
public class TrendingService {

    // 记录搜索（增加热度）
    public void recordSearch(String keyword) {
        String key = "trending:hot";

        // 热度+1
        redis.opsForZSet().incrementScore(key, keyword, 1);

        // 设置过期时间（保留24小时）
        redis.expire(key, 24, TimeUnit.HOURS);
    }

    // 获取热搜Top 10
    public List<Map<String, Object>> getHotSearches(int limit) {
        String key = "trending:hot";

        Set<ZSetOperations.TypedTuple<String>> tuples =
                redis.opsForZSet().reverseRangeWithScores(key, 0, limit - 1);

        List<Map<String, Object>> result = new ArrayList<>();
        int rank = 1;

        for (ZSetOperations.TypedTuple<String> tuple : tuples) {
            Map<String, Object> item = new HashMap<>();
            item.put("rank", rank++);
            item.put("keyword", tuple.getValue());
            item.put("hotValue", tuple.getScore().longValue());
            result.add(item);
        }

        return result;
    }

    // 按时间衰减热度（定时任务，每小时执行）
    @Scheduled(cron = "0 0 * * * ?")
    public void decayHotValue() {
        String key = "trending:hot";

        Set<ZSetOperations.TypedTuple<String>> all =
                redis.opsForZSet().rangeWithScores(key, 0, -1);

        for (ZSetOperations.TypedTuple<String> tuple : all) {
            double newScore = tuple.getScore() * 0.9;  // 衰减10%

            if (newScore < 1) {
                // 热度太低，删除
                redis.opsForZSet().remove(key, tuple.getValue());
            } else {
                redis.opsForZSet().add(key, tuple.getValue(), newScore);
            }
        }
    }
}
```

### 场景3：延迟队列

**基于ZSet实现延迟队列**：

```java
@Service
public class DelayQueueService {

    private static final String DELAY_QUEUE_KEY = "delay:queue";

    // 添加延迟任务
    public void addTask(String taskId, long delaySeconds) {
        long executeTime = System.currentTimeMillis() + delaySeconds * 1000;

        redis.opsForZSet().add(DELAY_QUEUE_KEY, taskId, executeTime);
    }

    // 获取到期任务（定时任务，每秒执行）
    @Scheduled(fixedRate = 1000)
    public void processExpiredTasks() {
        long now = System.currentTimeMillis();

        // 查询score小于当前时间的任务（已到期）
        Set<String> tasks = redis.opsForZSet().rangeByScore(DELAY_QUEUE_KEY,
                                                             0,
                                                             now);

        for (String taskId : tasks) {
            // 删除任务（防止重复执行）
            Long removed = redis.opsForZSet().remove(DELAY_QUEUE_KEY, taskId);

            if (removed > 0) {
                // 执行任务
                executeTask(taskId);
            }
        }
    }

    // 执行任务
    private void executeTask(String taskId) {
        log.info("执行延迟任务: {}", taskId);
        // 具体业务逻辑
    }

    // 取消任务
    public void cancelTask(String taskId) {
        redis.opsForZSet().remove(DELAY_QUEUE_KEY, taskId);
    }

    // 查询任务剩余时间
    public Long getTaskRemainTime(String taskId) {
        Double executeTime = redis.opsForZSet().score(DELAY_QUEUE_KEY, taskId);

        if (executeTime == null) {
            return null;
        }

        long remain = executeTime.longValue() - System.currentTimeMillis();
        return Math.max(0, remain / 1000);  // 转换为秒
    }
}
```

### 场景4：按价格筛选商品

**商品价格索引**：

```java
@Service
public class ProductPriceService {

    // 添加商品价格索引
    public void indexProduct(Long productId, BigDecimal price) {
        String key = "product:price:index";

        redis.opsForZSet().add(key,
                                String.valueOf(productId),
                                price.doubleValue());
    }

    // 按价格范围查询商品
    public List<Long> searchByPriceRange(BigDecimal minPrice,
                                          BigDecimal maxPrice,
                                          int page,
                                          int size) {
        String key = "product:price:index";

        // 分页参数
        int offset = (page - 1) * size;

        Set<String> productIds = redis.opsForZSet().rangeByScore(
                key,
                minPrice.doubleValue(),
                maxPrice.doubleValue(),
                offset,
                size
        );

        return productIds.stream()
                .map(Long::valueOf)
                .collect(Collectors.toList());
    }

    // 统计价格区间内的商品数量
    public Long countByPriceRange(BigDecimal minPrice, BigDecimal maxPrice) {
        String key = "product:price:index";

        return redis.opsForZSet().count(key,
                                         minPrice.doubleValue(),
                                         maxPrice.doubleValue());
    }

    // 删除商品索引
    public void removeProduct(Long productId) {
        String key = "product:price:index";
        redis.opsForZSet().remove(key, String.valueOf(productId));
    }
}
```

## 四、最佳实践

### 4.1 性能优化

**避免大ZSet**：

```java
// ❌ 不推荐：单个ZSet存储百万级数据
redis.opsForZSet().add("huge:zset", member, score);  // 100万个元素

// ✅ 推荐：按分片存储
String shardKey = "zset:shard:" + (hash(member) % 100);
redis.opsForZSet().add(shardKey, member, score);
```

**建议**：
- 单个ZSet元素数 < 10000
- 定期清理低分元素
- 监控ZSet大小

### 4.2 分数设计技巧

**时间戳作为分数**：

```java
// 延迟队列：执行时间作为分数
long executeTime = System.currentTimeMillis() + 3600000;  // 1小时后
redis.opsForZSet().add(key, taskId, executeTime);
```

**复合分数**：

```java
// 排行榜：score + timestamp（解决分数相同时的排序）
double score = actualScore + (timestamp / 1000000000.0);
redis.opsForZSet().add(key, member, score);
```

**负数分数**：

```java
// 优先级队列：数字越小优先级越高
redis.opsForZSet().add(key, task, -priority);
```

### 4.3 ZSet vs List

**何时用ZSet，何时用List？**

| 场景 | ZSet | List |
|------|------|------|
| **排行榜** | ✅ | ❌ |
| **按分数查询** | ✅ | ❌ |
| **时间线** | ✅ | ✅ |
| **消息队列** | ❌ | ✅ |
| **栈/队列** | ❌ | ✅ |

## 五、总结

### 核心要点

1. **ZSet是有序唯一集合**：按score排序，member唯一
2. **底层跳表实现**：查询、插入、删除都是O(log n)
3. **支持范围查询**：按排名、按分数、双向查询
4. **应用场景**：排行榜、热搜榜、延迟队列、价格筛选
5. **集合运算**：支持并集、交集，score可以相加

### 命令速查表

| 命令 | 作用 | 时间复杂度 |
|------|------|-----------|
| ZADD | 添加元素 | O(log n) |
| ZREM | 删除元素 | O(log n) |
| ZSCORE | 获取分数 | O(1) |
| ZRANK | 获取排名 | O(log n) |
| ZRANGE | 按排名查询 | O(log n + m) |
| ZRANGEBYSCORE | 按分数查询 | O(log n + m) |
| ZINCRBY | 增加分数 | O(log n) |
| ZCARD | 元素个数 | O(1) |
| ZCOUNT | 统计区间 | O(log n) |

### 下一步

掌握了5大数据类型后，下一篇我们将学习**键空间管理**：
- 过期策略详解
- 8种内存淘汰策略
- 内存优化技巧

---

**思考题**：
1. 为什么ZSet用跳表而不用红黑树？
2. 如何用ZSet实现一个按时间排序的时间线？
3. 排行榜中，分数相同的玩家如何排序？

下一篇见！
