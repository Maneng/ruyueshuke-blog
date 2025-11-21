---
title: 从HashMap到Redis：分布式缓存的演进
date: 2025-11-03T10:00:00+08:00
draft: false
tags:
  - Redis
  - 缓存
  - HashMap
  - Guava Cache
  - 分布式系统
  - 第一性原理
categories:
  - Java技术生态
series:
  - Redis第一性原理
weight: 38
stage: 1
stageTitle: "基础夯实篇"
description: 从最简单的HashMap开始，逐步演进到Redis分布式缓存。手写LRU缓存算法，深度剖析Redis单线程模型和IO多路复用，对比Cache Aside、Read/Write Through、Write Behind三大缓存更新策略。17000字深度技术文章。
---

## 一、引子：一个用户会话缓存的演进之路

假设你正在开发一个电商网站的用户会话管理功能。每次用户请求都需要验证身份，最初的实现是每次都查询数据库，但随着用户量增长，数据库压力越来越大。让我们看看这个功能如何一步步演进，从最简单的HashMap到最终的Redis分布式缓存。

### 1.1 场景0：无缓存（每次查数据库）

最直接的实现：每次请求都查询数据库验证用户身份。

```java
@RestController
public class UserController {

    @Autowired
    private UserRepository userRepository;

    /**
     * 获取用户信息（每次查数据库）
     * 问题：数据库压力大，响应慢
     */
    @GetMapping("/api/user/info")
    public UserVO getUserInfo(@RequestHeader("token") String token) {
        // 1. 根据token查询用户ID（查数据库）
        Long userId = tokenRepository.findUserIdByToken(token);
        if (userId == null) {
            throw new UnauthorizedException("未登录");
        }

        // 2. 查询用户详细信息（查数据库）
        User user = userRepository.findById(userId);
        if (user == null) {
            throw new UserNotFoundException("用户不存在");
        }

        return convertToVO(user);
    }
}
```

**性能数据**：

| 指标 | 数值 | 说明 |
|------|------|------|
| 平均响应时间 | 50ms | 2次SQL查询 |
| QPS上限 | 1000 | 数据库连接池限制 |
| 数据库压力 | 100% | 每次请求都查库 |

**问题**：
1. 每次请求都查数据库，数据库压力大
2. 响应慢（50ms），用户体验差
3. QPS受限于数据库性能

### 1.2 场景1：HashMap本地缓存

为了减轻数据库压力，我们引入最简单的缓存：HashMap。

```java
@RestController
public class UserController {

    @Autowired
    private UserRepository userRepository;

    // HashMap本地缓存
    private Map<String, UserVO> cache = new HashMap<>();

    /**
     * 获取用户信息（HashMap缓存）
     * 问题：无过期、无淘汰、线程不安全
     */
    @GetMapping("/api/user/info")
    public UserVO getUserInfo(@RequestHeader("token") String token) {
        // 1. 先查缓存
        UserVO cached = cache.get(token);
        if (cached != null) {
            return cached;
        }

        // 2. 缓存未命中，查数据库
        Long userId = tokenRepository.findUserIdByToken(token);
        if (userId == null) {
            throw new UnauthorizedException("未登录");
        }

        User user = userRepository.findById(userId);
        if (user == null) {
            throw new UserNotFoundException("用户不存在");
        }

        UserVO vo = convertToVO(user);

        // 3. 写入缓存
        cache.put(token, vo);

        return vo;
    }

    /**
     * 用户登出时删除缓存
     */
    @PostMapping("/api/user/logout")
    public void logout(@RequestHeader("token") String token) {
        cache.remove(token);
        tokenRepository.deleteByToken(token);
    }
}
```

**性能提升**：

| 指标 | 无缓存 | HashMap缓存 | 提升 |
|------|-------|------------|------|
| 平均响应时间 | 50ms | 1ms（命中） | 50倍 |
| QPS上限 | 1000 | 50000 | 50倍 |
| 数据库压力 | 100% | 5%（命中率95%） | 20倍降低 |

**致命问题**：

```java
// 问题1：无过期机制（内存泄漏）
// 用户登出后，如果忘记删除缓存，token会永久存在
cache.put(token, user);  // 永不过期，内存泄漏

// 问题2：无淘汰策略（内存溢出）
// 缓存无限增长，最终OOM
for (int i = 0; i < 1000000; i++) {
    cache.put("token" + i, user);  // 内存溢出
}

// 问题3：线程不安全（数据错乱）
// 多线程并发写入，可能导致数据不一致
Thread 1: cache.put("token1", user1);
Thread 2: cache.put("token1", user2);  // 覆盖了user1

// 问题4：无统计信息（无法监控）
// 无法知道命中率、缓存大小等信息
```

### 1.3 场景2：ConcurrentHashMap（线程安全）

为了解决线程安全问题，我们使用ConcurrentHashMap。

```java
@RestController
public class UserController {

    @Autowired
    private UserRepository userRepository;

    // ConcurrentHashMap线程安全
    private Map<String, UserVO> cache = new ConcurrentHashMap<>();

    @GetMapping("/api/user/info")
    public UserVO getUserInfo(@RequestHeader("token") String token) {
        // 1. 先查缓存（线程安全）
        UserVO cached = cache.get(token);
        if (cached != null) {
            return cached;
        }

        // 2. 缓存未命中，查数据库
        Long userId = tokenRepository.findUserIdByToken(token);
        if (userId == null) {
            throw new UnauthorizedException("未登录");
        }

        User user = userRepository.findById(userId);
        if (user == null) {
            throw new UserNotFoundException("用户不存在");
        }

        UserVO vo = convertToVO(user);

        // 3. 写入缓存（线程安全）
        cache.put(token, vo);

        return vo;
    }
}
```

**解决的问题**：
- ✅ 线程安全（使用分段锁，并发性能好）

**仍然存在的问题**：
- ❌ 无过期机制
- ❌ 无淘汰策略
- ❌ 无统计信息

### 1.4 场景3：Guava Cache（自动过期+淘汰）

为了解决过期和淘汰问题，我们引入Guava Cache。

