---
title: "TMS运费管理：从计费规则到自动结算的完整方案"
date: 2025-11-21T18:00:00+08:00
draft: false
tags: ["TMS", "运费管理", "自动结算", "计费规则"]
categories: ["供应链系统"]
description: "详细讲解运费计算规则设计和自动结算系统实现。从首重续重到体积重量换算,从运费模板到账单生成,全面掌握TMS的财务管理能力。"
weight: 5
stage: 1
stageTitle: "基础入门篇"
---

## 引言

运费管理是TMS的财务核心,直接关系到企业的成本控制和利润空间。一个完善的运费管理系统,可以实现运费自动计算、账单自动生成、对账自动核对,大幅降低人工成本和差错率。

本文将详细讲解运费计算规则的设计方法、运费模板的管理机制、自动结算系统的实现方案,为TMS提供完整的财务解决方案。

---

## 1. 运费计算规则

### 1.1 重量计费

#### 首重续重

**规则说明**：
- **首重**：1kg或更少,收取首重价格
- **续重**：超过首重部分,按续重价格计费

**计算公式**：
```
if (weight <= 首重) {
    运费 = 首重价格
} else {
    运费 = 首重价格 + (weight - 首重) × 续重价格
}
```

**示例**：
```
规则: 首重1kg/5元, 续重2元/kg

计算:
- 0.5kg: 5元 (不足首重按首重计)
- 1kg: 5元
- 1.5kg: 5 + (1.5-1) × 2 = 6元
- 2.5kg: 5 + (2.5-1) × 2 = 8元
```

**Java实现**：
```java
public class FirstWeightFreightCalculator {

    public BigDecimal calculate(BigDecimal weight, FreightRule rule) {
        BigDecimal firstWeight = rule.getFirstWeight();
        BigDecimal firstWeightPrice = rule.getFirstWeightPrice();
        BigDecimal 续重Price = rule.get续重Price();

        // 不足首重按首重计
        if (weight.compareTo(firstWeight) <= 0) {
            return firstWeightPrice;
        }

        // 超过首重部分
        BigDecimal 续重 = weight.subtract(firstWeight);

        // 续重向上取整(0.1kg也算1kg)
        续重 = 续重.setScale(0, RoundingMode.UP);

        return firstWeightPrice.add(续重.multiply(续重Price));
    }
}
```

#### 阶梯定价

**规则说明**：
- 不同重量区间,使用不同单价
- 重量越大,单价越低

**示例**：
```
规则:
- 0-100kg: 2元/kg
- 100-500kg: 1.5元/kg
- 500kg+: 1元/kg

计算:
- 50kg: 50 × 2 = 100元
- 150kg: 100 × 2 + 50 × 1.5 = 275元
- 600kg: 100 × 2 + 400 × 1.5 + 100 × 1 = 900元
```

**Java实现**：
```java
public class TieredPricingCalculator {

    public BigDecimal calculate(BigDecimal weight, List<PriceTier> tiers) {
        BigDecimal totalFreight = BigDecimal.ZERO;
        BigDecimal remainingWeight = weight;

        for (PriceTier tier : tiers) {
            if (remainingWeight.compareTo(BigDecimal.ZERO) <= 0) {
                break;
            }

            // 当前阶梯的重量
            BigDecimal tierWeight = tier.getMaxWeight().subtract(tier.getMinWeight());
            BigDecimal actualWeight = remainingWeight.min(tierWeight);

            // 当前阶梯的运费
            BigDecimal tierFreight = actualWeight.multiply(tier.getUnitPrice());
            totalFreight = totalFreight.add(tierFreight);

            remainingWeight = remainingWeight.subtract(actualWeight);
        }

        return totalFreight;
    }
}

@Data
class PriceTier {
    private BigDecimal minWeight;   // 最小重量
    private BigDecimal maxWeight;   // 最大重量
    private BigDecimal unitPrice;   // 单价
}
```

### 1.2 体积计费

#### 体积重量换算

**规则说明**：
- 体积重量(kg) = 长(cm) × 宽(cm) × 高(cm) ÷ 6000
- 计费重量 = max(实际重量, 体积重量)

**为什么要换算？**
- 轻泡货物(如棉花、泡沫)实际重量轻但占空间大
- 按体积收费更合理,避免承运商亏损

