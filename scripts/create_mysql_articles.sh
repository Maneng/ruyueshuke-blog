#!/bin/bash

# MySQL专题文章批量创建脚本
# 用途：批量创建MySQL专题的所有文章框架
# 作者：Claude
# 日期：2025-11-21

set -e

BASE_DIR="content/mysql/posts"
BLOG_ROOT="/Users/maneng/claude_project/blog"

cd "$BLOG_ROOT"

# 确保目录存在
mkdir -p "$BASE_DIR"

echo "🚀 开始创建MySQL专题文章..."
echo ""

# ==================== 第一阶段：基础入门篇（10篇）====================
echo "📝 创建第一阶段：基础入门篇（10篇）"

stage1_titles=(
  "01-什么是数据库-为什么需要数据库"
  "02-MySQL简介-历史特点与应用场景"
  "03-MySQL安装与环境配置"
  "04-数据库与表的创建-DDL基础"
  "05-数据类型详解-选择合适的数据类型"
  "06-基础增删改查-DML操作入门"
  "07-约束与完整性-主键外键唯一非空"
  "08-字符集与校对规则"
  "09-数据导入导出"
  "10-第一个完整案例-用户管理系统"
)

for i in "${!stage1_titles[@]}"; do
  title="${stage1_titles[$i]}"
  weight=$((i + 1))
  hugo new "mysql/posts/${title}.md"

  file="$BASE_DIR/${title}.md"
  if [ -f "$file" ]; then
    # 在 weight 行后添加 stage 和 stageTitle
    sed -i '' "/^weight:/a\\
stage: 1\\
stageTitle: \"基础入门篇\"
" "$file"
    echo "  ✅ 创建：${title}.md (weight: ${weight}, stage: 1)"
  fi
done

echo ""

# ==================== 第二阶段：SQL进阶篇（12篇）====================
echo "📝 创建第二阶段：SQL进阶篇（12篇）"

stage2_titles=(
  "11-单表查询进阶-WHERE条件与运算符"
  "12-排序与分页-ORDER-BY与LIMIT"
  "13-聚合函数-COUNT-SUM-AVG-MAX-MIN"
  "14-分组查询-GROUP-BY与HAVING"
  "15-多表连接-INNER-JOIN-LEFT-JOIN-RIGHT-JOIN"
  "16-子查询-嵌套查询与相关子查询"
  "17-联合查询-UNION与UNION-ALL"
  "18-窗口函数-ROW-NUMBER-RANK-DENSE-RANK"
  "19-常用字符串函数与日期函数"
  "20-条件表达式-CASE-WHEN与IF"
  "21-视图-虚拟表的创建与使用"
  "22-综合实战-电商订单查询系统"
)

for i in "${!stage2_titles[@]}"; do
  title="${stage2_titles[$i]}"
  weight=$((i + 11))
  hugo new "mysql/posts/${title}.md"

  file="$BASE_DIR/${title}.md"
  if [ -f "$file" ]; then
    sed -i '' "/^weight:/a\\
stage: 2\\
stageTitle: \"SQL进阶篇\"
" "$file"
    echo "  ✅ 创建：${title}.md (weight: ${weight}, stage: 2)"
  fi
done

echo ""

# ==================== 第三阶段：索引与优化篇（12篇）====================
echo "📝 创建第三阶段：索引与优化篇（12篇）"

stage3_titles=(
  "23-索引的本质-为什么索引能加速查询"
  "24-B+树详解-MySQL索引的数据结构"
  "25-索引类型-主键索引-唯一索引-普通索引-全文索引"
  "26-创建索引的最佳实践"
  "27-索引失效的场景分析"
  "28-联合索引-最左前缀原则"
  "29-覆盖索引-减少回表查询"
  "30-索引下推-ICP优化"
  "31-EXPLAIN执行计划详解-上-基础字段"
  "32-EXPLAIN执行计划详解-下-高级分析"
  "33-慢查询日志-定位性能瓶颈"
  "34-索引优化实战案例"
)

for i in "${!stage3_titles[@]}"; do
  title="${stage3_titles[$i]}"
  weight=$((i + 23))
  hugo new "mysql/posts/${title}.md"

  file="$BASE_DIR/${title}.md"
  if [ -f "$file" ]; then
    sed -i '' "/^weight:/a\\
stage: 3\\
stageTitle: \"索引与优化篇\"
" "$file"
    echo "  ✅ 创建：${title}.md (weight: ${weight}, stage: 3)"
  fi
done

echo ""

# ==================== 第四阶段：事务与锁篇（10篇）====================
echo "📝 创建第四阶段：事务与锁篇（10篇）"

stage4_titles=(
  "35-事务的本质-ACID特性详解"
  "36-事务隔离级别-读未提交-读已提交-可重复读-串行化"
  "37-脏读-不可重复读-幻读的本质"
  "38-MVCC多版本并发控制原理"
  "39-undo-log与版本链"
  "40-锁的分类-共享锁与排他锁"
  "41-行锁-表锁-间隙锁-临键锁"
  "42-死锁-产生原因与解决方案"
  "43-乐观锁与悲观锁实践"
  "44-事务实战-转账系统的实现"
)

for i in "${!stage4_titles[@]}"; do
  title="${stage4_titles[$i]}"
  weight=$((i + 35))
  hugo new "mysql/posts/${title}.md"

  file="$BASE_DIR/${title}.md"
  if [ -f "$file" ]; then
    sed -i '' "/^weight:/a\\
stage: 4\\
stageTitle: \"事务与锁篇\"
" "$file"
    echo "  ✅ 创建：${title}.md (weight: ${weight}, stage: 4)"
  fi
done

