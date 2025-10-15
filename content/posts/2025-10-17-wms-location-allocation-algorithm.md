---
title: "WMS仓储系统：库位分配算法的演进之路"
date: 2025-10-15T11:00:00+08:00
draft: false
tags: ["WMS", "仓储系统", "算法优化", "DDD", "供应链"]
categories: ["技术"]
description: "从随机分配到智能优化，完整展现WMS库位分配算法的演进历程。包含ABC分类法、动态优化策略和DDD领域驱动设计实践，附带生产环境真实效果数据。"
series: ["供应链系统实战"]
weight: 3
comments: true
---

## 引子：一个仓库主管的抱怨

"为什么拣货员每天要走10公里路？明明商品就在那里，为什么不能放得更合理一点？"

这是2022年夏天，我们深圳仓库主管老张的抱怨。他给我看了仓库的热力图——拣货员的行走轨迹遍布整个仓库，像一张密密麻麻的蜘蛛网。

**数据更触目惊心**：
- 8个仓库，总面积50,000+平方米
- 每天处理2万+出库单
- 拣货员人均每天行走路径：**10.5公里**
- 单笔订单平均拣货时间：**18分钟**

问题的根源在于：**我们的库位分配策略太随机了**。新到货的商品，系统找到第一个空闲库位就塞进去，完全不考虑商品的出库频率、拣货路径、库位高度等因素。

经过3个月的算法优化和系统重构，我们实现了：
- 拣货效率提升**40%**
- 人均行走路径减少至**6.3公里**
- 单笔订单拣货时间缩短至**10分钟**
- 空间利用率提升**15%**

这篇文章，就是那段时间算法演进的完整技术总结。

---

## 库位分配的业务价值

在讲算法之前，先理解为什么库位分配如此重要：

### 1. 拣货效率

**核心指标**：拣货路径长度

```
场景：订单包含3个商品（A、B、C）

方案1（随机分配）：
  入口 → A(100m) → B(300m) → C(50m) → 出口(150m)
  总路径：600m

方案2（优化分配）：
  入口 → A(20m) → B(30m) → C(40m) → 出口(50m)
  总路径：140m

效率提升：(600-140)/600 = 76.7%
```

### 2. 空间利用率

**核心指标**：库位满载率

- 重货在下层（承重强）
- 轻货在上层（便于搬运）
- 大件在地面库位
- 小件在货架

### 3. 作业安全

- 易碎品避开高层库位
- 危险品单独存放
- 高频商品避开拥挤区域

---

## 算法演进：从V1.0到V3.0

### V1.0：随机分配（最简单，最差）

**实现逻辑**：

```java
@Service
public class LocationAllocationServiceV1 {

    /**
     * V1.0：找第一个空闲库位
     */
    public Location allocate(Product product) {
        // 查询所有空闲库位
        List<Location> emptyLocations =
            locationRepository.findByStatus(LocationStatus.EMPTY);

        if (empty Locations.isEmpty()) {
            throw new NoAvailableLocationException();
        }

        // 返回第一个
        return emptyLocations.get(0);
    }
}
```

**优点**：
- 实现简单
- 响应快速（<10ms）

**缺点**：
- 完全不考虑业务场景
- 拣货路径极长
- 空间利用率低
- **仓库主管抱怨**

---

### V2.0：ABC分类法（业务驱动）

**核心思想**：根据商品出库频率分区存放

#### ABC分类规则

```java
/**
 * 商品ABC分类
 */
public enum ProductCategory {
    A("高频商品", "出口附近", "80%销量"),
    B("中频商品", "中间区域", "15%销量"),
    C("低频商品", "偏远区域", "5%销量");

    private final String desc;
    private final String zone;
    private final String salesRatio;
}

@Service
public class ProductCategoryService {

    /**
     * 根据历史出库频率分类
     */
    public ProductCategory classify(String sku) {
        // 统计最近30天出库次数
        int outboundCount = statisticsRepository
            .countOutboundLast30Days(sku);

        if (outboundCount >= 100) {
            return ProductCategory.A;  // 高频
        } else if (outboundCount >= 20) {
            return ProductCategory.B;  // 中频
        } else {
            return ProductCategory.C;  // 低频
        }
    }
}
```

