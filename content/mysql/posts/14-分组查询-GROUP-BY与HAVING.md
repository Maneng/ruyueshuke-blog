---
title: "分组查询：GROUP BY与HAVING"
date: 2025-11-21T17:30:00+08:00
draft: false
tags: ["MySQL", "SQL查询", "GROUP BY", "HAVING", "分组统计"]
categories: ["MySQL"]
description: "深入理解GROUP BY分组查询的原理和实践,掌握单字段、多字段分组技巧,理解WHERE与HAVING的区别,学会使用WITH ROLLUP进行汇总统计。"
series: ["MySQL从入门到精通"]
weight: 14
stage: 2
stageTitle: "SQL进阶篇"
---

## 引言

在上一篇我们学习了聚合函数（COUNT、SUM、AVG、MAX、MIN），它们能对整个结果集进行统计。但在实际开发中，我们经常需要**分组统计**：

- 统计每个类别的商品数量和平均价格
- 分析每个用户的订单总额和订单数
- 计算每个月的销售额和订单量
- 按地区统计客户数量和消费金额

这些需求都需要通过 `GROUP BY` 来实现——先分组，再对每组数据进行聚合计算。

**为什么GROUP BY如此重要？**

1. **多维度分析**：从不同角度分析数据（按时间、地区、类别等）
2. **报表统计的核心**：几乎所有报表都需要分组统计
3. **业务洞察**：发现不同群体的差异和规律
4. **决策支持**：为精细化运营提供数据依据

本文将系统讲解GROUP BY的原理、语法、使用技巧，以及HAVING子句的应用。

---

## 一、GROUP BY 基础

### 1.1 什么是分组查询？

**分组查询**将数据按照某个或某些列的值进行分组，然后对每个组分别进行聚合计算。

**执行流程**：
1. **FROM**：确定要查询的表
2. **WHERE**：过滤行（在分组之前）
3. **GROUP BY**：将数据分组
4. **HAVING**：过滤分组（在分组之后）
5. **SELECT**：选择要返回的列和聚合结果
6. **ORDER BY**：对结果排序
7. **LIMIT**：限制返回行数

### 1.2 基本语法

```sql
SELECT column1, aggregate_function(column2)
FROM table_name
WHERE condition
GROUP BY column1
HAVING group_condition
ORDER BY column1;
```

### 1.3 准备测试数据

继续使用上一篇的订单表，并补充一些数据：

```sql
-- 补充更多测试数据
INSERT INTO orders (user_id, product_name, price, quantity, order_date, status) VALUES
(1, '小米13', 3299.00, 1, '2024-11-11', 'completed'),
(2, 'iPad Air', 4799.00, 1, '2024-11-12', 'completed'),
(3, 'AirPods Pro', 1999.00, 1, '2024-11-13', 'completed'),
(4, '华为Mate 60', 6999.00, 1, '2024-11-14', 'completed'),
(5, '小米14', 3999.00, 1, '2024-11-15', 'pending'),
(6, 'MacBook Pro', 14999.00, 1, '2024-11-16', 'completed'),
(7, 'iPhone 15 Pro', 7999.00, 1, '2024-11-17', 'cancelled');
```

---

## 二、单字段分组

### 2.1 基础分组统计

```sql
-- 统计每个用户的订单数量
SELECT user_id, COUNT(*) AS order_count
FROM orders
GROUP BY user_id;
```

**结果**：
```
+---------+-------------+
| user_id | order_count |
+---------+-------------+
|       1 |           3 |
|       2 |           3 |
|       3 |           3 |
|       4 |           2 |
|       5 |           2 |
|       6 |           2 |
|       7 |           2 |
+---------+-------------+
```

**执行过程**：
1. 按 `user_id` 将数据分成多个组
2. 对每个组内的数据执行 `COUNT(*)`
3. 返回每个组的统计结果

### 2.2 分组后的多个聚合

```sql
-- 统计每个用户的订单详情
SELECT
    user_id,
    COUNT(*) AS order_count,
    SUM(price * quantity) AS total_amount,
    AVG(price) AS avg_price,
    MAX(price) AS max_price,
    MIN(price) AS min_price
FROM orders
WHERE status = 'completed'
GROUP BY user_id
ORDER BY total_amount DESC;
```

