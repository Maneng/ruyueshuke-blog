---
title: "降级规则与自定义降级处理"
date: 2025-11-21T15:40:00+08:00
draft: false
tags: ["Sentinel", "降级规则", "优雅降级"]
categories: ["技术"]
series: ["Sentinel从入门到精通"]
weight: 14
stage: 3
stageTitle: "熔断降级篇"
description: "学习配置降级规则和实现优雅的降级处理逻辑"
---

## 引言：降级不等于"失败"

在前面两篇文章中，我们学习了熔断的原理和三种熔断策略。我们知道，当熔断器开启时，Sentinel会**停止调用依赖服务，快速返回**。

但问题来了：**快速返回什么呢？**

很多初学者会认为：熔断就是"快速失败"，返回一个错误。

**这种理解是片面的！**

想象这样一个场景：

> 你在电商平台上浏览商品详情页。此时商品服务的推荐模块因为故障被熔断了。
>
> **糟糕的降级**：页面直接显示"服务异常，请稍后重试"
> - 用户体验差
> - 用户可能直接离开
> - 业务受损
>
> **优雅的降级**：推荐模块不显示，但商品详情、库存、价格等核心信息正常展示
> - 用户看不出异常
> - 核心功能不受影响
> - 业务损失最小

这就是**优雅降级**的艺术：**让系统在故障时仍然能提供有限但可用的服务**。

本文将深入讲解如何实现优雅的降级处理。

---

## 默认降级处理：快速失败

### Sentinel的默认行为

当熔断器开启时，Sentinel的**默认行为**是：

1. 拦截对资源的访问
2. 抛出`DegradeException`（继承自`BlockException`）
3. 业务代码需要捕获这个异常并处理

### 代码示例

```java
import com.alibaba.csp.sentinel.Entry;
import com.alibaba.csp.sentinel.SphU;
import com.alibaba.csp.sentinel.slots.block.BlockException;
import com.alibaba.csp.sentinel.slots.block.degrade.DegradeException;

public class DefaultFallbackDemo {

    public static void main(String[] args) {
        // 假设已经配置了熔断规则，并且熔断器已开启

        try (Entry entry = SphU.entry("queryProductDetail")) {
            // 业务逻辑：查询商品详情
            System.out.println("查询商品详情成功");
        } catch (DegradeException e) {
            // 熔断降级
            System.out.println("服务降级：" + e.getClass().getSimpleName());
        } catch (BlockException e) {
            // 其他限流、系统保护等
            System.out.println("被限流或保护：" + e.getClass().getSimpleName());
        }
    }
}
```

**输出**：

```
服务降级：DegradeException
```

### 默认处理的局限性

默认的降级处理有几个问题：

1. **用户体验差**：直接抛异常，没有友好的提示
2. **代码侵入性强**：每个地方都要写try-catch
3. **降级逻辑分散**：无法统一管理
4. **缺乏灵活性**：不能针对不同的资源做不同的处理

**我们需要更优雅的方案！**

---

## 方案一：@SentinelResource注解

Sentinel提供了`@SentinelResource`注解，可以**声明式**地配置降级处理。

### 基本用法

```java
import com.alibaba.csp.sentinel.annotation.SentinelResource;
import org.springframework.stereotype.Service;

@Service
public class ProductService {

    /**
     * 查询商品详情
     * @param productId 商品ID
     * @return 商品信息
     */
    @SentinelResource(
        value = "queryProductDetail",
        blockHandler = "handleBlock",  // 限流/熔断处理
        fallback = "handleFallback"     // 业务异常处理
    )
    public String queryProductDetail(Long productId) {
        // 模拟调用商品服务
        if (productId == null) {
            throw new IllegalArgumentException("商品ID不能为空");
        }

        // 实际业务逻辑
        return "商品详情：iPhone 15 Pro Max";
    }

    /**
     * 限流/熔断处理
     */
    public String handleBlock(Long productId, BlockException ex) {
        return "系统繁忙，请稍后重试（熔断或限流）";
    }

    /**
     * 业务异常处理
     */
    public String handleFallback(Long productId, Throwable ex) {
        return "查询失败：" + ex.getMessage();
    }
}
```

