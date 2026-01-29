---
title: "模块7：故障排查和优化"
date: 2026-01-29T11:07:00+08:00
draft: false
tags: ["Kubernetes", "阿里云", "ACK", "SOP", "教程", "故障排查"]
categories: ["技术"]
series: ["阿里云ACK部署SOP"]
weight: 7
description: "详细讲解Kubernetes常见问题的排查方法、日志分析、回滚操作和成本优化建议"
---

## 导航

- **上一步**：[模块6：部署应用到K8s](/blog/devops/posts/2026-01-29-ack-sop-06-deploy-app/)
- **返回主索引**：[阿里云ACK部署SOP](/blog/devops/posts/2026-01-29-aliyun-ack-deployment-sop/)

---

## 模块概述

**预计时间**：40分钟

**本模块目标**：
- ✅ 掌握Pod故障排查方法
- ✅ 掌握网络故障排查方法
- ✅ 学会查看和分析日志
- ✅ 学会回滚应用
- ✅ 了解成本优化方法
- ✅ 学会彻底清理资源

**成本说明**：
- 本模块不产生额外费用
- 会学习如何优化成本

---

## 步骤7.1：Pod故障排查 - ImagePullBackOff

### 🎬 操作说明
ImagePullBackOff是最常见的Pod启动失败错误，表示无法拉取Docker镜像。我们需要学会快速定位和解决这个问题。

### 📍 详细步骤

**第1步：识别错误**
- 运行命令查看Pod状态：
  ```bash
  kubectl get pods -n my-app
  ```
- 如果看到ImagePullBackOff或ErrImagePull：
  ```
  NAME                      READY   STATUS             RESTARTS   AGE
  my-app-7d9f8c6b5d-abc12   0/1     ImagePullBackOff   0          2m
  ```

**第2步：查看详细错误信息**
- 运行命令：
  ```bash
  kubectl describe pod <Pod名称> -n my-app
  ```
- 在Events部分查看错误：
  ```
  Events:
    Type     Reason     Age                From               Message
    ----     ------     ----               ----               -------
    Normal   Scheduled  2m                 default-scheduler  Successfully assigned my-app/my-app-xxx to node1
    Normal   Pulling    1m (x4 over 2m)    kubelet            Pulling image "registry.cn-hangzhou.aliyuncs.com/my-namespace/my-app:v1.0.0"
    Warning  Failed     1m (x4 over 2m)    kubelet            Failed to pull image: rpc error: code = Unknown desc = Error response from daemon: pull access denied
    Warning  Failed     1m (x4 over 2m)    kubelet            Error: ErrImagePull
    Normal   BackOff    30s (x6 over 2m)   kubelet            Back-off pulling image
    Warning  Failed     30s (x6 over 2m)   kubelet            Error: ImagePullBackOff
  ```

**第3步：分析错误原因**

**常见错误信息和原因**：

| 错误信息 | 原因 | 解决方法 |
|---------|------|---------|
| `pull access denied` | 权限不足，无法拉取私有镜像 | 检查镜像拉取密钥 |
| `manifest unknown` | 镜像不存在或标签错误 | 检查镜像地址和标签 |
| `timeout` | 网络超时 | 检查网络连接 |
| `repository does not exist` | 仓库不存在 | 检查镜像地址 |

**第4步：检查镜像地址**
- 查看Deployment中的镜像配置：
  ```bash
  kubectl get deployment my-app -n my-app -o yaml | grep image:
  ```
- 确认镜像地址是否正确

**第5步：检查镜像拉取密钥**
- 查看Secret是否存在：
  ```bash
  kubectl get secret acr-secret -n my-app
  ```
- 如果不存在，创建Secret：
  ```bash
  kubectl create secret docker-registry acr-secret \
    --docker-server=registry.cn-hangzhou.aliyuncs.com \
    --docker-username=your-username \
    --docker-password=your-password \
    --docker-email=your-email@example.com \
    -n my-app
  ```

**第6步：验证镜像是否存在**
- 在本地测试拉取镜像：
  ```bash
  docker pull registry.cn-hangzhou.aliyuncs.com/my-namespace/my-app:v1.0.0
  ```
