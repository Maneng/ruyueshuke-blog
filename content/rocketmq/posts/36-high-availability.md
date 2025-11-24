---
title: "RocketMQ生产06：高可用保障 - 多机房部署与故障演练"
date: 2025-11-15T12:00:00+08:00
draft: false
tags: ["RocketMQ", "高可用", "多机房部署", "故障演练"]
categories: ["技术"]
description: "构建企业级高可用 RocketMQ 集群，实现异地多活和故障自动切换"
series: ["RocketMQ从入门到精通"]
weight: 36
stage: 4
stageTitle: "生产实践篇"
---

## 引言：高可用的重要性

凌晨 3 点，机房断电，整个 RocketMQ 集群瘫痪，所有业务停摆，损失数百万...

**高可用（HA）的目标**：
- ✅ 任意单点故障不影响服务
- ✅ 机房级故障快速切换
- ✅ 数据零丢失或最小丢失
- ✅ RTO（恢复时间）< 5 分钟

**本文目标**：
- 掌握主从架构和 Dledger 架构
- 实现多机房部署方案
- 学会故障演练方法
- 建立完整的容灾体系

---

## 一、高可用架构

### 1.1 单机房主从架构

```
┌─────────────────────────────────────┐
│         机房A（生产机房）            │
│                                     │
│  ┌────────────┐    ┌────────────┐  │
│  │ NameServer │    │ NameServer │  │
│  │    (n1)    │    │    (n2)    │  │
│  └────────────┘    └────────────┘  │
│                                     │
│  ┌────────────┐    ┌────────────┐  │
│  │  Broker-A  │    │  Broker-B  │  │
│  │  (Master)  │    │  (Master)  │  │
│  └──────┬─────┘    └──────┬─────┘  │
│         │                  │        │
│  ┌──────▼─────┐    ┌──────▼─────┐  │
│  │  Broker-A  │    │  Broker-B  │  │
│  │  (Slave)   │    │  (Slave)   │  │
│  └────────────┘    └────────────┘  │
└─────────────────────────────────────┘
```

**特点**：
- ✅ 简单可靠
- ❌ 单机房故障导致服务不可用
- ❌ 需手动主从切换

---

### 1.2 双机房容灾架构

```
┌─────────────────────┐        ┌─────────────────────┐
│      机房A（主）     │        │      机房B（备）     │
│                     │        │                     │
│  ┌───────────────┐  │        │  ┌───────────────┐  │
│  │ NameServer-1  │  │        │  │ NameServer-3  │  │
│  └───────────────┘  │        │  └───────────────┘  │
│                     │        │                     │
│  ┌───────────────┐  │        │  ┌───────────────┐  │
│  │   Broker-A    │  │  同步   │  │   Broker-A    │  │
│  │   (Master)    │◄─┼────────┼─►│   (Slave)     │  │
│  └───────────────┘  │        │  └───────────────┘  │
│                     │        │                     │
│  ┌───────────────┐  │        │  ┌───────────────┐  │
│  │   Broker-B    │  │  同步   │  │   Broker-B    │  │
│  │   (Master)    │◄─┼────────┼─►│   (Slave)     │  │
│  └───────────────┘  │        │  └───────────────┘  │
└─────────────────────┘        └─────────────────────┘
         │                              │
         └──────────── VIP/域名 ─────────┘
```

**特点**：
- ✅ 机房级容灾
- ✅ Slave 可承担读流量
- ❌ 需手动切换
- ❌ 跨机房同步延迟

---

### 1.3 Dledger 自动选主架构

```
┌──────────────────────────────────────────────────┐
│              RocketMQ Dledger 集群                │
│                                                  │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐ │
│  │  Broker-1  │  │  Broker-2  │  │  Broker-3  │ │
│  │  (Leader)  │  │(Follower)  │  │(Follower)  │ │
│  │   机房A    │  │   机房B    │  │   机房C    │ │
│  └──────┬─────┘  └──────┬─────┘  └──────┬─────┘ │
│         └────────────────┼────────────────┘      │
│                   Raft 选主                      │
└──────────────────────────────────────────────────┘

Leader 故障 → 自动选举新 Leader（< 30秒）
```

