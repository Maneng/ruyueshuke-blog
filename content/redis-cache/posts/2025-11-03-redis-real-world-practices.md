---
title: Redis实战：分布式锁、消息队列、缓存设计
date: 2025-11-03T10:00:00+08:00
draft: false
tags:
  - Redis
  - 分布式锁
  - 消息队列
  - 缓存设计
  - Redisson
  - 第一性原理
categories:
  - Java技术生态
series:
  - Redis第一性原理
weight: 6
description: Redis系列终章：分布式锁（SETNX、Redlock、Redisson）、消息队列（List、Pub/Sub、Stream）、缓存设计模式（Cache Aside、缓存三大问题）、布隆过滤器、性能优化。20000字深度实战文章。
---

## 一、分布式锁：从SETNX到Redlock

### 1.1 为什么需要分布式锁？

**场景：秒杀系统的超卖问题**

```java
// ❌ 错误：单机锁无法解决分布式超卖
@Service
public class SeckillService {

    @Autowired
    private ProductRepository productRepository;

    /**
     * 秒杀下单（单机锁）
     */
    public synchronized Order seckill(Long productId, Long userId) {
        // 1. 检查库存
        Integer stock = productRepository.getStock(productId);
        if (stock <= 0) {
            throw new SoldOutException("商品已售罄");
        }

        // 2. 扣减库存
        productRepository.decrementStock(productId);

        // 3. 创建订单
        return orderService.createOrder(productId, userId);
    }
}

// 问题：
// 假设有3台服务器（Server A、B、C）
// T1: Server A：检查库存=1（通过）
// T2: Server B：检查库存=1（通过）
// T3: Server A：扣减库存=0，创建订单1
// T4: Server B：扣减库存=-1（超卖！），创建订单2

// synchronized只能锁住单机JVM内的线程
// 无法锁住分布式环境的多个进程
```

**核心问题**：分布式环境下，单机锁无效，需要**分布式锁**。

### 1.2 方案1：基于SETNX的简单实现

```java
@Service
public class SeckillService {

    @Autowired
    private RedisTemplate<String, String> redisTemplate;

    /**
     * 秒杀下单（Redis分布式锁）
     */
    public Order seckill(Long productId, Long userId) {
        String lockKey = "lock:product:" + productId;
        String lockValue = UUID.randomUUID().toString();

        try {
            // 1. 尝试获取锁（SETNX + 过期时间）
            Boolean locked = redisTemplate.opsForValue().setIfAbsent(
                lockKey,
                lockValue,
                10,
                TimeUnit.SECONDS
            );

            if (!Boolean.TRUE.equals(locked)) {
                throw new TooManyRequestsException("系统繁忙，请稍后再试");
            }

            // 2. 检查库存
            Integer stock = productRepository.getStock(productId);
            if (stock <= 0) {
                throw new SoldOutException("商品已售罄");
            }

            // 3. 扣减库存
            productRepository.decrementStock(productId);

            // 4. 创建订单
            return orderService.createOrder(productId, userId);

        } finally {
            // 5. 释放锁（使用Lua脚本，确保原子性）
            releaseLock(lockKey, lockValue);
        }
    }

    /**
     * 释放锁（Lua脚本）
     */
    private void releaseLock(String lockKey, String lockValue) {
        String script =
            "if redis.call('get', KEYS[1]) == ARGV[1] then " +
            "    return redis.call('del', KEYS[1]) " +
            "else " +
            "    return 0 " +
            "end";

        redisTemplate.execute(
            new DefaultRedisScript<>(script, Long.class),
            Collections.singletonList(lockKey),
            lockValue
        );
    }
}
```

**核心要点**：

```
1. 加锁：SET key value NX EX 10
   - NX：只有key不存在时才设置（SETNX）
   - EX：设置过期时间（防止死锁）

2. 释放锁：使用Lua脚本
   - 检查value是否匹配（防止释放别人的锁）
   - 原子操作（GET + DEL）

3. 锁的value：使用UUID
   - 唯一标识锁的持有者
   - 释放锁时校验
```

**潜在问题**：