- 如果本地可以拉取，说明镜像存在，问题在于Kubernetes的配置

**第7步：修复问题**
- 如果是镜像地址错误，修改Deployment：
  ```bash
  kubectl set image deployment/my-app my-app=正确的镜像地址 -n my-app
  ```
- 如果是密钥问题，确保Deployment中配置了imagePullSecrets：
  ```yaml
  spec:
    imagePullSecrets:
    - name: acr-secret
  ```

**第8步：验证修复**
- 查看Pod状态：
  ```bash
  kubectl get pods -n my-app -w
  ```
- 应该看到Pod从ImagePullBackOff变为Running

### ✅ 验证点
- 理解ImagePullBackOff的原因
- 能够通过describe命令查看详细错误
- 能够修复镜像拉取问题
- Pod状态变为Running

### ⚠️ 常见问题

**问题1：镜像地址明明是对的，为什么还是拉取失败？**
- 答：可能是权限问题
- 检查镜像仓库是否是私有的
- 检查镜像拉取密钥是否正确
- 检查密钥是否在正确的命名空间

**问题2：如何验证镜像拉取密钥是否正确？**
- 答：查看Secret的内容
  ```bash
  kubectl get secret acr-secret -n my-app -o yaml
  ```
- 检查.dockerconfigjson字段是否正确

**问题3：为什么有时是ErrImagePull，有时是ImagePullBackOff？**
- 答：这是重试机制
- ErrImagePull：第一次拉取失败
- ImagePullBackOff：多次失败后，进入退避重试状态
- 本质上是同一个问题

**问题4：如何加速镜像拉取？**
- 答：使用镜像缓存
- 在节点上预先拉取常用镜像
- 使用阿里云的镜像加速器
- 使用更小的镜像（如Alpine）

### 💡 小贴士
- 🔍 describe命令是排查ImagePullBackOff的关键
- 🔑 镜像拉取密钥必须在Pod所在的命名空间
- 📝 建议在本地先测试镜像拉取
- ⏰ 镜像拉取失败会自动重试，有指数退避机制

---

## 步骤7.2：Pod故障排查 - CrashLoopBackOff

### 🎬 操作说明
CrashLoopBackOff表示Pod启动后立即崩溃，Kubernetes不断尝试重启。这通常是应用代码或配置问题导致的。

### 📍 详细步骤

**第1步：识别错误**
- 运行命令：
  ```bash
  kubectl get pods -n my-app
  ```
- 如果看到CrashLoopBackOff：
  ```
  NAME                      READY   STATUS             RESTARTS   AGE
  my-app-7d9f8c6b5d-abc12   0/1     CrashLoopBackOff   5          5m
  ```
- 注意RESTARTS列，显示Pod已重启5次

**第2步：查看Pod日志**
- 这是最重要的一步，查看应用的错误日志：
  ```bash
  kubectl logs <Pod名称> -n my-app
  ```
- 可能看到的错误：
  ```
  panic: runtime error: invalid memory address or nil pointer dereference
  [signal SIGSEGV: segmentation violation code=0x1 addr=0x0 pc=0x123456]
  ```

**第3步：查看之前的日志**
- 如果Pod已经重启，当前日志可能为空，查看之前的日志：
  ```bash
  kubectl logs <Pod名称> -n my-app --previous
  ```

**第4步：查看Pod详情**
- 运行命令：
  ```bash
  kubectl describe pod <Pod名称> -n my-app
  ```
- 在Events部分查看：
  ```
  Events:
    Type     Reason     Age                  From               Message
    ----     ------     ----                 ----               -------
    Normal   Created    3m (x5 over 5m)      kubelet            Created container my-app
    Normal   Started    3m (x5 over 5m)      kubelet            Started container my-app
    Warning  BackOff    1m (x20 over 4m)     kubelet            Back-off restarting failed container
  ```

**第5步：分析常见原因**

**CrashLoopBackOff的常见原因**：

