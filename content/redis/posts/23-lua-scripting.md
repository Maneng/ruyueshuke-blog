---
title: "Lua脚本编程：Redis的原子操作利器"
date: 2025-01-21T22:00:00+08:00
draft: false
tags: ["Redis", "Lua", "脚本", "原子操作"]
categories: ["技术"]
description: "掌握Redis Lua脚本编程，实现复杂的原子操作，解决库存扣减、限流、分布式锁等实战场景"
weight: 23
stage: 3
stageTitle: "进阶特性篇"
---

## 为什么需要Lua脚本？

**问题**：多个Redis命令无法保证原子性
```java
// ❌ 非原子操作（有并发问题）
Long stock = redis.get("stock");
if (stock > 0) {
    redis.decr("stock");  // 可能有多个线程同时执行
    return "success";
}
```

**Lua脚本优势**：
- ✅ 原子性：脚本执行期间不会插入其他命令
- ✅ 减少网络往返：多个命令一次发送
- ✅ 复用：脚本可以缓存在服务器

## 基础语法

### 执行脚本

```bash
# EVAL命令
redis> EVAL "return redis.call('SET', 'key', 'value')" 0
OK

# 格式：EVAL script numkeys key [key ...] arg [arg ...]
# numkeys: key的数量
# KEYS[1], KEYS[2]: 传入的key
# ARGV[1], ARGV[2]: 传入的参数
```

### 调用Redis命令

```lua
-- redis.call()：命令错误会报错
redis.call('SET', 'key', 'value')

-- redis.pcall()：命令错误会返回错误对象
redis.pcall('SET', 'key', 'value')
```

## 实战案例

### 案例1：库存扣减（秒杀场景）

```lua
-- stock_deduct.lua
local key = KEYS[1]
local quantity = tonumber(ARGV[1])

local stock = tonumber(redis.call('GET', key) or '0')

if stock >= quantity then
    redis.call('DECRBY', key, quantity)
    return 1  -- 成功
else
    return 0  -- 库存不足
end
```

**Java调用**：
```java
@Service
public class StockService {
    @Autowired
    private RedisTemplate<String, Object> redis;

    private static final String SCRIPT =
        "local stock = tonumber(redis.call('GET', KEYS[1]) or '0') " +
        "if stock >= tonumber(ARGV[1]) then " +
        "  redis.call('DECRBY', KEYS[1], ARGV[1]) " +
        "  return 1 " +
        "else " +
        "  return 0 " +
        "end";

    public boolean deductStock(String productId, int quantity) {
        Long result = redis.execute(
            RedisScript.of(SCRIPT, Long.class),
            Collections.singletonList("stock:" + productId),
            String.valueOf(quantity)
        );
        return result != null && result == 1;
    }
}
```

### 案例2：限流（固定窗口）

```lua
-- rate_limit.lua
local key = KEYS[1]
local limit = tonumber(ARGV[1])
local window = tonumber(ARGV[2])

local current = tonumber(redis.call('GET', key) or '0')

if current < limit then
    redis.call('INCR', key)
    if current == 0 then
        redis.call('EXPIRE', key, window)
    end
    return 1  -- 允许
else
    return 0  -- 限流
end
```

**Java实现**：
```java
public boolean checkRateLimit(String userId, int limit, int windowSeconds) {
    String key = "rate_limit:" + userId;
    String script =
        "local current = tonumber(redis.call('GET', KEYS[1]) or '0') " +
        "if current < tonumber(ARGV[1]) then " +
        "  redis.call('INCR', KEYS[1]) " +
        "  if current == 0 then " +
        "    redis.call('EXPIRE', KEYS[1], ARGV[2]) " +
        "  end " +
        "  return 1 " +
        "else " +
        "  return 0 " +
        "end";

    Long result = redis.execute(
        RedisScript.of(script, Long.class),
        Collections.singletonList(key),
        String.valueOf(limit),
        String.valueOf(windowSeconds)
    );
    return result != null && result == 1;
}
```

### 案例3：分布式锁释放

```lua
-- unlock.lua
if redis.call('GET', KEYS[1]) == ARGV[1] then
    return redis.call('DEL', KEYS[1])
else
    return 0
end
```

**Java实现**：
```java
public void unlock(String lockKey, String requestId) {
    String script =
        "if redis.call('GET', KEYS[1]) == ARGV[1] then " +
        "  return redis.call('DEL', KEYS[1]) " +
        "else " +
        "  return 0 " +
        "end";

    redis.execute(
        RedisScript.of(script, Long.class),
        Collections.singletonList(lockKey),
        requestId
    );
}
```

### 案例4：滑动窗口限流

