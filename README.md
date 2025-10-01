# 我的Hugo博客

基于Hugo搭建的个人知识库，记录技术、思考与成长。

## 📋 项目信息

- **博客地址**：https://ruyueshuke.com/ (如约数科)
- **静态生成器**：Hugo
- **主题**：PaperMod
- **部署方式**：GitHub Actions自动部署
- **服务器**：阿里云

## 🚀 技术栈

- **前端**：Hugo + PaperMod主题
- **版本控制**：Git + GitHub
- **CI/CD**：GitHub Actions
- **Web服务器**：Nginx
- **图片存储**：GitHub仓库
- **SSL**：HTTPS

## 📝 日常使用

### 创建新文章

```bash
# 进入项目目录
cd /Users/maneng/claude_project/blog

# 创建新文章
hugo new posts/$(date +%Y-%m-%d)-my-new-post.md

# 或指定文章名
hugo new posts/java-performance-tuning.md
```

### 编辑文章

```bash
# 使用编辑器打开
vim content/posts/java-performance-tuning.md

# 或使用VS Code
code content/posts/java-performance-tuning.md
```

### 添加图片

```bash
# 复制图片到static/images目录
cp ~/Downloads/screenshot.png static/images/$(date +%Y-%m-%d)-screenshot.png

# 在Markdown中引用
# ![描述](/images/2025-01-15-screenshot.png)
```

### 本地预览

```bash
# 启动Hugo本地服务器
hugo server -D

# 浏览器访问
# http://localhost:1313
```

### 发布文章

```bash
# 查看修改
git status

# 添加所有修改
git add .

# 提交
git commit -m "Add: 新文章标题"

# 推送到GitHub（会自动触发部署）
git push origin main
```

### 查看部署状态

1. 访问：https://github.com/YOUR_USERNAME/my-blog/actions
2. 查看最新workflow运行状态
3. 等待2-3分钟后访问网站

## 🖼️ 图片管理

### 目录结构

```
static/images/
├── common/              # 通用图片
│   ├── logo.png
│   └── avatar.jpg
├── 2025-01-15/         # 按日期分类
│   └── screenshot.png
└── 2025-01-16/
    └── diagram.jpg
```

### 命名规范

- 使用语义化命名：`java-performance-chart.png`
- 避免中文和空格
- 使用小写字母和连字符

### 大小建议

- 小图标：< 50KB
- 配图：< 300KB
- 大图：< 800KB

## 🔧 维护

### 更新Hugo

```bash
brew upgrade hugo
```

### 更新主题

```bash
git submodule update --remote --merge
```

### 本地构建测试

```bash
# 构建静态文件
hugo --minify

# 查看构建结果
ls -lah public/
```

## 📂 目录结构

```
blog/
├── .github/
│   └── workflows/
│       └── deploy.yml          # GitHub Actions配置
├── archetypes/                 # 文章模板
├── content/
│   ├── posts/                  # 文章目录
│   ├── about.md               # 关于页面
│   ├── archives.md            # 归档页面
│   └── search.md              # 搜索页面
├── static/
│   └── images/                # 图片目录
├── themes/
│   └── PaperMod/              # 主题（Git子模块）
├── config.toml                # Hugo配置
├── .gitignore
├── README.md                  # 本文件
├── IMPLEMENTATION_TODO.md     # 实施清单
└── nginx-blog.conf           # Nginx配置参考
```

## 🐛 常见问题

### 推送后网站没更新

1. 检查GitHub Actions是否成功
2. 查看Actions页面的错误日志
3. 手动触发workflow

### 图片显示404

1. 检查图片路径是否正确
2. 确认图片已提交到Git
3. 路径区分大小写

### 本地预览正常但线上样式错误

1. 检查`config.toml`中的`baseURL`
2. 确保设置为`https://47.93.8.184/`

详细故障排查请查看：`TROUBLESHOOTING.md`

## 📚 参考资源

- [Hugo官方文档](https://gohugo.io/documentation/)
- [PaperMod主题文档](https://github.com/adityatelange/hugo-PaperMod/wiki)
- [GitHub Actions文档](https://docs.github.com/en/actions)
- [Markdown语法](https://www.markdownguide.org/)

## 📄 许可

本项目内容采用个人所有，未经许可不得转载。

---

**最后更新**：2025-01-15
