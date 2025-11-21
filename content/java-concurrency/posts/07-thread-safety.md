---
title: "Java并发07：线程安全问题的本质 - 从一个计数器说起"
date: 2025-11-20T16:00:00+08:00
draft: false
tags: ["Java并发", "线程安全", "竞态条件", "临界区"]
categories: ["技术"]
description: "从多线程计数器不准的现象出发，深入理解线程安全问题的根源。掌握竞态条件、临界区、原子操作的概念"
series: ["Java并发编程从入门到精通"]
weight: 7
stage: 1
stageTitle: "并发基础篇"
---

## 引言：一个不准的计数器

```java
public class Counter {
    private int count = 0;
    
    public void increment() {
        count++;  // 看似简单的一行代码
    }
    
    public int getCount() {
        return count;
    }
}
```

**测试**：100个线程各执行1000次increment()

```java
Counter counter = new Counter();
for (int i = 0; i < 100; i++) {
    new Thread(() -> {
        for (int j = 0; j < 1000; j++) {
            counter.increment();
        }
    }).start();
}
// 期望：100,000
// 实际：95,732（每次不同！）
```

**为什么？**

---

## 一、count++不是原子操作

### 1.1 字节码分析

```java
count++;  // 一行代码
```

**实际执行**：

```
1. LOAD   count        // 读取count的值到寄存器
2. ADD    1            // 寄存器值+1
3. STORE  count        // 写回count
```

### 1.2 时序问题

```
时间  线程A                  线程B                 count
t1   LOAD count=0                                0
t2                           LOAD count=0        0
t3   ADD  (寄存器=1)                            0
t4                           ADD  (寄存器=1)     0
t5   STORE count=1                              1
t6                           STORE count=1       1

期望结果：2
实际结果：1
```

**结论**：非原子操作 + 多线程 = 数据竞争

---

## 二、线程安全的定义

**定义**：当多个线程访问一个对象时，如果不用考虑这些线程的调度和交替执行，也不需要额外的同步，调用方代码也不需要做任何协调，这个对象的行为都是正确的，那么这个对象就是线程安全的。

### 2.1 线程安全的层级

1. **不可变（Immutable）**
   ```java
   public final class ImmutablePoint {
       private final int x;
       private final int y;
       // 没有setter，天然线程安全
   }
   ```

2. **绝对线程安全**
   ```java
   // Vector、Hashtable（已过时）
   ```

3. **相对线程安全**
   ```java
   // ConcurrentHashMap（需要外部同步组合操作）
   ```

4. **线程兼容**
   ```java
   // ArrayList（需要外部同步）
   ```

5. **线程对立**
   ```java
   // Thread.suspend()/resume()（已废弃）
   ```

---

## 三、三种线程安全问题

### 3.1 数据竞争（Data Race）

**定义**：多个线程同时访问共享变量，至少一个是写操作。

```java
class DataRace {
    private int value = 0;
    
    // 线程1
    public void write() {
        value = 42;  // 写
    }
    
    // 线程2
    public int read() {
        return value;  // 读
    }
}
```

### 3.2 竞态条件（Race Condition）

**定义**：程序的正确性依赖于线程的执行顺序。

```java
class RaceCondition {
    private int value = 0;
    
    public void incrementIfZero() {
        if (value == 0) {  // 检查
            value++;        // 操作
        }  // ← check-then-act，有竞态条件
    }
}
```

**时序问题**：
```
时间  线程A                  线程B                 value
t1   if (value == 0)                            0
t2                           if (value == 0)    0
t3   value++                                    1
t4                           value++            2

预期：1
实际：2
```

### 3.3 可见性问题

```java
class VisibilityProblem {
    private boolean ready = false;
    private int number = 0;
    
    // 线程1
    public void writer() {
        number = 42;
        ready = true;  // ← 线程2可能看不到
    }
    
    // 线程2
    public void reader() {
        while (!ready) {
            Thread.yield();
        }
        System.out.println(number);  // 可能输出0！
    }
}
```

