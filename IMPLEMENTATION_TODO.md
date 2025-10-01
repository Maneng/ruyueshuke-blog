# Hugo博客搭建实施清单

> 项目目标：搭建基于Hugo的个人博客，实现本地写作 → GitHub推送 → 自动部署的完整流程
>
> 服务器IP：https://47.93.8.184/
>
> 当前目录：/Users/maneng/claude_project/blog

---

## 📋 总体进度概览

- [ ] 阶段1：本地Hugo环境搭建
- [ ] 阶段2：GitHub仓库配置
- [ ] 阶段3：服务器环境配置
- [ ] 阶段4：GitHub Actions自动部署配置
- [ ] 阶段5：完整流程测试验证
- [ ] 阶段6：编写使用文档

---

## 🚀 阶段1：本地Hugo环境搭建

### 1.1 安装Hugo
- [ ] 检查Hugo是否已安装 (`hugo version`)
- [ ] 如未安装，使用brew安装 (`brew install hugo`)
- [ ] 验证安装成功，版本号 >= 0.120.0

**执行命令**：
```bash
hugo version
# 如果没有安装：
brew install hugo
```

**完成标志**：显示Hugo版本号

**执行时间**：
**执行结果**：
**备注**：

---

### 1.2 初始化Hugo站点
- [ ] 在当前目录创建Hugo站点结构
- [ ] 验证目录结构是否正确

**执行命令**：
```bash
# 当前已在 /Users/maneng/claude_project/blog
# 如果目录为空，执行：
hugo new site . --force

# 验证目录结构
ls -la
```

**完成标志**：看到 archetypes/, content/, layouts/, static/, themes/ 等目录

**执行时间**：
**执行结果**：
**备注**：

---

### 1.3 初始化Git仓库并添加主题
- [ ] 初始化Git仓库
- [ ] 添加PaperMod主题为子模块
- [ ] 更新子模块

**执行命令**：
```bash
# 初始化Git
git init

# 添加主题
git submodule add --depth=1 https://github.com/adityatelange/hugo-PaperMod.git themes/PaperMod

# 更新子模块
git submodule update --init --recursive
```

**完成标志**：themes/PaperMod 目录存在且有内容

**执行时间**：
**执行结果**：
**备注**：

---

### 1.4 创建Hugo配置文件
- [ ] 创建 config.toml 配置文件
- [ ] 配置基本信息（站点标题、作者、菜单等）
- [ ] 设置主题为 PaperMod
- [ ] 配置baseURL为服务器IP

**执行命令**：
```bash
# 配置文件已生成为 config.toml
cat config.toml
```

**完成标志**：config.toml 文件存在且内容正确

**执行时间**：
**执行结果**：
**备注**：

---

### 1.5 创建第一篇测试文章
- [ ] 创建 posts 目录下的第一篇文章
- [ ] 编写测试内容（包含代码、标题、文本）
- [ ] 设置 draft: false

**执行命令**：
```bash
hugo new posts/my-first-post.md
# 编辑文章内容
```

**完成标志**：content/posts/my-first-post.md 文件存在

**执行时间**：
**执行结果**：
**备注**：

---

### 1.6 准备测试图片
- [ ] 创建 static/images 目录
- [ ] 添加一张测试图片
- [ ] 在文章中引用图片

**执行命令**：
```bash
mkdir -p static/images
# 复制测试图片到 static/images/test.png
```

**完成标志**：static/images/test.png 存在

**执行时间**：
**执行结果**：
**备注**：

---

### 1.7 本地预览测试
- [ ] 启动Hugo本地服务器
- [ ] 浏览器访问 http://localhost:1313
- [ ] 验证首页、文章、图片、代码高亮是否正常
- [ ] 停止服务器

**执行命令**：
```bash
hugo server -D
# 浏览器访问 http://localhost:1313
# Ctrl+C 停止
```

**完成标志**：本地网站正常显示

**执行时间**：
**执行结果**：
**备注**：

---

## 🐙 阶段2：GitHub仓库配置

