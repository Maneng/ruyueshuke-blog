---
title: Spring源码深度解析：从使用者到贡献者
date: 2025-11-03T10:00:00+08:00
draft: false
tags:
  - Spring源码
  - IoC
  - AOP
  - 设计模式
  - Java
categories:
  - Java生态
series:
  - Spring框架第一性原理
weight: 6
stage: 5
stageTitle: "源码深度篇"
description: 深入Spring源码，剖析IoC容器启动流程、AOP代理创建、事务管理机制，总结Spring设计模式精华，展望Spring的未来
---

> **系列导航**：本文是《Spring框架第一性原理》系列的第6篇（最终篇）
> - [第1篇：为什么我们需要Spring框架？](/java-ecosystem/posts/2025-11-03-why-we-need-spring/)
> - [第2篇：IoC容器：从手动new到自动装配的演进](/java-ecosystem/posts/2025-11-03-ioc-container-evolution/)
> - [第3篇：AOP：从代码重复到面向切面编程](/java-ecosystem/posts/2025-11-03-aop-aspect-oriented-programming/)
> - [第4篇：Spring Boot：约定优于配置的威力](/java-ecosystem/posts/2025-11-03-spring-boot-convention-over-configuration/)
> - [第5篇：Spring Cloud：从单体到微服务的架构演进](/java-ecosystem/posts/2025-11-03-spring-cloud-microservices/)
> - **第6篇：Spring源码深度解析**（本文）

---

## 引子：为什么要阅读Spring源码？

### 三个真实场景

#### 场景1：面试被问倒

```
面试官："请说说Spring容器的启动流程？"
候选人："Spring容器启动时会扫描注解，创建Bean，然后注入依赖..."
面试官："具体一点，refresh()方法做了哪些事情？"
候选人："呃...不太清楚..."

面试官："那@Transactional是如何实现的？"
候选人："通过AOP代理..."
面试官："什么时候创建代理？代理怎么拦截方法？"
候选人："这个...没深入研究过..."

结果：错失Offer
```

#### 场景2：生产问题无从下手

```
线上问题：Spring容器启动失败

异常信息：
org.springframework.beans.factory.BeanCreationException:
Error creating bean with name 'orderService':
Unsatisfied dependency expressed through field 'userService'

问题：
├─ orderService依赖userService
├─ 但容器中没有userService的Bean
├─ 为什么没有创建？
└─ 如何定位问题？

不懂源码：
❌ 只能Google搜索错误信息
❌ 盲目尝试各种配置
❌ 浪费大量时间

懂源码：
✅ 知道Bean的创建流程
✅ 知道依赖注入的机制
✅ 快速定位到扫描路径配置错误
```

#### 场景3：性能优化无从优化

```
问题：Spring应用启动慢（需要30秒）

不懂源码：
├─ 不知道启动时间花在哪里
├─ 盲目减少Bean数量
└─ 效果有限

懂源码：
├─ 知道refresh()方法的12个步骤
├─ 知道Bean创建的生命周期
├─ 定位到瓶颈：@ComponentScan扫描了大量不必要的类
├─ 优化扫描范围
└─ 启动时间降到5秒
```

### 阅读源码的五大收益

```
1. 面试加分
   └─ 深入理解Spring原理，回答问题有理有据
      └─ 知其然也知其所以然

2. 问题定位
   └─ 遇到问题时，能快速定位根因
      └─ 不再盲目Google，节省时间

3. 性能优化
   └─ 知道性能瓶颈在哪里
      └─ 有针对性地优化

4. 技术提升
   └─ 学习优秀的代码设计
      └─ 学习设计模式的实战应用

5. 贡献开源
   └─ 有能力向Spring提交PR
      └─ 提升技术影响力
```

---

## 源码阅读准备

### 开发环境搭建

#### 1. 下载Spring源码

```bash
# 1. 克隆Spring Framework仓库
git clone https://github.com/spring-projects/spring-framework.git

# 2. 切换到稳定版本（推荐5.3.x）
cd spring-framework
git checkout v5.3.25

# 3. 查看项目结构
tree -L 1
.
├── spring-aop          # AOP模块
├── spring-aspects      # AspectJ集成
├── spring-beans        # Bean管理核心
├── spring-context      # 应用上下文
├── spring-core         # 核心工具类
├── spring-expression   # SpEL表达式
├── spring-jdbc         # JDBC支持
├── spring-orm          # ORM集成
├── spring-tx           # 事务管理
├── spring-web          # Web基础
├── spring-webmvc       # Spring MVC
└── spring-webflux      # 响应式Web
```

#### 2. 导入IDEA

```
步骤：
1. 打开IDEA → Open → 选择spring-framework目录
2. 等待Gradle构建完成（首次需要10-30分钟）
3. 构建完成后，项目结构如下：

spring-framework/
├── spring-beans/
│   └── src/main/java/
│       └── org/springframework/beans/
│           ├── factory/
│           │   ├── BeanFactory.java            # Bean工厂接口
│           │   ├── support/
│           │   │   ├── AbstractBeanFactory.java
│           │   │   └── DefaultListableBeanFactory.java
│           │   └── config/
│           │       └── BeanDefinition.java      # Bean定义
│           └── BeanWrapper.java
├── spring-context/
│   └── src/main/java/
│       └── org/springframework/context/
│           ├── ApplicationContext.java          # 应用上下文接口
│           ├── support/
│           │   └── AbstractApplicationContext.java  # 启动核心
│           └── annotation/
│               └── AnnotationConfigApplicationContext.java
└── spring-aop/
    └── src/main/java/
        └── org/springframework/aop/
            └── framework/
                ├── ProxyFactory.java
                └── autoproxy/
                    └── AbstractAutoProxyCreator.java

常用快捷键：
├─ Ctrl+N (Mac: Cmd+O)：搜索类
├─ Ctrl+Shift+N：搜索文件
├─ Ctrl+Alt+B (Mac: Cmd+Alt+B)：查看接口实现
├─ Ctrl+H：查看类层次结构
└─ Ctrl+F12：查看类的方法列表
```

#### 3. 编写测试用例

```java
// 创建测试项目：spring-source-test
// pom.xml
<dependencies>
    <!-- Spring核心依赖 -->
    <dependency>
        <groupId>org.springframework</groupId>
        <artifactId>spring-context</artifactId>
        <version>5.3.25</version>
    </dependency>

    <!-- 测试依赖 -->
    <dependency>
        <groupId>junit</groupId>
        <artifactId>junit</artifactId>
        <version>4.13.2</version>
        <scope>test</scope>
    </dependency>
</dependencies>

// 测试代码
@Configuration
@ComponentScan("com.example")
public class AppConfig {
}

@Component
public class UserService {
    public void sayHello() {
        System.out.println("Hello from UserService");
    }
}

// 测试类
public class SpringSourceTest {
    public static void main(String[] args) {
        // 在这里打断点，开始调试
        ApplicationContext context =
            new AnnotationConfigApplicationContext(AppConfig.class);

        UserService userService = context.getBean(UserService.class);
        userService.sayHello();
    }
}

调试技巧：
1. 在new AnnotationConfigApplicationContext(AppConfig.class)打断点
2. Step Into (F7)，进入构造方法
3. 一步步跟踪执行流程
4. 关注关键方法：refresh()、invokeBeanFactoryPostProcessors()、finishBeanFactoryInitialization()
```

### 源码阅读方法论

#### 方法1：从顶层接口入手

```
阅读顺序（IoC容器）：
1. BeanFactory               # 最顶层接口，定义基本功能
   ├─ getBean()              # 获取Bean
   ├─ containsBean()         # 是否包含Bean
   └─ isSingleton()          # 是否单例

2. ApplicationContext        # 扩展接口，增强功能
   ├─ 继承BeanFactory        # Bean管理
   ├─ 继承MessageSource      # 国际化
   ├─ 继承ApplicationEventPublisher  # 事件发布
   └─ 继承ResourceLoader     # 资源加载

3. AbstractApplicationContext  # 抽象实现类，定义模板
   └─ refresh()              # 核心方法，定义启动流程

4. AnnotationConfigApplicationContext  # 具体实现类
   └─ 使用注解配置

原则：
✅ 先看接口，理解设计意图
✅ 再看抽象类，理解模板流程
✅ 最后看具体实现，理解细节
❌ 避免：直接看具体实现（容易迷失）
```

#### 方法2：以功能为主线

```
功能主线1：Bean的创建流程
└─ 入口：ApplicationContext.getBean()
   └─ AbstractBeanFactory.doGetBean()
      └─ AbstractAutowireCapableBeanFactory.createBean()
         └─ AbstractAutowireCapableBeanFactory.doCreateBean()
            ├─ createBeanInstance()        # 实例化
            ├─ populateBean()              # 属性填充
            └─ initializeBean()            # 初始化

功能主线2：AOP代理的创建
└─ 入口：@EnableAspectJAutoProxy
   └─ AspectJAutoProxyRegistrar
      └─ AnnotationAwareAspectJAutoProxyCreator
         └─ postProcessAfterInitialization()  # Bean后置处理
            └─ wrapIfNecessary()               # 创建代理

功能主线3：事务的拦截
└─ 入口：@EnableTransactionManagement
   └─ TransactionInterceptor
      └─ invoke()                            # 拦截方法
         ├─ createTransactionIfNecessary()   # 开启事务
         ├─ invokation.proceed()             # 执行方法
         └─ commitTransactionAfterReturning() # 提交事务

原则：
✅ 选择一个功能点，深入研究
✅ 画出调用链路图
✅ 理解每个方法的职责
❌ 避免：同时看多个功能（容易混乱）
```

#### 方法3：Debug + 日志

```java
// 开启Spring Debug日志
logging.level.org.springframework=DEBUG

// 在关键位置打断点
public class SpringSourceTest {
    public static void main(String[] args) {
        // 断点1：容器创建
        ApplicationContext context =
            new AnnotationConfigApplicationContext(AppConfig.class);

        // 断点2：Bean获取
        UserService userService = context.getBean(UserService.class);

        // 断点3：方法调用
        userService.sayHello();
    }
}

// 查看调用栈
断点1命中时，查看Call Stack：
main()
└─ AnnotationConfigApplicationContext.<init>()
   └─ AbstractApplicationContext.refresh()
      ├─ prepareRefresh()
      ├─ obtainFreshBeanFactory()
      ├─ prepareBeanFactory()
      ├─ postProcessBeanFactory()
      ├─ invokeBeanFactoryPostProcessors()  ← 处理@Configuration、@Bean
      ├─ registerBeanPostProcessors()       ← 注册BeanPostProcessor
      ├─ initMessageSource()
      ├─ initApplicationEventMulticaster()
      ├─ onRefresh()
      ├─ registerListeners()
      └─ finishBeanFactoryInitialization()  ← 创建所有单例Bean

// 使用条件断点
右键断点 → Condition：
beanName.equals("userService")  # 只在创建userService时暂停

// 使用日志断点
右键断点 → Evaluate and log：
"Creating bean: " + beanName  # 记录日志，不暂停程序
```

---

## IoC容器启动流程：refresh()方法深度剖析

### refresh()方法概览