**示例**：
```
货物1: 尺寸60×40×30cm, 实际重量5kg
- 体积重量 = 60 × 40 × 30 ÷ 6000 = 12kg
- 计费重量 = max(5, 12) = 12kg

货物2: 尺寸30×20×10cm, 实际重量8kg
- 体积重量 = 30 × 20 × 10 ÷ 6000 = 1kg
- 计费重量 = max(8, 1) = 8kg
```

**Java实现**：
```java
public class VolumeWeightCalculator {

    private static final int VOLUME_DIVISOR = 6000;

    public BigDecimal calculateBillableWeight(BigDecimal actualWeight,
                                             BigDecimal length,
                                             BigDecimal width,
                                             BigDecimal height) {

        // 计算体积重量
        BigDecimal volumeWeight = length.multiply(width).multiply(height)
            .divide(new BigDecimal(VOLUME_DIVISOR), 2, RoundingMode.HALF_UP);

        // 取大值
        return actualWeight.max(volumeWeight);
    }
}
```

### 1.3 距离计费

#### 按公里数计费

**规则说明**：
- 适用于整车运输
- 运费 = 起步价 + (实际里程 - 起步里程) × 单价

**示例**：
```
规则: 起步价200元(含50km), 单价3元/km

计算:
- 30km: 200元 (不足起步里程按起步价)
- 50km: 200元
- 100km: 200 + (100-50) × 3 = 350元
- 500km: 200 + (500-50) × 3 = 1550元
```

**Java实现**：
```java
public class DistanceFreightCalculator {

    public BigDecimal calculate(BigDecimal distance, FreightRule rule) {
        BigDecimal basePrice = rule.getBasePrice();
        BigDecimal baseDistance = rule.getBaseDistance();
        BigDecimal unitPrice = rule.getUnitPricePerKm();

        // 不足起步里程按起步价
        if (distance.compareTo(baseDistance) <= 0) {
            return basePrice;
        }

        // 超过起步里程部分
        BigDecimal extraDistance = distance.subtract(baseDistance);

        return basePrice.add(extraDistance.multiply(unitPrice));
    }
}
```

#### 分段定价

**规则说明**：
- 不同距离区间,使用不同单价
- 长途运输,单价递减

**示例**：
```
规则:
- 0-100km: 3元/km
- 100-500km: 2元/km
- 500km+: 1.5元/km

计算:
- 50km: 50 × 3 = 150元
- 300km: 100 × 3 + 200 × 2 = 700元
- 600km: 100 × 3 + 400 × 2 + 100 × 1.5 = 1250元
```

### 1.4 时效加价

**规则说明**：
- 标准时效(3-5天): 无加价
- 快速时效(1-2天): +20%
- 极速时效(当日/次日): +50%

**示例**：
```
基础运费: 100元

- 标准时效: 100 × 1.0 = 100元
- 快速时效: 100 × 1.2 = 120元
- 极速时效: 100 × 1.5 = 150元
```

**Java实现**：
```java
public class TimeRequirementAdjuster {

    public BigDecimal adjust(BigDecimal baseFreight, String timeRequirement) {
        BigDecimal rate = getTimeRequirementRate(timeRequirement);
        return baseFreight.multiply(rate);
    }

    private BigDecimal getTimeRequirementRate(String timeRequirement) {
        switch (timeRequirement) {
            case "STANDARD":
                return new BigDecimal("1.0");
            case "EXPRESS":
                return new BigDecimal("1.2");
            case "URGENT":
                return new BigDecimal("1.5");
            default:
                return new BigDecimal("1.0");
        }
    }
}
```

### 1.5 特殊货物加价

**规则说明**：
- 易碎品: +10%
- 贵重物品: +20%
- 危险品: +30%

**示例**：
```
基础运费: 100元

- 普通货物: 100 × 1.0 = 100元
- 易碎品: 100 × 1.1 = 110元
- 贵重物品: 100 × 1.2 = 120元
- 危险品: 100 × 1.3 = 130元
```

