---
title: "网关流控：统一流量入口的防护"
date: 2025-11-21T16:15:00+08:00
draft: false
tags: ["Sentinel", "网关限流", "Spring Cloud Gateway", "API Gateway"]
categories: ["技术"]
series: ["Sentinel从入门到精通"]
weight: 21
stage: 4
stageTitle: "进阶特性篇"
description: "学习Sentinel在Spring Cloud Gateway中的集成，实现网关层的统一流控"
---

## 引言：为什么要在网关层做流控？

在微服务架构中，**API网关**是所有外部流量的统一入口：

```
         用户请求
            ↓
      【API Gateway】 ← 在这里做流控
            ↓
    ┌───────┴───────┐
    ↓               ↓
订单服务        商品服务
```

**为什么要在网关层做流控？**

1. **统一防护**：一处配置，保护所有后端服务
2. **提前拦截**：在流量进入内网之前就拦截，节省资源
3. **全局视角**：可以基于租户、API、IP等多维度限流
4. **安全防护**：防止DDoS攻击、CC攻击

**今天我们就来学习Sentinel在Spring Cloud Gateway中的集成和使用。**

---

## Spring Cloud Gateway + Sentinel集成

### 第一步：添加依赖

```xml
<!-- Spring Cloud Gateway -->
<dependency>
    <groupId>org.springframework.cloud</groupId>
    <artifactId>spring-cloud-starter-gateway</artifactId>
</dependency>

<!-- Sentinel Gateway适配器 -->
<dependency>
    <groupId>com.alibaba.csp</groupId>
    <artifactId>sentinel-spring-cloud-gateway-adapter</artifactId>
    <version>1.8.6</version>
</dependency>
```

### 第二步：配置Gateway

**application.yml**：

```yaml
spring:
  application:
    name: api-gateway
  cloud:
    gateway:
      routes:
        # 订单服务路由
        - id: order-service
          uri: lb://order-service
          predicates:
            - Path=/api/order/**
          filters:
            - StripPrefix=2

        # 商品服务路由
        - id: product-service
          uri: lb://product-service
          predicates:
            - Path=/api/product/**
          filters:
            - StripPrefix=2
```

### 第三步：配置Sentinel网关限流

```java
import com.alibaba.csp.sentinel.adapter.gateway.common.SentinelGatewayConstants;
import com.alibaba.csp.sentinel.adapter.gateway.common.api.ApiDefinition;
import com.alibaba.csp.sentinel.adapter.gateway.common.api.ApiPathPredicateItem;
import com.alibaba.csp.sentinel.adapter.gateway.common.api.ApiPredicateItem;
import com.alibaba.csp.sentinel.adapter.gateway.common.api.GatewayApiDefinitionManager;
import com.alibaba.csp.sentinel.adapter.gateway.common.rule.GatewayFlowRule;
import com.alibaba.csp.sentinel.adapter.gateway.common.rule.GatewayRuleManager;
import com.alibaba.csp.sentinel.adapter.gateway.sc.SentinelGatewayFilter;
import com.alibaba.csp.sentinel.adapter.gateway.sc.exception.SentinelGatewayBlockExceptionHandler;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.cloud.gateway.filter.GlobalFilter;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.http.codec.ServerCodecConfigurer;
import org.springframework.web.reactive.result.view.ViewResolver;

import javax.annotation.PostConstruct;
import java.util.*;

@Configuration
public class GatewaySentinelConfig {

    private final List<ViewResolver> viewResolvers;
    private final ServerCodecConfigurer serverCodecConfigurer;

    public GatewaySentinelConfig(ObjectProvider<List<ViewResolver>> viewResolversProvider,
                                 ServerCodecConfigurer serverCodecConfigurer) {
        this.viewResolvers = viewResolversProvider.getIfAvailable(Collections::emptyList);
        this.serverCodecConfigurer = serverCodecConfigurer;
    }

    /**
     * 配置Sentinel网关限流过滤器
     */
    @Bean
    @Order(Ordered.HIGHEST_PRECEDENCE)
    public GlobalFilter sentinelGatewayFilter() {
        return new SentinelGatewayFilter();
    }

    /**
     * 配置Sentinel网关限流异常处理器
     */
    @Bean
    @Order(Ordered.HIGHEST_PRECEDENCE)
    public SentinelGatewayBlockExceptionHandler sentinelGatewayBlockExceptionHandler() {
        return new SentinelGatewayBlockExceptionHandler(viewResolvers, serverCodecConfigurer);
    }

    /**
     * 初始化网关限流规则
     */
    @PostConstruct
    public void initGatewayRules() {
        Set<GatewayFlowRule> rules = new HashSet<>();

        // 规则1：订单服务限流 QPS 1000
        rules.add(new GatewayFlowRule("order-service")
                .setCount(1000)
                .setIntervalSec(1));

        // 规则2：商品服务限流 QPS 2000
        rules.add(new GatewayFlowRule("product-service")
                .setCount(2000)
                .setIntervalSec(1));

        GatewayRuleManager.loadRules(rules);
        System.out.println("✅ 网关限流规则已加载");
    }
}
```

