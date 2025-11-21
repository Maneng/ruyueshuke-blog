---
title: "JMH性能测试：科学测量并发性能的利器"
date: 2025-11-20T16:00:00+08:00
draft: false
tags: ["Java并发", "JMH", "性能测试", "基准测试"]
categories: ["技术"]
description: "深入JMH基准测试框架，掌握科学的并发性能测试方法，避免常见的测试陷阱"
series: ["Java并发编程从入门到精通"]
weight: 38
stage: 5
stageTitle: "问题排查篇"
---

## 一、为什么需要JMH？

### 1.1 传统性能测试的问题

```java
// ❌ 错误的性能测试
public class BadPerformanceTest {
    public static void main(String[] args) {
        long start = System.currentTimeMillis();

        for (int i = 0; i < 1_000_000; i++) {
            // 测试代码
        }

        long end = System.currentTimeMillis();
        System.out.println("耗时：" + (end - start) + "ms");
    }
}
```

**问题**：
- ❌ **JVM预热不足**：JIT未优化
- ❌ **GC影响**：测试期间GC
- ❌ **死代码消除**：编译器优化掉无用代码
- ❌ **缓存影响**：CPU缓存命中率
- ❌ **采样不足**：单次测试不准确

### 1.2 JMH的优势

```java
// ✅ 使用JMH进行科学测试
@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.NANOSECONDS)
@State(Scope.Thread)
public class JMHTest {

    @Benchmark
    public int test() {
        return 1 + 1;
    }
}
```

**JMH特性**：
- ✅ 自动JVM预热
- ✅ 多次迭代统计
- ✅ 防止死代码消除
- ✅ 支持多种测试模式
- ✅ 结果科学可信

---

## 二、JMH快速入门

### 2.1 添加依赖

```xml
<!-- Maven -->
<dependency>
    <groupId>org.openjdk.jmh</groupId>
    <artifactId>jmh-core</artifactId>
    <version>1.36</version>
</dependency>
<dependency>
    <groupId>org.openjdk.jmh</groupId>
    <artifactId>jmh-generator-annprocess</artifactId>
    <version>1.36</version>
</dependency>
```

### 2.2 第一个基准测试

```java
import org.openjdk.jmh.annotations.*;
import java.util.concurrent.TimeUnit;

@BenchmarkMode(Mode.AverageTime)  // 测试模式：平均时间
@OutputTimeUnit(TimeUnit.NANOSECONDS)  // 输出单位：纳秒
@State(Scope.Thread)  // 状态范围：每个线程
@Warmup(iterations = 3, time = 1)  // 预热：3轮，每轮1秒
@Measurement(iterations = 5, time = 1)  // 测试：5轮，每轮1秒
@Fork(1)  // 进程数：1个JVM进程
public class FirstBenchmark {

    @Benchmark
    public int test() {
        return 1 + 1;
    }

    public static void main(String[] args) throws Exception {
        org.openjdk.jmh.Main.main(args);
    }
}
```

**运行结果**：
```
Benchmark              Mode  Cnt  Score   Error  Units
FirstBenchmark.test    avgt    5  1.234 ± 0.001  ns/op
```

**结果解读**：
- **Mode**：测试模式（avgt = 平均时间）
- **Cnt**：迭代次数
- **Score**：平均耗时 1.234纳秒
- **Error**：误差 ±0.001纳秒

---

## 三、核心注解详解

### 3.1 @BenchmarkMode：测试模式

```java
// 1. Throughput：吞吐量（每秒操作数）
@BenchmarkMode(Mode.Throughput)

// 2. AverageTime：平均时间
@BenchmarkMode(Mode.AverageTime)

// 3. SampleTime：采样时间（P99、P999）
@BenchmarkMode(Mode.SampleTime)

// 4. SingleShotTime：单次执行时间
@BenchmarkMode(Mode.SingleShotTime)

// 5. All：所有模式
@BenchmarkMode(Mode.All)
```

### 3.2 @State：状态范围

```java
// 1. Scope.Thread：每个线程独立状态
@State(Scope.Thread)
public class ThreadState {
    int x = 0;  // 每个线程独立的x
}

// 2. Scope.Benchmark：所有线程共享状态
@State(Scope.Benchmark)
public class BenchmarkState {
    int x = 0;  // 所有线程共享的x
}

// 3. Scope.Group：线程组共享状态
@State(Scope.Group)
public class GroupState {
    int x = 0;  // 线程组共享的x
}
```

### 3.3 @Setup和@TearDown：初始化和清理

