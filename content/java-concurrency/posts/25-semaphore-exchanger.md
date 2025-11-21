---
title: "Java并发25：Semaphore与Exchanger - 控制并发与数据交换"
date: 2025-11-20T22:30:00+08:00
draft: false
tags: ["Java并发", "Semaphore", "Exchanger", "信号量"]
categories: ["技术"]
description: "Semaphore信号量的使用场景、实现原理、限流应用，以及Exchanger的数据交换机制。"
series: ["Java并发编程从入门到精通"]
weight: 25
stage: 3
stageTitle: "Lock与并发工具篇"
---

## Semaphore：信号量

**核心概念**：控制同时访问资源的线程数

```java
Semaphore semaphore = new Semaphore(3);  // 3个许可证

semaphore.acquire();  // 获取许可证（阻塞）
try {
    // 访问资源
} finally {
    semaphore.release();  // 释放许可证
}
```

### 应用场景

**场景1：限流（数据库连接池）**
```java
public class ConnectionPool {
    private final Semaphore semaphore;
    private final List<Connection> connections;

    public ConnectionPool(int size) {
        this.semaphore = new Semaphore(size);
        this.connections = new ArrayList<>(size);
        for (int i = 0; i < size; i++) {
            connections.add(createConnection());
        }
    }

    public Connection getConnection() throws InterruptedException {
        semaphore.acquire();  // 获取许可证
        return connections.remove(0);
    }

    public void releaseConnection(Connection conn) {
        connections.add(conn);
        semaphore.release();  // 释放许可证
    }
}
```

**场景2：限制并发访问**
```java
public class RateLimiter {
    private final Semaphore semaphore;

    public RateLimiter(int maxConcurrent) {
        this.semaphore = new Semaphore(maxConcurrent);
    }

    public void execute(Runnable task) {
        try {
            if (semaphore.tryAcquire(100, TimeUnit.MILLISECONDS)) {
                try {
                    task.run();
                } finally {
                    semaphore.release();
                }
            } else {
                throw new RuntimeException("Too many requests");
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
```

**场景3：停车场管理**
```java
public class ParkingLot {
    private final Semaphore spaces;

    public ParkingLot(int capacity) {
        this.spaces = new Semaphore(capacity);
    }

    public boolean park() {
        return spaces.tryAcquire();  // 尝试停车
    }

    public void leave() {
        spaces.release();  // 离开停车场
    }

    public int availableSpaces() {
        return spaces.availablePermits();
    }
}
```

### 核心方法

```java
Semaphore semaphore = new Semaphore(10);

// 获取许可证
semaphore.acquire();  // 阻塞
semaphore.acquire(3);  // 一次获取多个

// 尝试获取
if (semaphore.tryAcquire()) {  // 非阻塞
    // 获取成功
}

if (semaphore.tryAcquire(1, TimeUnit.SECONDS)) {  // 超时
    // 1秒内获取成功
}

// 释放许可证
semaphore.release();
semaphore.release(3);  // 一次释放多个

// 查询
int available = semaphore.availablePermits();  // 可用许可证数
int waiting = semaphore.getQueueLength();  // 等待线程数
```

### 公平性

```java
// 非公平（默认，性能好）
Semaphore unfair = new Semaphore(10);

// 公平（FIFO，避免饥饿）
Semaphore fair = new Semaphore(10, true);
```

---

## Exchanger：数据交换

**核心概念**：两个线程互相交换数据

```java
Exchanger<String> exchanger = new Exchanger<>();

// 线程1
new Thread(() -> {
    String data = exchanger.exchange("Data from Thread1");
    System.out.println("Thread1 received: " + data);
}).start();

// 线程2
new Thread(() -> {
    String data = exchanger.exchange("Data from Thread2");
    System.out.println("Thread2 received: " + data);
}).start();

// 输出：
// Thread1 received: Data from Thread2
// Thread2 received: Data from Thread1
```

### 应用场景

