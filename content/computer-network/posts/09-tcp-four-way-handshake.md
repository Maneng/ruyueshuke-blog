---
title: "TCP四次挥手详解：为什么需要四次挥手？"
date: 2025-11-20T16:20:00+08:00
draft: false
tags: ["计算机网络", "TCP", "四次挥手", "TIME_WAIT", "CLOSE_WAIT"]
categories: ["技术"]
description: "深入理解TCP四次挥手的设计哲学，TIME_WAIT状态的意义，CLOSE_WAIT问题排查，以及连接泄漏的定位与解决"
series: ["计算机网络从入门到精通"]
weight: 9
stage: 2
stageTitle: "传输层协议篇"
---

## 引言

在上一篇文章中，我们理解了TCP如何通过**三次握手建立连接**。今天我们来学习TCP如何**断开连接**：**四次挥手（Four-Way Handshake）**。

**为什么需要四次挥手？**
- TCP是**全双工通信**（双方可以同时发送和接收数据）
- 断开连接时，**双方都要关闭自己的发送通道**
- 一方关闭发送，不代表另一方也要立即关闭

今天我们来理解：
- ✅ 四次挥手的完整流程
- ✅ 为什么需要四次挥手而不是三次？
- ✅ TIME_WAIT状态为什么要等待2MSL？
- ✅ CLOSE_WAIT问题的排查与解决
- ✅ 连接泄漏的定位方法

## 四次挥手的完整流程

### 流程图解

```
客户端 (Client)                        服务器 (Server)
    |  ESTABLISHED                       |  ESTABLISHED
    |                                    |
    |  [第一次挥手] FIN=1, seq=101       |
    |  主动关闭                           |
    |----------------------------------->|
    |  FIN_WAIT_1                        |  收到FIN
    |                                    |  CLOSE_WAIT（被动关闭）
    |                                    |
    |  [第二次挥手] ACK=1, ack=102       |
    |<-----------------------------------|
    |  FIN_WAIT_2                        |  CLOSE_WAIT
    |  等待服务器关闭                    |  （可能继续发送数据）
    |                                    |
    |                                    |  应用程序调用close()
    |  [第三次挥手] FIN=1, seq=201       |
    |<-----------------------------------|
    |  收到FIN                           |  LAST_ACK
    |  TIME_WAIT                         |
    |                                    |
    |  [第四次挥手] ACK=1, ack=202       |
    |----------------------------------->|
    |  TIME_WAIT（等待2MSL）             |  收到ACK
    |                                    |  CLOSED
    |  2MSL后                            |
    |  CLOSED                            |
```

### 详细步骤

#### 第一次挥手：客户端发起关闭

**客户端 → 服务器**
```
TCP报文段：
- FIN标志位 = 1（表示要关闭发送通道）
- seq = 101（当前序列号）

含义：
"服务器，我没有数据要发送了，我要关闭发送通道"
```

**客户端状态**：`ESTABLISHED` → `FIN_WAIT_1`

**注意**：客户端关闭的是**发送通道**，但**接收通道还开着**（可以继续接收服务器的数据）

#### 第二次挥手：服务器确认

**服务器 → 客户端**
```
TCP报文段：
- ACK标志位 = 1
- ack = 102（确认号 = seq + 1）

含义：
"客户端，我收到了你的FIN，我知道你不会再发数据了"
```

**服务器状态**：`ESTABLISHED` → `CLOSE_WAIT`

**关键点**：
- 服务器只是**确认收到FIN**，还没有关闭自己的发送通道
- 服务器可能还有数据要发送给客户端
- 客户端进入 `FIN_WAIT_2` 状态，等待服务器关闭

#### 第三次挥手：服务器关闭

**服务器 → 客户端**
```
TCP报文段：
- FIN标志位 = 1
- seq = 201（当前序列号）

含义：
"客户端，我也没有数据要发送了，我也要关闭发送通道"
```

**服务器状态**：`CLOSE_WAIT` → `LAST_ACK`（等待最后的确认）

**触发条件**：应用程序调用 `close()` 或 `shutdown()`

#### 第四次挥手：客户端最后确认

**客户端 → 服务器**
```
TCP报文段：
- ACK标志位 = 1
- ack = 202（确认号 = seq + 1）

含义：
"服务器，我收到了你的FIN，连接可以关闭了"
```

