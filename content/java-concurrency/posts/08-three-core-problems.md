---
title: "Java并发08：并发编程的三大核心问题 - 原子性、可见性、有序性"
date: 2025-11-20T17:00:00+08:00
draft: false
tags: ["Java并发", "原子性", "可见性", "有序性", "JMM"]
categories: ["技术"]
description: "深入理解并发编程的三大核心问题：原子性、可见性、有序性。掌握volatile、synchronized如何解决这些问题"
series: ["Java并发编程从入门到精通"]
weight: 8
stage: 1
stageTitle: "并发基础篇"
---

## 引言：为什么synchronized能解决所有问题？

```java
// volatile只解决部分问题
private volatile int count = 0;
count++;  // 仍然不安全！

// synchronized解决所有问题
private int count = 0;
public synchronized void increment() {
    count++;  // 安全
}
```

**为什么？**

关键在于理解并发编程的**三大核心问题**：
1. **原子性**（Atomicity）
2. **可见性**（Visibility）  
3. **有序性**（Ordering）

---

## 一、原子性（Atomicity）

### 1.1 什么是原子性？

**定义**：一个操作或多个操作，要么全部执行且执行过程不被打断，要么都不执行。

```java
int a = 10;     // ✅ 原子操作
a++;            // ❌ 非原子操作（3条指令）
```

### 1.2 哪些操作是原子的？

**原子操作**：
```java
// ✅ 基本类型的读写（long/double除外）
int a = 1;
boolean b = true;

// ✅ 引用类型的读写
Object obj = new Object();

// ✅ volatile变量的读写
volatile int count = 0;
count = 1;  // 原子的
```

**非原子操作**：
```java
// ❌ long/double（64位，需要两次操作）
long value = 123L;  // 非原子的（未加volatile）

// ❌ 复合操作
count++;            // read-modify-write
array[index]++;     // 非原子

// ❌ check-then-act
if (map.get(key) == null) {
    map.put(key, value);  // 竞态条件
}
```

### 1.3 如何保证原子性？

#### 方式1：synchronized

```java
public synchronized void increment() {
    count++;  // 整个方法是原子的
}
```

#### 方式2：Lock

```java
private Lock lock = new ReentrantLock();

public void increment() {
    lock.lock();
    try {
        count++;
    } finally {
        lock.unlock();
    }
}
```

#### 方式3：原子类

```java
private AtomicInteger count = new AtomicInteger(0);

public void increment() {
    count.incrementAndGet();  // 原子操作
}
```

---

## 二、可见性（Visibility）

### 2.1 什么是可见性？

**定义**：当一个线程修改了共享变量，其他线程能够立即看到这个修改。

**问题来源**：CPU缓存

```
多核CPU缓存架构

┌──────────────┐    ┌──────────────┐
│   CPU 0      │    │   CPU 1      │
│  ┌────────┐  │    │  ┌────────┐  │
│  │ L1缓存 │  │    │  │ L1缓存 │  │
│  │ count=0│  │    │  │ count=0│  │
│  └────────┘  │    │  └────────┘  │
└──────┬───────┘    └──────┬───────┘
       │                   │
       └────────┬──────────┘
                │
         ┌──────┴──────┐
         │   主内存     │
         │   count=1   │  ← 线程1已更新
         └─────────────┘
```

**问题**：线程2的CPU缓存可能没有同步，仍然读到count=0。

### 2.2 可见性问题示例

```java
public class VisibilityDemo {
    private boolean ready = false;  // ← 无volatile
    private int number = 0;
    
    // 线程1：写入
    public void writer() {
        number = 42;
        ready = true;  // ← 线程2可能看不到
    }
    
    // 线程2：读取
    public void reader() {
        while (!ready) {  // ← 可能永远循环
            Thread.yield();
        }
        System.out.println(number);  // 可能输出0
    }
}
```

### 2.3 如何保证可见性？

#### 方式1：volatile

```java
private volatile boolean ready = false;  // ← 保证可见性

public void writer() {
    number = 42;
    ready = true;  // ← 立即刷新到主内存
}

public void reader() {
    while (!ready) {  // ← 立即从主内存读取
        Thread.yield();
    }
    System.out.println(number);  // 一定输出42
}
```

**volatile的语义**：
- **写**：立即刷新到主内存
- **读**：从主内存读取最新值

#### 方式2：synchronized

```java
private boolean ready = false;

public synchronized void writer() {
    ready = true;  // 退出synchronized时刷新
}

public synchronized boolean isReady() {
    return ready;  // 进入synchronized时读取最新值
}
```

#### 方式3：final

```java
public class Holder {
    private final int value;
    
    public Holder(int value) {
        this.value = value;
    }
    // 构造函数完成后，value对所有线程可见
}
```

---

## 三、有序性（Ordering）

### 3.1 什么是有序性？

**定义**：程序执行的顺序按照代码的先后顺序执行。

**问题来源**：指令重排序

```java
// 原始代码
int a = 1;  // 语句1
int b = 2;  // 语句2
int c = a + b;  // 语句3

// 可能重排序为：
int b = 2;  // 语句2
int a = 1;  // 语句1
int c = a + b;  // 语句3
```

**单线程重排序原则**：**as-if-serial**
- 不管怎么重排序，单线程的执行结果不能改变
- 但多线程下可能有问题

