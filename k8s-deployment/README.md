# Hugo博客系统 - Kubernetes部署方案

完整的阿里云ACK Kubernetes集群部署方案,包含详细的技术文档、配置文件和实战步骤。

---

## 项目概述

本项目提供Hugo静态博客系统从传统服务器部署迁移到阿里云ACK Kubernetes集群的完整解决方案。

### 核心特性

- ✅ **容器化部署**: Docker多阶段构建,镜像大小优化
- ✅ **自动化CI/CD**: GitHub Actions自动构建和部署
- ✅ **高可用架构**: 多副本部署,自动故障恢复
- ✅ **自动SSL管理**: cert-manager自动申请和续期证书
- ✅ **滚动更新**: 零停机部署,快速回滚
- ✅ **统一监控**: 阿里云SLS日志和监控集成
- ✅ **弹性伸缩**: 支持HPA自动扩缩容

---

## 目录结构

```
k8s-deployment/
├── docs/                           # 文档目录
│   ├── 01-architecture-design.md   # 架构设计文档(TRD)
│   ├── 02-deployment-guide.md      # 实战部署指南
│   └── 03-comparison-and-faq.md    # 对比分析和FAQ
│
├── dockerfiles/                    # Docker镜像构建文件
│   ├── hugo-blog.Dockerfile        # Hugo博客镜像
│   ├── visitor-stats.Dockerfile    # 访客统计镜像
│   ├── nginx.conf                  # Nginx主配置
│   └── default.conf                # Nginx虚拟主机配置
│
├── k8s-manifests/                  # Kubernetes资源配置
│   ├── 00-namespace.yaml           # 命名空间
│   ├── 01-hugo-blog.yaml           # Hugo博客Deployment和Service
│   ├── 02-visitor-stats.yaml       # 访客统计Deployment和Service
│   ├── 03-ingress.yaml             # Ingress路由配置
│   └── 04-cert-manager.yaml        # cert-manager配置
│
├── scripts/                        # 部署脚本
│   ├── build-images.sh             # 构建Docker镜像
│   ├── push-images.sh              # 推送镜像到ACR
│   └── deploy.sh                   # 部署到K8s集群
│
├── workflows/                      # GitHub Actions工作流
│   └── deploy-k8s.yml              # K8s自动部署工作流
│
└── README.md                       # 本文件
```

---

## 快速开始

### 前置要求

- 阿里云账号(已开通ACK和ACR服务)
- 本地安装kubectl和docker
- 域名已备案(如使用国内服务器)

### 5分钟快速部署

```bash
# 1. 克隆仓库
git clone https://github.com/Maneng/blog.git
cd blog

# 2. 配置kubectl(从阿里云ACK控制台获取kubeconfig)
mkdir -p ~/.kube
# 将kubeconfig内容保存到 ~/.kube/config

# 3. 登录阿里云ACR
docker login --username=<your-username> registry.cn-hangzhou.aliyuncs.com

# 4. 构建和推送镜像
./k8s-deployment/scripts/build-images.sh
./k8s-deployment/scripts/push-images.sh

# 5. 部署到K8s
./k8s-deployment/scripts/deploy.sh

# 6. 验证部署
kubectl get pods -n blog
kubectl get ingress -n blog
```

---

## 文档导航

### 1. 架构设计文档 (TRD)

**文件**: [docs/01-architecture-design.md](docs/01-architecture-design.md)

**内容**:
- 执行摘要和核心目标
- 问题陈述和技术债务分析
- 目标架构设计(含架构图)
- 技术选型和决策依据
- 成本分析(传统 vs K8s)
- 风险评估和缓解措施
- 实施计划和时间线

**适合人群**: 技术决策者、架构师、项目经理

### 2. 实战部署指南

**文件**: [docs/02-deployment-guide.md](docs/02-deployment-guide.md)

