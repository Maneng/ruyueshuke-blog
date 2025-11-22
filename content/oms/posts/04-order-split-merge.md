---
title: "订单拆分与合并策略：复杂场景下的智能决策"
date: 2025-11-22T10:30:00+08:00
draft: false
tags: ["OMS", "订单拆分", "订单合并", "算法设计", "电商系统"]
categories: ["技术"]
description: "深入解析订单拆分与合并的业务场景、算法设计和实现策略，探讨如何在保证用户体验的同时优化运营成本"
series: ["OMS订单管理系统"]
weight: 4
stage: 2
stageTitle: "核心功能篇"
---

## 引言

在电商场景中，一个看似简单的订单可能面临复杂的履约挑战：商品分布在不同仓库、部分商品是预售、有些需要跨境发货。这时，订单拆分与合并就成为OMS系统的核心能力。

订单拆分与合并不仅仅是技术问题，更是业务策略问题。拆得太细，物流成本高、用户体验差；合得太粗，库存利用率低、发货时效慢。如何在成本、时效、体验之间找到最优解？本文将从第一性原理出发，系统性地探讨这个问题。

## 为什么需要订单拆分？

### 业务驱动因素

订单拆分的本质是**将一个逻辑订单按照履约能力拆分成多个物理订单**。驱动因素包括：

**1. 库存分布不一致**
```
用户订单：
- 商品A × 2（华东仓有货）
- 商品B × 1（华南仓有货）
- 商品C × 1（华北仓有货）

拆分策略：按仓库拆分成3个子订单
```

**2. 商品属性差异**
```
用户订单：
- 普通商品（现货）
- 预售商品（7天后发货）
- 大件商品（需要专门配送）

拆分策略：按发货时效和物流方式拆分
```

**3. 跨境与国内混合**
```
用户订单：
- 国内商品（保税仓）
- 跨境商品（海外直邮）

拆分策略：按清关类型拆分
```

### 拆分的核心目标

1. **最大化履约效率**：让每个子订单都能快速发货
2. **优化物流成本**：减少不必要的拆分
3. **保障用户体验**：透明化拆分信息，合理预期
4. **提高库存周转**：优先消化滞销库存

## 订单拆分的典型场景

### 场景1：跨仓拆分

**业务场景**：
用户购买了3件商品，分别在上海仓、北京仓、广州仓有库存。

**拆分策略**：
```python
class CrossWarehouseSplitStrategy:
    """跨仓拆分策略"""

    def split(self, order, inventory_map):
        """
        按仓库拆分订单

        Args:
            order: 原始订单
            inventory_map: {sku_id: [warehouse_id, stock]}

        Returns:
            List[SubOrder]: 子订单列表
        """
        # 按仓库分组商品
        warehouse_groups = defaultdict(list)
        for item in order.items:
            warehouse_id = self._find_best_warehouse(
                item.sku_id,
                item.quantity,
                inventory_map,
                order.delivery_address
            )
            warehouse_groups[warehouse_id].append(item)

        # 生成子订单
        sub_orders = []
        for warehouse_id, items in warehouse_groups.items():
            sub_order = self._create_sub_order(
                parent_order=order,
                warehouse_id=warehouse_id,
                items=items
            )
            sub_orders.append(sub_order)

        return sub_orders

    def _find_best_warehouse(self, sku_id, quantity,
                            inventory_map, delivery_address):
        """选择最优仓库"""
        available_warehouses = [
            (wh_id, stock)
            for wh_id, stock in inventory_map.get(sku_id, [])
            if stock >= quantity
        ]

        if not available_warehouses:
            raise InsufficientStockException(sku_id)

        # 按距离排序，选择最近的仓库
        return self._sort_by_distance(
            available_warehouses,
            delivery_address
        )[0][0]
```

**关键决策点**：
- 是否允许单个SKU从多个仓库发货？
- 如何权衡距离和库存成本？
- 拆分后的运费如何分摊？

