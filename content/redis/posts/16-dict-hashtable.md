---
title: "字典与哈希表：渐进式rehash如何避免阻塞？"
date: 2025-01-21T20:30:00+08:00
draft: false
tags: ["Redis", "字典", "哈希表", "rehash"]
categories: ["技术"]
description: "深入Redis字典（dict）的实现原理，理解渐进式rehash机制如何在不阻塞服务的情况下完成哈希表扩容，掌握O(1)查询的秘密"
weight: 16
stage: 2
stageTitle: "架构原理篇"
---

## 引言

你是否好奇：**Redis的Hash类型如何实现O(1)的查询速度？当哈希表需要扩容时，如何避免长时间阻塞？数百万个key同时存在，Redis如何快速找到目标key？**

今天我们深入Redis字典（dict）的底层实现，揭秘渐进式rehash的精妙设计。

## 一、为什么需要字典？

### 1.1 Redis的核心数据结构

**Redis数据库本身就是一个巨大的字典**：

```
Redis数据库：
┌──────────────────────┐
│ key1 → value1 (String)│
│ key2 → value2 (Hash)  │
│ key3 → value3 (List)  │
│ ...                   │
│ keyN → valueN (ZSet)  │
└──────────────────────┘
所有key → redisObject的映射，都存储在字典中
```

**字典的使用场景**：
1. **数据库键空间**：整个Redis数据库（key → value）
2. **Hash类型**：Hash对象的底层实现
3. **ZSet类型**：ZSet的成员 → 分数映射
4. **过期键字典**：记录key的过期时间
5. **集群节点**：记录槽位与节点的映射

### 1.2 性能需求

| 操作 | 时间复杂度要求 |
|------|--------------|
| 添加键值对 | O(1) |
| 查找key | O(1) |
| 删除key | O(1) |
| 扩容 | **不能阻塞服务** |

## 二、哈希表基础

### 2.1 哈希表原理

```
哈希表 = 数组 + 链表（或其他冲突解决方法）

Key → Hash Function → Index → Value

示例：
"name" → hash("name") → 12345 → 12345 % 16 = 13 → table[13]
```

**核心优势**：O(1)时间复杂度

**核心挑战**：哈希冲突

### 2.2 哈希冲突解决

#### 方法1：链地址法（Redis采用）

```
table[0] → NULL
table[1] → ["key1", "value1"] → ["key9", "value9"] → NULL
table[2] → ["key2", "value2"] → NULL
table[3] → NULL
...

当hash(key1) % size == hash(key9) % size时发生冲突
解决：将冲突的key链接成链表
```

#### 方法2：开放寻址法

```
table[0] = ["key1", "value1"]
table[1] = NULL
table[2] = ["key2", "value2"]  # 本应在index=1，但已被占用，放到下一个位置

Redis未采用，因为：
- 删除操作复杂
- 缓存不友好（需要多次跳转）
```

### 2.3 负载因子与扩容

**负载因子（Load Factor）**：
```
load_factor = 已使用节点数 / 哈希表大小
```

**扩容时机**：
- **Java HashMap**：load_factor = 0.75
- **Redis dict**：load_factor = 1.0（正常情况），5.0（BGSAVE时推迟扩容）

**为什么要扩容？**
- 负载因子过高 → 链表变长 → 查询变慢（退化为O(n)）
- 扩容后 → 链表变短 → 查询保持O(1)

## 三、Redis字典结构

### 3.1 核心数据结构

#### 哈希表节点（dictEntry）

```c
typedef struct dictEntry {
    void *key;                // 键
    union {
        void *val;            // 值（指针）
        uint64_t u64;         // 值（无符号整数）
        int64_t s64;          // 值（有符号整数）
        double d;             // 值（浮点数）
    } v;
    struct dictEntry *next;   // 指向下一个节点（解决哈希冲突）
} dictEntry;
```

**注意**：
- **key**：通常是SDS字符串
- **v**：联合体，节省内存（只占用其中一种）
- **next**：链表指针，解决哈希冲突

#### 哈希表（dictht）

```c
typedef struct dictht {
    dictEntry **table;      // 哈希表数组（指针数组）
    unsigned long size;     // 哈希表大小（总是2的幂）
    unsigned long sizemask; // 哈希表大小掩码（size - 1）
    unsigned long used;     // 已使用节点数量
} dictht;
```

