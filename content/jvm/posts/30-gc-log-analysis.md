---
title: "GC日志解读：看懂每一行GC输出"
date: 2025-11-21T20:00:00+08:00
draft: false
tags: ["JVM", "垃圾回收", "GC日志", "性能分析"]
categories: ["技术"]
description: "掌握GC日志的格式、关键指标解读、性能分析方法，以及常用的GC日志分析工具"
series: ["JVM从入门到精通"]
weight: 30
stage: 4
stageTitle: "垃圾回收篇"
---

## GC日志参数

### 基础参数

```bash
# JDK 8及之前
java -XX:+PrintGC \
     -XX:+PrintGCDetails \
     -XX:+PrintGCTimeStamps \
     -XX:+PrintGCDateStamps \
     -Xloggc:gc.log \
     -jar app.jar

# JDK 9+统一日志
java -Xlog:gc*:file=gc.log:time,uptime,level,tags \
     -jar app.jar
```

### 常用参数

| 参数 | 说明 | JDK版本 |
|-----|------|--------|
| `-XX:+PrintGC` | 打印GC简要信息 | 8及之前 |
| `-XX:+PrintGCDetails` | 打印GC详细信息 | 8及之前 |
| `-XX:+PrintGCTimeStamps` | 打印GC时间戳 | 8及之前 |
| `-Xloggc:gc.log` | GC日志输出到文件 | 8及之前 |
| `-Xlog:gc*` | 统一GC日志 | 9+ |

---

## 日志格式解读

### Minor GC日志（JDK 8）

```
2023-01-15T10:30:45.123+0800: 0.234: [GC (Allocation Failure)
[PSYoungGen: 6144K->640K(7168K)] 6585K->2770K(23552K), 0.0019356 secs]
[Times: user=0.01 sys=0.00, real=0.00 secs]
```

**逐项解读**：

| 部分 | 含义 |
|-----|------|
| `2023-01-15T10:30:45.123` | GC发生时间 |
| `0.234` | JVM启动后的时间（秒） |
| `GC` | Minor GC |
| `Allocation Failure` | 触发原因：内存分配失败 |
| `PSYoungGen` | Parallel Scavenge新生代收集器 |
| `6144K->640K` | 新生代从6MB降到640KB |
| `(7168K)` | 新生代总大小7MB |
| `6585K->2770K` | 整堆从6.4MB降到2.7MB |
| `(23552K)` | 堆总大小23MB |
| `0.0019356 secs` | GC耗时1.9毫秒 |
| `user=0.01` | 用户态CPU时间 |
| `sys=0.00` | 内核态CPU时间 |
| `real=0.00` | 实际耗时 |

---

### Full GC日志

```
[Full GC (Ergonomics) [PSYoungGen: 808K->0K(9216K)]
[ParOldGen: 6144K->6827K(10240K)] 6952K->6827K(19456K),
[Metaspace: 3072K->3072K(1056768K)], 0.0098765 secs]
[Times: user=0.02 sys=0.00, real=0.01 secs]
```

**关键点**：
- `Full GC`：全堆收集
- `Ergonomics`：JVM自动触发
- `PSYoungGen`：新生代收集
- `ParOldGen`：老年代收集
- `Metaspace`：元空间收集

---

### G1日志

```
[GC pause (G1 Evacuation Pause) (young), 0.0045248 secs]
   [Parallel Time: 3.8 ms, GC Workers: 4]
      [GC Worker Start (ms): Min: 100.5, Avg: 100.5, Max: 100.5]
      [Ext Root Scanning (ms): Min: 0.1, Avg: 0.2, Max: 0.3]
      [Update RS (ms): Min: 0.0, Avg: 0.1, Max: 0.1]
      [Scan RS (ms): Min: 0.0, Avg: 0.0, Max: 0.0]
      [Code Root Scanning (ms): Min: 0.0, Avg: 0.0, Max: 0.0]
      [Object Copy (ms): Min: 3.2, Avg: 3.3, Max: 3.4]
   [Eden: 24.0M(24.0M)->0.0B(13.0M) Survivors: 0.0B->3072.0K
    Heap: 24.0M(256.0M)->3072.0K(256.0M)]
   [Times: user=0.01 sys=0.00, real=0.00 secs]
```

**关键指标**：
- `Parallel Time`：并行执行时间
- `GC Workers`：GC线程数
- `Ext Root Scanning`：扫描GC Roots时间
- `Object Copy`：复制对象时间

---

## 关键指标

### 1. GC频率

```
统计周期内GC次数：
Minor GC: 100次 / 10分钟 = 10次/分钟
Full GC:  5次 / 10分钟 = 0.5次/分钟

评估：
· Minor GC频率正常
· Full GC频率过高（应接近0）
```

---

### 2. GC停顿时间

