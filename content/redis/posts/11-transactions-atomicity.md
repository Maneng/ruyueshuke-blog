---
title: "事务与原子性：MULTI/EXEC命令详解"
date: 2025-01-21T15:00:00+08:00
draft: false
tags: ["Redis", "事务", "MULTI", "WATCH", "原子性"]
categories: ["技术"]
description: "深入理解Redis事务机制，掌握MULTI/EXEC/DISCARD/WATCH命令。理解Redis事务与关系型数据库事务的区别，实现原子性操作。"
weight: 11
stage: 1
stageTitle: "基础入门篇"
---

## 引言

在关系型数据库中，事务是保证数据一致性的重要手段（ACID）。那么**Redis有事务吗？**

答案是：**有，但不完全是你理解的那种事务**。

Redis的事务更像是**批量命令**，提供的是**有限的原子性**，而不是ACID中的那种强事务。

## 一、Redis事务的本质

### 1.1 什么是Redis事务？

Redis事务是**一组命令的集合**，这些命令会：
1. **顺序执行**：按队列顺序依次执行
2. **不被打断**：执行期间不会插入其他客户端的命令
3. **要么全执行，要么全不执行**（有限制）

**示例**：

```bash
127.0.0.1:6379> MULTI  # 开始事务
OK

127.0.0.1:6379> SET account:1 100
QUEUED

127.0.0.1:6379> SET account:2 200
QUEUED

127.0.0.1:6379> EXEC  # 执行事务
1) OK
2) OK
```

### 1.2 Redis事务 vs 关系型数据库事务

| 特性 | MySQL事务 | Redis事务 |
|------|-----------|-----------|
| **原子性（A）** | ✅ 全部成功或回滚 | ⚠️ 部分支持 |
| **一致性（C）** | ✅ 约束检查 | ⚠️ 无约束 |
| **隔离性（I）** | ✅ 多种隔离级别 | ⚠️ 无隔离级别 |
| **持久性（D）** | ✅ 提交后持久化 | ⚠️ 取决于配置 |
| **回滚** | ✅ 支持 | ❌ 不支持 |

**关键区别**：

```
MySQL：
BEGIN;
UPDATE account SET balance = balance - 100 WHERE id = 1;
UPDATE account SET balance = balance + 100 WHERE id = 2;
COMMIT;  -- 要么都成功，要么都回滚

Redis：
MULTI
DECR account:1:balance 100
INCR account:2:balance 100
EXEC  -- 命令出错也不回滚！
```

## 二、事务命令详解

### 2.1 MULTI - 开始事务

```bash
127.0.0.1:6379> MULTI
OK

# 此后的命令不会立即执行，而是进入队列
127.0.0.1:6379> SET key1 "value1"
QUEUED  # 入队

127.0.0.1:6379> SET key2 "value2"
QUEUED
```

### 2.2 EXEC - 执行事务

```bash
127.0.0.1:6379> EXEC
1) OK       # SET key1的返回值
2) OK       # SET key2的返回值

# 所有命令顺序执行，一次性返回结果
```

### 2.3 DISCARD - 取消事务

```bash
127.0.0.1:6379> MULTI
OK

127.0.0.1:6379> SET key1 "value1"
QUEUED

127.0.0.1:6379> DISCARD  # 取消事务
OK

# 队列中的命令全部丢弃，不执行
127.0.0.1:6379> GET key1
(nil)  # 没有执行
```

### 2.4 WATCH - 乐观锁

**问题场景**：

```
时刻1：客户端A读取 balance = 100
时刻2：客户端B修改 balance = 200
时刻3：客户端A基于100扣款，balance = 50  # 错误！
```

**WATCH机制**：

```bash
# 客户端A
127.0.0.1:6379> WATCH balance
OK

127.0.0.1:6379> GET balance
"100"

# 客户端B（此时修改了balance）
127.0.0.1:6379> SET balance 200
OK

# 客户端A（事务失败）
127.0.0.1:6379> MULTI
OK
127.0.0.1:6379> SET balance 50
QUEUED
127.0.0.1:6379> EXEC
(nil)  # 返回nil，表示事务失败

# 原因：balance被修改了，WATCH检测到变化
```

**WATCH原理**：

```
1. WATCH key：监视一个或多个键
2. MULTI之前，如果key被修改，事务失败
3. EXEC返回nil，客户端可以重试
4. UNWATCH取消监视
```

**实战示例（转账）**：

