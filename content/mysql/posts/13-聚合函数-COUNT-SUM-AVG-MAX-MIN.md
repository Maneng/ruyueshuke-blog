---
title: "聚合函数：COUNT、SUM、AVG、MAX、MIN"
date: 2025-11-20T17:00:00+08:00
draft: false
tags: ["MySQL", "SQL查询", "聚合函数", "数据统计"]
categories: ["MySQL"]
description: "深入理解MySQL五大聚合函数的原理与使用，掌握COUNT、SUM、AVG、MAX、MIN的区别和应用场景，学会处理NULL值和去重统计。"
series: ["MySQL从入门到精通"]
weight: 13
stage: 2
stageTitle: "SQL进阶篇"
---

## 引言

在数据分析和报表统计中,我们经常需要对数据进行汇总计算：

- 统计商品总数、总销售额
- 计算平均价格、平均评分
- 找出最高价、最低价
- 统计用户数、订单数

这些需求都需要通过**聚合函数**（Aggregate Functions）来实现。

**为什么聚合函数如此重要？**

1. **数据分析的基础**：90%的报表都需要聚合统计
2. **业务指标计算**：GMV、客单价、转化率等核心指标
3. **性能优化关键**：数据库层面的聚合比应用层效率高
4. **决策支持**：为业务决策提供数据依据

本文将系统讲解MySQL的五大聚合函数，以及它们在实际开发中的应用。

---

## 一、聚合函数基础

### 1.1 什么是聚合函数？

聚合函数对一组值执行计算，返回单个值。

**五大聚合函数**：
- `COUNT()`：计数
- `SUM()`：求和
- `AVG()`：平均值
- `MAX()`：最大值
- `MIN()`：最小值

### 1.2 基本语法

```sql
SELECT aggregate_function(column_name)
FROM table_name
WHERE condition;
```

### 1.3 聚合函数的特点

1. **输入多行，输出一行**：对多条记录进行计算，返回一个结果
2. **忽略NULL值**：除了 `COUNT(*)` 外，其他聚合函数都忽略NULL
3. **可与GROUP BY结合**：对分组后的每组数据分别聚合
4. **不能在WHERE中使用**：WHERE是在聚合之前执行的

### 1.4 准备测试数据

```sql
-- 创建订单表
CREATE TABLE orders (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    product_name VARCHAR(100),
    price DECIMAL(10, 2),
    quantity INT,
    order_date DATE,
    status VARCHAR(20)
);

-- 插入测试数据
INSERT INTO orders (user_id, product_name, price, quantity, order_date, status) VALUES
(1, 'iPhone 15 Pro', 7999.00, 1, '2024-11-01', 'completed'),
(1, 'AirPods Pro', 1999.00, 1, '2024-11-02', 'completed'),
(2, '华为Mate 60', 6999.00, 1, '2024-11-03', 'completed'),
(2, '小米14', 3999.00, 2, '2024-11-04', 'completed'),
(3, 'MacBook Pro', 14999.00, 1, '2024-11-05', 'pending'),
(3, 'iPad Air', 4799.00, 1, '2024-11-06', 'completed'),
(4, '小米13', 3299.00, 1, '2024-11-07', 'cancelled'),
(5, '联想ThinkPad', NULL, 1, '2024-11-08', 'completed'),  -- 价格为NULL
(6, 'AirPods Pro', 1999.00, 2, '2024-11-09', 'completed'),
(7, '索尼WH-1000XM5', 2499.00, 1, '2024-11-10', 'completed');
```

---

## 二、COUNT() - 计数函数

### 2.1 COUNT(*) - 统计总行数

统计所有行数，包括NULL值的行。

```sql
-- 统计订单总数
SELECT COUNT(*) AS total_orders
FROM orders;
```

**结果**：
```
+--------------+
| total_orders |
+--------------+
|           10 |
+--------------+
```

### 2.2 COUNT(column_name) - 统计非NULL值