```java
@Service
public class UserCacheService {

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private TokenRepository tokenRepository;

    /**
     * Guava Cache配置
     * - 最大容量：100万用户
     * - 过期时间：30分钟
     * - 淘汰策略：LRU
     * - 统计信息：命中率
     */
    private LoadingCache<String, UserVO> cache = CacheBuilder.newBuilder()
        .maximumSize(1000000)  // 最大容量100万
        .expireAfterWrite(30, TimeUnit.MINUTES)  // 写入30分钟后过期
        .recordStats()  // 记录统计信息（命中率）
        .removalListener(notification -> {
            // 缓存被删除时的回调
            log.info("缓存被删除：key={}, cause={}",
                notification.getKey(), notification.getCause());
        })
        .build(new CacheLoader<String, UserVO>() {
            @Override
            public UserVO load(String token) throws Exception {
                return loadUserFromDB(token);
            }
        });

    /**
     * 获取用户信息（Guava Cache）
     */
    public UserVO getUserInfo(String token) {
        try {
            return cache.get(token);
        } catch (ExecutionException e) {
            throw new RuntimeException("查询用户失败", e);
        }
    }

    /**
     * 从数据库加载用户
     */
    private UserVO loadUserFromDB(String token) {
        Long userId = tokenRepository.findUserIdByToken(token);
        if (userId == null) {
            throw new UnauthorizedException("未登录");
        }

        User user = userRepository.findById(userId);
        if (user == null) {
            throw new UserNotFoundException("用户不存在");
        }

        return convertToVO(user);
    }

    /**
     * 用户登出时手动删除缓存
     */
    public void logout(String token) {
        cache.invalidate(token);
        tokenRepository.deleteByToken(token);
    }

    /**
     * 获取缓存统计信息
     */
    public CacheStats getStats() {
        return cache.stats();
    }
}
```

**性能数据**：

```java
// 缓存统计信息
CacheStats stats = userCacheService.getStats();
System.out.println("命中次数：" + stats.hitCount());        // 950000
System.out.println("未命中次数：" + stats.missCount());      // 50000
System.out.println("命中率：" + stats.hitRate());           // 0.95（95%）
System.out.println("加载次数：" + stats.loadCount());       // 50000
System.out.println("平均加载时间：" + stats.averageLoadPenalty() / 1000000 + "ms");  // 50ms
```

**解决的问题**：
- ✅ 自动过期（expireAfterWrite、expireAfterAccess）
- ✅ 自动淘汰（LRU，基于最大容量）
- ✅ 线程安全（内部使用ConcurrentHashMap）
- ✅ 统计信息（命中率、加载时间）
- ✅ 自动加载（CacheLoader）

**仍然存在的问题**：
- ❌ 单机缓存，多台服务器无法共享
- ❌ 数据不一致（服务器A更新了，服务器B不知道）
- ❌ 内存浪费（每台服务器都缓存相同数据）

### 1.5 场景4：Redis（分布式缓存）

为了解决多台服务器之间的数据共享问题，我们引入Redis。

```java
@Service
public class UserCacheService {

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private TokenRepository tokenRepository;

    @Autowired
    private RedisTemplate<String, UserVO> redisTemplate;

    /**
     * 获取用户信息（Redis缓存）
     */
    public UserVO getUserInfo(String token) {
        String cacheKey = "user:token:" + token;

        // 1. 先查Redis
        UserVO cached = redisTemplate.opsForValue().get(cacheKey);
        if (cached != null) {
            return cached;
        }

        // 2. Redis未命中，查数据库（加分布式锁防止缓存击穿）
        String lockKey = "lock:user:" + token;
        try {
            Boolean locked = redisTemplate.opsForValue().setIfAbsent(
                lockKey, "1", 10, TimeUnit.SECONDS
            );

            if (Boolean.TRUE.equals(locked)) {
                // 双重检查
                cached = redisTemplate.opsForValue().get(cacheKey);
                if (cached != null) {
                    return cached;
                }

                // 查数据库
                UserVO vo = loadUserFromDB(token);

                // 写入Redis（30分钟过期）
                redisTemplate.opsForValue().set(cacheKey, vo, 30, TimeUnit.MINUTES);

                return vo;
            } else {
                // 获取锁失败，等待后重试
                Thread.sleep(100);
                return getUserInfo(token);
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new RuntimeException("获取用户信息失败", e);
        } finally {
            redisTemplate.delete(lockKey);
        }
    }

    /**
     * 用户登出时删除Redis缓存（所有服务器都会感知到）
     */
    public void logout(String token) {
        String cacheKey = "user:token:" + token;
        redisTemplate.delete(cacheKey);
        tokenRepository.deleteByToken(token);
    }

    /**
     * 从数据库加载用户
     */
    private UserVO loadUserFromDB(String token) {
        Long userId = tokenRepository.findUserIdByToken(token);
        if (userId == null) {
            throw new UnauthorizedException("未登录");
        }

        User user = userRepository.findById(userId);
        if (user == null) {
            throw new UserNotFoundException("用户不存在");
        }

        return convertToVO(user);
    }
}
```

**性能对比总结**：

| 方案 | 响应时间 | QPS | 数据一致性 | 过期机制 | 淘汰策略 | 统计信息 | 分布式 |
|------|---------|-----|-----------|---------|---------|---------|--------|
| 无缓存 | 50ms | 1000 | ✅ 强一致 | N/A | N/A | ❌ | N/A |
| HashMap | 1ms | 50000 | ✅ 强一致 | ❌ | ❌ | ❌ | ❌ |
| ConcurrentHashMap | 1ms | 50000 | ✅ 强一致 | ❌ | ❌ | ❌ | ❌ |
| Guava Cache | 1ms | 50000 | ❌ 不一致 | ✅ | ✅ | ✅ | ❌ |
| **Redis** | **2ms** | **100000** | **✅ 强一致** | **✅** | **✅** | **✅** | **✅** |

**核心结论**：
1. HashMap → ConcurrentHashMap：解决线程安全问题
2. ConcurrentHashMap → Guava Cache：增加过期、淘汰、统计功能
3. Guava Cache → Redis：解决分布式一致性问题

---

## 二、手写LRU缓存：理解缓存淘汰的本质