```
问题1：锁过期时间不好设置
- 设置太短：业务未完成，锁就过期了
- 设置太长：出现异常，锁长时间占用

问题2：不可重入
- 同一个线程无法再次获取锁
- 递归调用会死锁

问题3：无阻塞等待
- 获取锁失败立即返回
- 无法等待锁释放

问题4：单点故障
- Redis宕机，锁失效
- 主从切换时，锁可能丢失

解决方案：使用Redisson
```

### 1.3 方案2：Redisson（推荐）

**Redisson**：Redis官方推荐的Java客户端，提供完善的分布式锁实现。

```xml
<!-- 添加依赖 -->
<dependency>
    <groupId>org.redisson</groupId>
    <artifactId>redisson-spring-boot-starter</artifactId>
    <version>3.23.5</version>
</dependency>
```

**配置Redisson**：

```yaml
# application.yml
spring:
  redis:
    host: 127.0.0.1
    port: 6379
    password: mypassword
    database: 0
```

**使用Redisson分布式锁**：

```java
@Service
public class SeckillService {

    @Autowired
    private RedissonClient redissonClient;

    /**
     * 秒杀下单（Redisson分布式锁）
     */
    public Order seckill(Long productId, Long userId) {
        String lockKey = "lock:product:" + productId;

        // 获取锁对象
        RLock lock = redissonClient.getLock(lockKey);

        try {
            // 尝试获取锁（最多等待10秒，锁30秒自动释放）
            boolean locked = lock.tryLock(10, 30, TimeUnit.SECONDS);

            if (!locked) {
                throw new TooManyRequestsException("系统繁忙，请稍后再试");
            }

            // 执行业务逻辑
            Integer stock = productRepository.getStock(productId);
            if (stock <= 0) {
                throw new SoldOutException("商品已售罄");
            }

            productRepository.decrementStock(productId);
            return orderService.createOrder(productId, userId);

        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new RuntimeException("获取锁失败", e);
        } finally {
            // 释放锁
            if (lock.isHeldByCurrentThread()) {
                lock.unlock();
            }
        }
    }
}
```

**Redisson的核心特性**：

```
1. 可重入
   - 同一个线程可以多次获取锁
   - 内部使用计数器（类似ReentrantLock）

2. 锁续期（Watch Dog）
   - 默认30秒自动续期
   - 业务未完成，自动延长锁时间
   - 避免锁过期问题

3. 阻塞等待
   - tryLock(10, 30, TimeUnit.SECONDS)
   - 等待10秒，如果获取不到锁则返回false

4. 公平锁
   - 按请求顺序获取锁
   - RLock lock = redissonClient.getFairLock(lockKey);

5. 读写锁
   - RReadWriteLock rwLock = redissonClient.getReadWriteLock(lockKey);
   - 读锁：多个线程可以同时获取
   - 写锁：独占

6. 信号量
   - RSemaphore semaphore = redissonClient.getSemaphore(key);
   - 限流场景
```

### 1.4 方案3：Redlock（多节点容错）

**问题**：单机Redis宕机，锁失效。

**Redlock算法**：Redis作者提出的分布式锁算法，支持多节点容错。

```
原理：
1. 准备N个独立的Redis实例（推荐5个）
2. 客户端依次向N个实例申请锁
3. 如果超过半数（N/2+1）实例加锁成功，则认为获取锁成功
4. 锁的有效时间 = 设定时间 - 获取锁耗时
5. 释放锁时，向所有实例发送释放命令

优势：
- 容忍少数节点宕机（最多(N-1)/2个）
- 5个节点，可以容忍2个宕机

劣势：
- 复杂度高
- 成本高（需要5个Redis实例）
- 存在争议（有人认为Redlock不安全）
```

**Redisson实现Redlock**：

```java
@Configuration
public class RedissonConfig {

    @Bean
    public RedissonClient redissonClient() {
        Config config = new Config();

        // 配置5个独立的Redis节点
        config.useReplicatedServers()
            .addNodeAddress(
                "redis://127.0.0.1:6379",
                "redis://127.0.0.1:6380",
                "redis://127.0.0.1:6381",
                "redis://127.0.0.1:6382",
                "redis://127.0.0.1:6383"
            );

        return Redisson.create(config);
    }
}

@Service
public class SeckillService {

    @Autowired
    private RedissonClient redissonClient;

    public Order seckill(Long productId, Long userId) {
        // 使用Redlock（自动向所有节点申请锁）
        RLock lock = redissonClient.getLock("lock:product:" + productId);

        try {
            boolean locked = lock.tryLock(10, 30, TimeUnit.SECONDS);

            if (!locked) {
                throw new TooManyRequestsException("系统繁忙");
            }

            // 业务逻辑
            // ...

        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new RuntimeException("获取锁失败", e);
        } finally {
            if (lock.isHeldByCurrentThread()) {
                lock.unlock();
            }
        }
    }
}
```

