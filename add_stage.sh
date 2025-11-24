#!/bin/bash

# 为Java生态模块的文章批量添加stage参数

BASE_DIR="/Users/maneng/claude_project/blog/content/java-ecosystem/posts"

# 第一阶段：技术全景与核心思想篇
stage1_files=(
    "01-java-tech-stack-landscape.md"
    "02-why-microservices.md"
    "2025-11-03-why-we-need-spring.md"
    "2025-11-03-why-we-need-message-queue.md"
    "03-service-decomposition-principles.md"
    "06-why-circuit-breaker-rate-limiter.md"
)

# 第二阶段：核心框架深度篇
stage2_files=(
    "2025-11-03-ioc-container-evolution.md"
    "2025-11-03-aop-aspect-oriented-programming.md"
    "2025-11-03-spring-boot-convention-over-configuration.md"
    "2025-11-03-spring-cloud-microservices.md"
    "04-service-communication-patterns.md"
    "05-service-governance.md"
)

# 第三阶段：中间件实战篇
stage3_files=(
    "2025-11-03-message-queue-core-concepts.md"
    "2025-11-03-kafka-architecture-principles.md"
    "2025-11-03-rabbitmq-deep-dive.md"
    "2025-11-03-rocketmq-in-action.md"
    "2025-11-03-message-reliability-distributed-transaction.md"
)

# 第四阶段：生产实践篇
stage4_files=(
    "07-circuit-breaker-sentinel-practice.md"
    "08-rate-limiter-algorithms.md"
    "09-observability-monitoring-logging-tracing.md"
    "10-high-availability-replication-sharding.md"
    "11-distributed-transactions.md"
)

# 第五阶段：源码深度篇
stage5_files=(
    "2025-11-03-spring-source-code-analysis.md"
)

# 添加stage参数的函数
add_stage() {
    local file="$1"
    local stage="$2"
    local stage_title="$3"

    if [ ! -f "$file" ]; then
        echo "⚠️  文件不存在: $(basename "$file")"
        return
    fi

    # 检查是否已有stage参数
    if grep -q "^stage:" "$file"; then
        echo "⏭️  已有stage参数: $(basename "$file")"
        return
    fi

    # 在weight行后添加stage和stageTitle
    if grep -q "^weight:" "$file"; then
        sed -i '' '/^weight:/a\
stage: '"$stage"'\
stageTitle: "'"$stage_title"'"
' "$file"
        echo "✅ 已添加stage到: $(basename "$file")"
    else
        # 如果没有weight行，在series行后添加
        if grep -q "^series:" "$file"; then
            sed -i '' '/^series:/a\
weight: 1\
stage: '"$stage"'\
stageTitle: "'"$stage_title"'"
' "$file"
            echo "✅ 已添加weight和stage到: $(basename "$file")"
        else
            # 如果既没有weight也没有series，在description行后添加
            sed -i '' '/^description:/a\
weight: 1\
stage: '"$stage"'\
stageTitle: "'"$stage_title"'"
' "$file"
            echo "✅ 已添加weight和stage到: $(basename "$file")"
        fi
    fi
}

echo "=== 开始为文章添加stage参数 ==="
echo

echo "🎯 第一阶段：技术全景与核心思想篇"
for file in "${stage1_files[@]}"; do
    add_stage "$BASE_DIR/$file" 1 "技术全景与核心思想篇"
done
echo

echo "🏗️ 第二阶段：核心框架深度篇"
for file in "${stage2_files[@]}"; do
    add_stage "$BASE_DIR/$file" 2 "核心框架深度篇"
done
echo

echo "📨 第三阶段：中间件实战篇"
for file in "${stage3_files[@]}"; do
    add_stage "$BASE_DIR/$file" 3 "中间件实战篇"
done
echo

echo "🔧 第四阶段：生产实践篇"
for file in "${stage4_files[@]}"; do
    add_stage "$BASE_DIR/$file" 4 "生产实践篇"
done
echo

echo "💡 第五阶段：源码深度篇"
for file in "${stage5_files[@]}"; do
    add_stage "$BASE_DIR/$file" 5 "源码深度篇"
done
echo

echo "=== 完成！==="
