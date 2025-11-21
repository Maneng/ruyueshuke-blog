---
title: "Java并发11：happens-before原则 - JMM的核心规则"
date: 2025-11-20T17:00:00+08:00
draft: false
tags: ["Java并发", "happens-before", "JMM", "可见性", "有序性"]
categories: ["技术"]
description: "深入理解happens-before原则的8条规则，掌握如何判断程序是否线程安全，以及如何利用happens-before建立正确的并发语义。"
series: ["Java并发编程从入门到精通"]
weight: 11
stage: 2
stageTitle: "内存模型与原子性篇"
---

## 引言：如何判断程序是否线程安全？

看这段代码，能否确定线程安全？

```java
public class DataRace {
    private int data = 0;
    private boolean ready = false;

    // 线程1
    public void writer() {
        data = 42;        // 1
        ready = true;     // 2
    }

    // 线程2
    public void reader() {
        if (ready) {      // 3
            System.out.println(data);  // 4  一定输出42吗？
        }
    }
}
```

**三个问题**：
1. 线程2能看到`ready = true`吗？（可见性）
2. 如果看到`ready = true`，能保证看到`data = 42`吗？（有序性）
3. 如何用**形式化的规则**判断？

传统方法是分析各种可能的执行顺序，但这太复杂了！

**JMM的解决方案：happens-before原则**

**happens-before**是JMM的核心规则，它定义了：
- 什么时候一个操作的结果对另一个操作可见
- 什么时候两个操作不能重排序
- 如何建立正确的并发语义

掌握happens-before原则，就能快速判断程序是否线程安全。

---

## 一、happens-before的定义

### 1.1 形式化定义

**happens-before关系**（简写为 hb）：

如果操作A happens-before 操作B，记作 `A hb B`，则：

1. **可见性保证**：A的结果对B可见
2. **有序性保证**：A在B之前执行（从程序语义角度）

**注意**：
- `A hb B` **不代表**A在时间上一定先于B执行
- `A hb B` **代表**A的结果对B可见，且不会被重排序到B之后

### 1.2 happens-before vs 时间先后

**误区**：happens-before = 时间先后？

**错误示例**：
```java
int x = 0;
int y = 0;

// 线程1
x = 1;  // A
y = 2;  // B

// 程序顺序规则：A hb B
// 但实际执行时，B可能在A之前（指令重排序）
// 只要结果不变，这是允许的！
```

**正确理解**：
```
happens-before定义的是可见性关系，不是时间先后关系

A hb B 的含义：
1. 如果B要读A写的变量，保证B能看到A的结果
2. A和B不会被重排序（从程序语义角度）
3. 但A和B可能在时间上乱序执行（只要不违反1和2）
```

### 1.3 为什么需要happens-before？

**传统方法**：分析所有可能的执行顺序
```java
// 线程1: A → B
// 线程2: C → D

可能的执行顺序：
A → B → C → D
A → C → B → D
A → C → D → B
C → A → B → D
C → A → D → B
C → D → A → B
... 太多了！
```

**happens-before方法**：用规则判断
```java
// 只需判断：
是否存在 hb 关系？
- A hb B （程序顺序规则）
- C hb D （程序顺序规则）
- 是否有跨线程的 hb 关系？
  → 如果没有，就不是线程安全的！
```

---

## 二、happens-before的8条规则

JMM定义了8条happens-before规则，这是判断并发程序正确性的核心工具。

### 规则1：程序顺序规则（Program Order Rule）

**定义**：在单个线程中，按照程序顺序，前面的操作 happens-before 后面的操作。

```java
// 单线程
int a = 1;     // 操作A
int b = 2;     // 操作B
int c = a + b; // 操作C

// happens-before关系：
A hb B
B hb C
A hb C（传递性）
```

**关键点**：
- 只针对**单个线程**内
- 与实际执行顺序无关（可能重排序）
- 但语义上A的结果对B可见

**示例**：
```java
public void method() {
    int x = 1;          // 1
    int y = 2;          // 2
    int z = x + y;      // 3

    // happens-before链：
    // 1 hb 2 hb 3
    // 保证：z能看到x和y的值
}
```

**重排序限制**：
```java
int a = 1;          // 1
int b = 2;          // 2  可以与1重排序（无依赖）
int c = a + b;      // 3  不能重排序到1、2之前（有依赖）
```