统计指定列中非NULL值的数量。

```sql
-- 统计有价格的订单数
SELECT COUNT(price) AS orders_with_price
FROM orders;
```

**结果**：
```
+-------------------+
| orders_with_price |
+-------------------+
|                 9 |
+-------------------+
```

**说明**：
- 总共10条订单
- 其中1条price为NULL
- 所以 `COUNT(price)` 返回9

### 2.3 COUNT(1) vs COUNT(*) vs COUNT(列名)

```sql
-- 三种写法对比
SELECT COUNT(*) AS count_star,
       COUNT(1) AS count_one,
       COUNT(price) AS count_price
FROM orders;
```

**结果**：
```
+------------+-----------+-------------+
| count_star | count_one | count_price |
+------------+-----------+-------------+
|         10 |        10 |           9 |
+------------+-----------+-------------+
```

**区别与性能**：

| 写法 | 含义 | 是否统计NULL | 性能 |
|-----|------|-------------|------|
| `COUNT(*)` | 统计行数 | 是 | 最优（InnoDB优化） |
| `COUNT(1)` | 统计行数 | 是 | 与COUNT(*)相同 |
| `COUNT(列名)` | 统计非NULL值 | 否 | 需要判断NULL，稍慢 |

**最佳实践**：
- ✅ 推荐使用 `COUNT(*)`，语义清晰，性能最好
- ❌ 避免使用 `COUNT(主键)`，没有必要

### 2.4 COUNT(DISTINCT column) - 去重计数

统计不重复值的数量。

```sql
-- 统计有多少个不同的用户下过单
SELECT COUNT(DISTINCT user_id) AS unique_users
FROM orders;

-- 统计有多少种不同的商品被购买
SELECT COUNT(DISTINCT product_name) AS unique_products
FROM orders;
```

**结果**：
```
+--------------+
| unique_users |
+--------------+
|            7 |
+--------------+

+-----------------+
| unique_products |
+-----------------+
|            9    |
+-----------------+
```

### 2.5 条件计数

结合WHERE子句进行条件计数：

```sql
-- 统计已完成的订单数
SELECT COUNT(*) AS completed_orders
FROM orders
WHERE status = 'completed';

-- 统计取消的订单数
SELECT COUNT(*) AS cancelled_orders
FROM orders
WHERE status = 'cancelled';

-- 统计价格大于5000的订单数
SELECT COUNT(*) AS high_price_orders
FROM orders
WHERE price > 5000;
```

---

## 三、SUM() - 求和函数

### 3.1 基本用法

对数值列进行求和，忽略NULL值。

```sql
-- 计算订单总金额
SELECT SUM(price) AS total_amount
FROM orders;
```

**结果**：
```
+--------------+
| total_amount |
+--------------+
|     48491.00 |
+--------------+
```

**注意**：SUM会忽略NULL值，所以上面的结果不包括price为NULL的那条订单。

### 3.2 条件求和

```sql
-- 计算已完成订单的总金额
SELECT SUM(price) AS completed_amount
FROM orders
WHERE status = 'completed';

-- 计算某个用户的订单总金额
SELECT SUM(price) AS user_total
FROM orders
WHERE user_id = 1;
```

### 3.3 表达式求和

```sql
-- 计算总销售额（价格 * 数量）
SELECT SUM(price * quantity) AS total_revenue
FROM orders;

-- 计算税后总金额（假设税率10%）
SELECT SUM(price * 1.1) AS total_with_tax
FROM orders;
```

**结果**：
```
+---------------+
| total_revenue |
+---------------+
|     56489.00  |
+---------------+
```

**注意**：如果 `price` 或 `quantity` 任一为NULL，该行的计算结果为NULL，不参与求和。

### 3.4 SUM与NULL的处理

```sql
-- 查看NULL对SUM的影响
SELECT
    SUM(price) AS sum_price,
    SUM(IFNULL(price, 0)) AS sum_with_default
FROM orders;
```

