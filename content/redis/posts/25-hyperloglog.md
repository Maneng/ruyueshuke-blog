---
title: "HyperLogLog：基数统计的神器"
date: 2025-01-21T22:20:00+08:00
draft: false
tags: ["Redis", "HyperLogLog", "基数统计", "UV"]
categories: ["技术"]
description: "掌握Redis HyperLogLog原理，实现UV统计、独立IP统计等场景，12KB内存统计亿级数据，误差率仅0.81%"
weight: 25
stage: 3
stageTitle: "进阶特性篇"
---

## 什么是HyperLogLog？

**基数统计**：统计集合中不重复元素的个数（Cardinality）

**问题**：1亿用户UV统计需要多少内存？
```
方案1：Set存储所有userId
内存：1亿 * 8字节 = 763 MB

方案2：HyperLogLog
内存：12 KB（固定）
误差：0.81%
```

**核心优势**：
- ✅ 固定内存（12KB）
- ✅ 超高性能
- ❌ 有误差（0.81%）
- ❌ 无法获取具体元素

## 核心命令

```bash
# 添加元素
PFADD key element [element ...]

# 获取基数
PFCOUNT key [key ...]

# 合并多个HyperLogLog
PFMERGE destkey sourcekey [sourcekey ...]
```

## 实战案例

### 案例1：网站UV统计

```java
@Service
public class UVStatService {
    @Autowired
    private RedisTemplate<String, Object> redis;

    // 记录用户访问
    public void recordVisit(String userId) {
        String key = "uv:" + LocalDate.now();
        redis.opsForHyperLogLog().add(key, userId);
        redis.expire(key, 90, TimeUnit.DAYS);
    }

    // 获取今日UV
    public Long getTodayUV() {
        String key = "uv:" + LocalDate.now();
        return redis.opsForHyperLogLog().size(key);
    }

    // 获取近7天UV
    public Long getWeekUV() {
        List<String> keys = new ArrayList<>();
        for (int i = 0; i < 7; i++) {
            keys.add("uv:" + LocalDate.now().minusDays(i));
        }
        return redis.opsForHyperLogLog().size(keys.toArray(new String[0]));
    }

    // 获取本月UV
    public Long getMonthUV() {
        LocalDate now = LocalDate.now();
        List<String> keys = new ArrayList<>();
        for (int i = 1; i <= now.getDayOfMonth(); i++) {
            keys.add("uv:" + now.withDayOfMonth(i));
        }
        return redis.opsForHyperLogLog().size(keys.toArray(new String[0]));
    }
}
```

### 案例2：页面独立访客统计

```java
@Service
public class PageUVService {
    @Autowired
    private RedisTemplate<String, Object> redis;

    // 记录页面访问
    public void recordPageVisit(String pageId, String userId) {
        String key = "page:uv:" + pageId + ":" + LocalDate.now();
        redis.opsForHyperLogLog().add(key, userId);
        redis.expire(key, 30, TimeUnit.DAYS);
    }

    // 获取页面UV
    public Long getPageUV(String pageId) {
        String key = "page:uv:" + pageId + ":" + LocalDate.now();
        return redis.opsForHyperLogLog().size(key);
    }

    // 统计TOP 10热门页面
    public Map<String, Long> getTopPages(List<String> pageIds) {
        Map<String, Long> result = new LinkedHashMap<>();
        for (String pageId : pageIds) {
            Long uv = getPageUV(pageId);
            result.put(pageId, uv);
        }
        return result.entrySet().stream()
            .sorted(Map.Entry.<String, Long>comparingByValue().reversed())
            .limit(10)
            .collect(Collectors.toMap(
                Map.Entry::getKey,
                Map.Entry::getValue,
                (e1, e2) -> e1,
                LinkedHashMap::new
            ));
    }
}
```

### 案例3：独立IP统计

