---
title: "分布式锁实战：从SETNX到Redlock"
date: 2025-01-21T22:30:00+08:00
draft: false
tags: ["Redis", "分布式锁", "Redlock", "并发"]
categories: ["技术"]
description: "掌握Redis分布式锁的实现方案，从基础SETNX到Redlock算法，解决库存扣减、订单防重等并发问题"
weight: 26
stage: 3
stageTitle: "进阶特性篇"
---

## 为什么需要分布式锁？

**单机锁的局限**：
```java
// ❌ 单机环境有效
synchronized (this) {
    // 扣减库存
}

// ❌ 分布式环境失效
// 服务器1和服务器2的锁互不影响
```

**分布式锁特性**：
- 互斥性：同一时刻只有一个客户端持有锁
- 安全性：只有持锁者能释放锁
- 可用性：高可用，避免死锁
- 性能：加锁解锁快速

## 方案演进

### V1：基础版（SETNX + EXPIRE）

```java
public boolean lock(String key, String value, long expireSeconds) {
    Boolean success = redis.opsForValue().setIfAbsent(key, value);
    if (Boolean.TRUE.equals(success)) {
        redis.expire(key, expireSeconds, TimeUnit.SECONDS);
        return true;
    }
    return false;
}

// ❌ 问题：SETNX和EXPIRE不是原子操作
// 如果SETNX成功后宕机，锁永不过期
```

### V2：原子操作版（SET NX EX）

```java
public boolean lock(String key, String value, long expireSeconds) {
    Boolean success = redis.opsForValue()
        .setIfAbsent(key, value, expireSeconds, TimeUnit.SECONDS);
    return Boolean.TRUE.equals(success);
}

public void unlock(String key) {
    redis.delete(key);
}

// ❌ 问题：可能释放别人的锁
// 线程A持锁超时，锁自动释放
// 线程B获得锁
// 线程A执行完，删除了线程B的锁
```

### V3：安全释放版（Lua脚本）

```java
public class DistributedLock {
    @Autowired
    private RedisTemplate<String, String> redis;

    private static final String UNLOCK_SCRIPT =
        "if redis.call('GET', KEYS[1]) == ARGV[1] then " +
        "  return redis.call('DEL', KEYS[1]) " +
        "else " +
        "  return 0 " +
        "end";

    // 加锁
    public boolean lock(String key, String requestId, long expireSeconds) {
        Boolean success = redis.opsForValue()
            .setIfAbsent(key, requestId, expireSeconds, TimeUnit.SECONDS);
        return Boolean.TRUE.equals(success);
    }

    // 安全解锁
    public boolean unlock(String key, String requestId) {
        Long result = redis.execute(
            RedisScript.of(UNLOCK_SCRIPT, Long.class),
            Collections.singletonList(key),
            requestId
        );
        return result != null && result == 1;
    }
}

// ✅ 优势：原子性校验和删除
// ❌ 问题：业务执行时间超过锁过期时间
```

### V4：自动续期版（看门狗）

