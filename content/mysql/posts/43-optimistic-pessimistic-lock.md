---
title: "乐观锁与悲观锁：应用场景对比"
date: 2025-01-14T17:00:00+08:00
draft: false
tags: ["MySQL", "乐观锁", "悲观锁", "并发控制"]
categories: ["数据库"]
description: "深入理解乐观锁和悲观锁的原理、实现方式和适用场景，掌握高并发下的锁选择策略"
series: ["MySQL从入门到精通"]
weight: 43
stage: 4
stageTitle: "事务与锁篇"
---

## 乐观锁 vs 悲观锁

### 核心思想

| 类型    | 核心思想              | 锁机制        | 冲突处理   | 适用场景    |
|-------|-------------------|------------|--------|---------|
| **悲观锁** | 先加锁，再操作（悲观：总会冲突）  | 数据库锁（X锁、S锁） | 阻塞等待   | 冲突频繁    |
| **乐观锁** | 先操作，提交时检查（乐观：很少冲突） | 版本号、时间戳      | 重试或放弃  | 冲突少     |

---

## 1. 悲观锁（Pessimistic Lock）

### 定义

**假设冲突一定会发生**，每次读取数据前先加锁，其他事务无法修改数据。

### 实现方式

#### 方式1：排他锁（FOR UPDATE）

```sql
-- 加排他锁
START TRANSACTION;
SELECT * FROM account WHERE id = 1 FOR UPDATE; -- 加X锁，其他事务阻塞

-- 修改数据
UPDATE account SET balance = 900 WHERE id = 1;

COMMIT; -- 释放锁
```

#### 方式2：共享锁（LOCK IN SHARE MODE）

```sql
-- 加共享锁
START TRANSACTION;
SELECT * FROM account WHERE id = 1 LOCK IN SHARE MODE; -- 加S锁，其他事务可读但不可写

-- 读取后再更新
UPDATE account SET balance = 900 WHERE id = 1;

COMMIT;
```

### 应用场景

**场景1：库存扣减（防止超卖）**

```sql
-- 秒杀场景：10000个用户抢100件商品

START TRANSACTION;

-- 1. 加锁查询库存
SELECT stock FROM product WHERE id = 1001 FOR UPDATE; -- 悲观锁
-- stock = 100

-- 2. 检查库存
IF stock >= 1 THEN
    -- 3. 扣减库存
    UPDATE product SET stock = stock - 1 WHERE id = 1001;

    -- 4. 创建订单
    INSERT INTO orders (user_id, product_id) VALUES (123, 1001);

    COMMIT;
ELSE
    ROLLBACK; -- 库存不足
END IF;
```

**场景2：转账业务**

```sql
-- A向B转账100元

START TRANSACTION;

-- 1. 锁定双方账户
SELECT balance FROM account WHERE id IN (1, 2) FOR UPDATE;

-- 2. 检查余额
IF A.balance >= 100 THEN
    -- 3. 扣款和到账
    UPDATE account SET balance = balance - 100 WHERE id = 1;
    UPDATE account SET balance = balance + 100 WHERE id = 2;
    COMMIT;
ELSE
    ROLLBACK;
END IF;
```

**场景3：订单支付（防止重复支付）**

```sql
START TRANSACTION;

-- 1. 锁定订单
SELECT status FROM orders WHERE id = 12345 FOR UPDATE;

-- 2. 检查订单状态
IF status = 'UNPAID' THEN
    -- 3. 更新订单状态
    UPDATE orders SET status = 'PAID' WHERE id = 12345;

    -- 4. 扣减余额
    UPDATE account SET balance = balance - 100 WHERE user_id = 1;

    COMMIT;
ELSE
    ROLLBACK; -- 已支付或已取消
END IF;
```

### 优缺点

**优点**：
- ✅ 数据一致性强（真正的数据库锁）
- ✅ 适合高冲突场景（如秒杀、转账）

**缺点**：
- ❌ 性能开销大（阻塞等待）
- ❌ 可能死锁
- ❌ 降低并发性能

---

## 2. 乐观锁（Optimistic Lock）

### 定义

**假设冲突很少发生**，读取数据时不加锁，提交时检查数据是否被修改。

### 实现方式

#### 方式1：版本号（Version）

