---
title: "死锁：产生原因与解决方案"
date: 2025-01-14T16:00:00+08:00
draft: false
tags: ["MySQL", "死锁", "并发", "事务"]
categories: ["数据库"]
description: "深入理解MySQL死锁的产生原因、检测机制、解决方案，掌握死锁预防和排查技巧"
series: ["MySQL从入门到精通"]
weight: 42
stage: 4
stageTitle: "事务与锁篇"
---

## 什么是死锁？

**死锁（Deadlock）**：两个或多个事务互相等待对方释放锁，形成循环等待，导致所有事务都无法继续执行。

```sql
-- 经典死锁场景
事务A：持有锁1，等待锁2
事务B：持有锁2，等待锁1
→ 互相等待，形成死锁
```

---

## 死锁产生条件

**必须同时满足4个条件**：

1. **互斥**：资源不能被多个事务同时占用
2. **持有并等待**：事务持有锁的同时，等待其他锁
3. **不可剥夺**：已获得的锁不能被强制释放
4. **循环等待**：事务形成循环等待链

---

## 死锁示例

### 示例1：经典死锁

```sql
-- 建表
CREATE TABLE account (
    id INT PRIMARY KEY,
    balance INT
);
INSERT INTO account VALUES (1, 1000), (2, 2000);

-- 时间线
┌─────────────────┬─────────────────────────────────┐
│ 事务A             │ 事务B                            │
├─────────────────┼─────────────────────────────────┤
│ START TRANSACTION│                                 │
│ UPDATE account  │                                 │
│ SET balance=900 │                                 │
│ WHERE id=1;     │                                 │
│ -- 持有id=1的锁  │                                 │
│                 │ START TRANSACTION                │
│                 │ UPDATE account                   │
│                 │ SET balance=1800                 │
│                 │ WHERE id=2;                      │
│                 │ -- 持有id=2的锁                   │
│ UPDATE account  │                                 │
│ SET balance=800 │                                 │
│ WHERE id=2;     │                                 │
│ -- 等待id=2的锁  │                                 │
│                 │ UPDATE account                   │
│                 │ SET balance=1100                 │
│                 │ WHERE id=1;                      │
│                 │ -- 等待id=1的锁                   │
│                 │ -- 死锁！                         │
└─────────────────┴─────────────────────────────────┘
```

**死锁检测与处理**：

```sql
-- InnoDB自动检测到死锁
ERROR 1213 (40001): Deadlock found when trying to get lock;
try restarting transaction

-- InnoDB选择回滚其中一个事务（事务B）
-- 事务A继续执行
```

### 示例2：并发插入导致的死锁

```sql
-- 建表
CREATE TABLE orders (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT,
    amount INT,
    KEY idx_user (user_id)
);

-- 事务A
START TRANSACTION;
INSERT INTO orders (user_id, amount) VALUES (1, 100);
-- 持有id=1的锁 + user_id=1的间隙锁

-- 事务B
START TRANSACTION;
INSERT INTO orders (user_id, amount) VALUES (1, 200);
-- 等待user_id=1的间隙锁

-- 事务A
INSERT INTO orders (user_id, amount) VALUES (1, 300);
-- 等待自己释放的间隙锁（死锁！）
```

### 示例3：间隙锁导致的死锁

```sql
-- 建表
CREATE TABLE product (
    id INT PRIMARY KEY,
    name VARCHAR(50),
    stock INT,
    KEY idx_stock (stock)
);
INSERT INTO product VALUES (1, 'A', 10), (5, 'B', 20), (10, 'C', 30);

-- 事务A
START TRANSACTION;
SELECT * FROM product WHERE stock = 15 FOR UPDATE;
-- stock=15不存在，加间隙锁：(10, 20)

-- 事务B
START TRANSACTION;
SELECT * FROM product WHERE stock = 15 FOR UPDATE;
-- 也加间隙锁：(10, 20)（间隙锁不冲突）

-- 事务A
INSERT INTO product (id, name, stock) VALUES (7, 'D', 15);
-- 等待事务B释放间隙锁

-- 事务B
INSERT INTO product (id, name, stock) VALUES (8, 'E', 15);
-- 等待事务A释放间隙锁（死锁！）
```

---

## 死锁检测机制

### InnoDB自动检测

**wait-for graph（等待图）**：

```sql
-- InnoDB维护等待图
事务A → 等待 → 事务B
事务B → 等待 → 事务A
-- 检测到循环，发生死锁
```

**检测策略**：

```sql
-- 查看死锁检测配置
SHOW VARIABLES LIKE 'innodb_deadlock_detect'; -- 默认ON

-- 关闭自动检测（不推荐）
SET GLOBAL innodb_deadlock_detect = OFF;
```

### 死锁超时

