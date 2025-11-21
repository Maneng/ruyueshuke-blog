---
title: "引用计数法 vs 可达性分析：两种判断算法对比"
date: 2025-11-20T20:00:00+08:00
draft: false
tags: ["JVM", "垃圾回收", "引用计数", "可达性分析"]
categories: ["技术"]
description: "深入对比引用计数法和可达性分析法，理解循环引用问题、GC Roots的完整类型，以及主流虚拟机的选择"
series: ["JVM从入门到精通"]
weight: 20
stage: 4
stageTitle: "垃圾回收篇"
---

## 引言：两种流派的对决

判断对象是否存活，是垃圾回收的第一步。业界有两种主流算法：

1. **引用计数法**（Reference Counting）- 简单直接，实时性好
2. **可达性分析法**（Reachability Analysis）- 复杂但准确，能解决循环引用

Python选择了引用计数，Java选择了可达性分析。为什么？各有什么优缺点？

本文将深入对比这两种算法，理解它们的工作原理、适用场景，以及主流虚拟机的选择。

---

## 引用计数算法详解

### 核心原理

**为每个对象添加一个引用计数器**：
- 初始值为0
- 每增加一个引用，计数器+1
- 每减少一个引用，计数器-1
- 计数器为0时，对象可被回收

### 详细工作流程

```java
public class ReferenceCountingExample {
    public static void main(String[] args) {
        Object obj = new Object();  // ①
        Object ref1 = obj;          // ②
        Object ref2 = obj;          // ③
        ref1 = null;                // ④
        ref2 = null;                // ⑤
    }
}
```

**引用计数变化**：

| 步骤 | 操作 | 计数值 | 说明 |
|-----|------|-------|------|
| ① | `new Object()` | 0 → 1 | 创建对象，obj引用它 |
| ② | `ref1 = obj` | 1 → 2 | 增加引用ref1 |
| ③ | `ref2 = obj` | 2 → 3 | 增加引用ref2 |
| ④ | `ref1 = null` | 3 → 2 | 减少引用ref1 |
| ⑤ | `ref2 = null` | 2 → 1 | 减少引用ref2 |
| 方法结束 | obj失效 | 1 → 0 | 对象可被回收 |

---

### 优点

#### 1️⃣ 实现简单

只需为每个对象添加一个整数计数器，逻辑清晰易懂。

```c
// 伪代码
struct Object {
    int ref_count;  // 引用计数
    // 其他数据...
};

void addRef(Object* obj) {
    obj->ref_count++;
}

void removeRef(Object* obj) {
    obj->ref_count--;
    if (obj->ref_count == 0) {
        free(obj);  // 立即回收
    }
}
```

---

#### 2️⃣ 实时性好

**计数为0时立即回收**，不需要等待GC周期。

```java
// 对象使用完毕后立即释放内存
{
    HugeObject obj = new HugeObject();  // 分配大对象
    obj.process();
}  // 块结束，obj计数为0，立即回收内存
```

---

#### 3️⃣ 无停顿（理论上）

回收工作分散在程序执行过程中，不会出现集中的"Stop The World"。

---

### 缺点

#### 1️⃣ 无法解决循环引用（致命缺陷）

**循环引用示例**：

```java
public class CircularReference {
    public Object ref;

    public static void main(String[] args) {
        CircularReference obj1 = new CircularReference();
        CircularReference obj2 = new CircularReference();

        // 循环引用
        obj1.ref = obj2;
        obj2.ref = obj1;

        // 断开外部引用
        obj1 = null;
        obj2 = null;

        // 问题：obj1和obj2互相引用，计数都为1，无法回收
    }
}
```

**内存泄漏分析**：

```
外部引用断开后：

obj1对象：
· ref_count = 1（被obj2.ref引用）
· ref 字段 → obj2

obj2对象：
· ref_count = 1（被obj1.ref引用）
· ref 字段 → obj1

结果：
✗ 无法从外部访问obj1和obj2
✗ 但引用计数都不为0
✗ 内存泄漏
```

---

#### 2️⃣ 额外空间开销

每个对象需要额外存储计数器（通常4字节）。

```
对象大小 = 对象头 + 实例数据 + 引用计数器 + 对齐填充
```

---

#### 3️⃣ 性能开销

**每次引用变化都需要更新计数器**：

```java
for (int i = 0; i < 1000000; i++) {
    Object obj = new Object();  // 计数+1
    list.add(obj);              // 计数+1
}  // 每次循环都有2次计数更新
```

**多线程环境需要原子操作**：

```c
// 需要使用原子操作（CAS）保证线程安全
atomic_increment(&obj->ref_count);
atomic_decrement(&obj->ref_count);
```

---

#### 4️⃣ 无法处理自循环引用

```java
class Node {
    public Node next;
}

Node node = new Node();
node.next = node;  // 自循环引用
node = null;       // 计数仍为1，无法回收
```

---

### 实际应用

虽然Java不使用引用计数，但其他语言有使用：

#### Python

**策略**：引用计数 + 标记清除（解决循环引用）

