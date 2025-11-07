---
title: 线程安全与同步机制：从synchronized到Lock的演进
date: 2025-11-03T10:00:00+08:00
draft: false
tags:
  - Java
  - 并发编程
  - synchronized
  - Lock
  - AQS
  - 第一性原理
categories:
  - Java生态
series:
  - Java并发编程第一性原理
weight: 2
description: 深度剖析Java线程安全的本质，从synchronized的锁升级机制到Lock的灵活性，再到AQS的实现原理。通过真实案例理解同步机制的设计哲学，掌握死锁预防策略。
---

## 引子：一个购物车的线程安全之路

在上一篇文章中，我们理解了并发编程的三大核心问题：可见性、原子性、有序性。现在我们要解决这个问题：**如何让多线程安全地访问共享数据？**

### 场景：电商购物车的并发问题

```java
/**
 * 购物车服务（线程不安全版本）
 * 问题：多个线程同时添加商品，可能导致数据丢失
 */
public class ShoppingCart {
    private Map<String, Integer> items = new HashMap<>();  // 商品ID → 数量

    // 添加商品到购物车
    public void addItem(String productId, int quantity) {
        Integer currentQty = items.get(productId);
        if (currentQty == null) {
            items.put(productId, quantity);
        } else {
            items.put(productId, currentQty + quantity);
        }
    }

    // 获取购物车总商品数
    public int getTotalItems() {
        int total = 0;
        for (Integer qty : items.values()) {
            total += qty;
        }
        return total;
    }
}

// 并发测试
public class CartTest {
    public static void main(String[] args) throws InterruptedException {
        ShoppingCart cart = new ShoppingCart();

        // 10个线程并发添加商品
        Thread[] threads = new Thread[10];
        for (int i = 0; i < 10; i++) {
            threads[i] = new Thread(() -> {
                for (int j = 0; j < 100; j++) {
                    cart.addItem("product-123", 1);
                }
            });
        }

        for (Thread t : threads) t.start();
        for (Thread t : threads) t.join();

        System.out.println("期望数量：1000");
        System.out.println("实际数量：" + cart.getTotalItems());
    }
}

/*
执行结果（多次运行不一致）：
第1次：实际数量：856  ❌ 丢失144次更新
第2次：实际数量：923  ❌ 丢失77次更新
第3次：实际数量：891  ❌ 丢失109次更新

问题分析：
1. HashMap本身不是线程安全的
2. addItem方法不是原子操作（读取、计算、写入三步）
3. 多线程并发执行导致数据竞争

解决方案演进：
Level 1：使用synchronized → 简单但粗粒度
Level 2：使用ReentrantLock → 灵活但需要手动管理
Level 3：使用ConcurrentHashMap → 高性能（下一篇讲解）
*/
```

本文将深入探讨如何通过synchronized和Lock来保证线程安全。

---

## 一、线程安全的本质

### 1.1 什么是线程安全？

**定义**：当多个线程访问某个类时，不管运行时环境采用何种调度方式或者这些线程将如何交替执行，并且在主调代码中不需要任何额外的同步或协同，这个类都能表现出正确的行为，那么就称这个类是线程安全的。

**核心要素**：
```
线程安全 = 正确性 + 不依赖外部同步

正确性：
├─ 不变性条件（Invariants）得到维护
├─ 后验条件（Postconditions）得到满足
└─ 观察结果与预期一致

不依赖外部同步：
├─ 类本身保证线程安全
├─ 调用者无需额外同步
└─ 任何调度方式下都正确
```

---

### 1.2 线程安全的三种实现方式

#### 方式1：无状态（Stateless）

```java
/**
 * 无状态类：没有字段，不依赖外部状态
 * 天然线程安全，因为没有共享数据
 */
public class StatelessCalculator {
    // 只有方法，没有字段
    public int add(int a, int b) {
        return a + b;
    }

    public int multiply(int a, int b) {
        return a * b;
    }
}

/*
为什么线程安全？
1. 没有实例变量或类变量
2. 所有数据都在栈上（方法参数、局部变量）
3. 每个线程有独立的栈帧，互不干扰

适用场景：
├─ 工具类（Math、StringUtils）
├─ 无状态Service（Spring中的@Service通常是无状态的）
└─ 函数式编程风格
*/
```

#### 方式2：不可变（Immutable）

```java
/**
 * 不可变对象：创建后状态不能改变
 * 天然线程安全，因为状态无法修改
 */
public final class ImmutablePoint {
    private final int x;
    private final int y;

    public ImmutablePoint(int x, int y) {
        this.x = x;
        this.y = y;
    }

    public int getX() { return x; }
    public int getY() { return y; }

    // 返回新对象，而不是修改当前对象
    public ImmutablePoint move(int deltaX, int deltaY) {
        return new ImmutablePoint(x + deltaX, y + deltaY);
    }
}

/*
不可变对象的要求：
1. ✅ 类声明为final（防止子类破坏不可变性）
2. ✅ 所有字段都是final
3. ✅ 所有字段都是private
4. ✅ 不提供setter方法
5. ✅ 如果字段是可变对象，确保外部无法获取引用

典型案例：
├─ String（最经典的不可变类）
├─ Integer、Long等包装类
├─ LocalDate、LocalDateTime（JDK 8）
└─ BigInteger、BigDecimal

优势：
├─ 线程安全（无需同步）
├─ 可以安全共享（作为HashMap的key）
├─ 简化并发编程
└─ 适合做缓存

劣势：
├─ 每次修改都创建新对象（内存开销）
└─ 不适合频繁修改的场景
*/
```

#### 方式3：同步（Synchronization）

```java
/**
 * 通过同步机制保证线程安全
 * 适用于有状态且需要修改的场景
 */
public class SynchronizedCounter {
    private int count = 0;

    // 方法级同步
    public synchronized void increment() {
        count++;
    }

    public synchronized int getCount() {
        return count;
    }
}

/*
同步机制的演进：
Level 1：synchronized（Java 1.0，JVM内置）
Level 2：Lock接口（Java 5，java.util.concurrent）
Level 3：Atomic类（Java 5，无锁CAS）

本文重点：synchronized和Lock
下一篇：Atomic类和无锁编程
*/
```

---

### 1.3 不可变对象的威力

**案例：String为什么是不可变的？**

