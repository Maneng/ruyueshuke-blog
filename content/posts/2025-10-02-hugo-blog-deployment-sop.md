---
title: "从零搭建Hugo博客系统：完整实施SOP"
date: 2025-10-02T00:00:00+08:00
draft: false
tags: ["Hugo", "博客搭建", "GitHub Actions", "自动部署", "运维"]
categories: ["技术"]
description: "详细记录从零开始搭建Hugo博客的完整流程，包括本地环境配置、GitHub仓库管理、服务器部署、自动化CI/CD等全流程SOP文档"
---

## 前言

本文档记录了如约数科博客系统的完整搭建过程，从本地开发环境到自动化部署，形成标准化操作流程（SOP），可作为类似项目的参考模板。

**项目成果**：
- 博客地址：https://47.93.8.184/ （域名备案中）
- GitHub仓库：https://github.com/Maneng/ruyueshuke-blog
- 部署方式：Git推送自动触发部署
- 部署时间：2-3分钟自动完成

**技术栈**：
- 静态网站生成器：Hugo v0.150.1
- 主题：PaperMod
- 版本控制：Git + GitHub
- CI/CD：GitHub Actions
- 服务器：阿里云 CentOS
- Web服务器：Nginx 1.20.1
- 传输工具：rsync

---

## 一、需求分析

### 1.1 业务需求

作为一名7年Java后端开发，专注跨境电商和供应链领域，需要一个个人技术博客来：
- 记录技术学习和工作经验
- 整理每日思考和业务洞察
- 构建个人知识体系
- 分享问题解决方案

### 1.2 技术需求

**核心需求**：
1. ✅ Markdown写作，所见即所得
2. ✅ 自动化部署，无需手动操作
3. ✅ 版本控制，内容永不丢失
4. ✅ 代码高亮，支持多语言
5. ✅ 响应式设计，移动端友好
6. ✅ 搜索功能，快速定位内容
7. ✅ 零成本运行（服务器已有）

**扩展需求**：
- RSS订阅
- 标签和分类
- 暗黑模式
- SEO优化

### 1.3 方案选择

对比主流静态网站生成器：

| 工具 | 优势 | 劣势 | 选择原因 |
|------|------|------|----------|
| **Hugo** | 构建极快、单文件部署、主题丰富 | Go模板语法陌生 | ✅ 选中 |
| VuePress | Vue生态、可写组件 | 构建较慢 | - |
| Hexo | 社区大、插件多 | Node依赖复杂 | - |
| Jekyll | GitHub原生支持 | 构建很慢 | - |

**最终选择**：Hugo + PaperMod主题

---

## 二、环境准备

### 2.1 本地环境要求

**操作系统**：macOS（本案例）/ Linux / Windows

**必备工具**：
```bash
# 检查是否已安装
git --version           # Git 2.0+
hugo version           # Hugo 0.120.0+
ssh -V                 # OpenSSH 7.0+
```

### 2.2 服务器环境要求

**服务器信息**：
- 系统：CentOS / Alibaba Cloud Linux
- 配置：1核2G即可（静态网站）
- 带宽：1Mbps起
- SSH访问：root权限或sudo权限

**服务器必备软件**：
```bash
# 登录服务器检查
nginx -v               # Nginx
rsync --version        # rsync（用于文件同步）
```

### 2.3 GitHub账号

- GitHub账号（免费版即可）
- 可创建私有仓库
- 2000分钟/月 GitHub Actions 免费额度

---

## 三、本地Hugo环境搭建

### 3.1 安装Hugo

**macOS安装**：
```bash
# 使用Homebrew安装
brew install hugo

# 验证安装
hugo version
# 输出：hugo v0.150.1+extended+withdeploy darwin/arm64
```

**Linux安装**：
```bash
# Ubuntu/Debian
sudo apt update
sudo apt install hugo

# CentOS/RHEL
sudo yum install hugo
```

**Windows安装**：
```powershell
# 使用Chocolatey
choco install hugo-extended -y

# 或下载二进制文件
# https://github.com/gohugoio/hugo/releases
```

**关键点**：
- 推荐安装 `extended` 版本（支持SCSS）
- 版本建议 >= 0.120.0

### 3.2 创建项目目录

```bash
# 创建项目根目录
mkdir -p ~/projects/my-blog
cd ~/projects/my-blog

# 初始化Git仓库
git init
git branch -M main  # 重命名默认分支为main
```

