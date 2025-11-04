---
title: 并发集合：从HashMap到ConcurrentHashMap的演进
date: 2025-11-03T10:00:00+08:00
draft: false
tags:
  - Java
  - 并发编程
  - ConcurrentHashMap
  - 并发集合
  - 第一性原理
categories:
  - Java生态
series:
  - Java并发编程第一性原理
weight: 5
description: 深度剖析Java并发集合的设计哲学：从HashMap的死循环问题到ConcurrentHashMap的分段锁演进，从BlockingQueue的阻塞机制到CopyOnWriteArrayList的写时复制。通过源码分析和性能对比，掌握高并发场景下的集合选择艺术。
---

## 引子：一个缓存系统的并发灾难

假设你正在开发一个高并发的缓存系统，使用HashMap存储缓存数据。看似简单的设计，却可能导致系统崩溃。

### 场景：本地缓存的并发问题

```java
/**
 * 方案1：使用HashMap（线程不安全）
 */
public class UnsafeCache {
    private Map<String, String> cache = new HashMap<>();

    public void put(String key, String value) {
        cache.put(key, value);
    }

    public String get(String key) {
        return cache.get(key);
    }

    public static void main(String[] args) throws InterruptedException {
        UnsafeCache cache = new UnsafeCache();

        // 10个线程并发写入
        Thread[] threads = new Thread[10];
        for (int i = 0; i < 10; i++) {
            final int threadId = i;
            threads[i] = new Thread(() -> {
                for (int j = 0; j < 1000; j++) {
                    cache.put("key-" + threadId + "-" + j, "value-" + j);
                }
            });
        }

        for (Thread t : threads) t.start();
        for (Thread t : threads) t.join();

        System.out.println("缓存大小：" + cache.cache.size());
        System.out.println("期望大小：10000");
    }
}

/*
执行结果（多次运行）：
第1次：缓存大小：9856  ❌ 数据丢失
第2次：缓存大小：9923  ❌ 数据丢失
第3次：程序卡死      ❌ 死循环（JDK 1.7）
第4次：抛出ConcurrentModificationException

问题列表：
1. 数据丢失（最常见）
   └─ 多个线程同时put，覆盖彼此的修改

2. 死循环（JDK 1.7的经典Bug）
   └─ 扩容时形成环形链表，get()陷入死循环

3. ConcurrentModificationException
   └─ 迭代时其他线程修改了HashMap

4. 数据不一致
   └─ size()返回错误的值

真实案例：
某公司生产环境，使用HashMap作为本地缓存
高峰期CPU飙到100%，经排查是HashMap死循环
导致服务不可用，损失数百万
*/
```

---

### 解决方案演进

```java
/**
 * 方案2：使用Hashtable（线程安全，但性能差）
 */
public class HashtableCache {
    private Map<String, String> cache = new Hashtable<>();

    public void put(String key, String value) {
        cache.put(key, value);
    }

    public String get(String key) {
        return cache.get(key);
    }
}

/*
Hashtable的问题：
1. 整个方法都加synchronized（粗粒度锁）
2. 读写都加锁（读也需要互斥）
3. 性能差（高并发场景）

性能测试：
并发读写10000次
├─ HashMap（不安全）：50ms
├─ Hashtable（安全）：500ms
└─ 性能下降10倍！
*/

/**
 * 方案3：使用Collections.synchronizedMap（性能同样差）
 */
public class SynchronizedMapCache {
    private Map<String, String> cache = Collections.synchronizedMap(new HashMap<>());

    public void put(String key, String value) {
        cache.put(key, value);
    }

    public String get(String key) {
        return cache.get(key);
    }
}

/*
Collections.synchronizedMap的实现：
public V put(K key, V value) {
    synchronized (mutex) {  // 全局锁
        return m.put(key, value);
    }
}

问题：与Hashtable相同，粗粒度锁
*/

/**
 * 方案4：使用ConcurrentHashMap（最佳方案）
 */
public class ConcurrentHashMapCache {
    private Map<String, String> cache = new ConcurrentHashMap<>();

    public void put(String key, String value) {
        cache.put(key, value);
    }

    public String get(String key) {
        return cache.get(key);
    }

    public static void main(String[] args) throws InterruptedException {
        ConcurrentHashMapCache cache = new ConcurrentHashMapCache();

        // 10个线程并发写入
        Thread[] threads = new Thread[10];
        for (int i = 0; i < 10; i++) {
            final int threadId = i;
            threads[i] = new Thread(() -> {
                for (int j = 0; j < 1000; j++) {
                    cache.put("key-" + threadId + "-" + j, "value-" + j);
                }
            });
        }

        long start = System.currentTimeMillis();
        for (Thread t : threads) t.start();
        for (Thread t : threads) t.join();
        long end = System.currentTimeMillis();

        System.out.println("缓存大小：" + cache.cache.size());
        System.out.println("期望大小：10000");
        System.out.println("耗时：" + (end - start) + "ms");
    }
}

/*
执行结果：
缓存大小：10000  ✅ 正确
期望大小：10000
耗时：65ms

ConcurrentHashMap的优势：
1. 线程安全
2. 性能好（细粒度锁/无锁）
3. 读操作无锁（大部分情况）
4. 不会死循环
*/
```

---

### 性能对比总结

| 方案 | 线程安全 | 读性能 | 写性能 | 适用场景 |
|-----|---------|-------|-------|---------|
| **HashMap** | ❌ | 极快 | 极快 | 单线程 |
| **Hashtable** | ✅ | 慢（加锁） | 慢（加锁） | 低并发 |
| **SynchronizedMap** | ✅ | 慢（加锁） | 慢（加锁） | 低并发 |
| **ConcurrentHashMap** | ✅ | 快（无锁） | 较快（细粒度锁） | 高并发 |

**核心洞察**：
```
并发集合的设计哲学：
1. 安全性：必须保证线程安全
2. 性能：尽可能减少锁竞争
3. 可扩展性：支持高并发访问

ConcurrentHashMap的价值：
├─ 安全性：通过分段锁/CAS保证线程安全
├─ 高性能：读操作无锁，写操作细粒度锁
└─ 可扩展性：支持并发扩容
```

本文将深入剖析ConcurrentHashMap和其他并发集合的设计原理。

---

## 一、HashMap的线程安全问题

### 1.1 数据丢失问题

