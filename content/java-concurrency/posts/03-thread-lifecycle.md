---
title: "Java并发03：Java线程的生命周期 - 6种状态详解"
date: 2025-11-20T12:00:00+08:00
draft: false
tags: ["Java并发", "线程状态", "jstack", "问题排查"]
categories: ["技术"]
description: "从生产环境CPU飙升的排查场景出发，深入理解Java线程的6种状态。掌握状态转换规则，学会使用jstack分析线程问题"
series: ["Java并发编程从入门到精通"]
weight: 3
stage: 1
stageTitle: "并发基础篇"
---

## 引言：一次生产事故的排查

凌晨2点，生产环境告警：**CPU使用率持续100%**。

```bash
# 使用top命令查看，发现Java进程CPU占用异常
$ top
PID   USER  %CPU  %MEM  COMMAND
12345 app   850.0 45.2  java -jar app.jar  ← 8核CPU，占用850%
```

使用 `jstack` 查看线程状态：

```bash
$ jstack 12345 > thread-dump.txt

# 查看线程dump
"http-nio-8080-exec-45" #78 daemon prio=5 os_prio=0 tid=0x00007f8c4c001000 nid=0x1a2b RUNNABLE
   java.lang.Thread.State: RUNNABLE
   at java.net.SocketInputStream.socketRead0(Native Method)
   ...

"DB-Pool-Worker-23" #56 daemon prio=5 os_prio=0 tid=0x00007f8c48005000 nid=0x1a1f WAITING
   java.lang.Thread.State: WAITING (parking)
   at sun.misc.Unsafe.park(Native Method)
   ...

"Task-Executor-8" #45 daemon prio=5 os_prio=0 tid=0x00007f8c44003000 nid=0x1a0d BLOCKED
   java.lang.Thread.State: BLOCKED (on object monitor)
   at com.example.Service.process(Service.java:42)
   - waiting to lock <0x000000076b5d4c00> (a java.lang.Object)
   ...
```

**RUNNABLE、WAITING、BLOCKED... 这些状态是什么意思？**

理解线程的生命周期和状态转换，是排查并发问题的基础。

---

## 一、线程的6种状态

Java线程在其生命周期中会经历6种状态，定义在 `Thread.State` 枚举中：

```java
public enum State {
    NEW,           // 新建
    RUNNABLE,      // 可运行
    BLOCKED,       // 阻塞
    WAITING,       // 等待
    TIMED_WAITING, // 超时等待
    TERMINATED     // 终止
}
```

---

## 二、状态详解

### 2.1 NEW（新建状态）

**定义**：线程对象被创建，但还没有调用 `start()` 方法。

```java
public class NewStateExample {
    public static void main(String[] args) {
        Thread thread = new Thread(() -> {
            System.out.println("线程执行");
        });

        // 此时线程处于NEW状态
        System.out.println("状态: " + thread.getState());  // NEW
        System.out.println("是否存活: " + thread.isAlive());  // false
    }
}
```

**输出**：
```
状态: NEW
是否存活: false
```

**关键点**：
- 线程对象存在，但还未分配操作系统资源
- `isAlive()` 返回 `false`
- 不占用CPU时间

---

### 2.2 RUNNABLE（可运行状态）

**定义**：线程正在Java虚拟机中执行，但可能在等待CPU时间片。

```java
public class RunnableStateExample {
    public static void main(String[] args) throws Exception {
        Thread thread = new Thread(() -> {
            // CPU密集型任务
            long sum = 0;
            for (long i = 0; i < 10_000_000_000L; i++) {
                sum += i;
            }
        });

        thread.start();
        Thread.sleep(100);  // 等待线程开始运行

        // 此时线程处于RUNNABLE状态
        System.out.println("状态: " + thread.getState());  // RUNNABLE
        System.out.println("是否存活: " + thread.isAlive());  // true
    }
}
```

**重要！RUNNABLE包含两种子状态**：

