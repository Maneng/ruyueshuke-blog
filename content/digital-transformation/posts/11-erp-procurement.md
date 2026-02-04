---
title: "采购管理系统设计——从需求到入库的全流程"
date: 2026-02-04T15:00:00+08:00
draft: false
tags: ["ERP", "采购管理", "供应商管理", "跨境电商", "系统设计"]
categories: ["数字化转型"]
description: "跨境电商采购管理系统的完整设计方案，涵盖需求计划、询价比价、采购下单、到货验收、入库结算五大环节，包含供应商管理、多币种采购、审批流程等核心功能的数据库设计和代码实现。"
series: ["跨境电商数字化转型指南"]
weight: 11
---

## 引言：为什么采购管理是跨境电商的命脉

在跨境电商的成本结构中，**商品采购成本通常占到销售额的40%-60%**。采购管理的好坏，直接决定了企业的毛利率和现金流健康度。

然而，很多跨境电商企业的采购管理还停留在"Excel+微信"的原始阶段：

| 痛点 | 表现 | 后果 |
|-----|-----|-----|
| 信息孤岛 | 采购数据散落在各处 | 无法追溯、难以分析 |
| 流程混乱 | 没有标准化审批流程 | 越权采购、价格失控 |
| 库存失控 | 凭感觉补货 | 要么断货、要么积压 |
| 供应商管理缺失 | 没有评级和淘汰机制 | 质量不稳定、交期延误 |
| 成本核算困难 | 多币种、多批次混乱 | 毛利算不清 |

**本文目标**：设计一套适合5-7亿规模跨境电商的采购管理系统，从需求计划到入库结算，实现全流程数字化管理。

---

## 一、跨境电商采购的特殊性

### 1.1 与传统采购的核心差异

| 维度 | 传统企业采购 | 跨境电商采购 |
|-----|------------|------------|
| 供应商分布 | 国内为主 | 国内+海外（1688、阿里国际站、海外工厂） |
| 结算币种 | 单一（CNY） | 多币种（CNY、USD、EUR等） |
| 付款方式 | 银行转账、承兑 | T/T、信用证、PayPal、西联 |
| 采购周期 | 相对固定 | 差异大（国内7天 vs 海运45天） |
| 质检要求 | 标准化 | 需适应目的国标准（CE、FCC、FDA等） |
| 单据要求 | 国内发票 | 形式发票、装箱单、原产地证等 |

### 1.2 多币种采购的挑战

跨境电商经常面临这样的场景：

```
场景：从美国供应商采购一批电子配件
- 报价币种：USD
- 付款币种：USD（通过香港公司付款）
- 入库成本：需转换为CNY（国内公司记账）
- 销售币种：EUR（欧洲站销售）
```

**汇率波动的影响**：

```java
// 假设采购时汇率 1 USD = 7.2 CNY
// 采购成本：$100 × 7.2 = ¥720

// 一个月后付款时汇率 1 USD = 7.0 CNY
// 实际付款：$100 × 7.0 = ¥700
// 汇兑收益：¥20

// 但如果汇率变成 1 USD = 7.4 CNY
// 实际付款：$100 × 7.4 = ¥740
// 汇兑损失：¥20
```

### 1.3 海外供应商管理难点

**时差问题**：
- 美国供应商：时差12-15小时，沟通窗口有限
- 欧洲供应商：时差6-8小时，下午才能联系

**语言和文化差异**：
- 合同条款理解偏差
- 质量标准认知不同
- 交期承诺的"弹性"

**付款风险**：
- 预付款比例高（30%-50%）
- 跨境追款困难
- 汇率锁定需求

### 1.4 国际物流协调

```
采购流程中的物流节点：

国内采购：工厂 → 国内仓（3-7天）
海外采购：海外工厂 → 港口 → 海运 → 清关 → 国内仓（30-60天）
         └── 空运可缩短至7-15天，但成本高3-5倍
```

**关键决策点**：
- 海运 vs 空运的成本效益分析
- 整柜 vs 拼柜的选择
- 清关时效的预估

---

## 二、采购全流程设计

### 2.1 流程总览

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         采购管理全流程                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐│
│  │ 需求计划 │───▶│ 询价比价 │───▶│ 采购下单 │───▶│ 到货验收 │───▶│ 入库结算 ││
│  └─────────┘    └─────────┘    └─────────┘    └─────────┘    └─────────┘│
│       │              │              │              │              │     │
│       ▼              ▼              ▼              ▼              ▼     │
│   库存预警        供应商报价      PO审批        WMS收货       财务应付   │
│   销售预测        价格对比        合同签订      质检验收       成本核算   │
│   采购建议        供应商选择      付款申请      差异处理       凭证生成   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.2 环节一：需求计划

**触发采购需求的三种方式**：

| 方式 | 触发条件 | 适用场景 |
|-----|---------|---------|
| 安全库存预警 | 可用库存 < 安全库存 | 常规补货 |
| 销售预测驱动 | 预测销量 × 备货周期 | 大促备货 |
| 手动创建 | 业务人员判断 | 新品采购、临时需求 |

**采购建议算法**：

```java
/**
 * 采购建议生成服务
 *
 * 核心公式：
 * 建议采购量 = MAX(0, 目标库存 - 可用库存 - 在途库存 - 已下单未发货)
 *
 * 其中：
 * 目标库存 = 安全库存 + 日均销量 × (采购周期 + 安全天数)
 */
@Service
public class PurchaseSuggestionService {

    @Autowired
    private InventoryRepository inventoryRepository;

    @Autowired
    private SalesStatisticsService salesStatisticsService;

    @Autowired
    private PurchaseOrderRepository purchaseOrderRepository;

    /**
     * 生成单个SKU的采购建议
     */
    public PurchaseSuggestion generateSuggestion(String skuId, String warehouseId) {
        // 1. 获取SKU配置
        SkuPurchaseConfig config = getSkuConfig(skuId);

        // 2. 计算日均销量（取近30天数据）
        BigDecimal avgDailySales = salesStatisticsService
            .getAvgDailySales(skuId, 30);

        // 3. 计算目标库存
        int safetyStock = config.getSafetyStock();
        int leadTimeDays = config.getLeadTimeDays();  // 采购周期
        int safetyDays = config.getSafetyDays();      // 安全天数

        int targetStock = safetyStock +
            avgDailySales.multiply(BigDecimal.valueOf(leadTimeDays + safetyDays))
                .intValue();

        // 4. 获取当前库存状况
        int availableStock = inventoryRepository
            .getAvailableStock(skuId, warehouseId);
        int inTransitStock = purchaseOrderRepository
            .getInTransitQty(skuId, warehouseId);
        int pendingStock = purchaseOrderRepository
            .getPendingShipmentQty(skuId, warehouseId);

        // 5. 计算建议采购量
        int suggestQty = targetStock - availableStock - inTransitStock - pendingStock;
        suggestQty = Math.max(0, suggestQty);

        // 6. 考虑最小起订量（MOQ）
        int moq = config.getMinOrderQty();
        if (suggestQty > 0 && suggestQty < moq) {
            suggestQty = moq;
        }

        // 7. 考虑采购倍数
        int orderMultiple = config.getOrderMultiple();
        if (orderMultiple > 1) {
            suggestQty = (int) Math.ceil((double) suggestQty / orderMultiple)
                * orderMultiple;
        }

        return PurchaseSuggestion.builder()
            .skuId(skuId)
            .warehouseId(warehouseId)
            .currentStock(availableStock)
            .inTransitStock(inTransitStock)
            .targetStock(targetStock)
            .avgDailySales(avgDailySales)
            .suggestQty(suggestQty)
            .preferredSupplierId(config.getPreferredSupplierId())
            .urgencyLevel(calculateUrgency(availableStock, safetyStock, avgDailySales))
            .build();
    }

    /**
     * 计算紧急程度
     * - URGENT: 库存 < 安全库存的50%
     * - HIGH: 库存 < 安全库存
     * - NORMAL: 库存 < 目标库存
     */
    private String calculateUrgency(int available, int safety, BigDecimal avgSales) {
        if (available < safety * 0.5) {
            return "URGENT";
        } else if (available < safety) {
            return "HIGH";
        } else {
            return "NORMAL";
        }
    }
}
```

