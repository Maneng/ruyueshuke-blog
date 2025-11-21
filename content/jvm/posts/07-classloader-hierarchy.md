---
title: "类加载器家族：启动、扩展、应用类加载器"
date: 2025-11-21T18:30:00+08:00
draft: false
tags: ["JVM", "类加载器", "ClassLoader", "层次结构"]
categories: ["技术"]
description: "深入理解JVM的三层类加载器体系，掌握启动类加载器、扩展类加载器、应用类加载器的职责和加载范围"
series: ["JVM从入门到精通"]
weight: 7
stage: 2
stageTitle: "类加载机制篇"
---

## 引言

### 为什么要学习这个主题？

在上一篇文章中，我们了解了类加载的完整生命周期。但你是否想过：

- JVM中有多少个类加载器？
- 为什么要设计多个类加载器？
- `java.lang.String`和我们自己写的类是由同一个加载器加载的吗？

理解类加载器的层次结构，就像理解一个组织的部门分工。不同的类加载器负责加载不同来源的类，这种设计既保证了安全性，又提供了灵活性。

### 你将学到什么？

- ✅ JVM的三层类加载器体系
- ✅ 每个类加载器的职责和加载路径
- ✅ 类加载器的父子关系（委派关系）
- ✅ 如何查看类是由哪个加载器加载的
- ✅ 线程上下文类加载器

---

## 一、类加载器的层次结构

### 1.1 三层体系

```
┌────────────────────────────────────────┐
│   启动类加载器                          │  Bootstrap ClassLoader
│   (Bootstrap ClassLoader)              │  C++实现，加载核心类库
│   加载：rt.jar、核心API                │
└──────────────┬─────────────────────────┘
               │ 父加载器
┌──────────────▼─────────────────────────┐
│   扩展类加载器                          │  Extension ClassLoader
│   (Extension ClassLoader)              │  Java实现，加载扩展库
│   加载：lib/ext/*.jar                  │
└──────────────┬─────────────────────────┘
               │ 父加载器
┌──────────────▼─────────────────────────┐
│   应用类加载器                          │  Application ClassLoader
│   (Application ClassLoader)            │  Java实现，加载应用类
│   加载：classpath下的类                │
└────────────────────────────────────────┘
               │ 父加载器（可自定义）
┌──────────────▼─────────────────────────┐
│   自定义类加载器                        │  User ClassLoader
│   (Custom ClassLoader)                 │  继承ClassLoader
│   加载：自定义路径的类                  │
└────────────────────────────────────────┘
```

**关键理解**：
- 这是一种**委派关系**，不是继承关系
- 父加载器在上层，子加载器在下层
- 加载类时，先委派给父加载器尝试

---

## 二、启动类加载器（Bootstrap ClassLoader）

### 2.1 特点

**最顶层的类加载器，负责加载JVM核心类库。**

**特殊之处**：
- 由C++实现（不是Java类）
- 在Java代码中无法直接引用
- 返回值为`null`

### 2.2 加载路径

**加载的类库**：
```
<JAVA_HOME>/jre/lib/rt.jar
<JAVA_HOME>/jre/lib/resources.jar
<JAVA_HOME>/jre/lib/charsets.jar
<JAVA_HOME>/jre/lib/jce.jar
...以及其他核心类库
```

**包含的包**：
```java
java.lang.*      // 核心类（String、Object、System等）
java.util.*      // 工具类（List、Map等）
java.io.*        // IO类
java.nio.*       // NIO类
java.net.*       // 网络类
java.security.*  // 安全类
...
```

### 2.3 示例：验证启动类加载器

```java
public class BootstrapDemo {
    public static void main(String[] args) {
        // 获取String类的类加载器
        ClassLoader loader = String.class.getClassLoader();
        System.out.println("String类的类加载器: " + loader);

        // 获取Object类的类加载器
        ClassLoader loader2 = Object.class.getClassLoader();
        System.out.println("Object类的类加载器: " + loader2);
    }
}
```

**输出**：
```
String类的类加载器: null
Object类的类加载器: null
```

**说明**：返回`null`表示由启动类加载器加载（C++实现，无法获取引用）。