```
RUNNABLE状态的真相

1. Ready（就绪）
┌─────────────┐
│   线程A     │ ← 等待CPU时间片
│   线程B     │
│   线程C     │
└─────────────┘
       ↓ 获得CPU时间片

2. Running（运行中）
┌─────────────┐
│   CPU核心   │
│   执行线程A │ ← 正在CPU上运行
└─────────────┘
```

**为什么Java不区分Ready和Running？**

因为这是**操作系统层面的细节**，Java无法直接感知。从Java的角度看，只要线程没有被阻塞，就是RUNNABLE状态。

**特殊情况**：线程在等待IO（如网络IO、磁盘IO）时，虽然没有执行CPU指令，但仍然是RUNNABLE状态。

```java
public class IoBlockingExample {
    public static void main(String[] args) throws Exception {
        Thread thread = new Thread(() -> {
            try {
                // 阻塞等待网络IO
                InputStream in = new URL("https://www.baidu.com").openStream();
                in.read();
            } catch (Exception e) {
                e.printStackTrace();
            }
        });

        thread.start();
        Thread.sleep(100);

        // 虽然在等待IO，但状态仍然是RUNNABLE
        System.out.println("状态: " + thread.getState());  // RUNNABLE
    }
}
```

---

### 2.3 BLOCKED（阻塞状态）

**定义**：线程在等待获取一个**排它锁**（synchronized锁）。

```java
public class BlockedStateExample {
    private static final Object lock = new Object();

    public static void main(String[] args) throws Exception {
        // 线程1：持有锁
        Thread t1 = new Thread(() -> {
            synchronized (lock) {
                System.out.println("线程1获得锁");
                try {
                    Thread.sleep(5000);  // 持有锁5秒
                } catch (InterruptedException e) {}
            }
        }, "Thread-1");

        // 线程2：尝试获取锁，会被阻塞
        Thread t2 = new Thread(() -> {
            System.out.println("线程2尝试获取锁...");
            synchronized (lock) {  // ← 这里会阻塞
                System.out.println("线程2获得锁");
            }
        }, "Thread-2");

        t1.start();
        Thread.sleep(100);  // 确保线程1先获得锁

        t2.start();
        Thread.sleep(100);  // 等待线程2进入BLOCKED状态

        // 此时线程2处于BLOCKED状态
        System.out.println("线程2状态: " + t2.getState());  // BLOCKED

        t1.join();
        t2.join();
    }
}
```

**输出**：
```
线程1获得锁
线程2尝试获取锁...
线程2状态: BLOCKED
线程2获得锁
```

**BLOCKED状态的特点**：

1. **专属于synchronized**：只有等待synchronized锁时才会进入BLOCKED状态
2. **被动等待**：线程不主动放弃CPU，由JVM自动管理
3. **在等待队列中**：所有等待同一个锁的线程在**Entry Set**中排队

```
synchronized锁的等待队列

                Monitor（对象监视器）
┌─────────────────────────────────────┐
│                                     │
│  Entry Set (入口队列)               │
│  ┌───────┐  ┌───────┐  ┌───────┐  │
│  │线程2  │  │线程3  │  │线程4  │  │ ← BLOCKED状态
│  │BLOCKED│  │BLOCKED│  │BLOCKED│  │
│  └───────┘  └───────┘  └───────┘  │
│       ↓                             │
│  ┌───────────────┐                 │
│  │  Owner        │                 │
│  │  线程1持有锁  │ ← RUNNABLE状态  │
│  └───────────────┘                 │
│                                     │
│  Wait Set (等待队列)                │
│  ┌───────┐  ┌───────┐              │
│  │线程5  │  │线程6  │              │ ← WAITING状态
│  │WAITING│  │WAITING│              │
│  └───────┘  └───────┘              │
└─────────────────────────────────────┘
```

---

### 2.4 WAITING（等待状态）

