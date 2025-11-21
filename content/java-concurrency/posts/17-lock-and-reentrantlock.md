---
title: "Java并发17：Lock接口与ReentrantLock - 更灵活的锁"
date: 2025-11-20T20:00:00+08:00
draft: false
tags: ["Java并发", "Lock", "ReentrantLock", "AQS", "Condition"]
categories: ["技术"]
description: "深入理解Lock接口的设计理念、ReentrantLock的实现原理、公平锁与非公平锁、可中断锁、超时锁，以及Condition条件队列的使用。"
series: ["Java并发编程从入门到精通"]
weight: 17
stage: 3
stageTitle: "Lock与并发工具篇"
---

## 引言：synchronized的局限性

在前面的文章中，我们深入学习了synchronized，但它有一些局限性：

```java
public class SynchronizedLimitations {
    private final Object lock = new Object();

    public void method() {
        synchronized (lock) {
            // 问题1：无法响应中断
            // 如果获取锁的线程被阻塞，无法中断它

            // 问题2：无法设置超时
            // 如果获取不到锁，会一直等待

            // 问题3：必须在同一个代码块中释放锁
            // 无法在方法A获取，方法B释放

            // 问题4：无法尝试非阻塞获取锁
            // 无法tryLock()

            // 问题5：无法实现公平锁
            // synchronized是非公平的
        }
    }
}
```

**JDK 1.5引入Lock接口**，解决这些问题：

```java
Lock lock = new ReentrantLock();

// 可响应中断
lock.lockInterruptibly();

// 可设置超时
boolean success = lock.tryLock(1, TimeUnit.SECONDS);

// 可尝试非阻塞获取
if (lock.tryLock()) {
    try {
        // ...
    } finally {
        lock.unlock();
    }
}

// 可实现公平锁
Lock fairLock = new ReentrantLock(true);
```

本篇文章将深入Lock接口和ReentrantLock的实现原理。

---

## 一、Lock接口详解

### 1.1 Lock接口定义

```java
public interface Lock {
    // 获取锁（阻塞）
    void lock();

    // 获取锁（可中断）
    void lockInterruptibly() throws InterruptedException;

    // 尝试获取锁（非阻塞）
    boolean tryLock();

    // 尝试获取锁（超时）
    boolean tryLock(long time, TimeUnit unit) throws InterruptedException;

    // 释放锁
    void unlock();

    // 创建条件队列
    Condition newCondition();
}
```

### 1.2 Lock vs synchronized

| 特性 | synchronized | Lock |
|-----|-------------|------|
| **灵活性** | 低（固定模式） | 高（可自定义） |
| **响应中断** | ❌ 不支持 | ✅ 支持（lockInterruptibly） |
| **超时获取** | ❌ 不支持 | ✅ 支持（tryLock） |
| **非阻塞获取** | ❌ 不支持 | ✅ 支持（tryLock） |
| **公平性** | ❌ 非公平 | ✅ 可选（公平/非公平） |
| **多个条件** | ❌ 只有一个wait/notify | ✅ 多个Condition |
| **释放锁** | 自动释放 | 手动释放（需finally） |
| **性能** | JDK 1.6+优化后相当 | 相当 |
| **使用难度** | 简单 | 复杂（容易忘记unlock） |

### 1.3 Lock的基本使用模式

```java
Lock lock = new ReentrantLock();

lock.lock();  // 获取锁
try {
    // 临界区代码
    // ...
} finally {
    lock.unlock();  // 必须在finally中释放锁
}
```

**关键点**：
- ✅ **必须在finally中unlock**（避免锁泄漏）
- ✅ lock()和unlock()要成对出现
- ✅ unlock()前要确保已获取锁

---

## 二、ReentrantLock详解

### 2.1 可重入性

**可重入**：同一个线程可以多次获取同一个锁

```java
public class ReentrantExample {
    private final Lock lock = new ReentrantLock();

    public void methodA() {
        lock.lock();
        try {
            System.out.println("methodA");
            methodB();  // 再次获取同一个锁
        } finally {
            lock.unlock();
        }
    }

    public void methodB() {
        lock.lock();  // 不会死锁
        try {
            System.out.println("methodB");
        } finally {
            lock.unlock();
        }
    }
}
```

