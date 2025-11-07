---
title: 分布式事务：从ACID到BASE的演进
date: 2025-11-03T10:00:00+08:00
draft: false
tags:
  - 分布式事务
  - 微服务
  - Seata
  - TCC
  - Saga
  - 最终一致性
  - Java
categories:
  - 技术
description: 从第一性原理出发，深度剖析分布式事务的本质。理解CAP定理，掌握2PC、TCC、Saga、本地消息表等分布式事务解决方案的原理与选型。
series:
  - Java微服务架构第一性原理
weight: 4
---

## 引子：一次支付失败引发的数据不一致

2021年某电商平台出现严重Bug：用户支付成功，但订单状态未更新，导致重复支付。

**故障流程**：
```
1. 订单服务：创建订单（成功）
2. 库存服务：扣减库存（成功）
3. 支付服务：调用支付（成功）
4. 订单服务：更新订单状态（失败，网络超时）

结果：支付成功，但订单状态仍为"未支付"，用户再次支付
```

**核心问题**：微服务架构下，如何保证多个服务的数据一致性？

---

## 一、事务的本质：ACID四大特性

### 1.1 本地事务（单体架构）

**ACID特性**：
1. **原子性（Atomicity）**：要么都成功，要么都失败
2. **一致性（Consistency）**：数据始终处于一致状态
3. **隔离性（Isolation）**：并发事务互不干扰
4. **持久性（Durability）**：提交后永久保存

**示例**：

```java
@Transactional
public void createOrder(OrderRequest request) {
    // 1. 创建订单
    Order order = new Order();
    orderRepository.save(order);

    // 2. 扣减库存
    Inventory inventory = inventoryRepository.findByProductId(request.getProductId());
    inventory.setStock(inventory.getStock() - request.getQuantity());
    inventoryRepository.save(inventory);

    // 3. 创建支付记录
    Payment payment = new Payment();
    paymentRepository.save(payment);

    // 如果任何一步失败，全部回滚
}
```

### 1.2 分布式事务的困境

**微服务架构下**：

```
订单服务 → Order_DB
库存服务 → Inventory_DB
支付服务 → Payment_DB

问题：三个独立的数据库，无法用本地事务保证一致性
```

---

## 二、CAP定理与BASE理论

### 2.1 CAP定理

**CAP定理**指出，分布式系统最多只能同时满足以下三项中的两项：

1. **一致性（Consistency）**：所有节点同时看到相同的数据
2. **可用性（Availability）**：每个请求都能得到响应（成功或失败）
3. **分区容错性（Partition Tolerance）**：系统在网络分区时仍能继续工作

**为什么不能同时满足？**

```
场景：网络分区发生

选择CP（一致性+分区容错）：
- 节点A和节点B失去联系
- 为了保证一致性，拒绝服务（牺牲可用性）

选择AP（可用性+分区容错）：
- 节点A和节点B失去联系
- 继续提供服务，但数据可能不一致（牺牲一致性）
```

### 2.2 BASE理论

**BASE理论**是对CAP的延伸，为了可用性而牺牲强一致性：

1. **基本可用（Basically Available）**：允许损失部分可用性
2. **软状态（Soft State）**：允许系统存在中间状态
3. **最终一致性（Eventually Consistent）**：经过一段时间后，数据最终一致

**核心思想**：从强一致性转向最终一致性

---

## 三、两阶段提交（2PC）

### 3.1 2PC的流程

**阶段1：准备阶段（Prepare）**
```
协调者 → 参与者A：准备提交
       → 参与者B：准备提交
       → 参与者C：准备提交

参与者执行事务，但不提交，返回YES/NO
```

**阶段2：提交阶段（Commit）**
```
如果所有参与者返回YES：
  协调者 → 所有参与者：提交事务

如果任何参与者返回NO：
  协调者 → 所有参与者：回滚事务
```

### 3.2 2PC的问题

1. **同步阻塞**：参与者在等待协调者指令期间一直阻塞
2. **单点故障**：协调者挂了，整个系统停止
3. **数据不一致**：协调者发送提交指令时崩溃，部分参与者收到，部分没收到

**结论**：2PC在互联网场景下不适用（高延迟、低可用）

---

## 四、TCC补偿事务

### 4.1 TCC的三个阶段

1. **Try**：尝试执行，预留资源
2. **Confirm**：确认执行，使用预留资源
3. **Cancel**：取消执行，释放预留资源

### 4.2 TCC示例：订单支付

