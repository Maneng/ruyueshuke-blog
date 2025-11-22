---
title: "库存预占与释放机制：高并发下的库存一致性保障"
date: 2025-11-22T11:00:00+08:00
draft: false
tags: ["OMS", "库存管理", "分布式锁", "并发控制", "Redis"]
categories: ["技术"]
description: "深入解析库存预占的原理、流程设计和并发控制策略，探讨如何在高并发场景下保证库存数据的强一致性"
series: ["OMS订单管理系统"]
weight: 5
stage: 2
stageTitle: "核心功能篇"
---

## 引言

想象这样一个场景：用户在购物车中看到商品显示"有货"，提交订单时却提示"库存不足"。或者更糟糕的情况：订单已支付，仓库却发现没有库存可发货。这些问题的根源都指向一个核心能力：**库存预占**。

库存预占是OMS系统的生命线。它要解决的核心问题是：在下单到发货的整个周期内，如何保证已承诺给用户的商品库存不被其他订单抢走？本文将从第一性原理出发，系统性地探讨库存预占与释放机制的设计与实现。

## 库存预占的本质

### 什么是库存预占？

库存预占（Inventory Reservation）是指**在订单创建时，为订单中的商品临时锁定库存，防止被其他订单占用**。

```
库存状态转换：
可用库存 → 预占库存 → 已出库
   ↓
 释放回可用（订单取消）
```

### 为什么需要库存预占？

**场景1：下单到支付的时间窗口**
```
用户操作流程：
1. 加入购物车（不预占）
2. 提交订单（预占库存）← 关键点
3. 支付（15分钟内）
4. 发货

问题：如果不预占，步骤2到步骤3之间，库存可能被其他用户购买
```

**场景2：支付到发货的时间窗口**
```
订单处理流程：
1. 用户支付成功
2. 订单进入待发货队列
3. 仓库拣货打包（可能需要几小时）
4. 发货

问题：如果不预占，步骤1到步骤4之间，库存可能被超卖
```

**场景3：高并发秒杀**
```
秒杀场景：
- 库存：100件
- 请求：10000个并发请求
- 目标：保证只有前100个请求成功，且不超卖

核心挑战：如何在毫秒级时间内准确预占库存？
```

### 库存预占的核心目标

1. **防止超卖**：已售数量 ≤ 实际库存
2. **保证时效**：预占操作要快（毫秒级）
3. **支持释放**：订单取消/超时后自动释放
4. **高并发**：支持万级QPS的库存预占
5. **数据一致性**：分布式环境下保证强一致性

## 库存预占流程设计

### 标准预占流程

```python
class InventoryReservationService:
    """库存预占服务"""

    def reserve(self, order):
        """
        预占库存的标准流程

        1. 校验库存可用性
        2. 锁定库存
        3. 扣减可用库存
        4. 增加预占库存
        5. 记录预占日志
        """
        try:
            # 1. 校验库存
            self._validate_inventory(order)

            # 2. 获取分布式锁
            lock = self._acquire_lock(order.items)

            # 3. 执行预占
            reservations = []
            for item in order.items:
                reservation = self._reserve_single_item(
                    sku_id=item.sku_id,
                    warehouse_id=item.warehouse_id,
                    quantity=item.quantity,
                    order_id=order.order_id
                )
                reservations.append(reservation)

            # 4. 释放锁
            self._release_lock(lock)

            return ReservationResult(
                success=True,
                reservations=reservations
            )

        except InsufficientStockException as e:
            return ReservationResult(
                success=False,
                error=str(e)
            )

    def _reserve_single_item(self, sku_id, warehouse_id,
                            quantity, order_id):
        """预占单个SKU的库存"""
        # 原子操作：扣减可用库存，增加预占库存
        with self.db.transaction():
            # 1. 查询当前库存（加行锁）
            inventory = self.db.query(
                """
                SELECT available, reserved
                FROM inventory
                WHERE sku_id = %s AND warehouse_id = %s
                FOR UPDATE
                """,
                (sku_id, warehouse_id)
            )

            # 2. 检查库存充足性
            if inventory.available < quantity:
                raise InsufficientStockException(
                    f"SKU {sku_id} 库存不足"
                )

            # 3. 更新库存
            self.db.execute(
                """
                UPDATE inventory
                SET available = available - %s,
                    reserved = reserved + %s
                WHERE sku_id = %s AND warehouse_id = %s
                """,
                (quantity, quantity, sku_id, warehouse_id)
            )

            # 4. 记录预占记录
            reservation = InventoryReservation(
                reservation_id=generate_id(),
                order_id=order_id,
                sku_id=sku_id,
                warehouse_id=warehouse_id,
                quantity=quantity,
                status='RESERVED',
                expire_at=datetime.now() + timedelta(minutes=30)
            )
            self.db.insert('inventory_reservations', reservation)

            return reservation
```

