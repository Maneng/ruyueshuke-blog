---
title: "Java并发24：CountDownLatch与CyclicBarrier - 线程协作工具"
date: 2025-11-20T22:15:00+08:00
draft: false
tags: ["Java并发", "CountDownLatch", "CyclicBarrier", "线程协作"]
categories: ["技术"]
description: "CountDownLatch和CyclicBarrier的使用场景、实现原理、区别对比。"
series: ["Java并发编程从入门到精通"]
weight: 24
stage: 3
stageTitle: "Lock与并发工具篇"
---

## CountDownLatch：倒计时门闩

**核心概念**：等待N个事件完成后，才能继续

```java
CountDownLatch latch = new CountDownLatch(3);  // 初始化计数为3

// 工作线程
new Thread(() -> {
    doWork();
    latch.countDown();  // 计数-1
}).start();

// 主线程等待
latch.await();  // 阻塞，直到计数为0
System.out.println("所有任务完成");
```

### 应用场景

**场景1：等待多个服务启动**
```java
public class ApplicationStarter {
    private final CountDownLatch latch = new CountDownLatch(3);

    public void start() throws InterruptedException {
        // 启动数据库
        new Thread(() -> {
            initDatabase();
            latch.countDown();
        }).start();

        // 启动缓存
        new Thread(() -> {
            initCache();
            latch.countDown();
        }).start();

        // 启动MQ
        new Thread(() -> {
            initMQ();
            latch.countDown();
        }).start();

        // 等待所有服务启动完成
        latch.await();
        System.out.println("应用启动完成");
    }
}
```

**场景2：并行任务聚合**
```java
public class ParallelTask {
    public List<Result> executeParallel(List<Task> tasks) throws InterruptedException {
        CountDownLatch latch = new CountDownLatch(tasks.size());
        List<Result> results = new CopyOnWriteArrayList<>();

        for (Task task : tasks) {
            executor.submit(() -> {
                try {
                    Result result = task.execute();
                    results.add(result);
                } finally {
                    latch.countDown();
                }
            });
        }

        latch.await();  // 等待所有任务完成
        return results;
    }
}
```

**场景3：压测工具**
```java
public class LoadTest {
    public void test(int threadCount) throws InterruptedException {
        CountDownLatch startGate = new CountDownLatch(1);  // 起跑门
        CountDownLatch endGate = new CountDownLatch(threadCount);  // 终点门

        for (int i = 0; i < threadCount; i++) {
            new Thread(() -> {
                try {
                    startGate.await();  // 等待起跑信号
                    doTest();
                } finally {
                    endGate.countDown();
                }
            }).start();
        }

        long start = System.currentTimeMillis();
        startGate.countDown();  // 发出起跑信号，所有线程同时开始
        endGate.await();  // 等待所有线程完成
        long time = System.currentTimeMillis() - start;

        System.out.println("测试完成，耗时: " + time + "ms");
    }
}
```

---

## CyclicBarrier：循环栅栏

**核心概念**：N个线程互相等待，都到达屏障点后一起继续

```java
CyclicBarrier barrier = new CyclicBarrier(3, () -> {
    System.out.println("所有线程到达屏障，开始下一阶段");
});

// 工作线程
new Thread(() -> {
    doWork1();
    barrier.await();  // 等待其他线程
    doWork2();
}).start();
```

### 应用场景

**场景1：多线程计算**
```java
public class ParallelCompute {
    public void compute() throws Exception {
        int threadCount = 4;
        CyclicBarrier barrier = new CyclicBarrier(threadCount, () -> {
            System.out.println("所有线程计算完成，合并结果");
            mergeResults();
        });

        for (int i = 0; i < threadCount; i++) {
            int part = i;
            new Thread(() -> {
                try {
                    computePart(part);
                    barrier.await();  // 等待其他线程
                } catch (Exception e) {
                    e.printStackTrace();
                }
            }).start();
        }
    }
}
```

