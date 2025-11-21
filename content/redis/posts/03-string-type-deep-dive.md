---
title: "String类型深度解析：最简单也最强大"
date: 2025-01-21T11:00:00+08:00
draft: false
tags: ["Redis", "String", "数据结构", "SDS"]
categories: ["技术"]
description: "Redis的String类型不只是简单的字符串，它可以存储任何二进制数据，支持计数、位操作等强大功能。深入理解String的底层实现和应用场景。"
weight: 3
stage: 1
stageTitle: "基础入门篇"
---

## 引言

在Redis的五大基础数据类型中，String是最基础、最常用的一种。据统计，在实际生产环境中，**80%以上的Redis键都是String类型**。

但String远不止"字符串"这么简单。它可以：
- 存储任意二进制数据（文本、数字、图片、序列化对象）
- 作为计数器（原子性递增/递减）
- 实现分布式锁
- 存储位图数据

今天我们从第一性原理出发，理解String的本质和强大之处。

## 一、String的本质

### 1.1 不只是字符串

在Redis中，String类型的"String"是一个容易误导人的名字。它实际上是：

**二进制安全的字节数组（Binary Safe Byte Array）**

这意味着：
- ✅ 可以存储文本："hello world"
- ✅ 可以存储数字：123456
- ✅ 可以存储JSON：`{"name":"Redis"}`
- ✅ 可以存储序列化对象：Java对象、Protobuf
- ✅ 可以存储二进制数据：图片、音频（理论上，但不推荐）

### 1.2 底层实现：SDS

Redis使用自己实现的**简单动态字符串（Simple Dynamic String, SDS）**，而不是C语言原生的字符串。

**C字符串的问题**：

```c
char* str = "hello";
// 问题1：获取长度需要遍历，O(n)
int len = strlen(str);

// 问题2：不是二进制安全，遇到\0就截断
char* binary = "hello\0world";  // 只能读到"hello"

// 问题3：缓冲区溢出风险
strcat(str, " world");  // 可能溢出
```

**SDS的优势**：

```c
struct sdshdr {
    int len;        // 已使用长度
    int free;       // 剩余可用空间
    char buf[];     // 实际存储的字节数组
};
```

优势：
1. **O(1)时间获取长度**：直接读取len字段
2. **二进制安全**：不依赖`\0`判断结束
3. **预分配空间**：减少内存分配次数
4. **惰性释放**：空间不立即释放，可重用

### 1.3 内存占用

一个简单的String在Redis中的内存占用：

```
键：user:1001
值：张三

实际内存占用 ≈ 96字节
- RedisObject对象头：16字节
- SDS结构体：8字节（len + free）
- 键字符串：9字节（"user:1001"）
- 值字符串：6字节（"张三"的UTF-8编码）
- 指针和对齐：若干字节
```

## 二、String命令全解析

### 2.1 基础读写

**SET - 设置键值**

```bash
# 基本语法
SET key value [EX seconds] [PX milliseconds] [NX|XX]

# 示例1：简单设置
127.0.0.1:6379> SET name "Redis"
OK

# 示例2：设置并指定过期时间（秒）
127.0.0.1:6379> SET session:abc123 "user:1001" EX 3600
OK

# 示例3：设置并指定过期时间（毫秒）
127.0.0.1:6379> SET cache:hot "data" PX 5000
OK

# 示例4：仅当键不存在时设置（NX = Not eXists）
127.0.0.1:6379> SET lock:resource "token123" NX EX 30
OK  # 第一次成功
127.0.0.1:6379> SET lock:resource "token456" NX EX 30
(nil)  # 已存在，设置失败

# 示例5：仅当键存在时设置（XX = eXists）
127.0.0.1:6379> SET config:max_conn "1000" XX
(nil)  # 不存在，设置失败
```

**GET - 获取键值**

```bash
127.0.0.1:6379> GET name
"Redis"

127.0.0.1:6379> GET notexist
(nil)
```

**SETEX/SETNX - 快捷命令**

```bash
# SETEX = SET + EX
127.0.0.1:6379> SETEX cache:user 60 "userdata"
OK
# 等价于：SET cache:user "userdata" EX 60

# SETNX = SET + NX
127.0.0.1:6379> SETNX lock:order "locked"
(integer) 1  # 成功
127.0.0.1:6379> SETNX lock:order "locked"
(integer) 0  # 失败，已存在
```

### 2.2 批量操作

**MSET/MGET - 批量读写**