### 数据库设计

```sql
-- 库存表
CREATE TABLE inventory (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    sku_id VARCHAR(64) NOT NULL,
    warehouse_id VARCHAR(64) NOT NULL,
    available INT NOT NULL DEFAULT 0,      -- 可用库存
    reserved INT NOT NULL DEFAULT 0,       -- 预占库存
    sold INT NOT NULL DEFAULT 0,           -- 已售库存
    total INT NOT NULL DEFAULT 0,          -- 总库存
    version INT NOT NULL DEFAULT 0,        -- 乐观锁版本号
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL,
    UNIQUE KEY uk_sku_warehouse (sku_id, warehouse_id),
    INDEX idx_sku (sku_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 库存预占记录表
CREATE TABLE inventory_reservations (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    reservation_id VARCHAR(64) NOT NULL UNIQUE,
    order_id VARCHAR(64) NOT NULL,
    sku_id VARCHAR(64) NOT NULL,
    warehouse_id VARCHAR(64) NOT NULL,
    quantity INT NOT NULL,
    status VARCHAR(32) NOT NULL,           -- RESERVED, CONSUMED, RELEASED
    expire_at DATETIME NOT NULL,           -- 预占过期时间
    created_at DATETIME NOT NULL,
    released_at DATETIME,
    INDEX idx_order (order_id),
    INDEX idx_expire (expire_at, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 库存变更日志表
CREATE TABLE inventory_change_logs (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    log_id VARCHAR(64) NOT NULL UNIQUE,
    sku_id VARCHAR(64) NOT NULL,
    warehouse_id VARCHAR(64) NOT NULL,
    change_type VARCHAR(32) NOT NULL,      -- RESERVE, RELEASE, CONSUME
    quantity INT NOT NULL,
    before_available INT NOT NULL,
    after_available INT NOT NULL,
    order_id VARCHAR(64),
    created_at DATETIME NOT NULL,
    INDEX idx_sku (sku_id),
    INDEX idx_order (order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

## 库存预占失败处理

### 失败场景分类

```python
class ReservationFailureHandler:
    """预占失败处理器"""

    def handle_failure(self, order, failure_reason):
        """处理预占失败"""
        if isinstance(failure_reason, InsufficientStockException):
            return self._handle_insufficient_stock(order)
        elif isinstance(failure_reason, DistributedLockException):
            return self._handle_lock_timeout(order)
        elif isinstance(failure_reason, DatabaseException):
            return self._handle_db_error(order)
        else:
            return self._handle_unknown_error(order)

    def _handle_insufficient_stock(self, order):
        """处理库存不足"""
        # 1. 尝试部分预占
        partial_result = self._try_partial_reservation(order)
        if partial_result.has_available_items():
            return self._create_partial_order(
                order,
                partial_result.available_items
            )

        # 2. 尝试跨仓调拨
        transfer_result = self._try_warehouse_transfer(order)
        if transfer_result.success:
            return self._retry_reservation(order)

        # 3. 推荐替代商品
        alternatives = self._find_alternatives(order)
        return ReservationResult(
            success=False,
            error="库存不足",
            alternatives=alternatives
        )

    def _handle_lock_timeout(self, order):
        """处理锁超时"""
        # 重试策略：指数退避
        for retry in range(3):
            time.sleep(0.1 * (2 ** retry))  # 100ms, 200ms, 400ms
            try:
                return self.reservation_service.reserve(order)
            except DistributedLockException:
                continue

        # 降级策略：异步处理
        return self._async_reservation(order)
