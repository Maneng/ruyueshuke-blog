---
title: Redis持久化：RDB与AOF的权衡
date: 2025-11-03T10:00:00+08:00
draft: false
tags:
  - Redis
  - 持久化
  - RDB
  - AOF
  - 数据安全
  - 第一性原理
categories:
  - Java技术生态
series:
  - Redis第一性原理
weight: 40
stage: 2
stageTitle: "原理探索篇"
description: 深度剖析Redis持久化机制：RDB快照与AOF日志的原理、性能、数据安全性对比。详解COW机制、AOF重写、混合持久化。包含生产环境配置建议、性能优化和灾难恢复方案。16000字深度技术文章。
---

## 一、引子：Redis宕机后数据去哪了？

Redis是**内存数据库**，数据存储在内存中。那么问题来了：**Redis宕机后，数据还在吗？**

### 1.1 场景：双11大促数据丢失事故

```
场景：电商网站，双11大促

00:00:00 - 大促开始，流量暴增
00:00:01 - Redis缓存：10万个商品详情、50万个用户Session
00:05:00 - 服务器断电（机房故障）
00:05:01 - Redis进程被杀，内存数据全部丢失
00:10:00 - 服务器恢复，Redis重启
00:10:01 - Redis启动成功，但数据为空！

问题：
1. 所有商品详情缓存丢失 → 10万次数据库查询
2. 所有用户Session丢失 → 50万用户被强制登出
3. 缓存预热需要10分钟 → 数据库压力巨大
4. 用户体验极差 → 大量用户流失

损失：
- 用户流失：50万用户 × 10% = 5万用户
- 订单损失：5万用户 × 20% = 1万单
- GMV损失：1万单 × 200元 = 200万元
```

**核心问题**：Redis是内存数据库，断电后数据丢失，需要**持久化**。

### 1.2 持久化的本质

**持久化**：将内存中的数据保存到磁盘，重启后可以恢复。

```
为什么需要持久化？

原因1：数据安全
- Redis宕机、服务器断电、进程被杀
- 内存数据丢失
- 持久化后可以恢复

原因2：快速恢复
- 没有持久化：需要从数据库重新加载（10分钟+）
- 有持久化：直接加载持久化文件（1分钟）

原因3：数据备份
- 定期备份持久化文件
- 灾难恢复（机房火灾、磁盘损坏）
```

**Redis的两种持久化方式**：

| 持久化方式 | 原理 | 优势 | 劣势 |
|-----------|-----|------|------|
| **RDB（快照）** | 定期保存内存快照 | 恢复快、文件小 | 可能丢失数据 |
| **AOF（日志）** | 记录每个写命令 | 数据完整性高 | 恢复慢、文件大 |

---

## 二、RDB：全量快照

### 2.1 RDB的核心原理

**RDB（Redis Database）**：在某个时间点，将内存中的**全部数据**保存到磁盘。

```
工作原理：

T1: 触发RDB（手动SAVE/BGSAVE或自动触发）

T2: Redis fork一个子进程
    - 主进程继续处理客户端请求（不阻塞）
    - 子进程将内存数据写入临时RDB文件

T3: 子进程写完RDB文件，通知主进程

T4: 主进程用新RDB文件替换旧RDB文件
    - 原子操作（rename）
    - 确保RDB文件始终是完整的

T5: RDB保存完成

RDB文件：
- 文件名：dump.rdb
- 格式：二进制（压缩）
- 大小：比内存小（压缩后约50-70%）
```

### 2.2 RDB的两种触发方式

#### 方式1：SAVE命令（阻塞）

```bash
# 手动触发RDB（阻塞）
127.0.0.1:6379> SAVE
OK

# SAVE命令流程：
# 1. 主进程直接将内存数据写入RDB文件
# 2. 写入期间，Redis阻塞，无法处理任何请求
# 3. 写入完成，恢复服务

# 问题：
# - 阻塞Redis主线程
# - 10GB数据需要30秒，这30秒Redis不可用
# - 生产环境禁止使用！
```

#### 方式2：BGSAVE命令（非阻塞）

```bash
# 手动触发RDB（非阻塞）
127.0.0.1:6379> BGSAVE
Background saving started

# BGSAVE命令流程：
# 1. Redis fork一个子进程
# 2. 子进程将内存数据写入RDB文件
# 3. 主进程继续处理客户端请求（不阻塞）
# 4. 子进程写完后，通知主进程

# 优势：
# - 不阻塞主进程
# - 用户无感知
# - 生产环境推荐使用
```