```java
/**
 * HashMap数据丢失的根本原因
 */
public class HashMapDataLoss {
    /*
    问题根源：put操作不是原子的

    HashMap的put方法（简化）：
    public V put(K key, V value) {
        // 1. 计算hash
        int hash = hash(key);

        // 2. 定位桶
        int i = indexFor(hash, table.length);

        // 3. 遍历链表，查找key
        for (Entry<K,V> e = table[i]; e != null; e = e.next) {
            if (e.hash == hash && (e.key == key || key.equals(e.key))) {
                V oldValue = e.value;
                e.value = value;  // 更新值
                return oldValue;
            }
        }

        // 4. 未找到，添加新节点
        addEntry(hash, key, value, i);
        return null;
    }

    并发场景下的问题：
    时间  线程A                    线程B
    t1   计算hash，定位桶[0]
    t2                           计算hash，定位桶[0]
    t3   遍历链表，未找到
    t4                           遍历链表，未找到
    t5   addEntry(k1, v1)
    t6                           addEntry(k2, v2)  ← 覆盖了A的节点

    结果：k1的数据丢失

    为什么会覆盖？
    addEntry会在链表头部插入新节点
    如果两个线程同时插入，后插入的会覆盖先插入的
    */

    public static void main(String[] args) throws InterruptedException {
        Map<Integer, Integer> map = new HashMap<>();
        AtomicInteger lostCount = new AtomicInteger(0);

        // 10个线程并发put
        Thread[] threads = new Thread[10];
        for (int i = 0; i < 10; i++) {
            final int threadId = i;
            threads[i] = new Thread(() -> {
                for (int j = 0; j < 1000; j++) {
                    map.put(threadId * 1000 + j, j);
                }
            });
        }

        for (Thread t : threads) t.start();
        for (Thread t : threads) t.join();

        // 检查数据丢失
        int expected = 10000;
        int actual = map.size();
        System.out.println("期望大小：" + expected);
        System.out.println("实际大小：" + actual);
        System.out.println("丢失数据：" + (expected - actual));
    }
}

/*
执行结果（示例）：
期望大小：10000
实际大小：9847
丢失数据：153

数据丢失的三种情况：
1. 同时插入同一个桶，覆盖
2. 同时扩容，丢失部分数据
3. 同时修改，覆盖
*/
```

---

### 1.2 死循环问题（JDK 1.7经典Bug）

```java
/**
 * HashMap死循环问题（JDK 1.7）
 */
public class HashMapDeadLoop {
    /*
    JDK 1.7的HashMap在扩容时使用头插法
    并发扩容会导致环形链表，进而导致死循环

    扩容过程（transfer方法，简化）：
    void transfer(Entry[] newTable) {
        Entry[] src = table;
        for (int j = 0; j < src.length; j++) {
            Entry<K,V> e = src[j];
            if (e != null) {
                src[j] = null;
                do {
                    Entry<K,V> next = e.next;  // ← 关键点
                    int i = indexFor(e.hash, newTable.length);
                    e.next = newTable[i];      // ← 头插法
                    newTable[i] = e;
                    e = next;
                } while (e != null);
            }
        }
    }

    死循环产生过程：
    假设原HashMap：
    table[3] → Entry(3) → Entry(7) → null

    扩容后应该：
    table[3] → Entry(3) → null
    table[7] → Entry(7) → null

    并发扩容时：
    时间  线程A                         线程B
    t1   e = Entry(3)
         next = Entry(7)
    t2                                 e = Entry(3)
                                       next = Entry(7)
    t3                                 执行完整的transfer
                                       newTable[3] → Entry(7) → Entry(3) → null
    t4   继续执行transfer
         e.next = newTable[3]
         → Entry(3).next = Entry(7)
    t5   e = next = Entry(7)
         next = Entry(7).next = Entry(3)  ← 此时形成环！
    t6   e.next = Entry(3)
         → Entry(7).next = Entry(3)
    t7   e = next = Entry(3)
         next = Entry(3).next = Entry(7)
    t8   e.next = Entry(7)
         → Entry(3).next = Entry(7)

    最终结果：
    Entry(3) ↔ Entry(7)  （环形链表）

    get()时的死循环：
    public V get(Object key) {
        int hash = hash(key);
        int i = indexFor(hash, table.length);
        for (Entry<K,V> e = table[i]; e != null; e = e.next) {
            // e = Entry(3) → Entry(7) → Entry(3) → Entry(7) → ...
            // 永远不会为null，死循环！
        }
    }
    */

    public static void main(String[] args) throws InterruptedException {
        /*
        注意：JDK 8+已修复此问题（改用尾插法）
        但仍然不是线程安全的

        JDK 1.7的死循环问题：
        1. 高并发场景下，HashMap扩容
        2. 多个线程同时扩容
        3. 形成环形链表
        4. get()陷入死循环
        5. CPU 100%，系统卡死

        解决方案：
        ├─ 使用ConcurrentHashMap
        ├─ 或者外部加锁
        └─ 或者使用ThreadLocal
        */
        System.out.println("JDK版本：" + System.getProperty("java.version"));
        System.out.println("JDK 8+已修复死循环问题，但HashMap仍不是线程安全的");
    }
}
```

---

### 1.3 为什么不能用Collections.synchronizedMap？

```java
/**
 * Collections.synchronizedMap的问题
 */
public class SynchronizedMapProblem {
    public static void main(String[] args) throws InterruptedException {
        Map<String, String> map = Collections.synchronizedMap(new HashMap<>());

        // 问题1：复合操作不是原子的
        demonstrateProblem1(map);

        Thread.sleep(1000);

        // 问题2：迭代时需要外部同步
        demonstrateProblem2(map);
    }

    // 问题1：复合操作不是原子的
    private static void demonstrateProblem1(Map<String, String> map) {
        map.put("key", "0");

        // 多个线程并发执行：get + put
        Thread[] threads = new Thread[10];
        for (int i = 0; i < 10; i++) {
            threads[i] = new Thread(() -> {
                for (int j = 0; j < 100; j++) {
                    // 复合操作：先get，再put
                    String value = map.get("key");
                    int num = Integer.parseInt(value);
                    map.put("key", String.valueOf(num + 1));
                }
            });
        }

        try {
            for (Thread t : threads) t.start();
            for (Thread t : threads) t.join();
        } catch (InterruptedException e) {
            e.printStackTrace();
        }

        System.out.println("期望值：1000");
        System.out.println("实际值：" + map.get("key"));
        // 实际值可能是856（小于1000，数据丢失）

        /*
        原因：
        虽然get()和put()各自是线程安全的
        但get() + put()这个复合操作不是原子的

        时间  线程A           线程B
        t1   get("key")=0
        t2                  get("key")=0
        t3   put("key", 1)
        t4                  put("key", 1)  ← 覆盖了A的修改

        解决方案：
        // 错误写法
        String value = map.get("key");
        map.put("key", String.valueOf(Integer.parseInt(value) + 1));

        // 正确写法（ConcurrentHashMap）
        map.compute("key", (k, v) -> String.valueOf(Integer.parseInt(v) + 1));
        */
    }

    // 问题2：迭代时需要外部同步
    private static void demonstrateProblem2(Map<String, String> map) {
        map.clear();
        for (int i = 0; i < 100; i++) {
            map.put("key-" + i, "value-" + i);
        }

        // 线程1：迭代
        Thread t1 = new Thread(() -> {
            try {
                for (String key : map.keySet()) {
                    System.out.println(key);
                    Thread.sleep(10);
                }
            } catch (Exception e) {
                System.out.println("迭代异常：" + e.getClass().getSimpleName());
            }
        });

        // 线程2：修改
        Thread t2 = new Thread(() -> {
            try {
                Thread.sleep(50);
                map.put("new-key", "new-value");
            } catch (InterruptedException e) {
                e.printStackTrace();
            }
        });

        try {
            t1.start();
            t2.start();
            t1.join();
            t2.join();
        } catch (InterruptedException e) {
            e.printStackTrace();
        }

        /*
        可能抛出：ConcurrentModificationException

        原因：
        虽然map本身是线程安全的
        但迭代器不是线程安全的

        解决方案：
        1. 外部同步
        synchronized (map) {
            for (String key : map.keySet()) {
                // ...
            }
        }

        2. 使用ConcurrentHashMap（推荐）
        ConcurrentHashMap不会抛ConcurrentModificationException
        但迭代器是弱一致性的
        */
    }
}

/*
Collections.synchronizedMap vs ConcurrentHashMap：

| 特性 | SynchronizedMap | ConcurrentHashMap |
|-----|----------------|-------------------|
| 锁粒度 | 粗粒度（整个Map） | 细粒度（桶级别） |
| 读性能 | 差（加锁） | 好（无锁） |
| 写性能 | 差（加锁） | 较好（细粒度锁） |
| 迭代 | 需要外部同步 | 弱一致性迭代器 |
| 复合操作 | 需要外部同步 | 提供原子方法 |
| 适用场景 | 低并发 | 高并发 |

结论：
高并发场景，优先使用ConcurrentHashMap
*/
```

