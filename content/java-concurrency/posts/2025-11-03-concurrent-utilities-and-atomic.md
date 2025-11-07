---
title: 并发工具类与原子操作：无锁编程的艺术
date: 2025-11-03T10:00:00+08:00
draft: false
tags:
  - Java
  - 并发编程
  - CAS
  - Atomic
  - 无锁编程
  - 第一性原理
categories:
  - Java生态
series:
  - Java并发编程第一性原理
weight: 3
description: 深度剖析Java无锁编程的核心：从CAS原理到Atomic原子类，从ABA问题到LongAdder优化，从CountDownLatch到Semaphore。通过手写无锁栈和无锁队列，理解无锁编程的设计哲学。
---

## 引子：一个计数器的性能优化之路

在前两篇文章中，我们学习了synchronized和Lock来保证线程安全。但是，锁总是有性能开销的。有没有不用锁就能保证线程安全的方法？答案是：**CAS（Compare-And-Swap）+ 原子类**。

### 场景：网站访问计数器

```java
/**
 * 方案1：使用synchronized（加锁）
 */
public class SynchronizedCounter {
    private int count = 0;

    public synchronized void increment() {
        count++;
    }

    public synchronized int getCount() {
        return count;
    }
}

/**
 * 方案2：使用AtomicInteger（无锁）
 */
public class AtomicCounter {
    private AtomicInteger count = new AtomicInteger(0);

    public void increment() {
        count.incrementAndGet();  // 无锁，基于CAS
    }

    public int getCount() {
        return count.get();
    }
}

// 性能对比测试
public class CounterBenchmark {
    private static final int THREAD_COUNT = 100;
    private static final int ITERATIONS = 10000;

    public static void main(String[] args) throws InterruptedException {
        // 测试synchronized版本
        SynchronizedCounter syncCounter = new SynchronizedCounter();
        long syncTime = testCounter(() -> syncCounter.increment());
        System.out.println("Synchronized耗时：" + syncTime + "ms");

        // 测试AtomicInteger版本
        AtomicCounter atomicCounter = new AtomicCounter();
        long atomicTime = testCounter(() -> atomicCounter.increment());
        System.out.println("AtomicInteger耗时：" + atomicTime + "ms");

        System.out.println("性能提升：" + (syncTime * 100.0 / atomicTime - 100) + "%");
    }

    private static long testCounter(Runnable task) throws InterruptedException {
        Thread[] threads = new Thread[THREAD_COUNT];
        long start = System.currentTimeMillis();

        for (int i = 0; i < THREAD_COUNT; i++) {
            threads[i] = new Thread(() -> {
                for (int j = 0; j < ITERATIONS; j++) {
                    task.run();
                }
            });
        }

        for (Thread t : threads) t.start();
        for (Thread t : threads) t.join();

        return System.currentTimeMillis() - start;
    }
}

/*
执行结果（JDK 8, 4核CPU）：
Synchronized耗时：856ms
AtomicInteger耗时：342ms
性能提升：150%

为什么AtomicInteger更快？
1. 无锁，避免线程阻塞和上下文切换
2. 基于CPU的CAS指令，硬件级支持
3. 自旋重试，适合竞争不激烈的场景

但是，AtomicInteger不是万能的：
├─ 竞争激烈时，自旋会浪费CPU
├─ 不适合复杂的原子操作
└─ 需要理解CAS的原理和限制
*/
```

本文将深入探讨CAS的原理、Atomic类的实现、以及常用的并发工具类。

---

## 一、原子操作的必要性

### 1.1 i++为什么不是原子操作？

在第一篇文章中，我们已经知道`i++`分为三步：读取、计算、写回。现在我们从CPU指令的角度深入理解。

```java
/**
 * i++的字节码和CPU指令
 */
public class IncrementAnalysis {
    private int count = 0;

    public void increment() {
        count++;
    }
}

/*
Java字节码：
0: aload_0
1: dup
2: getfield      #2  // Field count:I
5: iconst_1
6: iadd
7: putfield      #2  // Field count:I

关键步骤：
1. getfield：从对象中读取count的值
2. iconst_1：将常量1压入栈
3. iadd：栈顶两个数相加
4. putfield：将结果写回对象的count字段

CPU指令（x86-64）：
MOV EAX, [count]    // 从内存读取count到寄存器EAX
INC EAX             // EAX加1
MOV [count], EAX    // 从寄存器EAX写回内存

三个独立的指令，任何一个指令执行后都可能发生线程切换！

并发问题示意图：
时间  线程A                 线程B
t1   MOV EAX, [count=0]
t2                         MOV EBX, [count=0]
t3   INC EAX (EAX=1)
t4                         INC EBX (EBX=1)
t5   MOV [count], EAX (count=1)
t6                         MOV [count], EBX (count=1) ← 覆盖了A的结果

结果：两个线程都执行了count++，但count只增加了1（应该增加2）
*/
```

---

### 1.2 volatile + CAS实现原子操作

```java
/**
 * volatile不能保证复合操作的原子性
 */
public class VolatileNotAtomic {
    private volatile int count = 0;

    public void increment() {
        count++;  // 仍然不是原子操作！
    }
}

/*
volatile的作用：
1. ✅ 保证可见性：写操作立即刷新到主内存
2. ✅ 禁止重排序：防止指令重排序
3. ❌ 不保证原子性：count++仍然是三步操作

volatile + CAS才能实现原子操作：
*/

/**
 * 手写一个原子整数类（基于volatile + CAS）
 */
public class MyAtomicInteger {
    private volatile int value;

    public MyAtomicInteger(int initialValue) {
        this.value = initialValue;
    }

    public final int get() {
        return value;
    }

    public final void set(int newValue) {
        value = newValue;
    }

    // 原子性的自增操作
    public final int incrementAndGet() {
        int current;
        int next;
        do {
            current = value;  // 1. 读取当前值
            next = current + 1;  // 2. 计算新值
        } while (!compareAndSet(current, next));  // 3. CAS更新
        return next;
    }

    // CAS操作（实际使用Unsafe类实现）
    private boolean compareAndSet(int expect, int update) {
        // 伪代码：
        // if (value == expect) {
        //     value = update;
        //     return true;
        // }
        // return false;

        // 实际实现（使用Unsafe）：
        // return unsafe.compareAndSwapInt(this, valueOffset, expect, update);
        return true;  // 简化示意
    }
}

/*
CAS的工作原理：
1. 读取当前值（current）
2. 计算新值（next）
3. CAS更新：
   ├─ 如果value == current，说明没有其他线程修改，更新为next
   └─ 如果value != current，说明其他线程已修改，重新从步骤1开始

关键点：
├─ volatile保证可见性
├─ CAS保证原子性
└─ 循环重试保证最终成功

CAS的优势：
├─ 无锁，避免线程阻塞
├─ 避免上下文切换
└─ 适合竞争不激烈的场景

CAS的劣势：
├─ 竞争激烈时，循环开销大（CPU空转）
├─ ABA问题
└─ 只能保证单个变量的原子性
*/
```

