---
title: "数据库与表的创建：DDL基础"
date: 2025-11-21T11:30:00+08:00
draft: false
tags: ["MySQL", "DDL", "SQL", "基础入门"]
categories: ["技术"]
description: "掌握DDL语句，学会创建、修改、删除数据库和表，理解数据库对象的生命周期管理"
series: ["MySQL从入门到精通"]
weight: 4
stage: 1
stageTitle: "基础入门篇"
---

## 引言

### 提出问题

安装好MySQL后，你可能迫不及待想要存储数据。但是：

- **如何创建一个数据库？**
- 如何创建表来存储用户信息、订单数据？
- 表创建后发现字段设计不合理，如何修改？
- 如何删除不需要的表和数据库？
- DDL、DML、DQL这些术语是什么意思？

**这篇文章将带你掌握MySQL的"数据定义语言"，学会管理数据库对象的生命周期！**

### 为什么重要

DDL（Data Definition Language）是使用MySQL的**第一步**：

- ✅ 没有数据库和表，就无法存储数据
- ✅ 合理的表结构设计，是性能优化的基础
- ✅ 掌握ALTER语句，应对需求变更
- ✅ 了解DROP的风险，避免误删数据

---

## 基础概念

### SQL语言的分类

SQL（Structured Query Language，结构化查询语言）按功能分为四大类：

#### 1. DDL（Data Definition Language，数据定义语言）

**作用**：定义和管理数据库对象（数据库、表、索引、视图）

**核心语句**：
- `CREATE`：创建数据库对象
- `ALTER`：修改数据库对象
- `DROP`：删除数据库对象
- `TRUNCATE`：清空表数据
- `RENAME`：重命名对象

**本文重点讲解DDL！**

#### 2. DML（Data Manipulation Language，数据操作语言）

**作用**：操作表中的数据

**核心语句**：
- `INSERT`：插入数据
- `UPDATE`：更新数据
- `DELETE`：删除数据

（下一篇详细讲解）

#### 3. DQL（Data Query Language，数据查询语言）

**作用**：查询数据

**核心语句**：
- `SELECT`：查询数据

（SQL进阶篇详细讲解）

#### 4. DCL（Data Control Language，数据控制语言）

**作用**：管理用户权限

**核心语句**：
- `GRANT`：授予权限
- `REVOKE`：撤销权限

---

## 数据库操作

### 创建数据库（CREATE DATABASE）

#### 基础语法

```sql
CREATE DATABASE database_name;
```

#### 实战示例

```sql
-- 创建一个名为 mydb 的数据库
CREATE DATABASE mydb;

-- 执行结果
Query OK, 1 row affected (0.01 sec)
```

#### 指定字符集和校对规则

```sql
CREATE DATABASE mydb
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;
```

**参数说明**：
- `CHARACTER SET utf8mb4`：字符集，支持emoji和生僻字
- `COLLATE utf8mb4_unicode_ci`：校对规则，不区分大小写

#### 防止重复创建（推荐）

```sql
CREATE DATABASE IF NOT EXISTS mydb
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;
```

**IF NOT EXISTS**：如果数据库已存在，不会报错，直接跳过。

### 查看数据库

```sql
-- 查看所有数据库
SHOW DATABASES;

-- 输出示例：
+--------------------+
| Database           |
+--------------------+
| information_schema |
| mysql              |
| mydb               |
| performance_schema |
| sys                |
+--------------------+

-- 查看数据库创建语句
SHOW CREATE DATABASE mydb;

-- 输出示例：
+----------+------------------------------------------------------------------+
| Database | Create Database                                                  |
+----------+------------------------------------------------------------------+
| mydb     | CREATE DATABASE `mydb` /*!40100 DEFAULT CHARACTER SET utf8mb4 */ |
+----------+------------------------------------------------------------------+
```

### 选择数据库（USE）

```sql
-- 切换到 mydb 数据库
USE mydb;

-- 输出：
Database changed

-- 查看当前所在的数据库
SELECT DATABASE();

-- 输出：
+------------+
| DATABASE() |
+------------+
| mydb       |
+------------+
```

### 修改数据库

```sql
-- 修改字符集
ALTER DATABASE mydb CHARACTER SET utf8mb4;

-- 修改校对规则
ALTER DATABASE mydb COLLATE utf8mb4_general_ci;
```

