---
title: "并发问题排查工具：从JDK工具到Arthas全解析"
date: 2025-11-20T15:00:00+08:00
draft: false
tags: ["Java并发", "问题排查", "工具", "Arthas"]
categories: ["技术"]
description: "掌握并发问题排查的核心工具，从jstack、jconsole到Arthas，快速定位死锁、性能瓶颈等并发问题"
series: ["Java并发编程从入门到精通"]
weight: 37
stage: 5
stageTitle: "问题排查篇"
---

## 一、JDK自带工具

### 1.1 jps：查看Java进程

```bash
# 列出所有Java进程
jps -l

# 输出示例：
# 12345 com.example.MyApplication
# 67890 org.apache.catalina.startup.Bootstrap

# 参数说明：
# -l：显示完整类名
# -v：显示JVM参数
# -m：显示main方法参数
```

### 1.2 jstack：线程堆栈分析

```bash
# 1. 导出线程堆栈
jstack <pid> > threads.txt

# 2. 检测死锁
jstack <pid> | grep -A 20 "Found one Java-level deadlock"

# 3. 查看线程数
jstack <pid> | grep "java.lang.Thread.State" | wc -l

# 4. 查看BLOCKED线程
jstack <pid> | grep "java.lang.Thread.State: BLOCKED" -A 5
```

**实战案例**：
```bash
# 场景1：CPU 100%排查
# 1. 找到Java进程
jps -l

# 2. 找到CPU占用高的线程
top -Hp <pid>  # Linux
# 输出：线程ID 12345占用CPU 90%

# 3. 转换线程ID为16进制
printf "%x\n" 12345
# 输出：0x3039

# 4. 查找对应线程堆栈
jstack <pid> | grep -A 50 "0x3039"

# 场景2：死锁排查
jstack <pid> | grep -A 50 "Found one Java-level deadlock"
```

### 1.3 jconsole：可视化监控

```bash
# 启动jconsole
jconsole

# 或连接远程JVM
jconsole <hostname>:<port>
```

**核心功能**：
1. **概览**：CPU、内存、线程数、类加载
2. **线程**：
   - 实时线程数
   - 检测死锁按钮
   - 线程详情（状态、堆栈）
3. **VM摘要**：JVM参数、系统属性

**死锁检测**：
- 切换到"线程"选项卡
- 点击"检测死锁"按钮
- 如果有死锁，会显示详细信息

### 1.4 JVisualVM：强大的分析工具

```bash
# 启动jvisualvm
jvisualvm
```

**核心功能**：
1. **监视**：CPU、内存、类、线程实时图表
2. **线程**：
   - 线程时间线（运行、等待、睡眠）
   - 线程dump
   - 死锁检测
3. **采样器**：CPU/内存采样
4. **插件**：支持BTrace、VisualGC等

**实战技巧**：
```bash
# 1. 线程dump分析
# - 右键进程 → 线程Dump
# - 查看所有线程状态

# 2. CPU采样
# - 采样器 → CPU → 启动
# - 运行一段时间后停止
# - 查看热点方法

# 3. 远程监控
# JVM参数：
-Dcom.sun.management.jmxremote
-Dcom.sun.management.jmxremote.port=9999
-Dcom.sun.management.jmxremote.authenticate=false
-Dcom.sun.management.jmxremote.ssl=false
```

---

## 二、Arthas：阿里开源诊断工具

### 2.1 安装与启动

```bash
# 下载arthas-boot.jar
curl -O https://arthas.aliyun.com/arthas-boot.jar

# 启动Arthas
java -jar arthas-boot.jar

# 选择要attach的Java进程
[INFO] arthas-boot version: 3.7.0
[INFO] Found existing java process, please choose one and input the serial number.
* [1]: 12345 com.example.MyApplication
  [2]: 67890 org.apache.catalina.startup.Bootstrap
1
```

### 2.2 核心命令

**1. dashboard：实时看板**
```bash
# 显示系统实时数据
dashboard

# 输出示例：
# ID   NAME                   GROUP       PRIORITY STATE  %CPU  TIME   INTERRUPTED
# 17   pool-1-thread-1        main        5        WAITI  0.0   0:0.10 false
# 18   pool-1-thread-2        main        5        RUNNA  57.0  0:5.06 false

# 按Ctrl+C退出
```

**2. thread：查看线程**
```bash
# 查看所有线程
thread

# 查看最忙的3个线程
thread -n 3

# 查看线程详情
thread <thread-id>

# 查看BLOCKED线程
thread -b

# 查看死锁
thread -b

# 输出示例：
# "Thread-1" Id=11 BLOCKED on java.lang.Object@1234 owned by "Thread-2" Id=12
# "Thread-2" Id=12 BLOCKED on java.lang.Object@5678 owned by "Thread-1" Id=11
```

**3. jad：反编译**
```bash
# 反编译类
jad com.example.MyClass

# 查看特定方法
jad com.example.MyClass myMethod
```

**4. watch：监控方法**
```bash
# 监控方法入参和返回值
watch com.example.MyClass myMethod "{params,returnObj}" -x 2

# 监控方法执行时间
watch com.example.MyClass myMethod "{params,returnObj,throwExp}" -x 2 -b -s -f

# -b：方法调用前
# -s：方法调用后
# -f：方法抛异常后
# -x 2：展开深度2
```

**5. trace：方法调用链**
```bash
# 追踪方法调用链
trace com.example.MyClass myMethod

# 输出示例：
# `---[10.05ms] com.example.MyClass:myMethod()
#     +---[5.02ms] com.example.Service:query()
#     +---[4.98ms] com.example.Repository:select()
```

**6. monitor：方法调用统计**
```bash
# 统计方法调用次数、成功率、平均耗时
monitor -c 5 com.example.MyClass myMethod

