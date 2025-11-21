---
title: Redis高可用架构：主从复制、哨兵、集群
date: 2025-11-03T10:00:00+08:00
draft: false
tags:
  - Redis
  - 高可用
  - 主从复制
  - 哨兵
  - 集群
  - 第一性原理
categories:
  - Java技术生态
series:
  - Redis第一性原理
weight: 41
stage: 2
stageTitle: "原理探索篇"
description: 深度剖析Redis高可用架构演进：从单机到主从复制、从哨兵到集群。详解全量同步、增量同步、哈希槽分片、故障转移等核心机制。包含生产环境配置、性能优化和故障排查。19000字深度技术文章。
---

## 一、引子：单机Redis的三大困境

假设你正在运行一个电商网站，使用单机Redis作为缓存。随着业务增长，你会遇到三个核心问题：

### 1.1 问题1：单点故障（可用性）

```
场景：双11大促，凌晨0点

00:00:00 - Redis单机宕机（内存不足OOM）
00:00:01 - 所有请求打到数据库
00:00:02 - 数据库连接池耗尽（1000个请求/秒）
00:00:03 - 数据库CPU 100%
00:00:05 - 网站503错误，用户无法下单
00:00:10 - 运维手动重启Redis
00:00:15 - Redis启动成功，但缓存为空
00:00:20 - 缓存预热中（需要10分钟）
00:10:00 - 系统恢复正常

损失：
- 10分钟宕机时间
- 订单损失：10分钟 × 1000单/分钟 = 1万单
- GMV损失：1万单 × 200元/单 = 200万元
```

**核心问题**：单点故障导致系统不可用，无容灾能力。

**可用性计算**：

```
假设：Redis每月宕机1次，每次10分钟

可用性 = (30天 × 24小时 × 60分钟 - 10分钟) / (30天 × 24小时 × 60分钟)
       = (43200 - 10) / 43200
       = 99.977%

看起来还不错？但实际上：
- 1年12次宕机，累计120分钟 = 2小时
- 如果恰好在大促期间宕机，损失巨大
- 高可用系统要求：99.99%（年宕机时间 < 52分钟）
```

### 1.2 问题2：容量瓶颈（可扩展性）

```
场景：业务增长，数据量暴增

第1个月：
- 商品数量：10万
- 缓存数据量：2GB
- 单机Redis：4GB内存（够用）

第6个月：
- 商品数量：100万
- 缓存数据量：20GB
- 单机Redis：4GB内存（不够用！）

解决方案1：垂直扩展（加内存）
- 4GB → 16GB（成本翻倍，但有上限）
- 最大：512GB（成本极高，且有物理上限）

解决方案2：水平扩展（加机器）
- 需要Redis集群（数据分片）
```

**核心问题**：单机内存有限，垂直扩展有上限，需要水平扩展。

### 1.3 问题3：性能瓶颈（QPS限制）

```
场景：秒杀活动，QPS暴增

平时：
- QPS：1万
- 单机Redis：可以承受（QPS上限10万）

秒杀时：
- QPS：50万
- 单机Redis：无法承受（CPU 100%）

瓶颈分析：
- 单线程模型（Redis 6.0之前）
- CPU成为瓶颈（单核占满）
- 网络带宽瓶颈（1Gbps = 125MB/s）

解决方案：水平扩展（多台Redis）
- 3台Redis：QPS = 3 × 10万 = 30万
- 10台Redis：QPS = 10 × 10万 = 100万
```

**核心问题**：单机QPS有限，需要多台Redis提升并发能力。

### 1.4 三大问题总结

| 问题 | 现象 | 影响 | 解决方案 |
|------|-----|------|---------|
| **单点故障** | Redis宕机，系统不可用 | 可用性差（99.9%） | **主从复制 + 哨兵** |
| **容量瓶颈** | 数据量超过单机内存 | 无法存储更多数据 | **集群（数据分片）** |
| **性能瓶颈** | QPS超过单机上限 | 响应慢、超时 | **集群（负载均衡）** |

**Redis高可用架构演进路径**：

```
单机Redis
  ↓ 问题：单点故障
主从复制（Master-Slave）
  ↓ 问题：手动故障转移
哨兵模式（Sentinel）
  ↓ 问题：容量和性能瓶颈
集群模式（Cluster）
  ✅ 解决所有问题
```

---

## 二、主从复制：数据备份与读写分离

### 2.1 主从复制的核心思想

**原理**：1个Master（主节点）+ N个Slave（从节点）

```
架构：
         ┌─────────────┐
         │   Master    │ ← 写操作
         │  (可读可写)  │
         └─────────────┘
              ↓  ↓  ↓ 数据同步
     ┌────────┼────────┼────────┐
     ↓        ↓        ↓        ↓
┌─────────┐ ┌─────────┐ ┌─────────┐
│ Slave 1 │ │ Slave 2 │ │ Slave 3 │ ← 读操作
│ (只读)  │ │ (只读)  │ │ (只读)  │
└─────────┘ └─────────┘ └─────────┘

工作流程：
1. 客户端写入数据到Master
2. Master将数据同步到所有Slave
3. 客户端从Slave读取数据（读写分离）

优势：
- 数据备份（Slave是Master的副本）
- 读写分离（Master写，Slave读）
- 容灾能力（Master宕机，Slave可以顶上）
```

### 2.2 搭建主从复制

**环境准备**：

```bash
# 1台Master + 2台Slave
Master: 127.0.0.1:6379
Slave1: 127.0.0.1:6380
Slave2: 127.0.0.1:6381
```

**Master配置**（redis-6379.conf）：

