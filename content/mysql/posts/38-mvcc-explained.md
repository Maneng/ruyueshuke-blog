---
title: "MVCC多版本并发控制：原理与实现"
date: 2025-01-14T12:00:00+08:00
draft: false
tags: ["MySQL", "MVCC", "并发控制", "InnoDB"]
categories: ["数据库"]
description: "深入理解MySQL的MVCC机制，掌握ReadView、undo log、版本链的工作原理，理解快照读和当前读的区别"
series: ["MySQL从入门到精通"]
weight: 38
stage: 4
stageTitle: "事务与锁篇"
---

## 什么是MVCC？

**MVCC（Multi-Version Concurrency Control，多版本并发控制）** 是InnoDB实现高并发的核心机制。

**核心思想**：
- 每行数据有**多个版本**
- **读操作**读取快照版本（不加锁）
- **写操作**创建新版本（加锁）
- **读写不冲突**，提高并发性能

**适用隔离级别**：
- ✅ READ COMMITTED
- ✅ REPEATABLE READ
- ❌ READ UNCOMMITTED（无需MVCC）
- ❌ SERIALIZABLE（完全加锁）

---

## MVCC的实现机制

### 1. 隐藏字段

InnoDB为每行数据添加三个隐藏字段：

| 字段名           | 长度    | 说明                |
|---------------|-------|-------------------|
| **DB_TRX_ID** | 6字节  | 最后修改该行的**事务ID**   |
| **DB_ROLL_PTR** | 7字节  | 回滚指针，指向**undo log** |
| **DB_ROW_ID** | 6字节  | 隐藏主键（无主键时自动生成）    |

```sql
-- 实际存储的行数据（用户不可见）
┌────┬──────┬─────────┬────────────┬─────────────┬────────────┐
│ id │ name │ balance │ DB_TRX_ID  │ DB_ROLL_PTR │ DB_ROW_ID  │
├────┼──────┼─────────┼────────────┼─────────────┼────────────┤
│ 1  │ A    │ 1000    │ 100        │ 0x7FA8...   │ 1          │
└────┴──────┴─────────┴────────────┴─────────────┴────────────┘
```

### 2. undo log版本链

每次修改数据，旧版本保存在**undo log**，形成版本链。

```sql
-- 初始数据
INSERT INTO account (id, name, balance) VALUES (1, 'A', 1000);
-- DB_TRX_ID = 100

-- 事务101：修改余额
UPDATE account SET balance = 900 WHERE id = 1;
-- DB_TRX_ID = 101，旧版本保存到undo log

-- 事务102：再次修改
UPDATE account SET balance = 800 WHERE id = 1;
-- DB_TRX_ID = 102，旧版本保存到undo log
```

**版本链结构**：

```
最新版本（当前数据）
┌────┬──────┬─────────┬────────────┬─────────────┐
│ id │ name │ balance │ DB_TRX_ID  │ DB_ROLL_PTR │
├────┼──────┼─────────┼────────────┼─────────────┤
│ 1  │ A    │ 800     │ 102        │ ───────┐    │
└────┴──────┴─────────┴────────────┴─────────┘    │
                                            │
                                            ▼
                                    undo log v2
                                    ┌─────────┬────────────┬─────────────┐
                                    │ balance │ DB_TRX_ID  │ DB_ROLL_PTR │
                                    ├─────────┼────────────┼─────────────┤
                                    │ 900     │ 101        │ ───────┐    │
                                    └─────────┴────────────┴─────────┘    │
                                                                    │
                                                                    ▼
                                                            undo log v1
                                                            ┌─────────┬────────────┬─────────────┐
                                                            │ balance │ DB_TRX_ID  │ DB_ROLL_PTR │
                                                            ├─────────┼────────────┼─────────────┤
                                                            │ 1000    │ 100        │ NULL        │
                                                            └─────────┴────────────┴─────────────┘
```

### 3. ReadView（读视图）

**ReadView** 是事务开始时生成的"快照"，记录当前活跃事务列表。

**关键字段**：

| 字段            | 说明                |
|---------------|-------------------|
| **m_ids**     | 当前活跃事务ID列表        |
| **min_trx_id** | 最小活跃事务ID          |
| **max_trx_id** | 下一个要分配的事务ID（最大值+1） |
| **creator_trx_id** | 创建ReadView的事务ID   |

**生成时机**：
- **READ COMMITTED**：每次SELECT生成新ReadView
- **REPEATABLE READ**：事务第一次SELECT生成ReadView，之后复用

---

## MVCC的可见性判断

**核心问题**：当前事务能否看到某个版本的数据？

