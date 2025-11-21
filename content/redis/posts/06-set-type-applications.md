---
title: "Set类型应用：去重与集合运算"
date: 2025-01-21T12:30:00+08:00
draft: false
tags: ["Redis", "Set", "集合运算", "去重"]
categories: ["技术"]
description: "Set是Redis的无序集合，元素唯一不重复，支持强大的集合运算。深入理解Set的特性和应用，实现标签系统、好友关系、抽奖去重等场景。"
weight: 6
stage: 1
stageTitle: "基础入门篇"
---

## 引言

前面我们学习了有序的List，今天要学习**无序但唯一**的Set。

想象一下这些场景：
- 🏷️ **文章标签**："Java"、"Redis"、"数据库"，每个标签只能添加一次
- 👥 **共同好友**：你和张三有哪些共同好友？
- 🎲 **抽奖去重**：从1000个用户中随机抽10个中奖者，不能重复
- 📊 **UV统计**：今天有多少独立访客？

这些场景的共同特点是：**需要去重、需要集合运算**。Set正是为此而生。

## 一、Set的本质

### 1.1 什么是Set？

Set是一个**无序的、不重复的字符串集合**：

```
Set: {element1, element2, element3, ...}

特点：
- 无序：元素没有固定顺序
- 唯一：元素不会重复
- 支持集合运算：交集、并集、差集
```

**示例**：

```bash
# 添加元素
127.0.0.1:6379> SADD myset "apple" "banana" "orange"
(integer) 3

# 重复添加无效
127.0.0.1:6379> SADD myset "apple"
(integer) 0  # 0表示未添加（已存在）

# 查看所有元素（无序）
127.0.0.1:6379> SMEMBERS myset
1) "banana"
2) "orange"
3) "apple"
# 顺序可能每次都不同
```

### 1.2 Set vs List

| 特性 | Set | List |
|------|-----|------|
| **有序性** | 无序 | 有序 |
| **唯一性** | 元素唯一 | 可重复 |
| **查询元素是否存在** | O(1) | O(n) |
| **按索引访问** | 不支持 | 支持 |
| **集合运算** | 支持 | 不支持 |
| **适用场景** | 去重、标签、关系 | 队列、时间线 |

### 1.3 底层实现

Set有两种底层编码：

**1. intset（整数集合）** - 省内存

条件：
- 所有元素都是整数
- 元素数量 < `set-max-intset-entries`（默认512）

特点：
- 内存紧凑
- 有序存储（为了二分查找）
- 适合小集合

**2. hashtable（哈希表）** - 高性能

条件：不满足intset条件时

特点：
- 查询快（O(1)）
- 无序存储
- 内存占用较大

**查看编码**：

```bash
127.0.0.1:6379> SADD nums 1 2 3 4 5
(integer) 5

127.0.0.1:6379> OBJECT ENCODING nums
"intset"  # 全是整数，用intset

127.0.0.1:6379> SADD names "alice" "bob"
(integer) 2

127.0.0.1:6379> OBJECT ENCODING names
"hashtable"  # 字符串，用hashtable
```

## 二、Set命令全解析

### 2.1 基础操作

**SADD - 添加元素**

```bash
# 添加单个元素
127.0.0.1:6379> SADD myset "apple"
(integer) 1

# 添加多个元素
127.0.0.1:6379> SADD myset "banana" "orange" "grape"
(integer) 3

# 重复添加返回0
127.0.0.1:6379> SADD myset "apple"
(integer) 0
```

**SMEMBERS - 获取所有元素**

```bash
127.0.0.1:6379> SMEMBERS myset
1) "grape"
2) "banana"
3) "orange"
4) "apple"

# ⚠️ 注意：顺序是随机的
```

⚠️ **警告**：SMEMBERS会返回所有元素，大集合慎用（可能阻塞）！

**SISMEMBER - 检查元素是否存在**

```bash
127.0.0.1:6379> SISMEMBER myset "apple"
(integer) 1  # 存在

127.0.0.1:6379> SISMEMBER myset "watermelon"
(integer) 0  # 不存在
```

时间复杂度：O(1)，非常快！

**SCARD - 获取元素个数**

```bash
127.0.0.1:6379> SCARD myset
(integer) 4
```