```java
/**
 * 账户服务：TCC实现
 */
@Service
public class AccountTccService {

    /**
     * Try：冻结金额
     */
    @TccTry
    public boolean tryDeduct(String accountNo, BigDecimal amount) {
        Account account = accountRepository.findByAccountNo(accountNo);

        // 检查余额
        if (account.getBalance().compareTo(amount) < 0) {
            return false;
        }

        // 冻结金额（不扣减余额）
        account.setFrozenAmount(account.getFrozenAmount().add(amount));
        accountRepository.save(account);

        return true;
    }

    /**
     * Confirm：确认扣款
     */
    @TccConfirm
    public void confirmDeduct(String accountNo, BigDecimal amount) {
        Account account = accountRepository.findByAccountNo(accountNo);

        // 扣减余额
        account.setBalance(account.getBalance().subtract(amount));
        // 解冻金额
        account.setFrozenAmount(account.getFrozenAmount().subtract(amount));
        accountRepository.save(account);
    }

    /**
     * Cancel：取消扣款
     */
    @TccCancel
    public void cancelDeduct(String accountNo, BigDecimal amount) {
        Account account = accountRepository.findByAccountNo(accountNo);

        // 解冻金额
        account.setFrozenAmount(account.getFrozenAmount().subtract(amount));
        accountRepository.save(account);
    }
}
```

### 4.3 TCC的优缺点

**优势**：
- ✅ 性能较好（不锁资源）
- ✅ 一致性强（最终强一致）

**劣势**：
- ❌ 代码侵入性强（需要实现Try、Confirm、Cancel）
- ❌ 业务复杂度高（需要设计补偿逻辑）

---

## 五、Saga长事务模式

### 5.1 Saga的两种编排方式

**1. 编排模式（Orchestration）**：由中心协调器控制

```
订单服务（协调器）
  ↓ 1. 创建订单
订单服务
  ↓ 2. 扣减库存
库存服务
  ↓ 3. 调用支付
支付服务
  ↓ 4. 更新订单状态
订单服务

失败：协调器按相反顺序执行补偿
```

**2. 编舞模式（Choreography）**：通过事件驱动

```
订单服务 → 发布"订单已创建"事件
库存服务 → 监听事件 → 扣减库存 → 发布"库存已扣减"事件
支付服务 → 监听事件 → 调用支付 → 发布"支付成功"事件
订单服务 → 监听事件 → 更新订单状态

失败：发布补偿事件
```

### 5.2 Saga示例：编排模式

```java
/**
 * 订单Saga编排器
 */
@Service
public class OrderSagaOrchestrator {

    @Autowired
    private OrderService orderService;
    @Autowired
    private InventoryService inventoryService;
    @Autowired
    private PaymentService paymentService;

    public Order createOrder(OrderRequest request) {
        Order order = null;
        boolean inventoryDeducted = false;
        boolean paymentSuccess = false;

        try {
            // Step 1: 创建订单
            order = orderService.createOrder(request);

            // Step 2: 扣减库存
            inventoryService.deduct(request.getProductId(), request.getQuantity());
            inventoryDeducted = true;

            // Step 3: 调用支付
            paymentService.pay(order.getOrderNo(), order.getAmount());
            paymentSuccess = true;

            // Step 4: 更新订单状态
            orderService.updateStatus(order.getOrderNo(), OrderStatus.PAID);

            return order;

        } catch (Exception e) {
            // 补偿操作（按相反顺序）
            if (paymentSuccess) {
                paymentService.refund(order.getOrderNo());
            }
            if (inventoryDeducted) {
                inventoryService.increase(request.getProductId(), request.getQuantity());
            }
            if (order != null) {
                orderService.cancel(order.getOrderNo());
            }
            throw e;
        }
    }
}
```

### 5.3 Saga vs TCC

| 维度 | TCC | Saga |
|------|-----|------|
| **一致性** | 强一致 | 最终一致 |
| **性能** | 较好 | 好 |
| **复杂度** | 高 | 中 |
| **适用场景** | 短事务 | 长事务 |

---

## 六、本地消息表（最终一致性）

### 6.1 本地消息表的原理

```
订单服务：
1. 开启本地事务
2. 创建订单
3. 插入消息表（待发送）
4. 提交事务

5. 定时任务扫描消息表
6. 发送消息到MQ
7. 更新消息状态（已发送）

库存服务：
8. 监听MQ消息
9. 扣减库存
10. 返回ACK
```

### 6.2 代码实现

