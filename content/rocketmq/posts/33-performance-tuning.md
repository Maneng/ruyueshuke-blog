---
title: "RocketMQ生产03：性能调优指南 - JVM、OS、Broker 参数优化"
date: 2025-11-15T09:00:00+08:00
draft: false
tags: ["RocketMQ", "性能调优", "JVM优化", "参数优化"]
categories: ["技术"]
description: "深入讲解 RocketMQ 性能调优的核心方法，榨干硬件性能极限"
series: ["RocketMQ从入门到精通"]
weight: 33
stage: 4
stageTitle: "生产实践篇"
---

## 引言：性能优化的本质

上线前压测：TPS 轻松 5 万，延迟 5ms 以内。生产环境一跑：TPS 破千就开始 Full GC，延迟飙到 500ms，系统濒临崩溃...

**性能问题的常见表现**：
- ❌ TPS 上不去，CPU 使用率却不高
- ❌ 频繁 Full GC，Stop-The-World 时间长
- ❌ 消息发送延迟高，P99 延迟上秒
- ❌ 磁盘 I/O 成瓶颈，写入速度慢

**本文目标**：
- ✅ 掌握 JVM 参数调优方法
- ✅ 理解操作系统层面优化
- ✅ 优化 Broker 核心参数
- ✅ 建立性能调优思维模型

---

## 一、性能调优方法论

### 1.1 调优三板斧

```
1. 测量（Measure）  → 建立性能基线
2. 分析（Analyze）  → 定位性能瓶颈
3. 优化（Optimize） → 针对性调优
```

**切忌盲目调优**：
- ❌ 看到别人的配置就直接copy
- ❌ 不测量就调参，凭感觉优化
- ❌ 多个参数同时修改，无法定位效果

**正确姿势**：
- ✅ 建立性能基线（压测记录初始状态）
- ✅ 单一变量法（一次只改一个参数）
- ✅ 量化效果（对比优化前后的指标）

---

### 1.2 性能指标体系

| 维度 | 核心指标 | 目标值 | 采集方式 |
|------|---------|-------|---------|
| **吞吐量** | TPS（消息/秒） | 根据业务需求 | Prometheus |
| **延迟** | P99 延迟（ms） | < 50ms | 客户端埋点 |
| **资源** | CPU 使用率 | < 70% | `top` |
| **资源** | 内存使用率 | < 80% | `free -h` |
| **资源** | 磁盘 I/O 等待 | < 10% | `iostat` |
| **稳定性** | GC 频率 | YGC < 1次/秒 | `jstat` |
| **稳定性** | Full GC 间隔 | > 1小时 | `jstat` |

---

## 二、JVM 参数调优

### 2.1 内存配置

#### 2.1.1 堆内存大小

**推荐配置**：
```bash
# 小型集群（TPS < 5000）
-Xms8g -Xmx8g -Xmn4g

# 中型集群（TPS 5000-20000）
-Xms16g -Xmx16g -Xmn8g

# 大型集群（TPS > 20000）
-Xms32g -Xmx32g -Xmn16g
```

**核心原则**：
1. **-Xms 和 -Xmx 设置相同**：避免运行时扩容，减少 GC
2. **-Xmn 设置为堆内存的 40-50%**：平衡 Young GC 和 Full GC
3. **堆内存不要超过 32GB**：超过后指针压缩失效，内存利用率下降

**验证**：
```bash
# 查看 JVM 参数
jinfo <pid> | grep -E "Xms|Xmx|Xmn"

# 查看实际内存分配
jmap -heap <pid>
```

---

#### 2.1.2 堆外内存（Direct Memory）

RocketMQ 使用 Direct Memory 实现零拷贝，需合理配置：

```bash
# 堆外内存大小（默认等于堆内存）
-XX:MaxDirectMemorySize=16g

# 推荐配置：堆内存 + 堆外内存 < 物理内存 * 0.75
# 例如：64GB 物理内存
# 堆内存：32GB
# 堆外内存：16GB
# PageCache：剩余 16GB
```

**监控堆外内存**：
```bash
# 查看 Direct Memory 使用情况
jcmd <pid> VM.native_memory summary | grep -A 10 "Internal"
```

---

### 2.2 垃圾回收器选择

#### 2.2.1 G1 GC（推荐）

