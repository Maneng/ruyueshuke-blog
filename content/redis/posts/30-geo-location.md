---
title: "GEO地理位置：附近的人与LBS服务"
date: 2025-01-21T23:10:00+08:00
draft: false
tags: ["Redis", "GEO", "LBS", "地理位置"]
categories: ["技术"]
description: "掌握Redis GEO地理位置功能，实现附近的人、周边搜索、配送范围判断等LBS场景"
weight: 30
stage: 3
stageTitle: "进阶特性篇"
---

## GEO核心命令

```bash
# 添加地理位置
GEOADD key longitude latitude member

# 获取位置坐标
GEOPOS key member [member ...]

# 计算距离
GEODIST key member1 member2 [unit]

# 范围查询
GEORADIUS key longitude latitude radius unit [WITHCOORD] [WITHDIST] [COUNT count]

# 以成员为中心查询
GEORADIUSBYMEMBER key member radius unit [WITHCOORD] [WITHDIST] [COUNT count]

# 获取GeoHash
GEOHASH key member [member ...]
```

**单位**：m（米）、km（千米）、mi（英里）、ft（英尺）

## 实战案例

### 案例1：附近的人

```java
@Service
public class NearbyPeopleService {
    @Autowired
    private RedisTemplate<String, String> redis;

    private static final String GEO_KEY = "user:location";

    // 更新用户位置
    public void updateLocation(Long userId, double longitude, double latitude) {
        redis.opsForGeo().add(GEO_KEY,
            new Point(longitude, latitude),
            String.valueOf(userId));
    }

    // 查找附近的人（5km内）
    public List<NearbyUser> findNearby(Long userId, double radius) {
        // 获取用户位置
        List<Point> positions = redis.opsForGeo().position(GEO_KEY, String.valueOf(userId));
        if (positions == null || positions.isEmpty()) {
            return Collections.emptyList();
        }

        Point userPos = positions.get(0);

        // 查询附近的人
        GeoResults<GeoLocation<String>> results = redis.opsForGeo().radius(
            GEO_KEY,
            userPos,
            new Distance(radius, Metrics.KILOMETERS),
            GeoRadiusCommandArgs.newGeoRadiusArgs()
                .includeDistance()
                .sortAscending()
                .limit(50)
        );

        if (results == null) {
            return Collections.emptyList();
        }

        List<NearbyUser> nearbyUsers = new ArrayList<>();
        for (GeoResult<GeoLocation<String>> result : results) {
            Long nearbyUserId = Long.valueOf(result.getContent().getName());
            if (!nearbyUserId.equals(userId)) {  // 排除自己
                NearbyUser user = new NearbyUser();
                user.setUserId(nearbyUserId);
                user.setDistance(result.getDistance().getValue());
                nearbyUsers.add(user);
            }
        }

        return nearbyUsers;
    }

    // 计算两用户间距离
    public Double getDistance(Long userId1, Long userId2) {
        Distance distance = redis.opsForGeo().distance(
            GEO_KEY,
            String.valueOf(userId1),
            String.valueOf(userId2),
            Metrics.KILOMETERS
        );
        return distance != null ? distance.getValue() : null;
    }
}
```

### 案例2：外卖配送范围判断

