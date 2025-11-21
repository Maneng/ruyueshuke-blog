---
title: "事务的隔离级别：Read Uncommitted、Read Committed、Repeatable Read、Serializable"
date: 2025-01-14T10:00:00+08:00
draft: false
tags: ["MySQL", "事务", "隔离级别", "并发控制"]
categories: ["数据库"]
description: "详解MySQL的四种事务隔离级别，理解脏读、不可重复读、幻读问题，掌握隔离级别的选择策略"
series: ["MySQL从入门到精通"]
weight: 36
stage: 4
stageTitle: "事务与锁篇"
---

## 为什么需要隔离级别？

**并发事务**可能产生三大问题：
1. **脏读（Dirty Read）**：读到未提交的数据
2. **不可重复读（Non-Repeatable Read）**：同一查询两次结果不同
3. **幻读（Phantom Read）**：范围查询两次结果不同

**隔离级别**就是用来控制**在多大程度上解决这些问题**。

## 四种隔离级别

### 级别对比表

| 隔离级别                       | 脏读   | 不可重复读 | 幻读   | 性能   | 应用场景            |
|----------------------------|------|-------|------|------|-----------------|
| READ UNCOMMITTED（读未提交）     | ❌ 会  | ❌ 会  | ❌ 会 | ⭐⭐⭐⭐ | 几乎不用            |
| READ COMMITTED（读已提交）       | ✅ 避免 | ❌ 会  | ❌ 会 | ⭐⭐⭐  | Oracle/PostgreSQL默认 |
| REPEATABLE READ（可重复读）      | ✅ 避免 | ✅ 避免 | ⚠️ 部分避免 | ⭐⭐   | MySQL默认（推荐）     |
| SERIALIZABLE（串行化）          | ✅ 避免 | ✅ 避免 | ✅ 避免 | ⭐    | 严格一致性要求         |

---

## 1. READ UNCOMMITTED（读未提交）

**特点**：事务可以读取其他事务**未提交**的数据（脏读）。

### 演示：脏读问题

```sql
-- 设置隔离级别
SET SESSION TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

-- 事务A
START TRANSACTION;
SELECT balance FROM account WHERE user_id = 'A'; -- 读到1000

-- 事务B（并发执行）
START TRANSACTION;
UPDATE account SET balance = 500 WHERE user_id = 'A'; -- 未提交
-- 此时事务A再次查询

-- 事务A
SELECT balance FROM account WHERE user_id = 'A'; -- 读到500（脏读！）
COMMIT;

-- 事务B
ROLLBACK; -- 回滚，余额恢复到1000
```

**问题**：事务A读到了事务B未提交的数据（500），但事务B最终回滚了，导致数据不一致。

**应用场景**：几乎不使用（风险太大）

---

## 2. READ COMMITTED（读已提交）

**特点**：只能读取**已提交**的数据，避免脏读，但可能不可重复读。

### 演示：不可重复读问题

```sql
-- 设置隔离级别
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- 事务A
START TRANSACTION;
SELECT balance FROM account WHERE user_id = 'A'; -- 第一次读：1000

-- 事务B（并发执行）
START TRANSACTION;
UPDATE account SET balance = 500 WHERE user_id = 'A';
COMMIT; -- 提交

-- 事务A
SELECT balance FROM account WHERE user_id = 'A'; -- 第二次读：500（不可重复读！）
COMMIT;
```

**问题**：事务A两次读取同一行数据，结果不同（因为事务B修改并提交了）。

**应用场景**：
- Oracle、PostgreSQL、SQL Server的默认隔离级别
- 适用于对一致性要求不高的场景（如统计报表）

---

## 3. REPEATABLE READ（可重复读）

**特点**：保证在同一事务内多次读取同一行数据结果一致，**MySQL的默认隔离级别**。

### 演示：解决不可重复读

```sql
-- 设置隔离级别（MySQL默认）
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- 事务A
START TRANSACTION;
SELECT balance FROM account WHERE user_id = 'A'; -- 第一次读：1000

-- 事务B（并发执行）
START TRANSACTION;
UPDATE account SET balance = 500 WHERE user_id = 'A';
COMMIT; -- 提交

-- 事务A
SELECT balance FROM account WHERE user_id = 'A'; -- 第二次读：仍然1000（可重复读）
COMMIT;
```

**实现原理**：**MVCC（多版本并发控制）**
- 每行数据有多个版本
- 事务A读取的是事务开始时的快照版本

### 幻读问题（部分避免）