echo ""

# ==================== 第五阶段：架构原理篇（12篇）====================
echo "📝 创建第五阶段：架构原理篇（12篇）"

stage5_titles=(
  "45-MySQL架构总览-连接器-查询缓存-分析器-优化器-执行器"
  "46-存储引擎对比-InnoDB-vs-MyISAM"
  "47-InnoDB存储结构-表空间-段-区-页"
  "48-InnoDB行格式-Compact-Redundant-Dynamic"
  "49-Buffer-Pool-MySQL的内存管理"
  "50-redo-log-崩溃恢复的保障"
  "51-binlog-主从复制的基础"
  "52-undo-log-回滚与MVCC的实现"
  "53-Change-Buffer-提升写入性能"
  "54-Adaptive-Hash-Index-自适应哈希索引"
  "55-Double-Write-Buffer-数据一致性保障"
  "56-MySQL启动与关闭流程"
)

for i in "${!stage5_titles[@]}"; do
  title="${stage5_titles[$i]}"
  weight=$((i + 45))
  hugo new "mysql/posts/${title}.md"

  file="$BASE_DIR/${title}.md"
  if [ -f "$file" ]; then
    sed -i '' "/^weight:/a\\
stage: 5\\
stageTitle: \"架构原理篇\"
" "$file"
    echo "  ✅ 创建：${title}.md (weight: ${weight}, stage: 5)"
  fi
done

echo ""

# ==================== 第六阶段：高可用实践篇（10篇）====================
echo "📝 创建第六阶段：高可用实践篇（10篇）"

stage6_titles=(
  "57-主从复制原理-binlog与relay-log"
  "58-主从复制配置-一主一从实战"
  "59-主从延迟-原因分析与优化"
  "60-半同步复制-保障数据一致性"
  "61-组复制MGR-MySQL的分布式方案"
  "62-读写分离架构设计"
  "63-数据库备份策略-全量备份与增量备份"
  "64-数据恢复实战-从备份恢复数据"
  "65-高可用方案对比-MHA-MMM-Orchestrator"
  "66-分库分表-应对海量数据"
)

for i in "${!stage6_titles[@]}"; do
  title="${stage6_titles[$i]}"
  weight=$((i + 57))
  hugo new "mysql/posts/${title}.md"

  file="$BASE_DIR/${title}.md"
  if [ -f "$file" ]; then
    sed -i '' "/^weight:/a\\
stage: 6\\
stageTitle: \"高可用实践篇\"
" "$file"
    echo "  ✅ 创建：${title}.md (weight: ${weight}, stage: 6)"
  fi
done

echo ""

# ==================== 第七阶段：性能调优篇（12篇）====================
echo "📝 创建第七阶段：性能调优篇（12篇）"

stage7_titles=(
  "67-MySQL性能监控指标"
  "68-慢查询优化思路与方法"
  "69-表结构设计优化"
  "70-大表优化-分区表"
  "71-JOIN优化-减少关联查询"
  "72-COUNT优化-如何高效统计"
  "73-分页查询优化-深分页问题"
  "74-INSERT批量插入优化"
  "75-参数调优-innodb-buffer-pool-size等关键参数"
  "76-连接池优化"
  "77-SQL改写技巧-提升执行效率"
  "78-生产环境问题排查案例"
)

for i in "${!stage7_titles[@]}"; do
  title="${stage7_titles[$i]}"
  weight=$((i + 67))
  hugo new "mysql/posts/${title}.md"

  file="$BASE_DIR/${title}.md"
  if [ -f "$file" ]; then
    sed -i '' "/^weight:/a\\
stage: 7\\
stageTitle: \"性能调优篇\"
" "$file"
    echo "  ✅ 创建：${title}.md (weight: ${weight}, stage: 7)"
  fi
done

echo ""

# ==================== 第八阶段：源码深度篇（8篇，可选）====================
echo "📝 创建第八阶段：源码深度篇（8篇，可选）"

stage8_titles=(
  "79-MySQL源码编译与调试环境搭建"
  "80-SQL执行流程源码分析"
  "81-InnoDB存储引擎源码结构"
  "82-B+树插入删除源码分析"
  "83-MVCC实现源码分析"
  "84-锁机制源码分析"
  "85-主从复制源码分析"
  "86-性能优化-从源码角度理解"
)

for i in "${!stage8_titles[@]}"; do
  title="${stage8_titles[$i]}"
  weight=$((i + 79))
  hugo new "mysql/posts/${title}.md"

  file="$BASE_DIR/${title}.md"
  if [ -f "$file" ]; then
    sed -i '' "/^weight:/a\\
stage: 8\\
stageTitle: \"源码深度篇\"
" "$file"
    echo "  ✅ 创建：${title}.md (weight: ${weight}, stage: 8)"
  fi
done

echo ""
echo "✅ MySQL专题文章创建完成！"
echo ""
echo "📊 统计信息："
echo "  - 第一阶段（基础入门篇）：10篇"
echo "  - 第二阶段（SQL进阶篇）：12篇"
echo "  - 第三阶段（索引与优化篇）：12篇"
echo "  - 第四阶段（事务与锁篇）：10篇"
echo "  - 第五阶段（架构原理篇）：12篇"
echo "  - 第六阶段（高可用实践篇）：10篇"
echo "  - 第七阶段（性能调优篇）：12篇"
echo "  - 第八阶段（源码深度篇）：8篇"
echo "  - 总计：86篇"
echo ""
echo "💡 下一步："
echo "  1. 检查生成的文章：ls -l $BASE_DIR"
echo "  2. 编辑文章内容，完善标题和描述"
echo "  3. 本地预览：hugo server -D"
