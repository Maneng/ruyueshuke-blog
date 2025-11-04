---
title: MySQL高可用架构：主从复制与分库分表
date: 2025-11-03T10:00:00+08:00
draft: false
tags:
  - MySQL
  - 高可用
  - 主从复制
  - 分库分表
  - 读写分离
categories:
  - 技术
series:
  - MySQL第一性原理
weight: 5
description: 深度剖析MySQL的主从复制原理、binlog三种格式、读写分离架构、分库分表策略。从单机到分布式，从百万到亿级数据的演进之路。
---

## 引言

单机MySQL的三大瓶颈：

```
1. 存储瓶颈：单机磁盘容量有限（TB级）
2. 并发瓶颈：单机QPS上限1-2万
3. 可用性瓶颈：单点故障，服务不可用
```

**高可用架构的演进路径：**

```
单机 → 主从复制 → 读写分离 → 分库分表 → 分布式数据库
 ↓       ↓          ↓          ↓           ↓
1台    1主N从     读扩展     存储扩展    NewSQL
```

---

## 一、主从复制：高可用的基石

### 1.1 主从复制原理

**核心组件：**

```
主库（Master）
  ↓ binlog（二进制日志）
从库（Slave）
  ↓ relay log（中继日志）
  ↓ 重放SQL
数据一致
```

**复制流程：**

```sql
-- 主库操作
INSERT INTO users (name, age) VALUES ('Zhang San', 25);

-- 主库写binlog
-- binlog内容：
-- Event_type: Query
-- Query: INSERT INTO users (name, age) VALUES ('Zhang San', 25)

-- 从库IO线程：
-- 1. 连接主库，请求binlog
-- 2. 主库binlog dump线程发送binlog
-- 3. 从库IO线程写入relay log

-- 从库SQL线程：
-- 1. 读取relay log
-- 2. 解析SQL语句
-- 3. 执行SQL：INSERT INTO users...
-- 4. 完成数据同步
```

**三个关键线程：**

| 线程 | 位置 | 职责 |
|------|------|------|
| **binlog dump线程** | 主库 | 发送binlog给从库 |
| **IO线程** | 从库 | 接收binlog，写relay log |
| **SQL线程** | 从库 | 读取relay log，执行SQL |

---

### 1.2 binlog三种格式

**1. Statement格式（语句复制）**

```sql
-- 主库执行
UPDATE users SET age = age + 1 WHERE id > 100;

-- binlog记录
-- Event: UPDATE users SET age = age + 1 WHERE id > 100;

-- 从库执行
-- 执行相同的SQL语句

优势：
  ✅ binlog体积小
  ✅ 日志清晰易读

劣势：
  ❌ 不确定性函数导致主从不一致
  -- 如：NOW()、UUID()、RAND()
  ❌ 主从执行顺序可能不同
```

**2. Row格式（行复制，推荐）**

```sql
-- 主库执行
UPDATE users SET age = 26 WHERE id = 1;

-- binlog记录（实际是二进制格式）
-- Event: UPDATE_ROWS_EVENT
-- Table: users
-- Before: id=1, name='Zhang San', age=25
-- After:  id=1, name='Zhang San', age=26

-- 从库执行
-- 直接应用行变更

优势：
  ✅ 数据一致性强
  ✅ 支持所有SQL语句
  ✅ 可恢复任意时间点数据

劣势：
  ❌ binlog体积大
  ❌ 批量更新日志量大
```

**3. Mixed格式（混合）**

```
策略：
  默认使用Statement格式
  遇到不确定性函数时，自动切换到Row格式

优势：
  ✅ 平衡了体积和一致性
```

**格式对比：**

| 格式 | 日志大小 | 一致性 | 推荐场景 |
|------|---------|--------|---------|
| **Statement** | 小 | 可能不一致 | 简单SQL |
| **Row** | 大 | 强一致 | 生产环境（推荐） |
| **Mixed** | 中等 | 强一致 | 折中方案 |

---

### 1.3 复制模式

**1. 异步复制（默认）**

```
主库：
  1. 执行SQL
  2. 写binlog
  3. 返回客户端（不等从库）

从库：
  异步拉取binlog并执行

特点：
  ✅ 性能最好
  ❌ 主库宕机可能丢数据
  ❌ 主从延迟

适用：
  对一致性要求不高的场景
```

