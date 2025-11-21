---
title: "死锁的产生与排查：从原理到实战"
date: 2025-11-20T12:00:00+08:00
draft: false
tags: ["Java并发", "死锁", "问题排查", "调优"]
categories: ["技术"]
description: "深入理解死锁的产生原理，掌握死锁排查方法和预防策略，彻底解决死锁问题"
series: ["Java并发编程从入门到精通"]
weight: 34
stage: 5
stageTitle: "问题排查篇"
---

## 一、什么是死锁？

### 1.1 死锁示例

```java
public class DeadlockDemo {
    private static Object lock1 = new Object();
    private static Object lock2 = new Object();

    public static void main(String[] args) {
        // 线程1：先锁lock1，再锁lock2
        Thread t1 = new Thread(() -> {
            synchronized (lock1) {
                System.out.println("线程1：持有lock1，等待lock2");

                sleep(100);  // 模拟业务逻辑

                synchronized (lock2) {
                    System.out.println("线程1：获取lock2成功");
                }
            }
        });

        // 线程2：先锁lock2，再锁lock1
        Thread t2 = new Thread(() -> {
            synchronized (lock2) {
                System.out.println("线程2：持有lock2，等待lock1");

                sleep(100);

                synchronized (lock1) {
                    System.out.println("线程2：获取lock1成功");
                }
            }
        });

        t1.start();
        t2.start();

        // 输出：
        // 线程1：持有lock1，等待lock2
        // 线程2：持有lock2，等待lock1
        // ... 程序卡住，发生死锁！
    }

    private static void sleep(long millis) {
        try {
            Thread.sleep(millis);
        } catch (InterruptedException e) {
            e.printStackTrace();
        }
    }
}
```

**死锁定义**：
两个或多个线程互相持有对方需要的资源，导致所有线程都无法继续执行。

### 1.2 死锁的四个必要条件

| 条件 | 说明 | 例子 |
|-----|------|------|
| **互斥** | 资源只能被一个线程占用 | synchronized锁 |
| **持有并等待** | 持有资源，同时等待其他资源 | 持有lock1，等待lock2 |
| **不可剥夺** | 资源不能被强制剥夺 | 线程不能抢占其他线程的锁 |
| **循环等待** | 线程之间形成循环等待链 | T1等T2，T2等T1 |

**破坏任意一个条件，即可避免死锁！**

---

## 二、死锁排查方法

### 2.1 jstack命令排查

```bash
# 1. 找到Java进程ID
jps -l
# 输出：12345 com.example.DeadlockDemo

# 2. 使用jstack导出线程堆栈
jstack 12345 > deadlock.txt

# 或者直接查看
jstack 12345
```

**jstack输出示例**：
```
Found one Java-level deadlock:
=============================
"Thread-1":
  waiting to lock monitor 0x00007f8b1c004a00 (object 0x00000007d5f5e5d0, a java.lang.Object),
  which is held by "Thread-0"
"Thread-0":
  waiting to lock monitor 0x00007f8b1c002e00 (object 0x00000007d5f5e5e0, a java.lang.Object),
  which is held by "Thread-1"

Java stack information for the threads listed above:
===================================================
"Thread-1":
	at com.example.DeadlockDemo.lambda$main$1(DeadlockDemo.java:28)
	- waiting to lock <0x00000007d5f5e5d0> (a java.lang.Object)
	- locked <0x00000007d5f5e5e0> (a java.lang.Object)
	...

"Thread-0":
	at com.example.DeadlockDemo.lambda$main$0(DeadlockDemo.java:18)
	- waiting to lock <0x00000007d5f5e5e0> (a java.lang.Object)
	- locked <0x00000007d5f5e5d0> (a java.lang.Object)
	...

Found 1 deadlock.
```

**关键信息**：
- **"Found one Java-level deadlock"**：检测到死锁
- **waiting to lock**：等待锁
- **which is held by**：锁被谁持有
- **循环等待链**：Thread-1 → Thread-0 → Thread-1

### 2.2 jconsole可视化排查

```bash
# 启动jconsole
jconsole
```

**步骤**：
1. 连接到目标Java进程
2. 切换到"线程"选项卡
3. 点击"检测死锁"按钮
4. 如果存在死锁，会显示详细信息

### 2.3 JVisualVM排查

```bash
# 启动jvisualvm
jvisualvm
```

**步骤**：
1. 连接到目标Java进程
2. 切换到"线程"选项卡
3. 查看线程状态图
4. 红色线程 = 死锁线程

### 2.4 编程方式检测

