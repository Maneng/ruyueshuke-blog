# MySQL从入门到精通 - 模块化专题实施方案

## 📋 项目概述

**专题名称**：MySQL从入门到精通
**模块标识**：`mysql`
**专题图标**：🐬
**配色方案**：`#00758F → #F29111`（MySQL官方品牌色：深蓝到橙色渐变）
**目标定位**：从第一性原理出发，系统化掌握MySQL，从小白成长为数据库专家
**文章总数**：约80篇（8个阶段）
**预计时长**：6-8个月完成全部内容

---

## 🎯 学习路径设计

### 阶段总览

| 阶段 | 名称 | 文章数 | 核心目标 | 难度 |
|-----|------|-------|---------|------|
| 🎯 第一阶段 | 基础入门篇 | 10篇 | 掌握MySQL基础操作和SQL基本语法 | ⭐ |
| 📚 第二阶段 | SQL进阶篇 | 12篇 | 精通复杂查询、多表关联、子查询 | ⭐⭐ |
| 🔍 第三阶段 | 索引与优化篇 | 12篇 | 深入理解索引原理和查询优化 | ⭐⭐⭐ |
| 🔒 第四阶段 | 事务与锁篇 | 10篇 | 掌握事务机制、MVCC、锁机制 | ⭐⭐⭐⭐ |
| 🏗️ 第五阶段 | 架构原理篇 | 12篇 | 理解MySQL内部架构和存储引擎 | ⭐⭐⭐⭐ |
| 🚀 第六阶段 | 高可用实践篇 | 10篇 | 掌握主从复制、集群部署、分库分表 | ⭐⭐⭐⭐ |
| ⚡ 第七阶段 | 性能调优篇 | 12篇 | 生产环境性能优化和问题排查 | ⭐⭐⭐⭐⭐ |
| 💡 第八阶段 | 源码深度篇 | 8篇 | 通过源码理解底层实现（可选） | ⭐⭐⭐⭐⭐ |

---

## 📖 详细文章规划

### 🎯 第一阶段：基础入门篇（10篇）

**阶段目标**：从零开始，建立MySQL的基础认知，掌握基本操作。

| 序号 | 文章标题 | 核心内容 | 学习目标 |
|-----|---------|---------|---------|
| 01 | 什么是数据库？为什么需要数据库？ | - 从文件存储到数据库的演进<br>- 数据库的核心价值（ACID、并发、安全）<br>- 数据库分类（关系型vs非关系型） | 理解数据库存在的意义 |
| 02 | MySQL简介：历史、特点与应用场景 | - MySQL的诞生与发展史<br>- MySQL的核心特点<br>- MySQL vs PostgreSQL vs Oracle<br>- 适用场景分析 | 了解MySQL的定位 |
| 03 | MySQL安装与环境配置 | - Windows/Linux/macOS 安装<br>- Docker快速部署<br>- 配置文件 my.cnf 详解<br>- 常用客户端工具（Workbench、Navicat、DBeaver） | 搭建本地开发环境 |
| 04 | 数据库与表的创建：DDL基础 | - CREATE DATABASE<br>- CREATE TABLE<br>- ALTER TABLE<br>- DROP、TRUNCATE、RENAME | 掌握DDL基本操作 |
| 05 | 数据类型详解：选择合适的数据类型 | - 数值类型（INT、BIGINT、DECIMAL）<br>- 字符串类型（CHAR、VARCHAR、TEXT）<br>- 日期时间类型（DATE、DATETIME、TIMESTAMP）<br>- 数据类型选择原则 | 理解数据类型的底层存储 |
| 06 | 基础增删改查：DML操作入门 | - INSERT：单行插入、批量插入<br>- UPDATE：单表更新、条件更新<br>- DELETE：删除数据<br>- SELECT：基础查询 | 掌握DML基本操作 |
| 07 | 约束与完整性：主键、外键、唯一、非空 | - PRIMARY KEY：主键约束<br>- FOREIGN KEY：外键约束<br>- UNIQUE：唯一约束<br>- NOT NULL：非空约束<br>- DEFAULT：默认值<br>- CHECK：检查约束 | 理解数据完整性的重要性 |
| 08 | 字符集与校对规则 | - 字符集（utf8、utf8mb4）<br>- 校对规则（Collation）<br>- 常见问题：乱码、emoji存储<br>- 最佳实践 | 解决字符集相关问题 |
| 09 | 数据导入导出 | - mysqldump备份工具<br>- LOAD DATA导入CSV<br>- SELECT INTO OUTFILE导出<br>- 第三方工具（Navicat导入导出） | 掌握数据迁移方法 |
| 10 | 第一个完整案例：用户管理系统 | - 需求分析<br>- 表设计（用户表、角色表、权限表）<br>- CRUD操作实现<br>- 数据初始化脚本 | 综合运用基础知识 |

---

### 📚 第二阶段：SQL进阶篇（12篇）

**阶段目标**：精通SQL查询语法，能够编写复杂的业务查询。

