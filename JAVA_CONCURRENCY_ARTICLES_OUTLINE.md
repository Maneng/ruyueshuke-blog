# Java 并发编程系列 - 详细文章大纲

> 本文档为每篇文章提供详细的内容大纲，包括引言场景、核心知识点、代码示例要点、总结要点

---

## 📚 第一阶段：并发基础篇（8篇）

### 01 - 为什么需要并发编程：从单线程到多线程的演进

**引言场景**：
一个Web服务器处理用户请求的故事：
- 单线程版本：一次只能处理一个请求，其他用户等待
- 多线程版本：同时处理多个请求，响应速度飞跃提升

**第一部分：计算机的性能差距**
- CPU速度：GHz级别
- 内存速度：纳秒级别
- 磁盘IO：毫秒级别
- 网络IO：更慢
- **关键图表**：CPU vs 内存 vs IO的性能差距对比图

**第二部分：为什么需要并发**
1. **提高CPU利用率**
   - 在等待IO时，CPU可以做其他事情
   - 示例：下载文件时可以继续编辑文档
2. **提升程序响应速度**
   - Web服务器同时处理多个请求
   - GUI程序在计算时界面不卡顿
3. **充分利用多核CPU**
   - 单线程只能用一个核
   - 多线程可以并行执行

**第三部分：并发 vs 并行**
- **并发（Concurrency）**：多个任务交替执行（逻辑上同时）
- **并行（Parallelism）**：多个任务真正同时执行（物理上同时）
- **示例图**：单核的并发 vs 多核的并行

**第四部分：阿姆达尔定律**
- 公式讲解
- 实际意义：不是所有任务都能无限加速
- **代码示例**：计算不同并行比例下的加速比

**第五部分：并发带来的问题**
- 线程安全问题
- 性能开销（上下文切换）
- 复杂性增加
- **预告**：后续文章会详细讲解如何解决

**总结要点**：
- 并发是为了提高资源利用率和响应速度
- 并发≠并行
- 多核时代，并发编程是必备技能
- 并发也会带来新的挑战

**代码示例**：
```java
// 示例1：单线程Web服务器（伪代码）
// 示例2：多线程Web服务器（伪代码）
// 示例3：阿姆达尔定律计算器
```

---

### 02 - 进程与线程的本质：操作系统视角

**引言场景**：
Chrome浏览器的多进程架构：
- 每个标签页是一个进程
- 一个标签页崩溃不影响其他标签页
- 为什么Chrome选择多进程而不是多线程？

**第一部分：进程是什么**
- 定义：资源分配的基本单位
- 进程的组成：代码段、数据段、堆、栈、文件描述符等
- **示意图**：进程的内存布局
- 进程间是相互隔离的

**第二部分：线程是什么**
- 定义：CPU调度的基本单位
- 线程的组成：程序计数器、栈、局部变量
- **关键点**：同一进程的线程共享进程资源
- **示意图**：一个进程内的多个线程

**第三部分：进程 vs 线程**
| 对比维度 | 进程 | 线程 |
|---------|------|------|
| 资源占用 | 重量级（MB级） | 轻量级（KB级） |
| 创建速度 | 慢 | 快 |
| 切换开销 | 大 | 小 |
| 通信方式 | IPC（复杂） | 共享内存（简单但易出错） |
| 隔离性 | 强（崩溃不影响其他进程） | 弱（一个线程崩溃导致整个进程崩溃） |

**第四部分：上下文切换**
- 什么是上下文切换
- 为什么上下文切换有开销
- 进程切换 vs 线程切换的开销对比
- **测试代码**：测量上下文切换的开销

**第五部分：Java中的线程**
- Java线程是对操作系统线程的封装
- JVM线程模型
- 线程与内核线程的映射关系

**第六部分：协程（扩展）**
- 什么是协程
- 用户态线程 vs 内核态线程
- Java的虚拟线程（Loom项目）
- **展望**：未来的并发编程

**总结要点**：
- 进程是资源分配单位，线程是调度单位
- 线程更轻量，但共享资源带来线程安全问题
- 理解底层原理有助于写出高性能代码

