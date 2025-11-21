---
title: "类加载的完整生命周期：7个阶段详解"
date: 2025-11-21T18:00:00+08:00
draft: false
tags: ["JVM", "类加载", "生命周期", "初始化"]
categories: ["技术"]
description: "深入理解类加载的7个阶段：加载、验证、准备、解析、初始化、使用、卸载，掌握类从加载到回收的完整过程"
series: ["JVM从入门到精通"]
weight: 6
stage: 2
stageTitle: "类加载机制篇"
---

## 引言

### 为什么要学习这个主题？

在第一阶段我们了解了JVM的基础架构，知道类加载子系统是JVM的重要组成部分。但你是否想过：

- 一个`.class`文件是如何一步步变成可用的Java类的？
- 为什么有时候类的静态变量有默认值，有时候又是我们设置的值？
- 类在什么时候被加载？什么时候被卸载？

理解类加载的生命周期，就像理解一个产品从原材料到成品的生产流程。这是理解Java类初始化、解决类加载问题的关键。

### 你将学到什么？

- ✅ 类加载的7个阶段及其作用
- ✅ 每个阶段的详细执行过程
- ✅ 验证、准备、初始化的区别
- ✅ 类的卸载机制
- ✅ 类加载的时机和触发条件

---

## 一、类加载的完整生命周期

### 1.1 七个阶段概览

```
.class文件
    ↓
1️⃣ 加载 (Loading)
    ↓
2️⃣ 验证 (Verification)
    ↓
3️⃣ 准备 (Preparation)          } 链接 (Linking)
    ↓
4️⃣ 解析 (Resolution)
    ↓
5️⃣ 初始化 (Initialization)
    ↓
6️⃣ 使用 (Using)
    ↓
7️⃣ 卸载 (Unloading)
```

**时间线**：
```
加载 → 验证 → 准备 → 解析 → 初始化
└──────────┬──────────┘
         链接阶段
```

**关键理解**：
- 前5个阶段的顺序是固定的（但可以交叉进行）
- 解析阶段可能在初始化之后（动态绑定）
- 验证、准备、解析统称为"链接"阶段

---

## 二、阶段1：加载（Loading）

### 2.1 作用

**将`.class`文件的二进制数据读入内存，转换成方法区的运行时数据结构，并在堆中创建一个`java.lang.Class`对象。**

### 2.2 三个步骤

```
1. 通过类的全限定名获取二进制字节流
   ↓
2. 将字节流代表的静态存储结构转化为方法区的运行时数据结构
   ↓
3. 在堆内存中生成一个代表这个类的java.lang.Class对象
```

### 2.3 数据来源

**类的字节码可以来自多种途径**：

```java
// 1. 从本地文件系统读取
.class文件

// 2. 从JAR/ZIP包中读取
jar:file:/path/to/app.jar!/com/example/User.class

// 3. 从网络获取
http://example.com/classes/User.class

// 4. 动态生成
动态代理（Proxy.newProxyInstance）
ASM字节码生成

// 5. 从数据库读取
某些中间件会从数据库加载类

// 6. 从加密文件读取
防止反编译的加密class
```

### 2.4 内存布局

```
┌─────────────────────┐
│       堆内存         │
│  ┌───────────────┐  │
│  │ Class对象     │  │  ← 对外的访问入口
│  │ (User.class)  │  │
│  └───────┬───────┘  │
└──────────│──────────┘
           │ 指向
┌──────────▼──────────┐
│      方法区          │
│  ┌───────────────┐  │
│  │ 类的元数据    │  │  ← 实际的类信息
│  │ - 字段信息    │  │
│  │ - 方法信息    │  │
│  │ - 常量池      │  │
│  │ - 注解信息    │  │
│  └───────────────┘  │
└─────────────────────┘
```

**关键理解**：
- Class对象在堆中，作为访问入口
- 类的元数据在方法区
- 每个类只有一个Class对象

### 2.5 代码示例

