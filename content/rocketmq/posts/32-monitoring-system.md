---
title: "RocketMQ生产02：监控体系搭建 - Prometheus + Grafana 实战"
date: 2025-11-15T08:00:00+08:00
draft: false
tags: ["RocketMQ", "监控", "Prometheus", "Grafana"]
categories: ["技术"]
description: "从零搭建 RocketMQ 监控体系，实现故障秒级发现和可视化分析"
series: ["RocketMQ从入门到精通"]
weight: 32
stage: 4
stageTitle: "生产实践篇"
---

## 引言：没有监控的生产环境是裸奔

凌晨 3 点，手机疯狂震动，告警短信轰炸："RocketMQ 消息堆积 100 万条！"你迅速爬起来，打开电脑，却不知道从哪里开始排查...

**这就是没有监控的痛**：
- ❌ 故障发现滞后，用户先于运维发现问题
- ❌ 排查无从下手，缺少历史数据
- ❌ 性能瓶颈不可见，容量规划靠猜
- ❌ 告警不及时，小问题变大故障

**本文目标**：
- ✅ 搭建完整的 RocketMQ 监控体系
- ✅ 实现核心指标的可视化
- ✅ 配置智能告警规则
- ✅ 掌握故障排查方法

---

## 一、监控体系架构

### 1.1 整体架构图

```
┌─────────────────────────────────────────────────────────┐
│                    RocketMQ 集群                        │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐              │
│  │ Broker-A │  │ Broker-B │  │ Broker-C │              │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘              │
│       │             │             │                     │
│       └─────────────┼─────────────┘                     │
│                     │                                   │
│              ┌──────▼──────┐                            │
│              │  Exporter   │  ← 暴露 Prometheus 指标    │
│              └──────┬──────┘                            │
└─────────────────────┼────────────────────────────────────┘
                      │
               ┌──────▼──────┐
               │ Prometheus  │  ← 采集、存储、查询
               └──────┬──────┘
                      │
        ┌─────────────┼─────────────┐
        │             │             │
 ┌──────▼──────┐ ┌───▼────┐ ┌──────▼──────┐
 │  Grafana    │ │AlertMgr│ │   其他工具   │
 │ (可视化)    │ │(告警)  │ │  (日志等)   │
 └─────────────┘ └────────┘ └─────────────┘
```

### 1.2 核心组件

| 组件 | 作用 | 端口 |
|------|------|------|
| **RocketMQ Exporter** | 采集 RocketMQ 指标，暴露给 Prometheus | 5557 |
| **Prometheus** | 时序数据库，存储监控指标 | 9090 |
| **Grafana** | 可视化平台，展示监控大盘 | 3000 |
| **AlertManager** | 告警管理，通知到钉钉/邮件/微信 | 9093 |

---

## 二、安装部署

### 2.1 安装 Prometheus

```bash
# 1. 下载 Prometheus
cd /opt
wget https://github.com/prometheus/prometheus/releases/download/v2.45.0/prometheus-2.45.0.linux-amd64.tar.gz
tar -xzf prometheus-2.45.0.linux-amd64.tar.gz
mv prometheus-2.45.0.linux-amd64 prometheus

# 2. 配置 Prometheus
cd prometheus
cat > prometheus.yml <<EOF
global:
  scrape_interval: 15s        # 采集间隔
  evaluation_interval: 15s    # 告警规则评估间隔

# 采集任务配置
scrape_configs:
  # Prometheus 自身监控
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # RocketMQ 监控
  - job_name: 'rocketmq'
    static_configs:
      - targets: ['192.168.1.100:5557']  # Exporter 地址
        labels:
          cluster: 'rocketmq-prod'
          env: 'production'
EOF

# 3. 启动 Prometheus
nohup ./prometheus --config.file=prometheus.yml \
  --storage.tsdb.path=./data \
  --web.listen-address=:9090 > prometheus.log 2>&1 &

# 4. 验证
curl http://localhost:9090/-/healthy
# 浏览器访问：http://your-ip:9090
```

