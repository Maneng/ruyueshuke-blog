# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

这是一个基于Hugo的个人博客系统，采用PaperMod主题，通过GitHub Actions自动部署到阿里云服务器。

## 常用命令

### 日常写作工作流

```bash
# 1. 创建新文章
hugo new posts/$(date +%Y-%m-%d)-article-title.md
# 或使用具体名称
hugo new posts/java-performance-tuning.md

# 2. 本地预览（包含草稿）
hugo server -D

# 3. 构建静态文件
hugo --minify

# 4. 提交并发布（自动触发部署）
git add .
git commit -m "Add: 文章标题"
git push origin main

# 5. 连接服务器（使用别名）
ruyue
```

### 图片管理

```bash
# 复制图片到静态目录
cp ~/Downloads/image.png static/images/$(date +%Y-%m-%d)-image.png

# 在Markdown中引用
# ![描述](/images/2025-01-15-image.png)
```

### 查看部署状态

访问 GitHub Actions 页面查看部署进度（通常2-3分钟完成）。

## 核心架构

### 目录结构

- `content/posts/` - 所有博客文章存放位置
- `static/images/` - 图片资源目录
- `themes/PaperMod/` - Hugo主题（Git子模块）
- `config.toml` - Hugo配置文件（站点配置）
- `.github/workflows/deploy.yml` - 自动部署配置
- `hugo-md-templates/` - 12种写作模板

### 部署流程

1. **本地编写** → Git推送到main分支
2. **GitHub Actions触发** → 安装Hugo → 构建站点
3. **SSH部署** → 同步到服务器 `/usr/share/testpage/`
4. **Nginx服务** → 访问地址 https://ruyueshuke.com/blog/

### 配置要点

- **baseURL**: `https://ruyueshuke.com/blog/`（正式域名）
- **部署目录**: `/usr/share/testpage/`（服务器上）
- **主题**: PaperMod（通过Git子模块管理）
- **语言**: 中文（zh-cn）

## 模块化专题系统

### 系统架构

博客支持模块化专题展示，每个专题独立管理，在首页以卡片形式展现。

**核心组成**：
1. **首页卡片** (`layouts/index.html`)：专题入口，显示在首页
2. **专题目录** (`content/{module-name}/`)：专题内容存放位置
3. **样式定义** (`layouts/partials/extend_head.html`)：卡片视觉样式

**现有专题**：
- `content/crossborder/` - 跨境电商关务知识（紫色渐变 🟣）
- `content/business/` - 跨境电商业务知识（深蓝到青色渐变 🔵）
- `content/java-ecosystem/` - Java技术生态全景（橙红渐变 🟠）

### 标准化创建流程（SOP）

#### 第一步：创建专题目录结构

```bash
# 1. 创建专题目录和文章子目录
mkdir -p content/{module-name}/posts

# 2. 创建专题首页 _index.md
# 示例路径：content/{module-name}/_index.md
```

**_index.md 模板**：
```yaml
---
title: "专题标题"
date: 2025-10-21T15:00:00+08:00
layout: "list"
description: "专题简介，一句话说明这个专题的定位"
---

## 关于{专题名称}

专题介绍，说明为什么这个专题重要，涵盖哪些内容。

### 为什么{专题}很重要？

- **关键点1**：说明
- **关键点2**：说明
- **关键点3**：说明

### 这里有什么？

系统化的知识分享，从入门到精通：

✅ **模块1**：说明
✅ **模块2**：说明
✅ **模块3**：说明

---

## 知识体系

### 🏛️ 分类1
简要说明

### 📋 分类2
简要说明

### 🔍 分类3
简要说明

---

## 最新文章
```

#### 第二步：在首页添加专题卡片

编辑 `layouts/index.html`，在现有专题卡片之后添加新卡片（约54-118行之间）：

```html
{{/* {专题名称}专题入口卡片 */}}
<article class="{module}-featured-card">
  <div class="{module}-card-content">
    <div class="{module}-card-header">
      <span class="{module}-icon">🎯</span>
      <h2>专题标题</h2>
    </div>
    <div class="{module}-card-tags">
      <span class="tag">🏷️ 标签1</span>
      <span class="tag">🏷️ 标签2</span>
      <span class="tag">🏷️ 标签3</span>
      <span class="tag">🏷️ 标签4</span>
      <span class="tag">🏷️ 标签5</span>
      <span class="tag">🏷️ 标签6</span>
    </div>
    <p class="{module}-card-description">
      专题简介，用一两句话说明这个专题的核心内容和价值。
    </p>
    <div class="{module}-card-footer">
      <a href="{{ "{module}/" | absURL }}" class="{module}-btn">
        进入专题 →
      </a>
      {{- with (site.GetPage "/{module}") }}
      {{- $count := len (where .Site.RegularPages "Section" "{module}") }}
      {{- if gt $count 0 }}
      <span class="{module}-count">{{ $count }} 篇文章</span>
      {{- end }}
      {{- end }}
    </div>
  </div>
</article>
```