```bash
# 批量设置（原子操作）
127.0.0.1:6379> MSET key1 "value1" key2 "value2" key3 "value3"
OK

# 批量获取
127.0.0.1:6379> MGET key1 key2 key3
1) "value1"
2) "value2"
3) "value3"

# 批量获取不存在的键
127.0.0.1:6379> MGET key1 notexist key3
1) "value1"
2) (nil)
3) "value3"
```

**性能对比**：

```bash
# 单条命令：100次SET，网络RTT = 1ms
100次 × 1ms = 100ms

# 批量命令：1次MSET（100个键值对）
1次 × 1ms = 1ms

性能提升：100倍！
```

### 2.3 字符串操作

**APPEND - 追加字符串**

```bash
127.0.0.1:6379> SET msg "Hello"
OK

127.0.0.1:6379> APPEND msg " World"
(integer) 11  # 返回追加后的长度

127.0.0.1:6379> GET msg
"Hello World"
```

**STRLEN - 获取长度**

```bash
127.0.0.1:6379> STRLEN msg
(integer) 11

# 注意：中文字符按UTF-8编码计算
127.0.0.1:6379> SET name "张三"
OK
127.0.0.1:6379> STRLEN name
(integer) 6  # "张三"占6字节（每个汉字3字节）
```

**GETRANGE/SETRANGE - 字符串切片**

```bash
127.0.0.1:6379> SET text "Hello Redis"
OK

# 获取子串（索引从0开始）
127.0.0.1:6379> GETRANGE text 0 4
"Hello"

127.0.0.1:6379> GETRANGE text 6 -1
"Redis"  # -1表示到末尾

# 替换子串
127.0.0.1:6379> SETRANGE text 6 "World"
(integer) 11

127.0.0.1:6379> GET text
"Hello World"
```

### 2.4 数值操作（重要！）

**INCR/DECR - 递增/递减**

```bash
# 初始化计数器
127.0.0.1:6379> SET counter 0
OK

# 递增（+1）
127.0.0.1:6379> INCR counter
(integer) 1

127.0.0.1:6379> INCR counter
(integer) 2

# 递减（-1）
127.0.0.1:6379> DECR counter
(integer) 1

# 如果键不存在，从0开始
127.0.0.1:6379> INCR newcounter
(integer) 1
```

**INCRBY/DECRBY - 指定增量**

```bash
127.0.0.1:6379> SET score 100
OK

127.0.0.1:6379> INCRBY score 50
(integer) 150

127.0.0.1:6379> DECRBY score 30
(integer) 120
```

**INCRBYFLOAT - 浮点数递增**

```bash
127.0.0.1:6379> SET price 99.99
OK

127.0.0.1:6379> INCRBYFLOAT price 10.01
"110"

127.0.0.1:6379> INCRBYFLOAT price -5.5
"104.5"
```

**原子性保证**：

```bash
# 场景：秒杀库存扣减
# 10000个并发请求同时执行 DECR stock
# Redis保证每次操作都是原子的，不会出现超卖
127.0.0.1:6379> SET stock 100
OK

127.0.0.1:6379> DECR stock  # 原子操作
(integer) 99
```

## 三、实战场景

### 场景1：缓存对象

**JSON序列化存储**

```java
// 存储用户对象
public void cacheUser(User user) {
    String key = "user:" + user.getId();
    String json = JSON.toJSONString(user);
    redis.setex(key, 3600, json);  // 缓存1小时
}

// 获取用户对象
public User getUser(Long userId) {
    String key = "user:" + userId;
    String json = redis.get(key);
    if (json != null) {
        return JSON.parseObject(json, User.class);
    }

    // 缓存未命中，查询数据库
    User user = userDao.selectById(userId);
    if (user != null) {
        cacheUser(user);
    }
    return user;
}
```

**序列化对象存储**

```java
// 使用Java序列化
public void cacheObject(String key, Object obj, int seconds) {
    RedisTemplate<String, Object> redis = ...;
    redis.opsForValue().set(key, obj, seconds, TimeUnit.SECONDS);
}
```

### 场景2：计数器

**文章浏览量**

```java
// 浏览量+1
public void incrPageView(Long articleId) {
    String key = "article:pv:" + articleId;
    redis.incr(key);
}

// 获取浏览量
public Long getPageView(Long articleId) {
    String key = "article:pv:" + articleId;
    String pv = redis.get(key);
    return pv != null ? Long.valueOf(pv) : 0L;
}
```

**点赞计数**