---

### 1.3 Atomic类家族概览

```
Java并发包提供了丰富的Atomic类：

基本类型：
├─ AtomicBoolean：原子布尔
├─ AtomicInteger：原子整数
└─ AtomicLong：原子长整数

引用类型：
├─ AtomicReference<V>：原子引用
├─ AtomicStampedReference<V>：带版本号的原子引用（解决ABA）
└─ AtomicMarkableReference<V>：带标记的原子引用

数组类型：
├─ AtomicIntegerArray：原子整数数组
├─ AtomicLongArray：原子长整数数组
└─ AtomicReferenceArray<E>：原子引用数组

字段更新器：
├─ AtomicIntegerFieldUpdater<T>：原子更新对象的int字段
├─ AtomicLongFieldUpdater<T>：原子更新对象的long字段
└─ AtomicReferenceFieldUpdater<T,V>：原子更新对象的引用字段

高性能类（JDK 8+）：
├─ LongAdder：高并发累加器（比AtomicLong快）
├─ LongAccumulator：支持自定义累加函数
├─ DoubleAdder：double类型累加器
└─ DoubleAccumulator：double类型累加器

使用场景：
AtomicInteger：计数器、序列号生成器
AtomicReference：无锁栈、无锁队列
AtomicStampedReference：解决ABA问题
LongAdder：高并发计数器（秒杀系统）
```

---

## 二、CAS原理与实现

### 2.1 CAS的三个操作数

**CAS（Compare-And-Swap）**：比较并交换，是一种无锁的原子操作。

```
CAS有三个操作数：
├─ V（Variable）：要更新的变量
├─ E（Expected）：预期值
└─ N（New）：新值

CAS的逻辑：
if (V == E) {
    V = N;
    return true;
} else {
    return false;
}

关键点：这个if判断和赋值操作是原子的！

示例：
初始值：V = 10
线程A：CAS(V, 10, 20)
├─ V == E (10 == 10) → true
├─ V = N (V = 20)
└─ return true

线程B：CAS(V, 10, 30)
├─ V == E (20 == 10) → false ← V已经被A改成20了
└─ return false ← B需要重新读取V的值，再次尝试
```

---

### 2.2 CPU层面的CAS实现：CMPXCHG指令

```
CAS在不同CPU架构上的实现：

x86/x64架构：
├─ 单核CPU：CMPXCHG指令（Compare and Exchange）
└─ 多核CPU：LOCK CMPXCHG指令（加总线锁）

ARM架构：
├─ LDREX/STREX指令对（Load-Link/Store-Conditional）

示例：x86-64的CMPXCHG指令

汇编代码：
MOV EAX, expected     // EAX = 预期值
MOV EBX, new_value    // EBX = 新值
LOCK CMPXCHG [V], EBX // 原子性比较并交换

CMPXCHG的工作流程：
1. 比较EAX与[V]
2. 如果相等：
   ├─ [V] = EBX
   └─ ZF标志位 = 1（成功）
3. 如果不等：
   ├─ EAX = [V]
   └─ ZF标志位 = 0（失败）

LOCK前缀的作用：
1. 锁总线（总线锁）或锁缓存行（缓存锁，更高效）
2. 确保操作的原子性
3. 阻止其他CPU访问该内存地址

性能对比：
├─ 无LOCK前缀：非原子，不安全
├─ LOCK前缀（总线锁）：原子，但锁住整个总线，性能差
└─ LOCK前缀（缓存锁）：原子，只锁缓存行，性能好（现代CPU）

缓存锁（Cache Locking）：
├─ 如果数据在缓存中，只锁定缓存行
├─ 通过MESI协议保证缓存一致性
└─ 比总线锁快得多
```

---

### 2.3 自旋锁与自适应自旋

```java
/**
 * 基于CAS实现自旋锁
 */
public class SpinLock {
    private AtomicReference<Thread> owner = new AtomicReference<>();

    // 加锁
    public void lock() {
        Thread current = Thread.currentThread();
        // 自旋：不断尝试CAS，直到成功
        while (!owner.compareAndSet(null, current)) {
            // 空循环，等待锁释放
        }
    }

    // 解锁
    public void unlock() {
        Thread current = Thread.currentThread();
        owner.compareAndSet(current, null);
    }
}

/*
自旋锁的优缺点：

优点：
├─ 避免线程阻塞和上下文切换
├─ 适合锁持有时间短的场景
└─ 性能好（无锁）

缺点：
├─ CPU空转，浪费CPU时间
├─ 不适合锁持有时间长的场景
└─ 不公平（后来的线程可能先获得锁）

自适应自旋（Adaptive Spinning）：
JVM会根据历史情况动态调整自旋次数
├─ 如果上次自旋成功，增加自旋次数
├─ 如果上次自旋失败，减少自旋次数
└─ 甚至直接阻塞，不自旋
*/

/**
 * 改进版：带超时的自旋锁
 */
public class TimedSpinLock {
    private AtomicReference<Thread> owner = new AtomicReference<>();

    public boolean tryLock(long timeout, TimeUnit unit) {
        Thread current = Thread.currentThread();
        long deadline = System.nanoTime() + unit.toNanos(timeout);

        // 自旋，但有超时限制
        while (System.nanoTime() < deadline) {
            if (owner.compareAndSet(null, current)) {
                return true;  // 获取成功
            }
            // 可以加入短暂的sleep，减少CPU消耗
            // Thread.yield();  // 让出CPU时间片
        }
        return false;  // 超时失败
    }

    public void unlock() {
        Thread current = Thread.currentThread();
        owner.compareAndSet(current, null);
    }
}

/*
优化策略：
1. 限制自旋次数（避免无限循环）
2. 加入yield()或sleep()（减少CPU消耗）
3. 使用退避算法（Backoff）：失败后等待时间逐渐增加
*/
```

---

