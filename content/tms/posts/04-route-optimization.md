---
title: "TMS路线优化：TSP与VRP问题的算法实现"
date: 2025-11-21T14:00:00+08:00
draft: false
tags: ["TMS", "路线优化", "TSP", "VRP", "算法"]
categories: ["供应链系统"]
description: "深入讲解路线优化的经典算法和工程实践。从TSP旅行商问题到VRP车辆路径问题,从贪心算法到遗传算法,全面掌握路线优化的核心技术。"
weight: 4
stage: 1
stageTitle: "基础入门篇"
---

## 引言

路线优化是TMS的核心技术之一,直接影响运输成本和配送效率。据统计,优化后的配送路线可以减少20-30%的行驶里程,节省大量燃油成本。

本文将深入探讨路线优化的两大经典问题——TSP(旅行商问题)和VRP(车辆路径问题),并提供Java实现代码和地图服务对接方案。

---

## 1. TSP问题(旅行商问题)

### 1.1 问题定义

**TSP(Traveling Salesman Problem)**：
一个销售员要访问n个城市,每个城市只访问一次,最后回到起点,求最短路径。

**数学描述**：
```
给定:
- N个城市: C = {c1, c2, ..., cn}
- 距离矩阵: D[i][j] = 城市i到城市j的距离

求:
- 一条路径 P = {ci1, ci2, ..., cin}
- 使得总距离最小: sum(D[cik][cik+1]) + D[cin][ci1]

约束:
- 每个城市访问且仅访问一次
```

**示例**：
```
城市: A, B, C, D
距离矩阵:
    A   B   C   D
A   0  10  15  20
B  10   0  35  25
C  15  35   0  30
D  20  25  30   0

可能的路径:
- A → B → C → D → A: 10 + 35 + 30 + 20 = 95
- A → B → D → C → A: 10 + 25 + 30 + 15 = 80 ✓ (最优)
- A → C → B → D → A: 15 + 35 + 25 + 20 = 95
```

### 1.2 算法选型

#### 穷举法

**原理**：枚举所有可能的路径,选择最短的。

**复杂度**：O(n!)

**适用场景**：n < 10

**代码实现**：
```java
public class TSPBruteForce {

    public List<Integer> solve(int[][] distance) {
        int n = distance.length;
        List<Integer> cities = new ArrayList<>();
        for (int i = 1; i < n; i++) {
            cities.add(i);
        }

        List<Integer> bestPath = new ArrayList<>();
        bestPath.add(0);  // 起点
        int minDistance = Integer.MAX_VALUE;

        // 生成所有排列
        List<List<Integer>> permutations = generatePermutations(cities);

        for (List<Integer> perm : permutations) {
            List<Integer> path = new ArrayList<>();
            path.add(0);
            path.addAll(perm);

            int dist = calculateDistance(path, distance);
            if (dist < minDistance) {
                minDistance = dist;
                bestPath = new ArrayList<>(path);
            }
        }

        return bestPath;
    }

    private int calculateDistance(List<Integer> path, int[][] distance) {
        int total = 0;
        for (int i = 0; i < path.size() - 1; i++) {
            total += distance[path.get(i)][path.get(i + 1)];
        }
        // 回到起点
        total += distance[path.get(path.size() - 1)][path.get(0)];
        return total;
    }
}
```

#### 贪心算法

**原理**：每次选择距离当前位置最近的未访问城市。

**复杂度**：O(n²)

**优点**：速度快,适用于实时计算

**缺点**：不保证全局最优

**代码实现**：
```java
public class TSPGreedy {

    public List<Integer> solve(int[][] distance) {
        int n = distance.length;
        List<Integer> path = new ArrayList<>();
        boolean[] visited = new boolean[n];

        // 从城市0开始
        int current = 0;
        path.add(current);
        visited[current] = true;

        for (int i = 1; i < n; i++) {
            int nearest = findNearest(current, distance, visited);
            path.add(nearest);
            visited[nearest] = true;
            current = nearest;
        }

        return path;
    }

    private int findNearest(int current, int[][] distance, boolean[] visited) {
        int nearest = -1;
        int minDistance = Integer.MAX_VALUE;

        for (int i = 0; i < distance.length; i++) {
            if (!visited[i] && distance[current][i] < minDistance) {
                minDistance = distance[current][i];
                nearest = i;
            }
        }

        return nearest;
    }
}
```

