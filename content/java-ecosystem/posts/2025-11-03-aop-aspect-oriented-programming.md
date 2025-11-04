---
title: AOP深度解析：从代码重复到面向切面编程
date: 2025-11-03T10:00:00+08:00s
draft: false
tags:
  - Spring
  - AOP
  - 动态代理
  - 切面编程
  - 第一性原理
categories:
  - 技术
description: 从第一性原理出发，深度剖析AOP如何解决代码重复问题。手写JDK动态代理和CGLIB代理，深入Spring AOP实现原理，实战自定义注解+AOP实现统一日志、权限、性能监控。
series:
  - Spring第一性原理
weight: 3
---

## 引子：一个方法的六段重复代码

假设你要实现一个转账方法，按照传统方式，代码可能是这样的：

```java
public void transfer(String from, String to, BigDecimal amount) {
    // ========== 重复代码1：日志记录 ==========
    log.info("开始转账：{} -> {}，金额：{}", from, to, amount);
    long startTime = System.currentTimeMillis();

    try {
        // ========== 重复代码2：权限校验 ==========
        User currentUser = SecurityContext.getCurrentUser();
        if (!currentUser.hasPermission("TRANSFER")) {
            throw new PermissionDeniedException("无转账权限");
        }

        // ========== 重复代码3：参数校验 ==========
        if (amount.compareTo(BigDecimal.ZERO) <= 0) {
            throw new IllegalArgumentException("金额必须大于0");
        }

        // ========== 重复代码4：事务管理 ==========
        Connection conn = dataSource.getConnection();
        try {
            conn.setAutoCommit(false);

            // ========== 核心业务逻辑（只占20%） ==========
            Account fromAccount = accountDao.getByName(from);
            Account toAccount = accountDao.getByName(to);

            fromAccount.setBalance(fromAccount.getBalance().subtract(amount));
            toAccount.setBalance(toAccount.getBalance().add(amount));

            accountDao.update(fromAccount);
            accountDao.update(toAccount);
            // =============================================

            conn.commit();
        } catch (Exception e) {
            conn.rollback();
            throw e;
        } finally {
            conn.close();
        }

    } catch (Exception e) {
        // ========== 重复代码5：异常处理 ==========
        log.error("转账失败", e);
        throw new BusinessException("转账失败：" + e.getMessage());

    } finally {
        // ========== 重复代码6：性能监控 ==========
        long endTime = System.currentTimeMillis();
        log.info("转账完成，耗时：{}ms", endTime - startTime);
    }
}
```

**问题**：
- 100行代码，核心业务逻辑只有10行（10%）
- 其他90行都是框架代码（日志、权限、事务、异常、监控）
- 每个方法都要写这些重复代码

**如果用AOP**：

```java
@Transactional
@RequirePermission("TRANSFER")
@Loggable
@PerformanceMonitor
public void transfer(String from, String to, BigDecimal amount) {
    // 100%纯粹的业务逻辑（10行）
    Account fromAccount = accountDao.getByName(from);
    Account toAccount = accountDao.getByName(to);

    fromAccount.setBalance(fromAccount.getBalance().subtract(amount));
    toAccount.setBalance(toAccount.getBalance().add(amount));

    accountDao.update(fromAccount);
    accountDao.update(toAccount);
}
```

**对比**：
- 代码减少90%（100行 → 10行）
- 框架代码通过AOP复用
- 业务逻辑清晰可见

**今天我们将深度剖析AOP如何做到这一点！**

---

## 一、横切关注点的困境

### 1.1 什么是横切关注点？

**业务系统的两类关注点**：

```
核心关注点（Core Concerns）：
├─ 业务逻辑（转账、下单、查询）
├─ 数据处理（CRUD）
└─ 领域模型（Account、Order、User）

横切关注点（Cross-cutting Concerns）：
├─ 日志记录（Logging）
├─ 权限控制（Security）
├─ 事务管理（Transaction）
├─ 异常处理（Exception Handling）
├─ 性能监控（Performance Monitoring）
├─ 缓存管理（Caching）
└─ 分布式追踪（Distributed Tracing）
```

**横切关注点的特点**：
- ✅ 不属于核心业务逻辑
- ✅ 在多个模块中重复出现
- ✅ 难以用传统OOP封装

### 1.2 传统OOP的困境

**问题1：代码重复**

