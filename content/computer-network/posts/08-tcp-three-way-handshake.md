---
title: "TCP三次握手详解：为什么是三次而不是两次？"
date: 2025-11-20T16:10:00+08:00
draft: false
tags: ["计算机网络", "TCP", "三次握手", "SYN", "ACK"]
categories: ["技术"]
description: "深入理解TCP三次握手的设计哲学，SYN/ACK标志位、半连接队列、全连接队列，以及SYN Flood攻击原理"
series: ["计算机网络从入门到精通"]
weight: 8
stage: 2
stageTitle: "传输层协议篇"
---

## 引言

在上一篇文章中，我们理解了传输层的核心使命和TCP/UDP的本质区别。今天我们深入TCP协议的第一个重要机制：**三次握手（Three-Way Handshake）**。

**为什么需要三次握手？**
- TCP是**面向连接**的协议（像打电话，先拨号建立连接）
- 在传输数据之前，**必须先建立一条可靠的连接**
- 三次握手就是建立连接的过程

今天我们来理解：
- ✅ 三次握手的完整流程
- ✅ 为什么是三次而不是两次或四次？
- ✅ SYN/ACK标志位的作用
- ✅ 半连接队列和全连接队列
- ✅ SYN Flood攻击原理与防护

## 三次握手的完整流程

### 流程图解

```
客户端 (Client)                        服务器 (Server)
    |                                      |
    |  [第一次握手] SYN=1, seq=100         |
    |------------------------------------->|  LISTEN状态
    |                                      |  收到SYN，进入SYN_RCVD状态
    |                                      |
    |  [第二次握手] SYN=1, ACK=1           |
    |  seq=200, ack=101                    |
    |<-------------------------------------|
    |  收到SYN-ACK，进入ESTABLISHED状态    |
    |                                      |
    |  [第三次握手] ACK=1, ack=201         |
    |------------------------------------->|
    |                                      |  收到ACK，进入ESTABLISHED状态
    |                                      |
    |  [连接建立完成，开始传输数据]        |
    |<------------------------------------>|
```

### 详细步骤

#### 第一次握手：客户端发送SYN

**客户端 → 服务器**
```
TCP报文段：
- SYN标志位 = 1（表示这是一个同步请求）
- seq（序列号） = 100（客户端的初始序列号，随机生成）
- 其他标志位 = 0

含义：
"服务器你好，我想和你建立连接，我的初始序列号是100"
```

**客户端状态**：`CLOSED` → `SYN_SENT`（等待服务器响应）

#### 第二次握手：服务器响应SYN-ACK

**服务器 → 客户端**
```
TCP报文段：
- SYN标志位 = 1（表示服务器也要同步）
- ACK标志位 = 1（表示确认收到客户端的SYN）
- seq = 200（服务器的初始序列号，随机生成）
- ack = 101（确认号 = 客户端seq + 1，表示期望下次收到101号）

含义：
"客户端你好，我收到了你的SYN（seq=100），我确认了（ack=101）。
我也想和你建立连接，我的初始序列号是200"
```

**服务器状态**：`LISTEN` → `SYN_RCVD`（等待客户端最后确认）

#### 第三次握手：客户端确认ACK

**客户端 → 服务器**
```
TCP报文段：
- ACK标志位 = 1（确认收到服务器的SYN）
- seq = 101（从101开始，因为已经用了100）
- ack = 201（确认号 = 服务器seq + 1）

含义：
"服务器，我收到了你的SYN-ACK（seq=200），我确认了（ack=201）。
连接建立完成！"
```

**双方状态**：都进入 `ESTABLISHED`（连接已建立）

---

## 为什么是三次而不是两次或四次？

### 为什么不能是两次握手？

**假设只有两次握手**：
```
客户端                     服务器
  |  [1] SYN, seq=100      |
  |----------------------->|
  |                        |  收到SYN，直接进入ESTABLISHED
  |  [2] SYN-ACK           |
  |<-----------------------|
  |  收到SYN-ACK           |
```

**问题1：旧连接请求导致混乱**

场景：
1. 客户端发送 SYN1（seq=100），但网络延迟，卡在了某个路由器
2. 客户端等待超时，重新发送 SYN2（seq=200）
3. SYN2正常到达，连接建立，数据传输完成，连接关闭
4. **此时，SYN1终于到达服务器**

两次握手的问题：
```
服务器收到SYN1（seq=100）→ 以为是新连接请求
服务器发送SYN-ACK → 进入ESTABLISHED状态
服务器等待数据... → 但客户端根本不会发数据（因为客户端认为这个连接已经过期）
服务器资源浪费！
```

