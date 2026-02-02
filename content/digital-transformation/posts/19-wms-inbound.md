---
title: "WMS入库管理详解——从ASN到上架的全流程设计"
date: 2026-02-02T10:00:00+08:00
draft: false
tags: ["WMS", "入库管理", "仓储系统", "ASN", "质检", "上架策略"]
categories: ["数字化转型"]
description: "入库是WMS的第一道关口，本文详解ASN预约、到货登记、质检管理、上架策略的完整设计，包含数据模型、业务流程、代码实现。"
series: ["跨境电商数字化转型指南"]
weight: 19
---

## 引言：入库管理的重要性

**入库是仓库的第一道关口**：

- 入库数据准确，后续流程才能顺畅
- 入库效率高，仓库周转才能快
- 入库质检严，售后问题才能少

**入库管理的核心目标**：
1. **准确**：收货数量与实际一致
2. **高效**：快速完成收货上架
3. **可追溯**：每件商品来源清晰

---

## 一、入库业务全景

### 1.1 入库类型

| 类型 | 来源 | 特点 |
|-----|-----|-----|
| 采购入库 | 供应商送货 | 有采购单，需质检 |
| 退货入库 | 客户退回 | 需检验，可能有损坏 |
| 调拨入库 | 其他仓库 | 有调拨单，已质检 |
| 生产入库 | 自有工厂 | 有生产单 |

### 1.2 入库流程总览

```
ASN预约 ──> 到货登记 ──> 质检 ──> 收货确认 ──> 上架
   │           │         │          │          │
   ▼           ▼         ▼          ▼          ▼
创建预约    扫码核对   质量检验   生成入库单  分配库位
通知仓库    数量清点   合格/不合格  库存增加   PDA扫码
```

---

## 二、ASN预约管理

### 2.1 什么是ASN

**ASN（Advance Shipping Notice）= 预到货通知**

供应商发货前，提前通知仓库：
- 什么时候到
- 送什么货
- 送多少

**ASN的价值**：
- 仓库提前安排人力
- 提前准备库位
- 加快收货效率

### 2.2 ASN数据模型

```sql
-- ASN主表
CREATE TABLE t_asn (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    asn_no VARCHAR(32) NOT NULL COMMENT 'ASN单号',
    warehouse_id VARCHAR(32) NOT NULL COMMENT '仓库ID',
    source_type VARCHAR(16) NOT NULL COMMENT '来源类型：PO/RETURN/TRANSFER',
    source_no VARCHAR(32) COMMENT '来源单号',
    supplier_id VARCHAR(32) COMMENT '供应商ID',
    expected_date DATE NOT NULL COMMENT '预计到货日期',
    status VARCHAR(16) NOT NULL DEFAULT 'CREATED',
    total_expected_qty INT DEFAULT 0,
    total_received_qty INT DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_asn_no (asn_no)
) ENGINE=InnoDB COMMENT='ASN预约主表';

-- ASN明细表
CREATE TABLE t_asn_item (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    asn_no VARCHAR(32) NOT NULL,
    sku_id VARCHAR(32) NOT NULL COMMENT 'SKU编码',
    sku_name VARCHAR(128) COMMENT 'SKU名称',
    expected_qty INT NOT NULL COMMENT '预约数量',
    received_qty INT DEFAULT 0 COMMENT '已收数量',
    KEY idx_asn_no (asn_no)
) ENGINE=InnoDB COMMENT='ASN明细表';
```

### 2.3 ASN状态流转

```
CREATED ──> ARRIVED ──> RECEIVING ──> COMPLETED
   │                        │
   └── CANCELLED            └── CLOSED（强制关闭）
```

| 状态 | 说明 |
|-----|-----|
| CREATED | 已创建，等待到货 |
| ARRIVED | 已到货，等待收货 |
| RECEIVING | 收货中 |
| COMPLETED | 收货完成 |
| CANCELLED | 已取消 |

### 2.4 ASN服务实现