```java
public class DeadlockDetector {

    public static void main(String[] args) throws InterruptedException {
        // 启动死锁检测线程
        Thread detector = new Thread(() -> {
            while (true) {
                detectDeadlock();
                try {
                    Thread.sleep(5000);  // 每5秒检测一次
                } catch (InterruptedException e) {
                    break;
                }
            }
        });
        detector.setDaemon(true);
        detector.start();

        // 主程序...
    }

    public static void detectDeadlock() {
        ThreadMXBean threadMXBean = ManagementFactory.getThreadMXBean();
        long[] deadlockedThreads = threadMXBean.findDeadlockedThreads();

        if (deadlockedThreads != null) {
            System.err.println("检测到死锁！");

            ThreadInfo[] threadInfos = threadMXBean.getThreadInfo(deadlockedThreads);
            for (ThreadInfo threadInfo : threadInfos) {
                System.err.println("线程：" + threadInfo.getThreadName());
                System.err.println("状态：" + threadInfo.getThreadState());
                System.err.println("锁信息：" + threadInfo.getLockName());
                System.err.println("持有锁的线程：" + threadInfo.getLockOwnerName());
                System.err.println("堆栈：");

                for (StackTraceElement element : threadInfo.getStackTrace()) {
                    System.err.println("  " + element);
                }
                System.err.println();
            }
        }
    }
}
```

---

## 三、避免死锁的策略

### 3.1 固定加锁顺序

```java
// ❌ 错误：加锁顺序不一致
// 线程1：lock1 → lock2
// 线程2：lock2 → lock1

// ✅ 正确：固定加锁顺序
public class FixedLockOrder {
    private static Object lock1 = new Object();
    private static Object lock2 = new Object();

    public void transfer1() {
        synchronized (lock1) {  // 统一先锁lock1
            synchronized (lock2) {  // 再锁lock2
                // 业务逻辑
            }
        }
    }

    public void transfer2() {
        synchronized (lock1) {  // 统一先锁lock1
            synchronized (lock2) {  // 再锁lock2
                // 业务逻辑
            }
        }
    }
}
```

### 3.2 使用tryLock超时机制

```java
public class TryLockDemo {
    private Lock lock1 = new ReentrantLock();
    private Lock lock2 = new ReentrantLock();

    public void transfer() throws InterruptedException {
        while (true) {
            // 尝试获取lock1（超时1秒）
            if (lock1.tryLock(1, TimeUnit.SECONDS)) {
                try {
                    // 尝试获取lock2（超时1秒）
                    if (lock2.tryLock(1, TimeUnit.SECONDS)) {
                        try {
                            // 获取两个锁成功，执行业务逻辑
                            System.out.println("转账成功");
                            return;
                        } finally {
                            lock2.unlock();
                        }
                    }
                } finally {
                    lock1.unlock();
                }
            }

            // 获取锁失败，释放已持有的锁，等待后重试
            System.out.println("获取锁失败，重试...");
            Thread.sleep(100);
        }
    }
}
```

### 3.3 使用单一锁

```java
// ❌ 多个锁：容易死锁
public class MultiLockDemo {
    private Object lock1 = new Object();
    private Object lock2 = new Object();

    public void method1() {
        synchronized (lock1) {
            synchronized (lock2) {
                // ...
            }
        }
    }
}

// ✅ 单一锁：简单安全
public class SingleLockDemo {
    private Object lock = new Object();

    public void method1() {
        synchronized (lock) {
            // ...
        }
    }

    public void method2() {
        synchronized (lock) {
            // ...
        }
    }
}
```

### 3.4 使用并发工具类

```java
// ❌ 手动加锁：复杂易错
public class ManualLockDemo {
    private Lock lock1 = new ReentrantLock();
    private Lock lock2 = new ReentrantLock();

    public void transfer() {
        lock1.lock();
        try {
            lock2.lock();
            try {
                // 业务逻辑
            } finally {
                lock2.unlock();
            }
        } finally {
            lock1.unlock();
        }
    }
}

// ✅ 使用并发工具类：简单安全
public class ConcurrentCollectionDemo {
    // 使用线程安全的集合
    private ConcurrentHashMap<String, Integer> map = new ConcurrentHashMap<>();

    public void update(String key) {
        map.compute(key, (k, v) -> (v == null ? 0 : v) + 1);
    }
}
```

---

## 四、实战案例：转账死锁

### 4.1 错误示例

```java
public class BankAccount {
    private int balance;
    private String accountId;

    public BankAccount(String accountId, int balance) {
        this.accountId = accountId;
        this.balance = balance;
    }

    // ❌ 转账方法：可能死锁
    public void transfer(BankAccount target, int amount) {
        synchronized (this) {              // 锁定源账户
            synchronized (target) {         // 锁定目标账户
                if (this.balance >= amount) {
                    this.balance -= amount;
                    target.balance += amount;
                    System.out.println("转账成功：" + accountId + " → " + target.accountId);
                }
            }
        }
    }
}

// 死锁场景：
// 线程1：accountA.transfer(accountB, 100);  // 锁A → 锁B
// 线程2：accountB.transfer(accountA, 100);  // 锁B → 锁A
// → 死锁！
```

### 4.2 解决方案1：固定加锁顺序

