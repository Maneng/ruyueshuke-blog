---
title: "库存管理：精准控制与实时同步"
date: 2025-11-22T13:00:00+08:00
draft: false
tags: ["WMS", "库存管理", "库存盘点", "库存调拨"]
categories: ["业务"]
description: "掌握库存管理的核心逻辑，理解库存查询、盘点、调拨和预警的最佳实践"
series: ["WMS从入门到精通"]
weight: 5
stage: 2
stageTitle: "业务实践篇"
---

## 引言

库存准确性是WMS的生命线。本文深入讲解库存管理的核心业务，包括库存查询、盘点、调拨和预警机制。

---

## 1. 库存的三个维度

### 1.1 可用库存、锁定库存、在途库存

```
总库存 = 可用库存 + 锁定库存 + 在途库存

示例：
总库存: 1000件
可用库存: 800件（可以销售）
锁定库存: 150件（已分配订单，未出库）
在途库存: 50件（调拨中，未到达）
```

### 1.2 库存扣减逻辑（防止超卖）

```sql
-- 悲观锁方案
BEGIN;
SELECT available_qty FROM inventory
WHERE sku_code = 'iPhone-15Pro' FOR UPDATE;

-- 扣减库存（原子操作）
UPDATE inventory
SET available_qty = available_qty - 1,
    locked_qty = locked_qty + 1
WHERE sku_code = 'iPhone-15Pro'
  AND available_qty >= 1;  -- 防止超卖
COMMIT;
```

---

## 2. 库存查询与统计

### 2.1 多维度查询

**1. 按SKU查询**
```sql
SELECT * FROM inventory WHERE sku_code = 'iPhone-15Pro';
```

**2. 按库位查询**
```sql
SELECT * FROM inventory WHERE location_code = 'A01-02-03';
```

**3. 按批次查询**
```sql
SELECT * FROM inventory WHERE batch_no = '20251120';
```

**4. 库龄分析**
```sql
SELECT
  sku_code,
  DATEDIFF(NOW(), created_at) AS age_days,
  qty
FROM inventory
WHERE DATEDIFF(NOW(), created_at) > 180  -- 库龄>180天
ORDER BY age_days DESC;
```

---

## 3. 库存盘点

### 3.1 盘点类型

**1. 全盘（Full Inventory Count）**
- **频率**：年度1次
- **范围**：所有库存
- **影响**：停业盘点，影响业务
- **准确率**：100%

**2. 循环盘点（Cycle Count）**
- **频率**：每天/每周
- **范围**：部分库存（ABC分类）
- **影响**：不停业，持续盘点
- **准确率**：99.5%

**3. 抽盘（Spot Check）**
- **频率**：随机抽查
- **范围**：高风险SKU
- **影响**：最小
- **准确率**：抽查验证

---

### 3.2 ABC分类盘点策略

```
A类商品（20% SKU，80%销售额）：
  - 盘点频率：每周1次
  - 盘点方式：循环盘点

B类商品（30% SKU，15%销售额）：
  - 盘点频率：每月1次
  - 盘点方式：循环盘点

C类商品（50% SKU，5%销售额）：
  - 盘点频率：每季度1次
  - 盘点方式：抽盘
```

---

### 3.3 盘点流程

```
生成盘点单 → 分配盘点员 → RF盘点 → 差异分析
→ 差异审批 → 库存调整 → 对账报告
```

**RF盘点界面**：
```
┌─────────────────────────┐
│  库位盘点               │
├─────────────────────────┤
│ 盘点单: INV20251122001  │
│ 库位: A01-02-03         │
│                         │
│ 扫描商品条码 ►          │
└─────────────────────────┘
       ↓（扫描后）
┌─────────────────────────┐
│  SKU: iPhone-15Pro      │
├─────────────────────────┤
│ 账面数量: 100           │
│ 实盘数量: [___]         │
│                         │
│ 输入实盘数量 ►          │
└─────────────────────────┘
       ↓（输入98）
┌─────────────────────────┐
│  盘点差异               │
├─────────────────────────┤
│ 账面: 100               │
│ 实盘: 98                │
│ 差异: -2 ❌             │
│                         │
│ 原因: [选择]            │
│ □ 系统错误              │
│ □ 盘点错误              │
│ ☑ 实物丢失              │
│                         │
│ [提交] [取消]           │
└─────────────────────────┘
```