**代码示例**：
```java
// 示例1：创建进程（ProcessBuilder）
// 示例2：创建线程
// 示例3：测量上下文切换开销
```

---

### 03 - Java线程的生命周期：6种状态详解

**引言场景**：
生产环境CPU飙升到100%，使用jstack查看线程状态：
- 有些线程是RUNNABLE
- 有些线程是WAITING
- 有些线程是BLOCKED
- 这些状态是什么意思？如何分析？

**第一部分：线程的6种状态**
```java
public enum State {
    NEW,           // 新建
    RUNNABLE,      // 可运行
    BLOCKED,       // 阻塞
    WAITING,       // 等待
    TIMED_WAITING, // 超时等待
    TERMINATED     // 终止
}
```

**第二部分：状态详解**

#### 1. NEW（新建）
- 线程对象创建，但还没调用start()
- **代码示例**：Thread t = new Thread(...)

#### 2. RUNNABLE（可运行）
- 调用start()后进入该状态
- **注意**：RUNNABLE包含两种情况：
  - 正在运行（Running）
  - 就绪（Ready），等待CPU时间片
- 为什么Java不区分？（操作系统层面的细节对Java不可见）

#### 3. BLOCKED（阻塞）
- 等待获取synchronized锁
- **场景**：多个线程竞争同一个锁
- **代码示例**：synchronized导致的BLOCKED

#### 4. WAITING（等待）
- 调用以下方法会进入：
  - Object.wait()
  - Thread.join()
  - LockSupport.park()
- **关键**：需要被显式唤醒
- **代码示例**：wait/notify导致的WAITING

#### 5. TIMED_WAITING（超时等待）
- 调用带超时参数的方法：
  - Object.wait(long)
  - Thread.join(long)
  - Thread.sleep(long)
  - LockSupport.parkNanos()
- **关键**：超时后自动唤醒
- **代码示例**：sleep导致的TIMED_WAITING

#### 6. TERMINATED（终止）
- run()方法执行完毕
- 或者抛出未捕获的异常

**第三部分：状态转换图**
```
          start()
NEW ─────────────→ RUNNABLE ←──────────┐
                       │                │
                       │                │ notify/notifyAll
                       ↓                │ 或获取到锁
    获取锁失败 ──→ BLOCKED              │
                                        │
    wait()         ──→ WAITING ─────────┘
    join()
    park()
                                        │
    sleep(long)    ──→ TIMED_WAITING ───┘
    wait(long)
    join(long)
                       │
                       │ run()方法执行完毕
                       ↓
                  TERMINATED
```

**第四部分：实战：分析线程dump**
- 使用jstack获取线程dump
- 分析不同状态的线程
- **案例**：
  - 大量BLOCKED：锁竞争激烈
  - 大量WAITING：可能是线程池空闲
  - 大量RUNNABLE：CPU密集型任务

**第五部分：常见误区**
1. RUNNABLE ≠ 正在运行（可能在等待CPU）
2. BLOCKED vs WAITING的区别（一个是等锁，一个是等待通知）
3. sleep不会释放锁，wait会释放锁

**总结要点**：
- Java线程有6种状态
- 理解状态转换对排查问题至关重要
- BLOCKED和WAITING是两种不同的等待

**代码示例**：
```java
// 示例1：演示6种状态
// 示例2：状态转换示例
// 示例3：jstack分析示例
```

---

### 04 - 线程的创建与启动：4种方式对比

**引言场景**：
面试官：请说一下创建线程有哪几种方式？
候选人：继承Thread类、实现Runnable接口...还有吗？

**第一部分：4种创建线程的方式**

#### 方式1：继承Thread类
```java
class MyThread extends Thread {
    @Override
    public void run() {
        // 线程执行的代码
    }
}
MyThread t = new MyThread();
t.start();
```
**优点**：简单直观
**缺点**：
- Java单继承，无法继承其他类
- 违反组合优于继承原则

#### 方式2：实现Runnable接口
```java
class MyRunnable implements Runnable {
    @Override
    public void run() {
        // 线程执行的代码
    }
}
Thread t = new Thread(new MyRunnable());
t.start();
```
**优点**：
- 可以继承其他类
- 任务与线程分离，符合单一职责
- 可以被多个线程共享

