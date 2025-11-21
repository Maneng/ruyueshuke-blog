---
title: "Java并发26：Phaser高级同步器 - 多阶段并发控制"
date: 2025-11-20T22:45:00+08:00
draft: false
tags: ["Java并发", "Phaser", "多阶段同步", "动态线程"]
categories: ["技术"]
description: "Phaser的使用场景、动态注册/注销、多阶段任务协调、层次结构。"
series: ["Java并发编程从入门到精通"]
weight: 26
stage: 3
stageTitle: "Lock与并发工具篇"
---

## Phaser简介

**Phaser = CountDownLatch + CyclicBarrier的增强版**

**核心特性**：
- ✅ 可重用（类似CyclicBarrier）
- ✅ 动态注册/注销线程（优于CyclicBarrier）
- ✅ 多阶段（支持多个屏障点）
- ✅ 层次结构（树形Phaser）

```java
Phaser phaser = new Phaser(3);  // 3个参与者

// 工作线程
new Thread(() -> {
    doWork1();
    phaser.arriveAndAwaitAdvance();  // 等待第1阶段
    doWork2();
    phaser.arriveAndAwaitAdvance();  // 等待第2阶段
}).start();
```

---

## 核心方法

```java
Phaser phaser = new Phaser(3);

// 到达并等待
int phase = phaser.arriveAndAwaitAdvance();  // 阻塞

// 到达但不等待
int phase = phaser.arrive();  // 不阻塞

// 到达并注销
int phase = phaser.arriveAndDeregister();  // 注销自己

// 动态注册
phaser.register();  // 增加参与者
phaser.bulkRegister(5);  // 一次注册5个

// 查询
int phase = phaser.getPhase();  // 当前阶段
int parties = phaser.getRegisteredParties();  // 参与者数
int arrived = phaser.getArrivedParties();  // 已到达数
int unarrived = phaser.getUnarrivedParties();  // 未到达数
boolean terminated = phaser.isTerminated();  // 是否终止
```

---

## 应用场景

### 场景1：多阶段任务
```java
public class MultiPhaseTask {
    public void execute() {
        int parties = 3;
        Phaser phaser = new Phaser(parties);

        for (int i = 0; i < parties; i++) {
            int id = i;
            new Thread(() -> {
                System.out.println("Thread-" + id + ": Phase 1");
                phaser.arriveAndAwaitAdvance();  // 阶段1结束

                System.out.println("Thread-" + id + ": Phase 2");
                phaser.arriveAndAwaitAdvance();  // 阶段2结束

                System.out.println("Thread-" + id + ": Phase 3");
                phaser.arriveAndAwaitAdvance();  // 阶段3结束
            }).start();
        }
    }
}
```

### 场景2：动态参与者
```java
public class DynamicParties {
    public void run() {
        Phaser phaser = new Phaser(1);  // 初始1个（主线程）

        for (int i = 0; i < 5; i++) {
            phaser.register();  // 动态注册
            new Thread(() -> {
                doWork();
                phaser.arriveAndDeregister();  // 完成后注销
            }).start();
        }

        phaser.arriveAndAwaitAdvance();  // 主线程等待
        System.out.println("所有任务完成");
    }
}
```

### 场景3：批处理
```java
public class BatchProcessor {
    public void process(List<Data> dataList, int batchSize) {
        Phaser phaser = new Phaser() {
            @Override
            protected boolean onAdvance(int phase, int registeredParties) {
                System.out.println("Batch " + phase + " completed");
                return registeredParties == 0;  // 无参与者时终止
            }
        };

        for (int i = 0; i < dataList.size(); i += batchSize) {
            List<Data> batch = dataList.subList(i, Math.min(i + batchSize, dataList.size()));

            phaser.register();
            executor.submit(() -> {
                processBatch(batch);
                phaser.arriveAndDeregister();
            });
        }

        phaser.register();
        phaser.arriveAndAwaitAdvance();  // 等待所有批次完成
        phaser.arriveAndDeregister();
    }
}
```

