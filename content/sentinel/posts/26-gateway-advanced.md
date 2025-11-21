---
title: "Gateway高级特性：自定义限流策略"
date: 2025-11-21T16:31:00+08:00
draft: false
tags: ["Sentinel", "Gateway", "自定义限流"]
categories: ["技术"]
series: ["Sentinel从入门到精通"]
weight: 26
stage: 5
stageTitle: "框架集成篇"
description: "深入Gateway流控，实现自定义限流策略"
---

## 自定义限流响应

### 方式1：自定义BlockExceptionHandler

```java
@Component
public class CustomGatewayBlockHandler implements BlockRequestHandler {

    @Override
    public Mono<ServerResponse> handleRequest(ServerWebExchange exchange, Throwable ex) {
        Map<String, Object> result = new HashMap<>();
        result.put("code", 429);
        result.put("message", "请求过于频繁，请稍后重试");
        result.put("timestamp", System.currentTimeMillis());

        if (ex instanceof FlowException) {
            result.put("reason", "触发限流");
        } else if (ex instanceof DegradeException) {
            result.put("reason", "触发熔断");
        }

        return ServerResponse
            .status(HttpStatus.TOO_MANY_REQUESTS)
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(result);
    }
}

@Configuration
public class GatewayConfig {
    @PostConstruct
    public void init() {
        GatewayCallbackManager.setBlockHandler(new CustomGatewayBlockHandler());
    }
}
```

### 方式2：根据路由返回不同响应

```java
@Component
public class RouteBasedBlockHandler implements BlockRequestHandler {

    @Override
    public Mono<ServerResponse> handleRequest(ServerWebExchange exchange, Throwable ex) {
        String routeId = exchange.getAttribute(ServerWebExchangeUtils.GATEWAY_PREDICATE_ROUTE_ATTR)
            .toString();

        Map<String, Object> result = new HashMap<>();
        result.put("code", 429);

        // 根据不同路由返回不同消息
        if ("order-service".equals(routeId)) {
            result.put("message", "订单服务繁忙，请稍后重试");
        } else if ("product-service".equals(routeId)) {
            result.put("message", "商品服务繁忙，请稍后重试");
        } else {
            result.put("message", "服务繁忙，请稍后重试");
        }

        return ServerResponse.status(HttpStatus.TOO_MANY_REQUESTS)
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(result);
    }
}
```

## 自定义限流算法

### 实现KeyResolver

```java
// 1. 基于IP的限流
@Component
public class IpKeyResolver implements KeyResolver {
    @Override
    public Mono<String> resolve(ServerWebExchange exchange) {
        return Mono.just(
            exchange.getRequest().getRemoteAddress()
                .getAddress().getHostAddress()
        );
    }
}

// 2. 基于用户ID的限流
@Component
public class UserKeyResolver implements KeyResolver {
    @Override
    public Mono<String> resolve(ServerWebExchange exchange) {
        return Mono.just(
            exchange.getRequest().getHeaders()
                .getFirst("X-User-Id")
        );
    }
}

// 3. 基于API Key的限流
@Component
public class ApiKeyResolver implements KeyResolver {
    @Override
    public Mono<String> resolve(ServerWebExchange exchange) {
        return Mono.just(
            exchange.getRequest().getHeaders()
                .getFirst("X-API-Key")
        );
    }
}
```

### 配置使用

```java
@Configuration
public class GatewayRateLimiterConfig {

    @Bean
    public KeyResolver ipKeyResolver() {
        return new IpKeyResolver();
    }

    @Bean
    public KeyResolver userKeyResolver() {
        return new UserKeyResolver();
    }
}

// 在路由中使用
@Bean
public RouteLocator customRouteLocator(RouteLocatorBuilder builder) {
    return builder.routes()
        .route("order-service", r -> r.path("/api/order/**")
            .filters(f -> f
                .stripPrefix(2)
                .requestRateLimiter(c -> c
                    .setRateLimiter(redisRateLimiter())
                    .setKeyResolver(ipKeyResolver())
                )
            )
            .uri("lb://order-service"))
        .build();
}
```

## 自定义过滤器

### 实现全局限流过滤器

```java
@Component
@Order(-1)
public class GlobalRateLimitFilter implements GlobalFilter {

    private final RedisTemplate<String, String> redisTemplate;

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        String ip = exchange.getRequest().getRemoteAddress()
            .getAddress().getHostAddress();

        String key = "rate_limit:" + ip;
        Long count = redisTemplate.opsForValue().increment(key);

        if (count == 1) {
            redisTemplate.expire(key, 1, TimeUnit.SECONDS);
        }

        if (count > 100) {  // 限流100 QPS
            exchange.getResponse().setStatusCode(HttpStatus.TOO_MANY_REQUESTS);
            return exchange.getResponse().setComplete();
        }

        return chain.filter(exchange);
    }
}
```

### 实现黑名单过滤器