**客户端状态**：`FIN_WAIT_2` → `TIME_WAIT`（等待2MSL）

**服务器状态**：收到ACK后，立即进入 `CLOSED`

**客户端等待2MSL后**：`TIME_WAIT` → `CLOSED`

---

## 为什么需要四次挥手而不是三次？

### TCP是全双工通信

**全双工**：双方可以同时发送和接收数据

```
客户端 ⇄ 服务器

发送通道：客户端 → 服务器
接收通道：客户端 ← 服务器
```

**关闭连接时，需要关闭两个通道**：
1. 客户端的发送通道（第一次挥手）
2. 服务器的发送通道（第三次挥手）

**为什么不能合并成三次？**

**三次挥手的假设**：服务器在收到FIN后，立即关闭自己的发送通道
```
[1] 客户端 → 服务器: FIN（我要关闭）
[2] 服务器 → 客户端: FIN-ACK（我确认，我也要关闭）← 合并第二次和第三次
[3] 客户端 → 服务器: ACK（确认）
```

**问题**：**服务器可能还有数据要发送！**

**实际场景**：
```java
// 客户端：发送HTTP请求后立即关闭发送通道
Socket socket = new Socket("server", 8080);
OutputStream out = socket.getOutputStream();
out.write("GET /api/data HTTP/1.1\r\n\r\n".getBytes());
socket.shutdownOutput();  // 关闭发送通道，发送FIN

// 但客户端还需要接收响应！
InputStream in = socket.getInputStream();
byte[] buffer = new byte[1024];
int len = in.read(buffer);  // 继续接收服务器的数据
System.out.println(new String(buffer, 0, len));

socket.close();  // 最后关闭整个连接
```

**服务器端**：
```java
// 服务器收到客户端的FIN（第一次挥手）
// 服务器发送ACK（第二次挥手），确认收到FIN

// 但服务器还在处理请求，还有数据要发送
response.write("HTTP/1.1 200 OK\r\n\r\n");
response.write("{\"data\": \"large response...\"}");  // 可能是大量数据

// 服务器发送完数据后，才关闭发送通道（第三次挥手）
response.close();  // 发送FIN
```

**结论**：**四次挥手允许双方独立地关闭自己的发送通道**，不会打断对方的数据传输。

---

## TIME_WAIT状态：为什么要等待2MSL？

### MSL是什么？

**MSL（Maximum Segment Lifetime）**：最大报文生存时间

- 一个TCP报文段在网络中的最长存活时间
- 通常设置为 **30秒、1分钟或2分钟**（不同操作系统不同）
- Linux默认：60秒

**2MSL = 2 × 60秒 = 120秒（2分钟）**

### 为什么要等待2MSL？

#### 原因1：确保最后的ACK能到达服务器

**场景**：第四次挥手的ACK丢失

```
客户端                     服务器
   |  FIN-WAIT-2            |  LAST_ACK
   |                        |  发送FIN
   |<-----------------------|
   |  TIME_WAIT             |
   |  发送ACK               |
   |----------------------->|  ACK丢失！
   |                        |  超时重传FIN
   |<-----------------------|
   |  重新发送ACK           |
   |----------------------->|  收到ACK
   |                        |  CLOSED
   |  2MSL后                |
   |  CLOSED                |
```

**如果没有TIME_WAIT**：
1. 客户端发送ACK后立即关闭
2. 服务器没收到ACK，重传FIN
3. 客户端已经关闭，无法响应
4. 服务器超时后才能关闭，浪费资源

**TIME_WAIT的作用**：
- **保持连接2MSL时间**
- 如果服务器重传FIN，客户端可以重新发送ACK
- 2MSL = FIN最大存活时间(MSL) + ACK最大存活时间(MSL)

#### 原因2：防止旧连接的数据包干扰新连接

**场景**：端口复用导致混乱

```
[旧连接]
客户端:54321 → 服务器:8080
关闭连接，进入TIME_WAIT

[假设没有TIME_WAIT，立即复用端口]
客户端:54321 → 服务器:8080（新连接）
建立连接，开始传输数据

[问题]
旧连接的数据包在网络中延迟，终于到达
服务器收到旧数据包，误以为是新连接的数据！
```

**TIME_WAIT的作用**：
- **等待2MSL，确保旧连接的所有数据包都消失**
- 2MSL后，网络中不可能还有旧连接的数据包
- 此时复用端口是安全的