**注意**：将 `{module}` 替换为实际的模块名称（如 `business`、`crossborder`）

#### 第三步：添加样式定义

编辑 `layouts/partials/extend_head.html`，在现有样式之后添加新模块的CSS：

```css
/* {专题名称}卡片样式 */
.{module}-featured-card {
  background: linear-gradient(135deg, #起始色 0%, #结束色 100%);
  border-radius: 16px;
  padding: 32px;
  margin-bottom: 32px;
  box-shadow: 0 10px 40px rgba(起始色RGB, 0.3);
  transition: transform 0.3s ease, box-shadow 0.3s ease;
  border: none;
  position: relative;
  overflow: hidden;
}

.{module}-featured-card::before {
  content: '';
  position: absolute;
  top: 0;
  right: 0;
  width: 200px;
  height: 200px;
  background: radial-gradient(circle, rgba(255,255,255,0.1) 0%, transparent 70%);
  border-radius: 50%;
  transform: translate(50%, -50%);
}

.{module}-featured-card:hover {
  transform: translateY(-4px);
  box-shadow: 0 15px 50px rgba(起始色RGB, 0.4);
}

.{module}-card-content {
  position: relative;
  z-index: 1;
}

.{module}-card-header {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-bottom: 20px;
}

.{module}-icon {
  font-size: 32px;
  line-height: 1;
}

.{module}-card-header h2 {
  color: #ffffff;
  font-size: 28px;
  font-weight: 700;
  margin: 0;
  letter-spacing: -0.5px;
}

.{module}-card-tags {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
  margin-bottom: 20px;
}

.{module}-card-tags .tag {
  background: rgba(255, 255, 255, 0.2);
  backdrop-filter: blur(10px);
  color: #ffffff;
  padding: 6px 14px;
  border-radius: 20px;
  font-size: 13px;
  font-weight: 500;
  border: 1px solid rgba(255, 255, 255, 0.3);
  transition: all 0.2s ease;
}

.{module}-card-tags .tag:hover {
  background: rgba(255, 255, 255, 0.3);
  transform: translateY(-2px);
}

.{module}-card-description {
  color: rgba(255, 255, 255, 0.95);
  font-size: 16px;
  line-height: 1.7;
  margin-bottom: 24px;
  font-weight: 400;
}

.{module}-card-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  flex-wrap: wrap;
  gap: 16px;
}

.{module}-btn {
  display: inline-flex;
  align-items: center;
  background: #ffffff;
  color: #主色调;
  padding: 12px 28px;
  border-radius: 8px;
  font-weight: 600;
  font-size: 15px;
  text-decoration: none;
  transition: all 0.3s ease;
  box-shadow: 0 4px 15px rgba(0, 0, 0, 0.1);
}

.{module}-btn:hover {
  background: #悬停背景色;
  transform: translateX(4px);
  box-shadow: 0 6px 20px rgba(0, 0, 0, 0.15);
}

.{module}-count {
  color: rgba(255, 255, 255, 0.9);
  font-size: 14px;
  font-weight: 500;
  padding: 8px 16px;
  background: rgba(255, 255, 255, 0.15);
  border-radius: 20px;
  backdrop-filter: blur(10px);
}

/* 响应式设计 */
@media screen and (max-width: 768px) {
  .{module}-featured-card {
    padding: 24px;
    margin-bottom: 24px;
  }

  .{module}-card-header h2 {
    font-size: 22px;
  }

  .{module}-card-tags {
    gap: 8px;
  }

  .{module}-card-tags .tag {
    font-size: 12px;
    padding: 5px 12px;
  }

  .{module}-card-description {
    font-size: 14px;
    line-height: 1.6;
  }

  .{module}-card-footer {
    flex-direction: column;
    align-items: flex-start;
  }

  .{module}-btn {
    width: 100%;
    justify-content: center;
  }
}

/* 暗色模式适配 */
.dark .{module}-featured-card {
  background: linear-gradient(135deg, #暗色起始 0%, #暗色结束 100%);
  box-shadow: 0 10px 40px rgba(暗色RGB, 0.3);
}

.dark .{module}-featured-card:hover {
  box-shadow: 0 15px 50px rgba(暗色RGB, 0.4);
}
```

