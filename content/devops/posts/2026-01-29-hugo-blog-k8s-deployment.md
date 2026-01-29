---
title: "Hugo博客迁移到阿里云ACK Kubernetes集群完整方案"
date: 2026-01-29T11:00:00+08:00
draft: false
tags: ["Kubernetes", "K8s", "阿里云ACK", "Docker", "容器化", "云原生", "DevOps"]
categories: ["技术"]
description: "详细记录Hugo博客从传统服务器部署迁移到阿里云ACK Kubernetes集群的完整方案，包括容器化、K8s配置、CI/CD改造、成本分析和最佳实践。"
---

## 方案概述

本文档提供Hugo博客从**传统服务器部署**迁移到**阿里云ACK Kubernetes集群**的完整技术方案，包括容器化、K8s资源配置、CI/CD流程改造和实战部署步骤。

### 架构对比

**当前架构（传统部署）**：
```
本地开发 → Git推送 → GitHub Actions构建 → rsync同步 → Nginx服务器 → 用户访问
```

**目标架构（K8s部署）**：
```
本地开发 → Git推送 → GitHub Actions构建 → Docker镜像 → 阿里云ACR → K8s集群 → Ingress → 用户访问
```

### 核心变化

| 维度 | 传统部署 | K8s部署 |
|------|---------|---------|
| **部署方式** | SSH + rsync | kubectl apply |
| **运行环境** | 直接在服务器 | Docker容器 |
| **负载均衡** | 单机Nginx | K8s Service + Ingress |
| **扩展性** | 手动扩容 | 自动扩缩容 |
| **更新策略** | 直接覆盖 | 滚动更新 |
| **回滚** | 手动恢复 | kubectl rollout undo |
| **成本** | ¥0/月 | ¥200-500/月 |

## 一、容器化方案

### 1.1 Dockerfile设计（多阶段构建）

创建 `docker/Dockerfile`：

```dockerfile
# 阶段1：构建阶段
FROM klakegg/hugo:0.150.1-ext-alpine AS builder

# 设置工作目录
WORKDIR /src

# 复制源代码
COPY . .

# 构建静态网站
RUN hugo --minify

# 阶段2：运行阶段
FROM nginx:1.25-alpine

# 复制自定义Nginx配置
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf

# 从构建阶段复制生成的静态文件
COPY --from=builder /src/public /usr/share/nginx/html

# 暴露端口
EXPOSE 80

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost/ || exit 1

# 启动Nginx
CMD ["nginx", "-g", "daemon off;"]
```

**多阶段构建优势**：
- **镜像体积小**：最终镜像只包含Nginx和静态文件，不包含Hugo
- **构建速度快**：利用Docker缓存层
- **安全性高**：运行时镜像不包含构建工具

### 1.2 Nginx配置

创建 `docker/nginx.conf`：

```nginx
server {
    listen 80;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    # Gzip压缩
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml;

    # 静态资源缓存
    location ~* \.(jpg|jpeg|png|gif|ico|svg|webp)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    location ~* \.(css|js)$ {
        expires 7d;
        add_header Cache-Control "public";
    }

    # SPA路由支持
    location / {
        try_files $uri $uri/ /index.html;
    }

    # 安全头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # 健康检查端点
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
```

### 1.3 构建和测试

```bash
# 构建镜像
docker build -t hugo-blog:latest -f docker/Dockerfile .

# 本地测试
docker run -d -p 8080:80 --name hugo-blog-test hugo-blog:latest

# 访问测试
curl http://localhost:8080

# 查看日志
docker logs hugo-blog-test

# 停止并删除
docker stop hugo-blog-test && docker rm hugo-blog-test
```

## 二、Kubernetes资源配置

### 2.1 目录结构

```
k8s/
├── base/
│   ├── namespace.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   └── configmap.yaml
└── overlays/
    └── production/
        ├── kustomization.yaml
        └── ingress-patch.yaml
```

### 2.2 Namespace配置

创建 `k8s/base/namespace.yaml`：

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: hugo-blog
  labels:
    name: hugo-blog
    environment: production
