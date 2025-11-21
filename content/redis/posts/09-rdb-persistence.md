---
title: "持久化入门：RDB快照详解"
date: 2025-01-21T14:00:00+08:00
draft: false
tags: ["Redis", "RDB", "持久化", "备份"]
categories: ["技术"]
description: "深入理解Redis的RDB持久化机制，掌握fork原理、快照策略、备份恢复流程。保证数据安全，应对服务器宕机。"
weight: 9
stage: 1
stageTitle: "基础入门篇"
---

## 引言

前面我们学习了Redis的数据类型和过期机制，但有一个关键问题：

**Redis是内存数据库，服务器重启或宕机后，数据会丢失吗？**

答案是：**如果不配置持久化，数据会丢失**。

Redis提供两种持久化方式：
1. **RDB（Redis Database）**：定时快照，保存某个时间点的数据副本
2. **AOF（Append Only File）**：记录写命令日志，恢复时重放

今天我们先学习RDB，下一篇学习AOF。

## 一、RDB的本质

### 1.1 什么是RDB？

RDB就是**内存快照（Snapshot）**：

```
Redis内存数据
    ↓
某个时间点
    ↓
完整复制到磁盘
    ↓
生成dump.rdb文件
```

类似于：
- 给电脑硬盘做Ghost镜像
- 虚拟机快照
- 游戏存档

**特点**：
- ✅ **全量备份**：保存完整数据
- ✅ **体积小**：二进制压缩格式
- ✅ **恢复快**：直接加载到内存
- ❌ **丢失风险**：两次快照之间的数据会丢失

### 1.2 RDB文件在哪里？

**查看配置**：

```bash
127.0.0.1:6379> CONFIG GET dir
1) "dir"
2) "/var/lib/redis"  # RDB文件目录

127.0.0.1:6379> CONFIG GET dbfilename
1) "dbfilename"
2) "dump.rdb"  # RDB文件名

# 完整路径：/var/lib/redis/dump.rdb
```

**文件示例**：

```bash
$ ls -lh /var/lib/redis/
-rw-r--r-- 1 redis redis 128M Jan 21 14:00 dump.rdb
```

### 1.3 RDB的工作流程

```
1. Redis接收到SAVE/BGSAVE命令或满足自动触发条件
    ↓
2. Fork子进程（写时复制）
    ↓
3. 子进程将内存数据写入临时RDB文件
    ↓
4. 替换旧的RDB文件
    ↓
5. 完成，父进程继续处理请求
```

## 二、触发RDB的三种方式

### 2.1 手动触发：SAVE命令

**阻塞式保存**：

```bash
127.0.0.1:6379> SAVE
OK  # 阻塞，直到保存完成

# 保存期间，Redis无法处理其他请求！
```

**特点**：
- ✅ 数据一致性好
- ❌ **阻塞主进程**（生产环境禁用！）
- ❌ 保存大数据集时，可能阻塞几十秒

**使用场景**：
- 调试环境
- 关闭服务器前手动备份

### 2.2 手动触发：BGSAVE命令（推荐）

**后台保存**：

```bash
127.0.0.1:6379> BGSAVE
Background saving started  # 立即返回，后台执行

# 不阻塞主进程，可以继续处理请求
```

**实现原理（fork机制）**：

```c
// 伪代码
def BGSAVE():
    if 已有子进程在保存:
        return "后台保存已在进行中"

    pid = fork()  // 创建子进程

    if pid == 0:  // 子进程
        将内存数据写入RDB文件
        exit(0)
    else:  // 父进程
        继续处理客户端请求
        return "后台保存已启动"
```

**fork机制（写时复制，Copy-On-Write）**：

```
父进程内存：[数据A] [数据B] [数据C]
    ↓ fork()
子进程：共享父进程的内存（不复制）
    ↓
父进程修改数据B
    ↓
写时复制：只复制修改的数据B
    ↓
父进程：[数据A] [数据B'] [数据C]
子进程：[数据A] [数据B] [数据C]  # 保持不变
```

**优点**：
- fork速度快（不复制内存）
- 节省内存（写时复制）
- 不阻塞主进程