### 删除数据库（谨慎！）

```sql
-- 删除数据库（危险操作！）
DROP DATABASE mydb;

-- 输出：
Query OK, 0 rows affected (0.05 sec)

-- 安全删除（如果存在才删除）
DROP DATABASE IF EXISTS mydb;
```

⚠️ **重要警告**：
- `DROP DATABASE` 会**永久删除**数据库及其所有表和数据
- 生产环境**必须先备份**再执行
- 建议使用 `IF EXISTS` 防止误删

---

## 表的创建（CREATE TABLE）

### 基础语法

```sql
CREATE TABLE table_name (
  column1 datatype constraints,
  column2 datatype constraints,
  ...
);
```

### 实战示例1：创建用户表

```sql
CREATE TABLE users (
  id INT,
  username VARCHAR(50),
  email VARCHAR(100),
  age INT,
  created_at TIMESTAMP
);

-- 执行结果
Query OK, 0 rows affected (0.03 sec)
```

### 查看表结构

```sql
-- 方式1：DESCRIBE（简写：DESC）
DESC users;

-- 输出：
+------------+--------------+------+-----+---------+-------+
| Field      | Type         | Null | Key | Default | Extra |
+------------+--------------+------+-----+---------+-------+
| id         | int          | YES  |     | NULL    |       |
| username   | varchar(50)  | YES  |     | NULL    |       |
| email      | varchar(100) | YES  |     | NULL    |       |
| age        | int          | YES  |     | NULL    |       |
| created_at | timestamp    | YES  |     | NULL    |       |
+------------+--------------+------+-----+---------+-------+

-- 方式2：SHOW CREATE TABLE
SHOW CREATE TABLE users\G

-- 输出：
*************************** 1. row ***************************
       Table: users
Create Table: CREATE TABLE `users` (
  `id` int DEFAULT NULL,
  `username` varchar(50) DEFAULT NULL,
  `email` varchar(100) DEFAULT NULL,
  `age` int DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
```

### 实战示例2：创建完整的用户表

```sql
CREATE TABLE users (
  id INT PRIMARY KEY AUTO_INCREMENT COMMENT '用户ID，自增主键',
  username VARCHAR(50) NOT NULL UNIQUE COMMENT '用户名，唯一',
  password VARCHAR(255) NOT NULL COMMENT '密码（加密存储）',
  email VARCHAR(100) NOT NULL UNIQUE COMMENT '邮箱，唯一',
  phone VARCHAR(20) COMMENT '手机号',
  age INT DEFAULT 0 COMMENT '年龄',
  status ENUM('active', 'inactive', 'banned') DEFAULT 'active' COMMENT '状态',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户表';
```

**关键要素解析**：

1. **PRIMARY KEY**：主键，唯一标识每一行
2. **AUTO_INCREMENT**：自增，插入数据时自动生成ID
3. **NOT NULL**：非空约束，字段不能为空
4. **UNIQUE**：唯一约束，字段值不能重复
5. **DEFAULT**：默认值
6. **COMMENT**：注释，便于理解
7. **ENGINE=InnoDB**：存储引擎，支持事务
8. **CHARSET=utf8mb4**：字符集

### 实战示例3：创建订单表

```sql
CREATE TABLE orders (
  id BIGINT PRIMARY KEY AUTO_INCREMENT COMMENT '订单ID',
  user_id INT NOT NULL COMMENT '用户ID',
  order_no VARCHAR(32) NOT NULL UNIQUE COMMENT '订单号',
  total_amount DECIMAL(10, 2) NOT NULL COMMENT '订单总金额',
  status TINYINT DEFAULT 0 COMMENT '订单状态：0待支付 1已支付 2已取消',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  paid_at TIMESTAMP NULL COMMENT '支付时间',
  INDEX idx_user_id (user_id),
  INDEX idx_order_no (order_no),
  INDEX idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单表';
```

**新增要素**：

- **BIGINT**：大整数，适合订单ID（数据量大）
- **DECIMAL(10, 2)**：精确小数，适合金额（10位数字，2位小数）
- **TINYINT**：小整数，适合状态码（-128~127）
- **INDEX**：索引，加速查询

### 查看所有表

