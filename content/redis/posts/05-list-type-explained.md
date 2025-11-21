---
title: "List类型详解：从队列到时间线"
date: 2025-01-21T12:00:00+08:00
draft: false
tags: ["Redis", "List", "队列", "消息队列"]
categories: ["技术"]
description: "List是Redis的双端链表，可以从两端插入和弹出元素。深入理解List的特性，实现消息队列、时间线、最新列表等经典场景。"
weight: 5
stage: 1
stageTitle: "基础入门篇"
---

## 引言

在前面我们学习了String和Hash，它们都是"单值"类型。今天我们要学习第一个"集合"类型：**List**。

List最大的特点是：**有序、可重复、双端操作**。

想象一下这些场景：
- 📝 **微信朋友圈**：按时间倒序展示，最新的在最前面
- 📮 **消息队列**：先进先出（FIFO），生产者推送，消费者弹出
- 📰 **最新文章列表**：保留最新的100篇，自动淘汰旧的
- ⏱️ **操作日志**：记录用户最近的操作历史

这些场景的共同特点是：**需要保持顺序，支持两端操作**。List正是为此而生。

## 一、List的本质

### 1.1 什么是List？

List是一个**双向链表（Doubly Linked List）**：

```
head                                              tail
 ↓                                                 ↓
[A] ⇄ [B] ⇄ [C] ⇄ [D] ⇄ [E]
 ↑                                                 ↑
左端(head)                                      右端(tail)
LPUSH/LPOP                                    RPUSH/RPOP
```

特点：
- ✅ **有序**：元素按插入顺序排列
- ✅ **可重复**：允许重复元素
- ✅ **双端操作**：可以从左端或右端插入/弹出
- ✅ **索引访问**：支持按索引读取（但不推荐频繁使用）

### 1.2 List vs 数组

| 特性 | List（链表） | 数组 |
|------|-------------|------|
| **按索引访问** | O(n) | O(1) |
| **头尾插入/删除** | O(1) | O(n) |
| **中间插入/删除** | O(n) | O(n) |
| **内存占用** | 较高（指针） | 较低 |
| **适用场景** | 队列、栈 | 随机访问 |

**结论**：List适合队列操作，不适合频繁随机访问。

### 1.3 底层实现

Redis 3.2之前：
- **ziplist**（压缩列表）：元素少且小时
- **linkedlist**（双向链表）：元素多或大时

Redis 3.2+：
- **quicklist**（快速列表）：ziplist + linkedlist的混合体
- 将多个ziplist用双向链表连接起来
- 兼顾内存和性能

**查看编码**：

```bash
127.0.0.1:6379> LPUSH mylist "a" "b" "c"
(integer) 3

127.0.0.1:6379> OBJECT ENCODING mylist
"quicklist"
```

## 二、List命令全解析

### 2.1 左端操作（L = Left）

**LPUSH - 从左端插入**

```bash
# 插入单个元素
127.0.0.1:6379> LPUSH mylist "world"
(integer) 1

127.0.0.1:6379> LPUSH mylist "hello"
(integer) 2

# 结果：["hello", "world"]
# 注意：后插入的在前面

# 插入多个元素
127.0.0.1:6379> LPUSH mylist "a" "b" "c"
(integer) 5

# 结果：["c", "b", "a", "hello", "world"]
```

**LPOP - 从左端弹出**

```bash
127.0.0.1:6379> LPOP mylist
"c"  # 返回并删除最左边的元素

127.0.0.1:6379> LPOP mylist
"b"

# 现在列表：["a", "hello", "world"]
```

**LPUSHX - 仅当列表存在时插入**

```bash
127.0.0.1:6379> LPUSHX mylist "new"
(integer) 4  # 成功，列表存在

127.0.0.1:6379> LPUSHX notexist "new"
(integer) 0  # 失败，列表不存在
```

### 2.2 右端操作（R = Right）

**RPUSH - 从右端插入**

```bash
127.0.0.1:6379> RPUSH mylist "1" "2" "3"
(integer) 7

# 结果：["a", "hello", "world", "new", "1", "2", "3"]
```

**RPOP - 从右端弹出**

```bash
127.0.0.1:6379> RPOP mylist
"3"

127.0.0.1:6379> RPOP mylist
"2"
```

