---
title: "库存成本核算——移动加权平均法实战"
date: 2026-02-04T16:00:00+08:00
draft: false
tags: ["ERP", "库存管理", "成本核算", "移动加权平均", "跨境电商"]
categories: ["数字化转型"]
description: "深入讲解跨境电商库存成本核算方法，重点介绍移动加权平均法的算法实现、特殊场景处理、月结流程设计，以及与财务系统的对接方案。"
series: ["跨境电商数字化转型指南"]
weight: 13
---

## 引言

在跨境电商业务中，库存成本核算是一个看似简单实则复杂的问题。同一个SKU，不同批次的采购价格可能差异很大——汇率波动、供应商调价、运费变化都会影响入库成本。当这个SKU出库时，应该按什么成本计算？

这个问题直接影响：
- **毛利计算**：成本算错，毛利就错
- **库存估值**：影响资产负债表
- **定价决策**：成本不准，定价就没有依据
- **税务合规**：成本核算方法需要符合会计准则

本文将深入讲解库存成本核算的核心方法，重点介绍**移动加权平均法**的算法实现、特殊场景处理和月结流程设计。

---

## 一、成本核算方法对比

### 1.1 三种主流方法

| 方法 | 原理 | 优点 | 缺点 | 适用场景 |
|-----|------|-----|------|---------|
| **先进先出法(FIFO)** | 先入库的先出库 | 符合实物流转，成本反映真实 | 计算复杂，需追踪批次 | 有保质期的商品 |
| **移动加权平均法** | 每次入库重新计算平均成本 | 成本平滑，计算相对简单 | 无法追溯具体批次成本 | 标准化商品 |
| **个别计价法** | 每个商品单独计价 | 成本最准确 | 管理成本高 | 高价值、可识别商品 |

### 1.2 跨境电商的选择

对于年营收5-7亿的跨境电商，**移动加权平均法**是最佳选择：

**选择理由**：
1. **SKU数量大**：通常有数万SKU，FIFO管理成本太高
2. **标准化商品**：大部分是标准化产品，无需追溯批次
3. **价格波动频繁**：汇率、运费变化大，平均法能平滑波动
4. **财务软件兼容**：金蝶、用友等主流财务软件都支持

**不适用场景**：
- 有保质期的商品（食品、化妆品）→ 建议FIFO
- 高价值单品（珠宝、艺术品）→ 建议个别计价
- 有序列号管理需求的商品 → 建议个别计价

---

## 二、移动加权平均算法详解

### 2.1 核心公式

```
新单位成本 = (原库存金额 + 本次入库金额) / (原库存数量 + 本次入库数量)
```

**示例**：
- 原库存：100件，单位成本10元，库存金额1000元
- 本次入库：50件，单位成本12元，入库金额600元
- 新单位成本 = (1000 + 600) / (100 + 50) = 10.67元

### 2.2 数据模型设计

```sql
-- 库存成本主表
CREATE TABLE inventory_cost (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    sku_code VARCHAR(50) NOT NULL COMMENT 'SKU编码',
    warehouse_code VARCHAR(50) NOT NULL COMMENT '仓库编码',
    quantity DECIMAL(18,4) NOT NULL DEFAULT 0 COMMENT '当前库存数量',
    unit_cost DECIMAL(18,6) NOT NULL DEFAULT 0 COMMENT '单位成本(6位小数)',
    total_cost DECIMAL(18,4) NOT NULL DEFAULT 0 COMMENT '库存总成本',
    last_in_cost DECIMAL(18,6) COMMENT '最近入库成本',
    last_in_time DATETIME COMMENT '最近入库时间',
    version INT NOT NULL DEFAULT 0 COMMENT '乐观锁版本号',
    created_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uk_sku_warehouse (sku_code, warehouse_code)
) COMMENT '库存成本主表';

-- 成本变动流水表
CREATE TABLE inventory_cost_log (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    sku_code VARCHAR(50) NOT NULL COMMENT 'SKU编码',
    warehouse_code VARCHAR(50) NOT NULL COMMENT '仓库编码',
    biz_type VARCHAR(30) NOT NULL COMMENT '业务类型:PURCHASE_IN/SALE_OUT/RETURN_IN/TRANSFER/ADJUST',
    biz_no VARCHAR(50) NOT NULL COMMENT '业务单号',
    direction TINYINT NOT NULL COMMENT '方向:1入库,-1出库',
    quantity DECIMAL(18,4) NOT NULL COMMENT '变动数量',
    unit_cost DECIMAL(18,6) NOT NULL COMMENT '本次单位成本',
    amount DECIMAL(18,4) NOT NULL COMMENT '本次金额',
    before_quantity DECIMAL(18,4) NOT NULL COMMENT '变动前数量',
    before_unit_cost DECIMAL(18,6) NOT NULL COMMENT '变动前单位成本',
    before_total_cost DECIMAL(18,4) NOT NULL COMMENT '变动前总成本',
    after_quantity DECIMAL(18,4) NOT NULL COMMENT '变动后数量',
    after_unit_cost DECIMAL(18,6) NOT NULL COMMENT '变动后单位成本',
    after_total_cost DECIMAL(18,4) NOT NULL COMMENT '变动后总成本',
    created_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_sku_warehouse (sku_code, warehouse_code),
    INDEX idx_biz_no (biz_no),
    INDEX idx_created_time (created_time)
) COMMENT '成本变动流水表';
```

### 2.3 核心算法实现

