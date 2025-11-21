---
title: Redis五大数据结构：从场景到实现
date: 2025-11-03T10:00:00+08:00
draft: false
tags:
  - Redis
  - 数据结构
  - String
  - List
  - Hash
  - Set
  - ZSet
  - 第一性原理
categories:
  - Java技术生态
series:
  - Redis第一性原理
weight: 39
stage: 1
stageTitle: "基础夯实篇"
description: 深度剖析Redis五大数据结构（String、List、Hash、Set、ZSet）的使用场景、底层实现和性能优化。从电商、社交、游戏等真实业务场景出发，讲解SDS、ziplist、skiplist等底层数据结构。18000字深度技术文章。
---

## 一、引子：为什么Redis需要五大数据结构？

很多人的疑问：Memcached只有String一种数据结构，Redis为什么需要五种？

**核心答案**：**不同的业务场景需要不同的数据结构**。

### 1.1 如果只有String会怎样？

假设我们要实现一个排行榜功能，只有String的话：

```java
// ❌ 方案1：用String存储整个排行榜（JSON序列化）
// 问题：每次更新一个用户分数，需要序列化/反序列化整个排行榜
public void updateScore(Long userId, int score) {
    // 1. 读取整个排行榜（反序列化）
    String json = redisTemplate.opsForValue().get("rank:list");
    List<User> rankList = JSON.parseArray(json, User.class);  // 10000个用户

    // 2. 更新一个用户的分数
    for (User user : rankList) {
        if (user.getId().equals(userId)) {
            user.setScore(score);
            break;
        }
    }

    // 3. 重新排序
    rankList.sort((a, b) -> b.getScore() - a.getScore());

    // 4. 写入Redis（序列化）
    String newJson = JSON.toJSONString(rankList);
    redisTemplate.opsForValue().set("rank:list", newJson);
}

// 性能问题：
// - 读取：反序列化10000个用户，耗时100ms
// - 排序：O(NlogN) = 10000*log(10000) ≈ 130000次比较
// - 写入：序列化10000个用户，耗时100ms
// 总耗时：200ms+（单次更新）
```

```java
// ✅ 方案2：使用Redis ZSet（有序集合）
// 优势：Redis内部维护排序，O(logN)复杂度
public void updateScore(Long userId, int score) {
    redisTemplate.opsForZSet().add("rank:zset", userId.toString(), score);
}

// 性能提升：
// - 写入：O(logN) = log(10000) ≈ 13次比较
// - 总耗时：1ms
// 性能提升：200倍
```

**核心洞察**：
- String：适合简单KV存储
- ZSet：适合排序场景，性能提升200倍

### 1.2 五大数据结构的业务场景

| 数据结构 | 核心特性 | 典型场景 | 时间复杂度 |
|---------|---------|---------|-----------|
| **String** | 简单KV存储 | 计数器、Session、缓存 | O(1) |
| **List** | 双向链表 | 消息队列、最新列表、时间线 | O(1) |
| **Hash** | 字段映射 | 对象存储、购物车 | O(1) |
| **Set** | 无序集合 | 标签、去重、共同好友 | O(1) |
| **ZSet** | 有序集合 | 排行榜、延时队列、范围查询 | O(logN) |

---

## 二、String：最基础的KV存储

### 2.1 String的应用场景

#### 场景1：分布式Session

```java
/**
 * 用户登录，生成Session
 */
@PostMapping("/api/login")
public LoginResponse login(@RequestBody LoginRequest request) {
    // 1. 验证用户名密码
    User user = userService.authenticate(request.getUsername(), request.getPassword());
    if (user == null) {
        throw new UnauthorizedException("用户名或密码错误");
    }

    // 2. 生成token
    String token = UUID.randomUUID().toString();

    // 3. 将用户信息存入Redis（Session）
    String sessionKey = "session:" + token;
    UserVO userVO = convertToVO(user);
    redisTemplate.opsForValue().set(sessionKey, userVO, 30, TimeUnit.MINUTES);

    return new LoginResponse(token);
}

/**
 * 验证Session
 */
@GetMapping("/api/user/info")
public UserVO getUserInfo(@RequestHeader("token") String token) {
    String sessionKey = "session:" + token;

    // 从Redis获取Session
    UserVO user = redisTemplate.opsForValue().get(sessionKey);
    if (user == null) {
        throw new UnauthorizedException("未登录或Session已过期");
    }

    return user;
}
```

**性能对比**：

| 方案 | 响应时间 | 说明 |
|------|---------|------|
| 数据库存储Session | 50ms | 每次查询数据库 |
| Redis存储Session | 1ms | 内存访问 |
| 性能提升 | 50倍 | |

#### 场景2：分布式计数器

```java
/**
 * 文章浏览量计数器
 */
@GetMapping("/api/article/{id}")
public ArticleVO getArticle(@PathVariable Long id) {
    // 1. 查询文章内容
    Article article = articleRepository.findById(id);

    // 2. 增加浏览量（原子操作）
    String viewCountKey = "article:view:" + id;
    Long viewCount = redisTemplate.opsForValue().increment(viewCountKey);

    ArticleVO vo = convertToVO(article);
    vo.setViewCount(viewCount);

    return vo;
}

/**
 * 定时任务：每分钟将浏览量同步到数据库
 */
@Scheduled(fixedDelay = 60000)
public void syncViewCountToDB() {
    // 1. 获取所有文章的浏览量key
    Set<String> keys = redisTemplate.keys("article:view:*");

    // 2. 批量获取浏览量
    List<Long> viewCounts = redisTemplate.opsForValue().multiGet(keys);

    // 3. 批量更新数据库
    for (int i = 0; i < keys.size(); i++) {
        String key = keys.get(i);
        Long articleId = Long.parseLong(key.replace("article:view:", ""));
        Long viewCount = viewCounts.get(i);

        articleRepository.updateViewCount(articleId, viewCount);
    }
}
```

**为什么用Redis而不是直接更新数据库？**

