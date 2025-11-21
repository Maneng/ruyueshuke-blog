---
title: "Java并发19：线程池核心原理 - 为什么需要线程池"
date: 2025-11-20T21:00:00+08:00
draft: false
tags: ["Java并发", "线程池", "ThreadPoolExecutor", "任务队列"]
categories: ["技术"]
description: "理解线程池的设计理念、核心参数、工作原理、拒绝策略，以及为什么生产环境必须使用线程池。"
series: ["Java并发编程从入门到精通"]
weight: 19
stage: 3
stageTitle: "Lock与并发工具篇"
---

## 为什么需要线程池？

**直接创建线程的问题**：
```java
// 每个请求创建一个线程
new Thread(() -> handleRequest()).start();
```

**三大问题**：
1. **创建/销毁开销大**：线程创建需要约1MB栈空间，耗时1ms
2. **资源无限制**：可能创建上千个线程，耗尽内存
3. **管理困难**：无法统一管理和监控

**线程池的优势**：
- ✅ 线程复用，降低开销
- ✅ 控制并发数，避免资源耗尽
- ✅ 统一管理，便于监控

---

## 核心组件

```java
public class ThreadPoolExecutor {
    // 核心参数
    int corePoolSize;       // 核心线程数
    int maximumPoolSize;    // 最大线程数
    long keepAliveTime;     // 空闲线程存活时间
    BlockingQueue<Runnable> workQueue;  // 任务队列
    RejectedExecutionHandler handler;   // 拒绝策略
}
```

---

## 工作流程

```
任务提交
    ↓
线程数 < corePoolSize?
    ├─ 是 → 创建核心线程执行
    └─ 否 → 队列未满?
            ├─ 是 → 加入队列等待
            └─ 否 → 线程数 < maximumPoolSize?
                    ├─ 是 → 创建临时线程执行
                    └─ 否 → 执行拒绝策略
```

**示例**：
```java
// corePoolSize=2, maxPoolSize=5, queue=3
// 提交7个任务：
任务1 → 创建核心线程1
任务2 → 创建核心线程2
任务3 → 加入队列[1/3]
任务4 → 加入队列[2/3]
任务5 → 加入队列[3/3]
任务6 → 创建临时线程3
任务7 → 创建临时线程4
任务8 → 拒绝（队列满且达到maxPoolSize）
```

---

## 四种拒绝策略

| 策略 | 行为 | 适用场景 |
|-----|------|---------|
| **AbortPolicy** | 抛异常（默认） | 必须处理所有任务 |
| **CallerRunsPolicy** | 调用者线程执行 | 降级策略 |
| **DiscardPolicy** | 静默丢弃 | 允许丢失任务 |
| **DiscardOldestPolicy** | 丢弃最旧任务 | 优先处理新任务 |

**实现**：
```java
// 自定义拒绝策略
RejectedExecutionHandler customHandler = (r, executor) -> {
    // 记录日志
    logger.warn("Task rejected: " + r);
    // 保存到数据库或MQ
    saveToDatabase(r);
};

ThreadPoolExecutor executor = new ThreadPoolExecutor(
    2, 5, 60L, TimeUnit.SECONDS,
    new ArrayBlockingQueue<>(3),
    customHandler  // 使用自定义策略
);
```

---

## 线程池状态

```java
private static final int RUNNING    = -1 << COUNT_BITS;  // 接受新任务
private static final int SHUTDOWN   =  0 << COUNT_BITS;  // 不接受新任务，执行完队列任务
private static final int STOP       =  1 << COUNT_BITS;  // 不接受新任务，中断所有线程
private static final int TIDYING    =  2 << COUNT_BITS;  // 所有任务终止
private static final int TERMINATED =  3 << COUNT_BITS;  // terminated()执行完毕
```

**状态转换**：
```
RUNNING → SHUTDOWN → TIDYING → TERMINATED
    ↓
RUNNING → STOP → TIDYING → TERMINATED
```

---

## 核心方法

```java
ExecutorService executor = Executors.newFixedThreadPool(10);

// 提交任务（无返回值）
executor.execute(() -> System.out.println("Task"));

// 提交任务（有返回值）
Future<Integer> future = executor.submit(() -> 42);
Integer result = future.get();

// 优雅关闭
executor.shutdown();  // 等待任务完成
executor.awaitTermination(1, TimeUnit.MINUTES);

// 立即关闭
executor.shutdownNow();  // 中断所有线程
```

---

## 最佳实践

**1. 合理设置线程数**：
```java
// CPU密集型：线程数 = CPU核心数 + 1
int cpuCount = Runtime.getRuntime().availableProcessors();
int threadCount = cpuCount + 1;

// IO密集型：线程数 = CPU核心数 * (1 + IO时间/CPU时间)
// 例如：IO时间是CPU时间的10倍
int threadCount = cpuCount * (1 + 10) = cpuCount * 11;
```

**2. 选择合适的队列**：
- `ArrayBlockingQueue`：有界，防止OOM
- `LinkedBlockingQueue`：无界，可能OOM
- `SynchronousQueue`：不存储，直接交付

**3. 监控线程池**：
```java
ThreadPoolExecutor executor = (ThreadPoolExecutor) Executors.newFixedThreadPool(10);

// 监控指标
int activeCount = executor.getActiveCount();        // 活跃线程数
long taskCount = executor.getTaskCount();           // 总任务数
long completedCount = executor.getCompletedTaskCount();  // 完成任务数
int queueSize = executor.getQueue().size();         // 队列大小
```

---

## 常见陷阱

**陷阱1：使用Executors创建线程池**
```java
// ❌ 不推荐：LinkedBlockingQueue无界，可能OOM
ExecutorService executor = Executors.newFixedThreadPool(10);

// ✅ 推荐：自定义参数
ThreadPoolExecutor executor = new ThreadPoolExecutor(
    10, 20, 60L, TimeUnit.SECONDS,
    new ArrayBlockingQueue<>(100),  // 有界队列
    new ThreadPoolExecutor.CallerRunsPolicy()
);
```

**陷阱2：忘记shutdown**
```java
// ❌ 线程池不会自动关闭
ExecutorService executor = Executors.newFixedThreadPool(10);
executor.submit(task);
// 程序不会退出

// ✅ 手动关闭
executor.shutdown();
```

---

## 总结

**核心要点**：
1. 线程池复用线程，降低开销
2. 核心参数：corePoolSize、maxPoolSize、队列、拒绝策略
3. 生产环境必须自定义参数，不用Executors

**下一篇**：ThreadPoolExecutor详解 - 深入源码分析

---

**系列文章**：
- 上一篇：[Java并发18：读写锁ReadWriteLock](/java-concurrency/posts/18-readwritelock/)
- 下一篇：[Java并发20：ThreadPoolExecutor详解](/java-concurrency/posts/20-threadpoolexecutor/) （即将发布）
