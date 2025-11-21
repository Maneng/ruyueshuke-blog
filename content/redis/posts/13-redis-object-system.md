---
title: "Redis内存模型与对象系统：深入理解redisObject"
date: 2025-01-21T20:00:00+08:00
draft: false
tags: ["Redis", "内存模型", "对象系统", "redisObject"]
categories: ["技术"]
description: "深入Redis底层对象系统，理解redisObject结构、类型编码、引用计数与内存优化机制，掌握Redis高性能的底层秘密"
weight: 13
stage: 2
stageTitle: "架构原理篇"
---

## 引言

在使用Redis时，我们操作的是String、Hash、List这些高层数据类型。但你是否想过：**Redis是如何在内存中存储和管理这些对象的？为什么同样是存储字符串，Redis能做到如此高的性能和内存利用率？**

今天我们深入Redis底层，揭开对象系统的神秘面纱。理解对象系统，是理解Redis高性能和内存优化的基础。

## 一、为什么需要对象系统？

### 1.1 直接存储的问题

假设我们不用对象系统，直接在内存中存储数据，会遇到什么问题？

```c
// 简单粗暴的方式
char* key = "user:1001";
char* value = "张三";

// 问题1：如何知道value的类型？是字符串？整数？还是列表？
// 问题2：如何实现引用计数？避免重复拷贝
// 问题3：如何记录对象的访问时间？用于LRU淘汰
// 问题4：如何选择最优的底层编码？节省内存
```

### 1.2 对象系统的价值

Redis设计了一个统一的对象系统`redisObject`，解决了以下问题：

1. **类型识别**：明确知道对象是什么类型（String/Hash/List/Set/ZSet）
2. **编码优化**：根据数据特点自动选择最优编码方式（节省内存）
3. **内存管理**：引用计数、LRU/LFU淘汰、内存回收
4. **命令多态**：同一个命令可以作用于不同编码的对象
5. **类型安全**：避免类型错误操作（如对字符串执行LPUSH）

## 二、redisObject核心结构

### 2.1 源码定义

```c
typedef struct redisObject {
    unsigned type:4;        // 类型（4 bits）：String、Hash、List、Set、ZSet
    unsigned encoding:4;    // 编码（4 bits）：底层实现方式
    unsigned lru:24;        // LRU时间戳（24 bits）或LFU数据
    int refcount;           // 引用计数（32 bits）
    void *ptr;              // 指向实际数据的指针（64 bits）
} robj;
```

**结构说明**：
- 总大小：**16字节**（紧凑设计，节省内存）
- 4 bits + 4 bits + 24 bits = 32 bits = 4字节
- refcount：4字节
- ptr：8字节（64位系统）

### 2.2 字段详解

#### 2.2.1 type：对象类型（4 bits）

```c
#define OBJ_STRING 0    // 字符串
#define OBJ_LIST   1    // 列表
#define OBJ_SET    2    // 集合
#define OBJ_ZSET   3    // 有序集合
#define OBJ_HASH   4    // 哈希表
```

**示例**：
```bash
127.0.0.1:6379> SET name "Redis"
127.0.0.1:6379> TYPE name
string  # type = OBJ_STRING

127.0.0.1:6379> LPUSH tasks "task1"
127.0.0.1:6379> TYPE tasks
list    # type = OBJ_LIST
```

#### 2.2.2 encoding：底层编码（4 bits）

Redis的5大类型，底层有**10种编码实现**：

```c
#define OBJ_ENCODING_RAW        0   // 简单动态字符串（SDS）
#define OBJ_ENCODING_INT        1   // 整数
#define OBJ_ENCODING_HT         2   // 字典（哈希表）
#define OBJ_ENCODING_ZIPLIST    5   // 压缩列表（已废弃，7.0+改用listpack）
#define OBJ_ENCODING_INTSET     6   // 整数集合
#define OBJ_ENCODING_SKIPLIST   7   // 跳表
#define OBJ_ENCODING_EMBSTR     8   // embstr编码的SDS（短字符串优化）
#define OBJ_ENCODING_QUICKLIST  9   // 快速列表（List的实现）
#define OBJ_ENCODING_LISTPACK  11   // 紧凑列表（7.0+）
```

**编码转换示例**（String类型）：

