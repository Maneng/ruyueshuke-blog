---
title: "整数集合与压缩列表：Redis的极致内存优化"
date: 2025-01-21T20:40:00+08:00
draft: false
tags: ["Redis", "intset", "ziplist", "listpack", "内存优化"]
categories: ["技术"]
description: "深入理解Redis的整数集合（intset）和压缩列表（ziplist/listpack），掌握小数据量场景的内存优化策略和编码转换机制"
weight: 17
stage: 2
stageTitle: "架构原理篇"
---

## 引言

你是否好奇：**为什么同样存储100个整数，Redis的内存占用只有其他数据库的1/10？为什么小Hash比大Hash节省这么多内存？编码转换是如何发生的？**

今天我们深入Redis的两大内存优化数据结构：**整数集合（intset）**和**压缩列表（ziplist/listpack）**，揭秘Redis在小数据量场景下的极致优化。

## 一、为什么需要内存优化数据结构？

### 1.1 性能 vs 内存的权衡

**通用数据结构的问题**：

```
字典（hashtable）：
- 查询：O(1) ✅
- 内存：每个节点 ~50字节（dictEntry + 指针） ❌

跳表（skiplist）：
- 查询：O(logN) ✅
- 内存：每个节点 ~80字节（多层指针） ❌

问题：对于小数据量（如10个元素的Set），使用通用结构浪费内存
```

**Redis的解决方案**：
> 针对小数据量场景，设计紧凑的专用数据结构，牺牲一点性能换取内存节省。

### 1.2 编码策略

Redis采用**双重编码**策略：

| 数据类型 | 小数据量编码 | 大数据量编码 | 转换阈值 |
|---------|------------|------------|---------|
| **Set** | intset（所有元素都是整数） | hashtable | 512个元素 |
| **Hash** | ziplist/listpack | hashtable | 512个字段 或 64字节值 |
| **ZSet** | ziplist/listpack | skiplist + hashtable | 128个元素 或 64字节值 |
| **List** | quicklist（内部使用ziplist/listpack） | quicklist | - |

**核心思想**：
- **小数据量**：节省内存优先（连续内存，紧凑编码）
- **大数据量**：性能优先（O(1)查询）

## 二、整数集合（intset）

### 2.1 核心结构

```c
typedef struct intset {
    uint32_t encoding;  // 编码方式（int16/int32/int64）
    uint32_t length;    // 元素数量
    int8_t contents[];  // 柔性数组，实际存储整数
} intset;
```

**编码类型**：
```c
#define INTSET_ENC_INT16 (sizeof(int16_t))  // 2字节，范围：-32768 ~ 32767
#define INTSET_ENC_INT32 (sizeof(int32_t))  // 4字节，范围：-2^31 ~ 2^31-1
#define INTSET_ENC_INT64 (sizeof(int64_t))  // 8字节，范围：-2^63 ~ 2^63-1
```

**关键特点**：
1. **有序数组**：元素按升序排列
2. **变长编码**：根据最大值选择编码（int16/int32/int64）
3. **紧凑存储**：连续内存，无指针开销
4. **自动升级**：插入大值时自动升级编码

### 2.2 内存布局示例

**示例1**：存储 `{1, 5, 10}`（int16编码）

```
+----------+--------+--------------------+
| encoding | length | contents           |
| 2 (int16)| 3      | 1 | 5 | 10 |      |
+----------+--------+--------------------+
  4字节      4字节     2   2   2   (字节)

总内存：8 + 6 = 14字节
```

**示例2**：存储 `{1, 5, 100000}`（int32编码，因为100000超出int16）

```
+----------+--------+----------------------------+
| encoding | length | contents                   |
| 4 (int32)| 3      | 1 | 5 | 100000 |          |
+----------+--------+----------------------------+
  4字节      4字节     4   4    4      (字节)

总内存：8 + 12 = 20字节
```

