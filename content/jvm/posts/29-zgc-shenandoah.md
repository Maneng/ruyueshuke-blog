---
title: "ZGC/Shenandoah：低延迟收集器的未来"
date: 2025-11-20T20:00:00+08:00
draft: false
tags: ["JVM", "垃圾回收", "ZGC", "Shenandoah"]
categories: ["技术"]
description: "理解ZGC和Shenandoah的超低延迟技术，掌握着色指针、读屏障、转发指针等核心机制"
series: ["JVM从入门到精通"]
weight: 29
stage: 4
stageTitle: "垃圾回收篇"
---

## ZGC收集器

### 核心特点

- **目标**：停顿时间<10ms
- **支持**：TB级堆内存
- **JDK版本**：JDK 11引入，JDK 15生产可用
- **并发度**：几乎所有阶段都并发执行

---

### 核心技术：着色指针（Colored Pointers）

**原理**：利用64位指针的高位存储元数据

```
64位对象指针布局：
┌───────┬────────────────┬──────────────────┐
│ 4位   │    16位        │      44位        │
│ 元数据 │   未使用       │    对象地址      │
└───────┴────────────────┴──────────────────┘

4位元数据：
· Marked0：标记位0
· Marked1：标记位1
· Remapped：是否已重定位
· Finalizable：是否可终结
```

**优势**：
- 无需额外空间存储标记信息
- 通过指针即可判断对象状态

---

### 工作流程

```
1. 初始标记（STW，极短）
   ↓
2. 并发标记
   ↓
3. 再标记（STW，极短）
   ↓
4. 并发转移准备
   ↓
5. 初始转移（STW，极短）
   ↓
6. 并发转移

所有STW阶段总和 < 10ms
```

---

### 读屏障（Load Barrier）

**作用**：访问对象时自动检查和修正指针

```java
// 伪代码
Object loadObject(Object ref) {
    if (needsBarrier(ref)) {
        ref = correctPointer(ref);  // 自动修正指针
    }
    return ref;
}
```

**开销**：
- 每次对象访问都需要屏障检查
- 性能影响约5-15%

---

### 参数配置

```bash
# 启用ZGC（JDK 11+）
java -XX:+UseZGC -Xmx16g -jar app.jar

# 设置并发GC线程数
java -XX:ConcGCThreads=2 -XX:+UseZGC -jar app.jar

# 启用大页内存（提升性能）
java -XX:+UseLargePages -XX:+UseZGC -jar app.jar

# JDK 15+生产环境推荐配置
java -XX:+UseZGC \
     -Xms16g -Xmx16g \
     -XX:ConcGCThreads=2 \
     -XX:+UseLargePages \
     -jar app.jar
```

---

## Shenandoah收集器

### 核心特点

- **目标**：停顿时间<10ms
- **开源**：Red Hat主导
- **JDK版本**：JDK 12引入
- **核心技术**：转发指针（Brooks Pointer）

---

### 核心技术：转发指针

**原理**：在对象头中添加转发指针

```
对象布局：
┌──────────────────┐
│  转发指针        │  ← 额外增加8字节
├──────────────────┤
│  对象头          │
├──────────────────┤
│  实例数据        │
└──────────────────┘

转发指针：
· 初始：指向自己
· 移动后：指向新地址
```

---

### 工作流程

```
1. 初始标记（STW）
   ↓
2. 并发标记
   ↓
3. 最终标记（STW）
   ↓
4. 并发清理
   ↓
5. 并发疏散（Evacuation）← 核心创新
   ↓
6. 初始引用更新（STW）
   ↓
7. 并发引用更新
   ↓
8. 最终引用更新（STW）
```

---

### 读写屏障

Shenandoah使用 **读屏障 + 写屏障**：

```java
// 读屏障（访问对象）
Object load(Object ref) {
    return ref.forwardingPointer;  // 自动转发
}

// 写屏障（更新引用）
void store(Object obj, Object ref) {
    obj.field = ref.forwardingPointer;  // 更新为新地址
}
```

---

### 参数配置

```bash
# 启用Shenandoah（JDK 12+）
java -XX:+UseShenandoahGC -Xmx16g -jar app.jar

# 设置GC模式
java -XX:ShenandoahGCMode=satb \
     -XX:+UseShenandoahGC \
     -jar app.jar

# 生产环境推荐配置
java -XX:+UseShenandoahGC \
     -Xms16g -Xmx16g \
     -XX:+AlwaysPreTouch \
     -XX:+UseNUMA \
     -jar app.jar
```

---

## ZGC vs Shenandoah

| 特性 | ZGC | Shenandoah |
|-----|-----|-----------|
| **核心技术** | 着色指针 | 转发指针 |
| **屏障类型** | 读屏障 | 读屏障 + 写屏障 |
| **内存开销** | 低（无额外对象头） | 高（每对象+8字节） |
| **性能开销** | 约5-15% | 约10-20% |
| **最大堆** | 16TB | 理论无限制 |
| **成熟度** | 高（Oracle支持） | 中（开源社区） |
| **开源** | 部分（JDK 15+完全开源） | 完全开源 |

---

## 性能对比

### 停顿时间对比

| 收集器 | 典型停顿时间 | 最坏情况 |
|-------|------------|---------|
| CMS | 50-200ms | 500ms+ |
| G1 | 100-500ms | 1s+ |
| ZGC | <10ms | <10ms |
| Shenandoah | <10ms | <10ms |

### 吞吐量对比

```
场景：100秒总运行时间

G1：
· GC时间 2秒
· 吞吐量 98%

ZGC：
· GC时间 5秒（屏障开销）
· 吞吐量 95%

权衡：
· ZGC牺牲约3%吞吐量
· 换取极低停顿时间
```

---

## 适用场景

### ZGC适用场景

1. **超大堆**：16GB-16TB堆内存
2. **低延迟要求**：99.99%请求<10ms
3. **云原生应用**：容器化、微服务
4. **实时交易系统**：金融、游戏

### Shenandoah适用场景

1. **大堆内存**：8GB-128GB
2. **开源优先**：完全开源，社区支持
3. **低延迟要求**：停顿时间敏感
4. **红帽系统**：Red Hat Linux

---

## 调优建议

### 1. 内存配置

```bash
# 避免堆动态扩展（影响性能）
-Xms16g -Xmx16g

# 启用大页内存
-XX:+UseLargePages

# 预分配内存
-XX:+AlwaysPreTouch
```

### 2. 监控指标

关注以下指标：
- **停顿时间**：P99/P999停顿时间
- **吞吐量**：应用运行时间占比
- **GC频率**：GC触发频率

### 3. 避免Full GC

ZGC/Shenandoah很少发生Full GC，如果出现说明配置不当：
- 堆内存过小
- 分配速度过快
- 并发线程数不足

---

## 总结

1. **ZGC/Shenandoah**：新一代低延迟收集器
2. **核心技术**：
   - ZGC：着色指针 + 读屏障
   - Shenandoah：转发指针 + 读写屏障
3. **停顿时间**：<10ms，几乎不受堆大小影响
4. **代价**：牺牲约5-15%吞吐量
5. **适用场景**：大堆、低延迟、云原生应用
6. **成熟度**：ZGC更成熟，Shenandoah更开源

---

> **下一篇预告**：《GC日志解读：看懂每一行GC输出》
