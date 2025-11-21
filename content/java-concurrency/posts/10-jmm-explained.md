---
title: "Java并发10：Java内存模型(JMM) - 抽象的内存模型"
date: 2025-11-20T16:30:00+08:00
draft: false
tags: ["Java并发", "JMM", "内存模型", "主内存", "工作内存"]
categories: ["技术"]
description: "深入理解Java内存模型（JMM）的设计理念、主内存与工作内存的交互、8种内存操作，以及JMM如何解决可见性和有序性问题。"
series: ["Java并发编程从入门到精通"]
weight: 10
stage: 2
stageTitle: "内存模型与原子性篇"
---

## 引言：从硬件到Java的抽象

在上一篇文章中，我们学习了CPU缓存、MESI协议、False Sharing等硬件层面的并发机制。但问题来了：

**作为Java开发者，我们需要关心这些底层细节吗？**

看这个例子：

```java
public class VisibilityProblem {
    private boolean flag = false;
    private int data = 0;

    // 线程1
    public void writer() {
        data = 42;        // 1
        flag = true;      // 2
    }

    // 线程2
    public void reader() {
        if (flag) {       // 3
            int result = data;  // 4
            System.out.println(result); // 可能输出0！
        }
    }
}
```

**三个疑问**：
1. 为什么线程2可能看不到`flag = true`？（**可见性问题**）
2. 为什么即使看到`flag = true`，也可能读到`data = 0`？（**有序性问题**）
3. 这个行为在不同CPU上是否一致？（**平台差异**）

**Java的解决方案：Java内存模型（JMM）**

JMM就像一份**"合同"**：
- 对JVM实现者：规定必须遵守的行为规范
- 对Java程序员：提供统一的并发语义保证
- **屏蔽平台差异**：无论x86、ARM还是RISC-V，行为一致

本篇文章，我们将深入理解JMM的设计理念和工作机制。

---

## 一、为什么需要Java内存模型？

### 1.1 硬件层面的挑战

不同CPU架构的内存模型差异巨大：

| CPU架构 | 内存模型 | Store-Load重排序 | 说明 |
|---------|---------|-----------------|------|
| **x86/x64** | TSO (Total Store Order) | **否** | 较强的内存模型，大部分情况有序 |
| **ARM** | Weak | **是** | 弱内存模型，重排序激进 |
| **RISC-V** | RVWMO | **是** | 类似ARM，弱内存模型 |
| **PowerPC** | Weak | **是** | 弱内存模型 |

**示例**：同样的Java代码，在x86上可能正常，在ARM上可能出错！

```java
// x86上可能正常工作
public class DataRace {
    int a = 0;
    int b = 0;

    public void method1() {
        a = 1;  // x86通常不会重排序
        b = 1;
    }

    public void method2() {
        if (b == 1) {
            assert a == 1; // x86上通常成立
                          // ARM上可能失败！
        }
    }
}
```

**问题**：如果让程序员关心CPU架构，代码就无法跨平台了！

### 1.2 JMM的设计目标

JMM要在两个矛盾的目标间取得平衡：

```
       强一致性（性能低）
              ↑
              │
    ┌─────────┴─────────┐
    │        JMM        │  ← 在这里取得平衡
    │   程序员友好       │
    │   +              │
    │   性能可接受       │
    └─────────┬─────────┘
              │
              ↓
       弱一致性（性能高）
```

**设计原则**：
1. **跨平台一致性**：屏蔽硬件差异
2. **正确性保证**：提供必要的同步语义
3. **性能优化空间**：允许编译器和CPU优化
4. **程序员友好**：不需要理解底层细节

### 1.3 JMM的两个关键抽象

JMM定义了两个抽象概念：

#### 1. 主内存（Main Memory）
- 所有线程**共享**的内存区域
- 存储共享变量的**主副本**
- 类似CPU的主内存（RAM）

#### 2. 工作内存（Working Memory）
- 每个线程**私有**的内存区域
- 存储共享变量的**本地副本**
- 类似CPU的L1/L2缓存

**示意图**：
```
┌─────────────────────────────────────────────────┐
│                  主内存 (Main Memory)            │
│  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐       │
│  │ 变量A│  │ 变量B│  │ 变量C│  │ 变量D│       │
│  └──┬───┘  └──┬───┘  └──┬───┘  └──┬───┘       │
└─────┼────────┼────────┼────────┼───────────────┘
      │        │        │        │
      ↓        ↓        ↓        ↓
┌─────────────────────────────────────────────────┐
│  线程1工作内存     │    线程2工作内存           │
│  ┌──────┐         │    ┌──────┐               │
│  │变量A │         │    │变量C │               │
│  │(副本)│         │    │(副本)│               │
│  └──────┘         │    └──────┘               │
│       ↕           │         ↕                  │
│  ┌────────┐       │    ┌────────┐             │
│  │ 线程1  │       │    │ 线程2  │             │
│  └────────┘       │    └────────┘             │
└─────────────────────────────────────────────────┘
```