**vs hashtable（Set类型）**：
```
hashtable存储{1, 5, 10}：
- dictEntry * 3：48字节（每个16字节）
- redisObject * 3：48字节（每个16字节）
- 哈希表数组：64字节（初始大小）
总计：160字节

intset存储{1, 5, 10}：14字节

节省：160 - 14 = 146字节（91%内存节省）
```

### 2.3 核心操作

#### 2.3.1 查找（二分查找）

```c
// 时间复杂度：O(logN)
static uint8_t intsetSearch(intset *is, int64_t value, uint32_t *pos) {
    int min = 0, max = intrev32ifbe(is->length) - 1, mid = -1;
    int64_t cur = -1;

    // 边界优化
    if (intrev32ifbe(is->length) == 0) {
        if (pos) *pos = 0;
        return 0;
    } else {
        // 如果value比最大值还大，直接返回
        if (value > _intsetGet(is, max)) {
            if (pos) *pos = intrev32ifbe(is->length);
            return 0;
        } else if (value < _intsetGet(is, 0)) {
            if (pos) *pos = 0;
            return 0;
        }
    }

    // 二分查找
    while (max >= min) {
        mid = ((unsigned int)min + (unsigned int)max) >> 1;
        cur = _intsetGet(is, mid);
        if (value > cur) {
            min = mid + 1;
        } else if (value < cur) {
            max = mid - 1;
        } else {
            break;  // 找到
        }
    }

    if (value == cur) {
        if (pos) *pos = mid;
        return 1;  // 找到
    } else {
        if (pos) *pos = min;
        return 0;  // 未找到
    }
}
```

**示例**：
```bash
127.0.0.1:6379> SADD myset 1 5 10 50 100
(integer) 5
# intset内部：{1, 5, 10, 50, 100}（有序）

127.0.0.1:6379> SISMEMBER myset 50
(integer) 1  # 通过二分查找，3次比较找到
```

#### 2.3.2 插入（可能触发升级）

```c
intset *intsetAdd(intset *is, int64_t value, uint8_t *success) {
    uint8_t valenc = _intsetValueEncoding(value);
    uint32_t pos;
    if (success) *success = 1;

    // 1. 如果value的编码大于当前编码，需要升级
    if (valenc > intrev32ifbe(is->encoding)) {
        return intsetUpgradeAndAdd(is, value);
    }

    // 2. 查找插入位置（同时检查是否已存在）
    if (intsetSearch(is, value, &pos)) {
        if (success) *success = 0;  // 已存在
        return is;
    }

    // 3. 扩展内存
    is = intsetResize(is, intrev32ifbe(is->length) + 1);

    // 4. 移动元素，腾出位置
    if (pos < intrev32ifbe(is->length)) {
        intsetMoveTail(is, pos, pos + 1);
    }

    // 5. 插入新值
    _intsetSet(is, pos, value);
    is->length = intrev32ifbe(intrev32ifbe(is->length) + 1);
    return is;
}
```

**升级过程**：
```c
// 从int16升级到int32
static intset *intsetUpgradeAndAdd(intset *is, int64_t value) {
    uint8_t curenc = intrev32ifbe(is->encoding);
    uint8_t newenc = _intsetValueEncoding(value);
    int length = intrev32ifbe(is->length);

    // 1. 扩展内存（新编码 * (元素数+1)）
    is = intsetResize(is, length + 1);

    // 2. 从后向前迁移所有元素（避免覆盖）
    while (length--) {
        _intsetSet(is, length + prepend, _intsetGetEncoded(is, length, curenc));
    }

    // 3. 插入新值（在头部或尾部）
    if (prepend) {
        _intsetSet(is, 0, value);
    } else {
        _intsetSet(is, intrev32ifbe(is->length), value);
    }

    // 4. 更新编码和长度
    is->encoding = intrev32ifbe(newenc);
    is->length = intrev32ifbe(intrev32ifbe(is->length) + 1);
    return is;
}
```

