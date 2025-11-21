---
title: "InnoDB行锁：Record Lock、Gap Lock、Next-Key Lock"
date: 2025-01-14T15:00:00+08:00
draft: false
tags: ["MySQL", "InnoDB", "行锁", "Next-Key Lock"]
categories: ["数据库"]
description: "深入理解InnoDB的三种行锁：记录锁、间隙锁、Next-Key Lock，掌握锁范围计算和幻读防止机制"
series: ["MySQL从入门到精通"]
weight: 41
stage: 4
stageTitle: "事务与锁篇"
---

## InnoDB行锁分类

```
InnoDB行锁
├─ Record Lock（记录锁）：锁住单行记录
├─ Gap Lock（间隙锁）：锁住记录间的间隙
└─ Next-Key Lock（临键锁）：Record Lock + Gap Lock
```

**适用场景**：
- REPEATABLE READ隔离级别（默认）
- SERIALIZABLE隔离级别

---

## 1. Record Lock（记录锁）

### 定义

**锁住索引记录**，不锁间隙。

### 加锁条件

**唯一索引等值查询**（命中记录）：

```sql
-- 建表
CREATE TABLE account (
    id INT PRIMARY KEY,
    name VARCHAR(50),
    balance INT,
    KEY idx_balance (balance)
);

INSERT INTO account VALUES
(1, 'A', 1000),
(5, 'B', 1500),
(10, 'C', 2000),
(15, 'D', 2500);

-- 加记录锁
START TRANSACTION;
SELECT * FROM account WHERE id = 5 FOR UPDATE;
-- 只锁id=5这一行（Record Lock）

-- 其他事务
UPDATE account SET balance = 900 WHERE id = 5;  -- ❌ 阻塞（锁冲突）
UPDATE account SET balance = 900 WHERE id = 10; -- ✅ 不阻塞（不同行）
INSERT INTO account VALUES (7, 'E', 800);       -- ✅ 不阻塞（无间隙锁）
```

### 锁范围示意

```
id索引：   1 ─── 5 ─── 10 ─── 15
           │      ▼      │      │
           │    [锁定]    │      │
           │      │      │      │
           └─────┴─────┴─────┘
                不锁间隙
```

---

## 2. Gap Lock（间隙锁）

### 定义

**锁住两个索引记录之间的间隙**，防止其他事务在间隙中插入数据。

### 加锁条件

**非唯一索引范围查询**，或**唯一索引未命中**：

```sql
-- 场景1：范围查询（非唯一索引）
START TRANSACTION;
SELECT * FROM account WHERE balance > 1500 FOR UPDATE;
-- 锁住间隙：(1500, 2000)、(2000, 2500)、(2500, +∞)

-- 其他事务
INSERT INTO account VALUES (12, 'F', 1800); -- ❌ 阻塞（在间隙中）
INSERT INTO account VALUES (20, 'G', 3000); -- ❌ 阻塞（在间隙中）
UPDATE account SET balance = 900 WHERE id = 5; -- ✅ 不阻塞（不在锁范围）
```

### 锁范围示意

```
balance索引： 1000 ─── 1500 ─── 2000 ─── 2500
                       │       ▼       ▼       ▼
                       │    (锁间隙) (锁间隙) (锁间隙)
                       │       │       │       │
                       └───────┴───────┴───────┘
                           防止插入
```

### 间隙锁的特点

1. **只在REPEATABLE READ级别存在**（READ COMMITTED无间隙锁）
2. **只阻塞INSERT**，不阻塞UPDATE/DELETE（除非命中记录锁）
3. **间隙锁之间不冲突**（多个事务可以同时持有同一间隙的锁）

```sql
-- 间隙锁不冲突
-- 事务A
START TRANSACTION;
SELECT * FROM account WHERE balance > 1500 FOR UPDATE;

-- 事务B（不阻塞）
START TRANSACTION;
SELECT * FROM account WHERE balance > 1500 FOR UPDATE; -- ✅ 不阻塞

-- 但INSERT会阻塞
INSERT INTO account VALUES (12, 'F', 1800); -- ❌ 阻塞
```

---

## 3. Next-Key Lock（临键锁）

### 定义

**Record Lock + Gap Lock**，锁住记录和前面的间隙。

**默认锁**：InnoDB在REPEATABLE READ级别默认使用Next-Key Lock。

### 加锁条件

**普通索引范围查询**：