### 3.3 创建Hugo站点结构

```bash
# 创建必需目录
mkdir -p archetypes content static/images themes layouts

# 创建文章模板
cat > archetypes/default.md << 'EOF'
---
title: "{{ replace .Name "-" " " | title }}"
date: {{ .Date }}
draft: true
tags: []
categories: []
description: ""
---

EOF
```

**目录结构说明**：
```
my-blog/
├── archetypes/       # 文章模板
├── content/          # 内容目录（文章、页面）
│   └── posts/        # 博客文章
├── static/           # 静态资源
│   └── images/       # 图片
├── themes/           # 主题目录
├── layouts/          # 自定义布局
├── config.toml       # Hugo配置文件
└── .gitignore        # Git忽略文件
```

### 3.4 添加PaperMod主题

```bash
# 添加主题作为Git子模块
git submodule add --depth=1 \
  https://github.com/adityatelange/hugo-PaperMod.git \
  themes/PaperMod

# 更新子模块
git submodule update --init --recursive

# 验证主题安装
ls -la themes/PaperMod/
```

**为什么使用Git子模块**：
- ✅ 方便主题更新
- ✅ 不污染项目代码
- ✅ GitHub Actions可自动拉取

### 3.5 创建Hugo配置文件

```bash
cat > config.toml << 'EOF'
baseURL = "https://47.93.8.184/"
# baseURL = "https://yourdomain.com/"  # 域名备案后启用
languageCode = "zh-cn"
title = "如约数科"
theme = "PaperMod"

# 启用Emoji
enableEmoji = true

# 分页
[pagination]
  pagerSize = 10

# 代码高亮
[markup]
  [markup.highlight]
    anchorLineNos = false
    codeFences = true
    guessSyntax = false
    lineNos = false
    lineNumbersInTable = true
    noClasses = true
    style = "monokai"
    tabWidth = 4

[params]
  # 基本信息
  author = "maneng"
  description = "记录技术、思考与成长"
  keywords = ["Java", "后端开发", "跨境电商", "供应链", "技术博客"]

  # 首页信息
  [params.homeInfoParams]
    Title = "欢迎来到如约数科 👋"
    Content = """
Java后端开发 | 跨境电商 | 供应链系统 | 7年经验

这里记录技术学习、工作思考和日常感悟。
    """

  # 显示设置
  ShowReadingTime = true
  ShowCodeCopyButtons = true
  ShowToc = true
  ShowWordCount = true

# 菜单配置
[menu]
  [[menu.main]]
    identifier = "posts"
    name = "📝 文章"
    url = "/posts/"
    weight = 10

  [[menu.main]]
    identifier = "archives"
    name = "📂 归档"
    url = "/archives/"
    weight = 20

  [[menu.main]]
    identifier = "tags"
    name = "🏷️ 标签"
    url = "/tags/"
    weight = 30

  [[menu.main]]
    identifier = "search"
    name = "🔍 搜索"
    url = "/search/"
    weight = 40

  [[menu.main]]
    identifier = "about"
    name = "👤 关于"
    url = "/about/"
    weight = 50

# 输出格式（搜索功能需要JSON）
[outputs]
  home = ["HTML", "RSS", "JSON"]

# 分类法
[taxonomies]
  category = "categories"
  tag = "tags"
  series = "series"
EOF
```

**配置关键点**：
- `baseURL`：必须设置为实际访问地址
- `theme`：必须与themes目录下的主题名一致
- 分页使用新语法：`[pagination]` 而非 `paginate`
- 输出JSON格式支持搜索功能

### 3.6 创建必要页面

**关于页面**：
```bash
cat > content/about.md << 'EOF'
---
title: "关于我"
date: 2025-10-02T00:00:00+08:00
draft: false
showToc: false
---

## 👋 你好

我是一名Java后端开发工程师，有7年的开发经验。

## 💼 专业领域

- **技术栈**：Java、Spring Boot、微服务架构
- **业务领域**：跨境电商、供应链系统
- **工作年限**：7年

## 📝 博客目的

记录技术学习、分享工作经验、整理每日思考。

---

*本博客使用 [Hugo](https://gohugo.io/) 搭建*
EOF
```

