---
title: "Java并发16：CAS算法与ABA问题 - 无锁编程的基石与陷阱"
date: 2025-11-20T19:30:00+08:00
draft: false
tags: ["Java并发", "CAS", "ABA问题", "Unsafe", "无锁算法"]
categories: ["技术"]
description: "深入理解CAS（Compare-And-Swap）算法的底层实现、ABA问题的本质和解决方案、以及如何正确使用CAS实现无锁数据结构。"
series: ["Java并发编程从入门到精通"]
weight: 16
stage: 2
stageTitle: "内存模型与原子性篇"
---

## 引言：原子类的秘密武器

在上一篇文章中，我们学习了AtomicInteger等原子类，它们的核心就是CAS操作：

```java
public final int incrementAndGet() {
    return unsafe.getAndAddInt(this, valueOffset, 1) + 1;
}

// Unsafe中的实现
public final int getAndAddInt(Object o, long offset, int delta) {
    int v;
    do {
        v = getIntVolatile(o, offset);  // 读取当前值
    } while (!compareAndSwapInt(o, offset, v, v + delta));  // CAS更新
    return v;
}
```

**三个核心问题**：
1. CAS是如何实现的？（底层原理）
2. CAS有什么问题？（ABA、自旋、单变量）
3. 如何解决这些问题？（AtomicStampedReference等）

本篇文章将深入CAS算法的每个细节。

---

## 一、CAS算法的原理

### 1.1 CAS的定义

**CAS（Compare-And-Swap）**：比较并交换

```java
boolean CAS(内存地址V, 期望值A, 新值B) {
    if (V的值 == A) {
        V的值 = B;
        return true;  // 更新成功
    } else {
        return false;  // 更新失败
    }
}
```

**关键特性**：
- **原子操作**：整个比较和交换过程不可分割
- **硬件支持**：由CPU指令保证原子性
- **无锁**：不需要加锁，避免线程阻塞

### 1.2 CAS的工作流程

**示例**：两个线程同时执行`count++`

```
初始值: count = 0

线程1                           线程2
│                               │
├─ 读取count = 0                │
│                               ├─ 读取count = 0
│                               │
├─ 计算newValue = 0 + 1 = 1     │
│                               ├─ 计算newValue = 0 + 1 = 1
│                               │
├─ CAS(count, 0, 1)             │
│  └─ count == 0? 是            │
│     └─ count = 1，成功         │
│                               │
│                               ├─ CAS(count, 0, 1)
│                               │  └─ count == 0? 否（已经是1了）
│                               │     └─ 失败，重试
│                               │
│                               ├─ 重新读取count = 1
│                               ├─ 计算newValue = 1 + 1 = 2
│                               ├─ CAS(count, 1, 2)
│                               │  └─ count == 1? 是
│                               │     └─ count = 2，成功
```

**关键点**：
- CAS失败后，线程会**自旋重试**
- 不会阻塞，一直尝试直到成功

### 1.3 Java中的CAS：Unsafe类

Java的CAS操作由`sun.misc.Unsafe`类提供：

```java
public final class Unsafe {
    // CAS操作（Java方法）
    public final native boolean compareAndSwapInt(
        Object o,      // 对象
        long offset,   // 字段在对象中的偏移量
        int expected,  // 期望值
        int update     // 新值
    );

    public final native boolean compareAndSwapLong(...);
    public final native boolean compareAndSwapObject(...);

    // 获取字段的偏移量
    public native long objectFieldOffset(Field field);

    // volatile读写
    public native int getIntVolatile(Object o, long offset);
    public native void putIntVolatile(Object o, long offset, int value);
}
```

**AtomicInteger的实现**：
```java
public class AtomicInteger {
    private static final Unsafe unsafe = Unsafe.getUnsafe();
    private static final long valueOffset;

    static {
        try {
            // 获取value字段的内存偏移量
            valueOffset = unsafe.objectFieldOffset(
                AtomicInteger.class.getDeclaredField("value"));
        } catch (Exception ex) {
            throw new Error(ex);
        }
    }

    private volatile int value;  // 实际存储的值

    public final int incrementAndGet() {
        return unsafe.getAndAddInt(this, valueOffset, 1) + 1;
    }

    public final boolean compareAndSet(int expect, int update) {
        return unsafe.compareAndSwapInt(this, valueOffset, expect, update);
    }
}
```

