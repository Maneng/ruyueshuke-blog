---
title: "故障排查手册：快速定位和解决Redis问题"
date: 2025-01-22T00:10:00+08:00
draft: false
tags: ["Redis", "故障排查", "问题诊断"]
categories: ["技术"]
description: "系统化的Redis故障排查方法论，覆盖连接、性能、内存、数据等常见问题，快速定位根因"
weight: 36
stage: 4
stageTitle: "生产实践篇"
---

## 故障分类

| 故障类型 | 典型现象 | 排查优先级 |
|---------|---------|-----------|
| **连接问题** | 无法连接、超时 | 🔴 最高 |
| **性能问题** | 响应慢、卡顿 | 🟡 高 |
| **内存问题** | OOM、淘汰 | 🟡 高 |
| **数据问题** | 数据丢失、不一致 | 🟡 高 |
| **集群问题** | 节点下线、脑裂 | 🔴 最高 |

## 1. 连接问题排查

### 问题1：无法连接Redis

**症状**：
```
Connection refused
Could not connect to Redis at 127.0.0.1:6379
```

**排查步骤**：
```bash
# 1. 检查Redis进程
ps aux | grep redis
systemctl status redis

# 2. 检查端口监听
netstat -tulnp | grep 6379
ss -tulnp | grep 6379

# 3. 检查防火墙
iptables -L | grep 6379
firewall-cmd --list-all

# 4. 检查绑定地址
redis-cli CONFIG GET bind
# 如果是127.0.0.1，外部无法访问

# 5. 测试连接
redis-cli -h 127.0.0.1 -p 6379 PING
telnet 127.0.0.1 6379
```

**解决方案**：
```conf
# redis.conf
bind 0.0.0.0  # 允许外部访问
protected-mode no  # 或设置密码

# 重启Redis
systemctl restart redis
```

### 问题2：连接数耗尽

**症状**：
```
Error: max number of clients reached
```

**排查**：
```bash
# 查看当前连接数
redis-cli INFO clients
# connected_clients:1000
# blocked_clients:10

# 查看最大连接数
redis-cli CONFIG GET maxclients
# maxclients: 10000

# 查看客户端列表
redis-cli CLIENT LIST
```

**解决方案**：
```bash
# 临时增加最大连接数
redis-cli CONFIG SET maxclients 20000

# 永久修改
# redis.conf
maxclients 20000

# 杀掉空闲连接
redis-cli CLIENT KILL TYPE normal SKIPME yes
```

**预防**：
```java
// 使用连接池
@Bean
public JedisPool jedisPool() {
    GenericObjectPoolConfig poolConfig = new GenericObjectPoolConfig();
    poolConfig.setMaxTotal(50);  // 最大连接数
    poolConfig.setMaxIdle(20);   // 最大空闲连接
    poolConfig.setMinIdle(5);    // 最小空闲连接
    poolConfig.setMaxWaitMillis(3000);  // 获取连接超时

    return new JedisPool(poolConfig, "localhost", 6379);
}
```

## 2. 性能问题排查

### 问题1：响应慢

**排查**：
```bash
# 1. 查看慢查询
redis-cli SLOWLOG GET 10

# 2. 查看QPS
redis-cli INFO stats | grep instantaneous
# instantaneous_ops_per_sec:10000

# 3. 查看延迟
redis-cli --latency
# min: 0, max: 50, avg: 2.5 (ms)

# 4. 查看命令统计
redis-cli INFO commandstats
```

**定位慢命令**：
```java
@Aspect
@Component
public class RedisPerformanceProfiler {
    @Around("execution(* org.springframework.data.redis.core.RedisTemplate.*(..))")
    public Object profile(ProceedingJoinPoint pjp) throws Throwable {
        String method = pjp.getSignature().getName();
        long start = System.currentTimeMillis();

        try {
            return pjp.proceed();
        } finally {
            long duration = System.currentTimeMillis() - start;
            if (duration > 100) {
                log.warn("慢操作: method={}, args={}, duration={}ms",
                    method, Arrays.toString(pjp.getArgs()), duration);
            }
        }
    }
}
```

**解决方案**：
- KEYS * → SCAN
- SMEMBERS → SSCAN
- HGETALL → HSCAN
- 使用Pipeline批量操作
- 拆分BigKey

### 问题2：突然变慢

**可能原因**：
1. **持久化阻塞**：
```bash
# 查看RDB/AOF状态
redis-cli INFO persistence
# rdb_bgsave_in_progress:1  # 正在BGSAVE

# 解决：优化fork性能
# redis.conf
stop-writes-on-bgsave-error no
```

2. **内存交换**：
```bash
# 查看内存
redis-cli INFO memory | grep used_memory_rss
free -h

# 解决：增加内存或减少数据
```

3. **网络拥塞**：
```bash
# 查看网络流量
iftop
nethogs

# 查看Redis网络统计
redis-cli INFO stats | grep net
```

## 3. 内存问题排查

### 问题1：内存占用过高

**排查**：
```bash
# 1. 内存使用详情
redis-cli INFO memory

# 2. 查找BigKey
redis-cli --bigkeys

# 3. 分析内存占用
redis-cli --memkeys

# 4. 查看key数量
redis-cli DBSIZE
```

**解决方案**：
```java
// 定期清理过期数据
@Scheduled(cron = "0 0 2 * * ?")
public void cleanup() {
    // 清理超过30天的数据
    long threshold = System.currentTimeMillis() - 30L * 24 * 3600 * 1000;
    redis.opsForZSet().removeRangeByScore("timeline", 0, threshold);

    // 清理空Hash
    Set<String> keys = redis.keys("user:*");
    for (String key : keys) {
        Long size = redis.opsForHash().size(key);
        if (size != null && size == 0) {
            redis.delete(key);
        }
    }
}
```