### TIME_WAIT的副作用

#### 问题：大量TIME_WAIT占用资源

**场景**：高并发短连接（如爬虫、压测工具）

```bash
# 查看TIME_WAIT连接数
netstat -an | grep TIME_WAIT | wc -l
# 输出：50000（大量TIME_WAIT）

# 每个TIME_WAIT连接占用：
# - 一个Socket（文件描述符）
# - 一个端口号（客户端动态端口）
# - 内存（Socket结构体）
```

**后果**：
- ❌ 端口耗尽（客户端动态端口：49152-65535，约16000个）
- ❌ 文件描述符耗尽
- ❌ 无法建立新连接

#### 解决方案

**方案1：启用TIME_WAIT重用（推荐）**

```bash
# Linux内核参数
sudo sysctl -w net.ipv4.tcp_tw_reuse=1

# 作用：允许将TIME_WAIT的端口分配给新的连接
# 前提：使用时间戳选项（tcp_timestamps=1）
```

**方案2：启用TIME_WAIT快速回收（不推荐，已废弃）**

```bash
# 不推荐！可能导致旧数据包干扰新连接
sudo sysctl -w net.ipv4.tcp_tw_recycle=1
```

**方案3：调整TIME_WAIT超时时间（不推荐）**

```bash
# Linux不支持直接修改2MSL时间
# 需要重新编译内核（不推荐）
```

**方案4：应用层使用长连接**

```java
// 使用连接池 + Keep-Alive，复用连接
HttpClient httpClient = HttpClients.custom()
    .setConnectionManager(new PoolingHttpClientConnectionManager())
    .setKeepAliveStrategy((response, context) -> 30000)  // 30秒
    .build();

// 一次连接，多次请求，减少TIME_WAIT
```

---

## CLOSE_WAIT问题：连接泄漏的罪魁祸首

### CLOSE_WAIT是什么？

**CLOSE_WAIT**：服务器收到客户端的FIN，但还没有关闭自己的发送通道

**正常流程**：
```
服务器收到FIN（第一次挥手）
 ↓
进入CLOSE_WAIT状态
 ↓
应用程序调用close()（关闭Socket）
 ↓
发送FIN（第三次挥手）
 ↓
收到ACK（第四次挥手）
 ↓
连接关闭
```

**异常情况**：**应用程序忘记调用close()！**

### CLOSE_WAIT过多的原因

#### 原因1：忘记关闭Socket

**错误代码**：
```java
public void handleRequest(String url) {
    try {
        Socket socket = new Socket(url, 8080);
        OutputStream out = socket.getOutputStream();
        InputStream in = socket.getInputStream();

        // 发送请求
        out.write("GET / HTTP/1.1\r\n\r\n".getBytes());

        // 读取响应
        byte[] buffer = new byte[1024];
        int len = in.read(buffer);
        System.out.println(new String(buffer, 0, len));

        // ❌ 忘记关闭Socket！
        // socket.close();

    } catch (IOException e) {
        e.printStackTrace();
    }
}

// 问题：
// - 客户端（远程）主动关闭连接，发送FIN
// - 服务器（本地）收到FIN，进入CLOSE_WAIT
// - 但应用程序没有调用close()，无法发送FIN
// - 连接一直停留在CLOSE_WAIT状态！
```

**正确代码**：
```java
public void handleRequest(String url) {
    Socket socket = null;
    try {
        socket = new Socket(url, 8080);
        // ...
    } catch (IOException e) {
        e.printStackTrace();
    } finally {
        if (socket != null) {
            try {
                socket.close();  // ✅ 确保关闭
            } catch (IOException e) {
                e.printStackTrace();
            }
        }
    }
}
```

**更好的做法**：使用try-with-resources
```java
public void handleRequest(String url) {
    try (Socket socket = new Socket(url, 8080)) {
        // ...
    } catch (IOException e) {
        e.printStackTrace();
    }
    // ✅ 自动关闭Socket
}
```

#### 原因2：应用程序阻塞，无法调用close()

