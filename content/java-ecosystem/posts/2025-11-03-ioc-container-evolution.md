---
title: IoC容器深度解析：从手动new到自动装配的演进
date: 2025-11-03T10:00:00+08:00
draft: false
tags:
  - Spring
  - IoC
  - 依赖注入
  - 容器
  - 第一性原理
categories:
  - 技术
description: 从第一性原理出发，通过5个渐进式场景深度剖析IoC容器的演进逻辑。手写200行简化版IoC容器，深入Spring容器核心设计，揭秘Bean生命周期和循环依赖的三级缓存解决方案。
series:
  - Spring第一性原理
weight: 2
stage: 2
stageTitle: "核心框架深度篇"
---

## 引子：一个UserService的五种创建方式

假设你要创建一个UserService，它依赖UserRepository，而UserRepository又依赖DataSource。

这个看似简单的三层依赖，在不同的阶段有完全不同的创建方式：

```java
// 方式1：手动new（最原始）
UserService userService = new UserService(
    new UserRepository(
        new DataSource("jdbc:mysql://localhost:3306/db", "root", "123456")
    )
);

// 方式2：工厂模式（稍好一点）
UserService userService = UserServiceFactory.create();

// 方式3：依赖注入（手动装配）
UserService userService = new UserService();
userService.setUserRepository(new UserRepository());

// 方式4：IoC容器（自动装配）
ApplicationContext context = new AnnotationConfigApplicationContext(AppConfig.class);
UserService userService = context.getBean(UserService.class);

// 方式5：Spring Boot（零配置）
@Autowired
private UserService userService;  // 自动注入
```

**从方式1到方式5，到底发生了什么？**

今天我们将通过**5个渐进式场景**，深度剖析IoC容器的演进逻辑，并亲手实现一个200行的简化版IoC容器。

---

## 一、场景0：手动new的噩梦（无容器）

### 1.1 三层依赖的手动创建

```java
/**
 * 场景0：完全手动管理依赖
 * 问题：硬编码、强耦合、难以测试
 */
public class ManualDependencyDemo {

    public static void main(String[] args) {
        // 第1层：创建DataSource
        DataSource dataSource = new DataSource();
        dataSource.setUrl("jdbc:mysql://localhost:3306/mydb");
        dataSource.setUsername("root");
        dataSource.setPassword("123456");
        dataSource.setMaxPoolSize(10);

        // 第2层：创建UserRepository（依赖DataSource）
        UserRepository userRepository = new UserRepository();
        userRepository.setDataSource(dataSource);

        // 第3层：创建UserService（依赖UserRepository）
        UserService userService = new UserService();
        userService.setUserRepository(userRepository);

        // 使用
        User user = userService.getUser(1L);
        System.out.println(user);
    }
}

/**
 * DataSource - 数据源
 */
class DataSource {
    private String url;
    private String username;
    private String password;
    private int maxPoolSize;

    // getter/setter省略
}

/**
 * UserRepository - 数据访问层
 */
class UserRepository {
    private DataSource dataSource;

    public void setDataSource(DataSource dataSource) {
        this.dataSource = dataSource;
    }

    public User findById(Long id) {
        // 使用dataSource查询数据库
        System.out.println("查询数据库，dataSource: " + dataSource);
        return new User(id, "张三");
    }
}

/**
 * UserService - 业务逻辑层
 */
class UserService {
    private UserRepository userRepository;

    public void setUserRepository(UserRepository userRepository) {
        this.userRepository = userRepository;
    }

    public User getUser(Long id) {
        return userRepository.findById(id);
    }
}

/**
 * User - 实体类
 */
class User {
    private Long id;
    private String name;

    public User(Long id, String name) {
        this.id = id;
        this.name = name;
    }

    @Override
    public String toString() {
        return "User{id=" + id + ", name='" + name + "'}";
    }
}
```

### 1.2 核心问题分析

**问题清单**：

| 问题 | 具体表现 | 影响 |
|------|---------|------|
| **硬编码** | 配置写死在代码里 | 环境切换困难 |
| **强耦合** | 直接new具体类 | 无法替换实现 |
| **重复创建** | 每次使用都要new | DataSource应该是单例 |
| **依赖层级深** | 3层依赖手动创建 | 层级越深越难维护 |
| **难以测试** | 无法注入mock对象 | 单元测试困难 |
| **顺序依赖** | 必须先创建DataSource | 容易出错 |

**代码统计**：
- 创建对象的代码：**15行**
- 配置代码：**7行**
- 真正的业务代码：**2行**

> **80%的代码都在管理依赖，只有20%是业务逻辑**

---

## 二、场景1：引入简单工厂（工厂模式）

### 2.1 工厂模式实现