**定义**：线程在等待其他线程执行特定操作（通知或中断），**无限期等待**。

**3种进入WAITING状态的方式**：

#### 方式1：Object.wait()

```java
public class WaitingStateExample1 {
    private static final Object lock = new Object();

    public static void main(String[] args) throws Exception {
        Thread t1 = new Thread(() -> {
            synchronized (lock) {
                try {
                    System.out.println("线程1开始等待");
                    lock.wait();  // ← 进入WAITING状态
                    System.out.println("线程1被唤醒");
                } catch (InterruptedException e) {}
            }
        }, "Thread-1");

        t1.start();
        Thread.sleep(100);

        // 线程1处于WAITING状态
        System.out.println("线程1状态: " + t1.getState());  // WAITING

        // 唤醒线程1
        synchronized (lock) {
            lock.notify();
        }

        t1.join();
    }
}
```

#### 方式2：Thread.join()

```java
public class WaitingStateExample2 {
    public static void main(String[] args) throws Exception {
        Thread t1 = new Thread(() -> {
            try {
                Thread.sleep(2000);
            } catch (InterruptedException e) {}
        }, "Thread-1");

        Thread t2 = new Thread(() -> {
            try {
                t1.join();  // ← 等待t1执行完成，进入WAITING状态
            } catch (InterruptedException e) {}
        }, "Thread-2");

        t1.start();
        t2.start();
        Thread.sleep(100);

        // 线程2处于WAITING状态
        System.out.println("线程2状态: " + t2.getState());  // WAITING

        t1.join();
        t2.join();
    }
}
```

#### 方式3：LockSupport.park()

```java
public class WaitingStateExample3 {
    public static void main(String[] args) throws Exception {
        Thread t1 = new Thread(() -> {
            System.out.println("线程1开始等待");
            LockSupport.park();  // ← 进入WAITING状态
            System.out.println("线程1被唤醒");
        }, "Thread-1");

        t1.start();
        Thread.sleep(100);

        // 线程1处于WAITING状态
        System.out.println("线程1状态: " + t1.getState());  // WAITING

        // 唤醒线程1
        LockSupport.unpark(t1);

        t1.join();
    }
}
```

**WAITING vs BLOCKED的区别**：

| 维度 | BLOCKED | WAITING |
|------|---------|---------|
| **触发原因** | 等待synchronized锁 | 调用wait()/join()/park() |
| **是否释放锁** | 从未获得锁 | 调用wait()会释放锁 |
| **唤醒方式** | 锁的持有者释放锁 | notify()/notifyAll()/unpark() |
| **是否主动** | 被动等待（JVM管理） | 主动等待（代码调用） |

---

### 2.5 TIMED_WAITING（超时等待状态）

**定义**：与WAITING类似，但有**时间限制**，超时后自动返回。

**5种进入TIMED_WAITING状态的方式**：

#### 方式1：Thread.sleep(long)

```java
public class TimedWaitingExample1 {
    public static void main(String[] args) throws Exception {
        Thread t1 = new Thread(() -> {
            try {
                Thread.sleep(5000);  // ← 进入TIMED_WAITING状态
            } catch (InterruptedException e) {}
        }, "Thread-1");

        t1.start();
        Thread.sleep(100);

        // 线程1处于TIMED_WAITING状态
        System.out.println("线程1状态: " + t1.getState());  // TIMED_WAITING

        t1.join();
    }
}
```

#### 方式2：Object.wait(long)

```java
public class TimedWaitingExample2 {
    private static final Object lock = new Object();

    public static void main(String[] args) throws Exception {
        Thread t1 = new Thread(() -> {
            synchronized (lock) {
                try {
                    lock.wait(5000);  // ← 最多等待5秒
                } catch (InterruptedException e) {}
            }
        }, "Thread-1");

        t1.start();
        Thread.sleep(100);

        System.out.println("线程1状态: " + t1.getState());  // TIMED_WAITING

        t1.join();
    }
}
```

