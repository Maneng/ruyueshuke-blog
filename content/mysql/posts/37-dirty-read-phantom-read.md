---
title: "脏读、不可重复读、幻读问题解析"
date: 2025-01-14T11:00:00+08:00
draft: false
tags: ["MySQL", "事务", "并发问题", "脏读", "幻读"]
categories: ["数据库"]
description: "深入理解数据库并发的三大经典问题：脏读、不可重复读、幻读，掌握问题场景、产生原因和解决方案"
series: ["MySQL从入门到精通"]
weight: 37
stage: 4
stageTitle: "事务与锁篇"
---

## 三大并发问题概述

| 问题      | 定义                | 影响范围  | 解决隔离级别           |
|---------|-------------------|-------|------------------|
| 脏读      | 读到未提交的数据          | 单行数据  | READ COMMITTED   |
| 不可重复读   | 同一查询两次结果不同（UPDATE） | 单行数据  | REPEATABLE READ  |
| 幻读      | 范围查询两次结果不同（INSERT） | 多行数据  | SERIALIZABLE     |

---

## 1. 脏读（Dirty Read）

### 定义
**读取到其他事务未提交的数据**，如果该事务回滚，就会读到"脏"数据。

### 场景演示

```sql
-- 设置为最低隔离级别
SET SESSION TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

-- 时间线：事务A和事务B并发执行
┌─────────────────┬─────────────────────────────────┐
│ 事务A             │ 事务B                            │
├─────────────────┼─────────────────────────────────┤
│ START TRANSACTION│                                 │
│                 │ START TRANSACTION                │
│ SELECT balance  │                                 │
│ FROM account    │                                 │
│ WHERE id=1;     │                                 │
│ -- 读到1000      │                                 │
│                 │ UPDATE account                   │
│                 │ SET balance=500                  │
│                 │ WHERE id=1;                      │
│                 │ -- 未提交                         │
│ SELECT balance  │                                 │
│ FROM account    │                                 │
│ WHERE id=1;     │                                 │
│ -- 读到500（脏读）│                                 │
│                 │ ROLLBACK;                        │
│                 │ -- 余额回滚到1000                  │
│ -- 但事务A已经基于 │                                 │
│ -- 500做决策，错误！│                                 │
│ COMMIT;         │                                 │
└─────────────────┴─────────────────────────────────┘
```

### 真实案例

```sql
-- 场景：电商库存扣减
-- 事务A：查询库存并下单
START TRANSACTION;
SELECT stock FROM product WHERE id = 1001; -- 读到库存50

-- 事务B：库存更正（发现统计错误）
START TRANSACTION;
UPDATE product SET stock = 10 WHERE id = 1001; -- 实际只有10件
-- 未提交

-- 事务A继续
-- 基于库存50的判断，允许用户下单40件
INSERT INTO orders (product_id, quantity) VALUES (1001, 40);
COMMIT;

-- 事务B回滚
ROLLBACK; -- 库存恢复到50

-- 结果：用户下单40件，但实际库存只有10件，超卖！
```

### 解决方案

**提高隔离级别到READ COMMITTED或更高**：

```sql
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- 事务A
START TRANSACTION;
SELECT stock FROM product WHERE id = 1001; -- 只能读到已提交的数据
-- 如果事务B未提交，读到的是修改前的值（50）
-- 如果事务B已提交，读到的是修改后的值（10）
COMMIT;
```

---

## 2. 不可重复读（Non-Repeatable Read）

### 定义
**同一事务内，两次读取同一行数据，结果不同**（其他事务修改并提交了数据）。

### 场景演示

```sql
-- 设置隔离级别
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- 时间线
┌─────────────────┬─────────────────────────────────┐
│ 事务A             │ 事务B                            │
├─────────────────┼─────────────────────────────────┤
│ START TRANSACTION│                                 │
│ SELECT balance  │                                 │
│ FROM account    │                                 │
│ WHERE id=1;     │                                 │
│ -- 第一次读：1000 │                                 │
│                 │ START TRANSACTION                │
│                 │ UPDATE account                   │
│                 │ SET balance=500                  │
│                 │ WHERE id=1;                      │
│                 │ COMMIT; -- 提交                   │
│ SELECT balance  │                                 │
│ FROM account    │                                 │
│ WHERE id=1;     │                                 │
│ -- 第二次读：500  │                                 │
│ -- 不可重复读！   │                                 │
│ COMMIT;         │                                 │
└─────────────────┴─────────────────────────────────┘
```

### 真实案例