```java
// UserService
public class UserService {
    public void createUser(User user) {
        log.info("开始创建用户");
        checkPermission("CREATE_USER");
        beginTransaction();
        try {
            // 业务逻辑
            userDao.insert(user);
            commit();
        } catch (Exception e) {
            rollback();
            throw e;
        }
    }

    public void updateUser(User user) {
        log.info("开始更新用户");
        checkPermission("UPDATE_USER");
        beginTransaction();
        try {
            // 业务逻辑
            userDao.update(user);
            commit();
        } catch (Exception e) {
            rollback();
            throw e;
        }
    }
}

// OrderService - 同样的重复代码
public class OrderService {
    public void createOrder(Order order) {
        log.info("开始创建订单");
        checkPermission("CREATE_ORDER");
        beginTransaction();
        try {
            // 业务逻辑
            orderDao.insert(order);
            commit();
        } catch (Exception e) {
            rollback();
            throw e;
        }
    }
}
```

**统计**：
- 3个方法，每个方法都有相同的日志、权限、事务代码
- 重复代码：**60行**
- 核心业务逻辑：**3行**
- 代码重复率：**95%**

**问题2：代码混杂**

```java
public void createOrder(Order order) {
    // 第1行：日志
    // 第2行：权限
    // 第3-5行：事务开始
    // 第6行：参数校验
    // 第7-10行：核心业务逻辑 ← 只有这4行是业务逻辑
    // 第11行：事务提交
    // 第12-14行：异常处理
    // 第15-16行：事务回滚
    // 第17行：性能监控
}
```

> **业务逻辑被框架代码淹没了！**

**问题3：难以维护**

```
如果要修改事务管理逻辑（比如改用分布式事务）：
├─ 需要修改UserService的10个方法
├─ 需要修改OrderService的15个方法
├─ 需要修改ProductService的8个方法
├─ ...
└─ 总计：修改100+个方法

风险：
├─ 容易遗漏
├─ 容易出错
└─ 测试工作量巨大
```

### 1.3 问题的本质

**OOP的局限性**：

```
面向对象编程（OOP）擅长处理：
├─ 纵向的业务逻辑（继承、组合）
└─ 数据与行为的封装

面向对象编程（OOP）不擅长处理：
├─ 横向的技术性功能（日志、事务、权限）
└─ 跨模块的重复代码
```

**为什么OOP不擅长？**

```
业务逻辑的组织方式：

UserService
├── createUser()
├── updateUser()
└── deleteUser()

OrderService
├── createOrder()
├── updateOrder()
└── deleteOrder()

横切关注点（日志）的分布：

createUser() → 日志
updateUser() → 日志
deleteUser() → 日志
createOrder() → 日志
updateOrder() → 日志
deleteOrder() → 日志

问题：日志代码散落在6个方法中，无法用继承或组合解决
```

---

## 二、解决方案：代理模式

### 2.1 代理模式基础

**代理模式的核心思想**：

> 在不修改原始对象的情况下，通过代理对象增强功能

```
Client（客户端）
  ↓
Proxy（代理对象）
  ├─ 前置增强（日志、权限）
  ├─ 调用真实对象
  └─ 后置增强（性能监控）
  ↓
RealSubject（真实对象）
```

**静态代理示例**：

```java
/**
 * 接口
 */
interface UserService {
    void createUser(User user);
}

/**
 * 真实对象
 */
class UserServiceImpl implements UserService {
    @Override
    public void createUser(User user) {
        // 纯粹的业务逻辑
        System.out.println("创建用户：" + user.getName());
    }
}

/**
 * 静态代理
 */
class UserServiceProxy implements UserService {

    private UserService target;

    public UserServiceProxy(UserService target) {
        this.target = target;
    }

    @Override
    public void createUser(User user) {
        // 前置增强：日志
        System.out.println("开始创建用户");
        long start = System.currentTimeMillis();

        try {
            // 调用真实对象
            target.createUser(user);

        } finally {
            // 后置增强：性能监控
            long end = System.currentTimeMillis();
            System.out.println("创建用户完成，耗时：" + (end - start) + "ms");
        }
    }
}

// 使用
public class StaticProxyDemo {
    public static void main(String[] args) {
        UserService target = new UserServiceImpl();
        UserService proxy = new UserServiceProxy(target);

        proxy.createUser(new User("张三"));
    }
}
```

**静态代理的问题**：

- ❌ 每个接口都要写一个代理类
- ❌ 代理类代码重复
- ❌ 新增方法需要修改代理类

**解决方案：动态代理**

---

## 三、JDK动态代理

### 3.1 JDK动态代理原理

**核心API**：