```
假设：文章浏览量QPS = 10000

方案1：直接更新数据库
  UPDATE article SET view_count = view_count + 1 WHERE id = 123;

  问题：
  - 每次更新都写磁盘（10ms）
  - QPS上限：1000/10ms = 100
  - 需要100台数据库才能支撑10000 QPS
  - 成本：100台 × 2000元/月 = 20万元/月

方案2：Redis计数器 + 定时同步
  INCR article:view:123  # 内存操作（0.1ms）

  优势：
  - QPS上限：10万+
  - 1台Redis即可支撑
  - 成本：200元/月

  权衡：
  - 数据库数据有1分钟延迟（可接受）
  - Redis重启会丢失未同步数据（可容忍）

成本对比：20万 vs 200元（1000倍差异）
```

#### 场景3：分布式锁

```java
/**
 * 秒杀场景：防止超卖
 */
@PostMapping("/api/seckill/{productId}")
public SeckillResult seckill(@PathVariable Long productId, @RequestHeader("token") String token) {
    String lockKey = "lock:seckill:" + productId;

    try {
        // 1. 尝试获取分布式锁（SETNX）
        Boolean locked = redisTemplate.opsForValue().setIfAbsent(
            lockKey,
            token,  // 锁的value设置为token，用于后续释放锁时校验
            10,     // 锁的过期时间（防止死锁）
            TimeUnit.SECONDS
        );

        if (!Boolean.TRUE.equals(locked)) {
            return new SeckillResult(false, "系统繁忙，请稍后再试");
        }

        // 2. 执行秒杀逻辑
        // 2.1 检查库存
        Integer stock = productRepository.getStock(productId);
        if (stock <= 0) {
            return new SeckillResult(false, "商品已售罄");
        }

        // 2.2 扣减库存
        productRepository.decrementStock(productId);

        // 2.3 创建订单
        Order order = orderService.createOrder(productId, getUserId(token));

        return new SeckillResult(true, "秒杀成功", order.getId());

    } finally {
        // 3. 释放锁（使用Lua脚本保证原子性）
        String script =
            "if redis.call('get', KEYS[1]) == ARGV[1] then " +
            "    return redis.call('del', KEYS[1]) " +
            "else " +
            "    return 0 " +
            "end";

        redisTemplate.execute(
            new DefaultRedisScript<>(script, Long.class),
            Collections.singletonList(lockKey),
            token
        );
    }
}
```

**为什么释放锁要用Lua脚本？**

```java
// ❌ 错误：非原子操作，可能删除别人的锁
String value = redisTemplate.opsForValue().get(lockKey);
if (token.equals(value)) {
    // 假设这里发生了长时间GC（5秒）
    // 锁已经过期，被其他线程获取
    redisTemplate.delete(lockKey);  // 删除了别人的锁！
}

// ✅ 正确：Lua脚本保证原子性
String script =
    "if redis.call('get', KEYS[1]) == ARGV[1] then " +
    "    return redis.call('del', KEYS[1]) " +
    "else " +
    "    return 0 " +
    "end";

// Lua脚本在Redis中原子执行，不会被打断
```

### 2.2 String的底层实现

Redis String的底层实现不是C语言的字符串（char*），而是**SDS（Simple Dynamic String）**。

**SDS vs C字符串**：

```c
// C字符串：以'\0'结尾
char* str = "hello";  // 实际存储：'h','e','l','l','o','\0'

// 问题：
// 1. 获取长度需要遍历：O(N)
// 2. 无法存储二进制数据（'\0'是结束符）
// 3. 容易缓冲区溢出（strcat不检查长度）

// Redis SDS结构（简化版）
struct sdshdr {
    int len;        // 字符串长度（已使用）
    int free;       // 剩余空间
    char buf[];     // 字符数组
};

// 优势：
// 1. 获取长度：O(1)
// 2. 可以存储二进制数据
// 3. 杜绝缓冲区溢出（自动扩容）
// 4. 减少内存重分配次数
```

**SDS的三种编码**：

Redis会根据字符串的内容和长度，选择不同的编码方式：

| 编码 | 条件 | 说明 |
|------|-----|------|
| **int** | 字符串是整数，且范围在long内 | 直接存储整数，节省内存 |
| **embstr** | 字符串长度 ≤ 44字节 | 一次内存分配，只读 |
| **raw** | 字符串长度 > 44字节 | 两次内存分配，可修改 |

```bash
# 查看String的编码
127.0.0.1:6379> SET count 123
OK
127.0.0.1:6379> OBJECT ENCODING count
"int"  # 整数编码

127.0.0.1:6379> SET short "hello"
OK
127.0.0.1:6379> OBJECT ENCODING short
"embstr"  # embstr编码（长度≤44字节）

127.0.0.1:6379> SET long "this is a very long string ........（超过44字节）"
OK
127.0.0.1:6379> OBJECT ENCODING long
"raw"  # raw编码（长度>44字节）
```

**为什么embstr是44字节？**

```
Redis对象头：16字节
SDS头：3字节
字符串内容：44字节
'\0'结束符：1字节
总计：16 + 3 + 44 + 1 = 64字节

Redis内存分配器（jemalloc）的最小分配单位是64字节
所以44字节是最优选择（最大化利用64字节）
```

### 2.3 String常用命令

```bash
# 基本操作
SET key value                    # 设置值
GET key                          # 获取值
DEL key                          # 删除key
EXISTS key                       # 判断key是否存在
STRLEN key                       # 获取字符串长度

# 过期时间
SET key value EX 30              # 设置值，30秒过期
SETEX key 30 value               # 同上
TTL key                          # 查看剩余过期时间
EXPIRE key 30                    # 设置过期时间

# 原子操作
INCR key                         # 自增1
INCRBY key 10                    # 自增10
DECR key                         # 自减1
DECRBY key 10                    # 自减10

# 批量操作
MSET key1 value1 key2 value2     # 批量设置
MGET key1 key2                   # 批量获取

# 分布式锁
SET lock_key token NX EX 10      # SETNX + 过期时间（原子操作）
```

---

## 三、List：双向链表

### 3.1 List的应用场景

#### 场景1：消息队列