---

## 网关限流的三种粒度

### 1. Route维度限流

**含义**：对整个路由进行限流。

**示例**：订单服务的所有接口总QPS不超过1000。

```java
GatewayFlowRule rule = new GatewayFlowRule("order-service") // Route ID
    .setCount(1000)
    .setIntervalSec(1);
```

### 2. API分组限流

**含义**：对一组API进行限流。

**示例**：订单查询类接口（`/order/query/**`）总QPS不超过500。

**第一步：定义API分组**：

```java
@PostConstruct
public void initCustomizedApis() {
    Set<ApiDefinition> definitions = new HashSet<>();

    // 定义订单查询API分组
    ApiDefinition orderQueryApi = new ApiDefinition("order_query_api")
        .setPredicateItems(new HashSet<ApiPredicateItem>() {{
            add(new ApiPathPredicateItem().setPattern("/api/order/query/**")
                .setMatchStrategy(SentinelGatewayConstants.URL_MATCH_STRATEGY_PREFIX));
        }});

    // 定义订单写API分组
    ApiDefinition orderWriteApi = new ApiDefinition("order_write_api")
        .setPredicateItems(new HashSet<ApiPredicateItem>() {{
            add(new ApiPathPredicateItem().setPattern("/api/order/create"));
            add(new ApiPathPredicateItem().setPattern("/api/order/cancel"));
        }});

    definitions.add(orderQueryApi);
    definitions.add(orderWriteApi);

    GatewayApiDefinitionManager.loadApiDefinitions(definitions);
    System.out.println("✅ API分组定义已加载");
}
```

**第二步：配置API分组限流规则**：

```java
Set<GatewayFlowRule> rules = new HashSet<>();

// 订单查询API限流 500 QPS
rules.add(new GatewayFlowRule("order_query_api")
        .setResourceMode(SentinelGatewayConstants.RESOURCE_MODE_CUSTOM_API_NAME)
        .setCount(500)
        .setIntervalSec(1));

// 订单写API限流 200 QPS
rules.add(new GatewayFlowRule("order_write_api")
        .setResourceMode(SentinelGatewayConstants.RESOURCE_MODE_CUSTOM_API_NAME)
        .setCount(200)
        .setIntervalSec(1));

GatewayRuleManager.loadRules(rules);
```

### 3. 参数限流

**含义**：根据请求参数进行限流。

**示例**：对特定用户ID限流。

```java
@PostConstruct
public void initParamFlowRules() {
    Set<GatewayFlowRule> rules = new HashSet<>();

    // 根据请求参数userId限流
    GatewayFlowRule rule = new GatewayFlowRule("order-service")
        .setCount(100) // 默认100 QPS
        .setIntervalSec(1);

    // 配置参数限流
    rule.setParamItem(new GatewayParamFlowItem()
        .setParseStrategy(SentinelGatewayConstants.PARAM_PARSE_STRATEGY_URL_PARAM) // 从URL参数提取
        .setFieldName("userId")); // 参数名

    rules.add(rule);
    GatewayRuleManager.loadRules(rules);
}
```

**效果**：

| 请求 | 限流阈值 |
|-----|---------|
| `/api/order/list?userId=1` | 100 QPS |
| `/api/order/list?userId=2` | 100 QPS |

---

## 实战案例：电商网关全方位防护

### 场景描述

电商API网关需要实现以下防护：