### 2.3 环节二：询价比价

**询价流程**：

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  创建询价单  │────▶│  发送供应商  │────▶│  收集报价   │────▶│  比价分析   │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
       │                   │                   │                   │
       ▼                   ▼                   ▼                   ▼
   选择SKU列表         邮件/系统通知       供应商回复报价      生成比价报告
   指定目标供应商       设置截止时间       记录报价明细        推荐最优方案
```

**比价维度**：

| 维度 | 权重建议 | 说明 |
|-----|---------|-----|
| 单价 | 40% | 含税价、到岸价 |
| 交期 | 25% | 能否满足需求时间 |
| 质量 | 20% | 历史质量表现 |
| 付款条件 | 10% | 账期、预付比例 |
| 服务 | 5% | 响应速度、售后支持 |

**比价算法实现**：

```java
@Service
public class QuotationCompareService {

    /**
     * 综合评分比价
     *
     * 综合得分 = 价格得分×40% + 交期得分×25% + 质量得分×20%
     *          + 付款得分×10% + 服务得分×5%
     */
    public List<QuotationRanking> compareQuotations(String inquiryId) {
        List<SupplierQuotation> quotations = quotationRepository
            .findByInquiryId(inquiryId);

        if (quotations.isEmpty()) {
            return Collections.emptyList();
        }

        // 找出最低价格（用于计算价格得分）
        BigDecimal minPrice = quotations.stream()
            .map(SupplierQuotation::getUnitPrice)
            .min(BigDecimal::compareTo)
            .orElse(BigDecimal.ONE);

        // 找出最短交期
        int minLeadTime = quotations.stream()
            .mapToInt(SupplierQuotation::getLeadTimeDays)
            .min()
            .orElse(1);

        List<QuotationRanking> rankings = new ArrayList<>();

        for (SupplierQuotation q : quotations) {
            QuotationRanking ranking = new QuotationRanking();
            ranking.setQuotationId(q.getId());
            ranking.setSupplierId(q.getSupplierId());
            ranking.setSupplierName(q.getSupplierName());

            // 价格得分：最低价/报价 × 100
            BigDecimal priceScore = minPrice
                .divide(q.getUnitPrice(), 4, RoundingMode.HALF_UP)
                .multiply(BigDecimal.valueOf(100));
            ranking.setPriceScore(priceScore);

            // 交期得分：最短交期/报价交期 × 100
            BigDecimal leadTimeScore = BigDecimal.valueOf(minLeadTime)
                .divide(BigDecimal.valueOf(q.getLeadTimeDays()), 4, RoundingMode.HALF_UP)
                .multiply(BigDecimal.valueOf(100));
            ranking.setLeadTimeScore(leadTimeScore);

            // 质量得分：取供应商历史质量评分
            BigDecimal qualityScore = getSupplierQualityScore(q.getSupplierId());
            ranking.setQualityScore(qualityScore);

            // 付款得分：账期越长越好
            BigDecimal paymentScore = calculatePaymentScore(q.getPaymentTerms());
            ranking.setPaymentScore(paymentScore);

            // 服务得分：取供应商服务评分
            BigDecimal serviceScore = getSupplierServiceScore(q.getSupplierId());
            ranking.setServiceScore(serviceScore);

            // 计算综合得分
            BigDecimal totalScore = priceScore.multiply(BigDecimal.valueOf(0.40))
                .add(leadTimeScore.multiply(BigDecimal.valueOf(0.25)))
                .add(qualityScore.multiply(BigDecimal.valueOf(0.20)))
                .add(paymentScore.multiply(BigDecimal.valueOf(0.10)))
                .add(serviceScore.multiply(BigDecimal.valueOf(0.05)));
            ranking.setTotalScore(totalScore);

            rankings.add(ranking);
        }

        // 按综合得分降序排列
        rankings.sort((a, b) -> b.getTotalScore().compareTo(a.getTotalScore()));

        // 设置排名
        for (int i = 0; i < rankings.size(); i++) {
            rankings.get(i).setRank(i + 1);
        }

        return rankings;
    }

    /**
     * 付款条件评分
     * - 月结60天：100分
     * - 月结30天：80分
     * - 货到付款：60分
     * - 预付30%：40分
     * - 预付50%：20分
     * - 全额预付：0分
     */
    private BigDecimal calculatePaymentScore(String paymentTerms) {
        Map<String, Integer> scoreMap = Map.of(
            "NET60", 100,
            "NET30", 80,
            "COD", 60,
            "30%_ADVANCE", 40,
            "50%_ADVANCE", 20,
            "100%_ADVANCE", 0
        );
        return BigDecimal.valueOf(scoreMap.getOrDefault(paymentTerms, 50));
    }
}
```

### 2.4 环节三：采购下单

**采购订单状态流转**：

```
┌─────────┐     ┌─────────┐     ┌─────────┐     ┌─────────┐     ┌─────────┐
│  草稿   │────▶│ 待审批  │────▶│ 已审批  │────▶│ 已发货  │────▶│ 已完成  │
│ DRAFT  │     │ PENDING │     │ APPROVED│     │ SHIPPED │     │ COMPLETED│
└─────────┘     └─────────┘     └─────────┘     └─────────┘     └─────────┘
     │               │               │               │
     │               ▼               │               │
     │          ┌─────────┐          │               │
     │          │  已驳回  │          │               │
     │          │ REJECTED│          │               │
     │          └─────────┘          │               │
     │                               │               │
     └───────────────────────────────┴───────────────┘
                                 可取消
                              ┌─────────┐
                              │ 已取消  │
                              │ CANCELLED│
                              └─────────┘
```

**采购订单创建服务**：

```java
@Service
@Transactional
public class PurchaseOrderService {

    @Autowired
    private PurchaseOrderRepository poRepository;

    @Autowired
    private SupplierService supplierService;

    @Autowired
    private ApprovalService approvalService;

    @Autowired
    private ExchangeRateService exchangeRateService;