### 场景2：预售与现货混合

**业务场景**：
订单中既有现货商品，也有预售商品（7天后发货）。

**拆分策略**：
```python
class PresaleNormalSplitStrategy:
    """预售与现货拆分策略"""

    def split(self, order):
        """按商品可发货时间拆分"""
        presale_items = []
        normal_items = []

        for item in order.items:
            if item.is_presale:
                presale_items.append(item)
            else:
                normal_items.append(item)

        sub_orders = []

        # 现货子订单
        if normal_items:
            sub_orders.append(self._create_sub_order(
                parent_order=order,
                items=normal_items,
                expected_ship_time=datetime.now() + timedelta(hours=24)
            ))

        # 预售子订单
        if presale_items:
            # 按预售批次分组
            presale_groups = self._group_by_presale_batch(presale_items)
            for batch_id, items in presale_groups.items():
                sub_orders.append(self._create_sub_order(
                    parent_order=order,
                    items=items,
                    expected_ship_time=self._get_presale_ship_time(batch_id)
                ))

        return sub_orders
```

**用户体验优化**：
```json
{
  "order_id": "O123456",
  "split_info": {
    "total_packages": 2,
    "packages": [
      {
        "package_id": "P1",
        "status": "已发货",
        "ship_time": "2025-11-22 10:00:00",
        "items": ["商品A", "商品B"]
      },
      {
        "package_id": "P2",
        "status": "预售中",
        "expected_ship_time": "2025-11-29 10:00:00",
        "items": ["商品C（预售）"]
      }
    ]
  }
}
```

### 场景3：跨品类拆分

**业务场景**：
订单中包含不同配送要求的商品（如生鲜、大家电、普通商品）。

**拆分策略**：
```python
class CategoryBasedSplitStrategy:
    """基于品类的拆分策略"""

    # 品类配送规则
    CATEGORY_RULES = {
        'FRESH': {
            'delivery_type': 'cold_chain',
            'max_delivery_hours': 24,
            'require_signature': True
        },
        'LARGE_APPLIANCE': {
            'delivery_type': 'installation',
            'require_appointment': True,
            'insurance_required': True
        },
        'NORMAL': {
            'delivery_type': 'standard',
            'max_delivery_days': 3
        }
    }

    def split(self, order):
        """按品类拆分"""
        category_groups = defaultdict(list)

        for item in order.items:
            category = self._get_category_type(item)
            category_groups[category].append(item)

        sub_orders = []
        for category, items in category_groups.items():
            delivery_config = self.CATEGORY_RULES[category]
            sub_order = self._create_sub_order(
                parent_order=order,
                items=items,
                delivery_type=delivery_config['delivery_type'],
                service_options=delivery_config
            )
            sub_orders.append(sub_order)

        return sub_orders
```

## 订单拆分算法设计

### 最优拆分算法

订单拆分是一个多目标优化问题，需要在以下目标之间平衡：

```
目标函数 = α × 物流成本 + β × 发货时效 + γ × 用户体验

约束条件：
1. 库存约束：每个SKU的分配数量 ≤ 可用库存
2. 仓库约束：同一子订单的商品必须来自同一仓库
3. 物流约束：同一子订单的商品必须使用相同物流方式
4. 时效约束：满足用户期望的发货时间
```

