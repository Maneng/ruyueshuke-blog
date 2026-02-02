---
title: "WMS与OMS集成——打通订单履约的关键链路"
date: 2026-02-02T13:00:00+08:00
draft: false
tags: ["WMS", "OMS", "系统集成", "库存同步", "订单履约"]
categories: ["数字化转型"]
description: "WMS与OMS的集成是订单履约的关键，本文详解出库指令下发、库存同步、状态回传的完整设计方案。"
series: ["跨境电商数字化转型指南"]
weight: 22
---

## 引言：WMS与OMS的关系

**OMS是大脑，WMS是手脚**：

- OMS负责订单决策：接单、拆单、分仓
- WMS负责实物执行：拣货、打包、发货

**集成的核心目标**：
1. **指令准确传递**：OMS的出库指令准确下发到WMS
2. **库存实时同步**：WMS的实物库存实时同步到OMS
3. **状态及时回传**：WMS的执行状态及时回传OMS

---

## 一、集成架构

### 1.1 系统边界

```
┌─────────────────────────────────────────────────────────────┐
│                          OMS                                 │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐           │
│  │订单管理 │ │库存预占 │ │履约路由 │ │状态跟踪 │           │
│  └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘           │
└───────┼───────────┼───────────┼───────────┼─────────────────┘
        │           │           │           │
        │    ┌──────┴───────────┴───────────┴──────┐
        │    │           消息队列/API               │
        │    └──────┬───────────┬───────────┬──────┘
        │           │           │           │
┌───────┼───────────┼───────────┼───────────┼─────────────────┐
│       ▼           ▼           ▼           ▼                  │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐           │
│  │出库管理 │ │库存管理 │ │拣货管理 │ │发货管理 │           │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘           │
│                          WMS                                 │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 数据流向

| 数据 | 方向 | 说明 |
|-----|-----|-----|
| 出库指令 | OMS → WMS | 订单履约指令 |
| 可售库存 | WMS → OMS | 库存同步 |
| 出库状态 | WMS → OMS | 拣货、发货状态 |
| 库存变动 | WMS → OMS | 入库、盘点等 |

---

## 二、出库指令下发

### 2.1 出库单数据结构

```java
/**
 * OMS下发给WMS的出库指令
 */
public class OutboundCommand {
    private String commandId;           // 指令ID
    private String orderNo;             // OMS订单号
    private String warehouseId;         // 仓库ID

    // 收货信息
    private String consignee;           // 收货人
    private String phone;               // 电话
    private String province;            // 省
    private String city;                // 市
    private String district;            // 区
    private String address;             // 详细地址

    // 物流信息
    private String carrierCode;         // 承运商编码
    private String serviceType;         // 服务类型

    // 时效要求
    private Integer priority;           // 优先级
    private LocalDateTime deadline;     // 截止时间

    // 商品明细
    private List<OutboundItem> items;

    // 扩展信息
    private Map<String, String> extInfo;
}

public class OutboundItem {
    private String skuId;               // SKU编码
    private String skuName;             // SKU名称
    private Integer quantity;           // 数量
    private String barcode;             // 条码
}
```

### 2.2 指令下发服务

```java
@Service
public class OutboundCommandService {

    @Autowired
    private RocketMQTemplate rocketMQTemplate;