**配色方案参考**：
- **紫色系**：`#667eea` → `#764ba2`（✅ 已用于关务知识）
- **深蓝青色系**：`#1e2875` → `#0ea5a5`（✅ 已用于业务知识）
- **橙红系（Java色）**：`#FF6B35` → `#F7931E`（✅ 已用于Java生态）
- **绿色系**：`#11998e` → `#38ef7d`（生机成长，待用）
- **金色系**：`#f7971e` → `#ffd200`（高端奢华，待用）
- **粉紫系**：`#f093fb` → `#f5576c`（温柔活力，待用）

#### 第四步：迁移或创建文章

```bash
# 方式1：移动现有文章到专题
mv content/posts/{article-name}.md content/{module}/posts/

# 方式2：创建新文章
hugo new {module}/posts/$(date +%Y-%m-%d)-article-title.md
```

#### 第五步：本地测试

```bash
# 1. 启动本地服务器
hugo server -D

# 2. 访问首页检查卡片显示
# 浏览器访问：http://localhost:1313/blog/

# 3. 访问专题页面检查文章列表
# 浏览器访问：http://localhost:1313/blog/{module}/
```

#### 第六步：提交代码

```bash
# 1. 查看更改
git status

# 2. 添加所有相关文件
git add content/{module}/ layouts/index.html layouts/partials/extend_head.html

# 3. 提交代码
git commit -m "Add: 新增{专题名称}模块"

# 4. 推送到服务器（自动部署）
git push origin main
```

### 注意事项

1. **模块命名**：使用小写字母和连字符，避免中文（如 `business`、`tech-tutorial`）
2. **配色选择**：每个模块使用不同的渐变色，保持视觉区分度，亮度适中
3. **图标选择**：为每个专题选择合适的emoji图标（如 🌏 📊 🎯 💡 ☕）
4. **文章数量**：建议每个专题至少有3-5篇文章再发布
5. **描述精准**：专题简介要简洁有力，突出核心价值
6. **首篇文章**：建议首篇是系统性、全景式的文章，为专题定调

### 实战案例参考

以下是已创建的三个专题模块，可作为新模块创建的参考：

#### 案例1：跨境电商关务知识（crossborder）

```yaml
模块名称: crossborder
专题标题: 跨境电商关务知识
图标: 🌏
配色: #667eea → #764ba2（紫色渐变）
定位: 关务实践经验，从资质准入到风险管理
核心标签: 资质准入、单证申报、查验检疫、税款缴纳、物流监管、风险管理
首篇文章: 三单对碰技术详解（技术实现细节）
```

#### 案例2：跨境电商业务知识（business）

```yaml
模块名称: business
专题标题: 跨境电商业务知识
图标: 📊
配色: #1e2875 → #0ea5a5（深蓝到青色渐变）
定位: 业务层面实践，从模式选择到供应链管理
核心标签: 业务模式、供应链、平台运营、风险合规、成本财务、技术支撑
首篇文章: 三大业务模式深度解析（业务全景视角）
配色调整: 初版过亮，调暗30-40%后更有质感
```

#### 案例3：Java技术生态全景（java-ecosystem）

```yaml
模块名称: java-ecosystem
专题标题: Java技术生态全景
图标: ☕
配色: #FF6B35 → #F7931E（橙红渐变，Java品牌色）
定位: Java技术栈系统化梳理，从JVM到微服务
核心标签: 核心基础、Spring生态、数据存储、微服务、性能优化、开发工具
首篇文章: Java技术生态全景图（10000字，9大章节）
创建时间: 约15分钟（按SOP流程）
```

**关键经验总结**：
- 配色要有品牌关联性（如Java用橙色、业务用沉稳蓝色）
- 首篇文章要有深度和广度，建立专题权威性
- 图标选择要直观，一眼看出专题方向
- 卡片描述用"涵盖XX、XX、XX六大核心XX"句式，简洁有力

### 快速检查清单

创建新专题模块时，确保完成以下步骤：

- [ ] 创建目录 `content/{module}/posts/`
- [ ] 创建 `content/{module}/_index.md`
- [ ] 在 `layouts/index.html` 添加卡片
- [ ] 在 `layouts/partials/extend_head.html` 添加样式
- [ ] 迁移或创建至少3篇文章
- [ ] 本地预览确认效果
- [ ] 提交代码并推送

## 专题内文章分组展示

### 功能概述

为专题内的文章实现**按学习阶段分组展示**，替代传统的单一列表，让学习路径更清晰。