**贪心算法实现**：
```python
class OptimalSplitAlgorithm:
    """最优拆分算法"""

    def __init__(self, alpha=0.4, beta=0.3, gamma=0.3):
        self.alpha = alpha  # 成本权重
        self.beta = beta    # 时效权重
        self.gamma = gamma  # 体验权重

    def split(self, order, inventory_service):
        """
        最优拆分算法

        核心思想：
        1. 优先尝试不拆分（单仓发货）
        2. 如果必须拆分，尽量减少拆分数量
        3. 在满足约束的前提下，选择成本最低的方案
        """
        # 1. 尝试单仓发货
        single_warehouse_plan = self._try_single_warehouse(
            order, inventory_service
        )
        if single_warehouse_plan:
            return [single_warehouse_plan]

        # 2. 计算所有可行的拆分方案
        feasible_plans = self._generate_feasible_plans(
            order, inventory_service
        )

        # 3. 评估每个方案的综合得分
        scored_plans = [
            (plan, self._calculate_score(plan, order))
            for plan in feasible_plans
        ]

        # 4. 选择最优方案
        best_plan = max(scored_plans, key=lambda x: x[1])[0]

        return best_plan

    def _calculate_score(self, plan, order):
        """计算拆分方案的综合得分"""
        # 成本评分：包裹数越少越好
        cost_score = 1.0 / len(plan.sub_orders)

        # 时效评分：最晚发货时间越早越好
        max_ship_time = max(so.expected_ship_time for so in plan.sub_orders)
        time_delta = (max_ship_time - datetime.now()).total_seconds() / 3600
        time_score = 1.0 / (1 + time_delta / 24)

        # 体验评分：拆分越少越好
        if len(plan.sub_orders) == 1:
            experience_score = 1.0
        elif len(plan.sub_orders) == 2:
            experience_score = 0.7
        else:
            experience_score = 0.4

        # 综合得分
        total_score = (
            self.alpha * cost_score +
            self.beta * time_score +
            self.gamma * experience_score
        )

        return total_score
```

### 动态规划优化

对于复杂场景，可以使用动态规划求解最优拆分：

```python
class DynamicProgrammingSplitter:
    """动态规划拆分算法"""

    def split(self, order, warehouses):
        """
        使用动态规划求解最优拆分

        状态定义：
        dp[i][j] = 前i件商品，使用前j个仓库，最小拆分成本

        状态转移：
        dp[i][j] = min(
            dp[i-1][j],  # 不使用第j个仓库
            dp[k][j-1] + cost(k+1, i, j)  # 使用第j个仓库发货商品k+1到i
        )
        """
        n = len(order.items)
        m = len(warehouses)

        # 初始化DP表
        dp = [[float('inf')] * (m + 1) for _ in range(n + 1)]
        dp[0][0] = 0

        # 动态规划求解
        for i in range(1, n + 1):
            for j in range(1, m + 1):
                # 不使用第j个仓库
                dp[i][j] = dp[i][j-1]

                # 尝试使用第j个仓库发货部分商品
                for k in range(i):
                    items = order.items[k:i]
                    if self._can_fulfill(items, warehouses[j-1]):
                        cost = self._calculate_fulfillment_cost(
                            items, warehouses[j-1], order.delivery_address
                        )
                        dp[i][j] = min(
                            dp[i][j],
                            dp[k][j-1] + cost
                        )

        # 回溯构建拆分方案
        return self._backtrack_solution(dp, order, warehouses)
```

## 订单合并场景与策略

### 为什么需要订单合并？

**成本优化**：
- 减少包裹数量，降低物流成本
- 提高打包效率
- 减少仓库操作次数

**用户体验**：
- 减少收货次数
- 降低丢件风险

### 合并触发条件

```python
class OrderMergeCondition:
    """订单合并条件判断"""

    @staticmethod
    def can_merge(order1, order2):
        """判断两个订单是否可以合并"""
        conditions = [
            # 1. 同一用户
            order1.user_id == order2.user_id,

            # 2. 相同收货地址
            order1.delivery_address == order2.delivery_address,

            # 3. 同一仓库
            order1.warehouse_id == order2.warehouse_id,

            # 4. 时间窗口内（如30分钟内下单）
            abs((order1.create_time - order2.create_time).seconds) < 1800,

            # 5. 未开始拣货
            order1.status in ['PENDING', 'PAID'],
            order2.status in ['PENDING', 'PAID'],

            # 6. 相同配送方式
            order1.delivery_type == order2.delivery_type,

            # 7. 无特殊要求（如礼品包装）
            not order1.has_special_requirement,
            not order2.has_special_requirement
        ]

        return all(conditions)
```