**推荐**：优先使用这种方式

#### 方式3：实现Callable接口
```java
class MyCallable implements Callable<Integer> {
    @Override
    public Integer call() throws Exception {
        // 线程执行的代码
        return 42;
    }
}
FutureTask<Integer> task = new FutureTask<>(new MyCallable());
Thread t = new Thread(task);
t.start();
Integer result = task.get(); // 获取返回值
```
**优点**：
- 有返回值
- 可以抛出异常

**适用场景**：需要获取线程执行结果

#### 方式4：线程池（推荐）
```java
ExecutorService executor = Executors.newFixedThreadPool(10);
executor.submit(() -> {
    // 线程执行的代码
});
executor.shutdown();
```
**优点**：
- 线程复用，降低开销
- 便于管理和监控
- 避免资源耗尽

**推荐**：生产环境应该使用线程池

**第二部分：start() vs run()**
- **start()**：启动新线程，JVM调用run()
- **run()**：普通方法调用，不会启动新线程
- **错误示例**：调用run()而不是start()

**第三部分：Lambda表达式简化**
```java
// 传统写法
Thread t1 = new Thread(new Runnable() {
    @Override
    public void run() {
        System.out.println("Hello");
    }
});

// Lambda简化
Thread t2 = new Thread(() -> System.out.println("Hello"));
```

**第四部分：线程的命名**
```java
Thread t = new Thread(() -> {...}, "my-thread-name");
```
**重要性**：
- 便于问题排查
- jstack时能快速定位
- **最佳实践**：给线程起有意义的名字

**第五部分：守护线程 vs 用户线程**
```java
thread.setDaemon(true); // 设置为守护线程
```
- **用户线程**：JVM等待所有用户线程结束
- **守护线程**：JVM不等待守护线程结束
- **应用场景**：GC线程、监控线程

**总结要点**：
- 推荐使用Runnable接口或线程池
- 生产环境必须使用线程池
- 给线程起有意义的名字
- 理解start() vs run()的区别

**代码示例**：
```java
// 示例1：4种创建方式的完整示例
// 示例2：Callable返回值示例
// 示例3：线程命名最佳实践
// 示例4：守护线程示例
```

---

### 05 - 线程的中断机制：优雅地停止线程

**引言场景**：
有一个下载任务正在执行，用户点击了"取消"按钮：
- 如何优雅地停止这个线程？
- 为什么Thread.stop()被废弃？
- 什么是中断机制？

**第一部分：为什么不能用stop()**
```java
@Deprecated
public final void stop() {...}
```
- **废弃原因**：强制停止，不释放锁，可能导致数据不一致
- **案例**：银行转账时被stop()，账户数据错乱
- **结论**：永远不要使用stop()、suspend()、resume()

**第二部分：中断机制的核心概念**
- **中断不是强制停止**：只是一个"请求停止"的标志
- **线程自己决定**：是否响应中断
- **协作式**：需要线程配合检查中断标志

**第三部分：中断的三个方法**

#### 1. interrupt() - 设置中断标志
```java
thread.interrupt(); // 请求中断
```

#### 2. isInterrupted() - 检查中断标志
```java
if (Thread.currentThread().isInterrupted()) {
    // 处理中断
}
```

#### 3. interrupted() - 检查并清除中断标志
```java
if (Thread.interrupted()) {
    // 处理中断，标志被清除
}
```

**第四部分：如何响应中断**

#### 场景1：线程在运行（没有阻塞）
```java
public void run() {
    while (!Thread.currentThread().isInterrupted()) {
        // 执行任务
        doWork();
    }
    // 清理资源
    cleanup();
}
```

#### 场景2：线程在阻塞（sleep、wait等）
```java
public void run() {
    try {
        while (!Thread.currentThread().isInterrupted()) {
            Thread.sleep(1000);
            doWork();
        }
    } catch (InterruptedException e) {
        // 响应中断
        Thread.currentThread().interrupt(); // 恢复中断状态
    } finally {
        cleanup();
    }
}
```

**关键点**：
- sleep/wait等方法会抛出InterruptedException
- 抛出异常后，中断标志被清除
- **最佳实践**：捕获后恢复中断状态