    /**
     * OMS调用：下发出库指令
     */
    public void sendOutboundCommand(OutboundCommand command) {
        // 1. 参数校验
        validateCommand(command);

        // 2. 幂等检查
        if (commandRepository.existsByCommandId(command.getCommandId())) {
            log.warn("重复指令: {}", command.getCommandId());
            return;
        }

        // 3. 保存指令记录
        OutboundCommandRecord record = new OutboundCommandRecord();
        record.setCommandId(command.getCommandId());
        record.setOrderNo(command.getOrderNo());
        record.setWarehouseId(command.getWarehouseId());
        record.setStatus(CommandStatus.SENT);
        record.setContent(JSON.toJSONString(command));
        record.setCreatedAt(LocalDateTime.now());
        commandRepository.save(record);

        // 4. 发送消息到WMS
        String topic = "WMS_OUTBOUND_COMMAND_" + command.getWarehouseId();
        rocketMQTemplate.syncSend(topic, command);

        log.info("出库指令已下发: {}", command.getCommandId());
    }
}
```

### 2.3 WMS接收处理

```java
@Service
@RocketMQMessageListener(
    topic = "WMS_OUTBOUND_COMMAND_${warehouse.id}",
    consumerGroup = "wms-outbound-consumer"
)
public class OutboundCommandConsumer implements RocketMQListener<OutboundCommand> {

    @Override
    public void onMessage(OutboundCommand command) {
        try {
            // 1. 幂等检查
            if (outboundOrderRepository.existsByOmsOrderNo(command.getOrderNo())) {
                log.warn("订单已存在: {}", command.getOrderNo());
                return;
            }

            // 2. 创建WMS出库单
            OutboundOrder order = createOutboundOrder(command);

            // 3. 校验库存
            boolean stockAvailable = checkStock(order);
            if (!stockAvailable) {
                // 库存不足，回传异常
                sendStockShortageCallback(command, order);
                return;
            }

            // 4. 锁定库存
            lockStock(order);

            // 5. 回传接收成功
            sendReceiveCallback(command.getCommandId(), "SUCCESS");

        } catch (Exception e) {
            log.error("处理出库指令失败: {}", command.getCommandId(), e);
            sendReceiveCallback(command.getCommandId(), "FAIL", e.getMessage());
        }
    }

    private OutboundOrder createOutboundOrder(OutboundCommand command) {
        OutboundOrder order = new OutboundOrder();
        order.setOutboundNo(generateOutboundNo());
        order.setOmsOrderNo(command.getOrderNo());
        order.setWarehouseId(command.getWarehouseId());
        order.setConsignee(command.getConsignee());
        order.setPhone(command.getPhone());
        order.setAddress(buildFullAddress(command));
        order.setCarrierCode(command.getCarrierCode());
        order.setPriority(command.getPriority());
        order.setDeadline(command.getDeadline());
        order.setStatus(OutboundStatus.CREATED);

        outboundOrderRepository.save(order);

        // 保存明细
        for (OutboundItem item : command.getItems()) {
            OutboundOrderItem orderItem = new OutboundOrderItem();
            orderItem.setOutboundNo(order.getOutboundNo());
            orderItem.setSkuId(item.getSkuId());
            orderItem.setQuantity(item.getQuantity());
            outboundItemRepository.save(orderItem);
        }

        return order;
    }
}
```

---

## 三、库存同步

### 3.1 库存同步策略

| 策略 | 说明 | 适用场景 |
|-----|-----|---------|
| 实时同步 | 每次变动立即同步 | 库存紧张、高并发 |
| 定时同步 | 定时批量同步 | 库存充足 |
| 增量同步 | 只同步变化部分 | 数据量大 |
| 全量同步 | 定期全量覆盖 | 数据校准 |

### 3.2 实时库存同步

```java
@Service
public class InventorySyncService {

    /**
     * 库存变动时触发同步
     */
    @EventListener
    public void onInventoryChange(InventoryChangeEvent event) {
        // 计算可售库存
        int availableQty = calculateAvailableQty(
            event.getWarehouseId(),
            event.getSkuId()
        );

        // 发送同步消息
        InventorySyncMessage message = new InventorySyncMessage();
        message.setWarehouseId(event.getWarehouseId());
        message.setSkuId(event.getSkuId());
        message.setAvailableQty(availableQty);
        message.setChangeType(event.getChangeType());
        message.setChangeQty(event.getChangeQty());
        message.setTimestamp(LocalDateTime.now());

        rocketMQTemplate.asyncSend("OMS_INVENTORY_SYNC", message, new SendCallback() {
            @Override
            public void onSuccess(SendResult sendResult) {
                log.info("库存同步成功: {} {}", event.getSkuId(), availableQty);
            }

            @Override
            public void onException(Throwable e) {
                log.error("库存同步失败: {}", event.getSkuId(), e);
                // 加入重试队列
                retrySyncQueue.add(message);
            }
        });
    }

