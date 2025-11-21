# Redis专题文章创作指南

## 📋 总体规划

- **专题名称**：Redis从入门到精通
- **总文章数**：64篇
- **学习周期**：3-4个月（每天1-2小时）
- **配色方案**：红色渐变 `#DC382D → #FF6B6B`
- **模块路径**：`content/redis/posts/`

---

## 🎯 六大学习阶段

### 第一阶段：基础入门篇（12篇）
**目标**：理解缓存本质，掌握5大数据类型和核心特性

### 第二阶段：架构原理篇（10篇）
**目标**：深入底层数据结构、单线程模型与高可用架构

### 第三阶段：进阶特性篇（12篇）
**目标**：掌握Lua脚本、高级数据类型、分布式锁等特性

### 第四阶段：生产实践篇（12篇）
**目标**：解决缓存三大问题、性能优化、监控告警与容灾

### 第五阶段：云原生演进篇（8篇）
**目标**：容器化、Kubernetes、服务网格与多云部署

### 第六阶段：源码深度篇（10篇）
**目标**：通过源码理解对象系统、跳表、事件循环等核心实现

---

## ✍️ 文章创作规范

### Front Matter模板

```yaml
---
title: "文章标题"
date: 2025-01-21T10:00:00+08:00  # 注意：必须使用当前或过去时间！
draft: false
tags: ["Redis", "具体技术点1", "具体技术点2"]
categories: ["技术"]
description: "一句话简介，突出核心价值（100字以内）"
weight: 序号  # 01-64
stage: 阶段编号  # 1-6
stageTitle: "阶段名称"  # 基础入门篇/架构原理篇/进阶特性篇/生产实践篇/云原生演进篇/源码深度篇
---
```

### 文件命名规范

```
格式：序号-英文slug.md
示例：
01-why-need-redis.md
02-redis-quick-start.md
03-string-type-deep-dive.md
```

### 文章结构模板

```markdown
## 引言
简短开场（100-200字），点明本文要解决的问题

## 一、从问题出发（第一性原理）
- 为什么需要这个特性/技术？
- 它解决了什么痛点？
- 不用它会怎样？

## 二、核心概念
- 基本原理讲解
- 概念拆解（由浅入深）
- 图示说明

## 三、命令/API详解
- 常用命令列表
- 参数说明
- 返回值解释
- 代码示例

## 四、底层原理（适当深入）
- 数据结构
- 实现机制
- 性能特点

## 五、实战场景
- 场景1：具体业务场景
- 场景2：代码实现
- 场景3：注意事项

## 六、最佳实践
- ✅ 推荐做法
- ❌ 反模式
- ⚠️ 常见坑点

## 七、总结
- 核心要点（3-5条）
- 下一篇预告
- 思考题（可选）
```

---

## 📐 写作原则

### 1. 第一性原理

每个概念都要回答：
- ❓ 为什么需要它？
- ❓ 它解决了什么问题？
- ❓ 不用它会怎样？

### 2. 渐进式复杂度

```
简单例子 → 复杂场景 → 边界情况 → 底层原理
```

不要一上来就讲复杂实现，要让读者先理解"是什么"和"怎么用"。

### 3. 理论+实战

每个知识点都要有：
- 📚 理论讲解
- 💻 代码示例
- 🎯 实战场景
- ⚠️ 注意事项

### 4. 字数控制

| 阶段 | 推荐字数 | 说明 |
|------|---------|------|
| 基础入门篇 | 2500-3500字 | 讲清楚基本用法即可 |
| 架构原理篇 | 3000-4200字 | 需要更多原理讲解 |
| 进阶特性篇 | 3000-4000字 | 场景复杂，需要详细示例 |
| 生产实践篇 | 3500-4000字 | 需要多个实战案例 |
| 云原生篇 | 2800-3500字 | 偏实操 |
| 源码篇 | 3500-4000字 | 源码分析需要细节 |