**三次握手如何解决？**
```
服务器收到SYN1（seq=100）→ 发送SYN-ACK
服务器进入SYN_RCVD状态，等待第三次握手
客户端收到SYN-ACK → 但客户端根本不认识这个连接！
客户端不会发送第三次握手的ACK
服务器超时后会关闭这个半连接，资源得到释放
```

**问题2：无法确认双方的接收能力**

两次握手只能证明：
- ✅ 客户端能发送
- ✅ 服务器能接收
- ✅ 服务器能发送
- ❌ **无法确认客户端能接收**（如果第二次握手的SYN-ACK丢失，客户端根本不知道）

三次握手能证明：
- ✅ 客户端能发送（第一次）
- ✅ 服务器能接收（收到第一次）
- ✅ 服务器能发送（第二次）
- ✅ **客户端能接收**（收到第二次，并发送第三次）
- ✅ **双向通信能力都得到确认**

### 为什么不需要四次握手？

**三次握手已经足够**：
- 第一次：客户端 → 服务器（证明客户端能发送）
- 第二次：服务器 → 客户端（证明服务器能接收和发送）
- 第三次：客户端 → 服务器（证明客户端能接收）

**四次握手是浪费**：
- 第二次握手已经同时完成了"确认客户端的SYN"和"发送自己的SYN"
- 如果拆成两次（先ACK，再SYN），就变成四次握手，完全没必要

---

## SYN和ACK标志位详解

### TCP报文段标志位

TCP头部有6个重要的标志位（1比特，0或1）：

| 标志位 | 全称 | 含义 | 三次握手中的使用 |
|--------|------|------|------------------|
| **SYN** | Synchronize | 同步序列号，建立连接 | 第一次、第二次 |
| **ACK** | Acknowledgment | 确认号有效 | 第二次、第三次 |
| PSH | Push | 推送数据到应用层 | 数据传输时 |
| FIN | Finish | 结束连接 | 四次挥手时 |
| RST | Reset | 重置连接 | 连接异常时 |
| URG | Urgent | 紧急指针有效 | 很少使用 |

### 序列号（seq）和确认号（ack）

**序列号（Sequence Number）**：
- 32位整数
- 标识发送的数据的第一个字节的编号
- 初始值随机生成（ISN，Initial Sequence Number）
- 每发送一个字节，seq + 1

**确认号（Acknowledgment Number）**：
- 32位整数
- 表示期望接收的下一个字节的编号
- ack = 收到的seq + 数据长度
- SYN和FIN标志位也占用一个序列号

**示例**：
```
第一次握手：
  SYN=1, seq=100
  （占用序列号100）

第二次握手：
  SYN=1, ACK=1, seq=200, ack=101
  （服务器确认收到了100，期望下次收到101）
  （占用序列号200）

第三次握手：
  ACK=1, seq=101, ack=201
  （客户端确认收到了200，期望下次收到201）
  （没有数据，不占用序列号）
```

---

## 半连接队列和全连接队列

### 服务器的连接管理

在三次握手过程中，服务器维护两个队列：

```
[半连接队列]          [全连接队列]           [应用程序]
SYN_RCVD状态    →   ESTABLISHED状态    →   accept()取走
  (待完成连接)          (完成连接)
```

#### 半连接队列（SYN Queue）

**作用**：存放收到SYN但还没完成三次握手的连接

**流程**：
1. 服务器收到SYN（第一次握手）
2. **将连接放入半连接队列**
3. 服务器发送SYN-ACK（第二次握手）
4. 等待客户端的ACK（第三次握手）

**状态**：`SYN_RCVD`

**队列大小**：`tcp_max_syn_backlog`（内核参数）
```bash
# Linux查看
sysctl net.ipv4.tcp_max_syn_backlog
# 输出：net.ipv4.tcp_max_syn_backlog = 512

# 调整（临时）
sudo sysctl -w net.ipv4.tcp_max_syn_backlog=1024
```

#### 全连接队列（Accept Queue）

**作用**：存放完成三次握手、等待应用程序accept()的连接

**流程**：
1. 服务器收到ACK（第三次握手）
2. **将连接从半连接队列移到全连接队列**
3. 等待应用程序调用 `accept()` 取走连接

**状态**：`ESTABLISHED`

**队列大小**：`min(backlog, somaxconn)`
- `backlog`：应用程序在 `listen(sockfd, backlog)` 中指定
- `somaxconn`：系统参数

```bash
# Linux查看
sysctl net.core.somaxconn
# 输出：net.core.somaxconn = 128

# Java中的backlog
ServerSocket serverSocket = new ServerSocket(8080, 50);
// 第二个参数就是backlog（全连接队列大小）
```

### 队列满了会怎样？

#### 半连接队列满

**现象**：新的SYN请求会被丢弃，客户端连接超时

