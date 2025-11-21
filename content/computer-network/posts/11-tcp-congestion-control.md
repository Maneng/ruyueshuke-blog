---
title: "TCP拥塞控制：慢启动、拥塞避免与BBR算法"
date: 2025-11-21T16:40:00+08:00
draft: false
tags: ["计算机网络", "TCP", "拥塞控制", "慢启动", "BBR"]
categories: ["技术"]
description: "深入理解TCP拥塞控制机制，慢启动、拥塞避免、快速重传、快速恢复四大算法，以及Google BBR算法的革新"
series: ["计算机网络从入门到精通"]
weight: 11
stage: 2
stageTitle: "传输层协议篇"
---

## 引言

在上一篇文章中，我们学习了TCP的**流量控制机制**（接收方控制发送方，避免接收缓冲区溢出）。今天我们来学习TCP的**拥塞控制机制（Congestion Control）**：发送方感知网络状况，避免网络拥塞。

**为什么需要拥塞控制？**
- 流量控制解决了端到端的问题（接收方处理能力）
- 但网络本身也有容量限制（带宽、路由器缓冲区）
- 如果所有发送方都全速发送，**网络会瘫痪**

今天我们来理解：
- ✅ 慢启动（Slow Start）
- ✅ 拥塞避免（Congestion Avoidance）
- ✅ 快速重传（Fast Retransmit）
- ✅ 快速恢复（Fast Recovery）
- ✅ Google BBR算法的革新

## 第一性原理：为什么需要拥塞控制？

### 问题：网络拥塞

**场景**：100个客户端同时向服务器发送数据

```
100个客户端                   路由器                  服务器
   |                           |                       |
   | 每个1Gbps速度发送          |  路由器带宽只有10Gbps  |
   |-------------------------->|                       |
   |                           | 队列满了！丢包！      |
   |                           |                       |
   | 丢包后重传，继续全速发送   |                       |
   |-------------------------->|                       |
   |                           | 更加拥塞！            |
   |                           | 丢包率暴增！          |
   |                           |                       |
   | ❌ 网络瘫痪                |                       |
```

**拥塞的后果**：
- ❌ 丢包率增加
- ❌ 延迟增加（路由器队列排队）
- ❌ 吞吐量下降（大量重传）
- ❌ 网络资源浪费

**拥塞控制的目标**：
- ✅ 感知网络拥塞状况
- ✅ 动态调整发送速率
- ✅ 避免网络崩溃
- ✅ 充分利用网络容量

---

## 拥塞窗口（cwnd）

### 核心概念

**拥塞窗口（Congestion Window, cwnd）**：发送方维护的一个变量，表示网络能承受的数据量

**实际发送窗口**：
```
实际发送窗口 = min(rwnd, cwnd)
             = min(接收窗口, 拥塞窗口)
```

**示例**：
```
rwnd = 64KB（接收方通告）
cwnd = 32KB（发送方自己维护）

实际发送窗口 = min(64KB, 32KB) = 32KB
```

**cwnd的调整**：
- 初始值：通常为10个MSS（Maximum Segment Size，最大报文段长度）
- 动态调整：根据网络状况增大或减小
- 目标：找到网络的最佳工作点

**MSS（Maximum Segment Size）**：
- TCP报文段的最大数据部分长度
- 通常为1460字节（以太网MTU 1500字节 - IP头部20字节 - TCP头部20字节）

---

## 慢启动（Slow Start）

### 核心思想

**不要一上来就全速发送，先试探网络容量**

### 算法流程

**初始状态**：
```
cwnd = 10 MSS（通常10 × 1460 = 14.6KB）
ssthresh（慢启动阈值）= 65535字节（初始值很大）
```

