---
title: "Java并发05：线程的中断机制 - 优雅地停止线程"
date: 2025-11-20T14:00:00+08:00
draft: false
tags: ["Java并发", "线程中断", "InterruptedException"]
categories: ["技术"]
description: "从Thread.stop()被废弃的原因出发，深入理解Java的协作式中断机制。掌握interrupt()、isInterrupted()的使用，学会正确处理InterruptedException"
series: ["Java并发编程从入门到精通"]
weight: 5
stage: 1
stageTitle: "并发基础篇"
---

## 引言：停止线程的困境

假设你正在开发一个下载工具，用户点击"取消"按钮，应该如何停止下载线程？

```java
// 某个下载任务正在执行
Thread downloadThread = new Thread(() -> {
    while (true) {
        downloadData();  // 持续下载
    }
});
downloadThread.start();

// 用户点击"取消"按钮
// ❌ 如何停止这个线程？
downloadThread.stop();  // 已废弃，不能用！
```

**为什么Thread.stop()被废弃？如何正确停止线程？**

---

## 一、为什么不能用stop()？

### 1.1 stop()的问题

```java
public class StopProblemDemo {
    private int balance = 1000;  // 银行账户余额

    public synchronized void transfer(int amount) {
        balance -= amount;       // 步骤1：扣款
        // 如果在这里被stop()...
        balance += amount;       // 步骤2：到账
    }

    public static void main(String[] args) throws Exception {
        StopProblemDemo account = new StopProblemDemo();

        Thread thread = new Thread(() -> {
            account.transfer(500);
        });

        thread.start();
        Thread.sleep(1);  // 让线程执行一半
        thread.stop();    // ← 强制停止

        System.out.println("余额: " + account.balance);  // 500？1000？
    }
}
```

**问题**：
- `stop()`会立即终止线程，不管线程在做什么
- 可能导致数据不一致（扣了款但没到账）
- 锁会被释放，但资源可能处于不一致状态

**结论**：**stop()、suspend()、resume() 都已被废弃**。

---

## 二、中断机制：协作式停止

### 2.1 核心思想

Java的中断机制是**协作式**的：
- 中断只是一个"请求"，不是强制命令
- 线程自己决定是否响应中断
- 线程检查中断标志，优雅地停止

```
协作式中断

主线程                      工作线程
  │                          │
  │ interrupt()              │ while (!interrupted()) {
  ├──────"请求中断"────────→│     doWork();
  │                          │ }
  │                          │ ← 检查到中断，自行停止
  │                          │ cleanup();  // 清理资源
  │                          × 线程结束
```

### 2.2 三个核心方法

```java
public class Thread {
    // 1. 设置中断标志
    public void interrupt() {
        // 将线程的中断标志设为true
    }

    // 2. 检查中断标志（不清除）
    public boolean isInterrupted() {
        return isInterrupted(false);  // 不清除标志
    }

    // 3. 检查并清除中断标志（静态方法）
    public static boolean interrupted() {
        return currentThread().isInterrupted(true);  // 清除标志
    }
}
```

| 方法 | 作用 | 是否清除标志 | 调用者 |
|------|------|------------|--------|
| `interrupt()` | 设置中断标志 | N/A | 其他线程 |
| `isInterrupted()` | 检查中断标志 | 否 | 被中断线程 |
| `interrupted()` | 检查并清除标志 | 是 | 被中断线程 |

---

## 三、场景1：线程在运行（无阻塞）

### 3.1 正确的停止方式

```java
public class InterruptRunningThread {
    public static void main(String[] args) throws Exception {
        Thread thread = new Thread(() -> {
            while (!Thread.currentThread().isInterrupted()) {
                // ← 检查中断标志
                System.out.println("线程运行中...");
                doWork();
            }
            System.out.println("线程被中断，准备退出");
            cleanup();  // 清理资源
            System.out.println("线程已退出");
        });

        thread.start();
        Thread.sleep(100);   // 让线程运行一会儿

        System.out.println("发送中断信号");
        thread.interrupt();  // 设置中断标志

        thread.join();       // 等待线程结束
    }

    private static void doWork() {
        // 模拟工作
        for (int i = 0; i < 1000; i++) {
            Math.sqrt(i);
        }
    }

    private static void cleanup() {
        System.out.println("清理资源...");
    }
}
```

