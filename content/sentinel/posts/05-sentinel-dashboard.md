---
title: "Sentinel Dashboard：可视化流控管理"
date: 2025-01-21T14:40:00+08:00
draft: false
tags: ["Sentinel", "Dashboard", "可视化", "监控"]
categories: ["技术"]
series: ["Sentinel从入门到精通"]
weight: 5
stage: 1
stageTitle: "基础入门篇"
description: "学习使用Sentinel Dashboard进行可视化的流控规则配置和监控"
---

## 引言：从命令行到可视化

前面四篇，我们都是通过代码来配置限流规则：

```java
FlowRule rule = new FlowRule();
rule.setResource("myResource");
rule.setCount(100);
FlowRuleManager.loadRules(Collections.singletonList(rule));
```

这种方式虽然灵活，但有三大痛点：
1. **修改麻烦**：改阈值需要改代码、重启服务
2. **不直观**：看不到实时流量数据
3. **排查困难**：出问题时无法快速定位

Sentinel Dashboard解决了这些问题，提供了：
- ✅ **实时监控**：秒级数据刷新，QPS/RT/异常数一目了然
- ✅ **规则配置**：图形化配置，立即生效
- ✅ **机器管理**：多实例统一管理

今天我们将学习如何安装和使用Sentinel Dashboard。

---

## 一、Dashboard简介

### 1.1 Dashboard是什么

Sentinel Dashboard是Sentinel的**可视化控制台**，类似于：
- Nacos的控制台
- Kubernetes的Dashboard
- Spring Boot Admin

**核心功能**：

```
┌────────────────────────────────────────┐
│  实时监控                               │
│  - QPS、RT、异常数                     │
│  - 秒级刷新，实时图表                  │
├────────────────────────────────────────┤
│  规则配置                               │
│  - 流控规则、熔断规则、系统规则        │
│  - 图形化配置，立即生效                │
├────────────────────────────────────────┤
│  机器管理                               │
│  - 机器列表、健康状态                  │
│  - 多实例统一管理                      │
└────────────────────────────────────────┘
```

### 1.2 Dashboard的架构

```
┌───────────────┐
│  浏览器       │
│  localhost:   │
│   8080        │
└───────┬───────┘
        │ HTTP
        ↓
┌───────────────────────┐
│  Sentinel Dashboard   │  ← 控制台（Java应用）
│  端口: 8080           │
└───────┬───────────────┘
        │ 心跳 + 规则推送
        ↓
┌─────────────────────────────────────┐
│  应用实例1    应用实例2    应用实例3  │  ← 接入的应用
│  port: 8719   port: 8719   port: 8719 │
└─────────────────────────────────────┘
```

**通信方式**：
1. **心跳上报**：应用定期向Dashboard发送心跳（默认10秒）
2. **数据拉取**：Dashboard从应用拉取监控数据
3. **规则推送**：Dashboard推送规则到应用（双向通信）

---

## 二、下载与启动Dashboard

### 2.1 下载Dashboard

#### 方式1：下载官方JAR包（推荐）

访问GitHub Releases页面：
```
https://github.com/alibaba/Sentinel/releases
```

找到最新版本（如1.8.6），下载`sentinel-dashboard-1.8.6.jar`。

或者使用wget命令：
```bash
wget https://github.com/alibaba/Sentinel/releases/download/1.8.6/sentinel-dashboard-1.8.6.jar
```

#### 方式2：从源码编译

```bash
# 克隆仓库
git clone https://github.com/alibaba/Sentinel.git
cd Sentinel/sentinel-dashboard

# 编译
mvn clean package -DskipTests

# JAR包位置
ls target/sentinel-dashboard-1.8.6.jar
```

### 2.2 启动Dashboard

```bash
# 基础启动（默认端口8080）
java -jar sentinel-dashboard-1.8.6.jar

# 指定端口
java -Dserver.port=8088 -jar sentinel-dashboard-1.8.6.jar

# 指定日志目录
java -Dcsp.sentinel.log.dir=/var/log/sentinel \
     -jar sentinel-dashboard-1.8.6.jar

# 生产环境完整配置
java -Dserver.port=8080 \
     -Dcsp.sentinel.log.dir=/var/log/sentinel \
     -Dsentinel.dashboard.auth.username=admin \
     -Dsentinel.dashboard.auth.password=yourpassword \
     -Xms512m -Xmx512m \
     -jar sentinel-dashboard-1.8.6.jar
```

