---
title: "RocketMQ云原生01：Kubernetes 部署实践 - 拥抱容器化时代"
date: 2025-11-15T15:00:00+08:00
draft: false
tags: ["RocketMQ", "Kubernetes", "云原生", "容器化"]
categories: ["技术"]
description: "在 Kubernetes 上部署 RocketMQ 集群，实现弹性伸缩和自动化运维"
series: ["RocketMQ从入门到精通"]
weight: 39
stage: 5
stageTitle: "云原生演进篇"
---

## 引言：云原生时代的 RocketMQ

传统物理机部署，扩容一台 Broker 需要 2 天：申请机器 → 装系统 → 装软件 → 配置 → 测试...

Kubernetes 部署，扩容只需 30 秒：`kubectl scale statefulset broker --replicas=5`

**云原生的优势**：
- ✅ 秒级弹性伸缩
- ✅ 自动故障恢复
- ✅ 统一资源管理
- ✅ 声明式配置

**本文目标**：
- 理解 RocketMQ 在 K8s 上的架构
- 掌握 StatefulSet 部署方法
- 实现持久化存储
- 配置服务发现和负载均衡

---

## 一、架构设计

### 1.1 K8s 部署架构

```
┌─────────────────────────────────────────────────────┐
│              Kubernetes 集群                         │
│                                                     │
│  ┌─────────────────────────────────────────────┐   │
│  │        Namespace: rocketmq                  │   │
│  │                                             │   │
│  │  ┌────────────────────────────────────┐    │   │
│  │  │  StatefulSet: rocketmq-nameserver  │    │   │
│  │  │  ┌─────────┐  ┌─────────┐         │    │   │
│  │  │  │  ns-0   │  │  ns-1   │         │    │   │
│  │  │  └─────────┘  └─────────┘         │    │   │
│  │  └────────────────────────────────────┘    │   │
│  │                                             │   │
│  │  ┌────────────────────────────────────┐    │   │
│  │  │  StatefulSet: rocketmq-broker      │    │   │
│  │  │  ┌──────────┐  ┌──────────┐        │    │   │
│  │  │  │ broker-0 │  │ broker-1 │        │    │   │
│  │  │  │          │  │          │        │    │   │
│  │  │  │  ┌─PVC─┐ │  │  ┌─PVC─┐ │        │    │   │
│  │  │  │  │ 50Gi│ │  │  │ 50Gi│ │        │    │   │
│  │  │  └──┴─────┴─┘  └──┴─────┴─┘        │    │   │
│  │  └────────────────────────────────────┘    │   │
│  │                                             │   │
│  │  ┌──────────────────────────┐              │   │
│  │  │  Service: nameserver-svc │              │   │
│  │  │  ClusterIP / Headless    │              │   │
│  │  └──────────────────────────┘              │   │
│  └─────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

---

## 二、部署准备

### 2.1 创建命名空间

```yaml
# namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: rocketmq
```

```bash
kubectl apply -f namespace.yaml
```

---

### 2.2 创建 ConfigMap

```yaml
# configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: rocketmq-broker-config
  namespace: rocketmq
data:
  broker.conf: |
    brokerClusterName=DefaultCluster
    brokerName=broker-{{ .Ordinal }}
    brokerId=0
    deleteWhen=04
    fileReservedTime=48
    brokerRole=ASYNC_MASTER
    flushDiskType=ASYNC_FLUSH

    # 存储路径
    storePathRootDir=/home/rocketmq/store
    storePathCommitLog=/home/rocketmq/store/commitlog

    # 网络配置
    brokerIP1={{ .PodIP }}
    listenPort=10911

    # NameServer 地址
    namesrvAddr=rocketmq-nameserver-0.rocketmq-nameserver.rocketmq.svc.cluster.local:9876;rocketmq-nameserver-1.rocketmq-nameserver.rocketmq.svc.cluster.local:9876
```

```bash
kubectl apply -f configmap.yaml
```

---

## 三、NameServer 部署

### 3.1 StatefulSet 配置

```yaml
# nameserver-statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: rocketmq-nameserver
  namespace: rocketmq