```java
// AbstractApplicationContext.refresh()
// 这是Spring容器启动的核心方法，包含12个步骤

@Override
public void refresh() throws BeansException, IllegalStateException {
    synchronized (this.startupShutdownMonitor) {
        // 1. 准备刷新上下文环境
        prepareRefresh();

        // 2. 获取BeanFactory（告诉子类刷新内部BeanFactory）
        ConfigurableListableBeanFactory beanFactory = obtainFreshBeanFactory();

        // 3. 准备BeanFactory（配置BeanFactory的标准上下文）
        prepareBeanFactory(beanFactory);

        try {
            // 4. BeanFactory后置处理（允许子类对BeanFactory进行后置处理）
            postProcessBeanFactory(beanFactory);

            // 5. 调用BeanFactory后置处理器（执行所有BeanFactoryPostProcessor）
            invokeBeanFactoryPostProcessors(beanFactory);

            // 6. 注册Bean后置处理器（注册所有BeanPostProcessor）
            registerBeanPostProcessors(beanFactory);

            // 7. 初始化消息源（国际化）
            initMessageSource();

            // 8. 初始化事件广播器
            initApplicationEventMulticaster();

            // 9. 刷新上下文（允许子类初始化特殊Bean，如内嵌Web容器）
            onRefresh();

            // 10. 注册监听器
            registerListeners();

            // 11. 初始化所有单例Bean（非懒加载）
            finishBeanFactoryInitialization(beanFactory);

            // 12. 完成刷新（发布ContextRefreshedEvent事件）
            finishRefresh();
        }
        catch (BeansException ex) {
            // 销毁已创建的Bean
            destroyBeans();

            // 取消刷新
            cancelRefresh(ex);

            throw ex;
        }
        finally {
            // 清理缓存
            resetCommonCaches();
        }
    }
}
```

### 步骤1：prepareRefresh() - 准备刷新

```java
protected void prepareRefresh() {
    // 1. 记录启动时间
    this.startupDate = System.currentTimeMillis();

    // 2. 设置容器状态
    this.closed.set(false);       // 未关闭
    this.active.set(true);        // 已激活

    // 3. 初始化属性源（可由子类覆盖）
    initPropertySources();

    // 4. 验证必需的属性
    // 例如：getEnvironment().setRequiredProperties("JAVA_HOME");
    getEnvironment().validateRequiredProperties();

    // 5. 创建早期事件集合（在事件广播器准备好之前收集事件）
    if (this.earlyApplicationListeners == null) {
        this.earlyApplicationListeners = new LinkedHashSet<>(this.applicationListeners);
    }
    else {
        this.applicationListeners.clear();
        this.applicationListeners.addAll(this.earlyApplicationListeners);
    }

    // 6. 创建早期事件集合
    this.earlyApplicationEvents = new LinkedHashSet<>();
}

作用：
✅ 记录启动时间（用于统计启动耗时）
✅ 设置容器状态（标记为激活状态）
✅ 初始化和验证环境变量
✅ 准备事件监听器
```

### 步骤2：obtainFreshBeanFactory() - 获取BeanFactory

```java
protected ConfigurableListableBeanFactory obtainFreshBeanFactory() {
    // 刷新BeanFactory（由子类实现）
    refreshBeanFactory();

    // 返回BeanFactory
    return getBeanFactory();
}

// AbstractRefreshableApplicationContext（XML配置）
@Override
protected final void refreshBeanFactory() throws BeansException {
    // 如果已有BeanFactory，先销毁
    if (hasBeanFactory()) {
        destroyBeans();
        closeBeanFactory();
    }

    try {
        // 创建新的BeanFactory（DefaultListableBeanFactory）
        DefaultListableBeanFactory beanFactory = createBeanFactory();

        // 设置序列化ID
        beanFactory.setSerializationId(getId());

        // 定制BeanFactory（是否允许Bean覆盖、是否允许循环依赖）
        customizeBeanFactory(beanFactory);

        // 加载Bean定义（从XML文件）
        loadBeanDefinitions(beanFactory);

        // 保存BeanFactory引用
        this.beanFactory = beanFactory;
    }
    catch (IOException ex) {
        throw new ApplicationContextException("I/O error parsing bean definition source", ex);
    }
}

// GenericApplicationContext（注解配置）
@Override
protected final void refreshBeanFactory() throws IllegalStateException {
    // 标记为已刷新
    if (!this.refreshed.compareAndSet(false, true)) {
        throw new IllegalStateException("GenericApplicationContext does not support multiple refresh attempts");
    }

    // 设置序列化ID
    this.beanFactory.setSerializationId(getId());
}

对比：
XML配置（AbstractRefreshableApplicationContext）：
  └─ 每次refresh都创建新的BeanFactory
  └─ 从XML文件加载Bean定义

注解配置（GenericApplicationContext）：
  └─ BeanFactory在构造方法中创建（只创建一次）
  └─ Bean定义通过注解扫描加载（在步骤5）
```

### 步骤3：prepareBeanFactory() - 准备BeanFactory

```java
protected void prepareBeanFactory(ConfigurableListableBeanFactory beanFactory) {
    // 1. 设置类加载器
    beanFactory.setBeanClassLoader(getClassLoader());

    // 2. 设置SpEL表达式解析器
    beanFactory.setBeanExpressionResolver(
        new StandardBeanExpressionResolver(beanFactory.getBeanClassLoader())
    );

    // 3. 添加属性编辑器注册器（用于类型转换）
    beanFactory.addPropertyEditorRegistrar(
        new ResourceEditorRegistrar(this, getEnvironment())
    );

    // 4. 添加BeanPostProcessor：ApplicationContextAwareProcessor
    // 作用：处理Aware接口回调（ApplicationContextAware、EnvironmentAware等）
    beanFactory.addBeanPostProcessor(
        new ApplicationContextAwareProcessor(this)
    );

    // 5. 忽略以下Aware接口的依赖注入（由ApplicationContextAwareProcessor处理）
    beanFactory.ignoreDependencyInterface(EnvironmentAware.class);
    beanFactory.ignoreDependencyInterface(EmbeddedValueResolverAware.class);
    beanFactory.ignoreDependencyInterface(ResourceLoaderAware.class);
    beanFactory.ignoreDependencyInterface(ApplicationEventPublisherAware.class);
    beanFactory.ignoreDependencyInterface(MessageSourceAware.class);
    beanFactory.ignoreDependencyInterface(ApplicationContextAware.class);

    // 6. 注册可解析的依赖（自动装配时使用）
    beanFactory.registerResolvableDependency(BeanFactory.class, beanFactory);
    beanFactory.registerResolvableDependency(ResourceLoader.class, this);
    beanFactory.registerResolvableDependency(ApplicationEventPublisher.class, this);
    beanFactory.registerResolvableDependency(ApplicationContext.class, this);

    // 7. 添加BeanPostProcessor：ApplicationListenerDetector
    // 作用：检测ApplicationListener类型的Bean并注册到事件广播器
    beanFactory.addBeanPostProcessor(
        new ApplicationListenerDetector(this)
    );

    // 8. 如果存在LoadTimeWeaver，添加编织支持
    if (beanFactory.containsBean(LOAD_TIME_WEAVER_BEAN_NAME)) {
        beanFactory.addBeanPostProcessor(new LoadTimeWeaverAwareProcessor(beanFactory));
        beanFactory.setTempClassLoader(new ContextTypeMatchClassLoader(beanFactory.getBeanClassLoader()));
    }

    // 9. 注册默认的环境Bean
    if (!beanFactory.containsLocalBean(ENVIRONMENT_BEAN_NAME)) {
        beanFactory.registerSingleton(ENVIRONMENT_BEAN_NAME, getEnvironment());
    }
    if (!beanFactory.containsLocalBean(SYSTEM_PROPERTIES_BEAN_NAME)) {
        beanFactory.registerSingleton(SYSTEM_PROPERTIES_BEAN_NAME, getEnvironment().getSystemProperties());
    }
    if (!beanFactory.containsLocalBean(SYSTEM_ENVIRONMENT_BEAN_NAME)) {
        beanFactory.registerSingleton(SYSTEM_ENVIRONMENT_BEAN_NAME, getEnvironment().getSystemEnvironment());
    }
}

作用：
✅ 配置类加载器、表达式解析器
✅ 添加BeanPostProcessor（处理Aware接口回调）
✅ 注册可解析的依赖（BeanFactory、ApplicationContext等）
✅ 注册环境Bean（Environment、System Properties等）
```

### 步骤5：invokeBeanFactoryPostProcessors() - 执行BeanFactory后置处理器

**这是最复杂也是最重要的步骤之一，负责处理@Configuration、@Bean、@ComponentScan等注解**

```java
protected void invokeBeanFactoryPostProcessors(ConfigurableListableBeanFactory beanFactory) {
    // 执行所有BeanFactoryPostProcessor
    PostProcessorRegistrationDelegate.invokeBeanFactoryPostProcessors(beanFactory, getBeanFactoryPostProcessors());

    // 如果存在LoadTimeWeaver，添加编织支持
    if (beanFactory.getTempClassLoader() == null && beanFactory.containsBean(LOAD_TIME_WEAVER_BEAN_NAME)) {
        beanFactory.addBeanPostProcessor(new LoadTimeWeaverAwareProcessor(beanFactory));
        beanFactory.setTempClassLoader(new ContextTypeMatchClassLoader(beanFactory.getBeanClassLoader()));
    }
}

// PostProcessorRegistrationDelegate.invokeBeanFactoryPostProcessors()
// 执行顺序：
1. 执行手动注册的BeanDefinitionRegistryPostProcessor
   └─ postProcessBeanDefinitionRegistry()

2. 执行容器中的BeanDefinitionRegistryPostProcessor（按优先级）
   └─ 实现PriorityOrdered接口的
   └─ 实现Ordered接口的
   └─ 其他的

3. 执行所有BeanDefinitionRegistryPostProcessor的postProcessBeanFactory()

4. 执行手动注册的BeanFactoryPostProcessor

5. 执行容器中的BeanFactoryPostProcessor（按优先级）
   └─ 实现PriorityOrdered接口的
   └─ 实现Ordered接口的
   └─ 其他的

关键处理器：
├─ ConfigurationClassPostProcessor（最重要）
│   ├─ 处理@Configuration类
│   ├─ 处理@Bean方法
│   ├─ 处理@Import注解
│   ├─ 处理@ComponentScan注解
│   └─ 注册BeanDefinition
└─ AutowiredAnnotationBeanPostProcessor
    └─ 处理@Autowired、@Value注解
```

**ConfigurationClassPostProcessor详解**：