```sql
-- 1. 建表时添加版本号字段
CREATE TABLE product (
    id INT PRIMARY KEY,
    name VARCHAR(50),
    stock INT,
    version INT DEFAULT 0 -- 版本号
);

INSERT INTO product VALUES (1, 'iPhone', 100, 0);

-- 2. 查询数据（不加锁）
SELECT id, stock, version FROM product WHERE id = 1;
-- 返回：id=1, stock=100, version=0

-- 3. 更新数据（比较版本号）
UPDATE product
SET stock = stock - 1,
    version = version + 1
WHERE id = 1 AND version = 0; -- 仅当version=0时才更新

-- 4. 检查影响行数
-- 如果affected_rows=0，说明数据已被修改，更新失败，需要重试
```

#### 方式2：时间戳（Timestamp）

```sql
-- 1. 建表时添加更新时间字段
CREATE TABLE product (
    id INT PRIMARY KEY,
    name VARCHAR(50),
    stock INT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- 2. 查询数据
SELECT id, stock, updated_at FROM product WHERE id = 1;
-- 返回：id=1, stock=100, updated_at='2025-01-14 12:00:00'

-- 3. 更新数据（比较时间戳）
UPDATE product
SET stock = stock - 1
WHERE id = 1 AND updated_at = '2025-01-14 12:00:00'; -- 仅当时间戳匹配时才更新

-- 4. 检查影响行数
-- 如果affected_rows=0，更新失败，需要重试
```

### 应用场景

**场景1：商品秒杀（低冲突）**

```python
# Python示例（使用版本号）
def buy_product(product_id, quantity):
    max_retries = 3

    for i in range(max_retries):
        # 1. 查询商品信息（不加锁）
        product = db.query("SELECT stock, version FROM product WHERE id=%s", product_id)

        if product['stock'] < quantity:
            return {"success": False, "message": "库存不足"}

        # 2. 尝试扣减库存（乐观锁）
        affected_rows = db.execute("""
            UPDATE product
            SET stock = stock - %s,
                version = version + 1
            WHERE id = %s AND version = %s
        """, quantity, product_id, product['version'])

        # 3. 检查是否更新成功
        if affected_rows > 0:
            # 成功扣减库存
            return {"success": True, "message": "购买成功"}
        else:
            # 版本号冲突，重试
            print(f"版本冲突，重试第{i+1}次...")
            time.sleep(0.01)  # 短暂延迟

    return {"success": False, "message": "购买失败，请重试"}
```

**场景2：文章点赞（高并发，低冲突）**

```sql
-- 1. 建表
CREATE TABLE article (
    id INT PRIMARY KEY,
    title VARCHAR(100),
    likes INT DEFAULT 0,
    version INT DEFAULT 0
);

-- 2. 点赞（乐观锁）
-- 应用层代码
def like_article(article_id):
    # 查询当前点赞数和版本号
    article = db.query("SELECT likes, version FROM article WHERE id=%s", article_id)

    # 尝试更新
    affected_rows = db.execute("""
        UPDATE article
        SET likes = %s,
            version = version + 1
        WHERE id = %s AND version = %s
    """, article['likes'] + 1, article_id, article['version'])

    # 如果失败，重试（通常1-2次即可）
    if affected_rows == 0:
        return like_article(article_id)  # 递归重试
```

**场景3：用户信息更新（低并发）**

```sql
-- 1. 查询用户信息
SELECT id, name, email, version FROM user WHERE id = 1;
-- 返回：id=1, name='Alice', email='alice@example.com', version=5

-- 2. 用户修改邮箱
UPDATE user
SET email = 'newemail@example.com',
    version = version + 1
WHERE id = 1 AND version = 5;

-- 3. 检查结果
-- 如果affected_rows=0，说明其他人也在修改，提示用户刷新重试
```

### 优缺点

**优点**：
- ✅ 无锁，性能好，不阻塞
- ✅ 不会死锁
- ✅ 适合低冲突场景（如点赞、浏览量）

**缺点**：
- ❌ 冲突频繁时，重试次数多，性能下降
- ❌ 需要应用层处理重试逻辑
- ❌ 不适合高冲突场景（如秒杀）

---

## 对比总结

| 特性      | 悲观锁                  | 乐观锁               |
|---------|----------------------|-------------------|
| 锁机制     | 数据库锁（X锁、S锁）          | 版本号、时间戳           |
| 冲突假设    | 假设冲突一定会发生            | 假设冲突很少发生          |
| 实现方式    | FOR UPDATE            | WHERE version=?   |
| 性能      | 低（阻塞等待）              | 高（无锁）             |
| 并发能力    | 低                    | 高                 |
| 死锁风险    | 有                    | 无                 |
| 适用场景    | 高冲突（秒杀、转账、支付）        | 低冲突（点赞、浏览量、评论）    |
| 重试逻辑    | 数据库自动阻塞              | 应用层处理             |
| 数据一致性   | 强一致性                 | 最终一致性             |

