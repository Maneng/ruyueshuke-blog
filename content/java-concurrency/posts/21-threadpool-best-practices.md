---
title: "Java并发21：线程池最佳实践 - Executors陷阱与生产配置"
date: 2025-11-20T21:30:00+08:00
draft: false
tags: ["Java并发", "线程池", "最佳实践", "生产配置"]
categories: ["技术"]
description: "线程池的生产级配置、Executors的陷阱、监控方案、异常处理、优雅关闭。"
series: ["Java并发编程从入门到精通"]
weight: 21
stage: 3
stageTitle: "Lock与并发工具篇"
---

## Executors的陷阱

**阿里巴巴Java开发手册**明确规定：禁止使用Executors创建线程池。

### 三大陷阱

**1. FixedThreadPool和SingleThreadExecutor**
```java
// 源码
public static ExecutorService newFixedThreadPool(int nThreads) {
    return new ThreadPoolExecutor(nThreads, nThreads,
        0L, TimeUnit.MILLISECONDS,
        new LinkedBlockingQueue<Runnable>());  // 无界队列
}
```
**问题**：队列无界，任务堆积导致OOM

**2. CachedThreadPool**
```java
public static ExecutorService newCachedThreadPool() {
    return new ThreadPoolExecutor(0, Integer.MAX_VALUE,  // 无限线程
        60L, TimeUnit.SECONDS,
        new SynchronousQueue<Runnable>());
}
```
**问题**：线程数无限，可能创建大量线程导致OOM

**3. ScheduledThreadPool**
```java
public static ScheduledExecutorService newScheduledThreadPool(int corePoolSize) {
    return new ScheduledThreadPoolExecutor(corePoolSize);
    // 内部使用DelayedWorkQueue，无界
}
```
**问题**：队列无界，任务堆积

---

## 生产级配置模板

### 模板1：Web服务
```java
@Configuration
public class ThreadPoolConfig {

    @Bean("webExecutor")
    public ThreadPoolExecutor webExecutor() {
        int coreSize = Runtime.getRuntime().availableProcessors() * 2;

        return new ThreadPoolExecutor(
            coreSize,                   // 核心线程数
            coreSize * 4,               // 最大线程数
            60L, TimeUnit.SECONDS,      // 空闲存活时间
            new ArrayBlockingQueue<>(1000),  // 有界队列
            new NamedThreadFactory("web-pool"),
            new ThreadPoolExecutor.CallerRunsPolicy()  // 降级策略
        );
    }
}

// 自定义线程工厂
class NamedThreadFactory implements ThreadFactory {
    private final AtomicInteger threadNumber = new AtomicInteger(1);
    private final String namePrefix;

    public NamedThreadFactory(String namePrefix) {
        this.namePrefix = namePrefix;
    }

    @Override
    public Thread newThread(Runnable r) {
        Thread t = new Thread(r, namePrefix + "-" + threadNumber.getAndIncrement());
        t.setDaemon(false);
        return t;
    }
}
```

### 模板2：异步任务
```java
@Bean("asyncExecutor")
public ThreadPoolExecutor asyncExecutor() {
    return new ThreadPoolExecutor(
        10,                         // 核心线程数
        20,                         // 最大线程数
        300L, TimeUnit.SECONDS,     // 较长的空闲时间
        new LinkedBlockingQueue<>(500),  // 较大队列
        new NamedThreadFactory("async-pool"),
        (r, executor) -> {
            // 自定义拒绝策略：记录日志
            log.error("Task rejected: {}", r);
            // 可以保存到数据库或MQ
        }
    );
}
```

---

## 异常处理

**问题**：线程池中的异常不会抛出
```java
executor.submit(() -> {
    throw new RuntimeException("Error");  // 异常被吞掉
});
```

**解决方案1：使用Future**
```java
Future<?> future = executor.submit(() -> {
    // 可能抛异常的代码
});

try {
    future.get();  // 获取结果时会抛出异常
} catch (ExecutionException e) {
    log.error("Task failed", e.getCause());
}
```

**解决方案2：自定义ThreadFactory**
```java
class CustomThreadFactory implements ThreadFactory {
    @Override
    public Thread newThread(Runnable r) {
        Thread t = new Thread(r);
        t.setUncaughtExceptionHandler((thread, throwable) -> {
            log.error("Thread {} threw exception", thread.getName(), throwable);
        });
        return t;
    }
}
```

**解决方案3：包装任务**
```java
executor.submit(() -> {
    try {
        // 业务代码
    } catch (Exception e) {
        log.error("Task failed", e);
    }
});
```

---

## 监控与告警

### 1. 自定义ThreadPoolExecutor
```java
public class MonitoredThreadPoolExecutor extends ThreadPoolExecutor {

    public MonitoredThreadPoolExecutor(...) {
        super(...);
    }

    @Override
    protected void beforeExecute(Thread t, Runnable r) {
        super.beforeExecute(t, r);
        log.debug("Task {} is about to execute", r);
    }

    @Override
    protected void afterExecute(Runnable r, Throwable t) {
        super.afterExecute(r, t);
        if (t != null) {
            log.error("Task {} failed", r, t);
        }
    }

    @Override
    protected void terminated() {
        super.terminated();
        log.info("ThreadPool terminated");
    }
}
```