**结果**：
```
+---------+-------------+--------------+-----------+-----------+-----------+
| user_id | order_count | total_amount | avg_price | max_price | min_price |
+---------+-------------+--------------+-----------+-----------+-----------+
|       6 |           2 |     19798.00 | 11899.00  | 14999.00  |  4799.00  |
|       1 |           3 |     13297.00 |  4432.33  |  7999.00  |  1999.00  |
|       2 |           3 |     15797.00 |  5265.67  |  6999.00  |  3999.00  |
|       3 |           3 |     21797.00 |  7265.67  | 14999.00  |  1999.00  |
|       4 |           2 |     10298.00 |  5149.00  |  6999.00  |  3299.00  |
|       5 |           1 |      2499.00 |  2499.00  |  2499.00  |  2499.00  |
|       7 |           1 |      2499.00 |  2499.00  |  2499.00  |  2499.00  |
+---------+-------------+--------------+-----------+-----------+-----------+
```

### 2.3 按状态分组

```sql
-- 统计各种订单状态的数量和金额
SELECT
    status,
    COUNT(*) AS order_count,
    SUM(price * quantity) AS total_amount,
    ROUND(AVG(price), 2) AS avg_price
FROM orders
GROUP BY status;
```

**结果**：
```
+-----------+-------------+--------------+-----------+
| status    | order_count | total_amount | avg_price |
+-----------+-------------+--------------+-----------+
| completed |          13 |     85486.00 |  5382.17  |
| pending   |           2 |     18998.00 |  9499.00  |
| cancelled |           2 |     11298.00 |  5649.00  |
+-----------+-------------+--------------+-----------+
```

### 2.4 按日期分组

```sql
-- 按日期统计每天的订单数和销售额
SELECT
    order_date,
    COUNT(*) AS daily_orders,
    SUM(price * quantity) AS daily_revenue
FROM orders
WHERE status = 'completed'
GROUP BY order_date
ORDER BY order_date DESC;
```

### 2.5 按月份分组

```sql
-- 按月份统计订单情况
SELECT
    DATE_FORMAT(order_date, '%Y-%m') AS month,
    COUNT(*) AS monthly_orders,
    SUM(price * quantity) AS monthly_revenue,
    ROUND(AVG(price), 2) AS avg_price
FROM orders
WHERE status = 'completed'
GROUP BY DATE_FORMAT(order_date, '%Y-%m')
ORDER BY month;
```

**结果**：
```
+---------+----------------+-----------------+-----------+
| month   | monthly_orders | monthly_revenue | avg_price |
+---------+----------------+-----------------+-----------+
| 2024-11 |             13 |        85486.00 |  5382.17  |
+---------+----------------+-----------------+-----------+
```

---

## 三、多字段分组

### 3.1 基本多字段分组

```sql
-- 按用户和状态分组
SELECT
    user_id,
    status,
    COUNT(*) AS order_count,
    SUM(price * quantity) AS total_amount
FROM orders
GROUP BY user_id, status
ORDER BY user_id, status;
```

**结果**：
```
+---------+-----------+-------------+--------------+
| user_id | status    | order_count | total_amount |
+---------+-----------+-------------+--------------+
|       1 | completed |           2 |     9998.00  |
|       1 | cancelled |           1 |     3299.00  |
|       2 | completed |           3 |    15797.00  |
|       3 | completed |           2 |     6798.00  |
|       3 | pending   |           1 |    14999.00  |
|       4 | completed |           1 |     3299.00  |
|       4 | cancelled |           1 |     6999.00  |
|       5 | completed |           1 |     2499.00  |
|       5 | pending   |           1 |     3999.00  |
|       6 | completed |           2 |    19798.00  |
|       7 | completed |           1 |     2499.00  |
|       7 | cancelled |           1 |     7999.00  |
+---------+-----------+-------------+--------------+
```

**分组逻辑**：
- 先按 `user_id` 分组
- 在每个 `user_id` 组内，再按 `status` 分组
- 相当于二维分组

### 3.2 按商品和日期分组

```sql
-- 统计每个商品每天的销量
SELECT
    product_name,
    DATE(order_date) AS order_date,
    SUM(quantity) AS daily_quantity,
    SUM(price * quantity) AS daily_revenue
FROM orders
WHERE status = 'completed'
GROUP BY product_name, DATE(order_date)
ORDER BY product_name, order_date;
```

### 3.3 多字段分组的顺序

