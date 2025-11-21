---
title: "打破双亲委派：自定义类加载器实战"
date: 2025-11-20T19:30:00+08:00
draft: false
tags: ["JVM", "自定义类加载器", "热部署", "类加密"]
categories: ["技术"]
description: "从零实现自定义类加载器，掌握如何打破双亲委派模型，实现热部署、类加密、模块隔离等高级特性"
series: ["JVM从入门到精通"]
weight: 9
stage: 2
stageTitle: "类加载机制篇"
---

## 引言

### 为什么要学习这个主题？

在前面的文章中，我们了解了双亲委派模型及其保护机制。但实际开发中，有些场景需要突破这些限制：

- Tomcat如何实现多个应用使用不同版本的同一个库？
- 如何实现代码的热部署（不重启更新代码）？
- 如何加密class文件防止反编译？

这些需求都需要自定义类加载器。理解自定义类加载器，就能掌握Java类加载的灵活性和扩展性。

### 你将学到什么？

- ✅ 如何自定义类加载器
- ✅ 如何打破双亲委派模型
- ✅ 实现热部署功能
- ✅ 实现类文件加密
- ✅ Tomcat的类加载架构
- ✅ 自定义类加载器的最佳实践

---

## 一、自定义类加载器的基础

### 1.1 继承ClassLoader

**自定义类加载器只需要继承`ClassLoader`并重写`findClass`方法**。

```java
public class MyClassLoader extends ClassLoader {

    @Override
    protected Class<?> findClass(String name) throws ClassNotFoundException {
        // 1. 根据类名找到.class文件
        // 2. 读取字节码数据
        // 3. 调用defineClass转换为Class对象
        return super.findClass(name);
    }
}
```

### 1.2 关键方法

| 方法 | 作用 | 是否重写 |
|-----|------|---------|
| `loadClass()` | 加载类的入口 | 通常**不**重写（保持双亲委派） |
| `findClass()` | 查找并加载类 | **必须**重写 |
| `defineClass()` | 字节码 → Class对象 | **不要**重写（final方法） |
| `resolveClass()` | 解析类 | 可选重写 |

**重要**：
- 重写`findClass()`：遵循双亲委派
- 重写`loadClass()`：打破双亲委派

---

## 二、实战1：从指定目录加载类

### 2.1 需求

**从`/custom/classes/`目录加载类，而不是从classpath。**

### 2.2 实现

```java
import java.io.*;
import java.nio.file.*;

public class FileClassLoader extends ClassLoader {
    private String classPath;

    public FileClassLoader(String classPath) {
        this.classPath = classPath;
    }

    @Override
    protected Class<?> findClass(String name) throws ClassNotFoundException {
        try {
            // 1. 将类名转换为文件路径
            // com.example.User → /custom/classes/com/example/User.class
            String fileName = name.replace('.', '/') + ".class";
            String filePath = classPath + File.separator + fileName;

            // 2. 读取字节码数据
            byte[] classData = Files.readAllBytes(Paths.get(filePath));

            // 3. 调用defineClass转换为Class对象
            return defineClass(name, classData, 0, classData.length);

        } catch (IOException e) {
            throw new ClassNotFoundException("无法加载类: " + name, e);
        }
    }
}
```

### 2.3 测试

**准备测试类**：

```java
// /custom/classes/com/example/Hello.java
package com.example;

public class Hello {
    public void sayHello() {
        System.out.println("Hello from custom classloader!");
    }
}
```

**编译**：
```bash
javac -d /custom/classes /path/to/Hello.java
```

**测试代码**：

```java
public class FileClassLoaderTest {
    public static void main(String[] args) throws Exception {
        // 创建自定义类加载器
        FileClassLoader loader = new FileClassLoader("/custom/classes");

        // 加载类
        Class<?> clazz = loader.loadClass("com.example.Hello");

        // 验证加载器
        System.out.println("类加载器: " + clazz.getClassLoader());

        // 创建实例并调用方法
        Object obj = clazz.newInstance();
        clazz.getMethod("sayHello").invoke(obj);
    }
}
```

**输出**：
```
类加载器: FileClassLoader@xxxxx
Hello from custom classloader!
```

---

## 三、实战2：实现类加密与解密

### 3.1 需求

**防止class文件被反编译，使用加密保护。**

### 3.2 加密工具类