```java
/**
 * 库存成本服务
 * 实现移动加权平均法
 */
@Service
@Slf4j
public class InventoryCostService {

    @Autowired
    private InventoryCostMapper costMapper;

    @Autowired
    private InventoryCostLogMapper logMapper;

    /**
     * 入库成本计算
     * 核心公式：新单位成本 = (原库存金额 + 本次入库金额) / (原库存数量 + 本次入库数量)
     */
    @Transactional(rollbackFor = Exception.class)
    public void processInbound(CostChangeRequest request) {
        String skuCode = request.getSkuCode();
        String warehouseCode = request.getWarehouseCode();
        BigDecimal inQuantity = request.getQuantity();
        BigDecimal inUnitCost = request.getUnitCost();

        // 1. 获取当前库存成本（加锁）
        InventoryCost cost = costMapper.selectForUpdate(skuCode, warehouseCode);

        // 2. 记录变动前状态
        CostSnapshot before = createSnapshot(cost);

        // 3. 计算新成本
        BigDecimal beforeQuantity = cost != null ? cost.getQuantity() : BigDecimal.ZERO;
        BigDecimal beforeTotalCost = cost != null ? cost.getTotalCost() : BigDecimal.ZERO;

        BigDecimal inAmount = inQuantity.multiply(inUnitCost);
        BigDecimal afterQuantity = beforeQuantity.add(inQuantity);
        BigDecimal afterTotalCost = beforeTotalCost.add(inAmount);

        // 移动加权平均计算
        BigDecimal afterUnitCost;
        if (afterQuantity.compareTo(BigDecimal.ZERO) > 0) {
            afterUnitCost = afterTotalCost.divide(afterQuantity, 6, RoundingMode.HALF_UP);
        } else {
            afterUnitCost = inUnitCost; // 库存为0时，使用入库成本
        }

        // 4. 更新库存成本
        if (cost == null) {
            cost = new InventoryCost();
            cost.setSkuCode(skuCode);
            cost.setWarehouseCode(warehouseCode);
            cost.setQuantity(afterQuantity);
            cost.setUnitCost(afterUnitCost);
            cost.setTotalCost(afterTotalCost);
            cost.setLastInCost(inUnitCost);
            cost.setLastInTime(new Date());
            costMapper.insert(cost);
        } else {
            cost.setQuantity(afterQuantity);
            cost.setUnitCost(afterUnitCost);
            cost.setTotalCost(afterTotalCost);
            cost.setLastInCost(inUnitCost);
            cost.setLastInTime(new Date());
            int rows = costMapper.updateWithVersion(cost);
            if (rows == 0) {
                throw new ConcurrentModificationException("库存成本更新冲突，请重试");
            }
        }

        // 5. 记录成本流水
        CostSnapshot after = createSnapshot(cost);
        saveCostLog(request, before, after, 1);

        log.info("入库成本计算完成: sku={}, warehouse={}, 入库数量={}, 入库成本={}, " +
                "新单位成本={}, 新库存数量={}",
                skuCode, warehouseCode, inQuantity, inUnitCost, afterUnitCost, afterQuantity);
    }

    /**
     * 出库成本计算
     * 出库时按当前单位成本计算
     */
    @Transactional(rollbackFor = Exception.class)
    public BigDecimal processOutbound(CostChangeRequest request) {
        String skuCode = request.getSkuCode();
        String warehouseCode = request.getWarehouseCode();
        BigDecimal outQuantity = request.getQuantity();

        // 1. 获取当前库存成本（加锁）
        InventoryCost cost = costMapper.selectForUpdate(skuCode, warehouseCode);
        if (cost == null || cost.getQuantity().compareTo(outQuantity) < 0) {
            throw new BusinessException("库存不足，无法出库");
        }

        // 2. 记录变动前状态
        CostSnapshot before = createSnapshot(cost);

        // 3. 计算出库金额（使用当前单位成本）
        BigDecimal outUnitCost = cost.getUnitCost();
        BigDecimal outAmount = outQuantity.multiply(outUnitCost);

        // 4. 更新库存
        BigDecimal afterQuantity = cost.getQuantity().subtract(outQuantity);
        BigDecimal afterTotalCost = cost.getTotalCost().subtract(outAmount);

        // 单位成本保持不变（出库不改变单位成本）
        cost.setQuantity(afterQuantity);
        cost.setTotalCost(afterTotalCost);

        int rows = costMapper.updateWithVersion(cost);
        if (rows == 0) {
            throw new ConcurrentModificationException("库存成本更新冲突，请重试");
        }

        // 5. 记录成本流水
        CostSnapshot after = createSnapshot(cost);
        request.setUnitCost(outUnitCost); // 设置出库成本
        saveCostLog(request, before, after, -1);

        log.info("出库成本计算完成: sku={}, warehouse={}, 出库数量={}, 出库成本={}, " +
                "出库金额={}",
                skuCode, warehouseCode, outQuantity, outUnitCost, outAmount);

        return outAmount; // 返回出库金额，用于计算销售成本
    }

    /**
     * 创建成本快照
     */
    private CostSnapshot createSnapshot(InventoryCost cost) {
        CostSnapshot snapshot = new CostSnapshot();
        if (cost != null) {
            snapshot.setQuantity(cost.getQuantity());
            snapshot.setUnitCost(cost.getUnitCost());
            snapshot.setTotalCost(cost.getTotalCost());
        } else {
            snapshot.setQuantity(BigDecimal.ZERO);
            snapshot.setUnitCost(BigDecimal.ZERO);
            snapshot.setTotalCost(BigDecimal.ZERO);
        }
        return snapshot;
    }

    /**
     * 保存成本流水
     */
    private void saveCostLog(CostChangeRequest request, CostSnapshot before,
                            CostSnapshot after, int direction) {
        InventoryCostLog log = new InventoryCostLog();
        log.setSkuCode(request.getSkuCode());
        log.setWarehouseCode(request.getWarehouseCode());
        log.setBizType(request.getBizType());
        log.setBizNo(request.getBizNo());
        log.setDirection(direction);
        log.setQuantity(request.getQuantity());
        log.setUnitCost(request.getUnitCost());
        log.setAmount(request.getQuantity().multiply(request.getUnitCost()));
        log.setBeforeQuantity(before.getQuantity());
        log.setBeforeUnitCost(before.getUnitCost());
        log.setBeforeTotalCost(before.getTotalCost());
        log.setAfterQuantity(after.getQuantity());
        log.setAfterUnitCost(after.getUnitCost());
        log.setAfterTotalCost(after.getTotalCost());
        logMapper.insert(log);
    }
}
```

