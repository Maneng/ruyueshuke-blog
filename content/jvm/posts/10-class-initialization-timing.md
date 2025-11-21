---
title: "类加载时机与初始化时机的6种场景"
date: 2025-11-21T20:00:00+08:00
draft: false
tags: ["JVM", "类初始化", "加载时机", "主动引用"]
categories: ["技术"]
description: "深入理解类加载和初始化的触发时机，掌握主动引用与被动引用的区别，避免类初始化的常见陷阱"
series: ["JVM从入门到精通"]
weight: 10
stage: 2
stageTitle: "类加载机制篇"
---

## 引言

### 为什么要学习这个主题？

在前面的文章中，我们学习了类加载的完整流程和自定义类加载器。但你是否想过：

- 类什么时候被加载？什么时候被初始化？
- 为什么有时候静态代码块会执行，有时候不会？
- `ClassName.class`会触发类初始化吗？

理解类的加载和初始化时机，能帮助我们：
- 优化程序启动速度（延迟加载）
- 避免循环依赖问题
- 正确使用单例模式
- 理解静态代码块的执行时机

### 你将学到什么？

- ✅ 类加载的时机（何时加载）
- ✅ 类初始化的6种主动引用场景
- ✅ 被动引用不会触发初始化
- ✅ 接口的初始化规则
- ✅ 类初始化的常见陷阱
- ✅ 如何控制类的加载时机

---

## 一、类加载的时机

### 1.1 何时加载类？

**JVM规范没有强制规定类的加载时机，由JVM实现自行决定。**

**通常在以下情况加载**：
- 第一次主动使用类时
- 预加载（可选，JVM优化）

### 1.2 何时必须初始化？

**JVM规范严格规定了6种必须初始化类的场景（主动引用）。**

---

## 二、6种主动引用场景（必须初始化）

### 场景1：使用new创建对象

**代码**：
```java
public class NewDemo {
    public static void main(String[] args) {
        User user = new User();  // ← 触发User类初始化
    }
}

class User {
    static {
        System.out.println("User类初始化");
    }
}
```

**输出**：
```
User类初始化
```

**说明**：
- `new`关键字会触发类的初始化
- 执行静态代码块
- 执行静态变量赋值

---

### 场景2：访问类的静态字段（除final常量）

**代码**：
```java
public class StaticFieldDemo {
    public static void main(String[] args) {
        System.out.println(Config.name);  // ← 触发Config类初始化
    }
}

class Config {
    static {
        System.out.println("Config类初始化");
    }

    public static String name = "Alice";
}
```

**输出**：
```
Config类初始化
Alice
```

**特殊情况：final常量**

```java
public class FinalConstDemo {
    public static void main(String[] args) {
        System.out.println(Constants.MAX);  // ← 不会触发初始化
    }
}

class Constants {
    static {
        System.out.println("Constants类初始化");  // 不会执行
    }

    public static final int MAX = 100;  // 编译期常量
}
```

**输出**：
```
100
```

**说明**：
- `final`的编译期常量不会触发初始化
- 因为值在编译时已内联到调用类的常量池

---

### 场景3：调用类的静态方法

**代码**：
```java
public class StaticMethodDemo {
    public static void main(String[] args) {
        Helper.doSomething();  // ← 触发Helper类初始化
    }
}

class Helper {
    static {
        System.out.println("Helper类初始化");
    }

    public static void doSomething() {
        System.out.println("执行静态方法");
    }
}
```

**输出**：
```
Helper类初始化
执行静态方法
```

---

### 场景4：反射调用类

**代码**：
```java
public class ReflectDemo {
    public static void main(String[] args) throws Exception {
        // Class.forName会触发初始化
        Class<?> clazz = Class.forName("User");  // ← 触发初始化

        // 验证：.class不会触发初始化
        Class<?> clazz2 = User.class;  // ← 不会触发初始化
    }
}

class User {
    static {
        System.out.println("User类初始化");
    }
}
```

