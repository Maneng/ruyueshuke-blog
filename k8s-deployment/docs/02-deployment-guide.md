# Hugo博客系统 - Kubernetes部署实战指南

## 完整部署步骤

本文档提供从零开始部署Hugo博客到阿里云ACK的完整步骤。

---

## 前置准备

### 1. 阿里云账号准备

- [ ] 注册阿里云账号
- [ ] 完成实名认证
- [ ] 开通容器服务ACK
- [ ] 开通容器镜像服务ACR
- [ ] 开通文件存储NAS(可选)

### 2. 本地工具安装

```bash
# macOS
brew install kubectl
brew install docker

# Linux (Ubuntu/Debian)
sudo apt-get update
sudo apt-get install -y kubectl docker.io

# 验证安装
kubectl version --client
docker --version
```

### 3. 域名准备

- [ ] 域名已备案(如使用国内服务器)
- [ ] 域名DNS解析已配置

---

## 第一阶段: 创建ACK集群

### 步骤1: 登录阿里云控制台

1. 访问 [阿里云容器服务控制台](https://cs.console.aliyun.com/)
2. 点击"集群" → "创建集群"

### 步骤2: 选择集群类型

**推荐配置**:
- **集群类型**: 托管版Kubernetes
- **Kubernetes版本**: 1.28.x (最新稳定版)
- **地域**: 选择离用户最近的地域(如华东1-杭州)
- **可用区**: 选择2个可用区(高可用)

### 步骤3: 配置Worker节点

**方案A: 双节点高可用** (推荐企业使用)
```
节点规格: ecs.t6-c1m2.large (2核4G)
节点数量: 2
系统盘: 40GB ESSD云盘
数据盘: 100GB ESSD云盘
```

**方案B: 单节点成本优化** (推荐个人使用)
```
节点规格: ecs.t6-c1m2.large (2核4G)
节点数量: 1
系统盘: 40GB ESSD云盘
数据盘: 100GB ESSD云盘
```

### 步骤4: 网络配置

```
VPC网络: 新建VPC (或选择已有VPC)
VPC网段: 192.168.0.0/16
Pod网段: 172.20.0.0/16
Service网段: 172.21.0.0/20
```

### 步骤5: 组件配置

**必选组件**:
- [x] Nginx Ingress Controller
- [x] 日志服务(可选,用于监控)

**可选组件**:
- [ ] cert-manager (SSL证书管理)
- [ ] Prometheus (监控)

### 步骤6: 创建集群

1. 点击"创建集群"
2. 等待10-15分钟,集群创建完成
3. 记录集群ID和访问地址

---

## 第二阶段: 配置kubectl访问

### 步骤1: 获取kubeconfig

1. 进入ACK集群管理页面
2. 点击"连接信息"
3. 复制"公网访问"的kubeconfig内容

### 步骤2: 配置本地kubectl

```bash
# 创建.kube目录
mkdir -p ~/.kube

# 保存kubeconfig
cat > ~/.kube/config << 'EOF'
# 粘贴从阿里云复制的kubeconfig内容
EOF

# 设置权限
chmod 600 ~/.kube/config

# 验证连接
kubectl cluster-info
kubectl get nodes
```

**预期输出**:
```
NAME                                 STATUS   ROLES    AGE   VERSION
cn-hangzhou.192.168.0.1              Ready    <none>   1h    v1.28.3
cn-hangzhou.192.168.0.2              Ready    <none>   1h    v1.28.3
```

---

## 第三阶段: 创建ACR镜像仓库

### 步骤1: 登录ACR控制台

访问 [容器镜像服务控制台](https://cr.console.aliyun.com/)

### 步骤2: 创建命名空间

1. 点击"命名空间" → "创建命名空间"
2. 命名空间名称: `blog-system`
3. 访问级别: 私有

### 步骤3: 创建镜像仓库

**仓库1: Hugo博客**
```
仓库名称: hugo-blog
命名空间: blog-system
仓库类型: 私有
代码源: 本地仓库
```

**仓库2: 访客统计**
```
仓库名称: visitor-stats
命名空间: blog-system
仓库类型: 私有
代码源: 本地仓库
```

### 步骤4: 获取访问凭证

1. 点击"访问凭证"
2. 设置固定密码
3. 记录用户名和密码

### 步骤5: 本地登录ACR

```bash
# 登录ACR
docker login --username=<your-username> registry.cn-hangzhou.aliyuncs.com

# 输入密码
Password: <your-password>

# 验证登录
docker info | grep Username
```

---

## 第四阶段: 安装cert-manager

### 步骤1: 安装cert-manager

```bash
# 安装cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# 等待Pod就绪
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s

# 验证安装
kubectl get pods -n cert-manager
```

**预期输出**:
```
NAME                                       READY   STATUS    RESTARTS   AGE
cert-manager-7d9f8c8c8-xxxxx              1/1     Running   0          2m
cert-manager-cainjector-5d9f8c8c8-xxxxx   1/1     Running   0          2m
cert-manager-webhook-5d9f8c8c8-xxxxx      1/1     Running   0          2m
```

---

## 第五阶段: 构建和推送镜像

### 步骤1: 克隆代码仓库

```bash
# 克隆仓库
git clone https://github.com/Maneng/blog.git
cd blog

# 更新子模块
git submodule update --init --recursive
```

### 步骤2: 本地构建镜像

```bash
# 构建镜像
./k8s-deployment/scripts/build-images.sh

# 查看构建结果
docker images | grep -E "hugo-blog|visitor-stats"
```

### 步骤3: 推送镜像到ACR

```bash
# 推送镜像
./k8s-deployment/scripts/push-images.sh

# 验证推送
# 访问ACR控制台查看镜像版本
```

---

## 第六阶段: 部署应用到K8s

### 步骤1: 创建NAS存储(可选)

如果使用访客统计功能,需要创建NAS存储:

1. 访问 [文件存储NAS控制台](https://nas.console.aliyun.com/)
2. 创建文件系统
   - 存储类型: 性能型
   - 协议类型: NFS
   - 容量: 10GB
3. 创建挂载点
   - VPC: 选择ACK集群所在VPC
   - 交换机: 选择ACK集群所在交换机
4. 记录挂载点地址

### 步骤2: 配置存储类(如使用NAS)

```bash
# 创建NAS存储类
cat > nas-storageclass.yaml << 'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: alicloud-nas
provisioner: nasplugin.csi.alibabacloud.com
parameters:
  server: "your-nas-server.cn-hangzhou.nas.aliyuncs.com"
  path: "/"
  vers: "3"
reclaimPolicy: Retain
EOF

# 应用配置
kubectl apply -f nas-storageclass.yaml
```

### 步骤3: 部署应用

```bash
# 部署所有资源
./k8s-deployment/scripts/deploy.sh

# 或手动部署
kubectl apply -f k8s-deployment/k8s-manifests/00-namespace.yaml
kubectl apply -f k8s-deployment/k8s-manifests/01-hugo-blog.yaml
kubectl apply -f k8s-deployment/k8s-manifests/02-visitor-stats.yaml
kubectl apply -f k8s-deployment/k8s-manifests/04-cert-manager.yaml
kubectl apply -f k8s-deployment/k8s-manifests/03-ingress.yaml
```

### 步骤4: 验证部署

```bash
# 查看Pod状态
kubectl get pods -n blog

# 查看Service
kubectl get svc -n blog

# 查看Ingress
kubectl get ingress -n blog

# 查看证书状态
kubectl get certificate -n blog
```

**预期输出**:
```
NAME                            READY   STATUS    RESTARTS   AGE
hugo-blog-xxxxxxxxx-xxxxx       1/1     Running   0          2m
hugo-blog-xxxxxxxxx-xxxxx       1/1     Running   0          2m
visitor-stats-xxxxxxxxx-xxxxx   1/1     Running   0          2m
```

---

## 第七阶段: 配置域名解析

### 步骤1: 获取Ingress IP

```bash
# 获取Ingress外网IP
kubectl get ingress blog-ingress -n blog

# 输出示例
NAME           CLASS   HOSTS              ADDRESS         PORTS     AGE
blog-ingress   nginx   ruyueshuke.com     47.xxx.xxx.xxx  80, 443   5m
```

### 步骤2: 配置DNS解析

登录域名服务商控制台,添加A记录:

```
记录类型: A
主机记录: @
记录值: 47.xxx.xxx.xxx (Ingress IP)
TTL: 600
```

### 步骤3: 验证域名解析

```bash
# 等待DNS生效(5-10分钟)
nslookup ruyueshuke.com

# 测试访问
curl -I https://ruyueshuke.com/blog/
```

---

## 第八阶段: 配置GitHub Actions自动部署

### 步骤1: 配置GitHub Secrets

进入GitHub仓库 → Settings → Secrets and variables → Actions

添加以下Secrets:

```
ACR_USERNAME: 阿里云ACR用户名
ACR_PASSWORD: 阿里云ACR密码
KUBE_CONFIG: kubectl配置文件(base64编码)
```

**生成KUBE_CONFIG**:
```bash
# 编码kubeconfig
cat ~/.kube/config | base64

# 复制输出内容到GitHub Secrets
```

### 步骤2: 复制GitHub Actions配置

```bash
# 复制工作流配置
cp k8s-deployment/workflows/deploy-k8s.yml .github/workflows/

# 提交代码
git add .github/workflows/deploy-k8s.yml
git commit -m "Add: K8s自动部署工作流"
git push origin main
```

### 步骤3: 验证自动部署

1. 推送代码到main分支
2. 访问GitHub Actions页面
3. 查看部署日志
4. 验证网站更新

---

## 第九阶段: 监控和日志配置

### 步骤1: 配置阿里云日志服务(可选)

1. 访问 [日志服务控制台](https://sls.console.aliyun.com/)
2. 创建Project和Logstore
3. 在ACK集群中安装日志组件

```bash
# 安装日志组件
kubectl apply -f https://raw.githubusercontent.com/AliyunContainerService/log-pilot/master/quickstart/log-pilot.yaml
```

### 步骤2: 配置告警规则

在阿里云SLS控制台配置告警:

- Pod重启次数 > 3
- CPU使用率 > 80%
- 内存使用率 > 80%
- HTTP 5xx错误率 > 5%

---

## 常用运维命令

### 查看资源状态

```bash
# 查看所有资源
kubectl get all -n blog

# 查看Pod详情
kubectl describe pod <pod-name> -n blog

# 查看Pod日志
kubectl logs -f <pod-name> -n blog

# 查看最近事件
kubectl get events -n blog --sort-by='.lastTimestamp'
```

### 更新部署

```bash
# 更新镜像
kubectl set image deployment/hugo-blog nginx=<new-image> -n blog

# 查看滚动更新状态
kubectl rollout status deployment/hugo-blog -n blog

# 查看更新历史
kubectl rollout history deployment/hugo-blog -n blog
```

### 回滚部署

```bash
# 回滚到上一版本
kubectl rollout undo deployment/hugo-blog -n blog

# 回滚到指定版本
kubectl rollout undo deployment/hugo-blog --to-revision=2 -n blog
```

### 扩缩容

```bash
# 手动扩容
kubectl scale deployment/hugo-blog --replicas=3 -n blog

# 查看扩容状态
kubectl get pods -n blog -w
```

### 故障排查

```bash
# 进入Pod调试
kubectl exec -it <pod-name> -n blog -- /bin/sh

# 查看Pod资源使用
kubectl top pods -n blog

# 查看节点资源使用
kubectl top nodes

# 查看证书状态
kubectl describe certificate blog-tls-secret -n blog
```

---

## 故障排查指南

### 问题1: Pod一直处于Pending状态

**原因**: 资源不足或存储未就绪

**解决方案**:
```bash
# 查看Pod事件
kubectl describe pod <pod-name> -n blog

# 检查节点资源
kubectl top nodes

# 检查存储
kubectl get pvc -n blog
```

### 问题2: Ingress无法访问

**原因**: Ingress Controller未安装或配置错误

**解决方案**:
```bash
# 检查Ingress Controller
kubectl get pods -n kube-system | grep ingress

# 检查Ingress配置
kubectl describe ingress blog-ingress -n blog

# 查看Ingress日志
kubectl logs -n kube-system -l app.kubernetes.io/name=ingress-nginx
```

### 问题3: SSL证书未自动申请

**原因**: cert-manager配置错误或域名解析未生效

**解决方案**:
```bash
# 检查cert-manager
kubectl get pods -n cert-manager

# 查看证书申请状态
kubectl get certificate -n blog
kubectl describe certificate blog-tls-secret -n blog

# 查看cert-manager日志
kubectl logs -n cert-manager -l app=cert-manager
```

### 问题4: 访客统计数据丢失

**原因**: PVC未正确挂载或数据未持久化

**解决方案**:
```bash
# 检查PVC状态
kubectl get pvc -n blog

# 检查Pod挂载
kubectl describe pod <visitor-stats-pod> -n blog

# 进入Pod检查数据
kubectl exec -it <visitor-stats-pod> -n blog -- ls -la /data
```

---

## 性能优化建议

### 1. 镜像优化

- 使用多阶段构建减小镜像大小
- 使用alpine基础镜像
- 清理不必要的文件和依赖

### 2. 资源配额优化

根据实际使用情况调整资源配额:

```yaml
resources:
  requests:
    cpu: 50m      # 降低请求值
    memory: 64Mi
  limits:
    cpu: 200m
    memory: 256Mi
```

### 3. 启用缓存

在Ingress中配置缓存:

```yaml
annotations:
  nginx.ingress.kubernetes.io/proxy-buffering: "on"
  nginx.ingress.kubernetes.io/proxy-cache-valid: "200 10m"
```

### 4. 启用CDN

将静态资源托管到阿里云CDN,减轻服务器压力。

---

## 成本优化建议

### 1. 使用抢占式实例

对于非关键业务,可使用抢占式实例降低成本:

```
节点类型: 抢占式实例
成本: 降低70%
风险: 可能被回收
```

### 2. 定时扩缩容

根据流量规律配置定时扩缩容:

```bash
# 工作时间扩容
0 9 * * * kubectl scale deployment/hugo-blog --replicas=2 -n blog

# 夜间缩容
0 22 * * * kubectl scale deployment/hugo-blog --replicas=1 -n blog
```

### 3. 使用Spot实例

配置Spot实例节点池,成本可降低50-70%。

---

## 安全加固建议

### 1. 启用RBAC

创建专用ServiceAccount,限制权限:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: blog-sa
  namespace: blog
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: blog-role
  namespace: blog
rules:
- apiGroups: [""]
  resources: ["pods", "services"]
  verbs: ["get", "list"]
```

### 2. 启用Pod Security Policy

限制Pod的安全上下文:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
```

### 3. 启用Network Policy

限制Pod之间的网络访问:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: blog-network-policy
  namespace: blog
spec:
  podSelector:
    matchLabels:
      app: hugo-blog
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: ingress-nginx
```

---

## 备份和恢复

### 备份策略

```bash
# 备份所有K8s资源
kubectl get all -n blog -o yaml > blog-backup.yaml

# 备份访客统计数据
kubectl exec -it <visitor-stats-pod> -n blog -- tar czf /tmp/stats-backup.tar.gz /data
kubectl cp blog/<visitor-stats-pod>:/tmp/stats-backup.tar.gz ./stats-backup.tar.gz
```

### 恢复策略

```bash
# 恢复K8s资源
kubectl apply -f blog-backup.yaml

# 恢复访客统计数据
kubectl cp ./stats-backup.tar.gz blog/<visitor-stats-pod>:/tmp/
kubectl exec -it <visitor-stats-pod> -n blog -- tar xzf /tmp/stats-backup.tar.gz -C /
```

---

## 总结

完成以上步骤后,您的Hugo博客已成功部署到阿里云ACK集群,具备以下特性:

- ✅ 容器化部署,环境一致
- ✅ 自动化CI/CD流程
- ✅ 高可用架构(双副本)
- ✅ 自动SSL证书管理
- ✅ 滚动更新和快速回滚
- ✅ 统一的监控和日志
- ✅ 弹性伸缩能力

**下一步**:
1. 配置监控告警
2. 优化资源配额
3. 配置自动备份
4. 编写运维文档

---

**文档结束**
