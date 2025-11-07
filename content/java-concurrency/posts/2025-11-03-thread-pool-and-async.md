---
title: 线程池与异步编程：从Thread到CompletableFuture的演进
date: 2025-11-03T10:00:00+08:00
draft: false
tags:
  - Java
  - 并发编程
  - 线程池
  - CompletableFuture
  - 异步编程
  - 第一性原理
categories:
  - Java生态
series:
  - Java并发编程第一性原理
weight: 4
description: 深度剖析Java线程池的设计哲学：从Thread创建成本到ThreadPoolExecutor七参数，从ForkJoinPool工作窃取到CompletableFuture组合式异步。通过性能对比和源码分析，掌握高并发系统的线程管理艺术。
---

## 引子：一个Web服务器的性能优化之路

假设你正在开发一个Web服务器，每个HTTP请求需要启动一个新线程来处理。看似简单的设计，却隐藏着严重的性能问题。

### 场景A：为每个请求创建新线程

```java
/**
 * 方案1：为每个请求创建新线程（性能差）
 */
public class ThreadPerRequestServer {
    public static void main(String[] args) throws IOException {
        ServerSocket serverSocket = new ServerSocket(8080);
        System.out.println("服务器启动，监听8080端口");

        while (true) {
            Socket socket = serverSocket.accept();

            // 为每个请求创建新线程
            new Thread(() -> {
                try {
                    handleRequest(socket);
                } catch (IOException e) {
                    e.printStackTrace();
                } finally {
                    try {
                        socket.close();
                    } catch (IOException e) {
                        e.printStackTrace();
                    }
                }
            }).start();
        }
    }

    private static void handleRequest(Socket socket) throws IOException {
        // 模拟请求处理（读取请求、业务处理、返回响应）
        InputStream in = socket.getInputStream();
        OutputStream out = socket.getOutputStream();

        // 简化处理
        byte[] buffer = new byte[1024];
        in.read(buffer);

        String response = "HTTP/1.1 200 OK\r\n\r\nHello World";
        out.write(response.getBytes());
    }
}

/*
性能测试（使用JMeter压测）：
并发数：1000
请求总数：10000

结果：
├─ 吞吐量：500 req/s
├─ 平均响应时间：2000ms
├─ CPU使用率：60%
└─ 内存使用：峰值2GB

问题分析：
1. 线程创建开销大
   ├─ 每个线程需要1MB栈空间
   ├─ 1000个线程 = 1GB内存
   └─ 线程创建/销毁耗时（ms级别）

2. 上下文切换频繁
   ├─ 1000个线程竞争CPU
   ├─ 大量时间花在线程切换
   └─ CPU利用率低

3. 系统资源耗尽
   ├─ 线程数无限制
   ├─ 可能导致OOM
   └─ 系统崩溃
*/
```

---

### 场景B：使用线程池

```java
/**
 * 方案2：使用线程池（性能好）
 */
public class ThreadPoolServer {
    // 创建固定大小的线程池
    private static final ExecutorService executor = Executors.newFixedThreadPool(100);

    public static void main(String[] args) throws IOException {
        ServerSocket serverSocket = new ServerSocket(8080);
        System.out.println("服务器启动，监听8080端口");

        while (true) {
            Socket socket = serverSocket.accept();

            // 提交任务到线程池
            executor.submit(() -> {
                try {
                    handleRequest(socket);
                } catch (IOException e) {
                    e.printStackTrace();
                } finally {
                    try {
                        socket.close();
                    } catch (IOException e) {
                        e.printStackTrace();
                    }
                }
            });
        }
    }

    private static void handleRequest(Socket socket) throws IOException {
        // 同上
        InputStream in = socket.getInputStream();
        OutputStream out = socket.getOutputStream();

        byte[] buffer = new byte[1024];
        in.read(buffer);

        String response = "HTTP/1.1 200 OK\r\n\r\nHello World";
        out.write(response.getBytes());
    }
}

/*
性能测试（同样的压测条件）：
并发数：1000
请求总数：10000

结果：
├─ 吞吐量：5000 req/s  ← 提升10倍！
├─ 平均响应时间：200ms  ← 降低10倍！
├─ CPU使用率：85%  ← 提升25%
└─ 内存使用：峰值200MB  ← 降低10倍！

优势分析：
1. 线程复用
   ├─ 100个线程处理1000个请求
   ├─ 无需频繁创建/销毁线程
   └─ 节省大量时间和内存

2. 减少上下文切换
   ├─ 线程数固定（100个）
   ├─ 上下文切换次数大幅减少
   └─ CPU利用率提升

3. 资源可控
   ├─ 线程数有上限
   ├─ 内存使用可预测
   └─ 系统稳定
*/
```

---

### 性能对比总结

| 对比维度 | 直接创建线程 | 线程池 | 提升 |
|---------|------------|-------|------|
| **吞吐量** | 500 req/s | 5000 req/s | 10倍 |
| **响应时间** | 2000ms | 200ms | 10倍 |
| **CPU使用率** | 60% | 85% | +25% |
| **内存峰值** | 2GB | 200MB | 10倍 |
| **线程数** | 1000+ | 100 | 可控 |

**核心洞察**：
```
线程池的价值 = 性能提升 × 资源节省 × 系统稳定性

为什么需要线程池？
├─ 线程创建成本高（内存、时间）
├─ 线程数无限制导致资源耗尽
├─ 频繁创建/销毁浪费资源
└─ 线程池实现线程复用和资源管理
```

本文将深入探讨线程池的设计原理和最佳实践。

---

## 一、为什么需要线程池？

### 1.1 线程创建的成本

```
线程创建的开销：

1. 内存开销
   ├─ JVM栈：默认1MB（可通过-Xss配置）
   ├─ 本地方法栈：若干KB
   ├─ 程序计数器：忽略不计
   └─ 线程对象本身：约1KB

   单个线程内存 ≈ 1MB
   1000个线程 ≈ 1GB内存

2. 时间开销
   ├─ 创建线程：0.5-1ms
   ├─ 启动线程：进入就绪状态
   ├─ 销毁线程：0.5-1ms
   └─ 线程创建+销毁 ≈ 1-2ms

3. 操作系统开销
   ├─ 内核为线程分配资源
   ├─ 线程调度
   └─ 上下文切换

示例：处理1000个请求
├─ 每个请求耗时：10ms
├─ 直接创建线程：总耗时 = 1000 × (1ms + 10ms + 1ms) = 12,000ms
└─ 线程池（100线程）：总耗时 = 100 × 10ms = 1,000ms
    性能提升：12倍
```

---

### 1.2 线程数无限制的危险

```java
/**
 * 演示：无限制创建线程导致OOM
 */
public class ThreadOOMExample {
    public static void main(String[] args) {
        int count = 0;
        try {
            while (true) {
                new Thread(() -> {
                    try {
                        Thread.sleep(1000000);  // 线程不退出
                    } catch (InterruptedException e) {
                        e.printStackTrace();
                    }
                }).start();
                count++;
                if (count % 100 == 0) {
                    System.out.println("已创建线程数：" + count);
                }
            }
        } catch (OutOfMemoryError e) {
            System.out.println("创建线程失败，总共创建了 " + count + " 个线程");
            e.printStackTrace();
        }
    }
}

/*
执行结果（JVM参数：-Xmx512m）：
已创建线程数：100
已创建线程数：200
...
已创建线程数：500
java.lang.OutOfMemoryError: unable to create new native thread

分析：
1. 每个线程占用1MB栈空间
2. 500个线程 = 500MB
3. 加上堆内存，超过JVM限制
4. 系统资源耗尽

真实案例：
某公司生产环境，因为没有限制线程数
高峰期创建了5000+线程，导致服务器宕机
*/
```

---

### 1.3 线程池的核心价值

```
线程池的三大核心价值：

1. 降低资源消耗
   ├─ 线程复用，减少创建/销毁开销
   ├─ 内存占用可控
   └─ CPU利用率提升

2. 提高响应速度
   ├─ 任务到达时，无需等待线程创建
   ├─ 线程已经ready，直接执行
   └─ 响应时间从ms级降低到μs级

3. 提高线程的可管理性
   ├─ 统一管理、监控、调优
   ├─ 防止资源耗尽
   └─ 支持拒绝策略

线程池的本质：
对象池模式（Object Pool Pattern）在线程管理中的应用
├─ 预先创建一定数量的线程
├─ 任务到达时，从池中获取线程执行
├─ 任务完成后，线程归还到池中
└─ 避免频繁创建/销毁对象
```