    /**
     * 创建采购订单
     */
    public PurchaseOrder createPurchaseOrder(PurchaseOrderCreateRequest request) {
        // 1. 生成PO编号
        String poNo = generatePoNo();

        // 2. 获取供应商信息
        Supplier supplier = supplierService.getById(request.getSupplierId());
        if (supplier == null || !"ACTIVE".equals(supplier.getStatus())) {
            throw new BusinessException("供应商不存在或已停用");
        }

        // 3. 创建采购订单主表
        PurchaseOrder po = new PurchaseOrder();
        po.setPoNo(poNo);
        po.setSupplierId(supplier.getId());
        po.setSupplierCode(supplier.getSupplierCode());
        po.setSupplierName(supplier.getSupplierName());
        po.setWarehouseId(request.getWarehouseId());
        po.setOrderDate(LocalDate.now());
        po.setExpectedDate(request.getExpectedDate());
        po.setCurrency(request.getCurrency());
        po.setPaymentTerms(request.getPaymentTerms());
        po.setStatus("DRAFT");
        po.setCreatedBy(SecurityUtils.getCurrentUser());

        // 4. 获取汇率（如果是外币采购）
        if (!"CNY".equals(request.getCurrency())) {
            BigDecimal exchangeRate = exchangeRateService
                .getRate(request.getCurrency(), "CNY", LocalDate.now());
            po.setExchangeRate(exchangeRate);
        } else {
            po.setExchangeRate(BigDecimal.ONE);
        }

        // 5. 创建采购订单明细
        List<PurchaseOrderItem> items = new ArrayList<>();
        BigDecimal totalAmount = BigDecimal.ZERO;

        for (PurchaseOrderItemRequest itemReq : request.getItems()) {
            PurchaseOrderItem item = new PurchaseOrderItem();
            item.setPoNo(poNo);
            item.setSeq(items.size() + 1);
            item.setSkuId(itemReq.getSkuId());
            item.setSkuName(itemReq.getSkuName());
            item.setQuantity(itemReq.getQuantity());
            item.setUnitPrice(itemReq.getUnitPrice());

            // 计算金额
            BigDecimal amount = itemReq.getUnitPrice()
                .multiply(BigDecimal.valueOf(itemReq.getQuantity()));
            item.setAmount(amount);
            item.setReceivedQty(0);

            items.add(item);
            totalAmount = totalAmount.add(amount);
        }

        po.setTotalAmount(totalAmount);
        po.setTotalAmountCny(totalAmount.multiply(po.getExchangeRate()));

        // 6. 保存
        poRepository.save(po);
        poRepository.saveItems(items);

        return po;
    }

    /**
     * 提交审批
     */
    public void submitForApproval(String poNo) {
        PurchaseOrder po = poRepository.findByPoNo(poNo);
        if (po == null) {
            throw new BusinessException("采购订单不存在");
        }
        if (!"DRAFT".equals(po.getStatus()) && !"REJECTED".equals(po.getStatus())) {
            throw new BusinessException("当前状态不允许提交审批");
        }

        // 更新状态
        po.setStatus("PENDING");
        poRepository.update(po);

        // 发起审批流程
        approvalService.startApproval(
            "PURCHASE_ORDER",
            poNo,
            po.getTotalAmountCny(),
            po.getCreatedBy()
        );
    }

    /**
     * 生成PO编号
     * 格式：PO + 年月日 + 4位流水号
     * 示例：PO202602040001
     */
    private String generatePoNo() {
        String dateStr = LocalDate.now().format(DateTimeFormatter.ofPattern("yyyyMMdd"));
        String prefix = "PO" + dateStr;

        // 获取当日最大流水号
        Integer maxSeq = poRepository.getMaxSeqByPrefix(prefix);
        int nextSeq = (maxSeq == null) ? 1 : maxSeq + 1;

        return prefix + String.format("%04d", nextSeq);
    }
}
```

### 2.5 环节四：到货验收

**到货验收流程**：

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  ASN预约    │────▶│  到货登记   │────▶│  质检验收   │────▶│  差异处理   │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
       │                   │                   │                   │
       ▼                   ▼                   ▼                   ▼
   供应商提交ASN       WMS扫码收货        抽检/全检          多收/少收/破损
   预约到货时间        核对数量品名        记录质检结果        生成差异单
```

**ASN（预到货通知）管理**：

```java
@Service
public class AsnService {

    /**
     * 创建ASN（预到货通知）
     */
    public Asn createAsn(AsnCreateRequest request) {
        // 验证采购订单
        PurchaseOrder po = poRepository.findByPoNo(request.getPoNo());
        if (po == null || !"APPROVED".equals(po.getStatus())) {
            throw new BusinessException("采购订单不存在或未审批");
        }

        // 生成ASN编号
        String asnNo = generateAsnNo();

        Asn asn = new Asn();
        asn.setAsnNo(asnNo);
        asn.setPoNo(request.getPoNo());
        asn.setSupplierId(po.getSupplierId());
        asn.setWarehouseId(po.getWarehouseId());
        asn.setExpectedArrivalDate(request.getExpectedArrivalDate());
        asn.setCarrier(request.getCarrier());
        asn.setTrackingNo(request.getTrackingNo());
        asn.setStatus("PENDING");

        // 创建ASN明细
        List<AsnItem> items = new ArrayList<>();
        for (AsnItemRequest itemReq : request.getItems()) {
            // 验证是否超过PO可收货数量
            PurchaseOrderItem poItem = poRepository
                .findItemByPoNoAndSku(request.getPoNo(), itemReq.getSkuId());

            int remainingQty = poItem.getQuantity() - poItem.getReceivedQty();
            if (itemReq.getQuantity() > remainingQty) {
                throw new BusinessException(
                    String.format("SKU[%s]预到货数量[%d]超过可收货数量[%d]",
                        itemReq.getSkuId(), itemReq.getQuantity(), remainingQty)
                );
            }

            AsnItem item = new AsnItem();
            item.setAsnNo(asnNo);
            item.setSkuId(itemReq.getSkuId());
            item.setExpectedQty(itemReq.getQuantity());
            item.setReceivedQty(0);
            items.add(item);
        }

        asnRepository.save(asn);
        asnRepository.saveItems(items);

        // 通知WMS准备收货
        wmsNotifyService.notifyAsnCreated(asn, items);

        return asn;
    }
}
```

**质检验收服务**：

```java
@Service
public class QualityInspectionService {

    /**
     * 执行质检
     */
    public QualityInspectionResult inspect(QualityInspectionRequest request) {
        QualityInspectionResult result = new QualityInspectionResult();
        result.setAsnNo(request.getAsnNo());
        result.setSkuId(request.getSkuId());
        result.setInspectionDate(LocalDateTime.now());
        result.setInspector(SecurityUtils.getCurrentUser());

        // 获取质检标准
        QualityStandard standard = qualityStandardRepository
            .findBySkuId(request.getSkuId());

        // 记录质检项目
        List<InspectionItem> inspectionItems = new ArrayList<>();
        int passCount = 0;
        int failCount = 0;

        for (InspectionItemRequest itemReq : request.getItems()) {
            InspectionItem item = new InspectionItem();
            item.setItemName(itemReq.getItemName());
            item.setStandardValue(itemReq.getStandardValue());
            item.setActualValue(itemReq.getActualValue());

            // 判断是否合格
            boolean passed = evaluateInspectionItem(itemReq, standard);
            item.setPassed(passed);

            if (passed) {
                passCount++;
            } else {
                failCount++;
            }

            inspectionItems.add(item);
        }

        result.setInspectionItems(inspectionItems);
        result.setTotalItems(inspectionItems.size());
        result.setPassedItems(passCount);
        result.setFailedItems(failCount);

        // 计算合格率
        BigDecimal passRate = BigDecimal.valueOf(passCount)
            .divide(BigDecimal.valueOf(inspectionItems.size()), 4, RoundingMode.HALF_UP);
        result.setPassRate(passRate);

        // 判断整体是否合格（合格率 >= 95%）
        result.setOverallPassed(passRate.compareTo(BigDecimal.valueOf(0.95)) >= 0);

        // 保存质检结果
        qualityInspectionRepository.save(result);

        return result;
    }
}
```

### 2.6 环节五：入库结算

**入库结算流程**：

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  WMS入库    │────▶│  ERP同步    │────▶│  成本核算   │────▶│  应付登记   │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
       │                   │                   │                   │
       ▼                   ▼                   ▼                   ▼
   实物上架完成        更新账面库存        计算入库成本        生成应付凭证
   WMS发送入库回执     更新PO收货数量      移动加权平均        等待发票核对
```

**入库结算服务**：

```java
@Service
@Transactional
public class PurchaseSettlementService {