```sql
-- 锁等待超时时间
SHOW VARIABLES LIKE 'innodb_lock_wait_timeout'; -- 默认50秒

-- 如果50秒后仍未获得锁，报错
ERROR 1205 (HY000): Lock wait timeout exceeded;
try restarting transaction
```

---

## 查看死锁日志

### 1. 查看最近一次死锁

```sql
-- 查看死锁信息
SHOW ENGINE INNODB STATUS\G

-- 输出示例（部分）
*** (1) TRANSACTION:
TRANSACTION 12345, ACTIVE 5 sec starting index read
mysql tables in use 1, locked 1
LOCK WAIT 2 lock struct(s), heap size 1136, 1 row lock(s)
MySQL thread id 10, OS thread handle 140123456, query id 100 localhost root updating
UPDATE account SET balance=800 WHERE id=2

*** (1) WAITING FOR THIS LOCK TO BE GRANTED:
RECORD LOCKS space id 2 page no 3 n bits 72 index PRIMARY of table `test`.`account`
trx id 12345 lock_mode X locks rec but not gap waiting

*** (2) TRANSACTION:
TRANSACTION 12346, ACTIVE 3 sec starting index read
mysql tables in use 1, locked 1
3 lock struct(s), heap size 1136, 2 row lock(s)
MySQL thread id 11, OS thread handle 140234567, query id 101 localhost root updating
UPDATE account SET balance=1100 WHERE id=1

*** (2) HOLDS THE LOCK(S):
RECORD LOCKS space id 2 page no 3 n bits 72 index PRIMARY of table `test`.`account`
trx id 12346 lock_mode X locks rec but not gap

*** (2) WAITING FOR THIS LOCK TO BE GRANTED:
RECORD LOCKS space id 2 page no 3 n bits 72 index PRIMARY of table `test`.`account`
trx id 12346 lock_mode X locks rec but not gap waiting

*** WE ROLL BACK TRANSACTION (2)
```

### 2. 开启死锁日志

```sql
-- MySQL 8.0+
SET GLOBAL log_error_verbosity = 3;

-- 查看错误日志
-- tail -f /var/log/mysql/error.log
```

---

## 死锁解决方案

### 1. 预防死锁

#### 方案1：固定加锁顺序

```sql
-- ❌ 不好：随机加锁顺序
-- 事务A
UPDATE account SET balance=900 WHERE id=1;
UPDATE account SET balance=800 WHERE id=2;

-- 事务B
UPDATE account SET balance=1800 WHERE id=2; -- 先锁id=2
UPDATE account SET balance=1100 WHERE id=1; -- 后锁id=1
-- 可能死锁

-- ✅ 好：固定加锁顺序（按主键升序）
-- 事务A
UPDATE account SET balance=900 WHERE id=1; -- 先锁id=1
UPDATE account SET balance=800 WHERE id=2; -- 后锁id=2

-- 事务B
UPDATE account SET balance=1100 WHERE id=1; -- 先锁id=1（等待事务A）
UPDATE account SET balance=1800 WHERE id=2; -- 后锁id=2
-- 不会死锁
```

#### 方案2：一次性获取所有锁

```sql
-- ✅ 一次性锁住所有需要的行
START TRANSACTION;
SELECT * FROM account WHERE id IN (1, 2) FOR UPDATE; -- 一次性锁住
UPDATE account SET balance=900 WHERE id=1;
UPDATE account SET balance=800 WHERE id=2;
COMMIT;
```

#### 方案3：缩小事务范围

```sql
-- ❌ 不好：事务太大
START TRANSACTION;
SELECT * FROM account WHERE id=1; -- 复杂查询
-- ... 业务逻辑处理（耗时10秒）
UPDATE account SET balance=900 WHERE id=1;
UPDATE account SET balance=800 WHERE id=2;
COMMIT;

-- ✅ 好：事务精简
-- 先查询（不加锁）
SELECT * FROM account WHERE id=1;
-- 业务逻辑处理

-- 再开启事务（快速提交）
START TRANSACTION;
UPDATE account SET balance=900 WHERE id=1;
UPDATE account SET balance=800 WHERE id=2;
COMMIT;
```

#### 方案4：降低隔离级别

```sql
-- REPEATABLE READ：有间隙锁，容易死锁
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- READ COMMITTED：无间隙锁，减少死锁概率
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
```

### 2. 死锁处理

#### 方案1：重试机制

```python
# Python示例
import pymysql
import time

def transfer_with_retry(from_id, to_id, amount, max_retries=3):
    for i in range(max_retries):
        try:
            conn = pymysql.connect(...)
            cursor = conn.cursor()

            # 开启事务
            conn.begin()

            # 转账操作
            cursor.execute("UPDATE account SET balance=balance-%s WHERE id=%s", (amount, from_id))
            cursor.execute("UPDATE account SET balance=balance+%s WHERE id=%s", (amount, to_id))

            # 提交事务
            conn.commit()
            print("转账成功")
            return True

        except pymysql.err.OperationalError as e:
            if e.args[0] == 1213:  # 死锁错误码
                print(f"发生死锁，重试第{i+1}次...")
                conn.rollback()
                time.sleep(0.1 * (i + 1))  # 指数退避
            else:
                raise
        finally:
            conn.close()

    print("转账失败，达到最大重试次数")
    return False
```