```java
/**
 * 场景1：使用工厂模式创建对象
 * 改进：解耦对象创建，但依赖关系仍需手动管理
 */
public class FactoryPatternDemo {

    public static void main(String[] args) {
        // 使用工厂创建对象
        UserService userService = BeanFactory.getUserService();

        User user = userService.getUser(1L);
        System.out.println(user);
    }
}

/**
 * 简单工厂 - 统一管理对象创建
 */
class BeanFactory {

    // 单例：DataSource应该是单例的
    private static DataSource dataSource;
    private static UserRepository userRepository;
    private static UserService userService;

    /**
     * 获取DataSource（单例）
     */
    public static DataSource getDataSource() {
        if (dataSource == null) {
            synchronized (BeanFactory.class) {
                if (dataSource == null) {
                    dataSource = new DataSource();
                    dataSource.setUrl("jdbc:mysql://localhost:3306/mydb");
                    dataSource.setUsername("root");
                    dataSource.setPassword("123456");
                    dataSource.setMaxPoolSize(10);
                }
            }
        }
        return dataSource;
    }

    /**
     * 获取UserRepository（单例）
     */
    public static UserRepository getUserRepository() {
        if (userRepository == null) {
            synchronized (BeanFactory.class) {
                if (userRepository == null) {
                    userRepository = new UserRepository();
                    userRepository.setDataSource(getDataSource());  // 注入依赖
                }
            }
        }
        return userRepository;
    }

    /**
     * 获取UserService（单例）
     */
    public static UserService getUserService() {
        if (userService == null) {
            synchronized (BeanFactory.class) {
                if (userService == null) {
                    userService = new UserService();
                    userService.setUserRepository(getUserRepository());  // 注入依赖
                }
            }
        }
        return userService;
    }
}
```

### 2.2 工厂模式的改进与问题

**改进**：
- ✅ 对象创建集中管理
- ✅ 实现了单例模式
- ✅ 依赖关系在工厂内部管理

**问题**：
- ❌ 每个类都要写一个工厂方法
- ❌ 依赖关系硬编码在工厂里
- ❌ 无法处理循环依赖
- ❌ 配置仍然硬编码

**对比场景0**：

| 维度 | 场景0（手动new） | 场景1（工厂） | 改进 |
|------|----------------|-------------|------|
| 对象创建 | 每次都new | 工厂统一创建 | ✅ |
| 单例管理 | 难以保证 | 双重检查锁 | ✅ |
| 依赖注入 | 手动注入 | 工厂内注入 | ✅ |
| 配置方式 | 硬编码 | 仍然硬编码 | ❌ |
| 扩展性 | 差 | 稍好 | 🔶 |

---

## 三、场景2：引入依赖注入（Setter注入）

### 3.1 依赖注入的基本实现

```java
/**
 * 场景2：依赖注入 - 通过配置文件或代码配置依赖关系
 * 改进：依赖关系外部化，对象创建与依赖注入分离
 */
public class DependencyInjectionDemo {

    public static void main(String[] args) {
        // 1. 创建所有对象（不注入依赖）
        DataSource dataSource = new DataSource();
        UserRepository userRepository = new UserRepository();
        UserService userService = new UserService();

        // 2. 配置对象（注入依赖）
        configureBeans(dataSource, userRepository, userService);

        // 3. 使用
        User user = userService.getUser(1L);
        System.out.println(user);
    }

    /**
     * 配置Bean的依赖关系
     * 这部分逻辑可以从XML或注解中读取
     */
    private static void configureBeans(
            DataSource dataSource,
            UserRepository userRepository,
            UserService userService) {

        // 配置DataSource
        dataSource.setUrl("jdbc:mysql://localhost:3306/mydb");
        dataSource.setUsername("root");
        dataSource.setPassword("123456");
        dataSource.setMaxPoolSize(10);

        // 注入依赖：UserRepository → DataSource
        userRepository.setDataSource(dataSource);

        // 注入依赖：UserService → UserRepository
        userService.setUserRepository(userRepository);
    }
}
```

### 3.2 进化：配置文件驱动

```xml
<!-- beans.xml - 依赖关系配置文件 -->
<beans>
    <!-- DataSource配置 -->
    <bean id="dataSource" class="com.example.DataSource">
        <property name="url" value="jdbc:mysql://localhost:3306/mydb"/>
        <property name="username" value="root"/>
        <property name="password" value="123456"/>
        <property name="maxPoolSize" value="10"/>
    </bean>

    <!-- UserRepository配置 -->
    <bean id="userRepository" class="com.example.UserRepository">
        <property name="dataSource" ref="dataSource"/>
    </bean>

    <!-- UserService配置 -->
    <bean id="userService" class="com.example.UserService">
        <property name="userRepository" ref="userRepository"/>
    </bean>
</beans>
```

```java
/**
 * 简化版XML配置解析器
 */
public class SimpleXmlBeanFactory {

    private Map<String, Object> beans = new HashMap<>();
    private Map<String, BeanDefinition> beanDefinitions = new HashMap<>();

    /**
     * 从XML加载Bean定义
     */
    public void loadBeans(String xmlPath) {
        // 1. 解析XML，提取Bean定义
        // 2. 创建所有Bean实例
        // 3. 注入依赖
    }

    /**
     * 获取Bean
     */
    public Object getBean(String beanName) {
        return beans.get(beanName);
    }
}

/**
 * Bean定义
 */
class BeanDefinition {
    private String id;
    private String className;
    private Map<String, Object> properties;  // 属性值
    private Map<String, String> references;  // 依赖引用

    // getter/setter省略
}
```