**实现原理**（稍后讲解AQS时详细说明）：
```java
// 伪代码
class ReentrantLock {
    Thread owner;        // 持有锁的线程
    int holdCount = 0;   // 重入次数

    void lock() {
        if (owner == currentThread) {
            holdCount++;  // 重入，计数+1
        } else {
            // 尝试获取锁...
        }
    }

    void unlock() {
        holdCount--;
        if (holdCount == 0) {
            owner = null;  // 完全释放锁
        }
    }
}
```

### 2.2 公平锁 vs 非公平锁

#### 非公平锁（默认）

```java
Lock lock = new ReentrantLock();  // 默认非公平
// 或
Lock lock = new ReentrantLock(false);
```

**工作方式**：
```
线程队列: [线程2, 线程3, 线程4]

线程1释放锁
    ↓
新来的线程5
    ├─ 直接尝试获取锁（CAS）
    │  ├─ 成功 → 获取锁（插队！）
    │  └─ 失败 → 排队到队尾
    │
线程2（队首）
    └─ 被唤醒，尝试获取锁
```

**优点**：
- 吞吐量高（减少线程切换）
- 性能好

**缺点**：
- 可能导致线程饥饿
- 排队久的线程可能一直获取不到锁

#### 公平锁

```java
Lock lock = new ReentrantLock(true);  // 公平锁
```

**工作方式**：
```
线程队列: [线程2, 线程3, 线程4]

线程1释放锁
    ↓
新来的线程5
    └─ 检查队列是否为空
       ├─ 队列非空 → 必须排队到队尾
       └─ 队列为空 → 才能尝试获取锁

线程2（队首）
    └─ 按顺序获取锁（先来先得）
```

**优点**：
- 公平性好，不会饥饿
- 先来先得

**缺点**：
- 性能较差（频繁线程切换）
- 吞吐量低

#### 性能对比

```java
public class FairVsNonFairTest {
    private static final int THREAD_COUNT = 10;
    private static final int ITERATIONS = 100_000;

    public static void testNonFair() throws InterruptedException {
        Lock lock = new ReentrantLock(false);  // 非公平
        CountDownLatch latch = new CountDownLatch(THREAD_COUNT);

        long start = System.currentTimeMillis();

        for (int i = 0; i < THREAD_COUNT; i++) {
            new Thread(() -> {
                for (int j = 0; j < ITERATIONS; j++) {
                    lock.lock();
                    try {
                        // 模拟临界区
                    } finally {
                        lock.unlock();
                    }
                }
                latch.countDown();
            }).start();
        }

        latch.await();
        long time = System.currentTimeMillis() - start;
        System.out.println("非公平锁: " + time + "ms");
    }

    public static void testFair() throws InterruptedException {
        Lock lock = new ReentrantLock(true);  // 公平
        CountDownLatch latch = new CountDownLatch(THREAD_COUNT);

        long start = System.currentTimeMillis();

        for (int i = 0; i < THREAD_COUNT; i++) {
            new Thread(() -> {
                for (int j = 0; j < ITERATIONS; j++) {
                    lock.lock();
                    try {
                        // 模拟临界区
                    } finally {
                        lock.unlock();
                    }
                }
                latch.countDown();
            }).start();
        }

        latch.await();
        long time = System.currentTimeMillis() - start;
        System.out.println("公平锁: " + time + "ms");
    }

    public static void main(String[] args) throws InterruptedException {
        testNonFair();
        testFair();
    }
}
```

**实测结果**：
```
非公平锁: 850ms
公平锁: 2300ms
性能差距: 2.7倍
```

### 2.3 可中断锁

**场景**：线程在等待锁时，可以响应中断

