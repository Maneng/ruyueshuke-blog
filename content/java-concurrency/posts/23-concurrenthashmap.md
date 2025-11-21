---
title: "Java并发23：ConcurrentHashMap原理 - 线程安全的HashMap"
date: 2025-11-20T22:00:00+08:00
draft: false
tags: ["Java并发", "ConcurrentHashMap", "分段锁", "CAS"]
categories: ["技术"]
description: "ConcurrentHashMap的演进历史、JDK 7分段锁、JDK 8 CAS+synchronized、性能优化。"
series: ["Java并发编程从入门到精通"]
weight: 23
stage: 3
stageTitle: "Lock与并发工具篇"
---

## HashMap的线程安全问题

```java
Map<String, String> map = new HashMap<>();

// 多线程并发put
map.put("key1", "value1");  // 线程1
map.put("key2", "value2");  // 线程2

// 问题1：数据丢失
// 问题2：死循环（JDK 7）
// 问题3：数据覆盖
```

**三种解决方案**：
```java
// 方案1：Hashtable（废弃）
Map<String, String> map = new Hashtable<>();  // synchronized，性能差

// 方案2：Collections.synchronizedMap
Map<String, String> map = Collections.synchronizedMap(new HashMap<>());  // 性能差

// 方案3：ConcurrentHashMap（推荐）
Map<String, String> map = new ConcurrentHashMap<>();  // 高性能
```

---

## JDK 7实现：分段锁

**核心思想**：将Map分成多个Segment，每个Segment独立加锁

```
ConcurrentHashMap
├─ Segment[0]  (ReentrantLock)
│  ├─ HashEntry[0]
│  ├─ HashEntry[1]
│  └─ ...
├─ Segment[1]  (ReentrantLock)
│  ├─ HashEntry[0]
│  └─ ...
└─ ...
```

**优点**：降低锁粒度，提高并发度
**缺点**：
- 内存占用大
- 扩容复杂
- 最多并发度 = Segment数量（默认16）

---

## JDK 8实现：CAS + synchronized

**核心变化**：
1. 取消Segment，直接用数组
2. 使用CAS + synchronized
3. 链表长度 > 8 转为红黑树

### 关键源码（简化）

```java
public V put(K key, V value) {
    int hash = spread(key.hashCode());

    for (Node<K,V>[] tab = table;;) {
        Node<K,V> f;
        int n, i, fh;

        if (tab == null || (n = tab.length) == 0)
            tab = initTable();  // 初始化

        else if ((f = tabAt(tab, i = (n - 1) & hash)) == null) {
            // 桶为空，CAS插入
            if (casTabAt(tab, i, null, new Node<K,V>(hash, key, value, null)))
                break;
        }

        else if ((fh = f.hash) == MOVED)
            tab = helpTransfer(tab, f);  // 协助扩容

        else {
            // 桶不为空，synchronized插入
            synchronized (f) {
                // 链表或红黑树插入
            }
        }
    }

    addCount(1L, binCount);
    return null;
}
```

---

## 核心机制

### 1. CAS无锁插入
```java
// 桶为空时，用CAS插入（无锁）
if (casTabAt(tab, i, null, newNode))
    break;  // 插入成功
```

### 2. synchronized锁桶
```java
// 桶不为空，锁住头节点
synchronized (头节点) {
    // 链表/红黑树插入
}
```

**优点**：
- 只锁一个桶，并发度高
- JDK 6后synchronized性能优化

### 3. 红黑树优化
```java
// 链表长度 > 8，转红黑树
if (binCount >= TREEIFY_THRESHOLD)
    treeifyBin(tab, i);
```

**优点**：O(n) → O(log n)

### 4. 扩容优化
```java
// 多线程协助扩容
if (当前正在扩容) {
    helpTransfer();  // 协助迁移数据
}
```

---

## 性能对比

| 实现 | 读性能 | 写性能 | 并发度 | 内存 |
|-----|-------|-------|--------|------|
| **Hashtable** | 差 | 差 | 1 | 低 |
| **synchronizedMap** | 差 | 差 | 1 | 低 |
| **CHM JDK 7** | 好 | 好 | 16 | 高 |
| **CHM JDK 8** | 更好 | 更好 | 无限 | 中 |

**测试代码**：
```java
// 10线程，各10万次put
Hashtable:         5800ms
synchronizedMap:   5200ms
ConcurrentHashMap: 450ms
```

---

## 重要方法

### 1. putIfAbsent
```java
// 原子操作：不存在时才put
V oldValue = map.putIfAbsent("key", "value");
if (oldValue == null) {
    // 插入成功
} else {
    // key已存在
}
```

### 2. computeIfAbsent
```java
// 原子操作：不存在时计算并put
String value = map.computeIfAbsent("key", k -> {
    return expensiveComputation(k);  // 只计算一次
});
```

### 3. merge
```java
// 原子操作：合并值
map.merge("key", 1, (oldValue, newValue) -> oldValue + newValue);
// 等价于：map.put("key", map.getOrDefault("key", 0) + 1);
```

---

## 最佳实践

**1. 初始容量设置**
```java
// 预估大小1000，负载因子0.75
int initialCapacity = (int) (1000 / 0.75) + 1;
Map<String, String> map = new ConcurrentHashMap<>(initialCapacity);
```

**2. 避免全表锁操作**
```java
// ❌ size()在JDK 7会锁所有Segment
int size = map.size();

// ✅ 使用mappingCount()
long size = map.mappingCount();  // 不加锁，返回近似值
```

**3. 批量操作**
```java
// ✅ 使用parallelStream
map.entrySet().parallelStream()
   .forEach(entry -> process(entry));
```

---

## 常见问题

**Q1：ConcurrentHashMap允许null吗？**
```java
// ❌ key和value都不允许null
map.put(null, "value");  // NullPointerException
map.put("key", null);    // NullPointerException
```

**Q2：size()准确吗？**
```java
// JDK 8：size()和mappingCount()都是近似值
// 不保证实时准确性
```

**Q3：迭代时可以修改吗？**
```java
// ✅ 弱一致性，不抛ConcurrentModificationException
for (String key : map.keySet()) {
    map.put(key + "_new", "value");  // 允许
}
```

---

## 总结

**核心要点**：
1. JDK 7：分段锁，最多并发16
2. JDK 8：CAS + synchronized，无限并发
3. 性能：远超Hashtable和synchronizedMap

**使用建议**：
- 高并发场景首选
- 不允许null
- size()是近似值
- 使用computeIfAbsent等原子方法

---

**系列文章**：
- 上一篇：[Java并发22：BlockingQueue详解](/java-concurrency/posts/22-blockingqueue/)
- 下一篇：[Java并发24：CountDownLatch与CyclicBarrier](/java-concurrency/posts/24-countdown-cyclic/) （即将发布）
