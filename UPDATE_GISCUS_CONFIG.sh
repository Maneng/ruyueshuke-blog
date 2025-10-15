#!/bin/bash
# Giscus配置更新脚本
# 使用方法：
# 1. 从 https://giscus.app/zh-CN 获取 repoId 和 categoryId
# 2. 运行：bash UPDATE_GISCUS_CONFIG.sh "你的repoId" "你的categoryId"

REPO_ID=$1
CATEGORY_ID=$2

if [ -z "$REPO_ID" ] || [ -z "$CATEGORY_ID" ]; then
    echo "❌ 错误：缺少参数"
    echo "使用方法："
    echo "  bash UPDATE_GISCUS_CONFIG.sh \"R_xxxxx\" \"DIC_xxxxx\""
    echo ""
    echo "请访问 https://giscus.app/zh-CN 获取配置ID"
    exit 1
fi

echo "📝 正在更新 config.toml..."

# 备份原文件
cp config.toml config.toml.backup

# 替换 repoId
sed -i '' "s/repoId = \"YOUR_REPO_ID\"/repoId = \"$REPO_ID\"/" config.toml

# 替换 categoryId
sed -i '' "s/categoryId = \"YOUR_CATEGORY_ID\"/categoryId = \"$CATEGORY_ID\"/" config.toml

echo "✅ 配置已更新！"
echo ""
echo "📋 请检查 config.toml 中的 [params.giscus] 部分："
grep -A 10 "\[params.giscus\]" config.toml
echo ""
echo "🚀 下一步："
echo "  git add config.toml"
echo "  git commit -m 'Config: 完成Giscus评论系统配置'"
echo "  git push origin main"