### 可见性规则

```sql
-- 对于版本链中的某个版本，其 DB_TRX_ID = trx_id

IF trx_id == creator_trx_id THEN
    -- 是自己修改的，可见
    RETURN 可见
ELSIF trx_id < min_trx_id THEN
    -- 在ReadView生成前已提交，可见
    RETURN 可见
ELSIF trx_id >= max_trx_id THEN
    -- 在ReadView生成后才开始，不可见
    RETURN 不可见
ELSIF trx_id IN m_ids THEN
    -- 是活跃事务修改的（未提交），不可见
    RETURN 不可见
ELSE
    -- 在ReadView生成前已提交，可见
    RETURN 可见
END IF
```

### 示例演示

```sql
-- 当前系统状态
活跃事务：[50, 60, 70]
min_trx_id = 50
max_trx_id = 80（下一个要分配的事务ID）

-- 事务100查询 id=1 的数据
START TRANSACTION; -- 生成ReadView (creator_trx_id=100)
SELECT * FROM account WHERE id = 1;

-- 版本链：
版本1: balance=1000, DB_TRX_ID=40  -- 40 < 50，可见✅
版本2: balance=900,  DB_TRX_ID=60  -- 60 in [50,60,70]，不可见❌
版本3: balance=800,  DB_TRX_ID=85  -- 85 >= 80，不可见❌

-- 结果：事务100读到balance=1000（版本1）
```

---

## READ COMMITTED vs REPEATABLE READ

### READ COMMITTED（每次生成ReadView）

```sql
-- 事务A
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
START TRANSACTION; -- 事务ID=100

-- 第一次查询，生成ReadView1
SELECT balance FROM account WHERE id = 1;
-- 读到1000（假设当前最新提交版本）

-- 事务B（并发执行）
START TRANSACTION; -- 事务ID=101
UPDATE account SET balance = 900 WHERE id = 1;
COMMIT; -- 提交

-- 事务A第二次查询，生成ReadView2（新的）
SELECT balance FROM account WHERE id = 1;
-- 读到900（事务101已提交，可见）
-- 不可重复读！
```

**特点**：
- 每次SELECT生成新ReadView
- 能读到其他事务已提交的数据
- 会出现**不可重复读**

### REPEATABLE READ（复用ReadView）

```sql
-- 事务A
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
START TRANSACTION; -- 事务ID=100

-- 第一次查询，生成ReadView1
SELECT balance FROM account WHERE id = 1;
-- 读到1000

-- 事务B（并发执行）
START TRANSACTION; -- 事务ID=101
UPDATE account SET balance = 900 WHERE id = 1;
COMMIT; -- 提交

-- 事务A第二次查询，复用ReadView1（不生成新的）
SELECT balance FROM account WHERE id = 1;
-- 仍然读到1000（事务101在ReadView生成后提交，不可见）
-- 可重复读！
```

**特点**：
- 事务第一次SELECT生成ReadView，之后复用
- 读到的是事务开始时的快照
- 避免**不可重复读**

---

## 快照读 vs 当前读

### 快照读（Snapshot Read）

**定义**：读取MVCC快照版本，**不加锁**。

```sql
-- 普通SELECT都是快照读
SELECT * FROM account WHERE id = 1;
SELECT * FROM account WHERE balance > 500;
```

**特点**：
- 不加锁，高并发
- 读取历史版本（通过undo log）
- 不会阻塞其他事务的写操作

### 当前读（Current Read）

**定义**：读取最新版本，**加锁**。

```sql
-- 以下操作都是当前读
SELECT * FROM account WHERE id = 1 FOR UPDATE;           -- 排他锁
SELECT * FROM account WHERE id = 1 LOCK IN SHARE MODE;   -- 共享锁
UPDATE account SET balance = 900 WHERE id = 1;           -- 排他锁
DELETE FROM account WHERE id = 1;                        -- 排他锁
INSERT INTO account VALUES (2, 'B', 500);                -- 排他锁
```

**特点**：
- 加锁（共享锁或排他锁）
- 读取最新提交的数据
- 会阻塞其他事务的写操作

### 对比总结

| 特性      | 快照读          | 当前读              |
|---------|--------------|------------------|
| SQL类型   | 普通SELECT     | SELECT FOR UPDATE等 |
| 是否加锁    | 否            | 是                |
| 读取版本    | 历史快照版本       | 最新版本             |
| 并发性能    | 高（读写不冲突）     | 低（读写互斥）          |
| 使用场景    | 统计报表、数据查询    | 防止幻读、更新前查询       |

---

## MVCC的优势

### 1. 提高并发性能

