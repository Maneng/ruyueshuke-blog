---
title: "WMS拣货策略优化——提升仓库出库效率的核心方法"
date: 2026-02-02T11:00:00+08:00
draft: false
tags: ["WMS", "拣货策略", "波次管理", "路径优化", "仓储效率"]
categories: ["数字化转型"]
description: "拣货是仓库作业中最耗时的环节，本文详解波次策略、拣货模式、路径优化算法，帮你将拣货效率提升50%以上。"
series: ["跨境电商数字化转型指南"]
weight: 20
---

## 引言：拣货效率决定仓库产能

**拣货占仓库作业时间的50%-60%**：

- 拣货效率直接决定发货速度
- 拣货准确率影响客户满意度
- 拣货成本是仓储成本的大头

**优化拣货的核心目标**：
1. **减少行走距离**：路径最短
2. **提高拣货准确率**：减少错拣
3. **提升人效**：单位时间拣更多

---

## 一、拣货业务全景

### 1.1 拣货流程

```
出库指令 ──> 波次生成 ──> 任务分配 ──> 拣货执行 ──> 复核 ──> 发货
    │           │           │           │          │       │
    ▼           ▼           ▼           ▼          ▼       ▼
接收OMS     按规则分波   分配拣货员   PDA扫码    扫码核对  交接物流
```

### 1.2 拣货模式对比

| 模式 | 说明 | 效率 | 准确率 | 适用场景 |
|-----|-----|-----|-------|---------|
| 单单拣货 | 一次拣一个订单 | 低 | 高 | 订单量小、高价值 |
| 批量拣货 | 先拣后分 | 高 | 中 | 订单量大、SKU集中 |
| 边拣边分 | 拣货同时分拣 | 中 | 高 | 中等订单量 |
| 播种式 | 先汇总再分播 | 高 | 高 | 大促、爆款 |

---

## 二、波次管理

### 2.1 什么是波次

**波次 = 将多个出库单合并成一个批次处理**

波次的价值：
- 合并相同SKU的拣货需求
- 减少重复行走
- 提高拣货效率

### 2.2 波次策略

| 策略 | 说明 | 适用场景 |
|-----|-----|---------|
| 按承运商 | 同一物流的订单一波 | 物流交接时间固定 |
| 按时效 | 同一时效要求的一波 | 有时效要求 |
| 按库区 | 同一库区的订单一波 | 仓库较大 |
| 按订单类型 | 单品/多品分开 | 提高效率 |
| 按SKU | 相同SKU的订单一波 | 爆款商品 |

### 2.3 波次数据模型

```sql
-- 波次主表
CREATE TABLE t_wave (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    wave_no VARCHAR(32) NOT NULL COMMENT '波次号',
    warehouse_id VARCHAR(32) NOT NULL,
    wave_type VARCHAR(16) NOT NULL COMMENT '波次类型',
    status VARCHAR(16) NOT NULL DEFAULT 'CREATED',
    order_count INT DEFAULT 0 COMMENT '订单数',
    sku_count INT DEFAULT 0 COMMENT 'SKU种类数',
    total_qty INT DEFAULT 0 COMMENT '总件数',
    picked_qty INT DEFAULT 0 COMMENT '已拣数量',
    start_time DATETIME,
    end_time DATETIME,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_wave_no (wave_no)
) ENGINE=InnoDB COMMENT='波次表';

-- 波次订单关联表
CREATE TABLE t_wave_order (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    wave_no VARCHAR(32) NOT NULL,
    outbound_no VARCHAR(32) NOT NULL COMMENT '出库单号',
    KEY idx_wave_no (wave_no),
    KEY idx_outbound_no (outbound_no)
) ENGINE=InnoDB COMMENT='波次订单关联';
```

### 2.4 波次生成服务