**典型应用场景**：
- 技术教程专题（基础→进阶→实战→源码）
- 系列课程专题（入门→原理→特性→优化→云原生）
- 知识体系专题（理论→实践→高级→专家）

**效果特点**：
- ✅ 多阶段折叠展示（默认全部折叠）
- ✅ 卡片式紧凑布局（信息密度高）
- ✅ 响应式设计（自适应各种屏幕）
- ✅ 优雅的动画效果
- ✅ 支持暗色模式

### 实现步骤（SOP）

#### 第一步：为文章添加阶段标签

在每篇文章的 Front Matter 中添加 `stage` 和 `stageTitle` 参数：

```yaml
---
title: "文章标题"
date: 2025-11-13T20:00:00+08:00
draft: false
tags: ["标签1", "标签2"]
categories: ["技术"]
description: "文章简介"
series: ["系列名称"]
weight: 1                           # 可选，用于阶段内排序
stage: 1                            # 必填，阶段编号（1-6）
stageTitle: "基础入门篇"             # 必填，阶段名称
---
```

**快速批量添加脚本**（示例）：
```bash
#!/bin/bash
# 为文章批量添加 stage 参数
BASE_DIR="/path/to/content/{module}/posts"

# 第一阶段：基础入门篇 (01-10)
for i in 01 02 03 04 05 06 07 08 09 10; do
    file=$(ls "$BASE_DIR/${i}-"*.md 2>/dev/null | head -1)
    if [ -f "$file" ]; then
        # 检查是否已有 stage 参数
        if ! grep -q "^stage:" "$file"; then
            # 在 weight 行后添加 stage 和 stageTitle
            sed -i '' '/^weight:/a\
stage: 1\
stageTitle: "基础入门篇"
' "$file"
            echo "✓ 已添加 stage 到: $(basename "$file")"
        fi
    fi
done

# 第二阶段：架构原理篇 (11-20)
for i in 11 12 13 14 15 16 17 18 19 20; do
    file=$(ls "$BASE_DIR/${i}-"*.md 2>/dev/null | head -1)
    if [ -f "$file" ]; then
        if ! grep -q "^stage:" "$file"; then
            sed -i '' '/^weight:/a\
stage: 2\
stageTitle: "架构原理篇"
' "$file"
            echo "✓ 已添加 stage 到: $(basename "$file")"
        fi
    fi
done

# 以此类推，添加其他阶段...
```

#### 第二步：创建自定义列表模板

创建文件 `layouts/{module}/list.html`（以 rocketmq 为例）：