---

## 二、ThreadPoolExecutor详解

### 2.1 七个核心参数

```java
/**
 * ThreadPoolExecutor的完整构造函数
 */
public ThreadPoolExecutor(
    int corePoolSize,                   // 核心线程数
    int maximumPoolSize,                // 最大线程数
    long keepAliveTime,                 // 空闲线程存活时间
    TimeUnit unit,                      // 时间单位
    BlockingQueue<Runnable> workQueue,  // 任务队列
    ThreadFactory threadFactory,        // 线程工厂
    RejectedExecutionHandler handler    // 拒绝策略
) {
    // ...
}

/*
参数1：corePoolSize（核心线程数）
├─ 定义：线程池中一直存活的线程数
├─ 特点：即使空闲，也不会被回收
└─ 类比：公司的正式员工

参数2：maximumPoolSize（最大线程数）
├─ 定义：线程池允许的最大线程数
├─ 特点：包含核心线程和非核心线程
└─ 类比：正式员工 + 临时工

参数3：keepAliveTime（空闲线程存活时间）
├─ 定义：非核心线程空闲后的存活时间
├─ 特点：超过这个时间，非核心线程会被回收
└─ 类比：临时工的试用期

参数4：unit（时间单位）
├─ TimeUnit.SECONDS
├─ TimeUnit.MILLISECONDS
└─ TimeUnit.NANOSECONDS

参数5：workQueue（任务队列）
├─ ArrayBlockingQueue：有界队列
├─ LinkedBlockingQueue：无界队列（默认Integer.MAX_VALUE）
├─ SynchronousQueue：不存储元素的队列
└─ PriorityBlockingQueue：优先级队列

参数6：threadFactory（线程工厂）
├─ 定义：创建线程的工厂
├─ 作用：自定义线程名称、优先级、是否守护线程
└─ 默认：Executors.defaultThreadFactory()

参数7：handler（拒绝策略）
├─ AbortPolicy：抛出异常（默认）
├─ CallerRunsPolicy：调用者线程执行
├─ DiscardPolicy：直接丢弃
└─ DiscardOldestPolicy：丢弃最老的任务
*/
```

---

### 2.2 线程池的工作流程

```
ThreadPoolExecutor的任务提交流程：

                      提交任务
                         ↓
          ┌──────────────────────────┐
          │ 核心线程数 < corePoolSize？│
          └──────────────────────────┘
                 ↓           ↓
               是            否
                 ↓           ↓
          创建核心线程    添加到队列
          执行任务           ↓
                    ┌─────────────┐
                    │ 队列是否满？  │
                    └─────────────┘
                         ↓       ↓
                       否        是
                         ↓       ↓
                    任务入队   线程数 < maximumPoolSize？
                                ↓           ↓
                              是            否
                                ↓           ↓
                         创建非核心线程   执行拒绝策略
                         执行任务

详细流程：

步骤1：核心线程未满
├─ 当前线程数 < corePoolSize
├─ 创建新的核心线程执行任务
└─ 即使有空闲核心线程，也创建新线程

步骤2：核心线程已满，队列未满
├─ 当前线程数 >= corePoolSize
├─ 队列未满
└─ 任务添加到队列，等待执行

步骤3：队列已满，线程数未达上限
├─ 队列已满
├─ 当前线程数 < maximumPoolSize
└─ 创建非核心线程执行任务

步骤4：队列已满，线程数达到上限
├─ 队列已满
├─ 当前线程数 >= maximumPoolSize
└─ 执行拒绝策略

关键理解：
1. 核心线程优先创建
2. 队列其次
3. 非核心线程最后
4. 拒绝策略兜底
*/

/**
 * 代码演示工作流程
 */
public class ThreadPoolFlowExample {
    public static void main(String[] args) throws InterruptedException {
        ThreadPoolExecutor executor = new ThreadPoolExecutor(
            2,                              // 核心线程数：2
            5,                              // 最大线程数：5
            60, TimeUnit.SECONDS,          // 空闲线程存活60秒
            new ArrayBlockingQueue<>(3),    // 队列容量：3
            new ThreadPoolExecutor.AbortPolicy()  // 拒绝策略：抛异常
        );

        // 提交10个任务
        for (int i = 1; i <= 10; i++) {
            final int taskId = i;
            try {
                executor.submit(() -> {
                    System.out.println("任务" + taskId + "执行，线程：" +
                        Thread.currentThread().getName());
                    try {
                        Thread.sleep(2000);
                    } catch (InterruptedException e) {
                        e.printStackTrace();
                    }
                });
                System.out.println("任务" + taskId + "提交成功");
            } catch (RejectedExecutionException e) {
                System.out.println("任务" + taskId + "被拒绝");
            }
            Thread.sleep(100);  // 间隔提交
        }

        executor.shutdown();
    }
}

/*
执行结果分析：

任务1提交成功  ← 创建核心线程1
任务1执行，线程：pool-1-thread-1

任务2提交成功  ← 创建核心线程2
任务2执行，线程：pool-1-thread-2

任务3提交成功  ← 核心线程满，进入队列（队列1/3）
任务4提交成功  ← 进入队列（队列2/3）
任务5提交成功  ← 进入队列（队列3/3）

任务6提交成功  ← 队列满，创建非核心线程3
任务6执行，线程：pool-1-thread-3

任务7提交成功  ← 创建非核心线程4
任务7执行，线程：pool-1-thread-4

任务8提交成功  ← 创建非核心线程5
任务8执行，线程：pool-1-thread-5

任务9被拒绝  ← 线程数达到最大值5，队列满，执行拒绝策略
任务10被拒绝

任务执行顺序：
1, 2（核心线程） → 6, 7, 8（非核心线程） → 3, 4, 5（队列中的任务）

关键点：
1. 任务3、4、5虽然先提交，但后执行（在队列中等待）
2. 任务6、7、8后提交，但先执行（创建新线程立即执行）
3. 任务9、10被拒绝（线程数和队列都满了）
*/
```

---

### 2.3 四种拒绝策略

```java
/**
 * 四种拒绝策略演示
 */
public class RejectionPolicyExample {
    public static void main(String[] args) {
        // 策略1：AbortPolicy（默认）- 抛出异常
        testPolicy("AbortPolicy", new ThreadPoolExecutor.AbortPolicy());

        // 策略2：CallerRunsPolicy - 调用者线程执行
        testPolicy("CallerRunsPolicy", new ThreadPoolExecutor.CallerRunsPolicy());

        // 策略3：DiscardPolicy - 直接丢弃
        testPolicy("DiscardPolicy", new ThreadPoolExecutor.DiscardPolicy());

        // 策略4：DiscardOldestPolicy - 丢弃最老的任务
        testPolicy("DiscardOldestPolicy", new ThreadPoolExecutor.DiscardOldestPolicy());
    }

    private static void testPolicy(String name, RejectedExecutionHandler handler) {
        System.out.println("\n===== " + name + " =====");

        ThreadPoolExecutor executor = new ThreadPoolExecutor(
            1, 1,                           // 核心线程数和最大线程数都是1
            0, TimeUnit.SECONDS,
            new ArrayBlockingQueue<>(1),    // 队列容量1
            handler
        );

        for (int i = 1; i <= 3; i++) {
            final int taskId = i;
            try {
                executor.submit(() -> {
                    System.out.println("任务" + taskId + "执行，线程：" +
                        Thread.currentThread().getName());
                    try {
                        Thread.sleep(1000);
                    } catch (InterruptedException e) {
                        e.printStackTrace();
                    }
                });
                System.out.println("任务" + taskId + "提交成功");
            } catch (RejectedExecutionException e) {
                System.out.println("任务" + taskId + "被拒绝：" + e.getMessage());
            }
        }

        executor.shutdown();
        try {
            Thread.sleep(3000);
        } catch (InterruptedException e) {
            e.printStackTrace();
        }
    }
}

/*
执行结果：

===== AbortPolicy =====
任务1提交成功  ← 核心线程执行
任务1执行，线程：pool-1-thread-1
任务2提交成功  ← 进入队列
任务3被拒绝：Task ... rejected from ...  ← 抛出异常

优点：及时发现问题，适合关键任务
缺点：任务丢失，可能导致系统异常

---

===== CallerRunsPolicy =====
任务1提交成功  ← 核心线程执行
任务1执行，线程：pool-1-thread-1
任务2提交成功  ← 进入队列
任务3提交成功  ← 调用者线程（main）执行
任务3执行，线程：main

优点：
├─ 任务不丢失
├─ 自动降级（回退到同步执行）
└─ 提供负反馈（降低提交速度）

缺点：
├─ 调用者线程被占用
└─ 性能下降

适用场景：
不允许任务丢失，且调用者可以承受短暂阻塞

---

===== DiscardPolicy =====
任务1提交成功  ← 核心线程执行
任务1执行，线程：pool-1-thread-1
任务2提交成功  ← 进入队列
任务3提交成功  ← 静默丢弃，无异常

优点：不抛异常，系统继续运行
缺点：任务丢失，且无感知（危险！）

适用场景：
允许任务丢失，如日志、监控数据采集

---

===== DiscardOldestPolicy =====
任务1提交成功  ← 核心线程执行
任务1执行，线程：pool-1-thread-1
任务2提交成功  ← 进入队列
任务3提交成功  ← 丢弃任务2，任务3入队

执行顺序：任务1 → 任务3（任务2被丢弃）

优点：保留最新的任务
缺点：老任务丢失

适用场景：
实时性要求高，如股票行情、实时监控
*/

/**
 * 自定义拒绝策略
 */
class CustomRejectedHandler implements RejectedExecutionHandler {
    @Override
    public void rejectedExecution(Runnable r, ThreadPoolExecutor executor) {
        // 记录日志
        System.err.println("任务被拒绝：" + r.toString());

        // 保存到数据库或消息队列，后续重试
        // saveToDatabase(r);

        // 或者发送告警
        // sendAlert("线程池任务拒绝");
    }
}
```

