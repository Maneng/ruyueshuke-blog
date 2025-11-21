---
title: "MySQL安装与环境配置"
date: 2025-11-21T11:00:00+08:00
draft: false
tags: ["MySQL", "安装部署", "基础入门"]
categories: ["技术"]
description: "手把手教你在Windows、Linux、macOS三大平台安装MySQL，掌握Docker快速部署和常用客户端工具"
series: ["MySQL从入门到精通"]
weight: 3
stage: 1
stageTitle: "基础入门篇"
---

## 引言

### 提出问题

前两篇文章中，我们理解了数据库的重要性和MySQL的核心优势。但是：

- **如何在自己的电脑上安装MySQL？**
- Windows、Mac、Linux系统的安装方式有什么区别？
- 如何快速搭建MySQL开发环境（Docker）？
- 安装后如何连接和使用MySQL？
- 有哪些好用的MySQL客户端工具？

**这篇文章将带你动手实战，从零开始搭建MySQL开发环境！**

### 为什么重要

"工欲善其事，必先利其器"。正确安装和配置MySQL是学习的第一步：

- ✅ 环境搭建好，后续学习才能顺畅
- ✅ 掌握多平台安装，适应不同工作环境
- ✅ 了解配置文件，为后续性能调优打基础
- ✅ 熟悉客户端工具，提升开发效率

---

## 基础概念

### MySQL的三种安装方式

#### 方式1：官方安装包（推荐新手）

**特点**：
- ✅ 安装简单，图形化界面
- ✅ 自动配置环境变量
- ✅ 集成MySQL Workbench客户端
- ❌ 版本更新需要重新下载安装包

**适用场景**：
- 开发环境
- 学习测试
- Windows/macOS用户

#### 方式2：包管理器（推荐Linux用户）

**特点**：
- ✅ 命令行一键安装
- ✅ 版本更新方便（apt upgrade/yum update）
- ✅ 自动处理依赖关系
- ❌ 版本可能不是最新

**适用场景**：
- Linux服务器
- CI/CD自动化
- 开发环境

#### 方式3：Docker容器（推荐进阶用户）

**特点**：
- ✅ 环境隔离，不污染主机
- ✅ 秒级启动和销毁
- ✅ 版本切换方便
- ❌ 需要掌握Docker基础

**适用场景**：
- 快速测试
- 多版本切换
- 微服务开发

---

## Windows系统安装

### 方式一：MSI安装包（推荐）

#### 步骤1：下载MySQL安装包

访问MySQL官网：https://dev.mysql.com/downloads/mysql/

选择：
- 版本：MySQL 8.0（最新GA版本）
- 操作系统：Microsoft Windows
- 安装类型：mysql-installer-community-8.0.xx.0.msi

**两种安装包**：
- `mysql-installer-web-community-8.0.xx.0.msi`（2MB）：在线安装，需联网下载
- `mysql-installer-community-8.0.xx.0.msi`（400MB）：离线安装，推荐

#### 步骤2：运行安装程序

双击 `.msi` 文件，选择安装类型：

1. **Developer Default**（开发者默认）- 推荐
   - 包含MySQL Server、Workbench、Shell、Router等
   - 适合学习和开发

2. **Server only**（仅服务器）
   - 只安装MySQL Server
   - 适合生产环境

3. **Full**（完整安装）
   - 安装所有组件
   - 体积大（500MB+）

4. **Custom**（自定义）
   - 自选组件

**建议选择**：Developer Default

#### 步骤3：配置MySQL Server

**Type and Networking（类型和网络）**：
```
Config Type: Development Computer（开发计算机）
Port: 3306（默认端口）
Open Windows Firewall: ✓（打开防火墙）
```

**Authentication Method（身份验证方法）**：
```
推荐：Use Strong Password Encryption for Authentication (RECOMMENDED)
（使用强密码加密 - MySQL 8.0默认）
```

**Accounts and Roles（账户和角色）**：
```
Root Password: 设置root密码（重要！不要忘记）
  建议：MySQL_123456（开发环境）
  生产环境：复杂密码 + 定期更换
```

**可选：创建额外的用户**
```
Username: developer
Password: Dev_123456
Role: DB Admin
```

**Windows Service（Windows服务）**：
```
✓ Configure MySQL Server as a Windows Service
Service Name: MySQL80（默认）
✓ Start the MySQL Server at System Startup（开机自启）
Run Windows Service as: Standard System Account（标准系统账户）
```

#### 步骤4：完成安装

点击 "Execute" 执行安装，等待完成。

#### 步骤5：验证安装

打开命令提示符（CMD）或PowerShell：

