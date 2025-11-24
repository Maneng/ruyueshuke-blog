# JVM专题快速启动指南

## 📋 快速检查清单

使用以下清单确保JVM专题创建完整：

### ✅ 第一步：创建目录结构（5分钟）

```bash
# 1. 创建专题目录
mkdir -p content/jvm/posts

# 2. 创建专题首页
# 从 JVM_MODULE_PLAN.md 复制 _index.md 的内容
```

**验证**：
```bash
ls -la content/jvm/
# 应该看到：
# - _index.md
# - posts/
```

---

### ✅ 第二步：添加首页卡片（10分钟）

**文件**：`layouts/index.html`

**位置**：在现有专题卡片（business、crossborder、java-ecosystem、rocketmq）之后添加

**代码**：从 `JVM_MODULE_PLAN.md` 中复制"首页卡片"部分的HTML代码

**验证**：
```bash
# 启动本地服务器
hugo server -D

# 浏览器访问
http://localhost:1313/blog/

# 应该看到新的JVM专题卡片（深蓝渐变）
```

---

### ✅ 第三步：添加样式定义（10分钟）

**文件**：`layouts/partials/extend_head.html`

**位置**：在文件末尾添加

**代码**：从 `JVM_MODULE_PLAN.md` 中复制"样式定义"部分的CSS代码

**验证**：
- 刷新浏览器
- 检查卡片样式是否正确显示
- 测试悬停效果

---

### ✅ 第四步：创建列表模板（15分钟）

**文件**：`layouts/jvm/list.html`

**参考**：复制 `layouts/rocketmq/list.html`，修改为8个阶段

**需要修改的部分**：
1. 所有 `rocketmq` 字符串替换为 `jvm`
2. 更新阶段定义（8个阶段）：

```go
{{- $stages := slice
  (dict "id" 1 "title" "🎯 第一阶段：基础认知篇" "desc" "建立JVM全局认知" "icon" "🎯")
  (dict "id" 2 "title" "🏛️ 第二阶段：类加载机制篇" "desc" "理解类的生命周期" "icon" "🏛️")
  (dict "id" 3 "title" "🧠 第三阶段：内存结构篇" "desc" "掌握JVM内存布局" "icon" "🧠")
  (dict "id" 4 "title" "🗑️ 第四阶段：垃圾回收篇" "desc" "全面掌握GC原理" "icon" "🗑️")
  (dict "id" 5 "title" "⚙️ 第五阶段：性能调优篇" "desc" "具备解决性能问题的能力" "icon" "⚙️")
  (dict "id" 6 "title" "🔍 第六阶段：故障诊断篇" "desc" "精通各种诊断工具" "icon" "🔍")
  (dict "id" 7 "title" "🔬 第七阶段：字节码与执行引擎篇" "desc" "理解代码执行的本质" "icon" "🔬")
  (dict "id" 8 "title" "🚀 第八阶段：高级特性与未来篇" "desc" "掌握现代JVM高级特性" "icon" "🚀")
-}}
```

3. 更新CSS样式中的配色（深蓝渐变）：

```css
.stage-header {
  background: linear-gradient(135deg, #1e3a8a 0%, #3b82f6 100%);
  /* ... */
}

.dark .stage-header {
  background: linear-gradient(135deg, #172554 0%, #1e40af 100%);
}
```

**验证**：
```bash
# 访问专题页面
http://localhost:1313/blog/jvm/

# 应该看到8个阶段的折叠列表
```

---

### ✅ 第五步：创建首篇文章（30分钟）

```bash
# 创建第一篇文章
hugo new jvm/posts/01-how-java-program-runs.md
```

**Front Matter模板**：
```yaml
---
title: "Java程序是如何运行的？从HelloWorld说起"
date: 2025-11-21T20:00:00+08:00
draft: false
tags: ["JVM", "Java基础", "运行原理", "HelloWorld"]
categories: ["技术"]
description: "从一个简单的HelloWorld程序开始，深入理解Java程序的完整执行流程，揭开JVM运行机制的神秘面纱"
series: ["JVM从入门到精通"]
weight: 1
stage: 1
stageTitle: "基础认知篇"
---
```

**内容参考**：`JVM_ARTICLE_TEMPLATE.md` 中的完整示例

**验证**：
- 本地预览文章
- 检查是否出现在"第一阶段"分组中

---

### ✅ 第六步：提交代码（5分钟）