### blockHandler vs fallback

| 属性 | 作用 | 触发条件 | 典型场景 |
|-----|-----|---------|---------|
| `blockHandler` | 处理Sentinel的限流/熔断 | 抛出`BlockException`及其子类 | 熔断、限流、系统保护 |
| `fallback` | 处理业务异常 | 抛出除`BlockException`外的异常 | 业务逻辑异常、依赖服务异常 |

**两者可以同时配置**，Sentinel会根据异常类型选择对应的处理方法。

### 完整示例

```java
import com.alibaba.csp.sentinel.annotation.SentinelResource;
import com.alibaba.csp.sentinel.slots.block.BlockException;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

@Service
public class RecommendService {

    private final RestTemplate restTemplate;

    public RecommendService(RestTemplate restTemplate) {
        this.restTemplate = restTemplate;
    }

    /**
     * 获取推荐商品
     */
    @SentinelResource(
        value = "getRecommendProducts",
        blockHandler = "recommendBlockHandler",
        fallback = "recommendFallback"
    )
    public List<Product> getRecommendProducts(Long userId) {
        // 调用推荐服务
        String url = "http://recommend-service/api/recommend?userId=" + userId;
        return restTemplate.getForObject(url, List.class);
    }

    /**
     * 熔断降级处理：返回热门商品
     */
    public List<Product> recommendBlockHandler(Long userId, BlockException ex) {
        System.out.println("推荐服务熔断，返回热门商品");
        // 返回热门商品作为降级数据
        return getHotProducts();
    }

    /**
     * 异常降级处理：返回默认推荐
     */
    public List<Product> recommendFallback(Long userId, Throwable ex) {
        System.out.println("推荐服务异常，返回默认推荐");
        // 返回默认推荐
        return getDefaultRecommend();
    }

    private List<Product> getHotProducts() {
        // 从缓存或数据库获取热门商品
        return Arrays.asList(
            new Product(1L, "iPhone 15"),
            new Product(2L, "MacBook Pro")
        );
    }

    private List<Product> getDefaultRecommend() {
        // 返回空列表或默认推荐
        return Collections.emptyList();
    }
}
```

### 注意事项

1. **blockHandler方法签名**：
   - 参数：必须与原方法相同，最后加一个`BlockException`参数
   - 返回值：必须与原方法相同
   - 访问修饰符：可以是`public`或`private`
   - 位置：必须在同一个类中（或通过`blockHandlerClass`指定）

2. **fallback方法签名**：
   - 参数：必须与原方法相同，最后加一个`Throwable`参数
   - 返回值：必须与原方法相同
   - 访问修饰符：可以是`public`或`private`
   - 位置：必须在同一个类中（或通过`fallbackClass`指定）

---

## 方案二：全局异常处理器

对于Spring Boot项目，可以使用`BlockExceptionHandler`统一处理所有的限流/熔断异常。

### 自定义全局处理器

```java
import com.alibaba.csp.sentinel.adapter.spring.webmvc.callback.BlockExceptionHandler;
import com.alibaba.csp.sentinel.slots.block.BlockException;
import com.alibaba.csp.sentinel.slots.block.degrade.DegradeException;
import com.alibaba.csp.sentinel.slots.block.flow.FlowException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Component;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;

@Component
public class CustomBlockExceptionHandler implements BlockExceptionHandler {

    private final ObjectMapper objectMapper = new ObjectMapper();

    @Override
    public void handle(HttpServletRequest request,
                      HttpServletResponse response,
                      BlockException ex) throws Exception {

        // 设置响应类型
        response.setContentType("application/json;charset=UTF-8");
        response.setStatus(429); // Too Many Requests

        // 根据不同的异常类型，返回不同的信息
        Result result;
        if (ex instanceof FlowException) {
            result = Result.error(429, "请求过于频繁，请稍后重试");
        } else if (ex instanceof DegradeException) {
            result = Result.error(503, "服务降级，请稍后重试");
        } else {
            result = Result.error(500, "系统繁忙，请稍后重试");
        }

        // 记录日志
        System.out.println("请求被拦截：" + request.getRequestURI() +
                          ", 原因：" + ex.getClass().getSimpleName());

        // 返回JSON响应
        response.getWriter().write(objectMapper.writeValueAsString(result));
    }
}

/**
 * 统一返回结果
 */
class Result {
    private int code;
    private String message;
    private Object data;

    public static Result error(int code, String message) {
        Result result = new Result();
        result.code = code;
        result.message = message;
        return result;
    }

    // getters and setters
}
```