    /**
     * 计算可售库存
     * 可售 = 实物库存 - 锁定库存 - 安全库存
     */
    private int calculateAvailableQty(String warehouseId, String skuId) {
        // 查询实物库存
        int physicalQty = inventoryRepository.sumQuantity(warehouseId, skuId);

        // 查询锁定库存
        int lockedQty = inventoryRepository.sumLockedQty(warehouseId, skuId);

        // 查询安全库存
        int safetyStock = skuService.getSafetyStock(skuId);

        return Math.max(0, physicalQty - lockedQty - safetyStock);
    }
}
```

### 3.3 OMS接收库存同步

```java
@Service
@RocketMQMessageListener(
    topic = "OMS_INVENTORY_SYNC",
    consumerGroup = "oms-inventory-consumer"
)
public class InventorySyncConsumer implements RocketMQListener<InventorySyncMessage> {

    @Override
    public void onMessage(InventorySyncMessage message) {
        // 1. 更新OMS库存
        OmsInventory inventory = omsInventoryRepository
            .findByWarehouseAndSku(message.getWarehouseId(), message.getSkuId());

        if (inventory == null) {
            inventory = new OmsInventory();
            inventory.setWarehouseId(message.getWarehouseId());
            inventory.setSkuId(message.getSkuId());
        }

        inventory.setAvailableQty(message.getAvailableQty());
        inventory.setLastSyncTime(message.getTimestamp());
        omsInventoryRepository.save(inventory);

        // 2. 更新渠道库存（如果需要）
        channelInventoryService.syncToChannels(message.getSkuId());

        // 3. 检查库存预警
        checkInventoryAlert(message);
    }
}
```

### 3.4 定时全量同步

```java
@Service
public class FullInventorySyncService {

    /**
     * 每天凌晨全量同步库存
     */
    @Scheduled(cron = "0 0 2 * * ?")
    public void fullSync() {
        log.info("开始全量库存同步");

        List<String> warehouses = warehouseService.getAllActiveWarehouses();

        for (String warehouseId : warehouses) {
            // 获取WMS所有库存
            List<InventorySummary> wmsInventories =
                wmsClient.getAllInventory(warehouseId);

            // 批量同步到OMS
            List<InventorySyncMessage> messages = wmsInventories.stream()
                .map(inv -> {
                    InventorySyncMessage msg = new InventorySyncMessage();
                    msg.setWarehouseId(warehouseId);
                    msg.setSkuId(inv.getSkuId());
                    msg.setAvailableQty(inv.getAvailableQty());
                    msg.setChangeType("FULL_SYNC");
                    return msg;
                })
                .collect(Collectors.toList());

            // 批量发送
            rocketMQTemplate.syncSend("OMS_INVENTORY_SYNC_BATCH", messages);
        }

        log.info("全量库存同步完成");
    }
}
```

---

## 四、状态回传

### 4.1 状态流转

```
OMS订单状态:  待发货 ──> 拣货中 ──> 已发货 ──> 已签收
                │         │         │         │
WMS状态回传:    │         │         │         │
                ▼         ▼         ▼         ▼
            接收成功   开始拣货   发货完成   物流回传
```

### 4.2 状态回传消息

```java
/**
 * WMS回传给OMS的状态消息
 */
public class OutboundStatusCallback {
    private String callbackId;          // 回传ID
    private String omsOrderNo;          // OMS订单号
    private String wmsOutboundNo;       // WMS出库单号
    private String status;              // 状态
    private LocalDateTime statusTime;   // 状态时间