#### 库位区域划分

```java
/**
 * 仓库区域配置
 */
@Configuration
public class WarehouseZoneConfig {

    public Map<ProductCategory, List<String>> getZoneMapping() {
        Map<ProductCategory, List<String>> mapping = new HashMap<>();

        // A类商品：靠近出口的黄金区域
        mapping.put(ProductCategory.A, Arrays.asList(
            "A-01", "A-02", "A-03",  // 一层出口附近
            "B-01", "B-02"           // 二层电梯附近
        ));

        // B类商品：中间区域
        mapping.put(ProductCategory.B, Arrays.asList(
            "A-04", "A-05", "A-06",
            "B-03", "B-04", "B-05"
        ));

        // C类商品：偏远区域
        mapping.put(ProductCategory.C, Arrays.asList(
            "C-01", "C-02", "C-03",  // 角落区域
            "D-01", "D-02"           // 最远区域
        ));

        return mapping;
    }
}
```

#### V2.0核心代码

```java
@Service
public class LocationAllocationServiceV2 {

    @Autowired
    private ProductCategoryService categoryService;

    @Autowired
    private WarehouseZoneConfig zoneConfig;

    /**
     * V2.0：按ABC分类分配
     */
    public Location allocate(Product product) {
        // 1. 商品分类
        ProductCategory category = categoryService.classify(product.getSku());

        // 2. 获取目标区域
        List<String> targetZones = zoneConfig.getZoneMapping().get(category);

        // 3. 在目标区域找空闲库位
        List<Location> emptyLocations = locationRepository
            .findByZoneInAndStatus(targetZones, LocationStatus.EMPTY);

        if (emptyLocations.isEmpty()) {
            // 降级：跨区域查找
            return findFromOtherZones(product);
        }

        // 4. 优先选择低层库位（便于拣货）
        return emptyLocations.stream()
            .min(Comparator.comparing(Location::getLevel))
            .orElse(emptyLocations.get(0));
    }

    private Location findFromOtherZones(Product product) {
        // 跨区域查找逻辑
        return locationRepository.findFirstByStatus(LocationStatus.EMPTY);
    }
}
```

**效果数据**：

| 指标 | V1.0（随机） | V2.0（ABC） | 提升 |
|------|-------------|------------|------|
| 平均拣货路径 | 600m | 320m | **46.7%** |
| 拣货时间 | 18分钟 | 12分钟 | **33.3%** |
| 空间利用率 | 65% | 72% | **10.8%** |

---

### V3.0：动态优化（数据驱动）

V2.0的问题：**ABC分类是静态的**，无法应对季节性变化、促销活动等动态场景。

#### 核心改进

1. **实时出库频率统计**
2. **机器学习预测热门商品**
3. **动态调整库位权重**

#### 权重计算模型