### 5. 代码规范

```java
// ✅ 好的代码示例：有注释、完整、可运行
public class RedisCache {
    private RedisTemplate<String, Object> redis;

    /**
     * 获取缓存，不存在则查询数据库
     */
    public Product getProduct(Long id) {
        String key = "product:" + id;

        // 1. 先查Redis
        Product product = (Product) redis.opsForValue().get(key);
        if (product != null) {
            return product;
        }

        // 2. Redis未命中，查数据库
        product = productDao.selectById(id);
        if (product != null) {
            // 3. 写入Redis，设置1小时过期
            redis.opsForValue().set(key, product, 3600, TimeUnit.SECONDS);
        }

        return product;
    }
}
```

```bash
# ✅ 命令示例：有注释、有输出
127.0.0.1:6379> SET user:1001 "张三"
OK

127.0.0.1:6379> GET user:1001
"张三"  # 返回值

127.0.0.1:6379> EXPIRE user:1001 3600
(integer) 1  # 1表示成功
```

---

## 📝 第一阶段详细大纲

### 01. 缓存的第一性原理：为什么需要Redis？✅
**核心内容**：
- 存储层次结构（CPU→内存→磁盘→网络）
- 时空矛盾（快的小，大的慢）
- 局部性原理与二八定律
- Redis的定位与价值

**字数**：3000字

### 02. Redis快速入门：安装部署与基本操作 ✅
**核心内容**：
- Docker/Linux/macOS三种安装方式
- 启动、连接、基本命令
- redis-cli使用技巧
- 配置文件简介

**字数**：2500字

### 03. String类型深度解析：最简单也最强大
**核心内容**：
- String的本质（SDS简单动态字符串）
- 常用命令：SET/GET/APPEND/INCR/DECR
- 应用场景：缓存、计数器、分布式锁、限流
- 内存优化技巧

**字数**：3500字

**命令清单**：
```bash
SET key value [EX seconds] [PX milliseconds] [NX|XX]
GET key
APPEND key value
STRLEN key
INCR key / DECR key
INCRBY key increment / DECRBY key decrement
SETEX key seconds value
SETNX key value
MSET key1 value1 [key2 value2 ...]
MGET key1 [key2 ...]
```

**示例场景**：
1. 缓存对象（JSON序列化）
2. 计数器（浏览量、点赞数）
3. 分布式锁（SETNX）
4. 限流器（INCR + EXPIRE）

### 04. Hash类型实战：对象存储的最佳选择
**核心内容**：
- Hash vs String：何时用Hash？
- 常用命令：HSET/HGET/HMGET/HGETALL
- 底层实现：ziplist vs hashtable
- 应用场景：用户信息、商品详情、购物车

**字数**：3000字

**命令清单**：
```bash
HSET key field value
HGET key field
HMSET key field1 value1 [field2 value2 ...]
HMGET key field1 [field2 ...]
HGETALL key
HDEL key field [field ...]
HEXISTS key field
HKEYS key / HVALS key
HLEN key
HINCRBY key field increment
```

**示例场景**：
1. 用户信息存储（避免序列化）
2. 商品详情缓存
3. 购物车实现
4. 对象部分字段更新

### 05. List类型详解：从队列到时间线
**核心内容**：
- List的双端特性
- 常用命令：LPUSH/RPUSH/LPOP/RPOP/LRANGE
- 阻塞命令：BLPOP/BRPOP
- 应用场景：消息队列、时间线、最新列表

**字数**：3200字

**命令清单**：
```bash
LPUSH key value [value ...] / RPUSH key value [value ...]
LPOP key / RPOP key
LRANGE key start stop
LLEN key
LINDEX key index
LSET key index value
LTRIM key start stop
BLPOP key [key ...] timeout
BRPOP key [key ...] timeout
RPOPLPUSH source destination
```

**示例场景**：
1. 简单消息队列
2. 朋友圈时间线
3. 最新文章列表
4. 任务队列