---

### 2.2 安装 RocketMQ Exporter

```bash
# 1. 下载 Exporter
cd /opt
wget https://github.com/apache/rocketmq-exporter/releases/download/rocketmq-exporter-0.0.2/rocketmq-exporter-0.0.2-bin.tar.gz
tar -xzf rocketmq-exporter-0.0.2-bin.tar.gz
cd rocketmq-exporter-0.0.2

# 2. 配置 application.properties
cat > application.properties <<EOF
# RocketMQ NameServer 地址
rocketmq.config.namesrvAddr=192.168.1.100:9876;192.168.1.101:9876

# Exporter 监听端口
server.port=5557

# 采集指标的消费组（用于监控消费进度）
rocketmq.config.consumerGroups=consumer_group_1,consumer_group_2

# 是否启用 ACL（如果 RocketMQ 开启了 ACL）
rocketmq.config.enableACL=false
EOF

# 3. 启动 Exporter
nohup java -jar rocketmq-exporter-0.0.2.jar \
  --spring.config.location=application.properties > exporter.log 2>&1 &

# 4. 验证指标暴露
curl http://localhost:5557/metrics
```

**成功输出示例**：
```
# HELP rocketmq_broker_tps Broker TPS
# TYPE rocketmq_broker_tps gauge
rocketmq_broker_tps{brokerIP="192.168.1.100",cluster="DefaultCluster"} 1234.0

# HELP rocketmq_consumer_lag Consumer message lag
# TYPE rocketmq_consumer_lag gauge
rocketmq_consumer_lag{group="consumer_group_1",topic="order_topic"} 500.0
```

---

### 2.3 安装 Grafana

```bash
# 1. 安装 Grafana（CentOS）
sudo yum install -y https://dl.grafana.com/oss/release/grafana-10.0.3-1.x86_64.rpm

# 2. 启动 Grafana
sudo systemctl start grafana-server
sudo systemctl enable grafana-server

# 3. 访问 Grafana
# 浏览器访问：http://your-ip:3000
# 默认账号密码：admin / admin（首次登录会要求修改）
```

**配置 Prometheus 数据源**：
```
1. 登录 Grafana → Configuration → Data Sources
2. 点击 Add data source → 选择 Prometheus
3. 配置：
   - Name: RocketMQ-Prometheus
   - URL: http://localhost:9090
   - Access: Server（默认）
4. 点击 Save & Test
```

---

## 三、核心监控指标

### 3.1 Broker 监控指标

#### 3.1.1 TPS（每秒消息数）

**指标名称**：`rocketmq_broker_tps`

**查询语句**：
```promql
# 单个 Broker 的 TPS
rocketmq_broker_tps{brokerIP="192.168.1.100"}

# 集群总 TPS
sum(rocketmq_broker_tps)

# 按 Broker 分组统计
sum(rocketmq_broker_tps) by (brokerIP)
```

**告警规则**：
```yaml
# prometheus.yml
rule_files:
  - "alert_rules.yml"

# alert_rules.yml
groups:
  - name: rocketmq_alerts
    rules:
      - alert: BrokerTPSTooHigh
        expr: rocketmq_broker_tps > 50000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Broker TPS 过高"
          description: "Broker {{ $labels.brokerIP }} TPS 达到 {{ $value }}，超过阈值 50000"
```

---

#### 3.1.2 消息堆积量

**指标名称**：`rocketmq_consumer_lag`

**含义**：Consumer 未消费的消息数量

**查询语句**：
```promql
# 单个消费组的堆积量
rocketmq_consumer_lag{group="order_consumer_group"}

# 堆积量 > 10000 的消费组
rocketmq_consumer_lag > 10000

# 堆积趋势（过去 1 小时）
delta(rocketmq_consumer_lag[1h])
```