```bash
# 1. 查看更改
git status

# 2. 添加所有文件
git add content/jvm/ layouts/index.html layouts/partials/extend_head.html layouts/jvm/

# 3. 提交
git commit -m "Add: 新增Java JVM从入门到精通专题模块

- 创建jvm专题目录结构
- 添加首页入口卡片（深蓝渐变）
- 实现8阶段分组展示功能
- 完成首篇文章：Java程序运行原理"

# 4. 推送到服务器
git push origin main
```

**验证**：
- GitHub Actions 执行成功
- 访问线上地址：https://ruyueshuke.com/blog/

---

## 📝 60篇文章创建流程

### 批量创建文章文件

```bash
#!/bin/bash
# create_jvm_articles.sh

BASE_DIR="content/jvm/posts"

# 第一阶段：基础认知篇（1-5）
hugo new jvm/posts/01-how-java-program-runs.md
hugo new jvm/posts/02-what-is-jvm.md
hugo new jvm/posts/03-jvm-architecture-overview.md
hugo new jvm/posts/04-what-is-bytecode.md
hugo new jvm/posts/05-jvm-jre-jdk-difference.md

# 第二阶段：类加载机制篇（6-10）
hugo new jvm/posts/06-class-loading-lifecycle.md
hugo new jvm/posts/07-classloader-hierarchy.md
hugo new jvm/posts/08-parent-delegation-model.md
hugo new jvm/posts/09-custom-classloader.md
hugo new jvm/posts/10-class-initialization-timing.md

# 第三阶段：内存结构篇（11-18）
hugo new jvm/posts/11-jvm-memory-structure-overview.md
hugo new jvm/posts/12-program-counter.md
hugo new jvm/posts/13-jvm-stack.md
hugo new jvm/posts/14-native-method-stack.md
hugo new jvm/posts/15-heap-memory.md
hugo new jvm/posts/16-method-area.md
hugo new jvm/posts/17-direct-memory.md
hugo new jvm/posts/18-object-memory-layout.md

# 第四阶段：垃圾回收篇（19-30）
hugo new jvm/posts/19-what-is-garbage.md
hugo new jvm/posts/20-reference-counting-vs-reachability.md
hugo new jvm/posts/21-four-reference-types.md
hugo new jvm/posts/22-gc-algorithms-part1.md
hugo new jvm/posts/23-gc-algorithms-part2.md
hugo new jvm/posts/24-gc-collectors-evolution.md
hugo new jvm/posts/25-serial-collector.md
hugo new jvm/posts/26-parallel-collector.md
hugo new jvm/posts/27-cms-collector.md
hugo new jvm/posts/28-g1-collector.md
hugo new jvm/posts/29-zgc-shenandoah.md
hugo new jvm/posts/30-gc-log-analysis.md

# 第五阶段：性能调优篇（31-38）
hugo new jvm/posts/31-jvm-parameters.md
hugo new jvm/posts/32-memory-tuning.md
hugo new jvm/posts/33-gc-tuning.md
hugo new jvm/posts/34-jit-tuning.md
hugo new jvm/posts/35-tuning-methodology.md
hugo new jvm/posts/36-oom-troubleshooting.md
hugo new jvm/posts/37-high-cpu-troubleshooting.md
hugo new jvm/posts/38-memory-leak-troubleshooting.md

# 第六阶段：故障诊断篇（39-45）
hugo new jvm/posts/39-cli-tools-part1.md
hugo new jvm/posts/40-cli-tools-part2.md
hugo new jvm/posts/41-visual-tools.md
hugo new jvm/posts/42-modern-tools.md
hugo new jvm/posts/43-thread-analysis.md
hugo new jvm/posts/44-heap-analysis-mat.md
hugo new jvm/posts/45-gc-analysis-tools.md

# 第七阶段：字节码与执行引擎篇（46-52）
hugo new jvm/posts/46-bytecode-instruction-set.md
hugo new jvm/posts/47-method-invocation.md
hugo new jvm/posts/48-stack-frame-execution.md
hugo new jvm/posts/49-jit-compilation.md
hugo new jvm/posts/50-compilation-optimization.md
hugo new jvm/posts/51-tiered-compilation.md
hugo new jvm/posts/52-reflection-performance.md

# 第八阶段：高级特性与未来篇（53-60）
hugo new jvm/posts/53-java-module-system.md
hugo new jvm/posts/54-cds-appcds.md
hugo new jvm/posts/55-graalvm.md
hugo new jvm/posts/56-project-loom.md
hugo new jvm/posts/57-project-panama.md
hugo new jvm/posts/58-jvm-in-containers.md
hugo new jvm/posts/59-jvm-security.md
hugo new jvm/posts/60-jvm-future.md

echo "✓ 已创建所有60篇文章框架"
```

