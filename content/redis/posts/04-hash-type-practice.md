---
title: "Hash类型实战：对象存储的最佳选择"
date: 2025-01-21T11:30:00+08:00
draft: false
tags: ["Redis", "Hash", "对象存储", "数据结构"]
categories: ["技术"]
description: "Hash是Redis中存储对象的利器。相比String存储JSON，Hash可以单独修改对象的某个字段，节省内存并提升性能。深入理解Hash的原理和应用。"
weight: 4
stage: 1
stageTitle: "基础入门篇"
---

## 引言

上一篇我们学习了String类型，可以用JSON序列化存储对象。但是有一个问题：

**如果只想修改用户的一个字段（比如年龄），需要怎么做？**

```java
// String方式：读取→反序列化→修改→序列化→写入
String json = redis.get("user:1001");
User user = JSON.parseObject(json, User.class);
user.setAge(26);  // 只改了年龄
redis.set("user:1001", JSON.toJSONString(user));
```

这样做有几个问题：
- ❌ 需要整个对象序列化/反序列化
- ❌ 网络传输整个对象（浪费带宽）
- ❌ 并发修改容易出现覆盖问题

**Hash类型就是为了解决这个问题而生的。**

## 一、Hash的本质

### 1.1 什么是Hash？

Hash就是一个**键值对集合**（类似Java的HashMap、Python的dict）：

```
Hash对象
├── field1: value1
├── field2: value2
└── field3: value3
```

在Redis中：
- **外层键（Key）**：对象的唯一标识
- **内层字段（Field）**：对象的属性名
- **值（Value）**：属性值

**示例**：

```bash
# 用户对象
user:1001
├── name: "张三"
├── age: "25"
├── email: "zhangsan@example.com"
└── city: "北京"
```

### 1.2 Hash vs String

| 维度 | String (JSON) | Hash |
|------|--------------|------|
| **存储方式** | 整个对象序列化为JSON | 每个字段单独存储 |
| **修改单个字段** | 需要整体读写 | 直接修改该字段 |
| **内存占用** | 略高（JSON格式化） | 略低（原生存储） |
| **可读性** | 好（JSON可读） | 一般（需遍历） |
| **性能** | 读写整个对象 | 按需读写字段 |
| **适用场景** | 整体读写 | 频繁修改部分字段 |

**选择原则**：
- ✅ **用Hash**：对象字段固定、经常修改部分字段
- ✅ **用String**：对象整体读写、字段不固定、需要序列化

### 1.3 底层实现

Hash有两种底层编码方式：

**1. ziplist（压缩列表）** - 省内存

条件：
- 字段数量 < `hash-max-ziplist-entries`（默认512）
- 所有value长度 < `hash-max-ziplist-value`（默认64字节）

特点：
- 内存紧凑，占用小
- 查询略慢（O(n)）

**2. hashtable（哈希表）** - 高性能

条件：
- 不满足ziplist条件时自动转换

特点：
- 查询快（O(1)）
- 内存占用较大

**查看编码方式**：

```bash
127.0.0.1:6379> HSET user:1001 name "张三" age "25"
(integer) 2

127.0.0.1:6379> OBJECT ENCODING user:1001
"ziplist"  # 小对象用ziplist

# 添加大量字段后
127.0.0.1:6379> OBJECT ENCODING user:1001
"hashtable"  # 自动转换
```

## 二、Hash命令全解析

### 2.1 基础读写

**HSET/HGET - 设置/获取单个字段**

```bash
# 设置单个字段
127.0.0.1:6379> HSET user:1001 name "张三"
(integer) 1  # 返回新增的字段数

# 获取单个字段
127.0.0.1:6379> HGET user:1001 name
"张三"

# 设置多个字段（Redis 4.0+）
127.0.0.1:6379> HSET user:1001 age "25" city "北京" email "zhangsan@example.com"
(integer) 3

# 获取不存在的字段
127.0.0.1:6379> HGET user:1001 phone
(nil)
```

**HMSET/HMGET - 批量设置/获取**

```bash
# 批量设置（兼容旧版本）
127.0.0.1:6379> HMSET user:1002 name "李四" age "30" city "上海"
OK

# 批量获取
127.0.0.1:6379> HMGET user:1002 name age city
1) "李四"
2) "30"
3) "上海"

# 获取不存在的字段返回nil
127.0.0.1:6379> HMGET user:1002 name phone email
1) "李四"
2) (nil)
3) (nil)
```

**HGETALL - 获取所有字段**

```bash
127.0.0.1:6379> HGETALL user:1001
1) "name"
2) "张三"
3) "age"
4) "25"
5) "city"
6) "北京"
7) "email"
8) "zhangsan@example.com"

# 返回格式：field1, value1, field2, value2, ...
```