```java
// String的设计
public final class String {
    private final char[] value;  // JDK 8
    // private final byte[] value;  // JDK 9+

    public String(String original) {
        this.value = original.value;  // 直接共享数组
    }

    // 没有任何方法修改value
}

/*
不可变带来的好处：

1. 线程安全
String s = "hello";
// 多个线程同时读取s，无需同步

2. 字符串常量池（String Pool）
String s1 = "hello";
String s2 = "hello";
// s1 == s2 为true，节省内存

3. 可以安全地用作HashMap的key
Map<String, User> map = new HashMap<>();
map.put("user123", user);  // String不会变，hashCode不会变

4. 安全性
void doSomething(String password) {
    // password是不可变的，方法内无法修改
}

如果String是可变的：
String url = "http://safe.com";
someMethod(url);
// someMethod可能把url改成 "http://evil.com"
// 后续使用url会访问恶意网站
*/
```

---

## 二、synchronized深度解析

### 2.1 synchronized的三种用法

```java
/**
 * 用法1：同步实例方法（锁对象是this）
 */
public class SyncInstanceMethod {
    private int count = 0;

    public synchronized void increment() {
        count++;
    }
    // 等价于：
    public void incrementEquivalent() {
        synchronized (this) {
            count++;
        }
    }
}

/**
 * 用法2：同步静态方法（锁对象是Class对象）
 */
public class SyncStaticMethod {
    private static int count = 0;

    public static synchronized void increment() {
        count++;
    }
    // 等价于：
    public static void incrementEquivalent() {
        synchronized (SyncStaticMethod.class) {
            count++;
        }
    }
}

/**
 * 用法3：同步代码块（锁对象可以是任意对象）
 */
public class SyncCodeBlock {
    private final Object lock = new Object();
    private int count = 0;

    public void increment() {
        synchronized (lock) {  // 锁对象是lock
            count++;
        }
    }
}

/*
三种用法的对比：

| 用法 | 锁对象 | 锁粒度 | 适用场景 |
|-----|-------|-------|---------|
| 同步实例方法 | this | 粗 | 整个方法都需要同步 |
| 同步静态方法 | Class对象 | 粗 | 静态变量的同步 |
| 同步代码块 | 自定义对象 | 细 | 只有部分代码需要同步 |

最佳实践：
1. 优先使用同步代码块（锁粒度更细，性能更好）
2. 锁对象使用private final（防止外部代码获取锁）
3. 避免锁this或Class（可能被外部代码加锁，导致死锁）
*/
```

---

### 2.2 对象头与Monitor

#### 2.2.1 Java对象的内存布局

```
Java对象在内存中的结构：

对象 = 对象头（Object Header）+ 实例数据（Instance Data）+ 对齐填充（Padding）

对象头（12-16字节）：
├─ Mark Word（8字节）：存储对象的运行时数据
│   ├─ hashCode（31位）
│   ├─ GC分代年龄（4位）
│   ├─ 锁状态标志（2位）
│   └─ 其他标志位
│
└─ 类型指针（4-8字节）：指向对象的类元数据

Mark Word在不同锁状态下的结构（64位JVM）：

无锁状态：
| unused:25 | hashCode:31 | unused:1 | age:4 | biased_lock:0 | lock:01 |

偏向锁：
| thread:54 | epoch:2 | unused:1 | age:4 | biased_lock:1 | lock:01 |

轻量级锁：
| ptr_to_lock_record:62 | lock:00 |

重量级锁：
| ptr_to_monitor:62 | lock:10 |

GC标记：
| empty:62 | lock:11 |

关键理解：
1. 锁信息存储在对象头的Mark Word中
2. 不同锁状态下，Mark Word的内容不同
3. 锁升级就是Mark Word的状态转换
```

#### 2.2.2 Monitor机制

```
Monitor（监视器）：

每个Java对象都关联一个Monitor对象

Monitor的结构：
┌─────────────────┐
│   Monitor       │
├─────────────────┤
│ _owner          │  ← 当前持有锁的线程
│ _EntryList      │  ← 等待获取锁的线程队列
│ _WaitSet        │  ← 调用wait()后等待的线程集合
│ _count          │  ← 重入次数
└─────────────────┘

Monitor的工作流程：

1. 线程进入同步块
   └─ 尝试获取Monitor的所有权

2. 获取成功
   ├─ _owner设置为当前线程
   ├─ _count加1（支持重入）
   └─ 执行同步代码

3. 获取失败
   ├─ 加入_EntryList
   └─ 阻塞等待

4. 释放锁
   ├─ _count减1
   ├─ 如果_count为0，_owner设置为null
   └─ 唤醒_EntryList中的一个线程

5. wait/notify机制
   ├─ wait()：当前线程进入_WaitSet，释放锁
   ├─ notify()：从_WaitSet唤醒一个线程到_EntryList
   └─ notifyAll()：唤醒_WaitSet中的所有线程
```

---

### 2.3 锁升级过程：从偏向锁到重量级锁

**设计哲学**：大多数情况下，锁不仅不存在多线程竞争，而且总是由同一个线程多次获得。为了让线程获得锁的代价更低，引入了偏向锁、轻量级锁。

```
锁升级路径：
无锁 → 偏向锁 → 轻量级锁 → 重量级锁

关键点：
1. 锁只能升级，不能降级（单向不可逆）
2. 每个级别针对不同的竞争场景优化
3. JVM会根据运行时情况自动升级
```

#### 2.3.1 偏向锁（Biased Locking）

```java
/**
 * 偏向锁适用场景：
 * 锁总是被同一个线程获取，没有多线程竞争
 */
public class BiasedLockExample {
    private int count = 0;

    public synchronized void increment() {
        count++;
    }

    public static void main(String[] args) {
        BiasedLockExample obj = new BiasedLockExample();

        // 只有一个线程执行1000次
        for (int i = 0; i < 1000; i++) {
            obj.increment();  // 每次都是同一个线程获取锁
        }
    }
}

/*
偏向锁的工作原理：

1. 首次获取锁（偏向）：
   ├─ Mark Word中记录线程ID
   ├─ 设置偏向锁标志位
   └─ 以后这个线程进入同步块，无需CAS操作

2. 再次获取锁（同一线程）：
   ├─ 检查Mark Word中的线程ID
   ├─ 如果是自己，直接进入同步块
   └─ 成本：只需一次Mark Word的检查（极低）

3. 其他线程尝试获取锁：
   ├─ 偏向锁失效
   ├─ 撤销偏向（Revoke）
   └─ 升级为轻量级锁

偏向锁的撤销：
时机1：另一个线程尝试获取锁
时机2：调用hashCode()方法（Mark Word空间冲突）
时机3：调用wait/notify方法

撤销过程：
1. 暂停持有偏向锁的线程
2. 检查线程是否还在执行同步代码
3. 如果是，升级为轻量级锁
4. 如果否，恢复为无锁状态

性能优势：
无竞争场景：偏向锁 > 轻量级锁 > 重量级锁
有竞争场景：偏向锁反而会因为频繁撤销而降低性能

JVM参数：
-XX:+UseBiasedLocking  // 启用偏向锁（JDK 6+默认开启）
-XX:-UseBiasedLocking  // 禁用偏向锁
-XX:BiasedLockingStartupDelay=0  // 立即启用（默认延迟4秒）
*/
```