```bash
# 端口
port 6379

# 绑定IP（0.0.0.0允许所有IP访问）
bind 0.0.0.0

# 后台运行
daemonize yes

# 日志文件
logfile "redis-6379.log"

# 数据目录
dir /var/redis/6379

# RDB持久化
save 900 1
save 300 10
save 60 10000

# AOF持久化
appendonly yes
appendfilename "appendonly-6379.aof"

# 密码（可选）
requirepass mypassword
```

**Slave配置**（redis-6380.conf）：

```bash
# 端口
port 6380

# 绑定IP
bind 0.0.0.0

# 后台运行
daemonize yes

# 日志文件
logfile "redis-6380.log"

# 数据目录
dir /var/redis/6380

# ========== 主从复制配置 ==========

# 指定Master（Redis 5.0之前使用slaveof）
replicaof 127.0.0.1 6379

# Master密码（如果Master设置了密码）
masterauth mypassword

# Slave只读（默认yes）
replica-read-only yes

# Slave优先级（数字越小优先级越高，用于故障转移）
replica-priority 100
```

**启动Redis**：

```bash
# 启动Master
redis-server /path/to/redis-6379.conf

# 启动Slave1
redis-server /path/to/redis-6380.conf

# 启动Slave2
redis-server /path/to/redis-6381.conf

# 查看主从状态
redis-cli -p 6379 INFO replication
```

**验证主从复制**：

```bash
# 在Master写入数据
127.0.0.1:6379> SET mykey "Hello Redis"
OK

# 在Slave读取数据
127.0.0.1:6380> GET mykey
"Hello Redis"  # 数据已同步

# Slave无法写入
127.0.0.1:6380> SET newkey "value"
(error) READONLY You can't write against a read only replica.
```

### 2.3 主从复制原理：全量同步 vs 增量同步

Redis主从复制分为两种：**全量同步**（第一次）和**增量同步**（后续）。

#### 全量同步（Full Resynchronization）

**触发条件**：
- Slave第一次连接Master
- Slave重启后重新连接Master
- Slave的复制偏移量在Master的复制积压缓冲区中找不到

**全量同步流程**：

```
时间线：

T1: Slave发送PSYNC命令到Master
    PSYNC ? -1  # ?表示第一次，-1表示从头开始

T2: Master判断是全量同步，回复+FULLRESYNC
    +FULLRESYNC <runid> <offset>

T3: Master执行BGSAVE，生成RDB快照文件
    BGSAVE在后台fork子进程，不阻塞主线程

T4: Master将RDB文件发送给Slave
    网络传输RDB文件（可能很大，如10GB）

T5: Master同时将新的写命令存入复制缓冲区
    这段时间的写命令会暂存

T6: Slave接收RDB文件，清空旧数据，加载RDB
    FLUSHALL → 加载RDB

T7: Master将复制缓冲区的命令发送给Slave
    增量同步这段时间的写命令

T8: Slave执行这些命令，完成全量同步
    现在Master和Slave数据一致

性能分析：
- BGSAVE时间：10GB数据约需30秒
- 网络传输时间：10GB / 100MB/s = 100秒
- 加载RDB时间：10GB数据约需30秒
- 总耗时：约160秒（近3分钟）
```

**全量同步的性能开销**：

```
Master开销：
- CPU：fork子进程（瞬时开销）
- 磁盘IO：写RDB文件（30秒）
- 网络带宽：发送RDB文件（100秒）
- 内存：复制缓冲区（存储这段时间的写命令）

Slave开销：
- 网络带宽：接收RDB文件（100秒）
- 磁盘IO：写RDB文件（30秒）
- CPU/内存：加载RDB文件（30秒）
- 阻塞：加载期间无法提供服务

问题：
- 全量同步耗时长（几分钟）
- Master和Slave压力大
- 如果网络断开，需要重新全量同步（太重）
```

#### 增量同步（Partial Resynchronization）

**触发条件**：
- Slave短暂断开连接后重连
- Slave的复制偏移量在Master的复制积压缓冲区中能找到

**增量同步流程**（Redis 2.8+）：

```
核心机制：
1. 复制偏移量（replication offset）
   - Master和Slave都维护一个偏移量
   - 每执行一个写命令，偏移量+1

2. 复制积压缓冲区（replication backlog）
   - Master维护一个固定大小的FIFO队列（默认1MB）
   - 存储最近的写命令

3. 运行ID（run id）
   - Master启动时生成唯一ID
   - 用于判断是否是同一个Master

增量同步流程：

T1: Slave断开连接（网络抖动）
    此时Master偏移量：1000
    此时Slave偏移量：950

T2: Slave重新连接Master
    发送PSYNC命令：PSYNC <runid> <offset>
    PSYNC xxxxx 950

T3: Master判断offset=950在复制积压缓冲区中
    回复+CONTINUE

T4: Master将offset=950之后的命令发送给Slave
    只发送增量数据（950到1000之间的命令）

T5: Slave执行这些命令，完成增量同步
    现在Master和Slave数据一致

性能分析：
- 只发送增量数据（可能只有几KB）
- 耗时：毫秒级
- 无需BGSAVE，无需发送RDB文件
- 性能提升：1000倍+
```

**复制积压缓冲区大小配置**：

```bash
# redis.conf
# 默认1MB，建议根据业务调整
repl-backlog-size 1mb

# 如何计算合适的大小？
# 复制积压缓冲区大小 = 平均写入速度 × 平均断开时间

# 示例：
# 平均写入速度：1MB/秒
# 平均断开时间：60秒（网络抖动）
# 建议大小：1MB/s × 60s = 60MB

repl-backlog-size 64mb
```

### 2.4 主从复制的应用：读写分离

**场景**：电商商品详情页（读多写少）