### 3.3 核心改进

**改进**：
- ✅ 对象创建与依赖注入分离
- ✅ 依赖关系外部化（XML配置）
- ✅ 配置与代码分离

**问题**：
- ❌ XML配置繁琐
- ❌ 仍需手动管理对象生命周期
- ❌ 没有自动扫描和装配

---

## 四、场景3：引入IoC容器（核心跃迁）

### 4.1 手写简化版IoC容器

现在我们来实现一个**200行**的简化版IoC容器，理解Spring IoC的核心原理。

```java
/**
 * 简化版IoC容器实现
 * 核心功能：
 * 1. Bean定义注册
 * 2. Bean实例化
 * 3. 依赖注入（Setter注入）
 * 4. 单例管理
 */
public class SimpleIoCContainer {

    // Bean定义存储
    private Map<String, BeanDefinition> beanDefinitions = new ConcurrentHashMap<>();

    // Bean实例缓存（单例）
    private Map<String, Object> singletonObjects = new ConcurrentHashMap<>();

    /**
     * 注册Bean定义
     */
    public void registerBeanDefinition(String beanName, BeanDefinition beanDefinition) {
        beanDefinitions.put(beanName, beanDefinition);
    }

    /**
     * 获取Bean（核心方法）
     */
    public Object getBean(String beanName) {
        // 1. 先从单例缓存中获取
        Object singleton = singletonObjects.get(beanName);
        if (singleton != null) {
            return singleton;
        }

        // 2. 获取Bean定义
        BeanDefinition beanDefinition = beanDefinitions.get(beanName);
        if (beanDefinition == null) {
            throw new RuntimeException("No bean named '" + beanName + "' is defined");
        }

        // 3. 创建Bean实例
        Object bean = createBean(beanDefinition);

        // 4. 缓存单例
        if (beanDefinition.isSingleton()) {
            singletonObjects.put(beanName, bean);
        }

        return bean;
    }

    /**
     * 创建Bean实例
     */
    private Object createBean(BeanDefinition beanDefinition) {
        try {
            // 1. 实例化：调用无参构造函数
            Class<?> beanClass = Class.forName(beanDefinition.getClassName());
            Object bean = beanClass.getDeclaredConstructor().newInstance();

            // 2. 属性注入：Setter注入
            injectProperties(bean, beanDefinition);

            return bean;

        } catch (Exception e) {
            throw new RuntimeException("Failed to create bean: " + beanDefinition.getBeanName(), e);
        }
    }

    /**
     * 属性注入（Setter注入）
     */
    private void injectProperties(Object bean, BeanDefinition beanDefinition) throws Exception {
        Map<String, Object> properties = beanDefinition.getProperties();
        if (properties == null || properties.isEmpty()) {
            return;
        }

        Class<?> beanClass = bean.getClass();

        for (Map.Entry<String, Object> entry : properties.entrySet()) {
            String propertyName = entry.getKey();
            Object propertyValue = entry.getValue();

            // 如果属性值是引用（BeanReference），则递归获取Bean
            if (propertyValue instanceof BeanReference) {
                BeanReference ref = (BeanReference) propertyValue;
                propertyValue = getBean(ref.getBeanName());
            }

            // 调用Setter方法注入
            String setterName = "set" + propertyName.substring(0, 1).toUpperCase()
                              + propertyName.substring(1);
            Method setter = beanClass.getMethod(setterName, propertyValue.getClass());
            setter.invoke(bean, propertyValue);
        }
    }

    /**
     * Bean定义
     */
    public static class BeanDefinition {
        private String beanName;
        private String className;
        private boolean singleton = true;  // 默认单例
        private Map<String, Object> properties = new HashMap<>();

        public BeanDefinition(String beanName, String className) {
            this.beanName = beanName;
            this.className = className;
        }

        public void addProperty(String name, Object value) {
            properties.put(name, value);
        }

        // getter/setter省略
        public String getBeanName() { return beanName; }
        public String getClassName() { return className; }
        public boolean isSingleton() { return singleton; }
        public Map<String, Object> getProperties() { return properties; }
    }

    /**
     * Bean引用（用于依赖注入）
     */
    public static class BeanReference {
        private String beanName;

        public BeanReference(String beanName) {
            this.beanName = beanName;
        }

        public String getBeanName() { return beanName; }
    }
}
```

### 4.2 使用简化版IoC容器