**升级示例**：
```bash
# 初始：{1, 5, 10}（int16编码）
127.0.0.1:6379> SADD myset 1 5 10
127.0.0.1:6379> OBJECT ENCODING myset
"intset"
127.0.0.1:6379> DEBUG OBJECT myset
Value at:0x... encoding:intset serializedlength:14

# 插入大值，触发升级
127.0.0.1:6379> SADD myset 100000  # 超出int16范围
(integer) 1
127.0.0.1:6379> DEBUG OBJECT myset
Value at:0x... encoding:intset serializedlength:24  # 内存增加（升级到int32）
```

**注意**：**升级是单向的，不会降级！**
```bash
# 即使删除大值，编码也不会降回int16
127.0.0.1:6379> SREM myset 100000
(integer) 1
127.0.0.1:6379> OBJECT ENCODING myset
"intset"  # 仍是int32编码
```

#### 2.3.3 删除

```c
intset *intsetRemove(intset *is, int64_t value, int *success) {
    uint8_t valenc = _intsetValueEncoding(value);
    uint32_t pos;

    // 1. 查找元素
    if (intsetSearch(is, value, &pos)) {
        uint32_t len = intrev32ifbe(is->length);

        // 2. 移动后续元素（覆盖被删除的元素）
        if (pos < (len - 1)) {
            intsetMoveTail(is, pos + 1, pos);
        }

        // 3. 缩小内存
        is = intsetResize(is, len - 1);
        is->length = intrev32ifbe(len - 1);
        if (success) *success = 1;
    } else {
        if (success) *success = 0;
    }
    return is;
}
```

### 2.4 性能分析

| 操作 | 时间复杂度 | 说明 |
|------|----------|------|
| 查找 | O(logN) | 二分查找（有序数组） |
| 插入 | O(N) | 可能需要移动元素 + 升级 |
| 删除 | O(N) | 需要移动元素 |
| 内存占用 | O(N) | 8字节头部 + N*encoding字节 |

**适用场景**：
- ✅ 小数据量（< 512个元素）
- ✅ 所有元素都是整数
- ✅ 读多写少

## 三、压缩列表（ziplist）与紧凑列表（listpack）

### 3.1 ziplist概述

**设计目标**：用一块连续内存存储多个元素，极致节省内存。

**使用场景**：
- Hash类型（小数据量）
- ZSet类型（小数据量）
- List类型（quicklist的内部节点）

**核心特点**：
1. **连续内存**：所有元素存储在一个连续的内存块
2. **变长编码**：根据元素大小选择最小的编码
3. **双向遍历**：支持从头到尾、从尾到头遍历
4. **紧凑存储**：无指针开销

### 3.2 ziplist结构

#### 整体布局

```
<zlbytes><zltail><zllen><entry>...<entry><zlend>

zlbytes: uint32_t，整个ziplist占用的字节数
zltail:  uint32_t，到最后一个entry的偏移量
zllen:   uint16_t，entry数量（如果超过2^16-2，需要遍历计数）
entry:   变长，实际存储的元素
zlend:   uint8_t，结束标志（0xFF）
```

**示例**：
```
ziplist存储 ["hello", "world", 123]

+--------+--------+--------+------------------+------------------+------------------+--------+
| zlbytes| zltail | zllen  | entry("hello")   | entry("world")   | entry(123)       | zlend  |
| 50     | 38     | 3      | prevlen|enc|hello| prevlen|enc|world| prevlen|enc|123  | 0xFF   |
+--------+--------+--------+------------------+------------------+------------------+--------+
  4字节    4字节    2字节      变长              变长              变长              1字节
```

#### entry结构

每个entry由三部分组成：

```
<prevlen><encoding><content>

prevlen:   前一个entry的长度（用于反向遍历）
           - 如果 < 254字节：1字节
           - 如果 >= 254字节：5字节（0xFE + 4字节实际长度）

encoding:  编码类型和content长度
           - 字符串：00/01/10开头
           - 整数：11开头

content:   实际数据
```

**prevlen示例**：
```
entry1长度=10字节，entry2的prevlen：
[0x0A]  # 1字节，值=10

entry1长度=300字节，entry2的prevlen：
[0xFE][0x2C][0x01][0x00][0x00]  # 5字节，0xFE + uint32(300)
```