**2. 半同步复制**

```
主库：
  1. 执行SQL
  2. 写binlog
  3. 等待至少1个从库接收binlog
  4. 返回客户端

从库：
  接收binlog后立即响应主库（不等执行）

特点：
  ✅ 不丢数据
  ⚠️ 性能略降（等待从库响应）
  ❌ 仍有主从延迟

适用：
  对数据安全性要求高的场景
```

**3. 组复制（MySQL Group Replication）**

```
特点：
  ✅ 多主模式，任意节点可写
  ✅ 强一致性（基于Paxos协议）
  ✅ 自动故障切换
  ❌ 配置复杂

适用：
  高可用、强一致性场景
```

---

### 1.4 主从延迟优化

**延迟的原因：**

```
1. 从库SQL线程单线程执行
   主库：10个并发写入
   从库：1个线程回放
   → 延迟累积

2. 大事务
   主库：执行10秒的大事务
   从库：也需要10秒回放
   → 阻塞后续binlog

3. 网络延迟
   主从之间网络带宽不足

4. 从库负载高
   大量读查询占用CPU
```

**优化方案：**

```sql
-- 1. 并行复制（MySQL 5.7+）
SET GLOBAL slave_parallel_type = 'LOGICAL_CLOCK';
SET GLOBAL slave_parallel_workers = 8;

-- 从库使用8个worker线程并行回放

-- 2. 避免大事务
-- 将大事务拆分为小事务
BEGIN;
UPDATE users SET status = 1 WHERE id BETWEEN 1 AND 1000;
COMMIT;

BEGIN;
UPDATE users SET status = 1 WHERE id BETWEEN 1001 AND 2000;
COMMIT;

-- 3. 提升从库硬件
-- 使用SSD、增加内存、提升CPU

-- 4. 读写分离时处理延迟
-- 方案1：强制从主库读（写后读）
-- 方案2：延迟检测，延迟过大时从主库读
SHOW SLAVE STATUS\G
-- Seconds_Behind_Master: 延迟秒数
```

---

## 二、读写分离：并发扩展

### 2.1 架构设计

```
                应用层
                  ↓
            中间件/代理层
          （ShardingSphere/ProxySQL）
          ↙              ↘
    写请求                读请求
      ↓                    ↓
   主库（Master）      从库（Slave1, Slave2, Slave3）
      ↓                    ↑
   binlog复制 ──────────────┘
```

**核心组件：**

| 组件 | 职责 | 方案 |
|------|------|------|
| **应用层** | 业务逻辑 | 标记读写SQL |
| **代理层** | SQL路由 | ShardingSphere、ProxySQL、MySQL Router |
| **主库** | 处理写请求 | 1台 |
| **从库** | 处理读请求 | N台（负载均衡） |

---

### 2.2 实现方案

**方案1：应用层实现**

```java
@Service
public class UserService {

    @Autowired
    private DataSource masterDataSource;  // 主库

    @Autowired
    private DataSource slaveDataSource;   // 从库

    // 写操作：主库
    public void createUser(User user) {
        JdbcTemplate template = new JdbcTemplate(masterDataSource);
        template.update("INSERT INTO users VALUES (?, ?)",
            user.getName(), user.getAge());
    }

    // 读操作：从库
    public User getUser(Long id) {
        JdbcTemplate template = new JdbcTemplate(slaveDataSource);
        return template.queryForObject("SELECT * FROM users WHERE id = ?",
            new Object[]{id}, new UserRowMapper());
    }
}
```

**方案2：中间件实现（推荐）**

```yaml
# ShardingSphere配置
dataSources:
  master:
    url: jdbc:mysql://master:3306/db

  slave1:
    url: jdbc:mysql://slave1:3306/db

  slave2:
    url: jdbc:mysql://slave2:3306/db

rules:
  readwriteSplitting:
    dataSources:
      readwrite_ds:
        writeDataSourceName: master
        readDataSourceNames:
          - slave1
          - slave2
        loadBalancerName: round_robin
```

---

### 2.3 读写分离的挑战

**1. 主从延迟导致读不到刚写的数据**