```java
@Service
public class ProductService {

    @Autowired
    @Qualifier("masterRedisTemplate")
    private RedisTemplate<String, ProductVO> masterRedis;  // 写Master

    @Autowired
    @Qualifier("slaveRedisTemplate")
    private RedisTemplate<String, ProductVO> slaveRedis;   // 读Slave

    /**
     * 获取商品详情（从Slave读）
     */
    public ProductVO getProduct(Long productId) {
        String cacheKey = "product:detail:" + productId;

        // 从Slave读取
        ProductVO cached = slaveRedis.opsForValue().get(cacheKey);
        if (cached != null) {
            return cached;
        }

        // 缓存未命中，查数据库
        Product product = productRepository.findById(productId);
        if (product == null) {
            return null;
        }

        ProductVO vo = convertToVO(product);

        // 写入Master（会自动同步到Slave）
        masterRedis.opsForValue().set(cacheKey, vo, 30, TimeUnit.MINUTES);

        return vo;
    }

    /**
     * 更新商品（写Master）
     */
    @Transactional
    public void updateProduct(Product product) {
        // 1. 更新数据库
        productRepository.update(product);

        // 2. 删除Master缓存（会自动同步到Slave）
        String cacheKey = "product:detail:" + product.getId();
        masterRedis.delete(cacheKey);
    }
}
```

**Spring Boot配置多数据源**：

```java
@Configuration
public class RedisConfig {

    /**
     * Master Redis配置
     */
    @Bean("masterRedisTemplate")
    public RedisTemplate<String, Object> masterRedisTemplate() {
        RedisStandaloneConfiguration config = new RedisStandaloneConfiguration();
        config.setHostName("127.0.0.1");
        config.setPort(6379);
        config.setPassword(RedisPassword.of("mypassword"));

        LettuceConnectionFactory factory = new LettuceConnectionFactory(config);
        factory.afterPropertiesSet();

        RedisTemplate<String, Object> template = new RedisTemplate<>();
        template.setConnectionFactory(factory);
        template.setKeySerializer(new StringRedisSerializer());
        template.setValueSerializer(new GenericJackson2JsonRedisSerializer());
        template.afterPropertiesSet();

        return template;
    }

    /**
     * Slave Redis配置（读取）
     */
    @Bean("slaveRedisTemplate")
    public RedisTemplate<String, Object> slaveRedisTemplate() {
        RedisStandaloneConfiguration config = new RedisStandaloneConfiguration();
        config.setHostName("127.0.0.1");
        config.setPort(6380);  // Slave端口
        config.setPassword(RedisPassword.of("mypassword"));

        LettuceConnectionFactory factory = new LettuceConnectionFactory(config);
        factory.afterPropertiesSet();

        RedisTemplate<String, Object> template = new RedisTemplate<>();
        template.setConnectionFactory(factory);
        template.setKeySerializer(new StringRedisSerializer());
        template.setValueSerializer(new GenericJackson2JsonRedisSerializer());
        template.afterPropertiesSet();

        return template;
    }
}
```

**读写分离的性能提升**：

```
场景：商品详情页
- 读写比：1000:1（读多写少）
- QPS：10万

单机Redis：
- Master承受所有读写：10万QPS
- CPU占用：80%
- 接近性能上限

主从复制（1 Master + 2 Slave）：
- Master承受写：100 QPS（10万 / 1000）
- Slave承受读：各5万 QPS（10万 / 2）
- Master CPU占用：10%
- Slave CPU占用：40%
- 性能提升：3倍（可以支撑30万QPS）

性能对比：
- 单机：10万QPS
- 1主2从：30万QPS
- 1主5从：60万QPS
```

### 2.5 主从复制的问题

```
问题1：Master宕机，需要手动故障转移
- Master宕机，Slave无法自动提升为Master
- 需要运维手动执行SLAVEOF NO ONE
- 恢复时间：分钟级（人工介入）

问题2：数据不一致窗口
- Master写入成功，Slave还未同步
- 如果此时Master宕机，数据丢失
- 异步复制导致的问题

问题3：Slave故障无法自动剔除
- Slave宕机，需要手动从负载均衡中移除
- 否则客户端会读到错误

问题4：无法水平扩展
- 所有数据都在Master上
- 无法分片，容量受限于单机内存

解决方案：哨兵模式（自动故障转移）
```

---

## 三、哨兵模式：自动故障转移

### 3.1 哨兵的核心思想

**哨兵（Sentinel）**：监控Redis实例，自动故障转移。

```
架构：
         ┌─────────────┐
         │  Sentinel 1 │ ← 监控
         └─────────────┘
              ↓  监控
         ┌─────────────┐
         │  Sentinel 2 │ ← 监控
         └─────────────┘
              ↓  监控
         ┌─────────────┐
         │  Sentinel 3 │ ← 监控（至少3个，奇数）
         └─────────────┘
              ↓  ↓  ↓
         ┌─────────────┐
         │   Master    │ ← 主节点
         └─────────────┘
              ↓  ↓
     ┌────────┴────────┐
     ↓                 ↓
┌─────────┐       ┌─────────┐
│ Slave 1 │       │ Slave 2 │ ← 从节点
└─────────┘       └─────────┘

哨兵的职责：
1. 监控（Monitoring）：
   - 定期ping Master和Slave
   - 检查是否在线

2. 通知（Notification）：
   - Master故障时通知管理员
   - 通知客户端Master地址变更

3. 自动故障转移（Automatic Failover）：
   - Master宕机时，自动选举Slave为新Master
   - 其他Slave改为复制新Master
   - 旧Master恢复后变为Slave

4. 配置提供者（Configuration Provider）：
   - 客户端连接Sentinel获取Master地址
   - 故障转移后，客户端自动连接新Master
```

### 3.2 搭建哨兵集群

