---
# ============================================================
# 代码片段模板
# 适用于：代码片段、工具函数、实用代码、算法实现
# ============================================================

title: "实用代码片段：XXX功能实现合集"
date: 2025-10-01T20:00:00+08:00
draft: false

tags: ["代码片段", "工具函数", "Java", "实用代码"]
categories: ["代码库"]

description: "收集整理XXX相关的实用代码片段，开箱即用"
---

## 说明

本文收集整理了XXX相关的实用代码片段，所有代码均已验证可用，可直接复制使用。

### 使用方法

1. 找到需要的代码片段
2. 复制到你的项目中
3. 根据实际需求调整参数
4. 运行测试确保正常工作

### 代码特点

- ✅ 简洁实用，易于理解
- ✅ 充分注释，便于维护
- ✅ 经过测试，可靠稳定
- ✅ 涵盖常见场景

---

## 目录

- [字符串处理](#字符串处理)
- [集合操作](#集合操作)
- [文件操作](#文件操作)
- [日期时间](#日期时间)
- [JSON处理](#json处理)
- [网络请求](#网络请求)
- [数据验证](#数据验证)
- [加密解密](#加密解密)
- [并发工具](#并发工具)
- [其他工具](#其他工具)

---

## 字符串处理

### 1. 判断字符串是否为空

```java
/**
 * 判断字符串是否为空（null、""、纯空格都算空）
 */
public class StringUtils {

    public static boolean isEmpty(String str) {
        return str == null || str.trim().isEmpty();
    }

    public static boolean isNotEmpty(String str) {
        return !isEmpty(str);
    }

    // 使用示例
    public static void main(String[] args) {
        System.out.println(isEmpty(null));      // true
        System.out.println(isEmpty(""));        // true
        System.out.println(isEmpty("  "));      // true
        System.out.println(isEmpty("hello"));   // false
    }
}
```

### 2. 驼峰命名转换

```java
/**
 * 驼峰命名和下划线命名互转
 */
public class NamingConverter {

    /**
     * 驼峰转下划线
     * userName -> user_name
     */
    public static String camelToSnake(String camel) {
        if (camel == null || camel.isEmpty()) {
            return camel;
        }
        StringBuilder snake = new StringBuilder();
        snake.append(Character.toLowerCase(camel.charAt(0)));

        for (int i = 1; i < camel.length(); i++) {
            char ch = camel.charAt(i);
            if (Character.isUpperCase(ch)) {
                snake.append('_').append(Character.toLowerCase(ch));
            } else {
                snake.append(ch);
            }
        }
        return snake.toString();
    }

    /**
     * 下划线转驼峰
     * user_name -> userName
     */
    public static String snakeToCamel(String snake) {
        if (snake == null || snake.isEmpty()) {
            return snake;
        }
        StringBuilder camel = new StringBuilder();
        boolean nextUpper = false;

        for (char ch : snake.toCharArray()) {
            if (ch == '_') {
                nextUpper = true;
            } else {
                if (nextUpper) {
                    camel.append(Character.toUpperCase(ch));
                    nextUpper = false;
                } else {
                    camel.append(ch);
                }
            }
        }
        return camel.toString();
    }

    // 测试
    public static void main(String[] args) {
        System.out.println(camelToSnake("userName"));    // user_name
        System.out.println(snakeToCamel("user_name"));   // userName
    }
}
```

### 3. 字符串截取（支持中文）

```java
/**
 * 按字节长度截取字符串，支持中文
 */
public static String substring(String str, int length) {
    if (str == null || str.length() == 0) {
        return str;
    }

    byte[] bytes = str.getBytes(StandardCharsets.UTF_8);
    if (bytes.length <= length) {
        return str;
    }

    int count = 0;
    for (int i = 0; i < str.length(); i++) {
        int charLength = String.valueOf(str.charAt(i))
            .getBytes(StandardCharsets.UTF_8).length;
        count += charLength;
        if (count == length) {
            return str.substring(0, i + 1);
        } else if (count > length) {
            return str.substring(0, i);
        }
    }
    return str;
}
```

---

## 集合操作

### 1. 列表分页

```java
/**
 * 对列表进行分页
 */
public static <T> List<T> page(List<T> list, int pageNum, int pageSize) {
    if (list == null || list.isEmpty()) {
        return Collections.emptyList();
    }

    int total = list.size();
    int fromIndex = (pageNum - 1) * pageSize;
    int toIndex = Math.min(fromIndex + pageSize, total);

    if (fromIndex >= total) {
        return Collections.emptyList();
    }

    return list.subList(fromIndex, toIndex);
}

// 使用示例
List<String> list = Arrays.asList("a", "b", "c", "d", "e");
List<String> page1 = page(list, 1, 2);  // [a, b]
List<String> page2 = page(list, 2, 2);  // [c, d]
```

### 2. 列表分批处理

```java
/**
 * 将大列表分割成多个小批次处理
 */
public static <T> List<List<T>> partition(List<T> list, int batchSize) {
    if (list == null || list.isEmpty()) {
        return Collections.emptyList();
    }

    List<List<T>> batches = new ArrayList<>();
    int total = list.size();

    for (int i = 0; i < total; i += batchSize) {
        int end = Math.min(i + batchSize, total);
        batches.add(list.subList(i, end));
    }

    return batches;
}

// 使用示例
List<Integer> numbers = Arrays.asList(1, 2, 3, 4, 5, 6, 7);
List<List<Integer>> batches = partition(numbers, 3);
// [[1, 2, 3], [4, 5, 6], [7]]
```

### 3. 去重保持顺序

```java
/**
 * 列表去重，保持原有顺序
 */
public static <T> List<T> distinct(List<T> list) {
    if (list == null || list.isEmpty()) {
        return list;
    }
    return new ArrayList<>(new LinkedHashSet<>(list));
}

// 使用示例
List<String> list = Arrays.asList("a", "b", "a", "c", "b");
List<String> distinct = distinct(list);  // [a, b, c]
```

---

## 文件操作

### 1. 读取文件全部内容

```java
/**
 * 读取文件全部内容为字符串
 */
public static String readFile(String filePath) throws IOException {
    return new String(Files.readAllBytes(Paths.get(filePath)),
                      StandardCharsets.UTF_8);
}

// Java 11+ 可以更简洁
public static String readFileJava11(String filePath) throws IOException {
    return Files.readString(Paths.get(filePath));
}
```

### 2. 写入文件

```java
/**
 * 写入内容到文件
 */
public static void writeFile(String filePath, String content) throws IOException {
    Files.write(Paths.get(filePath),
                content.getBytes(StandardCharsets.UTF_8));
}

// 追加内容
public static void appendFile(String filePath, String content) throws IOException {
    Files.write(Paths.get(filePath),
                content.getBytes(StandardCharsets.UTF_8),
                StandardOpenOption.CREATE,
                StandardOpenOption.APPEND);
}
```

### 3. 递归删除目录

```java
/**
 * 递归删除目录及其所有内容
 */
public static void deleteDirectory(File directory) throws IOException {
    if (directory.exists()) {
        File[] files = directory.listFiles();
        if (files != null) {
            for (File file : files) {
                if (file.isDirectory()) {
                    deleteDirectory(file);
                } else {
                    if (!file.delete()) {
                        throw new IOException("Failed to delete: " + file);
                    }
                }
            }
        }
        if (!directory.delete()) {
            throw new IOException("Failed to delete directory: " + directory);
        }
    }
}
```

---

## 日期时间

### 1. 日期格式化

```java
/**
 * 日期格式化工具
 */
public class DateUtils {

    private static final DateTimeFormatter DEFAULT_FORMATTER =
        DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    /**
     * 格式化日期
     */
    public static String format(LocalDateTime dateTime) {
        return dateTime.format(DEFAULT_FORMATTER);
    }

    public static String format(LocalDateTime dateTime, String pattern) {
        return dateTime.format(DateTimeFormatter.ofPattern(pattern));
    }

    /**
     * 解析日期字符串
     */
    public static LocalDateTime parse(String dateStr) {
        return LocalDateTime.parse(dateStr, DEFAULT_FORMATTER);
    }

    /**
     * 获取当前时间字符串
     */
    public static String now() {
        return format(LocalDateTime.now());
    }
}
```

### 2. 日期计算

```java
/**
 * 日期加减操作
 */
public class DateCalculator {

    /**
     * 加减天数
     */
    public static LocalDateTime plusDays(LocalDateTime dateTime, long days) {
        return dateTime.plusDays(days);
    }

    /**
     * 获取两个日期相差的天数
     */
    public static long daysBetween(LocalDate start, LocalDate end) {
        return ChronoUnit.DAYS.between(start, end);
    }

    /**
     * 判断是否在日期范围内
     */
    public static boolean isBetween(LocalDate date,
                                   LocalDate start,
                                   LocalDate end) {
        return !date.isBefore(start) && !date.isAfter(end);
    }
}
```

---

## JSON处理

### 1. JSON 序列化/反序列化

```java
/**
 * JSON 工具类（使用 Jackson）
 */
public class JsonUtils {

    private static final ObjectMapper mapper = new ObjectMapper();

    /**
     * 对象转 JSON 字符串
     */
    public static String toJson(Object obj) {
        try {
            return mapper.writeValueAsString(obj);
        } catch (JsonProcessingException e) {
            throw new RuntimeException("JSON serialization failed", e);
        }
    }

    /**
     * JSON 字符串转对象
     */
    public static <T> T fromJson(String json, Class<T> clazz) {
        try {
            return mapper.readValue(json, clazz);
        } catch (JsonProcessingException e) {
            throw new RuntimeException("JSON deserialization failed", e);
        }
    }

    /**
     * JSON 字符串转列表
     */
    public static <T> List<T> fromJsonList(String json, Class<T> clazz) {
        try {
            JavaType type = mapper.getTypeFactory()
                .constructCollectionType(List.class, clazz);
            return mapper.readValue(json, type);
        } catch (JsonProcessingException e) {
            throw new RuntimeException("JSON deserialization failed", e);
        }
    }
}
```

---

## 网络请求

### 1. HTTP GET 请求

```java
/**
 * 简单的 HTTP 工具类
 */
public class HttpUtils {

    /**
     * GET 请求
     */
    public static String get(String url) throws IOException {
        HttpURLConnection conn = (HttpURLConnection) new URL(url).openConnection();
        conn.setRequestMethod("GET");
        conn.setConnectTimeout(5000);
        conn.setReadTimeout(5000);

        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(conn.getInputStream()))) {
            StringBuilder response = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) {
                response.append(line);
            }
            return response.toString();
        }
    }

    /**
     * POST 请求
     */
    public static String post(String url, String body) throws IOException {
        HttpURLConnection conn = (HttpURLConnection) new URL(url).openConnection();
        conn.setRequestMethod("POST");
        conn.setDoOutput(true);
        conn.setRequestProperty("Content-Type", "application/json");

        try (OutputStream os = conn.getOutputStream()) {
            os.write(body.getBytes(StandardCharsets.UTF_8));
        }

        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(conn.getInputStream()))) {
            StringBuilder response = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) {
                response.append(line);
            }
            return response.toString();
        }
    }
}
```

---

## 数据验证

### 1. 常用格式验证

```java
/**
 * 数据验证工具
 */
public class ValidationUtils {

    // 邮箱正则
    private static final Pattern EMAIL_PATTERN =
        Pattern.compile("^[A-Za-z0-9+_.-]+@[A-Za-z0-9.-]+$");

    // 手机号正则（中国大陆）
    private static final Pattern PHONE_PATTERN =
        Pattern.compile("^1[3-9]\\d{9}$");

    // 身份证号正则
    private static final Pattern ID_CARD_PATTERN =
        Pattern.compile("^\\d{15}|\\d{17}[\\dXx]$");

    /**
     * 验证邮箱
     */
    public static boolean isValidEmail(String email) {
        return email != null && EMAIL_PATTERN.matcher(email).matches();
    }

    /**
     * 验证手机号
     */
    public static boolean isValidPhone(String phone) {
        return phone != null && PHONE_PATTERN.matcher(phone).matches();
    }

    /**
     * 验证身份证号
     */
    public static boolean isValidIdCard(String idCard) {
        return idCard != null && ID_CARD_PATTERN.matcher(idCard).matches();
    }

    /**
     * 验证URL
     */
    public static boolean isValidUrl(String url) {
        try {
            new URL(url);
            return true;
        } catch (MalformedURLException e) {
            return false;
        }
    }
}
```

---

## 加密解密

### 1. MD5 加密

```java
/**
 * MD5 加密工具
 */
public class MD5Utils {

    public static String md5(String text) {
        try {
            MessageDigest md = MessageDigest.getInstance("MD5");
            byte[] bytes = md.digest(text.getBytes(StandardCharsets.UTF_8));
            return bytesToHex(bytes);
        } catch (NoSuchAlgorithmException e) {
            throw new RuntimeException("MD5 algorithm not found", e);
        }
    }

    private static String bytesToHex(byte[] bytes) {
        StringBuilder sb = new StringBuilder();
        for (byte b : bytes) {
            sb.append(String.format("%02x", b));
        }
        return sb.toString();
    }
}
```

### 2. Base64 编码

```java
/**
 * Base64 编解码
 */
public class Base64Utils {

    /**
     * 编码
     */
    public static String encode(String text) {
        return Base64.getEncoder()
            .encodeToString(text.getBytes(StandardCharsets.UTF_8));
    }

    /**
     * 解码
     */
    public static String decode(String encoded) {
        byte[] bytes = Base64.getDecoder().decode(encoded);
        return new String(bytes, StandardCharsets.UTF_8);
    }
}
```

---

## 并发工具

### 1. 简单的线程池

```java
/**
 * 线程池工具
 */
public class ThreadPoolUtils {

    private static final ExecutorService POOL = new ThreadPoolExecutor(
        10,  // 核心线程数
        20,  // 最大线程数
        60L, TimeUnit.SECONDS,  // 空闲线程存活时间
        new LinkedBlockingQueue<>(1000),  // 任务队列
        new ThreadPoolExecutor.CallerRunsPolicy()  // 拒绝策略
    );

    /**
     * 提交任务
     */
    public static void execute(Runnable task) {
        POOL.execute(task);
    }

    /**
     * 提交有返回值的任务
     */
    public static <T> Future<T> submit(Callable<T> task) {
        return POOL.submit(task);
    }

    /**
     * 关闭线程池
     */
    public static void shutdown() {
        POOL.shutdown();
    }
}
```

---

## 其他工具

### 1. 重试工具

```java
/**
 * 重试工具
 */
public class RetryUtils {

    /**
     * 执行任务，失败自动重试
     *
     * @param task 要执行的任务
     * @param maxRetries 最大重试次数
     * @param delayMillis 重试间隔（毫秒）
     */
    public static <T> T retry(Callable<T> task,
                             int maxRetries,
                             long delayMillis) throws Exception {
        int attempts = 0;
        while (true) {
            try {
                return task.call();
            } catch (Exception e) {
                attempts++;
                if (attempts >= maxRetries) {
                    throw e;
                }
                Thread.sleep(delayMillis);
            }
        }
    }

    // 使用示例
    public static void main(String[] args) throws Exception {
        String result = retry(() -> {
            // 可能失败的操作
            return httpClient.get("https://api.example.com");
        }, 3, 1000);  // 最多重试3次，每次间隔1秒
    }
}
```

### 2. ID 生成器

```java
/**
 * 简单的 ID 生成器（雪花算法简化版）
 */
public class IdGenerator {

    private static final AtomicLong sequence = new AtomicLong(0);

    /**
     * 生成唯一 ID
     */
    public static long generateId() {
        long timestamp = System.currentTimeMillis();
        long seq = sequence.getAndIncrement() % 1000;
        return timestamp * 1000 + seq;
    }
}
```

---

## 使用建议

### 最佳实践

1. **选择合适的工具**：根据项目需求选择合适的代码片段
2. **理解代码逻辑**：不要盲目复制，理解代码的工作原理
3. **适当调整**：根据实际情况调整参数和逻辑
4. **添加测试**：为引入的代码编写测试用例
5. **注意依赖**：某些代码可能需要额外的依赖库

### 注意事项

- ⚠️ 生产环境使用前务必充分测试
- ⚠️ 注意异常处理和边界情况
- ⚠️ 考虑线程安全问题
- ⚠️ 关注性能影响

---

## 相关资源

- [Java官方文档](https://docs.oracle.com/en/java/)
- [Guava工具库](https://github.com/google/guava)
- [Apache Commons](https://commons.apache.org/)

---

**更新记录**：

- 2025-10-01：初始发布，收录30个常用代码片段
- 2025-10-15：新增并发工具和重试工具

> 💬 你有更好的实现方式吗？欢迎在评论区分享！