```java
public class BankAccount {
    private int balance;
    private int accountId;  // 使用int作为ID

    // ✅ 根据accountId排序，固定加锁顺序
    public void transfer(BankAccount target, int amount) {
        BankAccount first, second;

        if (this.accountId < target.accountId) {
            first = this;
            second = target;
        } else {
            first = target;
            second = this;
        }

        synchronized (first) {
            synchronized (second) {
                if (this.balance >= amount) {
                    this.balance -= amount;
                    target.balance += amount;
                    System.out.println("转账成功");
                }
            }
        }
    }
}
```

### 4.3 解决方案2：全局锁

```java
public class BankAccount {
    private static final Object GLOBAL_LOCK = new Object();  // 全局锁
    private int balance;

    // ✅ 使用全局锁
    public void transfer(BankAccount target, int amount) {
        synchronized (GLOBAL_LOCK) {  // 所有转账共用一个锁
            if (this.balance >= amount) {
                this.balance -= amount;
                target.balance += amount;
                System.out.println("转账成功");
            }
        }
    }
}
```

---

## 五、其他常见死锁场景

### 5.1 哲学家就餐问题

```java
public class DiningPhilosophers {
    private static class Fork {
        private boolean inUse = false;

        public synchronized void pickUp() throws InterruptedException {
            while (inUse) {
                wait();
            }
            inUse = true;
        }

        public synchronized void putDown() {
            inUse = false;
            notifyAll();
        }
    }

    private static class Philosopher extends Thread {
        private Fork leftFork;
        private Fork rightFork;

        public Philosopher(Fork leftFork, Fork rightFork) {
            this.leftFork = leftFork;
            this.rightFork = rightFork;
        }

        @Override
        public void run() {
            try {
                while (true) {
                    // 思考
                    Thread.sleep(1000);

                    // ❌ 可能死锁：所有哲学家同时拿起左手叉子
                    leftFork.pickUp();
                    rightFork.pickUp();

                    // 吃饭
                    System.out.println(getName() + " 正在吃饭");
                    Thread.sleep(1000);

                    // 放下叉子
                    rightFork.putDown();
                    leftFork.putDown();
                }
            } catch (InterruptedException e) {
                e.printStackTrace();
            }
        }
    }

    // ✅ 解决方案：奇数哲学家先拿左叉子，偶数哲学家先拿右叉子
}
```

### 5.2 线程池死锁

```java
// ❌ 线程池内部等待：可能死锁
ExecutorService executor = Executors.newFixedThreadPool(2);

executor.submit(() -> {
    Future<String> future = executor.submit(() -> {
        return "内部任务";
    });

    try {
        String result = future.get();  // 等待内部任务完成
        // 如果线程池满了，内部任务永远无法执行 → 死锁
    } catch (Exception e) {
        e.printStackTrace();
    }
});

// ✅ 解决方案：不要在线程池任务中等待同一个线程池的其他任务
```

---

## 六、死锁排查工具总结

| 工具 | 用法 | 优点 | 缺点 |
|-----|------|------|------|
| **jstack** | `jstack <pid>` | 命令行，快速 | 需要分析文本 |
| **jconsole** | GUI可视化 | 图形化，直观 | 需要安装JDK |
| **JVisualVM** | GUI可视化 | 功能强大 | 性能开销大 |
| **ThreadMXBean** | 编程检测 | 自动化，持续监控 | 需要编码 |
| **Arthas** | `thread -b` | 在线诊断，强大 | 需要部署 |

---

## 七、核心要点总结

### 7.1 死锁的四个必要条件

1. **互斥**：资源只能被一个线程占用
2. **持有并等待**：持有资源，同时等待其他资源
3. **不可剥夺**：资源不能被强制剥夺
4. **循环等待**：线程之间形成循环等待链

### 7.2 避免死锁的策略

| 策略 | 破坏条件 | 实现方式 |
|-----|---------|---------|
| **固定加锁顺序** | 循环等待 | 按ID排序加锁 |
| **tryLock超时** | 持有并等待 | 超时释放锁 |
| **单一锁** | 持有并等待 | 减少锁数量 |
| **并发工具类** | 多个条件 | 使用ConcurrentHashMap等 |

### 7.3 排查死锁步骤

1. **jstack导出堆栈**：`jstack <pid> > deadlock.txt`
2. **查找关键字**：搜索"Found one Java-level deadlock"
3. **分析等待链**：Thread-1 → Thread-0 → Thread-1
4. **定位代码行**：根据堆栈信息定位问题代码
5. **修复代码**：按照避免策略修复

---

## 总结

死锁是并发编程中的经典问题，理解原理和排查方法至关重要：

**核心原理**：
- ✅ **四个必要条件**：互斥、持有并等待、不可剥夺、循环等待
- ✅ **破坏任意条件**即可避免死锁

**排查方法**：
- ✅ **jstack**：快速导出线程堆栈
- ✅ **jconsole/JVisualVM**：可视化检测
- ✅ **ThreadMXBean**：编程自动检测

**避免策略**：
1. **固定加锁顺序**：最常用
2. **tryLock超时**：最灵活
3. **单一锁**：最简单
4. **并发工具类**：最安全

**下一篇预告**：我们将深入线程池监控与调优，学习如何优化线程池性能！
