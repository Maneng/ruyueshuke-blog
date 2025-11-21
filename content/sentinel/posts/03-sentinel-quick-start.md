---
title: "Sentinel初相识：5分钟快速上手"
date: 2025-01-21T14:20:00+08:00
draft: false
tags: ["Sentinel", "快速上手", "Hello World"]
categories: ["技术"]
series: ["Sentinel从入门到精通"]
weight: 3
stage: 1
stageTitle: "基础入门篇"
description: "通过最简单的Hello World案例，5分钟体验Sentinel的限流功能"
---

## 引言：第一个Sentinel程序

前两篇我们讲了流量控制的本质和微服务的三大挑战，理论已经足够。现在，让我们撸起袖子，动手写第一个Sentinel程序。

**目标**：用不到20行代码，实现一个每秒只允许1次调用的限流功能。

**效果**：
- 第1秒调用：✅ 成功
- 第2秒调用：✅ 成功
- 同一秒内第2次调用：❌ 被限流

准备好了吗？让我们开始！

---

## 一、Sentinel简介

在动手之前，先简单了解一下Sentinel是什么。

### 1.1 Sentinel的历史

**2012年**：阿里内部诞生，应对双11流量洪峰
**2018年**：开源，贡献给社区
**2019年**：成为Spring Cloud Alibaba核心组件
**2024年**：GitHub Star 23k+，生产环境广泛使用

**核心数据**：
- 阿里内部：6000+ 应用接入
- 日请求量：数十亿次
- 可用性：99.99%

### 1.2 Sentinel的三大特点

**特点1：轻量级**
```
核心库大小：< 1MB
内存占用：< 100MB
性能损耗：< 1ms
```

**特点2：功能全面**
- 流量控制（QPS、并发线程数）
- 熔断降级（慢调用、异常比例）
- 系统保护（CPU、Load、RT）
- 热点防护（参数级限流）
- 集群流控（分布式限流）

**特点3：生态完善**
- Dashboard控制台
- 多种规则持久化方案
- Spring Boot/Cloud/Dubbo适配器

### 1.3 Sentinel vs Hystrix

你可能听说过Netflix的Hystrix（已停止维护）。简单对比一下：

| 维度 | Hystrix | Sentinel |
|------|---------|----------|
| 隔离策略 | 线程池隔离 | 信号量隔离（更轻量） |
| 熔断降级 | 基于异常比例 | 慢调用、异常比例、异常数 |
| 实时监控 | 简单 | 丰富（秒级统计） |
| 动态规则 | 不支持 | 支持（实时生效） |
| 多维度流控 | 不支持 | 支持（QPS、线程数、热点） |
| 社区活跃度 | 已停更 | 活跃维护 |

**结论**：Sentinel是Hystrix的升级版，功能更强大，性能更好。

---

## 二、环境准备

### 2.1 JDK版本

Sentinel支持JDK 8及以上版本：

```bash
# 检查JDK版本
java -version
# 输出示例：
# java version "1.8.0_311"
# 或
# java version "11.0.12"
# 或
# java version "17.0.1"
```

### 2.2 创建Maven项目

使用IDEA或命令行创建Maven项目：

```bash
mvn archetype:generate \
  -DgroupId=com.example \
  -DartifactId=sentinel-demo \
  -DarchetypeArtifactId=maven-archetype-quickstart \
  -DinteractiveMode=false
```

或者直接在IDEA中：
```
File → New → Project → Maven → Create from archetype → quickstart
```

### 2.3 添加Sentinel依赖

编辑`pom.xml`，添加Sentinel核心库：

```xml
<dependencies>
    <!-- Sentinel核心库 -->
    <dependency>
        <groupId>com.alibaba.csp</groupId>
        <artifactId>sentinel-core</artifactId>
        <version>1.8.6</version>
    </dependency>
</dependencies>
```

**版本说明**：
- `1.8.6`：当前最新稳定版（2024年1月）
- 查看最新版本：https://github.com/alibaba/Sentinel/releases

---

## 三、Hello World：最简限流程序

### 3.1 完整代码

创建`SentinelDemo.java`：