**Java实现**：
```java
public class CargoTypeAdjuster {

    public BigDecimal adjust(BigDecimal baseFreight, String cargoType) {
        BigDecimal rate = getCargoTypeRate(cargoType);
        return baseFreight.multiply(rate);
    }

    private BigDecimal getCargoTypeRate(String cargoType) {
        switch (cargoType) {
            case "NORMAL":
                return new BigDecimal("1.0");
            case "FRAGILE":
                return new BigDecimal("1.1");
            case "VALUABLE":
                return new BigDecimal("1.2");
            case "DANGEROUS":
                return new BigDecimal("1.3");
            default:
                return new BigDecimal("1.0");
        }
    }
}
```

### 1.6 综合计算

**完整的运费计算流程**：
```
1. 计算计费重量
   - 体积重量 = 长×宽×高÷6000
   - 计费重量 = max(实际重量, 体积重量)

2. 计算基础运费
   - 按重量/体积/距离/件数计费

3. 时效加价
   - 基础运费 × 时效费率

4. 特殊货物加价
   - (基础运费 × 时效费率) × 货物类型费率

5. 最低收费
   - 运费 = max(计算运费, 最低收费)
```

**Java实现**：
```java
@Service
public class FreightCalculationService {

    @Autowired
    private VolumeWeightCalculator volumeWeightCalculator;

    @Autowired
    private FirstWeightFreightCalculator firstWeightCalculator;

    @Autowired
    private TimeRequirementAdjuster timeRequirementAdjuster;

    @Autowired
    private CargoTypeAdjuster cargoTypeAdjuster;

    public BigDecimal calculate(TransportOrder order, FreightRule rule) {

        // 1. 计算计费重量
        BigDecimal billableWeight = volumeWeightCalculator.calculateBillableWeight(
            order.getCargoWeight(),
            order.getCargoLength(),
            order.getCargoWidth(),
            order.getCargoHeight()
        );

        // 2. 计算基础运费
        BigDecimal baseFreight = calculateBaseFreight(billableWeight, rule);

        // 3. 时效加价
        BigDecimal freightWithTime = timeRequirementAdjuster.adjust(
            baseFreight,
            order.getTimeRequirement()
        );

        // 4. 特殊货物加价
        BigDecimal freightWithCargo = cargoTypeAdjuster.adjust(
            freightWithTime,
            order.getCargoType()
        );

        // 5. 最低收费
        BigDecimal minCharge = rule.getMinCharge();
        if (freightWithCargo.compareTo(minCharge) < 0) {
            freightWithCargo = minCharge;
        }

        return freightWithCargo.setScale(2, RoundingMode.HALF_UP);
    }

    private BigDecimal calculateBaseFreight(BigDecimal weight, FreightRule rule) {
        switch (rule.getCalculationType()) {
            case "BY_WEIGHT":
                return firstWeightCalculator.calculate(weight, rule);
            case "BY_DISTANCE":
                return distanceCalculator.calculate(distance, rule);
            // ... 其他计费方式
            default:
                return BigDecimal.ZERO;
        }
    }
}
```

---

## 2. 运费模板管理

### 2.1 模板分类

**按运输方式分类**：
- 快递模板：重量计费,首重续重
- 零担模板：重量/体积计费,阶梯定价
- 整车模板：距离计费,分段定价

**按服务区域分类**：
- 同城模板：北京→北京
- 省内模板：北京→河北
- 跨省模板：北京→上海
- 全国模板：全国通用

**按客户类型分类**：
- VIP客户模板：价格优惠
- 普通客户模板：标准价格
- 新客户模板：首单优惠

### 2.2 模板配置

