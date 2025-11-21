---
title: "undo log与redo log：事务日志详解"
date: 2025-01-14T13:00:00+08:00
draft: false
tags: ["MySQL", "事务", "undo log", "redo log", "binlog"]
categories: ["数据库"]
description: "深入理解MySQL的三种日志：undo log保证原子性，redo log保证持久性，binlog用于复制和恢复"
series: ["MySQL从入门到精通"]
weight: 39
stage: 4
stageTitle: "事务与锁篇"
---

## MySQL的三种日志

| 日志类型      | 作用          | 实现层  | 记录内容     | 刷盘时机        |
|-----------|-------------|------|----------|-------------|
| **undo log** | 保证原子性（回滚）   | InnoDB | 修改前的旧值   | 事务执行时       |
| **redo log** | 保证持久性（崩溃恢复） | InnoDB | 修改后的新值   | 事务提交时       |
| **binlog**  | 主从复制、数据恢复   | Server层 | 逻辑SQL或行变更 | 事务提交时       |

---

## 1. undo log（回滚日志）

### 作用

1. **事务回滚**：保证原子性（ROLLBACK时恢复数据）
2. **MVCC实现**：提供历史版本数据（快照读）

### 记录内容

**记录数据修改前的旧值**，用于回滚。

```sql
-- 执行UPDATE前，记录旧值到undo log
UPDATE account SET balance = 900 WHERE id = 1;

-- undo log记录：
INSERT INTO undo_log VALUES (
    trx_id = 101,
    table_id = account,
    row_id = 1,
    old_balance = 1000  -- 修改前的旧值
);
```

### undo log类型

| 类型               | 操作类型     | 回滚方式           |
|------------------|----------|----------------|
| **INSERT undo** | INSERT   | 删除插入的行         |
| **UPDATE undo** | UPDATE/DELETE | 恢复修改前的值        |

```sql
-- INSERT undo log
INSERT INTO account VALUES (2, 'B', 500);
-- undo log：DELETE FROM account WHERE id = 2;

-- UPDATE undo log
UPDATE account SET balance = 900 WHERE id = 1;
-- undo log：UPDATE account SET balance = 1000 WHERE id = 1;

-- DELETE undo log
DELETE FROM account WHERE id = 1;
-- undo log：INSERT INTO account VALUES (1, 'A', 1000);
```

### 版本链

undo log通过**DB_ROLL_PTR**形成版本链，用于MVCC。

```
当前版本（最新）
┌────┬──────┬─────────┬────────────┬─────────────┐
│ id │ name │ balance │ DB_TRX_ID  │ DB_ROLL_PTR │
├────┼──────┼─────────┼────────────┼─────────────┤
│ 1  │ A    │ 800     │ 102        │ ───────┐    │
└────┴──────┴─────────┴────────────┴─────────┘    │
                                            ▼
                                    undo log v2
                                    balance=900, trx_id=101
                                            │
                                            ▼
                                    undo log v1
                                    balance=1000, trx_id=100
```

### 清理时机

**undo log何时删除？**

```sql
-- 清理条件（同时满足）：
1. 事务已提交或回滚
2. 没有其他事务需要读取该版本（ReadView已不可见）
3. 不在活跃事务列表中

-- 查看undo log空间占用
SELECT tablespace_name, file_size/1024/1024 AS size_mb
FROM information_schema.FILES
WHERE tablespace_name LIKE '%undo%';
```

**长事务的危害**：

```sql
-- 事务A：长时间未提交
START TRANSACTION;
SELECT * FROM account WHERE id = 1; -- 生成ReadView

-- ... 1小时后仍未提交

-- 导致：
1. undo log无法清理（事务A可能还要读历史版本）
2. 磁盘空间占用增加
3. 版本链过长，影响查询性能
```

---

## 2. redo log（重做日志）

### 作用

**保证事务持久性（Durability）**：即使MySQL崩溃，已提交的事务也不会丢失。

### 记录内容

**记录数据修改后的新值**（物理日志，记录数据页的变更）。

```sql
-- 执行UPDATE
UPDATE account SET balance = 900 WHERE id = 1;

-- redo log记录：
在数据页P5，偏移量100的位置，将balance字段从1000改为900
```

### WAL机制（Write-Ahead Logging）

**核心思想**：先写日志，再写磁盘。

```sql
-- 传统方式（同步写磁盘，慢）
UPDATE account SET balance = 900 WHERE id = 1;
-- 直接修改数据文件（随机写，4KB页，慢）

-- WAL方式（先写日志，快）
UPDATE account SET balance = 900 WHERE id = 1;
1. 修改内存中的Buffer Pool（快）
2. 写redo log到磁盘（顺序写，快）
3. 返回客户端"提交成功"
4. 后台线程异步刷新数据文件（慢）
```