```cmd
# 查看MySQL版本
mysql --version

# 输出示例：
# mysql  Ver 8.0.35 for Win64 on x86_64 (MySQL Community Server - GPL)

# 连接MySQL
mysql -u root -p

# 输入密码后，看到以下提示说明安装成功：
mysql>
```

---

## macOS系统安装

### 方式一：DMG安装包（推荐新手）

#### 步骤1：下载MySQL安装包

访问：https://dev.mysql.com/downloads/mysql/

选择：
- 版本：MySQL 8.0
- 操作系统：macOS
- 芯片：
  - Intel芯片：x86, 64-bit
  - Apple Silicon（M1/M2/M3）：ARM, 64-bit

下载：`mysql-8.0.xx-macos-xxx.dmg`

#### 步骤2：安装MySQL

1. 双击 `.dmg` 文件
2. 双击 `.pkg` 安装包
3. 按照提示完成安装
4. **重要**：安装完成时会弹出临时root密码，**必须记录**！

```
2024-01-15T10:30:00.123456Z 6 [Note] A temporary password is generated for root@localhost: Abc#1234Def
```

#### 步骤3：启动MySQL

**方法1：系统偏好设置**
1. 打开"系统偏好设置"
2. 找到"MySQL"图标
3. 点击"Start MySQL Server"

**方法2：命令行**
```bash
# 启动MySQL
sudo /usr/local/mysql/support-files/mysql.server start

# 停止MySQL
sudo /usr/local/mysql/support-files/mysql.server stop

# 重启MySQL
sudo /usr/local/mysql/support-files/mysql.server restart
```

#### 步骤4：配置环境变量

```bash
# 编辑bash配置文件（如果使用zsh，编辑 ~/.zshrc）
nano ~/.bash_profile

# 添加以下内容：
export PATH=$PATH:/usr/local/mysql/bin

# 保存退出（Ctrl+O, Enter, Ctrl+X）

# 使配置生效
source ~/.bash_profile
```

#### 步骤5：修改root密码

```bash
# 使用临时密码登录
mysql -u root -p

# 输入临时密码后，执行以下SQL：
mysql> ALTER USER 'root'@'localhost' IDENTIFIED BY 'MySQL_123456';
Query OK, 0 rows affected (0.01 sec)

mysql> FLUSH PRIVILEGES;
Query OK, 0 rows affected (0.00 sec)
```

### 方式二：Homebrew安装（推荐进阶用户）

Homebrew是macOS的包管理器，安装更简单。

#### 步骤1：安装Homebrew（如已安装跳过）

```bash
# 访问 https://brew.sh/ 获取最新安装命令
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

#### 步骤2：安装MySQL

```bash
# 搜索MySQL版本
brew search mysql

# 安装最新版MySQL
brew install mysql

# 安装特定版本（如MySQL 5.7）
brew install mysql@5.7
```

#### 步骤3：启动MySQL

```bash
# 启动MySQL服务
brew services start mysql

# 开机自启
brew services restart mysql

# 停止MySQL服务
brew services stop mysql
```

#### 步骤4：初始化（首次安装）

```bash
# 运行安全配置脚本
mysql_secure_installation

# 按提示操作：
# 1. 设置root密码
# 2. 删除匿名用户
# 3. 禁止root远程登录
# 4. 删除test数据库
```

---

## Linux系统安装

### Ubuntu/Debian系统

#### 方式一：APT包管理器（推荐）

```bash
# 1. 更新软件包列表
sudo apt update

# 2. 安装MySQL Server
sudo apt install mysql-server

# 3. 启动MySQL服务
sudo systemctl start mysql

# 4. 设置开机自启
sudo systemctl enable mysql

# 5. 检查服务状态
sudo systemctl status mysql

# 6. 运行安全配置
sudo mysql_secure_installation
```

#### 方式二：官方APT仓库（获取最新版本）

```bash
# 1. 下载MySQL APT配置包
wget https://dev.mysql.com/get/mysql-apt-config_0.8.29-1_all.deb

# 2. 安装配置包
sudo dpkg -i mysql-apt-config_0.8.29-1_all.deb

# 选择MySQL版本（默认mysql-8.0）

# 3. 更新软件包列表
sudo apt update

# 4. 安装MySQL
sudo apt install mysql-server

# 5. 启动服务
sudo systemctl start mysql
```

### CentOS/RHEL系统

```bash
# 1. 下载MySQL Yum仓库
sudo yum install https://dev.mysql.com/get/mysql80-community-release-el7-7.noarch.rpm

# 2. 安装MySQL Server
sudo yum install mysql-community-server