```html
{{- define "main" }}

{{- if .Content }}
<div class="post-content">
  {{- if not (.Param "disableAnchoredHeadings") }}
  {{- partial "anchored_headings.html" .Content -}}
  {{- else }}{{ .Content }}{{ end }}
</div>
{{- end }}

{{/* 按阶段分组显示文章 */}}
<div class="rocketmq-articles-by-stage">
  {{/* 定义所有阶段 */}}
  {{- $stages := slice
    (dict "id" 1 "title" "🎯 第一阶段：基础入门篇" "desc" "从消息队列的本质出发，逐步掌握核心概念和基础用法" "icon" "🎯")
    (dict "id" 2 "title" "🏗️ 第二阶段：架构原理篇" "desc" "深入理解核心组件的设计原理" "icon" "🏗️")
    (dict "id" 3 "title" "⚡ 第三阶段：进阶特性篇" "desc" "掌握高级特性的原理与实践" "icon" "⚡")
    (dict "id" 4 "title" "🔧 第四阶段：生产实践篇" "desc" "学习生产环境的部署、监控、优化和排查" "icon" "🔧")
    (dict "id" 5 "title" "🚀 第五阶段：云原生演进篇" "desc" "探索云原生场景的应用" "icon" "🚀")
    (dict "id" 6 "title" "💡 第六阶段：源码深度篇" "desc" "通过源码分析，理解设计思想和优化技巧" "icon" "💡")
  -}}

  {{/* 获取所有文章并按 weight 排序 */}}
  {{- $pages := where .Site.RegularPages "Section" "rocketmq" }}
  {{- $pages = where $pages "Type" "rocketmq" }}
  {{- $pages = $pages.ByWeight }}

  {{/* 按阶段分组 */}}
  {{- range $stageInfo := $stages }}
    {{- $stageId := $stageInfo.id }}
    {{- $stagePosts := where $pages "Params.stage" $stageId }}

    {{- if $stagePosts }}
    <div class="stage-section" id="stage-{{ $stageId }}">
      <div class="stage-header" onclick="toggleStage({{ $stageId }})">
        <h2>
          <span class="stage-icon">{{ $stageInfo.icon }}</span>
          {{ $stageInfo.title }}
          <span class="article-count">({{ len $stagePosts }} 篇)</span>
          <span class="toggle-icon" id="toggle-{{ $stageId }}">▼</span>
        </h2>
        <p class="stage-desc">{{ $stageInfo.desc }}</p>
      </div>

      <div class="stage-articles" id="articles-{{ $stageId }}">
        <div class="articles-grid">
          {{- range $index, $page := $stagePosts }}
          <article class="article-card">
            <div class="article-number">{{ printf "%02d" (add $index 1) }}</div>
            <div class="article-content">
              <h3 class="article-title">
                <a href="{{ .RelPermalink }}">{{ .Title | markdownify }}</a>
              </h3>
              {{- if .Params.description }}
              <p class="article-description">{{ .Params.description }}</p>
              {{- end }}
              <div class="article-meta">
                <time datetime="{{ .Date.Format "2006-01-02" }}">
                  📅 {{ .Date.Format "2006-01-02" }}
                </time>
                {{- if .Params.tags }}
                <span class="article-tags">
                  {{- range first 3 .Params.tags }}
                  <span class="tag">{{ . }}</span>
                  {{- end }}
                </span>
                {{- end }}
              </div>
            </div>
          </article>
          {{- end }}
        </div>
      </div>
    </div>
    {{- end }}
  {{- end }}
</div>

<style>
/* 阶段分组样式 - 紧凑版 */
.rocketmq-articles-by-stage {
  margin-top: 30px;
}

.stage-section {
  margin-bottom: 40px;
  border-radius: 12px;
  overflow: hidden;
  box-shadow: 0 2px 8px rgba(0,0,0,0.1);
}

.stage-header {
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: white;
  padding: 24px 30px;
  cursor: pointer;
  user-select: none;
  transition: all 0.3s ease;
}

.stage-header:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(102, 126, 234, 0.3);
}

.stage-header h2 {
  margin: 0 0 10px 0;
  font-size: 24px;
  font-weight: 700;
  display: flex;
  align-items: center;
  gap: 10px;
  color: white;
}

.stage-icon {
  font-size: 28px;
}

.article-count {
  font-size: 16px;
  opacity: 0.9;
  font-weight: 500;
}

.toggle-icon {
  margin-left: auto;
  transition: transform 0.3s ease;
  font-size: 18px;
}

.toggle-icon.collapsed {
  transform: rotate(-90deg);
}

.stage-desc {
  margin: 0;
  font-size: 14px;
  opacity: 0.95;
  line-height: 1.6;
}

.stage-articles {
  background: var(--entry);
  padding: 15px;
  max-height: 10000px;
  overflow: hidden;
  transition: max-height 0.5s ease, padding 0.5s ease;
}

.stage-articles.collapsed {
  max-height: 0;
  padding: 0 15px;
}

.articles-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 12px;
}

.article-card {
  background: var(--theme);
  border: 1px solid var(--border);
  border-radius: 6px;
  padding: 12px;
  transition: all 0.3s ease;
  display: flex;
  gap: 10px;
  position: relative;
}

.article-card:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(0,0,0,0.08);
  border-color: #667eea;
}

.article-number {
  font-size: 24px;
  font-weight: 700;
  color: #667eea;
  opacity: 0.3;
  min-width: 40px;
  text-align: center;
}

.article-content {
  flex: 1;
}

.article-title {
  margin: 0 0 6px 0;
  font-size: 14px;
  line-height: 1.4;
}

.article-title a {
  color: var(--primary);
  text-decoration: none;
  transition: color 0.3s ease;
}

.article-title a:hover {
  color: #667eea;
}

.article-description {
  font-size: 12px;
  color: var(--secondary);
  margin: 0 0 8px 0;
  line-height: 1.5;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

.article-meta {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 11px;
  color: var(--secondary);
  flex-wrap: wrap;
}

.article-tags {
  display: flex;
  gap: 4px;
  flex-wrap: wrap;
}

.article-tags .tag {
  background: var(--code-bg);
  padding: 2px 6px;
  border-radius: 3px;
  font-size: 10px;
}

/* 响应式设计 */
@media screen and (max-width: 768px) {
  .articles-grid {
    grid-template-columns: 1fr;
  }

  .stage-header {
    padding: 20px;
  }

  .stage-header h2 {
    font-size: 20px;
  }

  .article-number {
    font-size: 20px;
    min-width: 35px;
  }
}

/* 暗色模式适配 */
.dark .stage-header {
  background: linear-gradient(135deg, #5a67d8 0%, #6b46c1 100%);
}
</style>

<script>
function toggleStage(stageId) {
  const articles = document.getElementById('articles-' + stageId);
  const toggle = document.getElementById('toggle-' + stageId);

  if (articles.classList.contains('collapsed')) {
    articles.classList.remove('collapsed');
    toggle.classList.remove('collapsed');
  } else {
    articles.classList.add('collapsed');
    toggle.classList.add('collapsed');
  }
}

// 页面加载时默认折叠所有阶段
document.addEventListener('DOMContentLoaded', function() {
  document.querySelectorAll('.stage-articles').forEach(el => el.classList.add('collapsed'));
  document.querySelectorAll('.toggle-icon').forEach(el => el.classList.add('collapsed'));
});
</script>

{{- end }}{{/* end main */}}
```