**第五部分：不可中断的阻塞**
某些阻塞无法被中断：
- synchronized的阻塞
- Socket IO的阻塞

**解决方案**：
- 使用Lock.lockInterruptibly()代替synchronized
- 使用NIO代替BIO

**第六部分：典型应用场景**

#### 1. 超时任务
```java
Future<?> future = executor.submit(task);
try {
    future.get(5, TimeUnit.SECONDS);
} catch (TimeoutException e) {
    future.cancel(true); // 中断任务
}
```

#### 2. 批处理任务
```java
for (Task task : tasks) {
    if (Thread.interrupted()) {
        break; // 收到中断信号，停止处理
    }
    process(task);
}
```

**第七部分：常见错误**

❌ **错误1：吞掉InterruptedException**
```java
try {
    Thread.sleep(1000);
} catch (InterruptedException e) {
    // 什么都不做 - 错误！
}
```

✅ **正确做法**：
```java
try {
    Thread.sleep(1000);
} catch (InterruptedException e) {
    Thread.currentThread().interrupt(); // 恢复中断状态
    // 或者向上抛出
}
```

❌ **错误2：用flag代替中断**
```java
volatile boolean stop = false;
while (!stop) { // 不推荐
    ...
}
```

✅ **正确做法**：
```java
while (!Thread.currentThread().isInterrupted()) {
    ...
}
```

**总结要点**：
- 中断是协作式的，不是强制的
- 响应中断是线程的责任
- 捕获InterruptedException后要恢复中断状态
- 优先使用中断机制，而不是自定义flag

**代码示例**：
```java
// 示例1：正确响应中断
// 示例2：InterruptedException处理
// 示例3：超时任务取消
// 示例4：不可中断阻塞的替代方案
```

---

### 06 - 线程间通信：wait/notify机制详解

**引言场景**：
生产者-消费者问题：
- 生产者生产数据，放入队列
- 消费者从队列取数据
- 队列满时，生产者等待
- 队列空时，消费者等待
- 如何实现这种协作？

**第一部分：为什么需要线程间通信**
- 线程不是孤立的，需要协作完成任务
- 一个线程的输出是另一个线程的输入
- 需要一种机制来协调线程的执行

**第二部分：wait/notify的核心概念**
- **wait()**：释放锁，进入等待队列
- **notify()**：唤醒一个等待线程
- **notifyAll()**：唤醒所有等待线程

**关键约束**：
- 必须在synchronized块中调用
- 调用对象必须是同一个monitor对象

**第三部分：对象监视器（Monitor）**
```
每个Java对象都有一个Monitor：
┌─────────────────┐
│   对象头        │
├─────────────────┤
│   Mark Word     │ ← 包含锁信息
├─────────────────┤
│   Class Pointer │
├─────────────────┤
│   数据          │
└─────────────────┘

Monitor包含：
- 入口队列（Entry Set）：等待获取锁的线程
- 等待队列（Wait Set）：调用wait()的线程
- Owner：持有锁的线程
```

**第四部分：wait/notify工作流程**

#### wait()流程：
1. 检查当前线程是否持有锁（否则抛IllegalMonitorStateException）
2. 释放锁
3. 进入等待队列（Wait Set）
4. 线程进入WAITING状态
5. 被唤醒后，重新竞争锁
6. 获取锁后，从wait()返回

#### notify()流程：
1. 检查当前线程是否持有锁
2. 从等待队列中唤醒一个线程（具体哪个不确定）
3. 被唤醒的线程进入入口队列，竞争锁
4. **注意**：notify()不会立即释放锁

**第五部分：经典示例：生产者-消费者**

```java
class SharedQueue {
    private Queue<Integer> queue = new LinkedList<>();
    private int capacity = 10;

    public synchronized void produce(int value) throws InterruptedException {
        while (queue.size() == capacity) {
            wait(); // 队列满，等待
        }
        queue.offer(value);
        notifyAll(); // 唤醒消费者
    }

    public synchronized int consume() throws InterruptedException {
        while (queue.isEmpty()) {
            wait(); // 队列空，等待
        }
        int value = queue.poll();
        notifyAll(); // 唤醒生产者
        return value;
    }
}
```

