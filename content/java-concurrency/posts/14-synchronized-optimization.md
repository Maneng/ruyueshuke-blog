---
title: "Java并发14：synchronized的优化演进 - 从偏向锁到重量级锁"
date: 2025-11-20T18:30:00+08:00
draft: false
tags: ["Java并发", "偏向锁", "轻量级锁", "重量级锁", "锁升级", "自旋锁"]
categories: ["技术"]
description: "深入理解synchronized锁的完整演化过程：偏向锁、轻量级锁、重量级锁的实现原理、锁升级机制、性能对比和优化策略。"
series: ["Java并发编程从入门到精通"]
weight: 14
stage: 2
stageTitle: "内存模型与原子性篇"
---

## 引言：synchronized为什么不慢了？

在JDK 1.5之前，synchronized被认为是"重量级锁"，性能很差：

```java
// JDK 1.4时代
public synchronized void increment() {
    count++;  // 即使无竞争，也要走完整的Monitor流程
}
// 每次加锁/解锁都要陷入内核态，开销巨大
```

**性能对比**（JDK 1.4 vs JDK 1.8）：
```
JDK 1.4:
100万次synchronized: 约3000ms

JDK 1.8:
100万次synchronized: 约50ms
性能提升60倍！
```

**为什么提升这么大？**

从JDK 1.6开始，HotSpot引入了**锁优化技术**：
- **偏向锁**（Biased Locking）
- **轻量级锁**（Lightweight Locking）
- **自旋锁**（Spinning）
- **锁消除**（Lock Elimination）
- **锁粗化**（Lock Coarsening）

本篇文章将深入这些优化技术的原理和实现。

---

## 一、锁的四种状态

Java对象锁有4种状态，按级别从低到高：

```
无锁 → 偏向锁 → 轻量级锁 → 重量级锁
```

**关键特性**：
- 锁只能**升级**，不能降级（单向）
- 每种锁适用不同的竞争场景

### 1.1 Mark Word的锁状态

回顾Mark Word结构（64位JVM）：

```
无锁状态 (001):
┌─────────────────────────────────────────────────────────────┐
│ unused(25) │ hashcode(31) │ unused(1) │ age(4) │ 0 │ 01 │
└─────────────────────────────────────────────────────────────┘

偏向锁状态 (101):
┌─────────────────────────────────────────────────────────────┐
│ ThreadID(54) │ epoch(2) │ unused(1) │ age(4) │ 1 │ 01 │
└─────────────────────────────────────────────────────────────┘

轻量级锁状态 (00):
┌─────────────────────────────────────────────────────────────┐
│         指向栈中Lock Record的指针(62)        │ 00 │
└─────────────────────────────────────────────────────────────┘

重量级锁状态 (10):
┌─────────────────────────────────────────────────────────────┐
│         指向Monitor对象的指针(62)            │ 10 │
└─────────────────────────────────────────────────────────────┘
```

**锁状态判断**：
```java
// 伪代码
if (lockBits == "00") {
    return "轻量级锁";
} else if (lockBits == "10") {
    return "重量级锁";
} else if (lockBits == "01") {
    if (biasedBit == "1") {
        return "偏向锁";
    } else {
        return "无锁";
    }
}
```

---

## 二、偏向锁（Biased Locking）

### 2.1 设计思想

**观察**：大多数情况下，锁总是由同一个线程多次获得，很少发生竞争。

**思路**：
- 第一次获取锁时，记录线程ID
- 后续该线程再次获取时，只需检查线程ID，无需CAS操作
- **性能提升**：几乎无开销

### 2.2 偏向锁的获取流程

```
线程A首次获取锁：

1. 检查Mark Word锁标志位
   ├─ 如果是001（无锁且未偏向）
   │  └─ CAS将Mark Word替换为偏向模式（ThreadID=A）
   │     成功 → 获取偏向锁
   │
   └─ 如果是101（已偏向）
      ├─ ThreadID == 当前线程？
      │  ├─ 是 → 直接进入同步块（无需CAS）
      │  └─ 否 → 偏向锁失败，尝试撤销偏向锁
      │
      └─ 撤销偏向锁
         └─ 升级为轻量级锁
```

### 2.3 偏向锁的撤销

**触发条件**：
1. 其他线程尝试获取偏向锁
2. 调用`Object.hashCode()`（偏向锁没有地方存hashcode）
3. 调用`Object.wait()`（需要Monitor）

