---
title: "供应链分布式事务：2PC、TCC、Saga模式详解"
date: 2025-11-22T19:00:00+08:00
draft: false
tags: ["分布式事务", "2PC", "TCC", "Saga", "Seata"]
categories: ["供应链系统"]
description: "深入讲解供应链场景下的分布式事务解决方案。从2PC到TCC，从Saga到Seata框架，全面掌握分布式事务的核心技术。"
weight: 5
---

## 引言

分布式事务是供应链集成的难点，需要保证跨系统操作的一致性。本文将探讨分布式事务的解决方案。

---

## 1. 分布式事务场景

### 1.1 下单扣库存

**场景**：
```
OMS创建订单 + 库存中心扣库存

要求：要么都成功，要么都失败
```

### 1.2 退款退库存

**场景**：
```
OMS退款 + 库存中心加库存

要求：数据一致
```

---

## 2. 2PC（两阶段提交）

### 2.1 原理

**准备阶段**：
```
协调者 → 询问各参与者是否可以提交
参与者 → 执行事务并锁定资源，返回准备就绪
```

**提交阶段**：
```
协调者 → 发起提交/回滚
参与者 → 提交/回滚事务并释放资源
```

### 2.2 优缺点

**优点**：
- 强一致性
- 事务隔离

**缺点**：
- 性能差
- 同步阻塞
- 单点故障

**适用场景**：
- 对一致性要求极高
- 并发量不大

---

## 3. TCC（Try-Confirm-Cancel）

### 3.1 原理

**Try阶段**：
- 资源预留
- 业务检查

**Confirm阶段**：
- 确认提交
- 完成业务

**Cancel阶段**：
- 回滚操作
- 释放资源

### 3.2 实现示例

```java
@TccTransaction
public class OrderTccService {

    @Autowired
    private InventoryService inventoryService;

    /**
     * Try: 预占库存
     */
    @Try
    public boolean createOrder(Order order) {
        // 1. 创建订单（状态：待确认）
        order.setStatus("PENDING");
        orderMapper.insert(order);

        // 2. 预占库存
        boolean reserved = inventoryService.reserve(
            order.getSku(),
            order.getQuantity()
        );

        if (!reserved) {
            throw new BusinessException("库存不足");
        }

        return true;
    }

    /**
     * Confirm: 确认订单，扣减库存
     */
    @Confirm
    public void confirmCreateOrder(Order order) {
        // 1. 确认订单
        order.setStatus("CONFIRMED");
        orderMapper.updateById(order);

        // 2. 扣减库存
        inventoryService.deduct(order.getSku(), order.getQuantity());
    }

    /**
     * Cancel: 取消订单，释放库存
     */
    @Cancel
    public void cancelCreateOrder(Order order) {
        // 1. 取消订单
        order.setStatus("CANCELLED");
        orderMapper.updateById(order);

        // 2. 释放库存
        inventoryService.release(order.getSku(), order.getQuantity());
    }
}
```

### 3.3 优缺点

**优点**：
- 性能好
- 解耦
- 不长期锁定资源

**缺点**：
- 业务侵入性强
- 需要实现三个接口

**适用场景**：
- 对性能要求高
- 可接受业务改造

---

## 4. Saga模式

### 4.1 原理

**长事务拆分**：
```
T1 → T2 → T3 → T4

如果T3失败：
执行C2 → C1（补偿操作）
```

### 4.2 实现示例

```java
@Service
public class OrderSagaService {

    public void createOrderSaga(Order order) {
        SagaExecution saga = SagaExecution.builder()
            .addStep(
                // T1: 创建订单
                () -> orderService.create(order),
                // C1: 删除订单
                () -> orderService.delete(order.getOrderNo())
            )
            .addStep(
                // T2: 预占库存
                () -> inventoryService.reserve(order.getSku(), order.getQuantity()),
                // C2: 释放库存
                () -> inventoryService.release(order.getSku(), order.getQuantity())
            )
            .addStep(
                // T3: 推送WMS
                () -> wmsService.pushOutbound(order),
                // C3: 取消出库
                () -> wmsService.cancelOutbound(order.getOrderNo())
            )
            .build();

        saga.execute();
    }
}
```

### 4.3 优缺点

**优点**：
- 适用于长流程
- 灵活性高

**缺点**：
- 最终一致性
- 补偿逻辑复杂

---

## 5. Seata框架实战

### 5.1 AT模式（自动补偿）

```java
@GlobalTransactional
public void createOrder(Order order) {
    // 1. 创建订单
    orderService.create(order);

    // 2. 扣减库存（Seata自动生成undo_log）
    inventoryService.deduct(order.getSku(), order.getQuantity());

    // 3. 扣减余额
    accountService.deduct(order.getUserId(), order.getTotalAmount());
}
```

### 5.2 TCC模式

```java
@LocalTCC
public interface InventoryTccService {

    @TwoPhaseBusinessAction(name = "reserve", commitMethod = "confirm", rollbackMethod = "cancel")
    boolean reserve(@BusinessActionContextParameter(paramName = "sku") String sku,
                   @BusinessActionContextParameter(paramName = "quantity") int quantity);

    boolean confirm(BusinessActionContext context);

    boolean cancel(BusinessActionContext context);
}
```

---

## 6. 实战案例：美团外卖的分布式事务

**场景**：
- 下单场景：TCC模式
- 退款场景：Saga模式

**技术栈**：
- Seata
- RocketMQ
- Redis

**成果**：
- 一致性：99.99%
- 性能：QPS > 10000

---

## 7. 总结

分布式事务是供应链集成的核心难点，需要根据场景选择合适的方案。

**核心要点**：

1. **2PC**：强一致性，性能差
2. **TCC**：性能好，业务侵入强
3. **Saga**：适用长流程，最终一致性
4. **Seata**：开箱即用的分布式事务框架

供应链集成专题的5篇基础文章至此全部完成！

---

## 参考资料

- Seata官方文档
- 《分布式事务实战》
- 美团技术博客
