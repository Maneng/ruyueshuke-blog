# Hugo 博客 Markdown 模板库

这是一套完整的 Hugo 博客 Markdown 写作模板，包含 12 种常见的博客写作场景。所有模板都已配置好 Front Matter，并包含详细的内容结构和使用说明。

## 📚 模板列表

| 模板文件 | 用途 | 适用场景 |
|---------|------|---------|
| `01-basic-post.md` | 基础文章模板 | 日常博客文章、技术分享、随笔 |
| `02-tech-tutorial.md` | 技术教程模板 | 分步骤的技术教程、操作指南 |
| `03-problem-solution.md` | 问题解决方案模板 | Bug 修复、问题排查记录 |
| `04-book-notes.md` | 读书笔记模板 | 书籍阅读笔记、影评、课程笔记 |
| `05-project-intro.md` | 项目介绍模板 | 开源项目介绍、作品展示 |
| `06-series-article.md` | 系列文章模板 | 连载文章、系列教程 |
| `07-interview-qa.md` | 面试题模板 | 面试题整理、知识点问答 |
| `08-daily-thinking.md` | 日常思考模板 | 工作思考、技术感悟、生活记录 |
| `09-code-snippet.md` | 代码片段模板 | 实用代码片段、工具函数 |
| `10-tool-recommendation.md` | 工具推荐模板 | 软件推荐、效率工具分享 |
| `11-best-practice.md` | 最佳实践模板 | 编码规范、设计模式、最佳实践 |
| `12-architecture-design.md` | 架构设计模板 | 系统架构、技术选型、设计文档 |

## 🚀 快速开始

### 1. 选择模板

根据你要写的内容类型，从上表中选择对应的模板文件。

### 2. 复制到 content/posts 目录

```bash
# 示例：使用技术教程模板
cp hugo-md-templates/02-tech-tutorial.md content/posts/my-new-tutorial.md
```

### 3. 修改 Front Matter

打开复制的文件，修改文件顶部的 Front Matter：

```yaml
---
title: "你的文章标题"              # 修改为实际标题
date: 2025-10-01T20:00:00+08:00  # 修改为当前日期
draft: false                      # true=草稿, false=发布
tags: ["标签1", "标签2"]          # 添加相关标签
categories: ["分类名"]            # 添加分类
description: "文章简短描述"       # 显示在列表页
---
```

### 4. 编写内容

按照模板中的结构编写你的内容，模板中的示例文本可以直接替换或删除。

### 5. 预览和发布

```bash
# 本地预览
hugo server -D

# 构建发布
hugo
```

## 📝 Front Matter 字段说明

所有模板都包含以下 Front Matter 字段：

| 字段 | 必填 | 说明 | 示例 |
|-----|------|------|------|
| `title` | ✅ | 文章标题 | `"Spring Boot 入门教程"` |
| `date` | ✅ | 发布日期时间 | `2025-10-01T20:00:00+08:00` |
| `draft` | ✅ | 是否为草稿 | `false` (发布) / `true` (草稿) |
| `tags` | ❌ | 标签列表 | `["Java", "Spring Boot"]` |
| `categories` | ❌ | 分类列表 | `["后端开发"]` |
| `description` | ❌ | 文章描述 | `"快速上手 Spring Boot 框架"` |
| `series` | ❌ | 系列名称 | `["Spring 系列"]` |
| `author` | ❌ | 作者（默认使用配置中的） | `"maneng"` |
| `weight` | ❌ | 排序权重（系列文章用） | `1`, `2`, `3` |

### 日期格式说明

推荐使用完整的 ISO 8601 格式：`YYYY-MM-DDTHH:MM:SS+08:00`

- `2025-10-01T20:00:00+08:00` - 包含时区（推荐）
- `2025-10-01T20:00:00` - 不含时区
- `2025-10-01` - 仅日期

## 🎨 Markdown 语法速查

### 标题层级

```markdown
# 一级标题（文章标题，不要使用）
## 二级标题（章节标题）
### 三级标题（小节标题）
#### 四级标题（更小的分组）
```

### 文本样式

```markdown
**粗体文本**
*斜体文本*
~~删除线~~
`行内代码`
```

### 列表

```markdown
# 无序列表
- 项目 1
- 项目 2
  - 子项目 2.1
  - 子项目 2.2

# 有序列表
1. 第一步
2. 第二步
3. 第三步

# 任务列表
- [x] 已完成任务
- [ ] 未完成任务
```

### 代码块