    // 发货信息（发货状态时填写）
    private String trackingNo;          // 物流单号
    private String carrierCode;         // 承运商
    private Integer packageCount;       // 包裹数
    private BigDecimal weight;          // 重量

    // 异常信息
    private String errorCode;           // 错误码
    private String errorMessage;        // 错误信息
}
```

### 4.3 状态回传服务

```java
@Service
public class StatusCallbackService {

    /**
     * 拣货开始回传
     */
    public void callbackPickStart(OutboundOrder order) {
        OutboundStatusCallback callback = new OutboundStatusCallback();
        callback.setCallbackId(generateCallbackId());
        callback.setOmsOrderNo(order.getOmsOrderNo());
        callback.setWmsOutboundNo(order.getOutboundNo());
        callback.setStatus("PICKING");
        callback.setStatusTime(LocalDateTime.now());

        sendCallback(callback);
    }

    /**
     * 发货完成回传
     */
    public void callbackShipped(OutboundOrder order, ShipmentInfo shipment) {
        OutboundStatusCallback callback = new OutboundStatusCallback();
        callback.setCallbackId(generateCallbackId());
        callback.setOmsOrderNo(order.getOmsOrderNo());
        callback.setWmsOutboundNo(order.getOutboundNo());
        callback.setStatus("SHIPPED");
        callback.setStatusTime(LocalDateTime.now());
        callback.setTrackingNo(shipment.getTrackingNo());
        callback.setCarrierCode(shipment.getCarrierCode());
        callback.setPackageCount(shipment.getPackageCount());
        callback.setWeight(shipment.getWeight());

        sendCallback(callback);
    }

    /**
     * 异常回传
     */
    public void callbackException(OutboundOrder order, String errorCode, String errorMessage) {
        OutboundStatusCallback callback = new OutboundStatusCallback();
        callback.setCallbackId(generateCallbackId());
        callback.setOmsOrderNo(order.getOmsOrderNo());
        callback.setWmsOutboundNo(order.getOutboundNo());
        callback.setStatus("EXCEPTION");
        callback.setStatusTime(LocalDateTime.now());
        callback.setErrorCode(errorCode);
        callback.setErrorMessage(errorMessage);

        sendCallback(callback);
    }

    private void sendCallback(OutboundStatusCallback callback) {
        // 保存回传记录
        CallbackRecord record = new CallbackRecord();
        record.setCallbackId(callback.getCallbackId());
        record.setContent(JSON.toJSONString(callback));
        record.setStatus(CallbackStatus.PENDING);
        callbackRepository.save(record);

        // 发送消息
        rocketMQTemplate.asyncSend("OMS_STATUS_CALLBACK", callback, new SendCallback() {
            @Override
            public void onSuccess(SendResult sendResult) {
                record.setStatus(CallbackStatus.SUCCESS);
                callbackRepository.save(record);
            }

            @Override
            public void onException(Throwable e) {
                record.setStatus(CallbackStatus.FAIL);
                record.setErrorMessage(e.getMessage());
                callbackRepository.save(record);
                // 加入重试队列
                retryQueue.add(callback);
            }
        });
    }
}
```

### 4.4 OMS接收状态回传

```java
@Service
@RocketMQMessageListener(
    topic = "OMS_STATUS_CALLBACK",
    consumerGroup = "oms-callback-consumer"
)
public class StatusCallbackConsumer implements RocketMQListener<OutboundStatusCallback> {

