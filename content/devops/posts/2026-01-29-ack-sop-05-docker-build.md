---
title: "模块5：构建Docker镜像"
date: 2026-01-29T11:05:00+08:00
draft: false
tags: ["Kubernetes", "阿里云", "ACK", "SOP", "教程", "Docker", "ACR"]
categories: ["技术"]
series: ["阿里云ACK部署SOP"]
weight: 5
description: "详细讲解如何编写Dockerfile、构建Docker镜像、推送到阿里云容器镜像服务ACR"
---

## 导航

- **上一步**：[模块4：配置ALB Ingress](/blog/devops/posts/2026-01-29-ack-sop-04-alb-ingress/)
- **下一步**：[模块6：部署应用到K8s](/blog/devops/posts/2026-01-29-ack-sop-06-deploy-app/)
- **返回主索引**：[阿里云ACK部署SOP](/blog/devops/posts/2026-01-29-aliyun-ack-deployment-sop/)

---

## 模块概述

**预计时间**：20分钟

**本模块目标**：
- ✅ 理解Docker镜像的基本概念
- ✅ 编写Dockerfile（使用多阶段构建）
- ✅ 本地构建Docker镜像
- ✅ 本地测试镜像
- ✅ 推送镜像到阿里云ACR
- ✅ 验证镜像可用性

**成本说明**：
- ACR个人版：免费
- 镜像存储：免费（个人版有300GB免费额度）
- 镜像拉取：免费（同地域）
- 本模块预计成本：¥0

---

## 步骤5.1：理解Docker镜像

### 🎬 操作说明
在开始构建镜像之前，我们需要先理解Docker镜像的基本概念。这一步不需要操作，只需要理解核心概念。

### 📍 详细说明

**什么是Docker镜像？**

Docker镜像是一个轻量级、可执行的独立软件包，包含运行应用所需的一切：
- 代码（你的应用程序）
- 运行时（如：Java、Python、Node.js）
- 系统工具和库
- 配置文件

**镜像 vs 容器**

| 概念 | 说明 | 类比 |
|-----|------|-----|
| **镜像（Image）** | 只读的模板，包含应用和依赖 | 类似于"类"（Class） |
| **容器（Container）** | 镜像的运行实例 | 类似于"对象"（Object） |

**镜像的层级结构**

Docker镜像由多个层（Layer）组成，每一层都是只读的：

```
┌─────────────────────────────┐
│  你的应用代码（Layer 4）      │  ← 最上层
├─────────────────────────────┤
│  应用依赖（Layer 3）          │
├─────────────────────────────┤
│  运行时环境（Layer 2）        │
├─────────────────────────────┤
│  基础操作系统（Layer 1）      │  ← 最底层
└─────────────────────────────┘
```

**为什么使用分层结构？**

1. **节省空间**：相同的层可以被多个镜像共享
2. **加速构建**：只需要重新构建变化的层
3. **加速分发**：只需要传输变化的层

**镜像标签（Tag）**

镜像标签用于标识镜像的不同版本：

```bash
registry.cn-hangzhou.aliyuncs.com/my-namespace/my-app:v1.0.0
│                                  │            │      │
│                                  │            │      └─ 标签（版本）
│                                  │            └──────── 镜像名称
│                                  └───────────────────── 命名空间
└──────────────────────────────────────────────────────── 镜像仓库地址
```

**常用标签规范**：
- `latest`：最新版本（不推荐生产环境使用）
- `v1.0.0`：语义化版本号
- `20260129-abc123`：日期 + Git commit SHA
- `prod-v1.0.0`：环境 + 版本号

### ✅ 验证点
- 理解镜像和容器的区别
- 理解镜像的分层结构
- 理解镜像标签的作用

### ⚠️ 常见问题

**问题1：镜像和虚拟机有什么区别？**
- 答：镜像更轻量
- 虚拟机包含完整的操作系统（GB级别）
- 镜像只包含应用和必要的依赖（MB级别）
- 镜像启动速度更快（秒级 vs 分钟级）

**问题2：为什么不推荐使用latest标签？**
- 答：latest标签不稳定
- latest会随着新版本发布而变化
- 生产环境无法确定运行的是哪个版本
- 建议使用明确的版本号

**问题3：镜像存储在哪里？**
- 答：存储在镜像仓库（Registry）
- 公共仓库：Docker Hub、阿里云ACR公共仓库
- 私有仓库：阿里云ACR、Harbor
- 本地：Docker守护进程的存储目录

