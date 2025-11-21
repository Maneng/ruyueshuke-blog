---
title: "索引下推：ICP优化"
date: 2025-11-20T21:45:00+08:00
draft: false
tags: ["MySQL", "索引下推", "ICP", "性能优化"]
categories: ["MySQL"]
description: "深入理解MySQL索引下推优化（ICP），掌握其原理和应用场景，提升复杂查询性能。"
series: ["MySQL从入门到精通"]
weight: 30
stage: 3
stageTitle: "索引与优化篇"
---

## 一、什么是索引下推（ICP）

### 1.1 问题场景

```sql
CREATE INDEX idx_a_b ON table(a, b);

SELECT * FROM table WHERE a = 1 AND b LIKE '%abc%';
```

**传统执行**（无ICP）：
1. 使用索引找到a=1的所有记录
2. 回表获取完整数据
3. 在Server层过滤b LIKE '%abc%'

**问题**：大量无效回表。

### 1.2 ICP优化

**ICP执行**（MySQL 5.6+）：
1. 使用索引找到a=1的记录
2. **在索引中**直接过滤b LIKE '%abc%'
3. 只回表符合条件的记录

**优势**：减少回表次数。

---

## 二、ICP原理

### 2.1 传统流程 vs ICP流程

**传统**：
```
索引层：找到a=1的10条记录
    ↓ 回表10次
存储引擎：获取10条完整数据
    ↓
Server层：过滤b，最终2条符合
```

**ICP**：
```
索引层：找到a=1的10条记录
    ↓ 在索引中过滤b
索引层：10条中2条符合b条件
    ↓ 只回表2次
存储引擎：获取2条完整数据
```

### 2.2 关键

**下推**：将Server层的过滤条件下推到存储引擎层。

---

## 三、ICP的适用条件

### 3.1 启用条件

```sql
-- 查看ICP状态
SHOW VARIABLES LIKE 'optimizer_switch';
-- index_condition_pushdown=on

-- 启用ICP
SET optimizer_switch='index_condition_pushdown=on';
```

### 3.2 使用场景

```sql
-- ✅ 可以使用ICP
CREATE INDEX idx_a_b_c ON table(a, b, c);

WHERE a = 1 AND b > 10 AND c = 3;
-- a精确匹配 → 使用索引
-- b范围查询 → 使用索引
-- c过滤条件 → ICP下推到索引层
```

### 3.3 不适用场景

```sql
-- ❌ 主键索引（聚簇索引）
-- 已经包含完整数据，无需下推

-- ❌ 覆盖索引
-- 不需要回表，无需下推

-- ❌ 全表扫描
-- 没有使用索引
```

---

## 四、EXPLAIN中的ICP

### 4.1 识别标志

```sql
EXPLAIN SELECT * FROM orders
WHERE user_id = 123 AND status LIKE '%pending%';
```

**结果**：
```
Extra: Using index condition  ← ICP优化
```

### 4.2 完整示例

```sql
-- 创建索引
CREATE INDEX idx_user_status ON orders(user_id, status);

-- 查询
EXPLAIN SELECT * FROM orders
WHERE user_id = 123 AND status LIKE '%ing%';
```

**EXPLAIN结果**：
```
type: ref
key: idx_user_status
Extra: Using index condition  ← ICP
```

---

## 五、ICP vs 非ICP对比

### 5.1 性能测试

```sql
-- 测试表：100万数据
CREATE TABLE test_users (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(50),
    age INT,
    city VARCHAR(50)
);
CREATE INDEX idx_name_age ON test_users(name, age);

-- 查询
SELECT * FROM test_users
WHERE name LIKE '张%' AND age BETWEEN 20 AND 30;
```

**无ICP**：
- 扫描name LIKE '张%'的10000条记录
- 回表10000次
- Server层过滤age，最终1000条
- 耗时：2秒

**有ICP**：
- 扫描name LIKE '张%'的10000条记录
- 在索引中过滤age，1000条符合
- 回表1000次
- 耗时：0.2秒

**性能提升**：10倍！

---

## 六、实战案例

### 案例1：范围查询优化

```sql
-- 查询
SELECT * FROM orders
WHERE user_id = 123
  AND created_at >= '2024-01-01'
  AND created_at <= '2024-12-31'
  AND status = 'completed';

-- 索引
CREATE INDEX idx_user_date_status ON orders(user_id, created_at, status);

-- 执行计划
EXPLAIN ...
-- type: range
-- Extra: Using index condition
-- ICP下推status过滤，减少回表
```

### 案例2：LIKE查询优化

```sql
-- 查询
SELECT * FROM products
WHERE category = '手机'
  AND name LIKE '%Pro%'
  AND price > 5000;

-- 索引
CREATE INDEX idx_category_name_price ON products(category, name, price);

-- ICP下推name和price过滤
```

---

## 七、ICP的限制

### 7.1 不支持的操作

```sql
-- ❌ 子查询
WHERE a = 1 AND b = (SELECT ...);

-- ❌ 存储函数
WHERE a = 1 AND b = custom_function(c);

-- ❌ 触发器相关列
```

### 7.2 InnoDB和MyISAM

- **InnoDB**：支持ICP
- **MyISAM**：支持ICP
- **Memory**：不支持ICP

---

## 八、优化建议

### 8.1 合理设计索引

```sql
-- 将过滤条件列加入索引
WHERE a = 1 AND b > 10 AND c = 3;

CREATE INDEX idx_a_b_c ON table(a, b, c);
-- c虽然在范围后失效，但ICP可下推过滤
```

### 8.2 监控ICP效果

```sql
-- 查看ICP使用情况
SHOW STATUS LIKE 'Handler_read%';
-- Handler_read_next: 索引扫描次数
-- Handler_read_rnd_next: 回表次数
```

---

## 九、总结

### 核心要点

1. **ICP定义**：Index Condition Pushdown，索引条件下推
2. **原理**：将过滤条件下推到存储引擎层
3. **优势**：减少回表次数，提升性能
4. **识别**：EXPLAIN Extra: Using index condition
5. **适用**：二级索引的范围查询后过滤条件
6. **限制**：不支持子查询、存储函数

### 记忆口诀

```
索引下推ICP好，过滤条件往下推，
范围查询后面列，索引层里先过滤。
减少回表次数多，性能提升看得见，
Using index condition，五点六以上版本。
```

---

**本文字数**：约2,000字
**难度等级**：⭐⭐⭐⭐（索引进阶）