**场景2：分批处理**
```java
public class BatchProcessor {
    public void process(List<Data> dataList) throws Exception {
        int batchSize = 100;
        CyclicBarrier barrier = new CyclicBarrier(3);  // 可重用

        for (int i = 0; i < dataList.size(); i += batchSize) {
            List<Data> batch = dataList.subList(i, Math.min(i + batchSize, dataList.size()));

            executor.submit(() -> {
                processBatch(batch);
                barrier.await();  // 等待本批次处理完成
                return null;
            });
        }
    }
}
```

---

## 核心区别

| 特性 | CountDownLatch | CyclicBarrier |
|-----|---------------|--------------|
| **计数方式** | 递减（countDown） | 递增（await） |
| **可重用** | ❌ 一次性 | ✅ 可重置 |
| **等待线程** | 1个（主线程） | N个（工作线程） |
| **回调** | ❌ 无 | ✅ 到达屏障时执行 |
| **应用场景** | 等待多个事件完成 | 多线程互相等待 |

**代码对比**：
```java
// CountDownLatch：主线程等待工作线程
CountDownLatch latch = new CountDownLatch(3);
for (int i = 0; i < 3; i++) {
    new Thread(() -> {
        doWork();
        latch.countDown();  // 工作线程完成，计数-1
    }).start();
}
latch.await();  // 主线程等待

// CyclicBarrier：工作线程互相等待
CyclicBarrier barrier = new CyclicBarrier(3);
for (int i = 0; i < 3; i++) {
    new Thread(() -> {
        doWork();
        barrier.await();  // 工作线程互相等待
    }).start();
}
```

---

## 实现原理

### CountDownLatch
```java
// 基于AQS的共享模式
public class CountDownLatch {
    private final Sync sync;

    private static final class Sync extends AbstractQueuedSynchronizer {
        Sync(int count) {
            setState(count);  // 设置初始计数
        }

        // countDown()
        protected boolean tryReleaseShared(int releases) {
            for (;;) {
                int c = getState();
                if (c == 0) return false;
                int nextc = c - 1;
                if (compareAndSetState(c, nextc))
                    return nextc == 0;  // 计数为0时返回true
            }
        }

        // await()
        protected int tryAcquireShared(int acquires) {
            return (getState() == 0) ? 1 : -1;  // 计数为0时获取成功
        }
    }
}
```

### CyclicBarrier
```java
// 基于ReentrantLock + Condition
public class CyclicBarrier {
    private final ReentrantLock lock = new ReentrantLock();
    private final Condition trip = lock.newCondition();
    private final int parties;
    private int count;  // 当前等待线程数

    public int await() throws InterruptedException, BrokenBarrierException {
        lock.lock();
        try {
            int index = --count;
            if (index == 0) {
                // 最后一个到达，唤醒所有线程
                trip.signalAll();
                // 重置count，可重用
                count = parties;
            } else {
                // 等待其他线程
                trip.await();
            }
            return index;
        } finally {
            lock.unlock();
        }
    }
}
```

---

## 常见问题

**Q1：CountDownLatch可以重置吗？**
```java
// ❌ 不能重置，必须创建新实例
latch.await();
// latch无法重置，需要：
latch = new CountDownLatch(3);
```

**Q2：CyclicBarrier可以中途取消吗？**
```java
// ✅ 可以reset
barrier.reset();  // 重置屏障，唤醒所有等待线程（抛BrokenBarrierException）
```

**Q3：超时等待**
```java
// CountDownLatch
if (latch.await(10, TimeUnit.SECONDS)) {
    // 在10秒内完成
} else {
    // 超时
}

// CyclicBarrier
try {
    barrier.await(10, TimeUnit.SECONDS);
} catch (TimeoutException e) {
    // 超时
}
```

---

## 总结

**使用场景**：
- `CountDownLatch`：主线程等待多个工作线程完成
- `CyclicBarrier`：多个工作线程互相等待

**选择建议**：
- 一次性等待 → CountDownLatch
- 多轮协作 → CyclicBarrier
- 需要回调 → CyclicBarrier

---

**系列文章**：
- 上一篇：[Java并发23：ConcurrentHashMap原理](/java-concurrency/posts/23-concurrenthashmap/)
- 下一篇：[Java并发25：Semaphore与Exchanger](/java-concurrency/posts/25-semaphore-exchanger/) （即将发布）
