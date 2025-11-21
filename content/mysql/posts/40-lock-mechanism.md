---
title: "MySQL锁机制：全局锁、表锁、行锁"
date: 2025-01-14T14:00:00+08:00
draft: false
tags: ["MySQL", "锁", "并发控制", "InnoDB"]
categories: ["数据库"]
description: "全面理解MySQL的锁机制，掌握全局锁、表锁、行锁的使用场景和实现原理"
series: ["MySQL从入门到精通"]
weight: 40
stage: 4
stageTitle: "事务与锁篇"
---

## MySQL锁分类

### 按锁粒度分类

```
全局锁（Global Lock）
    └─ FTWRL（Flush Tables With Read Lock）

表锁（Table Lock）
    ├─ 表级锁
    ├─ 元数据锁（MDL Lock）
    └─ 意向锁（Intention Lock）

行锁（Row Lock）
    ├─ 记录锁（Record Lock）
    ├─ 间隙锁（Gap Lock）
    └─ Next-Key Lock（Record + Gap）
```

### 按锁模式分类

| 锁模式         | 英文名             | 兼容性      | 应用场景        |
|-------------|-----------------|----------|-------------|
| **共享锁（S锁）** | Shared Lock     | 读读兼容，读写互斥 | SELECT ... LOCK IN SHARE MODE |
| **排他锁（X锁）** | Exclusive Lock  | 完全互斥     | UPDATE、DELETE、SELECT ... FOR UPDATE |

---

## 1. 全局锁（Global Lock）

### 定义

**锁住整个数据库实例**，只读不可写。

### 命令

```sql
-- 加全局读锁
FLUSH TABLES WITH READ LOCK; -- 简称FTWRL

-- 此时其他会话：
SELECT * FROM account WHERE id = 1; -- ✅ 可以读
UPDATE account SET balance = 900 WHERE id = 1; -- ❌ 阻塞
INSERT INTO account VALUES (2, 'B', 500); -- ❌ 阻塞

-- 释放锁
UNLOCK TABLES;
```

### 应用场景

**全库逻辑备份**（保证数据一致性）：

```bash
# mysqldump备份
mysqldump -h127.0.0.1 -uroot -p --all-databases --single-transaction > backup.sql

# 流程：
1. FLUSH TABLES WITH READ LOCK; -- 加全局读锁
2. 备份所有表
3. UNLOCK TABLES; -- 释放锁
```

### 缺点

- **业务停摆**：整个数据库只读，影响所有写操作
- **主从延迟**：主库加全局锁，从库同步阻塞

### 更好的替代方案

**使用InnoDB的一致性快照备份**：

```bash
# mysqldump加--single-transaction参数
mysqldump --single-transaction --master-data=2 --all-databases > backup.sql

# 原理：
1. 开启事务
2. 使用MVCC读取快照数据（不加锁）
3. 不影响其他事务的写操作
```

---

## 2. 表锁（Table Lock）

### 2.1 表级锁

**锁住整张表**，MyISAM默认使用。

```sql
-- 加表锁
LOCK TABLES account READ; -- 读锁（共享锁）
LOCK TABLES account WRITE; -- 写锁（排他锁）

-- 释放锁
UNLOCK TABLES;
```

**兼容性**：

| 锁类型           | 当前会话       | 其他会话       |
|---------------|------------|------------|
| 表级读锁（READ）    | 可读，不可写     | 可读，写阻塞     |
| 表级写锁（WRITE）   | 可读写        | 读写都阻塞      |

**InnoDB一般不使用表锁**（行锁粒度更细，并发更好）。

### 2.2 元数据锁（MDL Lock）

**自动加锁**，保护表结构一致性。

```sql
-- 事务A：查询表（自动加MDL读锁）
START TRANSACTION;
SELECT * FROM account WHERE id = 1; -- 自动加MDL读锁

-- 事务B：修改表结构（需要MDL写锁，阻塞）
ALTER TABLE account ADD COLUMN email VARCHAR(100); -- 阻塞，等待事务A提交

-- 事务A提交后，事务B才能执行
COMMIT;
```

**MDL锁类型**：

| 操作类型                | MDL锁类型 | 兼容性      |
|---------------------|--------|----------|
| SELECT、INSERT、UPDATE、DELETE | MDL读锁  | 读读兼容，读写互斥 |
| ALTER TABLE、DROP TABLE  | MDL写锁  | 完全互斥     |

**查看MDL锁等待**：

```sql
-- MySQL 5.7+
SELECT * FROM performance_schema.metadata_locks
WHERE OBJECT_TYPE = 'TABLE';
```

**避免MDL锁阻塞**：