| 序号 | 文章标题 | 核心内容 | 学习目标 |
|-----|---------|---------|---------|
| 11 | 单表查询进阶：WHERE条件与运算符 | - 比较运算符（=、<>、>、<、>=、<=）<br>- 逻辑运算符（AND、OR、NOT）<br>- 范围查询（BETWEEN、IN）<br>- 模糊查询（LIKE、REGEXP）<br>- 空值处理（IS NULL、IS NOT NULL） | 掌握复杂条件查询 |
| 12 | 排序与分页：ORDER BY与LIMIT | - ORDER BY 单字段、多字段排序<br>- ASC与DESC<br>- LIMIT分页原理<br>- 深分页性能问题<br>- 分页优化技巧 | 实现高效分页查询 |
| 13 | 聚合函数：COUNT、SUM、AVG、MAX、MIN | - 常用聚合函数详解<br>- COUNT(*)、COUNT(1)、COUNT(列名)的区别<br>- 聚合函数与NULL的处理<br>- DISTINCT去重 | 掌握数据统计分析 |
| 14 | 分组查询：GROUP BY与HAVING | - GROUP BY分组原理<br>- HAVING过滤分组结果<br>- WHERE vs HAVING<br>- 多字段分组<br>- WITH ROLLUP汇总 | 实现分组统计查询 |
| 15 | 多表连接：INNER JOIN、LEFT JOIN、RIGHT JOIN | - 连接的本质：笛卡尔积<br>- INNER JOIN：内连接<br>- LEFT JOIN：左连接<br>- RIGHT JOIN：右连接<br>- FULL JOIN的替代方案<br>- 连接条件 ON vs WHERE | 掌握多表关联查询 |
| 16 | 子查询：嵌套查询与相关子查询 | - 标量子查询<br>- 列子查询（IN、ANY、ALL）<br>- 行子查询<br>- 表子查询<br>- 相关子查询 vs 非相关子查询<br>- EXISTS vs IN 性能对比 | 灵活使用子查询 |
| 17 | 联合查询：UNION与UNION ALL | - UNION去重合并<br>- UNION ALL不去重合并<br>- 使用场景与最佳实践<br>- 性能对比 | 实现多结果集合并 |
| 18 | 窗口函数：ROW_NUMBER、RANK、DENSE_RANK | - 窗口函数概念（MySQL 8.0+）<br>- ROW_NUMBER()：行号<br>- RANK()：排名（有间隔）<br>- DENSE_RANK()：排名（无间隔）<br>- PARTITION BY分组<br>- ORDER BY排序<br>- 实战案例：Top N查询 | 掌握高级分析函数 |
| 19 | 常用字符串函数与日期函数 | **字符串函数**：<br>- CONCAT、SUBSTRING、LENGTH<br>- UPPER、LOWER、TRIM<br>- REPLACE、INSTR、LEFT、RIGHT<br>**日期函数**：<br>- NOW、CURDATE、CURTIME<br>- DATE_FORMAT、STR_TO_DATE<br>- DATE_ADD、DATE_SUB、DATEDIFF | 熟练使用内置函数 |
| 20 | 条件表达式：CASE WHEN与IF | - CASE WHEN简单表达式<br>- CASE WHEN搜索表达式<br>- IF()函数<br>- IFNULL()、NULLIF()<br>- COALESCE()多值判断<br>- 实战案例：数据分类统计 | 实现条件逻辑处理 |
| 21 | 视图：虚拟表的创建与使用 | - 视图的概念与作用<br>- CREATE VIEW创建视图<br>- 视图的更新<br>- 视图的优缺点<br>- 物化视图的替代方案 | 理解视图的应用场景 |
| 22 | 综合实战：电商订单查询系统 | - 需求分析（订单查询、统计报表）<br>- 表设计（订单表、商品表、用户表）<br>- 复杂查询实现<br>- 性能优化初探 | 综合运用SQL进阶知识 |

---

### 🔍 第三阶段：索引与优化篇（12篇）

**阶段目标**：深入理解索引原理，掌握查询优化技巧。

| 序号 | 文章标题 | 核心内容 | 学习目标 |
|-----|---------|---------|---------|
| 23 | 索引的本质：为什么索引能加速查询？ | - 从二分查找到索引<br>- 磁盘IO与查询性能<br>- 索引的代价（存储空间、写入性能）<br>- 索引的适用场景 | 理解索引存在的意义 |
| 24 | B+树详解：MySQL索引的数据结构 | - 二叉树、平衡二叉树、B树的演进<br>- B+树的特点（多路、叶子节点链表）<br>- 为什么MySQL选择B+树？<br>- B+树的高度与查询效率<br>- B+树插入删除原理 | 深入理解B+树原理 |
| 25 | 索引类型：主键索引、唯一索引、普通索引、全文索引 | - 主键索引（聚簇索引）<br>- 唯一索引（UNIQUE）<br>- 普通索引（二级索引）<br>- 全文索引（FULLTEXT）<br>- 聚簇索引 vs 非聚簇索引<br>- 回表查询的概念 | 掌握各类索引的特点 |
| 26 | 创建索引的最佳实践 | - 何时创建索引？<br>- 哪些列适合创建索引？<br>- 索引命名规范<br>- 索引长度限制<br>- 前缀索引的使用<br>- 索引监控与维护 | 学会正确创建索引 |
| 27 | 索引失效的场景分析 | - 违反最左前缀原则<br>- 索引列上使用函数<br>- 隐式类型转换<br>- OR条件的索引失效<br>- LIKE左模糊匹配<br>- 范围查询后的索引失效<br>- 实战案例分析 | 避免索引失效陷阱 |
| 28 | 联合索引：最左前缀原则 | - 联合索引的存储结构<br>- 最左前缀原则详解<br>- 索引顺序的选择<br>- 索引下推（ICP）<br>- 联合索引 vs 多个单列索引 | 掌握联合索引设计 |
| 29 | 覆盖索引：减少回表查询 | - 什么是覆盖索引？<br>- 覆盖索引的优势<br>- 如何设计覆盖索引？<br>- 实战案例：优化慢查询 | 利用覆盖索引优化查询 |
| 30 | 索引下推：ICP优化 | - 索引下推（Index Condition Pushdown）原理<br>- ICP vs 传统索引查询<br>- ICP的适用场景<br>- 如何验证ICP生效？ | 理解ICP优化机制 |
| 31 | EXPLAIN执行计划详解（上）：基础字段 | - EXPLAIN的作用<br>- id：查询标识<br>- select_type：查询类型<br>- table：表名<br>- type：访问类型（system、const、eq_ref、ref、range、index、all）<br>- possible_keys、key：索引选择 | 学会读懂执行计划 |
| 32 | EXPLAIN执行计划详解（下）：高级分析 | - key_len：索引长度<br>- ref：索引引用<br>- rows：扫描行数<br>- filtered：过滤比例<br>- Extra：额外信息（Using index、Using where、Using filesort、Using temporary）<br>- 实战案例分析 | 深入分析执行计划 |
| 33 | 慢查询日志：定位性能瓶颈 | - 慢查询日志配置<br>- slow_query_log、long_query_time<br>- mysqldumpslow分析工具<br>- pt-query-digest工具<br>- 慢查询优化流程 | 掌握慢查询分析方法 |
| 34 | 索引优化实战案例 | - 案例1：分页查询优化<br>- 案例2：多表关联优化<br>- 案例3：范围查询优化<br>- 案例4：排序优化<br>- 案例5：统计查询优化 | 综合运用索引优化技巧 |

---

### 🔒 第四阶段：事务与锁篇（10篇）

**阶段目标**：深入理解事务机制、MVCC、锁机制，解决并发问题。