**第六部分：关键要点**

#### 1. 为什么要用while而不是if？
```java
// ❌ 错误：使用if
if (queue.isEmpty()) {
    wait();
}
// 可能虚假唤醒，没有元素也会往下执行

// ✅ 正确：使用while
while (queue.isEmpty()) {
    wait();
}
// 被唤醒后再次检查条件
```

**虚假唤醒（Spurious Wakeup）**：
- 线程可能在没有notify的情况下被唤醒
- POSIX标准允许这种情况
- **最佳实践**：总是用while检查条件

#### 2. notify() vs notifyAll()
- **notify()**：唤醒一个线程（不确定是哪个）
- **notifyAll()**：唤醒所有线程
- **推荐**：大多数情况使用notifyAll()，避免死锁
- **例外**：确定只有一种类型的等待线程时，可以用notify()

#### 3. wait()必须在synchronized中
```java
// ❌ 错误
public void wrongWait() throws InterruptedException {
    obj.wait(); // IllegalMonitorStateException
}

// ✅ 正确
public void correctWait() throws InterruptedException {
    synchronized (obj) {
        obj.wait();
    }
}
```

**第七部分：wait() vs sleep()**
| wait() | sleep() |
|--------|---------|
| 释放锁 | 不释放锁 |
| Object的方法 | Thread的方法 |
| 需要synchronized | 不需要 |
| 需要notify唤醒 | 超时自动醒 |
| 进入WAITING | 进入TIMED_WAITING |

**第八部分：常见陷阱**

❌ **陷阱1：没有在循环中检查条件**
❌ **陷阱2：使用notify可能导致死锁**
❌ **陷阱3：wait的对象不对**
```java
synchronized (a) {
    b.wait(); // 错误！应该是a.wait()
}
```

**总结要点**：
- wait/notify必须在synchronized中使用
- 总是在while循环中调用wait
- 优先使用notifyAll而不是notify
- 理解虚假唤醒

**代码示例**：
```java
// 示例1：完整的生产者-消费者实现
// 示例2：虚假唤醒演示
// 示例3：notify vs notifyAll对比
// 示例4：常见错误演示
```

---

### 07 - 线程安全问题的本质：从一个计数器说起

**引言场景**：
一个简单的计数器程序：
```java
public class Counter {
    private int count = 0;
    public void increment() {
        count++;
    }
}
```
单线程运行：完美工作
多线程运行：结果不正确！
为什么一个简单的count++会有问题？

**第一部分：count++不是原子操作**

```java
count++; // 看似一行代码
```

实际上是3个步骤：
```
1. 读取count的值到寄存器   LOAD  [count], R1
2. 寄存器的值加1          ADD   R1, 1
3. 写回count             STORE R1, [count]
```

**时序图演示问题**：
```
时间  线程A                    线程B                count
t1   LOAD [count=0], R1                          0
t2                           LOAD [count=0], R1   0
t3   ADD R1, 1 (R1=1)                            0
t4                           ADD R1, 1 (R1=1)     0
t5   STORE R1 [count=1]                          1
t6                           STORE R1 [count=1]   1

期望结果：2
实际结果：1
```

**结论**：非原子操作 + 多线程 = 数据竞争

**第二部分：什么是线程安全**

**定义**：
当多个线程访问一个对象时，如果不用考虑这些线程的调度和交替执行，
也不需要额外的同步，调用方代码也不需要做任何协调，这个对象的行为
都是正确的，那么这个对象就是线程安全的。

**分类**：
1. **不可变对象**：String、Integer等（最安全）
2. **绝对线程安全**：Vector、Hashtable（已过时）
3. **相对线程安全**：ConcurrentHashMap
4. **线程兼容**：ArrayList（需要外部同步）
5. **线程对立**：很少见

**第三部分：线程安全问题的三种表现**

#### 1. 数据竞争（Data Race）
- 定义：多个线程同时访问共享变量，至少一个是写操作
- 示例：count++

#### 2. 竞态条件（Race Condition）
- 定义：程序的正确性依赖于线程的执行顺序
- 示例：单例模式的双重检查锁定