```

### 部分预占策略

```python
class PartialReservationStrategy:
    """部分预占策略"""

    def try_partial_reservation(self, order):
        """尝试部分预占"""
        available_items = []
        unavailable_items = []

        for item in order.items:
            try:
                # 尝试预占单个商品
                reservation = self.reservation_service.reserve_single_item(
                    item
                )
                available_items.append(item)
            except InsufficientStockException:
                unavailable_items.append(item)

        return PartialReservationResult(
            available_items=available_items,
            unavailable_items=unavailable_items,
            fulfillment_rate=len(available_items) / len(order.items)
        )

    def should_accept_partial(self, result, order):
        """判断是否接受部分预占"""
        # 策略1：订单金额超过阈值，接受部分预占
        if order.total_amount > 500 and result.fulfillment_rate > 0.8:
            return True

        # 策略2：重要商品都有货，接受部分预占
        critical_items = [i for i in order.items if i.is_critical]
        if all(i in result.available_items for i in critical_items):
            return True

        # 策略3：用户设置允许部分发货
        if order.allow_partial_shipment:
            return True

        return False
```

## 库存释放触发条件

### 自动释放场景

```python
class InventoryReleaseService:
    """库存释放服务"""

    def __init__(self):
        # 定义释放规则
        self.release_rules = [
            # 规则1：订单取消
            ReleaseRule(
                name="order_cancelled",
                condition=lambda order: order.status == 'CANCELLED',
                action=self._release_all
            ),
            # 规则2：支付超时
            ReleaseRule(
                name="payment_timeout",
                condition=lambda order: (
                    order.status == 'PENDING_PAYMENT' and
                    datetime.now() > order.payment_deadline
                ),
                action=self._release_all
            ),
            # 规则3：部分退货
            ReleaseRule(
                name="partial_refund",
                condition=lambda order: order.has_partial_refund(),
                action=self._release_partial
            ),
            # 规则4：预占过期
            ReleaseRule(
                name="reservation_expired",
                condition=lambda reservation: (
                    datetime.now() > reservation.expire_at
                ),
                action=self._release_expired
            )
        ]

    def release_for_order(self, order):
        """为订单释放库存"""
        # 1. 查询订单的所有预占记录
        reservations = self.reservation_repo.find_by_order(order.order_id)

        # 2. 执行释放
        released_count = 0
        for reservation in reservations:
            if reservation.status != 'RESERVED':
                continue

            try:
                self._release_reservation(reservation)
                released_count += 1
            except Exception as e:
                self.logger.error(
                    f"释放预占失败: {reservation.reservation_id}",
                    exc_info=e
                )

        return ReleaseResult(
            success=True,
            released_count=released_count
        )

    def _release_reservation(self, reservation):
        """释放单个预占"""
        with self.db.transaction():
            # 1. 更新库存（原子操作）
            affected_rows = self.db.execute(
                """
                UPDATE inventory
                SET available = available + %s,
                    reserved = reserved - %s
                WHERE sku_id = %s
                  AND warehouse_id = %s
                  AND reserved >= %s
                """,
                (
                    reservation.quantity,
                    reservation.quantity,
                    reservation.sku_id,
                    reservation.warehouse_id,
                    reservation.quantity
                )
            )

            if affected_rows == 0:
                raise InventoryMismatchException(
                    f"预占库存不足: {reservation.reservation_id}"
                )

            # 2. 更新预占记录状态
            self.db.execute(
                """
                UPDATE inventory_reservations
                SET status = 'RELEASED',
                    released_at = NOW()
                WHERE reservation_id = %s
                """,
                (reservation.reservation_id,)
            )

            # 3. 记录变更日志
            self._log_inventory_change(
                sku_id=reservation.sku_id,
                warehouse_id=reservation.warehouse_id,
                change_type='RELEASE',
                quantity=reservation.quantity,
                order_id=reservation.order_id
            )