spec:
  serviceName: rocketmq-nameserver
  replicas: 2
  selector:
    matchLabels:
      app: rocketmq-nameserver
  template:
    metadata:
      labels:
        app: rocketmq-nameserver
    spec:
      containers:
      - name: nameserver
        image: apache/rocketmq:5.0.0
        imagePullPolicy: IfNotPresent
        command:
          - sh
          - mqnamesrv
        ports:
        - containerPort: 9876
          name: nameserver
        env:
        - name: JAVA_OPT_EXT
          value: "-Xms512m -Xmx512m -Xmn256m"
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        livenessProbe:
          tcpSocket:
            port: 9876
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          tcpSocket:
            port: 9876
          initialDelaySeconds: 10
          periodSeconds: 5
```

---

### 3.2 Headless Service

```yaml
# nameserver-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: rocketmq-nameserver
  namespace: rocketmq
spec:
  clusterIP: None  # Headless Service
  selector:
    app: rocketmq-nameserver
  ports:
  - port: 9876
    targetPort: 9876
    name: nameserver
```

---

### 3.3 部署 NameServer

```bash
# 部署 StatefulSet
kubectl apply -f nameserver-statefulset.yaml

# 部署 Service
kubectl apply -f nameserver-service.yaml

# 查看 Pod 状态
kubectl get pods -n rocketmq -l app=rocketmq-nameserver

# 输出：
# NAME                       READY   STATUS    RESTARTS   AGE
# rocketmq-nameserver-0      1/1     Running   0          1m
# rocketmq-nameserver-1      1/1     Running   0          1m

# 查看 Service
kubectl get svc -n rocketmq

# 查看 DNS 记录
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup rocketmq-nameserver.rocketmq.svc.cluster.local
```

---

## 四、Broker 部署

### 4.1 StorageClass 配置

```yaml
# storageclass.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: rocketmq-storage
provisioner: kubernetes.io/aws-ebs  # 根据云厂商修改
parameters:
  type: gp3
  fsType: ext4
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

```bash
kubectl apply -f storageclass.yaml
```

---

### 4.2 Broker StatefulSet

```yaml
# broker-statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: rocketmq-broker
  namespace: rocketmq
spec:
  serviceName: rocketmq-broker
  replicas: 2
  selector:
    matchLabels:
      app: rocketmq-broker
  template:
    metadata:
      labels:
        app: rocketmq-broker
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values:
                - rocketmq-broker
            topologyKey: "kubernetes.io/hostname"
      containers:
      - name: broker
        image: apache/rocketmq:5.0.0
        imagePullPolicy: IfNotPresent
        command:
          - sh
          - mqbroker
          - -c
          - /etc/rocketmq/broker.conf
        ports:
        - containerPort: 10909
          name: vip
        - containerPort: 10911
          name: main
        - containerPort: 10912
          name: ha
        env:
        - name: NAMESRV_ADDR
          value: "rocketmq-nameserver-0.rocketmq-nameserver.rocketmq.svc.cluster.local:9876;rocketmq-nameserver-1.rocketmq-nameserver.rocketmq.svc.cluster.local:9876"
        - name: JAVA_OPT_EXT
          value: "-Xms2g -Xmx2g -Xmn1g"
        volumeMounts:
        - name: broker-storage
          mountPath: /home/rocketmq/store
        - name: broker-config
          mountPath: /etc/rocketmq/broker.conf
          subPath: broker.conf
        resources:
          requests:
            memory: "2Gi"
            cpu: "500m"
          limits:
            memory: "4Gi"
            cpu: "2000m"
        livenessProbe:
          tcpSocket:
            port: 10911
          initialDelaySeconds: 60
          periodSeconds: 10
        readinessProbe:
          tcpSocket:
            port: 10911
          initialDelaySeconds: 20
          periodSeconds: 5
      volumes:
      - name: broker-config
        configMap:
          name: rocketmq-broker-config
  volumeClaimTemplates:
  - metadata:
      name: broker-storage
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: rocketmq-storage
      resources:
        requests:
          storage: 50Gi
```