**为什么size总是2的幂？**
```c
// 计算索引位置
index = hash(key) % size;       // 慢（除法）

// 当size是2的幂时，可以优化为：
index = hash(key) & sizemask;   // 快（位运算）

// 示例：size=16, sizemask=15 (0b1111)
hash=12345 & 0b1111 = 12345 % 16  // 结果相同，但位运算更快
```

#### 字典（dict）

```c
typedef struct dict {
    dictType *type;          // 类型特定函数
    void *privdata;          // 私有数据
    dictht ht[2];            // 两个哈希表（用于渐进式rehash）
    long rehashidx;          // rehash进度（-1表示未进行）
    int iterators;           // 当前运行的迭代器数量
} dict;
```

**关键点**：
- **ht[2]**：两个哈希表，正常情况只使用`ht[0]`，rehash时使用`ht[1]`
- **rehashidx**：记录rehash的进度

### 3.2 内存布局示例

存储三个键值对：`{"name":"Redis", "age":"10", "type":"DB"}`

```
dict
├── ht[0]  (size=4, used=3)
│   ├── table[0] → NULL
│   ├── table[1] → ["name", "Redis"] → NULL
│   ├── table[2] → ["age", "10"] → ["type", "DB"] → NULL  (哈希冲突)
│   └── table[3] → NULL
└── ht[1]  (size=0, used=0)  未使用
```

## 四、渐进式rehash机制

### 4.1 为什么需要渐进式rehash？

**传统rehash的问题**：
```c
// 一次性rehash（Java HashMap）
void rehash() {
    // 1. 分配新数组（2倍大小）
    Entry[] newTable = new Entry[oldTable.length * 2];

    // 2. 遍历旧数组，重新计算索引，插入新数组
    for (Entry e : oldTable) {
        while (e != null) {
            int index = hash(e.key) & (newTable.length - 1);
            // 插入newTable[index]
            e = e.next;
        }
    }

    // 3. 替换旧数组
    table = newTable;
}

// 问题：如果oldTable有100万个key，rehash需要几百毫秒
// Redis是单线程，这段时间服务完全阻塞！
```

**Redis的解决方案：渐进式rehash**

> **核心思想**：不要一次性完成rehash，而是分多次、渐进式地完成。

### 4.2 渐进式rehash步骤

#### 步骤1：分配ht[1]空间

```c
// 触发条件：
// 1. load_factor >= 1（正常情况）
// 2. load_factor >= 5（BGSAVE时才扩容，避免写时复制的内存峰值）

int dictExpand(dict *d, unsigned long size) {
    // 1. 计算新大小（2的幂）
    unsigned long realsize = _dictNextPower(size);

    // 2. 创建新哈希表ht[1]
    dictht n;
    n.size = realsize;
    n.sizemask = realsize - 1;
    n.table = calloc(realsize, sizeof(dictEntry*));
    n.used = 0;

    // 3. 如果ht[0]为空，直接使用ht[1]
    if (d->ht[0].table == NULL) {
        d->ht[0] = n;
        return DICT_OK;
    }

    // 4. 否则，设置ht[1]，准备rehash
    d->ht[1] = n;
    d->rehashidx = 0;  // 开始rehash
    return DICT_OK;
}
```

**示例**：
```
Before:
ht[0]: size=4, used=4  (load_factor = 1.0，触发扩容)
ht[1]: (empty)

After dictExpand:
ht[0]: size=4, used=4  (保持不变)
ht[1]: size=8, used=0  (新分配，空表)
rehashidx = 0          (开始rehash)
```

#### 步骤2：渐进式迁移数据

**核心函数**：`dictRehash(dict *d, int n)`

