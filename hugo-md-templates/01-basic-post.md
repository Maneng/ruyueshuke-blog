---
# ============================================================
# Front Matter - 文章元数据配置
# ============================================================

# 文章标题（必填）- 显示在页面顶部和列表中
title: "这是文章标题 - 请修改为实际标题"

# 发布日期（必填）- 格式：YYYY-MM-DDTHH:MM:SS+08:00
date: 2025-10-01T20:00:00+08:00

# 草稿状态（必填）
# true = 草稿（本地预览可见，但不会被发布）
# false = 正式发布
draft: false

# 标签（可选）- 用于内容分类和搜索，可以有多个
tags: ["标签1", "标签2", "标签3"]

# 分类（可选）- 文章的主要分类
categories: ["技术"]

# 文章描述（可选）- 显示在文章列表和搜索结果中
description: "这是一篇关于 XXX 的文章，主要介绍了..."

# 作者（可选）- 不填则使用配置文件中的默认作者
# author: "maneng"

# 是否显示目录（可选）- 覆盖全局配置
# showtoc: true
# tocopen: false

# 封面图片（可选）
# image: "/images/cover.png"

# 其他可用字段：
# weight: 1  # 排序权重，数字越小越靠前
# slug: "custom-url"  # 自定义URL路径
# aliases: ["/old-url"]  # 旧URL重定向
---

<!--
============================================================
文章正文开始
============================================================
注意：
1. 一级标题（#）已被文章标题使用，正文从二级标题（##）开始
2. 所有示例内容都可以删除或替换
3. 代码块语言标识：java, javascript, python, bash, sql, yaml 等
============================================================
-->

## 前言

在这里写一段简短的前言，介绍文章的背景、目的或动机。

例如：
- 为什么要写这篇文章？
- 解决什么问题？
- 适合什么读者？

**关键要点**：
- ✅ 要点一
- ✅ 要点二
- ✅ 要点三

## 正文内容

### 第一部分：基础概念

在这里介绍基础概念或背景知识。

#### 什么是 XXX？

详细解释核心概念。可以包含：

1. **定义**：简洁明了的定义
2. **特点**：列出主要特征
3. **应用场景**：实际使用场景

> 💡 **提示**：可以用引用块来突出重要信息或提示。

### 第二部分：详细说明

#### 示例 1：文本格式

使用不同的文本格式来强调重点：

- **粗体文本**：用于强调重要内容
- *斜体文本*：用于术语或引用
- `行内代码`：用于代码片段或命令
- ~~删除线~~：用于标记废弃内容

#### 示例 2：代码块

Java 代码示例：

```java
public class Example {
    private String name;

    public Example(String name) {
        this.name = name;
    }

    public void sayHello() {
        System.out.println("Hello, " + name + "!");
    }

    public static void main(String[] args) {
        Example example = new Example("World");
        example.sayHello();
    }
}
```

JavaScript 代码示例：

```javascript
// 函数定义
function greet(name) {
    return `Hello, ${name}!`;
}

// 使用箭头函数
const greetArrow = (name) => `Hello, ${name}!`;

// 调用函数
console.log(greet("World"));
console.log(greetArrow("JavaScript"));
```

Shell 脚本示例：

```bash
#!/bin/bash

# 定义变量
NAME="World"

# 输出问候
echo "Hello, ${NAME}!"

# 条件判断
if [ -f "config.toml" ]; then
    echo "配置文件存在"
else
    echo "配置文件不存在"
fi
```

#### 示例 3：列表

**无序列表**：

- 第一项内容
- 第二项内容
  - 嵌套子项 2.1
  - 嵌套子项 2.2
    - 更深层级的子项
- 第三项内容

**有序列表**：

1. 第一步：做这个
2. 第二步：做那个
3. 第三步：完成操作

**任务列表**：

- [x] 已完成的任务
- [x] 另一个完成的任务
- [ ] 待办任务
- [ ] 另一个待办任务

### 第三部分：实践应用

#### 表格示例

比较不同选项或列出数据：

| 特性 | 选项 A | 选项 B | 选项 C |
|-----|-------|-------|-------|
| 性能 | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| 易用性 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ |
| 成本 | 低 | 中 | 高 |
| 推荐度 | ✅ | ✅ | ⚠️ |

#### 引用示例

引用他人观点或重要信息：

> 学而不思则罔，思而不学则殆。
>
> —— 孔子《论语》

或者引用多段内容：

> **关于学习的思考**
>
> 持续学习是保持竞争力的关键。在技术快速发展的今天，
> 我们需要不断更新知识体系，保持对新技术的敏感度。
>
> 但学习不能只停留在表面，要深入理解原理，
> 这样才能举一反三，应用到实际工作中。

