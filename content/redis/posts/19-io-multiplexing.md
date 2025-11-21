---
title: "IO多路复用：Reactor模式与epoll原理"
date: 2025-01-21T21:00:00+08:00
draft: false
tags: ["Redis", "IO多路复用", "epoll", "Reactor"]
categories: ["技术"]
description: "深入理解Redis的事件驱动架构，掌握select/poll/epoll的区别，理解Reactor模式如何实现高并发非阻塞I/O"
weight: 19
stage: 2
stageTitle: "架构原理篇"
---

## 引言

Redis单线程却能处理10000+并发连接，秘密就在于**IO多路复用（I/O Multiplexing）**。今天我们深入理解这个高并发的核心机制。

## 一、什么是IO多路复用？

**核心思想**：
> 一个线程监听多个文件描述符（socket连接），哪个准备好就处理哪个

```
传统阻塞I/O：
线程1 → 监听客户端1 → 阻塞等待
线程2 → 监听客户端2 → 阻塞等待
...
线程N → 监听客户端N → 阻塞等待

IO多路复用：
线程1 → 监听所有客户端 → 有事件就处理，没事件就等待
```

## 二、三种实现：select、poll、epoll

### 2.1 select（最古老，1983年）

```c
fd_set readfds;
FD_ZERO(&readfds);
FD_SET(fd1, &readfds);
FD_SET(fd2, &readfds);

select(max_fd + 1, &readfds, NULL, NULL, NULL);

// 缺点：
// 1. fd数量限制（默认1024）
// 2. 需要遍历所有fd检查哪个就绪（O(n)）
// 3. 每次调用需要拷贝fd_set到内核
```

### 2.2 poll（1997年）

```c
struct pollfd fds[N];
fds[0].fd = fd1;
fds[0].events = POLLIN;

poll(fds, N, -1);

// 改进：无fd数量限制
// 缺点：仍需遍历所有fd（O(n)）
```

### 2.3 epoll（Linux 2.6，2002年）

```c
// 1. 创建epoll实例
int epfd = epoll_create(1);

// 2. 添加监听的fd
struct epoll_event ev;
ev.events = EPOLLIN;
ev.data.fd = fd1;
epoll_ctl(epfd, EPOLL_CTL_ADD, fd1, &ev);

// 3. 等待事件
struct epoll_event events[MAX_EVENTS];
int n = epoll_wait(epfd, events, MAX_EVENTS, -1);

// 优势：
// ✅ O(1)时间复杂度（只返回就绪的fd）
// ✅ 无fd数量限制
// ✅ 无需每次拷贝fd列表
```

**性能对比**：

| 特性 | select | poll | epoll |
|------|--------|------|-------|
| fd数量限制 | ❌ 1024 | ✅ 无限制 | ✅ 无限制 |
| 时间复杂度 | O(n) | O(n) | **O(1)** |
| 内核拷贝 | 每次 | 每次 | 无需 |
| 适用连接数 | < 1000 | < 5000 | **> 10000** |

**Redis的选择**：
- Linux: epoll
- macOS/FreeBSD: kqueue
- Windows: select（Windows性能差）

## 三、Redis的Reactor模式

### 3.1 事件循环（Event Loop）

```c
void aeMain(aeEventLoop *eventLoop) {
    eventLoop->stop = 0;
    while (!eventLoop->stop) {
        // 1. 执行beforesleep回调
        if (eventLoop->beforesleep != NULL)
            eventLoop->beforesleep(eventLoop);

        // 2. 等待事件（epoll_wait）
        numevents = aeApiPoll(eventLoop, tvp);

        // 3. 处理文件事件
        for (j = 0; j < numevents; j++) {
            aeFileEvent *fe = &eventLoop->events[fd];

            // 可读事件（接收客户端命令）
            if (fe->mask & AE_READABLE) {
                fe->rfileProc(eventLoop, fd, fe->clientData, mask);
            }

            // 可写事件（发送响应）
            if (fe->mask & AE_WRITABLE) {
                fe->wfileProc(eventLoop, fd, fe->clientData, mask);
            }
        }

        // 4. 处理时间事件（定时任务）
        processTimeEvents(eventLoop);
    }
}
```

### 3.2 文件事件处理

```
客户端发送命令：
1. epoll_wait返回fd就绪
2. 调用readQueryFromClient（读取命令）
3. 解析命令（RESP协议）
4. 执行命令（单线程处理）
5. 将响应加入输出缓冲区
6. 注册可写事件
7. epoll_wait返回可写
8. 调用sendReplyToClient（发送响应）
```

### 3.3 时间事件处理

```c
// 定时任务
int serverCron(struct aeEventLoop *eventLoop, long long id, void *clientData) {
    // 1. 更新统计信息
    updateCachedTime();

    // 2. 检查客户端超时
    clientsCron();

    // 3. 触发BGSAVE、AOF重写
    backgroundSaveDoneHandler();

    // 4. 渐进式rehash
    if (server.activerehashing) {
        dictRehashMilliseconds(server.db[j].dict, 1);
    }

    return 100;  // 100ms后再次执行
}
```

## 四、epoll的两种触发模式

### 4.1 水平触发（LT，Level Triggered）

```
特点：只要fd就绪，epoll_wait就会返回

示例：
1. 客户端发送100字节
2. epoll_wait返回（可读）
3. 读取50字节
4. epoll_wait再次返回（仍可读，剩余50字节）

优势：不会丢失事件
劣势：可能重复通知
```

**Redis使用LT模式**（更简单、可靠）

### 4.2 边缘触发（ET，Edge Triggered）

```
特点：只在fd状态变化时通知一次

示例：
1. 客户端发送100字节
2. epoll_wait返回（可读）
3. 读取50字节
4. epoll_wait不再返回（需要一次性读完）

优势：减少通知次数
劣势：容易丢失事件（需要非阻塞+循环读取）
```

## 五、性能优化技巧

### 5.1 Pipeline批量操作

```java
// 减少网络往返
redis.executePipelined((RedisCallback<Object>) connection -> {
    for (int i = 0; i < 10000; i++) {
        connection.set(("key:" + i).getBytes(), ("value:" + i).getBytes());
    }
    return null;
});

// 效果：
// - 10000次操作 → 1次网络往返
// - epoll_wait调用次数：10000 → 2（1次读，1次写）
```

### 5.2 避免慢命令

```bash
# ❌ 不好：阻塞事件循环
KEYS *  # O(n)
FLUSHALL  # O(n)

# ✅ 好：使用渐进式命令
SCAN 0 COUNT 100  # 分批获取
FLUSHALL ASYNC  # 异步删除
```

## 六、总结

### 核心要点

1. **IO多路复用**
   - 一个线程监听多个连接
   - epoll：O(1)时间复杂度，支持海量连接

2. **Reactor模式**
   - 事件循环：等待事件 → 处理事件
   - 文件事件：客户端请求/响应
   - 时间事件：定时任务

3. **epoll优势**
   - 无fd数量限制
   - O(1)获取就绪fd
   - 无需每次拷贝fd列表

4. **LT vs ET**
   - Redis使用LT模式
   - 简单可靠，不会丢失事件

### 下一篇预告

理解了事件驱动架构后，你是否好奇：**Redis主从复制如何实现数据同步？全量复制和增量复制有什么区别？**

下一篇《主从复制：数据同步机制》，我们将深入剖析Redis的主从架构。

---

**思考题**：
1. 为什么epoll比select/poll快？
2. Redis为什么选择LT模式而不是ET模式？
3. 如果10000个客户端同时发送命令，Redis如何保证公平性？