---

### 2.4 线程池的状态转换

```
线程池的五种状态：

1. RUNNING（运行状态）
   ├─ 接受新任务
   ├─ 处理队列中的任务
   └─ 状态值：-1（负数）

2. SHUTDOWN（关闭状态）
   ├─ 不接受新任务
   ├─ 继续处理队列中的任务
   ├─ 调用shutdown()进入此状态
   └─ 状态值：0

3. STOP（停止状态）
   ├─ 不接受新任务
   ├─ 不处理队列中的任务
   ├─ 中断正在执行的任务
   ├─ 调用shutdownNow()进入此状态
   └─ 状态值：1

4. TIDYING（整理状态）
   ├─ 所有任务已终止
   ├─ 工作线程数为0
   ├─ 即将调用terminated()钩子方法
   └─ 状态值：2

5. TERMINATED（终止状态）
   ├─ terminated()钩子方法执行完毕
   ├─ 线程池彻底关闭
   └─ 状态值：3

状态转换图：

RUNNING
   ↓ shutdown()
SHUTDOWN
   ↓ 队列为空 && 工作线程为0
TIDYING
   ↓ terminated()完成
TERMINATED

或者：

RUNNING
   ↓ shutdownNow()
STOP
   ↓ 工作线程为0
TIDYING
   ↓ terminated()完成
TERMINATED

源码表示（高3位表示状态）：
private static final int RUNNING    = -1 << COUNT_BITS;  // 111...
private static final int SHUTDOWN   =  0 << COUNT_BITS;  // 000...
private static final int STOP       =  1 << COUNT_BITS;  // 001...
private static final int TIDYING    =  2 << COUNT_BITS;  // 010...
private static final int TERMINATED =  3 << COUNT_BITS;  // 011...
*/

/**
 * 线程池状态查询示例
 */
public class ThreadPoolStateExample {
    public static void main(String[] args) throws InterruptedException {
        ThreadPoolExecutor executor = new ThreadPoolExecutor(
            2, 5, 60, TimeUnit.SECONDS,
            new LinkedBlockingQueue<>(10)
        );

        System.out.println("初始状态：RUNNING");
        printState(executor);

        // 提交任务
        for (int i = 0; i < 5; i++) {
            executor.submit(() -> {
                try {
                    Thread.sleep(1000);
                } catch (InterruptedException e) {
                    e.printStackTrace();
                }
            });
        }

        Thread.sleep(500);
        System.out.println("\n执行任务中");
        printState(executor);

        // 优雅关闭
        executor.shutdown();
        System.out.println("\n调用shutdown()后：SHUTDOWN");
        printState(executor);

        // 等待终止
        executor.awaitTermination(10, TimeUnit.SECONDS);
        System.out.println("\n所有任务完成后：TERMINATED");
        printState(executor);
    }

    private static void printState(ThreadPoolExecutor executor) {
        System.out.println("  isShutdown: " + executor.isShutdown());
        System.out.println("  isTerminating: " + executor.isTerminating());
        System.out.println("  isTerminated: " + executor.isTerminated());
        System.out.println("  活跃线程数: " + executor.getActiveCount());
        System.out.println("  队列任务数: " + executor.getQueue().size());
    }
}
```

---

## 三、线程池的选择与配置

### 3.1 CPU密集型 vs IO密集型

```java
/**
 * 如何确定线程池大小？
 */
public class ThreadPoolSizingExample {
    /*
    理论公式：

    1. CPU密集型任务（计算密集）
       线程数 = CPU核心数 + 1

       原因：
       ├─ CPU密集型任务，线程主要消耗CPU
       ├─ 线程数 > CPU核心数，会导致频繁上下文切换
       └─ +1 是为了在某个线程阻塞时，有备用线程

       示例：图像处理、加密解密、数据分析

    2. IO密集型任务（IO等待多）
       线程数 = CPU核心数 × (1 + IO等待时间 / CPU执行时间)

       或者简化为：
       线程数 = CPU核心数 × 2（经验值）

       原因：
       ├─ IO密集型任务，大部分时间在等待IO
       ├─ 增加线程数，提高CPU利用率
       └─ 线程在等待IO时，CPU可以执行其他线程

       示例：文件读写、数据库查询、网络请求

    3. 混合型任务
       线程数 = CPU核心数 × (1 + 等待时间 / 执行时间)

       等待时间 = IO时间 + 等待锁时间
       执行时间 = CPU执行时间

    实际应用：需要根据压测结果调整
    */

    public static void main(String[] args) throws InterruptedException {
        int cpuCores = Runtime.getRuntime().availableProcessors();
        System.out.println("CPU核心数：" + cpuCores);

        // CPU密集型任务示例
        testCpuIntensive(cpuCores + 1);

        Thread.sleep(2000);

        // IO密集型任务示例
        testIoIntensive(cpuCores * 2);
    }

    // CPU密集型任务：计算斐波那契数列
    private static void testCpuIntensive(int poolSize) throws InterruptedException {
        System.out.println("\n===== CPU密集型任务 =====");
        System.out.println("线程池大小：" + poolSize);

        ThreadPoolExecutor executor = new ThreadPoolExecutor(
            poolSize, poolSize,
            0, TimeUnit.SECONDS,
            new LinkedBlockingQueue<>()
        );

        long start = System.currentTimeMillis();

        for (int i = 0; i < 100; i++) {
            executor.submit(() -> {
                // CPU密集计算
                fibonacci(40);
            });
        }

        executor.shutdown();
        executor.awaitTermination(1, TimeUnit.MINUTES);

        long end = System.currentTimeMillis();
        System.out.println("总耗时：" + (end - start) + "ms");
    }

    // IO密集型任务：模拟数据库查询
    private static void testIoIntensive(int poolSize) throws InterruptedException {
        System.out.println("\n===== IO密集型任务 =====");
        System.out.println("线程池大小：" + poolSize);

        ThreadPoolExecutor executor = new ThreadPoolExecutor(
            poolSize, poolSize,
            0, TimeUnit.SECONDS,
            new LinkedBlockingQueue<>()
        );

        long start = System.currentTimeMillis();

        for (int i = 0; i < 100; i++) {
            executor.submit(() -> {
                try {
                    // 模拟IO等待（数据库查询、网络请求）
                    Thread.sleep(100);
                } catch (InterruptedException e) {
                    e.printStackTrace();
                }
            });
        }

        executor.shutdown();
        executor.awaitTermination(1, TimeUnit.MINUTES);

        long end = System.currentTimeMillis();
        System.out.println("总耗时：" + (end - start) + "ms");
    }

    private static long fibonacci(int n) {
        if (n <= 1) return n;
        return fibonacci(n - 1) + fibonacci(n - 2);
    }
}

/*
执行结果（4核CPU）：

===== CPU密集型任务 =====
线程池大小：5（CPU核心数 + 1）
总耗时：25000ms

如果设置线程数为20（过大）：
总耗时：28000ms（更慢！）
原因：频繁上下文切换

---

===== IO密集型任务 =====
线程池大小：8（CPU核心数 × 2）
总耗时：1250ms

如果设置线程数为4（过小）：
总耗时：2500ms（慢2倍）
原因：CPU空闲时间多

最佳实践：
1. 先用公式估算
2. 压测验证
3. 监控调优
*/
```