**适用场景**：
- 堆内存 > 4GB
- 追求低延迟（P99 < 50ms）
- 可接受略微降低吞吐量

**配置示例**：
```bash
# runbroker.sh
JAVA_OPT="${JAVA_OPT} -server -Xms16g -Xmx16g -Xmn8g"

# 使用 G1 GC
JAVA_OPT="${JAVA_OPT} -XX:+UseG1GC"
JAVA_OPT="${JAVA_OPT} -XX:MaxGCPauseMillis=200"        # GC 暂停目标时间
JAVA_OPT="${JAVA_OPT} -XX:G1ReservePercent=10"         # 预留空间比例
JAVA_OPT="${JAVA_OPT} -XX:InitiatingHeapOccupancyPercent=45"  # 触发并发标记的堆占用率

# Young 区大小控制
JAVA_OPT="${JAVA_OPT} -XX:+UnlockExperimentalVMOptions"
JAVA_OPT="${JAVA_OPT} -XX:G1NewSizePercent=30"         # Young 区最小占比
JAVA_OPT="${JAVA_OPT} -XX:G1MaxNewSizePercent=40"      # Young 区最大占比

# Region 大小（可选）
JAVA_OPT="${JAVA_OPT} -XX:G1HeapRegionSize=16m"        # 单个 Region 大小

# GC 日志
JAVA_OPT="${JAVA_OPT} -XX:+PrintGCDetails"
JAVA_OPT="${JAVA_OPT} -XX:+PrintGCDateStamps"
JAVA_OPT="${JAVA_OPT} -Xloggc:${HOME}/logs/gc_broker.log"
```

**监控 G1 GC**：
```bash
# 实时监控 GC
jstat -gcutil <pid> 1000 10

# 分析 GC 日志
# 下载 GCViewer：https://github.com/chewiebug/GCViewer
java -jar gcviewer.jar gc_broker.log
```

---

#### 2.2.2 CMS GC（旧版本使用）

**适用场景**：
- 老版本 RocketMQ（4.5 之前）
- 追求吞吐量优先

**配置示例**：
```bash
JAVA_OPT="${JAVA_OPT} -XX:+UseConcMarkSweepGC"         # 使用 CMS
JAVA_OPT="${JAVA_OPT} -XX:+UseCMSCompactAtFullCollection"  # Full GC 时压缩
JAVA_OPT="${JAVA_OPT} -XX:CMSInitiatingOccupancyFraction=70"  # Old 区 70% 触发 CMS
JAVA_OPT="${JAVA_OPT} -XX:+CMSParallelRemarkEnabled"   # 并行 Remark
```

**⚠️ 建议**：新版本优先使用 G1 GC，CMS 已被废弃。

---

### 2.3 GC 调优实战

#### 案例 1：Young GC 频繁

**现象**：
```bash
jstat -gcutil <pid> 1000
# S0     S1     E      O      M     YGC  YGCT    FGC  FGCT
# 0.00  50.12  75.34  30.45  95.67  500  2.345    3  0.567

# YGC 每秒 0.5 次，过于频繁
```

**分析**：
- Young 区太小，对象快速晋升到 Old 区
- 导致 Full GC 频率升高

**优化**：
```bash
# 增大 Young 区
-Xmn8g  → -Xmn12g

# 或调整比例
-XX:G1NewSizePercent=30  → -XX:G1NewSizePercent=40
```

---

#### 案例 2：Full GC 频繁

**现象**：
```bash
# FGC 频率：10次/小时
jstat -gccause <pid> 1000 10
```

**分析思路**：
```
1. 检查堆内存是否过小
   → jmap -heap <pid>

2. 检查是否有内存泄漏
   → jmap -dump:format=b,file=heap.hprof <pid>
   → 使用 MAT 分析

3. 检查是否有大对象
   → -XX:+PrintGCDetails 查看晋升对象大小

4. 检查 Old 区触发比例
   → 调整 -XX:InitiatingHeapOccupancyPercent
```

**优化方案**：
```bash
# 1. 增大堆内存
-Xms16g -Xmx16g  → -Xms32g -Xmx32g

# 2. 提前触发并发标记
-XX:InitiatingHeapOccupancyPercent=45  → -XX:InitiatingHeapOccupancyPercent=40

# 3. 减少不必要的对象创建（代码层面）
```

---

## 三、操作系统优化

