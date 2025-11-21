---
title: "多表连接：INNER JOIN、LEFT JOIN、RIGHT JOIN"
date: 2025-11-20T18:00:00+08:00
draft: false
tags: ["MySQL", "SQL查询", "JOIN", "多表查询"]
categories: ["MySQL"]
description: "掌握MySQL多表连接的核心原理，理解INNER JOIN、LEFT JOIN、RIGHT JOIN的区别，学会高效地进行多表关联查询。"
series: ["MySQL从入门到精通"]
weight: 15
stage: 2
stageTitle: "SQL进阶篇"
---

## 引言

实际开发中，数据通常分散在多个表中。要获取完整信息，需要将多个表关联起来查询。本文讲解MySQL的多表连接。

---

## 一、连接的本质：笛卡尔积

### 1.1 笛卡尔积

```sql
-- 创建测试表
CREATE TABLE users (
    id INT PRIMARY KEY,
    name VARCHAR(50)
);

CREATE TABLE orders (
    id INT PRIMARY KEY,
    user_id INT,
    amount DECIMAL(10,2)
);

INSERT INTO users VALUES (1, '张三'), (2, '李四'), (3, '王五');
INSERT INTO orders VALUES (1, 1, 100), (2, 1, 200), (3, 2, 150);

-- 笛卡尔积：3 * 3 = 9 条记录
SELECT * FROM users, orders;
```

**结果**：所有可能的组合（9条）。

### 1.2 加上连接条件

```sql
-- 只保留有意义的组合
SELECT * FROM users, orders
WHERE users.id = orders.user_id;
```

这就是连接的本质：笛卡尔积 + 过滤条件。

---

## 二、INNER JOIN - 内连接

### 2.1 基本语法

```sql
SELECT columns
FROM table1
INNER JOIN table2 ON table1.key = table2.key;
```

### 2.2 示例

```sql
-- 查询用户及其订单信息
SELECT u.name, o.id AS order_id, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id;
```

**结果**：
```
+------+----------+--------+
| name | order_id | amount |
+------+----------+--------+
| 张三 |        1 | 100.00 |
| 张三 |        2 | 200.00 |
| 李四 |        3 | 150.00 |
+------+----------+--------+
```

**特点**：
- 只返回两表都匹配的记录
- 王五没有订单，不显示

### 2.3 多条件连接

```sql
SELECT u.name, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id AND o.amount > 100;
```

---

## 三、LEFT JOIN - 左连接

### 3.1 基本语法

```sql
SELECT columns
FROM table1
LEFT JOIN table2 ON table1.key = table2.key;
```

### 3.2 示例

```sql
-- 查询所有用户及其订单（包括没有订单的用户）
SELECT u.name, o.id AS order_id, o.amount
FROM users u
LEFT JOIN orders o ON u.id = o.user_id;
```

**结果**：
```
+------+----------+--------+
| name | order_id | amount |
+------+----------+--------+
| 张三 |        1 | 100.00 |
| 张三 |        2 | 200.00 |
| 李四 |        3 | 150.00 |
| 王五 |     NULL |   NULL |  <-- 没有订单，但仍显示
+------+----------+--------+
```

**特点**：
- 返回左表所有记录
- 右表无匹配时，右表字段为NULL

### 3.3 查找没有订单的用户

```sql
SELECT u.name
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
WHERE o.id IS NULL;
```

---

## 四、RIGHT JOIN - 右连接

### 4.1 基本语法

```sql
SELECT columns
FROM table1
RIGHT JOIN table2 ON table1.key = table2.key;
```

### 4.2 示例

```sql
-- 查询所有订单及其用户（包括无效用户的订单）
SELECT u.name, o.id AS order_id, o.amount
FROM users u
RIGHT JOIN orders o ON u.id = o.user_id;
```

**特点**：
- 返回右表所有记录
- 左表无匹配时，左表字段为NULL
- 实际开发中较少使用（可用LEFT JOIN替代）