**为什么快？**

| 操作类型     | 写入方式   | 速度   | 说明              |
|----------|--------|------|-----------------|
| 写数据文件    | 随机写    | 慢⭐   | 需要找到具体数据页，4KB页 |
| 写redo log | 顺序写    | 快⭐⭐⭐ | 追加写入，批量刷盘       |

### redo log文件

```bash
# InnoDB redo log文件（循环使用）
/var/lib/mysql/ib_logfile0  -- 48MB
/var/lib/mysql/ib_logfile1  -- 48MB

# MySQL 8.0+ 改为
/var/lib/mysql/#innodb_redo/ib_redo_XXX
```

**循环写入机制**：

```
ib_logfile0                    ib_logfile1
┌─────────────────────────┐   ┌─────────────────────────┐
│▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░│──▶│░░░░░░░░░░░░░░░░░░░░░░░░│
└─────────────────────────┘   └─────────────────────────┘
 ▲                                              │
 └──────────────────────────────────────────────┘
          写满后从头覆盖（已刷盘的数据可以覆盖）
```

### 刷盘策略

**innodb_flush_log_at_trx_commit** 参数：

| 值   | 刷盘时机           | 性能   | 安全性  | 数据丢失风险        |
|-----|----------------|------|------|-----------|
| **0** | 每秒刷盘一次         | ⭐⭐⭐⭐ | ⭐    | 可能丢失1秒数据     |
| **1** | 每次事务提交立即刷盘（默认） | ⭐⭐   | ⭐⭐⭐⭐ | 不丢失数据         |
| **2** | 每次提交写OS缓存，每秒刷盘 | ⭐⭐⭐  | ⭐⭐⭐  | MySQL崩溃不丢失，OS崩溃丢失1秒 |

```sql
-- 查看当前配置
SHOW VARIABLES LIKE 'innodb_flush_log_at_trx_commit';

-- 设置为2（折中方案）
SET GLOBAL innodb_flush_log_at_trx_commit = 2;
```

**性能对比**（100万行UPDATE测试）：

| 参数值 | 耗时    | TPS   |
|-----|-------|-------|
| 0   | 45秒   | 22000 |
| 1   | 180秒  | 5500  |
| 2   | 60秒   | 16600 |

### 崩溃恢复流程

```sql
-- MySQL启动时自动执行
1. 读取redo log
2. 找到未刷盘的数据页变更
3. 重做（Redo）已提交的事务
4. 回滚（Undo）未提交的事务
5. 恢复到崩溃前的一致状态
```

**示例**：

```sql
-- 事务A：已提交，redo log已写入，但数据页未刷盘
START TRANSACTION;
UPDATE account SET balance = 900 WHERE id = 1;
COMMIT; -- redo log写入成功

-- MySQL突然崩溃（数据页未刷盘）

-- 重启后：
1. 读取redo log，发现事务A已提交
2. 重做：将balance=900写入数据页
3. 数据不丢失✅
```

---

## 3. binlog（二进制日志）

### 作用

1. **主从复制**：将主库的变更同步到从库
2. **数据恢复**：基于时间点恢复（PITR）

### 记录内容

**逻辑SQL或行变更**（Server层日志，所有存储引擎通用）。

```sql
-- 执行UPDATE
UPDATE account SET balance = 900 WHERE id = 1;

-- binlog记录（STATEMENT格式）：
UPDATE account SET balance = 900 WHERE id = 1;

-- binlog记录（ROW格式）：
-- 修改前：id=1, balance=1000
-- 修改后：id=1, balance=900
```

### binlog格式

| 格式            | 记录内容      | 优点        | 缺点           |
|---------------|-----------|-----------|--------------|
| **STATEMENT** | SQL原文      | 日志量小      | 部分SQL不安全（如NOW()） |
| **ROW**       | 行变更       | 完全一致      | 日志量大         |
| **MIXED**     | 混合（自动切换）  | 平衡        | 复杂           |

```sql
-- 查看binlog格式
SHOW VARIABLES LIKE 'binlog_format';

-- 设置为ROW（推荐）
SET GLOBAL binlog_format = 'ROW';
```

### 刷盘策略

**sync_binlog** 参数：

| 值   | 刷盘时机           | 性能   | 安全性  |
|-----|----------------|------|------|
| **0** | 由OS决定           | ⭐⭐⭐⭐ | ⭐    |
| **1** | 每次事务提交立即刷盘（推荐） | ⭐⭐   | ⭐⭐⭐⭐ |
| **N** | 每N个事务刷盘        | ⭐⭐⭐  | ⭐⭐⭐  |

```sql
-- 查看当前配置
SHOW VARIABLES LIKE 'sync_binlog';

-- 设置为1（安全）
SET GLOBAL sync_binlog = 1;
```