**输出**：
```
User类初始化
```

**说明**：
- `Class.forName()`会触发初始化
- `ClassName.class`不会触发初始化（被动引用）

**不触发初始化的反射**：
```java
// 不触发初始化
ClassLoader.getSystemClassLoader().loadClass("User");
```

---

### 场景5：初始化子类会先初始化父类

**代码**：
```java
public class ParentDemo {
    public static void main(String[] args) {
        Child child = new Child();  // ← 先初始化Parent，再初始化Child
    }
}

class Parent {
    static {
        System.out.println("Parent类初始化");
    }
}

class Child extends Parent {
    static {
        System.out.println("Child类初始化");
    }
}
```

**输出**：
```
Parent类初始化
Child类初始化
```

**说明**：
- 子类初始化前，必须先初始化父类
- 递归向上，直到`Object`类

**特殊情况：只访问父类静态字段**

```java
public class ParentOnlyDemo {
    public static void main(String[] args) {
        System.out.println(Child.parentValue);  // ← 只触发Parent初始化
    }
}

class Parent {
    static {
        System.out.println("Parent类初始化");
    }
    public static int parentValue = 100;
}

class Child extends Parent {
    static {
        System.out.println("Child类初始化");  // 不会执行
    }
}
```

**输出**：
```
Parent类初始化
100
```

**说明**：
- 只触发定义该字段的类的初始化
- 子类不会被初始化

---

### 场景6：JVM启动时的主类

**代码**：
```java
public class MainClassDemo {
    static {
        System.out.println("主类初始化");
    }

    public static void main(String[] args) {
        System.out.println("main方法执行");
    }
}
```

**输出**：
```
主类初始化
main方法执行
```

**说明**：
- 包含`main`方法的主类会被初始化
- 在执行`main`方法之前

---

## 三、被动引用（不会触发初始化）

### 被动引用1：通过子类引用父类的静态字段

**见上面"场景5"的特殊情况**。

---

### 被动引用2：通过数组定义引用类

**代码**：
```java
public class ArrayDemo {
    public static void main(String[] args) {
        User[] users = new User[10];  // ← 不会触发User类初始化
    }
}

class User {
    static {
        System.out.println("User类初始化");  // 不会执行
    }
}
```

**输出**：
```
（无输出）
```

**说明**：
- 只是创建了数组对象
- 并没有使用User类本身

---

### 被动引用3：访问类的final常量

**见上面"场景2"的特殊情况**。

---

### 被动引用4：使用.class获取Class对象

**代码**：
```java
public class ClassLiteralDemo {
    public static void main(String[] args) {
        Class<?> clazz = User.class;  // ← 不会触发初始化
        System.out.println("获取Class对象");
    }
}

class User {
    static {
        System.out.println("User类初始化");  // 不会执行
    }
}
```

**输出**：
```
获取Class对象
```

**说明**：
- `.class`不会触发初始化
- 只是获取Class对象的引用

---

### 被动引用5：ClassLoader.loadClass()

**代码**：
```java
public class LoadClassDemo {
    public static void main(String[] args) throws Exception {
        ClassLoader loader = ClassLoader.getSystemClassLoader();
        Class<?> clazz = loader.loadClass("User");  // ← 不会触发初始化
        System.out.println("类已加载");
    }
}

class User {
    static {
        System.out.println("User类初始化");  // 不会执行
    }
}
```

**输出**：
```
类已加载
```

**说明**：
- `ClassLoader.loadClass()`只加载类，不初始化
- `Class.forName()`会加载并初始化

---

## 四、接口的初始化规则

### 4.1 接口 vs 类的初始化区别

**区别**：
- 类初始化时，父类必须先初始化
- 接口初始化时，父接口不需要先初始化

### 4.2 示例