#### 2.3.2 轻量级锁（Lightweight Locking）

```java
/**
 * 轻量级锁适用场景：
 * 多个线程交替获取锁，但不会同时竞争
 */
public class LightweightLockExample {
    private int count = 0;

    public synchronized void increment() {
        count++;
    }

    public static void main(String[] args) throws InterruptedException {
        LightweightLockExample obj = new LightweightLockExample();

        // 两个线程交替执行，不会同时竞争
        Thread t1 = new Thread(() -> {
            for (int i = 0; i < 1000; i++) {
                obj.increment();
            }
        });

        Thread t2 = new Thread(() -> {
            for (int i = 0; i < 1000; i++) {
                obj.increment();
            }
        });

        t1.start();
        t1.join();  // 等t1执行完
        t2.start(); // 再启动t2
        t2.join();
    }
}

/*
轻量级锁的工作原理：

1. 加锁过程：
   ├─ 在当前线程的栈帧中创建Lock Record
   ├─ 将对象头的Mark Word复制到Lock Record（Displaced Mark Word）
   ├─ 使用CAS将对象头的Mark Word替换为指向Lock Record的指针
   └─ 如果CAS成功，获取锁；失败，自旋重试

2. 自旋（Spin）：
   ├─ CAS失败后，不立即阻塞
   ├─ 自旋一定次数（默认10次）
   ├─ 期望持有锁的线程很快释放锁
   └─ 自适应自旋：根据历史成功率调整自旋次数

3. 解锁过程：
   ├─ 使用CAS将Displaced Mark Word恢复到对象头
   ├─ 如果CAS成功，解锁完成
   └─ 如果CAS失败，说明有竞争，膨胀为重量级锁

4. 锁膨胀：
   ├─ 自旋次数超过阈值
   ├─ 自旋线程数超过CPU核心数的一半
   └─ 升级为重量级锁

轻量级锁 vs 偏向锁：
偏向锁：适用于只有一个线程访问
轻量级锁：适用于多个线程交替访问，竞争不激烈

性能对比：
场景：交替访问，无实际竞争
├─ 轻量级锁：CAS操作（成本低）
└─ 重量级锁：用户态→内核态切换（成本高）

JVM参数：
-XX:PreBlockSpin=10  // 自旋次数（JDK 6）
-XX:+UseSpinning     // 启用自旋（JDK 6默认开启）
*/
```

#### 2.3.3 重量级锁（Heavyweight Locking）

```java
/**
 * 重量级锁适用场景：
 * 多个线程同时竞争锁，竞争激烈
 */
public class HeavyweightLockExample {
    private int count = 0;

    public synchronized void increment() {
        count++;
        // 模拟耗时操作
        try {
            Thread.sleep(10);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    public static void main(String[] args) throws InterruptedException {
        HeavyweightLockExample obj = new HeavyweightLockExample();

        // 10个线程同时竞争锁
        Thread[] threads = new Thread[10];
        for (int i = 0; i < 10; i++) {
            threads[i] = new Thread(() -> {
                for (int j = 0; j < 100; j++) {
                    obj.increment();
                }
            });
        }

        for (Thread t : threads) t.start();
        for (Thread t : threads) t.join();
    }
}

/*
重量级锁的工作原理：

1. 膨胀过程：
   ├─ 轻量级锁竞争失败
   ├─ 创建Monitor对象
   ├─ Mark Word指向Monitor
   └─ 锁状态变为10（重量级锁）

2. 加锁过程：
   ├─ 尝试获取Monitor的所有权
   ├─ 失败则进入_EntryList
   └─ 线程阻塞（用户态→内核态）

3. 阻塞与唤醒：
   ├─ 阻塞：pthread_mutex_lock()（依赖操作系统）
   └─ 唤醒：pthread_mutex_unlock()

4. 成本分析：
   ├─ 用户态→内核态切换：约1000个时钟周期
   ├─ 线程阻塞：放弃CPU时间片
   └─ 线程唤醒：重新调度

为什么叫"重量级"？
├─ 依赖操作系统的Mutex Lock
├─ 涉及用户态和内核态的切换
└─ 上下文切换成本高

适用场景：
├─ 锁持有时间长
├─ 竞争激烈
└─ 自旋会浪费CPU

不适用场景：
├─ 锁持有时间短
├─ 竞争不激烈
└─ 使用轻量级锁更高效
*/
```

#### 2.3.4 锁升级的完整流程

```
锁升级的完整决策树：

开始
  ↓
无锁状态
  ↓
首次加锁？
├─ 是 → 偏向锁（记录线程ID）
└─ 否 → 继续
       ↓
       同一线程再次加锁？
       ├─ 是 → 偏向锁（检查线程ID，快速进入）
       └─ 否 → 其他线程竞争
              ↓
              撤销偏向锁
              ↓
              轻量级锁（CAS + 自旋）
              ↓
              竞争激烈？
              ├─ 否 → 继续轻量级锁
              └─ 是 → 膨胀为重量级锁
                     ↓
                     重量级锁（Monitor + 阻塞）

判断"竞争激烈"的标准：
1. 自旋次数超过阈值（默认10次）
2. 自旋线程数 > CPU核心数 / 2
3. 等待队列中有线程

锁升级的不可逆性：
偏向锁 → 轻量级锁 ✅
轻量级锁 → 重量级锁 ✅
重量级锁 → 轻量级锁 ❌（不会降级）

为什么不降级？
1. 降级会引入额外的复杂性
2. 膨胀说明竞争激烈，很可能再次膨胀
3. JVM选择一旦膨胀，就保持重量级锁
```

---

### 2.4 wait/notify机制