**结果**：
```
+-----------+------------------+
| sum_price | sum_with_default |
+-----------+------------------+
| 48491.00  |        48491.00  |
+-----------+------------------+
```

**说明**：
- `SUM(price)`：忽略NULL，只对非NULL值求和
- `SUM(IFNULL(price, 0))`：将NULL替换为0后求和，结果相同

---

## 四、AVG() - 平均值函数

### 4.1 基本用法

计算数值列的平均值，忽略NULL值。

```sql
-- 计算订单平均价格
SELECT AVG(price) AS avg_price
FROM orders;
```

**结果**：
```
+-----------+
| avg_price |
+-----------+
|  5387.89  |
+-----------+
```

**计算方式**：
```
AVG(price) = SUM(price) / COUNT(price)
           = 48491.00 / 9
           = 5387.89
```

**注意**：AVG忽略NULL，所以分母是9（非NULL值的数量），而不是10（总行数）。

### 4.2 AVG与NULL的陷阱

```sql
-- 对比两种平均值计算
SELECT
    AVG(price) AS avg_ignore_null,
    SUM(price) / COUNT(*) AS avg_include_null
FROM orders;
```

**结果**：
```
+------------------+-------------------+
| avg_ignore_null  | avg_include_null  |
+------------------+-------------------+
|      5387.89     |       4849.10     |
+------------------+-------------------+
```

**差异原因**：
- `AVG(price)`：48491 / 9 = 5387.89（忽略NULL）
- `SUM(price) / COUNT(*)`：48491 / 10 = 4849.10（NULL当做0处理）

**最佳实践**：
- 如果NULL表示"没有值"，使用 `AVG(column)`
- 如果NULL应该当做0，使用 `SUM(column) / COUNT(*)`

### 4.3 条件平均值

```sql
-- 计算已完成订单的平均价格
SELECT AVG(price) AS avg_completed_price
FROM orders
WHERE status = 'completed';

-- 计算价格大于3000的订单平均价格
SELECT AVG(price) AS avg_high_price
FROM orders
WHERE price > 3000;
```

### 4.4 保留小数位数

```sql
-- 保留2位小数
SELECT ROUND(AVG(price), 2) AS avg_price
FROM orders;

-- 向上取整
SELECT CEILING(AVG(price)) AS avg_price_ceil
FROM orders;

-- 向下取整
SELECT FLOOR(AVG(price)) AS avg_price_floor
FROM orders;
```

---

## 五、MAX() 和 MIN() - 极值函数

### 5.1 MAX() - 最大值

```sql
-- 查询最高价格
SELECT MAX(price) AS max_price
FROM orders;
```

**结果**：
```
+-----------+
| max_price |
+-----------+
| 14999.00  |
+-----------+
```

**适用数据类型**：
- 数值类型：比较数值大小
- 字符串类型：按字典顺序比较
- 日期类型：比较时间先后

```sql
-- 查询最新的订单日期
SELECT MAX(order_date) AS latest_order
FROM orders;

-- 查询字典顺序最大的商品名称
SELECT MAX(product_name) AS max_product_name
FROM orders;
```

### 5.2 MIN() - 最小值

```sql
-- 查询最低价格
SELECT MIN(price) AS min_price
FROM orders;

-- 查询最早的订单日期
SELECT MIN(order_date) AS earliest_order
FROM orders;
```

### 5.3 MAX/MIN与NULL

```sql
-- MAX和MIN都忽略NULL值
SELECT
    MAX(price) AS max_price,
    MIN(price) AS min_price
FROM orders;
```

**结果**：
```
+-----------+-----------+
| max_price | min_price |
+-----------+-----------+
| 14999.00  |  1999.00  |
+-----------+-----------+
```

**说明**：即使price列有NULL值，MAX和MIN也会忽略它。

### 5.4 查询极值对应的完整记录

**错误示例**：

