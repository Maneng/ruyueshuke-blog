---
title: "单表查询进阶：WHERE条件与运算符"
date: 2025-11-21T16:00:00+08:00
draft: false
tags: ["MySQL", "SQL查询", "WHERE条件", "运算符"]
categories: ["MySQL"]
description: "深入理解WHERE子句的各种运算符和条件表达式，掌握复杂条件查询的编写技巧，从简单过滤到复杂业务查询。"
series: ["MySQL从入门到精通"]
weight: 11
stage: 2
stageTitle: "SQL进阶篇"
---

## 引言

在第一阶段我们学习了基础的 `SELECT` 查询，但在实际开发中，简单的 `SELECT * FROM table` 远远不够。我们需要根据各种复杂的业务条件来过滤数据，比如：

- 查询价格在100-500元之间的商品
- 查找姓"张"的所有员工
- 筛选订单金额大于1000且状态为"已支付"的订单
- 查询手机号为空或邮箱未验证的用户

这些都需要通过 `WHERE` 子句配合各种运算符来实现。

**为什么WHERE查询如此重要？**

1. **数据过滤的核心**：90%的查询都需要条件过滤
2. **性能的关键**：合理的WHERE条件能利用索引，大幅提升查询速度
3. **业务逻辑的体现**：复杂的业务规则需要通过条件组合来实现
4. **数据安全**：通过WHERE条件控制数据访问范围

本文将系统讲解WHERE子句的各类运算符和使用技巧，让你能够编写出精准、高效的条件查询。

---

## 一、WHERE子句基础

### 1.1 WHERE的基本语法

```sql
SELECT column1, column2, ...
FROM table_name
WHERE condition;
```

**执行顺序**：
1. **FROM**：确定要查询的表
2. **WHERE**：过滤出符合条件的行
3. **SELECT**：选择要返回的列

### 1.2 准备测试数据

让我们创建一个商品表来演示各种查询：

```sql
-- 创建商品表
CREATE TABLE products (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(100) NOT NULL,
    category VARCHAR(50),
    price DECIMAL(10, 2),
    stock INT,
    created_at DATE,
    description TEXT
);

-- 插入测试数据
INSERT INTO products (name, category, price, stock, created_at, description) VALUES
('iPhone 15 Pro', '手机', 7999.00, 50, '2024-09-20', 'Apple最新旗舰手机'),
('华为Mate 60', '手机', 6999.00, 80, '2024-08-15', '华为高端旗舰'),
('小米14', '手机', 3999.00, 120, '2024-10-01', '小米年度旗舰'),
('MacBook Pro', '电脑', 14999.00, 30, '2024-07-10', 'Apple笔记本电脑'),
('联想ThinkPad', '电脑', 8999.00, 45, '2024-06-20', '商务笔记本'),
('AirPods Pro', '耳机', 1999.00, 200, '2024-09-01', '苹果降噪耳机'),
('索尼WH-1000XM5', '耳机', 2499.00, 60, '2024-05-15', '索尼降噪耳机'),
('iPad Air', '平板', 4799.00, 70, '2024-08-20', 'Apple平板电脑'),
('小米平板6', '平板', 1999.00, 90, '2024-07-25', '小米高性价比平板'),
('罗技MX Master', '鼠标', 699.00, 150, '2024-04-10', '罗技旗舰鼠标');
```

---

## 二、比较运算符

比较运算符用于比较两个值的大小关系。

### 2.1 等于运算符（=）

**注意**：SQL中的等于是单个等号 `=`，不是 `==`。

```sql
-- 查询价格为7999的商品
SELECT * FROM products WHERE price = 7999.00;

-- 查询类别为"手机"的商品
SELECT name, price FROM products WHERE category = '手机';
```

**结果**：
```
+------------+--------+
| name       | price  |
+------------+--------+
| iPhone 15  | 7999.00|
| 华为Mate60 | 6999.00|
| 小米14     | 3999.00|
+------------+--------+
```

### 2.2 不等于运算符（<> 或 !=）

```sql
-- 查询类别不是"手机"的商品
SELECT name, category FROM products WHERE category <> '手机';

-- 两种写法等价
SELECT name, category FROM products WHERE category != '手机';
```

**最佳实践**：推荐使用 `<>`，因为它是SQL标准，`!=` 是MySQL扩展。

### 2.3 大于、小于运算符（>、<、>=、<=）

```sql
-- 查询价格大于5000的商品
SELECT name, price FROM products WHERE price > 5000;

-- 查询价格小于等于2000的商品
SELECT name, price FROM products WHERE price <= 2000;

-- 查询库存大于等于100的商品
SELECT name, stock FROM products WHERE stock >= 100;
```

