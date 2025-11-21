---
title: "渠道共享库存中心：Redis分布式锁的生产实践"
date: 2025-10-15T17:00:00+08:00
draft: false
tags: ["Redis", "分布式锁", "高并发", "库存系统", "供应链"]
categories: ["技术"]
description: "从一次库存超卖事故出发，深度解析Redis分布式锁在电商库存系统中的完整应用，包含Redisson实战代码、性能优化方案和生产踩坑经验。"
series: ["供应链系统实战"]
weight: 42
stage: 3
stageTitle: "特性进阶篇"
comments: true
---

## 引子：一次价值百万的库存超卖事故

2024年双十一，凌晨00:05分，我的手机突然响起刺耳的告警声。

打开监控大盘，一行红色数字让我瞬间清醒：**某爆款SKU超卖217件**。这意味着我们已经卖出了比实际库存多217件商品，客户投诉、赔偿成本、品牌信任危机接踵而至。

这不是我第一次遇到超卖问题，但这次的损失格外惨重——该SKU是限量联名款，成本价就超过500元，217件的赔偿成本加上品牌损失，直接损失超过百万。

**事后复盘**，我们发现问题的根源：**在分布式环境下，单机锁完全失效了。**

10个服务实例同时处理来自Amazon、Shopify、天猫国际等多个渠道的订单，每个实例内部的`synchronized`锁只能保证单个JVM内的线程安全，但对于跨JVM的并发请求，库存扣减的原子性荡然无存。

这次事故后，我们用了整整一周时间，重构了整个库存中心的并发控制机制，**将Redis分布式锁引入生产环境**。三个月后，超卖率从5%降至0.1%，系统TPS从200提升到2000。

这篇文章，就是那次重构的完整技术总结。

---

## 问题本质：分布式环境下的并发控制

### 业务场景

我们的渠道共享库存中心需要服务10+电商平台，这些平台的订单会同时扣减同一个商品的库存：

```
时间   渠道         SKU-1001  操作      当前库存
00:01  Amazon      -1        扣减      100 → 99
00:01  Shopify     -2        扣减       99 → 97
00:01  天猫国际     -1        扣减       97 → 96
00:01  独立站       -3        扣减       96 → 93
```

在分布式部署下（假设5个服务实例），这些请求可能被不同的实例处理。如果没有正确的并发控制机制，就会出现经典的**竞态条件（Race Condition）**。

### 错误方案的代价

我们尝试过的失败方案：

#### ❌ 方案1：数据库行锁

```sql
SELECT * FROM inventory WHERE sku = 'SKU-1001' FOR UPDATE;
UPDATE inventory SET quantity = quantity - 1 WHERE sku = 'SKU-1001';
```

**问题**：
- 性能极差：TPS<50，远低于业务需求
- 锁等待严重：高并发时大量请求超时
- 数据库压力大：成为系统瓶颈

#### ❌ 方案2：乐观锁（版本号）

```java
// 基于版本号的乐观锁
UPDATE inventory
SET quantity = quantity - 1, version = version + 1
WHERE sku = 'SKU-1001' AND version = 10;
```

**问题**：
- 高并发失败率高达70%
- 重试风暴：大量失败请求重试，雪上加霜
- 用户体验差：下单失败率高

#### ❌ 方案3：单机锁（synchronized）

```java
public synchronized boolean reduceStock(String sku, int quantity) {
    // 只能保证单个JVM内的线程安全
}
```

**问题**：
- 分布式环境完全失效
- 导致我们那次百万级的超卖事故

---

## 技术方案：Redis分布式锁实战

### 方案选型

经过技术选型，我们最终选择了**Redisson**作为分布式锁的实现框架：

| 方案 | 优点 | 缺点 | 是否选用 |
|------|------|------|---------|
| Redis SETNX + DEL | 简单直接 | 需要手动处理过期、重入等问题 | ❌ |
| Redisson | 功能完善、久经考验 | 引入额外依赖 | ✅ |
| Zookeeper | 强一致性 | 性能较差、运维复杂 | ❌ |
| 数据库 | 无需额外组件 | 性能最差 | ❌ |

### 核心代码实现

#### 1. Maven依赖

```xml
<dependency>
    <groupId>org.redisson</groupId>
    <artifactId>redisson-spring-boot-starter</artifactId>
    <version>3.23.5</version>
</dependency>
```