在深入理解Redis之前，让我们先手写一个LRU（Least Recently Used，最近最少使用）缓存，理解缓存淘汰的本质。

### 2.1 LRU算法原理

**LRU算法**：当缓存满了，淘汰最近最少使用的数据。

**核心思想**：
- 如果数据最近被访问过，那么将来被访问的概率也高
- 如果数据很久没被访问，那么将来被访问的概率也低

**数据结构**：双向链表 + 哈希表

```
哈希表：O(1)查找
双向链表：O(1)移动节点到头部、O(1)删除尾部节点

缓存结构：
  head → [key1, value1] ⇄ [key2, value2] ⇄ [key3, value3] ← tail
         (最近使用)                              (最久未使用)

操作：
1. get(key)：
   - 如果key存在，将节点移到head（标记为最近使用）
   - 如果key不存在，返回null

2. put(key, value)：
   - 如果key存在，更新value，将节点移到head
   - 如果key不存在：
     - 如果缓存未满，插入新节点到head
     - 如果缓存已满，删除tail节点，插入新节点到head
```

### 2.2 手写LRU缓存（200行代码）

```java
/**
 * 手写LRU缓存
 * @param <K> 键类型
 * @param <V> 值类型
 */
public class LRUCache<K, V> {

    /**
     * 双向链表节点
     */
    private static class Node<K, V> {
        K key;
        V value;
        Node<K, V> prev;
        Node<K, V> next;

        Node(K key, V value) {
            this.key = key;
            this.value = value;
        }
    }

    private final int capacity;  // 最大容量
    private final Map<K, Node<K, V>> map;  // 哈希表
    private final Node<K, V> head;  // 虚拟头节点
    private final Node<K, V> tail;  // 虚拟尾节点

    public LRUCache(int capacity) {
        if (capacity <= 0) {
            throw new IllegalArgumentException("容量必须大于0");
        }
        this.capacity = capacity;
        this.map = new HashMap<>(capacity);

        // 初始化虚拟头尾节点
        this.head = new Node<>(null, null);
        this.tail = new Node<>(null, null);
        head.next = tail;
        tail.prev = head;
    }

    /**
     * 获取缓存值
     * @param key 键
     * @return 值，不存在返回null
     */
    public V get(K key) {
        Node<K, V> node = map.get(key);
        if (node == null) {
            return null;
        }

        // 将节点移到头部（标记为最近使用）
        moveToHead(node);

        return node.value;
    }

    /**
     * 放入缓存
     * @param key 键
     * @param value 值
     */
    public void put(K key, V value) {
        Node<K, V> node = map.get(key);

        if (node != null) {
            // key已存在，更新value
            node.value = value;
            moveToHead(node);
        } else {
            // key不存在，插入新节点
            Node<K, V> newNode = new Node<>(key, value);

            if (map.size() >= capacity) {
                // 缓存已满，删除尾部节点（最久未使用）
                Node<K, V> tailNode = removeTail();
                map.remove(tailNode.key);
            }

            // 插入新节点到头部
            addToHead(newNode);
            map.put(key, newNode);
        }
    }

    /**
     * 删除缓存
     * @param key 键
     */
    public void remove(K key) {
        Node<K, V> node = map.get(key);
        if (node != null) {
            removeNode(node);
            map.remove(key);
        }
    }

    /**
     * 获取缓存大小
     */
    public int size() {
        return map.size();
    }

    /**
     * 清空缓存
     */
    public void clear() {
        map.clear();
        head.next = tail;
        tail.prev = head;
    }

    /**
     * 将节点移到头部
     */
    private void moveToHead(Node<K, V> node) {
        removeNode(node);
        addToHead(node);
    }

    /**
     * 将节点添加到头部
     */
    private void addToHead(Node<K, V> node) {
        node.prev = head;
        node.next = head.next;
        head.next.prev = node;
        head.next = node;
    }

    /**
     * 删除节点
     */
    private void removeNode(Node<K, V> node) {
        node.prev.next = node.next;
        node.next.prev = node.prev;
    }

    /**
     * 删除尾部节点
     */
    private Node<K, V> removeTail() {
        Node<K, V> node = tail.prev;
        removeNode(node);
        return node;
    }

    /**
     * 打印缓存（从头到尾）
     */
    public void print() {
        StringBuilder sb = new StringBuilder("LRU Cache: [");
        Node<K, V> current = head.next;
        while (current != tail) {
            sb.append(current.key).append("=").append(current.value);
            if (current.next != tail) {
                sb.append(", ");
            }
            current = current.next;
        }
        sb.append("]");
        System.out.println(sb);
    }
}
```

### 2.3 测试LRU缓存

```java
public class LRUCacheTest {

    public static void main(String[] args) {
        // 创建容量为3的LRU缓存
        LRUCache<Integer, String> cache = new LRUCache<>(3);

        System.out.println("=== 测试1：插入数据 ===");
        cache.put(1, "A");
        cache.print();  // [1=A]

        cache.put(2, "B");
        cache.print();  // [2=B, 1=A]

        cache.put(3, "C");
        cache.print();  // [3=C, 2=B, 1=A]

        System.out.println("\n=== 测试2：缓存已满，插入新数据，淘汰最久未使用的 ===");
        cache.put(4, "D");  // 淘汰key=1
        cache.print();  // [4=D, 3=C, 2=B]

        System.out.println("\n=== 测试3：访问数据，将其移到头部 ===");
        String value = cache.get(2);  // 访问key=2
        System.out.println("get(2) = " + value);
        cache.print();  // [2=B, 4=D, 3=C]

        System.out.println("\n=== 测试4：插入新数据，淘汰最久未使用的 ===");
        cache.put(5, "E");  // 淘汰key=3（最久未使用）
        cache.print();  // [5=E, 2=B, 4=D]

        System.out.println("\n=== 测试5：更新已存在的key ===");
        cache.put(2, "B_new");  // 更新key=2
        cache.print();  // [2=B_new, 5=E, 4=D]

        System.out.println("\n=== 测试6：删除缓存 ===");
        cache.remove(5);
        cache.print();  // [2=B_new, 4=D]
    }
}
```

**输出结果**：