```java
@Service
public class IPStatService {
    @Autowired
    private RedisTemplate<String, Object> redis;

    // 记录IP访问
    public void recordIP(String ip) {
        String hourKey = "ip:hour:" + LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMddHH"));
        String dayKey = "ip:day:" + LocalDate.now();

        redis.opsForHyperLogLog().add(hourKey, ip);
        redis.opsForHyperLogLog().add(dayKey, ip);

        redis.expire(hourKey, 2, TimeUnit.DAYS);
        redis.expire(dayKey, 90, TimeUnit.DAYS);
    }

    // 当前小时独立IP
    public Long getCurrentHourIP() {
        String key = "ip:hour:" + LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMddHH"));
        return redis.opsForHyperLogLog().size(key);
    }

    // 今日独立IP
    public Long getTodayIP() {
        String key = "ip:day:" + LocalDate.now();
        return redis.opsForHyperLogLog().size(key);
    }

    // 近24小时独立IP趋势
    public List<Map<String, Object>> get24HourTrend() {
        List<Map<String, Object>> result = new ArrayList<>();
        LocalDateTime now = LocalDateTime.now();

        for (int i = 23; i >= 0; i--) {
            LocalDateTime time = now.minusHours(i);
            String key = "ip:hour:" + time.format(DateTimeFormatter.ofPattern("yyyyMMddHH"));
            Long count = redis.opsForHyperLogLog().size(key);

            Map<String, Object> item = new HashMap<>();
            item.put("hour", time.format(DateTimeFormatter.ofPattern("HH:00")));
            item.put("count", count);
            result.add(item);
        }
        return result;
    }
}
```

### 案例4：APP活跃用户统计

```java
@Service
public class DAUService {
    @Autowired
    private RedisTemplate<String, Object> redis;

    // 记录用户活跃
    public void recordActive(Long userId) {
        String key = "dau:" + LocalDate.now();
        redis.opsForHyperLogLog().add(key, String.valueOf(userId));
        redis.expire(key, 90, TimeUnit.DAYS);
    }

    // 今日DAU（Daily Active Users）
    public Long getTodayDAU() {
        String key = "dau:" + LocalDate.now();
        return redis.opsForHyperLogLog().size(key);
    }

    // 近7天DAU
    public Long getWeekDAU() {
        List<String> keys = new ArrayList<>();
        for (int i = 0; i < 7; i++) {
            keys.add("dau:" + LocalDate.now().minusDays(i));
        }
        return redis.opsForHyperLogLog().size(keys.toArray(new String[0]));
    }

    // 近30天DAU（MAU - Monthly Active Users）
    public Long getMonthMAU() {
        List<String> keys = new ArrayList<>();
        for (int i = 0; i < 30; i++) {
            keys.add("dau:" + LocalDate.now().minusDays(i));
        }
        return redis.opsForHyperLogLog().size(keys.toArray(new String[0]));
    }

    // 计算留存率
    public double getRetentionRate(LocalDate startDate, int days) {
        String startKey = "dau:" + startDate;
        String endKey = "dau:" + startDate.plusDays(days);

        Long startDAU = redis.opsForHyperLogLog().size(startKey);
        Long endDAU = redis.opsForHyperLogLog().size(endKey);

        if (startDAU == null || startDAU == 0) {
            return 0.0;
        }
        return (double) endDAU / startDAU;
    }
}
```

## 合并统计

```bash
# 合并多个HyperLogLog
PFMERGE result uv:20250101 uv:20250102 uv:20250103

# 查询合并后的基数
PFCOUNT result
```

**Java实现**：
```java
// 合并多日UV
public Long mergeUV(List<LocalDate> dates, String resultKey) {
    List<String> keys = dates.stream()
        .map(date -> "uv:" + date)
        .collect(Collectors.toList());

    redis.opsForHyperLogLog().union(resultKey, keys.toArray(new String[0]));
    redis.expire(resultKey, 1, TimeUnit.HOURS);

    return redis.opsForHyperLogLog().size(resultKey);
}
```

## 原理简述

**核心思想**：基于概率统计

