---
title: "窗口函数：ROW_NUMBER、RANK、DENSE_RANK"
date: 2025-11-20T18:45:00+08:00
draft: false
tags: ["MySQL", "SQL查询", "窗口函数", "分析函数"]
categories: ["MySQL"]
description: "掌握MySQL 8.0+窗口函数的使用，理解ROW_NUMBER、RANK、DENSE_RANK的区别，学会使用PARTITION BY和ORDER BY进行高级分析。"
series: ["MySQL从入门到精通"]
weight: 18
stage: 2
stageTitle: "SQL进阶篇"
---

## 引言

窗口函数（Window Functions）是MySQL 8.0引入的强大分析功能，可以在不改变行数的情况下进行复杂的计算和排序。

---

## 一、窗口函数基础

### 1.1 基本语法

```sql
function_name() OVER (
    [PARTITION BY column]
    [ORDER BY column]
    [frame_specification]
)
```

**核心概念**：
- **PARTITION BY**：分组（类似GROUP BY，但不合并行）
- **ORDER BY**：排序
- **frame_specification**：窗口框架（可选）

### 1.2 与GROUP BY的区别

```sql
-- GROUP BY：合并行
SELECT category, COUNT(*) FROM products GROUP BY category;
-- 结果：3行

-- 窗口函数：保留所有行
SELECT name, category,
       COUNT(*) OVER (PARTITION BY category) AS category_count
FROM products;
-- 结果：10行（每行都显示）
```

---

## 二、ROW_NUMBER() - 行号

为每行分配唯一的序号。

### 2.1 基础用法

```sql
-- 为所有商品编号
SELECT name, price,
       ROW_NUMBER() OVER (ORDER BY price DESC) AS row_num
FROM products;
```

**结果**：
```
+-------------+--------+---------+
| name        | price  | row_num |
+-------------+--------+---------+
| MacBook Pro | 14999  |    1    |
| 华为Mate60  |  6999  |    2    |
| iPhone 15   |  7999  |    3    |
| ...         |  ...   |   ...   |
+-------------+--------+---------+
```

### 2.2 分组编号

```sql
-- 每个类别内编号
SELECT name, category, price,
       ROW_NUMBER() OVER (PARTITION BY category ORDER BY price DESC) AS rn
FROM products;
```

**结果**：
```
+----------+----------+--------+----+
| name     | category | price  | rn |
+----------+----------+--------+----+
| iPhone15 | 手机     | 7999   | 1  |
| 华为Mate | 手机     | 6999   | 2  |
| 小米14   | 手机     | 3999   | 3  |
| MacBook  | 电脑     | 14999  | 1  |
| ThinkPad | 电脑     | 8999   | 2  |
+----------+----------+--------+----+
```

### 2.3 Top N查询

```sql
-- 每个类别价格最高的3个商品
SELECT * FROM (
    SELECT name, category, price,
           ROW_NUMBER() OVER (PARTITION BY category ORDER BY price DESC) AS rn
    FROM products
) t
WHERE rn <= 3;
```

---

## 三、RANK() - 排名（有间隔）

相同值排名相同，后续排名跳过。

```sql
SELECT name, sales,
       RANK() OVER (ORDER BY sales DESC) AS rank_num
FROM products;
```

**结果**：
```
+-------+-------+-----------+
| name  | sales | rank_num  |
+-------+-------+-----------+
| A     | 1000  |    1      |
| B     | 1000  |    1      |  <-- 并列第1
| C     |  800  |    3      |  <-- 跳过第2，直接第3
| D     |  600  |    4      |
+-------+-------+-----------+
```

---

## 四、DENSE_RANK() - 排名（无间隔）

相同值排名相同，后续排名连续。

```sql
SELECT name, sales,
       DENSE_RANK() OVER (ORDER BY sales DESC) AS dense_rank_num
FROM products;
```

**结果**：
```
+-------+-------+-----------------+
| name  | sales | dense_rank_num  |
+-------+-------+-----------------+
| A     | 1000  |       1         |
| B     | 1000  |       1         |  <-- 并列第1
| C     |  800  |       2         |  <-- 连续第2
| D     |  600  |       3         |
+-------+-------+-----------------+
```

---

## 五、三者对比

| 函数 | 相同值处理 | 后续排名 | 适用场景 |
|------|----------|---------|---------|
| ROW_NUMBER | 不同 | 连续 | 去重、分页 |
| RANK | 相同 | 跳跃 | 允许并列的排名 |
| DENSE_RANK | 相同 | 连续 | 需要紧凑的排名 |