### 1.4 CPU层面的实现

CAS操作最终由CPU指令实现：

#### x86平台：CMPXCHG指令

```asm
# compareAndSwapInt的汇编实现（简化）
mov eax, [expected]     # 加载期望值到eax
lock cmpxchg [address], [update]
# lock前缀：锁定总线，保证原子性
# cmpxchg：比较eax与[address]，相等则交换
```

**lock前缀的作用**：
1. **锁定缓存行**：当前CPU独占该缓存行
2. **MESI协议**：通知其他CPU缓存失效
3. **内存屏障**：禁止指令重排序

#### ARM平台：LDREX/STREX指令

```asm
retry:
    ldrex  r1, [r0]        # Load-Exclusive：加载并标记独占
    cmp    r1, expected    # 比较
    bne    fail            # 不相等，跳转失败
    strex  r2, update, [r0] # Store-Exclusive：条件存储
    cmp    r2, #0          # 检查是否成功
    bne    retry           # 失败，重试
success:
    mov    r0, #1
    bx     lr
fail:
    mov    r0, #0
    bx     lr
```

**LDREX/STREX机制**：
- **LDREX**：标记地址为独占访问
- **STREX**：只有标记未被清除时才成功
- 其他CPU访问会清除标记

---

## 二、CAS的三大问题

### 2.1 问题1：ABA问题

#### 问题场景

```
初始值: V = A

时刻1: 线程1读取V = A
时刻2: 线程2修改V: A → B
时刻3: 线程2再修改V: B → A
时刻4: 线程1执行CAS(V, A, C)
       ├─ V == A? 是
       └─ V = C，成功

但是：V在中间经历了 A → B → A 的变化！
```

#### 实际案例

**链表的CAS删除**：

```java
public class LinkedStack<T> {
    private static class Node<T> {
        T value;
        Node<T> next;

        Node(T value) {
            this.value = value;
        }
    }

    private AtomicReference<Node<T>> top = new AtomicReference<>();

    public void push(T value) {
        Node<T> newTop = new Node<>(value);
        Node<T> oldTop;
        do {
            oldTop = top.get();
            newTop.next = oldTop;
        } while (!top.compareAndSet(oldTop, newTop));
    }

    public T pop() {
        Node<T> oldTop;
        Node<T> newTop;
        do {
            oldTop = top.get();
            if (oldTop == null) {
                return null;
            }
            newTop = oldTop.next;
        } while (!top.compareAndSet(oldTop, newTop));
        return oldTop.value;
    }
}
```

**ABA问题**：
```
初始栈: top → A → B → C

线程1: pop()
├─ 读取oldTop = A
├─ 读取newTop = B
└─ 准备CAS(top, A, B)  ← 暂停

线程2: pop() → 弹出A
       pop() → 弹出B
       push(A) → 压入A

当前栈: top → A → C  (B已被弹出)

线程1: 恢复执行
└─ CAS(top, A, B) 成功！  ← 问题！
   └─ top = B，但B.next可能是野指针（B已被弹出）
```

**结果**：
- CAS成功，但破坏了栈的结构
- B节点可能已被回收，导致悬空指针

#### ABA问题的危害

并非所有场景都有问题：

**无害的ABA**：
```java
AtomicInteger counter = new AtomicInteger(100);

// 线程1
counter.incrementAndGet();  // 100 → 101

// 线程2
counter.compareAndSet(100, 200);  // 100 → 200
counter.compareAndSet(200, 100);  // 200 → 100

// 线程1
counter.compareAndSet(100, 101);  // 成功，没问题
```

**有害的ABA**：
```java
// 链表、栈、队列等引用类型
AtomicReference<Node> ref = ...;
// 中间节点被删除又重新添加，引用关系已改变
```

### 2.2 问题2：循环时间长，开销大

**问题**：
```java
public final int incrementAndGet() {
    int v;
    do {
        v = getIntVolatile(this, valueOffset);
    } while (!compareAndSwapInt(this, valueOffset, v, v + 1));
    // 如果竞争激烈，可能循环很多次
    return v + 1;
}
```