```java
@Service
public class ASNService {

    public ASN createASN(ASNCreateRequest request) {
        ASN asn = new ASN();
        asn.setAsnNo(generateAsnNo());
        asn.setWarehouseId(request.getWarehouseId());
        asn.setSourceType(request.getSourceType());
        asn.setSourceNo(request.getSourceNo());
        asn.setExpectedDate(request.getExpectedDate());
        asn.setStatus(ASNStatus.CREATED);

        // 保存明细
        int totalQty = 0;
        for (ASNItemRequest item : request.getItems()) {
            ASNItem asnItem = new ASNItem();
            asnItem.setAsnNo(asn.getAsnNo());
            asnItem.setSkuId(item.getSkuId());
            asnItem.setExpectedQty(item.getExpectedQty());
            asnItemRepository.save(asnItem);
            totalQty += item.getExpectedQty();
        }

        asn.setTotalExpectedQty(totalQty);
        asnRepository.save(asn);
        return asn;
    }

    public void confirmArrival(String asnNo) {
        ASN asn = asnRepository.findByAsnNo(asnNo);
        if (asn.getStatus() != ASNStatus.CREATED) {
            throw new BusinessException("ASN状态不正确");
        }
        asn.setStatus(ASNStatus.ARRIVED);
        asn.setArrivalTime(LocalDateTime.now());
        asnRepository.save(asn);
    }
}
```

---

## 三、到货登记

### 3.1 到货登记流程

```
车辆到达 ──> 核对ASN ──> 卸货清点 ──> 登记数量 ──> 生成收货任务
```

### 3.2 收货任务模型

```sql
CREATE TABLE t_receive_task (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    task_no VARCHAR(32) NOT NULL COMMENT '任务单号',
    asn_no VARCHAR(32) NOT NULL COMMENT 'ASN单号',
    warehouse_id VARCHAR(32) NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'PENDING',
    operator_id VARCHAR(32) COMMENT '操作员',
    start_time DATETIME COMMENT '开始时间',
    end_time DATETIME COMMENT '结束时间',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_task_no (task_no)
) ENGINE=InnoDB COMMENT='收货任务表';
```

### 3.3 PDA收货操作

```java
@RestController
@RequestMapping("/api/pda/receive")
public class PDAReceiveController {

    /**
     * PDA扫码收货
     */
    @PostMapping("/scan")
    public Result<ReceiveScanResult> scan(@RequestBody ReceiveScanRequest request) {
        // 1. 校验ASN
        ASN asn = asnService.getByAsnNo(request.getAsnNo());
        if (asn == null) {
            return Result.fail("ASN不存在");
        }

        // 2. 校验SKU是否在ASN中
        ASNItem asnItem = asnItemService.findByAsnAndSku(
            request.getAsnNo(), request.getSkuId());
        if (asnItem == null) {
            return Result.fail("该SKU不在预约单中");
        }

        // 3. 校验数量
        int remainQty = asnItem.getExpectedQty() - asnItem.getReceivedQty();
        if (request.getQuantity() > remainQty) {
            return Result.fail("收货数量超出预约数量");
        }

        // 4. 更新收货数量
        asnItem.setReceivedQty(asnItem.getReceivedQty() + request.getQuantity());
        asnItemService.save(asnItem);

        // 5. 返回结果
        return Result.success(new ReceiveScanResult(
            asnItem.getSkuId(),
            asnItem.getExpectedQty(),
            asnItem.getReceivedQty()
        ));
    }
}
```

---

## 四、质检管理

### 4.1 质检类型

| 类型 | 说明 | 适用场景 |
|-----|-----|---------|
| 全检 | 每件都检 | 高价值商品、新供应商 |
| 抽检 | 按比例抽查 | 常规商品、稳定供应商 |
| 免检 | 不检验 | 信任供应商、调拨入库 |

### 4.2 质检项配置

```sql
CREATE TABLE t_qc_template (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    template_code VARCHAR(32) NOT NULL,
    template_name VARCHAR(64) NOT NULL,
    category_id VARCHAR(32) COMMENT '适用品类',
    qc_type VARCHAR(16) NOT NULL COMMENT '质检类型：FULL/SAMPLE/SKIP',
    sample_rate DECIMAL(5,2) COMMENT '抽检比例',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB COMMENT='质检模板';

CREATE TABLE t_qc_item (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    template_code VARCHAR(32) NOT NULL,
    item_name VARCHAR(64) NOT NULL COMMENT '检验项',
    item_type VARCHAR(16) NOT NULL COMMENT '类型：VISUAL/MEASURE/FUNCTION',
    standard VARCHAR(256) COMMENT '标准值',
    is_required TINYINT DEFAULT 1 COMMENT '是否必检',
    sort_order INT DEFAULT 0
) ENGINE=InnoDB COMMENT='质检项';
```