**启动参数说明**：

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `server.port` | Dashboard端口 | 8080 |
| `csp.sentinel.log.dir` | 日志目录 | `~/logs/csp/` |
| `sentinel.dashboard.auth.username` | 登录用户名 | sentinel |
| `sentinel.dashboard.auth.password` | 登录密码 | sentinel |
| `server.servlet.session.timeout` | 会话超时时间 | 7200秒 |

### 2.3 访问Dashboard

启动成功后，浏览器访问：
```
http://localhost:8080
```

**登录界面**：

```
┌──────────────────────────────┐
│                              │
│   Sentinel Dashboard         │
│                              │
│   用户名: sentinel           │
│   密码:   sentinel           │
│                              │
│   [ 登录 ]                   │
│                              │
└──────────────────────────────┘
```

默认账号密码都是`sentinel`。

---

## 三、应用接入Dashboard

### 3.1 添加依赖

在你的应用中添加`sentinel-transport-simple-http`依赖：

```xml
<dependency>
    <groupId>com.alibaba.csp</groupId>
    <artifactId>sentinel-core</artifactId>
    <version>1.8.6</version>
</dependency>

<!-- Dashboard通信依赖 -->
<dependency>
    <groupId>com.alibaba.csp</groupId>
    <artifactId>sentinel-transport-simple-http</artifactId>
    <version>1.8.6</version>
</dependency>
```

### 3.2 配置Dashboard地址

#### 方式1：JVM参数（推荐）

```bash
java -Dcsp.sentinel.dashboard.server=localhost:8080 \
     -Dproject.name=my-app \
     -jar my-app.jar
```

#### 方式2：application.properties

```properties
# Sentinel Dashboard地址
csp.sentinel.dashboard.server=localhost:8080

# 应用名称（必填）
project.name=my-app

# 客户端端口（可选，默认8719）
csp.sentinel.api.port=8719
```

#### 方式3：Spring Boot配置

```yaml
spring:
  cloud:
    sentinel:
      transport:
        dashboard: localhost:8080  # Dashboard地址
        port: 8719                 # 客户端端口

spring:
  application:
    name: my-app  # 应用名称
```

### 3.3 启动应用并触发调用

应用启动后，**必须先触发一次资源调用**，才会在Dashboard中显示。

```java
// 创建一个测试接口
@RestController
public class TestController {

    @GetMapping("/test")
    public String test() {
        Entry entry = null;
        try {
            entry = SphU.entry("testResource");
            return "Hello Sentinel!";
        } catch (BlockException ex) {
            return "Blocked!";
        } finally {
            if (entry != null) {
                entry.exit();
            }
        }
    }
}
```

**访问接口**：
```bash
curl http://localhost:8080/test
```

然后刷新Dashboard，你会看到应用已经接入：

```
┌────────────────────────────────────────┐
│ 应用列表                                │
├────────────────────────────────────────┤
│ my-app                                  │
│   ├─ 机器数: 1                          │
│   ├─ 健康: ✅                           │
│   └─ 资源数: 1 (testResource)          │
└────────────────────────────────────────┘
```

---

## 四、Dashboard功能介绍

### 4.1 实时监控

点击应用名称 → 实时监控：

```
┌────────────────────────────────────────┐
│ 资源链路                                │
├────────────────────────────────────────┤
│ testResource                            │
│   QPS: 10 ↑                            │
│   RT:  50ms                            │
│   异常: 0                               │
│   限流: 0                               │
│                                         │
│   [图表] ─────────────                │
│                 ╱╲  ╱╲                │
│                ╱  ╲╱  ╲               │
│   ─────────────────────────           │
│   0    10s   20s   30s   40s         │
└────────────────────────────────────────┘
```

**数据说明**：
- **QPS**：每秒请求数（实时）
- **RT**：平均响应时间（毫秒）
- **异常**：异常请求数
- **限流**：被限流的请求数

### 4.2 流控规则配置

点击"流控规则" → "新增流控规则"：

```
┌────────────────────────────────────────┐
│ 新增流控规则                            │
├────────────────────────────────────────┤
│ 资源名:    [testResource    ▼]        │
│ 针对来源:  [default        ▼]         │
│ 阈值类型:  (•) QPS  ( ) 线程数        │
│ 单机阈值:  [100          ]            │
│                                         │
│ 流控模式:  (•) 直接 ( ) 关联 ( ) 链路 │
│ 流控效果:  (•) 快速失败                │
│                                         │
│           [确定]  [取消]               │
└────────────────────────────────────────┘
```

