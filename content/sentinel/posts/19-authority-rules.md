---
title: "黑白名单与授权规则"
date: 2025-11-21T16:05:00+08:00
draft: false
tags: ["Sentinel", "授权规则", "黑白名单", "访问控制"]
categories: ["技术"]
series: ["Sentinel从入门到精通"]
weight: 19
stage: 4
stageTitle: "进阶特性篇"
description: "学习Sentinel的授权规则，实现基于黑白名单的访问控制"
---

## 引言：不是所有请求都应该被处理

在前面的文章中，我们学习了限流、熔断、系统保护、热点限流，它们都是**流量控制**的手段——控制流量的数量和速度。

但在实际生产中，还有另一种需求：**访问控制**。

> **场景1：恶意爬虫**
>
> 你的电商网站被某个爬虫疯狂抓取，虽然做了限流，但爬虫会换IP继续攻击。
>
> **需求**：将这个爬虫的IP拉黑，直接拒绝访问。

> **场景2：内部接口**
>
> 你有一个管理后台接口，只允许内网IP访问，外网IP不允许访问。
>
> **需求**：设置IP白名单，只允许特定IP访问。

> **场景3：VIP用户**
>
> 你的系统有普通用户和VIP用户，在流量高峰期，需要优先保证VIP用户的访问。
>
> **需求**：VIP用户不限流，普通用户限流。

这些场景都需要**授权规则（Authority Rule）**——根据调用来源决定是否允许访问。

---

## 授权规则的核心概念

### 什么是授权规则？

**授权规则**是Sentinel提供的**访问控制**机制，可以根据**调用来源（origin）**决定是否允许请求通过。

**核心要素**：

1. **调用来源（origin）**：标识请求来自哪里（如IP、用户ID、应用名）
2. **策略（strategy）**：黑名单或白名单
3. **限制应用（limitApp）**：具体的来源值列表

### 黑名单 vs 白名单

| 类型 | 策略 | 规则 | 适用场景 |
|-----|-----|-----|---------|
| **白名单** | AUTHORITY_WHITE | 只允许名单内的来源访问 | 内部接口、VIP服务 |
| **黑名单** | AUTHORITY_BLACK | 拒绝名单内的来源访问 | 封禁恶意用户、爬虫 |

### 工作流程

```
请求到达
    ↓
提取调用来源（origin）
    ↓
查找授权规则
    ↓
判断是否在黑/白名单中
    ↓
    ├─ 白名单：在名单内 → 通过，不在 → 拒绝
    └─ 黑名单：在名单内 → 拒绝，不在 → 通过
    ↓
返回结果
```

---

## 配置授权规则

### 基础配置：黑名单

```java
import com.alibaba.csp.sentinel.slots.block.authority.AuthorityRule;
import com.alibaba.csp.sentinel.slots.block.authority.AuthorityRuleManager;
import com.alibaba.csp.sentinel.slots.block.RuleConstant;

import java.util.ArrayList;
import java.util.List;

public class AuthorityRuleConfig {

    public static void initBlackListRule() {
        List<AuthorityRule> rules = new ArrayList<>();

        AuthorityRule rule = new AuthorityRule();
        rule.setResource("userInfo"); // 资源名
        rule.setStrategy(RuleConstant.AUTHORITY_BLACK); // 黑名单策略
        rule.setLimitApp("app1,app2"); // 黑名单列表（逗号分隔）

        rules.add(rule);
        AuthorityRuleManager.loadRules(rules);
        System.out.println("✅ 黑名单规则已加载：拒绝 app1, app2 访问");
    }
}
```

**配置说明**：

- `resource`：要保护的资源名称
- `strategy`：`AUTHORITY_BLACK`（黑名单）或 `AUTHORITY_WHITE`（白名单）
- `limitApp`：来源列表，逗号分隔（如"app1,app2,app3"）

### 基础配置：白名单

```java
public static void initWhiteListRule() {
    List<AuthorityRule> rules = new ArrayList<>();

    AuthorityRule rule = new AuthorityRule();
    rule.setResource("adminApi"); // 资源名
    rule.setStrategy(RuleConstant.AUTHORITY_WHITE); // 白名单策略
    rule.setLimitApp("admin-app,internal-service"); // 白名单列表

    rules.add(rule);
    AuthorityRuleManager.loadRules(rules);
    System.out.println("✅ 白名单规则已加载：仅允许 admin-app, internal-service 访问");
}
```

