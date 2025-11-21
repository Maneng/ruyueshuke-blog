---
title: "ParNew/Parallel：并行收集器"
date: 2025-11-20T20:00:00+08:00
draft: false
tags: ["JVM", "垃圾回收", "ParNew", "Parallel"]
categories: ["技术"]
description: "理解ParNew和Parallel Scavenge收集器的并行机制、吞吐量优先策略，以及参数调优"
series: ["JVM从入门到精通"]
weight: 26
stage: 4
stageTitle: "垃圾回收篇"
---

## ParNew收集器

### 核心特点

- **Serial的多线程版本**
- 新生代收集器
- 使用复制算法
- 可与CMS配合使用

### 工作流程

```
应用线程: ████████ [暂停] ████████
GC线程1:           ▓▓▓▓
GC线程2:           ▓▓▓▓
GC线程3:           ▓▓▓▓
GC线程4:           ▓▓▓▓
```

### 参数配置

```bash
# 启用ParNew（新生代）+ CMS（老年代）
java -XX:+UseConcMarkSweepGC -jar app.jar
# (ParNew会自动启用)

# 设置并行GC线程数
java -XX:ParallelGCThreads=4 -jar app.jar
```

---

## Parallel Scavenge收集器

### 核心特点

- **吞吐量优先**收集器
- 新生代收集器
- 使用复制算法
- 自适应调节策略（GC Ergonomics）

### 与ParNew的区别

| 特性 | ParNew | Parallel Scavenge |
|-----|--------|------------------|
| 目标 | 配合CMS降低延迟 | 最大化吞吐量 |
| 自适应 | 无 | 有 |
| 配合老年代 | CMS | Parallel Old |

### 关键参数

```bash
# 启用Parallel Scavenge（新生代）+ Parallel Old（老年代）
java -XX:+UseParallelGC -jar app.jar

# 设置吞吐量目标（默认99，即GC时间占1%）
java -XX:GCTimeRatio=19 -jar app.jar
# 吞吐量 = 1 / (1 + 1/GCTimeRatio)
# GCTimeRatio=19 → 吞吐量=95%

# 设置最大GC停顿时间（毫秒）
java -XX:MaxGCPauseMillis=200 -jar app.jar

# 启用自适应调节（默认开启）
java -XX:+UseAdaptiveSizePolicy -jar app.jar
```

---

## Parallel Old收集器

### 核心特点

- **Parallel Scavenge的老年代版本**
- 使用标记-整理算法
- 多线程并行收集

### 组合使用

```bash
# 完整的并行收集器组合（JDK 7/8常用）
java -XX:+UseParallelGC -XX:+UseParallelOldGC \
     -XX:MaxGCPauseMillis=100 \
     -XX:GCTimeRatio=19 \
     -jar app.jar
```

---

## 自适应调节策略

Parallel Scavenge的核心优势是 **自适应调节**：

1. 自动调整新生代大小
2. 自动调整Eden与Survivor比例
3. 自动调整晋升老年代的对象年龄阈值

**启用后无需手动调整**：
- `-Xmn`（新生代大小）
- `-XX:SurvivorRatio`（Eden/Survivor比例）
- `-XX:MaxTenuringThreshold`（晋升阈值）

---

## 性能对比

### 停顿时间

| 收集器 | 单次停顿时间 | 说明 |
|-------|------------|------|
| Serial | 100ms | 单线程，最慢 |
| ParNew | 25ms | 4线程并行，4倍提升 |
| Parallel | 30ms | 类似ParNew |

### 吞吐量

```
场景：100秒总运行时间

Serial：
· GC时间 10秒
· 吞吐量 = 90%

Parallel：
· GC时间 5秒
· 吞吐量 = 95%
```

---

## 适用场景

### ParNew
- 与CMS配合使用
- 低延迟要求的应用

### Parallel Scavenge + Parallel Old
- 后台计算任务
- 批处理作业
- 科学计算
- 吞吐量优先场景

---

## GC日志示例

### ParNew

```
[GC (Allocation Failure) [ParNew: 6144K->640K(6144K), 0.0023642 secs]
6585K->2770K(19456K), 0.0023901 secs] [Times: user=0.00 sys=0.00, real=0.00 secs]

解读：
· ParNew：并行新生代收集
· 0.0023642 secs：停顿2.3毫秒
```

### Parallel Scavenge

```
[GC (Allocation Failure) [PSYoungGen: 6144K->640K(7168K)]
6585K->2770K(23552K), 0.0019356 secs] [Times: user=0.01 sys=0.00, real=0.00 secs]

解读：
· PSYoungGen：Parallel Scavenge
· 0.0019356 secs：停顿1.9毫秒
```

---

## 总结

1. **ParNew**：Serial的多线程版本，与CMS配合
2. **Parallel Scavenge**：吞吐量优先，自适应调节
3. **Parallel Old**：老年代的并行收集器
4. **并行收集**：利用多核CPU，显著缩短停顿时间
5. **适用场景**：服务端、后台计算、吞吐量优先

---

> **下一篇预告**：《CMS收集器：并发标记清除详解》