```sql
-- ❌ 错误：不能直接这样查询
SELECT product_name, MAX(price)
FROM orders;
-- 这会返回一条记录，但product_name可能不是最高价的那个
```

**正确示例**：

```sql
-- ✅ 方法1：使用子查询
SELECT product_name, price
FROM orders
WHERE price = (SELECT MAX(price) FROM orders);

-- ✅ 方法2：使用ORDER BY + LIMIT
SELECT product_name, price
FROM orders
ORDER BY price DESC
LIMIT 1;

-- ✅ 方法3：使用窗口函数（MySQL 8.0+）
SELECT product_name, price
FROM (
    SELECT product_name, price,
           RANK() OVER (ORDER BY price DESC) AS rk
    FROM orders
) AS t
WHERE rk = 1;
```

---

## 六、聚合函数的组合使用

### 6.1 多个聚合函数一起使用

```sql
-- 一次性获取多个统计指标
SELECT
    COUNT(*) AS total_orders,
    COUNT(DISTINCT user_id) AS unique_users,
    SUM(price * quantity) AS total_revenue,
    AVG(price) AS avg_price,
    MAX(price) AS max_price,
    MIN(price) AS min_price
FROM orders
WHERE status = 'completed';
```

**结果**：
```
+--------------+--------------+---------------+-----------+-----------+-----------+
| total_orders | unique_users | total_revenue | avg_price | max_price | min_price |
+--------------+--------------+---------------+-----------+-----------+-----------+
|            7 |            6 |      32493.00 |  5082.00  | 14999.00  |  1999.00  |
+--------------+--------------+---------------+-----------+-----------+-----------+
```

### 6.2 聚合函数嵌套

**注意**：聚合函数不能直接嵌套！

```sql
-- ❌ 错误：不能嵌套聚合函数
SELECT AVG(SUM(price)) FROM orders;

-- ✅ 正确：使用子查询
SELECT AVG(group_sum) AS avg_of_sum
FROM (
    SELECT user_id, SUM(price) AS group_sum
    FROM orders
    GROUP BY user_id
) AS t;
```

### 6.3 与DISTINCT结合

```sql
-- 去重后求和
SELECT SUM(DISTINCT price) AS sum_distinct_price
FROM orders;
-- 对不同的价格求和（每个价格只算一次）

-- 去重后平均值
SELECT AVG(DISTINCT price) AS avg_distinct_price
FROM orders;
```

---

## 七、聚合函数与NULL的处理

### 7.1 各聚合函数对NULL的处理

| 函数 | 对NULL的处理 | 返回结果 |
|------|------------|---------|
| `COUNT(*)` | 计入统计 | 不受影响 |
| `COUNT(column)` | 忽略NULL | 只统计非NULL |
| `SUM(column)` | 忽略NULL | 只对非NULL求和 |
| `AVG(column)` | 忽略NULL | 分母为非NULL数量 |
| `MAX(column)` | 忽略NULL | 忽略NULL求最大 |
| `MIN(column)` | 忽略NULL | 忽略NULL求最小 |

### 7.2 全部为NULL的情况

```sql
-- 创建测试数据：所有price都为NULL
INSERT INTO orders (user_id, product_name, price, quantity, order_date, status) VALUES
(8, '测试商品1', NULL, 1, '2024-11-11', 'completed'),
(9, '测试商品2', NULL, 1, '2024-11-12', 'completed');

-- 测试聚合函数对全NULL列的处理
SELECT
    COUNT(price) AS count_result,
    SUM(price) AS sum_result,
    AVG(price) AS avg_result,
    MAX(price) AS max_result,
    MIN(price) AS min_result
FROM orders
WHERE user_id IN (8, 9);
```

**结果**：
```
+--------------+------------+------------+------------+------------+
| count_result | sum_result | avg_result | max_result | min_result |
+--------------+------------+------------+------------+------------+
|            0 |       NULL |       NULL |       NULL |       NULL |
+--------------+------------+------------+------------+------------+
```