```bash
# 1. 整数编码（最节省内存）
127.0.0.1:6379> SET count 123
127.0.0.1:6379> OBJECT ENCODING count
"int"  # encoding = OBJ_ENCODING_INT，直接存储整数

# 2. embstr编码（短字符串优化）
127.0.0.1:6379> SET name "Redis"
127.0.0.1:6379> OBJECT ENCODING name
"embstr"  # encoding = OBJ_ENCODING_EMBSTR，≤44字节

# 3. raw编码（长字符串）
127.0.0.1:6379> SET longstr "这是一个超过44字节的长字符串内容，用于测试raw编码..."
127.0.0.1:6379> OBJECT ENCODING longstr
"raw"  # encoding = OBJ_ENCODING_RAW
```

#### 2.2.3 lru：访问时间（24 bits）

用于LRU（Least Recently Used）或LFU（Least Frequently Used）淘汰策略。

```bash
# 查看对象的空闲时间（秒）
127.0.0.1:6379> SET test "hello"
127.0.0.1:6379> OBJECT IDLETIME test
(integer) 5  # 5秒未访问

# 再次访问
127.0.0.1:6379> GET test
"hello"
127.0.0.1:6379> OBJECT IDLETIME test
(integer) 0  # 刚访问，空闲时间清零
```

**内存淘汰时**：
- `volatile-lru/allkeys-lru`：淘汰最久未访问的key
- `volatile-lfu/allkeys-lfu`：淘汰访问频率最低的key

#### 2.2.4 refcount：引用计数（32 bits）

用于内存管理，当`refcount=0`时回收对象。

**共享对象优化**：
Redis会共享0-9999的整数对象，避免重复创建。

```bash
127.0.0.1:6379> SET a 100
127.0.0.1:6379> SET b 100
127.0.0.1:6379> OBJECT REFCOUNT a
(integer) 2147483647  # 共享对象，超大refcount表示不会被回收

127.0.0.1:6379> SET c 999999
127.0.0.1:6379> OBJECT REFCOUNT c
(integer) 1  # 超出共享范围，独立对象
```

**共享对象范围**：
- 整数：0-9999（默认，可配置）
- 字符串：不共享（因为比较成本高）

#### 2.2.5 ptr：数据指针（64 bits）

指向实际存储数据的内存地址。

```c
// 伪代码示例
redisObject *strObj = createStringObject("hello");

// strObj->ptr 指向实际的字符串数据：
// +--------+--------+------+-------+
// |  len   | alloc  | flag | "hello\0" |
// +--------+--------+------+-------+
//   SDS结构
```

## 三、类型与编码的对应关系

### 3.1 String类型的编码

| 编码 | 使用条件 | 内存占用 | 优势 |
|------|---------|---------|-----|
| **int** | 整数值，且在long范围内 | 8字节（不算redisObject） | 最节省内存，直接存储 |
| **embstr** | 字符串长度 ≤ 44字节 | 连续内存分配 | 减少内存碎片，缓存友好 |
| **raw** | 字符串长度 > 44字节 | redisObject + SDS | 灵活，支持动态扩展 |

**编码转换**：
```
int → embstr → raw（单向转换，不可逆）
```

### 3.2 Hash类型的编码

| 编码 | 使用条件 | 优势 |
|------|---------|-----|
| **ziplist**（7.0前） | 元素数量少 且 所有值长度小 | 连续内存，节省空间 |
| **listpack**（7.0+） | 同上 | ziplist的改进版 |
| **hashtable** | 数据量大 或 值较长 | 查询O(1)，高性能 |

**配置参数**：
```conf
hash-max-ziplist-entries 512   # 元素数量超过512，转换为hashtable
hash-max-ziplist-value 64      # 任一值超过64字节，转换为hashtable
```

### 3.3 List类型的编码

| 编码 | 版本 | 说明 |
|------|------|------|
| **quicklist** | 3.2+ | 双向链表 + ziplist的混合结构 |

**内部结构**：
```
quicklist = 双向链表 + 压缩列表
每个节点是一个ziplist，可配置压缩级别
```

### 3.4 Set类型的编码

| 编码 | 使用条件 | 优势 |
|------|---------|-----|
| **intset** | 所有元素都是整数 且 数量较少 | 有序数组，节省内存 |
| **hashtable** | 有非整数元素 或 数量较多 | 查询O(1) |

**配置参数**：
```conf
set-max-intset-entries 512  # 超过512个元素，转换为hashtable
```

### 3.5 ZSet类型的编码

| 编码 | 使用条件 | 优势 |
|------|---------|-----|
| **ziplist/listpack** | 元素少 且 值短 | 紧凑存储 |
| **skiplist + hashtable** | 数据量大 | skiplist实现有序，hashtable加速查询 |