```java
/**
 * 生产者：发送消息到队列
 */
public void sendMessage(String message) {
    String queueKey = "queue:task";

    // LPUSH：从左侧插入（头部插入）
    redisTemplate.opsForList().leftPush(queueKey, message);
}

/**
 * 消费者：从队列获取消息
 */
public String consumeMessage() {
    String queueKey = "queue:task";

    // BRPOP：从右侧弹出（尾部弹出），阻塞等待
    // 如果队列为空，会阻塞直到有消息或超时
    List<String> result = redisTemplate.opsForList().rightPop(
        queueKey,
        10,  // 超时时间10秒
        TimeUnit.SECONDS
    );

    if (result == null || result.isEmpty()) {
        return null;
    }

    return result.get(1);  // result[0]是key，result[1]是value
}

/**
 * 多消费者并发消费
 */
@Component
public class MessageConsumer {

    @Autowired
    private RedisTemplate<String, String> redisTemplate;

    @Scheduled(fixedDelay = 1000)
    public void consumeTask() {
        while (true) {
            String message = consumeMessage();
            if (message == null) {
                break;  // 队列为空，退出
            }

            // 处理消息
            processMessage(message);
        }
    }

    private void processMessage(String message) {
        log.info("处理消息：{}", message);
        // 业务逻辑
    }
}
```

**List消息队列 vs RabbitMQ/Kafka**：

| 维度 | Redis List | RabbitMQ | Kafka |
|------|-----------|----------|-------|
| 性能 | 极高（10万QPS） | 高（1万QPS） | 极高（100万QPS） |
| 可靠性 | 低（无持久化保证） | 高（持久化） | 高（分区+副本） |
| 消息顺序 | FIFO | FIFO | 分区内FIFO |
| 消费模式 | 单消费者 | 多消费者 | 多消费者组 |
| 适用场景 | 轻量级队列 | 企业级消息队列 | 大数据流处理 |

**结论**：Redis List适合轻量级、高性能的消息队列；RabbitMQ/Kafka适合企业级、高可靠性的消息队列。

#### 场景2：最新列表（时间线）

```java
/**
 * 用户发布动态
 */
public void publishPost(Long userId, Post post) {
    // 1. 保存动态到数据库
    postRepository.save(post);

    // 2. 将动态ID推送到用户的时间线（List）
    String timelineKey = "timeline:user:" + userId;
    redisTemplate.opsForList().leftPush(timelineKey, post.getId().toString());

    // 3. 只保留最新100条动态（节省内存）
    redisTemplate.opsForList().trim(timelineKey, 0, 99);
}

/**
 * 获取用户时间线（最新动态列表）
 */
public List<PostVO> getTimeline(Long userId, int page, int pageSize) {
    String timelineKey = "timeline:user:" + userId;

    // 1. 从Redis获取动态ID列表（分页）
    int start = page * pageSize;
    int end = start + pageSize - 1;
    List<String> postIds = redisTemplate.opsForList().range(timelineKey, start, end);

    if (postIds == null || postIds.isEmpty()) {
        return Collections.emptyList();
    }

    // 2. 根据ID批量查询动态详情（可以从缓存或数据库）
    List<PostVO> posts = postIds.stream()
        .map(id -> getPostDetail(Long.parseLong(id)))
        .collect(Collectors.toList());

    return posts;
}
```

**为什么用List而不是直接查数据库？**

```sql
-- 数据库查询：每次都查数据库
SELECT * FROM post
WHERE user_id = 123
ORDER BY created_at DESC
LIMIT 0, 20;

-- 问题：
-- 1. 每次查询都走磁盘IO（10ms）
-- 2. ORDER BY需要排序（慢）
-- 3. 如果有100万条动态，查询会很慢

-- Redis List：
-- 1. 内存操作（1ms）
-- 2. 已经排序（LPUSH保证新动态在头部）
-- 3. 只存储最新100条（节省内存）

-- 性能提升：10倍
```

#### 场景3：限流（滑动窗口）

```java
/**
 * 限流：每分钟最多100次请求
 */
public boolean isAllowed(String userId) {
    String limitKey = "limit:user:" + userId;
    long now = System.currentTimeMillis();

    // 1. 记录当前请求时间
    redisTemplate.opsForList().leftPush(limitKey, String.valueOf(now));

    // 2. 删除1分钟之前的记录（滑动窗口）
    long oneMinuteAgo = now - 60000;
    redisTemplate.opsForList().trim(limitKey, 0, -1);  // 先保留所有

    // 使用Lua脚本删除过期数据
    String script =
        "local key = KEYS[1] " +
        "local now = tonumber(ARGV[1]) " +
        "local limit = tonumber(ARGV[2]) " +
        "local window = tonumber(ARGV[3]) " +
        "redis.call('LPUSH', key, now) " +
        "redis.call('LTRIM', key, 0, limit - 1) " +
        "local count = redis.call('LLEN', key) " +
        "if count <= limit then " +
        "    redis.call('EXPIRE', key, window) " +
        "    return 1 " +
        "else " +
        "    return 0 " +
        "end";

    Long result = redisTemplate.execute(
        new DefaultRedisScript<>(script, Long.class),
        Collections.singletonList(limitKey),
        String.valueOf(now),
        "100",  // 限制100次
        "60"    // 60秒
    );

    return result != null && result == 1;
}
```

### 3.2 List的底层实现

Redis List的底层实现经历了多次演进：

**Redis 3.2之前**：ziplist（压缩列表） + linkedlist（双向链表）

```
条件：
- 元素数量 < 512 → ziplist
- 元素数量 ≥ 512 → linkedlist
```

**Redis 3.2之后**：quicklist（快速列表）

```
quicklist = ziplist + linkedlist 的结合

结构：
  head → [ziplist1] ⇄ [ziplist2] ⇄ [ziplist3] ← tail
         (3个元素)    (5个元素)    (2个元素)

优势：
- 节省内存（ziplist压缩）
- 性能好（linkedlist快速插入删除）
```

**ziplist（压缩列表）**：

