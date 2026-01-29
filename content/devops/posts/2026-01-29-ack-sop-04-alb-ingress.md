---
title: "模块4：配置ALB Ingress"
date: 2026-01-29T11:04:00+08:00
draft: false
tags: ["Kubernetes", "阿里云", "ACK", "SOP", "教程", "ALB", "Ingress"]
categories: ["技术"]
series: ["阿里云ACK部署SOP"]
weight: 4
description: "详细讲解如何在ACK集群中配置ALB Ingress Controller，实现七层负载均衡和HTTPS访问"
---

## 导航

- **上一步**：[模块3：创建ACK集群](/blog/devops/posts/2026-01-29-ack-sop-03-ack-cluster/)
- **下一步**：[模块5：构建Docker镜像](/blog/devops/posts/2026-01-29-ack-sop-05-docker-build/)
- **返回主索引**：[阿里云ACK部署SOP](/blog/devops/posts/2026-01-29-aliyun-ack-deployment-sop/)

---

## 模块概述

**预计时间**：25分钟

**本模块目标**：
- ✅ 理解ALB和SLB的区别
- ✅ 安装ALB Ingress Controller
- ✅ 创建ALB实例
- ✅ 配置域名解析
- ✅ 配置SSL证书（自动签发）
- ✅ 验证ALB工作正常

**成本说明**：
- ALB实例：约¥60/月（alb.s1.small规格）
- 流量费用：¥0.8/GB（按实际使用计费）
- 本模块预计成本：¥60-100/月

---

## 步骤4.1：理解ALB vs SLB

### 🎬 操作说明
在配置Ingress之前，我们需要先理解阿里云的两种负载均衡产品：ALB（应用型负载均衡）和SLB（传统负载均衡）。这一步不需要操作，只需要理解它们的区别。

### 📍 详细说明

**ALB vs SLB 对比表**

| 特性 | ALB（应用型负载均衡） | SLB（传统负载均衡） |
|-----|---------------------|-------------------|
| **OSI层级** | 七层（HTTP/HTTPS） | 四层（TCP/UDP）+ 七层 |
| **路由能力** | 基于域名、路径、Header | 基于端口 |
| **SSL证书** | 自动管理、自动续期 | 手动上传、手动续期 |
| **WebSocket** | 原生支持 | 需要特殊配置 |
| **HTTP/2** | 原生支持 | 部分支持 |
| **健康检查** | HTTP健康检查 | TCP健康检查 |
| **价格** | 约¥60/月起 | 约¥30/月起 |
| **适用场景** | Web应用、API网关 | 通用负载均衡 |
| **推荐度** | ⭐⭐⭐⭐⭐（强烈推荐） | ⭐⭐⭐（传统方案） |

**为什么选择ALB？**