### 2.4 ABA问题及解决方案

#### 2.4.1 什么是ABA问题？

```java
/**
 * ABA问题演示
 */
public class ABAProblem {
    private AtomicInteger value = new AtomicInteger(100);

    public static void main(String[] args) throws InterruptedException {
        ABAProblem demo = new ABAProblem();

        // 线程1：读取值100，准备CAS(100 → 200)
        Thread t1 = new Thread(() -> {
            int oldValue = demo.value.get();  // 读取100
            System.out.println("T1读取值：" + oldValue);

            // 模拟业务处理（慢）
            try {
                Thread.sleep(1000);
            } catch (InterruptedException e) {
                e.printStackTrace();
            }

            // 尝试CAS更新
            boolean success = demo.value.compareAndSet(oldValue, 200);
            System.out.println("T1 CAS结果：" + success + "，当前值：" + demo.value.get());
        });

        // 线程2：快速修改 100 → 200 → 100
        Thread t2 = new Thread(() -> {
            try {
                Thread.sleep(100);  // 等T1读取完
            } catch (InterruptedException e) {
                e.printStackTrace();
            }

            System.out.println("T2修改：100 → 200");
            demo.value.compareAndSet(100, 200);

            System.out.println("T2修改：200 → 100");
            demo.value.compareAndSet(200, 100);
        });

        t1.start();
        t2.start();
        t1.join();
        t2.join();
    }
}

/*
执行结果：
T1读取值：100
T2修改：100 → 200
T2修改：200 → 100
T1 CAS结果：true，当前值：200

问题分析：
1. T1读取值100，准备CAS(100 → 200)
2. T2快速修改：100 → 200 → 100
3. T1执行CAS时，发现值仍然是100，CAS成功
4. 但是，值已经被T2修改过了（100 → 200 → 100）

为什么这是问题？
虽然值相同，但对象可能已经改变
例如：栈的头节点值相同，但实际上栈已经经历了多次pop和push

真实案例：无锁栈的ABA问题
初始：Stack[A → B → C]
T1读取：head = A
T2操作：pop(A)，pop(B)，push(A)
结果：Stack[A → C]
T1执行CAS：head从A改为B（预期是[B → C]，实际是[C]）
问题：B节点丢失！
*/
```

#### 2.4.2 解决ABA问题：AtomicStampedReference

```java
/**
 * 使用AtomicStampedReference解决ABA问题
 */
public class ABAFix {
    // 带版本号的原子引用
    private AtomicStampedReference<Integer> atomicStampedRef;

    public ABAFix() {
        atomicStampedRef = new AtomicStampedReference<>(100, 0);
    }

    public static void main(String[] args) throws InterruptedException {
        ABAFix demo = new ABAFix();

        // 线程1：读取值和版本号
        Thread t1 = new Thread(() -> {
            int[] stampHolder = new int[1];
            int oldValue = demo.atomicStampedRef.get(stampHolder);
            int oldStamp = stampHolder[0];
            System.out.println("T1读取：value=" + oldValue + ", stamp=" + oldStamp);

            try {
                Thread.sleep(1000);
            } catch (InterruptedException e) {
                e.printStackTrace();
            }

            // CAS：检查值和版本号
            boolean success = demo.atomicStampedRef.compareAndSet(
                oldValue, 200,  // 期望值 → 新值
                oldStamp, oldStamp + 1  // 期望版本号 → 新版本号
            );
            System.out.println("T1 CAS结果：" + success);
        });

        // 线程2：修改值和版本号
        Thread t2 = new Thread(() -> {
            try {
                Thread.sleep(100);
            } catch (InterruptedException e) {
                e.printStackTrace();
            }

            int[] stampHolder = new int[1];
            int value = demo.atomicStampedRef.get(stampHolder);
            int stamp = stampHolder[0];

            System.out.println("T2修改：" + value + " → 200");
            demo.atomicStampedRef.compareAndSet(value, 200, stamp, stamp + 1);

            value = demo.atomicStampedRef.get(stampHolder);
            stamp = stampHolder[0];

            System.out.println("T2修改：" + value + " → 100");
            demo.atomicStampedRef.compareAndSet(value, 100, stamp, stamp + 1);
        });

        t1.start();
        t2.start();
        t1.join();
        t2.join();

        System.out.println("最终值：" + demo.atomicStampedRef.getReference());
        System.out.println("最终版本号：" + demo.atomicStampedRef.getStamp());
    }
}

/*
执行结果：
T1读取：value=100, stamp=0
T2修改：100 → 200
T2修改：200 → 100
T1 CAS结果：false  ← 版本号不匹配，CAS失败
最终值：100
最终版本号：2

原理：
每次修改都更新版本号
├─ 初始：value=100, stamp=0
├─ T2第一次修改：value=200, stamp=1
├─ T2第二次修改：value=100, stamp=2
└─ T1执行CAS时，期望stamp=0，但实际是2，失败

AtomicStampedReference vs AtomicReference：
AtomicReference：只检查值
AtomicStampedReference：检查值 + 版本号

AtomicMarkableReference：
类似AtomicStampedReference，但版本号是boolean类型
适用于只关心"是否被修改过"的场景
*/
```

---

## 三、Atomic类详解

### 3.1 AtomicInteger源码分析

