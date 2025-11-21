---
title: "执行引擎：SQL执行的最后一步"
date: 2025-01-15T19:00:00+08:00
draft: false
tags: ["MySQL", "执行引擎", "存储引擎接口", "SQL执行"]
categories: ["数据库"]
description: "深入理解MySQL执行引擎的工作原理，掌握执行引擎与存储引擎的交互机制"
series: ["MySQL从入门到精通"]
weight: 55
stage: 5
stageTitle: "架构原理篇"
---

## 执行引擎概述

**执行引擎（Executor）** 负责调用存储引擎接口，执行SQL，返回结果。

```
SQL执行完整流程：
┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
│ 连接器     │→│ 分析器     │→│ 优化器     │→│ 执行器     │
└──────────┘  └──────────┘  └──────────┘  └──────────┘
                                             ↓ 调用接口
                                        ┌──────────┐
                                        │ 存储引擎  │
                                        └──────────┘
```

---

## 执行引擎的职责

### 1. 权限检查

```sql
-- 查询前检查权限
SELECT * FROM users WHERE id = 1;

-- 检查流程
1. 当前用户是否有users表的SELECT权限？
2. 如果没有 → 返回错误：Access denied

-- 权限存储位置
mysql.user        -- 全局权限
mysql.db          -- 数据库权限
mysql.tables_priv -- 表权限
```

### 2. 调用存储引擎接口

```sql
-- 示例SQL
SELECT * FROM users WHERE id = 1;

-- 执行引擎操作
1. 打开表：handler = open_table("users")
2. 初始化查询：handler->index_init(id索引)
3. 定位第一行：handler->index_read(id=1)
4. 读取行数据：handler->read_row()
5. 关闭表：handler->close()
```

### 3. 结果返回

```sql
-- 返回流程
1. 存储引擎返回数据行
2. 执行引擎应用WHERE条件过滤
3. 格式化结果（MySQL协议）
4. 通过网络发送给客户端

-- 流式返回（Streaming）
-- MySQL边查询边返回，不等全部数据查完
```

---

## 存储引擎接口（Handler API）

### 1. 打开表

```c
// C代码示例（简化）
int handler::ha_open(TABLE *table, const char *name, int mode);

// 流程
1. 打开表文件（.ibd）
2. 加载表结构（.frm，MySQL 8.0已废弃）
3. 初始化Handler对象
```

### 2. 读取接口

```c
// 全表扫描
int handler::rnd_init();         // 初始化全表扫描
int handler::rnd_next(uchar *buf); // 读取下一行

// 索引扫描
int handler::index_init(uint idx);           // 初始化索引扫描
int handler::index_read(uchar *buf, const uchar *key, uint key_len);  // 定位第一行
int handler::index_next(uchar *buf);         // 读取下一行
```

### 3. 写入接口

```c
// 插入
int handler::write_row(uchar *buf);

// 更新
int handler::update_row(const uchar *old_data, const uchar *new_data);

// 删除
int handler::delete_row(const uchar *buf);
```

---

## 执行流程详解

### 1. 全表扫描

```sql
-- SQL
SELECT * FROM users WHERE age > 25;

-- 执行流程
1. 打开表：open_table("users")
2. 初始化全表扫描：rnd_init()
3. 循环读取
   WHILE (rnd_next(row) == 0) DO
       IF age > 25 THEN
           发送到客户端
       END IF
   END WHILE
4. 关闭表：close()

-- 扫描行数：全表所有行
```

### 2. 索引扫描

```sql
-- SQL
SELECT * FROM users WHERE id = 1;

-- 执行流程（主键索引）
1. 打开表：open_table("users")
2. 初始化索引扫描：index_init(PRIMARY)
3. 定位第一行：index_read(id=1)
4. 读取行数据：read_row()
5. 发送到客户端
6. 关闭表：close()

-- 扫描行数：1行（主键等值查询）
```

### 3. 索引范围扫描

```sql
-- SQL
SELECT * FROM users WHERE id BETWEEN 1 AND 100;

-- 执行流程
1. 打开表：open_table("users")
2. 初始化索引扫描：index_init(PRIMARY)
3. 定位第一行：index_read(id=1)
4. 循环读取
   WHILE (index_next(row) == 0 AND id <= 100) DO
       发送到客户端
   END WHILE
5. 关闭表：close()

-- 扫描行数：100行（range查询）
```

---

## JOIN执行流程

### Nested Loop Join

```sql
-- SQL
SELECT * FROM orders o
JOIN users u ON o.user_id = u.id;

-- 执行流程（Nested Loop Join）
1. 打开orders表：open_table("orders")
2. 打开users表：open_table("users")
3. 初始化orders全表扫描：orders->rnd_init()
4. 循环orders表
   FOR EACH order IN orders DO
       -- 内层：通过索引查找users表
       users->index_read(id = order.user_id)
       users->read_row()
       -- 拼接结果，发送客户端
   END FOR
5. 关闭表

-- 扫描次数
orders表：全表扫描（M行）
users表：索引查找（M次，每次O(log N)）
总复杂度：O(M × log N)
```

---

## 执行器优化

### 1. 条件下推