#### 方式3：Thread.join(long)

```java
Thread.join(5000);  // 最多等待5秒
```

#### 方式4：LockSupport.parkNanos(long)

```java
LockSupport.parkNanos(5_000_000_000L);  // 等待5秒（纳秒）
```

#### 方式5：LockSupport.parkUntil(long)

```java
LockSupport.parkUntil(System.currentTimeMillis() + 5000);  // 等到指定时间
```

**TIMED_WAITING vs WAITING**：

| 状态 | 是否有超时 | 自动恢复 |
|------|-----------|---------|
| WAITING | 无超时 | 需要显式唤醒 |
| TIMED_WAITING | 有超时 | 超时自动恢复 |

---

### 2.6 TERMINATED（终止状态）

**定义**：线程执行完成或因异常退出。

```java
public class TerminatedStateExample {
    public static void main(String[] args) throws Exception {
        Thread t1 = new Thread(() -> {
            System.out.println("线程执行");
        }, "Thread-1");

        System.out.println("启动前: " + t1.getState());  // NEW

        t1.start();
        t1.join();  // 等待线程执行完成

        System.out.println("结束后: " + t1.getState());  // TERMINATED
        System.out.println("是否存活: " + t1.isAlive());  // false
    }
}
```

**输出**：
```
启动前: NEW
线程执行
结束后: TERMINATED
是否存活: false
```

**注意**：
- 线程一旦进入TERMINATED状态，就不能再次启动
- 再次调用 `start()` 会抛出 `IllegalThreadStateException`

```java
thread.start();
thread.join();
thread.start();  // ← IllegalThreadStateException！
```

---

## 三、线程状态转换图

```
完整的线程状态转换图

                    start()
        NEW ─────────────────→ RUNNABLE ←─────────────┐
                                  │  ↑                 │
                                  │  │                 │
         获得锁/时间片到期/完成IO │  │ 获得锁/notify  │
                                  │  │ /时间到        │
                                  ↓  │                 │
        ┌──────────────────────────────────────┐      │
        │                                      │      │
 等待锁 │           进入synchronized           │      │
        ↓                                      │      │
    BLOCKED                                    │      │
                                               │      │
 wait()                                        │      │
 join() ────────────────→ WAITING ─────────────┘      │
 park()                                               │
        │                                             │
        │                                             │
 sleep(long)                                          │
 wait(long)  ──────────→ TIMED_WAITING ───────────────┘
 join(long)
 parkNanos(long)
        │
        │
        │ run()方法执行完毕
        │ 或抛出未捕获异常
        ↓
    TERMINATED
```

**关键转换规则**：

1. **NEW → RUNNABLE**
   - 触发：调用 `start()` 方法
   - 不可逆：一旦启动，不能回到NEW状态

2. **RUNNABLE → BLOCKED**
   - 触发：尝试获取synchronized锁失败
   - 恢复：获得锁后自动进入RUNNABLE

3. **RUNNABLE → WAITING**
   - 触发：调用 `wait()`、`join()`、`park()`
   - 恢复：`notify()`、`notifyAll()`、`unpark()`

4. **RUNNABLE → TIMED_WAITING**
   - 触发：调用 `sleep(long)`、`wait(long)`、`join(long)` 等
   - 恢复：超时或被提前唤醒

5. **任何状态 → TERMINATED**
   - 触发：run()方法执行完毕 或 抛出未捕获异常
   - 不可逆：不能重新启动

---

## 四、实战：使用jstack分析线程状态

### 4.1 导出线程dump

```bash
# 方法1：使用jstack
jstack <pid> > thread-dump.txt

# 方法2：在程序中生成
jstack <pid> | grep "java.lang.Thread.State" | sort | uniq -c
```

### 4.2 分析线程dump

#### 案例1：大量BLOCKED线程（锁竞争激烈）