### 💡 小贴士
- 📦 镜像是不可变的，每次修改都会创建新的层
- 🏷️ 建议使用语义化版本号作为标签
- 💾 镜像越小越好，减少传输时间和存储成本

---

## 步骤5.2：准备示例应用

### 🎬 操作说明
为了演示Docker镜像的构建过程，我们准备一个简单的Go语言Web应用。如果你有自己的应用，可以跳过这一步。

### 📍 详细步骤

**第1步：创建项目目录**
- 在本地电脑上，创建一个项目目录：
  ```bash
  mkdir -p ~/my-app
  cd ~/my-app
  ```

**第2步：创建Go应用代码**
- 创建文件 `main.go`：
  ```go
  package main

  import (
      "fmt"
      "log"
      "net/http"
      "os"
  )

  func main() {
      port := os.Getenv("PORT")
      if port == "" {
          port = "8080"
      }

      http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
          fmt.Fprintf(w, "Hello from Kubernetes!\n")
          fmt.Fprintf(w, "Version: 1.0.0\n")
          fmt.Fprintf(w, "Hostname: %s\n", os.Getenv("HOSTNAME"))
      })

      http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
          w.WriteHeader(http.StatusOK)
          fmt.Fprintf(w, "OK\n")
      })

      log.Printf("Server starting on port %s", port)
      if err := http.ListenAndServe(":"+port, nil); err != nil {
          log.Fatal(err)
      }
  }
  ```

**第3步：初始化Go模块**
- 运行命令：
  ```bash
  go mod init my-app
  ```
- 这会创建 `go.mod` 文件

**第4步：本地测试应用**
- 运行应用：
  ```bash
  go run main.go
  ```
- 在另一个终端中测试：
  ```bash
  curl http://localhost:8080
  ```
- 应该看到：
  ```
  Hello from Kubernetes!
  Version: 1.0.0
  Hostname:
  ```
- 按Ctrl+C停止应用

### ✅ 验证点
- 项目目录已创建
- main.go文件已创建
- go.mod文件已创建
- 应用可以本地运行

### ⚠️ 常见问题

**问题1：没有安装Go怎么办？**
- 答：可以使用其他语言
- Python示例：
  ```python
  from flask import Flask
  app = Flask(__name__)

  @app.route('/')
  def hello():
      return 'Hello from Kubernetes!'

  if __name__ == '__main__':
      app.run(host='0.0.0.0', port=8080)
  ```
- Node.js示例：
  ```javascript
  const express = require('express');
  const app = express();

  app.get('/', (req, res) => {
      res.send('Hello from Kubernetes!');
  });

  app.listen(8080, () => {
      console.log('Server started on port 8080');
  });
  ```

**问题2：为什么要有/health接口？**
- 答：用于Kubernetes的健康检查
- Kubernetes会定期访问这个接口
- 如果返回200，说明应用健康
- 如果返回非200或超时，Kubernetes会重启Pod

### 💡 小贴士
- 🎯 示例应用很简单，但包含了生产环境的基本要素
- 🏥 健康检查接口是生产环境的必备功能
- 📝 建议在应用中添加版本号，方便排查问题

---

## 步骤5.3：编写Dockerfile

### 🎬 操作说明
现在我们编写Dockerfile，这是构建Docker镜像的配置文件。我们使用多阶段构建，可以大幅减小镜像体积。

### 📍 详细步骤

**第1步：创建Dockerfile**
- 在项目目录中，创建文件 `Dockerfile`：
  ```dockerfile
  # 第一阶段：构建阶段
  FROM golang:1.21-alpine AS builder

  # 设置工作目录
  WORKDIR /app

  # 复制go.mod和go.sum（如果有）
  COPY go.mod ./

  # 下载依赖
  RUN go mod download

  # 复制源代码
  COPY . .

  # 编译应用
  RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o main .

  # 第二阶段：运行阶段
  FROM alpine:latest

  # 安装ca-certificates（用于HTTPS请求）
  RUN apk --no-cache add ca-certificates

  # 设置工作目录
  WORKDIR /root/

  # 从构建阶段复制编译好的二进制文件
  COPY --from=builder /app/main .

  # 暴露端口
  EXPOSE 8080

  # 运行应用
  CMD ["./main"]
  ```

**第2步：理解Dockerfile的每一行**

