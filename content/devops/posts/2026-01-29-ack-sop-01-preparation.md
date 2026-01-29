---
title: "ACK部署SOP-01：准备工作（账号、工具、环境）"
date: 2026-01-29T10:01:00+08:00
draft: false
tags: ["Kubernetes", "阿里云", "ACK", "DevOps", "kubectl", "Docker"]
categories: ["DevOps"]
series: ["ACK部署SOP"]
weight: 2
description: "阿里云ACK部署第一步：注册账号、实名认证、充值、安装kubectl和Docker Desktop，为K8s集群部署做好准备"
---

## 🎯 本章目标

完成阿里云ACK部署的所有准备工作，包括：
- ✅ 注册阿里云账号并完成实名认证
- ✅ 充值账户并开通必要服务
- ✅ 在本地安装kubectl命令行工具
- ✅ 在本地安装Docker Desktop
- ✅ 验证所有工具安装成功

**预计时间**：30分钟  
**预计费用**：¥0（仅充值，暂不产生费用）

## 📋 准备工作清单

在开始之前，请准备好：
- [ ] 一台电脑（Windows 10+、macOS 10.15+、或Linux）
- [ ] 稳定的网络连接
- [ ] 手机（用于接收验证码）
- [ ] 身份证（用于实名认证）
- [ ] 银行卡或支付宝（用于充值）

---

## 第一部分：阿里云账号准备

### 步骤1.1：注册阿里云账号

#### 🎬 操作说明
如果你已经有阿里云账号，可以跳过这一步。如果没有，我们现在来注册一个。

#### 📍 详细步骤

**第1步：打开阿里云官网**
- 在浏览器中输入：`https://www.aliyun.com`
- 按回车键访问阿里云官网
- 你会看到阿里云的首页，上面有很多产品介绍

**第2步：点击注册按钮**
- 在页面右上角，找到"免费注册"按钮
- 按钮通常是橙色或蓝色的，很显眼
- 点击"免费注册"按钮

**第3步：选择注册方式**
- 你会看到两种注册方式：
  - 手机号注册（推荐）
  - 邮箱注册
- 我们选择"手机号注册"（更方便）

**第4步：填写注册信息**
- 输入你的手机号码（11位数字）
- 点击"获取验证码"按钮
- 等待手机收到验证码（通常10秒内到达）
- 输入收到的6位验证码
- 设置登录密码（建议8位以上，包含字母和数字）
- 勾选"我已阅读并同意《阿里云服务协议》"
- 点击"注册"按钮

**第5步：完成注册**
- 注册成功后，页面会自动跳转
- 你会看到"注册成功"的提示
- 现在你已经有了一个阿里云账号

#### ✅ 验证点
- 确认收到阿里云的欢迎短信
- 确认可以用手机号和密码登录阿里云控制台
- 登录后能看到阿里云控制台首页

#### ⚠️ 常见问题

**问题1：收不到验证码怎么办？**
- 答：等待1-2分钟，验证码可能延迟
- 检查手机是否欠费或信号不好
- 尝试使用邮箱注册方式

**问题2：提示手机号已注册？**
- 答：说明你之前已经注册过
- 直接使用"忘记密码"功能重置密码
- 或者使用其他手机号注册

### 步骤1.2：完成实名认证

#### 🎬 操作说明
阿里云要求所有用户完成实名认证才能购买资源。我们现在来完成这个步骤。

#### 📍 详细步骤

**第1步：进入实名认证页面**
- 登录阿里云控制台：`https://homenew.console.aliyun.com`
- 在页面右上角，点击你的头像或用户名
- 在下拉菜单中，点击"实名认证"
- 或者直接访问：`https://account.console.aliyun.com/v2/#/authc/home`

**第2步：选择认证类型**
- 你会看到两种认证类型：
  - 个人实名认证（推荐个人用户）
  - 企业实名认证（需要营业执照）
- 我们选择"个人实名认证"
- 点击"立即认证"按钮

**第3步：选择认证方式**
- 阿里云提供三种认证方式：
  - 支付宝认证（最快，推荐）
  - 人脸识别认证
  - 银行卡认证
- 我们选择"支付宝认证"（最方便）