# 3. 启动MySQL服务
sudo systemctl start mysqld

# 4. 设置开机自启
sudo systemctl enable mysqld

# 5. 获取临时root密码
sudo grep 'temporary password' /var/log/mysqld.log

# 6. 修改root密码
mysql -u root -p
# 输入临时密码

mysql> ALTER USER 'root'@'localhost' IDENTIFIED BY 'MySQL_123!@#';
```

---

## Docker安装（跨平台，推荐）

### 前提条件

已安装Docker Desktop（Windows/macOS）或Docker Engine（Linux）。

### 方式一：快速启动（单命令）

```bash
# 启动MySQL 8.0容器
docker run -d \
  --name mysql80 \
  -p 3306:3306 \
  -e MYSQL_ROOT_PASSWORD=MySQL_123456 \
  mysql:8.0

# 参数说明：
# -d: 后台运行
# --name mysql80: 容器名称
# -p 3306:3306: 端口映射（主机:容器）
# -e MYSQL_ROOT_PASSWORD: root密码
# mysql:8.0: 镜像名称和版本
```

### 方式二：数据持久化（推荐生产）

```bash
# 创建数据卷
docker volume create mysql-data

# 启动MySQL容器
docker run -d \
  --name mysql80 \
  -p 3306:3306 \
  -e MYSQL_ROOT_PASSWORD=MySQL_123456 \
  -e MYSQL_DATABASE=mydb \
  -e MYSQL_USER=developer \
  -e MYSQL_PASSWORD=Dev_123456 \
  -v mysql-data:/var/lib/mysql \
  mysql:8.0

# 参数说明：
# -v mysql-data:/var/lib/mysql: 挂载数据卷，数据持久化
# -e MYSQL_DATABASE: 自动创建数据库
# -e MYSQL_USER: 创建普通用户
```

### 方式三：docker-compose（团队协作推荐）

创建 `docker-compose.yml` 文件：

```yaml
version: '3.8'

services:
  mysql:
    image: mysql:8.0
    container_name: mysql80
    restart: unless-stopped
    ports:
      - "3306:3306"
    environment:
      MYSQL_ROOT_PASSWORD: MySQL_123456
      MYSQL_DATABASE: mydb
      MYSQL_USER: developer
      MYSQL_PASSWORD: Dev_123456
    volumes:
      - mysql-data:/var/lib/mysql
      - ./my.cnf:/etc/mysql/conf.d/my.cnf
    command: --default-authentication-plugin=mysql_native_password

volumes:
  mysql-data:
```

启动：
```bash
# 启动容器
docker-compose up -d

# 查看日志
docker-compose logs -f mysql

# 停止容器
docker-compose down
```

### Docker常用操作

```bash
# 查看运行中的容器
docker ps

# 连接MySQL容器
docker exec -it mysql80 mysql -u root -p

# 查看容器日志
docker logs mysql80

# 停止容器
docker stop mysql80

# 启动容器
docker start mysql80

# 删除容器（数据会丢失！）
docker rm -f mysql80

# 删除数据卷（谨慎！）
docker volume rm mysql-data
```

---

## MySQL配置文件详解

### 配置文件位置

| 操作系统 | 配置文件路径 |
|---------|-------------|
| **Windows** | `C:\ProgramData\MySQL\MySQL Server 8.0\my.ini` |
| **macOS** | `/etc/my.cnf` 或 `/usr/local/mysql/my.cnf` |
| **Linux** | `/etc/mysql/my.cnf` 或 `/etc/my.cnf` |
| **Docker** | 通过 `-v` 挂载自定义配置 |

### 常用配置项

创建 `my.cnf` 文件：

```ini
[mysqld]
# 基础配置
port = 3306
datadir = /var/lib/mysql
socket = /var/lib/mysql/mysql.sock

# 字符集设置（重要！）
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

# 连接设置
max_connections = 200          # 最大连接数
max_connect_errors = 10        # 最大连接错误次数

# InnoDB设置
innodb_buffer_pool_size = 1G   # 缓冲池大小（建议物理内存的50-70%）
innodb_log_file_size = 256M    # redo log大小
innodb_flush_log_at_trx_commit = 1  # 事务提交时刷盘策略

# 日志设置
log_error = /var/log/mysql/error.log
slow_query_log = 1             # 开启慢查询日志
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = 2            # 慢查询阈值（秒）

# 二进制日志（主从复制）
log_bin = /var/log/mysql/mysql-bin.log
expire_logs_days = 7           # binlog保留天数

[mysql]
# 客户端默认字符集
default-character-set = utf8mb4