#### 方案2：监控与告警

```sql
-- 监控死锁频率
-- 查看死锁次数（从服务启动至今）
SHOW GLOBAL STATUS LIKE 'Innodb_deadlocks';

-- 如果死锁频繁（如每小时>10次），需要优化业务逻辑
```

---

## 实战建议

### 1. 设计阶段避免死锁

```sql
-- ✅ 使用唯一索引替代锁
CREATE UNIQUE INDEX uk_user_product ON orders(user_id, product_id);

-- 插入时自动检测冲突（无需加锁）
INSERT INTO orders (user_id, product_id) VALUES (1, 1001);
-- 如果冲突，直接报错，无死锁风险
```

### 2. 固定锁顺序（应用层实现）

```java
// Java示例
public void transfer(int fromId, int toId, int amount) {
    // 按ID升序排列，固定加锁顺序
    int firstId = Math.min(fromId, toId);
    int secondId = Math.max(fromId, toId);

    // 先锁小ID，再锁大ID
    updateBalance(firstId, ...);
    updateBalance(secondId, ...);
}
```

### 3. 避免长事务

```sql
-- 查看长事务
SELECT * FROM information_schema.INNODB_TRX
WHERE TIME_TO_SEC(TIMEDIFF(NOW(), trx_started)) > 10;

-- 杀死长事务
KILL <trx_mysql_thread_id>;
```

### 4. 监控死锁指标

```bash
# Prometheus监控
innodb_deadlocks_total{instance="mysql-01"}

# 告警规则（每小时死锁>10次）
rate(innodb_deadlocks_total[1h]) > 10
```

---

## 常见场景与解决方案

### 场景1：转账业务

```sql
-- 问题：并发转账可能死锁
-- 解决：固定加锁顺序（按账户ID升序）

-- 应用层实现
def transfer(from_id, to_id, amount):
    # 固定顺序
    ids = sorted([from_id, to_id])

    # 一次性锁定
    SELECT * FROM account WHERE id IN (ids[0], ids[1]) FOR UPDATE;

    # 更新余额
    UPDATE account SET balance = balance - amount WHERE id = from_id;
    UPDATE account SET balance = balance + amount WHERE id = to_id;
```

### 场景2：秒杀扣库存

```sql
-- 问题：高并发扣库存可能死锁
-- 解决：使用CAS（Compare And Swap）

-- ✅ 使用乐观锁（无死锁）
UPDATE product
SET stock = stock - 1, version = version + 1
WHERE id = 1001 AND stock > 0 AND version = <old_version>;

-- 如果更新失败（version不匹配），重试
```

### 场景3：批量更新

```sql
-- 问题：批量更新顺序不一致导致死锁
-- 解决：固定更新顺序（按主键排序）

-- ❌ 不好：随机顺序
UPDATE account SET status = 'INACTIVE' WHERE id IN (10, 5, 15, 2);

-- ✅ 好：固定顺序
UPDATE account SET status = 'INACTIVE' WHERE id IN (2, 5, 10, 15);
-- 或使用
UPDATE account SET status = 'INACTIVE' WHERE id IN (10, 5, 15, 2) ORDER BY id;
```

---

## 常见面试题

**Q1: 死锁的4个必要条件是什么？**
- 互斥、持有并等待、不可剥夺、循环等待

**Q2: InnoDB如何检测死锁？**
- wait-for graph（等待图），检测循环等待

**Q3: 死锁发生后，InnoDB如何处理？**
- 自动选择一个事务回滚（通常选择锁资源少的事务）

**Q4: 如何预防死锁？**
- 固定加锁顺序
- 一次性获取所有锁
- 缩小事务范围
- 降低隔离级别

**Q5: 为什么间隙锁容易导致死锁？**
- 间隙锁之间不冲突，但都会阻塞INSERT，容易形成循环等待

---

## 小结

✅ **死锁定义**：多个事务互相等待对方释放锁
✅ **预防方法**：固定加锁顺序、一次性获取锁、缩小事务
✅ **检测机制**：wait-for graph自动检测
✅ **处理策略**：自动回滚 + 应用层重试

理解死锁原理和预防方法是编写高并发应用的基础。

---

📚 **相关阅读**：
- 下一篇：《乐观锁与悲观锁：应用场景对比》
- 推荐：《InnoDB行锁：Record Lock、Gap Lock、Next-Key Lock》
