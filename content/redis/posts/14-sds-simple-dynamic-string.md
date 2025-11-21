---
title: "SDS简单动态字符串：为什么Redis不用C字符串？"
date: 2025-01-21T20:10:00+08:00
draft: false
tags: ["Redis", "SDS", "字符串", "数据结构"]
categories: ["技术"]
description: "深入剖析Redis的SDS（简单动态字符串）实现原理，理解O(1)获取长度、二进制安全、减少内存分配等核心特性，掌握Redis字符串高性能的秘密"
weight: 14
stage: 2
stageTitle: "架构原理篇"
---

## 引言

在Redis中，我们使用`SET`和`GET`命令操作字符串，看起来和C语言的字符串没什么区别。但实际上，**Redis并没有使用C语言传统的字符串表示（以空字符'\0'结尾的字符数组），而是自己实现了一种名为SDS（Simple Dynamic String，简单动态字符串）的抽象类型**。

为什么要重新实现字符串？SDS有什么优势？今天我们深入源码，揭开SDS的神秘面纱。

## 一、C字符串的局限性

### 1.1 C字符串的表示

```c
// C语言字符串
char str[] = "Redis";

// 内存布局
+---+---+---+---+---+---+
| R | e | d | i | s | \0|
+---+---+---+---+---+---+
  0   1   2   3   4   5
```

### 1.2 存在的问题

#### 问题1：获取字符串长度O(n)

```c
// 需要遍历整个字符串直到遇到'\0'
size_t len = strlen(str);  // O(n) 时间复杂度

// 对于频繁获取长度的场景（如Redis命令），性能损失严重
```

#### 问题2：不支持二进制数据

```c
// C字符串以'\0'作为结尾标志
char binary_data[] = {0x01, 0x02, 0x00, 0x03};  // ❌ 无法正确处理

// strlen会在遇到0x00时停止，认为字符串结束
// 导致无法存储图片、音频等二进制数据
```

#### 问题3：容易缓冲区溢出

```c
char dest[5] = "Hi";
char src[] = "Redis";

// ❌ 危险操作：没有检查dest空间是否足够
strcat(dest, src);  // 缓冲区溢出！破坏相邻内存
```

#### 问题4：内存重分配频繁

```c
// 字符串拼接需要重新分配内存
char *str = malloc(6);
strcpy(str, "Redis");

// 追加内容，需要重新分配
str = realloc(str, 12);  // 每次都要重新分配，性能差
strcat(str, " Fast");
```

#### 问题5：不兼容部分C函数

```c
// 很多C函数假设字符串以'\0'结尾
// 对于包含'\0'的二进制数据，这些函数无法正常工作
```

### 1.3 Redis的需求

Redis作为高性能数据库，对字符串的需求：

1. ✅ **频繁获取长度**：很多命令需要快速获取字符串长度
2. ✅ **支持二进制数据**：可以存储任意二进制数据（图片、序列化对象等）
3. ✅ **避免缓冲区溢出**：保证内存安全
4. ✅ **减少内存重分配**：优化字符串拼接性能
5. ✅ **兼容C函数**：尽量复用C标准库函数

## 二、SDS核心结构

### 2.1 结构定义（Redis 6.0+）

Redis针对不同长度的字符串，定义了5种SDS类型：

```c
// sdshdr5：长度 < 32字节（实际很少使用）
struct __attribute__ ((__packed__)) sdshdr5 {
    unsigned char flags;  // 低3位存储类型，高5位存储长度
    char buf[];           // 实际存储字符串的地方
};

// sdshdr8：长度 < 256字节
struct __attribute__ ((__packed__)) sdshdr8 {
    uint8_t len;        // 已使用长度（1字节，0-255）
    uint8_t alloc;      // 已分配长度（1字节，不包括头和'\0'）
    unsigned char flags; // 类型标志（1字节）
    char buf[];         // 字符串内容
};

// sdshdr16：长度 < 64KB
struct __attribute__ ((__packed__)) sdshdr16 {
    uint16_t len;       // 已使用长度（2字节，0-65535）
    uint16_t alloc;     // 已分配长度（2字节）
    unsigned char flags; // 类型标志（1字节）
    char buf[];         // 字符串内容
};

// sdshdr32：长度 < 4GB
struct __attribute__ ((__packed__)) sdshdr32 {
    uint32_t len;       // 已使用长度（4字节）
    uint32_t alloc;     // 已分配长度（4字节）
    unsigned char flags; // 类型标志（1字节）
    char buf[];         // 字符串内容
};

// sdshdr64：长度 >= 4GB
struct __attribute__ ((__packed__)) sdshdr64 {
    uint64_t len;       // 已使用长度（8字节）
    uint64_t alloc;     // 已分配长度（8字节）
    unsigned char flags; // 类型标志（1字节）
    char buf[];         // 字符串内容
};
```

