---
title: "持久化进阶：AOF日志详解"
date: 2025-01-21T14:30:00+08:00
draft: false
tags: ["Redis", "AOF", "持久化", "日志"]
categories: ["技术"]
description: "深入理解Redis的AOF持久化机制，掌握三种同步策略、AOF重写原理、混合持久化模式。实现更高的数据安全性。"
weight: 10
stage: 1
stageTitle: "基础入门篇"
---

## 引言

上一篇我们学习了RDB快照，但它有一个缺点：**两次快照之间的数据可能丢失**。

如果你的业务对数据安全性要求很高（比如交易系统、订单系统），RDB就不够了。这时候需要**AOF（Append Only File）**。

**AOF的核心思想**：记录每一条写命令，恢复时重新执行。

```
RDB：拍照存档（快但可能丢数据）
AOF：录像回放（慢但更安全）
```

## 一、AOF的本质

### 1.1 什么是AOF？

AOF是**命令日志（Command Log）**：

```
Redis执行写命令
    ↓
记录命令到AOF文件（appendonly.aof）
    ↓
服务器重启时
    ↓
重新执行AOF文件中的所有命令
    ↓
恢复数据
```

**示例**：

```bash
# Redis执行的命令
127.0.0.1:6379> SET name "张三"
OK
127.0.0.1:6379> SADD tags "Java" "Redis"
(integer) 2
127.0.0.1:6379> ZADD rank 100 "user1"
(integer) 1

# AOF文件内容（RESP协议格式）
*2
$6
SELECT
$1
0
*3
$3
SET
$4
name
$6
张三
*4
$4
SADD
$4
tags
$4
Java
$5
Redis
*4
$4
ZADD
$4
rank
$3
100
$5
user1
```

### 1.2 AOF配置

**redis.conf**：

```conf
# 开启AOF
appendonly yes

# AOF文件名
appendfilename "appendonly.aof"

# AOF文件目录（与RDB共用）
dir /var/lib/redis
```

**动态开启**：

```bash
127.0.0.1:6379> CONFIG SET appendonly yes
OK

# 持久化配置
127.0.0.1:6379> CONFIG REWRITE
OK
```

### 1.3 AOF文件格式（RESP协议）

**RESP（Redis Serialization Protocol）**：

```
*<参数个数>\r\n
$<参数长度>\r\n
<参数内容>\r\n
...
```

**示例解析**：

```
命令：SET name "张三"

AOF编码：
*3              # 3个参数
$3              # 第1个参数长度3
SET             # 第1个参数内容
$4              # 第2个参数长度4
name            # 第2个参数内容
$6              # 第3个参数长度6（UTF-8编码）
张三             # 第3个参数内容
```

## 二、三种同步策略

### 2.1 同步策略对比

AOF有三种同步策略（fsync频率）：

| 策略 | 说明 | 性能 | 数据安全性 | 丢失数据 |
|------|------|------|-----------|---------|
| **always** | 每条命令都同步 | 慢 | 最高 | 0条 |
| **everysec** | 每秒同步一次 | 较快 | 较高 | 最多1秒 |
| **no** | 由OS决定 | 最快 | 低 | 可能几十秒 |

### 2.2 always（最安全）

**配置**：

```conf
appendfsync always
```

**工作流程**：

```
1. 执行写命令
    ↓
2. 写入AOF缓冲区
    ↓
3. 立即调用fsync()同步到磁盘
    ↓
4. 返回成功
```

**优点**：
- 数据最安全，不会丢失

**缺点**：
- 性能最差（每条命令都要磁盘IO）
- QPS可能只有几百

**适用场景**：
- 金融交易系统
- 订单支付系统
- 绝对不能丢数据的场景

### 2.3 everysec（推荐，默认）

**配置**：

```conf
appendfsync everysec
```

**工作流程**：

```
1. 执行写命令
    ↓
2. 写入AOF缓冲区
    ↓
3. 立即返回成功（不等待fsync）
    ↓
4. 后台线程每秒调用一次fsync()
```

**优点**：
- 性能好（QPS可达几万）
- 数据安全性高（最多丢失1秒）
- **兼顾性能和安全**

**缺点**：
- 宕机可能丢失1秒数据

**适用场景**：
- **大多数生产环境（推荐）**
- 缓存系统
- 社交应用

### 2.4 no（最快）

**配置**：

```conf
appendfsync no
```

**工作流程**：

```
1. 执行写命令
    ↓
2. 写入AOF缓冲区
    ↓
3. 立即返回成功
    ↓
4. 由操作系统决定何时fsync（通常30秒）
```

**优点**：
- 性能最好（无fsync开销）

**缺点**：
- 宕机可能丢失几十秒数据

**适用场景**：
- 对数据安全性要求极低
- 纯缓存场景
- 不推荐

## 三、AOF重写

### 3.1 为什么需要重写？

**问题**：AOF文件会越来越大