```java
// 点赞
public void like(Long postId, Long userId) {
    String likeKey = "post:like:" + postId;
    String userKey = "post:like:user:" + postId + ":" + userId;

    // 检查是否已点赞
    if (redis.exists(userKey)) {
        return;
    }

    // 计数+1，并记录用户
    redis.incr(likeKey);
    redis.setex(userKey, 86400, "1");  // 24小时有效
}
```

**API限流**

```java
// 限流：每分钟最多100次请求
public boolean isAllowed(String userId) {
    String key = "rate:limit:" + userId + ":" +
                 (System.currentTimeMillis() / 60000);  // 按分钟

    Long count = redis.incr(key);
    if (count == 1) {
        redis.expire(key, 60);  // 设置过期时间
    }

    return count <= 100;
}
```

### 场景3：分布式锁

**简单分布式锁**

```java
// 加锁
public boolean tryLock(String lockKey, String requestId, int expireTime) {
    // NX：不存在才设置；EX：设置过期时间
    String result = redis.set(lockKey, requestId, "NX", "EX", expireTime);
    return "OK".equals(result);
}

// 解锁（使用Lua脚本保证原子性）
public boolean unlock(String lockKey, String requestId) {
    String script =
        "if redis.call('get', KEYS[1]) == ARGV[1] then " +
        "  return redis.call('del', KEYS[1]) " +
        "else " +
        "  return 0 " +
        "end";

    Object result = redis.eval(script,
                                Collections.singletonList(lockKey),
                                Collections.singletonList(requestId));
    return Long.valueOf(1).equals(result);
}

// 使用示例
public void processOrder(Long orderId) {
    String lockKey = "lock:order:" + orderId;
    String requestId = UUID.randomUUID().toString();

    // 尝试加锁，30秒超时
    if (tryLock(lockKey, requestId, 30)) {
        try {
            // 业务逻辑
            doProcessOrder(orderId);
        } finally {
            // 释放锁
            unlock(lockKey, requestId);
        }
    } else {
        throw new RuntimeException("获取锁失败");
    }
}
```

### 场景4：会话存储（Session）

**用户登录态**

```java
// 用户登录
public String login(String username, String password) {
    // 验证用户名密码
    User user = authenticate(username, password);
    if (user == null) {
        return null;
    }

    // 生成token
    String token = UUID.randomUUID().toString();
    String key = "session:" + token;

    // 存储会话信息，30分钟有效
    Map<String, String> session = new HashMap<>();
    session.put("userId", String.valueOf(user.getId()));
    session.put("username", user.getUsername());

    redis.setex(key, 1800, JSON.toJSONString(session));

    return token;
}

// 验证登录态
public User getLoginUser(String token) {
    String key = "session:" + token;
    String sessionJson = redis.get(key);

    if (sessionJson == null) {
        return null;  // 未登录或已过期
    }

    // 续期：刷新过期时间
    redis.expire(key, 1800);

    // 解析session
    Map<String, String> session = JSON.parseObject(sessionJson, Map.class);
    Long userId = Long.valueOf(session.get("userId"));

    return userDao.selectById(userId);
}

// 退出登录
public void logout(String token) {
    String key = "session:" + token;
    redis.del(key);
}
```

### 场景5：验证码

**短信验证码**

```java
// 发送验证码
public boolean sendSmsCode(String mobile) {
    String key = "sms:code:" + mobile;

    // 检查是否60秒内已发送
    if (redis.exists(key)) {
        Long ttl = redis.ttl(key);
        if (ttl > 240) {  // 5分钟-240秒=60秒
            return false;  // 60秒内不能重复发送
        }
    }

    // 生成6位验证码
    String code = String.format("%06d", new Random().nextInt(1000000));

    // 存储验证码，5分钟有效
    redis.setex(key, 300, code);

    // 调用短信服务发送
    smsService.send(mobile, code);

    return true;
}

// 验证验证码
public boolean verifySmsCode(String mobile, String code) {
    String key = "sms:code:" + mobile;
    String storedCode = redis.get(key);

    if (storedCode == null) {
        return false;  // 验证码不存在或已过期
    }

    if (storedCode.equals(code)) {
        redis.del(key);  // 验证成功后删除
        return true;
    }

    return false;
}
```

## 四、最佳实践

### 4.1 键命名规范

✅ **推荐**：

```bash
# 使用冒号分隔，层级清晰
user:1001
user:1001:profile
user:1001:cart

# 业务域前缀
order:123456
product:sku:888888

# 加上类型标识
cache:product:1001
lock:order:123
counter:pv:article:888
```

