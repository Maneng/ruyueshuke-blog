---
title: "跳表SkipList：为什么Redis选择它而不是红黑树？"
date: 2025-01-21T20:20:00+08:00
draft: false
tags: ["Redis", "跳表", "SkipList", "数据结构"]
categories: ["技术"]
description: "深入理解Redis跳表的设计原理、实现细节和性能特点，掌握ZSet有序集合的底层秘密，理解为什么跳表在Redis中优于平衡树"
weight: 15
stage: 2
stageTitle: "架构原理篇"
---

## 引言

你是否好奇：**为什么Redis的有序集合（ZSet）能在O(logN)时间内完成插入、删除、查找和范围查询？为什么Redis选择跳表（SkipList）而不是更常见的红黑树或AVL树？**

今天我们深入剖析跳表的设计思想和实现细节，理解这个优雅而高效的数据结构。

## 一、从问题出发：有序集合的需求

### 1.1 ZSet的典型操作

```bash
# 添加元素（带分数）
127.0.0.1:6379> ZADD ranking 95 "张三" 88 "李四" 92 "王五"
(integer) 3

# 按分数范围查询
127.0.0.1:6379> ZRANGEBYSCORE ranking 90 100
1) "王五"     # 92分
2) "张三"     # 95分

# 查询排名
127.0.0.1:6379> ZRANK ranking "李四"
(integer) 0  # 第0名（分数最低）

# 删除元素
127.0.0.1:6379> ZREM ranking "李四"
(integer) 1
```

### 1.2 性能需求

| 操作 | 时间复杂度要求 |
|------|--------------|
| 插入元素 | O(logN) |
| 删除元素 | O(logN) |
| 查找元素 | O(logN) |
| 范围查询 | O(logN + M)，M为结果数量 |
| 获取排名 | O(logN) |

### 1.3 候选数据结构

| 数据结构 | 插入/删除/查找 | 范围查询 | 实现复杂度 | 内存占用 |
|---------|-------------|---------|----------|---------|
| **有序数组** | O(N) | O(logN + M) | 简单 | 低 |
| **平衡二叉树（AVL/红黑树）** | O(logN) | O(logN + M) | 复杂 | 中 |
| **B树/B+树** | O(logN) | O(logN + M) | 复杂 | 中 |
| **跳表（SkipList）** | O(logN) | O(logN + M) | **简单** | 中 |

**Redis选择跳表的理由**：
1. ✅ 性能接近平衡树（O(logN)）
2. ✅ **实现简单**，易于理解和维护
3. ✅ **支持范围查询**（底层有序链表）
4. ✅ **并发友好**（锁粒度小，适合多线程）
5. ✅ 内存占用可控

## 二、跳表核心思想

### 2.1 从链表到跳表

#### 问题：单链表查找慢（O(n)）

```
查找元素 7：
[1] -> [3] -> [5] -> [7] -> [9] -> [11] -> NULL
需要遍历4个节点
```

#### 优化1：增加一层索引

```
Level 1: [1] ------------> [7] ------------> NULL  (索引层)
Level 0: [1] -> [3] -> [5] -> [7] -> [9] -> [11] -> NULL  (数据层)

查找元素 7：
1. Level 1: 1 → 7（找到）
2. Level 0: 确认7
只需遍历2个节点
```

#### 优化2：多层索引（跳表）

```
Level 3: [1] -----------------------------------> NULL
Level 2: [1] ----------------> [7] -------------> NULL
Level 1: [1] -------> [5] -----> [9] -----------> NULL
Level 0: [1] -> [3] -> [5] -> [7] -> [9] -> [11] -> NULL

查找元素 9：
1. Level 3: 1 → NULL（下降）
2. Level 2: 1 → 7（继续）→ NULL（下降）
3. Level 1: 7 → 9（找到）
4. Level 0: 确认9
```

**关键思想**：
- **纵向**：多层索引，快速跳跃
- **横向**：有序链表，精确定位
- **平衡**：每层节点数约为下一层的1/2

### 2.2 跳表的"概率平衡"

**与平衡树的对比**：
- **AVL树/红黑树**：通过旋转保持严格平衡，实现复杂
- **跳表**：通过**随机化层数**实现"概率平衡"，实现简单