| 原因 | 症状 | 解决方法 |
|-----|------|---------|
| 应用代码错误 | 日志显示panic或exception | 修复代码，重新构建镜像 |
| 端口配置错误 | 日志显示"address already in use" | 检查端口配置 |
| 环境变量缺失 | 日志显示"environment variable not set" | 添加环境变量 |
| 依赖服��不可用 | 日志显示"connection refused" | 检查依赖服务 |
| 启动命令错误 | 日志显示"command not found" | 检查Dockerfile的CMD |
| 资源不足 | 日志显示"OOMKilled" | 增加内存限制 |

**第6步：检查容器配置**
- 查看容器的启动命令：
  ```bash
  kubectl get pod <Pod名称> -n my-app -o yaml | grep -A 5 command
  ```
- 查看环境变量：
  ```bash
  kubectl get pod <Pod名称> -n my-app -o yaml | grep -A 10 env
  ```

**第7步：进入容器调试（如果容器能短暂运行）**
- 如果容器能运行几秒钟，快速进入调试：
  ```bash
  kubectl exec -it <Pod名称> -n my-app -- sh
  ```
- 在容器内检查：
  - 文件是否存在
  - 权限是否正确
  - 环境变量是否正确

**第8步：修复问题**
- 根据日志中的错误信息修复问题
- 常见修复方法：
  - 修复代码，重新构建镜像
  - 添加缺失的环境变量
  - 修改资源限制
  - 修改启动命令

**第9步：更新Deployment**
- 如果修改了镜像：
  ```bash
  kubectl set image deployment/my-app my-app=新镜像地址 -n my-app
  ```
- 如果修改了配置：
  ```bash
  kubectl apply -f base/deployment.yaml
  ```

**第10步：验证修复**
- 查看Pod状态：
  ```bash
  kubectl get pods -n my-app -w
  ```
- 查看日志确认应用正常启动：
  ```bash
  kubectl logs -f <Pod名称> -n my-app
  ```

### ✅ 验证点
- 能够查看Pod日志
- 能够查看之前的日志（--previous）
- 能够分析日志中的错误信息
- 能够修复问题并验证

### ⚠️ 常见问题

**问题1：日志为空怎么办？**
- 答：使用--previous查看之前的日志
- 或者Pod启动太快就崩溃了，来不及输出日志
- 可以在代码中添加更多日志

**问题2：如何区分是代码问题还是配置问题？**
- 答：看日志
- 代码问题：通常有panic、exception、error等关键词
- 配置问题：通常有"not found"、"permission denied"等

**问题3：Pod一直重启，如何停止？**
- 答：删除Pod或缩容Deployment
  ```bash
  kubectl scale deployment my-app --replicas=0 -n my-app
  ```
- 修复问题后再扩容

**问题4：如何在本地复现问题？**
- 答：使用相同的镜像在本地运行
  ```bash
  docker run -it --rm 镜像地址
  ```
- 这样可以更方便地调试

### 💡 小贴士
- 📝 日志是排查CrashLoopBackOff的关键
- 🔍 使用--previous查看之前的日志
- 🎯 在本地复现问题更容易调试
- ⏰ 重启次数越多，重启间隔越长（指数退避）

---

## 步骤7.3：Pod故障排查 - Pending状态

### 🎬 操作说明
Pending状态表示Pod无法被调度到节点上，通常是资源不足或配置问题导致的。

### 📍 详细步骤

**第1步：识别错误**
- 运行命令：
  ```bash
  kubectl get pods -n my-app
  ```
- 如果看到Pending状态：
  ```
  NAME                      READY   STATUS    RESTARTS   AGE
  my-app-7d9f8c6b5d-abc12   0/1     Pending   0          5m
  ```

**第2步：查看Pod详情**
- 运行命令：
  ```bash
  kubectl describe pod <Pod名称> -n my-app
  ```
- 在Events部分查看原因：
  ```
  Events:
    Type     Reason            Age   From               Message
    ----     ------            ----  ----               -------
    Warning  FailedScheduling  5m    default-scheduler  0/2 nodes are available: 2 Insufficient cpu.
  ```

**第3步：分析常见原因**

**Pending的常见原因**：

