---
title: "RocketMQ入门10：SpringBoot集成实战 - 从配置到生产级应用"
date: 2025-11-13T19:00:00+08:00
draft: false
tags: ["RocketMQ", "SpringBoot", "集成实战", "生产实践", "最佳实践"]
categories: ["技术"]
description: "通过 SpringBoot 集成 RocketMQ，构建一个完整的生产级消息系统，包含各种消息类型、错误处理、监控告警等最佳实践"
series: ["RocketMQ从入门到精通"]
weight: 10
stage: 1
stageTitle: "基础入门篇"
---

## 引言：将知识转化为实践

前面9篇，我们深入学习了 RocketMQ 的各个方面。现在，让我们通过一个完整的 SpringBoot 项目，把这些知识串联起来，构建一个真正的生产级应用。

这个项目将包含：
- 完整的项目结构
- 各种消息类型的实现
- 错误处理和重试机制
- 监控和告警
- 性能优化
- 部署方案

## 一、项目搭建

### 1.1 项目结构

```
rocketmq-springboot-demo/
├── pom.xml
├── src/main/java/com/example/rocketmq/
│   ├── RocketMQApplication.java           # 启动类
│   ├── config/
│   │   ├── RocketMQConfig.java           # RocketMQ配置
│   │   ├── ProducerConfig.java           # 生产者配置
│   │   └── ConsumerConfig.java           # 消费者配置
│   ├── producer/
│   │   ├── OrderProducer.java            # 订单消息生产者
│   │   ├── TransactionProducer.java      # 事务消息生产者
│   │   └── DelayProducer.java            # 延迟消息生产者
│   ├── consumer/
│   │   ├── OrderConsumer.java            # 订单消息消费者
│   │   ├── TransactionConsumer.java      # 事务消息消费者
│   │   └── DelayConsumer.java            # 延迟消息消费者
│   ├── message/
│   │   ├── OrderMessage.java             # 订单消息实体
│   │   └── MessageWrapper.java           # 消息包装器
│   ├── service/
│   │   ├── OrderService.java             # 订单服务
│   │   └── MessageService.java           # 消息服务
│   ├── utils/
│   │   ├── MessageBuilder.java           # 消息构建工具
│   │   └── TraceUtils.java              # 链路追踪工具
│   └── listener/
│       ├── TransactionListenerImpl.java  # 事务监听器
│       └── MessageListenerImpl.java      # 消息监听器
├── src/main/resources/
│   ├── application.yml                   # 配置文件
│   ├── application-dev.yml               # 开发环境配置
│   ├── application-prod.yml              # 生产环境配置
│   └── logback-spring.xml               # 日志配置
└── src/test/java/                       # 测试类
```

### 1.2 Maven 依赖

```xml
<!-- pom.xml -->
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0
         http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>2.7.14</version>
    </parent>

    <groupId>com.example</groupId>
    <artifactId>rocketmq-springboot-demo</artifactId>
    <version>1.0.0</version>

    <properties>
        <java.version>8</java.version>
        <rocketmq-spring.version>2.2.3</rocketmq-spring.version>
    </properties>

    <dependencies>
        <!-- Spring Boot Starter -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
        </dependency>

        <!-- RocketMQ Spring Boot Starter -->
        <dependency>
            <groupId>org.apache.rocketmq</groupId>
            <artifactId>rocketmq-spring-boot-starter</artifactId>
            <version>${rocketmq-spring.version}</version>
        </dependency>

        <!-- 数据库相关 -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-data-jpa</artifactId>
        </dependency>
        <dependency>
            <groupId>mysql</groupId>
            <artifactId>mysql-connector-java</artifactId>
            <scope>runtime</scope>
        </dependency>

        <!-- Redis -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-data-redis</artifactId>
        </dependency>

        <!-- 监控 -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-actuator</artifactId>
        </dependency>
        <dependency>
            <groupId>io.micrometer</groupId>
            <artifactId>micrometer-registry-prometheus</artifactId>
        </dependency>

        <!-- 工具类 -->
        <dependency>
            <groupId>org.projectlombok</groupId>
            <artifactId>lombok</artifactId>
        </dependency>
        <dependency>
            <groupId>com.alibaba</groupId>
            <artifactId>fastjson</artifactId>
            <version>2.0.34</version>
        </dependency>
        <dependency>
            <groupId>cn.hutool</groupId>
            <artifactId>hutool-all</artifactId>
            <version>5.8.20</version>
        </dependency>

        <!-- 测试 -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-test</artifactId>
            <scope>test</scope>
        </dependency>
    </dependencies>
</project>
```

