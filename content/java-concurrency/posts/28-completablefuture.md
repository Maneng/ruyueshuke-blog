---
title: "Java并发28：CompletableFuture异步编程 - 优雅的异步处理"
date: 2025-11-20T23:15:00+08:00
draft: false
tags: ["Java并发", "CompletableFuture", "异步编程", "Future"]
categories: ["技术"]
description: "CompletableFuture的使用方法、链式调用、异常处理、组合操作、性能优化。"
series: ["Java并发编程从入门到精通"]
weight: 28
stage: 4
stageTitle: "高级特性篇"
---

## Future的局限性

```java
Future<Integer> future = executor.submit(() -> {
    return compute();
});

Integer result = future.get();  // 阻塞等待

// 问题：
// 1. 无法主动完成
// 2. 无法链式调用
// 3. 无法组合多个Future
// 4. 无法异常处理回调
```

---

## CompletableFuture核心API

### 1. 创建
```java
// 无返回值
CompletableFuture<Void> future = CompletableFuture.runAsync(() -> {
    System.out.println("Running");
});

// 有返回值
CompletableFuture<Integer> future = CompletableFuture.supplyAsync(() -> {
    return 42;
});

// 指定线程池
CompletableFuture<Integer> future = CompletableFuture.supplyAsync(() -> {
    return 42;
}, executorService);
```

### 2. 回调
```java
CompletableFuture.supplyAsync(() -> "Hello")
    .thenApply(s -> s + " World")           // 转换
    .thenAccept(System.out::println)        // 消费
    .thenRun(() -> System.out.println("Done"));  // 运行
```

### 3. 异常处理
```java
CompletableFuture.supplyAsync(() -> {
    throw new RuntimeException("Error");
})
.exceptionally(ex -> {
    System.err.println("Exception: " + ex.getMessage());
    return "default";  // 默认值
})
.thenAccept(result -> System.out.println(result));
```

### 4. 组合
```java
CompletableFuture<Integer> future1 = CompletableFuture.supplyAsync(() -> 10);
CompletableFuture<Integer> future2 = CompletableFuture.supplyAsync(() -> 20);

// 两个都完成
future1.thenCombine(future2, (a, b) -> a + b)
    .thenAccept(System.out::println);  // 30

// 任一完成
future1.applyToEither(future2, x -> x * 2)
    .thenAccept(System.out::println);

// 全部完成
CompletableFuture.allOf(future1, future2).join();

// 任一完成
CompletableFuture.anyOf(future1, future2).join();
```

---

## 实战案例

### 案例1：异步查询聚合
```java
public CompletableFuture<UserInfo> getUserInfo(Long userId) {
    CompletableFuture<User> userFuture = CompletableFuture.supplyAsync(
        () -> userService.getUser(userId));

    CompletableFuture<List<Order>> ordersFuture = CompletableFuture.supplyAsync(
        () -> orderService.getOrders(userId));

    CompletableFuture<Address> addressFuture = CompletableFuture.supplyAsync(
        () -> addressService.getAddress(userId));

    return CompletableFuture.allOf(userFuture, ordersFuture, addressFuture)
        .thenApply(v -> {
            User user = userFuture.join();
            List<Order> orders = ordersFuture.join();
            Address address = addressFuture.join();
            return new UserInfo(user, orders, address);
        });
}
```

### 案例2：超时控制
```java
CompletableFuture<String> future = CompletableFuture.supplyAsync(() -> {
    sleep(5000);  // 模拟耗时操作
    return "result";
});

try {
    String result = future.get(3, TimeUnit.SECONDS);  // 3秒超时
} catch (TimeoutException e) {
    future.cancel(true);  // 超时取消
    return "default";
}

// JDK 9+：orTimeout
future.orTimeout(3, TimeUnit.SECONDS)
    .exceptionally(ex -> "default");
```

---

## 方法对比

| 方法 | 描述 | 是否阻塞 | 线程池 |
|-----|------|---------|--------|
| **thenApply** | 转换结果 | 否 | 同当前 |
| **thenApplyAsync** | 转换结果 | 否 | ForkJoinPool |
| **thenAccept** | 消费结果 | 否 | 同当前 |
| **thenRun** | 执行操作 | 否 | 同当前 |
| **thenCompose** | 链式异步 | 否 | 同当前 |
| **thenCombine** | 组合两个 | 否 | 同当前 |
| **get()** | 获取结果 | **是** | - |
| **join()** | 获取结果 | **是** | - |

---

## 最佳实践

**1. 指定线程池**
```java
// ❌ 不好：使用默认ForkJoinPool
CompletableFuture.supplyAsync(() -> query());

// ✅ 好：自定义线程池
Executor executor = Executors.newFixedThreadPool(10);
CompletableFuture.supplyAsync(() -> query(), executor);
```

**2. 异常处理**
```java
CompletableFuture.supplyAsync(() -> {
    // 可能抛异常
})
.exceptionally(ex -> {
    log.error("Error", ex);
    return defaultValue;
})
.thenAccept(result -> process(result));
```

**3. 避免阻塞**
```java
// ❌ 阻塞
future.get();

// ✅ 回调
future.thenAccept(result -> handle(result));
```

---

## 性能优化

**并行vs串行**：
```java
// 串行：1000ms + 1000ms = 2000ms
String result1 = queryService1();
String result2 = queryService2();

// 并行：max(1000ms, 1000ms) = 1000ms
CompletableFuture<String> f1 = CompletableFuture.supplyAsync(() -> queryService1());
CompletableFuture<String> f2 = CompletableFuture.supplyAsync(() -> queryService2());
CompletableFuture.allOf(f1, f2).join();
```

---

## 总结

**核心要点**：
1. 支持链式调用
2. 支持异常处理
3. 支持组合操作
4. 建议指定线程池

**适用场景**：
- 异步IO操作
- 多服务聚合
- 批量并行任务

---

**系列文章**：
- 上一篇：[Java并发27：CopyOnWriteArrayList](/java-concurrency/posts/27-copyonwritearraylist/)
- 下一篇：[Java并发29：ForkJoinPool与分治算法](/java-concurrency/posts/29-forkjoinpool/) （即将发布）