**环境准备**：

```bash
# 1个Master + 2个Slave + 3个Sentinel
Master:    127.0.0.1:6379
Slave1:    127.0.0.1:6380
Slave2:    127.0.0.1:6381
Sentinel1: 127.0.0.1:26379
Sentinel2: 127.0.0.1:26380
Sentinel3: 127.0.0.1:26381
```

**Sentinel配置**（sentinel-26379.conf）：

```bash
# 端口
port 26379

# 后台运行
daemonize yes

# 日志文件
logfile "sentinel-26379.log"

# 工作目录
dir /var/redis/sentinel

# ========== 监控配置 ==========

# 监控Master（mymaster是自定义名称）
# sentinel monitor <master-name> <ip> <port> <quorum>
# quorum：判断Master客观下线需要的Sentinel数量
sentinel monitor mymaster 127.0.0.1 6379 2

# Master密码
sentinel auth-pass mymaster mypassword

# Master被判定为主观下线的时间（30秒内没有回应）
sentinel down-after-milliseconds mymaster 30000

# 故障转移超时时间（3分钟）
sentinel failover-timeout mymaster 180000

# 并行同步Slave数量（1个Slave完成后再同步下一个）
sentinel parallel-syncs mymaster 1
```

**配置说明**：

```bash
# quorum参数详解
sentinel monitor mymaster 127.0.0.1 6379 2

quorum = 2 表示：
- 至少2个Sentinel认为Master主观下线
- 才判定Master客观下线
- 然后触发故障转移

假设有3个Sentinel：
- quorum = 2：允许1个Sentinel宕机
- quorum = 3：不允许Sentinel宕机（太严格）
- 推荐：quorum = Sentinel总数 / 2 + 1（过半数）

# down-after-milliseconds参数
sentinel down-after-milliseconds mymaster 30000

含义：
- Sentinel每10秒ping一次Master
- 如果30秒内没有回应，判定为主观下线
- 建议：30秒（太短容易误判，太长恢复慢）

# parallel-syncs参数
sentinel parallel-syncs mymaster 1

含义：
- 故障转移后，同时同步几个Slave
- 1：一个一个同步（慢但稳）
- 2：两个同时同步（快但压力大）
- 推荐：1（避免Master压力过大）
```

**启动Sentinel**：

```bash
# 启动Sentinel1
redis-sentinel /path/to/sentinel-26379.conf

# 启动Sentinel2
redis-sentinel /path/to/sentinel-26380.conf

# 启动Sentinel3
redis-sentinel /path/to/sentinel-26381.conf

# 查看Sentinel状态
redis-cli -p 26379 SENTINEL masters
redis-cli -p 26379 SENTINEL slaves mymaster
redis-cli -p 26379 SENTINEL sentinels mymaster
```

### 3.3 故障转移流程

**完整故障转移流程**：

```
T1: Master宕机（6379端口无响应）

T2: Sentinel1每10秒ping Master，30秒内无响应
    Sentinel1判定Master主观下线（Subjectively Down）

T3: Sentinel1询问其他Sentinel："Master是否下线？"
    Sentinel2: "是的，我也ping不通"
    Sentinel3: "是的，我也ping不通"

T4: 达到quorum=2，Sentinel1判定Master客观下线（Objectively Down）
    触发故障转移流程

T5: Sentinel之间进行Leader选举（Raft协议）
    Sentinel2当选为Leader，负责故障转移

T6: Sentinel2从Slave中选举新Master
    选举规则：
    1. 排除主观下线的Slave
    2. 排除5秒内没有回复INFO命令的Slave
    3. 排除与旧Master断开连接超过10秒的Slave
    4. 选择优先级最高的Slave（replica-priority）
    5. 优先级相同，选择复制偏移量最大的（数据最新）
    6. 偏移量相同，选择run id最小的

T7: Sentinel2向选中的Slave（假设是6380）发送SLAVEOF NO ONE
    Slave 6380提升为新Master

T8: Sentinel2向其他Slave（6381）发送SLAVEOF 127.0.0.1 6380
    Slave 6381改为复制新Master

T9: Sentinel2更新配置，记录新Master地址
    所有Sentinel的配置文件都会自动更新

T10: Sentinel2通知客户端Master地址变更
     客户端自动连接新Master（127.0.0.1:6380）

T11: 旧Master（6379）恢复后，Sentinel将其设置为Slave
     SLAVEOF 127.0.0.1 6380

故障转移完成！
总耗时：约30-60秒（自动完成，无需人工介入）
```

**故障转移时间分解**：

```
1. 主观下线判定：30秒（down-after-milliseconds）
2. 客观下线判定：1秒（Sentinel之间通信）
3. Leader选举：1秒（Raft协议）
4. 新Master选举：1秒
5. Slave切换：1秒（SLAVEOF命令）
6. 配置更新：1秒
7. 客户端感知：5秒（连接池刷新）

总计：约40秒（相比人工介入的10分钟，提升15倍）
```

### 3.4 Spring Boot集成Sentinel

**添加依赖**：

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-data-redis</artifactId>
</dependency>
<dependency>
    <groupId>io.lettuce</groupId>
    <artifactId>lettuce-core</artifactId>
</dependency>
```

**配置文件**（application.yml）：

```yaml
spring:
  redis:
    # 不再直接连接Master，而是连接Sentinel
    sentinel:
      master: mymaster  # Master名称（与sentinel.conf中的一致）
      nodes:
        - 127.0.0.1:26379
        - 127.0.0.1:26380
        - 127.0.0.1:26381
    password: mypassword
    database: 0
    lettuce:
      pool:
        max-active: 8
        max-idle: 8
        min-idle: 0
        max-wait: -1ms