### 1.3 配置文件

```yaml
# application.yml
spring:
  application:
    name: rocketmq-springboot-demo

# RocketMQ 配置
rocketmq:
  name-server: ${ROCKETMQ_NAMESRV:localhost:9876}
  producer:
    group: ${spring.application.name}_producer_group
    send-message-timeout: 3000
    compress-message-body-threshold: 4096
    max-message-size: 4194304
    retry-times-when-send-failed: 2
    retry-times-when-send-async-failed: 2
    retry-next-server: true

  # 自定义配置
  consumer:
    groups:
      order-consumer-group:
        topics: ORDER_TOPIC
        consumer-group: ${spring.application.name}_order_consumer
        consume-thread-max: 64
        consume-thread-min: 20
      transaction-consumer-group:
        topics: TRANSACTION_TOPIC
        consumer-group: ${spring.application.name}_transaction_consumer

# 应用配置
app:
  rocketmq:
    # 是否启用事务消息
    transaction-enabled: true
    # 是否启用消息轨迹
    trace-enabled: true
    # 消息轨迹Topic
    trace-topic: RMQ_SYS_TRACE_TOPIC
    # ACL配置
    acl-enabled: false
    access-key: ${ROCKETMQ_ACCESS_KEY:}
    secret-key: ${ROCKETMQ_SECRET_KEY:}

# 监控配置
management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus
  metrics:
    export:
      prometheus:
        enabled: true
```

## 二、核心配置类

### 2.1 RocketMQ 配置

```java
// RocketMQConfig.java
@Configuration
@EnableConfigurationProperties(RocketMQProperties.class)
@Slf4j
public class RocketMQConfig {

    @Autowired
    private RocketMQProperties rocketMQProperties;

    /**
     * 配置消息轨迹
     */
    @Bean
    @ConditionalOnProperty(prefix = "app.rocketmq", name = "trace-enabled", havingValue = "true")
    public DefaultMQProducer tracedProducer() {
        DefaultMQProducer producer = new DefaultMQProducer(
            rocketMQProperties.getProducer().getGroup(),
            true,  // 启用消息轨迹
            rocketMQProperties.getTraceTopic()
        );

        configureProducer(producer);
        return producer;
    }

    /**
     * 配置事务消息生产者
     */
    @Bean
    @ConditionalOnProperty(prefix = "app.rocketmq", name = "transaction-enabled", havingValue = "true")
    public TransactionMQProducer transactionProducer(
            @Autowired TransactionListener transactionListener) {

        TransactionMQProducer producer = new TransactionMQProducer(
            rocketMQProperties.getProducer().getGroup() + "_TX"
        );

        configureProducer(producer);

        // 设置事务监听器
        producer.setTransactionListener(transactionListener);

        // 设置事务回查线程池
        ThreadPoolExecutor executor = new ThreadPoolExecutor(
            2,
            5,
            100,
            TimeUnit.SECONDS,
            new ArrayBlockingQueue<>(2000),
            r -> {
                Thread thread = new Thread(r);
                thread.setName("transaction-check-thread");
                return thread;
            }
        );
        producer.setExecutorService(executor);

        return producer;
    }

    /**
     * 通用生产者配置
     */
    private void configureProducer(DefaultMQProducer producer) {
        producer.setNamesrvAddr(rocketMQProperties.getNameServer());
        producer.setSendMsgTimeout(rocketMQProperties.getProducer().getSendMessageTimeout());
        producer.setCompressMsgBodyOverHowmuch(
            rocketMQProperties.getProducer().getCompressMessageBodyThreshold()
        );
        producer.setMaxMessageSize(rocketMQProperties.getProducer().getMaxMessageSize());
        producer.setRetryTimesWhenSendFailed(
            rocketMQProperties.getProducer().getRetryTimesWhenSendFailed()
        );

        // 配置ACL
        if (rocketMQProperties.isAclEnabled()) {
            producer.setAccessKey(rocketMQProperties.getAccessKey());
            producer.setSecretKey(rocketMQProperties.getSecretKey());
        }
    }

    /**
     * 消息发送模板
     */
    @Bean
    public RocketMQTemplate rocketMQTemplate(RocketMQMessageConverter converter) {
        RocketMQTemplate template = new RocketMQTemplate();
        template.setMessageConverter(converter);
        return template;
    }

    /**
     * 自定义消息转换器
     */
    @Bean
    public RocketMQMessageConverter rocketMQMessageConverter() {
        return new CustomMessageConverter();
    }
}
```

