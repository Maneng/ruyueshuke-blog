---
title: "Java并发04：线程的创建与启动 - 4种方式深度对比"
date: 2025-11-20T13:00:00+08:00
draft: false
tags: ["Java并发", "Thread", "Runnable", "线程池"]
categories: ["技术"]
description: "从面试高频题出发，深度对比继承Thread、实现Runnable、Callable、线程池4种创建线程的方式。掌握start()与run()的区别，理解为什么要用线程池"
series: ["Java并发编程从入门到精通"]
weight: 4
stage: 1
stageTitle: "并发基础篇"
---

## 引言：一道高频面试题

面试官：**请说一下Java中创建线程有哪几种方式？**

候选人A：继承Thread类、实现Runnable接口...还有吗？

面试官：还有吗？Callable算吗？线程池算吗？它们有什么区别？

大部分候选人能说出前两种，但很少有人能说清楚：
- 为什么推荐实现Runnable而不是继承Thread？
- Callable和Runnable的本质区别是什么？
- 线程池是怎么创建线程的？
- start()和run()到底有什么区别？

今天我们从第一性原理出发，彻底搞懂这些问题。

---

## 一、方式1：继承Thread类

### 1.1 基本用法

```java
public class MyThread extends Thread {
    @Override
    public void run() {
        System.out.println("线程执行: " + Thread.currentThread().getName());
    }

    public static void main(String[] args) {
        MyThread thread = new MyThread();
        thread.start();  // 启动线程
    }
}
```

**输出**：
```
线程执行: Thread-0
```

### 1.2 原理分析

```java
// Thread类的核心结构
public class Thread implements Runnable {
    private Runnable target;  // 任务对象

    public Thread() {
        // 空构造
    }

    public Thread(Runnable target) {
        this.target = target;  // 传入任务
    }

    @Override
    public void run() {
        if (target != null) {
            target.run();  // 执行任务
        }
        // 子类可以重写这个方法
    }

    public synchronized void start() {
        // 1. 检查状态
        if (threadStatus != 0)
            throw new IllegalThreadStateException();

        // 2. 加入线程组
        group.add(this);

        // 3. 调用native方法启动线程
        boolean started = false;
        try {
            start0();  // ← native方法，创建操作系统线程
            started = true;
        } finally {
            // ...
        }
    }

    private native void start0();  // JNI调用，创建OS线程
}
```

**关键点**：
- Thread类本身实现了Runnable接口
- start()调用native方法创建操作系统线程
- 新线程会调用run()方法

### 1.3 优缺点

**优点**：
- ✅ 简单直观，易于理解
- ✅ 可以直接访问Thread类的方法

**缺点**：
- ❌ Java单继承限制，无法继承其他类
- ❌ 违反"组合优于继承"原则
- ❌ 线程和任务耦合，复用性差

```java
// ❌ 问题：无法继承其他类
public class MyThread extends Thread {
    // 如果需要继承其他类，就无法实现了
    // public class MyThread extends OtherClass  ← 编译错误
}
```

---

## 二、方式2：实现Runnable接口（推荐）

### 2.1 基本用法

```java
public class MyRunnable implements Runnable {
    @Override
    public void run() {
        System.out.println("线程执行: " + Thread.currentThread().getName());
    }

    public static void main(String[] args) {
        MyRunnable task = new MyRunnable();
        Thread thread = new Thread(task);  // 任务和线程分离
        thread.start();
    }
}
```

### 2.2 任务与线程分离

```
继承Thread方式：任务和线程耦合
┌─────────────────┐
│   MyThread      │
│  - 继承Thread   │
│  - 实现run()    │
│  线程 = 任务    │ ← 一体化，无法分离
└─────────────────┘

实现Runnable方式：任务和线程分离
┌─────────────┐     ┌─────────────┐
│ MyRunnable  │────→│   Thread    │
│ 实现run()   │     │  持有target │
│  (任务)     │     │  (线程)     │
└─────────────┘     └─────────────┘
      ↑                    ↑
  可复用的任务         管理线程生命周期
```

### 2.3 任务复用示例

```java
public class TaskReuse {
    public static void main(String[] args) {
        // 同一个任务可以被多个线程执行
        Runnable task = () -> {
            System.out.println(Thread.currentThread().getName() + " 执行任务");
        };

        Thread t1 = new Thread(task, "线程1");
        Thread t2 = new Thread(task, "线程2");
        Thread t3 = new Thread(task, "线程3");

        t1.start();
        t2.start();
        t3.start();
    }
}
```