**关键点**：
- 线程**不能直接访问主内存**
- 线程**只能读写自己的工作内存**
- 线程间通信必须通过**主内存中转**

---

## 二、JMM的8种内存操作

JMM定义了8种原子性的内存操作，用于在主内存和工作内存之间传输数据。

### 2.1 8种操作详解

| 操作 | 作用域 | 说明 |
|-----|-------|------|
| **lock** | 主内存 | 把变量标识为线程独占状态 |
| **unlock** | 主内存 | 释放锁定的变量，其他线程可以锁定 |
| **read** | 主内存 | 把变量从主内存读取到工作内存（传输） |
| **load** | 工作内存 | 把read的值放入工作内存的变量副本 |
| **use** | 工作内存 | 把工作内存的变量值传给执行引擎 |
| **assign** | 工作内存 | 把执行引擎的值赋给工作内存的变量 |
| **store** | 工作内存 | 把工作内存的变量值传送到主内存（传输） |
| **write** | 主内存 | 把store的值写入主内存的变量 |

### 2.2 操作的执行规则

JMM规定这些操作必须遵守的规则：

#### 规则1：read-load、store-write成对出现
```
read必须与load配对使用（但不要求连续）
store必须与write配对使用（但不要求连续）
```

#### 规则2：assign-store顺序
```
不允许一个变量在工作内存被assign后，不同步到主内存
```

#### 规则3：use-load顺序
```
不允许一个变量在工作内存未初始化就use
```

### 2.3 变量读写的完整流程

#### 读操作流程

```
线程1读取变量x的值：

1. 主内存 read x ─────→ 传输 ─────→ 2. 工作内存 load x
                                            ↓
                                    3. 工作内存变量副本 x
                                            ↓
                                    4. use x (传给执行引擎)
                                            ↓
                                    5. 执行引擎使用 x
```

**代码示例**：
```java
public void reader() {
    int value = x;  // read → load → use
}
```

#### 写操作流程

```
线程1修改变量x的值：

1. 执行引擎计算新值
        ↓
2. assign x (赋值给工作内存)
        ↓
3. 工作内存变量副本 x
        ↓
4. store x ─────→ 传输 ─────→ 5. 主内存 write x
```

**代码示例**：
```java
public void writer() {
    x = 42;  // assign → store → write
}
```

### 2.4 可见性问题的本质

**问题场景**：
```java
public class VisibilityDemo {
    private int x = 0;

    // 线程1
    public void writer() {
        x = 42;
        // assign → store → write
        // 但什么时候write？不确定！
    }

    // 线程2
    public void reader() {
        int value = x;
        // read → load → use
        // 但什么时候read？不确定！
        System.out.println(value); // 可能是0，也可能是42
    }
}
```

**时序图分析**：
```
时间轴  线程1（writer）           线程2（reader）
t1     assign x = 42
t2     store x                  read x = 0 (从主内存读取旧值)
t3     write x = 42             load x = 0
t4                              use x = 0
t5                              输出：0 (错误！)
```

**根本原因**：
- 线程1的`write`和线程2的`read`没有同步
- JMM不保证何时将工作内存的修改刷新到主内存
- 线程2可能读到旧值

---

## 三、synchronized的JMM语义

### 3.1 synchronized对内存的影响

**JMM规定**：

#### 进入synchronized（加锁）
```
1. 清空工作内存中的变量
2. 从主内存重新read+load最新值
→ 保证可见性
```

#### 退出synchronized（解锁）
```
1. 将工作内存中的变量store+write到主内存
→ 保证修改对其他线程可见
```

### 3.2 synchronized的完整语义

```java
public class SynchronizedDemo {
    private int x = 0;
    private int y = 0;

    public synchronized void writer() {
        // 【进入synchronized】
        // 1. 清空工作内存
        // 2. 从主内存重新加载所有变量

        x = 1;
        y = 2;

        // 【退出synchronized】
        // 1. 将所有修改刷新到主内存
        // 2. 释放锁
    }

    public synchronized void reader() {
        // 【进入synchronized】
        // 1. 获取锁
        // 2. 从主内存重新加载所有变量（看到最新值）

        int a = x;  // 一定读到1
        int b = y;  // 一定读到2
    }
}
```