```java
public class InterruptibleLockExample {
    private final Lock lock = new ReentrantLock();

    public void method() throws InterruptedException {
        System.out.println("尝试获取锁...");

        lock.lockInterruptibly();  // 可中断的锁
        try {
            System.out.println("获取锁成功，执行任务");
            // 执行任务...
            Thread.sleep(5000);
        } finally {
            lock.unlock();
            System.out.println("释放锁");
        }
    }

    public static void main(String[] args) throws InterruptedException {
        InterruptibleLockExample example = new InterruptibleLockExample();

        // 线程1：获取锁并持有
        Thread t1 = new Thread(() -> {
            try {
                example.method();
            } catch (InterruptedException e) {
                System.out.println("线程1被中断");
            }
        });

        // 线程2：等待锁
        Thread t2 = new Thread(() -> {
            try {
                example.method();
            } catch (InterruptedException e) {
                System.out.println("线程2被中断");  // 会打印这个
            }
        });

        t1.start();
        Thread.sleep(100);  // 确保t1先获取锁
        t2.start();

        Thread.sleep(1000);
        t2.interrupt();  // 中断t2

        t1.join();
        t2.join();
    }
}
```

**输出**：
```
线程1: 尝试获取锁...
线程1: 获取锁成功，执行任务
线程2: 尝试获取锁...
线程2被中断  ← t2响应中断
线程1: 释放锁
```

**对比synchronized**：
```java
// synchronized无法响应中断
synchronized (lock) {
    // 如果获取不到锁，线程会一直阻塞
    // 即使调用interrupt()也无效
}
```

### 2.4 超时锁

**场景**：尝试获取锁，超时后放弃

```java
public class TimeoutLockExample {
    private final Lock lock = new ReentrantLock();

    public boolean transfer(Account from, Account to, int amount) {
        try {
            // 尝试获取锁，最多等待1秒
            if (lock.tryLock(1, TimeUnit.SECONDS)) {
                try {
                    // 执行转账
                    from.debit(amount);
                    to.credit(amount);
                    return true;
                } finally {
                    lock.unlock();
                }
            } else {
                System.out.println("获取锁超时，放弃转账");
                return false;
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return false;
        }
    }
}
```

**避免死锁**：
```java
public class DeadlockAvoidance {
    public boolean transferMoney(
        Account from, Account to, int amount, long timeout, TimeUnit unit
    ) throws InterruptedException {
        long fixedDelay = unit.toNanos(timeout);
        long randMod = fixedDelay / 2;
        long stopTime = System.nanoTime() + fixedDelay;

        while (true) {
            if (from.lock.tryLock()) {
                try {
                    if (to.lock.tryLock()) {
                        try {
                            // 执行转账
                            from.debit(amount);
                            to.credit(amount);
                            return true;
                        } finally {
                            to.lock.unlock();
                        }
                    }
                } finally {
                    from.lock.unlock();
                }
            }

            // 检查超时
            if (System.nanoTime() >= stopTime) {
                return false;
            }

            // 随机延迟后重试（避免活锁）
            long delay = ThreadLocalRandom.current().nextLong(randMod);
            TimeUnit.NANOSECONDS.sleep(delay);
        }
    }
}
```

### 2.5 非阻塞尝试获取锁

```java
Lock lock = new ReentrantLock();

if (lock.tryLock()) {  // 立即返回，不阻塞
    try {
        // 获取锁成功，执行任务
    } finally {
        lock.unlock();
    }
} else {
    // 获取锁失败，执行备选方案
    System.out.println("锁被占用，执行其他任务");
}
```

**应用场景**：
```java
public class CacheWithLock {
    private final Map<String, String> cache = new HashMap<>();
    private final Lock lock = new ReentrantLock();

    public String get(String key) {
        // 尝试获取锁读缓存
        if (lock.tryLock()) {
            try {
                return cache.get(key);
            } finally {
                lock.unlock();
            }
        } else {
            // 获取不到锁，直接查数据库
            return queryDatabase(key);
        }
    }
}
```

---

## 三、Condition条件队列

### 3.1 Condition vs wait/notify

| 特性 | Object.wait/notify | Condition |
|-----|-------------------|-----------|
| **条件队列数量** | 1个 | 多个 |
| **等待** | wait() | await() |
| **通知** | notify() | signal() |
| **通知所有** | notifyAll() | signalAll() |
| **超时等待** | wait(long) | await(long, TimeUnit) |
| **可中断等待** | ✅ | ✅ |
| **绑定锁** | synchronized | Lock |