❌ **不推荐**：

```bash
# 无规则，难以管理
u1001
user_profile_1001
OrderLock123
```

### 4.2 值大小控制

**建议**：
- 单个String值 < 1MB
- 最好 < 100KB
- 超过10MB会导致性能问题

**大对象处理**：

```java
// ❌ 不推荐：存储大对象
redis.set("user:1001:detail", largeJsonString);  // 5MB

// ✅ 推荐：拆分存储
redis.hset("user:1001", "basic", basicInfo);      // 1KB
redis.hset("user:1001", "address", addressInfo);  // 2KB
redis.hset("user:1001", "orders", orderSummary);  // 3KB
```

### 4.3 过期时间设置

**必须设置过期时间的场景**：
- 缓存数据（防止内存泄漏）
- 会话数据（Session）
- 临时数据（验证码、Token）

**不设置过期时间的场景**：
- 持久化数据（计数器、配置）
- 需要手动删除的数据

**过期时间抖动**：

```java
// ❌ 不推荐：固定过期时间，可能导致缓存雪崩
redis.setex(key, 3600, value);

// ✅ 推荐：添加随机抖动（±10%）
int expire = 3600 + new Random().nextInt(720) - 360;
redis.setex(key, expire, value);
```

### 4.4 性能优化技巧

**使用批量命令**：

```java
// ❌ 慢：N次网络往返
for (int i = 0; i < 1000; i++) {
    redis.get("key" + i);
}

// ✅ 快：1次网络往返
List<String> keys = ...;
List<String> values = redis.mget(keys);
```

**使用Pipeline**：

```java
// 批量操作
Pipeline pipeline = redis.pipelined();
for (int i = 0; i < 1000; i++) {
    pipeline.set("key" + i, "value" + i);
}
pipeline.sync();
```

## 五、常见问题

### Q1: String存储数字 vs 存储字符串

```bash
# 存储数字（整型编码）
127.0.0.1:6379> SET num 123
OK
127.0.0.1:6379> OBJECT ENCODING num
"int"  # 内部用long存储，省内存

# 存储字符串
127.0.0.1:6379> SET str "123"
OK
127.0.0.1:6379> OBJECT ENCODING str
"embstr"  # SDS存储
```

**结论**：存储纯数字时，Redis自动优化为整型编码，更省内存。

### Q2: INCR操作的值不是数字会怎样？

```bash
127.0.0.1:6379> SET name "Redis"
OK

127.0.0.1:6379> INCR name
(error) ERR value is not an integer or out of range
```

**结论**：INCR只能操作数字，否则报错。

### Q3: SET与SETNX的区别

- **SET**：总是成功，覆盖已存在的键
- **SETNX**：仅当键不存在时才成功（分布式锁的基础）

```bash
127.0.0.1:6379> SET key "value1"
OK
127.0.0.1:6379> SET key "value2"
OK  # 覆盖成功

127.0.0.1:6379> SETNX key2 "value1"
(integer) 1  # 成功
127.0.0.1:6379> SETNX key2 "value2"
(integer) 0  # 失败，已存在
```

## 六、总结

### 核心要点

1. **String的本质**：二进制安全的字节数组，可存储任意数据
2. **底层实现**：SDS（简单动态字符串），O(1)获取长度，预分配空间
3. **常用命令**：SET/GET/MSET/MGET/INCR/DECR/SETEX/SETNX
4. **原子性保证**：INCR/DECR是原子操作，并发安全
5. **实战场景**：缓存、计数器、分布式锁、会话、验证码

### 命令速查表

| 命令 | 作用 | 时间复杂度 |
|------|------|-----------|
| SET | 设置键值 | O(1) |
| GET | 获取键值 | O(1) |
| MSET | 批量设置 | O(N) |
| MGET | 批量获取 | O(N) |
| INCR | 递增 | O(1) |
| DECR | 递减 | O(1) |
| APPEND | 追加 | O(1) |
| STRLEN | 获取长度 | O(1) |

### 下一步

掌握了String类型后，下一篇我们将学习**Hash类型**：
- 如何存储对象的多个字段
- Hash vs String的选择
- 购物车实战案例

---

**思考题**：
1. 为什么INCR/DECR是原子操作，而GET+计算+SET不是？
2. 什么情况下用Hash存储对象，什么情况下用String存储JSON？
3. 如何实现一个支持过期时间的分布式锁？

下一篇见！