**第4步：使用支付宝认证**
- 页面会显示一个二维码
- 打开手机支付宝APP
- 点击右上角的"扫一扫"
- 扫描页面上的二维码
- 在支付宝中确认授权
- 等待认证完成（通常10秒内）

**第5步：确认认证成功**
- 页面会显示"实名认证成功"
- 你的姓名和身份证号会显示在页面上
- 现在你可以购买阿里云资源了

#### ✅ 验证点
- 确认页面显示"已实名认证"
- 确认能看到你的真实姓名
- 确认认证类型为"个人"

#### ⚠️ 常见问题

**问题1：支付宝认证失败？**
- 答：确保支付宝已完成实名认证
- 确保支付宝绑定的身份证信息正确
- 可以尝试其他认证方式（人脸识别）

**问题2：认证需要多长时间？**
- 答：支付宝认证通常10秒内完成
- 人脸识别认证需要1-2分钟
- 银行卡认证需要1-3个工作日

### 步骤1.3：账户充值

#### 🎬 操作说明
为了避免在部署过程中因余额不足而中断，我们先给账户充值。

#### 📍 详细步骤

**第1步：进入充值页面**
- 在阿里云控制台首页
- 点击右上角的"费用"菜单
- 在下拉菜单中，点击"充值"
- 或者直接访问：`https://usercenter2.aliyun.com/finance/prepay`

**第2步：选择充值金额**
- 页面会显示几个预设金额：100元、500元、1000元等
- 建议充值金额：**500元**（足够完成本教程的所有操作）
- 你也可以自定义充值金额
- 输入充值金额后，点击"立即充值"

**第3步：选择支付方式**
- 阿里云支持多种支付方式：
  - 支付宝（推荐，到账最快）
  - 网银支付
  - 微信支付
- 我们选择"支付宝"
- 点击"确认支付"按钮

**第4步：完成支付**
- 页面会跳转到支付宝支付页面
- 使用支付宝扫码支付
- 或者在手机上打开支付宝完成支付
- 支付成功后，页面会自动跳转回阿里云

**第5步：确认到账**
- 返回阿里云控制台
- 点击右上角的"费用"菜单
- 查看"账户余额"
- 确认余额已增加

#### ✅ 验证点
- 确认账户余额≥500元
- 确认收到阿里云的充值成功短信
- 确认可以在"费用中心"看到充值记录

#### 💡 小贴士
- 充值金额会立即到账，无需等待
- 未使用的余额可以随时提现（需要1-3个工作日）
- 建议开启"余额预警"，余额不足时会收到通知

---

## 第二部分：安装kubectl工具

### 步骤2.1：下载kubectl

#### 🎬 操作说明
kubectl是Kubernetes的命令行工具，用于管理K8s集群。我们需要在本地安装它。

#### 📍 详细步骤（macOS）

**第1步：打开终端**
- 按下 `Command + 空格` 打开Spotlight搜索
- 输入"终端"或"Terminal"
- 按回车键打开终端

**第2步：使用Homebrew安装kubectl**
- 如果你已经安装了Homebrew，直接运行：
```bash
brew install kubectl
```
- 如果没有安装Homebrew，先安装Homebrew：
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```
- 然后再安装kubectl

**第3步：等待安装完成**
- 安装过程需要1-3分钟
- 你会看到下载和安装的进度信息
- 看到"kubectl was successfully installed"表示安装成功

#### 📍 详细步骤（Windows）

**第1步：下载kubectl**
- 访问：`https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/`
- 点击"Download kubectl"链接
- 下载kubectl.exe文件到本地（例如：`C:\kubectl\kubectl.exe`）

**第2步：配置环境变量**
- 右键点击"此电脑"，选择"属性"
- 点击"高级系统设置"
- 点击"环境变量"按钮
- 在"系统变量"中找到"Path"
- 点击"编辑"，然后点击"新建"
- 输入kubectl.exe所在的目录（例如：`C:\kubectl`）
- 点击"确定"保存

**第3步：验证安装**
- 打开命令提示符（CMD）或PowerShell
- 输入：`kubectl version --client`
- 如果看到版本信息，说明安装成功

#### 📍 详细步骤（Linux）

**第1步：下载kubectl**
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
```