```

**测试故障转移**：

```java
@SpringBootTest
public class SentinelTest {

    @Autowired
    private RedisTemplate<String, String> redisTemplate;

    @Test
    public void testSentinelFailover() throws InterruptedException {
        // 循环写入数据，观察故障转移
        for (int i = 0; i < 100; i++) {
            try {
                String key = "test:key:" + i;
                String value = "value:" + i;

                redisTemplate.opsForValue().set(key, value, 60, TimeUnit.SECONDS);
                System.out.println("写入成功：" + key);

                Thread.sleep(1000);  // 每秒写一次

            } catch (Exception e) {
                System.err.println("写入失败：" + e.getMessage());
                // 客户端会自动重连新Master
            }
        }
    }
}
```

**测试步骤**：

```bash
# 1. 启动测试程序（循环写入数据）
mvn test

# 2. 手动kill Master进程
redis-cli -p 6379 SHUTDOWN

# 3. 观察日志
# 约30秒后，Sentinel会自动故障转移
# 客户端自动连接新Master，写入恢复

# 4. 查看新Master
redis-cli -p 26379 SENTINEL get-master-addr-by-name mymaster
# 输出：127.0.0.1 6380（新Master）
```

### 3.5 哨兵的问题

```
问题1：容量瓶颈
- 所有数据仍在Master上
- 无法水平扩展
- 数据量受限于单机内存

问题2：QPS瓶颈
- Master处理所有写操作
- QPS受限于单机性能
- 无法通过增加机器提升QPS

问题3：无法数据分片
- 所有key都在同一个Master
- 无法按key分布到不同节点

解决方案：Redis Cluster（集群模式）
```

---

## 四、Redis Cluster：数据分片与高可用

### 4.1 Redis Cluster的核心思想

**原理**：多个Master节点，数据分片存储。

```
架构：
  ┌────────────────────────────────────────┐
  │          Redis Cluster                 │
  │                                        │
  │  ┌──────────┐  ┌──────────┐  ┌──────────┐
  │  │ Master 1 │  │ Master 2 │  │ Master 3 │
  │  │ (槽0-    │  │ (槽5461- │  │ (槽10923-│
  │  │  5460)   │  │  10922)  │  │  16383)  │
  │  └──────────┘  └──────────┘  └──────────┘
  │       ↓             ↓             ↓
  │  ┌──────────┐  ┌──────────┐  ┌──────────┐
  │  │ Slave 1  │  │ Slave 2  │  │ Slave 3  │
  │  └──────────┘  └──────────┘  └──────────┘
  │                                        │
  └────────────────────────────────────────┘

核心概念：
1. 哈希槽（Hash Slot）：
   - 16384个槽（0-16383）
   - 每个Master负责一部分槽
   - key通过CRC16(key) % 16384计算槽位

2. 数据分片：
   - key自动分布到不同Master
   - 水平扩展（增加Master即可扩容）

3. 高可用：
   - 每个Master配1-2个Slave
   - Master宕机，Slave自动提升

优势：
- 容量：理论无限（增加节点即可）
- QPS：线性扩展（3个Master = 3倍QPS）
- 高可用：自动故障转移
```

### 4.2 哈希槽分片原理

**哈希槽计算**：

```
槽位计算公式：
slot = CRC16(key) % 16384

示例：
key = "user:123"
CRC16("user:123") = 12345
slot = 12345 % 16384 = 12345

查找流程：
1. 客户端计算key的槽位：slot = 12345
2. 查找槽位12345属于哪个Master
   - Master1: 0-5460（不包含12345）
   - Master2: 5461-10922（不包含12345）
   - Master3: 10923-16383（包含12345）✓
3. 连接Master3，执行命令

为什么是16384个槽？
- 2^14 = 16384
- 足够多（可以支持1000+节点）
- 不太多（心跳包不会太大）
- 与主从复制的偏移量对齐
```

**Hash Tag（哈希标签）**：

```
问题：多个key需要在同一个节点

场景：购物车
cart:user:123:item:1
cart:user:123:item:2
cart:user:123:item:3

默认：
- 这3个key可能分布在不同节点
- 无法用MGET批量获取
- 无法用事务MULTI/EXEC

解决：Hash Tag
{user:123}:cart:item:1
{user:123}:cart:item:2
{user:123}:cart:item:3

计算槽位：
slot = CRC16("user:123") % 16384

所有带{user:123}的key都在同一个槽位！
```

### 4.3 搭建Redis Cluster

**环境准备**：

```bash
# 3个Master + 3个Slave
Master1: 127.0.0.1:7000  →  Slave1: 127.0.0.1:7003
Master2: 127.0.0.1:7001  →  Slave2: 127.0.0.1:7004
Master3: 127.0.0.1:7002  →  Slave3: 127.0.0.1:7005
```

**节点配置**（redis-7000.conf）：

```bash
# 端口
port 7000

# 绑定IP
bind 0.0.0.0

# 后台运行
daemonize yes

# 日志文件
logfile "redis-7000.log"

# 数据目录
dir /var/redis/7000

# ========== 集群配置 ==========

# 启用集群模式
cluster-enabled yes

# 集群配置文件（自动生成）
cluster-config-file nodes-7000.conf

# 节点超时时间（15秒）
cluster-node-timeout 15000

# 启用AOF
appendonly yes
```

**创建集群**：

```bash
# Redis 5.0+使用redis-cli创建集群
redis-cli --cluster create \
  127.0.0.1:7000 \
  127.0.0.1:7001 \
  127.0.0.1:7002 \
  127.0.0.1:7003 \
  127.0.0.1:7004 \
  127.0.0.1:7005 \
  --cluster-replicas 1  # 每个Master配1个Slave