**特点**：
- ✅ 自动故障切换
- ✅ 无需人工介入
- ✅ 强一致性保证
- ❌ 至少 3 个节点
- ❌ 跨机房延迟影响性能

---

## 二、多机房部署实战

### 2.1 双机房主从部署

#### 架构设计

```
机房A（主）：
- NameServer-1：192.168.1.100:9876
- NameServer-2：192.168.1.101:9876
- Broker-A-Master：192.168.1.110:10911
- Broker-B-Master：192.168.1.111:10911

机房B（备）：
- NameServer-3：192.168.2.100:9876
- Broker-A-Slave：192.168.2.110:10911
- Broker-B-Slave：192.168.2.111:10911
```

#### 配置示例

**机房A - Broker-A-Master**：
```properties
# broker-a-master.conf
brokerClusterName=DefaultCluster
brokerName=broker-a
brokerId=0
brokerRole=SYNC_MASTER          # 同步复制
flushDiskType=ASYNC_FLUSH
namesrvAddr=192.168.1.100:9876;192.168.1.101:9876;192.168.2.100:9876

# 主从同步
haService.listenPort=10912
haSendHeartbeatInterval=5000
```

**机房B - Broker-A-Slave**：
```properties
# broker-a-slave.conf
brokerClusterName=DefaultCluster
brokerName=broker-a
brokerId=1                      # Slave ID > 0
brokerRole=SLAVE
flushDiskType=ASYNC_FLUSH
namesrvAddr=192.168.1.100:9876;192.168.1.101:9876;192.168.2.100:9876

# 主从同步
haService.listenPort=10912
```

---

### 2.2 Dledger 三机房部署

#### 配置示例

**Broker-1（机房A）**：
```properties
# broker-dledger-1.conf
brokerClusterName=DefaultCluster
brokerName=broker-a
namesrvAddr=192.168.1.100:9876;192.168.2.100:9876;192.168.3.100:9876

# 启用 Dledger
enableDLegerCommitLog=true
dLegerGroup=broker-a
dLegerPeers=n0-192.168.1.110:40911;n1-192.168.2.110:40911;n2-192.168.3.110:40911
dLegerSelfId=n0
sendMessageThreadPoolNums=4
```

**Broker-2（机房B）**：
```properties
# broker-dledger-2.conf
brokerClusterName=DefaultCluster
brokerName=broker-a
namesrvAddr=192.168.1.100:9876;192.168.2.100:9876;192.168.3.100:9876

enableDLegerCommitLog=true
dLegerGroup=broker-a
dLegerPeers=n0-192.168.1.110:40911;n1-192.168.2.110:40911;n2-192.168.3.110:40911
dLegerSelfId=n1
sendMessageThreadPoolNums=4
```

**Broker-3（机房C）**：
```properties
# broker-dledger-3.conf
brokerClusterName=DefaultCluster
brokerName=broker-a
namesrvAddr=192.168.1.100:9876;192.168.2.100:9876;192.168.3.100:9876

enableDLegerCommitLog=true
dLegerGroup=broker-a
dLegerPeers=n0-192.168.1.110:40911;n1-192.168.2.110:40911;n2-192.168.3.110:40911
dLegerSelfId=n2
sendMessageThreadPoolNums=4
```

---

## 三、故障演练

### 3.1 演练目标

```
1. 验证高可用配置是否生效
2. 测量故障恢复时间（RTO）
3. 验证数据丢失情况（RPO）
4. 锻炼运维团队应急能力
```

---

### 3.2 演练场景

#### 场景1：单个 Broker Master 故障