```java
/**
 * wait/notify的经典应用：生产者-消费者模式
 */
public class ProducerConsumer {
    private final Queue<Integer> queue = new LinkedList<>();
    private final int MAX_SIZE = 10;
    private final Object lock = new Object();

    // 生产者
    public void produce(int value) throws InterruptedException {
        synchronized (lock) {
            // 队列满，等待
            while (queue.size() == MAX_SIZE) {
                System.out.println("队列已满，生产者等待...");
                lock.wait();  // 释放锁，进入WaitSet
            }

            queue.offer(value);
            System.out.println("生产：" + value + "，当前队列大小：" + queue.size());

            lock.notifyAll();  // 唤醒所有等待的消费者
        }
    }

    // 消费者
    public int consume() throws InterruptedException {
        synchronized (lock) {
            // 队列空，等待
            while (queue.isEmpty()) {
                System.out.println("队列为空，消费者等待...");
                lock.wait();  // 释放锁，进入WaitSet
            }

            int value = queue.poll();
            System.out.println("消费：" + value + "，当前队列大小：" + queue.size());

            lock.notifyAll();  // 唤醒所有等待的生产者
            return value;
        }
    }
}

/*
wait/notify的关键点：

1. 必须在synchronized块中调用
   ├─ wait()、notify()、notifyAll()都是Object的方法
   ├─ 必须先获取对象的Monitor
   └─ 否则抛出IllegalMonitorStateException

2. wait()的作用
   ├─ 释放当前持有的锁
   ├─ 线程进入Monitor的WaitSet
   ├─ 线程阻塞，等待被notify
   └─ 被唤醒后，重新竞争锁

3. notify() vs notifyAll()
   ├─ notify()：唤醒WaitSet中的一个线程（随机）
   └─ notifyAll()：唤醒WaitSet中的所有线程

4. 为什么用while而不是if？
   ├─ 虚假唤醒（Spurious Wakeup）：线程可能在没有notify的情况下被唤醒
   ├─ 多个线程竞争：被唤醒后，条件可能已经不满足
   └─ 最佳实践：总是用while循环检查条件

wait/notify的问题：
├─ 只能唤醒同一个锁对象上等待的线程
├─ notify()无法指定唤醒哪个线程
├─ 容易产生死锁和虚假唤醒
└─ Lock的Condition接口提供了更灵活的方案
*/
```

---

## 三、Lock接口与ReentrantLock

### 3.1 为什么需要Lock？synchronized的局限性

```java
/**
 * synchronized的局限性
 */
public class SynchronizedLimitations {
    private final Object lock = new Object();

    // 问题1：无法中断
    public void method1() {
        synchronized (lock) {
            // 如果获取锁失败，线程会一直阻塞
            // 无法响应中断
        }
    }

    // 问题2：无法设置超时
    public void method2() {
        synchronized (lock) {
            // 无法设置获取锁的超时时间
            // 可能永远阻塞
        }
    }

    // 问题3：无法尝试获取锁
    public void method3() {
        synchronized (lock) {
            // 无法尝试获取锁（tryLock）
            // 要么获取成功，要么阻塞
        }
    }

    // 问题4：读写无法分离
    private int count = 0;
    public synchronized int read() {
        return count;
    }
    public synchronized void write(int value) {
        count = value;
    }
    // 读操作之间可以并发，但synchronized做不到
}

/*
synchronized vs Lock：

| 特性 | synchronized | Lock |
|-----|-------------|------|
| 锁获取/释放 | 自动 | 手动（需要finally释放） |
| 中断响应 | 不支持 | 支持（lockInterruptibly） |
| 超时机制 | 不支持 | 支持（tryLock(timeout)） |
| 尝试获取锁 | 不支持 | 支持（tryLock()） |
| 公平性 | 非公平 | 可选（公平/非公平） |
| 条件队列 | 1个（WaitSet） | 多个（Condition） |
| 性能 | JDK 6+优化后相当 | 相当 |

Lock的优势：
1. 更灵活的锁获取方式
2. 可中断的锁等待
3. 支持超时
4. 支持公平锁
5. 支持多个条件队列

synchronized的优势：
1. 使用简单，自动释放锁
2. JVM优化（锁升级、锁消除、锁粗化）
3. 不会忘记释放锁
*/
```

---

### 3.2 ReentrantLock的基本用法

```java
/**
 * ReentrantLock的标准用法
 */
public class ReentrantLockExample {
    private final ReentrantLock lock = new ReentrantLock();
    private int count = 0;

    // 标准模式：lock + try + finally
    public void increment() {
        lock.lock();  // 获取锁
        try {
            count++;
        } finally {
            lock.unlock();  // 确保释放锁
        }
    }

    // 尝试获取锁（非阻塞）
    public boolean tryIncrement() {
        if (lock.tryLock()) {  // 尝试获取锁，立即返回
            try {
                count++;
                return true;
            } finally {
                lock.unlock();
            }
        }
        return false;  // 获取锁失败
    }

    // 带超时的锁获取
    public boolean incrementWithTimeout(long timeout, TimeUnit unit) throws InterruptedException {
        if (lock.tryLock(timeout, unit)) {  // 等待指定时间
            try {
                count++;
                return true;
            } finally {
                lock.unlock();
            }
        }
        return false;  // 超时
    }

    // 可中断的锁获取
    public void incrementInterruptibly() throws InterruptedException {
        lock.lockInterruptibly();  // 可响应中断
        try {
            count++;
        } finally {
            lock.unlock();
        }
    }

    // 查询锁状态
    public void checkLockStatus() {
        System.out.println("锁是否被持有：" + lock.isLocked());
        System.out.println("当前线程是否持有锁：" + lock.isHeldByCurrentThread());
        System.out.println("等待队列长度：" + lock.getQueueLength());
    }
}

/*
关键注意事项：

1. 必须在finally中释放锁
   ├─ lock()必须与unlock()配对
   ├─ 否则会导致死锁
   └─ 即使发生异常，也要释放锁

2. lock()的位置
   ✅ lock.lock(); try { ... } finally { unlock(); }
   ❌ try { lock.lock(); ... } finally { unlock(); }
   原因：如果lock()抛异常，unlock()会抛IllegalMonitorStateException

3. 重入性
   ├─ 同一线程可以多次获取同一把锁
   ├─ 每次lock()对应一次unlock()
   └─ 计数器为0时才真正释放锁

4. 公平性
   ├─ new ReentrantLock()：非公平锁（默认）
   ├─ new ReentrantLock(true)：公平锁
   └─ 公平锁保证FIFO，但性能较低
*/
```

---

### 3.3 公平锁 vs 非公平锁

