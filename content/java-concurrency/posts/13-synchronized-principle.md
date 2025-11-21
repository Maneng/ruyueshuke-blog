---
title: "Java并发13：synchronized原理与使用 - 重量级锁的前世今生"
date: 2025-11-20T18:00:00+08:00
draft: false
tags: ["Java并发", "synchronized", "Monitor", "对象头", "互斥锁"]
categories: ["技术"]
description: "深入理解synchronized的底层原理：对象头结构、Monitor机制、可重入性实现、锁粗化和锁消除优化。"
series: ["Java并发编程从入门到精通"]
weight: 13
stage: 2
stageTitle: "内存模型与原子性篇"
---

## 引言：从一个线程安全问题说起

看这个经典的银行转账问题：

```java
public class BankAccount {
    private int balance = 1000;

    public void transfer(BankAccount target, int amount) {
        this.balance -= amount;        // 1. 扣款
        target.balance += amount;      // 2. 入账
    }
}

// 两个线程同时转账
Thread t1 = new Thread(() -> accountA.transfer(accountB, 100));
Thread t2 = new Thread(() -> accountB.transfer(accountA, 200));
t1.start();
t2.start();
```

**问题**：可能发生死锁或数据不一致！

**解决方案**：使用synchronized
```java
public synchronized void transfer(BankAccount target, int amount) {
    this.balance -= amount;
    target.balance += amount;
}
```

**三个疑问**：
1. synchronized是如何保证线程安全的？
2. 为什么它能同时保证原子性、可见性、有序性？
3. 它的性能开销来自哪里？

本篇文章将深入synchronized的底层原理，从对象头到Monitor机制，彻底理解Java最基础的同步机制。

---

## 一、synchronized的三种使用方式

### 1.1 修饰实例方法

```java
public class Counter {
    private int count = 0;

    public synchronized void increment() {
        count++;
    }
    // 等价于：
    // public void increment() {
    //     synchronized (this) {
    //         count++;
    //     }
    // }
}
```

**锁对象**：当前实例（`this`）

**特点**：
- 同一个实例的多个synchronized方法互斥
- 不同实例的synchronized方法不互斥

```java
Counter c1 = new Counter();
Counter c2 = new Counter();

// 线程1和线程2会互斥（同一个对象）
Thread t1 = new Thread(() -> c1.increment());
Thread t2 = new Thread(() -> c1.increment());

// 线程3和线程4不会互斥（不同对象）
Thread t3 = new Thread(() -> c1.increment());
Thread t4 = new Thread(() -> c2.increment());
```

### 1.2 修饰静态方法

```java
public class StaticCounter {
    private static int count = 0;

    public static synchronized void increment() {
        count++;
    }
    // 等价于：
    // public static void increment() {
    //     synchronized (StaticCounter.class) {
    //         count++;
    //     }
    // }
}
```

**锁对象**：类的Class对象（`StaticCounter.class`）

**特点**：
- 所有实例共享同一个锁
- 与实例方法的锁不同

```java
// 这两个线程会互斥（锁同一个Class对象）
Thread t1 = new Thread(() -> StaticCounter.increment());
Thread t2 = new Thread(() -> StaticCounter.increment());

// 但与实例方法的锁不冲突
Thread t3 = new Thread(() -> new StaticCounter().instanceMethod());
```

### 1.3 修饰代码块

```java
public class BlockSync {
    private final Object lock = new Object();
    private int count = 0;

    public void increment() {
        synchronized (lock) {  // 自定义锁对象
            count++;
        }
    }
}
```

**锁对象**：自定义的任意对象

**优点**：
- 粒度更细，性能更好
- 可以使用多个锁（细粒度锁）

**最佳实践**：
```java
public class GoodPractice {
    private final Object lock = new Object();  // final防止被修改

    public void method() {
        // 只锁必要的代码
        doSomethingBefore();  // 不需要加锁

        synchronized (lock) {
            // 只锁这部分
            updateSharedState();
        }

        doSomethingAfter();  // 不需要加锁
    }
}
```

---

## 二、synchronized的底层原理

### 2.1 字节码分析

**源码**：
```java
public class SyncDemo {
    public void syncMethod() {
        synchronized (this) {
            System.out.println("Hello");
        }
    }
}
```