    /**
     * 处理WMS入库回执
     */
    @RocketMQMessageListener(topic = "wms-inbound-complete")
    public void onInboundComplete(InboundCompleteEvent event) {
        String asnNo = event.getAsnNo();
        String skuId = event.getSkuId();
        int receivedQty = event.getReceivedQty();

        // 1. 更新ASN状态
        Asn asn = asnRepository.findByAsnNo(asnNo);
        AsnItem asnItem = asnRepository.findItemByAsnNoAndSku(asnNo, skuId);
        asnItem.setReceivedQty(receivedQty);
        asnRepository.updateItem(asnItem);

        // 2. 更新PO收货数量
        PurchaseOrder po = poRepository.findByPoNo(asn.getPoNo());
        PurchaseOrderItem poItem = poRepository
            .findItemByPoNoAndSku(asn.getPoNo(), skuId);
        poItem.setReceivedQty(poItem.getReceivedQty() + receivedQty);
        poRepository.updateItem(poItem);

        // 检查PO是否全部收货完成
        checkAndUpdatePoStatus(po);

        // 3. 计算入库成本（移动加权平均）
        BigDecimal inboundAmount = poItem.getUnitPrice()
            .multiply(BigDecimal.valueOf(receivedQty))
            .multiply(po.getExchangeRate());  // 转换为本位币

        costCalculationService.calculateMovingAverageCost(
            skuId,
            receivedQty,
            inboundAmount
        );

        // 4. 更新ERP库存
        erpInventoryService.increaseStock(
            skuId,
            po.getWarehouseId(),
            receivedQty
        );

        // 5. 生成应付凭证
        createPayableVoucher(po, poItem, receivedQty, inboundAmount);
    }

    /**
     * 生成应付凭证
     *
     * 借：库存商品
     * 贷：应付账款
     */
    private void createPayableVoucher(PurchaseOrder po, PurchaseOrderItem item,
                                       int qty, BigDecimal amount) {
        Voucher voucher = new Voucher();
        voucher.setVoucherNo(generateVoucherNo());
        voucher.setVoucherDate(LocalDate.now());
        voucher.setPeriod(LocalDate.now().format(DateTimeFormatter.ofPattern("yyyyMM")));
        voucher.setVoucherType("转");
        voucher.setDescription(String.format("采购入库 PO:%s SKU:%s 数量:%d",
            po.getPoNo(), item.getSkuId(), qty));

        List<VoucherItem> voucherItems = new ArrayList<>();

        // 借方：库存商品
        VoucherItem debitItem = new VoucherItem();
        debitItem.setVoucherNo(voucher.getVoucherNo());
        debitItem.setSeq(1);
        debitItem.setAccountCode("1405");  // 库存商品科目
        debitItem.setDescription("采购入库-" + item.getSkuName());
        debitItem.setDebitAmount(amount);
        debitItem.setCreditAmount(BigDecimal.ZERO);
        voucherItems.add(debitItem);

        // 贷方：应付账款
        VoucherItem creditItem = new VoucherItem();
        creditItem.setVoucherNo(voucher.getVoucherNo());
        creditItem.setSeq(2);
        creditItem.setAccountCode("2202");  // 应付账款科目
        creditItem.setDescription("应付-" + po.getSupplierName());
        creditItem.setDebitAmount(BigDecimal.ZERO);
        creditItem.setCreditAmount(amount);
        voucherItems.add(creditItem);

        voucher.setTotalDebit(amount);
        voucher.setTotalCredit(amount);
        voucher.setStatus("DRAFT");

        voucherRepository.save(voucher);
        voucherRepository.saveItems(voucherItems);

        // 更新应付账款
        payableService.createPayable(
            po.getSupplierId(),
            po.getPoNo(),
            amount,
            po.getPaymentTerms()
        );
    }
}
```

---

## 三、核心功能详解

### 3.1 供应商管理

#### 3.1.1 供应商档案

**供应商信息维度**：

| 类别 | 字段 | 说明 |
|-----|-----|-----|
| 基本信息 | 名称、编码、类型 | 贸易商/工厂/代理 |
| 联系信息 | 联系人、电话、邮箱、地址 | 多联系人支持 |
| 资质信息 | 营业执照、税务登记、认证资质 | CE/FCC/FDA等 |
| 银行信息 | 开户行、账号、Swift Code | 支持多币种账户 |
| 合作信息 | 合作开始日期、主营品类、账期 | 历史合作记录 |

#### 3.1.2 供应商评级

**评级维度与权重**：

```java
@Service
public class SupplierRatingService {

    /**
     * 计算供应商综合评分
     *
     * 评分维度：
     * - 质量表现（30%）：合格率、退货率
     * - 交期表现（25%）：准时交货率
     * - 价格竞争力（20%）：价格水平
     * - 服务响应（15%）：响应速度、问题解决
     * - 合作稳定性（10%）：合作年限、订单量
     */
    public SupplierRating calculateRating(String supplierId) {
        SupplierRating rating = new SupplierRating();
        rating.setSupplierId(supplierId);
        rating.setRatingDate(LocalDate.now());

        // 1. 质量表现（30%）
        BigDecimal qualityScore = calculateQualityScore(supplierId);
        rating.setQualityScore(qualityScore);

        // 2. 交期表现（25%）
        BigDecimal deliveryScore = calculateDeliveryScore(supplierId);
        rating.setDeliveryScore(deliveryScore);

        // 3. 价格竞争力（20%）
        BigDecimal priceScore = calculatePriceScore(supplierId);
        rating.setPriceScore(priceScore);

        // 4. 服务响应（15%）
        BigDecimal serviceScore = calculateServiceScore(supplierId);
        rating.setServiceScore(serviceScore);

        // 5. 合作稳定性（10%）
        BigDecimal stabilityScore = calculateStabilityScore(supplierId);
        rating.setStabilityScore(stabilityScore);

        // 计算综合得分
        BigDecimal totalScore = qualityScore.multiply(BigDecimal.valueOf(0.30))
            .add(deliveryScore.multiply(BigDecimal.valueOf(0.25)))
            .add(priceScore.multiply(BigDecimal.valueOf(0.20)))
            .add(serviceScore.multiply(BigDecimal.valueOf(0.15)))
            .add(stabilityScore.multiply(BigDecimal.valueOf(0.10)));
        rating.setTotalScore(totalScore);

        // 确定等级
        rating.setGrade(determineGrade(totalScore));

        return rating;
    }

    /**
     * 质量得分计算
     * 合格率 >= 99%：100分
     * 合格率 >= 98%：90分
     * 合格率 >= 95%：70分
     * 合格率 >= 90%：50分
     * 合格率 < 90%：30分
     */
    private BigDecimal calculateQualityScore(String supplierId) {
        // 获取近6个月的质检数据
        QualityStatistics stats = qualityRepository
            .getStatistics(supplierId, 6);

        BigDecimal passRate = stats.getPassRate();

        if (passRate.compareTo(BigDecimal.valueOf(0.99)) >= 0) {
            return BigDecimal.valueOf(100);
        } else if (passRate.compareTo(BigDecimal.valueOf(0.98)) >= 0) {
            return BigDecimal.valueOf(90);
        } else if (passRate.compareTo(BigDecimal.valueOf(0.95)) >= 0) {
            return BigDecimal.valueOf(70);
        } else if (passRate.compareTo(BigDecimal.valueOf(0.90)) >= 0) {
            return BigDecimal.valueOf(50);
        } else {
            return BigDecimal.valueOf(30);
        }
    }