**SREM - 删除元素**

```bash
# 删除单个元素
127.0.0.1:6379> SREM myset "apple"
(integer) 1  # 返回删除的个数

# 删除多个元素
127.0.0.1:6379> SREM myset "banana" "grape"
(integer) 2

# 删除不存在的元素返回0
127.0.0.1:6379> SREM myset "watermelon"
(integer) 0
```

### 2.2 随机操作

**SRANDMEMBER - 随机获取元素（不删除）**

```bash
127.0.0.1:6379> SADD lottery "user1" "user2" "user3" "user4" "user5"
(integer) 5

# 随机获取1个元素
127.0.0.1:6379> SRANDMEMBER lottery
"user3"

# 随机获取3个元素（不重复）
127.0.0.1:6379> SRANDMEMBER lottery 3
1) "user1"
2) "user4"
3) "user2"

# 负数表示可以重复
127.0.0.1:6379> SRANDMEMBER lottery -3
1) "user3"
2) "user3"  # 可能重复
3) "user1"
```

**SPOP - 随机弹出元素（会删除）**

```bash
# 随机弹出1个元素
127.0.0.1:6379> SPOP lottery
"user5"

127.0.0.1:6379> SCARD lottery
(integer) 4  # 剩余4个

# 随机弹出2个元素
127.0.0.1:6379> SPOP lottery 2
1) "user2"
2) "user4"

127.0.0.1:6379> SCARD lottery
(integer) 2  # 剩余2个
```

### 2.3 集合运算（重要！）

**SUNION - 并集（A ∪ B）**

```bash
127.0.0.1:6379> SADD set1 "a" "b" "c"
(integer) 3

127.0.0.1:6379> SADD set2 "b" "c" "d"
(integer) 3

# 并集：两个集合的所有元素（去重）
127.0.0.1:6379> SUNION set1 set2
1) "a"
2) "b"
3) "c"
4) "d"

# 可以同时求多个集合的并集
127.0.0.1:6379> SUNION set1 set2 set3
```

**SUNIONSTORE - 并集结果存储到新集合**

```bash
127.0.0.1:6379> SUNIONSTORE result set1 set2
(integer) 4  # 返回结果集合的元素个数

127.0.0.1:6379> SMEMBERS result
1) "a"
2) "b"
3) "c"
4) "d"
```

**SINTER - 交集（A ∩ B）**

```bash
# 交集：两个集合的共同元素
127.0.0.1:6379> SINTER set1 set2
1) "b"
2) "c"
```

**SINTERSTORE - 交集结果存储**

```bash
127.0.0.1:6379> SINTERSTORE common set1 set2
(integer) 2

127.0.0.1:6379> SMEMBERS common
1) "b"
2) "c"
```

**SDIFF - 差集（A - B）**

```bash
# 差集：在set1中但不在set2中的元素
127.0.0.1:6379> SDIFF set1 set2
1) "a"

# 注意：顺序很重要
127.0.0.1:6379> SDIFF set2 set1
1) "d"
```

**SDIFFSTORE - 差集结果存储**

```bash
127.0.0.1:6379> SDIFFSTORE diff set1 set2
(integer) 1

127.0.0.1:6379> SMEMBERS diff
1) "a"
```

### 2.4 迭代操作

**SSCAN - 迭代集合（生产环境推荐）**

```bash
# 类似KEYS，但不会阻塞
127.0.0.1:6379> SSCAN myset 0
1) "0"  # 下次迭代的游标（0表示结束）
2) 1) "orange"
   2) "apple"
   3) "banana"

# 可以指定匹配模式和数量
127.0.0.1:6379> SSCAN myset 0 MATCH "a*" COUNT 10
```

## 三、实战场景

### 场景1：标签系统

**文章标签管理**：