**第2步：安装kubectl**
```bash
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

**第3步：验证安装**
```bash
kubectl version --client
```

#### ✅ 验证点
- 在终端或命令提示符中运行：`kubectl version --client`
- 应该看到类似这样的输出：
```
Client Version: v1.28.0
Kustomize Version: v5.0.4-0.20230601165947-6ce0bf390ce3
```
- 确认版本号≥1.26.0

#### ⚠️ 常见问题

**问题1：提示"kubectl: command not found"？**
- 答：说明kubectl没有正确安装或环境变量没有配置
- macOS：重新运行`brew install kubectl`
- Windows：检查环境变量Path是否正确配置
- Linux：检查kubectl是否在/usr/local/bin目录

**问题2：kubectl版本太旧？**
- 答：运行更新命令
- macOS：`brew upgrade kubectl`
- Windows：重新下载最新版本
- Linux：重新下载并安装

### 步骤2.2：配置kubectl自动补全（可选）

#### 🎬 操作说明
配置自动补全可以让kubectl使用更方便，按Tab键可以自动补全命令。

#### 📍 详细步骤（macOS/Linux - Bash）

```bash
# 安装bash-completion
brew install bash-completion  # macOS
sudo apt-get install bash-completion  # Ubuntu/Debian

# 配置kubectl自动补全
echo 'source <(kubectl completion bash)' >> ~/.bashrc
source ~/.bashrc
```

#### 📍 详细步骤（macOS/Linux - Zsh）

```bash
# 配置kubectl自动补全
echo 'source <(kubectl completion zsh)' >> ~/.zshrc
source ~/.zshrc
```

#### ✅ 验证点
- 在终端中输入：`kubectl get po` 然后按Tab键
- 应该能看到自动补全的建议（如：pods、podtemplates等）

---

## 第三部分：安装Docker Desktop

### 步骤3.1：下载Docker Desktop

#### 🎬 操作说明
Docker Desktop是Docker的桌面版本，包含了Docker引擎和图形界面，方便我们构建和测试Docker镜像。

#### 📍 详细步骤（macOS）

**第1步：访问Docker官网**
- 在浏览器中访问：`https://www.docker.com/products/docker-desktop/`
- 点击"Download for Mac"按钮
- 选择你的Mac芯片类型：
  - Apple Silicon（M1/M2/M3芯片）
  - Intel芯片

**第2步：下载安装包**
- 下载Docker.dmg文件（约500MB）
- 下载时间取决于网速，通常需要5-10分钟

**第3步：安装Docker Desktop**
- 双击下载的Docker.dmg文件
- 将Docker图标拖到Applications文件夹
- 等待复制完成（约1分钟）

**第4步：启动Docker Desktop**
- 打开Applications文件夹
- 双击Docker图标启动
- 首次启动需要输入Mac密码授权
- 等待Docker启动（约30秒）

**第5步：完成配置**
- Docker Desktop会显示欢迎界面
- 可以选择跳过教程
- 看到Docker图标在菜单栏显示，说明启动成功

#### 📍 详细步骤（Windows）

**第1步：检查系统要求**
- Windows 10 64位：专业版、企业版或教育版（Build 19041或更高）
- 或Windows 11 64位
- 启用WSL 2功能

**第2步：启用WSL 2**
- 以管理员身份打开PowerShell
- 运行以下命令：
```powershell
wsl --install
```
- 重启电脑

**第3步：下载Docker Desktop**
- 访问：`https://www.docker.com/products/docker-desktop/`
- 点击"Download for Windows"按钮
- 下载Docker Desktop Installer.exe（约500MB）

**第4步：安装Docker Desktop**
- 双击下载的安装程序
- 勾选"Use WSL 2 instead of Hyper-V"
- 点击"OK"开始安装
- 等待安装完成（约5分钟）
- 点击"Close and restart"重启电脑

**第5步：启动Docker Desktop**
- 重启后，Docker Desktop会自动启动
- 如果没有自动启动，从开始菜单打开Docker Desktop
- 接受服务协议
- 等待Docker启动（约30秒）

#### 📍 详细步骤（Linux）

**第1步：安装Docker Engine**
```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install docker.io
sudo systemctl start docker
sudo systemctl enable docker

# 添加当前用户到docker组
sudo usermod -aG docker $USER
newgrp docker
```