```java
/**
 * 公平锁与非公平锁的对比
 */
public class FairVsNonfair {
    // 非公平锁（默认）
    private final ReentrantLock unfairLock = new ReentrantLock();

    // 公平锁
    private final ReentrantLock fairLock = new ReentrantLock(true);

    public static void main(String[] args) throws InterruptedException {
        FairVsNonfair demo = new FairVsNonfair();

        System.out.println("===== 非公平锁 =====");
        demo.testLock(demo.unfairLock);

        Thread.sleep(1000);

        System.out.println("\n===== 公平锁 =====");
        demo.testLock(demo.fairLock);
    }

    private void testLock(ReentrantLock lock) throws InterruptedException {
        Runnable task = () -> {
            for (int i = 0; i < 3; i++) {
                lock.lock();
                try {
                    System.out.println(Thread.currentThread().getName() + " 获取锁");
                    Thread.sleep(10);
                } catch (InterruptedException e) {
                    e.printStackTrace();
                } finally {
                    lock.unlock();
                }
            }
        };

        Thread t1 = new Thread(task, "线程1");
        Thread t2 = new Thread(task, "线程2");
        Thread t3 = new Thread(task, "线程3");

        t1.start();
        t2.start();
        t3.start();

        t1.join();
        t2.join();
        t3.join();
    }
}

/*
执行结果对比：

非公平锁（可能的输出）：
线程1 获取锁
线程1 获取锁  ← 线程1连续获取
线程1 获取锁  ← 线程1连续获取
线程2 获取锁
线程3 获取锁
...

公平锁（输出）：
线程1 获取锁
线程2 获取锁  ← 严格按照请求顺序
线程3 获取锁
线程1 获取锁
线程2 获取锁
线程3 获取锁
...

公平锁的实现原理：
1. 维护一个FIFO队列
2. 线程按照请求锁的顺序排队
3. 队首线程获取锁
4. 保证不会有线程饥饿

非公平锁的实现原理：
1. 新线程先尝试CAS获取锁
2. 成功则直接获取（插队）
3. 失败则加入队列
4. 可能导致队列中的线程长时间等待

性能对比：
场景：100个线程竞争锁，每次持有锁10ms
├─ 非公平锁：总耗时 1.2秒
└─ 公平锁：总耗时 2.5秒（慢2倍）

非公平锁为什么更快？
1. 减少线程切换
   ├─ 刚释放锁的线程可能还在CPU上
   ├─ 直接再次获取锁，无需唤醒其他线程
   └─ 节省上下文切换成本

2. 提高吞吐量
   ├─ 减少线程唤醒和阻塞的次数
   └─ 整体吞吐量更高

何时使用公平锁？
├─ 需要严格按照请求顺序执行
├─ 不能容忍饥饿
└─ 对性能要求不高

何时使用非公平锁？
├─ 追求高吞吐量（默认选择）
├─ 可以容忍一定的不公平
└─ 大多数场景
*/
```

---

### 3.4 Condition条件队列

```java
/**
 * Condition的使用：实现生产者-消费者模式
 * 相比wait/notify的优势：可以有多个条件队列
 */
public class ProducerConsumerWithCondition {
    private final ReentrantLock lock = new ReentrantLock();
    private final Condition notFull = lock.newCondition();   // 队列未满条件
    private final Condition notEmpty = lock.newCondition();  // 队列非空条件

    private final Queue<Integer> queue = new LinkedList<>();
    private final int MAX_SIZE = 10;

    // 生产者
    public void produce(int value) throws InterruptedException {
        lock.lock();
        try {
            // 队列满，等待
            while (queue.size() == MAX_SIZE) {
                System.out.println("队列已满，生产者等待...");
                notFull.await();  // 在notFull条件上等待
            }

            queue.offer(value);
            System.out.println("生产：" + value);

            notEmpty.signal();  // 唤醒一个在notEmpty条件上等待的消费者
        } finally {
            lock.unlock();
        }
    }

    // 消费者
    public int consume() throws InterruptedException {
        lock.lock();
        try {
            // 队列空，等待
            while (queue.isEmpty()) {
                System.out.println("队列为空，消费者等待...");
                notEmpty.await();  // 在notEmpty条件上等待
            }

            int value = queue.poll();
            System.out.println("消费：" + value);

            notFull.signal();  // 唤醒一个在notFull条件上等待的生产者
            return value;
        } finally {
            lock.unlock();
        }
    }
}

/*
Condition vs wait/notify：

| 特性 | wait/notify | Condition |
|-----|------------|-----------|
| 条件队列数量 | 1个 | 多个 |
| 唤醒方式 | notify/notifyAll | signal/signalAll |
| 精确唤醒 | 不支持 | 支持 |
| 必须在同步块中 | 是 | 是（Lock块中） |

Condition的优势：
1. 多个条件队列
   ├─ notFull：队列未满
   ├─ notEmpty：队列非空
   └─ 避免唤醒错误的线程

2. 精确唤醒
   ├─ signal()唤醒指定条件上的线程
   └─ 比notifyAll()更高效

Condition的API：
await()           // 等待，对应wait()
signal()          // 唤醒一个线程，对应notify()
signalAll()       // 唤醒所有线程，对应notifyAll()
awaitNanos(long)  // 带超时的等待
awaitUntil(Date)  // 等待到指定时间

使用注意事项：
1. 必须先获取Lock
2. 必须在finally中释放Lock
3. await()会释放Lock，被唤醒后重新获取
4. 使用while循环检查条件（防止虚假唤醒）
*/
```

---

## 四、AQS源码剖析

### 4.1 AQS的核心思想

**AQS（AbstractQueuedSynchronizer）**：Java并发包的基石，ReentrantLock、CountDownLatch、Semaphore等都基于AQS实现。

```
AQS的设计哲学：

核心思想：
  如果被请求的共享资源空闲，将请求资源的线程设置为有效工作线程
  如果被请求的共享资源被占用，需要一套阻塞等待和唤醒机制

两个关键点：
1. 同步状态（state）
   └─ volatile int state  // 表示同步状态

2. FIFO等待队列
   └─ CLH队列（Craig, Landin, and Hagersten locks）

AQS的结构：
┌──────────────────────────────┐
│ AbstractQueuedSynchronizer   │
├──────────────────────────────┤
│ private volatile int state   │  ← 同步状态
│ private volatile Node head   │  ← 队列头
│ private volatile Node tail   │  ← 队列尾
├──────────────────────────────┤
│ acquire(int arg)             │  ← 独占模式获取
│ release(int arg)             │  ← 独占模式释放
│ acquireShared(int arg)       │  ← 共享模式获取
│ releaseShared(int arg)       │  ← 共享模式释放
└──────────────────────────────┘

Node节点的结构：
┌──────────────────┐
│ Node             │
├──────────────────┤
│ Thread thread    │  ← 等待的线程
│ Node prev        │  ← 前驱节点
│ Node next        │  ← 后继节点
│ int waitStatus   │  ← 等待状态
│ Node nextWaiter  │  ← Condition队列的下一个节点
└──────────────────┘

waitStatus的取值：
CANCELLED = 1   // 线程被取消
SIGNAL = -1     // 后继节点需要被唤醒
CONDITION = -2  // 线程在Condition队列中等待
PROPAGATE = -3  // 共享模式下，释放应该传播
0               // 初始状态
```

---

### 4.2 同步队列（CLH队列）

