---
title: "查询优化器：生成最优执行计划的艺术"
date: 2025-01-15T18:00:00+08:00
draft: false
tags: ["MySQL", "查询优化器", "执行计划", "性能优化"]
categories: ["数据库"]
description: "深入理解MySQL查询优化器的工作原理，掌握执行计划生成和成本评估机制"
series: ["MySQL从入门到精通"]
weight: 54
stage: 5
stageTitle: "架构原理篇"
---

## 查询优化器概述

**查询优化器（Optimizer）** 的作用是为SQL生成**最优执行计划**。

```sql
-- 原始SQL
SELECT * FROM orders o
JOIN users u ON o.user_id = u.id
WHERE u.name = 'Alice' AND o.status = 'PAID';

-- 优化器决策
1. 表连接顺序：先users还是orders？
2. 索引选择：使用哪个索引？
3. 连接算法：Nested Loop、Hash Join、Sort-Merge Join？
4. 条件下推：WHERE条件何时过滤？
```

---

## 优化器类型

### 1. 基于规则的优化器（RBO）

**Rule-Based Optimizer**：根据预定义规则选择执行计划。

```sql
-- 规则示例
1. 有索引优于无索引
2. 主键索引优于二级索引
3. 小表驱动大表

-- 缺点：
不考虑数据分布，可能选择非最优计划
```

### 2. 基于成本的优化器（CBO）

**Cost-Based Optimizer**（MySQL使用）：根据成本评估选择最优计划。

```sql
-- 成本因素
1. IO成本：磁盘读取次数
2. CPU成本：记录比较次数
3. 内存成本：临时表、排序开销

-- 优点：
考虑数据分布，选择更优计划
```

---

## 成本评估

### 1. 成本模型

```sql
总成本 = IO成本 + CPU成本

IO成本 = 页数 × IO_BLOCK_READ_COST
CPU成本 = 行数 × ROW_EVALUATE_COST

-- 默认值（可调整）
IO_BLOCK_READ_COST = 1.0
ROW_EVALUATE_COST  = 0.1
```

### 2. 索引扫描成本

```sql
-- 全表扫描（Table Scan）
成本 = 表页数 × 1.0 + 表行数 × 0.1

-- 索引扫描（Index Scan）
成本 = 索引页数 × 1.0 + 回表行数 × 0.1 + 回表IO × 1.0

-- 示例
表：100万行，10000页
索引：1000页，回表10万行

全表扫描成本 = 10000 × 1.0 + 1000000 × 0.1 = 110000
索引扫描成本 = 1000 × 1.0 + 100000 × 0.1 + 100000 × 1.0 = 111000

-- 优化器选择：全表扫描（成本更低）
```

---

## 优化策略

### 1. 条件化简

```sql
-- 原始条件
WHERE id > 0 AND id < 100 AND id = 50

-- 化简后
WHERE id = 50

-- 原始条件
WHERE (status = 'PAID' OR status = 'PAID') AND user_id = 1

-- 化简后
WHERE status = 'PAID' AND user_id = 1
```

### 2. 常量折叠

```sql
-- 原始
WHERE price > 100 * 2

-- 优化后
WHERE price > 200

-- 原始
WHERE YEAR(created_at) = 2025

-- 无法优化（函数作用于列，索引失效）
```

### 3. 谓词下推（Predicate Pushdown）

```sql
-- 原始SQL
SELECT * FROM orders o
JOIN users u ON o.user_id = u.id
WHERE u.name = 'Alice';

-- 优化后（谓词下推）
SELECT * FROM orders o
JOIN (SELECT * FROM users WHERE name = 'Alice') u
ON o.user_id = u.id;
-- WHERE条件先过滤users表，减少JOIN的数据量
```

### 4. 外连接消除

```sql
-- 原始SQL
SELECT * FROM orders o
LEFT JOIN users u ON o.user_id = u.id
WHERE u.id IS NOT NULL;

-- 优化后（LEFT JOIN → INNER JOIN）
SELECT * FROM orders o
JOIN users u ON o.user_id = u.id;
-- WHERE条件保证u.id不为NULL，可以消除LEFT JOIN
```

---

## 表连接顺序

### 1. 小表驱动大表

```sql
-- 示例
users表：100行
orders表：100万行

-- ✅ 好：users驱动orders
FOR EACH user IN users (100次)
    FOR EACH order IN orders WHERE order.user_id = user.id
END FOR
-- 总循环次数：100次（users） × 平均100次（orders） = 10000次

-- ❌ 不好：orders驱动users
FOR EACH order IN orders (100万次)
    FOR EACH user IN users WHERE user.id = order.user_id
END FOR
-- 总循环次数：100万次（效率低）
```

### 2. 连接算法

**Nested Loop Join（嵌套循环）**：

```sql
-- 适用：小表驱动大表，内层有索引
FOR EACH row1 IN table1 (外层表)
    FOR EACH row2 IN table2 WHERE row2.id = row1.id (内层表，走索引)
    END FOR
END FOR

-- 时间复杂度：O(M × log N)
```

**Block Nested Loop Join（块嵌套循环）**：

```sql
-- 适用：内层无索引，使用Join Buffer
FOR EACH block IN table1 (外层表，批量读取到Join Buffer)
    FOR EACH row IN table2 (内层表)
        IF 匹配 Join Buffer中的行 THEN
            输出结果
        END IF
    END FOR
END FOR

-- 时间复杂度：O(M × N / buffer_size)
```