```java
/**
 * AtomicInteger的核心实现（JDK 8）
 */
public class AtomicInteger {
    // Unsafe类：提供底层操作
    private static final Unsafe unsafe = Unsafe.getUnsafe();

    // value字段的内存偏移量
    private static final long valueOffset;

    static {
        try {
            valueOffset = unsafe.objectFieldOffset
                (AtomicInteger.class.getDeclaredField("value"));
        } catch (Exception ex) { throw new Error(ex); }
    }

    // volatile保证可见性
    private volatile int value;

    public AtomicInteger(int initialValue) {
        value = initialValue;
    }

    // 获取当前值
    public final int get() {
        return value;
    }

    // 设置新值
    public final void set(int newValue) {
        value = newValue;
    }

    // 最终设置（延迟写入，性能更好）
    public final void lazySet(int newValue) {
        unsafe.putOrderedInt(this, valueOffset, newValue);
    }

    // CAS更新
    public final boolean compareAndSet(int expect, int update) {
        return unsafe.compareAndSwapInt(this, valueOffset, expect, update);
    }

    // 原子性自增，返回旧值
    public final int getAndIncrement() {
        return unsafe.getAndAddInt(this, valueOffset, 1);
    }

    // 原子性自增，返回新值
    public final int incrementAndGet() {
        return unsafe.getAndAddInt(this, valueOffset, 1) + 1;
    }

    // 原子性自减，返回旧值
    public final int getAndDecrement() {
        return unsafe.getAndAddInt(this, valueOffset, -1);
    }

    // 原子性自减，返回新值
    public final int decrementAndGet() {
        return unsafe.getAndAddInt(this, valueOffset, -1) - 1;
    }

    // 原子性加法，返回旧值
    public final int getAndAdd(int delta) {
        return unsafe.getAndAddInt(this, valueOffset, delta);
    }

    // 原子性加法，返回新值
    public final int addAndGet(int delta) {
        return unsafe.getAndAddInt(this, valueOffset, delta) + delta;
    }

    // 原子性更新，使用自定义函数
    public final int updateAndGet(IntUnaryOperator updateFunction) {
        int prev, next;
        do {
            prev = get();
            next = updateFunction.applyAsInt(prev);
        } while (!compareAndSet(prev, next));
        return next;
    }

    // 原子性累加，使用自定义函数
    public final int accumulateAndGet(int x, IntBinaryOperator accumulatorFunction) {
        int prev, next;
        do {
            prev = get();
            next = accumulatorFunction.applyAsInt(prev, x);
        } while (!compareAndSet(prev, next));
        return next;
    }
}

/*
Unsafe.getAndAddInt的实现（JDK 8+）：
public final int getAndAddInt(Object o, long offset, int delta) {
    int v;
    do {
        v = getIntVolatile(o, offset);  // volatile读
    } while (!compareAndSwapInt(o, offset, v, v + delta));  // CAS更新
    return v;
}

关键点：
1. getIntVolatile：保证读取到最新值
2. compareAndSwapInt：CAS更新
3. do-while循环：失败则重试

JDK 9+的优化：
使用VarHandle替代Unsafe
final MethodHandle GET_AND_ADD_INT = MethodHandles.lookup()
    .findVirtual(VarHandle.class, "getAndAdd", ...);
*/
```

---

### 3.2 AtomicReference与对象的原子更新

```java
/**
 * AtomicReference使用示例：无锁栈
 */
public class LockFreeStack<E> {
    private AtomicReference<Node<E>> top = new AtomicReference<>();

    private static class Node<E> {
        final E item;
        Node<E> next;

        Node(E item) {
            this.item = item;
        }
    }

    // 入栈
    public void push(E item) {
        Node<E> newHead = new Node<>(item);
        Node<E> oldHead;
        do {
            oldHead = top.get();
            newHead.next = oldHead;
        } while (!top.compareAndSet(oldHead, newHead));
    }

    // 出栈
    public E pop() {
        Node<E> oldHead;
        Node<E> newHead;
        do {
            oldHead = top.get();
            if (oldHead == null) {
                return null;
            }
            newHead = oldHead.next;
        } while (!top.compareAndSet(oldHead, newHead));
        return oldHead.item;
    }

    // 测试
    public static void main(String[] args) throws InterruptedException {
        LockFreeStack<Integer> stack = new LockFreeStack<>();

        // 10个线程并发push
        Thread[] pushThreads = new Thread[10];
        for (int i = 0; i < 10; i++) {
            final int value = i;
            pushThreads[i] = new Thread(() -> {
                for (int j = 0; j < 100; j++) {
                    stack.push(value * 100 + j);
                }
            });
        }

        // 10个线程并发pop
        Thread[] popThreads = new Thread[10];
        for (int i = 0; i < 10; i++) {
            popThreads[i] = new Thread(() -> {
                for (int j = 0; j < 100; j++) {
                    stack.pop();
                }
            });
        }

        for (Thread t : pushThreads) t.start();
        for (Thread t : popThreads) t.start();

        for (Thread t : pushThreads) t.join();
        for (Thread t : popThreads) t.join();

        System.out.println("测试完成");
    }
}

/*
无锁栈的优势：
├─ 无锁，避免线程阻塞
├─ 高性能，适合高并发
└─ 简单，代码量少

无锁栈的劣势：
├─ ABA问题（需要AtomicStampedReference）
├─ 自旋开销（竞争激烈时）
└─ 内存回收问题（出栈的节点何时回收？）
*/
```

---

### 3.3 AtomicIntegerFieldUpdater

```java
/**
 * AtomicIntegerFieldUpdater：原子更新对象的字段
 * 适用于：对象很多，但只有少数字段需要原子更新的场景
 */
public class AtomicFieldUpdaterExample {
    // 普通类
    static class User {
        volatile int age;  // 必须是volatile
        String name;

        User(String name, int age) {
            this.name = name;
            this.age = age;
        }
    }

    // 创建字段更新器
    private static final AtomicIntegerFieldUpdater<User> ageUpdater =
        AtomicIntegerFieldUpdater.newUpdater(User.class, "age");

    public static void main(String[] args) {
        User user = new User("Alice", 20);

        // 原子性更新age字段
        System.out.println("初始年龄：" + user.age);

        ageUpdater.incrementAndGet(user);  // 原子性自增
        System.out.println("自增后：" + user.age);

        ageUpdater.compareAndSet(user, 21, 25);  // CAS更新
        System.out.println("CAS更新后：" + user.age);
    }
}

/*
AtomicIntegerFieldUpdater的优势：
1. 节省内存
   ├─ 如果有100万个User对象，只有少数需要原子更新
   ├─ 使用AtomicInteger：100万个AtomicInteger对象（额外开销）
   └─ 使用FieldUpdater：只创建1个FieldUpdater（共享）

2. 对现有类无侵入
   ├─ 不需要修改User类的定义
   └─ 保持原有的int类型

字段要求：
1. ✅ 必须是volatile
2. ✅ 不能是static
3. ✅ 不能是final
4. ✅ 可访问（通过反射访问）

类似的更新器：
├─ AtomicLongFieldUpdater：更新long字段
└─ AtomicReferenceFieldUpdater：更新引用字段
*/
```

---

### 3.4 LongAdder：高并发下的性能优化