```lua
-- sliding_window_limit.lua
local key = KEYS[1]
local limit = tonumber(ARGV[1])
local window = tonumber(ARGV[2])
local now = tonumber(ARGV[3])

-- 移除过期的记录
redis.call('ZREMRANGEBYSCORE', key, 0, now - window)

-- 统计当前窗口内的请求数
local count = redis.call('ZCARD', key)

if count < limit then
    redis.call('ZADD', key, now, now)
    redis.call('EXPIRE', key, window)
    return 1
else
    return 0
end
```

## 脚本管理

### SCRIPT LOAD/EVALSHA

```bash
# 1. 加载脚本，返回SHA1
redis> SCRIPT LOAD "return redis.call('GET', KEYS[1])"
"6b1bf486c81ceb7edf3c093f4c48582e38c0e791"

# 2. 使用SHA1执行（避免重复传输脚本）
redis> EVALSHA 6b1bf486c81ceb7edf3c093f4c48582e38c0e791 1 mykey
```

**Java实现**：
```java
@Component
public class LuaScriptManager {
    @Autowired
    private RedisTemplate<String, Object> redis;

    private String scriptSha;

    @PostConstruct
    public void init() {
        String script = "return redis.call('GET', KEYS[1])";
        scriptSha = redis.execute((RedisCallback<String>) connection -> {
            return connection.scriptLoad(script.getBytes());
        });
    }

    public String getValue(String key) {
        return redis.execute(
            RedisScript.of(scriptSha, String.class),
            Collections.singletonList(key)
        );
    }
}
```

### 查看已加载脚本

```bash
# 查看所有脚本
redis> SCRIPT EXISTS sha1 [sha1 ...]

# 清除所有脚本
redis> SCRIPT FLUSH

# 终止正在执行的脚本
redis> SCRIPT KILL
```

## 最佳实践

### 1. 传递参数使用KEYS和ARGV

```lua
-- ✅ 好：通过参数传递
local key = KEYS[1]
local value = ARGV[1]

-- ❌ 不好：硬编码
local key = "mykey"
```

### 2. 避免长时间运行

```lua
-- ❌ 不好：死循环
while true do
    -- ...
end

-- ✅ 好：限制循环次数
for i = 1, 1000 do
    -- ...
end
```

### 3. 使用局部变量

```lua
-- ✅ 好
local result = redis.call('GET', 'key')

-- ❌ 不好：全局变量（可能污染）
result = redis.call('GET', 'key')
```

### 4. 错误处理

```java
try {
    redis.execute(script, keys, args);
} catch (RedisException e) {
    log.error("Lua脚本执行失败", e);
    // 降级处理
}
```

## 调试技巧

### 1. 返回中间结果

```lua
-- 调试时返回详细信息
local stock = redis.call('GET', KEYS[1])
local quantity = ARGV[1]
return {stock, quantity, "debug info"}
```

### 2. 使用redis-cli测试

```bash
# 本地测试
redis-cli --eval script.lua key1 key2 , arg1 arg2

# 示例
redis-cli --eval stock_deduct.lua stock:1001 , 10
```

### 3. 日志输出

```lua
-- Redis 7.0+ 支持
redis.log(redis.LOG_WARNING, "debug message")
```

## 性能优化

### 1. 脚本缓存

```java
// 启动时加载脚本
@PostConstruct
public void loadScripts() {
    stockDeductSha = redis.execute(
        (RedisCallback<String>) connection ->
            connection.scriptLoad(STOCK_DEDUCT_SCRIPT.getBytes())
    );
}

// 使用时直接EVALSHA
public boolean deductStock(String productId, int quantity) {
    return redis.execute(
        RedisScript.of(stockDeductSha, Long.class),
        Collections.singletonList("stock:" + productId),
        String.valueOf(quantity)
    ) == 1;
}
```

### 2. 减少网络往返

```java
// ❌ 不好：多次调用Redis
Long stock = redis.opsForValue().get("stock");
if (stock > 0) {
    redis.opsForValue().decrement("stock");
    redis.opsForValue().increment("sales");
}

// ✅ 好：一次Lua脚本完成
String script =
    "local stock = tonumber(redis.call('GET', KEYS[1])) " +
    "if stock > 0 then " +
    "  redis.call('DECR', KEYS[1]) " +
    "  redis.call('INCR', KEYS[2]) " +
    "  return 1 " +
    "else " +
    "  return 0 " +
    "end";
```

## 限制与注意事项

1. **脚本执行时间**：超过5秒会被SCRIPT KILL中断
2. **原子性**：脚本执行期间会阻塞其他命令
3. **内存**：避免在脚本中创建大量临时数据
4. **随机性**：避免使用随机数（影响主从一致性）

## 总结

**核心价值**：
- 原子性：多个操作作为一个整体
- 性能：减少网络往返
- 灵活：实现复杂业务逻辑

**典型场景**：
- 库存扣减、秒杀
- 限流算法
- 分布式锁
- 复杂计数统计

**最佳实践**：
- 参数化脚本（KEYS/ARGV）
- 脚本缓存（EVALSHA）
- 控制执行时间
- 错误处理和降级