| 序号 | 文章标题 | 核心内容 | 学习目标 |
|-----|---------|---------|---------|
| 35 | 事务的本质：ACID特性详解 | - 什么是事务？<br>- Atomicity（原子性）：undo log保障<br>- Consistency（一致性）：约束保障<br>- Isolation（隔离性）：锁和MVCC保障<br>- Durability（持久性）：redo log保障<br>- 事务的基本操作（BEGIN、COMMIT、ROLLBACK） | 理解事务的底层原理 |
| 36 | 事务隔离级别：读未提交、读已提交、可重复读、串行化 | - 读未提交（READ UNCOMMITTED）<br>- 读已提交（READ COMMITTED）<br>- 可重复读（REPEATABLE READ）<br>- 串行化（SERIALIZABLE）<br>- 隔离级别的设置<br>- MySQL默认隔离级别 | 掌握事务隔离级别 |
| 37 | 脏读、不可重复读、幻读的本质 | - 脏读：读到未提交的数据<br>- 不可重复读：前后读取结果不一致<br>- 幻读：前后读取记录数不一致<br>- 三者的区别与联系<br>- 各隔离级别能解决的问题 | 理解并发问题的根源 |
| 38 | MVCC多版本并发控制原理 | - MVCC的设计思想<br>- ReadView快照读<br>- 当前读 vs 快照读<br>- 隐藏字段（trx_id、roll_pointer）<br>- 可见性判断算法<br>- MVCC如何解决不可重复读和幻读？ | 深入理解MVCC机制 |
| 39 | undo log与版本链 | - undo log的作用<br>- undo log的存储结构<br>- 版本链的形成<br>- undo log的清理（purge）<br>- undo log与回滚 | 理解多版本数据存储 |
| 40 | 锁的分类：共享锁与排他锁 | - 共享锁（S锁）：读锁<br>- 排他锁（X锁）：写锁<br>- 锁的兼容性<br>- 锁的申请与释放<br>- 手动加锁（SELECT ... LOCK IN SHARE MODE、SELECT ... FOR UPDATE） | 掌握锁的基本概念 |
| 41 | 行锁、表锁、间隙锁、临键锁 | - 表锁：LOCK TABLES<br>- 行锁：InnoDB的锁粒度<br>- 间隙锁（Gap Lock）：锁定范围<br>- 临键锁（Next-Key Lock）：记录锁+间隙锁<br>- 插入意向锁<br>- 如何查看锁信息？ | 理解各类锁的应用场景 |
| 42 | 死锁：产生原因与解决方案 | - 什么是死锁？<br>- 死锁的四个必要条件<br>- 死锁的检测与恢复<br>- 死锁日志分析<br>- 如何避免死锁？<br>- innodb_deadlock_detect参数 | 学会排查和预防死锁 |
| 43 | 乐观锁与悲观锁实践 | - 乐观锁：版本号机制<br>- 悲观锁：SELECT ... FOR UPDATE<br>- 两者的适用场景<br>- CAS（Compare And Swap）<br>- 实战案例：秒杀系统的并发控制 | 掌握并发控制策略 |
| 44 | 事务实战：转账系统的实现 | - 需求分析：A转账给B<br>- 表设计（账户表、流水表）<br>- 事务实现（扣款、入账、记录流水）<br>- 异常处理（余额不足、账户冻结）<br>- 并发控制（防止超卖） | 综合运用事务和锁 |

---

### 🏗️ 第五阶段：架构原理篇（12篇）

**阶段目标**：理解MySQL内部架构，掌握InnoDB存储引擎原理。

| 序号 | 文章标题 | 核心内容 | 学习目标 |
|-----|---------|---------|---------|
| 45 | MySQL架构总览：连接器、查询缓存、分析器、优化器、执行器 | - MySQL分层架构<br>- 连接器：身份认证与权限验证<br>- 查询缓存：已废弃的功能<br>- 分析器：词法分析与语法分析<br>- 优化器：执行计划生成<br>- 执行器：调用存储引擎接口<br>- SQL执行流程 | 理解MySQL整体架构 |
| 46 | 存储引擎对比：InnoDB vs MyISAM | - InnoDB的特点（支持事务、行锁、外键）<br>- MyISAM的特点（不支持事务、表锁）<br>- 存储结构对比<br>- 性能对比<br>- 如何选择存储引擎？<br>- 存储引擎切换 | 掌握存储引擎的选择 |
| 47 | InnoDB存储结构：表空间、段、区、页 | - 表空间（Tablespace）：系统表空间、独立表空间<br>- 段（Segment）：数据段、索引段、回滚段<br>- 区（Extent）：连续的页<br>- 页（Page）：InnoDB的基本IO单位（16KB）<br>- 页的内部结构 | 理解InnoDB的存储层次 |
| 48 | InnoDB行格式：Compact、Redundant、Dynamic | - 行格式的作用<br>- Compact格式：变长字段列表、NULL值列表、记录头信息、真实数据<br>- Redundant格式：旧版格式<br>- Dynamic格式：处理大字段<br>- Compressed格式：压缩存储<br>- 行溢出处理 | 理解数据行的存储格式 |
| 49 | Buffer Pool：MySQL的内存管理 | - Buffer Pool的作用<br>- Buffer Pool的结构（缓冲页、控制块）<br>- 页的管理：Free链表、Flush链表、LRU链表<br>- 预读机制（线性预读、随机预读）<br>- Buffer Pool的配置<br>- innodb_buffer_pool_size的设置 | 理解MySQL的内存管理 |
| 50 | redo log：崩溃恢复的保障 | - redo log的作用：WAL机制<br>- redo log的存储结构<br>- redo log buffer<br>- redo log刷盘时机<br>- innodb_flush_log_at_trx_commit参数<br>- redo log与binlog的区别<br>- 两阶段提交（2PC） | 理解事务持久性的保障 |
| 51 | binlog：主从复制的基础 | - binlog的作用：归档日志<br>- binlog的格式（STATEMENT、ROW、MIXED）<br>- binlog的写入流程<br>- sync_binlog参数<br>- binlog的查看与分析<br>- binlog与数据恢复 | 理解binlog的应用场景 |
| 52 | undo log：回滚与MVCC的实现 | - undo log的作用<br>- undo log的类型（insert、update、delete）<br>- undo log的存储结构<br>- undo log与回滚<br>- undo log与MVCC<br>- undo log的清理 | 理解undo log的双重作用 |
| 53 | Change Buffer：提升写入性能 | - Change Buffer的作用<br>- Change Buffer的工作原理<br>- 适用场景：非唯一二级索引<br>- Change Buffer的配置<br>- Change Buffer vs Buffer Pool | 理解写入优化机制 |
| 54 | Adaptive Hash Index：自适应哈希索引 | - AHI的作用<br>- AHI的工作原理<br>- AHI的适用场景<br>- AHI的性能影响<br>- innodb_adaptive_hash_index参数 | 了解InnoDB的自适应优化 |
| 55 | Double Write Buffer：数据一致性保障 | - 部分写问题（Partial Page Write）<br>- Double Write Buffer的作用<br>- 双写缓冲区的工作流程<br>- 性能影响<br>- innodb_doublewrite参数 | 理解数据一致性保障机制 |
| 56 | MySQL启动与关闭流程 | - MySQL启动流程<br>- 崩溃恢复流程<br>- MySQL关闭流程<br>- 安全关闭 vs 强制关闭<br>- mysqld_safe守护进程 | 理解MySQL的生命周期 |