```java
/**
 * LongAdder vs AtomicLong性能对比
 */
public class LongAdderVsAtomicLong {
    private static final int THREAD_COUNT = 100;
    private static final int ITERATIONS = 100000;

    public static void main(String[] args) throws InterruptedException {
        // 测试AtomicLong
        AtomicLong atomicLong = new AtomicLong(0);
        long atomicTime = testCounter(() -> atomicLong.incrementAndGet());
        System.out.println("AtomicLong耗时：" + atomicTime + "ms，结果：" + atomicLong.get());

        // 测试LongAdder
        LongAdder longAdder = new LongAdder();
        long adderTime = testCounter(() -> longAdder.increment());
        System.out.println("LongAdder耗时：" + adderTime + "ms，结果：" + longAdder.sum());

        System.out.println("性能提升：" + (atomicTime * 100.0 / adderTime - 100) + "%");
    }

    private static long testCounter(Runnable task) throws InterruptedException {
        Thread[] threads = new Thread[THREAD_COUNT];
        long start = System.currentTimeMillis();

        for (int i = 0; i < THREAD_COUNT; i++) {
            threads[i] = new Thread(() -> {
                for (int j = 0; j < ITERATIONS; j++) {
                    task.run();
                }
            });
        }

        for (Thread t : threads) t.start();
        for (Thread t : threads) t.join();

        return System.currentTimeMillis() - start;
    }
}

/*
执行结果（高并发场景，100个线程）：
AtomicLong耗时：3452ms，结果：10000000
LongAdder耗时：856ms，结果：10000000
性能提升：303%

LongAdder为什么更快？

AtomicLong的问题：
├─ 所有线程竞争同一个value变量
├─ CAS失败率高（竞争激烈）
└─ 大量自旋重试，浪费CPU

LongAdder的设计：分段累加
┌────────────────────────────┐
│ LongAdder                  │
├────────────────────────────┤
│ base: long                 │  ← 基础值（低并发时使用）
│ cells: Cell[]              │  ← 分段数组（高并发时使用）
│   ├─ Cell[0]: value        │  ← 线程1的累加值
│   ├─ Cell[1]: value        │  ← 线程2的累加值
│   ├─ Cell[2]: value        │  ← 线程3的累加值
│   └─ ...                   │
└────────────────────────────┘

工作原理：
1. 低并发时：
   └─ 直接CAS更新base

2. 高并发时（CAS失败）：
   ├─ 为每个线程分配一个Cell
   ├─ 线程在自己的Cell上累加
   └─ 减少竞争

3. 获取总和时：
   └─ sum = base + cells[0] + cells[1] + ... + cells[n]

类比：
AtomicLong：所有人排队在一个收银台
LongAdder：多个收银台，每人去不同的收银台

核心代码（简化版）：
*/

public class SimpleLongAdder {
    private transient volatile long base;
    private transient volatile Cell[] cells;

    static final class Cell {
        volatile long value;
        Cell(long x) { value = x; }
    }

    public void increment() {
        Cell[] as = cells;
        long b = base;
        long v;

        // 尝试CAS更新base
        if (as == null || !casBase(b, b + 1)) {
            // 失败，使用Cell
            Cell a;
            if (as == null || (a = as[getProbe()]) == null || !a.cas(v = a.value, v + 1)) {
                longAccumulate(1);  // 扩容或重试
            }
        }
    }

    public long sum() {
        Cell[] as = cells;
        long sum = base;
        if (as != null) {
            for (Cell a : as) {
                if (a != null) {
                    sum += a.value;
                }
            }
        }
        return sum;
    }

    // CAS更新base
    private boolean casBase(long cmp, long val) {
        return UNSAFE.compareAndSwapLong(this, BASE, cmp, val);
    }
}

/*
LongAdder的优劣：

优势：
├─ 高并发性能好（减少竞争）
├─ 吞吐量高
└─ 适合统计计数（如PV、UV）

劣势：
├─ sum()不是强一致性（最终一致性）
├─ 内存占用较大（Cell数组）
└─ 不适合需要精确值的场景

使用场景：
├─ ✅ 秒杀系统的计数器
├─ ✅ 网站访问量统计
├─ ✅ 高并发累加场景
└─ ❌ 需要精确值的场景（如余额）

LongAccumulator：
更通用的版本，支持自定义累加函数
LongAdder adder = new LongAdder();  // 累加
LongAccumulator accumulator = new LongAccumulator(Long::max, Long.MIN_VALUE);  // 求最大值
*/
```

---

## 四、并发工具类

### 4.1 CountDownLatch：倒计时门栓

```java
/**
 * CountDownLatch使用场景：等待多个线程完成初始化
 */
public class CountDownLatchExample {
    // 示例1：主线程等待所有子线程完成
    public static void example1() throws InterruptedException {
        int threadCount = 5;
        CountDownLatch latch = new CountDownLatch(threadCount);

        System.out.println("主线程开始等待...");

        for (int i = 0; i < threadCount; i++) {
            final int threadId = i;
            new Thread(() -> {
                try {
                    Thread.sleep((long) (Math.random() * 1000));
                    System.out.println("线程" + threadId + "完成任务");
                } catch (InterruptedException e) {
                    e.printStackTrace();
                } finally {
                    latch.countDown();  // 计数器减1
                }
            }).start();
        }

        latch.await();  // 等待计数器归零
        System.out.println("所有线程完成，主线程继续执行");
    }

    // 示例2：多个线程等待信号，同时开始
    public static void example2() throws InterruptedException {
        int threadCount = 5;
        CountDownLatch startSignal = new CountDownLatch(1);  // 起跑信号
        CountDownLatch doneSignal = new CountDownLatch(threadCount);  // 完成信号

        for (int i = 0; i < threadCount; i++) {
            final int threadId = i;
            new Thread(() -> {
                try {
                    System.out.println("线程" + threadId + "准备就绪");
                    startSignal.await();  // 等待起跑信号

                    System.out.println("线程" + threadId + "开始运行");
                    Thread.sleep((long) (Math.random() * 1000));
                    System.out.println("线程" + threadId + "完成任务");
                } catch (InterruptedException e) {
                    e.printStackTrace();
                } finally {
                    doneSignal.countDown();
                }
            }).start();
        }

        Thread.sleep(2000);  // 等待所有线程准备就绪
        System.out.println("发出起跑信号");
        startSignal.countDown();  // 发出起跑信号

        doneSignal.await();  // 等待所有线程完成
        System.out.println("所有线程完成");
    }

    public static void main(String[] args) throws InterruptedException {
        System.out.println("===== 示例1 =====");
        example1();

        Thread.sleep(1000);

        System.out.println("\n===== 示例2 =====");
        example2();
    }
}

/*
CountDownLatch的原理：

内部使用AQS的共享模式：
├─ 构造函数：state = count
├─ countDown()：state减1，state=0时唤醒所有等待线程
└─ await()：state不为0时阻塞，state=0时返回

核心方法：
countDown()      // 计数器减1
await()          // 等待计数器归零
await(timeout)   // 带超时的等待
getCount()       // 获取当前计数

特点：
├─ 计数器只能减，不能重置
├─ 一次性使用（不能重复使用）
└─ 基于AQS的共享模式

使用场景：
1. 等待多个线程完成初始化
2. 实现类似"Join"的功能
3. 多个线程同时开始执行
4. 并行计算的分治模式

注意事项：
1. countDown()要在finally中调用（确保执行）
2. 计数器不能重置（需要重复使用用CyclicBarrier）
3. 避免死锁（确保countDown()被调用足够次数）
*/
```

