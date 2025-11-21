---
title: "规则持久化：Nacos、Apollo、Redis三种方案"
date: 2025-11-21T16:33:00+08:00
draft: false
tags: ["Sentinel", "规则持久化", "Nacos", "Apollo", "Redis"]
categories: ["技术"]
series: ["Sentinel从入门到精通"]
weight: 27
stage: 5
stageTitle: "框架集成篇"
description: "对比三种规则持久化方案，选择最适合的配置中心"
---

## 三种方案对比

| 方案 | 实时性 | 高可用 | 运维成本 | 适用场景 |
|-----|-------|-------|---------|---------|
| **Nacos** | 秒级 | 高 | 低 | 推荐，微服务首选 |
| **Apollo** | 秒级 | 高 | 中 | 已使用Apollo的项目 |
| **Redis** | 秒级 | 高 | 低 | 轻量级方案 |
| **文件** | 分钟级 | 低 | 高 | 不推荐生产使用 |

## 方案1：Nacos（推荐）

### 配置

```yaml
spring:
  cloud:
    sentinel:
      datasource:
        flow:
          nacos:
            server-addr: localhost:8848
            dataId: ${spring.application.name}-flow-rules
            groupId: SENTINEL_GROUP
            rule-type: flow
            namespace: dev
```

### Nacos中配置规则

```json
[
  {
    "resource": "orderCreate",
    "limitApp": "default",
    "grade": 1,
    "count": 1000,
    "strategy": 0,
    "controlBehavior": 0
  }
]
```

### 优点

- 与Spring Cloud Alibaba深度集成
- 支持配置热更新
- 提供Web控制台
- 支持灰度发布
- 支持多环境（namespace）

## 方案2：Apollo

### 添加依赖

```xml
<dependency>
    <groupId>com.alibaba.csp</groupId>
    <artifactId>sentinel-datasource-apollo</artifactId>
    <version>1.8.6</version>
</dependency>
```

### 配置

```yaml
spring:
  cloud:
    sentinel:
      datasource:
        flow:
          apollo:
            namespace-name: application
            flow-rules-key: sentinel.flow.rules
            default-flow-rule-value: "[]"
            rule-type: flow
```

### Apollo中配置

**Namespace**: application
**Key**: sentinel.flow.rules
**Value**:
```json
[
  {
    "resource": "orderCreate",
    "count": 1000,
    "grade": 1
  }
]
```

### 优点

- 企业级配置中心
- 完善的权限管理
- 配置版本管理
- 灰度发布
- 配置审计

## 方案3：Redis

### 添加依赖

```xml
<dependency>
    <groupId>com.alibaba.csp</groupId>
    <artifactId>sentinel-datasource-redis</artifactId>
    <version>1.8.6</version>
</dependency>
```

### 配置

```java
@Configuration
public class RedisDataSourceConfig {

    @PostConstruct
    public void initRules() {
        ReadableDataSource<String, List<FlowRule>> redisDataSource = new RedisDataSource<>(
            "redis://localhost:6379",
            "sentinel:flow:rules",
            "sentinel:flow:rules:channel",
            source -> JSON.parseArray(source, FlowRule.class)
        );

        FlowRuleManager.register2Property(redisDataSource.getProperty());
    }
}
```

### Redis中配置

```bash
# 设置规则
redis-cli> SET sentinel:flow:rules '[{"resource":"orderCreate","count":1000,"grade":1}]'

# 发布更新通知
redis-cli> PUBLISH sentinel:flow:rules:channel update
```

### 优点

- 轻量级，易部署
- 高性能
- Pub/Sub实时推送
- 适合小规模应用

## 方案4：文件（不推荐）

### 配置

```yaml
spring:
  cloud:
    sentinel:
      datasource:
        file:
          file: classpath:sentinel-rules.json
          rule-type: flow
```

### 缺点

- 不支持热更新
- 修改需要重启
- 不适合集群
- 只适合本地开发

## 推送模式 vs 拉取模式

### 拉取模式（Pull）

```java
// 定时从配置中心拉取规则
@Scheduled(fixedDelay = 30000)
public void refreshRules() {
    String rules = nacosConfigService.getConfig(dataId, group);
    FlowRuleManager.loadRules(JSON.parseArray(rules, FlowRule.class));
}
```

**缺点**：实时性差，延迟最多30秒

### 推送模式（Push）

```java
// 监听配置变更
nacosConfigService.addListener(dataId, group, new Listener() {
    @Override
    public void receiveConfigInfo(String configInfo) {
        FlowRuleManager.loadRules(JSON.parseArray(configInfo, FlowRule.class));
    }
});
```

