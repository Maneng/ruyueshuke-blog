---
title: "垃圾回收算法（上）：标记-清除、标记-复制"
date: 2025-11-20T20:00:00+08:00
draft: false
tags: ["JVM", "垃圾回收", "GC算法", "标记清除"]
categories: ["技术"]
description: "深入理解标记-清除和标记-复制两种基础垃圾回收算法，掌握它们的工作原理、优缺点和适用场景"
series: ["JVM从入门到精通"]
weight: 22
stage: 4
stageTitle: "垃圾回收篇"
---

## 引言：如何回收垃圾？

前面我们学习了如何 **判断对象是否是垃圾**（可达性分析），现在进入下一个问题：**如何回收垃圾？**

垃圾回收算法解决的核心问题：
1. **如何标记垃圾对象？**
2. **如何清理垃圾对象占用的内存？**
3. **如何避免内存碎片？**
4. **如何提高回收效率？**

业界主流的垃圾回收算法有四种：
1. **标记-清除（Mark-Sweep）**
2. **标记-复制（Mark-Copy）**
3. **标记-整理（Mark-Compact）**
4. **分代收集（Generational Collection）**

本文将深入学习前两种基础算法：标记-清除和标记-复制。

---

## 标记-清除算法（Mark-Sweep）

### 核心思想

**分两个阶段**：
1. **标记阶段（Mark）**：标记所有存活的对象
2. **清除阶段（Sweep）**：清除所有未标记的对象

### 详细流程

#### 阶段1：标记（Mark）

从GC Roots开始，标记所有可达对象。

```
GC Roots开始遍历
    ↓
标记对象A（可达）
    ↓
标记对象B（A引用）
    ↓
标记对象C（B引用）
    ↓
...
完成标记
```

---

#### 阶段2：清除（Sweep）

遍历堆，清除所有未标记的对象。

```
遍历堆内存
    ↓
遇到未标记对象 → 释放内存
遇到已标记对象 → 保留（清除标记）
    ↓
完成清除
```

---

### 图解示例

**初始状态**：

```
堆内存:
┌────┬────┬────┬────┬────┬────┬────┬────┐
│ A  │ B  │ C  │ D  │ E  │ F  │ G  │ H  │
└────┴────┴────┴────┴────┴────┴────┴────┘

GC Roots引用: A, C, E
```

**标记阶段**：

```
┌────┬────┬────┬────┬────┬────┬────┬────┐
│ A✓ │ B  │ C✓ │ D✓ │ E✓ │ F  │ G  │ H✓ │
└────┴────┴────┴────┴────┴────┴────┴────┘

标记结果:
· A, C, E, D, H 可达（标记✓）
· B, F, G 不可达（未标记）
```

**清除阶段**：

```
┌────┬────┬────┬────┬────┬────┬────┬────┐
│ A  │ 空 │ C  │ D  │ E  │ 空 │ 空 │ H  │
└────┴────┴────┴────┴────┴────┴────┴────┘

清除结果:
· B, F, G 被清除
· 产生内存碎片（空闲区域不连续）
```

---

### 代码模拟

```java
public class MarkSweepDemo {
    static class Object {
        boolean marked = false;  // 标记位
        Object[] references;     // 引用的对象
    }

    // 标记阶段
    public void mark(Object obj) {
        if (obj == null || obj.marked) {
            return;
        }

        // 标记当前对象
        obj.marked = true;

        // 递归标记引用的对象
        if (obj.references != null) {
            for (Object ref : obj.references) {
                mark(ref);
            }
        }
    }

    // 清除阶段
    public void sweep(Object[] heap) {
        for (Object obj : heap) {
            if (obj != null && !obj.marked) {
                // 清除未标记对象
                release(obj);
            } else if (obj != null) {
                // 清除标记（为下次GC准备）
                obj.marked = false;
            }
        }
    }

    private void release(Object obj) {
        // 释放内存
        System.out.println("释放对象: " + obj);
    }
}
```

---

### 优点

#### 1️⃣ 实现简单

逻辑清晰，容易理解和实现。

---

#### 2️⃣ 不需要额外空间

不需要像复制算法那样预留一半空间。

---

### 缺点

#### 1️⃣ 效率低（两次遍历）

- 标记阶段：遍历所有存活对象
- 清除阶段：遍历整个堆

**时间复杂度**：O(n)，n为堆中对象总数

---

#### 2️⃣ 产生内存碎片（致命缺陷）

清除后，空闲内存分散在各处，无法满足大对象分配需求。

**示例**：