**常见组合**：

```bash
# 队列（FIFO）：左进右出
LPUSH queue "task1"  # 生产者
RPOP queue           # 消费者

# 栈（LIFO）：左进左出
LPUSH stack "item1"
LPOP stack

# 或者：右进右出
RPUSH stack "item1"
RPOP stack
```

### 2.3 阻塞操作（重要！）

**BLPOP/BRPOP - 阻塞式弹出**

```bash
# 阻塞式左弹出，超时时间10秒
127.0.0.1:6379> BLPOP mylist 10
1) "mylist"  # 键名
2) "a"       # 弹出的元素

# 如果列表为空，会阻塞等待，直到有元素或超时
127.0.0.1:6379> BLPOP emptylist 10
(nil)  # 10秒后超时返回nil

# 可以同时监听多个列表
127.0.0.1:6379> BLPOP list1 list2 list3 10
# 哪个列表先有元素就从哪个弹出
```

**应用场景**：

```java
// 消费者线程
while (true) {
    // 阻塞等待任务，0表示永不超时
    List<String> result = redis.blpop(0, "task:queue");
    if (result != null && result.size() == 2) {
        String task = result.get(1);
        processTask(task);
    }
}
```

### 2.4 查询操作

**LRANGE - 获取范围元素**

```bash
127.0.0.1:6379> RPUSH list "a" "b" "c" "d" "e"
(integer) 5

# 获取前3个元素（索引从0开始）
127.0.0.1:6379> LRANGE list 0 2
1) "a"
2) "b"
3) "c"

# 获取全部元素
127.0.0.1:6379> LRANGE list 0 -1
1) "a"
2) "b"
3) "c"
4) "d"
5) "e"

# 获取后3个元素
127.0.0.1:6379> LRANGE list -3 -1
1) "c"
2) "d"
3) "e"
```

**LINDEX - 按索引获取元素**

```bash
127.0.0.1:6379> LINDEX list 0
"a"

127.0.0.1:6379> LINDEX list -1
"e"  # -1表示最后一个

# 索引越界返回nil
127.0.0.1:6379> LINDEX list 100
(nil)
```

**LLEN - 获取列表长度**

```bash
127.0.0.1:6379> LLEN list
(integer) 5
```

### 2.5 修改操作

**LSET - 设置指定索引的值**

```bash
127.0.0.1:6379> LSET list 0 "A"
OK

127.0.0.1:6379> LRANGE list 0 -1
1) "A"  # 已修改
2) "b"
3) "c"
4) "d"
5) "e"

# 索引越界会报错
127.0.0.1:6379> LSET list 100 "X"
(error) ERR index out of range
```

**LINSERT - 在指定元素前/后插入**

```bash
# 在"c"之前插入"X"
127.0.0.1:6379> LINSERT list BEFORE "c" "X"
(integer) 6  # 返回插入后的列表长度

# 在"c"之后插入"Y"
127.0.0.1:6379> LINSERT list AFTER "c" "Y"
(integer) 7

127.0.0.1:6379> LRANGE list 0 -1
1) "A"
2) "b"
3) "X"
4) "c"
5) "Y"
6) "d"
7) "e"
```

**LTRIM - 保留指定范围，删除其他**

```bash
# 只保留索引1-3的元素
127.0.0.1:6379> LTRIM list 1 3
OK

127.0.0.1:6379> LRANGE list 0 -1
1) "b"
2) "X"
3) "c"

# 常用场景：保留最新的100条记录
LTRIM timeline 0 99
```

### 2.6 删除操作

**LREM - 删除指定值的元素**

```bash
127.0.0.1:6379> RPUSH nums 1 2 3 2 4 2 5
(integer) 7

# LREM key count value
# count > 0：从左往右删除count个
# count < 0：从右往左删除|count|个
# count = 0：删除所有

# 从左往右删除2个值为"2"的元素
127.0.0.1:6379> LREM nums 2 "2"
(integer) 2  # 返回删除的个数

127.0.0.1:6379> LRANGE nums 0 -1
1) "1"
2) "3"
3) "4"
4) "2"  # 还剩1个
5) "5"

# 删除所有值为"2"的元素
127.0.0.1:6379> LREM nums 0 "2"
(integer) 1
```

