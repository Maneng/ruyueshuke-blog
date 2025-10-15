---
title: "供应链数据中台：Flink实时计算架构实战"
date: 2025-10-19T09:00:00+08:00
draft: false
tags: ["Flink", "实时计算", "数据中台", "ClickHouse", "大数据"]
categories: ["技术"]
description: "从T+1到实时，完整展现供应链数据中台的架构设计与实现。包含Flink实时计算、Click House OLAP、CDC数据采集和Lambda vs Kappa架构选择，附带真实性能优化经验。"
series: ["供应链系统实战"]
weight: 5
comments: true
---

## 引子：一次决策的代价

"为什么昨天的销售报表现在才出来？市场部要的促销数据还要等多久？"

这是2022年底，CEO在周会上的质问。当时我们的数据报表都是**T+1**（次日）生成，决策永远慢半拍：

**真实案例**：
- 某SKU在双十一0点开卖，2小时售罄
- 但报表第二天早上才显示"热销"
- 错失最佳补货窗口，损失百万级销售额

**核心痛点**：
- 报表延迟：T+1日报，决策滞后
- 数据孤岛：12个系统，口径不一致
- 取数慢：临时SQL查询耗时30分钟+
- 无法预警：库存告急、异常订单发现太晚

经过6个月的数据中台建设，我们实现了：
- 数据实时性：**T+1 → 秒级**
- 查询响应：**30秒 → 3秒**
- 报表数量：**20+ → 100+**
- 决策效率：提升**50%**

这篇文章，就是那段时间架构设计和技术实现的完整总结。

---

## 业务痛点：报表慢、数据乱

### 痛点1：T+1日报

**传统方案**：每天凌晨2点跑批，ETL处理

```
00:00 业务数据产生
02:00 定时任务启动，从12个系统抽数据
03:00 数据清洗、转换
04:00 写入数据仓库
08:00 业务人员看到昨天数据

延迟：8小时+
```

**业务影响**：
- 无法实时监控订单异常
- 库存告警不及时
- 促销效果无法快速评估

### 痛点2：数据口径不一致

**示例**：同一个指标，不同系统统计结果不同

```
销售额统计差异：
- OMS订单系统：¥1,234,567  （已下单）
- WMS仓储系统：¥1,189,023  （已发货）
- 财务系统：    ¥1,156,789  （已收款）

哪个是对的？都对，但口径不同！
```

### 痛点3：临时取数耗时长

```sql
-- 运营经理的需求：统计最近30天各仓库的出库量
SELECT warehouse, COUNT(*) as total
FROM outbound_orders
WHERE create_time >= '2024-01-01'
  AND create_time < '2024-02-01'
GROUP BY warehouse;

-- 执行时间：38秒（全表扫描1000万行）
```

---

## 技术选型：Lambda vs Kappa

### Lambda架构（传统）

```
           批处理层（Batch Layer）
           ↓ Hadoop/Spark
用户请求 → 服务层 ← ↓ 数据仓库
           ↑
           实时层（Speed Layer）
           ↑ Flink/Storm
```

**优点**：
- 批处理保证准确性
- 实时层补充时效性

**缺点**：
- 两套代码，维护成本高
- 数据可能不一致

### Kappa架构（我们的选择）

```
       Kafka
         ↓
    Flink实时计算
         ↓
   ClickHouse OLAP
         ↓
      数据服务
```

**理由**：
- 统一流处理，降低复杂度
- Flink可以处理批和流
- ClickHouse支持实时写入和查询

---

## 技术栈

| 组件 | 选型 | 作用 |
|------|------|------|
| 数据采集 | Canal (CDC) | 监听MySQL Binlog |
| 消息队列 | Kafka | 消息缓冲、解耦 |
| 实时计算 | Flink 1.17 | 流式ETL、聚合计算 |
| OLAP数据库 | ClickHouse 23.8 | 列式存储、秒级查询 |
| 可视化 | Apache Superset | 报表展示 |
| 调度 | DolphinScheduler | 任务编排 |

---

## 核心实现

### 1. CDC数据采集（Canal）

**Canal配置**：

```yaml
# canal.properties
canal.instance.master.address=127.0.0.1:3306
canal.instance.dbUsername=canal
canal.instance.dbPassword=canal
canal.instance.filter.regex=.*\\..*
canal.instance.filter.black.regex=
canal.mq.topic=binlog-topic
```

**Kafka消息格式**：

```json
{
  "database": "oms",
  "table": "orders",
  "type": "INSERT",
  "ts": 1704038400000,
  "data": [{
    "order_id": "202401010001",
    "user_id": 12345,
    "amount": 99.00,
    "status": "PAID",
    "create_time": "2024-01-01 00:00:00"
  }]
}
```

### 2. Flink实时计算

#### 订单实时统计

