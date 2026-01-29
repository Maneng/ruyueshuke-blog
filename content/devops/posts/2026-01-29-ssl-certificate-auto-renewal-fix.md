---
title: "SSL证书过期修复实战：从手动模式到自动续期的完整解决方案"
date: 2026-01-29T10:00:00+08:00
draft: false
tags: ["SSL证书", "HTTPS", "acme.sh", "Let's Encrypt", "阿里云DNS", "运维"]
categories: ["技术"]
description: "记录一次SSL证书过期问题的完整诊断和修复过程，从DNS手动模式切换到阿里云DNS API自动续期，彻底解决证书自动续期失败的问题。"
---

## 问题背景

今天发现网站 `ruyueshuke.com` 无法正常访问，浏览器提示SSL证书错误。经过排查，发现证书已经过期约1个月（过期时间：2025年12月29日），而服务器上明明配置了自动续期任务，为什么没有自动续期成功呢？

## 问题诊断

### 1. 检查证书状态

首先使用 `openssl` 命令检查证书的有效期：

```bash
openssl s_client -connect ruyueshuke.com:443 -servername ruyueshuke.com </dev/null 2>/dev/null | openssl x509 -noout -dates
```

输出结果：
```
notBefore=Sep 30 01:29:45 2025 GMT
notAfter=Dec 29 01:29:44 2025 GMT
```

**结论**：证书确实已过期（过期日期：2025-12-29，当前日期：2026-01-29）。

### 2. 查找证书管理工具

登录服务器后，发现使用的是 **acme.sh** 而不是常见的 certbot：

```bash
which certbot  # 未找到
which acme.sh  # /root/.acme.sh/acme.sh
```

### 3. 检查证书列表

```bash
/root/.acme.sh/acme.sh --list
```

输出：
```
Main_Domain     KeyLength  SAN_Domains  CA               Created               Renew
ruyueshuke.com  "ec-256"   no           LetsEncrypt.org  2025-09-30T02:28:18Z  2025-11-28T02:28:18Z
```

**关键发现**：
- 证书创建时间：2025-09-30
- 应该续期时间：2025-11-28
- 但实际并未续期成功

### 4. 检查自动续期配置

```bash
crontab -l | grep acme
```

输出：
```
18 14 * * * "/root/.acme.sh"/acme.sh --cron --home "/root/.acme.sh" > /dev/null
```

**发现**：cron任务存在，每天14:18执行，但输出被重定向到 `/dev/null`，看不到错误日志。

### 5. 尝试手动续期

```bash
/root/.acme.sh/acme.sh --renew -d ruyueshuke.com --ecc --force
```

输出关键错误：
```
It seems that you are using dns manual mode.
```

**问题根源找到了！**

## 问题根源分析

### DNS手动模式的工作原理

Let's Encrypt 签发证书时需要验证域名所有权，常见的验证方式有：

1. **HTTP验证**（webroot）：在网站根目录放置验证文件
2. **DNS验证**（dns）：在DNS中添加TXT记录
3. **DNS API自动验证**（dns_ali等）：通过DNS提供商API自动添加TXT记录

本案例中，证书使用的是 **DNS手动模式**，这意味着：

- ✅ **首次签发**：可以手动添加DNS TXT记录完成验证
- ❌ **自动续期**：每次续期都需要人工添加新的TXT记录
- ❌ **无人值守**：cron任务无法自动完成续期

### 为什么会配置成手动模式？

查看证书配置文件：

```bash
cat /root/.acme.sh/ruyueshuke.com_ecc/ruyueshuke.com.conf
```

关键配置：
```
Le_Webroot='dns'  # DNS手动模式
Le_API='https://acme-v02.api.letsencrypt.org/directory'
```

**可能的原因**：
1. 初次配置时未配置DNS API密钥
2. 不了解DNS API自动验证的存在
3. 临时方案变成了长期配置

### 自动续期失败的完整链路