```sql
-- 分组顺序1：先status，后user_id
SELECT status, user_id, COUNT(*) AS cnt
FROM orders
GROUP BY status, user_id;

-- 分组顺序2：先user_id，后status
SELECT user_id, status, COUNT(*) AS cnt
FROM orders
GROUP BY user_id, status;
```

**注意**：分组顺序不影响聚合结果，但影响排序和可读性。

---

## 四、WHERE vs HAVING

### 4.1 两者的区别

| 对比项 | WHERE | HAVING |
|-------|-------|--------|
| 作用时机 | 分组之前 | 分组之后 |
| 过滤对象 | 行 | 组 |
| 能否使用聚合函数 | 否 | 是 |
| 能否使用别名 | 否 | 是（部分数据库） |
| 执行顺序 | 早（先执行） | 晚（后执行） |

### 4.2 WHERE - 分组前过滤

```sql
-- WHERE在分组前过滤：只统计已完成的订单
SELECT user_id, COUNT(*) AS order_count
FROM orders
WHERE status = 'completed'
GROUP BY user_id;
```

**执行流程**：
1. 先用WHERE过滤出 `status = 'completed'` 的行
2. 再对过滤后的数据按 `user_id` 分组
3. 最后统计每组的数量

### 4.3 HAVING - 分组后过滤

```sql
-- HAVING在分组后过滤：只显示订单数大于2的用户
SELECT user_id, COUNT(*) AS order_count
FROM orders
GROUP BY user_id
HAVING COUNT(*) > 2;
```

**结果**：
```
+---------+-------------+
| user_id | order_count |
+---------+-------------+
|       1 |           3 |
|       2 |           3 |
|       3 |           3 |
+---------+-------------+
```

**执行流程**：
1. 先按 `user_id` 分组
2. 对每组统计 `COUNT(*)`
3. 用HAVING过滤出 `COUNT(*) > 2` 的组

### 4.4 WHERE和HAVING同时使用

```sql
-- 统计已完成订单数大于1的用户的消费情况
SELECT
    user_id,
    COUNT(*) AS order_count,
    SUM(price * quantity) AS total_amount
FROM orders
WHERE status = 'completed'  -- 分组前过滤
GROUP BY user_id
HAVING COUNT(*) > 1  -- 分组后过滤
ORDER BY total_amount DESC;
```

**执行流程**：
1. **WHERE**：过滤出已完成的订单
2. **GROUP BY**：按用户分组
3. **HAVING**：过滤出订单数大于1的用户
4. **ORDER BY**：按总金额降序排列

### 4.5 HAVING中使用别名

```sql
-- HAVING可以使用SELECT中定义的别名（MySQL支持）
SELECT
    user_id,
    COUNT(*) AS order_count,
    SUM(price * quantity) AS total_amount
FROM orders
WHERE status = 'completed'
GROUP BY user_id
HAVING total_amount > 10000  -- 使用别名
ORDER BY total_amount DESC;
```

**注意**：
- MySQL支持在HAVING中使用别名
- 标准SQL不支持（因为逻辑上HAVING在SELECT之前执行）
- 为了兼容性，建议使用完整表达式：`HAVING SUM(price * quantity) > 10000`

---

## 五、GROUP BY的高级用法

### 5.1 WITH ROLLUP - 汇总统计

`WITH ROLLUP` 会在分组结果的基础上，额外增加一行汇总数据。

```sql
-- 按状态分组，并添加总计行
SELECT
    status,
    COUNT(*) AS order_count,
    SUM(price * quantity) AS total_amount
FROM orders
GROUP BY status WITH ROLLUP;
```

**结果**：
```
+-----------+-------------+--------------+
| status    | order_count | total_amount |
+-----------+-------------+--------------+
| cancelled |           2 |     11298.00 |
| completed |          13 |     85486.00 |
| pending   |           2 |     18998.00 |
| NULL      |          17 |    115782.00 | <-- 总计行
+-----------+-------------+--------------+
```

**说明**：
- 最后一行的 `status` 为 `NULL`
- 这一行是所有分组的汇总数据

**多字段WITH ROLLUP**：

```sql
-- 按用户和状态分组，多层汇总
SELECT
    user_id,
    status,
    COUNT(*) AS order_count,
    SUM(price * quantity) AS total_amount
FROM orders
GROUP BY user_id, status WITH ROLLUP;
```