---

### 🚀 第六阶段：高可用实践篇（10篇）

**阶段目标**：掌握MySQL的高可用架构，实现生产级部署。

| 序号 | 文章标题 | 核心内容 | 学习目标 |
|-----|---------|---------|---------|
| 57 | 主从复制原理：binlog与relay log | - 主从复制的作用<br>- 主从复制的核心组件（IO线程、SQL线程）<br>- binlog的传输<br>- relay log的应用<br>- 主从复制的延迟 | 理解主从复制原理 |
| 58 | 主从复制配置：一主一从实战 | - 主库配置（开启binlog、设置server-id）<br>- 从库配置（设置server-id、指定主库）<br>- 复制用户创建<br>- CHANGE MASTER TO命令<br>- START SLAVE<br>- 主从状态检查 | 掌握主从复制部署 |
| 59 | 主从延迟：原因分析与优化 | - 主从延迟的原因<br>- Seconds_Behind_Master指标<br>- 并行复制（基于组提交、基于WRITESET）<br>- 从库性能优化<br>- 监控主从延迟 | 解决主从延迟问题 |
| 60 | 半同步复制：保障数据一致性 | - 异步复制的问题<br>- 半同步复制原理<br>- rpl_semi_sync插件<br>- 半同步复制配置<br>- 超时降级机制<br>- 半同步复制 vs 全同步复制 | 提升数据一致性 |
| 61 | 组复制（MGR）：MySQL的分布式方案 | - MGR的架构<br>- 单主模式 vs 多主模式<br>- MGR的配置与部署<br>- MGR vs 传统主从复制<br>- MGR的适用场景 | 了解MySQL的分布式方案 |
| 62 | 读写分离架构设计 | - 读写分离的作用<br>- 读写分离的实现方式<br>- 中间件方案（ProxySQL、MaxScale、MyCat）<br>- 应用层方案（ShardingSphere）<br>- 读写分离的问题（主从延迟、数据一致性） | 设计读写分离架构 |
| 63 | 数据库备份策略：全量备份与增量备份 | - 备份的重要性<br>- 逻辑备份（mysqldump）<br>- 物理备份（xtrabackup）<br>- 全量备份 vs 增量备份<br>- 备份策略设计<br>- 备份自动化 | 制定备份策略 |
| 64 | 数据恢复实战：从备份恢复数据 | - 从mysqldump恢复<br>- 从xtrabackup恢复<br>- 增量恢复<br>- binlog恢复<br>- 恢复流程与注意事项 | 掌握数据恢复方法 |
| 65 | 高可用方案对比：MHA、MMM、Orchestrator | - MHA（Master High Availability）<br>- MMM（Multi-Master Replication Manager）<br>- Orchestrator<br>- Keepalived + 主从切换脚本<br>- 云厂商高可用方案（RDS） | 了解高可用解决方案 |
| 66 | 分库分表：应对海量数据 | - 分库分表的适用场景<br>- 垂直拆分 vs 水平拆分<br>- 分片键的选择<br>- 分库分表的问题（分布式事务、跨库查询）<br>- ShardingSphere实战 | 掌握分库分表方案 |

---

### ⚡ 第七阶段：性能调优篇（12篇）

**阶段目标**：掌握MySQL性能调优方法，解决生产环境问题。

| 序号 | 文章标题 | 核心内容 | 学习目标 |
|-----|---------|---------|---------|
| 67 | MySQL性能监控指标 | - QPS、TPS监控<br>- 连接数监控<br>- 缓冲池命中率<br>- 慢查询监控<br>- 锁等待监控<br>- 监控工具（Prometheus + Grafana、PMM） | 建立性能监控体系 |
| 68 | 慢查询优化思路与方法 | - 慢查询分析流程<br>- EXPLAIN执行计划分析<br>- 索引优化<br>- SQL改写<br>- 表结构优化<br>- 实战案例 | 掌握慢查询优化方法 |
| 69 | 表结构设计优化 | - 第三范式与反范式<br>- 字段类型优化<br>- NOT NULL vs NULL<br>- 大字段处理（TEXT、BLOB）<br>- 冗余字段的权衡<br>- 垂直拆分 vs 水平拆分 | 设计高效的表结构 |
| 70 | 大表优化：分区表 | - 分区表的作用<br>- 分区类型（RANGE、LIST、HASH、KEY）<br>- 分区表的创建<br>- 分区表的维护<br>- 分区表的适用场景<br>- 分区表的限制 | 掌握分区表的使用 |
| 71 | JOIN优化：减少关联查询 | - JOIN的性能开销<br>- JOIN顺序优化<br>- 小表驱动大表<br>- 索引优化JOIN<br>- 冗余字段减少JOIN<br>- 分库分表后的JOIN处理 | 优化多表关联查询 |
| 72 | COUNT优化：如何高效统计 | - COUNT(*)、COUNT(1)、COUNT(列名)的性能对比<br>- InnoDB COUNT(*)的实现<br>- COUNT优化方案（缓存、近似值、分页）<br>- 实战案例 | 优化COUNT查询 |
| 73 | 分页查询优化：深分页问题 | - 深分页的性能问题<br>- LIMIT优化方案（延迟关联、子查询、标签记录法）<br>- 游标分页<br>- 实战案例 | 解决深分页问题 |
| 74 | INSERT批量插入优化 | - 批量插入的优势<br>- 批量插入的最佳实践<br>- LOAD DATA INFILE<br>- INSERT ... ON DUPLICATE KEY UPDATE<br>- 事务批量提交<br>- innodb_flush_log_at_trx_commit调优 | 提升写入性能 |
| 75 | 参数调优：innodb_buffer_pool_size等关键参数 | - innodb_buffer_pool_size：缓冲池大小<br>- innodb_log_file_size：redo log大小<br>- innodb_flush_log_at_trx_commit：刷盘策略<br>- sync_binlog：binlog刷盘<br>- max_connections：最大连接数<br>- query_cache_size：查询缓存（已废弃）<br>- 参数调优方法论 | 掌握核心参数调优 |
| 76 | 连接池优化 | - 连接池的作用<br>- HikariCP连接池配置<br>- 连接池大小设置<br>- 连接泄漏检测<br>- 连接池监控 | 优化应用层连接管理 |
| 77 | SQL改写技巧：提升执行效率 | - 避免SELECT *<br>- 小表驱动大表<br>- EXISTS vs IN<br>- OR改写为UNION<br>- 临时表优化<br>- 函数索引（MySQL 8.0+）<br>- 实战案例 | 掌握SQL改写技巧 |
| 78 | 生产环境问题排查案例 | - 案例1：数据库连接数打满<br>- 案例2：慢查询导致锁等待<br>- 案例3：主从延迟<br>- 案例4：磁盘IO过高<br>- 案例5：死锁排查<br>- 排查工具与方法 | 提升问题排查能力 |