**配置示例**：

| 字段 | 值 | 说明 |
|------|---|------|
| 资源名 | testResource | 必填，下拉选择 |
| 针对来源 | default | 默认所有来源 |
| 阈值类型 | QPS | QPS限流 |
| 单机阈值 | 100 | 每秒100次 |
| 流控模式 | 直接 | 直接限流 |
| 流控效果 | 快速失败 | 超过阈值直接拒绝 |

点击"确定"后，**规则立即生效**，无需重启应用。

### 4.3 测试限流效果

使用ab工具进行压测：

```bash
# 安装ab（Apache Bench）
# Mac: brew install httpd
# Ubuntu: apt-get install apache2-utils

# 压测：10个并发，总共1000个请求
ab -n 1000 -c 10 http://localhost:8080/test
```

观察Dashboard实时监控：
```
QPS: 100  ← 达到阈值
限流: 45  ← 45个请求被拒绝
```

### 4.4 簇点链路

点击"簇点链路"，可以看到所有资源的调用关系：

```
┌────────────────────────────────────────┐
│ 簇点链路                                │
├────────────────────────────────────────┤
│ machine-root                            │
│   └─ testResource                      │
│       ├─ QPS: 100                      │
│       ├─ RT: 50ms                      │
│       └─ [+流控] [+降级] [+热点]      │
└────────────────────────────────────────┘
```

**功能**：
- 查看资源的调用关系
- 快速为资源添加规则

### 4.5 机器列表

点击"机器列表"，查看所有接入的实例：

```
┌────────────────────────────────────────┐
│ 机器列表                                │
├────────────────────────────────────────┤
│ 192.168.1.100:8719  ✅ 健康            │
│ 192.168.1.101:8719  ✅ 健康            │
│ 192.168.1.102:8719  ❌ 离线            │
└────────────────────────────────────────┘
```

**功能**：
- 查看机器健康状态
- 查看每台机器的资源列表
- 可单独为某台机器配置规则

---

## 五、实战演练

### 5.1 场景：为订单创建接口配置限流

**步骤1：应用接入Dashboard**

```java
@RestController
@RequestMapping("/api/order")
public class OrderController {

    @GetMapping("/create")
    public String createOrder(@RequestParam Long userId,
                              @RequestParam Long productId) {
        Entry entry = null;
        try {
            entry = SphU.entry("order_create");

            // 业务逻辑
            return "订单创建成功";

        } catch (BlockException ex) {
            return "系统繁忙，请稍后重试";
        } finally {
            if (entry != null) {
                entry.exit();
            }
        }
    }
}
```

**步骤2：启动应用并触发调用**

```bash
curl "http://localhost:8080/api/order/create?userId=1&productId=100"
```

**步骤3：在Dashboard配置规则**

1. 打开Dashboard → 选择应用"my-app"
2. 点击"流控规则" → "新增流控规则"
3. 配置：
   - 资源名：order_create
   - 阈值类型：QPS
   - 单机阈值：10
   - 流控效果：快速失败

**步骤4：压测验证**

```bash
# 每秒50个请求，持续10秒
ab -n 500 -c 50 http://localhost:8080/api/order/create?userId=1&productId=100
```

观察Dashboard：
- QPS稳定在10
- 限流数约为40/秒

### 5.2 场景：监控热点商品的访问

**步骤1：使用热点参数限流**

```java
@GetMapping("/product/{id}")
public String getProduct(@PathVariable Long id) {
    Entry entry = null;
    try {
        // 传入参数
        entry = SphU.entry("product_detail",
                           EntryType.IN,
                           1,
                           id);  // 热点参数

        return "商品详情: " + id;

    } catch (BlockException ex) {
        return "访问过于频繁";
    } finally {
        if (entry != null) {
            entry.exit();
        }
    }
}
```

**步骤2：配置热点规则**

1. Dashboard → "热点规则" → "新增热点规则"
2. 配置：
   - 资源名：product_detail
   - 参数索引：0（第一个参数，即id）
   - 单机阈值：10
   - 统计窗口：1秒

**步骤3：高级配置：特定商品的特殊限流**