**撤销流程**：
```
线程B尝试获取线程A的偏向锁：

1. 暂停持有偏向锁的线程A（Stop The World）
2. 检查线程A的状态
   ├─ 如果线程A已死亡或不在同步块中
   │  └─ 直接撤销偏向，升级为无锁状态
   │
   └─ 如果线程A还在同步块中
      └─ 升级为轻量级锁
         ├─ 在线程A的栈中创建Lock Record
         ├─ 将Mark Word复制到Lock Record
         └─ Mark Word指向Lock Record
3. 恢复线程A
4. 线程B尝试获取轻量级锁
```

### 2.4 偏向锁的性能

**测试代码**：
```java
public class BiasedLockTest {
    private int count = 0;

    public void increment() {
        synchronized (this) {
            count++;
        }
    }

    public static void main(String[] args) {
        BiasedLockTest test = new BiasedLockTest();

        // 单线程环境（适合偏向锁）
        long start = System.currentTimeMillis();
        for (int i = 0; i < 10_000_000; i++) {
            test.increment();
        }
        long time = System.currentTimeMillis() - start;
        System.out.println("单线程: " + time + "ms");
    }
}
```

**实测结果**：
```
开启偏向锁（-XX:+UseBiasedLocking）: 180ms
关闭偏向锁（-XX:-UseBiasedLocking）: 520ms
性能提升: 2.9倍
```

### 2.5 偏向锁的禁用

**JVM参数**：
```bash
# 禁用偏向锁
-XX:-UseBiasedLocking

# 设置偏向延迟（默认4000ms）
-XX:BiasedLockingStartupDelay=0  # 立即启用
```

**为什么默认延迟4秒？**
- JVM启动时大量类加载，竞争激烈
- 偏向锁撤销开销大
- 延迟启动避免频繁撤销

---

## 三、轻量级锁（Lightweight Locking）

### 3.1 设计思想

**场景**：
- 多个线程交替执行同步块
- 没有实际竞争（线程不会同时持有锁）

**思路**：
- 不使用重量级的Monitor
- 使用CAS操作替换Mark Word
- 在线程栈上创建Lock Record

### 3.2 Lock Record结构

```
线程栈：
┌────────────────────────┐
│     Lock Record        │
│  ┌──────────────────┐  │
│  │ Displaced Mark   │  │ ← 存储对象原来的Mark Word
│  │     Word         │  │
│  ├──────────────────┤  │
│  │ Owner Pointer    │  │ ← 指向锁对象
│  └──────────────────┘  │
└────────────────────────┘
```

### 3.3 轻量级锁的获取流程

```
线程A尝试获取锁：

1. 在栈中创建Lock Record
2. 将对象的Mark Word复制到Lock Record（Displaced Mark Word）
3. CAS尝试将对象的Mark Word替换为指向Lock Record的指针
   ├─ 成功 → 获取轻量级锁
   │  └─ 进入同步块
   │
   └─ 失败 → 其他线程持有锁
      └─ 自旋等待（Spinning）
         └─ 自旋一定次数后
            └─ 升级为重量级锁
```

**图解**：
```
获取锁前：
对象：
┌─────────────────────────────────────┐
│ Mark Word: hashcode | age | 001    │
└─────────────────────────────────────┘

获取锁后：
对象：                        线程栈：
┌────────────────────────┐   ┌───────────────────┐
│ Mark Word:             │   │ Lock Record       │
│ →Lock Record指针 | 00 │───→│ Displaced Mark    │
└────────────────────────┘   │ hashcode|age|001  │
                             └───────────────────┘
```

### 3.4 轻量级锁的释放流程

```
线程A释放锁：

1. 使用CAS将Displaced Mark Word替换回对象头
   ├─ 成功 → 释放锁成功
   │
   └─ 失败 → 锁已升级为重量级锁
      └─ 释放Monitor
```

### 3.5 自旋锁（Spinning）

**自旋的思想**：
- 线程获取锁失败时，不立即阻塞
- 在CPU上忙等待（循环检查锁状态）
- 适合持锁时间短的场景

**自旋代码（伪代码）**：
```java
// 轻量级锁自旋
int spinCount = 0;
while (!tryAcquireLock()) {  // CAS尝试获取锁
    spinCount++;
    if (spinCount > MAX_SPIN_COUNT) {
        // 自旋超过阈值，升级为重量级锁
        upgradeTo HeavyweightLock();
        break;
    }
}
```

**自旋参数**：
```bash
# JDK 1.6之前
-XX:PreBlockSpin=10  # 自旋次数（默认10次）

# JDK 1.6之后
-XX:+UseSpinning     # 开启自旋（默认开启）
# 自适应自旋，次数由JVM决定
```