```sql
-- 场景：统计报表生成
-- 事务A：生成财务报表（需要多次查询同一数据）
START TRANSACTION;

-- 第一步：查询账户余额
SELECT SUM(balance) FROM account; -- 总额：100万

-- 第二步：计算其他指标（耗时操作）
SELECT AVG(balance), MAX(balance) FROM account;

-- 事务B：财务调整（并发执行）
START TRANSACTION;
UPDATE account SET balance = balance * 1.05; -- 所有账户增加5%利息
COMMIT;

-- 事务A：第三步，再次查询余额用于核对
SELECT SUM(balance) FROM account; -- 总额：105万（不可重复读！）
-- 报表数据不一致，第一步和第三步的总额不同

COMMIT;
```

### 解决方案

**提高隔离级别到REPEATABLE READ**：

```sql
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- 事务A
START TRANSACTION;
SELECT balance FROM account WHERE id = 1; -- 第一次读：1000

-- 即使事务B修改并提交，事务A仍读到快照版本
SELECT balance FROM account WHERE id = 1; -- 第二次读：仍然1000
COMMIT;
```

**原理**：**MVCC（多版本并发控制）**
- 每行数据有多个版本
- 事务读取的是事务开始时的快照版本

---

## 3. 幻读（Phantom Read）

### 定义
**同一事务内，两次范围查询，返回的记录数不同**（其他事务插入或删除了数据）。

### 与不可重复读的区别

| 问题     | 影响范围  | 操作类型        | 示例                        |
|--------|-------|-------------|---------------------------|
| 不可重复读  | 单行数据  | UPDATE      | 查询id=1的余额，两次结果不同         |
| 幻读     | 多行数据  | INSERT/DELETE | 查询balance>500的记录，两次结果行数不同 |

### 场景演示

```sql
-- 设置隔离级别
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- 时间线
┌──────────────────┬─────────────────────────────────┐
│ 事务A              │ 事务B                            │
├──────────────────┼─────────────────────────────────┤
│ START TRANSACTION │                                 │
│ SELECT * FROM    │                                 │
│ account          │                                 │
│ WHERE balance>500│                                 │
│ -- 第一次：3行     │                                 │
│                  │ START TRANSACTION                │
│                  │ INSERT INTO account              │
│                  │ VALUES (4,'D',600);              │
│                  │ COMMIT;                          │
│ SELECT * FROM    │                                 │
│ account          │                                 │
│ WHERE balance>500│                                 │
│ -- 快照读：仍然3行  │                                 │
│                  │                                 │
│ UPDATE account   │                                 │
│ SET balance=     │                                 │
│ balance+10       │                                 │
│ WHERE balance>500│                                 │
│ -- 当前读：影响4行！│                                 │
│ -- 幻读！         │                                 │
│ COMMIT;          │                                 │
└──────────────────┴─────────────────────────────────┘
```

### 快照读 vs 当前读

**快照读（Snapshot Read）**：
- 普通SELECT语句
- 读取MVCC快照版本，**不加锁**
- **不会出现幻读**

```sql
SELECT * FROM account WHERE balance > 500;
-- 读取事务开始时的快照，新插入的行不可见
```

**当前读（Current Read）**：
- SELECT FOR UPDATE、SELECT LOCK IN SHARE MODE
- UPDATE、DELETE、INSERT
- 读取最新版本，**加锁**
- **可能出现幻读**

```sql
-- 当前读（会读到新插入的行）
SELECT * FROM account WHERE balance > 500 FOR UPDATE;
UPDATE account SET balance = balance + 10 WHERE balance > 500;
```

### 真实案例

```sql
-- 场景：防止重复下单
-- 业务逻辑：同一用户同一商品只能有1个未支付订单

-- 事务A：用户A下单商品1001
START TRANSACTION;

-- 第一步：检查是否有未支付订单（快照读）
SELECT COUNT(*) FROM orders
WHERE user_id = 'A' AND product_id = 1001 AND status = 'UNPAID';
-- 返回0，判断可以下单

-- 事务B：用户A在另一个设备上也下单（并发）
START TRANSACTION;
SELECT COUNT(*) FROM orders
WHERE user_id = 'A' AND product_id = 1001 AND status = 'UNPAID';
-- 也返回0，判断可以下单
INSERT INTO orders (user_id, product_id, status) VALUES ('A', 1001, 'UNPAID');
COMMIT; -- 提交

-- 事务A继续
-- 第二步：插入订单（当前读，会看到事务B插入的记录）
INSERT INTO orders (user_id, product_id, status) VALUES ('A', 1001, 'UNPAID');
COMMIT;

-- 结果：用户A有2个未支付订单，违反业务规则（幻读导致）
```

### 解决方案