### 2.1 创建GitHub仓库
- [ ] 在GitHub创建新仓库 (名称: my-blog)
- [ ] 设置为Private私有仓库
- [ ] 不要初始化任何文件（README、.gitignore等）

**操作步骤**：
1. 访问 https://github.com/new
2. 仓库名：my-blog
3. 类型：Private
4. 点击 Create repository

**完成标志**：GitHub仓库创建成功，复制仓库URL

**执行时间**：
**仓库URL**：
**备注**：

---

### 2.2 创建.gitignore文件
- [ ] 创建.gitignore文件
- [ ] 添加Hugo构建产物和系统文件

**执行命令**：
```bash
# .gitignore 文件已生成
cat .gitignore
```

**完成标志**：.gitignore 文件存在

**执行时间**：
**执行结果**：
**备注**：

---

### 2.3 本地仓库关联远程仓库
- [ ] 添加所有文件到Git
- [ ] 创建首次提交
- [ ] 关联GitHub远程仓库
- [ ] 推送到main分支

**执行命令**：
```bash
git add .
git commit -m "Initial commit: Hugo blog setup"
git remote add origin https://github.com/YOUR_USERNAME/my-blog.git
git branch -M main
git push -u origin main
```

**完成标志**：GitHub仓库中可以看到所有文件

**执行时间**：
**执行结果**：
**备注**：需要替换YOUR_USERNAME

---

## 🖥️ 阶段3：服务器环境配置

### 3.1 连接服务器并创建部署目录
- [ ] 使用 ruyue 命令连接服务器
- [ ] 创建 /var/www/blog 目录
- [ ] 修改目录所有者为当前用户
- [ ] 验证权限

**执行命令**：
```bash
ruyue
sudo mkdir -p /var/www/blog
sudo chown -R $USER:$USER /var/www/blog
ls -la /var/www/ | grep blog
exit
```

**完成标志**：目录存在且权限正确

**执行时间**：
**执行结果**：
**服务器用户名**：
**备注**：

---

### 3.2 配置Nginx站点
- [ ] 创建Nginx配置文件 /etc/nginx/sites-available/blog
- [ ] 配置HTTP和HTTPS监听
- [ ] 设置网站根目录为 /var/www/blog
- [ ] 配置静态资源缓存和Gzip压缩

**执行命令**：
```bash
ruyue
sudo vim /etc/nginx/sites-available/blog
# 复制 nginx-blog.conf 内容
exit
```

**完成标志**：配置文件创建成功

**执行时间**：
**执行结果**：
**备注**：

---

### 3.3 启用Nginx站点配置
- [ ] 创建软链接到 sites-enabled
- [ ] 删除默认配置（如果存在）
- [ ] 测试Nginx配置
- [ ] 重载Nginx

**执行命令**：
```bash
ruyue
sudo ln -sf /etc/nginx/sites-available/blog /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
exit
```

**完成标志**：nginx -t 返回成功，Nginx重载无错误

**执行时间**：
**执行结果**：
**备注**：

---

### 3.4 测试服务器访问
- [ ] 创建测试HTML文件
- [ ] 浏览器访问 https://47.93.8.184
- [ ] 验证HTTPS证书
- [ ] 删除测试文件

**执行命令**：
```bash
ruyue
echo "<h1>Hello from my blog!</h1>" > /var/www/blog/index.html
# 浏览器访问测试
rm /var/www/blog/index.html
exit
```

**完成标志**：浏览器能正常访问并显示测试页面

**执行时间**：
**执行结果**：
**备注**：

---

## 🔐 阶段4：GitHub Actions自动部署配置

### 4.1 生成SSH部署密钥对
- [ ] 在本地生成专用SSH密钥对
- [ ] 密钥名称：blog_deploy_key
- [ ] 密钥类型：ed25519

**执行命令**：
```bash
ssh-keygen -t ed25519 -C "github-actions-deploy" -f ~/.ssh/blog_deploy_key
# 不设置密码，直接回车
ls -la ~/.ssh/blog_deploy_key*
```