1. **全局限流**：网关总QPS不超过10000
2. **服务限流**：订单服务2000、商品服务3000、用户服务1000
3. **API分组限流**：写接口200、读接口1000
4. **热点限流**：秒杀商品单独限流5000
5. **IP黑名单**：封禁恶意IP

### 完整配置

```java
@Configuration
public class EcommerceGatewayConfig {

    @PostConstruct
    public void initAllRules() {
        // 1. 定义API分组
        initApiDefinitions();

        // 2. 配置限流规则
        initFlowRules();

        // 3. 配置IP黑名单
        initBlackList();
    }

    /**
     * 定义API分组
     */
    private void initApiDefinitions() {
        Set<ApiDefinition> definitions = new HashSet<>();

        // 写API分组
        ApiDefinition writeApi = new ApiDefinition("write_api")
            .setPredicateItems(new HashSet<ApiPredicateItem>() {{
                add(new ApiPathPredicateItem().setPattern("/api/order/create"));
                add(new ApiPathPredicateItem().setPattern("/api/order/cancel"));
                add(new ApiPathPredicateItem().setPattern("/api/payment/pay"));
            }});

        // 读API分组
        ApiDefinition readApi = new ApiDefinition("read_api")
            .setPredicateItems(new HashSet<ApiPredicateItem>() {{
                add(new ApiPathPredicateItem().setPattern("/api/order/query/**")
                    .setMatchStrategy(SentinelGatewayConstants.URL_MATCH_STRATEGY_PREFIX));
                add(new ApiPathPredicateItem().setPattern("/api/product/detail/**")
                    .setMatchStrategy(SentinelGatewayConstants.URL_MATCH_STRATEGY_PREFIX));
            }});

        // 秒杀API
        ApiDefinition seckillApi = new ApiDefinition("seckill_api")
            .setPredicateItems(new HashSet<ApiPredicateItem>() {{
                add(new ApiPathPredicateItem().setPattern("/api/seckill/**")
                    .setMatchStrategy(SentinelGatewayConstants.URL_MATCH_STRATEGY_PREFIX));
            }});

        definitions.add(writeApi);
        definitions.add(readApi);
        definitions.add(seckillApi);

        GatewayApiDefinitionManager.loadApiDefinitions(definitions);
    }

    /**
     * 配置限流规则
     */
    private void initFlowRules() {
        Set<GatewayFlowRule> rules = new HashSet<>();

        // 1. 服务级限流
        rules.add(new GatewayFlowRule("order-service").setCount(2000));
        rules.add(new GatewayFlowRule("product-service").setCount(3000));
        rules.add(new GatewayFlowRule("user-service").setCount(1000));

        // 2. API分组限流
        rules.add(new GatewayFlowRule("write_api")
            .setResourceMode(SentinelGatewayConstants.RESOURCE_MODE_CUSTOM_API_NAME)
            .setCount(200));

        rules.add(new GatewayFlowRule("read_api")
            .setResourceMode(SentinelGatewayConstants.RESOURCE_MODE_CUSTOM_API_NAME)
            .setCount(1000));

        // 3. 秒杀API特殊限流
        rules.add(new GatewayFlowRule("seckill_api")
            .setResourceMode(SentinelGatewayConstants.RESOURCE_MODE_CUSTOM_API_NAME)
            .setCount(5000)
            .setControlBehavior(RuleConstant.CONTROL_BEHAVIOR_WARM_UP) // Warm Up预热
            .setWarmUpPeriodSec(60)); // 预热60秒

        GatewayRuleManager.loadRules(rules);
        System.out.println("✅ 网关限流规则已加载");
    }

    /**
     * 配置IP黑名单
     */
    private void initBlackList() {
        // 通过自定义GatewayFilter实现
        // 这里只是示例，实际需要自定义实现
    }
}
```

---

## 自定义限流响应

### 默认响应

当请求被限流时，Sentinel Gateway默认返回：

```json
{
  "code": 429,
  "message": "Blocked by Sentinel"
}
```

### 自定义响应