**随机层数算法**：
```c
// 每个节点随机决定层数
int randomLevel() {
    int level = 1;
    // 50%概率增加一层（抛硬币）
    while (rand() < PROBABILITY && level < MAX_LEVEL) {
        level++;
    }
    return level;
}
```

**期望性质**：
- Level 0：N个节点
- Level 1：N/2个节点
- Level 2：N/4个节点
- Level 3：N/8个节点
- ...

**时间复杂度**：O(logN)

## 三、Redis跳表实现

### 3.1 数据结构定义

#### 跳表节点（zskiplistNode）

```c
typedef struct zskiplistNode {
    sds ele;                      // 成员对象（SDS字符串）
    double score;                 // 分数（用于排序）
    struct zskiplistNode *backward;  // 后退指针（用于反向遍历）

    // 层级数组
    struct zskiplistLevel {
        struct zskiplistNode *forward;  // 前进指针
        unsigned long span;             // 跨度（用于计算排名）
    } level[];
} zskiplistNode;
```

**字段说明**：
- **ele**：成员值（如"张三"）
- **score**：分数（如95分）
- **backward**：指向前一个节点（支持ZREVRANGE）
- **level[]**：柔性数组，每层一个forward指针和span
  - **forward**：指向同层的下一个节点
  - **span**：到下一个节点的跨度（用于快速计算排名）

#### 跳表结构（zskiplist）

```c
typedef struct zskiplist {
    struct zskiplistNode *header;  // 头节点（不存储数据）
    struct zskiplistNode *tail;    // 尾节点
    unsigned long length;          // 节点数量（不含header）
    int level;                     // 最大层数
} zskiplist;
```

### 3.2 内存布局示例

存储ZSet：`{("A", 10), ("B", 20), ("C", 30)}`

```
header
Level 2: [ ] ---------------------------------> [C,30] -> NULL
Level 1: [ ] --------> [B,20] --------> [C,30] -> NULL
Level 0: [ ] -> [A,10] -> [B,20] -> [C,30] -> NULL
         ↑                             ↑
       header                        tail

backward: NULL <- [A,10] <- [B,20] <- [C,30]
```

**span示例**：
```
header[L2].forward = C, span = 3  (跨越A、B、C)
header[L1].forward = B, span = 2  (跨越A、B)
B[L1].forward = C, span = 1       (跨越C)
```

### 3.3 核心操作实现

#### 3.3.1 查找元素

```c
zskiplistNode *zslSearch(zskiplist *zsl, double score, sds ele) {
    zskiplistNode *x = zsl->header;

    // 从最高层开始查找
    for (int i = zsl->level - 1; i >= 0; i--) {
        // 在当前层向右移动，直到下一个节点的score大于目标
        while (x->level[i].forward &&
               (x->level[i].forward->score < score ||
                (x->level[i].forward->score == score &&
                 sdscmp(x->level[i].forward->ele, ele) < 0))) {
            x = x->level[i].forward;
        }
    }

    // 下降到Level 0，检查下一个节点
    x = x->level[0].forward;
    if (x && x->score == score && sdscmp(x->ele, ele) == 0) {
        return x;  // 找到
    }
    return NULL;  // 未找到
}
```

**查找过程示例**（查找score=25的元素）：
```
Level 2: [header] ---span=3---> [C,30]  (30>25，下降)
Level 1: [header] ---span=2---> [B,20]  (20<25，前进) ---span=1---> [C,30]  (30>25，下降)
Level 0: [B,20] ---span=1---> [C,30]
结论：未找到score=25的元素
```

#### 3.3.2 插入元素

