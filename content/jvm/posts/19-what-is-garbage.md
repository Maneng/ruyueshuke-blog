---
title: "什么是垃圾？如何判断对象已死？"
date: 2025-11-21T20:00:00+08:00
draft: false
tags: ["JVM", "垃圾回收", "对象存活", "GC"]
categories: ["技术"]
description: "深入理解垃圾的定义、对象存活判定的方法、finalize机制，以及垃圾回收的核心概念"
series: ["JVM从入门到精通"]
weight: 19
stage: 4
stageTitle: "垃圾回收篇"
---

## 引言：垃圾回收的第一步

当你创建对象后不再使用它们时：

```java
public void createObjects() {
    User user1 = new User("张三", 25);
    User user2 = new User("李四", 30);
    // 方法结束后，user1和user2还能被访问吗？
}
```

这些对象会发生什么？它们如何被回收？在回收之前，JVM如何判断它们是否还有用？

这些问题的答案，都从理解 **"什么是垃圾"** 开始。

**垃圾回收的核心问题**：
1. 哪些内存需要回收？（什么是垃圾）
2. 什么时候回收？（GC触发时机）
3. 如何回收？（GC算法和收集器）

本文将深入第一个问题：**如何判断对象已死**。

---

## 什么是垃圾？

### 定义

**垃圾（Garbage）** = **不再被使用的对象**

更准确地说：**垃圾是指无法再被程序访问到的对象**。

### 为什么需要垃圾回收？

**内存资源是有限的**：
- 堆内存大小有限（如2GB、4GB）
- 不断创建对象，内存终将耗尽
- 需要回收不再使用的对象，释放内存

**手动管理的问题**（如C/C++）：
- 忘记释放内存 → 内存泄漏
- 释放后继续使用 → 悬空指针
- 重复释放 → 程序崩溃

**Java的自动垃圾回收**：
- 程序员无需手动释放内存
- JVM自动识别垃圾并回收
- 大幅减少内存管理错误

---

## 判断对象是否存活的两种算法

判断对象是否是垃圾，有两种主流算法：
1. **引用计数算法**（Reference Counting）
2. **可达性分析算法**（Reachability Analysis）

---

### 方法1：引用计数算法

#### 核心思想

**为每个对象添加一个引用计数器**：
- 有引用指向对象时，计数器+1
- 引用失效时，计数器-1
- 计数器为0时，对象可被回收

#### 示例

```java
public class ReferenceCountingDemo {
    public static void main(String[] args) {
        Object obj = new Object();  // 计数器 = 1
        Object obj2 = obj;          // 计数器 = 2

        obj = null;                 // 计数器 = 1
        obj2 = null;                // 计数器 = 0，可被回收
    }
}
```

**引用计数变化**：
```
创建对象:         计数 = 0
obj 引用对象:     计数 = 1
obj2 引用对象:    计数 = 2
obj = null:      计数 = 1
obj2 = null:     计数 = 0  ← 对象可回收
```

---

#### 优点

1. **实现简单**：只需维护计数器
2. **实时性好**：计数为0立即回收，不需要等待GC
3. **无停顿**：回收过程分散，不会集中暂停

---

#### 致命缺陷：无法解决循环引用

**循环引用示例**：

```java
public class CircularReferenceDemo {
    public Object instance = null;

    public static void main(String[] args) {
        CircularReferenceDemo obj1 = new CircularReferenceDemo();
        CircularReferenceDemo obj2 = new CircularReferenceDemo();

        // 相互引用
        obj1.instance = obj2;  // obj1 → obj2
        obj2.instance = obj1;  // obj2 → obj1

        // 断开外部引用
        obj1 = null;
        obj2 = null;

        // 此时obj1和obj2互相引用，引用计数都为1
        // 但外部已无法访问，应该被回收，但引用计数法无法回收
    }
}
```

**内存状态**：

```
外部引用断开后：

obj1对象:
· 引用计数 = 1（被obj2引用）
· instance → obj2

obj2对象:
· 引用计数 = 1（被obj1引用）
· instance → obj1

问题：
· 外部无法访问obj1和obj2
· 但引用计数都不为0
· 造成内存泄漏
```

---

#### 为什么Java不使用引用计数？

**原因**：
1. 无法解决循环引用
2. 需要额外空间存储计数器
3. 需要原子操作维护计数（多线程环境）

**其他语言的使用情况**：
- Python：使用引用计数 + 标记清除（解决循环引用）
- Swift：使用引用计数（开发者需手动打破循环引用）
- Objective-C：使用引用计数（ARC机制）

---

### 方法2：可达性分析算法

#### 核心思想

从 **GC Roots** 对象开始，向下搜索，搜索路径称为 **引用链（Reference Chain）**。

