---
title: "RocketMQ生产07：安全机制配置 - ACL 权限控制实战"
date: 2025-11-15T13:00:00+08:00
draft: false
tags: ["RocketMQ", "ACL", "权限控制", "安全"]
categories: ["技术"]
description: "为 RocketMQ 配置细粒度的权限控制，防止未授权访问和误操作"
series: ["RocketMQ从入门到精通"]
weight: 37
stage: 4
stageTitle: "生产实践篇"
---

## 引言：安全的重要性

某天，开发环境的测试账号误连到生产环境，执行了 `deleteTopic` 命令，核心业务 Topic 被删除，服务全面瘫痪...

**安全风险**：
- ❌ 任何人都能创建/删除 Topic
- ❌ 未授权用户读取敏感消息
- ❌ 恶意攻击导致集群瘫痪
- ❌ 内部人员误操作

**本文目标**：
- ✅ 理解 RocketMQ ACL 机制
- ✅ 配置细粒度权限控制
- ✅ 实现用户/应用隔离
- ✅ 建立安全最佳实践

---

## 一、ACL 基础概念

### 1.1 什么是 ACL？

**ACL（Access Control List）**：访问控制列表，用于定义"谁可以对哪些资源执行什么操作"。

```
ACL 三要素：
1. Subject（主体）：谁在访问？（用户、应用）
2. Resource（资源）：访问什么？（Topic、Group）
3. Permission（权限）：做什么操作？（PUB、SUB、DENY）
```

---

### 1.2 RocketMQ ACL 权限类型

| 权限 | 含义 | 适用对象 |
|------|------|---------|
| **PUB** | 发布权限（Producer） | Topic |
| **SUB** | 订阅权限（Consumer） | Topic + Group |
| **DENY** | 禁止访问 | Topic + Group |
| **ANY** | 所有权限 | Topic + Group |

---

### 1.3 ACL 工作流程

```
┌─────────┐      ┌─────────────────┐      ┌──────────┐
│ Client  │      │   ACL Validator │      │  Broker  │
└────┬────┘      └────────┬────────┘      └────┬─────┘
     │                    │                    │
     │ 1. 发送请求         │                    │
     │  (AccessKey)       │                    │
     ├───────────────────>│                    │
     │                    │                    │
     │                    │ 2. 校验签名         │
     │                    │    校验权限         │
     │                    │                    │
     │                    │ 3. 权限通过         │
     │                    ├───────────────────>│
     │                    │                    │
     │ 4. 返回结果         │                    │
     │<──────────────────────────────────────────┤
     │                    │                    │
```

---

## 二、启用 ACL

### 2.1 Broker 配置

```properties
# broker.conf

# 启用 ACL
aclEnable=true

# ACL 配置文件路径（相对于 ROCKETMQ_HOME）
accessKey=conf/plain_acl.yml
```

---

### 2.2 创建 ACL 配置文件

```bash
# 创建配置文件
vim /opt/rocketmq/conf/plain_acl.yml
```

```yaml
# plain_acl.yml

# 全局白名单（IP）
globalWhiteRemoteAddresses:
  - 10.10.103.*      # 内网IP段
  - 192.168.0.*

# 用户配置
accounts:
  # 管理员账号
  - accessKey: RocketMQ_Admin
    secretKey: 12345678
    whiteRemoteAddress:      # 白名单IP（可选）
    admin: true              # 管理员权限
    defaultTopicPerm: DENY   # 默认禁止所有Topic
    defaultGroupPerm: DENY   # 默认禁止所有Group
    topicPerms:
      - "*=PUB|SUB"          # 所有Topic的发布和订阅权限
    groupPerms:
      - "*=PUB|SUB"

  # 订单服务账号
  - accessKey: order_service
    secretKey: order_pwd_2024
    whiteRemoteAddress: 192.168.1.*  # 只允许订单服务器IP
    admin: false
    defaultTopicPerm: DENY
    defaultGroupPerm: DENY
    topicPerms:
      - "order_topic=PUB"    # 只能发送订单消息
      - "order_result_topic=SUB"  # 只能消费结果消息
    groupPerms:
      - "order_consumer_group=SUB"

  # 库存服务账号
  - accessKey: inventory_service
    secretKey: inventory_pwd_2024
    whiteRemoteAddress:
    admin: false
    defaultTopicPerm: DENY
    defaultGroupPerm: DENY
    topicPerms:
      - "order_topic=SUB"    # 只能消费订单消息
      - "inventory_topic=PUB"  # 只能发送库存消息
    groupPerms:
      - "inventory_consumer_group=SUB"

  # 只读账号（监控用）
  - accessKey: monitor_user
    secretKey: monitor_pwd_2024
    admin: false
    defaultTopicPerm: SUB    # 默认只读
    defaultGroupPerm: SUB
    topicPerms:
      - "*=SUB"
```