**指数增长阶段**：
```
RTT（往返时延）= 100ms

[初始] cwnd = 10 MSS
发送10个报文段

[100ms后] 收到10个ACK（无丢包）
cwnd = 10 + 10 = 20 MSS（每个ACK让cwnd+1）
发送20个报文段

[200ms后] 收到20个ACK
cwnd = 20 + 20 = 40 MSS
发送40个报文段

[300ms后] 收到40个ACK
cwnd = 40 + 40 = 80 MSS
发送80个报文段

...

每个RTT，cwnd翻倍（指数增长）
```

**增长曲线**：
```
cwnd
  ^
  |                      /
  |                    /
  |                  /
  |                /
  |              /
  |            /
  |          /
  |        /
  |      /
  |    /
  |  /
  | /
  |/
  +------------------------> 时间（RTT）
  10   20   40   80   160
```

**何时结束慢启动？**
1. **cwnd >= ssthresh**：进入拥塞避免阶段
2. **发生丢包**：网络拥塞了，降低cwnd
3. **收到3个重复ACK**：快速重传

---

## 拥塞避免（Congestion Avoidance）

### 核心思想

**慢启动阶段增长太快了，现在要小心翼翼地增长**

### 算法流程

**触发条件**：`cwnd >= ssthresh`

**线性增长**：
```
[初始] cwnd = 40 MSS, ssthresh = 40 MSS
进入拥塞避免阶段

[100ms后] 收到40个ACK
cwnd = 40 + 1 = 41 MSS（每个RTT只增加1个MSS）

[200ms后] 收到41个ACK
cwnd = 41 + 1 = 42 MSS

[300ms后] 收到42个ACK
cwnd = 42 + 1 = 43 MSS

...

每个RTT，cwnd只增加1个MSS（线性增长）
```

**增长曲线（慢启动 + 拥塞避免）**：
```
cwnd
  ^
  |                    /‾‾‾‾‾‾‾  拥塞避免（线性）
  |                   /
  |                  /
  |                 / ← ssthresh
  |                /
  |              /
  |            /    慢启动（指数）
  |          /
  |        /
  |      /
  |    /
  |  /
  | /
  +------------------------> 时间（RTT）
```

---

## 快速重传（Fast Retransmit）

### 问题：超时重传太慢

**传统重传**：等待RTO（Retransmission Timeout）超时后重传

```
发送方                                 接收方
   |  seq=1（到达）                    |
   |---------------------------------->|
   |                                   | ACK=2
   |<----------------------------------|
   |                                   |
   |  seq=2（丢失！）                  |
   |----X                              |
   |                                   |
   |  seq=3（到达）                    |
   |---------------------------------->|
   |                                   | 期望seq=2，收到seq=3
   |                                   | 发送重复ACK=2
   |  ACK=2（重复）                    |
   |<----------------------------------|
   |                                   |
   |  seq=4（到达）                    |
   |---------------------------------->|
   |  ACK=2（重复）                    |
   |<----------------------------------|
   |                                   |
   | 等待RTO超时（通常几秒）...        |
   |  seq=2（重传）                    |
   |---------------------------------->|
   |  ACK=5                            |
   |<----------------------------------|
```

**问题**：
- RTO通常很长（几百毫秒到几秒）
- 这段时间内，发送方停止发送
- 吞吐量下降

### 快速重传算法

**核心思想**：收到3个重复ACK，立即重传，不等超时

**流程**：
```
发送方                                 接收方
   |  seq=1（到达）                    |
   |---------------------------------->|
   |  ACK=2                            |
   |<----------------------------------|
   |                                   |
   |  seq=2（丢失！）                  |
   |----X                              |
   |                                   |
   |  seq=3（到达）                    |
   |---------------------------------->|
   |  ACK=2（重复ACK #1）              |
   |<----------------------------------|
   |                                   |
   |  seq=4（到达）                    |
   |---------------------------------->|
   |  ACK=2（重复ACK #2）              |
   |<----------------------------------|
   |                                   |
   |  seq=5（到达）                    |
   |---------------------------------->|
   |  ACK=2（重复ACK #3）              |
   |<----------------------------------|
   |                                   |
   | 收到3个重复ACK，立即重传seq=2！   |
   |  seq=2（快速重传）                |
   |---------------------------------->|
   |  ACK=6（确认2-5都收到了）         |
   |<----------------------------------|
```