**RPOPLPUSH - 原子性移动元素**

```bash
# 从list1右端弹出，插入list2左端
127.0.0.1:6379> RPUSH list1 "a" "b" "c"
(integer) 3

127.0.0.1:6379> RPOPLPUSH list1 list2
"c"

127.0.0.1:6379> LRANGE list1 0 -1
1) "a"
2) "b"

127.0.0.1:6379> LRANGE list2 0 -1
1) "c"
```

## 三、实战场景

### 场景1：消息队列（简易版）

**生产者-消费者模型**：

```java
@Service
public class SimpleQueueService {

    @Autowired
    private RedisTemplate<String, String> redis;

    private static final String QUEUE_KEY = "task:queue";

    // 生产者：发布任务
    public void publishTask(String task) {
        redis.opsForList().leftPush(QUEUE_KEY, task);
        log.info("发布任务: {}", task);
    }

    // 消费者：消费任务（阻塞式）
    @PostConstruct
    public void consumeTasks() {
        new Thread(() -> {
            while (true) {
                try {
                    // 阻塞等待任务，超时时间0表示永不超时
                    String task = redis.opsForList().rightPop(QUEUE_KEY,
                                                               0,
                                                               TimeUnit.SECONDS);
                    if (task != null) {
                        processTask(task);
                    }
                } catch (Exception e) {
                    log.error("消费任务失败", e);
                }
            }
        }).start();
    }

    // 处理任务
    private void processTask(String task) {
        log.info("处理任务: {}", task);
        // 具体业务逻辑
        try {
            Thread.sleep(1000);  // 模拟耗时操作
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    // 获取队列长度
    public Long getQueueSize() {
        return redis.opsForList().size(QUEUE_KEY);
    }
}
```

**可靠消息队列（备份机制）**：

```java
// 使用RPOPLPUSH实现可靠消息队列
public class ReliableQueueService {

    private static final String QUEUE_KEY = "task:queue";
    private static final String PROCESSING_KEY = "task:processing";

    // 消费者取任务（原子性移动到processing列表）
    public String fetchTask() {
        // 从队列右端弹出，移到processing列表左端
        return redis.opsForList().rightPopAndLeftPush(QUEUE_KEY,
                                                       PROCESSING_KEY,
                                                       10,
                                                       TimeUnit.SECONDS);
    }

    // 任务完成，从processing列表删除
    public void completeTask(String task) {
        redis.opsForList().remove(PROCESSING_KEY, 1, task);
    }

    // 任务失败，重新放回队列
    public void retryTask(String task) {
        redis.opsForList().remove(PROCESSING_KEY, 1, task);
        redis.opsForList().leftPush(QUEUE_KEY, task);
    }

    // 监控：检查processing列表，重新放回超时任务
    @Scheduled(fixedRate = 60000)  // 每分钟执行
    public void checkTimeoutTasks() {
        List<String> tasks = redis.opsForList().range(PROCESSING_KEY, 0, -1);
        for (String task : tasks) {
            // 检查任务是否超时（这里简化处理）
            retryTask(task);
        }
    }
}
```

### 场景2：朋友圈时间线

**发布动态**：

```java
@Service
public class TimelineService {

    // 发布动态
    public void publishPost(Long userId, Post post) {
        String timelineKey = "timeline:user:" + userId;
        String postJson = JSON.toJSONString(post);

        // 插入到时间线左端（最新的在前面）
        redis.opsForList().leftPush(timelineKey, postJson);

        // 只保留最新500条
        redis.opsForList().trim(timelineKey, 0, 499);

        // 设置过期时间（30天）
        redis.expire(timelineKey, 30, TimeUnit.DAYS);
    }

    // 获取时间线（分页）
    public List<Post> getTimeline(Long userId, int page, int size) {
        String timelineKey = "timeline:user:" + userId;

        // 计算范围
        int start = (page - 1) * size;
        int end = start + size - 1;

        // 获取分页数据
        List<String> postJsonList = redis.opsForList().range(timelineKey,
                                                               start,
                                                               end);

        // 反序列化
        return postJsonList.stream()
                .map(json -> JSON.parseObject(json, Post.class))
                .collect(Collectors.toList());
    }

    // 删除指定动态
    public void deletePost(Long userId, String postId) {
        String timelineKey = "timeline:user:" + userId;

        // 获取所有动态
        List<String> posts = redis.opsForList().range(timelineKey, 0, -1);

        // 找到并删除
        for (String postJson : posts) {
            Post post = JSON.parseObject(postJson, Post.class);
            if (post.getId().equals(postId)) {
                redis.opsForList().remove(timelineKey, 1, postJson);
                break;
            }
        }
    }
}
```