```
=== 测试1：插入数据 ===
LRU Cache: [1=A]
LRU Cache: [2=B, 1=A]
LRU Cache: [3=C, 2=B, 1=A]

=== 测试2：缓存已满，插入新数据，淘汰最久未使用的 ===
LRU Cache: [4=D, 3=C, 2=B]

=== 测试3：访问数据，将其移到头部 ===
get(2) = B
LRU Cache: [2=B, 4=D, 3=C]

=== 测试4：插入新数据，淘汰最久未使用的 ===
LRU Cache: [5=E, 2=B, 4=D]

=== 测试5：更新已存在的key ===
LRU Cache: [2=B_new, 5=E, 4=D]

=== 测试6：删除缓存 ===
LRU Cache: [2=B_new, 4=D]
```

**时间复杂度分析**：

| 操作 | 时间复杂度 | 说明 |
|------|-----------|------|
| get(key) | O(1) | 哈希表查找 + 双向链表移动节点 |
| put(key, value) | O(1) | 哈希表插入 + 双向链表插入/删除 |
| remove(key) | O(1) | 哈希表删除 + 双向链表删除 |

**空间复杂度**：O(capacity)

---

## 三、Redis深度剖析：为什么这么快？

### 3.1 Redis单线程模型

很多人疑惑：Redis是单线程的，为什么还这么快？

**核心原因**：

```
1. 纯内存操作（最核心）
   - 数据存储在内存，访问速度100ns
   - 避免磁盘IO（数据库需要10ms+）

2. 单线程避免了多线程竞争
   - 无需加锁，无上下文切换开销
   - 简单高效的事件驱动模型

3. IO多路复用（epoll）
   - 单线程监听多个客户端连接
   - 避免了为每个连接创建线程的开销

4. 高效的数据结构
   - SDS（Simple Dynamic String）：比C字符串更高效
   - ziplist：压缩列表，节省内存
   - skiplist：跳表，O(logN)查找

5. 优化的底层实现
   - 渐进式rehash：避免阻塞
   - 惰性删除：避免阻塞
   - 内存分配器优化（jemalloc）
```

### 3.2 Redis单线程模型详解

```
Redis单线程模型：

  ┌─────────────────────────────────────────┐
  │         Redis Server（单线程）           │
  │                                         │
  │  ┌────────────────────────────────┐   │
  │  │  Event Loop（事件循环）         │   │
  │  │                                 │   │
  │  │  1. epoll_wait()                │   │
  │  │     等待客户端请求（阻塞）       │   │
  │  │                                 │   │
  │  │  2. 处理文件事件（读取命令）     │   │
  │  │     read() → 读取客户端请求     │   │
  │  │                                 │   │
  │  │  3. 执行命令（内存操作）         │   │
  │  │     GET/SET/INCR...            │   │
  │  │                                 │   │
  │  │  4. 返回结果（写入响应）         │   │
  │  │     write() → 写入响应到客户端  │   │
  │  │                                 │   │
  │  │  5. 处理时间事件（后台任务）     │   │
  │  │     过期key删除、AOF刷盘...     │   │
  │  │                                 │   │
  │  │  6. 回到步骤1                   │   │
  │  └────────────────────────────────┘   │
  │                                         │
  └─────────────────────────────────────────┘

关键点：
1. 单线程串行处理所有命令（Redis 6.0之前）
2. IO多路复用监听多个客户端连接
3. 内存操作极快，单线程足够
```

### 3.3 IO多路复用（epoll）

**传统多线程模型**：

```java
// 为每个客户端创建一个线程（开销大）
while (true) {
    Socket client = serverSocket.accept();  // 阻塞等待连接
    new Thread(() -> {
        // 处理客户端请求
        while (true) {
            String request = client.read();  // 阻塞读取
            String response = process(request);
            client.write(response);
        }
    }).start();
}

问题：
├─ 线程创建开销大（1MB栈空间）
├─ 线程切换开销大（上下文切换）
├─ 线程数量有限（最多几千个）
└─ 大量线程阻塞在read()上（浪费）
```

**Redis的IO多路复用模型**：

```c
// 伪代码：Redis的事件循环
while (true) {
    // 1. epoll_wait()：监听所有客户端连接
    //    返回有数据可读的连接列表
    List<Socket> readySockets = epoll_wait(sockets);

    // 2. 遍历所有有数据可读的连接
    for (Socket socket : readySockets) {
        // 3. 读取命令（非阻塞）
        String command = socket.read();

        // 4. 执行命令（内存操作）
        String result = execute(command);

        // 5. 写入响应（非阻塞）
        socket.write(result);
    }

    // 6. 处理时间事件（后台任务）
    processTimeEvents();
}
```

**IO多路复用的优势**：

| 维度 | 传统多线程模型 | IO多路复用 | 差异 |
|------|--------------|-----------|------|
| 线程数量 | N个客户端 = N个线程 | 1个线程监听N个客户端 | N倍节省 |
| 内存占用 | N × 1MB = N MB | 几MB | 数百倍节省 |
| 上下文切换 | 频繁切换 | 无切换 | 性能提升 |
| 连接数上限 | 几千个 | 几万个 | 10倍提升 |

### 3.4 Redis 6.0多线程IO

Redis 6.0引入了多线程IO，但**命令执行仍然是单线程**。

```
Redis 6.0多线程模型：

  ┌─────────────────────────────────────────┐
  │         Redis Server（多线程）           │
  │                                         │
  │  ┌─────────────┐                       │
  │  │  IO Thread 1 │ ← 读取客户端请求       │
  │  │  IO Thread 2 │ ← 读取客户端请求       │
  │  │  IO Thread 3 │ ← 读取客户端请求       │
  │  └─────────────┘                       │
  │         ↓                               │
  │  ┌─────────────┐                       │
  │  │  Main Thread │ ← 执行命令（单线程）   │
  │  └─────────────┘                       │
  │         ↓                               │
  │  ┌─────────────┐                       │
  │  │  IO Thread 1 │ ← 写入响应到客户端     │
  │  │  IO Thread 2 │ ← 写入响应到客户端     │
  │  │  IO Thread 3 │ ← 写入响应到客户端     │
  │  └─────────────┘                       │
  │                                         │
  └─────────────────────────────────────────┘

关键点：
1. 多线程只用于网络IO（读取请求、写入响应）
2. 命令执行仍然是单线程（保证原子性）
3. 提升网络IO性能（从5万QPS提升到10万QPS）
```