```python
import sys

a = []
print(sys.getrefcount(a))  # 输出：2（a变量 + getrefcount临时引用）

b = a
print(sys.getrefcount(a))  # 输出：3（a变量 + b变量 + getrefcount临时引用）

# 循环引用
a.append(b)
b.append(a)
# Python使用额外的GC模块检测并回收循环引用
```

---

#### Swift/Objective-C

**策略**：ARC（Automatic Reference Counting）

```swift
class Person {
    var name: String
    weak var friend: Person?  // weak避免循环引用
}

var p1: Person? = Person(name: "张三")
var p2: Person? = Person(name: "李四")

p1?.friend = p2
p2?.friend = p1  // weak引用，不增加计数

p1 = nil  // p1对象计数为0，被回收
p2 = nil  // p2对象计数为0，被回收
```

---

## 可达性分析算法详解

### 核心原理

从 **GC Roots** 对象集合开始，向下搜索：
- **可达对象**：从GC Roots能够到达的对象（存活）
- **不可达对象**：从GC Roots无法到达的对象（垃圾）

**关键概念**：
- **GC Roots**：一组特殊的对象引用，作为起点
- **引用链（Reference Chain）**：从GC Roots到对象的路径

---

### GC Roots的完整类型

**GC Roots包括以下对象引用**：

#### 1️⃣ 虚拟机栈中引用的对象

```java
public void method() {
    Object localObj = new Object();  // GC Root（局部变量）
    // localObj是GC Root，只要方法未结束，对象就不会被回收
}
```

---

#### 2️⃣ 方法区中类静态属性引用的对象

```java
public class StaticReference {
    private static Object staticObj = new Object();  // GC Root（静态变量）

    public static void main(String[] args) {
        // staticObj始终可达，对象不会被回收
    }
}
```

---

#### 3️⃣ 方法区中常量引用的对象

```java
public class ConstantReference {
    private static final Object CONSTANT = new Object();  // GC Root（常量）

    public static void main(String[] args) {
        // CONSTANT始终可达，对象不会被回收
    }
}
```

---

#### 4️⃣ 本地方法栈中JNI引用的对象

```java
public class JNIReference {
    // Native方法引用的对象也是GC Root
    public native void nativeMethod();
}
```

---

#### 5️⃣ 所有被同步锁（synchronized）持有的对象

```java
public void synchronizedMethod() {
    Object lock = new Object();
    synchronized (lock) {
        // lock是GC Root（被synchronized持有）
        // 在同步块执行期间，lock不会被回收
    }
}
```

---

#### 6️⃣ JVM内部引用

- 基本类型的Class对象（如`Integer.class`）
- 异常对象（NullPointerException、OutOfMemoryError等）
- 系统类加载器

---

#### 7️⃣ Java虚拟机内部的引用

- 反射中引用的对象
- 类加载器
- 正在运行的线程对象

---

### 可达性分析流程

**完整流程**：

```
1. 确定GC Roots集合
   ├─ 扫描虚拟机栈
   ├─ 扫描方法区
   ├─ 扫描本地方法栈
   └─ 扫描同步锁等

2. 从GC Roots开始遍历
   ├─ 标记所有可达对象
   └─ 递归标记引用链上的所有对象

3. 未被标记的对象 = 不可达对象（垃圾）
```

---

### 详细示例

```java
public class ReachabilityExample {
    private static Object staticObj = new Object();  // ① GC Root

    public static void main(String[] args) {
        Object obj1 = new Object();  // ② GC Root（局部变量）
        Object obj2 = new Object();  // ③ 通过obj1可达
        Object obj3 = new Object();  // ④ 不可达（垃圾）

        obj1.ref = obj2;  // obj1 → obj2

        // obj3没有任何引用链到达，是垃圾
    }
}
```

**引用链图**：

```
GC Roots:
┌──────────────────────┐
│ staticObj (静态变量) │ ────→ [Object实例①]  ✅ 可达
└──────────────────────┘

┌──────────────────────┐
│ obj1 (局部变量)      │ ────→ [Object实例②] ────→ [Object实例③]  ✅ 可达
└──────────────────────┘

[Object实例④]  ❌ 不可达（垃圾）
```

---

### 循环引用的处理

**可达性分析完美解决循环引用**：

```java
public class CircularReachability {
    public Object ref;

    public static void main(String[] args) {
        CircularReachability obj1 = new CircularReachability();
        CircularReachability obj2 = new CircularReachability();

        obj1.ref = obj2;  // obj1 → obj2
        obj2.ref = obj1;  // obj2 → obj1

        obj1 = null;
        obj2 = null;

        // 虽然obj1和obj2互相引用，但从GC Roots不可达
        // 两者都会被回收
    }
}
```

**可达性分析**：

```
断开外部引用后：

GC Roots: （无引用指向obj1和obj2）

obj1实例 ←──┐
    ↓      │
obj2实例 ────┘

结果：
✓ obj1从GC Roots不可达 → 垃圾
✓ obj2从GC Roots不可达 → 垃圾
✓ 即使互相引用也会被回收
```

---

### 优点

#### 1️⃣ 能够解决循环引用

这是最大的优势，避免内存泄漏。

