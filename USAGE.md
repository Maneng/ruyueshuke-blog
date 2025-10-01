# 博客使用指南

本文档详细说明如何使用这个Hugo博客系统。

## 🎯 快速开始

### 完整工作流程

```
写作 → 预览 → 提交 → 推送 → 自动部署 → 访问网站
```

## ✍️ 写作流程

### 1. 创建新文章

```bash
# 方法1：使用日期前缀
cd /Users/maneng/claude_project/blog
hugo new posts/$(date +%Y-%m-%d)-article-title.md

# 方法2：手动指定名称
hugo new posts/java-spring-boot-tips.md

# 示例输出
# Content "/Users/maneng/claude_project/blog/content/posts/2025-01-15-article-title.md" created
```

### 2. 编辑文章

文章位于：`content/posts/` 目录

**Front Matter（文章头部元数据）**：

```markdown
---
title: "文章标题"
date: 2025-01-15T20:00:00+08:00
draft: false                    # false=发布，true=草稿
tags: ["Java", "Spring Boot"]
categories: ["技术"]
description: "文章简介，用于SEO和摘要"
---

## 正文开始

这里是文章内容...
```

**常用字段说明**：

| 字段 | 说明 | 示例 |
|------|------|------|
| title | 文章标题 | "Java性能优化技巧" |
| date | 发布日期时间 | 2025-01-15T20:00:00+08:00 |
| draft | 是否草稿 | false (发布) / true (草稿) |
| tags | 标签（数组） | ["Java", "性能优化"] |
| categories | 分类（数组） | ["技术", "后端"] |
| description | 简介 | 用于SEO和文章列表摘要 |
| showToc | 是否显示目录 | true / false |
| weight | 排序权重 | 数字越小越靠前 |

### 3. 添加图片

**方法1：手动复制**

```bash
# 创建日期目录（推荐）
mkdir -p static/images/$(date +%Y-%m-%d)

# 复制图片
cp ~/Downloads/screenshot.png static/images/2025-01-15/architecture.png
```

**方法2：直接拖拽**

使用Finder将图片拖到 `static/images/` 目录

**在Markdown中引用**：

```markdown
# 相对路径（推荐）
![架构图](/images/2025-01-15/architecture.png)

# 添加图片说明
![架构图](/images/2025-01-15/architecture.png "系统架构设计图")
```

### 4. 本地预览

```bash
# 启动Hugo开发服务器
hugo server -D

# 输出示例：
# Web Server is available at http://localhost:1313/
# Press Ctrl+C to stop
```

**预览特性**：
- ✅ 实时刷新（修改文件自动更新浏览器）
- ✅ `-D` 参数显示草稿文章
- ✅ 显示未来日期的文章

**浏览器访问**：`http://localhost:1313`

**停止预览**：按 `Ctrl + C`

### 5. 发布文章

**发布前检查**：
- [ ] 文章内容无误
- [ ] 图片正常显示
- [ ] 代码高亮正常
- [ ] `draft: false`（非草稿状态）
- [ ] 标签和分类合理

**提交流程**：

```bash
# 1. 查看修改内容
git status

# 输出示例：
# modified:   content/posts/java-tips.md
# new file:   static/images/2025-01-15/screenshot.png

# 2. 添加所有修改
git add .

# 3. 提交（写清楚改了什么）
git commit -m "Add: Java Spring Boot开发技巧"

# 4. 推送到GitHub
git push origin main
```

**提交信息规范**：

| 前缀 | 用途 | 示例 |
|------|------|------|
| Add: | 新增文章 | `Add: Java性能优化实战` |
| Update: | 更新文章 | `Update: 修正Java性能优化文章中的错误` |
| Fix: | 修复问题 | `Fix: 修复图片链接404问题` |
| Docs: | 文档更新 | `Docs: 更新README` |

### 6. 等待自动部署

**自动化流程**：

