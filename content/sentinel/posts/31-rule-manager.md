---
title: "规则管理与推送机制"
date: 2025-11-20T16:41:00+08:00
draft: false
tags: ["Sentinel", "规则管理", "推送机制"]
categories: ["技术"]
series: ["Sentinel从入门到精通"]
weight: 31
stage: 6
stageTitle: "架构原理篇"
description: "深入理解Sentinel的规则管理和推送机制"
---

## 规则管理架构

```
┌─────────────────────────────────────┐
│      Dashboard / 配置中心            │
└────────────────┬────────────────────┘
                 │ Push/Pull
                 ↓
┌─────────────────────────────────────┐
│      RuleManager                     │
│  ├─ FlowRuleManager                 │
│  ├─ DegradeRuleManager              │
│  ├─ SystemRuleManager               │
│  ├─ AuthorityRuleManager            │
│  └─ ParamFlowRuleManager            │
└────────────────┬────────────────────┘
                 │ Property
                 ↓
┌─────────────────────────────────────┐
│      PropertyListener                │
│      (规则变更监听)                   │
└────────────────┬────────────────────┘
                 │ Notify
                 ↓
┌─────────────────────────────────────┐
│      Slot Chain                      │
│      (应用规则)                       │
└─────────────────────────────────────┘
```

## RuleManager核心实现

### FlowRuleManager

```java
public class FlowRuleManager {
    // 规则存储：资源名 → 规则列表
    private static final Map<String, List<FlowRule>> flowRules = new ConcurrentHashMap<>();

    // 规则监听器
    private static final RulePropertyListener LISTENER = new FlowPropertyListener();

    // 数据源属性
    private static SentinelProperty<List<FlowRule>> currentProperty = new DynamicSentinelProperty<>();

    static {
        currentProperty.addListener(LISTENER);
    }

    // 加载规则
    public static void loadRules(List<FlowRule> rules) {
        currentProperty.updateValue(rules);
    }

    // 注册数据源
    public static void register2Property(SentinelProperty<List<FlowRule>> property) {
        AssertUtil.notNull(property, "property cannot be null");
        synchronized (LISTENER) {
            currentProperty.removeListener(LISTENER);
            property.addListener(LISTENER);
            currentProperty = property;
        }
    }

    // 获取规则
    public static List<FlowRule> getRules() {
        List<FlowRule> rules = new ArrayList<>();
        for (Map.Entry<String, List<FlowRule>> entry : flowRules.entrySet()) {
            rules.addAll(entry.getValue());
        }
        return rules;
    }

    // 获取资源的规则
    public static List<FlowRule> getRules(String resource) {
        return flowRules.get(resource);
    }
}
```

### PropertyListener

```java
private static final class FlowPropertyListener implements PropertyListener<List<FlowRule>> {

    @Override
    public synchronized void configLoad(List<FlowRule> value) {
        Map<String, List<FlowRule>> rules = new ConcurrentHashMap<>();

        if (value != null) {
            for (FlowRule rule : value) {
                // 校验规则
                if (!isValidRule(rule)) {
                    RecordLog.warn("Bad flow rule: " + rule.toString());
                    continue;
                }

                // 解析流控器
                FlowRuleUtil.generateRater(rule);

                // 按资源分组
                String resourceName = rule.getResource();
                rules.computeIfAbsent(resourceName, k -> new ArrayList<>()).add(rule);
            }
        }

        // 更新规则
        flowRules.clear();
        flowRules.putAll(rules);

        RecordLog.info("[FlowRuleManager] Flow rules loaded: " + rules);
    }

    @Override
    public void configUpdate(List<FlowRule> value) {
        configLoad(value);
    }
}
```

## 数据源抽象

### ReadableDataSource

```java
public interface ReadableDataSource<S, T> extends AutoCloseable {
    // 加载配置
    T loadConfig() throws Exception;

    // 获取属性
    SentinelProperty<T> getProperty();
}
```

### AbstractDataSource

```java
public abstract class AbstractDataSource<S, T> implements ReadableDataSource<S, T> {

    protected final Converter<S, T> parser;
    protected final SentinelProperty<T> property;

    public AbstractDataSource(Converter<S, T> parser) {
        this.parser = parser;
        this.property = new DynamicSentinelProperty<>();
    }

    @Override
    public T loadConfig() throws Exception {
        S source = readSource();
        return parser.convert(source);
    }

    // 子类实现：读取数据源
    public abstract S readSource() throws Exception;

    @Override
    public SentinelProperty<T> getProperty() {
        return property;
    }
}
```

## Pull模式实现

### FileDataSource

```java
public class FileRefreshableDataSource<T> extends AbstractDataSource<String, T> {

    private final String file;
    private long lastModified = 0;

    public FileRefreshableDataSource(File file, Converter<String, T> parser) {
        super(parser);
        this.file = file.getAbsolutePath();
        // 启动定时任务
        startTimerTask();
    }

    @Override
    public String readSource() throws Exception {
        return Files.readAllLines(Paths.get(file))
            .stream()
            .collect(Collectors.joining("\n"));
    }

    private void startTimerTask() {
        ScheduledExecutorService service = Executors.newScheduledThreadPool(1);
        service.scheduleAtFixedRate(() -> {
            try {
                File f = new File(file);
                long curModified = f.lastModified();
                if (curModified > lastModified) {
                    lastModified = curModified;
                    T conf = loadConfig();
                    getProperty().updateValue(conf);
                }
            } catch (Exception e) {
                RecordLog.warn("Error when loading file", e);
            }
        }, 0, 3, TimeUnit.SECONDS);
    }
}
```