**告警规则**：
```yaml
- alert: MessageLagTooHigh
  expr: rocketmq_consumer_lag > 100000
  for: 10m
  labels:
    severity: critical
  annotations:
    summary: "消息严重堆积"
    description: "消费组 {{ $labels.group }} Topic {{ $labels.topic }} 堆积量 {{ $value }}"
```

---

#### 3.1.3 磁盘使用率

**指标名称**：`rocketmq_broker_commitlog_disk_ratio`

**查询语句**：
```promql
# 磁盘使用率
rocketmq_broker_commitlog_disk_ratio{brokerIP="192.168.1.100"} * 100

# 磁盘使用率 > 80% 的 Broker
rocketmq_broker_commitlog_disk_ratio * 100 > 80
```

**告警规则**：
```yaml
- alert: DiskUsageTooHigh
  expr: rocketmq_broker_commitlog_disk_ratio * 100 > 85
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "Broker 磁盘空间不足"
    description: "Broker {{ $labels.brokerIP }} 磁盘使用率 {{ $value }}%"
```

---

#### 3.1.4 消息发送成功率

**指标名称**：`rocketmq_producer_message_size`（总数）、`rocketmq_producer_message_error`（失败数）

**查询语句**：
```promql
# 成功率计算
(1 -
  rate(rocketmq_producer_message_error[5m]) /
  rate(rocketmq_producer_message_size[5m])
) * 100

# 失败率 > 1%
(rate(rocketmq_producer_message_error[5m]) /
 rate(rocketmq_producer_message_size[5m])) * 100 > 1
```

---

### 3.2 Consumer 监控指标

#### 3.2.1 消费 TPS

**指标名称**：`rocketmq_consumer_tps`

**查询语句**：
```promql
# 消费组的消费速度
rocketmq_consumer_tps{group="order_consumer_group"}

# 消费速度 < 生产速度（可能堆积）
rocketmq_consumer_tps < rocketmq_producer_tps
```

---

#### 3.2.2 消费延迟

**指标名称**：`rocketmq_consumer_latency`

**查询语句**：
```promql
# 平均消费延迟（毫秒）
rocketmq_consumer_latency{group="order_consumer_group"}

# 延迟 > 5 秒
rocketmq_consumer_latency > 5000
```

**告警规则**：
```yaml
- alert: ConsumerLatencyTooHigh
  expr: rocketmq_consumer_latency > 10000
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "消费延迟过高"
    description: "消费组 {{ $labels.group }} 延迟 {{ $value }}ms"
```

---

### 3.3 系统资源监控

#### 3.3.1 JVM 内存

**指标名称**：`jvm_memory_used_bytes`

**查询语句**：
```promql
# 堆内存使用量（MB）
jvm_memory_used_bytes{area="heap"} / 1024 / 1024

# 堆内存使用率
jvm_memory_used_bytes{area="heap"} /
jvm_memory_max_bytes{area="heap"} * 100
```

---

#### 3.3.2 GC 统计

**指标名称**：`jvm_gc_collection_seconds_count`

**查询语句**：
```promql
# 每分钟 GC 次数
rate(jvm_gc_collection_seconds_count[1m]) * 60

# Full GC 频率（每小时）
rate(jvm_gc_collection_seconds_count{gc="PS MarkSweep"}[1h]) * 3600
```

**告警规则**：
```yaml
- alert: FullGCTooFrequent
  expr: rate(jvm_gc_collection_seconds_count{gc="PS MarkSweep"}[1h]) * 3600 > 10
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Full GC 频率过高"
    description: "Broker {{ $labels.instance }} 每小时 Full GC {{ $value }} 次"
```

---

## 四、Grafana 可视化配置

### 4.1 导入 RocketMQ 监控大盘

**方式1：使用社区模板**

```
1. 访问 Grafana Labs：https://grafana.com/grafana/dashboards/
2. 搜索 "RocketMQ"
3. 找到 Dashboard ID：10477（RocketMQ Dashboard）
4. Grafana → Dashboards → Import
5. 输入 ID：10477 → Load
6. 选择 Prometheus 数据源 → Import
```

