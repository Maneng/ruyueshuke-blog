---
title: "Redis快速入门：安装部署与基本操作"
date: 2025-01-21T10:30:00+08:00
draft: false
tags: ["Redis", "安装部署", "入门教程", "redis-cli"]
categories: ["技术"]
description: "快速上手Redis，从安装到第一个命令。支持Linux、macOS、Docker三种安装方式，10分钟完成部署。"
weight: 2
stage: 1
stageTitle: "基础入门篇"
---

## 引言

上一篇我们理解了为什么需要Redis，现在是时候动手实践了。这篇文章将带你完成：
- ✅ 10分钟安装Redis
- ✅ 启动并连接Redis
- ✅ 执行第一个命令
- ✅ 理解基本操作

不需要任何前置知识，跟着操作即可。

## 一、安装Redis

### 1.1 方式一：Docker安装（推荐）

**为什么推荐Docker？**
- 跨平台，Windows/Mac/Linux通用
- 隔离环境，不污染系统
- 一条命令搞定，最简单

**步骤**：

```bash
# 1. 拉取Redis镜像（最新稳定版）
docker pull redis:7.2

# 2. 启动Redis容器
docker run -d \
  --name my-redis \
  -p 6379:6379 \
  redis:7.2

# 3. 验证是否启动成功
docker ps | grep redis

# 4. 进入Redis客户端
docker exec -it my-redis redis-cli
```

**持久化配置**（可选）：

```bash
# 创建数据目录
mkdir -p ~/redis/data

# 启动带持久化的Redis
docker run -d \
  --name my-redis \
  -p 6379:6379 \
  -v ~/redis/data:/data \
  redis:7.2 redis-server --appendonly yes
```

### 1.2 方式二：Linux系统安装

**Ubuntu/Debian**：

```bash
# 1. 更新软件源
sudo apt update

# 2. 安装Redis
sudo apt install redis-server

# 3. 启动Redis服务
sudo systemctl start redis-server

# 4. 设置开机自启动
sudo systemctl enable redis-server

# 5. 验证状态
sudo systemctl status redis-server

# 6. 连接Redis
redis-cli
```

**CentOS/RHEL**：

```bash
# 1. 安装EPEL源
sudo yum install epel-release

# 2. 安装Redis
sudo yum install redis

# 3. 启动Redis服务
sudo systemctl start redis

# 4. 设置开机自启动
sudo systemctl enable redis

# 5. 连接Redis
redis-cli
```

### 1.3 方式三：macOS安装

**使用Homebrew**：

```bash
# 1. 安装Redis
brew install redis

# 2. 启动Redis服务
brew services start redis

# 3. 连接Redis
redis-cli

# 停止Redis服务
brew services stop redis

# 重启Redis服务
brew services restart redis
```

### 1.4 方式四：源码编译（可选）

**适用于需要最新版本或特定编译选项的场景**：

```bash
# 1. 下载源码
wget https://download.redis.io/releases/redis-7.2.4.tar.gz
tar xzf redis-7.2.4.tar.gz
cd redis-7.2.4

# 2. 编译
make

# 3. 测试（可选）
make test

# 4. 安装
sudo make install

# 5. 启动Redis服务器
redis-server

# 6. 新开终端，连接Redis
redis-cli
```

## 二、启动和连接

### 2.1 启动Redis服务器

**前台启动**（调试用）：

```bash
redis-server
# 输出：
# Ready to accept connections tcp
```

**后台启动**（推荐）：

```bash
# 方式1：使用配置文件
redis-server /etc/redis/redis.conf

# 方式2：使用nohup
nohup redis-server &

# 方式3：使用systemd（Linux）
sudo systemctl start redis
```

### 2.2 连接Redis客户端

**本地连接**：

```bash
redis-cli
# 输出：
# 127.0.0.1:6379>
```

**远程连接**：

```bash
redis-cli -h <主机IP> -p <端口> -a <密码>

# 例如：
redis-cli -h 192.168.1.100 -p 6379 -a mypassword
```