```
Git Push (本地)
    ↓
GitHub接收推送
    ↓
触发GitHub Actions
    ↓
安装Hugo → 构建网站 → SSH部署
    ↓
服务器更新文件
    ↓
网站内容更新完成
```

**时间**：约2-3分钟

**查看部署状态**：
1. 访问：`https://github.com/YOUR_USERNAME/my-blog/actions`
2. 点击最新的workflow
3. 查看运行步骤（全部绿色✅表示成功）

### 7. 访问网站

```
网站地址：https://47.93.8.184/
文章地址：https://47.93.8.184/posts/文章名/
```

## 📝 Markdown写作技巧

### 标题层级

```markdown
## 二级标题
### 三级标题
#### 四级标题
```

**建议**：
- 文章从 `##` 开始（一级标题是文章title）
- 保持层级清晰，不要跳级

### 代码块

**行内代码**：

```markdown
使用 `System.out.println()` 输出日志
```

**代码块**（支持语法高亮）：

````markdown
```java
public class Example {
    public static void main(String[] args) {
        System.out.println("Hello, World!");
    }
}
```
````

**支持的语言**：

- `java` - Java
- `python` - Python
- `javascript` / `js` - JavaScript
- `bash` / `shell` - Shell脚本
- `sql` - SQL
- `yaml` - YAML
- `json` - JSON
- `xml` - XML
- `html` - HTML
- `css` - CSS

### 引用块

```markdown
> 这是一段引用
> 可以多行
>
> —— 作者
```

### 列表

**无序列表**：

```markdown
- 第一项
- 第二项
  - 子项1
  - 子项2
```

**有序列表**：

```markdown
1. 第一步
2. 第二步
3. 第三步
```

**任务列表**：

```markdown
- [x] 已完成
- [ ] 未完成
```

### 表格

```markdown
| 列1 | 列2 | 列3 |
|-----|-----|-----|
| 内容1 | 内容2 | 内容3 |
| 内容4 | 内容5 | 内容6 |
```

**对齐**：

```markdown
| 左对齐 | 居中 | 右对齐 |
|:-------|:----:|-------:|
| 内容   | 内容  | 内容   |
```

### 链接

```markdown
# 外部链接
[Google](https://google.com)

# 文章内部链接
[关于页面](/about/)

# 带标题的链接
[Hugo官网](https://gohugo.io "Hugo静态网站生成器")
```

### 强调

```markdown
**粗体文字**
*斜体文字*
***粗斜体***
~~删除线~~
```

## 📂 文件组织建议

### 文章分类

```
content/posts/
├── 2025-01-15-java-performance.md      # 技术文章
├── 2025-01-16-daily-thinking.md        # 每日思考
├── 2025-01-17-supply-chain-design.md   # 业务思考
└── 2025-01-18-book-reading-notes.md    # 读书笔记
```

### 图片组织

```
static/images/
├── common/                    # 通用图片
│   ├── logo.png
│   ├── avatar.jpg
│   └── favicon.ico
├── 2025-01/                  # 按月分类
│   ├── 15-java-perf-01.png
│   ├── 15-java-perf-02.png
│   └── 16-thinking-diagram.png
└── projects/                 # 项目图片
    └── ecommerce-arch.png
```

## 🔧 高级功能

### 草稿管理

**创建草稿**：

```yaml
---
title: "草稿文章"
draft: true    # 草稿状态
---
```

**本地预览草稿**：

```bash
hugo server -D    # -D 显示草稿
```

**发布草稿**：

```yaml
draft: false      # 改为false
```

### 定时发布

设置未来时间，到时间自动发布：

```yaml
---
title: "定时发布的文章"
date: 2025-01-20T10:00:00+08:00    # 未来时间
draft: false
---
```

**本地预览未来文章**：

```bash
hugo server -D -F    # -F 显示未来日期文章
```

### 文章系列

使用 `series` 将相关文章组织在一起：

```yaml
---
title: "Java性能优化（一）：基础知识"
series: ["Java性能优化"]
---
```