#### 第三步：样式优化说明

**紧凑型设计尺寸**（相比标准版节省约40%空间）：

| 元素 | 标准版 | 紧凑版 | 说明 |
|-----|-------|-------|-----|
| 卡片内边距 | 20px | **12px** | 减少40% |
| 卡片间距 | 20px | **12px** | 减少40% |
| 文章编号 | 32px | **24px** | 减少25% |
| 标题字体 | 16px | **14px** | 减少12.5% |
| 描述字体 | 13px | **12px** | 减少7.7% |
| 标签字体 | 11px | **10px** | 减少9% |
| 网格最小宽度 | 320px | **280px** | 减少12.5% |

**颜色配色建议**：
- 默认使用紫色渐变：`#667eea → #764ba2`
- 可根据专题主题色调整 `.stage-header` 的 `background` 属性
- 暗色模式会自动调整为深紫色

#### 第四步：本地测试

```bash
# 1. 启动本地服务器
hugo server -D

# 2. 访问专题页面
# 浏览器访问：http://localhost:1313/blog/{module}/

# 3. 测试功能
# - 所有阶段是否默认折叠
# - 点击阶段标题是否能正常展开/折叠
# - 文章卡片是否紧凑显示
# - 响应式布局是否正常（调整浏览器窗口测试）
```

#### 第五步：提交代码

```bash
# 1. 查看更改
git status

# 2. 添加文件
git add content/{module}/posts/*.md layouts/{module}/list.html

# 3. 提交
git commit -m "Add: {专题名称}添加阶段分组展示功能"

# 4. 推送
git push origin main
```

### 实战案例：RocketMQ专题

```yaml
模块名称: rocketmq
专题标题: RocketMQ从入门到精通
图标: 🚀
配色: #667eea → #764ba2（紫色渐变）
文章数量: 12篇
阶段划分: 6个学习阶段

阶段分布:
- 🎯 第一阶段：基础入门篇 (10篇) - 01-10号文章
- 🏗️ 第二阶段：架构原理篇 (2篇)  - 11-12号文章
- ⚡ 第三阶段：进阶特性篇 (0篇)  - 待补充
- 🔧 第四阶段：生产实践篇 (0篇)  - 待补充
- 🚀 第五阶段：云原生演进篇 (0篇)  - 待补充
- 💡 第六阶段：源码深度篇 (0篇)  - 待补充

实现时间: 约20分钟
优化效果: 同屏显示文章数量提升60%
```

### 关键经验总结

1. **阶段数量**：建议3-6个阶段，过多会导致信息过载
2. **默认折叠**：提升页面加载速度，让用户主动选择感兴趣的阶段
3. **紧凑布局**：小卡片设计提高信息密度，适合快速浏览
4. **响应式**：手机端自动切换为单列布局
5. **渐进增强**：无JavaScript环境下仍可正常查看（默认展开）
6. **阶段命名**：使用emoji + 序号 + 名称，视觉识别度高
7. **描述精炼**：阶段描述控制在20字以内，简洁有力

### 常见问题

**Q1: 如何修改默认行为为展开所有阶段？**
```javascript
// 在 <script> 标签中，注释掉以下两行：
// document.querySelectorAll('.stage-articles').forEach(el => el.classList.add('collapsed'));
// document.querySelectorAll('.toggle-icon').forEach(el => el.classList.add('collapsed'));
```

**Q2: 如何调整卡片更大或更小？**
```css
/* 在 <style> 中修改这些值 */
.article-card {
  padding: 12px;  /* 增大此值可让卡片更大 */
}

.articles-grid {
  gap: 12px;      /* 卡片间距 */
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));  /* 最小宽度 */
}
```