⚠️ **注意**：HGETALL会返回所有字段，大对象慎用（可能阻塞）！

### 2.2 字段操作

**HEXISTS - 检查字段是否存在**

```bash
127.0.0.1:6379> HEXISTS user:1001 name
(integer) 1  # 存在

127.0.0.1:6379> HEXISTS user:1001 phone
(integer) 0  # 不存在
```

**HDEL - 删除字段**

```bash
127.0.0.1:6379> HDEL user:1001 email
(integer) 1  # 返回删除的字段数

# 批量删除
127.0.0.1:6379> HDEL user:1001 city age
(integer) 2
```

**HKEYS/HVALS - 获取所有字段名/值**

```bash
# 获取所有字段名
127.0.0.1:6379> HKEYS user:1001
1) "name"
2) "age"
3) "city"

# 获取所有字段值
127.0.0.1:6379> HVALS user:1001
1) "张三"
2) "25"
3) "北京"
```

**HLEN - 获取字段数量**

```bash
127.0.0.1:6379> HLEN user:1001
(integer) 3
```

### 2.3 数值操作

**HINCRBY - 整数递增**

```bash
127.0.0.1:6379> HSET product:1001 stock 100
(integer) 1

127.0.0.1:6379> HINCRBY product:1001 stock -1
(integer) 99  # 库存-1

127.0.0.1:6379> HINCRBY product:1001 sales 1
(integer) 1  # 销量+1（字段不存在时从0开始）
```

**HINCRBYFLOAT - 浮点数递增**

```bash
127.0.0.1:6379> HSET product:1001 price 99.99
(integer) 1

127.0.0.1:6379> HINCRBYFLOAT product:1001 price 10.01
"110"

127.0.0.1:6379> HINCRBYFLOAT product:1001 price -5.5
"104.5"
```

### 2.4 高级命令

**HSETNX - 仅当字段不存在时设置**

```bash
127.0.0.1:6379> HSETNX user:1001 name "王五"
(integer) 0  # 失败，字段已存在

127.0.0.1:6379> HSETNX user:1001 phone "13800138000"
(integer) 1  # 成功，字段不存在
```

**HSCAN - 迭代字段（生产环境推荐）**

```bash
# 类似KEYS，但不会阻塞
127.0.0.1:6379> HSCAN user:1001 0
1) "0"  # 下次迭代的游标（0表示结束）
2) 1) "name"
   2) "张三"
   3) "age"
   4) "25"
   5) "city"
   6) "北京"
```

## 三、实战场景

### 场景1：用户信息存储

**String方式 vs Hash方式**

```java
// ❌ String方式：整体读写
public class UserServiceString {
    public void updateAge(Long userId, int age) {
        String key = "user:" + userId;

        // 1. 读取整个对象
        String json = redis.get(key);
        User user = JSON.parseObject(json, User.class);

        // 2. 修改年龄
        user.setAge(age);

        // 3. 写回整个对象
        redis.setex(key, 3600, JSON.toJSONString(user));
    }
}

// ✅ Hash方式：单字段操作
public class UserServiceHash {
    public void updateAge(Long userId, int age) {
        String key = "user:" + userId;
        redis.hset(key, "age", String.valueOf(age));  // 直接修改
        redis.expire(key, 3600);
    }
}
```

**完整的用户信息管理**：

```java
@Service
public class UserCacheService {

    @Autowired
    private RedisTemplate<String, String> redis;

    // 缓存用户信息
    public void cacheUser(User user) {
        String key = "user:" + user.getId();
        Map<String, String> userMap = new HashMap<>();
        userMap.put("id", String.valueOf(user.getId()));
        userMap.put("name", user.getName());
        userMap.put("age", String.valueOf(user.getAge()));
        userMap.put("email", user.getEmail());
        userMap.put("city", user.getCity());

        redis.opsForHash().putAll(key, userMap);
        redis.expire(key, 3600, TimeUnit.SECONDS);
    }

    // 获取用户信息
    public User getUser(Long userId) {
        String key = "user:" + userId;
        Map<Object, Object> map = redis.opsForHash().entries(key);

        if (map.isEmpty()) {
            return null;
        }

        User user = new User();
        user.setId(Long.valueOf((String) map.get("id")));
        user.setName((String) map.get("name"));
        user.setAge(Integer.valueOf((String) map.get("age")));
        user.setEmail((String) map.get("email"));
        user.setCity((String) map.get("city"));

        return user;
    }

    // 更新单个字段
    public void updateField(Long userId, String field, String value) {
        String key = "user:" + userId;
        redis.opsForHash().put(key, field, value);
    }

    // 删除用户
    public void deleteUser(Long userId) {
        String key = "user:" + userId;
        redis.delete(key);
    }
}
```