    /**
     * 确定供应商等级
     * A级：90-100分（优选供应商）
     * B级：80-89分（合格供应商）
     * C级：60-79分（观察供应商）
     * D级：60分以下（淘汰供应商）
     */
    private String determineGrade(BigDecimal score) {
        if (score.compareTo(BigDecimal.valueOf(90)) >= 0) {
            return "A";
        } else if (score.compareTo(BigDecimal.valueOf(80)) >= 0) {
            return "B";
        } else if (score.compareTo(BigDecimal.valueOf(60)) >= 0) {
            return "C";
        } else {
            return "D";
        }
    }
}
```

#### 3.1.3 价格协议管理

**价格协议类型**：

| 类型 | 说明 | 适用场景 |
|-----|-----|---------|
| 固定价格 | 约定期限内价格不变 | 价格稳定的标品 |
| 阶梯价格 | 按采购量分档定价 | 大批量采购 |
| 浮动价格 | 随原材料价格浮动 | 原材料类商品 |
| 框架协议 | 约定年度采购量和价格 | 长期合作供应商 |

```java
@Service
public class PriceAgreementService {

    /**
     * 获取SKU的有效采购价格
     */
    public BigDecimal getEffectivePrice(String skuId, String supplierId, int quantity) {
        // 1. 查找有效的价格协议
        List<PriceAgreement> agreements = priceAgreementRepository
            .findValidAgreements(skuId, supplierId, LocalDate.now());

        if (agreements.isEmpty()) {
            // 没有协议，返回供应商最近报价
            return getLatestQuotationPrice(skuId, supplierId);
        }

        // 2. 按优先级选择协议
        PriceAgreement agreement = selectBestAgreement(agreements, quantity);

        // 3. 根据协议类型计算价格
        switch (agreement.getPriceType()) {
            case "FIXED":
                return agreement.getUnitPrice();

            case "TIERED":
                return calculateTieredPrice(agreement, quantity);

            case "FLOATING":
                return calculateFloatingPrice(agreement);

            default:
                return agreement.getUnitPrice();
        }
    }

    /**
     * 计算阶梯价格
     */
    private BigDecimal calculateTieredPrice(PriceAgreement agreement, int quantity) {
        List<PriceTier> tiers = agreement.getPriceTiers();

        // 按数量降序排列，找到适用的价格档
        tiers.sort((a, b) -> b.getMinQty() - a.getMinQty());

        for (PriceTier tier : tiers) {
            if (quantity >= tier.getMinQty()) {
                return tier.getUnitPrice();
            }
        }

        // 默认返回最高档价格
        return tiers.get(tiers.size() - 1).getUnitPrice();
    }
}
```

### 3.2 采购计划

**采购计划生成策略**：

```java
@Service
public class PurchasePlanService {

    /**
     * 生成周采购计划
     */
    @Scheduled(cron = "0 0 8 * * MON")  // 每周一早8点执行
    public void generateWeeklyPlan() {
        log.info("开始生成周采购计划...");

        // 1. 获取所有需要补货的SKU
        List<PurchaseSuggestion> suggestions = purchaseSuggestionService
            .generateAllSuggestions();

        // 2. 按供应商分组
        Map<String, List<PurchaseSuggestion>> bySupplier = suggestions.stream()
            .collect(Collectors.groupingBy(PurchaseSuggestion::getPreferredSupplierId));

        // 3. 生成采购计划
        List<PurchasePlan> plans = new ArrayList<>();

        for (Map.Entry<String, List<PurchaseSuggestion>> entry : bySupplier.entrySet()) {
            String supplierId = entry.getKey();
            List<PurchaseSuggestion> items = entry.getValue();

            PurchasePlan plan = new PurchasePlan();
            plan.setPlanNo(generatePlanNo());
            plan.setSupplierId(supplierId);
            plan.setPlanDate(LocalDate.now());
            plan.setStatus("DRAFT");

            // 计算计划总金额
            BigDecimal totalAmount = BigDecimal.ZERO;
            List<PurchasePlanItem> planItems = new ArrayList<>();

            for (PurchaseSuggestion suggestion : items) {
                PurchasePlanItem planItem = new PurchasePlanItem();
                planItem.setPlanNo(plan.getPlanNo());
                planItem.setSkuId(suggestion.getSkuId());
                planItem.setSuggestQty(suggestion.getSuggestQty());
                planItem.setConfirmedQty(suggestion.getSuggestQty());  // 默认确认建议数量

                // 获取价格
                BigDecimal price = priceAgreementService
                    .getEffectivePrice(suggestion.getSkuId(), supplierId, suggestion.getSuggestQty());
                planItem.setUnitPrice(price);
                planItem.setAmount(price.multiply(BigDecimal.valueOf(suggestion.getSuggestQty())));

                planItems.add(planItem);
                totalAmount = totalAmount.add(planItem.getAmount());
            }

            plan.setTotalAmount(totalAmount);
            plan.setItems(planItems);
            plans.add(plan);
        }

        // 4. 保存采购计划
        purchasePlanRepository.saveAll(plans);

        // 5. 发送通知给采购人员
        notifyPurchasers(plans);

        log.info("周采购计划生成完成，共{}个计划", plans.size());
    }
}
```

---

## 四、数据库设计

### 4.1 供应商相关表

```sql
-- 供应商主表
CREATE TABLE t_supplier (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    supplier_code VARCHAR(32) NOT NULL COMMENT '供应商编码',
    supplier_name VARCHAR(128) NOT NULL COMMENT '供应商名称',
    supplier_type VARCHAR(16) COMMENT '类型：FACTORY/TRADER/AGENT',
    country VARCHAR(32) COMMENT '国家',
    province VARCHAR(32) COMMENT '省份',
    city VARCHAR(32) COMMENT '城市',
    address VARCHAR(256) COMMENT '详细地址',
    contact_name VARCHAR(64) COMMENT '联系人',
    contact_phone VARCHAR(32) COMMENT '联系电话',
    contact_email VARCHAR(128) COMMENT '联系邮箱',
    payment_terms VARCHAR(64) COMMENT '付款条件：NET30/NET60/COD',
    currency VARCHAR(8) DEFAULT 'CNY' COMMENT '结算币种',
    tax_rate DECIMAL(5,2) COMMENT '税率',
    rating VARCHAR(8) DEFAULT 'B' COMMENT '评级：A/B/C/D',
    status VARCHAR(16) DEFAULT 'ACTIVE' COMMENT '状态',
    cooperation_start_date DATE COMMENT '合作开始日期',
    remark VARCHAR(512) COMMENT '备注',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uk_supplier_code (supplier_code),
    KEY idx_status (status),
    KEY idx_rating (rating)
) COMMENT '供应商主表';

-- 供应商银行账户表
CREATE TABLE t_supplier_bank_account (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    supplier_id BIGINT NOT NULL COMMENT '供应商ID',
    account_name VARCHAR(128) NOT NULL COMMENT '账户名称',
    bank_name VARCHAR(128) NOT NULL COMMENT '银行名称',
    bank_branch VARCHAR(128) COMMENT '支行名称',
    account_no VARCHAR(64) NOT NULL COMMENT '账号',
    currency VARCHAR(8) DEFAULT 'CNY' COMMENT '币种',
    swift_code VARCHAR(32) COMMENT 'SWIFT代码（国际汇款）',
    is_default TINYINT DEFAULT 0 COMMENT '是否默认账户',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    KEY idx_supplier_id (supplier_id)
) COMMENT '供应商银行账户表';