### 场景3：最新文章列表

**首页展示最新文章**：

```java
@Service
public class ArticleListService {

    private static final String LATEST_KEY = "articles:latest";
    private static final int MAX_SIZE = 100;

    // 发布文章
    public void publishArticle(Article article) {
        String articleId = String.valueOf(article.getId());

        // 检查是否已存在
        redis.opsForList().remove(LATEST_KEY, 0, articleId);

        // 插入到左端
        redis.opsForList().leftPush(LATEST_KEY, articleId);

        // 只保留最新100篇
        redis.opsForList().trim(LATEST_KEY, 0, MAX_SIZE - 1);
    }

    // 获取最新文章列表
    public List<Article> getLatestArticles(int page, int size) {
        int start = (page - 1) * size;
        int end = start + size - 1;

        // 获取文章ID列表
        List<String> articleIds = redis.opsForList().range(LATEST_KEY,
                                                            start,
                                                            end);

        // 批量查询文章详情（可以从缓存或数据库）
        return articleIds.stream()
                .map(id -> getArticleById(Long.valueOf(id)))
                .filter(Objects::nonNull)
                .collect(Collectors.toList());
    }

    // 删除文章
    public void deleteArticle(Long articleId) {
        redis.opsForList().remove(LATEST_KEY, 0, String.valueOf(articleId));
    }
}
```

### 场景4：用户操作历史

**记录最近操作**：

```java
@Service
public class UserActionService {

    // 记录用户操作
    public void recordAction(Long userId, String action) {
        String key = "user:action:" + userId;

        // 构造操作记录
        Map<String, Object> record = new HashMap<>();
        record.put("action", action);
        record.put("timestamp", System.currentTimeMillis());

        String recordJson = JSON.toJSONString(record);

        // 插入操作历史
        redis.opsForList().leftPush(key, recordJson);

        // 只保留最近50条
        redis.opsForList().trim(key, 0, 49);

        // 设置过期时间（7天）
        redis.expire(key, 7, TimeUnit.DAYS);
    }

    // 获取操作历史
    public List<Map<String, Object>> getActionHistory(Long userId, int limit) {
        String key = "user:action:" + userId;

        List<String> records = redis.opsForList().range(key, 0, limit - 1);

        return records.stream()
                .map(json -> JSON.parseObject(json, Map.class))
                .collect(Collectors.toList());
    }

    // 清空操作历史
    public void clearHistory(Long userId) {
        String key = "user:action:" + userId;
        redis.delete(key);
    }
}
```

### 场景5：限流滑动窗口

**基于List实现滑动窗口限流**：

```java
@Service
public class RateLimiterService {

    // 限流检查：1分钟内最多100次请求
    public boolean isAllowed(String userId) {
        String key = "rate:limit:" + userId;
        long now = System.currentTimeMillis();
        long windowStart = now - 60000;  // 1分钟窗口

        // 1. 移除过期的请求记录
        redis.opsForList().trim(key, 0, -1);  // 先确保列表存在

        // 2. 获取窗口内的请求
        List<String> requests = redis.opsForList().range(key, 0, -1);

        // 3. 过滤出窗口内的请求
        long count = requests.stream()
                .map(Long::valueOf)
                .filter(timestamp -> timestamp > windowStart)
                .count();

        if (count >= 100) {
            return false;  // 超过限流阈值
        }

        // 4. 记录本次请求
        redis.opsForList().leftPush(key, String.valueOf(now));

        // 5. 只保留窗口内的记录（最多100条）
        redis.opsForList().trim(key, 0, 99);

        // 6. 设置过期时间
        redis.expire(key, 120, TimeUnit.SECONDS);  // 2分钟

        return true;
    }
}
```

