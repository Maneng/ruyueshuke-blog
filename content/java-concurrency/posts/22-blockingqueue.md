---
title: "Java并发22：BlockingQueue详解 - 线程安全的队列"
date: 2025-11-20T21:45:00+08:00
draft: false
tags: ["Java并发", "BlockingQueue", "生产者消费者", "队列"]
categories: ["技术"]
description: "BlockingQueue接口、常用实现类、生产者-消费者模式、性能对比。"
series: ["Java并发编程从入门到精通"]
weight: 22
stage: 3
stageTitle: "Lock与并发工具篇"
---

## BlockingQueue核心方法

| 操作 | 抛异常 | 返回值 | 阻塞 | 超时 |
|-----|-------|-------|------|------|
| **插入** | add(e) | offer(e) | **put(e)** | offer(e, time, unit) |
| **删除** | remove() | poll() | **take()** | poll(time, unit) |
| **检查** | element() | peek() | - | - |

**核心区别**：
- `put/take`：阻塞，生产者-消费者模式常用
- `offer/poll`：不阻塞，适合轮询场景

---

## 常用实现类

### 1. ArrayBlockingQueue
```java
// 有界队列，数组实现，FIFO
BlockingQueue<String> queue = new ArrayBlockingQueue<>(10);

// 特点
✅ 有界，防止OOM
✅ 性能稳定
❌ 容量固定，无法扩展
```

### 2. LinkedBlockingQueue
```java
// 可选有界/无界，链表实现
BlockingQueue<String> bounded = new LinkedBlockingQueue<>(10);    // 有界
BlockingQueue<String> unbounded = new LinkedBlockingQueue<>();     // 无界

// 特点
✅ 容量可选
✅ 吞吐量高
❌ 无界模式可能OOM
```

### 3. PriorityBlockingQueue
```java
// 优先级队列，无界
BlockingQueue<Task> queue = new PriorityBlockingQueue<>();

class Task implements Comparable<Task> {
    int priority;

    @Override
    public int compareTo(Task other) {
        return Integer.compare(other.priority, this.priority);  // 高优先级优先
    }
}

// 特点
✅ 按优先级出队
❌ 无界，可能OOM
```

### 4. SynchronousQueue
```java
// 不存储元素，直接交付
BlockingQueue<String> queue = new SynchronousQueue<>();

// 特点
✅ 零容量，直接交付
✅ 适合传递场景
❌ 生产者必须等待消费者
```

### 5. DelayQueue
```java
// 延迟队列
BlockingQueue<DelayedTask> queue = new DelayQueue<>();

class DelayedTask implements Delayed {
    long executeTime;

    @Override
    public long getDelay(TimeUnit unit) {
        return unit.convert(executeTime - System.nanoTime(), TimeUnit.NANOSECONDS);
    }

    @Override
    public int compareTo(Delayed other) {
        return Long.compare(this.getDelay(TimeUnit.NANOSECONDS),
                           other.getDelay(TimeUnit.NANOSECONDS));
    }
}

// 特点
✅ 延迟执行
✅ 适合定时任务
```

---

## 生产者-消费者模式

```java
public class ProducerConsumer {
    private final BlockingQueue<String> queue = new ArrayBlockingQueue<>(10);

    // 生产者
    class Producer implements Runnable {
        @Override
        public void run() {
            try {
                for (int i = 0; i < 100; i++) {
                    String product = "Product-" + i;
                    queue.put(product);  // 阻塞
                    System.out.println("Produced: " + product);
                }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
    }

    // 消费者
    class Consumer implements Runnable {
        @Override
        public void run() {
            try {
                while (!Thread.interrupted()) {
                    String product = queue.take();  // 阻塞
                    System.out.println("Consumed: " + product);
                    // 处理产品
                    Thread.sleep(100);
                }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
    }

    public void start() {
        new Thread(new Producer()).start();
        new Thread(new Consumer()).start();
    }
}
```

---

## 性能对比

| 队列 | 吞吐量 | 是否有界 | 内存占用 | 适用场景 |
|-----|-------|---------|---------|---------|
| **ArrayBlockingQueue** | 中 | 是 | 低 | 通用 |
| **LinkedBlockingQueue** | 高 | 可选 | 高 | 高吞吐 |
| **PriorityBlockingQueue** | 低 | 否 | 高 | 优先级 |
| **SynchronousQueue** | 最高 | 是 | 最低 | 直接交付 |
| **DelayQueue** | 低 | 否 | 中 | 延迟任务 |

---

## 实战案例：任务调度

```java
public class TaskScheduler {
    private final BlockingQueue<Task> taskQueue = new LinkedBlockingQueue<>(100);
    private final ExecutorService executor = Executors.newFixedThreadPool(10);

    public void submitTask(Task task) {
        try {
            taskQueue.put(task);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    public void start() {
        for (int i = 0; i < 10; i++) {
            executor.submit(() -> {
                while (!Thread.interrupted()) {
                    try {
                        Task task = taskQueue.take();
                        task.execute();
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                        break;
                    }
                }
            });
        }
    }
}
```

---

## 总结

**选择指南**：
- 通用场景：`ArrayBlockingQueue`
- 高吞吐量：`LinkedBlockingQueue`
- 优先级：`PriorityBlockingQueue`
- 直接交付：`SynchronousQueue`
- 延迟执行：`DelayQueue`

---

**系列文章**：
- 上一篇：[Java并发21：线程池最佳实践](/java-concurrency/posts/21-threadpool-best-practices/)
- 下一篇：[Java并发23：ConcurrentHashMap原理](/java-concurrency/posts/23-concurrenthashmap/) （即将发布）