### 问题2：内存碎片率高

**排查**：
```bash
redis-cli INFO memory | grep mem_fragmentation_ratio
# mem_fragmentation_ratio:2.5  # > 1.5需要优化
```

**解决方案**：
```bash
# 方案1：重启Redis（彻底解决）
systemctl restart redis

# 方案2：主动碎片整理（Redis 4.0+）
redis-cli CONFIG SET activedefrag yes

# 方案3：读写分离，轮流重启从节点
```

## 4. 数据问题排查

### 问题1：数据丢失

**可能原因**：
1. **过期删除**：
```bash
# 查看key的TTL
redis-cli TTL mykey
# (integer) -2  # 已过期
```

2. **内存淘汰**：
```bash
# 查看淘汰key数量
redis-cli INFO stats | grep evicted
# evicted_keys:10000

# 查看淘汰策略
redis-cli CONFIG GET maxmemory-policy
```

3. **误删除**：
```bash
# 查看慢查询日志，寻找DEL/FLUSHDB命令
redis-cli SLOWLOG GET 100 | grep -E "DEL|FLUSHDB"
```

4. **主从同步丢失**：
```bash
# 检查主从状态
redis-cli -h slave INFO replication
# master_link_status:down  # 主从断开
```

**解决方案**：
- 开启持久化（RDB + AOF）
- 配置合理的淘汰策略
- 禁用危险命令（FLUSHDB/FLUSHALL）
- 监控主从复制状态

### 问题2：数据不一致

**排查**：
```bash
# 主节点
redis-cli -h master GET key1

# 从节点
redis-cli -h slave GET key1

# 对比结果

# 检查复制延迟
redis-cli -h slave INFO replication | grep master_last_io_seconds_ago
```

**解决方案**：
```bash
# 强制全量同步
redis-cli -h slave REPLICAOF NO ONE
redis-cli -h slave REPLICAOF master-ip master-port
```

## 5. 集群问题排查

### 问题1：节点下线

**排查**：
```bash
# 查看集群状态
redis-cli --cluster check 127.0.0.1:7000

# 查看节点状态
redis-cli CLUSTER NODES

# 查看槽位分配
redis-cli CLUSTER SLOTS
```

**解决方案**：
```bash
# 手动故障转移
redis-cli -h slave-ip CLUSTER FAILOVER

# 移除故障节点
redis-cli --cluster del-node 127.0.0.1:7000 <node-id>
```

### 问题2：槽位迁移失败

**排查**：
```bash
# 查看迁移状态
redis-cli CLUSTER NODES | grep importing
redis-cli CLUSTER NODES | grep migrating

# 查看slot的key
redis-cli --cluster check 127.0.0.1:7000
```

**解决方案**：
```bash
# 修复集群
redis-cli --cluster fix 127.0.0.1:7000

# 手动完成迁移
redis-cli --cluster reshard 127.0.0.1:7000
```

## 常用排查命令

```bash
# 1. 信息查看
redis-cli INFO [section]  # all/server/clients/memory/persistence/stats/replication
redis-cli CONFIG GET *    # 查看所有配置
redis-cli CLIENT LIST     # 客户端列表
redis-cli CLUSTER INFO    # 集群信息

# 2. 性能分析
redis-cli --latency       # 延迟测试
redis-cli --stat          # 实时统计
redis-cli --bigkeys       # BigKey分析
redis-cli SLOWLOG GET 10  # 慢查询
redis-cli MONITOR         # 实时命令监控（慎用）

# 3. 内存分析
redis-cli --memkeys       # 内存分析
redis-cli MEMORY USAGE key  # 单key内存
redis-cli MEMORY DOCTOR   # 内存诊断

# 4. 集群管理
redis-cli --cluster check <host:port>  # 集群检查
redis-cli --cluster fix <host:port>    # 集群修复
redis-cli --cluster rebalance <host:port>  # 槽位均衡
```

## 故障排查清单

### 快速诊断步骤

1. **确认故障现象**：
   - [ ] 无法连接？响应慢？数据丢失？

2. **检查基础信息**：
   - [ ] Redis进程是否运行
   - [ ] 网络是否通畅
   - [ ] 配置是否正确

3. **查看关键指标**：
   - [ ] QPS、延迟、命中率
   - [ ] 内存使用率、碎片率
   - [ ] 连接数、慢查询
   - [ ] 主从复制状态

4. **分析日志**：
   - [ ] Redis日志（redis.log）
   - [ ] 慢查询日志（SLOWLOG）
   - [ ] 应用日志

5. **定位根因**：
   - [ ] 慢命令？BigKey？内存不足？
   - [ ] 网络问题？配置问题？Bug？

6. **实施解决方案**：
   - [ ] 临时解决（重启、扩容）
   - [ ] 根本解决（优化代码、调整配置）

7. **验证效果**：
   - [ ] 故障是否解决
   - [ ] 是否引入新问题

8. **总结复盘**：
   - [ ] 记录故障原因和解决方案
   - [ ] 完善监控和告警
   - [ ] 预防类似问题

## 总结

**核心方法**：
- 从现象到本质
- 使用工具辅助诊断
- 查看日志和监控
- 快速定位根因

**常用工具**：
- redis-cli（INFO/SLOWLOG/CLIENT）
- redis-cli --bigkeys
- redis-cli --latency
- MONITOR（慎用）

**预防措施**：
- 完善监控告警
- 定期巡检
- 压力测试
- 应急预案

**经验总结**：
- 80%问题是配置和代码问题
- 20%是环境和资源问题
- 善用日志和监控
- 积累故障案例库