**归档页面**：
```bash
cat > content/archives.md << 'EOF'
---
title: "归档"
layout: "archives"
url: "/archives/"
summary: archives
---
EOF
```

**搜索页面**：
```bash
cat > content/search.md << 'EOF'
---
title: "搜索"
layout: "search"
url: "/search/"
summary: search
---
EOF
```

### 3.7 创建第一篇文章

```bash
hugo new posts/my-first-post.md

# 编辑文章内容
cat > content/posts/my-first-post.md << 'EOF'
---
title: "欢迎来到我的博客"
date: 2025-10-02T10:00:00+08:00
draft: false
tags: ["博客", "Hugo"]
categories: ["随笔"]
---

## 前言

这是我的第一篇文章，测试Hugo博客功能。

## 代码示例

```java
public class HelloWorld {
    public static void main(String[] args) {
        System.out.println("Hello, World!");
    }
}
```

## 总结

博客搭建完成！
EOF
```

### 3.8 本地预览测试

```bash
# 启动Hugo开发服务器
hugo server -D

# 输出示例：
# Web Server is available at http://localhost:1313/
```

**浏览器访问**：http://localhost:1313

**检查清单**：
- [ ] 首页正常显示
- [ ] 文章列表正常
- [ ] 文章详情页正常
- [ ] 图片加载正常（如有）
- [ ] 代码高亮正常
- [ ] 菜单导航正常
- [ ] 搜索功能正常
- [ ] 主题切换正常

**常见问题**：

1. **样式错乱**：检查 `baseURL` 配置
2. **主题不生效**：确认 `theme = "PaperMod"` 正确
3. **构建错误**：检查config.toml语法（TOML格式严格）

按 `Ctrl + C` 停止预览。

### 3.9 创建.gitignore

```bash
cat > .gitignore << 'EOF'
# Hugo构建产物
public/
resources/_gen/
.hugo_build.lock

# 操作系统文件
.DS_Store
Thumbs.db

# 编辑器文件
.vscode/
.idea/
*.swp
EOF
```

---

## 四、GitHub仓库配置

### 4.1 创建GitHub仓库

**步骤**：
1. 访问 https://github.com/new
2. 填写信息：
   - Repository name: `my-blog`（或自定义）
   - Description: `我的个人博客`
   - 类型：**Private**（私有）
   - ❌ 不要勾选任何初始化选项
3. 点击 **Create repository**
4. 复制仓库URL

### 4.2 推送本地代码

```bash
# 添加所有文件
git add .

# 首次提交
git commit -m "Initial commit: Hugo blog setup"

# 关联远程仓库（替换为你的仓库URL）
git remote add origin git@github.com:YOUR_USERNAME/my-blog.git

# 推送到GitHub
git push -u origin main
```

**验证**：访问GitHub仓库页面，确认文件已上传。

**关键点**：
- 使用SSH方式（需要配置SSH Key）
- 或使用HTTPS方式（需要输入用户名密码）
- 确保 `.gitignore` 生效，`public/` 目录不会被提交

---

## 五、服务器环境配置

### 5.1 连接服务器

```bash
# 使用SSH连接（替换为你的服务器信息）
ssh root@47.93.8.184

# 或配置快捷命令
echo "alias myserver='ssh root@47.93.8.184'" >> ~/.zshrc
source ~/.zshrc

# 使用快捷命令连接
myserver
```

### 5.2 检查现有配置

```bash
# 检查Nginx
nginx -v

# 检查网站目录
ls -la /var/www/
ls -la /usr/share/nginx/html/

# 检查Nginx配置
ls -la /etc/nginx/conf.d/
ls -la /etc/nginx/sites-available/

# 检查SSL证书
ls -la /etc/nginx/ssl/
```

**本案例情况**：
- Nginx已安装：v1.20.1
- 已有网站目录：`/usr/share/testpage/`
- SSL证书已配置
- 配置文件：`/etc/nginx/conf.d/ruyueshuke.conf`

### 5.3 安装rsync（如未安装）

```bash
# CentOS/AlmaLinux
yum install rsync -y

# Ubuntu/Debian
apt install rsync -y

# 验证安装
rsync --version
```

**rsync作用**：用于GitHub Actions部署时同步文件到服务器。

### 5.4 配置或确认Nginx

**检查现有配置**：
```bash
cat /etc/nginx/conf.d/ruyueshuke.conf
```