---

### 3.2 线程池监控与调优

```java
/**
 * 线程池监控示例
 */
public class ThreadPoolMonitorExample {
    public static void main(String[] args) throws InterruptedException {
        // 创建可监控的线程池
        ThreadPoolExecutor executor = new ThreadPoolExecutor(
            5, 10,
            60, TimeUnit.SECONDS,
            new ArrayBlockingQueue<>(20),
            new ThreadFactory() {
                private AtomicInteger count = new AtomicInteger(0);
                @Override
                public Thread newThread(Runnable r) {
                    Thread thread = new Thread(r);
                    thread.setName("MyPool-" + count.incrementAndGet());
                    return thread;
                }
            },
            new ThreadPoolExecutor.CallerRunsPolicy()
        );

        // 启动监控线程
        startMonitor(executor);

        // 提交任务
        for (int i = 0; i < 100; i++) {
            final int taskId = i;
            executor.submit(() -> {
                System.out.println("任务" + taskId + "执行");
                try {
                    Thread.sleep(1000);
                } catch (InterruptedException e) {
                    e.printStackTrace();
                }
            });
            Thread.sleep(50);
        }

        executor.shutdown();
        executor.awaitTermination(1, TimeUnit.MINUTES);
    }

    private static void startMonitor(ThreadPoolExecutor executor) {
        ScheduledExecutorService monitor = Executors.newSingleThreadScheduledExecutor();
        monitor.scheduleAtFixedRate(() -> {
            System.out.println("=============== 线程池监控 ===============");
            System.out.println("核心线程数：" + executor.getCorePoolSize());
            System.out.println("最大线程数：" + executor.getMaximumPoolSize());
            System.out.println("当前线程数：" + executor.getPoolSize());
            System.out.println("活跃线程数：" + executor.getActiveCount());
            System.out.println("历史最大线程数：" + executor.getLargestPoolSize());
            System.out.println("队列任务数：" + executor.getQueue().size());
            System.out.println("已完成任务数：" + executor.getCompletedTaskCount());
            System.out.println("总任务数：" + executor.getTaskCount());
            System.out.println("========================================\n");
        }, 0, 2, TimeUnit.SECONDS);
    }
}

/*
监控指标：

1. 核心指标
   ├─ getPoolSize()：当前线程数
   ├─ getActiveCount()：活跃线程数
   ├─ getQueue().size()：队列任务数
   └─ getCompletedTaskCount()：已完成任务数

2. 健康指标
   ├─ 活跃线程数 / 最大线程数：利用率
   ├─ 队列任务数 / 队列容量：队列使用率
   └─ 拒绝任务数：是否需要扩容

3. 性能指标
   ├─ 任务平均执行时间
   ├─ 任务平均等待时间
   └─ 吞吐量（QPS）

调优建议：

问题1：线程数经常达到最大值
├─ 分析：任务太多或任务执行太慢
├─ 解决：增加maximumPoolSize或优化任务逻辑
└─ 监控：持续观察CPU和内存

问题2：队列经常满
├─ 分析：任务提交速度 > 任务处理速度
├─ 解决：增加线程数或增加队列容量
└─ 注意：无界队列可能导致OOM

问题3：线程数经常低于核心线程数
├─ 分析：任务太少
├─ 解决：降低corePoolSize，节省资源
└─ 或者：使用allowCoreThreadTimeOut()

问题4：拒绝任务频繁
├─ 分析：系统过载
├─ 解决：
   ├─ 增加线程数和队列容量
   ├─ 限流（如令牌桶）
   └─ 降级（CallerRunsPolicy）
*/
```

---

### 3.3 Executors工厂方法的陷阱

```java
/**
 * Executors工厂方法的问题
 */
public class ExecutorsTraps {
    /*
    Executors提供了几个便捷的工厂方法：
    1. newFixedThreadPool(int)
    2. newSingleThreadExecutor()
    3. newCachedThreadPool()
    4. newScheduledThreadPool(int)

    但是，阿里巴巴Java开发手册明确禁止使用！
    */

    // 陷阱1：newFixedThreadPool - 无界队列导致OOM
    public static void trap1() {
        ExecutorService executor = Executors.newFixedThreadPool(10);

        /*
        等价于：
        new ThreadPoolExecutor(
            10, 10,
            0, TimeUnit.MILLISECONDS,
            new LinkedBlockingQueue<Runnable>()  ← 无界队列！
        );

        问题：
        ├─ LinkedBlockingQueue默认容量Integer.MAX_VALUE
        ├─ 任务堆积时，队列无限增长
        └─ 可能导致OOM

        真实案例：
        某公司的任务处理系统，使用newFixedThreadPool
        高峰期任务堆积到100万+，内存占用20GB
        最终OOM，系统崩溃
        */
    }

    // 陷阱2：newSingleThreadExecutor - 同样是无界队列
    public static void trap2() {
        ExecutorService executor = Executors.newSingleThreadExecutor();

        /*
        等价于：
        new ThreadPoolExecutor(
            1, 1,
            0, TimeUnit.MILLISECONDS,
            new LinkedBlockingQueue<Runnable>()  ← 无界队列！
        );

        问题：与newFixedThreadPool相同
        */
    }

    // 陷阱3：newCachedThreadPool - 无限线程导致OOM
    public static void trap3() {
        ExecutorService executor = Executors.newCachedThreadPool();

        /*
        等价于：
        new ThreadPoolExecutor(
            0, Integer.MAX_VALUE,  ← 最大线程数无限！
            60, TimeUnit.SECONDS,
            new SynchronousQueue<Runnable>()
        );

        问题：
        ├─ maximumPoolSize = Integer.MAX_VALUE
        ├─ 任务到达时立即创建新线程
        └─ 可能创建大量线程，导致OOM

        真实案例：
        某公司的爬虫系统，使用newCachedThreadPool
        突发流量导致创建5000+线程
        服务器卡死，最终重启
        */
    }

    // 正确做法：自定义ThreadPoolExecutor
    public static void correct() {
        ThreadPoolExecutor executor = new ThreadPoolExecutor(
            10,                             // 核心线程数
            20,                             // 最大线程数（有上限）
            60, TimeUnit.SECONDS,          // 空闲线程存活时间
            new ArrayBlockingQueue<>(100),  // 有界队列！
            new ThreadFactory() {
                private AtomicInteger count = new AtomicInteger(0);
                @Override
                public Thread newThread(Runnable r) {
                    Thread thread = new Thread(r);
                    thread.setName("CustomPool-" + count.incrementAndGet());
                    thread.setUncaughtExceptionHandler((t, e) -> {
                        System.err.println("线程" + t.getName() + "异常：" + e.getMessage());
                    });
                    return thread;
                }
            },
            new ThreadPoolExecutor.CallerRunsPolicy()  // 拒绝策略
        );

        /*
        优势：
        1. 队列有界，避免OOM
        2. 线程数有上限，避免无限创建
        3. 自定义ThreadFactory，便于监控和调试
        4. 明确拒绝策略，避免任务丢失
        */
    }
}
```

---

## 四、ForkJoinPool与工作窃取算法

### 4.1 分治算法思想