**优点**：
- ✅ 不需要等待RTO超时
- ✅ 快速恢复丢失的数据
- ✅ 降低延迟

---

## 快速恢复（Fast Recovery）

### 核心思想

**发生快速重传时，不要像超时那样把cwnd降到1，而是降到一半**

### 算法流程

**场景1：超时重传**（网络严重拥塞）
```
[拥塞发生]
cwnd = 40 MSS

[超时重传]
ssthresh = cwnd / 2 = 20 MSS
cwnd = 10 MSS（重新慢启动）
```

**场景2：快速重传**（轻微拥塞）
```
[拥塞发生]
cwnd = 40 MSS

[收到3个重复ACK，进入快速恢复]
ssthresh = cwnd / 2 = 20 MSS
cwnd = ssthresh + 3 = 23 MSS（不是10！）

[重传丢失的报文段]
...

[收到新的ACK（确认新数据）]
cwnd = ssthresh = 20 MSS
进入拥塞避免阶段
```

**为什么设置为 `ssthresh + 3`？**
- 收到3个重复ACK，说明有3个报文段已经到达接收方
- 这3个报文段已经离开了网络
- 可以立即发送3个新报文段填补空缺

### 拥塞控制完整状态机

```
              慢启动
              cwnd指数增长
                  |
                  | cwnd >= ssthresh
                  ↓
              拥塞避免
              cwnd线性增长
                  |
         /--------+---------\
         |                  |
   收到3个重复ACK        超时
         |                  |
         ↓                  ↓
     快速恢复           慢启动
  cwnd=ssthresh/2      cwnd=10
         |
         | 收到新ACK
         ↓
      拥塞避免
```

---

## BBR算法：拥塞控制的革新

### 传统算法的问题

**基于丢包的拥塞控制（TCP Reno/Cubic）**：
- ❌ 把丢包当作拥塞信号
- ❌ 但丢包不一定是拥塞（可能是无线网络干扰、路由器队列满）
- ❌ 需要把队列填满才能达到最大带宽（增加延迟）

**问题场景**：
```
高带宽 + 高延迟网络（如跨国链路）

带宽：100Mbps
RTT：200ms
BDP（带宽延迟积）= 100Mbps × 0.2s = 2.5MB

传统算法：
- 需要填满路由器队列才敢增大cwnd
- 延迟从200ms增加到500ms
- 用户体验差
```

### BBR算法核心思想

**不再基于丢包，而是基于带宽和延迟**

**目标**：
1. 最大化吞吐量：发送速率 = 瓶颈带宽
2. 最小化延迟：不让路由器队列积压

**关键概念**：
```
BtlBw（Bottleneck Bandwidth）：瓶颈带宽
RTprop（Round-Trip Propagation Time）：最小RTT（不排队）

发送速率 = BtlBw
cwnd = BtlBw × RTprop（刚好填满带宽，不排队）
```

### BBR算法工作模式

**四个阶段循环**：

#### 1. Startup（启动）
- 指数增长cwnd，探测带宽
- 类似慢启动，但更激进

#### 2. Drain（排空）
- 发现带宽后，排空队列中的数据
- 降低发送速率，让延迟恢复到最小

#### 3. ProbeBW（探测带宽）
- 周期性增大cwnd，探测带宽是否增加
- 大部分时间停留在这个阶段

#### 4. ProbeRTT（探测RTT）
- 周期性降低cwnd，探测最小RTT
- 避免低速流量无法探测到真实RTT

**BBR vs 传统算法**：

| 特性 | 传统（Reno/Cubic） | BBR |
|------|-------------------|-----|
| 拥塞信号 | 丢包 | 带宽和延迟 |
| 队列占用 | 填满队列 | 最小队列 |
| 延迟 | 高 | 低 |
| 吞吐量 | 中等 | 高 |
| 适用场景 | 低延迟网络 | 高带宽高延迟网络 |