```java
import javax.crypto.*;
import javax.crypto.spec.SecretKeySpec;
import java.security.Key;

public class ClassEncryptor {
    private static final String ALGORITHM = "AES";
    private static final String KEY = "MySecretKey12345"; // 16字节密钥

    // 加密class文件
    public static byte[] encrypt(byte[] data) throws Exception {
        Key key = new SecretKeySpec(KEY.getBytes(), ALGORITHM);
        Cipher cipher = Cipher.getInstance(ALGORITHM);
        cipher.init(Cipher.ENCRYPT_MODE, key);
        return cipher.doFinal(data);
    }

    // 解密class文件
    public static byte[] decrypt(byte[] data) throws Exception {
        Key key = new SecretKeySpec(KEY.getBytes(), ALGORITHM);
        Cipher cipher = Cipher.getInstance(ALGORITHM);
        cipher.init(Cipher.DECRYPT_MODE, key);
        return cipher.doFinal(data);
    }

    // 工具方法：加密文件
    public static void encryptFile(String inputFile, String outputFile) throws Exception {
        byte[] data = Files.readAllBytes(Paths.get(inputFile));
        byte[] encrypted = encrypt(data);
        Files.write(Paths.get(outputFile), encrypted);
        System.out.println("加密完成: " + outputFile);
    }
}
```

### 3.3 解密类加载器

```java
public class EncryptedClassLoader extends ClassLoader {
    private String classPath;

    public EncryptedClassLoader(String classPath) {
        this.classPath = classPath;
    }

    @Override
    protected Class<?> findClass(String name) throws ClassNotFoundException {
        try {
            // 1. 读取加密的class文件
            String fileName = name.replace('.', '/') + ".encrypted";
            String filePath = classPath + File.separator + fileName;
            byte[] encryptedData = Files.readAllBytes(Paths.get(filePath));

            // 2. 解密
            byte[] classData = ClassEncryptor.decrypt(encryptedData);

            // 3. 定义类
            return defineClass(name, classData, 0, classData.length);

        } catch (Exception e) {
            throw new ClassNotFoundException("无法加载加密类: " + name, e);
        }
    }
}
```

### 3.4 使用流程

**步骤1：加密class文件**

```java
public class EncryptDemo {
    public static void main(String[] args) throws Exception {
        ClassEncryptor.encryptFile(
            "/path/to/Hello.class",
            "/encrypted/Hello.encrypted"
        );
    }
}
```

**步骤2：使用解密加载器**

```java
public class EncryptedLoaderTest {
    public static void main(String[] args) throws Exception {
        EncryptedClassLoader loader = new EncryptedClassLoader("/encrypted");
        Class<?> clazz = loader.loadClass("com.example.Hello");

        Object obj = clazz.newInstance();
        clazz.getMethod("sayHello").invoke(obj);
    }
}
```

**效果**：
- `.encrypted`文件无法直接反编译
- 运行时动态解密并加载

---

## 四、实战3：实现热部署

### 4.1 需求

**代码修改后，不重启应用，自动重新加载类。**

### 4.2 热部署类加载器

```java
public class HotSwapClassLoader extends ClassLoader {
    private String classPath;

    public HotSwapClassLoader(String classPath, ClassLoader parent) {
        super(parent);
        this.classPath = classPath;
    }

    @Override
    protected Class<?> findClass(String name) throws ClassNotFoundException {
        try {
            String fileName = name.replace('.', '/') + ".class";
            String filePath = classPath + File.separator + fileName;
            byte[] classData = Files.readAllBytes(Paths.get(filePath));
            return defineClass(name, classData, 0, classData.length);
        } catch (IOException e) {
            throw new ClassNotFoundException("无法加载类: " + name, e);
        }
    }
}
```

### 4.3 热部署管理器

```java
public class HotSwapManager {
    private String classPath;
    private Map<String, Long> lastModified = new HashMap<>();

    public HotSwapManager(String classPath) {
        this.classPath = classPath;
    }

    public Class<?> loadClass(String name) throws Exception {
        String fileName = name.replace('.', '/') + ".class";
        String filePath = classPath + File.separator + fileName;
        File file = new File(filePath);

        long currentModified = file.lastModified();
        Long cachedModified = lastModified.get(name);

        // 检查文件是否修改
        if (cachedModified == null || currentModified > cachedModified) {
            System.out.println("检测到类变化，重新加载: " + name);

            // 创建新的类加载器（重要！）
            HotSwapClassLoader loader = new HotSwapClassLoader(
                classPath,
                this.getClass().getClassLoader()
            );

            Class<?> clazz = loader.loadClass(name);
            lastModified.put(name, currentModified);
            return clazz;
        }

        return null;  // 未修改
    }
}
```

### 4.4 测试热部署

