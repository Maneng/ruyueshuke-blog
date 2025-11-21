---
title: "四种引用类型：强、软、弱、虚引用详解"
date: 2025-11-21T20:00:00+08:00
draft: false
tags: ["JVM", "垃圾回收", "引用类型", "SoftReference"]
categories: ["技术"]
description: "深入理解Java的四种引用类型，掌握强引用、软引用、弱引用、虚引用的区别和使用场景，以及引用队列的应用"
series: ["JVM从入门到精通"]
weight: 21
stage: 4
stageTitle: "垃圾回收篇"
---

## 引言：引用的强度

在JDK 1.2之前，Java的引用只有一种：**要么有引用，对象存活；要么无引用，对象死亡**。

但在实际应用中，我们需要更灵活的引用语义：
- **缓存对象**：内存充足时保留，不足时清理
- **监控对象**：对象被回收时得到通知
- **弱关联对象**：不影响对象的生命周期

JDK 1.2引入了四种引用类型，将引用分为 **强引用、软引用、弱引用、虚引用**，它们的强度依次递减。

**引用强度排序**：
```
强引用 > 软引用 > 弱引用 > 虚引用
```

理解这四种引用类型，是实现高效缓存、监控对象生命周期的基础。

---

## 四种引用类型概览

| 引用类型 | 类 | 回收时机 | 典型使用场景 |
|---------|---|---------|------------|
| 强引用 | 直接引用 | 永不回收（除非无引用） | 普通对象引用 |
| 软引用 | SoftReference | 内存不足时回收 | 缓存、图片缓存 |
| 弱引用 | WeakReference | GC时必定回收 | ThreadLocal、WeakHashMap |
| 虚引用 | PhantomReference | 无法通过引用获取对象 | 对象回收监控、堆外内存清理 |

---

## 强引用（Strong Reference）

### 定义

**强引用** 是最常见的引用类型，使用 `=` 赋值运算符创建。

```java
Object obj = new Object();  // 强引用
```

### 特点

1. **只要有强引用，对象永不回收**
2. **宁可OOM也不回收强引用对象**
3. **最普遍的引用方式**

---

### 示例：强引用不会被回收

```java
public class StrongReferenceDemo {
    public static void main(String[] args) {
        Object obj = new Object();
        System.out.println("Before GC: " + obj);

        // 建议GC
        System.gc();

        // 对象仍然存活
        System.out.println("After GC: " + obj);  // 仍然有效
    }
}
```

**输出**：
```
Before GC: java.lang.Object@15db9742
After GC: java.lang.Object@15db9742
```

---

### 示例：强引用导致OOM

```java
/**
 * VM参数：-Xms20M -Xmx20M
 */
public class StrongReferenceOOM {
    public static void main(String[] args) {
        List<byte[]> list = new ArrayList<>();

        try {
            while (true) {
                // 不断创建强引用
                list.add(new byte[1024 * 1024]);  // 1MB
            }
        } catch (OutOfMemoryError e) {
            System.out.println("OOM: " + e.getMessage());
        }
    }
}
```

**输出**：
```
OOM: Java heap space
```

**关键理解**：
- 强引用对象只要可达，就不会被回收
- 即使内存不足导致OOM，也不会回收强引用对象

---

## 软引用（Soft Reference）

### 定义

**软引用** 用于描述"有用但非必需"的对象。

```java
import java.lang.ref.SoftReference;

Object obj = new Object();
SoftReference<Object> softRef = new SoftReference<>(obj);
```

### 特点

1. **内存充足时，软引用对象不会被回收**
2. **内存不足时，软引用对象会被回收**
3. **适合实现内存敏感的缓存**

---

### 回收时机

**两个条件同时满足时回收**：
1. 对象只有软引用（无强引用）
2. 内存不足（即将OOM）

```
内存充足:
GC → 保留软引用对象 → 对象存活

内存不足:
GC → 回收软引用对象 → 避免OOM
```

---

### 示例：软引用基本使用

