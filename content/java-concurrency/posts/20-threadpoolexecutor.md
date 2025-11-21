---
title: "Java并发20：ThreadPoolExecutor详解 - 深入线程池源码"
date: 2025-11-20T21:15:00+08:00
draft: false
tags: ["Java并发", "ThreadPoolExecutor", "线程池", "源码分析"]
categories: ["技术"]
description: "深入ThreadPoolExecutor源码，理解线程池的实现细节、核心参数的作用、任务提交与执行流程。"
series: ["Java并发编程从入门到精通"]
weight: 20
stage: 3
stageTitle: "Lock与并发工具篇"
---

## 核心参数详解

```java
public ThreadPoolExecutor(
    int corePoolSize,              // 核心线程数
    int maximumPoolSize,           // 最大线程数
    long keepAliveTime,            // 空闲线程存活时间
    TimeUnit unit,                 // 时间单位
    BlockingQueue<Runnable> workQueue,        // 任务队列
    ThreadFactory threadFactory,   // 线程工厂
    RejectedExecutionHandler handler  // 拒绝策略
) { ... }
```

### 参数说明

**corePoolSize（核心线程数）**：
- 即使空闲也不会回收
- 除非设置`allowCoreThreadTimeOut(true)`

**maximumPoolSize（最大线程数）**：
- 队列满后创建的临时线程
- 空闲超过keepAliveTime后回收

**workQueue（任务队列）**：
```java
// 1. 有界队列（推荐）
new ArrayBlockingQueue<>(100)

// 2. 无界队列（慎用）
new LinkedBlockingQueue<>()  // 可能OOM

// 3. 同步队列（不存储）
new SynchronousQueue<>()  // 直接交付给线程

// 4. 优先级队列
new PriorityBlockingQueue<>()  // 按优先级执行
```

---

## 任务提交流程

**execute() vs submit()**：
```java
// execute()：无返回值
executor.execute(() -> System.out.println("Task"));

// submit()：有返回值
Future<Integer> future = executor.submit(() -> {
    return 42;
});
Integer result = future.get();  // 阻塞等待结果
```

**源码分析**（简化）：
```java
public void execute(Runnable command) {
    int c = ctl.get();

    // 1. 线程数 < corePoolSize，创建核心线程
    if (workerCountOf(c) < corePoolSize) {
        if (addWorker(command, true))
            return;
    }

    // 2. 加入队列
    if (isRunning(c) && workQueue.offer(command)) {
        // double-check
    }

    // 3. 队列满，创建临时线程
    else if (!addWorker(command, false))
        // 4. 达到maxPoolSize，执行拒绝策略
        reject(command);
}
```

---

## 线程池配置实战

### 场景1：CPU密集型
```java
int coreCount = Runtime.getRuntime().availableProcessors();

ThreadPoolExecutor executor = new ThreadPoolExecutor(
    coreCount,              // 核心线程数 = CPU数
    coreCount * 2,          // 最大线程数
    60L, TimeUnit.SECONDS,
    new ArrayBlockingQueue<>(100),
    new ThreadPoolExecutor.AbortPolicy()
);
```

### 场景2：IO密集型
```java
int coreCount = Runtime.getRuntime().availableProcessors();

ThreadPoolExecutor executor = new ThreadPoolExecutor(
    coreCount * 2,          // 核心线程数 = CPU数 * 2
    coreCount * 10,         // 最大线程数
    60L, TimeUnit.SECONDS,
    new LinkedBlockingQueue<>(1000),  // 较大队列
    new ThreadPoolExecutor.CallerRunsPolicy()  // 降级策略
);
```

### 场景3：混合型
```java
ThreadPoolExecutor executor = new ThreadPoolExecutor(
    10,                     // 核心线程数
    50,                     // 最大线程数
    60L, TimeUnit.SECONDS,
    new ArrayBlockingQueue<>(500),
    new ThreadFactory() {
        private final AtomicInteger threadNumber = new AtomicInteger(1);

        @Override
        public Thread newThread(Runnable r) {
            Thread t = new Thread(r, "my-pool-" + threadNumber.getAndIncrement());
            t.setDaemon(false);  // 用户线程
            t.setPriority(Thread.NORM_PRIORITY);
            return t;
        }
    },
    (r, executor) -> {
        // 自定义拒绝策略
        logger.warn("Task rejected: " + r);
    }
);
```

