---
title: "RocketMQ生产08：版本升级策略 - 平滑迁移与回滚方案"
date: 2025-11-15T14:00:00+08:00
draft: false
tags: ["RocketMQ", "版本升级", "平滑迁移", "回滚"]
categories: ["技术"]
description: "掌握 RocketMQ 版本升级的核心方法，实现零停机升级和快速回滚"
series: ["RocketMQ从入门到精通"]
weight: 38
stage: 4
stageTitle: "生产实践篇"
---

## 引言：升级的挑战

生产环境 RocketMQ 4.5 升级到 5.0，结果消息格式不兼容，业务大面积报错，紧急回滚...

**升级风险**：
- ❌ 新旧版本不兼容
- ❌ 升级过程业务中断
- ❌ 数据格式变更导致丢消息
- ❌ 回滚困难，恢复时间长

**本文目标**：
- ✅ 理解版本升级的风险点
- ✅ 掌握平滑升级方法
- ✅ 实现零停机升级
- ✅ 建立快速回滚机制

---

## 一、版本兼容性分析

### 1.1 RocketMQ 版本演进

| 版本 | 发布时间 | 重大变更 | 兼容性 |
|------|---------|---------|--------|
| **4.5.x** | 2019 | 事务消息优化 | ✅ 向下兼容 |
| **4.7.x** | 2020 | Dledger 主从切换 | ✅ 向下兼容 |
| **4.9.x** | 2021 | 性能优化、ACL增强 | ✅ 向下兼容 |
| **5.0.x** | 2022 | Pop消费模式、轻量级客户端 | ⚠️ 部分不兼容 |
| **5.1.x** | 2023 | Proxy模式、gRPC协议 | ⚠️ 新架构 |

---

### 1.2 兼容性检查清单

**升级前必查**：
- [ ] 查看官方 Release Notes
- [ ] 检查 API 是否有破坏性变更
- [ ] 验证客户端版本兼容性
- [ ] 确认配置文件格式是否变化
- [ ] 检查数据存储格式是否兼容

**官方文档**：
```
Release Notes: https://github.com/apache/rocketmq/releases
升级指南: https://rocketmq.apache.org/docs/upgrade/
```

---

## 二、升级策略

### 2.1 滚动升级（推荐）

**原理**：逐台升级 Broker，保证集群始终可用。

```
┌───────────────────────────────────────────────────┐
│  升级流程（2M-2S 集群）                            │
│                                                   │
│  阶段1：升级 Broker-A-Slave                       │
│  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐          │
│  │ A-M  │  │ A-S  │  │ B-M  │  │ B-S  │          │
│  │ v4.9 │  │ v4.9 │  │ v4.9 │  │ v4.9 │          │
│  └──────┘  └──┬───┘  └──────┘  └──────┘          │
│               │ 停止 → 升级 → 启动                │
│  ┌──────┐  ┌──▼───┐  ┌──────┐  ┌──────┐          │
│  │ A-M  │  │ A-S  │  │ B-M  │  │ B-S  │          │
│  │ v4.9 │  │ v5.0 │  │ v4.9 │  │ v4.9 │  ✅      │
│  └──────┘  └──────┘  └──────┘  └──────┘          │
│                                                   │
│  阶段2：升级 Broker-B-Slave                       │
│  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐          │
│  │ A-M  │  │ A-S  │  │ B-M  │  │ B-S  │          │
│  │ v4.9 │  │ v5.0 │  │ v4.9 │  │ v4.9 │          │
│  └──────┘  └──────┘  └──────┘  └──┬───┘          │
│                                   │ 停止 → 升级   │
│  ┌──────┐  ┌──────┐  ┌──────┐  ┌──▼───┐          │
│  │ A-M  │  │ A-S  │  │ B-M  │  │ B-S  │          │
│  │ v4.9 │  │ v5.0 │  │ v4.9 │  │ v5.0 │  ✅      │
│  └──────┘  └──────┘  └──────┘  └──────┘          │
│                                                   │
│  阶段3：升级 Broker-A-Master                      │
│  阶段4：升级 Broker-B-Master                      │
│                                                   │
│  最终状态：                                        │
│  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐          │
│  │ A-M  │  │ A-S  │  │ B-M  │  │ B-S  │          │
│  │ v5.0 │  │ v5.0 │  │ v5.0 │  │ v5.0 │  ✅      │
│  └──────┘  └──────┘  └──────┘  └──────┘          │
└───────────────────────────────────────────────────┘
```