```java
// 不安全的单例
public class Singleton {
    private static Singleton instance;

    public static Singleton getInstance() {
        if (instance == null) {          // 线程1执行到这里
            instance = new Singleton();  // 线程2也执行到这里
        }
        return instance;
    }
}
```

#### 3. 可见性问题
- 定义：一个线程修改了变量，其他线程看不到
- 原因：CPU缓存

```java
public class VisibilityProblem {
    private boolean flag = false;

    // 线程1
    public void writer() {
        flag = true;
    }

    // 线程2
    public void reader() {
        while (!flag) {
            // 可能永远循环，因为看不到flag的变化
        }
    }
}
```

**第四部分：临界区（Critical Section）**
- **定义**：访问共享资源的代码段
- **要求**：同一时刻只能有一个线程执行
- **实现**：加锁

```java
public class SafeCounter {
    private int count = 0;

    public synchronized void increment() {
        count++; // 临界区
    }
}
```

**第五部分：共享变量 vs 局部变量**

#### 安全的局部变量
```java
public void method() {
    int local = 0; // 线程私有，安全
    local++;
}
```

#### 不安全的共享变量
```java
private int shared = 0; // 多线程共享，不安全

public void method() {
    shared++;
}
```

**原则**：
- 不共享数据：最安全
- 只读数据：安全（不可变对象）
- 读写数据：需要同步

**第六部分：原子性、可见性、有序性（预告）**
线程安全的三大核心问题：
1. **原子性**：操作不可分割
2. **可见性**：修改对其他线程可见
3. **有序性**：不会被重排序

**预告**：下一篇文章详细讲解

**第七部分：如何保证线程安全**
1. **不要共享数据**：ThreadLocal
2. **使用不可变对象**：String、Integer
3. **加锁**：synchronized、Lock
4. **使用原子类**：AtomicInteger
5. **使用并发容器**：ConcurrentHashMap
6. **使用线程安全的类**：StringBuffer

**总结要点**：
- 线程安全问题的根源是共享可变状态
- count++不是原子操作
- 理解临界区的概念
- 局部变量是线程安全的

**代码示例**：
```java
// 示例1：计数器的线程安全问题演示
// 示例2：可见性问题演示
// 示例3：竞态条件演示
// 示例4：正确的线程安全实现
```

---

### 08 - 并发编程的三大核心问题：原子性、可见性、有序性

**引言场景**：
为什么synchronized能解决所有线程安全问题？
为什么volatile只能解决部分问题？
关键在于理解并发编程的三大核心问题。

**第一部分：原子性（Atomicity）**

**定义**：一个操作或多个操作，要么全部执行且执行过程不被打断，要么都不执行。

#### 原子操作的例子
✅ **原子的**：
- 基本类型的读写（除了long和double）
- volatile变量的读写
- AtomicXXX的操作

❌ **非原子的**：
- count++
- if-then-act复合操作
- check-then-act复合操作

#### 如何保证原子性
1. **synchronized**：互斥锁
2. **Lock**：显式锁
3. **原子类**：AtomicInteger等

**代码示例**：
```java
// 问题：复合操作不是原子的
if (map.get(key) == null) {
    map.put(key, value); // 有问题！
}

// 解决：使用原子方法
map.putIfAbsent(key, value); // 原子操作
```

**第二部分：可见性（Visibility）**

**定义**：当一个线程修改了共享变量，其他线程能够立即看到这个修改。

#### 为什么会有可见性问题？

```
CPU核心架构：
┌─────────────┐    ┌─────────────┐
│   CPU 0     │    │   CPU 1     │
│  ┌───────┐  │    │  ┌───────┐  │
│  │  L1   │  │    │  │  L1   │  │ ← CPU缓存
│  └───────┘  │    │  └───────┘  │
└──────┬──────┘    └──────┬──────┘
       │                  │
       └──────────┬───────┘
                  │
           ┌──────┴──────┐
           │     L3      │ ← 共享缓存
           └──────┬──────┘
                  │
           ┌──────┴──────┐
           │  主内存      │
           └─────────────┘
```

