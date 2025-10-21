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