**排查**：
```bash
# Linux查看SYN队列溢出次数
netstat -s | grep "SYNs to LISTEN"
# 输出：
#   123456 SYNs to LISTEN sockets dropped
```

**解决**：
1. 增大 `tcp_max_syn_backlog`
2. 启用 SYN Cookies（稍后讲）

#### 全连接队列满

**现象**：完成三次握手的连接无法被accept()，客户端可能收到RST

**排查**：
```bash
# Linux查看全连接队列溢出次数
netstat -s | grep "overflowed"
# 输出：
#   789 times the listen queue of a socket overflowed
```

**排查当前队列状态**：
```bash
# 查看某个端口的连接队列
ss -lnt | grep :8080
# 输出：
# State  Recv-Q Send-Q Local Address:Port
# LISTEN 50     128    *:8080
#        ↑      ↑
#  当前队列长度  最大队列长度

# 如果Recv-Q接近Send-Q，说明队列快满了
```

**解决**：
1. 增大应用程序的backlog
2. 增大系统的somaxconn
3. **加快应用程序处理速度**（最根本的解决办法）

---

## SYN Flood攻击与防护

### SYN Flood攻击原理

**攻击手法**：
1. 攻击者伪造大量IP地址
2. 向服务器发送大量SYN请求（第一次握手）
3. 服务器发送SYN-ACK（第二次握手）
4. **攻击者永远不发送ACK（第三次握手）**
5. 服务器的半连接队列被大量SYN_RCVD状态的连接占满
6. 正常用户无法建立连接（SYN请求被丢弃）

```
攻击者（伪造IP）         服务器               正常用户
     |                    |                    |
     | SYN, seq=1         |                    |
     |------------------->|                    |
     |                    | 放入半连接队列     |
     | SYN, seq=2         |                    |
     |------------------->|                    |
     |                    | 放入半连接队列     |
     | SYN, seq=3         |                    |
     |------------------->|                    |
     | ...                |                    |
     | SYN, seq=10000     |                    |
     |------------------->|                    |
     |                    | 半连接队列满！     |
     |                    |                    |
     |                    |                    | SYN, seq=100
     |                    |                    |-------------->
     |                    |                    | 被丢弃！
     |                    |                    |<-- 连接超时
```

### 防护手段

#### 1. SYN Cookies

**原理**：不使用半连接队列，将连接信息编码到序列号中

**流程**：
1. 服务器收到SYN，**不放入半连接队列**
2. 根据客户端IP、端口、时间戳等信息，**计算一个特殊的初始序列号（Cookie）**
3. 发送SYN-ACK（seq=Cookie）
4. 客户端发送ACK（ack=Cookie+1）
5. 服务器收到ACK，**从ack中解码出连接信息**，建立连接

**优点**：不占用半连接队列，理论上可以抵御无限量的SYN Flood

**缺点**：
- 无法使用TCP选项（如窗口缩放、SACK）
- 增加CPU计算开销

**启用SYN Cookies**：
```bash
# Linux
sudo sysctl -w net.ipv4.tcp_syncookies=1

# 查看状态
sysctl net.ipv4.tcp_syncookies
# 输出：net.ipv4.tcp_syncookies = 1
```

#### 2. 减少SYN-ACK重传次数

**默认行为**：服务器发送SYN-ACK后，如果没收到ACK，会重传5次（等待约3分钟）

**优化**：减少重传次数，快速释放资源

```bash
# Linux
sudo sysctl -w net.ipv4.tcp_synack_retries=2

# 查看
sysctl net.ipv4.tcp_synack_retries
# 输出：net.ipv4.tcp_synack_retries = 2
```

#### 3. 增大半连接队列

```bash
# 增大半连接队列（治标不治本）
sudo sysctl -w net.ipv4.tcp_max_syn_backlog=8192
```

#### 4. 使用防火墙和CDN

- **iptables限制**：限制单个IP的连接速率
- **CDN防护**：Cloudflare、阿里云盾等提供DDoS防护
- **负载均衡**：在SLB层做连接限制

---

## 实战案例：抓包分析三次握手

### 案例：用tcpdump观察三次握手

**场景**：用curl访问本地Web服务器

