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

## 故障排查

- **推送后网站没更新**: 检查GitHub Actions是否成功执行
- **图片显示404**: 确认路径正确（路径区分大小写）且图片已提交
- **本地预览正常但线上样式错误**: 检查config.toml中的baseURL配置

详细故障排查请查看 `TROUBLESHOOTING.md`。