---

## 二、ConcurrentHashMap深度剖析

### 2.1 JDK 1.7：分段锁（Segment）

```java
/**
 * JDK 1.7的ConcurrentHashMap设计
 */
public class ConcurrentHashMapJDK7 {
    /*
    核心思想：分段锁（Lock Striping）

    数据结构：
    ┌─────────────────────────────────────┐
    │ ConcurrentHashMap                   │
    ├─────────────────────────────────────┤
    │ Segment[] segments                  │  ← 默认16个Segment
    │   ├─ Segment[0]  (extends ReentrantLock)
    │   │   ├─ HashEntry[] table
    │   │   │   ├─ HashEntry[0] → Entry → Entry → null
    │   │   │   ├─ HashEntry[1] → Entry → null
    │   │   │   └─ ...
    │   │
    │   ├─ Segment[1]
    │   ├─ Segment[2]
    │   └─ ...
    └─────────────────────────────────────┘

    关键点：
    1. Segment数组，默认16个（concurrencyLevel）
    2. 每个Segment是一个小HashMap
    3. 每个Segment继承ReentrantLock
    4. 不同Segment之间可以并发访问

    并发度：
    ├─ 最大并发度 = Segment数量 = 16
    ├─ 16个线程可以同时写入（访问不同Segment）
    └─ 访问同一个Segment的线程需要竞争锁

    put操作：
    public V put(K key, V value) {
        int hash = hash(key);
        // 1. 定位Segment
        int segmentIndex = (hash >>> segmentShift) & segmentMask;
        Segment<K,V> segment = segments[segmentIndex];

        // 2. Segment内部加锁
        return segment.put(key, hash, value);
    }

    Segment内部的put：
    V put(K key, int hash, V value) {
        lock();  // 加锁（ReentrantLock）
        try {
            // 与HashMap的put类似
            // 定位桶，遍历链表，插入或更新
        } finally {
            unlock();
        }
    }

    get操作：
    public V get(Object key) {
        int hash = hash(key);
        int segmentIndex = (hash >>> segmentShift) & segmentMask;
        Segment<K,V> segment = segments[segmentIndex];

        // get操作不加锁！（大部分情况）
        return segment.get(key, hash);
    }

    Segment内部的get：
    V get(Object key, int hash) {
        // 不加锁，使用volatile读
        // HashEntry的value和next都是volatile
        for (HashEntry<K,V> e = getFirst(hash); e != null; e = e.next) {
            if (e.hash == hash && key.equals(e.key))
                return e.value;  // volatile读
        }
        return null;
    }

    优势：
    1. 并发度高（最多16个线程并发写）
    2. 读操作无锁（使用volatile）
    3. 写操作细粒度锁（只锁一个Segment）

    劣势：
    1. 并发度固定（Segment数量固定）
    2. 内存占用较大（每个Segment都有HashEntry数组）
    3. size()操作复杂（需要锁定所有Segment）
    */
}
```

---

### 2.2 JDK 1.8：CAS + synchronized

```java
/**
 * JDK 1.8的ConcurrentHashMap设计
 */
public class ConcurrentHashMapJDK8 {
    /*
    核心变化：抛弃Segment，改用CAS + synchronized

    数据结构：
    ┌─────────────────────────────────┐
    │ ConcurrentHashMap               │
    ├─────────────────────────────────┤
    │ Node[] table                    │
    │   ├─ Node[0] → Node → Node → null
    │   ├─ Node[1] → TreeNode (红黑树)
    │   ├─ Node[2] → null
    │   └─ ...
    └─────────────────────────────────┘

    关键点：
    1. 取消Segment，直接使用Node数组
    2. 数组 + 链表 + 红黑树（链表长度>8时转换）
    3. CAS + synchronized保证线程安全
    4. 锁粒度更细（桶级别，而不是Segment级别）

    并发度：
    ├─ 理论并发度 = table.length（桶的数量）
    ├─ 动态扩容，并发度随之增加
    └─ 远高于JDK 1.7的固定16

    put操作（简化）：
    */

    static class SimplePut {
        private Node[] table;

        public Object put(Object key, Object value) {
            int hash = hash(key);

            for (;;) {  // 自旋
                Node[] tab = table;
                int n = tab.length;
                int i = (n - 1) & hash;  // 定位桶
                Node f = tab[i];  // 首节点

                if (f == null) {
                    // 桶为空，使用CAS插入（无锁）
                    if (casTabAt(tab, i, null, new Node(hash, key, value))) {
                        break;  // 插入成功
                    }
                    // CAS失败，继续自旋
                } else {
                    // 桶不为空，使用synchronized
                    synchronized (f) {  // 锁住首节点
                        if (tab[i] == f) {  // 再次检查
                            // 遍历链表或红黑树，插入或更新
                            // ...
                        }
                    }
                    break;
                }
            }
            return null;
        }

        private int hash(Object key) { return 0; }
        private boolean casTabAt(Node[] tab, int i, Node c, Node v) { return true; }
        static class Node {
            Node(int hash, Object key, Object value) {}
        }
    }

    /*
    关键优化：

    1. 空桶插入：CAS（无锁）
       ├─ 首次插入某个桶，使用CAS
       ├─ 无锁，性能高
       └─ 失败则重试

    2. 非空桶插入：synchronized（细粒度锁）
       ├─ 只锁首节点（桶级别）
       ├─ 不同桶之间完全并发
       └─ 锁粒度比Segment小得多

    3. 读操作：无锁
       ├─ Node的val和next都是volatile
       ├─ 读操作直接读取，无需加锁
       └─ 性能极高

    get操作（简化）：
    public V get(Object key) {
        Node[] tab = table;
        int n = tab.length;
        int hash = hash(key);
        Node e = tab[(n - 1) & hash];  // 定位桶

        // 遍历链表或红黑树，无锁
        for (; e != null; e = e.next) {
            if (e.hash == hash && key.equals(e.key))
                return e.val;  // volatile读
        }
        return null;
    }

    size操作：
    ├─ JDK 1.7：需要锁定所有Segment，性能差
    ├─ JDK 1.8：使用baseCount + counterCells
    └─ 类似LongAdder的思想，性能好

    扩容机制（协助扩容）：
    ├─ 发现正在扩容的线程，会帮助扩容
    ├─ 多个线程并发扩容，提高速度
    └─ 扩容完成后，旧table被废弃

    JDK 1.7 vs JDK 1.8：

    | 特性 | JDK 1.7 | JDK 1.8 |
    |-----|---------|---------|
    | 数据结构 | Segment + HashEntry | Node数组 + 链表/红黑树 |
    | 并发度 | 固定16 | 动态（table.length） |
    | 空桶插入 | 加锁 | CAS（无锁） |
    | 非空桶插入 | 加锁（Segment） | 加锁（首节点） |
    | 锁粒度 | Segment级别 | 桶级别 |
    | 读操作 | 无锁（volatile） | 无锁（volatile） |
    | size() | 锁定所有Segment | baseCount + counterCells |
    | 内存占用 | 较大 | 较小 |

    结论：
    JDK 1.8的ConcurrentHashMap性能更好
    ├─ 更细的锁粒度
    ├─ 更高的并发度
    ├─ 更低的内存占用
    └─ 更快的扩容速度
    */
}
```