```
ziplist：连续内存块，节省内存

结构：
[zlbytes][zltail][zllen][entry1][entry2][..][zlend]

示例：
ziplist: [15][10][3][hello][world][redis][255]
         ↑   ↑   ↑   ↑
         总字节数 尾偏移 元素数 数据

优势：内存连续，缓存友好
劣势：插入删除需要移动数据（O(N)）
```

**linkedlist（双向链表）**：

```c
typedef struct listNode {
    struct listNode *prev;  // 前驱节点
    struct listNode *next;  // 后继节点
    void *value;            // 节点值
} listNode;

typedef struct list {
    listNode *head;  // 头节点
    listNode *tail;  // 尾节点
    unsigned long len;  // 节点数量
} list;

优势：插入删除O(1)
劣势：内存不连续，指针开销大
```

### 3.3 List常用命令

```bash
# 插入
LPUSH key value1 value2        # 从左侧插入
RPUSH key value1 value2        # 从右侧插入
LINSERT key BEFORE pivot value # 在pivot前插入

# 删除
LPOP key                       # 从左侧弹出
RPOP key                       # 从右侧弹出
LREM key count value           # 删除count个value
LTRIM key start stop           # 保留[start, stop]范围

# 查询
LRANGE key start stop          # 获取范围内的元素
LINDEX key index               # 获取索引位置的元素
LLEN key                       # 获取列表长度

# 阻塞操作（消息队列）
BLPOP key timeout              # 阻塞弹出（左侧）
BRPOP key timeout              # 阻塞弹出（右侧）
```

---

## 四、Hash：字段映射

### 4.1 Hash的应用场景

#### 场景1：对象存储

```java
/**
 * 存储用户对象（Hash）
 * 优势：可以单独更新某个字段，无需序列化整个对象
 */
public void saveUser(User user) {
    String userKey = "user:hash:" + user.getId();

    Map<String, String> userMap = new HashMap<>();
    userMap.put("id", user.getId().toString());
    userMap.put("name", user.getName());
    userMap.put("age", user.getAge().toString());
    userMap.put("email", user.getEmail());

    redisTemplate.opsForHash().putAll(userKey, userMap);
    redisTemplate.expire(userKey, 30, TimeUnit.MINUTES);
}

/**
 * 获取用户对象
 */
public User getUser(Long userId) {
    String userKey = "user:hash:" + userId;

    Map<Object, Object> userMap = redisTemplate.opsForHash().entries(userKey);
    if (userMap.isEmpty()) {
        return null;
    }

    User user = new User();
    user.setId(Long.parseLong((String) userMap.get("id")));
    user.setName((String) userMap.get("name"));
    user.setAge(Integer.parseInt((String) userMap.get("age")));
    user.setEmail((String) userMap.get("email"));

    return user;
}

/**
 * 只更新用户的年龄字段
 */
public void updateUserAge(Long userId, int age) {
    String userKey = "user:hash:" + userId;

    // 只更新age字段，无需序列化整个对象
    redisTemplate.opsForHash().put(userKey, "age", String.valueOf(age));
}
```

**Hash vs String对比**：

```java
// 方案1：String存储对象（JSON序列化）
User user = new User(1L, "Alice", 25, "alice@example.com");
String json = JSON.toJSONString(user);  // {"id":1,"name":"Alice","age":25,"email":"alice@example.com"}
redisTemplate.opsForValue().set("user:1", json);

// 更新age字段：需要反序列化→修改→序列化
String json = redisTemplate.opsForValue().get("user:1");
User user = JSON.parseObject(json, User.class);
user.setAge(26);
String newJson = JSON.toJSONString(user);
redisTemplate.opsForValue().set("user:1", newJson);

// 方案2：Hash存储对象
Map<String, String> userMap = new HashMap<>();
userMap.put("id", "1");
userMap.put("name", "Alice");
userMap.put("age", "25");
userMap.put("email", "alice@example.com");
redisTemplate.opsForHash().putAll("user:1", userMap);

// 更新age字段：直接更新，无需序列化
redisTemplate.opsForHash().put("user:1", "age", "26");

// 性能对比：
// String：反序列化(1ms) + 序列化(1ms) = 2ms
// Hash：直接更新 = 0.1ms
// 性能提升：20倍
```

#### 场景2：购物车

```java
/**
 * 添加商品到购物车
 */
public void addToCart(Long userId, Long productId, int quantity) {
    String cartKey = "cart:user:" + userId;

    // HINCRBY：如果商品已存在，增加数量；否则设置数量
    redisTemplate.opsForHash().increment(cartKey, productId.toString(), quantity);
}

/**
 * 获取购物车
 */
public Map<Long, Integer> getCart(Long userId) {
    String cartKey = "cart:user:" + userId;

    Map<Object, Object> cart = redisTemplate.opsForHash().entries(cartKey);

    Map<Long, Integer> result = new HashMap<>();
    for (Map.Entry<Object, Object> entry : cart.entrySet()) {
        Long productId = Long.parseLong((String) entry.getKey());
        Integer quantity = Integer.parseInt((String) entry.getValue());
        result.put(productId, quantity);
    }

    return result;
}

/**
 * 删除购物车中的商品
 */
public void removeFromCart(Long userId, Long productId) {
    String cartKey = "cart:user:" + userId;
    redisTemplate.opsForHash().delete(cartKey, productId.toString());
}

/**
 * 清空购物车
 */
public void clearCart(Long userId) {
    String cartKey = "cart:user:" + userId;
    redisTemplate.delete(cartKey);
}
```

**购物车的数据结构对比**：

```
方案1：String存储购物车（JSON）
{
  "cart:user:123": "{\"456\":2,\"789\":1}"
}
问题：
- 更新一个商品需要反序列化整个购物车
- 商品很多时，序列化/反序列化开销大

方案2：Hash存储购物车
{
  "cart:user:123": {
    "456": "2",  # 商品456，数量2
    "789": "1"   # 商品789，数量1
  }
}
优势：
- 可以单独更新某个商品的数量
- HINCRBY原子操作，并发安全
- 内存效率高
```

#### 场景3：统计信息

