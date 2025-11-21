---
title: "双亲委派模型：为什么要这样设计？"
date: 2025-11-20T19:00:00+08:00
draft: false
tags: ["JVM", "双亲委派", "类加载器", "安全机制"]
categories: ["技术"]
description: "深入理解双亲委派模型的工作原理、设计动机和安全保障，掌握Java类加载的核心机制"
series: ["JVM从入门到精通"]
weight: 8
stage: 2
stageTitle: "类加载机制篇"
---

## 引言

### 为什么要学习这个主题？

在上一篇文章中，我们了解了JVM的三层类加载器体系。但你是否想过：

- 为什么要设计"父子"关系？直接加载不行吗？
- 如果我自己写一个`java.lang.String`类会发生什么？
- 双亲委派模型是如何保证Java核心类库不被篡改的？

双亲委派模型是类加载机制的核心，也是JVM安全性的基础。理解它，就能理解Java为什么是一个安全的平台。

### 你将学到什么？

- ✅ 双亲委派模型的完整工作流程
- ✅ 为什么要设计双亲委派模型
- ✅ 双亲委派模型带来的好处
- ✅ 如何验证双亲委派模型
- ✅ 双亲委派模型的局限性

---

## 一、什么是双亲委派模型？

### 1.1 定义

**当一个类加载器收到类加载请求时，它首先不会自己尝试加载，而是把这个请求委派给父加载器完成。只有当父加载器无法完成加载时，子加载器才会尝试自己加载。**

### 1.2 工作流程

```
应用类加载器收到加载请求：加载 com.example.User
    ↓ 委派给父加载器
扩展类加载器尝试加载 com.example.User
    ↓ 委派给父加载器
启动类加载器尝试加载 com.example.User
    ↓ 在核心类库中找不到
    ✗ 返回"无法加载"
    ↓
扩展类加载器尝试自己加载
    ↓ 在扩展库中找不到
    ✗ 返回"无法加载"
    ↓
应用类加载器尝试自己加载
    ↓ 在classpath中找到
    ✓ 加载成功
```

### 1.3 流程图

```
┌────────────────────────────────────────────┐
│  1. 应用类加载器收到请求                    │
│     "加载 com.example.User"                │
└──────────────┬─────────────────────────────┘
               │ 委派给父加载器
┌──────────────▼─────────────────────────────┐
│  2. 扩展类加载器收到请求                    │
│     检查：是否在 lib/ext 中？               │
└──────────────┬─────────────────────────────┘
               │ 委派给父加载器
┌──────────────▼─────────────────────────────┐
│  3. 启动类加载器收到请求                    │
│     检查：是否在 rt.jar 中？                │
│     结果：✗ 没找到                         │
└──────────────┬─────────────────────────────┘
               │ 返回失败
┌──────────────▼─────────────────────────────┐
│  4. 扩展类加载器尝试加载                    │
│     在 lib/ext 中查找                       │
│     结果：✗ 没找到                         │
└──────────────┬─────────────────────────────┘
               │ 返回失败
┌──────────────▼─────────────────────────────┐
│  5. 应用类加载器尝试加载                    │
│     在 classpath 中查找                     │
│     结果：✓ 找到并加载                     │
└────────────────────────────────────────────┘
```

---

## 二、双亲委派模型的源码实现

### 2.1 ClassLoader.loadClass() 源码

```java
public abstract class ClassLoader {

    protected Class<?> loadClass(String name, boolean resolve)
        throws ClassNotFoundException
    {
        synchronized (getClassLoadingLock(name)) {
            // 1. 首先检查该类是否已经被加载
            Class<?> c = findLoadedClass(name);
            if (c == null) {
                try {
                    // 2. 如果有父加载器，委派给父加载器加载
                    if (parent != null) {
                        c = parent.loadClass(name, false);
                    } else {
                        // 3. 如果没有父加载器，委派给启动类加载器
                        c = findBootstrapClassOrNull(name);
                    }
                } catch (ClassNotFoundException e) {
                    // 父加载器无法加载，不做处理
                }

                if (c == null) {
                    // 4. 父加载器无法加载时，调用自己的findClass
                    c = findClass(name);
                }
            }

            // 5. 如果需要，解析类
            if (resolve) {
                resolveClass(c);
            }
            return c;
        }
    }

    // 子类需要重写这个方法
    protected Class<?> findClass(String name) throws ClassNotFoundException {
        throw new ClassNotFoundException(name);
    }
}
```

### 2.2 关键步骤解析

**步骤1：检查缓存**
```java
Class<?> c = findLoadedClass(name);
```
- 避免重复加载
- 每个类只加载一次

**步骤2：委派给父加载器**
```java
if (parent != null) {
    c = parent.loadClass(name, false);
}
```
- 递归向上委派
- 最终到达启动类加载器