```c
zskiplistNode *zslInsert(zskiplist *zsl, double score, sds ele) {
    zskiplistNode *update[ZSKIPLIST_MAXLEVEL];  // 记录每层的插入位置
    unsigned long rank[ZSKIPLIST_MAXLEVEL];     // 记录每层的排名
    zskiplistNode *x;

    x = zsl->header;
    // 1. 查找插入位置（类似查找操作）
    for (int i = zsl->level - 1; i >= 0; i--) {
        rank[i] = (i == zsl->level - 1) ? 0 : rank[i + 1];

        while (x->level[i].forward &&
               (x->level[i].forward->score < score ||
                (x->level[i].forward->score == score &&
                 sdscmp(x->level[i].forward->ele, ele) < 0))) {
            rank[i] += x->level[i].span;
            x = x->level[i].forward;
        }
        update[i] = x;  // 记录每层的插入前驱节点
    }

    // 2. 随机生成层数
    int level = zslRandomLevel();
    if (level > zsl->level) {
        for (int i = zsl->level; i < level; i++) {
            rank[i] = 0;
            update[i] = zsl->header;
            update[i]->level[i].span = zsl->length;
        }
        zsl->level = level;
    }

    // 3. 创建新节点
    x = zslCreateNode(level, score, ele);

    // 4. 插入到跳表中（更新每层的forward指针和span）
    for (int i = 0; i < level; i++) {
        x->level[i].forward = update[i]->level[i].forward;
        update[i]->level[i].forward = x;

        // 更新span
        x->level[i].span = update[i]->level[i].span - (rank[0] - rank[i]);
        update[i]->level[i].span = (rank[0] - rank[i]) + 1;
    }

    // 5. 更新未涉及层的span
    for (int i = level; i < zsl->level; i++) {
        update[i]->level[i].span++;
    }

    // 6. 设置backward指针
    x->backward = (update[0] == zsl->header) ? NULL : update[0];
    if (x->level[0].forward) {
        x->level[0].forward->backward = x;
    } else {
        zsl->tail = x;
    }

    zsl->length++;
    return x;
}
```

**插入示例**（插入("B", 20)到空跳表）：
```
1. 随机层数：假设level=2
2. 创建节点B

Before:
Level 1: [header] -> NULL
Level 0: [header] -> NULL

After:
Level 1: [header] ---span=1---> [B,20] -> NULL
Level 0: [header] ---span=1---> [B,20] -> NULL
```

#### 3.3.3 删除元素

```c
int zslDelete(zskiplist *zsl, double score, sds ele) {
    zskiplistNode *update[ZSKIPLIST_MAXLEVEL];
    zskiplistNode *x;

    x = zsl->header;
    // 1. 查找删除位置
    for (int i = zsl->level - 1; i >= 0; i--) {
        while (x->level[i].forward &&
               (x->level[i].forward->score < score ||
                (x->level[i].forward->score == score &&
                 sdscmp(x->level[i].forward->ele, ele) < 0))) {
            x = x->level[i].forward;
        }
        update[i] = x;
    }

    x = x->level[0].forward;
    if (x && x->score == score && sdscmp(x->ele, ele) == 0) {
        // 2. 删除节点（更新指针和span）
        zslDeleteNode(zsl, x, update);
        zslFreeNode(x);
        return 1;
    }
    return 0;  // 未找到
}

void zslDeleteNode(zskiplist *zsl, zskiplistNode *x, zskiplistNode **update) {
    // 更新每层的forward指针和span
    for (int i = 0; i < zsl->level; i++) {
        if (update[i]->level[i].forward == x) {
            update[i]->level[i].span += x->level[i].span - 1;
            update[i]->level[i].forward = x->level[i].forward;
        } else {
            update[i]->level[i].span--;
        }
    }

    // 更新backward指针
    if (x->level[0].forward) {
        x->level[0].forward->backward = x->backward;
    } else {
        zsl->tail = x->backward;
    }

    // 更新level（如果删除的是最高层的唯一节点）
    while (zsl->level > 1 && zsl->header->level[zsl->level - 1].forward == NULL) {
        zsl->level--;
    }
    zsl->length--;
}
```

#### 3.3.4 范围查询

```c
// 按分数范围查询
zskiplistNode *zslFirstInRange(zskiplist *zsl, zrangespec *range) {
    if (!zslIsInRange(zsl, range)) return NULL;

    zskiplistNode *x = zsl->header;
    // 从最高层开始查找第一个符合条件的节点
    for (int i = zsl->level - 1; i >= 0; i--) {
        while (x->level[i].forward &&
               !zslValueGteMin(x->level[i].forward->score, range)) {
            x = x->level[i].forward;
        }
    }

    x = x->level[0].forward;
    if (!zslValueLteMax(x->score, range)) return NULL;
    return x;
}
```