```sql
-- 查看当前数据库的所有表
SHOW TABLES;

-- 输出：
+----------------+
| Tables_in_mydb |
+----------------+
| orders         |
| users          |
+----------------+
```

---

## 表的修改（ALTER TABLE）

### 添加列（ADD COLUMN）

```sql
-- 添加单列
ALTER TABLE users ADD COLUMN gender ENUM('male', 'female', 'other') DEFAULT 'other';

-- 添加多列
ALTER TABLE users
  ADD COLUMN nickname VARCHAR(50) COMMENT '昵称',
  ADD COLUMN avatar VARCHAR(255) COMMENT '头像URL';

-- 在指定位置添加列
ALTER TABLE users ADD COLUMN birth_date DATE AFTER age;

-- 在第一列添加
ALTER TABLE users ADD COLUMN user_code VARCHAR(20) FIRST;
```

### 修改列（MODIFY COLUMN）

```sql
-- 修改列的数据类型
ALTER TABLE users MODIFY COLUMN age TINYINT;

-- 修改列的数据类型和约束
ALTER TABLE users MODIFY COLUMN username VARCHAR(100) NOT NULL;
```

### 修改列名（CHANGE COLUMN）

```sql
-- 修改列名（同时可以修改数据类型）
ALTER TABLE users CHANGE COLUMN username user_name VARCHAR(50) NOT NULL;
```

**CHANGE vs MODIFY**：
- `CHANGE`：可以改列名 + 数据类型
- `MODIFY`：只能改数据类型

### 删除列（DROP COLUMN）

```sql
-- 删除单列
ALTER TABLE users DROP COLUMN user_code;

-- 删除多列
ALTER TABLE users
  DROP COLUMN nickname,
  DROP COLUMN avatar;
```

### 修改表名（RENAME TABLE）

```sql
-- 方式1：ALTER TABLE
ALTER TABLE users RENAME TO user_info;

-- 方式2：RENAME TABLE
RENAME TABLE user_info TO users;
```

### 修改表的字符集

```sql
ALTER TABLE users CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```

### 修改表的存储引擎

```sql
ALTER TABLE users ENGINE = MyISAM;  -- 不推荐，InnoDB更好
```

---

## 表的删除

### 删除表（DROP TABLE）

```sql
-- 删除表（永久删除！）
DROP TABLE users;

-- 安全删除（如果存在才删除）
DROP TABLE IF EXISTS users;

-- 删除多张表
DROP TABLE IF EXISTS users, orders, products;
```

⚠️ **警告**：`DROP TABLE` 会永久删除表及其所有数据，无法恢复！

### 清空表数据（TRUNCATE TABLE）

```sql
-- 清空表数据，保留表结构
TRUNCATE TABLE users;
```

**TRUNCATE vs DELETE**：

| 特性 | TRUNCATE | DELETE |
|-----|----------|--------|
| **速度** | 非常快（直接删除数据文件） | 较慢（逐行删除） |
| **事务** | 不可回滚（DDL操作） | 可回滚（DML操作） |
| **自增ID** | 重置为初始值 | 不重置 |
| **触发器** | 不触发 | 触发DELETE触发器 |
| **WHERE条件** | 不支持 | 支持 |

**使用场景**：
- `TRUNCATE`：清空测试数据、重置表
- `DELETE`：删除部分数据、需要回滚

---

## 实战案例：电商数据库设计

### 需求分析

设计一个简单的电商系统，需要以下表：
1. 用户表（users）
2. 商品表（products）
3. 订单表（orders）
4. 订单详情表（order_items）

### 创建数据库

```sql
-- 创建数据库
CREATE DATABASE IF NOT EXISTS ecommerce
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

-- 使用数据库
USE ecommerce;
```

### 创建用户表

```sql
CREATE TABLE users (
  id INT PRIMARY KEY AUTO_INCREMENT,
  username VARCHAR(50) NOT NULL UNIQUE,
  password VARCHAR(255) NOT NULL,
  email VARCHAR(100) NOT NULL UNIQUE,
  phone VARCHAR(20),
  balance DECIMAL(10, 2) DEFAULT 0.00 COMMENT '账户余额',
  status TINYINT DEFAULT 1 COMMENT '状态：1正常 0禁用',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_username (username),
  INDEX idx_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户表';
```

### 创建商品表

