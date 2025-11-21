---
title: "CompletableFuture实战：异步编程最佳实践"
date: 2025-11-19T20:00:00+08:00
draft: false
tags: ["Java并发", "CompletableFuture", "异步编程"]
categories: ["技术"]
description: "深入CompletableFuture实战应用，掌握异步编程最佳实践，包括任务编排、异常处理、超时控制等核心场景"
series: ["Java并发编程从入门到精通"]
weight: 29
stage: 4
stageTitle: "实战应用篇"
---

## 一、为什么需要CompletableFuture？

### 1.1 传统Future的局限

```java
// Future的问题
ExecutorService executor = Executors.newFixedThreadPool(10);
Future<String> future = executor.submit(() -> {
    Thread.sleep(1000);
    return "result";
});

// ❌ 只能阻塞等待
String result = future.get();  // 阻塞！

// ❌ 无法组合多个异步任务
// ❌ 无法处理异常回调
// ❌ 无法设置超时后的默认值
```

### 1.2 CompletableFuture的优势

```java
// ✅ 链式编程
CompletableFuture.supplyAsync(() -> "Hello")
    .thenApply(s -> s + " World")
    .thenAccept(System.out::println);

// ✅ 任务组合
CompletableFuture<String> future1 = CompletableFuture.supplyAsync(() -> "A");
CompletableFuture<String> future2 = CompletableFuture.supplyAsync(() -> "B");
CompletableFuture<String> result = future1.thenCombine(future2, (a, b) -> a + b);

// ✅ 异常处理
CompletableFuture.supplyAsync(() -> {
    if (Math.random() > 0.5) throw new RuntimeException("Error");
    return "OK";
}).exceptionally(ex -> "Default");
```

**核心改进**：
- **非阻塞**：支持回调，不阻塞主线程
- **可组合**：支持多个任务的组合编排
- **异常友好**：提供完善的异常处理机制
- **超时控制**：支持超时设置和降级处理

---

## 二、核心API实战

### 2.1 创建CompletableFuture

```java
// 1. 无返回值的异步任务
CompletableFuture<Void> future1 = CompletableFuture.runAsync(() -> {
    System.out.println("执行任务，无返回值");
});

// 2. 有返回值的异步任务
CompletableFuture<String> future2 = CompletableFuture.supplyAsync(() -> {
    return "返回结果";
});

// 3. 指定线程池（推荐）
ExecutorService executor = Executors.newFixedThreadPool(10);
CompletableFuture<String> future3 = CompletableFuture.supplyAsync(() -> {
    return "使用自定义线程池";
}, executor);

// 4. 手动创建并完成
CompletableFuture<String> future4 = new CompletableFuture<>();
future4.complete("手动完成");  // 主动设置结果
```

### 2.2 任务串联

```java
// thenApply：有参数、有返回值
CompletableFuture<Integer> future = CompletableFuture.supplyAsync(() -> 10)
    .thenApply(x -> x * 2)      // 20
    .thenApply(x -> x + 5);     // 25

// thenAccept：有参数、无返回值
CompletableFuture.supplyAsync(() -> "Hello")
    .thenAccept(s -> System.out.println(s));  // 消费结果

// thenRun：无参数、无返回值
CompletableFuture.supplyAsync(() -> "Hello")
    .thenRun(() -> System.out.println("任务完成"));  // 不关心结果

// thenCompose：扁平化嵌套的CompletableFuture
CompletableFuture<String> future = CompletableFuture.supplyAsync(() -> "userId:123")
    .thenCompose(userId -> getUserInfo(userId));  // 返回新的CompletableFuture

private CompletableFuture<String> getUserInfo(String userId) {
    return CompletableFuture.supplyAsync(() -> "User:" + userId);
}
```

**Async版本区别**：
```java
// thenApply：在当前线程或调用线程执行
future.thenApply(x -> x * 2);

// thenApplyAsync：在线程池中异步执行
future.thenApplyAsync(x -> x * 2);
```

### 2.3 任务组合