---

## 二、消息队列：从List到Stream

### 2.1 方案1：基于List的简单队列

```java
/**
 * 生产者：发送消息
 */
@Service
public class MessageProducer {

    @Autowired
    private RedisTemplate<String, String> redisTemplate;

    public void sendMessage(String queue, String message) {
        redisTemplate.opsForList().leftPush(queue, message);
    }
}

/**
 * 消费者：消费消息
 */
@Service
public class MessageConsumer {

    @Autowired
    private RedisTemplate<String, String> redisTemplate;

    @Scheduled(fixedDelay = 1000)
    public void consumeMessages() {
        String queue = "queue:task";

        while (true) {
            // BRPOP：阻塞弹出（超时10秒）
            List<String> message = redisTemplate.opsForList().rightPop(
                queue,
                10,
                TimeUnit.SECONDS
            );

            if (message == null || message.isEmpty()) {
                break;  // 队列为空
            }

            String msg = message.get(1);  // message[0]是key，message[1]是value
            processMessage(msg);
        }
    }

    private void processMessage(String message) {
        log.info("处理消息：{}", message);
        // 业务逻辑
    }
}
```

**优劣分析**：

```
优势：
- 简单易用
- 性能好（10万QPS）
- FIFO顺序

劣势：
- 无消息确认机制（消费后就删除，失败无法重试）
- 无消息持久化（Redis宕机丢失）
- 单消费者（多消费者会竞争）

适用场景：
- 轻量级异步任务
- 对可靠性要求不高
```

### 2.2 方案2：基于Pub/Sub的发布订阅

```java
/**
 * 发布者
 */
@Service
public class MessagePublisher {

    @Autowired
    private RedisTemplate<String, String> redisTemplate;

    public void publish(String channel, String message) {
        redisTemplate.convertAndSend(channel, message);
    }
}

/**
 * 订阅者
 */
@Component
public class MessageSubscriber {

    @Bean
    public RedisMessageListenerContainer container(
        RedisConnectionFactory factory) {

        RedisMessageListenerContainer container = new RedisMessageListenerContainer();
        container.setConnectionFactory(factory);

        // 订阅channel1
        container.addMessageListener(
            (message, pattern) -> {
                String msg = new String(message.getBody());
                System.out.println("收到消息：" + msg);
                // 处理消息
            },
            new ChannelTopic("channel1")
        );

        return container;
    }
}
```

**优劣分析**：

```
优势：
- 支持多订阅者（广播）
- 解耦（发布者和订阅者互不感知）

劣势：
- 无消息持久化（订阅者不在线，消息丢失）
- 无消息确认（消费失败无法重试）
- 不适合任务队列（适合通知、广播）

适用场景：
- 消息通知
- 缓存失效通知
- 系统事件广播
```

### 2.3 方案3：基于Stream的高级队列（推荐）

**Redis Stream**（Redis 5.0+）：专业的消息队列数据结构。

```java
/**
 * 生产者：发送消息
 */
@Service
public class StreamProducer {

    @Autowired
    private StringRedisTemplate redisTemplate;

    public void sendMessage(String stream, Map<String, String> message) {
        redisTemplate.opsForStream().add(stream, message);
    }
}

/**
 * 消费者：消费消息（消费组模式）
 */
@Service
public class StreamConsumer {

    @Autowired
    private StringRedisTemplate redisTemplate;

    @PostConstruct
    public void init() {
        String stream = "stream:task";
        String group = "group1";

        // 创建消费组
        try {
            redisTemplate.opsForStream().createGroup(stream, group);
        } catch (Exception e) {
            // 消费组已存在
        }
    }

    @Scheduled(fixedDelay = 1000)
    public void consumeMessages() {
        String stream = "stream:task";
        String group = "group1";
        String consumer = "consumer1";

        // 读取消息（阻塞10秒）
        List<MapRecord<String, String, String>> messages =
            redisTemplate.opsForStream().read(
                Consumer.from(group, consumer),
                StreamReadOptions.empty().count(10).block(Duration.ofSeconds(10)),
                StreamOffset.create(stream, ReadOffset.lastConsumed())
            );

        if (messages == null || messages.isEmpty()) {
            return;
        }

        for (MapRecord<String, String, String> message : messages) {
            try {
                // 处理消息
                processMessage(message.getValue());

                // 确认消息（ACK）
                redisTemplate.opsForStream().acknowledge(
                    stream,
                    group,
                    message.getId()
                );

            } catch (Exception e) {
                log.error("处理消息失败：{}", message.getId(), e);
                // 消息会进入Pending List，可以重新消费
            }
        }
    }

    private void processMessage(Map<String, String> message) {
        log.info("处理消息：{}", message);
        // 业务逻辑
    }
}
```