```java
import java.lang.ref.SoftReference;

public class SoftReferenceDemo {
    public static void main(String[] args) {
        // 创建软引用
        SoftReference<byte[]> softRef = new SoftReference<>(new byte[1024 * 1024]);

        System.out.println("Before GC: " + softRef.get());  // 获取对象

        // 建议GC（内存充足，不回收）
        System.gc();

        System.out.println("After GC: " + softRef.get());  // 对象仍存在
    }
}
```

**输出**：
```
Before GC: [B@15db9742
After GC: [B@15db9742
```

---

### 示例：内存不足时回收软引用

```java
/**
 * VM参数：-Xms20M -Xmx20M
 */
public class SoftReferenceOOM {
    public static void main(String[] args) {
        // 创建软引用
        SoftReference<byte[]> softRef = new SoftReference<>(new byte[10 * 1024 * 1024]);  // 10MB

        System.out.println("Before allocation: " + softRef.get());

        try {
            // 分配大对象，导致内存不足
            byte[] bigArray = new byte[15 * 1024 * 1024];  // 15MB
        } catch (OutOfMemoryError e) {
            System.out.println("OOM: " + e.getMessage());
        }

        // 软引用对象被回收
        System.out.println("After allocation: " + softRef.get());  // null
    }
}
```

**输出**：
```
Before allocation: [B@15db9742
After allocation: null
```

**关键理解**：
- 分配15MB对象时，堆内存不足
- JVM在抛出OOM之前，先回收软引用对象
- 软引用对象被回收后，`softRef.get()` 返回null

---

### 实战场景：图片缓存

```java
import java.lang.ref.SoftReference;
import java.util.HashMap;
import java.util.Map;

public class ImageCache {
    // 图片缓存：使用软引用避免OOM
    private Map<String, SoftReference<byte[]>> cache = new HashMap<>();

    public byte[] getImage(String path) {
        SoftReference<byte[]> ref = cache.get(path);

        // 从缓存获取
        if (ref != null) {
            byte[] image = ref.get();
            if (image != null) {
                System.out.println("从缓存加载: " + path);
                return image;
            }
        }

        // 缓存miss，从磁盘加载
        System.out.println("从磁盘加载: " + path);
        byte[] image = loadImageFromDisk(path);

        // 放入缓存（软引用）
        cache.put(path, new SoftReference<>(image));

        return image;
    }

    private byte[] loadImageFromDisk(String path) {
        // 模拟从磁盘加载图片
        return new byte[1024 * 1024];  // 1MB
    }
}
```

**优势**：
- 内存充足时，图片保留在缓存中，提高性能
- 内存不足时，自动清理缓存，避免OOM

---

## 弱引用（Weak Reference）

### 定义

**弱引用** 用于描述"非必需"的对象。

```java
import java.lang.ref.WeakReference;

Object obj = new Object();
WeakReference<Object> weakRef = new WeakReference<>(obj);
```

### 特点

1. **只要发生GC，弱引用对象就会被回收**
2. **无论内存是否充足**
3. **比软引用更弱**

---

### 回收时机

**条件**：
- 对象只有弱引用（无强引用）
- 发生GC

```
GC发生:
· 有强引用 → 保留对象
· 只有弱引用 → 回收对象
```

---

### 示例：弱引用基本使用

```java
import java.lang.ref.WeakReference;

public class WeakReferenceDemo {
    public static void main(String[] args) {
        // 创建弱引用
        WeakReference<Object> weakRef = new WeakReference<>(new Object());

        System.out.println("Before GC: " + weakRef.get());

        // 建议GC
        System.gc();

        // 对象已被回收
        System.out.println("After GC: " + weakRef.get());  // null
    }
}
```

**输出**：
```
Before GC: java.lang.Object@15db9742
After GC: null
```

---

### 实战场景：WeakHashMap

**WeakHashMap** 的key使用弱引用，当key不再被使用时，自动从Map中移除。

```java
import java.util.WeakHashMap;

public class WeakHashMapDemo {
    public static void main(String[] args) {
        WeakHashMap<Object, String> map = new WeakHashMap<>();

        Object key1 = new Object();
        Object key2 = new Object();

        map.put(key1, "value1");
        map.put(key2, "value2");

        System.out.println("Before GC: " + map.size());  // 2

        // 移除强引用
        key1 = null;

        // 建议GC
        System.gc();
        System.runFinalization();

        System.out.println("After GC: " + map.size());  // 1（key1被回收）
    }
}
```

