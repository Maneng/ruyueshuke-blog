---
title: "RocketMQ云原生05：EventBridge 事件总线 - 事件驱动架构实践"
date: 2025-11-15T19:00:00+08:00
draft: false
tags: ["RocketMQ", "EventBridge", "事件驱动", "微服务"]
categories: ["技术"]
description: "使用 EventBridge 构建事件驱动架构，解耦微服务系统"
series: ["RocketMQ从入门到精通"]
weight: 43
stage: 5
stageTitle: "云原生演进篇"
---

## 引言：事件驱动架构的演进

**传统点对点模式**：
```
订单服务 ──────> 库存服务
订单服务 ──────> 积分服务
订单服务 ──────> 通知服务
订单服务 ──────> 物流服务

问题：紧耦合，订单服务需要知道所有下游服务
```

**EventBridge 事件总线模式**：
```
订单服务 ──> EventBridge ──> 库存服务
                │          ──> 积分服务
                │          ──> 通知服务
                └──────────> 物流服务

优势：解耦，订单服务只需发布事件，无需关心谁消费
```

**本文目标**：
- 理解事件驱动架构核心理念
- 掌握 EventBridge 使用方法
- 实现事件路由和过滤
- 构建完整的事件驱动系统

---

## 一、EventBridge 核心概念

### 1.1 什么是 EventBridge？

**定义**：事件总线（Event Bus），用于接收、路由、分发事件的中心化服务。

**核心组件**：
```
┌─────────────────────────────────────────────────┐
│              EventBridge                        │
│                                                 │
│  ┌────────┐    ┌─────────┐    ┌──────────┐    │
│  │ Event  │───>│ Event   │───>│  Rule    │    │
│  │ Source │    │  Bus    │    │ (路由规则)│    │
│  └────────┘    └─────────┘    └────┬─────┘    │
│                                     │          │
│                              ┌──────▼──────┐   │
│                              │   Target    │   │
│                              │  (目标服务)  │   │
│                              └─────────────┘   │
└─────────────────────────────────────────────────┘
```

---

### 1.2 核心概念

| 概念 | 说明 | 示例 |
|------|------|------|
| **Event** | 事件 | 订单创建事件 |
| **Event Source** | 事件源 | 订单服务 |
| **Event Bus** | 事件总线 | 中心化的事件分发器 |
| **Rule** | 路由规则 | 订单金额 > 1000 的事件 |
| **Target** | 目标 | 库存服务、积分服务 |

---

## 二、阿里云 EventBridge

### 2.1 快速开始

**1. 创建事件总线**
```
控制台 → 事件总线 EventBridge → 创建事件总线
→ 名称：order-event-bus
→ 描述：订单事件总线
→ 创建
```

**2. 创建事件源**
```
事件总线详情 → 事件源 → 创建事件源
→ 名称：order-service-source
→ 类型：自定义应用
→ 创建
```

**3. 创建事件规则**
```
事件总线详情 → 事件规则 → 创建规则
→ 名称：high-value-order-rule
→ 事件模式：
{
  "source": ["order-service"],
  "type": ["OrderCreated"],
  "data": {
    "amount": [{
      "numeric": [">", 1000]
    }]
  }
}
→ 目标：RocketMQ Topic
→ 创建
```

---

### 2.2 Java SDK 使用

**Maven 依赖**：
```xml
<dependency>
    <groupId>com.aliyun</groupId>
    <artifactId>eventbridge-sdk</artifactId>
    <version>1.3.10</version>
</dependency>
```

**发布事件**：
```java
import com.aliyun.eventbridge.EventBridgeClient;
import com.aliyun.eventbridge.models.*;

public class EventPublisher {

    public static void main(String[] args) {
        // 1. 创建客户端
        Config config = new Config();
        config.setAccessKeyId("YOUR_ACCESS_KEY");
        config.setAccessKeySecret("YOUR_SECRET_KEY");
        config.setEndpoint("eventbridge.cn-hangzhou.aliyuncs.com");

        EventBridgeClient client = new EventBridgeClient(config);

        // 2. 构建事件
        CloudEvent event = new CloudEvent();
        event.setId(UUID.randomUUID().toString());
        event.setSource("order-service");
        event.setType("OrderCreated");
        event.setSpecversion("1.0");
        event.setDatacontenttype("application/json");

        // 事件数据
        Map<String, Object> data = new HashMap<>();
        data.put("orderId", "ORDER_12345");
        data.put("userId", "USER_001");
        data.put("amount", 1500.0);
        data.put("createTime", System.currentTimeMillis());
        event.setData(JSON.toJSONString(data).getBytes());

        // 3. 发布事件
        PutEventsRequest request = new PutEventsRequest();
        request.setEventBusName("order-event-bus");
        request.setEvents(Arrays.asList(event));

        PutEventsResponse response = client.putEvents(request);
        System.out.println("事件发布成功：" + response.getRequestId());
    }
}
```