```java
@Service
public class TagService {

    // 给文章添加标签
    public void addTags(Long articleId, String... tags) {
        String key = "article:tags:" + articleId;
        redis.opsForSet().add(key, tags);
    }

    // 获取文章的所有标签
    public Set<String> getTags(Long articleId) {
        String key = "article:tags:" + articleId;
        return redis.opsForSet().members(key);
    }

    // 删除标签
    public void removeTag(Long articleId, String tag) {
        String key = "article:tags:" + articleId;
        redis.opsForSet().remove(key, tag);
    }

    // 检查文章是否有某个标签
    public boolean hasTag(Long articleId, String tag) {
        String key = "article:tags:" + articleId;
        return redis.opsForSet().isMember(key, tag);
    }

    // 获取带有指定标签的所有文章
    public Set<Long> getArticlesByTag(String tag) {
        String key = "tag:articles:" + tag;
        return redis.opsForSet().members(key).stream()
                .map(Long::valueOf)
                .collect(Collectors.toSet());
    }

    // 双向关联：给文章打标签时，同时维护标签→文章的关系
    public void addTagWithIndex(Long articleId, String tag) {
        String articleKey = "article:tags:" + articleId;
        String tagKey = "tag:articles:" + tag;

        // 文章→标签
        redis.opsForSet().add(articleKey, tag);

        // 标签→文章
        redis.opsForSet().add(tagKey, String.valueOf(articleId));
    }

    // 查找相似文章（标签交集）
    public Set<Long> findSimilarArticles(Long articleId) {
        String key = "article:tags:" + articleId;
        Set<String> tags = redis.opsForSet().members(key);

        if (tags.isEmpty()) {
            return Collections.emptySet();
        }

        // 获取每个标签对应的文章
        List<String> tagKeys = tags.stream()
                .map(tag -> "tag:articles:" + tag)
                .collect(Collectors.toList());

        // 求交集（有共同标签的文章）
        Set<String> similar = redis.opsForSet().intersect(tagKeys.get(0),
                                                           tagKeys.subList(1, tagKeys.size()));

        // 排除自己
        if (similar != null) {
            similar.remove(String.valueOf(articleId));
        }

        return similar.stream()
                .map(Long::valueOf)
                .collect(Collectors.toSet());
    }
}
```

### 场景2：共同好友

**社交关系管理**：

```java
@Service
public class FriendService {

    // 添加好友
    public void addFriend(Long userId, Long friendId) {
        String key = "user:friends:" + userId;
        redis.opsForSet().add(key, String.valueOf(friendId));
    }

    // 删除好友
    public void removeFriend(Long userId, Long friendId) {
        String key = "user:friends:" + userId;
        redis.opsForSet().remove(key, String.valueOf(friendId));
    }

    // 获取好友列表
    public Set<Long> getFriends(Long userId) {
        String key = "user:friends:" + userId;
        return redis.opsForSet().members(key).stream()
                .map(Long::valueOf)
                .collect(Collectors.toSet());
    }

    // 检查是否是好友
    public boolean isFriend(Long userId, Long friendId) {
        String key = "user:friends:" + userId;
        return redis.opsForSet().isMember(key, String.valueOf(friendId));
    }

    // 查找共同好友（交集）
    public Set<Long> getCommonFriends(Long userId1, Long userId2) {
        String key1 = "user:friends:" + userId1;
        String key2 = "user:friends:" + userId2;

        Set<String> common = redis.opsForSet().intersect(key1, key2);

        if (common == null) {
            return Collections.emptySet();
        }

        return common.stream()
                .map(Long::valueOf)
                .collect(Collectors.toSet());
    }

    // 可能认识的人（好友的好友，但不是自己的好友）
    public Set<Long> getMayKnow(Long userId) {
        String key = "user:friends:" + userId;
        Set<String> friends = redis.opsForSet().members(key);

        Set<Long> mayKnow = new HashSet<>();

        // 遍历每个好友
        for (String friendId : friends) {
            String friendKey = "user:friends:" + friendId;
            Set<String> friendsOfFriend = redis.opsForSet().members(friendKey);

            // 好友的好友
            for (String fof : friendsOfFriend) {
                Long fofId = Long.valueOf(fof);

                // 排除自己和已经是好友的人
                if (!fofId.equals(userId) && !friends.contains(fof)) {
                    mayKnow.add(fofId);
                }
            }
        }

        return mayKnow;
    }

    // 获取好友数量
    public Long getFriendCount(Long userId) {
        String key = "user:friends:" + userId;
        return redis.opsForSet().size(key);
    }
}
```

### 场景3：抽奖系统

**去重抽奖**：

