---
title: "DNS域名解析：从域名到IP的查询过程"
date: 2025-11-20T18:10:00+08:00
draft: false
tags: ["计算机网络", "DNS", "域名解析"]
categories: ["技术"]
description: "深入理解DNS解析过程，递归查询与迭代查询，DNS缓存机制，以及微服务DNS配置实践"
series: ["计算机网络从入门到精通"]
weight: 20
stage: 3
stageTitle: "应用层协议篇"
---

## DNS基础

### 为什么需要DNS？

```
人类习惯：www.baidu.com
计算机需要：180.97.33.108

DNS（Domain Name System）：域名系统
作用：域名 → IP地址
```

### DNS分层架构

```
根域名服务器（Root DNS）
    .
    ├── com（顶级域）
    │   ├── baidu.com（二级域）
    │   │   ├── www.baidu.com
    │   │   └── api.baidu.com
    │   └── google.com
    ├── cn（顶级域）
    │   └── taobao.com
    └── org（顶级域）
        └── wikipedia.org
```

---

## DNS查询过程

### 递归查询 vs 迭代查询

**递归查询**（客户端 → 本地DNS）：
```
客户端：请帮我查 www.baidu.com
本地DNS：好的，我帮你查到底，然后告诉你结果
```

**迭代查询**（本地DNS → 各级DNS服务器）：
```
本地DNS → 根DNS：www.baidu.com的IP是？
根DNS → 本地DNS：我不知道，你去问.com的DNS服务器

本地DNS → .com DNS：www.baidu.com的IP是？
.com DNS → 本地DNS：我不知道，你去问baidu.com的DNS服务器

本地DNS → baidu.com DNS：www.baidu.com的IP是？
baidu.com DNS → 本地DNS：是180.97.33.108
```

### 完整流程

```
1. 浏览器缓存（Chrome://net-internals/#dns）
2. 操作系统缓存（/etc/hosts，系统DNS缓存）
3. 本地DNS服务器（ISP提供，如8.8.8.8）
4. 根DNS服务器（全球13个根服务器集群）
5. 顶级域DNS服务器（.com、.cn等）
6. 权威DNS服务器（baidu.com的DNS服务器）
```

**示例**：
```bash
# dig追踪DNS查询
dig +trace www.baidu.com

# 输出
.			518400	IN	NS	a.root-servers.net.  # 根服务器
com.		172800	IN	NS	a.gtld-servers.net.  # .com服务器
baidu.com.	86400	IN	NS	dns.baidu.com.      # baidu.com服务器
www.baidu.com.	1200	IN	CNAME www.a.shifen.com.  # CNAME记录
www.a.shifen.com. 300	IN	A	180.97.33.108        # 最终IP
```

---

## DNS记录类型

| 类型 | 全称 | 作用 | 示例 |
|------|------|------|------|
| **A** | Address | IPv4地址 | `baidu.com → 180.97.33.108` |
| **AAAA** | IPv6 Address | IPv6地址 | `baidu.com → 240e:...` |
| **CNAME** | Canonical Name | 别名 | `www.baidu.com → www.a.shifen.com` |
| **MX** | Mail Exchange | 邮件服务器 | `baidu.com → mx.baidu.com` |
| **NS** | Name Server | DNS服务器 | `baidu.com → dns.baidu.com` |
| **TXT** | Text | 文本记录 | 域名验证、SPF记录 |
| **SRV** | Service | 服务记录 | 微服务发现 |

---

## DNS缓存

### TTL（Time To Live）

```
www.baidu.com.  300  IN  A  180.97.33.108
                ↑TTL（秒）

含义：缓存有效期300秒（5分钟）
过期后重新查询
```

### 缓存层次

```
[浏览器缓存] TTL：chrome://net-internals/#dns
    ↓
[操作系统缓存] TTL：根据系统配置
    ↓
[本地DNS缓存] TTL：根据权威DNS返回的TTL
```

### 查看和清除缓存

```bash
# macOS查看DNS缓存
sudo dscacheutil -cachedump -entries Host

# macOS清除DNS缓存
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder

# Linux清除DNS缓存
sudo systemd-resolve --flush-caches

# Windows清除DNS缓存
ipconfig /flushdns
```