---

#### 2️⃣ 准确性高

只要从GC Roots不可达，就一定是垃圾。

---

#### 3️⃣ 适合现代垃圾收集器

配合标记-清除、标记-整理等算法，实现高效GC。

---

### 缺点

#### 1️⃣ 实现复杂

需要遍历整个对象图，实现较复杂。

---

#### 2️⃣ Stop The World（STW）

**GC过程需要暂停应用线程**（保证对象关系不变）：

```
应用线程执行
    ↓
GC触发
    ↓
暂停所有应用线程（Stop The World）
    ↓
可达性分析 + 标记 + 清除
    ↓
恢复应用线程
```

**STW时间**：
- 传统GC：几十毫秒到几秒
- 现代GC（G1、ZGC）：几毫秒到十几毫秒

---

#### 3️⃣ 无法实时回收

不像引用计数那样立即回收，需要等待GC周期。

---

## 两种算法对比总结

| 对比维度 | 引用计数法 | 可达性分析法 |
|---------|----------|------------|
| **循环引用** | ❌ 无法处理 | ✅ 完美处理 |
| **实现复杂度** | ✅ 简单 | ❌ 复杂 |
| **实时性** | ✅ 立即回收 | ❌ 等待GC |
| **Stop The World** | ✅ 无STW | ❌ 有STW |
| **空间开销** | ❌ 每个对象需计数器 | ✅ 无额外空间 |
| **多线程开销** | ❌ 需原子操作 | ✅ 无频繁更新 |
| **准确性** | ❌ 可能内存泄漏 | ✅ 准确 |
| **典型应用** | Python、Swift、Objective-C | Java、C#、Go |

---

## 主流虚拟机的选择

### Java虚拟机：可达性分析

**HotSpot、OpenJ9、Graal等都使用可达性分析**。

**原因**：
- 循环引用在Java中很常见（如双向链表、树结构）
- 引用计数无法处理循环引用
- 可达性分析更适合现代GC算法

---

### Python：引用计数 + 标记清除

**策略**：
- 主要使用引用计数（实时回收）
- 额外使用标记清除GC（处理循环引用）

**优点**：
- 大部分对象通过引用计数立即回收
- 循环引用由GC模块定期检测并回收

---

### Swift/Objective-C：ARC（引用计数）

**策略**：
- 使用自动引用计数（ARC）
- 通过`weak`和`unowned`引用打破循环引用

**优点**：
- 编译期插入引用计数管理代码
- 程序员通过`weak`主动避免循环引用

---

## 实战：验证可达性分析

### 示例：循环引用不会导致内存泄漏

```java
/**
 * VM参数：-Xms20M -Xmx20M -XX:+PrintGCDetails
 */
public class ReachabilityTest {
    private static final int _1MB = 1024 * 1024;

    public Object instance = null;

    public static void main(String[] args) {
        // 创建循环引用
        ReachabilityTest obj1 = new ReachabilityTest();
        ReachabilityTest obj2 = new ReachabilityTest();

        obj1.instance = obj2;
        obj2.instance = obj1;

        // 断开GC Roots引用
        obj1 = null;
        obj2 = null;

        // 建议GC
        System.gc();

        // 观察GC日志，obj1和obj2应该被回收
    }
}
```

**GC日志分析**：
```
[GC (System.gc()) [PSYoungGen: 2048K->808K(6144K)] 2048K->816K(19456K), 0.0012345 secs]
[Full GC (System.gc()) [PSYoungGen: 808K->0K(6144K)] [ParOldGen: 8K->639K(13312K)] 816K->639K(19456K), 0.0045678 secs]

解读：
· obj1和obj2虽然互相引用，但从GC Roots不可达
· Full GC后被成功回收
· 证明可达性分析能够处理循环引用
```

---

## 总结

### 核心要点

1. **引用计数法**：简单但无法处理循环引用，Java不使用

2. **可达性分析法**：复杂但准确，能处理循环引用，Java使用

3. **GC Roots包括**：虚拟机栈、静态变量、常量、本地方法栈、同步锁、JVM内部引用

4. **可达性分析完美解决循环引用**：只要从GC Roots不可达，就是垃圾

5. **主流虚拟机选择**：
   - Java/C#/Go：可达性分析
   - Python：引用计数 + 标记清除
   - Swift/Objective-C：ARC（引用计数 + weak引用）

6. **可达性分析的代价**：Stop The World（现代GC已大幅优化）

### 与下篇文章的衔接

下一篇文章，我们将学习 **四种引用类型：强、软、弱、虚引用**，理解不同引用类型对对象生命周期的影响，以及它们的使用场景。

---

## 参考资料

- 《深入理解Java虚拟机（第3版）》- 周志明
- [Java虚拟机规范（Java SE 8版）](https://docs.oracle.com/javase/specs/jvms/se8/html/)
- [Python GC模块文档](https://docs.python.org/3/library/gc.html)

---

> **下一篇预告**：《四种引用类型：强、软、弱、虚引用详解》
> 深入理解强引用、软引用、弱引用、虚引用的区别，以及它们在缓存、监控等场景的应用。