```java
@Slf4j
public class OrderRealtimeStatisticsJob {

    public static void main(String[] args) throws Exception {
        // 1. 创建执行环境
        StreamExecutionEnvironment env =
            StreamExecutionEnvironment.getExecutionEnvironment();

        env.setParallelism(4);
        env.enableCheckpointing(60000);  // 1分钟checkpoint

        // 2. 配置Kafka Source
        Properties kafkaProps = new Properties();
        kafkaProps.setProperty("bootstrap.servers", "localhost:9092");
        kafkaProps.setProperty("group.id", "flink-order-stats");

        FlinkKafkaConsumer<String> kafkaSource =
            new FlinkKafkaConsumer<>("binlog-topic",
                new SimpleStringSchema(), kafkaProps);
        kafkaSource.setStartFromLatest();

        // 3. 读取数据流
        DataStream<String> rawStream = env.addSource(kafkaSource);

        // 4. 解析Binlog
        DataStream<Order> orderStream = rawStream
            .filter(msg -> msg.contains("\"table\":\"orders\""))
            .map(new ParseBinlogFunction())
            .filter(Objects::nonNull);

        // 5. 按仓库分组，5分钟滚动窗口聚合
        DataStream<OrderStats> statsStream = orderStream
            .keyBy(Order::getWarehouse)
            .window(TumblingEventTimeWindows.of(Time.minutes(5)))
            .aggregate(new OrderAggregator());

        // 6. 写入ClickHouse
        statsStream.addSink(new ClickHouseSink());

        // 7. 执行
        env.execute("Order Realtime Statistics Job");
    }

    /**
     * 解析Binlog JSON
     */
    static class ParseBinlogFunction implements MapFunction<String, Order> {
        @Override
        public Order map(String json) {
            try {
                JSONObject obj = JSON.parseObject(json);
                if (!"INSERT".equals(obj.getString("type"))) {
                    return null;  // 只处理新增订单
                }

                JSONObject data = obj.getJSONArray("data").getJSONObject(0);
                Order order = new Order();
                order.setOrderId(data.getString("order_id"));
                order.setUserId(data.getLong("user_id"));
                order.setAmount(data.getBigDecimal("amount"));
                order.setWarehouse(data.getString("warehouse"));
                order.setCreateTime(data.getTimestamp("create_time"));

                return order;
            } catch (Exception e) {
                log.error("解析Binlog失败", e);
                return null;
            }
        }
    }

    /**
     * 聚合函数：统计订单量和金额
     */
    static class OrderAggregator
            implements AggregateFunction<Order, OrderStats, OrderStats> {

        @Override
        public OrderStats createAccumulator() {
            return new OrderStats();
        }

        @Override
        public OrderStats add(Order order, OrderStats acc) {
            acc.setWarehouse(order.getWarehouse());
            acc.setOrderCount(acc.getOrderCount() + 1);
            acc.setTotalAmount(
                acc.getTotalAmount().add(order.getAmount()));
            acc.setWindowEnd(System.currentTimeMillis());
            return acc;
        }

        @Override
        public OrderStats getResult(OrderStats acc) {
            return acc;
        }

        @Override
        public OrderStats merge(OrderStats a, OrderStats b) {
            OrderStats merged = new OrderStats();
            merged.setWarehouse(a.getWarehouse());
            merged.setOrderCount(a.getOrderCount() + b.getOrderCount());
            merged.setTotalAmount(a.getTotalAmount().add(b.getTotalAmount()));
            return merged;
        }
    }

    /**
     * ClickHouse Sink
     */
    static class ClickHouseSink extends RichSinkFunction<OrderStats> {

        private transient Connection conn;

        @Override
        public void open(Configuration parameters) throws Exception {
            Class.forName("ru.yandex.clickhouse.ClickHouseDriver");
            conn = DriverManager.getConnection(
                "jdbc:clickhouse://localhost:8123/default");
        }

        @Override
        public void invoke(OrderStats stats, Context context) throws Exception {
            String sql = "INSERT INTO order_stats " +
                "(warehouse, order_count, total_amount, window_end) " +
                "VALUES (?, ?, ?, ?)";

            try (PreparedStatement ps = conn.prepareStatement(sql)) {
                ps.setString(1, stats.getWarehouse());
                ps.setInt(2, stats.getOrderCount());
                ps.setBigDecimal(3, stats.getTotalAmount());
                ps.setTimestamp(4, new Timestamp(stats.getWindowEnd()));
                ps.executeUpdate();
            }
        }

        @Override
        public void close() throws Exception {
            if (conn != null) {
                conn.close();
            }
        }
    }
}
```

### 3. ClickHouse表设计