**输出**：
```
线程1 执行任务
线程2 执行任务
线程3 执行任务
```

### 2.4 优缺点

**优点**：
- ✅ 符合"组合优于继承"原则
- ✅ 可以继承其他类
- ✅ 任务可以被多个线程共享
- ✅ 适合资源共享场景

**缺点**：
- ❌ 无法返回结果
- ❌ 无法抛出受检异常

```java
// ❌ Runnable无法返回结果
public class MyRunnable implements Runnable {
    @Override
    public void run() {
        int result = calculate();
        // 无法返回result！只能通过共享变量或回调
    }
}
```

---

## 三、方式3：实现Callable接口（有返回值）

### 3.1 基本用法

```java
public class MyCallable implements Callable<Integer> {
    @Override
    public Integer call() throws Exception {
        Thread.sleep(1000);  // 模拟耗时操作
        return 42;  // ← 可以返回结果
    }

    public static void main(String[] args) throws Exception {
        MyCallable task = new MyCallable();

        // 使用FutureTask包装
        FutureTask<Integer> futureTask = new FutureTask<>(task);

        // 提交给线程执行
        Thread thread = new Thread(futureTask);
        thread.start();

        // 获取结果（阻塞等待）
        Integer result = futureTask.get();
        System.out.println("结果: " + result);
    }
}
```

**输出**：
```
结果: 42
```

### 3.2 Callable vs Runnable

| 特性 | Runnable | Callable |
|------|----------|----------|
| **返回值** | 无返回值（void） | 有返回值（泛型） |
| **异常处理** | 无法抛出受检异常 | 可以抛出Exception |
| **使用方式** | 直接传给Thread | 需要FutureTask包装 |
| **适用场景** | 不需要返回结果 | 需要返回结果 |

```java
// Runnable接口
@FunctionalInterface
public interface Runnable {
    void run();  // 无返回值，无法抛出受检异常
}

// Callable接口
@FunctionalInterface
public interface Callable<V> {
    V call() throws Exception;  // 有返回值，可以抛出异常
}
```

### 3.3 FutureTask原理

```java
// FutureTask实现了RunnableFuture接口
public class FutureTask<V> implements RunnableFuture<V> {
    private Callable<V> callable;  // 持有Callable任务
    private Object outcome;        // 保存执行结果
    private volatile int state;    // 任务状态

    public FutureTask(Callable<V> callable) {
        this.callable = callable;
        this.state = NEW;
    }

    @Override
    public void run() {
        try {
            Callable<V> c = callable;
            if (c != null && state == NEW) {
                V result = c.call();  // ← 执行Callable.call()
                set(result);          // ← 保存结果
            }
        } catch (Throwable ex) {
            setException(ex);         // ← 保存异常
        }
    }

    @Override
    public V get() throws InterruptedException, ExecutionException {
        int s = state;
        if (s <= COMPLETING)
            s = awaitDone(false, 0L);  // ← 阻塞等待结果
        return report(s);              // ← 返回结果
    }
}
```

**关键设计**：
1. FutureTask包装Callable，实现Runnable接口
2. run()方法内部调用call()，保存结果
3. get()方法阻塞等待结果

### 3.4 实战案例：并行计算

```java
public class ParallelCalculation {
    public static void main(String[] args) throws Exception {
        // 任务1：计算1-1000的和
        Callable<Long> task1 = () -> {
            long sum = 0;
            for (int i = 1; i <= 1000; i++) {
                sum += i;
            }
            return sum;
        };

        // 任务2：计算1001-2000的和
        Callable<Long> task2 = () -> {
            long sum = 0;
            for (int i = 1001; i <= 2000; i++) {
                sum += i;
            }
            return sum;
        };

        // 并行执行
        FutureTask<Long> future1 = new FutureTask<>(task1);
        FutureTask<Long> future2 = new FutureTask<>(task2);

        new Thread(future1).start();
        new Thread(future2).start();

        // 获取结果并汇总
        long result1 = future1.get();
        long result2 = future2.get();
        long total = result1 + result2;

        System.out.println("1-2000的和: " + total);
    }
}
```

---

## 四、方式4：使用线程池（生产推荐）