```dockerfile
# 第一阶段：构建阶段
FROM golang:1.21-alpine AS builder
```
- 使用Go 1.21的Alpine镜像作为基础镜像
- Alpine是一个极小的Linux发行版（只有5MB）
- `AS builder`给这个阶段命名，后续可以引用

```dockerfile
WORKDIR /app
```
- 设置工作目录为/app
- 后续的命令都在这个目录中执行

```dockerfile
COPY go.mod ./
RUN go mod download
```
- 先复制go.mod文件
- 然后下载依赖
- 这样可以利用Docker的缓存机制
- 如果go.mod没变，就不会重新下载依赖

```dockerfile
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o main .
```
- 复制所有源代码
- 编译应用
- `CGO_ENABLED=0`：禁用CGO，生成静态链接的二进制文件
- `GOOS=linux`：编译为Linux平台

```dockerfile
# 第二阶段：运行阶段
FROM alpine:latest
```
- 使用Alpine作为运行时镜像
- 这个镜像只有5MB，非常小

```dockerfile
COPY --from=builder /app/main .
```
- 从第一阶段（builder）复制编译好的二进制文件
- 不复制源代码和编译工具
- 这样最终镜像非常小

```dockerfile
CMD ["./main"]
```
- 容器启动时运行的命令

**第3步：创建.dockerignore文件**
- 创建文件 `.dockerignore`：
  ```
  .git
  .gitignore
  README.md
  .DS_Store
  *.md
  ```
- 这个文件类似于.gitignore
- 列出的文件不会被复制到镜像中

### ✅ 验证点
- Dockerfile已创建
- .dockerignore已创建
- 理解多阶段构建的原理

### ⚠️ 常见问题

**问题1：什么是多阶段构建？**
- 答：在一个Dockerfile中使用多个FROM指令
- 第一阶段：构建应用（包含编译工具）
- 第二阶段：运行应用（只包含二进制文件）
- 最终镜像只包含第二阶段的内容
- 可以大幅减小镜像体积（从几百MB到几MB）

**问题2：为什么要使用Alpine镜像？**
- 答：Alpine非常小
- 普通的Ubuntu镜像：约100MB
- Alpine镜像：只有5MB
- 镜像越小，传输越快，启动越快

**问题3：CGO_ENABLED=0是什么意思？**
- 答：禁用CGO
- CGO允许Go调用C代码
- 禁用CGO后，生成的是静态链接的二进制文件
- 静态链接的二进制文件可以在任何Linux系统上运行
- 不需要依赖系统库

### 💡 小贴士
- 📦 多阶段构建可以减小镜像体积90%以上
- 🎯 生产环境强烈推荐使用多阶段构建
- 📝 .dockerignore可以加速构建过程

---

## 步骤5.4：本地构建Docker镜像

### 🎬 操作说明
现在Dockerfile已经准备好了，我们来构建Docker镜像。构建过程会执行Dockerfile中的所有指令，生成最终的镜像。

### 📍 详细步骤

**第1步：检查Docker是否运行**
- 在终端中运行：
  ```bash
  docker version
  ```
- 应该看到Client和Server的版本信息
- 如果提示"Cannot connect to the Docker daemon"，需要启动Docker

**第2步：构建镜像**
- 在项目目录中运行：
  ```bash
  docker build -t my-app:v1.0.0 .
  ```
- 参数说明：
  - `-t my-app:v1.0.0`：指定镜像名称和标签
  - `.`：Dockerfile所在的目录（当前目录）

**第3步：观察构建过程**
- 构建过程会输出每一步的执行结果：
  ```
  [+] Building 45.2s (15/15) FINISHED
   => [internal] load build definition from Dockerfile
   => [internal] load .dockerignore
   => [internal] load metadata for docker.io/library/golang:1.21-alpine
   => [builder 1/6] FROM docker.io/library/golang:1.21-alpine
   => [builder 2/6] WORKDIR /app
   => [builder 3/6] COPY go.mod ./
   => [builder 4/6] RUN go mod download
   => [builder 5/6] COPY . .
   => [builder 6/6] RUN CGO_ENABLED=0 GOOS=linux go build ...
   => [stage-1 1/3] FROM docker.io/library/alpine:latest
   => [stage-1 2/3] RUN apk --no-cache add ca-certificates
   => [stage-1 3/3] COPY --from=builder /app/main .
   => exporting to image
   => => writing image sha256:abc123...
   => => naming to docker.io/library/my-app:v1.0.0
  ```