### 2.2 自定义消息转换器

```java
// CustomMessageConverter.java
@Component
public class CustomMessageConverter extends CompositeMessageConverter {

    private static final String ENCODING = "UTF-8";

    @Override
    public org.springframework.messaging.Message<?> toMessage(
            Object payload, MessageHeaders headers) {

        // 添加追踪信息
        Map<String, Object> enrichedHeaders = new HashMap<>(headers);
        enrichedHeaders.put("traceId", TraceUtils.getTraceId());
        enrichedHeaders.put("timestamp", System.currentTimeMillis());

        return super.toMessage(payload, new MessageHeaders(enrichedHeaders));
    }

    @Override
    public Object fromMessage(org.springframework.messaging.Message<?> message, Class<?> targetClass) {
        // 自定义反序列化逻辑
        if (targetClass == OrderMessage.class) {
            return JSON.parseObject(
                new String((byte[]) message.getPayload(), StandardCharsets.UTF_8),
                OrderMessage.class
            );
        }
        return super.fromMessage(message, targetClass);
    }
}
```

## 三、消息生产者实现

### 3.1 通用消息服务

```java
// MessageService.java
@Service
@Slf4j
public class MessageService {

    @Autowired
    private RocketMQTemplate rocketMQTemplate;

    /**
     * 发送普通消息
     */
    public SendResult sendMessage(String topic, String tag, Object message) {
        String destination = buildDestination(topic, tag);

        try {
            Message<Object> springMessage = MessageBuilder
                .withPayload(message)
                .setHeader(RocketMQHeaders.KEYS, generateKey(message))
                .setHeader("businessType", message.getClass().getSimpleName())
                .build();

            SendResult result = rocketMQTemplate.syncSend(destination, springMessage);

            log.info("消息发送成功: destination={}, msgId={}, sendStatus={}",
                destination, result.getMsgId(), result.getSendStatus());

            // 记录监控指标
            recordMetrics(topic, tag, true, 0);

            return result;
        } catch (Exception e) {
            log.error("消息发送失败: destination={}, error={}", destination, e.getMessage());
            recordMetrics(topic, tag, false, 1);
            throw new RuntimeException("消息发送失败", e);
        }
    }

    /**
     * 发送延迟消息
     */
    public SendResult sendDelayMessage(String topic, String tag, Object message, int delayLevel) {
        String destination = buildDestination(topic, tag);

        Message<Object> springMessage = MessageBuilder
            .withPayload(message)
            .setHeader(RocketMQHeaders.KEYS, generateKey(message))
            .build();

        // delayLevel: 1s 5s 10s 30s 1m 2m 3m 4m 5m 6m 7m 8m 9m 10m 20m 30m 1h 2h
        SendResult result = rocketMQTemplate.syncSend(destination, springMessage,
            rocketMQTemplate.getProducer().getSendMsgTimeout(), delayLevel);

        log.info("延迟消息发送成功: destination={}, delayLevel={}, msgId={}",
            destination, delayLevel, result.getMsgId());

        return result;
    }

    /**
     * 发送顺序消息
     */
    public SendResult sendOrderlyMessage(String topic, String tag, Object message, String hashKey) {
        String destination = buildDestination(topic, tag);

        Message<Object> springMessage = MessageBuilder
            .withPayload(message)
            .setHeader(RocketMQHeaders.KEYS, generateKey(message))
            .build();

        SendResult result = rocketMQTemplate.syncSendOrderly(
            destination, springMessage, hashKey);

        log.info("顺序消息发送成功: destination={}, hashKey={}, msgId={}",
            destination, hashKey, result.getMsgId());

        return result;
    }

    /**
     * 发送事务消息
     */
    public TransactionSendResult sendTransactionMessage(
            String topic, String tag, Object message, Object arg) {

        String destination = buildDestination(topic, tag);

        Message<Object> springMessage = MessageBuilder
            .withPayload(message)
            .setHeader(RocketMQHeaders.KEYS, generateKey(message))
            .setHeader("transactionId", UUID.randomUUID().toString())
            .build();

        TransactionSendResult result = rocketMQTemplate.sendMessageInTransaction(
            destination, springMessage, arg);

        log.info("事务消息发送成功: destination={}, transactionId={}, sendStatus={}",
            destination, result.getTransactionId(), result.getSendStatus());

        return result;
    }

    /**
     * 批量发送消息
     */
    public SendResult sendBatchMessage(String topic, String tag, List<?> messages) {
        String destination = buildDestination(topic, tag);

        List<Message> rocketMQMessages = messages.stream()
            .map(msg -> {
                Message message = new Message();
                message.setTopic(topic);
                message.setTags(tag);
                message.setKeys(generateKey(msg));
                message.setBody(JSON.toJSONBytes(msg));
                return message;
            })
            .collect(Collectors.toList());

        SendResult result = rocketMQTemplate.syncSend(destination, rocketMQMessages);

        log.info("批量消息发送成功: destination={}, count={}, msgId={}",
            destination, messages.size(), result.getMsgId());

        return result;
    }

    /**
     * 异步发送消息
     */
    public void sendAsyncMessage(String topic, String tag, Object message,
                                 SendCallback sendCallback) {
        String destination = buildDestination(topic, tag);

        Message<Object> springMessage = MessageBuilder
            .withPayload(message)
            .setHeader(RocketMQHeaders.KEYS, generateKey(message))
            .build();

        rocketMQTemplate.asyncSend(destination, springMessage, sendCallback);

        log.info("异步消息已提交: destination={}", destination);
    }

    private String buildDestination(String topic, String tag) {
        return StringUtils.isBlank(tag) ? topic : topic + ":" + tag;
    }

    private String generateKey(Object message) {
        if (message instanceof BaseMessage) {
            return ((BaseMessage) message).getBusinessId();
        }
        return UUID.randomUUID().toString();
    }

    private void recordMetrics(String topic, String tag, boolean success, int failCount) {
        // 记录Prometheus指标
        if (success) {
            Metrics.counter("rocketmq.message.sent",
                "topic", topic,
                "tag", tag,
                "status", "success"
            ).increment();
        } else {
            Metrics.counter("rocketmq.message.sent",
                "topic", topic,
                "tag", tag,
                "status", "fail"
            ).increment(failCount);
        }
    }
}
```