-- 供应商评级记录表
CREATE TABLE t_supplier_rating_record (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    supplier_id BIGINT NOT NULL COMMENT '供应商ID',
    rating_date DATE NOT NULL COMMENT '评级日期',
    quality_score DECIMAL(5,2) COMMENT '质量得分',
    delivery_score DECIMAL(5,2) COMMENT '交期得分',
    price_score DECIMAL(5,2) COMMENT '价格得分',
    service_score DECIMAL(5,2) COMMENT '服务得分',
    stability_score DECIMAL(5,2) COMMENT '稳定性得分',
    total_score DECIMAL(5,2) COMMENT '综合得分',
    grade VARCHAR(8) COMMENT '等级',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    KEY idx_supplier_date (supplier_id, rating_date)
) COMMENT '供应商评级记录表';
```

### 4.2 价格协议表

```sql
-- 价格协议主表
CREATE TABLE t_price_agreement (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    agreement_no VARCHAR(32) NOT NULL COMMENT '协议编号',
    supplier_id BIGINT NOT NULL COMMENT '供应商ID',
    sku_id VARCHAR(32) NOT NULL COMMENT 'SKU编码',
    price_type VARCHAR(16) NOT NULL COMMENT '价格类型：FIXED/TIERED/FLOATING',
    unit_price DECIMAL(12,4) COMMENT '单价（固定价格时使用）',
    currency VARCHAR(8) DEFAULT 'CNY' COMMENT '币种',
    effective_date DATE NOT NULL COMMENT '生效日期',
    expiry_date DATE NOT NULL COMMENT '失效日期',
    min_order_qty INT COMMENT '最小起订量',
    status VARCHAR(16) DEFAULT 'ACTIVE' COMMENT '状态',
    remark VARCHAR(256) COMMENT '备注',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_agreement_no (agreement_no),
    KEY idx_supplier_sku (supplier_id, sku_id),
    KEY idx_effective_date (effective_date, expiry_date)
) COMMENT '价格协议主表';

-- 阶梯价格表
CREATE TABLE t_price_tier (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    agreement_id BIGINT NOT NULL COMMENT '协议ID',
    min_qty INT NOT NULL COMMENT '最小数量',
    max_qty INT COMMENT '最大数量',
    unit_price DECIMAL(12,4) NOT NULL COMMENT '单价',
    KEY idx_agreement_id (agreement_id)
) COMMENT '阶梯价格表';
```

### 4.3 采购订单表

```sql
-- 采购订单主表
CREATE TABLE t_purchase_order (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    po_no VARCHAR(32) NOT NULL COMMENT 'PO编号',
    supplier_id BIGINT NOT NULL COMMENT '供应商ID',
    supplier_code VARCHAR(32) COMMENT '供应商编码',
    supplier_name VARCHAR(128) COMMENT '供应商名称',
    warehouse_id VARCHAR(32) COMMENT '目标仓库',
    order_date DATE NOT NULL COMMENT '下单日期',
    expected_date DATE COMMENT '预计到货日期',
    currency VARCHAR(8) DEFAULT 'CNY' COMMENT '币种',
    exchange_rate DECIMAL(10,6) DEFAULT 1 COMMENT '汇率',
    total_amount DECIMAL(16,2) COMMENT '订单总金额（原币）',
    total_amount_cny DECIMAL(16,2) COMMENT '订单总金额（本位币）',
    payment_terms VARCHAR(64) COMMENT '付款条件',
    shipping_method VARCHAR(32) COMMENT '运输方式：SEA/AIR/EXPRESS',
    status VARCHAR(16) DEFAULT 'DRAFT' COMMENT '状态',
    approved_by VARCHAR(64) COMMENT '审批人',
    approved_at DATETIME COMMENT '审批时间',
    remark VARCHAR(512) COMMENT '备注',
    created_by VARCHAR(64) COMMENT '创建人',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uk_po_no (po_no),
    KEY idx_supplier_id (supplier_id),
    KEY idx_status (status),
    KEY idx_order_date (order_date)
) COMMENT '采购订单主表';

-- 采购订单明细表
CREATE TABLE t_purchase_order_item (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    po_no VARCHAR(32) NOT NULL COMMENT 'PO编号',
    seq INT NOT NULL COMMENT '行号',
    sku_id VARCHAR(32) NOT NULL COMMENT 'SKU编码',
    sku_name VARCHAR(256) COMMENT 'SKU名称',
    quantity INT NOT NULL COMMENT '采购数量',
    unit_price DECIMAL(12,4) COMMENT '单价',
    amount DECIMAL(16,2) COMMENT '金额',
    received_qty INT DEFAULT 0 COMMENT '已收货数量',
    tax_rate DECIMAL(5,2) COMMENT '税率',
    remark VARCHAR(256) COMMENT '备注',
    KEY idx_po_no (po_no),
    KEY idx_sku_id (sku_id)
) COMMENT '采购订单明细表';
```

### 4.4 ASN和收货表

```sql
-- ASN预到货通知表
CREATE TABLE t_asn (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    asn_no VARCHAR(32) NOT NULL COMMENT 'ASN编号',
    po_no VARCHAR(32) NOT NULL COMMENT '关联PO编号',
    supplier_id BIGINT NOT NULL COMMENT '供应商ID',
    warehouse_id VARCHAR(32) NOT NULL COMMENT '目标仓库',
    expected_arrival_date DATE COMMENT '预计到货日期',
    actual_arrival_date DATE COMMENT '实际到货日期',
    carrier VARCHAR(64) COMMENT '承运商',
    tracking_no VARCHAR(64) COMMENT '物流单号',
    status VARCHAR(16) DEFAULT 'PENDING' COMMENT '状态',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_asn_no (asn_no),
    KEY idx_po_no (po_no),
    KEY idx_status (status)
) COMMENT 'ASN预到货通知表';

-- ASN明细表
CREATE TABLE t_asn_item (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    asn_no VARCHAR(32) NOT NULL COMMENT 'ASN编号',
    sku_id VARCHAR(32) NOT NULL COMMENT 'SKU编码',
    expected_qty INT NOT NULL COMMENT '预计数量',
    received_qty INT DEFAULT 0 COMMENT '实收数量',
    damaged_qty INT DEFAULT 0 COMMENT '破损数量',
    KEY idx_asn_no (asn_no)
) COMMENT 'ASN明细表';

-- 收货差异表
CREATE TABLE t_receiving_variance (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    variance_no VARCHAR(32) NOT NULL COMMENT '差异单号',
    asn_no VARCHAR(32) NOT NULL COMMENT 'ASN编号',
    sku_id VARCHAR(32) NOT NULL COMMENT 'SKU编码',
    expected_qty INT NOT NULL COMMENT '预计数量',
    actual_qty INT NOT NULL COMMENT '实际数量',
    variance_qty INT NOT NULL COMMENT '差异数量',
    variance_type VARCHAR(16) COMMENT '差异类型：OVER/SHORT/DAMAGED',
    status VARCHAR(16) DEFAULT 'PENDING' COMMENT '处理状态',
    handle_result VARCHAR(256) COMMENT '处理结果',
    handled_by VARCHAR(64) COMMENT '处理人',
    handled_at DATETIME COMMENT '处理时间',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_variance_no (variance_no),
    KEY idx_asn_no (asn_no)
) COMMENT '收货差异表';
```

---

## 五、业务规则设计

### 5.1 审批流程配置

**审批规则引擎**：

```java
@Service
public class ApprovalRuleEngine {