#### 方式3：自动触发（配置）

```bash
# redis.conf配置

# 触发条件：时间 + 修改次数
save 900 1      # 900秒内至少1次修改，触发BGSAVE
save 300 10     # 300秒内至少10次修改，触发BGSAVE
save 60 10000   # 60秒内至少10000次修改，触发BGSAVE

# 解释：
# 满足任意一个条件，就会自动执行BGSAVE

# 示例：
# - 大促期间，60秒内10000次修改，自动保存
# - 深夜低峰，900秒内1次修改，也会保存
# - 确保数据不会丢失太多

# 其他配置
stop-writes-on-bgsave-error yes  # BGSAVE失败时，停止写入
rdbcompression yes               # 启用RDB压缩（LZF算法）
rdbchecksum yes                  # 启用RDB校验和（检测文件损坏）
dbfilename dump.rdb              # RDB文件名
dir /var/redis/6379              # RDB文件目录
```

### 2.3 COW（Copy-On-Write）机制

**问题**：BGSAVE期间，如果主进程修改了数据怎么办？

```
场景：BGSAVE期间的数据修改

T1: 执行BGSAVE，fork子进程
    此时内存：
    key1 = "old_value1"
    key2 = "old_value2"

T2: 子进程开始遍历内存，写入RDB
    写入：key1 = "old_value1"

T3: 主进程修改key2
    SET key2 "new_value2"

问题：
- 子进程还在遍历，还没写key2
- 主进程已经修改了key2
- 子进程应该写入哪个值？

答案：使用COW机制
```

**COW（Copy-On-Write）机制**：

```
工作原理：

1. fork子进程时，不会复制整个内存
   - 父子进程共享同一块物理内存
   - 使用页表（Page Table）映射
   - 所有内存页标记为只读

2. 主进程修改数据时，触发COW
   - 操作系统检测到写操作
   - 复制该内存页（4KB）
   - 主进程修改复制后的新页
   - 子进程继续使用旧页

3. 子进程写RDB时
   - 读取的是fork时刻的快照
   - 不受主进程后续修改影响

示例：
T1: fork子进程
    物理内存：[page1][page2][page3]
    父子进程都指向相同的物理页

T2: 主进程修改page2的数据
    - 触发COW
    - 复制page2 → page2'
    - 主进程指向page2'
    - 子进程仍指向page2

T3: 子进程写RDB
    - 写入page2（旧数据）
    - 保持一致性快照

优势：
- 避免复制整个内存（节省内存和时间）
- 只复制被修改的内存页
- 10GB数据，如果修改10%，只复制1GB
```

**COW的内存开销**：

```
假设：
- Redis数据：10GB
- BGSAVE期间，写入速度：1000次/秒
- BGSAVE耗时：30秒
- 平均每次写入：1KB

内存开销计算：
- 总写入次数：1000次/秒 × 30秒 = 3万次
- 修改的内存页：3万次 × 4KB/页 = 120MB
- 额外内存开销：120MB（仅1.2%）

结论：
- COW机制内存开销很小
- 不会翻倍（不是10GB → 20GB）
- 实际额外开销：1-5%
```

### 2.4 RDB的优劣势

**优势**：

```
1. 恢复速度快
   - RDB是二进制格式，加载快
   - 10GB数据，加载耗时约1分钟
   - AOF需要重放命令，耗时10分钟+

2. 文件体积小
   - RDB经过压缩
   - 10GB内存 → 5GB RDB文件
   - 节省磁盘空间和备份成本

3. 性能开销小
   - BGSAVE由子进程执行
   - 主进程几乎无影响
   - 只有fork时有短暂停顿（毫秒级）

4. 适合备份
   - 定期生成RDB文件
   - 按时间命名（dump-2024-11-03-12:00.rdb）
   - 灾难恢复
```

**劣势**：

```
1. 数据丢失风险
   - RDB是定期保存（如每5分钟）
   - Redis宕机时，丢失最近5分钟的数据
   - 无法做到秒级持久化

2. fork耗时
   - fork会复制页表
   - 10GB数据，fork耗时约200ms
   - 这200ms Redis会有短暂停顿

3. CPU和磁盘IO开销
   - 子进程需要遍历内存、压缩、写磁盘
   - CPU占用：10-20%
   - 磁盘IO：写入5-10GB

4. 不适合实时性要求高的场景
   - 如金融交易、支付
   - 不能接受丢失几分钟数据
```

