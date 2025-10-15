# Gitalk评论系统配置指南（私有仓库方案）

## 方案说明

由于主仓库是私有的，无法使用Giscus。Gitalk方案：
- 博客代码仓库：私有（当前仓库）
- 评论存储仓库：公开（新建 `blog-comments` 仓库）

---

## 配置步骤

### Step 1: 创建公开评论仓库

1. 访问 https://github.com/new
2. Repository name: `blog-comments`
3. 选择 **Public**
4. 创建仓库

### Step 2: 注册GitHub OAuth App

1. 访问 https://github.com/settings/developers
2. 点击 **New OAuth App**
3. 填写信息：
   - Application name: `如约数科博客评论`
   - Homepage URL: `https://ruyueshuke.com`
   - Authorization callback URL: `https://ruyueshuke.com/blog/`
4. 点击 **Register application**
5. 复制 **Client ID** 和 **Client Secret**

### Step 3: 修改评论模板

```html
<!-- layouts/partials/comments.html -->
{{- if .Site.Params.gitalk.enable -}}
<div id="gitalk-container"></div>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/gitalk@1/dist/gitalk.css">
<script src="https://cdn.jsdelivr.net/npm/gitalk@1/dist/gitalk.min.js"></script>
<script>
  const gitalk = new Gitalk({
    clientID: '{{ .Site.Params.gitalk.clientID }}',
    clientSecret: '{{ .Site.Params.gitalk.clientSecret }}',
    repo: '{{ .Site.Params.gitalk.repo }}',
    owner: '{{ .Site.Params.gitalk.owner }}',
    admin: ['{{ .Site.Params.gitalk.owner }}'],
    id: location.pathname,
    distractionFreeMode: false
  })
  gitalk.render('gitalk-container')
</script>
{{- end -}}
```

### Step 4: 配置config.toml

```toml
[params.gitalk]
  enable = true
  clientID = "你的Client ID"
  clientSecret = "你的Client Secret"
  repo = "blog-comments"  # 公开评论仓库
  owner = "Maneng"
```

---

## 优缺点

### 优点
- ✅ 博客代码保持私有
- ✅ 评论功能正常
- ✅ GitHub账号登录

### 缺点
- ❌ 需要OAuth配置
- ❌ 首次评论需要初始化Issue
- ❌ Client Secret暴露在前端（安全风险）

---

*建议：如果可能，还是推荐将博客仓库改为公开，使用Giscus更安全。*