**关键配置项**：
```nginx
server {
    listen       443 ssl http2;
    server_name  47.93.8.184 ruyueshuke.com www.ruyueshuke.com;
    root         /usr/share/testpage;      # 部署目录
    index        index.html;

    # SSL证书
    ssl_certificate      /etc/nginx/ssl/ruyueshuke.com.cer;
    ssl_certificate_key  /etc/nginx/ssl/ruyueshuke.com.key;

    location / {
        # nginx自动查找index.html
    }
}
```

**测试配置**：
```bash
nginx -t
```

**重载Nginx**：
```bash
systemctl reload nginx
```

### 5.5 确认部署目录权限

```bash
# 检查目录权限
ls -la /usr/share/testpage/

# 如果权限不对，修改
chown -R root:root /usr/share/testpage/
chmod -R 755 /usr/share/testpage/
```

---

## 六、GitHub Actions自动部署配置

### 6.1 生成SSH密钥对

**在本地执行**：
```bash
# 生成专用部署密钥
ssh-keygen -t ed25519 \
  -C "github-actions-deploy" \
  -f ~/.ssh/blog_deploy_key \
  -N ""

# 查看公钥（稍后添加到服务器）
cat ~/.ssh/blog_deploy_key.pub

# 查看私钥（稍后添加到GitHub Secrets）
cat ~/.ssh/blog_deploy_key
```

**密钥说明**：
- `ed25519`：现代加密算法，比RSA更安全更快
- `-N ""`：不设置密码（自动化需要）
- 私钥：GitHub Actions使用
- 公钥：服务器授权

### 6.2 将公钥添加到服务器

```bash
# 复制公钥内容
cat ~/.ssh/blog_deploy_key.pub

# 登录服务器
ssh root@47.93.8.184

# 添加公钥到authorized_keys
mkdir -p ~/.ssh
chmod 700 ~/.ssh
echo "粘贴公钥内容" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# 退出服务器
exit
```

**测试SSH密钥连接**：
```bash
ssh -i ~/.ssh/blog_deploy_key root@47.93.8.184 "echo 'SSH连接成功'"
```

应该输出：`SSH连接成功`

### 6.3 配置GitHub Secrets

**步骤**：
1. 访问：`https://github.com/YOUR_USERNAME/my-blog/settings/secrets/actions`
2. 点击 **New repository secret**
3. 依次添加3个Secrets

**Secret 1：SSH_PRIVATE_KEY**
```bash
# Name: SSH_PRIVATE_KEY
# Value: 完整的私钥内容

# 获取私钥内容
cat ~/.ssh/blog_deploy_key
# 复制从 -----BEGIN OPENSSH PRIVATE KEY-----
# 到 -----END OPENSSH PRIVATE KEY----- 的全部内容
```

**Secret 2：SERVER_HOST**
```
Name: SERVER_HOST
Value: 47.93.8.184
```

**Secret 3：SERVER_USER**
```
Name: SERVER_USER
Value: root
```

**验证**：确认3个Secrets都已添加成功。

### 6.4 创建GitHub Actions Workflow

```bash
# 创建workflow目录
mkdir -p .github/workflows

# 创建部署workflow
cat > .github/workflows/deploy.yml << 'EOF'
name: Deploy Hugo Blog

on:
  push:
    branches:
      - main  # main分支有push时触发

  # 允许手动触发
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      # 步骤1：检出代码
      - name: 📥 Checkout repository
        uses: actions/checkout@v4
        with:
          submodules: true  # 拉取主题子模块
          fetch-depth: 0    # 获取完整历史

      # 步骤2：安装Hugo
      - name: 🔧 Setup Hugo
        uses: peaceiris/actions-hugo@v2
        with:
          hugo-version: 'latest'
          extended: true

      # 步骤3：构建网站
      - name: 🏗️ Build website
        run: hugo --minify

      # 步骤4：显示构建信息
      - name: 📊 Show build info
        run: |
          echo "构建完成！"
          echo "生成文件列表："
          ls -lah public/

      # 步骤5：部署到服务器
      - name: 🚀 Deploy to server
        uses: easingthemes/ssh-deploy@main
        with:
          SSH_PRIVATE_KEY: ${{ secrets.SSH_PRIVATE_KEY }}
          REMOTE_HOST: ${{ secrets.SERVER_HOST }}
          REMOTE_USER: ${{ secrets.SERVER_USER }}
          SOURCE: "public/"
          TARGET: "/usr/share/testpage/"
          ARGS: "-avzr --delete --exclude='.well-known'"
          SCRIPT_BEFORE: |
            echo "开始部署到服务器"
            echo "服务器用户: $(whoami)"
            echo "目标目录: /usr/share/testpage/"
          SCRIPT_AFTER: |
            echo "部署完成！"
            ls -lth /usr/share/testpage/ | head -10
            echo "网站地址: https://47.93.8.184/"

      # 步骤6：通知部署结果
      - name: ✅ Deployment successful
        if: success()
        run: |
          echo "🎉 部署成功！"
          echo "访问地址: https://47.93.8.184/"

      - name: ❌ Deployment failed
        if: failure()
        run: |
          echo "部署失败，请检查日志"
EOF
```