### 4.3 质检结果记录

```sql
CREATE TABLE t_qc_record (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    qc_no VARCHAR(32) NOT NULL COMMENT '质检单号',
    asn_no VARCHAR(32) NOT NULL,
    sku_id VARCHAR(32) NOT NULL,
    total_qty INT NOT NULL COMMENT '送检数量',
    qualified_qty INT DEFAULT 0 COMMENT '合格数量',
    unqualified_qty INT DEFAULT 0 COMMENT '不合格数量',
    qc_result VARCHAR(16) COMMENT '结果：PASS/FAIL/PARTIAL',
    operator_id VARCHAR(32),
    qc_time DATETIME,
    remark TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB COMMENT='质检记录';
```

### 4.4 质检服务实现

```java
@Service
public class QCService {

    public QCRecord createQCTask(String asnNo, String skuId, int quantity) {
        // 1. 获取质检模板
        SKU sku = skuService.getSku(skuId);
        QCTemplate template = qcTemplateService.getByCategory(sku.getCategoryId());

        // 2. 判断是否需要质检
        if (template.getQcType() == QCType.SKIP) {
            // 免检，直接通过
            return createPassRecord(asnNo, skuId, quantity);
        }

        // 3. 计算抽检数量
        int sampleQty = quantity;
        if (template.getQcType() == QCType.SAMPLE) {
            sampleQty = (int) Math.ceil(quantity * template.getSampleRate() / 100);
        }

        // 4. 创建质检任务
        QCRecord record = new QCRecord();
        record.setQcNo(generateQcNo());
        record.setAsnNo(asnNo);
        record.setSkuId(skuId);
        record.setTotalQty(quantity);
        record.setSampleQty(sampleQty);
        record.setStatus(QCStatus.PENDING);
        return qcRecordRepository.save(record);
    }

    public void submitQCResult(String qcNo, int qualifiedQty, int unqualifiedQty) {
        QCRecord record = qcRecordRepository.findByQcNo(qcNo);

        record.setQualifiedQty(qualifiedQty);
        record.setUnqualifiedQty(unqualifiedQty);
        record.setQcTime(LocalDateTime.now());

        // 判断结果
        if (unqualifiedQty == 0) {
            record.setQcResult(QCResult.PASS);
        } else if (qualifiedQty == 0) {
            record.setQcResult(QCResult.FAIL);
        } else {
            record.setQcResult(QCResult.PARTIAL);
        }

        qcRecordRepository.save(record);

        // 触发后续流程
        if (record.getQcResult() != QCResult.FAIL) {
            inboundService.createInboundOrder(record);
        }
    }
}
```

---

## 五、收货确认与入库单

### 5.1 入库单模型

```sql
CREATE TABLE t_inbound_order (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    inbound_no VARCHAR(32) NOT NULL COMMENT '入库单号',
    warehouse_id VARCHAR(32) NOT NULL,
    asn_no VARCHAR(32) COMMENT '关联ASN',
    inbound_type VARCHAR(16) NOT NULL COMMENT '入库类型',
    status VARCHAR(16) NOT NULL DEFAULT 'CREATED',
    total_qty INT DEFAULT 0,
    putaway_qty INT DEFAULT 0 COMMENT '已上架数量',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_inbound_no (inbound_no)
) ENGINE=InnoDB COMMENT='入库单';

CREATE TABLE t_inbound_item (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    inbound_no VARCHAR(32) NOT NULL,
    sku_id VARCHAR(32) NOT NULL,
    quantity INT NOT NULL COMMENT '入库数量',
    putaway_qty INT DEFAULT 0 COMMENT '已上架数量',
    batch_no VARCHAR(32) COMMENT '批次号',
    production_date DATE COMMENT '生产日期',
    expiry_date DATE COMMENT '过期日期',
    KEY idx_inbound_no (inbound_no)
) ENGINE=InnoDB COMMENT='入库单明细';
```

### 5.2 入库单生成