```java
/**
 * 场景3：使用自己实现的IoC容器
 */
public class SimpleIoCContainerDemo {

    public static void main(String[] args) {
        // 1. 创建容器
        SimpleIoCContainer container = new SimpleIoCContainer();

        // 2. 注册Bean定义
        registerBeans(container);

        // 3. 获取Bean（自动创建和注入依赖）
        UserService userService = (UserService) container.getBean("userService");

        // 4. 使用
        User user = userService.getUser(1L);
        System.out.println(user);

        // 5. 验证单例
        UserService userService2 = (UserService) container.getBean("userService");
        System.out.println("是否单例: " + (userService == userService2));  // true
    }

    /**
     * 注册Bean定义（模拟XML配置）
     */
    private static void registerBeans(SimpleIoCContainer container) {
        // 1. 注册DataSource
        SimpleIoCContainer.BeanDefinition dataSourceDef =
            new SimpleIoCContainer.BeanDefinition("dataSource", "com.example.DataSource");
        dataSourceDef.addProperty("url", "jdbc:mysql://localhost:3306/mydb");
        dataSourceDef.addProperty("username", "root");
        dataSourceDef.addProperty("password", "123456");
        container.registerBeanDefinition("dataSource", dataSourceDef);

        // 2. 注册UserRepository
        SimpleIoCContainer.BeanDefinition userRepositoryDef =
            new SimpleIoCContainer.BeanDefinition("userRepository", "com.example.UserRepository");
        userRepositoryDef.addProperty("dataSource",
            new SimpleIoCContainer.BeanReference("dataSource"));  // 引用dataSource
        container.registerBeanDefinition("userRepository", userRepositoryDef);

        // 3. 注册UserService
        SimpleIoCContainer.BeanDefinition userServiceDef =
            new SimpleIoCContainer.BeanDefinition("userService", "com.example.UserService");
        userServiceDef.addProperty("userRepository",
            new SimpleIoCContainer.BeanReference("userRepository"));  // 引用userRepository
        container.registerBeanDefinition("userService", userServiceDef);
    }
}
```

### 4.3 IoC容器的核心价值

**对比场景0-2**：

| 维度 | 场景0<br>（手动new） | 场景1<br>（工厂） | 场景2<br>（DI） | 场景3<br>（IoC容器） |
|------|---------------------|----------------|---------------|-------------------|
| 对象创建 | 手动new | 工厂创建 | 手动new | **容器自动创建** |
| 依赖注入 | 手动注入 | 工厂注入 | 手动注入 | **容器自动注入** |
| 单例管理 | 难以保证 | 双重检查锁 | 难以保证 | **容器管理** |
| 配置方式 | 硬编码 | 硬编码 | XML配置 | **XML/注解配置** |
| 生命周期 | 手动管理 | 手动管理 | 手动管理 | **容器管理** |
| 循环依赖 | 无法处理 | 无法处理 | 无法处理 | **可处理（三级缓存）** |

**核心价值**：

> IoC容器是一个**对象生命周期管理器**，负责对象的创建、依赖注入、生命周期管理

---

## 五、场景4：引入自动装配（注解驱动）

### 5.1 基于注解的Bean定义

```java
/**
 * 场景4：使用注解自动扫描和装配
 * 改进：零配置，注解驱动
 */

/**
 * @Component注解 - 标记为Bean
 */
@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.TYPE)
@interface Component {
    String value() default "";
}

/**
 * @Autowired注解 - 自动注入
 */
@Retention(RetentionPolicy.RUNTIME)
@Target({ElementType.FIELD, ElementType.METHOD})
@interface Autowired {
}

/**
 * DataSource - 使用注解
 */
@Component("dataSource")
class DataSource {
    private String url = "jdbc:mysql://localhost:3306/mydb";
    private String username = "root";
    private String password = "123456";

    // getter/setter省略
}

/**
 * UserRepository - 使用注解
 */
@Component("userRepository")
class UserRepository {

    @Autowired
    private DataSource dataSource;  // 自动注入

    public User findById(Long id) {
        System.out.println("查询数据库，dataSource: " + dataSource);
        return new User(id, "张三");
    }
}

/**
 * UserService - 使用注解
 */
@Component("userService")
class UserService {

    @Autowired
    private UserRepository userRepository;  // 自动注入

    public User getUser(Long id) {
        return userRepository.findById(id);
    }
}
```

### 5.2 注解驱动的IoC容器

```java
/**
 * 注解驱动的IoC容器
 * 核心功能：
 * 1. 扫描@Component注解
 * 2. 自动注册Bean定义
 * 3. 自动注入@Autowired字段
 */
public class AnnotationIoCContainer {

    private Map<String, Object> beans = new ConcurrentHashMap<>();

    /**
     * 扫描指定包下的所有@Component类
     */
    public void scan(String basePackage) throws Exception {
        // 1. 扫描包下的所有类
        List<Class<?>> classes = scanClasses(basePackage);

        // 2. 筛选出带@Component注解的类
        for (Class<?> clazz : classes) {
            if (clazz.isAnnotationPresent(Component.class)) {
                // 3. 创建Bean实例
                Object bean = clazz.getDeclaredConstructor().newInstance();

                // 4. 获取Bean名称
                Component component = clazz.getAnnotation(Component.class);
                String beanName = component.value();
                if (beanName.isEmpty()) {
                    beanName = clazz.getSimpleName();
                    beanName = beanName.substring(0, 1).toLowerCase() + beanName.substring(1);
                }

                // 5. 缓存Bean
                beans.put(beanName, bean);
            }
        }

        // 6. 注入依赖
        for (Object bean : beans.values()) {
            injectDependencies(bean);
        }
    }

    /**
     * 注入@Autowired字段
     */
    private void injectDependencies(Object bean) throws Exception {
        Class<?> clazz = bean.getClass();

        // 遍历所有字段
        for (Field field : clazz.getDeclaredFields()) {
            if (field.isAnnotationPresent(Autowired.class)) {
                // 根据字段类型查找Bean
                Object dependency = getBeanByType(field.getType());
                if (dependency == null) {
                    throw new RuntimeException("No bean found for type: " + field.getType());
                }

                // 注入字段
                field.setAccessible(true);
                field.set(bean, dependency);
            }
        }
    }

    /**
     * 根据类型获取Bean
     */
    private Object getBeanByType(Class<?> type) {
        for (Object bean : beans.values()) {
            if (type.isAssignableFrom(bean.getClass())) {
                return bean;
            }
        }
        return null;
    }

    /**
     * 获取Bean
     */
    public Object getBean(String beanName) {
        return beans.get(beanName);
    }

    /**
     * 扫描包下的所有类（简化实现）
     */
    private List<Class<?>> scanClasses(String basePackage) {
        // 实际实现需要扫描classpath
        // 这里简化处理，直接返回预定义的类列表
        return Arrays.asList(DataSource.class, UserRepository.class, UserService.class);
    }
}
```