### 2.4 查看启动类加载器的搜索路径

```java
public class BootstrapPathDemo {
    public static void main(String[] args) {
        // 获取启动类加载器的搜索路径
        String paths = System.getProperty("sun.boot.class.path");
        String[] pathArray = paths.split(":");

        System.out.println("启动类加载器的搜索路径：");
        for (String path : pathArray) {
            System.out.println(path);
        }
    }
}
```

**输出示例**（macOS）：
```
/Library/Java/JavaVirtualMachines/jdk-17.jdk/Contents/Home/lib/modules
/Library/Java/JavaVirtualMachines/jdk-17.jdk/Contents/Home/lib/jrt-fs.jar
```

---

## 三、扩展类加载器（Extension ClassLoader）

### 3.1 特点

**加载JDK的扩展库，提供额外功能。**

**实现类**：
```
Java 8：sun.misc.Launcher$ExtClassLoader
Java 9+：jdk.internal.loader.ClassLoaders$PlatformClassLoader
```

### 3.2 加载路径

**加载的类库**：
```
<JAVA_HOME>/jre/lib/ext/*.jar
或系统属性 java.ext.dirs 指定的目录
```

**包含的包**：
```java
javax.*          // Java扩展包
sun.*            // Sun专有实现
com.sun.*        // Sun公司的工具类
...
```

### 3.3 示例：验证扩展类加载器

```java
public class ExtensionDemo {
    public static void main(String[] args) {
        // 获取扩展类加载器
        ClassLoader extLoader = ClassLoader.getSystemClassLoader().getParent();
        System.out.println("扩展类加载器: " + extLoader);

        // 查看扩展类加载器的搜索路径
        String paths = System.getProperty("java.ext.dirs");
        System.out.println("扩展类加载器搜索路径:");
        if (paths != null) {
            for (String path : paths.split(":")) {
                System.out.println(path);
            }
        } else {
            System.out.println("Java 9+ 已移除 java.ext.dirs");
        }
    }
}
```

**输出**（Java 8）：
```
扩展类加载器: sun.misc.Launcher$ExtClassLoader@xxxxx
扩展类加载器搜索路径:
/Library/Java/Extensions
/System/Library/Java/Extensions
```

**Java 9+ 的变化**：
- 扩展类加载器改名为**平台类加载器**（Platform ClassLoader）
- 不再使用`lib/ext`目录
- 改用模块化系统

---

## 四、应用类加载器（Application ClassLoader）

### 4.1 特点

**加载应用程序的类，也称为系统类加载器。**

**实现类**：
```
Java 8：sun.misc.Launcher$AppClassLoader
Java 9+：jdk.internal.loader.ClassLoaders$AppClassLoader
```

### 4.2 加载路径

**加载的类**：
```
classpath下的所有类
-cp 或 -classpath 指定的路径
系统属性 java.class.path 指定的路径
```

**包括**：
- 用户自己编写的类
- 第三方库（如Spring、MyBatis）
- Maven/Gradle依赖的jar包

### 4.3 示例：验证应用类加载器

```java
public class AppDemo {
    public static void main(String[] args) {
        // 获取应用类加载器
        ClassLoader appLoader = ClassLoader.getSystemClassLoader();
        System.out.println("应用类加载器: " + appLoader);

        // 获取当前类的类加载器
        ClassLoader myLoader = AppDemo.class.getClassLoader();
        System.out.println("AppDemo的类加载器: " + myLoader);

        // 验证是否相同
        System.out.println("是否相同: " + (appLoader == myLoader));

        // 查看classpath
        String classpath = System.getProperty("java.class.path");
        System.out.println("\nClasspath:");
        for (String path : classpath.split(":")) {
            System.out.println(path);
        }
    }
}
```

**输出**：
```
应用类加载器: jdk.internal.loader.ClassLoaders$AppClassLoader@xxxxx
AppDemo的类加载器: jdk.internal.loader.ClassLoaders$AppClassLoader@xxxxx
是否相同: true

Classpath:
/Users/user/project/target/classes
/Users/user/.m2/repository/...
```

