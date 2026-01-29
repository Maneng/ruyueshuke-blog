---
title: "ERP核心模块设计——财务、采购、库存三位一体"
date: 2026-01-29T17:20:00+08:00
draft: false
tags: ["ERP", "财务系统", "采购管理", "库存管理", "跨境电商"]
categories: ["数字化转型"]
description: "跨境电商ERP与传统ERP有何不同？本文详解ERP的核心模块设计，包括财务核算、采购管理、库存管理，以及与OMS/WMS的集成方案。"
series: ["跨境电商数字化转型指南"]
weight: 10
---

## 引言：跨境电商ERP的特殊性

传统ERP（如SAP、Oracle）是为制造业设计的，而跨境电商有其特殊性：

| 维度 | 传统ERP | 跨境电商ERP |
|-----|--------|-----------|
| 销售渠道 | 单一/少量 | 多渠道（Amazon、eBay等） |
| 币种 | 单一 | 多币种 |
| 仓库 | 集中 | 分布式（国内+海外） |
| 订单量 | 少量大单 | 大量小单 |
| 库存管理 | 批次管理 | SKU+批次+效期 |

**因此，跨境电商需要一套适合自己的ERP设计。**

---

## 一、ERP在系统矩阵中的定位

### 1.1 系统边界

```
┌─────────────────────────────────────────────────────┐
│                      OMS                             │
│              订单管理（销售端）                        │
└─────────────────────┬───────────────────────────────┘
                      │ 销售数据
                      ▼
┌─────────────────────────────────────────────────────┐
│                      ERP                             │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐               │
│  │ 财务模块 │ │ 采购模块 │ │ 库存模块 │               │
│  └─────────┘ └─────────┘ └─────────┘               │
└─────────────────────┬───────────────────────────────┘
                      │ 采购/入库指令
                      ▼
┌─────────────────────────────────────────────────────┐
│                      WMS                             │
│              仓储执行（实物管理）                      │
└─────────────────────────────────────────────────────┘
```

### 1.2 职责划分

| 功能 | OMS | ERP | WMS |
|-----|-----|-----|-----|
| 销售订单 | ✓ | | |
| 可售库存 | ✓ | | |
| 财务核算 | | ✓ | |
| 采购管理 | | ✓ | |
| 账面库存 | | ✓ | |
| 实物库存 | | | ✓ |
| 库位管理 | | | ✓ |

---

## 二、财务模块设计

### 2.1 跨境电商财务特点

**多币种挑战**：
- 销售币种：USD、EUR、GBP、JPY等
- 采购币种：CNY、USD
- 记账本位币：CNY

**多主体挑战**：
- 国内公司
- 香港公司
- 海外公司
- 关联交易

### 2.2 核心功能

```
┌─────────────────────────────────────────────────────┐
│                    财务模块                          │
├─────────────────────────────────────────────────────┤
│  应收管理                                           │
│  ├── 销售收入确认                                   │
│  ├── 平台结算对账                                   │
│  └── 应收账款管理                                   │
├─────────────────────────────────────────────────────┤
│  应付管理                                           │
│  ├── 采购应付登记                                   │
│  ├── 发票核对                                       │
│  └── 付款管理                                       │
├─────────────────────────────────────────────────────┤
│  成本核算                                           │
│  ├── 商品成本计算                                   │
│  ├── 物流成本分摊                                   │
│  └── 平台费用核算                                   │
├─────────────────────────────────────────────────────┤
│  汇兑管理                                           │
│  ├── 汇率维护                                       │
│  ├── 汇兑损益计算                                   │
│  └── 外币报表                                       │
└─────────────────────────────────────────────────────┘
```

### 2.3 数据模型