```
"Task-Worker-45" #78 daemon prio=5 os_prio=0 BLOCKED
   java.lang.Thread.State: BLOCKED (on object monitor)
   at com.example.Service.process(Service.java:42)
   - waiting to lock <0x000000076b5d4c00> (a java.lang.Object)
   - locked <0x000000076b5d4c10> (a java.lang.Object)

"Task-Worker-46" #79 daemon prio=5 os_prio=0 BLOCKED
   java.lang.Thread.State: BLOCKED (on object monitor)
   at com.example.Service.process(Service.java:42)
   - waiting to lock <0x000000076b5d4c00> (a java.lang.Object)
```

**分析**：
- 多个线程在等待同一把锁（`<0x000000076b5d4c00>`）
- **问题**：锁粒度太大，导致锁竞争激烈
- **解决**：缩小锁范围，或使用并发容器

#### 案例2：大量WAITING线程（线程池空闲）

```
"DB-Pool-Worker-1" #25 daemon prio=5 os_prio=0 WAITING
   java.lang.Thread.State: WAITING (parking)
   at sun.misc.Unsafe.park(Native Method)
   at java.util.concurrent.locks.LockSupport.park(LockSupport.java:175)
   at java.util.concurrent.LinkedBlockingQueue.take(LinkedBlockingQueue.java:442)

"DB-Pool-Worker-2" #26 daemon prio=5 os_prio=0 WAITING
   java.lang.Thread.State: WAITING (parking)
   at sun.misc.Unsafe.park(Native Method)
   ...
```

**分析**：
- 线程池的工作线程在等待任务（`LinkedBlockingQueue.take()`）
- **这是正常的**：线程池空闲时，工作线程会等待新任务

#### 案例3：大量RUNNABLE线程（CPU密集型或IO阻塞）

```
"http-nio-8080-exec-45" #78 daemon prio=5 os_prio=0 RUNNABLE
   java.lang.Thread.State: RUNNABLE
   at java.net.SocketInputStream.socketRead0(Native Method)
   at java.net.SocketInputStream.socketRead(SocketInputStream.java:116)
   ...
```

**分析**：
- 线程在等待网络IO（`socketRead0`）
- 虽然状态是RUNNABLE，但实际在等待IO
- **注意**：这不是CPU密集型，是IO阻塞

### 4.3 使用Java代码监控线程状态

```java
public class ThreadMonitor {
    public static void main(String[] args) {
        // 获取所有线程
        ThreadMXBean threadMXBean = ManagementFactory.getThreadMXBean();
        long[] threadIds = threadMXBean.getAllThreadIds();

        // 统计各状态的线程数
        Map<Thread.State, Integer> stateCount = new HashMap<>();
        for (Thread.State state : Thread.State.values()) {
            stateCount.put(state, 0);
        }

        for (long threadId : threadIds) {
            ThreadInfo threadInfo = threadMXBean.getThreadInfo(threadId);
            if (threadInfo != null) {
                Thread.State state = threadInfo.getThreadState();
                stateCount.put(state, stateCount.get(state) + 1);
            }
        }

        // 打印统计结果
        System.out.println("线程状态统计：");
        stateCount.forEach((state, count) ->
            System.out.println(state + ": " + count + " 个线程")
        );
    }
}
```

**输出示例**：
```
线程状态统计：
NEW: 0 个线程
RUNNABLE: 12 个线程
BLOCKED: 3 个线程
WAITING: 15 个线程
TIMED_WAITING: 8 个线程
TERMINATED: 0 个线程
```

---

## 五、常见误区

### 误区1：RUNNABLE = 正在运行

❌ **错误理解**：RUNNABLE状态的线程一定在CPU上运行。

✅ **正确理解**：RUNNABLE包含两种情况：
1. **Ready**：等待CPU时间片
2. **Running**：正在CPU上运行