```java
@Component
public class RedisLockWithWatchdog {
    @Autowired
    private RedisTemplate<String, String> redis;

    private static final long DEFAULT_EXPIRE_SECONDS = 30;
    private static final long RENEW_INTERVAL_SECONDS = 10;

    private final Map<String, ScheduledFuture<?>> renewTasks = new ConcurrentHashMap<>();
    private final ScheduledExecutorService scheduler = Executors.newScheduledThreadPool(1);

    public boolean lock(String key, String requestId) {
        Boolean success = redis.opsForValue()
            .setIfAbsent(key, requestId, DEFAULT_EXPIRE_SECONDS, TimeUnit.SECONDS);

        if (Boolean.TRUE.equals(success)) {
            // 启动续期任务
            startRenewTask(key, requestId);
            return true;
        }
        return false;
    }

    private void startRenewTask(String key, String requestId) {
        ScheduledFuture<?> task = scheduler.scheduleAtFixedRate(() -> {
            try {
                String value = redis.opsForValue().get(key);
                if (requestId.equals(value)) {
                    redis.expire(key, DEFAULT_EXPIRE_SECONDS, TimeUnit.SECONDS);
                    log.debug("锁续期成功: {}", key);
                } else {
                    // 锁已被他人持有，停止续期
                    stopRenewTask(key);
                }
            } catch (Exception e) {
                log.error("锁续期失败", e);
            }
        }, RENEW_INTERVAL_SECONDS, RENEW_INTERVAL_SECONDS, TimeUnit.SECONDS);

        renewTasks.put(key, task);
    }

    public boolean unlock(String key, String requestId) {
        stopRenewTask(key);

        String script =
            "if redis.call('GET', KEYS[1]) == ARGV[1] then " +
            "  return redis.call('DEL', KEYS[1]) " +
            "else " +
            "  return 0 " +
            "end";

        Long result = redis.execute(
            RedisScript.of(script, Long.class),
            Collections.singletonList(key),
            requestId
        );
        return result != null && result == 1;
    }

    private void stopRenewTask(String key) {
        ScheduledFuture<?> task = renewTasks.remove(key);
        if (task != null) {
            task.cancel(false);
        }
    }
}
```

## 实战案例

### 案例1：库存扣减

```java
@Service
public class StockService {
    @Autowired
    private RedisLockWithWatchdog redisLock;
    @Autowired
    private RedisTemplate<String, Object> redis;

    public boolean deductStock(String productId, int quantity) {
        String lockKey = "lock:stock:" + productId;
        String requestId = UUID.randomUUID().toString();

        try {
            // 尝试获取锁（超时3秒）
            if (!tryLock(lockKey, requestId, 3000)) {
                return false;  // 获取锁失败
            }

            // 检查库存
            Integer stock = (Integer) redis.opsForValue().get("stock:" + productId);
            if (stock == null || stock < quantity) {
                return false;  // 库存不足
            }

            // 扣减库存
            redis.opsForValue().decrement("stock:" + productId, quantity);
            return true;

        } finally {
            // 释放锁
            redisLock.unlock(lockKey, requestId);
        }
    }

    private boolean tryLock(String key, String requestId, long timeoutMs) {
        long startTime = System.currentTimeMillis();
        while (System.currentTimeMillis() - startTime < timeoutMs) {
            if (redisLock.lock(key, requestId)) {
                return true;
            }
            try {
                Thread.sleep(50);  // 等待50ms后重试
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return false;
            }
        }
        return false;
    }
}
```

### 案例2：订单防重

```java
@Service
public class OrderService {
    @Autowired
    private RedisLockWithWatchdog redisLock;

    public String createOrder(OrderRequest request) {
        String lockKey = "lock:order:" + request.getUserId() + ":" + request.getOrderNo();
        String requestId = UUID.randomUUID().toString();

        try {
            if (!redisLock.lock(lockKey, requestId)) {
                throw new BusinessException("订单正在处理中，请勿重复提交");
            }

            // 创建订单逻辑
            Order order = new Order();
            order.setOrderNo(request.getOrderNo());
            // ... 保存订单

            return order.getOrderNo();

        } finally {
            redisLock.unlock(lockKey, requestId);
        }
    }
}
```

### 案例3：定时任务防重

```java
@Component
public class ScheduledTaskWithLock {
    @Autowired
    private RedisLockWithWatchdog redisLock;

    @Scheduled(cron = "0 */5 * * * ?")  // 每5分钟执行
    public void syncData() {
        String lockKey = "lock:task:sync_data";
        String requestId = UUID.randomUUID().toString();

        if (!redisLock.lock(lockKey, requestId)) {
            log.info("其他节点正在执行同步任务，跳过");
            return;
        }

        try {
            log.info("开始执行同步任务");
            // 执行同步逻辑
            doSync();
        } finally {
            redisLock.unlock(lockKey, requestId);
        }
    }

    private void doSync() {
        // 同步逻辑
    }
}
```

## Redlock算法（多Redis实例）

**问题**：单Redis实例有单点故障风险