### 效果

当接口被熔断时，会返回JSON格式的友好提示：

```json
{
  "code": 503,
  "message": "服务降级，请稍后重试",
  "data": null
}
```

---

## 优雅降级的五种实践模式

### 1. 返回默认值

适用于查询类接口，返回一个安全的默认值。

```java
@SentinelResource(value = "getUserScore", blockHandler = "scoreBlockHandler")
public int getUserScore(Long userId) {
    // 调用积分服务
    return scoreService.getScore(userId);
}

public int scoreBlockHandler(Long userId, BlockException ex) {
    // 降级：返回默认积分0
    return 0;
}
```

### 2. 返回缓存数据

适用于数据变化不频繁的场景，返回缓存中的数据。

```java
@Service
public class ProductService {

    @Autowired
    private RedisTemplate<String, Product> redisTemplate;

    @SentinelResource(
        value = "getProductDetail",
        blockHandler = "productBlockHandler"
    )
    public Product getProductDetail(Long productId) {
        // 调用商品服务
        return productClient.getProduct(productId);
    }

    public Product productBlockHandler(Long productId, BlockException ex) {
        // 降级：返回Redis缓存数据
        String key = "product:" + productId;
        Product product = redisTemplate.opsForValue().get(key);

        if (product != null) {
            System.out.println("服务降级，返回缓存数据");
            return product;
        }

        // 缓存也没有，返回一个空对象
        Product emptyProduct = new Product();
        emptyProduct.setId(productId);
        emptyProduct.setName("商品信息暂时无法获取");
        return emptyProduct;
    }
}
```

### 3. 返回空集合/空对象

适用于非核心功能，降级时可以不展示。

```java
@SentinelResource(
    value = "getRecommendList",
    blockHandler = "recommendBlockHandler"
)
public List<Product> getRecommendList() {
    return recommendService.getList();
}

public List<Product> recommendBlockHandler(BlockException ex) {
    // 降级：返回空列表（推荐模块不展示）
    System.out.println("推荐服务降级，不展示推荐内容");
    return Collections.emptyList();
}
```

### 4. 返回静态数据

适用于营销类模块，返回预置的静态数据。

```java
@SentinelResource(
    value = "getBannerList",
    blockHandler = "bannerBlockHandler"
)
public List<Banner> getBannerList() {
    return bannerService.getList();
}

public List<Banner> bannerBlockHandler(BlockException ex) {
    // 降级：返回静态Banner图
    System.out.println("Banner服务降级，返回静态数据");
    return Arrays.asList(
        new Banner("默认活动1", "/images/default1.jpg"),
        new Banner("默认活动2", "/images/default2.jpg")
    );
}
```

### 5. 降级到本地服务

适用于有本地备份能力的场景。

```java
@SentinelResource(
    value = "queryOrderInfo",
    blockHandler = "orderBlockHandler"
)
public Order queryOrderInfo(Long orderId) {
    // 调用订单服务
    return orderClient.getOrder(orderId);
}

public Order orderBlockHandler(Long orderId, BlockException ex) {
    // 降级：查询本地数据库
    System.out.println("订单服务降级，查询本地数据库");
    return localOrderDao.findById(orderId);
}
```