```java
/**
 * AQS的同步队列（简化版）
 */
public class SimplifiedAQS {
    // 同步状态
    private volatile int state = 0;

    // 队列头尾
    private volatile Node head;
    private volatile Node tail;

    // 节点定义
    static class Node {
        Thread thread;
        Node prev;
        Node next;
        int waitStatus;

        Node(Thread thread) {
            this.thread = thread;
        }
    }

    // 获取锁（独占模式）
    public void acquire() {
        // 1. 尝试获取锁
        if (!tryAcquire()) {
            // 2. 获取失败，加入队列
            Node node = enq(Thread.currentThread());
            // 3. 阻塞当前线程
            park(node);
        }
    }

    // 尝试获取锁（子类实现）
    protected boolean tryAcquire() {
        // 使用CAS设置state从0→1
        return compareAndSetState(0, 1);
    }

    // 加入队列（自旋 + CAS）
    private Node enq(Thread thread) {
        Node node = new Node(thread);
        for (;;) {  // 自旋
            Node t = tail;
            if (t == null) {
                // 队列为空，初始化
                if (compareAndSetHead(new Node())) {
                    tail = head;
                }
            } else {
                // 加入队尾
                node.prev = t;
                if (compareAndSetTail(t, node)) {
                    t.next = node;
                    return node;
                }
            }
        }
    }

    // 阻塞当前线程
    private void park(Node node) {
        for (;;) {
            Node p = node.prev;
            // 如果前驱是head，尝试获取锁
            if (p == head && tryAcquire()) {
                setHead(node);  // 获取成功，设置为新head
                p.next = null;  // 帮助GC
                return;
            }
            // 阻塞当前线程
            LockSupport.park(this);
        }
    }

    // 释放锁
    public void release() {
        if (tryRelease()) {
            Node h = head;
            if (h != null && h.waitStatus != 0) {
                unparkSuccessor(h);  // 唤醒后继节点
            }
        }
    }

    // 尝试释放锁（子类实现）
    protected boolean tryRelease() {
        setState(0);
        return true;
    }

    // 唤醒后继节点
    private void unparkSuccessor(Node node) {
        Node s = node.next;
        if (s != null && s.thread != null) {
            LockSupport.unpark(s.thread);
        }
    }

    // CAS操作（实际使用Unsafe类实现）
    private boolean compareAndSetState(int expect, int update) {
        // return unsafe.compareAndSwapInt(this, stateOffset, expect, update);
        return true;  // 简化实现
    }

    private boolean compareAndSetHead(Node update) {
        return true;  // 简化实现
    }

    private boolean compareAndSetTail(Node expect, Node update) {
        return true;  // 简化实现
    }

    private void setHead(Node node) {
        head = node;
        node.thread = null;
        node.prev = null;
    }

    private void setState(int newState) {
        state = newState;
    }
}

/*
CLH队列的工作流程：

初始状态（队列为空）：
head → null
tail → null

线程1获取锁成功：
state = 1
线程1持有锁，继续执行

线程2尝试获取锁失败：
1. tryAcquire()失败
2. 创建Node2，加入队列
3. park()阻塞

队列状态：
head → dummy node → Node2(thread2) ← tail

线程3尝试获取锁失败：
队列状态：
head → dummy node → Node2(thread2) → Node3(thread3) ← tail

线程1释放锁：
1. tryRelease()成功，state = 0
2. unparkSuccessor()唤醒Node2的线程2
3. 线程2被唤醒，重新尝试获取锁
4. 获取成功，Node2成为新head

新队列状态：
head → Node2(thread2) → Node3(thread3) ← tail

关键点：
1. head是dummy节点（哨兵节点），不存储线程
2. 使用自旋 + CAS保证线程安全
3. 被唤醒的线程需要重新tryAcquire()
4. FIFO保证公平性
*/
```

---

### 4.3 ReentrantLock基于AQS的实现

```java
/**
 * ReentrantLock的核心实现（简化版）
 */
public class SimpleReentrantLock {
    // 内部使用AQS的Sync
    private final Sync sync;

    public SimpleReentrantLock() {
        sync = new NonfairSync();  // 默认非公平锁
    }

    public SimpleReentrantLock(boolean fair) {
        sync = fair ? new FairSync() : new NonfairSync();
    }

    // AQS的子类
    abstract static class Sync extends AbstractQueuedSynchronizer {
        // 尝试获取锁
        abstract void lock();

        // 非公平方式获取锁
        final boolean nonfairTryAcquire(int acquires) {
            Thread current = Thread.currentThread();
            int c = getState();
            if (c == 0) {
                // 锁空闲，直接CAS获取（不检查队列）
                if (compareAndSetState(0, acquires)) {
                    setExclusiveOwnerThread(current);
                    return true;
                }
            } else if (current == getExclusiveOwnerThread()) {
                // 重入
                int nextc = c + acquires;
                if (nextc < 0) // overflow
                    throw new Error("Maximum lock count exceeded");
                setState(nextc);
                return true;
            }
            return false;
        }

        // 释放锁
        protected final boolean tryRelease(int releases) {
            int c = getState() - releases;
            if (Thread.currentThread() != getExclusiveOwnerThread())
                throw new IllegalMonitorStateException();
            boolean free = false;
            if (c == 0) {
                free = true;
                setExclusiveOwnerThread(null);
            }
            setState(c);
            return free;
        }
    }

    // 非公平锁实现
    static final class NonfairSync extends Sync {
        final void lock() {
            // 直接尝试CAS获取锁（插队）
            if (compareAndSetState(0, 1))
                setExclusiveOwnerThread(Thread.currentThread());
            else
                acquire(1);  // 失败，调用AQS的acquire
        }

        protected final boolean tryAcquire(int acquires) {
            return nonfairTryAcquire(acquires);
        }
    }

    // 公平锁实现
    static final class FairSync extends Sync {
        final void lock() {
            acquire(1);  // 不尝试插队，直接调用AQS的acquire
        }

        protected final boolean tryAcquire(int acquires) {
            Thread current = Thread.currentThread();
            int c = getState();
            if (c == 0) {
                // 检查队列中是否有等待的线程
                if (!hasQueuedPredecessors() &&
                    compareAndSetState(0, acquires)) {
                    setExclusiveOwnerThread(current);
                    return true;
                }
            } else if (current == getExclusiveOwnerThread()) {
                int nextc = c + acquires;
                if (nextc < 0)
                    throw new Error("Maximum lock count exceeded");
                setState(nextc);
                return true;
            }
            return false;
        }
    }

    // 对外API
    public void lock() {
        sync.lock();
    }

    public void unlock() {
        sync.release(1);
    }

    public boolean tryLock() {
        return sync.nonfairTryAcquire(1);
    }
}

/*
公平锁 vs 非公平锁的实现差异：

非公平锁（NonfairSync）：
lock() {
    if (compareAndSetState(0, 1))  ← 直接尝试获取（插队）
        setExclusiveOwnerThread(Thread.currentThread());
    else
        acquire(1);  ← 失败才加入队列
}

公平锁（FairSync）：
lock() {
    acquire(1);  ← 不尝试插队，直接加入队列
}

tryAcquire() {
    if (!hasQueuedPredecessors() && ...)  ← 检查队列
        ...
}

关键差异：
非公平锁：先尝试插队，失败才排队
公平锁：直接排队，严格FIFO

性能影响：
非公平锁：减少线程切换，吞吐量高
公平锁：增加线程切换，吞吐量低，但公平
*/
```

