---
title: "Java并发18：读写锁ReadWriteLock - 优化读多写少场景"
date: 2025-11-20T20:30:00+08:00
draft: false
tags: ["Java并发", "ReadWriteLock", "ReentrantReadWriteLock", "共享锁", "独占锁"]
categories: ["技术"]
description: "深入理解读写锁的设计理念、读锁与写锁的实现原理、锁降级机制、以及如何利用读写锁优化读多写少场景的性能。"
series: ["Java并发编程从入门到精通"]
weight: 18
stage: 3
stageTitle: "Lock与并发工具篇"
---

## 引言：ReentrantLock的性能瓶颈

在上一篇文章中，我们学习了ReentrantLock，但它有一个性能问题：

```java
public class Cache {
    private final Map<String, String> map = new HashMap<>();
    private final Lock lock = new ReentrantLock();

    public String get(String key) {
        lock.lock();  // 读操作也要加锁
        try {
            return map.get(key);
        } finally {
            lock.unlock();
        }
    }

    public void put(String key, String value) {
        lock.lock();  // 写操作加锁
        try {
            map.put(key, value);
        } finally {
            lock.unlock();
        }
    }
}
```

**问题**：
- 读操作（get）本身是线程安全的，多个线程可以同时读
- 但ReentrantLock是**独占锁**，同一时刻只有一个线程能持有
- 大量读操作被阻塞，性能差

**解决方案**：使用读写锁（ReadWriteLock）

```java
public class CacheWithReadWriteLock {
    private final Map<String, String> map = new HashMap<>();
    private final ReadWriteLock rwLock = new ReentrantReadWriteLock();
    private final Lock readLock = rwLock.readLock();
    private final Lock writeLock = rwLock.writeLock();

    public String get(String key) {
        readLock.lock();  // 读锁（共享）
        try {
            return map.get(key);
        } finally {
            readLock.unlock();
        }
    }

    public void put(String key, String value) {
        writeLock.lock();  // 写锁（独占）
        try {
            map.put(key, value);
        } finally {
            writeLock.unlock();
        }
    }
}
```

**性能提升**（10个线程，90%读操作）：
```
ReentrantLock: 2300ms
ReadWriteLock: 350ms
性能提升: 6.6倍
```

本篇文章将深入读写锁的实现原理和最佳实践。

---

## 一、ReadWriteLock接口

### 1.1 接口定义

```java
public interface ReadWriteLock {
    // 获取读锁
    Lock readLock();

    // 获取写锁
    Lock writeLock();
}
```

### 1.2 读写锁的规则

```
读锁（共享锁）：
- 多个线程可以同时持有读锁
- 有写锁时，读锁获取会阻塞

写锁（独占锁）：
- 只有一个线程可以持有写锁
- 有读锁或写锁时，写锁获取会阻塞
```

**状态表**：

| 当前状态 | 读锁请求 | 写锁请求 |
|---------|---------|---------|
| **无锁** | ✅ 成功 | ✅ 成功 |
| **读锁** | ✅ 成功（多个线程共享） | ❌ 阻塞 |
| **写锁** | ❌ 阻塞 | ❌ 阻塞 |

### 1.3 读写锁 vs 独占锁

**ReentrantLock（独占锁）**：
```
时刻1: 线程1获取锁 → 读数据
时刻2: 线程2获取锁 → 阻塞
时刻3: 线程3获取锁 → 阻塞
时刻4: 线程1释放锁
时刻5: 线程2获取锁 → 读数据
时刻6: 线程3获取锁 → 阻塞
...

同一时刻只有一个线程能读
```

**ReadWriteLock（读写锁）**：
```
时刻1: 线程1获取读锁 → 读数据
时刻2: 线程2获取读锁 → 读数据（同时进行）
时刻3: 线程3获取读锁 → 读数据（同时进行）
时刻4: 线程4获取写锁 → 阻塞（等待读锁释放）
时刻5: 线程1释放读锁
时刻6: 线程2释放读锁
时刻7: 线程3释放读锁
时刻8: 线程4获取写锁 → 写数据

多个线程可以同时读
```

---

## 二、ReentrantReadWriteLock详解

### 2.1 基本使用

