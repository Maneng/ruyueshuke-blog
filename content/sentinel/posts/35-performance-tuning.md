---
title: "性能调优：降低Sentinel开销"
date: 2025-11-21T16:49:00+08:00
draft: false
tags: ["Sentinel", "性能优化", "调优"]
categories: ["技术"]
series: ["Sentinel从入门到精通"]
weight: 35
stage: 7
stageTitle: "生产实践篇"
description: "优化Sentinel性能，降低对业务的影响"
---

## 性能开销分析

### Sentinel引入的开销

| 组件 | 开销 | 说明 |
|-----|-----|-----|
| Entry创建 | < 0.1ms | 创建Entry对象 |
| Slot Chain | < 0.2ms | 责任链处理 |
| 统计更新 | < 0.1ms | 滑动窗口更新 |
| **总开销** | **< 0.5ms** | 正常情况下 |

### 压测对比

```
无Sentinel：
- QPS: 10,000
- 平均RT: 10ms

有Sentinel：
- QPS: 9,800 (-2%)
- 平均RT: 10.4ms (+0.4ms)

结论：对性能影响< 5%
```

## 优化策略

### 1. 减少资源数量

```java
// ❌ 不推荐：每个URL都是资源
@SentinelResource(value = "/order/{id}")
public Order getOrder(@PathVariable Long id) { }

// ✅ 推荐：按模块定义资源
@SentinelResource(value = "orderQuery")
public Order getOrder(@PathVariable Long id) { }
```

### 2. 合并规则

```java
// ❌ 不推荐：100个资源，100条规则
for (String resource : resources) {
    FlowRule rule = new FlowRule();
    rule.setResource(resource);
    rule.setCount(1000);
    rules.add(rule);
}

// ✅ 推荐：按分组定义规则
FlowRule readRule = new FlowRule();
readRule.setResource("read_api");
readRule.setCount(10000);

FlowRule writeRule = new FlowRule();
writeRule.setResource("write_api");
writeRule.setCount(1000);
```

### 3. 禁用不必要的Slot

```java
public class CustomSlotChainBuilder implements SlotChainBuilder {
    @Override
    public ProcessorSlotChain build() {
        ProcessorSlotChain chain = new DefaultProcessorSlotChain();

        chain.addLast(new NodeSelectorSlot());
        chain.addLast(new ClusterBuilderSlot());
        chain.addLast(new StatisticSlot());
        // 不需要授权，不添加AuthoritySlot
        // chain.addLast(new AuthoritySlot());
        chain.addLast(new FlowSlot());
        chain.addLast(new DegradeSlot());

        return chain;
    }
}
```

### 4. 调整滑动窗口参数

```java
// 默认：2个窗口，1秒
// 适合QPS限流

// 高QPS场景：增加窗口数
SampleCountProperty.setSampleCount(4);  // 4个窗口
IntervalProperty.setInterval(1000);     // 1秒

// 低QPS场景：减少窗口数
SampleCountProperty.setSampleCount(1);  // 1个窗口
```

### 5. 使用异步模式

```java
// 同步模式
@SentinelResource("orderCreate")
public Order createOrder(OrderDTO dto) {
    return orderService.create(dto);
}

// 异步模式
@SentinelResource("orderCreate")
public CompletableFuture<Order> createOrderAsync(OrderDTO dto) {
    return CompletableFuture.supplyAsync(() -> orderService.create(dto));
}
```

## JVM参数优化

### 堆内存

```bash
# 合理设置堆内存，避免过度GC
-Xms2g -Xmx2g
-XX:MetaspaceSize=256m
-XX:MaxMetaspaceSize=512m
```

### GC调优

```bash
# 使用G1 GC
-XX:+UseG1GC
-XX:MaxGCPauseMillis=200
-XX:G1HeapRegionSize=16m

# GC日志
-Xloggc:logs/gc.log
-XX:+PrintGCDetails
-XX:+PrintGCDateStamps
```

### 线程池

```bash
# Tomcat线程池
server.tomcat.threads.max=200
server.tomcat.threads.min-spare=50
server.tomcat.accept-count=100
```

## 批量操作优化

### 批量检查

```java
// ❌ 不推荐：循环检查
for (Long productId : productIds) {
    Entry entry = SphU.entry("queryProduct");
    try {
        queryProduct(productId);
    } finally {
        entry.exit();
    }
}

// ✅ 推荐：批量检查一次
Entry entry = SphU.entry("queryProduct", EntryType.IN, productIds.size());
try {
    batchQueryProducts(productIds);
} finally {
    entry.exit();
}
```