---

## 五、FULL JOIN - 全连接

MySQL不支持FULL JOIN，但可以用UNION模拟：

```sql
SELECT u.name, o.amount
FROM users u LEFT JOIN orders o ON u.id = o.user_id
UNION
SELECT u.name, o.amount
FROM users u RIGHT JOIN orders o ON u.id = o.user_id;
```

---

## 六、ON vs WHERE

### 6.1 INNER JOIN中的区别

```sql
-- 两者等价
SELECT * FROM users u INNER JOIN orders o ON u.id = o.user_id AND o.amount > 100;
SELECT * FROM users u INNER JOIN orders o ON u.id = o.user_id WHERE o.amount > 100;
```

### 6.2 LEFT JOIN中的区别

```sql
-- ON条件：连接时过滤（影响匹配）
SELECT u.name, o.amount
FROM users u LEFT JOIN orders o ON u.id = o.user_id AND o.amount > 100;
-- 结果：王五仍然显示，订单为NULL

-- WHERE条件：连接后过滤（不影响匹配）
SELECT u.name, o.amount
FROM users u LEFT JOIN orders o ON u.id = o.user_id
WHERE o.amount > 100;
-- 结果：王五不显示（被WHERE过滤掉）
```

**最佳实践**：
- 连接条件放ON
- 过滤条件放WHERE

---

## 七、多表连接

### 7.1 三表连接

```sql
-- 用户、订单、商品三表连接
SELECT u.name, o.id AS order_id, p.name AS product_name
FROM users u
INNER JOIN orders o ON u.id = o.user_id
INNER JOIN products p ON o.product_id = p.id;
```

### 7.2 连接顺序

```sql
-- MySQL会自动优化连接顺序
-- 但可以用STRAIGHT_JOIN强制顺序
SELECT * FROM users u
STRAIGHT_JOIN orders o ON u.id = o.user_id;
```

---

## 八、性能优化

### 8.1 索引优化

```sql
-- 为连接字段创建索引
CREATE INDEX idx_user_id ON orders(user_id);
CREATE INDEX idx_product_id ON orders(product_id);
```

### 8.2 小表驱动大表

```sql
-- 用小表（users）驱动大表（orders）
SELECT * FROM users u INNER JOIN orders o ON u.id = o.user_id;
-- 优于
SELECT * FROM orders o INNER JOIN users u ON o.user_id = u.id;
```

### 8.3 避免SELECT *

```sql
-- ❌ 差
SELECT * FROM users u INNER JOIN orders o ON u.id = o.user_id;

-- ✅ 好
SELECT u.name, o.amount FROM users u INNER JOIN orders o ON u.id = o.user_id;
```

---

## 九、实战案例

### 案例1：查询用户订单统计

```sql
SELECT u.name,
       COUNT(o.id) AS order_count,
       IFNULL(SUM(o.amount), 0) AS total_amount
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.id, u.name;
```

### 案例2：查询最近订单

```sql
SELECT u.name, o.amount, o.created_at
FROM users u
INNER JOIN (
    SELECT user_id, amount, created_at,
           ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY created_at DESC) AS rn
    FROM orders
) o ON u.id = o.user_id AND o.rn = 1;
```

---

## 十、总结

### 核心要点

1. **INNER JOIN**：只返回两表都匹配的记录
2. **LEFT JOIN**：返回左表所有记录，右表无匹配时为NULL
3. **RIGHT JOIN**：返回右表所有记录，左表无匹配时为NULL
4. **ON vs WHERE**：ON影响连接过程，WHERE过滤最终结果
5. **性能优化**：创建索引、小表驱动大表、避免SELECT *

### 记忆口诀

```
连接查询多表联，内左右三种常见，
内连交集左全集，右连较少用左换。
ON条件连接时，WHERE条件后面添，
索引优化不能忘，小表驱动大表连。
```

---

**本文字数**：约3,200字
**难度等级**：⭐⭐⭐（SQL进阶）