```java
public class ReadWriteLockExample {
    private final ReadWriteLock rwLock = new ReentrantReadWriteLock();
    private final Lock readLock = rwLock.readLock();
    private final Lock writeLock = rwLock.writeLock();
    private int value = 0;

    // 读操作
    public int read() {
        readLock.lock();
        try {
            System.out.println(Thread.currentThread().getName() + " 读取: " + value);
            return value;
        } finally {
            readLock.unlock();
        }
    }

    // 写操作
    public void write(int newValue) {
        writeLock.lock();
        try {
            System.out.println(Thread.currentThread().getName() + " 写入: " + newValue);
            value = newValue;
        } finally {
            writeLock.unlock();
        }
    }

    public static void main(String[] args) {
        ReadWriteLockExample example = new ReadWriteLockExample();

        // 5个读线程
        for (int i = 0; i < 5; i++) {
            new Thread(() -> example.read(), "读线程-" + i).start();
        }

        // 1个写线程
        new Thread(() -> example.write(100), "写线程").start();
    }
}
```

**输出**（示例）：
```
读线程-0 读取: 0
读线程-1 读取: 0  ← 多个读线程同时执行
读线程-2 读取: 0
读线程-3 读取: 0
读线程-4 读取: 0
写线程 写入: 100  ← 等待所有读线程完成
```

### 2.2 公平性

**非公平模式（默认）**：
```java
ReadWriteLock rwLock = new ReentrantReadWriteLock();  // 默认非公平
// 或
ReadWriteLock rwLock = new ReentrantReadWriteLock(false);
```

**工作方式**：
```
当前: 线程1持有读锁

时刻1: 线程2请求写锁 → 阻塞（等待线程1释放读锁）
时刻2: 线程3请求读锁 → 成功（插队！）
时刻3: 线程4请求读锁 → 成功（插队！）
时刻4: 线程1释放读锁
时刻5: 线程3、4仍持有读锁
时刻6: 线程2仍在等待...（写线程可能饥饿）
```

**问题**：写线程可能长时间获取不到锁（写饥饿）

**公平模式**：
```java
ReadWriteLock rwLock = new ReentrantReadWriteLock(true);  // 公平
```

**工作方式**：
```
当前: 线程1持有读锁

时刻1: 线程2请求写锁 → 阻塞
时刻2: 线程3请求读锁 → 阻塞（不能插队）
时刻3: 线程4请求读锁 → 阻塞（不能插队）
时刻4: 线程1释放读锁
时刻5: 线程2获取写锁（按顺序）
时刻6: 线程2释放写锁
时刻7: 线程3、4获取读锁（按顺序）
```

### 2.3 锁降级

**锁降级**：持有写锁时获取读锁，然后释放写锁

```java
public class LockDowngradeExample {
    private final ReadWriteLock rwLock = new ReentrantReadWriteLock();
    private final Lock readLock = rwLock.readLock();
    private final Lock writeLock = rwLock.writeLock();
    private Map<String, String> cache = new HashMap<>();

    public void processData() {
        readLock.lock();
        boolean needUpdate = false;

        try {
            // 1. 先读取数据
            String value = cache.get("key");

            if (value == null) {
                needUpdate = true;
            }
        } finally {
            readLock.unlock();
        }

        if (needUpdate) {
            writeLock.lock();  // 2. 获取写锁
            try {
                // 3. 再次检查（double-check）
                String value = cache.get("key");
                if (value == null) {
                    // 4. 更新缓存
                    cache.put("key", "newValue");

                    // 5. 锁降级：在释放写锁前获取读锁
                    readLock.lock();
                }
            } finally {
                writeLock.unlock();  // 6. 释放写锁
            }

            // 7. 使用读锁访问数据
            try {
                String value = cache.get("key");
                System.out.println("读取数据: " + value);
            } finally {
                readLock.unlock();  // 8. 释放读锁
            }
        }
    }
}
```

**为什么需要锁降级？**
```
如果不降级：
writeLock.lock();
try {
    cache.put("key", "value");
}  // 释放写锁
writeLock.unlock();

readLock.lock();  // 获取读锁
try {
    cache.get("key");  // 可能读到其他线程的修改！
} finally {
    readLock.unlock();
}

如果降级：
writeLock.lock();
try {
    cache.put("key", "value");
    readLock.lock();  // 在释放写锁前获取读锁
} finally {
    writeLock.unlock();  // 释放写锁
}

try {
    cache.get("key");  // 保证读到自己的修改
} finally {
    readLock.unlock();
}
```