### 3.2 订单消息生产者

```java
// OrderProducer.java
@Component
@Slf4j
public class OrderProducer {

    @Autowired
    private MessageService messageService;

    /**
     * 发送订单创建消息
     */
    public void sendOrderCreateMessage(Order order) {
        OrderMessage message = OrderMessage.builder()
            .orderId(order.getOrderId())
            .userId(order.getUserId())
            .amount(order.getAmount())
            .status(OrderStatus.CREATED)
            .createTime(new Date())
            .build();

        messageService.sendMessage("ORDER_TOPIC", "ORDER_CREATE", message);
    }

    /**
     * 发送订单支付消息（事务消息）
     */
    public void sendOrderPaymentMessage(Order order, PaymentInfo paymentInfo) {
        OrderMessage message = OrderMessage.builder()
            .orderId(order.getOrderId())
            .userId(order.getUserId())
            .amount(order.getAmount())
            .status(OrderStatus.PAID)
            .paymentInfo(paymentInfo)
            .build();

        // 发送事务消息，确保订单更新和消息发送的原子性
        messageService.sendTransactionMessage(
            "ORDER_TOPIC",
            "ORDER_PAYMENT",
            message,
            order  // 传递订单对象作为事务回查参数
        );
    }

    /**
     * 发送订单状态变更消息（顺序消息）
     */
    public void sendOrderStatusMessage(Order order, OrderStatus newStatus) {
        OrderMessage message = OrderMessage.builder()
            .orderId(order.getOrderId())
            .userId(order.getUserId())
            .status(newStatus)
            .updateTime(new Date())
            .build();

        // 使用订单ID作为顺序key，确保同一订单的消息顺序
        messageService.sendOrderlyMessage(
            "ORDER_TOPIC",
            "ORDER_STATUS_" + newStatus.name(),
            message,
            order.getOrderId()
        );
    }

    /**
     * 发送订单超时取消消息（延迟消息）
     */
    public void sendOrderTimeoutMessage(Order order) {
        OrderMessage message = OrderMessage.builder()
            .orderId(order.getOrderId())
            .userId(order.getUserId())
            .status(OrderStatus.TIMEOUT)
            .build();

        // 30分钟后发送超时消息（延迟级别16 = 30m）
        messageService.sendDelayMessage(
            "ORDER_TOPIC",
            "ORDER_TIMEOUT",
            message,
            16
        );
    }
}
```