**为什么命令执行仍然是单线程？**

```
原因1：保证原子性
  INCR key  # 原子操作
  如果多线程，需要加锁，反而更慢

原因2：避免竞争
  多线程需要处理锁竞争、死锁等问题
  单线程简单高效

原因3：内存操作足够快
  内存访问100ns，单线程每秒可以执行1000万次操作
  瓶颈不在CPU，而在网络IO

结论：
  Redis 6.0多线程IO解决了网络IO瓶颈
  但命令执行仍然单线程，保证简单高效
```

---

## 四、Redis客户端协议（RESP）

### 4.1 RESP协议详解

RESP（REdis Serialization Protocol）是Redis客户端和服务器之间的通信协议，设计简单高效。

**RESP数据类型**：

| 类型 | 前缀 | 示例 | 说明 |
|------|-----|------|------|
| 简单字符串 | + | `+OK\r\n` | 成功响应 |
| 错误 | - | `-ERR unknown command\r\n` | 错误响应 |
| 整数 | : | `:123\r\n` | 整数值 |
| 批量字符串 | $ | `$5\r\nhello\r\n` | 字符串（长度前缀） |
| 数组 | * | `*2\r\n$3\r\nGET\r\n$3\r\nkey\r\n` | 命令数组 |

**示例**：

```bash
# 客户端发送：GET mykey
*2\r\n          # 数组，2个元素
$3\r\n          # 批量字符串，长度3
GET\r\n         # "GET"
$5\r\n          # 批量字符串，长度5
mykey\r\n       # "mykey"

# 服务器响应：myvalue
$7\r\n          # 批量字符串，长度7
myvalue\r\n     # "myvalue"

# 服务器响应：key不存在
$-1\r\n         # NULL（长度-1）

# 服务器响应：错误
-ERR unknown command 'GETT'\r\n
```

### 4.2 手写RESP协议解析器

```java
/**
 * RESP协议解析器
 */
public class RESPParser {

    /**
     * 编码命令
     * @param args 命令参数
     * @return RESP格式字符串
     */
    public static String encodeCommand(String... args) {
        StringBuilder sb = new StringBuilder();

        // 数组标记 + 元素数量
        sb.append("*").append(args.length).append("\r\n");

        // 每个参数
        for (String arg : args) {
            // 批量字符串标记 + 长度
            sb.append("$").append(arg.length()).append("\r\n");
            // 字符串内容
            sb.append(arg).append("\r\n");
        }

        return sb.toString();
    }

    /**
     * 解析响应
     * @param response RESP格式字符串
     * @return 解析结果
     */
    public static Object parseResponse(String response) {
        if (response == null || response.isEmpty()) {
            return null;
        }

        char type = response.charAt(0);

        switch (type) {
            case '+':  // 简单字符串
                return response.substring(1, response.length() - 2);

            case '-':  // 错误
                throw new RuntimeException(response.substring(1, response.length() - 2));

            case ':':  // 整数
                return Long.parseLong(response.substring(1, response.length() - 2));

            case '$':  // 批量字符串
                int len = Integer.parseInt(
                    response.substring(1, response.indexOf("\r\n"))
                );
                if (len == -1) {
                    return null;  // NULL
                }
                int start = response.indexOf("\r\n") + 2;
                return response.substring(start, start + len);

            case '*':  // 数组
                int count = Integer.parseInt(
                    response.substring(1, response.indexOf("\r\n"))
                );
                List<Object> list = new ArrayList<>(count);
                // 递归解析每个元素
                String remaining = response.substring(response.indexOf("\r\n") + 2);
                for (int i = 0; i < count; i++) {
                    Object element = parseResponse(remaining);
                    list.add(element);
                    // 移动到下一个元素
                    remaining = remaining.substring(remaining.indexOf("\r\n") + 2);
                }
                return list;

            default:
                throw new RuntimeException("未知的RESP类型：" + type);
        }
    }

    /**
     * 测试
     */
    public static void main(String[] args) {
        // 测试编码
        System.out.println("=== 测试编码 ===");
        String command = encodeCommand("GET", "mykey");
        System.out.println(command);
        // 输出：
        // *2
        // $3
        // GET
        // $5
        // mykey

        // 测试解析
        System.out.println("\n=== 测试解析 ===");

        // 简单字符串
        String response1 = "+OK\r\n";
        System.out.println("简单字符串：" + parseResponse(response1));  // OK

        // 整数
        String response2 = ":123\r\n";
        System.out.println("整数：" + parseResponse(response2));  // 123

        // 批量字符串
        String response3 = "$5\r\nhello\r\n";
        System.out.println("批量字符串：" + parseResponse(response3));  // hello

        // NULL
        String response4 = "$-1\r\n";
        System.out.println("NULL：" + parseResponse(response4));  // null

        // 错误
        try {
            String response5 = "-ERR unknown command\r\n";
            parseResponse(response5);
        } catch (RuntimeException e) {
            System.out.println("错误：" + e.getMessage());  // ERR unknown command
        }
    }
}
```

### 4.3 简易Redis客户端实现

```java
/**
 * 简易Redis客户端
 */
public class SimpleRedisClient {

    private Socket socket;
    private OutputStream out;
    private InputStream in;

    /**
     * 连接Redis服务器
     */
    public void connect(String host, int port) throws IOException {
        socket = new Socket(host, port);
        out = socket.getOutputStream();
        in = socket.getInputStream();
    }

    /**
     * 执行命令
     * @param args 命令参数
     * @return 响应结果
     */
    public Object execute(String... args) throws IOException {
        // 1. 编码命令
        String command = RESPParser.encodeCommand(args);

        // 2. 发送命令
        out.write(command.getBytes());
        out.flush();

        // 3. 读取响应
        byte[] buffer = new byte[1024];
        int len = in.read(buffer);
        String response = new String(buffer, 0, len);

        // 4. 解析响应
        return RESPParser.parseResponse(response);
    }

    /**
     * 关闭连接
     */
    public void close() throws IOException {
        if (socket != null) {
            socket.close();
        }
    }

    /**
     * 测试
     */
    public static void main(String[] args) throws IOException {
        SimpleRedisClient client = new SimpleRedisClient();

        try {
            // 连接Redis
            client.connect("localhost", 6379);

            // SET命令
            Object result1 = client.execute("SET", "mykey", "myvalue");
            System.out.println("SET: " + result1);  // OK

            // GET命令
            Object result2 = client.execute("GET", "mykey");
            System.out.println("GET: " + result2);  // myvalue

            // INCR命令
            Object result3 = client.execute("INCR", "counter");
            System.out.println("INCR: " + result3);  // 1

            // DEL命令
            Object result4 = client.execute("DEL", "mykey");
            System.out.println("DEL: " + result4);  // 1

        } finally {
            client.close();
        }
    }
}
```