```sql
-- 会计科目表
CREATE TABLE t_account (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    account_code VARCHAR(32) NOT NULL,
    account_name VARCHAR(128) NOT NULL,
    account_type VARCHAR(16) NOT NULL, -- ASSET/LIABILITY/EQUITY/INCOME/EXPENSE
    parent_code VARCHAR(32),
    level INT NOT NULL,
    is_leaf TINYINT DEFAULT 1,
    currency VARCHAR(8),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_account_code (account_code)
);

-- 会计凭证表
CREATE TABLE t_voucher (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    voucher_no VARCHAR(32) NOT NULL,
    voucher_date DATE NOT NULL,
    period VARCHAR(8) NOT NULL, -- 202401
    voucher_type VARCHAR(16), -- 收/付/转
    description VARCHAR(512),
    total_debit DECIMAL(16,2),
    total_credit DECIMAL(16,2),
    status VARCHAR(16) DEFAULT 'DRAFT',
    created_by VARCHAR(64),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_voucher_no (voucher_no)
);

-- 凭证明细表
CREATE TABLE t_voucher_item (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    voucher_no VARCHAR(32) NOT NULL,
    seq INT NOT NULL,
    account_code VARCHAR(32) NOT NULL,
    description VARCHAR(256),
    currency VARCHAR(8) DEFAULT 'CNY',
    exchange_rate DECIMAL(10,6) DEFAULT 1,
    original_amount DECIMAL(16,2), -- 原币金额
    debit_amount DECIMAL(16,2),    -- 借方本位币
    credit_amount DECIMAL(16,2),   -- 贷方本位币
    KEY idx_voucher_no (voucher_no)
);

-- 汇率表
CREATE TABLE t_exchange_rate (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    from_currency VARCHAR(8) NOT NULL,
    to_currency VARCHAR(8) NOT NULL,
    rate_date DATE NOT NULL,
    rate DECIMAL(10,6) NOT NULL,
    UNIQUE KEY uk_currency_date (from_currency, to_currency, rate_date)
);
```

### 2.4 成本核算方法

**移动加权平均法**：

```java
@Service
public class CostCalculationService {

    /**
     * 移动加权平均法计算成本
     *
     * 公式：新单位成本 = (原库存金额 + 本次入库金额) / (原库存数量 + 本次入库数量)
     */
    public BigDecimal calculateMovingAverageCost(String skuId, int inboundQty, BigDecimal inboundAmount) {
        // 获取当前库存
        InventoryCost current = inventoryCostRepository.findBySkuId(skuId);

        if (current == null) {
            // 首次入库
            return inboundAmount.divide(BigDecimal.valueOf(inboundQty), 4, RoundingMode.HALF_UP);
        }

        // 计算新的加权平均成本
        BigDecimal totalAmount = current.getTotalAmount().add(inboundAmount);
        int totalQty = current.getQuantity() + inboundQty;

        BigDecimal newUnitCost = totalAmount.divide(BigDecimal.valueOf(totalQty), 4, RoundingMode.HALF_UP);

        // 更新库存成本
        current.setQuantity(totalQty);
        current.setTotalAmount(totalAmount);
        current.setUnitCost(newUnitCost);
        inventoryCostRepository.save(current);

        return newUnitCost;
    }

    /**
     * 出库成本计算
     */
    public BigDecimal calculateOutboundCost(String skuId, int outboundQty) {
        InventoryCost current = inventoryCostRepository.findBySkuId(skuId);

        if (current == null || current.getQuantity() < outboundQty) {
            throw new InsufficientInventoryException(skuId);
        }

        // 出库金额 = 出库数量 × 单位成本
        BigDecimal outboundAmount = current.getUnitCost().multiply(BigDecimal.valueOf(outboundQty));

        // 更新库存
        current.setQuantity(current.getQuantity() - outboundQty);
        current.setTotalAmount(current.getTotalAmount().subtract(outboundAmount));
        inventoryCostRepository.save(current);

        return outboundAmount;
    }
}
```

---

## 三、采购模块设计

### 3.1 采购流程

```
需求计划 ──> 询价比价 ──> 采购下单 ──> 到货验收 ──> 入库结算
    │           │           │           │           │
    ▼           ▼           ▼           ▼           ▼
 生成计划    选择供应商   创建PO     WMS收货    财务应付
```

### 3.2 核心功能

**供应商管理**：
- 供应商档案
- 供应商评级
- 价格协议

**采购计划**：
- 安全库存预警
- 采购建议生成
- 计划审批

**采购订单**：
- PO创建
- PO审批
- PO跟踪

**到货管理**：
- ASN预约
- 到货登记
- 质检管理

### 3.3 数据模型

```sql
-- 供应商表
CREATE TABLE t_supplier (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    supplier_code VARCHAR(32) NOT NULL,
    supplier_name VARCHAR(128) NOT NULL,
    contact_name VARCHAR(64),
    contact_phone VARCHAR(32),
    address VARCHAR(256),
    payment_terms VARCHAR(64), -- 账期
    rating VARCHAR(8), -- A/B/C/D
    status VARCHAR(16) DEFAULT 'ACTIVE',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_supplier_code (supplier_code)
);

-- 采购订单表
CREATE TABLE t_purchase_order (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    po_no VARCHAR(32) NOT NULL,
    supplier_code VARCHAR(32) NOT NULL,
    warehouse_id VARCHAR(32),
    order_date DATE NOT NULL,
    expected_date DATE,
    currency VARCHAR(8) DEFAULT 'CNY',
    total_amount DECIMAL(16,2),
    status VARCHAR(16) DEFAULT 'DRAFT',
    created_by VARCHAR(64),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_po_no (po_no)
);

-- 采购订单明细表
CREATE TABLE t_purchase_order_item (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    po_no VARCHAR(32) NOT NULL,
    seq INT NOT NULL,
    sku_id VARCHAR(32) NOT NULL,
    sku_name VARCHAR(256),
    quantity INT NOT NULL,
    unit_price DECIMAL(12,4),
    amount DECIMAL(16,2),
    received_qty INT DEFAULT 0,
    KEY idx_po_no (po_no)
);
```