**代价**：
- fork本身会有短暂阻塞（毫秒级）
- 如果写入频繁，会复制大量内存

**查看进度**：

```bash
127.0.0.1:6379> LASTSAVE
(integer) 1735689600  # 上次保存的时间戳

127.0.0.1:6379> INFO persistence
rdb_bgsave_in_progress:1  # 1表示正在保存
rdb_last_save_time:1735689600
rdb_last_bgsave_status:ok
```

### 2.3 自动触发（配置文件）

**redis.conf配置**：

```conf
# 格式：save <seconds> <changes>
# 含义：seconds秒内，至少changes次修改，触发BGSAVE

save 900 1     # 900秒（15分钟）内，至少1次修改
save 300 10    # 300秒（5分钟）内，至少10次修改
save 60 10000  # 60秒（1分钟）内，至少10000次修改

# 满足任意一个条件，就触发
```

**示例**：

```bash
# 1分钟内修改了10000次
127.0.0.1:6379> DEBUG POPULATE 10000 key 100
OK

# 等待1分钟，自动触发BGSAVE
127.0.0.1:6379> INFO persistence
rdb_bgsave_in_progress:1
```

**禁用自动触发**：

```conf
# 注释掉所有save配置，或者
save ""
```

**动态修改配置**：

```bash
# 查看配置
127.0.0.1:6379> CONFIG GET save
1) "save"
2) "900 1 300 10 60 10000"

# 修改配置（重启后失效）
127.0.0.1:6379> CONFIG SET save "3600 1"
OK

# 持久化配置到文件
127.0.0.1:6379> CONFIG REWRITE
OK
```

### 2.4 其他触发时机

**SHUTDOWN命令**：

```bash
127.0.0.1:6379> SHUTDOWN SAVE
# 关闭服务器前，先执行SAVE保存数据
```

**主从复制**：

```bash
# 从节点全量复制时，主节点会执行BGSAVE
127.0.0.1:6379> REPLICAOF master-host master-port
```

**FLUSHALL**：

```bash
127.0.0.1:6379> FLUSHALL
OK
# 生成一个空的RDB文件（如果配置了save）
```

## 三、RDB文件格式

### 3.1 文件结构

```
RDB文件结构：

[REDIS] [版本号] [数据库选择] [键值对] [键值对] ... [EOF] [校验和]
  ↓       ↓         ↓           ↓                      ↓      ↓
 魔数    9位      DB0/DB1      数据                  结束   CRC64
```

**魔数**：
```
"REDIS" (5字节)
用于识别文件类型
```

**版本号**：
```
0009 (4字节)
RDB文件版本，Redis 7.0使用v9
```

**数据库选择**：
```
0xFE 0x00  # 选择DB0
0xFE 0x01  # 选择DB1
```

**键值对编码**：
```
[类型] [键] [值]
- String: 直接存储
- List: 存储元素数量+元素列表
- Set: 存储元素数量+元素列表
- ZSet: 存储元素数量+(元素,分数)列表
- Hash: 存储字段数量+(字段,值)列表
```

**过期时间**：
```
[0xFC] [毫秒时间戳]  # 8字节毫秒级
或
[0xFD] [秒时间戳]    # 4字节秒级
```

### 3.2 查看RDB文件

**使用redis-check-rdb工具**：

```bash
$ redis-check-rdb /var/lib/redis/dump.rdb
[offset 0] Checking RDB file dump.rdb
[offset 26] AUX field = 'redis-ver' value = '7.0.0'
[offset 40] AUX field = 'redis-bits' value = '64'
[offset 52] AUX field = 'ctime' value = '1735689600'
[offset 67] AUX field = 'used-mem' value = '1048576'
...
[offset 12345] Checksum OK
[offset 12345] DB 0: 1000 keys, 0 expires
RDB file is OK
```

**Python解析示例**：

```python
import struct

def read_rdb(filename):
    with open(filename, 'rb') as f:
        # 读取魔数
        magic = f.read(5)
        if magic != b'REDIS':
            raise ValueError("Invalid RDB file")

        # 读取版本号
        version = f.read(4)
        print(f"RDB Version: {version.decode()}")

        # 后续解析...
```