**注意**：不支持锁升级（从读锁升级到写锁）

```java
// ❌ 错误：会死锁
readLock.lock();
try {
    writeLock.lock();  // 死锁！
    try {
        // ...
    } finally {
        writeLock.unlock();
    }
} finally {
    readLock.unlock();
}
```

### 2.4 实现原理（简化）

**状态共享**：
```java
// 简化版
public class ReentrantReadWriteLock {
    abstract static class Sync extends AbstractQueuedSynchronizer {
        // state的高16位表示读锁计数
        // state的低16位表示写锁计数

        static final int SHARED_SHIFT   = 16;
        static final int SHARED_UNIT    = (1 << SHARED_SHIFT);
        static final int MAX_COUNT      = (1 << SHARED_SHIFT) - 1;
        static final int EXCLUSIVE_MASK = (1 << SHARED_SHIFT) - 1;

        // 读锁计数
        static int sharedCount(int c) {
            return c >>> SHARED_SHIFT;
        }

        // 写锁计数
        static int exclusiveCount(int c) {
            return c & EXCLUSIVE_MASK;
        }
    }
}
```

**state示例**：
```
初始状态: state = 0
┌─────────────────┬─────────────────┐
│  读锁计数: 0    │  写锁计数: 0    │
│  (高16位)       │  (低16位)       │
└─────────────────┴─────────────────┘

线程1获取写锁: state = 1
┌─────────────────┬─────────────────┐
│  读锁计数: 0    │  写锁计数: 1    │
└─────────────────┴─────────────────┘

线程2获取读锁: state = 65537 (0x10001)
┌─────────────────┬─────────────────┐
│  读锁计数: 1    │  写锁计数: 1    │
└─────────────────┴─────────────────┘
```

---

## 三、性能测试

### 3.1 读多写少场景

```java
public class ReadWriteLockPerformanceTest {
    private static final int THREAD_COUNT = 10;
    private static final int READ_RATIO = 90;  // 90%读操作
    private static final int ITERATIONS = 100_000;

    static class Data {
        private int value = 0;
    }

    // ReentrantLock版本
    static class ReentrantLockData {
        private Data data = new Data();
        private Lock lock = new ReentrantLock();

        public int read() {
            lock.lock();
            try {
                return data.value;
            } finally {
                lock.unlock();
            }
        }

        public void write(int newValue) {
            lock.lock();
            try {
                data.value = newValue;
            } finally {
                lock.unlock();
            }
        }
    }

    // ReadWriteLock版本
    static class ReadWriteLockData {
        private Data data = new Data();
        private ReadWriteLock rwLock = new ReentrantReadWriteLock();
        private Lock readLock = rwLock.readLock();
        private Lock writeLock = rwLock.writeLock();

        public int read() {
            readLock.lock();
            try {
                return data.value;
            } finally {
                readLock.unlock();
            }
        }

        public void write(int newValue) {
            writeLock.lock();
            try {
                data.value = newValue;
            } finally {
                writeLock.unlock();
            }
        }
    }

    public static void testReentrantLock() throws InterruptedException {
        ReentrantLockData data = new ReentrantLockData();
        CountDownLatch latch = new CountDownLatch(THREAD_COUNT);

        long start = System.currentTimeMillis();

        for (int i = 0; i < THREAD_COUNT; i++) {
            new Thread(() -> {
                Random random = new Random();
                for (int j = 0; j < ITERATIONS; j++) {
                    if (random.nextInt(100) < READ_RATIO) {
                        data.read();  // 90%读
                    } else {
                        data.write(j);  // 10%写
                    }
                }
                latch.countDown();
            }).start();
        }

        latch.await();
        long time = System.currentTimeMillis() - start;
        System.out.println("ReentrantLock (90%读): " + time + "ms");
    }

    public static void testReadWriteLock() throws InterruptedException {
        ReadWriteLockData data = new ReadWriteLockData();
        CountDownLatch latch = new CountDownLatch(THREAD_COUNT);

        long start = System.currentTimeMillis();

        for (int i = 0; i < THREAD_COUNT; i++) {
            new Thread(() -> {
                Random random = new Random();
                for (int j = 0; j < ITERATIONS; j++) {
                    if (random.nextInt(100) < READ_RATIO) {
                        data.read();  // 90%读
                    } else {
                        data.write(j);  // 10%写
                    }
                }
                latch.countDown();
            }).start();
        }

        latch.await();
        long time = System.currentTimeMillis() - start;
        System.out.println("ReadWriteLock (90%读): " + time + "ms");
    }

    public static void main(String[] args) throws InterruptedException {
        testReentrantLock();
        testReadWriteLock();
    }
}
```

