---
title: "条件表达式：CASE WHEN与IF"
date: 2025-11-21T19:15:00+08:00
draft: false
tags: ["MySQL", "SQL函数", "CASE WHEN", "IF函数"]
categories: ["MySQL"]
description: "掌握MySQL条件表达式的使用，理解CASE WHEN和IF函数的应用场景，学会实现复杂的条件逻辑判断。"
series: ["MySQL从入门到精通"]
weight: 20
stage: 2
stageTitle: "SQL进阶篇"
---

## 引言

在查询中经常需要根据不同条件返回不同结果。MySQL提供了CASE WHEN和IF等条件表达式来实现。

---

## 一、CASE WHEN 表达式

### 1.1 简单CASE表达式

```sql
-- 语法
CASE expression
    WHEN value1 THEN result1
    WHEN value2 THEN result2
    ELSE default_result
END

-- 示例：订单状态转换
SELECT order_id,
       CASE status
           WHEN 1 THEN '待支付'
           WHEN 2 THEN '已支付'
           WHEN 3 THEN '已发货'
           WHEN 4 THEN '已完成'
           ELSE '未知'
       END AS status_text
FROM orders;
```

### 1.2 搜索CASE表达式（推荐）

```sql
-- 语法
CASE
    WHEN condition1 THEN result1
    WHEN condition2 THEN result2
    ELSE default_result
END

-- 示例：价格分级
SELECT name, price,
       CASE
           WHEN price < 2000 THEN '低价'
           WHEN price BETWEEN 2000 AND 5000 THEN '中价'
           WHEN price > 5000 THEN '高价'
           ELSE '未知'
       END AS price_level
FROM products;
```

### 1.3 嵌套CASE

```sql
SELECT name,
       CASE
           WHEN stock = 0 THEN '缺货'
           WHEN stock > 0 THEN
               CASE
                   WHEN stock < 10 THEN '库存紧张'
                   WHEN stock < 50 THEN '库存正常'
                   ELSE '库存充足'
               END
       END AS stock_status
FROM products;
```

---

## 二、IF() 函数

### 2.1 基本用法

```sql
-- IF(condition, value_if_true, value_if_false)
SELECT name, price,
       IF(price > 5000, '高价', '普通价') AS price_tag
FROM products;

-- 多条件判断（嵌套IF）
SELECT name,
       IF(stock > 0,
          IF(stock > 50, '充足', '正常'),
          '缺货'
       ) AS stock_status
FROM products;
```

### 2.2 IF vs CASE WHEN

```sql
-- IF：适合简单的二元判断
SELECT IF(score >= 60, '及格', '不及格') FROM students;

-- CASE WHEN：适合多条件判断
SELECT
    CASE
        WHEN score >= 90 THEN '优秀'
        WHEN score >= 80 THEN '良好'
        WHEN score >= 60 THEN '及格'
        ELSE '不及格'
    END AS grade
FROM students;
```

---

## 三、IFNULL() / COALESCE()

### 3.1 IFNULL() - 处理NULL

```sql
-- IFNULL(expr, default_value)
SELECT name,
       IFNULL(phone, '未提供') AS phone
FROM users;

-- 计算时避免NULL
SELECT name,
       price * IFNULL(discount, 1) AS final_price
FROM products;
```

### 3.2 COALESCE() - 返回第一个非NULL值

```sql
-- COALESCE(value1, value2, value3, ...)
SELECT name,
       COALESCE(mobile, phone, email, '无联系方式') AS contact
FROM users;
```

---

## 四、NULLIF() - 返回NULL

```sql
-- NULLIF(expr1, expr2)：如果相等返回NULL，否则返回expr1
SELECT NULLIF(10, 10);  -- NULL
SELECT NULLIF(10, 20);  -- 10

-- 避免除零错误
SELECT sales / NULLIF(days, 0) AS avg_daily_sales
FROM stats;
```

---

## 五、实战案例

### 案例1：分组统计

```sql
-- 统计各价格区间的商品数
SELECT
    SUM(CASE WHEN price < 2000 THEN 1 ELSE 0 END) AS low_price_count,
    SUM(CASE WHEN price BETWEEN 2000 AND 5000 THEN 1 ELSE 0 END) AS mid_price_count,
    SUM(CASE WHEN price > 5000 THEN 1 ELSE 0 END) AS high_price_count
FROM products;
```

### 案例2：数据透视

```sql
-- 按月统计各状态订单数
SELECT
    DATE_FORMAT(created_at, '%Y-%m') AS month,
    SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS completed_count,
    SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) AS pending_count,
    SUM(CASE WHEN status = 'cancelled' THEN 1 ELSE 0 END) AS cancelled_count
FROM orders
GROUP BY DATE_FORMAT(created_at, '%Y-%m');
```

### 案例3：动态排序

```sql
-- 根据参数动态排序
SET @sort_field = 'price';

SELECT * FROM products
ORDER BY
    CASE @sort_field
        WHEN 'price' THEN price
        WHEN 'sales' THEN sales
        WHEN 'stock' THEN stock
    END DESC;
```

### 案例4：数据清洗

```sql
-- 清洗性别数据
UPDATE users
SET gender = CASE
    WHEN gender IN ('male', 'M', '男', '1') THEN '男'
    WHEN gender IN ('female', 'F', '女', '0') THEN '女'
    ELSE '未知'
END;
```

### 案例5：行列转换

```sql
-- 将多行转为多列
SELECT user_id,
       MAX(CASE WHEN subject = '数学' THEN score END) AS math_score,
       MAX(CASE WHEN subject = '语文' THEN score END) AS chinese_score,
       MAX(CASE WHEN subject = '英语' THEN score END) AS english_score
FROM scores
GROUP BY user_id;
```

---

## 六、性能优化

### 6.1 索引失效

```sql
-- ❌ 差：在索引列上使用CASE，索引失效
SELECT * FROM products
WHERE CASE WHEN category = '手机' THEN price > 3000 ELSE price > 5000 END;

-- ✅ 好：拆分条件
SELECT * FROM products
WHERE (category = '手机' AND price > 3000)
   OR (category != '手机' AND price > 5000);
```

### 6.2 避免重复计算

```sql
-- ❌ 差：CASE重复计算
SELECT
    CASE WHEN price * 0.8 > 5000 THEN '高价' ELSE '普通' END AS tag1,
    CASE WHEN price * 0.8 > 3000 THEN '贵' ELSE '便宜' END AS tag2
FROM products;

-- ✅ 好：先计算再判断
SELECT
    CASE WHEN discount_price > 5000 THEN '高价' ELSE '普通' END AS tag1,
    CASE WHEN discount_price > 3000 THEN '贵' ELSE '便宜' END AS tag2
FROM (
    SELECT *, price * 0.8 AS discount_price FROM products
) t;
```

---

## 七、总结

### 核心要点

1. **CASE WHEN**：多条件判断，功能强大
   - 简单CASE：匹配固定值
   - 搜索CASE：复杂条件判断
2. **IF()**：二元判断，简洁易读
3. **IFNULL() / COALESCE()**：处理NULL值
4. **NULLIF()**：避免除零错误
5. **性能**：避免在索引列上使用条件表达式

### 记忆口诀

```
条件表达式两大将，CASE WHEN IF各擅长，
CASE多条件分级判，IF二元选择强。
IFNULL处理空值好，COALESCE多值找，
NULLIF避免除零错，实战案例记心上。
```

---

**本文字数**：约2,600字
**难度等级**：⭐⭐（SQL进阶）