```java
@Service
public class WaveService {

    /**
     * 自动生成波次
     */
    public List<Wave> autoCreateWaves(String warehouseId, WaveStrategy strategy) {
        // 1. 获取待处理的出库单
        List<OutboundOrder> orders = outboundService.getPendingOrders(warehouseId);

        // 2. 按策略分组
        Map<String, List<OutboundOrder>> groups = groupByStrategy(orders, strategy);

        // 3. 生成波次
        List<Wave> waves = new ArrayList<>();
        for (Map.Entry<String, List<OutboundOrder>> entry : groups.entrySet()) {
            Wave wave = createWave(warehouseId, entry.getValue());
            waves.add(wave);
        }

        return waves;
    }

    private Map<String, List<OutboundOrder>> groupByStrategy(
            List<OutboundOrder> orders, WaveStrategy strategy) {

        switch (strategy.getType()) {
            case CARRIER:
                return orders.stream()
                    .collect(Collectors.groupingBy(OutboundOrder::getCarrierCode));

            case PRIORITY:
                return orders.stream()
                    .collect(Collectors.groupingBy(o -> o.getPriority().name()));

            case ZONE:
                return groupByZone(orders);

            case ORDER_TYPE:
                return orders.stream()
                    .collect(Collectors.groupingBy(this::getOrderType));

            default:
                // 默认按数量分组，每波最多100单
                return splitBySize(orders, 100);
        }
    }

    private String getOrderType(OutboundOrder order) {
        int skuCount = order.getItems().size();
        int totalQty = order.getItems().stream()
            .mapToInt(OutboundItem::getQuantity).sum();

        if (skuCount == 1 && totalQty == 1) {
            return "SINGLE_SINGLE"; // 单品单件
        } else if (skuCount == 1) {
            return "SINGLE_MULTI";  // 单品多件
        } else {
            return "MULTI";         // 多品
        }
    }
}
```

---

## 三、拣货任务生成

### 3.1 拣货任务模型

```sql
CREATE TABLE t_pick_task (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    task_no VARCHAR(32) NOT NULL COMMENT '任务单号',
    wave_no VARCHAR(32) NOT NULL COMMENT '波次号',
    warehouse_id VARCHAR(32) NOT NULL,
    pick_mode VARCHAR(16) NOT NULL COMMENT '拣货模式',
    status VARCHAR(16) NOT NULL DEFAULT 'PENDING',
    operator_id VARCHAR(32) COMMENT '拣货员',
    total_locations INT DEFAULT 0 COMMENT '库位数',
    total_qty INT DEFAULT 0 COMMENT '总件数',
    picked_qty INT DEFAULT 0 COMMENT '已拣数量',
    start_time DATETIME,
    end_time DATETIME,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_task_no (task_no)
) ENGINE=InnoDB COMMENT='拣货任务';

CREATE TABLE t_pick_item (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    task_no VARCHAR(32) NOT NULL,
    sku_id VARCHAR(32) NOT NULL,
    location_code VARCHAR(32) NOT NULL COMMENT '库位',
    quantity INT NOT NULL COMMENT '应拣数量',
    picked_qty INT DEFAULT 0 COMMENT '已拣数量',
    pick_order INT DEFAULT 0 COMMENT '拣货顺序',
    status VARCHAR(16) NOT NULL DEFAULT 'PENDING',
    KEY idx_task_no (task_no)
) ENGINE=InnoDB COMMENT='拣货明细';
```

### 3.2 拣货任务生成