**效果对比**（Google数据）：
```
场景：跨国数据传输
带宽：100Mbps
RTT：200ms

传统Cubic：
- 吞吐量：80Mbps
- 延迟：500ms（队列排队）

BBR：
- 吞吐量：95Mbps
- 延迟：210ms（几乎无排队）

BBR提升：
- 吞吐量提升18.75%
- 延迟降低58%
```

### Linux启用BBR

**检查内核版本**（需要4.9+）：
```bash
uname -r
# 输出：4.19.0（或更高版本）
```

**启用BBR**：
```bash
# 临时启用
sudo sysctl -w net.ipv4.tcp_congestion_control=bbr
sudo sysctl -w net.core.default_qdisc=fq

# 持久化配置
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
sudo sysctl -p

# 验证
sysctl net.ipv4.tcp_congestion_control
# 输出：net.ipv4.tcp_congestion_control = bbr
```

---

## 实战案例：拥塞控制问题排查

### 案例1：查看当前拥塞控制算法

```bash
# 查看系统默认算法
sysctl net.ipv4.tcp_congestion_control
# 输出：net.ipv4.tcp_congestion_control = cubic

# 查看所有可用算法
sysctl net.ipv4.tcp_available_congestion_control
# 输出：net.ipv4.tcp_available_congestion_control = reno cubic bbr
```

### 案例2：用ss命令查看cwnd

```bash
# 查看TCP连接的拥塞窗口
ss -tin

# 输出示例
State      Recv-Q Send-Q Local Address:Port  Peer Address:Port
ESTAB      0      0      192.168.1.100:8080 192.168.1.200:54321
         cubic wscale:7,7 rto:204 rtt:4/2 cwnd:10 ssthresh:7
         ↑算法  ↑窗口缩放  ↑RTO   ↑RTT    ↑拥塞窗口 ↑慢启动阈值

# 关键字段
cwnd:10         # 当前拥塞窗口为10个MSS
ssthresh:7      # 慢启动阈值为7个MSS（通常表示发生过拥塞）
```

### 案例3：微服务跨地域调用慢

**现象**：北京机房调用美国机房接口，延迟5秒

**排查步骤**：

**步骤1：测量RTT**
```bash
ping us-service.example.com

# 输出
64 bytes from us-service: time=200ms
# RTT很高（200ms）
```

**步骤2：查看拥塞控制算法**
```bash
sysctl net.ipv4.tcp_congestion_control
# 输出：cubic（传统算法）
```

**步骤3：分析问题**
```
网络环境：
- 带宽：100Mbps
- RTT：200ms
- BDP = 100Mbps × 0.2s = 2.5MB

Cubic算法：
- 慢启动阶段：cwnd从10个MSS（14.6KB）开始
- 每个RTT翻倍：14.6KB → 29.2KB → 58.4KB → 116.8KB ...
- 达到2.5MB需要：log2(2.5MB / 14.6KB) ≈ 8个RTT
- 时间：8 × 200ms = 1.6秒

加上拥塞避免阶段，总共需要几秒才能达到最佳吞吐量
```

**步骤4：解决方案**
```bash
# 启用BBR算法
sudo sysctl -w net.ipv4.tcp_congestion_control=bbr

# 增大初始cwnd（可选）
sudo ip route change default via <gateway> initcwnd 30

# 效果：
# - BBR快速探测到瓶颈带宽（100Mbps）
# - 从一开始就以最佳速率发送
# - 延迟从5秒降低到1秒以内
```

### 案例4：高丢包率导致吞吐量低

**现象**：文件传输速度只有10Mbps，但带宽有100Mbps

**排查**：
```bash
# 查看丢包情况
netstat -s | grep retransmit

# 输出
12345 segments retransmitted  # 大量重传！

# 查看cwnd
ss -tin | grep ESTAB

# 输出
cwnd:5 ssthresh:5  # cwnd很小，说明频繁发生拥塞
```