**测试连接**：

```bash
127.0.0.1:6379> PING
PONG  # 返回PONG说明连接正常
```

## 三、第一个Redis命令

### 3.1 基本数据操作

**存储数据**：

```bash
# SET命令：设置一个键值对
127.0.0.1:6379> SET name "Redis从入门到精通"
OK

# GET命令：获取键的值
127.0.0.1:6379> GET name
"Redis从入门到精通"
```

**检查键是否存在**：

```bash
127.0.0.1:6379> EXISTS name
(integer) 1  # 1表示存在，0表示不存在

127.0.0.1:6379> EXISTS notexist
(integer) 0
```

**删除键**：

```bash
127.0.0.1:6379> DEL name
(integer) 1  # 返回删除的键数量

127.0.0.1:6379> GET name
(nil)  # nil表示键不存在
```

### 3.2 设置过期时间

**设置10秒后过期**：

```bash
127.0.0.1:6379> SET session:user123 "token_abc123"
OK

127.0.0.1:6379> EXPIRE session:user123 10
(integer) 1

# 查看剩余过期时间（秒）
127.0.0.1:6379> TTL session:user123
(integer) 8

# 10秒后查询
127.0.0.1:6379> GET session:user123
(nil)  # 已过期，自动删除
```

**设置键的同时设置过期时间**：

```bash
# 方式1：EX参数（秒）
127.0.0.1:6379> SET cache:product EX 60 "商品信息"
OK

# 方式2：PX参数（毫秒）
127.0.0.1:6379> SET cache:hot PX 5000 "热点数据"
OK

# 方式3：SETEX命令
127.0.0.1:6379> SETEX cache:banner 3600 "首页Banner"
OK
```

### 3.3 批量操作

**批量设置**：

```bash
127.0.0.1:6379> MSET key1 "value1" key2 "value2" key3 "value3"
OK
```

**批量获取**：

```bash
127.0.0.1:6379> MGET key1 key2 key3
1) "value1"
2) "value2"
3) "value3"
```

## 四、常用管理命令

### 4.1 查看所有键

```bash
# 查看所有键（生产环境慎用！）
127.0.0.1:6379> KEYS *
1) "key1"
2) "key2"
3) "key3"

# 模糊匹配
127.0.0.1:6379> KEYS user:*
1) "user:1001"
2) "user:1002"

# 生产环境推荐使用SCAN
127.0.0.1:6379> SCAN 0 MATCH user:* COUNT 100
```

### 4.2 查看键的类型

```bash
127.0.0.1:6379> SET mystring "hello"
OK

127.0.0.1:6379> TYPE mystring
string
```

### 4.3 清空数据库

```bash
# 清空当前数据库
127.0.0.1:6379> FLUSHDB
OK

# 清空所有数据库
127.0.0.1:6379> FLUSHALL
OK
```

### 4.4 查看数据库信息

```bash
# 查看服务器信息
127.0.0.1:6379> INFO

# 查看内存使用情况
127.0.0.1:6379> INFO memory

# 查看统计信息
127.0.0.1:6379> INFO stats

# 查看键数量
127.0.0.1:6379> DBSIZE
(integer) 1234
```

## 五、redis-cli高级用法

### 5.1 执行单条命令

```bash
# 不进入交互模式，直接执行命令
redis-cli SET counter 100
redis-cli GET counter
redis-cli INCR counter
```

### 5.2 批量执行命令

```bash
# 从文件读取命令
cat commands.txt | redis-cli

# 例如commands.txt内容：
# SET key1 value1
# SET key2 value2
# GET key1
```

### 5.3 监控实时命令

```bash
# 实时监控Redis执行的所有命令
redis-cli MONITOR

# 输出：
# 1642567890.123456 [0 127.0.0.1:54321] "GET" "name"
# 1642567891.234567 [0 127.0.0.1:54322] "SET" "age" "25"
```

### 5.4 查看慢查询