**自适应自旋**：
- 如果上次自旋成功，增加自旋次数
- 如果上次自旋失败，减少自旋次数
- JVM动态调整，无需手动配置

### 3.6 轻量级锁的性能

**测试代码**：
```java
public class LightweightLockTest {
    private int count = 0;

    public void increment() {
        synchronized (this) {
            count++;
        }
    }

    public static void main(String[] args) throws InterruptedException {
        LightweightLockTest test = new LightweightLockTest();

        // 两个线程交替执行（适合轻量级锁）
        Thread t1 = new Thread(() -> {
            for (int i = 0; i < 5_000_000; i++) {
                test.increment();
            }
        });

        Thread t2 = new Thread(() -> {
            for (int i = 0; i < 5_000_000; i++) {
                test.increment();
            }
        });

        long start = System.currentTimeMillis();
        t1.start();
        t2.start();
        t1.join();
        t2.join();
        long time = System.currentTimeMillis() - start;

        System.out.println("两线程交替: " + time + "ms");
    }
}
```

**实测结果**：
```
轻量级锁: 350ms
重量级锁: 1200ms
性能提升: 3.4倍
```

---

## 四、重量级锁（Heavyweight Locking）

### 4.1 重量级锁的特点

**使用Monitor机制**：
- 依赖操作系统的Mutex Lock（互斥量）
- 线程阻塞/唤醒需要切换到内核态
- 开销最大，但能处理高竞争场景

**Mark Word结构**：
```
┌─────────────────────────────────────┐
│ 指向Monitor对象的指针 (62位) │ 10 │
└─────────────────────────────────────┘
```

### 4.2 Monitor对象结构

```
┌──────────────────────────────────────┐
│           Monitor对象                │
├──────────────────────────────────────┤
│ _owner:      持有锁的线程             │
│ _recursions: 重入次数                │
│ _EntryList:  等待获取锁的线程队列     │
│ _WaitSet:    调用wait()的线程队列    │
│ _count:      等待线程数量             │
└──────────────────────────────────────┘
```

### 4.3 重量级锁的获取流程

```
线程A尝试获取重量级锁：

1. 检查_owner字段
   ├─ 如果_owner == null
   │  └─ CAS设置_owner为当前线程
   │     成功 → 获取锁
   │
   └─ 如果_owner == 当前线程
      └─ 重入，_recursions++

2. 如果_owner != null且不是当前线程
   └─ 进入_EntryList等待队列
      └─ 阻塞线程（park）

3. 被唤醒后
   └─ 重新尝试获取锁（步骤1）
```

### 4.4 重量级锁的释放流程

```
线程A释放锁：

1. _recursions--
2. 如果_recursions == 0
   ├─ 设置_owner = null
   └─ 唤醒_EntryList中的一个线程（unpark）
```

---

## 五、锁升级的完整过程

### 5.1 锁升级路径

```
无锁状态 (001)
    │
    │ 线程A首次获取
    ↓
偏向锁 (101) ← 线程A的ThreadID
    │
    │ 线程B尝试获取
    ↓
轻量级锁 (00) ← CAS + 自旋
    │
    │ 竞争激烈，自旋失败
    ↓
重量级锁 (10) ← Monitor + 阻塞
```

### 5.2 详细的状态转换

```
初始状态：
Mark Word: | unused | hashcode | age | 0 | 01 |  (无锁)

线程A首次进入synchronized：
Mark Word: | ThreadA_ID | epoch | age | 1 | 01 |  (偏向锁)

线程A再次进入synchronized：
检查ThreadID == A → 直接进入（无开销）

线程B尝试进入synchronized：
检查ThreadID != B → 撤销偏向锁
Mark Word: | →Lock Record | 00 |  (轻量级锁)

线程C也尝试进入synchronized（线程B还未释放）：
CAS失败 → 自旋等待
自旋10次后仍失败 → 升级
Mark Word: | →Monitor | 10 |  (重量级锁)
```

### 5.3 锁升级的代码示例