### 5.3 使用注解驱动容器

```java
/**
 * 场景4：使用注解驱动的IoC容器
 */
public class AnnotationIoCContainerDemo {

    public static void main(String[] args) throws Exception {
        // 1. 创建容器
        AnnotationIoCContainer container = new AnnotationIoCContainer();

        // 2. 扫描包（自动注册Bean和注入依赖）
        container.scan("com.example");

        // 3. 获取Bean
        UserService userService = (UserService) container.getBean("userService");

        // 4. 使用
        User user = userService.getUser(1L);
        System.out.println(user);
    }
}
```

### 5.4 自动装配的价值

**对比场景3**：

| 维度 | 场景3（XML配置） | 场景4（注解驱动） | 改进 |
|------|----------------|-----------------|------|
| Bean定义 | XML配置 | @Component注解 | 减少90%配置 |
| 依赖注入 | XML ref | @Autowired注解 | 零配置 |
| 包扫描 | 手动注册 | 自动扫描 | 自动化 |
| 开发效率 | 低 | 高 | 5倍提升 |

**代码量对比**：

```
场景0（手动new）：
  业务代码：2行
  框架代码：15行
  占比：88%框架代码

场景4（注解驱动）：
  业务代码：2行
  框架代码：2行（@Component + @Autowired）
  占比：50%框架代码

减少：75%框架代码
```

---

## 六、Spring IoC容器核心设计

### 6.1 核心接口体系

```
BeanFactory（根接口）
├── HierarchicalBeanFactory（层次化）
│   └── ConfigurableBeanFactory（可配置）
│
└── ListableBeanFactory（可列举）
    └── ApplicationContext（应用上下文）
        ├── ConfigurableApplicationContext（可配置）
        ├── WebApplicationContext（Web环境）
        └── AnnotationConfigApplicationContext（注解配置）
```

**核心接口说明**：

| 接口 | 职责 | 核心方法 |
|------|-----|---------|
| **BeanFactory** | Bean工厂根接口 | `getBean(String name)`<br>`getBean(Class<T> type)` |
| **ApplicationContext** | 应用上下文 | 继承BeanFactory<br>+ 事件发布<br>+ 资源加载<br>+ 国际化 |
| **BeanDefinition** | Bean定义 | 存储Bean的元数据<br>（类名、作用域、属性等） |
| **BeanPostProcessor** | Bean后置处理器 | `postProcessBeforeInitialization`<br>`postProcessAfterInitialization` |

### 6.2 Spring IoC容器启动流程

