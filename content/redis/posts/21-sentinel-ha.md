---
title: "哨兵Sentinel：Redis的自动故障转移"
date: 2025-01-21T21:20:00+08:00
draft: false
tags: ["Redis", "Sentinel", "哨兵", "高可用"]
categories: ["技术"]
description: "深入理解Redis哨兵模式的实现原理，掌握自动故障检测、主从切换、客户端自动发现等核心机制"
weight: 21
stage: 2
stageTitle: "架构原理篇"
---

## 引言

主从复制虽然实现了数据备份，但**主节点宕机后需要手动切换**。**哨兵（Sentinel）**提供了**自动故障检测和故障转移**能力，实现真正的高可用。

## 一、哨兵概述

### 1.1 什么是哨兵？

```
监控
  ↓
[哨兵1] ←→ [哨兵2] ←→ [哨兵3]  (多个哨兵相互通信)
  ↓           ↓           ↓
监控        监控        监控
  ↓           ↓           ↓
[主节点] ← [从节点1] ← [从节点2]

功能：
1. 监控：检查主从节点是否正常
2. 通知：故障通知管理员
3. 故障转移：自动提升从节点为主节点
4. 配置中心：客户端通过哨兵发现主节点
```

### 1.2 核心功能

1. **监控（Monitoring）**
   - 检查主从节点健康状态
   - 周期性发送PING命令

2. **故障检测（Failure Detection）**
   - 主观下线（SDOWN）：单个哨兵判断
   - 客观下线（ODOWN）：多数哨兵同意

3. **自动故障转移（Failover）**
   - 选举领导者哨兵
   - 选择新主节点
   - 通知从节点切换
   - 通知客户端

4. **配置中心（Configuration Provider）**
   - 客户端从哨兵获取主节点地址
   - 主节点变更自动通知客户端

## 二、哨兵部署

### 2.1 最小配置

```conf
# sentinel.conf
port 26379
sentinel monitor mymaster 127.0.0.1 6379 2  # 2个哨兵同意才判定下线
sentinel down-after-milliseconds mymaster 5000  # 5秒无响应判断下线
sentinel failover-timeout mymaster 180000  # 故障转移超时时间
sentinel parallel-syncs mymaster 1  # 同时同步的从节点数量
```

### 2.2 启动哨兵

```bash
# 方式1：
redis-sentinel sentinel.conf

# 方式2：
redis-server sentinel.conf --sentinel

# 查看哨兵状态
127.0.0.1:26379> SENTINEL masters
127.0.0.1:26379> SENTINEL slaves mymaster
127.0.0.1:26379> SENTINEL sentinels mymaster
```

### 2.3 推荐部署架构

```
机器1：Redis Master + Sentinel1
机器2：Redis Slave1 + Sentinel2
机器3：Redis Slave2 + Sentinel3

好处：
- 3个哨兵互相监控，防止误判
- 分布式部署，避免单点故障
```

## 三、故障检测机制

### 3.1 主观下线（SDOWN）

```
哨兵1每秒向主节点发送PING：
PING → 主节点
PING → 主节点
PING → (超时5秒无响应)

判断：主节点主观下线（SDOWN）
```

**配置**：
```conf
sentinel down-after-milliseconds mymaster 5000
```

### 3.2 客观下线（ODOWN）

```
哨兵1询问其他哨兵：
  ↓
"你们认为主节点下线了吗？"
  ↓
哨兵2：是的  |
哨兵3：是的  | → 2个哨兵同意（达到quorum=2）
  ↓
判断：主节点客观下线（ODOWN）
```

**配置**：
```conf
sentinel monitor mymaster 127.0.0.1 6379 2  # quorum=2
```

## 四、故障转移流程

### 4.1 选举领导者哨兵

```
哨兵1检测到主节点客观下线：
  ↓
向其他哨兵发起投票：
  "我要成为领导者，负责故障转移"
  ↓
哨兵2投票：同意
哨兵3投票：同意
  ↓
哨兵1获得多数票，成为领导者（Leader）
```

**Raft算法**：确保只有一个领导者

### 4.2 选择新主节点

**选择规则**：
1. 剔除下线和断线的从节点
2. 选择优先级最高的（replica-priority）
3. 优先级相同，选择offset最大的（数据最新）
4. offset相同，选择runid最小的

```
从节点1：priority=100, offset=1000, runid=aaa
从节点2：priority=100, offset=1200, runid=bbb
从节点3：priority=50, offset=1100, runid=ccc

选择：从节点3（优先级最高）
```

### 4.3 提升新主节点