```
执行100次INCR counter
AOF文件记录100条命令：
INCR counter
INCR counter
...（100次）

实际上，只需要一条命令：
SET counter 100
```

**文件膨胀**：

```
初始：appendonly.aof = 10MB
1天后：appendonly.aof = 500MB
1周后：appendonly.aof = 3GB
1个月后：appendonly.aof = 15GB  # 太大了！
```

**影响**：
- 占用磁盘空间
- 恢复时间长（要重放所有命令）
- 性能下降

### 3.2 AOF重写原理

**核心思想**：用当前内存数据生成新的AOF文件

```
不是：
INCR counter（重放100次）

而是：
SET counter 100（一条命令）
```

**重写流程**：

```
1. 父进程fork子进程
    ↓
2. 子进程遍历内存数据，生成新AOF文件
    ↓
3. 父进程继续处理请求，新命令写入：
   - 旧AOF文件（追加）
   - AOF重写缓冲区（额外）
    ↓
4. 子进程完成重写，通知父进程
    ↓
5. 父进程将重写缓冲区的命令追加到新AOF文件
    ↓
6. 用新AOF文件替换旧文件
```

**示例**：

```bash
# 原AOF文件（1000条命令）
SET key1 "value1"
SET key1 "value2"
SET key1 "value3"
DEL key2
SET key2 "value4"
...（1000条）

# 重写后AOF文件（2条命令）
SET key1 "value3"  # 最终值
SET key2 "value4"
```

### 3.3 触发AOF重写

**手动触发**：

```bash
127.0.0.1:6379> BGREWRITEAOF
Background append only file rewriting started
```

**自动触发**：

```conf
# redis.conf

# 当前AOF文件大小超过上次重写后大小的100%时触发
auto-aof-rewrite-percentage 100

# AOF文件至少要达到64MB才触发
auto-aof-rewrite-min-size 64mb
```

**触发条件**：

```
同时满足：
1. 当前AOF文件 >= 上次重写后大小 * (1 + 100/100)
2. 当前AOF文件 >= 64MB

示例：
上次重写后：100MB
当前文件：210MB
触发条件：210MB >= 100MB * 2 且 210MB >= 64MB
结果：触发重写
```

**查看状态**：

```bash
127.0.0.1:6379> INFO persistence
aof_enabled:1
aof_rewrite_in_progress:0          # 是否正在重写
aof_last_rewrite_time_sec:5        # 上次重写耗时
aof_current_rewrite_time_sec:-1    # 当前重写耗时
aof_last_bgrewrite_status:ok       # 上次重写状态
aof_current_size:2048000           # 当前AOF文件大小
aof_base_size:1024000              # 上次重写后大小
```

## 四、混合持久化（Redis 4.0+）

### 4.1 为什么需要混合持久化？

**问题**：

```
RDB：快但可能丢数据
AOF：安全但恢复慢

能否结合两者优点？
```

**混合持久化**：

```
AOF重写时：
- 前半部分：RDB格式（二进制快照）
- 后半部分：AOF格式（增量命令）
```

**优点**：
- ✅ 恢复速度快（大部分用RDB）
- ✅ 数据安全性高（增量用AOF）
- ✅ 文件体积小（RDB压缩）

### 4.2 开启混合持久化

**配置**：

```conf
# redis.conf（Redis 4.0+）
aof-use-rdb-preamble yes
```

**动态开启**：

```bash
127.0.0.1:6379> CONFIG SET aof-use-rdb-preamble yes
OK
```

### 4.3 混合持久化文件格式

```
appendonly.aof文件结构：

[REDIS RDB格式]  # 前半部分（快照）
[AOF格式命令]    # 后半部分（增量）

示例：
REDIS0009...（RDB二进制数据）
*2
$6
SELECT
$1
0
*3
$3
SET
$3
key
$5
value
...（AOF命令）
```

**恢复流程**：

```
1. 先加载RDB部分（快速恢复大部分数据）
    ↓
2. 再重放AOF部分（恢复增量数据）
    ↓
3. 完成恢复
```

## 五、RDB vs AOF vs 混合

### 5.1 三种方式对比

| 维度 | RDB | AOF | 混合持久化 |
|------|-----|-----|-----------|
| **数据完整性** | 可能丢失 | 最多丢失1秒 | 最多丢失1秒 |
| **文件大小** | 小 | 大 | 中等 |
| **恢复速度** | 快（2-3分钟） | 慢（20-30分钟） | 较快（5-10分钟） |
| **性能影响** | fork阻塞 | 每秒fsync | fork+每秒fsync |
| **兼容性** | 高 | 高 | Redis 4.0+ |

### 5.2 选择指南

**场景1：纯缓存（可接受数据丢失）**

```conf
# 只用RDB，定时备份
appendonly no
save 900 1
save 300 10
save 60 10000
```

**场景2：高可用（数据重要）**