```java
@Service
public class PickTaskService {

    public PickTask createPickTask(Wave wave) {
        // 1. 创建拣货任务
        PickTask task = new PickTask();
        task.setTaskNo(generateTaskNo());
        task.setWaveNo(wave.getWaveNo());
        task.setWarehouseId(wave.getWarehouseId());
        task.setPickMode(determinePickMode(wave));
        task.setStatus(TaskStatus.PENDING);

        // 2. 汇总拣货需求
        Map<String, Map<String, Integer>> pickRequirements =
            aggregatePickRequirements(wave);

        // 3. 分配库位库存
        List<PickItem> pickItems = allocateInventory(pickRequirements);

        // 4. 路径优化
        pickItems = optimizePath(pickItems);

        // 5. 设置拣货顺序
        for (int i = 0; i < pickItems.size(); i++) {
            pickItems.get(i).setPickOrder(i + 1);
        }

        // 6. 保存
        task.setTotalLocations(pickItems.size());
        task.setTotalQty(pickItems.stream().mapToInt(PickItem::getQuantity).sum());
        pickTaskRepository.save(task);

        for (PickItem item : pickItems) {
            item.setTaskNo(task.getTaskNo());
            pickItemRepository.save(item);
        }

        return task;
    }

    /**
     * 汇总拣货需求：SKU -> 库位 -> 数量
     */
    private Map<String, Map<String, Integer>> aggregatePickRequirements(Wave wave) {
        Map<String, Map<String, Integer>> result = new HashMap<>();

        List<OutboundOrder> orders = waveOrderService.getOrders(wave.getWaveNo());
        for (OutboundOrder order : orders) {
            for (OutboundItem item : order.getItems()) {
                result.computeIfAbsent(item.getSkuId(), k -> new HashMap<>());
                // 这里先按SKU汇总，后续再分配库位
            }
        }

        return result;
    }
}
```

---

## 四、路径优化算法

### 4.1 S型路径

**原理**：按巷道顺序，奇数巷道从前往后，偶数巷道从后往前

```
入口 ──> A01 ──> A02 ──> A03 ──> A04
                                  │
         B04 <── B03 <── B02 <── B01
         │
         C01 ──> C02 ──> C03 ──> C04
                                  │
                              出口 <──
```

```java
@Service
public class SShapePathOptimizer implements PathOptimizer {

    @Override
    public List<PickItem> optimize(List<PickItem> items) {
        // 按巷道分组
        Map<String, List<PickItem>> byAisle = items.stream()
            .collect(Collectors.groupingBy(PickItem::getAisle));

        List<PickItem> result = new ArrayList<>();
        List<String> aisles = new ArrayList<>(byAisle.keySet());
        Collections.sort(aisles);

        for (int i = 0; i < aisles.size(); i++) {
            String aisle = aisles.get(i);
            List<PickItem> aisleItems = byAisle.get(aisle);

            // 按库位排序
            aisleItems.sort(Comparator.comparing(PickItem::getLocationCode));

            // 偶数巷道反转
            if (i % 2 == 1) {
                Collections.reverse(aisleItems);
            }

            result.addAll(aisleItems);
        }

        return result;
    }
}
```

### 4.2 最短路径算法

**原理**：计算所有库位之间的距离，找最短路径

```java
@Service
public class ShortestPathOptimizer implements PathOptimizer {

    @Override
    public List<PickItem> optimize(List<PickItem> items) {
        if (items.size() <= 1) {
            return items;
        }

        // 使用贪心算法：每次选择最近的下一个库位
        List<PickItem> result = new ArrayList<>();
        Set<PickItem> remaining = new HashSet<>(items);

        // 从入口开始
        PickItem current = findNearestToEntrance(remaining);
        result.add(current);
        remaining.remove(current);

        while (!remaining.isEmpty()) {
            PickItem nearest = findNearest(current, remaining);
            result.add(nearest);
            remaining.remove(nearest);
            current = nearest;
        }

        return result;
    }

    private PickItem findNearest(PickItem from, Set<PickItem> candidates) {
        return candidates.stream()
            .min(Comparator.comparingDouble(c -> calculateDistance(from, c)))
            .orElse(null);
    }

    private double calculateDistance(PickItem a, PickItem b) {
        // 曼哈顿距离
        Location locA = parseLocation(a.getLocationCode());
        Location locB = parseLocation(b.getLocationCode());

        return Math.abs(locA.getX() - locB.getX())
             + Math.abs(locA.getY() - locB.getY());
    }
}
```

### 4.3 分区拣货

**原理**：将仓库分成多个区域，每个区域一个拣货员