---

### 2.3 重启 Broker

```bash
# 停止 Broker
sh /opt/rocketmq/bin/mqshutdown broker

# 启动 Broker（应用 ACL 配置）
sh /opt/rocketmq/bin/mqbroker -c /opt/rocketmq/conf/broker.conf &

# 验证 ACL 是否生效
tail -f /opt/rocketmq/logs/rocketmqlogs/broker.log | grep ACL
# 输出：ACL is enabled
```

---

## 三、客户端配置

### 3.1 Producer 配置

```java
import org.apache.rocketmq.acl.common.AclClientRPCHook;
import org.apache.rocketmq.acl.common.SessionCredentials;
import org.apache.rocketmq.client.producer.DefaultMQProducer;

public class AclProducerExample {

    public static void main(String[] args) throws Exception {
        // 1. 创建 ACL 凭证
        String accessKey = "order_service";
        String secretKey = "order_pwd_2024";
        SessionCredentials credentials = new SessionCredentials(accessKey, secretKey);
        AclClientRPCHook aclHook = new AclClientRPCHook(credentials);

        // 2. 创建 Producer（传入 ACL Hook）
        DefaultMQProducer producer = new DefaultMQProducer(
            "order_producer_group",
            aclHook,  // ACL Hook
            true,     // 启用消息轨迹
            null      // 自定义轨迹Topic（可选）
        );

        producer.setNamesrvAddr("127.0.0.1:9876");
        producer.start();

        // 3. 发送消息
        Message msg = new Message("order_topic", "Hello RocketMQ with ACL".getBytes());
        SendResult result = producer.send(msg);
        System.out.println("发送结果：" + result.getSendStatus());

        producer.shutdown();
    }
}
```

---

### 3.2 Consumer 配置

```java
import org.apache.rocketmq.acl.common.AclClientRPCHook;
import org.apache.rocketmq.acl.common.SessionCredentials;
import org.apache.rocketmq.client.consumer.DefaultMQPushConsumer;
import org.apache.rocketmq.client.consumer.listener.*;
import org.apache.rocketmq.common.message.MessageExt;

import java.util.List;

public class AclConsumerExample {

    public static void main(String[] args) throws Exception {
        // 1. 创建 ACL 凭证
        String accessKey = "inventory_service";
        String secretKey = "inventory_pwd_2024";
        SessionCredentials credentials = new SessionCredentials(accessKey, secretKey);
        AclClientRPCHook aclHook = new AclClientRPCHook(credentials);

        // 2. 创建 Consumer（传入 ACL Hook）
        DefaultMQPushConsumer consumer = new DefaultMQPushConsumer(
            "inventory_consumer_group",
            aclHook,  // ACL Hook
            null      // 消息轨迹相关配置
        );

        consumer.setNamesrvAddr("127.0.0.1:9876");
        consumer.subscribe("order_topic", "*");

        // 3. 注册消息监听器
        consumer.registerMessageListener(new MessageListenerConcurrently() {
            @Override
            public ConsumeConcurrentlyStatus consumeMessage(
                List<MessageExt> msgs,
                ConsumeConcurrentlyContext context) {

                for (MessageExt msg : msgs) {
                    System.out.println("收到消息：" + new String(msg.getBody()));
                }
                return ConsumeConcurrentlyStatus.CONSUME_SUCCESS;
            }
        });

        consumer.start();
        System.out.println("Consumer 启动成功");
    }
}
```

---

### 3.3 Spring Boot 配置

```yaml
# application.yml
rocketmq:
  name-server: 127.0.0.1:9876
  producer:
    group: order_producer_group
    access-key: order_service        # ACL AccessKey
    secret-key: order_pwd_2024       # ACL SecretKey
    send-message-timeout: 3000
    retry-times-when-send-failed: 2

  consumer:
    group: inventory_consumer_group
    access-key: inventory_service
    secret-key: inventory_pwd_2024
    consume-thread-min: 5
    consume-thread-max: 10
```

**Producer 代码**：
```java
@Service
public class OrderProducer {

    @Autowired
    private RocketMQTemplate rocketMQTemplate;

    public void sendOrder(OrderDTO order) {
        // Spring Boot 自动注入 ACL 凭证
        rocketMQTemplate.convertAndSend("order_topic", order);
    }
}
```

