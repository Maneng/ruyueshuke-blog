---
title: "事务实战：转账案例与并发控制"
date: 2025-01-14T18:00:00+08:00
draft: false
tags: ["MySQL", "事务", "实战案例", "并发控制"]
categories: ["数据库"]
description: "通过转账、秒杀、订单支付等真实案例，掌握MySQL事务的实战应用和并发控制技巧"
series: ["MySQL从入门到精通"]
weight: 44
stage: 4
stageTitle: "事务与锁篇"
---

## 实战案例概览

| 案例      | 核心问题        | 解决方案            | 难点              |
|---------|-------------|-----------------|-----------------|
| 转账业务    | 数据一致性、死锁    | 固定加锁顺序、悲观锁     | 多账户并发转账         |
| 秒杀抢购    | 超卖、高并发      | 乐观锁 + 限流        | 10000人抢100件商品   |
| 订单支付    | 重复支付、幂等性    | 悲观锁 + 唯一约束      | 防止重复扣款          |
| 红包发放    | 余额不足、公平性    | 悲观锁 + 事务隔离      | 1个红包被多人抢        |
| 积分扣减    | 负数积分        | 乐观锁 + 余额检查      | 并发扣减积分          |

---

## 案例1：转账业务

### 需求

用户A向用户B转账100元，要求：
- 余额不能为负数
- 转账过程中不能被打断
- 防止死锁

### 方案1：基础实现（有死锁风险）

```sql
-- ❌ 可能死锁
-- 事务A：A向B转100
START TRANSACTION;
UPDATE account SET balance = balance - 100 WHERE user_id = 'A'; -- 锁A
UPDATE account SET balance = balance + 100 WHERE user_id = 'B'; -- 等待锁B
COMMIT;

-- 事务B：B向A转50（并发执行）
START TRANSACTION;
UPDATE account SET balance = balance - 50 WHERE user_id = 'B'; -- 锁B
UPDATE account SET balance = balance + 50 WHERE user_id = 'A'; -- 等待锁A（死锁！）
COMMIT;
```

### 方案2：固定加锁顺序（推荐）

```sql
-- ✅ 避免死锁：按user_id升序加锁

-- 转账函数（伪代码）
FUNCTION transfer(from_user, to_user, amount):
    -- 1. 固定加锁顺序（按user_id升序）
    first_user = MIN(from_user, to_user)
    second_user = MAX(from_user, to_user)

    START TRANSACTION;

    -- 2. 按顺序锁定账户
    SELECT balance FROM account WHERE user_id = first_user FOR UPDATE;
    SELECT balance FROM account WHERE user_id = second_user FOR UPDATE;

    -- 3. 检查余额
    IF from_user.balance < amount THEN
        ROLLBACK;
        RETURN "余额不足";
    END IF;

    -- 4. 扣款和到账
    UPDATE account SET balance = balance - amount WHERE user_id = from_user;
    UPDATE account SET balance = balance + amount WHERE user_id = to_user;

    COMMIT;
    RETURN "转账成功";
END FUNCTION;
```

### 方案3：Java实现（完整代码）

```java
@Service
public class TransferService {

    @Autowired
    private AccountMapper accountMapper;

    @Transactional(rollbackFor = Exception.class)
    public void transfer(String fromUser, String toUser, BigDecimal amount) {
        // 1. 固定加锁顺序（避免死锁）
        String firstUser = fromUser.compareTo(toUser) < 0 ? fromUser : toUser;
        String secondUser = fromUser.compareTo(toUser) < 0 ? toUser : fromUser;

        // 2. 按顺序锁定账户（悲观锁）
        Account first = accountMapper.selectForUpdate(firstUser);
        Account second = accountMapper.selectForUpdate(secondUser);

        // 3. 检查余额
        Account fromAccount = fromUser.equals(firstUser) ? first : second;
        if (fromAccount.getBalance().compareTo(amount) < 0) {
            throw new BusinessException("余额不足");
        }

        // 4. 扣款和到账
        accountMapper.updateBalance(fromUser, amount.negate()); // 扣款
        accountMapper.updateBalance(toUser, amount);             // 到账

        // 5. 记录流水（可选）
        recordTransferLog(fromUser, toUser, amount);
    }
}
```

