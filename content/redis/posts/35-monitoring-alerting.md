---
title: "监控告警体系：构建Redis可观测性"
date: 2025-01-22T00:00:00+08:00
draft: false
tags: ["Redis", "监控", "告警", "Prometheus"]
categories: ["技术"]
description: "构建完善的Redis监控告警体系，实时掌握Redis运行状态，及时发现和解决问题"
weight: 35
stage: 4
stageTitle: "生产实践篇"
---

## 核心监控指标

### 1. 性能指标

```java
@Component
public class RedisMetricsCollector {
    @Autowired
    private RedisTemplate<String, String> redis;

    // QPS（每秒查询数）
    public long getQPS() {
        Properties info = redis.execute((RedisCallback<Properties>) connection ->
            connection.info("stats")
        );
        return Long.parseLong(info.getProperty("instantaneous_ops_per_sec"));
    }

    // 延迟
    public long getLatency() {
        long start = System.currentTimeMillis();
        redis.opsForValue().get("health_check");
        return System.currentTimeMillis() - start;
    }

    // 命中率
    public double getHitRate() {
        Properties info = redis.execute((RedisCallback<Properties>) connection ->
            connection.info("stats")
        );

        long hits = Long.parseLong(info.getProperty("keyspace_hits"));
        long misses = Long.parseLong(info.getProperty("keyspace_misses"));

        if (hits + misses == 0) {
            return 0;
        }
        return hits * 100.0 / (hits + misses);
    }

    // 慢查询数量
    public long getSlowlogCount() {
        return redis.execute((RedisCallback<Long>) connection ->
            connection.slowlogLen()
        );
    }
}
```

### 2. 资源指标

```java
// 内存使用
public Map<String, Object> getMemoryMetrics() {
    Properties info = redis.execute((RedisCallback<Properties>) connection ->
        connection.info("memory")
    );

    Map<String, Object> metrics = new HashMap<>();
    metrics.put("used_memory", Long.parseLong(info.getProperty("used_memory")));
    metrics.put("used_memory_rss", Long.parseLong(info.getProperty("used_memory_rss")));
    metrics.put("mem_fragmentation_ratio",
        Double.parseDouble(info.getProperty("mem_fragmentation_ratio")));
    metrics.put("evicted_keys", Long.parseLong(info.getProperty("evicted_keys")));

    return metrics;
}

// CPU使用
public double getCPUUsage() {
    Properties info = redis.execute((RedisCallback<Properties>) connection ->
        connection.info("cpu")
    );
    return Double.parseDouble(info.getProperty("used_cpu_sys"));
}

// 连接数
public Map<String, Long> getConnectionMetrics() {
    Properties info = redis.execute((RedisCallback<Properties>) connection ->
        connection.info("clients")
    );

    Map<String, Long> metrics = new HashMap<>();
    metrics.put("connected_clients", Long.parseLong(info.getProperty("connected_clients")));
    metrics.put("blocked_clients", Long.parseLong(info.getProperty("blocked_clients")));

    return metrics;
}
```

### 3. 持久化指标

```java
public Map<String, Object> getPersistenceMetrics() {
    Properties info = redis.execute((RedisCallback<Properties>) connection ->
        connection.info("persistence")
    );

    Map<String, Object> metrics = new HashMap<>();

    // RDB
    metrics.put("rdb_last_save_time", Long.parseLong(info.getProperty("rdb_last_save_time")));
    metrics.put("rdb_changes_since_last_save",
        Long.parseLong(info.getProperty("rdb_changes_since_last_save")));

    // AOF
    if ("1".equals(info.getProperty("aof_enabled"))) {
        metrics.put("aof_current_size", Long.parseLong(info.getProperty("aof_current_size")));
        metrics.put("aof_base_size", Long.parseLong(info.getProperty("aof_base_size")));
    }

    return metrics;
}
```

### 4. 复制指标

```java
public Map<String, Object> getReplicationMetrics() {
    Properties info = redis.execute((RedisCallback<Properties>) connection ->
        connection.info("replication")
    );

    Map<String, Object> metrics = new HashMap<>();
    metrics.put("role", info.getProperty("role"));

    if ("master".equals(info.getProperty("role"))) {
        metrics.put("connected_slaves",
            Integer.parseInt(info.getProperty("connected_slaves")));
    } else {
        metrics.put("master_link_status", info.getProperty("master_link_status"));
        metrics.put("master_last_io_seconds_ago",
            Integer.parseInt(info.getProperty("master_last_io_seconds_ago")));
    }

    return metrics;
}
```