**Workflow说明**：

| 配置项 | 说明 |
|--------|------|
| `on.push.branches` | 触发条件：推送到main分支 |
| `checkout@v4` | 检出代码，包含子模块 |
| `actions-hugo@v2` | 安装Hugo环境 |
| `hugo --minify` | 构建并压缩网站 |
| `ssh-deploy@main` | SSH部署到服务器 |
| `--exclude='.well-known'` | 排除证书验证目录 |

### 6.5 提交Workflow并触发部署

```bash
# 添加workflow文件
git add .github/workflows/deploy.yml

# 提交
git commit -m "Add: GitHub Actions自动部署workflow"

# 推送（触发首次部署）
git push origin main
```

### 6.6 监控部署过程

**查看部署日志**：
1. 访问：`https://github.com/YOUR_USERNAME/my-blog/actions`
2. 点击最新的workflow运行
3. 查看每个步骤的详细日志

**部署流程**：
```
触发 (0秒)
  ↓
Checkout代码 (10秒)
  ↓
安装Hugo (20秒)
  ↓
构建网站 (30秒)
  ↓
SSH连接服务器 (10秒)
  ↓
rsync同步文件 (30秒)
  ↓
部署完成 (100秒 ≈ 2分钟)
```

**成功标志**：
- ✅ 所有步骤显示绿色对勾
- ✅ 最后显示"Deployment successful"
- ✅ 访问网站看到最新内容

**常见错误**：

| 错误 | 原因 | 解决方案 |
|------|------|----------|
| `Permission denied` | SSH密钥错误 | 检查Secrets配置 |
| `rsync: command not found` | 服务器未安装rsync | 服务器上安装rsync |
| `Hugo build failed` | 配置语法错误 | 检查config.toml |
| `Connection refused` | 服务器防火墙 | 开放SSH端口(22) |

---

## 七、验证和测试

### 7.1 验证网站访问

**浏览器访问**：https://47.93.8.184/

**检查清单**：
- [ ] 首页正常显示
- [ ] 标题显示"如约数科"
- [ ] 文章列表正常
- [ ] 点击文章可以查看详情
- [ ] 代码高亮正常
- [ ] 图片加载正常
- [ ] 菜单导航正常
- [ ] 搜索功能正常
- [ ] 亮色/暗色主题切换正常
- [ ] HTTPS证书正常

### 7.2 测试完整工作流

**创建新文章**：
```bash
cd ~/projects/my-blog

# 创建文章
hugo new posts/test-deployment.md

# 编辑文章
cat > content/posts/test-deployment.md << 'EOF'
---
title: "测试自动部署"
date: 2025-10-02T12:00:00+08:00
draft: false
tags: ["测试"]
categories: ["技术"]
---

## 测试内容

这是一篇测试文章，验证自动部署功能。

当前时间：2025-10-02 12:00:00
EOF
```

**本地预览**：
```bash
hugo server -D
# 访问 http://localhost:1313
# 确认文章正常显示
```

**发布文章**：
```bash
# 提交并推送
git add .
git commit -m "Add: 测试自动部署文章"
git push origin main
```

**等待2-3分钟**，然后：
1. 访问GitHub Actions查看部署进度
2. 部署完成后访问网站
3. 确认新文章已经出现

### 7.3 测试图片上传

**添加图片**：
```bash
# 复制图片到static/images
cp ~/some-image.png static/images/test-image.png

# 在文章中引用
cat >> content/posts/test-deployment.md << 'EOF'

## 图片测试

![测试图片](/images/test-image.png)
EOF
```

