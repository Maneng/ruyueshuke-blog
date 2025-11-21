---
title: "Serial/Serial Old：单线程收集器"
date: 2025-11-20T20:00:00+08:00
draft: false
tags: ["JVM", "垃圾回收", "Serial", "单线程GC"]
categories: ["技术"]
description: "理解Serial和Serial Old收集器的工作原理、Stop The World机制，以及适用场景"
series: ["JVM从入门到精通"]
weight: 25
stage: 4
stageTitle: "垃圾回收篇"
---

## 核心特点

**Serial收集器**：
- 单线程收集器（只用一个线程进行GC）
- 新生代收集器
- 使用复制算法
- 必须暂停所有应用线程（Stop The World）

**Serial Old收集器**：
- Serial的老年代版本
- 使用标记-整理算法

---

## 工作流程

```
应用线程执行
    ↓
触发GC
    ↓
Stop The World（暂停所有应用线程）
    ↓
单个GC线程执行垃圾回收
    ↓
恢复应用线程
```

**图解**：

```
应用线程: ████████ [暂停] ████████
GC线程:            ▓▓▓▓▓▓
                  (单线程)
```

---

## 优缺点

### 优点

1. **简单高效**：单线程无需线程切换开销
2. **内存占用小**：适合小堆内存
3. **客户端模式默认**：适合桌面应用

### 缺点

1. **Stop The World时间长**：单线程收集效率低
2. **不适合服务端**：停顿时间无法接受

---

## 使用方法

```bash
# 启用Serial收集器（新生代）+ Serial Old（老年代）
java -XX:+UseSerialGC -jar app.jar

# 查看GC日志
java -XX:+PrintGCDetails -XX:+UseSerialGC -jar app.jar
```

---

## 适用场景

1. **客户端应用**：桌面应用、小工具
2. **小内存应用**：堆内存<100MB
3. **单CPU环境**：无法利用多线程优势

---

## GC日志示例

```
[GC (Allocation Failure) [DefNew: 3072K->320K(3456K), 0.0015428 secs]
3072K->1344K(11904K), 0.0015779 secs] [Times: user=0.00 sys=0.00, real=0.00 secs]

解读：
· DefNew：新生代使用Serial收集器
· 3072K->320K：新生代从3MB降到320KB
· (3456K)：新生代总大小3.5MB
· 0.0015428 secs：GC耗时1.5毫秒
```

---

## 总结

- **Serial**：最古老、最简单的收集器
- **单线程**：Stop The World时间长
- **适用场景**：客户端、小内存应用
- **现代应用**：基本不使用（除非资源极度受限）

---

> **下一篇预告**：《ParNew/Parallel：并行收集器》
