---
title: "HTTPS与TLS/SSL：加密通信原理与证书验证"
date: 2025-11-21T17:40:00+08:00
draft: false
tags: ["计算机网络", "HTTPS", "TLS", "SSL", "加密"]
categories: ["技术"]
description: "深入理解HTTPS加密原理，TLS握手过程，证书链验证机制，以及微服务HTTPS配置实践"
series: ["计算机网络从入门到精通"]
weight: 17
stage: 3
stageTitle: "应用层协议篇"
---

## 为什么需要HTTPS？

### HTTP的三大安全问题

**1. 明文传输（窃听）**
```
中间人可以看到所有内容：

客户端 → 路由器: POST /login {"username":"admin", "password":"123456"}
              ↑ 窃听者看到密码！
```

**2. 篡改（中间人攻击）**
```
中间人可以修改请求/响应：

客户端 → 中间人 → 服务器
         ↑ 修改转账金额 1000 → 10000
```

**3. 冒充（钓鱼网站）**
```
客户端访问 http://bank.com
中间人伪造假网站，窃取用户密码
```

### HTTPS = HTTP + TLS/SSL

```
HTTP over TLS/SSL

应用层     HTTP
         ----
安全层     TLS/SSL（加密）
         ----
传输层     TCP
```

---

## 加密基础

### 对称加密

**相同的密钥加密和解密**

```
加密：明文 + 密钥 → 密文
解密：密文 + 密钥 → 明文

示例：
明文："Hello"
密钥："secret123"
密文："Xf9kL2p"
```

**常见算法**：AES、DES、3DES

**优点**：速度快
**缺点**：密钥如何安全传递？

### 非对称加密

**公钥加密，私钥解密**

```
公钥：公开，任何人都可以获取
私钥：保密，只有服务器持有

加密：明文 + 公钥 → 密文
解密：密文 + 私钥 → 明文

示例：
服务器生成密钥对：公钥A、私钥B
客户端用公钥A加密：密文C
服务器用私钥B解密：得到明文
```

**常见算法**：RSA、ECC

**优点**：密钥传递安全
**缺点**：速度慢（比对称加密慢100-1000倍）

### HTTPS混合加密

**结合两者优点**：

```
1. 非对称加密传递对称密钥（握手阶段）
2. 对称加密传输数据（数据传输阶段）

优点：安全 + 高效
```

---

## TLS握手过程

### 完整流程（TLS 1.2）

```
客户端                                 服务器
   |                                      |
   | [1] Client Hello                     |
   |   - 支持的TLS版本                    |
   |   - 支持的加密套件列表               |
   |   - 随机数1（ClientRandom）          |
   |------------------------------------->|
   |                                      |
   | [2] Server Hello                     |
   |   - 选择的TLS版本                    |
   |   - 选择的加密套件                   |
   |   - 随机数2（ServerRandom）          |
   |<-------------------------------------|
   |                                      |
   | [3] Certificate                      |
   |   - 服务器证书（包含公钥）           |
   |<-------------------------------------|
   |                                      |
   | [4] Server Key Exchange（可选）      |
   |<-------------------------------------|
   |                                      |
   | [5] Server Hello Done                |
   |<-------------------------------------|
   |                                      |
   | [6] Client Key Exchange              |
   |   - 预主密钥（用服务器公钥加密）     |
   |------------------------------------->|
   |                                      |
   | [7] Change Cipher Spec               |
   |   - 通知：后续使用加密通信           |
   |------------------------------------->|
   |                                      |
   | [8] Finished                         |
   |   - 加密的握手消息摘要               |
   |------------------------------------->|
   |                                      |
   | [9] Change Cipher Spec               |
   |<-------------------------------------|
   |                                      |
   | [10] Finished                        |
   |<-------------------------------------|
   |                                      |
   | [加密的HTTP数据传输]                 |
   |<------------------------------------>|
```

### 密钥生成