## 四、最佳实践

### 4.1 性能优化

**避免大列表**：

```java
// ❌ 不推荐：单个列表存储百万级数据
redis.opsForList().leftPush("big:list", item);  // 100万条

// ✅ 推荐：按分片存储
String shardKey = "list:shard:" + (userId % 100);
redis.opsForList().leftPush(shardKey, item);
```

**避免LRANGE大范围查询**：

```java
// ❌ 不推荐：一次查询10000条
List<String> data = redis.opsForList().range(key, 0, 9999);

// ✅ 推荐：分页查询
for (int page = 0; page < 100; page++) {
    List<String> pageData = redis.opsForList().range(key,
                                                      page * 100,
                                                      page * 100 + 99);
}
```

### 4.2 控制列表大小

**使用LTRIM自动淘汰**：

```java
// 每次插入后自动修剪
public void addToList(String key, String value, int maxSize) {
    redis.opsForList().leftPush(key, value);
    redis.opsForList().trim(key, 0, maxSize - 1);
}
```

**建议**：
- 单个List元素数 < 10000
- 如果是时间线类场景，定期清理过期数据
- 监控列表长度，设置告警

### 4.3 消息队列的选择

| 场景 | 推荐方案 |
|------|---------|
| **简单任务队列** | Redis List |
| **需要消息确认** | Redis Stream（5.0+） |
| **高可靠性** | RabbitMQ |
| **高吞吐量** | Kafka |
| **延迟队列** | Redis ZSet |

**Redis List适合**：
- ✅ 轻量级任务队列
- ✅ 消息不需要持久化
- ✅ 消费者单一或少量
- ✅ 丢失少量消息可接受

**Redis List不适合**：
- ❌ 需要消息确认机制
- ❌ 需要多消费者组
- ❌ 需要消息回溯
- ❌ 对可靠性要求极高

## 五、常见问题

### Q1: LPUSH多个元素的顺序

```bash
127.0.0.1:6379> LPUSH list "a" "b" "c"
(integer) 3

127.0.0.1:6379> LRANGE list 0 -1
1) "c"  # 最后插入的在最左边
2) "b"
3) "a"

# 等价于：
LPUSH list "a"
LPUSH list "b"
LPUSH list "c"
```

### Q2: 如何实现栈和队列？

```bash
# 栈（LIFO）
LPUSH stack "item"  # 入栈
LPOP stack          # 出栈

# 队列（FIFO）
LPUSH queue "item"  # 入队
RPOP queue          # 出队
```

### Q3: BLPOP会一直阻塞吗？

```bash
# timeout=0：永不超时，一直阻塞
BLPOP list 0

# timeout>0：超时后返回nil
BLPOP list 10  # 10秒超时
```

## 六、总结

### 核心要点

1. **List是双向链表**：支持从两端插入/弹出，O(1)时间复杂度
2. **阻塞操作**：BLPOP/BRPOP适合实现消息队列
3. **LTRIM淘汰**：自动保留最新N条记录
4. **有序可重复**：元素按插入顺序排列，允许重复
5. **应用场景**：消息队列、时间线、最新列表、操作历史

### 命令速查表

| 命令 | 作用 | 时间复杂度 |
|------|------|-----------|
| LPUSH | 左端插入 | O(1) |
| RPUSH | 右端插入 | O(1) |
| LPOP | 左端弹出 | O(1) |
| RPOP | 右端弹出 | O(1) |
| BLPOP | 阻塞左弹出 | O(1) |
| BRPOP | 阻塞右弹出 | O(1) |
| LRANGE | 范围查询 | O(n) |
| LTRIM | 保留范围 | O(n) |
| LLEN | 获取长度 | O(1) |
| LINDEX | 按索引获取 | O(n) |

### 下一步

掌握了List类型后，下一篇我们将学习**Set类型**：
- 无序集合的特性
- 交并差集合运算
- 标签系统、好友关系、抽奖实现

---

**思考题**：
1. 为什么List实现消息队列时，推荐用BLPOP而不是循环LPOP？
2. 如何用List实现一个最大容量为100的循环队列？
3. RPOPLPUSH命令有什么用？能解决什么问题？

下一篇见！