**说明**：
- `COUNT(price)` 返回0（没有非NULL值）
- 其他聚合函数返回NULL

### 7.3 处理NULL值的技巧

```sql
-- 使用IFNULL或COALESCE避免NULL结果
SELECT
    IFNULL(SUM(price), 0) AS total_amount,
    IFNULL(AVG(price), 0) AS avg_price,
    COALESCE(MAX(price), 0) AS max_price
FROM orders
WHERE user_id = 999;  -- 不存在的用户，返回空结果
```

---

## 八、实战案例

### 案例1：销售报表

**需求**：统计每个商品的销售情况。

```sql
SELECT
    product_name,
    COUNT(*) AS order_count,
    SUM(quantity) AS total_quantity,
    SUM(price * quantity) AS total_revenue,
    AVG(price) AS avg_price
FROM orders
WHERE status = 'completed'
GROUP BY product_name
ORDER BY total_revenue DESC;
```

### 案例2：用户消费分析

**需求**：统计每个用户的消费情况。

```sql
SELECT
    user_id,
    COUNT(*) AS order_count,
    SUM(price * quantity) AS total_spent,
    AVG(price) AS avg_order_price,
    MAX(price) AS max_order_price,
    MIN(price) AS min_order_price
FROM orders
WHERE status = 'completed'
GROUP BY user_id
ORDER BY total_spent DESC;
```

### 案例3：订单状态统计

**需求**：统计各种订单状态的数量和金额。

```sql
SELECT
    status,
    COUNT(*) AS order_count,
    SUM(price * quantity) AS total_amount,
    ROUND(AVG(price), 2) AS avg_price
FROM orders
GROUP BY status;
```

### 案例4：时间维度统计

**需求**：按月统计订单情况。

```sql
SELECT
    DATE_FORMAT(order_date, '%Y-%m') AS month,
    COUNT(*) AS order_count,
    SUM(price * quantity) AS monthly_revenue,
    AVG(price) AS avg_price
FROM orders
WHERE status = 'completed'
GROUP BY DATE_FORMAT(order_date, '%Y-%m')
ORDER BY month;
```

---

## 九、性能优化建议

### 9.1 索引优化

```sql
-- 为经常用于聚合的列创建索引
CREATE INDEX idx_status ON orders(status);
CREATE INDEX idx_order_date ON orders(order_date);
CREATE INDEX idx_user_id ON orders(user_id);
```

### 9.2 避免全表扫描

```sql
-- ❌ 差：全表COUNT，慢
SELECT COUNT(*) FROM orders;

-- ✅ 好：带WHERE条件，能用索引
SELECT COUNT(*) FROM orders WHERE status = 'completed';
```

### 9.3 COUNT优化技巧

```sql
-- 对于InnoDB，COUNT(*)和COUNT(1)性能相同，都优化过
SELECT COUNT(*) FROM orders;  -- 推荐

-- 如果只需要判断是否存在，用EXISTS
SELECT EXISTS(SELECT 1 FROM orders WHERE user_id = 1);
```

### 9.4 聚合函数与覆盖索引

```sql
-- 创建覆盖索引
CREATE INDEX idx_status_price ON orders(status, price);

-- 查询可以只扫描索引，不回表
SELECT status, SUM(price), AVG(price)
FROM orders
GROUP BY status;
```

---

## 十、总结

### 核心要点回顾

1. **COUNT函数**：
   - `COUNT(*)`：统计所有行
   - `COUNT(列名)`：统计非NULL值
   - `COUNT(DISTINCT 列名)`：去重统计
   - 推荐使用 `COUNT(*)`

2. **SUM函数**：
   - 对数值列求和
   - 忽略NULL值
   - 可以对表达式求和

3. **AVG函数**：
   - 计算平均值 = SUM / COUNT
   - 忽略NULL值，分母为非NULL数量
   - 注意NULL的影响

