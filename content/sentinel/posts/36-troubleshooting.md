---
title: "问题排查与故障处理"
date: 2025-11-20T16:51:00+08:00
draft: false
tags: ["Sentinel", "故障排查", "问题诊断"]
categories: ["技术"]
series: ["Sentinel从入门到精通"]
weight: 36
stage: 7
stageTitle: "生产实践篇"
description: "Sentinel常见问题排查和解决方案"
---

## 常见问题清单

### 1. 规则不生效

**问题**：配置了限流规则，但不生效。

**排查**：
```bash
# 1. 检查Dashboard连接
curl http://localhost:8719/api

# 2. 检查规则是否加载
curl http://localhost:8719/getRules?type=flow

# 3. 检查资源名是否一致
# Dashboard中的资源名 vs 代码中的资源名
```

**解决**：
```java
// 确保资源名完全一致
@SentinelResource(value = "orderCreate")  // 代码中
// Dashboard配置的资源名也必须是 "orderCreate"

// 检查规则加载
List<FlowRule> rules = FlowRuleManager.getRules();
System.out.println("规则数量：" + rules.size());
```

### 2. Dashboard看不到应用

**问题**：应用启动后，Dashboard看不到应用。

**排查**：
```yaml
# 检查配置
spring:
  cloud:
    sentinel:
      transport:
        dashboard: localhost:8080  # Dashboard地址
        port: 8719                 # 客户端端口
      eager: true                  # 立即初始化
```

**解决**：
```java
// 主动触发一次资源调用
@PostConstruct
public void init() {
    try {
        Entry entry = SphU.entry("sentinel-heartbeat");
        entry.exit();
    } catch (BlockException e) {
        // ignore
    }
}
```

### 3. 规则推送失败

**问题**：Dashboard推送规则失败。

**排查**：
```bash
# 检查网络连通性
telnet 192.168.1.100 8719

# 检查防火墙
iptables -L | grep 8719
```

**解决**：
```bash
# 开放8719端口
firewall-cmd --zone=public --add-port=8719/tcp --permanent
firewall-cmd --reload
```

### 4. 规则不持久化

**问题**：重启后规则丢失。

**解决**：
```yaml
# 配置Nacos数据源
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
```

### 5. 熔断器不恢复

**问题**：熔断器开启后不自动恢复。

**排查**：
```java
// 检查熔断规则配置
DegradeRule rule = new DegradeRule();
rule.setTimeWindow(10);  // 熔断时长10秒，确认是否配置
```

**解决**：
```java
// 确保熔断时长合理
rule.setTimeWindow(10);  // 10秒后自动恢复

// 检查探测请求是否成功
// 半开状态下，确保探测请求能成功
```

### 6. 限流不准确

**问题**：实际QPS超过限流阈值。

**原因**：
- 集群部署，每个实例独立限流
- 流量分布不均匀

**解决**：
```java
// 方案1：使用集群流控
FlowRule rule = new FlowRule();
rule.setClusterMode(true);

// 方案2：降低单实例阈值
// 3个实例，总QPS 3000
// 每个实例配置 3000 / 3 = 1000
rule.setCount(1000);
```

### 7. 内存泄漏

**问题**：长时间运行后内存持续增长。

**排查**：
```bash
# 生成堆转储
jmap -dump:live,format=b,file=heap.bin <pid>

# 分析堆转储
jhat heap.bin
```

**解决**：
```java
// 清理过期的统计数据
@Scheduled(fixedRate = 60000)
public void cleanUp() {
    // Sentinel会自动清理，无需手动
}

// 限制资源数量
// 避免动态创建过多资源
```

### 8. CPU占用过高

**问题**：Sentinel导致CPU占用过高。

**排查**：
```bash
# 查看线程堆栈
jstack <pid> | grep -A 10 "Sentinel"

# 查看CPU占用
top -Hp <pid>
```

**解决**：
```java
// 减少规则数量
// 调整滑动窗口大小
SampleCountProperty.setSampleCount(2);

// 禁用不必要的Slot
```

## 日志分析

### 开启Sentinel日志

```yaml
logging:
  level:
    com.alibaba.csp.sentinel: DEBUG

# 日志文件位置
# ${user.home}/logs/csp/sentinel-*.log
```