```

### 2.3 Deployment配置

创建 `k8s/base/deployment.yaml`：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hugo-blog
  namespace: hugo-blog
  labels:
    app: hugo-blog
spec:
  replicas: 2  # 2个副本实现高可用
  selector:
    matchLabels:
      app: hugo-blog
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1        # 滚动更新时最多多1个Pod
      maxUnavailable: 0  # 滚动更新时最多0个Pod不可用（零停机）
  template:
    metadata:
      labels:
        app: hugo-blog
    spec:
      containers:
      - name: hugo-blog
        image: registry.cn-hangzhou.aliyuncs.com/your-namespace/hugo-blog:latest
        imagePullPolicy: Always
        ports:
        - containerPort: 80
          name: http
          protocol: TCP
        resources:
          requests:
            cpu: 100m      # 最小CPU：0.1核
            memory: 128Mi  # 最小内存：128MB
          limits:
            cpu: 200m      # 最大CPU：0.2核
            memory: 256Mi  # 最大内存：256MB
        livenessProbe:   # 存活探针
          httpGet:
            path: /health
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 10
          timeoutSeconds: 3
          failureThreshold: 3
        readinessProbe:  # 就绪探针
          httpGet:
            path: /health
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
      imagePullSecrets:
      - name: acr-secret  # 阿里云ACR密钥
```

### 2.4 Service配置

创建 `k8s/base/service.yaml`：

```yaml
apiVersion: v1
kind: Service
metadata:
  name: hugo-blog
  namespace: hugo-blog
  labels:
    app: hugo-blog
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
    name: http
  selector:
    app: hugo-blog
```

### 2.5 Ingress配置

创建 `k8s/base/ingress.yaml`：

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hugo-blog
  namespace: hugo-blog
  annotations:
    # 使用Nginx Ingress Controller
    kubernetes.io/ingress.class: nginx
    # 自动HTTPS重定向
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    # cert-manager自动签发证书
    cert-manager.io/cluster-issuer: letsencrypt-prod
    # 客户端最大body大小
    nginx.ingress.kubernetes.io/proxy-body-size: "10m"
spec:
  tls:
  - hosts:
    - ruyueshuke.com
    - www.ruyueshuke.com
    secretName: hugo-blog-tls
  rules:
  - host: ruyueshuke.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: hugo-blog
            port:
              number: 80
  - host: www.ruyueshuke.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: hugo-blog
            port:
              number: 80
```

## 三、CI/CD流程改造

### 3.1 改造后的GitHub Actions

创建 `.github/workflows/deploy-k8s.yml`：

```yaml
name: Deploy to ACK Kubernetes

on:
  push:
    branches:
      - main
  workflow_dispatch:

env:
  ACR_REGISTRY: registry.cn-hangzhou.aliyuncs.com
  ACR_NAMESPACE: your-namespace
  IMAGE_NAME: hugo-blog
  K8S_NAMESPACE: hugo-blog

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest

    steps:
      # 步骤1：检出代码
      - name: 📥 Checkout repository
        uses: actions/checkout@v4
        with:
          submodules: true
          fetch-depth: 0

      # 步骤2：设置Docker Buildx
      - name: 🔧 Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      # 步骤3：登录阿里云容器镜像服务
      - name: 🔐 Login to Alibaba Cloud Container Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.ACR_REGISTRY }}
          username: ${{ secrets.ACR_USERNAME }}
          password: ${{ secrets.ACR_PASSWORD }}

      # 步骤4：构建并推送Docker镜像
      - name: 🏗️ Build and push Docker image
        uses: docker/build-push-action@v5
        with:
          context: .
          file: ./docker/Dockerfile
          push: true
          tags: |
            ${{ env.ACR_REGISTRY }}/${{ env.ACR_NAMESPACE }}/${{ env.IMAGE_NAME }}:latest
            ${{ env.ACR_REGISTRY }}/${{ env.ACR_NAMESPACE }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      # 步骤5：配置kubectl
      - name: ⚙️ Configure kubectl
        uses: azure/k8s-set-context@v3
        with:
          method: kubeconfig
          kubeconfig: ${{ secrets.KUBE_CONFIG }}

      # 步骤6：更新K8s Deployment
      - name: 🚀 Deploy to Kubernetes
        run: |
          kubectl set image deployment/hugo-blog \
            hugo-blog=${{ env.ACR_REGISTRY }}/${{ env.ACR_NAMESPACE }}/${{ env.IMAGE_NAME }}:${{ github.sha }} \
            -n ${{ env.K8S_NAMESPACE }}

          kubectl rollout status deployment/hugo-blog -n ${{ env.K8S_NAMESPACE }}

      # 步骤7：验证部署
      - name: ✅ Verify deployment
        run: |
          kubectl get pods -n ${{ env.K8S_NAMESPACE }}
          kubectl get svc -n ${{ env.K8S_NAMESPACE }}
          kubectl get ingress -n ${{ env.K8S_NAMESPACE }}
```

### 3.2 GitHub Secrets配置

需要在GitHub仓库设置中添加以下Secrets：

| Secret名称 | 说明 | 获取方式 |
|-----------|------|----------|
| `ACR_USERNAME` | 阿里云ACR用户名 | 阿里云控制台 → 容器镜像服务 |
| `ACR_PASSWORD` | 阿里云ACR密码 | 阿里云控制台 → 容器镜像服务 |
| `KUBE_CONFIG` | K8s集群配置文件 | `cat ~/.kube/config` |

## 四、阿里云ACK配置

### 4.1 创建ACK集群

**推荐配置**（个人博客场景）：

| 配置项 | 推荐值 | 说明 |
|-------|--------|------|
| **集群类型** | 标准托管版 | 控制平面免费 |
| **节点规格** | ecs.t6-c1m2.large | 2核4G，¥0.18/小时 |
| **节点数量** | 2个 | 高可用 |
| **网络插件** | Flannel | 简单稳定 |
| **存储插件** | CSI | 支持动态PV |
| **日志服务** | 开启 | 集成阿里云SLS |

**创建命令**（使用aliyun CLI）：

```bash
# 安装aliyun CLI
brew install aliyun-cli  # macOS
# 或
curl -O https://aliyuncli.alicdn.com/aliyun-cli-linux-latest-amd64.tgz

# 配置凭证
aliyun configure

# 创建ACK集群
aliyun cs POST /clusters \
  --body "$(cat <<EOF
{
  "name": "hugo-blog-cluster",
  "cluster_type": "ManagedKubernetes",
  "region_id": "cn-hangzhou",
  "kubernetes_version": "1.28.3-aliyun.1",
  "worker_instance_types": ["ecs.t6-c1m2.large"],
  "num_of_nodes": 2,
  "vswitch_ids": ["vsw-xxxxx"],
  "container_cidr": "172.16.0.0/16",
  "service_cidr": "172.17.0.0/16"
}
EOF
)"
```

### 4.2 配置kubectl

```bash
# 下载kubeconfig
aliyun cs GET /k8s/$(CLUSTER_ID)/user_config > ~/.kube/config-ack

# 合并到主配置
export KUBECONFIG=~/.kube/config:~/.kube/config-ack
kubectl config view --flatten > ~/.kube/config-merged
mv ~/.kube/config-merged ~/.kube/config

# 验证连接
kubectl get nodes
```

### 4.3 安装Nginx Ingress Controller

```bash
# 使用Helm安装
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/alibaba-cloud-loadbalancer-spec"="slb.s1.small"
```

### 4.4 安装cert-manager（自动SSL证书）

```bash
# 安装cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# 创建Let's Encrypt Issuer
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
```

## 五、实战部署步骤

### 5.1 准备工作

```bash
# 1. 克隆项目
git clone https://github.com/your-username/hugo-blog.git
cd hugo-blog

# 2. 创建K8s配置目录
mkdir -p k8s/base docker

# 3. 创建所有配置文件（参考上文）
# - docker/Dockerfile
# - docker/nginx.conf
# - k8s/base/*.yaml
# - .github/workflows/deploy-k8s.yml
```

### 5.2 本地测试

```bash
# 1. 构建Docker镜像
docker build -t hugo-blog:test -f docker/Dockerfile .

