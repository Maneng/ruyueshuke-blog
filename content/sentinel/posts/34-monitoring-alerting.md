---
title: "监控指标与告警体系"
date: 2025-11-21T16:47:00+08:00
draft: false
tags: ["Sentinel", "监控", "告警"]
categories: ["技术"]
series: ["Sentinel从入门到精通"]
weight: 34
stage: 7
stageTitle: "生产实践篇"
description: "构建完整的Sentinel监控告警体系"
---

## 核心监控指标

### 流量指标

| 指标 | 说明 | 单位 |
|-----|-----|-----|
| passQps | 通过QPS | 次/秒 |
| blockQps | 限流QPS | 次/秒 |
| successQps | 成功QPS | 次/秒 |
| exceptionQps | 异常QPS | 次/秒 |
| avgRt | 平均响应时间 | 毫秒 |
| minRt | 最小响应时间 | 毫秒 |
| maxConcurrency | 最大并发数 | 个 |

### 规则指标

| 指标 | 说明 |
|-----|-----|
| flowRuleCount | 流控规则数量 |
| degradeRuleCount | 熔断规则数量 |
| systemRuleCount | 系统规则数量 |
| authorityRuleCount | 授权规则数量 |

### 系统指标

| 指标 | 说明 |
|-----|-----|
| systemLoad | 系统负载 |
| cpuUsage | CPU使用率 |
| memoryUsage | 内存使用率 |
| threadCount | 线程数 |

## Prometheus集成

### 暴露指标

```xml
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>
```

```yaml
management:
  endpoints:
    web:
      exposure:
        include: '*'
  metrics:
    export:
      prometheus:
        enabled: true
```

### 自定义指标

```java
@Component
public class SentinelMetrics {

    private final MeterRegistry meterRegistry;

    public SentinelMetrics(MeterRegistry meterRegistry) {
        this.meterRegistry = meterRegistry;

        // 注册指标采集
        Metrics.addRegistry(meterRegistry);

        // 定时采集Sentinel指标
        Executors.newScheduledThreadPool(1).scheduleAtFixedRate(() -> {
            collectMetrics();
        }, 0, 10, TimeUnit.SECONDS);
    }

    private void collectMetrics() {
        Map<String, Node> nodeMap = ClusterBuilderSlot.getClusterNodeMap();

        for (Map.Entry<String, ClusterNode> entry : nodeMap.entrySet()) {
            String resource = entry.getKey();
            ClusterNode node = entry.getValue();

            // 通过QPS
            Gauge.builder("sentinel.pass.qps", node, Node::passQps)
                .tag("resource", resource)
                .register(meterRegistry);

            // 限流QPS
            Gauge.builder("sentinel.block.qps", node, Node::blockQps)
                .tag("resource", resource)
                .register(meterRegistry);

            // 平均RT
            Gauge.builder("sentinel.avg.rt", node, Node::avgRt)
                .tag("resource", resource)
                .register(meterRegistry);
        }
    }
}
```

### Prometheus配置

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'sentinel'
    metrics_path: '/actuator/prometheus'
    static_configs:
      - targets: ['localhost:8080']
```

## Grafana Dashboard

### Dashboard JSON

```json
{
  "dashboard": {
    "title": "Sentinel Monitoring",
    "panels": [
      {
        "title": "QPS",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(sentinel_pass_qps{resource=\"orderCreate\"}[1m])",
            "legendFormat": "通过"
          },
          {
            "expr": "rate(sentinel_block_qps{resource=\"orderCreate\"}[1m])",
            "legendFormat": "限流"
          }
        ]
      },
      {
        "title": "限流比例",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(sentinel_block_qps[1m]) / (rate(sentinel_pass_qps[1m]) + rate(sentinel_block_qps[1m]))",
            "legendFormat": "{{resource}}"
          }
        ]
      },
      {
        "title": "平均RT",
        "type": "graph",
        "targets": [
          {
            "expr": "sentinel_avg_rt",
            "legendFormat": "{{resource}}"
          }
        ]
      }
    ]
  }
}
```

## 告警规则

### Prometheus Alertmanager

```yaml
# alert_rules.yml
groups:
  - name: sentinel_alerts
    rules:
      # 限流频繁告警
      - alert: HighBlockRate
        expr: |
          rate(sentinel_block_qps[1m]) /
          (rate(sentinel_pass_qps[1m]) + rate(sentinel_block_qps[1m])) > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "限流比例过高"
          description: "资源 {{ $labels.resource }} 限流比例超过10%"

      # 熔断告警
      - alert: CircuitBreakerOpen
        expr: sentinel_circuit_breaker_state == 1
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "熔断器开启"
          description: "资源 {{ $labels.resource }} 熔断器已开启"

      # RT过高告警
      - alert: HighAvgRT
        expr: sentinel_avg_rt > 1000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "平均RT过高"
          description: "资源 {{ $labels.resource }} 平均RT超过1秒"

      # 系统负载过高
      - alert: HighSystemLoad
        expr: system_load > 4.0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "系统负载过高"
          description: "系统负载为 {{ $value }}"