```
主密钥（Master Secret）= PRF(预主密钥, "master secret", ClientRandom + ServerRandom)

会话密钥 = PRF(主密钥, "key expansion", ServerRandom + ClientRandom)

生成6个密钥：
- 客户端加密密钥
- 服务器加密密钥
- 客户端MAC密钥
- 服务器MAC密钥
- 客户端IV
- 服务器IV
```

### TLS 1.3简化握手

```
TLS 1.3只需1-RTT：

客户端 → 服务器: Client Hello + Key Share（预共享密钥）
客户端 ← 服务器: Server Hello + Key Share + Certificate + Finished

立即开始加密传输！
```

---

## 数字证书与CA

### 证书内容

```
证书包含：
- 域名（Subject）
- 公钥
- 有效期
- 颁发机构（Issuer）
- 签名（CA用私钥签名）
```

### 证书链

```
根证书（Root CA）
   ↓ 签名
中间证书（Intermediate CA）
   ↓ 签名
服务器证书（End-Entity Certificate）
```

### 证书验证过程

```
1. 浏览器收到服务器证书
2. 验证域名是否匹配
3. 验证证书是否过期
4. 验证证书签名：
   - 用中间CA的公钥验证服务器证书签名
   - 用根CA的公钥验证中间CA证书签名
5. 根CA证书在浏览器预装列表中
6. 验证通过，信任该证书
```

### 查看证书

```bash
# OpenSSL查看证书
openssl s_client -connect baidu.com:443 -showcerts

# 输出
Certificate chain
 0 s:/CN=baidu.com
   i:/C=BE/O=GlobalSign nv-sa/CN=GlobalSign Organization Validation CA - SHA256 - G2
 1 s:/C=BE/O=GlobalSign nv-sa/CN=GlobalSign Organization Validation CA - SHA256 - G2
   i:/C=BE/O=GlobalSign nv-sa/OU=Root CA/CN=GlobalSign Root CA
```

---

## Spring Boot HTTPS配置

### 生成自签名证书

```bash
# 生成keystore（JKS格式）
keytool -genkeypair \
  -alias my-app \
  -keyalg RSA \
  -keysize 2048 \
  -keystore keystore.jks \
  -validity 365

# 输入密码和证书信息
Enter keystore password: 123456
What is your first and last name? localhost
What is the name of your organizational unit? IT
What is the name of your organization? MyCompany
...
```

### Spring Boot配置

```yaml
# application.yml
server:
  port: 8443
  ssl:
    enabled: true
    key-store: classpath:keystore.jks
    key-store-password: 123456
    key-alias: my-app
    key-store-type: JKS
```

### Java代码

```java
// HTTPS监听
@SpringBootApplication
public class Application {
    public static void main(String[] args) {
        SpringApplication.run(Application.class, args);
    }
}

// 访问
// https://localhost:8443/api/users
```

---

## 微服务HTTPS实战

### 案例1：RestTemplate HTTPS调用

```java
@Configuration
public class RestTemplateConfig {

    @Bean
    public RestTemplate httpsRestTemplate() throws Exception {
        // 信任所有证书（仅开发环境！生产禁用）
        TrustStrategy acceptingTrustStrategy = (X509Certificate[] chain, String authType) -> true;

        SSLContext sslContext = SSLContexts.custom()
            .loadTrustMaterial(null, acceptingTrustStrategy)
            .build();

        SSLConnectionSocketFactory csf = new SSLConnectionSocketFactory(
            sslContext,
            NoopHostnameVerifier.INSTANCE  // 不验证主机名（仅开发环境）
        );

        CloseableHttpClient httpClient = HttpClients.custom()
            .setSSLSocketFactory(csf)
            .build();

        HttpComponentsClientHttpRequestFactory factory =
            new HttpComponentsClientHttpRequestFactory(httpClient);

        return new RestTemplate(factory);
    }
}

// 生产环境：信任特定证书
@Bean
public RestTemplate productionRestTemplate() throws Exception {
    // 加载信任的证书
    KeyStore trustStore = KeyStore.getInstance("JKS");
    try (InputStream trustStoreStream = getClass().getResourceAsStream("/truststore.jks")) {
        trustStore.load(trustStoreStream, "password".toCharArray());
    }

    SSLContext sslContext = SSLContexts.custom()
        .loadTrustMaterial(trustStore, null)
        .build();

    SSLConnectionSocketFactory csf = new SSLConnectionSocketFactory(sslContext);

    CloseableHttpClient httpClient = HttpClients.custom()
        .setSSLSocketFactory(csf)
        .build();

    HttpComponentsClientHttpRequestFactory factory =
        new HttpComponentsClientHttpRequestFactory(httpClient);

    return new RestTemplate(factory);
}
```