**内容**:
- 完整的9个阶段部署步骤
- 每个步骤的详细命令和截图说明
- 常用运维命令速查
- 故障排查指南
- 性能优化建议
- 安全加固建议
- 备份和恢复策略

**适合人群**: 运维工程师、DevOps工程师、开发者

### 3. 对比分析和FAQ

**文件**: [docs/03-comparison-and-faq.md](docs/03-comparison-and-faq.md)

**内容**:
- 传统部署 vs K8s部署详细对比
- 10个维度的对比表格
- 适用场景分析
- 迁移决策树
- ROI分析(3年周期)
- 10个常见问题FAQ
- 决策建议

**适合人群**: 所有人

---

## 核心配置文件说明

### Dockerfile

**hugo-blog.Dockerfile**:
- 多阶段构建,优化镜像大小
- 第一阶段: 使用Hugo构建静态文件
- 第二阶段: 使用Nginx提供静态文件服务
- 镜像大小: ~25MB

**visitor-stats.Dockerfile**:
- 基于python:3.11-slim
- 使用Gunicorn运行Flask应用
- 镜像大小: ~150MB

### Kubernetes资源

**Deployment**:
- Hugo博客: 2个副本(高可用)
- 访客统计: 1个副本(SQLite限制)
- 滚动更新策略: maxSurge=1, maxUnavailable=0

**Service**:
- 类型: ClusterIP(集群内部访问)
- 会话保持: ClientIP(访客统计)

**Ingress**:
- 域名路由: /blog/ → Hugo, /api/stats/ → Stats
- SSL终止: cert-manager自动管理
- CORS配置: 支持跨域访问

**PersistentVolume**:
- 存储类型: 阿里云NAS
- 容量: 10GB
- 用途: 持久化SQLite数据库

---

## 部署架构

### 传统部署架构

```
GitHub → GitHub Actions → SSH → 单服务器 → Nginx
```

**问题**:
- 单点故障
- 手动运维
- 扩展困难
- 回滚复杂

### Kubernetes部署架构

```
GitHub → GitHub Actions → Build Image → Push ACR → Update K8s
                                                        ↓
                                                    ACK Cluster
                                                        ↓
                                        SLB → Ingress → Services → Pods
```

**优势**:
- 高可用(多副本)
- 自动化运维
- 易扩展(弹性伸缩)
- 快速回滚(30秒)

---

## 成本对比

| 方案 | 月成本 | 高可用 | 适用场景 |
|-----|--------|--------|---------|
| 传统部署 | ¥150 | ❌ | 个人博客,流量小 |
| K8s单节点 | ¥125 | ❌ | 个人博客,学习K8s |
| K8s双节点 | ¥255 | ✅ | 企业博客,高可用 |

**结论**:
- **个人博客**: 推荐传统部署或K8s单节点
- **企业博客**: 推荐K8s双节点
- **学习目的**: 推荐K8s单节点

---

## 技术栈

### 容器化

- **Docker**: 容器运行时
- **多阶段构建**: 优化镜像大小
- **Alpine Linux**: 轻量级基础镜像

### Kubernetes

- **ACK**: 阿里云托管Kubernetes
- **版本**: 1.28+
- **Ingress**: Nginx Ingress Controller
- **证书**: cert-manager

### CI/CD

- **GitHub Actions**: 自动化构建和部署
- **ACR**: 阿里云容器镜像服务
- **kubectl**: K8s命令行工具

### 监控

- **SLS**: 阿里云日志服务
- **Prometheus**: 指标监控(可选)
- **Grafana**: 可视化Dashboard(可选)

---

## 常用命令

### 本地开发

```bash
# 构建镜像
./k8s-deployment/scripts/build-images.sh

# 推送镜像
./k8s-deployment/scripts/push-images.sh

# 部署到K8s
./k8s-deployment/scripts/deploy.sh
```

### K8s运维

