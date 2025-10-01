# 如约数科博客 - 快速上手指南

> 这是最简洁的使用指南，帮你快速开始写作和发布

## 🚀 5分钟快速开始

### 1. 创建新文章（30秒）

```bash
cd /Users/maneng/claude_project/blog
hugo new posts/$(date +%Y-%m-%d)-my-article.md
```

### 2. 编辑文章（根据需要）

打开刚创建的文件，修改内容：

```markdown
---
title: "我的新文章"
date: 2025-10-02T10:00:00+08:00
draft: false                          # 改为false才会发布
tags: ["标签1", "标签2"]
categories: ["分类"]
---

## 标题

文章内容...
```

### 3. 本地预览（可选，1分钟）

```bash
hugo server -D
# 浏览器访问 http://localhost:1313
# 按 Ctrl+C 停止
```

### 4. 发布文章（1分钟）

```bash
git add .
git commit -m "Add: 文章标题"
git push origin main
```

**等待2-3分钟，访问** https://ruyueshuke.com/ **查看新文章！**

---

## 📝 常用操作

### 添加图片

```bash
# 1. 复制图片到目录
cp ~/图片.png static/images/2025-10-02-screenshot.png

# 2. 在Markdown中引用
![图片说明](/images/2025-10-02-screenshot.png)
```

### 使用代码块

```markdown
​```java
public class Hello {
    public static void main(String[] args) {
        System.out.println("Hello!");
    }
}
​```
```

### 修改已发布的文章

```bash
# 1. 编辑文章
vim content/posts/existing-article.md

# 2. 提交并推送
git add .
git commit -m "Update: 更新文章内容"
git push origin main
```

---

## 🎯 Front Matter 常用字段

```yaml
---
title: "文章标题"              # 必填
date: 2025-10-02T10:00:00+08:00  # 必填
draft: false                   # false=发布, true=草稿
tags: ["Java", "技术"]         # 标签
categories: ["后端"]           # 分类
description: "文章简介"        # SEO用
---
```

---

## ⚡ 快捷命令

### 创建今日文章
```bash
hugo new posts/$(date +%Y-%m-%d)-daily-note.md
```

### 查看所有文章
```bash
ls -lth content/posts/
```

### 快速发布
```bash
git add . && git commit -m "Add: $(date +%Y-%m-%d)文章" && git push
```

---

## 🔍 查看部署状态

**GitHub Actions页面**：
https://github.com/Maneng/ruyueshuke-blog/actions

**查看服务器文件**：
```bash
ruyue "ls -lth /usr/share/testpage/ | head"
```

---

## 📞 遇到问题？

1. **图片404**：检查路径是否为 `/images/xxx.png`
2. **文章不显示**：检查 `draft: false`
3. **推送后没更新**：查看GitHub Actions是否有错误

详细故障排查参考：`TROUBLESHOOTING.md`

---

## 🎨 写作建议

### 标题层级
```markdown
# 一级标题（不用，Hugo自动用title）
## 二级标题（章节）
### 三级标题（小节）
```

### 常用格式
```markdown
**粗体**
*斜体*
`行内代码`
[链接文字](https://example.com)
> 引用
- 无序列表
1. 有序列表
```

### 任务列表
```markdown
- [x] 已完成
- [ ] 待完成
```

---

## 📂 文件组织建议

### 图片命名
```
static/images/
├── 2025-10-02-architecture.png      # 好：日期+描述
├── 2025-10-02-code-example.jpg      # 好：语义化
└── IMG_1234.png                      # 差：无意义
```

### 文章命名
```
content/posts/
├── 2025-10-02-java-tips.md          # 好：日期+主题
├── 2025-10-02-daily-thinking.md     # 好：日期+类型
└── article1.md                       # 差：无意义
```

---

## 💡 提示

- ✅ 每次写完文章先本地预览
- ✅ 提交信息写清楚改了什么
- ✅ 图片尽量压缩（<500KB）
- ✅ 代码块指定语言（语法高亮）
- ✅ 善用标签和分类组织文章

---

**博客地址**：https://ruyueshuke.com/
**项目目录**：/Users/maneng/claude_project/blog/
**完整文档**：README.md, USAGE.md, DEPLOYMENT_SUMMARY.md
