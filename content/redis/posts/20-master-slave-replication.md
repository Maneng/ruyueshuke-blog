---
title: "主从复制：Redis的数据同步机制"
date: 2025-01-21T21:10:00+08:00
draft: false
tags: ["Redis", "主从复制", "数据同步", "高可用"]
categories: ["技术"]
description: "深入理解Redis主从复制的实现原理，掌握全量复制、增量复制、psync机制，构建高可用Redis架构"
weight: 20
stage: 2
stageTitle: "架构原理篇"
---

## 引言

**单个Redis实例存在风险**：硬件故障、数据丢失、无法扩展读能力。**主从复制（Master-Slave Replication）**是Redis高可用的基础。

今天我们深入剖析Redis主从复制的实现原理。

## 一、主从复制概述

### 1.1 什么是主从复制？

```
主节点（Master）                从节点（Slave1、Slave2）
    ↓                                ↓
[写操作] SET key value         [只读] GET key
    ↓                                ↑
自动同步数据 ───────────────────────┘

特点：
- 主节点：可读可写
- 从节点：只读（默认）
- 数据自动同步：主 → 从
```

### 1.2 应用场景

1. **读写分离**：主写从读，提升读性能
2. **数据备份**：从节点作为数据备份
3. **高可用**：主节点宕机，从节点可提升为主
4. **异地容灾**：从节点部署在不同机房

## 二、配置主从复制

### 2.1 基本配置

```bash
# 从节点配置
redis-server --port 6380 --replicaof 127.0.0.1 6379

# 或修改redis.conf
replicaof 127.0.0.1 6379  # 指定主节点
```

### 2.2 运行时配置

```bash
# 从节点执行
127.0.0.1:6380> REPLICAOF 127.0.0.1 6379
OK

# 取消复制
127.0.0.1:6380> REPLICAOF NO ONE
OK  # 变为独立节点
```

### 2.3 查看复制状态

```bash
# 主节点
127.0.0.1:6379> INFO replication
role:master
connected_slaves:2
slave0:ip=127.0.0.1,port=6380,state=online,offset=1234
slave1:ip=127.0.0.1,port=6381,state=online,offset=1234

# 从节点
127.0.0.1:6380> INFO replication
role:slave
master_host:127.0.0.1
master_port:6379
master_link_status:up
```

## 三、复制流程

### 3.1 全量复制（Full Resynchronization）

**触发时机**：
- 首次连接主节点
- 断线后重连，且偏移量丢失

**流程**：
```
从节点                           主节点
  |                                |
  | 1. PSYNC ? -1                 |
  |──────────────────────────────>|
  |                                | 2. 开始BGSAVE
  |                                | 3. 生成RDB文件
  | 4. +FULLRESYNC <runid> <offset>|
  |<──────────────────────────────|
  | 5. 接收RDB文件                 |
  |<══════════════════════════════| （大文件传输）
  | 6. 清空旧数据                  |
  | 7. 载入RDB                     |
  |                                |
  | 8. 接收积压的命令              |
  |<══════════════════════════════|
  | 9. 完成同步                    |
```

### 3.2 增量复制（Partial Resynchronization）

**触发时机**：
- 短暂断线后重连
- 偏移量仍在积压缓冲区内

**流程**：
```
从节点                           主节点
  |                                |
  | 1. PSYNC <runid> <offset>     |
  |──────────────────────────────>|
  |                                | 2. 检查offset是否在缓冲区
  | 3. +CONTINUE                   |
  |<──────────────────────────────|
  | 4. 接收增量命令                |
  |<══════════════════════════════|
  | 5. 完成同步                    |
```

### 3.3 命令传播（Command Propagation）

**正常运行时**：
```
客户端发送命令：SET key value
    ↓
主节点执行命令
    ↓
记录到积压缓冲区
    ↓
异步发送给所有从节点
    ↓
从节点执行命令
```

## 四、PSYNC机制

### 4.1 核心概念

**runid**（运行ID）：
- 每个Redis实例的唯一标识
- 重启后变化

**replication offset**（复制偏移量）：
- 主从双方都维护
- 记录已复制的字节数
- 用于判断数据一致性