```sql
-- 1. 尽快提交事务（不要长时间持有MDL读锁）
START TRANSACTION;
SELECT * FROM account WHERE id = 1;
COMMIT; -- 及时提交

-- 2. 设置DDL超时时间
SET SESSION lock_wait_timeout = 5; -- 5秒超时
ALTER TABLE account ADD COLUMN email VARCHAR(100);
```

### 2.3 意向锁（Intention Lock）

**InnoDB自动加锁**，用于提高加表锁的效率。

```sql
-- 事务A：加行锁（自动加意向排他锁IX）
START TRANSACTION;
SELECT * FROM account WHERE id = 1 FOR UPDATE; -- 加IX锁（表级）+ X锁（行级）

-- 事务B：加表锁（检查意向锁，发现冲突，快速返回阻塞）
LOCK TABLES account READ; -- 检查到IX锁，阻塞
```

**意向锁类型**：

| 锁类型          | 英文名                 | 含义             |
|--------------|---------------------|----------------|
| **意向共享锁（IS）** | Intention Shared Lock | 表内有行级共享锁       |
| **意向排他锁（IX）** | Intention Exclusive Lock | 表内有行级排他锁       |

**兼容性矩阵**：

|      | IS   | IX   | S锁   | X锁   |
|------|------|------|------|------|
| **IS** | ✅兼容 | ✅兼容 | ✅兼容 | ❌互斥 |
| **IX** | ✅兼容 | ✅兼容 | ❌互斥 | ❌互斥 |
| **S锁** | ✅兼容 | ❌互斥 | ✅兼容 | ❌互斥 |
| **X锁** | ❌互斥 | ❌互斥 | ❌互斥 | ❌互斥 |

**作用**：加表锁时，无需逐行检查是否有行锁，直接检查意向锁即可。

---

## 3. 行锁（Row Lock）

### 3.1 记录锁（Record Lock）

**锁住单行记录**，InnoDB默认使用。

```sql
-- 加记录锁（排他锁）
START TRANSACTION;
SELECT * FROM account WHERE id = 1 FOR UPDATE; -- 锁住id=1这一行

-- 其他事务
UPDATE account SET balance = 900 WHERE id = 1; -- 阻塞
UPDATE account SET balance = 900 WHERE id = 2; -- 不阻塞（不同行）
```

**前提条件**：**索引列条件**，否则升级为表锁。

```sql
-- ✅ 有索引，使用行锁
UPDATE account SET balance = 900 WHERE id = 1; -- id是主键

-- ❌ 无索引，升级为表锁
UPDATE account SET balance = 900 WHERE name = 'A'; -- name无索引，锁全表
```

### 3.2 间隙锁（Gap Lock）

**锁住记录之间的间隙**，防止幻读。

```sql
-- 当前数据：id = 1, 5, 10
START TRANSACTION;
SELECT * FROM account WHERE id > 5 FOR UPDATE;
-- 锁住间隙：(5, 10)、(10, +∞)

-- 其他事务
INSERT INTO account (id, name, balance) VALUES (7, 'C', 500); -- 阻塞（在间隙中）
INSERT INTO account (id, name, balance) VALUES (3, 'D', 600); -- 不阻塞（不在间隙中）
```

**作用**：防止其他事务在间隙中插入数据（防止幻读）。

**适用隔离级别**：REPEATABLE READ、SERIALIZABLE

### 3.3 Next-Key Lock

**记录锁 + 间隙锁**，InnoDB的默认锁。

```sql
-- 当前数据：id = 1, 5, 10, 15
START TRANSACTION;
SELECT * FROM account WHERE id >= 5 AND id <= 10 FOR UPDATE;

-- Next-Key Lock锁定范围：
[5, 5]      -- Record Lock（记录锁）
(5, 10)     -- Gap Lock（间隙锁）
[10, 10]    -- Record Lock
(10, 15)    -- Gap Lock

-- 其他事务（都会阻塞）
UPDATE account SET balance = 900 WHERE id = 5;  -- 阻塞（记录锁）
UPDATE account SET balance = 900 WHERE id = 10; -- 阻塞（记录锁）
INSERT INTO account (id) VALUES (7);            -- 阻塞（间隙锁）
INSERT INTO account (id) VALUES (12);           -- 阻塞（间隙锁）
```

**锁范围计算**（左开右闭）：

```sql
-- 当前索引值：1, 5, 10, 15

-- 查询：WHERE id = 5
-- 锁定：(1, 5]（Next-Key Lock）+ (5, 10)（Gap Lock）

-- 查询：WHERE id > 5 AND id < 15
-- 锁定：(5, 10]（Next-Key Lock）+ (10, 15)（Gap Lock）
```

---

## 锁对比总结

