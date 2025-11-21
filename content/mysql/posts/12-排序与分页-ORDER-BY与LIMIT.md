---
title: "排序与分页：ORDER BY与LIMIT"
date: 2025-11-20T16:30:00+08:00
draft: false
tags: ["MySQL", "SQL查询", "排序", "分页", "性能优化"]
categories: ["MySQL"]
description: "深入理解ORDER BY排序和LIMIT分页的原理与实践，掌握单字段、多字段排序技巧，解决深分页性能问题，实现高效的数据查询。"
series: ["MySQL从入门到精通"]
weight: 12
stage: 2
stageTitle: "SQL进阶篇"
---

## 引言

在实际开发中，我们经常需要对查询结果进行排序和分页：

- 商品列表按价格从低到高排序
- 文章列表按发布时间倒序显示
- 用户列表分页展示，每页20条
- 排行榜按得分从高到低排序

这些需求都需要通过 `ORDER BY` 和 `LIMIT` 来实现。

**为什么排序和分页如此重要？**

1. **用户体验**：有序的数据更符合用户的阅读习惯
2. **性能优化**：分页可以减少数据传输量，提升响应速度
3. **业务需求**：排行榜、Top N查询等场景必不可少
4. **数据管理**：便于数据的浏览和检索

本文将深入讲解排序和分页的原理、语法、性能优化技巧，以及如何解决深分页问题。

---

## 一、ORDER BY 排序基础

### 1.1 基本语法

```sql
SELECT column1, column2, ...
FROM table_name
WHERE condition
ORDER BY column1 [ASC|DESC], column2 [ASC|DESC], ...;
```

**执行顺序**：
1. **FROM**：确定要查询的表
2. **WHERE**：过滤出符合条件的行
3. **ORDER BY**：对结果进行排序
4. **SELECT**：选择要返回的列

**排序方向**：
- `ASC`：升序（Ascending），从小到大，**默认值**
- `DESC`：降序（Descending），从大到小

### 1.2 准备测试数据

继续使用上一篇的商品表，并添加一些新数据：

```sql
-- 补充更多测试数据
INSERT INTO products (name, category, price, stock, created_at, description) VALUES
('iPhone 14', '手机', 5999.00, 100, '2024-09-01', 'Apple上代旗舰'),
('小米13', '手机', 3299.00, 150, '2024-03-15', '小米上代旗舰'),
('华为P60', '手机', 4999.00, 80, '2024-04-20', '华为影像旗舰'),
('戴尔XPS', '电脑', 9999.00, 25, '2024-05-10', '戴尔高端笔记本'),
('Surface Pro', '平板', 6999.00, 40, '2024-06-15', '微软二合一平板');
```

---

## 二、单字段排序

### 2.1 数值字段排序

```sql
-- 按价格升序排列（从低到高）
SELECT name, price
FROM products
ORDER BY price ASC;

-- 等价写法（ASC可省略）
SELECT name, price
FROM products
ORDER BY price;
```

**结果**：
```
+------------------+--------+
| name             | price  |
+------------------+--------+
| 罗技MX Master    | 699.00 |
| AirPods Pro      |1999.00 |
| 小米平板6        |1999.00 |
| 索尼WH-1000XM5   |2499.00 |
| 小米13           |3299.00 |
| 小米14           |3999.00 |
| iPad Air         |4799.00 |
| 华为P60          |4999.00 |
| iPhone 14        |5999.00 |
| 华为Mate 60      |6999.00 |
| Surface Pro      |6999.00 |
| iPhone 15 Pro    |7999.00 |
| 联想ThinkPad     |8999.00 |
| 戴尔XPS          |9999.00 |
| MacBook Pro      |14999.00|
+------------------+--------+
```

```sql
-- 按价格降序排列（从高到低）
SELECT name, price
FROM products
ORDER BY price DESC;
```

**结果**：价格从高到低，MacBook Pro排在第一位。

### 2.2 字符串字段排序

```sql
-- 按名称字母顺序排列
SELECT name, category
FROM products
ORDER BY name;

-- 按名称逆字母顺序排列
SELECT name, category
FROM products
ORDER BY name DESC;
```

**字符串排序规则**：
- 遵循字符集的校对规则（Collation）
- 中文按拼音或笔画排序（取决于校对规则）
- 英文按字母顺序排序
- 大小写敏感性取决于校对规则

```sql
-- 查看表的字符集和校对规则
SHOW CREATE TABLE products;
```

### 2.3 日期字段排序

```sql
-- 按创建时间升序（最早的在前）
SELECT name, created_at
FROM products
ORDER BY created_at ASC;

-- 按创建时间降序（最新的在前）
SELECT name, created_at
FROM products
ORDER BY created_at DESC;
```