## 四、消息消费者实现

### 4.1 订单消息消费者

```java
// OrderConsumer.java
@Component
@Slf4j
@RocketMQMessageListener(
    topic = "ORDER_TOPIC",
    consumerGroup = "order_consumer_group",
    messageModel = MessageModel.CLUSTERING,
    consumeMode = ConsumeMode.CONCURRENTLY,
    consumeThreadMax = 64,
    consumeThreadMin = 20
)
public class OrderConsumer implements RocketMQListener<OrderMessage>,
                                     RocketMQPushConsumerLifecycleListener {

    @Autowired
    private OrderService orderService;

    @Autowired
    private RedisTemplate<String, Object> redisTemplate;

    private final AtomicLong consumeCount = new AtomicLong(0);
    private final AtomicLong errorCount = new AtomicLong(0);

    @Override
    public void onMessage(OrderMessage message) {
        long count = consumeCount.incrementAndGet();
        log.info("消费订单消息: orderId={}, status={}, count={}",
            message.getOrderId(), message.getStatus(), count);

        try {
            // 幂等性检查
            if (isDuplicate(message)) {
                log.warn("重复消息，跳过处理: orderId={}", message.getOrderId());
                return;
            }

            // 处理消息
            processMessage(message);

            // 记录已处理
            markAsProcessed(message);

            // 记录监控指标
            recordSuccessMetrics(message);

        } catch (Exception e) {
            errorCount.incrementAndGet();
            log.error("消息处理失败: orderId={}, error={}",
                message.getOrderId(), e.getMessage(), e);

            // 记录错误指标
            recordErrorMetrics(message);

            // 重新抛出异常，触发重试
            throw new RuntimeException(e);
        }
    }

    /**
     * 幂等性检查
     */
    private boolean isDuplicate(OrderMessage message) {
        String key = "msg:processed:" + message.getOrderId();
        Boolean result = redisTemplate.opsForValue().setIfAbsent(
            key, "1", 24, TimeUnit.HOURS);
        return !Boolean.TRUE.equals(result);
    }

    /**
     * 处理消息
     */
    private void processMessage(OrderMessage message) {
        switch (message.getStatus()) {
            case CREATED:
                orderService.handleOrderCreated(message);
                break;
            case PAID:
                orderService.handleOrderPaid(message);
                break;
            case SHIPPED:
                orderService.handleOrderShipped(message);
                break;
            case COMPLETED:
                orderService.handleOrderCompleted(message);
                break;
            case CANCELLED:
                orderService.handleOrderCancelled(message);
                break;
            case TIMEOUT:
                orderService.handleOrderTimeout(message);
                break;
            default:
                log.warn("未知订单状态: {}", message.getStatus());
        }
    }

    /**
     * 标记消息已处理
     */
    private void markAsProcessed(OrderMessage message) {
        String key = "msg:processed:" + message.getOrderId();
        redisTemplate.opsForValue().set(key, JSON.toJSONString(message),
            7, TimeUnit.DAYS);
    }

    /**
     * 记录成功指标
     */
    private void recordSuccessMetrics(OrderMessage message) {
        Metrics.counter("order.message.consumed",
            "status", message.getStatus().name(),
            "result", "success"
        ).increment();
    }

    /**
     * 记录错误指标
     */
    private void recordErrorMetrics(OrderMessage message) {
        Metrics.counter("order.message.consumed",
            "status", message.getStatus().name(),
            "result", "error"
        ).increment();
    }

    @Override
    public void prepareStart(DefaultMQPushConsumer consumer) {
        // 消费者启动前的准备工作
        log.info("订单消费者准备启动: group={}", consumer.getConsumerGroup());

        // 设置消费位点
        consumer.setConsumeFromWhere(ConsumeFromWhere.CONSUME_FROM_LAST_OFFSET);

        // 设置消费超时（默认15分钟）
        consumer.setConsumeTimeout(15);

        // 设置最大重试次数
        consumer.setMaxReconsumeTimes(3);

        // 设置消息过滤
        try {
            consumer.subscribe("ORDER_TOPIC",
                MessageSelector.bySql("status in ('PAID', 'SHIPPED')"));
        } catch (Exception e) {
            log.error("设置消息过滤失败", e);
        }
    }
}
```