- **可达对象**：从GC Roots出发能够到达的对象（存活）
- **不可达对象**：从GC Roots无法到达的对象（垃圾）

#### 什么是GC Roots？

**GC Roots** 是一组特殊的对象引用，作为可达性分析的 **起点**。

**GC Roots包括**：

1. **虚拟机栈中引用的对象**
   - 局部变量
   - 方法参数

2. **方法区中类静态属性引用的对象**
   - 静态变量

3. **方法区中常量引用的对象**
   - 字符串常量池中的引用

4. **本地方法栈中JNI引用的对象**
   - Native方法引用的对象

5. **所有被同步锁持有的对象**

6. **JVM内部引用**
   - 基本类型的Class对象
   - 异常对象
   - 类加载器

---

#### 可达性分析示例

```java
public class ReachabilityDemo {
    private static Object staticObj = new Object();  // GC Root（静态变量）

    public void method() {
        Object localObj = new Object();  // GC Root（局部变量）
        Object obj2 = new Object();
        Object obj3 = new Object();

        obj2.next = obj3;  // obj2 → obj3

        // localObj和obj2可达，obj3通过obj2可达
        // 都不会被回收
    }
}
```

**引用链图**：

```
GC Roots:
┌──────────────┐
│ staticObj    │────→ [Object实例]  ✅ 可达
└──────────────┘

┌──────────────┐
│ localObj     │────→ [Object实例]  ✅ 可达
└──────────────┘

┌──────────────┐
│ obj2         │────→ [Object实例] ────→ [Object实例 obj3]  ✅ 可达
└──────────────┘
```

**方法返回后**：

```
GC Roots:
┌──────────────┐
│ staticObj    │────→ [Object实例]  ✅ 可达
└──────────────┘

[Object实例 localObj]  ❌ 不可达（垃圾）
[Object实例 obj2]      ❌ 不可达（垃圾）
[Object实例 obj3]      ❌ 不可达（垃圾）
```

---

#### 循环引用的解决

**可达性分析可以正确处理循环引用**：

```java
public class CircularReachabilityDemo {
    public Object instance = null;

    public static void main(String[] args) {
        CircularReachabilityDemo obj1 = new CircularReachabilityDemo();
        CircularReachabilityDemo obj2 = new CircularReachabilityDemo();

        obj1.instance = obj2;  // obj1 → obj2
        obj2.instance = obj1;  // obj2 → obj1

        obj1 = null;  // 断开GC Root到obj1的引用
        obj2 = null;  // 断开GC Root到obj2的引用

        // 此时obj1和obj2从GC Roots不可达，即使互相引用也会被回收
    }
}
```

**引用链分析**：

```
断开外部引用前：
GC Roots (局部变量obj1) ────→ [obj1实例] ←──┐
                                  ↓        │
                            [obj2实例] ────┘

断开外部引用后：
GC Roots （无引用）

[obj1实例] ←──┐
    ↓        │
[obj2实例] ────┘

结论：obj1和obj2从GC Roots不可达，都是垃圾
```

---

## 对象的两次标记过程

**关键问题**：不可达对象一定会被回收吗？

**答案**：不一定！还有一次"自救"的机会。

### 对象回收的完整流程

#### 第一次标记：可达性分析

1. 从GC Roots开始可达性分析
2. 标记所有不可达对象

---

#### 第二次标记：finalize方法判定

**判断条件**：
- 对象是否覆盖了 `finalize()` 方法？
- `finalize()` 方法是否已被JVM调用过？

**两种情况**：

**情况1：不需要执行finalize()**
- 对象没有覆盖finalize()
- finalize()已被调用过

→ 直接回收

**情况2：需要执行finalize()**
- 对象覆盖了finalize()
- finalize()未被调用

→ 加入F-Queue队列，等待finalize()执行

---

### finalize()方法详解

#### 定义

```java
protected void finalize() throws Throwable {
    // 对象被回收前的最后一次机会
}
```

**特点**：
- 定义在Object类中
- protected修饰，可以被子类覆盖
- 由JVM自动调用，不应手动调用
- **只会被调用一次**

---

#### finalize()的"自救"机制

**对象可以在finalize()中"复活"**：只需让自己重新可达（被GC Roots引用）。

**示例**：

```java
public class FinalizeDemo {
    public static FinalizeDemo SAVE_HOOK = null;

    public void isAlive() {
        System.out.println("我还活着！");
    }

    @Override
    protected void finalize() throws Throwable {
        super.finalize();
        System.out.println("finalize()被调用");

        // 自救：重新将自己赋值给静态变量（GC Root）
        FinalizeDemo.SAVE_HOOK = this;
    }

    public static void main(String[] args) throws InterruptedException {
        SAVE_HOOK = new FinalizeDemo();

        // 第一次自救
        SAVE_HOOK = null;
        System.gc();
        Thread.sleep(500);  // 等待finalize()执行

        if (SAVE_HOOK != null) {
            SAVE_HOOK.isAlive();  // 输出：我还活着！
        } else {
            System.out.println("我死了");
        }

        // 第二次自救（失败）
        SAVE_HOOK = null;
        System.gc();
        Thread.sleep(500);

        if (SAVE_HOOK != null) {
            SAVE_HOOK.isAlive();
        } else {
            System.out.println("我死了");  // 输出：我死了
        }
    }
}
```