**提交推送**：
```bash
git add .
git commit -m "Add: 测试图片上传"
git push origin main
```

**验证**：访问文章，确认图片正常显示。

### 7.4 性能测试

**测试指标**：
```bash
# 首页加载时间
curl -o /dev/null -s -w 'Total: %{time_total}s\n' https://47.93.8.184/

# 测试Gzip压缩
curl -H "Accept-Encoding: gzip" -I https://47.93.8.184/

# 测试缓存
curl -I https://47.93.8.184/images/test-image.png
```

**预期结果**：
- 首页加载 < 2秒
- Gzip压缩已启用
- 静态资源有缓存头

---

## 八、日常使用流程

### 8.1 写作流程

```bash
# 1. 进入项目目录
cd ~/projects/my-blog

# 2. 创建新文章
hugo new posts/$(date +%Y-%m-%d)-article-title.md

# 3. 编辑文章
vim content/posts/2025-10-02-article-title.md

# 4. 本地预览（可选）
hugo server -D
# 浏览器访问 http://localhost:1313

# 5. 提交并发布
git add .
git commit -m "Add: 文章标题"
git push origin main

# 6. 等待2-3分钟，访问网站查看
```

### 8.2 文章模板

```markdown
---
title: "文章标题"
date: 2025-10-02T10:00:00+08:00
draft: false
tags: ["标签1", "标签2"]
categories: ["分类"]
description: "文章简介，用于SEO"
---

## 前言

文章背景介绍...

## 正文

详细内容...

## 代码示例

```java
public class Example {
    // 代码
}
```

## 总结

总结内容...

## 参考资料

- [链接1](https://example.com)
```

### 8.3 图片管理

**目录结构**：
```
static/images/
├── 2025-10-02/              # 按日期分类
│   ├── screenshot-01.png
│   └── diagram-01.jpg
└── common/                  # 通用图片
    ├── logo.png
    └── avatar.jpg
```

**添加图片**：
```bash
# 复制图片
cp ~/screenshot.png static/images/2025-10-02/

# 在Markdown中引用
![图片描述](/images/2025-10-02/screenshot.png)
```

**图片优化建议**：
- 压缩图片（< 500KB）
- 使用JPG（照片）或PNG（图标）
- 语义化命名：`java-performance-chart.png`

### 8.4 更新已发布文章

```bash
# 1. 编辑文章
vim content/posts/existing-article.md

# 2. 提交更新
git add .
git commit -m "Update: 更新文章内容"
git push origin main
```

### 8.5 域名切换（备案完成后）

**修改配置**：
```bash
# 编辑config.toml
vim config.toml

# 修改baseURL
baseURL = "https://yourdomain.com/"  # 启用域名
# baseURL = "https://47.93.8.184/"  # 注释IP

# 提交推送
git add config.toml
git commit -m "Update: 切换到域名访问"
git push origin main
```

**Nginx配置已支持域名**，无需修改。

---

## 九、故障排查

### 9.1 本地问题

**问题1：Hugo构建失败**
```bash
# 症状：hugo命令报错
# 解决：检查config.toml语法

hugo --minify --verbose

# 常见错误：
# - TOML语法错误（缩进、引号）
# - 主题路径错误
# - Front Matter格式错误
```

**问题2：主题不生效**
```bash
# 症状：网站无样式
# 解决：

# 1. 检查主题是否存在
ls themes/PaperMod/

# 2. 更新子模块
git submodule update --init --recursive

# 3. 检查config.toml
grep "theme" config.toml
# 应该是：theme = "PaperMod"
```

**问题3：图片404**
```bash
# 症状：图片不显示
# 原因：路径错误

# 正确路径：
# 文件位置：static/images/test.png
# 引用路径：![](/images/test.png)

# 错误路径：
# ![](../images/test.png)
# ![](static/images/test.png)
```

### 9.2 部署问题

**问题4：GitHub Actions失败**

**查看日志**：
```
GitHub仓库 → Actions → 点击失败的workflow → 查看错误步骤
```

**常见错误**：

| 错误信息 | 原因 | 解决方案 |
|---------|------|----------|
| `submodule error` | 主题子模块问题 | 检查.gitmodules文件 |
| `Hugo build error` | 配置错误 | 本地测试 `hugo --minify` |
| `Permission denied` | SSH密钥问题 | 重新配置Secrets |
| `rsync: command not found` | 服务器缺少rsync | 服务器安装rsync |