```bash
# 启动抓包（监听8080端口）
sudo tcpdump -i any port 8080 -n -S

# 另一个终端：用curl访问
curl http://localhost:8080

# 抓包输出（添加了解释）
# [第一次握手]
IP 127.0.0.1.54321 > 127.0.0.1.8080: Flags [S], seq 1000000000, win 65535
# Flags [S] → SYN=1
# seq 1000000000 → 客户端初始序列号
# win 65535 → 接收窗口大小

# [第二次握手]
IP 127.0.0.1.8080 > 127.0.0.1.54321: Flags [S.], seq 2000000000, ack 1000000001, win 65535
# Flags [S.] → SYN=1, ACK=1
# seq 2000000000 → 服务器初始序列号
# ack 1000000001 → 确认号 = 客户端seq + 1

# [第三次握手]
IP 127.0.0.1.54321 > 127.0.0.1.8080: Flags [.], ack 2000000001, win 65535
# Flags [.] → ACK=1
# ack 2000000001 → 确认号 = 服务器seq + 1

# [连接建立完成，开始传输HTTP请求]
IP 127.0.0.1.54321 > 127.0.0.1.8080: Flags [P.], seq 1000000001:1000000100, ack 2000000001
# Flags [P.] → PSH=1, ACK=1（推送数据）
# seq 1000000001:1000000100 → 发送99字节数据（HTTP请求）
```

**关键观察**：
- 三个数据包：`[S]` → `[S.]` → `[.]`
- 序列号和确认号的关系：`ack = seq + 1`
- SYN标志位占用一个序列号

---

## 微服务场景的三次握手问题

### 问题1：连接超时

**现象**：Feign调用其他服务，报错 `ConnectTimeoutException`

**原因**：三次握手超时（网络问题或服务器不可达）

**排查**：
```bash
# 检查目标服务是否可达
telnet user-service 8080

# 如果卡住，说明无法建立连接
# 可能原因：
# 1. 服务未启动
# 2. 防火墙拦截
# 3. 网络不通
```

**解决**：
```yaml
# application.yml - 调整连接超时
feign:
  client:
    config:
      default:
        connectTimeout: 5000  # 连接超时5秒
```

### 问题2：全连接队列满

**现象**：高并发时，部分请求连接超时

**排查**：
```bash
# 查看全连接队列溢出次数
netstat -s | grep "overflowed"

# 查看当前队列状态
ss -lnt | grep :8080
```

**解决**：
```yaml
# Spring Boot - 增大连接队列
server:
  tomcat:
    accept-count: 200  # 增大全连接队列
    max-connections: 10000  # 增大最大连接数
```

### 问题3：连接池中的三次握手开销

**问题**：每次HTTP请求都要三次握手，延迟高

**解决**：使用连接池 + Keep-Alive

```java
// 配置RestTemplate连接池
@Bean
public RestTemplate restTemplate() {
    HttpComponentsClientHttpRequestFactory factory =
        new HttpComponentsClientHttpRequestFactory();

    // 连接池配置
    PoolingHttpClientConnectionManager connectionManager =
        new PoolingHttpClientConnectionManager();
    connectionManager.setMaxTotal(200);  // 最大连接数
    connectionManager.setDefaultMaxPerRoute(20);  // 每个路由最大连接数

    HttpClient httpClient = HttpClients.custom()
        .setConnectionManager(connectionManager)
        .setKeepAliveStrategy((response, context) -> 30000)  // Keep-Alive 30秒
        .build();

    factory.setHttpClient(httpClient);
    factory.setConnectTimeout(5000);  // 连接超时5秒
    factory.setReadTimeout(10000);  // 读取超时10秒

    return new RestTemplate(factory);
}
```

**效果**：
- 第一次请求：三次握手 + 数据传输
- 后续请求：复用连接，无需握手，降低延迟

---

## 总结

### 核心要点

1. **三次握手流程**：
   - 第一次：客户端发送SYN（我想连接）
   - 第二次：服务器发送SYN-ACK（我同意，我也想连接）
   - 第三次：客户端发送ACK（确认连接建立）

2. **为什么是三次？**
   - 防止旧连接请求导致混乱
   - 确认双方的收发能力
   - 两次不够，四次浪费

3. **半连接队列和全连接队列**：
   - 半连接队列：SYN_RCVD状态，等待第三次握手
   - 全连接队列：ESTABLISHED状态，等待accept()

4. **SYN Flood攻击**：
   - 攻击者发送大量SYN，不发送ACK
   - 半连接队列被占满，正常用户无法连接
   - 防护：SYN Cookies、减少重传、防火墙

### 与下一篇的关联

本文讲解了TCP如何**建立连接**（三次握手）。下一篇我们将学习TCP如何**断开连接**：**TCP四次挥手详解**，理解：
- 为什么需要四次挥手？
- TIME_WAIT状态的意义
- CLOSE_WAIT问题排查
- 连接泄漏的定位与解决

### 思考题

1. 如果第三次握手的ACK丢失，会发生什么？
2. 为什么SYN和FIN标志位要占用一个序列号，而ACK不占用？
3. 在高并发场景下，如何避免全连接队列满？
4. SYN Cookies有哪些缺点？什么时候不适合使用？

---

**下一篇预告**：《TCP四次挥手详解：为什么需要四次挥手？》