```java
// java.lang.reflect.Proxy类
public static Object newProxyInstance(
    ClassLoader loader,        // 类加载器
    Class<?>[] interfaces,     // 代理的接口
    InvocationHandler h        // 调用处理器
)

// InvocationHandler接口
public interface InvocationHandler {
    Object invoke(Object proxy, Method method, Object[] args) throws Throwable;
}
```

**工作原理**：

```
1. Proxy.newProxyInstance() 生成代理类
   └─ 动态生成类：$Proxy0 implements UserService

2. 代理类的方法调用
   └─ proxy.createUser() → InvocationHandler.invoke()

3. InvocationHandler.invoke()
   ├─ 前置增强（日志、权限）
   ├─ method.invoke(target, args)  // 调用真实对象
   └─ 后置增强（性能监控）
```

### 3.2 手写JDK动态代理

```java
/**
 * 手写JDK动态代理 - 完整示例
 */
public class JdkDynamicProxyDemo {

    public static void main(String[] args) {
        // 1. 创建真实对象
        UserService target = new UserServiceImpl();

        // 2. 创建代理对象
        UserService proxy = (UserService) Proxy.newProxyInstance(
            target.getClass().getClassLoader(),
            target.getClass().getInterfaces(),
            new LoggingInvocationHandler(target)
        );

        // 3. 调用代理对象的方法
        proxy.createUser(new User("张三"));
        proxy.updateUser(new User("李四"));

        // 输出：
        // ========================================
        // 开始执行方法: createUser
        // 参数: [User{name='张三'}]
        // 创建用户：张三
        // 方法执行成功，耗时: 5ms
        // ========================================
    }
}

/**
 * 日志增强的InvocationHandler
 */
class LoggingInvocationHandler implements InvocationHandler {

    private Object target;  // 真实对象

    public LoggingInvocationHandler(Object target) {
        this.target = target;
    }

    @Override
    public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
        // 前置增强：日志
        System.out.println("========================================");
        System.out.println("开始执行方法: " + method.getName());
        System.out.println("参数: " + Arrays.toString(args));

        long startTime = System.currentTimeMillis();

        Object result = null;
        try {
            // 调用真实对象的方法
            result = method.invoke(target, args);

            // 后置增强：成功日志
            long endTime = System.currentTimeMillis();
            System.out.println("方法执行成功，耗时: " + (endTime - startTime) + "ms");

        } catch (Exception e) {
            // 异常增强：异常日志
            System.out.println("方法执行失败: " + e.getMessage());
            throw e;

        } finally {
            System.out.println("========================================");
        }

        return result;
    }
}

/**
 * UserService接口
 */
interface UserService {
    void createUser(User user);
    void updateUser(User user);
    User getUser(Long id);
}

/**
 * UserService实现类
 */
class UserServiceImpl implements UserService {

    @Override
    public void createUser(User user) {
        System.out.println("创建用户：" + user.getName());
    }

    @Override
    public void updateUser(User user) {
        System.out.println("更新用户：" + user.getName());
    }

    @Override
    public User getUser(Long id) {
        System.out.println("查询用户：" + id);
        return new User("测试用户");
    }
}

/**
 * User实体类
 */
class User {
    private String name;

    public User(String name) {
        this.name = name;
    }

    public String getName() {
        return name;
    }

    @Override
    public String toString() {
        return "User{name='" + name + "'}";
    }
}
```

### 3.3 多种增强组合

```java
/**
 * 组合多种增强：日志 + 性能监控 + 事务
 */
class CompositeInvocationHandler implements InvocationHandler {

    private Object target;

    public CompositeInvocationHandler(Object target) {
        this.target = target;
    }

    @Override
    public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
        // 1. 日志增强
        System.out.println("[LOG] 开始执行: " + method.getName());

        // 2. 性能监控增强
        long startTime = System.currentTimeMillis();

        // 3. 事务增强
        boolean transactionStarted = false;
        try {
            System.out.println("[TX] 开始事务");
            transactionStarted = true;

            // 调用真实对象
            Object result = method.invoke(target, args);

            // 事务提交
            System.out.println("[TX] 提交事务");

            return result;

        } catch (Exception e) {
            // 事务回滚
            if (transactionStarted) {
                System.out.println("[TX] 回滚事务");
            }
            throw e;

        } finally {
            // 性能监控
            long endTime = System.currentTimeMillis();
            System.out.println("[PERF] 耗时: " + (endTime - startTime) + "ms");

            // 日志
            System.out.println("[LOG] 执行完成");
        }
    }
}
```

### 3.4 JDK动态代理的限制

**限制1：必须有接口**