---

## 自定义调用来源解析

### 默认的origin解析

Sentinel默认的调用来源是**应用名称**，通过以下方式获取：

1. HTTP Header：`S-user`（可以自定义）
2. Dubbo RPC：从Dubbo attachment获取

### 自定义origin解析器

在实际项目中，我们通常需要根据**IP地址**、**用户ID**、**API Key**等来源进行授权控制。

**实现RequestOriginParser接口**：

```java
import com.alibaba.csp.sentinel.adapter.spring.webmvc.callback.RequestOriginParser;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;

import javax.servlet.http.HttpServletRequest;

/**
 * 自定义调用来源解析器
 */
@Component
public class CustomRequestOriginParser implements RequestOriginParser {

    @Override
    public String parseOrigin(HttpServletRequest request) {
        // 方式1：根据IP地址
        String ip = getClientIP(request);
        if (ip != null) {
            return "ip_" + ip;
        }

        // 方式2：根据API Key
        String apiKey = request.getHeader("X-API-Key");
        if (StringUtils.hasText(apiKey)) {
            return "apikey_" + apiKey;
        }

        // 方式3：根据用户ID
        String userId = request.getHeader("X-User-Id");
        if (StringUtils.hasText(userId)) {
            return "user_" + userId;
        }

        // 默认：未知来源
        return "unknown";
    }

    /**
     * 获取客户端真实IP
     */
    private String getClientIP(HttpServletRequest request) {
        String ip = request.getHeader("X-Forwarded-For");
        if (ip == null || ip.isEmpty() || "unknown".equalsIgnoreCase(ip)) {
            ip = request.getHeader("X-Real-IP");
        }
        if (ip == null || ip.isEmpty() || "unknown".equalsIgnoreCase(ip)) {
            ip = request.getRemoteAddr();
        }
        return ip;
    }
}
```

---

## 实战案例1：IP黑名单

### 场景描述

封禁恶意爬虫IP：`192.168.1.100`、`192.168.1.101`。

### 完整代码

#### 1. 自定义origin解析器

```java
@Component
public class IPOriginParser implements RequestOriginParser {

    @Override
    public String parseOrigin(HttpServletRequest request) {
        // 获取客户端IP
        String ip = getClientIP(request);
        return ip != null ? ip : "unknown";
    }

    private String getClientIP(HttpServletRequest request) {
        String ip = request.getHeader("X-Forwarded-For");
        if (ip == null || ip.isEmpty()) {
            ip = request.getHeader("X-Real-IP");
        }
        if (ip == null || ip.isEmpty()) {
            ip = request.getRemoteAddr();
        }
        // 处理多个IP的情况（X-Forwarded-For可能包含多个IP）
        if (ip != null && ip.contains(",")) {
            ip = ip.split(",")[0].trim();
        }
        return ip;
    }
}
```

#### 2. 配置IP黑名单规则

```java
@Configuration
public class IPBlackListConfig {

    @PostConstruct
    public void initIPBlackList() {
        List<AuthorityRule> rules = new ArrayList<>();

        AuthorityRule rule = new AuthorityRule();
        rule.setResource("productList"); // 保护商品列表接口
        rule.setStrategy(RuleConstant.AUTHORITY_BLACK); // 黑名单
        rule.setLimitApp("192.168.1.100,192.168.1.101"); // 封禁的IP列表

        rules.add(rule);
        AuthorityRuleManager.loadRules(rules);
        System.out.println("✅ IP黑名单已生效：192.168.1.100, 192.168.1.101");
    }
}
```

#### 3. Controller

```java
@RestController
@RequestMapping("/product")
public class ProductController {

    @GetMapping("/list")
    @SentinelResource(value = "productList", blockHandler = "handleBlock")
    public List<Product> getProductList() {
        // 查询商品列表
        return productService.list();
    }

    public List<Product> handleBlock(BlockException ex) {
        throw new RuntimeException("访问被拒绝");
    }
}
```

### 效果