**原因**：
- 网络丢包率高（如无线网络）
- 传统算法把丢包当作拥塞，降低cwnd
- cwnd一直很小，无法充分利用带宽

**解决**：
```bash
# 方案1：启用BBR（不基于丢包）
sudo sysctl -w net.ipv4.tcp_congestion_control=bbr

# 方案2：调整TCP参数，容忍丢包
sudo sysctl -w net.ipv4.tcp_reordering=10
```

---

## 拥塞控制算法对比

| 算法 | 拥塞信号 | 增长方式 | 适用场景 | 优点 | 缺点 |
|------|---------|---------|---------|------|------|
| **Reno** | 丢包 | 慢启动 + AIMD | 低延迟网络 | 简单稳定 | 带宽利用率低 |
| **Cubic** | 丢包 | 立方函数增长 | 高带宽网络 | 快速收敛 | 高延迟网络效果差 |
| **BBR** | 带宽+延迟 | 基于模型 | 高带宽高延迟 | 低延迟高吞吐 | 可能不公平 |

**AIMD（Additive Increase Multiplicative Decrease）**：
- 加性增（Additive Increase）：每个RTT增加1个MSS
- 乘性减（Multiplicative Decrease）：发生拥塞时减半

---

## 微服务场景的拥塞控制优化

### 场景1：内网微服务（低延迟）

```yaml
# 特点：延迟<1ms，带宽1Gbps+
# 建议：使用Cubic（默认）即可

net.ipv4.tcp_congestion_control = cubic
net.ipv4.tcp_slow_start_after_idle = 0  # 禁用慢启动（连接空闲后）
```

### 场景2：跨地域微服务（高延迟）

```yaml
# 特点：延迟50-200ms，带宽100Mbps
# 建议：启用BBR

net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
```

### 场景3：云服务调用（带宽受限）

```yaml
# 特点：延迟10-50ms，带宽10-100Mbps
# 建议：BBR + 调整初始窗口

net.ipv4.tcp_congestion_control = bbr

# 增大初始cwnd（需要ip route命令）
# ip route change default via <gateway> initcwnd 30
```

### 场景4：CDN边缘节点

```yaml
# 特点：大量短连接，需要快速达到峰值
# 建议：BBR + 大初始窗口 + 禁用慢启动

net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_slow_start_after_idle = 0
```

---

## 总结

### 核心要点

1. **拥塞控制的目标**：
   - 避免网络拥塞
   - 充分利用网络容量
   - 公平共享带宽

2. **四大算法**：
   - **慢启动**：指数增长，快速探测网络容量
   - **拥塞避免**：线性增长，小心翼翼地接近最优点
   - **快速重传**：收到3个重复ACK立即重传
   - **快速恢复**：轻微拥塞时不重新慢启动

3. **拥塞窗口（cwnd）**：
   - 发送方维护，表示网络能承受的数据量
   - 动态调整：根据网络状况增大或减小
   - 实际发送窗口 = min(rwnd, cwnd)

4. **BBR算法**：
   - 基于带宽和延迟，不是丢包
   - 低延迟 + 高吞吐量
   - 适合高带宽高延迟网络

### 与下一篇的关联

本文讲解了TCP的**拥塞控制机制**（慢启动、拥塞避免、快速重传、快速恢复）。下一篇我们将学习TCP的**重传机制**，理解：
- 超时重传（RTO计算）
- 快速重传的详细机制
- SACK选择性确认
- 如何用Wireshark分析重传问题

### 思考题

1. 为什么慢启动是"慢"的？它的增长速度其实很快（指数增长）？
2. 快速恢复为什么要设置 `cwnd = ssthresh + 3`？
3. BBR算法为什么能在高延迟网络下表现更好？
4. 在什么场景下不应该使用BBR？

---

**下一篇预告**：《TCP重传机制：超时重传与快速重传详解》