| 原因 | 错误信息 | 解决方法 |
|-----|---------|---------|
| CPU不足 | `Insufficient cpu` | 减少CPU requests或增加节点 |
| 内存不足 | `Insufficient memory` | 减少内存requests或增加节点 |
| 节点不可用 | `0/0 nodes are available` | 检查节点状态 |
| 镜像拉取密钥不存在 | `secret not found` | 创建Secret |
| PVC不可用 | `persistentvolumeclaim not found` | 创建PVC |
| 节点选择器不匹配 | `node(s) didn't match node selector` | 检查nodeSelector |

**第4步：检查节点资源**
- 查看节点资源使用情况：
  ```bash
  kubectl top nodes
  ```
- 输出示例：
  ```
  NAME    CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
  node1   1800m        90%    3000Mi          75%
  node2   1900m        95%    3500Mi          87%
  ```

**第5步：检查Pod的资源请求**
- 查看Pod的资源requests：
  ```bash
  kubectl get pod <Pod名称> -n my-app -o yaml | grep -A 4 resources
  ```
- 输出示例：
  ```yaml
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
  ```

**第6步：计算是否有足够资源**
- 节点可用资源 = 节点总资源 - 已分配的requests
- 如果Pod的requests大于节点可用资源，无法调度

**第7步：解决资源不足问题**

**方案1：减少资源请求**
- 修改Deployment，减少requests：
  ```yaml
  resources:
    requests:
      cpu: 50m        # 从100m减少到50m
      memory: 64Mi    # 从128Mi减少到64Mi
  ```
- 应用修改：
  ```bash
  kubectl apply -f base/deployment.yaml
  ```

**方案2：增加节点**
- 在ACK控制台扩容节点池
- 或者使用命令行：
  ```bash
  # 这需要在ACK控制台操作，kubectl无法直接扩容节点
  ```

**方案3：删除不需要的Pod**
- 如果有其他不重要的Pod，可以删除释放资源：
  ```bash
  kubectl delete pod <不需要的Pod> -n <命名空间>
  ```

**第8步：验证修复**
- 查看Pod状态：
  ```bash
  kubectl get pods -n my-app -w
  ```
- 应该看到Pod从Pending变为Running

### ✅ 验证点
- 理解Pending的原因
- 能够查看节点资源使用情况
- 能够计算是否有足够资源
- 能够解决资源不足问题

### ⚠️ 常见问题

**问题1：如何查看节点的总资源？**
- 答：使用describe命令
  ```bash
  kubectl describe node <节点名称>
  ```
- 查看Capacity和Allocatable部分

**问题2：requests和limits有什么区别？**
- 答：requests用于调度，limits用于限制
- 调度器根据requests决定Pod放在哪个节点
- 运行时根据limits限制Pod的资源使用
- requests应该设置为正常使用量，limits设置为峰值

**问题3：为什么节点还有资源，Pod还是Pending？**
- 答：可能是其他原因
- 检查是否有nodeSelector或affinity配置
- 检查是否有taints和tolerations
- 检查是否有PVC等其他依赖

**问题4：如何临时增加节点资源？**
- 答：在ACK控制台操作
- 进入集群详情 → 节点池 → 扩容
- 或者创建新的节点池

### 💡 小贴士
- 📊 定期检查节点资源使用情况
- 🎯 合理设置资源requests，避免过度分配
- 💰 资源不足时，考虑成本和性能的平衡
- 🔍 使用kubectl top命令查看实际资源使用情况

---

## 步骤7.4：网络故障排查

### 🎬 操作说明
网络问题是Kubernetes中常见的故障类型，包括Service无法访问、Ingress无法访问等。我们需要系统地排查网络问题。

### 📍 详细步骤

**第1步：Service连通性测试**
- 创建测试Pod：
  ```bash
  kubectl run test --image=busybox -it --rm -n my-app -- sh
  ```
- 在Pod内测试Service：
  ```bash
  # 测试Service名称
  wget -O- http://my-app

  # 测试完整域名
  wget -O- http://my-app.my-app.svc.cluster.local

  # 测试ClusterIP
  wget -O- http://10.96.123.456
  ```