| IP地址 | 访问结果 |
|--------|---------|
| 192.168.1.100 | ❌ 被拒绝 |
| 192.168.1.101 | ❌ 被拒绝 |
| 192.168.1.102 | ✅ 正常访问 |

---

## 实战案例2：内部接口白名单

### 场景描述

管理后台接口只允许内网IP访问：`10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`。

### 完整代码

#### 1. IP白名单检查器

```java
@Component
public class InternalIPChecker implements RequestOriginParser {

    private static final String[] INTERNAL_IP_PREFIXES = {
        "10.",        // 10.0.0.0/8
        "172.16.",    // 172.16.0.0/12
        "192.168."    // 192.168.0.0/16
    };

    @Override
    public String parseOrigin(HttpServletRequest request) {
        String ip = getClientIP(request);

        // 判断是否是内网IP
        if (ip != null && isInternalIP(ip)) {
            return "internal"; // 内网标识
        }

        return "external"; // 外网标识
    }

    private boolean isInternalIP(String ip) {
        for (String prefix : INTERNAL_IP_PREFIXES) {
            if (ip.startsWith(prefix)) {
                return true;
            }
        }
        return false;
    }

    private String getClientIP(HttpServletRequest request) {
        String ip = request.getHeader("X-Real-IP");
        if (ip == null || ip.isEmpty()) {
            ip = request.getRemoteAddr();
        }
        return ip;
    }
}
```

#### 2. 配置白名单规则

```java
@Configuration
public class AdminWhiteListConfig {

    @PostConstruct
    public void initAdminWhiteList() {
        List<AuthorityRule> rules = new ArrayList<>();

        AuthorityRule rule = new AuthorityRule();
        rule.setResource("adminApi"); // 保护管理接口
        rule.setStrategy(RuleConstant.AUTHORITY_WHITE); // 白名单
        rule.setLimitApp("internal"); // 只允许内网访问

        rules.add(rule);
        AuthorityRuleManager.loadRules(rules);
        System.out.println("✅ 管理接口白名单已生效：仅内网可访问");
    }
}
```

#### 3. Controller

```java
@RestController
@RequestMapping("/admin")
public class AdminController {

    @GetMapping("/users")
    @SentinelResource(value = "adminApi", blockHandler = "handleBlock")
    public List<User> getUsers() {
        return userService.list();
    }

    public List<User> handleBlock(BlockException ex) {
        throw new RuntimeException("仅限内网访问");
    }
}
```

### 效果

| IP地址 | 类型 | 访问结果 |
|--------|-----|---------|
| 10.0.1.10 | 内网 | ✅ 正常访问 |
| 192.168.1.20 | 内网 | ✅ 正常访问 |
| 8.8.8.8 | 外网 | ❌ 被拒绝 |

---

## 实战案例3：VIP用户免限流

### 场景描述

- VIP用户：不限流
- 普通用户：QPS限流1000

### 完整代码

#### 1. 用户类型解析器

```java
@Component
public class UserTypeOriginParser implements RequestOriginParser {

    @Override
    public String parseOrigin(HttpServletRequest request) {
        // 从Header或Token中获取用户类型
        String userType = request.getHeader("X-User-Type");

        if ("vip".equalsIgnoreCase(userType)) {
            return "vip";
        }

        return "normal";
    }
}
```

#### 2. 配置规则

```java
@Configuration
public class UserTypeRuleConfig {

    @PostConstruct
    public void initUserTypeRules() {
        // 1. 授权规则：VIP用户白名单（不走限流）
        List<AuthorityRule> authRules = new ArrayList<>();
        AuthorityRule authRule = new AuthorityRule();
        authRule.setResource("orderCreate");
        authRule.setStrategy(RuleConstant.AUTHORITY_WHITE);
        authRule.setLimitApp("vip"); // VIP用户白名单
        authRules.add(authRule);
        AuthorityRuleManager.loadRules(authRules);

        // 2. 限流规则：普通用户限流
        List<FlowRule> flowRules = new ArrayList<>();
        FlowRule flowRule = new FlowRule();
        flowRule.setResource("orderCreate");
        flowRule.setGrade(RuleConstant.FLOW_GRADE_QPS);
        flowRule.setCount(1000);
        flowRule.setLimitApp("normal"); // 只对普通用户限流
        flowRules.add(flowRule);
        FlowRuleManager.loadRules(flowRules);

        System.out.println("✅ VIP用户规则已生效");
    }
}
```