```

### 定时释放任务

```python
class ScheduledReleaseJob:
    """定时释放任务"""

    def run(self):
        """
        每分钟执行一次，释放过期预占

        批量处理策略：
        1. 查询过期预占（分批查询）
        2. 批量释放库存
        3. 批量更新预占状态
        """
        batch_size = 1000
        offset = 0

        while True:
            # 1. 查询过期预占
            expired_reservations = self.reservation_repo.find_expired(
                limit=batch_size,
                offset=offset
            )

            if not expired_reservations:
                break

            # 2. 按仓库和SKU分组
            grouped = defaultdict(list)
            for res in expired_reservations:
                key = (res.sku_id, res.warehouse_id)
                grouped[key].append(res)

            # 3. 批量释放
            for (sku_id, warehouse_id), reservations in grouped.items():
                total_quantity = sum(r.quantity for r in reservations)

                # 批量更新库存
                self.db.execute(
                    """
                    UPDATE inventory
                    SET available = available + %s,
                        reserved = reserved - %s
                    WHERE sku_id = %s AND warehouse_id = %s
                    """,
                    (total_quantity, total_quantity, sku_id, warehouse_id)
                )

                # 批量更新预占状态
                reservation_ids = [r.reservation_id for r in reservations]
                self.db.execute(
                    """
                    UPDATE inventory_reservations
                    SET status = 'RELEASED',
                        released_at = NOW()
                    WHERE reservation_id IN %s
                    """,
                    (tuple(reservation_ids),)
                )

            offset += batch_size

            # 限流保护
            time.sleep(0.1)
```

## 库存预占的并发控制

### 数据库层面的并发控制

**方案1：悲观锁（SELECT FOR UPDATE）**

```python
def reserve_with_pessimistic_lock(sku_id, quantity):
    """使用悲观锁预占库存"""
    with db.transaction():
        # 加行锁，阻塞其他事务
        inventory = db.query(
            """
            SELECT available, reserved
            FROM inventory
            WHERE sku_id = %s
            FOR UPDATE
            """,
            (sku_id,)
        )

        if inventory.available < quantity:
            raise InsufficientStockException()

        # 更新库存
        db.execute(
            """
            UPDATE inventory
            SET available = available - %s,
                reserved = reserved + %s
            WHERE sku_id = %s
            """,
            (quantity, quantity, sku_id)
        )
```

**优点**：实现简单，数据一致性强
**缺点**：高并发下性能差，容易死锁

**方案2：乐观锁（Version版本号）**

```python
def reserve_with_optimistic_lock(sku_id, quantity, max_retries=3):
    """使用乐观锁预占库存"""
    for retry in range(max_retries):
        # 1. 查询当前库存和版本号
        inventory = db.query(
            "SELECT available, version FROM inventory WHERE sku_id = %s",
            (sku_id,)
        )

        if inventory.available < quantity:
            raise InsufficientStockException()

        # 2. 更新库存（CAS操作）
        affected_rows = db.execute(
            """
            UPDATE inventory
            SET available = available - %s,
                reserved = reserved + %s,
                version = version + 1
            WHERE sku_id = %s
              AND version = %s
              AND available >= %s
            """,
            (quantity, quantity, sku_id, inventory.version, quantity)
        )

        # 3. 检查是否更新成功
        if affected_rows > 0:
            return True

        # 4. 版本冲突，重试
        time.sleep(0.01 * (retry + 1))

    raise ConcurrentUpdateException("乐观锁重试次数超限")