### 4.2 事务消息监听器

```java
// TransactionListenerImpl.java
@Component
@Slf4j
public class TransactionListenerImpl implements RocketMQLocalTransactionListener {

    @Autowired
    private OrderService orderService;

    @Autowired
    private TransactionLogService transactionLogService;

    /**
     * 执行本地事务
     */
    @Override
    public RocketMQLocalTransactionState executeLocalTransaction(
            Message msg, Object arg) {

        String transactionId = msg.getHeaders().get("transactionId", String.class);
        log.info("执行本地事务: transactionId={}", transactionId);

        try {
            // 解析消息
            OrderMessage orderMessage = JSON.parseObject(
                new String((byte[]) msg.getPayload()),
                OrderMessage.class
            );

            // 执行本地事务
            Order order = (Order) arg;
            orderService.updateOrderStatus(order, OrderStatus.PAID);

            // 记录事务日志
            transactionLogService.save(
                transactionId,
                orderMessage.getOrderId(),
                TransactionStatus.COMMIT
            );

            log.info("本地事务执行成功: orderId={}", orderMessage.getOrderId());
            return RocketMQLocalTransactionState.COMMIT;

        } catch (Exception e) {
            log.error("本地事务执行失败: transactionId={}", transactionId, e);

            // 记录失败
            transactionLogService.save(
                transactionId,
                null,
                TransactionStatus.ROLLBACK
            );

            return RocketMQLocalTransactionState.ROLLBACK;
        }
    }

    /**
     * 事务回查
     */
    @Override
    public RocketMQLocalTransactionState checkLocalTransaction(Message msg) {
        String transactionId = msg.getHeaders().get("transactionId", String.class);
        log.info("事务回查: transactionId={}", transactionId);

        // 查询事务日志
        TransactionLog log = transactionLogService.findByTransactionId(transactionId);

        if (log == null) {
            log.warn("事务日志不存在: transactionId={}", transactionId);
            return RocketMQLocalTransactionState.UNKNOWN;
        }

        // 根据事务状态返回
        switch (log.getStatus()) {
            case COMMIT:
                return RocketMQLocalTransactionState.COMMIT;
            case ROLLBACK:
                return RocketMQLocalTransactionState.ROLLBACK;
            default:
                return RocketMQLocalTransactionState.UNKNOWN;
        }
    }
}
```

## 五、错误处理和重试

### 5.1 消费失败处理

```java
// RetryMessageHandler.java
@Component
@Slf4j
public class RetryMessageHandler {

    @Autowired
    private MessageService messageService;

    @Autowired
    private RedisTemplate<String, Object> redisTemplate;

    /**
     * 处理消费失败的消息
     */
    public void handleConsumeError(Message message, Exception error) {
        String messageId = message.getHeaders().get(RocketMQHeaders.MESSAGE_ID, String.class);
        String topic = message.getHeaders().get(RocketMQHeaders.TOPIC, String.class);

        // 记录重试次数
        String retryKey = "retry:count:" + messageId;
        Long retryCount = redisTemplate.opsForValue().increment(retryKey);
        redisTemplate.expire(retryKey, 1, TimeUnit.DAYS);

        log.error("消息消费失败: messageId={}, topic={}, retryCount={}, error={}",
            messageId, topic, retryCount, error.getMessage());

        // 根据重试次数决定处理策略
        if (retryCount <= 3) {
            // 延迟重试
            retryWithDelay(message, retryCount);
        } else if (retryCount <= 5) {
            // 发送到重试队列
            sendToRetryQueue(message);
        } else {
            // 发送到死信队列
            sendToDeadLetterQueue(message, error);
        }
    }

    /**
     * 延迟重试
     */
    private void retryWithDelay(Message message, Long retryCount) {
        // 计算延迟级别：第1次10s，第2次30s，第3次1m
        int delayLevel = retryCount.intValue() * 2 + 1;

        messageService.sendDelayMessage(
            message.getHeaders().get(RocketMQHeaders.TOPIC, String.class),
            "RETRY",
            message.getPayload(),
            delayLevel
        );

        log.info("消息已发送到延迟重试队列: messageId={}, delayLevel={}",
            message.getHeaders().get(RocketMQHeaders.MESSAGE_ID), delayLevel);
    }

    /**
     * 发送到重试队列
     */
    private void sendToRetryQueue(Message message) {
        String retryTopic = "%RETRY%" +
            message.getHeaders().get(RocketMQHeaders.CONSUMER_GROUP);

        messageService.sendMessage(retryTopic, "RETRY", message.getPayload());

        log.info("消息已发送到重试队列: topic={}", retryTopic);
    }

    /**
     * 发送到死信队列
     */
    private void sendToDeadLetterQueue(Message message, Exception error) {
        String dlqTopic = "%DLQ%" +
            message.getHeaders().get(RocketMQHeaders.CONSUMER_GROUP);

        // 添加错误信息
        Map<String, Object> headers = new HashMap<>(message.getHeaders());
        headers.put("errorMessage", error.getMessage());
        headers.put("errorTime", new Date());

        Message<Object> dlqMessage = MessageBuilder
            .withPayload(message.getPayload())
            .copyHeaders(headers)
            .build();

        messageService.sendMessage(dlqTopic, "DLQ", dlqMessage);

        log.error("消息已发送到死信队列: topic={}", dlqTopic);

        // 发送告警
        sendAlert(message, error);
    }

    /**
     * 发送告警
     */
    private void sendAlert(Message message, Exception error) {
        // 发送告警通知（邮件、短信、钉钉等）
        String alertMessage = String.format(
            "消息处理失败告警\n" +
            "Topic: %s\n" +
            "MessageId: %s\n" +
            "Error: %s\n" +
            "Time: %s",
            message.getHeaders().get(RocketMQHeaders.TOPIC),
            message.getHeaders().get(RocketMQHeaders.MESSAGE_ID),
            error.getMessage(),
            new Date()
        );

        // 这里可以集成告警系统
        log.error("告警: {}", alertMessage);
    }
}
```