```java
// 1. thenCombine：两个任务都完成后，合并结果
CompletableFuture<Integer> future1 = CompletableFuture.supplyAsync(() -> 10);
CompletableFuture<Integer> future2 = CompletableFuture.supplyAsync(() -> 20);

CompletableFuture<Integer> result = future1.thenCombine(future2, (a, b) -> a + b);
System.out.println(result.get());  // 30

// 2. thenAcceptBoth：两个任务都完成后，消费结果
future1.thenAcceptBoth(future2, (a, b) -> {
    System.out.println("结果：" + (a + b));
});

// 3. applyToEither：任意一个完成就返回
CompletableFuture<String> future3 = CompletableFuture.supplyAsync(() -> {
    sleep(100);
    return "快";
});
CompletableFuture<String> future4 = CompletableFuture.supplyAsync(() -> {
    sleep(200);
    return "慢";
});

future3.applyToEither(future4, s -> s).thenAccept(System.out::println);  // 输出：快

// 4. allOf：等待所有任务完成
CompletableFuture<Void> all = CompletableFuture.allOf(future1, future2, future3, future4);
all.join();  // 等待所有任务完成

// 5. anyOf：等待任意一个任务完成
CompletableFuture<Object> any = CompletableFuture.anyOf(future3, future4);
System.out.println(any.get());  // 返回最快完成的结果
```

---

## 三、异常处理

### 3.1 异常处理方式

```java
// 1. exceptionally：捕获异常，返回默认值
CompletableFuture<String> future = CompletableFuture.supplyAsync(() -> {
    if (Math.random() > 0.5) {
        throw new RuntimeException("随机异常");
    }
    return "成功";
}).exceptionally(ex -> {
    System.err.println("发生异常：" + ex.getMessage());
    return "默认值";  // 返回降级结果
});

// 2. handle：无论是否异常，都会执行
CompletableFuture<String> future2 = CompletableFuture.supplyAsync(() -> {
    if (Math.random() > 0.5) {
        throw new RuntimeException("异常");
    }
    return "成功";
}).handle((result, ex) -> {
    if (ex != null) {
        System.err.println("异常：" + ex.getMessage());
        return "默认值";
    }
    return result;
});

// 3. whenComplete：类似finally，不影响结果传递
CompletableFuture<String> future3 = CompletableFuture.supplyAsync(() -> "结果")
    .whenComplete((result, ex) -> {
        if (ex != null) {
            System.err.println("异常：" + ex.getMessage());
        } else {
            System.out.println("成功：" + result);
        }
    });
```

### 3.2 异常传播

```java
CompletableFuture.supplyAsync(() -> {
    throw new RuntimeException("步骤1异常");
})
.thenApply(s -> {
    System.out.println("步骤2");  // 不会执行
    return s + "2";
})
.thenApply(s -> {
    System.out.println("步骤3");  // 不会执行
    return s + "3";
})
.exceptionally(ex -> {
    System.err.println("捕获异常：" + ex.getMessage());  // 最终捕获
    return "默认值";
});
```

**异常传播规则**：
- 异常会**跳过**后续的 `thenApply`、`thenAccept` 等方法
- 直到遇到 `exceptionally` 或 `handle` 才会被处理
- 类似传统的 `try-catch` 机制

---

## 四、实战场景

### 4.1 并行查询多个数据源