```java
package com.example;

import com.alibaba.csp.sentinel.Entry;
import com.alibaba.csp.sentinel.SphU;
import com.alibaba.csp.sentinel.slots.block.BlockException;
import com.alibaba.csp.sentinel.slots.block.RuleConstant;
import com.alibaba.csp.sentinel.slots.block.flow.FlowRule;
import com.alibaba.csp.sentinel.slots.block.flow.FlowRuleManager;

import java.util.ArrayList;
import java.util.List;

public class SentinelDemo {

    public static void main(String[] args) throws InterruptedException {
        // 1. 定义限流规则
        initFlowRules();

        // 2. 模拟10次调用
        for (int i = 1; i <= 10; i++) {
            Entry entry = null;
            try {
                // 3. 定义资源（受保护的代码块）
                entry = SphU.entry("HelloWorld");

                // 4. 业务逻辑
                System.out.println("第" + i + "次调用：成功执行业务逻辑");

            } catch (BlockException ex) {
                // 5. 限流处理
                System.out.println("第" + i + "次调用：被限流了！");

            } finally {
                // 6. 释放资源
                if (entry != null) {
                    entry.exit();
                }
            }

            // 每次调用间隔500ms
            Thread.sleep(500);
        }
    }

    /**
     * 定义限流规则：每秒最多1次调用
     */
    private static void initFlowRules() {
        List<FlowRule> rules = new ArrayList<>();

        FlowRule rule = new FlowRule();
        rule.setResource("HelloWorld");              // 资源名称
        rule.setGrade(RuleConstant.FLOW_GRADE_QPS);  // 限流类型：QPS
        rule.setCount(1);                             // 限流阈值：1次/秒

        rules.add(rule);
        FlowRuleManager.loadRules(rules);  // 加载规则

        System.out.println("限流规则已生效：HelloWorld资源每秒最多1次调用");
    }
}
```

### 3.2 运行程序

点击运行，你会看到类似这样的输出：

```
限流规则已生效：HelloWorld资源每秒最多1次调用
第1次调用：成功执行业务逻辑
第2次调用：成功执行业务逻辑
第3次调用：被限流了！
第4次调用：成功执行业务逻辑
第5次调用：被限流了！
第6次调用：成功执行业务逻辑
第7次调用：被限流了！
第8次调用：成功执行业务逻辑
第9次调用：被限流了！
第10次调用：成功执行业务逻辑
```

**观察规律**：每秒只有1次调用成功，其他的都被限流了。

---

## 四、代码详解

让我们逐行理解这段代码的工作原理。

### 4.1 定义限流规则

```java
private static void initFlowRules() {
    FlowRule rule = new FlowRule();
    rule.setResource("HelloWorld");              // ①
    rule.setGrade(RuleConstant.FLOW_GRADE_QPS);  // ②
    rule.setCount(1);                             // ③

    FlowRuleManager.loadRules(Collections.singletonList(rule));  // ④
}
```

**代码解读**：

① **setResource("HelloWorld")**
   - 指定保护哪个资源
   - 资源名称可以是任意字符串
   - 后面会用这个名称标记代码块

② **setGrade(RuleConstant.FLOW_GRADE_QPS)**
   - 限流类型：QPS（每秒请求数）
   - 还有另一种类型：FLOW_GRADE_THREAD（并发线程数）
   - QPS是最常用的限流方式

③ **setCount(1)**
   - 限流阈值：每秒最多1次调用
   - 可以是任意正数，如10、100、1000

④ **FlowRuleManager.loadRules(...)**
   - 加载规则到Sentinel内核
   - 规则立即生效
   - 可以动态修改（运行时重新加载）

### 4.2 定义资源

```java
Entry entry = null;
try {
    entry = SphU.entry("HelloWorld");  // ①

    // 业务逻辑
    System.out.println("成功执行");

} catch (BlockException ex) {  // ②
    // 限流处理
    System.out.println("被限流了");

} finally {
    if (entry != null) {
        entry.exit();  // ③
    }
}
```

**代码解读**：

① **SphU.entry("HelloWorld")**
   - 定义资源的入口
   - 资源名称必须与规则中的一致
   - 如果通过限流检查，返回Entry对象
   - 如果被限流，抛出BlockException

② **catch (BlockException ex)**
   - 捕获限流异常
   - 在这里实现降级逻辑
   - 可以返回默认值、缓存数据等

③ **entry.exit()**
   - 释放资源
   - **必须在finally中调用**（避免资源泄漏）
   - 类似数据库连接的关闭

### 4.3 资源保护的完整流程

```
调用 SphU.entry("HelloWorld")
         ↓
   检查限流规则
         ↓
    ┌────┴────┐
    |         |
 通过检查   被限流
    |         |
    ↓         ↓
返回Entry  抛出BlockException
    |         |
    ↓         ↓
执行业务  执行降级逻辑
    |
    ↓
entry.exit()
```

---

## 五、运行效果分析

### 5.1 时间线分析

假设从0秒开始运行：

| 时间 | 调用次数 | 结果 | 原因 |
|------|---------|------|------|
| 0.0秒 | 第1次 | ✅ 成功 | 第1秒的第1次调用 |
| 0.5秒 | 第2次 | ✅ 成功 | 第1秒的第2次调用（等待0.5秒后已是第2秒）|
| 1.0秒 | 第3次 | ❌ 限流 | 第2秒的第2次调用（超过1次） |
| 1.5秒 | 第4次 | ✅ 成功 | 第3秒的第1次调用 |
| 2.0秒 | 第5次 | ❌ 限流 | 第4秒的第2次调用（超过1次） |

**关键理解**：
- Sentinel的QPS限流是基于**滑动窗口**的
- 不是固定的"每1秒重置计数器"
- 而是"任意1秒内最多N次"