### 06. Set类型应用：去重与集合运算
**核心内容**：
- Set的无序性与唯一性
- 常用命令：SADD/SMEMBERS/SISMEMBER
- 集合运算：SUNION/SINTER/SDIFF
- 应用场景：标签、好友关系、去重、抽奖

**字数**：2800字

**命令清单**：
```bash
SADD key member [member ...]
SMEMBERS key
SISMEMBER key member
SCARD key
SREM key member [member ...]
SPOP key [count]
SRANDMEMBER key [count]
SUNION key [key ...]  # 并集
SINTER key [key ...]  # 交集
SDIFF key [key ...]   # 差集
```

**示例场景**：
1. 文章标签系统
2. 共同好友查询
3. 用户去重统计
4. 抽奖系统

### 07. ZSet有序集合：排行榜的终极方案
**核心内容**：
- ZSet的分数排序机制
- 常用命令：ZADD/ZRANGE/ZREVRANGE/ZRANK
- 底层实现：skiplist（跳表）
- 应用场景：排行榜、延迟队列、范围查询

**字数**：3500字

**命令清单**：
```bash
ZADD key score member [score member ...]
ZRANGE key start stop [WITHSCORES]
ZREVRANGE key start stop [WITHSCORES]
ZRANGEBYSCORE key min max [WITHSCORES] [LIMIT offset count]
ZRANK key member / ZREVRANK key member
ZSCORE key member
ZREM key member [member ...]
ZINCRBY key increment member
ZCARD key
ZCOUNT key min max
```

**示例场景**：
1. 游戏排行榜
2. 热搜榜
3. 延迟队列（定时任务）
4. 范围查询（按时间、按价格）

### 08. 键空间管理：过期策略与淘汰机制
**核心内容**：
- 过期时间设置：EXPIRE/EXPIREAT/TTL
- 过期删除策略：惰性删除、定期删除
- 8种内存淘汰策略：noeviction/allkeys-lru/volatile-lru等
- 应用场景：缓存、会话、验证码

**字数**：4000字

**核心知识点**：
1. **过期策略**：
   - 定时删除（主动）
   - 惰性删除（被动）
   - 定期删除（折中）

2. **淘汰策略**：
   - noeviction：不淘汰，返回错误
   - allkeys-lru：所有key，LRU算法
   - volatile-lru：有过期时间的key，LRU
   - allkeys-random：所有key，随机
   - volatile-random：有过期时间的key，随机
   - volatile-ttl：有过期时间的key，TTL越小越先淘汰
   - allkeys-lfu：所有key，LFU算法（4.0+）
   - volatile-lfu：有过期时间的key，LFU

### 09. 持久化入门：RDB快照详解
**核心内容**：
- RDB原理：内存快照
- 触发机制：SAVE/BGSAVE/自动触发
- 配置参数：save 900 1
- 优缺点分析
- 应用场景：全量备份、灾难恢复

**字数**：3200字

**核心知识点**：
1. RDB文件格式
2. fork机制（写时复制）
3. 性能影响
4. 数据安全性

### 10. 持久化进阶：AOF日志详解
**核心内容**：
- AOF原理：命令日志
- 三种同步策略：always/everysec/no
- AOF重写机制：减小文件体积
- 混合持久化（4.0+）
- RDB vs AOF对比

**字数**：3800字

**核心知识点**：
1. AOF文件格式（RESP协议）
2. AOF重写触发条件
3. 数据恢复流程
4. 性能与安全权衡

### 11. 事务与原子性：MULTI/EXEC命令详解
**核心内容**：
- Redis事务的特点（不完全ACID）
- 命令：MULTI/EXEC/DISCARD
- WATCH乐观锁
- 与关系型数据库事务的对比
- 应用场景：批量操作、库存扣减

**字数**：3000字

**核心知识点**：
1. Redis事务不支持回滚
2. 命令错误 vs 执行错误
3. WATCH实现CAS
4. Lua脚本更强大

