---
title: "CMS收集器：并发标记清除详解"
date: 2025-11-20T20:00:00+08:00
draft: false
tags: ["JVM", "垃圾回收", "CMS", "并发GC"]
categories: ["技术"]
description: "深入理解CMS收集器的四个阶段、并发标记机制、浮动垃圾问题，以及Concurrent Mode Failure"
series: ["JVM从入门到精通"]
weight: 27
stage: 4
stageTitle: "垃圾回收篇"
---

## 核心特点

**CMS（Concurrent Mark Sweep）** - 并发标记清除：

- **目标**：最短停顿时间
- **老年代收集器**
- **并发执行**：大部分时间与应用线程并发
- **算法**：标记-清除

---

## 四个阶段

### 1️⃣ 初始标记（Initial Mark）**【STW】**

**工作**：标记GC Roots直接引用的对象
**特点**：Stop The World，但速度很快

```
应用线程: ████████ [暂停] ████████████████
GC线程:            ▓
                 (极短)
```

---

### 2️⃣ 并发标记（Concurrent Mark）

**工作**：从GC Roots开始遍历整个对象图
**特点**：与应用线程并发执行，耗时最长

```
应用线程: ████████████████████████████
GC线程:   ░░░░░░░░░░░░░░░░░░░░░░░░
         (并发执行)
```

---

### 3️⃣ 重新标记（Remark）**【STW】**

**工作**：修正并发标记期间变化的对象
**特点**：Stop The World，时间略长于初始标记

```
应用线程: ████████████ [暂停] ████████
GC线程:              ▓▓▓
```

---

### 4️⃣ 并发清除（Concurrent Sweep）

**工作**：清除标记为死亡的对象
**特点**：与应用线程并发执行

```
应用线程: ████████████████████████████
GC线程:   ░░░░░░░░░░░░░░░░░░░░░░░░
```

---

## 完整流程图

```
┌──────────────┐
│ 初始标记(STW) │  ← 极短停顿
└──────┬───────┘
       ↓
┌──────────────┐
│ 并发标记      │  ← 耗时最长，并发
└──────┬───────┘
       ↓
┌──────────────┐
│ 重新标记(STW) │  ← 短停顿
└──────┬───────┘
       ↓
┌──────────────┐
│ 并发清除      │  ← 并发
└──────────────┘
```

---

## 优点

1. **低停顿**：大部分时间并发执行
2. **适合互联网应用**：对响应时间敏感的场景

---

## 缺点

### 1️⃣ CPU资源敏感

并发阶段占用CPU资源，影响应用吞吐量。

**默认GC线程数**：
```
GC线程数 = (CPU核心数 + 3) / 4

例如：
· 4核CPU → 1个GC线程（占用25% CPU）
· 8核CPU → 2个GC线程（占用25% CPU）
```

---

### 2️⃣ 浮动垃圾（Floating Garbage）

并发清除阶段产生的新垃圾无法在本次GC清除。

```
并发清除阶段:
应用线程创建新对象 → 变成垃圾 → 本次无法清除
                                ↓
                            下次GC清除
```

**解决方案**：预留空间，不能等老年代满了才GC

```bash
# 设置触发阈值（老年代使用比例）
java -XX:CMSInitiatingOccupancyFraction=75 -jar app.jar
# 老年代使用达到75%时触发CMS GC（默认92%）
```

---

### 3️⃣ 内存碎片

使用标记-清除算法，产生内存碎片。

**解决方案**：定期进行内存整理

```bash
# 多少次Full GC后进行压缩整理（默认0，表示每次）
java -XX:CMSFullGCsBeforeCompaction=5 -jar app.jar
```

---

### 4️⃣ Concurrent Mode Failure

**问题**：并发清除速度赶不上对象分配速度，老年代空间不足。

**现象**：
```
[CMS-concurrent-mark: 0.123/0.123 secs]
[CMS: Concurrent Mode Failure]
[Full GC (Allocation Failure) ...]
```

**后果**：降级为Serial Old收集器，停顿时间变长。

**解决方案**：
1. 降低触发阈值（更早GC）
2. 增大老年代空间
3. 优化应用，减少对象分配

---

## 参数配置

### 启用CMS

```bash
# 启用CMS收集器
java -XX:+UseConcMarkSweepGC -jar app.jar

# 新生代自动使用ParNew
```

### 关键参数

```bash
# 触发阈值（老年代使用比例）
-XX:CMSInitiatingOccupancyFraction=75

# 启用自适应触发阈值
-XX:+UseCMSInitiatingOccupancyOnly

# 并行GC线程数
-XX:ParallelGCThreads=4

# 并发GC线程数
-XX:ConcGCThreads=1

# 多少次Full GC后压缩
-XX:CMSFullGCsBeforeCompaction=0
```

---

## GC日志示例

```
[GC (CMS Initial Mark) [1 CMS-initial-mark: 10812K(13696K)]
11197K(19888K), 0.0001640 secs] [Times: user=0.00 sys=0.00, real=0.00 secs]

[CMS-concurrent-mark-start]
[CMS-concurrent-mark: 0.002/0.002 secs] [Times: user=0.00 sys=0.00, real=0.00 secs]

[CMS-concurrent-preclean-start]
[CMS-concurrent-preclean: 0.000/0.000 secs] [Times: user=0.00 sys=0.00, real=0.00 secs]

[GC (CMS Final Remark) [YG occupancy: 1597 K (6192 K)]
[1 CMS-remark: 10812K(13696K)] 12409K(19888K), 0.0003370 secs]
[Times: user=0.00 sys=0.00, real=0.00 secs]

[CMS-concurrent-sweep-start]
[CMS-concurrent-sweep: 0.001/0.001 secs] [Times: user=0.00 sys=0.00, real=0.00 secs]

解读：
· 初始标记：0.16毫秒
· 并发标记：2毫秒
· 重新标记：0.33毫秒
· 并发清除：1毫秒
· 总STW时间：0.49毫秒
```

---

## 适用场景

1. **互联网应用**：对停顿时间敏感
2. **老年代较大**：足够空间避免Concurrent Mode Failure
3. **CPU资源充足**：能容忍并发GC占用CPU
4. **JDK 8及之前**：主流低延迟选择（JDK 9后推荐G1）

---

## 总结

1. **CMS**：第一个真正意义的并发收集器
2. **四阶段**：初始标记(STW) → 并发标记 → 重新标记(STW) → 并发清除
3. **优点**：低停顿，适合低延迟要求
4. **缺点**：CPU敏感、浮动垃圾、内存碎片、Concurrent Mode Failure
5. **现状**：JDK 9后被G1取代，JDK 14正式废弃

---

> **下一篇预告**：《G1收集器：划时代的垃圾收集器》