---

## onAdvance回调

```java
Phaser phaser = new Phaser(3) {
    @Override
    protected boolean onAdvance(int phase, int registeredParties) {
        System.out.println("Phase " + phase + " completed, parties: " + registeredParties);
        return phase >= 2 || registeredParties == 0;  // 3个阶段后终止
    }
};
```

**返回值**：
- `true`：终止Phaser
- `false`：继续下一阶段

---

## 层次结构

```java
// 父Phaser
Phaser root = new Phaser(2);

// 子Phaser（自动注册到父Phaser）
Phaser child1 = new Phaser(root, 3);
Phaser child2 = new Phaser(root, 2);

// 执行流程：
// child1的3个线程 → child1完成 → root的第1个参与者到达
// child2的2个线程 → child2完成 → root的第2个参与者到达
// root完成 → 所有任务完成
```

**应用**：
- 大规模并发（分层管理）
- 减少单个Phaser的竞争

---

## Phaser vs 其他工具

| 特性 | CountDownLatch | CyclicBarrier | Phaser |
|-----|---------------|--------------|---------|
| **可重用** | ❌ | ✅ | ✅ |
| **动态参与者** | ❌ | ❌ | ✅ |
| **多阶段** | ❌ | ❌ | ✅ |
| **层次结构** | ❌ | ❌ | ✅ |
| **回调** | ❌ | ✅ | ✅ |
| **复杂度** | 低 | 低 | 高 |

**选择建议**：
- 简单一次性等待 → CountDownLatch
- 固定线程多轮协作 → CyclicBarrier
- 动态线程、多阶段 → Phaser

---

## 实战案例：Map-Reduce

```java
public class MapReduceWithPhaser {
    public void execute(List<Data> data) {
        int mappers = 4;
        int reducers = 2;

        Phaser phaser = new Phaser(1) {  // 1=主线程
            @Override
            protected boolean onAdvance(int phase, int registeredParties) {
                if (phase == 0) {
                    System.out.println("Map阶段完成");
                } else if (phase == 1) {
                    System.out.println("Reduce阶段完成");
                }
                return phase >= 1;  // 2个阶段后终止
            }
        };

        // Map阶段
        List<List<Result>> mapResults = new ArrayList<>();
        for (int i = 0; i < mappers; i++) {
            phaser.register();
            int id = i;
            executor.submit(() -> {
                List<Result> result = map(data, id);
                mapResults.add(result);
                phaser.arriveAndAwaitAdvance();  // 等待Map完成
            });
        }

        phaser.arriveAndAwaitAdvance();  // 主线程等待Map完成

        // Reduce阶段
        List<Result> finalResults = new ArrayList<>();
        for (int i = 0; i < reducers; i++) {
            phaser.register();
            int id = i;
            executor.submit(() -> {
                Result result = reduce(mapResults, id);
                finalResults.add(result);
                phaser.arriveAndAwaitAdvance();  // 等待Reduce完成
            });
        }

        phaser.arriveAndAwaitAdvance();  // 主线程等待Reduce完成
        System.out.println("任务完成: " + finalResults);
    }
}
```

---

## 总结

**核心优势**：
1. 动态注册/注销参与者
2. 支持多阶段
3. 可重用
4. 支持层次结构

**适用场景**：
- 多阶段任务协调
- 动态线程数
- 大规模并发（分层）

**注意事项**：
- 比其他工具更复杂
- 性能略低于CyclicBarrier
- 简单场景优先使用CountDownLatch/CyclicBarrier

---

**系列文章**：
- 上一篇：[Java并发25：Semaphore与Exchanger](/java-concurrency/posts/25-semaphore-exchanger/)
- 下一篇：[Java并发27：CopyOnWriteArrayList](/java-concurrency/posts/27-copyonwritearraylist/) （即将发布）
