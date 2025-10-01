---
# ============================================================
# 技术教程文章模板
# 适用于：分步骤教程、技术指南、操作手册
# ============================================================

title: "技术教程标题 - 如何实现 XXX 功能"
date: 2025-10-01T20:00:00+08:00
draft: false

# 教程类文章推荐的标签
tags: ["教程", "入门", "实战", "技术名称"]
categories: ["技术教程"]

description: "本教程将手把手教你如何实现 XXX，适合初学者跟随学习"

# 如果是系列教程，可以设置 series
# series: ["Spring Boot 系列教程"]
# weight: 1  # 系列文章的顺序

# 预计阅读时间（可选，会自动计算）
# readingTime: 15
---

## 教程概览

### 你将学到什么

通过本教程，你将学会：

- ✅ 核心技能点 1
- ✅ 核心技能点 2
- ✅ 核心技能点 3
- ✅ 实际应用场景

### 前置要求

在开始之前，你需要：

- 📌 基础知识 1（如：Java 基础）
- 📌 基础知识 2（如：Maven 使用）
- 📌 工具准备（如：IntelliJ IDEA）
- 📌 环境要求（如：JDK 17+）

### 技术栈

本教程使用的技术栈：

| 技术 | 版本 | 说明 |
|-----|------|------|
| Java | 17+ | 编程语言 |
| Spring Boot | 3.2.0 | Web 框架 |
| Maven | 3.8+ | 构建工具 |
| MySQL | 8.0+ | 数据库 |

### 最终效果

简要说明完成教程后能实现什么功能：

![最终效果图](/images/tutorial-result.png)

*图：完成教程后的效果展示*

### 预计时间

- ⏱️ **学习时间**：30-45 分钟
- ⏱️ **实践时间**：1-2 小时

---

## 第一步：环境准备

### 1.1 安装必要工具

#### 安装 JDK

macOS 安装：

```bash
# 使用 Homebrew 安装
brew install openjdk@17

# 配置环境变量
echo 'export PATH="/usr/local/opt/openjdk@17/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

# 验证安装
java -version
```

Windows 安装：

```bash
# 1. 从 Oracle 官网下载 JDK 17
# 2. 运行安装程序
# 3. 配置环境变量 JAVA_HOME
# 4. 验证安装
java -version
```

#### 安装 Maven

```bash
# macOS
brew install maven

# 验证安装
mvn -version
```

### 1.2 创建项目

使用 Spring Initializr 创建项目：

```bash
# 使用命令行创建（或访问 https://start.spring.io/）
curl https://start.spring.io/starter.zip \
  -d dependencies=web,data-jpa,mysql \
  -d type=maven-project \
  -d language=java \
  -d bootVersion=3.2.0 \
  -d groupId=com.example \
  -d artifactId=demo \
  -d name=demo \
  -d packageName=com.example.demo \
  -d javaVersion=17 \
  -o demo.zip

# 解压
unzip demo.zip
cd demo
```

### 1.3 验证项目

```bash
# 运行项目
mvn spring-boot:run

# 如果看到以下输出，说明项目创建成功：
# Started DemoApplication in X.XXX seconds
```

> 💡 **提示**：如果遇到端口占用错误，可以在 `application.properties` 中修改端口：
> ```properties
> server.port=8081
> ```

---

## 第二步：配置数据库

### 2.1 创建数据库

连接 MySQL 并创建数据库：

```sql
-- 创建数据库
CREATE DATABASE tutorial_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

-- 使用数据库
USE tutorial_db;

-- 创建用户表（示例）
CREATE TABLE users (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(100) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);
```

### 2.2 配置连接

编辑 `src/main/resources/application.properties`：

```properties
# 数据源配置
spring.datasource.url=jdbc:mysql://localhost:3306/tutorial_db?useSSL=false&serverTimezone=UTC
spring.datasource.username=root
spring.datasource.password=your_password
spring.datasource.driver-class-name=com.mysql.cj.jdbc.Driver

# JPA 配置
spring.jpa.hibernate.ddl-auto=update
spring.jpa.show-sql=true
spring.jpa.properties.hibernate.format_sql=true
spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.MySQLDialect
```