### 场景2：商品详情缓存

**商品信息包含多个维度**：

```java
@Service
public class ProductCacheService {

    // 缓存商品详情
    public void cacheProduct(Product product) {
        String key = "product:" + product.getId();
        Map<String, String> productMap = new HashMap<>();

        // 基本信息
        productMap.put("name", product.getName());
        productMap.put("price", String.valueOf(product.getPrice()));
        productMap.put("stock", String.valueOf(product.getStock()));
        productMap.put("category", product.getCategory());

        // 统计信息
        productMap.put("sales", String.valueOf(product.getSales()));
        productMap.put("views", String.valueOf(product.getViews()));
        productMap.put("rating", String.valueOf(product.getRating()));

        redis.opsForHash().putAll(key, productMap);
        redis.expire(key, 7200, TimeUnit.SECONDS);  // 2小时
    }

    // 浏览量+1
    public void incrViews(Long productId) {
        String key = "product:" + productId;
        redis.opsForHash().increment(key, "views", 1);
    }

    // 扣减库存
    public boolean decrStock(Long productId, int quantity) {
        String key = "product:" + productId;
        Long stock = redis.opsForHash().increment(key, "stock", -quantity);

        if (stock < 0) {
            // 库存不足，回滚
            redis.opsForHash().increment(key, "stock", quantity);
            return false;
        }

        return true;
    }

    // 获取商品价格（只读一个字段）
    public BigDecimal getPrice(Long productId) {
        String key = "product:" + productId;
        String price = (String) redis.opsForHash().get(key, "price");
        return price != null ? new BigDecimal(price) : null;
    }
}
```

### 场景3：购物车实现

**购物车结构**：

```
cart:user:1001
├── product:1001: "2"  (商品ID: 数量)
├── product:1002: "1"
└── product:1003: "5"
```

**完整实现**：

```java
@Service
public class ShoppingCartService {

    @Autowired
    private RedisTemplate<String, String> redis;

    // 添加商品到购物车
    public void addItem(Long userId, Long productId, int quantity) {
        String key = "cart:user:" + userId;
        String field = "product:" + productId;

        // 获取当前数量
        Integer currentQty = redis.opsForHash().increment(key, field, 0).intValue();

        // 累加数量
        redis.opsForHash().increment(key, field, quantity);

        // 设置过期时间（30天）
        redis.expire(key, 30, TimeUnit.DAYS);
    }

    // 修改商品数量
    public void updateQuantity(Long userId, Long productId, int quantity) {
        String key = "cart:user:" + userId;
        String field = "product:" + productId;

        if (quantity <= 0) {
            // 数量<=0，删除商品
            redis.opsForHash().delete(key, field);
        } else {
            redis.opsForHash().put(key, field, String.valueOf(quantity));
        }
    }

    // 删除商品
    public void removeItem(Long userId, Long productId) {
        String key = "cart:user:" + userId;
        String field = "product:" + productId;
        redis.opsForHash().delete(key, field);
    }

    // 清空购物车
    public void clearCart(Long userId) {
        String key = "cart:user:" + userId;
        redis.delete(key);
    }

    // 获取购物车商品列表
    public Map<Long, Integer> getCartItems(Long userId) {
        String key = "cart:user:" + userId;
        Map<Object, Object> map = redis.opsForHash().entries(key);

        Map<Long, Integer> items = new HashMap<>();
        for (Map.Entry<Object, Object> entry : map.entrySet()) {
            String field = (String) entry.getKey();
            Long productId = Long.valueOf(field.replace("product:", ""));
            Integer quantity = Integer.valueOf((String) entry.getValue());
            items.put(productId, quantity);
        }

        return items;
    }

    // 获取购物车商品数量
    public int getCartCount(Long userId) {
        String key = "cart:user:" + userId;
        return redis.opsForHash().size(key).intValue();
    }

    // 检查商品是否在购物车
    public boolean hasItem(Long userId, Long productId) {
        String key = "cart:user:" + userId;
        String field = "product:" + productId;
        return redis.opsForHash().hasKey(key, field);
    }
}
```

### 场景4：统计信息聚合

**网站统计**：