**Stream的核心特性**：

```
1. 消息持久化
   - Stream存储在Redis内存
   - 支持AOF/RDB持久化
   - Redis重启后消息不丢失

2. 消息确认（ACK）
   - 消费者确认消息
   - 未确认的消息进入Pending List
   - 可以重新消费

3. 消费组（Consumer Group）
   - 多消费者协同工作
   - 消息只被组内一个消费者消费
   - 负载均衡

4. 消息ID
   - 自动生成唯一ID（时间戳-序列号）
   - 支持按ID范围查询

5. 最大长度限制
   - MAXLEN：限制Stream长度
   - 避免内存溢出

6. Pending List
   - 记录已读取但未确认的消息
   - 消费者宕机后，可以由其他消费者接管
```

**Stream vs RabbitMQ vs Kafka**：

| 维度 | Redis Stream | RabbitMQ | Kafka |
|------|-------------|----------|-------|
| 性能 | 极高（10万QPS） | 高（1万QPS） | 极高（100万QPS） |
| 可靠性 | 中（内存+持久化） | 高（持久化+镜像） | 高（分区+副本） |
| 功能 | 基础 | 丰富 | 丰富 |
| 运维 | 简单 | 中等 | 复杂 |
| 适用场景 | 轻量级队列 | 企业级消息队列 | 大数据流处理 |

---

## 三、缓存设计模式

### 3.1 Cache Aside模式（最常用）

```java
/**
 * 读操作
 */
public UserVO getUser(Long userId) {
    String cacheKey = "user:info:" + userId;

    // 1. 查缓存
    UserVO cached = redisTemplate.opsForValue().get(cacheKey);
    if (cached != null) {
        return cached;
    }

    // 2. 查数据库
    User user = userRepository.findById(userId);
    if (user == null) {
        // 缓存空值（防止缓存穿透）
        redisTemplate.opsForValue().set(cacheKey, new UserVO(), 1, TimeUnit.MINUTES);
        throw new UserNotFoundException();
    }

    UserVO vo = convertToVO(user);

    // 3. 写缓存
    redisTemplate.opsForValue().set(cacheKey, vo, 30, TimeUnit.MINUTES);

    return vo;
}

/**
 * 写操作
 */
@Transactional
public void updateUser(User user) {
    // 1. 更新数据库
    userRepository.update(user);

    // 2. 删除缓存（而不是更新缓存）
    String cacheKey = "user:info:" + user.getId();
    redisTemplate.delete(cacheKey);
}
```

### 3.2 缓存三大问题

#### 问题1：缓存穿透

**现象**：查询不存在的数据，缓存和数据库都没有，请求打到数据库。

