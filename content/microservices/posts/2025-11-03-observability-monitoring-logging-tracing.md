---
title: 可观测性：监控、日志、链路追踪三位一体
date: 2025-11-03T10:00:00+08:00
draft: false
tags:
  - 可观测性
  - 微服务
  - Prometheus
  - ELK
  - SkyWalking
  - 监控
  - Java
categories:
  - 技术
description: 深度剖析微服务可观测性体系。掌握监控指标采集、日志聚合、链路追踪，快速定位和解决分布式系统问题。
series:
  - Java微服务架构第一性原理
weight: 6
---

## 引子：一次线上故障的排查噩梦

2021年某晚，某电商平台接口响应慢，用户投诉激增。

**排查过程**：
- 运维：哪个服务出问题了？（无监控）
- 开发：日志在哪？（分散在100台服务器）
- 架构师：调用链路是什么？（无链路追踪）

**耗时**：3小时才定位到问题（数据库连接池配置错误）

**教训**：微服务架构下，可观测性至关重要

---

## 一、可观测性的本质

### 1.1 什么是可观测性？

**可观测性（Observability）**是指通过外部输出理解系统内部状态的能力。

**三大支柱**：
1. **Metrics（指标）**：数字化的度量（QPS、响应时间、错误率）
2. **Logs（日志）**：事件的记录（请求日志、错误日志）
3. **Traces（追踪）**：请求的全链路视图（调用链路）

### 1.2 监控 vs 可观测性

| 维度 | 监控 | 可观测性 |
|------|------|---------|
| **目标** | 已知问题 | 未知问题 |
| **方式** | 预设指标 | 任意维度查询 |
| **例子** | CPU > 80%告警 | 为什么这个请求慢？ |

---

## 二、监控体系：Prometheus + Grafana

### 2.1 监控指标的四个黄金信号

1. **延迟（Latency）**：请求响应时间
2. **流量（Traffic）**：QPS、TPS
3. **错误（Errors）**：错误率
4. **饱和度（Saturation）**：CPU、内存、磁盘使用率

### 2.2 Prometheus监控配置

**1. 添加依赖**

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>
```

**2. 配置application.yml**

```yaml
management:
  endpoints:
    web:
      exposure:
        include: "*"  # 暴露所有端点
  metrics:
    export:
      prometheus:
        enabled: true
    tags:
      application: ${spring.application.name}
```

**3. 自定义指标**

```java
/**
 * 订单服务指标
 */
@Component
public class OrderMetrics {

    private final Counter orderCreatedCounter;
    private final Timer orderCreatedTimer;

    public OrderMetrics(MeterRegistry registry) {
        // 计数器：订单创建总数
        this.orderCreatedCounter = Counter.builder("order.created.total")
                .description("订单创建总数")
                .tag("service", "order-service")
                .register(registry);

        // 计时器：订单创建耗时
        this.orderCreatedTimer = Timer.builder("order.created.duration")
                .description("订单创建耗时")
                .tag("service", "order-service")
                .register(registry);
    }

    public void recordOrderCreated() {
        orderCreatedCounter.increment();
    }

    public void recordOrderCreatedDuration(Runnable task) {
        orderCreatedTimer.record(task);
    }
}

/**
 * 使用指标
 */
@Service
public class OrderService {

    @Autowired
    private OrderMetrics metrics;

    public Order createOrder(OrderRequest request) {
        return metrics.recordOrderCreatedDuration(() -> {
            Order order = doCreateOrder(request);
            metrics.recordOrderCreated();
            return order;
        });
    }
}
```

**4. Prometheus配置**

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'order-service'
    metrics_path: '/actuator/prometheus'
    static_configs:
      - targets: ['localhost:8080']
```

### 2.3 Grafana Dashboard

**核心面板**：
1. **QPS**：每秒请求数
2. **响应时间**：P50、P95、P99
3. **错误率**：4xx、5xx错误占比
4. **JVM监控**：堆内存、GC次数、线程数
5. **数据库监控**：连接池使用率、慢SQL

---

## 三、日志聚合：ELK Stack

### 3.1 ELK架构

```
应用服务 → Filebeat → Logstash → Elasticsearch → Kibana
          (采集)    (处理)     (存储)        (查询)
```

### 3.2 结构化日志

**传统日志**：

```
2025-11-03 10:00:00 ERROR OrderService - 订单创建失败 orderNo=ORD001 userId=123
```

**结构化日志（JSON）**：

```json
{
  "timestamp": "2025-11-03T10:00:00+08:00",
  "level": "ERROR",
  "service": "order-service",
  "class": "OrderService",
  "message": "订单创建失败",
  "orderNo": "ORD001",
  "userId": 123,
  "traceId": "abc123",
  "spanId": "xyz789"
}
```

**配置Logback**：

```xml
<!-- logback-spring.xml -->
<configuration>
    <appender name="JSON" class="ch.qos.logback.core.ConsoleAppender">
        <encoder class="net.logstash.logback.encoder.LogstashEncoder">
            <customFields>{"service":"order-service"}</customFields>
        </encoder>
    </appender>

    <root level="INFO">
        <appender-ref ref="JSON"/>
    </root>
</configuration>
```

### 3.3 日志规范

**1. 日志级别**

| 级别 | 用途 | 示例 |
|------|------|------|
| ERROR | 错误 | 订单创建失败 |
| WARN | 警告 | 库存不足 |
| INFO | 关键信息 | 订单创建成功 |
| DEBUG | 调试信息 | SQL语句 |

**2. 日志内容**

```java
// ❌ 错误示例
log.info("订单创建");

// ✅ 正确示例
log.info("订单创建成功: orderNo={}, userId={}, amount={}",
    order.getOrderNo(), order.getUserId(), order.getAmount());
```