# 输出：
>>> Performing hash slots allocation on 6 nodes...
Master[0] -> Slots 0 - 5460
Master[1] -> Slots 5461 - 10922
Master[2] -> Slots 10923 - 16383
Adding replica 127.0.0.1:7004 to 127.0.0.1:7000
Adding replica 127.0.0.1:7005 to 127.0.0.1:7001
Adding replica 127.0.0.1:7003 to 127.0.0.1:7002

# 确认创建
Can I set the above configuration? (type 'yes' to accept): yes

# 集群创建成功！
```

**验证集群**：

```bash
# 连接集群（-c参数表示集群模式）
redis-cli -c -p 7000

# 查看集群信息
127.0.0.1:7000> CLUSTER INFO
cluster_state:ok
cluster_slots_assigned:16384
cluster_slots_ok:16384
cluster_known_nodes:6
cluster_size:3

# 查看集群节点
127.0.0.1:7000> CLUSTER NODES
abc123... 127.0.0.1:7000@17000 myself,master - 0 0 1 connected 0-5460
def456... 127.0.0.1:7001@17001 master - 0 1635000000 2 connected 5461-10922
ghi789... 127.0.0.1:7002@17002 master - 0 1635000000 3 connected 10923-16383
jkl012... 127.0.0.1:7003@17003 slave ghi789... 0 1635000000 3 connected
mno345... 127.0.0.1:7004@17004 slave abc123... 0 1635000000 1 connected
pqr678... 127.0.0.1:7005@17005 slave def456... 0 1635000000 2 connected

# 测试数据写入
127.0.0.1:7000> SET user:123 "Alice"
-> Redirected to slot [12345] located at 127.0.0.1:7002
OK

# 客户端自动重定向到正确的节点（7002）
```

### 4.4 集群重定向机制

**MOVED重定向**（槽位已迁移）：

```
场景：客户端连接错误的节点

T1: 客户端连接7000，执行 GET user:123
    slot = CRC16("user:123") % 16384 = 12345

T2: 7000判断slot=12345不归自己管理
    返回：(error) MOVED 12345 127.0.0.1:7002

T3: 客户端收到MOVED，记录槽位映射
    缓存：slot 12345 → 127.0.0.1:7002

T4: 客户端重新连接7002，执行 GET user:123
    返回：value

T5: 客户端后续对slot=12345的操作，直接连接7002
    无需再重定向
```

**ASK重定向**（槽位正在迁移）：

```
场景：集群扩容，槽位正在迁移

T1: 集群扩容，增加Master4
    决定将slot=12345从Master3迁移到Master4

T2: 迁移开始，slot=12345进入迁移状态
    Master3标记：slot 12345 正在迁移到Master4

T3: 客户端连接Master3，执行 GET user:123
    Master3检查key是否已迁移：
    - 如果key还在Master3：返回value
    - 如果key已迁移到Master4：返回 (error) ASK 12345 127.0.0.1:7003

T4: 客户端收到ASK，临时连接Master4
    发送ASKING命令（告诉Master4这是临时请求）
    ASKING
    GET user:123
    返回：value

T5: 迁移完成后，客户端再次请求
    Master3返回：(error) MOVED 12345 127.0.0.1:7003
    客户端更新槽位映射

MOVED vs ASK：
- MOVED：槽位已永久迁移，客户端更新缓存
- ASK：槽位正在迁移，客户端临时重定向，不更新缓存
```

### 4.5 集群扩容与缩容

**扩容（增加节点）**：

```bash
# 1. 启动新节点
redis-server /path/to/redis-7006.conf
redis-server /path/to/redis-7007.conf

# 2. 将新节点加入集群（作为Master）
redis-cli --cluster add-node 127.0.0.1:7006 127.0.0.1:7000

# 3. 分配槽位给新节点（从其他Master分一些槽位过来）
redis-cli --cluster reshard 127.0.0.1:7000
# 输入要迁移的槽位数量：5461
# 输入目标节点ID（7006的ID）
# 输入源节点ID（all表示从所有Master平均分配）

# 4. 给新Master添加Slave
redis-cli --cluster add-node 127.0.0.1:7007 127.0.0.1:7000 --cluster-slave --cluster-master-id <7006的ID>

# 扩容完成！
# 原来：3个Master，每个5461个槽
# 现在：4个Master，每个4096个槽
```

**槽位迁移过程**：

```
T1: 开始迁移slot=100从Master1到Master4

T2: Master1将slot=100标记为迁移状态
    CLUSTER SETSLOT 100 MIGRATING <Master4-id>

T3: Master4将slot=100标记为导入状态
    CLUSTER SETSLOT 100 IMPORTING <Master1-id>

T4: Master1逐个迁移slot=100的key到Master4
    for key in slot 100:
        MIGRATE 127.0.0.1 7006 key 0 5000

T5: 所有key迁移完成，更新槽位归属
    Master1: CLUSTER SETSLOT 100 NODE <Master4-id>
    Master4: CLUSTER SETSLOT 100 NODE <Master4-id>

T6: 通知所有节点槽位变更
    广播：slot 100 → Master4

迁移完成！
```

**缩容（删除节点）**：

```bash
# 1. 将要删除节点的槽位迁移到其他节点
redis-cli --cluster reshard 127.0.0.1:7000 \
  --cluster-from <要删除节点的ID> \
  --cluster-to <目标节点的ID> \
  --cluster-slots 5461  # 迁移全部槽位

# 2. 删除Slave节点
redis-cli --cluster del-node 127.0.0.1:7000 <Slave节点ID>

# 3. 删除Master节点（槽位必须为0）
redis-cli --cluster del-node 127.0.0.1:7000 <Master节点ID>