```
P99停顿时间：99%的GC停顿时间
P999停顿时间：99.9%的GC停顿时间

目标：
· Minor GC: <50ms
· Full GC: <1s
· G1/ZGC: <10ms
```

---

### 3. 吞吐量

```
吞吐量 = 运行用户代码时间 / 总运行时间

计算：
· 10分钟运行，GC耗时30秒
· 吞吐量 = (600-30) / 600 = 95%

目标：>99%
```

---

### 4. 内存回收效率

```
回收效率 = 回收内存量 / 回收时间

示例：
· 回收100MB内存，耗时50ms
· 回收效率 = 2GB/s

评估：
· 低效：频繁GC但回收少
· 高效：偶尔GC回收多
```

---

## 问题诊断

### 1. 频繁Minor GC

**现象**：
```
[GC ... ] 0.001 secs
[GC ... ] 0.002 secs  ← 间隔极短
[GC ... ] 0.001 secs
```

**原因**：
- Eden区过小
- 对象分配速度过快

**解决**：
```bash
# 增大新生代
-Xmn2g

# 调整新生代比例
-XX:NewRatio=2  # 新生代:老年代 = 1:2
```

---

### 2. 频繁Full GC

**现象**：
```
[Full GC ... ] 0.5 secs
[Full GC ... ] 0.6 secs  ← 频繁Full GC
[Full GC ... ] 0.7 secs
```

**原因**：
- 老年代空间不足
- 元空间不足
- 内存泄漏

**解决**：
```bash
# 增大堆内存
-Xmx4g

# 增大元空间
-XX:MetaspaceSize=256m

# 分析内存泄漏
jmap -dump:live,format=b,file=heap.bin <pid>
```

---

### 3. GC停顿时间过长

**现象**：
```
[GC ... ] 1.5 secs  ← 停顿过长
```

**原因**：
- 堆过大
- 收集器选择不当
- Full GC

**解决**：
```bash
# 使用低延迟收集器
-XX:+UseG1GC
-XX:MaxGCPauseMillis=200

# 或使用ZGC
-XX:+UseZGC
```

---

## GC日志分析工具

### 1. GCeasy

**在线工具**：https://gceasy.io

**功能**：
- 上传GC日志自动分析
- 生成图表报告
- 给出优化建议

---

### 2. GCViewer

**开源工具**：https://github.com/chewiebug/GCViewer

**功能**：
- 可视化GC日志
- 分析GC趋势
- 导出报告

---

### 3. JClarity Censum

**商业工具**（现已开源部分功能）

**功能**：
- 深度GC分析
- 性能优化建议
- 自动化调优

---

## 最佳实践

### 1. 持续监控

```bash
# 生产环境必须开启GC日志
java -Xlog:gc*:file=gc-%t.log:time,uptime,level,tags \
     -XX:+UseGZip \
     -XX:+UseGCLogFileRotation \
     -XX:NumberOfGCLogFiles=10 \
     -XX:GCLogFileSize=100M \
     -jar app.jar
```

---

### 2. 定期分析

- 每天检查GC日志
- 关注异常指标
- 趋势分析（对比历史数据）

---

### 3. 性能基线

建立性能基线，对比优化前后：
- GC频率
- 停顿时间
- 吞吐量
- 内存使用

---

## 总结

1. **GC日志**：性能分析的重要依据
2. **关键指标**：GC频率、停顿时间、吞吐量、回收效率
3. **问题诊断**：
   - 频繁Minor GC → 增大新生代
   - 频繁Full GC → 增大堆/排查泄漏
   - 停顿过长 → 更换收集器
4. **工具**：GCeasy、GCViewer等工具辅助分析
5. **持续监控**：生产环境必须开启GC日志

---

### 第四阶段完成！

至此，我们完成了 **垃圾回收篇** 的全部12篇文章：

✅ 19. 什么是垃圾？如何判断对象已死？
✅ 20. 引用计数法 vs 可达性分析
✅ 21. 四种引用类型详解
✅ 22. 垃圾回收算法（上）
✅ 23. 垃圾回收算法（下）
✅ 24. 垃圾收集器演进史
✅ 25. Serial/Serial Old收集器
✅ 26. ParNew/Parallel收集器
✅ 27. CMS收集器详解
✅ 28. G1收集器详解
✅ 29. ZGC/Shenandoah详解
✅ 30. GC日志解读

**学习成果**：全面掌握垃圾回收理论、算法、收集器、调优方法。

---

## 参考资料

- 《深入理解Java虚拟机（第3版）》- 周志明
- [HotSpot GC Tuning Guide](https://docs.oracle.com/en/java/javase/11/gctuning/)
- [GCeasy](https://gceasy.io)

---

> **下一阶段预告**：性能调优篇
> 学习JVM参数调优、性能分析方法、实战案例排查。