**性能测试**：
```java
public class CASSpinTest {
    private AtomicInteger count = new AtomicInteger(0);

    public static void main(String[] args) throws InterruptedException {
        CASSpinTest test = new CASSpinTest();
        int threadCount = 100;

        long start = System.currentTimeMillis();
        CountDownLatch latch = new CountDownLatch(threadCount);

        for (int i = 0; i < threadCount; i++) {
            new Thread(() -> {
                for (int j = 0; j < 1_000_000; j++) {
                    test.count.incrementAndGet();
                }
                latch.countDown();
            }).start();
        }

        latch.await();
        long time = System.currentTimeMillis() - start;

        System.out.println("100线程竞争: " + time + "ms");
        System.out.println("结果: " + test.count.get());
    }
}
```

**实测结果**：
```
10线程竞争: 280ms
100线程竞争: 8500ms  ← 性能下降严重
```

**解决方案**：
- 使用**LongAdder**（分段累加，减少竞争）
- 使用**锁**（竞争激烈时，锁的性能可能更好）

### 2.3 问题3：只能保证单个变量的原子性

**问题**：
```java
// ❌ 无法保证两个变量的原子性
AtomicInteger x = new AtomicInteger(0);
AtomicInteger y = new AtomicInteger(0);

// 需要原子地更新x和y
x.incrementAndGet();  // 1
y.incrementAndGet();  // 2
// 在1和2之间可能有其他线程读取，看到不一致的状态
```

**解决方案1：使用AtomicReference包装**
```java
class Point {
    final int x;
    final int y;

    Point(int x, int y) {
        this.x = x;
        this.y = y;
    }
}

AtomicReference<Point> pointRef = new AtomicReference<>(new Point(0, 0));

// 原子地更新x和y
Point oldPoint, newPoint;
do {
    oldPoint = pointRef.get();
    newPoint = new Point(oldPoint.x + 1, oldPoint.y + 1);
} while (!pointRef.compareAndSet(oldPoint, newPoint));
```

**解决方案2：使用锁**
```java
private int x = 0;
private int y = 0;

public synchronized void update() {
    x++;
    y++;
}
```

---

## 三、ABA问题的解决方案

### 3.1 AtomicStampedReference

**核心思想**：维护版本号（stamp）

```java
public class AtomicStampedReference<V> {
    private static class Pair<T> {
        final T reference;
        final int stamp;  // 版本号

        Pair(T reference, int stamp) {
            this.reference = reference;
            this.stamp = stamp;
        }
    }

    private volatile Pair<V> pair;

    public boolean compareAndSet(
        V expectedReference,   // 期望的引用
        V newReference,        // 新引用
        int expectedStamp,     // 期望的版本号
        int newStamp           // 新版本号
    ) {
        Pair<V> current = pair;
        return expectedReference == current.reference &&
               expectedStamp == current.stamp &&
               ((newReference == current.reference &&
                 newStamp == current.stamp) ||
                casPair(current, Pair.of(newReference, newStamp)));
    }
}
```

### 3.2 完整示例：解决链表ABA

```java
public class SafeLinkedStack<T> {
    private static class Node<T> {
        T value;
        Node<T> next;

        Node(T value) {
            this.value = value;
        }
    }

    private AtomicStampedReference<Node<T>> top =
        new AtomicStampedReference<>(null, 0);

    public void push(T value) {
        Node<T> newTop = new Node<>(value);
        int[] stampHolder = new int[1];
        Node<T> oldTop;

        do {
            oldTop = top.get(stampHolder);
            int oldStamp = stampHolder[0];
            newTop.next = oldTop;
        } while (!top.compareAndSet(
            oldTop, newTop,
            oldStamp, oldStamp + 1  // 版本号+1
        ));
    }

    public T pop() {
        int[] stampHolder = new int[1];
        Node<T> oldTop;
        Node<T> newTop;

        do {
            oldTop = top.get(stampHolder);
            if (oldTop == null) {
                return null;
            }
            int oldStamp = stampHolder[0];
            newTop = oldTop.next;
        } while (!top.compareAndSet(
            oldTop, newTop,
            oldStamp, oldStamp + 1  // 版本号+1
        ));

        return oldTop.value;
    }
}
```