**使用示例**：
```bash
127.0.0.1:6379> ZRANGEBYSCORE ranking 90 95
# 内部流程：
# 1. 查找第一个score>=90的节点（zslFirstInRange）
# 2. 从该节点开始，沿着Level 0向右遍历
# 3. 每个节点判断score是否<=95
# 4. 收集符合条件的节点
```

## 四、性能分析

### 4.1 时间复杂度

| 操作 | 平均情况 | 最坏情况 | 说明 |
|------|---------|---------|------|
| 查找 | O(logN) | O(N) | 最坏情况：退化为链表（概率极低） |
| 插入 | O(logN) | O(N) | 查找位置 + 插入操作 |
| 删除 | O(logN) | O(N) | 查找位置 + 删除操作 |
| 范围查询 | O(logN + M) | O(N + M) | M为结果数量 |
| 获取排名 | O(logN) | O(N) | 通过span计算 |

**为什么平均是O(logN)？**
- 每层节点数期望为下层的1/2
- 最高层期望高度：log₂N
- 查找路径期望长度：log₂N

### 4.2 空间复杂度

**每个节点的额外空间**：
```
平均层数 = 1 / (1 - p) = 1 / 0.5 = 2

每个节点平均有2层，每层需要：
- forward指针：8字节
- span：8字节
总计：2 * 16 = 32字节额外空间

加上节点本身（ele + score + backward）：约50字节
总内存：约80-100字节 per 节点
```

**与红黑树对比**：
- **跳表**：平均每节点2个指针（forward）
- **红黑树**：每节点2个指针（left, right）+ 颜色标志
- **内存占用**：跳表 ≈ 红黑树

### 4.3 概率保证

**退化概率**：
- 所有节点只有1层（退化为链表）：p = (1/2)^N ≈ 0（N很小时也极低）
- 最高层超过logN：p < 1/N

**实际性能**：
- 10,000个元素：平均查找14次比较
- 1,000,000个元素：平均查找20次比较
- 性能稳定，不需要平衡操作

## 五、跳表 vs 红黑树

### 5.1 全面对比

| 特性 | 跳表 | 红黑树 |
|------|------|--------|
| **时间复杂度** | O(logN) 平均，O(N)最坏 | O(logN) 严格保证 |
| **实现复杂度** | ✅ 简单（100行代码） | ❌ 复杂（500+行代码） |
| **范围查询** | ✅ 简单（顺序遍历） | ❌ 需要中序遍历 |
| **并发性** | ✅ 好（锁粒度小） | ❌ 差（平衡需要全局锁） |
| **内存占用** | 中（平均2层） | 中（2个指针+颜色） |
| **代码可读性** | ✅ 高 | ❌ 低（旋转逻辑复杂） |
| **维护成本** | ✅ 低 | ❌ 高 |

### 5.2 Redis选择跳表的原因

**William Pugh（跳表发明者）的评价**：
> "Skip lists are a probabilistically balanced data structure that are simpler, faster, and use less space than balanced trees."

**Redis作者antirez的解释**：
> 1. 实现简单，代码可读性高
> 2. 不需要复杂的旋转操作
> 3. 范围查询性能好（底层就是有序链表）
> 4. 适合单线程模型（如果将来支持多线程，跳表也更容易加锁）

## 六、实战应用

### 6.1 排行榜系统

```java
@Service
public class LeaderboardService {
    @Autowired
    private RedisTemplate<String, Object> redis;

    // 添加/更新用户分数
    public void updateScore(String userId, double score) {
        redis.opsForZSet().add("leaderboard", userId, score);
        // 内部：跳表插入，O(logN)
    }

    // 获取Top N
    public Set<ZSetOperations.TypedTuple<Object>> getTopN(int n) {
        return redis.opsForZSet().reverseRangeWithScores("leaderboard", 0, n - 1);
        // 内部：从tail开始遍历n个节点，O(logN + n)
    }

    // 获取用户排名
    public Long getUserRank(String userId) {
        return redis.opsForZSet().reverseRank("leaderboard", userId);
        // 内部：通过span计算排名，O(logN)
    }

    // 获取分数段用户
    public Set<Object> getRangeByScore(double min, double max) {
        return redis.opsForZSet().rangeByScore("leaderboard", min, max);
        // 内部：跳表范围查询，O(logN + M)
    }
}
```

