---
title: "联合查询：UNION与UNION ALL"
date: 2025-11-21T18:30:00+08:00
draft: false
tags: ["MySQL", "SQL查询", "UNION", "UNION ALL"]
categories: ["MySQL"]
description: "掌握UNION和UNION ALL的使用场景和区别，学会合并多个查询结果集，理解性能差异和使用技巧。"
series: ["MySQL从入门到精通"]
weight: 17
stage: 2
stageTitle: "SQL进阶篇"
---

## 引言

UNION用于合并多个SELECT语句的结果集，适用于需要从不同表或不同条件查询结果合并的场景。

---

## 一、UNION基础

### 1.1 基本语法

```sql
SELECT column1, column2 FROM table1
UNION
SELECT column1, column2 FROM table2;
```

**要求**：
1. 列数必须相同
2. 列的数据类型要兼容
3. 默认去重

### 1.2 示例

```sql
-- 合并2024年和2025年的订单
SELECT order_id, amount, '2024' AS year
FROM orders_2024
UNION
SELECT order_id, amount, '2025' AS year
FROM orders_2025;
```

---

## 二、UNION vs UNION ALL

### 2.1 UNION - 去重合并

```sql
SELECT name FROM products WHERE category = '手机'
UNION
SELECT name FROM products WHERE price > 5000;
```

**特点**：
- 自动去重
- 性能较差（需要排序去重）

### 2.2 UNION ALL - 保留重复

```sql
SELECT name FROM products WHERE category = '手机'
UNION ALL
SELECT name FROM products WHERE price > 5000;
```

**特点**：
- 保留所有记录（包括重复）
- 性能好（不需要去重）

### 2.3 性能对比

```sql
-- UNION：去重需要额外排序，慢
EXPLAIN SELECT id FROM orders_2024
UNION
SELECT id FROM orders_2025;
-- Extra: Using temporary

-- UNION ALL：直接合并，快
EXPLAIN SELECT id FROM orders_2024
UNION ALL
SELECT id FROM orders_2025;
-- Extra: (无)
```

**建议**：
- 确定无重复或允许重复：用UNION ALL
- 必须去重：用UNION

---

## 三、使用场景

### 3.1 分表查询

```sql
-- 查询所有历史订单（按月分表）
SELECT * FROM orders_202401
UNION ALL
SELECT * FROM orders_202402
UNION ALL
SELECT * FROM orders_202403;
```

### 3.2 不同条件的结果合并

```sql
-- 查询热门商品 + 新品
SELECT name, '热门' AS tag FROM products WHERE sales > 1000
UNION ALL
SELECT name, '新品' AS tag FROM products WHERE created_at > DATE_SUB(NOW(), INTERVAL 7 DAY);
```

### 3.3 实现FULL JOIN

```sql
-- MySQL不支持FULL JOIN，用UNION模拟
SELECT u.name, o.amount
FROM users u LEFT JOIN orders o ON u.id = o.user_id
UNION
SELECT u.name, o.amount
FROM users u RIGHT JOIN orders o ON u.id = o.user_id;
```

---

## 四、ORDER BY与LIMIT

### 4.1 对整个结果排序

```sql
-- 对合并后的结果排序
(SELECT name, price FROM products WHERE category = '手机')
UNION ALL
(SELECT name, price FROM products WHERE category = '电脑')
ORDER BY price DESC;
```

**注意**：ORDER BY作用于整个UNION结果。

### 4.2 对每个查询排序并合并

```sql
-- 每个查询单独排序
(SELECT name, price FROM products WHERE category = '手机' ORDER BY price DESC LIMIT 5)
UNION ALL
(SELECT name, price FROM products WHERE category = '电脑' ORDER BY price DESC LIMIT 5);
```

### 4.3 分页

```sql
-- 对合并结果分页
(SELECT name FROM products WHERE category = '手机')
UNION ALL
(SELECT name FROM products WHERE category = '电脑')
LIMIT 10 OFFSET 0;
```

---

## 五、注意事项

### 5.1 列数和类型

```sql
-- ❌ 错误：列数不同
SELECT name, price FROM products
UNION
SELECT name FROM users;

-- ✅ 正确：补齐列数
SELECT name, price FROM products
UNION
SELECT name, NULL AS price FROM users;
```

### 5.2 列名以第一个SELECT为准

```sql
SELECT name, price FROM products
UNION ALL
SELECT username AS name, salary AS price FROM employees;
-- 结果列名为：name, price
```

### 5.3 性能优化

```sql
-- ❌ 差：每个查询都扫描全表
SELECT * FROM products WHERE category = '手机'
UNION ALL
SELECT * FROM products WHERE category = '电脑';

-- ✅ 好：用OR或IN代替
SELECT * FROM products WHERE category IN ('手机', '电脑');
```

---

## 六、实战案例

### 案例1：多维度统计

```sql
SELECT '总订单数' AS metric, COUNT(*) AS value FROM orders
UNION ALL
SELECT '已完成订单数', COUNT(*) FROM orders WHERE status = 'completed'
UNION ALL
SELECT '待处理订单数', COUNT(*) FROM orders WHERE status = 'pending';
```

### 案例2：报表汇总

```sql
SELECT category, SUM(sales) AS total_sales, 'normal' AS row_type
FROM products
GROUP BY category
UNION ALL
SELECT '总计', SUM(sales), 'summary'
FROM products;
```

### 案例3：分库分表查询

```sql
-- 从多个库查询
SELECT * FROM db1.orders WHERE user_id = 123
UNION ALL
SELECT * FROM db2.orders WHERE user_id = 123
UNION ALL
SELECT * FROM db3.orders WHERE user_id = 123;
```

---

## 七、总结

### 核心要点

1. **UNION**：去重合并，性能较差
2. **UNION ALL**：保留重复，性能好，推荐优先使用
3. **要求**：列数相同、类型兼容
4. **ORDER BY**：作用于整个结果集
5. **优化**：能用IN/OR代替就不用UNION

### 记忆口诀

```
UNION合并多结果，ALL保留UNION去，
列数类型要相同，第一列名是标准。
ORDER作用整体上，LIMIT分页在最后，
确定无重用ALL，性能更好不用愁。
```

---

**本文字数**：约2,200字
**难度等级**：⭐⭐（SQL进阶）