### 3.1 内核参数调优

```bash
# /etc/sysctl.conf

# 1. 文件句柄数
fs.file-max = 2097152

# 2. 虚拟内存
vm.swappiness = 0              # 禁用 swap
vm.max_map_count = 655360      # 增加内存映射区域数量
vm.overcommit_memory = 1       # 允许内存过量分配

# 3. 网络优化
net.core.somaxconn = 2048                    # 监听队列长度
net.core.netdev_max_backlog = 2048           # 网卡接收队列
net.ipv4.tcp_max_syn_backlog = 2048          # SYN 队列长度
net.ipv4.tcp_tw_reuse = 1                    # 重用 TIME_WAIT 连接
net.ipv4.tcp_fin_timeout = 30                # FIN_WAIT2 超时时间

# 4. TCP 缓冲区
net.ipv4.tcp_rmem = 4096 87380 16777216      # 读缓冲区
net.ipv4.tcp_wmem = 4096 65536 16777216      # 写缓冲区

# 应用配置
sysctl -p
```

---

### 3.2 文件系统优化

#### 3.2.1 挂载选项

```bash
# /etc/fstab
# 使用 noatime 选项，减少磁盘 I/O
/dev/sdb1  /data/rocketmq  ext4  defaults,noatime,nodiratime  0  0

# 重新挂载
mount -o remount /data/rocketmq
```

**效果**：
- 减少访问时间戳更新
- 降低磁盘 I/O 开销
- TPS 提升 5-10%

---

#### 3.2.2 I/O 调度器

```bash
# 查看当前调度器
cat /sys/block/sdb/queue/scheduler
# [mq-deadline] kyber none

# 修改为 none（针对 SSD）
echo none > /sys/block/sdb/queue/scheduler

# 永久生效（添加到 /etc/rc.local）
echo 'echo none > /sys/block/sdb/queue/scheduler' >> /etc/rc.local
```

**调度器选择**：
- **HDD 机械硬盘**：mq-deadline（默认）
- **SSD 固态硬盘**：none 或 kyber
- **NVMe SSD**：none

---

### 3.3 关闭透明大页

```bash
# 查看透明大页状态
cat /sys/kernel/mm/transparent_hugepage/enabled
# [always] madvise never

# 临时关闭
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag

# 永久关闭（添加到 /etc/rc.local）
cat >> /etc/rc.local <<EOF
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag
EOF
```

**原因**：
- 透明大页可能导致内存碎片
- 引发 stop-the-world 停顿
- 影响延迟敏感的应用

---

## 四、Broker 参数调优

### 4.1 核心参数配置

```properties
# broker.conf

# ============ 刷盘策略 ============
# 刷盘方式：SYNC_FLUSH（同步刷盘） | ASYNC_FLUSH（异步刷盘）
flushDiskType=ASYNC_FLUSH

# 异步刷盘参数
flushCommitLogTimed=false                    # 定时刷盘（false=实时）
flushCommitLogLeastPages=4                   # 最少4页才刷盘（减少I/O）
flushCommitLogThoroughInterval=10000         # 10秒强制刷盘一次
flushConsumeQueueLeastPages=2
flushConsumeQueueThoroughInterval=60000      # 60秒强制刷盘索引

# ============ 主从同步 ============
# 主从复制方式：SYNC_MASTER（同步） | ASYNC_MASTER（异步）
brokerRole=ASYNC_MASTER

# 高可用传输
haTransferBatchSize=32768                    # 主从同步批量大小（32KB）
haSendHeartbeatInterval=5000                 # 心跳间隔（5秒）
haHousekeepingInterval=20000                 # 连接检测间隔（20秒）

# ============ 网络通信 ============
# 发送线程池
sendMessageThreadPoolNums=16                 # 发送消息线程数
sendThreadPoolQueueCapacity=10000            # 发送队列长度

# 拉取线程池
pullMessageThreadPoolNums=16
pullThreadPoolQueueCapacity=10000

# Netty 配置
serverSelectorThreads=3                      # Netty Selector 线程数
serverWorkerThreads=8                        # Netty Worker 线程数
serverChannelMaxIdleTimeSeconds=120          # 连接最大空闲时间

# ============ 存储配置 ============
# CommitLog 文件大小（默认 1GB）
mapedFileSizeCommitLog=1073741824

# ConsumeQueue 文件大小（默认 600万字节）
mapedFileSizeConsumeQueue=6000000

# 消息保留时间（小时）
fileReservedTime=72                          # 保留3天

# 删除文件时间点（凌晨4点）
deleteWhen=04

# 磁盘使用率超过多少触发清理（默认75%）
diskMaxUsedSpaceRatio=75

# ============ 性能优化 ============
# 预热内存映射
warmMapedFileEnable=true                     # 启用预热
flushLeastPagesWhenWarmMapedFile=4096        # 预热时刷盘页数

# 传输零拷贝
transferMsgByHeap=false                      # 使用零拷贝（Direct Memory）

# 开启快速失败（防止消息堆积）
osPageCacheBusyTimeOutMills=1000             # PageCache 繁忙超时（1秒）

# 消息索引
messageIndexEnable=true                      # 启用消息索引
messageIndexSafe=false                       # 索引安全模式（false=高性能）

# ============ 限流保护 ============
# 单次查询消息最大数量
maxMessageSize=4194304                       # 单条消息最大 4MB
```