### 2. 定时监控
```java
@Scheduled(fixedRate = 5000)
public void monitorThreadPool() {
    int poolSize = executor.getPoolSize();
    int activeCount = executor.getActiveCount();
    int queueSize = executor.getQueue().size();
    long completedTaskCount = executor.getCompletedTaskCount();

    log.info("Pool[size={}, active={}, queue={}, completed={}]",
        poolSize, activeCount, queueSize, completedTaskCount);

    // 告警：队列积压
    if (queueSize > 800) {
        alert("ThreadPool queue size too high: " + queueSize);
    }

    // 告警：拒绝任务
    if (executor instanceof ThreadPoolExecutor) {
        long rejectedCount = getRejectedCount(executor);
        if (rejectedCount > 0) {
            alert("ThreadPool rejected tasks: " + rejectedCount);
        }
    }
}
```

### 3. Micrometer集成
```java
@Bean
public ThreadPoolExecutor monitoredExecutor(MeterRegistry registry) {
    ThreadPoolExecutor executor = new ThreadPoolExecutor(...);

    // 注册指标
    registry.gauge("threadpool.size", executor, ThreadPoolExecutor::getPoolSize);
    registry.gauge("threadpool.active", executor, ThreadPoolExecutor::getActiveCount);
    registry.gauge("threadpool.queue.size", executor, e -> e.getQueue().size());

    return executor;
}
```

---

## 优雅关闭

```java
@PreDestroy
public void shutdown() {
    log.info("Shutting down thread pool...");

    // 1. 停止接受新任务
    executor.shutdown();

    try {
        // 2. 等待已有任务完成（最多等待60秒）
        if (!executor.awaitTermination(60, TimeUnit.SECONDS)) {
            log.warn("Pool did not terminate gracefully, forcing shutdown");

            // 3. 强制关闭
            List<Runnable> droppedTasks = executor.shutdownNow();
            log.warn("Dropped {} tasks", droppedTasks.size());

            // 4. 再次等待（最多10秒）
            if (!executor.awaitTermination(10, TimeUnit.SECONDS)) {
                log.error("Pool did not terminate");
            }
        }
    } catch (InterruptedException e) {
        log.error("Shutdown interrupted", e);
        executor.shutdownNow();
        Thread.currentThread().interrupt();
    }

    log.info("Thread pool shutdown complete");
}
```

---

## 动态配置

### 使用Apollo/Nacos动态调整
```java
@Component
public class DynamicThreadPoolConfig {

    @Value("${threadpool.coreSize:10}")
    private int coreSize;

    @Value("${threadpool.maxSize:20}")
    private int maxSize;

    @Autowired
    private ThreadPoolExecutor executor;

    @ApolloConfigChangeListener
    public void onChange(ConfigChangeEvent changeEvent) {
        if (changeEvent.isChanged("threadpool.coreSize")) {
            int newCoreSize = Integer.parseInt(changeEvent.getChange("threadpool.coreSize").getNewValue());
            executor.setCorePoolSize(newCoreSize);
            log.info("CorePoolSize changed to {}", newCoreSize);
        }

        if (changeEvent.isChanged("threadpool.maxSize")) {
            int newMaxSize = Integer.parseInt(changeEvent.getChange("threadpool.maxSize").getNewValue());
            executor.setMaximumPoolSize(newMaxSize);
            log.info("MaximumPoolSize changed to {}", newMaxSize);
        }
    }
}
```

---

## 压测调优

### 性能测试脚本
```java
public class ThreadPoolBenchmark {

    @Benchmark
    public void testThreadPool() {
        ThreadPoolExecutor executor = new ThreadPoolExecutor(
            10, 20, 60L, TimeUnit.SECONDS,
            new ArrayBlockingQueue<>(100),
            new ThreadPoolExecutor.CallerRunsPolicy()
        );

        CountDownLatch latch = new CountDownLatch(1000);
        for (int i = 0; i < 1000; i++) {
            executor.submit(() -> {
                // 模拟任务
                try {
                    Thread.sleep(10);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
                latch.countDown();
            });
        }

        latch.await();
        executor.shutdown();
    }
}
```

---

## 总结

**生产环境检查清单**：
- [ ] 使用自定义ThreadPoolExecutor，不用Executors
- [ ] 设置有界队列
- [ ] 设置合理的拒绝策略
- [ ] 给线程池命名
- [ ] 实现异常处理
- [ ] 添加监控告警
- [ ] 实现优雅关闭
- [ ] 支持动态调整
- [ ] 进行压测调优

---

**系列文章**：
- 上一篇：[Java并发20：ThreadPoolExecutor详解](/java-concurrency/posts/20-threadpoolexecutor/)
- 下一篇：[Java并发22：BlockingQueue详解](/java-concurrency/posts/22-blockingqueue/) （即将发布）