### 2.4 并发控制

库存成本计算必须保证并发安全，否则会导致成本计算错误。

**方案一：数据库行锁（推荐）**

```java
// Mapper中使用FOR UPDATE
@Select("SELECT * FROM inventory_cost WHERE sku_code = #{skuCode} " +
        "AND warehouse_code = #{warehouseCode} FOR UPDATE")
InventoryCost selectForUpdate(@Param("skuCode") String skuCode,
                              @Param("warehouseCode") String warehouseCode);
```

**方案二：乐观锁**

```java
// 更新时检查版本号
@Update("UPDATE inventory_cost SET quantity = #{quantity}, unit_cost = #{unitCost}, " +
        "total_cost = #{totalCost}, version = version + 1 " +
        "WHERE id = #{id} AND version = #{version}")
int updateWithVersion(InventoryCost cost);
```

**方案三：分布式锁（高并发场景）**

```java
@Autowired
private RedissonClient redissonClient;

public void processWithLock(CostChangeRequest request) {
    String lockKey = "cost:lock:" + request.getSkuCode() + ":" + request.getWarehouseCode();
    RLock lock = redissonClient.getLock(lockKey);

    try {
        if (lock.tryLock(5, 30, TimeUnit.SECONDS)) {
            // 执行成本计算
            processInbound(request);
        } else {
            throw new BusinessException("获取锁超时，请重试");
        }
    } finally {
        if (lock.isHeldByCurrentThread()) {
            lock.unlock();
        }
    }
}
```

**选择建议**：
- 日均订单量 < 1万：数据库行锁足够
- 日均订单量 1-10万：乐观锁 + 重试
- 日均订单量 > 10万：分布式锁 + 异步处理

---

## 三、特殊场景处理

### 3.1 退货成本处理

退货是跨境电商的常见场景，退货成本处理有两种策略：

**策略一：按原出库成本退回（推荐）**

```java
/**
 * 退货入库成本处理
 * 按原出库成本退回，保持成本一致性
 */
@Transactional(rollbackFor = Exception.class)
public void processReturn(ReturnRequest request) {
    // 1. 查询原出库记录
    InventoryCostLog outLog = logMapper.selectByBizNo(request.getOriginalOrderNo());
    if (outLog == null) {
        throw new BusinessException("未找到原出库记录");
    }

    // 2. 按原出库成本入库
    CostChangeRequest costRequest = new CostChangeRequest();
    costRequest.setSkuCode(request.getSkuCode());
    costRequest.setWarehouseCode(request.getWarehouseCode());
    costRequest.setQuantity(request.getReturnQuantity());
    costRequest.setUnitCost(outLog.getUnitCost()); // 使用原出库成本
    costRequest.setBizType("RETURN_IN");
    costRequest.setBizNo(request.getReturnNo());

    processInbound(costRequest);
}
```

**策略二：按当前成本退回**

适用于退货商品需要重新质检、翻新的场景，退货成本可能与原成本不同。

```java
/**
 * 退货入库（按评估成本）
 */
public void processReturnWithEvaluation(ReturnRequest request) {
    // 退货商品质检后评估成本
    BigDecimal evaluatedCost = evaluateReturnCost(request);

    CostChangeRequest costRequest = new CostChangeRequest();
    costRequest.setSkuCode(request.getSkuCode());
    costRequest.setWarehouseCode(request.getWarehouseCode());
    costRequest.setQuantity(request.getReturnQuantity());
    costRequest.setUnitCost(evaluatedCost); // 使用评估成本
    costRequest.setBizType("RETURN_IN");
    costRequest.setBizNo(request.getReturnNo());

    processInbound(costRequest);
}
```

### 3.2 调拨成本处理

仓库间调拨涉及两个仓库的成本变动：

```java
/**
 * 调拨成本处理
 * 调出仓按当前成本出库，调入仓按调出成本入库
 */
@Transactional(rollbackFor = Exception.class)
public void processTransfer(TransferRequest request) {
    String skuCode = request.getSkuCode();
    String fromWarehouse = request.getFromWarehouse();
    String toWarehouse = request.getToWarehouse();
    BigDecimal quantity = request.getQuantity();

    // 1. 调出仓出库
    CostChangeRequest outRequest = new CostChangeRequest();
    outRequest.setSkuCode(skuCode);
    outRequest.setWarehouseCode(fromWarehouse);
    outRequest.setQuantity(quantity);
    outRequest.setBizType("TRANSFER_OUT");
    outRequest.setBizNo(request.getTransferNo());

    BigDecimal transferAmount = processOutbound(outRequest);

    // 2. 计算调拨单位成本
    BigDecimal transferUnitCost = transferAmount.divide(quantity, 6, RoundingMode.HALF_UP);

    // 3. 调入仓入库（按调出成本）
    CostChangeRequest inRequest = new CostChangeRequest();
    inRequest.setSkuCode(skuCode);
    inRequest.setWarehouseCode(toWarehouse);
    inRequest.setQuantity(quantity);
    inRequest.setUnitCost(transferUnitCost);
    inRequest.setBizType("TRANSFER_IN");
    inRequest.setBizNo(request.getTransferNo());

    processInbound(inRequest);

    log.info("调拨成本处理完成: sku={}, 从{}调拨到{}, 数量={}, 调拨成本={}",
            skuCode, fromWarehouse, toWarehouse, quantity, transferUnitCost);
}
```

