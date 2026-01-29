#!/bin/bash
# ============================================
# 本地构建和测试Docker镜像
# ============================================
# 用途: 在本地环境构建和测试镜像
# 使用: ./build-images.sh
# ============================================

set -e  # 遇到错误立即退出

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 配置
REGISTRY="registry.cn-hangzhou.aliyuncs.com"
NAMESPACE="blog-system"
HUGO_IMAGE="${REGISTRY}/${NAMESPACE}/hugo-blog"
STATS_IMAGE="${REGISTRY}/${NAMESPACE}/visitor-stats"
TAG="${1:-latest}"  # 默认使用latest标签

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}开始构建Docker镜像${NC}"
echo -e "${GREEN}========================================${NC}"

# 检查Docker是否运行
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}错误: Docker未运行,请先启动Docker${NC}"
    exit 1
fi

# 构建Hugo博客镜像
echo -e "\n${YELLOW}[1/4] 构建Hugo博客镜像...${NC}"
docker build \
    -f k8s-deployment/dockerfiles/hugo-blog.Dockerfile \
    -t ${HUGO_IMAGE}:${TAG} \
    .

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Hugo博客镜像构建成功${NC}"
else
    echo -e "${RED}✗ Hugo博客镜像构建失败${NC}"
    exit 1
fi

# 构建访客统计镜像
echo -e "\n${YELLOW}[2/4] 构建访客统计镜像...${NC}"
docker build \
    -f k8s-deployment/dockerfiles/visitor-stats.Dockerfile \
    -t ${STATS_IMAGE}:${TAG} \
    .

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ 访客统计镜像构建成功${NC}"
else
    echo -e "${RED}✗ 访客统计镜像构建失败${NC}"
    exit 1
fi

# 显示镜像信息
echo -e "\n${YELLOW}[3/4] 镜像信息:${NC}"
docker images | grep -E "hugo-blog|visitor-stats" | head -2

# 测试镜像
echo -e "\n${YELLOW}[4/4] 测试镜像...${NC}"

# 测试Hugo博客镜像
echo -e "\n测试Hugo博客镜像..."
HUGO_CONTAINER=$(docker run -d -p 8080:80 ${HUGO_IMAGE}:${TAG})
sleep 3

if curl -f http://localhost:8080/health > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Hugo博客镜像测试通过${NC}"
else
    echo -e "${RED}✗ Hugo博客镜像测试失败${NC}"
fi

docker stop ${HUGO_CONTAINER} > /dev/null 2>&1
docker rm ${HUGO_CONTAINER} > /dev/null 2>&1

# 测试访客统计镜像
echo -e "\n测试访客统计镜像..."
STATS_CONTAINER=$(docker run -d -p 5000:5000 ${STATS_IMAGE}:${TAG})
sleep 5

if curl -f http://localhost:5000/api/health > /dev/null 2>&1; then
    echo -e "${GREEN}✓ 访客统计镜像测试通过${NC}"
else
    echo -e "${RED}✗ 访客统计镜像测试失败${NC}"
fi

docker stop ${STATS_CONTAINER} > /dev/null 2>&1
docker rm ${STATS_CONTAINER} > /dev/null 2>&1

# 完成
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}镜像构建和测试完成!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n镜像列表:"
echo -e "  ${HUGO_IMAGE}:${TAG}"
echo -e "  ${STATS_IMAGE}:${TAG}"

echo -e "\n${YELLOW}提示:${NC}"
echo -e "  1. 推送镜像到ACR: ./push-images.sh ${TAG}"
echo -e "  2. 部署到K8s: kubectl apply -f k8s-deployment/k8s-manifests/"