---

### 规则2：锁定规则（Monitor Lock Rule）

**定义**：对一个锁的**unlock**操作 happens-before 后续对这个锁的**lock**操作。

```java
synchronized (lock) {
    // 操作A
}  // unlock

// 其他线程
synchronized (lock) {  // lock
    // 操作B
    // B能看到A的所有操作结果
}
```

**示意图**：
```
线程1                    线程2
  │                        │
  ├─ synchronized(lock) {  │
  │    x = 1;              │
  │  } ← unlock            │
  │        │               │
  │        │ hb            │
  │        ↓               │
  │                        ├─ synchronized(lock) { ← lock
  │                        │    int a = x; // 读到1
  │                        │  }
```

**完整示例**：
```java
public class LockDemo {
    private int data = 0;
    private final Object lock = new Object();

    public void writer() {
        synchronized (lock) {
            data = 42;      // A
        }  // unlock → hb → 后续的lock
    }

    public void reader() {
        synchronized (lock) {  // lock
            int value = data;  // B
            System.out.println(value); // 一定输出42
        }
    }
}
```

**happens-before链**：
```
writer中的A
    ↓
unlock
    ↓ hb
lock（reader）
    ↓
reader中的B

结论：A hb B，B能看到A的结果
```

---

### 规则3：volatile规则（Volatile Variable Rule）

**定义**：对volatile变量的**写操作** happens-before 后续对这个变量的**读操作**。

```java
volatile boolean flag = false;

// 线程1
flag = true;  // volatile写

// 线程2
if (flag) {   // volatile读
    // 能看到flag=true
}
```

**完整示例**：
```java
public class VolatileDemo {
    private int data = 0;
    private volatile boolean ready = false;

    public void writer() {
        data = 42;        // 1
        ready = true;     // 2 volatile写
    }

    public void reader() {
        if (ready) {      // 3 volatile读
            System.out.println(data);  // 4  一定输出42
        }
    }
}
```

**happens-before链**：
```
1. data = 42
   ↓ （程序顺序规则）
2. ready = true (volatile写)
   ↓ （volatile规则）
3. if (ready) (volatile读)
   ↓ （程序顺序规则）
4. println(data)

结论：1 hb 4，所以4能看到1的结果
```

**关键保证**：
```java
// 写线程
普通写          // A
普通写          // B
volatile写      // C
// volatile写前的所有操作，都 hb volatile读后的所有操作

// 读线程
volatile读      // D
普通读          // E
普通读          // F
```

---

### 规则4：传递性规则（Transitivity）

**定义**：如果 A hb B，且 B hb C，则 A hb C。

```java
A hb B
B hb C
───────
A hb C
```

**示例1**：程序顺序 + 传递性
```java
int x = 1;  // A
int y = 2;  // B
int z = 3;  // C

// A hb B（程序顺序规则）
// B hb C（程序顺序规则）
// A hb C（传递性）
```

**示例2**：volatile + 传递性
```java
private int x = 0;
private int y = 0;
private volatile int z = 0;

// 线程1
public void writer() {
    x = 1;      // A
    y = 2;      // B
    z = 3;      // C (volatile写)
}

// 线程2
public void reader() {
    int a = z;  // D (volatile读)
    int b = y;  // E
    int c = x;  // F
}

// happens-before链：
A hb B  (程序顺序规则)
B hb C  (程序顺序规则)
C hb D  (volatile规则)
D hb E  (程序顺序规则)
E hb F  (程序顺序规则)

// 传递性：
A hb C hb D hb E
→ A hb E  （E能看到A）

A hb C hb D hb F
→ A hb F  （F能看到A）
```

---

### 规则5：线程启动规则（Thread Start Rule）

**定义**：线程的`start()`方法 happens-before 该线程的所有操作。

```java
int x = 0;

Thread t = new Thread(() -> {
    int a = x;  // B  能看到x=42
});

x = 42;    // A
t.start(); // start() hb B
```

**完整示例**：
```java
public class ThreadStartDemo {
    private int data = 0;

    public void startThread() {
        data = 42;  // A

        Thread t = new Thread(() -> {
            // B：能看到data=42
            System.out.println(data);
        });

        t.start();  // start() hb B
    }
}
```