**encoding示例**：

| 编码前缀 | 含义 | content长度 |
|---------|------|------------|
| `00pppppp` | 字符串，长度 ≤ 63字节 | 6 bits表示 |
| `01pppppp pppppppp` | 字符串，长度 ≤ 16383字节 | 14 bits表示 |
| `10______ pppppppp pppppppp pppppppp pppppppp` | 字符串，长度 > 16383字节 | 32 bits表示 |
| `11000000` | int16 | 2字节 |
| `11010000` | int32 | 4字节 |
| `11100000` | int64 | 8字节 |
| `11110000` | 24位整数 | 3字节 |
| `11111110` | 8位整数 | 1字节 |
| `1111xxxx` | 0-12的立即数 | 0字节（编码在encoding中） |

**示例1**：存储字符串"hello"（5字节）

```
prevlen: [0x00]          # 假设是第一个entry
encoding: [0x05]         # 00000101，字符串，长度5
content: [h][e][l][l][o]

总计：1 + 1 + 5 = 7字节
```

**示例2**：存储整数123

```
prevlen: [0x07]          # 前一个entry长度7
encoding: [0xFE]         # 11111110，8位整数
content: [0x7B]          # 123

总计：1 + 1 + 1 = 3字节
```

**示例3**：存储整数5

```
prevlen: [0x03]
encoding: [0xF5]         # 11110101，立即数5（1111xxxx，xxxx+1=5）
content: (无)

总计：1 + 1 = 2字节
```

### 3.3 ziplist的问题：连锁更新

**问题描述**：

```
假设有一个ziplist，所有entry长度都是250字节（prevlen=1字节）

entry1(250) -> entry2(250) -> entry3(250) -> ...
prevlen:1      prevlen:1      prevlen:1

现在在entry1前面插入一个长度254字节的新entry：

newEntry(254) -> entry1(250) -> entry2(250) -> ...

entry1的prevlen需要从1字节变成5字节（因为254>=254）
entry1长度变成250+4=254字节

entry2的prevlen也需要从1字节变成5字节
entry2长度变成254字节

entry3的prevlen也需要扩展...

级联更新！每个entry都需要重新分配内存和移动数据
```

**最坏情况**：
- N个entry全部触发连锁更新
- 时间复杂度：O(N²)
- 导致长时间阻塞

**概率**：
- 实际场景很少见（需要所有entry长度都在250-253字节）
- 但理论上可能发生

### 3.4 listpack：ziplist的改进版（Redis 7.0+）

**设计目标**：解决ziplist的连锁更新问题。

**核心改进**：取消prevlen字段，改为每个entry自己记录自己的长度。

#### listpack结构

```
<total-bytes><num-elements><entry>...<entry><end>

total-bytes:   uint32_t，整个listpack字节数
num-elements:  uint16_t，元素数量
entry:         变长
end:           0xFF
```

#### listpack entry结构

```
<encoding><content><backlen>

encoding:  编码类型和长度
content:   实际数据
backlen:   当前entry的总长度（用于反向遍历）
```

**关键点**：
- **backlen**：记录当前entry的长度，而不是前一个entry的长度
- **从后向前遍历**：读取backlen，向前跳过backlen字节，就能到达前一个entry
- **插入/删除**：不会影响其他entry的backlen，避免连锁更新

**示例**：
```
entry1: <enc1><data1><backlen=10>  (总长10字节)
entry2: <enc2><data2><backlen=8>   (总长8字节)
entry3: <enc3><data3><backlen=12>  (总长12字节)

反向遍历：
1. 从entry3的末尾读取backlen=12
2. 向前跳过12字节，到达entry2的末尾
3. 读取backlen=8
4. 向前跳过8字节，到达entry1的末尾
```

**优势**：
- ✅ 避免连锁更新（插入/删除只影响当前entry）
- ✅ 内存占用与ziplist相当
- ✅ 性能稳定