**结果示例**：
```
+---------------+--------+
| name          | price  |
+---------------+--------+
| iPhone 15 Pro | 7999.00|
| 华为Mate 60   | 6999.00|
| MacBook Pro   |14999.00|
| 联想ThinkPad  | 8999.00|
+---------------+--------+
```

### 2.4 比较运算符的组合

```sql
-- 查询价格在3000-8000之间的手机
SELECT name, price
FROM products
WHERE category = '手机' AND price >= 3000 AND price <= 8000;
```

---

## 三、逻辑运算符

逻辑运算符用于组合多个条件。

### 3.1 AND 运算符（与）

所有条件都必须为真，结果才为真。

```sql
-- 查询价格大于5000且库存大于50的商品
SELECT name, price, stock
FROM products
WHERE price > 5000 AND stock > 50;

-- 三个条件的AND组合
SELECT name, price, stock
FROM products
WHERE category = '手机'
  AND price > 5000
  AND stock > 60;
```

**结果**：
```
+------------+--------+-------+
| name       | price  | stock |
+------------+--------+-------+
| 华为Mate60 | 6999.00|  80   |
+------------+--------+-------+
```

### 3.2 OR 运算符（或）

只要有一个条件为真，结果就为真。

```sql
-- 查询类别为"手机"或"电脑"的商品
SELECT name, category
FROM products
WHERE category = '手机' OR category = '电脑';

-- 查询价格低于2000或高于10000的商品
SELECT name, price
FROM products
WHERE price < 2000 OR price > 10000;
```

### 3.3 NOT 运算符（非）

对条件取反。

```sql
-- 查询类别不是"手机"的商品
SELECT name, category
FROM products
WHERE NOT category = '手机';

-- 等价写法
SELECT name, category
FROM products
WHERE category <> '手机';
```

### 3.4 逻辑运算符优先级

**优先级顺序**：`NOT` > `AND` > `OR`

```sql
-- 示例1：没有括号（容易出错）
SELECT name, category, price
FROM products
WHERE category = '手机' OR category = '电脑' AND price > 10000;

-- 上面的查询等价于：
WHERE category = '手机' OR (category = '电脑' AND price > 10000)
-- 结果：所有手机 + 价格大于10000的电脑

-- 示例2：使用括号（推荐）
SELECT name, category, price
FROM products
WHERE (category = '手机' OR category = '电脑') AND price > 10000;
-- 结果：价格大于10000的手机和电脑
```

**最佳实践**：
- ✅ **总是使用括号明确优先级**，增强可读性
- ❌ 不要依赖运算符的隐式优先级

---

## 四、范围查询运算符

### 4.1 BETWEEN ... AND（闭区间）

用于查询某个范围内的值，**包含边界值**。

```sql
-- 查询价格在3000-8000之间的商品（包含3000和8000）
SELECT name, price
FROM products
WHERE price BETWEEN 3000 AND 8000;

-- 等价写法
SELECT name, price
FROM products
WHERE price >= 3000 AND price <= 8000;
```

**注意事项**：
1. BETWEEN是闭区间，包含两端
2. 第一个值必须小于等于第二个值
3. 适用于数值、日期、字符串

**日期范围查询**：
```sql
-- 查询2024年7月到9月创建的商品
SELECT name, created_at
FROM products
WHERE created_at BETWEEN '2024-07-01' AND '2024-09-30';
```

### 4.2 NOT BETWEEN（不在范围内）

```sql
-- 查询价格不在3000-8000之间的商品
SELECT name, price
FROM products
WHERE price NOT BETWEEN 3000 AND 8000;

-- 等价写法
SELECT name, price
FROM products
WHERE price < 3000 OR price > 8000;
```

### 4.3 IN（在集合中）

用于匹配多个可能的值，相当于多个 `OR` 的简化写法。

```sql
-- 查询类别为"手机"、"电脑"或"平板"的商品
SELECT name, category
FROM products
WHERE category IN ('手机', '电脑', '平板');

-- 等价写法（繁琐）
SELECT name, category
FROM products
WHERE category = '手机'
   OR category = '电脑'
   OR category = '平板';
```

**数值IN查询**：
```sql
-- 查询ID为1、3、5、7、9的商品
SELECT id, name FROM products WHERE id IN (1, 3, 5, 7, 9);
```

### 4.4 NOT IN（不在集合中）