```java
// ConfigurationClassPostProcessor.postProcessBeanDefinitionRegistry()
public void postProcessBeanDefinitionRegistry(BeanDefinitionRegistry registry) {
    // ...
    processConfigBeanDefinitions(registry);
}

public void processConfigBeanDefinitions(BeanDefinitionRegistry registry) {
    // 1. 找到所有@Configuration类
    List<BeanDefinitionHolder> configCandidates = new ArrayList<>();
    String[] candidateNames = registry.getBeanDefinitionNames();

    for (String beanName : candidateNames) {
        BeanDefinition beanDef = registry.getBeanDefinition(beanName);

        // 检查是否是@Configuration类
        if (ConfigurationClassUtils.checkConfigurationClassCandidate(beanDef, this.metadataReaderFactory)) {
            configCandidates.add(new BeanDefinitionHolder(beanDef, beanName));
        }
    }

    // 2. 如果没有@Configuration类，直接返回
    if (configCandidates.isEmpty()) {
        return;
    }

    // 3. 按@Order排序
    configCandidates.sort((bd1, bd2) -> {
        int i1 = ConfigurationClassUtils.getOrder(bd1.getBeanDefinition());
        int i2 = ConfigurationClassUtils.getOrder(bd2.getBeanDefinition());
        return Integer.compare(i1, i2);
    });

    // 4. 解析@Configuration类
    ConfigurationClassParser parser = new ConfigurationClassParser(
        this.metadataReaderFactory, this.problemReporter,
        this.environment, this.resourceLoader,
        this.componentScanBeanNameGenerator, registry
    );

    Set<BeanDefinitionHolder> candidates = new LinkedHashSet<>(configCandidates);
    Set<ConfigurationClass> alreadyParsed = new HashSet<>(configCandidates.size());

    do {
        // 解析@Configuration类
        parser.parse(candidates);
        parser.validate();

        // 获取所有配置类（包括@Import导入的）
        Set<ConfigurationClass> configClasses = new LinkedHashSet<>(parser.getConfigurationClasses());
        configClasses.removeAll(alreadyParsed);

        // 5. 读取配置类，注册BeanDefinition
        if (this.reader == null) {
            this.reader = new ConfigurationClassBeanDefinitionReader(
                registry, this.sourceExtractor, this.resourceLoader,
                this.environment, this.importBeanNameGenerator, parser.getImportRegistry()
            );
        }

        // 加载Bean定义（@Bean方法、@Import等）
        this.reader.loadBeanDefinitions(configClasses);
        alreadyParsed.addAll(configClasses);

        candidates.clear();

        // 检查是否有新的@Configuration类
        if (registry.getBeanDefinitionCount() > candidateNames.length) {
            String[] newCandidateNames = registry.getBeanDefinitionNames();
            Set<String> oldCandidateNames = new HashSet<>(Arrays.asList(candidateNames));
            Set<String> alreadyParsedClasses = new HashSet<>();

            for (ConfigurationClass configurationClass : alreadyParsed) {
                alreadyParsedClasses.add(configurationClass.getMetadata().getClassName());
            }

            for (String candidateName : newCandidateNames) {
                if (!oldCandidateNames.contains(candidateName)) {
                    BeanDefinition bd = registry.getBeanDefinition(candidateName);
                    if (ConfigurationClassUtils.checkConfigurationClassCandidate(bd, this.metadataReaderFactory) &&
                        !alreadyParsedClasses.contains(bd.getBeanClassName())) {
                        candidates.add(new BeanDefinitionHolder(bd, candidateName));
                    }
                }
            }
            candidateNames = newCandidateNames;
        }
    }
    while (!candidates.isEmpty());

    // 6. 注册ImportRegistry为Bean
    if (!registry.containsBeanDefinition(IMPORT_REGISTRY_BEAN_NAME)) {
        registry.registerBeanDefinition(IMPORT_REGISTRY_BEAN_NAME,
            new RootBeanDefinition(ImportRegistry.class));
    }

    // 7. 清理缓存
    this.metadataReaderFactory.clearCache();
}

处理流程示例：
@Configuration
@ComponentScan("com.example")
public class AppConfig {
    @Bean
    public UserService userService() {
        return new UserService();
    }
}

执行步骤：
1. 找到AppConfig类（标注了@Configuration）
2. 解析@ComponentScan注解
   └─ 扫描com.example包
   └─ 找到所有@Component、@Service、@Repository、@Controller
   └─ 注册为BeanDefinition
3. 解析@Bean方法
   └─ 找到userService()方法
   └─ 注册为BeanDefinition（名称：userService，类型：UserService）
4. 处理@Import注解（如果有）
5. 处理@PropertySource注解（如果有）
```

### 步骤6：registerBeanPostProcessors() - 注册Bean后置处理器

```java
protected void registerBeanPostProcessors(ConfigurableListableBeanFactory beanFactory) {
    PostProcessorRegistrationDelegate.registerBeanPostProcessors(beanFactory, this);
}

// PostProcessorRegistrationDelegate.registerBeanPostProcessors()
public static void registerBeanPostProcessors(
        ConfigurableListableBeanFactory beanFactory, AbstractApplicationContext applicationContext) {

    // 1. 找到所有BeanPostProcessor的Bean名称
    String[] postProcessorNames = beanFactory.getBeanNamesForType(BeanPostProcessor.class, true, false);

    // 2. 计算BeanPostProcessor数量
    int beanProcessorTargetCount = beanFactory.getBeanPostProcessorCount() + 1 + postProcessorNames.length;

    // 3. 添加BeanPostProcessorChecker（用于记录日志）
    beanFactory.addBeanPostProcessor(new BeanPostProcessorChecker(beanFactory, beanProcessorTargetCount));

    // 4. 按优先级分组
    List<BeanPostProcessor> priorityOrderedPostProcessors = new ArrayList<>();
    List<BeanPostProcessor> internalPostProcessors = new ArrayList<>();
    List<String> orderedPostProcessorNames = new ArrayList<>();
    List<String> nonOrderedPostProcessorNames = new ArrayList<>();

    for (String ppName : postProcessorNames) {
        if (beanFactory.isTypeMatch(ppName, PriorityOrdered.class)) {
            BeanPostProcessor pp = beanFactory.getBean(ppName, BeanPostProcessor.class);
            priorityOrderedPostProcessors.add(pp);
            if (pp instanceof MergedBeanDefinitionPostProcessor) {
                internalPostProcessors.add(pp);
            }
        }
        else if (beanFactory.isTypeMatch(ppName, Ordered.class)) {
            orderedPostProcessorNames.add(ppName);
        }
        else {
            nonOrderedPostProcessorNames.add(ppName);
        }
    }

    // 5. 注册实现PriorityOrdered接口的BeanPostProcessor
    sortPostProcessors(priorityOrderedPostProcessors, beanFactory);
    registerBeanPostProcessors(beanFactory, priorityOrderedPostProcessors);

    // 6. 注册实现Ordered接口的BeanPostProcessor
    List<BeanPostProcessor> orderedPostProcessors = new ArrayList<>(orderedPostProcessorNames.size());
    for (String ppName : orderedPostProcessorNames) {
        BeanPostProcessor pp = beanFactory.getBean(ppName, BeanPostProcessor.class);
        orderedPostProcessors.add(pp);
        if (pp instanceof MergedBeanDefinitionPostProcessor) {
            internalPostProcessors.add(pp);
        }
    }
    sortPostProcessors(orderedPostProcessors, beanFactory);
    registerBeanPostProcessors(beanFactory, orderedPostProcessors);

    // 7. 注册普通的BeanPostProcessor
    List<BeanPostProcessor> nonOrderedPostProcessors = new ArrayList<>(nonOrderedPostProcessorNames.size());
    for (String ppName : nonOrderedPostProcessorNames) {
        BeanPostProcessor pp = beanFactory.getBean(ppName, BeanPostProcessor.class);
        nonOrderedPostProcessors.add(pp);
        if (pp instanceof MergedBeanDefinitionPostProcessor) {
            internalPostProcessors.add(pp);
        }
    }
    registerBeanPostProcessors(beanFactory, nonOrderedPostProcessors);

    // 8. 最后注册内部的BeanPostProcessor（MergedBeanDefinitionPostProcessor）
    sortPostProcessors(internalPostProcessors, beanFactory);
    registerBeanPostProcessors(beanFactory, internalPostProcessors);

    // 9. 重新注册ApplicationListenerDetector（移到最后）
    beanFactory.addBeanPostProcessor(new ApplicationListenerDetector(applicationContext));
}

注册顺序：
1. 实现PriorityOrdered接口的
2. 实现Ordered接口的
3. 普通的
4. 内部的（MergedBeanDefinitionPostProcessor）
5. ApplicationListenerDetector（最后）

常见的BeanPostProcessor：
├─ AutowiredAnnotationBeanPostProcessor（处理@Autowired）
├─ CommonAnnotationBeanPostProcessor（处理@Resource、@PostConstruct、@PreDestroy）
├─ AnnotationAwareAspectJAutoProxyCreator（创建AOP代理）
└─ ApplicationListenerDetector（检测ApplicationListener）
```

### 步骤11：finishBeanFactoryInitialization() - 初始化所有单例Bean

**这是容器启动最重要的步骤，所有单例Bean都在这里创建**

```java
protected void finishBeanFactoryInitialization(ConfigurableListableBeanFactory beanFactory) {
    // 1. 初始化类型转换服务
    if (beanFactory.containsBean(CONVERSION_SERVICE_BEAN_NAME) &&
        beanFactory.isTypeMatch(CONVERSION_SERVICE_BEAN_NAME, ConversionService.class)) {
        beanFactory.setConversionService(
            beanFactory.getBean(CONVERSION_SERVICE_BEAN_NAME, ConversionService.class));
    }

    // 2. 注册默认的嵌入式值解析器（如果没有BeanPostProcessor注册）
    if (!beanFactory.hasEmbeddedValueResolver()) {
        beanFactory.addEmbeddedValueResolver(strVal -> getEnvironment().resolvePlaceholders(strVal));
    }

    // 3. 初始化LoadTimeWeaverAware类型的Bean
    String[] weaverAwareNames = beanFactory.getBeanNamesForType(LoadTimeWeaverAware.class, false, false);
    for (String weaverAwareName : weaverAwareNames) {
        getBean(weaverAwareName);
    }

    // 4. 停止使用临时类加载器
    beanFactory.setTempClassLoader(null);

    // 5. 冻结配置（不再修改BeanDefinition）
    beanFactory.freezeConfiguration();

    // 6. 实例化所有剩余的单例Bean（核心）
    beanFactory.preInstantiateSingletons();
}

// DefaultListableBeanFactory.preInstantiateSingletons()
@Override
public void preInstantiateSingletons() throws BeansException {
    // 1. 获取所有Bean名称
    List<String> beanNames = new ArrayList<>(this.beanDefinitionNames);

    // 2. 遍历所有Bean名称，触发初始化
    for (String beanName : beanNames) {
        // 合并父Bean定义
        RootBeanDefinition bd = getMergedLocalBeanDefinition(beanName);

        // 检查是否是抽象、单例、懒加载
        if (!bd.isAbstract() && bd.isSingleton() && !bd.isLazyInit()) {
            // 如果是FactoryBean
            if (isFactoryBean(beanName)) {
                // 获取FactoryBean本身
                Object bean = getBean(FACTORY_BEAN_PREFIX + beanName);

                // 如果FactoryBean实现了SmartFactoryBean且希望立即初始化
                if (bean instanceof FactoryBean) {
                    FactoryBean<?> factory = (FactoryBean<?>) bean;
                    boolean isEagerInit;
                    if (System.getSecurityManager() != null && factory instanceof SmartFactoryBean) {
                        isEagerInit = AccessController.doPrivileged(
                            (PrivilegedAction<Boolean>) ((SmartFactoryBean<?>) factory)::isEagerInit,
                            getAccessControlContext()
                        );
                    }
                    else {
                        isEagerInit = (factory instanceof SmartFactoryBean &&
                            ((SmartFactoryBean<?>) factory).isEagerInit());
                    }
                    if (isEagerInit) {
                        getBean(beanName);
                    }
                }
            }
            else {
                // 普通Bean，直接获取（触发创建）
                getBean(beanName);
            }
        }
    }

    // 3. 触发所有SmartInitializingSingleton的回调
    for (String beanName : beanNames) {
        Object singletonInstance = getSingleton(beanName);
        if (singletonInstance instanceof SmartInitializingSingleton) {
            SmartInitializingSingleton smartSingleton = (SmartInitializingSingleton) singletonInstance;
            if (System.getSecurityManager() != null) {
                AccessController.doPrivileged((PrivilegedAction<Object>) () -> {
                    smartSingleton.afterSingletonsInstantiated();
                    return null;
                }, getAccessControlContext());
            }
            else {
                smartSingleton.afterSingletonsInstantiated();
            }
        }
    }
}

流程：
1. 获取所有Bean名称
2. 遍历每个Bean：
   ├─ 如果不是抽象、是单例、不是懒加载
   │   ├─ 如果是FactoryBean → 特殊处理
   │   └─ 如果是普通Bean → getBean()触发创建
   └─ 跳过（抽象、原型、懒加载）
3. 触发SmartInitializingSingleton回调
```

---

## Bean的创建流程：doCreateBean()方法

### getBean()调用链

```
ApplicationContext.getBean()
└─ AbstractBeanFactory.getBean()
   └─ AbstractBeanFactory.doGetBean()
      ├─ 1. 转换Bean名称（处理别名、&前缀）
      ├─ 2. 从缓存获取单例Bean
      │   └─ getSingleton() → 三级缓存
      ├─ 3. 如果缓存没有，检查父容器
      ├─ 4. 标记Bean正在创建
      ├─ 5. 处理@DependsOn依赖
      ├─ 6. 创建Bean实例
      │   ├─ 单例：getSingleton() → createBean()
      │   ├─ 原型：createBean()
      │   └─ 其他作用域：scope.get()
      └─ 7. 类型转换
```