## 缓存优化

### 规则缓存

```java
@Component
public class RuleCacheManager {

    private final LoadingCache<String, List<FlowRule>> ruleCache;

    public RuleCacheManager() {
        this.ruleCache = CacheBuilder.newBuilder()
            .maximumSize(1000)
            .expireAfterWrite(1, TimeUnit.MINUTES)
            .build(new CacheLoader<String, List<FlowRule>>() {
                @Override
                public List<FlowRule> load(String resource) {
                    return FlowRuleManager.getRules(resource);
                }
            });
    }

    public List<FlowRule> getRules(String resource) {
        try {
            return ruleCache.get(resource);
        } catch (ExecutionException e) {
            return Collections.emptyList();
        }
    }
}
```

## 监控性能指标

### 性能指标

```java
@Component
public class SentinelPerformanceMonitor {

    private final Timer entryTimer;

    public SentinelPerformanceMonitor(MeterRegistry registry) {
        this.entryTimer = Timer.builder("sentinel.entry.timer")
            .description("Sentinel entry execution time")
            .register(registry);
    }

    @Around("@annotation(sentinelResource)")
    public Object monitor(ProceedingJoinPoint pjp, SentinelResource sentinelResource) throws Throwable {
        return entryTimer.record(() -> {
            try {
                return pjp.proceed();
            } catch (Throwable e) {
                throw new RuntimeException(e);
            }
        });
    }
}
```

## 压测验证

### 压测脚本

```bash
#!/bin/bash
# 压测接口

# 无Sentinel
ab -n 100000 -c 100 http://localhost:8080/order/create

# 有Sentinel
# 修改代码添加@SentinelResource
ab -n 100000 -c 100 http://localhost:8080/order/create

# 对比结果
```

### 性能报告

```
压测结果对比：

指标          | 无Sentinel | 有Sentinel | 差异
-------------|-----------|-----------|------
QPS          | 10,245    | 10,087    | -1.5%
平均RT(ms)    | 9.76      | 9.91      | +1.5%
最大RT(ms)    | 45        | 48        | +6.7%
错误率        | 0%        | 0%        | 0%

结论：性能影响在可接受范围内（< 2%）
```

## 最佳实践

### 1. 资源粒度

```java
// ✅ 推荐：模块级资源
@SentinelResource("orderModule")

// ❌ 避免：方法级资源（太多）
@SentinelResource("orderService.createOrder")
@SentinelResource("orderService.updateOrder")
@SentinelResource("orderService.deleteOrder")
```

### 2. 规则数量

```java
// ✅ 推荐：< 100条规则
// 每个应用的规则总数控制在100条以内

// ❌ 避免：> 1000条规则
// 规则过多会影响性能
```

### 3. 统计窗口

```java
// 高QPS（> 1000）：使用更多窗口
SampleCountProperty.setSampleCount(4);

// 低QPS（< 100）：使用更少窗口
SampleCountProperty.setSampleCount(1);
```

### 4. 集群模式

```java
// 高流量场景使用集群模式
rule.setClusterMode(true);

// 低流量场景使用本地模式
rule.setClusterMode(false);
```

## 性能测试

### 测试用例

```java
@Test
public void testSentinelPerformance() {
    // 预热
    for (int i = 0; i < 10000; i++) {
        testEntry();
    }

    // 测试
    long start = System.currentTimeMillis();
    for (int i = 0; i < 100000; i++) {
        testEntry();
    }
    long cost = System.currentTimeMillis() - start;

    System.out.println("10万次Entry操作耗时：" + cost + "ms");
    System.out.println("平均耗时：" + (cost / 100000.0) + "ms");
}

private void testEntry() {
    try (Entry entry = SphU.entry("test")) {
        // 业务逻辑
    } catch (BlockException e) {
        // 限流
    }
}
```

## 总结

性能优化要点：
1. **减少资源数量**：按模块定义资源
2. **合并规则**：避免规则过多
3. **禁用不必要的Slot**：按需加载
4. **调整滑动窗口**：根据QPS调整
5. **JVM调优**：合理的堆大小和GC策略

**性能目标**：
- Entry开销 < 0.5ms
- 对业务影响 < 5%
- 规则数量 < 100条
- GC暂停 < 100ms

**验证方法**：
- 压测对比有无Sentinel的性能
- 监控Sentinel自身的性能指标
- 定期review规则数量和复杂度