### 2.3 验证连接

启动应用验证数据库连接是否成功：

```bash
mvn spring-boot:run
```

如果没有报错，说明数据库连接配置正确。

---

## 第三步：创建实体类

### 3.1 创建 User 实体

创建文件 `src/main/java/com/example/demo/entity/User.java`：

```java
package com.example.demo.entity;

import jakarta.persistence.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "users")
public class User {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true, length = 50)
    private String username;

    @Column(nullable = false, unique = true, length = 100)
    private String email;

    @Column(nullable = false)
    private String password;

    @Column(name = "created_at", updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at")
    private LocalDateTime updatedAt;

    // Constructors
    public User() {
    }

    public User(String username, String email, String password) {
        this.username = username;
        this.email = email;
        this.password = password;
    }

    // Lifecycle callbacks
    @PrePersist
    protected void onCreate() {
        createdAt = LocalDateTime.now();
        updatedAt = LocalDateTime.now();
    }

    @PreUpdate
    protected void onUpdate() {
        updatedAt = LocalDateTime.now();
    }

    // Getters and Setters
    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public String getUsername() {
        return username;
    }

    public void setUsername(String username) {
        this.username = username;
    }

    public String getEmail() {
        return email;
    }

    public void setEmail(String email) {
        this.email = email;
    }

    public String getPassword() {
        return password;
    }

    public void setPassword(String password) {
        this.password = password;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public LocalDateTime getUpdatedAt() {
        return updatedAt;
    }

    @Override
    public String toString() {
        return "User{" +
                "id=" + id +
                ", username='" + username + '\'' +
                ", email='" + email + '\'' +
                ", createdAt=" + createdAt +
                '}';
    }
}
```

### 3.2 代码说明

关键注解解释：

- `@Entity`：标记这是一个 JPA 实体类
- `@Table`：指定数据库表名
- `@Id`：标记主键字段
- `@GeneratedValue`：主键自动生成策略
- `@Column`：配置列属性（长度、唯一性等）
- `@PrePersist` / `@PreUpdate`：生命周期回调方法

---

## 第四步：创建 Repository

### 4.1 创建 UserRepository 接口

创建文件 `src/main/java/com/example/demo/repository/UserRepository.java`：

```java
package com.example.demo.repository;

import com.example.demo.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface UserRepository extends JpaRepository<User, Long> {

    // 根据用户名查找
    Optional<User> findByUsername(String username);

    // 根据邮箱查找
    Optional<User> findByEmail(String email);

    // 检查用户名是否存在
    boolean existsByUsername(String username);

    // 检查邮箱是否存在
    boolean existsByEmail(String email);

    // 自定义查询
    @Query("SELECT u FROM User u WHERE u.username = ?1 OR u.email = ?2")
    Optional<User> findByUsernameOrEmail(String username, String email);
}
```

### 4.2 Spring Data JPA 说明

Spring Data JPA 提供了强大的查询功能：

- **方法命名查询**：按照约定命名方法，自动生成 SQL
- **@Query 注解**：自定义 JPQL 或 SQL 查询
- **分页和排序**：内置支持

---

## 第五步：创建 Service 层

### 5.1 创建 UserService 接口

创建文件 `src/main/java/com/example/demo/service/UserService.java`：

```java
package com.example.demo.service;

import com.example.demo.entity.User;
import java.util.List;
import java.util.Optional;

public interface UserService {

    User createUser(User user);

    Optional<User> getUserById(Long id);

    Optional<User> getUserByUsername(String username);

    List<User> getAllUsers();

    User updateUser(Long id, User user);

    void deleteUser(Long id);

    boolean existsByUsername(String username);

    boolean existsByEmail(String email);
}
```

### 5.2 创建 UserServiceImpl 实现