---

### 2.3 putVal方法源码剖析

```java
/**
 * JDK 1.8 ConcurrentHashMap.putVal源码分析
 */
public class PutValAnalysis {
    /*
    完整的putVal方法（精简注释版）：
    */

    static class SimpleConcurrentHashMap {
        static class Node {
            final int hash;
            final Object key;
            volatile Object val;  // volatile
            volatile Node next;   // volatile

            Node(int hash, Object key, Object val, Node next) {
                this.hash = hash;
                this.key = key;
                this.val = val;
                this.next = next;
            }
        }

        private transient volatile Node[] table;

        final Object putVal(Object key, Object value, boolean onlyIfAbsent) {
            if (key == null || value == null) throw new NullPointerException();

            int hash = hash(key);  // 计算hash
            int binCount = 0;  // 链表长度计数器

            for (Node[] tab = table;;) {  // 自旋
                Node f; int n, i, fh;

                if (tab == null || (n = tab.length) == 0) {
                    // 情况1：表未初始化，初始化
                    tab = initTable();
                }
                else if ((f = tabAt(tab, i = (n - 1) & hash)) == null) {
                    // 情况2：桶为空，CAS插入（无锁）
                    if (casTabAt(tab, i, null, new Node(hash, key, value, null)))
                        break;  // CAS成功，退出循环
                    // CAS失败，继续自旋
                }
                else if ((fh = f.hash) == MOVED) {
                    // 情况3：正在扩容，帮助扩容
                    tab = helpTransfer(tab, f);
                }
                else {
                    // 情况4：桶不为空，加锁插入
                    Object oldVal = null;
                    synchronized (f) {  // 锁住首节点
                        if (tabAt(tab, i) == f) {  // 双重检查
                            if (fh >= 0) {  // 链表
                                binCount = 1;
                                for (Node e = f;; ++binCount) {
                                    Object ek;
                                    if (e.hash == hash &&
                                        ((ek = e.key) == key ||
                                         (ek != null && key.equals(ek)))) {
                                        // 找到相同key，更新value
                                        oldVal = e.val;
                                        if (!onlyIfAbsent)
                                            e.val = value;
                                        break;
                                    }
                                    Node pred = e;
                                    if ((e = e.next) == null) {
                                        // 到达链表尾部，插入新节点
                                        pred.next = new Node(hash, key, value, null);
                                        break;
                                    }
                                }
                            }
                            else if (f instanceof TreeBin) {  // 红黑树
                                // 红黑树插入逻辑
                                binCount = 2;
                                // ...
                            }
                        }
                    }

                    if (binCount != 0) {
                        // 链表长度>=8，转换为红黑树
                        if (binCount >= TREEIFY_THRESHOLD)
                            treeifyBin(tab, i);
                        if (oldVal != null)
                            return oldVal;
                        break;
                    }
                }
            }

            // 增加计数
            addCount(1L, binCount);
            return null;
        }

        // 辅助方法
        private int hash(Object key) { return 0; }
        private Node[] initTable() { return null; }
        private Node tabAt(Node[] tab, int i) { return null; }
        private boolean casTabAt(Node[] tab, int i, Node c, Node v) { return true; }
        private Node[] helpTransfer(Node[] tab, Node f) { return null; }
        private void treeifyBin(Node[] tab, int i) {}
        private void addCount(long x, int check) {}
        private static final int MOVED = -1;
        private static final int TREEIFY_THRESHOLD = 8;
    }

    /*
    关键流程：

    1. 初始化检查
       ├─ 如果表未初始化，调用initTable()
       └─ 使用sizeCtl控制初始化（CAS）

    2. 空桶插入
       ├─ 使用CAS插入首节点
       ├─ 无锁，性能高
       └─ 失败则重试

    3. 扩容协助
       ├─ 检测到MOVED标记（正在扩容）
       ├─ 调用helpTransfer()帮助扩容
       └─ 扩容完成后继续插入

    4. 链表/红黑树插入
       ├─ synchronized锁住首节点
       ├─ 遍历链表或红黑树
       ├─ 插入或更新
       └─ 链表长度>=8，转换为红黑树

    5. 计数更新
       ├─ addCount()增加元素计数
       ├─ 使用baseCount + counterCells
       └─ 类似LongAdder的分段计数

    性能优化点：

    1. CAS无锁插入
       ├─ 空桶插入无需加锁
       ├─ 减少锁竞争
       └─ 提高并发度

    2. synchronized锁粒度小
       ├─ 只锁首节点
       ├─ 不同桶完全并发
       └─ 比Segment锁粒度小得多

    3. 扩容协助机制
       ├─ 多线程并发扩容
       ├─ 加快扩容速度
       └─ 减少扩容对性能的影响

    4. 红黑树优化
       ├─ 链表过长影响性能
       ├─ 转换为红黑树（O(log n)）
       └─ JDK 1.8新增优化
    */
}
```

---

### 2.4 size()方法的实现

```java
/**
 * ConcurrentHashMap.size()的实现
 */
public class SizeImplementation {
    /*
    JDK 1.7的size()实现：
    ├─ 尝试2次不加锁统计
    ├─ 如果2次结果一致，返回
    ├─ 否则锁定所有Segment，再统计
    └─ 性能较差（可能需要锁定16个Segment）

    JDK 1.8的size()实现：
    使用baseCount + counterCells（类似LongAdder）
    */

    static class CounterCell {
        volatile long value;
    }

    static class SimpleConcurrentHashMap {
        private transient volatile long baseCount;  // 基础计数
        private transient volatile CounterCell[] counterCells;  // 分段计数

        // size方法
        public int size() {
            long n = sumCount();
            return ((n < 0L) ? 0 :
                    (n > (long)Integer.MAX_VALUE) ? Integer.MAX_VALUE :
                    (int)n);
        }

        // 统计总数
        final long sumCount() {
            CounterCell[] as = counterCells;
            long sum = baseCount;  // 基础计数

            if (as != null) {
                // 累加所有CounterCell
                for (int i = 0; i < as.length; ++i) {
                    CounterCell a = as[i];
                    if (a != null)
                        sum += a.value;
                }
            }
            return sum;
        }

        // 增加计数（put时调用）
        private final void addCount(long x, int check) {
            CounterCell[] as; long b, s;

            if ((as = counterCells) != null ||
                !casBaseCount(b = baseCount, s = b + x)) {
                // 尝试CAS更新baseCount
                // 失败，使用CounterCell

                CounterCell a; long v; int m;
                boolean uncontended = true;

                // 获取当前线程的CounterCell
                if (as == null || (m = as.length - 1) < 0 ||
                    (a = as[getProbe() & m]) == null ||
                    !(uncontended = casCounterCell(a, v = a.value, v + x))) {
                    // 如果CounterCell也失败，fullAddCount
                    fullAddCount(x, uncontended);
                    return;
                }
                if (check <= 1)
                    return;
                s = sumCount();
            }

            // 检查是否需要扩容
            if (check >= 0) {
                // 扩容逻辑...
            }
        }

        private boolean casBaseCount(long cmp, long val) { return true; }
        private boolean casCounterCell(CounterCell a, long cmp, long val) { return true; }
        private void fullAddCount(long x, boolean wasUncontended) {}
        private int getProbe() { return 0; }
    }

    /*
    设计思想（借鉴LongAdder）：

    1. 低并发：
       └─ 直接CAS更新baseCount

    2. 高并发（CAS冲突）：
       ├─ 为每个线程分配一个CounterCell
       ├─ 线程在自己的CounterCell上累加
       └─ 减少竞争

    3. 获取总数：
       └─ sum = baseCount + Σ(counterCells[i].value)

    优势：
    ├─ 无锁（大部分情况）
    ├─ 高并发性能好
    └─ size()非强一致性（最终一致性）

    注意：
    size()返回的是一个近似值（弱一致性）
    ├─ 在统计过程中，可能有新的元素插入
    ├─ 返回值可能不是精确的实时值
    └─ 但对于高并发场景，这是可接受的
    */
}
```