### 6.2 延迟队列

```java
@Service
public class DelayQueueService {
    @Autowired
    private RedisTemplate<String, Object> redis;

    // 添加延迟任务（score=执行时间戳）
    public void addTask(String taskId, long executeTime) {
        redis.opsForZSet().add("delay_queue", taskId, executeTime);
    }

    // 拉取到期任务
    public Set<Object> pullReadyTasks() {
        long now = System.currentTimeMillis();
        Set<Object> tasks = redis.opsForZSet().rangeByScore("delay_queue", 0, now);

        // 删除已拉取的任务
        if (!tasks.isEmpty()) {
            redis.opsForZSet().removeRangeByScore("delay_queue", 0, now);
        }
        return tasks;
        // 内部：范围查询 + 范围删除，O(logN + M)
    }
}
```

## 七、最佳实践

### 7.1 充分利用跳表特性

✅ **推荐做法**：

1. **范围查询优先用ZSet**：
   ```java
   // ✅ 用ZSet存储时间序列数据
   redis.opsForZSet().add("user_actions", action, timestamp);
   Set<Object> recent = redis.opsForZSet().rangeByScore("user_actions",
       start, end);  // O(logN + M)
   ```

2. **利用排名特性**：
   ```java
   // ✅ 快速获取排名
   Long rank = redis.opsForZSet().rank("scores", userId);  // O(logN)
   ```

3. **分数相同时的排序**：
   ```java
   // ✅ 分数相同时，按member字典序排序
   redis.opsForZSet().add("ranking", "user1", 100.0);
   redis.opsForZSet().add("ranking", "user2", 100.0);
   // 返回顺序：user1, user2（字典序）
   ```

### 7.2 避免的误区

❌ **反模式**：

1. **不要频繁获取全部元素**：
   ```java
   // ❌ 不好：获取全部元素
   Set<Object> all = redis.opsForZSet().range("zset", 0, -1);  // O(N)

   // ✅ 好：分页获取
   Set<Object> page = redis.opsForZSet().range("zset", 0, 99);  // O(logN + 100)
   ```

2. **避免单个ZSet过大**：
   ```java
   // ❌ 不好：单个ZSet存储百万级数据
   // 导致单次操作耗时过长

   // ✅ 好：按时间/类型分片
   String key = "ranking:" + (userId % 100);  // 100个ZSet分片
   ```

## 八、总结

### 8.1 核心要点

1. **跳表设计思想**
   - 多层索引 + 有序链表
   - 概率平衡（随机层数）
   - 纵向快速跳跃，横向精确定位

2. **Redis跳表实现**
   - zskiplistNode：ele、score、backward、level[]
   - level.forward：前进指针
   - level.span：跨度（用于排名计算）

3. **性能特点**
   - 时间复杂度：O(logN) 平均
   - 空间复杂度：O(N)，每节点平均2层
   - 并发友好，实现简单

4. **跳表 vs 红黑树**
   - 性能相当，实现简单得多
   - 范围查询更快
   - 适合Redis单线程模型

5. **适用场景**
   - 排行榜、延迟队列
   - 时间序列数据
   - 需要快速范围查询的有序数据

### 8.2 设计哲学

跳表体现了"简单就是美"的设计哲学：

1. **用随机化代替复杂的平衡算法**
2. **用空间换时间**（多层索引）
3. **保持实现的简洁性**（易于理解和维护）
4. **优先考虑实际应用场景**（范围查询、排名）

### 8.3 下一篇预告

理解了跳表的实现后，你是否好奇：**Redis的哈希表（Hash）是如何实现O(1)查询的？渐进式rehash是如何避免阻塞的？**

下一篇《字典与哈希表》，我们将深入剖析Redis字典的实现细节，理解渐进式rehash、哈希冲突解决等核心机制。

---

**思考题**：
1. 为什么跳表的随机层数算法使用50%概率而不是33%或75%？
2. 如果要实现一个并发安全的跳表，你会如何设计锁策略？
3. 跳表的span字段有什么用？如果去掉span，如何快速获取排名？

欢迎在评论区分享你的思考！