创建文件 `src/main/java/com/example/demo/service/impl/UserServiceImpl.java`：

```java
package com.example.demo.service.impl;

import com.example.demo.entity.User;
import com.example.demo.repository.UserRepository;
import com.example.demo.service.UserService;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Optional;

@Service
@Transactional
public class UserServiceImpl implements UserService {

    private final UserRepository userRepository;

    public UserServiceImpl(UserRepository userRepository) {
        this.userRepository = userRepository;
    }

    @Override
    public User createUser(User user) {
        // 检查用户名是否已存在
        if (userRepository.existsByUsername(user.getUsername())) {
            throw new RuntimeException("用户名已存在");
        }

        // 检查邮箱是否已存在
        if (userRepository.existsByEmail(user.getEmail())) {
            throw new RuntimeException("邮箱已被使用");
        }

        return userRepository.save(user);
    }

    @Override
    @Transactional(readOnly = true)
    public Optional<User> getUserById(Long id) {
        return userRepository.findById(id);
    }

    @Override
    @Transactional(readOnly = true)
    public Optional<User> getUserByUsername(String username) {
        return userRepository.findByUsername(username);
    }

    @Override
    @Transactional(readOnly = true)
    public List<User> getAllUsers() {
        return userRepository.findAll();
    }

    @Override
    public User updateUser(Long id, User user) {
        User existingUser = userRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("用户不存在"));

        existingUser.setUsername(user.getUsername());
        existingUser.setEmail(user.getEmail());

        return userRepository.save(existingUser);
    }

    @Override
    public void deleteUser(Long id) {
        if (!userRepository.existsById(id)) {
            throw new RuntimeException("用户不存在");
        }
        userRepository.deleteById(id);
    }

    @Override
    @Transactional(readOnly = true)
    public boolean existsByUsername(String username) {
        return userRepository.existsByUsername(username);
    }

    @Override
    @Transactional(readOnly = true)
    public boolean existsByEmail(String email) {
        return userRepository.existsByEmail(email);
    }
}
```

---

## 第六步：创建 Controller

创建文件 `src/main/java/com/example/demo/controller/UserController.java`：

```java
package com.example.demo.controller;

import com.example.demo.entity.User;
import com.example.demo.service.UserService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/users")
public class UserController {

    private final UserService userService;

    public UserController(UserService userService) {
        this.userService = userService;
    }

    // 创建用户
    @PostMapping
    public ResponseEntity<User> createUser(@RequestBody User user) {
        User createdUser = userService.createUser(user);
        return ResponseEntity.status(HttpStatus.CREATED).body(createdUser);
    }

    // 获取所有用户
    @GetMapping
    public ResponseEntity<List<User>> getAllUsers() {
        List<User> users = userService.getAllUsers();
        return ResponseEntity.ok(users);
    }

    // 根据ID获取用户
    @GetMapping("/{id}")
    public ResponseEntity<User> getUserById(@PathVariable Long id) {
        return userService.getUserById(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    // 根据用户名获取用户
    @GetMapping("/username/{username}")
    public ResponseEntity<User> getUserByUsername(@PathVariable String username) {
        return userService.getUserByUsername(username)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    // 更新用户
    @PutMapping("/{id}")
    public ResponseEntity<User> updateUser(@PathVariable Long id, @RequestBody User user) {
        User updatedUser = userService.updateUser(id, user);
        return ResponseEntity.ok(updatedUser);
    }

    // 删除用户
    @DeleteMapping("/{id}")
    public ResponseEntity<Void> deleteUser(@PathVariable Long id) {
        userService.deleteUser(id);
        return ResponseEntity.noContent().build();
    }
}
```

---

## 第七步：测试接口

### 7.1 启动应用

```bash
mvn spring-boot:run
```

### 7.2 测试 API

使用 curl 或 Postman 测试：

#### 创建用户

```bash
curl -X POST http://localhost:8080/api/users \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "email": "test@example.com",
    "password": "password123"
  }'
```