---

## 预启动核心线程

```java
ThreadPoolExecutor executor = new ThreadPoolExecutor(...);

// 预启动一个核心线程
executor.prestartCoreThread();

// 预启动所有核心线程
executor.prestartAllCoreThreads();
```

**使用场景**：
- 系统启动时预热
- 避免首次任务延迟

---

## 动态调整参数

```java
ThreadPoolExecutor executor = new ThreadPoolExecutor(...);

// 运行时动态调整
executor.setCorePoolSize(20);
executor.setMaximumPoolSize(50);
executor.setKeepAliveTime(120, TimeUnit.SECONDS);

// 允许核心线程超时
executor.allowCoreThreadTimeOut(true);
```

---

## 监控与调优

```java
// 监控指标
ThreadPoolExecutor executor = ...;

// 线程数
int poolSize = executor.getPoolSize();           // 当前线程数
int activeCount = executor.getActiveCount();     // 活跃线程数
int largestPoolSize = executor.getLargestPoolSize();  // 历史峰值

// 任务数
long taskCount = executor.getTaskCount();        // 总任务数
long completedTaskCount = executor.getCompletedTaskCount();  // 完成数

// 队列
int queueSize = executor.getQueue().size();      // 队列大小
int remainingCapacity = executor.getQueue().remainingCapacity();  // 剩余容量

// 监控线程
new Thread(() -> {
    while (true) {
        logger.info("Pool size: " + executor.getPoolSize() +
                   ", Active: " + executor.getActiveCount() +
                   ", Queue: " + executor.getQueue().size());
        Thread.sleep(5000);
    }
}).start();
```

---

## 优雅关闭

```java
// 方式1：shutdown（推荐）
executor.shutdown();  // 不再接受新任务，等待已有任务完成

// 等待终止
if (!executor.awaitTermination(60, TimeUnit.SECONDS)) {
    executor.shutdownNow();  // 超时强制关闭
}

// 方式2：shutdownNow（立即关闭）
List<Runnable> notExecuted = executor.shutdownNow();  // 返回未执行的任务

// Spring Boot中的实现
@PreDestroy
public void destroy() {
    executor.shutdown();
    try {
        if (!executor.awaitTermination(60, TimeUnit.SECONDS)) {
            executor.shutdownNow();
        }
    } catch (InterruptedException e) {
        executor.shutdownNow();
        Thread.currentThread().interrupt();
    }
}
```

---

## 常见问题

**Q1：为什么不用Executors？**
```java
// Executors.newFixedThreadPool
public static ExecutorService newFixedThreadPool(int nThreads) {
    return new ThreadPoolExecutor(nThreads, nThreads,
        0L, TimeUnit.MILLISECONDS,
        new LinkedBlockingQueue<Runnable>());  // 无界队列，可能OOM
}

// Executors.newCachedThreadPool
public static ExecutorService newCachedThreadPool() {
    return new ThreadPoolExecutor(0, Integer.MAX_VALUE,  // 无限线程，可能OOM
        60L, TimeUnit.SECONDS,
        new SynchronousQueue<Runnable>());
}
```

**Q2：如何选择队列大小？**
```
队列大小 = 预期QPS * 平均处理时间 * 安全系数

例如：QPS=1000, 处理时间=100ms, 安全系数=2
队列大小 = 1000 * 0.1 * 2 = 200
```

**Q3：拒绝策略如何选择？**
- 核心服务：`AbortPolicy`（抛异常）
- 非核心服务：`CallerRunsPolicy`（降级）
- 日志采集：`DiscardOldestPolicy`（丢弃旧任务）

---

## 总结

**核心要点**：
1. 理解7个核心参数的作用
2. 根据场景选择合适的配置
3. 监控线程池状态
4. 优雅关闭线程池

**最佳实践**：
- 自定义参数，不用Executors
- 使用有界队列
- 设置合理的拒绝策略
- 给线程池命名，便于排查

---

**系列文章**：
- 上一篇：[Java并发19：线程池核心原理](/java-concurrency/posts/19-threadpool-principle/)
- 下一篇：[Java并发21：线程池的最佳实践](/java-concurrency/posts/21-threadpool-best-practices/) （即将发布）