```java
@Service
public class InboundService {

    @Transactional
    public InboundOrder createFromASN(String asnNo) {
        ASN asn = asnService.getByAsnNo(asnNo);
        List<ASNItem> items = asnItemService.listByAsnNo(asnNo);

        // 创建入库单
        InboundOrder order = new InboundOrder();
        order.setInboundNo(generateInboundNo());
        order.setWarehouseId(asn.getWarehouseId());
        order.setAsnNo(asnNo);
        order.setInboundType(InboundType.PURCHASE);
        order.setStatus(InboundStatus.CREATED);

        int totalQty = 0;
        for (ASNItem asnItem : items) {
            if (asnItem.getReceivedQty() > 0) {
                InboundItem item = new InboundItem();
                item.setInboundNo(order.getInboundNo());
                item.setSkuId(asnItem.getSkuId());
                item.setQuantity(asnItem.getReceivedQty());
                item.setBatchNo(generateBatchNo());
                inboundItemRepository.save(item);
                totalQty += asnItem.getReceivedQty();
            }
        }

        order.setTotalQty(totalQty);
        inboundOrderRepository.save(order);

        // 更新ASN状态
        asn.setStatus(ASNStatus.COMPLETED);
        asnService.save(asn);

        return order;
    }
}
```

---

## 六、上架管理

### 6.1 上架策略

| 策略 | 说明 | 适用场景 |
|-----|-----|---------|
| 就近上架 | 放到同SKU已有库存附近 | 减少拣货行走距离 |
| 分区上架 | 按品类/属性分配库区 | 便于管理 |
| ABC分区 | 高周转放近，低周转放远 | 提高拣货效率 |
| 随机上架 | 系统随机分配空库位 | 简单快速 |

### 6.2 上架任务模型

```sql
CREATE TABLE t_putaway_task (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    task_no VARCHAR(32) NOT NULL,
    inbound_no VARCHAR(32) NOT NULL,
    sku_id VARCHAR(32) NOT NULL,
    quantity INT NOT NULL COMMENT '待上架数量',
    from_location VARCHAR(32) COMMENT '暂存位',
    to_location VARCHAR(32) COMMENT '目标库位',
    status VARCHAR(16) NOT NULL DEFAULT 'PENDING',
    operator_id VARCHAR(32),
    completed_at DATETIME,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_task_no (task_no)
) ENGINE=InnoDB COMMENT='上架任务';
```

### 6.3 库位推荐算法

```java
@Service
public class LocationRecommendService {

    /**
     * 推荐上架库位
     */
    public String recommendLocation(String warehouseId, String skuId, int quantity) {
        // 1. 获取SKU信息
        SKU sku = skuService.getSku(skuId);

        // 2. 获取上架策略
        PutawayStrategy strategy = strategyService.getStrategy(warehouseId, sku);

        // 3. 根据策略推荐库位
        switch (strategy.getType()) {
            case NEARBY:
                return recommendNearby(warehouseId, skuId, quantity);
            case ZONE_BASED:
                return recommendByZone(warehouseId, sku, quantity);
            case ABC:
                return recommendByABC(warehouseId, sku, quantity);
            default:
                return recommendRandom(warehouseId, quantity);
        }
    }

    private String recommendNearby(String warehouseId, String skuId, int quantity) {
        // 找到该SKU已有库存的库位
        List<String> existingLocations = inventoryService.getLocations(warehouseId, skuId);

        if (existingLocations.isEmpty()) {
            // 没有现有库存，随机分配
            return recommendRandom(warehouseId, quantity);
        }

        // 找附近的空库位
        for (String location : existingLocations) {
            String nearbyEmpty = locationService.findNearestEmpty(warehouseId, location);
            if (nearbyEmpty != null) {
                return nearbyEmpty;
            }
        }

        return recommendRandom(warehouseId, quantity);
    }

    private String recommendByABC(String warehouseId, SKU sku, int quantity) {
        // 根据周转率确定ABC分区
        String zone;
        if (sku.getTurnoverRate() > 10) {
            zone = "A"; // 高周转，靠近出库口
        } else if (sku.getTurnoverRate() > 3) {
            zone = "B"; // 中周转
        } else {
            zone = "C"; // 低周转，远离出库口
        }

        return locationService.findEmptyInZone(warehouseId, zone);
    }
}
```

### 6.4 PDA上架操作