---

## 五、缓存更新策略：Cache Aside vs Read/Write Through vs Write Behind

### 5.1 Cache Aside（旁路缓存）

**最常用的模式（90%场景）**。

**读流程**：

```java
public UserVO getUserInfo(Long userId) {
    String cacheKey = "user:info:" + userId;

    // 1. 先查缓存
    UserVO cached = redisTemplate.opsForValue().get(cacheKey);
    if (cached != null) {
        return cached;  // 缓存命中
    }

    // 2. 缓存未命中，查数据库
    User user = userRepository.findById(userId);
    if (user == null) {
        // 缓存空值（防止缓存穿透）
        redisTemplate.opsForValue().set(cacheKey, new UserVO(), 1, TimeUnit.MINUTES);
        throw new UserNotFoundException();
    }

    UserVO vo = convertToVO(user);

    // 3. 写入缓存
    redisTemplate.opsForValue().set(cacheKey, vo, 30, TimeUnit.MINUTES);

    return vo;
}
```

**写流程**：

```java
@Transactional
public void updateUser(User user) {
    // 1. 先更新数据库
    userRepository.update(user);

    // 2. 再删除缓存（而不是更新缓存）
    String cacheKey = "user:info:" + user.getId();
    redisTemplate.delete(cacheKey);
}
```

**为什么删除而不是更新缓存？**

```
场景：并发更新

方案1：更新缓存
  时间线：
  T1: 线程A更新数据库（name=Alice）
  T2: 线程B更新数据库（name=Bob）
  T3: 线程B更新缓存（name=Bob）
  T4: 线程A更新缓存（name=Alice）  ← 后执行，覆盖了Bob

  结果：
    数据库：name=Bob（正确）
    缓存：  name=Alice（错误！）

方案2：删除缓存
  时间线：
  T1: 线程A更新数据库（name=Alice）
  T2: 线程B更新数据库（name=Bob）
  T3: 线程B删除缓存
  T4: 线程A删除缓存
  T5: 线程C查询，缓存未命中，查数据库，得到name=Bob（正确）

  结果：
    数据库：name=Bob（正确）
    缓存：  无（下次查询会重新加载）

结论：删除缓存更安全
```

**优劣分析**：

| 维度 | 优势 | 劣势 |
|------|-----|------|
| 一致性 | 最终一致（通常1秒内） | 有短暂不一致窗口 |
| 性能 | 读性能好 | 写性能一般（需删除缓存） |
| 复杂度 | 简单 | 需要业务代码管理缓存 |
| 适用场景 | 读多写少 | 不适合写多读少 |

### 5.2 Read/Write Through（读写穿透）

**缓存层负责同步数据库，业务代码只操作缓存**。

**架构**：

```
业务代码 → 缓存层 → 数据库
           ↑
       负责同步
```

**读流程**：

```java
// 业务代码：只操作缓存
public UserVO getUserInfo(Long userId) {
    String cacheKey = "user:info:" + userId;
    return cacheService.get(cacheKey);  // 缓存层负责查数据库
}

// 缓存层：自动从数据库加载
@Service
public class CacheService {

    @Autowired
    private RedisTemplate<String, UserVO> redisTemplate;

    @Autowired
    private UserRepository userRepository;

    public UserVO get(String cacheKey) {
        // 1. 先查缓存
        UserVO cached = redisTemplate.opsForValue().get(cacheKey);
        if (cached != null) {
            return cached;
        }

        // 2. 缓存未命中，查数据库
        Long userId = extractUserIdFromKey(cacheKey);
        User user = userRepository.findById(userId);
        if (user == null) {
            throw new UserNotFoundException();
        }

        UserVO vo = convertToVO(user);

        // 3. 写入缓存
        redisTemplate.opsForValue().set(cacheKey, vo, 30, TimeUnit.MINUTES);

        return vo;
    }
}
```

**写流程**：

```java
// 业务代码：只操作缓存
@Transactional
public void updateUser(User user) {
    String cacheKey = "user:info:" + user.getId();
    UserVO vo = convertToVO(user);
    cacheService.set(cacheKey, vo);  // 缓存层负责同步数据库
}

// 缓存层：自动同步到数据库
@Service
public class CacheService {

    @Autowired
    private RedisTemplate<String, UserVO> redisTemplate;

    @Autowired
    private UserRepository userRepository;

    public void set(String cacheKey, UserVO vo) {
        // 1. 先更新数据库
        User user = convertToEntity(vo);
        userRepository.update(user);

        // 2. 再更新缓存
        redisTemplate.opsForValue().set(cacheKey, vo, 30, TimeUnit.MINUTES);
    }
}
```

**优劣分析**：

| 维度 | 优势 | 劣势 |
|------|-----|------|
| 一致性 | 强一致（同步写数据库） | 性能较低 |
| 性能 | 一般 | 写操作需同步 |
| 复杂度 | 业务代码简单 | 缓存层复杂 |
| 适用场景 | 需要强一致性 | 不适合高并发写 |

### 5.3 Write Behind（异步写回）

**写操作只写缓存，异步批量写数据库**。

**架构**：

```
业务代码 → 缓存 → 异步队列 → 批量写数据库
```

**写流程**：