**关键点说明**：

1. **`__attribute__ ((__packed__))`**：告诉编译器不要进行内存对齐，紧凑存储
2. **len**：当前字符串的实际长度
3. **alloc**：已分配的总长度（不包括头部和终止符）
4. **flags**：低3位标识SDS类型（sdshdr8/16/32/64）
5. **buf[]**：柔性数组，实际存储字符串内容

### 2.2 内存布局示例

以`sdshdr8`为例，存储字符串"Redis"：

```
+-------+-------+-------+---------------------------+-----+
| len=5 |alloc=5| flags | R | e | d | i | s | \0   |     |
+-------+-------+-------+---------------------------+-----+
  1字节   1字节   1字节         5字节            1字节
          ↑
          SDS指针指向这里（buf的起始位置）
```

**注意**：
- SDS指针实际指向`buf`，而非结构体起始位置
- 通过`buf[-1]`可以访问`flags`
- 通过`flags`可以确定结构体类型，进而访问`len`和`alloc`

### 2.3 获取头部信息的宏

```c
// 根据字符串指针获取SDS头部
#define SDS_HDR(T,s) ((struct sdshdr##T *)((s)-(sizeof(struct sdshdr##T))))

// 获取len字段
static inline size_t sdslen(const sds s) {
    unsigned char flags = s[-1];
    switch(flags & SDS_TYPE_MASK) {
        case SDS_TYPE_5:
            return SDS_TYPE_5_LEN(flags);
        case SDS_TYPE_8:
            return SDS_HDR(8,s)->len;
        case SDS_TYPE_16:
            return SDS_HDR(16,s)->len;
        case SDS_TYPE_32:
            return SDS_HDR(32,s)->len;
        case SDS_TYPE_64:
            return SDS_HDR(64,s)->len;
    }
    return 0;
}
```

## 三、SDS的核心优势

### 3.1 优势1：O(1)获取字符串长度

```c
// C字符串：O(n)
size_t len = strlen(cstr);  // 需要遍历

// SDS：O(1)
size_t len = sdslen(sds);   // 直接读取len字段
```

**实战场景**：
```bash
# STRLEN命令可以瞬间返回结果
127.0.0.1:6379> SET longstr "一个超长的字符串..."
127.0.0.1:6379> STRLEN longstr
(integer) 1000000  # O(1)时间复杂度，无论字符串多长
```

### 3.2 优势2：二进制安全

```c
// SDS不依赖'\0'判断结束，而是通过len字段
sds s = sdsnewlen("\x00\x01\x02\x03", 4);  // ✅ 可以存储任意二进制数据

// 应用：存储序列化对象、图片等
```

**实战场景**：
```java
// 存储Java对象的二进制序列化数据
public void saveBinaryData() {
    byte[] data = SerializationUtils.serialize(user);  // 可能包含0x00
    redis.opsForValue().set("user:1:binary", data);   // ✅ Redis正常存储
}
```

### 3.3 优势3：杜绝缓冲区溢出

```c
// SDS会检查空间是否足够，不够会自动扩展
sds s = sdsnew("Redis");
s = sdscat(s, " is fast");  // ✅ 自动扩展，不会溢出

// 内部实现：
sds sdscatlen(sds s, const void *t, size_t len) {
    size_t curlen = sdslen(s);
    s = sdsMakeRoomFor(s, len);  // ✅ 自动检查并扩展空间
    if (s == NULL) return NULL;
    memcpy(s+curlen, t, len);
    sdssetlen(s, curlen+len);
    s[curlen+len] = '\0';
    return s;
}
```

### 3.4 优势4：空间预分配（减少内存重分配）

SDS采用**空间预分配策略**：

```c
sds sdsMakeRoomFor(sds s, size_t addlen) {
    size_t free = sdsavail(s);
    size_t len = sdslen(s);

    if (free >= addlen) return s;  // 空间足够，直接返回

    size_t newlen = len + addlen;

    // 空间预分配策略
    if (newlen < SDS_MAX_PREALLOC) {
        newlen *= 2;  // 小于1MB，翻倍分配
    } else {
        newlen += SDS_MAX_PREALLOC;  // 大于1MB，额外分配1MB
    }

    // 重新分配内存
    // ...
}
```