### 2.5 RDB最佳实践

**生产环境配置**：

```bash
# redis.conf

# 1. 自动触发策略（根据业务调整）
save 900 1      # 15分钟内有1次修改
save 300 10     # 5分钟内有10次修改
save 60 10000   # 1分钟内有10000次修改

# 2. 关闭RDB（如果使用AOF）
# save ""  # 注释掉所有save配置

# 3. BGSAVE失败时的处理
stop-writes-on-bgsave-error yes  # 推荐yes（确保数据安全）

# 4. 压缩
rdbcompression yes  # 推荐yes（节省磁盘空间）

# 5. 校验和
rdbchecksum yes  # 推荐yes（检测文件损坏）

# 6. 文件路径
dir /data/redis  # 推荐使用独立磁盘（避免与日志竞争IO）
dbfilename dump.rdb
```

**RDB备份脚本**：

```bash
#!/bin/bash
# rdb-backup.sh

# 配置
REDIS_HOST="127.0.0.1"
REDIS_PORT="6379"
REDIS_PASSWORD="mypassword"
BACKUP_DIR="/data/redis-backup"
DATE=$(date +%Y%m%d-%H%M%S)

# 1. 触发BGSAVE
redis-cli -h $REDIS_HOST -p $REDIS_PORT -a $REDIS_PASSWORD BGSAVE

# 2. 等待BGSAVE完成
while true; do
    LASTSAVE=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT -a $REDIS_PASSWORD LASTSAVE)
    sleep 1
    NEWSAVE=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT -a $REDIS_PASSWORD LASTSAVE)
    if [ "$LASTSAVE" == "$NEWSAVE" ]; then
        break
    fi
done

# 3. 复制RDB文件到备份目录
cp /var/redis/6379/dump.rdb $BACKUP_DIR/dump-$DATE.rdb

# 4. 压缩备份文件
gzip $BACKUP_DIR/dump-$DATE.rdb

# 5. 删除7天前的备份
find $BACKUP_DIR -name "dump-*.rdb.gz" -mtime +7 -delete

echo "RDB备份完成：$BACKUP_DIR/dump-$DATE.rdb.gz"
```

**定时备份（crontab）**：

```bash
# 每天凌晨2点备份
0 2 * * * /data/scripts/rdb-backup.sh >> /var/log/redis-backup.log 2>&1
```

---

## 三、AOF：增量日志

### 3.1 AOF的核心原理

**AOF（Append Only File）**：记录**每个写命令**，重启时重新执行这些命令恢复数据。

```
工作原理：

T1: 客户端执行写命令
    SET key1 "value1"

T2: Redis执行命令，修改内存

T3: Redis将命令追加到AOF缓冲区
    AOF buffer: "SET key1 \"value1\"\r\n"

T4: 根据策略，将AOF缓冲区写入磁盘
    - always：每个命令立即写磁盘
    - everysec：每秒写一次磁盘
    - no：由操作系统决定

T5: AOF文件持续增长

AOF文件格式（RESP协议）：
*3\r\n              # 3个参数
$3\r\n              # 第1个参数长度3
SET\r\n             # SET
$4\r\n              # 第2个参数长度4
key1\r\n            # key1
$6\r\n              # 第3个参数长度6
value1\r\n          # value1
```

### 3.2 AOF的三种同步策略

**策略1：always（每次写入都同步）**

```bash
# redis.conf
appendonly yes
appendfsync always

# 工作流程：
# 1. 客户端发送写命令：SET key1 "value1"
# 2. Redis执行命令，修改内存
# 3. 将命令追加到AOF缓冲区
# 4. 立即调用fsync()，将缓冲区写入磁盘
# 5. 返回客户端成功

# 优势：
# - 数据最安全（每个命令都持久化）
# - 最多丢失1个命令的数据

# 劣势：
# - 性能最差（每次写入都要磁盘IO）
# - 写入速度：约1000次/秒（受限于磁盘IO）
# - 不适合高并发场景

# 适用场景：
# - 金融、支付等对数据安全性要求极高的场景
```

**策略2：everysec（每秒同步一次）**