**模板数据结构**：
```java
@Data
public class FreightTemplate {

    private Long id;
    private String templateCode;      // 模板编码
    private String templateName;      // 模板名称

    // 适用范围
    private Long carrierId;           // 承运商ID
    private String transportType;     // 运输方式
    private String fromProvince;      // 起始省份
    private String fromCity;          // 起始城市
    private String toProvince;        // 目的省份
    private String toCity;            // 目的城市

    // 计费方式
    private String calculationType;   // BY_WEIGHT/BY_VOLUME/BY_DISTANCE

    // 重量计费参数
    private BigDecimal firstWeight;
    private BigDecimal firstWeightPrice;
    private BigDecimal 续重Price;

    // 体积计费参数
    private BigDecimal firstVolume;
    private BigDecimal firstVolumePrice;
    private BigDecimal 续体积Price;

    // 距离计费参数
    private BigDecimal basePrice;
    private BigDecimal baseDistance;
    private BigDecimal unitPricePerKm;

    // 价格限制
    private BigDecimal minCharge;     // 最低收费
    private BigDecimal maxWeight;     // 最大重量
    private BigDecimal maxVolume;     // 最大体积

    // 时效费率
    private BigDecimal standardRate;  // 标准时效费率
    private BigDecimal expressRate;   // 快速时效费率
    private BigDecimal urgentRate;    // 极速时效费率

    // 特殊货物费率
    private BigDecimal fragileRate;   // 易碎品费率
    private BigDecimal valuableRate;  // 贵重物品费率
    private BigDecimal dangerousRate; // 危险品费率

    // 生效时间
    private LocalDate effectiveDate;
    private LocalDate expiryDate;

    // 状态
    private String status;            // ACTIVE/INACTIVE
}
```

**模板管理接口**：
```java
@Service
public class FreightTemplateService {

    @Autowired
    private FreightTemplateMapper templateMapper;

    /**
     * 创建模板
     */
    public void createTemplate(FreightTemplate template) {
        // 生成模板编码
        template.setTemplateCode(generateTemplateCode());
        template.setStatus("ACTIVE");
        templateMapper.insert(template);
    }

    /**
     * 更新模板
     */
    public void updateTemplate(FreightTemplate template) {
        templateMapper.updateById(template);
    }

    /**
     * 停用模板
     */
    public void deactivateTemplate(Long id) {
        FreightTemplate template = templateMapper.selectById(id);
        template.setStatus("INACTIVE");
        templateMapper.updateById(template);
    }

    /**
     * 查询模板
     */
    public FreightTemplate getTemplate(Long carrierId, String transportType,
                                      String fromCity, String toCity) {

        LambdaQueryWrapper<FreightTemplate> wrapper = new LambdaQueryWrapper<>();
        wrapper.eq(FreightTemplate::getCarrierId, carrierId)
               .eq(FreightTemplate::getTransportType, transportType)
               .eq(FreightTemplate::getFromCity, fromCity)
               .eq(FreightTemplate::getToCity, toCity)
               .eq(FreightTemplate::getStatus, "ACTIVE")
               .le(FreightTemplate::getEffectiveDate, LocalDate.now())
               .ge(FreightTemplate::getExpiryDate, LocalDate.now());

        return templateMapper.selectOne(wrapper);
    }

    /**
     * 模板匹配(按优先级)
     */
    public FreightTemplate matchTemplate(TransportOrder order) {
        // 1. 精确匹配：城市→城市
        FreightTemplate template = getTemplate(
            order.getCarrierId(),
            order.getTransportType(),
            order.getShipperCity(),
            order.getConsigneeCity()
        );

        if (template != null) return template;

        // 2. 省级匹配：省→省
        template = getTemplate(
            order.getCarrierId(),
            order.getTransportType(),
            order.getShipperProvince(),
            order.getConsigneeProvince()
        );

        if (template != null) return template;

        // 3. 全国通用模板
        template = getTemplate(
            order.getCarrierId(),
            order.getTransportType(),
            null,
            null
        );

        return template;
    }

    private String generateTemplateCode() {
        return "FT" + System.currentTimeMillis();
    }
}
```

### 2.3 模板生效规则

**生效逻辑**：
```
1. 时间范围内: effectiveDate <= today <= expiryDate
2. 状态为ACTIVE
3. 匹配优先级:
   - 精确匹配(城市→城市) > 省级匹配(省→省) > 全国通用
```

**模板冲突处理**：
```java
public class TemplateConflictResolver {

    public FreightTemplate resolve(List<FreightTemplate> templates) {
        if (templates.isEmpty()) return null;
        if (templates.size() == 1) return templates.get(0);

        // 按优先级排序
        templates.sort(Comparator
            .comparing(this::getMatchLevel)        // 匹配级别
            .thenComparing(FreightTemplate::getEffectiveDate)  // 生效时间(新的优先)
        );

        return templates.get(0);
    }

    private int getMatchLevel(FreightTemplate template) {
        // 精确匹配:1, 省级匹配:2, 全国通用:3
        if (template.getFromCity() != null && template.getToCity() != null) {
            return 1;
        } else if (template.getFromProvince() != null && template.getToProvince() != null) {
            return 2;
        } else {
            return 3;
        }
    }
}
```