```java
// 解决方案1：缓存空值
public UserVO getUser(Long userId) {
    String cacheKey = "user:info:" + userId;

    UserVO cached = redisTemplate.opsForValue().get(cacheKey);
    if (cached != null) {
        if (cached.getUserId() == null) {
            throw new UserNotFoundException();  // 缓存的空值
        }
        return cached;
    }

    User user = userRepository.findById(userId);
    if (user == null) {
        // 缓存空值（TTL设短一点）
        redisTemplate.opsForValue().set(cacheKey, new UserVO(), 1, TimeUnit.MINUTES);
        throw new UserNotFoundException();
    }

    UserVO vo = convertToVO(user);
    redisTemplate.opsForValue().set(cacheKey, vo, 30, TimeUnit.MINUTES);

    return vo;
}

// 解决方案2：布隆过滤器
@Service
public class UserService {

    @Autowired
    private RedissonClient redissonClient;

    private RBloomFilter<Long> userIdFilter;

    @PostConstruct
    public void init() {
        // 创建布隆过滤器
        userIdFilter = redissonClient.getBloomFilter("user:id:filter");
        userIdFilter.tryInit(10000000, 0.01);  // 预期元素1000万，误判率1%

        // 初始化：将所有用户ID加入布隆过滤器
        List<Long> userIds = userRepository.findAllUserIds();
        for (Long userId : userIds) {
            userIdFilter.add(userId);
        }
    }

    public UserVO getUser(Long userId) {
        // 先判断userId是否存在
        if (!userIdFilter.contains(userId)) {
            throw new UserNotFoundException();  // 一定不存在
        }

        // 可能存在，继续查询
        String cacheKey = "user:info:" + userId;
        // ... 后续逻辑
    }
}
```

#### 问题2：缓存击穿

**现象**：热点数据过期，瞬间大量请求打到数据库。

```java
// 解决方案1：热点数据永不过期
public UserVO getUser(Long userId) {
    String cacheKey = "user:info:" + userId;

    UserVO cached = redisTemplate.opsForValue().get(cacheKey);
    if (cached != null) {
        return cached;
    }

    User user = userRepository.findById(userId);
    UserVO vo = convertToVO(user);

    // 热点数据不设置过期时间
    redisTemplate.opsForValue().set(cacheKey, vo);

    return vo;
}

// 解决方案2：分布式锁
public UserVO getUser(Long userId) {
    String cacheKey = "user:info:" + userId;
    String lockKey = "lock:user:" + userId;

    UserVO cached = redisTemplate.opsForValue().get(cacheKey);
    if (cached != null) {
        return cached;
    }

    // 获取分布式锁
    RLock lock = redissonClient.getLock(lockKey);

    try {
        lock.lock(10, TimeUnit.SECONDS);

        // 双重检查
        cached = redisTemplate.opsForValue().get(cacheKey);
        if (cached != null) {
            return cached;
        }

        // 查数据库
        User user = userRepository.findById(userId);
        UserVO vo = convertToVO(user);

        // 写缓存
        redisTemplate.opsForValue().set(cacheKey, vo, 30, TimeUnit.MINUTES);

        return vo;

    } finally {
        if (lock.isHeldByCurrentThread()) {
            lock.unlock();
        }
    }
}
```

#### 问题3：缓存雪崩

**现象**：大量缓存同时过期，请求打到数据库。

```java
// 解决方案：过期时间随机化
public void cacheUser(Long userId, UserVO vo) {
    String cacheKey = "user:info:" + userId;

    // 过期时间随机化：30分钟 + 随机0-60秒
    int baseExpire = 30 * 60;
    int randomExpire = new Random().nextInt(60);
    int expireTime = baseExpire + randomExpire;

    redisTemplate.opsForValue().set(cacheKey, vo, expireTime, TimeUnit.SECONDS);
}
```

---

## 四、性能优化实战

### 4.1 Pipeline批量操作

```java
// ❌ 错误：循环单次操作（1000次网络往返）
for (int i = 0; i < 1000; i++) {
    redisTemplate.opsForValue().set("key" + i, "value" + i);
}
// 耗时：1000ms（假设每次1ms）

// ✅ 正确：Pipeline批量操作（1次网络往返）
redisTemplate.executePipelined(new RedisCallback<Object>() {
    @Override
    public Object doInRedis(RedisConnection connection) {
        for (int i = 0; i < 1000; i++) {
            connection.set(("key" + i).getBytes(), ("value" + i).getBytes());
        }
        return null;
    }
});
// 耗时：10ms
// 性能提升：100倍
```

### 4.2 Lua脚本（原子操作）

```java
/**
 * 限流器：固定窗口
 */
public boolean isAllowed(String key, int limit, int window) {
    String script =
        "local current = redis.call('incr', KEYS[1]) " +
        "if current == 1 then " +
        "    redis.call('expire', KEYS[1], ARGV[2]) " +
        "end " +
        "if current > tonumber(ARGV[1]) then " +
        "    return 0 " +
        "else " +
        "    return 1 " +
        "end";

    Long result = redisTemplate.execute(
        new DefaultRedisScript<>(script, Long.class),
        Collections.singletonList(key),
        String.valueOf(limit),
        String.valueOf(window)
    );

    return result != null && result == 1;
}
```