**第2步：检查Service配置**
- 查看Service：
  ```bash
  kubectl get svc my-app -n my-app
  ```
- 检查Endpoints：
  ```bash
  kubectl get endpoints my-app -n my-app
  ```
- 如果Endpoints为空，说明Service没有找到Pod

**第3步：检查标签匹配**
- 查看Service的selector：
  ```bash
  kubectl get svc my-app -n my-app -o yaml | grep -A 2 selector
  ```
- 查看Pod的labels：
  ```bash
  kubectl get pods -n my-app --show-labels
  ```
- 确保selector和labels一致

**第4步：检查Ingress配置**
- 查看Ingress：
  ```bash
  kubectl get ingress -n my-app
  ```
- 检查Ingress详情：
  ```bash
  kubectl describe ingress my-app -n my-app
  ```

**第5步：检查DNS解析**
- 测试域名解析：
  ```bash
  nslookup www.example.com
  ```
- 应该返回ALB的公网IP

**第6步：检查ALB状态**
- 在ALB控制台查看：
  - ALB实例是否运行中
  - 监听器是否配置正确
  - 后端服务器组是否有健康的服务器

### ✅ 验证点
- Service可以在集群内部访问
- Service的Endpoints不为空
- Ingress有ADDRESS
- DNS解析正确

### ⚠️ 常见问题

**问题1：Service可以访问，但Ingress无法访问？**
- 答：检查Ingress配置
- 检查域名是否正确
- 检查SSL证书是否签发
- 检查ALB的安全组

**问题2：如何测试Pod之间的网络？**
- 答：使用ping或wget
  ```bash
  kubectl exec -it <Pod1> -n my-app -- ping <Pod2的IP>
  ```

**问题3：CoreDNS不工作怎么办？**
- 答：检查CoreDNS的Pod
  ```bash
  kubectl get pods -n kube-system -l k8s-app=kube-dns
  ```
- 查看日志：
  ```bash
  kubectl logs -n kube-system -l k8s-app=kube-dns
  ```

### 💡 小贴士
- 🔍 从Pod到Service到Ingress，逐层排查
- 📝 Endpoints是关键，如果为空说明Service配置有问题
- 🌐 DNS问题通常是CoreDNS的问题

---

## 步骤7.5：应用回滚操作

### 🎬 操作说明
当新版本出现问题时，我们需要快速回滚到上一个稳定版本。Kubernetes提供了简单的回滚机制。

### 📍 详细步骤

**第1步：查看部署历史**
- 运行命令：
  ```bash
  kubectl rollout history deployment/my-app -n my-app
  ```
- 输出示例：
  ```
  deployment.apps/my-app
  REVISION  CHANGE-CAUSE
  1         <none>
  2         <none>
  3         <none>
  ```

**第2步：查看特定版本的详情**
- 运行命令：
  ```bash
  kubectl rollout history deployment/my-app -n my-app --revision=2
  ```
- 可以看到该版本的配置

**第3步：回滚到上一个版本**
- 运行命令：
  ```bash
  kubectl rollout undo deployment/my-app -n my-app
  ```
- 这会回滚到上一个版本（REVISION 2）

**第4步：回滚到指定版本**
- 运行命令：
  ```bash
  kubectl rollout undo deployment/my-app -n my-app --to-revision=1
  ```
- 这会回滚到REVISION 1

**第5步：查看回滚状态**
- 运行命令：
  ```bash
  kubectl rollout status deployment/my-app -n my-app
  ```
- 输出示例：
  ```
  Waiting for deployment "my-app" rollout to finish: 1 out of 2 new replicas have been updated...
  deployment "my-app" successfully rolled out
  ```

**第6步：验证回滚**
- 查看Pod：
  ```bash
  kubectl get pods -n my-app
  ```
- 查看镜像版本：
  ```bash
  kubectl get deployment my-app -n my-app -o yaml | grep image:
  ```

### ✅ 验证点
- 能够查看部署历史
- 能够回滚到上一个版本
- 能够回滚到指定版本
- 回滚后应用正常工作

### ⚠️ 常见问题