```bash
# redis.conf
appendonly yes
appendfsync everysec  # 推荐配置

# 工作流程：
# 1. 客户端发送写命令：SET key1 "value1"
# 2. Redis执行命令，修改内存
# 3. 将命令追加到AOF缓冲区
# 4. 返回客户端成功（不等待磁盘写入）
# 5. 后台线程每秒调用fsync()，将缓冲区写入磁盘

# 优势：
# - 性能好（不阻塞主线程）
# - 数据安全性高（最多丢失1秒数据）
# - 写入速度：约10万次/秒

# 劣势：
# - 可能丢失1秒数据（Redis宕机时）

# 适用场景：
# - 大部分业务场景（推荐）
# - 平衡性能和数据安全性
```

**策略3：no（由操作系统决定）**

```bash
# redis.conf
appendonly yes
appendfsync no

# 工作流程：
# 1. 客户端发送写命令：SET key1 "value1"
# 2. Redis执行命令，修改内存
# 3. 将命令追加到AOF缓冲区
# 4. 返回客户端成功
# 5. 由操作系统决定何时将缓冲区写入磁盘（通常30秒）

# 优势：
# - 性能最好（完全不阻塞）
# - 写入速度：约20万次/秒

# 劣势：
# - 数据不安全（可能丢失30秒数据）

# 适用场景：
# - 对数据安全性要求不高的场景（如缓存）
# - 不推荐
```

**三种策略对比**：

| 策略 | 性能 | 数据安全性 | 可能丢失数据 | 适用场景 |
|------|-----|-----------|------------|---------|
| **always** | 低（1000 QPS） | 极高 | 1个命令 | 金融、支付 |
| **everysec** | 高（10万 QPS） | 高 | 1秒 | **大部分场景（推荐）** |
| **no** | 极高（20万 QPS） | 低 | 30秒 | 纯缓存场景 |

### 3.3 AOF重写机制

**问题**：AOF文件持续增长，最终会占满磁盘。

```
场景：AOF文件膨胀

T1: SET key1 "v1"      # AOF文件：第1行
T2: SET key1 "v2"      # AOF文件：第2行
T3: SET key1 "v3"      # AOF文件：第3行
...
T100: SET key1 "v100"  # AOF文件：第100行

问题：
- AOF文件记录了100次SET命令
- 但实际只需要最后一次：SET key1 "v100"
- 前99次都是冗余的

结果：
- AOF文件越来越大
- 恢复时间越来越长
- 占用磁盘空间

解决方案：AOF重写
```

**AOF重写原理**：

```
重写流程：

T1: 触发AOF重写（手动BGREWRITEAOF或自动触发）

T2: Redis fork一个子进程
    - 主进程继续处理客户端请求
    - 子进程遍历内存，生成新AOF文件

T3: 子进程遍历内存数据
    - key1 = "v100"  → 写入：SET key1 "v100"
    - key2 = "abc"   → 写入：SET key2 "abc"
    - list1 = [1,2,3] → 写入：RPUSH list1 1 2 3

T4: 主进程继续接收写命令
    - 写入旧AOF文件（保持数据安全）
    - 写入AOF重写缓冲区（用于后续同步）

T5: 子进程写完新AOF文件，通知主进程

T6: 主进程将AOF重写缓冲区的命令追加到新AOF文件

T7: 主进程用新AOF文件替换旧AOF文件
    - 原子操作（rename）

T8: AOF重写完成

效果：
- 旧AOF：1GB（100万条命令）
- 新AOF：100MB（10万条命令，去掉冗余）
- 文件缩小10倍！
```

**手动触发AOF重写**：

```bash
# 手动触发AOF重写
127.0.0.1:6379> BGREWRITEAOF
Background append only file rewriting started
```

**自动触发AOF重写**：

```bash
# redis.conf

# 自动触发条件
auto-aof-rewrite-percentage 100  # AOF文件大小增长100%时触发
auto-aof-rewrite-min-size 64mb   # AOF文件至少64MB才触发

# 解释：
# 假设上次重写后AOF文件为100MB
# 当AOF文件增长到200MB时（增长100%），触发重写
# 但如果AOF文件只有10MB，即使增长100%到20MB，也不会触发（因为没到64MB）

# 推荐配置：
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
```

### 3.4 AOF的优劣势

**优势**：