**第4步：验证镜像已创建**
- 运行命令查看本地镜像：
  ```bash
  docker images | grep my-app
  ```
- 应该看到：
  ```
  my-app       v1.0.0    abc123def456   1 minute ago   15MB
  ```
- 注意镜像大小只有15MB（多阶段构建的效果）

**第5步：查看镜像详情**
- 运行命令：
  ```bash
  docker inspect my-app:v1.0.0
  ```
- 可以看到镜像的详细信息，包括层级结构、环境变量等

### ✅ 验证点
- 镜像构建成功
- 镜像出现在本地镜像列表中
- 镜像大小合理（约15MB）

### ⚠️ 常见问题

**问题1：构建很慢怎么办？**
- 答：可能是网络问题
- 第一次构建需要下载基础镜像
- 可以使用国内镜像加速器：
  ```bash
  # 配置Docker镜像加速器（阿里云）
  # 在Docker Desktop的设置中添加：
  # https://registry.cn-hangzhou.aliyuncs.com
  ```

**问题2：构建失败，提示"no space left on device"？**
- 答：磁盘空间不足
- 清理无用的镜像和容器：
  ```bash
  docker system prune -a
  ```
- 或者增加Docker的磁盘配额

**问题3：每次构建都很慢？**
- 答：可能没有利用缓存
- Docker会缓存每一层
- 如果某一层的输入没变，就会使用缓存
- 确保Dockerfile的顺序合理（先复制依赖文件，再复制源代码）

**问题4：镜像太大怎么办？**
- 答：检查以下几点
- 是否使用了多阶段构建？
- 是否使用了Alpine基础镜像？
- 是否有不必要的文件被复制进去？
- 可以使用 `docker history my-app:v1.0.0` 查看每一层的大小

### 💡 小贴士
- 🚀 第一次构建会慢，后续构建会利用缓存
- 📦 多阶段构建可以让镜像从几百MB减小到几MB
- 🔍 使用 `docker history` 可以分析镜像大小

---

## 步骤5.5：本地测试镜像

### 🎬 操作说明
镜像构建好了，但是还不确定是否能正常运行。我们需要在本地测试一下，确保应用可以正常启动和响应请求。

### 📍 详细步骤

**第1步：运行容器**
- 在终端中运行：
  ```bash
  docker run -d -p 8080:8080 --name my-app-test my-app:v1.0.0
  ```
- 参数说明：
  - `-d`：后台运行
  - `-p 8080:8080`：将容器的8080端口映射到主机的8080端口
  - `--name my-app-test`：给容器命名
  - `my-app:v1.0.0`：使用的镜像

**第2步：查看容器状态**
- 运行命令：
  ```bash
  docker ps
  ```
- 应该看到：
  ```
  CONTAINER ID   IMAGE            COMMAND     STATUS         PORTS                    NAMES
  abc123def456   my-app:v1.0.0    "./main"    Up 10 seconds  0.0.0.0:8080->8080/tcp   my-app-test
  ```
- 确认STATUS是"Up"

**第3步：查看容器日志**
- 运行命令：
  ```bash
  docker logs my-app-test
  ```
- 应该看到：
  ```
  2026/01/29 03:00:00 Server starting on port 8080
  ```

**第4步：测试应用**
- 使用curl测试：
  ```bash
  curl http://localhost:8080
  ```
- 应该看到：
  ```
  Hello from Kubernetes!
  Version: 1.0.0
  Hostname: abc123def456
  ```

**第5步：测试健康检查接口**
- 运行命令：
  ```bash
  curl http://localhost:8080/health
  ```
- 应该看到：
  ```
  OK
  ```

**第6步：停止并删除容器**
- 运行命令：
  ```bash
  docker stop my-app-test
  docker rm my-app-test
  ```

### ✅ 验证点
- 容器可以正常启动
- 应用可以响应HTTP请求
- 健康检查接口正常工作
- 容器日志没有错误

### ⚠️ 常见问题

**问题1：容器启动后立即退出？**
- 答：可能是应用启动失败
- 查看容器日志：
  ```bash
  docker logs my-app-test
  ```
- 检查是否有错误信息

**问题2：curl提示"Connection refused"？**
- 答：可能是端口映射错误
- 检查容器是否在运行：`docker ps`
- 检查端口映射是否正确：`docker port my-app-test`
- 检查应用是否监听正确的端口

