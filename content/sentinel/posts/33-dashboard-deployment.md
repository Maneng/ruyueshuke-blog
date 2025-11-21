---
title: "Dashboard生产部署与配置"
date: 2025-11-21T16:45:00+08:00
draft: false
tags: ["Sentinel", "Dashboard", "生产部署"]
categories: ["技术"]
series: ["Sentinel从入门到精通"]
weight: 33
stage: 7
stageTitle: "生产实践篇"
description: "Sentinel Dashboard的生产环境部署指南"
---

## Dashboard部署方案

### 方式1：Jar包直接部署

```bash
# 1. 下载Dashboard
wget https://github.com/alibaba/Sentinel/releases/download/1.8.6/sentinel-dashboard-1.8.6.jar

# 2. 启动Dashboard
java -Dserver.port=8080 \
     -Dcsp.sentinel.dashboard.server=localhost:8080 \
     -Dproject.name=sentinel-dashboard \
     -jar sentinel-dashboard-1.8.6.jar

# 3. 访问控制台
# http://localhost:8080
# 默认账号/密码：sentinel/sentinel
```

### 方式2：Docker部署

```dockerfile
FROM openjdk:8-jre-slim

# 下载Dashboard
ADD https://github.com/alibaba/Sentinel/releases/download/1.8.6/sentinel-dashboard-1.8.6.jar /app.jar

# 暴露端口
EXPOSE 8080

# 启动命令
ENTRYPOINT ["java", "-jar", "/app.jar"]
```

```bash
# 构建镜像
docker build -t sentinel-dashboard:1.8.6 .

# 运行容器
docker run -d \
  --name sentinel-dashboard \
  -p 8080:8080 \
  sentinel-dashboard:1.8.6
```

### 方式3：Kubernetes部署

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sentinel-dashboard
spec:
  replicas: 2
  selector:
    matchLabels:
      app: sentinel-dashboard
  template:
    metadata:
      labels:
        app: sentinel-dashboard
    spec:
      containers:
      - name: dashboard
        image: sentinel-dashboard:1.8.6
        ports:
        - containerPort: 8080
        env:
        - name: JAVA_OPTS
          value: "-Xms512m -Xmx512m"
---
apiVersion: v1
kind: Service
metadata:
  name: sentinel-dashboard
spec:
  selector:
    app: sentinel-dashboard
  ports:
  - port: 8080
    targetPort: 8080
  type: LoadBalancer
```

## 生产配置

### application.properties

```properties
# 服务端口
server.port=8080

# Session超时时间（30分钟）
server.servlet.session.timeout=30m

# 认证配置
auth.enabled=true
auth.username=admin
auth.password=your_password

# 数据源配置（持久化到Nacos）
nacos.server-addr=localhost:8848
nacos.namespace=production
nacos.group-id=SENTINEL_GROUP

# 规则推送模式
sentinel.rule.push.mode=nacos
```

### JVM参数

```bash
java -Xms1g -Xmx1g \
     -XX:+UseG1GC \
     -XX:MaxGCPauseMillis=200 \
     -Xloggc:logs/gc.log \
     -XX:+PrintGCDetails \
     -XX:+PrintGCDateStamps \
     -jar sentinel-dashboard.jar
```

## 改造Dashboard

### 持久化到Nacos

#### 1. 修改pom.xml

```xml
<dependency>
    <groupId>com.alibaba.csp</groupId>
    <artifactId>sentinel-datasource-nacos</artifactId>
</dependency>
```

#### 2. 配置Nacos

```java
@Configuration
public class NacosConfig {

    @Bean
    public ConfigService nacosConfigService() throws Exception {
        Properties properties = new Properties();
        properties.put(PropertyKeyConst.SERVER_ADDR, "localhost:8848");
        properties.put(PropertyKeyConst.NAMESPACE, "production");
        return ConfigFactory.createConfigService(properties);
    }
}
```

#### 3. 规则发布器

```java
@Component
public class FlowRuleNacosPublisher implements DynamicRulePublisher<List<FlowRuleEntity>> {

    @Autowired
    private ConfigService configService;

    @Override
    public void publish(String app, List<FlowRuleEntity> rules) throws Exception {
        String dataId = app + "-flow-rules";
        configService.publishConfig(
            dataId,
            "SENTINEL_GROUP",
            JSON.toJSONString(rules),
            ConfigType.JSON.getType()
        );
    }
}

@Component
public class FlowRuleNacosProvider implements DynamicRuleProvider<List<FlowRuleEntity>> {

    @Autowired
    private ConfigService configService;

    @Override
    public List<FlowRuleEntity> getRules(String appName) throws Exception {
        String dataId = appName + "-flow-rules";
        String rules = configService.getConfig(dataId, "SENTINEL_GROUP", 3000);
        return StringUtil.isEmpty(rules) ? new ArrayList<>() :
            JSON.parseArray(rules, FlowRuleEntity.class);
    }
}
```

#### 4. Controller改造

```java
@RestController
@RequestMapping("/v1/flow")
public class FlowControllerV2 {

    @Autowired
    private DynamicRuleProvider<List<FlowRuleEntity>> ruleProvider;