**示例**：
```
起点: A
1. A的最近邻居: B(10)  → 访问B
2. B的最近邻居: D(25)  → 访问D
3. D的最近邻居: C(30)  → 访问C
4. 回到A: C→A(15)

路径: A → B → D → C → A (总距离80)
```

#### 动态规划

**原理**：将问题分解为子问题,避免重复计算。

**复杂度**：O(n² × 2ⁿ)

**适用场景**：n < 20

**代码实现**：
```java
public class TSPDP {

    public int solve(int[][] distance) {
        int n = distance.length;
        int[][] dp = new int[1 << n][n];

        // 初始化
        for (int[] row : dp) {
            Arrays.fill(row, Integer.MAX_VALUE / 2);
        }
        dp[1][0] = 0;  // 起点

        // 动态规划
        for (int mask = 1; mask < (1 << n); mask++) {
            for (int u = 0; u < n; u++) {
                if ((mask & (1 << u)) == 0) continue;

                for (int v = 0; v < n; v++) {
                    if ((mask & (1 << v)) != 0) continue;

                    int newMask = mask | (1 << v);
                    dp[newMask][v] = Math.min(dp[newMask][v],
                        dp[mask][u] + distance[u][v]);
                }
            }
        }

        // 回到起点
        int result = Integer.MAX_VALUE;
        int fullMask = (1 << n) - 1;
        for (int u = 1; u < n; u++) {
            result = Math.min(result, dp[fullMask][u] + distance[u][0]);
        }

        return result;
    }
}
```

#### 遗传算法

**原理**：模拟生物进化,通过选择、交叉、变异找到近似最优解。

**适用场景**：大规模TSP问题(n > 100)

