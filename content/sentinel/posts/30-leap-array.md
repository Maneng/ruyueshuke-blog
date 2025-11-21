---
title: "滑动窗口算法：统计的秘密武器"
date: 2025-11-21T16:39:00+08:00
draft: false
tags: ["Sentinel", "滑动窗口", "LeapArray"]
categories: ["技术"]
series: ["Sentinel从入门到精通"]
weight: 30
stage: 6
stageTitle: "架构原理篇"
description: "深入理解Sentinel的滑动窗口实现"
---

## 滑动窗口原理

### 为什么需要滑动窗口？

固定窗口的临界问题：

```
时间：  0s    0.5s    1s    1.5s    2s
        |---窗口1---|---窗口2---|
请求：   999个      1个     999个

窗口1：999 < 1000 ✅
窗口2：999 < 1000 ✅
实际：0.5s内1998个请求 ❌
```

滑动窗口解决方案：

```
时间：  0s        1s        2s
        |----窗口-----|
        |  分成10个格子  |

每个格子：100ms
统计QPS：滑动统计最近1秒的请求
```

## LeapArray实现

### 核心数据结构

```java
public abstract class LeapArray<T> {
    protected int windowLengthInMs;     // 每个窗口时长
    protected int sampleCount;          // 窗口数量
    protected int intervalInMs;         // 总时长

    protected final AtomicReferenceArray<WindowWrap<T>> array;

    public LeapArray(int sampleCount, int intervalInMs) {
        this.sampleCount = sampleCount;
        this.intervalInMs = intervalInMs;
        this.windowLengthInMs = intervalInMs / sampleCount;
        this.array = new AtomicReferenceArray<>(sampleCount);
    }
}
```

### WindowWrap（窗口包装）

```java
public class WindowWrap<T> {
    private final long windowLengthInMs;  // 窗口时长
    private long windowStart;              // 窗口开始时间
    private T value;                       // 统计数据

    public WindowWrap(long windowLengthInMs, long windowStart, T value) {
        this.windowLengthInMs = windowLengthInMs;
        this.windowStart = windowStart;
        this.value = value;
    }

    public boolean isTimeInWindow(long timeMillis) {
        return windowStart <= timeMillis &&
               timeMillis < windowStart + windowLengthInMs;
    }
}
```

### MetricBucket（统计桶）

```java
public class MetricBucket {
    private final LongAdder[] counters;  // 各项指标计数器

    private volatile long minRt;         // 最小RT

    public MetricBucket() {
        MetricEvent[] events = MetricEvent.values();
        this.counters = new LongAdder[events.length];
        for (MetricEvent event : events) {
            counters[event.ordinal()] = new LongAdder();
        }
        initMinRt();
    }

    public long get(MetricEvent event) {
        return counters[event.ordinal()].sum();
    }

    public void add(MetricEvent event, long n) {
        counters[event.ordinal()].add(n);
    }
}

enum MetricEvent {
    PASS,       // 通过
    BLOCK,      // 阻塞
    EXCEPTION,  // 异常
    SUCCESS,    // 成功
    RT,         // 响应时间
    OCCUPIED_PASS  // 占用通过
}
```

## 窗口获取算法

```java
public WindowWrap<T> currentWindow(long timeMillis) {
    if (timeMillis < 0) {
        return null;
    }

    int idx = calculateTimeIdx(timeMillis);
    long windowStart = calculateWindowStart(timeMillis);

    while (true) {
        WindowWrap<T> old = array.get(idx);

        if (old == null) {
            // 窗口不存在，创建新窗口
            WindowWrap<T> window = new WindowWrap<>(windowLengthInMs, windowStart, newEmptyBucket(timeMillis));
            if (array.compareAndSet(idx, null, window)) {
                return window;
            } else {
                Thread.yield();
            }
        } else if (windowStart == old.windowStart()) {
            // 窗口存在且有效
            return old;
        } else if (windowStart > old.windowStart()) {
            // 窗口过期，重置窗口
            if (updateLock.tryLock()) {
                try {
                    return resetWindowTo(old, windowStart);
                } finally {
                    updateLock.unlock();
                }
            } else {
                Thread.yield();
            }
        } else if (windowStart < old.windowStart()) {
            // 时钟回拨
            return new WindowWrap<>(windowLengthInMs, windowStart, newEmptyBucket(timeMillis));
        }
    }
}

// 计算窗口索引
private int calculateTimeIdx(long timeMillis) {
    long timeId = timeMillis / windowLengthInMs;
    return (int) (timeId % array.length());
}

// 计算窗口开始时间
private long calculateWindowStart(long timeMillis) {
    return timeMillis - timeMillis % windowLengthInMs;
}
```