```java
// 问题场景
userService.createUser(user);        // 写主库
User newUser = userService.getUser(userId);  // 读从库（可能还未同步）
// newUser可能为null

// 解决方案1：写后读强制走主库
@Transactional
public void createAndGet(User user) {
    userService.createUser(user);
    User newUser = userService.getUserFromMaster(userId);  // 强制主库
}

// 解决方案2：缓存
userService.createUser(user);
cache.put(userId, user);  // 写缓存
User newUser = cache.get(userId);  // 从缓存读
```

**2. 事务中的读必须走主库**

```java
@Transactional
public void transfer(Long fromId, Long toId, BigDecimal amount) {
    // 事务中的所有操作都必须在主库执行
    Account from = accountService.getAccount(fromId);  // 必须主库
    Account to = accountService.getAccount(toId);      // 必须主库

    from.setBalance(from.getBalance().subtract(amount));
    to.setBalance(to.getBalance().add(amount));

    accountService.update(from);
    accountService.update(to);
}
```

---

## 三、分库分表：存储扩展

### 3.1 为什么需要分库分表？

**单表数据量过大的问题：**

```
单表1亿行：
  ✅ 索引体积：约5GB（B+树高度4层）
  ✅ 查询性能：可接受（有索引）
  ❌ 写入性能：下降（索引维护成本高）
  ❌ DDL操作：ALTER TABLE需要数小时
  ❌ 备份恢复：耗时长

建议：
  单表行数 < 2000万
  单表大小 < 10GB
```

---

### 3.2 分库分表策略

**1. 垂直拆分：按业务模块**

```
原始数据库：
  ├─ users表
  ├─ orders表
  ├─ products表
  └─ payments表

垂直拆分后：
  用户库：
    └─ users表

  订单库：
    ├─ orders表
    └─ payments表

  商品库：
    └─ products表

优势：
  ✅ 业务解耦
  ✅ 扩展灵活

劣势：
  ❌ 跨库JOIN困难
  ❌ 分布式事务
```

**2. 水平拆分：按数据行**

```
原始：
  orders表（1亿行）

水平拆分（按user_id哈希，分16库64表）：
  db_00:
    ├─ orders_00
    ├─ orders_01
    ├─ orders_02
    └─ orders_03

  db_01:
    ├─ orders_04
    ├─ orders_05
    ├─ orders_06
    └─ orders_07

  ...

  db_15:
    ├─ orders_60
    ├─ orders_61
    ├─ orders_62
    └─ orders_63

路由规则：
  db_index = user_id % 16
  table_index = user_id / 16 % 4

示例：
  user_id = 123
  db_index = 123 % 16 = 11  → db_11
  table_index = 123 / 16 % 4 = 3  → orders_51

优势：
  ✅ 单表数据量降低（1亿 → 150万）
  ✅ 并发扩展（16倍）

劣势：
  ❌ 路由复杂
  ❌ 跨分片查询困难
```

---

### 3.3 分片键选择

**原则：**

```
1. 高频查询条件
   ✅ user_id（80%查询都带user_id）
   ❌ order_date（很少作为查询条件）

2. 数据分布均匀
   ✅ user_id哈希（均匀分布）
   ❌ 地区（北上广深数据多，其他少）

3. 避免热点
   ✅ user_id（用户分散）
   ❌ 商家id（大商家订单多）
```

**常见分片策略：**

| 策略 | 算法 | 优势 | 劣势 |
|------|------|------|------|
| **哈希** | `id % N` | 分布均匀 | 扩容困难 |
| **范围** | `0-100万→db0, 100-200万→db1` | 扩容简单 | 可能热点 |
| **一致性哈希** | 虚拟节点环 | 扩容平滑 | 实现复杂 |

---

### 3.4 分库分表中间件

**ShardingSphere（推荐）**

```yaml
rules:
  sharding:
    tables:
      orders:
        actualDataNodes: ds_${0..15}.orders_${0..63}

        databaseStrategy:
          standard:
            shardingColumn: user_id
            shardingAlgorithmName: db_mod

        tableStrategy:
          standard:
            shardingColumn: user_id
            shardingAlgorithmName: table_mod

    shardingAlgorithms:
      db_mod:
        type: MOD
        props:
          sharding-count: 16

      table_mod:
        type: MOD
        props:
          sharding-count: 64
```