4. **MAX/MIN函数**：
   - 求最大值/最小值
   - 适用于数值、字符串、日期
   - 忽略NULL值

5. **NULL处理**：
   - 除了 `COUNT(*)`，其他聚合函数都忽略NULL
   - 全部为NULL时，返回NULL（COUNT返回0）
   - 使用 `IFNULL` 或 `COALESCE` 处理NULL结果

6. **性能优化**：
   - 为聚合列创建索引
   - 使用覆盖索引避免回表
   - 避免不必要的全表扫描

### 记忆口诀

```
五大聚合常用到，COUNT SUM AVG MAX MIN，
COUNT星号统计行，COUNT列名非空算。
SUM求和AVG平均，MAX最大MIN最小，
NULL值处理要注意，忽略NULL是常态。

COUNT星号最高效，InnoDB已优化，
聚合函数配索引，查询性能大提升。
WHERE之前做过滤，GROUP BY后面聚合，
实战案例多练习，报表统计手到擒。
```

---

## 十一、常见问题（FAQ）

**Q1：为什么COUNT(*)比COUNT(列名)快？**

A：
- `COUNT(*)`：InnoDB会选择最小的索引来扫描，或者直接从索引中统计
- `COUNT(列名)`：需要判断每行的该列是否为NULL，多了一步判断

**Q2：COUNT(1)和COUNT(*)有什么区别？**

A：
- MySQL内部优化后，两者性能完全相同
- `COUNT(*)` 语义更清晰，推荐使用

**Q3：如何统计某个条件的数量？**

A：两种方法：
```sql
-- 方法1：WHERE过滤
SELECT COUNT(*) FROM orders WHERE status = 'completed';

-- 方法2：CASE WHEN（可一次性统计多个条件）
SELECT
    COUNT(CASE WHEN status = 'completed' THEN 1 END) AS completed_count,
    COUNT(CASE WHEN status = 'pending' THEN 1 END) AS pending_count,
    COUNT(CASE WHEN status = 'cancelled' THEN 1 END) AS cancelled_count
FROM orders;
```

**Q4：AVG计算平均值时，NULL应该算0还是忽略？**

A：取决于业务含义：
- NULL表示"没有值"：使用 `AVG(column)`，忽略NULL
- NULL应该当做0：使用 `AVG(IFNULL(column, 0))` 或 `SUM(column) / COUNT(*)`

**Q5：如何查询最大值对应的完整行？**

A：
```sql
-- 方法1：子查询
SELECT * FROM orders WHERE price = (SELECT MAX(price) FROM orders);

-- 方法2：ORDER BY + LIMIT
SELECT * FROM orders ORDER BY price DESC LIMIT 1;

-- 方法3：窗口函数（MySQL 8.0+）
SELECT * FROM (
    SELECT *, RANK() OVER (ORDER BY price DESC) AS rk
    FROM orders
) AS t WHERE rk = 1;
```

---

## 参考资料

1. [MySQL官方文档 - 聚合函数](https://dev.mysql.com/doc/refman/8.0/en/aggregate-functions.html)
2. [MySQL官方文档 - COUNT优化](https://dev.mysql.com/doc/refman/8.0/en/counting-rows.html)
3. 《高性能MySQL》第6章：查询性能优化 - 聚合函数优化
4. 《MySQL实战45讲》- 第14讲：count(*)这么慢，我该怎么办？

---

## 下一篇预告

下一篇我们将学习**《分组查询：GROUP BY与HAVING》**，内容包括：
- GROUP BY分组原理
- 单字段和多字段分组
- HAVING过滤分组结果
- WHERE vs HAVING的区别
- WITH ROLLUP汇总
- 实战案例：销售分析报表

聚合函数配合GROUP BY，就能实现强大的分组统计功能，敬请期待！

---

**本文字数**：约5,800字
**预计阅读时间**：20-25分钟
**难度等级**：⭐⭐（SQL进阶）