```

### Alertmanager配置

```yaml
# alertmanager.yml
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'resource']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'default'

receivers:
  - name: 'default'
    webhook_configs:
      - url: 'http://localhost:8060/webhook'
    email_configs:
      - to: 'ops@example.com'
        from: 'alert@example.com'
        smarthost: 'smtp.example.com:587'
```

## 自定义告警

### 钉钉告警

```java
@Component
public class DingTalkAlerter {

    private static final String WEBHOOK_URL = "https://oapi.dingtalk.com/robot/send?access_token=xxx";

    public void sendAlert(String title, String content) {
        Map<String, Object> message = new HashMap<>();
        message.put("msgtype", "markdown");

        Map<String, String> markdown = new HashMap<>();
        markdown.put("title", title);
        markdown.put("text", content);
        message.put("markdown", markdown);

        RestTemplate restTemplate = new RestTemplate();
        restTemplate.postForObject(WEBHOOK_URL, message, String.class);
    }
}

@Component
public class SentinelAlerter {

    @Autowired
    private DingTalkAlerter dingTalkAlerter;

    private final AtomicLong blockCount = new AtomicLong(0);

    @PostConstruct
    public void init() {
        // 定时检查限流次数
        Executors.newScheduledThreadPool(1).scheduleAtFixedRate(() -> {
            checkBlockCount();
        }, 0, 1, TimeUnit.MINUTES);
    }

    private void checkBlockCount() {
        long currentBlock = blockCount.get();

        if (currentBlock > 1000) {  // 1分钟限流超过1000次
            String content = String.format(
                "### Sentinel告警\\n" +
                "- **告警类型**: 限流频繁\\n" +
                "- **限流次数**: %d次/分钟\\n" +
                "- **告警时间**: %s",
                currentBlock,
                LocalDateTime.now().format(DateTimeFormatter.ISO_LOCAL_DATE_TIME)
            );

            dingTalkAlerter.sendAlert("Sentinel限流告警", content);
        }

        blockCount.set(0);  // 重置计数
    }

    public void recordBlock() {
        blockCount.incrementAndGet();
    }
}
```

## 日志监控

### 结构化日志

```java
@Aspect
@Component
public class SentinelLogAspect {

    private static final Logger log = LoggerFactory.getLogger(SentinelLogAspect.class);

    @Around("@annotation(sentinelResource)")
    public Object around(ProceedingJoinPoint pjp, SentinelResource sentinelResource) throws Throwable {
        String resource = sentinelResource.value();
        long start = System.currentTimeMillis();

        try {
            Object result = pjp.proceed();
            long cost = System.currentTimeMillis() - start;

            // 记录成功日志
            log.info("resource={}, status=success, cost={}ms", resource, cost);

            return result;
        } catch (BlockException e) {
            // 记录限流日志
            log.warn("resource={}, status=blocked, reason={}", resource, e.getRule());
            throw e;
        } catch (Exception e) {
            // 记录异常日志
            log.error("resource={}, status=error, message={}", resource, e.getMessage());
            throw e;
        }
    }
}
```

### ELK日志分析

```json
{
  "logstash": {
    "input": {
      "file": {
        "path": "/var/log/sentinel/*.log",
        "type": "sentinel"
      }
    },
    "filter": {
      "grok": {
        "match": {
          "message": "resource=%{WORD:resource}, status=%{WORD:status}, cost=%{NUMBER:cost}ms"
        }
      }
    },
    "output": {
      "elasticsearch": {
        "hosts": ["localhost:9200"],
        "index": "sentinel-%{+YYYY.MM.dd}"
      }
    }
  }
}
```

## 监控大盘

### 关键指标展示

```
┌─────────────────────────────────────┐
│      Sentinel监控大盘                │
├─────────────────────────────────────┤
│ 实时QPS：     1,234 / 10,000       │
│ 限流比例：    2.3%                  │
│ 平均RT：      45ms                  │
│ 熔断器状态：  正常 ✅               │
├─────────────────────────────────────┤
│ TOP 5 限流资源：                     │
│  1. orderCreate    123次            │
│  2. paymentPay     89次             │
│  3. productQuery   56次             │
├─────────────────────────────────────┤
│ 告警记录：                           │
│  [15:30] 订单服务限流频繁           │
│  [14:20] 商品服务熔断               │
└─────────────────────────────────────┘
```

## 总结

监控告警体系：
1. **指标采集**：Prometheus采集Sentinel指标
2. **可视化**：Grafana展示监控大盘
3. **告警规则**：配置限流、熔断、RT告警
4. **通知渠道**：钉钉、邮件、短信
5. **日志分析**：ELK分析限流日志

**最佳实践**：
- 采集关键指标，避免过度监控
- 设置合理告警阈值，减少误报
- 多渠道通知，确保及时响应
- 定期review告警，优化规则