**步骤3：自己尝试加载**
```java
c = findClass(name);
```
- 父加载器无法加载时才执行
- 调用自己的findClass方法

---

## 三、为什么要设计双亲委派模型？

### 3.1 保证类的唯一性

**问题场景**：如果没有双亲委派模型

```java
// 应用类加载器加载的 String
String s1 = "hello";  // 加载 java.lang.String

// 自定义加载器加载的 String
String s2 = myLoader.loadClass("java.lang.String");

// 结果：s1 和 s2 是不同的类！
s1.getClass() != s2.getClass()
```

**问题**：
- 同一个类被不同加载器加载，产生多个副本
- 破坏了Java类型系统的一致性

**双亲委派的解决方案**：
```
任何加载器加载 java.lang.String
    ↓ 委派
启动类加载器统一加载
    ↓
保证全局只有一个 String 类
```

### 3.2 保证核心类库的安全性

**攻击场景**：恶意代码篡改核心类

```java
// 攻击者自己写的 String 类
package java.lang;

public class String {
    // 恶意代码：窃取密码
    public String(String value) {
        sendToHacker(value);  // 发送到黑客服务器
    }
}
```

**如果没有双亲委派**：
- 应用类加载器可能加载攻击者的String
- 导致核心类被替换

**双亲委派的防护**：
```
加载 java.lang.String
    ↓ 委派
启动类加载器加载
    ↓ 从 rt.jar 加载官方String
    ✓ 攻击者的String永远不会被加载
```

### 3.3 避免类的重复加载

**场景**：多个加载器加载同一个类

```
应用类加载器加载 User
扩展类加载器加载 User
启动类加载器加载 User
    ↓ 结果：浪费内存，类重复加载
```

**双亲委派的优化**：
```
所有加载器都委派给父加载器
    ↓
最终由某一个加载器统一加载
    ↓
其他加载器复用这个加载结果
```

---

## 四、实战：验证双亲委派模型

### 4.1 尝试创建自己的 java.lang.String

**步骤1：创建自己的String类**

```java
// 注意：必须放在 java.lang 包下
package java.lang;

public class String {
    static {
        System.out.println("我的String类被加载了！");
    }

    public static void main(String[] args) {
        System.out.println("Hello from my String!");
    }
}
```

**步骤2：编译运行**

```bash
javac java/lang/String.java
java java.lang.String
```

**结果**：
```
错误: 在类 java.lang.String 中找不到 main 方法
```

**原因**：
1. 启动类加载器首先加载`java.lang.String`
2. 从`rt.jar`中找到官方的String类
3. 官方String没有main方法
4. 你自己的String类永远不会被加载

**结论**：✅ 双亲委派模型成功保护了核心类

### 4.2 详细验证流程

```java
public class DelegationDemo {
    public static void main(String[] args) throws Exception {
        // 获取系统类加载器
        ClassLoader appLoader = ClassLoader.getSystemClassLoader();

        // 尝试加载 String 类
        Class<?> clazz = appLoader.loadClass("java.lang.String");

        // 查看是哪个加载器加载的
        ClassLoader loader = clazz.getClassLoader();
        System.out.println("String的类加载器: " + loader);

        // 验证：无论用哪个加载器，都是同一个String类
        ClassLoader extLoader = appLoader.getParent();
        Class<?> clazz2 = extLoader.loadClass("java.lang.String");

        System.out.println("两次加载的类是否相同: " + (clazz == clazz2));
    }
}
```

**输出**：
```
String的类加载器: null（启动类加载器）
两次加载的类是否相同: true
```

### 4.3 监控类加载过程

**使用JVM参数**：
```bash
java -verbose:class DelegationDemo
```

**输出示例**：
```
[Loaded java.lang.Object from /Library/Java/.../rt.jar]
[Loaded java.lang.String from /Library/Java/.../rt.jar]
[Loaded DelegationDemo from file:/.../classes/]
...
```

**说明**：
- `java.lang.String`从`rt.jar`加载（启动类加载器）
- `DelegationDemo`从`classpath`加载（应用类加载器）

---

## 五、双亲委派模型的好处

### 5.1 优点总结

| 好处 | 说明 | 示例 |
|-----|------|------|
| **类的唯一性** | 同一个类在JVM中只有一份 | `String`类全局唯一 |
| **安全性** | 核心类不会被替换 | 无法篡改`Object`类 |
| **避免重复加载** | 父加载器已加载的类，子加载器不重复加载 | 节省内存 |
| **隔离性** | 不同应用的类相互隔离 | Tomcat多应用部署 |

### 5.2 安全机制详解

**场景1：攻击者尝试替换Object类**

```java
// 攻击代码
package java.lang;

public class Object {
    // 恶意代码
    public Object() {
        System.exit(0);  // 让JVM崩溃
    }
}
```