```java
/**
 * 统计网站访问量（按地区）
 */
public void recordVisit(String region) {
    String statsKey = "stats:visit:region";

    // HINCRBY：原子自增
    redisTemplate.opsForHash().increment(statsKey, region, 1);
}

/**
 * 获取各地区访问量
 */
public Map<String, Long> getVisitStats() {
    String statsKey = "stats:visit:region";

    Map<Object, Object> stats = redisTemplate.opsForHash().entries(statsKey);

    Map<String, Long> result = new HashMap<>();
    for (Map.Entry<Object, Object> entry : stats.entrySet()) {
        String region = (String) entry.getKey();
        Long count = Long.parseLong((String) entry.getValue());
        result.put(region, count);
    }

    return result;
}
```

### 4.2 Hash的底层实现

Redis Hash有两种底层实现：

**编码1：ziplist（压缩列表）**

```
条件：
- 所有键值对的键和值的字符串长度都 < 64字节
- 键值对数量 < 512

优势：内存占用小（连续内存）
劣势：查找是O(N)
```

**编码2：hashtable（哈希表）**

```c
typedef struct dict {
    dictType *type;       // 类型特定函数
    void *privdata;       // 私有数据
    dictht ht[2];         // 两个哈希表（用于渐进式rehash）
    long rehashidx;       // rehash进度（-1表示未rehash）
} dict;

typedef struct dictht {
    dictEntry **table;    // 哈希表数组
    unsigned long size;   // 哈希表大小
    unsigned long sizemask;  // 哈希表大小掩码（size-1）
    unsigned long used;   // 已有节点数量
} dictht;

typedef struct dictEntry {
    void *key;           // 键
    void *val;           // 值
    struct dictEntry *next;  // 下一个节点（链表法解决冲突）
} dictEntry;

优势：查找O(1)
劣势：内存占用大（指针开销）
```

**渐进式rehash**：

```
问题：当哈希表需要扩容时，一次性rehash会阻塞Redis

解决：渐进式rehash
1. 分配新哈希表（ht[1]）
2. 将rehashidx设置为0
3. 每次对Hash的操作（增删改查），顺带将ht[0].table[rehashidx]的所有键值对rehash到ht[1]
4. rehashidx++
5. 当ht[0]为空时，释放ht[0]，将ht[1]设置为ht[0]，创建新的空白ht[1]

优势：
- 避免阻塞Redis
- 渐进式完成rehash
```

### 4.3 Hash常用命令

```bash
# 设置
HSET key field value             # 设置单个字段
HMSET key field1 value1 field2 value2  # 设置多个字段
HSETNX key field value           # 字段不存在时设置

# 获取
HGET key field                   # 获取单个字段
HMGET key field1 field2          # 获取多个字段
HGETALL key                      # 获取所有字段和值
HKEYS key                        # 获取所有字段名
HVALS key                        # 获取所有值

# 删除
HDEL key field1 field2           # 删除字段

# 判断
HEXISTS key field                # 判断字段是否存在
HLEN key                         # 获取字段数量

# 原子操作
HINCRBY key field increment      # 原子自增
HINCRBYFLOAT key field increment # 浮点数自增
```

---

## 五、Set：无序集合

### 5.1 Set的应用场景

#### 场景1：标签系统

```java
/**
 * 给文章添加标签
 */
public void addTags(Long articleId, String... tags) {
    String tagKey = "article:tags:" + articleId;
    redisTemplate.opsForSet().add(tagKey, tags);
}

/**
 * 获取文章标签
 */
public Set<String> getTags(Long articleId) {
    String tagKey = "article:tags:" + articleId;
    return redisTemplate.opsForSet().members(tagKey);
}

/**
 * 获取两篇文章的共同标签
 */
public Set<String> getCommonTags(Long articleId1, Long articleId2) {
    String tagKey1 = "article:tags:" + articleId1;
    String tagKey2 = "article:tags:" + articleId2;

    // SINTER：交集
    return redisTemplate.opsForSet().intersect(tagKey1, tagKey2);
}

/**
 * 推荐相似文章（基于标签相似度）
 */
public List<Long> recommendSimilarArticles(Long articleId, int limit) {
    String tagKey = "article:tags:" + articleId;
    Set<String> tags = redisTemplate.opsForSet().members(tagKey);

    if (tags == null || tags.isEmpty()) {
        return Collections.emptyList();
    }

    // 统计每篇文章与当前文章的共同标签数
    Map<Long, Integer> similarityMap = new HashMap<>();

    for (String tag : tags) {
        // 获取有这个标签的所有文章
        String articlesByTagKey = "tag:articles:" + tag;
        Set<String> articleIds = redisTemplate.opsForSet().members(articlesByTagKey);

        if (articleIds != null) {
            for (String id : articleIds) {
                Long otherArticleId = Long.parseLong(id);
                if (!otherArticleId.equals(articleId)) {
                    similarityMap.put(otherArticleId, similarityMap.getOrDefault(otherArticleId, 0) + 1);
                }
            }
        }
    }

    // 按相似度排序，返回Top N
    return similarityMap.entrySet().stream()
        .sorted((a, b) -> b.getValue() - a.getValue())
        .limit(limit)
        .map(Map.Entry::getKey)
        .collect(Collectors.toList());
}
```

#### 场景2：共同好友

```java
/**
 * 添加好友
 */
public void addFriend(Long userId, Long friendId) {
    String friendKey = "user:friends:" + userId;
    redisTemplate.opsForSet().add(friendKey, friendId.toString());
}

/**
 * 获取共同好友
 */
public Set<Long> getCommonFriends(Long userId1, Long userId2) {
    String friendKey1 = "user:friends:" + userId1;
    String friendKey2 = "user:friends:" + userId2;

    // SINTER：交集
    Set<String> commonFriends = redisTemplate.opsForSet().intersect(friendKey1, friendKey2);

    if (commonFriends == null) {
        return Collections.emptySet();
    }

    return commonFriends.stream()
        .map(Long::parseLong)
        .collect(Collectors.toSet());
}

/**
 * 可能认识的人（好友的好友，但不是自己的好友）
 */
public Set<Long> getPeopleYouMayKnow(Long userId, int limit) {
    String friendKey = "user:friends:" + userId;
    Set<String> friends = redisTemplate.opsForSet().members(friendKey);

    if (friends == null || friends.isEmpty()) {
        return Collections.emptySet();
    }

    Set<Long> candidates = new HashSet<>();

    // 遍历每个好友
    for (String friendId : friends) {
        String friendOfFriendKey = "user:friends:" + friendId;
        Set<String> friendsOfFriend = redisTemplate.opsForSet().members(friendOfFriendKey);

        if (friendsOfFriend != null) {
            for (String fofId : friendsOfFriend) {
                Long fof = Long.parseLong(fofId);
                // 不是自己，也不是已经是好友的人
                if (!fof.equals(userId) && !friends.contains(fofId)) {
                    candidates.add(fof);
                }
            }
        }
    }

    return candidates.stream().limit(limit).collect(Collectors.toSet());
}
```