```

**优点**：高并发下性能好
**缺点**：冲突率高时重试次数多

### 分布式锁方案

**基于Redis的分布式锁**

```python
class RedisDistributedLock:
    """Redis分布式锁"""

    def __init__(self, redis_client):
        self.redis = redis_client

    def acquire(self, sku_id, timeout=5):
        """获取锁"""
        lock_key = f"inventory:lock:{sku_id}"
        lock_value = str(uuid.uuid4())
        end_time = time.time() + timeout

        while time.time() < end_time:
            # 使用SET NX EX命令原子性获取锁
            if self.redis.set(
                lock_key,
                lock_value,
                ex=30,  # 锁过期时间30秒
                nx=True  # 只在key不存在时设置
            ):
                return Lock(lock_key, lock_value, self.redis)

            # 自旋等待
            time.sleep(0.01)

        raise DistributedLockException(f"获取锁超时: {sku_id}")

    def release(self, lock):
        """释放锁（Lua脚本保证原子性）"""
        lua_script = """
        if redis.call("get", KEYS[1]) == ARGV[1] then
            return redis.call("del", KEYS[1])
        else
            return 0
        end
        """
        self.redis.eval(lua_script, 1, lock.key, lock.value)


class Lock:
    """锁对象"""

    def __init__(self, key, value, redis):
        self.key = key
        self.value = value
        self.redis = redis

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        RedisDistributedLock(self.redis).release(self)


# 使用示例
def reserve_with_redis_lock(sku_id, quantity):
    """使用Redis分布式锁预占库存"""
    lock_manager = RedisDistributedLock(redis_client)

    with lock_manager.acquire(sku_id):
        # 在锁保护下执行预占操作
        inventory = get_inventory(sku_id)
        if inventory.available < quantity:
            raise InsufficientStockException()

        update_inventory(sku_id, -quantity)
```

### Redis原子操作方案（推荐）

```python
class RedisInventoryService:
    """基于Redis的库存服务"""

    def __init__(self, redis_client):
        self.redis = redis_client

    def reserve(self, sku_id, quantity):
        """
        使用Lua脚本原子性预占库存

        优势：
        1. 原子性：Lua脚本在Redis中原子执行
        2. 高性能：单次网络请求
        3. 无锁：不需要分布式锁
        """
        lua_script = """
        local sku_key = KEYS[1]
        local quantity = tonumber(ARGV[1])

        -- 获取当前可用库存
        local available = tonumber(redis.call('HGET', sku_key, 'available') or 0)

        -- 检查库存充足性
        if available < quantity then
            return -1  -- 库存不足
        end

        -- 扣减可用库存，增加预占库存
        redis.call('HINCRBY', sku_key, 'available', -quantity)
        redis.call('HINCRBY', sku_key, 'reserved', quantity)

        return available - quantity  -- 返回剩余库存
        """

        result = self.redis.eval(
            lua_script,
            1,  # KEYS数量
            f"inventory:{sku_id}",  # KEYS[1]
            quantity  # ARGV[1]
        )

        if result < 0:
            raise InsufficientStockException(
                f"SKU {sku_id} 库存不足"
            )

        return result

    def release(self, sku_id, quantity):
        """释放库存"""
        lua_script = """
        local sku_key = KEYS[1]
        local quantity = tonumber(ARGV[1])

        -- 增加可用库存，扣减预占库存
        redis.call('HINCRBY', sku_key, 'available', quantity)
        redis.call('HINCRBY', sku_key, 'reserved', -quantity)

        return 1
        """

        self.redis.eval(
            lua_script,
            1,
            f"inventory:{sku_id}",
            quantity
        )

    def sync_to_database(self):
        """定期同步Redis库存到数据库"""
        # 扫描所有库存key
        cursor = 0
        while True:
            cursor, keys = self.redis.scan(
                cursor,
                match="inventory:*",
                count=100
            )

            for key in keys:
                sku_id = key.split(':')[1]
                inventory_data = self.redis.hgetall(key)

                # 更新数据库
                self.db.execute(
                    """
                    UPDATE inventory
                    SET available = %s,
                        reserved = %s
                    WHERE sku_id = %s
                    """,
                    (
                        inventory_data['available'],
                        inventory_data['reserved'],
                        sku_id
                    )
                )

            if cursor == 0:
                break