```
每天14:18 cron执行
    ↓
acme.sh --cron 检查证书
    ↓
发现需要续期（距离过期<30天）
    ↓
尝试续期 → 需要DNS手动验证
    ↓
❌ 无法自动添加TXT记录
    ↓
续期失败（输出被重定向到/dev/null，无人知晓）
    ↓
证书过期 → 网站无法访问
```

## 解决方案

### 方案选择

有两种解决方案：

| 方案 | 优点 | 缺点 | 适用场景 |
|------|------|------|----------|
| **方案1：DNS API自动验证** | 完全自动化，无需人工干预 | 需要配置API密钥 | ✅ 推荐，长期方案 |
| **方案2：继续手动模式** | 无需配置API | 每次续期需要人工操作 | ❌ 不推荐，临时应急 |

本次采用 **方案1：配置阿里云DNS API自动验证**。

### 实施步骤

#### 第一步：获取阿里云API密钥

1. 登录阿里云控制台
2. 进入 **RAM访问控制** → **用户** → **AccessKey管理**
3. 创建AccessKey，获得：
   - `AccessKey ID`：类似 `LTAI5tXXXXXXXXXXXXXXXXXX`
   - `AccessKey Secret`：类似 `LypcXXXXXXXXXXXXXXXXXXXXXX`
4. 授予 **AliyunDNSFullAccess** 权限

#### 第二步：重新签发证书（使用DNS API）

```bash
# 设置环境变量
export Ali_Key="您的AccessKey ID"
export Ali_Secret="您的AccessKey Secret"

# 重新签发证书
/root/.acme.sh/acme.sh --issue -d ruyueshuke.com \
  --dns dns_ali \
  --keylength ec-256
```

**执行过程**：
```
[2026-01-29 11:01:52] Adding TXT value: CSzYBraLcPKjYdIAHslL0v1__7wmCL0EbPHtBTBx_Mk
[2026-01-29 11:01:53] The TXT record has been successfully added.
[2026-01-29 11:02:13] Checking ruyueshuke.com for _acme-challenge.ruyueshuke.com
[2026-01-29 11:02:24] Success for domain ruyueshuke.com
[2026-01-29 11:02:28] Verification finished, beginning signing.
[2026-01-29 11:02:32] Cert success.
```

**关键点**：
- acme.sh 自动调用阿里云API添加TXT记录
- 等待DNS生效（约20秒）
- Let's Encrypt验证通过
- 自动删除TXT记录
- 签发新证书

#### 第三步：安装证书到nginx

```bash
/root/.acme.sh/acme.sh --installcert -d ruyueshuke.com --ecc \
  --key-file /etc/nginx/ssl/ruyueshuke.com.key \
  --fullchain-file /etc/nginx/ssl/ruyueshuke.com.cer \
  --reloadcmd 'systemctl reload nginx'
```

输出：
```
[2026-01-29 11:02:41] Installing key to: /etc/nginx/ssl/ruyueshuke.com.key
[2026-01-29 11:02:41] Installing full chain to: /etc/nginx/ssl/ruyueshuke.com.cer
[2026-01-29 11:02:41] Running reload cmd: systemctl reload nginx
[2026-01-29 11:02:41] Reload successful
```

#### 第四步：验证证书生效

```bash
openssl s_client -connect ruyueshuke.com:443 -servername ruyueshuke.com </dev/null 2>/dev/null | openssl x509 -noout -dates
```

输出：
```
notBefore=Jan 29 02:04:00 2026 GMT
notAfter=Apr 29 02:03:59 2026 GMT
```

✅ **证书已更新，有效期至2026年4月29日！**

#### 第五步：保存API密钥（用于自动续期）

acme.sh 会自动保存API密钥到配置文件：

```bash
cat /root/.acme.sh/account.conf
```

可以看到：
```
SAVED_Ali_Key='LTAI5tXXXXXXXXXXXXXXXXXX'
SAVED_Ali_Secret='LypcXXXXXXXXXXXXXXXXXXXXXX'
```

#### 第六步：验证自动续期配置

```bash
/root/.acme.sh/acme.sh --list
```