```java
public boolean transfer(String fromAccount, String toAccount, int amount) {
    int maxRetries = 3;
    for (int i = 0; i < maxRetries; i++) {
        // 1. 监视余额
        redis.watch(fromAccount);

        // 2. 读取余额
        Integer balance = (Integer) redis.opsForValue().get(fromAccount);
        if (balance == null || balance < amount) {
            redis.unwatch();
            return false;  // 余额不足
        }

        // 3. 开始事务
        redis.multi();
        redis.opsForValue().set(fromAccount, balance - amount);
        redis.opsForValue().increment(toAccount, amount);

        // 4. 执行事务
        List<Object> results = redis.exec();

        if (results != null) {
            return true;  // 成功
        }

        // 事务失败，重试
        log.warn("转账事务冲突，重试第{}次", i + 1);
    }

    return false;  // 重试失败
}
```

## 三、Redis事务的原子性

### 3.1 两种错误

**1. 命令语法错误（入队失败）**

```bash
127.0.0.1:6379> MULTI
OK

127.0.0.1:6379> SET key1 "value1"
QUEUED

127.0.0.1:6379> SET key2  # 语法错误，缺少value
(error) ERR wrong number of arguments for 'set' command

127.0.0.1:6379> SET key3 "value3"
QUEUED

127.0.0.1:6379> EXEC
(error) EXECABORT Transaction discarded because of previous errors.

# 结果：所有命令都不执行（原子性✅）
127.0.0.1:6379> GET key1
(nil)
127.0.0.1:6379> GET key3
(nil)
```

**2. 命令执行错误（运行时错误）**

```bash
127.0.0.1:6379> MULTI
OK

127.0.0.1:6379> SET key1 "value1"
QUEUED

127.0.0.1:6379> INCR key1  # key1是字符串，不能INCR
QUEUED

127.0.0.1:6379> SET key2 "value2"
QUEUED

127.0.0.1:6379> EXEC
1) OK                                                      # SET成功
2) (error) ERR value is not an integer or out of range    # INCR失败
3) OK                                                      # SET成功

# 结果：错误命令失败，其他命令成功（无原子性❌）
127.0.0.1:6379> GET key1
"value1"  # 存在
127.0.0.1:6379> GET key2
"value2"  # 存在
```

**结论**：
- ✅ 语法错误：全部不执行（有原子性）
- ❌ 运行时错误：部分执行（无原子性，不回滚）

### 3.2 为什么不支持回滚？

Redis官方的解释：

```
1. Redis命令只会因为错误的语法失败，生产环境不应该出现
2. 不支持回滚可以保持简单和快速
3. 回滚机制会影响性能
```

## 四、实战场景

### 场景1：库存扣减（简单版）

```java
public boolean deductStock(Long productId, int quantity) {
    String key = "product:stock:" + productId;

    redis.multi();
    redis.opsForValue().decrement(key, quantity);
    redis.opsForHash().increment("product:sales:" + productId, "count", quantity);

    List<Object> results = redis.exec();

    return results != null;
}
```

**问题**：没有检查库存是否充足！

### 场景2：库存扣减（WATCH版）

```java
public boolean deductStockWithCheck(Long productId, int quantity) {
    String stockKey = "product:stock:" + productId;
    int maxRetries = 3;

    for (int i = 0; i < maxRetries; i++) {
        // 1. 监视库存
        redis.watch(stockKey);

        // 2. 检查库存
        Integer stock = (Integer) redis.opsForValue().get(stockKey);
        if (stock == null || stock < quantity) {
            redis.unwatch();
            return false;  // 库存不足
        }

        // 3. 扣减库存
        redis.multi();
        redis.opsForValue().decrement(stockKey, quantity);
        redis.opsForHash().increment("product:sales:" + productId, "count", quantity);

        List<Object> results = redis.exec();

        if (results != null) {
            return true;  // 成功
        }

        // 冲突，重试
        log.warn("库存扣减冲突，重试第{}次", i + 1);
    }

    return false;
}
```

### 场景3：Lua脚本（更优方案）

**为什么用Lua？**

```
WATCH + MULTI + EXEC：
- 需要多次网络往返
- 可能冲突需要重试
- 复杂

Lua脚本：
- 一次性执行，原子性保证
- 不需要重试
- 简洁高效
```

**Lua脚本实现**：

```lua
-- deduct_stock.lua
local stock_key = KEYS[1]
local sales_key = KEYS[2]
local quantity = tonumber(ARGV[1])

-- 检查库存
local stock = redis.call('GET', stock_key)
if not stock or tonumber(stock) < quantity then
    return 0  -- 库存不足
end

-- 扣减库存
redis.call('DECRBY', stock_key, quantity)

-- 增加销量
redis.call('HINCRBY', sales_key, 'count', quantity)

return 1  -- 成功
```

**Java调用**：