### 12. 管道Pipeline：批量操作性能优化
**核心内容**：
- RTT延迟问题
- Pipeline原理：批量发送命令
- 使用方法（Jedis/Lettuce）
- Pipeline vs 事务 vs 原生批量命令
- 注意事项：命令数量、原子性

**字数**：2500字

**核心知识点**：
1. 网络RTT是瓶颈
2. Pipeline不保证原子性
3. 适用场景：大量读写操作
4. 性能提升：10-100倍

---

## 🎨 写作技巧

### 1. 开头要抓人

❌ **糟糕的开头**：
> "本文介绍Redis的String类型，包括命令和用法。"

✅ **好的开头**：
> "为什么淘宝首页能在1ms内返回？为什么微博热搜能实时更新？答案就藏在Redis的String类型中。今天我们从第一性原理出发，理解String为什么是Redis中最简单也最强大的数据类型。"

### 2. 概念要类比

❌ **晦涩的概念**：
> "Redis使用跳表实现有序集合，时间复杂度O(logN)。"

✅ **通俗的类比**：
> "想象一本字典。如果你要查'Redis'这个词，最笨的方法是从第一页翻到最后一页（O(n)）。聪明的方法是先看目录，直接跳到R开头的章节（O(logN)）。Redis的跳表就像给数据加了'目录索引'。"

### 3. 图示要清晰

```
✅ 推荐用ASCII图或Mermaid图

内存 → Redis → CPU
 ↓      ↑ 命中
数据库  ← 未命中
```

### 4. 代码要完整

❌ **不完整的代码**：
```java
redis.set(key, value);
```

✅ **完整可运行的代码**：
```java
@Service
public class RedisService {
    @Autowired
    private RedisTemplate<String, Object> redis;

    public void cacheUser(User user) {
        String key = "user:" + user.getId();
        redis.opsForValue().set(key, user, 3600, TimeUnit.SECONDS);
    }
}
```

---

## 🚀 快速创作流程

### Step 1: 确定大纲（5分钟）
```
- 核心问题是什么？
- 要讲哪些知识点？
- 举什么例子？
```

### Step 2: 写引言（10分钟）
```
- 提出问题
- 引起兴趣
- 预告内容
```

### Step 3: 写主体（60-90分钟）
```
- 从简单到复杂
- 每个概念都有代码示例
- 理论+实战结合
```

### Step 4: 写总结（10分钟）
```
- 提炼核心要点
- 预告下一篇
- 可选：思考题
```

### Step 5: 校对优化（10-15分钟）
```
- 检查代码是否可运行
- 检查标点符号
- 检查排版格式
```

---

## 📊 质量检查清单

- [ ] Front Matter完整正确（date必须是当前或过去时间）
- [ ] 文章标题吸引人
- [ ] 引言提出了明确的问题
- [ ] 遵循"第一性原理→渐进式复杂度"
- [ ] 每个概念都有代码示例
- [ ] 代码可以运行（或明确标注伪代码）
- [ ] 有实战场景
- [ ] 有总结和下一篇预告
- [ ] 字数在推荐范围内
- [ ] 排版整洁，易于阅读

---

## 🔗 参考资源

**官方文档**：
- https://redis.io/docs/
- https://redis.io/commands/

**书籍推荐**：
- 《Redis设计与实现》 - 黄健宏
- 《Redis深度历险》 - 钱文品

**源码阅读**：
- https://github.com/redis/redis

---

## 📌 重要提醒

1. **date字段必须使用当前或过去时间**，否则Hugo不会发布文章！
2. **weight字段用于排序**，01-64依次递增
3. **stage字段用于分组显示**，1-6对应六个阶段
4. **每篇文章独立完整**，不要出现"详见上一篇"或"下一篇详解"

---

开始创作吧！每完成一篇文章，就更新一次todo，给自己一点成就感 ✨