```java
@Service
public class DynamicWeightService {

    /**
     * 计算库位权重（越小越优）
     */
    public double calculateWeight(Location location, Product product) {
        double weight = 0.0;

        // 1. 距离权重（40%）
        double distanceWeight = calculateDistanceWeight(location);
        weight += distanceWeight * 0.4;

        // 2. 高度权重（30%）
        double heightWeight = calculateHeightWeight(location, product);
        weight += heightWeight * 0.3;

        // 3. 拥挤度权重（20%）
        double congestionWeight = calculateCongestionWeight(location);
        weight += congestionWeight * 0.2;

        // 4. 兼容性权重（10%）
        double compatibilityWeight = calculateCompatibilityWeight(location, product);
        weight += compatibilityWeight * 0.1;

        return weight;
    }

    /**
     * 距离权重：基于历史拣货热力图
     */
    private double calculateDistanceWeight(Location location) {
        // 从缓存获取该库位的平均拣货路径
        Double avgDistance = redisTemplate.opsForValue()
            .get("location:distance:" + location.getCode());

        if (avgDistance == null) {
            // 计算该库位到出口的直线距离
            return location.distanceToExit();
        }

        return avgDistance;
    }

    /**
     * 高度权重：重货在下，轻货在上
     */
    private double calculateHeightWeight(Location location, Product product) {
        int level = location.getLevel();  // 层数：1-5
        double weight = product.getWeight();  // 商品重量

        if (weight > 20.0 && level > 2) {
            // 重货在高层，权重很高（不推荐）
            return 100.0;
        } else if (weight < 5.0 && level == 1) {
            // 轻货在底层，浪费空间
            return 50.0;
        }

        return level * 10.0;  // 正常情况
    }

    /**
     * 拥挤度权重：避开拥挤区域
     */
    private double calculateCongestionWeight(Location location) {
        String zone = location.getZone();

        // 查询该区域当前拣货人数
        Long activePickersCount = redisTemplate.opsForSet()
            .size("zone:pickers:" + zone);

        return activePickersCount != null ? activePickersCount * 20.0 : 0.0;
    }

    /**
     * 兼容性权重：同类商品集中存放
     */
    private double calculateCompatibilityWeight(Location location, Product product) {
        // 查询该库位附近是否有同类商品
        boolean hasSameCategory = locationRepository
            .existsNearbySameCategory(location, product.getCategory());

        return hasSameCategory ? 0.0 : 30.0;
    }
}
```

#### V3.0完整实现

```java
@Service
public class LocationAllocationServiceV3 {

    @Autowired
    private DynamicWeightService weightService;

    @Autowired
    private LocationRepository locationRepository;

    /**
     * V3.0：动态权重优化
     */
    public Location allocate(Product product) {
        // 1. 查询所有可用库位
        List<Location> availableLocations =
            locationRepository.findByStatus(LocationStatus.EMPTY);

        if (availableLocations.isEmpty()) {
            throw new NoAvailableLocationException();
        }

        // 2. 计算每个库位的权重
        Map<Location, Double> weightMap = availableLocations.stream()
            .collect(Collectors.toMap(
                location -> location,
                location -> weightService.calculateWeight(location, product)
            ));

        // 3. 选择权重最小的库位
        Location bestLocation = weightMap.entrySet().stream()
            .min(Map.Entry.comparingByValue())
            .map(Map.Entry::getKey)
            .orElse(availableLocations.get(0));

        log.info("分配库位：{}, 权重：{}", bestLocation.getCode(),
            weightMap.get(bestLocation));

        return bestLocation;
    }
}
```

---

## DDD领域驱动设计实践

### 聚合根：库位（Location）

```java
@Entity
@Table(name = "wms_location")
public class Location {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String code;          // 库位编号：A-01-03-02
    private String zone;          // 区域：A
    private Integer level;        // 层数：1-5
    private LocationStatus status; // 状态：EMPTY/OCCUPIED/LOCKED

    // 坐标（用于距离计算）
    @Embedded
    private Coordinate coordinate;

    /**
     * 领域行为：占用库位
     */
    public void occupy(String sku) {
        if (this.status != LocationStatus.EMPTY) {
            throw new LocationNotAvailableException(
                "库位" + this.code + "不可用");
        }

        this.status = LocationStatus.OCCUPIED;
        this.occupiedSku = sku;
        this.occupiedTime = LocalDateTime.now();

        // 发布领域事件
        DomainEventPublisher.publish(
            new LocationOccupiedEvent(this.code, sku));
    }

    /**
     * 领域行为：释放库位
     */
    public void release() {
        if (this.status != LocationStatus.OCCUPIED) {
            throw new IllegalStateException(
                "库位" + this.code + "未被占用");
        }

        this.status = LocationStatus.EMPTY;
        this.occupiedSku = null;
        this.releasedTime = LocalDateTime.now();

        DomainEventPublisher.publish(
            new LocationReleasedEvent(this.code));
    }

    /**
     * 领域计算：到出口的距离
     */
    public double distanceToExit() {
        Coordinate exitCoordinate = WarehouseConfig.getExitCoordinate();
        return this.coordinate.distanceTo(exitCoordinate);
    }
}
```