**代码实现**：
```java
public class TSPGenetic {

    private static final int POPULATION_SIZE = 100;
    private static final int MAX_GENERATIONS = 500;
    private static final double MUTATION_RATE = 0.01;

    public List<Integer> solve(int[][] distance) {
        int n = distance.length;

        // 初始化种群
        List<Individual> population = initializePopulation(n);

        for (int gen = 0; gen < MAX_GENERATIONS; gen++) {
            // 评估适应度
            evaluateFitness(population, distance);

            // 选择
            List<Individual> selected = select(population);

            // 交叉
            List<Individual> offspring = crossover(selected);

            // 变异
            mutate(offspring);

            population = offspring;
        }

        // 返回最优个体
        Individual best = population.stream()
            .max(Comparator.comparing(Individual::getFitness))
            .orElse(null);

        return best != null ? best.getPath() : new ArrayList<>();
    }

    private List<Individual> initializePopulation(int n) {
        List<Individual> population = new ArrayList<>();

        for (int i = 0; i < POPULATION_SIZE; i++) {
            List<Integer> path = new ArrayList<>();
            for (int j = 0; j < n; j++) {
                path.add(j);
            }
            Collections.shuffle(path);

            Individual individual = new Individual();
            individual.setPath(path);
            population.add(individual);
        }

        return population;
    }

    private void evaluateFitness(List<Individual> population, int[][] distance) {
        for (Individual individual : population) {
            int totalDist = calculateDistance(individual.getPath(), distance);
            // 适应度 = 1 / 距离 (距离越短,适应度越高)
            individual.setFitness(1.0 / totalDist);
        }
    }

    private List<Individual> select(List<Individual> population) {
        // 轮盘赌选择
        double totalFitness = population.stream()
            .mapToDouble(Individual::getFitness)
            .sum();

        List<Individual> selected = new ArrayList<>();
        for (int i = 0; i < POPULATION_SIZE; i++) {
            double random = ThreadLocalRandom.current().nextDouble() * totalFitness;
            double sum = 0;

            for (Individual ind : population) {
                sum += ind.getFitness();
                if (sum >= random) {
                    selected.add(ind.clone());
                    break;
                }
            }
        }

        return selected;
    }

    private List<Individual> crossover(List<Individual> parents) {
        List<Individual> offspring = new ArrayList<>();

        for (int i = 0; i < parents.size(); i += 2) {
            if (i + 1 < parents.size()) {
                Individual parent1 = parents.get(i);
                Individual parent2 = parents.get(i + 1);

                // 顺序交叉(OX)
                Individual child = orderCrossover(parent1, parent2);
                offspring.add(child);
            } else {
                offspring.add(parents.get(i));
            }
        }

        return offspring;
    }

    private Individual orderCrossover(Individual parent1, Individual parent2) {
        int n = parent1.getPath().size();
        int start = ThreadLocalRandom.current().nextInt(n);
        int end = ThreadLocalRandom.current().nextInt(start, n);

        List<Integer> childPath = new ArrayList<>(Collections.nCopies(n, -1));

        // 复制片段
        for (int i = start; i <= end; i++) {
            childPath.set(i, parent1.getPath().get(i));
        }

        // 填充剩余
        int pos = (end + 1) % n;
        for (int i = 0; i < n; i++) {
            int city = parent2.getPath().get((end + 1 + i) % n);
            if (!childPath.contains(city)) {
                childPath.set(pos, city);
                pos = (pos + 1) % n;
            }
        }

        Individual child = new Individual();
        child.setPath(childPath);
        return child;
    }

    private void mutate(List<Individual> population) {
        for (Individual individual : population) {
            if (ThreadLocalRandom.current().nextDouble() < MUTATION_RATE) {
                // 交换两个城市
                swapMutation(individual);
            }
        }
    }

    private void swapMutation(Individual individual) {
        List<Integer> path = individual.getPath();
        int n = path.size();
        int i = ThreadLocalRandom.current().nextInt(n);
        int j = ThreadLocalRandom.current().nextInt(n);
        Collections.swap(path, i, j);
    }
}

class Individual implements Cloneable {
    private List<Integer> path;
    private double fitness;

    // getter/setter...

    @Override
    public Individual clone() {
        Individual cloned = new Individual();
        cloned.path = new ArrayList<>(this.path);
        cloned.fitness = this.fitness;
        return cloned;
    }
}
```

### 1.3 2-opt优化算法

**原理**：对现有路径进行局部优化,交换两条边。

**适用场景**：对贪心算法/遗传算法的结果进行优化

**代码实现**：
```java
public class TwoOptOptimizer {

    public List<Integer> optimize(List<Integer> path, int[][] distance) {
        boolean improved = true;

        while (improved) {
            improved = false;

            for (int i = 1; i < path.size() - 1; i++) {
                for (int j = i + 1; j < path.size(); j++) {
                    // 尝试交换边(i-1,i)和(j,j+1)
                    if (shouldSwap(path, distance, i, j)) {
                        // 反转path[i..j]
                        reverse(path, i, j);
                        improved = true;
                    }
                }
            }
        }

        return path;
    }

    private boolean shouldSwap(List<Integer> path, int[][] distance, int i, int j) {
        int a = path.get(i - 1);
        int b = path.get(i);
        int c = path.get(j);
        int d = path.get((j + 1) % path.size());

        // 原距离: a-b + c-d
        int oldDist = distance[a][b] + distance[c][d];
        // 新距离: a-c + b-d
        int newDist = distance[a][c] + distance[b][d];

        return newDist < oldDist;
    }

    private void reverse(List<Integer> path, int i, int j) {
        while (i < j) {
            Collections.swap(path, i, j);
            i++;
            j--;
        }
    }
}
```

---

## 2. VRP问题(车辆路径问题)

### 2.1 问题定义

**VRP(Vehicle Routing Problem)**：
多个车辆从配送中心出发,服务多个客户,求总成本最小。