```java
public class LoadingDemo {
    public static void main(String[] args) throws Exception {
        // 方式1：Class.forName（会触发初始化）
        Class<?> clazz1 = Class.forName("java.lang.String");

        // 方式2：类名.class（不会触发初始化）
        Class<?> clazz2 = String.class;

        // 方式3：对象.getClass()
        String str = "hello";
        Class<?> clazz3 = str.getClass();

        // 验证：同一个类只有一个Class对象
        System.out.println(clazz1 == clazz2);  // true
        System.out.println(clazz2 == clazz3);  // true
    }
}
```

---

## 三、阶段2：验证（Verification）

### 3.1 作用

**确保Class文件的字节流符合JVM规范，不会危害虚拟机安全。**

### 3.2 四个验证步骤

#### 1. 文件格式验证

**检查项**：
- 魔数是否为`0xCAFEBABE`
- 主次版本号是否在当前JVM支持范围内
- 常量池的常量类型是否合法
- 索引值是否指向有效的常量

**目的**：保证输入的字节流能正确解析

**示例错误**：
```
java.lang.UnsupportedClassVersionError:
    com/example/User has been compiled by a more recent version of
    the Java Runtime (class file version 61.0), this version of
    the Java Runtime only recognizes class file versions up to 52.0

说明：用Java 17编译的类，在Java 8上运行
```

#### 2. 元数据验证

**检查项**：
- 类是否有父类（除了Object）
- 父类是否可以被继承（是否final）
- 抽象类是否实现了所有抽象方法
- 字段、方法是否与父类冲突

**目的**：保证语义符合Java语言规范

#### 3. 字节码验证

**检查项**：
- 类型转换是否合法
- 跳转指令不会跳出方法体
- 方法体中的类型转换有效
- 操作数栈的数据类型匹配

**目的**：保证方法体（字节码）的逻辑正确

**示例**：
```java
// 如果字节码中有这样的操作：
String s = (String) new Integer(123);  // ❌ 类型不匹配
// 字节码验证会失败
```

#### 4. 符号引用验证

**检查项**：
- 符号引用对应的类是否存在
- 字段、方法是否可访问（权限检查）
- 符号引用的类、字段、方法是否存在

**目的**：确保解析阶段能正常进行

**示例错误**：
```
java.lang.NoClassDefFoundError: com/example/Helper
    说明：引用的类不存在

java.lang.IllegalAccessError: tried to access class com.example.Helper
    说明：访问权限不足
```

### 3.3 验证的重要性

**为什么需要验证？**
- **安全性**：防止恶意字节码攻击JVM
- **稳定性**：避免非法字节码导致JVM崩溃
- **兼容性**：检查版本兼容性

**可以关闭验证吗？**
```bash
# 使用 -Xverify:none 关闭验证（不推荐）
java -Xverify:none MyApp

# 风险：可能导致JVM崩溃或安全问题
```

---

## 四、阶段3：准备（Preparation）

### 4.1 作用

**为类的静态变量分配内存，并设置默认初始值。**

### 4.2 关键理解

**准备阶段只处理静态变量，不包括实例变量。**

```java
public class PrepareDemo {
    // 静态变量
    private static int count;           // 准备阶段：count = 0
    private static String name;         // 准备阶段：name = null
    private static final int MAX = 100; // 准备阶段：MAX = 100 ✅

    // 实例变量
    private int age;                    // 不在准备阶段处理
}
```

### 4.3 默认值表

| 数据类型 | 默认值 |
|---------|--------|
| `int` | `0` |
| `long` | `0L` |
| `short` | `(short)0` |
| `char` | `'\u0000'` |
| `byte` | `(byte)0` |
| `boolean` | `false` |
| `float` | `0.0f` |
| `double` | `0.0d` |
| `reference` | `null` |

### 4.4 特殊情况：final常量

**如果静态变量被`final`修饰，且是编译期常量，则在准备阶段就赋值。**