**Q3: 如何为不同阶段设置不同颜色？**
```css
/* 为每个阶段添加特定样式 */
#stage-1 .stage-header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); }
#stage-2 .stage-header { background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%); }
#stage-3 .stage-header { background: linear-gradient(135deg, #4facfe 0%, #00f2fe 100%); }
/* ... 以此类推 */
```

### 快速检查清单

实现分组展示功能时，确保完成：

- [ ] 为所有文章添加 `stage` 和 `stageTitle` 参数
- [ ] 创建 `layouts/{module}/list.html` 自定义模板
- [ ] 定义所有阶段信息（标题、图标、描述）
- [ ] 本地测试折叠/展开功能
- [ ] 测试响应式布局（手机/平板/电脑）
- [ ] 检查暗色模式下的显示效果
- [ ] 提交代码并推送

## 文章Front Matter规范

```yaml
---
title: "文章标题"
date: 2025-01-15T20:00:00+08:00
draft: false                    # false=发布，true=草稿
tags: ["标签1", "标签2"]
categories: ["分类"]
description: "文章简介"
series: ["系列名称"]            # 可选，用于系列文章
weight: 1                       # 可选，系列文章排序
---
```

### ⚠️ 重要：文章发布时间规范

**CRITICAL: Hugo默认不会发布未来时间的文章！**

创建文章时，`date` 字段**必须遵守以下规则**：

1. ✅ **使用当前时间或过去时间**
2. ❌ **绝对不要使用未来时间**

**错误示例**（会导致文章不显示）：
```yaml
# 当前时间：2025-10-21 14:00
date: 2025-10-21T18:00:00+08:00  # ❌ 未来时间，文章不会显示！
```

**正确示例**：
```yaml
# 当前时间：2025-10-21 14:00
date: 2025-10-21T12:00:00+08:00  # ✅ 过去时间，正常显示
date: 2025-10-21T14:00:00+08:00  # ✅ 当前时间，正常显示
```

**如何获取当前时间**：
```bash
# 获取当前时间（东八区）
date +"%Y-%m-%dT%H:%M:%S+08:00"
# 输出示例：2025-10-21T14:30:00+08:00
```

**定时发布方案**（如果需要）：
- 方案1：先设置 `draft: true`，到发布时间改为 `draft: false`
- 方案2：使用当前时间发布，不要使用未来时间

### 📌 文章排序说明

**问题**：Hugo默认在有 `weight` 字段时，会按weight升序排列，而不是按日期倒序。

**解决方案**：已创建自定义模板 `layouts/_default/list.html`，强制按日期倒序排列。

**核心代码**：
```go
{{- $pages = sort $pages "Date" "desc" }}
```

**说明**：
- `weight` 字段仍然可以使用（用于系列文章内部排序）
- 文章列表页面会按日期倒序显示（最新文章在最前面）
- 如需修改排序逻辑，编辑 `layouts/_default/list.html` 文件

## 写作模板

项目包含12种预定义模板在 `hugo-md-templates/` 目录：

1. `01-basic-post.md` - 基础文章
2. `02-tech-tutorial.md` - 技术教程
3. `03-problem-solution.md` - 问题解决方案
4. `04-book-notes.md` - 读书笔记
5. `05-project-intro.md` - 项目介绍
6. `06-series-article.md` - 系列文章
7. `07-interview-qa.md` - 面试题整理
8. `08-daily-thinking.md` - 日常思考
9. `09-code-snippet.md` - 代码片段
10. `10-tool-recommendation.md` - 工具推荐
11. `11-best-practice.md` - 最佳实践
12. `12-architecture-design.md` - 架构设计

使用方法：
```bash
cp hugo-md-templates/02-tech-tutorial.md content/posts/my-new-tutorial.md
```

## 开发注意事项

### Git工作流

- 主分支: `main`
- 推送到main自动触发部署
- GitHub Secrets配置:
  - `SSH_PRIVATE_KEY` - SSH私钥
  - `SERVER_HOST` - 服务器IP
  - `SERVER_USER` - 服务器用户名

### 图片管理规范

- 存放在 `static/images/` 目录
- 建议按日期组织: `2025-01-15/image.png`
- 避免中文和空格，使用小写字母和连字符
- 大小建议: 小图标<50KB，配图<300KB，大图<800KB

### 标签和分类规范

**技术标签**:
- Java, Spring Boot, MySQL, Redis
- 架构设计, 性能优化, 问题排查