**输出**：
```
线程运行中...
线程运行中...
发送中断信号
线程被中断，准备退出
清理资源...
线程已退出
```

### 3.2 错误示例：忽略中断

```java
// ❌ 错误：不检查中断标志
public void run() {
    while (true) {  // 死循环，无法停止
        doWork();
    }
}
```

---

## 四、场景2：线程在阻塞（sleep/wait/join）

### 4.1 InterruptedException的意义

当线程在阻塞状态被中断时，会抛出 `InterruptedException`：

```java
public class InterruptBlockingThread {
    public static void main(String[] args) throws Exception {
        Thread thread = new Thread(() -> {
            try {
                System.out.println("线程开始休眠");
                Thread.sleep(10000);  // 休眠10秒
                System.out.println("线程休眠结束");
            } catch (InterruptedException e) {
                System.out.println("线程在休眠时被中断");
                System.out.println("中断标志: " +
                    Thread.currentThread().isInterrupted());  // false
            }
        });

        thread.start();
        Thread.sleep(1000);   // 等待1秒

        System.out.println("中断线程");
        thread.interrupt();   // 中断正在sleep的线程

        thread.join();
    }
}
```

**输出**：
```
线程开始休眠
中断线程
线程在休眠时被中断
中断标志: false  ← 注意：抛异常后，中断标志被清除！
```

**关键点**：
1. `sleep()`、`wait()`、`join()` 等阻塞方法会响应中断
2. 被中断时，抛出 `InterruptedException`
3. **抛异常后，中断标志会被清除**（变回false）

### 4.2 正确处理InterruptedException

#### 方式1：向上传播异常

```java
// ✅ 推荐：向上抛出，让调用方决定如何处理
public void doWork() throws InterruptedException {
    Thread.sleep(1000);
}
```

#### 方式2：恢复中断状态

```java
// ✅ 推荐：捕获后恢复中断状态
public void doWork() {
    try {
        Thread.sleep(1000);
    } catch (InterruptedException e) {
        Thread.currentThread().interrupt();  // ← 恢复中断状态
        // 然后返回或做清理工作
    }
}
```

#### ❌ 错误方式：吞掉异常

```java
// ❌ 错误：什么都不做，忽略中断
public void doWork() {
    try {
        Thread.sleep(1000);
    } catch (InterruptedException e) {
        // 什么都不做 ← 中断信息丢失！
    }
}
```

### 4.3 完整示例：可中断的任务

```java
public class InterruptibleTask {
    public static void main(String[] args) throws Exception {
        Thread thread = new Thread(() -> {
            try {
                System.out.println("开始处理任务");
                for (int i = 0; i < 5; i++) {
                    System.out.println("处理第" + i + "步");
                    Thread.sleep(1000);  // 可能被中断
                }
                System.out.println("任务完成");
            } catch (InterruptedException e) {
                System.out.println("任务被中断");
                // 清理资源
                cleanup();
            }
        });

        thread.start();
        Thread.sleep(2500);  // 让任务执行一半

        System.out.println("取消任务");
        thread.interrupt();

        thread.join();
    }

    private static void cleanup() {
        System.out.println("清理资源");
    }
}
```

**输出**：
```
开始处理任务
处理第0步
处理第1步
处理第2步
取消任务
任务被中断
清理资源
```

---

## 五、场景3：不可中断的阻塞

### 5.1 synchronized不可中断

```java
public class SynchronizedNotInterruptible {
    private static final Object lock = new Object();

    public static void main(String[] args) throws Exception {
        // 线程1：持有锁
        Thread t1 = new Thread(() -> {
            synchronized (lock) {
                System.out.println("线程1获得锁");
                try {
                    Thread.sleep(10000);  // 持有锁10秒
                } catch (InterruptedException e) {}
            }
        });

        // 线程2：等待锁
        Thread t2 = new Thread(() -> {
            System.out.println("线程2尝试获取锁...");
            synchronized (lock) {  // ← 阻塞在这里
                System.out.println("线程2获得锁");
            }
        });

        t1.start();
        Thread.sleep(100);
        t2.start();
        Thread.sleep(100);

        // 中断线程2
        System.out.println("中断线程2");
        t2.interrupt();  // ← 无效！线程2仍然阻塞
        Thread.sleep(1000);

        System.out.println("线程2状态: " + t2.getState());  // BLOCKED

        t1.join();
        t2.join();
    }
}
```