### 关键日志

```bash
# 限流日志
[2025-01-21 10:00:00] WARN - Block request: resource=orderCreate, origin=default

# 熔断日志
[2025-01-21 10:00:00] WARN - Circuit breaker opened: resource=callProductService

# 规则加载日志
[2025-01-21 10:00:00] INFO - Flow rules loaded: 10 rules
```

## 性能诊断

### JVM监控

```bash
# 查看GC情况
jstat -gcutil <pid> 1000

# 查看内存使用
jstat -gc <pid>

# 查看线程
jstat -threads <pid>
```

### Arthas诊断

```bash
# 启动Arthas
java -jar arthas-boot.jar

# 查看热点方法
dashboard

# 追踪方法调用
trace com.alibaba.csp.sentinel.Entry entry

# 查看Sentinel统计
sc -d com.alibaba.csp.sentinel.*
```

## 监控告警

### 关键指标

```yaml
# Prometheus告警规则
groups:
  - name: sentinel
    rules:
      - alert: SentinelRuleLoadFailed
        expr: sentinel_rule_load_failed > 0
        annotations:
          summary: "规则加载失败"

      - alert: SentinelHighBlockRate
        expr: rate(sentinel_block_qps[1m]) / rate(sentinel_pass_qps[1m]) > 0.2
        annotations:
          summary: "限流比例过高"
```

## 应急预案

### 紧急关闭Sentinel

```java
// 方式1：禁用所有规则
FlowRuleManager.loadRules(new ArrayList<>());
DegradeRuleManager.loadRules(new ArrayList<>());

// 方式2：配置开关
@ConditionalOnProperty(name = "sentinel.enabled", havingValue = "true")
public class SentinelConfig { }

# application.yml
sentinel.enabled=false
```

### 降级方案

```java
// 全局降级开关
@Component
public class GlobalFallback {

    private volatile boolean degradeAll = false;

    @Around("@annotation(sentinelResource)")
    public Object around(ProceedingJoinPoint pjp) throws Throwable {
        if (degradeAll) {
            // 全局降级，直接返回
            return null;
        }
        return pjp.proceed();
    }

    public void setDegradeAll(boolean degradeAll) {
        this.degradeAll = degradeAll;
    }
}
```

## 问题排查流程

```
发现问题
    ↓
1. 查看Dashboard监控
    ↓
2. 检查应用日志
    ↓
3. 检查规则配置
    ↓
4. 检查网络连通性
    ↓
5. 分析JVM状态
    ↓
6. 使用Arthas诊断
    ↓
定位根因
    ↓
制定解决方案
    ↓
验证修复效果
    ↓
总结文档
```

## 故障Case库

### Case 1：限流过度

**现象**：大量请求被限流，实际QPS远低于阈值。

**原因**：时钟回拨导致统计异常。

**解决**：
```bash
# 同步时钟
ntpdate ntp.aliyun.com

# 配置自动同步
crontab -e
0 * * * * ntpdate ntp.aliyun.com
```

### Case 2：Dashboard卡顿

**现象**：Dashboard页面卡顿，无响应。

**原因**：应用数量过多，Dashboard内存不足。

**解决**：
```bash
# 增加Dashboard内存
java -Xms2g -Xmx2g -jar sentinel-dashboard.jar
```

### Case 3：规则丢失

**现象**：Dashboard配置的规则突然消失。

**原因**：未配置持久化，Dashboard重启导致。

**解决**：配置Nacos持久化（见第22篇）。

## 总结

故障排查要点：
1. **日志分析**：查看Sentinel日志定位问题
2. **监控指标**：关注QPS、限流率、熔断状态
3. **规则检查**：确认规则配置正确
4. **网络诊断**：检查Dashboard连通性
5. **性能分析**：使用JVM工具和Arthas

**应急预案**：
- 准备降级开关，紧急时关闭Sentinel
- 配置规则持久化，避免规则丢失
- 建立故障Case库，快速定位问题
- 定期演练应急流程

**预防措施**：
- 完善监控告警
- 定期巡检规则配置
- 压测验证限流效果
- 建立变更审批流程