**Redlock方案**：
```
部署5个独立的Redis实例（不是主从）

加锁流程：
1. 获取当前时间戳
2. 依次向5个实例加锁
3. 如果>=3个实例加锁成功，且总耗时<锁过期时间，则成功
4. 否则，向所有实例释放锁

解锁流程：
向所有5个实例释放锁
```

**Java实现**（Redisson）：
```java
@Configuration
public class RedissonConfig {
    @Bean
    public RedissonClient redissonClient() {
        Config config = new Config();
        config.useSingleServer()
            .setAddress("redis://127.0.0.1:6379");
        return Redisson.create(config);
    }
}

@Service
public class RedissonLockService {
    @Autowired
    private RedissonClient redisson;

    public void executeWithLock(String lockKey, Runnable task) {
        RLock lock = redisson.getLock(lockKey);
        try {
            // 尝试加锁，最多等待100秒，锁自动释放时间30秒
            if (lock.tryLock(100, 30, TimeUnit.SECONDS)) {
                task.run();
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        } finally {
            if (lock.isHeldByCurrentThread()) {
                lock.unlock();
            }
        }
    }
}
```

## 最佳实践

### 1. 锁的粒度要细

```java
// ❌ 不好：粒度太粗
String lockKey = "lock:order";  // 所有订单共用一把锁

// ✅ 好：细粒度锁
String lockKey = "lock:order:" + userId;  // 每个用户一把锁
```

### 2. 设置合理的超时时间

```java
// 根据业务执行时间设置
// 快速操作：5-10秒
// 慢操作：30-60秒
// 加上看门狗自动续期
```

### 3. 降级方案

```java
public boolean deductStock(String productId, int quantity) {
    String lockKey = "lock:stock:" + productId;
    String requestId = UUID.randomUUID().toString();

    try {
        if (!tryLock(lockKey, requestId, 3000)) {
            // 降级方案：使用Lua脚本原子操作
            return deductStockWithLua(productId, quantity);
        }

        // 正常流程
        return doDeductStock(productId, quantity);

    } finally {
        unlock(lockKey, requestId);
    }
}
```

### 4. 监控告警

```java
@Aspect
@Component
public class LockMonitorAspect {
    @Around("@annotation(DistributedLock)")
    public Object around(ProceedingJoinPoint pjp, DistributedLock lock) throws Throwable {
        long startTime = System.currentTimeMillis();
        String lockKey = lock.key();

        try {
            Object result = pjp.proceed();
            long duration = System.currentTimeMillis() - startTime;

            // 监控：锁持有时间过长告警
            if (duration > 10000) {
                log.warn("锁持有时间过长: key={}, duration={}ms", lockKey, duration);
            }
            return result;
        } catch (Exception e) {
            log.error("加锁执行异常: key={}", lockKey, e);
            throw e;
        }
    }
}
```

## 常见问题

### 1. 锁超时释放

**问题**：业务还没执行完，锁就过期了

**解决**：
- 使用看门狗自动续期
- 设置足够长的超时时间
- 优化业务逻辑，减少执行时间

### 2. 死锁

**问题**：持锁进程崩溃，锁永不释放

**解决**：
- 设置锁过期时间（必须）
- 避免过长的业务逻辑

### 3. 锁重入

**问题**：同一线程多次获取同一把锁

**解决**：使用Redisson的可重入锁
```java
RLock lock = redisson.getLock("mylock");
lock.lock();
try {
    // 业务逻辑
    doSomething();  // 内部可能再次获取同一把锁
} finally {
    lock.unlock();
}
```

## 总结

**方案选择**：
- **简单场景**：SETNX + Lua脚本释放
- **复杂场景**：自动续期（看门狗）
- **高可用要求**：Redlock（多实例）
- **生产推荐**：Redisson（功能完善）

**核心要点**：
- 原子性加锁（SET NX EX）
- 安全释放（Lua脚本校验）
- 自动续期（避免超时）
- 细粒度锁（提高并发）
- 降级方案（Redis不可用）

**典型场景**：
- 库存扣减、秒杀
- 订单防重提交
- 定时任务防重
- 资源独占访问