### 3.3 盘盈盘亏处理

盘点差异需要调整库存成本：

```java
/**
 * 盘盈处理
 * 盘盈按最近入库成本或指定成本入库
 */
@Transactional(rollbackFor = Exception.class)
public void processInventoryGain(InventoryAdjustRequest request) {
    // 获取入库成本（优先使用指定成本，否则使用最近入库成本）
    BigDecimal unitCost = request.getUnitCost();
    if (unitCost == null) {
        InventoryCost cost = costMapper.selectBySkuAndWarehouse(
                request.getSkuCode(), request.getWarehouseCode());
        unitCost = cost != null && cost.getLastInCost() != null ?
                cost.getLastInCost() : BigDecimal.ZERO;
    }

    CostChangeRequest costRequest = new CostChangeRequest();
    costRequest.setSkuCode(request.getSkuCode());
    costRequest.setWarehouseCode(request.getWarehouseCode());
    costRequest.setQuantity(request.getAdjustQuantity());
    costRequest.setUnitCost(unitCost);
    costRequest.setBizType("INVENTORY_GAIN");
    costRequest.setBizNo(request.getAdjustNo());

    processInbound(costRequest);
}

/**
 * 盘亏处理
 * 盘亏按当前单位成本出库
 */
@Transactional(rollbackFor = Exception.class)
public void processInventoryLoss(InventoryAdjustRequest request) {
    CostChangeRequest costRequest = new CostChangeRequest();
    costRequest.setSkuCode(request.getSkuCode());
    costRequest.setWarehouseCode(request.getWarehouseCode());
    costRequest.setQuantity(request.getAdjustQuantity().abs());
    costRequest.setBizType("INVENTORY_LOSS");
    costRequest.setBizNo(request.getAdjustNo());

    processOutbound(costRequest);
}
```

### 3.4 成本调整处理

有时需要手动调整库存成本（如发现历史成本错误）：

```java
/**
 * 成本调整
 * 直接修改单位成本，不改变数量
 */
@Transactional(rollbackFor = Exception.class)
public void adjustCost(CostAdjustRequest request) {
    String skuCode = request.getSkuCode();
    String warehouseCode = request.getWarehouseCode();
    BigDecimal newUnitCost = request.getNewUnitCost();

    // 1. 获取当前成本
    InventoryCost cost = costMapper.selectForUpdate(skuCode, warehouseCode);
    if (cost == null) {
        throw new BusinessException("库存成本记录不存在");
    }

    // 2. 记录调整前状态
    CostSnapshot before = createSnapshot(cost);

    // 3. 计算新的总成本
    BigDecimal newTotalCost = cost.getQuantity().multiply(newUnitCost);

    // 4. 更新成本
    cost.setUnitCost(newUnitCost);
    cost.setTotalCost(newTotalCost);
    costMapper.updateWithVersion(cost);

    // 5. 记录调整流水
    CostSnapshot after = createSnapshot(cost);
    InventoryCostLog log = new InventoryCostLog();
    log.setSkuCode(skuCode);
    log.setWarehouseCode(warehouseCode);
    log.setBizType("COST_ADJUST");
    log.setBizNo(request.getAdjustNo());
    log.setDirection(0); // 调整不涉及数量变动
    log.setQuantity(BigDecimal.ZERO);
    log.setUnitCost(newUnitCost);
    log.setAmount(newTotalCost.subtract(before.getTotalCost())); // 成本差异
    log.setBeforeQuantity(before.getQuantity());
    log.setBeforeUnitCost(before.getUnitCost());
    log.setBeforeTotalCost(before.getTotalCost());
    log.setAfterQuantity(after.getQuantity());
    log.setAfterUnitCost(after.getUnitCost());
    log.setAfterTotalCost(after.getTotalCost());
    logMapper.insert(log);

    log.info("成本调整完成: sku={}, warehouse={}, 原成本={}, 新成本={}, 差异={}",
            skuCode, warehouseCode, before.getUnitCost(), newUnitCost,
            newTotalCost.subtract(before.getTotalCost()));
}
```

---

## 四、月结流程设计

### 4.1 月结的必要性

月结是财务核算的关键环节，主要目的：

1. **锁定成本**：确保当月成本不再变动
2. **生成报表**：为财务报表提供数据基础
3. **对账校验**：与财务系统核对数据
4. **审计追溯**：保留历史成本快照

### 4.2 月结数据模型

