---
title: "EXPLAIN执行计划详解（下）：高级分析"
date: 2025-11-21T22:15:00+08:00
draft: false
tags: ["MySQL", "EXPLAIN", "性能分析", "高级优化"]
categories: ["MySQL"]
description: "深入掌握EXPLAIN的高级字段，学会分析ref、rows、filtered、Extra等信息，全面诊断查询性能。"
series: ["MySQL从入门到精通"]
weight: 32
stage: 3
stageTitle: "索引与优化篇"
---

## 一、ref - 索引引用

### 1.1 含义

显示索引查找使用的列或常量。

```sql
-- 常量查询
EXPLAIN SELECT * FROM users WHERE id = 10;
-- ref: const

-- JOIN查询
EXPLAIN SELECT * FROM orders o JOIN users u ON o.user_id = u.id;
-- ref: database.o.user_id（orders表的user_id列）
```

---

## 二、rows - 扫描行数

### 2.1 预估行数

```sql
EXPLAIN SELECT * FROM users WHERE name = '张三';
-- rows: 100（预估扫描100行）
```

**注意**：是估算值，不是精确值。

### 2.2 优化目标

```
rows越小越好
- ✅ rows < 100：良好
- ⚠️ rows < 10000：可接受
- ❌ rows > 100000：需优化
```

---

## 三、filtered - 过滤百分比

### 3.1 含义

经过WHERE过滤后，剩余记录的百分比。

```sql
EXPLAIN SELECT * FROM users
WHERE name = '张三' AND age = 20;
-- rows: 1000
-- filtered: 10%
-- 最终：1000 * 10% = 100行
```

### 3.2 计算

```
实际返回行数 ≈ rows * (filtered / 100)
```

---

## 四、Extra - 额外信息（重要）

### 4.1 Using index（覆盖索引）

```sql
EXPLAIN SELECT id, name FROM users WHERE name = '张三';
-- Extra: Using index（覆盖索引，最优）
```

**含义**：只需扫描索引，无需回表。

### 4.2 Using where

```sql
EXPLAIN SELECT * FROM users WHERE age = 20;
-- Extra: Using where（Server层过滤）
```

**含义**：使用WHERE条件过滤。

### 4.3 Using index condition（ICP）

```sql
EXPLAIN SELECT * FROM users
WHERE name = '张三' AND age > 20;
-- Extra: Using index condition（索引下推）
```

**含义**：索引条件下推优化。

### 4.4 Using filesort（需优化）

```sql
EXPLAIN SELECT * FROM users ORDER BY age;
-- Extra: Using filesort（文件排序，慢）
```

**含义**：无法利用索引排序，需额外排序。

**优化**：
```sql
CREATE INDEX idx_age ON users(age);
-- 排序利用索引，去除Using filesort
```

### 4.5 Using temporary（需优化）

```sql
EXPLAIN SELECT DISTINCT age FROM users;
-- Extra: Using temporary（使用临时表）
```

**含义**：需要创建临时表。

**常见场景**：
- DISTINCT
- GROUP BY无索引
- UNION

### 4.6 Using join buffer

```sql
EXPLAIN SELECT * FROM orders o JOIN users u ON o.user_id = u.id;
-- Extra: Using join buffer（使用连接缓冲）
```

**含义**：JOIN时使用了缓冲区（通常因为无索引）。

### 4.7 Impossible WHERE

```sql
EXPLAIN SELECT * FROM users WHERE 1 = 0;
-- Extra: Impossible WHERE（不可能的条件）
```

**含义**：WHERE条件永远为假。

---

## 五、综合分析案例

### 案例1：全表扫描

```sql
EXPLAIN SELECT * FROM orders WHERE status = 'pending';
```

**结果**：
```
type: ALL
key: NULL
rows: 1000000
Extra: Using where
```

**分析**：
- 全表扫描（type: ALL）
- 未使用索引（key: NULL）
- 扫描100万行
- 需要优化

**优化**：
```sql
CREATE INDEX idx_status ON orders(status);

-- 优化后
type: ref
key: idx_status
rows: 50000
Extra: NULL
```

