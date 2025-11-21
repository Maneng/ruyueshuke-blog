---
title: "InnoDB行格式：Compact、Redundant、Dynamic、Compressed"
date: 2025-01-15T12:00:00+08:00
draft: false
tags: ["MySQL", "InnoDB", "行格式", "存储优化"]
categories: ["数据库"]
description: "深入理解InnoDB的四种行格式，掌握行溢出处理和存储优化技巧"
series: ["MySQL从入门到精通"]
weight: 48
stage: 5
stageTitle: "架构原理篇"
---

## 行格式概述

**行格式（Row Format）** 定义了一行数据在磁盘上的存储方式。

```sql
-- 查看表的行格式
SHOW TABLE STATUS LIKE 'users'\G
-- Row_format: Dynamic

-- 创建表时指定行格式
CREATE TABLE test (
    id INT PRIMARY KEY,
    name VARCHAR(100)
) ROW_FORMAT=COMPACT;

-- 修改行格式
ALTER TABLE test ROW_FORMAT=DYNAMIC;
```

---

## 四种行格式

| 行格式           | MySQL版本   | 特点              | 适用场景        |
|---------------|-----------|-----------------|-------------|
| **Redundant**   | 5.0前默认    | 旧格式，占用空间大       | 兼容性         |
| **Compact**     | 5.0-5.6默认 | 紧凑格式，节省20%空间   | 通用（已过时）     |
| **Dynamic**     | 5.7+默认    | 动态格式，处理行溢出      | 推荐（默认）      |
| **Compressed**  | 5.5+      | 压缩格式，节省50%+空间  | 只读表、归档数据    |

---

## 1. Compact行格式（紧凑格式）

### 结构

```
┌──────────────────────────────────────────────────┐
│ 变长字段长度列表（逆序）                              │  VARCHAR、TEXT字段的长度
├──────────────────────────────────────────────────┤
│ NULL值列表（位图，逆序）                             │  标记哪些字段为NULL
├──────────────────────────────────────────────────┤
│ 记录头信息（5字节）                                  │  deleted_flag、min_rec_flag等
├──────────────────────────────────────────────────┤
│ 隐藏列                                           │  DB_TRX_ID、DB_ROLL_PTR、DB_ROW_ID
├──────────────────────────────────────────────────┤
│ 列1数据                                          │  实际数据
├──────────────────────────────────────────────────┤
│ 列2数据                                          │
├──────────────────────────────────────────────────┤
│ ...                                              │
└──────────────────────────────────────────────────┘
```

### 示例

```sql
CREATE TABLE user_compact (
    id INT PRIMARY KEY,
    name VARCHAR(20),
    age INT,
    email VARCHAR(50)
) ROW_FORMAT=COMPACT;

INSERT INTO user_compact VALUES (1, 'Alice', 25, 'alice@example.com');
```

**存储布局**：

```
变长字段长度列表：[17, 5]（逆序，email长度17，name长度5）
NULL值列表：0x00（无NULL值）
记录头信息：5字节
隐藏列：
  - DB_TRX_ID：6字节（事务ID）
  - DB_ROLL_PTR：7字节（回滚指针）
列数据：
  - id：4字节（1）
  - name：5字节（Alice）
  - age：4字节（25）
  - email：17字节（alice@example.com）
```

### 特点

- **节省空间**：比Redundant节省约20%
- **变长字段优化**：VARCHAR实际长度存储
- **NULL值优化**：用位图标记，不占用实际空间

---

## 2. Dynamic行格式（动态格式）

### 结构

与Compact**几乎相同**，主要区别在**行溢出处理**。

### 行溢出（Row Overflow）

**问题**：当一行数据超过页大小（16KB）怎么办？

**Compact处理**：
- 前768字节存储在数据页（行内）
- 剩余部分存储在**溢出页**（Overflow Page）
- 数据页保留768字节 + 20字节指针

**Dynamic处理**：
- **完全溢出**：整个字段存储在溢出页
- 数据页只保留20字节指针
- 节省数据页空间，提高缓存命中率

### 示例

```sql
CREATE TABLE test_overflow (
    id INT PRIMARY KEY,
    content TEXT  -- 假设存储100KB数据
) ROW_FORMAT=DYNAMIC;

INSERT INTO test_overflow VALUES (1, REPEAT('A', 100000));
```

**Compact存储**：

```
数据页：
  - id：4字节
  - content前768字节
  - 指针（20字节）→ 溢出页1

溢出页1：
  - 剩余99232字节（100000 - 768）
```

**Dynamic存储**：

```
数据页：
  - id：4字节
  - 指针（20字节）→ 溢出页1

溢出页1：
  - 完整的100000字节
```

**优点**：
- 数据页更紧凑，缓存命中率高
- 减少回表次数

---

## 3. Compressed行格式（压缩格式）

### 特点

**在Dynamic基础上增加压缩**，使用zlib算法压缩数据页。

### 配置

```sql
-- 创建压缩表
CREATE TABLE test_compressed (
    id INT PRIMARY KEY,
    name VARCHAR(100),
    content TEXT
) ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=8;  -- 压缩页大小8KB

-- KEY_BLOCK_SIZE可选值：1、2、4、8、16（默认16）
```

### 压缩流程