```
1. 数据完整性高
   - everysec策略：最多丢失1秒数据
   - always策略：最多丢失1个命令
   - 比RDB安全（RDB可能丢失几分钟数据）

2. AOF可读性强
   - 文本格式（RESP协议）
   - 可以直接查看、修改
   - 误删数据可以手动恢复

3. 支持增量备份
   - AOF是追加写入
   - 可以实时备份
   - 不需要停机

4. 适合实时性要求高的场景
   - 金融、支付、订单
```

**劣势**：

```
1. 文件体积大
   - AOF文件比RDB大（5-10倍）
   - 10GB内存 → 50GB AOF文件（重写前）
   - 10GB内存 → 10GB AOF文件（重写后）

2. 恢复速度慢
   - 需要重新执行所有命令
   - 10GB数据，恢复耗时10分钟+
   - RDB只需1分钟

3. 性能开销大
   - always策略：写入速度1000 QPS
   - everysec策略：写入速度10万 QPS
   - 比纯内存慢

4. AOF重写开销
   - fork子进程
   - 遍历内存、写磁盘
   - CPU和磁盘IO开销
```

### 3.5 AOF最佳实践

**生产环境配置**：

```bash
# redis.conf

# 1. 启用AOF
appendonly yes

# 2. 同步策略（推荐everysec）
appendfsync everysec

# 3. AOF文件名
appendfilename "appendonly.aof"

# 4. AOF重写配置
auto-aof-rewrite-percentage 100  # 增长100%时重写
auto-aof-rewrite-min-size 64mb   # 至少64MB才重写

# 5. AOF重写时，是否继续fsync
no-appendfsync-on-rewrite no  # 推荐no（确保数据安全）

# 6. AOF加载时，忽略错误
aof-load-truncated yes  # 推荐yes（AOF文件损坏时，加载截断前的数据）

# 7. 混合持久化（Redis 4.0+）
aof-use-rdb-preamble yes  # 推荐yes（RDB+AOF混合）
```

---

## 四、混合持久化：RDB + AOF

### 4.1 混合持久化的原理

**Redis 4.0+新特性**：RDB + AOF混合持久化。

```
问题：
- RDB：恢复快，但可能丢失数据
- AOF：数据安全，但恢复慢

解决方案：混合持久化
- AOF重写时，将内存数据以RDB格式写入AOF文件头部
- 后续的增量命令以AOF格式追加到文件尾部

AOF文件结构（混合模式）：
┌─────────────────────────────────────┐
│  RDB格式（全量数据）                  │  ← 快速恢复
├─────────────────────────────────────┤
│  AOF格式（增量命令）                  │  ← 数据完整性
└─────────────────────────────────────┘

优势：
- 恢复速度快（RDB部分快速加载）
- 数据完整性高（AOF部分补全增量数据）
- 兼具RDB和AOF的优点
```

**混合持久化流程**：

```
T1: 执行AOF重写

T2: 子进程遍历内存，以RDB格式写入新AOF文件头部
    - RDB格式：二进制、压缩
    - 包含重写时刻的全量数据

T3: 主进程继续接收写命令
    - 写入AOF重写缓冲区

T4: 子进程写完RDB部分，通知主进程

T5: 主进程将AOF重写缓冲区的命令追加到新AOF文件尾部
    - AOF格式：文本、RESP协议

T6: 用新AOF文件替换旧AOF文件

T7: 后续的写命令继续追加到AOF文件尾部
    - AOF格式

恢复流程：
T1: Redis启动，读取AOF文件

T2: 检测AOF文件格式
    - 如果是混合格式，先加载RDB部分（快）
    - 然后执行AOF部分的命令（补全增量）

T3: 数据恢复完成

恢复时间：
- 纯AOF：10GB数据，10分钟
- 混合持久化：10GB数据，1分钟（RDB部分）+ 1分钟（AOF部分）= 2分钟
- 性能提升：5倍
```

### 4.2 混合持久化配置

```bash
# redis.conf

# 启用混合持久化（Redis 4.0+）
aof-use-rdb-preamble yes

# 同时启用RDB和AOF
save 900 1
save 300 10
save 60 10000

appendonly yes
appendfsync everysec
```

### 4.3 混合持久化的优劣势

**优势**：

```
1. 恢复速度快
   - RDB部分快速加载（1分钟）
   - AOF部分补全增量（1分钟）
   - 总计2分钟（比纯AOF快5倍）

2. 数据完整性高
   - everysec策略：最多丢失1秒数据
   - 比纯RDB安全

3. 文件体积适中
   - RDB部分压缩（5GB）
   - AOF部分增量（1GB）
   - 总计6GB（比纯AOF小）

4. 兼具RDB和AOF优点
```