**结果**：
```
+---------+-----------+-------------+--------------+
| user_id | status    | order_count | total_amount |
+---------+-----------+-------------+--------------+
|       1 | cancelled |           1 |     3299.00  |
|       1 | completed |           2 |     9998.00  |
|       1 | NULL      |           3 |    13297.00  | <-- user_id=1的小计
|       2 | completed |           3 |    15797.00  |
|       2 | NULL      |           3 |    15797.00  | <-- user_id=2的小计
|       3 | completed |           2 |     6798.00  |
|       3 | pending   |           1 |    14999.00  |
|       3 | NULL      |           3 |    21797.00  | <-- user_id=3的小计
|     ... | ...       |         ... |          ... |
|    NULL | NULL      |          17 |   115782.00  | <-- 总计
+---------+-----------+-------------+--------------+
```

**识别汇总行**：

```sql
-- 使用GROUPING()函数判断是否为汇总行
SELECT
    IF(GROUPING(status) = 1, '总计', status) AS status,
    COUNT(*) AS order_count,
    SUM(price * quantity) AS total_amount
FROM orders
GROUP BY status WITH ROLLUP;
```

### 5.2 按表达式分组

```sql
-- 按价格区间分组
SELECT
    CASE
        WHEN price < 2000 THEN '低价'
        WHEN price BETWEEN 2000 AND 5000 THEN '中价'
        WHEN price > 5000 THEN '高价'
        ELSE '未知'
    END AS price_range,
    COUNT(*) AS product_count,
    ROUND(AVG(price), 2) AS avg_price
FROM orders
WHERE price IS NOT NULL
GROUP BY
    CASE
        WHEN price < 2000 THEN '低价'
        WHEN price BETWEEN 2000 AND 5000 THEN '中价'
        WHEN price > 5000 THEN '高价'
        ELSE '未知'
    END;
```

### 5.3 DISTINCT与GROUP BY

```sql
-- 方法1：使用DISTINCT
SELECT DISTINCT user_id FROM orders;

-- 方法2：使用GROUP BY
SELECT user_id FROM orders GROUP BY user_id;
```

**性能对比**：
- 两者在MySQL中通常性能相近
- `GROUP BY` 可以配合聚合函数使用，更灵活
- `DISTINCT` 语义更清晰，适合单纯去重

---

## 六、GROUP BY的陷阱与规范

### 6.1 SELECT列必须在GROUP BY中或是聚合函数

**错误示例**：

```sql
-- ❌ 错误：product_name不在GROUP BY中，也不是聚合函数
SELECT user_id, product_name, COUNT(*)
FROM orders
GROUP BY user_id;
```

**MySQL 5.7+默认行为**：
- 开启了 `ONLY_FULL_GROUP_BY` 模式
- 上述查询会报错：`Expression #2 of SELECT list is not in GROUP BY clause`

**正确示例**：

```sql
-- ✅ 方法1：把product_name加入GROUP BY
SELECT user_id, product_name, COUNT(*)
FROM orders
GROUP BY user_id, product_name;

-- ✅ 方法2：对product_name使用聚合函数
SELECT user_id, GROUP_CONCAT(product_name) AS products, COUNT(*)
FROM orders
GROUP BY user_id;

-- ✅ 方法3：只选择GROUP BY的列和聚合函数
SELECT user_id, COUNT(*)
FROM orders
GROUP BY user_id;
```

### 6.2 GROUP BY的列顺序

```sql
-- GROUP BY的列顺序不影响结果，但影响执行计划
GROUP BY user_id, status
-- 与下面等价
GROUP BY status, user_id
```

**最佳实践**：
- 将过滤性强（区分度高）的列放在前面
- 与索引顺序保持一致，有助于优化

### 6.3 NULL值的分组

```sql
-- 插入包含NULL的测试数据
INSERT INTO orders (user_id, product_name, price, quantity, order_date, status) VALUES
(NULL, '测试商品', 100.00, 1, '2024-11-20', 'completed');

-- NULL值会作为一个单独的分组
SELECT user_id, COUNT(*) AS cnt
FROM orders
GROUP BY user_id;
```

**结果**：
```
+---------+-----+
| user_id | cnt |
+---------+-----+
|    NULL |   1 |  <-- NULL单独一组
|       1 |   3 |
|       2 |   3 |
|     ... | ... |
+---------+-----+
```

---

## 七、实战案例

