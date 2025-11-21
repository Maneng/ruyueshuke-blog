---
title: "存储引擎对比：InnoDB vs MyISAM"
date: 2025-01-15T10:00:00+08:00
draft: false
tags: ["MySQL", "InnoDB", "MyISAM", "存储引擎"]
categories: ["数据库"]
description: "深入对比InnoDB和MyISAM存储引擎，掌握存储引擎的选择策略"
series: ["MySQL从入门到精通"]
weight: 46
stage: 5
stageTitle: "架构原理篇"
---

## 存储引擎概述

**存储引擎（Storage Engine）** 是MySQL的核心组件，负责数据的存储和读取。

```sql
-- 查看支持的存储引擎
SHOW ENGINES;

-- 输出示例
+--------------------+---------+
| Engine             | Support |
+--------------------+---------+
| InnoDB             | DEFAULT |  -- 默认引擎
| MyISAM             | YES     |
| MEMORY             | YES     |
| CSV                | YES     |
| ARCHIVE            | YES     |
+--------------------+---------+
```

---

## InnoDB vs MyISAM对比

| 特性          | InnoDB            | MyISAM       |
|-------------|-------------------|--------------|
| **事务支持**    | ✅ 支持ACID         | ❌ 不支持        |
| **锁粒度**     | ✅ 行锁              | ❌ 表锁         |
| **外键**      | ✅ 支持              | ❌ 不支持        |
| **崩溃恢复**    | ✅ 自动恢复（redo log） | ❌ 需要手动修复     |
| **MVCC**    | ✅ 支持              | ❌ 不支持        |
| **全文索引**    | ✅ 支持（5.6+）       | ✅ 支持         |
| **存储结构**    | 聚簇索引            | 非聚簇索引        |
| **COUNT(*)** | 慢（需要扫描）         | 快（存储行数）      |
| **空间占用**    | 较大              | 较小           |
| **适用场景**    | OLTP（事务处理）      | OLAP（统计分析）   |

---

## InnoDB存储引擎

### 核心特性

1. **支持事务**：ACID保障
2. **行级锁**：高并发性能
3. **MVCC**：读写不冲突
4. **外键约束**：数据完整性

### 文件结构

```bash
# InnoDB文件（MySQL 5.7+）
/var/lib/mysql/
  ├─ ibdata1                # 系统表空间（共享）
  ├─ ib_logfile0            # redo log文件
  ├─ ib_logfile1
  ├─ test/                  # 数据库目录
  │   ├─ users.ibd          # 独立表空间（数据+索引）
  │   └─ users.frm          # 表结构定义（MySQL 8.0已废弃）
```

### 聚簇索引

**主键索引直接存储数据**：

```
主键索引（B+树）
       10
      /  \
     5    15
    / \   / \
  [数据] [数据]
```

**优点**：
- 主键查询快（直接读取数据）
- 范围查询快（叶子节点有序）

**缺点**：
- 二级索引需要回表（先查二级索引，再查主键索引）

### 适用场景

```sql
-- 适合InnoDB的场景
1. 事务需求（转账、订单、支付）
2. 高并发读写（电商、社交）
3. 数据一致性要求高（金融、库存）
4. 需要外键约束
```

---

## MyISAM存储引擎

### 核心特性

1. **不支持事务**：无ACID保障
2. **表级锁**：并发性能差
3. **快速COUNT**：存储行数
4. **全文索引**：早期支持

### 文件结构

```bash
# MyISAM文件
/var/lib/mysql/test/
  ├─ users.frm          # 表结构定义
  ├─ users.MYD          # 数据文件（MyData）
  └─ users.MYI          # 索引文件（MyIndex）
```

### 非聚簇索引

**索引和数据分离存储**：

```
主键索引（B+树）
       10
      /  \
     5    15
    / \   / \
  [地址] [地址]  → 指向.MYD文件中的数据
```

**优点**：
- 插入性能好（数据按插入顺序存储）
- COUNT(*)快（存储行数）

**缺点**：
- 查询需要两次IO（读索引+读数据文件）

### 适用场景

```sql
-- 适合MyISAM的场景（已很少使用）
1. 只读数据（日志、历史数据）
2. 统计分析（COUNT、SUM频繁）
3. 全文搜索（MySQL 5.6前）
```

---

## 性能对比

### 1. COUNT(\*)性能

```sql
-- InnoDB：需要扫描表（受MVCC影响）
SELECT COUNT(*) FROM users; -- 慢（需要扫描）

-- MyISAM：直接返回存储的行数
SELECT COUNT(*) FROM users; -- 快（O(1)）

-- 原因：
InnoDB的MVCC机制，不同事务看到的行数可能不同，无法缓存
MyISAM无事务，行数固定，可以缓存
```

### 2. 写入性能

