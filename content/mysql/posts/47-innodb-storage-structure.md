---
title: "InnoDB存储结构：表空间、段、区、页"
date: 2025-01-15T11:00:00+08:00
draft: false
tags: ["MySQL", "InnoDB", "表空间", "存储结构"]
categories: ["数据库"]
description: "深入理解InnoDB的存储层次结构，掌握表空间、段、区、页的组织方式"
series: ["MySQL从入门到精通"]
weight: 47
stage: 5
stageTitle: "架构原理篇"
---

## InnoDB存储层次

```
表空间（Tablespace）
  └─ 段（Segment）
      └─ 区（Extent，1MB = 64页）
          └─ 页（Page，16KB，InnoDB的基本IO单位）
              └─ 行（Row）
```

---

## 1. 表空间（Tablespace）

### 定义

**表空间**是InnoDB存储数据的逻辑单位，包含多个段。

### 分类

| 类型          | 文件名               | 内容                | 配置参数                   |
|-------------|-------------------|-------------------|------------------------|
| **系统表空间**   | `ibdata1`         | 数据字典、undo log、双写缓冲 | innodb_data_file_path  |
| **独立表空间**   | `table_name.ibd`  | 表数据+索引            | innodb_file_per_table  |
| **通用表空间**   | `tablespace.ibd`  | 多个表共享             | CREATE TABLESPACE      |
| **临时表空间**   | `ibtmp1`          | 临时表、排序缓冲         | innodb_temp_data_file_path |
| **Undo表空间** | `undo_001`、`undo_002` | undo log（MySQL 8.0+） | innodb_undo_tablespaces |

### 系统表空间 vs 独立表空间

```sql
-- 查看配置
SHOW VARIABLES LIKE 'innodb_file_per_table';
-- ON：每个表独立.ibd文件（推荐）
-- OFF：所有表共享ibdata1（不推荐）

-- 查看表空间文件
# ls -lh /var/lib/mysql/test/
-rw-r----- 1 mysql mysql  16M users.ibd  -- 独立表空间
```

**优点**：
- 独立表空间易于管理（可单独备份、迁移）
- 碎片整理不影响其他表
- DELETE后空间可回收

**缺点**：
- 文件数量多

---

## 2. 段（Segment）

### 定义

**段**是一组区的集合，用于管理索引和数据。

### 分类

| 段类型       | 作用           | 存储内容       |
|-----------|--------------|------------|
| **数据段**   | 存储表数据        | 聚簇索引的叶子节点  |
| **索引段**   | 存储索引数据       | 二级索引的非叶子节点 |
| **回滚段**   | 存储undo log   | 事务回滚信息     |

```
B+树索引结构
       根节点（索引段）
      /      \
   分支节点    分支节点（索引段）
   /    \    /    \
 叶子节点 叶子节点 叶子节点 叶子节点（数据段）
```

---

## 3. 区（Extent）

### 定义

**区**是连续的64个页（1MB），是InnoDB分配空间的单位。

```
1个区（Extent）= 64个页 = 64 × 16KB = 1MB
```

### 作用

**提高磁盘IO效率**，减少碎片。

```sql
-- 顺序扫描一个区
连续读取64个页（1MB），只需要1次磁盘寻址
-- vs 随机读取64个页
需要64次磁盘寻址（慢）
```

### 区的状态

| 状态         | 说明          |
|------------|-------------|
| **FREE**   | 空闲，未被使用     |
| **FREE_FRAG** | 碎片区，部分页已使用  |
| **FULL_FRAG** | 碎片区，所有页已使用  |
| **FSEG**   | 被段完全占用      |

---

## 4. 页（Page）

### 定义

**页**是InnoDB的**基本IO单位**，默认大小16KB。

```sql
-- 查看页大小
SHOW VARIABLES LIKE 'innodb_page_size';
-- 16384（16KB，默认）
```

### 为什么是16KB？

1. **磁盘IO优化**：一次IO读取16KB，减少IO次数
2. **缓存效率**：Buffer Pool以页为单位缓存
3. **B+树高度**：16KB可以存储更多索引项，减少树高度

### 页的类型

| 页类型              | 作用              |
|------------------|-----------------|
| **数据页**          | 存储表数据（叶子节点）     |
| **索引页**          | 存储索引数据（非叶子节点）   |
| **Undo页**        | 存储undo log      |
| **系统页**          | 存储系统信息（如数据字典）   |
| **BLOB页**        | 存储大对象（TEXT、BLOB） |

### 页的内部结构