### 效果

| 用户类型 | 访问结果 |
|---------|---------|
| VIP | ✅ 不限流 |
| 普通 | ⚠️ 限流1000 QPS |

---

## 最佳实践

### 1. 黑名单管理

**动态更新**：

```java
@Service
public class BlackListService {

    /**
     * 添加IP到黑名单
     */
    public void addToBlackList(String ip) {
        // 1. 获取当前规则
        List<AuthorityRule> rules = AuthorityRuleManager.getRules();

        // 2. 更新黑名单
        for (AuthorityRule rule : rules) {
            if ("productList".equals(rule.getResource())) {
                String limitApp = rule.getLimitApp();
                if (!limitApp.contains(ip)) {
                    rule.setLimitApp(limitApp + "," + ip);
                }
            }
        }

        // 3. 重新加载规则
        AuthorityRuleManager.loadRules(rules);
        System.out.println("✅ 已添加到黑名单：" + ip);
    }

    /**
     * 从黑名单移除IP
     */
    public void removeFromBlackList(String ip) {
        List<AuthorityRule> rules = AuthorityRuleManager.getRules();

        for (AuthorityRule rule : rules) {
            if ("productList".equals(rule.getResource())) {
                String limitApp = rule.getLimitApp();
                String newLimitApp = Arrays.stream(limitApp.split(","))
                    .filter(app -> !app.equals(ip))
                    .collect(Collectors.joining(","));
                rule.setLimitApp(newLimitApp);
            }
        }

        AuthorityRuleManager.loadRules(rules);
        System.out.println("✅ 已从黑名单移除：" + ip);
    }
}
```

### 2. 黑名单持久化

```java
@Service
public class BlackListPersistenceService {

    @Autowired
    private RedisTemplate<String, String> redisTemplate;

    private static final String BLACK_LIST_KEY = "sentinel:blacklist:ip";

    /**
     * 添加到黑名单（持久化到Redis）
     */
    public void addToBlackList(String ip) {
        // 1. 保存到Redis
        redisTemplate.opsForSet().add(BLACK_LIST_KEY, ip);

        // 2. 更新Sentinel规则
        updateSentinelRule();
    }

    /**
     * 从Redis加载黑名单
     */
    @PostConstruct
    public void loadBlackListFromRedis() {
        Set<String> blackList = redisTemplate.opsForSet().members(BLACK_LIST_KEY);
        if (blackList != null && !blackList.isEmpty()) {
            String limitApp = String.join(",", blackList);
            // 更新Sentinel规则
            // ...
        }
    }
}
```

### 3. 监控告警

```yaml
# Prometheus告警
- alert: HighAuthorityBlockRate
  expr: rate(sentinel_authority_block_total[1m]) > 100
  annotations:
    summary: "授权拦截频繁"
```

---

## 注意事项

### 1. 必须使用@SentinelResource

授权规则必须配合`@SentinelResource`使用。

### 2. origin不能为空

如果`RequestOriginParser`返回`null`或空字符串，授权规则不会生效。

### 3. 黑白名单不能同时使用

对于同一个资源，不能同时配置黑名单和白名单。

### 4. 性能考虑

- origin解析会在每次请求时调用，避免复杂的逻辑
- 黑白名单列表不要太长（建议<1000个）

---

## 总结

本文我们学习了Sentinel的授权规则：

1. **授权规则**：基于调用来源的访问控制
2. **黑白名单**：黑名单拒绝访问，白名单只允许访问
3. **自定义origin解析**：根据IP、用户ID、API Key等来源进行控制
4. **实战案例**：IP黑名单、内部接口白名单、VIP用户免限流
5. **最佳实践**：动态更新、持久化、监控告警

**核心要点**：

> 授权规则是Sentinel的"门卫"，它在流量进入系统之前就进行拦截，实现基于来源的访问控制。

**下一篇预告**：

我们将学习**集群流控**：
- 什么是集群流控？
- 为什么需要集群流控？
- Token Server和Token Client的架构
- 如何配置集群流控规则？

让我们一起探索跨实例的流量管理！