**预分配策略**：
- **字符串 < 1MB**：分配2倍空间（如当前10KB，分配20KB）
- **字符串 ≥ 1MB**：额外分配1MB空间

**效果**：
```c
// 连续追加100次字符串
for (int i = 0; i < 100; i++) {
    s = sdscat(s, "x");
}

// C字符串：100次内存重分配
// SDS：约7次内存重分配（每次翻倍，2/4/8/16/32/64/128）
```

### 3.5 优势5：惰性空间释放

```c
// 缩短字符串时，不立即释放内存，而是保留以备将来使用
sds s = sdsnew("Redis is awesome");  // 长度17

s = sdsrange(s, 0, 4);  // 截取"Redis"，长度5

// 此时：len=5, alloc=17
// 保留12字节未使用空间，避免将来追加时重新分配
```

**真正释放内存**：
```c
s = sdsRemoveFreeSpace(s);  // 显式释放未使用空间
```

### 3.6 优势6：兼容C字符串函数

```c
// SDS以'\0'结尾，可以直接传给C函数
sds s = sdsnew("Redis");

printf("%s\n", s);         // ✅ 兼容printf
int cmp = strcmp(s, "Redis");  // ✅ 兼容strcmp
```

## 四、SDS类型选择

Redis根据字符串长度自动选择最合适的SDS类型：

| 类型 | len/alloc字段 | 适用范围 | 头部开销 |
|------|-------------|---------|---------|
| sdshdr5 | 5 bits | < 32字节 | 1字节 |
| sdshdr8 | 1字节 | < 256字节 | 3字节 |
| sdshdr16 | 2字节 | < 64KB | 5字节 |
| sdshdr32 | 4字节 | < 4GB | 9字节 |
| sdshdr64 | 8字节 | ≥ 4GB | 17字节 |

**示例**：
```c
// 存储"hello"（5字节）
// 使用sdshdr8，头部3字节 + 内容5字节 + '\0'(1字节) = 9字节

// 存储10KB字符串
// 使用sdshdr16，头部5字节 + 内容10240字节 + '\0' = 10246字节
```

## 五、实战：SDS vs C字符串性能对比

### 5.1 字符串长度获取

```c
// 测试：获取100万次字符串长度

// C字符串
char *cstr = "这是一个很长的字符串...（1000字节）";
for (int i = 0; i < 1000000; i++) {
    size_t len = strlen(cstr);  // O(n)，每次遍历1000字节
}
// 耗时：约100ms

// SDS
sds s = sdsnew("这是一个很长的字符串...（1000字节）");
for (int i = 0; i < 1000000; i++) {
    size_t len = sdslen(s);  // O(1)，直接读取
}
// 耗时：约1ms
```

**性能提升**：100倍

### 5.2 字符串拼接

```c
// 测试：拼接1000次字符串

// C字符串
char *cstr = malloc(1);
strcpy(cstr, "");
for (int i = 0; i < 1000; i++) {
    cstr = realloc(cstr, strlen(cstr) + 2);  // 每次重新分配
    strcat(cstr, "x");
}
// 耗时：约50ms，1000次内存重分配

// SDS
sds s = sdsempty();
for (int i = 0; i < 1000; i++) {
    s = sdscat(s, "x");  // 预分配策略，约10次重分配
}
// 耗时：约5ms
```

**性能提升**：10倍

## 六、Java客户端中的SDS

### 6.1 Jedis示例

```java
import redis.clients.jedis.Jedis;

public class SdsExample {
    public static void main(String[] args) {
        Jedis jedis = new Jedis("localhost", 6379);

        // 1. 存储普通字符串（SDS自动管理）
        jedis.set("name", "Redis");

        // 2. 存储二进制数据
        byte[] key = "image:001".getBytes();
        byte[] imageData = loadImageBytes();  // 包含0x00字节
        jedis.set(key, imageData);  // ✅ SDS支持二进制安全

        // 3. 字符串追加（SDS优化内存重分配）
        jedis.append("log", "第1行日志\n");
        jedis.append("log", "第2行日志\n");
        jedis.append("log", "第3行日志\n");
        // SDS预分配空间，减少重分配次数

        // 4. 获取字符串长度（O(1)）
        long len = jedis.strlen("log");  // 直接读取SDS的len字段
        System.out.println("长度: " + len);

        jedis.close();
    }
}
```

