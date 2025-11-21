---
title: "Java并发06：线程间通信 - wait/notify机制详解"
date: 2025-11-20T15:00:00+08:00
draft: false
tags: ["Java并发", "wait", "notify", "线程通信"]
categories: ["技术"]
description: "从生产者-消费者问题出发，深入理解wait/notify机制。掌握对象监视器、等待队列的原理，避免虚假唤醒陷阱"
series: ["Java并发编程从入门到精通"]
weight: 6
stage: 1
stageTitle: "并发基础篇"
---

## 引言：生产者-消费者问题

经典场景：生产者生产数据→放入队列→消费者从队列取数据。

**问题**：
- 队列满时，生产者如何等待？
- 队列空时，消费者如何等待？
- 如何通知对方继续工作？

这就是 **wait/notify** 机制要解决的问题。

---

## 一、wait/notify基础

### 1.1 三个核心方法

```java
public class Object {
    // 释放锁，进入等待队列
    public final void wait() throws InterruptedException {}
    
    // 释放锁，等待指定时间
    public final void wait(long timeout) throws InterruptedException {}
    
    // 唤醒一个等待线程
    public final void notify() {}
    
    // 唤醒所有等待线程
    public final void notifyAll() {}
}
```

**关键约束**：必须在 **synchronized** 块中调用！

### 1.2 工作原理

```
对象监视器（Monitor）结构

┌─────────────────────────────────────┐
│          Object Monitor              │
│                                      │
│  Entry Set（入口队列）               │
│  ┌───────┐  ┌───────┐               │
│  │线程2  │  │线程3  │  ← BLOCKED    │
│  └───────┘  └───────┘               │
│       ↓                              │
│  ┌────────────┐                     │
│  │  Owner     │  ← RUNNABLE          │
│  │  (线程1)   │                      │
│  └────────────┘                     │
│       ↓ wait()                       │
│  Wait Set（等待队列）                │
│  ┌───────┐  ┌───────┐               │
│  │线程4  │  │线程5  │  ← WAITING    │
│  └───────┘  └───────┘               │
│       ↑ notify()                     │
└─────────────────────────────────────┘
```

---

## 二、生产者-消费者实现

### 2.1 标准实现

```java
class SharedQueue {
    private Queue<Integer> queue = new LinkedList<>();
    private int capacity = 5;

    // 生产
    public synchronized void produce(int value) throws InterruptedException {
        while (queue.size() == capacity) {  // ← 用while，不是if
            System.out.println("队列满，生产者等待");
            wait();  // 释放锁，进入等待
        }
        queue.offer(value);
        System.out.println("生产: " + value);
        notifyAll();  // 唤醒消费者
    }

    // 消费
    public synchronized int consume() throws InterruptedException {
        while (queue.isEmpty()) {  // ← 用while，不是if
            System.out.println("队列空，消费者等待");
            wait();
        }
        int value = queue.poll();
        System.out.println("消费: " + value);
        notifyAll();  // 唤醒生产者
        return value;
    }
}
```

### 2.2 为什么用while不用if？

```java
// ❌ 错误：使用if
if (queue.isEmpty()) {
    wait();  // 被唤醒后直接往下执行
}
int value = queue.poll();  // ← 可能queue仍然为空！

// ✅ 正确：使用while
while (queue.isEmpty()) {
    wait();  // 被唤醒后重新检查条件
}
int value = queue.poll();  // 确保queue不为空
```

**原因**：**虚假唤醒**（Spurious Wakeup）
- 线程可能在没有notify的情况下被唤醒
- POSIX标准允许这种情况
- **解决**：总是用while循环检查条件

---

## 三、wait() vs sleep()

| 维度 | wait() | sleep() |
|------|--------|---------|
| **所属类** | Object | Thread |
| **是否释放锁** | ✅ 释放 | ❌ 不释放 |
| **必须在synchronized中** | ✅ 是 | ❌ 否 |
| **唤醒方式** | notify/notifyAll | 超时自动醒 |
| **线程状态** | WAITING | TIMED_WAITING |

```java
// wait()会释放锁
synchronized (lock) {
    lock.wait();  // 释放锁，其他线程可以获得lock
}

// sleep()不释放锁
synchronized (lock) {
    Thread.sleep(1000);  // 持有锁，其他线程无法获得lock
}
```

---

## 四、notify() vs notifyAll()

### 4.1 区别

- **notify()**：随机唤醒一个等待线程
- **notifyAll()**：唤醒所有等待线程

### 4.2 何时用notifyAll()？

**推荐**：大多数情况使用 `notifyAll()`

```java
// ✅ 推荐：notifyAll()
public synchronized void produce(int value) {
    queue.offer(value);
    notifyAll();  // 唤醒所有消费者
}

// ❌ 可能死锁：notify()
public synchronized void produce(int value) {
    queue.offer(value);
    notify();  // 可能唤醒另一个生产者而不是消费者
}
```

**使用notify()的前提**：
1. 只有一种类型的等待线程
2. 每次notify只需要唤醒一个线程

---

## 五、常见陷阱

### 陷阱1：没在synchronized中调用

```java
// ❌ 错误
public void wrongWait() throws InterruptedException {
    obj.wait();  // IllegalMonitorStateException
}

// ✅ 正确
public void correctWait() throws InterruptedException {
    synchronized (obj) {
        obj.wait();
    }
}
```

### 陷阱2：wait的对象不对

```java
// ❌ 错误
synchronized (a) {
    b.wait();  // IllegalMonitorStateException
}

// ✅ 正确
synchronized (a) {
    a.wait();
}
```

### 陷阱3：notify后立即释放锁

```java
synchronized (lock) {
    condition = true;
    lock.notify();  // 唤醒线程
    // 但锁还没释放，被唤醒的线程仍然阻塞
    doSomethingElse();  // 执行其他操作
}  // ← 这里才释放锁
```

---

## 六、总结

### 核心要点

1. **wait/notify必须在synchronized中使用**
2. **总是用while循环检查条件**（避免虚假唤醒）
3. **优先使用notifyAll()**（避免死锁）
4. **wait()会释放锁，sleep()不会**
5. **notify()后不会立即释放锁**

### 标准模板

```java
// 等待条件成立
synchronized (lock) {
    while (!condition) {
        lock.wait();
    }
    // 条件成立，执行操作
}

// 改变条件并通知
synchronized (lock) {
    condition = true;
    lock.notifyAll();
}
```

### 下一篇预告

**《线程安全问题的本质：从一个计数器说起》**
- count++为什么不安全？
- 什么是竞态条件？
- 如何保证线程安全？

---

## 扩展阅读

- [Java Concurrency in Practice](https://jcip.net/) - Chapter 14
- [Object.wait() JavaDoc](https://docs.oracle.com/javase/8/docs/api/java/lang/Object.html#wait--)