**测试代码**：
```java
public class ABAPreventionTest {
    public static void main(String[] args) throws InterruptedException {
        SafeLinkedStack<Integer> stack = new SafeLinkedStack<>();

        stack.push(1);
        stack.push(2);
        stack.push(3);

        // 线程1：准备pop
        Thread t1 = new Thread(() -> {
            int[] stamp = new int[1];
            var oldTop = stack.top.get(stamp);
            int oldStamp = stamp[0];

            System.out.println("线程1: 读取top=" + oldTop.value + ", stamp=" + oldStamp);

            // 模拟延迟
            try {
                Thread.sleep(100);
            } catch (InterruptedException e) {
                e.printStackTrace();
            }

            // 尝试CAS
            boolean success = stack.top.compareAndSet(
                oldTop, oldTop.next, oldStamp, oldStamp + 1);
            System.out.println("线程1 CAS结果: " + success);
        });

        // 线程2：ABA操作
        Thread t2 = new Thread(() -> {
            stack.pop();  // 3
            stack.pop();  // 2
            stack.push(3); // 重新压入3
            System.out.println("线程2: 完成ABA操作");
        });

        t1.start();
        Thread.sleep(10);  // 确保t1先读取
        t2.start();

        t1.join();
        t2.join();
    }
}
```

**输出**：
```
线程1: 读取top=3, stamp=0
线程2: 完成ABA操作
线程1 CAS结果: false  ← 检测到ABA，CAS失败
```

### 3.3 AtomicMarkableReference

**适用场景**：不关心修改了多少次，只关心是否被修改过

```java
public class AtomicMarkableReference<V> {
    private static class Pair<T> {
        final T reference;
        final boolean mark;  // 标记位（true/false）

        Pair(T reference, boolean mark) {
            this.reference = reference;
            this.mark = mark;
        }
    }

    public boolean compareAndSet(
        V expectedReference,
        V newReference,
        boolean expectedMark,
        boolean newMark
    ) { ... }
}
```

**使用示例**：
```java
public class MarkableExample {
    private static class Node {
        int value;
        AtomicMarkableReference<Node> next;

        Node(int value) {
            this.value = value;
            this.next = new AtomicMarkableReference<>(null, false);
        }
    }

    // 标记删除（逻辑删除）
    public boolean markDeleted(Node node) {
        boolean[] markHolder = new boolean[1];
        Node next = node.next.get(markHolder);

        if (markHolder[0]) {
            return false;  // 已经被标记
        }

        // 标记为已删除
        return node.next.compareAndSet(next, next, false, true);
    }
}
```

---

## 四、CAS的实战应用

### 4.1 无锁队列（Michael-Scott Queue）

```java
public class LockFreeQueue<T> {
    private static class Node<T> {
        final T value;
        final AtomicReference<Node<T>> next;

        Node(T value) {
            this.value = value;
            this.next = new AtomicReference<>(null);
        }
    }

    private final AtomicReference<Node<T>> head;
    private final AtomicReference<Node<T>> tail;

    public LockFreeQueue() {
        Node<T> dummy = new Node<>(null);
        head = new AtomicReference<>(dummy);
        tail = new AtomicReference<>(dummy);
    }

    public void enqueue(T value) {
        Node<T> newNode = new Node<>(value);
        while (true) {
            Node<T> curTail = tail.get();
            Node<T> tailNext = curTail.next.get();

            if (curTail == tail.get()) {
                if (tailNext != null) {
                    // 尾指针落后，帮助推进
                    tail.compareAndSet(curTail, tailNext);
                } else {
                    // 尝试插入
                    if (curTail.next.compareAndSet(null, newNode)) {
                        // 推进尾指针
                        tail.compareAndSet(curTail, newNode);
                        return;
                    }
                }
            }
        }
    }

    public T dequeue() {
        while (true) {
            Node<T> curHead = head.get();
            Node<T> curTail = tail.get();
            Node<T> headNext = curHead.next.get();

            if (curHead == head.get()) {
                if (curHead == curTail) {
                    if (headNext == null) {
                        return null;  // 队列为空
                    }
                    tail.compareAndSet(curTail, headNext);
                } else {
                    T value = headNext.value;
                    if (head.compareAndSet(curHead, headNext)) {
                        return value;
                    }
                }
            }
        }
    }
}
```