```java
public boolean deductStockWithLua(Long productId, int quantity) {
    String stockKey = "product:stock:" + productId;
    String salesKey = "product:sales:" + productId;

    String script =
        "local stock_key = KEYS[1]\n" +
        "local sales_key = KEYS[2]\n" +
        "local quantity = tonumber(ARGV[1])\n" +
        "local stock = redis.call('GET', stock_key)\n" +
        "if not stock or tonumber(stock) < quantity then\n" +
        "    return 0\n" +
        "end\n" +
        "redis.call('DECRBY', stock_key, quantity)\n" +
        "redis.call('HINCRBY', sales_key, 'count', quantity)\n" +
        "return 1";

    List<String> keys = Arrays.asList(stockKey, salesKey);
    Long result = redis.execute(
            RedisScript.of(script, Long.class),
            keys,
            quantity
    );

    return result == 1L;
}
```

### 场景4：批量操作

```java
// 批量设置用户信息
public void batchSetUserInfo(Map<Long, User> users) {
    redis.multi();

    for (Map.Entry<Long, User> entry : users.entrySet()) {
        String key = "user:" + entry.getKey();
        redis.opsForValue().set(key, entry.getValue());
    }

    redis.exec();
}
```

## 五、最佳实践

### 5.1 何时使用事务？

**✅ 适合使用事务**：
- 批量操作，需要保证顺序执行
- 简单的原子性需求（如批量SET）
- 不需要条件判断的场景

**❌ 不适合使用事务**：
- 需要回滚
- 复杂的条件判断
- 依赖前一个命令的结果

**更好的选择**：
- **Lua脚本**：复杂逻辑、原子性保证
- **分布式锁**：跨Redis实例的原子性

### 5.2 事务 vs Lua脚本

| 维度 | 事务 | Lua脚本 |
|------|------|---------|
| **原子性** | 有限 | 完全 |
| **回滚** | 不支持 | 不需要 |
| **条件判断** | 需要WATCH | 直接支持 |
| **网络往返** | 多次 | 1次 |
| **性能** | 一般 | 更好 |
| **复杂度** | 高（WATCH重试） | 低 |

**推荐**：优先使用Lua脚本！

### 5.3 常见坑

**坑1：在事务中读取数据**

```java
// ❌ 错误：MULTI后的GET不会立即执行
redis.multi();
redis.opsForValue().set("key1", "value1");
String value = (String) redis.opsForValue().get("key1");  // 返回null！
redis.opsForValue().set("key2", value);
redis.exec();

// ✅ 正确：在MULTI之前读取
String value = (String) redis.opsForValue().get("key1");
redis.multi();
redis.opsForValue().set("key2", value);
redis.exec();
```

**坑2：忘记UNWATCH**

```java
// ❌ 错误：WATCH后没有UNWATCH
redis.watch("key");
// ... 检查逻辑
if (条件不满足) {
    return;  // 没有UNWATCH，key一直被监视
}

// ✅ 正确：总是UNWATCH
redis.watch("key");
try {
    // ... 检查逻辑
    if (条件不满足) {
        return;
    }
    // ... 事务逻辑
} finally {
    redis.unwatch();
}
```

**坑3：事务中使用Pipeline**

```java
// ❌ 错误：不能混用
redis.multi();
Pipeline pipeline = redis.pipelined();  // 错误！
pipeline.set("key1", "value1");
pipeline.sync();
redis.exec();

// ✅ 正确：分开使用
// 方式1：只用事务
redis.multi();
redis.opsForValue().set("key1", "value1");
redis.exec();

// 方式2：只用Pipeline
Pipeline pipeline = redis.pipelined();
pipeline.set("key1", "value1");
pipeline.sync();
```

## 六、总结

### 核心要点

1. **Redis事务是命令队列**：顺序执行，不被打断
2. **有限的原子性**：语法错误全失败，运行时错误不回滚
3. **不支持回滚**：与MySQL事务不同
4. **WATCH实现乐观锁**：监视键，冲突时事务失败
5. **Lua脚本更强大**：完全原子性、无需重试、性能更好
6. **适用场景**：简单批量操作，复杂逻辑用Lua

### 事务流程图

```
MULTI
  ↓
命令入队（QUEUED）
  ↓
命令入队（QUEUED）
  ↓
EXEC
  ↓
顺序执行所有命令
  ↓
返回结果数组
```

### WATCH流程图

```
WATCH key
  ↓
读取数据
  ↓
key被修改？
├─ Yes → EXEC返回nil（失败）
└─ No → EXEC正常执行
```

### 下一步

掌握了事务后，最后一篇我们将学习**Pipeline性能优化**：
- RTT延迟问题
- Pipeline批量操作
- Pipeline vs 事务 vs Lua

---

**思考题**：
1. 为什么Redis事务不支持回滚？
2. WATCH+MULTI+EXEC与Lua脚本有什么区别？
3. 什么场景下必须使用Lua脚本而不能用事务？

最后一篇见！