```java
public class HotSwapTest {
    public static void main(String[] args) throws Exception {
        HotSwapManager manager = new HotSwapManager("/hotswap/classes");

        while (true) {
            Class<?> clazz = manager.loadClass("com.example.Hello");

            if (clazz != null) {
                Object obj = clazz.newInstance();
                clazz.getMethod("sayHello").invoke(obj);
            }

            Thread.sleep(3000);  // 每3秒检查一次
        }
    }
}
```

**效果**：
- 修改`Hello.java`并重新编译
- 3秒后自动重新加载
- 无需重启应用

**关键点**：
- **每次重新加载都创建新的ClassLoader**
- 旧的ClassLoader和类会被GC回收

---

## 五、打破双亲委派模型

### 5.1 为什么要打破？

**场景**：
- Tomcat需要隔离不同应用的类
- OSGi模块化系统
- SPI机制（父加载器加载子加载器的类）

### 5.2 如何打破？

**重写`loadClass()`方法，不再委派给父加载器。**

```java
public class BreakDelegationLoader extends ClassLoader {
    private String classPath;

    public BreakDelegationLoader(String classPath) {
        this.classPath = classPath;
    }

    @Override
    public Class<?> loadClass(String name) throws ClassNotFoundException {
        // 1. 检查是否已加载
        Class<?> clazz = findLoadedClass(name);
        if (clazz != null) {
            return clazz;
        }

        // 2. 如果是JDK核心类，委派给父加载器
        if (name.startsWith("java.") || name.startsWith("javax.")) {
            return super.loadClass(name);
        }

        // 3. 自己加载（不委派给父加载器）
        try {
            return findClass(name);
        } catch (ClassNotFoundException e) {
            // 4. 如果自己无法加载，再委派给父加载器
            return super.loadClass(name);
        }
    }

    @Override
    protected Class<?> findClass(String name) throws ClassNotFoundException {
        try {
            String fileName = name.replace('.', '/') + ".class";
            String filePath = classPath + File.separator + fileName;
            byte[] classData = Files.readAllBytes(Paths.get(filePath));
            return defineClass(name, classData, 0, classData.length);
        } catch (IOException e) {
            throw new ClassNotFoundException("无法加载类: " + name, e);
        }
    }
}
```

**关键变化**：
- 不再先委派给父加载器
- 优先自己加载
- 只有核心类（`java.*`）才委派给父加载器

### 5.3 验证

```java
public class BreakDelegationTest {
    public static void main(String[] args) throws Exception {
        // 创建两个独立的类加载器
        BreakDelegationLoader loader1 = new BreakDelegationLoader("/app1/classes");
        BreakDelegationLoader loader2 = new BreakDelegationLoader("/app2/classes");

        // 加载同名类
        Class<?> clazz1 = loader1.loadClass("com.example.User");
        Class<?> clazz2 = loader2.loadClass("com.example.User");

        // 验证：是不同的类
        System.out.println("类名相同: " + clazz1.getName().equals(clazz2.getName()));
        System.out.println("类对象相同: " + (clazz1 == clazz2));
        System.out.println("类加载器1: " + clazz1.getClassLoader());
        System.out.println("类加载器2: " + clazz2.getClassLoader());
    }
}
```

**输出**：
```
类名相同: true
类对象相同: false
类加载器1: BreakDelegationLoader@xxxxx
类加载器2: BreakDelegationLoader@yyyyy
```

---

## 六、Tomcat的类加载架构

### 6.1 Tomcat的类加载器层次

```
┌────────────────────────┐
│  Bootstrap ClassLoader │  JDK核心类
└──────────┬─────────────┘
           │
┌──────────▼─────────────┐
│  Extension ClassLoader │  JDK扩展类
└──────────┬─────────────┘
           │
┌──────────▼─────────────┐
│ Application ClassLoader│  启动Tomcat的类
└──────────┬─────────────┘
           │
┌──────────▼─────────────┐
│  Common ClassLoader    │  Tomcat和应用共享的类
└──────────┬─────────────┘
           │
       ┌───┴────┐
       ↓        ↓
┌────────┐  ┌────────┐
│Catalina│  │ Shared │  Tomcat内部类
└────────┘  └───┬────┘
                │
         ┌──────┴──────┐
         ↓             ↓
    ┌────────┐    ┌────────┐
    │WebApp1 │    │WebApp2 │  各应用独立的类
    └────────┘    └────────┘
```

### 6.2 Tomcat打破双亲委派的策略

**加载顺序**：
1. 先在本地Repository查找（WEB-INF/classes, WEB-INF/lib）
2. 再委派给父加载器
3. 父加载器无法加载时，返回失败

**好处**：
- 应用优先加载自己的类
- 不同应用可以使用不同版本的库
- 应用之间类互相隔离