### 为文章添加Stage参数脚本

```bash
#!/bin/bash
# add_stage_params.sh

BASE_DIR="content/jvm/posts"

# 第一阶段：基础认知篇（1-5）
for i in 01 02 03 04 05; do
    file=$(ls "$BASE_DIR/${i}-"*.md 2>/dev/null | head -1)
    if [ -f "$file" ]; then
        if ! grep -q "^stage:" "$file"; then
            sed -i '' '/^weight:/a\
stage: 1\
stageTitle: "基础认知篇"
' "$file"
            echo "✓ 已添加 stage 到: $(basename "$file")"
        fi
    fi
done

# 第二阶段：类加载机制篇（6-10）
for i in 06 07 08 09 10; do
    file=$(ls "$BASE_DIR/${i}-"*.md 2>/dev/null | head -1)
    if [ -f "$file" ]; then
        if ! grep -q "^stage:" "$file"; then
            sed -i '' '/^weight:/a\
stage: 2\
stageTitle: "类加载机制篇"
' "$file"
            echo "✓ 已添加 stage 到: $(basename "$file")"
        fi
    fi
done

# 第三阶段：内存结构篇（11-18）
for i in 11 12 13 14 15 16 17 18; do
    file=$(ls "$BASE_DIR/${i}-"*.md 2>/dev/null | head -1)
    if [ -f "$file" ]; then
        if ! grep -q "^stage:" "$file"; then
            sed -i '' '/^weight:/a\
stage: 3\
stageTitle: "内存结构篇"
' "$file"
            echo "✓ 已添加 stage 到: $(basename "$file")"
        fi
    fi
done

# 第四阶段：垃圾回收篇（19-30）
for i in {19..30}; do
    file=$(ls "$BASE_DIR/${i}-"*.md 2>/dev/null | head -1)
    if [ -f "$file" ]; then
        if ! grep -q "^stage:" "$file"; then
            sed -i '' '/^weight:/a\
stage: 4\
stageTitle: "垃圾回收篇"
' "$file"
            echo "✓ 已添加 stage 到: $(basename "$file")"
        fi
    fi
done

# 第五阶段：性能调优篇（31-38）
for i in {31..38}; do
    file=$(ls "$BASE_DIR/${i}-"*.md 2>/dev/null | head -1)
    if [ -f "$file" ]; then
        if ! grep -q "^stage:" "$file"; then
            sed -i '' '/^weight:/a\
stage: 5\
stageTitle: "性能调优篇"
' "$file"
            echo "✓ 已添加 stage 到: $(basename "$file")"
        fi
    fi
done

# 第六阶段：故障诊断篇（39-45）
for i in {39..45}; do
    file=$(ls "$BASE_DIR/${i}-"*.md 2>/dev/null | head -1)
    if [ -f "$file" ]; then
        if ! grep -q "^stage:" "$file"; then
            sed -i '' '/^weight:/a\
stage: 6\
stageTitle: "故障诊断篇"
' "$file"
            echo "✓ 已添加 stage 到: $(basename "$file")"
        fi
    fi
done

# 第七阶段：字节码与执行引擎篇（46-52）
for i in {46..52}; do
    file=$(ls "$BASE_DIR/${i}-"*.md 2>/dev/null | head -1)
    if [ -f "$file" ]; then
        if ! grep -q "^stage:" "$file"; then
            sed -i '' '/^weight:/a\
stage: 7\
stageTitle: "字节码与执行引擎篇"
' "$file"
            echo "✓ 已添加 stage 到: $(basename "$file")"
        fi
    fi
done

# 第八阶段：高级特性与未来篇（53-60）
for i in {53..60}; do
    file=$(ls "$BASE_DIR/${i}-"*.md 2>/dev/null | head -1)
    if [ -f "$file" ]; then
        if ! grep -q "^stage:" "$file"; then
            sed -i '' '/^weight:/a\
stage: 8\
stageTitle: "高级特性与未来篇"
' "$file"
            echo "✓ 已添加 stage 到: $(basename "$file")"
        fi
    fi
done

echo "✓ 已为所有文章添加 stage 参数"
```

---

## 📊 写作进度跟踪建议

### 方式1：创建进度文件