**配置参数**：
```conf
zset-max-ziplist-entries 128
zset-max-ziplist-value 64
```

## 四、内存优化机制

### 4.1 整数共享池（0-9999）

```c
// Redis启动时预创建10000个整数对象
for (int i = 0; i < 10000; i++) {
    shared.integers[i] = createObject(OBJ_STRING, (void*)(long)i);
    shared.integers[i]->encoding = OBJ_ENCODING_INT;
}
```

**效果**：
```bash
127.0.0.1:6379> SET user:1 100
127.0.0.1:6379> SET user:2 100
127.0.0.1:6379> SET user:3 100
# 三个key共享同一个100对象，只占用1份内存
```

### 4.2 embstr优化（短字符串）

**embstr vs raw**：

```
# raw编码（两次内存分配）
+----------------+       +----------+
| redisObject    | ----> | SDS      |
| type=STRING    |       | len=5    |
| encoding=RAW   |       | "hello"  |
+----------------+       +----------+

# embstr编码（一次内存分配）
+---------------------------------------+
| redisObject | SDS                     |
| type=STRING | len=5 | "hello"        |
| encoding=EMBSTR                      |
+---------------------------------------+
连续内存，缓存友好
```

**优势**：
1. 减少内存分配次数（1次 vs 2次）
2. 减少内存碎片
3. 提高CPU缓存命中率

**为什么是44字节？**
```
jemalloc分配器的64字节对齐
64字节 - redisObject(16字节) - SDS头(3字节) - '\0'(1字节) = 44字节
```

### 4.3 压缩列表（ziplist/listpack）

**原理**：
- 连续内存块存储
- 紧凑编码（变长整数、字符串）
- 适合小数据量

**权衡**：
- ✅ 优势：节省内存，缓存友好
- ❌ 劣势：修改O(n)（需要移动元素）

## 五、实战：内存优化案例

### 5.1 案例1：整数值尽量用数字

```java
@Service
public class UserService {
    @Autowired
    private RedisTemplate<String, Object> redis;

    // ❌ 不好的做法：字符串存储
    public void badPractice(Long userId) {
        redis.opsForValue().set("user:" + userId, String.valueOf(userId));
        // 占用：embstr编码，约20字节
    }

    // ✅ 好的做法：整数存储
    public void goodPractice(Long userId) {
        redis.opsForValue().set("user:" + userId, userId);
        // 占用：int编码，8字节
        // 且会使用共享对象（如果值在0-9999范围）
    }
}
```

### 5.2 案例2：Hash vs String选择

**场景**：存储用户信息

```java
// 方式1：String存储整个对象（JSON序列化）
public void storeUserAsString(User user) {
    String key = "user:" + user.getId();
    String json = JSON.toJSONString(user);
    redis.opsForValue().set(key, json);
    // 优势：一次操作取出所有数据
    // 劣势：修改任一字段需要重新序列化整个对象
}

// 方式2：Hash存储字段
public void storeUserAsHash(User user) {
    String key = "user:" + user.getId();
    Map<String, Object> map = new HashMap<>();
    map.put("name", user.getName());
    map.put("age", user.getAge());
    map.put("email", user.getEmail());
    redis.opsForHash().putAll(key, map);
    // 优势：字段级别修改，节省带宽
    // 劣势：小对象时，Hash开销更大（redisObject + field开销）
}
```

**选择建议**：
- **小对象（<5个字段）**：用String + JSON
- **大对象（≥5个字段）**：用Hash
- **频繁修改部分字段**：用Hash

### 5.3 案例3：优化Hash编码

```java
// 控制Hash使用ziplist编码（节省内存）
@Configuration
public class RedisConfig {

    @Bean
    public RedisTemplate<String, Object> redisTemplate(RedisConnectionFactory factory) {
        RedisTemplate<String, Object> template = new RedisTemplate<>();
        template.setConnectionFactory(factory);

        // 确保值的序列化不会产生过长字符串
        template.setValueSerializer(new GenericJackson2JsonRedisSerializer());

        return template;
    }
}

// 业务代码：保持字段值简短
public void saveProduct(Product product) {
    String key = "product:" + product.getId();
    Map<String, String> map = new HashMap<>();
    map.put("name", product.getName());  // 控制长度 < 64字节
    map.put("price", String.valueOf(product.getPrice()));  // 整数用字符串表示
    redis.opsForHash().putAll(key, map);

    // 验证编码
    Object encoding = redis.execute((RedisCallback<Object>) connection -> {
        return connection.execute("OBJECT", "ENCODING".getBytes(), key.getBytes());
    });
    System.out.println("Encoding: " + encoding);  // 期望输出：ziplist 或 listpack
}
```