## 六、监控和运维

### 6.1 健康检查

```java
// RocketMQHealthIndicator.java
@Component
public class RocketMQHealthIndicator implements HealthIndicator {

    @Autowired
    private RocketMQTemplate rocketMQTemplate;

    @Override
    public Health health() {
        try {
            // 检查 NameServer 连接
            DefaultMQProducer producer = rocketMQTemplate.getProducer();
            producer.getDefaultMQProducerImpl().getmQClientFactory()
                .getMQClientAPIImpl().getNameServerAddressList();

            // 检查 Broker 连接
            Collection<String> topics = producer.getDefaultMQProducerImpl()
                .getmQClientFactory().getTopicRouteTable().keySet();

            return Health.up()
                .withDetail("nameServer", producer.getNamesrvAddr())
                .withDetail("producerGroup", producer.getProducerGroup())
                .withDetail("topics", topics)
                .build();

        } catch (Exception e) {
            return Health.down()
                .withDetail("error", e.getMessage())
                .build();
        }
    }
}
```

### 6.2 监控指标收集

```java
// RocketMQMetrics.java
@Component
@Slf4j
public class RocketMQMetrics {

    private final MeterRegistry meterRegistry;
    private final Map<String, AtomicLong> counters = new ConcurrentHashMap<>();

    public RocketMQMetrics(MeterRegistry meterRegistry) {
        this.meterRegistry = meterRegistry;
        initMetrics();
    }

    private void initMetrics() {
        // 发送成功计数
        Gauge.builder("rocketmq.producer.send.success", counters,
            map -> map.getOrDefault("send.success", new AtomicLong()).get())
            .register(meterRegistry);

        // 发送失败计数
        Gauge.builder("rocketmq.producer.send.failure", counters,
            map -> map.getOrDefault("send.failure", new AtomicLong()).get())
            .register(meterRegistry);

        // 消费成功计数
        Gauge.builder("rocketmq.consumer.consume.success", counters,
            map -> map.getOrDefault("consume.success", new AtomicLong()).get())
            .register(meterRegistry);

        // 消费失败计数
        Gauge.builder("rocketmq.consumer.consume.failure", counters,
            map -> map.getOrDefault("consume.failure", new AtomicLong()).get())
            .register(meterRegistry);

        // 消息堆积数
        Gauge.builder("rocketmq.consumer.lag", this, RocketMQMetrics::getConsumerLag)
            .register(meterRegistry);
    }

    public void recordSendSuccess() {
        counters.computeIfAbsent("send.success", k -> new AtomicLong()).incrementAndGet();
    }

    public void recordSendFailure() {
        counters.computeIfAbsent("send.failure", k -> new AtomicLong()).incrementAndGet();
    }

    public void recordConsumeSuccess() {
        counters.computeIfAbsent("consume.success", k -> new AtomicLong()).incrementAndGet();
    }

    public void recordConsumeFailure() {
        counters.computeIfAbsent("consume.failure", k -> new AtomicLong()).incrementAndGet();
    }

    private double getConsumerLag() {
        // 实现获取消费延迟的逻辑
        return 0.0;
    }
}
```