### 3.4 采购建议算法

```java
@Service
public class PurchaseSuggestionService {

    /**
     * 生成采购建议
     *
     * 建议采购量 = 目标库存 - 当前可用库存 - 在途库存
     * 目标库存 = 安全库存 + 预计销量 × 采购周期
     */
    public List<PurchaseSuggestion> generateSuggestions() {
        List<PurchaseSuggestion> suggestions = new ArrayList<>();

        // 获取所有需要补货的SKU
        List<SkuInventory> inventories = inventoryRepository.findAll();

        for (SkuInventory inv : inventories) {
            String skuId = inv.getSkuId();

            // 获取SKU配置
            SkuConfig config = skuConfigRepository.findBySkuId(skuId);
            if (config == null) continue;

            // 计算目标库存
            int safetyStock = config.getSafetyStock();
            int avgDailySales = calculateAvgDailySales(skuId, 30); // 近30天日均销量
            int leadTime = config.getLeadTimeDays(); // 采购周期
            int targetStock = safetyStock + avgDailySales * leadTime;

            // 计算当前可用
            int availableStock = inv.getAvailableQty();
            int inTransitStock = getInTransitQty(skuId);

            // 计算建议采购量
            int suggestQty = targetStock - availableStock - inTransitStock;

            if (suggestQty > 0) {
                PurchaseSuggestion suggestion = new PurchaseSuggestion();
                suggestion.setSkuId(skuId);
                suggestion.setCurrentStock(availableStock);
                suggestion.setInTransitStock(inTransitStock);
                suggestion.setTargetStock(targetStock);
                suggestion.setSuggestQty(suggestQty);
                suggestion.setSupplierId(config.getPreferredSupplierId());
                suggestions.add(suggestion);
            }
        }

        return suggestions;
    }
}
```

---

## 四、库存模块设计

### 4.1 ERP库存 vs WMS库存

| 维度 | ERP库存（账面库存） | WMS库存（实物库存） |
|-----|-------------------|-------------------|
| 管理粒度 | SKU级别 | SKU+库位级别 |
| 更新时机 | 财务确认后 | 实物操作后 |
| 主要用途 | 财务核算、成本计算 | 仓储执行、拣货 |
| 数据来源 | WMS同步 | 实物操作 |

### 4.2 库存同步机制

```java
@Service
public class InventorySyncService {

    /**
     * WMS库存变动同步到ERP
     */
    @RocketMQMessageListener(topic = "wms-inventory-change")
    public void onWmsInventoryChange(InventoryChangeEvent event) {
        String skuId = event.getSkuId();
        String warehouseId = event.getWarehouseId();
        int changeQty = event.getChangeQty();
        String changeType = event.getChangeType(); // IN/OUT/ADJUST

        // 更新ERP库存
        ErpInventory erpInventory = erpInventoryRepository.findBySkuAndWarehouse(skuId, warehouseId);
        if (erpInventory == null) {
            erpInventory = new ErpInventory();
            erpInventory.setSkuId(skuId);
            erpInventory.setWarehouseId(warehouseId);
            erpInventory.setQuantity(0);
        }

        switch (changeType) {
            case "IN":
                erpInventory.setQuantity(erpInventory.getQuantity() + changeQty);
                // 入库需要计算成本
                costCalculationService.calculateMovingAverageCost(skuId, changeQty, event.getAmount());
                break;
            case "OUT":
                erpInventory.setQuantity(erpInventory.getQuantity() - changeQty);
                // 出库需要结转成本
                costCalculationService.calculateOutboundCost(skuId, changeQty);
                break;
            case "ADJUST":
                erpInventory.setQuantity(erpInventory.getQuantity() + changeQty);
                // 盘点差异处理
                handleInventoryAdjustment(skuId, changeQty);
                break;
        }

        erpInventoryRepository.save(erpInventory);
    }
}
```

---

## 五、与外部系统集成

### 5.1 与金蝶/用友对接

**对接方案**：