[client]
port = 3306
socket = /var/lib/mysql/mysql.sock
```

### 重启MySQL使配置生效

```bash
# Windows
net stop MySQL80
net start MySQL80

# macOS/Linux
sudo systemctl restart mysql

# Docker
docker restart mysql80
```

---

## MySQL客户端工具

### 1. MySQL Command Line（命令行）

**内置工具，轻量高效**

```bash
# 连接本地MySQL
mysql -u root -p

# 连接远程MySQL
mysql -h 192.168.1.100 -P 3306 -u root -p

# 指定数据库
mysql -u root -p mydb

# 执行SQL文件
mysql -u root -p < init.sql

# 导出数据
mysqldump -u root -p mydb > backup.sql
```

**优点**：
- ✅ 轻量级，启动快
- ✅ 适合自动化脚本
- ✅ 服务器环境必备

**缺点**：
- ❌ 界面简陋
- ❌ 不适合复杂查询
- ❌ 新手不友好

### 2. MySQL Workbench（官方GUI，免费）

**下载**：https://dev.mysql.com/downloads/workbench/

**特点**：
- ✅ 官方出品，功能全面
- ✅ 可视化数据库设计（ER图）
- ✅ SQL编辑器（语法高亮、自动补全）
- ✅ 数据库管理（备份、恢复、用户管理）
- ✅ 性能监控

**适用场景**：
- 数据库设计
- SQL开发
- 数据库管理

### 3. Navicat（商业软件，功能最强）

**官网**：https://www.navicat.com.cn/

**特点**：
- ✅ 界面美观，易用性最好
- ✅ 支持多种数据库（MySQL、PostgreSQL、Oracle）
- ✅ 数据同步、结构同步
- ✅ 数据备份、定时任务
- ✅ SSH隧道、SSL连接
- ❌ 收费（约1400元/年）

**适用场景**：
- 企业开发
- 数据库运维
- 多数据库管理

### 4. DBeaver（免费开源，强大）

**官网**：https://dbeaver.io/

**特点**：
- ✅ 完全免费开源
- ✅ 支持几乎所有数据库
- ✅ SQL编辑器强大
- ✅ ER图设计
- ✅ 数据可视化
- ❌ 启动稍慢（基于Java）

**适用场景**：
- 多数据库环境
- 开源技术栈
- 预算有限的团队

### 5. DataGrip（JetBrains，收费）

**官网**：https://www.jetbrains.com/datagrip/

**特点**：
- ✅ JetBrains出品，IDE级别体验
- ✅ 智能补全、重构
- ✅ 版本控制集成
- ✅ 支持所有主流数据库
- ❌ 收费（约800元/年）

**适用场景**：
- 已使用JetBrains全家桶
- 对代码质量要求高
- 大型项目开发

---

## 实战：首次连接MySQL

### 使用命令行连接

```bash
# 连接MySQL
mysql -u root -p

# 输入密码后，看到提示符：
mysql>

# 查看数据库列表
mysql> SHOW DATABASES;
+--------------------+
| Database           |
+--------------------+
| information_schema |
| mysql              |
| performance_schema |
| sys                |
+--------------------+
4 rows in set (0.00 sec)

# 查看当前用户
mysql> SELECT USER();
+----------------+
| USER()         |
+----------------+
| root@localhost |
+----------------+
1 row in set (0.00 sec)

# 查看MySQL版本
mysql> SELECT VERSION();
+-----------+
| VERSION() |
+-----------+
| 8.0.35    |
+-----------+
1 row in set (0.00 sec)

# 退出MySQL
mysql> EXIT;
Bye
```

### 使用Workbench连接

1. 打开MySQL Workbench
2. 点击"+"创建新连接
3. 填写连接信息：
   - Connection Name: 本地MySQL
   - Connection Method: Standard (TCP/IP)
   - Hostname: 127.0.0.1
   - Port: 3306
   - Username: root
   - Password: 点击"Store in Keychain"输入密码
4. 点击"Test Connection"测试连接
5. 连接成功后，双击连接进入SQL编辑器

---

## 常见问题排查

### 问题1：连接被拒绝（Connection refused）

**原因**：
- MySQL服务未启动
- 端口被占用

**解决**：
```bash
# 检查MySQL服务状态
# Windows
sc query MySQL80

# macOS/Linux
sudo systemctl status mysql

# 启动MySQL服务
sudo systemctl start mysql
```

### 问题2：访问被拒绝（Access denied）

**原因**：
- 密码错误
- 用户不存在
- 权限不足

**解决**：
```bash
# 重置root密码（仅开发环境）
# 1. 停止MySQL服务
sudo systemctl stop mysql