```java
public class InterfaceDemo {
    public static void main(String[] args) {
        System.out.println(Child.value);  // ← 只初始化Child接口
    }
}

interface Parent {
    int parentValue = getValue("Parent接口初始化");

    static int getValue(String msg) {
        System.out.println(msg);
        return 100;
    }
}

interface Child extends Parent {
    int value = getValue("Child接口初始化");

    static int getValue(String msg) {
        System.out.println(msg);
        return 200;
    }
}
```

**输出**：
```
Child接口初始化
200
```

**说明**：
- 只初始化Child接口
- Parent接口不会被初始化

---

## 五、类初始化的完整顺序

### 5.1 初始化顺序规则

```
1. 父类静态变量和静态代码块（按代码顺序）
    ↓
2. 子类静态变量和静态代码块（按代码顺序）
    ↓
3. 父类实例变量和构造代码块（按代码顺序）
    ↓
4. 父类构造器
    ↓
5. 子类实例变量和构造代码块（按代码顺序）
    ↓
6. 子类构造器
```

### 5.2 完整示例

```java
public class InitOrderDemo {
    public static void main(String[] args) {
        Child child = new Child();
    }
}

class Parent {
    // 1. 父类静态变量
    private static int parentStatic = getStatic("父类静态变量");

    // 2. 父类静态代码块
    static {
        System.out.println("父类静态代码块");
    }

    // 5. 父类实例变量
    private int parentInstance = getInstance("父类实例变量");

    // 6. 父类构造代码块
    {
        System.out.println("父类构造代码块");
    }

    // 7. 父类构造器
    public Parent() {
        System.out.println("父类构造器");
    }

    private static int getStatic(String msg) {
        System.out.println(msg);
        return 0;
    }

    private int getInstance(String msg) {
        System.out.println(msg);
        return 0;
    }
}

class Child extends Parent {
    // 3. 子类静态变量
    private static int childStatic = getStatic("子类静态变量");

    // 4. 子类静态代码块
    static {
        System.out.println("子类静态代码块");
    }

    // 8. 子类实例变量
    private int childInstance = getInstance("子类实例变量");

    // 9. 子类构造代码块
    {
        System.out.println("子类构造代码块");
    }

    // 10. 子类构造器
    public Child() {
        System.out.println("子类构造器");
    }

    private static int getStatic(String msg) {
        System.out.println(msg);
        return 0;
    }

    private int getInstance(String msg) {
        System.out.println(msg);
        return 0;
    }
}
```

**输出**：
```
父类静态变量
父类静态代码块
子类静态变量
子类静态代码块
父类实例变量
父类构造代码块
父类构造器
子类实例变量
子类构造代码块
子类构造器
```

---

## 六、常见陷阱与最佳实践

### 陷阱1：静态变量的初始化顺序

```java
public class OrderTrap {
    private static int a = 1;
    private static int b = getB();
    private static int c = 3;

    static {
        System.out.println("a=" + a);
        System.out.println("b=" + b);
        System.out.println("c=" + c);
    }

    private static int getB() {
        System.out.println("getB: a=" + a + ", c=" + c);
        return 2;
    }

    public static void main(String[] args) {
        // 触发初始化
    }
}
```

**输出**：
```
getB: a=1, c=0
a=1
b=2
c=3
```

**说明**：
- 静态变量按代码顺序初始化
- `getB()`执行时，`c`还未赋值（默认值0）

### 陷阱2：单例模式的类初始化

**错误示例**：
```java
public class Singleton {
    private static Singleton instance = new Singleton();  // ← 陷阱！
    private static int counter1;
    private static int counter2 = 0;

    private Singleton() {
        counter1++;
        counter2++;
    }

    public static Singleton getInstance() {
        return instance;
    }

    public static void main(String[] args) {
        Singleton singleton = Singleton.getInstance();
        System.out.println("counter1=" + counter1);
        System.out.println("counter2=" + counter2);
    }
}
```

**输出**：
```
counter1=1
counter2=0  ← 为什么是0？
```

**原因**：
```
1. instance = new Singleton()  // counter1=1, counter2=1
2. counter1 初始化（默认值0）  // 无影响
3. counter2 = 0                // 覆盖为0！
```