```java
/**
 * ForkJoinPool：适用于分治算法的线程池
 */
public class ForkJoinPoolExample {
    /*
    分治算法（Divide and Conquer）：
    1. 分解（Fork）：将大任务分解为小任务
    2. 解决（Compute）：并行执行小任务
    3. 合并（Join）：合并小任务的结果

    示例：计算1到1亿的和
    ├─ 传统方式：顺序累加
    └─ 分治方式：
        ├─ 分解：[1, 1亿] → [1, 5000万] + [5000万+1, 1亿]
        ├─ 递归分解：直到任务足够小
        ├─ 并行计算：多个线程同时计算
        └─ 合并：sum1 + sum2
    */

    // 递归任务：计算数组和
    static class SumTask extends RecursiveTask<Long> {
        private static final int THRESHOLD = 10000;  // 阈值
        private long[] array;
        private int start;
        private int end;

        public SumTask(long[] array, int start, int end) {
            this.array = array;
            this.start = start;
            this.end = end;
        }

        @Override
        protected Long compute() {
            int length = end - start;

            // 任务足够小，直接计算
            if (length <= THRESHOLD) {
                long sum = 0;
                for (int i = start; i < end; i++) {
                    sum += array[i];
                }
                return sum;
            }

            // 任务较大，分解为两个子任务
            int middle = start + length / 2;

            SumTask leftTask = new SumTask(array, start, middle);
            SumTask rightTask = new SumTask(array, middle, end);

            // Fork：异步执行左任务
            leftTask.fork();

            // 当前线程执行右任务（避免创建过多线程）
            long rightResult = rightTask.compute();

            // Join：等待左任务完成
            long leftResult = leftTask.join();

            // 合并结果
            return leftResult + rightResult;
        }
    }

    public static void main(String[] args) {
        // 准备数据
        long[] array = new long[100_000_000];
        for (int i = 0; i < array.length; i++) {
            array[i] = i + 1;
        }

        // 方式1：顺序计算
        long start1 = System.currentTimeMillis();
        long sum1 = 0;
        for (long num : array) {
            sum1 += num;
        }
        long end1 = System.currentTimeMillis();
        System.out.println("顺序计算结果：" + sum1 + "，耗时：" + (end1 - start1) + "ms");

        // 方式2：ForkJoinPool并行计算
        long start2 = System.currentTimeMillis();
        ForkJoinPool pool = new ForkJoinPool();
        long sum2 = pool.invoke(new SumTask(array, 0, array.length));
        long end2 = System.currentTimeMillis();
        System.out.println("并行计算结果：" + sum2 + "，耗时：" + (end2 - start2) + "ms");

        System.out.println("性能提升：" + ((end1 - start1) * 100.0 / (end2 - start2) - 100) + "%");
    }
}

/*
执行结果（4核CPU）：
顺序计算结果：5000000050000000，耗时：156ms
并行计算结果：5000000050000000，耗时：45ms
性能提升：247%

RecursiveTask vs RecursiveAction：
├─ RecursiveTask<V>：有返回值
└─ RecursiveAction：无返回值

ForkJoinTask的生命周期：
1. NEW：初始状态
2. COMPLETING：计算中
3. NORMAL：正常完成
4. EXCEPTIONAL：异常完成
5. CANCELLED：已取消

适用场景：
├─ ✅ CPU密集型任务
├─ ✅ 可分解的递归任务
├─ ✅ 大数据量计算
└─ ❌ IO密集型任务（不适合）
*/
```

---

### 4.2 工作窃取算法

```
工作窃取（Work-Stealing）算法：

传统线程池：
┌─────────────────────┐
│   任务队列（共享）    │
│  ┌───┬───┬───┬───┐  │
│  │ T1│ T2│ T3│ T4│  │
│  └───┴───┴───┴───┘  │
└─────────────────────┘
   ↓   ↓   ↓   ↓
线程1 线程2 线程3 线程4

问题：
├─ 所有线程竞争同一个队列
├─ 锁竞争激烈
└─ 性能瓶颈

ForkJoinPool（工作窃取）：
线程1有自己的队列：[T1, T2, T3]
线程2有自己的队列：[T4, T5]
线程3有自己的队列：[T6, T7, T8, T9]
线程4有自己的队列：[]  ← 空闲

工作窃取：
├─ 线程4发现自己的队列为空
├─ 从线程3的队列尾部"窃取"任务T9
└─ 减少空闲，提高CPU利用率

为什么从队列尾部窃取？
├─ 线程3从队列头部取任务
├─ 线程4从队列尾部窃取
└─ 减少冲突（双端队列）

核心数据结构：
每个线程都有一个双端队列（Deque）
├─ 自己从队列头部取任务（LIFO）
├─ 其他线程从队列尾部窃取（FIFO）
└─ 使用CAS操作，减少锁竞争

优势：
1. 减少线程间竞争
2. 提高CPU利用率
3. 自动负载均衡

适用场景：
├─ 任务执行时间差异大
├─ 任务会产生子任务
└─ 分治算法
*/

/**
 * ForkJoinPool的参数
 */
public class ForkJoinPoolConfig {
    public static void main(String[] args) {
        // 方式1：使用默认的ForkJoinPool（推荐）
        ForkJoinPool commonPool = ForkJoinPool.commonPool();
        System.out.println("默认并行度：" + commonPool.getParallelism());
        // 并行度 = CPU核心数 - 1

        // 方式2：自定义ForkJoinPool
        ForkJoinPool customPool = new ForkJoinPool(
            8,                          // 并行度
            ForkJoinPool.defaultForkJoinWorkerThreadFactory,
            null,                       // 异常处理器
            false                       // 非异步模式
        );

        // 方式3：通过系统属性设置默认并行度
        // System.setProperty("java.util.concurrent.ForkJoinPool.common.parallelism", "8");

        /*
        参数说明：

        1. parallelism（并行度）
           ├─ 定义：活跃线程的目标数量
           ├─ 默认：CPU核心数 - 1
           └─ 注意：不是最大线程数

        2. ForkJoinWorkerThreadFactory
           ├─ 用于创建工作线程
           └─ 可自定义线程名称、优先级

        3. UncaughtExceptionHandler
           ├─ 处理未捕获的异常
           └─ 默认打印到System.err

        4. asyncMode
           ├─ false：LIFO（后进先出，适合递归）
           └─ true：FIFO（先进先出，适合事件驱动）
        */
    }
}
```

---

### 4.3 并行流的底层实现

```java
/**
 * Java 8并行流的底层是ForkJoinPool
 */
public class ParallelStreamExample {
    public static void main(String[] args) {
        List<Integer> list = IntStream.rangeClosed(1, 100_000_000)
            .boxed()
            .collect(Collectors.toList());

        // 方式1：顺序流
        long start1 = System.currentTimeMillis();
        long sum1 = list.stream()
            .mapToLong(Integer::longValue)
            .sum();
        long end1 = System.currentTimeMillis();
        System.out.println("顺序流：" + sum1 + "，耗时：" + (end1 - start1) + "ms");

        // 方式2：并行流（底层使用ForkJoinPool.commonPool()）
        long start2 = System.currentTimeMillis();
        long sum2 = list.parallelStream()  // 并行流
            .mapToLong(Integer::longValue)
            .sum();
        long end2 = System.currentTimeMillis();
        System.out.println("并行流：" + sum2 + "，耗时：" + (end2 - start2) + "ms");

        System.out.println("性能提升：" + ((end1 - start1) * 100.0 / (end2 - start2) - 100) + "%");

        // 查看并行流使用的线程池
        list.parallelStream().forEach(i -> {
            if (i == 1) {
                System.out.println("并行流线程：" + Thread.currentThread().getName());
            }
        });
    }
}

/*
执行结果：
顺序流：5000000050000000，耗时：523ms
并行流：5000000050000000，耗时：156ms
性能提升：235%
并行流线程：ForkJoinPool.commonPool-worker-1

注意事项：

1. 并行流并非总是更快
   ├─ 数据量小：并行开销 > 收益
   ├─ 任务简单：并行开销 > 收益
   └─ IO操作：并行可能导致资源竞争

2. 何时使用并行流？
   ├─ ✅ 数据量大（百万级以上）
   ├─ ✅ CPU密集型任务
   ├─ ✅ 任务独立（无共享状态）
   └─ ❌ IO密集型任务

3. 并行流的陷阱
   ├─ 共享可变状态导致线程安全问题
   ├─ 使用线程本地变量（ThreadLocal）失效
   └─ 所有并行流共享ForkJoinPool.commonPool()

4. 自定义并行流的线程池
*/

// 自定义并行流的线程池
public class CustomParallelStream {
    public static void main(String[] args) throws InterruptedException, ExecutionException {
        List<Integer> list = IntStream.rangeClosed(1, 100).boxed().collect(Collectors.toList());

        // 创建自定义ForkJoinPool
        ForkJoinPool customPool = new ForkJoinPool(4);

        // 在自定义线程池中执行并行流
        Long sum = customPool.submit(() ->
            list.parallelStream()
                .peek(i -> System.out.println("线程：" + Thread.currentThread().getName()))
                .mapToLong(Integer::longValue)
                .sum()
        ).get();

        System.out.println("结果：" + sum);
        customPool.shutdown();
    }
}
```

---

## 五、CompletableFuture异步编程

### 5.1 Future的局限性

