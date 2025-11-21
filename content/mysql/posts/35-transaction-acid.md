---
title: "事务的四大特性：ACID详解"
date: 2025-01-14T09:00:00+08:00
draft: false
tags: ["MySQL", "事务", "ACID", "数据库原理"]
categories: ["数据库"]
description: "深入理解MySQL事务的ACID特性，掌握原子性、一致性、隔离性、持久性的原理与实现"
series: ["MySQL从入门到精通"]
weight: 35
stage: 4
stageTitle: "事务与锁篇"
---

## 什么是事务？

**事务（Transaction）** 是数据库操作的最小工作单元，是一组不可分割的SQL语句集合。

```sql
-- 转账场景：A向B转账100元
START TRANSACTION;
UPDATE account SET balance = balance - 100 WHERE user_id = 'A';
UPDATE account SET balance = balance + 100 WHERE user_id = 'B';
COMMIT;
```

## ACID四大特性

### 1. 原子性（Atomicity）

**定义**：事务是不可分割的最小单元，要么全部成功，要么全部失败回滚。

**实现机制**：**undo log（回滚日志）**
- 每次修改前，记录原始值到undo log
- 回滚时，读取undo log恢复数据

```sql
-- 示例：转账失败自动回滚
START TRANSACTION;
UPDATE account SET balance = balance - 100 WHERE user_id = 'A'; -- 成功
UPDATE account SET balance = balance + 100 WHERE user_id = 'B'; -- 失败（余额不足）
ROLLBACK; -- 自动回滚，A的余额恢复
```

**应用场景**：
- 订单支付（扣库存 + 创建订单 + 扣款）
- 批量数据导入（全部成功或全部失败）

### 2. 一致性（Consistency）

**定义**：事务执行前后，数据库从一个一致性状态转换到另一个一致性状态。

**一致性约束**：
1. **数据完整性约束**：主键、外键、唯一索引
2. **业务规则约束**：账户余额>=0，库存>=0
3. **应用层约束**：总金额守恒

```sql
-- 转账前：A有1000，B有500，总额1500
-- 转账后：A有900，B有600，总额仍是1500

-- 违反一致性的例子
UPDATE account SET balance = balance - 100 WHERE user_id = 'A';
-- 如果这里系统崩溃，没有执行下一条，总额变成1400，违反一致性
UPDATE account SET balance = balance + 100 WHERE user_id = 'B';
```

**如何保证一致性**？
- 由**原子性、隔离性、持久性共同保证**
- 应用层也要做校验（如余额检查）

### 3. 隔离性（Isolation）

**定义**：多个事务并发执行时，相互隔离，不会互相干扰。

**并发问题**：
- **脏读**：读到未提交的数据
- **不可重复读**：同一查询两次结果不同
- **幻读**：范围查询两次结果不同

**实现机制**：**锁 + MVCC（多版本并发控制）**

```sql
-- 事务A
START TRANSACTION;
SELECT balance FROM account WHERE user_id = 'A'; -- 读到1000
-- ... 其他操作
SELECT balance FROM account WHERE user_id = 'A'; -- 仍然读到1000（可重复读）
COMMIT;

-- 事务B（并发执行）
START TRANSACTION;
UPDATE account SET balance = 900 WHERE user_id = 'A';
COMMIT;
```

**隔离级别**（从低到高）：
1. **READ UNCOMMITTED**：可能脏读
2. **READ COMMITTED**：避免脏读
3. **REPEATABLE READ**（MySQL默认）：避免脏读、不可重复读
4. **SERIALIZABLE**：完全串行化

### 4. 持久性（Durability）

**定义**：事务一旦提交，对数据的修改就是永久的，即使系统崩溃也不会丢失。

**实现机制**：**redo log（重做日志）**
- 事务提交时，先写redo log（顺序写，快）
- 然后异步刷盘到数据文件（随机写，慢）
- 崩溃恢复时，根据redo log重做未完成的操作

```bash
# MySQL崩溃重启流程
1. 读取redo log
2. 重做已提交但未写入磁盘的事务
3. 回滚未提交的事务（根据undo log）
4. 数据库恢复到崩溃前的一致状态
```

**持久化策略**（innodb_flush_log_at_trx_commit）：
- **0**：每秒刷盘（性能最好，可能丢失1秒数据）
- **1**：每次提交刷盘（默认，最安全）
- **2**：每次提交写OS缓存，每秒刷盘（折中）

## ACID总结

| 特性   | 含义            | 实现机制          | 作用              |
|------|---------------|---------------|-----------------|
| 原子性  | 全部成功或全部失败     | undo log      | 保证操作不可分割        |
| 一致性  | 从一个一致状态到另一个   | A+I+D共同保证     | 保证数据符合约束        |
| 隔离性  | 事务之间相互隔离      | 锁 + MVCC      | 解决并发冲突          |
| 持久性  | 提交后永久生效       | redo log      | 防止数据丢失          |

## 实战建议

### 1. 事务边界要小
```sql
-- ❌ 不好：事务太大
START TRANSACTION;
SELECT ... -- 复杂查询，耗时10秒
UPDATE ... -- 批量更新，耗时30秒
-- 长时间占用锁，影响并发
COMMIT;

-- ✅ 好：事务精简
START TRANSACTION;
UPDATE ... -- 只包含必要的写操作
COMMIT;
```

### 2. 避免长事务
```sql
-- 查看当前运行的事务
SELECT * FROM information_schema.INNODB_TRX;

-- 查看持续时间超过60秒的事务
SELECT * FROM information_schema.INNODB_TRX
WHERE TIME_TO_SEC(TIMEDIFF(NOW(), trx_started)) > 60;
```

**长事务的危害**：
- 占用锁资源，阻塞其他事务
- undo log膨胀，占用磁盘空间
- 增加死锁概率

### 3. 手动事务 vs 自动提交
```sql
-- 查看自动提交状态
SHOW VARIABLES LIKE 'autocommit'; -- 默认ON

-- 关闭自动提交（慎用）
SET autocommit = 0;

-- 推荐：显式使用事务
START TRANSACTION;
-- 业务SQL
COMMIT; -- 或 ROLLBACK
```

### 4. 保存点（Savepoint）
```sql
START TRANSACTION;
INSERT INTO orders VALUES (1, 'A', 100);
SAVEPOINT sp1; -- 保存点

INSERT INTO orders VALUES (2, 'B', 200);
ROLLBACK TO sp1; -- 回滚到保存点（保留第一条插入）

INSERT INTO orders VALUES (3, 'C', 300);
COMMIT; -- 提交1和3，2被回滚
```

## 常见面试题

**Q1: 为什么需要undo log和redo log两种日志？**
- **undo log**：保证原子性（回滚）
- **redo log**：保证持久性（崩溃恢复）

**Q2: 一致性是由谁保证的？**
- 数据库层面：原子性 + 隔离性 + 持久性
- 应用层面：业务逻辑校验（如余额检查）

**Q3: ACID和CAP理论的区别？**
- **ACID**：单机数据库的一致性保证
- **CAP**：分布式系统的权衡（一致性、可用性、分区容错性）

## 小结

✅ **原子性**：undo log保证全部成功或全部失败
✅ **一致性**：业务规则始终得到满足
✅ **隔离性**：锁+MVCC解决并发冲突
✅ **持久性**：redo log保证数据不丢失

ACID是数据库事务的基石，理解ACID原理有助于编写高质量的数据库应用程序。

---

📚 **相关阅读**：
- 下一篇：《事务的隔离级别：从READ UNCOMMITTED到SERIALIZABLE》
- 推荐：《MVCC多版本并发控制：原理与实现》