```java
// 业务代码：只写缓存
public void updateUser(User user) {
    String cacheKey = "user:info:" + user.getId();
    UserVO vo = convertToVO(user);

    // 1. 写入缓存（立即返回）
    redisTemplate.opsForValue().set(cacheKey, vo, 30, TimeUnit.MINUTES);

    // 2. 发送到异步队列
    asyncQueue.offer(new UpdateEvent(user.getId(), vo));
}

// 异步任务：批量写数据库
@Scheduled(fixedDelay = 1000)  // 每秒执行一次
public void flushToDatabase() {
    List<UpdateEvent> events = asyncQueue.poll(100);  // 批量获取
    if (events.isEmpty()) {
        return;
    }

    // 批量更新数据库
    List<User> users = events.stream()
        .map(e -> convertToEntity(e.vo))
        .collect(Collectors.toList());

    userRepository.batchUpdate(users);
}
```

**优劣分析**：

| 维度 | 优势 | 劣势 |
|------|-----|------|
| 一致性 | 最终一致（延迟1秒+） | 可能丢失数据 |
| 性能 | 写性能极高（只写缓存） | 读可能读到旧数据 |
| 复杂度 | 复杂（需异步任务） | 实现复杂 |
| 适用场景 | 日志、统计数据 | 不适合关键数据 |

### 5.4 三种策略对比

| 策略 | 一致性 | 读性能 | 写性能 | 复杂度 | 适用场景 |
|------|-------|-------|-------|-------|---------|
| **Cache Aside** | 最终一致 | 高 | 中 | 低 | 读多写少（90%场景） |
| **Read/Write Through** | 强一致 | 中 | 低 | 中 | 强一致性要求 |
| **Write Behind** | 最终一致 | 高 | 极高 | 高 | 日志、统计数据 |

**推荐**：
- **首选Cache Aside**：90%场景适用，简单高效
- **强一致性用Read/Write Through**：金融、支付场景
- **高性能写用Write Behind**：日志、监控数据

---

## 六、Redis淘汰策略详解

### 6.1 Redis内存淘汰策略

当Redis内存达到maxmemory时，会触发淘汰策略。

**8种淘汰策略**：

| 策略 | 说明 | 适用场景 |
|------|-----|---------|
| **noeviction** | 不淘汰，内存满时返回错误 | 不推荐 |
| **allkeys-lru** | 对所有key使用LRU淘汰 | **推荐（通用场景）** |
| **allkeys-lfu** | 对所有key使用LFU淘汰 | 推荐（热点数据） |
| **allkeys-random** | 随机淘汰所有key | 不推荐 |
| **volatile-lru** | 对设置了过期时间的key使用LRU | 部分key需永久保留 |
| **volatile-lfu** | 对设置了过期时间的key使用LFU | 部分key需永久保留 |
| **volatile-random** | 随机淘汰设置了过期时间的key | 不推荐 |
| **volatile-ttl** | 淘汰TTL最小的key | 按过期时间优先淘汰 |

**配置**：

```bash
# redis.conf
maxmemory 2gb
maxmemory-policy allkeys-lru
```

### 6.2 LRU vs LFU

**LRU（Least Recently Used）**：最近最少使用

```
原理：淘汰最久未访问的key
适合：时间局部性（最近访问的数据将来也会访问）

示例：
  访问序列：A B C D E A B C D E
  缓存容量：3
  淘汰顺序：A B C（最久未使用）
```

**LFU（Least Frequently Used）**：最不经常使用

```
原理：淘汰访问频率最低的key
适合：频率局部性（访问频率高的数据将来也会访问）

示例：
  访问序列：A A A B B C D D D D
  访问频率：A=3, B=2, C=1, D=4
  缓存容量：3
  淘汰顺序：C（访问频率最低）
```

**对比**：

| 维度 | LRU | LFU |
|------|-----|-----|
| 淘汰依据 | 最后访问时间 | 访问频率 |
| 实现复杂度 | 简单 | 复杂 |
| 内存开销 | 低 | 高（需记录频率） |
| 适用场景 | 通用 | 热点数据集中 |
| 缺点 | 可能淘汰高频但最近未访问的key | 新key难以进入缓存 |

**推荐**：
- **通用场景用LRU**：简单高效，适合大部分场景
- **热点数据用LFU**：访问频率差异大的场景（如热门商品）

---

## 七、总结与最佳实践

### 7.1 缓存演进路径总结

```
HashMap
  ↓ 问题：无过期、无淘汰、线程不安全
ConcurrentHashMap
  ↓ 问题：无过期、无淘汰
Guava Cache / Caffeine
  ↓ 问题：单机、无分布式
Redis
  ✅ 解决所有问题：分布式、过期、淘汰、高可用
```

### 7.2 缓存选型决策树

```
是否需要分布式？
├─ 否 → 是否需要过期/淘汰？
│       ├─ 否 → ConcurrentHashMap
│       └─ 是 → Caffeine（性能最优）
└─ 是 → 是否需要丰富数据结构？
        ├─ 否 → Memcached（极简KV）
        └─ 是 → Redis（推荐）
```

### 7.3 最佳实践

**1. 缓存Key设计**

```java
// ❌ 错误：key太短，容易冲突
redisTemplate.opsForValue().set("123", user);

// ✅ 正确：带业务前缀，含义清晰
redisTemplate.opsForValue().set("user:info:123", user);

// ✅ 正确：分层命名，便于管理
redisTemplate.opsForValue().set("ecommerce:user:info:123", user);
redisTemplate.opsForValue().set("ecommerce:product:detail:456", product);
```

**2. 缓存过期时间设置**

```java
// ❌ 错误：所有key相同过期时间（缓存雪崩）
redisTemplate.opsForValue().set(key, value, 30, TimeUnit.MINUTES);

// ✅ 正确：过期时间随机化（防止缓存雪崩）
int baseExpire = 30 * 60;  // 30分钟
int randomExpire = new Random().nextInt(60);  // 0-60秒
int expireTime = baseExpire + randomExpire;
redisTemplate.opsForValue().set(key, value, expireTime, TimeUnit.SECONDS);
```

**3. 缓存空值（防止缓存穿透）**