**问题1：为什么CHANGE-CAUSE是<none>？**
- 答：没有记录变更原因
- 可以在apply时添加：
  ```bash
  kubectl apply -f deployment.yaml --record
  ```
- 或者添加annotation：
  ```bash
  kubectl annotate deployment/my-app kubernetes.io/change-cause="更新到v1.0.1" -n my-app
  ```

**问题2：回滚会丢失数据吗？**
- 答：不会
- 回滚只是更换镜像版本
- 数据存储在PVC或外部数据库中，不受影响

**问题3：如何暂停和恢复滚动更新？**
- 答：使用pause和resume命令
  ```bash
  # 暂停
  kubectl rollout pause deployment/my-app -n my-app

  # 恢复
  kubectl rollout resume deployment/my-app -n my-app
  ```

### 💡 小贴士
- 🔄 回滚是无损操作，可以放心使用
- 📝 建议使用--record记录变更原因
- ⏰ 回滚速度很快，通常1-2分钟完成

---

## 步骤7.6：成本优化建议

### 🎬 操作说明
ACK集群会持续产生费用，我们需要了解如何优化成本。这里介绍几种常见的成本优化方法。

### 📍 详细说明

**成本构成分析**

| 资源类型 | 月成本 | 优化空间 | 优化后成本 |
|---------|-------|---------|-----------|
| Worker节点（2个2核4G） | ¥446 | 高 | ¥134-223 |
| ALB实例（alb.s1.small） | ¥60 | 中 | ¥30-60 |
| 流量费用 | ¥10-50 | 低 | ¥10-50 |
| **总计** | **¥516-556** | - | **¥174-333** |

**优化方案对比**

**方案1：使用抢占式实例（节省70%）**

优点：
- 成本降低70%（¥446 → ¥134）
- 配置和使用方式完全相同
- 适合无状态应用

缺点：
- 可能被回收（概率较低）
- 回收前有3分钟通知时间
- 不适合有状态应用

操作方法：
- 在ACK控制台创建节点池时
- 选择"抢占式实例"
- 其他配置保持不变

**方案2：单节点部署（节省50%）**

优点：
- 成本降低50%（¥446 → ¥223）
- 配置简单
- 适合学习和测试

缺点：
- 没有高可用
- 节点故障会导致服务中断
- 不适合生产环境

操作方法：
- 修改Deployment的replicas为1
- 节点池只保留1个节点

**方案3：使用Serverless K8s（按需付费）**

优点：
- 按Pod运行时间计费
- 无需管理节点
- 自动扩缩容

缺点：
- 单价较高
- 冷启动时间较长
- 网络配置复杂

适用场景：
- 突发流��
- 定时任务
- 测试环境

**方案4：定时启停集群**

优点：
- 非工作时间停止，节省成本
- 适合开发和测试环境

缺点：
- 需要手动或脚本控制
- 启动需要时间

操作方法：
- 缩容节点池到0：
  ```bash
  # 在ACK控制台操作
  ```
- 需要时再扩容

**方案5：优化资源配置**

优点：
- 根据实际使用情况调整
- 避免资源浪费

操作方法：
- 查看实际资源使用：
  ```bash
  kubectl top pods -n my-app
  kubectl top nodes
  ```
- 调整Deployment的resources配置
- 使用更小的节点规格

### ✅ 验证点
- 理解成本构成
- 了解各种优化方案的优缺点
- 能够根据场景选择合适的方案

### ⚠️ 常见问题

**问题1：抢占式实例会经常被回收吗？**
- 答：概率较低
- 阿里云会提前3分钟通知
- 可以配置自动迁移
- 实际使用中，回收频率很低

**问题2：如何监控成本？**
- 答：使用阿里云的费用中心
- 可以设置预算告警
- 定期查看账单明细

**问题3：学习测试用哪个方案最省钱？**
- 答：单节点 + 抢占式实例
- 成本约¥67/月（节省88%）
- 完全够用

### 💡 小贴士
- 💰 学习测试环境优先考虑成本
- 🎯 生产环境优先考虑稳定性
- 📊 定期检查资源使用情况
- ⏰ 不用时及时删除资源

---