```java
/**
 * Spring IoC容器启动流程（简化）
 */
public class ApplicationContext {

    private Map<String, BeanDefinition> beanDefinitions = new HashMap<>();
    private Map<String, Object> singletonObjects = new ConcurrentHashMap<>();
    private List<BeanPostProcessor> beanPostProcessors = new ArrayList<>();

    /**
     * 容器启动流程
     */
    public void refresh() {
        // 1. 准备BeanFactory
        prepareBeanFactory();

        // 2. 调用BeanFactoryPostProcessor
        invokeBeanFactoryPostProcessors();

        // 3. 注册BeanPostProcessor
        registerBeanPostProcessors();

        // 4. 初始化消息源（国际化）
        initMessageSource();

        // 5. 初始化事件广播器
        initApplicationEventMulticaster();

        // 6. 刷新子类特殊Bean（模板方法）
        onRefresh();

        // 7. 注册监听器
        registerListeners();

        // 8. 实例化所有单例Bean（核心）
        finishBeanFactoryInitialization();

        // 9. 完成刷新，发布事件
        finishRefresh();
    }

    /**
     * 实例化所有单例Bean
     */
    private void finishBeanFactoryInitialization() {
        // 遍历所有Bean定义
        for (String beanName : beanDefinitions.keySet()) {
            BeanDefinition beanDefinition = beanDefinitions.get(beanName);

            // 如果是单例且非懒加载，立即实例化
            if (beanDefinition.isSingleton() && !beanDefinition.isLazyInit()) {
                getBean(beanName);
            }
        }
    }

    /**
     * 获取Bean（核心方法）
     */
    public Object getBean(String beanName) {
        // 1. 从单例缓存获取
        Object singleton = singletonObjects.get(beanName);
        if (singleton != null) {
            return singleton;
        }

        // 2. 创建Bean
        Object bean = createBean(beanName);

        // 3. 缓存单例
        singletonObjects.put(beanName, bean);

        return bean;
    }

    /**
     * 创建Bean（完整流程）
     */
    private Object createBean(String beanName) {
        BeanDefinition beanDefinition = beanDefinitions.get(beanName);

        // 1. 实例化Bean
        Object bean = instantiateBean(beanDefinition);

        // 2. 属性填充（依赖注入）
        populateBean(bean, beanDefinition);

        // 3. 初始化Bean
        bean = initializeBean(beanName, bean, beanDefinition);

        return bean;
    }

    /**
     * 初始化Bean
     */
    private Object initializeBean(String beanName, Object bean, BeanDefinition beanDefinition) {
        // 1. 调用Aware接口
        invokeAwareMethods(beanName, bean);

        // 2. 调用BeanPostProcessor前置处理
        Object wrappedBean = applyBeanPostProcessorsBeforeInitialization(bean, beanName);

        // 3. 调用初始化方法
        invokeInitMethods(beanName, wrappedBean, beanDefinition);

        // 4. 调用BeanPostProcessor后置处理（AOP代理在这里创建）
        wrappedBean = applyBeanPostProcessorsAfterInitialization(wrappedBean, beanName);

        return wrappedBean;
    }

    /**
     * 调用BeanPostProcessor前置处理
     */
    private Object applyBeanPostProcessorsBeforeInitialization(Object bean, String beanName) {
        Object result = bean;
        for (BeanPostProcessor processor : beanPostProcessors) {
            Object current = processor.postProcessBeforeInitialization(result, beanName);
            if (current == null) {
                return result;
            }
            result = current;
        }
        return result;
    }

    /**
     * 调用BeanPostProcessor后置处理
     */
    private Object applyBeanPostProcessorsAfterInitialization(Object bean, String beanName) {
        Object result = bean;
        for (BeanPostProcessor processor : beanPostProcessors) {
            Object current = processor.postProcessAfterInitialization(result, beanName);
            if (current == null) {
                return result;
            }
            result = current;
        }
        return result;
    }
}
```

### 6.3 Bean完整生命周期

```
Bean生命周期（9个阶段）：

1. 实例化（Instantiation）
   └─ 调用构造方法创建对象

2. 属性填充（Populate Properties）
   └─ 注入@Autowired/@Value等依赖

3. BeanNameAware.setBeanName()
   └─ 如果Bean实现了BeanNameAware接口

4. BeanFactoryAware.setBeanFactory()
   └─ 如果Bean实现了BeanFactoryAware接口

5. ApplicationContextAware.setApplicationContext()
   └─ 如果Bean实现了ApplicationContextAware接口

6. BeanPostProcessor.postProcessBeforeInitialization()
   └─ 前置处理（例如：@PostConstruct注解处理）

7. InitializingBean.afterPropertiesSet()
   └─ 如果Bean实现了InitializingBean接口

8. init-method
   └─ 调用自定义初始化方法

9. BeanPostProcessor.postProcessAfterInitialization()
   └─ 后置处理（例如：AOP代理创建）

10. Bean使用（In Use）
    └─ Bean可以被使用

11. DisposableBean.destroy()
    └─ 容器关闭时调用

12. destroy-method
    └─ 调用自定义销毁方法
```

**代码示例**：

```java
/**
 * Bean生命周期演示
 */
@Component
public class LifecycleBean implements
        BeanNameAware,
        BeanFactoryAware,
        ApplicationContextAware,
        InitializingBean,
        DisposableBean {

    private String beanName;

    public LifecycleBean() {
        System.out.println("1. 构造方法执行");
    }

    @Autowired
    private UserService userService;  // 2. 属性填充

    @Override
    public void setBeanName(String name) {
        this.beanName = name;
        System.out.println("3. setBeanName: " + name);
    }

    @Override
    public void setBeanFactory(BeanFactory beanFactory) {
        System.out.println("4. setBeanFactory");
    }

    @Override
    public void setApplicationContext(ApplicationContext applicationContext) {
        System.out.println("5. setApplicationContext");
    }

    @PostConstruct
    public void postConstruct() {
        System.out.println("6. @PostConstruct");
    }

    @Override
    public void afterPropertiesSet() {
        System.out.println("7. afterPropertiesSet");
    }

    @Override
    public void destroy() {
        System.out.println("11. destroy()");
    }

    @PreDestroy
    public void preDestroy() {
        System.out.println("12. @PreDestroy");
    }
}
```

---

## 七、循环依赖的三级缓存解决方案

### 7.1 循环依赖问题

**什么是循环依赖？**

```java
@Component
class A {
    @Autowired
    private B b;  // A依赖B
}

@Component
class B {
    @Autowired
    private A a;  // B依赖A
}

// 循环依赖：A → B → A
```

**问题**：