**happens-before链**：
```
A: data = 42
   ↓ （程序顺序规则）
start()
   ↓ （线程启动规则）
B: println(data)

结论：A hb B
```

---

### 规则6：线程终止规则（Thread Termination Rule）

**定义**：线程的所有操作 happens-before 其他线程检测到该线程已终止。

**检测终止的方式**：
- `Thread.join()`返回
- `Thread.isAlive()`返回false

```java
int x = 0;

Thread t = new Thread(() -> {
    x = 42;  // A
});

t.start();
t.join();  // 等待t终止
int a = x; // B  能看到x=42
```

**完整示例**：
```java
public class ThreadJoinDemo {
    private int result = 0;

    public void compute() throws InterruptedException {
        Thread t = new Thread(() -> {
            result = 42;  // A
        });

        t.start();
        t.join();  // join() hb B
        System.out.println(result);  // B  一定输出42
    }
}
```

**happens-before链**：
```
A: result = 42
   ↓ （线程内所有操作）
线程t终止
   ↓ （线程终止规则）
join()返回
   ↓ （程序顺序规则）
B: println(result)

结论：A hb B
```

---

### 规则7：中断规则（Thread Interruption Rule）

**定义**：对线程的`interrupt()`调用 happens-before 被中断线程检测到中断事件。

**检测中断的方式**：
- `Thread.interrupted()`
- `Thread.isInterrupted()`
- 抛出`InterruptedException`

```java
Thread t = new Thread(() -> {
    while (!Thread.currentThread().isInterrupted()) {  // B
        // 能看到中断标志
    }
});

t.start();
t.interrupt();  // A  hb B
```

**完整示例**：
```java
public class InterruptDemo {
    private volatile boolean stopped = false;

    public void run() {
        Thread t = new Thread(() -> {
            while (!Thread.currentThread().isInterrupted()) {
                if (stopped) {  // B
                    break;
                }
            }
        });

        t.start();

        // 一段时间后
        stopped = true;     // A1
        t.interrupt();      // A2  hb B
    }
}
```

---

### 规则8：对象终结规则（Finalizer Rule）

**定义**：对象的构造函数结束 happens-before 该对象的`finalize()`方法开始。

```java
public class FinalizeDemo {
    private int data;

    public FinalizeDemo() {
        data = 42;  // A
    }  // 构造函数结束

    @Override
    protected void finalize() {
        // B：能看到data=42
        System.out.println(data);
    }
}
```

**注意**：
- `finalize()`机制已被废弃（JDK 9+）
- 了解即可，实际开发中不要使用
- 推荐使用`try-with-resources`或`Cleaner`

---

## 三、happens-before的综合应用

### 3.1 案例1：单例模式DCL

**问题代码**：
```java
public class Singleton {
    private static Singleton instance;

    public static Singleton getInstance() {
        if (instance == null) {           // A (读)
            synchronized (Singleton.class) {
                if (instance == null) {   // B (读)
                    instance = new Singleton(); // C (写)
                }
            }
        }
        return instance;  // D (读)
    }
}
```

**happens-before分析**：
```
线程1（首次创建）：
A hb B  (程序顺序规则)
B hb C  (程序顺序规则)
C hb unlock (锁定规则)

线程2（后续读取）：
lock hb D (锁定规则)

问题：C hb D 吗？
→ 不一定！如果线程2不加锁，就没有hb关系
→ C的写入可能重排序，D可能看到未初始化的对象
```

**正确代码**（加volatile）：
```java
private static volatile Singleton instance;

// volatile规则：
// C (volatile写) hb D (volatile读)
// 建立了hb关系，线程安全！
```

### 3.2 案例2：生产者-消费者

```java
public class ProducerConsumer {
    private int data = 0;
    private volatile boolean ready = false;

    // 生产者
    public void produce() {
        data = 42;        // A
        ready = true;     // B (volatile写)
    }

    // 消费者
    public void consume() {
        while (!ready) {  // C (volatile读)
        }
        int value = data; // D
        System.out.println(value); // 一定输出42
    }
}
```

**happens-before链**：
```
A hb B  (程序顺序规则)
B hb C  (volatile规则)
C hb D  (程序顺序规则)

传递性：A hb D
结论：D能看到A的结果
```

### 3.3 案例3：CountDownLatch