**输出**：
```
Before GC: 2
After GC: 1
```

---

### 实战场景：ThreadLocal防内存泄漏

**ThreadLocal内部使用WeakReference**：

```java
// ThreadLocal内部实现（简化）
static class ThreadLocalMap {
    static class Entry extends WeakReference<ThreadLocal<?>> {
        Object value;

        Entry(ThreadLocal<?> k, Object v) {
            super(k);  // key使用弱引用
            value = v;
        }
    }
}
```

**为什么使用弱引用？**
- ThreadLocal对象不再使用时，key会被回收
- 避免线程长时间运行导致的内存泄漏

---

## 虚引用（Phantom Reference）

### 定义

**虚引用** 是最弱的引用类型，几乎不影响对象的生命周期。

```java
import java.lang.ref.PhantomReference;
import java.lang.ref.ReferenceQueue;

Object obj = new Object();
ReferenceQueue<Object> queue = new ReferenceQueue<>();
PhantomReference<Object> phantomRef = new PhantomReference<>(obj, queue);
```

### 特点

1. **无法通过虚引用获取对象**（`get()` 永远返回null）
2. **必须配合引用队列使用**
3. **对象被回收时，虚引用会被加入引用队列**

---

### 用途

**监控对象回收**：在对象被回收时执行清理操作。

**典型场景**：
- 清理堆外内存（DirectByteBuffer）
- 记录对象回收日志
- 资源释放监控

---

### 示例：虚引用基本使用

```java
import java.lang.ref.PhantomReference;
import java.lang.ref.ReferenceQueue;

public class PhantomReferenceDemo {
    public static void main(String[] args) throws InterruptedException {
        Object obj = new Object();
        ReferenceQueue<Object> queue = new ReferenceQueue<>();
        PhantomReference<Object> phantomRef = new PhantomReference<>(obj, queue);

        System.out.println("phantomRef.get(): " + phantomRef.get());  // null

        // 断开强引用
        obj = null;

        // 建议GC
        System.gc();

        // 等待对象被回收
        Thread.sleep(1000);

        // 检查引用队列
        if (queue.poll() == phantomRef) {
            System.out.println("对象已被回收");
        }
    }
}
```

**输出**：
```
phantomRef.get(): null
对象已被回收
```

---

### 实战场景：DirectByteBuffer清理

**DirectByteBuffer使用虚引用清理堆外内存**：

```java
// DirectByteBuffer内部实现（简化）
class DirectByteBuffer extends MappedByteBuffer {
    private final Cleaner cleaner;  // 虚引用的变种

    DirectByteBuffer(int cap) {
        // 分配堆外内存
        long address = Unsafe.allocateMemory(cap);

        // 注册清理器（虚引用）
        cleaner = Cleaner.create(this, new Deallocator(address, cap));
    }

    private static class Deallocator implements Runnable {
        public void run() {
            // 释放堆外内存
            Unsafe.freeMemory(address);
        }
    }
}
```

**工作流程**：
1. DirectByteBuffer对象被回收
2. Cleaner（虚引用）被加入引用队列
3. ReferenceHandler线程处理队列，调用Deallocator
4. 释放堆外内存

---

## 引用队列（Reference Queue）

### 定义

**引用队列** 用于监控引用对象的回收状态。

```java
import java.lang.ref.ReferenceQueue;
import java.lang.ref.SoftReference;

ReferenceQueue<Object> queue = new ReferenceQueue<>();
SoftReference<Object> ref = new SoftReference<>(new Object(), queue);
```

### 工作原理

1. 创建引用时关联引用队列
2. 对象被回收前，引用对象被加入队列
3. 程序可以从队列中获取引用，执行清理操作

---

### 示例：监控对象回收