### 第四部分：图片和链接

#### 插入图片

图片需要先放置在 `static/images/` 目录下：

![图片描述文本](/images/example.png)

*图：这是图片的说明文字*

#### 插入链接

- [Hugo 官方文档](https://gohugo.io/documentation/)
- [Markdown 语法指南](https://www.markdownguide.org/)
- [内部链接示例](/posts/my-first-post/)

## 进阶内容

### 代码块带高亮

SQL 示例：

```sql
-- 创建用户表
CREATE TABLE users (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_email (email),
    INDEX idx_username (username)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 查询活跃用户
SELECT
    u.username,
    u.email,
    COUNT(o.id) as order_count
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
WHERE u.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
GROUP BY u.id
HAVING order_count > 0
ORDER BY order_count DESC
LIMIT 10;
```

YAML 配置示例：

```yaml
# 应用配置
app:
  name: "我的应用"
  version: "1.0.0"
  port: 8080

# 数据库配置
database:
  driver: mysql
  host: localhost
  port: 3306
  name: mydb
  username: root
  password: secret
  pool:
    min: 5
    max: 20

# 日志配置
logging:
  level: info
  file: logs/app.log
  max_size: 100  # MB
  max_backups: 10
```

JSON 数据示例：

```json
{
  "user": {
    "id": 1001,
    "username": "maneng",
    "email": "maneng@example.com",
    "roles": ["admin", "user"],
    "profile": {
      "nickname": "码农",
      "avatar": "/images/avatar.png",
      "bio": "Java 后端开发工程师"
    },
    "preferences": {
      "theme": "dark",
      "language": "zh-CN",
      "notifications": true
    }
  }
}
```

### 特殊格式

#### 水平分隔线

可以使用分隔线来分割不同部分：

---

#### 脚注

这是一段包含脚注的文本[^1]，这里还有另一个脚注[^note]。

[^1]: 这是第一个脚注的内容
[^note]: 这是命名脚注的内容，可以包含更多详细信息

#### 高亮文本

使用特殊标记来突出重要内容：

==这段文本被高亮显示==（需要主题支持）

或使用 HTML：

<mark>这段文本被标记为重要</mark>

## 最佳实践

### 写作建议

1. **清晰的结构**
   - 使用合理的标题层级
   - 每个章节有明确的主题
   - 逻辑顺序组织内容

2. **简洁的表达**
   - 避免冗长的句子
   - 使用短段落
   - 适当使用列表和表格

3. **丰富的示例**
   - 提供实际可运行的代码
   - 添加必要的注释
   - 包含常见场景的示例

4. **视觉元素**
   - 适当使用图片和图表
   - 使用引用块突出重点
   - 合理使用格式化文本

### 技术写作技巧

- ✅ **准确性**：确保技术细节准确无误
- ✅ **完整性**：涵盖必要的背景知识
- ✅ **可读性**：使用通俗易懂的语言
- ✅ **可操作性**：提供具体的操作步骤
- ✅ **时效性**：注明技术版本和更新日期

## 总结

在这里对全文进行总结：

1. **主要内容回顾**
   - 要点一
   - 要点二
   - 要点三

2. **关键收获**
   - 学到了什么
   - 解决了什么问题
   - 有哪些实际应用

3. **下一步**
   - 推荐的延伸阅读
   - 相关技术探索方向
   - 后续计划

## 参考资料

列出文章中引用或推荐的资源：

- [资源1标题](https://example.com) - 简短描述
- [资源2标题](https://example.com) - 简短描述
- [资源3标题](https://example.com) - 简短描述

## 相关文章

如果有相关文章，可以在这里列出：

- [相关文章1](/posts/related-post-1/)
- [相关文章2](/posts/related-post-2/)

---

**更新记录**：

- 2025-10-01：初始发布
- 2025-10-15：更新示例代码
- 2025-11-01：补充最佳实践章节

> 💬 如果你有任何问题或建议，欢迎在评论区留言讨论！

<!--
============================================================
模板使用说明
============================================================

1. 复制这个文件到 content/posts/ 目录
2. 重命名为你的文章名（如：spring-boot-tutorial.md）
3. 修改 Front Matter 中的字段
4. 替换或删除示例内容
5. 添加你自己的内容
6. 使用 hugo server -D 预览
7. 确认无误后设置 draft: false 发布

常用命令：
- hugo server -D  # 本地预览（包含草稿）
- hugo            # 构建网站
- hugo new posts/my-post.md  # 创建新文章

祝写作愉快！
============================================================
-->
