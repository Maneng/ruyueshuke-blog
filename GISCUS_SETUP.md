# Giscus评论系统配置指南

## 📋 配置概览

Giscus是一个基于GitHub Discussions的评论系统，完全免费且易于集成。

**当前状态**：
- ✅ 评论模板已创建（`layouts/partials/comments.html`）
- ✅ 基础配置已添加（`config.toml`）
- ⏳ 需要完成最后配置步骤

---

## 🚀 配置步骤

### Step 1: 启用GitHub Discussions

1. 访问仓库页面：https://github.com/Maneng/ruyueshuke-blog
2. 点击 **Settings**（设置）
3. 向下滚动到 **Features** 部分
4. 勾选 **Discussions** 复选框
5. 保存设置

### Step 2: 安装Giscus应用

1. 访问：https://github.com/apps/giscus
2. 点击 **Install**
3. 选择 **Only select repositories**
4. 选择 `Maneng/ruyueshuke-blog` 仓库
5. 点击 **Install**

### Step 3: 获取配置参数

1. 访问：https://giscus.app/zh-CN
2. 在 **仓库** 部分输入：`Maneng/ruyueshuke-blog`
3. 系统会自动验证仓库（需要公开仓库且启用了Discussions）
4. 在 **Discussion 分类** 部分选择：**Announcements**
5. 其他配置保持默认：
   - 页面 ↔️ discussion 映射关系：`pathname`
   - Discussion 分类：`Announcements`
   - 特性：勾选"启用反应"
6. 向下滚动到 **启用 giscus** 部分
7. 复制生成的配置代码中的两个ID：
   - `data-repo-id="xxxxx"` → 复制这个ID
   - `data-category-id="xxxxx"` → 复制这个ID

### Step 4: 更新config.toml

打开 `config.toml`，找到 `[params.giscus]` 部分，替换以下两个值：

```toml
[params.giscus]
  repo = "Maneng/ruyueshuke-blog"
  repoId = "粘贴你的repo-id"           # 从giscus.app复制
  category = "Announcements"
  categoryId = "粘贴你的category-id"   # 从giscus.app复制
  # 其他配置保持不变
```

### Step 5: 本地测试

```bash
# 启动本地服务器
hugo server -D

# 访问任意文章页面，检查页面底部是否显示评论框
# 地址示例：http://localhost:1313/posts/your-post/
```

### Step 6: 部署上线

```bash
git add .
git commit -m "Feature: 启用Giscus评论系统"
git push origin main
```

等待GitHub Actions部署完成（约2-3分钟），然后访问线上文章页面验证。

---

## ⚙️ 配置说明

### 已配置的参数

| 参数 | 值 | 说明 |
|------|------|------|
| repo | Maneng/ruyueshuke-blog | 仓库地址 |
| mapping | pathname | 使用页面路径映射评论 |
| reactionsEnabled | 1 | 启用反应表情（👍👎😄等） |
| inputPosition | bottom | 评论框在底部 |
| theme | preferred_color_scheme | 自动适配亮暗模式 |
| lang | zh-CN | 中文界面 |
| loading | lazy | 懒加载，提升性能 |

### 评论分类建议

- **Announcements**（公告）：推荐用于博客评论（只有仓库维护者可以创建新讨论）
- **General**（一般）：任何人都可以创建讨论
- **Q&A**（问答）：问答形式，可选择最佳答案

---

## 🔧 故障排查

### 问题1：评论框不显示

**可能原因**：
- GitHub Discussions未启用
- Giscus应用未安装
- repoId或categoryId配置错误

**解决方法**：
1. 检查 https://github.com/Maneng/ruyueshuke-blog/discussions 能否访问
2. 重新访问 https://giscus.app/zh-CN 验证配置
3. 检查浏览器控制台是否有错误信息

### 问题2：评论显示异常

**解决方法**：
- 清除浏览器缓存
- 确认仓库是公开的（Private仓库不支持Giscus）

### 问题3：评论显示英文界面

**解决方法**：
- 确认 `config.toml` 中 `lang = "zh-CN"` 配置正确
- 重新构建网站：`hugo --minify`

---

## 📊 评论管理

### 管理评论

所有评论会自动同步到GitHub Discussions：

1. 访问：https://github.com/Maneng/ruyueshuke-blog/discussions
2. 在对应的Discussion中管理评论（删除、编辑、回复等）

### 邮件通知

- GitHub会自动发送评论通知邮件
- 可在GitHub设置中配置通知偏好：https://github.com/settings/notifications

---

## 💡 高级配置

### 自定义样式

如需自定义评论框样式，可在 `layouts/partials/comments.html` 中添加自定义CSS。

### 按文章禁用评论

在文章的Front Matter中添加：

```yaml
---
title: "文章标题"
comments: false  # 禁用评论
---
```

---

## 📚 参考资源

- Giscus官网：https://giscus.app/zh-CN
- Giscus GitHub：https://github.com/giscus/giscus
- Hugo评论文档：https://gohugo.io/content-management/comments/

---

*配置完成后请删除本文件或移至文档目录*