```java
import com.alibaba.csp.sentinel.adapter.gateway.sc.callback.BlockRequestHandler;
import com.alibaba.csp.sentinel.adapter.gateway.sc.callback.GatewayCallbackManager;
import com.alibaba.csp.sentinel.slots.block.BlockException;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.web.reactive.function.server.ServerResponse;
import org.springframework.web.server.ServerWebExchange;
import reactor.core.publisher.Mono;

@Configuration
public class CustomBlockHandler {

    @PostConstruct
    public void initBlockHandler() {
        GatewayCallbackManager.setBlockHandler(new BlockRequestHandler() {
            @Override
            public Mono<ServerResponse> handleRequest(ServerWebExchange exchange, Throwable ex) {
                // 自定义限流响应
                String result = "{\n" +
                    "  \"code\": 429,\n" +
                    "  \"message\": \"请求过于频繁，请稍后重试\",\n" +
                    "  \"timestamp\": " + System.currentTimeMillis() + "\n" +
                    "}";

                return ServerResponse
                    .status(HttpStatus.TOO_MANY_REQUESTS)
                    .contentType(MediaType.APPLICATION_JSON)
                    .bodyValue(result);
            }
        });

        System.out.println("✅ 自定义限流响应已配置");
    }
}
```

---

## 网关流控最佳实践

### 1. 分层防护

```
第一层：网关全局限流（QPS 10000）
    ↓
第二层：服务级限流（订单2000、商品3000）
    ↓
第三层：API分组限流（读1000、写200）
    ↓
第四层：热点限流（秒杀5000）
    ↓
第五层：服务内部限流（接口级、方法级）
```

### 2. 预热机制

对于秒杀等突发流量场景，使用Warm Up预热：

```java
GatewayFlowRule rule = new GatewayFlowRule("seckill_api")
    .setCount(5000)
    .setControlBehavior(RuleConstant.CONTROL_BEHAVIOR_WARM_UP)
    .setWarmUpPeriodSec(60); // 60秒内从0逐步提升到5000
```

### 3. 限流降级组合

```java
// 限流规则
GatewayFlowRule flowRule = new GatewayFlowRule("order-service").setCount(2000);

// 熔断规则（需要在后端服务中配置）
DegradeRule degradeRule = new DegradeRule();
degradeRule.setResource("order-service");
degradeRule.setGrade(RuleConstant.DEGRADE_GRADE_RT);
degradeRule.setCount(1000);
```

### 4. 监控告警

**关键指标**：

```yaml
# Prometheus指标
gateway_pass_qps{route="order-service"}
gateway_block_qps{route="order-service"}
gateway_rt{route="order-service"}
```

**告警规则**：

```yaml
- alert: HighGatewayBlockRate
  expr: rate(gateway_block_qps[1m]) / rate(gateway_pass_qps[1m]) > 0.1
  annotations:
    summary: "网关限流比例超过10%"
```

---

## 网关流控 vs 服务内流控

### 对比

| 维度 | 网关流控 | 服务内流控 |
|-----|---------|-----------|
| **保护对象** | 整个网关/服务 | 单个接口/方法 |
| **限流粒度** | 粗（Route、API分组） | 细（方法级） |
| **拦截位置** | 网关层（外层） | 服务内部（内层） |
| **配置位置** | 网关配置 | 服务配置 |
| **适用场景** | 统一防护、提前拦截 | 精细控制 |

### 组合使用

```
外部流量
    ↓
【网关流控】 ← 第一道防线（粗粒度）
    ↓
【服务内流控】 ← 第二道防线（细粒度）
    ↓
业务逻辑
```

---

## 总结

本文我们学习了Sentinel在Spring Cloud Gateway中的集成和使用：

1. **网关流控的必要性**：统一入口、提前拦截、全局视角
2. **集成步骤**：添加依赖、配置Gateway、配置Sentinel
3. **三种限流粒度**：Route维度、API分组、参数限流
4. **实战案例**：电商网关的全方位防护（5层防护）
5. **自定义限流响应**：友好的错误提示
6. **最佳实践**：分层防护、预热机制、监控告警

**核心要点**：

> 网关流控是系统的"第一道防线"，它在流量进入内网之前就进行拦截，保护后端服务。与服务内限流结合，构成完整的流控体系。

**下一篇预告（第四阶段最后一篇）**：

我们将学习**动态规则配置**：
- 硬编码规则的问题
- Nacos配置中心集成
- Apollo配置中心集成
- 规则推送与拉取模式
- 配置热更新

让我们一起探索如何实现规则的动态管理！
