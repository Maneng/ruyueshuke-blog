# 故障排查指南

遇到问题？本文档提供常见问题的解决方案。

## 📋 目录

- [部署相关问题](#部署相关问题)
- [图片相关问题](#图片相关问题)
- [样式和显示问题](#样式和显示问题)
- [Git相关问题](#git相关问题)
- [服务器相关问题](#服务器相关问题)
- [调试工具](#调试工具)

---

## 部署相关问题

### ❌ 问题1：推送后网站没有更新

**症状**：
- Git推送成功
- 但访问网站看不到最新内容

**排查步骤**：

**1. 检查GitHub Actions是否成功**

```bash
# 访问Actions页面
https://github.com/YOUR_USERNAME/my-blog/actions
```

查看最新workflow的状态：
- ✅ 全部绿色 = 成功
- ❌ 红色 = 失败
- 🟡 黄色 = 运行中

**2. 查看失败日志**

点击失败的步骤，查看错误信息：

常见错误类型：

| 错误信息 | 原因 | 解决方案 |
|----------|------|----------|
| `Permission denied` | SSH权限问题 | 检查GitHub Secrets配置 |
| `Hugo build failed` | 文章语法错误 | 检查Markdown语法 |
| `submodule error` | 主题拉取失败 | 检查子模块配置 |

**3. 手动触发部署**

```
GitHub仓库 → Actions →
选择 "Deploy Hugo Blog" workflow →
Run workflow → Run workflow
```

**4. 检查服务器文件**

```bash
# 连接服务器
ruyue

# 查看部署目录
ls -lt /var/www/blog/ | head

# 查看最新文件时间
stat /var/www/blog/index.html

# 退出
exit
```

**5. 清除浏览器缓存**

- Chrome：`Cmd + Shift + R`（Mac）或 `Ctrl + Shift + R`（Windows）
- 或使用隐私窗口访问

---

### ❌ 问题2：GitHub Actions一直失败

**症状**：
- 每次推送都失败
- 红色❌状态

**检查清单**：

**1. SSH配置是否正确**

```bash
# 测试SSH连接
ssh -i ~/.ssh/blog_deploy_key 用户名@47.93.8.184 "echo 'Test OK'"

# 应该输出：Test OK
```

如果失败：

```bash
# 检查公钥是否在服务器上
ruyue
cat ~/.ssh/authorized_keys | grep github-actions
exit
```

**2. GitHub Secrets是否正确**

GitHub仓库 → Settings → Secrets and variables → Actions

确认3个Secrets存在：
- `SSH_PRIVATE_KEY`：完整私钥内容（包括BEGIN和END行）
- `SERVER_HOST`：`47.93.8.184`
- `SERVER_USER`：服务器用户名（如`ubuntu`或`root`）

**3. 服务器目录权限**

```bash
ruyue

# 检查权限
ls -la /var/www/blog/

# 应该显示当前用户拥有权限
# 如果不对，修复：
sudo chown -R $USER:$USER /var/www/blog/
sudo chmod -R 755 /var/www/blog/

exit
```

**4. Hugo构建错误**

本地测试构建：

```bash
cd /Users/maneng/claude_project/blog

# 尝试构建
hugo --minify

# 如果失败，查看错误信息
```

常见构建错误：

| 错误 | 原因 | 解决 |
|------|------|------|
| `failed to extract shortcode` | Markdown语法错误 | 检查文章语法 |
| `template not found` | 主题文件缺失 | 重新拉取主题 |
| `failed to render` | Front matter错误 | 检查YAML语法 |

---

### ❌ 问题3：部署很慢或超时

**症状**：
- GitHub Actions运行超过10分钟
- 超时失败

**解决方案**：

**1. 检查仓库大小**

```bash
# 查看仓库大小
du -sh /Users/maneng/claude_project/blog

# 查看Git历史大小
du -sh .git
```

如果过大（>500MB），考虑：
- 使用Git LFS管理图片
- 清理大文件历史

**2. 优化SSH部署**

修改 `.github/workflows/deploy.yml`：

```yaml
# 添加--exclude参数，跳过不需要的文件
ARGS: "-avzr --delete --exclude='.git' --exclude='.DS_Store'"
```

**3. 增加超时时间**

在workflow中添加：

```yaml
jobs:
  deploy:
    timeout-minutes: 15    # 默认10分钟，增加到15分钟
```

---

## 图片相关问题

### ❌ 问题4：图片显示404

**症状**：
- 本地预览图片正常
- 线上显示404

**排查步骤**：

**1. 检查图片路径**

Markdown中的路径：

```markdown
# ✅ 正确（以/开头）
![图片](/images/test.png)

# ❌ 错误（相对路径）
![图片](../images/test.png)

# ❌ 错误（没有/）
![图片](images/test.png)
```

实际文件位置：

```
static/images/test.png
```

**2. 检查大小写**

Linux服务器区分大小写：

```markdown
# 文件名：Test.png
![图片](/images/Test.png)    # ✅ 正确
![图片](/images/test.png)    # ❌ 错误
```

**3. 检查文件是否提交**

```bash
# 查看Git状态
git status

# 查看未跟踪的文件
git status | grep "images"

# 如果图片是新的，需要添加：
git add static/images/
git commit -m "Add: 补充图片"
git push
```

**4. 检查文件是否存在**

```bash
# 连接服务器
ruyue

# 检查图片文件
ls -la /var/www/blog/images/

# 查找特定图片
find /var/www/blog -name "test.png"

# 退出
exit
```

**5. 浏览器直接访问图片**

```
https://47.93.8.184/images/test.png
```

查看返回结果：
- `200 OK` - 文件存在，检查Markdown路径
- `404 Not Found` - 文件不存在，检查是否部署
- `403 Forbidden` - 权限问题

---

### ❌ 问题5：图片加载很慢

**原因**：
- 图片太大
- 未压缩

**解决方案**：

**1. 压缩图片**

使用在线工具：
- https://tinypng.com/
- https://squoosh.app/

**2. 调整图片尺寸**

```bash
# macOS使用sips命令
sips -Z 1200 static/images/large-image.png

# 或使用ImageMagick
brew install imagemagick
convert static/images/large-image.png -resize 1200x static/images/large-image.png
```

**3. 使用WebP格式**

```bash
# 转换为WebP
brew install webp
cwebp static/images/test.png -o static/images/test.webp

# 在Markdown中使用
![图片](/images/test.webp)
```

---

## 样式和显示问题

### ❌ 问题6：本地预览正常，线上样式错乱

**原因**：
- `baseURL` 配置错误

**解决方案**：

检查 `config.toml`：

```toml
# ❌ 错误
baseURL = "/"
baseURL = "http://localhost:1313/"

# ✅ 正确
baseURL = "https://47.93.8.184/"
```

修改后：

```bash
git add config.toml
git commit -m "Fix: 修正baseURL配置"
git push
```

---

### ❌ 问题7：代码高亮不正常

**原因**：
- 语言标识错误
- 主题配置问题

**解决方案**：

**1. 检查代码块语法**

```markdown
# ❌ 错误
\`\`\`
代码
\`\`\`

# ✅ 正确
\`\`\`java
public class Test {}
\`\`\`
```

**2. 检查config.toml配置**

```toml
[markup]
  [markup.highlight]
    codeFences = true
    guessSyntax = false
    style = "monokai"    # 可选：dracula, github, monokai等
```

---

### ❌ 问题8：文章列表没有显示新文章

**原因**：
- `draft: true` 未改为 `false`
- 日期是未来时间

**解决方案**：

**1. 检查Front Matter**

```yaml
---
title: "文章标题"
date: 2025-01-15T20:00:00+08:00
draft: false    # ✅ 必须是false
---
```

**2. 检查日期**

```yaml
# 日期不能是未来时间
date: 2025-01-15T20:00:00+08:00    # ✅ 当前或过去
date: 2026-01-15T20:00:00+08:00    # ❌ 未来时间不显示
```

---

## Git相关问题

### ❌ 问题9：Git推送失败

**症状**：
```
! [rejected] main -> main (fetch first)
```

**解决方案**：

```bash
# 拉取最新代码
git pull origin main --rebase

# 如果有冲突，解决后：
git add .
git rebase --continue

# 推送
git push origin main
```

---

### ❌ 问题10：子模块（主题）问题

**症状**：
- `themes/PaperMod` 目录为空
- 构建失败：`template not found`

**解决方案**：

```bash
# 初始化子模块
git submodule update --init --recursive

# 或重新添加主题
rm -rf themes/PaperMod
git submodule add --depth=1 https://github.com/adityatelange/hugo-PaperMod.git themes/PaperMod
```

---

## 服务器相关问题

### ❌ 问题11：Nginx 403 Forbidden

**症状**：
- 访问网站显示 `403 Forbidden`

**解决方案**：

```bash
ruyue

# 1. 检查目录权限
ls -la /var/www/blog/

# 2. 修复权限
sudo chown -R www-data:www-data /var/www/blog/
sudo chmod -R 755 /var/www/blog/

# 3. 检查Nginx配置
sudo nginx -t

# 4. 重启Nginx
sudo systemctl reload nginx

# 5. 查看错误日志
sudo tail -f /var/log/nginx/blog_error.log

exit
```

---

### ❌ 问题12：Nginx 502 Bad Gateway

**症状**：
- 访问网站显示 `502 Bad Gateway`

**原因**：
- 静态网站不应该出现502
- 可能是Nginx配置错误

**解决方案**：

```bash
ruyue

# 检查Nginx状态
sudo systemctl status nginx

# 查看错误日志
sudo tail -n 50 /var/log/nginx/error.log

# 测试配置
sudo nginx -t

# 重启Nginx
sudo systemctl restart nginx

exit
```

---

### ❌ 问题13：HTTPS证书问题

**症状**：
- 浏览器显示"不安全"
- SSL证书错误

**解决方案**：

```bash
ruyue

# 检查证书文件是否存在
ls -la /etc/letsencrypt/live/

# 如果使用IP访问，可能需要自签名证书
# 或使用已有证书

# 重新加载Nginx
sudo systemctl reload nginx

exit
```

---

## 调试工具

### 🔍 本地调试

**1. Hugo详细输出**

```bash
# 显示详细构建信息
hugo --verbose

# 显示调试信息
hugo --debug
```

**2. 检查构建产物**

```bash
# 构建网站
hugo --minify

# 查看生成的文件
ls -lah public/

# 查看具体文件
cat public/index.html
```

**3. 测试特定文章**

```bash
# 只构建特定文章
hugo --buildDrafts --buildFuture
```

---

### 🔍 服务器调试

**1. 查看Nginx日志**

```bash
ruyue

# 实时查看访问日志
sudo tail -f /var/log/nginx/blog_access.log

# 实时查看错误日志
sudo tail -f /var/log/nginx/blog_error.log

# 查看最近50行
sudo tail -n 50 /var/log/nginx/blog_error.log

exit
```

**2. 测试文件访问**

```bash
ruyue

# 测试首页
curl -I http://localhost/

# 测试图片
curl -I http://localhost/images/test.png

# 测试完整内容
curl http://localhost/ | head -50

exit
```

**3. 检查端口和进程**

```bash
ruyue

# 检查Nginx是否运行
sudo systemctl status nginx

# 检查端口监听
sudo netstat -tlnp | grep nginx

exit
```

---

### 🔍 GitHub Actions调试

**1. 查看详细日志**

```
GitHub仓库 → Actions → 点击失败的workflow → 点击失败的步骤
```

**2. 手动运行workflow**

```
Actions → Deploy Hugo Blog → Run workflow
```

**3. 添加调试输出**

修改 `.github/workflows/deploy.yml`，添加调试步骤：

```yaml
- name: Debug - Show Environment
  run: |
    echo "工作目录:"
    pwd
    echo "文件列表:"
    ls -la
    echo "主题目录:"
    ls -la themes/
```

---

## 📞 获取更多帮助

### 官方文档

- [Hugo官方文档](https://gohugo.io/documentation/)
- [PaperMod主题Wiki](https://github.com/adityatelange/hugo-PaperMod/wiki)
- [GitHub Actions文档](https://docs.github.com/en/actions)
- [Nginx文档](https://nginx.org/en/docs/)

### 快速命令参考

| 任务 | 命令 |
|------|------|
| 本地预览 | `hugo server -D` |
| 构建网站 | `hugo --minify` |
| 查看Git状态 | `git status` |
| 连接服务器 | `ruyue` |
| 查看Nginx日志 | `sudo tail -f /var/log/nginx/blog_error.log` |
| 测试Nginx配置 | `sudo nginx -t` |
| 重载Nginx | `sudo systemctl reload nginx` |

---

**问题未解决？**

1. 检查 `README.md` 和 `USAGE.md`
2. 查看GitHub Actions详细日志
3. 检查服务器Nginx日志
4. 尝试本地重新构建：`hugo --minify`

---

**最后更新**：2025-01-15
