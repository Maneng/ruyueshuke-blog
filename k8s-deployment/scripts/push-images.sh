#!/bin/bash
# ============================================
# 推送镜像到阿里云ACR
# ============================================
# 用途: 推送Docker镜像到阿里云容器镜像服务
# 使用: ./push-images.sh [TAG]
# ============================================

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 配置
REGISTRY="registry.cn-hangzhou.aliyuncs.com"
NAMESPACE="blog-system"
HUGO_IMAGE="${REGISTRY}/${NAMESPACE}/hugo-blog"
STATS_IMAGE="${REGISTRY}/${NAMESPACE}/visitor-stats"
TAG="${1:-latest}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}推送镜像到阿里云ACR${NC}"
echo -e "${GREEN}========================================${NC}"

# 检查是否已登录
echo -e "\n${YELLOW}检查ACR登录状态...${NC}"
if ! docker info | grep -q "Username"; then
    echo -e "${YELLOW}请先登录阿里云ACR:${NC}"
    echo -e "  docker login --username=<your-username> ${REGISTRY}"
    exit 1
fi

# 推送Hugo博客镜像
echo -e "\n${YELLOW}[1/2] 推送Hugo博客镜像...${NC}"
docker push ${HUGO_IMAGE}:${TAG}

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Hugo博客镜像推送成功${NC}"
else
    echo -e "${RED}✗ Hugo博客镜像推送失败${NC}"
    exit 1
fi

# 推送访客统计镜像
echo -e "\n${YELLOW}[2/2] 推送访客统计镜像...${NC}"
docker push ${STATS_IMAGE}:${TAG}

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ 访客统计镜像推送成功${NC}"
else
    echo -e "${RED}✗ 访客统计镜像推送失败${NC}"
    exit 1
fi

# 完成
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}镜像推送完成!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n镜像地址:"
echo -e "  ${HUGO_IMAGE}:${TAG}"
echo -e "  ${STATS_IMAGE}:${TAG}"

echo -e "\n${YELLOW}下一步:${NC}"
echo -e "  部署到K8s: kubectl apply -f k8s-deployment/k8s-manifests/"