---

## 3. 自动结算系统

### 3.1 账单生成

#### 定时任务

**生成策略**：
- 每月1日凌晨2点生成上月账单
- 按承运商分组,生成多张账单

**定时任务实现**：
```java
@Component
public class BillingTask {

    @Autowired
    private BillingService billingService;

    @Scheduled(cron = "0 0 2 1 * ?")  // 每月1日凌晨2点
    public void generateMonthlyBill() {
        log.info("开始生成月度账单");

        // 上月时间范围
        LocalDate startDate = LocalDate.now().minusMonths(1).withDayOfMonth(1);
        LocalDate endDate = LocalDate.now().withDayOfMonth(1).minusDays(1);

        billingService.generateBill(startDate, endDate);

        log.info("月度账单生成完成");
    }
}
```

#### 账单明细

**账单数据结构**：
```java
@Data
public class FreightBill {

    private Long id;
    private String billNo;            // 账单号
    private Long carrierId;           // 承运商ID
    private String carrierName;       // 承运商名称

    // 账期
    private LocalDate startDate;      // 开始日期
    private LocalDate endDate;        // 结束日期

    // 统计信息
    private Integer totalOrders;      // 总订单数
    private BigDecimal totalFreight;  // 总运费
    private BigDecimal discount;      // 折扣金额
    private BigDecimal actualFreight; // 实付运费

    // 明细
    private List<FreightBillDetail> details;

    // 状态
    private String status;            // PENDING/CONFIRMED/PAID

    // 时间
    private LocalDateTime createdTime;
    private LocalDateTime confirmedTime;
    private LocalDateTime paidTime;
}

@Data
class FreightBillDetail {
    private Long id;
    private Long billId;
    private String waybillNo;         // 运单号
    private LocalDate shipDate;       // 发货日期
    private BigDecimal freight;       // 运费
}
```

**账单生成逻辑**：
```java
@Service
public class BillingService {

    @Autowired
    private WaybillMapper waybillMapper;

    @Autowired
    private FreightBillMapper billMapper;

    @Transactional
    public void generateBill(LocalDate startDate, LocalDate endDate) {

        // 查询所有承运商
        List<Carrier> carriers = carrierService.listAll();

        for (Carrier carrier : carriers) {
            // 查询该承运商的运单
            List<Waybill> waybills = waybillMapper.selectByCarrierAndDate(
                carrier.getId(),
                startDate,
                endDate
            );

            if (waybills.isEmpty()) continue;

            // 生成账单
            FreightBill bill = new FreightBill();
            bill.setBillNo(generateBillNo());
            bill.setCarrierId(carrier.getId());
            bill.setCarrierName(carrier.getCarrierName());
            bill.setStartDate(startDate);
            bill.setEndDate(endDate);
            bill.setStatus("PENDING");

            // 统计信息
            int totalOrders = waybills.size();
            BigDecimal totalFreight = waybills.stream()
                .map(Waybill::getFreight)
                .reduce(BigDecimal.ZERO, BigDecimal::add);

            // 计算折扣(如大客户9折)
            BigDecimal discount = calculateDiscount(carrier, totalFreight);
            BigDecimal actualFreight = totalFreight.subtract(discount);

            bill.setTotalOrders(totalOrders);
            bill.setTotalFreight(totalFreight);
            bill.setDiscount(discount);
            bill.setActualFreight(actualFreight);

            // 插入账单
            billMapper.insert(bill);

            // 插入明细
            for (Waybill waybill : waybills) {
                FreightBillDetail detail = new FreightBillDetail();
                detail.setBillId(bill.getId());
                detail.setWaybillNo(waybill.getWaybillNo());
                detail.setShipDate(waybill.getPickupTime().toLocalDate());
                detail.setFreight(waybill.getFreight());

                billDetailMapper.insert(detail);
            }

            log.info("已生成账单: {}, 承运商: {}, 金额: {}",
                bill.getBillNo(), carrier.getCarrierName(), actualFreight);
        }
    }

    private String generateBillNo() {
        return "BILL" + LocalDate.now().format(DateTimeFormatter.ofPattern("yyyyMM"))
            + String.format("%06d", billMapper.selectCount(null) + 1);
    }

    private BigDecimal calculateDiscount(Carrier carrier, BigDecimal totalFreight) {
        // 大客户9折
        if ("A".equals(carrier.getGrade())) {
            return totalFreight.multiply(new BigDecimal("0.1"));
        }
        return BigDecimal.ZERO;
    }
}
```

