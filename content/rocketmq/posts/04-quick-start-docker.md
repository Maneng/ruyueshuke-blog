---
title: "RocketMQ入门04：快速上手 - Docker一键部署与第一条消息"
date: 2025-11-13T13:00:00+08:00
draft: false
tags: ["RocketMQ", "Docker", "实战教程", "快速入门"]
categories: ["技术"]
description: "通过 Docker 快速搭建 RocketMQ 环境，发送和消费第一条消息，包含完整的实战步骤和问题排查"
series: ["RocketMQ从入门到精通"]
weight: 4
stage: 1
stageTitle: "基础入门篇"
---

## 引言：5分钟上手 RocketMQ

不需要复杂的环境配置，不需要编译源码，通过 Docker，我们可以在 5 分钟内搭建一个完整的 RocketMQ 环境，并成功发送第一条消息。

让我们开始这段激动人心的旅程！

## 一、环境准备

### 1.1 前置要求

```bash
# 检查 Docker 版本（需要 20.10+）
docker --version
# Docker version 24.0.5, build ced0996

# 检查 Docker Compose 版本（需要 2.0+）
docker-compose --version
# Docker Compose version v2.20.2

# 检查系统资源
# 建议：4GB+ 内存，10GB+ 磁盘空间
docker system info | grep -E "Memory|Storage"
```

### 1.2 创建项目目录

```bash
# 创建项目目录
mkdir -p ~/rocketmq-demo
cd ~/rocketmq-demo

# 创建必要的子目录
mkdir -p data/namesrv/logs data/broker/logs data/broker/store
mkdir -p conf
```

## 二、Docker Compose 部署

### 2.1 编写 docker-compose.yml

```yaml
# docker-compose.yml
version: '3.8'

services:
  # NameServer 服务
  namesrv:
    image: apache/rocketmq:5.1.3
    container_name: rocketmq-namesrv
    ports:
      - "9876:9876"
    environment:
      JAVA_OPT: "-Duser.home=/opt"
      JAVA_OPT_EXT: "-Xms512M -Xmx512M -Xmn128m"
    volumes:
      - ./data/namesrv/logs:/opt/logs
    command: sh mqnamesrv
    networks:
      - rocketmq-net

  # Broker 服务
  broker:
    image: apache/rocketmq:5.1.3
    container_name: rocketmq-broker
    ports:
      - "10909:10909"
      - "10911:10911"
      - "10912:10912"
    environment:
      JAVA_OPT_EXT: "-Xms1G -Xmx1G -Xmn512m"
    volumes:
      - ./data/broker/logs:/opt/logs
      - ./data/broker/store:/opt/store
      - ./conf/broker.conf:/opt/conf/broker.conf
    command: sh mqbroker -n namesrv:9876 -c /opt/conf/broker.conf
    depends_on:
      - namesrv
    networks:
      - rocketmq-net

  # 控制台服务
  dashboard:
    image: apacherocketmq/rocketmq-dashboard:latest
    container_name: rocketmq-dashboard
    ports:
      - "8080:8080"
    environment:
      JAVA_OPTS: "-Drocketmq.namesrv.addr=namesrv:9876 -Dcom.rocketmq.sendMessageWithVIPChannel=false"
    depends_on:
      - namesrv
      - broker
    networks:
      - rocketmq-net

networks:
  rocketmq-net:
    driver: bridge
```

### 2.2 配置 Broker

```bash
# conf/broker.conf
cat > conf/broker.conf << 'EOF'
# 集群名称
brokerClusterName = DefaultCluster
# broker 名称
brokerName = broker-a
# 0 表示 Master，>0 表示 Slave
brokerId = 0
# 删除文件时间点，默认凌晨 4 点
deleteWhen = 04
# 文件保留时间，默认 48 小时
fileReservedTime = 48
# Broker 的角色
brokerRole = ASYNC_MASTER
# 刷盘方式
flushDiskType = ASYNC_FLUSH
# 存储路径
storePathRootDir = /opt/store
# 队列存储路径
storePathCommitLog = /opt/store/commitlog
# 自动创建 Topic
autoCreateTopicEnable = true
# 自动创建订阅组
autoCreateSubscriptionGroup = true
# Broker 监听端口
listenPort = 10911
# 是否允许 Broker 自动创建 Topic
brokerIP1 = broker
EOF
```