```java
/**
 * Future的问题
 */
public class FutureLimitations {
    public static void main(String[] args) throws ExecutionException, InterruptedException {
        ExecutorService executor = Executors.newFixedThreadPool(10);

        // 提交异步任务
        Future<String> future = executor.submit(() -> {
            Thread.sleep(1000);
            return "Hello";
        });

        /*
        Future的局限性：

        1. 无法链式调用
           想要在任务完成后继续处理结果？
           ├─ 必须调用get()阻塞等待
           └─ 无法注册回调函数

        2. 无法组合多个Future
           想要合并两个异步任务的结果？
           ├─ 必须分别get()
           └─ 无法并行等待

        3. 无法处理异常
           任务抛出异常？
           ├─ get()会抛出ExecutionException
           └─ 无法优雅处理异常

        4. get()是阻塞的
           ├─ 调用get()会阻塞当前线程
           └─ 无法实现真正的异步
        */

        // 问题演示：无法链式调用
        String result = future.get();  // 阻塞等待
        String upperCase = result.toUpperCase();  // 同步处理
        System.out.println(upperCase);

        // 想要的效果（链式调用）：
        // future
        //     .thenApply(String::toUpperCase)  // Future不支持！
        //     .thenAccept(System.out::println);

        executor.shutdown();
    }
}
```

---

### 5.2 CompletableFuture的优势

```java
/**
 * CompletableFuture：Java 8引入的强大异步编程工具
 */
public class CompletableFutureExample {
    public static void main(String[] args) throws ExecutionException, InterruptedException {
        // 示例1：创建CompletableFuture
        CompletableFuture<String> future1 = CompletableFuture.supplyAsync(() -> {
            System.out.println("任务1执行，线程：" + Thread.currentThread().getName());
            sleep(1000);
            return "Hello";
        });

        // 示例2：链式调用
        CompletableFuture<String> future2 = future1
            .thenApply(s -> {
                System.out.println("thenApply执行，线程：" + Thread.currentThread().getName());
                return s + " World";
            })
            .thenApply(String::toUpperCase);

        System.out.println("结果：" + future2.get());

        /*
        CompletableFuture vs Future：

        | 特性 | Future | CompletableFuture |
        |-----|--------|-------------------|
        | 链式调用 | ❌ | ✅ thenApply/thenAccept |
        | 组合多个 | ❌ | ✅ thenCombine/allOf |
        | 异常处理 | ❌ | ✅ exceptionally/handle |
        | 非阻塞 | ❌ get()阻塞 | ✅ thenAccept回调 |
        | 手动完成 | ❌ | ✅ complete() |

        CompletableFuture的优势：
        1. 支持链式调用（函数式编程）
        2. 支持组合多个异步任务
        3. 支持优雅的异常处理
        4. 支持非阻塞回调
        5. 可以手动完成任务
        */
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

---

### 5.3 CompletableFuture的常用方法

```java
/**
 * CompletableFuture API详解
 */
public class CompletableFutureAPI {
    /*
    一、创建CompletableFuture

    1. supplyAsync：有返回值
       CompletableFuture.supplyAsync(() -> "result")

    2. runAsync：无返回值
       CompletableFuture.runAsync(() -> System.out.println("task"))

    3. completedFuture：已完成的Future
       CompletableFuture.completedFuture("value")

    二、转换（thenApply系列）

    1. thenApply：转换结果（Function）
       future.thenApply(s -> s.toUpperCase())

    2. thenApplyAsync：异步转换
       future.thenApplyAsync(s -> s.toUpperCase())

    3. thenAccept：消费结果（Consumer）
       future.thenAccept(System.out::println)

    4. thenRun：不关心结果（Runnable）
       future.thenRun(() -> System.out.println("done"))

    三、组合（thenCompose/thenCombine）

    1. thenCompose：链式依赖（flatMap）
       future1.thenCompose(s -> future2)

    2. thenCombine：组合两个Future
       future1.thenCombine(future2, (s1, s2) -> s1 + s2)

    3. allOf：等待所有Future完成
       CompletableFuture.allOf(future1, future2, future3)

    4. anyOf：等待任意Future完成
       CompletableFuture.anyOf(future1, future2, future3)

    四、异常处理

    1. exceptionally：处理异常
       future.exceptionally(ex -> "default")

    2. handle：处理结果或异常
       future.handle((result, ex) -> ...)

    3. whenComplete：完成时回调
       future.whenComplete((result, ex) -> ...)
    */

    public static void main(String[] args) throws ExecutionException, InterruptedException {
        // 示例1：thenApply链式调用
        example1();

        Thread.sleep(1000);

        // 示例2：thenCompose依赖调用
        example2();

        Thread.sleep(1000);

        // 示例3：thenCombine组合调用
        example3();

        Thread.sleep(1000);

        // 示例4：allOf并行等待
        example4();

        Thread.sleep(1000);

        // 示例5：异常处理
        example5();
    }

    // 示例1：thenApply链式调用
    private static void example1() throws ExecutionException, InterruptedException {
        System.out.println("===== thenApply链式调用 =====");

        String result = CompletableFuture.supplyAsync(() -> "hello")
            .thenApply(s -> s + " world")
            .thenApply(String::toUpperCase)
            .thenApply(s -> s + "!")
            .get();

        System.out.println("结果：" + result);
        // 输出：HELLO WORLD!
    }

    // 示例2：thenCompose依赖调用
    private static void example2() throws ExecutionException, InterruptedException {
        System.out.println("\n===== thenCompose依赖调用 =====");

        // 场景：先查询用户ID，再根据ID查询用户详情
        CompletableFuture<String> userIdFuture = CompletableFuture.supplyAsync(() -> {
            System.out.println("查询用户ID");
            sleep(500);
            return "user123";
        });

        CompletableFuture<String> userDetailFuture = userIdFuture.thenCompose(userId ->
            CompletableFuture.supplyAsync(() -> {
                System.out.println("查询用户详情：" + userId);
                sleep(500);
                return "User{id=" + userId + ", name=张三}";
            })
        );

        System.out.println("结果：" + userDetailFuture.get());
    }

    // 示例3：thenCombine组合调用
    private static void example3() throws ExecutionException, InterruptedException {
        System.out.println("\n===== thenCombine组合调用 =====");

        // 场景：并行查询用户信息和订单信息，然后合并
        CompletableFuture<String> userFuture = CompletableFuture.supplyAsync(() -> {
            System.out.println("查询用户信息");
            sleep(500);
            return "张三";
        });

        CompletableFuture<String> orderFuture = CompletableFuture.supplyAsync(() -> {
            System.out.println("查询订单信息");
            sleep(500);
            return "订单123";
        });

        CompletableFuture<String> combinedFuture = userFuture.thenCombine(orderFuture, (user, order) -> {
            return user + "的" + order;
        });

        System.out.println("结果：" + combinedFuture.get());
    }

    // 示例4：allOf并行等待
    private static void example4() throws ExecutionException, InterruptedException {
        System.out.println("\n===== allOf并行等待 =====");

        // 场景：并行查询多个商品信息
        CompletableFuture<String> product1 = CompletableFuture.supplyAsync(() -> {
            sleep(500);
            return "商品1";
        });

        CompletableFuture<String> product2 = CompletableFuture.supplyAsync(() -> {
            sleep(600);
            return "商品2";
        });

        CompletableFuture<String> product3 = CompletableFuture.supplyAsync(() -> {
            sleep(700);
            return "商品3";
        });

        // 等待所有任务完成
        CompletableFuture<Void> allFuture = CompletableFuture.allOf(product1, product2, product3);
        allFuture.get();  // 阻塞直到所有任务完成

        // 获取所有结果
        System.out.println("结果1：" + product1.get());
        System.out.println("结果2：" + product2.get());
        System.out.println("结果3：" + product3.get());
    }