**输出**：
```
线程1获得锁
线程2尝试获取锁...
中断线程2
线程2状态: BLOCKED  ← 仍然阻塞，中断无效
...
线程2获得锁
```

**结论**：**等待synchronized锁的线程无法被中断**。

### 5.2 解决方案：使用Lock.lockInterruptibly()

```java
import java.util.concurrent.locks.Lock;
import java.util.concurrent.locks.ReentrantLock;

public class LockInterruptibly {
    private static final Lock lock = new ReentrantLock();

    public static void main(String[] args) throws Exception {
        // 线程1：持有锁
        Thread t1 = new Thread(() -> {
            lock.lock();
            try {
                System.out.println("线程1获得锁");
                Thread.sleep(10000);
            } catch (InterruptedException e) {
            } finally {
                lock.unlock();
            }
        });

        // 线程2：可中断地等待锁
        Thread t2 = new Thread(() -> {
            try {
                System.out.println("线程2尝试获取锁...");
                lock.lockInterruptibly();  // ← 可中断
                try {
                    System.out.println("线程2获得锁");
                } finally {
                    lock.unlock();
                }
            } catch (InterruptedException e) {
                System.out.println("线程2在等待锁时被中断");
            }
        });

        t1.start();
        Thread.sleep(100);
        t2.start();
        Thread.sleep(100);

        // 中断线程2
        System.out.println("中断线程2");
        t2.interrupt();  // ← 有效！

        t2.join();
        t1.join();
    }
}
```

**输出**：
```
线程1获得锁
线程2尝试获取锁...
中断线程2
线程2在等待锁时被中断  ← 成功响应中断
```

---

## 六、实战案例

### 6.1 案例1：可取消的下载任务

```java
public class DownloadTask {
    public static void main(String[] args) throws Exception {
        Thread downloadThread = new Thread(() -> {
            try {
                System.out.println("开始下载文件...");
                for (int progress = 0; progress <= 100; progress += 10) {
                    // 检查中断
                    if (Thread.currentThread().isInterrupted()) {
                        System.out.println("下载被取消");
                        return;
                    }

                    System.out.println("下载进度: " + progress + "%");
                    Thread.sleep(500);  // 模拟下载耗时
                }
                System.out.println("下载完成");
            } catch (InterruptedException e) {
                System.out.println("下载被中断");
            }
        });

        downloadThread.start();
        Thread.sleep(2000);  // 下载2秒

        System.out.println("用户点击取消");
        downloadThread.interrupt();  // 取消下载

        downloadThread.join();
    }
}
```

### 6.2 案例2：超时任务

```java
public class TimeoutTask {
    public static void main(String[] args) throws Exception {
        Thread worker = new Thread(() -> {
            try {
                System.out.println("开始执行任务");
                // 模拟长时间任务
                for (int i = 0; i < 100; i++) {
                    System.out.println("步骤 " + i);
                    Thread.sleep(100);
                }
            } catch (InterruptedException e) {
                System.out.println("任务超时，被中断");
            }
        });

        worker.start();

        // 等待5秒
        worker.join(5000);

        if (worker.isAlive()) {
            System.out.println("任务超时，强制中断");
            worker.interrupt();
            worker.join();
        }

        System.out.println("主线程结束");
    }
}
```

### 6.3 案例3：优雅关闭线程池

```java
public class GracefulShutdown {
    public static void main(String[] args) throws Exception {
        ExecutorService executor = Executors.newFixedThreadPool(3);

        // 提交10个任务
        for (int i = 0; i < 10; i++) {
            final int taskId = i;
            executor.submit(() -> {
                try {
                    System.out.println("任务" + taskId + "开始");
                    Thread.sleep(2000);
                    System.out.println("任务" + taskId + "完成");
                } catch (InterruptedException e) {
                    System.out.println("任务" + taskId + "被中断");
                }
            });
        }

        Thread.sleep(3000);  // 让一些任务完成

        System.out.println("开始关闭线程池");

        // 方式1：等待所有任务完成
        executor.shutdown();  // 不接受新任务，等待已有任务完成

        // 方式2：立即停止（中断所有任务）
        // List<Runnable> pending = executor.shutdownNow();
        // System.out.println("未执行的任务: " + pending.size());

        // 等待线程池终止
        if (!executor.awaitTermination(10, TimeUnit.SECONDS)) {
            System.out.println("超时，强制关闭");
            executor.shutdownNow();
        }

        System.out.println("线程池已关闭");
    }
}
```

