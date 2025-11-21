---
title: "Java并发27：CopyOnWriteArrayList - 写时复制容器"
date: 2025-11-20T23:00:00+08:00
draft: false
tags: ["Java并发", "CopyOnWriteArrayList", "写时复制", "COW"]
categories: ["技术"]
description: "CopyOnWriteArrayList的实现原理、适用场景、性能特点、以及为什么读多写少才能用。"
series: ["Java并发编程从入门到精通"]
weight: 27
stage: 3
stageTitle: "Lock与并发工具篇"
---

## 核心原理：写时复制（Copy-On-Write）

```java
public class CopyOnWriteArrayList<E> {
    private volatile Object[] array;  // 底层数组

    public boolean add(E e) {
        synchronized (lock) {
            Object[] oldArray = getArray();
            int len = oldArray.length;
            Object[] newArray = Arrays.copyOf(oldArray, len + 1);  // 复制
            newArray[len] = e;
            setArray(newArray);  // 切换
            return true;
        }
    }

    public E get(int index) {
        return get(getArray(), index);  // 无锁读取
    }
}
```

**核心思想**：
- **读**：直接读，无锁
- **写**：复制整个数组，修改副本，切换引用

---

## 适用场景

### 场景1：黑白名单
```java
public class BlackList {
    private final CopyOnWriteArrayList<String> list = new CopyOnWriteArrayList<>();

    public void add(String ip) {
        list.add(ip);  // 很少写
    }

    public boolean contains(String ip) {
        return list.contains(ip);  // 频繁读
    }
}
```

### 场景2：监听器列表
```java
public class EventPublisher {
    private final CopyOnWriteArrayList<EventListener> listeners = new CopyOnWriteArrayList<>();

    public void addListener(EventListener listener) {
        listeners.add(listener);  // 很少添加
    }

    public void publishEvent(Event event) {
        for (EventListener listener : listeners) {  // 频繁遍历
            listener.onEvent(event);
        }
    }
}
```

### 场景3：配置管理
```java
public class ConfigManager {
    private final CopyOnWriteArrayList<Config> configs = new CopyOnWriteArrayList<>();

    public void updateConfig(Config config) {
        configs.add(config);  // 偶尔更新
    }

    public Config getConfig(String key) {
        for (Config config : configs) {  // 频繁查询
            if (config.getKey().equals(key)) {
                return config;
            }
        }
        return null;
    }
}
```

---

## 核心特性

### 1. 读操作无锁
```java
// 读操作：直接访问volatile数组
public E get(int index) {
    return get(getArray(), index);  // 无synchronized
}

public Iterator<E> iterator() {
    return new COWIterator<E>(getArray(), 0);  // 快照迭代器
}
```

### 2. 写操作加锁
```java
// 写操作：加锁 + 复制
public boolean add(E e) {
    synchronized (lock) {
        // 1. 复制原数组
        Object[] oldArray = getArray();
        int len = oldArray.length;
        Object[] newArray = Arrays.copyOf(oldArray, len + 1);

        // 2. 修改副本
        newArray[len] = e;

        // 3. 切换引用（原子操作）
        setArray(newArray);
        return true;
    }
}
```

### 3. 快照迭代器
```java
// 迭代器基于创建时的快照
Iterator<String> it = list.iterator();
list.add("new");  // 不影响迭代器

while (it.hasNext()) {
    System.out.println(it.next());  // 不包含"new"
}
```

**特点**：
- ✅ 不会抛`ConcurrentModificationException`
- ✅ 弱一致性（看到的是旧数据）

---

## 性能分析

### 读写性能对比
```java
// 测试：10个线程，90%读 + 10%写
ArrayList + synchronized:  1200ms
CopyOnWriteArrayList:      350ms

// 测试：10个线程，10%读 + 90%写
ArrayList + synchronized:  1500ms
CopyOnWriteArrayList:      8900ms  ← 性能差
```

### 内存占用
```java
// 每次写操作都复制整个数组
List<String> list = new CopyOnWriteArrayList<>();

// 添加10000个元素
for (int i = 0; i < 10000; i++) {
    list.add("Item" + i);  // 每次add都复制数组
}

// 内存占用：远高于ArrayList
```

---

## 何时使用？

### ✅ 适合的场景
1. **读多写少**（读:写 > 10:1）
2. **数据量小**（< 1000个元素）
3. **不需要实时一致性**（允许短暂的旧数据）

**示例**：
- 黑白名单（很少更新）
- 监听器列表（很少增删）
- 系统配置（很少改变）

### ❌ 不适合的场景
1. **写操作频繁**
2. **数据量大**
3. **需要实时一致性**

**替代方案**：
```java
// 写频繁：使用ConcurrentHashMap
Map<String, String> map = new ConcurrentHashMap<>();

// 需要实时一致性：使用Collections.synchronizedList
List<String> list = Collections.synchronizedList(new ArrayList<>());
```

---

## CopyOnWriteArraySet

```java
public class CopyOnWriteArraySet<E> {
    private final CopyOnWriteArrayList<E> al;  // 底层用COW

    public boolean add(E e) {
        return al.addIfAbsent(e);  // 去重
    }
}
```

**特点**：
- 基于CopyOnWriteArrayList
- add时检查重复（O(n)）
- 适合小集合

---

## 对比其他容器

| 容器 | 读性能 | 写性能 | 一致性 | 内存 |
|-----|-------|-------|--------|------|
| **ArrayList** | 高 | 高 | - | 低 |
| **synchronizedList** | 低 | 低 | 强 | 低 |
| **CopyOnWriteArrayList** | 最高 | 最低 | 弱 | 高 |
| **ConcurrentHashMap** | 高 | 高 | 弱 | 中 |

---

## 实战建议

### 1. 监控数据量
```java
CopyOnWriteArrayList<String> list = new CopyOnWriteArrayList<>();

// 定期检查大小
if (list.size() > 1000) {
    logger.warn("CopyOnWriteArrayList too large: " + list.size());
}
```

### 2. 避免频繁写
```java
// ❌ 不好：循环中频繁写
for (int i = 0; i < 10000; i++) {
    list.add("Item" + i);  // 每次复制数组
}

// ✅ 好：批量写
List<String> temp = new ArrayList<>();
for (int i = 0; i < 10000; i++) {
    temp.add("Item" + i);
}
list.addAll(temp);  // 只复制一次
```

### 3. 注意一致性
```java
// 弱一致性：可能读到旧数据
list.add("new");
// 其他线程可能暂时看不到"new"
```

---

## 总结

**核心要点**：
1. 写时复制，读无锁
2. 适合读多写少（90%+读）
3. 数据量要小（< 1000）
4. 弱一致性（旧数据）

**使用场景**：
- ✅ 黑白名单
- ✅ 监听器列表
- ✅ 系统配置

**禁用场景**：
- ❌ 写操作频繁
- ❌ 数据量大
- ❌ 需要强一致性

**第三阶段完成**：恭喜完成Lock与并发工具篇！

---

**系列文章**：
- 上一篇：[Java并发26：Phaser高级同步器](/java-concurrency/posts/26-phaser/)
- 下一篇：[Java并发28：CompletableFuture异步编程](/java-concurrency/posts/28-completablefuture/) （第四阶段开始）