**问题5：部署成功但网站没更新**

**排查步骤**：
```bash
# 1. 确认GitHub Actions成功
# 查看Actions页面，全部绿色✅

# 2. 检查服务器文件
ssh root@47.93.8.184 "ls -lth /usr/share/testpage/ | head"

# 3. 检查文件时间戳
# 应该是最近的时间

# 4. 清除浏览器缓存
# Chrome: Cmd/Ctrl + Shift + R

# 5. 检查Nginx配置
ssh root@47.93.8.184 "nginx -t"
```

**问题6：SSH连接超时**

```bash
# 症状：GitHub Actions卡在SSH步骤
# 原因：防火墙、网络问题

# 解决：
# 1. 检查服务器SSH端口是否开放
ssh root@47.93.8.184 "netstat -tlnp | grep 22"

# 2. 检查防火墙规则
ssh root@47.93.8.184 "firewall-cmd --list-all"

# 3. 本地测试SSH连接
ssh -i ~/.ssh/blog_deploy_key root@47.93.8.184 "echo test"
```

### 9.3 服务器问题

**问题7：Nginx 403 Forbidden**

```bash
# 症状：访问网站显示403
# 原因：文件权限问题

# 解决：
ssh root@47.93.8.184

# 检查目录权限
ls -la /usr/share/testpage/

# 修复权限
chown -R root:root /usr/share/testpage/
chmod -R 755 /usr/share/testpage/

# 检查Nginx错误日志
tail -50 /var/log/nginx/blog_error.log

# 重启Nginx
systemctl reload nginx
```

**问题8：SSL证书问题**

```bash
# 症状：HTTPS不可访问或证书警告

# 检查证书文件
ls -la /etc/nginx/ssl/

# 检查证书有效期
openssl x509 -in /etc/nginx/ssl/ruyueshuke.com.cer -noout -dates

# 续期证书（使用acme.sh或certbot）
# 具体操作取决于证书获取方式
```

---

## 十、优化建议

### 10.1 性能优化

**图片优化**：
```bash
# 使用ImageMagick压缩
brew install imagemagick
mogrify -resize 1200x -quality 85 static/images/*.{jpg,png}

# 或使用在线工具：
# - TinyPNG: https://tinypng.com/
# - Squoosh: https://squoosh.app/
```

**缓存优化**：
```nginx
# Nginx配置（已包含）
location ~* \.(jpg|jpeg|png|gif|css|js)$ {
    expires 30d;
    add_header Cache-Control "public, immutable";
}
```

**Gzip压缩**：
```nginx
# Nginx配置（已包含）
gzip on;
gzip_types text/plain text/css application/json application/javascript;
```

### 10.2 SEO优化

**Sitemap**：
```bash
# Hugo自动生成sitemap.xml
# 访问：https://47.93.8.184/sitemap.xml
```

**robots.txt**：
```bash
cat > static/robots.txt << 'EOF'
User-agent: *
Allow: /
Sitemap: https://47.93.8.184/sitemap.xml
EOF
```

**Meta标签**：
```toml
# config.toml中配置
[params]
  description = "记录技术、思考与成长"
  keywords = ["Java", "后端开发", "技术博客"]
```

### 10.3 功能扩展

**添加评论系统（utterances）**：
1. 创建GitHub仓库（如blog-comments）
2. 启用Issues功能
3. 安装utterances app
4. 在config.toml中配置

**添加访问统计（Google Analytics）**：
```toml
[params]
  googleAnalytics = "G-XXXXXXXXXX"
```

**添加RSS订阅**：
```
# Hugo自动生成
# 订阅地址：https://47.93.8.184/index.xml
```

---

## 十一、成本分析

### 11.1 初始成本

| 项目 | 费用 | 备注 |
|------|------|------|
| Hugo | ¥0 | 开源免费 |
| GitHub | ¥0 | 私有仓库免费 |
| GitHub Actions | ¥0 | 2000分钟/月免费 |
| 服务器 | 已有 | 阿里云服务器 |
| 域名 | 已有 | 已购买 |
| SSL证书 | ¥0 | Let's Encrypt免费 |
| **总计** | **¥0** | - |