### 4.3 连接池优化

```yaml
spring:
  redis:
    lettuce:
      pool:
        max-active: 16      # 最大连接数
        max-idle: 8         # 最大空闲连接
        min-idle: 4         # 最小空闲连接
        max-wait: 3000ms    # 最大等待时间
      shutdown-timeout: 100ms
```

---

## 五、系列总结

### 5.1 Redis核心知识图谱

```
Redis知识体系：

1. 基础篇：为什么需要Redis？
   └─ 性能：100倍提升
   └─ 成本：10倍降低
   └─ 场景：缓存、Session、计数器

2. 演进篇：从HashMap到Redis
   └─ 单机缓存的局限
   └─ 分布式缓存的价值
   └─ Redis单线程模型

3. 数据结构篇：五大数据结构
   └─ String：KV存储
   └─ List：队列、时间线
   └─ Hash：对象存储
   └─ Set：去重、集合运算
   └─ ZSet：排行榜、范围查询

4. 高可用篇：主从、哨兵、集群
   └─ 主从复制：读写分离
   └─ 哨兵模式：自动故障转移
   └─ 集群模式：水平扩展

5. 持久化篇：RDB与AOF
   └─ RDB：快照，恢复快
   └─ AOF：日志，数据安全
   └─ 混合持久化：推荐

6. 实战篇：分布式锁、消息队列、缓存设计
   └─ 分布式锁：Redisson
   └─ 消息队列：Stream
   └─ 缓存设计：Cache Aside + 三大问题
```

### 5.2 学习路径建议

```
初级（1-2周）：
- 理解Redis的价值
- 掌握五大数据结构
- 能独立使用Redis

中级（1-2月）：
- 掌握主从、哨兵、集群
- 理解持久化机制
- 能设计缓存架构

高级（3-6月）：
- 阅读Redis源码
- 理解底层实现
- 能解决复杂问题
```

### 5.3 生产环境检查清单

```
部署架构：
□ 使用哨兵或集群模式
□ Master配置主从复制
□ 每个Master至少1个Slave

持久化配置：
□ 启用混合持久化
□ appendfsync everysec
□ auto-aof-rewrite-percentage 100

内存配置：
□ 设置maxmemory
□ maxmemory-policy allkeys-lru
□ 预留20%内存（避免OOM）

安全配置：
□ 设置密码（requirepass）
□ 绑定IP（bind）
□ 禁用危险命令（rename-command）

监控告警：
□ 监控内存使用率
□ 监控QPS
□ 监控命中率
□ 监控主从延迟

备份策略：
□ 每日备份RDB/AOF
□ 每周远程备份
□ 定期演练恢复
```

---

## 六、终章寄语

从第一篇到第六篇，我们完成了Redis的系统化学习之旅：

**第一性原理思维**：始终追问"为什么"
- 为什么需要缓存？→ 性能、成本
- 为什么需要Redis？→ 数据结构、高可用
- 为什么需要持久化？→ 数据安全

**渐进式复杂度**：从简单到复杂
- HashMap → Guava Cache → Redis
- 单机 → 主从 → 哨兵 → 集群
- RDB → AOF → 混合持久化

**实战导向**：理论+实践
- 真实业务场景
- 完整代码示例
- 生产环境配置

**系统化思考**：建立知识体系
- 不是简单记忆命令
- 而是理解设计思想
- 培养架构思维

希望这个系列能帮助你：
1. **深入理解Redis**：不仅会用，更知道为什么
2. **建立系统思维**：从点到面，构建知识体系
3. **提升工程能力**：理论结合实践，解决真实问题

**Redis系列完结，感谢陪伴！**

---

**参考资料**：
- 《Redis设计与实现》- 黄健宏
- 《Redis实战》- Josiah L. Carlson
- 《Redis开发与运维》- 付磊、张益军
- Redis官方文档：https://redis.io/documentation
- Redisson文档：https://redisson.org

---

*本文是"Redis第一性原理"系列的第6篇，也是最后一篇。感谢您的阅读！*