### 值对象：坐标（Coordinate）

```java
@Embeddable
public class Coordinate {

    private Double x;  // X坐标
    private Double y;  // Y坐标
    private Double z;  // Z坐标（高度）

    /**
     * 计算到另一个坐标的欧几里得距离
     */
    public double distanceTo(Coordinate other) {
        double dx = this.x - other.x;
        double dy = this.y - other.y;
        double dz = this.z - other.z;

        return Math.sqrt(dx * dx + dy * dy + dz * dz);
    }

    /**
     * 值对象必须重写equals和hashCode
     */
    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof Coordinate)) return false;
        Coordinate that = (Coordinate) o;
        return Objects.equals(x, that.x) &&
               Objects.equals(y, that.y) &&
               Objects.equals(z, that.z);
    }

    @Override
    public int hashCode() {
        return Objects.hash(x, y, z);
    }
}
```

### 领域服务：库位分配服务

```java
@Service
public class LocationAllocationDomainService {

    /**
     * 领域服务：为商品分配最优库位
     */
    public AllocationResult allocate(Product product, List<Location> candidates) {
        // 1. 过滤不符合条件的库位
        List<Location> validLocations = candidates.stream()
            .filter(location -> location.canStore(product))
            .collect(Collectors.toList());

        if (validLocations.isEmpty()) {
            return AllocationResult.failed("无可用库位");
        }

        // 2. 计算权重并排序
        Location bestLocation = validLocations.stream()
            .min(Comparator.comparing(location ->
                calculateScore(location, product)))
            .orElseThrow();

        // 3. 占用库位
        bestLocation.occupy(product.getSku());

        return AllocationResult.success(bestLocation);
    }

    private double calculateScore(Location location, Product product) {
        // 调用V3.0的权重计算
        return dynamicWeightService.calculateWeight(location, product);
    }
}
```

---

## 效果数据与经验总结

### 最终效果

| 指标 | V1.0 | V2.0 | V3.0 | 总提升 |
|------|------|------|------|--------|
| 拣货路径 | 600m | 320m | 220m | **63.3%** |
| 拣货时间 | 18分钟 | 12分钟 | 10分钟 | **44.4%** |
| 空间利用率 | 65% | 72% | 75% | **15.4%** |
| 人均日行走 | 10.5km | 7.8km | 6.3km | **40%** |

### 核心经验

#### ✅ DO

1. **先业务后技术**：V2.0的ABC分类比V1.0的随机重要得多
2. **数据驱动优化**：V3.0基于真实数据计算权重
3. **DDD建模**：库位是聚合根，有清晰的领域行为
4. **灰度发布**：先在一个仓库试点，验证后推广
5. **实时监控**：拣货路径热力图、库位使用率大盘

#### ❌ DON'T

1. **不要过度优化**：V3.0的复杂度已经足够，不要引入AI
2. **不要忽略异常**：库位占用冲突、货架倒塌等
3. **不要静态分类**：ABC分类需要定期重新计算
4. **不要忽略人因**：拣货员的经验也很重要

---

## 参考资料

- [仓储管理系统设计与实现](https://book.douban.com/)
- [DDD领域驱动设计](https://www.domainlanguage.com/)

---

## 系列文章

本文是《供应链系统实战》系列的第三篇：

- **第1篇**：渠道共享库存中心 - Redis分布式锁的生产实践 ✅
- **第2篇**：跨境电商关务系统 - 三单对碰的技术实现 ✅
- **第3篇**：WMS仓储系统 - 库位分配算法的演进之路 ✅
- **第4篇**：OMS订单系统 - 智能拆单规则引擎设计（即将发布）
- **第5篇**：供应链数据中台 - Flink实时计算架构实战（即将发布）

---

*如果这篇文章对你有帮助，欢迎在评论区分享你的WMS系统经验。*