**原因**：CPU缓存，线程2可能一直读取缓存中的旧值。

---

## 四、临界区（Critical Section）

**定义**：访问共享资源的代码段。

```java
public class Counter {
    private int count = 0;
    
    public void increment() {
        // ← 临界区开始
        count++;
        // ← 临界区结束
    }
}
```

**要求**：同一时刻只能有一个线程执行临界区。

**实现**：加锁

```java
public synchronized void increment() {
    count++;  // 现在是线程安全的
}
```

---

## 五、如何保证线程安全？

### 方式1：不共享数据

```java
// ✅ 安全：局部变量
public void method() {
    int localVar = 0;  // 线程私有，安全
    localVar++;
}
```

### 方式2：使用不可变对象

```java
// ✅ 安全：final + 不可变
public final class ImmutableClass {
    private final int value;
    
    public ImmutableClass(int value) {
        this.value = value;
    }
}
```

### 方式3：加锁（synchronized）

```java
// ✅ 安全：同步方法
public synchronized void increment() {
    count++;
}
```

### 方式4：使用原子类

```java
// ✅ 安全：AtomicInteger
private AtomicInteger count = new AtomicInteger(0);

public void increment() {
    count.incrementAndGet();
}
```

### 方式5：使用并发容器

```java
// ❌ 不安全
private List<String> list = new ArrayList<>();

// ✅ 安全
private List<String> list = new CopyOnWriteArrayList<>();
```

---

## 六、共享变量 vs 局部变量

```java
public class VariableScope {
    private int shared = 0;  // 共享，不安全
    
    public void method() {
        int local = 0;       // 局部，安全
        shared++;            // ← 线程不安全
        local++;             // ← 线程安全
    }
}
```

**原则**：
- **不共享数据**：最安全
- **只读数据**：安全（不可变对象）
- **读写数据**：需要同步

---

## 七、实战案例

### 案例1：安全的单例模式

```java
// ❌ 不安全：双重检查锁定（无volatile）
public class Singleton {
    private static Singleton instance;
    
    public static Singleton getInstance() {
        if (instance == null) {
            synchronized (Singleton.class) {
                if (instance == null) {
                    instance = new Singleton();  // ← 指令重排序问题
                }
            }
        }
        return instance;
    }
}

// ✅ 安全：加volatile
public class Singleton {
    private static volatile Singleton instance;  // ← 禁止重排序
    
    public static Singleton getInstance() {
        if (instance == null) {
            synchronized (Singleton.class) {
                if (instance == null) {
                    instance = new Singleton();
                }
            }
        }
        return instance;
    }
}
```

### 案例2：安全的懒加载集合

```java
// ❌ 不安全
if (map.get(key) == null) {
    map.put(key, value);  // ← 竞态条件
}

// ✅ 安全：使用原子方法
map.putIfAbsent(key, value);
```

---

## 八、总结

### 核心要点

1. **count++不是原子操作**（3条指令）
2. **线程安全问题的根源**：共享可变状态
3. **三种线程安全问题**：
   - 数据竞争：同时访问共享变量
   - 竞态条件：check-then-act
   - 可见性：CPU缓存导致看不到修改
4. **临界区**：访问共享资源的代码段
5. **保证线程安全的5种方式**：
   - 不共享数据
   - 不可变对象
   - 加锁（synchronized）
   - 原子类（AtomicXXX）
   - 并发容器

### 安全等级

```
安全性从高到低：
不可变对象 > 不共享数据 > 原子类 > 并发容器 > synchronized
```

### 下一篇预告

**《并发编程的三大核心问题：原子性、可见性、有序性》**
- 什么是原子性、可见性、有序性？
- volatile如何保证可见性？
- synchronized如何解决所有问题？

---

## 扩展阅读

- [Java Concurrency in Practice](https://jcip.net/) - Chapter 2-3
- [Effective Java](https://www.oreilly.com/library/view/effective-java/9780134686097/) - Item 78-82