**字节码**（javap -v SyncDemo.class）：
```
public void syncMethod();
  Code:
    0: aload_0                    // 加载this
    1: dup                        // 复制栈顶元素
    2: astore_1                   // 存储到局部变量1
    3: monitorenter               // 获取monitor ← 关键
    4: getstatic     #2           // System.out
    7: ldc           #3           // "Hello"
    9: invokevirtual #4           // println
   12: aload_1                    // 加载局部变量1
   13: monitorexit                // 释放monitor ← 关键
   14: goto          22
   17: astore_2                   // 异常处理
   18: aload_1
   19: monitorexit                // 异常时也要释放monitor
   20: aload_2
   21: athrow
   22: return

  Exception table:
     from    to  target type
         4    14    17   any
        17    20    17   any
```

**关键点**：
- **monitorenter**：获取对象的monitor
- **monitorexit**：释放对象的monitor
- 异常情况下也会释放monitor（异常表保证）

### 2.2 对象头结构

每个Java对象在内存中的布局：

```
┌─────────────────────────────────────────────────┐
│                  Java对象                        │
├─────────────────────────────────────────────────┤
│  对象头 (Object Header)                          │
│  ├─ Mark Word (8字节，64位JVM)                  │
│  └─ Class Pointer (4字节/8字节)                 │
├─────────────────────────────────────────────────┤
│  实例数据 (Instance Data)                        │
├─────────────────────────────────────────────────┤
│  对齐填充 (Padding)                              │
└─────────────────────────────────────────────────┘
```

### 2.3 Mark Word详解

**Mark Word**（64位JVM）：

```
无锁状态：
┌─────────────────────────────────────────────────────────────┐
│ unused(25位) │ hashcode(31位) │ unused(1) │ age(4) │ 0 │ 01│
└─────────────────────────────────────────────────────────────┘
                                                      ↑    ↑
                                                   lock  lock type

偏向锁状态：
┌─────────────────────────────────────────────────────────────┐
│ ThreadID(54位) │ epoch(2位) │ unused(1) │ age(4) │ 1 │ 01 │
└─────────────────────────────────────────────────────────────┘

轻量级锁状态：
┌─────────────────────────────────────────────────────────────┐
│         指向栈中锁记录的指针(62位)          │ 00 │
└─────────────────────────────────────────────────────────────┘

重量级锁状态：
┌─────────────────────────────────────────────────────────────┐
│      指向Monitor对象的指针(62位)            │ 10 │
└─────────────────────────────────────────────────────────────┘

GC标记状态：
┌─────────────────────────────────────────────────────────────┐
│                     (62位)                  │ 11 │
└─────────────────────────────────────────────────────────────┘
```

**锁状态标志**：

| 锁状态 | 标志位 | 说明 |
|-------|-------|------|
| 无锁 | 01 | 未被锁定 |
| 偏向锁 | 01 (biased_lock=1) | 偏向某个线程 |
| 轻量级锁 | 00 | 栈上锁记录 |
| 重量级锁 | 10 | 指向Monitor对象 |
| GC标记 | 11 | 垃圾回收标记 |

### 2.4 Monitor机制

**Monitor对象结构**：

```
┌─────────────────────────────────────┐
│          Monitor对象                │
├─────────────────────────────────────┤
│  _owner:      持有锁的线程           │
│  _recursions: 重入次数               │
│  _EntryList:  等待获取锁的线程队列    │
│  _WaitSet:    调用wait()的线程队列   │
└─────────────────────────────────────┘
```

**工作流程**：

```
                    ┌──────────────┐
                    │  尝试获取锁   │
                    └───────┬──────┘
                            │
                ┌───────────┴───────────┐
                │    锁是否空闲？        │
                └───────┬───────────────┘
                        │
        ┌───────────────┼───────────────┐
        │ 是                            │ 否
        ↓                               ↓
┌──────────────┐              ┌──────────────────┐
│ 获取锁成功    │              │ 进入EntryList等待 │
│ _owner=当前线程│              │ (阻塞状态)        │
└──────┬───────┘              └─────────┬────────┘
       │                                 │
       │  执行同步代码块                  │
       │                                 │
       ↓                                 │
┌──────────────┐                         │
│  释放锁      │                         │
│  _owner=null │                         │
└──────┬───────┘                         │
       │                                 │
       └──────唤醒EntryList中的一个线程───┘
```

### 2.5 重入性实现

**重入性**：同一个线程可以多次获取同一个锁