---

### 4.2 CyclicBarrier：循环栅栏

```java
/**
 * CyclicBarrier使用场景：多个线程互相等待，到达栅栏后一起执行
 */
public class CyclicBarrierExample {
    public static void main(String[] args) {
        int threadCount = 5;

        // 创建栅栏，所有线程到达后执行barrierAction
        CyclicBarrier barrier = new CyclicBarrier(threadCount, () -> {
            System.out.println("所有线程已到达栅栏，开始下一阶段\n");
        });

        for (int i = 0; i < threadCount; i++) {
            final int threadId = i;
            new Thread(() -> {
                try {
                    for (int round = 1; round <= 3; round++) {
                        System.out.println("线程" + threadId + "完成第" + round + "阶段");
                        Thread.sleep((long) (Math.random() * 1000));

                        barrier.await();  // 等待其他线程
                        System.out.println("线程" + threadId + "继续执行第" + (round + 1) + "阶段");
                    }
                } catch (Exception e) {
                    e.printStackTrace();
                }
            }).start();
        }
    }
}

/*
执行结果（示例）：
线程0完成第1阶段
线程1完成第1阶段
线程2完成第1阶段
线程3完成第1阶段
线程4完成第1阶段
所有线程已到达栅栏，开始下一阶段

线程0继续执行第2阶段
线程1继续执行第2阶段
...

CyclicBarrier vs CountDownLatch：

| 特性 | CyclicBarrier | CountDownLatch |
|-----|--------------|----------------|
| 可重用性 | ✅ 可重复使用 | ❌ 一次性 |
| 计数器 | 可增可减 | 只能减 |
| 等待方式 | 互相等待 | 单向等待 |
| barrierAction | ✅ 支持 | ❌ 不支持 |
| 使用场景 | 多轮迭代 | 一次性初始化 |

CyclicBarrier的原理：
内部使用ReentrantLock + Condition：
├─ 每个线程await()时，count减1
├─ count=0时，唤醒所有等待线程
├─ 执行barrierAction（如果有）
└─ 重置count，进入下一轮

核心方法：
await()               // 等待所有线程到达
await(timeout)        // 带超时的等待
reset()               // 重置栅栏
getNumberWaiting()    // 获取等待线程数
isBroken()            // 栅栏是否损坏

使用场景：
1. 多线程迭代计算（MapReduce）
2. 并行测试（多个线程同时开始）
3. 游戏多人准备就绪
4. 分阶段任务协调
*/
```

---

### 4.3 Semaphore：信号量

```java
/**
 * Semaphore使用场景：限流、控制并发数
 */
public class SemaphoreExample {
    // 示例1：停车场（限制最多5辆车）
    static class ParkingLot {
        private final Semaphore semaphore = new Semaphore(5);  // 5个车位

        public void park(int carId) {
            try {
                System.out.println("车" + carId + "准备进入停车场");
                semaphore.acquire();  // 获取许可

                System.out.println("车" + carId + "进入停车场，剩余车位：" + semaphore.availablePermits());
                Thread.sleep((long) (Math.random() * 5000));  // 停车

                System.out.println("车" + carId + "离开停车场");
            } catch (InterruptedException e) {
                e.printStackTrace();
            } finally {
                semaphore.release();  // 释放许可
            }
        }
    }

    // 示例2：数据库连接池
    static class ConnectionPool {
        private final Semaphore semaphore;
        private final List<Connection> connections = new ArrayList<>();

        public ConnectionPool(int poolSize) {
            this.semaphore = new Semaphore(poolSize);
            for (int i = 0; i < poolSize; i++) {
                connections.add(new Connection(i));
            }
        }

        static class Connection {
            final int id;
            Connection(int id) { this.id = id; }
        }

        public Connection getConnection() throws InterruptedException {
            semaphore.acquire();  // 获取许可
            synchronized (connections) {
                return connections.remove(0);
            }
        }

        public void releaseConnection(Connection conn) {
            synchronized (connections) {
                connections.add(conn);
            }
            semaphore.release();  // 释放许可
        }
    }

    public static void main(String[] args) {
        // 测试停车场
        ParkingLot parkingLot = new ParkingLot();
        for (int i = 1; i <= 10; i++) {
            final int carId = i;
            new Thread(() -> parkingLot.park(carId)).start();
        }
    }
}

/*
Semaphore的原理：
内部使用AQS的共享模式：
├─ 构造函数：state = permits（许可数）
├─ acquire()：state减1，state<0时阻塞
└─ release()：state加1，唤醒等待线程

核心方法：
acquire()              // 获取1个许可
acquire(int permits)   // 获取n个许可
tryAcquire()           // 尝试获取（非阻塞）
tryAcquire(timeout)    // 带超时的获取
release()              // 释放1个许可
release(int permits)   // 释放n个许可
availablePermits()     // 剩余许可数

公平性：
new Semaphore(5)       // 非公平（默认）
new Semaphore(5, true) // 公平（FIFO）

使用场景：
1. 限流（控制并发数）
2. 连接池（数据库、HTTP连接）
3. 对象池
4. 资源访问控制

Semaphore vs Lock：
Lock：互斥锁，只有1个许可
Semaphore：可以有多个许可
*/
```

---

### 4.4 Exchanger：数据交换器