#### 方案1：使用当前读 + 行锁

```sql
START TRANSACTION;

-- 使用FOR UPDATE加锁（当前读）
SELECT COUNT(*) FROM orders
WHERE user_id = 'A' AND product_id = 1001 AND status = 'UNPAID'
FOR UPDATE;
-- 如果返回0，可以插入

INSERT INTO orders (user_id, product_id, status) VALUES ('A', 1001, 'UNPAID');
COMMIT;
```

#### 方案2：提高隔离级别到SERIALIZABLE

```sql
SET SESSION TRANSACTION ISOLATION LEVEL SERIALIZABLE;

-- SELECT自动加锁，阻塞其他事务的INSERT
START TRANSACTION;
SELECT COUNT(*) FROM orders
WHERE user_id = 'A' AND product_id = 1001 AND status = 'UNPAID';
-- 其他事务的INSERT会被阻塞
COMMIT;
```

#### 方案3：应用层唯一约束

```sql
-- 创建唯一索引（推荐）
CREATE UNIQUE INDEX uk_user_product_unpaid
ON orders(user_id, product_id, status)
WHERE status = 'UNPAID';

-- 插入时自动检测冲突
INSERT INTO orders (user_id, product_id, status) VALUES ('A', 1001, 'UNPAID');
-- 如果已有未支付订单，抛出唯一约束冲突错误
```

---

## MySQL的特殊处理

### Next-Key Lock机制

**MySQL在REPEATABLE READ级别使用Next-Key Lock，部分解决幻读**：

```sql
-- 事务A
START TRANSACTION;
SELECT * FROM account WHERE id BETWEEN 1 AND 10 FOR UPDATE;
-- 加Next-Key Lock：锁住id=1~10的行，以及(10, +∞)的间隙

-- 事务B（并发执行）
INSERT INTO account (id, name, balance) VALUES (5, 'E', 500);
-- 阻塞！无法插入id=5的行

INSERT INTO account (id, name, balance) VALUES (15, 'F', 600);
-- 阻塞！无法插入id=15的行（间隙锁）
```

**Next-Key Lock = Record Lock（行锁） + Gap Lock（间隙锁）**

---

## 问题对比总结

| 特性      | 脏读            | 不可重复读          | 幻读              |
|---------|---------------|----------------|-----------------|
| 读到的数据   | 未提交的数据        | 已提交的修改         | 已提交的新增/删除       |
| 影响范围    | 单行            | 单行             | 多行（范围查询）        |
| 操作类型    | UPDATE/INSERT | UPDATE         | INSERT/DELETE   |
| 最低解决级别  | READ COMMITTED | REPEATABLE READ | SERIALIZABLE    |
| MySQL特殊处理 | -             | MVCC快照读        | Next-Key Lock   |

---

## 实战建议

### 1. 默认使用REPEATABLE READ
```sql
-- 查看当前隔离级别
SELECT @@transaction_isolation; -- 默认REPEATABLE-READ
```

### 2. 关键业务使用当前读
```sql
-- 防止幻读：使用FOR UPDATE
SELECT * FROM orders WHERE user_id = 'A' FOR UPDATE;
INSERT INTO orders VALUES (...);
```

### 3. 应用层加唯一约束
```sql
-- 数据库层面防止重复
CREATE UNIQUE INDEX uk_user_product ON orders(user_id, product_id);
```

### 4. 避免长事务
- 减少锁冲突概率
- 降低幻读风险

---

## 常见面试题

**Q1: 为什么READ COMMITTED不能防止不可重复读？**
- 因为每次SELECT都读取最新的已提交数据，不使用快照

**Q2: MySQL的REPEATABLE READ能完全防止幻读吗？**
- 快照读：能防止（MVCC）
- 当前读：能防止（Next-Key Lock）
- 但先快照读后当前读，可能出现幻读

**Q3: 如何选择使用快照读还是当前读？**
- 只读操作：快照读（性能好）
- 需要修改数据：当前读（FOR UPDATE）
- 防止幻读：当前读 + Next-Key Lock

---

## 小结

✅ **脏读**：读到未提交数据，READ COMMITTED解决
✅ **不可重复读**：同一查询两次结果不同，REPEATABLE READ解决
✅ **幻读**：范围查询两次行数不同，SERIALIZABLE或Next-Key Lock解决

**推荐**：默认REPEATABLE READ + 关键业务使用FOR UPDATE。

---

📚 **相关阅读**：
- 下一篇：《MVCC多版本并发控制：原理与实现》
- 推荐：《InnoDB行锁：Record Lock、Gap Lock、Next-Key Lock》