### 案例2：Feign HTTPS调用

```yaml
# application.yml
feign:
  client:
    config:
      user-service:
        url: https://user-service:8443  # HTTPS
```

```java
// Feign配置（信任所有证书，仅开发）
@Configuration
public class FeignConfig {

    @Bean
    public Client feignClient() throws Exception {
        TrustManager[] trustAllCerts = new TrustManager[]{
            new X509TrustManager() {
                public X509Certificate[] getAcceptedIssuers() {
                    return new X509Certificate[0];
                }
                public void checkClientTrusted(X509Certificate[] certs, String authType) {}
                public void checkServerTrusted(X509Certificate[] certs, String authType) {}
            }
        };

        SSLContext sslContext = SSLContext.getInstance("TLS");
        sslContext.init(null, trustAllCerts, new SecureRandom());

        return new Client.Default(
            sslContext.getSocketFactory(),
            (hostname, session) -> true  // 不验证主机名
        );
    }
}
```

### 案例3：Let's Encrypt免费证书

```bash
# 安装Certbot
sudo apt-get install certbot

# 生成证书（需要域名解析到服务器）
sudo certbot certonly --standalone -d api.example.com

# 证书位置
/etc/letsencrypt/live/api.example.com/fullchain.pem  # 证书链
/etc/letsencrypt/live/api.example.com/privkey.pem    # 私钥

# 转换为JKS格式
openssl pkcs12 -export \
  -in /etc/letsencrypt/live/api.example.com/fullchain.pem \
  -inkey /etc/letsencrypt/live/api.example.com/privkey.pem \
  -out keystore.p12 \
  -name api.example.com

keytool -importkeystore \
  -srckeystore keystore.p12 -srcstoretype PKCS12 \
  -destkeystore keystore.jks -deststoretype JKS

# 自动续期（Let's Encrypt证书有效期90天）
sudo crontab -e
0 0 1 * * /usr/bin/certbot renew --quiet
```

### 案例4：Nginx反向代理HTTPS

```nginx
# nginx.conf
server {
    listen 443 ssl http2;
    server_name api.example.com;

    # SSL证书
    ssl_certificate /etc/letsencrypt/live/api.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.example.com/privkey.pem;

    # SSL配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # 代理到后端服务（HTTP）
    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# HTTP重定向到HTTPS
server {
    listen 80;
    server_name api.example.com;
    return 301 https://$server_name$request_uri;
}
```

---

## HTTPS性能优化

### 1. 会话复用

```
TLS Session Resumption：

首次握手：完整TLS握手（2-RTT）
后续连接：复用会话ID（1-RTT）

配置：
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 10m;
```

### 2. OCSP Stapling

```
在线证书状态协议：

传统方式：客户端向CA查询证书是否吊销（慢）
OCSP Stapling：服务器预先查询并附带在握手中（快）

Nginx配置：
ssl_stapling on;
ssl_stapling_verify on;
```

### 3. HTTP/2 + HTTPS

```
HTTP/2必须使用HTTPS：

listen 443 ssl http2;  # 启用HTTP/2
```

---

## 总结

### 核心要点

1. **HTTPS = HTTP + TLS/SSL**：解决窃听、篡改、冒充三大问题
2. **混合加密**：非对称加密传递密钥，对称加密传输数据
3. **TLS握手**：TLS 1.2需要2-RTT，TLS 1.3仅需1-RTT
4. **证书验证**：通过证书链验证服务器身份
5. **生产实践**：Let's Encrypt免费证书 + Nginx反向代理

### 下一篇预告

《HTTP/2协议详解：多路复用与头部压缩》