输出：
```
Main_Domain     KeyLength  SAN_Domains  CA               Created               Renew
ruyueshuke.com  "ec-256"   no           LetsEncrypt.org  2026-01-29T03:02:32Z  2026-03-29T03:02:32Z
```

查看证书配置：
```bash
grep 'Le_Webroot' /root/.acme.sh/ruyueshuke.com_ecc/ruyueshuke.com.conf
```

输出：
```
Le_Webroot='dns_ali'  # ✅ 已从 'dns' 更新为 'dns_ali'
```

测试自动续期：
```bash
/root/.acme.sh/acme.sh --cron
```

输出：
```
[2026-01-29 11:03:31] ===Starting cron===
[2026-01-29 11:03:31] Renewing: 'ruyueshuke.com'
[2026-01-29 11:03:31] Skipping. Next renewal time is: 2026-03-29T03:02:32Z
[2026-01-29 11:03:31] ===End cron===
```

✅ **自动续期配置成功！**

## 技术原理深度解析

### acme.sh 工作原理

acme.sh 是一个纯Shell脚本实现的ACME协议客户端，用于自动化管理Let's Encrypt证书。

#### ACME协议流程

```
1. 客户端向CA申请证书
   ↓
2. CA返回验证挑战（Challenge）
   ↓
3. 客户端完成验证（添加DNS TXT记录或HTTP文件）
   ↓
4. CA验证成功
   ↓
5. CA签发证书
   ↓
6. 客户端下载并安装证书
```

#### DNS API验证的优势

| 验证方式 | 原理 | 优点 | 缺点 |
|---------|------|------|------|
| **HTTP验证** | 在 `.well-known/acme-challenge/` 放置文件 | 简单，无需DNS权限 | 需要80端口，无法签发通配符证书 |
| **DNS手动验证** | 手动添加TXT记录 | 可签发通配符证书 | ❌ 无法自动化 |
| **DNS API验证** | 通过API自动添加TXT记录 | ✅ 完全自动化，支持通配符 | 需要配置API密钥 |

### 阿里云DNS API工作流程

```bash
# acme.sh 调用阿里云DNS API的过程

1. 生成验证Token
   Token: CSzYBraLcPKjYdIAHslL0v1__7wmCL0EbPHtBTBx_Mk

2. 调用阿里云API添加DNS记录
   POST https://alidns.aliyuncs.com/
   参数：
   - Action: AddDomainRecord
   - DomainName: ruyueshuke.com
   - RR: _acme-challenge
   - Type: TXT
   - Value: CSzYBraLcPKjYdIAHslL0v1__7wmCL0EbPHtBTBx_Mk

3. 等待DNS生效（20秒）

4. Let's Encrypt验证
   查询：_acme-challenge.ruyueshuke.com TXT记录
   验证：Token是否匹配

5. 验证成功后删除TXT记录
   POST https://alidns.aliyuncs.com/
   参数：
   - Action: DeleteDomainRecord
```

### 证书自动续期机制

#### 续期时机

Let's Encrypt证书有效期为90天，acme.sh的续期策略：

- **检查频率**：每天执行一次（cron任务）
- **续期时机**：距离过期 < 30天时触发续期
- **续期窗口**：第60-90天之间

```
证书生命周期：
|-------- 60天 --------|--- 30天 ---|
签发                   开始尝试续期    过期
2026-01-29            2026-03-29    2026-04-29
```

#### cron任务详解

```bash
18 14 * * * "/root/.acme.sh"/acme.sh --cron --home "/root/.acme.sh" > /dev/null
```

**参数说明**：
- `18 14 * * *`：每天14:18执行
- `--cron`：检查所有证书，自动续期即将过期的证书
- `--home`：指定acme.sh主目录
- `> /dev/null`：丢弃输出（⚠️ 建议改为记录日志）

**改进建议**：
```bash
# 将输出记录到日志文件，便于排查问题
18 14 * * * "/root/.acme.sh"/acme.sh --cron --home "/root/.acme.sh" >> /var/log/acme.sh.log 2>&1
```

### 证书文件结构