## Push模式实现

### NacosDataSource

```java
public class NacosDataSource<T> extends AbstractDataSource<String, T> {

    private final ConfigService configService;
    private final String dataId;
    private final String groupId;

    public NacosDataSource(String serverAddr, String groupId, String dataId, Converter<String, T> parser) throws Exception {
        super(parser);
        this.groupId = groupId;
        this.dataId = dataId;

        Properties properties = new Properties();
        properties.put(PropertyKeyConst.SERVER_ADDR, serverAddr);
        this.configService = ConfigFactory.createConfigService(properties);

        initNacosListener();
        loadInitialConfig();
    }

    @Override
    public String readSource() throws Exception {
        return configService.getConfig(dataId, groupId, 3000);
    }

    private void initNacosListener() {
        try {
            configService.addListener(dataId, groupId, new Listener() {
                @Override
                public Executor getExecutor() {
                    return null;
                }

                @Override
                public void receiveConfigInfo(String configInfo) {
                    RecordLog.info("[NacosDataSource] New property value received: " + configInfo);
                    T newValue = NacosDataSource.this.parser.convert(configInfo);
                    getProperty().updateValue(newValue);
                }
            });
        } catch (Exception e) {
            throw new IllegalStateException("Error occurred when initializing Nacos listener", e);
        }
    }

    private void loadInitialConfig() {
        try {
            T newValue = loadConfig();
            if (newValue == null) {
                RecordLog.warn("[NacosDataSource] WARN: initial config is null, you may have to check your data source");
            }
            getProperty().updateValue(newValue);
        } catch (Exception e) {
            RecordLog.warn("[NacosDataSource] Error when loading initial config", e);
        }
    }
}
```

## 规则校验

```java
public class RuleValidator {

    public static boolean isValidFlowRule(FlowRule rule) {
        if (rule == null) {
            return false;
        }

        // 校验资源名
        if (StringUtil.isBlank(rule.getResource())) {
            return false;
        }

        // 校验阈值
        if (rule.getCount() < 0) {
            return false;
        }

        // 校验限流模式
        if (rule.getGrade() != RuleConstant.FLOW_GRADE_QPS &&
            rule.getGrade() != RuleConstant.FLOW_GRADE_THREAD) {
            return false;
        }

        // 校验流控策略
        if (rule.getStrategy() != RuleConstant.STRATEGY_DIRECT &&
            rule.getStrategy() != RuleConstant.STRATEGY_RELATE &&
            rule.getStrategy() != RuleConstant.STRATEGY_CHAIN) {
            return false;
        }

        // 校验流控效果
        if (rule.getControlBehavior() < 0 || rule.getControlBehavior() > 2) {
            return false;
        }

        return true;
    }
}
```

## 规则转换器

```java
public class FlowRuleJsonConverter implements Converter<String, List<FlowRule>> {

    @Override
    public List<FlowRule> convert(String source) {
        if (StringUtil.isEmpty(source)) {
            return new ArrayList<>();
        }

        try {
            return JSON.parseArray(source, FlowRule.class);
        } catch (Exception e) {
            RecordLog.warn("Error when parsing flow rules", e);
            return new ArrayList<>();
        }
    }
}
```

## Dashboard推送

### RulePublisher

```java
public interface DynamicRulePublisher<T> {
    void publish(String app, T rules) throws Exception;
}

@Component
public class FlowRuleNacosPublisher implements DynamicRulePublisher<List<FlowRuleEntity>> {

    @Autowired
    private ConfigService configService;

    @Override
    public void publish(String app, List<FlowRuleEntity> rules) throws Exception {
        AssertUtil.notEmpty(app, "app name cannot be empty");

        if (rules == null) {
            return;
        }

        String dataId = app + NacosConfigUtil.FLOW_DATA_ID_POSTFIX;
        configService.publishConfig(
            dataId,
            NacosConfigUtil.GROUP_ID,
            JSON.toJSONString(rules),
            ConfigType.JSON.getType()
        );
    }
}
```

### RuleProvider

```java
public interface DynamicRuleProvider<T> {
    T getRules(String appName) throws Exception;
}

@Component
public class FlowRuleNacosProvider implements DynamicRuleProvider<List<FlowRuleEntity>> {

    @Autowired
    private ConfigService configService;

    @Override
    public List<FlowRuleEntity> getRules(String appName) throws Exception {
        String dataId = appName + NacosConfigUtil.FLOW_DATA_ID_POSTFIX;
        String rules = configService.getConfig(
            dataId,
            NacosConfigUtil.GROUP_ID,
            3000
        );

        if (StringUtil.isEmpty(rules)) {
            return new ArrayList<>();
        }

        return JSON.parseArray(rules, FlowRuleEntity.class);
    }
}
```

## 总结

规则管理核心机制：
1. **RuleManager**：管理规则，按资源分组存储
2. **PropertyListener**：监听规则变更，实时生效
3. **DataSource**：抽象数据源，支持Pull和Push
4. **Converter**：规则转换，支持JSON、XML等格式
5. **Validator**：规则校验，确保规则合法性

**推送模式选择**：
- **Pull模式**：定时拉取，实时性差（3秒）
- **Push模式**：配置中心推送，实时性高（秒级）

**最佳实践**：
- 生产环境使用Push模式 + Nacos
- Dashboard改造支持持久化
- 规则变更监控和告警
- 定期备份规则配置