**数学描述**：
```
给定:
- K辆车,每辆车载重Qk
- N个客户,每个客户需求qi
- 距离矩阵D[i][j]

求:
- K条路径,覆盖所有客户
- 每辆车载重 ≤ Qk
- 总距离最小

约束:
- 每个客户被访问且仅被访问一次
- 车辆容量约束
- 时间窗口约束(VRPTW)
```

**示例**：
```
配送中心: 0
客户: 1,2,3,4,5,6
车辆: 2辆,载重各100kg
客户需求: [30, 40, 20, 50, 25, 35]

可能的方案:
车辆1: 0 → 1(30) → 2(40) → 3(20) → 0  (总90kg)
车辆2: 0 → 4(50) → 5(25) → 6(35) → 0  (总110kg) ✗ 超载!

优化方案:
车辆1: 0 → 1(30) → 2(40) → 5(25) → 0  (总95kg) ✓
车辆2: 0 → 4(50) → 3(20) → 6(35) → 0  (总105kg) ✗ 仍超载!

最优方案:
车辆1: 0 → 1(30) → 2(40) → 3(20) → 0  (总90kg) ✓
车辆2: 0 → 4(50) → 5(25) → 0         (总75kg) ✓
车辆3: 0 → 6(35) → 0                 (总35kg) ✓
```

### 2.2 求解思路

#### 分组聚类

**思路**：
1. 将客户按地理位置分组
2. 每组分配一辆车
3. 每组内求解TSP问题

**K-means聚类**：
```java
public class KMeansClustering {

    public List<List<Customer>> cluster(List<Customer> customers, int k) {
        // 初始化k个聚类中心
        List<Customer> centers = initializeCenters(customers, k);

        boolean changed = true;
        List<List<Customer>> clusters = new ArrayList<>();

        while (changed) {
            // 分配客户到最近的聚类中心
            clusters = assignClusters(customers, centers);

            // 更新聚类中心
            List<Customer> newCenters = updateCenters(clusters);

            // 检查是否收敛
            changed = !centersEqual(centers, newCenters);
            centers = newCenters;
        }

        return clusters;
    }

    private List<List<Customer>> assignClusters(List<Customer> customers,
                                               List<Customer> centers) {

        List<List<Customer>> clusters = new ArrayList<>();
        for (int i = 0; i < centers.size(); i++) {
            clusters.add(new ArrayList<>());
        }

        for (Customer customer : customers) {
            int nearestCenter = findNearestCenter(customer, centers);
            clusters.get(nearestCenter).add(customer);
        }

        return clusters;
    }

    private int findNearestCenter(Customer customer, List<Customer> centers) {
        int nearest = 0;
        double minDistance = Double.MAX_VALUE;

        for (int i = 0; i < centers.size(); i++) {
            double dist = distance(customer, centers.get(i));
            if (dist < minDistance) {
                minDistance = dist;
                nearest = i;
            }
        }

        return nearest;
    }

    private double distance(Customer c1, Customer c2) {
        double dx = c1.getLongitude() - c2.getLongitude();
        double dy = c1.getLatitude() - c2.getLatitude();
        return Math.sqrt(dx * dx + dy * dy);
    }
}
```

#### 扫描算法

**思路**：
1. 从配送中心出发,按极角排序客户
2. 按顺序添加客户到当前车辆
3. 如果超载,开启新车辆

**代码实现**：
```java
public class SweepAlgorithm {

    public List<List<Customer>> solve(Depot depot, List<Customer> customers,
                                     double capacity) {

        // 按极角排序
        customers.sort(Comparator.comparing(c -> calculateAngle(depot, c)));

        List<List<Customer>> routes = new ArrayList<>();
        List<Customer> currentRoute = new ArrayList<>();
        double currentLoad = 0;

        for (Customer customer : customers) {
            if (currentLoad + customer.getDemand() <= capacity) {
                // 添加到当前路线
                currentRoute.add(customer);
                currentLoad += customer.getDemand();
            } else {
                // 开启新路线
                if (!currentRoute.isEmpty()) {
                    routes.add(currentRoute);
                }
                currentRoute = new ArrayList<>();
                currentRoute.add(customer);
                currentLoad = customer.getDemand();
            }
        }

        if (!currentRoute.isEmpty()) {
            routes.add(currentRoute);
        }

        return routes;
    }

    private double calculateAngle(Depot depot, Customer customer) {
        double dx = customer.getLongitude() - depot.getLongitude();
        double dy = customer.getLatitude() - depot.getLatitude();
        return Math.atan2(dy, dx);
    }
}
```