### 合并策略实现

```python
class OrderMergeService:
    """订单合并服务"""

    def __init__(self, merge_window_seconds=1800):
        self.merge_window = merge_window_seconds

    def find_mergeable_orders(self, new_order):
        """查找可合并的订单"""
        # 查询时间窗口内的待处理订单
        candidate_orders = self.order_repo.find_pending_orders(
            user_id=new_order.user_id,
            warehouse_id=new_order.warehouse_id,
            delivery_address=new_order.delivery_address,
            time_window=self.merge_window
        )

        # 过滤可合并的订单
        mergeable = []
        for order in candidate_orders:
            if OrderMergeCondition.can_merge(new_order, order):
                mergeable.append(order)

        return mergeable

    def merge_orders(self, orders):
        """合并多个订单"""
        if len(orders) < 2:
            return orders[0]

        # 创建合并订单
        merged_order = Order(
            user_id=orders[0].user_id,
            delivery_address=orders[0].delivery_address,
            warehouse_id=orders[0].warehouse_id,
            items=[],
            merged_from=[o.order_id for o in orders]
        )

        # 合并商品项
        item_map = defaultdict(int)
        for order in orders:
            for item in order.items:
                item_map[item.sku_id] += item.quantity

        for sku_id, quantity in item_map.items():
            merged_order.add_item(sku_id, quantity)

        # 更新原订单状态
        for order in orders:
            order.status = 'MERGED'
            order.merged_to = merged_order.order_id
            self.order_repo.update(order)

        # 保存合并订单
        self.order_repo.save(merged_order)

        return merged_order
```

## 拆分合并的数据一致性保障

### 分布式事务处理

```python
class OrderSplitTransaction:
    """订单拆分事务管理"""

    def execute_split(self, order, split_plan):
        """
        使用Saga模式保证拆分的数据一致性

        步骤：
        1. 创建子订单
        2. 预占库存
        3. 更新父订单状态
        4. 发送拆分通知
        """
        saga = SagaOrchestrator()

        try:
            # Step 1: 创建子订单
            sub_orders = saga.execute_step(
                forward=lambda: self._create_sub_orders(split_plan),
                compensate=lambda so: self._delete_sub_orders(so)
            )

            # Step 2: 预占库存
            reservations = saga.execute_step(
                forward=lambda: self._reserve_inventory(sub_orders),
                compensate=lambda res: self._release_inventory(res)
            )

            # Step 3: 更新父订单
            saga.execute_step(
                forward=lambda: self._update_parent_order(order, 'SPLIT'),
                compensate=lambda: self._update_parent_order(order, 'PENDING')
            )

            # Step 4: 发送通知
            saga.execute_step(
                forward=lambda: self._notify_user(order, sub_orders),
                compensate=lambda: None  # 通知无需补偿
            )

            saga.commit()
            return sub_orders

        except Exception as e:
            saga.rollback()
            raise OrderSplitException(f"订单拆分失败: {str(e)}")
```

### 幂等性保证

```python
class IdempotentSplitter:
    """幂等性拆分器"""

    def split_order(self, order_id, idempotency_key):
        """
        幂等性拆分

        使用Redis存储拆分结果，避免重复拆分
        """
        # 检查是否已拆分
        cache_key = f"order:split:{order_id}:{idempotency_key}"
        cached_result = self.redis.get(cache_key)

        if cached_result:
            return json.loads(cached_result)

        # 执行拆分
        with self.redis.lock(f"lock:order:split:{order_id}"):
            # 双重检查
            cached_result = self.redis.get(cache_key)
            if cached_result:
                return json.loads(cached_result)

            # 执行拆分逻辑
            result = self._do_split(order_id)

            # 缓存结果（24小时）
            self.redis.setex(
                cache_key,
                86400,
                json.dumps(result)
            )

            return result
```

## 实战案例：大促期间的订单拆分

### 双11场景挑战