```sql
-- 查询类别不是"手机"和"电脑"的商品
SELECT name, category
FROM products
WHERE category NOT IN ('手机', '电脑');
```

**⚠️ NOT IN的陷阱**：
如果IN列表中包含NULL，NOT IN会返回空结果！

```sql
-- 危险示例
WHERE category NOT IN ('手机', '电脑', NULL)  -- 永远返回空结果！
```

**原因**：`NULL <> '手机'` 的结果是 `UNKNOWN`，而不是 `TRUE`。

---

## 五、模糊查询

### 5.1 LIKE 运算符

用于模式匹配，支持两个通配符：
- `%`：匹配任意长度的字符串（包括空字符串）
- `_`：匹配单个字符

#### 5.1.1 百分号（%）通配符

```sql
-- 查询名称以"iPhone"开头的商品
SELECT name FROM products WHERE name LIKE 'iPhone%';
-- 结果：iPhone 15 Pro

-- 查询名称以"Pro"结尾的商品
SELECT name FROM products WHERE name LIKE '%Pro';
-- 结果：iPhone 15 Pro, MacBook Pro, AirPods Pro

-- 查询名称包含"米"的商品
SELECT name FROM products WHERE name LIKE '%米%';
-- 结果：小米14, 小米平板6
```

#### 5.1.2 下划线（_）通配符

```sql
-- 查询名称为"小米1"加一个字符的商品
SELECT name FROM products WHERE name LIKE '小米1_';
-- 结果：小米14

-- 查询名称为"iPad"加3个字符的商品
SELECT name FROM products WHERE name LIKE 'iPad___';
-- 结果：iPad Air（iPad + 空格 + A + i + r 共8个字符，不匹配）

-- 查询类别为两个字符的商品
SELECT DISTINCT category FROM products WHERE category LIKE '__';
-- 结果：手机、电脑、耳机、平板、鼠标
```

#### 5.1.3 NOT LIKE（不匹配）

```sql
-- 查询名称不包含"米"的商品
SELECT name FROM products WHERE name NOT LIKE '%米%';
```

#### 5.1.4 转义特殊字符

如果要查询包含 `%` 或 `_` 字符本身的数据，需要转义：

```sql
-- 查询描述包含"50%"的商品
SELECT name, description
FROM products
WHERE description LIKE '%50\%%';
-- 使用反斜杠 \ 转义

-- 或者自定义转义字符
SELECT name, description
FROM products
WHERE description LIKE '%50!%%' ESCAPE '!';
-- 使用 ! 作为转义字符
```

### 5.2 REGEXP 正则表达式（MySQL扩展）

LIKE只支持简单的通配符，复杂模式需要使用正则表达式。

```sql
-- 查询名称包含数字的商品
SELECT name FROM products WHERE name REGEXP '[0-9]';
-- 结果：iPhone 15 Pro, 华为Mate 60, 小米14, 小米平板6, WH-1000XM5

-- 查询名称以"小米"或"华为"开头的商品
SELECT name FROM products WHERE name REGEXP '^(小米|华为)';

-- 查询名称以"Pro"或"Air"结尾的商品
SELECT name FROM products WHERE name REGEXP '(Pro|Air)$';
```

**常用正则符号**：
- `^`：匹配字符串开头
- `$`：匹配字符串结尾
- `.`：匹配任意单个字符
- `*`：匹配前一个字符0次或多次
- `+`：匹配前一个字符1次或多次
- `[abc]`：匹配a、b或c
- `[0-9]`：匹配任意数字
- `|`：或运算

---

## 六、空值处理

在MySQL中，`NULL` 表示"未知"或"不存在"，它与空字符串 `''` 和数字 `0` 都不同。

### 6.1 NULL的特殊性

```sql
-- 插入包含NULL的测试数据
INSERT INTO products (name, category, price, stock, description) VALUES
('神秘商品', NULL, 9999.00, 10, NULL);

-- 错误示例：使用 = 判断NULL（不会返回结果）
SELECT * FROM products WHERE category = NULL;  -- ❌ 错误，不会返回任何结果

SELECT * FROM products WHERE description = NULL;  -- ❌ 错误
```

**原因**：`NULL` 表示未知，任何值与 `NULL` 的比较结果都是 `UNKNOWN`，而不是 `TRUE` 或 `FALSE`。

### 6.2 IS NULL（判断为空）

```sql
-- 正确示例：使用 IS NULL
SELECT name, category FROM products WHERE category IS NULL;
-- 结果：神秘商品

SELECT name, description FROM products WHERE description IS NULL;
-- 结果：神秘商品
```