```c
// n：本次最多迁移n个桶（不是n个元素）
int dictRehash(dict *d, int n) {
    int empty_visits = n * 10;  // 最多访问10n个空桶

    if (!dictIsRehashing(d)) return 0;

    while (n-- && d->ht[0].used != 0) {
        dictEntry *de, *nextde;

        // 1. 跳过空桶（最多跳过10n个）
        while (d->ht[0].table[d->rehashidx] == NULL) {
            d->rehashidx++;
            if (--empty_visits == 0) return 1;  // 避免阻塞过久
        }

        // 2. 迁移当前桶的所有元素
        de = d->ht[0].table[d->rehashidx];
        while (de) {
            uint64_t h;

            nextde = de->next;
            // 计算在ht[1]中的索引
            h = dictHashKey(d, de->key) & d->ht[1].sizemask;
            // 插入ht[1]（头插法）
            de->next = d->ht[1].table[h];
            d->ht[1].table[h] = de;
            d->ht[0].used--;
            d->ht[1].used++;
            de = nextde;
        }
        d->ht[0].table[d->rehashidx] = NULL;
        d->rehashidx++;
    }

    // 3. 检查是否完成
    if (d->ht[0].used == 0) {
        free(d->ht[0].table);
        d->ht[0] = d->ht[1];
        _dictReset(&d->ht[1]);
        d->rehashidx = -1;
        return 0;  // 完成
    }
    return 1;  // 未完成
}
```

**迁移示例**：
```
rehashidx=0，迁移ht[0].table[0]：
ht[0].table[0]: NULL  (跳过)
rehashidx=1

rehashidx=1，迁移ht[0].table[1]：
ht[0].table[1]: ["name","Redis"] → NULL
计算新索引：hash("name") & 7 = 3
ht[1].table[3]: ["name","Redis"] → NULL  (已迁移)
ht[0].used: 4 → 3
ht[1].used: 0 → 1
rehashidx=2

... 逐步迁移，直到ht[0].used=0
```

#### 步骤3：在每次操作中推进rehash

**关键点**：Redis在每次字典操作（增删改查）时，都会调用`dictRehash(d, 1)`，迁移1个桶。

```c
// 添加元素
int dictAdd(dict *d, void *key, void *val) {
    // 1. 如果正在rehash，先推进一步
    if (dictIsRehashing(d)) _dictRehashStep(d);

    // 2. 添加到ht[1]（如果正在rehash）
    // 或添加到ht[0]（如果未rehash）
    // ...
}

// 查找元素
dictEntry *dictFind(dict *d, const void *key) {
    // 1. 如果正在rehash，先推进一步
    if (dictIsRehashing(d)) _dictRehashStep(d);

    // 2. 先查ht[0]，再查ht[1]
    uint64_t h = dictHashKey(d, key);
    for (int table = 0; table <= 1; table++) {
        uint64_t idx = h & d->ht[table].sizemask;
        dictEntry *he = d->ht[table].table[idx];
        while (he) {
            if (key == he->key || dictCompareKeys(d, key, he->key)) {
                return he;
            }
            he = he->next;
        }
        if (!dictIsRehashing(d)) return NULL;  // 未rehash，不查ht[1]
    }
    return NULL;
}
```

**效果**：
- 每次操作（增删改查）推进rehash一点点
- 100万次操作，就完成100万个桶的迁移
- 平摊到每次操作的开销：O(1)

#### 步骤4：完成rehash

```c
if (d->ht[0].used == 0) {
    // 1. 释放ht[0]的内存
    free(d->ht[0].table);

    // 2. 将ht[1]替换为ht[0]
    d->ht[0] = d->ht[1];

    // 3. 重置ht[1]
    _dictReset(&d->ht[1]);

    // 4. 标记rehash完成
    d->rehashidx = -1;
}
```

### 4.3 渐进式rehash期间的操作

#### 查询操作

```c
// 需要同时查询ht[0]和ht[1]
dictEntry *dictFind(dict *d, const void *key) {
    _dictRehashStep(d);  // 推进rehash

    h = dictHashKey(d, key);
    // 先查ht[0]
    he = d->ht[0].table[h & d->ht[0].sizemask];
    if (he) return he;

    // 再查ht[1]（如果正在rehash）
    if (dictIsRehashing(d)) {
        he = d->ht[1].table[h & d->ht[1].sizemask];
        return he;
    }
    return NULL;
}
```

#### 插入操作

```c
// 新key直接插入ht[1]（如果正在rehash）
dictEntry *dictAddRaw(dict *d, void *key) {
    _dictRehashStep(d);  // 推进rehash

    // 如果正在rehash，插入ht[1]
    int table = dictIsRehashing(d) ? 1 : 0;
    dictht *ht = &d->ht[table];

    // 计算索引
    long index = dictHashKey(d, key) & ht->sizemask;

    // 插入节点
    dictEntry *entry = zmalloc(sizeof(*entry));
    entry->next = ht->table[index];
    ht->table[index] = entry;
    ht->used++;

    return entry;
}
```