```java
// 每日PV/UV统计
public class WebStatService {

    // 记录页面访问
    public void recordPageView(String page) {
        String today = LocalDate.now().format(DateTimeFormatter.BASIC_ISO_DATE);
        String key = "stat:pv:" + today;

        // page维度统计
        redis.opsForHash().increment(key, page, 1);

        // 设置过期时间（保留90天）
        redis.expire(key, 90, TimeUnit.DAYS);
    }

    // 获取今日各页面PV
    public Map<String, Long> getTodayPageViews() {
        String today = LocalDate.now().format(DateTimeFormatter.BASIC_ISO_DATE);
        String key = "stat:pv:" + today;

        Map<Object, Object> map = redis.opsForHash().entries(key);
        Map<String, Long> result = new HashMap<>();

        for (Map.Entry<Object, Object> entry : map.entrySet()) {
            result.put((String) entry.getKey(),
                      Long.valueOf((String) entry.getValue()));
        }

        return result;
    }

    // 获取指定页面的PV
    public Long getPageViewCount(String page) {
        String today = LocalDate.now().format(DateTimeFormatter.BASIC_ISO_DATE);
        String key = "stat:pv:" + today;

        String count = (String) redis.opsForHash().get(key, page);
        return count != null ? Long.valueOf(count) : 0L;
    }
}
```

## 四、最佳实践

### 4.1 何时使用Hash？

✅ **适合Hash的场景**：
- 对象字段固定（如用户、商品）
- 需要频繁修改部分字段
- 需要获取部分字段（不是全部）
- 对象字段较多（>5个）

❌ **不适合Hash的场景**：
- 对象结构不固定（动态字段）
- 总是整体读写
- 需要复杂查询（如JSON路径查询）
- 需要嵌套结构

### 4.2 性能优化

**批量操作**：

```java
// ❌ 慢：多次网络请求
for (String field : fields) {
    redis.opsForHash().put(key, field, value);
}

// ✅ 快：一次网络请求
Map<String, String> map = new HashMap<>();
for (String field : fields) {
    map.put(field, value);
}
redis.opsForHash().putAll(key, map);
```

**避免大Hash**：

```java
// ❌ 不推荐：单个Hash存储10000个字段
redis.opsForHash().put("users", "user:1001", data);  // 10000次
redis.opsForHash().put("users", "user:1002", data);
// ...

// ✅ 推荐：每个用户一个Hash
redis.opsForHash().putAll("user:1001", userData);
redis.opsForHash().putAll("user:1002", userData);
```

**建议**：
- 单个Hash字段数 < 1000
- 单个字段value < 100KB
- 超过限制考虑拆分

### 4.3 过期时间

⚠️ **注意**：Hash **不支持给单个字段设置过期时间**，只能整体设置！

```bash
# ✅ 正确：给整个Hash设置过期
127.0.0.1:6379> EXPIRE user:1001 3600

# ❌ 错误：不能给字段设置过期
# EXPIRE user:1001:name 3600  # 这样不行！
```

**解决方案**：

```java
// 方案1：使用String存储需要独立过期的字段
redis.setex("user:1001:session", 1800, token);  // 30分钟
redis.opsForHash().putAll("user:1001:profile", profileData);  // 永久

// 方案2：使用时间戳判断
redis.opsForHash().put(key, "expire_time", String.valueOf(expireTimestamp));

// 读取时检查
String expireTimeStr = redis.opsForHash().get(key, "expire_time");
if (System.currentTimeMillis() > Long.valueOf(expireTimeStr)) {
    // 已过期
    redis.delete(key);
}
```

## 五、总结

### 核心要点

1. **Hash是键值对集合**：一个外层Key包含多个Field-Value对
2. **适合存储对象**：相比String存JSON，Hash可以单独操作字段
3. **底层实现**：小对象用ziplist（省内存），大对象用hashtable（高性能）
4. **常用场景**：用户信息、商品详情、购物车、统计数据
5. **过期时间**：只能整体设置，不能单字段设置

### 命令速查表

| 命令 | 作用 | 时间复杂度 |
|------|------|-----------|
| HSET | 设置字段 | O(1) |
| HGET | 获取字段 | O(1) |
| HMSET | 批量设置 | O(N) |
| HMGET | 批量获取 | O(N) |
| HGETALL | 获取所有 | O(N) |
| HDEL | 删除字段 | O(N) |
| HINCRBY | 递增 | O(1) |
| HEXISTS | 字段存在性 | O(1) |
| HLEN | 字段数量 | O(1) |

### 选择指南

| 场景 | String (JSON) | Hash |
|------|--------------|------|
| 整体读写对象 | ✅ | ❌ |
| 频繁修改部分字段 | ❌ | ✅ |
| 对象结构动态 | ✅ | ❌ |
| 需要嵌套结构 | ✅ | ❌ |
| 购物车类场景 | ❌ | ✅ |

### 下一步

掌握了Hash类型后，下一篇我们将学习**List类型**：
- 双端队列特性
- 实现消息队列
- 时间线和最新列表

---

**思考题**：
1. 为什么Hash不支持单个字段设置过期时间？如何实现类似功能？
2. 一个Hash存储10000个字段和10000个String键，哪个更省内存？
3. 购物车用Hash存储有什么优势？

下一篇见！