```
创建A：
  └─ 注入B
      └─ 创建B
          └─ 注入A
              └─ 创建A ← 死循环！
```

### 7.2 Spring的三级缓存解决方案

**三级缓存**：

```java
public class DefaultSingletonBeanRegistry {

    /**
     * 一级缓存：单例对象缓存
     * 存储完全初始化的Bean
     */
    private final Map<String, Object> singletonObjects = new ConcurrentHashMap<>();

    /**
     * 二级缓存：早期单例对象缓存
     * 存储实例化但未初始化的Bean
     */
    private final Map<String, Object> earlySingletonObjects = new HashMap<>();

    /**
     * 三级缓存：单例工厂缓存
     * 存储Bean工厂，用于创建早期对象（处理AOP）
     */
    private final Map<String, ObjectFactory<?>> singletonFactories = new HashMap<>();

    /**
     * 正在创建的Bean名称集合
     */
    private final Set<String> singletonsCurrentlyInCreation =
        Collections.newSetFromMap(new ConcurrentHashMap<>());
}
```

**三级缓存的作用**：

| 缓存级别 | 名称 | 存储内容 | 作用 |
|---------|-----|---------|------|
| **一级缓存** | singletonObjects | 完整的Bean对象 | 存储完全初始化的单例Bean |
| **二级缓存** | earlySingletonObjects | 早期Bean对象 | 存储实例化但未初始化的Bean |
| **三级缓存** | singletonFactories | Bean工厂 | 存储创建早期对象的工厂（处理AOP代理） |

### 7.3 循环依赖解决流程

```java
/**
 * 获取单例Bean（支持循环依赖）
 */
protected Object getSingleton(String beanName) {
    // 1. 从一级缓存获取完整对象
    Object singletonObject = this.singletonObjects.get(beanName);

    // 2. 如果一级缓存没有，且Bean正在创建中
    if (singletonObject == null && isSingletonCurrentlyInCreation(beanName)) {
        synchronized (this.singletonObjects) {
            // 3. 从二级缓存获取早期对象
            singletonObject = this.earlySingletonObjects.get(beanName);

            // 4. 如果二级缓存也没有
            if (singletonObject == null) {
                // 5. 从三级缓存获取工厂
                ObjectFactory<?> singletonFactory = this.singletonFactories.get(beanName);
                if (singletonFactory != null) {
                    // 6. 通过工厂创建早期对象
                    singletonObject = singletonFactory.getObject();

                    // 7. 放入二级缓存
                    this.earlySingletonObjects.put(beanName, singletonObject);

                    // 8. 移除三级缓存
                    this.singletonFactories.remove(beanName);
                }
            }
        }
    }

    return singletonObject;
}

/**
 * 创建Bean
 */
protected Object doCreateBean(String beanName, BeanDefinition beanDefinition) {
    // 1. 实例化Bean
    Object bean = createBeanInstance(beanDefinition);

    // 2. 将Bean工厂放入三级缓存（提前暴露）
    addSingletonFactory(beanName, () -> getEarlyBeanReference(beanName, bean));

    // 3. 填充属性（依赖注入）
    populateBean(bean, beanDefinition);

    // 4. 初始化Bean
    bean = initializeBean(beanName, bean, beanDefinition);

    // 5. 移除二级和三级缓存，放入一级缓存
    if (isSingleton(beanDefinition)) {
        addSingleton(beanName, bean);
    }

    return bean;
}

/**
 * 将Bean工厂放入三级缓存
 */
protected void addSingletonFactory(String beanName, ObjectFactory<?> singletonFactory) {
    synchronized (this.singletonObjects) {
        if (!this.singletonObjects.containsKey(beanName)) {
            this.singletonFactories.put(beanName, singletonFactory);
            this.earlySingletonObjects.remove(beanName);
        }
    }
}

/**
 * 将完整Bean放入一级缓存
 */
protected void addSingleton(String beanName, Object singletonObject) {
    synchronized (this.singletonObjects) {
        this.singletonObjects.put(beanName, singletonObject);
        this.singletonFactories.remove(beanName);
        this.earlySingletonObjects.remove(beanName);
    }
}
```

### 7.4 循环依赖解决过程图解

```
假设：A依赖B，B依赖A

步骤1：创建A
├─ 实例化A（调用构造方法）
├─ 将A的工厂放入三级缓存
└─ 填充属性：需要注入B

步骤2：创建B
├─ 实例化B（调用构造方法）
├─ 将B的工厂放入三级缓存
└─ 填充属性：需要注入A

步骤3：获取A（B需要注入A）
├─ 从一级缓存获取：没有
├─ 从二级缓存获取：没有
├─ 从三级缓存获取：有！
├─ 调用工厂创建早期A对象
├─ 放入二级缓存
└─ 返回早期A对象给B

步骤4：B初始化完成
├─ B持有早期A对象
├─ B初始化完成
└─ B放入一级缓存

步骤5：A初始化完成
├─ A持有完整B对象
├─ A初始化完成
└─ A放入一级缓存

结果：循环依赖解决！
```

### 7.5 为什么需要三级缓存？

**疑问**：二级缓存不够吗？