### 3.2 对账流程

**对账步骤**：
```
1. 系统生成账单 → 推送给承运商

2. 承运商核对账单
   - 核对订单数量
   - 核对运费金额
   - 标注差异订单

3. 差异处理
   - 补单: 系统漏记的订单
   - 调整: 运费计算错误
   - 作废: 已取消的订单

4. 双方确认
   - 承运商确认
   - 财务确认
   - 状态变更为CONFIRMED
```

**差异处理**：
```java
@Service
public class BillReconciliationService {

    @Autowired
    private FreightBillMapper billMapper;

    /**
     * 添加补单
     */
    public void addMissingWaybill(Long billId, String waybillNo) {
        // 查询运单
        Waybill waybill = waybillMapper.selectByWaybillNo(waybillNo);
        if (waybill == null) {
            throw new BusinessException("运单不存在");
        }

        // 添加到账单明细
        FreightBillDetail detail = new FreightBillDetail();
        detail.setBillId(billId);
        detail.setWaybillNo(waybillNo);
        detail.setShipDate(waybill.getPickupTime().toLocalDate());
        detail.setFreight(waybill.getFreight());

        billDetailMapper.insert(detail);

        // 更新账单总额
        updateBillAmount(billId);

        log.info("已添加补单: billId={}, waybillNo={}", billId, waybillNo);
    }

    /**
     * 调整运费
     */
    public void adjustFreight(Long detailId, BigDecimal newFreight, String reason) {
        FreightBillDetail detail = billDetailMapper.selectById(detailId);
        BigDecimal oldFreight = detail.getFreight();

        detail.setFreight(newFreight);
        billDetailMapper.updateById(detail);

        // 更新账单总额
        updateBillAmount(detail.getBillId());

        log.info("已调整运费: detailId={}, oldFreight={}, newFreight={}, reason={}",
            detailId, oldFreight, newFreight, reason);
    }

    /**
     * 作废订单
     */
    public void cancelDetail(Long detailId, String reason) {
        FreightBillDetail detail = billDetailMapper.selectById(detailId);

        billDetailMapper.deleteById(detailId);

        // 更新账单总额
        updateBillAmount(detail.getBillId());

        log.info("已作废明细: detailId={}, reason={}", detailId, reason);
    }

    /**
     * 确认账单
     */
    public void confirmBill(Long billId) {
        FreightBill bill = billMapper.selectById(billId);
        bill.setStatus("CONFIRMED");
        bill.setConfirmedTime(LocalDateTime.now());
        billMapper.updateById(bill);

        log.info("账单已确认: billId={}", billId);
    }

    private void updateBillAmount(Long billId) {
        List<FreightBillDetail> details = billDetailMapper.selectByBillId(billId);

        BigDecimal totalFreight = details.stream()
            .map(FreightBillDetail::getFreight)
            .reduce(BigDecimal.ZERO, BigDecimal::add);

        FreightBill bill = billMapper.selectById(billId);
        bill.setTotalFreight(totalFreight);
        bill.setActualFreight(totalFreight.subtract(bill.getDiscount()));
        billMapper.updateById(bill);
    }
}
```

### 3.3 财务结算

**结算流程**：
```
1. 账单确认完成

2. 生成付款申请
   - 创建付款申请单
   - 关联账单
   - 填写付款信息

3. 推送到ERP系统
   - 调用ERP接口
   - 传输账单数据

4. 财务部执行付款
   - 审批通过
   - 银行转账
   - 更新付款状态

5. 账单状态变更为PAID
```