```java
public class ReentrantDemo {
    public synchronized void methodA() {
        System.out.println("methodA");
        methodB();  // 再次获取this的锁
    }

    public synchronized void methodB() {
        System.out.println("methodB");  // 不会死锁
    }
}
```

**实现原理**：

```
第一次获取锁：
_owner = Thread-1
_recursions = 1  ← 重入计数

第二次获取锁（同一个线程）：
_owner = Thread-1（不变）
_recursions = 2  ← 重入计数+1

第一次释放锁：
_recursions = 1  ← 重入计数-1（不释放锁）

第二次释放锁：
_recursions = 0  ← 重入计数归零，释放锁
_owner = null
```

**代码验证**：
```java
public class ReentrantTest {
    private final Object lock = new Object();

    public void test() {
        synchronized (lock) {
            System.out.println("第一次获取锁");
            synchronized (lock) {
                System.out.println("第二次获取锁（重入）");
                synchronized (lock) {
                    System.out.println("第三次获取锁（重入）");
                }
            }
        }
    }
}
// 输出：
// 第一次获取锁
// 第二次获取锁（重入）
// 第三次获取锁（重入）
// （不会死锁）
```

---

## 三、synchronized的内存语义

### 3.1 三大保证

#### 1. 原子性

```java
synchronized (lock) {
    count++;  // 三个操作（读、加、写）作为整体执行
}
```

**保证**：
- 同一时刻只有一个线程执行
- 其他线程必须等待

#### 2. 可见性

```java
int a = 0;
int b = 0;

// 线程1
synchronized (lock) {
    a = 1;
    b = 2;
}  // 释放锁时，刷新所有变量到主内存

// 线程2
synchronized (lock) {  // 获取锁时，清空工作内存，从主内存重新加载
    System.out.println(a);  // 一定读到1
    System.out.println(b);  // 一定读到2
}
```

**JMM规定**：
- **进入synchronized**：清空工作内存，从主内存加载最新值
- **退出synchronized**：将工作内存的修改刷新到主内存

#### 3. 有序性

```java
int a = 0;
int b = 0;

synchronized (lock) {
    a = 1;  // 1
    b = 2;  // 2
}

// synchronized内的代码不会重排序到外面
// 1和2的顺序可能调整，但整体不会跑到synchronized外面
```

### 3.2 happens-before规则

**锁定规则**：对一个锁的unlock操作 happens-before 后续对这个锁的lock操作

```java
// 线程1
synchronized (lock) {
    x = 1;      // A
}  // unlock    B

// 线程2
synchronized (lock) {  // lock  C
    int a = x;  // D  读到1
}

// happens-before链：
A hb B (程序顺序规则)
B hb C (锁定规则)
C hb D (程序顺序规则)
→ A hb D（传递性）
```

---

## 四、synchronized的典型应用

### 4.1 保护共享变量

```java
public class Counter {
    private int count = 0;

    public synchronized void increment() {
        count++;  // 读-改-写，需要原子性
    }

    public synchronized int getCount() {
        return count;  // 读操作也要加锁，保证可见性
    }
}
```

**注意**：
- 写操作要加锁（原子性）
- **读操作也要加锁**（可见性）

### 4.2 保护多个相关变量

```java
public class Range {
    private int lower = 0;
    private int upper = 10;

    public synchronized void setRange(int lower, int upper) {
        if (lower > upper) {
            throw new IllegalArgumentException();
        }
        this.lower = lower;  // 两个变量要保持一致性
        this.upper = upper;
    }

    public synchronized boolean isInRange(int value) {
        return value >= lower && value <= upper;
    }
}
```

**关键**：
- 多个变量有不变性条件（lower <= upper）
- 必须同时修改，保证原子性

### 4.3 单例模式的正确实现

**饿汉式**（线程安全）：
```java
public class Singleton {
    private static final Singleton INSTANCE = new Singleton();

    private Singleton() {}

    public static Singleton getInstance() {
        return INSTANCE;
    }
}
```

**双重检查锁定**（DCL）：
```java
public class Singleton {
    private static volatile Singleton instance;

    private Singleton() {}

    public static Singleton getInstance() {
        if (instance == null) {           // 第1次检查
            synchronized (Singleton.class) {
                if (instance == null) {   // 第2次检查
                    instance = new Singleton();
                }
            }
        }
        return instance;
    }
}
```