```java
// 100个线程都是RUNNABLE，但8核CPU最多8个在运行
ExecutorService executor = Executors.newFixedThreadPool(100);
for (int i = 0; i < 100; i++) {
    executor.submit(() -> {
        while (true) {
            // CPU密集型任务
        }
    });
}
```

### 误区2：BLOCKED和WAITING是一回事

❌ **错误理解**：BLOCKED和WAITING都是等待，没有区别。

✅ **正确理解**：

| BLOCKED | WAITING |
|---------|---------|
| 等待synchronized锁 | 调用wait()/park()主动等待 |
| 被动（JVM管理） | 主动（代码调用） |
| 在Entry Set队列 | 在Wait Set队列 |
| 不释放已持有的锁 | wait()会释放锁 |

### 误区3：线程状态转换是瞬时的

❌ **错误理解**：调用 `notify()` 后，线程立即从WAITING变成RUNNABLE。

✅ **正确理解**：

```
notify()后的状态转换
1. 线程A调用notify()
   └→ 将线程B从Wait Set移到Entry Set

2. 线程A释放锁（退出synchronized块）
   └→ 线程B和其他BLOCKED线程开始竞争锁

3. 线程B获得锁
   └→ 线程B从BLOCKED变成RUNNABLE

4. 线程B从wait()返回继续执行
```

### 误区4：sleep不会释放锁

✅ **正确**：`Thread.sleep()` 不会释放synchronized锁。

```java
synchronized (lock) {
    Thread.sleep(1000);  // ← 持有锁的同时sleep
    // 其他线程无法获得lock
}
```

❌ **但要注意**：`wait()` 会释放锁！

```java
synchronized (lock) {
    lock.wait(1000);  // ← 释放锁，其他线程可以获得lock
}
```

---

## 六、总结

### 6.1 核心要点

1. **Java线程有6种状态**：
   - NEW：对象创建，未启动
   - RUNNABLE：正在执行或等待CPU
   - BLOCKED：等待synchronized锁
   - WAITING：无限期等待（wait/join/park）
   - TIMED_WAITING：有超时的等待（sleep/wait(long)）
   - TERMINATED：执行完成

2. **关键区别**：
   - RUNNABLE包含Ready和Running，Java不区分
   - BLOCKED是被动等待synchronized锁
   - WAITING是主动调用wait()/park()
   - TIMED_WAITING有超时限制

3. **实战技巧**：
   - 使用jstack导出线程dump
   - 大量BLOCKED→锁竞争问题
   - 大量WAITING→正常（线程池空闲）或死锁
   - RUNNABLE+高CPU→CPU密集型或死循环
   - RUNNABLE+低CPU→IO阻塞

### 6.2 快速记忆口诀

```
NEW未启动，TERMINATED已结束
RUNNABLE在运行，包含Ready和Running
BLOCKED等synchronized，被动等待在队列
WAITING主动等，wait/join/park
TIMED_WAITING有超时，sleep最常见
```

### 6.3 思考题

1. 为什么Java不区分Ready和Running状态？
2. 一个线程处于BLOCKED状态，能被 `interrupt()` 中断吗？
3. 为什么 `wait()` 需要在synchronized块中调用？
4. 如何判断线程池的线程数是否设置合理？

### 6.4 下一篇预告

**《线程的创建与启动：4种方式对比》**

- 继承Thread vs 实现Runnable的区别？
- Callable如何返回结果？
- 线程池是如何创建线程的？
- Lambda表达式如何简化线程创建？

---

## 扩展阅读

- [Java Thread States](https://docs.oracle.com/javase/8/docs/api/java/lang/Thread.State.html)
- [jstack命令详解](https://docs.oracle.com/javase/8/docs/technotes/tools/unix/jstack.html)
- [Analyzing Thread Dumps](https://dzone.com/articles/how-to-analyze-java-thread-dumps)
- [Understanding JVM Thread States](https://www.baeldung.com/java-thread-lifecycle)