**优点**：
- ✅ 业务零中断
- ✅ 可随时暂停升级
- ✅ 风险可控

**缺点**：
- ❌ 升级耗时较长
- ❌ 需逐台操作

---

### 2.2 蓝绿部署

**原理**：部署新版本集群（绿），流量切换后下线旧集群（蓝）。

```
┌──────────────────────────┐      ┌──────────────────────────┐
│      蓝环境（旧版本）      │      │      绿环境（新版本）      │
│    RocketMQ 4.9.x        │      │    RocketMQ 5.0.x        │
│                          │      │                          │
│  ┌────┐  ┌────┐  ┌────┐  │      │  ┌────┐  ┌────┐  ┌────┐  │
│  │B-A │  │B-B │  │B-C │  │      │  │B-A │  │B-B │  │B-C │  │
│  └────┘  └────┘  └────┘  │      │  └────┘  └────┘  └────┘  │
└───────┬──────────────────┘      └──────────┬───────────────┘
        │                                    │
        │ 流量100%                            │ 流量0%
        │                                    │
    ┌───▼────────┐                       ┌───▼────────┐
    │  Producer  │                       │  Producer  │
    │  Consumer  │                       │  Consumer  │
    └────────────┘                       └────────────┘

              ↓ 切换流量 ↓

┌──────────────────────────┐      ┌──────────────────────────┐
│      蓝环境（下线）        │      │      绿环境（生产）        │
│                          │      │                          │
└──────────────────────────┘      └──────────┬───────────────┘
                                             │ 流量100%
                                         ┌───▼────────┐
                                         │  Producer  │
                                         │  Consumer  │
                                         └────────────┘
```

**优点**：
- ✅ 快速回滚（切换流量）
- ✅ 充分测试新版本
- ✅ 风险最低

**缺点**：
- ❌ 资源成本高（双倍机器）
- ❌ 需要流量切换机制

---

### 2.3 灰度升级

**原理**：部分流量先接入新版本，逐步扩大比例。

```
阶段1：10% 流量 → RocketMQ 5.0
阶段2：30% 流量 → RocketMQ 5.0
阶段3：50% 流量 → RocketMQ 5.0
阶段4：100% 流量 → RocketMQ 5.0（下线旧版本）
```

**适用场景**：
- 大规模集群升级
- 对稳定性要求极高
- 有精细的流量控制能力

---

## 三、升级实战

### 3.1 升级前准备

#### 3.1.1 备份数据

```bash
#!/bin/bash
# backup_before_upgrade.sh - 升级前备份脚本

BACKUP_DIR="/backup/rocketmq/upgrade_$(date +%Y%m%d_%H%M%S)"
mkdir -p $BACKUP_DIR

echo "===== 开始备份 ====="

# 1. 备份配置文件
echo "1. 备份配置..."
cp -r /opt/rocketmq/conf $BACKUP_DIR/

# 2. 备份消息存储（可选，数据量大时跳过）
echo "2. 备份消息存储..."
# rsync -av /data/rocketmq/store $BACKUP_DIR/

# 3. 导出集群元数据
echo "3. 导出元数据..."
sh mqadmin clusterList -n 127.0.0.1:9876 > $BACKUP_DIR/cluster_info.txt
sh mqadmin topicList -n 127.0.0.1:9876 > $BACKUP_DIR/topic_list.txt
sh mqadmin consumerProgress -n 127.0.0.1:9876 > $BACKUP_DIR/consumer_progress.txt

echo "===== 备份完成 ====="
echo "备份目录: $BACKUP_DIR"
```

---

#### 3.1.2 压测验证