**静态内部类**（最优雅）：
```java
public class Singleton {
    private Singleton() {}

    private static class Holder {
        private static final Singleton INSTANCE = new Singleton();
    }

    public static Singleton getInstance() {
        return Holder.INSTANCE;  // 类加载机制保证线程安全
    }
}
```

### 4.4 生产者-消费者模式

```java
public class BoundedBuffer<T> {
    private final Queue<T> queue = new LinkedList<>();
    private final int capacity;

    public BoundedBuffer(int capacity) {
        this.capacity = capacity;
    }

    public synchronized void put(T item) throws InterruptedException {
        while (queue.size() == capacity) {
            wait();  // 队列满，等待
        }
        queue.offer(item);
        notifyAll();  // 唤醒消费者
    }

    public synchronized T take() throws InterruptedException {
        while (queue.isEmpty()) {
            wait();  // 队列空，等待
        }
        T item = queue.poll();
        notifyAll();  // 唤醒生产者
        return item;
    }
}
```

---

## 五、synchronized的性能优化

### 5.1 锁粗化（Lock Coarsening）

**问题代码**：
```java
for (int i = 0; i < 1000; i++) {
    synchronized (lock) {
        count++;  // 每次循环都加锁/解锁
    }
}
```

**JVM优化后**：
```java
synchronized (lock) {
    for (int i = 0; i < 1000; i++) {
        count++;  // 只加锁一次
    }
}
```

**原理**：
- JIT编译器检测到连续的加锁操作
- 自动将锁的范围扩大
- 减少加锁/解锁的开销

### 5.2 锁消除（Lock Elimination）

**代码**：
```java
public String concat(String s1, String s2, String s3) {
    StringBuffer sb = new StringBuffer();  // 局部变量
    sb.append(s1);  // StringBuffer.append是synchronized的
    sb.append(s2);
    sb.append(s3);
    return sb.toString();
}
```

**分析**：
- `sb`是局部变量，不会被其他线程访问
- `append()`的synchronized是多余的

**JVM优化**：
- 通过逃逸分析（Escape Analysis）
- 发现`sb`不会逃逸到方法外
- **消除synchronized，性能提升**

**启用逃逸分析**：
```bash
-XX:+DoEscapeAnalysis     # 开启逃逸分析（默认开启）
-XX:+EliminateLocks       # 开启锁消除（默认开启）
```

### 5.3 减小锁粒度

**问题代码**：
```java
public class CoarseGrainedLock {
    private final List<String> list = new ArrayList<>();

    public synchronized void add(String item) {
        list.add(item);
        // ... 其他不需要加锁的操作
        doExpensiveWork();  // 耗时操作，不需要加锁
    }
}
```

**优化后**：
```java
public class FineGrainedLock {
    private final List<String> list = new ArrayList<>();

    public void add(String item) {
        doExpensiveWork();  // 先做耗时操作（不加锁）

        synchronized (list) {
            list.add(item);  // 只锁必要的部分
        }
    }
}
```

### 5.4 使用读写分离

**问题**：读多写少的场景，synchronized效率低

```java
public class ReadWriteExample {
    private final Map<String, String> map = new HashMap<>();

    // 读操作（频繁）
    public synchronized String get(String key) {
        return map.get(key);  // 读也要加锁，影响并发度
    }

    // 写操作（少见）
    public synchronized void put(String key, String value) {
        map.put(key, value);
    }
}
```

**优化**：使用ReadWriteLock（后续文章详解）
```java
public class ReadWriteOptimized {
    private final Map<String, String> map = new HashMap<>();
    private final ReadWriteLock lock = new ReentrantReadWriteLock();

    public String get(String key) {
        lock.readLock().lock();  // 读锁（共享）
        try {
            return map.get(key);
        } finally {
            lock.readLock().unlock();
        }
    }

    public void put(String key, String value) {
        lock.writeLock().lock();  // 写锁（独占）
        try {
            map.put(key, value);
        } finally {
            lock.writeLock().unlock();
        }
    }
}
```

---

## 六、synchronized的常见陷阱

### 陷阱1：锁对象被改变

```java
public class WrongLock {
    private Object lock = new Object();  // 没有final

    public void method1() {
        synchronized (lock) {
            // ...
        }
    }

    public void changeLock() {
        lock = new Object();  // 锁对象被替换了！
        // 之后的synchronized锁的是新对象
    }
}
```

**正确做法**：
```java
private final Object lock = new Object();  // 使用final
```

### 陷阱2：锁的不是同一个对象