### 案例1：销售报表

**需求**：按月统计销售情况，包括订单数、销售额、平均客单价。

```sql
SELECT
    DATE_FORMAT(order_date, '%Y-%m') AS month,
    COUNT(*) AS order_count,
    COUNT(DISTINCT user_id) AS customer_count,
    SUM(price * quantity) AS total_revenue,
    ROUND(AVG(price * quantity), 2) AS avg_order_value,
    MAX(price * quantity) AS max_order_value
FROM orders
WHERE status = 'completed'
GROUP BY DATE_FORMAT(order_date, '%Y-%m')
ORDER BY month;
```

### 案例2：用户消费分析

**需求**：分析用户消费情况，找出高价值客户（消费总额 > 15000）。

```sql
SELECT
    user_id,
    COUNT(*) AS order_count,
    SUM(price * quantity) AS total_spent,
    ROUND(AVG(price * quantity), 2) AS avg_order_value,
    MAX(order_date) AS last_order_date
FROM orders
WHERE status = 'completed'
GROUP BY user_id
HAVING total_spent > 15000
ORDER BY total_spent DESC;
```

### 案例3：商品销售排行

**需求**：统计每个商品的销量，并按销量降序排列。

```sql
SELECT
    product_name,
    SUM(quantity) AS total_quantity,
    COUNT(*) AS order_count,
    SUM(price * quantity) AS total_revenue,
    ROUND(AVG(price), 2) AS avg_price
FROM orders
WHERE status = 'completed'
GROUP BY product_name
ORDER BY total_quantity DESC
LIMIT 10;
```

### 案例4：多维度分析

**需求**：按月份和订单状态统计，使用WITH ROLLUP汇总。

```sql
SELECT
    DATE_FORMAT(order_date, '%Y-%m') AS month,
    status,
    COUNT(*) AS order_count,
    SUM(price * quantity) AS total_amount
FROM orders
GROUP BY DATE_FORMAT(order_date, '%Y-%m'), status WITH ROLLUP;
```

### 案例5：用户分层

**需求**：根据消费金额将用户分为不同层级。

```sql
SELECT
    CASE
        WHEN total_spent >= 20000 THEN 'VIP用户'
        WHEN total_spent >= 10000 THEN '高价值用户'
        WHEN total_spent >= 5000 THEN '普通用户'
        ELSE '低活用户'
    END AS user_level,
    COUNT(*) AS user_count,
    ROUND(AVG(total_spent), 2) AS avg_spent
FROM (
    SELECT user_id, SUM(price * quantity) AS total_spent
    FROM orders
    WHERE status = 'completed'
    GROUP BY user_id
) AS user_stats
GROUP BY
    CASE
        WHEN total_spent >= 20000 THEN 'VIP用户'
        WHEN total_spent >= 10000 THEN '高价值用户'
        WHEN total_spent >= 5000 THEN '普通用户'
        ELSE '低活用户'
    END
ORDER BY avg_spent DESC;
```

---

## 八、性能优化

### 8.1 索引优化

```sql
-- 为GROUP BY的列创建索引
CREATE INDEX idx_user_id ON orders(user_id);
CREATE INDEX idx_status ON orders(status);
CREATE INDEX idx_order_date ON orders(order_date);

-- 联合索引（覆盖GROUP BY和WHERE）
CREATE INDEX idx_status_user_id ON orders(status, user_id);
```

### 8.2 使用覆盖索引

```sql
-- 创建覆盖索引
CREATE INDEX idx_status_price ON orders(status, price, quantity);

-- 查询可以只扫描索引，不回表
SELECT status, SUM(price * quantity) AS total
FROM orders
GROUP BY status;
```

### 8.3 避免filesort

```sql
-- ❌ 差：GROUP BY后ORDER BY不同的列，产生filesort
SELECT user_id, COUNT(*) AS cnt
FROM orders
GROUP BY user_id
ORDER BY order_date;  -- 额外排序

-- ✅ 好：GROUP BY和ORDER BY使用相同的列
SELECT user_id, COUNT(*) AS cnt
FROM orders
GROUP BY user_id
ORDER BY user_id;  -- 利用分组已有的顺序
```

### 8.4 减少分组数据量