#### 2. Redisson配置

```java
@Configuration
public class RedissonConfig {

    @Bean
    public RedissonClient redissonClient() {
        Config config = new Config();
        config.useSingleServer()
              .setAddress("redis://localhost:6379")
              .setConnectionPoolSize(64)
              .setConnectionMinimumIdleSize(10)
              .setPassword("your_password");

        return Redisson.create(config);
    }
}
```

#### 3. 库存服务实现

```java
@Service
@Slf4j
public class InventoryService {

    @Autowired
    private RedissonClient redissonClient;

    @Autowired
    private InventoryRepository inventoryRepository;

    @Autowired
    private RocketMQTemplate rocketMQTemplate;

    /**
     * 扣减库存（分布式锁版本）
     * @param sku 商品SKU
     * @param quantity 扣减数量
     * @return 是否成功
     */
    public boolean reduceStock(String sku, int quantity) {
        // 锁的粒度：每个SKU一把锁
        String lockKey = "inventory:lock:" + sku;
        RLock lock = redissonClient.getLock(lockKey);

        try {
            // 尝试加锁：最多等待10秒，锁30秒后自动释放
            boolean acquired = lock.tryLock(10, 30, TimeUnit.SECONDS);

            if (!acquired) {
                log.warn("获取库存锁失败，SKU: {}", sku);
                return false;
            }

            // 业务逻辑：检查并扣减库存
            Inventory inventory = inventoryRepository.findBySku(sku);

            if (inventory == null) {
                log.error("商品不存在，SKU: {}", sku);
                return false;
            }

            if (inventory.getQuantity() < quantity) {
                log.warn("库存不足，SKU: {}, 当前库存: {}, 需要: {}",
                    sku, inventory.getQuantity(), quantity);
                return false;
            }

            // 扣减库存
            inventory.setQuantity(inventory.getQuantity() - quantity);
            inventoryRepository.save(inventory);

            // 发送库存变更消息（异步通知其他渠道）
            InventoryChangeEvent event = new InventoryChangeEvent(
                sku, -quantity, inventory.getQuantity());
            rocketMQTemplate.convertAndSend("inventory-change", event);

            log.info("库存扣减成功，SKU: {}, 扣减: {}, 剩余: {}",
                sku, quantity, inventory.getQuantity());
            return true;

        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            log.error("库存扣减被中断，SKU: {}", sku, e);
            return false;
        } finally {
            // 释放锁（必须在finally块中）
            if (lock.isHeldByCurrentThread()) {
                lock.unlock();
            }
        }
    }
}
```

#### 4. 关键细节解析

**① 锁的粒度设计**

```java
String lockKey = "inventory:lock:" + sku;  // ✅ 每个SKU一把锁（细粒度）
String lockKey = "inventory:lock:global";  // ❌ 全局锁（粗粒度，性能差）
```

细粒度锁的优势：
- SKU-1001和SKU-1002可以并发扣减
- 提升系统吞吐量
- 减少锁竞争

**② 超时时间设置**

```java
lock.tryLock(10, 30, TimeUnit.SECONDS);
//          ↑   ↑
//          |   锁的过期时间（防止死锁）
//          等待获取锁的最长时间
```

实践经验：
- **等待时间** = 业务正常响应时间 × 2
- **过期时间** = 业务最长执行时间 × 2 + 缓冲时间(5s)

**③ 异常处理**

```java
finally {
    if (lock.isHeldByCurrentThread()) {  // 必须检查锁是否由当前线程持有
        lock.unlock();
    }
}
```

为什么要检查`isHeldByCurrentThread()`？
- 避免释放别人的锁
- 避免锁过期后误解锁

---

## 生产优化：从理论到实战

### 性能优化

#### 1. 批量扣减优化

当多个订单包含同一个SKU时，可以合并扣减：

```java
public Map<String, Boolean> batchReduceStock(Map<String, Integer> skuQuantityMap) {
    Map<String, Boolean> results = new ConcurrentHashMap<>();

    // 并发处理多个SKU
    skuQuantityMap.entrySet().parallelStream().forEach(entry -> {
        String sku = entry.getKey();
        Integer quantity = entry.getValue();
        results.put(sku, reduceStock(sku, quantity));
    });

    return results;
}
```

**效果**：TPS提升30%

#### 2. 异步化非核心操作