## 七、部署和运维

### 7.1 Docker 部署

```yaml
# docker-compose.yml
version: '3.8'

services:
  app:
    build: .
    container_name: rocketmq-springboot-demo
    environment:
      - SPRING_PROFILES_ACTIVE=prod
      - ROCKETMQ_NAMESRV=rocketmq-namesrv:9876
      - JAVA_OPTS=-Xms1G -Xmx1G -XX:+UseG1GC
    ports:
      - "8080:8080"
      - "9090:9090"  # Prometheus metrics
    depends_on:
      - rocketmq-namesrv
      - rocketmq-broker
      - redis
      - mysql
    networks:
      - rocketmq-network

  rocketmq-namesrv:
    image: apache/rocketmq:4.9.4
    container_name: rocketmq-namesrv
    command: sh mqnamesrv
    ports:
      - "9876:9876"
    networks:
      - rocketmq-network

  rocketmq-broker:
    image: apache/rocketmq:4.9.4
    container_name: rocketmq-broker
    command: sh mqbroker -n rocketmq-namesrv:9876
    ports:
      - "10909:10909"
      - "10911:10911"
    networks:
      - rocketmq-network

  redis:
    image: redis:6.2
    container_name: redis
    ports:
      - "6379:6379"
    networks:
      - rocketmq-network

  mysql:
    image: mysql:8.0
    container_name: mysql
    environment:
      - MYSQL_ROOT_PASSWORD=root123
      - MYSQL_DATABASE=rocketmq_demo
    ports:
      - "3306:3306"
    networks:
      - rocketmq-network

networks:
  rocketmq-network:
    driver: bridge
```

### 7.2 Kubernetes 部署

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rocketmq-springboot-demo
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: rocketmq-springboot-demo
  template:
    metadata:
      labels:
        app: rocketmq-springboot-demo
    spec:
      containers:
      - name: app
        image: rocketmq-springboot-demo:latest
        ports:
        - containerPort: 8080
        - containerPort: 9090
        env:
        - name: SPRING_PROFILES_ACTIVE
          value: "prod"
        - name: ROCKETMQ_NAMESRV
          value: "rocketmq-namesrv-service:9876"
        - name: JAVA_OPTS
          value: "-Xms1G -Xmx1G -XX:+UseG1GC"
        resources:
          requests:
            memory: "1Gi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
        livenessProbe:
          httpGet:
            path: /actuator/health
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /actuator/health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 5

---
apiVersion: v1
kind: Service
metadata:
  name: rocketmq-springboot-demo-service
spec:
  selector:
    app: rocketmq-springboot-demo
  ports:
  - name: http
    port: 8080
    targetPort: 8080
  - name: metrics
    port: 9090
    targetPort: 9090
  type: LoadBalancer
```

## 八、总结

通过这个完整的 SpringBoot 集成示例，我们实现了：

1. **完整的项目结构**：清晰的分层和模块化设计
2. **各种消息类型**：普通、延迟、顺序、事务、批量消息
3. **错误处理**：重试机制、死信队列、告警通知
4. **监控运维**：健康检查、指标收集、Prometheus集成
5. **生产部署**：Docker和Kubernetes部署方案

这个项目可以作为生产环境的起点，根据具体业务需求进行扩展和优化。

## 🎉 第一阶段完成

恭喜！我们已经完成了 **RocketMQ 基础入门篇**的全部10篇文章。通过这个阶段的学习，你已经：

- 理解了消息队列的本质和价值
- 掌握了 RocketMQ 的核心概念
- 学会了各种消息模式的使用
- 能够构建生产级的消息系统

下一阶段，我们将深入 **架构原理篇**，探索 RocketMQ 的内部实现机制。

---

**实践作业**：

1. 基于本文的示例代码，搭建一个完整的项目
2. 实现一个电商订单的完整流程
3. 添加监控告警，观察系统运行状态
4. 进行压力测试，优化系统性能

坚持实践，不断进步！🚀