**问题3：如何进入容器内部调试？**
- 答：使用docker exec命令
  ```bash
  docker exec -it my-app-test sh
  ```
- 这会进入容器的shell
- 可以查看文件、运行命令等
- 退出：输入 `exit`

### 💡 小贴士
- 🧪 本地测试可以快速发现问题
- 📝 建议测试所有关键接口
- 🔍 使用 `docker logs -f` 可以实时查看日志

---

## 步骤5.6：登录阿里云ACR

### 🎬 操作说明
现在镜像已经在本地测试通过了，我们需要将镜像推送到阿里云容器镜像服务（ACR），这样Kubernetes才能拉取镜像。首先需要登录ACR。

### 📍 详细步骤

**第1步：进入ACR控制台**
- 在浏览器中访问：https://cr.console.aliyun.com/
- 确认地域为"华东1（杭州）"

**第2步：创建命名空间**
- 在左侧菜单中，点击"命名空间"
- 点击"创建命名空间"按钮
- 命名空间名称：输入 `my-namespace`（全局唯一，如果被占用需要换一个）
- 命名空间类型：选择"私有"
- 点击"确定"按钮

**第3步：获取登录密码**
- 在左侧菜单中，点击"访问凭证"
- 看到"固定密码"区域
- 如果没有设置过密码，点击"设置固定密码"
- 输入密码（至少8位，包含大小写字母和数字）
- 确认密码
- 点击"确定"按钮

**第4步：获取登录命令**
- 在"访问凭证"页面，看到"登录命令"
- 复制登录命令，类似：
  ```bash
  docker login --username=your-username registry.cn-hangzhou.aliyuncs.com
  ```

**第5步：在本地登录ACR**
- 在终端中，粘贴并运行登录命令：
  ```bash
  docker login --username=your-username registry.cn-hangzhou.aliyuncs.com
  ```
- 输入密码（就是刚才设置的固定密码）
- 看到"Login Succeeded"表示登录成功

### ✅ 验证点
- 命名空间已创建
- 固定密码已设置
- Docker登录ACR成功

### ⚠️ 常见问题

**问题1：命名空间名称被占用？**
- 答：命名空间是全局唯一的
- 换一个名称，如：`my-namespace-20260129`
- 或者使用你的阿里云账号ID作为前缀

**问题2：忘记固定密码怎么办？**
- 答：可以重新设置
- 在"访问凭证"页面，点击"重置固定密码"
- 输入新密码即可

**问题3：登录失败，提示"unauthorized"？**
- 答：可能是用户名或密码错误
- 用户名是你的阿里云账号（不是昵称）
- 密码是固定密码（不是阿里云登录密码）
- 检查是否有多余的空格

**问题4：ACR个人版和企业版有什么区别？**
- 答：个人版免费，企业版收费
- 个人版：300GB存储，无SLA保证
- 企业版：更大存储，99.9% SLA，更多功能
- 学习和小项目使用个人版完全够用

### 💡 小贴士
- 🔒 固定密码要妥善保管，不要泄露
- 📝 建议将登录命令保存到笔记中，方便后续使用
- 💰 ACR个人版完全免费，放心使用

---

## 步骤5.7：推送镜像到ACR

### 🎬 操作说明
现在已经登录ACR了，我们可以将本地的镜像推送到ACR。推送后，Kubernetes就可以从ACR拉取镜像了。

### 📍 详细步骤

**第1步：给镜像打标签**
- 在终端中运行：
  ```bash
  docker tag my-app:v1.0.0 registry.cn-hangzhou.aliyuncs.com/my-namespace/my-app:v1.0.0
  ```
- 参数说明：
  - `my-app:v1.0.0`：本地镜像
  - `registry.cn-hangzhou.aliyuncs.com`：ACR的地址
  - `my-namespace`：你创建的命名空间
  - `my-app`：镜像名称
  - `v1.0.0`：标签

**第2步：推送镜像**
- 运行命令：
  ```bash
  docker push registry.cn-hangzhou.aliyuncs.com/my-namespace/my-app:v1.0.0
  ```
- 推送过程会显示进度：
  ```
  The push refers to repository [registry.cn-hangzhou.aliyuncs.com/my-namespace/my-app]
  abc123: Pushed
  def456: Pushed
  v1.0.0: digest: sha256:xyz789... size: 1234
  ```