    // 示例5：异常处理
    private static void example5() throws ExecutionException, InterruptedException {
        System.out.println("\n===== 异常处理 =====");

        // exceptionally：捕获异常并返回默认值
        String result1 = CompletableFuture.supplyAsync(() -> {
            if (Math.random() > 0.5) {
                throw new RuntimeException("随机异常");
            }
            return "成功";
        }).exceptionally(ex -> {
            System.out.println("捕获异常：" + ex.getMessage());
            return "默认值";
        }).get();

        System.out.println("结果1：" + result1);

        // handle：同时处理结果和异常
        String result2 = CompletableFuture.supplyAsync(() -> {
            throw new RuntimeException("测试异常");
        }).handle((result, ex) -> {
            if (ex != null) {
                return "异常：" + ex.getMessage();
            }
            return result;
        }).get();

        System.out.println("结果2：" + result2);
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

---

### 5.4 CompletableFuture实战案例

```java
/**
 * 实战案例：电商商品详情页异步加载
 */
public class ProductDetailAsync {
    // 模拟服务
    static class ProductService {
        public String getBasicInfo(String productId) {
            sleep(500);
            return "商品基本信息";
        }

        public String getPrice(String productId) {
            sleep(300);
            return "价格：99.99";
        }

        public String getStock(String productId) {
            sleep(400);
            return "库存：100";
        }

        public String getComments(String productId) {
            sleep(600);
            return "评论：好评如潮";
        }

        public String getRecommendations(String productId) {
            sleep(700);
            return "推荐商品列表";
        }
    }

    public static void main(String[] args) throws ExecutionException, InterruptedException {
        ProductService service = new ProductService();
        String productId = "product123";

        // 方式1：同步串行加载（慢）
        long start1 = System.currentTimeMillis();
        String basicInfo = service.getBasicInfo(productId);
        String price = service.getPrice(productId);
        String stock = service.getStock(productId);
        String comments = service.getComments(productId);
        String recommendations = service.getRecommendations(productId);
        long end1 = System.currentTimeMillis();

        System.out.println("同步加载耗时：" + (end1 - start1) + "ms");
        // 总耗时 = 500 + 300 + 400 + 600 + 700 = 2500ms

        // 方式2：CompletableFuture异步并行加载（快）
        long start2 = System.currentTimeMillis();

        CompletableFuture<String> basicInfoFuture = CompletableFuture.supplyAsync(() ->
            service.getBasicInfo(productId)
        );

        CompletableFuture<String> priceFuture = CompletableFuture.supplyAsync(() ->
            service.getPrice(productId)
        );

        CompletableFuture<String> stockFuture = CompletableFuture.supplyAsync(() ->
            service.getStock(productId)
        );

        CompletableFuture<String> commentsFuture = CompletableFuture.supplyAsync(() ->
            service.getComments(productId)
        );

        CompletableFuture<String> recommendationsFuture = CompletableFuture.supplyAsync(() ->
            service.getRecommendations(productId)
        );

        // 等待所有任务完成
        CompletableFuture.allOf(
            basicInfoFuture, priceFuture, stockFuture,
            commentsFuture, recommendationsFuture
        ).get();

        long end2 = System.currentTimeMillis();

        System.out.println("\n异步加载耗时：" + (end2 - start2) + "ms");
        // 总耗时 ≈ max(500, 300, 400, 600, 700) = 700ms

        System.out.println("性能提升：" + ((end1 - start1) * 100.0 / (end2 - start2) - 100) + "%");

        // 组装结果
        String result = String.join("\n",
            basicInfoFuture.get(),
            priceFuture.get(),
            stockFuture.get(),
            commentsFuture.get(),
            recommendationsFuture.get()
        );

        System.out.println("\n商品详情：\n" + result);
    }

    private static void sleep(long millis) {
        try {
            Thread.sleep(millis);
        } catch (InterruptedException e) {
            e.printStackTrace();
        }
    }
}

/*
执行结果：
同步加载耗时：2500ms

异步加载耗时：710ms
性能提升：252%

商品详情：
商品基本信息
价格：99.99
库存：100
评论：好评如潮
推荐商品列表

关键收益：
1. 性能提升3.5倍
2. 用户体验大幅提升
3. 代码简洁优雅

最佳实践：
1. 独立的查询操作并行执行
2. 使用allOf等待所有任务完成
3. 统一异常处理
4. 自定义线程池（避免共用ForkJoinPool.commonPool()）
*/
```

---

## 六、最佳实践

### 6.1 线程池的正确关闭方式

```java
/**
 * 线程池关闭的最佳实践
 */
public class ThreadPoolShutdown {
    public static void main(String[] args) throws InterruptedException {
        ThreadPoolExecutor executor = new ThreadPoolExecutor(
            5, 10, 60, TimeUnit.SECONDS,
            new LinkedBlockingQueue<>(20)
        );

        // 提交任务
        for (int i = 0; i < 10; i++) {
            final int taskId = i;
            executor.submit(() -> {
                System.out.println("任务" + taskId + "执行");
                try {
                    Thread.sleep(1000);
                } catch (InterruptedException e) {
                    System.out.println("任务" + taskId + "被中断");
                }
            });
        }

        // 正确的关闭方式
        shutdownGracefully(executor);
    }

    /**
     * 优雅关闭线程池
     */
    private static void shutdownGracefully(ExecutorService executor) throws InterruptedException {
        System.out.println("开始关闭线程池...");

        // 步骤1：调用shutdown()，不再接受新任务
        executor.shutdown();

        try {
            // 步骤2：等待已提交的任务完成（最多等待60秒）
            if (!executor.awaitTermination(60, TimeUnit.SECONDS)) {
                System.out.println("等待超时，强制关闭");

                // 步骤3：强制关闭，中断正在执行的任务
                List<Runnable> droppedTasks = executor.shutdownNow();
                System.out.println("丢弃的任务数：" + droppedTasks.size());

                // 步骤4：再次等待（最多等待60秒）
                if (!executor.awaitTermination(60, TimeUnit.SECONDS)) {
                    System.err.println("线程池无法正常关闭");
                }
            }
        } catch (InterruptedException e) {
            // 当前线程被中断，强制关闭线程池
            executor.shutdownNow();
            Thread.currentThread().interrupt();
        }

        System.out.println("线程池已关闭");
    }

    /*
    shutdown() vs shutdownNow()：

    shutdown()：
    ├─ 不再接受新任务
    ├─ 已提交的任务继续执行
    ├─ 等待所有任务完成后关闭
    └─ 温柔的关闭方式

    shutdownNow()：
    ├─ 不再接受新任务
    ├─ 尝试中断正在执行的任务
    ├─ 返回等待队列中未执行的任务
    └─ 强制的关闭方式

    最佳实践：
    1. 优先使用shutdown()
    2. 使用awaitTermination()等待
    3. 超时后使用shutdownNow()
    4. 再次awaitTermination()
    5. 处理InterruptedException

    常见错误：
    1. ❌ 不调用shutdown()，导致JVM无法退出
    2. ❌ 只调用shutdown()，不等待任务完成
    3. ❌ 直接调用shutdownNow()，导致任务丢失
    */
}
```

---

### 6.2 避免线程池死锁

```java
/**
 * 线程池死锁问题
 */
public class ThreadPoolDeadlock {
    /*
    死锁场景：
    任务A提交到线程池，任务A内部又提交任务B到同一个线程池

    如果线程池满了，任务A占用线程等待任务B完成
    但任务B在队列中等待线程执行
    → 死锁！
    */

    public static void main(String[] args) throws ExecutionException, InterruptedException {
        // 问题演示
        deadlockExample();

        Thread.sleep(2000);

        // 解决方案
        solutionExample();
    }

    // 问题演示：会死锁
    private static void deadlockExample() throws ExecutionException, InterruptedException {
        System.out.println("===== 死锁示例 =====");

        ExecutorService executor = Executors.newFixedThreadPool(1);  // 只有1个线程

        Future<String> future = executor.submit(() -> {
            System.out.println("外层任务开始");

            // 在同一个线程池中提交新任务
            Future<String> innerFuture = executor.submit(() -> {
                System.out.println("内层任务执行");  // 永远不会执行
                return "内层结果";
            });

            try {
                // 等待内层任务完成
                String result = innerFuture.get();  // 永远阻塞！
                return "外层结果：" + result;
            } catch (Exception e) {
                return "异常";
            }
        });

        try {
            String result = future.get(2, TimeUnit.SECONDS);
            System.out.println(result);
        } catch (TimeoutException e) {
            System.out.println("超时！发生死锁");
        }

        executor.shutdownNow();
    }

    // 解决方案
    private static void solutionExample() throws ExecutionException, InterruptedException {
        System.out.println("\n===== 解决方案 =====");

        // 方案1：使用两个不同的线程池
        ExecutorService outerExecutor = Executors.newFixedThreadPool(1);
        ExecutorService innerExecutor = Executors.newFixedThreadPool(1);

        Future<String> future = outerExecutor.submit(() -> {
            System.out.println("外层任务开始");

            // 提交到不同的线程池
            Future<String> innerFuture = innerExecutor.submit(() -> {
                System.out.println("内层任务执行");
                return "内层结果";
            });

            try {
                String result = innerFuture.get();
                return "外层结果：" + result;
            } catch (Exception e) {
                return "异常";
            }
        });

        System.out.println(future.get());

        outerExecutor.shutdown();
        innerExecutor.shutdown();

        /*
        其他解决方案：

        方案2：增加线程池大小
        ├─ 确保线程池有足够的线程
        └─ 缺点：无法确定需要多少线程

        方案3：使用ForkJoinPool
        ├─ ForkJoinPool针对这种场景优化
        └─ 子任务可以窃取父任务的线程

        方案4：避免嵌套提交
        ├─ 重构代码，避免在任务中提交新任务
        └─ 最佳方案
        */
    }
}
```

---

### 6.3 线程池命名策略

```java
/**
 * 线程池命名的最佳实践
 */
public class ThreadPoolNaming {
    public static void main(String[] args) {
        // 方案1：使用自定义ThreadFactory
        ThreadFactory threadFactory = new ThreadFactory() {
            private final AtomicInteger threadNumber = new AtomicInteger(1);
            private final String namePrefix = "MyBusinessPool-";

            @Override
            public Thread newThread(Runnable r) {
                Thread thread = new Thread(r, namePrefix + threadNumber.getAndIncrement());

                // 设置为非守护线程
                thread.setDaemon(false);

                // 设置优先级
                thread.setPriority(Thread.NORM_PRIORITY);

                // 设置异常处理器
                thread.setUncaughtExceptionHandler((t, e) -> {
                    System.err.println("线程" + t.getName() + "发生异常：" + e.getMessage());
                    // 记录日志、发送告警
                });

                return thread;
            }
        };

        ThreadPoolExecutor executor = new ThreadPoolExecutor(
            5, 10, 60, TimeUnit.SECONDS,
            new LinkedBlockingQueue<>(20),
            threadFactory,  // 使用自定义ThreadFactory
            new ThreadPoolExecutor.CallerRunsPolicy()
        );

        // 提交任务
        executor.submit(() -> {
            System.out.println("任务执行，线程名：" + Thread.currentThread().getName());
        });

        executor.shutdown();

        /*
        为什么需要线程命名？

        1. 问题排查
           ├─ 线程dump时，能快速定位线程归属
           ├─ 日志中能清晰看到是哪个线程池的线程
           └─ CPU飙高时，能快速找到问题线程

        2. 监控统计
           ├─ 按线程池分组统计
           └─ 了解各线程池的负载情况

        3. 规范管理
           ├─ 强制团队统一命名规范
           └─ 避免使用默认名称（pool-1-thread-1）

        命名规范：
        ├─ 业务名称-pool-线程编号
        ├─ 如：order-pool-1, payment-pool-1
        └─ 见名知意

        常用ThreadFactory实现：
        1. Executors.defaultThreadFactory()：默认
        2. Google Guava的ThreadFactoryBuilder
        3. Spring的CustomizableThreadFactory
        4. 自定义实现（推荐）
        */
    }

    // 方案2：使用Google Guava的ThreadFactoryBuilder
    private static void guavaExample() {
        /*
        // 需要引入Guava依赖
        ThreadFactory threadFactory = new ThreadFactoryBuilder()
            .setNameFormat("MyPool-%d")
            .setDaemon(false)
            .setPriority(Thread.NORM_PRIORITY)
            .setUncaughtExceptionHandler((t, e) -> {
                System.err.println("异常：" + e.getMessage());
            })
            .build();

        ThreadPoolExecutor executor = new ThreadPoolExecutor(
            5, 10, 60, TimeUnit.SECONDS,
            new LinkedBlockingQueue<>(20),
            threadFactory
        );
        */
    }
}
```

---

## 七、总结与思考

### 7.1 线程池核心原理

```
线程池的本质：
对象池模式 + 生产者-消费者模式

核心组件：
1. 核心线程（core threads）
   └─ 常驻线程，即使空闲也不回收

2. 任务队列（work queue）
   └─ 存储等待执行的任务

3. 非核心线程（non-core threads）
   └─ 临时线程，空闲超时后回收

4. 拒绝策略（rejection handler）
   └─ 任务无法执行时的处理策略

工作流程：
任务提交 → 核心线程 → 队列 → 非核心线程 → 拒绝策略

关键参数：
corePoolSize、maximumPoolSize、keepAliveTime、workQueue、handler

性能优化：
1. 合理设置线程数（CPU密集 vs IO密集）
2. 选择合适的队列（有界 vs 无界）
3. 监控线程池状态
4. 避免死锁
```

---

### 7.2 CompletableFuture最佳实践

```
CompletableFuture的价值：
1. 链式调用，代码优雅
2. 组合多个异步任务
3. 优雅的异常处理
4. 非阻塞回调

常用API：
├─ 创建：supplyAsync、runAsync
├─ 转换：thenApply、thenAccept、thenRun
├─ 组合：thenCompose、thenCombine
├─ 等待：allOf、anyOf
└─ 异常：exceptionally、handle

适用场景：
1. 微服务聚合查询
2. 商品详情页异步加载
3. 并行计算
4. 事件驱动编程

注意事项：
1. 自定义线程池（避免共用ForkJoinPool.commonPool()）
2. 异常处理（避免静默失败）
3. 超时控制（避免无限等待）
4. 资源释放（线程池关闭）
```

---

## 八、下一篇预告

在下一篇文章《并发集合：从HashMap到ConcurrentHashMap》中，我们将深入探讨：

1. **HashMap的线程安全问题**
   - 数据丢失问题
   - 死循环问题（JDK 1.7）
   - 为什么不能用Collections.synchronizedMap？

2. **ConcurrentHashMap深度剖析**
   - JDK 1.7：分段锁（Segment）
   - JDK 1.8：CAS + synchronized
   - put操作的完整流程
   - size()方法的实现
   - 扩容机制（协助扩容）

3. **BlockingQueue家族**
   - ArrayBlockingQueue vs LinkedBlockingQueue
   - PriorityBlockingQueue（优先级队列）
   - DelayQueue（延迟队列）
   - 生产者-消费者模式实战

4. **CopyOnWriteArrayList**
   - 写时复制（COW）思想
   - 适用场景：读多写少
   - 迭代器的弱一致性

5. **其他并发集合**
   - ConcurrentLinkedQueue（无界非阻塞队列）
   - ConcurrentSkipListMap（跳表实现的有序Map）
   - 如何选择合适的并发集合？

敬请期待！

---

**本文要点回顾**：

```
为什么需要线程池？
├─ 线程创建成本高（内存1MB、时间1-2ms）
├─ 线程数无限制导致OOM
└─ 线程池实现线程复用和资源管理

ThreadPoolExecutor七参数：
├─ corePoolSize：核心线程数
├─ maximumPoolSize：最大线程数
├─ keepAliveTime：空闲线程存活时间
├─ workQueue：任务队列
├─ threadFactory：线程工厂
├─ handler：拒绝策略
└─ 工作流程：核心线程 → 队列 → 非核心线程 → 拒绝

ForkJoinPool：
├─ 分治算法（Fork-Join）
├─ 工作窃取算法（Work-Stealing）
└─ 并行流的底层实现

CompletableFuture：
├─ 链式调用：thenApply、thenAccept
├─ 组合操作：thenCompose、thenCombine
├─ 异常处理：exceptionally、handle
└─ 并行等待：allOf、anyOf

最佳实践：
├─ 合理配置线程数（CPU密集 vs IO密集）
├─ 优雅关闭线程池（shutdown + awaitTermination）
├─ 避免死锁（分离线程池）
└─ 线程命名（便于监控和排查）
```

---

**系列文章**：
1. ✅ Java并发第一性原理：为什么并发如此困难？
2. ✅ 线程安全与同步机制：从synchronized到Lock的演进
3. ✅ 并发工具类与原子操作：无锁编程的艺术
4. ✅ **线程池与异步编程：从Thread到CompletableFuture的演进**（本文）
5. ⏳ 并发集合：从HashMap到ConcurrentHashMap
6. ⏳ 并发设计模式与最佳实践

---

**参考资料**：
- 《Java并发编程实战》- Brian Goetz
- 《Java并发编程的艺术》- 方腾飞、魏鹏、程晓明
- JDK源码：java.util.concurrent包
- Doug Lea, "A Java Fork/Join Framework"

---

**关于作者**：
专注于Java技术栈的深度研究，致力于用第一性原理思维拆解复杂技术问题。本系列文章采用渐进式复杂度模型，从"为什么"出发，系统化学习Java并发编程。

如果这篇文章对你有帮助，欢迎关注本系列后续文章！