**完成标志**：生成 blog_deploy_key 和 blog_deploy_key.pub 两个文件

**执行时间**：
**执行结果**：
**备注**：

---

### 4.2 将公钥添加到服务器
- [ ] 查看公钥内容
- [ ] 连接服务器
- [ ] 创建 .ssh 目录（如不存在）
- [ ] 将公钥追加到 authorized_keys
- [ ] 设置正确权限

**执行命令**：
```bash
cat ~/.ssh/blog_deploy_key.pub
# 复制输出内容

ruyue
mkdir -p ~/.ssh
chmod 700 ~/.ssh
cat >> ~/.ssh/authorized_keys << 'EOF'
# 粘贴公钥内容
EOF
chmod 600 ~/.ssh/authorized_keys
exit
```

**完成标志**：公钥成功添加到服务器

**执行时间**：
**执行结果**：
**备注**：

---

### 4.3 测试SSH密钥连接
- [ ] 使用私钥测试SSH连接
- [ ] 验证免密登录成功
- [ ] 记录服务器用户名和IP

**执行命令**：
```bash
ssh -i ~/.ssh/blog_deploy_key 用户名@47.93.8.184 "echo 'SSH connection successful!'"
```

**完成标志**：显示 "SSH connection successful!"

**执行时间**：
**执行结果**：
**服务器用户名**：
**备注**：

---

### 4.4 配置GitHub Secrets
- [ ] 打开GitHub仓库 Settings → Secrets and variables → Actions
- [ ] 添加 SSH_PRIVATE_KEY (私钥完整内容)
- [ ] 添加 SERVER_HOST (47.93.8.184)
- [ ] 添加 SERVER_USER (服务器用户名)

**操作步骤**：
1. 复制私钥：`cat ~/.ssh/blog_deploy_key`
2. GitHub仓库 → Settings → Secrets and variables → Actions
3. New repository secret
4. 添加3个secrets

**完成标志**：3个Secrets全部添加成功

**执行时间**：
**执行结果**：
**备注**：

---

### 4.5 创建GitHub Actions工作流
- [ ] 创建 .github/workflows 目录
- [ ] 创建 deploy.yml 文件
- [ ] 配置构建和部署步骤
- [ ] 提交并推送

**执行命令**：
```bash
mkdir -p .github/workflows
# deploy.yml 文件已生成
cat .github/workflows/deploy.yml
git add .github/workflows/deploy.yml
git commit -m "Add: GitHub Actions自动部署工作流"
git push origin main
```

**完成标志**：工作流文件推送成功

**执行时间**：
**执行结果**：
**备注**：

---

### 4.6 监控首次自动部署
- [ ] 访问GitHub仓库的Actions页面
- [ ] 查看工作流运行状态
- [ ] 检查每个步骤是否成功
- [ ] 查看部署日志

**操作步骤**：
1. GitHub仓库 → Actions 标签
2. 点击最新的workflow运行
3. 查看详细日志

**完成标志**：所有步骤显示绿色✅

**执行时间**：
**执行结果**：
**备注**：

---

## ✅ 阶段5：完整流程测试验证

### 5.1 验证网站访问
- [ ] 浏览器访问 https://47.93.8.184
- [ ] 验证首页正常显示
- [ ] 验证文章列表正常
- [ ] 验证文章详情页正常
- [ ] 验证图片正常加载
- [ ] 验证代码高亮正常

**测试URL**：
- 首页：https://47.93.8.184
- 文章：https://47.93.8.184/posts/my-first-post/
- 图片：https://47.93.8.184/images/test.png

**完成标志**：所有页面正常访问

**执行时间**：
**执行结果**：
**备注**：

---

### 5.2 测试自动部署流程
- [ ] 本地创建新文章
- [ ] 本地预览确认无误
- [ ] Git提交并推送
- [ ] 观察GitHub Actions自动触发
- [ ] 等待部署完成（约2-3分钟）
- [ ] 访问线上网站验证更新

**执行命令**：
```bash
hugo new posts/test-deployment.md
# 编辑文章
hugo server -D
# 确认无误后
git add .
git commit -m "Test: 测试自动部署流程"
git push origin main
```