---

## 四、分布式ID生成

分库分表后，主键ID不能使用AUTO_INCREMENT（会重复）。

### 4.1 雪花算法（Snowflake）

```
64位ID结构：
  1位符号位 + 41位时间戳 + 10位机器ID + 12位序列号

  0 - 00000000000000000000000000000000000000000 - 0000000000 - 000000000000
  ↑                   ↑                            ↑            ↑
  符号                毫秒时间戳                    机器ID       序列号

特点：
  ✅ 趋势递增（时间有序）
  ✅ 高性能（本地生成，无网络IO）
  ✅ 每毫秒4096个ID
  ❌ 依赖系统时间（时钟回拨问题）
```

**Java实现：**

```java
public class SnowflakeIdGenerator {

    private final long epoch = 1609459200000L;  // 2021-01-01
    private final long workerIdBits = 10L;
    private final long sequenceBits = 12L;

    private final long workerId;
    private long sequence = 0L;
    private long lastTimestamp = -1L;

    public synchronized long nextId() {
        long timestamp = System.currentTimeMillis();

        // 时钟回拨检测
        if (timestamp < lastTimestamp) {
            throw new RuntimeException("Clock moved backwards");
        }

        if (timestamp == lastTimestamp) {
            // 同一毫秒内，序列号+1
            sequence = (sequence + 1) & ((1 << sequenceBits) - 1);
            if (sequence == 0) {
                // 序列号用完，等待下一毫秒
                timestamp = waitNextMillis(lastTimestamp);
            }
        } else {
            sequence = 0L;
        }

        lastTimestamp = timestamp;

        return ((timestamp - epoch) << (workerIdBits + sequenceBits))
            | (workerId << sequenceBits)
            | sequence;
    }
}
```

---

### 4.2 号段模式

```sql
-- ID分配表
CREATE TABLE id_generator (
    biz_type VARCHAR(50) PRIMARY KEY,
    max_id BIGINT NOT NULL,
    step INT NOT NULL
);

-- 每次批量获取一段ID
UPDATE id_generator
SET max_id = max_id + step
WHERE biz_type = 'order';

-- 应用层缓存：[1000, 2000)
-- 用完后再申请下一段：[2000, 3000)

特点：
  ✅ 趋势递增
  ✅ 数据库压力小（批量获取）
  ❌ 服务器重启会浪费一段ID
```

---

## 五、高可用最佳实践

### 5.1 架构演进路径

```
阶段1：单机（QPS < 1000）
  └─ 1台MySQL

阶段2：主从复制（QPS 1000-5000）
  └─ 1主2从 + 读写分离

阶段3：分库分表（QPS 5000-5万）
  └─ 16个分片 × (1主2从)

阶段4：分布式数据库（QPS > 5万）
  └─ TiDB、CockroachDB
```

---

### 5.2 监控与运维

**关键指标：**

```sql
-- 1. 主从延迟
SHOW SLAVE STATUS\G
-- Seconds_Behind_Master: < 1秒正常

-- 2. QPS/TPS
SHOW GLOBAL STATUS LIKE 'Questions';
SHOW GLOBAL STATUS LIKE 'Com_commit';

-- 3. 慢查询
SHOW VARIABLES LIKE 'slow_query_log';
SHOW VARIABLES LIKE 'long_query_time';

-- 4. 连接数
SHOW STATUS LIKE 'Threads_connected';
SHOW VARIABLES LIKE 'max_connections';
```

---

## 总结

本文介绍了MySQL高可用架构的核心技术：

**主从复制：**
- binlog三种格式（Row推荐）
- 三种复制模式（半同步平衡性能和安全）
- 主从延迟优化（并行复制）

**读写分离：**
- 架构设计（中间件路由）
- 延迟处理（强制主库读）

**分库分表：**
- 垂直拆分（业务拆分）
- 水平拆分（数据拆分）
- 分片键选择（高频、均匀）

**分布式ID：**
- 雪花算法（趋势递增）
- 号段模式（批量获取）

---

**参考资料:**
- 《高性能MySQL（第4版）》第10章
- 《MySQL技术内幕:InnoDB存储引擎》第9章
- ShardingSphere官方文档