---

## 三、BlockingQueue家族

### 3.1 阻塞队列的核心价值

```java
/**
 * BlockingQueue：生产者-消费者的最佳实践
 */
public class BlockingQueueValue {
    /*
    BlockingQueue的核心特性：
    1. 线程安全
    2. 阻塞操作
       ├─ put：队列满时阻塞
       └─ take：队列空时阻塞

    四组API：

    | 操作 | 抛异常 | 返回特殊值 | 阻塞 | 超时 |
    |-----|--------|----------|------|------|
    | 插入 | add(e) | offer(e) | put(e) | offer(e,time,unit) |
    | 删除 | remove() | poll() | take() | poll(time,unit) |
    | 检查 | element() | peek() | - | - |

    使用场景：
    1. 生产者-消费者模式
    2. 线程池的任务队列
    3. 消息队列
    4. 限流
    */

    public static void main(String[] args) throws InterruptedException {
        // 示例：生产者-消费者模式
        BlockingQueue<String> queue = new ArrayBlockingQueue<>(10);

        // 生产者
        Thread producer = new Thread(() -> {
            try {
                for (int i = 0; i < 20; i++) {
                    String product = "产品-" + i;
                    queue.put(product);  // 队列满时阻塞
                    System.out.println("生产：" + product + "，队列大小：" + queue.size());
                    Thread.sleep(100);
                }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        });

        // 消费者
        Thread consumer = new Thread(() -> {
            try {
                while (true) {
                    String product = queue.take();  // 队列空时阻塞
                    System.out.println("消费：" + product + "，队列大小：" + queue.size());
                    Thread.sleep(200);  // 消费速度慢于生产速度
                }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        });

        producer.start();
        consumer.start();

        Thread.sleep(5000);
        consumer.interrupt();

        /*
        执行结果：
        生产：产品-0，队列大小：1
        消费：产品-0，队列大小：0
        生产：产品-1，队列大小：1
        生产：产品-2，队列大小：2
        消费：产品-1，队列大小：1
        ...
        生产：产品-10，队列大小：10  ← 队列满
        （生产者阻塞，等待消费者消费）
        消费：产品-2，队列大小：9   ← 消费者消费
        生产：产品-11，队列大小：10  ← 生产者继续

        关键点：
        1. 队列满时，生产者自动阻塞
        2. 队列空时，消费者自动阻塞
        3. 无需手动wait/notify
        4. 代码简洁，线程安全
        */
    }
}
```

---

### 3.2 ArrayBlockingQueue vs LinkedBlockingQueue

```java
/**
 * ArrayBlockingQueue vs LinkedBlockingQueue
 */
public class BlockingQueueComparison {
    public static void main(String[] args) throws InterruptedException {
        // ArrayBlockingQueue：有界队列，基于数组
        testArrayBlockingQueue();

        Thread.sleep(2000);

        // LinkedBlockingQueue：可选有界/无界，基于链表
        testLinkedBlockingQueue();
    }

    private static void testArrayBlockingQueue() {
        System.out.println("===== ArrayBlockingQueue =====");
        BlockingQueue<String> queue = new ArrayBlockingQueue<>(3);  // 容量3

        /*
        ArrayBlockingQueue的实现：

        public class ArrayBlockingQueue<E> extends AbstractQueue<E>
                implements BlockingQueue<E> {
            private final Object[] items;  // 数组存储
            private int takeIndex;         // 取出位置
            private int putIndex;          // 放入位置
            private int count;             // 元素数量

            private final ReentrantLock lock;  // 全局锁
            private final Condition notEmpty;  // 非空条件
            private final Condition notFull;   // 非满条件

            public void put(E e) throws InterruptedException {
                lock.lockInterruptibly();  // 加锁
                try {
                    while (count == items.length)  // 队列满
                        notFull.await();  // 阻塞等待
                    enqueue(e);  // 入队
                } finally {
                    lock.unlock();
                }
            }

            public E take() throws InterruptedException {
                lock.lockInterruptibly();  // 加锁
                try {
                    while (count == 0)  // 队列空
                        notEmpty.await();  // 阻塞等待
                    return dequeue();  // 出队
                } finally {
                    lock.unlock();
                }
            }
        }

        特点：
        1. 基于数组，固定容量
        2. 使用一把锁（putLock和takeLock是同一把锁）
        3. put和take互斥（不能同时进行）
        4. 内存占用固定
        */

        try {
            queue.put("A");
            queue.put("B");
            queue.put("C");
            System.out.println("队列：" + queue);

            // queue.put("D");  // 会阻塞，因为队列已满

            System.out.println("取出：" + queue.take());
            queue.put("D");  // 现在可以插入了
            System.out.println("队列：" + queue);
        } catch (InterruptedException e) {
            e.printStackTrace();
        }
    }

    private static void testLinkedBlockingQueue() {
        System.out.println("\n===== LinkedBlockingQueue =====");
        // 方式1：无界队列（容量Integer.MAX_VALUE）
        BlockingQueue<String> unbounded = new LinkedBlockingQueue<>();

        // 方式2：有界队列
        BlockingQueue<String> bounded = new LinkedBlockingQueue<>(3);

        /*
        LinkedBlockingQueue的实现：

        public class LinkedBlockingQueue<E> extends AbstractQueue<E>
                implements BlockingQueue<E> {
            static class Node<E> {
                E item;
                Node<E> next;
            }

            private final int capacity;  // 容量
            private final AtomicInteger count = new AtomicInteger();  // 元素数量

            private transient Node<E> head;  // 头节点
            private transient Node<E> last;  // 尾节点

            private final ReentrantLock takeLock = new ReentrantLock();  // 取锁
            private final Condition notEmpty = takeLock.newCondition();

            private final ReentrantLock putLock = new ReentrantLock();   // 放锁
            private final Condition notFull = putLock.newCondition();

            public void put(E e) throws InterruptedException {
                int c = -1;
                final ReentrantLock putLock = this.putLock;
                final AtomicInteger count = this.count;

                putLock.lockInterruptibly();  // 加放锁
                try {
                    while (count.get() == capacity)
                        notFull.await();
                    enqueue(new Node<>(e));
                    c = count.getAndIncrement();
                    if (c + 1 < capacity)
                        notFull.signal();  // 唤醒其他put线程
                } finally {
                    putLock.unlock();
                }

                if (c == 0)
                    signalNotEmpty();  // 唤醒take线程
            }

            public E take() throws InterruptedException {
                E x;
                int c = -1;
                final AtomicInteger count = this.count;
                final ReentrantLock takeLock = this.takeLock;

                takeLock.lockInterruptibly();  // 加取锁
                try {
                    while (count.get() == 0)
                        notEmpty.await();
                    x = dequeue();
                    c = count.getAndDecrement();
                    if (c > 1)
                        notEmpty.signal();  // 唤醒其他take线程
                } finally {
                    takeLock.unlock();
                }

                if (c == capacity)
                    signalNotFull();  // 唤醒put线程
                return x;
            }
        }

        特点：
        1. 基于链表，动态扩展
        2. 使用两把锁（putLock和takeLock分离）
        3. put和take可以并发进行
        4. 内存占用动态变化
        */

        try {
            bounded.put("A");
            bounded.put("B");
            bounded.put("C");
            System.out.println("队列：" + bounded);

            System.out.println("取出：" + bounded.take());
            bounded.put("D");
            System.out.println("队列：" + bounded);
        } catch (InterruptedException e) {
            e.printStackTrace();
        }
    }

    /*
    ArrayBlockingQueue vs LinkedBlockingQueue：

    | 特性 | ArrayBlockingQueue | LinkedBlockingQueue |
    |-----|-------------------|---------------------|
    | 数据结构 | 数组 | 链表 |
    | 容量 | 必须指定 | 可选（默认无界） |
    | 锁 | 1把锁（put和take互斥） | 2把锁（put和take可并发） |
    | 内存占用 | 固定 | 动态 |
    | 性能（高并发） | 较低（锁竞争） | 较高（锁分离） |
    | 适用场景 | 有界队列 | 无界队列或高并发 |

    选择建议：
    1. 需要严格限制队列大小：ArrayBlockingQueue
    2. 高并发场景：LinkedBlockingQueue
    3. 内存敏感：ArrayBlockingQueue（固定内存）
    4. 默认选择：LinkedBlockingQueue（更通用）
    */
}
```