```sql
-- SQL
SELECT * FROM users WHERE id > 100;

-- 未优化
1. 存储引擎返回所有行
2. 执行器过滤 id > 100
3. 返回结果

-- ICP优化（Index Condition Pushdown）
1. 存储引擎扫描索引时，直接过滤 id > 100
2. 返回满足条件的行
3. 减少回表次数
```

### 2. 批量读取

```sql
-- Multi-Range Read（MRR）优化
-- 场景：范围查询 + 回表

-- 未优化
1. 扫描索引：获取10个主键ID（随机顺序）
2. 逐个回表：10次随机IO

-- MRR优化
1. 扫描索引：获取10个主键ID
2. 排序主键ID（变为顺序）
3. 批量回表：1次顺序IO
```

---

## 执行器与优化器的配合

```sql
-- SQL
SELECT * FROM users WHERE name = 'Alice' AND age = 25;

-- 优化器决策
1. 选择索引：idx_name_age
2. 生成执行计划：
   - type: ref
   - key: idx_name_age
   - rows: 1

-- 执行器执行
1. 调用存储引擎接口：index_read(idx_name_age, 'Alice', 25)
2. 存储引擎返回数据行
3. 执行器返回客户端
```

---

## 查看执行器操作

### 1. SHOW PROFILE

```sql
-- 开启profiling
SET profiling = 1;

-- 执行SQL
SELECT * FROM users WHERE id = 1;

-- 查看执行耗时
SHOW PROFILES;

-- 详细分析
SHOW PROFILE FOR QUERY 1;

-- 输出示例
+----------------------+----------+
| Status               | Duration |
+----------------------+----------+
| starting             | 0.000050 |
| checking permissions | 0.000005 |
| Opening tables       | 0.000020 |
| init                 | 0.000010 |
| System lock          | 0.000005 |
| optimizing           | 0.000005 |
| statistics           | 0.000010 |
| preparing            | 0.000010 |
| executing            | 0.000005 |  ← 执行器调用存储引擎
| Sending data         | 0.000050 |  ← 存储引擎返回数据
| end                  | 0.000005 |
| query end            | 0.000005 |
| closing tables       | 0.000005 |
| freeing items        | 0.000010 |
| cleaning up          | 0.000010 |
+----------------------+----------+
```

### 2. Performance Schema

```sql
-- 查看执行引擎调用存储引擎的次数
SELECT * FROM performance_schema.events_statements_summary_by_digest
WHERE DIGEST_TEXT LIKE 'SELECT%users%'
LIMIT 1\G

-- 关键指标
COUNT_STAR         : 10000   -- 执行次数
SUM_ROWS_EXAMINED  : 100000  -- 扫描行数
SUM_ROWS_SENT      : 10000   -- 返回行数
```

---

## 执行器性能影响

### 1. 扫描行数

```sql
-- 全表扫描（扫描100万行）
SELECT * FROM users;
-- 执行器调用100万次 rnd_next()

-- 索引查询（扫描1行）
SELECT * FROM users WHERE id = 1;
-- 执行器调用1次 index_read()

-- 优化：减少扫描行数
```

### 2. 回表次数

```sql
-- 非覆盖索引（需要回表）
SELECT * FROM users WHERE name = 'Alice';
-- 1. 索引扫描：index_read(name='Alice')
-- 2. 回表：read_row(主键=1)

-- 覆盖索引（无需回表）
SELECT id, name FROM users WHERE name = 'Alice';
-- 1. 索引扫描：index_read(name='Alice')
-- 2. 直接返回（无需回表）

-- 优化：使用覆盖索引
```

---

## 实战建议

### 1. 减少扫描行数

```sql
-- ❌ 不好：全表扫描
SELECT * FROM users WHERE age > 25;

-- ✅ 好：使用索引
CREATE INDEX idx_age ON users(age);
SELECT * FROM users WHERE age > 25;
```

### 2. 使用覆盖索引

```sql
-- ❌ 不好：需要回表
SELECT * FROM users WHERE name = 'Alice';

-- ✅ 好：覆盖索引
CREATE INDEX idx_name_age ON users(name, age);
SELECT name, age FROM users WHERE name = 'Alice';
```

### 3. 避免大结果集

```sql
-- ❌ 不好：返回100万行
SELECT * FROM users;

-- ✅ 好：分页查询
SELECT * FROM users LIMIT 0, 100;
```

---

## 常见面试题

**Q1: 执行引擎的作用是什么？**
- 调用存储引擎接口，执行SQL，返回结果

**Q2: 执行引擎如何调用存储引擎？**
- 通过Handler API（rnd_next、index_read等接口）

**Q3: 如何查看SQL执行过程？**
- `SHOW PROFILE`、`Performance Schema`

**Q4: 如何优化执行器性能？**
- 减少扫描行数、使用覆盖索引、避免大结果集

---

## 小结

✅ **执行引擎**：调用存储引擎接口，执行SQL
✅ **Handler API**：rnd_next、index_read、write_row等接口
✅ **执行流程**：打开表 → 扫描数据 → 应用条件 → 返回结果
✅ **优化建议**：减少扫描行数、使用覆盖索引

执行引擎是SQL执行的最后一步。

---

📚 **相关阅读**：
- 下一篇：《InnoDB架构综合实战》
- 推荐：《查询优化器：生成最优执行计划》