**关键保证**：
- **互斥性**：同一时刻只有一个线程执行
- **可见性**：释放锁时刷新所有变量到主内存
- **有序性**：加锁前后不能重排序

### 3.3 synchronized的内存语义图

```
线程1 (writer)                线程2 (reader)
     │                             │
     ├─ synchronized (lock) {      │
     │                             │
     │  清空工作内存                │
     │       ↓                     │
     │  从主内存加载                │
     │       ↓                     │
     │  x = 1; y = 2;              │
     │  (在工作内存修改)            │
     │       ↓                     │
     │  刷新到主内存 ───────────┐  │
     │                         │  │
     ├─ } (unlock)             │  │
     │                         │  │
     │                         ↓  │
     │                      主内存 │
     │                    x=1,y=2 │
     │                         ↓  │
     │                         │  ├─ synchronized (lock) {
     │                         │  │
     │                         │  │  清空工作内存
     │                         │  │       ↓
     │                         └──│  从主内存加载最新值
     │                            │       ↓
     │                            │  int a = x; // 读到1
     │                            │  int b = y; // 读到2
     │                            │
     │                            ├─ } (unlock)
```

---

## 四、volatile的JMM语义

### 4.1 volatile的两个作用

#### 作用1：保证可见性

**规则**：
- **volatile写**：立即刷新到主内存（store + write）
- **volatile读**：总是从主内存读取（read + load）

```java
public class VolatileDemo {
    private volatile boolean flag = false;

    // 线程1
    public void writer() {
        flag = true;  // volatile写
        // → assign
        // → store (立即)
        // → write (立即)
    }

    // 线程2
    public void reader() {
        while (!flag) {  // volatile读
            // → read (强制从主内存)
            // → load
            // → use
        }
        // 一定能看到flag=true
    }
}
```

#### 作用2：禁止指令重排序

**内存屏障（Memory Barrier）**：

```java
int a = 1;           // 普通写
int b = 2;           // 普通写
volatile int c = 3;  // volatile写
                     // ← 插入StoreStore屏障
                     //   禁止前面的写与后面的写重排序
int d = 4;           // 普通写
```

**4种内存屏障**：

| 屏障类型 | 指令示例 | 说明 |
|---------|---------|------|
| **LoadLoad** | Load1; LoadLoad; Load2 | 禁止Load1与Load2重排序 |
| **StoreStore** | Store1; StoreStore; Store2 | 禁止Store1与Store2重排序 |
| **LoadStore** | Load1; LoadStore; Store2 | 禁止Load1与Store2重排序 |
| **StoreLoad** | Store1; StoreLoad; Load2 | 禁止Store1与Load2重排序（最昂贵）|

### 4.2 volatile插入屏障的规则

JMM对volatile的插入策略：

#### volatile写

```
普通写
普通写
        ← StoreStore屏障（禁止前面的写重排序到后面）
volatile写
        ← StoreLoad屏障（禁止后面的读写重排序到前面）
普通读/写
```

#### volatile读

```
普通读/写
        ← LoadLoad屏障（禁止后面的读重排序到前面）
        ← LoadStore屏障（禁止后面的写重排序到前面）
volatile读
普通读
普通写
```

### 4.3 DCL单例模式的正确实现

**错误版本**（不加volatile）：
```java
public class Singleton {
    private static Singleton instance;

    public static Singleton getInstance() {
        if (instance == null) {              // 第1次检查
            synchronized (Singleton.class) {
                if (instance == null) {      // 第2次检查
                    instance = new Singleton(); // 问题在这里！
                    // 可能的执行顺序：
                    // 1. 分配内存
                    // 2. instance指向内存（未初始化）← 重排序
                    // 3. 初始化对象
                    //
                    // 线程B可能看到未初始化的对象！
                }
            }
        }
        return instance;
    }
}
```

**正确版本**（加volatile）：
```java
public class Singleton {
    private static volatile Singleton instance; // 加volatile

    public static Singleton getInstance() {
        if (instance == null) {
            synchronized (Singleton.class) {
                if (instance == null) {
                    instance = new Singleton();
                    // volatile禁止重排序：
                    // 1. 分配内存
                    // 2. 初始化对象
                    // 3. instance指向内存
                    // ← StoreStore屏障保证顺序
                }
            }
        }
        return instance;
    }
}
```

**内存屏障分析**：
```java
// new Singleton()实际执行
memory = allocate();      // 1. 分配内存
                          ← StoreStore屏障
ctorInstance(memory);     // 2. 初始化对象（不能重排到3后面）
                          ← StoreStore屏障
instance = memory;        // 3. 赋值（volatile写）
                          ← StoreLoad屏障
```

---

## 五、final的JMM语义