```
清除后的堆内存:
┌────┬────┬────┬────┬────┬────┬────┬────┐
│ A  │ 空 │ C  │ D  │ 空 │ 空 │ E  │ 空 │
└────┴────┴────┴────┴────┴────┴────┴────┘

问题:
· 空闲内存总计: 4个单位
· 但不连续,无法分配大小为3的对象
· 需要压缩或整理内存
```

---

#### 3️⃣ Stop The World

标记和清除期间，必须暂停所有应用线程。

---

### 适用场景

- **老年代**：对象存活率高，标记-清除效率相对较高
- **配合标记-整理**：先标记-清除，再定期整理碎片

---

## 标记-复制算法（Mark-Copy）

### 核心思想

将内存分为 **两块相等的区域**（From区和To区）：
1. **标记阶段**：标记From区的存活对象
2. **复制阶段**：将存活对象复制到To区
3. **清除阶段**：清空From区
4. **交换角色**：From和To互换

---

### 详细流程

#### 阶段1：标记（Mark）

标记From区的存活对象。

---

#### 阶段2：复制（Copy）

将存活对象复制到To区（连续分配）。

---

#### 阶段3：清除（Sweep）

清空整个From区。

---

#### 阶段4：交换（Swap）

From区和To区角色互换。

---

### 图解示例

**初始状态**：

```
From区（使用中）:
┌────┬────┬────┬────┬────┬────┬────┬────┐
│ A  │ B  │ C  │ D  │ E  │ F  │ G  │ H  │
└────┴────┴────┴────┴────┴────┴────┴────┘

To区（空闲）:
┌────────────────────────────────────────┐
│                  空                     │
└────────────────────────────────────────┘

存活对象: A, C, D, E, H
```

**复制阶段**：

```
From区:
┌────┬────┬────┬────┬────┬────┬────┬────┐
│ A  │ B  │ C  │ D  │ E  │ F  │ G  │ H  │
└────┴────┴────┴────┴────┴────┴────┴────┘
   ↓           ↓    ↓    ↓              ↓
To区（连续分配）:
┌────┬────┬────┬────┬────┬────┬────┬────┐
│ A  │ C  │ D  │ E  │ H  │ 空 │ 空 │ 空 │
└────┴────┴────┴────┴────┴────┴────┴────┘
```

**清除与交换**：

```
From区（清空）:
┌────────────────────────────────────────┐
│                  空                     │
└────────────────────────────────────────┘

To区（现在是From区）:
┌────┬────┬────┬────┬────┬────┬────┬────┐
│ A  │ C  │ D  │ E  │ H  │ 空 │ 空 │ 空 │
└────┴────┴────┴────┴────┴────┴────┴────┘

结果:
· 存活对象紧密排列，无碎片
· From和To角色互换
```

---

### 代码模拟

```java
public class MarkCopyDemo {
    static class Object {
        String name;
        Object[] references;
    }

    private Object[] fromSpace;  // From区
    private Object[] toSpace;    // To区
    private int toIndex = 0;     // To区分配指针

    public void markCopy() {
        // 1. 标记并复制存活对象
        for (Object root : gcRoots) {
            copy(root);
        }

        // 2. 清空From区
        fromSpace = new Object[fromSpace.length];

        // 3. 交换From和To
        Object[] temp = fromSpace;
        fromSpace = toSpace;
        toSpace = temp;

        // 4. 重置To区指针
        toIndex = 0;
    }

    private Object copy(Object obj) {
        if (obj == null || obj.forwarded != null) {
            return obj.forwarded;  // 已复制
        }

        // 复制对象到To区
        Object newObj = copyObject(obj);
        obj.forwarded = newObj;  // 记录转发地址

        // 递归复制引用的对象
        if (obj.references != null) {
            for (int i = 0; i < obj.references.length; i++) {
                newObj.references[i] = copy(obj.references[i]);
            }
        }

        return newObj;
    }

    private Object copyObject(Object obj) {
        // 在To区分配空间并复制
        Object newObj = new Object();
        newObj.name = obj.name;
        toSpace[toIndex++] = newObj;
        return newObj;
    }
}
```

---

### 优点

#### 1️⃣ 无内存碎片

存活对象连续分配，没有碎片。

---

#### 2️⃣ 分配速度快

使用 **指针碰撞（Bump Pointer）** 分配内存，只需移动指针。

```java
// 分配内存（伪代码）
Object allocate(int size) {
    if (toIndex + size <= toSpace.length) {
        Object obj = toSpace[toIndex];
        toIndex += size;
        return obj;
    }
    return null;  // 内存不足
}
```

---

#### 3️⃣ 高效（只处理存活对象）

只需遍历和复制存活对象，不需要处理死亡对象。

---

### 缺点