#### 获取所有用户

```bash
curl http://localhost:8080/api/users
```

#### 根据ID获取用户

```bash
curl http://localhost:8080/api/users/1
```

#### 更新用户

```bash
curl -X PUT http://localhost:8080/api/users/1 \
  -H "Content-Type: application/json" \
  -d '{
    "username": "updateduser",
    "email": "updated@example.com"
  }'
```

#### 删除用户

```bash
curl -X DELETE http://localhost:8080/api/users/1
```

### 7.3 预期结果

成功的响应示例：

```json
{
  "id": 1,
  "username": "testuser",
  "email": "test@example.com",
  "createdAt": "2025-10-01T20:00:00",
  "updatedAt": "2025-10-01T20:00:00"
}
```

---

## 进阶内容

### 异常处理

创建全局异常处理器：

```java
@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(RuntimeException.class)
    public ResponseEntity<ErrorResponse> handleRuntimeException(RuntimeException ex) {
        ErrorResponse error = new ErrorResponse(
            HttpStatus.BAD_REQUEST.value(),
            ex.getMessage()
        );
        return ResponseEntity.badRequest().body(error);
    }
}
```

### 数据验证

添加验证依赖并使用注解：

```java
@Entity
public class User {
    @NotBlank(message = "用户名不能为空")
    @Size(min = 3, max = 50, message = "用户名长度必须在3-50之间")
    private String username;

    @Email(message = "邮箱格式不正确")
    @NotBlank(message = "邮箱不能为空")
    private String email;
}
```

### 密码加密

使用 BCrypt 加密密码：

```java
@Service
public class UserServiceImpl implements UserService {

    private final PasswordEncoder passwordEncoder;

    @Override
    public User createUser(User user) {
        // 加密密码
        user.setPassword(passwordEncoder.encode(user.getPassword()));
        return userRepository.save(user);
    }
}
```

---

## 常见问题

### Q1: 端口被占用怎么办？

**解决方案**：修改 `application.properties` 中的端口：
```properties
server.port=8081
```

### Q2: 数据库连接失败？

**检查项**：
1. MySQL 是否启动
2. 数据库名、用户名、密码是否正确
3. 端口是否正确（默认 3306）

### Q3: 实体类字段无法映射？

**解决方案**：
- 检查 getter/setter 方法是否存在
- 确认字段类型是否支持
- 查看日志中的具体错误信息

---

## 总结

通过本教程，你学会了：

- ✅ 搭建 Spring Boot 项目环境
- ✅ 配置数据库连接
- ✅ 创建实体类和 Repository
- ✅ 实现 Service 业务逻辑
- ✅ 开发 RESTful API
- ✅ 测试 API 接口

### 完整项目结构

```
demo/
├── src/
│   └── main/
│       ├── java/
│       │   └── com/example/demo/
│       │       ├── controller/
│       │       │   └── UserController.java
│       │       ├── entity/
│       │       │   └── User.java
│       │       ├── repository/
│       │       │   └── UserRepository.java
│       │       ├── service/
│       │       │   ├── UserService.java
│       │       │   └── impl/
│       │       │       └── UserServiceImpl.java
│       │       └── DemoApplication.java
│       └── resources/
│           └── application.properties
└── pom.xml
```

### 下一步学习

- 📘 添加用户认证和授权（Spring Security）
- 📘 实现分页和排序功能
- 📘 添加日志记录
- 📘 编写单元测试和集成测试
- 📘 容器化部署（Docker）

## 参考资料

- [Spring Boot 官方文档](https://spring.io/projects/spring-boot)
- [Spring Data JPA 文档](https://spring.io/projects/spring-data-jpa)
- [MySQL 官方文档](https://dev.mysql.com/doc/)

## 源码下载

完整代码已上传至 GitHub：[项目地址](https://github.com/yourusername/tutorial-demo)

---

**更新记录**：
- 2025-10-01：初始发布

> 💬 如果在学习过程中遇到问题，欢迎在评论区留言！