**正确写法**：
```java
public class Singleton {
    private static int counter1;
    private static int counter2 = 0;
    private static Singleton instance = new Singleton();  // ← 放在最后

    // ...
}
```

### 陷阱3：循环依赖导致的初始化问题

```java
class A {
    static {
        System.out.println("A类初始化");
    }
    public static B b = new B();
}

class B {
    static {
        System.out.println("B类初始化");
    }
    public static A a = new A();
}

public class CircularDemo {
    public static void main(String[] args) {
        A.b.hashCode();  // ← 触发死锁？
    }
}
```

**结果**：不会死锁，但会产生空指针

**JVM保证**：
- 类初始化是线程安全的
- 同一个类只会初始化一次

---

## 七、实战：延迟加载优化

### 7.1 静态内部类实现单例（推荐）

```java
public class Singleton {
    private Singleton() {}

    // 静态内部类，只有在使用时才加载
    private static class Holder {
        private static final Singleton INSTANCE = new Singleton();
    }

    public static Singleton getInstance() {
        return Holder.INSTANCE;  // ← 此时才触发Holder类初始化
    }
}
```

**优点**：
- 延迟加载
- 线程安全（类初始化锁）
- 无需synchronized

### 7.2 使用ClassLoader延迟加载

```java
public class LazyLoadDemo {
    public static void main(String[] args) throws Exception {
        System.out.println("程序开始");

        // 方式1：立即初始化
        // Class<?> clazz = Class.forName("HeavyClass");

        // 方式2：延迟初始化
        ClassLoader loader = ClassLoader.getSystemClassLoader();
        Class<?> clazz = loader.loadClass("HeavyClass");
        System.out.println("类已加载，但未初始化");

        // 真正使用时才初始化
        clazz.newInstance();
    }
}

class HeavyClass {
    static {
        System.out.println("HeavyClass初始化（耗时操作）");
    }
}
```

---

## 总结

### 核心要点回顾

1. **6种主动引用（必须初始化）**
   - new创建对象
   - 访问静态字段（除final常量）
   - 调用静态方法
   - 反射调用（Class.forName）
   - 初始化子类
   - JVM启动的主类

2. **被动引用（不会初始化）**
   - 通过子类引用父类静态字段
   - 定义类数组
   - 访问final常量
   - 使用.class
   - ClassLoader.loadClass()

3. **初始化顺序**
   - 父类静态 → 子类静态 → 父类实例 → 子类实例

4. **最佳实践**
   - 静态变量放在静态代码块之前
   - 单例用静态内部类
   - 注意循环依赖

### 思考题

1. 为什么`ClassName.class`不会触发初始化，而`Class.forName()`会？
2. 如何实现一个类的"真正"延迟加载（用到时才初始化）？
3. 静态代码块中可以访问后面定义的静态变量吗？

### 第二阶段总结

恭喜！你已经完成了**类加载机制篇**的所有文章。现在你应该：
- ✅ 理解类加载的7个阶段
- ✅ 掌握三层类加载器体系
- ✅ 理解双亲委派模型
- ✅ 能够自定义类加载器
- ✅ 掌握类加载和初始化时机

### 下一阶段预告

第三阶段《内存结构篇》，我们将深入探讨：
- JVM内存结构全景
- 程序计数器
- 虚拟机栈与栈帧
- 堆内存与对象分配
- 方法区与元空间
- 直接内存
- 对象的内存布局

---

## 参考资料

- [The Java Virtual Machine Specification - Chapter 5.5: Initialization](https://docs.oracle.com/javase/specs/jvms/se17/html/jvms-5.html#jvms-5.5)
- 《深入理解Java虚拟机（第3版）》- 周志明，第7章
- [When Does Class Initialization Happen?](https://www.baeldung.com/java-class-initialization)

---

**欢迎在评论区分享你对类初始化时机的理解！**