**演练步骤**：
```bash
# 1. 记录当前状态
sh mqadmin clusterList -n 127.0.0.1:9876 > before_failure.txt

# 2. 模拟 Master 故障（强制杀进程）
ssh 192.168.1.110 "kill -9 $(pgrep -f BrokerStartup)"

# 3. 观察 Slave 接管情况
watch -n 1 "sh mqadmin clusterList -n 127.0.0.1:9876"

# 4. 记录恢复时间
# 期望：Slave 在 30 秒内开始提供消费服务

# 5. 验证消息是否丢失
sh mqadmin consumerProgress -g test_consumer_group -n 127.0.0.1:9876

# 6. 恢复 Master
ssh 192.168.1.110 "cd /opt/rocketmq && sh bin/mqbroker -c conf/broker-a-master.conf &"

# 7. 验证主从同步恢复
sh mqadmin brokerStatus -n 127.168.1:9876 -b 192.168.1.110:10911
```

**期望结果**：
- ✅ Slave 自动提供消费服务
- ✅ Producer 可继续发送（发往其他 Broker）
- ✅ 消息零丢失（同步复制）
- ✅ RTO < 30 秒

---

#### 场景2：机房级故障（断网）

**演练步骤**：
```bash
# 1. 记录当前状态
sh mqadmin clusterList -n 127.0.0.1:9876 > before_datacenter_failure.txt

# 2. 模拟机房A断网（防火墙规则）
ssh 192.168.1.1 "iptables -A INPUT -s 192.168.2.0/24 -j DROP"
ssh 192.168.1.1 "iptables -A OUTPUT -d 192.168.2.0/24 -j DROP"

# 3. 观察机房B Slave 状态
ssh 192.168.2.110 "tail -f /opt/rocketmq/logs/rocketmqlogs/broker.log"

# 4. 手动提升 Slave 为 Master（主从模式）
ssh 192.168.2.110 "sh /opt/rocketmq/bin/mqadmin updateBrokerConfig -b 192.168.2.110:10911 -k brokerRole -v ASYNC_MASTER"

# 5. 验证服务恢复
sh mqadmin topicStatus -n 192.168.2.100:9876 -t test_topic

# 6. 恢复网络
ssh 192.168.1.1 "iptables -F"

# 7. 恢复主从关系
# 将机房A的 Master 降级为 Slave，机房B 继续为 Master
# 或重新规划主从关系
```

**期望结果**：
- ✅ 机房B 的 Slave 可手动提升为 Master
- ✅ 服务恢复时间 < 5 分钟
- ✅ 数据丢失量 < 1000 条（取决于同步延迟）

---

#### 场景3：Dledger 自动选主

**演练步骤**：
```bash
# 1. 查看当前 Leader
sh mqadmin clusterList -n 127.0.0.1:9876 | grep -A 10 "broker-a"

# 2. 模拟 Leader 故障
# 假设 n0 是 Leader
ssh 192.168.1.110 "kill -9 $(pgrep -f BrokerStartup)"

# 3. 观察自动选主过程
watch -n 1 "sh mqadmin clusterList -n 127.0.0.1:9876 | grep -A 10 broker-a"

# 4. 记录选主耗时
# 期望：< 30 秒完成新 Leader 选举

# 5. 验证消息收发
# Producer 发送
sh mqadmin sendMessage -n 127.0.0.1:9876 -t test_topic -p "test message after leader election"

# Consumer 消费
sh mqadmin consumeMessage -n 127.0.0.1:9876 -t test_topic -g test_group

# 6. 恢复故障节点
ssh 192.168.1.110 "cd /opt/rocketmq && sh bin/mqbroker -c conf/broker-dledger-1.conf &"

# 7. 验证重新加入集群
sh mqadmin clusterList -n 127.0.0.1:9876
```

**期望结果**：
- ✅ 自动选举新 Leader（< 30 秒）
- ✅ 消息零丢失
- ✅ 无需人工介入