---

## 七、常见陷阱

### 陷阱1：吞掉InterruptedException

```java
// ❌ 错误
public void run() {
    while (true) {
        try {
            doWork();
        } catch (InterruptedException e) {
            // 什么都不做 ← 错误！中断信息丢失
        }
    }
}

// ✅ 正确
public void run() {
    while (!Thread.currentThread().isInterrupted()) {
        try {
            doWork();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();  // 恢复中断状态
            break;  // 退出循环
        }
    }
}
```

### 陷阱2：使用自定义标志代替中断

```java
// ❌ 不推荐：自定义标志
private volatile boolean stopped = false;

public void run() {
    while (!stopped) {
        // 如果线程在sleep，无法及时响应
        try {
            Thread.sleep(1000);
        } catch (InterruptedException e) {
            // 需要额外检查stopped
        }
    }
}

// ✅ 推荐：使用中断机制
public void run() {
    while (!Thread.currentThread().isInterrupted()) {
        try {
            Thread.sleep(1000);  // 会立即响应中断
        } catch (InterruptedException e) {
            break;
        }
    }
}
```

### 陷阱3：在finally块中调用interrupt()

```java
// ❌ 错误
public void run() {
    try {
        doWork();
    } catch (InterruptedException e) {
        cleanup();
    } finally {
        Thread.currentThread().interrupt();  // ← 错误！会影响后续代码
    }
}
```

---

## 八、总结

### 8.1 核心要点

1. **不要用stop()**
   - stop()会强制终止线程，可能导致数据不一致
   - 使用中断机制代替

2. **中断是协作式的**
   - `interrupt()` 只是设置标志，不强制停止
   - 线程需要检查 `isInterrupted()` 并自行停止

3. **正确处理InterruptedException**
   - 向上传播：`throws InterruptedException`
   - 恢复中断状态：`Thread.currentThread().interrupt()`
   - 不要吞掉异常

4. **synchronized不可中断**
   - 等待synchronized锁的线程无法被中断
   - 使用 `Lock.lockInterruptibly()` 代替

5. **线程池的优雅关闭**
   - `shutdown()`：等待任务完成
   - `shutdownNow()`：立即停止（中断任务）
   - `awaitTermination()`：等待终止

### 8.2 快速记忆

```
中断三步曲：
1. 主线程调用 interrupt()   ← 发送中断信号
2. 工作线程检查 isInterrupted() ← 检查中断标志
3. 工作线程自行停止并清理     ← 协作式退出
```

### 8.3 最佳实践

```java
// ✅ 标准的可中断任务模板
public void run() {
    try {
        while (!Thread.currentThread().isInterrupted()) {
            doWork();  // 可能抛出InterruptedException
        }
    } catch (InterruptedException e) {
        // 清理资源
    } finally {
        cleanup();
    }
}
```

### 8.4 思考题

1. 为什么抛出InterruptedException后，中断标志会被清除？
2. 如何让正在等待synchronized锁的线程响应中断？
3. `interrupt()` 和 `interrupted()` 有什么区别？
4. 线程池的 `shutdown()` 和 `shutdownNow()` 有什么区别？

### 8.5 下一篇预告

**《线程间通信：wait/notify机制详解》**

- 生产者-消费者问题如何解决？
- wait()和sleep()有什么区别？
- 为什么wait()必须在synchronized中调用？
- 什么是虚假唤醒？如何避免？

---

## 扩展阅读

- [Java Concurrency in Practice](https://jcip.net/) - Chapter 7: Cancellation
- [Why are Thread.stop deprecated?](https://docs.oracle.com/javase/8/docs/technotes/guides/concurrency/threadPrimitiveDeprecation.html)
- [Dealing with InterruptedException](https://www.ibm.com/developerworks/library/j-jtp05236/)