```sql
-- 月结主表
CREATE TABLE inventory_cost_period (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    period VARCHAR(7) NOT NULL COMMENT '会计期间(YYYY-MM)',
    status TINYINT NOT NULL DEFAULT 0 COMMENT '状态:0未结,1已结,2已反结',
    close_time DATETIME COMMENT '结账时间',
    close_user VARCHAR(50) COMMENT '结账人',
    created_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_period (period)
) COMMENT '月结主表';

-- 月结快照表
CREATE TABLE inventory_cost_snapshot (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    period VARCHAR(7) NOT NULL COMMENT '会计期间',
    sku_code VARCHAR(50) NOT NULL COMMENT 'SKU编码',
    warehouse_code VARCHAR(50) NOT NULL COMMENT '仓库编码',
    begin_quantity DECIMAL(18,4) NOT NULL COMMENT '期初数量',
    begin_unit_cost DECIMAL(18,6) NOT NULL COMMENT '期初单位成本',
    begin_total_cost DECIMAL(18,4) NOT NULL COMMENT '期初总成本',
    in_quantity DECIMAL(18,4) NOT NULL DEFAULT 0 COMMENT '本期入库数量',
    in_amount DECIMAL(18,4) NOT NULL DEFAULT 0 COMMENT '本期入库金额',
    out_quantity DECIMAL(18,4) NOT NULL DEFAULT 0 COMMENT '本期出库数量',
    out_amount DECIMAL(18,4) NOT NULL DEFAULT 0 COMMENT '本期出库金额',
    end_quantity DECIMAL(18,4) NOT NULL COMMENT '期末数量',
    end_unit_cost DECIMAL(18,6) NOT NULL COMMENT '期末单位成本',
    end_total_cost DECIMAL(18,4) NOT NULL COMMENT '期末总成本',
    created_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_period_sku_warehouse (period, sku_code, warehouse_code),
    INDEX idx_period (period)
) COMMENT '月结快照表';
```

### 4.3 月结流程实现

```java
/**
 * 月结服务
 */
@Service
@Slf4j
public class PeriodCloseService {

    @Autowired
    private InventoryCostMapper costMapper;

    @Autowired
    private InventoryCostLogMapper logMapper;

    @Autowired
    private InventoryCostPeriodMapper periodMapper;

    @Autowired
    private InventoryCostSnapshotMapper snapshotMapper;

    /**
     * 执行月结
     */
    @Transactional(rollbackFor = Exception.class)
    public void closePeriod(String period, String operator) {
        // 1. 检查是否可以结账
        validatePeriodClose(period);

        // 2. 生成月结快照
        generateSnapshot(period);

        // 3. 更新月结状态
        InventoryCostPeriod periodRecord = new InventoryCostPeriod();
        periodRecord.setPeriod(period);
        periodRecord.setStatus(1); // 已结
        periodRecord.setCloseTime(new Date());
        periodRecord.setCloseUser(operator);
        periodMapper.insertOrUpdate(periodRecord);

        log.info("月结完成: period={}, operator={}", period, operator);
    }

    /**
     * 验证是否可以结账
     */
    private void validatePeriodClose(String period) {
        // 检查上期是否已结账
        String lastPeriod = getLastPeriod(period);
        InventoryCostPeriod lastPeriodRecord = periodMapper.selectByPeriod(lastPeriod);
        if (lastPeriodRecord == null || lastPeriodRecord.getStatus() != 1) {
            throw new BusinessException("上期(" + lastPeriod + ")未结账，不能结账本期");
        }

        // 检查本期是否已结账
        InventoryCostPeriod currentPeriod = periodMapper.selectByPeriod(period);
        if (currentPeriod != null && currentPeriod.getStatus() == 1) {
            throw new BusinessException("本期已结账，不能重复结账");
        }

        // 检查是否有未处理的单据
        int pendingCount = logMapper.countPendingByPeriod(period);
        if (pendingCount > 0) {
            throw new BusinessException("存在" + pendingCount + "条未处理的成本单据");
        }
    }

    /**
     * 生成月结快照
     */
    private void generateSnapshot(String period) {
        String lastPeriod = getLastPeriod(period);
        LocalDate periodStart = LocalDate.parse(period + "-01");
        LocalDate periodEnd = periodStart.plusMonths(1).minusDays(1);

        // 获取所有SKU+仓库组合
        List<InventoryCost> allCosts = costMapper.selectAll();

        for (InventoryCost cost : allCosts) {
            String skuCode = cost.getSkuCode();
            String warehouseCode = cost.getWarehouseCode();

            // 获取期初数据（上期期末）
            InventoryCostSnapshot lastSnapshot = snapshotMapper.selectByPeriodAndSku(
                    lastPeriod, skuCode, warehouseCode);

            BigDecimal beginQuantity = lastSnapshot != null ?
                    lastSnapshot.getEndQuantity() : BigDecimal.ZERO;
            BigDecimal beginUnitCost = lastSnapshot != null ?
                    lastSnapshot.getEndUnitCost() : BigDecimal.ZERO;
            BigDecimal beginTotalCost = lastSnapshot != null ?
                    lastSnapshot.getEndTotalCost() : BigDecimal.ZERO;

            // 统计本期入库
            CostSummary inSummary = logMapper.sumByPeriodAndDirection(
                    skuCode, warehouseCode, periodStart, periodEnd, 1);
            BigDecimal inQuantity = inSummary != null ? inSummary.getQuantity() : BigDecimal.ZERO;
            BigDecimal inAmount = inSummary != null ? inSummary.getAmount() : BigDecimal.ZERO;

            // 统计本期出库
            CostSummary outSummary = logMapper.sumByPeriodAndDirection(
                    skuCode, warehouseCode, periodStart, periodEnd, -1);
            BigDecimal outQuantity = outSummary != null ? outSummary.getQuantity() : BigDecimal.ZERO;
            BigDecimal outAmount = outSummary != null ? outSummary.getAmount() : BigDecimal.ZERO;

            // 计算期末数据
            BigDecimal endQuantity = cost.getQuantity();
            BigDecimal endUnitCost = cost.getUnitCost();
            BigDecimal endTotalCost = cost.getTotalCost();

            // 保存快照
            InventoryCostSnapshot snapshot = new InventoryCostSnapshot();
            snapshot.setPeriod(period);
            snapshot.setSkuCode(skuCode);
            snapshot.setWarehouseCode(warehouseCode);
            snapshot.setBeginQuantity(beginQuantity);
            snapshot.setBeginUnitCost(beginUnitCost);
            snapshot.setBeginTotalCost(beginTotalCost);
            snapshot.setInQuantity(inQuantity);
            snapshot.setInAmount(inAmount);
            snapshot.setOutQuantity(outQuantity);
            snapshot.setOutAmount(outAmount);
            snapshot.setEndQuantity(endQuantity);
            snapshot.setEndUnitCost(endUnitCost);
            snapshot.setEndTotalCost(endTotalCost);
            snapshotMapper.insert(snapshot);
        }
    }

    /**
     * 获取上一期间
     */
    private String getLastPeriod(String period) {
        LocalDate date = LocalDate.parse(period + "-01");
        return date.minusMonths(1).format(DateTimeFormatter.ofPattern("yyyy-MM"));
    }
}
```