**第3步：同时推送latest标签**
- 给镜像打latest标签：
  ```bash
  docker tag my-app:v1.0.0 registry.cn-hangzhou.aliyuncs.com/my-namespace/my-app:latest
  ```
- 推送latest标签：
  ```bash
  docker push registry.cn-hangzhou.aliyuncs.com/my-namespace/my-app:latest
  ```

**第4步：在ACR控制台验证**
- 回到ACR控制台
- 在左侧菜单中，点击"镜像仓库"
- 应该看到新创建的仓库：`my-namespace/my-app`
- 点击仓库名称，进入仓库详情
- 在"镜像版本"标签页，应该看到两个标签：
  - `v1.0.0`
  - `latest`

**第5步：查看镜像详情**
- 在镜像版本列表中，点击某个标签
- 可以看到镜像的详细信息：
  - 镜像大小
  - 推送时间
  - 镜像层级
  - 安全扫描结果（如果开启了）

### ✅ 验证点
- 镜像已推送到ACR
- ACR控制台可以看到镜像
- 镜像有v1.0.0和latest两个标签

### ⚠️ 常见问题

**问题1：推送失败，提示"denied"？**
- 答：可能是权限问题
- 检查是否已登录ACR
- 检查命名空间名称是否正确
- 检查命名空间是否是你创建的

**问题2：推送很慢怎么办？**
- 答：可能是网络问题
- 第一次推送需要上传所有层
- 后续推送只需要上传变化的层
- 可以使用阿里云ECS推送，速度更快

**问题3：为什么要推送latest标签？**
- 答：方便测试
- 开发环境可以使用latest标签
- 生产环境必须使用明确的版本号
- latest标签会随着新版本发布而变化

**问题4：如何删除镜像？**
- 答：在ACR控制台删除
- 进入镜像仓库详情
- 在"镜像版本"标签页，勾选要删除的版本
- 点击"删除"按钮

### 💡 小贴士
- 🏷️ 建议同时推送版本号和latest标签
- 📦 镜像推送后，可以在任何地方拉取
- 🔒 私有仓库的镜像只有你自己可以访问

---

## 步骤5.8：验证镜像可用性

### 🎬 操作说明
镜像已经推送到ACR了，我们需要验证Kubernetes是否可以从ACR拉取镜像。这是部署应用前的最后一步验证。

### 📍 详细步骤

**第1步：创建镜像拉取密钥**
- Kubernetes需要认证信息才能从私有仓库拉取镜像
- 在终端中运行：
  ```bash
  kubectl create secret docker-registry acr-secret \
    --docker-server=registry.cn-hangzhou.aliyuncs.com \
    --docker-username=your-username \
    --docker-password=your-password \
    --docker-email=your-email@example.com \
    -n default
  ```
- 参数说明：
  - `acr-secret`：密钥名称
  - `--docker-server`：ACR地址
  - `--docker-username`：你的阿里云账号
  - `--docker-password`：ACR固定密码
  - `--docker-email`：你的邮箱
  - `-n default`：在default命名空间创建

**第2步：创建测试Pod**
- 创建文件 `test-pod.yaml`：
  ```yaml
  apiVersion: v1
  kind: Pod
  metadata:
    name: test-acr
    namespace: default
  spec:
    containers:
    - name: my-app
      image: registry.cn-hangzhou.aliyuncs.com/my-namespace/my-app:v1.0.0
      ports:
      - containerPort: 8080
    imagePullSecrets:
    - name: acr-secret
  ```

**第3步：应用测试Pod**
- 运行命令：
  ```bash
  kubectl apply -f test-pod.yaml
  ```

**第4步：查看Pod状态**
- 运行命令：
  ```bash
  kubectl get pod test-acr -n default
  ```
- 初始状态可能是"ContainerCreating"
- 等待约30秒，状态应该变为"Running"：
  ```
  NAME       READY   STATUS    RESTARTS   AGE
  test-acr   1/1     Running   0          1m
  ```

**第5步：查看Pod详情**
- 如果Pod状态不是Running，查看详情：
  ```bash
  kubectl describe pod test-acr -n default
  ```
- 在Events部分，可以看到镜像拉取的过程
- 如果成功，会看到"Successfully pulled image"

**第6步：测试Pod**
- 使用port-forward访问Pod：
  ```bash
  kubectl port-forward pod/test-acr 8080:8080 -n default
  ```