**结果**（降序）：
```
+------------------+-------------+
| name             | created_at  |
+------------------+-------------+
| 小米14           | 2024-10-01  |
| iPhone 15 Pro    | 2024-09-20  |
| iPhone 14        | 2024-09-01  |
| AirPods Pro      | 2024-09-01  |
| ...              | ...         |
+------------------+-------------+
```

---

## 三、多字段排序

当第一个字段的值相同时，按第二个字段排序；第二个字段也相同时，按第三个字段排序，以此类推。

### 3.1 基本多字段排序

```sql
-- 先按类别升序，再按价格降序
SELECT name, category, price
FROM products
ORDER BY category ASC, price DESC;
```

**执行逻辑**：
1. 先按 `category` 分组（但不是GROUP BY，只是排序）
2. 在同一类别内，按 `price` 降序排列

**结果**：
```
+------------------+----------+--------+
| name             | category | price  |
+------------------+----------+--------+
| 戴尔XPS          | 电脑     |9999.00 |
| MacBook Pro      | 电脑     |14999.00|
| 联想ThinkPad     | 电脑     |8999.00 |
| 索尼WH-1000XM5   | 耳机     |2499.00 |
| AirPods Pro      | 耳机     |1999.00 |
| 罗技MX Master    | 鼠标     |699.00  |
| iPhone 15 Pro    | 手机     |7999.00 |
| 华为Mate 60      | 手机     |6999.00 |
| iPhone 14        | 手机     |5999.00 |
| ...              | ...      | ...    |
+------------------+----------+--------+
```

### 3.2 不同排序方向组合

```sql
-- 类别升序，价格降序，库存升序
SELECT name, category, price, stock
FROM products
ORDER BY category ASC, price DESC, stock ASC;
```

**应用场景**：
- 电商网站：类别 → 销量 → 价格
- 论坛：版块 → 置顶 → 发帖时间
- 游戏排行榜：等级 → 经验值 → 注册时间

### 3.3 NULL值的排序

MySQL中，NULL值在排序时有特殊处理：

```sql
-- 添加包含NULL的测试数据
INSERT INTO products (name, category, price, stock, created_at) VALUES
('测试商品1', NULL, 100.00, 10, '2024-11-20');

-- ASC排序：NULL值排在最前面
SELECT name, category FROM products ORDER BY category ASC;

-- DESC排序：NULL值排在最后面
SELECT name, category FROM products ORDER BY category DESC;
```

**NULL排序规则**：
- `ORDER BY column ASC`：NULL值排在最前面
- `ORDER BY column DESC`：NULL值排在最后面

---

## 四、LIMIT 分页查询

### 4.1 基本语法

```sql
-- 语法1：只指定返回的行数
SELECT * FROM table_name LIMIT n;

-- 语法2：指定起始位置和行数
SELECT * FROM table_name LIMIT offset, row_count;

-- 语法3：MySQL 8.0+ 推荐语法
SELECT * FROM table_name LIMIT row_count OFFSET offset;
```

**参数说明**：
- `offset`：起始位置，从0开始计数
- `row_count`：返回的行数

### 4.2 获取前N条记录

```sql
-- 获取价格最高的5个商品
SELECT name, price
FROM products
ORDER BY price DESC
LIMIT 5;
```

**结果**：
```
+------------------+--------+
| name             | price  |
+------------------+--------+
| MacBook Pro      |14999.00|
| 戴尔XPS          |9999.00 |
| 联想ThinkPad     |8999.00 |
| iPhone 15 Pro    |7999.00 |
| 华为Mate 60      |6999.00 |
+------------------+--------+
```

### 4.3 分页查询

```sql
-- 第1页：前10条记录（offset = 0）
SELECT name, price
FROM products
ORDER BY price DESC
LIMIT 10 OFFSET 0;

-- 等价写法
SELECT name, price
FROM products
ORDER BY price DESC
LIMIT 0, 10;

-- 第2页：第11-20条记录（offset = 10）
SELECT name, price
FROM products
ORDER BY price DESC
LIMIT 10 OFFSET 10;

-- 第3页：第21-30条记录（offset = 20）
SELECT name, price
FROM products
ORDER BY price DESC
LIMIT 10 OFFSET 20;
```

**分页公式**：
```
每页大小：pageSize
当前页码：pageNum（从1开始）
offset = (pageNum - 1) * pageSize
```

### 4.4 实战案例：商品列表分页

