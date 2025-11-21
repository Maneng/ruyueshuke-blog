---
title: "并发设计模式：经典模式与最佳实践"
date: 2025-11-20T11:00:00+08:00
draft: false
tags: ["Java并发", "设计模式", "最佳实践"]
categories: ["技术"]
description: "掌握经典并发设计模式，包括生产者-消费者、线程池、Future模式、不变模式等，写出高质量并发代码"
series: ["Java并发编程从入门到精通"]
weight: 33
stage: 4
stageTitle: "实战应用篇"
---

## 一、生产者-消费者模式

### 1.1 核心思想

```
生产者线程 → [队列] → 消费者线程

- 生产者：生产数据，放入队列
- 消费者：从队列取出数据，处理
- 队列：解耦生产者和消费者
```

**优势**：
- ✅ 解耦：生产者和消费者独立
- ✅ 削峰填谷：队列缓冲，应对突发流量
- ✅ 异步处理：提高响应速度

### 1.2 BlockingQueue实现

```java
public class ProducerConsumerDemo {
    private BlockingQueue<Task> queue = new LinkedBlockingQueue<>(100);

    // 生产者
    class Producer implements Runnable {
        @Override
        public void run() {
            while (true) {
                try {
                    Task task = produceTask();
                    queue.put(task);  // 队列满时阻塞
                    System.out.println("生产：" + task);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    break;
                }
            }
        }

        private Task produceTask() {
            // 生产任务
            return new Task();
        }
    }

    // 消费者
    class Consumer implements Runnable {
        @Override
        public void run() {
            while (true) {
                try {
                    Task task = queue.take();  // 队列空时阻塞
                    processTask(task);
                    System.out.println("消费：" + task);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    break;
                }
            }
        }

        private void processTask(Task task) {
            // 处理任务
        }
    }

    public static void main(String[] args) {
        ProducerConsumerDemo demo = new ProducerConsumerDemo();

        // 启动3个生产者
        for (int i = 0; i < 3; i++) {
            new Thread(demo.new Producer()).start();
        }

        // 启动5个消费者
        for (int i = 0; i < 5; i++) {
            new Thread(demo.new Consumer()).start();
        }
    }
}
```

---

## 二、线程池模式

### 2.1 核心思想

```
任务提交 → [线程池] → 线程执行

- 预创建线程，复用线程资源
- 避免频繁创建/销毁线程的开销
- 控制并发数量，避免资源耗尽
```

### 2.2 自定义线程池

```java
public class CustomThreadPool {
    private final BlockingQueue<Runnable> taskQueue;
    private final List<WorkerThread> workers;
    private volatile boolean isShutdown = false;

    public CustomThreadPool(int poolSize, int queueSize) {
        taskQueue = new LinkedBlockingQueue<>(queueSize);
        workers = new ArrayList<>(poolSize);

        // 创建工作线程
        for (int i = 0; i < poolSize; i++) {
            WorkerThread worker = new WorkerThread();
            workers.add(worker);
            worker.start();
        }
    }

    // 提交任务
    public void submit(Runnable task) {
        if (isShutdown) {
            throw new IllegalStateException("线程池已关闭");
        }

        try {
            taskQueue.put(task);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    // 关闭线程池
    public void shutdown() {
        isShutdown = true;
        for (WorkerThread worker : workers) {
            worker.interrupt();
        }
    }

    // 工作线程
    private class WorkerThread extends Thread {
        @Override
        public void run() {
            while (!isShutdown) {
                try {
                    Runnable task = taskQueue.take();
                    task.run();
                } catch (InterruptedException e) {
                    break;
                }
            }
        }
    }
}
```

---

## 三、Future模式

### 3.1 核心思想

```
主线程提交任务 → 异步执行 → 主线程继续工作 → 需要时获取结果

- 异步获取结果
- 主线程不阻塞
- 提高并发性能
```

### 3.2 简化实现

```java
public class FutureDemo {

    // 自定义Future
    class FutureResult<T> {
        private volatile T result;
        private volatile boolean isDone = false;

        public void set(T result) {
            this.result = result;
            this.isDone = true;
            synchronized (this) {
                notifyAll();  // 唤醒等待线程
            }
        }

        public T get() throws InterruptedException {
            if (!isDone) {
                synchronized (this) {
                    while (!isDone) {
                        wait();  // 等待结果
                    }
                }
            }
            return result;
        }
    }

    // 异步任务
    public FutureResult<String> asyncTask() {
        FutureResult<String> future = new FutureResult<>();

        new Thread(() -> {
            // 模拟耗时操作
            try {
                Thread.sleep(2000);
            } catch (InterruptedException e) {
                e.printStackTrace();
            }

            // 设置结果
            future.set("异步任务完成");
        }).start();

        return future;  // 立即返回Future
    }

    public static void main(String[] args) throws InterruptedException {
        FutureDemo demo = new FutureDemo();

        // 提交异步任务
        FutureResult<String> future = demo.asyncTask();

        // 主线程继续工作
        System.out.println("主线程继续工作...");

        // 需要时获取结果
        String result = future.get();
        System.out.println("结果：" + result);
    }
}
```