```java
// ✅ 有接口，可以使用JDK动态代理
interface UserService {
    void createUser(User user);
}
class UserServiceImpl implements UserService { }

// ❌ 没有接口，无法使用JDK动态代理
class UserService {
    void createUser(User user) { }
}
```

**限制2：只能代理接口中的方法**

```java
interface UserService {
    void createUser(User user);
}

class UserServiceImpl implements UserService {
    @Override
    public void createUser(User user) { }

    // 这个方法不在接口中，无法被代理
    public void internalMethod() { }
}
```

**解决方案：CGLIB代理**

---

## 四、CGLIB代理

### 4.1 CGLIB原理

**CGLIB（Code Generation Library）**：
- 基于**字节码**生成
- 通过**继承**目标类来创建代理
- **不需要接口**

**工作原理**：

```
1. CGLIB生成目标类的子类
   └─ class UserService$$EnhancerByCGLIB$$1234 extends UserService

2. 子类重写所有public方法
   └─ @Override public void createUser(User user) {
         // 调用MethodInterceptor
      }

3. MethodInterceptor拦截方法调用
   ├─ 前置增强
   ├─ methodProxy.invokeSuper()  // 调用父类方法
   └─ 后置增强
```

### 4.2 手写CGLIB代理

```java
import net.sf.cglib.proxy.Enhancer;
import net.sf.cglib.proxy.MethodInterceptor;
import net.sf.cglib.proxy.MethodProxy;

import java.lang.reflect.Method;

/**
 * 手写CGLIB代理 - 完整示例
 */
public class CglibDynamicProxyDemo {

    public static void main(String[] args) {
        // 1. 创建Enhancer
        Enhancer enhancer = new Enhancer();

        // 2. 设置父类（要代理的类）
        enhancer.setSuperclass(UserService.class);

        // 3. 设置回调（MethodInterceptor）
        enhancer.setCallback(new LoggingMethodInterceptor());

        // 4. 创建代理对象
        UserService proxy = (UserService) enhancer.create();

        // 5. 调用代理对象的方法
        proxy.createUser(new User("张三"));
        proxy.updateUser(new User("李四"));

        // 输出：
        // ========================================
        // 开始执行方法: createUser
        // 创建用户：张三
        // 方法执行成功，耗时: 5ms
        // ========================================
    }
}

/**
 * 日志增强的MethodInterceptor
 */
class LoggingMethodInterceptor implements MethodInterceptor {

    @Override
    public Object intercept(Object obj, Method method, Object[] args, MethodProxy proxy)
            throws Throwable {

        // 前置增强：日志
        System.out.println("========================================");
        System.out.println("开始执行方法: " + method.getName());

        long startTime = System.currentTimeMillis();

        Object result = null;
        try {
            // 调用父类方法（真实对象的方法）
            result = proxy.invokeSuper(obj, args);

            // 后置增强：成功日志
            long endTime = System.currentTimeMillis();
            System.out.println("方法执行成功，耗时: " + (endTime - startTime) + "ms");

        } catch (Exception e) {
            // 异常增强：异常日志
            System.out.println("方法执行失败: " + e.getMessage());
            throw e;

        } finally {
            System.out.println("========================================");
        }

        return result;
    }
}

/**
 * UserService类（没有接口）
 */
class UserService {

    public void createUser(User user) {
        System.out.println("创建用户：" + user.getName());
    }

    public void updateUser(User user) {
        System.out.println("更新用户：" + user.getName());
    }

    public User getUser(Long id) {
        System.out.println("查询用户：" + id);
        return new User("测试用户");
    }
}
```

### 4.3 JDK动态代理 vs CGLIB代理

| 维度 | JDK动态代理 | CGLIB代理 | 推荐 |
|------|-----------|----------|------|
| **实现方式** | 实现接口 | 继承类 | - |
| **接口要求** | **必须有接口** | 不需要接口 | CGLIB更灵活 |
| **性能** | 稍慢 | 稍快 | CGLIB略优 |
| **限制** | 只能代理接口方法 | 不能代理final类/方法 | - |
| **字节码** | Proxy类生成 | CGLIB生成 | - |
| **Spring默认** | 有接口时使用 | 无接口时使用 | 自动选择 |

**Spring的选择策略**：

```java
// Spring AOP代理选择逻辑
if (目标类有接口) {
    // 使用JDK动态代理
    Proxy.newProxyInstance(...);
} else {
    // 使用CGLIB代理
    Enhancer enhancer = new Enhancer();
    enhancer.create();
}

// 强制使用CGLIB（配置）
@EnableAspectJAutoProxy(proxyTargetClass = true)
```

---