### 6.2 二进制数据存储

```java
// 场景：缓存序列化的Java对象
public class ObjectCache {
    @Autowired
    private RedisTemplate<String, byte[]> redis;

    public void saveUser(User user) throws Exception {
        ByteArrayOutputStream bos = new ByteArrayOutputStream();
        ObjectOutputStream oos = new ObjectOutputStream(bos);
        oos.writeObject(user);
        byte[] data = bos.toByteArray();  // 二进制数据

        // ✅ SDS二进制安全，可以正确存储
        redis.opsForValue().set("user:" + user.getId(), data);
    }

    public User getUser(Long userId) throws Exception {
        byte[] data = redis.opsForValue().get("user:" + userId);
        if (data == null) return null;

        ByteArrayInputStream bis = new ByteArrayInputStream(data);
        ObjectInputStream ois = new ObjectInputStream(bis);
        return (User) ois.readObject();
    }
}
```

## 七、最佳实践

### 7.1 充分利用SDS特性

✅ **推荐做法**：

1. **直接使用字符串拼接命令**：
   ```bash
   # Redis会自动利用SDS的预分配机制优化
   APPEND log "新日志行\n"
   ```

2. **不用担心二进制数据**：
   ```java
   // 可以放心存储包含0x00的数据
   redis.set("binary_key", binaryData);
   ```

3. **利用STRLEN的O(1)特性**：
   ```java
   // 实现限流：检查日志长度
   Long logSize = redis.strlen("user:log:" + userId);
   if (logSize > MAX_LOG_SIZE) {
       // 清理日志
   }
   ```

### 7.2 避免的误区

❌ **反模式**：

1. **频繁SET整个字符串**：
   ```java
   // ❌ 不好：每次都SET整个字符串
   String log = redis.get("log");
   log += "新日志\n";
   redis.set("log", log);  // 客户端拼接 + 整体SET

   // ✅ 好：使用APPEND
   redis.append("log", "新日志\n");  // 利用SDS预分配
   ```

2. **客户端做字符串拼接**：
   ```java
   // ❌ 不好
   for (int i = 0; i < 1000; i++) {
       String str = redis.get("key");
       str += "x";
       redis.set("key", str);  // 1000次网络往返
   }

   // ✅ 好：使用Lua脚本或Pipeline
   String script = "for i=1,1000 do redis.call('APPEND','key','x') end";
   redis.eval(script);  // 1次网络往返，利用SDS优化
   ```

## 八、总结

### 8.1 核心要点

1. **SDS vs C字符串**
   - C字符串：简单但功能受限，性能差，不安全
   - SDS：针对Redis需求优化，高性能，二进制安全

2. **SDS核心结构**
   - len：当前长度（O(1)获取）
   - alloc：已分配长度（预分配策略）
   - flags：类型标识（5种类型优化内存）
   - buf：实际数据（兼容C函数）

3. **六大核心优势**
   - O(1)获取长度
   - 二进制安全
   - 杜绝缓冲区溢出
   - 空间预分配（减少重分配）
   - 惰性空间释放
   - 兼容C函数

4. **性能提升**
   - 长度获取：100倍提升
   - 字符串拼接：10倍提升
   - 内存重分配：减少90%次数

5. **类型自动选择**
   - 根据字符串长度选择sdshdr8/16/32/64
   - 平衡内存占用和表示范围

### 8.2 设计思想

SDS体现了Redis的核心设计哲学：

1. **针对场景优化**：不是通用字符串，而是为Redis场景定制
2. **空间换时间**：预分配空间换取性能提升
3. **渐进式优化**：5种类型适配不同长度，节省内存
4. **兼容性优先**：保持与C函数的兼容性

### 8.3 下一篇预告

理解了SDS字符串的实现后，你是否好奇：**有序集合ZSet是如何实现O(logN)时间复杂度的范围查询和排序的？跳表（SkipList）相比红黑树有什么优势？**

下一篇《跳表SkipList原理与实现》，我们将深入剖析Redis跳表的设计思想、实现细节和性能特点，理解为什么Redis选择跳表而不是平衡树。

---

**思考题**：
1. 为什么SDS要设计5种不同的类型（sdshdr5/8/16/32/64）？
2. 空间预分配策略为什么在1MB处有一个分界点？
3. 如果你设计一个高性能字符串库，还有哪些可以优化的点？

欢迎在评论区分享你的思考！