### 3.2 经典案例：双重检查锁定

```java
public class Singleton {
    private static Singleton instance;
    
    public static Singleton getInstance() {
        if (instance == null) {
            synchronized (Singleton.class) {
                if (instance == null) {
                    instance = new Singleton();  // ← 有问题！
                }
            }
        }
        return instance;
    }
}
```

**问题分析**：

```java
instance = new Singleton();
```

实际包含3个步骤：
```
1. 分配内存空间
2. 初始化对象
3. instance指向内存
```

可能被重排序为：
```
1. 分配内存空间
3. instance指向内存  ← 对象未初始化！
2. 初始化对象
```

**时序问题**：
```
时间  线程A                        线程B
t1   if (instance == null)
t2   synchronized
t3   分配内存
t4   instance指向内存（未初始化）
t5                                instance != null
t6                                使用instance  ← 对象未初始化！
t7   初始化对象
```

### 3.3 如何保证有序性？

#### 方式1：volatile（禁止重排序）

```java
private static volatile Singleton instance;  // ← 禁止重排序

public static Singleton getInstance() {
    if (instance == null) {
        synchronized (Singleton.class) {
            if (instance == null) {
                instance = new Singleton();  // 不会重排序
            }
        }
    }
    return instance;
}
```

**volatile的内存屏障**：
- **写volatile前**：禁止前面的普通写与volatile写重排序
- **写volatile后**：禁止后面的普通读/写与volatile写重排序
- **读volatile后**：禁止后面的普通读与volatile读重排序

#### 方式2：synchronized

```java
// synchronized块内的代码不会与块外的代码重排序
```

---

## 四、三者的关系

### 4.1 对比表

| 问题 | synchronized | volatile | AtomicXXX |
|------|-------------|----------|-----------|
| **原子性** | ✅ | ❌ | ✅ |
| **可见性** | ✅ | ✅ | ✅ |
| **有序性** | ✅ | ✅ | ❌ |

### 4.2 使用场景

```java
// ✅ volatile：状态标志
private volatile boolean shutdown = false;

public void shutdown() {
    shutdown = true;  // 仅需可见性
}

// ❌ volatile：count++（需要原子性）
private volatile int count = 0;
count++;  // 不安全！

// ✅ synchronized：count++（需要原子性）
private int count = 0;
public synchronized void increment() {
    count++;  // 安全
}

// ✅ AtomicInteger：count++（高性能）
private AtomicInteger count = new AtomicInteger(0);
count.incrementAndGet();  // 安全且高效
```

---

## 五、happens-before原则（预告）

**happens-before**：JMM的核心规则，定义了操作的可见性。

```java
// 程序顺序规则
int a = 1;  // 操作1
int b = a + 1;  // 操作2，能看到a=1

// volatile规则
volatile boolean ready = false;
number = 42;      // 操作1
ready = true;     // 操作2（volatile写）
// 操作1 happens-before 操作2
// 其他线程读到ready=true时，一定能看到number=42
```

**详细内容**：下一阶段详细讲解。

---

## 六、总结

### 6.1 核心要点

1. **原子性**：操作不可分割
   - count++ 不是原子操作
   - 使用synchronized/Lock/AtomicXXX保证

2. **可见性**：修改对其他线程可见
   - CPU缓存导致可见性问题
   - 使用volatile/synchronized/final保证

3. **有序性**：代码不会被重排序
   - 指令重排序导致多线程问题
   - 使用volatile/synchronized禁止重排序

### 6.2 选择指南

```
需要原子性？
├─ 是 → synchronized / Lock / AtomicXXX
└─ 否
    └─ 只需要可见性？
        ├─ 是 → volatile
        └─ 否 → 普通变量
```

### 6.3 典型场景

```java
// 场景1：状态标志（只需可见性）
private volatile boolean running = true;

// 场景2：计数器（需要原子性）
private AtomicInteger count = new AtomicInteger(0);

// 场景3：复杂操作（需要所有保证）
public synchronized void transfer(int amount) {
    balance -= amount;
    otherAccount.balance += amount;
}

// 场景4：双重检查锁定（需要可见性+有序性）
private static volatile Singleton instance;
```

### 6.4 第一阶段总结

**并发基础篇8篇**已完成：
1. ✅ 为什么需要并发编程
2. ✅ 进程与线程的本质
3. ✅ Java线程的生命周期
4. ✅ 线程的创建与启动
5. ✅ 线程的中断机制
6. ✅ 线程间通信
7. ✅ 线程安全问题的本质
8. ✅ 并发编程的三大核心问题

**你已经掌握**：
- 并发的价值和原理
- 线程的生命周期和状态
- 线程的创建、启动、停止
- 线程间通信机制
- 线程安全的本质
- 原子性、可见性、有序性

**下一阶段预告**：**内存模型与原子性篇**
- CPU缓存与多核架构
- Java内存模型(JMM)详解
- happens-before原则
- volatile深度解析
- synchronized原理与优化
- CAS算法与ABA问题

---

## 扩展阅读

- [Java Concurrency in Practice](https://jcip.net/) - Chapter 16: Java Memory Model
- [JSR 133: Java Memory Model](https://jcp.org/en/jsr/detail?id=133)
- [The Java Language Specification - Chapter 17](https://docs.oracle.com/javase/specs/jls/se8/html/jls-17.html)