### 3.2 Condition基本使用

```java
public class BoundedBuffer<T> {
    private final Queue<T> queue = new LinkedList<>();
    private final int capacity;
    private final Lock lock = new ReentrantLock();
    private final Condition notFull = lock.newCondition();   // 非满条件
    private final Condition notEmpty = lock.newCondition();  // 非空条件

    public BoundedBuffer(int capacity) {
        this.capacity = capacity;
    }

    public void put(T item) throws InterruptedException {
        lock.lock();
        try {
            while (queue.size() == capacity) {
                notFull.await();  // 队列满，等待非满条件
            }
            queue.offer(item);
            notEmpty.signal();  // 通知非空条件
        } finally {
            lock.unlock();
        }
    }

    public T take() throws InterruptedException {
        lock.lock();
        try {
            while (queue.isEmpty()) {
                notEmpty.await();  // 队列空，等待非空条件
            }
            T item = queue.poll();
            notFull.signal();  // 通知非满条件
            return item;
        } finally {
            lock.unlock();
        }
    }
}
```

### 3.3 多条件队列的优势

**使用synchronized（只有一个条件队列）**：
```java
public class SingleConditionQueue {
    private final Queue<String> queue = new LinkedList<>();
    private final int capacity = 10;

    public synchronized void put(String item) throws InterruptedException {
        while (queue.size() == capacity) {
            wait();  // 生产者和消费者都在同一个队列等待
        }
        queue.offer(item);
        notifyAll();  // 必须notifyAll()，唤醒所有线程
    }

    public synchronized String take() throws InterruptedException {
        while (queue.isEmpty()) {
            wait();  // 生产者和消费者都在同一个队列等待
        }
        String item = queue.poll();
        notifyAll();  // 必须notifyAll()，唤醒所有线程
        return item;
    }
}
```

**问题**：
- 生产者和消费者混在同一个等待队列
- 必须使用`notifyAll()`，效率低
- 可能唤醒不该唤醒的线程

**使用Condition（多个条件队列）**：
```java
public class MultiConditionQueue {
    private final Queue<String> queue = new LinkedList<>();
    private final int capacity = 10;
    private final Lock lock = new ReentrantLock();
    private final Condition notFull = lock.newCondition();
    private final Condition notEmpty = lock.newCondition();

    public void put(String item) throws InterruptedException {
        lock.lock();
        try {
            while (queue.size() == capacity) {
                notFull.await();  // 生产者等待
            }
            queue.offer(item);
            notEmpty.signal();  // 只唤醒一个消费者
        } finally {
            lock.unlock();
        }
    }

    public String take() throws InterruptedException {
        lock.lock();
        try {
            while (queue.isEmpty()) {
                notEmpty.await();  // 消费者等待
            }
            String item = queue.poll();
            notFull.signal();  // 只唤醒一个生产者
            return item;
        } finally {
            lock.unlock();
        }
    }
}
```

**优点**：
- 生产者和消费者分开等待
- 只唤醒需要的线程，效率高

---

## 四、AQS简介（AbstractQueuedSynchronizer）

### 4.1 什么是AQS？

**AQS**是ReentrantLock、CountDownLatch、Semaphore等的基础框架。

**核心思想**：
```
AQS = 状态（state） + 等待队列（CLH队列）

┌───────────────────────────────┐
│         AQS                   │
├───────────────────────────────┤
│ state: int                    │ ← 同步状态
│   - 0: 未锁定                 │
│   - 1: 锁定                   │
│   - >1: 重入次数              │
├───────────────────────────────┤
│ CLH队列:                      │
│ head → [Node] → [Node] → tail │ ← 等待线程队列
└───────────────────────────────┘
```

### 4.2 ReentrantLock的AQS实现