```sql
-- 订单统计表
CREATE TABLE order_stats (
    warehouse String,
    order_count UInt32,
    total_amount Decimal(18, 2),
    window_end DateTime
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(window_end)
ORDER BY (warehouse, window_end)
SETTINGS index_granularity = 8192;

-- 物化视图：每小时统计
CREATE MATERIALIZED VIEW order_stats_hourly
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMMDD(window_end)
ORDER BY (warehouse, toStartOfHour(window_end))
AS SELECT
    warehouse,
    toStartOfHour(window_end) as hour,
    sum(order_count) as total_orders,
    sum(total_amount) as total_sales
FROM order_stats
GROUP BY warehouse, hour;
```

### 4. 查询示例

```sql
-- 实时查询：过去1小时各仓库订单量
SELECT
    warehouse,
    sum(order_count) as total_orders,
    sum(total_amount) as total_sales
FROM order_stats
WHERE window_end >= now() - INTERVAL 1 HOUR
GROUP BY warehouse
ORDER BY total_orders DESC;

-- 响应时间：<3秒
```

---

## 生产优化

### 1. Checkpoint策略

```java
// checkpoint配置
env.enableCheckpointing(60000);  // 1分钟
env.getCheckpointConfig()
   .setCheckpointingMode(CheckpointingMode.EXACTLY_ONCE);  // 精确一次
env.getCheckpointConfig()
   .setMinPauseBetweenCheckpoints(30000);  // 最小间隔30秒
env.getCheckpointConfig()
   .setCheckpointTimeout(120000);  // 超时2分钟
env.getCheckpointConfig()
   .setMaxConcurrentCheckpoints(1);  // 同时只有1个checkpoint
env.getCheckpointConfig()
   .enableExternalizedCheckpoints(
       ExternalizedCheckpointCleanup.RETAIN_ON_CANCELLATION);  // 取消时保留
```

### 2. 反压监控

```java
// 自定义Metric
public class BackpressureMetric extends RichMapFunction<Order, Order> {

    private transient Counter processedRecords;
    private transient Meter recordsPerSecond;

    @Override
    public void open(Configuration parameters) {
        processedRecords = getRuntimeContext()
            .getMetricGroup()
            .counter("processed_records");

        recordsPerSecond = getRuntimeContext()
            .getMetricGroup()
            .meter("records_per_second", new MeterView(60));
    }

    @Override
    public Order map(Order order) {
        processedRecords.inc();
        recordsPerSecond.markEvent();
        return order;
    }
}
```

### 3. ClickHouse分区策略

```sql
-- 按月分区 + 按天二级分区
ALTER TABLE order_stats
PARTITION BY (toYYYYMM(window_end), toDayOfMonth(window_end));

-- 自动删除90天前的分区
ALTER TABLE order_stats
DROP PARTITION WHERE toDate(window_end) < today() - 90;
```

---

## 效果数据与经验总结

### 上线效果

| 指标 | 优化前 | 优化后 | 提升 |
|------|--------|--------|------|
| 数据实时性 | T+1（24小时） | 秒级 | **99.9%** |
| 查询响应时间 | 30秒 | 3秒 | **90%** |
| 报表数量 | 20+ | 100+ | **5倍** |
| 数据准确率 | 85% | 99.5% | **17%** |

### 核心经验

#### ✅ DO

1. **选择合适架构**：Kappa比Lambda简单，够用就行
2. **CDC优于定时抽取**：实时性更好，对源库压力小
3. **ClickHouse分区设计**：按时间分区，查询+删除都快
4. **Exactly-Once**：Flink checkpoint保证数据不丢不重
5. **监控要完善**：反压、延迟、数据量实时监控

#### ❌ DON'T

1. **不要过度实时**：不是所有指标都需要秒级
2. **不要忽略成本**：ClickHouse内存消耗大
3. **不要缺少降级**：实时链路故障时要有批处理兜底
4. **不要忽略数据质量**：脏数据会污染整个数据湖

---

## 参考资料

- [Apache Flink官方文档](https://flink.apache.org/)
- [ClickHouse官方文档](https://clickhouse.com/docs/)
- [Canal GitHub](https://github.com/alibaba/canal)

---

## 系列文章完结

恭喜！你已读完《供应链系统实战》全系列：

- **第1篇**：渠道共享库存中心 - Redis分布式锁的生产实践 ✅
- **第2篇**：跨境电商关务系统 - 三单对碰的技术实现 ✅
- **第3篇**：WMS仓储系统 - 库位分配算法的演进之路 ✅
- **第4篇**：OMS订单系统 - 智能拆单规则引擎设计 ✅
- **第5篇**：供应链数据中台 - Flink实时计算架构实战 ✅

**系列总结**：
- 总字数：**21,500+字**
- 涵盖领域：分布式、WebService、算法、规则引擎、大数据
- 代码示例：**50+段**
- 真实案例：**5个生产环境优化故事**

感谢阅读！期待在评论区与你交流。

---

*如果这个系列对你有帮助，欢迎分享给更多同行。*