# 输出示例：
# Timestamp   Class                Method    Total  Success  Fail  Avg RT(ms)
# 2025-01-21  com.example.MyClass  myMethod  100    95       5     15.5
```

**7. stack：方法调用栈**
```bash
# 查看方法被谁调用
stack com.example.MyClass myMethod
```

---

## 三、第三方工具

### 3.1 MAT（Memory Analyzer Tool）

```bash
# 用途：分析堆dump，排查内存泄漏

# 1. 生成堆dump
jmap -dump:format=b,file=heap.hprof <pid>

# 2. 使用MAT打开heap.hprof

# 3. 分析
# - Leak Suspects：疑似泄漏
# - Dominator Tree：支配树
# - Top Consumers：内存占用Top
```

**实战案例**：
```bash
# 场景：线程泄漏排查
# 1. 生成堆dump
jmap -dump:format=b,file=heap.hprof 12345

# 2. MAT打开，搜索"Thread"
# 3. 查看Thread对象数量
# 4. 分析线程引用链，找到泄漏点
```

### 3.2 async-profiler

```bash
# 用途：低开销的CPU/内存分析

# 1. 下载
wget https://github.com/async-profiler/async-profiler/releases/download/v2.9/async-profiler-2.9-linux-x64.tar.gz
tar -xzf async-profiler-2.9-linux-x64.tar.gz

# 2. 采样CPU（60秒）
./profiler.sh -d 60 -f /tmp/profile.html <pid>

# 3. 查看火焰图
# 浏览器打开 /tmp/profile.html
```

**火焰图解读**：
- 横轴：方法占用CPU时间比例
- 纵轴：调用栈深度
- 颜色：不同类型方法（Java、JVM、Native）

---

## 四、实战案例

### 4.1 案例1：CPU 100%排查

```bash
# 1. 找到Java进程
jps -l
# 输出：12345 com.example.MyApp

# 2. 找到CPU占用高的线程
top -Hp 12345
# 输出：线程ID 12350占用CPU 90%

# 3. 转换线程ID为16进制
printf "%x\n" 12350
# 输出：0x303e

# 4. jstack查找线程堆栈
jstack 12345 | grep -A 50 "0x303e"

# 5. 或使用Arthas
java -jar arthas-boot.jar
thread -n 3  # 查看最忙的3个线程
```

**问题定位**：
- 死循环
- 正则表达式回溯
- 大量字符串拼接

### 4.2 案例2：线程池任务堆积

```bash
# 1. 使用Arthas连接
java -jar arthas-boot.jar

# 2. 查看线程池状态
dashboard

# 3. 找到线程池相关线程
thread | grep "pool-"

# 4. 监控线程池方法
watch java.util.concurrent.ThreadPoolExecutor execute "{params}" -x 2

# 5. 追踪任务执行
trace com.example.MyTask run
```

**问题定位**：
- 任务执行慢
- 线程数不足
- 队列容量小

### 4.3 案例3：死锁排查

```bash
# 方式1：jstack
jstack <pid> | grep -A 50 "Found one Java-level deadlock"

# 方式2：jconsole
# 线程 → 检测死锁

# 方式3：Arthas
java -jar arthas-boot.jar
thread -b  # 查找阻塞线程
```

---

## 五、工具对比与选择

| 工具 | 优点 | 缺点 | 适用场景 |
|-----|------|------|---------|
| **jstack** | 快速、无依赖 | 命令行，需要分析 | 快速排查死锁 |
| **jconsole** | 图形化、简单 | 功能有限 | 实时监控 |
| **JVisualVM** | 功能强大 | 性能开销大 | 详细分析 |
| **Arthas** | 在线诊断、功能丰富 | 需要安装 | 生产环境排查 |
| **MAT** | 内存分析专业 | 需要堆dump | 内存泄漏排查 |
| **async-profiler** | 低开销、火焰图 | 需要编译 | 性能分析 |

**选择建议**：
- **快速排查**：jstack + Arthas
- **实时监控**：jconsole + dashboard
- **详细分析**：JVisualVM + MAT
- **性能分析**：async-profiler

---

## 六、核心排查流程

### 6.1 CPU 100%排查

1. `top -Hp <pid>` → 找到CPU高的线程ID
2. `printf "%x\n" <thread-id>` → 转换为16进制
3. `jstack <pid> | grep "0x<hex-id>"` → 查看堆栈
4. 定位代码 → 修复问题

### 6.2 死锁排查

1. `jstack <pid>` → 查找"Found one Java-level deadlock"
2. 分析等待链 → Thread-1 等 Thread-2，Thread-2 等 Thread-1
3. 定位加锁代码 → 修复锁顺序

### 6.3 线程泄漏排查

1. `jstack <pid>` → 查看线程数
2. `thread | wc -l` → 统计线程数
3. `jmap -dump` → 生成堆dump
4. MAT分析 → 查找Thread对象
5. 定位泄漏点 → 修复问题

---

## 总结

掌握并发问题排查工具是解决线上问题的关键：

**核心工具**：
- ✅ **jstack**：快速查看线程堆栈
- ✅ **jconsole**：实时监控和死锁检测
- ✅ **Arthas**：生产环境在线诊断
- ✅ **MAT**：内存泄漏分析

**实战技巧**：
1. **CPU 100%**：top -Hp → printf → jstack
2. **死锁**：jstack → 查找"Found one Java-level deadlock"
3. **线程泄漏**：jstack → jmap → MAT
4. **性能分析**：Arthas trace → async-profiler

**工具选择**：
- 快速排查：**Arthas**
- 实时监控：**jconsole**
- 详细分析：**JVisualVM**
- 内存分析：**MAT**

**下一篇预告**：我们将深入JMH性能测试，学习如何科学地进行并发性能测试！