## 告警规则

### 1. 性能告警

```java
@Component
public class PerformanceAlerting {
    @Autowired
    private RedisMetricsCollector metrics;

    @Scheduled(fixedRate = 60000)  // 每分钟
    public void checkPerformance() {
        // QPS过高
        long qps = metrics.getQPS();
        if (qps > 50000) {
            sendAlert("QPS告警", String.format("当前QPS: %d", qps));
        }

        // 延迟过高
        long latency = metrics.getLatency();
        if (latency > 100) {
            sendAlert("延迟告警", String.format("当前延迟: %dms", latency));
        }

        // 命中率过低
        double hitRate = metrics.getHitRate();
        if (hitRate < 80) {
            sendAlert("命中率告警", String.format("当前命中率: %.2f%%", hitRate));
        }

        // 慢查询过多
        long slowlogCount = metrics.getSlowlogCount();
        if (slowlogCount > 100) {
            sendAlert("慢查询告警", String.format("慢查询数量: %d", slowlogCount));
        }
    }

    private void sendAlert(String title, String message) {
        log.warn("{}: {}", title, message);
        // 发送钉钉/邮件/短信告警
    }
}
```

### 2. 资源告警

```java
@Scheduled(fixedRate = 60000)
public void checkResources() {
    // 内存使用
    Map<String, Object> memMetrics = metrics.getMemoryMetrics();
    long usedMemory = (long) memMetrics.get("used_memory");
    long maxMemory = 4L * 1024 * 1024 * 1024;  // 4GB

    if (usedMemory > maxMemory * 0.9) {
        sendAlert("内存告警",
            String.format("内存使用: %dMB / %dMB",
                usedMemory / 1024 / 1024, maxMemory / 1024 / 1024));
    }

    // 内存碎片率
    double fragRatio = (double) memMetrics.get("mem_fragmentation_ratio");
    if (fragRatio > 1.5) {
        sendAlert("内存碎片告警", String.format("碎片率: %.2f", fragRatio));
    }

    // 连接数
    Map<String, Long> connMetrics = metrics.getConnectionMetrics();
    long connectedClients = connMetrics.get("connected_clients");
    if (connectedClients > 1000) {
        sendAlert("连接数告警", String.format("当前连接数: %d", connectedClients));
    }
}
```

### 3. 可用性告警

```java
@Scheduled(fixedRate = 10000)  // 每10秒
public void checkAvailability() {
    try {
        // 健康检查
        redis.opsForValue().get("health_check");
    } catch (Exception e) {
        sendAlert("Redis不可用", e.getMessage());
    }

    // 主从复制状态
    Map<String, Object> replMetrics = metrics.getReplicationMetrics();
    if ("slave".equals(replMetrics.get("role"))) {
        String linkStatus = (String) replMetrics.get("master_link_status");
        if (!"up".equals(linkStatus)) {
            sendAlert("主从复制断开", "master_link_status: " + linkStatus);
        }

        int lastIO = (int) replMetrics.get("master_last_io_seconds_ago");
        if (lastIO > 60) {
            sendAlert("主从复制延迟",
                String.format("最后同步时间: %d秒前", lastIO));
        }
    }
}
```

## Prometheus + Grafana监控

### 1. 安装Redis Exporter

```bash
docker run -d \
  --name redis-exporter \
  -p 9121:9121 \
  oliver006/redis_exporter:latest \
  --redis.addr=redis://redis:6379
```

### 2. Prometheus配置

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'redis'
    static_configs:
      - targets: ['redis-exporter:9121']