## 步骤7.7：彻底清理资源

### 🎬 操作说明
学习完成后，我们需要彻底清理所有资源，避免继续产生费用。清理顺序很重要，按照从应用到基础设施的顺序清理。

### 📍 详细步骤

**第1步：删除应用资源**
- 删除所有应用资源：
  ```bash
  kubectl delete -f base/
  ```
- 或者逐个删除：
  ```bash
  kubectl delete ingress my-app -n my-app
  kubectl delete svc my-app -n my-app
  kubectl delete deployment my-app -n my-app
  kubectl delete namespace my-app
  ```

**第2步：验证应用资源已删除**
- 运行命令：
  ```bash
  kubectl get all -n my-app
  ```
- 应该显示"No resources found"

**第3步：删除ALB实例**
- 进入ALB控制台：https://slb.console.aliyun.com/
- 找到创建的ALB实例
- 点击"删除"
- 确认删除

**第4步：删除ACK集群**
- 进入ACK控制台：https://cs.console.aliyun.com/
- 找到创建的集群
- 点击"删除"
- 勾选"删除集群下的所有资源"
- 输入集群名称确认
- 点击"确定"
- 等待约5-10分钟

**第5步：删除VPC网络（可选）**
- 如果VPC是专门为这个项目创建的，可以删除
- 进入VPC控制台：https://vpc.console.aliyun.com/
- 先删除交换机
- 再删除VPC

**第6步：删除ACR镜像（可选）**
- 进入ACR控制台：https://cr.console.aliyun.com/
- 删除不需要的镜像
- 删除命名空间（如果不再使用）

**第7步：验证资源已释放**
- 检查ECS实例列表，确认Worker节点已删除
- 检查SLB/ALB列表，确认负载均衡器已删除
- 检查VPC列表，确认VPC已删除（如果删除了）

**第8步：检查账单**
- 进入费用中心：https://expense.console.aliyun.com/
- 查看账单明细
- 确认没有持续产生的费用
- 如果有，检查是否有遗漏的资源

### ✅ 验证点
- 所有应用资源已删除
- ALB实例已删除
- ACK集群已删除
- VPC已删除（如果需要）
- 账单中没有持续产生的费用

### ⚠️ 常见问题

**问题1：删除集群时提示"有资源正在使用"？**
- 答：可能有LoadBalancer类型的Service
- 先删除所有Service：
  ```bash
  kubectl delete svc --all --all-namespaces
  ```
- 然后再删除集群

**问题2：删除VPC时提示"有资源正在使用"？**
- 答：VPC中还有其他资源
- 检查是否有ECS实例
- 检查是否有SLB/ALB实例
- 检查是否有NAT网关
- 先删除这些资源，再删除VPC

**问题3：删除后还在计费？**
- 答：检查是否有遗漏的资源
- 常见遗漏：
  - 快照（ECS磁盘快照）
  - 镜像（自定义镜像）
  - 日志服务（SLS）
  - 监控服务

**问题4：如何确认所有资源都删除了？**
- 答：在各个控制台检查
- ECS控制台：检查实例列表
- SLB/ALB控制台：检查负载均衡器列表
- VPC控制台：检查VPC列表
- ACR控制台：检查镜像列表

### 💡 小贴士
- 🗑️ 删除顺序：应用 → ALB → 集群 → VPC
- 💰 删除后24小时内检查账单
- 📝 建议截图保存配置，方便后续参考
- ⚠️ 删除操作不可恢复，请谨慎操作

---

## 模块总结

### 🎉 恭喜！你已经完成了整个ACK部署SOP

在这个模块中，我们学习了：

1. ✅ **Pod故障排查**
   - ImagePullBackOff：镜像拉取失败
   - CrashLoopBackOff：应用启动失败
   - Pending：资源不足或调度失败

2. ✅ **网络故障排查**
   - Service连通性测试
   - Ingress配置检查
   - DNS解析问题

3. ✅ **应用回滚**
   - 查看部署历史
   - 回滚到上一个版本
   - 回滚到指定版本

4. ✅ **成本优化**
   - 使用抢占式实例（节省70%）
   - 单节点部署（节省50%）
   - 定时启停集群
   - 优化资源配置