### 5.1 final字段的特殊保证

**JMM规定**：
1. 在构造函数内对final字段的写入，与随后把这个对象的引用赋值给其他变量，这两个操作**不能重排序**
2. 初次读对象引用，与读该对象包含的final字段，这两个操作**不能重排序**

**示例**：
```java
public class FinalDemo {
    private final int x;
    private int y;

    public FinalDemo() {
        x = 1;  // final字段写入
        y = 2;  // 普通字段写入
    }
    // 构造函数结束后，final字段保证对所有线程可见
}

// 线程1
FinalDemo obj = new FinalDemo();
// JMM保证：
// 1. x=1 和 y=2 不会重排序到构造函数外
// 2. obj赋值不会重排序到构造函数执行之前

// 线程2
if (obj != null) {
    int a = obj.x;  // 保证读到1（final语义）
    int b = obj.y;  // 可能读到0（普通字段，没保证）
}
```

### 5.2 final的内存屏障

```java
public FinalDemo() {
    x = 1;  // final字段
            ← StoreStore屏障
    y = 2;  // 普通字段
}           ← StoreStore屏障（针对final）
            // 构造函数结束

// 对象引用赋值
obj = new FinalDemo();
```

### 5.3 不可变对象的线程安全

**不可变对象**天然线程安全：
```java
public final class ImmutablePoint {
    private final int x;
    private final int y;

    public ImmutablePoint(int x, int y) {
        this.x = x;
        this.y = y;
    }

    public int getX() { return x; }
    public int getY() { return y; }
}

// 线程安全，无需同步！
ImmutablePoint point = new ImmutablePoint(10, 20);
```

**原因**：
1. final字段构造后不可变
2. JMM保证构造后对所有线程可见
3. 没有共享可变状态

---

## 六、JMM与硬件内存模型的关系

### 6.1 JMM是如何实现的？

JMM是抽象规范，底层通过**内存屏障指令**实现：

| JMM抽象 | x86实现 | ARM实现 |
|---------|---------|---------|
| volatile写 | 无需指令（TSO模型强序） | `dmb st`（数据内存屏障） |
| volatile读 | 无需指令 | `dmb ld` |
| synchronized | `lock`前缀指令 | `dmb`指令 |
| final | 无需指令 | `dmb st` |

### 6.2 x86 vs ARM的差异

#### x86（强内存模型）
```java
// x86的TSO模型不会重排序Store-Load之外的操作
int a = 1;  // Store
int b = 2;  // Store
            // x86保证不重排序

// volatile在x86上几乎无开销
```

#### ARM（弱内存模型）
```java
// ARM可能重排序任何操作
int a = 1;  // Store
int b = 2;  // Store
            // ARM可能重排序！

// 需要插入内存屏障
```

### 6.3 JVM如何处理平台差异？

**编译器策略**：
```
Java源码
    ↓
字节码（平台无关）
    ↓
JIT编译
    ↓
┌──────────┬──────────┐
│   x86    │   ARM    │
├──────────┼──────────┤
│ 少量屏障 │ 大量屏障 │
│ 性能高   │ 性能稍低 │
└──────────┴──────────┘
```

**示例**（volatile long的读写）：
```java
volatile long x;

// x86汇编（简化）
movq %rax, (%rbx)    // Store（无需屏障）

// ARM汇编（简化）
dmb st               // StoreStore屏障
str x0, [x1]         // Store
dmb                  // StoreLoad屏障
```

---

## 七、JMM的核心原则

### 7.1 happens-before关系（预告）

**定义**：如果操作A happens-before 操作B，那么A的结果对B可见。

**8条规则**（下一篇详细讲解）：
1. **程序顺序规则**：单线程内，前面的操作happens-before后面的操作
2. **锁定规则**：unlock happens-before 后续的lock
3. **volatile规则**：volatile写happens-before后续的volatile读
4. **传递性**：A hb B，B hb C → A hb C
5. **线程启动规则**：Thread.start() happens-before线程的所有操作
6. **线程终止规则**：线程的所有操作happens-before Thread.join()
7. **中断规则**：interrupt() happens-before检测到中断
8. **对象终结规则**：构造函数结束happens-before finalize()

### 7.2 as-if-serial语义

**定义**：不管怎么重排序，单线程的执行结果不能改变。

```java
// 编译器可以重排序
int a = 1;  // 可以与下一行重排序
int b = 2;

int c = a + b;  // 不能重排序到前两行之前（依赖关系）
```

**限制**：
- 存在数据依赖的操作不能重排序
- 单线程内结果必须正确

### 7.3 程序员的心智模型

