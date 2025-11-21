---
title: "G1收集器：划时代的垃圾收集器"
date: 2025-11-21T20:00:00+08:00
draft: false
tags: ["JVM", "垃圾回收", "G1", "分区收集"]
categories: ["技术"]
description: "深入理解G1收集器的Region设计、Mixed GC机制、停顿时间预测模型，以及调优策略"
series: ["JVM从入门到精通"]
weight: 28
stage: 4
stageTitle: "垃圾回收篇"
---

## 核心特点

**G1（Garbage-First）** 收集器：

- **面向服务端**的收集器（JDK 9默认）
- **分区设计**：将堆划分为多个Region
- **可预测停顿**：设置目标停顿时间
- **混合收集**：同时收集新生代和老年代
- **整体标记-整理，局部复制**：避免碎片

---

## Region设计

### 传统堆 vs G1堆

**传统堆**：
```
┌────────────────────┐
│    新生代 (固定)    │
├────────────────────┤
│    老年代 (固定)    │
└────────────────────┘
```

**G1堆**：
```
┌───┬───┬───┬───┬───┬───┬───┬───┐
│ E │ E │ S │ O │ O │ H │ O │ E │
├───┼───┼───┼───┼───┼───┼───┼───┤
│ O │ E │ S │ O │ E │ O │ E │ O │
└───┴───┴───┴───┴───┴───┴───┴───┘

E - Eden区
S - Survivor区
O - Old区
H - Humongous区（大对象）
```

### Region特点

- 每个Region大小相同（1MB-32MB，2的幂）
- 动态分配角色（Eden/Survivor/Old）
- 大对象（>= Region一半）占用连续Region

---

## G1的GC类型

### 1️⃣ Young GC

**触发**：Eden区满

**回收范围**：所有Eden + Survivor区

**特点**：
- 多线程并行
- Stop The World
- 使用复制算法

---

### 2️⃣ Mixed GC

**触发**：老年代占用比例达到阈值

**回收范围**：所有新生代 + **部分**老年代

**核心思想**：优先回收价值最大的Region（Garbage-First）

**选择策略**：
```
回收价值 = 垃圾占比 / 回收时间

优先选择：
· 垃圾多
· 回收快
的Region
```

---

### 3️⃣ Full GC

**触发**：Mixed GC无法跟上分配速度

**特点**：
- 单线程Serial Old
- Stop The World时间长
- **应尽量避免**

---

## 工作流程

### Mixed GC的四个阶段

#### 1️⃣ 初始标记（Initial Mark）**【STW】**

标记GC Roots直接引用的对象。

---

#### 2️⃣ 并发标记（Concurrent Mark）

遍历对象图，标记存活对象。

---

#### 3️⃣ 最终标记（Final Mark）**【STW】**

处理并发标记期间的变化。

---

#### 4️⃣ 筛选回收（Live Data Counting and Evacuation）**【STW】**

- 统计每个Region的回收价值
- 选择价值最大的Region
- 复制存活对象到新Region

---

## 重要参数

### 基础配置

```bash
# 启用G1（JDK 9+默认）
java -XX:+UseG1GC -jar app.jar

# 设置堆大小
java -Xms4g -Xmx4g -XX:+UseG1GC -jar app.jar
```

### 停顿时间控制

```bash
# 设置目标停顿时间（毫秒，默认200ms）
java -XX:MaxGCPauseMillis=100 -XX:+UseG1GC -jar app.jar

# 注意：目标非硬性保证，是期望值
```

### Region配置

```bash
# 设置Region大小（1MB-32MB，2的幂）
java -XX:G1HeapRegionSize=16m -XX:+UseG1GC -jar app.jar

# 自动计算公式：
# Region大小 = 堆大小 / 2048
# 例如：4GB堆 → 2MB Region
```

### 触发条件

```bash
# 老年代占用比例达到多少触发Mixed GC（默认45%）
java -XX:InitiatingHeapOccupancyPercent=45 -XX:+UseG1GC -jar app.jar

# 每次Mixed GC回收的Region数量
java -XX:G1MixedGCCountTarget=8 -XX:+UseG1GC -jar app.jar
```

---

## 优点

1. **可预测停顿**：通过停顿预测模型控制停顿时间
2. **无碎片**：整体标记-整理算法
3. **并发标记**：减少停顿时间
4. **适合大堆**：Region设计，局部回收

---

## 缺点

1. **内存占用高**：需要额外的记忆集、卡表
2. **写屏障开销**：维护记忆集
3. **小堆劣势**：额外开销明显（<4GB不推荐）

---

## 停顿预测模型

G1通过统计历史数据，预测每个Region的回收时间：

```
预测模型：
· 记录每个Region的回收耗时
· 根据目标停顿时间，选择Region集合
· 优先选择价值最大的Region

示例：
目标停顿时间 = 100ms
Region1: 垃圾90%, 回收耗时30ms → 价值3.0
Region2: 垃圾50%, 回收耗时20ms → 价值2.5
Region3: 垃圾80%, 回收耗时40ms → 价值2.0

选择Region1和Region2（总耗时50ms < 100ms）
```

---

## 调优建议

### 1. 合理设置停顿时间目标

```bash
# 不要设置过小（会导致频繁GC，吞吐量下降）
-XX:MaxGCPauseMillis=200  # 推荐200-500ms

# 过小示例（不推荐）
-XX:MaxGCPauseMillis=10  # 会导致频繁GC
```

### 2. 避免Full GC

**监控指标**：
- Full GC次数应为0或极少
- 出现Full GC说明G1无法跟上分配速度

**优化方案**：
1. 增大堆内存
2. 降低`InitiatingHeapOccupancyPercent`（更早触发Mixed GC）
3. 增加并发GC线程数

### 3. 大对象优化

```bash
# 避免大对象（超过Region一半）
# Region默认大小：堆大小/2048

# 示例：4GB堆 → Region = 2MB
# 大对象阈值 = 1MB
# 应避免分配超过1MB的连续对象
```

---

## GC日志示例

```
[GC pause (G1 Evacuation Pause) (young), 0.0045248 secs]
   [Parallel Time: 3.8 ms, GC Workers: 4]
   [GC Worker Start (ms): Min: 100.5, Avg: 100.5, Max: 100.5]
   [Eden: 24.0M(24.0M)->0.0B(13.0M) Survivors: 0.0B->3072.0K Heap: 24.0M(256.0M)->3072.0K(256.0M)]
 [Times: user=0.01 sys=0.00, real=0.00 secs]

解读：
· Young GC（Evacuation Pause）
· 4个GC线程并行
· Eden区从24MB降到0
· Survivor区增加3MB
· 总堆从24MB降到3MB
· 停顿时间4.5毫秒
```

---

## 适用场景

1. **大堆内存**：4GB-64GB堆
2. **低延迟要求**：可接受100-500ms停顿
3. **服务端应用**：Web应用、微服务
4. **JDK 9+**：默认收集器，推荐使用

---

## 总结

1. **G1**：JDK 9+默认收集器，面向服务端
2. **Region设计**：动态分配，局部回收
3. **Mixed GC**：优先回收价值最大的Region
4. **可预测停顿**：通过预测模型控制停顿时间
5. **适用场景**：大堆、低延迟、服务端应用

---

> **下一篇预告**：《ZGC/Shenandoah：低延迟收集器的未来》