#### 节约算法(Clarke-Wright)

**原理**：
合并两条路线,如果节约的距离最大。

**节约值**：
```
s(i,j) = d(0,i) + d(0,j) - d(i,j)
```

**代码实现**：
```java
public class ClarkeWrightAlgorithm {

    public List<List<Customer>> solve(Depot depot, List<Customer> customers,
                                     int[][] distance, double capacity) {

        // 初始化:每个客户一条路线
        List<List<Customer>> routes = new ArrayList<>();
        for (Customer customer : customers) {
            List<Customer> route = new ArrayList<>();
            route.add(customer);
            routes.add(route);
        }

        // 计算节约值
        List<Saving> savings = calculateSavings(depot, customers, distance);

        // 按节约值降序排序
        savings.sort(Comparator.comparing(Saving::getValue).reversed());

        // 合并路线
        for (Saving saving : savings) {
            // 找到包含i和j的路线
            List<Customer> route1 = findRoute(routes, saving.getCustomer1());
            List<Customer> route2 = findRoute(routes, saving.getCustomer2());

            if (route1 != route2 && canMerge(route1, route2, capacity)) {
                // 合并
                route1.addAll(route2);
                routes.remove(route2);
            }
        }

        return routes;
    }

    private List<Saving> calculateSavings(Depot depot, List<Customer> customers,
                                         int[][] distance) {

        List<Saving> savings = new ArrayList<>();

        for (int i = 0; i < customers.size(); i++) {
            for (int j = i + 1; j < customers.size(); j++) {
                Customer c1 = customers.get(i);
                Customer c2 = customers.get(j);

                int save = distance[0][c1.getId()] + distance[0][c2.getId()]
                         - distance[c1.getId()][c2.getId()];

                savings.add(new Saving(c1, c2, save));
            }
        }

        return savings;
    }

    private boolean canMerge(List<Customer> route1, List<Customer> route2,
                            double capacity) {

        double totalDemand = route1.stream().mapToDouble(Customer::getDemand).sum()
                           + route2.stream().mapToDouble(Customer::getDemand).sum();

        return totalDemand <= capacity;
    }
}

class Saving {
    private Customer customer1;
    private Customer customer2;
    private int value;

    // constructor, getter/setter...
}
```

---

## 3. 地图服务对接

### 3.1 高德地图API

**路径规划API**：
```java
@Service
public class AmapService {

    private static final String API_KEY = "your_api_key";
    private static final String DIRECTION_URL =
        "https://restapi.amap.com/v3/direction/driving";

    @Autowired
    private RestTemplate restTemplate;

    public RouteResponse planRoute(String origin, String destination) {
        String url = String.format("%s?origin=%s&destination=%s&key=%s",
            DIRECTION_URL, origin, destination, API_KEY);

        ResponseEntity<String> response = restTemplate.getForEntity(url, String.class);

        JSONObject json = JSON.parseObject(response.getBody());
        JSONObject route = json.getJSONObject("route");
        JSONArray paths = route.getJSONArray("paths");
        JSONObject path = paths.getJSONObject(0);

        RouteResponse result = new RouteResponse();
        result.setDistance(path.getInteger("distance"));  // 米
        result.setDuration(path.getInteger("duration"));  // 秒
        result.setPolyline(path.getString("polyline"));   // 坐标串

        return result;
    }

    public int[][] calculateDistanceMatrix(List<String> locations) {
        int n = locations.size();
        int[][] matrix = new int[n][n];

        for (int i = 0; i < n; i++) {
            for (int j = i + 1; j < n; j++) {
                RouteResponse route = planRoute(locations.get(i), locations.get(j));
                matrix[i][j] = route.getDistance();
                matrix[j][i] = route.getDistance();
            }
        }

        return matrix;
    }
}

@Data
class RouteResponse {
    private Integer distance;  // 距离(米)
    private Integer duration;  // 时长(秒)
    private String polyline;   // 路径坐标
}
```