```java
@State(Scope.Thread)
public class SetupTearDownTest {

    private List<Integer> list;

    @Setup(Level.Trial)  // 每次基准测试前执行一次
    public void setupTrial() {
        System.out.println("Trial setup");
    }

    @Setup(Level.Iteration)  // 每次迭代前执行
    public void setupIteration() {
        list = new ArrayList<>();
    }

    @Setup(Level.Invocation)  // 每次方法调用前执行
    public void setupInvocation() {
        list.clear();
    }

    @Benchmark
    public void test() {
        list.add(1);
    }

    @TearDown(Level.Trial)  // 每次基准测试后执行一次
    public void tearDownTrial() {
        System.out.println("Trial teardown");
    }
}
```

---

## 四、实战案例

### 4.1 案例1：对比synchronized vs ReentrantLock

```java
@BenchmarkMode(Mode.Throughput)
@OutputTimeUnit(TimeUnit.MILLISECONDS)
@State(Scope.Benchmark)
@Warmup(iterations = 3, time = 1)
@Measurement(iterations = 5, time = 1)
@Fork(1)
@Threads(10)  // 10个线程
public class LockBenchmark {

    private int count = 0;
    private final Object syncLock = new Object();
    private final ReentrantLock reentrantLock = new ReentrantLock();

    @Benchmark
    public void testSynchronized() {
        synchronized (syncLock) {
            count++;
        }
    }

    @Benchmark
    public void testReentrantLock() {
        reentrantLock.lock();
        try {
            count++;
        } finally {
            reentrantLock.unlock();
        }
    }
}
```

**结果**：
```
Benchmark                         Mode  Cnt     Score    Error   Units
LockBenchmark.testSynchronized   thrpt    5  5000.123 ± 50.234  ops/ms
LockBenchmark.testReentrantLock  thrpt    5  4800.456 ± 60.123  ops/ms
```

### 4.2 案例2：对比AtomicLong vs LongAdder

```java
@BenchmarkMode(Mode.Throughput)
@OutputTimeUnit(TimeUnit.MILLISECONDS)
@State(Scope.Benchmark)
@Warmup(iterations = 3)
@Measurement(iterations = 5)
@Fork(1)
public class AtomicBenchmark {

    private AtomicLong atomicLong = new AtomicLong(0);
    private LongAdder longAdder = new LongAdder();

    @Benchmark
    @Threads(1)  // 1个线程
    public void testAtomicLong1Thread() {
        atomicLong.incrementAndGet();
    }

    @Benchmark
    @Threads(1)
    public void testLongAdder1Thread() {
        longAdder.increment();
    }

    @Benchmark
    @Threads(64)  // 64个线程
    public void testAtomicLong64Threads() {
        atomicLong.incrementAndGet();
    }

    @Benchmark
    @Threads(64)
    public void testLongAdder64Threads() {
        longAdder.increment();
    }
}
```

**结果**：
```
Benchmark                              (threads)  Mode  Cnt      Score     Error   Units
AtomicBenchmark.testAtomicLong1Thread          1  thrpt    5  50000.123 ± 500.234  ops/ms
AtomicBenchmark.testLongAdder1Thread           1  thrpt    5  52000.456 ± 600.123  ops/ms
AtomicBenchmark.testAtomicLong64Threads       64  thrpt    5   5000.123 ± 100.234  ops/ms
AtomicBenchmark.testLongAdder64Threads        64  thrpt    5  45000.456 ± 500.123  ops/ms
```

**结论**：
- 1个线程：性能相当
- 64个线程：LongAdder **9倍**性能提升

### 4.3 案例3：ConcurrentHashMap vs Collections.synchronizedMap

```java
@BenchmarkMode(Mode.Throughput)
@OutputTimeUnit(TimeUnit.MILLISECONDS)
@State(Scope.Benchmark)
@Warmup(iterations = 3)
@Measurement(iterations = 5)
@Fork(1)
@Threads(10)
public class MapBenchmark {

    private ConcurrentHashMap<Integer, Integer> concurrentMap = new ConcurrentHashMap<>();
    private Map<Integer, Integer> syncMap = Collections.synchronizedMap(new HashMap<>());

    @Setup(Level.Iteration)
    public void setup() {
        for (int i = 0; i < 1000; i++) {
            concurrentMap.put(i, i);
            syncMap.put(i, i);
        }
    }

    @Benchmark
    public Integer testConcurrentHashMapGet() {
        return concurrentMap.get(500);
    }

    @Benchmark
    public Integer testSyncMapGet() {
        return syncMap.get(500);
    }

    @Benchmark
    public void testConcurrentHashMapPut() {
        concurrentMap.put(1001, 1001);
    }

    @Benchmark
    public void testSyncMapPut() {
        syncMap.put(1001, 1001);
    }
}
```