## 四、编码转换

### 4.1 Set类型的编码转换

```bash
# 初始：intset编码
127.0.0.1:6379> SADD nums 1 5 10
127.0.0.1:6379> OBJECT ENCODING nums
"intset"

# 添加非整数，转换为hashtable
127.0.0.1:6379> SADD nums "hello"
127.0.0.1:6379> OBJECT ENCODING nums
"hashtable"  # 不可逆！

# 或者元素数量超过512（默认阈值）
127.0.0.1:6379> SADD big_set {1..1000}
127.0.0.1:6379> OBJECT ENCODING big_set
"hashtable"
```

**配置参数**：
```conf
set-max-intset-entries 512  # 超过512个元素，转换为hashtable
```

### 4.2 Hash类型的编码转换

```bash
# 初始：ziplist/listpack编码
127.0.0.1:6379> HSET user name "Alice" age 25
127.0.0.1:6379> OBJECT ENCODING user
"ziplist"  # 或 "listpack"（Redis 7.0+）

# 触发转换：字段数量超过512
127.0.0.1:6379> HSET user field1 val1 field2 val2 ... field600 val600
127.0.0.1:6379> OBJECT ENCODING user
"hashtable"

# 或者：任一字段值超过64字节
127.0.0.1:6379> HSET user longfield "非常非常非常长的字符串...（超过64字节）"
127.0.0.1:6379> OBJECT ENCODING user
"hashtable"
```

**配置参数**：
```conf
hash-max-ziplist-entries 512  # 字段数量阈值
hash-max-ziplist-value 64     # 字段值长度阈值
```

### 4.3 ZSet类型的编码转换

```bash
# 初始：ziplist/listpack编码
127.0.0.1:6379> ZADD ranking 95 "Alice" 88 "Bob"
127.0.0.1:6379> OBJECT ENCODING ranking
"ziplist"

# 触发转换
127.0.0.1:6379> ZADD ranking 90 "非常非常非常长的名字...（超过64字节）"
127.0.0.1:6379> OBJECT ENCODING ranking
"skiplist"  # 实际是skiplist + hashtable
```

**配置参数**：
```conf
zset-max-ziplist-entries 128
zset-max-ziplist-value 64
```

## 五、性能对比

### 5.1 内存占用对比

**场景**：存储100个整数（1-100）

| 数据结构 | 内存占用 | 说明 |
|---------|---------|------|
| **intset** | 8 + 200 = 208字节 | 头部8字节 + 100*2字节（int16） |
| **hashtable** | ~5000字节 | dictEntry*100 + redisObject*100 + 哈希表数组 |
| **节省率** | 96% | |

**场景**：存储10个字段的Hash

| 数据结构 | 内存占用 | 说明 |
|---------|---------|------|
| **ziplist** | ~150字节 | 头部10字节 + 10对entry（每对约14字节） |
| **hashtable** | ~800字节 | dictEntry*10 + SDS*20 + 哈希表数组 |
| **节省率** | 81% | |

### 5.2 性能对比

**小数据量（< 100个元素）**：

| 操作 | intset | hashtable | 差异 |
|------|--------|-----------|------|
| 查找 | O(logN) ≈ 7次比较 | O(1) ≈ 1次比较 | intset慢6倍 |
| 插入 | O(N) ≈ 50次移动 | O(1) | intset慢50倍 |
| 内存 | 200字节 | 5000字节 | intset省96% |

**结论**：小数据量时，内存节省远大于性能损失。

**大数据量（> 1000个元素）**：

| 操作 | intset | hashtable | 差异 |
|------|--------|-----------|------|
| 查找 | O(logN) ≈ 10次比较 | O(1) ≈ 1次比较 | intset慢10倍 |
| 插入 | O(N) ≈ 500次移动 | O(1) | intset慢500倍 |
| 内存 | 2KB | 50KB | intset省96% |

**结论**：大数据量时，性能差异显著，应转换为hashtable。

## 六、最佳实践