### 4.1 基本用法

```java
public class ThreadPoolExample {
    public static void main(String[] args) {
        // 创建固定大小的线程池
        ExecutorService executor = Executors.newFixedThreadPool(5);

        // 提交任务
        for (int i = 0; i < 10; i++) {
            final int taskId = i;
            executor.submit(() -> {
                System.out.println("任务" + taskId + " 执行");
            });
        }

        // 关闭线程池
        executor.shutdown();
    }
}
```

### 4.2 线程池的优势

**对比前3种方式**：

```java
// ❌ 方式1-3：每次创建新线程
for (int i = 0; i < 1000; i++) {
    new Thread(() -> {
        // 执行任务
    }).start();  // ← 创建1000个线程！
}

// ✅ 线程池：复用线程
ExecutorService executor = Executors.newFixedThreadPool(10);
for (int i = 0; i < 1000; i++) {
    executor.submit(() -> {
        // 执行任务
    });  // ← 只用10个线程！
}
```

**线程池的5大优势**：

1. **降低资源消耗**：线程复用，减少创建/销毁开销
2. **提高响应速度**：任务到达时，无需等待线程创建
3. **提高可管理性**：统一管理、监控、调优
4. **提供更多功能**：定时执行、周期执行、并发控制
5. **避免资源耗尽**：限制最大线程数

### 4.3 线程池提交任务的3种方式

```java
ExecutorService executor = Executors.newFixedThreadPool(5);

// 方式1：提交Runnable（无返回值）
executor.execute(() -> {
    System.out.println("execute提交");
});

// 方式2：提交Runnable（有Future，但无实际返回值）
Future<?> future1 = executor.submit(() -> {
    System.out.println("submit提交Runnable");
});
Object result1 = future1.get();  // null

// 方式3：提交Callable（有返回值）
Future<Integer> future2 = executor.submit(() -> {
    return 42;
});
Integer result2 = future2.get();  // 42
```

### 4.4 4种常见线程池

```java
// 1. 固定大小线程池
ExecutorService fixed = Executors.newFixedThreadPool(5);

// 2. 单线程线程池
ExecutorService single = Executors.newSingleThreadExecutor();

// 3. 缓存线程池（自动扩缩容）
ExecutorService cached = Executors.newCachedThreadPool();

// 4. 定时任务线程池
ScheduledExecutorService scheduled = Executors.newScheduledThreadPool(3);
scheduled.schedule(() -> {
    System.out.println("5秒后执行");
}, 5, TimeUnit.SECONDS);
```

**⚠️ 阿里巴巴Java开发手册强制规定**：

> 线程池不允许使用Executors创建，而是通过ThreadPoolExecutor的方式，这样的处理方式让写的同学更加明确线程池的运行规则，规避资源耗尽的风险。

**原因**：

```java
// ❌ newFixedThreadPool的问题
public static ExecutorService newFixedThreadPool(int nThreads) {
    return new ThreadPoolExecutor(nThreads, nThreads,
        0L, TimeUnit.MILLISECONDS,
        new LinkedBlockingQueue<Runnable>());  // ← 无界队列！可能OOM
}

// ❌ newCachedThreadPool的问题
public static ExecutorService newCachedThreadPool() {
    return new ThreadPoolExecutor(0, Integer.MAX_VALUE,  // ← 无限线程！
        60L, TimeUnit.SECONDS,
        new SynchronousQueue<Runnable>());
}
```

**✅ 推荐的创建方式**：

```java
ThreadPoolExecutor executor = new ThreadPoolExecutor(
    5,                      // 核心线程数
    10,                     // 最大线程数
    60L,                    // 空闲线程存活时间
    TimeUnit.SECONDS,       // 时间单位
    new ArrayBlockingQueue<>(100),  // 有界队列
    new ThreadFactory() {   // 自定义线程工厂
        private AtomicInteger count = new AtomicInteger(1);
        @Override
        public Thread newThread(Runnable r) {
            return new Thread(r, "MyPool-" + count.getAndIncrement());
        }
    },
    new ThreadPoolExecutor.CallerRunsPolicy()  // 拒绝策略
);
```

---

## 五、start() vs run()：本质区别

### 5.1 错误示例