**问题**：
- 订单量暴增（平时10倍）
- 部分商品库存紧张
- 用户对时效要求高
- 系统负载接近极限

**解决方案**：

```python
class PromotionSplitStrategy:
    """大促拆分策略"""

    def __init__(self):
        # 预热期规则：优先保证单仓发货
        self.preheat_rules = {
            'max_split': 2,  # 最多拆2个包裹
            'prefer_nearby': True,  # 优先就近仓库
            'allow_partial': False  # 不允许部分发货
        }

        # 爆发期规则：优先保证发货
        self.burst_rules = {
            'max_split': 5,  # 可拆分更多包裹
            'prefer_stock': True,  # 优先有货仓库
            'allow_partial': True  # 允许部分发货
        }

    def split(self, order, current_phase):
        """根据大促阶段动态调整拆分策略"""
        rules = (
            self.burst_rules
            if current_phase == 'BURST'
            else self.preheat_rules
        )

        # 1. 智能库存分配
        allocation = self._smart_allocate(order, rules)

        # 2. 生成拆分方案
        split_plan = self._generate_plan(allocation, rules)

        # 3. 限流保护
        if len(split_plan.sub_orders) > rules['max_split']:
            raise TooManySplitsException(
                f"拆分数超过限制: {rules['max_split']}"
            )

        return split_plan

    def _smart_allocate(self, order, rules):
        """智能库存分配"""
        allocation = {}

        for item in order.items:
            # 查询实时库存
            stocks = self.inventory_service.get_available_stock(
                item.sku_id,
                near_address=order.delivery_address
            )

            if rules['prefer_stock']:
                # 优先库存充足的仓库
                stocks.sort(key=lambda x: x.quantity, reverse=True)
            elif rules['prefer_nearby']:
                # 优先距离近的仓库
                stocks.sort(key=lambda x: x.distance)

            # 分配库存
            remaining = item.quantity
            for stock in stocks:
                if remaining <= 0:
                    break

                alloc_qty = min(remaining, stock.quantity)
                allocation[(item.sku_id, stock.warehouse_id)] = alloc_qty
                remaining -= alloc_qty

            # 检查是否满足
            if remaining > 0 and not rules['allow_partial']:
                raise InsufficientStockException(item.sku_id)

        return allocation
```

### 监控指标

```python
class SplitMetricsCollector:
    """拆分指标收集器"""

    def collect_metrics(self, split_result):
        """收集拆分指标"""
        metrics = {
            # 拆分率
            'split_rate': self._calculate_split_rate(),

            # 平均拆分数
            'avg_splits': self._calculate_avg_splits(),

            # 拆分耗时
            'split_duration': split_result.duration_ms,

            # 库存命中率
            'inventory_hit_rate': self._calculate_hit_rate(),

            # 成本增加比例
            'cost_increase': self._calculate_cost_increase(),

            # 用户投诉率
            'complaint_rate': self._calculate_complaint_rate()
        }

        # 上报监控系统
        self.monitor.report(metrics)

        # 告警检查
        if metrics['split_rate'] > 0.5:
            self.alert.send(
                "订单拆分率过高",
                f"当前拆分率: {metrics['split_rate']:.2%}"
            )
```

## 总结

订单拆分与合并是OMS系统的核心能力，直接影响履约效率和用户体验。关键要点：

1. **业务驱动**：拆分合并的根本目的是优化履约效率，而非技术炫技
2. **算法优化**：使用贪心、动态规划等算法寻找最优解
3. **数据一致性**：使用Saga模式、幂等性设计保证分布式事务
4. **动态策略**：根据业务场景（如大促）动态调整拆分规则
5. **监控告警**：实时监控拆分指标，及时发现和解决问题

下一篇文章，我们将深入探讨**库存预占与释放机制**，这是订单拆分的基础能力。

---

**关键词**：订单拆分、订单合并、库存分配、动态规划、分布式事务、Saga模式、电商OMS