# 2. 运行容器测试
docker run -d -p 8080:80 --name test hugo-blog:test

# 3. 访问测试
curl http://localhost:8080

# 4. 清理
docker stop test && docker rm test
```

### 5.3 推送到ACR

```bash
# 1. 登录ACR
docker login --username=your-username registry.cn-hangzhou.aliyuncs.com

# 2. 打标签
docker tag hugo-blog:test registry.cn-hangzhou.aliyuncs.com/your-namespace/hugo-blog:v1.0.0

# 3. 推送
docker push registry.cn-hangzhou.aliyuncs.com/your-namespace/hugo-blog:v1.0.0
```

### 5.4 部署到K8s

```bash
# 1. 创建命名空间
kubectl apply -f k8s/base/namespace.yaml

# 2. 创建ACR密钥
kubectl create secret docker-registry acr-secret \
  --docker-server=registry.cn-hangzhou.aliyuncs.com \
  --docker-username=your-username \
  --docker-password=your-password \
  -n hugo-blog

# 3. 部署应用
kubectl apply -f k8s/base/deployment.yaml
kubectl apply -f k8s/base/service.yaml
kubectl apply -f k8s/base/ingress.yaml

# 4. 查看部署状态
kubectl get pods -n hugo-blog
kubectl get svc -n hugo-blog
kubectl get ingress -n hugo-blog
```

### 5.5 配置域名

```bash
# 1. 获取Ingress的LoadBalancer IP
kubectl get svc -n ingress-nginx

# 2. 在域名DNS中添加A记录
# ruyueshuke.com     A    <LoadBalancer-IP>
# www.ruyueshuke.com A    <LoadBalancer-IP>

# 3. 等待DNS生效（5-10分钟）
nslookup ruyueshuke.com

# 4. 访问网站
curl https://ruyueshuke.com
```

## 六、成本分析

### 6.1 详细成本对比

**传统部署成本**：
| 项目 | 费用 | 说明 |
|------|------|------|
| ECS服务器 | 已有 | 复用现有服务器 |
| 域名 | 已有 | 复用现有域名 |
| SSL证书 | ¥0 | Let's Encrypt免费 |
| **总计** | **¥0/月** | 零成本运营 |

**K8s部署成本**：
| 项目 | 费用 | 说明 |
|------|------|------|
| ACK控制平面 | ¥0 | 标准托管版免费 |
| Worker节点×2 | ¥260/月 | ecs.t6-c1m2.large ¥0.18/小时×2×24×30 |
| SLB负载均衡器 | ¥30/月 | slb.s1.small规格 |
| 公网带宽 | ¥20/月 | 5Mbps按固定带宽 |
| 容器镜像服务 | ¥0 | 个人版免费 |
| **总计** | **¥310/月** | 约¥3720/年 |

**成本优化方案**：
1. **使用抢占式实例**：节省50-90%成本（¥130-260/月）
2. **单节点部署**：节省50%成本（¥155/月）
3. **使用Serverless K8s**：按Pod计费，低流量场景更便宜

### 6.2 ROI分析

**适合K8s的场景**：
- ✅ 微服务架构（多个服务）
- ✅ 需要弹性伸缩
- ✅ 高可用要求（99.9%+）
- ✅ 多环境部署（dev/staging/prod）
- ✅ 团队协作开发

**不适合K8s的场景**：
- ❌ 单体静态网站（如本博客）
- ❌ 低流量应用（<1000 PV/天）
- ❌ 个人项目
- ❌ 成本敏感

## 七、运维管理

### 7.1 常用命令

```bash
# 查看Pod状态
kubectl get pods -n hugo-blog

# 查看Pod日志
kubectl logs -f deployment/hugo-blog -n hugo-blog

# 进入Pod调试
kubectl exec -it deployment/hugo-blog -n hugo-blog -- sh

# 查看资源使用
kubectl top pods -n hugo-blog

# 扩容/缩容
kubectl scale deployment/hugo-blog --replicas=3 -n hugo-blog

# 滚动更新
kubectl set image deployment/hugo-blog hugo-blog=new-image:tag -n hugo-blog

# 回滚
kubectl rollout undo deployment/hugo-blog -n hugo-blog