- 在另一个终端中测试：
  ```bash
  curl http://localhost:8080
  ```
- 应该看到应用的响应

**第7步：清理测试Pod**
- 运行命令：
  ```bash
  kubectl delete pod test-acr -n default
  ```

### ✅ 验证点
- 镜像拉取密钥已创建
- Pod可以成功拉取ACR的镜像
- Pod状态为Running
- 应用可以正常响应请求

### ⚠️ 常见问题

**问题1：Pod一直是ImagePullBackOff状态？**
- 答：镜像拉取失败
- 查看Pod详情：
  ```bash
  kubectl describe pod test-acr -n default
  ```
- 常见原因：
  - 镜像名称错误
  - 镜像拉取密钥错误
  - 网络问题

**问题2：如何查看镜像拉取日志？**
- 答：查看Pod的Events
  ```bash
  kubectl describe pod test-acr -n default | grep -A 10 Events
  ```
- 会显示详细的错误信息

**问题3：每个命名空间都要创建镜像拉取密钥吗？**
- 答：是的
- 镜像拉取密钥是命名空间级别的资源
- 每个命名空间都需要创建
- 或者使用ServiceAccount的imagePullSecrets

### 💡 小贴士
- 🔑 镜像拉取密钥很重要，没有它无法拉取私有镜像
- 📝 建议将创建密钥的命令保存下来
- 🎯 下一步：部署真实应用到Kubernetes

---

## 模块总结

### 🎉 恭喜！你已经完成了Docker镜像的构建和推送

在这个模块中，我们完成了以下工作：

1. ✅ **理解了Docker镜像的基本概念**
   - 镜像和容器的区别
   - 镜像的分层结构
   - 镜像标签的规范

2. ✅ **编写了Dockerfile**
   - 使用多阶段构建
   - 使用Alpine基础镜像
   - 镜像体积只有15MB

3. ✅ **构建和测试了镜像**
   - 本地构建镜像
   - 本地测试镜像
   - 验证应用正常工作

4. ✅ **推送镜像到ACR**
   - 创建ACR命名空间
   - 登录ACR
   - 推送镜像到ACR

5. ✅ **验证了镜像可用性**
   - 创建镜像拉取密钥
   - Kubernetes成功拉取镜像
   - Pod正常运行

### 📊 镜像对比

| 构建方式 | 镜像大小 | 构建时间 | 安全性 |
|---------|---------|---------|--------|
| 单阶段构建（包含编译工具） | 约300MB | 快 | 低（包含不必要的工具） |
| 多阶段构建（只包含二进制） | 约15MB | 稍慢 | 高（最小化攻击面） |

### 🎯 下一步

现在镜像已经准备好了，在下一个模块中，我们将：

1. 创建Kubernetes配置文件（Deployment、Service、Ingress）
2. 部署应用到Kubernetes集群
3. 配置健康检查和资源限制
4. 通过域名访问应用

**继续学习**：[模块6：部署应用到K8s](/blog/devops/posts/2026-01-29-ack-sop-06-deploy-app/)

### 💡 重要提示

- 📦 **镜像优化**：多阶段构建可以减小镜像体积90%以上
- 🏷️ **标签规范**：生产环境使用明确的版本号，不要使用latest
- 🔒 **安全建议**：定期扫描镜像漏洞，及时更新基础镜像
- 💰 **成本优化**：ACR个人版完全免费，放心使用

### 📖 扩展阅读

**其他语言的Dockerfile示例**

**Python应用**：
```dockerfile
# 多阶段构建 - Python
FROM python:3.11-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --user -r requirements.txt

FROM python:3.11-slim
WORKDIR /app
COPY --from=builder /root/.local /root/.local
COPY . .
ENV PATH=/root/.local/bin:$PATH
CMD ["python", "app.py"]
```

**Node.js应用**：
```dockerfile
# 多阶段构建 - Node.js
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

FROM node:18-alpine
WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY . .
CMD ["node", "server.js"]
```

---

**导航**：
- **上一步**：[模块4：配置ALB Ingress](/blog/devops/posts/2026-01-29-ack-sop-04-alb-ingress/)
- **下一步**：[模块6：部署应用到K8s](/blog/devops/posts/2026-01-29-ack-sop-06-deploy-app/)
- **返回主索引**：[阿里云ACK部署SOP](/blog/devops/posts/2026-01-29-aliyun-ack-deployment-sop/)