```bash
# 1. 记录当前性能基线
sh mqadmin statsAll -n 127.0.0.1:9876 > baseline_stats.txt

# 2. 压测工具验证
sh benchmark.sh Producer \
  -n 127.0.0.1:9876 \
  -t test_topic \
  -s 1024 \
  -c 10 \
  -w 100

# 3. 记录 TPS、延迟等指标
```

---

### 3.2 滚动升级步骤

#### 步骤 1：升级 Slave

```bash
#!/bin/bash
# upgrade_slave.sh - 升级 Slave Broker

BROKER_HOST="192.168.1.111"
BROKER_PORT="10911"
NEW_VERSION="rocketmq-5.0.0"

echo "===== 开始升级 Slave Broker: $BROKER_HOST ====="

# 1. 下载新版本（提前下载到所有机器）
echo "1. 下载新版本..."
ssh $BROKER_HOST "cd /opt && wget https://dist.apache.org/repos/dist/release/rocketmq/5.0.0/${NEW_VERSION}-bin.tar.gz"
ssh $BROKER_HOST "cd /opt && tar -xzf ${NEW_VERSION}-bin.tar.gz"

# 2. 停止 Slave Broker
echo "2. 停止 Slave Broker..."
ssh $BROKER_HOST "sh /opt/rocketmq/bin/mqshutdown broker"

# 3. 备份旧版本
echo "3. 备份旧版本..."
ssh $BROKER_HOST "mv /opt/rocketmq /opt/rocketmq-4.9-backup"

# 4. 软链接到新版本
echo "4. 切换到新版本..."
ssh $BROKER_HOST "ln -s /opt/${NEW_VERSION} /opt/rocketmq"

# 5. 复制配置文件
echo "5. 复制配置文件..."
ssh $BROKER_HOST "cp /opt/rocketmq-4.9-backup/conf/broker.conf /opt/rocketmq/conf/"

# 6. 启动新版本 Slave
echo "6. 启动新版本 Slave..."
ssh $BROKER_HOST "cd /opt/rocketmq && sh bin/mqbroker -c conf/broker.conf &"

# 7. 验证启动成功
echo "7. 验证 Slave 启动..."
sleep 10
sh mqadmin clusterList -n 127.0.0.1:9876 | grep $BROKER_HOST

# 8. 检查主从同步
echo "8. 检查主从同步..."
sh mqadmin brokerStatus -n 127.0.0.1:9876 -b ${BROKER_HOST}:${BROKER_PORT}

echo "===== Slave 升级完成 ====="
```

---

#### 步骤 2：升级 Master（关键）

```bash
#!/bin/bash
# upgrade_master.sh - 升级 Master Broker

MASTER_HOST="192.168.1.110"
SLAVE_HOST="192.168.1.111"
NEW_VERSION="rocketmq-5.0.0"

echo "===== 开始升级 Master Broker: $MASTER_HOST ====="

# 1. 禁止 Master 写入（可选，减少数据同步压力）
echo "1. 禁止 Master 写入..."
sh mqadmin wipeWritePerm -n 127.0.0.1:9876 -b ${MASTER_HOST}:10911

# 2. 等待消息消费完成
echo "2. 等待消息消费..."
sleep 30

# 3. 检查消费进度
echo "3. 检查消费进度..."
sh mqadmin consumerProgress -n 127.0.0.1:9876

# 4. 停止 Master
echo "4. 停止 Master..."
ssh $MASTER_HOST "sh /opt/rocketmq/bin/mqshutdown broker"

# 5. 备份旧版本
echo "5. 备份旧版本..."
ssh $MASTER_HOST "mv /opt/rocketmq /opt/rocketmq-4.9-backup"

# 6. 切换到新版本
echo "6. 切换到新版本..."
ssh $MASTER_HOST "ln -s /opt/${NEW_VERSION} /opt/rocketmq"
ssh $MASTER_HOST "cp /opt/rocketmq-4.9-backup/conf/broker.conf /opt/rocketmq/conf/"

# 7. 启动新版本 Master
echo "7. 启动新版本 Master..."
ssh $MASTER_HOST "cd /opt/rocketmq && sh bin/mqbroker -c conf/broker.conf &"

# 8. 验证启动
echo "8. 验证 Master 启动..."
sleep 10
sh mqadmin clusterList -n 127.0.0.1:9876 | grep $MASTER_HOST

# 9. 恢复写入权限
echo "9. 恢复写入权限..."
sh mqadmin addWritePerm -n 127.0.0.1:9876 -b ${MASTER_HOST}:10911

# 10. 验证消息收发
echo "10. 验证消息收发..."
sh mqadmin sendMessage -n 127.0.0.1:9876 -t test_topic -p "upgrade test"

echo "===== Master 升级完成 ====="
```