---

### 💡 第八阶段：源码深度篇（可选，8篇）

**阶段目标**：通过源码理解MySQL底层实现，达到专家级水平。

| 序号 | 文章标题 | 核心内容 | 学习目标 |
|-----|---------|---------|---------|
| 79 | MySQL源码编译与调试环境搭建 | - 源码下载与目录结构<br>- 编译环境配置<br>- CMake编译<br>- GDB调试环境<br>- CLion/VSCode调试配置 | 搭建源码调试环境 |
| 80 | SQL执行流程源码分析 | - 连接器源码<br>- 分析器源码（词法分析、语法分析）<br>- 优化器源码<br>- 执行器源码<br>- 关键函数调用链 | 理解SQL执行流程实现 |
| 81 | InnoDB存储引擎源码结构 | - InnoDB目录结构<br>- 核心模块（Buffer Pool、Redo Log、Undo Log、Lock）<br>- 关键数据结构<br>- 代码导读 | 了解InnoDB源码结构 |
| 82 | B+树插入删除源码分析 | - B+树的代码实现<br>- 插入操作源码分析<br>- 删除操作源码分析<br>- 页分裂与页合并<br>- 调试跟踪 | 深入理解B+树实现 |
| 83 | MVCC实现源码分析 | - ReadView的创建<br>- 可见性判断算法实现<br>- 版本链的遍历<br>- undo log的读取<br>- 关键函数分析 | 理解MVCC的底层实现 |
| 84 | 锁机制源码分析 | - 锁的数据结构<br>- 锁的申请与释放<br>- 死锁检测算法实现<br>- 锁等待队列<br>- 关键函数分析 | 理解锁机制的实现 |
| 85 | 主从复制源码分析 | - binlog的生成<br>- IO线程的实现<br>- SQL线程的实现<br>- relay log的处理<br>- 半同步复制实现 | 理解主从复制的实现 |
| 86 | 性能优化：从源码角度理解 | - 为什么B+树高度影响性能？<br>- 为什么Buffer Pool如此重要？<br>- 为什么联合索引要遵循最左前缀？<br>- 为什么COUNT(*)慢？<br>- 从源码看优化思路 | 从源码角度理解优化原理 |

---

## 🛠️ 实施步骤

### Step 1: 创建MySQL模块目录结构

```bash
# 1. 创建专题目录和文章子目录
mkdir -p content/mysql/posts

# 2. 创建专题首页 _index.md
# 内容见下方模板
```

### Step 2: 在首页添加MySQL专题卡片

编辑 `layouts/index.html`，参考现有专题卡片格式添加：

```html
{{/* MySQL专题入口卡片 */}}
<article class="mysql-featured-card">
  <div class="mysql-card-content">
    <div class="mysql-card-header">
      <span class="mysql-icon">🐬</span>
      <h2>MySQL从入门到精通</h2>
    </div>
    <div class="mysql-card-tags">
      <span class="tag">🎯 基础入门</span>
      <span class="tag">📚 SQL进阶</span>
      <span class="tag">🔍 索引优化</span>
      <span class="tag">🔒 事务锁</span>
      <span class="tag">🏗️ 架构原理</span>
      <span class="tag">🚀 高可用</span>
    </div>
    <p class="mysql-card-description">
      从第一性原理出发，系统化掌握MySQL，涵盖SQL查询、索引优化、事务锁、架构原理、高可用、性能调优、源码分析八大核心领域，从小白成长为数据库专家。
    </p>
    <div class="mysql-card-footer">
      <a href="{{ "mysql/" | absURL }}" class="mysql-btn">
        进入专题 →
      </a>
      {{- with (site.GetPage "/mysql") }}
      {{- $count := len (where .Site.RegularPages "Section" "mysql") }}
      {{- if gt $count 0 }}
      <span class="mysql-count">{{ $count }} 篇文章</span>
      {{- end }}
      {{- end }}
    </div>
  </div>
</article>
```

### Step 3: 添加样式定义

编辑 `layouts/partials/extend_head.html`，添加MySQL专题样式：