## 五、Spring AOP核心概念

### 5.1 AOP术语

| 术语 | 英文 | 说明 | 示例 |
|------|-----|------|------|
| **切面** | Aspect | 横切关注点的模块化 | 日志切面、事务切面 |
| **连接点** | Join Point | 程序执行的某个点 | 方法调用、异常抛出 |
| **切点** | Pointcut | 匹配连接点的表达式 | `execution(* com.example..*.*(..))` |
| **通知** | Advice | 在切点执行的增强代码 | @Before、@After、@Around |
| **目标对象** | Target Object | 被代理的原始对象 | UserServiceImpl |
| **代理对象** | Proxy Object | AOP框架创建的对象 | UserServiceProxy |
| **织入** | Weaving | 把切面应用到目标对象的过程 | 编译时、类加载时、运行时 |

### 5.2 通知类型

```java
@Aspect
@Component
public class LoggingAspect {

    /**
     * 前置通知：方法执行前
     */
    @Before("execution(* com.example.service.*.*(..))")
    public void before(JoinPoint joinPoint) {
        System.out.println("Before: " + joinPoint.getSignature());
    }

    /**
     * 后置通知：方法执行后（无论成功或失败）
     */
    @After("execution(* com.example.service.*.*(..))")
    public void after(JoinPoint joinPoint) {
        System.out.println("After: " + joinPoint.getSignature());
    }

    /**
     * 返回通知：方法成功返回后
     */
    @AfterReturning(
        pointcut = "execution(* com.example.service.*.*(..))",
        returning = "result"
    )
    public void afterReturning(JoinPoint joinPoint, Object result) {
        System.out.println("AfterReturning: " + result);
    }

    /**
     * 异常通知：方法抛出异常后
     */
    @AfterThrowing(
        pointcut = "execution(* com.example.service.*.*(..))",
        throwing = "ex"
    )
    public void afterThrowing(JoinPoint joinPoint, Exception ex) {
        System.out.println("AfterThrowing: " + ex.getMessage());
    }

    /**
     * 环绕通知：最强大的通知，可以完全控制方法执行
     */
    @Around("execution(* com.example.service.*.*(..))")
    public Object around(ProceedingJoinPoint pjp) throws Throwable {
        System.out.println("Around Before");

        Object result = null;
        try {
            // 执行目标方法
            result = pjp.proceed();

            System.out.println("Around AfterReturning");
        } catch (Exception e) {
            System.out.println("Around AfterThrowing");
            throw e;
        } finally {
            System.out.println("Around After");
        }

        return result;
    }
}
```

**通知执行顺序**：

```
正常流程：
  @Around Before
  @Before
  目标方法执行
  @AfterReturning
  @After
  @Around AfterReturning
  @Around After

异常流程：
  @Around Before
  @Before
  目标方法执行（抛出异常）
  @AfterThrowing
  @After
  @Around AfterThrowing
  @Around After
```

### 5.3 切点表达式

**execution表达式**：

```java
// 完整格式
execution(modifiers-pattern? ret-type-pattern declaring-type-pattern?
          name-pattern(param-pattern) throws-pattern?)

// 示例1：匹配所有public方法
execution(public * *(..))

// 示例2：匹配所有set开头的方法
execution(* set*(..))

// 示例3：匹配com.example.service包下所有类的所有方法
execution(* com.example.service.*.*(..))

// 示例4：匹配com.example.service包及子包下所有类的所有方法
execution(* com.example.service..*.*(..))

// 示例5：匹配UserService的所有方法
execution(* com.example.service.UserService.*(..))

// 示例6：匹配UserService的createUser方法
execution(* com.example.service.UserService.createUser(..))

// 示例7：匹配参数为String的方法
execution(* *(String))

// 示例8：匹配参数为String,int的方法
execution(* *(String, int))

// 示例9：匹配返回值为User的方法
execution(User *(..))
```

**@annotation表达式**：

```java
// 匹配标注了@Loggable注解的方法
@Around("@annotation(com.example.annotation.Loggable)")
public Object logMethod(ProceedingJoinPoint pjp) { }

// 匹配标注了@Transactional注解的方法
@Around("@annotation(org.springframework.transaction.annotation.Transactional)")
public Object handleTransaction(ProceedingJoinPoint pjp) { }
```

**within表达式**：

```java
// 匹配com.example.service包下所有类
@Before("within(com.example.service.*)")

// 匹配com.example.service包及子包下所有类
@Before("within(com.example.service..*)")

// 匹配UserService类的所有方法
@Before("within(com.example.service.UserService)")
```