```sql
-- 建表（非唯一索引）
CREATE TABLE account (
    id INT PRIMARY KEY,
    balance INT,
    KEY idx_balance (balance)
);

INSERT INTO account VALUES
(1, 1000),
(5, 1500),
(10, 2000),
(15, 2500);

-- 加Next-Key Lock
START TRANSACTION;
SELECT * FROM account WHERE balance >= 1500 AND balance <= 2000 FOR UPDATE;

-- 锁定范围（左开右闭）：
-- (1000, 1500]（Next-Key Lock）
-- (1500, 2000]（Next-Key Lock）
-- (2000, 2500)（Gap Lock）

-- 其他事务
UPDATE account SET balance = 1500 WHERE id = 5;  -- ❌ 阻塞（Record Lock）
UPDATE account SET balance = 2000 WHERE id = 10; -- ❌ 阻塞（Record Lock）
INSERT INTO account VALUES (7, 1800);            -- ❌ 阻塞（Gap Lock）
INSERT INTO account VALUES (12, 2200);           -- ❌ 阻塞（Gap Lock）
UPDATE account SET balance = 900 WHERE id = 1;   -- ✅ 不阻塞（不在锁范围）
```

### 锁范围计算规则

**原则**：左开右闭区间，即 **(左边界, 右边界]**

```sql
-- 当前索引值：1000, 1500, 2000, 2500

-- 查询1：WHERE balance = 1500
-- 锁定：(1000, 1500]（Next-Key Lock）
--      (1500, 2000)（Gap Lock，可能优化掉）

-- 查询2：WHERE balance > 1500
-- 锁定：(1500, 2000]（Next-Key Lock）
--      (2000, 2500]（Next-Key Lock）
--      (2500, +∞)（Gap Lock）

-- 查询3：WHERE balance >= 1500 AND balance < 2500
-- 锁定：(1000, 1500]（Next-Key Lock）
--      (1500, 2000]（Next-Key Lock）
--      (2000, 2500)（Gap Lock）
```

### 锁范围示意

```
balance索引： 1000 ────── 1500 ────── 2000 ────── 2500
               │    ▼     │     ▼     │     ▼     │
               │  (间隙锁) [记录锁]  (间隙锁) [记录锁]  (间隙锁) │
               │    │     │     │     │     │     │
               └────┴─────┴─────┴─────┴─────┴─────┘
                       Next-Key Lock = 记录锁 + 前面的间隙锁
```

---

## 锁升级与优化

### 1. 唯一索引等值查询优化

**如果查询命中记录，Next-Key Lock退化为Record Lock**：

```sql
-- 唯一索引等值查询（命中）
SELECT * FROM account WHERE id = 5 FOR UPDATE;
-- 锁定：仅锁id=5这一行（Record Lock）
-- 不锁间隙

-- 唯一索引等值查询（未命中）
SELECT * FROM account WHERE id = 7 FOR UPDATE;
-- 锁定：(5, 10)（Gap Lock）
```

### 2. 主键范围查询优化

**主键范围查询的最后一个间隙可能优化掉**：

```sql
-- 主键范围查询
SELECT * FROM account WHERE id >= 5 AND id < 10 FOR UPDATE;
-- 锁定：[5, 5]（Record Lock）
--      (5, 10)（Gap Lock）
-- 不锁[10, 10]（优化）
```

### 3. 非唯一索引 + 主键回表

**非唯一索引加Next-Key Lock，主键加Record Lock**：

```sql
-- balance是非唯一索引
SELECT * FROM account WHERE balance = 1500 FOR UPDATE;

-- 锁定（balance索引）：
-- (1000, 1500]（Next-Key Lock）
-- (1500, 2000)（Gap Lock）

-- 锁定（主键索引）：
-- [5, 5]（Record Lock，balance=1500对应id=5）
```

---

## 防止幻读的原理

### 快照读（无幻读）

```sql
-- 事务A
START TRANSACTION;
SELECT * FROM account WHERE balance > 1500; -- 快照读，返回3行

-- 事务B
INSERT INTO account VALUES (12, 1800); -- 插入新行
COMMIT;

-- 事务A
SELECT * FROM account WHERE balance > 1500; -- 仍然返回3行（MVCC快照）
COMMIT;
```

**原理**：MVCC读取快照版本，看不到新插入的行。

### 当前读（Next-Key Lock防幻读）

```sql
-- 事务A
START TRANSACTION;
SELECT * FROM account WHERE balance > 1500 FOR UPDATE; -- 当前读
-- 加Next-Key Lock，锁住间隙

-- 事务B
INSERT INTO account VALUES (12, 1800); -- ❌ 阻塞（间隙锁）

-- 事务A
SELECT * FROM account WHERE balance > 1500 FOR UPDATE; -- 仍然3行（间隙锁防止插入）
COMMIT;
```

**原理**：Next-Key Lock锁住间隙，阻止其他事务插入。

---

## 实战案例

### 案例1：防止重复下单