````markdown
```java
public class HelloWorld {
    public static void main(String[] args) {
        System.out.println("Hello, World!");
    }
}
```
````

支持的语言标识：`java`, `javascript`, `python`, `go`, `bash`, `sql`, `yaml`, `json`, `xml`, `html`, `css` 等

### 引用

```markdown
> 这是一段引用文本
>
> 可以有多行
```

### 表格

```markdown
| 列1 | 列2 | 列3 |
|-----|-----|-----|
| 数据1 | 数据2 | 数据3 |
| 数据4 | 数据5 | 数据6 |
```

### 链接和图片

```markdown
# 链接
[链接文本](https://example.com)

# 图片
![图片描述](/images/example.png)

# 带链接的图片
[![图片描述](/images/example.png)](https://example.com)
```

### 分隔线

```markdown
---
```

## 💡 使用技巧

### 1. 图片管理

将图片放在 `static/images/` 目录下，然后在 Markdown 中引用：

```markdown
![图片描述](/images/your-image.png)
```

目录结构示例：
```
static/
└── images/
    ├── 2025/
    │   └── 10/
    │       └── article-image.png
    └── common/
        └── logo.png
```

### 2. 代码高亮

配置文件 `config.toml` 中已启用代码高亮（Monokai 主题），支持行号显示。

### 3. 目录（TOC）

配置中已启用文章目录（`showtoc = true`），会自动根据二级、三级标题生成。

### 4. 草稿管理

- 草稿文章设置 `draft: true`
- 本地预览包含草稿：`hugo server -D`
- 构建时不包含草稿：`hugo`

### 5. 系列文章

使用 `series` 字段和 `weight` 排序：

```yaml
---
title: "Spring Boot 入门（一）：环境搭建"
series: ["Spring Boot 系列"]
weight: 1
---
```

### 6. 快速创建新文章

可以使用 Hugo 命令创建：

```bash
hugo new posts/my-article.md
```

然后基于模板内容修改。

### 7. 标签和分类建议

**常用技术标签**：
- 编程语言：`Java`, `Python`, `JavaScript`, `Go`
- 框架：`Spring Boot`, `React`, `Vue`, `Django`
- 工具：`Git`, `Docker`, `Maven`, `Gradle`
- 领域：`后端开发`, `前端开发`, `数据库`, `架构设计`

**分类建议**：
- 技术文章：`后端开发`, `前端开发`, `DevOps`, `数据库`
- 其他：`工具推荐`, `读书笔记`, `随笔`, `项目`

## 📖 写作流程建议

1. **选择模板** - 根据文章类型选择合适的模板
2. **复制重命名** - 复制到 `content/posts/` 目录并重命名
3. **更新 Front Matter** - 修改标题、日期、标签等信息
4. **编写大纲** - 先列出文章的主要章节
5. **填充内容** - 按照大纲逐步完成内容
6. **添加代码示例** - 包含实际可运行的代码
7. **插入图片** - 适当添加配图说明
8. **本地预览** - `hugo server -D` 查看效果
9. **检查修改** - 检查格式、错别字、链接等
10. **发布** - 设置 `draft: false` 并构建发布

## 🔧 常见问题

### Q: 如何修改文章的发布时间？

A: 修改 Front Matter 中的 `date` 字段：
```yaml
date: 2025-10-01T20:00:00+08:00
```

### Q: 文章不显示在首页？

A: 检查以下几点：
1. `draft` 是否设置为 `false`
2. `date` 是否是未来时间
3. 文件是否在 `content/posts/` 目录下

### Q: 代码块没有语法高亮？

A: 确保代码块使用了正确的语言标识：
````markdown
```java
// 你的代码
```
````

### Q: 图片不显示？

A: 检查：
1. 图片路径是否正确（相对于 `static/` 目录）
2. 图片文件是否存在
3. 路径是否以 `/` 开头

### Q: 如何创建页面而不是文章？

A: 在 `content/` 目录下直接创建 `.md` 文件（不在 `posts/` 目录下），例如 `content/about.md`

## 📚 参考资源

- [Hugo 官方文档](https://gohugo.io/documentation/)
- [PaperMod 主题文档](https://github.com/adityatelange/hugo-PaperMod)
- [Markdown 语法指南](https://www.markdownguide.org/)
- [CommonMark 规范](https://commonmark.org/)

## 🤝 贡献

如果你有更好的模板建议或发现问题，欢迎：

1. 基于现有模板创建新的变体
2. 改进现有模板的结构
3. 补充更多使用示例

---

**最后更新**：2025-10-01

祝写作愉快！✍️