**组合表达式**：

```java
// AND：同时满足多个条件
@Around("execution(* com.example.service.*.*(..)) && @annotation(Loggable)")

// OR：满足任一条件
@Around("execution(* com.example.service.*.*(..)) || execution(* com.example.dao.*.*(..))")

// NOT：不满足条件
@Around("execution(* com.example.service.*.*(..)) && !execution(* com.example.service.Internal*.*(..))")
```

---

## 六、Spring AOP实现原理

### 6.1 ProxyFactory核心流程

```java
/**
 * Spring AOP代理创建流程（简化）
 */
public class ProxyFactoryDemo {

    public static void main(String[] args) {
        // 1. 创建目标对象
        UserService target = new UserServiceImpl();

        // 2. 创建ProxyFactory
        ProxyFactory proxyFactory = new ProxyFactory(target);

        // 3. 添加Advice（通知）
        proxyFactory.addAdvice(new MethodBeforeAdvice() {
            @Override
            public void before(Method method, Object[] args, Object target) {
                System.out.println("Before: " + method.getName());
            }
        });

        // 4. 获取代理对象
        UserService proxy = (UserService) proxyFactory.getProxy();

        // 5. 调用代理方法
        proxy.createUser(new User("张三"));
    }
}
```

### 6.2 Spring AOP代理创建源码分析

```java
/**
 * AbstractAutoProxyCreator - Spring AOP自动代理创建器
 */
public abstract class AbstractAutoProxyCreator implements BeanPostProcessor {

    @Override
    public Object postProcessAfterInitialization(Object bean, String beanName) {
        if (bean != null) {
            // 1. 获取所有Advisor（切面）
            Object[] specificInterceptors = getAdvicesAndAdvisorsForBean(
                bean.getClass(), beanName, null
            );

            // 2. 如果有匹配的Advisor，创建代理
            if (specificInterceptors != DO_NOT_PROXY) {
                return createProxy(
                    bean.getClass(),
                    beanName,
                    specificInterceptors,
                    new SingletonTargetSource(bean)
                );
            }
        }

        return bean;
    }

    /**
     * 创建代理
     */
    protected Object createProxy(Class<?> beanClass, String beanName,
            Object[] specificInterceptors, TargetSource targetSource) {

        // 1. 创建ProxyFactory
        ProxyFactory proxyFactory = new ProxyFactory();

        // 2. 设置目标对象
        proxyFactory.setTargetSource(targetSource);

        // 3. 添加所有Advisor
        Advisor[] advisors = buildAdvisors(beanName, specificInterceptors);
        proxyFactory.addAdvisors(advisors);

        // 4. 决定使用JDK动态代理还是CGLIB
        if (beanClass.isInterface() || Proxy.isProxyClass(beanClass)) {
            // 使用JDK动态代理
            proxyFactory.setInterfaces(ClassUtils.getAllInterfaces(bean));
        } else {
            // 使用CGLIB
            proxyFactory.setProxyTargetClass(true);
        }

        // 5. 创建代理对象
        return proxyFactory.getProxy(getProxyClassLoader());
    }
}

/**
 * ProxyFactory - 代理工厂
 */
public class ProxyFactory extends ProxyCreatorSupport {

    public Object getProxy(ClassLoader classLoader) {
        // 创建AopProxy
        return createAopProxy().getProxy(classLoader);
    }

    protected final synchronized AopProxy createAopProxy() {
        // 根据配置选择JDK动态代理或CGLIB
        return getAopProxyFactory().createAopProxy(this);
    }
}

/**
 * DefaultAopProxyFactory - AOP代理工厂
 */
public class DefaultAopProxyFactory implements AopProxyFactory {

    @Override
    public AopProxy createAopProxy(AdvisedSupport config) {
        // 判断使用哪种代理方式
        if (config.isOptimize() ||
            config.isProxyTargetClass() ||
            hasNoUserSuppliedProxyInterfaces(config)) {

            // 使用CGLIB代理
            return new CglibAopProxy(config);
        } else {
            // 使用JDK动态代理
            return new JdkDynamicAopProxy(config);
        }
    }
}
```

### 6.3 AOP代理调用流程

```
用户调用代理方法：
  proxy.createUser(user)
  ↓
JdkDynamicAopProxy.invoke() 或 CglibAopProxy.intercept()
  ↓
获取拦截器链：
  List<Object> chain = this.advised.getInterceptorsAndDynamicInterceptionAdvice()
  ↓
创建方法调用对象：
  MethodInvocation invocation = new ReflectiveMethodInvocation(...)
  ↓
执行拦截器链：
  invocation.proceed()
  ├─ @Around Before
  ├─ @Before
  ├─ 目标方法执行
  ├─ @AfterReturning
  ├─ @After
  └─ @Around After
```