```css
/* MySQL专题卡片样式 - MySQL官方品牌色 */
.mysql-featured-card {
  background: linear-gradient(135deg, #00758F 0%, #F29111 100%);
  border-radius: 16px;
  padding: 32px;
  margin-bottom: 32px;
  box-shadow: 0 10px 40px rgba(0, 117, 143, 0.3);
  transition: transform 0.3s ease, box-shadow 0.3s ease;
  border: none;
  position: relative;
  overflow: hidden;
}

.mysql-featured-card::before {
  content: '';
  position: absolute;
  top: 0;
  right: 0;
  width: 200px;
  height: 200px;
  background: radial-gradient(circle, rgba(255,255,255,0.1) 0%, transparent 70%);
  border-radius: 50%;
  transform: translate(50%, -50%);
}

.mysql-featured-card:hover {
  transform: translateY(-4px);
  box-shadow: 0 15px 50px rgba(0, 117, 143, 0.4);
}

.mysql-card-content {
  position: relative;
  z-index: 1;
}

.mysql-card-header {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-bottom: 20px;
}

.mysql-icon {
  font-size: 32px;
  line-height: 1;
}

.mysql-card-header h2 {
  color: #ffffff;
  font-size: 28px;
  font-weight: 700;
  margin: 0;
  letter-spacing: -0.5px;
}

.mysql-card-tags {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
  margin-bottom: 20px;
}

.mysql-card-tags .tag {
  background: rgba(255, 255, 255, 0.2);
  backdrop-filter: blur(10px);
  color: #ffffff;
  padding: 6px 14px;
  border-radius: 20px;
  font-size: 13px;
  font-weight: 500;
  border: 1px solid rgba(255, 255, 255, 0.3);
  transition: all 0.2s ease;
}

.mysql-card-tags .tag:hover {
  background: rgba(255, 255, 255, 0.3);
  transform: translateY(-2px);
}

.mysql-card-description {
  color: rgba(255, 255, 255, 0.95);
  font-size: 16px;
  line-height: 1.7;
  margin-bottom: 24px;
  font-weight: 400;
}

.mysql-card-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  flex-wrap: wrap;
  gap: 16px;
}

.mysql-btn {
  display: inline-flex;
  align-items: center;
  background: #ffffff;
  color: #00758F;
  padding: 12px 28px;
  border-radius: 8px;
  font-weight: 600;
  font-size: 15px;
  text-decoration: none;
  transition: all 0.3s ease;
  box-shadow: 0 4px 15px rgba(0, 0, 0, 0.1);
}

.mysql-btn:hover {
  background: #f0f0f0;
  transform: translateX(4px);
  box-shadow: 0 6px 20px rgba(0, 0, 0, 0.15);
}

.mysql-count {
  color: rgba(255, 255, 255, 0.9);
  font-size: 14px;
  font-weight: 500;
  padding: 8px 16px;
  background: rgba(255, 255, 255, 0.15);
  border-radius: 20px;
  backdrop-filter: blur(10px);
}

/* 响应式设计 */
@media screen and (max-width: 768px) {
  .mysql-featured-card {
    padding: 24px;
    margin-bottom: 24px;
  }

  .mysql-card-header h2 {
    font-size: 22px;
  }

  .mysql-card-tags {
    gap: 8px;
  }

  .mysql-card-tags .tag {
    font-size: 12px;
    padding: 5px 12px;
  }

  .mysql-card-description {
    font-size: 14px;
    line-height: 1.6;
  }

  .mysql-card-footer {
    flex-direction: column;
    align-items: flex-start;
  }

  .mysql-btn {
    width: 100%;
    justify-content: center;
  }
}

/* 暗色模式适配 */
.dark .mysql-featured-card {
  background: linear-gradient(135deg, #005266 0%, #D47A0A 100%);
  box-shadow: 0 10px 40px rgba(0, 82, 102, 0.3);
}

.dark .mysql-featured-card:hover {
  box-shadow: 0 15px 50px rgba(0, 82, 102, 0.4);
}
```

### Step 4: 创建专题首页 _index.md

```yaml
---
title: "MySQL从入门到精通"
date: 2025-11-21T15:00:00+08:00
layout: "list"
description: "从第一性原理出发，系统化掌握MySQL，从小白成长为数据库专家"
---

## 关于MySQL从入门到精通

这是一个**系统化、渐进式**的MySQL学习专题，从第一性原理出发，带你从小白成长为数据库领域的专家。

### 为什么MySQL如此重要？

- **市场占有率第一**：全球最流行的开源关系型数据库
- **互联网基础设施**：支撑着90%以上的互联网应用
- **必备技能**：后端开发、数据分析、运维工程师的核心能力
- **高薪保障**：精通MySQL的工程师平均薪资提升30%+

### 这里有什么？

系统化的知识分享，从入门到精通：

✅ **SQL查询**：从基础到高级，掌握复杂查询技巧
✅ **索引优化**：深入理解B+树，掌握索引设计与优化
✅ **事务与锁**：理解MVCC、锁机制，解决并发问题
✅ **架构原理**：剖析InnoDB存储引擎，理解底层实现
✅ **高可用**：掌握主从复制、读写分离、分库分表
✅ **性能调优**：生产环境性能优化和问题排查
✅ **源码分析**：从源码角度理解MySQL（可选）

---

## 学习路径

### 🎯 第一阶段：基础入门篇（10篇）
从零开始，建立MySQL的基础认知，掌握基本操作。

### 📚 第二阶段：SQL进阶篇（12篇）
精通SQL查询语法，能够编写复杂的业务查询。

### 🔍 第三阶段：索引与优化篇（12篇）
深入理解索引原理，掌握查询优化技巧。

### 🔒 第四阶段：事务与锁篇（10篇）
深入理解事务机制、MVCC、锁机制，解决并发问题。

### 🏗️ 第五阶段：架构原理篇（12篇）
理解MySQL内部架构，掌握InnoDB存储引擎原理。

### 🚀 第六阶段：高可用实践篇（10篇）
掌握MySQL的高可用架构，实现生产级部署。

### ⚡ 第七阶段：性能调优篇（12篇）
掌握MySQL性能调优方法，解决生产环境问题。

### 💡 第八阶段：源码深度篇（8篇，可选）
通过源码理解MySQL底层实现，达到专家级水平。

---

## 最新文章
```

### Step 5: 创建自定义列表模板（阶段分组展示）

创建文件 `layouts/mysql/list.html`：