---

### 3.3 升级后验证

```bash
#!/bin/bash
# verify_upgrade.sh - 升级后验证脚本

echo "===== 开始验证升级 ====="

# 1. 检查集群状态
echo "1. 检查集群状态..."
sh mqadmin clusterList -n 127.0.0.1:9876

# 2. 验证版本号
echo "2. 验证版本号..."
sh mqadmin brokerStatus -n 127.0.0.1:9876 -b 192.168.1.110:10911 | grep "brokerVersion"

# 3. 检查主从同步
echo "3. 检查主从同步..."
sh mqadmin brokerStatus -n 127.0.0.1:9876 -b 192.168.1.110:10911 | grep "slaveAckOffset"

# 4. 验证消息发送
echo "4. 验证消息发送..."
sh mqadmin sendMessage -n 127.0.0.1:9876 -t test_topic -p "post-upgrade test"

# 5. 验证消息消费
echo "5. 验证消息消费..."
sh mqadmin consumerProgress -n 127.0.0.1:9876

# 6. 检查监控指标
echo "6. 检查监控指标..."
curl -s "http://prometheus:9090/api/v1/query?query=rocketmq_broker_tps" | jq .

# 7. 对比性能（与 baseline_stats.txt 对比）
echo "7. 对比性能..."
sh mqadmin statsAll -n 127.0.0.1:9876 > after_upgrade_stats.txt
diff baseline_stats.txt after_upgrade_stats.txt

echo "===== 验证完成 ====="
```

---

## 四、回滚方案

### 4.1 快速回滚

**场景**：升级后发现严重问题，需紧急回滚

```bash
#!/bin/bash
# rollback.sh - 紧急回滚脚本

BROKER_HOST="192.168.1.110"

echo "===== 开始回滚 Broker: $BROKER_HOST ====="

# 1. 停止新版本 Broker
echo "1. 停止新版本 Broker..."
ssh $BROKER_HOST "sh /opt/rocketmq/bin/mqshutdown broker"

# 2. 切换回旧版本
echo "2. 切换回旧版本..."
ssh $BROKER_HOST "rm /opt/rocketmq"
ssh $BROKER_HOST "mv /opt/rocketmq-4.9-backup /opt/rocketmq"

# 3. 启动旧版本
echo "3. 启动旧版本..."
ssh $BROKER_HOST "cd /opt/rocketmq && sh bin/mqbroker -c conf/broker.conf &"

# 4. 验证回滚
echo "4. 验证回滚..."
sleep 10
sh mqadmin clusterList -n 127.0.0.1:9876 | grep $BROKER_HOST

echo "===== 回滚完成 ====="
```

**回滚耗时**：< 5 分钟

---

### 4.2 数据恢复

**场景**：新版本导致数据损坏，需恢复备份

```bash
#!/bin/bash
# restore_from_backup.sh - 从备份恢复

BACKUP_DIR="/backup/rocketmq/upgrade_20251115_100000"

echo "===== 开始从备份恢复 ====="

# 1. 停止 Broker
sh /opt/rocketmq/bin/mqshutdown broker

# 2. 恢复配置文件
cp -r $BACKUP_DIR/conf/* /opt/rocketmq/conf/

# 3. 恢复消息存储（如果有备份）
# cp -r $BACKUP_DIR/store/* /data/rocketmq/store/

# 4. 启动 Broker
sh /opt/rocketmq/bin/mqbroker -c /opt/rocketmq/conf/broker.conf &

echo "===== 恢复完成 ====="
```