```
┌─────────────────────────────────────────────────────┐
│                    自研ERP                           │
│         (采购、库存、业务数据)                        │
└─────────────────────┬───────────────────────────────┘
                      │ 凭证数据
                      ▼
┌─────────────────────────────────────────────────────┐
│                   中间层                             │
│              (数据转换、格式适配)                     │
└─────────────────────┬───────────────────────────────┘
                      │ 标准凭证
                      ▼
┌─────────────────────────────────────────────────────┐
│                 金蝶/用友                            │
│            (财务核算、报表输出)                       │
└─────────────────────────────────────────────────────┘
```

**凭证同步接口**：

```java
@Service
public class FinanceSystemSyncService {

    /**
     * 同步凭证到金蝶
     */
    public void syncVoucherToKingdee(Voucher voucher) {
        // 转换为金蝶凭证格式
        KingdeeVoucher kdVoucher = convertToKingdee(voucher);

        // 调用金蝶API
        kingdeeApiClient.createVoucher(kdVoucher);

        // 更新同步状态
        voucher.setSyncStatus("SYNCED");
        voucherRepository.save(voucher);
    }

    private KingdeeVoucher convertToKingdee(Voucher voucher) {
        KingdeeVoucher kd = new KingdeeVoucher();
        kd.setFDate(voucher.getVoucherDate());
        kd.setFNumber(voucher.getVoucherNo());

        List<KingdeeVoucherEntry> entries = new ArrayList<>();
        for (VoucherItem item : voucher.getItems()) {
            KingdeeVoucherEntry entry = new KingdeeVoucherEntry();
            entry.setFAccountId(mapAccountCode(item.getAccountCode()));
            entry.setFDebit(item.getDebitAmount());
            entry.setFCredit(item.getCreditAmount());
            entry.setFExplanation(item.getDescription());
            entries.add(entry);
        }
        kd.setFEntity(entries);

        return kd;
    }
}
```

---

## 六、报表设计

### 6.1 核心报表

| 报表 | 用途 | 数据来源 |
|-----|-----|---------|
| 利润表 | 查看盈利情况 | 销售收入、成本、费用 |
| 库存报表 | 查看库存状况 | ERP库存数据 |
| 采购报表 | 查看采购情况 | 采购订单数据 |
| 应收报表 | 查看回款情况 | 平台结算数据 |
| 应付报表 | 查看付款情况 | 采购应付数据 |

### 6.2 利润计算

```java
@Service
public class ProfitReportService {

    /**
     * 计算SKU利润
     *
     * 毛利 = 销售收入 - 商品成本 - 平台费用 - 物流费用
     * 毛利率 = 毛利 / 销售收入
     */
    public SkuProfitReport calculateSkuProfit(String skuId, String period) {
        SkuProfitReport report = new SkuProfitReport();
        report.setSkuId(skuId);
        report.setPeriod(period);

        // 销售收入
        BigDecimal salesRevenue = orderService.getSalesRevenue(skuId, period);
        report.setSalesRevenue(salesRevenue);

        // 商品成本
        BigDecimal productCost = costService.getProductCost(skuId, period);
        report.setProductCost(productCost);

        // 平台费用（佣金、广告等）
        BigDecimal platformFee = feeService.getPlatformFee(skuId, period);
        report.setPlatformFee(platformFee);

        // 物流费用
        BigDecimal shippingCost = feeService.getShippingCost(skuId, period);
        report.setShippingCost(shippingCost);

        // 计算毛利
        BigDecimal grossProfit = salesRevenue
            .subtract(productCost)
            .subtract(platformFee)
            .subtract(shippingCost);
        report.setGrossProfit(grossProfit);

        // 计算毛利率
        if (salesRevenue.compareTo(BigDecimal.ZERO) > 0) {
            BigDecimal grossMargin = grossProfit.divide(salesRevenue, 4, RoundingMode.HALF_UP);
            report.setGrossMargin(grossMargin);
        }

        return report;
    }
}
```

---

## 七、总结

### 7.1 核心要点

1. **财务模块**：多币种、多主体、成本核算
2. **采购模块**：供应商管理、采购计划、到货管理
3. **库存模块**：账面库存、与WMS同步
4. **外部集成**：与金蝶/用友对接

### 7.2 实施建议

- 财务核算建议采购成熟产品（金蝶/用友）
- 采购和库存模块可以自研
- 重点做好与OMS/WMS的集成

---

> **系列文章导航**
>
> 本文是《跨境电商数字化转型指南》系列的第10篇
>
> - [x] 01-09. 前序文章
> - [x] 10. ERP核心模块设计（本文）
> - [ ] 11. 采购管理系统详解
> - [ ] 12. 财务核算模块详解