### 4.2 无锁计数器（分段累加）

```java
public class StripedCounter {
    private static final int STRIPE_COUNT = Runtime.getRuntime().availableProcessors();
    private final AtomicInteger[] stripes;

    public StripedCounter() {
        stripes = new AtomicInteger[STRIPE_COUNT];
        for (int i = 0; i < STRIPE_COUNT; i++) {
            stripes[i] = new AtomicInteger(0);
        }
    }

    public void increment() {
        int index = ThreadLocalRandom.current().nextInt(STRIPE_COUNT);
        stripes[index].incrementAndGet();
    }

    public long get() {
        long sum = 0;
        for (AtomicInteger stripe : stripes) {
            sum += stripe.get();
        }
        return sum;
    }
}
```

---

## 五、总结

### 5.1 核心要点

1. **CAS算法**
   - Compare-And-Swap：比较并交换
   - 原子操作，由CPU指令保证
   - 无锁算法的基础

2. **底层实现**
   - Java：Unsafe类
   - x86：CMPXCHG + lock前缀
   - ARM：LDREX/STREX指令对

3. **三大问题**
   - ABA问题：中间值变化无法检测
   - 循环时间长：高竞争下性能差
   - 单变量限制：无法原子更新多个变量

4. **解决方案**
   - ABA问题：AtomicStampedReference（版本号）
   - 性能问题：LongAdder（分段累加）
   - 多变量：AtomicReference包装或使用锁

5. **使用建议**
   - 低竞争：CAS性能优于锁
   - 高竞争：锁可能更好
   - 读多写少：读写锁
   - 简单累加：LongAdder

### 5.2 最佳实践

1. **优先使用JDK提供的原子类**
   ```java
   // ✅ 好
   AtomicInteger counter = new AtomicInteger();

   // ❌ 不好（自己实现CAS）
   Unsafe unsafe = Unsafe.getUnsafe();
   ```

2. **关注ABA问题**
   ```java
   // 引用类型要注意ABA
   AtomicStampedReference<Node> ref = ...;

   // 基本类型通常无需担心
   AtomicInteger count = ...;
   ```

3. **高并发选择LongAdder**
   ```java
   // 100+线程竞争
   LongAdder adder = new LongAdder();
   ```

4. **复杂场景使用锁**
   ```java
   // 多个变量有关联关系
   synchronized (lock) {
       x++;
       y++;
   }
   ```

### 5.3 思考题

1. 为什么CAS需要volatile变量？
2. 什么情况下CAS的性能会比synchronized差？
3. LongAdder为什么能解决高并发下的性能问题？

### 5.4 第二阶段总结

**恭喜完成第二阶段！**

我们已经学习了：
- 09 - CPU缓存与多核架构
- 10 - Java内存模型(JMM)
- 11 - happens-before原则
- 12 - volatile关键字
- 13 - synchronized原理
- 14 - synchronized优化演进
- 15 - 原子类AtomicXXX
- 16 - CAS算法与ABA问题

**下一阶段预告**：第三阶段 - Lock与并发工具篇，我们将学习ReentrantLock、ReadWriteLock、线程池、并发容器等高级并发工具。

---

## 扩展阅读

1. **论文**：
   - "Simple, Fast, and Practical Non-Blocking and Blocking Concurrent Queue Algorithms" - Michael & Scott
   - "Practical lock-freedom" - Keir Fraser

2. **书籍**：
   - 《Java并发编程实战》第15章：原子变量与非阻塞同步
   - 《并发的艺术》- 布莱恩·格茨

3. **源码**：
   - java.util.concurrent.atomic包
   - sun.misc.Unsafe类
   - OpenJDK hotspot源码

4. **工具**：
   - JCStress：并发正确性测试
   - hsdis：查看汇编代码

---

**系列文章**：
- 上一篇：[Java并发15：原子类AtomicXXX详解](/java-concurrency/posts/15-atomic-classes/)
- 下一篇：[Java并发17：Lock接口与ReentrantLock](/java-concurrency/posts/17-lock-and-reentrantlock/) （第三阶段开始）