**劣势**：

```
1. 兼容性问题
   - Redis 4.0+才支持
   - 旧版本无法读取混合格式AOF文件

2. 复杂度增加
   - 需要理解RDB和AOF两种格式
   - 故障排查更复杂

3. AOF重写开销
   - 仍然需要fork子进程
   - CPU和磁盘IO开销
```

---

## 五、持久化方案对比与选择

### 5.1 三种方案对比

| 维度 | RDB | AOF | 混合持久化 |
|------|-----|-----|-----------|
| **数据安全性** | 低（丢失几分钟） | 高（丢失1秒） | 高（丢失1秒） |
| **恢复速度** | 快（1分钟） | 慢（10分钟） | 中（2分钟） |
| **文件体积** | 小（5GB） | 大（50GB未重写） | 中（10GB） |
| **性能开销** | 低 | 中（everysec） | 中 |
| **CPU开销** | fork时有峰值 | 持续低负载 | fork时有峰值 |
| **磁盘IO** | BGSAVE时高 | 持续中等 | AOF重写时高 |
| **适用场景** | 允许丢失数据 | 不允许丢失数据 | 推荐 |

### 5.2 选择决策树

```
业务场景 → 持久化方案

是否允许丢失几分钟数据？
├─ 是（纯缓存场景）
│   └─ 使用RDB
│       - save 900 1
│       - 性能最好
│
└─ 否（重要业务数据）
    └─ 是否对恢复速度敏感？
        ├─ 是（快速恢复）
        │   └─ 使用混合持久化（推荐）
        │       - aof-use-rdb-preamble yes
        │       - appendfsync everysec
        │
        └─ 否（数据安全第一）
            └─ 使用AOF
                - appendfsync always（金融场景）
                - appendfsync everysec（一般场景）
```

### 5.3 生产环境推荐配置

**场景1：纯缓存（允许丢失数据）**

```bash
# redis.conf

# 只使用RDB
save 900 1
save 300 10
save 60 10000

# 关闭AOF
appendonly no

# 适用场景：
# - 商品详情缓存
# - 用户信息缓存
# - 丢失后可以从数据库重新加载
```

**场景2：重要业务数据（推荐）**

```bash
# redis.conf

# 使用混合持久化
save 900 1
save 300 10
save 60 10000

appendonly yes
appendfsync everysec
aof-use-rdb-preamble yes  # Redis 4.0+

# 适用场景：
# - 订单数据
# - 用户Session
# - 大部分业务场景（推荐）
```

**场景3：金融/支付（数据安全第一）**

```bash
# redis.conf

# 使用AOF（always策略）
save ""  # 关闭RDB

appendonly yes
appendfsync always  # 每个命令都持久化

# 适用场景：
# - 金融交易
# - 支付流水
# - 不能容忍任何数据丢失
```

---

## 六、灾难恢复方案

### 6.1 数据恢复流程

**Redis启动时的恢复优先级**：

```
优先级：AOF > RDB

Redis启动流程：
1. 检查是否存在AOF文件
   - 存在 → 加载AOF文件
   - 不存在 → 检查RDB文件

2. 加载AOF文件
   - 读取AOF文件
   - 逐条执行命令
   - 恢复数据

3. 如果AOF不存在，加载RDB文件
   - 读取RDB文件
   - 加载二进制数据
   - 恢复数据

4. 启动完成
```

**手动恢复数据**：

```bash
# 1. 停止Redis
redis-cli SHUTDOWN

# 2. 备份当前数据文件（防止误操作）
cp /var/redis/6379/dump.rdb /var/redis/backup/
cp /var/redis/6379/appendonly.aof /var/redis/backup/

# 3. 复制备份文件到Redis数据目录
cp /data/redis-backup/dump-20241103.rdb /var/redis/6379/dump.rdb
cp /data/redis-backup/appendonly-20241103.aof /var/redis/6379/appendonly.aof

# 4. 启动Redis
redis-server /etc/redis/redis.conf

# 5. 验证数据
redis-cli
127.0.0.1:6379> DBSIZE
(integer) 1000000  # 数据已恢复
```

### 6.2 AOF文件损坏修复

**问题**：Redis宕机时，AOF文件可能损坏。