```html
{{- define "main" }}

{{- if .Content }}
<div class="post-content">
  {{- if not (.Param "disableAnchoredHeadings") }}
  {{- partial "anchored_headings.html" .Content -}}
  {{- else }}{{ .Content }}{{ end }}
</div>
{{- end }}

{{/* 按阶段分组显示文章 */}}
<div class="mysql-articles-by-stage">
  {{/* 定义所有阶段 */}}
  {{- $stages := slice
    (dict "id" 1 "title" "🎯 第一阶段：基础入门篇" "desc" "从零开始，建立MySQL的基础认知，掌握基本操作" "icon" "🎯")
    (dict "id" 2 "title" "📚 第二阶段：SQL进阶篇" "desc" "精通SQL查询语法，能够编写复杂的业务查询" "icon" "📚")
    (dict "id" 3 "title" "🔍 第三阶段：索引与优化篇" "desc" "深入理解索引原理，掌握查询优化技巧" "icon" "🔍")
    (dict "id" 4 "title" "🔒 第四阶段：事务与锁篇" "desc" "深入理解事务机制、MVCC、锁机制，解决并发问题" "icon" "🔒")
    (dict "id" 5 "title" "🏗️ 第五阶段：架构原理篇" "desc" "理解MySQL内部架构，掌握InnoDB存储引擎原理" "icon" "🏗️")
    (dict "id" 6 "title" "🚀 第六阶段：高可用实践篇" "desc" "掌握MySQL的高可用架构，实现生产级部署" "icon" "🚀")
    (dict "id" 7 "title" "⚡ 第七阶段：性能调优篇" "desc" "掌握MySQL性能调优方法，解决生产环境问题" "icon" "⚡")
    (dict "id" 8 "title" "💡 第八阶段：源码深度篇" "desc" "通过源码理解MySQL底层实现，达到专家级水平（可选）" "icon" "💡")
  -}}

  {{/* 获取所有文章并按 weight 排序 */}}
  {{- $pages := where .Site.RegularPages "Section" "mysql" }}
  {{- $pages = where $pages "Type" "mysql" }}
  {{- $pages = $pages.ByWeight }}

  {{/* 按阶段分组 */}}
  {{- range $stageInfo := $stages }}
    {{- $stageId := $stageInfo.id }}
    {{- $stagePosts := where $pages "Params.stage" $stageId }}

    {{- if $stagePosts }}
    <div class="stage-section" id="stage-{{ $stageId }}">
      <div class="stage-header" onclick="toggleStage({{ $stageId }})">
        <h2>
          <span class="stage-icon">{{ $stageInfo.icon }}</span>
          {{ $stageInfo.title }}
          <span class="article-count">({{ len $stagePosts }} 篇)</span>
          <span class="toggle-icon" id="toggle-{{ $stageId }}">▼</span>
        </h2>
        <p class="stage-desc">{{ $stageInfo.desc }}</p>
      </div>

      <div class="stage-articles" id="articles-{{ $stageId }}">
        <div class="articles-grid">
          {{- range $index, $page := $stagePosts }}
          <article class="article-card">
            <div class="article-number">{{ printf "%02d" (add $index 1) }}</div>
            <div class="article-content">
              <h3 class="article-title">
                <a href="{{ .RelPermalink }}">{{ .Title | markdownify }}</a>
              </h3>
              {{- if .Params.description }}
              <p class="article-description">{{ .Params.description }}</p>
              {{- end }}
              <div class="article-meta">
                <time datetime="{{ .Date.Format "2006-01-02" }}">
                  📅 {{ .Date.Format "2006-01-02" }}
                </time>
                {{- if .Params.tags }}
                <span class="article-tags">
                  {{- range first 3 .Params.tags }}
                  <span class="tag">{{ . }}</span>
                  {{- end }}
                </span>
                {{- end }}
              </div>
            </div>
          </article>
          {{- end }}
        </div>
      </div>
    </div>
    {{- end }}
  {{- end }}
</div>

<style>
/* 阶段分组样式 - 紧凑版 - MySQL品牌色 */
.mysql-articles-by-stage {
  margin-top: 30px;
}

.stage-section {
  margin-bottom: 40px;
  border-radius: 12px;
  overflow: hidden;
  box-shadow: 0 2px 8px rgba(0,0,0,0.1);
}

.stage-header {
  background: linear-gradient(135deg, #00758F 0%, #F29111 100%);
  color: white;
  padding: 24px 30px;
  cursor: pointer;
  user-select: none;
  transition: all 0.3s ease;
}

.stage-header:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(0, 117, 143, 0.3);
}

.stage-header h2 {
  margin: 0 0 10px 0;
  font-size: 24px;
  font-weight: 700;
  display: flex;
  align-items: center;
  gap: 10px;
  color: white;
}

.stage-icon {
  font-size: 28px;
}

.article-count {
  font-size: 16px;
  opacity: 0.9;
  font-weight: 500;
}

.toggle-icon {
  margin-left: auto;
  transition: transform 0.3s ease;
  font-size: 18px;
}

.toggle-icon.collapsed {
  transform: rotate(-90deg);
}

.stage-desc {
  margin: 0;
  font-size: 14px;
  opacity: 0.95;
  line-height: 1.6;
}

.stage-articles {
  background: var(--entry);
  padding: 15px;
  max-height: 10000px;
  overflow: hidden;
  transition: max-height 0.5s ease, padding 0.5s ease;
}

.stage-articles.collapsed {
  max-height: 0;
  padding: 0 15px;
}

.articles-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 12px;
}

.article-card {
  background: var(--theme);
  border: 1px solid var(--border);
  border-radius: 6px;
  padding: 12px;
  transition: all 0.3s ease;
  display: flex;
  gap: 10px;
  position: relative;
}

.article-card:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(0,0,0,0.08);
  border-color: #00758F;
}

.article-number {
  font-size: 24px;
  font-weight: 700;
  color: #00758F;
  opacity: 0.3;
  min-width: 40px;
  text-align: center;
}

.article-content {
  flex: 1;
}

.article-title {
  margin: 0 0 6px 0;
  font-size: 14px;
  line-height: 1.4;
}

.article-title a {
  color: var(--primary);
  text-decoration: none;
  transition: color 0.3s ease;
}

.article-title a:hover {
  color: #00758F;
}

.article-description {
  font-size: 12px;
  color: var(--secondary);
  margin: 0 0 8px 0;
  line-height: 1.5;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

.article-meta {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 11px;
  color: var(--secondary);
  flex-wrap: wrap;
}

.article-tags {
  display: flex;
  gap: 4px;
  flex-wrap: wrap;
}

.article-tags .tag {
  background: var(--code-bg);
  padding: 2px 6px;
  border-radius: 3px;
  font-size: 10px;
}

/* 响应式设计 */
@media screen and (max-width: 768px) {
  .articles-grid {
    grid-template-columns: 1fr;
  }

  .stage-header {
    padding: 20px;
  }

  .stage-header h2 {
    font-size: 20px;
  }

  .article-number {
    font-size: 20px;
    min-width: 35px;
  }
}

/* 暗色模式适配 */
.dark .stage-header {
  background: linear-gradient(135deg, #005266 0%, #D47A0A 100%);
}

.dark .article-card:hover {
  border-color: #F29111;
}

.dark .article-number {
  color: #F29111;
}

.dark .article-title a:hover {
  color: #F29111;
}
</style>

<script>
function toggleStage(stageId) {
  const articles = document.getElementById('articles-' + stageId);
  const toggle = document.getElementById('toggle-' + stageId);

  if (articles.classList.contains('collapsed')) {
    articles.classList.remove('collapsed');
    toggle.classList.remove('collapsed');
  } else {
    articles.classList.add('collapsed');
    toggle.classList.add('collapsed');
  }
}

// 页面加载时默认折叠所有阶段
document.addEventListener('DOMContentLoaded', function() {
  document.querySelectorAll('.stage-articles').forEach(el => el.classList.add('collapsed'));
  document.querySelectorAll('.toggle-icon').forEach(el => el.classList.add('collapsed'));
});
</script>

{{- end }}{{/* end main */}}
```