```sql
SELECT name, score,
       ROW_NUMBER() OVER (ORDER BY score DESC) AS row_num,
       RANK() OVER (ORDER BY score DESC) AS rank_num,
       DENSE_RANK() OVER (ORDER BY score DESC) AS dense_rank
FROM students;
```

**结果**：
```
+------+-------+---------+----------+------------+
| name | score | row_num | rank_num | dense_rank |
+------+-------+---------+----------+------------+
| 张三 |   95  |    1    |     1    |     1      |
| 李四 |   95  |    2    |     1    |     1      |
| 王五 |   90  |    3    |     3    |     2      |
| 赵六 |   85  |    4    |     4    |     3      |
+------+-------+---------+----------+------------+
```

---

## 六、其他常用窗口函数

### 6.1 LAG() / LEAD()

访问前一行或后一行的数据。

```sql
-- 查看每个商品与前一个商品的价格差
SELECT name, price,
       LAG(price, 1) OVER (ORDER BY price) AS prev_price,
       price - LAG(price, 1) OVER (ORDER BY price) AS price_diff
FROM products;
```

### 6.2 FIRST_VALUE() / LAST_VALUE()

获取窗口内第一个或最后一个值。

```sql
-- 每个类别的最高价和最低价
SELECT name, category, price,
       FIRST_VALUE(price) OVER (PARTITION BY category ORDER BY price DESC) AS max_price,
       LAST_VALUE(price) OVER (PARTITION BY category ORDER BY price DESC
           ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS min_price
FROM products;
```

### 6.3 NTILE()

将数据分成N个桶。

```sql
-- 将商品按价格分成4个等级
SELECT name, price,
       NTILE(4) OVER (ORDER BY price) AS price_level
FROM products;
```

---

## 七、实战案例

### 案例1：销量排行榜

```sql
-- 销量前10的商品及其排名
SELECT name, sales,
       RANK() OVER (ORDER BY sales DESC) AS sales_rank
FROM products
WHERE RANK() OVER (ORDER BY sales DESC) <= 10;  -- ❌ 错误

-- ✅ 正确写法
SELECT * FROM (
    SELECT name, sales,
           RANK() OVER (ORDER BY sales DESC) AS sales_rank
    FROM products
) t
WHERE sales_rank <= 10;
```

### 案例2：每个类别的Top 3

```sql
SELECT category, name, price
FROM (
    SELECT category, name, price,
           ROW_NUMBER() OVER (PARTITION BY category ORDER BY price DESC) AS rn
    FROM products
) t
WHERE rn <= 3;
```

### 案例3：同比增长

```sql
-- 计算每月销售额的同比增长
SELECT month,
       sales,
       LAG(sales, 12) OVER (ORDER BY month) AS last_year_sales,
       ROUND((sales - LAG(sales, 12) OVER (ORDER BY month)) / LAG(sales, 12) OVER (ORDER BY month) * 100, 2) AS growth_rate
FROM monthly_sales;
```

---

## 八、性能优化

### 8.1 索引优化

```sql
-- 为PARTITION BY和ORDER BY的列创建索引
CREATE INDEX idx_category_price ON products(category, price);
```

### 8.2 避免重复计算

```sql
-- ❌ 差：LAG计算两次
SELECT price - LAG(price) OVER (ORDER BY id) AS diff
FROM products;

-- ✅ 好：先计算LAG，再做差值
WITH cte AS (
    SELECT price, LAG(price) OVER (ORDER BY id) AS prev_price
    FROM products
)
SELECT price - prev_price AS diff FROM cte;
```

---

## 九、总结

### 核心要点

1. **窗口函数**：不减少行数，可进行复杂分析
2. **ROW_NUMBER**：唯一序号
3. **RANK**：并列排名，有间隔
4. **DENSE_RANK**：并列排名，无间隔
5. **PARTITION BY**：分组
6. **ORDER BY**：排序

### 记忆口诀

```
窗口函数MySQL八，不减行数把计算加，
ROW_NUMBER唯一号，RANK跳跃DENSE紧挨。
PARTITION分组不合并，ORDER排序定先后，
LAG看前LEAD看后，FIRST LAST头尾拿。
```

---

**本文字数**：约3,000字
**难度等级**：⭐⭐⭐（SQL进阶，MySQL 8.0+）