**输出**：
```
finalize()被调用
我还活着！
我死了
```

**解释**：
- 第一次GC：finalize()被调用，对象自救成功
- 第二次GC：finalize()不会再被调用，对象被回收

---

#### finalize()的问题

**1. 性能问题**
- finalize()执行缓慢，会延迟GC
- F-Queue队列可能积压大量对象

**2. 不确定性**
- 无法保证finalize()何时执行
- 无法保证finalize()是否执行

**3. 安全问题**
- finalize()中可能抛出异常
- finalize()可能被恶意利用

**建议**：
- **不要使用finalize()**
- 使用 `try-with-resources` 或 `try-finally` 管理资源
- 使用 `Cleaner` 或 `PhantomReference` 替代

---

## 方法区的回收

### 方法区也会回收吗？

**答案**：会，但条件苛刻，效率低。

### 回收内容

1. **废弃的常量**
2. **无用的类**

---

### 废弃常量的判定

**条件**：常量池中的常量没有任何引用。

**示例**：

```java
String s1 = "hello";
s1 = null;

// 如果"hello"字符串常量没有其他引用，可能被回收
```

---

### 无用类的判定

**必须同时满足3个条件**：

1. **该类的所有实例都已被回收**
   - 堆中不存在该类的任何实例

2. **加载该类的类加载器已被回收**
   - 非常难达成（除非使用自定义类加载器）

3. **该类对应的Class对象没有被引用**
   - 无法通过反射访问该类

**示例**：

```java
// 使用自定义类加载器加载类
MyClassLoader loader = new MyClassLoader();
Class<?> clazz = loader.loadClass("com.example.MyClass");
Object obj = clazz.newInstance();

// 释放所有引用
obj = null;
clazz = null;
loader = null;

// 建议GC
System.gc();

// MyClass可能被卸载（取决于JVM实现）
```

---

## 实战：查看对象存活状态

### 使用jmap工具

```bash
# 查看堆中对象统计
jmap -histo <pid>

# 示例输出
 num     #instances         #bytes  class name
----------------------------------------------
   1:         12345        1234567  java.lang.String
   2:          5678         567890  java.util.HashMap
   3:          3456         345678  com.example.User
```

---

### 使用jconsole监控

```bash
# 启动jconsole
jconsole

# 连接到Java进程
# 查看"内存"标签页，观察对象数量和内存变化
```

---

## 常见问题与误区

### ❌ 误区1：System.gc()立即回收垃圾

**真相**：
- `System.gc()` 只是 **建议** JVM执行GC
- JVM可以忽略这个建议
- 即使执行GC，也不保证立即完成

---

### ❌ 误区2：finalize()可以替代资源清理

**真相**：
- finalize()执行时机不确定
- 不保证一定会执行
- 应使用try-finally或try-with-resources

---

### ❌ 误区3：不可达对象立即回收

**真相**：
- 不可达对象需要经过两次标记
- 如果有finalize()，需要等待执行
- 回收时机由GC算法决定

---

## 总结

### 核心要点

1. **垃圾 = 不再被使用的对象 = 不可达对象**

2. **引用计数法**：简单但无法解决循环引用（Java不使用）

3. **可达性分析法**：从GC Roots出发，能到达的对象存活（Java使用）

4. **GC Roots包括**：虚拟机栈、静态变量、常量、本地方法栈、同步锁等

5. **对象回收需要两次标记**：可达性分析 + finalize()判定

6. **finalize()不推荐使用**：性能差、不确定、有安全问题

7. **方法区也会回收**：废弃常量和无用类（条件苛刻）

### 与下篇文章的衔接

下一篇文章，我们将深入对比 **引用计数法 vs 可达性分析法**，理解两种算法的详细工作原理、优缺点，以及GC Roots的完整类型。

---

## 参考资料

- 《深入理解Java虚拟机（第3版）》- 周志明
- [Java虚拟机规范（Java SE 8版）](https://docs.oracle.com/javase/specs/jvms/se8/html/)
- [HotSpot GC算法](https://docs.oracle.com/en/java/javase/11/gctuning/)

---

> **下一篇预告**：《引用计数法 vs 可达性分析：两种判断算法对比》
> 深入对比两种对象存活判定算法，理解GC Roots的完整类型和可达性分析的详细过程。