### 2.3 启动服务

```bash
# 启动所有服务
docker-compose up -d

# 查看服务状态
docker-compose ps

# 输出示例：
# NAME                   IMAGE                                      STATUS
# rocketmq-namesrv       apache/rocketmq:5.1.3                     Up 30 seconds
# rocketmq-broker        apache/rocketmq:5.1.3                     Up 20 seconds
# rocketmq-dashboard     apacherocketmq/rocketmq-dashboard:latest  Up 10 seconds

# 查看日志
docker-compose logs -f broker
```

## 三、发送第一条消息

### 3.1 创建 Java 项目

```xml
<!-- pom.xml -->
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0
         http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.example</groupId>
    <artifactId>rocketmq-demo</artifactId>
    <version>1.0.0</version>

    <properties>
        <maven.compiler.source>8</maven.compiler.source>
        <maven.compiler.target>8</maven.compiler.target>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>

    <dependencies>
        <!-- RocketMQ 客户端 -->
        <dependency>
            <groupId>org.apache.rocketmq</groupId>
            <artifactId>rocketmq-client-java</artifactId>
            <version>5.0.5</version>
        </dependency>

        <!-- 日志 -->
        <dependency>
            <groupId>ch.qos.logback</groupId>
            <artifactId>logback-classic</artifactId>
            <version>1.2.11</version>
        </dependency>
    </dependencies>
</project>
```

### 3.2 编写生产者代码

```java
// QuickProducer.java
package com.example.rocketmq;

import org.apache.rocketmq.client.producer.DefaultMQProducer;
import org.apache.rocketmq.client.producer.SendResult;
import org.apache.rocketmq.common.message.Message;
import org.apache.rocketmq.remoting.common.RemotingHelper;

public class QuickProducer {
    public static void main(String[] args) throws Exception {
        // 1. 创建生产者，指定生产者组名
        DefaultMQProducer producer = new DefaultMQProducer("quick_producer_group");

        // 2. 指定 NameServer 地址
        producer.setNamesrvAddr("localhost:9876");

        // 3. 启动生产者
        producer.start();
        System.out.println("Producer Started.");

        // 4. 发送消息
        for (int i = 0; i < 10; i++) {
            // 创建消息对象
            Message msg = new Message(
                "QuickStartTopic",     // Topic
                "TagA",                // Tag
                ("Hello RocketMQ " + i).getBytes(RemotingHelper.DEFAULT_CHARSET)
            );

            // 发送消息
            SendResult sendResult = producer.send(msg);

            // 打印发送结果
            System.out.printf("%s%n", sendResult);

            Thread.sleep(1000);
        }

        // 5. 关闭生产者
        producer.shutdown();
        System.out.println("Producer Shutdown.");
    }
}
```

### 3.3 编写消费者代码