**Hash Join（哈希连接，MySQL 8.0.18+）**：

```sql
-- 适用：等值连接，内存充足
1. 构建Hash表（小表）
2. 探测Hash表（大表）

-- 时间复杂度：O(M + N)
```

---

## 索引选择

### 1. 可用索引

```sql
CREATE TABLE users (
    id INT PRIMARY KEY,
    name VARCHAR(50),
    age INT,
    city VARCHAR(50),
    INDEX idx_name (name),
    INDEX idx_age (age),
    INDEX idx_name_age (name, age)
);

-- 查询
SELECT * FROM users WHERE name = 'Alice' AND age = 25;

-- 可用索引
1. idx_name：WHERE name = 'Alice'
2. idx_age：WHERE age = 25
3. idx_name_age：WHERE name = 'Alice' AND age = 25（最优）
```

### 2. 索引选择算法

```sql
-- 成本评估
FOR EACH 可用索引 DO
    计算索引扫描成本
    计算回表成本
    总成本 = 索引扫描成本 + 回表成本
END FOR

-- 选择成本最低的索引
```

### 3. 索引失效

```sql
-- 索引失效场景
1. 函数作用于列
WHERE YEAR(created_at) = 2025  -- 失效

2. 隐式类型转换
WHERE user_id = '123'  -- user_id是INT，失效

3. 左模糊匹配
WHERE name LIKE '%Alice'  -- 失效

4. OR条件（部分失效）
WHERE name = 'Alice' OR age = 25  -- 如果age无索引，全表扫描
```

---

## EXPLAIN查看执行计划

```sql
EXPLAIN SELECT * FROM users WHERE name = 'Alice';

-- 关键字段
+----+-------------+-------+------+---------------+----------+---------+-------+------+-------------+
| id | select_type | table | type | possible_keys | key      | key_len | ref   | rows | Extra       |
+----+-------------+-------+------+---------------+----------+---------+-------+------+-------------+
|  1 | SIMPLE      | users | ref  | idx_name      | idx_name | 152     | const |    1 | Using where |
+----+-------------+-------+------+---------------+----------+---------+-------+------+-------------+

-- type：访问类型（system > const > eq_ref > ref > range > index > ALL）
-- possible_keys：可用索引
-- key：实际选择的索引
-- rows：预估扫描行数
```

---

## 优化器提示（Hint）

### 1. 强制使用索引

```sql
-- FORCE INDEX
SELECT * FROM users FORCE INDEX (idx_name) WHERE name = 'Alice';

-- USE INDEX（建议使用）
SELECT * FROM users USE INDEX (idx_name) WHERE name = 'Alice';

-- IGNORE INDEX（忽略索引）
SELECT * FROM users IGNORE INDEX (idx_age) WHERE age = 25;
```

### 2. 控制连接顺序

```sql
-- STRAIGHT_JOIN（强制连接顺序）
SELECT STRAIGHT_JOIN * FROM t1
JOIN t2 ON t1.id = t2.id;
-- 强制t1驱动t2
```

---

## 优化器限制

### 1. 统计信息过时

```sql
-- 问题：优化器基于统计信息评估成本
-- 如果统计信息过时，可能选择错误的计划

-- 解决：定期更新统计信息
ANALYZE TABLE users;
```

### 2. 多表连接复杂度

```sql
-- 问题：N表连接有N!种连接顺序
-- 3表：3! = 6种
-- 5表：5! = 120种
-- 10表：10! = 3628800种

-- MySQL限制：最多评估62种连接顺序（贪心算法）
```

---

## 实战建议

### 1. 辅助优化器

```sql
-- 及时更新统计信息
ANALYZE TABLE users;

-- 删除冗余索引
-- 过多索引增加优化器负担
```

### 2. 使用覆盖索引

```sql
-- 覆盖索引：SELECT的列都在索引中
CREATE INDEX idx_name_age_city ON users(name, age, city);

SELECT name, age, city FROM users WHERE name = 'Alice';
-- 无需回表，性能好
```

### 3. 避免复杂SQL

```sql
-- ❌ 不好：10表JOIN
SELECT * FROM t1
JOIN t2 ON ...
JOIN t3 ON ...
...
JOIN t10 ON ...;

-- ✅ 好：拆分查询
SELECT * FROM t1 JOIN t2 ON ...;
-- 应用层处理
SELECT * FROM t3 JOIN t4 ON ...;
```

---

## 常见面试题

**Q1: MySQL优化器是RBO还是CBO？**
- CBO（基于成本的优化器）

**Q2: 成本评估包括哪些因素？**
- IO成本（磁盘读取）+ CPU成本（记录比较）

**Q3: 如何查看优化器选择的执行计划？**
- EXPLAIN命令

**Q4: 如何强制使用某个索引？**
- FORCE INDEX (idx_name)

---

## 小结

✅ **优化器作用**：生成最优执行计划
✅ **成本评估**：IO成本 + CPU成本
✅ **优化策略**：条件化简、谓词下推、小表驱动大表
✅ **索引选择**：成本最低的索引

理解优化器原理有助于编写高效SQL。

---

📚 **相关阅读**：
- 下一篇：《执行引擎：SQL执行的最后一步》
- 推荐：《EXPLAIN执行计划详解》