```
写入流程：
1. 数据写入Buffer Pool（16KB页）
2. 压缩为8KB页
3. 写入磁盘（8KB）

读取流程：
1. 从磁盘读取8KB压缩页
2. 解压缩为16KB页
3. 缓存到Buffer Pool
```

### 性能影响

| 操作    | 压缩格式            | 普通格式  |
|-------|-----------------|-------|
| **存储空间** | 节省50-70%        | 100%  |
| **写入性能** | 慢30-50%（压缩开销）  | 100%  |
| **读取性能** | 慢10-20%（解压开销）  | 100%  |
| **CPU占用** | 高（压缩/解压）        | 低     |

### 适用场景

```sql
-- ✅ 适合：只读表、归档数据
CREATE TABLE log_archive (
    id BIGINT PRIMARY KEY,
    log_time TIMESTAMP,
    log_content TEXT
) ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=8;

-- ❌ 不适合：频繁更新的表
-- 压缩/解压开销大，性能下降明显
```

---

## 4. Redundant行格式（冗余格式）

### 特点

**MySQL 5.0前的默认格式**，已过时，占用空间大。

### 与Compact的区别

| 特性       | Redundant        | Compact    |
|----------|------------------|------------|
| **空间占用** | 大（多占用20%）       | 小          |
| **变长字段** | 存储固定长度（浪费空间）   | 存储实际长度     |
| **NULL值** | 占用实际空间（如INT 4字节） | 位图标记（不占空间） |

**不推荐使用**，仅用于兼容旧版本。

---

## 行格式选择

### 1. 默认使用Dynamic（推荐）

```sql
-- MySQL 5.7+默认
-- 大字段处理好，性能好

-- 查看默认行格式
SHOW VARIABLES LIKE 'innodb_default_row_format';
-- dynamic
```

### 2. 归档表使用Compressed

```sql
-- 归档日志表
CREATE TABLE log_2024 (
    id BIGINT PRIMARY KEY,
    log_time TIMESTAMP,
    log_content TEXT
) ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=8;

-- 优势：
- 节省50%+存储空间
- 减少备份时间和成本
```

### 3. 避免使用Redundant

```sql
-- ❌ 不推荐
ROW_FORMAT=REDUNDANT
-- 浪费空间，性能差
```

---

## 行溢出阈值

### 何时触发行溢出？

```sql
-- 阈值计算
一行数据大小 > (页大小 - 页头 - 页尾) / 2
即：行大小 > (16384 - 200) / 2 ≈ 8KB

-- 触发行溢出的场景
1. TEXT、BLOB大字段
2. VARCHAR(10000)超长字段
3. 多个VARCHAR累计超8KB
```

### 查看行溢出

```sql
-- 查看表的数据和溢出页大小
SELECT
    table_name,
    data_length/1024/1024 AS data_mb,
    max_data_length/1024/1024 AS overflow_mb
FROM information_schema.TABLES
WHERE table_schema = 'test';
```

---

## 实战建议

### 1. 默认使用Dynamic

```ini
# my.cnf
[mysqld]
innodb_default_row_format = DYNAMIC  # 默认值
```

### 2. 避免过长字段

```sql
-- ❌ 不好：VARCHAR过长
name VARCHAR(10000)  -- 可能触发行溢出

-- ✅ 好：合理长度
name VARCHAR(200)    -- 根据业务需求
```

### 3. 大字段拆分

```sql
-- ❌ 不好：大字段和小字段混合
CREATE TABLE article (
    id INT PRIMARY KEY,
    title VARCHAR(200),
    content TEXT  -- 可能很大，触发行溢出
);

-- ✅ 好：大字段单独存储
CREATE TABLE article (
    id INT PRIMARY KEY,
    title VARCHAR(200)
);

CREATE TABLE article_content (
    article_id INT PRIMARY KEY,
    content TEXT,
    FOREIGN KEY (article_id) REFERENCES article(id)
);
```

### 4. 监控压缩效果

```sql
-- 查看压缩表的压缩率
SELECT
    table_name,
    data_length/1024/1024 AS data_mb,
    data_free/1024/1024 AS free_mb,
    ROUND(data_free/data_length * 100, 2) AS compress_ratio
FROM information_schema.TABLES
WHERE table_schema = 'test' AND row_format = 'COMPRESSED';
```

---

## 常见面试题

**Q1: Dynamic和Compact的区别？**
- 主要区别在行溢出处理：Dynamic完全溢出，Compact部分溢出

**Q2: 什么时候使用Compressed？**
- 归档表、只读表，节省存储空间

**Q3: 行溢出的阈值是多少？**
- 约8KB（页大小16KB的一半）

**Q4: 如何避免行溢出？**
- 合理设计字段长度、大字段拆分、使用Dynamic格式

---

## 小结

✅ **Compact**：紧凑格式，节省空间（已过时）
✅ **Dynamic**：动态格式，完全行溢出（推荐，默认）
✅ **Compressed**：压缩格式，节省空间，性能差（归档表使用）
✅ **Redundant**：冗余格式，浪费空间（不推荐）

**建议**：默认Dynamic，归档表使用Compressed。

---

📚 **相关阅读**：
- 下一篇：《Buffer Pool：MySQL的内存管理》
- 推荐：《InnoDB存储结构：表空间、段、区、页》