## 四、RDB的优缺点

### 4.1 优点

**1. 性能好**

```
- RDB文件是二进制压缩格式
- 恢复速度快（直接load到内存）
- 适合大数据集

示例：
10GB数据
- RDB恢复：约2-3分钟
- AOF重放：约20-30分钟
```

**2. 适合备份**

```
- 可以定时生成不同时间点的快照
- 便于传输（文件小）
- 支持灾难恢复

备份策略：
- 每小时生成一次快照
- 保留最近24小时的快照
- 每天生成一次全量备份，保留7天
```

**3. 对性能影响小**

```
- fork子进程执行，不阻塞主进程
- 写时复制，内存占用小
```

### 4.2 缺点

**1. 数据丢失风险**

```
问题：两次快照之间的数据会丢失

场景：
14:00 - 自动BGSAVE（保存）
14:01 - 写入数据A
14:02 - 写入数据B
14:03 - 服务器宕机

结果：数据A和B丢失（没有来得及保存）
```

**2. fork阻塞**

```
问题：fork本身会短暂阻塞

影响因素：
- 数据集越大，fork越慢
- 10GB数据，fork可能需要100-200ms
- 高并发下，100ms阻塞影响明显
```

**3. 不适合实时性要求高的场景**

```
场景：
- 交易系统（不能丢失任何交易）
- 实时聊天（不能丢失消息）

推荐使用AOF或AOF+RDB混合模式
```

## 五、实战配置

### 5.1 推荐配置

**生产环境（均衡）**：

```conf
# redis.conf

# RDB文件名
dbfilename dump.rdb

# RDB文件目录
dir /var/lib/redis

# 自动保存策略（保守）
save 900 1      # 15分钟内至少1次修改
save 300 10     # 5分钟内至少10次修改
save 60 10000   # 1分钟内至少10000次修改

# BGSAVE失败时，停止写入（安全优先）
stop-writes-on-bgsave-error yes

# 压缩RDB文件（默认开启，推荐）
rdbcompression yes

# 校验和（默认开启，推荐）
rdbchecksum yes
```

**高可用场景（激进）**：

```conf
# 更频繁的保存
save 60 1       # 1分钟内至少1次修改
save 30 10      # 30秒内至少10次修改
save 10 1000    # 10秒内至少1000次修改

# 配合AOF使用（下一篇）
appendonly yes
```

**只读场景（禁用）**：

```conf
# 禁用RDB
save ""

# 或者只保留长时间的备份
save 3600 1  # 1小时内至少1次修改
```

### 5.2 备份脚本

**定时备份脚本**：

```bash
#!/bin/bash
# backup-redis.sh

REDIS_CLI="/usr/bin/redis-cli"
RDB_DIR="/var/lib/redis"
BACKUP_DIR="/backup/redis"
DATE=$(date +%Y%m%d_%H%M%S)

# 1. 触发BGSAVE
$REDIS_CLI BGSAVE

# 2. 等待BGSAVE完成
while [ $($REDIS_CLI INFO persistence | grep rdb_bgsave_in_progress | cut -d: -f2 | tr -d '\r') -eq 1 ]; do
    echo "等待BGSAVE完成..."
    sleep 1
done

# 3. 复制RDB文件到备份目录
cp $RDB_DIR/dump.rdb $BACKUP_DIR/dump_$DATE.rdb

# 4. 压缩备份
gzip $BACKUP_DIR/dump_$DATE.rdb

# 5. 删除7天前的备份
find $BACKUP_DIR -name "dump_*.rdb.gz" -mtime +7 -delete

echo "备份完成: dump_$DATE.rdb.gz"
```

**定时任务（crontab）**：

```bash
# 每小时备份一次
0 * * * * /path/to/backup-redis.sh

# 每天凌晨2点备份
0 2 * * * /path/to/backup-redis.sh
```

### 5.3 数据恢复

**恢复流程**：

