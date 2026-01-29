#!/bin/bash
# ============================================
# 部署到Kubernetes集群
# ============================================
# 用途: 部署所有K8s资源到ACK集群
# 使用: ./deploy.sh
# ============================================

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置
MANIFESTS_DIR="k8s-deployment/k8s-manifests"
NAMESPACE="blog"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}部署Hugo博客到Kubernetes${NC}"
echo -e "${GREEN}========================================${NC}"

# 检查kubectl
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}错误: kubectl未安装${NC}"
    exit 1
fi

# 检查集群连接
echo -e "\n${YELLOW}检查集群连接...${NC}"
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}错误: 无法连接到Kubernetes集群${NC}"
    echo -e "${YELLOW}请先配置kubectl:${NC}"
    echo -e "  1. 登录阿里云控制台"
    echo -e "  2. 进入ACK集群管理页面"
    echo -e "  3. 点击'连接信息'获取kubeconfig"
    exit 1
fi

echo -e "${GREEN}✓ 集群连接正常${NC}"
kubectl cluster-info | head -1

# 创建命名空间
echo -e "\n${YELLOW}[1/6] 创建命名空间...${NC}"
kubectl apply -f ${MANIFESTS_DIR}/00-namespace.yaml
echo -e "${GREEN}✓ 命名空间创建完成${NC}"

# 部署Hugo博客
echo -e "\n${YELLOW}[2/6] 部署Hugo博客服务...${NC}"
kubectl apply -f ${MANIFESTS_DIR}/01-hugo-blog.yaml
echo -e "${GREEN}✓ Hugo博客部署完成${NC}"

# 部署访客统计服务
echo -e "\n${YELLOW}[3/6] 部署访客统计服务...${NC}"
kubectl apply -f ${MANIFESTS_DIR}/02-visitor-stats.yaml
echo -e "${GREEN}✓ 访客统计服务部署完成${NC}"

# 部署cert-manager配置
echo -e "\n${YELLOW}[4/6] 配置cert-manager...${NC}"
if kubectl get crd certificates.cert-manager.io &> /dev/null; then
    kubectl apply -f ${MANIFESTS_DIR}/04-cert-manager.yaml
    echo -e "${GREEN}✓ cert-manager配置完成${NC}"
else
    echo -e "${YELLOW}⚠ cert-manager未安装,跳过证书配置${NC}"
    echo -e "${YELLOW}  安装命令: kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml${NC}"
fi

# 部署Ingress
echo -e "\n${YELLOW}[5/6] 部署Ingress...${NC}"
kubectl apply -f ${MANIFESTS_DIR}/03-ingress.yaml
echo -e "${GREEN}✓ Ingress部署完成${NC}"

# 等待Pod就绪
echo -e "\n${YELLOW}[6/6] 等待Pod就绪...${NC}"
echo -e "${BLUE}等待Hugo博客Pod...${NC}"
kubectl wait --for=condition=ready pod -l app=hugo-blog -n ${NAMESPACE} --timeout=300s

echo -e "${BLUE}等待访客统计Pod...${NC}"
kubectl wait --for=condition=ready pod -l app=visitor-stats -n ${NAMESPACE} --timeout=300s

echo -e "${GREEN}✓ 所有Pod已就绪${NC}"

# 显示部署状态
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}部署完成!${NC}"
echo -e "${GREEN}========================================${NC}"

echo -e "\n${BLUE}Pod状态:${NC}"
kubectl get pods -n ${NAMESPACE}

echo -e "\n${BLUE}Service状态:${NC}"
kubectl get svc -n ${NAMESPACE}

echo -e "\n${BLUE}Ingress状态:${NC}"
kubectl get ingress -n ${NAMESPACE}

# 获取访问地址
echo -e "\n${YELLOW}访问地址:${NC}"
INGRESS_IP=$(kubectl get ingress blog-ingress -n ${NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
if [ "$INGRESS_IP" != "pending" ]; then
    echo -e "  ${GREEN}https://ruyueshuke.com/blog/${NC}"
    echo -e "  ${GREEN}https://ruyueshuke.com/api/stats${NC}"
    echo -e "\n  Ingress IP: ${INGRESS_IP}"
else
    echo -e "  ${YELLOW}Ingress IP分配中,请稍后查看${NC}"
    echo -e "  ${YELLOW}查看命令: kubectl get ingress -n ${NAMESPACE}${NC}"
fi

echo -e "\n${YELLOW}常用命令:${NC}"
echo -e "  查看日志: kubectl logs -f deployment/hugo-blog -n ${NAMESPACE}"
echo -e "  查看事件: kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp'"
echo -e "  重启服务: kubectl rollout restart deployment/hugo-blog -n ${NAMESPACE}"
echo -e "  回滚版本: kubectl rollout undo deployment/hugo-blog -n ${NAMESPACE}"