# 缩容完成！
```

### 4.6 Spring Boot集成Cluster

**配置文件**（application.yml）：

```yaml
spring:
  redis:
    cluster:
      nodes:
        - 127.0.0.1:7000
        - 127.0.0.1:7001
        - 127.0.0.1:7002
        - 127.0.0.1:7003
        - 127.0.0.1:7004
        - 127.0.0.1:7005
      max-redirects: 3  # 最大重定向次数
    password: mypassword
    lettuce:
      pool:
        max-active: 8
        max-idle: 8
        min-idle: 0
```

**测试集群**：

```java
@SpringBootTest
public class ClusterTest {

    @Autowired
    private RedisTemplate<String, String> redisTemplate;

    @Test
    public void testCluster() {
        // 写入10000个key，观察数据分布
        for (int i = 0; i < 10000; i++) {
            String key = "test:key:" + i;
            String value = "value:" + i;
            redisTemplate.opsForValue().set(key, value);
        }

        System.out.println("写入完成！");

        // 读取数据，客户端会自动路由到正确的节点
        String value = redisTemplate.opsForValue().get("test:key:123");
        System.out.println("test:key:123 = " + value);
    }
}
```

**查看数据分布**：

```bash
# 统计每个节点的key数量
redis-cli -c -p 7000 DBSIZE  # Master1
redis-cli -c -p 7001 DBSIZE  # Master2
redis-cli -c -p 7002 DBSIZE  # Master3

# 输出示例：
# Master1: 3333 keys
# Master2: 3334 keys
# Master3: 3333 keys

# 数据均匀分布！
```

---

## 五、高可用架构对比

### 5.1 三种架构对比

| 维度 | 主从复制 | 哨兵模式 | 集群模式 |
|------|---------|---------|---------|
| **架构** | 1 Master + N Slave | 1 Master + N Slave + 哨兵 | N Master + N Slave |
| **数据分片** | ❌ | ❌ | ✅ |
| **自动故障转移** | ❌（手动） | ✅（自动） | ✅（自动） |
| **容量** | 单机内存 | 单机内存 | 水平扩展（无限） |
| **QPS** | 读：N倍，写：1倍 | 读：N倍，写：1倍 | 读写：N倍 |
| **可用性** | 99.9% | 99.99% | 99.99%+ |
| **复杂度** | 低 | 中 | 高 |
| **适用场景** | 小型业务，读多写少 | 中型业务，需要高可用 | 大型业务，海量数据 |

### 5.2 可用性对比

```
计算公式：
可用性 = MTBF / (MTBF + MTTR)
- MTBF（Mean Time Between Failures）：平均故障间隔时间
- MTTR（Mean Time To Repair）：平均故障恢复时间

单机Redis：
- MTBF：720小时（30天）
- MTTR：10分钟（手动重启）
- 可用性 = 720 / (720 + 0.167) = 99.977%

主从复制：
- MTBF：720小时
- MTTR：10分钟（手动故障转移）
- 可用性 = 99.977%（与单机相同）

哨兵模式：
- MTBF：720小时
- MTTR：1分钟（自动故障转移）
- 可用性 = 720 / (720 + 0.017) = 99.9976%

集群模式：
- MTBF：720小时
- MTTR：30秒（自动故障转移，无需迁移全部数据）
- 可用性 = 720 / (720 + 0.008) = 99.9988%

结论：
- 哨兵模式：99.99%（年宕机时间 < 52分钟）
- 集群模式：99.999%（年宕机时间 < 5分钟）
```

### 5.3 性能对比

```
场景：100万QPS

单机Redis：
- 无法承受（单机QPS上限10万）

主从复制（1 Master + 5 Slave）：
- 写操作：Master 10万QPS（瓶颈）
- 读操作：5个Slave各20万QPS = 100万QPS
- 限制：写QPS仍受限于单机

哨兵模式：
- 同主从复制

集群模式（10个Master，每个Master配1个Slave）：
- 写操作：10个Master各10万QPS = 100万QPS
- 读操作：10个Slave各10万QPS = 100万QPS
- 总计：200万QPS

结论：
- 集群模式可以线性扩展
- 10个Master = 10倍QPS
```

---

## 六、生产环境最佳实践

### 6.1 部署架构建议

**小型业务（QPS < 1万，数据 < 10GB）**：

```
架构：主从复制
- 1 Master + 2 Slave
- 手动故障转移（业务量小，可接受短暂宕机）

成本：
- 3台Redis（2核4G）
- 约600元/月

优势：
- 部署简单
- 成本低
```

**中型业务（QPS < 10万，数据 < 50GB）**：

```
架构：哨兵模式
- 1 Master + 2 Slave + 3 Sentinel
- 自动故障转移

成本：
- 3台Redis（4核8G）
- 3台Sentinel（1核2G）
- 约3000元/月

优势：
- 高可用（99.99%）
- 自动故障转移
```

**大型业务（QPS > 10万，数据 > 50GB）**：

```
架构：集群模式
- 6个Master + 6个Slave（最少配置）
- 数据分片 + 自动故障转移

成本：
- 12台Redis（4核8G）
- 约12000元/月

优势：
- 水平扩展
- 高可用（99.999%）
- 线性扩展QPS
```

### 6.2 配置优化

**内存配置**：

```bash
# redis.conf

# 1. 最大内存
maxmemory 4gb

# 2. 淘汰策略
maxmemory-policy allkeys-lru

# 3. LRU样本数（越大越精确，但越慢）
maxmemory-samples 5
```

**持久化配置**：

```bash
# 1. RDB（快照）
save 900 1      # 900秒内有1次修改，触发BGSAVE
save 300 10     # 300秒内有10次修改
save 60 10000   # 60秒内有10000次修改