---

## 实战案例：商品详情页的多层降级

### 场景描述

商品详情页包含多个模块：
1. **商品基本信息**（核心，不能降级）
2. **库存信息**（重要，降级显示"有货"）
3. **推荐商品**（非核心，降级不展示）
4. **用户评论**（非核心，降级不展示）

### 完整代码

```java
import com.alibaba.csp.sentinel.annotation.SentinelResource;
import com.alibaba.csp.sentinel.slots.block.BlockException;
import org.springframework.stereotype.Service;

@Service
public class ProductDetailService {

    /**
     * 获取商品详情（核心功能，不降级）
     */
    public ProductDetail getProductDetail(Long productId) {
        ProductDetail detail = new ProductDetail();

        // 1. 商品基本信息（必须成功）
        detail.setProduct(getProductInfo(productId));

        // 2. 库存信息（可降级）
        detail.setStock(getStockInfo(productId));

        // 3. 推荐商品（可降级）
        detail.setRecommendList(getRecommendProducts(productId));

        // 4. 用户评论（可降级）
        detail.setComments(getComments(productId));

        return detail;
    }

    /**
     * 获取商品基本信息（不使用Sentinel，不降级）
     */
    private Product getProductInfo(Long productId) {
        // 直接查询数据库，确保一定返回数据
        return productDao.findById(productId);
    }

    /**
     * 获取库存信息
     */
    @SentinelResource(
        value = "getStockInfo",
        blockHandler = "stockBlockHandler"
    )
    public StockInfo getStockInfo(Long productId) {
        // 调用库存服务
        return stockClient.getStock(productId);
    }

    public StockInfo stockBlockHandler(Long productId, BlockException ex) {
        // 降级：显示"有货"
        StockInfo stock = new StockInfo();
        stock.setAvailable(true);
        stock.setStockCount(-1); // -1表示未知库存
        stock.setMessage("有货");
        return stock;
    }

    /**
     * 获取推荐商品
     */
    @SentinelResource(
        value = "getRecommendProducts",
        blockHandler = "recommendBlockHandler"
    )
    public List<Product> getRecommendProducts(Long productId) {
        // 调用推荐服务
        return recommendClient.getRecommend(productId);
    }

    public List<Product> recommendBlockHandler(Long productId, BlockException ex) {
        // 降级：不展示推荐模块
        return Collections.emptyList();
    }

    /**
     * 获取用户评论
     */
    @SentinelResource(
        value = "getComments",
        blockHandler = "commentBlockHandler"
    )
    public List<Comment> getComments(Long productId) {
        // 调用评论服务
        return commentClient.getComments(productId);
    }

    public List<Comment> commentBlockHandler(Long productId, BlockException ex) {
        // 降级：不展示评论模块
        return Collections.emptyList();
    }
}
```

### 降级效果

**正常情况**：
```json
{
  "product": { "id": 1, "name": "iPhone 15" },
  "stock": { "available": true, "stockCount": 100 },
  "recommendList": [
    { "id": 2, "name": "AirPods Pro" },
    { "id": 3, "name": "Apple Watch" }
  ],
  "comments": [
    { "user": "张三", "content": "非常好用" }
  ]
}
```

**推荐服务熔断后**：
```json
{
  "product": { "id": 1, "name": "iPhone 15" },
  "stock": { "available": true, "stockCount": 100 },
  "recommendList": [],  ← 降级为空
  "comments": [
    { "user": "张三", "content": "非常好用" }
  ]
}
```

**库存服务熔断后**：
```json
{
  "product": { "id": 1, "name": "iPhone 15" },
  "stock": { "available": true, "stockCount": -1, "message": "有货" },  ← 降级为默认值
  "recommendList": [
    { "id": 2, "name": "AirPods Pro" }
  ],
  "comments": [
    { "user": "张三", "content": "非常好用" }
  ]
}
```