```java
@Service
public class LotteryService {

    // 参与抽奖
    public boolean joinLottery(Long userId, String lotteryId) {
        String key = "lottery:participants:" + lotteryId;

        // 检查是否已参与
        if (redis.opsForSet().isMember(key, String.valueOf(userId))) {
            return false;  // 已参与，不能重复
        }

        // 添加到参与者集合
        redis.opsForSet().add(key, String.valueOf(userId));

        // 设置过期时间（活动结束后7天）
        redis.expire(key, 7, TimeUnit.DAYS);

        return true;
    }

    // 获取参与人数
    public Long getParticipantCount(String lotteryId) {
        String key = "lottery:participants:" + lotteryId;
        return redis.opsForSet().size(key);
    }

    // 开奖：随机抽取N个中奖者
    public Set<Long> drawWinners(String lotteryId, int count) {
        String key = "lottery:participants:" + lotteryId;

        // 随机弹出N个元素
        List<String> winners = redis.opsForSet().pop(key, count);

        if (winners == null) {
            return Collections.emptySet();
        }

        return winners.stream()
                .map(Long::valueOf)
                .collect(Collectors.toSet());
    }

    // 开奖（不删除参与者，用于可以多次抽奖）
    public Set<Long> drawWinnersWithoutRemove(String lotteryId, int count) {
        String key = "lottery:participants:" + lotteryId;

        // 随机获取N个元素（不删除）
        List<String> winners = redis.opsForSet().randomMembers(key, count);

        if (winners == null) {
            return Collections.emptySet();
        }

        return winners.stream()
                .map(Long::valueOf)
                .collect(Collectors.toSet());
    }

    // 查询是否中奖
    public boolean isWinner(Long userId, String lotteryId) {
        String key = "lottery:winners:" + lotteryId;
        return redis.opsForSet().isMember(key, String.valueOf(userId));
    }

    // 保存中奖名单
    public void saveWinners(String lotteryId, Set<Long> winners) {
        String key = "lottery:winners:" + lotteryId;

        String[] winnerArray = winners.stream()
                .map(String::valueOf)
                .toArray(String[]::new);

        redis.opsForSet().add(key, winnerArray);

        // 永久保存
        redis.persist(key);
    }
}
```

### 场景4：UV统计（独立访客）

**网站UV统计**：

```java
@Service
public class UVStatService {

    // 记录访问
    public void recordVisit(String page, Long userId) {
        String today = LocalDate.now().format(DateTimeFormatter.BASIC_ISO_DATE);
        String key = "uv:" + page + ":" + today;

        // 添加用户ID（Set自动去重）
        redis.opsForSet().add(key, String.valueOf(userId));

        // 设置过期时间（保留90天）
        redis.expire(key, 90, TimeUnit.DAYS);
    }

    // 获取今日UV
    public Long getTodayUV(String page) {
        String today = LocalDate.now().format(DateTimeFormatter.BASIC_ISO_DATE);
        String key = "uv:" + page + ":" + today;

        return redis.opsForSet().size(key);
    }

    // 获取指定日期UV
    public Long getUV(String page, LocalDate date) {
        String dateStr = date.format(DateTimeFormatter.BASIC_ISO_DATE);
        String key = "uv:" + page + ":" + dateStr;

        return redis.opsForSet().size(key);
    }

    // 获取最近7天UV（并集）
    public Long getRecentUV(String page, int days) {
        List<String> keys = new ArrayList<>();

        for (int i = 0; i < days; i++) {
            LocalDate date = LocalDate.now().minusDays(i);
            String dateStr = date.format(DateTimeFormatter.BASIC_ISO_DATE);
            keys.add("uv:" + page + ":" + dateStr);
        }

        // 求并集（去重）
        if (keys.isEmpty()) {
            return 0L;
        }

        Set<String> union = redis.opsForSet().union(keys.get(0),
                                                     keys.subList(1, keys.size()));

        return union != null ? (long) union.size() : 0L;
    }

    // 检查用户今天是否访问过
    public boolean hasVisitedToday(String page, Long userId) {
        String today = LocalDate.now().format(DateTimeFormatter.BASIC_ISO_DATE);
        String key = "uv:" + page + ":" + today;

        return redis.opsForSet().isMember(key, String.valueOf(userId));
    }
}
```

### 场景5：黑名单/白名单

**IP黑名单**：