    @Autowired
    private DynamicRulePublisher<List<FlowRuleEntity>> rulePublisher;

    @GetMapping("/rules")
    public Result<List<FlowRuleEntity>> apiQueryRules(@RequestParam String app) {
        try {
            List<FlowRuleEntity> rules = ruleProvider.getRules(app);
            return Result.ofSuccess(rules);
        } catch (Exception e) {
            return Result.ofFail(-1, e.getMessage());
        }
    }

    @PostMapping("/rule")
    public Result<FlowRuleEntity> apiAddFlowRule(@RequestBody FlowRuleEntity entity) {
        try {
            List<FlowRuleEntity> rules = ruleProvider.getRules(entity.getApp());
            rules.add(entity);
            rulePublisher.publish(entity.getApp(), rules);
            return Result.ofSuccess(entity);
        } catch (Exception e) {
            return Result.ofFail(-1, e.getMessage());
        }
    }
}
```

## 权限控制

### 自定义用户认证

```java
@Configuration
public class WebSecurityConfig extends WebSecurityConfigurerAdapter {

    @Override
    protected void configure(HttpSecurity http) throws Exception {
        http
            .authorizeRequests()
                .antMatchers("/").permitAll()
                .anyRequest().authenticated()
            .and()
            .formLogin()
                .loginPage("/login")
                .permitAll()
            .and()
            .logout()
                .permitAll();
    }

    @Override
    protected void configure(AuthenticationManagerBuilder auth) throws Exception {
        auth.inMemoryAuthentication()
            .withUser("admin").password("{noop}admin123").roles("ADMIN")
            .and()
            .withUser("user").password("{noop}user123").roles("USER");
    }
}
```

### 基于角色的权限控制

```java
@RestController
@RequestMapping("/v1/flow")
public class FlowController {

    @GetMapping("/rules")
    @PreAuthorize("hasAnyRole('ADMIN', 'USER')")
    public Result apiQueryRules(@RequestParam String app) {
        // ...
    }

    @PostMapping("/rule")
    @PreAuthorize("hasRole('ADMIN')")
    public Result apiAddRule(@RequestBody FlowRuleEntity entity) {
        // ...
    }

    @DeleteMapping("/rule/{id}")
    @PreAuthorize("hasRole('ADMIN')")
    public Result apiDeleteRule(@PathVariable Long id) {
        // ...
    }
}
```

## 监控告警

### Prometheus集成

```java
@Configuration
public class PrometheusConfig {

    @Bean
    MeterRegistryCustomizer<MeterRegistry> metricsCommonTags() {
        return registry -> registry.config().commonTags("application", "sentinel-dashboard");
    }
}
```

### Grafana Dashboard

```json
{
  "dashboard": {
    "title": "Sentinel Dashboard Monitoring",
    "panels": [
      {
        "title": "QPS",
        "targets": [
          {
            "expr": "rate(sentinel_pass_qps[1m])"
          }
        ]
      },
      {
        "title": "Block Rate",
        "targets": [
          {
            "expr": "rate(sentinel_block_qps[1m]) / rate(sentinel_pass_qps[1m])"
          }
        ]
      }
    ]
  }
}
```

## 高可用部署

### Nginx负载均衡

```nginx
upstream sentinel_dashboard {
    server 192.168.1.10:8080;
    server 192.168.1.11:8080;
}

server {
    listen 80;
    server_name dashboard.example.com;

    location / {
        proxy_pass http://sentinel_dashboard;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

### Session共享

```properties
# Redis共享Session
spring.session.store-type=redis
spring.redis.host=localhost
spring.redis.port=6379
```

## 运维脚本

### 启动脚本

```bash
#!/bin/bash
# start.sh

JAVA_OPTS="-Xms1g -Xmx1g -XX:+UseG1GC"
APP_NAME="sentinel-dashboard"
APP_JAR="sentinel-dashboard.jar"

nohup java $JAVA_OPTS -jar $APP_JAR > logs/dashboard.log 2>&1 &
echo $! > dashboard.pid
echo "Dashboard started"
```

### 停止脚本

```bash
#!/bin/bash
# stop.sh

if [ -f dashboard.pid ]; then
    kill $(cat dashboard.pid)
    rm -f dashboard.pid
    echo "Dashboard stopped"
else
    echo "PID file not found"
fi
```

### 健康检查

```bash
#!/bin/bash
# health_check.sh

URL="http://localhost:8080/actuator/health"

if curl -f $URL > /dev/null 2>&1; then
    echo "Dashboard is healthy"
    exit 0
else
    echo "Dashboard is down"
    exit 1
fi
```

## 总结

Dashboard生产部署要点：
1. **部署方式**：Jar包、Docker、Kubernetes
2. **持久化**：改造Dashboard支持Nacos
3. **权限控制**：用户认证、角色权限
4. **高可用**：多实例部署、Nginx负载均衡
5. **监控告警**：Prometheus + Grafana

**最佳实践**：
- 使用Nacos持久化规则
- 配置权限控制保护Dashboard
- 部署多实例保证高可用
- 集成监控系统实时告警