### createBean()方法详解

```java
// AbstractAutowireCapableBeanFactory.createBean()
@Override
protected Object createBean(String beanName, RootBeanDefinition mbd, @Nullable Object[] args)
        throws BeanCreationException {

    RootBeanDefinition mbdToUse = mbd;

    // 1. 确保Bean类已经解析
    Class<?> resolvedClass = resolveBeanClass(mbd, beanName);
    if (resolvedClass != null && !mbd.hasBeanClass() && mbd.getBeanClassName() != null) {
        mbdToUse = new RootBeanDefinition(mbd);
        mbdToUse.setBeanClass(resolvedClass);
    }

    // 2. 准备方法覆盖（处理@Lookup、replace-method）
    try {
        mbdToUse.prepareMethodOverrides();
    }
    catch (BeanDefinitionValidationException ex) {
        throw new BeanDefinitionStoreException(mbdToUse.getResourceDescription(),
            beanName, "Validation of method overrides failed", ex);
    }

    try {
        // 3. 给BeanPostProcessor机会返回代理对象（InstantiationAwareBeanPostProcessor）
        Object bean = resolveBeforeInstantiation(beanName, mbdToUse);
        if (bean != null) {
            return bean;  // 短路：直接返回代理对象
        }
    }
    catch (Throwable ex) {
        throw new BeanCreationException(mbdToUse.getResourceDescription(), beanName,
            "BeanPostProcessor before instantiation of bean failed", ex);
    }

    try {
        // 4. 实际创建Bean（核心）
        Object beanInstance = doCreateBean(beanName, mbdToUse, args);
        return beanInstance;
    }
    catch (BeanCreationException | ImplicitlyAppearedSingletonException ex) {
        throw ex;
    }
    catch (Throwable ex) {
        throw new BeanCreationException(
            mbdToUse.getResourceDescription(), beanName, "Unexpected exception during bean creation", ex);
    }
}
```

### doCreateBean()方法详解

```java
// AbstractAutowireCapableBeanFactory.doCreateBean()
// 这是Bean创建的核心方法
protected Object doCreateBean(String beanName, RootBeanDefinition mbd, @Nullable Object[] args)
        throws BeanCreationException {

    // 1. 实例化Bean
    BeanWrapper instanceWrapper = null;
    if (mbd.isSingleton()) {
        instanceWrapper = this.factoryBeanInstanceCache.remove(beanName);
    }
    if (instanceWrapper == null) {
        // 创建Bean实例（调用构造方法）
        instanceWrapper = createBeanInstance(beanName, mbd, args);
    }
    Object bean = instanceWrapper.getWrappedInstance();
    Class<?> beanType = instanceWrapper.getWrappedClass();

    // 2. 允许BeanPostProcessor修改合并的Bean定义
    synchronized (mbd.postProcessingLock) {
        if (!mbd.postProcessed) {
            try {
                // MergedBeanDefinitionPostProcessor.postProcessMergedBeanDefinition()
                applyMergedBeanDefinitionPostProcessors(mbd, beanType, beanName);
            }
            catch (Throwable ex) {
                throw new BeanCreationException(mbd.getResourceDescription(), beanName,
                    "Post-processing of merged bean definition failed", ex);
            }
            mbd.postProcessed = true;
        }
    }

    // 3. 提前暴露单例Bean（解决循环依赖）
    boolean earlySingletonExposure = (mbd.isSingleton() && this.allowCircularReferences &&
            isSingletonCurrentlyInCreation(beanName));
    if (earlySingletonExposure) {
        // 添加到三级缓存
        addSingletonFactory(beanName, () -> getEarlyBeanReference(beanName, mbd, bean));
    }

    // 4. 填充属性（依赖注入）
    Object exposedObject = bean;
    try {
        // 属性填充：@Autowired、@Resource、@Value
        populateBean(beanName, mbd, instanceWrapper);

        // 初始化Bean（Aware接口回调、@PostConstruct、InitializingBean、init-method）
        exposedObject = initializeBean(beanName, exposedObject, mbd);
    }
    catch (Throwable ex) {
        if (ex instanceof BeanCreationException && beanName.equals(((BeanCreationException) ex).getBeanName())) {
            throw (BeanCreationException) ex;
        }
        else {
            throw new BeanCreationException(
                mbd.getResourceDescription(), beanName, "Initialization of bean failed", ex);
        }
    }

    // 5. 处理循环依赖
    if (earlySingletonExposure) {
        Object earlySingletonReference = getSingleton(beanName, false);
        if (earlySingletonReference != null) {
            if (exposedObject == bean) {
                exposedObject = earlySingletonReference;
            }
            else if (!this.allowRawInjectionDespiteWrapping && hasDependentBean(beanName)) {
                String[] dependentBeans = getDependentBeans(beanName);
                Set<String> actualDependentBeans = new LinkedHashSet<>(dependentBeans.length);
                for (String dependentBean : dependentBeans) {
                    if (!removeSingletonIfCreatedForTypeCheckOnly(dependentBean)) {
                        actualDependentBeans.add(dependentBean);
                    }
                }
                if (!actualDependentBeans.isEmpty()) {
                    throw new BeanCurrentlyInCreationException(beanName,
                        "Bean with name '" + beanName + "' has been injected into other beans [" +
                        StringUtils.collectionToCommaDelimitedString(actualDependentBeans) +
                        "] in its raw version as part of a circular reference, but has eventually been " +
                        "wrapped. This means that said other beans do not use the final version of the " +
                        "bean. This is often the result of over-eager type matching - consider using " +
                        "'getBeanNamesForType' with the 'allowEagerInit' flag turned off, for example.");
                }
            }
        }
    }

    // 6. 注册销毁回调
    try {
        registerDisposableBeanIfNecessary(beanName, bean, mbd);
    }
    catch (BeanDefinitionValidationException ex) {
        throw new BeanCreationException(
            mbd.getResourceDescription(), beanName, "Invalid destruction signature", ex);
    }

    return exposedObject;
}

完整流程：
1. createBeanInstance()      # 实例化（调用构造方法）
2. applyMergedBeanDefinitionPostProcessors()  # 合并Bean定义
3. addSingletonFactory()     # 添加到三级缓存（解决循环依赖）
4. populateBean()            # 属性填充（依赖注入）
5. initializeBean()          # 初始化
   ├─ invokeAwareMethods()              # Aware接口回调
   ├─ applyBeanPostProcessorsBeforeInitialization()  # @PostConstruct
   ├─ invokeInitMethods()               # InitializingBean、init-method
   └─ applyBeanPostProcessorsAfterInitialization()   # AOP代理创建
6. registerDisposableBeanIfNecessary()  # 注册销毁回调
```

### createBeanInstance() - 实例化

```java
protected BeanWrapper createBeanInstance(String beanName, RootBeanDefinition mbd, @Nullable Object[] args) {
    // 1. 确保Bean类已加载
    Class<?> beanClass = resolveBeanClass(mbd, beanName);

    // 2. 检查Bean类的访问权限
    if (beanClass != null && !Modifier.isPublic(beanClass.getModifiers()) && !mbd.isNonPublicAccessAllowed()) {
        throw new BeanCreationException(mbd.getResourceDescription(), beanName,
            "Bean class isn't public, and non-public access not allowed: " + beanClass.getName());
    }

    // 3. 如果有Supplier，使用Supplier创建实例
    Supplier<?> instanceSupplier = mbd.getInstanceSupplier();
    if (instanceSupplier != null) {
        return obtainFromSupplier(instanceSupplier, beanName);
    }

    // 4. 如果有工厂方法，使用工厂方法创建实例（@Bean方法）
    if (mbd.getFactoryMethodName() != null) {
        return instantiateUsingFactoryMethod(beanName, mbd, args);
    }

    // 5. 重新创建相同Bean时的快捷方式
    boolean resolved = false;
    boolean autowireNecessary = false;
    if (args == null) {
        synchronized (mbd.constructorArgumentLock) {
            if (mbd.resolvedConstructorOrFactoryMethod != null) {
                resolved = true;
                autowireNecessary = mbd.constructorArgumentsResolved;
            }
        }
    }
    if (resolved) {
        if (autowireNecessary) {
            return autowireConstructor(beanName, mbd, null, null);
        }
        else {
            return instantiateBean(beanName, mbd);
        }
    }

    // 6. 选择构造方法
    Constructor<?>[] ctors = determineConstructorsFromBeanPostProcessors(beanClass, beanName);
    if (ctors != null || mbd.getResolvedAutowireMode() == AUTOWIRE_CONSTRUCTOR ||
            mbd.hasConstructorArgumentValues() || !ObjectUtils.isEmpty(args)) {
        // 使用构造器自动装配
        return autowireConstructor(beanName, mbd, ctors, args);
    }

    // 7. 首选构造方法（如果有）
    ctors = mbd.getPreferredConstructors();
    if (ctors != null) {
        return autowireConstructor(beanName, mbd, ctors, null);
    }

    // 8. 使用无参构造方法
    return instantiateBean(beanName, mbd);
}

实例化策略：
1. Supplier（优先级最高）
2. 工厂方法（@Bean方法）
3. 带参数的构造方法（构造器注入）
4. 无参构造方法（默认）
```

### populateBean() - 属性填充

```java
protected void populateBean(String beanName, RootBeanDefinition mbd, @Nullable BeanWrapper bw) {
    if (bw == null) {
        if (mbd.hasPropertyValues()) {
            throw new BeanCreationException(
                mbd.getResourceDescription(), beanName, "Cannot apply property values to null instance");
        }
        else {
            return;
        }
    }

    // 1. 给InstantiationAwareBeanPostProcessor机会修改Bean状态
    if (!mbd.isSynthetic() && hasInstantiationAwareBeanPostProcessors()) {
        for (InstantiationAwareBeanPostProcessor bp : getBeanPostProcessorCache().instantiationAware) {
            if (!bp.postProcessAfterInstantiation(bw.getWrappedInstance(), beanName)) {
                return;  // 短路：跳过属性填充
            }
        }
    }

    PropertyValues pvs = (mbd.hasPropertyValues() ? mbd.getPropertyValues() : null);

    // 2. 自动装配（byName或byType）
    int resolvedAutowireMode = mbd.getResolvedAutowireMode();
    if (resolvedAutowireMode == AUTOWIRE_BY_NAME || resolvedAutowireMode == AUTOWIRE_BY_TYPE) {
        MutablePropertyValues newPvs = new MutablePropertyValues(pvs);
        // 根据名称自动装配
        if (resolvedAutowireMode == AUTOWIRE_BY_NAME) {
            autowireByName(beanName, mbd, bw, newPvs);
        }
        // 根据类型自动装配
        if (resolvedAutowireMode == AUTOWIRE_BY_TYPE) {
            autowireByType(beanName, mbd, bw, newPvs);
        }
        pvs = newPvs;
    }

    boolean hasInstAwareBpps = hasInstantiationAwareBeanPostProcessors();
    boolean needsDepCheck = (mbd.getDependencyCheck() != AbstractBeanDefinition.DEPENDENCY_CHECK_NONE);

    PropertyDescriptor[] filteredPds = null;
    if (hasInstAwareBpps) {
        if (pvs == null) {
            pvs = mbd.getPropertyValues();
        }
        // 3. 处理@Autowired、@Resource、@Value注解
        for (InstantiationAwareBeanPostProcessor bp : getBeanPostProcessorCache().instantiationAware) {
            // AutowiredAnnotationBeanPostProcessor.postProcessProperties()
            PropertyValues pvsToUse = bp.postProcessProperties(pvs, bw.getWrappedInstance(), beanName);
            if (pvsToUse == null) {
                if (filteredPds == null) {
                    filteredPds = filterPropertyDescriptorsForDependencyCheck(bw, mbd.allowCaching);
                }
                pvsToUse = bp.postProcessPropertyValues(pvs, filteredPds, bw.getWrappedInstance(), beanName);
                if (pvsToUse == null) {
                    return;
                }
            }
            pvs = pvsToUse;
        }
    }

    // 4. 依赖检查
    if (needsDepCheck) {
        if (filteredPds == null) {
            filteredPds = filterPropertyDescriptorsForDependencyCheck(bw, mbd.allowCaching);
        }
        checkDependencies(beanName, mbd, filteredPds, pvs);
    }

    // 5. 应用属性值
    if (pvs != null) {
        applyPropertyValues(beanName, mbd, bw, pvs);
    }
}

流程：
1. postProcessAfterInstantiation()      # 实例化后处理
2. 自动装配（byName、byType）
3. postProcessProperties()              # 处理@Autowired、@Resource、@Value
4. 依赖检查
5. applyPropertyValues()                # 应用属性值
```