---

### 4.2 参数调优实战

#### 案例 1：提升写入吞吐量

**目标**：TPS 从 3 万提升到 5 万

**优化方案**：
```properties
# 1. 采用异步刷盘
flushDiskType=ASYNC_FLUSH

# 2. 减少刷盘频率
flushCommitLogLeastPages=4   → flushCommitLogLeastPages=8

# 3. 增大发送线程池
sendMessageThreadPoolNums=16 → sendMessageThreadPoolNums=32

# 4. 启用零拷贝
transferMsgByHeap=false

# 5. 关闭消息索引（如不需要按 Key 查询）
messageIndexEnable=false
```

**效果**：
- TPS 提升 60%（3万 → 5万）
- 延迟略微增加（5ms → 8ms）
- CPU 使用率上升（50% → 65%）

---

#### 案例 2：降低消息延迟

**目标**：P99 延迟从 50ms 降到 20ms

**优化方案**：
```properties
# 1. 同步刷盘（牺牲吞吐量）
flushDiskType=SYNC_FLUSH

# 2. 实时刷盘
flushCommitLogTimed=false

# 3. 增加 Netty 线程
serverWorkerThreads=8 → serverWorkerThreads=16

# 4. 使用 SSD + RAID 10（硬件层面）
```

**效果**：
- P99 延迟降低 60%（50ms → 20ms）
- TPS 下降 20%（5万 → 4万）
- 磁盘 I/O 压力增大

---

## 五、性能测试与验证

### 5.1 压测工具

```bash
# 1. RocketMQ 自带压测工具
cd /opt/rocketmq/bin

# 生产者压测
sh benchmark.sh Producer \
  -n 127.0.0.1:9876 \
  -t test_topic \
  -s 1024 \           # 消息大小 1KB
  -c 10 \             # 生产者数量
  -w 100              # 每个生产者的线程数

# 消费者压测
sh benchmark.sh Consumer \
  -n 127.0.0.1:9876 \
  -t test_topic \
  -g test_group \
  -c 10 \             # 消费者数量
  -w 100              # 每个消费者的线程数

# 2. 自定义压测（Java代码）
```

---

### 5.2 性能基线建立

**步骤**：
```
1. 使用默认配置压测
   → 记录 TPS、延迟、CPU、内存、磁盘 I/O

2. 单一变量优化
   → 修改一个参数
   → 重新压测
   → 对比效果

3. 逐步叠加优化
   → 保留有效优化
   → 放弃无效或负面优化

4. 记录最终配置
   → 形成标准化配置模板
```

**压测报告模板**：
```markdown
## 压测环境
- Broker: 3 台（16核 32GB 内存，2TB SSD）
- NameServer: 2 台
- 测试客户端: 10 台

## 压测场景
- 消息大小: 1KB
- 生产者: 100 线程
- 消费者: 100 线程
- 持续时间: 30 分钟

## 性能指标
- TPS: 50,000 条/秒
- P99 延迟: 25ms
- CPU 使用率: 60%
- 内存使用率: 70%
- 磁盘 I/O 等待: 5%

## 优化配置
- JVM: -Xms16g -Xmx16g -XX:+UseG1GC
- Broker: flushDiskType=ASYNC_FLUSH, sendMessageThreadPoolNums=32
- OS: vm.swappiness=0, I/O 调度器=none
```