```java
public class FinalDemo {
    // 编译期常量：准备阶段赋值
    private static final int MAX = 100;
    private static final String NAME = "Alice";

    // 非编译期常量：初始化阶段赋值
    private static final int RANDOM = new Random().nextInt();
    private static final String TIME = String.valueOf(System.currentTimeMillis());
}
```

**区别**：
```
编译期常量：值在编译时就确定，存储在常量池
非编译期常量：值需要运行时计算，在初始化阶段赋值
```

---

## 五、阶段4：解析（Resolution）

### 5.1 作用

**将常量池中的符号引用替换为直接引用。**

### 5.2 核心概念

#### 符号引用（Symbolic Reference）

**定义**：用一组符号描述引用目标，可以是任何形式的字面量。

**示例**：
```
类的全限定名：com/example/User
字段名和描述符：name:Ljava/lang/String;
方法名和描述符：getName:()Ljava/lang/String;
```

**特点**：
- 与内存布局无关
- 编译时就存在
- 字符串形式

#### 直接引用（Direct Reference）

**定义**：直接指向目标的指针、偏移量或句柄。

**示例**：
```
内存地址：0x00007f8a1c001000
方法表偏移量：offset 24
```

**特点**：
- 与内存布局相关
- 加载时才确定
- 指针/偏移量

### 5.3 解析的类型

```java
public class ResolveDemo {
    // 1. 类或接口的解析
    User user = new User();  // 解析User类

    // 2. 字段解析
    String name = user.name;  // 解析name字段

    // 3. 方法解析
    user.getName();  // 解析getName方法

    // 4. 接口方法解析
    List<String> list = new ArrayList<>();
    list.add("hello");  // 解析List.add接口方法
}
```

### 5.4 解析时机

**解析可能发生在**：
- 初始化之前（静态解析）
- 初始化之后（动态解析）
- 第一次使用时（延迟解析）

**动态绑定示例**：
```java
Animal animal = new Dog();
animal.eat();  // 运行时才确定调用Dog.eat()
```

---

## 六、阶段5：初始化（Initialization）

### 6.1 作用

**执行类构造器`<clinit>()`方法，真正开始执行类中定义的Java程序代码。**

### 6.2 <clinit>()方法

**`<clinit>()`方法是什么？**
- 编译器自动生成
- 收集所有静态变量的赋值动作和静态代码块
- 按照源代码顺序合并

**示例**：
```java
public class InitDemo {
    private static int count = 100;

    static {
        System.out.println("静态代码块1");
        count = 200;
    }

    private static String name = "Alice";

    static {
        System.out.println("静态代码块2");
    }
}
```

**等价的`<clinit>()`方法**：
```java
static void <clinit>() {
    count = 100;                           // 第1行
    System.out.println("静态代码块1");      // 第2行
    count = 200;                           // 第3行
    name = "Alice";                        // 第4行
    System.out.println("静态代码块2");      // 第5行
}
```

### 6.3 初始化顺序

```java
public class Parent {
    static {
        System.out.println("Parent静态代码块");
    }
}

public class Child extends Parent {
    static {
        System.out.println("Child静态代码块");
    }

    public static void main(String[] args) {
        System.out.println("main方法");
    }
}
```

**输出**：
```
Parent静态代码块   ← 父类先初始化
Child静态代码块    ← 子类后初始化
main方法
```

**规则**：
1. 父类的`<clinit>()`先执行
2. 接口的初始化不要求父接口全部完成初始化
3. `<clinit>()`是线程安全的（JVM保证）

### 6.4 准备 vs 初始化对比

```java
public class CompareDemo {
    private static int count = 100;
}
```

**时间线**：
```
准备阶段：count = 0（默认值）
    ↓
初始化阶段：count = 100（真正赋值）
```

**完整流程**：
```
1. 加载：读取.class文件
2. 验证：检查字节码合法性
3. 准备：count = 0（分配内存，设置默认值）
4. 解析：符号引用 → 直接引用
5. 初始化：count = 100（执行<clinit>()方法）
```

---

## 七、阶段6：使用（Using）

**类被初始化后，就可以正常使用了。**