#### 1️⃣ 浪费50%的内存空间（致命缺陷）

始终有一半内存处于空闲状态。

```
总内存: 100MB
From区: 50MB（使用）
To区:   50MB（空闲）

实际可用: 50MB
浪费:    50MB
```

---

#### 2️⃣ 存活对象多时效率低

如果存活对象很多，复制开销很大。

**示例**：
```
假设堆大小100MB，存活对象90MB：
· 需要复制90MB对象
· 复制时间长
· 效率低
```

---

#### 3️⃣ Stop The World

复制期间，必须暂停所有应用线程。

---

### 优化：新生代的复制算法

**问题**：标准复制算法浪费50%空间。

**解决方案**：**8:1:1的Eden + Survivor设计**。

```
新生代内存布局:
┌────────────────────────────────────────┐
│           Eden区（8）                   │
├────────────────────┬───────────────────┤
│   Survivor 0（1）  │  Survivor 1（1）  │
└────────────────────┴───────────────────┘

工作流程:
1. 对象分配到Eden区
2. Minor GC时，存活对象复制到Survivor区
3. Survivor区轮流作为From和To
4. 实际可用空间: 90%（Eden + 1个Survivor）
5. 浪费空间: 10%（1个Survivor）
```

**关键优势**：
- 可用空间从50%提升到90%
- 浪费空间从50%降低到10%
- 利用"弱分代假说"（大部分对象朝生夕死）

---

### 适用场景

- **新生代**：对象存活率低（通常<10%），复制算法效率高
- **配合分代收集**：新生代用复制，老年代用标记-清除或标记-整理

---

## 两种算法对比

| 对比维度 | 标记-清除 | 标记-复制 |
|---------|----------|----------|
| **内存碎片** | ❌ 有碎片 | ✅ 无碎片 |
| **内存利用率** | ✅ 100% | ❌ 50%（标准）或90%（优化） |
| **分配速度** | ❌ 慢（需查找空闲块） | ✅ 快（指针碰撞） |
| **存活率高时** | ✅ 效率高 | ❌ 效率低 |
| **存活率低时** | ❌ 效率低 | ✅ 效率高 |
| **实现复杂度** | ✅ 简单 | ❌ 复杂 |
| **典型应用** | 老年代 | 新生代 |

---

## 实战场景

### 新生代的Minor GC

```java
/**
 * VM参数：-Xms20M -Xmx20M -Xmn10M -XX:+PrintGCDetails -XX:SurvivorRatio=8
 */
public class MinorGCDemo {
    private static final int _1MB = 1024 * 1024;

    public static void main(String[] args) {
        byte[] allocation1, allocation2, allocation3, allocation4;

        // Eden区分配
        allocation1 = new byte[2 * _1MB];
        allocation2 = new byte[2 * _1MB];
        allocation3 = new byte[2 * _1MB];

        // Eden区不足，触发Minor GC
        allocation4 = new byte[4 * _1MB];
    }
}
```

**GC日志**：
```
[GC (Allocation Failure) [PSYoungGen: 7291K->808K(9216K)] 7291K->6952K(19456K), 0.0031993 secs]

解读:
· 触发Minor GC（Allocation Failure）
· 新生代从7MB减少到808KB（使用复制算法）
· allocation1/2/3晋升到老年代
· allocation4在Eden区
```

---

## 总结

### 核心要点

1. **标记-清除**：
   - 两个阶段：标记 + 清除
   - 优点：实现简单，不浪费空间
   - 缺点：产生内存碎片，效率低
   - 适用：老年代

2. **标记-复制**：
   - 三个阶段：标记 + 复制 + 清除
   - 优点：无碎片，分配速度快
   - 缺点：浪费50%空间（标准）
   - 优化：新生代8:1:1设计，浪费仅10%
   - 适用：新生代

3. **算法选择**：
   - 存活率低 → 复制算法（新生代）
   - 存活率高 → 标记-清除或标记-整理（老年代）

### 与下篇文章的衔接

下一篇文章，我们将学习 **垃圾回收算法（下）：标记-整理、分代收集**，理解如何解决标记-清除的碎片问题，以及分代收集的完整理论。

---

## 参考资料

- 《深入理解Java虚拟机（第3版）》- 周志明
- [HotSpot GC算法](https://docs.oracle.com/en/java/javase/11/gctuning/)
- [Java虚拟机规范](https://docs.oracle.com/javase/specs/jvms/se8/html/)

---

> **下一篇预告**：《垃圾回收算法（下）：标记-整理、分代收集》
> 深入理解标记-整理算法如何解决碎片问题，以及分代收集理论的完整工作原理。