#### 场景3：抽奖系统

```java
/**
 * 参与抽奖
 */
public void participateInLottery(String lotteryId, Long userId) {
    String participantsKey = "lottery:participants:" + lotteryId;
    redisTemplate.opsForSet().add(participantsKey, userId.toString());
}

/**
 * 随机抽取N个中奖者
 */
public List<Long> drawWinners(String lotteryId, int count) {
    String participantsKey = "lottery:participants:" + lotteryId;

    // SRANDMEMBER：随机获取N个成员（不删除）
    List<String> winners = redisTemplate.opsForSet().randomMembers(participantsKey, count);

    if (winners == null) {
        return Collections.emptyList();
    }

    return winners.stream()
        .map(Long::parseLong)
        .collect(Collectors.toList());
}

/**
 * 抽取中奖者并移除（不能重复中奖）
 */
public List<Long> drawAndRemoveWinners(String lotteryId, int count) {
    String participantsKey = "lottery:participants:" + lotteryId;

    List<Long> winners = new ArrayList<>();

    for (int i = 0; i < count; i++) {
        // SPOP：随机弹出一个成员（删除）
        String winner = redisTemplate.opsForSet().pop(participantsKey);
        if (winner == null) {
            break;  // 参与者不足
        }
        winners.add(Long.parseLong(winner));
    }

    return winners;
}
```

### 5.2 Set的底层实现

Redis Set有两种底层实现：

**编码1：intset（整数集合）**

```
条件：
- 所有元素都是整数
- 元素数量 < 512

结构：
typedef struct intset {
    uint32_t encoding;  // 编码方式（int16_t、int32_t、int64_t）
    uint32_t length;    // 元素数量
    int8_t contents[];  // 数组（有序）
} intset;

示例：
intset: [2][5][1,3,5,7,9]
        ↑ ↑  ↑
     编码 长度 数据（有序）

优势：
- 内存占用小（连续内存，无指针）
- 有序（二分查找O(logN)）

劣势：
- 插入删除需要移动数据（O(N)）
- 只能存储整数
```

**编码2：hashtable（哈希表）**

```
条件：
- 元素不全是整数，或数量 ≥ 512

结构：同Hash的hashtable

优势：
- 插入删除查找都是O(1)
- 可以存储任意类型

劣势：
- 内存占用大（指针开销）
```

### 5.3 Set常用命令

```bash
# 添加/删除
SADD key member1 member2         # 添加成员
SREM key member1 member2         # 删除成员
SPOP key [count]                 # 随机弹出成员
SMOVE source dest member         # 移动成员

# 查询
SMEMBERS key                     # 获取所有成员
SISMEMBER key member             # 判断成员是否存在
SCARD key                        # 获取成员数量
SRANDMEMBER key [count]          # 随机获取成员（不删除）

# 集合运算
SINTER key1 key2                 # 交集
SUNION key1 key2                 # 并集
SDIFF key1 key2                  # 差集（在key1但不在key2）
SINTERSTORE dest key1 key2       # 交集存储到dest
```

---

## 六、ZSet：有序集合

### 6.1 ZSet的应用场景

#### 场景1：排行榜

```java
/**
 * 更新用户分数
 */
public void updateScore(Long userId, int score) {
    String rankKey = "rank:game:score";
    redisTemplate.opsForZSet().add(rankKey, userId.toString(), score);
}

/**
 * 获取排行榜（Top 10）
 */
public List<RankVO> getTopRank(int topN) {
    String rankKey = "rank:game:score";

    // ZREVRANGE：按分数降序获取（分数从高到低）
    Set<ZSetOperations.TypedTuple<String>> tuples =
        redisTemplate.opsForZSet().reverseRangeWithScores(rankKey, 0, topN - 1);

    if (tuples == null) {
        return Collections.emptyList();
    }

    List<RankVO> result = new ArrayList<>();
    int rank = 1;
    for (ZSetOperations.TypedTuple<String> tuple : tuples) {
        Long userId = Long.parseLong(tuple.getValue());
        Integer score = tuple.getScore().intValue();

        RankVO vo = new RankVO();
        vo.setRank(rank++);
        vo.setUserId(userId);
        vo.setScore(score);

        result.add(vo);
    }

    return result;
}

/**
 * 获取用户排名
 */
public Integer getUserRank(Long userId) {
    String rankKey = "rank:game:score";

    // ZREVRANK：获取用户排名（从0开始，所以要+1）
    Long rank = redisTemplate.opsForZSet().reverseRank(rankKey, userId.toString());

    return rank == null ? null : rank.intValue() + 1;
}

/**
 * 获取用户分数
 */
public Integer getUserScore(Long userId) {
    String rankKey = "rank:game:score";

    // ZSCORE：获取用户分数
    Double score = redisTemplate.opsForZSet().score(rankKey, userId.toString());

    return score == null ? null : score.intValue();
}
```

#### 场景2：延时队列