---

## 五、客户端升级

### 5.1 客户端兼容性

| Broker 版本 | 客户端版本 | 兼容性 |
|------------|-----------|--------|
| 4.9.x | 4.x 客户端 | ✅ 完全兼容 |
| 5.0.x | 4.x 客户端 | ✅ 向下兼容 |
| 5.0.x | 5.x 客户端 | ✅ 推荐使用 |

**建议**：
- Broker 升级后，客户端可逐步升级
- 使用新特性时，才需升级客户端

---

### 5.2 客户端升级步骤

**Maven 依赖升级**：
```xml
<!-- 旧版本 -->
<dependency>
    <groupId>org.apache.rocketmq</groupId>
    <artifactId>rocketmq-client</artifactId>
    <version>4.9.4</version>
</dependency>

<!-- 新版本 -->
<dependency>
    <groupId>org.apache.rocketmq</groupId>
    <artifactId>rocketmq-client</artifactId>
    <version>5.0.0</version>
</dependency>
```

**灰度发布**：
```
1. 20% 实例升级客户端
2. 观察 24 小时，无异常
3. 50% 实例升级
4. 观察 24 小时，无异常
5. 100% 升级完成
```

---

## 六、常见问题

### Q1：升级过程中消息会丢失吗？

**答**：
- **Slave 升级**：不会丢消息（Master 继续服务）
- **Master 升级**：
  - 同步复制 + 同步刷盘：不丢消息
  - 异步复制 + 异步刷盘：可能丢少量消息（内存中未刷盘的）

---

### Q2：升级顺序有要求吗？

**推荐顺序**：
```
1. NameServer（全部升级）
2. Broker Slave（逐台升级）
3. Broker Master（逐台升级）
4. 客户端（灰度升级）
```

**原因**：NameServer 无状态，可随时升级；Slave 升级对业务影响最小。

---

### Q3：如何判断升级是否成功？

**验证指标**：
- ✅ 集群状态正常（`clusterList`）
- ✅ 主从同步正常（`slaveAckOffset` 接近 `masterPutWhere`）
- ✅ 消息正常收发
- ✅ 消费进度正常
- ✅ TPS、延迟无异常波动

---

## 七、总结

### 升级检查清单

**升级前**：
- [ ] 阅读 Release Notes
- [ ] 备份配置和数据
- [ ] 验证兼容性
- [ ] 压测性能基线
- [ ] 准备回滚方案
- [ ] 通知相关团队

**升级中**：
- [ ] 按顺序升级（NameServer → Slave → Master）
- [ ] 每台升级后验证
- [ ] 记录升级日志
- [ ] 监控关键指标

**升级后**：
- [ ] 验证集群状态
- [ ] 验证消息收发
- [ ] 对比性能指标
- [ ] 保留旧版本备份 7 天
- [ ] 更新运维文档

### 升级策略选择

| 场景 | 推荐策略 | 停机时间 |
|------|---------|---------|
| 小型集群 | 滚动升级 | 0 |
| 大型集群 | 蓝绿部署 | 0 |
| 核心业务 | 灰度升级 | 0 |
| 测试环境 | 直接升级 | 可接受 |

### 核心原则

```
1. 充分准备，多次演练
2. 逐步升级，及时验证
3. 保留后路，随时回滚
4. 监控先行，异常秒发现
5. 文档完善，经验沉淀
```

---

**🎉 恭喜！生产实践篇全部完成！**

已完成：
- ✅ 生产部署方案（31）
- ✅ 监控体系搭建（32）
- ✅ 性能调优指南（33）
- ✅ 消息丢失排查（34）
- ✅ 消息重复处理（35）
- ✅ 高可用保障（36）
- ✅ 安全机制配置（37）
- ✅ 版本升级策略（38）

**下一阶段预告**：第五阶段「云原生演进篇」，探索 RocketMQ 在 Kubernetes、Serverless 等云原生场景的应用。

**本文关键词**：`版本升级` `滚动升级` `蓝绿部署` `回滚方案`