---

## 七、实战案例

### 7.1 案例1：统一日志处理

```java
/**
 * 自定义注解
 */
@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
public @interface Loggable {
    String value() default "";
    LogLevel level() default LogLevel.INFO;
}

enum LogLevel {
    DEBUG, INFO, WARN, ERROR
}

/**
 * 日志切面
 */
@Aspect
@Component
@Slf4j
public class LoggingAspect {

    @Around("@annotation(loggable)")
    public Object logMethod(ProceedingJoinPoint pjp, Loggable loggable) throws Throwable {
        String methodName = pjp.getSignature().toShortString();
        Object[] args = pjp.getArgs();

        // 前置日志
        log.info("========================================");
        log.info("开始执行: {}", loggable.value().isEmpty() ? methodName : loggable.value());
        log.info("方法: {}", methodName);
        log.info("参数: {}", Arrays.toString(args));

        long startTime = System.currentTimeMillis();

        Object result = null;
        try {
            // 执行目标方法
            result = pjp.proceed();

            // 成功日志
            long endTime = System.currentTimeMillis();
            log.info("执行成功");
            log.info("返回值: {}", result);
            log.info("耗时: {}ms", endTime - startTime);

        } catch (Throwable e) {
            // 异常日志
            log.error("执行失败: {}", e.getMessage(), e);
            throw e;

        } finally {
            log.info("========================================");
        }

        return result;
    }
}

/**
 * 使用示例
 */
@Service
public class UserService {

    @Loggable("创建用户")
    public User createUser(User user) {
        // 纯粹的业务逻辑
        return userRepository.save(user);
    }
}
```

### 7.2 案例2：统一异常处理

```java
/**
 * 异常处理切面
 */
@Aspect
@Component
@Slf4j
public class ExceptionHandlingAspect {

    @AfterThrowing(
        pointcut = "execution(* com.example.service.*.*(..))",
        throwing = "ex"
    )
    public void handleException(JoinPoint joinPoint, Exception ex) {
        String methodName = joinPoint.getSignature().toShortString();
        Object[] args = joinPoint.getArgs();

        // 记录异常日志
        log.error("方法执行异常");
        log.error("方法: {}", methodName);
        log.error("参数: {}", Arrays.toString(args));
        log.error("异常类型: {}", ex.getClass().getName());
        log.error("异常信息: {}", ex.getMessage());
        log.error("异常堆栈: ", ex);

        // 发送告警（可选）
        sendAlert(methodName, ex);

        // 记录到数据库（可选）
        saveErrorLog(methodName, args, ex);
    }

    private void sendAlert(String methodName, Exception ex) {
        // 发送钉钉/邮件/短信告警
    }

    private void saveErrorLog(String methodName, Object[] args, Exception ex) {
        // 保存到error_log表
    }
}
```

### 7.3 案例3：权限控制

```java
/**
 * 权限注解
 */
@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
public @interface RequirePermission {
    String value();  // 权限码
}

/**
 * 权限切面
 */
@Aspect
@Component
public class PermissionAspect {

    @Autowired
    private UserService userService;

    @Before("@annotation(requirePermission)")
    public void checkPermission(JoinPoint joinPoint, RequirePermission requirePermission) {
        // 1. 获取当前用户
        User currentUser = SecurityContext.getCurrentUser();
        if (currentUser == null) {
            throw new UnauthorizedException("未登录");
        }

        // 2. 获取所需权限
        String requiredPermission = requirePermission.value();

        // 3. 检查用户是否具有该权限
        if (!currentUser.hasPermission(requiredPermission)) {
            String methodName = joinPoint.getSignature().toShortString();
            log.warn("权限拒绝: 用户 {} 尝试访问 {}，需要权限: {}",
                currentUser.getId(), methodName, requiredPermission);

            throw new PermissionDeniedException("无权限: " + requiredPermission);
        }

        log.debug("权限校验通过: 用户 {} 具有 {} 权限",
            currentUser.getId(), requiredPermission);
    }
}

/**
 * 使用示例
 */
@Service
public class OrderService {

    @RequirePermission("ORDER:CREATE")
    public Order createOrder(OrderRequest request) {
        // 只有具有ORDER:CREATE权限的用户才能执行
        return orderRepository.save(order);
    }

    @RequirePermission("ORDER:DELETE")
    public void deleteOrder(Long orderId) {
        // 只有具有ORDER:DELETE权限的用户才能执行
        orderRepository.deleteById(orderId);
    }
}
```