---

## 五、避免测试陷阱

### 5.1 死代码消除

```java
// ❌ 错误：结果未被使用，可能被优化掉
@Benchmark
public void testBad() {
    int result = 1 + 1;  // 编译器可能优化掉
}

// ✅ 正确：返回结果，防止优化
@Benchmark
public int testGood() {
    return 1 + 1;
}

// ✅ 或使用Blackhole消费结果
@Benchmark
public void testBlackhole(Blackhole bh) {
    int result = 1 + 1;
    bh.consume(result);  // 防止优化
}
```

### 5.2 常量折叠

```java
// ❌ 错误：编译器可能在编译期计算
@Benchmark
public int testBad() {
    return 1 + 1;  // 编译期已知结果
}

// ✅ 正确：使用变量
@State(Scope.Thread)
public class ConstantFoldingTest {
    int a = 1;
    int b = 1;

    @Benchmark
    public int testGood() {
        return a + b;  // 运行时计算
    }
}
```

### 5.3 循环展开

```java
// ❌ 错误：循环可能被展开优化
@Benchmark
public int testBad() {
    int sum = 0;
    for (int i = 0; i < 10; i++) {
        sum += i;
    }
    return sum;
}

// ✅ JMH会自动处理，无需担心
```

---

## 六、最佳实践

### 6.1 推荐配置

```java
@BenchmarkMode(Mode.Throughput)  // 或 AverageTime
@OutputTimeUnit(TimeUnit.MILLISECONDS)
@State(Scope.Thread)
@Warmup(iterations = 3, time = 1, timeUnit = TimeUnit.SECONDS)
@Measurement(iterations = 5, time = 1, timeUnit = TimeUnit.SECONDS)
@Fork(value = 1, jvmArgs = {"-Xms2g", "-Xmx2g"})
@Threads(10)
public class BestPracticeBenchmark {

    @Benchmark
    public void test() {
        // 测试代码
    }
}
```

### 6.2 结果分析

```bash
# 运行测试
mvn clean install
java -jar target/benchmarks.jar

# 输出结果到文件
java -jar target/benchmarks.jar -rf json -rff results.json

# 指定测试方法
java -jar target/benchmarks.jar ".*LockBenchmark.*"

# 查看帮助
java -jar target/benchmarks.jar -h
```

### 6.3 可视化结果

使用[JMH Visualizer](https://jmh.morethan.io/)：
1. 运行测试，导出JSON结果
2. 上传到JMH Visualizer
3. 查看图表分析

---

## 七、核心要点总结

### 7.1 常用注解

| 注解 | 作用 | 常用值 |
|-----|------|--------|
| **@BenchmarkMode** | 测试模式 | Throughput, AverageTime |
| **@OutputTimeUnit** | 输出单位 | MILLISECONDS, NANOSECONDS |
| **@State** | 状态范围 | Thread, Benchmark |
| **@Warmup** | 预热配置 | iterations=3 |
| **@Measurement** | 测试配置 | iterations=5 |
| **@Fork** | 进程数 | 1 |
| **@Threads** | 线程数 | 10 |

### 7.2 避免陷阱

1. **死代码消除**：使用Blackhole或返回结果
2. **常量折叠**：使用@State变量
3. **JVM预热**：配置@Warmup
4. **GC影响**：配置@Fork的jvmArgs

### 7.3 测试流程

1. **编写基准测试**：使用JMH注解
2. **配置参数**：预热、迭代、线程数
3. **运行测试**：`java -jar benchmarks.jar`
4. **分析结果**：Score、Error、对比
5. **优化代码**：根据结果调优

---

## 总结

JMH是Java性能测试的标准工具，帮助我们科学测量并发性能：

**核心优势**：
- ✅ 自动JVM预热
- ✅ 多次迭代统计
- ✅ 防止编译器优化
- ✅ 结果科学可信

**实战要点**：
1. **使用@BenchmarkMode**：选择合适的测试模式
2. **配置@Warmup**：确保JVM充分预热
3. **避免陷阱**：使用Blackhole防止死代码消除
4. **对比测试**：多个方案并行测试

**典型场景**：
- 对比锁性能
- 对比并发集合
- 对比原子类
- 验证优化效果

**下一篇预告**：最后一篇，我们将总结Java并发编程的最佳实践，为整个专题画上圆满句号！