    @Override
    public void onMessage(OutboundStatusCallback callback) {
        // 1. 幂等检查
        if (callbackRepository.existsByCallbackId(callback.getCallbackId())) {
            return;
        }

        // 2. 查找订单
        Order order = orderRepository.findByOrderNo(callback.getOmsOrderNo());
        if (order == null) {
            log.error("订单不存在: {}", callback.getOmsOrderNo());
            return;
        }

        // 3. 更新订单状态
        switch (callback.getStatus()) {
            case "PICKING":
                order.setStatus(OrderStatus.PICKING);
                order.setPickStartTime(callback.getStatusTime());
                break;

            case "SHIPPED":
                order.setStatus(OrderStatus.SHIPPED);
                order.setShipTime(callback.getStatusTime());
                order.setTrackingNo(callback.getTrackingNo());
                order.setCarrierCode(callback.getCarrierCode());
                // 释放库存预占
                inventoryService.releaseReservation(order.getOrderNo());
                break;

            case "EXCEPTION":
                order.setStatus(OrderStatus.EXCEPTION);
                order.setExceptionCode(callback.getErrorCode());
                order.setExceptionMessage(callback.getErrorMessage());
                // 触发异常处理流程
                exceptionHandler.handle(order, callback);
                break;
        }

        orderRepository.save(order);

        // 4. 通知下游（如通知客户）
        notifyService.notifyOrderStatusChange(order);
    }
}
```

---

## 五、异常处理

### 5.1 常见异常场景

| 异常 | 原因 | 处理方式 |
|-----|-----|---------|
| 库存不足 | WMS实际库存不够 | 重新分仓或取消 |
| 地址异常 | 地址无法配送 | 人工处理 |
| SKU不存在 | WMS没有该商品 | 检查主数据 |
| 超时未处理 | WMS未及时处理 | 催促或转仓 |

### 5.2 异常处理服务

```java
@Service
public class IntegrationExceptionHandler {

    /**
     * 处理库存不足异常
     */
    public void handleStockShortage(Order order, OutboundStatusCallback callback) {
        // 1. 尝试重新分仓
        String newWarehouse = fulfillmentRouter.findAlternativeWarehouse(order);

        if (newWarehouse != null) {
            // 取消原出库指令
            wmsClient.cancelOutbound(order.getOrderNo(), order.getWarehouseId());

            // 下发新出库指令
            order.setWarehouseId(newWarehouse);
            outboundCommandService.sendOutboundCommand(buildCommand(order));

            log.info("订单{}重新分仓到{}", order.getOrderNo(), newWarehouse);
        } else {
            // 无可用仓库，标记异常
            order.setStatus(OrderStatus.STOCK_SHORTAGE);
            orderRepository.save(order);

            // 通知客服
            alertService.notifyCustomerService(order, "库存不足，需人工处理");
        }
    }

    /**
     * 处理超时未处理
     */
    @Scheduled(fixedRate = 300000) // 每5分钟检查
    public void checkTimeoutOrders() {
        // 查找超时订单
        LocalDateTime timeout = LocalDateTime.now().minusHours(4);
        List<Order> timeoutOrders = orderRepository
            .findByStatusAndCreatedBefore(OrderStatus.PENDING_SHIP, timeout);

        for (Order order : timeoutOrders) {
            // 查询WMS状态
            OutboundOrder wmsOrder = wmsClient.getOutboundOrder(order.getOrderNo());

            if (wmsOrder == null || wmsOrder.getStatus() == OutboundStatus.CREATED) {
                // WMS未处理，发送催促
                alertService.notifyWarehouse(order.getWarehouseId(),
                    "订单" + order.getOrderNo() + "超时未处理");
            }
        }
    }
}
```

---

## 六、接口设计

### 6.1 REST API接口

```java
@RestController
@RequestMapping("/api/wms")
public class WmsIntegrationController {

    /**
     * OMS调用：下发出库指令
     */
    @PostMapping("/outbound/command")
    public Result<Void> sendOutboundCommand(@RequestBody OutboundCommand command) {
        outboundCommandService.sendOutboundCommand(command);
        return Result.success();
    }

    /**
     * OMS调用：取消出库指令
     */
    @PostMapping("/outbound/cancel")
    public Result<Void> cancelOutbound(@RequestBody CancelRequest request) {
        wmsService.cancelOutbound(request.getOrderNo(), request.getReason());
        return Result.success();
    }

