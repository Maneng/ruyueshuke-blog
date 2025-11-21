---
title: "基础增删改查：DML操作入门"
date: 2025-11-20T12:30:00+08:00
draft: false
tags: ["MySQL", "DML", "CRUD", "基础入门"]
categories: ["技术"]
description: "掌握INSERT、UPDATE、DELETE、SELECT基础操作，学会对数据进行增删改查"
series: ["MySQL从入门到精通"]
weight: 6
stage: 1
stageTitle: "基础入门篇"
---

## 引言

### 提出问题

前面几篇我们学会了创建数据库和表，但表只是一个空壳，现在要学习：

- **如何往表里插入数据？**（INSERT）
- 如何修改已有的数据？（UPDATE）
- 如何删除不需要的数据？（DELETE）
- 如何查询数据？（SELECT）
- 批量插入和批量更新如何操作？

**这就是CRUD操作（Create增、Read读、Update改、Delete删），是使用数据库的核心！**

---

## DML语句概述

**DML（Data Manipulation Language，数据操作语言）**：操作表中的数据

| 操作 | 语句 | 作用 | 对应CRUD |
|-----|------|------|----------|
| **插入** | INSERT | 向表中添加新数据 | Create |
| **查询** | SELECT | 从表中读取数据 | Read |
| **更新** | UPDATE | 修改表中已有数据 | Update |
| **删除** | DELETE | 从表中删除数据 | Delete |

---

## INSERT：插入数据

### 基础语法

```sql
INSERT INTO table_name (column1, column2, ...) VALUES (value1, value2, ...);
```

### 实战准备：创建测试表

```sql
CREATE TABLE users (
  id INT PRIMARY KEY AUTO_INCREMENT,
  username VARCHAR(50) NOT NULL,
  email VARCHAR(100) NOT NULL,
  age INT,
  status TINYINT DEFAULT 1,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### 插入单行数据

```sql
-- 方式1：指定列名（推荐）
INSERT INTO users (username, email, age)
VALUES ('zhangsan', 'zhangsan@example.com', 25);

-- 方式2：不指定列名（必须提供所有列的值，按顺序）
INSERT INTO users
VALUES (NULL, 'lisi', 'lisi@example.com', 30, 1, CURRENT_TIMESTAMP);
-- NULL：让AUTO_INCREMENT自动生成ID
-- CURRENT_TIMESTAMP：当前时间
```

**推荐使用方式1**，因为：
- ✅ 可读性好
- ✅ 不受表结构变化影响
- ✅ 可以省略有默认值的列

### 插入多行数据（推荐）

```sql
-- 批量插入（性能更好）
INSERT INTO users (username, email, age) VALUES
  ('wangwu', 'wangwu@example.com', 28),
  ('zhaoliu', 'zhaoliu@example.com', 22),
  ('sunqi', 'sunqi@example.com', 35);

-- 执行结果：
Query OK, 3 rows affected (0.01 sec)
Records: 3  Duplicates: 0  Warnings: 0
```

**性能对比**：
- 单条插入3次：3次网络IO + 3次磁盘IO
- 批量插入1次：1次网络IO + 1次磁盘IO（快10倍以上！）

### INSERT IGNORE（忽略重复）

```sql
-- 普通INSERT：遇到重复键会报错
INSERT INTO users (username, email, age)
VALUES ('zhangsan', 'zhangsan@example.com', 25);
-- ERROR 1062: Duplicate entry 'zhangsan@example.com' for key 'email'

-- INSERT IGNORE：遇到重复键会跳过，不报错
INSERT IGNORE INTO users (username, email, age)
VALUES ('zhangsan', 'zhangsan@example.com', 25);
-- Query OK, 0 rows affected（没有插入，但不报错）
```

### REPLACE INTO（替换插入）

```sql
-- 如果存在相同的主键或唯一键，先删除旧数据，再插入新数据
REPLACE INTO users (id, username, email, age)
VALUES (1, 'zhangsan_new', 'zhangsan@example.com', 26);