---

## 四、不变模式（Immutable Pattern）

### 4.1 核心思想

```
对象创建后，状态不可改变

- 无需同步：线程安全
- 简化并发：无竞态条件
- 高性能：无锁开销
```

### 4.2 实现方式

```java
// 不变对象
public final class ImmutablePoint {
    private final int x;
    private final int y;

    public ImmutablePoint(int x, int y) {
        this.x = x;
        this.y = y;
    }

    public int getX() {
        return x;
    }

    public int getY() {
        return y;
    }

    // 修改操作返回新对象
    public ImmutablePoint move(int deltaX, int deltaY) {
        return new ImmutablePoint(x + deltaX, y + deltaY);
    }
}

// 使用
ImmutablePoint p1 = new ImmutablePoint(0, 0);
ImmutablePoint p2 = p1.move(10, 10);  // 新对象

// 多线程安全：p1和p2都不会被修改
```

**关键要素**：
1. **final类**：防止继承
2. **final字段**：防止修改
3. **不提供setter**：只读
4. **返回新对象**：修改操作返回新对象

---

## 五、Thread-Per-Message模式

### 5.1 核心思想

```
每个请求一个线程

- 简单直接：每个请求独立线程
- 隔离性好：请求互不影响
- 适合短任务：快速响应
```

### 5.2 实现

```java
public class ThreadPerMessageDemo {

    // 为每个请求创建线程
    public void handleRequest(final Request request) {
        new Thread(() -> {
            // 处理请求
            processRequest(request);
        }).start();
    }

    private void processRequest(Request request) {
        System.out.println("处理请求：" + request);
    }

    // 优化：使用线程池
    private ExecutorService executor = Executors.newCachedThreadPool();

    public void handleRequestOptimized(final Request request) {
        executor.submit(() -> {
            processRequest(request);
        });
    }
}
```

**注意**：
- ❌ 高并发时线程数爆炸
- ✅ 改用线程池优化

---

## 六、Worker Thread模式

### 6.1 核心思想

```
任务队列 + 工作线程池

- 预创建线程：复用线程资源
- 任务队列：缓冲任务
- 负载均衡：线程自动分配任务
```

### 6.2 实现（类似线程池）

```java
public class WorkerThreadDemo {
    private final BlockingQueue<Task> taskQueue = new LinkedBlockingQueue<>(100);
    private final List<WorkerThread> workers = new ArrayList<>();

    public WorkerThreadDemo(int workerCount) {
        for (int i = 0; i < workerCount; i++) {
            WorkerThread worker = new WorkerThread("Worker-" + i, taskQueue);
            workers.add(worker);
            worker.start();
        }
    }

    public void submit(Task task) throws InterruptedException {
        taskQueue.put(task);
    }

    // 工作线程
    static class WorkerThread extends Thread {
        private final BlockingQueue<Task> taskQueue;

        public WorkerThread(String name, BlockingQueue<Task> taskQueue) {
            super(name);
            this.taskQueue = taskQueue;
        }

        @Override
        public void run() {
            while (!isInterrupted()) {
                try {
                    Task task = taskQueue.take();
                    System.out.println(getName() + " 执行任务：" + task);
                    task.execute();
                } catch (InterruptedException e) {
                    break;
                }
            }
        }
    }
}
```

---

## 七、Two-Phase Termination模式

### 7.1 核心思想

```
两阶段终止：

1. 发送终止信号
2. 等待线程完成清理

- 安全终止：避免资源泄漏
- 优雅关闭：完成清理工作
```

### 7.2 实现

```java
public class TwoPhaseTerminationDemo {

    private volatile boolean shutdownRequested = false;
    private Thread workerThread;

    // 启动工作线程
    public void start() {
        workerThread = new Thread(() -> {
            try {
                while (!shutdownRequested) {
                    // 执行任务
                    doWork();
                }
            } finally {
                // 清理资源
                doCleanup();
            }
        });
        workerThread.start();
    }

    // 请求关闭（第一阶段）
    public void shutdown() {
        shutdownRequested = true;
        workerThread.interrupt();  // 唤醒阻塞
    }

    // 等待终止（第二阶段）
    public void awaitTermination() throws InterruptedException {
        workerThread.join();
    }

    private void doWork() {
        try {
            // 模拟工作
            Thread.sleep(1000);
            System.out.println("工作中...");
        } catch (InterruptedException e) {
            // 响应中断
        }
    }

    private void doCleanup() {
        System.out.println("清理资源...");
    }

    public static void main(String[] args) throws InterruptedException {
        TwoPhaseTerminationDemo demo = new TwoPhaseTerminationDemo();
        demo.start();

        Thread.sleep(3000);

        // 两阶段终止
        demo.shutdown();           // 第一阶段：请求关闭
        demo.awaitTermination();   // 第二阶段：等待终止

        System.out.println("程序结束");
    }
}
```

