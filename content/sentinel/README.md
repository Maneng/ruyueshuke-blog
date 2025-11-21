# Sentinel 从入门到精通 - 专题使用指南

## 📚 专题概述

这是一个系统化的 Sentinel 学习专题，涵盖从基础概念到生产实践的完整知识体系。

**学习路径**：7个阶段 → 37篇文章 → 约15万字

## 🎯 7大学习阶段

1. **🎯 基础入门篇**（5篇）- 理解流量控制的本质，快速上手
2. **🌊 流量控制深入篇**（6篇）- 掌握限流算法和各种限流策略
3. **🔥 熔断降级篇**（5篇）- 学习熔断降级，防止服务雪崩
4. **⚡ 进阶特性篇**（6篇）- 探索系统保护、热点限流、集群流控
5. **🔌 框架集成篇**（5篇）- 与 Spring Boot、Dubbo、Gateway 集成
6. **🏗️ 架构原理篇**（5篇）- 深入理解 SlotChain、滑动窗口等核心机制
7. **🚀 生产实践篇**（5篇）- 掌握部署、监控、调优、问题排查

## 📝 文章大纲

完整的文章大纲请查看 [ARTICLE_OUTLINES.md](./ARTICLE_OUTLINES.md)

每篇文章都包含：
- ✅ 详细的知识点讲解
- ✅ 完整的代码示例
- ✅ 实战案例演示
- ✅ 配图和架构图
- ✅ 最佳实践建议

## 🚀 快速开始

### 1. 创建新文章

使用 Hugo 命令创建文章：

```bash
hugo new sentinel/posts/01-what-is-flow-control.md
```

### 2. 设置文章参数

每篇文章必须包含以下 Front Matter 参数：

```yaml
---
title: "文章标题"
date: 2025-01-21T14:00:00+08:00
draft: false
tags: ["Sentinel", "流量控制"]
categories: ["技术"]
series: ["Sentinel从入门到精通"]
weight: 1              # 文章序号，用于排序
stage: 1               # 所属阶段（1-7）
stageTitle: "基础入门篇"
description: "文章简介"
---
```

**重要参数说明**：
- `weight`: 文章序号，决定在同一阶段内的排序
- `stage`: 阶段编号（1-7），用于分组展示
- `stageTitle`: 阶段名称，必须与 `layouts/sentinel/list.html` 中定义的一致

### 3. 本地预览

```bash
# 启动本地服务器（包含草稿）
hugo server -D

# 访问专题页面
open http://localhost:1313/blog/sentinel/
```

### 4. 发布文章

```bash
# 将 draft 改为 false
# 确保 date 是当前时间或过去时间（不要用未来时间）

git add content/sentinel/posts/*.md
git commit -m "Add: Sentinel系列文章 - XXX"
git push origin main
```

## 📂 目录结构

```
content/sentinel/
├── README.md                    # 本文件
├── ARTICLE_OUTLINES.md          # 完整文章大纲（37篇）
├── _index.md                    # 专题首页
└── posts/                       # 文章目录
    ├── 01-what-is-flow-control.md
    ├── 02-microservice-challenges.md
    └── ...

layouts/sentinel/
└── list.html                    # 自定义列表模板（阶段分组）

layouts/
├── index.html                   # 首页（含 Sentinel 专题卡片）
└── partials/
    └── extend_head.html         # 样式定义
```

## 🎨 专题样式

**配色方案**：绿色渐变（#11998e → #38ef7d）
**图标**：🛡️ 盾牌（代表保护）
**核心标签**：流量控制、熔断降级、系统保护、集群流控、热点限流、框架集成

## 📊 写作建议

1. **循序渐进**：严格按照阶段顺序写作
2. **实战为主**：每篇文章至少包含1个完整代码示例
3. **配图丰富**：架构图、流程图、效果对比图
4. **深入浅出**：复杂概念用类比、用图解
5. **温故知新**：新文章引用前面的知识点

## 📚 参考资料

- [Sentinel 官方文档](https://sentinelguard.io/zh-cn/)
- [Sentinel GitHub](https://github.com/alibaba/Sentinel)
- [阿里云 AHAS](https://www.aliyun.com/product/ahas)

## ✅ 写作进度

当前进度：**0/37**（0%）

查看详细进度：参见 `ARTICLE_OUTLINES.md` 中的"写作进度跟踪"表格

---

**最后更新**：2025-01-21