### 6.3 简化的Tomcat加载器

```java
public class TomcatLikeClassLoader extends ClassLoader {
    private String webAppPath;

    public TomcatLikeClassLoader(String webAppPath, ClassLoader parent) {
        super(parent);
        this.webAppPath = webAppPath;
    }

    @Override
    public Class<?> loadClass(String name) throws ClassNotFoundException {
        // 1. 检查是否已加载
        Class<?> clazz = findLoadedClass(name);
        if (clazz != null) {
            return clazz;
        }

        // 2. JDK核心类委派给父加载器
        if (name.startsWith("java.")) {
            return super.loadClass(name);
        }

        // 3. 先尝试自己加载（应用优先）
        try {
            return findClass(name);
        } catch (ClassNotFoundException e) {
            // 4. 自己加载失败，委派给父加载器
            return super.loadClass(name);
        }
    }

    @Override
    protected Class<?> findClass(String name) throws ClassNotFoundException {
        // 从 WEB-INF/classes 和 WEB-INF/lib 中加载
        String fileName = name.replace('.', '/') + ".class";
        String filePath = webAppPath + "/WEB-INF/classes/" + fileName;

        try {
            byte[] classData = Files.readAllBytes(Paths.get(filePath));
            return defineClass(name, classData, 0, classData.length);
        } catch (IOException e) {
            throw new ClassNotFoundException("无法加载类: " + name, e);
        }
    }
}
```

---

## 七、最佳实践与注意事项

### 7.1 自定义类加载器的最佳实践

| 原则 | 说明 |
|-----|------|
| **重写findClass而非loadClass** | 保持双亲委派，除非必要 |
| **不要加载JDK核心类** | 避免安全问题 |
| **处理好父子关系** | 正确设置parent加载器 |
| **缓存已加载的类** | 使用findLoadedClass检查 |
| **线程安全** | loadClass方法需要同步 |

### 7.2 常见陷阱

**陷阱1：忘记调用defineClass**
```java
// ❌ 错误
protected Class<?> findClass(String name) {
    byte[] data = readClassData(name);
    return null;  // 忘记调用defineClass
}

// ✅ 正确
protected Class<?> findClass(String name) {
    byte[] data = readClassData(name);
    return defineClass(name, data, 0, data.length);
}
```

**陷阱2：类名和实际路径不匹配**
```java
// ❌ 错误
defineClass("User", data, 0, data.length);  // 类名错误

// ✅ 正确
defineClass("com.example.User", data, 0, data.length);
```

**陷阱3：热部署时重用ClassLoader**
```java
// ❌ 错误：重用类加载器
ClassLoader loader = new MyClassLoader();
Class<?> v1 = loader.loadClass("User");
// 修改代码后
Class<?> v2 = loader.loadClass("User");  // 返回的还是v1

// ✅ 正确：每次创建新的类加载器
ClassLoader loader1 = new MyClassLoader();
Class<?> v1 = loader1.loadClass("User");
// 修改代码后
ClassLoader loader2 = new MyClassLoader();  // 新的加载器
Class<?> v2 = loader2.loadClass("User");
```

---

## 总结

### 核心要点回顾

1. **自定义类加载器**
   - 继承ClassLoader
   - 重写findClass方法
   - 使用defineClass转换字节码

2. **遵循双亲委派**
   - 重写findClass
   - 不重写loadClass

3. **打破双亲委派**
   - 重写loadClass
   - 先自己加载，失败再委派
   - 核心类必须委派给父加载器

4. **实际应用**
   - 热部署：每次新建ClassLoader
   - 类加密：加载时动态解密
   - 类隔离：不同应用独立加载器

### 思考题

1. 为什么热部署必须每次创建新的ClassLoader，而不能重用旧的？
2. 如果自定义类加载器加载了`java.lang.String`，会发生什么？
3. Tomcat如何实现一个应用的重新部署不影响其他应用？

### 下一篇预告

下一篇《类加载时机与初始化时机的6种场景》，我们将探讨：
- 类什么时候被加载
- 类什么时候被初始化
- 主动引用 vs 被动引用
- 如何控制类的加载时机
- 类初始化的常见陷阱

---

## 参考资料

- 《深入理解Java虚拟机（第3版）》- 周志明，第7章
- [How Tomcat Works](https://www.amazon.com/How-Tomcat-Works-Budi-Kurniawan/dp/097521280X)
- [Understanding Java Class Loaders](https://www.baeldung.com/java-classloaders)

---

**欢迎在评论区分享你的自定义类加载器实践经验！**