---

## 八、Guarded Suspension模式

### 8.1 核心思想

```
等待条件满足再执行

- 条件保护：检查条件
- 等待通知：条件不满足时等待
- 唤醒执行：条件满足时唤醒
```

### 8.2 实现

```java
public class GuardedSuspensionDemo {

    private final Queue<Request> queue = new LinkedList<>();
    private final Object lock = new Object();

    // 生产者：放入请求
    public void putRequest(Request request) {
        synchronized (lock) {
            queue.offer(request);
            lock.notifyAll();  // 唤醒等待的消费者
        }
    }

    // 消费者：获取请求（等待条件满足）
    public Request getRequest() throws InterruptedException {
        synchronized (lock) {
            while (queue.isEmpty()) {
                lock.wait();  // 等待队列非空
            }
            return queue.poll();
        }
    }

    public static void main(String[] args) throws InterruptedException {
        GuardedSuspensionDemo demo = new GuardedSuspensionDemo();

        // 消费者线程
        Thread consumer = new Thread(() -> {
            try {
                while (true) {
                    Request request = demo.getRequest();
                    System.out.println("处理请求：" + request);
                }
            } catch (InterruptedException e) {
                e.printStackTrace();
            }
        });
        consumer.start();

        // 生产者：延迟2秒后放入请求
        Thread.sleep(2000);
        demo.putRequest(new Request());
    }

    static class Request {
    }
}
```

---

## 九、并发设计模式总结

| 模式 | 核心思想 | 适用场景 | 典型实现 |
|-----|---------|---------|---------|
| **生产者-消费者** | 队列解耦 | 异步处理、削峰填谷 | BlockingQueue |
| **线程池** | 线程复用 | 高并发任务执行 | ThreadPoolExecutor |
| **Future** | 异步获取结果 | 异步计算 | FutureTask |
| **不变模式** | 对象不可变 | 无锁并发 | String、Integer |
| **Thread-Per-Message** | 每请求一线程 | 短任务、快速响应 | new Thread() |
| **Worker Thread** | 工作线程池 | 任务队列 | 线程池 |
| **Two-Phase Termination** | 两阶段终止 | 优雅关闭 | shutdown + awaitTermination |
| **Guarded Suspension** | 等待条件 | 同步通信 | wait/notify |

---

## 十、最佳实践

### 10.1 选择合适的模式

```java
// 场景1：异步处理
// 使用：生产者-消费者 + 线程池
ExecutorService executor = Executors.newFixedThreadPool(10);
BlockingQueue<Task> queue = new LinkedBlockingQueue<>();

// 场景2：需要结果
// 使用：Future模式
Future<Result> future = executor.submit(() -> compute());

// 场景3：无锁并发
// 使用：不变模式
ImmutablePoint point = new ImmutablePoint(0, 0);

// 场景4：优雅关闭
// 使用：Two-Phase Termination
executor.shutdown();
executor.awaitTermination(60, TimeUnit.SECONDS);
```

### 10.2 避免常见陷阱

```java
// ❌ 过度创建线程
for (int i = 0; i < 10000; i++) {
    new Thread(() -> task()).start();  // 线程数爆炸
}

// ✅ 使用线程池
ExecutorService executor = Executors.newFixedThreadPool(10);
for (int i = 0; i < 10000; i++) {
    executor.submit(() -> task());
}

// ❌ 忘记关闭线程池
executor.submit(() -> task());
// 没有shutdown，导致资源泄漏

// ✅ 优雅关闭
try {
    executor.submit(() -> task());
} finally {
    executor.shutdown();
    executor.awaitTermination(60, TimeUnit.SECONDS);
}
```

---

## 总结

掌握并发设计模式，能让我们写出更高质量的并发代码：

**核心模式**：
- ✅ **生产者-消费者**：队列解耦，异步处理
- ✅ **线程池**：线程复用，控制并发数
- ✅ **Future**：异步获取结果
- ✅ **不变模式**：对象不可变，线程安全

**实战建议**：
1. **异步处理**优先使用生产者-消费者
2. **高并发任务**使用线程池
3. **需要结果**使用Future模式
4. **无锁并发**使用不变模式
5. **优雅关闭**使用Two-Phase Termination

**下一篇预告**：我们将深入死锁的产生与排查，学习如何避免和解决死锁问题！