---

## 六、监控调优效果

### 6.1 关键监控指标

**JVM 监控**：
```bash
# GC 频率
jstat -gcutil <pid> 1000 10

# 期望值：
# Young GC: < 1次/秒
# Full GC: < 1次/小时
# GC 暂停时间: < 100ms
```

**Broker 监控**（Prometheus）：
```promql
# TPS
rate(rocketmq_broker_put_nums[1m])

# 延迟
histogram_quantile(0.99, rocketmq_producer_latency_bucket)

# 消息堆积
rocketmq_consumer_lag
```

**系统监控**：
```bash
# CPU
top

# 磁盘 I/O
iostat -x 1

# 网络
iftop
```

---

### 6.2 性能对比

**优化前 vs 优化后**：

| 指标 | 优化前 | 优化后 | 提升 |
|------|-------|-------|------|
| TPS | 30,000 | 50,000 | +67% |
| P99 延迟 | 50ms | 25ms | -50% |
| Young GC 频率 | 2次/秒 | 0.5次/秒 | -75% |
| Full GC 间隔 | 30分钟 | 2小时 | +300% |
| CPU 使用率 | 50% | 60% | +10% |

---

## 七、常见问题

### Q1：调优后性能反而下降？

**可能原因**：
1. 参数配置冲突（如堆内存过大导致 GC 时间过长）
2. 过度优化（如线程池过大导致上下文切换频繁）
3. 硬件瓶颈（如磁盘 I/O 已达上限）

**解决方法**：
- 回滚到基线配置
- 单一变量法重新调优
- 检查硬件监控指标

---

### Q2：如何确定 JVM 堆内存大小？

**经验公式**：
```
堆内存 = 并发连接数 × 单连接内存占用 × 2（安全系数）

例如：
- 1000 个 Producer 连接
- 每个连接占用 10MB 内存
- 堆内存 = 1000 × 10MB × 2 = 20GB
```

**验证方法**：
```bash
# 堆内存分析
jmap -heap <pid>

# 找出大对象
jmap -histo:live <pid> | head -n 20
```

---

### Q3：SSD 和 HDD 配置区别？

**SSD 配置**：
```properties
flushDiskType=ASYNC_FLUSH
flushCommitLogLeastPages=8
osPageCacheBusyTimeOutMills=1000
```

**HDD 配置**：
```properties
flushDiskType=ASYNC_FLUSH
flushCommitLogLeastPages=16       # 更大批量减少 I/O
osPageCacheBusyTimeOutMills=5000  # 更长超时
```

---

## 八、总结

### 调优优先级

```
1. 硬件层面（ROI 最高）
   → SSD > HDD
   → 增加内存
   → 万兆网卡

2. JVM 层面
   → 堆内存大小
   → GC 算法选择
   → GC 参数调整

3. 操作系统层面
   → 关闭 swap
   → I/O 调度器
   → 内核参数

4. Broker 参数层面
   → 刷盘策略
   → 线程池大小
   → 网络配置
```

### 核心配置模板

**高吞吐量场景**：
```bash
# JVM
-Xms32g -Xmx32g -Xmn16g -XX:+UseG1GC

# Broker
flushDiskType=ASYNC_FLUSH
flushCommitLogLeastPages=8
sendMessageThreadPoolNums=32
transferMsgByHeap=false
```

**低延迟场景**：
```bash
# JVM
-Xms16g -Xmx16g -Xmn8g -XX:+UseG1GC -XX:MaxGCPauseMillis=50

# Broker
flushDiskType=SYNC_FLUSH
serverWorkerThreads=16
```

### 调优检查清单

- [ ] 建立性能基线
- [ ] 配置 JVM 参数（堆内存、GC）
- [ ] 优化操作系统（swap、I/O 调度器）
- [ ] 调整 Broker 参数（刷盘、线程池）
- [ ] 压测验证效果
- [ ] 监控关键指标
- [ ] 记录优化配置
- [ ] 定期Review和调整

---

**下一篇预告**：《消息丢失排查 - 全链路追踪与问题定位》，我们将讲解如何通过全链路追踪，快速定位消息丢失问题。

**本文关键词**：`性能调优` `JVM优化` `参数配置` `压测验证`