```bash
# 1. 停止Redis服务
systemctl stop redis

# 2. 备份当前RDB文件（如果有）
mv /var/lib/redis/dump.rdb /var/lib/redis/dump.rdb.backup

# 3. 复制备份的RDB文件
cp /backup/redis/dump_20250121_140000.rdb.gz /var/lib/redis/
gunzip /var/lib/redis/dump_20250121_140000.rdb.gz
mv /var/lib/redis/dump_20250121_140000.rdb /var/lib/redis/dump.rdb

# 4. 修改文件权限
chown redis:redis /var/lib/redis/dump.rdb
chmod 644 /var/lib/redis/dump.rdb

# 5. 启动Redis服务
systemctl start redis

# 6. 验证数据
redis-cli PING
redis-cli DBSIZE
```

**Java代码恢复验证**：

```java
@Service
public class RedisRecoveryService {

    public boolean verifyRecovery() {
        try {
            // 1. 检查连接
            String pong = redis.getRequiredConnectionFactory()
                               .getConnection()
                               .ping();
            if (!"PONG".equals(pong)) {
                return false;
            }

            // 2. 检查数据量
            Long dbSize = redis.getRequiredConnectionFactory()
                               .getConnection()
                               .dbSize();
            log.info("数据库键数量: {}", dbSize);

            // 3. 抽查关键数据
            Object testData = redis.opsForValue().get("test:key");
            if (testData == null) {
                log.warn("测试键不存在");
                return false;
            }

            log.info("数据恢复验证成功");
            return true;

        } catch (Exception e) {
            log.error("数据恢复验证失败", e);
            return false;
        }
    }
}
```

## 六、监控和优化

### 6.1 关键指标

```bash
127.0.0.1:6379> INFO persistence
# RDB相关指标
rdb_changes_since_last_save:1234   # 上次保存后的修改次数
rdb_bgsave_in_progress:0           # 是否正在保存
rdb_last_save_time:1735689600      # 上次保存时间
rdb_last_bgsave_status:ok          # 上次保存状态
rdb_last_bgsave_time_sec:2         # 上次保存耗时（秒）
rdb_current_bgsave_time_sec:-1     # 当前保存耗时
rdb_last_cow_size:0                # 写时复制的内存大小
```

### 6.2 性能优化

**1. 减少fork阻塞**

```conf
# 使用huge pages（Linux）
echo "vm.nr_hugepages=128" >> /etc/sysctl.conf
sysctl -p

# 禁用透明大页（THP）
echo never > /sys/kernel/mm/transparent_hugepage/enabled
```

**2. 控制内存使用**

```conf
# 设置最大内存
maxmemory 2gb

# 配置淘汰策略
maxmemory-policy allkeys-lru
```

**3. 优化磁盘IO**

```bash
# 将RDB目录放在SSD上
dir /ssd/redis

# 使用RAID增加可靠性
```

## 七、总结

### 核心要点

1. **RDB是快照**：保存某个时间点的完整数据
2. **三种触发方式**：SAVE（阻塞）、BGSAVE（推荐）、自动触发
3. **fork机制**：写时复制，不阻塞主进程
4. **优点**：性能好、体积小、恢复快
5. **缺点**：可能丢失两次快照之间的数据
6. **适用场景**：全量备份、灾难恢复、大数据集

### RDB vs AOF

| 维度 | RDB | AOF |
|------|-----|-----|
| **数据完整性** | 可能丢失 | 最多丢失1秒 |
| **文件大小** | 小 | 大 |
| **恢复速度** | 快 | 慢 |
| **性能影响** | fork短暂阻塞 | 每秒同步 |
| **适用场景** | 备份、大数据 | 实时性高 |

### 下一步

掌握了RDB后，下一篇我们将学习**AOF持久化**：
- 命令日志记录
- 三种同步策略
- AOF重写机制
- RDB vs AOF vs 混合模式

---

**思考题**：
1. 为什么SAVE命令在生产环境禁用？
2. fork时的"写时复制"是如何节省内存的？
3. 如果RDB和AOF同时开启，恢复时用哪个？

下一篇见！