```java
public class ParallelQueryDemo {

    // 模拟查询用户基本信息
    private CompletableFuture<UserInfo> queryUserInfo(String userId) {
        return CompletableFuture.supplyAsync(() -> {
            sleep(100);  // 模拟网络延迟
            return new UserInfo(userId, "张三");
        });
    }

    // 模拟查询用户订单
    private CompletableFuture<List<Order>> queryOrders(String userId) {
        return CompletableFuture.supplyAsync(() -> {
            sleep(150);
            return Arrays.asList(new Order("order1"), new Order("order2"));
        });
    }

    // 模拟查询用户积分
    private CompletableFuture<Integer> queryPoints(String userId) {
        return CompletableFuture.supplyAsync(() -> {
            sleep(80);
            return 1000;
        });
    }

    // 并行查询，组合结果
    public UserDetailDTO getUserDetail(String userId) {
        CompletableFuture<UserInfo> userInfoFuture = queryUserInfo(userId);
        CompletableFuture<List<Order>> ordersFuture = queryOrders(userId);
        CompletableFuture<Integer> pointsFuture = queryPoints(userId);

        // 等待所有查询完成，组合结果
        return CompletableFuture.allOf(userInfoFuture, ordersFuture, pointsFuture)
            .thenApply(v -> {
                UserInfo userInfo = userInfoFuture.join();
                List<Order> orders = ordersFuture.join();
                Integer points = pointsFuture.join();

                return new UserDetailDTO(userInfo, orders, points);
            })
            .join();  // 阻塞等待最终结果
    }
}
```

**优势**：
- 串行执行需要：100 + 150 + 80 = 330ms
- 并行执行仅需：max(100, 150, 80) = 150ms
- 性能提升：**2.2倍**

### 4.2 超时控制与降级

```java
public String queryWithTimeout(String userId) {
    CompletableFuture<String> future = CompletableFuture.supplyAsync(() -> {
        sleep(3000);  // 模拟慢查询
        return "查询结果";
    });

    try {
        // 设置超时时间：1秒
        return future.get(1, TimeUnit.SECONDS);
    } catch (TimeoutException e) {
        System.err.println("查询超时，返回默认值");
        return "默认值";  // 降级处理
    } catch (Exception e) {
        System.err.println("查询异常：" + e.getMessage());
        return "异常默认值";
    }
}

// Java 9+：使用 orTimeout 和 completeOnTimeout
public String queryWithTimeoutJava9(String userId) {
    return CompletableFuture.supplyAsync(() -> {
        sleep(3000);
        return "查询结果";
    })
    .orTimeout(1, TimeUnit.SECONDS)  // 超时抛出异常
    .exceptionally(ex -> "默认值")    // 处理超时异常
    .join();
}

public String queryWithDefaultValue(String userId) {
    return CompletableFuture.supplyAsync(() -> {
        sleep(3000);
        return "查询结果";
    })
    .completeOnTimeout("默认值", 1, TimeUnit.SECONDS)  // 超时返回默认值
    .join();
}
```

### 4.3 异步回调链

```java
public class AsyncCallbackChainDemo {

    public void processOrder(String orderId) {
        CompletableFuture.supplyAsync(() -> {
            // 步骤1：查询订单
            System.out.println("查询订单：" + orderId);
            return getOrder(orderId);
        })
        .thenApplyAsync(order -> {
            // 步骤2：库存扣减
            System.out.println("扣减库存");
            return deductStock(order);
        })
        .thenApplyAsync(order -> {
            // 步骤3：创建支付单
            System.out.println("创建支付单");
            return createPayment(order);
        })
        .thenAcceptAsync(payment -> {
            // 步骤4：发送通知
            System.out.println("发送支付通知");
            sendNotification(payment);
        })
        .exceptionally(ex -> {
            // 异常处理
            System.err.println("订单处理失败：" + ex.getMessage());
            rollback(orderId);  // 回滚操作
            return null;
        });
    }
}
```

---

## 五、最佳实践

### 5.1 务必指定线程池

```java
// ❌ 不推荐：使用默认的 ForkJoinPool.commonPool()
CompletableFuture.supplyAsync(() -> "result");

// ✅ 推荐：指定业务线程池
ExecutorService executor = new ThreadPoolExecutor(
    10, 20, 60L, TimeUnit.SECONDS,
    new LinkedBlockingQueue<>(1000),
    new ThreadFactoryBuilder().setNameFormat("async-pool-%d").build(),
    new ThreadPoolExecutor.CallerRunsPolicy()
);

CompletableFuture.supplyAsync(() -> "result", executor);
```