**方式2：手动创建 Panel**

```json
{
  "title": "Broker TPS",
  "targets": [
    {
      "expr": "sum(rocketmq_broker_tps) by (brokerIP)",
      "legendFormat": "{{brokerIP}}"
    }
  ],
  "type": "graph"
}
```

---

### 4.2 核心监控大盘

#### 4.2.1 集群概览大盘

**指标布局**：
```
┌─────────────────────────────────────────────┐
│  集群总 TPS    |  消息堆积总量  |  Broker数量 │
├─────────────────────────────────────────────┤
│         Broker TPS 趋势图（折线图）          │
├──────────────────┬──────────────────────────┤
│  各 Broker TPS   │   磁盘使用率（饼图）     │
├──────────────────┴──────────────────────────┤
│         消息堆积 Top 10（表格）              │
└─────────────────────────────────────────────┘
```

**Panel 配置示例**：

**集群总 TPS**（Single Stat）：
```json
{
  "targets": [{
    "expr": "sum(rocketmq_broker_tps)"
  }],
  "type": "stat",
  "options": {
    "colorMode": "value",
    "graphMode": "area"
  }
}
```

**Broker TPS 趋势**（Time Series）：
```json
{
  "targets": [{
    "expr": "sum(rocketmq_broker_tps) by (brokerIP)",
    "legendFormat": "{{brokerIP}}"
  }],
  "type": "timeseries",
  "fieldConfig": {
    "defaults": {
      "unit": "ops"
    }
  }
}
```

---

#### 4.2.2 消费监控大盘

**指标布局**：
```
┌─────────────────────────────────────────────┐
│  消费组数量    |  总堆积量      |  消费TPS    │
├─────────────────────────────────────────────┤
│      消费组堆积量 Top 10（柱状图）           │
├─────────────────────────────────────────────┤
│      消费延迟趋势（折线图）                  │
├─────────────────────────────────────────────┤
│      消费组详情（表格）                      │
└─────────────────────────────────────────────┘
```

**消费组堆积量 Top 10**（Bar Gauge）：
```json
{
  "targets": [{
    "expr": "topk(10, rocketmq_consumer_lag)",
    "legendFormat": "{{group}}-{{topic}}"
  }],
  "type": "bargauge",
  "options": {
    "orientation": "horizontal"
  }
}
```

---

#### 4.2.3 JVM 监控大盘

**堆内存使用率**（Gauge）：
```json
{
  "targets": [{
    "expr": "jvm_memory_used_bytes{area='heap'} / jvm_memory_max_bytes{area='heap'} * 100"
  }],
  "type": "gauge",
  "options": {
    "reduceOptions": {
      "values": false,
      "calcs": ["lastNotNull"]
    },
    "thresholds": {
      "steps": [
        { "value": 0, "color": "green" },
        { "value": 70, "color": "yellow" },
        { "value": 85, "color": "red" }
      ]
    }
  }
}
```

**GC 频率**（Time Series）：
```json
{
  "targets": [
    {
      "expr": "rate(jvm_gc_collection_seconds_count{gc='PS Scavenge'}[5m]) * 60",
      "legendFormat": "Young GC/min"
    },
    {
      "expr": "rate(jvm_gc_collection_seconds_count{gc='PS MarkSweep'}[5m]) * 60",
      "legendFormat": "Full GC/min"
    }
  ],
  "type": "timeseries"
}
```

---

## 五、告警配置

### 5.1 安装 AlertManager