1. **智能路由**
   - 可以根据域名路由（如：api.example.com → API服务）
   - 可以根据路径路由（如：/api/* → API服务，/web/* → Web服务）
   - 可以根据Header路由（如：灰度发布）

2. **自动SSL管理**
   - 集成Let's Encrypt，自动签发免费SSL证书
   - 自动续期，不用担心证书过期
   - 支持SNI，一个ALB可以绑定多个域名

3. **更好的性能**
   - 原生支持HTTP/2，提升页面加载速度
   - 原生支持WebSocket，适合实时应用
   - 更智能的健康检查

4. **更低的运维成本**
   - 不需要手动管理SSL证书
   - 不需要配置复杂的路由规则
   - 通过Ingress YAML文件声明式管理

**SLB的局限性**

1. **路由能力弱**
   - 只能基于端口路由
   - 一个域名需要一个SLB实例
   - 多个服务需要多个SLB，成本高

2. **SSL管理复杂**
   - 需要手动上传证书
   - 需要手动续期（Let's Encrypt证书90天过期）
   - 证书更新需要重新上传

3. **配置复杂**
   - 需要在SLB控制台手动配置
   - 需要配置监听器、转发规则等
   - 不支持声明式管理

### ✅ 验证点
- 理解ALB和SLB的区别
- 明确我们选择ALB的原因

### ⚠️ 常见问题

**问题1：ALB比SLB贵，为什么还要用？**
- 答：虽然单价贵，但总成本更低
- SLB需要为每个域名创建一个实例
- ALB一个实例可以支持多个域名
- 加上运维成本，ALB更划算

**问题2：ALB只支持HTTP/HTTPS吗？**
- 答：是的，ALB是七层负载均衡
- 如果需要TCP/UDP负载均衡，使用SLB
- 对于Web应用和API，ALB完全够用

**问题3：可以同时使用ALB和SLB吗？**
- 答：可以
- Web流量使用ALB
- 数据库、Redis等使用SLB
- 根据场景选择合适的产品

### 💡 小贴士
- 🎯 推荐使用ALB，除非有特殊需求
- 💰 ALB的自动SSL管理可以节省大量运维时间
- 📚 ALB是阿里云推荐的Kubernetes Ingress方案

---

## 步骤4.2：安装ALB Ingress Controller

### 🎬 操作说明
ALB Ingress Controller是一个Kubernetes组件，它会监听Ingress资源的变化，自动在ALB上配置路由规则。我们需要先在集群中安装这个组件。

### 📍 详细步骤

**第1步：进入ACK控制台**
- 在浏览器中访问：https://cs.console.aliyun.com/
- 确认地域为"华东1（杭州）"
- 在左侧菜单点击"集群"
- 找到我们创建的集群"my-ack-cluster"

**第2步：进入应用市场**
- 点击集群名称，进入集群详情
- 在左侧菜单中，找到"应用"部分
- 点击"应用市场"
- 页面跳转到应用市场

**第3步：搜索ALB Ingress Controller**
- 在应用市场的搜索框中
- 输入"alb"或"ingress"
- 在搜索结果中，找到"ack-alb-ingress-controller"
- 点击进入应用详情页

**第4步：安装ALB Ingress Controller**
- 在应用详情页，点击"一键部署"按钮
- 在弹出的对话框中，确认配置
- 命名空间：选择"kube-system"
- 发布名称：保持默认"ack-alb-ingress-controller"
- 点击"确定"按钮开始安装

**第5步：等待安装完成**
- 安装过程约需要2-3分钟
- 页面会显示安装进度
- 安装完成后，会显示"安装成功"的提示

**第6步：验证安装**
- 在终端中运行命令：
  ```bash
  kubectl get pods -n kube-system | grep alb
  ```
- 应该看到类似输出：
  ```
  ack-alb-ingress-controller-xxx   1/1     Running   0          2m
  ```
- 确认Pod状态为"Running"

### ✅ 验证点
- ALB Ingress Controller已安装
- Pod状态为"Running"
- 没有报错信息

### ⚠️ 常见问题

**问题1：找不到"应用市场"菜单？**
- 答：可能是ACK版本较老
- 可以使用Helm安装：
  ```bash
  helm repo add aliyun https://kubernetes.github.io/ingress-nginx
  helm install alb-ingress-controller aliyun/alb-ingress-controller -n kube-system
  ```

**问题2：Pod一直Pending？**
- 答：可能是资源不足
- 查看Pod详情：
  ```bash
  kubectl describe pod <Pod名称> -n kube-system
  ```
- 检查是否有资源不足的提示

**问题3：Pod一直CrashLoopBackOff？**
- 答：可能是权限问题
- 查看Pod日志：
  ```bash
  kubectl logs <Pod名称> -n kube-system
  ```
- 检查是否有权限错误

### 💡 小贴士
- 📦 ALB Ingress Controller是开源项目
- 🔄 安装后会自动监听Ingress资源
- 🎯 一个集群只需要安装一次

---

## 步骤4.3：创建ALB实例

### 🎬 操作说明
现在ALB Ingress Controller已经安装好了，但是还没有ALB实例。我们需要在阿里云控制台创建一个ALB实例。

### 📍 详细步骤

**第1步：进入ALB控制台**
- 在浏览器中访问：https://slb.console.aliyun.com/
- 在左侧菜单中，找到"应用型负载均衡ALB"
- 点击"实例管理"
- 页面显示ALB实例列表

**第2步：创建ALB实例**
- 点击右上角的"创建应用型负载均衡"按钮
- 进入创建向导页面

**第3步：配置基本信息**
- 实例名称：输入`my-alb`
- 地域：选择"华东1（杭州）"
- 可用区：选择"可用区H"和"可用区I"（和集群的可用区一致）
- 实例规格：选择"alb.s1.small"（小规格，适合学习测试）

**第4步：配置网络**
- VPC：选择"my-vpc"（和集群在同一个VPC）
- 交换机：
  - 可用区H：选择"my-vswitch-1"
  - 可用区I：选择"my-vswitch-2"
- 确保交换机和集群的交换机一致

**第5步：配置计费方式**
- 计费方式：选择"按量付费"
- 规格费用：约¥0.08/小时（约¥60/月）
- 流量费用：¥0.8/GB
- 点击"立即购买"按钮

**第6步：确认订单**
- 在确认页面，检查配置是否正确
- 勾选"我已阅读并同意《应用型负载均衡服务协议》"
- 点击"确认购买"按钮

**第7步：等待创建完成**
- 创建过程约需要1-2分钟
- 页面会跳转到实例列表
- 看到新创建的ALB实例
- 实例状态显示为"运行中"

### ✅ 验证点
- ALB实例已创建
- 实例状态为"运行中"
- 实例在正确的VPC和交换机中

### ⚠️ 常见问题

**问题1：为什么选择alb.s1.small规格？**
- 答：这是最小的规格，适合学习测试
- 性能：5000 QPS，50 Mbps带宽
- 对于小流量应用完全够用
- 后续可以升级规格

**问题2：ALB实例必须和集群在同一个VPC吗？**
- 答：是的，必须在同一个VPC
- ALB需要访问集群内的Pod
- 如果不在同一个VPC，无法通信

**问题3：可以使用已有的ALB实例吗？**
- 答：可以
- 但建议为每个集群创建独立的ALB实例
- 避免不同集群的路由规则冲突

### 💡 小贴士
- 💰 alb.s1.small规格约¥60/月
- 🎯 生产环境建议使用alb.s2.small或更高规格
- 📊 可以在ALB控制台查看流量监控

---

## 步骤4.4：配置域名解析

### 🎬 操作说明
现在ALB实例已经创建好了，我们需要配置域名解析，让域名指向ALB的公网IP。这样用户才能通过域名访问我们的应用。

### 📍 详细步骤

**第1步：获取ALB的公网IP**
- 在ALB实例列表中，找到我们创建的ALB
- 在"IP地址"列，看到ALB的公网IP
- 复制这个IP地址（如：47.98.123.456）

**第2步：进入域名解析控制台**
- 在浏览器中访问：https://dns.console.aliyun.com/
- 如果你的域名在阿里云，会看到域名列表
- 如果域名不在阿里云，需要在域名注册商处配置

**第3步：添加A记录**
- 找到你的域名（如：example.com）
- 点击"解析设置"按钮
- 点击"添加记录"按钮

**第4步：配置A记录**
- 记录类型：选择"A"
- 主机记录：输入"www"（表示www.example.com）
- 解析线路：选择"默认"
- 记录值：粘贴ALB的公网IP
- TTL：选择"10分钟"
- 点击"确定"按钮

**第5步：添加根域名记录（可选）**
- 如果希望example.com也能访问（不带www）
- 再添加一条A记录
- 主机记录：输入"@"（表示根域名）
- 其他配置和上面一样

**第6步：等待DNS生效**
- DNS解析需要5-10分钟生效
- 可以使用命令验证：
  ```bash
  nslookup www.example.com
  ```
- 如果返回ALB的IP，说明解析已生效

### ✅ 验证点
- A记录已添加
- nslookup命令返回正确的IP
- DNS解析已生效

### ⚠️ 常见问题

**问题1：没有域名怎么办？**
- 答：可以购买一个便宜的域名
- 阿里云域名：.com约¥55/年，.cn约¥29/年
- 或者使用免费的二级域名服务（如：freenom.com）
- 或者使用IP地址访问（但无法配置HTTPS）

**问题2：域名不在阿里云怎么办？**
- 答：在域名注册商处配置DNS
- 添加A记录，指向ALB的公网IP
- 配置方法和阿里云类似

**问题3：DNS解析多久生效？**
- 答：通常5-10分钟
- 最长可能需要24小时（全球DNS同步）
- 可以使用 `nslookup` 或 `dig` 命令验证

**问题4：可以使用CNAME记录吗？**
- 答：不推荐
- ALB的公网IP是固定的，使用A记录更简单
- CNAME记录适合指向另一个域名

### 💡 小贴士
- 🌐 建议同时配置www和根域名
- ⏰ DNS生效需要时间，请耐心等待
- 🔍 使用 `nslookup` 命令可以快速验证DNS

---

## 步骤4.5：配置SSL证书（使用cert-manager）

### 🎬 操作说明
现在域名已经解析到ALB了，但是还不支持HTTPS。我们需要配置SSL证书。阿里云ALB支持自动从Let's Encrypt签发免费SSL证书，我们使用cert-manager来实现自动化。

### 📍 详细步骤

**第1步：安装cert-manager**
- 在终端中运行命令：
  ```bash
  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
  ```
- 这会在集群中安装cert-manager组件
- 等待约2分钟，所有Pod启动完成

**第2步：验证cert-manager安装**
- 运行命令查看cert-manager的Pod：
  ```bash
  kubectl get pods -n cert-manager
  ```
- 应该看到3个Pod都在运行：
  ```
  cert-manager-xxx          1/1     Running   0          2m
  cert-manager-cainjector-xxx   1/1     Running   0          2m
  cert-manager-webhook-xxx      1/1     Running   0          2m
  ```

**第3步：创建Let's Encrypt Issuer**
- 创建一个文件 `letsencrypt-issuer.yaml`：
  ```yaml
  apiVersion: cert-manager.io/v1
  kind: ClusterIssuer
  metadata:
    name: letsencrypt-prod
  spec:
    acme:
      server: https://acme-v02.api.letsencrypt.org/directory
      email: your-email@example.com  # 替换为你的邮箱
      privateKeySecretRef:
        name: letsencrypt-prod
      solvers:
      - http01:
          ingress:
            class: alb
  ```
- 注意：将 `your-email@example.com` 替换为你的真实邮箱

**第4步：应用Issuer配置**
- 运行命令：
  ```bash
  kubectl apply -f letsencrypt-issuer.yaml
  ```
- 这会创建一个ClusterIssuer资源
- cert-manager会使用这个Issuer来签发证书

**第5步：验证Issuer创建**
- 运行命令：
  ```bash
  kubectl get clusterissuer
  ```
- 应该看到：
  ```
  NAME               READY   AGE
  letsencrypt-prod   True    1m
  ```
- 确认READY状态为True

### ✅ 验证点
- cert-manager已安装
- cert-manager的Pod都在运行
- ClusterIssuer已创建且状态为Ready

### ⚠️ 常见问题

**问题1：cert-manager是什么？**
- 答：Kubernetes的证书管理工具
- 可以自动从Let's Encrypt签发SSL证书
- 可以自动续期证书（Let's Encrypt证书90天过期）
- 是Kubernetes社区推荐的证书管理方案

**问题2：Let's Encrypt是什么？**
- 答：免费的SSL证书颁发机构
- 提供免费的DV（域名验证）证书
- 证书有效期90天，但可以自动续期
- 被所有主流浏览器信任

**问题3：为什么需要填写邮箱？**
- 答：Let's Encrypt会发送证书相关通知
- 如：证书即将过期（如果自动续期失败）
- 如：Let's Encrypt的重要公告
- 邮箱不会被公开或用于营销

**问题4：http01验证是什么？**
- 答：Let's Encrypt的域名验证方式
- cert-manager会在你的域名下创建一个临时文件
- Let's Encrypt访问这个文件来验证你拥有这个域名
- 验证通过后，签发证书

### 💡 小贴士
- 🔒 Let's Encrypt证书完全免费
- 🔄 cert-manager会自动续期，不用担心证书过期
- 📧 建议使用真实邮箱，以便接收重要通知

---

## 步骤4.6：创建测试应用和Ingress

### 🎬 操作说明
现在所有基础设施都准备好了，我们创建一个简单的测试应用，并配置Ingress，验证ALB和SSL证书是否工作正常。

### 📍 详细步骤

**第1步：创建测试应用**
- 创建一个文件 `test-app.yaml`：
  ```yaml
  apiVersion: v1
  kind: Namespace
  metadata:
    name: test
  ---
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: nginx-test
    namespace: test
  spec:
    replicas: 2
    selector:
      matchLabels:
        app: nginx-test
    template:
      metadata:
        labels:
          app: nginx-test
      spec:
        containers:
        - name: nginx
          image: nginx:1.25-alpine
          ports:
          - containerPort: 80
  ---
  apiVersion: v1
  kind: Service
  metadata:
    name: nginx-test
    namespace: test
  spec:
    selector:
      app: nginx-test
    ports:
    - port: 80
      targetPort: 80
    type: ClusterIP
  ```

**第2步：应用测试应用**
- 运行命令：
  ```bash
  kubectl apply -f test-app.yaml
  ```
- 这会创建一个命名空间、一个Deployment和一个Service

**第3步：验证应用运行**
- 运行命令查看Pod：
  ```bash
  kubectl get pods -n test
  ```
- 应该看到2个nginx Pod都在运行：
  ```
  NAME                          READY   STATUS    RESTARTS   AGE
  nginx-test-xxx                1/1     Running   0          1m
  nginx-test-yyy                1/1     Running   0          1m
  ```

**第4步：创建Ingress配置**
- 创建一个文件 `test-ingress.yaml`：
  ```yaml
  apiVersion: networking.k8s.io/v1
  kind: Ingress
  metadata:
    name: nginx-test
    namespace: test
    annotations:
      kubernetes.io/ingress.class: alb
      cert-manager.io/cluster-issuer: letsencrypt-prod
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
      alb.ingress.kubernetes.io/ssl-redirect: "true"
  spec:
    tls:
    - hosts:
      - www.example.com  # 替换为你的域名
      secretName: nginx-test-tls
    rules:
    - host: www.example.com  # 替换为你的域名
      http:
        paths:
        - path: /
          pathType: Prefix
          backend:
            service:
              name: nginx-test
              port:
                number: 80
  ```
- 注意：将 `www.example.com` 替换为你的真实域名

**第5步：应用Ingress配置**
- 运行命令：
  ```bash
  kubectl apply -f test-ingress.yaml
  ```
- 这会创建一个Ingress资源
- ALB Ingress Controller会自动在ALB上配置路由规则
- cert-manager会自动签发SSL证书

**第6步：等待证书签发**
- 运行命令查看证书状态：
  ```bash
  kubectl get certificate -n test
  ```
- 初始状态可能是"False"，等待约2-3分钟
- 最终应该看到：
  ```
  NAME             READY   SECRET           AGE
  nginx-test-tls   True    nginx-test-tls   3m
  ```
- 确认READY状态为True

**第7步：查看Ingress状态**
- 运行命令：
  ```bash
  kubectl get ingress -n test
  ```
- 应该看到：
  ```
  NAME         CLASS   HOSTS              ADDRESS          PORTS     AGE
  nginx-test   alb     www.example.com    47.98.123.456    80, 443   3m
  ```
- ADDRESS列显示ALB的公网IP

### ✅ 验证点
- 测试应用的Pod都在运行
- Ingress已创建
- Certificate状态为Ready
- Ingress的ADDRESS显示ALB的IP

### ⚠️ 常见问题

**问题1：Certificate一直是False？**
- 答：可能是DNS还没生效
- 运行命令查看Certificate详情：
  ```bash
  kubectl describe certificate nginx-test-tls -n test
  ```
- 查看Events部分的错误信息
- 常见原因：DNS未生效、域名无法访问

**问题2：Ingress没有ADDRESS？**
- 答：可能是ALB Ingress Controller有问题
- 查看Controller日志：
  ```bash
  kubectl logs -n kube-system -l app=alb-ingress-controller
  ```
- 检查是否有错误信息

**问题3：ssl-redirect是什么？**
- 答：自动将HTTP重定向到HTTPS
- 用户访问http://www.example.com会自动跳转到https://www.example.com
- 这是HTTPS的最佳实践

### 💡 小贴士
- ⏰ 证书签发需要2-3分钟，请耐心等待
- 🔒 证书签发成功后，会自动存储在Secret中
- 🔄 证书会在过期前30天自动续期

---

## 步骤4.7：验证HTTPS访问

### 🎬 操作说明
现在所有配置都完成了，我们来验证是否可以通过HTTPS访问应用。这是最后的验证步骤。

### 📍 详细步骤

**第1步：使用curl测试HTTP访问**
- 在终端中运行：
  ```bash
  curl -I http://www.example.com
  ```
- 应该看到301重定向响应：
  ```
  HTTP/1.1 301 Moved Permanently
  Location: https://www.example.com/
  ```
- 这说明HTTP自动重定向到HTTPS

**第2步：使用curl测试HTTPS访问**
- 在终端中运行：
  ```bash
  curl -I https://www.example.com
  ```
- 应该看到200成功响应：
  ```
  HTTP/2 200
  server: nginx/1.25.3
  ```
- 这说明HTTPS访问成功

**第3步：使用浏览器访问**
- 在浏览器中访问：https://www.example.com
- 应该看到nginx的欢迎页面
- 浏览器地址栏显示小锁图标（表示HTTPS安全连接）
- 点击小锁图标，可以查看证书详情

**第4步：检查证书信息**
- 在浏览器中，点击地址栏的小锁图标
- 点击"证书"或"连接是安全的"
- 查看证书详情：
  - 颁发者：Let's Encrypt
  - 有效期：90天
  - 域名：www.example.com

**第5步：测试HTTP/2**
- 在浏览器的开发者工具中（F12）
- 切换到"Network"标签页
- 刷新页面
- 查看请求的Protocol列
- 应该显示"h2"（表示HTTP/2）

### ✅ 验证点
- HTTP访问自动重定向到HTTPS
- HTTPS访问返回200状态码
- 浏览器显示安全连接（小锁图标）
- 证书由Let's Encrypt签发
- 支持HTTP/2协议

### ⚠️ 常见问题

**问题1：浏览器显示"不安全"或"证书错误"？**
- 答：可能是证书还没签发成功
- 运行命令检查证书状态：
  ```bash
  kubectl get certificate -n test
  ```
- 如果READY是False，等待几分钟
- 如果长时间False，查看Certificate的Events

**问题2：curl提示"SSL certificate problem"？**
- 答：可能是证书还没生效
- 可以使用 `-k` 参数跳过证书验证：
  ```bash
  curl -Ik https://www.example.com
  ```
- 但生产环境不要使用 `-k` 参数

**问题3：访问超时或无法连接？**
- 答：检查以下几点
- DNS是否生效（nslookup www.example.com）
- ALB安全组是否允许80和443端口
- Ingress的ADDRESS是否正确

**问题4：看到的是ALB的默认页面，不是nginx页面？**
- 答：可能是Ingress配置错误
- 检查Ingress的host是否和访问的域名一致
- 检查Service和Pod是否正常运行

### 💡 小贴士
- 🔒 小锁图标表示HTTPS连接安全
- 🚀 HTTP/2可以提升页面加载速度
- 📊 可以在ALB控制台查看访问日志和监控数据

---

## 步骤4.8：清理测试资源（可选）

### 🎬 操作说明
如果你只是测试ALB Ingress的功能，可以清理测试资源。如果你要继续使用，可以跳过这一步。

### 📍 详细步骤

**第1步：删除测试应用**
- 运行命令：
  ```bash
  kubectl delete -f test-ingress.yaml
  kubectl delete -f test-app.yaml
  ```
- 这会删除Ingress、Service、Deployment和Namespace

**第2步：验证资源已删除**
- 运行命令：
  ```bash
  kubectl get all -n test
  ```
- 应该显示"No resources found"

**第3步：保留ALB和cert-manager**
- ALB实例和cert-manager不要删除
- 后续部署真实应用时还会用到
- 只删除测试应用即可

### ✅ 验证点
- 测试应用已删除
- ALB实例仍然存在
- cert-manager仍然运行

### ⚠️ 常见问题

**问题1：删除Ingress后，ALB上的规则会删除吗？**
- 答：会的
- ALB Ingress Controller会自动清理ALB上的路由规则
- 但ALB实例本身不会删除

**问题2：删除应用后，证书会删除吗？**
- 答：会的
- 证书存储在Secret中
- 删除Namespace会删除所有资源，包括Secret

**问题3：需要删除cert-manager吗？**
- 答：不需要
- cert-manager是集群级别的组件
- 后续部署应用还会用到

### 💡 小贴士
- 🗑️ 测试完成后及时清理资源，避免浪费
- 💰 但不要删除ALB和cert-manager，后续还会用到
- 📝 建议保存测试配置文件，方便后续参考

---

## 模块总结

### 🎉 恭喜！你已经完成了ALB Ingress的配置

在这个模块中，我们完成了以下工作：

1. ✅ **理解了ALB和SLB的区别**
   - ALB是七层负载均衡，支持智能路由
   - ALB支持自动SSL管理，运维成本低
   - ALB是阿里云推荐的Kubernetes Ingress方案

2. ✅ **安装了ALB Ingress Controller**
   - 在集群中安装了ALB Ingress Controller组件
   - Controller会自动监听Ingress资源
   - Controller会自动在ALB上配置路由规则

3. ✅ **创建了ALB实例**
   - 创建了alb.s1.small规格的ALB实例
   - ALB实例在和集群相同的VPC中
   - ALB实例有公网IP，可以从外部访问

4. ✅ **配置了域名解析**
   - 添加了A记录，将域名指向ALB的公网IP
   - DNS解析已生效

5. ✅ **配置了SSL证书**
   - 安装了cert-manager组件
   - 创建了Let's Encrypt Issuer
   - 证书会自动签发和续期

6. ✅ **验证了HTTPS访问**
   - 创建了测试应用和Ingress
   - 验证了HTTP自动重定向到HTTPS
   - 验证了HTTPS访问成功
   - 验证了HTTP/2支持

### 📊 资源清单

| 资源类型 | 资源名称 | 规格 | 月成本 |
|---------|---------|------|--------|
| ALB实例 | my-alb | alb.s1.small | ¥60 |
| 流量费用 | - | ¥0.8/GB | 按实际使用 |
| cert-manager | - | 免费 | ¥0 |
| SSL证书 | Let's Encrypt | 免费 | ¥0 |
| **总计** | - | - | **¥60-100/月** |

### 🎯 下一步

现在ALB Ingress已经配置好了，应用可以从外部通过HTTPS访问。在下一个模块中，我们将：

1. 编写Dockerfile
2. 构建Docker镜像
3. 推送镜像到阿里云容器镜像服务（ACR）
4. 准备部署真实应用

**继续学习**：[模块5：构建Docker镜像](/blog/devops/posts/2026-01-29-ack-sop-05-docker-build/)

### 💡 重要提示

- 🔒 **安全提示**：Let's Encrypt证书会自动续期，不用担心过期
- 💰 **成本提示**：ALB按小时计费，不用时可以删除
- 📚 **学习建议**：理解Ingress的工作原理，这是Kubernetes的核心概念
- 🎯 **最佳实践**：生产环境建议使用更高规格的ALB（如alb.s2.small）

### 📖 扩展阅读

**Ingress配置示例**

```yaml
# 多域名配置
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: multi-domain
  annotations:
    kubernetes.io/ingress.class: alb
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  tls:
  - hosts:
    - api.example.com
    - www.example.com
    secretName: multi-domain-tls
  rules:
  - host: api.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 80
  - host: www.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 80
```

```yaml
# 路径路由配置
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: path-routing
  annotations:
    kubernetes.io/ingress.class: alb
spec:
  rules:
  - host: www.example.com
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 80
      - path: /web
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 80
```

---

**导航**：
- **上一步**：[模块3：创建ACK集群](/blog/devops/posts/2026-01-29-ack-sop-03-ack-cluster/)
- **下一步**：[模块5：构建Docker镜像](/blog/devops/posts/2026-01-29-ack-sop-05-docker-build/)
- **返回主索引**：[阿里云ACK部署SOP](/blog/devops/posts/2026-01-29-aliyun-ack-deployment-sop/)