```sql
-- 商品列表分页，每页20条，按价格降序
-- 第1页
SELECT id, name, category, price, stock
FROM products
ORDER BY price DESC
LIMIT 20 OFFSET 0;

-- 第2页
SELECT id, name, category, price, stock
FROM products
ORDER BY price DESC
LIMIT 20 OFFSET 20;

-- 第N页（N从1开始）
SELECT id, name, category, price, stock
FROM products
ORDER BY price DESC
LIMIT 20 OFFSET ((N - 1) * 20);
```

### 4.5 获取总记录数

分页时通常需要知道总记录数，用于计算总页数：

```sql
-- 获取符合条件的总记录数
SELECT COUNT(*) AS total
FROM products
WHERE category = '手机';

-- 结合WHERE和分页
SELECT name, price
FROM products
WHERE category = '手机'
ORDER BY price DESC
LIMIT 10 OFFSET 0;
```

---

## 五、排序与分页的性能优化

### 5.1 索引对排序的影响

**无索引排序**：使用 `filesort`（文件排序），性能较差。

```sql
-- 假设price字段没有索引
SELECT name, price FROM products ORDER BY price;
-- 执行计划：Extra = "Using filesort"
```

**有索引排序**：直接利用索引的有序性，性能好。

```sql
-- 为price字段创建索引
CREATE INDEX idx_price ON products(price);

-- 再次排序
SELECT name, price FROM products ORDER BY price;
-- 执行计划：Extra = "Using index"
```

**最佳实践**：
- ✅ 为经常排序的字段创建索引
- ✅ 联合索引的最左前缀可用于排序
- ❌ 避免对大量数据进行filesort

### 5.2 覆盖索引优化排序

```sql
-- 创建联合索引
CREATE INDEX idx_category_price ON products(category, price);

-- 查询可以完全利用索引（覆盖索引）
SELECT category, price
FROM products
WHERE category = '手机'
ORDER BY price;
-- Extra = "Using where; Using index"（不需要回表）
```

### 5.3 深分页性能问题

**问题场景**：

```sql
-- 翻到第1000页，每页20条
SELECT * FROM products
ORDER BY created_at DESC
LIMIT 20 OFFSET 19980;  -- offset = (1000-1) * 20
```

**性能问题**：
- MySQL需要扫描前面的19980+20=20000行
- 然后丢弃前19980行，只返回最后20行
- 翻页越深，性能越差

**解决方案1：延迟关联（Deferred Join）**

```sql
-- 只对ID进行分页，然后关联回原表
SELECT p.*
FROM products p
INNER JOIN (
    SELECT id
    FROM products
    ORDER BY created_at DESC
    LIMIT 20 OFFSET 19980
) AS t ON p.id = t.id;
```

**原理**：
- 子查询只选择ID，数据量小，速度快
- 利用主键索引快速定位，然后关联回完整数据

**解决方案2：标签记录法（Bookmark Method）**

```sql
-- 记录上一页最后一条记录的ID和时间
-- 第1页
SELECT * FROM products
ORDER BY created_at DESC, id DESC
LIMIT 20;
-- 假设最后一条记录：created_at='2024-06-15', id=100

-- 第2页（不使用OFFSET）
SELECT * FROM products
WHERE created_at <= '2024-06-15'
  AND (created_at < '2024-06-15' OR id < 100)
ORDER BY created_at DESC, id DESC
LIMIT 20;
```

**优点**：
- 不使用OFFSET，性能稳定
- 无论翻到哪一页，速度都一样快

**缺点**：
- 不支持跳页（只能上一页、下一页）
- 前端实现稍复杂

**解决方案3：游标分页（适用于API）**

```sql
-- 返回数据时同时返回游标（最后一条记录的ID）
SELECT id, name, created_at
FROM products
WHERE id < :lastId  -- lastId是上一页最后一条的ID
ORDER BY id DESC
LIMIT 20;
```

**适用场景**：
- 移动端下拉刷新
- 无限滚动加载
- API分页

### 5.4 分页优化最佳实践

1. **限制最大页数**
   ```sql
   -- 限制只能翻到第100页
   IF pageNum > 100 THEN
       RETURN error("超出最大页数");
   END IF;
   ```

2. **使用ES等搜索引擎**
   - 对于深分页场景，使用Elasticsearch等专业搜索引擎
   - 它们对深分页有更好的优化

3. **缓存热点数据**
   - 前几页的数据缓存到Redis
   - 减少数据库查询压力

4. **引导用户使用搜索**
   - 而不是无限翻页
   - 提供筛选条件，缩小结果集

---

## 六、ORDER BY与LIMIT的组合技巧

### 6.1 Top N 查询