---

## 五、父子关系与委派关系

### 5.1 不是继承关系

**重要**：类加载器之间是**组合关系**，不是继承关系。

```java
public abstract class ClassLoader {
    private final ClassLoader parent;  // 父加载器引用

    protected ClassLoader(ClassLoader parent) {
        this.parent = parent;
    }

    public final ClassLoader getParent() {
        return parent;
    }
}
```

### 5.2 查看父子关系

```java
public class ParentDemo {
    public static void main(String[] args) {
        ClassLoader appLoader = ClassLoader.getSystemClassLoader();
        ClassLoader extLoader = appLoader.getParent();
        ClassLoader bootLoader = extLoader.getParent();

        System.out.println("应用类加载器: " + appLoader);
        System.out.println("扩展类加载器: " + extLoader);
        System.out.println("启动类加载器: " + bootLoader);

        // 验证层次关系
        System.out.println("\n层次关系：");
        ClassLoader current = appLoader;
        int level = 1;
        while (current != null) {
            System.out.println("Level " + level + ": " + current);
            current = current.getParent();
            level++;
        }
        System.out.println("Level " + level + ": Bootstrap ClassLoader (C++)");
    }
}
```

**输出**：
```
应用类加载器: jdk.internal.loader.ClassLoaders$AppClassLoader@xxxxx
扩展类加载器: jdk.internal.loader.ClassLoaders$PlatformClassLoader@xxxxx
启动类加载器: null

层次关系：
Level 1: jdk.internal.loader.ClassLoaders$AppClassLoader@xxxxx
Level 2: jdk.internal.loader.ClassLoaders$PlatformClassLoader@xxxxx
Level 3: Bootstrap ClassLoader (C++)
```

---

## 六、实战：查看类是由哪个加载器加载的

### 6.1 工具方法

```java
public class LoaderUtil {
    public static void printClassLoader(Class<?> clazz) {
        System.out.println("=== " + clazz.getName() + " ===");

        ClassLoader loader = clazz.getClassLoader();
        if (loader == null) {
            System.out.println("加载器: Bootstrap ClassLoader (C++)");
        } else {
            System.out.println("加载器: " + loader.getClass().getName());

            // 打印父加载器链
            System.out.println("父加载器链:");
            int level = 1;
            ClassLoader parent = loader;
            while (parent != null) {
                System.out.println("  Level " + level + ": " + parent.getClass().getName());
                parent = parent.getParent();
                level++;
            }
            System.out.println("  Level " + level + ": Bootstrap ClassLoader (C++)");
        }
        System.out.println();
    }
}
```

### 6.2 测试不同来源的类

```java
public class LoaderTest {
    public static void main(String[] args) {
        // 1. JDK核心类
        LoaderUtil.printClassLoader(String.class);
        LoaderUtil.printClassLoader(Object.class);

        // 2. JDK扩展类
        LoaderUtil.printClassLoader(sun.security.ec.SunEC.class);

        // 3. 应用程序类
        LoaderUtil.printClassLoader(LoaderTest.class);

        // 4. 第三方库类（如果有）
        // LoaderUtil.printClassLoader(org.springframework.context.ApplicationContext.class);
    }
}
```

**输出**：
```
=== java.lang.String ===
加载器: Bootstrap ClassLoader (C++)

=== java.lang.Object ===
加载器: Bootstrap ClassLoader (C++)

=== sun.security.ec.SunEC ===
加载器: jdk.internal.loader.ClassLoaders$PlatformClassLoader
父加载器链:
  Level 1: jdk.internal.loader.ClassLoaders$PlatformClassLoader
  Level 2: Bootstrap ClassLoader (C++)

=== LoaderTest ===
加载器: jdk.internal.loader.ClassLoaders$AppClassLoader
父加载器链:
  Level 1: jdk.internal.loader.ClassLoaders$AppClassLoader
  Level 2: jdk.internal.loader.ClassLoaders$PlatformClassLoader
  Level 3: Bootstrap ClassLoader (C++)
```

---

## 七、线程上下文类加载器

### 7.1 问题背景

**场景**：JDBC驱动加载

