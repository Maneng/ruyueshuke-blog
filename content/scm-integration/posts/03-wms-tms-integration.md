---
title: "WMS-TMS集成：从出库到配送的高效协同"
date: 2025-11-22T17:00:00+08:00
draft: false
tags: ["WMS", "TMS", "系统集成", "物流协同"]
categories: ["供应链系统"]
description: "深入讲解WMS与TMS的集成方案。从发货信息推送到签收确认回调，从运费结算到异常处理，全面掌握WMS-TMS集成的核心技术。"
weight: 3
---

## 引言

WMS与TMS的集成是仓储与运输协同的关键，直接影响配送效率和客户体验。本文将探讨WMS-TMS集成的技术方案。

---

## 1. 集成场景

### 1.1 发货场景

```
WMS出库完成 → 推送发货信息到TMS → TMS创建运单 → 承运商揽货
```

### 1.2 签收场景

```
TMS配送完成 → 推送签收信息到WMS → WMS更新出库单状态
```

---

## 2. 接口设计

### 2.1 发货信息推送

**请求体**：
```json
{
  "orderNo": "OMS202511220001",
  "waybillNo": "SF1234567890",
  "shipperAddress": "北京市大兴区XX仓库",
  "consigneeAddress": "北京市朝阳区XX街道XX号",
  "consignee": {
    "name": "张三",
    "phone": "13800138000"
  },
  "cargoInfo": {
    "weight": 5.0,
    "volume": 0.02,
    "quantity": 2,
    "value": 198.00
  },
  "timeRequirement": "STANDARD"
}
```

### 2.2 配送状态回调

```json
{
  "waybillNo": "SF1234567890",
  "status": "DELIVERED",
  "deliveredTime": "2025-11-23T15:00:00",
  "signer": "张三",
  "signImage": "https://xxx.com/sign.jpg"
}
```

---

## 3. 运费结算

### 3.1 运费记录

```java
@Service
public class FreightRecordService {

    public void recordFreight(String waybillNo, BigDecimal freight) {
        FreightRecord record = new FreightRecord();
        record.setWaybillNo(waybillNo);
        record.setFreight(freight);
        record.setStatus("PENDING");
        freightRecordMapper.insert(record);
    }
}
```

### 3.2 定期对账

```java
@Component
public class FreightReconciliationTask {

    @Scheduled(cron = "0 0 2 1 * ?")  // 每月1日凌晨2点
    public void reconcile() {
        LocalDate lastMonth = LocalDate.now().minusMonths(1);

        List<FreightRecord> records = freightRecordMapper
            .selectByMonth(lastMonth);

        // 生成对账单
        FreightBill bill = new FreightBill();
        bill.setBillNo("BILL" + lastMonth.format(DateTimeFormatter.ofPattern("yyyyMM")));
        bill.setRecords(records);
        bill.setTotalFreight(records.stream()
            .map(FreightRecord::getFreight)
            .reduce(BigDecimal.ZERO, BigDecimal::add)
        );

        freightBillService.create(bill);
    }
}
```

---

## 4. 异常处理

### 4.1 拒收处理

```java
public void handleReject(String waybillNo, String reason) {
    // 1. 更新运单状态
    Waybill waybill = waybillMapper.selectByNo(waybillNo);
    waybill.setStatus("REJECTED");
    waybill.setRejectReason(reason);
    waybillMapper.updateById(waybill);

    // 2. 通知WMS创建退货入库单
    wmsService.createReturnInbound(waybillNo);

    // 3. 通知OMS更新订单状态
    omsService.updateOrderStatus(waybill.getOrderNo(), "REJECTED");
}
```

---

## 5. 实战案例：顺丰的WMS-TMS集成

**技术方案**：
- 自动分拣系统
- 智能路由引擎
- 实时追踪平台

**成果**：
- 分拣效率：10万件/小时
- 准时率：99%+
- 全程可追溯

---

## 6. 总结

WMS-TMS集成是仓储与运输协同的关键，需要设计完善的接口和结算机制。

**核心要点**：

1. **接口设计**：发货推送、状态回调
2. **运费结算**：运费记录、定期对账
3. **异常处理**：拒收、破损、理赔

下一篇将探讨库存数据实时同步方案，敬请期待！