```sql
-- 查询价格最高的前10个商品
SELECT name, price
FROM products
ORDER BY price DESC
LIMIT 10;

-- 查询每个类别价格最高的商品（MySQL 8.0+）
SELECT * FROM (
    SELECT name, category, price,
           ROW_NUMBER() OVER (PARTITION BY category ORDER BY price DESC) AS rn
    FROM products
) AS t
WHERE rn = 1;
```

### 6.2 随机获取N条记录

```sql
-- 随机获取5个商品
SELECT name, price
FROM products
ORDER BY RAND()
LIMIT 5;
```

**⚠️ 性能警告**：
- `RAND()` 会对每一行计算随机数，性能差
- 大表不推荐使用
- 替代方案：先随机获取ID，再查询详情

```sql
-- 性能优化版本
SELECT p.*
FROM products p
INNER JOIN (
    SELECT id
    FROM products
    WHERE id >= FLOOR(RAND() * (SELECT MAX(id) FROM products))
    LIMIT 5
) AS t ON p.id = t.id;
```

### 6.3 分组后排序

```sql
-- 每个类别选出价格最高的前3个商品（MySQL 8.0+）
SELECT name, category, price
FROM (
    SELECT name, category, price,
           ROW_NUMBER() OVER (PARTITION BY category ORDER BY price DESC) AS rn
    FROM products
) AS t
WHERE rn <= 3;
```

---

## 七、常见问题与误区

### 7.1 ORDER BY的位置

```sql
-- ❌ 错误：ORDER BY不能在WHERE之前
SELECT * FROM products
ORDER BY price
WHERE category = '手机';

-- ✅ 正确：ORDER BY必须在WHERE之后
SELECT * FROM products
WHERE category = '手机'
ORDER BY price;
```

**SQL语句顺序**：
```
SELECT -> FROM -> WHERE -> GROUP BY -> HAVING -> ORDER BY -> LIMIT
```

### 7.2 ORDER BY与GROUP BY的关系

```sql
-- 错误示例：SELECT的列不在GROUP BY中，也不是聚合函数
SELECT category, name, AVG(price)
FROM products
GROUP BY category
ORDER BY AVG(price) DESC;
-- ❌ name不在GROUP BY中，结果不确定

-- 正确示例
SELECT category, AVG(price) AS avg_price, COUNT(*) AS cnt
FROM products
GROUP BY category
ORDER BY avg_price DESC;
```

### 7.3 LIMIT的负数和超出范围

```sql
-- LIMIT不能使用负数
SELECT * FROM products LIMIT -10;  -- ❌ 错误

-- OFFSET超出范围不会报错，只是返回空结果
SELECT * FROM products LIMIT 10 OFFSET 1000000;  -- ✅ 返回空结果
```

### 7.4 排序字段的数据类型

```sql
-- 如果price是VARCHAR类型
-- '100' > '90' 为FALSE（按字符串比较）
SELECT name, price FROM products ORDER BY price;
-- 结果：'100'会排在'90'前面

-- 正确做法：使用数值类型或强制类型转换
SELECT name, price FROM products ORDER BY CAST(price AS DECIMAL(10,2));
```

---

## 八、实战案例

### 案例1：电商商品列表排序

**需求**：商品列表支持多种排序方式（价格、销量、评分、新品）

```sql
-- 按价格升序
SELECT id, name, price, sales, rating
FROM products
WHERE category = '手机' AND stock > 0
ORDER BY price ASC
LIMIT 20 OFFSET 0;

-- 按销量降序
SELECT id, name, price, sales, rating
FROM products
WHERE category = '手机' AND stock > 0
ORDER BY sales DESC, price ASC
LIMIT 20 OFFSET 0;

-- 按评分降序
SELECT id, name, price, sales, rating
FROM products
WHERE category = '手机' AND stock > 0
ORDER BY rating DESC, sales DESC
LIMIT 20 OFFSET 0;

-- 按上架时间降序（新品优先）
SELECT id, name, price, sales, created_at
FROM products
WHERE category = '手机' AND stock > 0
ORDER BY created_at DESC
LIMIT 20 OFFSET 0;
```

### 案例2：排行榜查询

**需求**：显示销量Top 10的商品

```sql
SELECT RANK() OVER (ORDER BY sales DESC) AS ranking,
       name,
       category,
       sales,
       price
FROM products
WHERE created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
ORDER BY sales DESC
LIMIT 10;
```

### 案例3：优化后的分页查询

**需求**：大数据量下的高性能分页

