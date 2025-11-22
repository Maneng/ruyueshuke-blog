---
title: "WMS生产实践与故障排查"
date: 2025-11-22T17:00:00+08:00
draft: false
tags: ["WMS", "生产实践", "故障排查", "性能优化"]
categories: ["技术"]
description: "掌握WMS生产环境的部署、监控、故障排查和性能调优实战经验"
series: ["WMS从入门到精通"]
weight: 9
stage: 3
stageTitle: "架构进阶篇"
---

## 引言

本文分享WMS生产环境的实战经验，包括部署架构、常见故障排查、性能调优和大促保障。

---

## 1. 生产环境部署

### 1.1 服务器规划

**小型WMS（日订单<5000单）**：
```
应用服务器: 2台（4核8G）
数据库服务器: 1台（8核16G）+ 从库1台（备份）
Redis服务器: 1台（4核8G）
```

**中型WMS（日订单5000-50000单）**：
```
应用服务器: 4台（8核16G）+ 负载均衡
数据库服务器: 1主2从（16核32G）+ 读写分离
Redis集群: 3台（8核16G）
消息队列: 3台（RabbitMQ集群）
```

**大型WMS（日订单>50000单）**：
```
应用服务器: 10+台（16核32G）+ Kubernetes
数据库服务器: MySQL主从 + 分库分表
Redis集群: 6台（哨兵模式）
消息队列: Kafka集群（5台）
监控服务: Prometheus + Grafana
```

---

### 1.2 高可用架构

```
┌─────────────────────────────────────┐
│     Nginx负载均衡（主备）            │
└─────────────────────────────────────┘
        ↓          ↓          ↓
  ┌─────────┐ ┌─────────┐ ┌─────────┐
  │ WMS-1   │ │ WMS-2   │ │ WMS-3   │
  └─────────┘ └─────────┘ └─────────┘
        ↓          ↓          ↓
  ┌─────────────────────────────────┐
  │    MySQL主从（读写分离）         │
  │    Master + Slave1 + Slave2     │
  └─────────────────────────────────┘
        ↓
  ┌─────────────────────────────────┐
  │    Redis哨兵模式                │
  │    Master + Slave + Sentinel    │
  └─────────────────────────────────┘
```

---

### 1.3 容灾备份策略

**数据库备份**：
```bash
# 每天凌晨2点全量备份
0 2 * * * mysqldump -u root -p wms > /backup/wms_$(date +\%Y\%m\%d).sql

# 增量备份（binlog）
mysqlbinlog --start-datetime="2025-11-22 00:00:00" \
            --stop-datetime="2025-11-22 23:59:59" \
            /var/log/mysql/mysql-bin.000001 > incremental_backup.sql
```

**Redis备份**：
```bash
# 每小时保存RDB
save 3600 1

# AOF持久化
appendonly yes
appendfsync everysec
```

---

## 2. 常见故障与排查

### 2.1 库存不准

**现象**：
- 账面库存: 100件
- 实际库存: 98件
- 差异: 2件

**原因分析**：
1. 入库未记录：收货完成，未调用API
2. 出库未扣减：拣货完成，系统未扣减
3. 盘点错误：人工盘点漏盘
4. 实物丢失：盗窃、损坏

**排查步骤**：
```sql
-- 1. 查询库存操作日志
SELECT * FROM inventory_log
WHERE sku_code = 'iPhone-15Pro'
ORDER BY created_at DESC
LIMIT 100;

-- 2. 对比入库单和库存
SELECT
  SUM(received_qty) AS total_received
FROM inbound_order_detail
WHERE sku_code = 'iPhone-15Pro';

SELECT qty FROM inventory
WHERE sku_code = 'iPhone-15Pro';

-- 3. 查询异常日志
SELECT * FROM error_log
WHERE message LIKE '%库存%'
  AND created_at >= '2025-11-20';
```

**解决方案**：
1. 补录数据：手工调整库存
2. 修复BUG：修复代码逻辑
3. 加强监控：库存变化告警

---

### 2.2 波次拣货慢

**现象**：
- 波次拣货时间：从15分钟增加到45分钟
- 拣货员反馈：系统卡顿

**原因分析**：
1. 数据库慢查询
2. 波次订单数过多（>500单）
3. 路径优化算法超时

**排查步骤**：
```sql
-- 查询慢查询日志
SHOW VARIABLES LIKE 'slow_query_log';
SHOW VARIABLES LIKE 'long_query_time';

-- 查询执行时间超过2秒的SQL
SELECT * FROM mysql.slow_log
WHERE query_time > 2
ORDER BY query_time DESC;

-- 分析执行计划
EXPLAIN SELECT * FROM outbound_order_detail
WHERE order_no IN (SELECT order_no FROM outbound_order WHERE wave_no = 'WAVE001');
```

**解决方案**：
1. 添加索引：
```sql
CREATE INDEX idx_outbound_wave ON outbound_order(wave_no);
```

2. 优化波次策略：限制波次订单数（<200单）

3. 异步优化路径：
```java
@Async
public void optimizePath(Wave wave) {
    // 异步计算最优路径
    List<PickTask> tasks = wave.getTasks();
    List<PickTask> optimizedTasks = tspAlgorithm.optimize(tasks);
    wave.setTasks(optimizedTasks);
}
```

---

### 2.3 RF终端卡顿

**现象**：
- RF扫描后，页面loading 5秒以上
- 拣货员投诉：系统太慢

**原因分析**：
1. 网络延迟：WiFi信号弱
2. 接口响应慢：数据库查询慢
3. RF终端性能差