```java
public class DifferentLocks {
    public void method1() {
        synchronized (new Object()) {  // 每次都是新对象！
            // 没有互斥效果
        }
    }
}
```

### 陷阱3：锁粒度过粗

```java
public class CoarseLock {
    private List<String> list = new ArrayList<>();

    public synchronized void process() {
        // 大量耗时操作
        for (int i = 0; i < 1000000; i++) {
            doExpensiveWork();  // 整个过程都持有锁
        }
        list.add("result");  // 只有这一行需要加锁
    }
}
```

### 陷阱4：死锁

```java
public class DeadLock {
    private final Object lock1 = new Object();
    private final Object lock2 = new Object();

    public void method1() {
        synchronized (lock1) {
            synchronized (lock2) {  // 获取lock1后再获取lock2
                // ...
            }
        }
    }

    public void method2() {
        synchronized (lock2) {
            synchronized (lock1) {  // 获取lock2后再获取lock1
                // ...               死锁！
            }
        }
    }
}
```

**解决方案**：
```java
// 所有线程按相同顺序获取锁
public void method1() {
    synchronized (lock1) {
        synchronized (lock2) {
            // ...
        }
    }
}

public void method2() {
    synchronized (lock1) {  // 改为相同顺序
        synchronized (lock2) {
            // ...
        }
    }
}
```

### 陷阱5：在循环中频繁加锁

```java
// 性能差
for (int i = 0; i < 100000; i++) {
    synchronized (lock) {
        count++;
    }
}

// 优化后
synchronized (lock) {
    for (int i = 0; i < 100000; i++) {
        count++;
    }
}
```

---

## 七、总结

### 7.1 核心要点

1. **synchronized的实现原理**
   - 字节码：monitorenter/monitorexit
   - 对象头：Mark Word存储锁状态
   - Monitor对象：_owner、_recursions、_EntryList、_WaitSet

2. **重入性机制**
   - 同一线程可多次获取同一个锁
   - _recursions计数器实现

3. **内存语义**
   - 原子性：互斥执行
   - 可见性：unlock刷新，lock重新加载
   - 有序性：synchronized内外不会重排序

4. **性能优化**
   - 锁粗化：合并连续的加锁操作
   - 锁消除：消除不必要的锁
   - 减小锁粒度：只锁必要的代码

5. **常见陷阱**
   - 锁对象被改变
   - 锁的不是同一个对象
   - 锁粒度过粗
   - 死锁
   - 循环中频繁加锁

### 7.2 最佳实践

1. **锁对象使用final**
   ```java
   private final Object lock = new Object();
   ```

2. **缩小锁的范围**
   ```java
   // 只锁必要的代码
   doSomething();  // 不需要锁
   synchronized (lock) {
       updateSharedState();  // 只锁这部分
   }
   doSomethingElse();  // 不需要锁
   ```

3. **避免在锁内调用未知方法**
   ```java
   synchronized (lock) {
       listener.onEvent();  // 未知方法可能很慢或死锁
   }
   ```

4. **锁的顺序一致性**
   ```java
   // 总是按相同顺序获取多个锁
   synchronized (lockA) {
       synchronized (lockB) {
           // ...
       }
   }
   ```

### 7.3 思考题

1. 为什么synchronized修饰静态方法和实例方法的锁不同？
2. synchronized能否被继承？（子类方法会自动加锁吗？）
3. synchronized和ReentrantLock有什么区别？

### 7.4 下一篇预告

在理解了synchronized的基本原理后，下一篇我们将深入学习**synchronized的优化演进** —— 偏向锁、轻量级锁、重量级锁的完整演化过程，以及JVM如何优化锁的性能。

---

## 扩展阅读

1. **OpenJDK源码**：
   - hotspot/src/share/vm/runtime/objectMonitor.cpp

2. **书籍**：
   - 《深入理解Java虚拟机》第13章：线程安全与锁优化
   - 《Java并发编程实战》第2章：线程安全性

3. **工具**：
   - jstack：查看线程状态和死锁
   - JProfiler：分析锁竞争

4. **论文**：
   - "Biased Locking in HotSpot" - Oracle

---

**系列文章**：
- 上一篇：[Java并发12：volatile关键字深度解析](/java-concurrency/posts/12-volatile-deep-dive/)
- 下一篇：[Java并发14：synchronized的优化演进](/java-concurrency/posts/14-synchronized-optimization/) （即将发布）