**优点**：实时更新，秒级生效

## Dashboard持久化改造

### 问题

Dashboard推送规则到应用，应用重启后规则丢失。

### 解决方案

改造Dashboard，推送规则到配置中心。

```java
@Component
public class NacosFlowRulePublisher implements DynamicRulePublisher<List<FlowRuleEntity>> {

    @Autowired
    private ConfigService configService;

    @Override
    public void publish(String app, List<FlowRuleEntity> rules) throws Exception {
        String dataId = app + "-flow-rules";
        configService.publishConfig(
            dataId,
            "SENTINEL_GROUP",
            JSON.toJSONString(rules),
            ConfigType.JSON.getType()
        );
    }
}

@Component
public class NacosFlowRuleProvider implements DynamicRuleProvider<List<FlowRuleEntity>> {

    @Autowired
    private ConfigService configService;

    @Override
    public List<FlowRuleEntity> getRules(String appName) throws Exception {
        String dataId = appName + "-flow-rules";
        String rules = configService.getConfig(dataId, "SENTINEL_GROUP", 3000);
        return JSON.parseArray(rules, FlowRuleEntity.class);
    }
}
```

## 完整实战：Nacos方案

### 应用端配置

```yaml
# application.yml
spring:
  application:
    name: order-service
  cloud:
    nacos:
      config:
        server-addr: localhost:8848
        namespace: dev
    sentinel:
      transport:
        dashboard: localhost:8080
      datasource:
        flow:
          nacos:
            server-addr: localhost:8848
            dataId: ${spring.application.name}-flow-rules
            groupId: SENTINEL_GROUP
            rule-type: flow
            namespace: dev
        degrade:
          nacos:
            server-addr: localhost:8848
            dataId: ${spring.application.name}-degrade-rules
            groupId: SENTINEL_GROUP
            rule-type: degrade
            namespace: dev
        system:
          nacos:
            server-addr: localhost:8848
            dataId: ${spring.application.name}-system-rules
            groupId: SENTINEL_GROUP
            rule-type: system
            namespace: dev
```

### Nacos配置

**1. 流控规则（order-service-flow-rules）**

```json
[
  {
    "resource": "orderCreate",
    "limitApp": "default",
    "grade": 1,
    "count": 1000,
    "strategy": 0,
    "controlBehavior": 0,
    "clusterMode": false
  }
]
```

**2. 熔断规则（order-service-degrade-rules）**

```json
[
  {
    "resource": "callProductService",
    "grade": 0,
    "count": 1000,
    "timeWindow": 10,
    "minRequestAmount": 5,
    "slowRatioThreshold": 0.5
  }
]
```

**3. 系统规则（order-service-system-rules）**

```json
[
  {
    "highestCpuUsage": 0.8,
    "avgRt": 500,
    "maxThread": 50
  }
]
```

### 监听配置变更

```java
@Component
public class SentinelRuleListener {

    @PostConstruct
    public void init() {
        FlowRuleManager.register2Property(new SentinelProperty<List<FlowRule>>() {
            @Override
            public void addListener(PropertyListener<List<FlowRule>> listener) {
                // 监听规则变更
            }

            @Override
            public void removeListener(PropertyListener<List<FlowRule>> listener) {
            }

            @Override
            public boolean updateValue(List<FlowRule> newValue) {
                log.info("流控规则已更新：{}", newValue.size());
                return true;
            }
        });
    }
}
```

## 规则备份与恢复

```bash
#!/bin/bash
# 备份脚本

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backup/sentinel/$DATE"
mkdir -p $BACKUP_DIR

# 备份Nacos配置
for dataId in "order-service-flow-rules" "order-service-degrade-rules"; do
    curl "http://localhost:8848/nacos/v1/cs/configs?dataId=$dataId&group=SENTINEL_GROUP" \
      > $BACKUP_DIR/$dataId.json
done

echo "备份完成：$BACKUP_DIR"
```

## 总结

规则持久化方案选择：
1. **推荐Nacos**：与Spring Cloud Alibaba深度集成，开箱即用
2. **Apollo**：已使用Apollo的项目，企业级配置管理
3. **Redis**：轻量级方案，适合小规模应用
4. **文件**：仅用于本地开发测试

**关键要点**：
- 使用Push模式，实现秒级更新
- 改造Dashboard，推送规则到配置中心
- 定期备份规则，防止误删
- 监控规则变更，及时告警