---

## 四、权限测试

### 4.1 测试场景 1：正常访问

```java
// 使用 order_service 账号发送消息到 order_topic（有权限）
String accessKey = "order_service";
String secretKey = "order_pwd_2024";
SessionCredentials credentials = new SessionCredentials(accessKey, secretKey);
AclClientRPCHook aclHook = new AclClientRPCHook(credentials);

DefaultMQProducer producer = new DefaultMQProducer("test_group", aclHook, false, null);
producer.setNamesrvAddr("127.0.0.1:9876");
producer.start();

Message msg = new Message("order_topic", "test".getBytes());
SendResult result = producer.send(msg);

// 输出：SEND_OK
System.out.println(result.getSendStatus());
```

---

### 4.2 测试场景 2：权限拒绝

```java
// 使用 order_service 账号发送消息到 inventory_topic（无权限）
Message msg = new Message("inventory_topic", "test".getBytes());

try {
    SendResult result = producer.send(msg);
} catch (Exception e) {
    // 输出：CODE: 207 DESC: No permission to send message to topic
    e.printStackTrace();
}
```

---

### 4.3 测试场景 3：错误凭证

```java
// 使用错误的 SecretKey
String accessKey = "order_service";
String secretKey = "wrong_password";
SessionCredentials credentials = new SessionCredentials(accessKey, secretKey);
AclClientRPCHook aclHook = new AclClientRPCHook(credentials);

DefaultMQProducer producer = new DefaultMQProducer("test_group", aclHook, false, null);
producer.setNamesrvAddr("127.0.0.1:9876");

try {
    producer.start();
} catch (Exception e) {
    // 输出：CODE: 204 DESC: signature doesn't match, maybe accessKey or secretKey is wrong
    e.printStackTrace();
}
```

---

## 五、高级配置

### 5.1 IP 白名单

```yaml
# plain_acl.yml

accounts:
  - accessKey: web_service
    secretKey: web_pwd_2024
    whiteRemoteAddress: 192.168.1.100,192.168.1.101  # 逗号分隔多个IP
    admin: false
    topicPerms:
      - "web_topic=PUB"
```

**IP 格式支持**：
- 单个 IP：`192.168.1.100`
- IP 段：`192.168.1.*`
- CIDR：`192.168.1.0/24`
- 多个 IP：`192.168.1.100,192.168.1.101`

---

### 5.2 通配符权限

```yaml
accounts:
  - accessKey: log_service
    secretKey: log_pwd_2024
    admin: false
    topicPerms:
      - "log_*=PUB"       # 所有以 log_ 开头的 Topic 有发送权限
      - "*_result=SUB"    # 所有以 _result 结尾的 Topic 有订阅权限
```

---

### 5.3 动态更新 ACL

```bash
# 修改 plain_acl.yml 后，无需重启 Broker

# 1. 修改配置文件
vim /opt/rocketmq/conf/plain_acl.yml

# 2. 通知 Broker 重新加载 ACL
sh mqadmin updateAcl -n 127.0.0.1:9876

# 3. 验证新配置
# 客户端重新连接即可使用新权限
```

---

## 六、安全最佳实践

### 6.1 权限设计原则

```
1. 最小权限原则：只授予必要的权限
2. 职责分离：不同服务使用不同账号
3. 定期审计：定期检查权限配置
4. 密钥轮换：定期更换 SecretKey
5. 白名单限制：限制访问IP范围
```

---

### 6.2 账号命名规范

```
{服务名}_{环境}_{角色}

示例：
- order_prod_producer     # 订单服务生产环境Producer
- order_prod_consumer     # 订单服务生产环境Consumer
- inventory_test_producer # 库存服务测试环境Producer
- monitor_prod_readonly   # 监控服务生产环境只读
```

---

### 6.3 密钥管理

**不要硬编码**：
```java
// ❌ 错误：硬编码密钥
String secretKey = "order_pwd_2024";

// ✅ 正确：从配置中心读取
String secretKey = ConfigClient.get("rocketmq.order.secretKey");

// ✅ 正确：从环境变量读取
String secretKey = System.getenv("ROCKETMQ_SECRET_KEY");
```