```java
@Component
@Order(-2)
public class BlackListFilter implements GlobalFilter {

    private final Set<String> blackList = new ConcurrentHashSet<>();

    @PostConstruct
    public void init() {
        // 从Redis或数据库加载黑名单
        blackList.add("192.168.1.100");
        blackList.add("192.168.1.101");
    }

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        String ip = exchange.getRequest().getRemoteAddress()
            .getAddress().getHostAddress();

        if (blackList.contains(ip)) {
            exchange.getResponse().setStatusCode(HttpStatus.FORBIDDEN);
            return exchange.getResponse().setComplete();
        }

        return chain.filter(exchange);
    }

    public void addToBlackList(String ip) {
        blackList.add(ip);
    }

    public void removeFromBlackList(String ip) {
        blackList.remove(ip);
    }
}
```

## 动态路由

### 基于Nacos的动态路由

```java
@Component
public class DynamicRouteService implements ApplicationEventPublisherAware {

    @Autowired
    private RouteDefinitionWriter routeDefinitionWriter;

    private ApplicationEventPublisher publisher;

    @Override
    public void setApplicationEventPublisher(ApplicationEventPublisher applicationEventPublisher) {
        this.publisher = applicationEventPublisher;
    }

    public void add(RouteDefinition definition) {
        routeDefinitionWriter.save(Mono.just(definition)).subscribe();
        this.publisher.publishEvent(new RefreshRoutesEvent(this));
    }

    public void update(RouteDefinition definition) {
        try {
            this.routeDefinitionWriter.delete(Mono.just(definition.getId()));
        } catch (Exception e) {
            // ignore
        }
        routeDefinitionWriter.save(Mono.just(definition)).subscribe();
        this.publisher.publishEvent(new RefreshRoutesEvent(this));
    }

    public void delete(String id) {
        this.routeDefinitionWriter.delete(Mono.just(id)).subscribe();
        this.publisher.publishEvent(new RefreshRoutesEvent(this));
    }
}

@Component
public class NacosRouteListener {

    @Autowired
    private DynamicRouteService dynamicRouteService;

    @Autowired
    private NacosConfigManager nacosConfigManager;

    @PostConstruct
    public void init() throws Exception {
        String dataId = "gateway-routes";
        String group = "DEFAULT_GROUP";

        nacosConfigManager.getConfigService().addListener(dataId, group, new Listener() {
            @Override
            public void receiveConfigInfo(String configInfo) {
                // 解析路由配置并更新
                List<RouteDefinition> routes = JSON.parseArray(configInfo, RouteDefinition.class);
                routes.forEach(dynamicRouteService::update);
            }

            @Override
            public Executor getExecutor() {
                return null;
            }
        });
    }
}
```

## 完整实战案例

```java
@Configuration
public class GatewayAdvancedConfig {

    // 1. 自定义限流响应
    @PostConstruct
    public void initBlockHandler() {
        GatewayCallbackManager.setBlockHandler(new CustomGatewayBlockHandler());
    }

    // 2. 配置限流规则
    @PostConstruct
    public void initGatewayRules() {
        Set<GatewayFlowRule> rules = new HashSet<>();

        // 订单服务：QPS 1000 + Warm Up
        GatewayFlowRule orderRule = new GatewayFlowRule("order-service")
            .setCount(1000)
            .setControlBehavior(RuleConstant.CONTROL_BEHAVIOR_WARM_UP)
            .setWarmUpPeriodSec(60);
        rules.add(orderRule);

        // 商品服务：QPS 2000
        GatewayFlowRule productRule = new GatewayFlowRule("product-service")
            .setCount(2000);
        rules.add(productRule);

        // 秒杀API：QPS 5000
        GatewayFlowRule seckillRule = new GatewayFlowRule("seckill_api")
            .setResourceMode(SentinelGatewayConstants.RESOURCE_MODE_CUSTOM_API_NAME)
            .setCount(5000);
        rules.add(seckillRule);

        GatewayRuleManager.loadRules(rules);
    }

    // 3. 配置API分组
    @PostConstruct
    public void initCustomizedApis() {
        Set<ApiDefinition> definitions = new HashSet<>();

        // 秒杀API分组
        ApiDefinition seckillApi = new ApiDefinition("seckill_api")
            .setPredicateItems(new HashSet<ApiPredicateItem>() {{
                add(new ApiPathPredicateItem().setPattern("/api/seckill/**")
                    .setMatchStrategy(SentinelGatewayConstants.URL_MATCH_STRATEGY_PREFIX));
            }});

        definitions.add(seckillApi);
        GatewayApiDefinitionManager.loadApiDefinitions(definitions);
    }
}
```

## 总结

Gateway高级特性：
1. 自定义限流响应，返回友好提示
2. 实现KeyResolver，支持IP、用户、API Key等维度限流
3. 自定义全局过滤器，实现黑名单、速率限制
4. 动态路由，从Nacos加载路由配置
5. 多层防护：黑名单 → 限流 → 路由 → 后端服务