---

### 3.3 PriorityBlockingQueue与DelayQueue

```java
/**
 * 特殊的阻塞队列
 */
public class SpecialBlockingQueues {
    /*
    PriorityBlockingQueue：优先级队列
    ├─ 无界队列
    ├─ 基于堆（二叉堆）
    ├─ 元素按优先级排序
    └─ take()取出优先级最高的元素
    */

    static class Task implements Comparable<Task> {
        String name;
        int priority;

        Task(String name, int priority) {
            this.name = name;
            this.priority = priority;
        }

        @Override
        public int compareTo(Task o) {
            return Integer.compare(o.priority, this.priority);  // 优先级高的先执行
        }

        @Override
        public String toString() {
            return name + "(优先级:" + priority + ")";
        }
    }

    public static void testPriorityBlockingQueue() throws InterruptedException {
        System.out.println("===== PriorityBlockingQueue =====");

        PriorityBlockingQueue<Task> queue = new PriorityBlockingQueue<>();

        // 乱序放入
        queue.put(new Task("任务C", 1));
        queue.put(new Task("任务A", 3));
        queue.put(new Task("任务B", 2));

        // 按优先级取出
        System.out.println("取出：" + queue.take());  // 任务A(优先级:3)
        System.out.println("取出：" + queue.take());  // 任务B(优先级:2)
        System.out.println("取出：" + queue.take());  // 任务C(优先级:1)

        /*
        适用场景：
        1. 任务调度（优先级任务）
        2. 定时器
        3. 事件处理（按优先级）
        */
    }

    /*
    DelayQueue：延迟队列
    ├─ 无界队列
    ├─ 元素实现Delayed接口
    ├─ 只有到期的元素才能被取出
    └─ 基于PriorityQueue
    */

    static class DelayedTask implements Delayed {
        String name;
        long delayTime;  // 延迟时间（毫秒）
        long startTime;  // 开始时间

        DelayedTask(String name, long delayTime) {
            this.name = name;
            this.delayTime = delayTime;
            this.startTime = System.currentTimeMillis() + delayTime;
        }

        @Override
        public long getDelay(TimeUnit unit) {
            long diff = startTime - System.currentTimeMillis();
            return unit.convert(diff, TimeUnit.MILLISECONDS);
        }

        @Override
        public int compareTo(Delayed o) {
            return Long.compare(this.startTime, ((DelayedTask) o).startTime);
        }

        @Override
        public String toString() {
            return name + "(延迟" + delayTime + "ms)";
        }
    }

    public static void testDelayQueue() throws InterruptedException {
        System.out.println("\n===== DelayQueue =====");

        DelayQueue<DelayedTask> queue = new DelayQueue<>();

        // 放入延迟任务
        queue.put(new DelayedTask("任务A", 3000));  // 3秒后执行
        queue.put(new DelayedTask("任务B", 1000));  // 1秒后执行
        queue.put(new DelayedTask("任务C", 2000));  // 2秒后执行

        System.out.println("开始时间：" + System.currentTimeMillis());

        // 按到期时间取出
        while (!queue.isEmpty()) {
            DelayedTask task = queue.take();  // 阻塞直到有任务到期
            System.out.println("执行：" + task + "，当前时间：" + System.currentTimeMillis());
        }

        /*
        执行结果：
        开始时间：1635820800000
        执行：任务B(延迟1000ms)，当前时间：1635820801000  ← 1秒后
        执行：任务C(延迟2000ms)，当前时间：1635820802000  ← 2秒后
        执行：任务A(延迟3000ms)，当前时间：1635820803000  ← 3秒后

        适用场景：
        1. 定时任务调度
        2. 缓存过期
        3. 超时处理
        4. 订单延迟关闭
        */
    }

    public static void main(String[] args) throws InterruptedException {
        testPriorityBlockingQueue();
        testDelayQueue();
    }
}
```

---

## 四、CopyOnWriteArrayList

### 4.1 写时复制（COW）思想

```java
/**
 * CopyOnWriteArrayList：读多写少的最佳选择
 */
public class CopyOnWriteArrayListExample {
    /*
    核心思想：写时复制（Copy-On-Write）

    读操作：
    ├─ 直接读取原数组
    ├─ 无锁
    └─ 性能极高

    写操作：
    ├─ 复制原数组
    ├─ 在新数组上修改
    ├─ 替换原数组引用
    └─ 加锁（ReentrantLock）

    源码简化：
    */

    static class SimpleCopyOnWriteArrayList<E> {
        private volatile Object[] array;  // volatile
        private final ReentrantLock lock = new ReentrantLock();

        public boolean add(E e) {
            lock.lock();  // 加锁
            try {
                Object[] elements = array;
                int len = elements.length;

                // 复制原数组
                Object[] newElements = Arrays.copyOf(elements, len + 1);

                // 在新数组上添加元素
                newElements[len] = e;

                // 替换原数组（volatile写）
                array = newElements;
                return true;
            } finally {
                lock.unlock();
            }
        }

        public E get(int index) {
            // 直接读取，无锁
            return (E) array[index];
        }

        private static class Arrays {
            static Object[] copyOf(Object[] original, int newLength) {
                return new Object[newLength];
            }
        }
    }

    /*
    优势：
    1. 读操作完全无锁（性能极高）
    2. 读写不互斥（可以并发）
    3. 迭代器不会ConcurrentModificationException

    劣势：
    1. 写操作开销大（复制整个数组）
    2. 内存占用高（新旧两个数组）
    3. 数据一致性是最终一致性（不是实时的）

    适用场景：
    ├─ ✅ 读多写少（读操作远多于写操作）
    ├─ ✅ 数据量不大（避免复制开销过大）
    ├─ ✅ 迭代操作频繁
    └─ ❌ 写操作频繁或数据量大
    */

    public static void main(String[] args) throws InterruptedException {
        // 示例：事件监听器列表
        CopyOnWriteArrayList<String> listeners = new CopyOnWriteArrayList<>();

        // 添加监听器（写操作，不频繁）
        listeners.add("监听器1");
        listeners.add("监听器2");
        listeners.add("监听器3");

        // 触发事件（读操作，频繁）
        for (int i = 0; i < 5; i++) {
            new Thread(() -> {
                // 迭代监听器，无锁
                for (String listener : listeners) {
                    System.out.println(Thread.currentThread().getName() + " 通知：" + listener);
                }
            }).start();
        }

        Thread.sleep(100);

        // 添加新监听器（不影响正在迭代的线程）
        listeners.add("监听器4");

        /*
        关键点：
        1. 迭代器使用快照（迭代开始时的数组）
        2. 迭代过程中的修改不影响迭代器
        3. 不会抛ConcurrentModificationException
        */
    }
}
```