**问题示例**：
```java
public class VisibilityProblem {
    private boolean ready = false;
    private int number = 0;

    // 线程1
    public void writer() {
        number = 42;
        ready = true;
    }

    // 线程2
    public void reader() {
        while (!ready) {
            Thread.yield();
        }
        System.out.println(number); // 可能输出0！
    }
}
```

**原因**：
- 线程2可能一直看不到ready的变化（缓存未同步）
- 即使看到ready=true，也可能看不到number=42（指令重排序）

#### 如何保证可见性
1. **volatile**：强制从主内存读写
2. **synchronized**：释放锁时刷新到主内存
3. **Lock**：类似synchronized
4. **final**：构造函数内初始化后对其他线程可见

**第三部分：有序性（Ordering）**

**定义**：程序执行的顺序按照代码的先后顺序执行。

#### 为什么会有有序性问题？

**编译器优化**和**CPU指令重排序**：
```java
// 原始代码
int a = 1;  // 语句1
int b = 2;  // 语句2
int c = a + b; // 语句3

// 可能重排序为：
int b = 2;  // 语句2
int a = 1;  // 语句1
int c = a + b; // 语句3（不影响单线程结果）
```

**单线程重排序原则（as-if-serial）**：
- 不管怎么重排序，单线程的执行结果不能改变
- 但多线程下可能有问题！

#### 经典案例：双重检查锁定的单例模式

```java
public class Singleton {
    private static Singleton instance;

    public static Singleton getInstance() {
        if (instance == null) {              // 第一次检查
            synchronized (Singleton.class) {
                if (instance == null) {      // 第二次检查
                    instance = new Singleton(); // 问题在这里！
                }
            }
        }
        return instance;
    }
}
```

**问题分析**：
```java
instance = new Singleton();
```

这一行代码实际包含3个步骤：
```
1. 分配内存空间
2. 初始化对象
3. 将instance指向内存空间
```

可能被重排序为：
```
1. 分配内存空间
3. 将instance指向内存空间（未初始化！）
2. 初始化对象
```

**时序图**：
```
时间  线程A                     线程B
t1   instance == null
t2   进入synchronized
t3   分配内存
t4   instance指向内存（未初始化）
t5                            instance != null（但未初始化！）
t6                            使用instance（出错！）
t7   初始化对象
```

**解决方案**：使用volatile
```java
private static volatile Singleton instance; // 禁止重排序
```

#### 如何保证有序性
1. **volatile**：禁止指令重排序
2. **synchronized**：同一时刻只有一个线程执行
3. **Lock**：类似synchronized

**第四部分：三者的关系**

| 问题 | synchronized | volatile | AtomicXXX |
|-----|-------------|----------|-----------|
| 原子性 | ✅ | ❌ | ✅ |
| 可见性 | ✅ | ✅ | ✅ |
| 有序性 | ✅ | ✅ | ❌ |

**重要结论**：
- **synchronized**：解决所有问题，但性能开销大
- **volatile**：只解决可见性和有序性，不解决原子性
- **AtomicXXX**：解决原子性和可见性

**第五部分：happens-before原则（预告）**
如何判断两个操作的执行顺序？
- happens-before是JMM的核心规则
- 下一阶段详细讲解

**总结要点**：
- 原子性：操作不可分割
- 可见性：修改对其他线程可见
- 有序性：代码不会被重排序
- synchronized解决所有问题，但开销大
- 根据场景选择合适的解决方案

**代码示例**：
```java
// 示例1：原子性问题演示
// 示例2：可见性问题演示
// 示例3：有序性问题演示（DCL单例）
// 示例4：正确使用volatile
```

---

## 📝 说明

本文档提供了第一阶段（并发基础篇）的详细大纲。

**特点**：
- ✅ 每篇都从具体场景引入
- ✅ 渐进式复杂度提升
- ✅ 大量示意图和代码示例
- ✅ 理论与实践结合
- ✅ 避免一次性讲太多

**后续阶段大纲**：
- 第二阶段：内存模型与原子性篇（8篇）
- 第三阶段：Lock与并发工具篇（11篇）
- 第四阶段：高级特性篇（6篇）
- 第五阶段：生产实践篇（7篇）

需要继续展开其他阶段的详细大纲吗？