### initializeBean() - 初始化

```java
protected Object initializeBean(String beanName, Object bean, @Nullable RootBeanDefinition mbd) {
    // 1. 调用Aware接口方法
    if (System.getSecurityManager() != null) {
        AccessController.doPrivileged((PrivilegedAction<Object>) () -> {
            invokeAwareMethods(beanName, bean);
            return null;
        }, getAccessControlContext());
    }
    else {
        invokeAwareMethods(beanName, bean);
    }

    // 2. BeanPostProcessor前置处理
    Object wrappedBean = bean;
    if (mbd == null || !mbd.isSynthetic()) {
        // @PostConstruct在这里执行
        wrappedBean = applyBeanPostProcessorsBeforeInitialization(wrappedBean, beanName);
    }

    // 3. 调用初始化方法
    try {
        invokeInitMethods(beanName, wrappedBean, mbd);
    }
    catch (Throwable ex) {
        throw new BeanCreationException(
            (mbd != null ? mbd.getResourceDescription() : null),
            beanName, "Invocation of init method failed", ex);
    }

    // 4. BeanPostProcessor后置处理
    if (mbd == null || !mbd.isSynthetic()) {
        // AOP代理在这里创建
        wrappedBean = applyBeanPostProcessorsAfterInitialization(wrappedBean, beanName);
    }

    return wrappedBean;
}

// invokeAwareMethods()
private void invokeAwareMethods(String beanName, Object bean) {
    if (bean instanceof Aware) {
        if (bean instanceof BeanNameAware) {
            ((BeanNameAware) bean).setBeanName(beanName);
        }
        if (bean instanceof BeanClassLoaderAware) {
            ClassLoader bcl = getBeanClassLoader();
            if (bcl != null) {
                ((BeanClassLoaderAware) bean).setBeanClassLoader(bcl);
            }
        }
        if (bean instanceof BeanFactoryAware) {
            ((BeanFactoryAware) bean).setBeanFactory(AbstractAutowireCapableBeanFactory.this);
        }
    }
}

// invokeInitMethods()
protected void invokeInitMethods(String beanName, Object bean, @Nullable RootBeanDefinition mbd)
        throws Throwable {

    // 1. 调用InitializingBean.afterPropertiesSet()
    boolean isInitializingBean = (bean instanceof InitializingBean);
    if (isInitializingBean && (mbd == null || !mbd.isExternallyManagedInitMethod("afterPropertiesSet"))) {
        if (System.getSecurityManager() != null) {
            try {
                AccessController.doPrivileged((PrivilegedExceptionAction<Object>) () -> {
                    ((InitializingBean) bean).afterPropertiesSet();
                    return null;
                }, getAccessControlContext());
            }
            catch (PrivilegedActionException pae) {
                throw pae.getException();
            }
        }
        else {
            ((InitializingBean) bean).afterPropertiesSet();
        }
    }

    // 2. 调用自定义init-method
    if (mbd != null && bean.getClass() != NullBean.class) {
        String initMethodName = mbd.getInitMethodName();
        if (StringUtils.hasLength(initMethodName) &&
                !(isInitializingBean && "afterPropertiesSet".equals(initMethodName)) &&
                !mbd.isExternallyManagedInitMethod(initMethodName)) {
            invokeCustomInitMethod(beanName, bean, mbd);
        }
    }
}

完整初始化流程：
1. invokeAwareMethods()                           # Aware接口回调
2. applyBeanPostProcessorsBeforeInitialization()  # @PostConstruct
3. InitializingBean.afterPropertiesSet()          # InitializingBean接口
4. invokeCustomInitMethod()                       # 自定义init-method
5. applyBeanPostProcessorsAfterInitialization()   # AOP代理创建
```

---

## AOP代理创建流程

### 入口：@EnableAspectJAutoProxy

```java
// @EnableAspectJAutoProxy注解
@Target(ElementType.TYPE)
@Retention(RetentionPolicy.RUNTIME)
@Documented
@Import(AspectJAutoProxyRegistrar.class)  # 导入AspectJAutoProxyRegistrar
public @interface EnableAspectJAutoProxy {
    boolean proxyTargetClass() default false;  // 是否强制使用CGLIB
    boolean exposeProxy() default false;       // 是否暴露代理对象到AopContext
}

// AspectJAutoProxyRegistrar
class AspectJAutoProxyRegistrar implements ImportBeanDefinitionRegistrar {

    @Override
    public void registerBeanDefinitions(
            AnnotationMetadata importingClassMetadata, BeanDefinitionRegistry registry) {

        // 注册AnnotationAwareAspectJAutoProxyCreator
        AopConfigUtils.registerAspectJAnnotationAutoProxyCreatorIfNecessary(registry);

        // 处理@EnableAspectJAutoProxy的属性
        AnnotationAttributes enableAspectJAutoProxy =
            AnnotationConfigUtils.attributesFor(importingClassMetadata, EnableAspectJAutoProxy.class);
        if (enableAspectJAutoProxy != null) {
            if (enableAspectJAutoProxy.getBoolean("proxyTargetClass")) {
                AopConfigUtils.forceAutoProxyCreatorToUseClassProxying(registry);
            }
            if (enableAspectJAutoProxy.getBoolean("exposeProxy")) {
                AopConfigUtils.forceAutoProxyCreatorToExposeProxy(registry);
            }
        }
    }
}

流程：
@EnableAspectJAutoProxy
    ↓
AspectJAutoProxyRegistrar
    ↓
注册AnnotationAwareAspectJAutoProxyCreator（BeanPostProcessor）
    ↓
在Bean初始化后，创建AOP代理
```

### AnnotationAwareAspectJAutoProxyCreator

**类层次结构**：

```
AnnotationAwareAspectJAutoProxyCreator
    ↓ 继承
AspectJAwareAdvisorAutoProxyCreator
    ↓ 继承
AbstractAdvisorAutoProxyCreator
    ↓ 继承
AbstractAutoProxyCreator
    ↓ 实现
SmartInstantiationAwareBeanPostProcessor（BeanPostProcessor子接口）

核心方法：
├─ postProcessBeforeInstantiation()     # 在实例化前创建代理（特殊情况）
├─ postProcessAfterInitialization()     # 在初始化后创建代理（常规情况）
└─ wrapIfNecessary()                    # 创建代理的核心方法
```

### postProcessAfterInitialization() - 创建代理

```java
// AbstractAutoProxyCreator.postProcessAfterInitialization()
@Override
public Object postProcessAfterInitialization(@Nullable Object bean, String beanName) {
    if (bean != null) {
        // 获取缓存key
        Object cacheKey = getCacheKey(bean.getClass(), beanName);

        // 如果不是早期代理引用，则尝试创建代理
        if (this.earlyProxyReferences.remove(cacheKey) != bean) {
            return wrapIfNecessary(bean, beanName, cacheKey);
        }
    }
    return bean;
}

// wrapIfNecessary()
protected Object wrapIfNecessary(Object bean, String beanName, Object cacheKey) {
    // 1. 如果已处理过，直接返回
    if (StringUtils.hasLength(beanName) && this.targetSourcedBeans.contains(beanName)) {
        return bean;
    }

    // 2. 如果已标记为不需要增强，直接返回
    if (Boolean.FALSE.equals(this.advisedBeans.get(cacheKey))) {
        return bean;
    }

    // 3. 如果是基础设施类或应该跳过，标记并返回
    if (isInfrastructureClass(bean.getClass()) || shouldSkip(bean.getClass(), beanName)) {
        this.advisedBeans.put(cacheKey, Boolean.FALSE);
        return bean;
    }

    // 4. 获取所有匹配的Advisor（核心）
    Object[] specificInterceptors = getAdvicesAndAdvisorsForBean(bean.getClass(), beanName, null);

    // 5. 如果有匹配的Advisor，创建代理
    if (specificInterceptors != DO_NOT_PROXY) {
        this.advisedBeans.put(cacheKey, Boolean.TRUE);

        // 创建代理对象
        Object proxy = createProxy(
            bean.getClass(), beanName, specificInterceptors, new SingletonTargetSource(bean));

        this.proxyTypes.put(cacheKey, proxy.getClass());
        return proxy;
    }

    // 6. 没有匹配的Advisor，标记为不需要增强
    this.advisedBeans.put(cacheKey, Boolean.FALSE);
    return bean;
}

流程：
1. 检查是否已处理
2. 检查是否已标记为不需要增强
3. 检查是否是基础设施类或应该跳过
4. 获取所有匹配的Advisor（getAdvicesAndAdvisorsForBean）
5. 如果有匹配的Advisor，创建代理（createProxy）
6. 否则，标记为不需要增强，返回原始Bean
```

### getAdvicesAndAdvisorsForBean() - 查找匹配的Advisor