```java
// QuickConsumer.java
package com.example.rocketmq;

import org.apache.rocketmq.client.consumer.DefaultMQPushConsumer;
import org.apache.rocketmq.client.consumer.listener.ConsumeConcurrentlyContext;
import org.apache.rocketmq.client.consumer.listener.ConsumeConcurrentlyStatus;
import org.apache.rocketmq.client.consumer.listener.MessageListenerConcurrently;
import org.apache.rocketmq.common.message.MessageExt;
import org.apache.rocketmq.common.protocol.heartbeat.MessageModel;

import java.util.List;

public class QuickConsumer {
    public static void main(String[] args) throws Exception {
        // 1. 创建消费者，指定消费者组名
        DefaultMQPushConsumer consumer = new DefaultMQPushConsumer("quick_consumer_group");

        // 2. 指定 NameServer 地址
        consumer.setNamesrvAddr("localhost:9876");

        // 3. 订阅 Topic 和 Tag
        consumer.subscribe("QuickStartTopic", "*");

        // 4. 设置消费模式（默认集群模式）
        consumer.setMessageModel(MessageModel.CLUSTERING);

        // 5. 注册消息监听器
        consumer.registerMessageListener(new MessageListenerConcurrently() {
            @Override
            public ConsumeConcurrentlyStatus consumeMessage(
                    List<MessageExt> messages,
                    ConsumeConcurrentlyContext context) {

                for (MessageExt message : messages) {
                    System.out.printf("Consume message: %s%n",
                        new String(message.getBody()));
                }

                // 返回消费状态：成功
                return ConsumeConcurrentlyStatus.CONSUME_SUCCESS;
            }
        });

        // 6. 启动消费者
        consumer.start();
        System.out.println("Consumer Started.");

        // 保持运行
        Thread.sleep(Long.MAX_VALUE);
    }
}
```

## 四、运行测试

### 4.1 运行步骤

```bash
# 1. 先启动消费者（新终端）
mvn compile exec:java -Dexec.mainClass="com.example.rocketmq.QuickConsumer"

# 输出：
# Consumer Started.
# 等待消息...

# 2. 启动生产者（新终端）
mvn compile exec:java -Dexec.mainClass="com.example.rocketmq.QuickProducer"

# 输出：
# Producer Started.
# SendResult [sendStatus=SEND_OK, msgId=7F00000100002A9F0000000000000000, ...
# SendResult [sendStatus=SEND_OK, msgId=7F00000100002A9F00000000000000B8, ...
# ...
# Producer Shutdown.

# 3. 查看消费者输出
# Consume message: Hello RocketMQ 0
# Consume message: Hello RocketMQ 1
# ...
```

### 4.2 使用控制台查看

打开浏览器访问：http://localhost:8080

```
控制台功能：
├── 集群状态
│   ├── Broker 列表
│   └── NameServer 状态
├── Topic 管理
│   ├── Topic 列表
│   ├── 消息查询
│   └── 消息轨迹
├── 消费者管理
│   ├── 消费组列表
│   ├── 消费进度
│   └── 消费者详情
└── 生产者管理
    └── 生产者列表
```

## 五、进阶实践

### 5.1 发送不同类型的消息

```java
public class AdvancedProducer {

    // 1. 同步发送
    public void syncSend() throws Exception {
        Message msg = new Message("TopicTest", "TagA", "OrderID001",
            "Hello World".getBytes());
        SendResult sendResult = producer.send(msg);
        System.out.printf("%s%n", sendResult);
    }

    // 2. 异步发送
    public void asyncSend() throws Exception {
        Message msg = new Message("TopicTest", "TagA", "OrderID002",
            "Hello World".getBytes());
        producer.send(msg, new SendCallback() {
            @Override
            public void onSuccess(SendResult sendResult) {
                System.out.printf("异步发送成功：%s%n", sendResult);
            }

            @Override
            public void onException(Throwable e) {
                System.out.printf("异步发送失败：%s%n", e);
            }
        });
    }

    // 3. 单向发送（不关心发送结果）
    public void onewaySend() throws Exception {
        Message msg = new Message("TopicTest", "TagA", "OrderID003",
            "Hello World".getBytes());
        producer.sendOneway(msg);
    }

    // 4. 批量发送
    public void batchSend() throws Exception {
        List<Message> messages = new ArrayList<>();
        for (int i = 0; i < 10; i++) {
            messages.add(new Message("BatchTopic", "TagA",
                ("Hello " + i).getBytes()));
        }
        SendResult sendResult = producer.send(messages);
        System.out.printf("批量发送结果：%s%n", sendResult);
    }
}
```

### 5.2 延迟消息

