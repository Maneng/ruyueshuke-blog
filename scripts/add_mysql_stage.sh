#!/bin/bash

# MySQL专题文章批量添加stage参数脚本
# 用途：为已存在的MySQL文章批量添加 stage 和 stageTitle 参数
# 作者：Claude
# 日期：2025-11-21

set -e

BASE_DIR="content/mysql/posts"
BLOG_ROOT="/Users/maneng/claude_project/blog"

cd "$BLOG_ROOT"

echo "🚀 开始为MySQL专题文章添加stage参数..."
echo ""

# ==================== 第一阶段：基础入门篇 (01-10) ====================
echo "📝 处理第一阶段：基础入门篇 (01-10)"
for i in $(seq -w 1 10); do
  file=$(ls "$BASE_DIR/${i}-"*.md 2>/dev/null | head -1)
  if [ -f "$file" ]; then
    # 检查是否已有 stage 参数
    if ! grep -q "^stage:" "$file"; then
      # 在 weight 行后添加 stage 和 stageTitle
      sed -i '' '/^weight:/a\
stage: 1\
stageTitle: "基础入门篇"
' "$file"
      echo "  ✅ 已添加 stage 到: $(basename "$file")"
    else
      echo "  ⏭️  已存在 stage: $(basename "$file")"
    fi
  else
    echo "  ⚠️  文件不存在: ${i}-*.md"
  fi
done

echo ""

# ==================== 第二阶段：SQL进阶篇 (11-22) ====================
echo "📝 处理第二阶段：SQL进阶篇 (11-22)"
for i in $(seq 11 22); do
  file=$(ls "$BASE_DIR/${i}-"*.md 2>/dev/null | head -1)
  if [ -f "$file" ]; then
    if ! grep -q "^stage:" "$file"; then
      sed -i '' '/^weight:/a\
stage: 2\
stageTitle: "SQL进阶篇"
' "$file"
      echo "  ✅ 已添加 stage 到: $(basename "$file")"
    else
      echo "  ⏭️  已存在 stage: $(basename "$file")"
    fi
  else
    echo "  ⚠️  文件不存在: ${i}-*.md"
  fi
done

echo ""

# ==================== 第三阶段：索引与优化篇 (23-34) ====================
echo "📝 处理第三阶段：索引与优化篇 (23-34)"
for i in $(seq 23 34); do
  file=$(ls "$BASE_DIR/${i}-"*.md 2>/dev/null | head -1)
  if [ -f "$file" ]; then
    if ! grep -q "^stage:" "$file"; then
      sed -i '' '/^weight:/a\
stage: 3\
stageTitle: "索引与优化篇"
' "$file"
      echo "  ✅ 已添加 stage 到: $(basename "$file")"
    else
      echo "  ⏭️  已存在 stage: $(basename "$file")"
    fi
  else
    echo "  ⚠️  文件不存在: ${i}-*.md"
  fi
done

echo ""

# ==================== 第四阶段：事务与锁篇 (35-44) ====================
echo "📝 处理第四阶段：事务与锁篇 (35-44)"
for i in $(seq 35 44); do
  file=$(ls "$BASE_DIR/${i}-"*.md 2>/dev/null | head -1)
  if [ -f "$file" ]; then
    if ! grep -q "^stage:" "$file"; then
      sed -i '' '/^weight:/a\
stage: 4\
stageTitle: "事务与锁篇"
' "$file"
      echo "  ✅ 已添加 stage 到: $(basename "$file")"
    else
      echo "  ⏭️  已存在 stage: $(basename "$file")"
    fi
  else
    echo "  ⚠️  文件不存在: ${i}-*.md"
  fi
done

echo ""

# ==================== 第五阶段：架构原理篇 (45-56) ====================
echo "📝 处理第五阶段：架构原理篇 (45-56)"
for i in $(seq 45 56); do
  file=$(ls "$BASE_DIR/${i}-"*.md 2>/dev/null | head -1)
  if [ -f "$file" ]; then
    if ! grep -q "^stage:" "$file"; then
      sed -i '' '/^weight:/a\
stage: 5\
stageTitle: "架构原理篇"
' "$file"
      echo "  ✅ 已添加 stage 到: $(basename "$file")"
    else
      echo "  ⏭️  已存在 stage: $(basename "$file")"
    fi
  else
    echo "  ⚠️  文件不存在: ${i}-*.md"
  fi
done

echo ""

# ==================== 第六阶段：高可用实践篇 (57-66) ====================
echo "📝 处理第六阶段：高可用实践篇 (57-66)"
for i in $(seq 57 66); do
  file=$(ls "$BASE_DIR/${i}-"*.md 2>/dev/null | head -1)
  if [ -f "$file" ]; then
    if ! grep -q "^stage:" "$file"; then
      sed -i '' '/^weight:/a\
stage: 6\
stageTitle: "高可用实践篇"
' "$file"
      echo "  ✅ 已添加 stage 到: $(basename "$file")"
    else
      echo "  ⏭️  已存在 stage: $(basename "$file")"
    fi
  else
    echo "  ⚠️  文件不存在: ${i}-*.md"
  fi
done

echo ""

# ==================== 第七阶段：性能调优篇 (67-78) ====================
echo "📝 处理第七阶段：性能调优篇 (67-78)"
for i in $(seq 67 78); do
  file=$(ls "$BASE_DIR/${i}-"*.md 2>/dev/null | head -1)
  if [ -f "$file" ]; then
    if ! grep -q "^stage:" "$file"; then
      sed -i '' '/^weight:/a\
stage: 7\
stageTitle: "性能调优篇"
' "$file"
      echo "  ✅ 已添加 stage 到: $(basename "$file")"
    else
      echo "  ⏭️  已存在 stage: $(basename "$file")"
    fi
  else
    echo "  ⚠️  文件不存在: ${i}-*.md"
  fi
done

echo ""

# ==================== 第八阶段：源码深度篇 (79-86) ====================
echo "📝 处理第八阶段：源码深度篇 (79-86)"
for i in $(seq 79 86); do
  file=$(ls "$BASE_DIR/${i}-"*.md 2>/dev/null | head -1)
  if [ -f "$file" ]; then
    if ! grep -q "^stage:" "$file"; then
      sed -i '' '/^weight:/a\
stage: 8\
stageTitle: "源码深度篇"
' "$file"
      echo "  ✅ 已添加 stage 到: $(basename "$file")"
    else
      echo "  ⏭️  已存在 stage: $(basename "$file")"
    fi
  else
    echo "  ⚠️  文件不存在: ${i}-*.md"
  fi
done

echo ""
echo "✅ MySQL专题文章stage参数添加完成！"
echo ""
echo "💡 下一步："
echo "  1. 检查文章stage参数：grep -r 'stage:' $BASE_DIR"
echo "  2. 本地预览：hugo server -D"