```sql
-- 需求：同一用户同一商品只能有1个未支付订单

-- ❌ 错误做法（快照读，可能幻读）
START TRANSACTION;
SELECT COUNT(*) FROM orders
WHERE user_id = 'A' AND product_id = 1001 AND status = 'UNPAID';
-- 返回0

-- 其他事务可能插入新订单

INSERT INTO orders (user_id, product_id, status) VALUES ('A', 1001, 'UNPAID');
COMMIT;
-- 结果：可能重复下单

-- ✅ 正确做法（当前读 + Next-Key Lock）
START TRANSACTION;
SELECT COUNT(*) FROM orders
WHERE user_id = 'A' AND product_id = 1001 AND status = 'UNPAID'
FOR UPDATE; -- 当前读，加Next-Key Lock
-- 返回0，且锁住间隙

-- 其他事务的INSERT会阻塞

INSERT INTO orders (user_id, product_id, status) VALUES ('A', 1001, 'UNPAID');
COMMIT;
-- 结果：不会重复下单
```

### 案例2：库存扣减

```sql
-- 需求：扣减库存，防止超卖

-- ❌ 错误做法（快照读）
START TRANSACTION;
SELECT stock FROM product WHERE id = 1001; -- 快照读，stock=10

-- 其他事务可能并发扣减

UPDATE product SET stock = stock - 5 WHERE id = 1001;
COMMIT;
-- 结果：可能超卖

-- ✅ 正确做法（当前读 + 行锁）
START TRANSACTION;
SELECT stock FROM product WHERE id = 1001 FOR UPDATE; -- 当前读，加行锁
-- stock=10，且锁住该行

-- 其他事务的UPDATE会阻塞

UPDATE product SET stock = stock - 5 WHERE id = 1001;
COMMIT;
-- 结果：不会超卖
```

### 案例3：唯一约束替代锁

```sql
-- 需求：防止重复下单

-- 方案1：锁（复杂）
SELECT ... FOR UPDATE;
INSERT ...;

-- 方案2：唯一索引（简单，推荐）
CREATE UNIQUE INDEX uk_user_product_unpaid
ON orders(user_id, product_id, status)
WHERE status = 'UNPAID';

-- 插入时自动检测冲突
INSERT INTO orders (user_id, product_id, status) VALUES ('A', 1001, 'UNPAID');
-- 如果已存在，抛出唯一约束冲突错误
```

---

## 实战建议

### 1. 优先使用唯一索引

```sql
-- ✅ 唯一索引等值查询（Record Lock）
SELECT * FROM account WHERE id = 5 FOR UPDATE; -- 只锁1行

-- ❌ 非唯一索引范围查询（Next-Key Lock）
SELECT * FROM account WHERE balance > 1500 FOR UPDATE; -- 锁多行+间隙
```

### 2. 避免全表扫描

```sql
-- ❌ 无索引，锁全表
UPDATE account SET balance = 900 WHERE name = 'A'; -- name无索引

-- ✅ 有索引，行锁
UPDATE account SET balance = 900 WHERE id = 1; -- id是主键
```

### 3. 降低隔离级别避免间隙锁

```sql
-- REPEATABLE READ：有间隙锁
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- READ COMMITTED：无间隙锁（可能幻读）
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
```

### 4. 使用应用层唯一约束

```sql
-- 数据库层面保证唯一
CREATE UNIQUE INDEX uk_user_product ON orders(user_id, product_id);

-- 无需使用FOR UPDATE
INSERT INTO orders (user_id, product_id) VALUES ('A', 1001);
-- 自动检测冲突
```

---

## 常见面试题

**Q1: Record Lock、Gap Lock、Next-Key Lock的区别？**
- Record Lock：锁单行记录
- Gap Lock：锁记录间的间隙，防止插入
- Next-Key Lock：Record Lock + Gap Lock

**Q2: 为什么需要Next-Key Lock？**
- 防止幻读（REPEATABLE READ级别）
- 其他事务无法在间隙中插入数据

**Q3: 如何避免间隙锁？**
- 降低隔离级别到READ COMMITTED
- 使用唯一索引等值查询
- 使用应用层唯一约束

**Q4: 间隙锁会不会冲突？**
- 间隙锁之间不冲突（多个事务可以同时持有）
- 间隙锁只阻塞INSERT

---

## 小结

✅ **Record Lock**：锁单行，唯一索引等值查询
✅ **Gap Lock**：锁间隙，防止INSERT，防止幻读
✅ **Next-Key Lock**：记录锁+间隙锁，InnoDB默认
✅ **锁范围**：左开右闭区间 **(左, 右]**

理解InnoDB行锁机制是编写高并发应用的关键。

---

📚 **相关阅读**：
- 下一篇：《死锁：产生原因与解决方案》
- 推荐：《MVCC多版本并发控制：原理与实现》