## QPS计算

```java
public double getQps() {
    long pass = 0;
    List<MetricBucket> list = listAll();

    for (MetricBucket window : list) {
        pass += window.pass();
    }

    return pass / intervalInSec();
}

public List<MetricBucket> listAll() {
    List<MetricBucket> result = new ArrayList<>();
    long currentTime = TimeUtil.currentTimeMillis();

    for (int i = 0; i < array.length(); i++) {
        WindowWrap<MetricBucket> windowWrap = array.get(i);
        if (windowWrap == null || isWindowDeprecated(currentTime, windowWrap)) {
            continue;
        }
        result.add(windowWrap.value());
    }

    return result;
}
```

## 实战示例

### 统计QPS

```java
public class MetricDemo {
    public static void main(String[] args) throws InterruptedException {
        // 创建滑动窗口：2个窗口，1秒总时长
        ArrayMetric metric = new ArrayMetric(2, 1000);

        // 模拟请求
        for (int i = 0; i < 100; i++) {
            metric.addPass(1);
            Thread.sleep(10);
        }

        // 统计QPS
        System.out.println("QPS: " + metric.pass());
        System.out.println("Success: " + metric.success());
        System.out.println("AvgRT: " + metric.avgRt());
    }
}
```

### 自定义统计

```java
public class CustomMetric extends LeapArray<MetricBucket> {

    public CustomMetric(int sampleCount, int intervalInMs) {
        super(sampleCount, intervalInMs);
    }

    @Override
    public MetricBucket newEmptyBucket(long timeMillis) {
        return new MetricBucket();
    }

    @Override
    protected WindowWrap<MetricBucket> resetWindowTo(WindowWrap<MetricBucket> w, long startTime) {
        w.resetTo(startTime);
        w.value().reset();
        return w;
    }

    // 自定义统计方法
    public void addCustomEvent(String event, long value) {
        WindowWrap<MetricBucket> wrap = currentWindow();
        wrap.value().add(event, value);
    }
}
```

## 性能优化

### 1. LongAdder替代AtomicLong

```java
// 高并发下性能更好
private final LongAdder counter = new LongAdder();

public void increment() {
    counter.increment();
}

public long sum() {
    return counter.sum();
}
```

### 2. 数组环形复用

```java
// 使用固定大小数组，避免GC
private final AtomicReferenceArray<WindowWrap<T>> array;

// 环形索引
private int idx = (int) (timeId % array.length());
```

### 3. CAS无锁更新

```java
// 使用CAS避免锁竞争
if (array.compareAndSet(idx, null, window)) {
    return window;
}
```

## 时间对齐问题

```java
// 问题：时间戳100ms对齐
long timeMillis = 12345;  // 实际时间
long windowStart = timeMillis - timeMillis % 100;  // 对齐到100ms

// 结果
12345 → 12300
12399 → 12300
12400 → 12400
```

## 总结

滑动窗口核心：
1. **LeapArray**：环形数组存储窗口
2. **WindowWrap**：包装每个时间窗口
3. **MetricBucket**：统计各项指标
4. **CAS无锁**：高性能并发更新
5. **时间对齐**：窗口开始时间对齐

**性能优势**：
- O(1)复杂度获取当前窗口
- LongAdder高并发统计
- 环形数组避免GC
- 无锁CAS更新