```bash
# 创建 JVM_PROGRESS.md 文件跟踪进度
cat > JVM_PROGRESS.md << 'EOF'
# JVM专题写作进度

## 第一阶段：基础认知篇（0/5）
- [ ] 01. Java程序是如何运行的？
- [ ] 02. JVM到底是什么？
- [ ] 03. JVM架构全景图
- [ ] 04. 字节码是什么？
- [ ] 05. JVM、JRE、JDK三者的关系

## 第二阶段：类加载机制篇（0/5）
...
EOF
```

### 方式2：使用GitHub Issues/Projects

在GitHub仓库中创建Project看板，添加60个Issue：

```
Issue #1: [JVM-01] Java程序是如何运行的？
Issue #2: [JVM-02] JVM到底是什么？
...
```

**标签分类**：
- `stage-1` 到 `stage-8`
- `priority-high`、`priority-medium`、`priority-low`
- `status-draft`、`status-review`、`status-published`

---

## 🎯 写作建议

### 每周目标

- **第1-2周**：完成第一阶段（5篇）
- **第3-4周**：完成第二阶段（5篇）
- **第5-7周**：完成第三阶段（8篇）
- **第8-11周**：完成第四阶段（12篇）
- **第12-14周**：完成第五阶段（8篇）
- **第15-16周**：完成第六阶段（7篇）
- **第17-19周**：完成第七阶段（7篇）
- **第20-22周**：完成第八阶段（8篇）

**总计**：约22周（5.5个月）

### 每篇文章的时间分配

- **研究阅读**：1-2小时（查阅资料、源码分析）
- **大纲设计**：30分钟
- **内容撰写**：2-3小时
- **代码验证**：30分钟-1小时
- **校对优化**：30分钟

**每篇总计**：4-6小时

### 质量控制

每篇文章发布前检查：

- [ ] 文章长度：2000-3500字
- [ ] 代码示例：至少2个可运行的示例
- [ ] 图表：至少1个流程图或示意图
- [ ] 实战性：理论60% + 实战40%
- [ ] 连贯性：与上下篇文章有衔接
- [ ] Front Matter：所有字段完整且正确
- [ ] 本地预览：排版正常，无乱码
- [ ] Stage参数：正确分组显示

---

## 📚 推荐资源

### 必备书籍
1. **《深入理解Java虚拟机（第3版）》** - 周志明
2. **《Java性能权威指南》** - Scott Oaks
3. **《Java虚拟机规范》** - Oracle官方

### 在线资源
- [Oracle JVM Specification](https://docs.oracle.com/javase/specs/jvms/se17/html/index.html)
- [OpenJDK Source Code](https://github.com/openjdk/jdk)
- [Java Performance Tuning Guide](https://docs.oracle.com/en/java/javase/17/gctuning/)

### 工具安装
```bash
# JDK 17（推荐使用LTS版本）
brew install openjdk@17

# 可视化工具
brew install --cask visualvm

# Arthas（阿里诊断工具）
curl -O https://arthas.aliyun.com/arthas-boot.jar
```

---

## ❓ 常见问题

### Q1: 如何保持写作节奏？
**建议**：
- 每周固定时间写作（如周末2小时）
- 提前准备好下一篇的大纲
- 使用番茄工作法（25分钟专注 + 5分钟休息）

### Q2: 如何处理复杂主题？
**建议**：
- 拆分成多篇文章（如GC收集器可以每个收集器一篇）
- 先写简化版，再逐步深入
- 使用类比和可视化降低理解难度

### Q3: 如何验证文章的准确性？
**建议**：
- 所有代码必须自己运行验证
- 参考至少2个权威资料（如官方文档 + 权威书籍）
- 对不确定的内容标注"待验证"

### Q4: 如何收集读者反馈？
**建议**：
- 开启博客评论功能
- 在文章末尾添加"有疑问请留言"
- 定期回顾评论，调整后续文章方向

---

## 🚀 现在就开始！

```bash
# 1. 进入博客目录
cd /Users/maneng/claude_project/blog

# 2. 执行快速检查清单的前3步
# （创建目录、添加卡片、添加样式）

# 3. 创建第一篇文章
hugo new jvm/posts/01-how-java-program-runs.md

# 4. 开始写作！
# 参考 JVM_ARTICLE_TEMPLATE.md 中的示例大纲

# 5. 本地预览
hugo server -D

# 6. 提交发布
git add . && git commit -m "Add: JVM专题首篇文章" && git push
```

---

**祝写作顺利！期待看到这个高质量的JVM专题！** ☕