**场景**：读取数据时阻塞
```java
public void handleRequest() {
    try (Socket socket = serverSocket.accept()) {
        InputStream in = socket.getInputStream();

        // ❌ 阻塞在read()，永远无法到达close()
        byte[] buffer = new byte[1024];
        int len = in.read(buffer);  // 如果客户端不发送数据，永远阻塞

        // ...
    } catch (IOException e) {
        e.printStackTrace();
    }
}

// 问题：
// - 客户端发送FIN，本地收到，进入CLOSE_WAIT
// - 但应用程序还在等待读取数据，阻塞在read()
// - 无法到达close()，无法发送FIN
```

**解决**：设置读取超时
```java
try (Socket socket = serverSocket.accept()) {
    socket.setSoTimeout(30000);  // ✅ 设置30秒超时

    InputStream in = socket.getInputStream();
    byte[] buffer = new byte[1024];
    int len = in.read(buffer);  // 30秒后超时，抛出SocketTimeoutException

} catch (SocketTimeoutException e) {
    System.out.println("读取超时");
} catch (IOException e) {
    e.printStackTrace();
}
// ✅ 超时后退出try块，自动close()
```

### CLOSE_WAIT问题排查

#### 步骤1：查看CLOSE_WAIT连接数

```bash
# 查看CLOSE_WAIT连接数
netstat -an | grep CLOSE_WAIT | wc -l

# 输出：1000（大量CLOSE_WAIT，说明有连接泄漏）

# 查看CLOSE_WAIT的详细信息
netstat -antp | grep CLOSE_WAIT
# 输出：
# tcp  0  0  192.168.1.100:8080  192.168.1.200:54321  CLOSE_WAIT  1234/java
#                 ↑本地地址↑       ↑远程地址↑         ↑状态↑    ↑进程PID/名称↑
```

#### 步骤2：定位问题进程

```bash
# 根据PID查看进程详细信息
ps -ef | grep 1234

# 查看进程打开的文件描述符
lsof -p 1234 | grep CLOSE_WAIT

# 输出：
# java  1234  user  100u  IPv4  0x1234  TCP 192.168.1.100:8080->192.168.1.200:54321 (CLOSE_WAIT)
# java  1234  user  101u  IPv4  0x1235  TCP 192.168.1.100:8080->192.168.1.201:54322 (CLOSE_WAIT)
# ...（大量CLOSE_WAIT）
```

#### 步骤3：分析代码

**排查重点**：
1. ✅ 所有Socket都在finally块或try-with-resources中关闭
2. ✅ 设置了读取超时（避免永久阻塞）
3. ✅ 连接池配置正确（最大空闲时间、最大连接数）
4. ✅ 异常处理中也要关闭Socket

#### 步骤4：重启应用（临时）

```bash
# 重启应用，释放CLOSE_WAIT连接
systemctl restart my-app

# 或杀掉进程
kill -9 1234
```

**注意**：这只是临时解决办法，必须修复代码才能根治问题。

---

## 实战案例：抓包分析四次挥手

### 案例：用tcpdump观察四次挥手

```bash
# 启动抓包
sudo tcpdump -i any port 8080 -n

# 另一个终端：用curl访问（curl会自动关闭连接）
curl http://localhost:8080

# 抓包输出（简化，只看挥手部分）

# [数据传输阶段]
# ...（省略HTTP请求和响应）

# [第一次挥手]
IP 127.0.0.1.54321 > 127.0.0.1.8080: Flags [F.], seq 100, ack 500
# Flags [F.] → FIN=1, ACK=1
# curl客户端主动关闭

# [第二次挥手]
IP 127.0.0.1.8080 > 127.0.0.1.54321: Flags [.], ack 101
# Flags [.] → ACK=1
# 服务器确认收到FIN

# [第三次挥手]（可能在几毫秒到几秒后）
IP 127.0.0.1.8080 > 127.0.0.1.54321: Flags [F.], seq 500, ack 101
# Flags [F.] → FIN=1, ACK=1
# 服务器也关闭

# [第四次挥手]
IP 127.0.0.1.54321 > 127.0.0.1.8080: Flags [.], ack 501
# Flags [.] → ACK=1
# 客户端确认收到服务器的FIN

# 此时客户端进入TIME_WAIT，等待2MSL（120秒）
```

**查看TIME_WAIT状态**：
```bash
# 另一个终端：立即查看连接状态
netstat -an | grep 54321

# 输出：
# tcp  0  0  127.0.0.1.54321  127.0.0.1.8080  TIME_WAIT

# 等待120秒后再查看
netstat -an | grep 54321
# 输出：（无结果，连接已关闭）
```