```bash
# 查看Pod状态
kubectl get pods -n blog

# 查看日志
kubectl logs -f deployment/hugo-blog -n blog

# 重启服务
kubectl rollout restart deployment/hugo-blog -n blog

# 回滚版本
kubectl rollout undo deployment/hugo-blog -n blog

# 扩容
kubectl scale deployment/hugo-blog --replicas=3 -n blog
```

### 故障排查

```bash
# 查看Pod详情
kubectl describe pod <pod-name> -n blog

# 查看事件
kubectl get events -n blog --sort-by='.lastTimestamp'

# 进入Pod调试
kubectl exec -it <pod-name> -n blog -- /bin/sh

# 查看资源使用
kubectl top pods -n blog
kubectl top nodes
```

---

## GitHub Actions配置

### 必需的Secrets

在GitHub仓库设置中添加以下Secrets:

```
ACR_USERNAME: 阿里云ACR用户名
ACR_PASSWORD: 阿里云ACR密码
KUBE_CONFIG: kubectl配置文件(base64编码)
```

### 生成KUBE_CONFIG

```bash
# 编码kubeconfig
cat ~/.kube/config | base64

# 复制输出内容到GitHub Secrets
```

### 触发部署

```bash
# 推送代码到main分支自动触发
git push origin main

# 或手动触发
# 访问GitHub Actions页面,点击"Run workflow"
```

---

## 监控和告警

### 监控指标

- Pod CPU/内存使用率
- HTTP请求QPS和延迟
- 错误率和5xx响应
- 访客统计API调用量

### 告警规则

- Pod重启次数 > 3
- CPU使用率 > 80%
- 内存使用率 > 80%
- HTTP 5xx错误率 > 5%

### 配置SLS

1. 访问阿里云SLS控制台
2. 创建Project和Logstore
3. 在ACK集群中安装日志组件
4. 配置日志采集规则

---

## 安全最佳实践

### 容器安全

- ✅ 使用非root用户运行
- ✅ 只读根文件系统(部分场景)
- ✅ 禁止特权提升
- ✅ 镜像扫描

### 网络安全

- ✅ Network Policy隔离
- ✅ Ingress SSL终止
- ✅ Service Mesh(可选)

### 访问控制

- ✅ RBAC权限管理
- ✅ ServiceAccount隔离
- ✅ Secret加密存储

---

## 性能优化

### 镜像优化

- 使用多阶段构建
- 使用alpine基础镜像
- 清理不必要的文件

### 资源优化

- 合理设置资源配额
- 启用HPA自动扩缩容
- 使用节点亲和性

### 缓存优化

- Nginx静态资源缓存
- CDN加速(可选)
- 浏览器缓存策略

---

## 故障排查

### 常见问题

1. **Pod一直Pending**: 检查资源配额和存储
2. **Ingress无法访问**: 检查Ingress Controller和DNS
3. **SSL证书未生效**: 检查cert-manager和域名解析
4. **数据丢失**: 检查PVC挂载和备份

### 排查步骤

1. 查看Pod状态和日志
2. 查看事件和错误信息
3. 检查资源配额和限制
4. 验证网络和存储配置

---

## 贡献指南

欢迎提交Issue和Pull Request!

### 提交Issue

- 描述问题和复现步骤
- 提供错误日志和截图
- 说明环境信息(K8s版本、节点规格等)

### 提交PR

- Fork仓库并创建分支
- 编写清晰的commit message
- 更新相关文档
- 通过所有测试

---

## 许可证

MIT License

---

## 联系方式

- **邮箱**: service@ruyueshuke.com
- **博客**: https://ruyueshuke.com/blog/
- **GitHub**: https://github.com/Maneng

---

## 致谢

感谢以下开源项目:

- [Hugo](https://gohugo.io/) - 静态网站生成器
- [Kubernetes](https://kubernetes.io/) - 容器编排平台
- [cert-manager](https://cert-manager.io/) - SSL证书管理
- [Nginx Ingress](https://kubernetes.github.io/ingress-nginx/) - Ingress控制器

---

**祝你部署顺利!** 🎉