```
领导者哨兵执行：
  ↓
1. 向从节点3发送：REPLICAOF NO ONE
   （从节点变为主节点）
  ↓
2. 向从节点1、2发送：REPLICAOF <新主节点IP> <新主节点端口>
   （指向新主节点）
  ↓
3. 更新哨兵配置：记录新主节点信息
  ↓
4. 通知其他哨兵：更新主节点信息
  ↓
5. 通知客户端：主节点地址已变更
```

### 4.4 旧主节点恢复

```
旧主节点恢复后：
  ↓
哨兵检测到旧主节点上线
  ↓
发送命令：REPLICAOF <新主节点IP> <新主节点端口>
  ↓
旧主节点变为从节点
```

## 五、客户端配置

### 5.1 Jedis示例

```java
import redis.clients.jedis.JedisSentinelPool;

// 配置哨兵连接
Set<String> sentinels = new HashSet<>();
sentinels.add("127.0.0.1:26379");
sentinels.add("127.0.0.1:26380");
sentinels.add("127.0.0.1:26381");

JedisSentinelPool pool = new JedisSentinelPool(
    "mymaster",  // 主节点名称
    sentinels,   // 哨兵列表
    poolConfig   // 连接池配置
);

// 使用
try (Jedis jedis = pool.getResource()) {
    jedis.set("key", "value");
    String value = jedis.get("key");
}

// 原理：
// 1. 客户端向哨兵询问主节点地址
// 2. 哨兵返回当前主节点信息
// 3. 客户端连接主节点
// 4. 主节点故障时，哨兵通知客户端新主节点地址
```

### 5.2 Spring Boot配置

```yaml
spring:
  redis:
    sentinel:
      master: mymaster
      nodes:
        - 127.0.0.1:26379
        - 127.0.0.1:26380
        - 127.0.0.1:26381
    password: yourpassword
```

## 六、最佳实践

### 6.1 哨兵数量

✅ **推荐**：
- **奇数个哨兵**（3个或5个）
- 最少3个哨兵（防止单点故障）

❌ **避免**：
- 2个哨兵（无法达成多数）
- 偶数个哨兵（可能脑裂）

### 6.2 quorum设置

```
quorum = (哨兵数量 / 2) + 1

示例：
- 3个哨兵 → quorum=2
- 5个哨兵 → quorum=3
```

**原则**：确保多数哨兵同意才触发故障转移

### 6.3 网络分区

**场景**：
```
网络故障：
  机房A          |          机房B
[主节点]       (网络断开)     [从节点1]
[哨兵1]          |          [从节点2]
[哨兵2]          |          [哨兵3]

问题：
- 哨兵1、2检测不到主节点 → 判断下线
- 哨兵3仍能连接主节点 → 认为正常

解决：
- quorum=2（多数原则）
- 哨兵1、2达成共识，触发故障转移
- 提升从节点1或2为新主节点
```

### 6.4 避免频繁切换

```conf
# 增大down-after-milliseconds（避免误判）
sentinel down-after-milliseconds mymaster 30000  # 30秒

# 增大failover-timeout（避免重复故障转移）
sentinel failover-timeout mymaster 180000  # 3分钟
```

## 七、监控与告警

### 7.1 关键指标

```bash
127.0.0.1:26379> INFO sentinel
sentinel_masters:1
sentinel_running_scripts:0
sentinel_scripts_queue_length:0
master0:name=mymaster,status=ok,slaves=2,sentinels=3
```

**监控项**：
- 主从节点状态（ok/down）
- 哨兵数量（确保多数在线）
- 故障转移次数（频繁切换需排查）

### 7.2 日志分析

```
# 故障检测
+sdown master mymaster 127.0.0.1 6379  # 主观下线
+odown master mymaster 127.0.0.1 6379 #quorum 2/2  # 客观下线

# 故障转移
+failover-state-select-slave master mymaster  # 选择从节点
+selected-slave slave 127.0.0.1:6380  # 选中从节点
+failover-state-send-slaveof-noone slave 127.0.0.1:6380  # 提升主节点
+switch-master mymaster 127.0.0.1 6379 127.0.0.1 6380  # 切换完成
```

## 八、总结

### 核心要点

1. **哨兵作用**
   - 监控主从节点
   - 自动故障转移
   - 配置中心

2. **故障检测**
   - 主观下线（单个哨兵）
   - 客观下线（多数哨兵）

3. **故障转移流程**
   1. 选举领导者哨兵
   2. 选择新主节点
   3. 提升新主节点
   4. 通知客户端

4. **最佳实践**
   - 奇数个哨兵（3或5）
   - quorum = (N/2) + 1
   - 分布式部署

5. **客户端**
   - 通过哨兵自动发现主节点
   - 故障转移对客户端透明

### 下一篇预告

哨兵解决了高可用问题，但**单个主节点的容量有限**。**如何实现水平扩展？Cluster集群如何分片？**

下一篇《Cluster集群：分片与容错》，我们将深入Redis集群模式。