---

### 4.2 迭代器的弱一致性

```java
/**
 * CopyOnWriteArrayList迭代器的弱一致性
 */
public class WeakConsistencyIterator {
    public static void main(String[] args) {
        CopyOnWriteArrayList<String> list = new CopyOnWriteArrayList<>();
        list.add("A");
        list.add("B");
        list.add("C");

        // 获取迭代器
        Iterator<String> iterator = list.iterator();

        // 迭代过程中修改列表
        list.add("D");
        list.remove("A");

        // 迭代器仍然遍历旧的快照
        System.out.println("迭代器遍历：");
        while (iterator.hasNext()) {
            System.out.println(iterator.next());
        }

        System.out.println("\n实际列表：");
        System.out.println(list);

        /*
        执行结果：
        迭代器遍历：
        A
        B
        C

        实际列表：
        [B, C, D]

        解释：
        1. 迭代器创建时，保存了当时的数组快照
        2. 迭代过程中的修改，创建了新数组
        3. 迭代器仍然遍历旧数组
        4. 这就是"弱一致性"

        对比ArrayList：
        ArrayList iterator = list.iterator();
        list.add("D");  // 修改列表
        iterator.next();  // 抛ConcurrentModificationException

        CopyOnWriteArrayList iterator = list.iterator();
        list.add("D");  // 修改列表
        iterator.next();  // 正常执行，遍历旧快照
        */
    }
}
```

---

## 五、其他并发集合

### 5.1 ConcurrentLinkedQueue

```java
/**
 * ConcurrentLinkedQueue：无界非阻塞队列
 */
public class ConcurrentLinkedQueueExample {
    /*
    特点：
    1. 无界队列（理论上无限大）
    2. 非阻塞（基于CAS）
    3. 线程安全
    4. FIFO（先进先出）

    vs LinkedBlockingQueue：
    ├─ ConcurrentLinkedQueue：非阻塞，无界
    └─ LinkedBlockingQueue：阻塞，可选有界/无界

    实现原理：
    基于Michael & Scott的无锁队列算法
    使用CAS操作保证线程安全
    */

    public static void main(String[] args) throws InterruptedException {
        ConcurrentLinkedQueue<String> queue = new ConcurrentLinkedQueue<>();

        // 10个线程并发offer
        Thread[] threads = new Thread[10];
        for (int i = 0; i < 10; i++) {
            final int threadId = i;
            threads[i] = new Thread(() -> {
                for (int j = 0; j < 100; j++) {
                    queue.offer("线程" + threadId + "-" + j);
                }
            });
        }

        for (Thread t : threads) t.start();
        for (Thread t : threads) t.join();

        System.out.println("队列大小：" + queue.size());
        System.out.println("期望大小：1000");

        /*
        使用场景：
        1. 不需要阻塞的场景
        2. 无界队列
        3. 高并发场景

        注意：
        size()方法不是精确的（弱一致性）
        需要遍历整个队列，性能差
        */
    }
}
```

---

### 5.2 ConcurrentSkipListMap

```java
/**
 * ConcurrentSkipListMap：跳表实现的有序Map
 */
public class ConcurrentSkipListMapExample {
    /*
    特点：
    1. 有序Map（按key排序）
    2. 线程安全
    3. 基于跳表（Skip List）
    4. 性能：O(log n)

    vs TreeMap：
    ├─ TreeMap：非线程安全，基于红黑树
    └─ ConcurrentSkipListMap：线程安全，基于跳表

    跳表（Skip List）：
    ┌───┐                       ┌───┐
    │ 3 │─────────────────────→ │ 9 │  ← Level 2
    └───┘                       └───┘
      ↓                           ↓
    ┌───┐         ┌───┐         ┌───┐
    │ 3 │────────→│ 7 │────────→│ 9 │  ← Level 1
    └───┘         └───┘         └───┘
      ↓             ↓             ↓
    ┌───┐┌───┐┌───┐┌───┐┌───┐┌───┐
    │ 3 ││ 5 ││ 6 ││ 7 ││ 8 ││ 9 │  ← Level 0
    └───┘└───┘└───┘└───┘└───┘└───┘

    优势：
    ├─ 插入、删除、查找：O(log n)
    ├─ 无需平衡操作（比红黑树简单）
    └─ 易于并发实现（每层独立）
    */

    public static void main(String[] args) {
        ConcurrentSkipListMap<Integer, String> map = new ConcurrentSkipListMap<>();

        // 乱序插入
        map.put(5, "E");
        map.put(2, "B");
        map.put(8, "H");
        map.put(1, "A");
        map.put(9, "I");
        map.put(3, "C");

        // 按key排序输出
        System.out.println("有序输出：");
        map.forEach((k, v) -> System.out.println(k + " -> " + v));

        // 范围查询
        System.out.println("\n范围查询（3-8）：");
        map.subMap(3, 9).forEach((k, v) -> System.out.println(k + " -> " + v));

        /*
        执行结果：
        有序输出：
        1 -> A
        2 -> B
        3 -> C
        5 -> E
        8 -> H
        9 -> I

        范围查询（3-8）：
        3 -> C
        5 -> E
        8 -> H

        使用场景：
        1. 需要有序Map
        2. 高并发场景
        3. 范围查询频繁
        */
    }
}
```

---

## 六、如何选择合适的并发集合？