#### 删除操作

```c
// 同时检查ht[0]和ht[1]
int dictDelete(dict *d, const void *key) {
    _dictRehashStep(d);  // 推进rehash

    h = dictHashKey(d, key);
    // 先查ht[0]
    for (table = 0; table <= 1; table++) {
        idx = h & d->ht[table].sizemask;
        // 删除节点...
        if (deleted) return DICT_OK;
        if (!dictIsRehashing(d)) break;
    }
    return DICT_ERR;
}
```

### 4.4 定时rehash

**问题**：如果长时间没有操作，rehash会停滞。

**解决**：Redis的定时任务`serverCron`会定时调用`dictRehashMilliseconds`：

```c
// 在指定时间内（默认1ms）持续rehash
int dictRehashMilliseconds(dict *d, int ms) {
    long long start = timeInMilliseconds();
    int rehashes = 0;

    while (dictRehash(d, 100)) {  // 每次迁移100个桶
        rehashes += 100;
        if (timeInMilliseconds() - start > ms) break;  // 超时退出
    }
    return rehashes;
}
```

**效果**：即使没有用户操作，rehash也会在后台逐步完成。

## 五、性能分析

### 5.1 时间复杂度

| 操作 | 平均情况 | 最坏情况 | 说明 |
|------|---------|---------|------|
| 查找 | O(1) | O(n) | 最坏情况：所有key哈希冲突到同一个桶 |
| 插入 | O(1) | O(n) | 最坏情况：查找key是否存在（冲突链很长） |
| 删除 | O(1) | O(n) | 最坏情况：查找key（冲突链很长） |
| rehash单步 | O(1) | O(n) | 最坏情况：桶内链表很长 |
| rehash总计 | O(n) | O(n) | 但分摊到n次操作中，平摊O(1) |

### 5.2 空间复杂度

**正常情况**：O(n)
- 一个哈希表：size * sizeof(dictEntry*)

**rehash期间**：O(2n)
- 两个哈希表：ht[0] + ht[1]
- 内存峰值约为正常的2倍

**优化**：
- Redis会在BGSAVE期间推迟rehash，避免写时复制的内存峰值

### 5.3 渐进式rehash的优势

| 特性 | 一次性rehash | 渐进式rehash |
|------|------------|-------------|
| **阻塞时间** | ❌ 100ms+（大字典） | ✅ <1ms（每次操作） |
| **实现复杂度** | ✅ 简单 | ❌ 复杂（维护两个表） |
| **内存峰值** | ✅ 低 | ❌ 高（2倍） |
| **查询性能** | ✅ O(1) | ✅ O(1)（查两个表） |
| **适合场景** | 小数据量 | **大数据量**（Redis） |

## 六、实战应用

### 6.1 监控rehash状态

```bash
# 查看数据库信息
127.0.0.1:6379> INFO stats
# Keyspace
db0:keys=1000000,expires=0,avg_ttl=0

# 查看内存使用
127.0.0.1:6379> INFO memory
used_memory:104857600
used_memory_human:100.00M

# 如果正在rehash，keys会显示两个哈希表的总数
# 内存占用会升高（ht[0] + ht[1]）
```

### 6.2 Java客户端观察

```java
@Service
public class RedisMonitorService {
    @Autowired
    private RedisTemplate<String, Object> redis;

    // 批量插入，观察rehash
    public void bulkInsert(int count) {
        long start = System.currentTimeMillis();

        for (int i = 0; i < count; i++) {
            redis.opsForValue().set("key:" + i, "value:" + i);

            if (i % 10000 == 0) {
                long elapsed = System.currentTimeMillis() - start;
                System.out.println("Inserted: " + i + ", Time: " + elapsed + "ms");
            }
        }

        long total = System.currentTimeMillis() - start;
        System.out.println("Total: " + total + "ms");

        // 观察：
        // - 插入速度基本稳定（渐进式rehash的平摊效果）
        // - 如果是一次性rehash，会在某个点出现明显的延迟峰值
    }
}
```

### 6.3 Hash类型的编码转换