### 案例2：排序优化

```sql
EXPLAIN SELECT * FROM orders
WHERE user_id = 123
ORDER BY created_at;
```

**优化前**：
```
key: idx_user_id
Extra: Using where; Using filesort  ← 文件排序
```

**优化**：
```sql
CREATE INDEX idx_user_created ON orders(user_id, created_at);

-- 优化后
key: idx_user_created
Extra: NULL  ← 无filesort，利用索引排序
```

### 案例3：覆盖索引优化

```sql
EXPLAIN SELECT user_id, created_at FROM orders
WHERE user_id = 123
ORDER BY created_at;
```

**优化前**：
```
key: idx_user_created
Extra: NULL
```

**优化后**（添加覆盖索引）：
```sql
CREATE INDEX idx_user_created ON orders(user_id, created_at);
-- 索引包含：user_id, created_at, id（主键）

-- 结果
Extra: Using index  ← 覆盖索引，性能最优
```

---

## 六、EXPLAIN ANALYZE（MySQL 8.0.18+）

### 6.1 实际执行分析

```sql
EXPLAIN ANALYZE SELECT * FROM users WHERE name = '张三';
```

**结果**：
```
-> Filter: (users.name = '张三')  (cost=10.5 rows=10) (actual time=0.05..0.12 rows=5 loops=1)
    -> Table scan on users  (cost=10.5 rows=100) (actual time=0.03..0.10 rows=100 loops=1)
```

**关键信息**：
- **cost**：估算成本
- **rows**：估算行数
- **actual time**：实际执行时间
- **actual rows**：实际行数

### 6.2 对比估算vs实际

```
估算：rows=100
实际：actual rows=5

→ 统计信息不准确，需要ANALYZE TABLE
```

---

## 七、优化实战流程

### 7.1 执行EXPLAIN

```sql
EXPLAIN SELECT ...;
```

### 7.2 检查关键字段

```
1. type：是否ALL（全表扫描）？
2. key：是否NULL（无索引）？
3. rows：扫描行数是否过多？
4. Extra：是否有Using filesort/Using temporary？
```

### 7.3 针对性优化

```sql
-- type: ALL → 创建索引
CREATE INDEX ...;

-- Using filesort → 索引排序
CREATE INDEX idx_col ON table(col);

-- Using temporary → 索引分组
CREATE INDEX idx_group ON table(group_col);
```

### 7.4 验证效果

```sql
EXPLAIN SELECT ...;
-- 检查是否改善
```

---

## 八、Extra字段速查表

| Extra | 含义 | 性能 | 优化 |
|-------|------|------|------|
| Using index | 覆盖索引 | ✅ 优 | 保持 |
| Using index condition | 索引下推 | ✅ 良好 | 保持 |
| Using where | WHERE过滤 | ⚠️ 中 | 考虑索引 |
| Using filesort | 文件排序 | ❌ 差 | 索引排序 |
| Using temporary | 临时表 | ❌ 差 | 索引优化 |
| Using join buffer | JOIN缓冲 | ❌ 差 | 添加索引 |

---

## 九、总结

### 核心要点

1. **ref**：索引查找的列或常量
2. **rows**：估算扫描行数，越小越好
3. **filtered**：过滤后剩余百分比
4. **Extra**：最重要的诊断信息
   - Using index：最优（覆盖索引）
   - Using filesort：需优化（文件排序）
   - Using temporary：需优化（临时表）
5. **EXPLAIN ANALYZE**：查看实际执行情况

### 优化检查清单

```
□ type不是ALL
□ key不是NULL
□ rows < 10000
□ filtered > 10%
□ Extra无filesort/temporary
```

### 记忆口诀

```
ref显示索引引用，rows扫描行数看，
filtered过滤百分比，Extra信息最关键。
Using index最优化，filesort temporary差，
index condition ICP好，优化目标要记牢。
```

---

**本文字数**：约2,400字
**难度等级**：⭐⭐⭐⭐（性能分析）