```conf
# 推荐：AOF + 混合持久化
appendonly yes
appendfsync everysec
aof-use-rdb-preamble yes
```

**场景3：极致性能（牺牲安全性）**

```conf
# RDB + AOF no
appendonly yes
appendfsync no
save 3600 1
```

**场景4：极致安全（牺牲性能）**

```conf
# AOF always
appendonly yes
appendfsync always
```

### 5.3 推荐配置（生产环境）

```conf
# redis.conf

# ===== RDB配置 =====
save 900 1
save 300 10
save 60 10000
dbfilename dump.rdb

# ===== AOF配置 =====
appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec

# ===== AOF重写 =====
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb

# ===== 混合持久化（Redis 4.0+）=====
aof-use-rdb-preamble yes

# ===== 目录 =====
dir /var/lib/redis
```

## 六、实战案例

### 6.1 数据恢复

**恢复优先级**：

```
1. 如果AOF开启，优先用AOF恢复
2. 如果AOF关闭，用RDB恢复
3. 如果都没有，从空数据库开始
```

**恢复流程**：

```bash
# 1. 停止Redis
systemctl stop redis

# 2. 检查AOF和RDB文件
ls -lh /var/lib/redis/
-rw-r--r-- appendonly.aof  # 优先
-rw-r--r-- dump.rdb

# 3. 启动Redis（自动加载）
systemctl start redis

# 4. 查看日志
tail -f /var/log/redis/redis.log
# 输出：
# DB loaded from append only file: 5.123 seconds
```

### 6.2 AOF文件修复

**AOF文件损坏**：

```bash
# 检查AOF文件
redis-check-aof appendonly.aof
# 输出：
# AOF analyzed: ok
# 或
# AOF is not valid: ...

# 修复AOF文件
redis-check-aof --fix appendonly.aof
# 警告：会删除损坏部分及之后的数据
```

### 6.3 Java代码监控

```java
@Component
public class PersistenceMonitor {

    @Scheduled(fixedRate = 60000)
    public void checkAOF() {
        Properties info = redis.getRequiredConnectionFactory()
                               .getConnection()
                               .info("persistence");

        // AOF状态
        String aofEnabled = info.getProperty("aof_enabled");
        String aofRewriteInProgress = info.getProperty("aof_rewrite_in_progress");
        String aofLastRewriteStatus = info.getProperty("aof_last_bgrewrite_status");
        Long aofCurrentSize = Long.parseLong(info.getProperty("aof_current_size"));

        log.info("AOF状态: enabled={}, rewriting={}, status={}, size={}MB",
                 aofEnabled,
                 aofRewriteInProgress,
                 aofLastRewriteStatus,
                 aofCurrentSize / 1024 / 1024);

        // 告警：AOF文件过大
        if (aofCurrentSize > 1024 * 1024 * 1024) {  // 1GB
            log.warn("AOF文件过大: {}MB", aofCurrentSize / 1024 / 1024);
        }

        // 告警：重写失败
        if ("err".equals(aofLastRewriteStatus)) {
            log.error("AOF重写失败");
            alertService.sendAlert("Redis AOF重写失败");
        }
    }
}
```

## 七、常见问题

### Q1: RDB和AOF能同时开启吗？

**可以，且推荐**：

```conf
# 同时开启
appendonly yes
save 900 1

# 恢复时优先用AOF（更完整）
```

### Q2: AOF重写会阻塞吗？

**fork时短暂阻塞**（毫秒级），之后不阻塞：

```
fork子进程：阻塞100-200ms
子进程重写：不阻塞
父进程追加：不阻塞
```

### Q3: everysec真的每秒执行一次吗？

**不一定**，可能延迟：

```
场景：上次fsync还没完成
行为：跳过本次fsync，等待下次

结果：可能2秒才执行一次
极端情况：可能丢失2秒数据
```

## 八、总结

### 核心要点

1. **AOF是命令日志**：记录每条写命令，重放恢复
2. **三种同步策略**：always（最安全）、everysec（推荐）、no（最快）
3. **AOF重写**：压缩文件，用当前数据生成新AOF
4. **混合持久化**：RDB+AOF，兼顾速度和安全
5. **恢复优先级**：AOF > RDB > 空数据库
6. **推荐配置**：everysec + 混合持久化

### 同步策略选择

```
对数据安全要求极高？
└─ Yes → always

性能和安全兼顾？
└─ Yes → everysec（推荐）

纯缓存，可丢数据？
└─ Yes → no 或 关闭AOF
```

### 下一步

掌握了持久化后，下一篇我们将学习**Redis事务**：
- MULTI/EXEC命令
- WATCH乐观锁
- 与关系型数据库事务的区别

---

**思考题**：
1. 为什么AOF恢复比RDB慢？
2. 混合持久化的文件为什么比纯AOF小？
3. 如果服务器突然断电，everysec最多丢失多少数据？

下一篇见！