---

### 4.3 Broker Service

```yaml
# broker-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: rocketmq-broker
  namespace: rocketmq
spec:
  clusterIP: None
  selector:
    app: rocketmq-broker
  ports:
  - port: 10909
    targetPort: 10909
    name: vip
  - port: 10911
    targetPort: 10911
    name: main
  - port: 10912
    targetPort: 10912
    name: ha
```

---

### 4.4 部署 Broker

```bash
# 部署 StatefulSet
kubectl apply -f broker-statefulset.yaml

# 部署 Service
kubectl apply -f broker-service.yaml

# 查看 Pod
kubectl get pods -n rocketmq -l app=rocketmq-broker -w

# 查看 PVC
kubectl get pvc -n rocketmq

# 查看日志
kubectl logs -f rocketmq-broker-0 -n rocketmq

# 进入 Pod 验证
kubectl exec -it rocketmq-broker-0 -n rocketmq -- sh
> sh mqadmin clusterList -n rocketmq-nameserver-0.rocketmq-nameserver.rocketmq.svc.cluster.local:9876
```

---

## 五、客户端连接

### 5.1 内部访问

**在 K8s 集群内部**：

```java
// Java 客户端配置
DefaultMQProducer producer = new DefaultMQProducer("producer_group");

// 使用 Service DNS
producer.setNamesrvAddr(
    "rocketmq-nameserver-0.rocketmq-nameserver.rocketmq.svc.cluster.local:9876;" +
    "rocketmq-nameserver-1.rocketmq-nameserver.rocketmq.svc.cluster.local:9876"
);

producer.start();
```

---

### 5.2 外部访问

**方式1：NodePort**

```yaml
# nameserver-nodeport.yaml
apiVersion: v1
kind: Service
metadata:
  name: rocketmq-nameserver-external
  namespace: rocketmq
spec:
  type: NodePort
  selector:
    app: rocketmq-nameserver
  ports:
  - port: 9876
    targetPort: 9876
    nodePort: 30876  # 外部访问端口
```

**方式2：LoadBalancer**

```yaml
# nameserver-lb.yaml
apiVersion: v1
kind: Service
metadata:
  name: rocketmq-nameserver-lb
  namespace: rocketmq
spec:
  type: LoadBalancer
  selector:
    app: rocketmq-nameserver
  ports:
  - port: 9876
    targetPort: 9876
```

**方式3：Ingress（推荐）**

```yaml
# ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rocketmq-ingress
  namespace: rocketmq
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "TCP"
spec:
  rules:
  - host: rocketmq.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: rocketmq-nameserver
            port:
              number: 9876
```

---

## 六、弹性伸缩

### 6.1 手动扩容

```bash
# 扩容 Broker（2 → 3）
kubectl scale statefulset rocketmq-broker --replicas=3 -n rocketmq

# 查看扩容进度
kubectl get pods -n rocketmq -l app=rocketmq-broker -w

# 验证新 Broker 加入集群
kubectl exec rocketmq-broker-0 -n rocketmq -- \
  sh mqadmin clusterList -n rocketmq-nameserver-0.rocketmq-nameserver.rocketmq.svc.cluster.local:9876
```

---

### 6.2 自动扩容（HPA）

```yaml
# hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: rocketmq-broker-hpa
  namespace: rocketmq
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: StatefulSet
    name: rocketmq-broker
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

**注意**：StatefulSet 的 HPA 需要 K8s 1.23+ 版本支持。

---

## 七、监控集成

### 7.1 部署 Prometheus

```yaml
# prometheus-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: rocketmq
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
    scrape_configs:
      - job_name: 'rocketmq-exporter'
        kubernetes_sd_configs:
        - role: pod
          namespaces:
            names:
            - rocketmq
        relabel_configs:
        - source_labels: [__meta_kubernetes_pod_label_app]
          regex: rocketmq-exporter
          action: keep