```java
public void sendDelayMessage() throws Exception {
    Message msg = new Message("DelayTopic", "TagA",
        "Delay Message".getBytes());

    // 设置延迟级别
    // 1s 5s 10s 30s 1m 2m 3m 4m 5m 6m 7m 8m 9m 10m 20m 30m 1h 2h
    msg.setDelayTimeLevel(3);  // 10 秒后投递

    SendResult sendResult = producer.send(msg);
    System.out.printf("延迟消息发送：%s%n", sendResult);
}
```

### 5.3 顺序消息

```java
// 顺序消息生产者
public void sendOrderlyMessage() throws Exception {
    for (int orderId = 0; orderId < 10; orderId++) {
        for (String status : Arrays.asList("创建", "付款", "发货", "收货")) {
            Message msg = new Message("OrderTopic", "Order",
                (orderId + ":" + status).getBytes());

            // 同一订单的消息发送到同一个队列
            SendResult sendResult = producer.send(msg,
                new MessageQueueSelector() {
                    @Override
                    public MessageQueue select(List<MessageQueue> mqs,
                        Message msg, Object arg) {
                        Integer orderId = (Integer) arg;
                        int index = orderId % mqs.size();
                        return mqs.get(index);
                    }
                }, orderId);

            System.out.printf("OrderId: %d, Status: %s, SendResult: %s%n",
                orderId, status, sendResult);
        }
    }
}
```

## 六、常见问题排查

### 6.1 连接失败

```bash
# 问题：connect to <localhost:9876> failed
# 解决：检查 NameServer 是否启动
docker ps | grep namesrv

# 检查端口
netstat -an | grep 9876

# 查看防火墙
sudo iptables -L -n | grep 9876
```

### 6.2 消息发送失败

```java
// 问题：No route info of this topic
// 解决：设置自动创建 Topic
producer.setCreateTopicKey("AUTO_CREATE_TOPIC_KEY");

// 或手动创建 Topic
sh mqadmin updateTopic -n localhost:9876 -t QuickStartTopic -c DefaultCluster
```

### 6.3 消费不到消息

```java
// 检查点：
// 1. Topic 是否正确
consumer.subscribe("QuickStartTopic", "*");

// 2. 消费组是否正确
consumer.setConsumerGroup("quick_consumer_group");

// 3. 消费位点
consumer.setConsumeFromWhere(ConsumeFromWhere.CONSUME_FROM_FIRST_OFFSET);

// 4. 检查消费进度
sh mqadmin consumerProgress -n localhost:9876 -g quick_consumer_group
```

### 6.4 性能优化

```yaml
# 优化 docker-compose.yml
broker:
  environment:
    # 增加内存
    JAVA_OPT_EXT: "-Xms2G -Xmx2G -Xmn1G"
  # 增加 ulimits
  ulimits:
    nofile:
      soft: 65535
      hard: 65535
```

## 七、清理环境

```bash
# 停止所有服务
docker-compose down

# 清理数据（慎用）
docker-compose down -v
rm -rf data/

# 清理镜像（可选）
docker rmi apache/rocketmq:5.1.3
docker rmi apacherocketmq/rocketmq-dashboard:latest
```

## 八、总结

通过本篇教程，我们完成了：

✅ 使用 Docker Compose 一键部署 RocketMQ
✅ 编写生产者发送消息
✅ 编写消费者接收消息
✅ 使用控制台管理和监控
✅ 尝试不同类型的消息发送
✅ 学习常见问题排查方法

这只是 RocketMQ 旅程的开始，接下来我们将深入学习 RocketMQ 的核心概念和高级特性。

## 下一篇预告

成功发送了第一条消息后，下一篇我们将深入理解 RocketMQ 的核心概念：Producer、Consumer、Broker 的工作原理，为后续的深入学习打下基础。

---

**动手练习**：

1. 尝试修改消息内容，发送 JSON 格式的消息
2. 尝试创建多个消费者，观察负载均衡效果
3. 尝试停止 Broker 后重启，观察消息是否丢失

记录你的实验结果，我们下篇见！