```java
// AbstractAdvisorAutoProxyCreator.getAdvicesAndAdvisorsForBean()
@Override
@Nullable
protected Object[] getAdvicesAndAdvisorsForBean(
        Class<?> beanClass, String beanName, @Nullable TargetSource targetSource) {

    // 查找匹配的Advisor
    List<Advisor> advisors = findEligibleAdvisors(beanClass, beanName);
    if (advisors.isEmpty()) {
        return DO_NOT_PROXY;
    }
    return advisors.toArray();
}

// findEligibleAdvisors()
protected List<Advisor> findEligibleAdvisors(Class<?> beanClass, String beanName) {
    // 1. 查找所有候选Advisor
    List<Advisor> candidateAdvisors = findCandidateAdvisors();

    // 2. 过滤出匹配的Advisor
    List<Advisor> eligibleAdvisors = findAdvisorsThatCanApply(candidateAdvisors, beanClass, beanName);

    // 3. 扩展Advisor列表（添加默认的ExposeInvocationInterceptor）
    extendAdvisors(eligibleAdvisors);

    // 4. 排序Advisor
    if (!eligibleAdvisors.isEmpty()) {
        eligibleAdvisors = sortAdvisors(eligibleAdvisors);
    }

    return eligibleAdvisors;
}

// AnnotationAwareAspectJAutoProxyCreator.findCandidateAdvisors()
@Override
protected List<Advisor> findCandidateAdvisors() {
    // 1. 查找实现了Advisor接口的Bean（Spring AOP）
    List<Advisor> advisors = super.findCandidateAdvisors();

    // 2. 查找@Aspect注解的Bean，解析为Advisor（AspectJ AOP）
    if (this.aspectJAdvisorsBuilder != null) {
        advisors.addAll(this.aspectJAdvisorsBuilder.buildAspectJAdvisors());
    }

    return advisors;
}

// BeanFactoryAspectJAdvisorsBuilder.buildAspectJAdvisors()
public List<Advisor> buildAspectJAdvisors() {
    List<String> aspectNames = this.aspectBeanNames;

    // 1. 如果缓存为空，扫描所有Bean
    if (aspectNames == null) {
        synchronized (this) {
            aspectNames = this.aspectBeanNames;
            if (aspectNames == null) {
                List<Advisor> advisors = new ArrayList<>();
                aspectNames = new ArrayList<>();

                // 获取所有Bean名称
                String[] beanNames = BeanFactoryUtils.beanNamesForTypeIncludingAncestors(
                    this.beanFactory, Object.class, true, false);

                // 遍历所有Bean，找到@Aspect注解的Bean
                for (String beanName : beanNames) {
                    if (!isEligibleBean(beanName)) {
                        continue;
                    }

                    Class<?> beanType = this.beanFactory.getType(beanName, false);
                    if (beanType == null) {
                        continue;
                    }

                    // 检查是否有@Aspect注解
                    if (this.advisorFactory.isAspect(beanType)) {
                        aspectNames.add(beanName);
                        AspectMetadata amd = new AspectMetadata(beanType, beanName);

                        if (amd.getAjType().getPerClause().getKind() == PerClauseKind.SINGLETON) {
                            MetadataAwareAspectInstanceFactory factory =
                                new BeanFactoryAspectInstanceFactory(this.beanFactory, beanName);

                            // 解析Aspect类，获取所有Advisor
                            List<Advisor> classAdvisors = this.advisorFactory.getAdvisors(factory);

                            if (this.beanFactory.isSingleton(beanName)) {
                                this.advisorsCache.put(beanName, classAdvisors);
                            }
                            else {
                                this.aspectFactoryCache.put(beanName, factory);
                            }
                            advisors.addAll(classAdvisors);
                        }
                        else {
                            // 非单例Aspect
                            if (this.beanFactory.isSingleton(beanName)) {
                                throw new IllegalArgumentException("Bean with name '" + beanName +
                                    "' is a singleton, but aspect instantiation model is not singleton");
                            }
                            MetadataAwareAspectInstanceFactory factory =
                                new PrototypeAspectInstanceFactory(this.beanFactory, beanName);
                            this.aspectFactoryCache.put(beanName, factory);
                            advisors.addAll(this.advisorFactory.getAdvisors(factory));
                        }
                    }
                }
                this.aspectBeanNames = aspectNames;
                return advisors;
            }
        }
    }

    // 2. 如果缓存不为空，直接从缓存获取
    if (aspectNames.isEmpty()) {
        return Collections.emptyList();
    }
    List<Advisor> advisors = new ArrayList<>();
    for (String aspectName : aspectNames) {
        List<Advisor> cachedAdvisors = this.advisorsCache.get(aspectName);
        if (cachedAdvisors != null) {
            advisors.addAll(cachedAdvisors);
        }
        else {
            MetadataAwareAspectInstanceFactory factory = this.aspectFactoryCache.get(aspectName);
            advisors.addAll(this.advisorFactory.getAdvisors(factory));
        }
    }
    return advisors;
}

流程：
1. 查找所有候选Advisor
   ├─ 查找实现Advisor接口的Bean
   └─ 查找@Aspect注解的Bean，解析为Advisor
2. 过滤出匹配当前Bean的Advisor（通过Pointcut表达式）
3. 排序Advisor（@Order、@Priority）
4. 返回匹配的Advisor列表
```

### createProxy() - 创建代理对象

```java
// AbstractAutoProxyCreator.createProxy()
protected Object createProxy(Class<?> beanClass, @Nullable String beanName,
        @Nullable Object[] specificInterceptors, TargetSource targetSource) {

    if (this.beanFactory instanceof ConfigurableListableBeanFactory) {
        AutoProxyUtils.exposeTargetClass((ConfigurableListableBeanFactory) this.beanFactory, beanName, beanClass);
    }

    // 1. 创建ProxyFactory
    ProxyFactory proxyFactory = new ProxyFactory();
    proxyFactory.copyFrom(this);

    // 2. 判断是否使用CGLIB代理
    if (!proxyFactory.isProxyTargetClass()) {
        if (shouldProxyTargetClass(beanClass, beanName)) {
            proxyFactory.setProxyTargetClass(true);
        }
        else {
            evaluateProxyInterfaces(beanClass, proxyFactory);
        }
    }

    // 3. 构建Advisor数组
    Advisor[] advisors = buildAdvisors(beanName, specificInterceptors);
    proxyFactory.addAdvisors(advisors);
    proxyFactory.setTargetSource(targetSource);
    customizeProxyFactory(proxyFactory);

    proxyFactory.setFrozen(this.freezeProxy);
    if (advisorsPreFiltered()) {
        proxyFactory.setPreFiltered(true);
    }

    // 4. 获取代理对象
    return proxyFactory.getProxy(getProxyClassLoader());
}

// ProxyFactory.getProxy()
public Object getProxy(@Nullable ClassLoader classLoader) {
    return createAopProxy().getProxy(classLoader);
}

// createAopProxy()
protected final synchronized AopProxy createAopProxy() {
    if (!this.active) {
        activate();
    }
    return getAopProxyFactory().createAopProxy(this);
}

// DefaultAopProxyFactory.createAopProxy()
@Override
public AopProxy createAopProxy(AdvisedSupport config) throws AopConfigException {
    // 判断使用JDK动态代理还是CGLIB代理
    if (config.isOptimize() || config.isProxyTargetClass() || hasNoUserSuppliedProxyInterfaces(config)) {
        Class<?> targetClass = config.getTargetClass();
        if (targetClass == null) {
            throw new AopConfigException("TargetSource cannot determine target class: " +
                "Either an interface or a target is required for proxy creation.");
        }
        // 如果目标类是接口或已经是代理类，使用JDK动态代理
        if (targetClass.isInterface() || Proxy.isProxyClass(targetClass)) {
            return new JdkDynamicAopProxy(config);
        }
        // 否则使用CGLIB代理
        return new ObjenesisCglibAopProxy(config);
    }
    else {
        // 使用JDK动态代理
        return new JdkDynamicAopProxy(config);
    }
}

判断逻辑：
1. 如果proxyTargetClass=true → CGLIB代理
2. 如果目标类是接口 → JDK动态代理
3. 如果目标类没有接口 → CGLIB代理
4. 默认 → JDK动态代理
```

---

## @Transactional事务管理源码

### 入口：@EnableTransactionManagement

```java
// @EnableTransactionManagement注解
@Target(ElementType.TYPE)
@Retention(RetentionPolicy.RUNTIME)
@Documented
@Import(TransactionManagementConfigurationSelector.class)
public @interface EnableTransactionManagement {
    boolean proxyTargetClass() default false;  // 是否使用CGLIB代理
    AdviceMode mode() default AdviceMode.PROXY;  // 模式：PROXY或ASPECTJ
    int order() default Ordered.LOWEST_PRECEDENCE;  // 顺序
}

// TransactionManagementConfigurationSelector
public class TransactionManagementConfigurationSelector extends AdviceModeImportSelector<EnableTransactionManagement> {

    @Override
    protected String[] selectImports(AdviceMode adviceMode) {
        switch (adviceMode) {
            case PROXY:
                return new String[] {
                    AutoProxyRegistrar.class.getName(),
                    ProxyTransactionManagementConfiguration.class.getName()
                };
            case ASPECTJ:
                return new String[] {
                    determineTransactionAspectClass()
                };
            default:
                return null;
        }
    }
}

// ProxyTransactionManagementConfiguration
@Configuration
public class ProxyTransactionManagementConfiguration extends AbstractTransactionManagementConfiguration {

    // 注册TransactionInterceptor（事务拦截器）
    @Bean
    @Role(BeanDefinition.ROLE_INFRASTRUCTURE)
    public TransactionInterceptor transactionInterceptor() {
        TransactionInterceptor interceptor = new TransactionInterceptor();
        interceptor.setTransactionAttributeSource(transactionAttributeSource());
        if (this.txManager != null) {
            interceptor.setTransactionManager(this.txManager);
        }
        return interceptor;
    }

    // 注册BeanFactoryTransactionAttributeSourceAdvisor
    @Bean
    @Role(BeanDefinition.ROLE_INFRASTRUCTURE)
    public BeanFactoryTransactionAttributeSourceAdvisor transactionAdvisor() {
        BeanFactoryTransactionAttributeSourceAdvisor advisor = new BeanFactoryTransactionAttributeSourceAdvisor();
        advisor.setTransactionAttributeSource(transactionAttributeSource());
        advisor.setAdvice(transactionInterceptor());
        if (this.enableTx != null) {
            advisor.setOrder(this.enableTx.<Integer>getNumber("order"));
        }
        return advisor;
    }

    // 注册AnnotationTransactionAttributeSource
    @Bean
    @Role(BeanDefinition.ROLE_INFRASTRUCTURE)
    public TransactionAttributeSource transactionAttributeSource() {
        return new AnnotationTransactionAttributeSource();
    }
}

流程：
@EnableTransactionManagement
    ↓
TransactionManagementConfigurationSelector
    ↓
导入ProxyTransactionManagementConfiguration
    ↓
注册TransactionInterceptor（拦截器）
    ↓
注册BeanFactoryTransactionAttributeSourceAdvisor（Advisor）
    ↓
在创建Bean代理时，匹配@Transactional方法
```

### TransactionInterceptor - 事务拦截器

```java
// TransactionInterceptor
public class TransactionInterceptor extends TransactionAspectSupport implements MethodInterceptor, Serializable {

    @Override
    @Nullable
    public Object invoke(MethodInvocation invocation) throws Throwable {
        // 获取目标类
        Class<?> targetClass = (invocation.getThis() != null ? AopUtils.getTargetClass(invocation.getThis()) : null);

        // 调用invokeWithinTransaction
        return invokeWithinTransaction(invocation.getMethod(), targetClass, invocation::proceed);
    }
}

// TransactionAspectSupport.invokeWithinTransaction()
@Nullable
protected Object invokeWithinTransaction(Method method, @Nullable Class<?> targetClass,
        final InvocationCallback invocation) throws Throwable {

    // 1. 获取事务属性源
    TransactionAttributeSource tas = getTransactionAttributeSource();

    // 2. 获取事务属性（@Transactional注解信息）
    final TransactionAttribute txAttr = (tas != null ? tas.getTransactionAttribute(method, targetClass) : null);

    // 3. 获取事务管理器
    final TransactionManager tm = determineTransactionManager(txAttr);

    if (this.reactiveAdapterRegistry != null && tm instanceof ReactiveTransactionManager) {
        // 响应式事务处理（略）
        // ...
    }

    PlatformTransactionManager ptm = asPlatformTransactionManager(tm);
    final String joinpointIdentification = methodIdentification(method, targetClass, txAttr);

    if (txAttr == null || !(ptm instanceof CallbackPreferringPlatformTransactionManager)) {
        // 4. 创建事务（如果需要）
        TransactionInfo txInfo = createTransactionIfNecessary(ptm, txAttr, joinpointIdentification);

        Object retVal;
        try {
            // 5. 执行目标方法
            retVal = invocation.proceedWithInvocation();
        }
        catch (Throwable ex) {
            // 6. 异常时回滚事务
            completeTransactionAfterThrowing(txInfo, ex);
            throw ex;
        }
        finally {
            // 7. 清理事务信息
            cleanupTransactionInfo(txInfo);
        }

        if (retVal != null && vavrPresent && VavrDelegate.isVavrTry(retVal)) {
            // Vavr Try处理（略）
            // ...
        }

        // 8. 提交事务
        commitTransactionAfterReturning(txInfo);

        return retVal;
    }
    else {
        // CallbackPreferringPlatformTransactionManager处理（略）
        // ...
    }
}

流程：
1. 获取@Transactional注解信息（TransactionAttribute）
2. 获取事务管理器（PlatformTransactionManager）
3. 创建事务（createTransactionIfNecessary）
4. 执行目标方法（invocation.proceed()）
5. 如果抛出异常 → 回滚事务（completeTransactionAfterThrowing）
6. 如果正常返回 → 提交事务（commitTransactionAfterReturning）
7. 清理事务信息（cleanupTransactionInfo）
```