```xml
<!-- MyBatis Mapper -->
<select id="selectForUpdate" resultType="Account">
    SELECT * FROM account WHERE user_id = #{userId} FOR UPDATE
</select>

<update id="updateBalance">
    UPDATE account
    SET balance = balance + #{amount}
    WHERE user_id = #{userId}
</update>
```

---

## 案例2：秒杀抢购

### 需求

10000个用户抢购100件商品，要求：
- 不能超卖（库存>=0）
- 高并发（TPS>1000）
- 防止刷单

### 方案1：乐观锁（推荐）

```sql
-- 1. 建表
CREATE TABLE product (
    id INT PRIMARY KEY,
    name VARCHAR(50),
    stock INT,
    version INT DEFAULT 0,
    INDEX idx_stock (stock)
);

-- 2. 秒杀逻辑（乐观锁）
-- 伪代码
FUNCTION buy_product(product_id, quantity):
    max_retries = 3

    FOR i IN 1..max_retries:
        -- 查询库存和版本号（不加锁）
        product = SELECT stock, version FROM product WHERE id = product_id;

        -- 检查库存
        IF product.stock < quantity THEN
            RETURN "库存不足";
        END IF;

        -- 尝试扣减库存（乐观锁）
        affected_rows = UPDATE product
                        SET stock = stock - quantity,
                            version = version + 1
                        WHERE id = product_id
                          AND version = product.version
                          AND stock >= quantity; -- 双重检查

        -- 更新成功
        IF affected_rows > 0 THEN
            -- 创建订单
            INSERT INTO orders (user_id, product_id, quantity) VALUES (...);
            RETURN "购买成功";
        END IF;

        -- 版本冲突，重试
        SLEEP(10ms);
    END FOR;

    RETURN "购买失败，请重试";
END FUNCTION;
```

### 方案2：悲观锁（库存少时）

```sql
-- 当库存剩余<10时，切换到悲观锁（防止超卖）

START TRANSACTION;

-- 1. 锁定商品（悲观锁）
SELECT stock FROM product WHERE id = 1001 FOR UPDATE;

-- 2. 检查库存
IF stock < 1 THEN
    ROLLBACK;
    RETURN "库存不足";
END IF;

-- 3. 扣减库存
UPDATE product SET stock = stock - 1 WHERE id = 1001;

-- 4. 创建订单
INSERT INTO orders (user_id, product_id, quantity) VALUES (...);

COMMIT;
RETURN "购买成功";
```

### 方案3：Redis + MySQL（高并发）

```python
# Python示例（Redis预减库存 + MySQL兜底）

def buy_product_with_redis(user_id, product_id):
    # 1. Redis预减库存（快速失败）
    stock = redis.decr(f"product:{product_id}:stock")

    if stock < 0:
        # 库存不足，恢复Redis
        redis.incr(f"product:{product_id}:stock")
        return {"success": False, "message": "库存不足"}

    # 2. 异步写入MySQL（消息队列）
    mq.send({
        "user_id": user_id,
        "product_id": product_id,
        "quantity": 1
    })

    return {"success": True, "message": "购买成功"}

# 消费者（异步写入MySQL）
def consume_order_message(message):
    user_id = message['user_id']
    product_id = message['product_id']

    # MySQL扣减库存（乐观锁兜底）
    affected_rows = db.execute("""
        UPDATE product
        SET stock = stock - 1,
            version = version + 1
        WHERE id = %s AND stock > 0
    """, product_id)

    if affected_rows > 0:
        # 创建订单
        db.execute("""
            INSERT INTO orders (user_id, product_id)
            VALUES (%s, %s)
        """, user_id, product_id)
    else:
        # MySQL库存不足，恢复Redis
        redis.incr(f"product:{product_id}:stock")
```

---

## 案例3：订单支付

### 需求

用户支付订单，要求：
- 防止重复支付
- 幂等性（多次请求结果一致）
- 扣款和订单状态更新原子性

### 方案1：悲观锁 + 状态检查