```sql
-- 使用延迟关联优化
SELECT p.id, p.name, p.category, p.price
FROM products p
INNER JOIN (
    SELECT id
    FROM products
    WHERE category = '手机'
    ORDER BY price DESC
    LIMIT 20 OFFSET 980
) AS t ON p.id = t.id;
```

---

## 九、总结

### 核心要点回顾

1. **ORDER BY排序**：
   - 单字段排序：`ORDER BY column [ASC|DESC]`
   - 多字段排序：第一字段相同时按第二字段排序
   - NULL值：ASC时排在前面，DESC时排在后面
   - 默认升序（ASC），可省略

2. **LIMIT分页**：
   - 语法：`LIMIT n` 或 `LIMIT offset, row_count`
   - offset从0开始计数
   - 分页公式：`offset = (pageNum - 1) * pageSize`

3. **性能优化**：
   - 为排序字段创建索引
   - 使用覆盖索引避免回表
   - 深分页问题：延迟关联、标签记录法、游标分页
   - 避免使用 `ORDER BY RAND()`

4. **最佳实践**：
   - 多字段排序时注意顺序
   - 限制最大翻页页数
   - 缓存热点数据
   - 引导用户使用搜索和筛选

### 记忆口诀

```
排序分页常相伴，ORDER BY后跟LIMIT见，
ASC升序DESC降序，默认升序可不填。
多字段排序要注意，第一相同看第二，
索引优化很关键，filesort千万要避免。
深分页性能问题大，延迟关联来改善，
标签记录不用offset，游标分页最自然。
Top N查询要熟练，随机获取RAND()慢，
实战案例多总结，排序分页信手拈。
```

---

## 十、常见问题（FAQ）

**Q1：ORDER BY能使用别名吗？**

A：可以！ORDER BY可以使用SELECT中定义的别名。

```sql
SELECT name, price * 0.8 AS discount_price
FROM products
ORDER BY discount_price;  -- ✅ 正确
```

**Q2：可以按表达式排序吗？**

A：可以！

```sql
-- 按价格折扣后排序
SELECT name, price FROM products ORDER BY price * 0.8;

-- 按字符串长度排序
SELECT name FROM products ORDER BY LENGTH(name);
```

**Q3：LIMIT 0 有什么用？**

A：`LIMIT 0` 会返回0行数据，但可以用来测试SQL语法或获取表结构：

```sql
SELECT * FROM products LIMIT 0;  -- 返回空结果，但包含列信息
```

**Q4：如何实现"每页X条，共Y页"的分页？**

A：
```sql
-- 1. 获取总记录数
SELECT COUNT(*) AS total FROM products WHERE category = '手机';
-- 假设total = 156

-- 2. 计算总页数
total_pages = CEIL(total / pageSize)  -- CEIL(156 / 20) = 8

-- 3. 查询当前页数据
SELECT * FROM products
WHERE category = '手机'
ORDER BY price DESC
LIMIT 20 OFFSET ((pageNum - 1) * 20);
```

**Q5：ORDER BY与GROUP BY可以一起使用吗？**

A：可以，但要遵守GROUP BY的规则：

```sql
-- 正确：ORDER BY聚合函数
SELECT category, AVG(price) AS avg_price
FROM products
GROUP BY category
ORDER BY avg_price DESC;

-- 正确：ORDER BY GROUP BY的字段
SELECT category, COUNT(*) AS cnt
FROM products
GROUP BY category
ORDER BY category;

-- 错误：ORDER BY非聚合字段且不在GROUP BY中
SELECT category, AVG(price)
FROM products
GROUP BY category
ORDER BY name;  -- ❌ name不在GROUP BY中
```

---

## 参考资料

1. [MySQL官方文档 - ORDER BY优化](https://dev.mysql.com/doc/refman/8.0/en/order-by-optimization.html)
2. [MySQL官方文档 - LIMIT优化](https://dev.mysql.com/doc/refman/8.0/en/limit-optimization.html)
3. 《高性能MySQL》第6章：查询性能优化 - 排序优化
4. 《MySQL实战45讲》- 第16讲：如何正确显示随机消息？
5. [Percona博客 - 高效分页查询](https://www.percona.com/blog/)

---

## 下一篇预告

下一篇我们将学习**《聚合函数：COUNT、SUM、AVG、MAX、MIN》**，内容包括：
- 五大聚合函数详解
- COUNT(*)、COUNT(1)、COUNT(列名)的区别
- 聚合函数与NULL的处理
- DISTINCT去重
- 实战案例：销售报表统计

掌握排序和分页后，配合聚合函数，你就能实现各种统计分析查询了！

---

**本文字数**：约5,500字
**预计阅读时间**：18-22分钟
**难度等级**：⭐⭐（SQL进阶）