### createTransactionIfNecessary() - 创建事务

```java
protected TransactionInfo createTransactionIfNecessary(@Nullable PlatformTransactionManager tm,
        @Nullable TransactionAttribute txAttr, final String joinpointIdentification) {

    // 如果没有指定名称，使用方法标识作为名称
    if (txAttr != null && txAttr.getName() == null) {
        txAttr = new DelegatingTransactionAttribute(txAttr) {
            @Override
            public String getName() {
                return joinpointIdentification;
            }
        };
    }

    TransactionStatus status = null;
    if (txAttr != null) {
        if (tm != null) {
            // 获取事务状态（核心）
            status = tm.getTransaction(txAttr);
        }
        else {
            // 没有事务管理器，记录日志
        }
    }

    // 准备事务信息
    return prepareTransactionInfo(tm, txAttr, joinpointIdentification, status);
}

// AbstractPlatformTransactionManager.getTransaction()
@Override
public final TransactionStatus getTransaction(@Nullable TransactionDefinition definition)
        throws TransactionException {

    // 1. 获取当前事务对象
    Object transaction = doGetTransaction();

    // 2. 如果已存在事务，处理传播行为
    if (isExistingTransaction(transaction)) {
        return handleExistingTransaction(definition, transaction, debugEnabled);
    }

    // 3. 检查超时时间
    if (definition.getTimeout() < TransactionDefinition.TIMEOUT_DEFAULT) {
        throw new InvalidTimeoutException("Invalid transaction timeout", definition.getTimeout());
    }

    // 4. 根据传播行为处理
    if (definition.getPropagationBehavior() == TransactionDefinition.PROPAGATION_MANDATORY) {
        throw new IllegalTransactionStateException(
            "No existing transaction found for transaction marked with propagation 'mandatory'");
    }
    else if (definition.getPropagationBehavior() == TransactionDefinition.PROPAGATION_REQUIRED ||
             definition.getPropagationBehavior() == TransactionDefinition.PROPAGATION_REQUIRES_NEW ||
             definition.getPropagationBehavior() == TransactionDefinition.PROPAGATION_NESTED) {

        // 挂起当前事务（如果有）
        SuspendedResourcesHolder suspendedResources = suspend(null);

        try {
            // 开启新事务
            return startTransaction(definition, transaction, debugEnabled, suspendedResources);
        }
        catch (RuntimeException | Error ex) {
            resume(null, suspendedResources);
            throw ex;
        }
    }
    else {
        // 创建空事务
        boolean newSynchronization = (getTransactionSynchronization() == SYNCHRONIZATION_ALWAYS);
        return prepareTransactionStatus(definition, null, true, newSynchronization, debugEnabled, null);
    }
}

// startTransaction()
private TransactionStatus startTransaction(TransactionDefinition definition, Object transaction,
        boolean debugEnabled, @Nullable SuspendedResourcesHolder suspendedResources) {

    boolean newSynchronization = (getTransactionSynchronization() != SYNCHRONIZATION_NEVER);
    DefaultTransactionStatus status = newTransactionStatus(
        definition, transaction, true, newSynchronization, debugEnabled, suspendedResources);

    // 开启事务（调用DataSourceTransactionManager.doBegin()）
    doBegin(transaction, definition);

    // 准备事务同步
    prepareSynchronization(status, definition);

    return status;
}

// DataSourceTransactionManager.doBegin()
@Override
protected void doBegin(Object transaction, TransactionDefinition definition) {
    DataSourceTransactionObject txObject = (DataSourceTransactionObject) transaction;
    Connection con = null;

    try {
        if (!txObject.hasConnectionHolder() ||
            txObject.getConnectionHolder().isSynchronizedWithTransaction()) {

            // 获取数据库连接
            Connection newCon = obtainDataSource().getConnection();
            txObject.setConnectionHolder(new ConnectionHolder(newCon), true);
        }

        txObject.getConnectionHolder().setSynchronizedWithTransaction(true);
        con = txObject.getConnectionHolder().getConnection();

        // 设置只读、隔离级别
        Integer previousIsolationLevel = DataSourceUtils.prepareConnectionForTransaction(con, definition);
        txObject.setPreviousIsolationLevel(previousIsolationLevel);
        txObject.setReadOnly(definition.isReadOnly());

        // 关闭自动提交
        if (con.getAutoCommit()) {
            txObject.setMustRestoreAutoCommit(true);
            con.setAutoCommit(false);
        }

        // 准备事务连接
        prepareTransactionalConnection(con, definition);
        txObject.getConnectionHolder().setTransactionActive(true);

        // 设置超时时间
        int timeout = determineTimeout(definition);
        if (timeout != TransactionDefinition.TIMEOUT_DEFAULT) {
            txObject.getConnectionHolder().setTimeoutInSeconds(timeout);
        }

        // 绑定连接到当前线程（ThreadLocal）
        if (txObject.isNewConnectionHolder()) {
            TransactionSynchronizationManager.bindResource(obtainDataSource(), txObject.getConnectionHolder());
        }
    }
    catch (Throwable ex) {
        if (txObject.isNewConnectionHolder()) {
            DataSourceUtils.releaseConnection(con, obtainDataSource());
            txObject.setConnectionHolder(null, false);
        }
        throw new CannotCreateTransactionException("Could not open JDBC Connection for transaction", ex);
    }
}

事务创建流程：
1. 获取当前事务对象（doGetTransaction）
2. 判断是否已存在事务
   ├─ 如果已存在 → 根据传播行为处理（handleExistingTransaction）
   └─ 如果不存在 → 开启新事务（startTransaction）
3. 开启新事务（doBegin）
   ├─ 获取数据库连接
   ├─ 设置只读、隔离级别
   ├─ 关闭自动提交（setAutoCommit(false)）
   ├─ 设置超时时间
   └─ 绑定连接到当前线程（ThreadLocal）
```

### 事务传播行为处理

```java
// handleExistingTransaction()
private TransactionStatus handleExistingTransaction(
        TransactionDefinition definition, Object transaction, boolean debugEnabled)
        throws TransactionException {

    // 1. PROPAGATION_NEVER：不允许在事务中执行
    if (definition.getPropagationBehavior() == TransactionDefinition.PROPAGATION_NEVER) {
        throw new IllegalTransactionStateException(
            "Existing transaction found for transaction marked with propagation 'never'");
    }

    // 2. PROPAGATION_NOT_SUPPORTED：挂起当前事务，以非事务方式执行
    if (definition.getPropagationBehavior() == TransactionDefinition.PROPAGATION_NOT_SUPPORTED) {
        SuspendedResourcesHolder suspendedResources = suspend(transaction);
        boolean newSynchronization = (getTransactionSynchronization() == SYNCHRONIZATION_ALWAYS);
        return prepareTransactionStatus(
            definition, null, false, newSynchronization, debugEnabled, suspendedResources);
    }

    // 3. PROPAGATION_REQUIRES_NEW：挂起当前事务，创建新事务
    if (definition.getPropagationBehavior() == TransactionDefinition.PROPAGATION_REQUIRES_NEW) {
        SuspendedResourcesHolder suspendedResources = suspend(transaction);
        try {
            return startTransaction(definition, transaction, debugEnabled, suspendedResources);
        }
        catch (RuntimeException | Error beginEx) {
            resumeAfterBeginException(transaction, suspendedResources, beginEx);
            throw beginEx;
        }
    }

    // 4. PROPAGATION_NESTED：嵌套事务（Savepoint）
    if (definition.getPropagationBehavior() == TransactionDefinition.PROPAGATION_NESTED) {
        if (!isNestedTransactionAllowed()) {
            throw new NestedTransactionNotSupportedException(
                "Transaction manager does not allow nested transactions by default - " +
                "specify 'nestedTransactionAllowed' property with value 'true'");
        }
        if (useSavepointForNestedTransaction()) {
            // 使用Savepoint实现嵌套事务
            DefaultTransactionStatus status =
                prepareTransactionStatus(definition, transaction, false, false, debugEnabled, null);
            status.createAndHoldSavepoint();
            return status;
        }
        else {
            // 创建新事务（类似REQUIRES_NEW）
            return startTransaction(definition, transaction, debugEnabled, null);
        }
    }

    // 5. PROPAGATION_SUPPORTS或PROPAGATION_REQUIRED：加入当前事务
    if (definition.getPropagationBehavior() == TransactionDefinition.PROPAGATION_MANDATORY) {
        // ...
    }

    boolean newSynchronization = (getTransactionSynchronization() != SYNCHRONIZATION_NEVER);
    return prepareTransactionStatus(definition, transaction, false, newSynchronization, debugEnabled, null);
}

传播行为总结：
├─ REQUIRED（默认）：如果有事务则加入，没有则创建
├─ SUPPORTS：如果有事务则加入，没有则以非事务执行
├─ MANDATORY：必须在事务中执行，否则抛异常
├─ REQUIRES_NEW：总是创建新事务，挂起当前事务
├─ NOT_SUPPORTED：以非事务执行，挂起当前事务
├─ NEVER：不允许在事务中执行
└─ NESTED：嵌套事务（使用Savepoint）
```

---

## Spring设计模式精华

### 1. 工厂模式（Factory Pattern）

```
BeanFactory：Bean工厂，创建和管理Bean

实现类：
├─ DefaultListableBeanFactory（默认实现）
├─ XmlBeanFactory（XML配置）
└─ AnnotationConfigApplicationContext（注解配置）

使用场景：
✅ 创建复杂对象（Bean）
✅ 延迟初始化（懒加载）
✅ 统一管理对象生命周期

代码示例：
BeanFactory factory = new DefaultListableBeanFactory();
factory.registerBean("userService", UserService.class);
UserService userService = factory.getBean("userService", UserService.class);
```

### 2. 单例模式（Singleton Pattern）

```
Spring Bean默认是单例

实现：
└─ DefaultSingletonBeanRegistry
   ├─ 一级缓存：singletonObjects（成品Bean）
   ├─ 二级缓存：earlySingletonObjects（半成品Bean）
   └─ 三级缓存：singletonFactories（Bean工厂）

特点：
✅ 线程安全（ConcurrentHashMap）
✅ 懒加载支持（@Lazy）
✅ 循环依赖支持（三级缓存）

代码示例：
@Component  // 默认单例
public class UserService {
    // 只会创建一个实例
}
```

### 3. 代理模式（Proxy Pattern）

```
AOP的核心实现

两种代理方式：
├─ JDK动态代理（基于接口）
└─ CGLIB代理（基于继承）

使用场景：
✅ AOP（@Aspect）
✅ 事务管理（@Transactional）
✅ 延迟加载（@Lazy）
✅ 异步执行（@Async）

代码示例：
@Service
public class UserService {
    @Transactional  // 会创建代理对象
    public void saveUser(User user) {
        // ...
    }
}
```

### 4. 模板方法模式（Template Method Pattern）

```
AbstractApplicationContext.refresh()

模板方法：refresh()（定义流程）
钩子方法：
├─ postProcessBeanFactory()
├─ onRefresh()
└─ getInternalParentBeanFactory()

子类实现：
├─ GenericApplicationContext
├─ AbstractRefreshableApplicationContext
└─ GenericWebApplicationContext

使用场景：
✅ 定义算法骨架，具体步骤由子类实现
✅ JdbcTemplate、RestTemplate、TransactionTemplate

代码示例：
public abstract class AbstractTemplate {
    // 模板方法（final，不可覆盖）
    public final void execute() {
        before();
        doExecute();  // 抽象方法，由子类实现
        after();
    }

    protected abstract void doExecute();

    protected void before() {
        // 前置处理
    }

    protected void after() {
        // 后置处理
    }
}
```

### 5. 观察者模式（Observer Pattern）