    /**
     * 获取采购订单审批流程
     *
     * 审批规则：
     * - 金额 <= 1万：采购主管审批
     * - 金额 <= 10万：采购经理审批
     * - 金额 <= 50万：采购总监审批
     * - 金额 > 50万：总经理审批
     */
    public List<ApprovalNode> getApprovalFlow(String businessType, BigDecimal amount) {
        List<ApprovalRule> rules = approvalRuleRepository
            .findByBusinessType(businessType);

        List<ApprovalNode> nodes = new ArrayList<>();

        for (ApprovalRule rule : rules) {
            if (amount.compareTo(rule.getMinAmount()) >= 0 &&
                amount.compareTo(rule.getMaxAmount()) < 0) {

                ApprovalNode node = new ApprovalNode();
                node.setNodeName(rule.getNodeName());
                node.setApproverRole(rule.getApproverRole());
                node.setApproverIds(getApproversByRole(rule.getApproverRole()));
                node.setSeq(rule.getSeq());
                nodes.add(node);
            }
        }

        // 按序号排序
        nodes.sort(Comparator.comparingInt(ApprovalNode::getSeq));

        return nodes;
    }

    /**
     * 处理审批
     */
    @Transactional
    public void processApproval(String approvalId, String action, String comment) {
        ApprovalInstance instance = approvalRepository.findById(approvalId);

        if ("APPROVE".equals(action)) {
            // 检查是否还有下一个审批节点
            ApprovalNode nextNode = getNextNode(instance);

            if (nextNode != null) {
                // 流转到下一节点
                instance.setCurrentNode(nextNode.getNodeName());
                instance.setCurrentApprovers(nextNode.getApproverIds());
            } else {
                // 审批完成
                instance.setStatus("APPROVED");
                instance.setCompletedAt(LocalDateTime.now());

                // 回调业务系统
                callbackBusinessSystem(instance, "APPROVED");
            }
        } else if ("REJECT".equals(action)) {
            instance.setStatus("REJECTED");
            instance.setCompletedAt(LocalDateTime.now());
            instance.setRejectReason(comment);

            // 回调业务系统
            callbackBusinessSystem(instance, "REJECTED");
        }

        // 记录审批日志
        saveApprovalLog(instance, action, comment);

        approvalRepository.update(instance);
    }
}
```

### 5.2 价格管控规则

```java
@Service
public class PriceControlService {

    /**
     * 采购价格校验
     *
     * 规则：
     * 1. 不能高于历史最高价的110%
     * 2. 不能高于市场参考价的105%
     * 3. 超出需要特殊审批
     */
    public PriceCheckResult checkPrice(String skuId, String supplierId, BigDecimal price) {
        PriceCheckResult result = new PriceCheckResult();
        result.setSkuId(skuId);
        result.setInputPrice(price);

        // 1. 获取历史最高价
        BigDecimal historyMaxPrice = getHistoryMaxPrice(skuId, supplierId);
        BigDecimal historyThreshold = historyMaxPrice.multiply(BigDecimal.valueOf(1.10));

        if (price.compareTo(historyThreshold) > 0) {
            result.setExceedHistory(true);
            result.setHistoryMaxPrice(historyMaxPrice);
            result.setHistoryExceedRate(
                price.subtract(historyMaxPrice)
                    .divide(historyMaxPrice, 4, RoundingMode.HALF_UP)
            );
        }

        // 2. 获取市场参考价
        BigDecimal marketPrice = getMarketReferencePrice(skuId);
        if (marketPrice != null) {
            BigDecimal marketThreshold = marketPrice.multiply(BigDecimal.valueOf(1.05));

            if (price.compareTo(marketThreshold) > 0) {
                result.setExceedMarket(true);
                result.setMarketPrice(marketPrice);
                result.setMarketExceedRate(
                    price.subtract(marketPrice)
                        .divide(marketPrice, 4, RoundingMode.HALF_UP)
                );
            }
        }

        // 3. 判断是否需要特殊审批
        result.setNeedSpecialApproval(result.isExceedHistory() || result.isExceedMarket());

        return result;
    }
}
```

### 5.3 交期管理规则

```java
@Service
public class DeliveryManagementService {

    /**
     * 交期预警检查
     *
     * 预警规则：
     * - 红色预警：已超期
     * - 橙色预警：3天内到期
     * - 黄色预警：7天内到期
     */
    @Scheduled(cron = "0 0 9 * * *")  // 每天早9点执行
    public void checkDeliveryWarning() {
        LocalDate today = LocalDate.now();

        // 获取所有未完成的采购订单
        List<PurchaseOrder> pendingOrders = poRepository
            .findByStatusIn(Arrays.asList("APPROVED", "SHIPPED"));

        List<DeliveryWarning> warnings = new ArrayList<>();

        for (PurchaseOrder po : pendingOrders) {
            LocalDate expectedDate = po.getExpectedDate();
            if (expectedDate == null) continue;

            long daysUntilDue = ChronoUnit.DAYS.between(today, expectedDate);

            DeliveryWarning warning = new DeliveryWarning();
            warning.setPoNo(po.getPoNo());
            warning.setSupplierId(po.getSupplierId());
            warning.setSupplierName(po.getSupplierName());
            warning.setExpectedDate(expectedDate);
            warning.setDaysUntilDue((int) daysUntilDue);

            if (daysUntilDue < 0) {
                warning.setWarningLevel("RED");
                warning.setMessage("已超期" + Math.abs(daysUntilDue) + "天");
            } else if (daysUntilDue <= 3) {
                warning.setWarningLevel("ORANGE");
                warning.setMessage("即将到期，剩余" + daysUntilDue + "天");
            } else if (daysUntilDue <= 7) {
                warning.setWarningLevel("YELLOW");
                warning.setMessage("临近到期，剩余" + daysUntilDue + "天");
            } else {
                continue;  // 不需要预警
            }

            warnings.add(warning);
        }

        // 发送预警通知
        if (!warnings.isEmpty()) {
            sendWarningNotifications(warnings);
        }
    }

    /**
     * 更新供应商交期表现
     */
    public void updateDeliveryPerformance(String poNo, LocalDate actualDate) {
        PurchaseOrder po = poRepository.findByPoNo(poNo);
        LocalDate expectedDate = po.getExpectedDate();

        // 计算交期偏差
        long variance = ChronoUnit.DAYS.between(expectedDate, actualDate);

        // 记录交期表现
        DeliveryPerformance performance = new DeliveryPerformance();
        performance.setSupplierId(po.getSupplierId());
        performance.setPoNo(poNo);
        performance.setExpectedDate(expectedDate);
        performance.setActualDate(actualDate);
        performance.setVarianceDays((int) variance);
        performance.setOnTime(variance <= 0);

        deliveryPerformanceRepository.save(performance);

        // 更新供应商准时交货率
        updateSupplierOnTimeRate(po.getSupplierId());
    }
}
```

---

## 六、实战案例

### 6.1 完整采购流程演示

**场景**：某跨境电商公司需要从1688供应商采购一批蓝牙耳机，用于亚马逊美国站销售。

**Step 1：需求计划生成**

```
系统自动检测到：
- SKU: BT-EARPHONE-001
- 当前库存：500件
- 安全库存：800件
- 日均销量：50件
- 采购周期：14天（含生产+物流）
- 目标库存：800 + 50×14 = 1500件
- 建议采购量：1500 - 500 = 1000件

系统生成采购建议，紧急程度：HIGH（库存低于安全库存）
```

**Step 2：询价比价**

```
向3家供应商发送询价：
- 供应商A（工厂）：$8.5/件，交期15天，MOQ 500
- 供应商B（贸易商）：$9.0/件，交期10天，MOQ 200
- 供应商C（工厂）：$8.2/件，交期20天，MOQ 1000

比价结果（综合评分）：
1. 供应商A：85分（价格适中，交期合适）
2. 供应商C：78分（价格最低，但交期太长）
3. 供应商B：72分（价格最高，但交期最短）

系统推荐：供应商A
```

**Step 3：创建采购订单**

```
PO编号：PO202602040001
供应商：供应商A
币种：USD
汇率：7.20

明细：
- BT-EARPHONE-001 × 1000件 × $8.5 = $8,500
- 运费：$200
- 总金额：$8,700（折合人民币：¥62,640）