```sql
-- InnoDB：行锁，高并发
INSERT INTO users (name) VALUES ('Alice'); -- 并发写入，互不阻塞

-- MyISAM：表锁，低并发
INSERT INTO users (name) VALUES ('Bob');   -- 阻塞其他INSERT
```

### 3. 查询性能

```sql
-- InnoDB：主键查询快
SELECT * FROM users WHERE id = 1; -- 一次B+树查询

-- MyISAM：需要两次IO
SELECT * FROM users WHERE id = 1; -- B+树查询 + 读取.MYD文件
```

---

## 存储引擎选择

### 选择InnoDB（推荐）

```sql
-- 场景1：需要事务
START TRANSACTION;
UPDATE account SET balance = balance - 100 WHERE id = 1;
UPDATE account SET balance = balance + 100 WHERE id = 2;
COMMIT;

-- 场景2：高并发写入
INSERT INTO orders (user_id, amount) VALUES (1, 100);
INSERT INTO orders (user_id, amount) VALUES (2, 200); -- 不阻塞

-- 场景3：外键约束
CREATE TABLE orders (
    id INT PRIMARY KEY,
    user_id INT,
    FOREIGN KEY (user_id) REFERENCES users(id)
);
```

### 选择MyISAM（极少数场景）

```sql
-- 场景1：只读日志表
CREATE TABLE access_log (
    id INT AUTO_INCREMENT PRIMARY KEY,
    ip VARCHAR(15),
    url VARCHAR(200),
    access_time TIMESTAMP
) ENGINE=MyISAM;

-- 场景2：临时统计表
CREATE TABLE stats_temp (
    date DATE,
    count INT
) ENGINE=MyISAM;
```

---

## 存储引擎转换

### 查看表引擎

```sql
-- 查看表信息
SHOW TABLE STATUS LIKE 'users'\G

-- 输出
*************************** 1. row ***************************
           Name: users
         Engine: InnoDB
        Version: 10
     Row_format: Dynamic
           Rows: 1000
 Avg_row_length: 100
    Data_length: 100000
Max_data_length: 0
   Index_length: 50000
      Data_free: 0
 Auto_increment: 1001
    Create_time: 2025-01-15 10:00:00
    Update_time: 2025-01-15 12:00:00
     Check_time: NULL
      Collation: utf8mb4_general_ci
       Checksum: NULL
 Create_options:
        Comment:
```

### 转换引擎

```sql
-- 方法1：ALTER TABLE（锁表，慢）
ALTER TABLE users ENGINE=InnoDB;

-- 方法2：导出导入（快）
# mysqldump -uroot -p test users > users.sql
# 修改users.sql中的ENGINE=MyISAM为ENGINE=InnoDB
# mysql -uroot -p test < users.sql

-- 方法3：创建新表（推荐）
CREATE TABLE users_new LIKE users;
ALTER TABLE users_new ENGINE=InnoDB;
INSERT INTO users_new SELECT * FROM users;
RENAME TABLE users TO users_old, users_new TO users;
```

---

## 实战建议

### 1. 默认使用InnoDB

```ini
# my.cnf
[mysqld]
default-storage-engine = InnoDB
```

### 2. 避免混用引擎

```sql
-- ❌ 不好：orders表用InnoDB，users表用MyISAM
-- 外键无法创建，事务一致性无法保障

-- ✅ 好：所有表都用InnoDB
```

### 3. MyISAM转InnoDB注意事项

```sql
-- 1. 检查是否有FULLTEXT索引
SHOW INDEX FROM users WHERE Index_type = 'FULLTEXT';

-- 2. 检查表大小（预估转换时间）
SELECT table_name, data_length/1024/1024 AS size_mb
FROM information_schema.TABLES
WHERE table_schema = 'test' AND table_name = 'users';

-- 3. 转换前备份
mysqldump -uroot -p test users > users_backup.sql
```

---

## 常见面试题

**Q1: InnoDB和MyISAM的主要区别？**
- InnoDB支持事务、行锁、外键、MVCC
- MyISAM不支持事务、表锁、COUNT(*)快

**Q2: 为什么InnoDB的COUNT(\*)慢？**
- MVCC机制，不同事务看到的行数可能不同，无法缓存

**Q3: 什么时候选择MyISAM？**
- 极少数场景：只读日志、临时统计表（但仍推荐InnoDB）

**Q4: 如何从MyISAM迁移到InnoDB？**
- ALTER TABLE（慢）、mysqldump导出导入、创建新表（推荐）

---

## 小结

✅ **InnoDB**：事务、行锁、MVCC，适合OLTP（推荐）
✅ **MyISAM**：无事务、表锁、COUNT(*)快，已很少使用
✅ **选择策略**：默认InnoDB，几乎所有场景都适用

**MySQL 5.5+默认InnoDB，MyISAM已成为历史。**

---

📚 **相关阅读**：
- 下一篇：《InnoDB存储结构：表空间、段、区、页》
- 推荐：《聚簇索引 vs 非聚簇索引》