-- 等价于：
-- DELETE FROM users WHERE id = 1;
-- INSERT INTO users VALUES (1, 'zhangsan_new', 'zhangsan@example.com', 26);
```

⚠️ **注意**：REPLACE会删除旧记录，其他列的值会丢失！

### ON DUPLICATE KEY UPDATE（推荐）

```sql
-- 如果存在重复键，执行UPDATE而不是INSERT
INSERT INTO users (id, username, email, age)
VALUES (1, 'zhangsan', 'zhangsan@example.com', 26)
ON DUPLICATE KEY UPDATE age = 26;

-- 如果id=1存在，执行：UPDATE users SET age=26 WHERE id=1
-- 如果id=1不存在，执行：INSERT INTO users VALUES (1, 'zhangsan', ...)
```

**使用场景**：计数器、统计表

```sql
-- 每日UV统计
INSERT INTO daily_stats (date, uv)
VALUES ('2024-01-15', 1)
ON DUPLICATE KEY UPDATE uv = uv + 1;
```

---

## SELECT：查询数据

### 基础查询

```sql
-- 查询所有列
SELECT * FROM users;

-- 查询指定列（推荐，节省带宽）
SELECT id, username, email FROM users;

-- 查询并起别名
SELECT
  id AS user_id,
  username AS name,
  email
FROM users;
```

### WHERE条件查询

```sql
-- 等值查询
SELECT * FROM users WHERE id = 1;

-- 范围查询
SELECT * FROM users WHERE age > 25;
SELECT * FROM users WHERE age BETWEEN 20 AND 30;

-- 多个条件（AND）
SELECT * FROM users WHERE age > 25 AND status = 1;

-- 多个条件（OR）
SELECT * FROM users WHERE age < 20 OR age > 60;

-- IN查询
SELECT * FROM users WHERE id IN (1, 2, 3);

-- 模糊查询
SELECT * FROM users WHERE username LIKE 'zhang%';  -- zhang开头
SELECT * FROM users WHERE email LIKE '%@gmail.com';  -- @gmail.com结尾
```

### ORDER BY排序

```sql
-- 升序（默认）
SELECT * FROM users ORDER BY age ASC;

-- 降序
SELECT * FROM users ORDER BY age DESC;

-- 多字段排序
SELECT * FROM users ORDER BY age DESC, created_at DESC;
```

### LIMIT分页

```sql
-- 查询前10条
SELECT * FROM users LIMIT 10;

-- 分页查询（第1页，每页10条）
SELECT * FROM users LIMIT 0, 10;

-- 分页查询（第2页，每页10条）
SELECT * FROM users LIMIT 10, 10;

-- 分页查询（第3页，每页10条）
SELECT * FROM users LIMIT 20, 10;

-- 公式：LIMIT (page-1)*pageSize, pageSize
```

### DISTINCT去重

```sql
-- 查询所有不重复的年龄
SELECT DISTINCT age FROM users;

-- 多列去重（组合唯一）
SELECT DISTINCT age, status FROM users;
```

---

## UPDATE：更新数据

### 基础语法

```sql
UPDATE table_name SET column1 = value1, column2 = value2 WHERE condition;
```

⚠️ **重要警告**：**UPDATE必须加WHERE条件**，否则会更新所有行！

### 更新单列

```sql
-- 更新id=1的用户年龄
UPDATE users SET age = 26 WHERE id = 1;

-- 执行结果：
Query OK, 1 row affected (0.01 sec)
Rows matched: 1  Changed: 1  Warnings: 0
```

### 更新多列

```sql
-- 同时更新多个字段
UPDATE users
SET
  age = 27,
  email = 'zhangsan_new@example.com',
  status = 0
WHERE id = 1;
```

### 基于计算更新

```sql
-- 年龄+1
UPDATE users SET age = age + 1 WHERE id = 1;

-- 批量涨价10%
UPDATE products SET price = price * 1.1;

-- 库存-1（下单扣减库存）
UPDATE products SET stock = stock - 1 WHERE id = 100 AND stock > 0;
```

### 基于查询更新

```sql
-- 将username设置为邮箱的@前面部分
UPDATE users
SET username = SUBSTRING_INDEX(email, '@', 1)
WHERE id = 1;