```java
@Service
public class BlacklistService {

    private static final String BLACKLIST_KEY = "ip:blacklist";

    // 添加到黑名单
    public void addToBlacklist(String ip) {
        redis.opsForSet().add(BLACKLIST_KEY, ip);
    }

    // 从黑名单移除
    public void removeFromBlacklist(String ip) {
        redis.opsForSet().remove(BLACKLIST_KEY, ip);
    }

    // 检查是否在黑名单
    public boolean isBlacklisted(String ip) {
        return redis.opsForSet().isMember(BLACKLIST_KEY, ip);
    }

    // 获取黑名单列表
    public Set<String> getBlacklist() {
        return redis.opsForSet().members(BLACKLIST_KEY);
    }

    // 批量添加
    public void batchAdd(List<String> ips) {
        redis.opsForSet().add(BLACKLIST_KEY, ips.toArray(new String[0]));
    }

    // 获取黑名单大小
    public Long getBlacklistSize() {
        return redis.opsForSet().size(BLACKLIST_KEY);
    }
}
```

## 四、最佳实践

### 4.1 避免大集合

```java
// ❌ 不推荐：单个Set存储百万级数据
redis.opsForSet().add("big:set", ...);  // 100万个元素

// ✅ 推荐：按分片存储
String shardKey = "set:shard:" + (id % 100);
redis.opsForSet().add(shardKey, value);
```

**建议**：
- 单个Set元素数 < 10000
- 使用SSCAN而非SMEMBERS遍历大集合
- 监控集合大小，设置告警

### 4.2 集合运算优化

```java
// ❌ 不推荐：多次网络请求
Set<String> set1 = redis.opsForSet().members(key1);
Set<String> set2 = redis.opsForSet().members(key2);
set1.retainAll(set2);  // 在应用层求交集

// ✅ 推荐：在Redis服务器求交集
Set<String> result = redis.opsForSet().intersect(key1, key2);
```

### 4.3 Set vs Bitmap

**UV统计场景选择**：

| 方案 | Set | Bitmap |
|------|-----|--------|
| **内存占用** | 高 | 低 |
| **精确性** | 精确 | 精确 |
| **查询是否访问** | 快（O(1)） | 快（O(1)） |
| **适用场景** | UV < 100万 | UV > 100万 |

```java
// Set方式（精确，但占内存）
redis.opsForSet().add("uv:page1", userId);

// Bitmap方式（省内存）
redis.opsForValue().setBit("uv:page1", userId, true);
```

## 五、总结

### 核心要点

1. **Set是无序唯一集合**：自动去重，查询是否存在O(1)
2. **支持集合运算**：交集、并集、差集，解决复杂关系问题
3. **随机操作**：SRANDMEMBER/SPOP适合抽奖场景
4. **底层实现**：小整数集合用intset，其他用hashtable
5. **应用场景**：标签系统、好友关系、抽奖、UV统计、黑名单

### 命令速查表

| 命令 | 作用 | 时间复杂度 |
|------|------|-----------|
| SADD | 添加元素 | O(1) |
| SREM | 删除元素 | O(1) |
| SISMEMBER | 判断存在 | O(1) |
| SCARD | 元素个数 | O(1) |
| SMEMBERS | 所有元素 | O(n) |
| SRANDMEMBER | 随机获取 | O(1) |
| SPOP | 随机弹出 | O(1) |
| SUNION | 并集 | O(n) |
| SINTER | 交集 | O(n*m) |
| SDIFF | 差集 | O(n) |

### 集合运算图解

```
Set A: {1, 2, 3, 4}
Set B: {3, 4, 5, 6}

并集 SUNION: {1, 2, 3, 4, 5, 6}
交集 SINTER: {3, 4}
差集 SDIFF A B: {1, 2}
差集 SDIFF B A: {5, 6}
```

### 下一步

掌握了Set类型后，下一篇我们将学习**ZSet有序集合**：
- 分数排序机制
- 跳表数据结构
- 排行榜、延迟队列实现

---

**思考题**：
1. 为什么Set能O(1)判断元素是否存在，而List需要O(n)？
2. 如何用Set实现"你可能认识的人"功能？
3. 集合运算（交并差）的应用场景还有哪些？

下一篇见！