```java
/**
 * 添加延时任务
 */
public void addDelayedTask(String taskId, String taskData, long delaySeconds) {
    String queueKey = "queue:delayed";

    // 执行时间 = 当前时间 + 延时时间
    long executeTime = System.currentTimeMillis() + delaySeconds * 1000;

    // 使用执行时间作为score
    redisTemplate.opsForZSet().add(queueKey, taskData, executeTime);
}

/**
 * 消费延时任务（定时任务）
 */
@Scheduled(fixedDelay = 1000)
public void consumeDelayedTasks() {
    String queueKey = "queue:delayed";
    long now = System.currentTimeMillis();

    // ZRANGEBYSCORE：获取score <= now的任务（已到期的任务）
    Set<String> tasks = redisTemplate.opsForZSet().rangeByScore(queueKey, 0, now);

    if (tasks == null || tasks.isEmpty()) {
        return;
    }

    for (String task : tasks) {
        // 处理任务
        processTask(task);

        // 删除任务
        redisTemplate.opsForZSet().remove(queueKey, task);
    }
}
```

**延时队列的应用**：
- 订单超时自动取消（30分钟未支付）
- 定时提醒（提前1小时提醒会议）
- 延时重试（失败后5分钟重试）

#### 场景3：范围查询（时间范围、价格范围）

```java
/**
 * 按时间范围查询文章
 */
public List<Article> getArticlesByTimeRange(long startTime, long endTime) {
    String timelineKey = "articles:timeline";

    // ZRANGEBYSCORE：按分数范围查询
    Set<String> articleIds = redisTemplate.opsForZSet().rangeByScore(
        timelineKey,
        startTime,
        endTime
    );

    if (articleIds == null || articleIds.isEmpty()) {
        return Collections.emptyList();
    }

    return articleIds.stream()
        .map(id -> articleRepository.findById(Long.parseLong(id)))
        .collect(Collectors.toList());
}

/**
 * 按价格范围查询商品
 */
public List<Product> getProductsByPriceRange(double minPrice, double maxPrice) {
    String priceIndexKey = "products:price:index";

    // ZRANGEBYSCORE：按价格范围查询
    Set<String> productIds = redisTemplate.opsForZSet().rangeByScore(
        priceIndexKey,
        minPrice,
        maxPrice
    );

    if (productIds == null || productIds.isEmpty()) {
        return Collections.emptyList();
    }

    return productIds.stream()
        .map(id -> productRepository.findById(Long.parseLong(id)))
        .collect(Collectors.toList());
}
```

### 6.2 ZSet的底层实现

Redis ZSet有两种底层实现：

**编码1：ziplist（压缩列表）**

```
条件：
- 所有元素的长度 < 64字节
- 元素数量 < 128

结构：
ziplist: [member1][score1][member2][score2][...]

示例：
ziplist: [Alice][95][Bob][87][Charlie][92]

优势：内存占用小
劣势：查找O(N)，插入删除O(N)
```

**编码2：skiplist（跳表） + dict（哈希表）**

```
条件：
- 元素长度 ≥ 64字节，或元素数量 ≥ 128

为什么同时使用skiplist和dict？
- skiplist：实现范围查询（O(logN)）
- dict：实现O(1)查询member对应的score

结构：
typedef struct zset {
    dict *dict;       // 哈希表（member → score）
    zskiplist *zsl;   // 跳表（按score排序）
} zset;
```

**跳表（skiplist）原理**：

```
跳表：多层链表，每层都是有序的

示例：4层跳表
Level 4:  head ───────────────────────────────→ NULL
Level 3:  head ─────────→ 50 ─────────────────→ NULL
Level 2:  head ───→ 20 ──→ 50 ───→ 80 ────────→ NULL
Level 1:  head → 10 → 20 → 30 → 50 → 70 → 80 → 90 → NULL

查找80：
1. 从Level 4开始：head → NULL（跳过）
2. Level 3：head → 50（50 < 80，继续）→ NULL（下降）
3. Level 2：50 → 80（找到！）
4. 总比较次数：3次

如果是链表：需要比较7次

跳表特点：
- 平均查找/插入/删除：O(logN)
- 空间复杂度：O(N)
- 实现简单（相比红黑树）
```

### 6.3 ZSet常用命令

```bash
# 添加/删除
ZADD key score1 member1 score2 member2  # 添加成员
ZREM key member1 member2                # 删除成员
ZINCRBY key increment member            # 增加score

# 查询
ZRANGE key start stop [WITHSCORES]      # 按分数升序获取
ZREVRANGE key start stop [WITHSCORES]   # 按分数降序获取
ZRANGEBYSCORE key min max               # 按分数范围查询
ZRANK key member                        # 获取排名（升序）
ZREVRANK key member                     # 获取排名（降序）
ZSCORE key member                       # 获取分数
ZCARD key                               # 获取成员数量

# 集合运算
ZUNIONSTORE dest numkeys key1 key2      # 并集
ZINTERSTORE dest numkeys key1 key2      # 交集
```

---

## 七、性能对比与选型建议

### 7.1 五大数据结构性能对比

| 数据结构 | 查找 | 插入 | 删除 | 范围查询 | 排序 | 内存占用 |
|---------|-----|-----|-----|---------|-----|---------|
| String | O(1) | O(1) | O(1) | ❌ | ❌ | 低 |
| List | O(N) | O(1) | O(N) | O(N) | ❌ | 中 |
| Hash | O(1) | O(1) | O(1) | ❌ | ❌ | 中 |
| Set | O(1) | O(1) | O(1) | ❌ | ❌ | 中 |
| ZSet | O(logN) | O(logN) | O(logN) | O(logN) | ✅ | 高 |

### 7.2 数据结构选型决策树

```
需要排序？
├─ 是 → ZSet（排行榜、延时队列）
└─ 否 → 需要去重？
        ├─ 是 → Set（标签、抽奖）
        └─ 否 → 需要保持顺序？
                ├─ 是 → List（消息队列、时间线）
                └─ 否 → 需要字段映射？
                        ├─ 是 → Hash（对象存储、购物车）
                        └─ 否 → String（简单KV）
```

### 7.3 常见场景推荐