```bash
# 1. 检查AOF文件
redis-check-aof appendonly.aof

# 输出示例：
# AOF analyzed: size=1024MB, ok_up_to=1020MB, diff=4MB
# Bad file format: Expected *3, got garbage

# 2. 修复AOF文件（删除损坏部分）
redis-check-aof --fix appendonly.aof

# 确认修复？
# This will shrink the AOF from 1024MB to 1020MB
# Continue? [y/N] y

# 3. 重新启动Redis
redis-server /etc/redis/redis.conf
```

### 6.3 定期备份策略

**备份策略**：

```
1. 每日备份
   - 每天凌晨2点
   - 备份RDB和AOF文件
   - 保留7天

2. 每周备份
   - 每周日凌晨3点
   - 备份到远程存储（OSS/S3）
   - 保留4周

3. 每月备份
   - 每月1号凌晨4点
   - 备份到远程存储
   - 永久保留（用于审计）

4. 实时备份（可选）
   - 使用主从复制
   - Slave作为热备
   - 实时同步数据
```

**备份脚本**：

```bash
#!/bin/bash
# redis-full-backup.sh

DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/data/redis-backup"
REMOTE_BACKUP_DIR="s3://my-bucket/redis-backup"

# 1. 触发BGSAVE
redis-cli BGSAVE

# 2. 等待BGSAVE完成
while [ $(redis-cli INFO persistence | grep rdb_bgsave_in_progress | cut -d: -f2) -eq 1 ]; do
    sleep 1
done

# 3. 备份RDB文件
cp /var/redis/6379/dump.rdb $BACKUP_DIR/dump-$DATE.rdb

# 4. 备份AOF文件
cp /var/redis/6379/appendonly.aof $BACKUP_DIR/appendonly-$DATE.aof

# 5. 压缩备份文件
tar -czf $BACKUP_DIR/redis-backup-$DATE.tar.gz \
    $BACKUP_DIR/dump-$DATE.rdb \
    $BACKUP_DIR/appendonly-$DATE.aof

# 6. 上传到远程存储（S3）
aws s3 cp $BACKUP_DIR/redis-backup-$DATE.tar.gz $REMOTE_BACKUP_DIR/

# 7. 删除本地临时文件
rm $BACKUP_DIR/dump-$DATE.rdb
rm $BACKUP_DIR/appendonly-$DATE.aof

# 8. 删除7天前的本地备份
find $BACKUP_DIR -name "redis-backup-*.tar.gz" -mtime +7 -delete

echo "Redis备份完成：$BACKUP_DIR/redis-backup-$DATE.tar.gz"
```

---

## 七、总结

### 7.1 核心要点回顾

**Redis持久化的本质**：

```
问题：Redis是内存数据库，断电后数据丢失
解决：持久化（保存到磁盘）

两种持久化方式：
1. RDB（快照）：
   - 定期保存内存快照
   - 恢复快、文件小
   - 可能丢失数据

2. AOF（日志）：
   - 记录每个写命令
   - 数据安全、恢复慢
   - 文件大

3. 混合持久化（推荐）：
   - RDB + AOF
   - 兼具两者优点
```

**选择建议**：

```
场景 → 方案

纯缓存：
- 使用RDB
- save 900 1

重要数据：
- 使用混合持久化（推荐）
- aof-use-rdb-preamble yes
- appendfsync everysec

金融/支付：
- 使用AOF
- appendfsync always
```

### 7.2 下一步学习

本文是Redis系列的第5篇，最后一篇将综合实战：

1. ✅ Redis第一性原理：为什么我们需要缓存？
2. ✅ 从HashMap到Redis：分布式缓存的演进
3. ✅ Redis五大数据结构：从场景到实现
4. ✅ Redis高可用架构：主从复制、哨兵、集群
5. ✅ **Redis持久化：RDB与AOF的权衡**
6. ⏳ Redis实战：分布式锁、消息队列、缓存设计

---

**参考资料**：
- 《Redis设计与实现》- 黄健宏
- 《Redis实战》- Josiah L. Carlson
- Redis官方文档：https://redis.io/documentation
- Redis持久化文档：https://redis.io/topics/persistence

---

*本文是"Redis第一性原理"系列的第5篇，共6篇。下一篇也是最后一篇，将综合讲解《Redis实战：分布式锁、消息队列、缓存设计》，敬请期待。*