```sql
-- 事务A
START TRANSACTION;
SELECT * FROM account WHERE balance > 500; -- 第一次读：返回3行

-- 事务B（并发执行）
START TRANSACTION;
INSERT INTO account VALUES (4, 'D', 600); -- 插入新行
COMMIT;

-- 事务A
SELECT * FROM account WHERE balance > 500; -- 第二次读：仍然3行（MVCC快照读）
UPDATE account SET balance = balance + 10 WHERE balance > 500; -- 当前读：影响4行（幻读！）
COMMIT;
```

**MySQL的特殊处理**：
- **快照读**（普通SELECT）：通过MVCC避免幻读
- **当前读**（SELECT FOR UPDATE、UPDATE、DELETE）：通过Next-Key Lock避免幻读

**应用场景**：
- MySQL默认隔离级别
- 适用于大多数OLTP业务场景

---

## 4. SERIALIZABLE（串行化）

**特点**：最高隔离级别，完全串行化执行，避免所有并发问题，但性能最差。

### 演示：完全避免幻读

```sql
-- 设置隔离级别
SET SESSION TRANSACTION ISOLATION LEVEL SERIALIZABLE;

-- 事务A
START TRANSACTION;
SELECT * FROM account WHERE balance > 500; -- 自动加共享锁

-- 事务B（并发执行）
START TRANSACTION;
INSERT INTO account VALUES (4, 'D', 600); -- 阻塞，等待事务A提交
COMMIT;

-- 事务A
COMMIT; -- 事务B才能继续执行
```

**实现原理**：
- **读加共享锁（S锁）**
- **写加排他锁（X锁）**
- 锁范围覆盖整个查询范围（表锁或Next-Key Lock）

**应用场景**：
- 金融系统（对一致性要求极高）
- 批量对账任务
- 一般不推荐（性能太差）

---

## 查看和设置隔离级别

### 查看当前隔离级别

```sql
-- MySQL 5.7.20之前
SELECT @@tx_isolation;

-- MySQL 8.0+
SELECT @@transaction_isolation;

-- 查看全局和会话级别
SHOW VARIABLES LIKE 'transaction_isolation';
```

### 设置隔离级别

```sql
-- 设置会话级别（仅当前连接有效）
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- 设置全局级别（重启后失效）
SET GLOBAL TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- 永久修改（配置文件my.cnf）
[mysqld]
transaction-isolation = REPEATABLE-READ
```

### 为单个事务设置

```sql
-- 仅对下一个事务生效
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
START TRANSACTION;
-- 业务SQL
COMMIT;
```

---

## 隔离级别选择策略

### 1. 默认使用REPEATABLE READ（推荐）
- MySQL默认级别
- 性能和一致性的平衡
- 通过MVCC避免大部分并发问题

### 2. 对一致性要求不高的场景：READ COMMITTED
- 统计报表
- 日志查询
- 临时数据分析

### 3. 极少数场景：SERIALIZABLE
- 金融交易
- 库存扣减（防止超卖）
- 批量对账

### 4. 绝不使用READ UNCOMMITTED
- 会读到脏数据，风险太大

---

## 性能对比

```sql
-- 测试工具：sysbench
-- 场景：100并发，1000万行数据

隔离级别              | TPS      | 延迟(ms) | 锁冲突
--------------------|----------|---------|-------
READ UNCOMMITTED    | 12000    | 8       | 低
READ COMMITTED      | 10000    | 10      | 中
REPEATABLE READ     | 8000     | 12      | 中高
SERIALIZABLE        | 1200     | 83      | 高
```

**结论**：隔离级别越高，性能越差（锁冲突增加）。

---

## 常见面试题

**Q1: 为什么MySQL默认是REPEATABLE READ，而Oracle是READ COMMITTED？**
- MySQL使用MVCC，可以高效实现REPEATABLE READ
- Oracle早期未实现MVCC，READ COMMITTED性能更好

**Q2: REPEATABLE READ能完全避免幻读吗？**
- 快照读（SELECT）：能避免（MVCC）
- 当前读（SELECT FOR UPDATE）：能避免（Next-Key Lock）
- 特殊情况：先SELECT再UPDATE，可能出现幻读

**Q3: 如何选择隔离级别？**
- 默认REPEATABLE READ（适用大多数场景）
- 对一致性要求不高：READ COMMITTED
- 对一致性要求极高：SERIALIZABLE + 应用层校验

---

## 小结

✅ **READ UNCOMMITTED**：会脏读，几乎不用
✅ **READ COMMITTED**：避免脏读，Oracle默认
✅ **REPEATABLE READ**：避免脏读和不可重复读，MySQL默认
✅ **SERIALIZABLE**：完全避免并发问题，性能最差

**推荐**：默认使用REPEATABLE READ，根据业务场景适当调整。

---

📚 **相关阅读**：
- 下一篇：《脏读、不可重复读、幻读问题深度解析》
- 推荐：《MVCC多版本并发控制：原理与实现》