---

## 三、事件路由规则

### 3.1 基于内容的路由

**场景1：按事件类型路由**
```json
{
  "source": ["order-service"],
  "type": ["OrderCreated"]
}
```
→ 路由到：库存服务、积分服务

---

**场景2：按金额路由**
```json
{
  "source": ["order-service"],
  "type": ["OrderCreated"],
  "data": {
    "amount": [{
      "numeric": [">", 1000]
    }]
  }
}
```
→ 路由到：VIP 服务通道

---

**场景3：组合条件**
```json
{
  "source": ["order-service"],
  "type": ["OrderCreated"],
  "data": {
    "amount": [{
      "numeric": [">", 1000]
    }],
    "userLevel": ["VIP", "SVIP"]
  }
}
```
→ 路由到：VIP 运营团队

---

### 3.2 事件转换

**场景：事件数据转换**
```json
// 原始事件
{
  "orderId": "ORDER_12345",
  "userId": "USER_001",
  "amount": 1500.0
}

// 转换后
{
  "order_no": "ORDER_12345",
  "user_id": "USER_001",
  "total_amount": 1500.0,
  "currency": "CNY"
}
```

**配置转换规则**：
```
事件规则 → 目标配置 → 数据转换
→ 使用模板：
{
  "order_no": "$.orderId",
  "user_id": "$.userId",
  "total_amount": "$.amount",
  "currency": "CNY"
}
```

---

## 四、实战案例

### 4.1 电商订单事件驱动

**架构**：
```
订单服务 ──> EventBridge
              │
              ├──> 库存服务（扣减库存）
              ├──> 积分服务（发放积分）
              ├──> 通知服务（发送通知）
              └──> 数据分析（实时报表）
```

**1. 订单服务发布事件**
```java
@Service
public class OrderService {

    @Autowired
    private EventBridgeClient eventBridgeClient;

    public void createOrder(Order order) {
        // 1. 创建订单
        orderRepository.save(order);

        // 2. 发布订单创建事件
        CloudEvent event = new CloudEvent();
        event.setId(UUID.randomUUID().toString());
        event.setSource("order-service");
        event.setType("OrderCreated");
        event.setSpecversion("1.0");

        Map<String, Object> data = new HashMap<>();
        data.put("orderId", order.getId());
        data.put("userId", order.getUserId());
        data.put("amount", order.getAmount());
        data.put("items", order.getItems());
        event.setData(JSON.toJSONString(data).getBytes());

        PutEventsRequest request = new PutEventsRequest();
        request.setEventBusName("order-event-bus");
        request.setEvents(Arrays.asList(event));

        eventBridgeClient.putEvents(request);

        log.info("订单创建事件已发布，orderId={}", order.getId());
    }
}
```

**2. 库存服务消费事件**
```java
@RocketMQMessageListener(
    topic = "order-created-topic",
    consumerGroup = "inventory-service-group"
)
public class InventoryEventHandler implements RocketMQListener<String> {

    @Override
    public void onMessage(String message) {
        CloudEvent event = JSON.parseObject(message, CloudEvent.class);
        Map<String, Object> data = JSON.parseObject(
            new String(event.getData()),
            Map.class
        );

        String orderId = (String) data.get("orderId");
        List<OrderItem> items = (List<OrderItem>) data.get("items");

        // 扣减库存
        for (OrderItem item : items) {
            inventoryService.reduceStock(item.getProductId(), item.getQuantity());
        }

        log.info("库存扣减完成，orderId={}", orderId);
    }
}
```