### 4.4 月结报表生成

```java
/**
 * 库存成本报表服务
 */
@Service
public class InventoryCostReportService {

    /**
     * 生成库存收发存汇总表
     */
    public List<InventoryMovementReport> generateMovementReport(String period) {
        List<InventoryCostSnapshot> snapshots = snapshotMapper.selectByPeriod(period);

        return snapshots.stream().map(s -> {
            InventoryMovementReport report = new InventoryMovementReport();
            report.setSkuCode(s.getSkuCode());
            report.setWarehouseCode(s.getWarehouseCode());

            // 期初
            report.setBeginQuantity(s.getBeginQuantity());
            report.setBeginAmount(s.getBeginTotalCost());

            // 本期收入
            report.setInQuantity(s.getInQuantity());
            report.setInAmount(s.getInAmount());

            // 本期发出
            report.setOutQuantity(s.getOutQuantity());
            report.setOutAmount(s.getOutAmount());

            // 期末
            report.setEndQuantity(s.getEndQuantity());
            report.setEndAmount(s.getEndTotalCost());

            return report;
        }).collect(Collectors.toList());
    }

    /**
     * 生成销售成本明细表
     */
    public List<SalesCostReport> generateSalesCostReport(String period) {
        LocalDate periodStart = LocalDate.parse(period + "-01");
        LocalDate periodEnd = periodStart.plusMonths(1).minusDays(1);

        // 查询本期所有销售出库记录
        List<InventoryCostLog> saleLogs = logMapper.selectByPeriodAndBizType(
                periodStart, periodEnd, "SALE_OUT");

        return saleLogs.stream().map(log -> {
            SalesCostReport report = new SalesCostReport();
            report.setOrderNo(log.getBizNo());
            report.setSkuCode(log.getSkuCode());
            report.setQuantity(log.getQuantity());
            report.setUnitCost(log.getUnitCost());
            report.setCostAmount(log.getAmount());
            report.setSaleTime(log.getCreatedTime());
            return report;
        }).collect(Collectors.toList());
    }
}
```

---

## 五、实战案例

### 5.1 完整计算示例

以一个SKU在一个月内的成本变动为例：

**初始状态**：
- SKU: SKU001
- 仓库: WH01
- 库存数量: 0
- 单位成本: 0

**业务流水**：

| 日期 | 业务类型 | 数量 | 单位成本 | 计算过程 | 结果 |
|-----|---------|-----|---------|---------|-----|
| 1月5日 | 采购入库 | 100 | 10.00 | (0+1000)/(0+100) | 数量100，成本10.00 |
| 1月10日 | 采购入库 | 50 | 12.00 | (1000+600)/(100+50) | 数量150，成本10.67 |
| 1月15日 | 销售出库 | 30 | 10.67 | 150-30=120 | 数量120，成本10.67 |
| 1月20日 | 退货入库 | 5 | 10.67 | (1280.4+53.35)/(120+5) | 数量125，成本10.67 |
| 1月25日 | 调拨出库 | 20 | 10.67 | 125-20=105 | 数量105，成本10.67 |
| 1月28日 | 采购入库 | 80 | 11.00 | (1120.35+880)/(105+80) | 数量185，成本10.81 |

**月末状态**：
- 库存数量: 185
- 单位成本: 10.81
- 库存总成本: 1999.85

### 5.2 代码验证

```java
@Test
public void testCostCalculation() {
    String skuCode = "SKU001";
    String warehouseCode = "WH01";

    // 1月5日：采购入库100件，单价10元
    processInbound(skuCode, warehouseCode, new BigDecimal("100"), new BigDecimal("10.00"));
    InventoryCost cost = getCost(skuCode, warehouseCode);
    assertEquals(new BigDecimal("100.0000"), cost.getQuantity());
    assertEquals(new BigDecimal("10.000000"), cost.getUnitCost());

    // 1月10日：采购入库50件，单价12元
    processInbound(skuCode, warehouseCode, new BigDecimal("50"), new BigDecimal("12.00"));
    cost = getCost(skuCode, warehouseCode);
    assertEquals(new BigDecimal("150.0000"), cost.getQuantity());
    assertEquals(new BigDecimal("10.666667"), cost.getUnitCost()); // (1000+600)/150

    // 1月15日：销售出库30件
    processOutbound(skuCode, warehouseCode, new BigDecimal("30"));
    cost = getCost(skuCode, warehouseCode);
    assertEquals(new BigDecimal("120.0000"), cost.getQuantity());
    assertEquals(new BigDecimal("10.666667"), cost.getUnitCost()); // 出库不改变单位成本

    // 1月20日：退货入库5件（按原出库成本）
    processInbound(skuCode, warehouseCode, new BigDecimal("5"), new BigDecimal("10.666667"));
    cost = getCost(skuCode, warehouseCode);
    assertEquals(new BigDecimal("125.0000"), cost.getQuantity());

    // 1月25日：调拨出库20件
    processOutbound(skuCode, warehouseCode, new BigDecimal("20"));
    cost = getCost(skuCode, warehouseCode);
    assertEquals(new BigDecimal("105.0000"), cost.getQuantity());

    // 1月28日：采购入库80件，单价11元
    processInbound(skuCode, warehouseCode, new BigDecimal("80"), new BigDecimal("11.00"));
    cost = getCost(skuCode, warehouseCode);
    assertEquals(new BigDecimal("185.0000"), cost.getQuantity());
    // (105*10.666667 + 80*11) / 185 ≈ 10.81
    assertTrue(cost.getUnitCost().compareTo(new BigDecimal("10.80")) > 0);
    assertTrue(cost.getUnitCost().compareTo(new BigDecimal("10.82")) < 0);
}
```

