---
title: "WebSocket与gRPC：全双工通信与高效RPC"
date: 2025-11-21T18:20:00+08:00
draft: false
tags: ["计算机网络", "WebSocket", "gRPC", "实时通信"]
categories: ["技术"]
description: "深入理解WebSocket全双工通信，gRPC流式RPC，以及微服务场景的协议选择与实践"
series: ["计算机网络从入门到精通"]
weight: 21
stage: 3
stageTitle: "应用层协议篇"
---

## WebSocket：全双工实时通信

### HTTP的局限

**HTTP请求-响应模式**：
```
客户端 → 服务器: 请求
客户端 ← 服务器: 响应

问题：
- 服务器无法主动推送
- 实时性差（需要轮询）
```

**轮询（Polling）**：
```
客户端每隔1秒请求一次：

GET /api/messages（1秒后）
GET /api/messages（2秒后）
GET /api/messages（3秒后）
...

问题：大量无效请求，浪费资源
```

**长轮询（Long Polling）**：
```
客户端请求，服务器挂起直到有新消息：

GET /api/messages
... 服务器等待30秒 ...
← 返回新消息

问题：仍然是请求-响应模式，连接频繁断开重连
```

### WebSocket协议

**核心特点**：
- 全双工通信（双向同时传输）
- 基于TCP
- 低开销（头部仅2字节）
- 持久连接

**协议升级**：
```http
# 客户端发起升级请求
GET /chat HTTP/1.1
Host: example.com
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==
Sec-WebSocket-Version: 13

# 服务器同意升级
HTTP/1.1 101 Switching Protocols
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=

# 升级完成，使用WebSocket通信
```

---

## Spring Boot WebSocket

### 服务端

```java
// WebSocket配置
@Configuration
@EnableWebSocket
public class WebSocketConfig implements WebSocketConfigurer {

    @Override
    public void registerWebSocketHandlers(WebSocketHandlerRegistry registry) {
        registry.addHandler(chatHandler(), "/chat")
            .setAllowedOrigins("*");  // CORS
    }

    @Bean
    public ChatHandler chatHandler() {
        return new ChatHandler();
    }
}

// WebSocket处理器
@Component
public class ChatHandler extends TextWebSocketHandler {

    private static final Set<WebSocketSession> sessions = new CopyOnWriteArraySet<>();

    @Override
    public void afterConnectionEstablished(WebSocketSession session) {
        sessions.add(session);
        System.out.println("新连接：" + session.getId());
    }

    @Override
    protected void handleTextMessage(WebSocketSession session, TextMessage message) throws Exception {
        String payload = message.getPayload();
        System.out.println("收到消息：" + payload);

        // 广播给所有客户端
        for (WebSocketSession s : sessions) {
            if (s.isOpen()) {
                s.sendMessage(new TextMessage("服务器转发：" + payload));
            }
        }
    }

    @Override
    public void afterConnectionClosed(WebSocketSession session, CloseStatus status) {
        sessions.remove(session);
        System.out.println("连接关闭：" + session.getId());
    }
}
```

### 客户端（JavaScript）

```javascript
// 建立WebSocket连接
const ws = new WebSocket('ws://localhost:8080/chat');

// 连接打开
ws.onopen = () => {
    console.log('WebSocket连接已建立');
    ws.send('你好，服务器');
};

// 接收消息
ws.onmessage = (event) => {
    console.log('收到消息：', event.data);
};

// 连接关闭
ws.onclose = () => {
    console.log('WebSocket连接已关闭');
};

// 连接错误
ws.onerror = (error) => {
    console.error('WebSocket错误：', error);
};
```

---

## STOMP：WebSocket消息协议

### 问题

**原始WebSocket只传输文本/二进制**：
- 没有消息格式
- 没有路由
- 没有主题订阅

### STOMP协议

**Simple Text Oriented Messaging Protocol**