-- 将所有25岁以上的用户状态设为VIP
UPDATE users SET status = 2 WHERE age >= 25;
```

### 更新多张表（多表关联更新）

```sql
-- 将用户表的积分同步到用户详情表
UPDATE users u
JOIN user_details d ON u.id = d.user_id
SET d.total_score = u.score;
```

---

## DELETE：删除数据

### 基础语法

```sql
DELETE FROM table_name WHERE condition;
```

⚠️ **重要警告**：**DELETE必须加WHERE条件**，否则会删除所有行！

### 删除单行

```sql
-- 删除id=1的用户
DELETE FROM users WHERE id = 1;

-- 执行结果：
Query OK, 1 row affected (0.01 sec)
```

### 删除多行

```sql
-- 删除所有状态为0的用户
DELETE FROM users WHERE status = 0;

-- 删除年龄小于18岁的用户
DELETE FROM users WHERE age < 18;

-- 删除多个ID的用户
DELETE FROM users WHERE id IN (1, 2, 3);
```

### DELETE vs TRUNCATE

| 特性 | DELETE | TRUNCATE |
|-----|--------|----------|
| **速度** | 慢（逐行删除） | 快（直接删除数据文件） |
| **WHERE条件** | 支持 | 不支持 |
| **事务回滚** | 可以 | 不可以（DDL操作） |
| **自增ID** | 不重置 | 重置为初始值 |
| **触发器** | 触发 | 不触发 |

```sql
-- DELETE：删除所有数据，但自增ID不重置
DELETE FROM users;
INSERT INTO users (username, email) VALUES ('test', 'test@example.com');
-- 新插入的id会从上次的ID继续（如10001）