```
1. 对每个元素计算hash值
2. hash值转为二进制，统计末尾连续0的个数
3. 记录最大连续0个数
4. 基数估算 ≈ 2^(最大连续0个数)

示例：
hash(user1) = 0b00110100 → 0个连续0
hash(user2) = 0b10101000 → 3个连续0 ← 最大
hash(user3) = 0b01100000 → 5个连续0 ← 最大

估算基数 ≈ 2^5 = 32

实际HyperLogLog使用16384个桶（2^14），精度更高
```

**误差率**：0.81%
```
真实基数：1000000
HyperLogLog统计：约1000000 ± 8100
```

## 内存占用对比

```
场景：1亿UV统计

方案1：Set
内存：1亿 * 8字节 = 763 MB

方案2：Bitmap
内存：1亿 bits / 8 = 12.5 MB
问题：需要连续的userId

方案3：HyperLogLog
内存：12 KB（固定）
误差：0.81%

适用场景：
- Set：需要精确统计，数据量小
- Bitmap：userId连续，需要精确统计
- HyperLogLog：数据量大，允许误差
```

## 最佳实践

### 1. 合理设置过期时间

```java
// UV数据保留90天
redis.opsForHyperLogLog().add(key, userId);
redis.expire(key, 90, TimeUnit.DAYS);
```

### 2. 定时聚合数据

```java
@Scheduled(cron = "0 0 1 * * ?")  // 每天凌晨1点
public void aggregateMonthlyUV() {
    LocalDate now = LocalDate.now();
    String monthKey = "uv:month:" + now.format(DateTimeFormatter.ofPattern("yyyyMM"));

    List<String> dayKeys = new ArrayList<>();
    for (int i = 1; i <= now.getDayOfMonth(); i++) {
        dayKeys.add("uv:" + now.withDayOfMonth(i));
    }

    redis.opsForHyperLogLog().union(monthKey, dayKeys.toArray(new String[0]));
    redis.expire(monthKey, 365, TimeUnit.DAYS);

    log.info("月UV聚合完成: {}, UV: {}", monthKey, redis.opsForHyperLogLog().size(monthKey));
}
```

### 3. 与精确统计对比

```java
@Service
public class UVComparisonService {
    @Autowired
    private RedisTemplate<String, Object> redis;

    // 同时使用HyperLogLog和Set统计（小数据量）
    public void recordVisit(String userId) {
        String hllKey = "uv:hll:" + LocalDate.now();
        String setKey = "uv:set:" + LocalDate.now();

        // HyperLogLog统计
        redis.opsForHyperLogLog().add(hllKey, userId);

        // Set精确统计（用于对比）
        redis.opsForSet().add(setKey, userId);

        redis.expire(hllKey, 1, TimeUnit.DAYS);
        redis.expire(setKey, 1, TimeUnit.DAYS);
    }

    // 对比误差
    public void compareError() {
        String hllKey = "uv:hll:" + LocalDate.now();
        String setKey = "uv:set:" + LocalDate.now();

        Long hllCount = redis.opsForHyperLogLog().size(hllKey);
        Long setCount = redis.opsForSet().size(setKey);

        double error = Math.abs(hllCount - setCount) / (double) setCount * 100;
        log.info("精确UV: {}, HyperLogLog UV: {}, 误差: {}%",
            setCount, hllCount, String.format("%.2f", error));
    }
}
```

## 限制与注意事项

1. **只能统计基数**：无法获取具体元素
2. **有误差**：标准误差0.81%
3. **不可删除元素**：只能整体删除
4. **固定内存**：12KB，与元素数量无关

## 总结

**核心价值**：
- 固定内存（12KB）
- 统计亿级数据
- 误差可控（0.81%）

**典型场景**：
- UV统计（网站、APP、页面）
- 独立IP统计
- DAU/MAU统计
- 用户去重计数

**适用条件**：
- 数据量大（百万级以上）
- 只需要基数，不需要具体元素
- 允许0.81%误差

**不适用场景**：
- 需要精确统计
- 需要获取具体元素
- 需要删除特定元素
- 数据量很小（<1万）