### 5.3 常见问题处理

**问题1：库存为负数**

```java
// 问题：出库时库存不足，但业务已经发生
// 解决：允许负库存，但需要告警

public BigDecimal processOutboundAllowNegative(CostChangeRequest request) {
    InventoryCost cost = costMapper.selectForUpdate(
            request.getSkuCode(), request.getWarehouseCode());

    BigDecimal currentQuantity = cost != null ? cost.getQuantity() : BigDecimal.ZERO;
    BigDecimal outQuantity = request.getQuantity();

    if (currentQuantity.compareTo(outQuantity) < 0) {
        // 记录告警
        alertService.sendAlert("库存不足告警",
                String.format("SKU=%s, 当前库存=%s, 出库数量=%s",
                        request.getSkuCode(), currentQuantity, outQuantity));
    }

    // 继续处理出库
    return processOutbound(request);
}
```

**问题2：成本为0或负数**

```java
// 问题：入库成本为0（如赠品、样品）
// 解决：使用最近入库成本或标准成本

public void processInboundWithDefaultCost(CostChangeRequest request) {
    BigDecimal unitCost = request.getUnitCost();

    if (unitCost == null || unitCost.compareTo(BigDecimal.ZERO) <= 0) {
        // 获取最近入库成本
        InventoryCost cost = costMapper.selectBySkuAndWarehouse(
                request.getSkuCode(), request.getWarehouseCode());

        if (cost != null && cost.getLastInCost() != null
                && cost.getLastInCost().compareTo(BigDecimal.ZERO) > 0) {
            unitCost = cost.getLastInCost();
        } else {
            // 获取标准成本
            unitCost = skuService.getStandardCost(request.getSkuCode());
        }

        request.setUnitCost(unitCost);
        log.warn("入库成本为0，使用默认成本: sku={}, cost={}",
                request.getSkuCode(), unitCost);
    }

    processInbound(request);
}
```

**问题3：精度丢失**

```java
// 问题：多次计算后精度累积误差
// 解决：使用高精度计算，定期校准

// 1. 使用6位小数存储单位成本
BigDecimal unitCost = totalCost.divide(quantity, 6, RoundingMode.HALF_UP);

// 2. 定期校准（月结时）
public void calibrateCost(String skuCode, String warehouseCode) {
    InventoryCost cost = costMapper.selectBySkuAndWarehouse(skuCode, warehouseCode);

    // 重新计算总成本
    BigDecimal recalculatedTotal = cost.getQuantity().multiply(cost.getUnitCost())
            .setScale(4, RoundingMode.HALF_UP);

    if (cost.getTotalCost().subtract(recalculatedTotal).abs()
            .compareTo(new BigDecimal("0.01")) > 0) {
        // 存在误差，进行校准
        cost.setTotalCost(recalculatedTotal);
        costMapper.update(cost);
        log.info("成本校准: sku={}, 原总成本={}, 校准后={}",
                skuCode, cost.getTotalCost(), recalculatedTotal);
    }
}
```

**问题4：历史数据修正**

```java
// 问题：发现历史入库成本录入错误
// 解决：成本调整 + 差异记录

public void correctHistoricalCost(CostCorrectionRequest request) {
    // 1. 计算成本差异
    BigDecimal originalCost = request.getOriginalUnitCost();
    BigDecimal correctCost = request.getCorrectUnitCost();
    BigDecimal quantity = request.getQuantity();
    BigDecimal costDiff = correctCost.subtract(originalCost).multiply(quantity);

    // 2. 调整当前库存成本
    InventoryCost cost = costMapper.selectForUpdate(
            request.getSkuCode(), request.getWarehouseCode());

    BigDecimal newTotalCost = cost.getTotalCost().add(costDiff);
    BigDecimal newUnitCost = newTotalCost.divide(cost.getQuantity(), 6, RoundingMode.HALF_UP);

    cost.setTotalCost(newTotalCost);
    cost.setUnitCost(newUnitCost);
    costMapper.update(cost);

    // 3. 记录调整流水
    saveCorrectionLog(request, costDiff);

    log.info("历史成本修正: sku={}, 原成本={}, 正确成本={}, 差异={}",
            request.getSkuCode(), originalCost, correctCost, costDiff);
}
```

---

## 六、与财务系统对接

### 6.1 对接方案

库存成本数据需要同步到财务系统（金蝶、用友等），主要有两种方案：

**方案一：凭证推送**