```
并发集合选择指南：

┌─────────────────────────────────────────────┐
│             需要什么数据结构？                │
└─────────────────────────────────────────────┘
         │
    ┌────┴────┬─────┬─────┬──────┐
    │         │     │     │      │
   Map      List  Set  Queue  其他
    │         │     │     │
    ↓         ↓     ↓     ↓
┌──────┐  ┌──────┐ ┌──────┐ ┌──────────────┐
│需要排│  │读多写│ │需要排│ │需要阻塞等待？│
│序吗？│  │少吗？│ │序吗？│ └──────────────┘
└──────┘  └──────┘ └──────┘     │
   │         │        │      ┌───┴───┐
 是│      是│     是│     是│      否│
   ↓         ↓        ↓        ↓        ↓
ConcurrentSkipListMap  ConcurrentSkipListSet  BlockingQueue  ConcurrentLinkedQueue
   │                   │
 否│                 否│
   ↓                   ↓
ConcurrentHashMap    CopyOnWriteArraySet
                      │
                      │
                   CopyOnWriteArrayList

详细对比：

1. Map类
   ├─ ConcurrentHashMap：高并发、无序
   └─ ConcurrentSkipListMap：高并发、有序

2. List类
   └─ CopyOnWriteArrayList：读多写少

3. Set类
   ├─ CopyOnWriteArraySet：读多写少
   └─ ConcurrentSkipListSet：高并发、有序

4. Queue类
   ├─ ArrayBlockingQueue：有界、阻塞
   ├─ LinkedBlockingQueue：可选有界/无界、阻塞
   ├─ PriorityBlockingQueue：无界、阻塞、有优先级
   ├─ DelayQueue：无界、阻塞、延迟
   ├─ SynchronousQueue：不存储元素、阻塞
   └─ ConcurrentLinkedQueue：无界、非阻塞

性能对比（并发读写10000次）：

| 集合 | 读性能 | 写性能 | 适用场景 |
|-----|-------|-------|---------|
| HashMap | 极快 | 极快 | 单线程 |
| Hashtable | 慢 | 慢 | 低并发 |
| ConcurrentHashMap | 快 | 较快 | 高并发 |
| CopyOnWriteArrayList | 极快 | 极慢 | 读多写少 |
| Collections.synchronizedList | 慢 | 慢 | 低并发 |

选择建议：
1. Map：优先ConcurrentHashMap
2. List：读多写少用CopyOnWriteArrayList
3. Queue：生产者-消费者用BlockingQueue
4. Set：根据需求选择CopyOnWriteArraySet或ConcurrentSkipListSet

最佳实践：
1. ✅ 高并发Map：ConcurrentHashMap
2. ✅ 线程池任务队列：LinkedBlockingQueue
3. ✅ 事件监听器列表：CopyOnWriteArrayList
4. ✅ 延迟任务：DelayQueue
5. ❌ 避免使用Hashtable、Vector（性能差）
6. ❌ 避免使用Collections.synchronizedXxx（性能差）
```

---

## 七、总结与思考

### 7.1 并发集合的设计哲学

```
核心原则：

1. 安全性优先
   ├─ 必须保证线程安全
   ├─ 避免数据丢失、死循环
   └─ 提供强一致性或弱一致性

2. 性能优化
   ├─ 减少锁竞争（细粒度锁、无锁）
   ├─ 读写分离（CopyOnWrite）
   └─ 分段锁（JDK 1.7 ConcurrentHashMap）

3. 可扩展性
   ├─ 支持高并发访问
   ├─ 动态扩容
   └─ 协助扩容

技术手段：
├─ CAS：无锁操作（空桶插入）
├─ synchronized：细粒度锁（桶级别）
├─ volatile：可见性保证
├─ 分段锁：降低竞争（JDK 1.7）
└─ 写时复制：读写分离

演进历史：
├─ JDK 1.0：Hashtable、Vector（粗粒度锁）
├─ JDK 1.5：ConcurrentHashMap（分段锁）、CopyOnWriteArrayList
├─ JDK 1.8：ConcurrentHashMap（CAS + synchronized）
└─ 未来：无锁化、更细粒度
```

---

### 7.2 常见误区

```
误区1：ConcurrentHashMap完全线程安全
❌ 错误
✅ 正确：复合操作仍需要外部同步

// 错误写法
if (!map.containsKey(key)) {
    map.put(key, value);  // 复合操作，不是原子的
}

// 正确写法
map.putIfAbsent(key, value);  // 原子操作

误区2：size()返回精确值
❌ 错误（JDK 1.8弱一致性）
✅ 正确：size()返回近似值

误区3：迭代器强一致性
❌ 错误
✅ 正确：迭代器是弱一致性的
不会抛ConcurrentModificationException
但可能看不到最新的修改

误区4：所有操作都无锁
❌ 错误
✅ 正确：
读操作无锁（volatile读）
空桶插入无锁（CAS）
非空桶插入加锁（synchronized）

误区5：性能总是更好
❌ 错误
✅ 正确：
低并发场景，HashMap可能更快
写密集场景，CopyOnWriteArrayList性能很差
```

---

## 八、下一篇预告

在最后一篇文章《并发设计模式与最佳实践》中，我们将探讨：

1. **不可变对象模式**
   - 不可变类的设计
   - String的不可变性
   - 不可变集合

2. **ThreadLocal模式**
   - ThreadLocal的使用
   - 内存泄漏问题
   - InheritableThreadLocal

3. **两阶段终止模式**
   - 如何优雅地停止线程
   - interrupt机制
   - 守护线程

4. **读写锁模式**
   - ReentrantReadWriteLock
   - StampedLock（JDK 8）
   - 读写分离思想

5. **并发编程最佳实践**
   - 性能调优技巧
   - 并发测试策略
   - 常见陷阱与避坑指南

敬请期待，这将是本系列的完结篇！

---

**本文要点回顾**：

```
HashMap的问题：
├─ 数据丢失：put操作不是原子的
├─ 死循环：JDK 1.7扩容时形成环形链表
└─ 不适合高并发场景

ConcurrentHashMap演进：
├─ JDK 1.7：Segment分段锁（并发度16）
├─ JDK 1.8：CAS + synchronized（并发度=桶数量）
├─ 空桶插入：CAS无锁
├─ 非空桶插入：synchronized锁首节点
└─ size()：baseCount + counterCells（类似LongAdder）

BlockingQueue家族：
├─ ArrayBlockingQueue：有界、1把锁
├─ LinkedBlockingQueue：可选有界/无界、2把锁
├─ PriorityBlockingQueue：优先级队列
└─ DelayQueue：延迟队列

CopyOnWriteArrayList：
├─ 写时复制（COW）
├─ 读操作无锁（性能极高）
├─ 写操作复制数组（开销大）
└─ 适用场景：读多写少

其他并发集合：
├─ ConcurrentLinkedQueue：无界非阻塞队列
└─ ConcurrentSkipListMap：跳表实现的有序Map

选择建议：
├─ 高并发Map：ConcurrentHashMap
├─ 生产者-消费者：BlockingQueue
├─ 读多写少List：CopyOnWriteArrayList
└─ 避免使用：Hashtable、Vector、Collections.synchronizedXxx
```

---

**系列文章**：
1. ✅ Java并发第一性原理：为什么并发如此困难？
2. ✅ 线程安全与同步机制：从synchronized到Lock的演进
3. ✅ 并发工具类与原子操作：无锁编程的艺术
4. ✅ 线程池与异步编程：从Thread到CompletableFuture的演进
5. ✅ **并发集合：从HashMap到ConcurrentHashMap的演进**（本文）
6. ⏳ 并发设计模式与最佳实践

---

**参考资料**：
- 《Java并发编程实战》- Brian Goetz
- 《Java并发编程的艺术》- 方腾飞、魏鹏、程晓明
- JDK源码：java.util.concurrent包
- Doug Lea, "The java.util.concurrent Synchronizer Framework"

---

**关于作者**：
专注于Java技术栈的深度研究，致力于用第一性原理思维拆解复杂技术问题。本系列文章采用渐进式复杂度模型，从"为什么"出发，系统化学习Java并发编程。

如果这篇文章对你有帮助，欢迎关注本系列的完结篇！