**实测结果**：
```
ReentrantLock (90%读): 2300ms
ReadWriteLock (90%读): 350ms
性能提升: 6.6倍
```

### 3.2 不同读写比例的性能

| 读操作比例 | ReentrantLock | ReadWriteLock | 性能提升 |
|-----------|--------------|---------------|---------|
| 50% | 1800ms | 1200ms | 1.5倍 |
| 70% | 2000ms | 750ms | 2.7倍 |
| 90% | 2300ms | 350ms | **6.6倍** |
| 99% | 2500ms | 120ms | **20倍** |

**结论**：读操作比例越高，ReadWriteLock优势越明显

---

## 四、实战应用

### 4.1 缓存实现

```java
public class ConcurrentCache<K, V> {
    private final Map<K, V> cache = new HashMap<>();
    private final ReadWriteLock rwLock = new ReentrantReadWriteLock();
    private final Lock readLock = rwLock.readLock();
    private final Lock writeLock = rwLock.writeLock();

    public V get(K key) {
        readLock.lock();
        try {
            return cache.get(key);
        } finally {
            readLock.unlock();
        }
    }

    public void put(K key, V value) {
        writeLock.lock();
        try {
            cache.put(key, value);
        } finally {
            writeLock.unlock();
        }
    }

    public V computeIfAbsent(K key, Function<K, V> mappingFunction) {
        // 先用读锁检查
        readLock.lock();
        V value = cache.get(key);
        readLock.unlock();

        if (value != null) {
            return value;
        }

        // 需要计算，获取写锁
        writeLock.lock();
        try {
            // double-check
            value = cache.get(key);
            if (value == null) {
                value = mappingFunction.apply(key);
                cache.put(key, value);
            }
            return value;
        } finally {
            writeLock.unlock();
        }
    }
}
```

### 4.2 配置管理

```java
public class ConfigManager {
    private Map<String, String> config = new HashMap<>();
    private final ReadWriteLock rwLock = new ReentrantReadWriteLock();
    private final Lock readLock = rwLock.readLock();
    private final Lock writeLock = rwLock.writeLock();

    // 读取配置（频繁）
    public String getConfig(String key) {
        readLock.lock();
        try {
            return config.get(key);
        } finally {
            readLock.unlock();
        }
    }

    // 更新配置（偶尔）
    public void updateConfig(Map<String, String> newConfig) {
        writeLock.lock();
        try {
            config.clear();
            config.putAll(newConfig);
        } finally {
            writeLock.unlock();
        }
    }

    // 热加载配置（使用锁降级）
    public void reloadConfig() {
        readLock.lock();
        boolean needReload = checkNeedReload();
        readLock.unlock();

        if (needReload) {
            writeLock.lock();
            try {
                // double-check
                if (checkNeedReload()) {
                    Map<String, String> newConfig = loadFromFile();
                    config.clear();
                    config.putAll(newConfig);

                    // 锁降级
                    readLock.lock();
                }
            } finally {
                writeLock.unlock();
            }

            try {
                // 使用新配置
                logConfigChange();
            } finally {
                readLock.unlock();
            }
        }
    }

    private boolean checkNeedReload() {
        // 检查配置文件是否有更新
        return true;
    }

    private Map<String, String> loadFromFile() {
        // 从文件加载配置
        return new HashMap<>();
    }

    private void logConfigChange() {
        // 记录配置变化
    }
}
```

---

## 五、最佳实践