付款条件：30%预付，70%发货前付清
预计到货：2026-02-18
```

**Step 4：审批流程**

```
金额：¥62,640（属于1万-10万区间）
审批流程：采购主管 → 采购经理

审批记录：
- 2026-02-04 10:30 采购主管张三 审批通过
- 2026-02-04 14:20 采购经理李四 审批通过

PO状态变更：DRAFT → PENDING → APPROVED
```

**Step 5：付款申请**

```
预付款申请：
- 金额：$8,700 × 30% = $2,610
- 付款方式：T/T
- 收款账户：供应商A美元账户

财务审批后付款，记录：
借：预付账款 ¥18,792
贷：银行存款 ¥18,792
```

**Step 6：到货验收**

```
2026-02-17 供应商发货，创建ASN：
- ASN编号：ASN202602170001
- 物流单号：SF1234567890
- 预计到货：2026-02-18

2026-02-18 仓库收货：
- 预计数量：1000件
- 实收数量：998件
- 破损数量：2件

质检结果：
- 抽检50件，合格49件
- 合格率：98%
- 判定：合格

差异处理：
- 短少2件，生成差异单
- 与供应商协商，下次补发
```

**Step 7：入库结算**

```
入库完成，系统自动处理：

1. 更新库存：
   - 原库存：500件
   - 入库：998件
   - 新库存：1498件

2. 成本核算（移动加权平均）：
   - 原库存成本：500 × ¥60 = ¥30,000
   - 入库成本：998 × ¥61.2 = ¥61,077.6
   - 新单位成本：(30,000 + 61,077.6) / 1498 = ¥60.82

3. 生成凭证：
   借：库存商品 ¥61,077.6
   贷：应付账款 ¥61,077.6

4. 更新应付账款：
   - 已付预付款：¥18,792
   - 待付尾款：¥61,077.6 - ¥18,792 = ¥42,285.6
```

### 6.2 踩坑经验分享

#### 踩坑1：汇率波动导致成本失控

**问题**：采购时汇率7.0，付款时汇率涨到7.3，导致成本增加4.3%。

**解决方案**：
```java
// 大额采购时锁定汇率
public void lockExchangeRate(String poNo, BigDecimal lockedRate) {
    PurchaseOrder po = poRepository.findByPoNo(poNo);

    // 记录锁定汇率
    po.setLockedRate(lockedRate);
    po.setRateLockDate(LocalDate.now());

    // 与银行签订远期结汇协议
    forexService.createForwardContract(
        po.getCurrency(),
        po.getTotalAmount(),
        lockedRate,
        po.getExpectedDate()
    );

    poRepository.update(po);
}
```

**经验**：金额超过10万美元的采购，建议锁定汇率。

#### 踩坑2：供应商交期延误影响销售

**问题**：供应商承诺15天交货，实际25天才到，导致断货10天，损失销售额约5万美元。

**解决方案**：
```java
// 建立供应商交期信用体系
public int getAdjustedLeadTime(String supplierId, int promisedLeadTime) {
    // 获取供应商历史交期表现
    DeliveryStatistics stats = deliveryRepository.getStatistics(supplierId);

    // 计算平均延误天数
    int avgDelay = stats.getAvgDelayDays();

    // 调整后的交期 = 承诺交期 + 历史平均延误 + 安全缓冲
    int safetyBuffer = 3;  // 3天安全缓冲
    return promisedLeadTime + avgDelay + safetyBuffer;
}
```

**经验**：不要完全相信供应商承诺的交期，要根据历史数据调整。

#### 踩坑3：质量问题导致大批退货

**问题**：一批货到货后发现质量问题，退货率高达15%，严重影响销售评分。

**解决方案**：
```java
// 建立供应商质量预警机制
public void checkSupplierQualityTrend(String supplierId) {
    // 获取近3个月质量数据
    List<QualityRecord> records = qualityRepository
        .findBySupplierId(supplierId, 3);

    // 计算质量趋势
    BigDecimal currentPassRate = records.get(0).getPassRate();
    BigDecimal avgPassRate = calculateAvgPassRate(records);

    // 如果当前合格率低于平均值5%以上，发出预警
    if (currentPassRate.compareTo(avgPassRate.subtract(BigDecimal.valueOf(0.05))) < 0) {
        sendQualityWarning(supplierId, currentPassRate, avgPassRate);

        // 自动调整该供应商的质检策略为全检
        updateInspectionStrategy(supplierId, "FULL_INSPECTION");
    }
}
```

**经验**：建立质量趋势监控，发现问题苗头及时干预。

#### 踩坑4：MOQ限制导致库存积压

**问题**：供应商MOQ是1000件，但实际只需要500件，导致多采购500件积压。

**解决方案**：
```java
// 智能采购建议，考虑MOQ和库存周转
public PurchaseSuggestion generateSmartSuggestion(String skuId) {
    int suggestQty = calculateBaseSuggestion(skuId);
    int moq = getSupplierMoq(skuId);

    if (suggestQty < moq) {
        // 计算如果按MOQ采购，库存周转天数
        int avgDailySales = getAvgDailySales(skuId);
        int turnoverDays = moq / avgDailySales;

        if (turnoverDays > 90) {
            // 周转超过90天，建议寻找其他供应商或暂不采购
            return PurchaseSuggestion.builder()
                .skuId(skuId)
                .suggestQty(0)
                .reason("MOQ过高，建议寻找其他供应商")
                .alternativeSuppliers(findAlternativeSuppliers(skuId, suggestQty))
                .build();
        }
    }

    return PurchaseSuggestion.builder()
        .skuId(skuId)
        .suggestQty(Math.max(suggestQty, moq))
        .build();
}
```

**经验**：采购前评估MOQ对库存周转的影响，必要时寻找替代供应商。

---

## 七、总结

### 7.1 核心要点回顾

| 模块 | 核心功能 | 关键设计 |
|-----|---------|---------|
| 需求计划 | 采购建议生成 | 安全库存+销售预测+在途库存 |
| 询价比价 | 综合评分比价 | 价格40%+交期25%+质量20%+付款10%+服务5% |
| 采购下单 | PO创建与审批 | 多币种支持+审批流程引擎 |
| 到货验收 | ASN+质检 | 预到货通知+差异处理 |
| 入库结算 | 成本核算+应付 | 移动加权平均+自动生成凭证 |

### 7.2 跨境电商采购的特殊考量

1. **多币种管理**：支持USD、EUR等多币种采购，自动汇率转换
2. **海外供应商**：考虑时差、语言、付款方式差异
3. **国际物流**：海运/空运选择，清关时效预估
4. **合规要求**：CE/FCC/FDA等认证资质管理

### 7.3 实施建议

1. **分阶段实施**：
   - 第一阶段：供应商管理+采购订单（2-3周）
   - 第二阶段：询价比价+审批流程（2周）
   - 第三阶段：到货验收+入库结算（2周）

2. **数据迁移**：
   - 供应商档案从Excel导入
   - 历史采购数据用于初始化供应商评级

3. **系统集成**：
   - 与WMS对接：ASN推送、入库回执
   - 与财务系统对接：凭证同步

---

> **系列文章导航**
>
> 本文是《跨境电商数字化转型指南》系列的第11篇
>
> **ERP自研篇**：
> - [x] 10. [ERP核心模块设计——财务、采购、库存三位一体](/blog/digital-transformation/posts/10-erp-overview/)
> - [x] 11. 采购管理系统设计（本文）
> - [ ] 12. 财务核算模块设计——多币种、多主体的挑战
> - [ ] 13. 库存成本核算——移动加权平均法实战