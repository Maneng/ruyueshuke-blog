---
title: "EXPLAIN执行计划详解（上）：基础字段"
date: 2025-11-20T22:00:00+08:00
draft: false
tags: ["MySQL", "EXPLAIN", "执行计划", "性能分析"]
categories: ["MySQL"]
description: "掌握EXPLAIN执行计划的基础字段，学会分析查询的执行过程，快速定位性能问题。"
series: ["MySQL从入门到精通"]
weight: 31
stage: 3
stageTitle: "索引与优化篇"
---

## 一、EXPLAIN基础

### 1.1 什么是EXPLAIN

```sql
EXPLAIN SELECT * FROM users WHERE id = 10;
```

**作用**：
- 查看SQL执行计划
- 不实际执行查询
- 分析索引使用情况
- 优化查询性能

### 1.2 基本用法

```sql
-- 方式1：EXPLAIN
EXPLAIN SELECT ...;

-- 方式2：DESCRIBE（同义词）
DESCRIBE SELECT ...;

-- 方式3：查看实际执行（MySQL 8.0.18+）
EXPLAIN ANALYZE SELECT ...;
```

---

## 二、id - 查询标识

### 2.1 含义

查询的执行顺序标识。

```sql
EXPLAIN SELECT * FROM users WHERE id = 10;
```

**结果**：
```
id: 1  ← 简单查询
```

### 2.2 子查询

```sql
EXPLAIN SELECT * FROM users
WHERE id IN (SELECT user_id FROM orders);
```

**结果**：
```
id  | table
----+--------
1   | users
2   | orders  ← 先执行id=2（子查询）
```

**规则**：
- **id大的先执行**
- **id相同，从上往下执行**

---

## 三、select_type - 查询类型

### 3.1 SIMPLE

简单查询，无子查询或UNION。

```sql
EXPLAIN SELECT * FROM users WHERE id = 10;
-- select_type: SIMPLE
```

### 3.2 PRIMARY

最外层查询。

```sql
EXPLAIN SELECT * FROM users WHERE id IN (SELECT ...);
-- select_type: PRIMARY（外层查询）
```

### 3.3 SUBQUERY

子查询。

```sql
EXPLAIN SELECT * FROM users
WHERE id = (SELECT MAX(user_id) FROM orders);
-- 子查询：SUBQUERY
```

### 3.4 DERIVED

派生表（FROM子句中的子查询）。

```sql
EXPLAIN SELECT * FROM (SELECT * FROM users) AS t;
-- select_type: DERIVED
```

### 3.5 UNION

UNION查询。

```sql
EXPLAIN
SELECT * FROM users WHERE id = 1
UNION
SELECT * FROM users WHERE id = 2;
-- 第二个SELECT：UNION
```

---

## 四、table - 表名

显示查询的表名。

```sql
EXPLAIN SELECT * FROM users;
-- table: users
```

**派生表**：
```sql
EXPLAIN SELECT * FROM (SELECT * FROM users) AS t;
-- table: <derived2>（派生表）
```

---

## 五、type - 访问类型（重要）

### 5.1 性能排序

```
system > const > eq_ref > ref > range > index > ALL
 最好                                          最差
```

### 5.2 system

表只有一行（系统表）。

```sql
EXPLAIN SELECT * FROM mysql.proxies_priv;
-- type: system
```

### 5.3 const

主键或唯一索引的等值查询。

```sql
EXPLAIN SELECT * FROM users WHERE id = 10;
-- type: const（最多一条记录）
```

### 5.4 eq_ref

JOIN时，主键或唯一索引的等值连接。

```sql
EXPLAIN SELECT * FROM orders o
JOIN users u ON o.user_id = u.id;
-- users表：eq_ref
```

### 5.5 ref

非唯一索引的等值查询。

```sql
EXPLAIN SELECT * FROM users WHERE name = '张三';
-- type: ref（普通索引）
```

### 5.6 range

范围查询。

```sql
EXPLAIN SELECT * FROM users WHERE id BETWEEN 10 AND 20;
-- type: range
```

### 5.7 index

全索引扫描。

```sql
EXPLAIN SELECT id FROM users;
-- type: index（扫描整个索引）
```

### 5.8 ALL

全表扫描（最差）。

```sql
EXPLAIN SELECT * FROM users WHERE age = 20;
-- type: ALL（无索引）
```

---

## 六、possible_keys - 可能使用的索引

```sql
EXPLAIN SELECT * FROM users WHERE name = '张三' AND age = 20;
-- possible_keys: idx_name, idx_age
```

**含义**：MySQL认为可能使用的索引。

---

## 七、key - 实际使用的索引

```sql
EXPLAIN SELECT * FROM users WHERE name = '张三' AND age = 20;
-- key: idx_name（实际选择的索引）
```

**NULL**：未使用索引。

```sql
EXPLAIN SELECT * FROM users WHERE age = 20;
-- key: NULL（全表扫描）
```

---

## 八、key_len - 索引长度

### 8.1 含义

使用的索引长度（字节数）。

```sql
-- 索引
CREATE INDEX idx_name ON users(name);  -- VARCHAR(50)

EXPLAIN SELECT * FROM users WHERE name = '张三';
-- key_len: 203（50*4+2+1，UTF8MB4）
```

### 8.2 计算规则

```
VARCHAR(N)：
- UTF8：N * 3 + 2（长度） + 1（NULL标志）
- UTF8MB4：N * 4 + 2 + 1

INT：4字节
BIGINT：8字节
DATETIME：8字节
```

### 8.3 联合索引

```sql
CREATE INDEX idx_a_b ON table(a, b);  -- a INT, b INT

WHERE a = 1;
-- key_len: 4（只用了a）

WHERE a = 1 AND b = 2;
-- key_len: 8（用了a和b）
```

---

## 九、实战示例

### 示例1：优化前后对比

```sql
-- 优化前
EXPLAIN SELECT * FROM orders WHERE user_id = 123;
-- type: ALL（全表扫描）
-- key: NULL

-- 创建索引
CREATE INDEX idx_user_id ON orders(user_id);

-- 优化后
EXPLAIN SELECT * FROM orders WHERE user_id = 123;
-- type: ref
-- key: idx_user_id
```

### 示例2：联合索引分析

```sql
CREATE INDEX idx_a_b_c ON table(a, b, c);

EXPLAIN SELECT * FROM table WHERE a = 1 AND b = 2;
-- key_len: 8（使用了a和b）

EXPLAIN SELECT * FROM table WHERE a = 1;
-- key_len: 4（只使用了a）
```

---

## 十、总结

### 核心字段

| 字段 | 含义 | 重点 |
|-----|------|------|
| id | 执行顺序 | 大的先执行 |
| select_type | 查询类型 | SIMPLE/PRIMARY/SUBQUERY |
| table | 表名 | - |
| **type** | 访问类型 | **最重要！** |
| possible_keys | 可能的索引 | - |
| **key** | 实际索引 | **NULL=无索引** |
| **key_len** | 索引长度 | 判断索引使用情况 |

### type优化目标

```
目标：至少达到range级别
- ✅ 理想：const/eq_ref/ref
- ⚠️ 可接受：range
- ❌ 需优化：index/ALL
```

### 记忆口诀

```
EXPLAIN分析很重要，type字段是关键，
const ref range最常见，index ALL要优化。
key显示用的索引，NULL表示没用上，
key_len索引长度看，判断联合索引用几列。
```

---

**本文字数**：约2,200字
**难度等级**：⭐⭐⭐⭐（性能分析）