```
/root/.acme.sh/ruyueshuke.com_ecc/
├── ruyueshuke.com.key          # 私钥
├── ruyueshuke.com.cer          # 证书
├── ca.cer                      # 中间证书
├── fullchain.cer               # 完整证书链（证书+中间证书）
└── ruyueshuke.com.conf         # 配置文件

/etc/nginx/ssl/
├── ruyueshuke.com.key          # nginx使用的私钥（软链接或复制）
└── ruyueshuke.com.cer          # nginx使用的证书（软链接或复制）
```

**nginx配置**：
```nginx
server {
    listen 443 ssl http2;
    server_name ruyueshuke.com;

    ssl_certificate /etc/nginx/ssl/ruyueshuke.com.cer;      # 完整证书链
    ssl_certificate_key /etc/nginx/ssl/ruyueshuke.com.key;  # 私钥

    # 其他配置...
}
```

## 经验总结

### 问题复盘

1. **根本原因**：证书配置为DNS手动模式，无法自动续期
2. **发现延迟**：输出重定向到 `/dev/null`，续期失败被静默忽略
3. **影响范围**：证书过期1个月才发现，网站无法访问

### 最佳实践

#### 1. 优先使用DNS API自动验证

```bash
# ✅ 推荐：DNS API自动验证
acme.sh --issue -d example.com --dns dns_ali

# ❌ 不推荐：DNS手动验证
acme.sh --issue -d example.com --dns dns_manual
```

#### 2. 记录日志而不是丢弃输出

```bash
# ❌ 错误做法
18 14 * * * acme.sh --cron > /dev/null

# ✅ 正确做法
18 14 * * * acme.sh --cron >> /var/log/acme.sh.log 2>&1
```

#### 3. 配置监控告警

- 监控证书过期时间（提前30天告警）
- 监控续期任务执行结果
- 使用工具：SSL Labs、Uptime Robot等

#### 4. 定期检查证书状态

```bash
# 每月检查一次
acme.sh --list

# 查看证书有效期
openssl x509 -in /etc/nginx/ssl/example.com.cer -noout -dates
```

### 常用命令速查

```bash
# 查看证书列表
acme.sh --list

# 查看证书详细信息
acme.sh --info -d example.com

# 手动触发续期（测试用）
acme.sh --renew -d example.com --force

# 测试自动续期
acme.sh --cron

# 查看证书有效期
openssl x509 -in /path/to/cert.cer -noout -dates

# 查看证书详细信息
openssl x509 -in /path/to/cert.cer -noout -text

# 验证证书链
openssl verify -CAfile ca.cer fullchain.cer
```

### 支持的DNS提供商

acme.sh 支持100+DNS提供商的API，常见的有：

- **阿里云**：`--dns dns_ali`
- **腾讯云**：`--dns dns_tencent`
- **Cloudflare**：`--dns dns_cf`
- **AWS Route53**：`--dns dns_aws`
- **DNSPod**：`--dns dns_dp`

完整列表：https://github.com/acmesh-official/acme.sh/wiki/dnsapi

## 总结

这次SSL证书过期问题的修复，让我们深入理解了：

1. **ACME协议**：自动化证书管理的标准协议
2. **DNS验证**：通过DNS TXT记录验证域名所有权
3. **API自动化**：通过DNS提供商API实现完全���动化
4. **证书生命周期**：签发、续期、过期的完整流程

**核心要点**：
- ✅ 使用DNS API自动验证，实现无人值守
- ✅ 记录日志，便于排查问题
- ✅ 配置监控，提前发现问题
- ✅ 定期检查，确保系统正常运行

通过这次修复，网站的SSL证书管理已经实现了完全自动化，以后再也不用担心证书过期的问题了！

---

## 参考资料

- [acme.sh 官方文档](https://github.com/acmesh-official/acme.sh)
- [Let's Encrypt 官方文档](https://letsencrypt.org/docs/)
- [ACME协议规范](https://datatracker.ietf.org/doc/html/rfc8555)
- [阿里云DNS API文档](https://help.aliyun.com/document_detail/29739.html)

