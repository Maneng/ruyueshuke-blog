# Kubernetes部署 - 快速参考卡片

一页纸速查手册,包含最常用的命令和配置。

---

## 部署流程(5步)

```bash
# 1. 配置kubectl
mkdir -p ~/.kube && vi ~/.kube/config

# 2. 登录ACR
docker login registry.cn-hangzhou.aliyuncs.com

# 3. 构建镜像
./k8s-deployment/scripts/build-images.sh

# 4. 推送镜像
./k8s-deployment/scripts/push-images.sh

# 5. 部署应用
./k8s-deployment/scripts/deploy.sh
```

---

## 常用命令速查

### 查看资源

```bash
# 查看所有资源
kubectl get all -n blog

# 查看Pod
kubectl get pods -n blog
kubectl get pods -n blog -o wide
kubectl get pods -n blog -w  # 实时监控

# 查看Service
kubectl get svc -n blog

# 查看Ingress
kubectl get ingress -n blog

# 查看PVC
kubectl get pvc -n blog
```

### 查看日志

```bash
# 查看Pod日志
kubectl logs <pod-name> -n blog
kubectl logs -f <pod-name> -n blog  # 实时日志
kubectl logs --tail=100 <pod-name> -n blog  # 最后100行

# 查看Deployment日志
kubectl logs -f deployment/hugo-blog -n blog

# 查看多个Pod日志
kubectl logs -l app=hugo-blog -n blog
```

### 调试Pod

```bash
# 查看Pod详情
kubectl describe pod <pod-name> -n blog

# 进入Pod
kubectl exec -it <pod-name> -n blog -- /bin/sh

# 查看Pod资源使用
kubectl top pod <pod-name> -n blog
kubectl top pods -n blog
```

### 更新部署

```bash
# 更新镜像
kubectl set image deployment/hugo-blog \
  nginx=registry.cn-hangzhou.aliyuncs.com/blog-system/hugo-blog:v2 \
  -n blog

# 查看滚动更新状态
kubectl rollout status deployment/hugo-blog -n blog

# 查看更新历史
kubectl rollout history deployment/hugo-blog -n blog

# 暂停更新
kubectl rollout pause deployment/hugo-blog -n blog

# 恢复更新
kubectl rollout resume deployment/hugo-blog -n blog
```

### 回滚部署

```bash
# 回滚到上一版本
kubectl rollout undo deployment/hugo-blog -n blog

# 回滚到指定版本
kubectl rollout undo deployment/hugo-blog --to-revision=2 -n blog

# 查看回滚状态
kubectl rollout status deployment/hugo-blog -n blog
```

### 扩缩容

```bash
# 手动扩容
kubectl scale deployment/hugo-blog --replicas=3 -n blog

# 手动缩容
kubectl scale deployment/hugo-blog --replicas=1 -n blog

# 查看扩容状态
kubectl get pods -n blog -w
```

### 重启服务

```bash
# 重启Deployment
kubectl rollout restart deployment/hugo-blog -n blog

# 删除Pod(自动重建)
kubectl delete pod <pod-name> -n blog
```

---

## 故障排查速查

### Pod状态异常

```bash
# 1. 查看Pod状态
kubectl get pods -n blog

# 2. 查看Pod详情
kubectl describe pod <pod-name> -n blog

# 3. 查看Pod日志
kubectl logs <pod-name> -n blog

# 4. 查看事件
kubectl get events -n blog --sort-by='.lastTimestamp'
```

### Ingress无法访问

```bash
# 1. 查看Ingress状态
kubectl get ingress -n blog
kubectl describe ingress blog-ingress -n blog

# 2. 查看Ingress Controller
kubectl get pods -n kube-system | grep ingress

# 3. 查看Ingress日志
kubectl logs -n kube-system -l app.kubernetes.io/name=ingress-nginx
```

### SSL证书问题

```bash
# 1. 查看证书状态
kubectl get certificate -n blog
kubectl describe certificate blog-tls-secret -n blog

# 2. 查看cert-manager日志
kubectl logs -n cert-manager -l app=cert-manager

# 3. 手动触发证书申请
kubectl delete certificate blog-tls-secret -n blog
kubectl apply -f k8s-deployment/k8s-manifests/03-ingress.yaml
```

### 存储问题

```bash
# 1. 查看PVC状态
kubectl get pvc -n blog
kubectl describe pvc visitor-stats-pvc -n blog

# 2. 查看PV状态
kubectl get pv

# 3. 进入Pod检查挂载
kubectl exec -it <pod-name> -n blog -- df -h
kubectl exec -it <pod-name> -n blog -- ls -la /data
```

---

## 配置文件速查

### Deployment配置

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hugo-blog
  namespace: blog
spec:
  replicas: 2
  selector:
    matchLabels:
      app: hugo-blog
  template:
    metadata:
      labels:
        app: hugo-blog
    spec:
      containers:
      - name: nginx
        image: registry.cn-hangzhou.aliyuncs.com/blog-system/hugo-blog:latest
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
```

### Service配置

```yaml
apiVersion: v1
kind: Service
metadata:
  name: hugo-blog
  namespace: blog
spec:
  type: ClusterIP
  selector:
    app: hugo-blog
  ports:
  - port: 80
    targetPort: 80
```

### Ingress配置

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: blog-ingress
  namespace: blog
  annotations:
    kubernetes.io/ingress.class: "nginx"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  tls:
  - hosts:
    - ruyueshuke.com
    secretName: blog-tls-secret
  rules:
  - host: ruyueshuke.com
    http:
      paths:
      - path: /blog
        pathType: Prefix
        backend:
          service:
            name: hugo-blog
            port:
              number: 80
```

---

## 资源配额参考

### 小流量(<1000PV/天)

```yaml
resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 100m
    memory: 128Mi
```

### 中流量(1000-10000PV/天)

```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 200m
    memory: 256Mi
```

### 大流量(>10000PV/天)

```yaml
resources:
  requests:
    cpu: 200m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

---

## 监控指标参考

### 正常状态

- CPU使用率: <50%
- 内存使用率: <70%
- Pod重启次数: 0
- HTTP 5xx错误率: <1%
- 响应时间: <500ms

### 告警阈值

- CPU使用率: >80%
- 内存使用率: >80%
- Pod重启次数: >3
- HTTP 5xx错误率: >5%
- 响应时间: >3s

---

## 成本参考

| 配置 | 月成本 | 适用场景 |
|-----|--------|---------|
| 单节点(2核4G) | ¥125 | 个人博客 |
| 双节点(2核4G×2) | ¥255 | 企业博客 |
| 双节点+监控 | ¥285 | 生产环境 |

---

## 紧急联系

- **技术支持**: service@ruyueshuke.com
- **文档**: /k8s-deployment/docs/
- **GitHub**: https://github.com/Maneng/blog

---

**保存此文件以便快速查阅!**