| 场景 | 推荐数据结构 | 理由 |
|------|------------|------|
| Session共享 | String | 简单高效 |
| 计数器 | String（INCR） | 原子操作 |
| 分布式锁 | String（SETNX） | 原子操作 |
| 消息队列 | List（LPUSH+BRPOP） | FIFO |
| 最新列表 | List | 保持顺序 |
| 对象存储 | Hash | 字段独立更新 |
| 购物车 | Hash | HINCRBY原子操作 |
| 标签系统 | Set | 去重+集合运算 |
| 共同好友 | Set（SINTER） | 交集运算 |
| 抽奖 | Set（SPOP） | 随机弹出 |
| 排行榜 | ZSet | 自动排序 |
| 延时队列 | ZSet | 按时间排序 |
| 范围查询 | ZSet（ZRANGEBYSCORE） | 范围查询 |

---

## 八、最佳实践

### 8.1 内存优化

**1. 使用合适的数据结构**

```java
// ❌ 错误：用String存储对象（内存浪费）
User user = new User(1L, "Alice", 25);
String json = JSON.toJSONString(user);  // {"id":1,"name":"Alice","age":25}
redisTemplate.opsForValue().set("user:1", json);  // 45字节

// ✅ 正确：用Hash存储对象（节省内存）
Map<String, String> userMap = new HashMap<>();
userMap.put("id", "1");        // 7字节
userMap.put("name", "Alice");  // 10字节
userMap.put("age", "25");      // 7字节
redisTemplate.opsForHash().putAll("user:1", userMap);  // 24字节

// 节省：45 - 24 = 21字节（47%）
```

**2. 控制集合大小**

```java
// ❌ 错误：List无限增长
redisTemplate.opsForList().leftPush("timeline:user:123", postId);

// ✅ 正确：只保留最新100条
redisTemplate.opsForList().leftPush("timeline:user:123", postId);
redisTemplate.opsForList().trim("timeline:user:123", 0, 99);
```

**3. 设置过期时间**

```java
// ❌ 错误：不设置过期时间（内存泄漏）
redisTemplate.opsForValue().set("session:" + token, user);

// ✅ 正确：设置过期时间
redisTemplate.opsForValue().set("session:" + token, user, 30, TimeUnit.MINUTES);
```

### 8.2 性能优化

**1. 批量操作**

```java
// ❌ 错误：循环执行单个命令（N次网络往返）
for (int i = 0; i < 1000; i++) {
    redisTemplate.opsForValue().set("key" + i, "value" + i);
}

// ✅ 正确：使用Pipeline（1次网络往返）
redisTemplate.executePipelined((RedisCallback<Object>) connection -> {
    for (int i = 0; i < 1000; i++) {
        connection.set(("key" + i).getBytes(), ("value" + i).getBytes());
    }
    return null;
});

// 性能提升：100倍
```

**2. 避免大Key**

```java
// ❌ 错误：List存储100万个元素（大Key）
for (int i = 0; i < 1000000; i++) {
    redisTemplate.opsForList().rightPush("big:list", "item" + i);
}

// ✅ 正确：拆分成多个小List
for (int i = 0; i < 1000; i++) {
    String listKey = "list:part:" + i;
    for (int j = 0; j < 1000; j++) {
        redisTemplate.opsForList().rightPush(listKey, "item" + (i * 1000 + j));
    }
}
```

**3. 使用合适的命令**

```java
// ❌ 错误：使用KEYS命令（阻塞Redis）
Set<String> keys = redisTemplate.keys("user:*");  // 扫描所有key

// ✅ 正确：使用SCAN命令（不阻塞）
ScanOptions options = ScanOptions.scanOptions().match("user:*").count(100).build();
Cursor<byte[]> cursor = redisTemplate.executeWithStickyConnection(
    connection -> connection.scan(options)
);

while (cursor.hasNext()) {
    String key = new String(cursor.next());
    // 处理key
}
```

### 8.3 安全建议

**1. 避免Key冲突**

```java
// ❌ 错误：key太短，容易冲突
redisTemplate.opsForValue().set("123", user);

// ✅ 正确：带业务前缀
redisTemplate.opsForValue().set("user:info:123", user);
```

**2. 设置maxmemory**

```bash
# redis.conf
maxmemory 2gb
maxmemory-policy allkeys-lru
```

**3. 监控慢查询**

```bash
# 查看慢查询
127.0.0.1:6379> SLOWLOG GET 10

# 配置慢查询阈值（10ms）
slowlog-log-slower-than 10000
slowlog-max-len 128
```

---

## 九、总结

### 9.1 核心要点回顾

**五大数据结构的本质**：

```
String：   KV存储，万能但不高效
List：     有序列表，适合队列和时间线
Hash：     字段映射，适合对象存储
Set：      无序集合，适合去重和集合运算
ZSet：     有序集合，适合排序和范围查询
```

**底层实现总结**：

| 数据结构 | 小对象编码 | 大对象编码 | 阈值 |
|---------|-----------|-----------|------|
| String | int/embstr | raw | 44字节 |
| List | ziplist → quicklist | - | - |
| Hash | ziplist | hashtable | 512个/64字节 |
| Set | intset | hashtable | 512个/整数 |
| ZSet | ziplist | skiplist+dict | 128个/64字节 |

**性能特点**：

```
时间复杂度：
String/Hash/Set：O(1)
List：O(N)
ZSet：O(logN)

空间复杂度：
String < Hash < Set < List < ZSet
```

### 9.2 下一步学习

本文是Redis系列的第3篇，后续文章将深入讲解：

1. ✅ Redis第一性原理：为什么我们需要缓存？
2. ✅ 从HashMap到Redis：分布式缓存的演进
3. ✅ **Redis五大数据结构：从场景到实现**
4. ⏳ Redis高可用架构：主从复制、哨兵、集群
5. ⏳ Redis持久化：RDB与AOF的权衡
6. ⏳ Redis实战：分布式锁、消息队列、缓存设计

---

**参考资料**：
- 《Redis设计与实现》- 黄健宏
- 《Redis实战》- Josiah L. Carlson
- Redis官方文档：https://redis.io/documentation
- Redis命令参考：https://redis.io/commands

---

*本文是"Redis第一性原理"系列的第3篇，共6篇。下一篇将深入讲解《Redis高可用架构：主从复制、哨兵、集群》，敬请期待。*