**第2步：验证安装**
```bash
docker --version
```

#### ✅ 验证点
- Docker Desktop图标在系统托盘显示（macOS在菜单栏，Windows在任务栏）
- 图标显示为绿色（表示运行中）
- 在终端运行：`docker --version`，应该看到版本信息
- 在终端运行：`docker ps`，应该看到空的容器列表（不报错）

#### ⚠️ 常见问题

**问题1：Docker Desktop启动失败？**
- 答：检查系统是否满足要求
- macOS：确保系统版本≥10.15
- Windows：确保已启用WSL 2
- 尝试重启电脑后再启动

**问题2：提示"Docker daemon is not running"？**
- 答：Docker服务没有启动
- 手动启动Docker Desktop应用
- 等待30秒让Docker完全启动

**问题3：Windows上提示需要启用虚拟化？**
- 答：需要在BIOS中启用虚拟化功能
- 重启电脑，进入BIOS设置
- 找到"Virtualization Technology"或"VT-x"
- 设置为"Enabled"
- 保存并重启

### 步骤3.2：测试Docker

#### 🎬 操作说明
运行一个简单的Docker容器，验证Docker是否正常工作。

#### 📍 详细步骤

**第1步：打开终端**
- macOS：打开Terminal
- Windows：打开PowerShell或CMD
- Linux：打开终端

**第2步：运行测试容器**
```bash
docker run hello-world
```

**第3步：查看输出**
- 你应该看到类似这样的输出：
```
Hello from Docker!
This message shows that your installation appears to be working correctly.
...
```

**第4步：清理测试容器**
```bash
# 查看所有容器
docker ps -a

# 删除测试容器
docker rm $(docker ps -aq)

# 删除测试镜像
docker rmi hello-world
```

#### ✅ 验证点
- 成功运行hello-world容器
- 看到"Hello from Docker!"消息
- 能够列出和删除容器

---

## 第四部分：验证所有工具

### 步骤4.1：综合验证

#### 🎬 操作说明
现在我们来验证所有工具都已正确安装。

#### 📍 详细步骤

**第1步：验证kubectl**
```bash
kubectl version --client
```
期望输出：显示kubectl版本信息

**第2步：验证Docker**
```bash
docker --version
docker ps
```
期望输出：显示Docker版本信息和空的容器列表

**第3步：验证阿里云账号**
- 访问：`https://homenew.console.aliyun.com`
- 确认能够登录
- 确认已完成实名认证
- 确认账户余额≥500元

#### ✅ 验证清单

请确认以下所有项目都已完成：
- [ ] 阿里云账号已注册
- [ ] 已完成实名认证
- [ ] 账户余额≥500元
- [ ] kubectl已安装（版本≥1.26.0）
- [ ] Docker Desktop已安装并运行
- [ ] 能够运行docker命令
- [ ] 能够运行kubectl命令

---

## 🎉 恭喜！准备工作完成

你已经完成了所有准备工作，现在可以开始创建K8s集群了！

### 📊 完成情况总结

| 项目 | 状态 | 说明 |
|-----|------|------|
| 阿里云账号 | ✅ | 已注册并实名认证 |
| 账户余额 | ✅ | ≥500元 |
| kubectl工具 | ✅ | 已安装并验证 |
| Docker Desktop | ✅ | 已安装并运行 |

### 💰 费用统计

| 项目 | 费用 |
|-----|------|
| 账号注册 | ¥0 |
| 实名认证 | ¥0 |
| 工具安装 | ¥0 |
| 账户充值 | ¥500（预充值） |
| **本章总计** | **¥0（仅充值）** |

### 🚀 下一步

现在让我们进入第二步：创建VPC网络

👉 [点击进入：02-网络配置](/blog/devops/posts/2026-01-29-ack-sop-02-vpc-network/)

---

## 📚 相关文档

- [返回总览](/blog/devops/posts/2026-01-29-aliyun-ack-deployment-sop/)
- [下一步：02-网络配置](/blog/devops/posts/2026-01-29-ack-sop-02-vpc-network/)
- [kubectl官方文档](https://kubernetes.io/docs/reference/kubectl/)
- [Docker官方文档](https://docs.docker.com/)