```java
@Service
public class ZonePickService {

    public List<PickTask> createZoneTasks(Wave wave) {
        // 1. 获取拣货需求
        List<PickItem> allItems = generatePickItems(wave);

        // 2. 按库区分组
        Map<String, List<PickItem>> byZone = allItems.stream()
            .collect(Collectors.groupingBy(PickItem::getZone));

        // 3. 每个库区创建一个任务
        List<PickTask> tasks = new ArrayList<>();
        for (Map.Entry<String, List<PickItem>> entry : byZone.entrySet()) {
            PickTask task = new PickTask();
            task.setTaskNo(generateTaskNo());
            task.setWaveNo(wave.getWaveNo());
            task.setZone(entry.getKey());

            // 区内路径优化
            List<PickItem> optimized = pathOptimizer.optimize(entry.getValue());
            task.setItems(optimized);

            tasks.add(task);
        }

        return tasks;
    }
}
```

---

## 五、拣货执行

### 5.1 PDA拣货操作

```java
@RestController
@RequestMapping("/api/pda/pick")
public class PDAPickController {

    /**
     * 获取拣货任务
     */
    @GetMapping("/task")
    public Result<PickTaskVO> getTask(@RequestParam String operatorId) {
        PickTask task = pickTaskService.getAssignedTask(operatorId);
        if (task == null) {
            task = pickTaskService.assignTask(operatorId);
        }
        return Result.success(convertToVO(task));
    }

    /**
     * 获取下一个拣货位
     */
    @GetMapping("/next")
    public Result<PickItemVO> getNextItem(@RequestParam String taskNo) {
        PickItem item = pickItemService.getNextPending(taskNo);
        if (item == null) {
            return Result.success(null, "拣货完成");
        }
        return Result.success(convertToVO(item));
    }

    /**
     * 确认拣货
     */
    @PostMapping("/confirm")
    public Result<Void> confirmPick(@RequestBody PickConfirmRequest request) {
        // 1. 校验库位
        PickItem item = pickItemService.getById(request.getItemId());
        if (!item.getLocationCode().equals(request.getScannedLocation())) {
            return Result.fail("库位不匹配");
        }

        // 2. 校验SKU
        if (!item.getSkuId().equals(request.getScannedSku())) {
            return Result.fail("商品不匹配");
        }

        // 3. 校验数量
        if (request.getQuantity() > item.getQuantity() - item.getPickedQty()) {
            return Result.fail("拣货数量超出");
        }

        // 4. 更新拣货数量
        item.setPickedQty(item.getPickedQty() + request.getQuantity());
        if (item.getPickedQty().equals(item.getQuantity())) {
            item.setStatus(PickStatus.COMPLETED);
        }
        pickItemService.save(item);

        // 5. 扣减库存
        inventoryService.deductInventory(
            item.getWarehouseId(),
            item.getLocationCode(),
            item.getSkuId(),
            request.getQuantity()
        );

        return Result.success();
    }

    /**
     * 缺货上报
     */
    @PostMapping("/shortage")
    public Result<Void> reportShortage(@RequestBody ShortageRequest request) {
        PickItem item = pickItemService.getById(request.getItemId());

        // 记录缺货
        ShortageRecord record = new ShortageRecord();
        record.setTaskNo(item.getTaskNo());
        record.setSkuId(item.getSkuId());
        record.setLocationCode(item.getLocationCode());
        record.setExpectedQty(item.getQuantity());
        record.setActualQty(request.getActualQty());
        record.setShortageQty(item.getQuantity() - request.getActualQty());
        shortageService.save(record);

        // 更新拣货明细
        item.setPickedQty(request.getActualQty());
        item.setStatus(PickStatus.SHORTAGE);
        pickItemService.save(item);

        // 触发补货或重新分配
        shortageService.handleShortage(record);

        return Result.success();
    }
}
```

### 5.2 批量拣货与分拣

```java
@Service
public class BatchPickService {

    /**
     * 批量拣货后分拣
     */
    public void sortAfterPick(String taskNo) {
        PickTask task = pickTaskService.getByTaskNo(taskNo);
        Wave wave = waveService.getByWaveNo(task.getWaveNo());

        // 获取波次内的所有订单
        List<OutboundOrder> orders = waveOrderService.getOrders(wave.getWaveNo());

        // 生成分拣任务
        for (OutboundOrder order : orders) {
            SortTask sortTask = new SortTask();
            sortTask.setTaskNo(generateSortTaskNo());
            sortTask.setOrderNo(order.getOrderNo());
            sortTask.setWaveNo(wave.getWaveNo());

            // 设置分拣格口
            sortTask.setSlotNo(allocateSlot(order));

            sortTaskRepository.save(sortTask);
        }
    }

    /**
     * 分配分拣格口
     */
    private String allocateSlot(OutboundOrder order) {
        // 简单策略：按订单号hash分配
        int slotCount = 50; // 假设有50个格口
        int slot = Math.abs(order.getOrderNo().hashCode()) % slotCount + 1;
        return String.format("S%02d", slot);
    }
}
```