```java
public class CountDownLatchDemo {
    private final CountDownLatch latch = new CountDownLatch(1);
    private int data = 0;

    // 线程1
    public void writer() {
        data = 42;     // A
        latch.countDown();  // B
    }

    // 线程2
    public void reader() throws InterruptedException {
        latch.await();  // C
        int value = data;  // D  能看到42吗？
    }
}
```

**happens-before分析**：
```
A hb B  (程序顺序规则)
B hb C  (CountDownLatch内部使用volatile/CAS，建立hb)
C hb D  (程序顺序规则)

传递性：A hb D
结论：线程安全
```

**原理**：
- `countDown()`内部使用`volatile`或`CAS`
- `await()`也会读取`volatile`变量
- 建立了happens-before关系

---

## 四、如何利用happens-before编写线程安全代码

### 4.1 判断线程安全的步骤

**步骤1：识别共享变量**
```java
private int sharedData = 0;  // 共享变量
```

**步骤2：找出所有访问共享变量的操作**
```java
// 线程1：写
sharedData = 42;

// 线程2：读
int value = sharedData;
```

**步骤3：判断是否存在happens-before关系**
```
写操作 hb 读操作？
→ 如果有，线程安全
→ 如果没有，数据竞争！
```

**步骤4：如果没有hb关系，建立hb关系**
- 使用`volatile`
- 使用`synchronized`
- 使用并发工具类

### 4.2 建立happens-before的几种方式

#### 方式1：volatile

```java
private volatile int data = 0;  // 加volatile

// 写线程
data = 42;  // volatile写

// 读线程
int value = data;  // volatile读
// volatile规则：写 hb 读
```

#### 方式2：synchronized

```java
private int data = 0;
private final Object lock = new Object();

// 写线程
synchronized (lock) {
    data = 42;  // A
}  // unlock

// 读线程
synchronized (lock) {  // lock
    int value = data;  // B
}
// 锁定规则：unlock hb lock
// A hb B
```

#### 方式3：使用并发容器

```java
private final ConcurrentHashMap<String, Integer> map = new ConcurrentHashMap<>();

// 写线程
map.put("key", 42);  // A

// 读线程
int value = map.get("key");  // B
// ConcurrentHashMap内部保证hb
```

### 4.3 常见错误模式

#### 错误1：没有建立hb关系

```java
private int data = 0;  // 没有volatile
private boolean ready = false;  // 没有volatile

// 写线程
data = 42;
ready = true;

// 读线程
if (ready) {
    System.out.println(data);  // 可能输出0！
}
// 没有hb关系，不安全
```

#### 错误2：hb关系不完整

```java
private int data = 0;
private volatile boolean ready = false;

// 写线程
ready = true;  // volatile写
data = 42;     // 在volatile写之后！

// 读线程
if (ready) {   // volatile读
    System.out.println(data);  // 可能输出0！
}
// 虽然有volatile，但顺序错误
// ready=true hb data=42（程序顺序）
// 但data=42不hb后面的读取
```

**正确写法**：
```java
// 写线程
data = 42;     // 先写数据
ready = true;  // 后写标志
// data=42 hb ready=true hb volatile读 hb println
```

#### 错误3：误以为普通变量有hb关系

```java
private int a = 0;
private int b = 0;

// 线程1
a = 1;
b = 2;

// 线程2
if (b == 2) {
    assert a == 1;  // 可能失败！
}
// 没有任何hb关系
```

---

## 五、happens-before与as-if-serial的区别

### 5.1 as-if-serial语义

**定义**：不管怎么重排序，单线程的执行结果不能改变。

```java
// 单线程
int a = 1;     // 可以与下一行重排序
int b = 2;
int c = a + b; // 不能重排序到前两行之前（有依赖）
```

**限制**：
- 只针对单线程
- 只保证**结果**不变
- 不保证**中间状态**

### 5.2 happens-before语义

**定义**：如果A hb B，则A的结果对B可见。

```java
// 多线程
volatile int a = 0;

// 线程1
a = 1;

// 线程2
int b = a;  // hb关系保证b=1
```

**保证**：
- 针对多线程
- 保证可见性
- 保证有序性

### 5.3 两者的关系

```
as-if-serial：单线程内的正确性保证
happens-before：多线程间的正确性保证

程序正确性 = as-if-serial + happens-before
```

---

## 六、实战技巧

### 6.1 快速判断技巧