包括：
- 创建对象
- 调用静态方法
- 访问静态字段
- 调用实例方法
- ...

---

## 八、阶段7：卸载（Unloading）

### 8.1 类何时被卸载？

**必须同时满足3个条件**：
1. 该类所有的实例都已被回收
2. 加载该类的ClassLoader已被回收
3. 该类的`java.lang.Class`对象没有被引用

### 8.2 常见场景

**不会被卸载**：
- JDK自带的类（由启动类加载器加载）
- 应用类加载器加载的类（ClassLoader长期存活）

**可能被卸载**：
- 自定义ClassLoader加载的类
- JSP类（每次修改后重新加载）
- 热部署场景

### 8.3 示例

```java
public class UnloadDemo {
    public static void main(String[] args) throws Exception {
        // 创建自定义ClassLoader
        URLClassLoader loader = new URLClassLoader(
            new URL[]{new URL("file:///path/to/classes/")}
        );

        // 加载类
        Class<?> clazz = loader.loadClass("com.example.User");
        Object obj = clazz.newInstance();

        // 使用完毕
        obj = null;
        clazz = null;
        loader = null;

        // 建议GC
        System.gc();

        // 此时User类可能被卸载
    }
}
```

---

## 九、完整流程示例

### 9.1 代码示例

```java
public class LifecycleDemo {
    public static void main(String[] args) {
        System.out.println("main开始");
        User user = new User();
        System.out.println("main结束");
    }
}

class User {
    private static int count = 0;

    static {
        System.out.println("User类初始化");
        count = 100;
    }

    public User() {
        System.out.println("User构造器");
    }
}
```

### 9.2 执行流程

```
1. JVM启动
2. 加载LifecycleDemo类
3. 验证LifecycleDemo类
4. 准备LifecycleDemo类（静态变量默认值）
5. 解析LifecycleDemo类
6. 初始化LifecycleDemo类（执行<clinit>()）
7. 执行main方法 → 输出"main开始"
8. 遇到new User() → 触发User类加载
9. 加载User类
10. 验证User类
11. 准备User类：count = 0
12. 解析User类
13. 初始化User类：输出"User类初始化"，count = 100
14. 创建User对象 → 输出"User构造器"
15. 输出"main结束"
16. 程序结束
```

**输出**：
```
main开始
User类初始化
User构造器
main结束
```

---

## 总结

### 核心要点回顾

1. **7个阶段**
   - 加载：读取字节码，创建Class对象
   - 验证：检查字节码安全性
   - 准备：分配内存，设置默认值
   - 解析：符号引用 → 直接引用
   - 初始化：执行`<clinit>()`，真正赋值
   - 使用：正常使用类
   - 卸载：类被回收

2. **关键区别**
   - 准备阶段：默认值（count = 0）
   - 初始化阶段：真正赋值（count = 100）

3. **初始化规则**
   - 父类先于子类初始化
   - `<clinit>()`线程安全
   - 只执行一次

4. **卸载条件**
   - 所有实例被回收
   - ClassLoader被回收
   - Class对象无引用

### 思考题

1. 为什么需要"准备"和"初始化"两个阶段？为什么不在准备阶段就直接赋值？
2. final静态常量在准备阶段就赋值，这样做有什么好处？
3. 类的卸载为什么这么难？为什么JDK自带的类不会被卸载？

### 下一篇预告

下一篇《类加载器家族：启动、扩展、应用类加载器》，我们将探讨：
- JVM的三层类加载器体系
- 每个类加载器的职责和加载范围
- 类加载器的父子关系
- 如何查看类是由哪个加载器加载的

---

## 参考资料

- [The Java Virtual Machine Specification - Chapter 5: Loading, Linking, and Initializing](https://docs.oracle.com/javase/specs/jvms/se17/html/jvms-5.html)
- 《深入理解Java虚拟机（第3版）》- 周志明，第7章
- [Class Loading in the Java Virtual Machine](https://www.artima.com/insidejvm/ed2/lifetype.html)

---

**欢迎在评论区分享你对类加载的理解！**