### 6.3 IS NOT NULL（判断不为空）

```sql
-- 查询有类别的商品
SELECT name, category FROM products WHERE category IS NOT NULL;

-- 查询有描述的商品
SELECT name, description FROM products WHERE description IS NOT NULL;
```

### 6.4 NULL的运算特性

```sql
-- 任何值与NULL的算术运算结果都是NULL
SELECT 100 + NULL;  -- 结果：NULL
SELECT 100 * NULL;  -- 结果：NULL

-- 任何值与NULL的比较结果都是UNKNOWN
SELECT 100 > NULL;  -- 结果：NULL（不是FALSE）
SELECT NULL = NULL; -- 结果：NULL（不是TRUE）

-- 逻辑运算中的NULL
SELECT TRUE AND NULL;   -- 结果：NULL
SELECT FALSE AND NULL;  -- 结果：FALSE（因为AND有短路特性）
SELECT TRUE OR NULL;    -- 结果：TRUE（因为OR有短路特性）
```

### 6.5 IFNULL() 和 COALESCE() 函数

处理NULL值的实用函数：

```sql
-- IFNULL(expr1, expr2)：如果expr1为NULL，返回expr2
SELECT name, IFNULL(description, '暂无描述') AS description
FROM products;

-- COALESCE(value1, value2, ...)：返回第一个非NULL的值
SELECT name,
       COALESCE(description, category, '未知商品') AS info
FROM products;
```

---

## 七、复杂条件组合实战

### 7.1 案例1：多条件筛选商品

**需求**：查询价格在2000-8000之间，且库存大于50，类别为"手机"或"电脑"的商品。

```sql
SELECT name, category, price, stock
FROM products
WHERE price BETWEEN 2000 AND 8000
  AND stock > 50
  AND (category = '手机' OR category = '电脑');
```

### 7.2 案例2：排除条件查询

**需求**：查询所有手机，但排除价格低于4000或库存低于60的。

```sql
SELECT name, price, stock
FROM products
WHERE category = '手机'
  AND NOT (price < 4000 OR stock < 60);

-- 等价写法（德摩根定律）
SELECT name, price, stock
FROM products
WHERE category = '手机'
  AND price >= 4000
  AND stock >= 60;
```

### 7.3 案例3：模糊查询结合范围查询

**需求**：查询名称包含"Pro"且价格大于5000的商品。

```sql
SELECT name, price
FROM products
WHERE name LIKE '%Pro%'
  AND price > 5000;
```

### 7.4 案例4：NULL值处理

**需求**：查询有描述或价格低于2000的商品。

```sql
SELECT name, price, description
FROM products
WHERE description IS NOT NULL
   OR price < 2000;
```

---

## 八、最佳实践与常见误区

### 8.1 性能优化建议

#### ✅ 推荐做法

```sql
-- 1. 在WHERE条件中使用索引列
SELECT * FROM products WHERE id = 10;  -- id是主键，有索引

-- 2. 避免在索引列上使用函数
SELECT * FROM products WHERE price > 5000;  -- ✅ 好

-- 3. 使用BETWEEN代替多个OR
SELECT * FROM products WHERE price BETWEEN 3000 AND 8000;  -- ✅ 好
```

#### ❌ 避免做法

```sql
-- 1. 在索引列上使用函数（索引失效）
SELECT * FROM products WHERE YEAR(created_at) = 2024;  -- ❌ 差

-- 改进：
SELECT * FROM products
WHERE created_at BETWEEN '2024-01-01' AND '2024-12-31';  -- ✅ 好

-- 2. 使用大量OR条件
SELECT * FROM products
WHERE price = 3000 OR price = 4000 OR price = 5000
   OR price = 6000 OR price = 7000;  -- ❌ 差

-- 改进：
SELECT * FROM products WHERE price IN (3000, 4000, 5000, 6000, 7000);  -- ✅ 好

-- 3. LIKE左模糊匹配（索引失效）
SELECT * FROM products WHERE name LIKE '%手机';  -- ❌ 差，无法使用索引

-- 改进：右模糊或全文索引
SELECT * FROM products WHERE name LIKE '手机%';  -- ✅ 好，能使用索引
```

### 8.2 常见误区

#### 误区1：NULL的判断

```sql
-- ❌ 错误
WHERE column = NULL
WHERE column != NULL

-- ✅ 正确
WHERE column IS NULL
WHERE column IS NOT NULL
```

#### 误区2：字符串与数字的比较