**3. 积分服务消费事件**
```java
@RocketMQMessageListener(
    topic = "order-created-topic",
    consumerGroup = "points-service-group"
)
public class PointsEventHandler implements RocketMQListener<String> {

    @Override
    public void onMessage(String message) {
        CloudEvent event = JSON.parseObject(message, CloudEvent.class);
        Map<String, Object> data = JSON.parseObject(
            new String(event.getData()),
            Map.class
        );

        String userId = (String) data.get("userId");
        Double amount = (Double) data.get("amount");

        // 计算积分（订单金额 × 0.01）
        int points = (int) (amount * 0.01);
        pointsService.addPoints(userId, points);

        log.info("积分发放完成，userId={}, points={}", userId, points);
    }
}
```

---

### 4.2 多事件编排

**场景：订单完整生命周期**
```
OrderCreated      → 库存扣减、积分发放
OrderPaid         → 通知商家、物流发货
OrderShipped      → 通知用户、更新状态
OrderCompleted    → 评价提醒、优惠券发放
OrderCancelled    → 库存回滚、积分回收
```

**事件规则配置**：
```json
// 规则1：订单创建
{
  "type": ["OrderCreated"]
} → 库存服务、积分服务

// 规则2：订单支付
{
  "type": ["OrderPaid"]
} → 商家服务、物流服务

// 规则3：订单取消
{
  "type": ["OrderCancelled"]
} → 库存服务（回滚）、积分服务（回收）
```

---

## 五、最佳实践

### 5.1 事件设计原则

**1. CloudEvents 标准**
```json
{
  "specversion": "1.0",
  "id": "unique-event-id",
  "source": "order-service",
  "type": "OrderCreated",
  "datacontenttype": "application/json",
  "time": "2025-11-15T10:00:00Z",
  "data": {
    "orderId": "ORDER_12345",
    "amount": 1500.0
  }
}
```

**2. 事件命名规范**
```
格式：<资源>.<动作>
示例：
- OrderCreated
- OrderPaid
- OrderShipped
- OrderCancelled
- UserRegistered
- ProductUpdated
```

**3. 事件版本管理**
```json
{
  "type": "OrderCreated",
  "dataschemaversion": "1.0",  // 事件版本
  "data": {
    "orderId": "ORDER_12345"
  }
}
```

---

### 5.2 幂等性保证

```java
@Service
public class EventHandler {

    @Autowired
    private ProcessedEventRepository eventRepository;

    public void handleEvent(CloudEvent event) {
        String eventId = event.getId();

        // 1. 检查事件是否已处理
        if (eventRepository.exists(eventId)) {
            log.warn("事件已处理，跳过，eventId={}", eventId);
            return;
        }

        // 2. 处理事件
        try {
            processEvent(event);

            // 3. 记录已处理
            eventRepository.save(eventId);
        } catch (Exception e) {
            log.error("事件处理失败，eventId={}", eventId, e);
            throw e;
        }
    }
}
```

---

### 5.3 错误处理

**死信队列**：
```
事件规则 → 目标配置 → 失败处理
→ 最大重试次数：3
→ 死信队列：event-dlq-topic
```

**监控告警**：
```
CloudWatch / 云监控：
- 事件发布失败率
- 事件处理延迟
- 死信队列堆积量
```

---

## 六、EventBridge vs RocketMQ

| 对比项 | EventBridge | RocketMQ |
|--------|------------|----------|
| **定位** | 事件路由 | 消息队列 |
| **解耦程度** | 高（发布者无需知道订阅者） | 中（需指定 Topic） |
| **路由能力** | 强（基于内容路由） | 弱 |
| **事件转换** | 支持 | 不支持 |
| **多目标** | 一对多路由 | 需多次发送 |
| **成本** | 较高 | 较低 |

**选择建议**：
- 需要复杂路由 → EventBridge
- 简单消息传递 → RocketMQ
- 混合使用 → EventBridge 路由到 RocketMQ

---

## 七、总结

### EventBridge 核心价值

```
1. 解耦：发布者与订阅者完全解耦
2. 灵活路由：基于内容的智能路由
3. 事件转换：统一事件格式
4. 多目标：一个事件路由到多个服务
```

### 适用场景

✅ **推荐使用**：
- 微服务事件驱动
- 多系统集成
- 复杂事件路由
- Serverless 架构

❌ **不推荐使用**：
- 简单点对点消息
- 超高 TPS（> 10 万/秒）
- 对成本敏感

---

**下一篇预告**：《多语言客户端对比 - Java、Go、Python、Node.js》，探索 RocketMQ 在不同语言生态中的使用。

**本文关键词**：`EventBridge` `事件驱动` `事件路由` `微服务解耦`