```
ApplicationEvent事件机制

组成：
├─ ApplicationEvent（事件）
├─ ApplicationListener（监听器）
└─ ApplicationEventPublisher（发布器）

使用场景：
✅ 容器启动完成（ContextRefreshedEvent）
✅ 容器关闭（ContextClosedEvent）
✅ 自定义业务事件

代码示例：
// 定义事件
public class UserRegisterEvent extends ApplicationEvent {
    private User user;
    public UserRegisterEvent(Object source, User user) {
        super(source);
        this.user = user;
    }
}

// 发布事件
@Service
public class UserService {
    @Autowired
    private ApplicationEventPublisher publisher;

    public void register(User user) {
        saveUser(user);
        publisher.publishEvent(new UserRegisterEvent(this, user));
    }
}

// 监听事件
@Component
public class EmailListener {
    @EventListener
    public void onUserRegister(UserRegisterEvent event) {
        sendWelcomeEmail(event.getUser());
    }
}
```

### 6. 策略模式（Strategy Pattern）

```
Resource资源加载

策略接口：Resource
实现类：
├─ ClassPathResource（类路径资源）
├─ FileSystemResource（文件系统资源）
├─ UrlResource（URL资源）
└─ ServletContextResource（Servlet上下文资源）

使用场景：
✅ 资源加载（不同来源）
✅ Bean实例化策略（SimpleInstantiationStrategy、CglibSubclassingInstantiationStrategy）
✅ 负载均衡策略（Ribbon）

代码示例：
ResourceLoader loader = new DefaultResourceLoader();
Resource resource = loader.getResource("classpath:config.properties");
// 策略自动选择：ClassPathResource
```

### 7. 适配器模式（Adapter Pattern）

```
HandlerAdapter（Spring MVC）

作用：适配不同类型的Controller

实现类：
├─ RequestMappingHandlerAdapter（@RequestMapping）
├─ HttpRequestHandlerAdapter（HttpRequestHandler）
└─ SimpleControllerHandlerAdapter（Controller接口）

使用场景：
✅ 统一接口，适配不同实现
✅ AdvisorAdapter（Advisor适配器）
✅ HandlerMethodArgumentResolver（参数解析器）

代码示例：
public interface HandlerAdapter {
    boolean supports(Object handler);
    ModelAndView handle(HttpServletRequest request,
                       HttpServletResponse response,
                       Object handler) throws Exception;
}
```

---

## Spring的未来：三大技术方向

### 1. GraalVM原生编译（Spring Native）

```
传统Spring应用：
├─ 启动时间：5-30秒
├─ 内存占用：100-500MB
├─ JIT编译：运行时编译，预热时间长
└─ 打包大小：50-200MB

Spring Native（GraalVM）：
├─ 启动时间：0.1秒（快50-300倍）
├─ 内存占用：20-50MB（减少80%）
├─ AOT编译：编译时优化，无预热
└─ 打包大小：10-50MB

优势：
✅ 启动极快（适合Serverless、容器化）
✅ 内存占用小（成本降低）
✅ 打包体积小（部署快）

限制：
❌ 编译时间长（5-10分钟）
❌ 反射、动态代理需要额外配置
❌ 不支持某些特性（如CGLIB）

使用示例：
<dependency>
    <groupId>org.springframework.experimental</groupId>
    <artifactId>spring-native</artifactId>
    <version>0.12.1</version>
</dependency>

// 编译为原生镜像
mvn spring-boot:build-image
```

### 2. 响应式编程（Spring WebFlux）

```
传统Spring MVC（阻塞式）：
请求1 → 线程1 → 等待数据库响应（阻塞）→ 返回
请求2 → 线程2 → 等待数据库响应（阻塞）→ 返回
├─ 每个请求占用一个线程
├─ 线程数量有限（通常200-500）
└─ 高并发时线程耗尽

Spring WebFlux（非阻塞式）：
请求1 → 线程1 → 发起数据库请求（不阻塞）→ 处理其他请求
请求2 → 线程1 → 发起数据库请求（不阻塞）→ 处理其他请求
├─ 一个线程处理多个请求
├─ 线程数量少（通常CPU核心数）
└─ 高并发性能好

使用场景：
✅ 高并发场景（百万级QPS）
✅ I/O密集型应用（数据库、网络请求）
✅ 微服务间通信

代码示例：
@RestController
public class UserController {

    @Autowired
    private UserRepository userRepository;

    // 响应式API（返回Mono/Flux）
    @GetMapping("/users/{id}")
    public Mono<User> getUser(@PathVariable Long id) {
        return userRepository.findById(id);
    }

    @GetMapping("/users")
    public Flux<User> listUsers() {
        return userRepository.findAll();
    }
}

// 响应式Repository
public interface UserRepository extends ReactiveCrudRepository<User, Long> {
    Flux<User> findByName(String name);
}
```

### 3. 云原生架构（Spring Cloud Kubernetes）

```
传统微服务：
├─ 服务注册：Nacos、Eureka
├─ 配置中心：Nacos Config、Apollo
├─ 负载均衡：Ribbon、LoadBalancer
├─ 熔断降级：Sentinel、Hystrix
└─ 需要额外组件，增加复杂度

Kubernetes原生：
├─ 服务发现：Kubernetes Service
├─ 配置管理：ConfigMap、Secret
├─ 负载均衡：Kubernetes Service
├─ 健康检查：Liveness/Readiness Probe
└─ Kubernetes内置，无额外组件

Spring Cloud Kubernetes：
├─ 自动服务发现（从Kubernetes API）
├─ 自动配置管理（从ConfigMap/Secret）
├─ Kubernetes原生特性集成
└─ 简化微服务部署

代码示例：
<dependency>
    <groupId>org.springframework.cloud</groupId>
    <artifactId>spring-cloud-starter-kubernetes-all</artifactId>
</dependency>

// application.yml（从ConfigMap读取配置）
spring:
  cloud:
    kubernetes:
      config:
        enabled: true
        name: my-app-config
      secrets:
        enabled: true
        name: my-app-secret

// 服务发现（自动从Kubernetes Service）
@FeignClient(name = "user-service")
public interface UserServiceClient {
    @GetMapping("/users/{id}")
    User getUser(@PathVariable Long id);
}
```

---

## 总结：从使用者到贡献者

### 学习路径总结

```
L1（初级）：会用Spring
├─ 掌握基本注解（@Component、@Autowired、@Transactional）
├─ 能搭建Spring Boot应用
├─ 理解IoC和AOP概念
└─ 能解决常见问题

L2（中级）：理解原理
├─ 理解IoC容器启动流程
├─ 理解AOP代理创建流程
├─ 理解事务管理机制
├─ 能阅读关键源码
└─ 能优化性能

L3（高级）：源码级理解
├─ 深入理解refresh()方法
├─ 深入理解Bean生命周期
├─ 深入理解三级缓存
├─ 能贡献Spring源码
└─ 能设计框架

学习建议：
✅ 从使用入手，遇到问题深入研究
✅ 带着问题阅读源码（不要盲目阅读）
✅ Debug + 日志，理解执行流程
✅ 画图总结，建立系统认知
❌ 避免：一开始就看源码（容易迷失）
```

### 核心知识点回顾

```
1. IoC容器启动流程（refresh方法12个步骤）
   ├─ prepareRefresh()
   ├─ obtainFreshBeanFactory()
   ├─ prepareBeanFactory()
   ├─ invokeBeanFactoryPostProcessors()  ← 处理@Configuration、@Bean
   ├─ registerBeanPostProcessors()
   └─ finishBeanFactoryInitialization()  ← 创建所有单例Bean

2. Bean创建流程（doCreateBean）
   ├─ createBeanInstance()      # 实例化
   ├─ populateBean()            # 属性填充
   └─ initializeBean()          # 初始化
      ├─ Aware接口回调
      ├─ @PostConstruct
      ├─ InitializingBean
      └─ AOP代理创建

3. AOP代理创建流程
   ├─ postProcessAfterInitialization()
   ├─ wrapIfNecessary()
   ├─ getAdvicesAndAdvisorsForBean()
   └─ createProxy()

4. 事务管理流程
   ├─ TransactionInterceptor.invoke()
   ├─ createTransactionIfNecessary()
   ├─ invocation.proceed()
   └─ commitTransactionAfterReturning()

5. Spring设计模式
   ├─ 工厂模式（BeanFactory）
   ├─ 单例模式（DefaultSingletonBeanRegistry）
   ├─ 代理模式（AOP）
   ├─ 模板方法模式（AbstractApplicationContext）
   ├─ 观察者模式（ApplicationEvent）
   ├─ 策略模式（Resource）
   └─ 适配器模式（HandlerAdapter）
```

### 给从业者的建议

```
如何阅读Spring源码：
1. 从接口开始（理解设计意图）
2. 找到入口方法（如refresh()）
3. 绘制调用链路图
4. Debug跟踪执行流程
5. 总结核心逻辑

如何向Spring贡献代码：
1. 阅读贡献指南（CONTRIBUTING.md）
2. 从简单问题入手（good first issue）
3. 提交高质量PR（测试、文档）
4. 参与社区讨论（GitHub Issues）
5. 持续学习和贡献

技术提升路径：
1. 深入一个框架（Spring）
2. 横向扩展（Dubbo、MyBatis）
3. 研究设计模式
4. 学习架构设计
5. 尝试自己造轮子
```

---

## 结语

通过深入阅读Spring源码，我们不仅能理解Spring的设计思想，更能学习到优秀的编程范式和设计模式。

**核心收获**：
1. **IoC容器启动流程**：refresh()方法的12个步骤，Bean的创建流程
2. **AOP代理创建**：AnnotationAwareAspectJAutoProxyCreator的工作原理
3. **事务管理机制**：TransactionInterceptor的拦截流程
4. **设计模式精华**：工厂、单例、代理、模板、观察者等7种模式
5. **Spring的未来**：GraalVM、响应式编程、云原生

**系列总结**：
- [第1篇](/java-ecosystem/posts/2025-11-03-why-we-need-spring/)：理解Spring存在的意义
- [第2篇](/java-ecosystem/posts/2025-11-03-ioc-container-evolution/)：掌握IoC容器的演进
- [第3篇](/java-ecosystem/posts/2025-11-03-aop-aspect-oriented-programming/)：理解AOP的实现原理
- [第4篇](/java-ecosystem/posts/2025-11-03-spring-boot-convention-over-configuration/)：掌握Spring Boot自动配置
- [第5篇](/java-ecosystem/posts/2025-11-03-spring-cloud-microservices/)：理解微服务架构
- **第6篇**（本文）：深入Spring源码，成为Spring专家

**最后的话**：

阅读源码是一个漫长的过程，不要试图一次性读懂所有代码。从一个功能点入手，逐步深入，持之以恒，你终将成为Spring专家。

感谢你阅读完《Spring框架第一性原理》系列的所有文章！希望这个系列能帮助你建立对Spring的系统认知，从使用者成长为贡献者。

---

> 🤔 **思考题**：
> 1. 你在使用Spring时遇到过哪些问题？是如何解决的？
> 2. 阅读Spring源码对你的编程能力有哪些帮助？
> 3. 你觉得Spring未来会如何发展？
>
> 欢迎在评论区分享你的思考和经验！

> 📚 **推荐资源**：
> - [Spring Framework源码](https://github.com/spring-projects/spring-framework)
> - [Spring官方文档](https://spring.io/projects/spring-framework)
> - [Spring Native文档](https://docs.spring.io/spring-native/docs/current/reference/htmlsingle/)
> - 《Spring源码深度解析》- 郝佳
> - 《Spring揭秘》- 王福强

---

**🎉 系列完结！感谢阅读！**

如果这个系列对你有帮助，欢迎：
- ⭐ 收藏本系列文章
- 📢 分享给更多需要的人
- 💬 在评论区交流你的学习心得