```java
import java.lang.ref.ReferenceQueue;
import java.lang.ref.WeakReference;

public class ReferenceQueueDemo {
    public static void main(String[] args) throws InterruptedException {
        ReferenceQueue<Object> queue = new ReferenceQueue<>();

        // 创建弱引用，关联队列
        WeakReference<Object> ref1 = new WeakReference<>(new Object(), queue);
        WeakReference<Object> ref2 = new WeakReference<>(new Object(), queue);
        WeakReference<Object> ref3 = new WeakReference<>(new Object(), queue);

        System.out.println("Before GC:");
        System.out.println("ref1.get() = " + ref1.get());
        System.out.println("ref2.get() = " + ref2.get());
        System.out.println("ref3.get() = " + ref3.get());

        // 建议GC
        System.gc();
        Thread.sleep(1000);

        System.out.println("\nAfter GC:");
        System.out.println("ref1.get() = " + ref1.get());
        System.out.println("ref2.get() = " + ref2.get());
        System.out.println("ref3.get() = " + ref3.get());

        // 从队列中获取被回收的引用
        System.out.println("\nReference Queue:");
        WeakReference<?> ref;
        while ((ref = (WeakReference<?>) queue.poll()) != null) {
            System.out.println("回收: " + ref);
        }
    }
}
```

**输出**：
```
Before GC:
ref1.get() = java.lang.Object@15db9742
ref2.get() = java.lang.Object@6d06d69c
ref3.get() = java.lang.Object@7852e922

After GC:
ref1.get() = null
ref2.get() = null
ref3.get() = null

Reference Queue:
回收: java.lang.ref.WeakReference@4e25154f
回收: java.lang.ref.WeakReference@70dea4e
回收: java.lang.ref.WeakReference@5c647e05
```

---

## 四种引用类型对比

| 对比维度 | 强引用 | 软引用 | 弱引用 | 虚引用 |
|---------|-------|-------|-------|-------|
| **类** | 直接引用 | SoftReference | WeakReference | PhantomReference |
| **回收时机** | 永不回收 | 内存不足时 | GC时 | GC时 |
| **get()返回** | - | 对象或null | 对象或null | 永远null |
| **引用队列** | - | 可选 | 可选 | 必需 |
| **典型场景** | 普通对象 | 缓存 | WeakHashMap、ThreadLocal | 对象回收监控 |

---

## 实战建议

### 选择合适的引用类型

**强引用**：
- 默认选择
- 对象必须存活

**软引用**：
- 实现缓存
- 对象可有可无，内存不足时清理

**弱引用**：
- 对象可有可无，GC时清理
- WeakHashMap、ThreadLocal

**虚引用**：
- 监控对象回收
- 清理堆外内存

---

## 常见问题与误区

### ❌ 误区1：软引用对象永不回收

**真相**：内存不足时会回收。

---

### ❌ 误区2：弱引用等同于软引用

**真相**：
- 软引用：内存不足时回收
- 弱引用：GC时必定回收

---

### ❌ 误区3：虚引用可以获取对象

**真相**：虚引用的`get()`永远返回null。

---

## 总结

### 核心要点

1. **四种引用类型强度递减**：强引用 > 软引用 > 弱引用 > 虚引用

2. **强引用**：普通引用，宁可OOM也不回收

3. **软引用**：内存不足时回收，适合缓存

4. **弱引用**：GC时必定回收，适合WeakHashMap、ThreadLocal

5. **虚引用**：无法获取对象，用于监控对象回收

6. **引用队列**：监控引用对象的回收状态，执行清理操作

### 与下篇文章的衔接

下一篇文章，我们将学习 **垃圾回收算法（上）：标记-清除、标记-复制**，理解两种基础的垃圾回收算法，以及它们的优缺点和适用场景。

---

## 参考资料

- 《深入理解Java虚拟机（第3版）》- 周志明
- [java.lang.ref包文档](https://docs.oracle.com/javase/8/docs/api/java/lang/ref/package-summary.html)
- [Understanding Weak References](https://community.oracle.com/blogs/enicholas/2006/05/04/understanding-weak-references)

---

> **下一篇预告**：《垃圾回收算法（上）：标记-清除、标记-复制》
> 深入理解两种基础垃圾回收算法的工作原理、优缺点，以及它们在不同场景的应用。