    /**
     * OMS调用：查询库存
     */
    @GetMapping("/inventory")
    public Result<InventoryVO> queryInventory(
            @RequestParam String warehouseId,
            @RequestParam String skuId) {
        InventoryVO inventory = inventoryService.queryInventory(warehouseId, skuId);
        return Result.success(inventory);
    }

    /**
     * WMS调用：状态回传
     */
    @PostMapping("/callback/status")
    public Result<Void> statusCallback(@RequestBody OutboundStatusCallback callback) {
        callbackService.handleCallback(callback);
        return Result.success();
    }

    /**
     * WMS调用：库存同步
     */
    @PostMapping("/inventory/sync")
    public Result<Void> syncInventory(@RequestBody InventorySyncRequest request) {
        inventorySyncService.sync(request);
        return Result.success();
    }
}
```

### 6.2 接口幂等设计

```java
@Aspect
@Component
public class IdempotentAspect {

    @Around("@annotation(idempotent)")
    public Object checkIdempotent(ProceedingJoinPoint point, Idempotent idempotent) throws Throwable {
        // 获取幂等键
        String key = getIdempotentKey(point, idempotent);

        // 检查是否已处理
        String result = redisTemplate.opsForValue().get(key);
        if (result != null) {
            log.info("重复请求，返回缓存结果: {}", key);
            return JSON.parseObject(result, point.getSignature().getDeclaringType());
        }

        // 执行业务
        Object response = point.proceed();

        // 缓存结果
        redisTemplate.opsForValue().set(key, JSON.toJSONString(response),
            idempotent.expireSeconds(), TimeUnit.SECONDS);

        return response;
    }
}
```

---

## 七、监控与告警

### 7.1 集成监控指标

| 指标 | 说明 | 告警阈值 |
|-----|-----|---------|
| 指令下发成功率 | 成功/总数 | < 99% |
| 库存同步延迟 | 同步耗时 | > 5秒 |
| 状态回传延迟 | 回传耗时 | > 10秒 |
| 消息积压数 | 队列积压 | > 1000 |

### 7.2 监控实现

```java
@Service
public class IntegrationMonitorService {

    @Scheduled(fixedRate = 60000)
    public void monitor() {
        // 检查消息积压
        long pendingCount = messageRepository.countPending();
        if (pendingCount > 1000) {
            alertService.sendAlert("消息积压告警",
                "待处理消息数: " + pendingCount);
        }

        // 检查同步延迟
        LocalDateTime lastSync = inventorySyncRepository.getLastSyncTime();
        if (lastSync.isBefore(LocalDateTime.now().minusMinutes(5))) {
            alertService.sendAlert("库存同步延迟",
                "最后同步时间: " + lastSync);
        }

        // 检查失败率
        long totalCount = callbackRepository.countByHour();
        long failCount = callbackRepository.countFailByHour();
        double failRate = failCount * 100.0 / totalCount;
        if (failRate > 1) {
            alertService.sendAlert("回传失败率告警",
                String.format("失败率: %.2f%%", failRate));
        }
    }
}
```

---

## 八、总结

### 8.1 集成核心要点

1. **指令下发**：幂等、可靠、可追溯
2. **库存同步**：实时、准确、有兜底
3. **状态回传**：及时、完整、可重试
4. **异常处理**：自动重试、人工兜底

### 8.2 最佳实践

| 实践 | 说明 |
|-----|-----|
| 消息队列解耦 | 异步处理，削峰填谷 |
| 幂等设计 | 防止重复处理 |
| 重试机制 | 失败自动重试 |
| 监控告警 | 及时发现问题 |

---

> **系列文章导航**
>
> 本文是《跨境电商数字化转型指南》系列的第22篇
>
> - [x] 18. WMS仓储系统架构设计
> - [x] 19. WMS入库管理详解
> - [x] 20. WMS拣货策略优化
> - [x] 21. WMS库存盘点实战
> - [x] 22. WMS与OMS集成（本文）