```

### 3. Grafana Dashboard

导入官方Dashboard：
- ID: 763（Redis Overview）
- ID: 11835（Redis Cluster）

### 4. 告警规则

```yaml
# redis-alerts.yml
groups:
  - name: redis
    interval: 60s
    rules:
      # 内存使用超过90%
      - alert: RedisMemoryHigh
        expr: redis_memory_used_bytes / redis_memory_max_bytes > 0.9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Redis内存使用过高"
          description: "{{ $labels.instance }} 内存使用 {{ $value | humanizePercentage }}"

      # Redis宕机
      - alert: RedisDown
        expr: redis_up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Redis实例宕机"
          description: "{{ $labels.instance }} 已宕机"

      # 主从复制断开
      - alert: RedisMasterLinkDown
        expr: redis_master_link_up == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "主从复制断开"
          description: "{{ $labels.instance }} 主从复制断开"

      # 命中率低
      - alert: RedisHitRateLow
        expr: redis_keyspace_hits_total / (redis_keyspace_hits_total + redis_keyspace_misses_total) < 0.8
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Redis命中率过低"
          description: "{{ $labels.instance }} 命中率 {{ $value | humanizePercentage }}"
```

## 自定义监控面板

```java
@RestController
@RequestMapping("/api/redis/metrics")
public class RedisMetricsController {
    @Autowired
    private RedisMetricsCollector metrics;

    @GetMapping("/dashboard")
    public Map<String, Object> getDashboard() {
        Map<String, Object> dashboard = new HashMap<>();

        // 性能指标
        dashboard.put("qps", metrics.getQPS());
        dashboard.put("latency", metrics.getLatency());
        dashboard.put("hit_rate", metrics.getHitRate());

        // 资源指标
        dashboard.put("memory", metrics.getMemoryMetrics());
        dashboard.put("cpu", metrics.getCPUUsage());
        dashboard.put("connections", metrics.getConnectionMetrics());

        // 持久化指标
        dashboard.put("persistence", metrics.getPersistenceMetrics());

        // 复制指标
        dashboard.put("replication", metrics.getReplicationMetrics());

        return dashboard;
    }

    @GetMapping("/health")
    public Map<String, String> health() {
        Map<String, String> health = new HashMap<>();

        try {
            redis.opsForValue().get("health_check");
            health.put("status", "UP");
        } catch (Exception e) {
            health.put("status", "DOWN");
            health.put("error", e.getMessage());
        }

        return health;
    }
}
```

## 日志监控

```java
@Aspect
@Component
public class RedisOperationLogger {
    @Around("execution(* org.springframework.data.redis.core.RedisTemplate.*(..))")
    public Object logOperation(ProceedingJoinPoint pjp) throws Throwable {
        String method = pjp.getSignature().getName();
        long start = System.currentTimeMillis();

        try {
            Object result = pjp.proceed();
            long duration = System.currentTimeMillis() - start;

            // 记录慢操作
            if (duration > 100) {
                log.warn("Redis慢操作: method={}, duration={}ms",
                    method, duration);
            }

            return result;
        } catch (Exception e) {
            log.error("Redis操作异常: method={}, error={}",
                method, e.getMessage());
            throw e;
        }
    }
}
```

## 监控清单

### 必须监控的指标

- [ ] **可用性**：Redis是否可连接
- [ ] **QPS**：每秒查询数
- [ ] **延迟**：命令执行延迟
- [ ] **内存使用率**：used_memory / maxmemory
- [ ] **命中率**：hits / (hits + misses)
- [ ] **连接数**：connected_clients
- [ ] **慢查询**：slowlog长度

### 建议监控的指标

- [ ] 内存碎片率
- [ ] CPU使用率
- [ ] 网络流量
- [ ] 淘汰key数量
- [ ] 主从复制状态
- [ ] 持久化状态
- [ ] 阻塞客户端数量

### 告警阈值建议

| 指标 | 告警阈值 | 严重级别 |
|------|---------|---------|
| 可用性 | DOWN | Critical |
| QPS | > 50000 | Warning |
| 延迟 | > 100ms | Warning |
| 内存使用 | > 90% | Warning |
| 命中率 | < 80% | Warning |
| 慢查询 | > 100 | Warning |
| 主从复制 | DOWN | Critical |

## 总结

**监控指标**：
- 性能：QPS、延迟、命中率
- 资源：内存、CPU、连接数
- 可用性：健康检查、主从状态

**告警规则**：
- 性能告警：QPS、延迟、慢查询
- 资源告警：内存、连接数
- 可用性告警：宕机、主从断开

**监控工具**：
- Prometheus + Grafana（推荐）
- Redis Exporter
- 自定义监控面板

**最佳实践**：
- 设置合理的告警阈值
- 多级告警（Warning/Critical）
- 告警收敛（避免告警风暴）
- 定期review告警规则