**付款申请**：
```java
@Service
public class PaymentService {

    @Autowired
    private FreightBillMapper billMapper;

    @Autowired
    private ErpApiClient erpApiClient;

    /**
     * 生成付款申请
     */
    public PaymentRequest createPaymentRequest(Long billId) {
        FreightBill bill = billMapper.selectById(billId);

        if (!"CONFIRMED".equals(bill.getStatus())) {
            throw new BusinessException("账单未确认,无法生成付款申请");
        }

        // 创建付款申请
        PaymentRequest request = new PaymentRequest();
        request.setBillId(billId);
        request.setBillNo(bill.getBillNo());
        request.setCarrierId(bill.getCarrierId());
        request.setCarrierName(bill.getCarrierName());
        request.setAmount(bill.getActualFreight());
        request.setStatus("PENDING");

        paymentRequestMapper.insert(request);

        log.info("已生成付款申请: billNo={}, amount={}",
            bill.getBillNo(), bill.getActualFreight());

        return request;
    }

    /**
     * 推送到ERP
     */
    public void pushToErp(Long requestId) {
        PaymentRequest request = paymentRequestMapper.selectById(requestId);

        // 调用ERP接口
        ErpPaymentRequest erpRequest = new ErpPaymentRequest();
        erpRequest.setBillNo(request.getBillNo());
        erpRequest.setVendorCode(request.getCarrierCode());
        erpRequest.setVendorName(request.getCarrierName());
        erpRequest.setAmount(request.getAmount());

        ErpPaymentResponse response = erpApiClient.createPayment(erpRequest);

        if (response.isSuccess()) {
            request.setErpPaymentNo(response.getPaymentNo());
            request.setStatus("PUSHED");
            paymentRequestMapper.updateById(request);

            log.info("付款申请已推送到ERP: requestId={}, erpPaymentNo={}",
                requestId, response.getPaymentNo());
        } else {
            throw new BusinessException("推送ERP失败: " + response.getMessage());
        }
    }

    /**
     * 更新付款状态
     */
    public void updatePaymentStatus(Long requestId, String status) {
        PaymentRequest request = paymentRequestMapper.selectById(requestId);
        request.setStatus(status);

        if ("PAID".equals(status)) {
            request.setPaidTime(LocalDateTime.now());

            // 更新账单状态
            FreightBill bill = billMapper.selectById(request.getBillId());
            bill.setStatus("PAID");
            bill.setPaidTime(LocalDateTime.now());
            billMapper.updateById(bill);
        }

        paymentRequestMapper.updateById(request);

        log.info("付款状态已更新: requestId={}, status={}", requestId, status);
    }
}
```

---

## 4. 实战案例：菜鸟网络的运费结算

### 4.1 业务背景

菜鸟网络连接上百家承运商,每月处理数亿运费账单,需要：
- 自动生成账单
- 快速核对差异
- 及时完成结算

### 4.2 技术方案

**账单生成**：
- 定时任务每月自动生成
- 分布式任务调度(xxl-job)
- 异步处理,提高性能

**对账优化**：
- AI识别异常订单
- 自动化差异分析
- 可视化对账界面

**结算加速**：
- 与ERP系统无缝对接
- 自动推送付款申请
- 电子化审批流程

### 4.3 优化成果

- **效率提升**：账单生成时间从2天缩短至2小时
- **准确率提升**：差错率从5%降至0.5%
- **成本降低**：人工成本降低60%

---

## 5. 总结

本文详细讲解了TMS运费管理的完整方案,从计费规则设计到自动结算系统,为企业提供了成本控制和财务管理的利器。

**核心要点**：

1. **运费计算规则**：
   - 重量计费: 首重续重、阶梯定价
   - 体积计费: 体积重量换算
   - 距离计费: 按公里数、分段定价
   - 时效加价: 标准/快速/极速
   - 特殊货物加价: 易碎/贵重/危险

2. **运费模板管理**：
   - 模板分类: 运输方式、服务区域、客户类型
   - 模板配置: 计费参数、生效规则
   - 模板匹配: 精确匹配、省级匹配、全国通用

3. **自动结算系统**：
   - 账单生成: 定时任务、账单明细
   - 对账流程: 差异处理、双方确认
   - 财务结算: 付款申请、ERP对接

TMS前5篇基础文章至此全部完成!在下一个系列中,我们将探讨库存管理系统,敬请期待！

---

## 参考资料

- 菜鸟网络技术博客
- 《财务管理》教材
- 《运筹学》教材
- 阿里云ERP对接方案