---

## redo log vs binlog

| 特性      | redo log                     | binlog                        |
|---------|------------------------------|-------------------------------|
| 所属层     | InnoDB存储引擎                    | MySQL Server层                  |
| 记录内容    | 物理日志（数据页变更）                  | 逻辑日志（SQL或行变更）                 |
| 写入方式    | 循环写（覆盖）                      | 追加写（不覆盖）                      |
| 用途      | 崩溃恢复（保证持久性）                  | 主从复制、数据恢复                     |
| 事务支持    | 支持（保证ACID）                   | 不支持（仅记录）                      |

---

## 两阶段提交（2PC）

**问题**：如何保证redo log和binlog的一致性？

**解决方案**：两阶段提交（Two-Phase Commit）

### 提交流程

```sql
UPDATE account SET balance = 900 WHERE id = 1;

-- 阶段1：Prepare（准备）
1. 写redo log（prepare状态）
2. 写binlog
3. 刷新binlog到磁盘

-- 阶段2：Commit（提交）
4. 写redo log（commit状态）
5. 事务提交成功
```

**时间线**：

```
┌──────────────┬──────────────┬──────────────┬──────────────┐
│ InnoDB       │ redo log     │ binlog       │ InnoDB       │
├──────────────┼──────────────┼──────────────┼──────────────┤
│ 1. 更新Buffer│ 2. 写prepare │ 3. 写binlog  │ 4. 写commit  │
│    Pool      │    状态      │    并刷盘    │    状态      │
└──────────────┴──────────────┴──────────────┴──────────────┘
```

### 崩溃恢复

**场景1：binlog写入前崩溃**

```sql
1. 写redo log（prepare）
2. ❌ 崩溃，binlog未写入
3. 恢复：事务回滚（binlog不完整，从库无此变更）
```

**场景2：binlog写入后崩溃**

```sql
1. 写redo log（prepare）
2. 写binlog成功
3. ❌ 崩溃，redo log未commit
4. 恢复：事务提交（binlog已写入，从库有此变更）
```

**保证一致性**：主库和从库数据完全一致。

---

## 实战建议

### 1. 生产环境配置（推荐）

```ini
# my.cnf
[mysqld]
# redo log配置（安全优先）
innodb_flush_log_at_trx_commit = 1

# binlog配置（安全优先）
sync_binlog = 1
binlog_format = ROW

# redo log大小（根据业务调整）
innodb_log_file_size = 512M
innodb_log_files_in_group = 2
```

### 2. 性能优化配置（可接受丢失1秒数据）

```ini
# my.cnf
[mysqld]
innodb_flush_log_at_trx_commit = 2  # 每秒刷盘
sync_binlog = 10                   # 每10个事务刷盘
```

### 3. 监控日志空间

```sql
-- undo log空间
SELECT tablespace_name,
       file_size/1024/1024 AS size_mb
FROM information_schema.FILES
WHERE tablespace_name LIKE '%undo%';

-- binlog空间
SHOW BINARY LOGS;
-- 清理旧binlog（保留3天）
PURGE BINARY LOGS BEFORE DATE_SUB(NOW(), INTERVAL 3 DAY);
```

### 4. 避免长事务

```sql
-- 查看长事务
SELECT trx_id, trx_state, trx_started,
       TIME_TO_SEC(TIMEDIFF(NOW(), trx_started)) AS duration_sec
FROM information_schema.INNODB_TRX
WHERE TIME_TO_SEC(TIMEDIFF(NOW(), trx_started)) > 60;

-- 杀死长事务
KILL <trx_mysql_thread_id>;
```

---

## 常见面试题

**Q1: undo log和redo log的区别？**
- undo log：记录旧值，用于回滚和MVCC
- redo log：记录新值，用于崩溃恢复

**Q2: 为什么需要两阶段提交？**
- 保证redo log和binlog一致
- 保证主从库数据一致

**Q3: redo log写入速度为什么快？**
- 顺序写（vs 数据文件的随机写）
- 批量刷盘（group commit）

**Q4: 如何选择刷盘策略？**
- 数据安全优先：innodb_flush_log_at_trx_commit=1, sync_binlog=1
- 性能优先（可接受丢失1秒）：设置为2和10

---

## 小结

✅ **undo log**：回滚日志，保证原子性，支持MVCC
✅ **redo log**：重做日志，保证持久性，崩溃恢复
✅ **binlog**：二进制日志，主从复制，数据恢复
✅ **两阶段提交**：保证redo log和binlog一致

理解三种日志的作用和配置，是MySQL调优的基础。

---

📚 **相关阅读**：
- 下一篇：《MySQL锁机制：全局锁、表锁、行锁》
- 推荐：《MVCC多版本并发控制：原理与实现》