| 锁类型      | 粒度   | 并发性能 | 使用场景           | 是否自动加锁 |
|----------|------|------|----------------|--------|
| 全局锁      | 整个数据库 | ⭐    | 全库备份           | ❌ 手动   |
| 表锁       | 整张表  | ⭐⭐   | MyISAM、DDL操作    | ✅ 自动   |
| 元数据锁（MDL） | 表结构  | ⭐⭐⭐  | 保护表结构一致性       | ✅ 自动   |
| 意向锁      | 表级   | ⭐⭐⭐⭐ | 辅助表锁快速判断       | ✅ 自动   |
| 记录锁      | 单行   | ⭐⭐⭐⭐ | UPDATE、DELETE、FOR UPDATE | ✅ 自动   |
| 间隙锁      | 间隙   | ⭐⭐⭐  | 防止幻读           | ✅ 自动   |
| Next-Key Lock | 记录+间隙 | ⭐⭐⭐  | REPEATABLE READ默认 | ✅ 自动   |

---

## 查看锁信息

### 查看当前锁

```sql
-- 查看InnoDB锁等待
SELECT * FROM performance_schema.data_locks;

-- 查看锁等待关系
SELECT * FROM performance_schema.data_lock_waits;

-- 查看阻塞的事务
SELECT
    waiting_trx_id AS 等待事务,
    waiting_pid AS 等待线程,
    blocking_trx_id AS 阻塞事务,
    blocking_pid AS 阻塞线程
FROM sys.innodb_lock_waits;
```

### 查看MDL锁

```sql
-- MySQL 5.7+
SELECT
    OBJECT_TYPE,
    OBJECT_SCHEMA,
    OBJECT_NAME,
    LOCK_TYPE,
    LOCK_DURATION,
    LOCK_STATUS
FROM performance_schema.metadata_locks
WHERE OBJECT_TYPE = 'TABLE';
```

---

## 实战建议

### 1. 优先使用行锁

```sql
-- ✅ 使用主键或唯一索引（行锁）
UPDATE account SET balance = 900 WHERE id = 1;

-- ❌ 避免无索引条件（表锁）
UPDATE account SET balance = 900 WHERE name = 'A'; -- name无索引，锁全表
```

### 2. 及时提交事务

```sql
-- ❌ 不好：长时间持有锁
START TRANSACTION;
SELECT * FROM account WHERE id = 1 FOR UPDATE;
-- ... 业务逻辑处理10秒
COMMIT;

-- ✅ 好：尽快提交
START TRANSACTION;
SELECT * FROM account WHERE id = 1 FOR UPDATE;
UPDATE account SET balance = 900 WHERE id = 1;
COMMIT; -- 立即提交
```

### 3. 避免大事务

```sql
-- ❌ 不好：一次更新100万行
START TRANSACTION;
UPDATE account SET status = 'INACTIVE' WHERE created_at < '2020-01-01'; -- 100万行
COMMIT;

-- ✅ 好：分批更新
REPEAT
    UPDATE account SET status = 'INACTIVE'
    WHERE created_at < '2020-01-01'
    LIMIT 1000; -- 每次1000行
    COMMIT;
UNTIL ROW_COUNT() = 0 END REPEAT;
```

### 4. 合理设置锁等待超时

```sql
-- 查看锁等待超时时间
SHOW VARIABLES LIKE 'innodb_lock_wait_timeout'; -- 默认50秒

-- 设置为5秒
SET SESSION innodb_lock_wait_timeout = 5;
```

---

## 常见面试题

**Q1: 为什么InnoDB使用行锁，而MyISAM使用表锁？**
- InnoDB支持事务，需要细粒度的锁控制
- MyISAM不支持事务，表锁实现简单，开销小

**Q2: 如何避免表锁？**
- 确保WHERE条件使用索引
- 避免全表扫描

**Q3: 间隙锁的作用是什么？**
- 防止幻读（其他事务在间隙中插入数据）
- 仅在REPEATABLE READ及以上隔离级别使用

**Q4: 如何判断当前是行锁还是表锁？**
- 查看执行计划：EXPLAIN，如果type=ALL（全表扫描），可能是表锁
- 查看锁信息：performance_schema.data_locks

---

## 小结

✅ **全局锁**：锁整个数据库，用于全库备份
✅ **表锁**：锁整张表，MyISAM使用，InnoDB尽量避免
✅ **行锁**：锁单行记录，InnoDB默认，并发性能好
✅ **间隙锁**：防止幻读，REPEATABLE READ使用
✅ **Next-Key Lock**：记录锁+间隙锁，InnoDB默认

理解锁机制是编写高并发应用的基础。

---

📚 **相关阅读**：
- 下一篇：《InnoDB行锁：Record Lock、Gap Lock、Next-Key Lock》
- 推荐：《死锁：产生原因与解决方案》