```sql
-- 1. 建表
CREATE TABLE orders (
    id INT PRIMARY KEY,
    user_id INT,
    amount DECIMAL(10,2),
    status ENUM('UNPAID', 'PAID', 'CANCELLED') DEFAULT 'UNPAID',
    INDEX idx_user_status (user_id, status)
);

-- 2. 支付逻辑
START TRANSACTION;

-- 1. 锁定订单（悲观锁）
SELECT status FROM orders WHERE id = 12345 FOR UPDATE;

-- 2. 检查订单状态
IF status != 'UNPAID' THEN
    ROLLBACK;
    RETURN "订单状态异常"; -- 已支付或已取消
END IF;

-- 3. 锁定账户
SELECT balance FROM account WHERE user_id = 1 FOR UPDATE;

-- 4. 检查余额
IF balance < order.amount THEN
    ROLLBACK;
    RETURN "余额不足";
END IF;

-- 5. 扣款
UPDATE account SET balance = balance - order.amount WHERE user_id = 1;

-- 6. 更新订单状态
UPDATE orders SET status = 'PAID' WHERE id = 12345;

-- 7. 记录支付流水
INSERT INTO payment_log (order_id, amount, pay_time) VALUES (12345, 100, NOW());

COMMIT;
RETURN "支付成功";
```

### 方案2：唯一约束 + 幂等性

```sql
-- 1. 建表（支付流水表）
CREATE TABLE payment_log (
    id INT PRIMARY KEY AUTO_INCREMENT,
    order_id INT NOT NULL,
    pay_id VARCHAR(64) NOT NULL, -- 支付请求唯一ID（客户端生成）
    amount DECIMAL(10,2),
    status ENUM('SUCCESS', 'FAILED'),
    create_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_pay_id (pay_id) -- 唯一约束，防止重复支付
);

-- 2. 支付逻辑（幂等性）
START TRANSACTION;

-- 1. 插入支付流水（幂等性检查）
INSERT INTO payment_log (order_id, pay_id, amount, status)
VALUES (12345, 'PAY_1234567890', 100, 'SUCCESS')
ON DUPLICATE KEY UPDATE id = id; -- 如果pay_id已存在，不做任何操作

-- 2. 检查是否插入成功
IF affected_rows == 1 THEN
    -- 首次支付，执行扣款和订单更新
    UPDATE account SET balance = balance - 100 WHERE user_id = 1;
    UPDATE orders SET status = 'PAID' WHERE id = 12345;
    COMMIT;
    RETURN "支付成功";
ELSE
    -- 重复支付，直接返回成功
    ROLLBACK;
    RETURN "支付成功（已支付）";
END IF;
```

---

## 案例4：红包发放

### 需求

用户A发1个100元红包，10个人抢，要求：
- 总金额不能超100元
- 每人只能抢1次
- 公平性（随机金额）

### 方案：悲观锁 + 原子性

```sql
-- 1. 建表
CREATE TABLE red_packet (
    id INT PRIMARY KEY,
    user_id INT,          -- 发红包的人
    total_amount DECIMAL(10,2),
    remain_amount DECIMAL(10,2), -- 剩余金额
    total_count INT,      -- 红包总数
    remain_count INT,     -- 剩余个数
    status ENUM('ACTIVE', 'FINISHED') DEFAULT 'ACTIVE'
);

CREATE TABLE red_packet_record (
    id INT PRIMARY KEY AUTO_INCREMENT,
    red_packet_id INT,
    user_id INT,          -- 抢红包的人
    amount DECIMAL(10,2),
    create_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_packet_user (red_packet_id, user_id) -- 防止重复抢
);

-- 2. 抢红包逻辑
START TRANSACTION;

-- 1. 锁定红包（悲观锁）
SELECT remain_amount, remain_count, status
FROM red_packet
WHERE id = 1001 FOR UPDATE;

-- 2. 检查红包状态
IF status != 'ACTIVE' OR remain_count <= 0 THEN
    ROLLBACK;
    RETURN "红包已抢完";
END IF;

-- 3. 计算抢到的金额（随机）
IF remain_count == 1 THEN
    amount = remain_amount; -- 最后1个红包，拿走剩余所有金额
ELSE
    -- 随机金额（0.01 ~ 剩余平均值*2）
    max_amount = remain_amount / remain_count * 2;
    amount = RAND() * max_amount;
    amount = MAX(0.01, amount); -- 至少0.01元
END IF;

-- 4. 插入抢红包记录（防止重复抢）
INSERT INTO red_packet_record (red_packet_id, user_id, amount)
VALUES (1001, 123, amount);
-- 如果重复抢，唯一约束报错，事务回滚

-- 5. 更新红包余额
UPDATE red_packet
SET remain_amount = remain_amount - amount,
    remain_count = remain_count - 1,
    status = IF(remain_count - 1 = 0, 'FINISHED', 'ACTIVE')
WHERE id = 1001;

-- 6. 用户余额增加
UPDATE account SET balance = balance + amount WHERE user_id = 123;

COMMIT;
RETURN "抢到红包：" + amount + "元";
```

