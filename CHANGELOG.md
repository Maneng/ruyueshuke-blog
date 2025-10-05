# Changelog

所有重要的项目变更都会记录在此文件中。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)，
并且该项目遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [Unreleased]

## [1.1.0] - 2025-01-15

### 🎉 新增 (Added)

#### 网站架构调整
- **公司介绍首页** - 新增 `index.html` 作为网站主页
  - 专业的公司介绍页面，展示如约数科工作室的服务和能力
  - 包含导航栏、服务介绍、项目经验、技术栈、关于我们等模块
  - 响应式设计，支持移动端和桌面端
  - 使用 Tailwind CSS 构建的现代化界面

- **博客入口** - 在首页多处添加博客访问入口
  - 导航栏添加"技术博客"菜单项（带书籍图标）
  - Hero区域添加"访问技术博客"按钮
  - 移动端菜单同步添加博客链接

- **项目文档** - 新增 `CLAUDE.md` 文件
  - 为 Claude Code 提供项目特定的指导信息
  - 包含常用命令、核心架构、开发规范等内容
  - 帮助未来的 Claude 实例快速理解项目结构

### 🔧 变更 (Changed)

#### 部署配置调整
- **Hugo配置** (`config.toml`)
  - baseURL 从 `https://47.93.8.184/` 改为 `https://47.93.8.184/blog/`
  - 博客系统现在部署在 `/blog/` 子目录下

- **GitHub Actions** (`.github/workflows/deploy.yml`)
  - 分离首页和博客的部署流程
  - Hugo博客部署到 `/usr/share/testpage/blog/` 子目录
  - index.html 部署到 `/usr/share/testpage/` 根目录
  - 添加自动创建目录的逻辑
  - 更新部署成功后的提示信息

### 📁 网站结构

部署后的网站结构：
```
https://47.93.8.184/          → 公司介绍首页（如约数科工作室）
https://47.93.8.184/blog/     → Hugo博客系统
```

服务器目录结构：
```
/usr/share/testpage/
├── index.html          # 公司介绍页（首页）
└── blog/               # Hugo博客目录
    ├── index.html      # 博客首页
    ├── posts/          # 博客文章
    ├── css/            # 样式文件
    └── ...             # 其他Hugo生成的文件
```

### 🚀 部署信息

- **提交哈希**: 68b85e7
- **部署方式**: GitHub Actions 自动部署
- **目标服务器**: 阿里云服务器 (47.93.8.184)
- **部署时间**: 约2-3分钟

### 📝 提交记录

```
68b85e7 - Feat: 添加公司介绍首页并将博客部署到/blog/子目录
8ce2517 - Update: 改回IP访问并发布Hugo博客搭建SOP文档
b85d1ca - Docs: 添加部署总结和快速上手指南
1dd18ca - Fix: 安装rsync并更新README访问地址
e136e8b - Update: 配置域名和部署路径
01595da - Initial commit: Hugo blog setup with PaperMod theme
```

### 🔗 访问地址

- **公司首页**: https://47.93.8.184/
- **技术博客**: https://47.93.8.184/blog/
- **GitHub仓库**: https://github.com/Maneng/ruyueshuke-blog

### 📋 待办事项

- [ ] 域名备案完成后更新配置
- [ ] 添加SSL证书
- [ ] 优化移动端体验
- [ ] 添加更多博客内容

---

## [1.0.0] - 2025-01-14

### 🎉 初始版本

- Hugo博客系统搭建完成
- 使用 PaperMod 主题
- 配置 GitHub Actions 自动部署
- 包含文章模板和使用文档
- 支持中文界面和内容

### 📚 项目文档

- `README.md` - 项目说明和快速开始指南
- `USAGE.md` - 详细使用指南
- `TROUBLESHOOTING.md` - 故障排查手册
- `PROJECT_OVERVIEW.md` - 项目架构概览
- `IMPLEMENTATION_TODO.md` - 实施清单

### 🛠️ 技术栈

- **静态网站生成器**: Hugo v0.150.1
- **主题**: PaperMod
- **CI/CD**: GitHub Actions
- **Web服务器**: Nginx
- **部署目标**: 阿里云服务器

---

*本 CHANGELOG 遵循 [Keep a Changelog](https://keepachangelog.com/) 规范*