---

### 3.3 演练检查清单

**演练前**：
- [ ] 确认演练时间（避开业务高峰）
- [ ] 通知相关团队
- [ ] 准备回滚方案
- [ ] 备份关键数据
- [ ] 检查监控告警是否正常

**演练中**：
- [ ] 记录每个步骤的时间戳
- [ ] 截图关键日志和监控
- [ ] 观察业务影响范围
- [ ] 验证告警是否及时触发

**演练后**：
- [ ] 对比数据一致性
- [ ] 分析故障恢复时间
- [ ] 总结问题点
- [ ] 更新应急预案
- [ ] 组织复盘会议

---

## 四、容灾切换方案

### 4.1 主从手动切换

**切换脚本**：
```bash
#!/bin/bash
# failover.sh - 主从手动切换脚本

OLD_MASTER="192.168.1.110:10911"
NEW_MASTER="192.168.2.110:10911"

echo "===== 开始主从切换 ====="

# 1. 停止旧 Master 写入（可选）
echo "1. 禁用旧 Master 写入..."
sh mqadmin wipeWritePerm -n 127.0.0.1:9876 -b $OLD_MASTER

# 2. 等待主从同步完成
echo "2. 等待主从同步..."
sleep 10

# 3. 提升 Slave 为 Master
echo "3. 提升 Slave 为 Master..."
sh mqadmin updateBrokerConfig \
  -n 127.0.0.1:9876 \
  -b $NEW_MASTER \
  -k brokerRole \
  -v ASYNC_MASTER

# 4. 重启新 Master 使配置生效
echo "4. 重启新 Master..."
ssh 192.168.2.110 "sh /opt/rocketmq/bin/mqshutdown broker && sleep 5 && sh /opt/rocketmq/bin/mqbroker -c /opt/rocketmq/conf/broker-a-master.conf &"

# 5. 验证新 Master 状态
echo "5. 验证新 Master..."
sh mqadmin clusterList -n 127.0.0.1:9876 | grep $NEW_MASTER

echo "===== 切换完成 ====="
```

---

### 4.2 DNS/VIP 切换

**架构**：
```
┌─────────┐
│  Client │
└────┬────┘
     │ 访问域名: rocketmq.example.com
     │
┌────▼────────────────────────┐
│  DNS / 负载均衡器 (VIP)     │
│  域名: rocketmq.example.com │
└────┬────────────────────────┘
     │
     ├────> 机房A: 192.168.1.100:9876  (主)
     │
     └────> 机房B: 192.168.2.100:9876  (备)
```

**切换步骤**：
```bash
# 1. 修改 DNS 记录
# 将 rocketmq.example.com 从 192.168.1.100 改为 192.168.2.100

# 2. 等待 DNS 生效
# TTL 时间（如 60 秒）

# 3. 验证解析
nslookup rocketmq.example.com

# 4. 客户端重连
# 客户端自动使用新地址
```

---

## 五、数据备份与恢复

### 5.1 数据备份

```bash
#!/bin/bash
# backup_rocketmq.sh - 数据备份脚本

BACKUP_DIR="/backup/rocketmq/$(date +%Y%m%d_%H%M%S)"
mkdir -p $BACKUP_DIR

echo "===== 开始备份 ====="

# 1. 备份配置文件
echo "1. 备份配置..."
cp -r /opt/rocketmq/conf $BACKUP_DIR/

# 2. 备份消息存储
echo "2. 备份消息存储..."
rsync -av --progress /data/rocketmq/store $BACKUP_DIR/

# 3. 备份元数据
echo "3. 备份元数据..."
sh mqadmin clusterList -n 127.0.0.1:9876 > $BACKUP_DIR/cluster_info.txt
sh mqadmin topicList -n 127.0.0.1:9876 > $BACKUP_DIR/topic_list.txt

# 4. 压缩备份文件
echo "4. 压缩备份..."
tar -czf $BACKUP_DIR.tar.gz -C /backup/rocketmq $(basename $BACKUP_DIR)

# 5. 上传到远程存储（可选）
# aws s3 cp $BACKUP_DIR.tar.gz s3://my-bucket/rocketmq/

echo "===== 备份完成 ====="
echo "备份文件: $BACKUP_DIR.tar.gz"
```