---

## 案例5：积分扣减

### 需求

用户兑换商品，扣减100积分，要求：
- 积分不能为负数
- 高并发（1000 TPS）
- 记录扣减日志

### 方案：乐观锁 + 版本号

```sql
-- 1. 建表
CREATE TABLE user_points (
    user_id INT PRIMARY KEY,
    points INT DEFAULT 0,
    version INT DEFAULT 0
);

CREATE TABLE points_log (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT,
    change_amount INT, -- 正数表示增加，负数表示扣减
    reason VARCHAR(100),
    create_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. 扣减积分逻辑（乐观锁）
FUNCTION deduct_points(user_id, amount, reason):
    max_retries = 3

    FOR i IN 1..max_retries:
        -- 1. 查询积分和版本号（不加锁）
        user = SELECT points, version FROM user_points WHERE user_id = user_id;

        -- 2. 检查积分
        IF user.points < amount THEN
            RETURN "积分不足";
        END IF;

        -- 3. 尝试扣减积分（乐观锁）
        affected_rows = UPDATE user_points
                        SET points = points - amount,
                            version = version + 1
                        WHERE user_id = user_id
                          AND version = user.version
                          AND points >= amount; -- 双重检查

        -- 4. 更新成功
        IF affected_rows > 0 THEN
            -- 记录扣减日志
            INSERT INTO points_log (user_id, change_amount, reason)
            VALUES (user_id, -amount, reason);

            RETURN "扣减成功";
        END IF;

        -- 版本冲突，重试
        SLEEP(10ms);
    END FOR;

    RETURN "扣减失败，请重试";
END FUNCTION;
```

---

## 实战总结

### 1. 选择合适的锁

| 场景      | 锁类型   | 原因              |
|---------|-------|-----------------|
| 转账、支付   | 悲观锁   | 高一致性要求，防止余额为负   |
| 秒杀、抢购   | 乐观锁   | 高并发，冲突少         |
| 红包、库存   | 悲观锁   | 防止超发、超卖         |
| 积分、点赞   | 乐观锁   | 高并发，允许重试        |

### 2. 避免死锁

- ✅ 固定加锁顺序（按主键升序）
- ✅ 一次性获取所有锁
- ✅ 缩小事务范围

### 3. 幂等性设计

- ✅ 唯一约束（pay_id、order_id）
- ✅ 状态检查（已支付不再扣款）
- ✅ 插入前查询（防止重复操作）

### 4. 性能优化

- ✅ 乐观锁 + 重试（高并发）
- ✅ Redis预减库存（秒杀）
- ✅ 异步消息队列（削峰）

---

## 小结

✅ **转账**：固定加锁顺序，避免死锁
✅ **秒杀**：乐观锁 + Redis，高并发
✅ **支付**：悲观锁 + 幂等性，防重复
✅ **红包**：悲观锁 + 唯一约束，防超发
✅ **积分**：乐观锁 + 版本号，高性能

掌握这些实战案例，就能应对大部分并发控制场景。

---

📚 **相关阅读**：
- 推荐：《乐观锁与悲观锁：应用场景对比》
- 推荐：《死锁：产生原因与解决方案》

🎉 **恭喜！你已完成MySQL事务与锁篇的全部内容！**