**完成标志**：新文章出现在线上网站

**执行时间**：
**执行结果**：
**备注**：

---

### 5.3 测试图片上传流程
- [ ] 添加新图片到 static/images
- [ ] 在文章中引用新图片
- [ ] 本地预览图片显示
- [ ] 推送到GitHub
- [ ] 验证线上图片加载

**执行命令**：
```bash
cp ~/some-image.png static/images/deployment-test.png
# 在文章中添加：![测试](/images/deployment-test.png)
git add .
git commit -m "Add: 测试图片上传"
git push origin main
```

**完成标志**：线上图片正常显示

**执行时间**：
**执行结果**：
**备注**：

---

### 5.4 性能和缓存测试
- [ ] 测试首页加载速度
- [ ] 测试静态资源缓存（图片、CSS、JS）
- [ ] 测试Gzip压缩是否生效
- [ ] 测试HTTPS证书

**测试命令**：
```bash
# 测试首页
curl -I https://47.93.8.184

# 测试图片缓存
curl -I https://47.93.8.184/images/test.png

# 测试Gzip
curl -H "Accept-Encoding: gzip" -I https://47.93.8.184
```

**完成标志**：返回正确的缓存头和压缩头

**执行时间**：
**执行结果**：
**备注**：

---

## 📚 阶段6：编写使用文档

### 6.1 创建README文档
- [ ] 创建 README.md
- [ ] 记录项目简介
- [ ] 记录技术栈
- [ ] 记录日常使用流程

**执行命令**：
```bash
# README.md 文件已生成
cat README.md
git add README.md
git commit -m "Docs: 添加README文档"
git push origin main
```

**完成标志**：README.md 文件存在且内容完整

**执行时间**：
**执行结果**：
**备注**：

---

### 6.2 创建日常使用指南
- [ ] 创建 USAGE.md
- [ ] 记录写作流程
- [ ] 记录常见问题解决方案
- [ ] 记录快捷命令

**执行命令**：
```bash
# USAGE.md 文件已生成
cat USAGE.md
```

**完成标志**：USAGE.md 文件存在

**执行时间**：
**执行结果**：
**备注**：

---

### 6.3 创建故障排查文档
- [ ] 创建 TROUBLESHOOTING.md
- [ ] 记录常见错误及解决方案
- [ ] 记录调试命令
- [ ] 记录联系方式和资源链接

**执行命令**：
```bash
# TROUBLESHOOTING.md 文件已生成
cat TROUBLESHOOTING.md
```

**完成标志**：TROUBLESHOOTING.md 文件存在

**执行时间**：
**执行结果**：
**备注**：

---

## 🎉 项目完成检查清单

- [ ] 本地可以正常写作和预览
- [ ] Git推送触发自动部署
- [ ] 服务器可以访问最新内容
- [ ] 图片正常显示
- [ ] HTTPS正常工作
- [ ] 所有文档齐全
- [ ] 了解日常使用流程
- [ ] 了解故障排查方法

---

## 📝 执行日志

### 开始时间：
### 完成时间：
### 总耗时：
### 遇到的问题：
### 解决方案：

---

## 🔖 重要信息速查

| 项目 | 信息 |
|------|------|
| 服务器IP | 47.93.8.184 |
| SSH快捷命令 | ruyue |
| 部署路径 | /var/www/blog |
| 本地预览 | http://localhost:1313 |
| GitHub仓库 | (待填写) |
| Hugo配置 | config.toml |
| Nginx配置 | /etc/nginx/sites-available/blog |
| Actions状态 | https://github.com/USER/my-blog/actions |

---

## 📞 获取帮助

如果遇到问题：
1. 查看 TROUBLESHOOTING.md
2. 检查 GitHub Actions 日志
3. 检查服务器 Nginx 日志：`sudo tail -f /var/log/nginx/blog_error.log`
4. 重新阅读本文档相关章节

---

**文档版本**：v1.0
**最后更新**：2025-01-15
**维护者**：maneng