-- TRUNCATE：删除所有数据，自增ID重置
TRUNCATE TABLE users;
INSERT INTO users (username, email) VALUES ('test', 'test@example.com');
-- 新插入的id从1开始
```

---

## 实战案例：用户管理系统

### 需求

实现一个简单的用户管理系统，支持：
1. 用户注册（插入）
2. 用户登录（查询）
3. 修改用户信息（更新）
4. 删除用户（删除）

### 1. 创建用户表

```sql
CREATE TABLE users (
  id INT PRIMARY KEY AUTO_INCREMENT,
  username VARCHAR(50) NOT NULL UNIQUE,
  password VARCHAR(255) NOT NULL,
  email VARCHAR(100) NOT NULL UNIQUE,
  phone VARCHAR(20),
  nickname VARCHAR(50),
  avatar VARCHAR(255),
  status TINYINT DEFAULT 1 COMMENT '1正常 0禁用',
  login_count INT DEFAULT 0 COMMENT '登录次数',
  last_login_at TIMESTAMP NULL COMMENT '最后登录时间',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户表';
```

### 2. 用户注册

```sql
-- 注册新用户
INSERT INTO users (username, password, email, phone)
VALUES ('zhangsan', SHA2('password123', 256), 'zhangsan@example.com', '13800138000');

-- 检查用户名是否已存在（应用层先查询）
SELECT COUNT(*) FROM users WHERE username = 'zhangsan';
-- 如果结果>0，说明用户名已存在
```

### 3. 用户登录

```sql
-- 验证用户名和密码
SELECT id, username, email, nickname, status
FROM users
WHERE username = 'zhangsan'
  AND password = SHA2('password123', 256)
  AND status = 1;

-- 如果查询到记录，登录成功

-- 登录成功后，更新登录次数和最后登录时间
UPDATE users
SET
  login_count = login_count + 1,
  last_login_at = CURRENT_TIMESTAMP
WHERE id = 1;
```

### 4. 查询用户列表（带分页）

```sql
-- 查询所有用户（第1页，每页10条）
SELECT id, username, email, nickname, status, created_at
FROM users
WHERE status = 1
ORDER BY id DESC
LIMIT 0, 10;

-- 统计总用户数
SELECT COUNT(*) AS total FROM users WHERE status = 1;
```

### 5. 修改用户信息

```sql
-- 修改昵称和头像
UPDATE users
SET
  nickname = '张三',
  avatar = 'https://example.com/avatars/zhangsan.jpg'
WHERE id = 1;

-- 修改密码
UPDATE users
SET password = SHA2('new_password456', 256)
WHERE id = 1
  AND password = SHA2('password123', 256);  -- 验证旧密码
```

### 6. 禁用用户（软删除）

```sql
-- 软删除：将status设为0（推荐）
UPDATE users SET status = 0 WHERE id = 1;

-- 硬删除：直接删除记录（不推荐，数据无法恢复）
DELETE FROM users WHERE id = 1;
```

**软删除 vs 硬删除**：

| 方式 | 优点 | 缺点 |
|-----|------|------|
| **软删除** | 可恢复、保留历史记录 | 数据库会越来越大 |
| **硬删除** | 节省空间 | 无法恢复、丢失关联数据 |

**推荐**：用户数据用软删除，测试数据用硬删除。

---

## 最佳实践

### INSERT最佳实践

1. **批量插入代替单条插入**：
```sql
-- ❌ 不推荐：单条插入
INSERT INTO users (username, email) VALUES ('user1', 'user1@example.com');
INSERT INTO users (username, email) VALUES ('user2', 'user2@example.com');
INSERT INTO users (username, email) VALUES ('user3', 'user3@example.com');

-- ✅ 推荐：批量插入
INSERT INTO users (username, email) VALUES
  ('user1', 'user1@example.com'),
  ('user2', 'user2@example.com'),
  ('user3', 'user3@example.com');
```

2. **明确指定列名**：
```sql
-- ❌ 不推荐
INSERT INTO users VALUES (NULL, 'test', 'test@example.com', ...);

-- ✅ 推荐
INSERT INTO users (username, email) VALUES ('test', 'test@example.com');
```

3. **使用事务保证一致性**（后续章节详解）：
```sql
START TRANSACTION;
INSERT INTO users (username, email) VALUES ('user1', 'user1@example.com');
INSERT INTO user_logs (user_id, action) VALUES (LAST_INSERT_ID(), 'register');
COMMIT;
```

### UPDATE最佳实践

1. **必须加WHERE条件**：
```sql
-- ❌ 危险：会更新所有行！
UPDATE users SET age = 30;

-- ✅ 安全：只更新指定行
UPDATE users SET age = 30 WHERE id = 1;
```

2. **先SELECT后UPDATE**：
```sql
-- 第一步：查询要更新的记录
SELECT * FROM users WHERE id = 1;

-- 第二步：确认无误后执行UPDATE
UPDATE users SET age = 30 WHERE id = 1;
```

3. **使用LIMIT限制更新行数**：
```sql
-- 只更新前100条
UPDATE users SET status = 0 WHERE age < 18 LIMIT 100;
```

### DELETE最佳实践

1. **优先使用软删除**：
```sql
-- ✅ 推荐：软删除
UPDATE users SET status = 0, deleted_at = CURRENT_TIMESTAMP WHERE id = 1;

-- ❌ 不推荐：硬删除（除非确定不再需要）
DELETE FROM users WHERE id = 1;
```

2. **删除前先备份**：
```sql
-- 第一步：备份要删除的数据
CREATE TABLE users_backup AS
SELECT * FROM users WHERE id IN (1, 2, 3);

-- 第二步：执行删除
DELETE FROM users WHERE id IN (1, 2, 3);
```

3. **使用LIMIT防止误删**：
```sql
-- 删除前先查询
SELECT COUNT(*) FROM users WHERE status = 0;
-- 假设结果是5条

-- 使用LIMIT防止误删
DELETE FROM users WHERE status = 0 LIMIT 5;
```

### SELECT最佳实践

1. **避免SELECT ***：
```sql
-- ❌ 不推荐：查询所有列
SELECT * FROM users;

-- ✅ 推荐：只查询需要的列
SELECT id, username, email FROM users;
```

2. **加索引提升查询速度**：
```sql
-- 为常用查询字段创建索引
CREATE INDEX idx_username ON users(username);
CREATE INDEX idx_email ON users(email);
```

3. **使用LIMIT限制结果集**：
```sql
-- ✅ 推荐：限制返回行数
SELECT * FROM users ORDER BY id DESC LIMIT 100;
```

---

## 常见问题（FAQ）

**Q1：INSERT报错"Duplicate entry"？**

A：主键或唯一键重复，使用`INSERT IGNORE`或`ON DUPLICATE KEY UPDATE`。

**Q2：UPDATE没有生效？**

A：检查WHERE条件是否正确，执行前先SELECT查询。

**Q3：DELETE误删数据如何恢复？**

A：
- 如果有备份：从备份恢复
- 如果开启了binlog：从binlog恢复
- 如果都没有：**无法恢复**（所以强调软删除）

**Q4：如何获取INSERT后的自增ID？**

A：
```sql
INSERT INTO users (username, email) VALUES ('test', 'test@example.com');
SELECT LAST_INSERT_ID();  -- 返回刚插入的ID
```

**Q5：如何批量更新不同的值？**

A：
```sql
-- 使用CASE WHEN
UPDATE users
SET age = CASE id
  WHEN 1 THEN 25
  WHEN 2 THEN 30
  WHEN 3 THEN 28
END
WHERE id IN (1, 2, 3);
```

---

## 总结

### 核心要点

1. **INSERT（插入）**：
   - 批量插入比单条插入快10倍+
   - 使用`ON DUPLICATE KEY UPDATE`处理重复键

2. **SELECT（查询）**：
   - 避免`SELECT *`
   - 使用WHERE筛选数据
   - 使用ORDER BY排序
   - 使用LIMIT分页

3. **UPDATE（更新）**：
   - **必须加WHERE条件**
   - 先SELECT后UPDATE
   - 可以基于计算更新

4. **DELETE（删除）**：
   - **必须加WHERE条件**
   - 优先使用软删除
   - 删除前先备份

### 记忆口诀

**CRUD四大操作：增查改删**
- **增**：INSERT INTO ... VALUES ...
- **查**：SELECT ... FROM ... WHERE ...
- **改**：UPDATE ... SET ... WHERE ...（必须加WHERE！）
- **删**：DELETE FROM ... WHERE ...（必须加WHERE！）

### 实践建议

1. **动手练习**：
   - 创建用户表
   - 插入10条测试数据
   - 练习各种查询、更新、删除

2. **养成好习惯**：
   - UPDATE和DELETE前先SELECT
   - 批量操作使用事务
   - 重要数据使用软删除

3. **性能优化**：
   - 批量插入代替单条插入
   - 为常用查询字段创建索引
   - 避免全表扫描

### 下一步学习

- **前置知识**：上一篇《数据类型详解：选择合适的数据类型》
- **后续推荐**：下一篇《约束与完整性：主键外键唯一非空》
- **实战项目**：实现一个完整的CRUD功能（用户管理、商品管理）

---

## 参考资料

1. [MySQL官方文档 - DML语句](https://dev.mysql.com/doc/refman/8.0/en/sql-data-manipulation-statements.html)
2. [MySQL官方文档 - INSERT](https://dev.mysql.com/doc/refman/8.0/en/insert.html)
3. [MySQL官方文档 - SELECT](https://dev.mysql.com/doc/refman/8.0/en/select.html)
4. [MySQL官方文档 - UPDATE](https://dev.mysql.com/doc/refman/8.0/en/update.html)

---

**系列文章导航**：
- 上一篇：《数据类型详解：选择合适的数据类型》
- 下一篇：《约束与完整性：主键外键唯一非空》
- 返回目录：[MySQL从入门到精通](/mysql/)

---

> 💡 **提示**：本文是 "MySQL从入门到精通" 系列的第 6 篇（共86篇），从第一性原理出发，系统化掌握MySQL。
>
> 📚 **学习建议**：建议动手练习每一个SQL语句，熟能生巧！
>
> 🤝 **交流讨论**：如有问题或建议，欢迎在评论区留言交流。