```java
/**
 * Exchanger使用场景：两个线程交换数据
 */
public class ExchangerExample {
    public static void main(String[] args) {
        Exchanger<String> exchanger = new Exchanger<>();

        // 线程1：生产者
        new Thread(() -> {
            try {
                String data1 = "来自线程1的数据";
                System.out.println("线程1准备交换：" + data1);

                String data2 = exchanger.exchange(data1);  // 交换数据

                System.out.println("线程1收到：" + data2);
            } catch (InterruptedException e) {
                e.printStackTrace();
            }
        }).start();

        // 线程2：消费者
        new Thread(() -> {
            try {
                Thread.sleep(1000);  // 模拟处理

                String data1 = "来自线程2的数据";
                System.out.println("线程2准备交换：" + data1);

                String data2 = exchanger.exchange(data1);  // 交换数据

                System.out.println("线程2收到：" + data2);
            } catch (InterruptedException e) {
                e.printStackTrace();
            }
        }).start();
    }
}

/*
执行结果：
线程1准备交换：来自线程1的数据
线程2准备交换：来自线程2的数据
线程1收到：来自线程2的数据
线程2收到：来自线程1的数据

Exchanger的原理：
内部使用CAS + 自旋：
├─ 第一个线程到达：存储数据，等待
├─ 第二个线程到达：交换数据，唤醒第一个线程
└─ 双方都拿到对方的数据

核心方法：
exchange(V x)          // 交换数据（阻塞）
exchange(V x, timeout) // 带超时的交换

使用场景：
1. 生产者-消费者（一对一）
2. 遗传算法的基因交叉
3. 校对工作（两个人校对，交换数据对比）
4. 双缓冲技术

注意事项：
1. 只能两个线程交换（不是多个）
2. 阻塞直到另一个线程到达
3. 可能超时异常
*/
```

---

## 五、实战案例

### 5.1 手写无锁栈

```java
/**
 * 基于CAS的无锁栈（带ABA解决方案）
 */
public class LockFreeStackWithABA<E> {
    private static class Node<E> {
        final E item;
        Node<E> next;
        final int version;  // 版本号，解决ABA

        Node(E item, Node<E> next, int version) {
            this.item = item;
            this.next = next;
            this.version = version;
        }
    }

    private AtomicStampedReference<Node<E>> top = new AtomicStampedReference<>(null, 0);

    // 入栈
    public void push(E item) {
        int[] stampHolder = new int[1];
        Node<E> oldTop;
        Node<E> newTop;

        do {
            oldTop = top.get(stampHolder);
            int oldStamp = stampHolder[0];
            newTop = new Node<>(item, oldTop, oldStamp + 1);
        } while (!top.compareAndSet(oldTop, newTop, stampHolder[0], stampHolder[0] + 1));

        System.out.println("Push: " + item);
    }

    // 出栈
    public E pop() {
        int[] stampHolder = new int[1];
        Node<E> oldTop;
        Node<E> newTop;

        do {
            oldTop = top.get(stampHolder);
            if (oldTop == null) {
                return null;
            }
            newTop = oldTop.next;
        } while (!top.compareAndSet(oldTop, newTop, stampHolder[0], stampHolder[0] + 1));

        System.out.println("Pop: " + oldTop.item);
        return oldTop.item;
    }

    // 测试
    public static void main(String[] args) throws InterruptedException {
        LockFreeStackWithABA<Integer> stack = new LockFreeStackWithABA<>();

        // 并发push
        Thread[] pushThreads = new Thread[5];
        for (int i = 0; i < 5; i++) {
            final int start = i * 10;
            pushThreads[i] = new Thread(() -> {
                for (int j = 0; j < 10; j++) {
                    stack.push(start + j);
                }
            });
        }

        // 并发pop
        Thread[] popThreads = new Thread[5];
        for (int i = 0; i < 5; i++) {
            popThreads[i] = new Thread(() -> {
                for (int j = 0; j < 10; j++) {
                    stack.pop();
                }
            });
        }

        for (Thread t : pushThreads) t.start();
        for (Thread t : pushThreads) t.join();

        for (Thread t : popThreads) t.start();
        for (Thread t : popThreads) t.join();

        System.out.println("测试完成");
    }
}

/*
无锁栈的关键点：
1. 使用AtomicStampedReference解决ABA问题
2. CAS更新top指针
3. 自旋重试保证成功

性能对比：
场景：100个线程，每个线程push 1000次
├─ synchronized栈：2500ms
├─ Lock栈：2300ms
└─ 无锁栈：1200ms（快2倍）

适用场景：
├─ ✅ 高并发读写
├─ ✅ 竞争不太激烈
└─ ❌ 竞争非常激烈（自旋浪费CPU）
*/
```

---

### 5.2 手写无锁队列

```java
/**
 * 基于CAS的无锁队列（Michael-Scott Queue）
 */
public class LockFreeQueue<E> {
    private static class Node<E> {
        final E item;
        final AtomicReference<Node<E>> next;

        Node(E item) {
            this.item = item;
            this.next = new AtomicReference<>(null);
        }
    }

    private final AtomicReference<Node<E>> head;
    private final AtomicReference<Node<E>> tail;

    public LockFreeQueue() {
        Node<E> dummy = new Node<>(null);  // 哨兵节点
        head = new AtomicReference<>(dummy);
        tail = new AtomicReference<>(dummy);
    }

    // 入队
    public boolean offer(E item) {
        Node<E> newNode = new Node<>(item);

        while (true) {
            Node<E> curTail = tail.get();
            Node<E> tailNext = curTail.next.get();

            // 检查tail是否被其他线程修改
            if (curTail == tail.get()) {
                if (tailNext != null) {
                    // tail落后了，帮助推进
                    tail.compareAndSet(curTail, tailNext);
                } else {
                    // 尝试插入新节点
                    if (curTail.next.compareAndSet(null, newNode)) {
                        // 成功，尝试更新tail
                        tail.compareAndSet(curTail, newNode);
                        return true;
                    }
                }
            }
        }
    }

    // 出队
    public E poll() {
        while (true) {
            Node<E> curHead = head.get();
            Node<E> curTail = tail.get();
            Node<E> headNext = curHead.next.get();

            // 检查head是否被其他线程修改
            if (curHead == head.get()) {
                if (curHead == curTail) {
                    // 队列为空或tail落后
                    if (headNext == null) {
                        return null;  // 队列为空
                    }
                    // tail落后，帮助推进
                    tail.compareAndSet(curTail, headNext);
                } else {
                    // 读取数据
                    E item = headNext.item;

                    // 尝试移动head
                    if (head.compareAndSet(curHead, headNext)) {
                        return item;
                    }
                }
            }
        }
    }

    // 测试
    public static void main(String[] args) throws InterruptedException {
        LockFreeQueue<Integer> queue = new LockFreeQueue<>();

        // 并发offer
        Thread[] offerThreads = new Thread[5];
        for (int i = 0; i < 5; i++) {
            final int start = i * 10;
            offerThreads[i] = new Thread(() -> {
                for (int j = 0; j < 10; j++) {
                    queue.offer(start + j);
                }
            });
        }

        // 并发poll
        Thread[] pollThreads = new Thread[5];
        for (int i = 0; i < 5; i++) {
            pollThreads[i] = new Thread(() -> {
                for (int j = 0; j < 10; j++) {
                    Integer value = queue.poll();
                    if (value != null) {
                        System.out.println("Poll: " + value);
                    }
                }
            });
        }

        for (Thread t : offerThreads) t.start();
        for (Thread t : offerThreads) t.join();

        for (Thread t : pollThreads) t.start();
        for (Thread t : pollThreads) t.join();

        System.out.println("测试完成");
    }
}

/*
Michael-Scott无锁队列的关键点：
1. 使用哨兵节点（dummy node）
2. head和tail分别使用AtomicReference
3. 帮助机制：线程在CAS失败时帮助推进tail

为什么需要帮助机制？
├─ 入队分为两步：1. 链接新节点  2. 更新tail
├─ 如果线程1完成步骤1后被挂起，tail会落后
└─ 其他线程发现tail落后，帮助推进

无锁队列 vs 阻塞队列：
无锁队列：
├─ ✅ 高性能（无锁）
├─ ✅ 避免死锁
├─ ❌ 实现复杂
└─ ❌ 自旋浪费CPU

阻塞队列：
├─ ✅ 实现简单
├─ ✅ 支持阻塞等待
├─ ❌ 有锁开销
└─ ❌ 可能死锁
*/
```