---

## 五、死锁问题

### 5.1 死锁的定义与案例

```java
/**
 * 经典死锁案例：转账系统
 */
public class DeadlockExample {
    static class Account {
        private int balance = 1000;
        private final String name;

        public Account(String name) {
            this.name = name;
        }

        public synchronized void transfer(Account to, int amount) {
            // 1. 锁定当前账户（this）
            System.out.println(Thread.currentThread().getName() + " 锁定 " + this.name);

            try {
                Thread.sleep(100);  // 模拟业务处理
            } catch (InterruptedException e) {
                e.printStackTrace();
            }

            // 2. 尝试锁定目标账户（to）
            synchronized (to) {
                System.out.println(Thread.currentThread().getName() + " 锁定 " + to.name);

                // 3. 执行转账
                this.balance -= amount;
                to.balance += amount;

                System.out.println("转账成功：" + this.name + " → " + to.name + " " + amount + "元");
            }
        }
    }

    public static void main(String[] args) {
        Account account1 = new Account("账户1");
        Account account2 = new Account("账户2");

        // 线程1：账户1 → 账户2
        Thread t1 = new Thread(() -> {
            account1.transfer(account2, 100);
        }, "线程1");

        // 线程2：账户2 → 账户1
        Thread t2 = new Thread(() -> {
            account2.transfer(account1, 200);
        }, "线程2");

        t1.start();
        t2.start();
    }
}

/*
执行结果（死锁）：
线程1 锁定 账户1
线程2 锁定 账户2
（然后程序卡住，双方都在等待对方释放锁）

死锁分析：
时间  线程1                    线程2
t1   锁定account1
t2                           锁定account2
t3   尝试锁定account2（阻塞） 尝试锁定account1（阻塞）
t4   等待...                 等待...
...  死锁！                   死锁！

可视化：
线程1： account1(锁定) → account2(等待)
线程2： account2(锁定) → account1(等待)

形成环路：
account1 → 线程2 → account2 → 线程1 → account1
*/
```

---

### 5.2 死锁的四个必要条件

```
死锁的四个必要条件（Coffman条件）：

1. 互斥条件（Mutual Exclusion）
   └─ 资源不能被共享，一次只能被一个线程使用

2. 持有并等待（Hold and Wait）
   └─ 线程已经持有至少一个资源，但又提出新的资源请求

3. 不可剥夺（No Preemption）
   └─ 资源不能被强制剥夺，只能由持有者主动释放

4. 循环等待（Circular Wait）
   └─ 存在一个线程-资源的循环等待链

四个条件必须同时满足才会死锁
破坏任意一个条件，就可以预防死锁
```

---

### 5.3 死锁预防策略

#### 策略1：破坏持有并等待（一次性获取所有资源）

```java
/**
 * 策略1：一次性获取所有资源
 * 破坏"持有并等待"条件
 */
public class PreventHoldAndWait {
    static class Account {
        private int balance = 1000;
        private final String name;

        public Account(String name) {
            this.name = name;
        }

        // 转账前，一次性获取两个账户的锁
        public void transfer(Account to, int amount) {
            // 使用一个全局锁来协调获取两个账户的锁
            synchronized (Account.class) {
                synchronized (this) {
                    synchronized (to) {
                        this.balance -= amount;
                        to.balance += amount;
                        System.out.println("转账成功");
                    }
                }
            }
        }
    }
}

/*
优点：
├─ 彻底避免死锁
└─ 实现简单

缺点：
├─ 降低并发度（全局锁）
├─ 可能导致饥饿
└─ 性能较差
*/
```

#### 策略2：破坏不可剥夺（使用tryLock）

```java
/**
 * 策略2：使用tryLock，获取不到锁就释放已持有的锁
 * 破坏"不可剥夺"条件
 */
public class PreventNoPreemption {
    static class Account {
        private int balance = 1000;
        private final String name;
        private final ReentrantLock lock = new ReentrantLock();

        public Account(String name) {
            this.name = name;
        }

        public void transfer(Account to, int amount) throws InterruptedException {
            while (true) {
                // 尝试获取当前账户的锁
                if (this.lock.tryLock()) {
                    try {
                        // 尝试获取目标账户的锁
                        if (to.lock.tryLock()) {
                            try {
                                // 执行转账
                                this.balance -= amount;
                                to.balance += amount;
                                System.out.println("转账成功");
                                return;
                            } finally {
                                to.lock.unlock();
                            }
                        }
                    } finally {
                        this.lock.unlock();
                    }
                }

                // 获取锁失败，随机休眠后重试
                Thread.sleep((long) (Math.random() * 10));
            }
        }
    }
}

/*
优点：
├─ 避免死锁
└─ 并发度高

缺点：
├─ 实现复杂
├─ 可能活锁（所有线程都不断重试）
└─ 需要处理超时和重试逻辑
*/
```

#### 策略3：破坏循环等待（资源有序分配）

```java
/**
 * 策略3：按照固定顺序获取锁
 * 破坏"循环等待"条件
 */
public class PreventCircularWait {
    static class Account {
        private int balance = 1000;
        private final String name;
        private final int id;  // 账户唯一ID

        public Account(String name, int id) {
            this.name = name;
            this.id = id;
        }

        public void transfer(Account to, int amount) {
            // 按照账户ID的顺序获取锁
            Account first = this.id < to.id ? this : to;
            Account second = this.id < to.id ? to : this;

            synchronized (first) {
                System.out.println(Thread.currentThread().getName() + " 锁定 " + first.name);

                synchronized (second) {
                    System.out.println(Thread.currentThread().getName() + " 锁定 " + second.name);

                    // 执行转账
                    this.balance -= amount;
                    to.balance += amount;

                    System.out.println("转账成功：" + this.name + " → " + to.name);
                }
            }
        }
    }

    public static void main(String[] args) {
        Account account1 = new Account("账户1", 1);
        Account account2 = new Account("账户2", 2);

        Thread t1 = new Thread(() -> {
            account1.transfer(account2, 100);
        }, "线程1");

        Thread t2 = new Thread(() -> {
            account2.transfer(account1, 200);
        }, "线程2");

        t1.start();
        t2.start();
    }
}

/*
执行结果（无死锁）：
线程1 锁定 账户1
线程1 锁定 账户2
转账成功：账户1 → 账户2
线程2 锁定 账户1
线程2 锁定 账户2
转账成功：账户2 → 账户1

原理分析：
无论是 账户1→账户2 还是 账户2→账户1
都按照 先锁定账户1，再锁定账户2 的顺序
不会形成循环等待

优点：
├─ 彻底避免死锁
├─ 性能好
└─ 实现相对简单

缺点：
├─ 需要为资源定义全局顺序
└─ 不适用于动态资源
*/
```