```bash
# 1. 下载 AlertManager
cd /opt
wget https://github.com/prometheus/alertmanager/releases/download/v0.26.0/alertmanager-0.26.0.linux-amd64.tar.gz
tar -xzf alertmanager-0.26.0.linux-amd64.tar.gz
mv alertmanager-0.26.0.linux-amd64 alertmanager

# 2. 配置 AlertManager
cd alertmanager
cat > alertmanager.yml <<EOF
global:
  resolve_timeout: 5m

# 告警路由
route:
  group_by: ['alertname', 'cluster']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'dingtalk'

# 接收器配置
receivers:
  - name: 'dingtalk'
    webhook_configs:
      - url: 'http://localhost:8060/dingtalk/webhook1/send'
EOF

# 3. 启动 AlertManager
nohup ./alertmanager --config.file=alertmanager.yml > alertmanager.log 2>&1 &
```

---

### 5.2 配置钉钉告警

```bash
# 1. 安装 prometheus-webhook-dingtalk
wget https://github.com/timonwong/prometheus-webhook-dingtalk/releases/download/v2.1.0/prometheus-webhook-dingtalk-2.1.0.linux-amd64.tar.gz
tar -xzf prometheus-webhook-dingtalk-2.1.0.linux-amd64.tar.gz

# 2. 配置钉钉机器人
cat > dingtalk.yml <<EOF
targets:
  webhook1:
    url: https://oapi.dingtalk.com/robot/send?access_token=YOUR_TOKEN
    secret: YOUR_SECRET
EOF

# 3. 启动钉钉 Webhook
nohup ./prometheus-webhook-dingtalk --config.file=dingtalk.yml > dingtalk.log 2>&1 &
```

**钉钉机器人配置**：
```
1. 钉钉群 → 群设置 → 智能群助手 → 添加机器人 → 自定义
2. 安全设置：选择"加签"方式
3. 复制 Webhook 地址和加签密钥
4. 填入上述配置文件
```

---

### 5.3 核心告警规则

```yaml
# alert_rules.yml
groups:
  - name: rocketmq_critical
    interval: 30s
    rules:
      # 1. 消息严重堆积
      - alert: MessageLagCritical
        expr: rocketmq_consumer_lag > 1000000
        for: 10m
        labels:
          severity: critical
        annotations:
          summary: "消息严重堆积"
          description: "消费组 {{ $labels.group }} Topic {{ $labels.topic }} 堆积 {{ $value }} 条"

      # 2. Broker 不可用
      - alert: BrokerDown
        expr: up{job="rocketmq"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Broker 宕机"
          description: "Broker {{ $labels.instance }} 不可用"

      # 3. 磁盘空间告急
      - alert: DiskSpaceCritical
        expr: rocketmq_broker_commitlog_disk_ratio * 100 > 90
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "磁盘空间告急"
          description: "Broker {{ $labels.brokerIP }} 磁盘使用率 {{ $value }}%"

      # 4. 消费延迟过高
      - alert: ConsumerLatencyHigh
        expr: rocketmq_consumer_latency > 30000
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "消费延迟过高"
          description: "消费组 {{ $labels.group }} 延迟 {{ $value }}ms"

      # 5. Full GC 频繁
      - alert: FullGCFrequent
        expr: rate(jvm_gc_collection_seconds_count{gc="PS MarkSweep"}[5m]) * 60 > 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Full GC 频繁"
          description: "Broker {{ $labels.instance }} 每分钟 Full GC {{ $value }} 次"
```

---

## 六、实战案例

### 案例1：消息堆积告警处理

**告警内容**：
```
【严重】消息严重堆积
消费组：order_consumer_group
Topic：order_topic
堆积量：1,500,000 条
```

**排查步骤**：

1. **查看 Grafana 堆积趋势**：
   - 是突发堆积还是持续增长？
   - 消费 TPS 是否下降？

2. **检查 Consumer 状态**：
```bash
# 查看消费组详情
sh mqadmin consumerProgress -g order_consumer_group -n 127.0.0.1:9876
```

3. **分析原因**：
   - Consumer 实例数不足 → 扩容
   - Consumer 处理慢 → 优化业务逻辑
   - 下游服务故障 → 临时降级