---

## 六、播种式拣货

### 6.1 播种式流程

```
汇总拣货 ──> 集中拣货 ──> 播种分拣 ──> 复核打包
    │           │           │           │
    ▼           ▼           ▼           ▼
按SKU汇总   一次拣完    分到各订单   逐单复核
```

### 6.2 播种墙设计

```sql
CREATE TABLE t_seeding_wall (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    wall_code VARCHAR(32) NOT NULL COMMENT '播种墙编码',
    warehouse_id VARCHAR(32) NOT NULL,
    slot_count INT NOT NULL COMMENT '格口数量',
    status VARCHAR(16) NOT NULL DEFAULT 'IDLE',
    current_wave VARCHAR(32) COMMENT '当前波次',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB COMMENT='播种墙';

CREATE TABLE t_seeding_slot (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    wall_code VARCHAR(32) NOT NULL,
    slot_no VARCHAR(8) NOT NULL COMMENT '格口号',
    order_no VARCHAR(32) COMMENT '绑定订单',
    status VARCHAR(16) NOT NULL DEFAULT 'EMPTY',
    KEY idx_wall (wall_code)
) ENGINE=InnoDB COMMENT='播种格口';
```

### 6.3 播种服务实现

```java
@Service
public class SeedingService {

    /**
     * 初始化播种墙
     */
    public void initWall(String wallCode, String waveNo) {
        SeedingWall wall = wallRepository.findByCode(wallCode);
        Wave wave = waveService.getByWaveNo(waveNo);

        // 获取波次订单
        List<OutboundOrder> orders = waveOrderService.getOrders(waveNo);

        if (orders.size() > wall.getSlotCount()) {
            throw new BusinessException("订单数超过格口数");
        }

        // 绑定订单到格口
        List<SeedingSlot> slots = slotRepository.findByWall(wallCode);
        for (int i = 0; i < orders.size(); i++) {
            SeedingSlot slot = slots.get(i);
            slot.setOrderNo(orders.get(i).getOrderNo());
            slot.setStatus(SlotStatus.BINDIED);
            slotRepository.save(slot);
        }

        wall.setCurrentWave(waveNo);
        wall.setStatus(WallStatus.IN_USE);
        wallRepository.save(wall);
    }

    /**
     * 播种操作
     */
    public SeedResult seed(String wallCode, String skuId, int quantity) {
        SeedingWall wall = wallRepository.findByCode(wallCode);

        // 找到需要该SKU的格口
        List<SeedingSlot> targetSlots = findSlotsNeedSku(wall, skuId);

        SeedResult result = new SeedResult();
        int remainQty = quantity;

        for (SeedingSlot slot : targetSlots) {
            if (remainQty <= 0) break;

            // 获取该订单需要的数量
            int needQty = getOrderNeedQty(slot.getOrderNo(), skuId);
            int seedQty = Math.min(needQty, remainQty);

            // 播种
            result.addSeedAction(slot.getSlotNo(), seedQty);
            remainQty -= seedQty;

            // 更新订单拣货状态
            updateOrderPickStatus(slot.getOrderNo(), skuId, seedQty);
        }

        if (remainQty > 0) {
            result.setRemainQty(remainQty);
            result.setMessage("有剩余，请检查");
        }

        return result;
    }
}
```

---

## 七、拣货效率监控

### 7.1 关键指标