### 11.2 运营成本

| 项目 | 月费用 | 说明 |
|------|--------|------|
| GitHub Actions | ¥0 | 每月构建次数<100次 |
| 服务器带宽 | 已包含 | 静态网站流量小 |
| 图片存储 | ¥0 | 存储在Git（<1GB） |
| **月成本** | **¥0** | - |

### 11.3 时间成本

| 任务 | 时间 | 频率 |
|------|------|------|
| 初次搭建 | 2-3小时 | 一次性 |
| 写一篇文章 | 30-60分钟 | 按需 |
| 发布文章 | 1分钟 | 每次写作 |
| 等待部署 | 2-3分钟 | 自动 |
| 系统维护 | 5分钟 | 每月 |

---

## 十二、总结

### 12.1 项目成果

**已实现功能**：
- ✅ Hugo博客系统搭建
- ✅ PaperMod主题集成
- ✅ GitHub版本控制
- ✅ GitHub Actions自动部署
- ✅ HTTPS安全访问
- ✅ 响应式设计
- ✅ 搜索功能
- ✅ 代码高亮
- ✅ RSS订阅

**技术指标**：
- 构建速度：< 1秒（文章<100篇）
- 部署时间：2-3分钟自动完成
- 首页加载：< 2秒
- 运营成本：¥0/月

### 12.2 工作流程

```
写作 → Git推送 → 自动构建 → 自动部署 → 访问更新
 ↓       ↓          ↓           ↓         ↓
本地   GitHub   Actions      rsync    网站生效
(2分)   (即时)   (1.5分)     (30秒)    (即时)
```

### 12.3 经验总结

**关键成功因素**：
1. ✅ 选对工具：Hugo构建快、主题丰富
2. ✅ 自动化：GitHub Actions减少手动操作
3. ✅ 简单化：静态网站无数据库、易维护
4. ✅ 版本化：Git管理，内容永不丢失

**常见坑点**：
1. ❌ config.toml语法错误（TOML格式严格）
2. ❌ baseURL配置错误（必须与实际地址一致）
3. ❌ 服务器缺少rsync（部署失败）
4. ❌ SSH密钥权限错误（部署连接失败）

**最佳实践**：
1. ✅ 本地先预览再推送
2. ✅ 提交信息写清楚
3. ✅ 图片压缩后再上传
4. ✅ 定期备份GitHub仓库
5. ✅ 监控GitHub Actions状态

### 12.4 后续计划

**短期（1个月内）**：
- [ ] 写10篇技术文章
- [ ] 添加评论系统
- [ ] 添加访问统计
- [ ] 优化SEO

**中期（3个月内）**：
- [ ] 自定义主题样式
- [ ] 添加友情链接
- [ ] 创建文章系列
- [ ] 优化图片加载

**长期（1年内）**：
- [ ] 图片迁移到OSS
- [ ] 启用CDN加速
- [ ] 多语言支持
- [ ] 自定义域名邮箱

---

## 附录

### A. 常用命令速查

| 任务 | 命令 |
|------|------|
| 创建文章 | `hugo new posts/article.md` |
| 本地预览 | `hugo server -D` |
| 构建网站 | `hugo --minify` |
| Git提交 | `git add . && git commit -m "message"` |
| Git推送 | `git push origin main` |
| 连接服务器 | `ssh root@47.93.8.184` |
| 查看部署 | GitHub Actions页面 |

### B. 重要链接

- **Hugo官方文档**：https://gohugo.io/documentation/
- **PaperMod主题**：https://github.com/adityatelange/hugo-PaperMod
- **GitHub Actions**：https://docs.github.com/en/actions
- **Markdown指南**：https://www.markdownguide.org/

### C. 配置文件模板

所有配置文件模板可在项目目录中找到：
- `config.toml` - Hugo配置
- `.github/workflows/deploy.yml` - 部署workflow
- `.gitignore` - Git忽略规则

---

**文档版本**：v1.0
**创建日期**：2025-10-02
**作者**：maneng
**博客地址**：https://47.93.8.184/

---

## 后记

本文档记录了完整的Hugo博客搭建过程，从需求分析到最终部署，每一步都经过实际验证。希望这份SOP能帮助到需要搭建类似系统的开发者。

如有问题或建议，欢迎通过博客留言交流。

**开始你的写作之旅吧！** 📝✨