```

## 实战：秒杀场景的库存预占

### 秒杀场景特点

- **高并发**：瞬时万级QPS
- **库存少**：通常几十到几百件
- **时间短**：1-2秒决定胜负
- **零容忍**：绝对不能超卖

### 秒杀库存预占方案

```python
class SeckillInventoryService:
    """秒杀库存服务"""

    def __init__(self, redis_client):
        self.redis = redis_client

    def prepare_seckill(self, sku_id, total_stock):
        """
        秒杀预热：提前将库存加载到Redis

        数据结构：
        - String: inventory:seckill:{sku_id} → 剩余库存（原子递减）
        - Set: inventory:seckill:{sku_id}:users → 已抢购用户（防重复）
        """
        # 1. 设置初始库存
        self.redis.set(
            f"inventory:seckill:{sku_id}",
            total_stock
        )

        # 2. 设置过期时间（秒杀结束后1小时）
        self.redis.expire(
            f"inventory:seckill:{sku_id}",
            3600
        )

    def reserve_seckill(self, sku_id, user_id):
        """
        秒杀库存预占

        使用Lua脚本保证原子性：
        1. 检查用户是否已抢购
        2. 检查库存是否充足
        3. 扣减库存
        4. 记录用户
        """
        lua_script = """
        local stock_key = KEYS[1]
        local users_key = KEYS[2]
        local user_id = ARGV[1]

        -- 1. 检查用户是否已抢购
        if redis.call('SISMEMBER', users_key, user_id) == 1 then
            return -2  -- 重复抢购
        end

        -- 2. 检查库存
        local stock = tonumber(redis.call('GET', stock_key) or 0)
        if stock <= 0 then
            return -1  -- 库存不足
        end

        -- 3. 扣减库存
        redis.call('DECR', stock_key)

        -- 4. 记录用户
        redis.call('SADD', users_key, user_id)

        return stock - 1  -- 返回剩余库存
        """

        result = self.redis.eval(
            lua_script,
            2,
            f"inventory:seckill:{sku_id}",
            f"inventory:seckill:{sku_id}:users",
            user_id
        )

        if result == -1:
            raise SoldOutException("商品已抢光")
        elif result == -2:
            raise DuplicatePurchaseException("您已抢购过该商品")

        return result

    def fallback_to_queue(self, sku_id, user_id):
        """
        降级方案：库存不足时进入等待队列

        场景：用户取消订单后，自动通知队列中的用户
        """
        queue_key = f"inventory:seckill:{sku_id}:queue"

        # 加入队列（带分数的有序集合，分数=时间戳）
        self.redis.zadd(
            queue_key,
            {user_id: time.time()}
        )

        # 查询队列位置
        rank = self.redis.zrank(queue_key, user_id)

        return QueueResult(
            position=rank + 1,
            estimated_wait_time=(rank + 1) * 60  # 假设每分钟处理1个
        )
```

## 总结

库存预占是OMS系统的核心能力，直接决定了系统的可靠性和用户体验。关键要点：

1. **原子性保证**：使用数据库事务、Redis Lua脚本保证操作原子性
2. **并发控制**：根据场景选择悲观锁、乐观锁或分布式锁
3. **自动释放**：通过定时任务、事件触发实现库存自动释放
4. **降级策略**：库存不足时提供部分预占、排队等降级方案
5. **监控告警**：实时监控预占成功率、释放及时性等指标

下一篇文章，我们将探讨**订单智能路由与仓库选择**，这是库存预占的前置决策环节。

---

**关键词**：库存预占、分布式锁、Redis、并发控制、Lua脚本、秒杀系统、库存一致性