# 查看历史版本
kubectl rollout history deployment/hugo-blog -n hugo-blog
```

### 7.2 监控和日志

**使用阿里云日志服务（SLS）**：

```bash
# 1. 在ACK控制台启用日志服务
# 2. 配置日志采集规则
# 3. 在SLS控制台查看日志

# 查看实时日志
aliyun sls GetLogs \
  --project=k8s-log-xxx \
  --logstore=stdout \
  --query="namespace:hugo-blog"
```

### 7.3 备份和恢复

```bash
# 备份K8s资源
kubectl get all -n hugo-blog -o yaml > backup-$(date +%Y%m%d).yaml

# 恢复
kubectl apply -f backup-20260129.yaml
```

## 八、最佳实践

### 8.1 镜像优化

1. **使用多阶段构建**：减小镜像体积
2. **使用Alpine基础镜像**：更小更安全
3. **合理使用缓存**：加快构建速度
4. **镜像扫描**：定期扫描安全漏洞

### 8.2 资源配置

1. **合理设置requests和limits**：避免资源浪费
2. **配置健康检查**：自动重启故障Pod
3. **使用HPA**：根据CPU/内存自动扩缩容

### 8.3 安全加固

1. **使用非root用户运行**：提高安全性
2. **配置Network Policy**：限制Pod间通信
3. **定期更新镜像**：修复安全漏洞
4. **使用Secret管理敏感信息**：不要硬编码

## 九、故障排查

### 9.1 Pod无法启动

```bash
# 查看Pod事件
kubectl describe pod <pod-name> -n hugo-blog

# 查看Pod日志
kubectl logs <pod-name> -n hugo-blog

# 常见原因：
# - 镜像拉取失败（检查ACR密钥）
# - 资源不足（检查节点资源）
# - 健康检查失败（检查探针配置）
```

### 9.2 Ingress无法访问

```bash
# 查看Ingress状态
kubectl describe ingress hugo-blog -n hugo-blog

# 查看Ingress Controller日志
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller

# 常见原因：
# - DNS未生效（等待5-10分钟）
# - 证书未签发（检查cert-manager）
# - Service配置错误（检查selector）
```

### 9.3 性能问题

```bash
# 查看资源使用
kubectl top pods -n hugo-blog
kubectl top nodes

# 查看Pod事件
kubectl get events -n hugo-blog --sort-by='.lastTimestamp'

# 常见原因：
# - CPU/内存限制过低
# - 副本数不足
# - 节点资源不足
```

## 十、总结

### 10.1 方案对比

| 维度 | 传统部署 | K8s部署 |
|------|---------|---------|
| **成本** | ¥0/月 | ¥310/月 |
| **复杂度** | 低 | 高 |
| **扩展性** | 差 | 优秀 |
| **高可用** | 无 | 有 |
| **运维难度** | 低 | 高 |
| **学习曲线** | 平缓 | 陡峭 |
| **适用场景** | 个人博客 | 企业应用 |

### 10.2 建议

**对于个人博客**：
- ✅ **推荐传统部署**：成本低、简单、够用
- ❌ **不推荐K8s**：成本高、复杂、过度设计

**对于企业应用**：
- ✅ **推荐K8s**：高可用、易扩展、标准化
- ❌ **不推荐传统部署**：难扩展、难管理

### 10.3 学习价值

虽然个人博客不适合K8s，但学习K8s部署有以下价值：
1. **掌握容器化技术**：Docker是现代应用的标准
2. **理解云原生架构**：K8s是云原生的核心
3. **提升运维能力**：K8s是DevOps的重要技能
4. **为未来做准备**：企业级应用必备技能

---

## 参考资料

- [Kubernetes官方文档](https://kubernetes.io/docs/)
- [阿里云ACK文档](https://help.aliyun.com/product/85222.html)
- [Docker官方文档](https://docs.docker.com/)
- [Nginx Ingress Controller](https://kubernetes.github.io/ingress-nginx/)
- [cert-manager文档](https://cert-manager.io/docs/)
- [Hugo官方文档](https://gohugo.io/documentation/)