**技巧1：检查共享变量**
```java
// 问题：这个类线程安全吗？
public class Counter {
    private int count = 0;  // 共享变量

    public void increment() {
        count++;  // 读+写
    }
}

// 判断：
// 1. 有共享变量：count
// 2. 多线程访问：increment()
// 3. 有hb关系吗？没有
// 结论：不安全
```

**技巧2：寻找同步点**
```java
// 有volatile？
// 有synchronized？
// 有Lock？
// 有并发工具类？
// → 有就是安全的，没有就不安全
```

**技巧3：画happens-before链**
```java
A → B → C (单线程)
    ↓ hb
    D → E (另一线程)

如果能连成链，就是安全的
```

### 6.2 调试技巧

**使用-XX:+PrintAssembly**
```bash
# 查看JIT生成的汇编代码
java -XX:+UnlockDiagnosticVMOptions \
     -XX:+PrintAssembly \
     -XX:CompileCommand=print,*ClassName.methodName \
     YourClass
```

**使用JCStress测试**
```java
@JCStressTest
@Outcome(id = "42", expect = Expect.ACCEPTABLE, desc = "Correct")
@Outcome(id = "0", expect = Expect.FORBIDDEN, desc = "Data race!")
public class VolatileTest {
    private volatile int x = 0;

    @Actor
    public void writer() {
        x = 42;
    }

    @Actor
    public void reader(I_Result r) {
        r.r1 = x;
    }
}
```

---

## 七、总结

### 7.1 核心要点

1. **happens-before定义**
   - A hb B：A的结果对B可见
   - 不是时间先后关系
   - 是JMM的核心规则

2. **8条规则**
   - 程序顺序规则：单线程内有序
   - 锁定规则：unlock hb lock
   - volatile规则：写 hb 读
   - 传递性：A hb B, B hb C → A hb C
   - 线程启动规则：start() hb 线程内操作
   - 线程终止规则：线程内操作 hb join()
   - 中断规则：interrupt() hb 检测中断
   - 终结规则：构造 hb finalize()

3. **判断线程安全的方法**
   - 找共享变量
   - 找所有访问点
   - 判断是否有hb关系
   - 没有就建立hb关系

4. **建立hb关系的方式**
   - volatile
   - synchronized
   - Lock
   - 并发工具类（内部已实现）

### 7.2 最佳实践

1. **优先使用高层并发工具**
   ```java
   // 推荐
   ConcurrentHashMap<String, Integer> map = new ConcurrentHashMap<>();

   // 不推荐（自己实现hb关系）
   Map<String, Integer> map = new HashMap<>();
   synchronized (map) { ... }
   ```

2. **正确使用volatile**
   ```java
   // ✓ 状态标志
   private volatile boolean stopped = false;

   // ✓ 双重检查锁定
   private static volatile Singleton instance;

   // ✗ 复合操作（不保证原子性）
   private volatile int count = 0;
   count++;  // 不安全！
   ```

3. **画happens-before链**
   - 复杂并发代码，画图分析
   - 确保每个共享变量访问都有hb关系

### 7.3 思考题

1. 为什么volatile不能保证原子性？（从hb角度解释）
2. 两个线程都只读一个volatile变量，需要建立hb关系吗？
3. `Thread.start()`和`Thread.join()`分别建立什么样的hb关系？

### 7.4 下一篇预告

在理解了happens-before原则后，下一篇我们将深入学习**volatile关键字** —— 它是如何通过内存屏障实现可见性和有序性保证的。

---

## 扩展阅读

1. **JSR-133**：Java内存模型规范
   - happens-before的正式定义

2. **论文**：
   - "The Java Memory Model" - Manson, Pugh, Adve

3. **书籍**：
   - 《Java并发编程实战》第16章
   - 《深入理解Java虚拟机》第12章

4. **工具**：
   - JCStress：并发正确性测试
   - hsdis：查看汇编代码

5. **在线资源**：
   - Doug Lea的JSR-133 Cookbook
   - Aleksey Shipilëv的博客

---

**系列文章**：
- 上一篇：[Java并发10：Java内存模型(JMM)详解](/java-concurrency/posts/10-jmm-explained/)
- 下一篇：[Java并发12：volatile关键字深度解析](/java-concurrency/posts/12-volatile-deep-dive/) （即将发布）