### Step 6: 批量创建文章脚本

创建脚本 `scripts/create_mysql_articles.sh`：

```bash
#!/bin/bash

# MySQL专题文章批量创建脚本
BASE_DIR="content/mysql/posts"
mkdir -p "$BASE_DIR"

# 第一阶段：基础入门篇（10篇）
stage1_titles=(
  "01-什么是数据库-为什么需要数据库"
  "02-MySQL简介-历史特点与应用场景"
  "03-MySQL安装与环境配置"
  "04-数据库与表的创建-DDL基础"
  "05-数据类型详解-选择合适的数据类型"
  "06-基础增删改查-DML操作入门"
  "07-约束与完整性-主键外键唯一非空"
  "08-字符集与校对规则"
  "09-数据导入导出"
  "10-第一个完整案例-用户管理系统"
)

for i in "${!stage1_titles[@]}"; do
  title="${stage1_titles[$i]}"
  hugo new "mysql/posts/${title}.md"
  # 添加 stage 和 stageTitle
  file="$BASE_DIR/${title}.md"
  if [ -f "$file" ]; then
    sed -i '' '/^weight:/a\
stage: 1\
stageTitle: "基础入门篇"
' "$file"
  fi
done

# 第二阶段：SQL进阶篇（12篇）
stage2_titles=(
  "11-单表查询进阶-WHERE条件与运算符"
  "12-排序与分页-ORDER-BY与LIMIT"
  "13-聚合函数-COUNT-SUM-AVG-MAX-MIN"
  "14-分组查询-GROUP-BY与HAVING"
  "15-多表连接-INNER-JOIN-LEFT-JOIN-RIGHT-JOIN"
  "16-子查询-嵌套查询与相关子查询"
  "17-联合查询-UNION与UNION-ALL"
  "18-窗口函数-ROW-NUMBER-RANK-DENSE-RANK"
  "19-常用字符串函数与日期函数"
  "20-条件表达式-CASE-WHEN与IF"
  "21-视图-虚拟表的创建与使用"
  "22-综合实战-电商订单查询系统"
)

for i in "${!stage2_titles[@]}"; do
  title="${stage2_titles[$i]}"
  hugo new "mysql/posts/${title}.md"
  file="$BASE_DIR/${title}.md"
  if [ -f "$file" ]; then
    sed -i '' '/^weight:/a\
stage: 2\
stageTitle: "SQL进阶篇"
' "$file"
  fi
done

# ... 其他阶段类似 ...

echo "✅ MySQL专题文章创建完成！"
```

---

## 📊 进度跟踪

### 完成情况（实时更新）

| 阶段 | 文章数 | 已完成 | 进度 | 状态 |
|-----|-------|-------|------|------|
| 🎯 基础入门篇 | 10 | 0 | 0% | 📝 待开始 |
| 📚 SQL进阶篇 | 12 | 0 | 0% | 📝 待开始 |
| 🔍 索引与优化篇 | 12 | 0 | 0% | 📝 待开始 |
| 🔒 事务与锁篇 | 10 | 0 | 0% | 📝 待开始 |
| 🏗️ 架构原理篇 | 12 | 0 | 0% | 📝 待开始 |
| 🚀 高可用实践篇 | 10 | 0 | 0% | 📝 待开始 |
| ⚡ 性能调优篇 | 12 | 0 | 0% | 📝 待开始 |
| 💡 源码深度篇 | 8 | 0 | 0% | 📝 待开始 |
| **总计** | **86** | **0** | **0%** | 📝 待开始 |

---

## 🎯 写作建议

### 每篇文章的标准结构

```markdown
# 标题

## 引言
- 提出问题：这篇文章要解决什么问题？
- 为什么重要：为什么需要学习这个知识点？

## 基础概念
- 第一性原理：从最基础的概念讲起
- 渐进式复杂度：由浅入深，逐步引入复杂概念

## 核心原理
- 深入剖析：底层原理是什么？
- 图解说明：用图表辅助理解

## 实战示例
- 代码演示：提供可运行的示例代码
- 案例分析：分析实际应用场景

## 最佳实践
- 使用建议：什么时候用？怎么用？
- 常见误区：有哪些坑需要避免？

## 总结
- 核心要点回顾
- 延伸阅读推荐
```

### 写作要点

1. **第一性原理**：每个概念追溯到最底层的原理
2. **渐进复杂度**：先简单例子，再复杂场景，不要一上来就讲高深的
3. **图文并茂**：多用图表、流程图、示意图
4. **代码示例**：提供可运行的示例代码
5. **适中篇幅**：3000-5000字，单一主题，不要贪多
6. **实战导向**：理论+实践，即学即用

---

## ✅ 快速检查清单

创建MySQL专题时，确保完成：

- [ ] 创建目录 `content/mysql/posts/`
- [ ] 创建 `content/mysql/_index.md`
- [ ] 在 `layouts/index.html` 添加卡片
- [ ] 在 `layouts/partials/extend_head.html` 添加样式
- [ ] 创建 `layouts/mysql/list.html` 自定义模板
- [ ] 创建文章批量生成脚本
- [ ] 本地预览确认效果
- [ ] 提交代码并推送

---

## 📚 参考资料

- **官方文档**：https://dev.mysql.com/doc/
- **《MySQL技术内幕：InnoDB存储引擎》**：姜承尧
- **《高性能MySQL》**：Baron Schwartz等
- **《MySQL实战45讲》**：丁奇（极客时间）
- **源码**：https://github.com/mysql/mysql-server

---

**预计完成时间**：6-8个月
**创建时间**：2025-11-21
**最后更新**：2025-11-21