```java
@Service
public class DeliveryService {
    @Autowired
    private RedisTemplate<String, String> redis;

    private static final String STORE_GEO_KEY = "store:location";
    private static final double MAX_DELIVERY_DISTANCE = 5.0;  // 5km配送范围

    // 添加店铺位置
    public void addStore(Long storeId, double longitude, double latitude) {
        redis.opsForGeo().add(STORE_GEO_KEY,
            new Point(longitude, latitude),
            String.valueOf(storeId));
    }

    // 查找可配送的店铺
    public List<DeliveryStore> findAvailableStores(double longitude, double latitude) {
        GeoResults<GeoLocation<String>> results = redis.opsForGeo().radius(
            STORE_GEO_KEY,
            new Circle(new Point(longitude, latitude),
                new Distance(MAX_DELIVERY_DISTANCE, Metrics.KILOMETERS)),
            GeoRadiusCommandArgs.newGeoRadiusArgs()
                .includeDistance()
                .includeCoordinates()
                .sortAscending()
        );

        if (results == null) {
            return Collections.emptyList();
        }

        return results.getContent().stream()
            .map(result -> {
                DeliveryStore store = new DeliveryStore();
                store.setStoreId(Long.valueOf(result.getContent().getName()));
                store.setDistance(result.getDistance().getValue());
                store.setLongitude(result.getContent().getPoint().getX());
                store.setLatitude(result.getContent().getPoint().getY());
                return store;
            })
            .collect(Collectors.toList());
    }

    // 判断是否在配送范围内
    public boolean isInDeliveryRange(Long storeId, double longitude, double latitude) {
        List<Point> positions = redis.opsForGeo().position(STORE_GEO_KEY, String.valueOf(storeId));
        if (positions == null || positions.isEmpty()) {
            return false;
        }

        Point storePos = positions.get(0);
        Distance distance = calculateDistance(storePos, new Point(longitude, latitude));

        return distance.getValue() <= MAX_DELIVERY_DISTANCE;
    }

    private Distance calculateDistance(Point p1, Point p2) {
        // Haversine公式计算距离
        double lat1 = Math.toRadians(p1.getY());
        double lat2 = Math.toRadians(p2.getY());
        double lon1 = Math.toRadians(p1.getX());
        double lon2 = Math.toRadians(p2.getX());

        double dLat = lat2 - lat1;
        double dLon = lon2 - lon1;

        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                   Math.cos(lat1) * Math.cos(lat2) *
                   Math.sin(dLon / 2) * Math.sin(dLon / 2);

        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        double distance = 6371 * c;  // 地球半径6371km

        return new Distance(distance, Metrics.KILOMETERS);
    }
}
```

### 案例3：打车服务（司机匹配）

```java
@Service
public class TaxiService {
    @Autowired
    private RedisTemplate<String, String> redis;

    private static final String DRIVER_GEO_KEY = "driver:location";

    // 司机上线，更新位置
    public void driverOnline(Long driverId, double longitude, double latitude) {
        redis.opsForGeo().add(DRIVER_GEO_KEY,
            new Point(longitude, latitude),
            String.valueOf(driverId));

        // 设置过期时间（10分钟，超时下线）
        redis.expire(DRIVER_GEO_KEY, 10, TimeUnit.MINUTES);
    }

    // 司机下线
    public void driverOffline(Long driverId) {
        redis.opsForGeo().remove(DRIVER_GEO_KEY, String.valueOf(driverId));
    }

    // 乘客叫车，匹配最近的司机
    public List<Driver> matchNearbyDrivers(double longitude, double latitude, int count) {
        GeoResults<GeoLocation<String>> results = redis.opsForGeo().radius(
            DRIVER_GEO_KEY,
            new Circle(new Point(longitude, latitude),
                new Distance(3, Metrics.KILOMETERS)),  // 3km范围内
            GeoRadiusCommandArgs.newGeoRadiusArgs()
                .includeDistance()
                .includeCoordinates()
                .sortAscending()
                .limit(count)
        );

        if (results == null) {
            return Collections.emptyList();
        }

        return results.getContent().stream()
            .map(result -> {
                Driver driver = new Driver();
                driver.setDriverId(Long.valueOf(result.getContent().getName()));
                driver.setDistance(result.getDistance().getValue());
                driver.setLongitude(result.getContent().getPoint().getX());
                driver.setLatitude(result.getContent().getPoint().getY());
                return driver;
            })
            .collect(Collectors.toList());
    }

    // 定期更新司机位置（心跳）
    @Scheduled(fixedRate = 30000)  // 每30秒
    public void updateDriverLocations() {
        // 从GPS服务获取所有在线司机位置
        List<DriverLocation> locations = fetchDriverLocations();

        for (DriverLocation location : locations) {
            driverOnline(location.getDriverId(),
                location.getLongitude(),
                location.getLatitude());
        }
    }

    private List<DriverLocation> fetchDriverLocations() {
        // 从GPS服务获取位置
        return new ArrayList<>();
    }
}
```

### 案例4：充电桩查询

