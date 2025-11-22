---
title: "OMS-WMS集成：从订单到出库的无缝衔接"
date: 2025-11-22T16:00:00+08:00
draft: false
tags: ["OMS", "WMS", "系统集成", "接口设计"]
categories: ["供应链系统"]
description: "详细讲解OMS与WMS的集成方案和技术实现。从接口设计到数据一致性保障，从异常处理到实战案例，全面掌握OMS-WMS集成的核心技术。"
weight: 2
---

## 引言

OMS与WMS的集成是供应链系统的核心环节，直接影响订单履约效率。本文将深入探讨OMS-WMS集成的方案设计和技术实现。

---

## 1. 集成场景

### 1.1 出库场景

**流程**：
```
1. OMS推送出库指令
   ↓
2. WMS创建出库单
   ↓
3. WMS拣货打包
   ↓
4. WMS出库确认
   ↓
5. WMS回调OMS（运单号、发货时间）
```

### 1.2 入库场景

**采购入库**：
```
采购系统 → OMS → WMS创建入库单
```

**退货入库**：
```
OMS创建退货单 → WMS验收入库
```

---

## 2. 接口设计

### 2.1 出库指令接口

**接口定义**：
```
POST /api/wms/outbound/create
Content-Type: application/json
```

**请求体**：
```json
{
  "orderNo": "OMS202511220001",
  "warehouseCode": "WH001",
  "priority": "HIGH/NORMAL/LOW",
  "timeRequirement": "STANDARD/EXPRESS",
  "items": [
    {
      "sku": "SKU001",
      "quantity": 2,
      "batchNo": "BATCH001"
    }
  ],
  "consignee": {
    "name": "张三",
    "phone": "13800138000",
    "province": "北京市",
    "city": "北京市",
    "district": "朝阳区",
    "address": "XX街道XX号"
  }
}
```

**响应体**：
```json
{
  "code": 200,
  "message": "success",
  "data": {
    "outboundNo": "WMS202511220001",
    "status": "PENDING"
  }
}
```

### 2.2 出库确认回调

**接口定义**：
```
POST /api/oms/outbound/callback
Content-Type: application/json
```

**请求体**：
```json
{
  "orderNo": "OMS202511220001",
  "outboundNo": "WMS202511220001",
  "waybillNo": "SF1234567890",
  "carrier": "顺丰速运",
  "actualItems": [
    {
      "sku": "SKU001",
      "quantity": 2,
      "batchNo": "BATCH001"
    }
  ],
  "shippedTime": "2025-11-22T10:00:00"
}
```

---

## 3. Java实现

### 3.1 OMS推送出库指令

```java
@Service
public class OutboundPushService {

    @Autowired
    private WmsApiClient wmsApiClient;

    public void pushOutbound(Order order) {
        // 构建出库指令
        OutboundRequest request = new OutboundRequest();
        request.setOrderNo(order.getOrderNo());
        request.setWarehouseCode(order.getWarehouseCode());
        request.setPriority(order.getPriority());
        request.setItems(convertItems(order.getItems()));
        request.setConsignee(order.getConsignee());

        // 调用WMS接口
        OutboundResponse response = wmsApiClient.createOutbound(request);

        if (response.isSuccess()) {
            // 更新订单状态
            order.setStatus("PUSHED_TO_WMS");
            order.setOutboundNo(response.getOutboundNo());
            orderMapper.updateById(order);

            log.info("已推送出库指令: orderNo={}, outboundNo={}",
                order.getOrderNo(), response.getOutboundNo());
        } else {
            log.error("推送出库指令失败: orderNo={}, error={}",
                order.getOrderNo(), response.getMessage());
            throw new BusinessException("推送出库指令失败");
        }
    }
}
```

### 3.2 WMS回调OMS

```java
@RestController
@RequestMapping("/api/oms/outbound")
public class OutboundCallbackController {

    @Autowired
    private OutboundCallbackService callbackService;

    @PostMapping("/callback")
    public ApiResponse callback(@RequestBody OutboundCallbackRequest request) {
        try {
            callbackService.handleCallback(request);
            return ApiResponse.success();
        } catch (Exception e) {
            log.error("处理出库回调失败", e);
            return ApiResponse.error("处理失败");
        }
    }
}

@Service
public class OutboundCallbackService {

    @Transactional
    public void handleCallback(OutboundCallbackRequest request) {
        // 1. 查询订单
        Order order = orderMapper.selectByOrderNo(request.getOrderNo());
        if (order == null) {
            throw new BusinessException("订单不存在");
        }

        // 2. 更新订单状态
        order.setStatus("SHIPPED");
        order.setWaybillNo(request.getWaybillNo());
        order.setCarrier(request.getCarrier());
        order.setShippedTime(request.getShippedTime());
        orderMapper.updateById(order);

        // 3. 扣减库存
        for (ItemDTO item : request.getActualItems()) {
            inventoryService.deduct(item.getSku(), item.getQuantity());
        }

        // 4. 推送配送信息到TMS
        tmsService.pushShipment(order);

        log.info("出库回调处理完成: orderNo={}, waybillNo={}",
            request.getOrderNo(), request.getWaybillNo());
    }
}
```

---

## 4. 数据一致性保障

### 4.1 幂等性设计

**订单号去重**：
```java
@Service
public class IdempotentService {

    @Autowired
    private RedisTemplate<String, String> redisTemplate;

    public boolean checkAndSet(String orderNo) {
        String key = "outbound:idempotent:" + orderNo;

        // 设置key，过期时间24小时
        Boolean success = redisTemplate.opsForValue()
            .setIfAbsent(key, "1", 24, TimeUnit.HOURS);

        return Boolean.TRUE.equals(success);
    }
}
```

### 4.2 重试机制

**指数退避重试**：
```java
@Component
public class OutboundRetryTask {

    @Scheduled(fixedRate = 60000)  // 每分钟
    public void retryFailedOutbound() {
        List<Order> failedOrders = orderMapper.selectFailed();

        for (Order order : failedOrders) {
            if (order.getRetryCount() >= 3) {
                // 超过最大重试次数，人工介入
                alertService.send("出库推送失败: " + order.getOrderNo());
                continue;
            }

            try {
                outboundPushService.pushOutbound(order);
                order.setRetryCount(0);
            } catch (Exception e) {
                order.setRetryCount(order.getRetryCount() + 1);
                log.error("重试推送出库失败: orderNo={}", order.getOrderNo(), e);
            }

            orderMapper.updateById(order);
        }
    }
}
```

---

## 5. 异常处理

### 5.1 WMS缺货

```java
public void handleOutOfStock(Order order, String sku) {
    // 1. 部分发货
    if (order.getAllowPartialShip()) {
        wmsService.shipAvailableItems(order);
        omsService.createBackorder(order, sku);  // 创建缺货补单
    }
    // 2. 取消订单
    else if (order.getAllowCancel()) {
        omsService.cancelOrder(order.getOrderNo());
        inventoryService.releaseReserved(order);  // 释放预占库存
    }
    // 3. 转其他仓库
    else {
        String alternativeWarehouse = findAlternativeWarehouse(sku);
        if (alternativeWarehouse != null) {
            order.setWarehouseCode(alternativeWarehouse);
            outboundPushService.pushOutbound(order);
        }
    }
}
```

---

## 6. 总结

OMS-WMS集成是订单履约的核心环节，需要设计完善的接口和异常处理机制。

**核心要点**：

1. **接口设计**：出库指令、出库回调
2. **一致性保障**：幂等性、重试机制
3. **异常处理**：缺货、超时、人工介入

下一篇文章将探讨WMS-TMS集成方案，敬请期待！