### 5.2 修改限流阈值

试试把阈值改成2：

```java
rule.setCount(2);  // 每秒最多2次
```

运行结果：

```
第1次调用：成功
第2次调用：成功
第3次调用：成功
第4次调用：被限流了！
第5次调用：成功
第6次调用：被限流了！
...
```

**规律**：每秒2次成功，第3次被限流。

### 5.3 修改调用间隔

试试把间隔改成200ms（每秒5次调用）：

```java
Thread.sleep(200);  // 间隔200ms
```

运行结果（阈值=1）：

```
第1次调用：成功
第2次调用：被限流了！
第3次调用：被限流了！
第4次调用：被限流了！
第5次调用：被限流了！
第6次调用：成功
...
```

**规律**：每5次调用只有1次成功（因为每秒最多1次）。

---

## 六、常见问题

### 6.1 Maven依赖冲突

**问题**：运行时报错`NoClassDefFoundError`

**原因**：Sentinel依赖了其他库（如slf4j），可能与你的项目冲突

**解决**：
```xml
<dependency>
    <groupId>com.alibaba.csp</groupId>
    <artifactId>sentinel-core</artifactId>
    <version>1.8.6</version>
    <exclusions>
        <!-- 排除冲突的依赖 -->
        <exclusion>
            <groupId>org.slf4j</groupId>
            <artifactId>slf4j-api</artifactId>
        </exclusion>
    </exclusions>
</dependency>

<!-- 使用你项目的slf4j版本 -->
<dependency>
    <groupId>org.slf4j</groupId>
    <artifactId>slf4j-api</artifactId>
    <version>1.7.36</version>
</dependency>
```

### 6.2 版本选择

**问题**：应该用哪个版本的Sentinel？

**建议**：

| 场景 | 推荐版本 | 说明 |
|------|---------|------|
| 新项目 | 1.8.6+ | 最新稳定版 |
| Spring Cloud Alibaba | 看SCA版本 | 参考兼容性表 |
| 生产环境 | 至少1.8.0 | 修复了很多bug |

**Spring Cloud Alibaba兼容性**：

| SCA版本 | Sentinel版本 |
|---------|-------------|
| 2021.0.4.0 | 1.8.5 |
| 2021.0.5.0 | 1.8.6 |
| 2022.0.0.0 | 1.8.6 |

查看最新兼容性：https://github.com/alibaba/spring-cloud-alibaba/wiki

### 6.3 资源名称重复

**问题**：两个不同的代码块用了相同的资源名称

```java
// 方法A
Entry entry = SphU.entry("myResource");

// 方法B（另一个文件）
Entry entry = SphU.entry("myResource");  // 同名！
```

**后果**：共享同一个限流规则，互相影响

**解决**：
1. **方案1**：用不同的名称（推荐）
   ```java
   SphU.entry("orderService.createOrder");
   SphU.entry("orderService.queryOrder");
   ```

2. **方案2**：用链路模式区分调用来源（后续讲解）

### 6.4 忘记调用entry.exit()

**问题**：没有在finally中释放Entry

```java
Entry entry = SphU.entry("test");
// 业务逻辑
// 忘记调用 entry.exit()
```

**后果**：
- 资源泄漏
- 统计数据不准确
- 可能导致限流失效

**正确做法**：**始终在finally中调用**

```java
Entry entry = null;
try {
    entry = SphU.entry("test");
    // 业务逻辑
} catch (BlockException ex) {
    // 限流处理
} finally {
    if (entry != null) {
        entry.exit();  // 必须调用
    }
}
```

---

## 七、小结

恭喜你！你已经完成了第一个Sentinel程序。

**回顾一下我们学到的**：

1. **Sentinel的特点**：轻量级、功能全面、生态完善
2. **核心API**：
   - `FlowRule`：定义限流规则
   - `FlowRuleManager.loadRules()`：加载规则
   - `SphU.entry()`：标记资源
   - `entry.exit()`：释放资源
3. **限流效果**：基于滑动窗口，精准控制

**下一篇预告**：《核心概念详解：资源、规则、Context、Entry》

我们将深入理解Sentinel的四大核心概念，建立正确的心智模型。只有理解了这些概念，才能灵活运用Sentinel解决实际问题。

---

## 思考题

1. 如果把`entry.exit()`从finally移到try块末尾，会有什么问题？
2. 一个资源可以配置多个限流规则吗？
3. 如果同时有10个线程调用，限流阈值是1，会发生什么？

欢迎在评论区分享你的理解和实验结果！

---

## 完整代码

本文完整代码已上传GitHub（示例仓库）：
- 代码：https://github.com/example/sentinel-demo
- 分支：`01-quick-start`

你可以clone下来直接运行：
```bash
git clone https://github.com/example/sentinel-demo.git
cd sentinel-demo
git checkout 01-quick-start
mvn clean package
java -jar target/sentinel-demo.jar
```