**定期轮换密钥**：
```bash
# 1. 生成新密钥
NEW_SECRET_KEY=$(openssl rand -base64 32)

# 2. 更新配置文件
vim /opt/rocketmq/conf/plain_acl.yml
# 修改 secretKey

# 3. 通知 Broker 重新加载
sh mqadmin updateAcl -n 127.0.0.1:9876

# 4. 灰度更新客户端（新旧密钥并存）

# 5. 验证新密钥生效后，删除旧密钥
```

---

### 6.4 监控与审计

```yaml
# prometheus/alert_rules.yml

groups:
  - name: rocketmq_security
    rules:
      # 1. ACL 认证失败告警
      - alert: AclAuthenticationFailed
        expr: rate(rocketmq_acl_auth_failed_total[5m]) > 10
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "ACL 认证失败频繁"
          description: "过去 5 分钟认证失败 {{ $value }} 次"

      # 2. 未授权访问告警
      - alert: UnauthorizedAccess
        expr: rate(rocketmq_acl_permission_denied_total[5m]) > 5
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "检测到未授权访问"
          description: "过去 5 分钟未授权访问 {{ $value }} 次"
```

---

## 七、故障排查

### 7.1 常见错误

#### 错误 1：CODE: 204（签名不匹配）

```
org.apache.rocketmq.remoting.exception.RemotingCommandException:
CODE: 204 DESC: signature doesn't match
```

**原因**：
- AccessKey 或 SecretKey 错误
- 时间不同步（时间差 > 5 分钟）

**解决方法**：
```bash
# 1. 检查凭证是否正确
cat /opt/rocketmq/conf/plain_acl.yml | grep -A 5 "order_service"

# 2. 检查服务器时间同步
ntpdate -u pool.ntp.org
date
```

---

#### 错误 2：CODE: 207（无权限）

```
org.apache.rocketmq.remoting.exception.RemotingCommandException:
CODE: 207 DESC: No permission to send message to topic
```

**原因**：
- 账号没有对应 Topic 的发送权限

**解决方法**：
```yaml
# 修改 plain_acl.yml，添加权限
accounts:
  - accessKey: order_service
    secretKey: order_pwd_2024
    topicPerms:
      - "order_topic=PUB"  # 添加发送权限
```

---

#### 错误 3：IP 白名单拒绝

```
CODE: 205 DESC: The remoteAddress is not in whitelist
```

**原因**：
- 客户端 IP 不在白名单中

**解决方法**：
```yaml
# 添加 IP 到白名单
accounts:
  - accessKey: order_service
    whiteRemoteAddress: 192.168.1.100,192.168.1.101
```

---

### 7.2 调试技巧

```bash
# 1. 查看 Broker ACL 日志
tail -f /opt/rocketmq/logs/rocketmqlogs/broker.log | grep ACL

# 2. 查看认证失败详情
grep "CODE: 204\|CODE: 207" /opt/rocketmq/logs/rocketmqlogs/broker.log

# 3. 验证配置文件语法
cat /opt/rocketmq/conf/plain_acl.yml | python -m yaml

# 4. 测试连接（使用 mqadmin）
sh mqadmin sendMessage \
  -n 127.0.0.1:9876 \
  -t test_topic \
  -p "test message" \
  -ak order_service \
  -sk order_pwd_2024
```

---

## 八、总结

### ACL 配置检查清单

- [ ] 启用 ACL（aclEnable=true）
- [ ] 创建 plain_acl.yml 配置文件
- [ ] 为每个服务创建独立账号
- [ ] 配置最小权限
- [ ] 限制 IP 白名单
- [ ] 密钥不要硬编码
- [ ] 配置监控告警
- [ ] 定期审计权限
- [ ] 定期轮换密钥
- [ ] 编写应急预案

### 权限设计示例

| 账号 | Topic 权限 | Group 权限 | 适用场景 |
|------|-----------|-----------|---------|
| admin | *=PUB\|SUB | *=PUB\|SUB | 管理员 |
| order_producer | order_topic=PUB | order_group=SUB | 订单生产者 |
| inventory_consumer | order_topic=SUB | inventory_group=SUB | 库存消费者 |
| monitor_readonly | *=SUB | *=SUB | 监控只读 |

### 核心要点

```
1. 生产环境必须启用 ACL
2. 每个服务使用独立账号
3. 遵循最小权限原则
4. 定期审计和轮换密钥
5. 配置监控告警
```

---

**下一篇预告**：《版本升级策略 - 平滑迁移与回滚方案》，我们将讲解如何安全地升级 RocketMQ 版本，避免业务中断。

**本文关键词**：`ACL` `权限控制` `安全配置` `访问控制`