**场景1：生产者-消费者（一对一）**
```java
public class ProducerConsumerExchanger {
    private final Exchanger<Buffer> exchanger = new Exchanger<>();

    class Producer implements Runnable {
        @Override
        public void run() {
            Buffer buffer = new Buffer();
            try {
                while (true) {
                    fillBuffer(buffer);  // 填充数据
                    buffer = exchanger.exchange(buffer);  // 交换空buffer
                }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
    }

    class Consumer implements Runnable {
        @Override
        public void run() {
            Buffer buffer = new Buffer();
            try {
                while (true) {
                    buffer = exchanger.exchange(buffer);  // 交换满buffer
                    processBuffer(buffer);  // 处理数据
                }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
    }
}
```

**场景2：数据校验**
```java
public class DataValidator {
    private final Exchanger<Data> exchanger = new Exchanger<>();

    public void validate() {
        // 线程1：从数据库读取
        new Thread(() -> {
            Data dbData = readFromDatabase();
            Data fileData = exchanger.exchange(dbData);
            if (!dbData.equals(fileData)) {
                alert("Data mismatch!");
            }
        }).start();

        // 线程2：从文件读取
        new Thread(() -> {
            Data fileData = readFromFile();
            Data dbData = exchanger.exchange(fileData);
            // 数据已交换，可以对比
        }).start();
    }
}
```

**场景3：遗传算法**
```java
public class GeneticAlgorithm {
    private final Exchanger<Individual> exchanger = new Exchanger<>();

    public void evolve() {
        // 种群1
        new Thread(() -> {
            Individual best = selectBest(population1);
            Individual other = exchanger.exchange(best);  // 交换最优个体
            crossover(best, other);  // 交叉繁殖
        }).start();

        // 种群2
        new Thread(() -> {
            Individual best = selectBest(population2);
            Individual other = exchanger.exchange(best);
            crossover(best, other);
        }).start();
    }
}
```

### 超时处理

```java
Exchanger<String> exchanger = new Exchanger<>();

try {
    String data = exchanger.exchange("myData", 5, TimeUnit.SECONDS);
    System.out.println("Exchanged: " + data);
} catch (TimeoutException e) {
    System.out.println("Exchange timeout");
} catch (InterruptedException e) {
    Thread.currentThread().interrupt();
}
```

---

## 实现原理

### Semaphore
```java
// 基于AQS的共享模式
public class Semaphore {
    private final Sync sync;

    abstract static class Sync extends AbstractQueuedSynchronizer {
        Sync(int permits) {
            setState(permits);  // 初始许可证数
        }

        // acquire()
        protected int tryAcquireShared(int acquires) {
            for (;;) {
                int available = getState();
                int remaining = available - acquires;
                if (remaining < 0 || compareAndSetState(available, remaining))
                    return remaining;
            }
        }

        // release()
        protected boolean tryReleaseShared(int releases) {
            for (;;) {
                int current = getState();
                int next = current + releases;
                if (compareAndSetState(current, next))
                    return true;
            }
        }
    }
}
```

### Exchanger
```java
// 使用槽位（slot）机制
public class Exchanger<V> {
    private volatile Node[] arena;  // 多槽位（高并发）
    private volatile Node slot;     // 单槽位（低并发）

    public V exchange(V x) throws InterruptedException {
        Object v = slotExchange(x, false, 0);
        if (v == null)
            v = arenaExchange(x, false, 0);  // 槽位冲突，使用arena
        return (V) v;
    }
}
```

---

## 性能对比

| 工具 | 适用场景 | 性能 | 复杂度 |
|-----|---------|------|--------|
| **Semaphore** | 限流、资源控制 | 高 | 低 |
| **Exchanger** | 一对一数据交换 | 中 | 中 |

---

## 总结

**Semaphore使用场景**：
- 限流（如数据库连接池）
- 限制并发访问
- 资源管理

**Exchanger使用场景**：
- 一对一数据交换
- 生产者-消费者（一对一）
- 数据校验

**选择建议**：
- 控制并发数 → Semaphore
- 两线程交换数据 → Exchanger

---

**系列文章**：
- 上一篇：[Java并发24：CountDownLatch与CyclicBarrier](/java-concurrency/posts/24-countdown-cyclic/)
- 下一篇：[Java并发26：Phaser高级同步器](/java-concurrency/posts/26-phaser/) （即将发布）