# 2. 跳过权限启动
sudo mysqld_safe --skip-grant-tables &

# 3. 无密码登录
mysql -u root

# 4. 重置密码
mysql> FLUSH PRIVILEGES;
mysql> ALTER USER 'root'@'localhost' IDENTIFIED BY 'NewPassword123!';
mysql> EXIT;

# 5. 正常启动MySQL
sudo systemctl start mysql
```

### 问题3：端口3306被占用

**检查端口占用**：
```bash
# Windows
netstat -ano | findstr 3306

# macOS/Linux
lsof -i :3306
```

**解决**：
- 关闭占用端口的程序
- 或修改MySQL端口（在my.cnf中设置）

### 问题4：字符集乱码

**检查字符集**：
```sql
SHOW VARIABLES LIKE 'character%';
```

**设置为utf8mb4**（在my.cnf）：
```ini
[mysqld]
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

[mysql]
default-character-set = utf8mb4
```

---

## 最佳实践

### 安全配置建议

1. **设置强密码**：
   - 至少12位
   - 包含大小写字母、数字、特殊字符

2. **禁止root远程登录**（生产环境）：
```sql
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
FLUSH PRIVILEGES;
```

3. **创建普通用户**：
```sql
CREATE USER 'developer'@'localhost' IDENTIFIED BY 'Dev_123456';
GRANT ALL PRIVILEGES ON mydb.* TO 'developer'@'localhost';
FLUSH PRIVILEGES;
```

4. **定期备份**：
```bash
# 自动备份脚本
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
mysqldump -u root -p'MySQL_123456' --all-databases > /backup/mysql_$DATE.sql
```

### 性能优化建议

1. **合理设置innodb_buffer_pool_size**：
   - 开发环境：512M - 1G
   - 生产环境：物理内存的50-70%

2. **开启慢查询日志**（开发环境）：
```ini
[mysqld]
slow_query_log = 1
long_query_time = 2
```

3. **关闭查询缓存**（MySQL 8.0已默认关闭）：
   - MySQL 8.0移除了查询缓存功能

---

## 总结

### 核心要点

1. **三种安装方式**：
   - 官方安装包：图形化，适合新手
   - 包管理器：命令行，适合Linux
   - Docker：环境隔离，适合开发测试

2. **关键配置**：
   - 字符集：utf8mb4
   - 端口：3306（默认）
   - root密码：强密码，妥善保管

3. **客户端工具**：
   - 命令行：轻量高效
   - Workbench：官方免费
   - Navicat：商业最强
   - DBeaver：开源免费

4. **初次连接**：
   - 检查服务状态
   - 使用正确的用户名和密码
   - 测试基本SQL命令

### 记忆口诀

**MySQL安装三步走：下、装、连**
- **下**：官网下载对应平台安装包
- **装**：按提示安装并设置root密码
- **连**：使用客户端工具连接测试

### 实践建议

1. **动手安装**：选择一种方式，实际安装一遍
2. **熟悉命令**：记住常用的启动、停止、连接命令
3. **工具尝试**：至少安装一个GUI工具（推荐Workbench或DBeaver）
4. **备份配置**：保存好my.cnf配置文件和root密码

### 下一步学习

- **前置知识**：上一篇《MySQL简介：历史、特点与应用场景》
- **后续推荐**：下一篇《数据库与表的创建：DDL基础》，开始学习SQL语句
- **实战项目**：安装完成后，可以导入示例数据库sakila进行练习

---

## 参考资料

1. [MySQL官方文档 - 安装指南](https://dev.mysql.com/doc/refman/8.0/en/installing.html)
2. [Docker Hub - MySQL镜像](https://hub.docker.com/_/mysql)
3. [MySQL Workbench用户手册](https://dev.mysql.com/doc/workbench/en/)
4. [MySQL配置文件参考](https://dev.mysql.com/doc/refman/8.0/en/option-files.html)

---

**系列文章导航**：
- 上一篇：《MySQL简介：历史、特点与应用场景》
- 下一篇：《数据库与表的创建：DDL基础》
- 返回目录：[MySQL从入门到精通](/mysql/)

---

> 💡 **提示**：本文是 "MySQL从入门到精通" 系列的第 3 篇（共86篇），从第一性原理出发，系统化掌握MySQL。
>
> 📚 **学习建议**：安装完成后，建议立即打开MySQL，执行几个简单的SQL命令熟悉环境。
>
> 🤝 **交流讨论**：如果安装过程中遇到问题，欢迎在评论区留言，我会及时回复！