---

## 微服务场景的四次挥手问题

### 问题1：RestTemplate连接泄漏

**现象**：应用运行一段时间后，无法建立新连接

**排查**：
```bash
# 查看CLOSE_WAIT连接数
netstat -an | grep CLOSE_WAIT | wc -l
# 输出：500（大量CLOSE_WAIT）
```

**原因**：RestTemplate没有使用连接池，每次请求都创建新连接，但没有正确关闭

**错误代码**：
```java
// ❌ 每次都创建新的RestTemplate（没有连接池）
public String callUserService() {
    RestTemplate restTemplate = new RestTemplate();
    return restTemplate.getForObject(
        "http://user-service:8080/api/users/123",
        String.class
    );
}
// 问题：
// - 每次请求都建立新连接
// - user-service主动关闭连接（响应后）
// - 本地收到FIN，进入CLOSE_WAIT
// - 但RestTemplate没有正确关闭，导致连接泄漏
```

**正确做法**：使用连接池
```java
@Configuration
public class RestTemplateConfig {
    @Bean
    public RestTemplate restTemplate() {
        PoolingHttpClientConnectionManager connectionManager =
            new PoolingHttpClientConnectionManager();
        connectionManager.setMaxTotal(200);
        connectionManager.setDefaultMaxPerRoute(20);

        HttpClient httpClient = HttpClients.custom()
            .setConnectionManager(connectionManager)
            .build();

        HttpComponentsClientHttpRequestFactory factory =
            new HttpComponentsClientHttpRequestFactory(httpClient);

        return new RestTemplate(factory);
    }
}

@Autowired
private RestTemplate restTemplate;  // ✅ 复用连接池
```

### 问题2：Feign调用超时导致TIME_WAIT激增

**现象**：压测时TIME_WAIT连接数暴增

**原因**：
1. Feign调用超时，客户端主动关闭连接
2. 每次超时都产生一个TIME_WAIT连接
3. TIME_WAIT需要等待2MSL（120秒）
4. 高并发时，TIME_WAIT累积，端口耗尽

**解决**：
```yaml
# 1. 增加超时时间（避免频繁超时）
feign:
  client:
    config:
      default:
        connectTimeout: 5000
        readTimeout: 30000  # 增大读取超时

# 2. 启用Keep-Alive（复用连接）
feign:
  httpclient:
    enabled: true
    max-connections: 200
    max-connections-per-route: 50

# 3. 启用TIME_WAIT重用
# 在Linux上配置内核参数
net.ipv4.tcp_tw_reuse=1
```

---

## 总结

### 核心要点

1. **四次挥手流程**：
   - 第一次：客户端发送FIN（我要关闭发送通道）
   - 第二次：服务器发送ACK（我知道了）
   - 第三次：服务器发送FIN（我也要关闭发送通道）
   - 第四次：客户端发送ACK（确认）

2. **为什么是四次？**
   - TCP是全双工通信，双方要独立关闭自己的发送通道
   - 服务器可能还有数据要发送，不能立即关闭

3. **TIME_WAIT状态**：
   - 主动关闭方进入TIME_WAIT
   - 等待2MSL（120秒），确保最后的ACK到达服务器
   - 防止旧连接的数据包干扰新连接

4. **CLOSE_WAIT问题**：
   - 被动关闭方收到FIN，但应用程序没有关闭Socket
   - 常见原因：忘记close()、阻塞在read()
   - 解决：使用try-with-resources、设置超时

### 与下一篇的关联

本文讲解了TCP的**连接建立（三次握手）**和**连接断开（四次挥手）**。下一篇我们将学习TCP如何在连接建立后**可靠地传输数据**：**TCP流量控制机制**，理解：
- 滑动窗口原理
- 接收窗口和发送窗口
- 零窗口与窗口探测
- 如何调整TCP窗口大小

### 思考题

1. 为什么TIME_WAIT状态在主动关闭方，而不是被动关闭方？
2. 如果第四次挥手的ACK丢失，会发生什么？
3. 为什么CLOSE_WAIT状态不会自动超时？如何强制关闭？
4. 在微服务场景下，如何避免TIME_WAIT过多导致端口耗尽？

---

**下一篇预告**：《TCP流量控制机制：滑动窗口原理详解》