### 6.1 充分利用紧凑编码

✅ **推荐做法**：

1. **保持小对象**：
   ```java
   // ✅ 好：利用ziplist编码
   for (int i = 0; i < 100; i++) {
       redis.opsForHash().put("user:" + i, "name", "User" + i);
       redis.opsForHash().put("user:" + i, "age", String.valueOf(20 + i));
   }
   // 每个Hash约100字节，总计10KB

   // ❌ 不好：单个大Hash
   for (int i = 0; i < 10000; i++) {
       redis.opsForHash().put("big_user", "field" + i, "value" + i);
   }
   // 转换为hashtable，占用500KB+
   ```

2. **控制字段值长度**：
   ```java
   // ✅ 好：保持值简短
   redis.opsForHash().put("product:1", "price", "99.99");  // 5字节

   // ❌ 不好：存储长JSON
   redis.opsForHash().put("product:1", "detail", longJsonString);  // 超过64字节
   // 触发编码转换
   ```

3. **Set存储整数**：
   ```java
   // ✅ 好：利用intset
   redis.opsForSet().add("user:followers:" + userId, followerId1, followerId2);

   // ❌ 不好：混入字符串
   redis.opsForSet().add("user:followers:" + userId, "follower_" + followerId);
   // 转换为hashtable
   ```

### 6.2 监控编码状态

```java
// 检查对象编码
public String checkEncoding(String key) {
    return redis.execute((RedisCallback<String>) connection -> {
        byte[] result = connection.execute("OBJECT", "ENCODING".getBytes(), key.getBytes());
        return new String(result);
    });
}

// 批量检查
public void monitorEncodings() {
    Set<String> keys = redis.keys("user:*");
    Map<String, Long> encodingStats = new HashMap<>();

    for (String key : keys) {
        String encoding = checkEncoding(key);
        encodingStats.merge(encoding, 1L, Long::sum);
    }

    System.out.println("Encoding statistics: " + encodingStats);
    // 输出示例：{ziplist=950, hashtable=50}
    // 说明：95%的Hash使用紧凑编码，内存利用率高
}
```

## 七、总结

### 7.1 核心要点

1. **整数集合（intset）**
   - 有序数组，变长编码（int16/int32/int64）
   - 查找O(logN)，插入/删除O(N)
   - 适合小数据量、所有元素都是整数的Set
   - 内存节省90%+

2. **压缩列表（ziplist）**
   - 连续内存，变长编码
   - 支持双向遍历（prevlen字段）
   - 存在连锁更新问题（概率低）
   - Redis 7.0前用于Hash、ZSet、List

3. **紧凑列表（listpack）**
   - ziplist的改进版，解决连锁更新
   - 用backlen代替prevlen
   - Redis 7.0+替代ziplist

4. **编码转换**
   - 小数据量：紧凑编码（节省内存）
   - 大数据量：高性能编码（提升速度）
   - 转换单向，不可逆

5. **性能权衡**
   - 小对象（< 100元素）：紧凑编码优势明显
   - 大对象（> 1000元素）：转换为高性能编码

### 7.2 设计哲学

Redis的内存优化体现了精妙的工程权衡：

1. **针对实际场景优化**：大多数对象都很小（< 100元素）
2. **双重编码策略**：小对象节省内存，大对象保证性能
3. **渐进式转换**：随着数据增长自动切换编码
4. **极致优化**：变长编码、立即数、连续内存，每个字节都精打细算

### 7.3 下一篇预告

理解了底层数据结构后，你是否好奇：**Redis是单线程的，为什么还能达到10万+QPS？单线程模型有什么优势？**

下一篇《单线程模型：为什么Redis这么快？》，我们将深入剖析Redis的事件驱动架构，理解单线程高性能的秘密。

---

**思考题**：
1. 为什么intset的升级是单向的，不会降级？
2. ziplist的连锁更新在什么场景下最容易发生？
3. 如果你设计一个内存数据库，会如何在性能和内存之间权衡？

欢迎在评论区分享你的思考！