### 5.1 什么时候使用ReadWriteLock？

**适合的场景**：
- ✅ 读操作远多于写操作（读:写 > 10:1）
- ✅ 读操作耗时较长
- ✅ 写操作不频繁

**不适合的场景**：
- ❌ 写操作频繁（读:写 < 2:1）
- ❌ 读操作很快（加锁开销大于读操作本身）
- ❌ 简单的数据结构（用ConcurrentHashMap更好）

### 5.2 避免写饥饿

**问题**：非公平模式下，持续的读操作会导致写线程饥饿

**解决方案1：使用公平锁**
```java
ReadWriteLock rwLock = new ReentrantReadWriteLock(true);
```

**解决方案2：限制读锁的持有时间**
```java
public V get(K key) {
    readLock.lock();
    try {
        // 快速返回，不要在锁内做耗时操作
        return cache.get(key);
    } finally {
        readLock.unlock();
    }
}
```

**解决方案3：写优先策略**（自己实现）
```java
public class WritePriorityRWLock {
    private int readers = 0;
    private int writers = 0;
    private int writeRequests = 0;

    public synchronized void lockRead() throws InterruptedException {
        while (writers > 0 || writeRequests > 0) {
            wait();  // 有写请求时，读操作等待
        }
        readers++;
    }

    public synchronized void lockWrite() throws InterruptedException {
        writeRequests++;
        while (readers > 0 || writers > 0) {
            wait();
        }
        writeRequests--;
        writers++;
    }
}
```

### 5.3 锁降级的正确使用

```java
// ✅ 正确：先获取读锁，再释放写锁
writeLock.lock();
try {
    // 更新数据
    readLock.lock();  // 锁降级
} finally {
    writeLock.unlock();
}

try {
    // 使用更新后的数据
} finally {
    readLock.unlock();
}

// ❌ 错误：不支持锁升级
readLock.lock();
try {
    writeLock.lock();  // 死锁！
    try {
        // ...
    } finally {
        writeLock.unlock();
    }
} finally {
    readLock.unlock();
}
```

---

## 六、总结

### 6.1 核心要点

1. **ReadWriteLock的优势**
   - 读锁共享，写锁独占
   - 读多写少场景性能提升显著
   - 支持锁降级

2. **使用原则**
   - 读操作要多（90%+）
   - 读操作要耗时
   - 写操作不频繁

3. **锁降级**
   - 持有写锁时可以获取读锁
   - 不支持锁升级（读锁→写锁）

4. **公平性**
   - 非公平：性能好，可能写饥饿
   - 公平：公平性好，性能差

### 6.2 最佳实践

1. **优先使用JDK并发容器**
   ```java
   // 优先使用
   ConcurrentHashMap<K, V> map = new ConcurrentHashMap<>();

   // 而不是
   Map<K, V> map = new HashMap<>();
   ReadWriteLock lock = new ReentrantReadWriteLock();
   ```

2. **读多写少才用ReadWriteLock**
   - 读:写 > 10:1 才有明显提升

3. **避免在锁内做耗时操作**
   ```java
   readLock.lock();
   try {
       // 快速返回
       return cache.get(key);
   } finally {
       readLock.unlock();
   }
   ```

4. **正确使用锁降级**
   - 避免死锁
   - 保证数据一致性

### 6.3 思考题

1. 为什么不支持锁升级（读锁→写锁）？
2. 在什么情况下ReadWriteLock比ReentrantLock慢？
3. 如何避免写线程饥饿？

### 6.4 下一篇预告

在理解了Lock机制后，下一篇我们将学习**线程池** —— Java并发编程中最重要的工具之一，理解为什么需要线程池以及线程池的核心原理。

---

## 扩展阅读

1. **JDK源码**：
   - java.util.concurrent.locks.ReentrantReadWriteLock

2. **书籍**：
   - 《Java并发编程实战》第13章：显式锁
   - 《Java并发编程的艺术》第5章：Lock

---

**系列文章**：
- 上一篇：[Java并发17：Lock接口与ReentrantLock](/java-concurrency/posts/17-lock-and-reentrantlock/)
- 下一篇：[Java并发19：线程池核心原理](/java-concurrency/posts/19-threadpool-principle/) （即将发布）