```java
public class StartVsRun {
    public static void main(String[] args) {
        Thread thread = new Thread(() -> {
            System.out.println("线程: " + Thread.currentThread().getName());
        });

        // ❌ 错误：直接调用run()
        thread.run();  // 在主线程中执行，不会创建新线程

        // ✅ 正确：调用start()
        thread.start();  // 创建新线程执行
    }
}
```

**输出对比**：

```
// thread.run() 的输出
线程: main  ← 在主线程中执行！

// thread.start() 的输出
线程: Thread-0  ← 在新线程中执行
```

### 5.2 原理分析

```java
// Thread类的源码
public class Thread implements Runnable {
    @Override
    public void run() {
        if (target != null) {
            target.run();  // 普通方法调用
        }
    }

    public synchronized void start() {
        // 1. 检查状态（只能启动一次）
        if (threadStatus != 0)
            throw new IllegalThreadStateException();

        // 2. 加入线程组
        group.add(this);

        // 3. 调用native方法，创建操作系统线程
        boolean started = false;
        try {
            start0();  // ← JNI调用
            started = true;
        } finally {
            // ...
        }
    }

    private native void start0();  // 本地方法
}
```

**区别总结**：

| 维度 | run() | start() |
|------|-------|---------|
| **执行线程** | 当前线程 | 新线程 |
| **是否创建线程** | 否 | 是 |
| **能否多次调用** | 可以 | 不可以（抛异常） |
| **方法类型** | 普通方法 | native方法 |

### 5.3 验证代码

```java
public class StartVsRunDemo {
    public static void main(String[] args) {
        Thread thread = new Thread(() -> {
            System.out.println("执行线程: " + Thread.currentThread().getName());
            System.out.println("是否是主线程: " +
                (Thread.currentThread() == Thread.currentThread().getThreadGroup().getParent()));
        });

        System.out.println("=== 调用run() ===");
        thread.run();  // 在main线程中执行

        System.out.println("\n=== 调用start() ===");
        thread = new Thread(() -> {
            System.out.println("执行线程: " + Thread.currentThread().getName());
        });
        thread.start();  // 在新线程中执行
    }
}
```

---

## 六、Lambda表达式简化

### 6.1 传统写法 vs Lambda

```java
// ❌ 传统写法：啰嗦
Thread thread1 = new Thread(new Runnable() {
    @Override
    public void run() {
        System.out.println("传统写法");
    }
});

// ✅ Lambda简化
Thread thread2 = new Thread(() -> {
    System.out.println("Lambda写法");
});

// ✅ 更简洁（单行）
Thread thread3 = new Thread(() -> System.out.println("单行Lambda"));
```

### 6.2 线程池 + Lambda

```java
ExecutorService executor = Executors.newFixedThreadPool(5);

// 提交10个任务
for (int i = 0; i < 10; i++) {
    final int taskId = i;
    executor.submit(() -> {
        System.out.println("任务" + taskId + " 在 " +
            Thread.currentThread().getName() + " 执行");
    });
}

executor.shutdown();
```

---

## 七、守护线程 vs 用户线程

### 7.1 基本概念

**用户线程（User Thread）**：
- JVM等待所有用户线程结束才退出
- 默认创建的都是用户线程

**守护线程（Daemon Thread）**：
- JVM不等待守护线程结束
- 所有用户线程结束后，JVM立即退出（即使守护线程还在运行）

### 7.2 实例演示

```java
public class DaemonThreadDemo {
    public static void main(String[] args) throws Exception {
        // 用户线程
        Thread userThread = new Thread(() -> {
            for (int i = 0; i < 3; i++) {
                System.out.println("用户线程执行: " + i);
                try { Thread.sleep(1000); } catch (InterruptedException e) {}
            }
        });

        // 守护线程
        Thread daemonThread = new Thread(() -> {
            for (int i = 0; i < 100; i++) {  // 循环100次
                System.out.println("守护线程执行: " + i);
                try { Thread.sleep(1000); } catch (InterruptedException e) {}
            }
        });
        daemonThread.setDaemon(true);  // ← 设置为守护线程

        userThread.start();
        daemonThread.start();

        System.out.println("主线程结束");
    }
}
```

**输出**：
```
主线程结束
用户线程执行: 0
守护线程执行: 0
用户线程执行: 1
守护线程执行: 1
用户线程执行: 2
守护线程执行: 2
← 用户线程结束后，JVM立即退出，守护线程被强制终止
```

### 7.3 典型应用