```
Spring Boot STOMP配置：

@Configuration
@EnableWebSocketMessageBroker
public class WebSocketConfig implements WebSocketMessageBrokerConfigurer {

    @Override
    public void configureMessageBroker(MessageBrokerRegistry config) {
        config.enableSimpleBroker("/topic");  // 订阅前缀
        config.setApplicationDestinationPrefixes("/app");  // 发送前缀
    }

    @Override
    public void registerStompEndpoints(StompEndpointRegistry registry) {
        registry.addEndpoint("/ws")
            .setAllowedOrigins("*")
            .withSockJS();  // 降级支持
    }
}

// 消息控制器
@Controller
public class ChatController {

    @MessageMapping("/chat")  // 客户端发送到 /app/chat
    @SendTo("/topic/messages")  // 广播到 /topic/messages
    public ChatMessage send(ChatMessage message) {
        return message;
    }
}
```

**JavaScript客户端**：
```javascript
const stompClient = Stomp.over(new SockJS('/ws'));

stompClient.connect({}, () => {
    // 订阅主题
    stompClient.subscribe('/topic/messages', (message) => {
        console.log('收到消息：', JSON.parse(message.body));
    });

    // 发送消息
    stompClient.send('/app/chat', {}, JSON.stringify({
        user: '张三',
        content: '你好'
    }));
});
```

---

## gRPC：高效RPC框架

### gRPC特点

- 基于HTTP/2（多路复用、头部压缩）
- Protocol Buffers序列化（二进制、高效）
- 支持4种RPC模式
- 跨语言

### 定义服务（.proto）

```protobuf
syntax = "proto3";

package user;

// 用户服务
service UserService {
  // 一元RPC（请求-响应）
  rpc GetUser(GetUserRequest) returns (User);

  // 服务器流RPC（一个请求，多个响应）
  rpc ListUsers(Empty) returns (stream User);

  // 客户端流RPC（多个请求，一个响应）
  rpc CreateUsers(stream User) returns (Summary);

  // 双向流RPC（多个请求，多个响应）
  rpc ChatUsers(stream Message) returns (stream Message);
}

message User {
  int64 id = 1;
  string name = 2;
  string email = 3;
}

message GetUserRequest {
  int64 id = 1;
}

message Empty {}

message Summary {
  int32 count = 1;
}

message Message {
  string text = 1;
}
```

### Java实现

**服务端**：
```java
@GrpcService
public class UserServiceImpl extends UserServiceGrpc.UserServiceImplBase {

    // 一元RPC
    @Override
    public void getUser(GetUserRequest request, StreamObserver<User> responseObserver) {
        User user = User.newBuilder()
            .setId(request.getId())
            .setName("张三")
            .setEmail("zhangsan@example.com")
            .build();

        responseObserver.onNext(user);
        responseObserver.onCompleted();
    }

    // 服务器流RPC
    @Override
    public void listUsers(Empty request, StreamObserver<User> responseObserver) {
        List<User> users = getUsersFromDB();

        for (User user : users) {
            responseObserver.onNext(user);  // 流式发送
        }

        responseObserver.onCompleted();
    }

    // 客户端流RPC
    @Override
    public StreamObserver<User> createUsers(StreamObserver<Summary> responseObserver) {
        return new StreamObserver<User>() {
            int count = 0;

            @Override
            public void onNext(User user) {
                // 接收客户端流式发送的用户
                saveUser(user);
                count++;
            }

            @Override
            public void onCompleted() {
                // 客户端发送完成，返回摘要
                Summary summary = Summary.newBuilder().setCount(count).build();
                responseObserver.onNext(summary);
                responseObserver.onCompleted();
            }

            @Override
            public void onError(Throwable t) {
                log.error("错误", t);
            }
        };
    }

    // 双向流RPC
    @Override
    public StreamObserver<Message> chatUsers(StreamObserver<Message> responseObserver) {
        return new StreamObserver<Message>() {
            @Override
            public void onNext(Message message) {
                // 收到客户端消息，立即响应
                Message response = Message.newBuilder()
                    .setText("服务器收到：" + message.getText())
                    .build();
                responseObserver.onNext(response);
            }

            @Override
            public void onCompleted() {
                responseObserver.onCompleted();
            }

            @Override
            public void onError(Throwable t) {
                log.error("错误", t);
            }
        };
    }
}
```