---

## 如何选择？

### 选择悲观锁的场景

1. **高冲突场景**：秒杀、抢购、抢红包
2. **金融交易**：转账、支付、扣款
3. **库存管理**：库存扣减、座位预订
4. **严格一致性要求**：不允许任何冲突

```sql
-- 典型悲观锁场景
START TRANSACTION;
SELECT stock FROM product WHERE id = 1001 FOR UPDATE; -- 加锁
UPDATE product SET stock = stock - 1 WHERE id = 1001;
COMMIT;
```

### 选择乐观锁的场景

1. **低冲突场景**：点赞、浏览量、评论数
2. **读多写少**：用户信息更新、文章编辑
3. **高并发读取**：缓存失效重建
4. **分布式系统**：避免分布式锁

```sql
-- 典型乐观锁场景
-- 1. 读取数据（不加锁）
SELECT likes, version FROM article WHERE id = 1;

-- 2. 更新数据（检查版本号）
UPDATE article SET likes = likes + 1, version = version + 1
WHERE id = 1 AND version = <old_version>;
```

---

## 实战建议

### 1. 悲观锁优化

```sql
-- ❌ 不好：锁的时间太长
START TRANSACTION;
SELECT * FROM account WHERE id = 1 FOR UPDATE;
-- ... 复杂业务逻辑（10秒）
UPDATE account SET balance = 900 WHERE id = 1;
COMMIT;

-- ✅ 好：缩小锁的范围
-- 先做业务逻辑（不加锁）
-- ... 业务逻辑处理

-- 再开启事务（快速提交）
START TRANSACTION;
SELECT * FROM account WHERE id = 1 FOR UPDATE;
UPDATE account SET balance = 900 WHERE id = 1;
COMMIT;
```

### 2. 乐观锁重试策略

```python
# 指数退避重试
def update_with_retry(product_id, max_retries=3):
    for i in range(max_retries):
        # 尝试更新
        success = update_product(product_id)
        if success:
            return True

        # 失败后，指数退避
        wait_time = 0.01 * (2 ** i)  # 10ms, 20ms, 40ms
        time.sleep(wait_time)

    return False
```

### 3. 混合使用

```sql
-- 场景：秒杀商品，先用乐观锁快速扣减，库存不足时切换到悲观锁

-- 第一阶段：乐观锁（快速扣减）
UPDATE product SET stock = stock - 1, version = version + 1
WHERE id = 1001 AND stock > 0 AND version = <old_version>;

-- 如果失败，切换到悲观锁
START TRANSACTION;
SELECT stock FROM product WHERE id = 1001 FOR UPDATE;
IF stock > 0 THEN
    UPDATE product SET stock = stock - 1 WHERE id = 1001;
    COMMIT;
ELSE
    ROLLBACK;
END IF;
```

---

## 常见面试题

**Q1: 乐观锁和悲观锁的本质区别？**
- 悲观锁：真正的数据库锁，阻塞其他事务
- 乐观锁：应用层实现，通过版本号检测冲突

**Q2: 为什么乐观锁性能更好？**
- 无锁，不阻塞，并发读写性能高

**Q3: 乐观锁在高并发下的问题？**
- 冲突频繁时，重试次数多，性能下降
- 可能导致"活锁"（一直重试失败）

**Q4: 如何避免乐观锁的"活锁"？**
- 设置最大重试次数
- 使用指数退避策略
- 高冲突场景改用悲观锁

**Q5: 版本号会溢出吗？**
- INT最大值21亿，正常业务不会溢出
- 如果担心，使用BIGINT（最大值9223372036854775807）

---

## 小结

✅ **悲观锁**：先加锁，适合高冲突场景（秒杀、转账）
✅ **乐观锁**：不加锁，适合低冲突场景（点赞、浏览量）
✅ **选择策略**：根据冲突频率和一致性要求选择
✅ **混合使用**：先乐观锁，失败后切换到悲观锁

理解两种锁的适用场景，是高并发系统设计的基础。

---

📚 **相关阅读**：
- 下一篇：《事务实战：转账案例与并发控制》
- 推荐：《死锁：产生原因与解决方案》