```java
/**
 * 订单服务：本地消息表
 */
@Service
public class OrderService {

    @Autowired
    private OrderRepository orderRepository;
    @Autowired
    private LocalMessageRepository messageRepository;

    /**
     * 创建订单（本地事务）
     */
    @Transactional
    public Order createOrder(OrderRequest request) {
        // 1. 创建订单
        Order order = new Order();
        orderRepository.save(order);

        // 2. 插入本地消息表
        LocalMessage message = LocalMessage.builder()
                .messageId(UUID.randomUUID().toString())
                .topic("ORDER_CREATED")
                .content(JSON.toJSONString(order))
                .status(MessageStatus.PENDING)
                .build();
        messageRepository.save(message);

        return order;
    }
}

/**
 * 定时任务：发送本地消息
 */
@Component
public class LocalMessageSender {

    @Autowired
    private LocalMessageRepository messageRepository;
    @Autowired
    private RocketMQTemplate rocketMQTemplate;

    @Scheduled(fixedDelay = 1000)
    public void sendMessages() {
        // 查询待发送消息
        List<LocalMessage> messages = messageRepository.findByStatus(MessageStatus.PENDING);

        for (LocalMessage message : messages) {
            try {
                // 发送到MQ
                rocketMQTemplate.syncSend(message.getTopic(), message.getContent());

                // 更新状态
                message.setStatus(MessageStatus.SENT);
                messageRepository.save(message);

            } catch (Exception e) {
                log.error("发送消息失败: {}", e.getMessage());
            }
        }
    }
}
```

---

## 七、Seata分布式事务框架

### 7.1 Seata的四种模式

1. **AT模式**：自动补偿（基于SQL解析）
2. **TCC模式**：手动补偿（需要实现Try、Confirm、Cancel）
3. **Saga模式**：长事务（状态机编排）
4. **XA模式**：强一致性（基于XA协议）

### 7.2 AT模式示例

```java
/**
 * 订单服务：Seata AT模式
 */
@Service
public class OrderService {

    @Autowired
    private OrderRepository orderRepository;
    @Autowired
    private InventoryServiceClient inventoryServiceClient;
    @Autowired
    private PaymentServiceClient paymentServiceClient;

    /**
     * 创建订单（分布式事务）
     */
    @GlobalTransactional(timeoutMills = 60000, name = "create-order")
    public Order createOrder(OrderRequest request) {
        // 1. 创建订单（本地事务）
        Order order = new Order();
        orderRepository.save(order);

        // 2. 扣减库存（远程调用，Seata自动管理分支事务）
        inventoryServiceClient.deduct(request.getProductId(), request.getQuantity());

        // 3. 调用支付（远程调用，Seata自动管理分支事务）
        paymentServiceClient.pay(order.getOrderNo(), order.getAmount());

        // 4. 更新订单状态
        order.setStatus(OrderStatus.PAID);
        orderRepository.save(order);

        return order;
        // 如果任何一步失败，Seata自动回滚所有分支事务
    }
}
```

### 7.3 配置Seata

```yaml
# application.yml
seata:
  enabled: true
  application-id: order-service
  tx-service-group: my_tx_group
  registry:
    type: nacos
    nacos:
      server-addr: 127.0.0.1:8848
  config:
    type: nacos
    nacos:
      server-addr: 127.0.0.1:8848
```

---

## 八、分布式事务的选型策略

| 场景 | 推荐方案 | 理由 |
|------|---------|------|
| 强一致性要求 | Seata XA模式 | 基于XA协议，保证强一致 |
| 短事务 | Seata AT模式、TCC | 性能好，实现简单 |
| 长事务 | Saga | 支持长事务，补偿灵活 |
| 高并发 | 本地消息表、MQ事务消息 | 异步处理，性能最好 |
| 允许最终一致 | 本地消息表 | 实现简单，成本低 |

**核心原则**：
1. 优先使用**最终一致性**方案（性能好、成本低）
2. 业务允许的情况下，使用**Saga模式**（长事务）
3. 必须强一致时，使用**TCC**或**Seata AT**
4. 尽量避免**2PC**和**XA**（性能差、可用性低）

---

## 九、总结

### 核心观点

1. **分布式事务的本质**：CAP定理导致无法同时满足一致性和可用性
2. **从ACID到BASE**：从强一致性转向最终一致性
3. **四种主流方案**：2PC（不推荐）、TCC（短事务）、Saga（长事务）、本地消息表（最终一致）
4. **Seata框架**：提供AT、TCC、Saga、XA四种模式

### 选型建议

**优先级**：
1. 最终一致性方案（本地消息表、MQ事务消息）
2. Saga模式（长事务）
3. TCC模式（短事务、强一致）
4. Seata AT模式（自动补偿）
5. 2PC/XA（不推荐，除非必须）

---

**参考资料**：
1. 《分布式事务实战》- 李艳鹏
2. Seata官方文档
3. 《微服务架构设计模式》- Chris Richardson

**最后更新时间**：2025-11-03