```yaml
---
title: "Java性能优化（二）：JVM调优"
series: ["Java性能优化"]
---
```

### 自定义URL

```yaml
---
title: "文章标题"
url: "/custom-url/"    # 自定义URL
---
```

### 隐藏文章

```yaml
---
title: "隐藏的文章"
draft: false
hidden: true    # 不在列表中显示，但可以直接访问
---
```

## 🎨 写作模板

### 技术文章模板

```markdown
---
title: "技术文章标题"
date: 2025-01-15T20:00:00+08:00
draft: false
tags: ["Java", "Spring Boot"]
categories: ["技术"]
description: "简短描述文章内容"
---

## 背景

为什么要研究这个问题...

## 问题分析

遇到了什么问题...

## 解决方案

```java
// 代码示例
```

## 效果

解决问题后的效果...

## 总结

经验总结...

## 参考资料

- [参考链接1](https://example.com)
- [参考链接2](https://example.com)
```

### 每日思考模板

```markdown
---
title: "2025-01-15 每日思考"
date: 2025-01-15T22:00:00+08:00
draft: false
tags: ["思考", "日记"]
categories: ["随笔"]
---

## 今日工作

- 完成了XXX功能
- 解决了XXX问题
- 学习了XXX知识

## 思考

今天的思考和感悟...

## 待办

- [ ] 明天要做XXX
- [ ] 学习XXX
```

### 读书笔记模板

```markdown
---
title: "《书名》读书笔记"
date: 2025-01-15T20:00:00+08:00
draft: false
tags: ["读书笔记", "书名"]
categories: ["学习"]
---

## 书籍信息

- 书名：《XXX》
- 作者：XXX
- 出版社：XXX
- 阅读日期：2025-01-15

## 核心观点

1. 观点一...
2. 观点二...

## 精彩摘录

> 引用内容...

## 个人思考

我的理解和思考...

## 行动计划

- [ ] 实践XXX
- [ ] 学习XXX
```

## 🚀 快捷脚本（可选）

### 创建新文章脚本

创建 `~/bin/newpost.sh`：

```bash
#!/bin/bash
cd /Users/maneng/claude_project/blog

read -p "文章标题: " title
filename=$(echo "$title" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
datestamp=$(date +%Y-%m-%d)
filepath="posts/${datestamp}-${filename}.md"

hugo new "$filepath"
code "content/$filepath"

echo "✅ 文章已创建：$filepath"
```

**使用**：

```bash
chmod +x ~/bin/newpost.sh
echo "alias newpost='~/bin/newpost.sh'" >> ~/.zshrc
source ~/.zshrc

# 创建文章
newpost
```

### 快速发布脚本

创建 `~/bin/publish.sh`：

```bash
#!/bin/bash
cd /Users/maneng/claude_project/blog

git status -s
read -p "提交信息: " message

git add .
git commit -m "$message"
git push origin main

echo "✅ 已推送，等待自动部署..."
```

**使用**：

```bash
chmod +x ~/bin/publish.sh
echo "alias publish='~/bin/publish.sh'" >> ~/.zshrc
source ~/.zshrc

# 快速发布
publish
```

## 📊 内容管理建议

### 标签规范

**技术类**：
- `Java`、`Spring Boot`、`MySQL`、`Redis`
- `架构设计`、`性能优化`、`问题排查`

**业务类**：
- `跨境电商`、`供应链`、`订单系统`

**非技术类**：
- `思考`、`读书笔记`、`随笔`

### 分类规范

- `技术` - 技术文章
- `业务` - 业务思考
- `随笔` - 日常思考
- `学习` - 读书笔记、课程笔记

### 更新旧文章

```bash
# 修改文章
vim content/posts/old-article.md

# 更新日期（可选）
# lastmod: 2025-01-15T20:00:00+08:00

# 提交
git add .
git commit -m "Update: 更新XXX文章内容"
git push origin main
```

---

**有问题？** 查看 `TROUBLESHOOTING.md` 或 `README.md`
