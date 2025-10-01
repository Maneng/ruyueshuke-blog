---
title: "欢迎来到我的博客"
date: 2025-01-15T20:00:00+08:00
draft: false
tags: ["博客", "Hugo", "开始"]
categories: ["随笔"]
description: "这是我的第一篇文章，记录博客搭建过程"
---

## 前言

欢迎来到我的个人知识库！这里将记录我的技术学习、工作思考和日常感悟。

作为一名有7年经验的Java后端开发，专注于跨境电商和供应链系统，我希望通过这个博客：
- 📝 记录技术知识和经验
- 💡 分享问题解决方案
- 🤔 整理每日思考
- 📚 积累个人知识体系

## 技术栈

这个博客使用以下技术搭建：

- **静态网站生成器**：Hugo
- **主题**：PaperMod
- **代码托管**：GitHub
- **自动部署**：GitHub Actions
- **服务器**：阿里云
- **Web服务器**：Nginx

## 特点

- ✅ 支持Markdown写作
- ✅ 代码语法高亮
- ✅ 响应式设计
- ✅ 全文搜索
- ✅ RSS订阅
- ✅ 自动部署

## 代码示例

Java代码示例：

```java
public class HelloWorld {
    public static void main(String[] args) {
        System.out.println("Hello, World!");

        // 输出当前时间
        LocalDateTime now = LocalDateTime.now();
        System.out.println("当前时间: " + now);
    }
}
```

Shell脚本示例：

```bash
#!/bin/bash

# 快速部署脚本
echo "开始部署..."
hugo --minify
rsync -avz public/ user@server:/var/www/blog/
echo "部署完成！"
```

## 图片测试

下面是一张测试图片：

![测试图片](/images/test.png)

## 引用测试

> 学而不思则罔，思而不学则殆。
>
> —— 《论语》

## 列表测试

### 无序列表

- 第一项
- 第二项
  - 子项1
  - 子项2
- 第三项

### 有序列表

1. 首先做这个
2. 然后做那个
3. 最后做另一个

### 任务列表

- [x] 搭建Hugo博客
- [x] 配置GitHub Actions
- [x] 部署到服务器
- [ ] 写更多文章
- [ ] 优化SEO

## 表格测试

| 技术 | 用途 | 难度 |
|------|------|------|
| Hugo | 静态网站生成 | ⭐⭐ |
| GitHub Actions | CI/CD | ⭐⭐⭐ |
| Nginx | Web服务器 | ⭐⭐ |
| Markdown | 写作 | ⭐ |

## 总结

博客搭建完成！接下来会持续更新内容，记录学习和思考的过程。

如果你也想搭建类似的博客，可以参考：
- [Hugo官方文档](https://gohugo.io/documentation/)
- [PaperMod主题](https://github.com/adityatelange/hugo-PaperMod)
- [GitHub Actions文档](https://docs.github.com/en/actions)

---

**更新记录**：
- 2025-01-15：初始发布