```java
public UserVO getUserInfo(Long userId) {
    String cacheKey = "user:info:" + userId;

    UserVO cached = redisTemplate.opsForValue().get(cacheKey);
    if (cached != null) {
        // 判断是否是空值
        if (cached.getUserId() == null) {
            throw new UserNotFoundException();
        }
        return cached;
    }

    User user = userRepository.findById(userId);
    if (user == null) {
        // ✅ 缓存空值（TTL设短一点）
        redisTemplate.opsForValue().set(cacheKey, new UserVO(), 1, TimeUnit.MINUTES);
        throw new UserNotFoundException();
    }

    UserVO vo = convertToVO(user);
    redisTemplate.opsForValue().set(cacheKey, vo, 30, TimeUnit.MINUTES);
    return vo;
}
```

**4. 分布式锁（防止缓存击穿）**

```java
public UserVO getUserInfo(Long userId) {
    String cacheKey = "user:info:" + userId;
    String lockKey = "lock:user:" + userId;

    UserVO cached = redisTemplate.opsForValue().get(cacheKey);
    if (cached != null) {
        return cached;
    }

    // ✅ 获取分布式锁（防止缓存击穿）
    Boolean locked = redisTemplate.opsForValue().setIfAbsent(
        lockKey, "1", 10, TimeUnit.SECONDS
    );

    if (Boolean.TRUE.equals(locked)) {
        try {
            // 双重检查
            cached = redisTemplate.opsForValue().get(cacheKey);
            if (cached != null) {
                return cached;
            }

            // 查数据库
            UserVO vo = loadFromDB(userId);

            // 写入缓存
            redisTemplate.opsForValue().set(cacheKey, vo, 30, TimeUnit.MINUTES);

            return vo;
        } finally {
            // ✅ 释放锁
            redisTemplate.delete(lockKey);
        }
    } else {
        // 获取锁失败，等待后重试
        Thread.sleep(100);
        return getUserInfo(userId);
    }
}
```

**5. 监控缓存命中率**

```java
@Component
public class CacheMonitor {

    private AtomicLong hitCount = new AtomicLong(0);
    private AtomicLong missCount = new AtomicLong(0);

    public void recordHit() {
        hitCount.incrementAndGet();
    }

    public void recordMiss() {
        missCount.incrementAndGet();
    }

    @Scheduled(fixedDelay = 60000)  // 每分钟输出一次
    public void printStats() {
        long hit = hitCount.get();
        long miss = missCount.get();
        double hitRate = (double) hit / (hit + miss);

        log.info("缓存统计：命中={}, 未命中={}, 命中率={:.2f}%",
            hit, miss, hitRate * 100);

        // 重置计数器
        hitCount.set(0);
        missCount.set(0);
    }
}
```

### 7.4 性能优化建议

**1. 使用Pipeline批量操作**

```java
// ❌ 错误：循环执行1000次SET（1000次网络往返）
for (int i = 0; i < 1000; i++) {
    redisTemplate.opsForValue().set("key" + i, "value" + i);
}
// 耗时：1000ms（假设每次1ms）

// ✅ 正确：使用Pipeline批量执行（1次网络往返）
redisTemplate.executePipelined((RedisCallback<Object>) connection -> {
    for (int i = 0; i < 1000; i++) {
        connection.set(("key" + i).getBytes(), ("value" + i).getBytes());
    }
    return null;
});
// 耗时：10ms（性能提升100倍）
```

**2. 避免大Key**

```java
// ❌ 错误：单个key存储100MB数据
List<String> bigList = new ArrayList<>();
for (int i = 0; i < 1000000; i++) {
    bigList.add("item" + i);
}
redisTemplate.opsForValue().set("big:list", bigList);  // 100MB

// ✅ 正确：拆分成多个小key
for (int i = 0; i < 1000; i++) {
    List<String> subList = bigList.subList(i * 1000, (i + 1) * 1000);
    redisTemplate.opsForValue().set("list:part:" + i, subList);
}
```

**3. 合理使用数据结构**

```java
// ❌ 错误：用String存储对象（序列化开销大）
redisTemplate.opsForValue().set("user:123", user);  // 序列化整个对象

// ✅ 正确：用Hash存储对象（只序列化变化的字段）
redisTemplate.opsForHash().put("user:123", "name", user.getName());
redisTemplate.opsForHash().put("user:123", "age", user.getAge());

// 更新时只更新变化的字段
redisTemplate.opsForHash().put("user:123", "age", 25);
```

---

## 八、核心要点回顾

### 8.1 缓存演进总结

```
1. HashMap → ConcurrentHashMap：解决线程安全
2. ConcurrentHashMap → Guava Cache：增加过期、淘汰
3. Guava Cache → Redis：解决分布式一致性
```

### 8.2 Redis核心优势

```
1. 单线程模型：无锁竞争，简单高效
2. IO多路复用：单线程监听多个客户端
3. 纯内存操作：访问速度100ns，比SSD快1500倍
4. 丰富数据结构：String、List、Hash、Set、ZSet等
5. 持久化能力：RDB+AOF，重启不丢数据
6. 高可用架构：主从+哨兵+集群
```

### 8.3 缓存更新策略

```
1. Cache Aside：最常用（90%场景）
2. Read/Write Through：强一致性场景
3. Write Behind：高性能写场景
```

### 8.4 下一步学习

本文是Redis系列的第2篇，后续文章将深入讲解：

1. ✅ Redis第一性原理：为什么我们需要缓存？
2. ✅ **从HashMap到Redis：分布式缓存的演进**
3. ⏳ Redis五大数据结构：从场景到实现
4. ⏳ Redis高可用架构：主从复制、哨兵、集群
5. ⏳ Redis持久化：RDB与AOF的权衡
6. ⏳ Redis实战：分布式锁、消息队列、缓存设计

---

**参考资料**：
- 《Redis设计与实现》- 黄健宏
- 《Redis实战》- Josiah L. Carlson
- Redis官方文档：https://redis.io/documentation
- Guava Cache文档：https://github.com/google/guava/wiki/CachesExplained
- Caffeine文档：https://github.com/ben-manes/caffeine

---

*本文是"Redis第一性原理"系列的第2篇，共6篇。下一篇将深入讲解《Redis五大数据结构：从场景到实现》，敬请期待。*