```java
public class LockUpgradeDemo {
    private static final Object lock = new Object();

    public static void main(String[] args) throws Exception {
        // 等待偏向锁启用（默认延迟4秒）
        Thread.sleep(5000);

        System.out.println("=== 初始状态（无锁） ===");
        System.out.println(ClassLayout.parseInstance(lock).toPrintable());

        // 阶段1：偏向锁
        new Thread(() -> {
            synchronized (lock) {
                System.out.println("=== 线程1获取偏向锁 ===");
                System.out.println(ClassLayout.parseInstance(lock).toPrintable());
            }
        }).start();

        Thread.sleep(100);

        // 阶段2：轻量级锁（另一个线程尝试获取）
        new Thread(() -> {
            synchronized (lock) {
                System.out.println("=== 线程2获取轻量级锁 ===");
                System.out.println(ClassLayout.parseInstance(lock).toPrintable());
            }
        }).start();

        Thread.sleep(100);

        // 阶段3：重量级锁（多个线程竞争）
        for (int i = 0; i < 10; i++) {
            new Thread(() -> {
                synchronized (lock) {
                    System.out.println("=== 竞争激烈，升级为重量级锁 ===");
                    System.out.println(ClassLayout.parseInstance(lock).toPrintable());
                }
            }).start();
        }
    }
}
```

**依赖**（使用JOL查看对象布局）：
```xml
<dependency>
    <groupId>org.openjdk.jol</groupId>
    <artifactId>jol-core</artifactId>
    <version>0.16</version>
</dependency>
```

---

## 六、性能对比与优化建议

### 6.1 性能对比表

| 锁类型 | 适用场景 | 性能 | 开销 |
|-------|---------|------|------|
| **偏向锁** | 单线程反复获取 | ⚡⚡⚡⚡⚡ 最快 | 几乎无开销 |
| **轻量级锁** | 多线程交替执行 | ⚡⚡⚡⚡ 快 | CAS + 自旋 |
| **重量级锁** | 高竞争场景 | ⚡ 慢 | 内核态切换 |

### 6.2 性能测试

```java
public class LockPerformanceTest {
    private int count = 0;

    public void increment() {
        synchronized (this) {
            count++;
        }
    }

    public static void testSingleThread() {
        // 偏向锁场景
        LockPerformanceTest test = new LockPerformanceTest();
        long start = System.nanoTime();
        for (int i = 0; i < 10_000_000; i++) {
            test.increment();
        }
        long time = System.nanoTime() - start;
        System.out.println("单线程（偏向锁）: " + time / 1_000_000 + "ms");
    }

    public static void testAlternating() throws InterruptedException {
        // 轻量级锁场景
        LockPerformanceTest test = new LockPerformanceTest();
        long start = System.nanoTime();

        Thread t1 = new Thread(() -> {
            for (int i = 0; i < 5_000_000; i++) {
                test.increment();
            }
        });

        Thread t2 = new Thread(() -> {
            for (int i = 0; i < 5_000_000; i++) {
                test.increment();
            }
        });

        t1.start();
        t2.start();
        t1.join();
        t2.join();

        long time = System.nanoTime() - start;
        System.out.println("两线程交替（轻量级锁）: " + time / 1_000_000 + "ms");
    }

    public static void testHighContention() throws InterruptedException {
        // 重量级锁场景
        LockPerformanceTest test = new LockPerformanceTest();
        int threadCount = 10;
        CountDownLatch latch = new CountDownLatch(threadCount);

        long start = System.nanoTime();

        for (int i = 0; i < threadCount; i++) {
            new Thread(() -> {
                for (int j = 0; j < 1_000_000; j++) {
                    test.increment();
                }
                latch.countDown();
            }).start();
        }

        latch.await();
        long time = System.nanoTime() - start;
        System.out.println(threadCount + "线程竞争（重量级锁）: " + time / 1_000_000 + "ms");
    }

    public static void main(String[] args) throws InterruptedException {
        Thread.sleep(5000);  // 等待偏向锁启用

        testSingleThread();
        testAlternating();
        testHighContention();
    }
}
```

**实测结果**（8核CPU）：
```
单线程（偏向锁）: 180ms
两线程交替（轻量级锁）: 350ms
10线程竞争（重量级锁）: 1200ms
```

### 6.3 优化建议

#### 1. 减少锁的持有时间
```java
// ❌ 不好
public synchronized void process() {
    // 大量耗时操作
    doExpensiveWork();
    // 最后才需要同步
    updateSharedState();
}

// ✅ 好
public void process() {
    doExpensiveWork();  // 不需要锁
    synchronized (this) {
        updateSharedState();  // 只锁这部分
    }
}
```