```sql
-- 如果price是VARCHAR类型
WHERE price > '1000'  -- 字符串比较，可能不符合预期

-- 正确做法：使用数值类型存储数值数据
```

#### 误区3：逻辑运算符优先级

```sql
-- ❌ 错误（可能不符合预期）
WHERE a = 1 OR b = 2 AND c = 3
-- 实际执行：WHERE a = 1 OR (b = 2 AND c = 3)

-- ✅ 正确（明确优先级）
WHERE (a = 1 OR b = 2) AND c = 3
```

#### 误区4：IN与NOT IN的NULL问题

```sql
-- ❌ 危险
WHERE category NOT IN ('手机', '电脑', NULL)  -- 永远返回空结果

-- ✅ 正确
WHERE category NOT IN ('手机', '电脑') AND category IS NOT NULL
```

---

## 九、总结

### 核心要点回顾

1. **比较运算符**：`=`、`<>`、`>`、`<`、`>=`、`<=`
2. **逻辑运算符**：`AND`（与）、`OR`（或）、`NOT`（非）
   - 优先级：`NOT` > `AND` > `OR`
   - 建议总是使用括号明确优先级
3. **范围查询**：
   - `BETWEEN ... AND`：闭区间查询
   - `IN (value1, value2, ...)`：集合匹配
4. **模糊查询**：
   - `LIKE`：支持 `%` 和 `_` 通配符
   - `REGEXP`：支持正则表达式（MySQL扩展）
5. **空值处理**：
   - 使用 `IS NULL` 和 `IS NOT NULL` 判断
   - 任何值与NULL的运算结果都是NULL
6. **性能优化**：
   - 避免在索引列上使用函数
   - 避免LIKE左模糊匹配
   - 使用IN代替大量OR
   - 使用BETWEEN代替范围OR

### 记忆口诀

```
比较运算六兄弟，等于不等大小齐，
逻辑运算三剑客，与或非来组合题。
范围查询BETWEEN IN，模糊查询LIKE配，
NULL判断IS专用，等号判断要放弃。
括号明确优先级，索引列上别用函数，
左模糊来索引废，性能优化记心里。
```

---

## 十、常见问题（FAQ）

**Q1：WHERE和HAVING有什么区别？**

A：
- `WHERE`：在分组之前过滤行，不能使用聚合函数
- `HAVING`：在分组之后过滤组，可以使用聚合函数
- 详见下一篇文章《分组查询：GROUP BY与HAVING》

**Q2：LIKE和REGEXP性能哪个更好？**

A：
- LIKE性能更好，因为它更简单
- REGEXP功能更强，但性能较差
- 能用LIKE解决的不要用REGEXP
- 对于复杂模式，REGEXP是更好的选择

**Q3：为什么我的WHERE条件没有生效？**

A：常见原因：
1. NULL判断使用了 `=` 而不是 `IS NULL`
2. 逻辑运算符优先级问题，缺少括号
3. 数据类型不匹配（如字符串与数字比较）
4. 隐式类型转换导致索引失效

**Q4：如何优化包含OR的查询？**

A：
- 少量OR：保持不变
- 大量OR：使用IN代替
- 不同列OR：考虑拆分为多个查询用UNION合并
- 有索引的列OR无索引的列：拆分查询

**Q5：BETWEEN是否包含边界值？**

A：是的，BETWEEN是闭区间，包含两端的值。
- `WHERE price BETWEEN 100 AND 200` 等价于 `WHERE price >= 100 AND price <= 200`

---

## 参考资料

1. [MySQL官方文档 - WHERE语法](https://dev.mysql.com/doc/refman/8.0/en/where-optimization.html)
2. [MySQL官方文档 - 运算符优先级](https://dev.mysql.com/doc/refman/8.0/en/operator-precedence.html)
3. [MySQL官方文档 - 模式匹配](https://dev.mysql.com/doc/refman/8.0/en/pattern-matching.html)
4. 《高性能MySQL》第6章：查询优化
5. 《MySQL技术内幕：InnoDB存储引擎》第7章：索引与算法

---

## 下一篇预告

下一篇我们将学习**《排序与分页：ORDER BY与LIMIT》**，内容包括：
- 单字段和多字段排序
- ASC与DESC排序方向
- LIMIT分页原理
- 深分页性能问题及优化
- 实战案例：高效分页查询

WHERE条件查询掌握后，加上排序和分页，你就能应对大部分的单表查询需求了！

---

**本文字数**：约5,200字
**预计阅读时间**：15-20分钟
**难度等级**：⭐⭐（SQL进阶）