| 指标 | 计算方式 | 目标值 |
|-----|---------|-------|
| 拣货效率 | 件数/小时 | > 150件/小时 |
| 拣货准确率 | 正确件数/总件数 | > 99.9% |
| 行走距离 | 总行走米数/件数 | < 5米/件 |
| 任务完成率 | 完成任务数/总任务数 | > 98% |

### 7.2 效率统计

```java
@Service
public class PickEfficiencyService {

    public PickEfficiencyReport generateReport(String warehouseId, LocalDate date) {
        // 获取当日完成的拣货任务
        List<PickTask> tasks = pickTaskRepository.findCompletedByDate(warehouseId, date);

        PickEfficiencyReport report = new PickEfficiencyReport();
        report.setDate(date);
        report.setWarehouseId(warehouseId);

        // 统计总体数据
        int totalTasks = tasks.size();
        int totalQty = tasks.stream().mapToInt(PickTask::getPickedQty).sum();
        long totalMinutes = tasks.stream()
            .mapToLong(t -> Duration.between(t.getStartTime(), t.getEndTime()).toMinutes())
            .sum();

        report.setTotalTasks(totalTasks);
        report.setTotalQty(totalQty);
        report.setTotalHours(totalMinutes / 60.0);
        report.setAvgEfficiency(totalQty / (totalMinutes / 60.0)); // 件/小时

        // 按拣货员统计
        Map<String, List<PickTask>> byOperator = tasks.stream()
            .collect(Collectors.groupingBy(PickTask::getOperatorId));

        List<OperatorEfficiency> operatorStats = new ArrayList<>();
        for (Map.Entry<String, List<PickTask>> entry : byOperator.entrySet()) {
            OperatorEfficiency stat = calculateOperatorEfficiency(entry.getKey(), entry.getValue());
            operatorStats.add(stat);
        }

        report.setOperatorStats(operatorStats);
        return report;
    }
}
```

---

## 八、常见问题与优化

### 8.1 热门库位拥堵

**问题**：爆款商品库位拣货员扎堆

**解决方案**：
```java
// 分散存储：同一SKU存放在多个库位
@Service
public class InventoryDispersionService {

    public void disperseHotSku(String skuId, String warehouseId) {
        // 获取当前库存分布
        List<LocationInventory> inventories =
            inventoryRepository.findBySku(warehouseId, skuId);

        // 如果只在1-2个库位，需要分散
        if (inventories.size() < 3) {
            // 找到空库位
            List<String> emptyLocations =
                locationService.findEmptyInDifferentZones(warehouseId, 3);

            // 调拨分散
            for (String location : emptyLocations) {
                transferService.createTransfer(
                    inventories.get(0).getLocationCode(),
                    location,
                    skuId,
                    calculateTransferQty(inventories.get(0))
                );
            }
        }
    }
}
```

### 8.2 拣货路径过长

**问题**：波次内SKU分布太散

**解决方案**：
```java
// 波次优化：按库区聚合
public List<Wave> optimizeWaveByZone(List<OutboundOrder> orders) {
    // 分析每个订单的库区分布
    Map<OutboundOrder, Set<String>> orderZones = new HashMap<>();
    for (OutboundOrder order : orders) {
        Set<String> zones = analyzeOrderZones(order);
        orderZones.put(order, zones);
    }

    // 按库区相似度聚类
    return clusterByZoneSimilarity(orderZones);
}
```

---

## 九、总结

### 9.1 拣货优化核心要点

1. **波次策略**：合理分组，减少重复
2. **路径优化**：S型或最短路径
3. **模式选择**：根据订单特征选择拣货模式
4. **实时监控**：及时发现效率问题

### 9.2 效率提升效果

| 优化项 | 提升效果 |
|-------|---------|
| 波次合并 | 效率提升30% |
| 路径优化 | 行走距离减少40% |
| 播种式拣货 | 大促效率提升100% |
| 分区拣货 | 减少拥堵50% |

---

> **系列文章导航**
>
> 本文是《跨境电商数字化转型指南》系列的第20篇
>
> - [x] 18. WMS仓储系统架构设计
> - [x] 19. WMS入库管理详解
> - [x] 20. WMS拣货策略优化（本文）
> - [ ] 21. WMS库存盘点实战