**守护线程的应用场景**：
- GC线程（垃圾回收）
- 监控线程
- 心跳检测线程

```java
// JVM的GC线程就是守护线程
Thread gcThread = new Thread(() -> {
    while (true) {
        // 垃圾回收
    }
});
gcThread.setDaemon(true);
```

---

## 八、线程命名最佳实践

### 8.1 为什么要命名线程？

**问题场景**：生产环境线程dump

```bash
$ jstack 12345

"pool-1-thread-5" #45 prio=5 os_prio=0 RUNNABLE  ← 无法识别是什么线程
"pool-1-thread-8" #48 prio=5 os_prio=0 BLOCKED
"pool-2-thread-3" #52 prio=5 os_prio=0 WAITING
```

**解决**：给线程起有意义的名字

```bash
"OrderService-Worker-5" #45 RUNNABLE  ← 一眼看出是订单服务的工作线程
"PaymentService-Worker-3" #52 BLOCKED
"DB-ConnectionPool-8" #48 WAITING
```

### 8.2 命名方式

```java
// 方式1：构造方法传入
Thread thread = new Thread(() -> {
    // 任务
}, "MyThread-1");

// 方式2：setName方法
Thread thread = new Thread(() -> {
    // 任务
});
thread.setName("MyThread-2");

// 方式3：自定义ThreadFactory（线程池）
ThreadFactory factory = new ThreadFactory() {
    private AtomicInteger counter = new AtomicInteger(1);

    @Override
    public Thread newThread(Runnable r) {
        Thread thread = new Thread(r);
        thread.setName("OrderPool-" + counter.getAndIncrement());
        return thread;
    }
};

ExecutorService executor = new ThreadPoolExecutor(
    5, 10, 60L, TimeUnit.SECONDS,
    new ArrayBlockingQueue<>(100),
    factory  // ← 使用自定义ThreadFactory
);
```

---

## 九、总结

### 9.1 4种方式对比

| 方式 | 优点 | 缺点 | 推荐场景 |
|------|------|------|----------|
| **继承Thread** | 简单直观 | 单继承限制，耦合度高 | 学习演示 |
| **实现Runnable** | 解耦，可复用 | 无返回值 | 简单任务 |
| **实现Callable** | 有返回值，可抛异常 | 需要FutureTask包装 | 需要返回结果 |
| **线程池** | 线程复用，资源可控 | 配置复杂 | 生产环境（推荐） |

### 9.2 最佳实践

1. **优先使用线程池**
   ```java
   // ✅ 推荐
   ExecutorService executor = ...;
   executor.submit(task);
   ```

2. **避免直接new Thread**
   ```java
   // ❌ 不推荐
   new Thread(() -> {}).start();
   ```

3. **自定义ThreadPoolExecutor**
   ```java
   // ✅ 明确参数，避免风险
   new ThreadPoolExecutor(5, 10, ...);
   ```

4. **给线程起有意义的名字**
   ```java
   // ✅ 便于排查问题
   thread.setName("OrderService-Worker");
   ```

5. **使用Lambda简化代码**
   ```java
   // ✅ 简洁
   executor.submit(() -> doWork());
   ```

### 9.3 关键要点

- **start() vs run()**：start()创建新线程，run()是普通方法调用
- **Runnable vs Callable**：Callable可以返回结果和抛异常
- **线程池是生产环境的标准做法**：避免频繁创建线程
- **守护线程**：JVM不等待守护线程结束
- **线程命名**：便于问题排查

### 9.4 思考题

1. 为什么推荐实现Runnable而不是继承Thread？
2. FutureTask是如何保存Callable的返回结果的？
3. 为什么不推荐使用Executors创建线程池？
4. 一个线程对象可以多次调用start()吗？

### 9.5 下一篇预告

**《线程的中断机制：优雅地停止线程》**

- 为什么Thread.stop()被废弃？
- 如何正确中断线程？
- InterruptedException应该如何处理？
- 如何优雅地停止一个正在运行的任务？

---

## 扩展阅读

- [Java Concurrency in Practice](https://jcip.net/) - Chapter 6: Task Execution
- [阿里巴巴Java开发手册](https://github.com/alibaba/p3c)
- [ThreadPoolExecutor详解](https://docs.oracle.com/javase/8/docs/api/java/util/concurrent/ThreadPoolExecutor.html)