**用户体验**：
- 核心功能（商品信息）始终正常
- 部分模块降级对用户影响很小
- 页面不会白屏或报错

---

## 降级监控与告警

### 记录降级事件

可以在降级处理方法中记录日志，方便后续分析。

```java
public List<Product> recommendBlockHandler(Long userId, BlockException ex) {
    // 记录降级事件
    logger.warn("推荐服务降级 - userId: {}, 原因: {}",
                userId, ex.getClass().getSimpleName());

    // 上报监控指标
    monitorService.recordDegrade("recommend_service");

    // 返回降级数据
    return getHotProducts();
}
```

### 配置告警

可以使用监控平台（如Prometheus + Alertmanager）配置告警规则：

```yaml
# Prometheus告警规则示例
groups:
  - name: sentinel_degrade
    rules:
      - alert: HighDegradeRate
        expr: rate(sentinel_degrade_total[1m]) > 10
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Sentinel降级频繁"
          description: "服务 {{ $labels.resource }} 在过去5分钟内降级超过10次/秒"
```

### 降级统计

```java
@Component
public class DegradeStatistics {

    private final AtomicLong degradeCount = new AtomicLong(0);

    public void recordDegrade(String resource) {
        long count = degradeCount.incrementAndGet();
        System.out.println("降级统计 - " + resource + ": " + count + "次");
    }

    public long getDegradeCount() {
        return degradeCount.get();
    }

    public void reset() {
        degradeCount.set(0);
    }
}
```

---

## 最佳实践

### 1. 降级方案设计原则

- **核心功能不降级**：订单创建、支付扣款等核心业务不能降级
- **非核心功能优雅降级**：推荐、评论、营销模块等可以降级
- **降级有层次**：优先降级最不重要的模块
- **降级有后备**：降级方案要有数据兜底（缓存、默认值）

### 2. 降级数据来源

优先级（从高到低）：

1. **本地缓存**（Redis、Caffeine）
2. **静态数据**（配置文件、数据库）
3. **默认值**（空列表、0值、友好提示）
4. **什么都不展示**（对用户影响最小的方案）

### 3. 降级方法命名规范

```java
// 原方法：getRecommendProducts
// blockHandler：recommendProductsBlockHandler
// fallback：recommendProductsFallback

// 建议命名：{原方法名} + BlockHandler/Fallback
```

### 4. 降级测试

在上线前，一定要测试降级方案：

```java
@Test
public void testDegrade() {
    // 1. 配置熔断规则
    DegradeRule rule = new DegradeRule();
    rule.setResource("getRecommendProducts");
    rule.setGrade(RuleConstant.DEGRADE_GRADE_EXCEPTION_RATIO);
    rule.setCount(0.1); // 异常比例10%
    rule.setTimeWindow(10);
    DegradeRuleManager.loadRules(Collections.singletonList(rule));

    // 2. 模拟调用触发熔断
    for (int i = 0; i < 20; i++) {
        // 模拟20%异常率
        // ...
    }

    // 3. 验证降级方法被调用
    // 验证返回的是降级数据
}
```

---

## 总结

本文我们学习了如何实现优雅的降级处理：

1. **默认降级**：抛出`DegradeException`，需要手动捕获
2. **@SentinelResource注解**：声明式配置，支持`blockHandler`和`fallback`
3. **全局异常处理器**：统一处理所有的限流/熔断异常
4. **五种降级模式**：默认值、缓存、空对象、静态数据、本地服务
5. **实战案例**：商品详情页的多层降级方案
6. **监控告警**：记录降级事件、配置告警规则

**核心要点**：

> 降级不是简单的"失败"，而是一种"优雅的后备方案"。好的降级设计能让系统在故障时仍然提供有限但可用的服务，最大程度降低业务损失。

**下一篇预告**：

我们将深入学习**熔断恢复机制**：
- 半开状态是如何工作的？
- 探测请求是如何选择的？
- 恢复条件是什么？
- 如何避免频繁的熔断-恢复抖动？

敬请期待！