## 六、调试命令

### 6.1 查看对象信息

```bash
# 1. 查看对象类型
127.0.0.1:6379> TYPE key

# 2. 查看对象编码
127.0.0.1:6379> OBJECT ENCODING key

# 3. 查看引用计数
127.0.0.1:6379> OBJECT REFCOUNT key

# 4. 查看空闲时间（秒）
127.0.0.1:6379> OBJECT IDLETIME key

# 5. 查看对象占用内存（字节）
127.0.0.1:6379> MEMORY USAGE key
```

### 6.2 内存分析示例

```bash
# 示例1：分析String对象
127.0.0.1:6379> SET num 12345
127.0.0.1:6379> OBJECT ENCODING num
"int"
127.0.0.1:6379> MEMORY USAGE num
(integer) 48  # 16(redisObject) + 8(int) + 24(开销)

# 示例2：分析Hash对象
127.0.0.1:6379> HSET user:1 name "张三" age 25
127.0.0.1:6379> OBJECT ENCODING user:1
"ziplist"  # 或 "listpack"（Redis 7.0+）
127.0.0.1:6379> MEMORY USAGE user:1
(integer) 128  # 具体值取决于实现
```

## 七、最佳实践

### 7.1 内存优化建议

✅ **推荐做法**：

1. **优先使用整数**：能用整数表示的尽量用整数
   ```bash
   SET user_id 1001      # ✅ int编码
   SET user_id "1001"    # ❌ embstr编码
   ```

2. **控制字符串长度**：
   - ≤ 44字节：使用embstr
   - > 44字节：考虑是否能压缩或拆分

3. **合理使用Hash**：
   - 字段数量：< 512
   - 字段值长度：< 64字节
   - 保持在ziplist/listpack编码

4. **利用整数共享**：
   - 计数器、状态码等用0-9999范围的整数

5. **避免大对象**：
   - 单个String：< 10MB
   - 单个Hash：< 1000个字段
   - 单个List/Set/ZSet：< 5000个元素

### 7.2 反模式

❌ **避免的做法**：

1. **滥用String存储大JSON**：
   ```java
   // ❌ 不好
   redis.set("user:1", JSON.toJSONString(bigUserObject));  // 100KB JSON
   ```

2. **不关注编码转换**：
   ```bash
   # 开始是ziplist，随着数据增加变成hashtable，内存暴增
   HSET product:1 field1 value1
   # ... 添加了1000个字段 ...
   # 内存占用从1KB → 50KB
   ```

3. **过度依赖共享对象**：
   ```java
   // ❌ 不要为了共享对象而限制业务
   // 如果实际需要存储10000以上的ID，就直接存，不要纠结共享
   ```

## 八、总结

### 8.1 核心要点

1. **redisObject是Redis对象系统的核心**
   - 16字节结构，包含类型、编码、LRU、引用计数、数据指针

2. **类型与编码分离**
   - 5大类型：String、Hash、List、Set、ZSet
   - 10种编码：int、embstr、raw、ziplist、intset、skiplist等
   - 根据数据特点自动选择最优编码

3. **三大内存优化机制**
   - 整数共享池（0-9999）
   - embstr短字符串优化（≤44字节）
   - 压缩列表（ziplist/listpack）

4. **编码会自动转换**
   - 小数据量 → 紧凑编码（ziplist/intset/embstr）
   - 大数据量 → 高性能编码（hashtable/skiplist/raw）
   - 单向转换，不可逆

5. **内存优化原则**
   - 优先整数，控制字符串长度
   - 合理配置编码转换阈值
   - 避免单个对象过大

### 8.2 下一篇预告

理解了redisObject对象系统后，你是否好奇：**为什么Redis不用C语言的字符串，而要自己实现SDS（简单动态字符串）？SDS有什么神奇之处？**

下一篇《SDS简单动态字符串》，我们将深入剖析Redis字符串的底层实现，揭秘O(1)复杂度获取字符串长度、二进制安全、减少内存分配等核心特性的实现原理。

---

**思考题**：
1. 为什么embstr的临界值是44字节，而不是32或64？
2. 整数共享池为什么只共享0-9999，而不是更大范围？
3. 如果你要存储1000万个用户ID（范围1-10000000），用什么数据结构最省内存？

欢迎在评论区分享你的思考！