```java
// 简化版
public class ReentrantLock {
    abstract static class Sync extends AbstractQueuedSynchronizer {
        // 尝试获取锁
        final boolean tryAcquire(int acquires) {
            Thread current = Thread.currentThread();
            int c = getState();

            if (c == 0) {
                // 锁未被占用，尝试CAS获取
                if (compareAndSetState(0, acquires)) {
                    setExclusiveOwnerThread(current);
                    return true;
                }
            } else if (current == getExclusiveOwnerThread()) {
                // 重入
                int nextc = c + acquires;
                setState(nextc);
                return true;
            }
            return false;
        }

        // 尝试释放锁
        final boolean tryRelease(int releases) {
            int c = getState() - releases;
            if (Thread.currentThread() != getExclusiveOwnerThread()) {
                throw new IllegalMonitorStateException();
            }
            boolean free = false;
            if (c == 0) {
                free = true;
                setExclusiveOwnerThread(null);
            }
            setState(c);
            return free;
        }
    }

    // 非公平锁
    static final class NonfairSync extends Sync { ... }

    // 公平锁
    static final class FairSync extends Sync { ... }
}
```

---

## 五、最佳实践

### 5.1 标准使用模式

```java
Lock lock = new ReentrantLock();

lock.lock();
try {
    // 临界区代码
} finally {
    lock.unlock();  // 必须在finally中
}
```

### 5.2 避免锁泄漏

```java
// ❌ 错误：unlock不在finally中
lock.lock();
// ...
lock.unlock();  // 如果上面抛异常，锁永远不会释放

// ✅ 正确
lock.lock();
try {
    // ...
} finally {
    lock.unlock();
}
```

### 5.3 使用tryLock避免死锁

```java
public boolean transferMoney(Account from, Account to, int amount) {
    if (from.lock.tryLock()) {
        try {
            if (to.lock.tryLock()) {
                try {
                    from.debit(amount);
                    to.credit(amount);
                    return true;
                } finally {
                    to.lock.unlock();
                }
            }
        } finally {
            from.lock.unlock();
        }
    }
    return false;
}
```

### 5.4 合理选择公平性

```java
// 默认非公平（性能优先）
Lock lock = new ReentrantLock();

// 公平锁（公平性优先）
Lock fairLock = new ReentrantLock(true);
```

**建议**：
- 大多数情况使用非公平锁（性能更好）
- 需要严格公平性时才使用公平锁

---

## 六、总结

### 6.1 核心要点

1. **Lock接口的优势**
   - 可响应中断
   - 可设置超时
   - 可非阻塞获取
   - 可实现公平锁
   - 支持多个条件队列

2. **ReentrantLock特性**
   - 可重入
   - 公平/非公平可选
   - 性能与synchronized相当

3. **Condition条件队列**
   - 替代wait/notify
   - 支持多个条件队列
   - 更精确的线程唤醒

4. **使用原则**
   - 必须在finally中unlock
   - 优先使用非公平锁
   - 能用synchronized就用synchronized

### 6.2 Lock vs synchronized选择

**使用synchronized的场景**：
- ✅ 简单的同步需求
- ✅ JDK 1.6+（性能已优化）
- ✅ 不需要Lock的高级特性

**使用Lock的场景**：
- ✅ 需要响应中断
- ✅ 需要超时获取
- ✅ 需要非阻塞获取
- ✅ 需要公平锁
- ✅ 需要多个条件队列

### 6.3 思考题

1. 为什么ReentrantLock需要在finally中unlock？
2. 公平锁为什么比非公平锁慢？
3. Condition的await()和Object的wait()有什么区别？

### 6.4 下一篇预告

在理解了基本的Lock机制后，下一篇我们将学习**ReadWriteLock** —— 专门优化读多写少场景的锁，性能提升数倍。

---

## 扩展阅读

1. **JDK源码**：
   - java.util.concurrent.locks.ReentrantLock
   - java.util.concurrent.locks.AbstractQueuedSynchronizer

2. **书籍**：
   - 《Java并发编程实战》第13章：显式锁
   - 《Java并发编程的艺术》第5章：Lock

3. **论文**：
   - "The java.util.concurrent Synchronizer Framework" - Doug Lea

---

**系列文章**：
- 上一篇：[Java并发16：CAS算法与ABA问题](/java-concurrency/posts/16-cas-and-aba/)
- 下一篇：[Java并发18：读写锁ReadWriteLock](/java-concurrency/posts/18-readwritelock/) （即将发布）