**客户端**：
```java
// 创建Channel
ManagedChannel channel = ManagedChannelBuilder
    .forAddress("localhost", 9090)
    .usePlaintext()
    .build();

UserServiceGrpc.UserServiceBlockingStub blockingStub =
    UserServiceGrpc.newBlockingStub(channel);

// 一元RPC
User user = blockingStub.getUser(GetUserRequest.newBuilder().setId(1).build());

// 服务器流RPC
Iterator<User> users = blockingStub.listUsers(Empty.newBuilder().build());
while (users.hasNext()) {
    User u = users.next();
    System.out.println(u.getName());
}
```

---

## WebSocket vs gRPC vs HTTP

| 特性 | HTTP | WebSocket | gRPC |
|------|------|-----------|------|
| **通信模式** | 请求-响应 | 全双工 | 请求-响应/流式 |
| **传输层** | TCP | TCP | TCP (HTTP/2) |
| **开销** | 较大（头部） | 小（2字节） | 小（二进制） |
| **服务器推送** | ❌ | ✅ | ✅（流式RPC） |
| **适用场景** | RESTful API | 实时通信 | 微服务RPC |
| **序列化** | JSON/XML | 文本/二进制 | Protobuf |

---

## 微服务实战案例

### 案例1：WebSocket消息推送

```java
// 订单服务：订单状态变更时推送
@Service
public class OrderService {

    @Autowired
    private SimpMessagingTemplate messagingTemplate;

    public void updateOrderStatus(Long orderId, OrderStatus status) {
        Order order = orderRepository.findById(orderId);
        order.setStatus(status);
        orderRepository.save(order);

        // WebSocket推送给前端
        messagingTemplate.convertAndSend(
            "/topic/order/" + orderId,
            new OrderStatusEvent(orderId, status)
        );
    }
}
```

### 案例2：gRPC服务间调用

```java
// 订单服务调用用户服务（gRPC）
@Service
public class OrderService {

    @GrpcClient("user-service")
    private UserServiceGrpc.UserServiceBlockingStub userStub;

    public Order createOrder(CreateOrderRequest request) {
        // gRPC调用用户服务
        User user = userStub.getUser(GetUserRequest.newBuilder()
            .setId(request.getUserId())
            .build());

        // 创建订单
        Order order = new Order();
        order.setUserId(user.getId());
        order.setUsername(user.getName());
        // ...

        return orderRepository.save(order);
    }
}
```

### 案例3：流式日志聚合

```java
// 日志服务：gRPC流式接收日志
@GrpcService
public class LogServiceImpl extends LogServiceGrpc.LogServiceImplBase {

    @Override
    public StreamObserver<LogEntry> collectLogs(StreamObserver<LogSummary> responseObserver) {
        return new StreamObserver<LogEntry>() {
            int count = 0;

            @Override
            public void onNext(LogEntry log) {
                // 接收日志
                System.out.println(log.getMessage());
                count++;
            }

            @Override
            public void onCompleted() {
                // 返回摘要
                LogSummary summary = LogSummary.newBuilder()
                    .setCount(count)
                    .build();
                responseObserver.onNext(summary);
                responseObserver.onCompleted();
            }

            @Override
            public void onError(Throwable t) {
                log.error("错误", t);
            }
        };
    }
}
```

---

## 总结

### 核心要点

1. **WebSocket**：全双工实时通信，适合聊天、推送、实时协作
2. **STOMP**：WebSocket之上的消息协议，支持主题订阅
3. **gRPC**：基于HTTP/2的高效RPC，支持4种RPC模式
4. **Protocol Buffers**：二进制序列化，比JSON更高效
5. **微服务应用**：gRPC用于服务间调用，WebSocket用于前后端实时通信

### 第三阶段完成！

至此，我们已经完成了第三阶段《应用层协议篇》全部7篇文章！