```sql
-- ❌ 差：先GROUP BY再WHERE过滤
SELECT user_id, COUNT(*) AS cnt
FROM orders
GROUP BY user_id
HAVING status = 'completed';  -- 错误，status不能在HAVING中直接判断

-- ✅ 好：先WHERE过滤再GROUP BY
SELECT user_id, COUNT(*) AS cnt
FROM orders
WHERE status = 'completed'
GROUP BY user_id;
```

---

## 九、总结

### 核心要点回顾

1. **GROUP BY基础**：
   - 将数据分组，对每组进行聚合计算
   - 执行顺序：WHERE → GROUP BY → HAVING → SELECT → ORDER BY → LIMIT
   - SELECT的列必须在GROUP BY中或是聚合函数

2. **单字段vs多字段分组**：
   - 单字段：按一个维度分组
   - 多字段：按多个维度组合分组（相当于多维分组）

3. **WHERE vs HAVING**：
   - WHERE：分组前过滤行，不能使用聚合函数
   - HAVING：分组后过滤组，可以使用聚合函数
   - 两者可以同时使用

4. **WITH ROLLUP**：
   - 在分组结果基础上增加汇总行
   - 多字段分组时会产生多层汇总

5. **性能优化**：
   - 为GROUP BY列创建索引
   - 使用覆盖索引避免回表
   - WHERE先过滤，减少分组数据量
   - GROUP BY和ORDER BY使用相同列

### 记忆口诀

```
GROUP BY分组很关键，聚合统计离不开，
单字段分组一维看，多字段分组多维展。
WHERE分组前过滤，HAVING分组后筛选，
前者过滤行数据，后者过滤组聚合。

SELECT列要记牢，GROUP BY中或聚合找，
WITH ROLLUP加汇总，多层分组层层套。
索引优化不能少，覆盖索引最高效，
WHERE先过滤数据，GROUP BY性能好。
```

---

## 十、常见问题（FAQ）

**Q1：SELECT的列为什么必须在GROUP BY中或是聚合函数？**

A：因为GROUP BY会将多行合并为一行，如果SELECT的列不在GROUP BY中，MySQL不知道返回哪一行的值。例如：
```sql
SELECT user_id, product_name, COUNT(*)
FROM orders
GROUP BY user_id;
-- 一个user_id可能对应多个product_name，应该返回哪个？
```

**Q2：GROUP BY和DISTINCT有什么区别？**

A：
- `DISTINCT`：单纯去重
- `GROUP BY`：分组 + 聚合
- 性能相近，但GROUP BY更灵活（可配合聚合函数）

**Q3：为什么HAVING比WHERE慢？**

A：
- WHERE在分组前过滤，减少了参与分组的数据量
- HAVING在分组后过滤，需要先对所有数据分组
- 能用WHERE解决的不要用HAVING

**Q4：如何统计每组的前N条记录？**

A：使用窗口函数（MySQL 8.0+）：
```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY order_date DESC) AS rn
    FROM orders
) AS t
WHERE rn <= 3;
```

**Q5：GROUP BY能使用别名吗？**

A：
- MySQL允许在GROUP BY中使用SELECT定义的别名
- 但标准SQL不允许（因为逻辑上GROUP BY在SELECT之前）
- 为了兼容性，建议不使用别名

---

## 参考资料

1. [MySQL官方文档 - GROUP BY优化](https://dev.mysql.com/doc/refman/8.0/en/group-by-optimization.html)
2. [MySQL官方文档 - HAVING子句](https://dev.mysql.com/doc/refman/8.0/en/having.html)
3. [MySQL官方文档 - WITH ROLLUP](https://dev.mysql.com/doc/refman/8.0/en/group-by-modifiers.html)
4. 《高性能MySQL》第6章：查询性能优化 - 分组查询优化
5. 《MySQL实战45讲》- 第17讲：如何正确地显示随机消息？

---

## 下一篇预告

下一篇我们将学习**《多表连接：INNER JOIN、LEFT JOIN、RIGHT JOIN》**，内容包括：
- 连接的本质：笛卡尔积
- INNER JOIN、LEFT JOIN、RIGHT JOIN的区别
- FULL JOIN的替代方案
- ON vs WHERE in JOIN
- 多表连接的性能优化
- 实战案例：订单、用户、商品三表联查

掌握GROUP BY后，再学习多表连接，你就能应对复杂的业务查询了！

---

**本文字数**：约6,200字
**预计阅读时间**：22-28分钟
**难度等级**：⭐⭐⭐（SQL进阶）