```sql
CREATE TABLE products (
  id INT PRIMARY KEY AUTO_INCREMENT,
  name VARCHAR(200) NOT NULL COMMENT '商品名称',
  price DECIMAL(10, 2) NOT NULL COMMENT '商品价格',
  stock INT NOT NULL DEFAULT 0 COMMENT '库存数量',
  description TEXT COMMENT '商品描述',
  category VARCHAR(50) COMMENT '商品分类',
  image_url VARCHAR(255) COMMENT '商品图片',
  status TINYINT DEFAULT 1 COMMENT '状态：1上架 0下架',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_name (name),
  INDEX idx_category (category),
  INDEX idx_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='商品表';
```

### 创建订单表

```sql
CREATE TABLE orders (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  user_id INT NOT NULL COMMENT '用户ID',
  order_no VARCHAR(32) NOT NULL UNIQUE COMMENT '订单号',
  total_amount DECIMAL(10, 2) NOT NULL COMMENT '订单总金额',
  status TINYINT DEFAULT 0 COMMENT '0待支付 1已支付 2已发货 3已完成 4已取消',
  payment_method VARCHAR(20) COMMENT '支付方式',
  shipping_address TEXT COMMENT '收货地址',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  paid_at TIMESTAMP NULL COMMENT '支付时间',
  shipped_at TIMESTAMP NULL COMMENT '发货时间',
  completed_at TIMESTAMP NULL COMMENT '完成时间',
  INDEX idx_user_id (user_id),
  INDEX idx_order_no (order_no),
  INDEX idx_status (status),
  INDEX idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单表';
```

### 创建订单详情表

```sql
CREATE TABLE order_items (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  order_id BIGINT NOT NULL COMMENT '订单ID',
  product_id INT NOT NULL COMMENT '商品ID',
  product_name VARCHAR(200) NOT NULL COMMENT '商品名称（冗余存储）',
  price DECIMAL(10, 2) NOT NULL COMMENT '商品单价',
  quantity INT NOT NULL COMMENT '购买数量',
  subtotal DECIMAL(10, 2) NOT NULL COMMENT '小计金额',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_order_id (order_id),
  INDEX idx_product_id (product_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单详情表';
```

### 查看创建结果

```sql
-- 查看所有表
SHOW TABLES;

-- 输出：
+---------------------+
| Tables_in_ecommerce |
+---------------------+
| order_items         |
| orders              |
| products            |
| users               |
+---------------------+

-- 查看表结构
DESC users;
DESC products;
DESC orders;
DESC order_items;
```

---

## 最佳实践

### 数据库命名规范

1. **使用小写字母**：MySQL在Linux下区分大小写
   - ✅ `user_info`
   - ❌ `UserInfo`

2. **使用下划线分隔**：
   - ✅ `order_items`
   - ❌ `orderItems`

3. **避免保留字**：
   - ❌ `order`、`group`、`select`
   - ✅ `orders`、`user_group`

4. **名称要有意义**：
   - ✅ `users`、`products`
   - ❌ `table1`、`t1`

### 表设计规范

1. **每张表必须有主键**：
```sql
id INT PRIMARY KEY AUTO_INCREMENT
```

2. **使用合适的数据类型**：
   - 金额：`DECIMAL(10, 2)`
   - 状态码：`TINYINT`
   - 日期时间：`TIMESTAMP`
   - 文本：`VARCHAR`（有长度限制）、`TEXT`（无限制）

3. **添加索引加速查询**：
```sql
INDEX idx_user_id (user_id)
```

4. **添加注释**：
```sql
COMMENT '用户表'
```

5. **使用InnoDB存储引擎**：
```sql
ENGINE=InnoDB
```

6. **使用utf8mb4字符集**：
```sql
DEFAULT CHARSET=utf8mb4
```

### 修改表的注意事项

1. **ALTER TABLE会锁表**：
   - 生产环境修改表结构时，会阻塞读写操作
   - 建议在业务低峰期执行

2. **大表修改需谨慎**：
   - 百万级数据的表，ALTER可能需要几分钟到几小时
   - 建议使用在线DDL工具（如pt-online-schema-change）

3. **备份后再操作**：
```bash
mysqldump -u root -p mydb > backup.sql
```

### 常见误区