**原因**：
- `ForkJoinPool.commonPool()` 是全局共享的，线程数有限（默认为 CPU 核心数 - 1）
- 不同业务混用会互相影响，导致任务排队
- 自定义线程池可以根据业务特性调优，并且便于监控

### 5.2 避免阻塞操作

```java
// ❌ 不要在回调中执行阻塞操作
CompletableFuture.supplyAsync(() -> "result")
    .thenApply(s -> {
        // 错误：在回调中执行阻塞 I/O
        return syncHttpCall(s);  // 阻塞线程池
    });

// ✅ 改为异步执行
CompletableFuture.supplyAsync(() -> "result")
    .thenComposeAsync(s -> asyncHttpCall(s), executor);  // 异步执行
```

### 5.3 异常处理要完整

```java
// ❌ 不处理异常，可能导致任务静默失败
CompletableFuture.supplyAsync(() -> {
    throw new RuntimeException("异常");
});

// ✅ 完整的异常处理
CompletableFuture.supplyAsync(() -> {
    if (Math.random() > 0.5) {
        throw new RuntimeException("业务异常");
    }
    return "成功";
})
.exceptionally(ex -> {
    log.error("任务执行失败", ex);
    return "默认值";
})
.thenAccept(result -> {
    log.info("最终结果：{}", result);
});
```

### 5.4 避免过长的调用链

```java
// ❌ 调用链过长，难以维护
CompletableFuture.supplyAsync(() -> step1())
    .thenApply(r -> step2(r))
    .thenApply(r -> step3(r))
    .thenApply(r -> step4(r))
    .thenApply(r -> step5(r))
    .thenApply(r -> step6(r))
    .thenApply(r -> step7(r));

// ✅ 拆分为多个方法
public CompletableFuture<Result> processTask() {
    return step1And2()
        .thenCompose(r -> step3And4(r))
        .thenCompose(r -> step5And6(r));
}
```

---

## 六、核心要点

### 6.1 关键API对比

| API | 参数 | 返回值 | 场景 |
|-----|------|--------|------|
| `thenApply` | 有 | 有 | 转换结果 |
| `thenAccept` | 有 | 无 | 消费结果 |
| `thenRun` | 无 | 无 | 通知完成 |
| `thenCompose` | 有 | CompletableFuture | 扁平化嵌套 |
| `thenCombine` | 两个CF | 合并结果 | 并行任务合并 |
| `allOf` | 多个CF | Void | 等待所有完成 |
| `anyOf` | 多个CF | Object | 任意一个完成 |

### 6.2 异常处理对比

| API | 是否改变结果 | 是否传播异常 | 场景 |
|-----|------------|------------|------|
| `exceptionally` | 是 | 否 | 捕获异常，返回默认值 |
| `handle` | 是 | 否 | 统一处理结果和异常 |
| `whenComplete` | 否 | 是 | 类似finally，不影响结果 |

### 6.3 性能优化建议

1. **使用自定义线程池**：避免共享 `ForkJoinPool`，防止任务排队
2. **批量任务使用 allOf**：并行执行，等待所有完成
3. **超时控制**：使用 `orTimeout` 或 `get(timeout)` 避免无限等待
4. **避免阻塞操作**：使用 `Async` 版本的方法
5. **异常处理**：使用 `exceptionally` 或 `handle` 兜底

---

## 总结

CompletableFuture是Java 8引入的强大异步编程工具，解决了传统Future的诸多痛点：

**核心优势**：
- ✅ **非阻塞**：支持回调，不阻塞主线程
- ✅ **可组合**：支持任务串联、并行、组合
- ✅ **异常友好**：完善的异常处理机制
- ✅ **超时控制**：灵活的超时和降级策略

**实战要点**：
1. **务必指定线程池**，避免使用默认的 `commonPool`
2. **完整的异常处理**，避免任务静默失败
3. **避免过长调用链**，保持代码可维护性
4. **合理使用超时控制**，防止任务无限等待

**下一篇预告**：我们将深入 ForkJoinPool 的工作窃取算法，理解其如何高效处理并行任务！