### 7.4 案例4：性能监控

```java
/**
 * 性能监控注解
 */
@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
public @interface PerformanceMonitor {
    long threshold() default 1000;  // 慢方法阈值（毫秒）
}

/**
 * 性能监控切面
 */
@Aspect
@Component
@Slf4j
public class PerformanceMonitorAspect {

    @Around("@annotation(monitor)")
    public Object monitorPerformance(ProceedingJoinPoint pjp, PerformanceMonitor monitor)
            throws Throwable {

        String methodName = pjp.getSignature().toShortString();
        long threshold = monitor.threshold();

        long startTime = System.currentTimeMillis();

        try {
            // 执行目标方法
            return pjp.proceed();

        } finally {
            long endTime = System.currentTimeMillis();
            long duration = endTime - startTime;

            // 如果超过阈值，记录慢方法日志
            if (duration > threshold) {
                log.warn("慢方法警告: {} 执行耗时 {}ms，超过阈值 {}ms",
                    methodName, duration, threshold);

                // 可以发送告警或记录到监控系统
                sendSlowMethodAlert(methodName, duration, threshold);
            } else {
                log.debug("方法 {} 执行耗时 {}ms", methodName, duration);
            }

            // 记录性能指标到监控系统（Prometheus/Grafana）
            recordMetrics(methodName, duration);
        }
    }

    private void sendSlowMethodAlert(String methodName, long duration, long threshold) {
        // 发送慢方法告警
    }

    private void recordMetrics(String methodName, long duration) {
        // 记录到Prometheus
    }
}

/**
 * 使用示例
 */
@Service
public class OrderService {

    @PerformanceMonitor(threshold = 500)  // 超过500ms告警
    public Order createOrder(OrderRequest request) {
        return orderRepository.save(order);
    }
}
```

---

## 八、总结与最佳实践

### 8.1 核心要点总结

**AOP解决的核心问题**：

> 将横切关注点从业务逻辑中分离，实现代码复用和关注点分离

**AOP的本质**：

```
AOP = 代理模式 + 动态织入

代理模式：在不修改原始对象的情况下增强功能
动态织入：运行时动态生成代理对象
```

**两种代理方式**：

| 方式 | 适用场景 | 优势 | 劣势 |
|------|---------|------|------|
| **JDK动态代理** | 目标类有接口 | JDK自带，无依赖 | 必须有接口 |
| **CGLIB代理** | 目标类无接口 | 不需要接口 | 不能代理final类/方法 |

### 8.2 最佳实践

**1. 优先使用@Around**

```java
// ✅ 推荐：使用@Around，可以完全控制方法执行
@Around("@annotation(Loggable)")
public Object log(ProceedingJoinPoint pjp) throws Throwable {
    // 前置逻辑
    Object result = pjp.proceed();
    // 后置逻辑
    return result;
}

// ❌ 不推荐：使用多个通知，难以控制执行顺序
@Before("@annotation(Loggable)")
public void before() { }

@AfterReturning("@annotation(Loggable)")
public void afterReturning() { }
```

**2. 合理使用切点表达式**

```java
// ✅ 推荐：使用@annotation，精确控制
@Around("@annotation(Loggable)")

// ❌ 不推荐：使用execution，范围过大
@Around("execution(* com.example..*(..))")
```

**3. 避免在AOP中抛出未检查异常**

```java
// ✅ 推荐：捕获异常并记录
@Around("@annotation(Loggable)")
public Object log(ProceedingJoinPoint pjp) throws Throwable {
    try {
        return pjp.proceed();
    } catch (Throwable e) {
        log.error("方法执行失败", e);
        throw e;  // 重新抛出
    }
}
```

**4. 注意AOP的性能影响**

```
AOP性能开销：
├─ JDK动态代理：约5-10%
├─ CGLIB代理：约10-15%
└─ 建议：不要在高频调用的方法上使用复杂AOP
```

---

## 下一篇预告

**《Spring Boot自动配置：约定优于配置的威力》**

我们将：
1. 深入@SpringBootApplication注解
2. 揭秘自动配置的加载流程
3. 手写一个自定义Starter
4. 条件装配的完整体系
5. 从0到1创建生产级Spring Boot应用

---

**写在最后**：

AOP是Spring的两大核心之一（另一个是IoC）。

理解AOP的本质：**代理模式 + 动态织入**。

记住：**横切关注点应该与业务逻辑分离**。

这就是AOP带来的价值！