**业务标签**:
- 跨境电商, 供应链, 订单系统

**分类**:
- 技术 - 技术文章
- 业务 - 业务思考
- 随笔 - 日常思考
- 学习 - 读书笔记

## 访客统计系统

### 系统架构

博客使用**自建访客统计系统**，完全替代不蒜子等第三方服务，数据准确可控。

**技术栈**：
- **后端**: Python 3.6 + Flask 2.0 + SQLite
- **部署**: Gunicorn + Systemd + Nginx反向代理
- **特性**: 防刷机制、IP哈希、HTTPS支持

**核心功能**：
- ✅ PV统计（总访问量）
- ✅ UV统计（独立访客，基于IP哈希）
- ✅ 今日访问统计
- ✅ 防刷机制（同一IP 60秒冷却）
- ✅ 隐私保护（IP经SHA256哈希）

### API端点

```
GET  https://ruyueshuke.com/api/stats        # 获取统计数据
POST https://ruyueshuke.com/api/stats/visit  # 记录访问
GET  https://ruyueshuke.com/api/health       # 健康检查
```

**响应示例**：
```json
{
  "success": true,
  "data": {
    "total_pv": 1234,
    "total_uv": 567,
    "today_pv": 89,
    "today_uv": 45
  }
}
```

### 服务管理

```bash
# 查看服务状态
ruyue "systemctl status visitor-stats"

# 查看实时日志
ruyue "journalctl -u visitor-stats -f"

# 重启服务
ruyue "systemctl restart visitor-stats"

# 手动测试API
curl https://ruyueshuke.com/api/stats
```

### 重要文件位置

- **应用目录**: `/opt/visitor-stats/`
- **数据库**: `/var/lib/visitor-stats/stats.db`
- **配置文件**: `/etc/systemd/system/visitor-stats.service`
- **Nginx配置**: `/etc/nginx/conf.d/ruyueshuke.conf`
- **本地代码**: `visitor-stats/`
- **详细文档**: `visitor-stats/README.md`

### 前端集成

访客统计显示在页面底部（`layouts/partials/extend_footer.html`）：

```html
👀 本站总访问量 XXX 次 | 👤 访客数 XXX 人 | 📅 今日访问 XXX 次
```

**工作原理**：
1. 页面加载时自动调用 `POST /api/stats/visit` 记录访问
2. 同时调用 `GET /api/stats` 获取并显示统计数据
3. 数字格式化（千分位逗号分隔）

### 数据维护

**查看数据库**：
```bash
ruyue "sqlite3 /var/lib/visitor-stats/stats.db 'SELECT COUNT(*) as total_visits FROM visits'"
ruyue "sqlite3 /var/lib/visitor-stats/stats.db 'SELECT COUNT(*) as unique_visitors FROM visitors'"
```

**数据备份**（可选）：
```bash
# 手动备份
ruyue "cp /var/lib/visitor-stats/stats.db /backup/stats-$(date +%Y%m%d).db"

# 定时备份（添加到crontab）
ruyue "crontab -e"
# 添加：每天凌晨2点备份
0 2 * * * cp /var/lib/visitor-stats/stats.db /backup/stats-$(date +\%Y\%m\%d).db
```

**注意**：
- 访客统计系统运行稳定，通常无需频繁备份
- 如需备份，建议每周或每月备份一次即可
- 数据丢失可从0重新开始累计

### 故障排查

**访客数显示为 "..." 或 "-"**：
```bash
# 1. 检查API服务状态
ruyue "systemctl status visitor-stats"

# 2. 检查API是否响应
curl https://ruyueshuke.com/api/health

# 3. 查看服务日志
ruyue "journalctl -u visitor-stats -n 50"

# 4. 重启服务
ruyue "systemctl restart visitor-stats"
```

**数据库未初始化**：
```bash
ruyue "cd /opt/visitor-stats && python3 -c 'from app import init_db; init_db()'"
```

**Nginx 502错误**：
```bash
# 检查API服务
ruyue "systemctl status visitor-stats"

# 检查端口监听
ruyue "netstat -tulnp | grep 5000"

# 测试本地连接
ruyue "curl http://127.0.0.1:5000/api/health"
```

## 故障排查

- **推送后网站没更新**: 检查GitHub Actions是否成功执行
- **图片显示404**: 确认路径正确（路径区分大小写）且图片已提交
- **本地预览正常但线上样式错误**: 检查config.toml中的baseURL配置
- **访客统计不显示**: 参考"访客统计系统 - 故障排查"章节

详细故障排查请查看 `TROUBLESHOOTING.md`。