```
┌──────────────────────────────────────┐
│ File Header（38字节）                  │  页头，校验和、页号、前后页指针
├──────────────────────────────────────┤
│ Page Header（56字节）                 │  页状态信息
├──────────────────────────────────────┤
│ Infimum + Supremum（26字节）          │  虚拟最小/最大记录
├──────────────────────────────────────┤
│ User Records（动态）                   │  实际数据行
├──────────────────────────────────────┤
│ Free Space（动态）                     │  空闲空间
├──────────────────────────────────────┤
│ Page Directory（动态）                 │  页内目录（加速查找）
├──────────────────────────────────────┤
│ File Trailer（8字节）                  │  校验和（与File Header对应）
└──────────────────────────────────────┘
总大小：16KB
```

**关键字段**：

1. **File Header**：
   - `FIL_PAGE_OFFSET`：页号
   - `FIL_PAGE_PREV`：前一页
   - `FIL_PAGE_NEXT`：后一页（形成双向链表）

2. **Page Directory**：
   - 页内槽（Slot），加速二分查找

---

## 5. 行（Row）

### 行格式

详见下一篇《InnoDB行格式：Compact、Redundant、Dynamic》。

---

## 存储层次关系

### 示例：users表

```sql
CREATE TABLE users (
    id INT PRIMARY KEY,
    name VARCHAR(50),
    age INT,
    INDEX idx_name (name)
);
```

**存储结构**：

```
表空间（users.ibd）
  ├─ 数据段（聚簇索引叶子节点）
  │   ├─ 区1（1MB = 64页）
  │   │   ├─ 页1（16KB）：行1-200
  │   │   ├─ 页2（16KB）：行201-400
  │   │   ├─ ...
  │   │   └─ 页64（16KB）
  │   └─ 区2（1MB）
  ├─ 索引段（聚簇索引非叶子节点）
  │   └─ 区3（1MB）
  └─ 索引段（idx_name二级索引）
      └─ 区4（1MB）
```

---

## 性能影响

### 1. 页大小与B+树高度

```
假设：
- 主键INT（4字节）
- 每个索引项14字节（主键4 + 页号6 + 其他4）
- 非叶子节点填充率67%

16KB页可以存储：
16384 × 67% / 14 ≈ 783个索引项

B+树高度计算：
- 高度1：1个根节点（索引页），1个叶子节点（数据页）
- 高度2：1个根节点 + 783个叶子节点 = 783 × 80（每页80行） ≈ 62,640行
- 高度3：1个根节点 + 783个分支节点 + 783×783个叶子节点 ≈ 4900万行
```

**结论**：3层B+树可以存储约5000万行数据！

### 2. 顺序IO vs 随机IO

```
顺序扫描（区为单位）：
读取1MB（64页） = 1次磁盘寻址 + 顺序读取

随机读取（页为单位）：
读取64页 = 64次磁盘寻址（慢10倍+）
```

---

## 实战建议

### 1. 使用独立表空间

```ini
# my.cnf
[mysqld]
innodb_file_per_table = 1  # 默认ON
```

### 2. 监控表空间大小

```sql
-- 查看表空间大小
SELECT
    table_name,
    ROUND(data_length/1024/1024, 2) AS data_mb,
    ROUND(index_length/1024/1024, 2) AS index_mb,
    ROUND((data_length + index_length)/1024/1024, 2) AS total_mb
FROM information_schema.TABLES
WHERE table_schema = 'test';
```

### 3. 回收空间

```sql
-- 删除数据后，空间未释放
DELETE FROM users WHERE id < 1000;
-- 表空间仍是原大小

-- 优化表，回收空间
OPTIMIZE TABLE users;
-- 或重建表
ALTER TABLE users ENGINE=InnoDB;
```

### 4. 分区表（大表优化）

```sql
-- 按范围分区
CREATE TABLE orders (
    id INT,
    order_date DATE,
    amount DECIMAL(10,2)
) PARTITION BY RANGE (YEAR(order_date)) (
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p2025 VALUES LESS THAN (2026)
);

-- 每个分区一个独立表空间
orders#P#p2023.ibd
orders#P#p2024.ibd
orders#P#p2025.ibd
```

---

## 常见面试题

**Q1: InnoDB的存储层次是什么？**
- 表空间 → 段 → 区（1MB） → 页（16KB） → 行

**Q2: 为什么InnoDB的页大小是16KB？**
- 磁盘IO优化、缓存效率、B+树高度控制

**Q3: 一个3层B+树可以存储多少行数据？**
- 约5000万行（假设每页80行）

**Q4: 如何回收DELETE后的表空间？**
- OPTIMIZE TABLE 或 ALTER TABLE ENGINE=InnoDB

---

## 小结

✅ **表空间**：最顶层，包含段（系统表空间、独立表空间）
✅ **段**：索引段、数据段、回滚段
✅ **区**：1MB = 64页，减少碎片
✅ **页**：16KB，InnoDB的基本IO单位
✅ **行**：实际数据存储

理解InnoDB存储结构是性能优化的基础。

---

📚 **相关阅读**：
- 下一篇：《InnoDB行格式：Compact、Redundant、Dynamic》
- 推荐：《Buffer Pool：MySQL的内存管理》