```bash
# 小Hash使用ziplist编码
127.0.0.1:6379> HSET user name "Alice" age 25
127.0.0.1:6379> OBJECT ENCODING user
"ziplist"  # 或 "listpack"（Redis 7.0+）

# 添加大量字段，触发编码转换
127.0.0.1:6379> HSET user field1 val1 field2 val2 ... field600 val600
127.0.0.1:6379> OBJECT ENCODING user
"hashtable"  # 转换为字典

# 此时底层就是dict数据结构
# 如果继续添加，可能触发rehash
```

## 七、最佳实践

### 7.1 优化建议

✅ **推荐做法**：

1. **避免超大字典**：
   ```java
   // ❌ 不好：单个Hash存储百万级字段
   redis.opsForHash().put("giant_hash", "field" + i, "value" + i);
   // rehash时内存翻倍，可能OOM

   // ✅ 好：分片存储
   String key = "hash:" + (i % 100);  // 100个Hash分片
   redis.opsForHash().put(key, "field" + i, "value" + i);
   ```

2. **预估容量**：
   ```conf
   # 如果已知数据量，可以调整初始大小（避免频繁rehash）
   # 但Redis会自动管理，通常不需要干预
   ```

3. **监控内存**：
   ```java
   // 定期检查内存使用
   String info = redis.getClientList();
   // 如果发现内存突然翻倍，可能正在rehash大字典
   ```

### 7.2 避免的误区

❌ **反模式**：

1. **批量操作不使用Pipeline**：
   ```java
   // ❌ 不好：逐个插入，网络往返次数多
   for (int i = 0; i < 10000; i++) {
       redis.opsForValue().set("key:" + i, "value:" + i);
   }

   // ✅ 好：使用Pipeline
   redis.executePipelined((RedisCallback<Object>) connection -> {
       for (int i = 0; i < 10000; i++) {
           connection.set(("key:" + i).getBytes(), ("value:" + i).getBytes());
       }
       return null;
   });
   ```

2. **误解rehash的影响**：
   ```java
   // ❌ 错误认知：rehash会阻塞Redis
   // ✅ 正确理解：渐进式rehash，每次操作只增加微小开销（<1%）
   ```

## 八、总结

### 8.1 核心要点

1. **Redis字典结构**
   - dictEntry：键值对节点（链表解决冲突）
   - dictht：哈希表（数组+链表）
   - dict：字典（两个哈希表ht[0]和ht[1]）

2. **渐进式rehash机制**
   - **目标**：避免一次性rehash的长时间阻塞
   - **方法**：分多次、渐进式地迁移数据
   - **触发**：每次字典操作+定时任务
   - **效果**：平摊O(1)，单次操作无感知

3. **rehash步骤**
   1. 分配ht[1]空间（2倍大小）
   2. 渐进式迁移：每次操作迁移1个桶
   3. rehash期间：查询两个表，插入ht[1]
   4. 完成后：ht[1]替换ht[0]

4. **性能特点**
   - 查询：O(1) 平均
   - rehash：总O(n)，但分摊到n次操作，平摊O(1)
   - 内存：rehash期间翻倍（ht[0] + ht[1]）

5. **设计权衡**
   - 实现复杂度 ↑（维护两个表）
   - 阻塞时间 ↓（<1ms）
   - 内存峰值 ↑（2倍）
   - 适合大数据量场景 ✅

### 8.2 设计哲学

渐进式rehash体现了Redis的核心设计理念：

1. **响应时间优先**：宁可增加实现复杂度，也要保证低延迟
2. **平摊复杂度**：将大开销分摊到多次操作
3. **渐进式优化**：不追求一次到位，持续改进
4. **实用主义**：接受内存翻倍的代价，换取稳定的响应时间

### 8.3 下一篇预告

理解了字典和哈希表后，你是否好奇：**整数集合（intset）和压缩列表（ziplist）是如何节省内存的？Redis如何在性能和内存之间取得平衡？**

下一篇《整数集合与压缩列表》，我们将深入剖析Redis的内存优化数据结构，理解小数据量场景的极致优化策略。

---

**思考题**：
1. 为什么Redis的哈希表大小总是2的幂？如果不是会怎样？
2. 渐进式rehash期间，如果用户长时间不操作，会发生什么？
3. 如果要实现一个支持并发的字典，你会如何设计锁策略？

欢迎在评论区分享你的思考！