```java
@RestController
@RequestMapping("/api/pda/putaway")
public class PDAPutawayController {

    /**
     * 获取上架任务
     */
    @GetMapping("/tasks")
    public Result<List<PutawayTask>> getTasks(@RequestParam String operatorId) {
        List<PutawayTask> tasks = putawayService.getPendingTasks(operatorId);
        return Result.success(tasks);
    }

    /**
     * 扫码上架
     */
    @PostMapping("/confirm")
    public Result<Void> confirmPutaway(@RequestBody PutawayConfirmRequest request) {
        // 1. 校验任务
        PutawayTask task = putawayService.getByTaskNo(request.getTaskNo());
        if (task.getStatus() != TaskStatus.PENDING) {
            return Result.fail("任务状态不正确");
        }

        // 2. 校验库位
        if (!request.getLocationCode().equals(task.getToLocation())) {
            // 允许上架到其他库位，但需要记录
            task.setActualLocation(request.getLocationCode());
        }

        // 3. 执行上架
        putawayService.confirmPutaway(task, request.getQuantity());

        // 4. 增加库存
        inventoryService.addInventory(
            task.getWarehouseId(),
            request.getLocationCode(),
            task.getSkuId(),
            request.getQuantity(),
            "INBOUND",
            task.getInboundNo()
        );

        return Result.success();
    }
}
```

---

## 七、异常处理

### 7.1 常见异常场景

| 异常 | 处理方式 |
|-----|---------|
| 到货数量与ASN不符 | 按实际数量收货，记录差异 |
| 质检不合格 | 转入不良品库位，通知采购 |
| 无预约到货 | 创建临时ASN，正常收货 |
| 库位已满 | 推荐其他库位或暂存 |

### 7.2 差异处理

```java
@Service
public class ReceiveDifferenceService {

    public void handleDifference(String asnNo) {
        ASN asn = asnService.getByAsnNo(asnNo);
        List<ASNItem> items = asnItemService.listByAsnNo(asnNo);

        for (ASNItem item : items) {
            int diff = item.getExpectedQty() - item.getReceivedQty();
            if (diff != 0) {
                // 记录差异
                ReceiveDifference difference = new ReceiveDifference();
                difference.setAsnNo(asnNo);
                difference.setSkuId(item.getSkuId());
                difference.setExpectedQty(item.getExpectedQty());
                difference.setReceivedQty(item.getReceivedQty());
                difference.setDifferenceQty(diff);
                difference.setDifferenceType(diff > 0 ? "SHORT" : "OVER");
                differenceRepository.save(difference);

                // 通知相关人员
                notifyService.notifyDifference(difference);
            }
        }
    }
}
```

---

## 八、性能优化

### 8.1 批量操作

```java
// 批量创建上架任务
@Transactional
public void batchCreatePutawayTasks(String inboundNo) {
    List<InboundItem> items = inboundItemService.listByInboundNo(inboundNo);

    List<PutawayTask> tasks = new ArrayList<>();
    for (InboundItem item : items) {
        PutawayTask task = new PutawayTask();
        task.setTaskNo(generateTaskNo());
        task.setInboundNo(inboundNo);
        task.setSkuId(item.getSkuId());
        task.setQuantity(item.getQuantity());
        task.setToLocation(recommendLocation(item));
        tasks.add(task);
    }

    // 批量插入
    putawayTaskRepository.batchInsert(tasks);
}
```

### 8.2 缓存优化

```java
@Service
public class LocationCacheService {

    @Cacheable(value = "emptyLocations", key = "#warehouseId + ':' + #zone")
    public List<String> getEmptyLocations(String warehouseId, String zone) {
        return locationRepository.findEmptyByZone(warehouseId, zone);
    }

    @CacheEvict(value = "emptyLocations", key = "#warehouseId + ':' + #zone")
    public void evictCache(String warehouseId, String zone) {
        // 库位状态变化时清除缓存
    }
}
```

---

## 九、总结

### 9.1 入库管理核心要点

1. **ASN预约**：提前通知，提高效率
2. **到货登记**：扫码核对，数量准确
3. **质检管理**：分类质检，保证质量
4. **上架策略**：智能推荐，优化布局

### 9.2 关键指标

| 指标 | 目标值 |
|-----|-------|
| 收货准确率 | > 99.9% |
| 上架及时率 | > 95% |
| 质检合格率 | > 98% |
| 入库效率 | < 4小时 |

---

> **系列文章导航**
>
> 本文是《跨境电商数字化转型指南》系列的第19篇
>
> - [x] 18. WMS仓储系统架构设计
> - [x] 19. WMS入库管理详解（本文）
> - [ ] 20. WMS拣货策略优化
> - [ ] 21. WMS库存盘点实战