```java
@Service
public class ChargingStationService {
    @Autowired
    private RedisTemplate<String, String> redis;

    private static final String STATION_GEO_KEY = "charging:station";

    // 添加充电桩
    public void addStation(Long stationId, double longitude, double latitude) {
        redis.opsForGeo().add(STATION_GEO_KEY,
            new Point(longitude, latitude),
            String.valueOf(stationId));
    }

    // 查找附近充电桩
    public List<ChargingStation> findNearbyStations(
            double longitude, double latitude, double radiusKm) {

        GeoResults<GeoLocation<String>> results = redis.opsForGeo().radius(
            STATION_GEO_KEY,
            new Circle(new Point(longitude, latitude),
                new Distance(radiusKm, Metrics.KILOMETERS)),
            GeoRadiusCommandArgs.newGeoRadiusArgs()
                .includeDistance()
                .includeCoordinates()
                .sortAscending()
        );

        if (results == null) {
            return Collections.emptyList();
        }

        return results.getContent().stream()
            .map(result -> {
                Long stationId = Long.valueOf(result.getContent().getName());

                // 从数据库获取充电桩详情
                ChargingStation station = getStationDetails(stationId);
                station.setDistance(result.getDistance().getValue());

                return station;
            })
            .collect(Collectors.toList());
    }

    private ChargingStation getStationDetails(Long stationId) {
        // 从数据库查询
        return new ChargingStation();
    }
}
```

## 性能优化

### 1. 缓存用户位置

```java
// 避免频繁GEO查询
public Point getUserLocation(Long userId) {
    String cacheKey = "user:pos:" + userId;

    // 先查缓存
    String cached = redis.opsForValue().get(cacheKey);
    if (cached != null) {
        String[] parts = cached.split(",");
        return new Point(Double.parseDouble(parts[0]), Double.parseDouble(parts[1]));
    }

    // GEO查询
    List<Point> positions = redis.opsForGeo().position(GEO_KEY, String.valueOf(userId));
    if (positions != null && !positions.isEmpty()) {
        Point point = positions.get(0);

        // 缓存5分钟
        redis.opsForValue().set(cacheKey,
            point.getX() + "," + point.getY(),
            5, TimeUnit.MINUTES);

        return point;
    }

    return null;
}
```

### 2. 批量查询优化

```java
// 批量获取位置
public Map<Long, Point> batchGetLocations(List<Long> userIds) {
    String[] members = userIds.stream()
        .map(String::valueOf)
        .toArray(String[]::new);

    List<Point> positions = redis.opsForGeo().position(GEO_KEY, members);

    Map<Long, Point> result = new HashMap<>();
    for (int i = 0; i < userIds.size(); i++) {
        if (positions != null && i < positions.size()) {
            result.put(userIds.get(i), positions.get(i));
        }
    }

    return result;
}
```

## 底层原理

**GeoHash编码**：
```
1. 将经纬度转换为二进制
2. 交织经纬度二进制位
3. 转换为Base32编码

示例：
经度：116.397128 → 二进制 → 11010010110001011110...
纬度：39.916527 → 二进制 → 10111000110001010101...
交织：1101010011001100001111100101...
Base32：wx4g0b
```

**存储**：GEO底层使用ZSet，score为GeoHash编码

## 最佳实践

1. **定期清理过期位置**：
```java
@Scheduled(cron = "0 0 2 * * ?")
public void cleanExpiredLocations() {
    // 清理超过24小时未更新的位置
    long threshold = System.currentTimeMillis() - 86400000;
    // 实现清理逻辑
}
```

2. **限制查询范围**：
```java
// 避免查询过大范围
double maxRadius = 50.0;  // 最大50km
if (radius > maxRadius) {
    radius = maxRadius;
}
```

3. **分片存储**：
```java
// 按城市分片，避免单个GEO过大
String geoKey = "driver:location:" + cityId;
```

## 总结

**核心功能**：
- GEOADD：添加位置
- GEORADIUS：范围查询
- GEODIST：距离计算

**典型场景**：
- 附近的人/店铺/充电桩
- 外卖配送范围
- 打车司机匹配
- LBS推荐

**注意事项**：
- 控制查询范围（避免过大）
- 定期清理过期数据
- 大数据量考虑分片
- 缓存热点位置查询