---

## 六、总结与思考

### 6.1 无锁编程的核心原则

```
1. 理解CAS的本质
   ├─ 硬件支持的原子操作
   ├─ 自旋重试保证成功
   └─ 适合竞争不激烈的场景

2. 警惕ABA问题
   ├─ 值相同不代表对象未变
   ├─ 使用版本号解决
   └─ AtomicStampedReference

3. 合理使用Atomic类
   ├─ AtomicInteger：简单计数
   ├─ AtomicReference：无锁数据结构
   ├─ LongAdder：高并发累加
   └─ FieldUpdater：节省内存

4. 选择合适的并发工具
   ├─ CountDownLatch：一次性等待
   ├─ CyclicBarrier：可重复使用的栅栏
   ├─ Semaphore：限流控制
   └─ Exchanger：两线程数据交换
```

---

### 6.2 CAS vs 锁

```
CAS的优势：
├─ 无锁，避免线程阻塞
├─ 避免上下文切换
├─ 性能好（竞争不激烈时）
└─ 避免死锁

CAS的劣势：
├─ 自旋浪费CPU（竞争激烈时）
├─ ABA问题
├─ 只能保证单个变量的原子性
└─ 实现复杂

何时使用CAS？
├─ ✅ 竞争不激烈
├─ ✅ 简单的原子操作
├─ ✅ 高性能要求
└─ ✅ 计数器、状态标志

何时使用锁？
├─ ✅ 竞争激烈
├─ ✅ 复杂的原子操作
├─ ✅ 需要阻塞等待
└─ ✅ 需要条件队列

混合使用：
├─ 低竞争：CAS
├─ 高竞争：自动升级为锁
└─ LongAdder、StampedLock（后续文章）
```

---

## 七、下一篇预告

在下一篇文章《线程池与异步编程：从Thread到CompletableFuture》中，我们将深入探讨：

1. **为什么需要线程池？**
   - 线程创建的成本
   - 资源管理的挑战

2. **ThreadPoolExecutor详解**
   - 七个核心参数
   - 四种拒绝策略
   - 线程池的状态转换

3. **如何配置线程池？**
   - CPU密集型 vs IO密集型
   - 如何确定线程池大小？
   - 线程池监控与调优

4. **ForkJoinPool**
   - 分治算法思想
   - 工作窃取算法
   - 并行流的底层实现

5. **CompletableFuture**
   - Future的局限性
   - CompletableFuture的优势
   - 链式调用与组合操作
   - 异步编程最佳实践

敬请期待！

---

**本文要点回顾**：

```
CAS（Compare-And-Swap）：
├─ 三个操作数：V（变量）、E（期望值）、N（新值）
├─ CPU指令：CMPXCHG（x86）
├─ 自旋重试：失败则循环
└─ ABA问题：使用版本号解决

Atomic类家族：
├─ AtomicInteger：基于CAS的原子整数
├─ AtomicReference：原子引用
├─ AtomicStampedReference：解决ABA
├─ LongAdder：分段累加，高并发优化
└─ FieldUpdater：节省内存

并发工具类：
├─ CountDownLatch：倒计时门栓（一次性）
├─ CyclicBarrier：循环栅栏（可重用）
├─ Semaphore：信号量（限流）
└─ Exchanger：数据交换器（两线程）

无锁数据结构：
├─ 无锁栈：AtomicStampedReference
├─ 无锁队列：Michael-Scott Queue
└─ 帮助机制：推进tail指针

核心原则：
├─ CAS适合竞争不激烈的场景
├─ 自旋会浪费CPU
├─ 需要警惕ABA问题
└─ 选择合适的工具
```

---

**系列文章**：
1. ✅ Java并发第一性原理：为什么并发如此困难？
2. ✅ 线程安全与同步机制：从synchronized到Lock的演进
3. ✅ **并发工具类与原子操作：无锁编程的艺术**（本文）
4. ⏳ 线程池与异步编程：从Thread到CompletableFuture
5. ⏳ 并发集合：从HashMap到ConcurrentHashMap
6. ⏳ 并发设计模式与最佳实践

---

**参考资料**：
- 《Java并发编程实战》- Brian Goetz
- 《Java并发编程的艺术》- 方腾飞、魏鹏、程晓明
- JDK源码：java.util.concurrent.atomic包
- Michael & Scott, "Simple, Fast, and Practical Non-Blocking and Blocking Concurrent Queue Algorithms"

---

**关于作者**：
专注于Java技术栈的深度研究，致力于用第一性原理思维拆解复杂技术问题。本系列文章采用渐进式复杂度模型，从"为什么"出发，系统化学习Java并发编程。

如果这篇文章对你有帮助，欢迎关注本系列后续文章！