---

### 3.4 盘点差异处理

**常见差异原因**：
1. 系统错误：入库未记录、出库未扣减
2. 盘点错误：漏盘、重复盘、扫描错误
3. 实物丢失：盗窃、损坏、质量问题

**处理流程**：
```sql
-- 记录差异
INSERT INTO inventory_check_exception (
  check_no, sku_code, location_code,
  book_qty, actual_qty, diff_qty, reason
)
VALUES (
  'INV20251122001', 'iPhone-15Pro', 'A01-02-03',
  100, 98, -2, '实物丢失'
);

-- 审批后调整库存
UPDATE inventory
SET qty = 98, available_qty = 98
WHERE sku_code = 'iPhone-15Pro' AND location_code = 'A01-02-03';
```

---

## 4. 库存调拨

### 4.1 库内调拨

**场景**：库位间移动（库位优化、商品整理）

**流程**：
```
生成调拨单 → RF拣货（源库位） → RF上架（目标库位）
→ 库存更新
```

**数据更新**：
```sql
-- 扣减源库位
UPDATE inventory
SET qty = qty - 10
WHERE location_code = 'A01-02-03' AND sku_code = 'iPhone-15Pro';

-- 增加目标库位
UPDATE inventory
SET qty = qty + 10
WHERE location_code = 'A01-02-05' AND sku_code = 'iPhone-15Pro';
```

---

### 4.2 跨仓调拨

**场景**：仓库间转移（平衡库存、就近发货）

**流程**：
```
源仓库出库 → 在途库存 → 目标仓库入库
```

**在途库存管理**：
```sql
-- 源仓库出库：扣减可用库存，增加在途库存
UPDATE inventory
SET available_qty = available_qty - 100,
    in_transit_qty = in_transit_qty + 100
WHERE warehouse_code = 'WH001' AND sku_code = 'iPhone-15Pro';

-- 目标仓库入库：减少在途库存，增加可用库存
UPDATE inventory
SET in_transit_qty = in_transit_qty - 100,
    available_qty = available_qty + 100
WHERE warehouse_code = 'WH002' AND sku_code = 'iPhone-15Pro';
```

---

## 5. 安全库存与预警

### 5.1 安全库存计算

**公式**：
```
安全库存 = 平均日销量 × 补货周期 × 安全系数

示例：
平均日销量: 50件/天
补货周期: 7天（供应商发货时间）
安全系数: 1.5（应对波动）

安全库存 = 50 × 7 × 1.5 = 525件
```

---

### 5.2 库存预警规则

**预警类型**：

**1. 低库存预警**
```sql
SELECT sku_code, available_qty, safety_stock
FROM inventory
WHERE available_qty < safety_stock;
```

**2. 高库存预警**
```sql
SELECT sku_code, available_qty, max_stock
FROM inventory
WHERE available_qty > max_stock;
```

**3. 库龄预警**
```sql
SELECT sku_code, qty, DATEDIFF(NOW(), created_at) AS age_days
FROM inventory
WHERE DATEDIFF(NOW(), created_at) > 180;  -- 库龄>6个月
```

---

## 6. 库存对账

### 6.1 与上游系统对账

**对账维度**：
1. 与ERP对账：财务库存 vs 实物库存
2. 与OMS对账：可用库存一致性

**对账流程**：
```
定时任务（每天凌晨2点）
  ↓
导出WMS库存
  ↓
导出ERP库存
  ↓
差异比对
  ↓
差异报表 → 通知管理员
```

---

## 7. 总结

**库存管理核心要点**：
1. **三个维度**：可用、锁定、在途
2. **盘点策略**：ABC分类，循环盘点
3. **调拨管理**：库内调拨、跨仓调拨
4. **预警机制**：低库存、高库存、库龄

**下一篇预告**：库位管理与优化策略

---

**版权声明**：本文为原创文章，转载请注明出处。