---

## DNS排查工具

### 1. nslookup

```bash
# 基本查询
nslookup www.baidu.com

# 输出
Server:		8.8.8.8  # 使用的DNS服务器
Address:	8.8.8.8#53

Name:	www.baidu.com
Address: 180.97.33.108

# 指定DNS服务器查询
nslookup www.baidu.com 114.114.114.114
```

### 2. dig（推荐）

```bash
# 基本查询
dig www.baidu.com

# 追踪查询路径
dig +trace www.baidu.com

# 查询特定记录类型
dig www.baidu.com A      # IPv4
dig www.baidu.com AAAA   # IPv6
dig www.baidu.com CNAME  # 别名
dig baidu.com MX         # 邮件服务器

# 简洁输出
dig www.baidu.com +short
# 180.97.33.108
```

### 3. host

```bash
# 基本查询
host www.baidu.com

# 输出
www.baidu.com is an alias for www.a.shifen.com.
www.a.shifen.com has address 180.97.33.108
```

---

## 微服务DNS实战

### 案例1：Kubernetes DNS

**CoreDNS配置**：
```yaml
# Kubernetes中每个Service自动获得DNS记录

# Service DNS格式
<service-name>.<namespace>.svc.cluster.local

# 示例
user-service.default.svc.cluster.local → 10.96.0.10
```

**应用调用**：
```java
@FeignClient(name = "user-service")  // 自动DNS解析
public interface UserClient {
    @GetMapping("/api/users/{id}")
    User getUser(@PathVariable Long id);
}

// Kubernetes DNS解析：
// user-service → user-service.default.svc.cluster.local → 10.96.0.10
```

### 案例2：Consul DNS

**Consul DNS配置**：
```
# Consul DNS格式
<service-name>.service.consul

# 示例
user-service.service.consul → 192.168.1.10, 192.168.1.11（多个实例）
```

**Spring Boot配置**：
```yaml
spring:
  cloud:
    consul:
      discovery:
        hostname: ${HOSTNAME}
        prefer-ip-address: true
```

```java
// 调用时自动通过Consul DNS解析并负载均衡
restTemplate.getForObject("http://user-service/api/users/123", User.class);
```

### 案例3：DNS轮询负载均衡

```
配置多个A记录（DNS Round Robin）：

user-service.example.com:
  - 192.168.1.10
  - 192.168.1.11
  - 192.168.1.12

每次DNS查询返回不同顺序，实现简单负载均衡
```

**问题**：
- DNS缓存导致无法及时切换
- 无法检测后端健康状态
- 粒度粗（无法按请求级别负载均衡）

**解决**：使用专业负载均衡（Nginx、Ribbon、Spring Cloud LoadBalancer）

---

## DNS优化

### 1. DNS预解析

```html
<!-- HTML预解析 -->
<link rel="dns-prefetch" href="//api.example.com">
<link rel="dns-prefetch" href="//cdn.example.com">
```

### 2. 减少DNS查询

```
合并域名：
static1.example.com
static2.example.com
static3.example.com

优化为：
static.example.com
```

### 3. 使用HTTPDNS

**传统DNS问题**：
- ISP劫持（广告注入）
- 解析不准确（跨地域解析到远程CDN）

**HTTPDNS**：通过HTTP请求获取IP
```bash
# 阿里云HTTPDNS
curl "http://203.107.1.1/123456/d?host=www.example.com"

# 返回JSON
{"ips":["1.2.3.4","5.6.7.8"],"ttl":60}
```

---

## 总结

### 核心要点

1. **DNS分层架构**：根DNS → 顶级域DNS → 权威DNS
2. **查询方式**：递归查询（客户端） + 迭代查询（DNS服务器间）
3. **DNS缓存**：浏览器 → 操作系统 → 本地DNS → 权威DNS
4. **微服务DNS**：Kubernetes CoreDNS、Consul DNS
5. **排查工具**：dig、nslookup、host

### 下一篇预告

《WebSocket与gRPC：全双工通信与高效RPC》