**答案**：三级缓存是为了处理**AOP代理**

```java
/**
 * 获取早期Bean引用（处理AOP）
 */
protected Object getEarlyBeanReference(String beanName, Object bean) {
    Object exposedObject = bean;

    // 如果Bean需要AOP代理
    for (BeanPostProcessor bp : getBeanPostProcessors()) {
        if (bp instanceof SmartInstantiationAwareBeanPostProcessor) {
            SmartInstantiationAwareBeanPostProcessor ibp =
                (SmartInstantiationAwareBeanPostProcessor) bp;

            // 提前创建AOP代理
            exposedObject = ibp.getEarlyBeanReference(exposedObject, beanName);
        }
    }

    return exposedObject;
}
```

**流程对比**：

```
如果只有二级缓存：
  创建A
  └─ 实例化A
  └─ 放入二级缓存（原始对象）
  └─ 填充属性（注入B）
      └─ 创建B
          └─ 注入A（从二级缓存获取原始对象）
  └─ 初始化A
      └─ AOP创建代理
  问题：B持有的是A的原始对象，不是代理对象！

使用三级缓存：
  创建A
  └─ 实例化A
  └─ 放入三级缓存（工厂）
  └─ 填充属性（注入B）
      └─ 创建B
          └─ 注入A（从三级缓存工厂获取，提前创建代理）
  └─ 初始化A
  结果：B持有的是A的代理对象！
```

---

## 八、三种依赖注入方式对比

### 8.1 构造器注入

```java
@Service
public class UserService {

    private final UserRepository userRepository;

    // 构造器注入
    @Autowired
    public UserService(UserRepository userRepository) {
        this.userRepository = userRepository;
    }
}
```

**优点**：
- ✅ 依赖明确（final字段）
- ✅ 不可变对象
- ✅ 循环依赖编译期就会报错
- ✅ 便于单元测试

**缺点**：
- ❌ 参数过多时构造函数臃肿

### 8.2 Setter注入

```java
@Service
public class UserService {

    private UserRepository userRepository;

    // Setter注入
    @Autowired
    public void setUserRepository(UserRepository userRepository) {
        this.userRepository = userRepository;
    }
}
```

**优点**：
- ✅ 灵活，可选依赖

**缺点**：
- ❌ 可变对象
- ❌ 循环依赖运行时才发现

### 8.3 字段注入

```java
@Service
public class UserService {

    // 字段注入
    @Autowired
    private UserRepository userRepository;
}
```

**优点**：
- ✅ 代码简洁

**缺点**：
- ❌ 无法声明为final
- ❌ 难以单元测试
- ❌ 违反依赖倒置原则

### 8.4 推荐使用构造器注入

**Spring官方推荐**：优先使用构造器注入

```java
// ✅ 推荐
@Service
public class UserService {

    private final UserRepository userRepository;
    private final ProductService productService;

    public UserService(UserRepository userRepository,
                      ProductService productService) {
        this.userRepository = userRepository;
        this.productService = productService;
    }
}

// ❌ 不推荐
@Service
public class UserService {

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private ProductService productService;
}
```

---

## 九、总结与实践建议

### 9.1 IoC容器演进总结

**五个场景的演进**：

```
场景0：手动new
  └─ 问题：硬编码、强耦合、难测试

场景1：工厂模式
  └─ 改进：对象创建集中管理
  └─ 问题：仍需手动管理依赖

场景2：依赖注入
  └─ 改进：依赖关系外部化
  └─ 问题：配置繁琐

场景3：IoC容器
  └─ 改进：自动管理生命周期
  └─ 问题：需要XML配置

场景4：自动装配
  └─ 改进：注解驱动，零配置
  └─ 完美！
```

### 9.2 核心要点

**IoC容器的本质**：

> IoC容器 = 对象工厂 + 依赖注入器 + 生命周期管理器

**三大核心能力**：

1. **对象创建**：根据Bean定义创建对象
2. **依赖注入**：自动装配依赖关系
3. **生命周期管理**：从实例化到销毁的完整管理

**三级缓存的价值**：

> 三级缓存解决了循环依赖问题，使Spring可以处理复杂的对象依赖图

### 9.3 实践建议

**对于学习者**：

1. ✅ 手写一个简化版IoC容器（本文示例）
2. ✅ 理解Bean的完整生命周期
3. ✅ 掌握三级缓存原理
4. ✅ 优先使用构造器注入

**对于开发者**：

1. ✅ 使用@Component而非XML配置
2. ✅ 使用构造器注入而非字段注入
3. ✅ 避免循环依赖（设计问题）
4. ✅ 合理使用@Lazy延迟初始化

---

## 下一篇预告

**《AOP深度解析：从代码重复到面向切面编程》**

我们将：
1. 手写JDK动态代理和CGLIB代理
2. 深入Spring AOP的实现原理
3. 详解ProxyFactory的代理创建流程
4. 实战：自定义注解+AOP实现统一日志
5. AOP性能优化技巧

---

**写在最后**：

IoC容器是Spring的核心，理解IoC容器就理解了Spring的50%。

记住：**容器管理对象，开发者专注业务**。

这就是IoC带来的价值！