```java
/**
 * 生成财务凭证并推送
 */
public void pushVoucherToFinance(String period) {
    // 1. 汇总本期成本数据
    List<InventoryCostSnapshot> snapshots = snapshotMapper.selectByPeriod(period);

    // 2. 按科目汇总
    Map<String, BigDecimal> accountSummary = new HashMap<>();

    for (InventoryCostSnapshot snapshot : snapshots) {
        // 入库：借-库存商品，贷-应付账款
        if (snapshot.getInAmount().compareTo(BigDecimal.ZERO) > 0) {
            accountSummary.merge("1405-库存商品", snapshot.getInAmount(), BigDecimal::add);
            accountSummary.merge("2202-应付账款", snapshot.getInAmount().negate(), BigDecimal::add);
        }

        // 出库：借-主营业务成本，贷-库存商品
        if (snapshot.getOutAmount().compareTo(BigDecimal.ZERO) > 0) {
            accountSummary.merge("6401-主营业务成本", snapshot.getOutAmount(), BigDecimal::add);
            accountSummary.merge("1405-库存商品", snapshot.getOutAmount().negate(), BigDecimal::add);
        }
    }

    // 3. 生成凭证
    FinanceVoucher voucher = new FinanceVoucher();
    voucher.setPeriod(period);
    voucher.setVoucherType("转");
    voucher.setSummary("库存成本结转");

    for (Map.Entry<String, BigDecimal> entry : accountSummary.entrySet()) {
        VoucherEntry voucherEntry = new VoucherEntry();
        voucherEntry.setAccountCode(entry.getKey().split("-")[0]);
        voucherEntry.setAccountName(entry.getKey().split("-")[1]);

        if (entry.getValue().compareTo(BigDecimal.ZERO) > 0) {
            voucherEntry.setDebitAmount(entry.getValue());
        } else {
            voucherEntry.setCreditAmount(entry.getValue().abs());
        }

        voucher.addEntry(voucherEntry);
    }

    // 4. 推送到财务系统
    financeApiClient.pushVoucher(voucher);
}
```

**方案二：数据同步**

```java
/**
 * 同步库存成本数据到财务系统
 */
public void syncCostDataToFinance(String period) {
    List<InventoryCostSnapshot> snapshots = snapshotMapper.selectByPeriod(period);

    // 转换为财务系统格式
    List<FinanceInventoryData> financeDataList = snapshots.stream()
            .map(this::convertToFinanceFormat)
            .collect(Collectors.toList());

    // 批量同步
    financeApiClient.batchSyncInventoryData(financeDataList);
}

private FinanceInventoryData convertToFinanceFormat(InventoryCostSnapshot snapshot) {
    FinanceInventoryData data = new FinanceInventoryData();
    data.setPeriod(snapshot.getPeriod());
    data.setMaterialCode(snapshot.getSkuCode());
    data.setWarehouseCode(snapshot.getWarehouseCode());
    data.setBeginQty(snapshot.getBeginQuantity());
    data.setBeginAmt(snapshot.getBeginTotalCost());
    data.setInQty(snapshot.getInQuantity());
    data.setInAmt(snapshot.getInAmount());
    data.setOutQty(snapshot.getOutQuantity());
    data.setOutAmt(snapshot.getOutAmount());
    data.setEndQty(snapshot.getEndQuantity());
    data.setEndAmt(snapshot.getEndTotalCost());
    return data;
}
```

### 6.2 对账校验

```java
/**
 * 与财务系统对账
 */
public ReconciliationResult reconcileWithFinance(String period) {
    // 1. 获取ERP库存成本数据
    BigDecimal erpTotalCost = snapshotMapper.sumEndTotalCostByPeriod(period);

    // 2. 获取财务系统库存科目余额
    BigDecimal financeTotalCost = financeApiClient.getInventoryBalance(period);

    // 3. 计算差异
    BigDecimal diff = erpTotalCost.subtract(financeTotalCost);

    ReconciliationResult result = new ReconciliationResult();
    result.setPeriod(period);
    result.setErpAmount(erpTotalCost);
    result.setFinanceAmount(financeTotalCost);
    result.setDifference(diff);
    result.setMatched(diff.abs().compareTo(new BigDecimal("0.01")) <= 0);

    if (!result.isMatched()) {
        log.warn("库存成本对账不平: period={}, ERP={}, 财务={}, 差异={}",
                period, erpTotalCost, financeTotalCost, diff);
    }

    return result;
}
```

---

## 总结

### 核心要点

1. **方法选择**：跨境电商推荐使用移动加权平均法，平衡准确性和管理成本
2. **并发控制**：成本计算必须保证并发安全，根据业务量选择合适的锁方案
3. **特殊场景**：退货、调拨、盘点等场景需要特殊处理，保持成本一致性
4. **月结流程**：定期月结锁定成本，生成快照便于追溯和对账
5. **系统对接**：与财务系统保持数据同步，定期对账确保一致

### 实施建议

| 阶段 | 目标 | 关键任务 |
|-----|------|---------|
| 第一阶段 | 基础功能 | 实现入库、出库成本计算，建立成本流水 |
| 第二阶段 | 特殊场景 | 处理退货、调拨、盘点等场景 |
| 第三阶段 | 月结报表 | 实现月结流程，生成成本报表 |
| 第四阶段 | 系统对接 | 与财务系统对接，实现自动对账 |

### 常见陷阱

- **精度问题**：使用高精度计算（6位小数），定期校准
- **并发问题**：必须加锁，否则成本会计算错误
- **负库存**：业务上可能出现，需要告警但不能阻断
- **历史修正**：需要完整的调整流程和审计追踪

---

> **系列文章导航**
>
> - 上一篇：[财务核算模块设计——多币种、多主体的挑战](/digital-transformation/posts/12-erp-finance/)
> - 下一篇：[系统集成架构设计——打通数据孤岛](/digital-transformation/posts/25-system-integration-architecture/)
> - [返回系列目录](/digital-transformation/)
```