# 2. AOF（日志）
appendonly yes
appendfilename "appendonly.aof"

# AOF同步策略
appendfsync everysec  # 每秒同步一次（推荐）
# appendfsync always  # 每次写入都同步（慢但安全）
# appendfsync no      # 由操作系统决定（快但不安全）

# AOF重写
auto-aof-rewrite-percentage 100  # AOF文件大小翻倍时重写
auto-aof-rewrite-min-size 64mb   # AOF文件至少64MB才重写
```

**网络配置**：

```bash
# 1. 最大客户端连接数
maxclients 10000

# 2. TCP backlog
tcp-backlog 511

# 3. 超时时间（0表示永不超时）
timeout 0

# 4. TCP keepalive
tcp-keepalive 300  # 300秒发送一次心跳
```

### 6.3 监控指标

**关键指标**：

```bash
# 1. 内存使用率
used_memory / maxmemory

# 2. QPS
instantaneous_ops_per_sec

# 3. 命中率
keyspace_hits / (keyspace_hits + keyspace_misses)

# 4. 连接数
connected_clients

# 5. 慢查询数
slowlog len

# 6. 主从延迟
master_repl_offset - slave_repl_offset

# 7. 过期key数
expired_keys

# 8. 淘汰key数
evicted_keys
```

**监控脚本**：

```python
import redis
import time

def monitor_redis(host, port):
    r = redis.Redis(host=host, port=port, decode_responses=True)

    while True:
        info = r.info()

        # 内存使用率
        used_memory = info['used_memory']
        maxmemory = info['maxmemory']
        memory_usage = used_memory / maxmemory * 100 if maxmemory > 0 else 0

        # QPS
        qps = info['instantaneous_ops_per_sec']

        # 命中率
        hits = info['keyspace_hits']
        misses = info['keyspace_misses']
        hit_rate = hits / (hits + misses) * 100 if (hits + misses) > 0 else 0

        # 连接数
        connected_clients = info['connected_clients']

        print(f"时间: {time.strftime('%H:%M:%S')}")
        print(f"内存使用率: {memory_usage:.2f}%")
        print(f"QPS: {qps}")
        print(f"命中率: {hit_rate:.2f}%")
        print(f"连接数: {connected_clients}")
        print("-" * 50)

        time.sleep(5)

if __name__ == '__main__':
    monitor_redis('127.0.0.1', 6379)
```

### 6.4 故障排查

**问题1：主从延迟过大**

```bash
# 现象
127.0.0.1:6379> INFO replication
master_repl_offset:1000000
slave0:offset=900000  # 延迟10万个命令

# 原因
1. 网络延迟（跨地域）
2. Slave处理慢（CPU/内存不足）
3. Master写入速度太快

# 解决
1. 增加Slave配置（CPU/内存）
2. 减少Master写入速度（限流）
3. 增加repl-backlog-size（避免全量同步）
```

**问题2：集群脑裂**

```bash
# 现象
网络分区，导致两个Master同时存在

# 原因
Sentinel或Cluster节点之间网络分区

# 解决
配置min-replicas参数

# redis.conf
min-replicas-to-write 1       # 至少1个Slave在线才能写
min-replicas-max-lag 10       # Slave延迟不超过10秒

# 效果
如果Master无法连接到Slave，拒绝写入
防止脑裂导致数据不一致
```

**问题3：慢查询**

```bash
# 查看慢查询
127.0.0.1:6379> SLOWLOG GET 10

# 常见原因
1. KEYS * （扫描所有key，O(N)）
2. HGETALL big_hash （大Hash，O(N)）
3. SMEMBERS big_set （大Set，O(N)）
4. ZRANGE big_zset 0 -1 （大ZSet，O(N)）

# 解决
1. 避免使用KEYS，改用SCAN
2. 避免大key，拆分为多个小key
3. 使用HSCAN、SSCAN、ZSCAN分批获取
```

---

## 七、总结

### 7.1 核心要点回顾

**Redis高可用架构演进**：

```
单机 → 主从复制 → 哨兵模式 → 集群模式

单机：
- 问题：单点故障、容量瓶颈、性能瓶颈

主从复制：
- 解决：数据备份、读写分离
- 问题：手动故障转移

哨兵模式：
- 解决：自动故障转移
- 问题：容量和性能仍受限

集群模式：
- 解决：数据分片、水平扩展、自动故障转移
- 适用：海量数据、高并发场景
```

**选型建议**：

```
业务规模 → 架构选择

小型（QPS < 1万）：
- 主从复制
- 1 Master + 2 Slave

中型（QPS < 10万）：
- 哨兵模式
- 1 Master + 2 Slave + 3 Sentinel

大型（QPS > 10万）：
- 集群模式
- 6+ Master + 6+ Slave
```

### 7.2 下一步学习

本文是Redis系列的第4篇，后续文章将深入讲解：

1. ✅ Redis第一性原理：为什么我们需要缓存？
2. ✅ 从HashMap到Redis：分布式缓存的演进
3. ✅ Redis五大数据结构：从场景到实现
4. ✅ **Redis高可用架构：主从复制、哨兵、集群**
5. ⏳ Redis持久化：RDB与AOF的权衡
6. ⏳ Redis实战：分布式锁、消息队列、缓存设计

---

**参考资料**：
- 《Redis设计与实现》- 黄健宏
- 《Redis实战》- Josiah L. Carlson
- Redis官方文档：https://redis.io/documentation
- Redis Sentinel文档：https://redis.io/topics/sentinel
- Redis Cluster文档：https://redis.io/topics/cluster-tutorial

---

*本文是"Redis第一性原理"系列的第4篇，共6篇。下一篇将深入讲解《Redis持久化：RDB与AOF的权衡》，敬请期待。*