**replication backlog**（积压缓冲区）：
- 固定大小的环形缓冲区（默认1MB）
- 保存最近的写命令
- 用于增量复制

### 4.2 PSYNC命令

```bash
# 首次同步
PSYNC ? -1

# 重连同步
PSYNC <master_runid> <offset>

# 主节点响应：
+FULLRESYNC <runid> <offset>  # 全量复制
+CONTINUE                     # 增量复制
-ERR                          # 错误
```

### 4.3 积压缓冲区

```
主节点写命令：
SET key1 v1  → offset=0
SET key2 v2  → offset=10
SET key3 v3  → offset=20
       ↓
[===== 积压缓冲区（1MB）=====]
| offset=0: SET key1 v1       |
| offset=10: SET key2 v2      |
| offset=20: SET key3 v3      |
| ...                         |
[=============================]

从节点断线重连：
- 如果offset=20仍在缓冲区 → 增量复制
- 如果offset已被覆盖 → 全量复制
```

**配置参数**：
```conf
# 积压缓冲区大小
repl-backlog-size 1mb

# 缓冲区保留时间（从节点全部断开后）
repl-backlog-ttl 3600
```

## 五、性能优化

### 5.1 避免全量复制

**优化策略**：

1. **增大积压缓冲区**：
   ```conf
   repl-backlog-size 10mb  # 根据写入速度调整
   ```

2. **减少断线概率**：
   ```conf
   # 从节点配置
   repl-timeout 60  # 超时时间
   repl-ping-slave-period 10  # 心跳间隔
   ```

3. **避免主节点重启**：
   - 使用持久化恢复数据
   - 避免runid变化

### 5.2 主节点优化

```conf
# 1. 关闭RDB持久化（由从节点备份）
save ""

# 2. 开启无磁盘复制（适合高速网络）
repl-diskless-sync yes

# 3. 限制同时同步的从节点数量
repl-diskless-sync-delay 5  # 延迟5秒，收集多个从节点
```

### 5.3 从节点优化

```conf
# 1. 只读模式（默认）
replica-read-only yes

# 2. 优先级（用于选主）
replica-priority 100  # 越小优先级越高

# 3. 禁用持久化（如果仅用于读）
save ""
appendonly no
```

## 六、常见问题

### 6.1 复制风暴

**问题**：
```
主节点宕机重启 → runid变化
    ↓
所有从节点全量复制
    ↓
主节点负载暴增（N个RDB + 网络传输）
```

**解决**：
- 分批重启从节点
- 使用持久化恢复主节点数据（保持runid）
- 使用哨兵自动故障转移

### 6.2 数据延迟

**问题**：主从数据不一致

**原因**：
- 网络延迟
- 从节点处理慢

**检测**：
```bash
# 查看延迟（字节数）
127.0.0.1:6379> INFO replication
master_repl_offset:10000  # 主节点
slave0:...,offset=9500    # 从节点落后500字节
```

**优化**：
- 使用Pipeline批量操作
- 避免慢命令（KEYS、FLUSHALL）
- 升级网络带宽

### 6.3 主从切换

**问题**：主节点宕机，如何切换？

**手动切换**：
```bash
# 1. 选择一个从节点
127.0.0.1:6380> REPLICAOF NO ONE  # 变为主节点

# 2. 其他从节点指向新主
127.0.0.1:6381> REPLICAOF 127.0.0.1 6380
```

**自动切换**：使用哨兵（Sentinel）

## 七、总结

### 核心要点

1. **主从复制作用**
   - 读写分离、数据备份
   - 高可用基础

2. **复制类型**
   - 全量复制：首次或offset丢失
   - 增量复制：短暂断线，offset在缓冲区

3. **PSYNC机制**
   - runid：主节点标识
   - offset：复制进度
   - backlog：积压缓冲区

4. **性能优化**
   - 增大积压缓冲区
   - 无磁盘复制
   - 分批同步

5. **常见问题**
   - 复制风暴：分批重启
   - 数据延迟：监控offset
   - 主从切换：使用哨兵

### 下一篇预告

主从复制解决了数据备份问题，但**如何实现自动故障转移？哨兵（Sentinel）如何工作？**

下一篇《哨兵Sentinel：高可用方案》，我们将深入哨兵机制。