---

### 5.2 数据恢复

```bash
#!/bin/bash
# restore_rocketmq.sh - 数据恢复脚本

BACKUP_FILE="/backup/rocketmq/20251115_020000.tar.gz"

echo "===== 开始恢复 ====="

# 1. 停止 RocketMQ
echo "1. 停止 RocketMQ..."
sh /opt/rocketmq/bin/mqshutdown broker
sh /opt/rocketmq/bin/mqshutdown namesrv

# 2. 解压备份文件
echo "2. 解压备份..."
tar -xzf $BACKUP_FILE -C /tmp/

# 3. 恢复配置文件
echo "3. 恢复配置..."
cp -r /tmp/20251115_020000/conf/* /opt/rocketmq/conf/

# 4. 恢复消息存储
echo "4. 恢复消息存储..."
rm -rf /data/rocketmq/store/*
cp -r /tmp/20251115_020000/store/* /data/rocketmq/store/

# 5. 启动 RocketMQ
echo "5. 启动 RocketMQ..."
sh /opt/rocketmq/bin/mqnamesrv &
sleep 5
sh /opt/rocketmq/bin/mqbroker -c /opt/rocketmq/conf/broker.conf &

# 6. 验证恢复
echo "6. 验证恢复..."
sh mqadmin clusterList -n 127.0.0.1:9876

echo "===== 恢复完成 ====="
```

---

## 六、监控与告警

### 6.1 关键告警规则

```yaml
# prometheus/alert_rules.yml
groups:
  - name: rocketmq_ha
    rules:
      # 1. Broker 不可用
      - alert: BrokerDown
        expr: up{job="rocketmq"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Broker 宕机"
          description: "Broker {{ $labels.instance }} 不可用"

      # 2. 主从同步延迟过高
      - alert: SlaveReplicationLag
        expr: rocketmq_slave_replication_lag > 1000000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "主从同步延迟过高"
          description: "Slave {{ $labels.instance }} 同步延迟 {{ $value }}"

      # 3. Dledger 集群无 Leader
      - alert: DledgerNoLeader
        expr: rocketmq_dledger_leader_election_time > 60
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Dledger 选主超时"
          description: "集群 {{ $labels.cluster }} 超过 60 秒未选出 Leader"
```

---

## 七、总结

### 高可用架构选择

| 场景 | 推荐架构 | RTO | RPO |
|------|---------|-----|-----|
| 单机房 | 2M-2S | 30秒 | 0 |
| 双机房 | 2M-2S + 手动切换 | 5分钟 | < 1000条 |
| 三机房 | Dledger 3节点 | 30秒 | 0 |
| 异地多活 | Dledger 5节点 | 30秒 | 0 |

### 容灾演练频率

```
- 故障切换演练：每季度 1 次
- 数据恢复演练：每半年 1 次
- 全链路演练：每年 1 次
```

### 高可用检查清单

- [ ] 主从同步配置为 SYNC_MASTER
- [ ] 刷盘策略配置为 SYNC_FLUSH（核心业务）
- [ ] 部署至少 2 个机房
- [ ] 配置主从自动切换或定期演练手动切换
- [ ] 建立监控告警体系
- [ ] 定期备份数据和配置
- [ ] 编写应急预案
- [ ] 定期组织故障演练

---

**下一篇预告**：《安全机制配置 - ACL 权限控制实战》，我们将讲解如何为 RocketMQ 配置访问控制，保障集群安全。

**本文关键词**：`高可用` `多机房部署` `故障演练` `容灾切换`