**误区1：过度使用VARCHAR(255)**
- ❌ 所有字符串都用 `VARCHAR(255)`
- ✅ 根据实际需求设置长度
  - 用户名：`VARCHAR(50)`
  - 邮箱：`VARCHAR(100)`
  - 描述：`TEXT`

**误区2：不加主键**
- ❌ 没有主键的表，性能很差
- ✅ 每张表必须有主键

**误区3：滥用TEXT类型**
- ❌ 所有长文本都用TEXT
- ✅ 能用VARCHAR就用VARCHAR
  - TEXT无法创建索引（全文索引除外）
  - TEXT查询性能较差

---

## 常见问题（FAQ）

**Q1：创建表时报错"Table already exists"？**

A：表已存在，使用 `IF NOT EXISTS`：
```sql
CREATE TABLE IF NOT EXISTS users (...);
```

**Q2：修改表时报错"Column not found"？**

A：列名拼写错误，检查列名：
```sql
DESC users;  -- 查看所有列名
```

**Q3：删除数据库时报错"Can't drop database"？**

A：数据库正在被使用，先切换到其他数据库：
```sql
USE mysql;
DROP DATABASE mydb;
```

**Q4：如何查看当前数据库的所有表？**

A：
```sql
SHOW TABLES;
```

**Q5：如何复制表结构？**

A：
```sql
-- 复制表结构（不包含数据）
CREATE TABLE users_copy LIKE users;

-- 复制表结构和数据
CREATE TABLE users_copy AS SELECT * FROM users;
```

---

## 总结

### 核心要点

1. **DDL语句**：
   - `CREATE`：创建数据库、表
   - `ALTER`：修改表结构
   - `DROP`：删除数据库、表
   - `TRUNCATE`：清空表数据

2. **数据库操作**：
   - 创建：`CREATE DATABASE mydb`
   - 选择：`USE mydb`
   - 删除：`DROP DATABASE mydb`

3. **表操作**：
   - 创建：`CREATE TABLE users (...)`
   - 查看：`DESC users` 或 `SHOW CREATE TABLE users`
   - 修改：`ALTER TABLE users ADD/MODIFY/DROP COLUMN`
   - 删除：`DROP TABLE users`

4. **设计规范**：
   - 必须有主键
   - 使用合适的数据类型
   - 添加索引
   - 添加注释
   - 使用InnoDB和utf8mb4

### 记忆口诀

**DDL三大操作：CREATE、ALTER、DROP**
- **CREATE**：创建对象（数据库、表）
- **ALTER**：修改表结构（加列、改列、删列）
- **DROP**：删除对象（谨慎使用！）

### 实践建议

1. **动手练习**：
   - 创建一个数据库
   - 创建几张表（用户、商品、订单）
   - 练习修改表结构
   - 练习删除表

2. **参考示例**：
   - 本文的电商数据库设计
   - MySQL官方示例数据库（sakila、employees）

3. **避免误删**：
   - 使用 `IF EXISTS`
   - 生产环境先备份
   - 谨慎使用 `DROP`

### 下一步学习

- **前置知识**：上一篇《MySQL安装与环境配置》
- **后续推荐**：下一篇《数据类型详解：选择合适的数据类型》
- **实战项目**：尝试设计一个博客系统的数据库（用户、文章、评论、标签）

---

## 参考资料

1. [MySQL官方文档 - DDL语句](https://dev.mysql.com/doc/refman/8.0/en/sql-data-definition-statements.html)
2. [MySQL官方文档 - CREATE TABLE](https://dev.mysql.com/doc/refman/8.0/en/create-table.html)
3. [MySQL官方文档 - ALTER TABLE](https://dev.mysql.com/doc/refman/8.0/en/alter-table.html)
4. 《MySQL技术内幕：InnoDB存储引擎》 - 姜承尧

---

**系列文章导航**：
- 上一篇：《MySQL安装与环境配置》
- 下一篇：《数据类型详解：选择合适的数据类型》
- 返回目录：[MySQL从入门到精通](/mysql/)

---

> 💡 **提示**：本文是 "MySQL从入门到精通" 系列的第 4 篇（共86篇），从第一性原理出发，系统化掌握MySQL。
>
> 📚 **学习建议**：建议动手创建一个完整的数据库，包含3-5张表，熟悉DDL操作。
>
> 🤝 **交流讨论**：如有问题或建议，欢迎在评论区留言交流。