---

### 5.4 死锁检测工具

```
1. jstack（JDK自带）
   └─ jstack <pid> > deadlock.txt
   └─ 输出线程堆栈，自动检测死锁

2. JConsole（JDK自带）
   └─ GUI工具，实时监控线程状态
   └─ "线程"标签页会显示死锁信息

3. VisualVM（JDK自带）
   └─ 功能更强大的监控工具
   └─ 可以生成线程dump

4. Arthas（阿里开源）
   └─ thread -b  // 显示阻塞的线程
   └─ thread <tid>  // 查看线程详细信息

示例：jstack检测死锁
$ jstack 12345

Found one Java-level deadlock:
=============================
"线程2":
  waiting to lock monitor 0x00007f8a1c004e80 (object 0x000000076ab0a0e0, a Account),
  which is held by "线程1"
"线程1":
  waiting to lock monitor 0x00007f8a1c007330 (object 0x000000076ab0a0f0, a Account),
  which is held by "线程2"

Java stack information for the threads listed above:
...

预防死锁的最佳实践：
1. ✅ 尽量减少锁的使用
2. ✅ 缩小锁的范围
3. ✅ 使用tryLock而不是lock
4. ✅ 按照固定顺序获取锁
5. ✅ 使用超时机制
6. ✅ 使用并发工具类（下一篇）
7. ✅ 代码审查，检查嵌套锁
```

---

## 六、总结与思考

### 6.1 synchronized vs Lock

```
选择指南：

使用synchronized的场景：
├─ 代码简单，不需要高级特性
├─ JVM会自动优化（锁升级）
├─ 不会忘记释放锁
└─ 绝大多数场景（推荐优先使用）

使用Lock的场景：
├─ 需要尝试获取锁（tryLock）
├─ 需要超时机制
├─ 需要可中断的锁获取
├─ 需要公平锁
├─ 需要多个条件队列（Condition）
└─ 需要手动控制锁的范围

性能对比（JDK 8+）：
├─ 低竞争：synchronized ≈ Lock
├─ 高竞争：synchronized ≈ Lock
└─ JVM的锁优化已经非常成熟

代码复杂度：
├─ synchronized：简单，不易出错
└─ Lock：复杂，容易忘记unlock()
```

---

### 6.2 线程安全的最佳实践

```
1. 优先使用不可变对象
   ├─ String、Integer、LocalDateTime
   ├─ 自定义不可变类
   └─ 天然线程安全

2. 减少锁的范围
   ├─ 只锁必要的代码
   ├─ 避免在锁内调用外部方法
   └─ 避免在锁内执行耗时操作

3. 避免锁嵌套
   ├─ 嵌套锁容易导致死锁
   ├─ 如果必须嵌套，按照固定顺序
   └─ 考虑使用tryLock

4. 使用并发集合
   ├─ ConcurrentHashMap > Hashtable
   ├─ CopyOnWriteArrayList > Vector
   └─ 下一篇详细讲解

5. 使用ThreadLocal
   ├─ 避免共享变量
   ├─ 每个线程独立副本
   └─ 注意内存泄漏

6. 使用原子类
   ├─ AtomicInteger、AtomicLong
   ├─ 无锁CAS操作
   └─ 下一篇详细讲解
```

---

## 七、下一篇预告

在下一篇文章《并发工具类与原子操作：无锁编程的艺术》中，我们将深入探讨：

1. **Atomic原子类家族**
   - AtomicInteger、AtomicLong、AtomicReference
   - CAS（Compare-And-Swap）原理
   - ABA问题及解决方案

2. **并发工具类**
   - CountDownLatch（倒计时门栓）
   - CyclicBarrier（循环栅栏）
   - Semaphore（信号量）
   - Exchanger（数据交换器）

3. **无锁编程**
   - 手写无锁栈和无锁队列
   - LongAdder的分段锁思想
   - 自旋锁的实现与优化

敬请期待！

---

**本文要点回顾**：

```
线程安全的三种实现方式：
├─ 无状态：没有共享数据，天然线程安全
├─ 不可变：状态不能改变，天然线程安全
└─ 同步：synchronized、Lock

synchronized：
├─ 锁升级：偏向锁 → 轻量级锁 → 重量级锁
├─ Monitor机制：_owner、_EntryList、_WaitSet
├─ wait/notify：线程间通信
└─ 优势：简单、JVM优化

Lock接口：
├─ tryLock：尝试获取锁
├─ lockInterruptibly：可中断
├─ Condition：多个条件队列
└─ 优势：灵活、功能丰富

AQS：
├─ 同步状态：volatile int state
├─ CLH队列：FIFO等待队列
├─ 独占模式：ReentrantLock
└─ 共享模式：CountDownLatch（下一篇）

死锁：
├─ 四个必要条件：互斥、持有并等待、不可剥夺、循环等待
├─ 预防策略：破坏任意一个条件
└─ 检测工具：jstack、JConsole、Arthas
```

---

**系列文章**：
1. ✅ Java并发第一性原理：为什么并发如此困难？
2. ✅ **线程安全与同步机制：从synchronized到Lock的演进**（本文）
3. ⏳ 并发工具类与原子操作：无锁编程的艺术
4. ⏳ 线程池与异步编程：从Thread到CompletableFuture
5. ⏳ 并发集合：从HashMap到ConcurrentHashMap
6. ⏳ 并发设计模式与最佳实践

---

**参考资料**：
- 《Java并发编程实战》- Brian Goetz
- 《Java并发编程的艺术》- 方腾飞、魏鹏、程晓明
- JDK源码：java.util.concurrent.locks包
- 《深入理解Java虚拟机》- 周志明

---

**关于作者**：
专注于Java技术栈的深度研究，致力于用第一性原理思维拆解复杂技术问题。本系列文章采用渐进式复杂度模型，从"为什么"出发，系统化学习Java并发编程。

如果这篇文章对你有帮助，欢迎关注本系列后续文章！