---

## 四、链路追踪：SkyWalking

### 4.1 链路追踪的必要性

**问题**：微服务调用链路长，无法快速定位问题

```
用户请求 → Gateway → 订单服务 → 库存服务 → 数据库
                   → 商品服务 → Redis
                   → 支付服务 → 第三方API

问题：哪个环节慢？
```

**解决方案**：链路追踪

```
TraceID: abc123（贯穿整个请求）
  - SpanID: span1 (Gateway: 10ms)
  - SpanID: span2 (订单服务: 50ms)
    - SpanID: span3 (库存服务: 20ms)
    - SpanID: span4 (商品服务: 15ms)
    - SpanID: span5 (支付服务: 80ms)  ← 慢！

结论：支付服务响应慢，是性能瓶颈
```

### 4.2 SkyWalking配置

**1. 下载SkyWalking Agent**

```bash
wget https://archive.apache.org/dist/skywalking/java-agent/8.15.0/apache-skywalking-java-agent-8.15.0.tgz
tar -zxvf apache-skywalking-java-agent-8.15.0.tgz
```

**2. 启动应用时添加Agent**

```bash
java -javaagent:/path/to/skywalking-agent.jar \
     -Dskywalking.agent.service_name=order-service \
     -Dskywalking.collector.backend_service=127.0.0.1:11800 \
     -jar order-service.jar
```

**3. 查看链路追踪**

访问SkyWalking UI: http://localhost:8080

### 4.3 TraceID传递

**手动传递TraceID**：

```java
/**
 * TraceID过滤器
 */
@Component
public class TraceIdFilter implements Filter {

    private static final String TRACE_ID_HEADER = "X-Trace-Id";

    @Override
    public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain) {
        HttpServletRequest httpRequest = (HttpServletRequest) request;

        // 获取或生成TraceID
        String traceId = httpRequest.getHeader(TRACE_ID_HEADER);
        if (StringUtils.isEmpty(traceId)) {
            traceId = UUID.randomUUID().toString();
        }

        // 存入MDC（用于日志输出）
        MDC.put("traceId", traceId);

        try {
            chain.doFilter(request, response);
        } finally {
            MDC.clear();
        }
    }
}
```

**Feign传递TraceID**：

```java
/**
 * Feign拦截器：传递TraceID
 */
@Component
public class TraceIdFeignInterceptor implements RequestInterceptor {

    @Override
    public void apply(RequestTemplate template) {
        String traceId = MDC.get("traceId");
        if (StringUtils.isNotEmpty(traceId)) {
            template.header("X-Trace-Id", traceId);
        }
    }
}
```

---

## 五、告警系统

### 5.1 告警规则设计

**示例**：

```yaml
# Prometheus告警规则
groups:
  - name: order-service
    interval: 30s
    rules:
      # 错误率告警
      - alert: HighErrorRate
        expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.05
        for: 5m
        annotations:
          summary: "错误率超过5%"

      # 响应时间告警
      - alert: HighLatency
        expr: histogram_quantile(0.99, http_request_duration_seconds) > 1
        for: 5m
        annotations:
          summary: "P99响应时间超过1秒"

      # CPU告警
      - alert: HighCPU
        expr: process_cpu_usage > 0.8
        for: 10m
        annotations:
          summary: "CPU使用率超过80%"
```

### 5.2 告警收敛

**问题**：告警风暴（1000个实例同时告警）

**解决方案**：
1. **分组**：按服务分组
2. **抑制**：高级别告警抑制低级别
3. **静默**：维护期间静默告警
4. **去重**：相同告警只发送一次

---

## 六、总结

### 可观测性三件套

1. **Prometheus + Grafana**：监控指标（实时）
2. **ELK Stack**：日志聚合（查询历史）
3. **SkyWalking**：链路追踪（定位问题）

### 最佳实践

1. ✅ **使用结构化日志**（JSON格式）
2. ✅ **TraceID贯穿全链路**（便于关联查询）
3. ✅ **四个黄金信号**（延迟、流量、错误、饱和度）
4. ✅ **合理设置告警阈值**（避免告警风暴）
5. ✅ **建立Grafana Dashboard**（可视化监控）

### 快速定位问题的步骤

1. **查看监控**：Grafana看指标异常（哪个服务？）
2. **查看日志**：Kibana查询错误日志（什么错误？）
3. **查看链路**：SkyWalking追踪调用链（哪个环节慢？）
4. **定位根因**：结合代码分析（如何修复？）

---

**参考资料**：
1. Prometheus官方文档
2. ELK Stack官方文档
3. SkyWalking官方文档
4. 《分布式系统可观测性》

**最后更新时间**：2025-11-03

---

## 系列总结

恭喜你完成《Java微服务架构第一性原理》系列的全部6篇文章！

**系列回顾**：
1. ✅ **为什么需要微服务**：单体架构的困境与演进
2. ✅ **如何拆分服务**：领域驱动设计与康威定律
3. ✅ **如何通信**：同步调用、异步消息与事件驱动
4. ✅ **如何保证一致性**：分布式事务解决方案
5. ✅ **如何治理**：注册发现、负载均衡与熔断降级
6. ✅ **如何观测**：监控、日志、链路追踪三位一体

**核心收获**：
- 🎯 掌握微服务架构的完整知识体系
- 🎯 理解从单体到微服务的演进路径
- 🎯 学会分布式系统的设计与实践
- 🎯 建立第一性原理的思维方式

**下一步**：
- 实战演练：搭建一个完整的微服务系统
- 深入学习：Spring Cloud、Dubbo、Kubernetes
- 持续优化：性能调优、成本优化、稳定性建设

感谢阅读，祝你在微服务架构之路上越走越远！