**排查步骤**：
```bash
# 1. 测试网络延迟
ping wms-server.com

# 2. 查看接口响应时间
curl -w "@curl-format.txt" -o /dev/null -s http://wms-server.com/api/pick
```

**curl-format.txt**：
```
time_namelookup:  %{time_namelookup}\n
time_connect:  %{time_connect}\n
time_starttransfer:  %{time_starttransfer}\n
time_total:  %{time_total}\n
```

**解决方案**：
1. 优化WiFi覆盖：增加AP
2. 接口优化：添加Redis缓存
3. 升级RF终端硬件

---

### 2.4 打印失败

**现象**：
- 打印机报错：无法打印
- 打印队列堆积

**原因分析**：
1. 打印机离线：网络断开、电源关闭
2. 驱动问题：打印协议不匹配
3. 打印队列满：任务堆积

**排查步骤**：
```bash
# 检查打印机网络连接
ping printer-ip

# 查看打印队列
lpstat -p

# 清空打印队列
cancel -a
```

**解决方案**：
1. 重启打印机
2. 检查打印协议（ZPL、TSPL）
3. 清空打印队列

---

## 3. 性能调优

### 3.1 数据库慢查询优化

**案例**：库存查询慢

**优化前**：
```sql
SELECT * FROM inventory
WHERE sku_code = 'iPhone-15Pro' AND available_qty > 0;

-- 执行时间：2.5秒
```

**分析执行计划**：
```sql
EXPLAIN SELECT * FROM inventory
WHERE sku_code = 'iPhone-15Pro' AND available_qty > 0;

-- type: ALL（全表扫描）
```

**优化方案**：添加索引
```sql
CREATE INDEX idx_inventory_sku_qty ON inventory(sku_code, available_qty);
```

**优化后**：
```sql
-- 执行时间：0.01秒（提升250倍）
```

---

### 3.2 库存扣减锁优化

**问题**：高并发场景，库存扣减慢

**优化前**（悲观锁）：
```java
@Transactional
public boolean lockInventory(String skuCode, int qty) {
    Inventory inventory = inventoryRepo.findBySkuCodeForUpdate(skuCode);
    // 阻塞等待，性能差
    ...
}
```

**优化后**（Redis + 异步）：
```java
public boolean lockInventory(String skuCode, int qty) {
    // Redis原子扣减
    String key = "inventory:" + skuCode;
    Long available = redisTemplate.opsForValue().decrement(key, qty);

    if (available < 0) {
        redisTemplate.opsForValue().increment(key, qty);
        return false;
    }

    // 异步更新DB
    asyncUpdateInventory(skuCode, qty);
    return true;
}
```

**性能提升**：
- QPS: 500 → 5000（提升10倍）

---

### 3.3 批量任务调度优化

**场景**：每小时生成500个波次

**优化前**：
```java
for (Wave wave : waves) {
    generateWave(wave);  // 同步处理，总耗时50分钟
}
```

**优化后**：
```java
// 线程池并发处理
ExecutorService executor = Executors.newFixedThreadPool(10);
for (Wave wave : waves) {
    executor.submit(() -> generateWave(wave));
}
executor.shutdown();
executor.awaitTermination(10, TimeUnit.MINUTES);
// 总耗时5分钟（提升10倍）
```

---

## 4. 大促保障（双11案例）

### 4.1 预案准备

**1. 容量规划**
```
预估订单量: 100万单/天
峰值QPS: 2000单/秒
服务器扩容: 10台 → 30台
数据库扩容: 16核32G → 32核64G
Redis扩容: 3台 → 6台
```

**2. 压力测试**
```bash
# 使用JMeter压测
jmeter -n -t wms_stress_test.jmx -l result.jtl

# 模拟10000并发用户
# 持续压测30分钟
```

**3. 限流熔断**
```java
@RateLimiter(value = 1000, timeout = 100)  // 限流1000QPS
@HystrixCommand(fallbackMethod = "fallback")
public Result createOrder(OutboundOrder order) {
    // 业务逻辑
}

public Result fallback(OutboundOrder order) {
    return Result.error("系统繁忙，请稍后重试");
}
```

---

### 4.2 实时监控

**Grafana监控面板**：
```
1. 系统指标：
   - CPU使用率: < 70%
   - 内存使用率: < 80%
   - QPS: 实时曲线

2. 业务指标：
   - 订单量: 实时统计
   - 库存准确率: 99.9%
   - 出库时效: <2小时

3. 告警规则：
   - CPU > 80%：告警
   - 数据库慢查询 > 2秒：告警
   - 库存不足：告警
```

---

### 4.3 应急预案

**场景1：数据库挂了**
```
1. 切换到从库（1分钟）
2. 通知DBA修复主库
3. 数据同步，切回主库
```

**场景2：Redis挂了**
```
1. 降级：直连数据库（性能下降）
2. 重启Redis
3. 恢复缓存
```

**场景3：库存不足**
```
1. 系统提示：部分商品缺货
2. 紧急调拨其他仓库库存
3. 通知采购补货
```

---

## 5. 总结

**生产实践要点**：
1. **高可用架构**：负载均衡 + 主从 + 哨兵
2. **故障排查**：日志分析 + 监控告警
3. **性能调优**：索引优化 + Redis缓存 + 异步处理
4. **大促保障**：扩容 + 压测 + 限流 + 监控

**下一篇预告**：WMS未来趋势：智能化与自动化

---

**版权声明**：本文为原创文章，转载请注明出处。