**批量路径规划**：
```java
public List<RouteResponse> batchPlanRoute(List<String> origins,
                                         List<String> destinations) {

    List<RouteResponse> results = new ArrayList<>();

    // 并行调用(线程池)
    ExecutorService executor = Executors.newFixedThreadPool(10);
    List<Future<RouteResponse>> futures = new ArrayList<>();

    for (int i = 0; i < origins.size(); i++) {
        final int index = i;
        futures.add(executor.submit(() ->
            planRoute(origins.get(index), destinations.get(index))
        ));
    }

    for (Future<RouteResponse> future : futures) {
        try {
            results.add(future.get());
        } catch (Exception e) {
            log.error("路径规划失败", e);
        }
    }

    executor.shutdown();
    return results;
}
```

### 3.2 百度地图API

**路况查询**：
```java
@Service
public class BaiduMapService {

    private static final String API_KEY = "your_api_key";
    private static final String TRAFFIC_URL =
        "https://api.map.baidu.com/traffic/v1/road";

    public TrafficStatus getTrafficStatus(String road) {
        String url = String.format("%s?road_name=%s&ak=%s",
            TRAFFIC_URL, road, API_KEY);

        ResponseEntity<String> response = restTemplate.getForEntity(url, String.class);

        JSONObject json = JSON.parseObject(response.getBody());
        JSONObject traffic = json.getJSONObject("road_traffic");

        TrafficStatus status = new TrafficStatus();
        status.setCongestionIndex(traffic.getDouble("congestion_index"));
        status.setSpeed(traffic.getDouble("speed"));
        status.setStatus(traffic.getString("status"));  // 畅通/缓行/拥堵

        return status;
    }
}

@Data
class TrafficStatus {
    private Double congestionIndex;  // 拥堵指数(0-10)
    private Double speed;            // 平均速度(km/h)
    private String status;           // 状态
}
```

---

## 4. 实战案例：顺丰科技的路径优化

### 4.1 业务场景

顺丰科技每天处理500万+配送订单,需要优化：
- 最后一公里配送路径
- 多仓协同配送路径
- 跨省干线运输路径

### 4.2 优化方案

**算法组合**：
```
1. 订单分组(K-means聚类)
   - 按地理位置分组
   - 每组50-100个订单

2. 路径规划(改进的遗传算法)
   - 考虑实时路况
   - 考虑时间窗口
   - 考虑车辆载重

3. 局部优化(2-opt)
   - 对生成的路径进行微调
   - 减少交叉路径
```

### 4.3 优化成果

- **配送距离缩短**：20%
- **配送时效提升**：15%
- **车辆利用率提升**：25%
- **燃油成本降低**：18%

---

## 5. 总结

本文深入探讨了路线优化的经典算法和工程实践,为TMS系统提供了完整的路径规划解决方案。

**核心要点**：

1. **TSP问题**：
   - 穷举法：精确解,适用于小规模(n<10)
   - 贪心算法：快速近似解,适用于实时场景
   - 动态规划：精确解,适用于中等规模(n<20)
   - 遗传算法：近似解,适用于大规模(n>100)
   - 2-opt优化：局部优化,提升解的质量

2. **VRP问题**：
   - K-means聚类：客户分组
   - 扫描算法：简单快速
   - 节约算法：质量较好

3. **地图服务对接**：
   - 高德地图：路径规划、距离计算
   - 百度地图：路况查询、批量规划

在下一篇文章中,我们将探讨运费管理与自动结算的完整方案,敬请期待！

---

## 参考资料

- 《算法导论》
- 《运筹学》教材
- 顺丰科技官方博客
- 高德地图开放平台文档
- 百度地图开放平台文档