**防护**：
- 启动类加载器首先加载官方Object
- 攻击者的Object永远不会被加载

**场景2：攻击者尝试窃取敏感信息**

```java
// 攻击代码
package java.lang;

public class System {
    public static PrintStream out = new HackerPrintStream();
}
```

**防护**：
- 启动类加载器保护System类
- 恶意代码无法生效

---

## 六、双亲委派模型的局限性

### 6.1 无法向下委派

**问题场景**：SPI（Service Provider Interface）

```
DriverManager（核心类，启动类加载器）
    ↓ 需要加载
MySQL驱动（第三方库，应用类加载器）
```

**困境**：
- 父加载器加载的类，无法加载子加载器路径下的类
- 违反了双亲委派的单向性

**解决方案**：
- 线程上下文类加载器（Thread Context ClassLoader）
- 父加载器通过上下文加载器请求子加载器加载

### 6.2 无法实现热部署

**热部署需求**：
- 代码修改后不重启应用
- 重新加载修改后的类

**双亲委派的限制**：
- 类加载器的类加载缓存
- 一个类只能被加载一次

**解决方案**：
- 自定义类加载器
- 每次重新创建类加载器
- 打破双亲委派模型

### 6.3 类隔离问题

**需求**：Tomcat中多个应用使用不同版本的同一个库

```
应用A：使用 Spring 4.x
应用B：使用 Spring 5.x
```

**双亲委派的限制**：
- 同一个类只能有一个版本
- 无法实现类隔离

**解决方案**：
- 每个应用使用独立的类加载器
- 部分打破双亲委派

---

## 七、类的唯一性判定

### 7.1 类的唯一性规则

**在JVM中，一个类的唯一性由两个因素决定**：
1. 类的全限定名
2. 加载该类的类加载器

```java
类A == 类B 当且仅当：
    类A的全限定名 == 类B的全限定名
    AND
    类A的类加载器 == 类B的类加载器
```

### 7.2 示例验证

```java
public class ClassIdentityDemo {
    public static void main(String[] args) throws Exception {
        // 使用系统类加载器加载
        ClassLoader loader1 = ClassLoader.getSystemClassLoader();
        Class<?> clazz1 = loader1.loadClass("com.example.User");

        // 使用自定义类加载器加载
        ClassLoader loader2 = new MyClassLoader();
        Class<?> clazz2 = loader2.loadClass("com.example.User");

        // 验证
        System.out.println("类名相同: " + clazz1.getName().equals(clazz2.getName()));
        System.out.println("加载器相同: " + (loader1 == loader2));
        System.out.println("类对象相同: " + (clazz1 == clazz2));

        // 尝试类型转换
        Object obj1 = clazz1.newInstance();
        Object obj2 = clazz2.newInstance();

        try {
            clazz1.cast(obj2);  // 尝试将obj2转换为clazz1类型
        } catch (ClassCastException e) {
            System.out.println("类型转换失败: " + e.getMessage());
        }
    }
}
```

**输出**：
```
类名相同: true
加载器相同: false
类对象相同: false
类型转换失败: Cannot cast com.example.User to com.example.User
```

**说明**：
- 虽然类名相同
- 但加载器不同
- 在JVM中是两个不同的类

---

## 总结

### 核心要点回顾

1. **双亲委派模型**
   - 先委派给父加载器
   - 父加载器无法加载时才自己加载
   - 从上到下查找，从下到上加载

2. **设计动机**
   - 保证类的唯一性
   - 保护核心类库安全
   - 避免类的重复加载

3. **工作流程**
   - 检查缓存 → 委派父加载器 → 自己加载
   - 递归向上委派，递归向下加载

4. **安全保障**
   - 核心类库不可替换
   - 防止恶意代码攻击
   - 类型系统一致性

5. **局限性**
   - 无法向下委派（SPI问题）
   - 无法热部署
   - 类隔离受限

### 思考题

1. 如果把自己写的类放在`rt.jar`中，能绕过双亲委派模型吗？
2. 为什么说"双亲委派模型"是个错误的翻译？（提示：parent不一定是双亲）
3. Tomcat是如何打破双亲委派模型实现类隔离的？

### 下一篇预告

下一篇《打破双亲委派：自定义类加载器实战》，我们将探讨：
- 如何自定义类加载器
- 如何打破双亲委派模型
- Tomcat的类加载架构
- 热部署的实现原理
- 自定义类加载器的应用场景

---

## 参考资料

- 《深入理解Java虚拟机（第3版）》- 周志明，第7章
- [The Java Virtual Machine Specification - Chapter 5.3](https://docs.oracle.com/javase/specs/jvms/se17/html/jvms-5.html#jvms-5.3)
- [Understanding Class Loaders in Java](https://www.baeldung.com/java-classloaders)

---

**欢迎在评论区分享你对双亲委派模型的理解！**