**顺序一致性模型（理想模型）**：
```
所有操作按程序顺序执行
所有线程看到相同的执行顺序
↓
但性能极差！
```

**JMM的权衡**：
```
默认：允许重排序优化（性能）
  ↓
使用volatile/synchronized：禁止重排序（正确性）
```

**程序员只需记住**：
- 正确使用synchronized/volatile
- 无需关心底层CPU架构
- JMM保证跨平台一致性

---

## 八、实战案例分析

### 案例1：可见性问题

**问题代码**：
```java
public class VisibilityBug {
    private boolean stop = false;

    public void run() {
        new Thread(() -> {
            while (!stop) {
                // 可能永远循环
                doWork();
            }
        }).start();

        Thread.sleep(1000);
        stop = true;  // 可能不可见
    }
}
```

**原因**：
- `stop`的修改在工作内存
- 没有刷新到主内存
- 读线程一直读旧值

**解决方案**：
```java
private volatile boolean stop = false;  // 加volatile
```

### 案例2：指令重排序问题

**问题代码**：
```java
public class ReorderBug {
    private int x = 0;
    private boolean ready = false;

    public void writer() {
        x = 42;         // 1
        ready = true;   // 2  可能重排序到1之前
    }

    public void reader() {
        if (ready) {    // 3
            assert x == 42;  // 可能失败！
        }
    }
}
```

**时序分析**：
```
重排序后的执行顺序：
线程1: ready = true (2) → x = 42 (1)
线程2: 读到ready=true (3) → 读到x=0 (4)
```

**解决方案**：
```java
private int x = 0;
private volatile boolean ready = false;  // 加volatile

public void writer() {
    x = 42;         // 1
                    ← StoreStore屏障
    ready = true;   // 2  不会重排序到1之前
}
```

### 案例3：双重检查锁定

已在前面详细分析，这里总结：

**问题**：对象初始化与引用赋值可能重排序
**解决**：使用volatile禁止重排序
**关键**：StoreStore屏障保证初始化在赋值之前完成

---

## 九、总结

### 9.1 核心要点

1. **JMM是抽象规范**
   - 屏蔽硬件差异
   - 提供统一的并发语义
   - 在性能和正确性间权衡

2. **主内存与工作内存**
   - 线程不能直接访问主内存
   - 通过8种操作进行数据传输
   - 理解可见性问题的根源

3. **synchronized的内存语义**
   - 进入时：清空工作内存，重新加载
   - 退出时：刷新所有修改到主内存
   - 保证互斥性、可见性、有序性

4. **volatile的内存语义**
   - 写操作：立即刷新到主内存
   - 读操作：总是从主内存读取
   - 通过内存屏障禁止重排序

5. **final的内存语义**
   - 构造后对所有线程可见
   - 不可变对象天然线程安全

### 9.2 最佳实践

1. **优先使用不可变对象**
   ```java
   public final class ImmutableData {
       private final int value;
       // ...
   }
   ```

2. **正确使用volatile**
   ```java
   private volatile boolean flag;  // 状态标志
   private volatile Object instance;  // 引用
   ```

3. **正确使用synchronized**
   ```java
   public synchronized void update() {
       // 修改共享变量
   }
   ```

4. **避免复杂的同步逻辑**
   - 使用JUC工具类（后续文章详解）
   - 使用线程安全容器

### 9.3 思考题

1. 为什么volatile不能保证原子性？
2. synchronized和volatile的内存语义有什么区别？
3. JMM与CPU内存模型是什么关系？

### 9.4 下一篇预告

在理解了JMM的基本概念后，下一篇我们将深入学习**happens-before原则** —— JMM的核心规则，掌握如何判断程序是否线程安全。

---

## 扩展阅读

1. **JSR-133**：Java内存模型规范
   - http://www.cs.umd.edu/~pugh/java/memoryModel/

2. **论文**：
   - "The Java Memory Model" - Manson, Pugh, Adve (2005)
   - "Threads Cannot be Implemented as a Library" - Boehm (2005)

3. **书籍**：
   - 《Java并发编程实战》第16章：Java内存模型
   - 《深入理解Java虚拟机》第12章：Java内存模型与线程

4. **工具**：
   - JCStress：Java并发压力测试工具
   - hsdis：HotSpot反汇编插件

5. **在线资源**：
   - Aleksey Shipilëv的博客
   - Doug Lea的并发编程文章

---

**系列文章**：
- 上一篇：[Java并发09：CPU缓存与多核架构](/java-concurrency/posts/09-cpu-cache-and-multicore/)
- 下一篇：[Java并发11：happens-before原则](/java-concurrency/posts/11-happens-before/) （即将发布）