```
参数例外项：
  参数值: 1001  →  限流阈值: 100  （热门商品，允许更高QPS）
  参数值: 1002  →  限流阈值: 50
  其他商品：10
```

---

## 六、注意事项与最佳实践

### 6.1 Dashboard的规则不持久化

**重要警告**：Dashboard配置的规则**保存在内存中**，重启后丢失！

```
Dashboard重启
    ↓
规则丢失 ❌
    ↓
应用的规则也丢失（因为是从Dashboard拉取的）
```

**解决方案**：

| 方案 | 说明 | 推荐度 |
|------|------|--------|
| 配置中心（Nacos） | 规则持久化到Nacos | ⭐⭐⭐⭐⭐ |
| 数据库 | 规则持久化到MySQL | ⭐⭐⭐⭐ |
| 文件 | 规则持久化到本地文件 | ⭐⭐⭐ |

**后续章节会详细讲解规则持久化方案。**

### 6.2 Dashboard的安全配置

**默认配置非常不安全**：
- 用户名/密码：sentinel/sentinel
- 无IP白名单
- 无HTTPS

**生产环境必须配置**：

```bash
# 修改默认密码
-Dsentinel.dashboard.auth.username=admin
-Dsentinel.dashboard.auth.password=YourStrongPassword123

# 启用IP白名单
-Dsentinel.dashboard.auth.whitelist=192.168.1.0/24

# 使用Nginx反向代理，配置HTTPS
```

### 6.3 Dashboard的性能考虑

**Dashboard本身需要资源**：
- 内存：推荐512MB-1GB
- CPU：2核
- 网络：与应用频繁通信

**优化建议**：
1. 单独部署（不要与应用在同一台机器）
2. 高可用部署（至少2个实例）
3. 监控Dashboard本身的健康状态

### 6.4 多环境管理

**问题**：开发、测试、生产环境如何管理？

**方案1：多个Dashboard实例**

```
开发环境：dashboard-dev.example.com
测试环境：dashboard-test.example.com
生产环境：dashboard-prod.example.com
```

**方案2：通过应用名称区分**

```
应用名称带环境标识：
  my-app-dev
  my-app-test
  my-app-prod
```

---

## 七、总结

**Dashboard的价值**：
1. **实时监控**：秒级查看QPS、RT、异常数
2. **快速配置**：图形化配置规则，立即生效
3. **问题排查**：快速定位限流、熔断问题

**接入步骤**：
1. 下载并启动Dashboard
2. 应用添加`sentinel-transport-simple-http`依赖
3. 配置Dashboard地址
4. 触发资源调用，应用出现在Dashboard中

**注意事项**：
- ⚠️ Dashboard规则不持久化（需要配置规则中心）
- ⚠️ 生产环境必须修改默认密码
- ⚠️ Dashboard需要单独部署（资源隔离）

**下一篇预告**：《限流算法原理：计数器、滑动窗口、令牌桶、漏桶》

我们将深入学习4种经典限流算法的原理、优缺点和适用场景，理解Sentinel为什么选择滑动窗口算法。

---

## 思考题

1. Dashboard重启后，应用的限流规则会丢失吗？
2. 如果有100台机器，Dashboard如何管理它们的规则？
3. Dashboard的监控数据存储在哪里？会一直保留吗？

欢迎在评论区分享你的理解！

---

## 附录：Dashboard常用配置

```bash
# 完整的生产环境启动脚本
#!/bin/bash

JAVA_OPTS="-Xms1g -Xmx1g \
           -XX:+UseG1GC \
           -XX:MaxGCPauseMillis=200"

SENTINEL_OPTS="-Dserver.port=8080 \
               -Dcsp.sentinel.log.dir=/var/log/sentinel \
               -Dsentinel.dashboard.auth.username=admin \
               -Dsentinel.dashboard.auth.password=YourPassword \
               -Dsentinel.dashboard.auth.whitelist=192.168.1.0/24 \
               -Dserver.servlet.session.timeout=7200"

nohup java $JAVA_OPTS $SENTINEL_OPTS \
      -jar sentinel-dashboard-1.8.6.jar \
      > /var/log/sentinel/dashboard.log 2>&1 &

echo "Sentinel Dashboard started. PID: $!"
```

保存为`start-dashboard.sh`，赋予执行权限：
```bash
chmod +x start-dashboard.sh
./start-dashboard.sh
```