4. **应急处理**：
```bash
# 临时扩容 Consumer（K8s）
kubectl scale deployment order-consumer --replicas=10

# 监控堆积量下降
watch -n 5 "curl -s 'http://prometheus:9090/api/v1/query?query=rocketmq_consumer_lag{group=\"order_consumer_group\"}' | jq '.data.result[0].value[1]'"
```

---

### 案例2：磁盘空间不足

**告警内容**：
```
【严重】磁盘空间告急
Broker：192.168.1.100
磁盘使用率：92%
```

**处理步骤**：

1. **确认磁盘使用情况**：
```bash
df -h /data/rocketmq/store
du -sh /data/rocketmq/store/*
```

2. **清理过期消息**（临时）：
```bash
# 缩短保留时间（谨慎操作）
# 修改 broker.conf
fileReservedTime=24  # 改为1天

# 重启 Broker
sh mqshutdown broker
sh mqbroker -c broker.conf &
```

3. **扩容磁盘**（长期）：
```bash
# 挂载新磁盘
# 迁移数据
# 更新配置
```

---

## 七、最佳实践

### 7.1 监控指标分级

| 级别 | 指标类型 | 告警方式 | 响应时间 |
|------|---------|---------|---------|
| **P0（致命）** | Broker宕机、磁盘满 | 电话+钉钉 | 5分钟内 |
| **P1（严重）** | 消息大量堆积、Full GC频繁 | 钉钉+短信 | 30分钟内 |
| **P2（警告）** | 磁盘使用率高、消费延迟 | 钉钉 | 1小时内 |
| **P3（提示）** | TPS波动、GC耗时增加 | 邮件 | 工作时间处理 |

---

### 7.2 大盘设计原则

1. **分层展示**：
   - 集群总览大盘（管理层）
   - Broker 详情大盘（运维层）
   - Consumer 监控大盘（业务层）

2. **关键指标突出**：
   - 使用颜色区分（绿/黄/红）
   - 重要指标放在顶部
   - 趋势图配合即时值

3. **可操作性**：
   - 添加链接跳转到详情
   - 集成日志查询入口
   - 提供常用 PromQL 模板

---

### 7.3 告警优化

**避免告警风暴**：
```yaml
# 分组聚合
route:
  group_by: ['alertname', 'cluster']
  group_wait: 30s        # 等待30s聚合同类告警
  group_interval: 5m     # 5分钟内同组告警只发一次
  repeat_interval: 4h    # 未恢复的告警4小时重复一次
```

**告警抑制**：
```yaml
# 当 Broker 宕机时，抑制其他告警
inhibit_rules:
  - source_match:
      alertname: 'BrokerDown'
    target_match_re:
      alertname: '.*'
    equal: ['instance']
```

---

## 八、总结

### 监控体系搭建清单

- [ ] 安装 Prometheus（端口 9090）
- [ ] 安装 RocketMQ Exporter（端口 5557）
- [ ] 配置 Prometheus 采集任务
- [ ] 安装 Grafana（端口 3000）
- [ ] 导入 RocketMQ 监控大盘
- [ ] 安装 AlertManager（端口 9093）
- [ ] 配置钉钉/邮件告警
- [ ] 编写核心告警规则
- [ ] 进行告警测试
- [ ] 编写监控运维文档

### 核心监控指标

```
Broker层：TPS、磁盘使用率、可用性
Consumer层：消费TPS、消息堆积、消费延迟
系统层：JVM内存、GC频率、CPU、网络
业务层：消息发送成功率、端到端延迟
```

### 告警级别

```
P0：Broker宕机、磁盘满       → 立即响应
P1：消息大量堆积、Full GC频繁 → 30分钟内
P2：性能下降、资源使用率高    → 1小时内
P3：趋势预警、优化建议        → 工作时间
```

---

**下一篇预告**：《性能调优指南 - JVM、OS、Broker 参数优化》，我们将深入讲解如何通过参数调优，榨干 RocketMQ 的性能极限。

**本文关键词**：`监控体系` `Prometheus` `Grafana` `告警配置`