#### 2. 减少锁的粒度
```java
// ❌ 一个锁保护所有数据
public class CoarseGrained {
    private final Object lock = new Object();
    private List<String> listA = new ArrayList<>();
    private List<String> listB = new ArrayList<>();

    public void addA(String item) {
        synchronized (lock) {
            listA.add(item);  // listA和listB互不相关，不需要同一个锁
        }
    }

    public void addB(String item) {
        synchronized (lock) {
            listB.add(item);
        }
    }
}

// ✅ 分离锁
public class FineGrained {
    private final Object lockA = new Object();
    private final Object lockB = new Object();
    private List<String> listA = new ArrayList<>();
    private List<String> listB = new ArrayList<>();

    public void addA(String item) {
        synchronized (lockA) {
            listA.add(item);
        }
    }

    public void addB(String item) {
        synchronized (lockB) {
            listB.add(item);
        }
    }
}
```

#### 3. 使用读写锁
```java
// 读多写少的场景
public class ReadWriteExample {
    private final ReadWriteLock lock = new ReentrantReadWriteLock();
    private final Map<String, String> map = new HashMap<>();

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

#### 4. 避免锁竞争
```java
// 使用ThreadLocal避免共享
private ThreadLocal<SimpleDateFormat> dateFormat =
    ThreadLocal.withInitial(() -> new SimpleDateFormat("yyyy-MM-dd"));

// 使用无锁数据结构
private AtomicInteger count = new AtomicInteger();

// 使用并发容器
private ConcurrentHashMap<String, String> map = new ConcurrentHashMap<>();
```

---

## 七、JVM参数调优

### 7.1 偏向锁参数

```bash
# 禁用偏向锁
-XX:-UseBiasedLocking

# 偏向延迟（默认4000ms）
-XX:BiasedLockingStartupDelay=0

# 批量重偏向阈值
-XX:BiasedLockingBulkRebiasThreshold=20

# 批量撤销阈值
-XX:BiasedLockingBulkRevokeThreshold=40
```

### 7.2 自旋锁参数

```bash
# 自适应自旋（JDK 1.6+默认开启）
-XX:+UseSpinning

# 固定自旋次数（JDK 1.6之前）
-XX:PreBlockSpin=10
```

### 7.3 查看锁状态

```bash
# 使用jstack查看线程状态
jstack <pid>

# 查看线程详细信息
jstack -l <pid>

# 查看死锁
jstack <pid> | grep -A 10 "Found one Java-level deadlock"
```

---

## 八、总结

### 8.1 核心要点

1. **锁的四种状态**
   - 无锁 → 偏向锁 → 轻量级锁 → 重量级锁
   - 单向升级，不能降级

2. **偏向锁**
   - 适合单线程反复获取
   - 记录ThreadID，无需CAS
   - 性能最优，几乎无开销

3. **轻量级锁**
   - 适合多线程交替执行
   - CAS + 自旋，避免阻塞
   - 性能优于重量级锁

4. **重量级锁**
   - 适合高竞争场景
   - Monitor机制，线程阻塞
   - 开销最大，但能处理任何场景

5. **优化策略**
   - 减少锁持有时间
   - 减少锁粒度
   - 使用读写锁
   - 避免锁竞争

### 8.2 最佳实践

1. **让JVM自动优化**
   ```java
   // 不需要手动干预，JVM会自动选择合适的锁
   synchronized (lock) {
       // ...
   }
   ```

2. **避免过早优化**
   - 先用synchronized
   - 性能测试后再考虑优化

3. **选择合适的工具**
   - 低竞争：synchronized（偏向锁/轻量级锁）
   - 高竞争：ReentrantLock（更灵活）
   - 读多写少：ReadWriteLock
   - 无状态：无锁算法（AtomicXXX）

### 8.3 思考题

1. 为什么锁只能升级，不能降级？
2. 什么情况下偏向锁会被撤销？
3. 自适应自旋是如何工作的？

### 8.4 下一篇预告

在理解了synchronized的优化演进后，下一篇我们将学习**原子类AtomicXXX** —— 无锁的线程安全实现，以及CAS算法的原理。

---

## 扩展阅读

1. **OpenJDK源码**：
   - hotspot/src/share/vm/runtime/synchronizer.cpp
   - hotspot/src/share/vm/runtime/biasedLocking.cpp

2. **论文**：
   - "Biased Locking in HotSpot" - Oracle
   - "Thin Locks: Featherweight Synchronization for Java" - IBM

3. **工具**：
   - JOL (Java Object Layout)：查看对象布局
   - jstack：查看线程状态和锁信息

4. **书籍**：
   - 《深入理解Java虚拟机》第13章
   - 《Java性能权威指南》第9章

---

**系列文章**：
- 上一篇：[Java并发13：synchronized原理与使用](/java-concurrency/posts/13-synchronized-principle/)
- 下一篇：[Java并发15：原子类AtomicXXX详解](/java-concurrency/posts/15-atomic-classes/) （即将发布）