```bash
# 查看慢查询日志
redis-cli SLOWLOG GET 10

# 配置慢查询阈值（微秒）
redis-cli CONFIG SET slowlog-log-slower-than 10000

# 配置慢查询日志长度
redis-cli CONFIG SET slowlog-max-len 128
```

## 六、配置文件简介

### 6.1 重要配置项

**redis.conf主要配置**：

```conf
# 绑定IP地址（0.0.0.0表示所有网卡）
bind 127.0.0.1

# 监听端口
port 6379

# 后台运行
daemonize yes

# PID文件位置
pidfile /var/run/redis_6379.pid

# 日志级别：debug、verbose、notice、warning
loglevel notice

# 日志文件
logfile /var/log/redis/redis.log

# 数据库数量
databases 16

# 设置密码
requirepass your_password

# 最大内存
maxmemory 2gb

# 内存淘汰策略
maxmemory-policy allkeys-lru
```

### 6.2 动态修改配置

```bash
# 查看配置
127.0.0.1:6379> CONFIG GET maxmemory
1) "maxmemory"
2) "2147483648"

# 修改配置
127.0.0.1:6379> CONFIG SET maxmemory 4gb
OK

# 持久化配置到文件
127.0.0.1:6379> CONFIG REWRITE
OK
```

## 七、实战练习

### 练习1：简单计数器

```bash
# 访问计数
127.0.0.1:6379> SET page:home:views 0
127.0.0.1:6379> INCR page:home:views
(integer) 1
127.0.0.1:6379> INCR page:home:views
(integer) 2
127.0.0.1:6379> GET page:home:views
"2"
```

### 练习2：验证码存储

```bash
# 生成验证码并设置5分钟过期
127.0.0.1:6379> SETEX captcha:13800138000 300 "8823"
OK

# 用户输入验证码后验证
127.0.0.1:6379> GET captcha:13800138000
"8823"

# 验证成功后删除
127.0.0.1:6379> DEL captcha:13800138000
(integer) 1
```

### 练习3：会话存储

```bash
# 用户登录，存储会话
127.0.0.1:6379> SETEX session:abc123 3600 "user_id:1001"
OK

# 检查会话是否有效
127.0.0.1:6379> GET session:abc123
"user_id:1001"

# 续期会话
127.0.0.1:6379> EXPIRE session:abc123 3600
(integer) 1
```

## 八、常见问题

### Q1: 连接被拒绝

```bash
Error: Connection refused
```

**解决**：
1. 检查Redis是否启动：`ps aux | grep redis`
2. 检查端口是否监听：`netstat -tlnp | grep 6379`
3. 检查防火墙规则

### Q2: 认证失败

```bash
(error) NOAUTH Authentication required
```

**解决**：
```bash
# 方式1：连接时指定密码
redis-cli -a your_password

# 方式2：连接后认证
127.0.0.1:6379> AUTH your_password
OK
```

### Q3: 内存不足

```bash
(error) OOM command not allowed when used memory > 'maxmemory'
```

**解决**：
```bash
# 增加最大内存
CONFIG SET maxmemory 4gb

# 或配置淘汰策略
CONFIG SET maxmemory-policy allkeys-lru
```

## 九、总结

### 核心要点

1. **安装方式**：推荐Docker（简单），Linux用包管理器，macOS用Homebrew
2. **启动连接**：`redis-server`启动服务，`redis-cli`连接客户端
3. **基本命令**：SET/GET/DEL/EXISTS/EXPIRE/TTL
4. **管理命令**：INFO/DBSIZE/KEYS/SCAN/FLUSHDB
5. **配置文件**：redis.conf包含所有配置项，可动态修改

### 下一步

掌握了基本操作后，下一篇我们将深入学习Redis的第一个数据类型：**String类型**。
- String的底层实现
- 常用命令详解
- 实战应用场景

---

**动手练习**：
1. 尝试安装Redis并成功连接
2. 执行本文所有命令示例
3. 创建一个简单的计数器应用
4. 探索INFO命令输出的各项指标

下一篇见！