```

---

### 7.2 部署 RocketMQ Exporter

```yaml
# exporter-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rocketmq-exporter
  namespace: rocketmq
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rocketmq-exporter
  template:
    metadata:
      labels:
        app: rocketmq-exporter
    spec:
      containers:
      - name: exporter
        image: apache/rocketmq-exporter:latest
        ports:
        - containerPort: 5557
        env:
        - name: rocketmq.config.namesrvAddr
          value: "rocketmq-nameserver:9876"
```

---

## 八、最佳实践

### 8.1 资源配置建议

| 组件 | CPU 请求 | CPU 限制 | 内存请求 | 内存限制 | 存储 |
|------|---------|---------|---------|---------|------|
| NameServer | 250m | 500m | 512Mi | 1Gi | - |
| Broker（小） | 500m | 2000m | 2Gi | 4Gi | 50Gi |
| Broker（中） | 1000m | 4000m | 4Gi | 8Gi | 200Gi |
| Broker（大） | 2000m | 8000m | 8Gi | 16Gi | 500Gi |

---

### 8.2 亲和性配置

**反亲和（推荐）**：
```yaml
# Pod 反亲和，确保 Broker 分散到不同节点
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchExpressions:
        - key: app
          operator: In
          values:
          - rocketmq-broker
      topologyKey: "kubernetes.io/hostname"
```

**节点亲和**：
```yaml
# 指定 Broker 运行在高性能节点
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: node-type
          operator: In
          values:
          - high-performance
```

---

### 8.3 持久化存储优化

```yaml
# 使用 Local PV 提升性能
apiVersion: v1
kind: PersistentVolume
metadata:
  name: rocketmq-broker-pv-0
spec:
  capacity:
    storage: 500Gi
  volumeMode: Filesystem
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  local:
    path: /mnt/disks/ssd0
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - node-1
```

---

## 九、故障排查

### 9.1 Pod 启动失败

```bash
# 查看 Pod 状态
kubectl describe pod rocketmq-broker-0 -n rocketmq

# 查看日志
kubectl logs rocketmq-broker-0 -n rocketmq

# 常见问题：
# 1. 资源不足 → 调整 requests/limits
# 2. PVC 未绑定 → 检查 StorageClass
# 3. 配置错误 → 检查 ConfigMap
```

---

### 9.2 网络不通

```bash
# 测试 NameServer 连通性
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  telnet rocketmq-nameserver-0.rocketmq-nameserver.rocketmq.svc.cluster.local 9876

# 测试 Broker 连通性
kubectl exec -it rocketmq-broker-0 -n rocketmq -- \
  sh mqadmin clusterList -n rocketmq-nameserver:9876
```

---

### 9.3 数据丢失

```bash
# 检查 PV 状态
kubectl get pv | grep rocketmq

# 检查 PVC 绑定
kubectl get pvc -n rocketmq

# 验证数据持久化
kubectl exec -it rocketmq-broker-0 -n rocketmq -- ls -lh /home/rocketmq/store
```

---

## 十、总结

### K8s 部署检查清单

- [ ] 创建 Namespace
- [ ] 配置 StorageClass
- [ ] 部署 NameServer StatefulSet
- [ ] 部署 NameServer Service
- [ ] 配置 Broker ConfigMap
- [ ] 部署 Broker StatefulSet
- [ ] 部署 Broker Service
- [ ] 配置外部访问（NodePort/LB/Ingress）
- [ ] 部署监控（Exporter + Prometheus）
- [ ] 配置 HPA 自动伸缩
- [ ] 测试消息收发

### 核心优势

```
1. 秒级扩缩容
2. 自动故障恢复
3. 统一资源管理
4. 声明式配置
5. 与云原生生态集成
```

---

**下一篇预告**：《RocketMQ Operator - 声明式运维管理》，我们将讲解如何使用 Operator 进一步简化 RocketMQ 的运维管理。

**本文关键词**：`Kubernetes` `StatefulSet` `云原生` `容器化部署`