```java
// 发送消息改为异步
CompletableFuture.runAsync(() -> {
    rocketMQTemplate.convertAndSend("inventory-change", event);
});
```

**效果**：平均响应时间从150ms降至80ms

### 高可用保障

#### 1. Redis哨兵模式

```yaml
spring:
  redis:
    sentinel:
      master: mymaster
      nodes:
        - 192.168.1.10:26379
        - 192.168.1.11:26379
        - 192.168.1.12:26379
```

**效果**：主从自动切换，可用性99.9%

#### 2. 降级方案

```java
@HystrixCommand(fallbackMethod = "reduceStockFallback")
public boolean reduceStock(String sku, int quantity) {
    // 正常流程
}

public boolean reduceStockFallback(String sku, int quantity) {
    // 降级：记录到数据库，异步处理
    log.warn("库存扣减降级，SKU: {}", sku);
    asyncInventoryService.recordPendingReduce(sku, quantity);
    return true;  // 先让订单通过，后台异步补偿
}
```

### 边界案例处理

#### 1. 库存预占（下单未支付）

```java
public boolean reserveStock(String sku, int quantity, String orderId) {
    String lockKey = "inventory:lock:" + sku;
    RLock lock = redissonClient.getLock(lockKey);

    try {
        lock.lock(30, TimeUnit.SECONDS);

        // 扣减可用库存
        inventory.setAvailableQuantity(inventory.getAvailableQuantity() - quantity);
        // 增加预占库存
        inventory.setReservedQuantity(inventory.getReservedQuantity() + quantity);

        // 设置30分钟后自动释放
        redisTemplate.opsForValue().set(
            "inventory:reserve:" + orderId,
            quantity,
            30,
            TimeUnit.MINUTES
        );

        return true;
    } finally {
        lock.unlock();
    }
}
```

#### 2. 库存释放（订单取消）

```java
@Scheduled(fixedRate = 60000)  // 每分钟执行一次
public void releaseExpiredReservations() {
    List<String> expiredOrders = findExpiredOrders();

    for (String orderId : expiredOrders) {
        String sku = getSkuByOrder(orderId);
        Integer quantity = redisTemplate.opsForValue().get("inventory:reserve:" + orderId);

        if (quantity != null) {
            // 释放库存
            releaseStock(sku, quantity, orderId);
        }
    }
}
```

---

## 效果数据与经验总结

### 上线效果

| 指标 | 优化前 | 优化后 | 提升 |
|------|--------|--------|------|
| 超卖率 | 5% | 0.1% | **降低50倍** |
| 系统TPS | 200 | 2000 | **提升10倍** |
| 平均响应时间 | 300ms | 80ms | **降低73%** |
| 系统可用性 | 98.5% | 99.9% | **提升1.4%** |

### 核心经验

#### ✅ DO - 应该这样做

1. **锁粒度要细**：按SKU加锁而非全局锁
2. **过期时间要合理**：业务耗时 × 2 + 缓冲时间
3. **失败要重试**：结合消息队列异步补偿
4. **监控要完善**：实时告警 + 日志追踪
5. **降级要准备**：高峰期保护核心链路

#### ❌ DON'T - 不要这样做

1. **不要使用全局锁**：严重影响并发性能
2. **不要无限等待**：必须设置超时时间
3. **不要忘记解锁**：使用try-finally保证释放
4. **不要过度依赖锁**：能异步的尽量异步
5. **不要忽略边界情况**：预占、释放、超时都要考虑

---

## 参考资料

- [Redis官方文档 - Distributed Locks](https://redis.io/docs/manual/patterns/distributed-locks/)
- [Redisson GitHub](https://github.com/redisson/redisson)
- [分布式锁的正确姿势](https://martin.kleppmann.com/2016/02/08/how-to-do-distributed-locking.html)

---

## 系列文章预告

本文是《供应链系统实战》系列的第一篇，后续文章：

- **第2篇**：跨境电商关务系统 - 三单对碰的技术实现
- **第3篇**：WMS仓储系统 - 库位分配算法的演进之路
- **第4篇**：OMS订单系统 - 智能拆单规则引擎设计
- **第5篇**：供应链数据中台 - Flink实时计算架构实战

敬请期待！

---

*如果这篇文章对你有帮助，欢迎在评论区分享你的经验或提出问题。*