5. ✅ **资源清理**
   - 删除应用资源
   - 删除ALB实例
   - 删除ACK集群
   - 删除VPC网络

### 📊 故障排查速查表

| 问题 | 症状 | 排查命令 | 常见原因 |
|-----|------|---------|---------|
| ImagePullBackOff | Pod无法启动 | `kubectl describe pod` | 镜像地址错误、权限不足 |
| CrashLoopBackOff | Pod不断重启 | `kubectl logs --previous` | 应用代码错误、配置错误 |
| Pending | Pod无法调度 | `kubectl describe pod` | 资源不足、节点不可用 |
| Service无法访问 | 集群内无法访问 | `kubectl get endpoints` | 标签不匹配、端口错误 |
| Ingress无法访问 | 外网无法访问 | `kubectl describe ingress` | DNS未生效、证书未签发 |

### 🎯 最佳实践总结

**开发环境**：
- 使用单节点 + 抢占式实例
- 成本约¥67/月
- 不用时及时删除

**生产环境**：
- 使用至少2个节点（高可用）
- 配置资源限制和健康检查
- 配置监控告警
- 定期备份配置文件

**故障排查**：
- 从Pod到Service到Ingress，逐层排查
- 善用describe和logs命令
- 保持冷静，系统分析

**成本控制**：
- 定期检查资源使用情况
- 删除不需要的资源
- 使用抢占式实例
- 优化资源配置

### 💡 重要提示

- 🎓 **学习建议**：多实践，多排查问题，积累经验
- 📚 **文档建议**：收藏Kubernetes官方文档和阿里云ACK文档
- 🔍 **排查建议**：善用Google和Stack Overflow
- 💰 **成本建议**：学习完成后及时清理资源

### 📖 常用命令速查

```bash
# 查看资源
kubectl get pods/svc/ingress/deployment -n <namespace>

# 查看详情
kubectl describe pod/svc/ingress/deployment <name> -n <namespace>

# 查看日志
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous

# 进入容器
kubectl exec -it <pod-name> -n <namespace> -- sh

# 端口转发
kubectl port-forward pod/<pod-name> 8080:8080 -n <namespace>

# 扩缩容
kubectl scale deployment <name> --replicas=<number> -n <namespace>

# 更新镜像
kubectl set image deployment/<name> <container>=<image> -n <namespace>

# 回滚
kubectl rollout undo deployment/<name> -n <namespace>

# 查看资源使用
kubectl top nodes
kubectl top pods -n <namespace>

# 删除资源
kubectl delete pod/svc/ingress/deployment <name> -n <namespace>
kubectl delete -f <file.yaml>
```

### 🎉 结语

恭喜你完成了整个阿里云ACK部署SOP！

你现在已经掌握了：
- ✅ 从零开始创建ACK集群
- ✅ 配置网络和负载均衡
- ✅ 构建和推送Docker镜像
- ✅ 部署应用到Kubernetes
- ✅ 排查和解决常见问题
- ✅ 优化成本和清理资源

这些技能是云原生开发的基础，继续学习和实践，你会越来越熟练！

**下一步学习建议**：
1. 学习Kubernetes的高级特性（StatefulSet、DaemonSet、Job等）
2. 学习Helm包管理工具
3. 学习CI/CD流水线（Jenkins、GitLab CI、ArgoCD等）
4. 学习服务网格（Istio、Linkerd等）
5. 学习可观测性（Prometheus、Grafana、Jaeger等）

**推荐资源**：
- Kubernetes官方文档：https://kubernetes.io/docs/
- 阿里云ACK文档：https://help.aliyun.com/product/85222.html
- Kubernetes中文社区：https://kubernetes.io/zh-cn/

祝你在云原生的道路上越走越远！🚀

---

**导航**：
- **上一步**：[模块6：部署应用到K8s](/blog/devops/posts/2026-01-29-ack-sop-06-deploy-app/)
- **返回主索引**：[阿里云ACK部署SOP](/blog/devops/posts/2026-01-29-aliyun-ack-deployment-sop/)