```
DriverManager（核心类，启动类加载器加载）
    ↓ 需要加载
MySQL驱动（第三方库，应用类加载器加载）
```

**问题**：
- 启动类加载器加载的类，无法加载应用类加载器的类
- 违反了双亲委派模型的单向委派原则

### 7.2 解决方案

**线程上下文类加载器（Thread Context ClassLoader）**

```java
// 设置线程上下文类加载器
Thread.currentThread().setContextClassLoader(classLoader);

// 获取线程上下文类加载器
ClassLoader loader = Thread.currentThread().getContextClassLoader();
```

### 7.3 JDBC示例

```java
// DriverManager（JDK核心类）
public class DriverManager {
    static {
        // 使用线程上下文类加载器加载驱动
        loadInitialDrivers();
    }

    private static void loadInitialDrivers() {
        // 获取线程上下文类加载器
        ServiceLoader<Driver> loadedDrivers = ServiceLoader.load(
            Driver.class,
            Thread.currentThread().getContextClassLoader()  // ← 使用上下文加载器
        );

        Iterator<Driver> driversIterator = loadedDrivers.iterator();
        while(driversIterator.hasNext()) {
            driversIterator.next();
        }
    }
}
```

**说明**：
- DriverManager由启动类加载器加载
- 但它通过线程上下文类加载器加载MySQL驱动
- 默认的线程上下文类加载器是应用类加载器

---

## 八、对比总结

### 8.1 三层类加载器对比表

| 特性 | 启动类加载器 | 扩展类加载器 | 应用类加载器 |
|-----|-------------|-------------|-------------|
| **实现语言** | C++ | Java | Java |
| **父加载器** | 无 | 启动类加载器 | 扩展类加载器 |
| **加载路径** | `<JAVA_HOME>/lib` | `<JAVA_HOME>/lib/ext` | classpath |
| **加载内容** | 核心类库（rt.jar） | 扩展库 | 应用程序类 |
| **返回值** | null | 具体对象 | 具体对象 |
| **典型类** | `java.lang.*` | `javax.*` | 用户自定义类 |

### 8.2 类加载器的职责划分

```
启动类加载器：
    - 加载JVM运行所需的核心类
    - 保证核心类的安全性和不可篡改性

扩展类加载器：
    - 加载JDK的扩展功能
    - 提供可选的标准库

应用类加载器：
    - 加载用户的应用程序
    - 加载第三方库

自定义类加载器：
    - 加密类的加载
    - 热部署
    - 模块隔离
```

---

## 总结

### 核心要点回顾

1. **三层类加载器体系**
   - 启动类加载器：C++实现，加载核心类库
   - 扩展类加载器：Java实现，加载扩展库
   - 应用类加载器：Java实现，加载应用程序

2. **父子关系**
   - 是组合关系，不是继承关系
   - 通过`parent`字段引用父加载器
   - 启动类加载器返回null

3. **职责划分**
   - 不同的加载器加载不同来源的类
   - 保证核心类的安全性
   - 提供扩展和自定义能力

4. **线程上下文类加载器**
   - 解决父加载器需要加载子加载器类的问题
   - JDBC、SPI等场景使用

### 思考题

1. 为什么启动类加载器返回null？这样设计有什么好处？
2. 为什么要设计三层类加载器，而不是一个加载器加载所有类？
3. 线程上下文类加载器破坏了双亲委派模型吗？

### 下一篇预告

下一篇《双亲委派模型：为什么要这样设计？》，我们将深入探讨：
- 双亲委派模型的完整流程
- 为什么要设计双亲委派模型
- 双亲委派带来的好处和限制
- 如何验证双亲委派模型的工作

---

## 参考资料

- [The Java Virtual Machine Specification - Chapter 5.3: Creation and Loading](https://docs.oracle.com/javase/specs/jvms/se17/html/jvms-5.html#jvms-5.3)
- 《深入理解Java虚拟机（第3版）》- 周志明，第7章
- [Understanding the Java ClassLoader](https://www.baeldung.com/java-classloaders)

---

**欢迎在评论区分享你对类加载器的理解！**