```sql
-- 传统锁机制（SERIALIZABLE）
事务A: SELECT * FROM account WHERE id = 1; -- 加共享锁
事务B: UPDATE account SET balance = 900 WHERE id = 1; -- 阻塞，等待A释放锁

-- MVCC机制（REPEATABLE READ）
事务A: SELECT * FROM account WHERE id = 1; -- 快照读，不加锁
事务B: UPDATE account SET balance = 900 WHERE id = 1; -- 不阻塞，可以并发执行
```

### 2. 避免读写冲突

```
传统锁机制：
读操作 ⇄ 写操作（互斥，阻塞）

MVCC机制：
读操作 ➜ 快照版本（不加锁）
写操作 ➜ 最新版本（加锁）
读写不冲突！
```

### 3. 性能对比

| 隔离级别           | 机制       | TPS  | 并发能力 |
|----------------|----------|------|------|
| SERIALIZABLE   | 完全加锁     | 1200 | ⭐    |
| REPEATABLE READ | MVCC     | 8000 | ⭐⭐⭐  |
| READ COMMITTED | MVCC（弱） | 10000 | ⭐⭐⭐⭐ |

---

## MVCC的局限性

### 1. 不能完全避免幻读

```sql
-- MVCC只解决快照读的幻读
START TRANSACTION;
SELECT * FROM account WHERE balance > 500; -- 快照读，3行

-- 其他事务插入新行并提交
INSERT INTO account VALUES (4, 'D', 600);

SELECT * FROM account WHERE balance > 500; -- 快照读，仍然3行（无幻读）

-- 但如果使用当前读
UPDATE account SET balance = balance + 10 WHERE balance > 500; -- 影响4行（幻读！）
```

**解决方案**：使用**Next-Key Lock**（当前读自动加锁）

### 2. undo log膨胀

```sql
-- 长事务导致undo log无法清理
START TRANSACTION;
SELECT * FROM account WHERE id = 1; -- 生成ReadView

-- ... 长时间未提交（如1小时）

-- 其他事务的undo log无法清理（因为事务A可能还要读取历史版本）
-- 导致磁盘空间占用增加
```

**解决方案**：避免长事务，及时COMMIT或ROLLBACK。

---

## 实战建议

### 1. 默认使用快照读

```sql
-- 大部分查询使用快照读
SELECT * FROM account WHERE id = 1; -- 不加锁，高性能
```

### 2. 防止幻读使用当前读

```sql
-- 防止重复下单
START TRANSACTION;
SELECT COUNT(*) FROM orders
WHERE user_id = 'A' AND status = 'UNPAID'
FOR UPDATE; -- 当前读，加Next-Key Lock

-- 如果返回0，可以插入
INSERT INTO orders VALUES (...);
COMMIT;
```

### 3. 避免长事务

```sql
-- 查看长事务
SELECT * FROM information_schema.INNODB_TRX
WHERE TIME_TO_SEC(TIMEDIFF(NOW(), trx_started)) > 60;

-- 及时提交
START TRANSACTION;
-- 业务SQL
COMMIT; -- 尽快提交
```

### 4. 监控undo log空间

```sql
-- 查看undo表空间大小
SELECT file_name, tablespace_name,
       ROUND(file_size/1024/1024, 2) AS size_mb
FROM information_schema.FILES
WHERE tablespace_name LIKE '%undo%';
```

---

## 常见面试题

**Q1: MVCC是如何实现的？**
- 隐藏字段（DB_TRX_ID、DB_ROLL_PTR）
- undo log版本链
- ReadView可见性判断

**Q2: READ COMMITTED和REPEATABLE READ的MVCC区别？**
- READ COMMITTED：每次SELECT生成新ReadView
- REPEATABLE READ：第一次SELECT生成ReadView，之后复用

**Q3: MVCC能完全避免幻读吗？**
- 快照读：能避免（读历史版本）
- 当前读：部分避免（Next-Key Lock）

**Q4: 为什么MVCC能提高并发性能？**
- 读写不冲突（读快照，写最新）
- 减少锁等待时间

---

## 小结

✅ **MVCC核心**：多版本 + ReadView + undo log
✅ **快照读**：不加锁，读历史版本，高并发
✅ **当前读**：加锁，读最新版本，防幻读
✅ **可见性判断**：根据事务ID和ReadView

MVCC是MySQL高并发的核心机制，理解MVCC有助于编写高性能的数据库应用。

---

📚 **相关阅读**：
- 下一篇：《undo log与redo log：事务日志详解》
- 推荐：《InnoDB行锁：Record Lock、Gap Lock、Next-Key Lock》
