---
title: "供应链主数据管理全景图：从数据建模到数据治理的完整体系"
date: 2025-11-22T09:00:00+08:00
draft: false
tags: ["主数据管理", "MDM", "数据治理", "数据建模"]
categories: ["供应链"]
description: "系统化介绍供应链主数据管理的核心概念、数据分类、系统架构和治理方法，为构建高质量的主数据管理体系打下坚实基础。"
---

## 引言

在数字化转型的浪潮中，数据已成为企业最重要的资产。然而，许多企业面临着严重的数据质量问题：同一个商品在不同系统有不同的编码，同一个供应商在ERP、SRM、财务系统中信息不一致，客户数据分散在各个业务系统无法整合......这些问题的根源在于缺乏统一的主数据管理。

本文将系统化介绍供应链主数据管理（Master Data Management, MDM）的完整体系，帮助你构建高质量的主数据管理能力。

---

## 一、什么是主数据管理

### 1.1 主数据的定义

**主数据（Master Data）**是企业核心业务实体的基础数据，具有以下特征：

- **共享性**：被多个业务系统共同使用
- **稳定性**：相对稳定，变化频率低
- **权威性**：是业务运营的权威数据源
- **一致性**：在各系统间保持一致

**常见的供应链主数据包括**：
- 商品主数据（Product Master Data）
- 客户主数据（Customer Master Data）
- 供应商主数据（Supplier Master Data）
- 仓库主数据（Warehouse Master Data）
- 物料主数据（Material Master Data）
- 员工主数据（Employee Master Data）

### 1.2 主数据 vs 参考数据 vs 交易数据

| 数据类型 | 定义 | 示例 | 变化频率 |
|---------|------|------|---------|
| **主数据** | 核心业务实体的基础数据 | 商品、客户、供应商 | 低（月/季度） |
| **参考数据** | 用于分类和标准化的数据 | 国家代码、币种、单位 | 极低（年） |
| **交易数据** | 业务交易产生的数据 | 订单、库存、物流单 | 高（秒/分钟） |

**举例说明**：
- **主数据**：iPhone 15 Pro Max（SKU: IP15PM256GB-BLK）
- **参考数据**：商品品类（手机）、单位（台）、币种（CNY）
- **交易数据**：2025-11-22下单购买1台iPhone 15 Pro Max

### 1.3 主数据管理的价值

#### 业务价值
1. **提升运营效率**：统一数据标准，减少重复录入，降低30-50%数据维护成本
2. **支撑决策分析**：高质量数据是BI分析的基础，提升决策准确性
3. **改善客户体验**：360度客户视图，提供个性化服务
4. **降低合规风险**：满足GDPR、SOX等法规要求

#### 技术价值
1. **消除信息孤岛**：实现跨系统数据共享
2. **保障数据质量**：建立数据质量标准和监控机制
3. **提升系统集成效率**：统一数据接口，降低集成复杂度
4. **支撑数字化转型**：为大数据、AI等新技术提供高质量数据基础

---

## 二、供应链主数据分类

### 2.1 商品主数据

**核心属性**：
```yaml
基本信息:
  - SKU编码（唯一标识）
  - 商品名称
  - 品牌
  - 型号
  - 规格
  - 条形码/EAN码
  
分类信息:
  - 品类（一级/二级/三级）
  - 品牌
  - 系列
  
物理属性:
  - 长/宽/高（cm）
  - 毛重/净重（kg）
  - 体积（m³）
  - 颜色/尺码
  
商业属性:
  - 采购价
  - 销售价
  - 成本价
  - 税率
  - 供应商
  
库存属性:
  - 是否可销售
  - 是否可采购
  - 安全库存
  - 最小订货量
```

**SPU vs SKU**：
- **SPU（Standard Product Unit）**：标准产品单元，如"iPhone 15 Pro Max"
- **SKU（Stock Keeping Unit）**：库存量单位，如"iPhone 15 Pro Max 256GB 黑色"

一个SPU可以有多个SKU。

### 2.2 客户主数据

**核心属性**：
```yaml
基本信息:
  - 客户编码
  - 客户名称
  - 客户类型（企业/个人）
  - 联系人
  - 联系电话
  - Email
  
企业客户特有:
  - 统一社会信用代码
  - 法人代表
  - 注册资本
  - 经营范围
  
财务信息:
  - 信用等级（AAA/AA/A/B/C）
  - 信用额度
  - 账期（30天/60天/90天）
  - 开票信息
  
业务信息:
  - 客户分级（VIP/普通）
  - 所属销售
  - 所属区域
  - 客户标签
```

### 2.3 供应商主数据

**核心属性**：
```yaml
基本信息:
  - 供应商编码
  - 供应商名称
  - 供应商类型（生产商/经销商/服务商）
  - 联系人/电话/Email
  
资质信息:
  - 营业执照号
  - 税务登记证
  - 开户行/账号
  - 资质证书
  
业务信息:
  - 供应商分级（A/B/C/D）
  - 合作开始日期
  - 合同编号
  - 主营品类
  - 服务区域
  
绩效信息:
  - 质量合格率
  - 准时交付率
  - 价格竞争力
  - 服务响应速度
```

### 2.4 仓库主数据

**核心属性**：
```yaml
基本信息:
  - 仓库编码
  - 仓库名称
  - 仓库类型（自营/第三方）
  - 仓库地址
  - 负责人/电话
  
能力信息:
  - 仓库面积（m²）
  - 存储容量（m³）
  - 库位数量
  - 作业能力（件/天）
  
服务信息:
  - 服务区域
  - 服务品类
  - 是否支持冷链
  - 是否支持危险品
```

---

## 三、主数据建模实践

### 3.1 商品主数据数据模型

```sql
-- 商品主数据表
CREATE TABLE product_master (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  sku VARCHAR(64) UNIQUE NOT NULL COMMENT 'SKU编码',
  spu VARCHAR(64) NOT NULL COMMENT 'SPU编码',
  product_name VARCHAR(200) NOT NULL COMMENT '商品名称',
  brand_id BIGINT COMMENT '品牌ID',
  category_id BIGINT COMMENT '品类ID',
  
  -- 规格属性
  specification JSON COMMENT '规格属性（颜色、尺码等）',
  barcode VARCHAR(50) COMMENT '条形码',
  
  -- 物理属性
  length DECIMAL(10,2) COMMENT '长度(cm)',
  width DECIMAL(10,2) COMMENT '宽度(cm)',
  height DECIMAL(10,2) COMMENT '高度(cm)',
  gross_weight DECIMAL(10,3) COMMENT '毛重(kg)',
  net_weight DECIMAL(10,3) COMMENT '净重(kg)',
  volume DECIMAL(10,4) COMMENT '体积(m³)',
  
  -- 商业属性
  purchase_price DECIMAL(10,2) COMMENT '采购价',
  sale_price DECIMAL(10,2) COMMENT '销售价',
  cost_price DECIMAL(10,2) COMMENT '成本价',
  tax_rate DECIMAL(5,4) COMMENT '税率',
  
  -- 库存属性
  is_saleable TINYINT(1) DEFAULT 1 COMMENT '是否可销售',
  is_purchasable TINYINT(1) DEFAULT 1 COMMENT '是否可采购',
  safety_stock INT COMMENT '安全库存',
  min_order_qty INT COMMENT '最小订货量',
  
  -- 审计字段
  status VARCHAR(20) DEFAULT 'ACTIVE' COMMENT '状态：ACTIVE/INACTIVE/DELETED',
  created_by VARCHAR(50),
  created_time DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_by VARCHAR(50),
  updated_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  version INT DEFAULT 1 COMMENT '数据版本号',
  
  INDEX idx_spu (spu),
  INDEX idx_brand_category (brand_id, category_id),
  INDEX idx_barcode (barcode)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='商品主数据表';

-- 品牌主数据表
CREATE TABLE brand_master (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  brand_code VARCHAR(50) UNIQUE NOT NULL,
  brand_name VARCHAR(100) NOT NULL,
  brand_name_en VARCHAR(100),
  country VARCHAR(50) COMMENT '品牌国家',
  logo_url VARCHAR(500),
  status VARCHAR(20) DEFAULT 'ACTIVE',
  created_time DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='品牌主数据表';

-- 品类主数据表（三级分类）
CREATE TABLE category_master (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  category_code VARCHAR(50) UNIQUE NOT NULL,
  category_name VARCHAR(100) NOT NULL,
  parent_id BIGINT COMMENT '父品类ID',
  level TINYINT COMMENT '层级：1/2/3',
  sort_order INT COMMENT '排序',
  status VARCHAR(20) DEFAULT 'ACTIVE',
  created_time DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_parent (parent_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='品类主数据表';
```

### 3.2 客户主数据数据模型

```sql
-- 客户主数据表
CREATE TABLE customer_master (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  customer_code VARCHAR(50) UNIQUE NOT NULL COMMENT '客户编码',
  customer_name VARCHAR(200) NOT NULL COMMENT '客户名称',
  customer_type VARCHAR(20) NOT NULL COMMENT '客户类型：ENTERPRISE/INDIVIDUAL',
  
  -- 联系信息
  contact_person VARCHAR(50) COMMENT '联系人',
  contact_phone VARCHAR(20) COMMENT '联系电话',
  contact_email VARCHAR(100) COMMENT 'Email',
  address VARCHAR(500) COMMENT '地址',
  
  -- 企业客户特有字段
  unified_social_credit_code VARCHAR(50) COMMENT '统一社会信用代码',
  legal_representative VARCHAR(50) COMMENT '法人代表',
  registered_capital DECIMAL(15,2) COMMENT '注册资本',
  business_scope TEXT COMMENT '经营范围',
  
  -- 财务信息
  credit_level VARCHAR(10) COMMENT '信用等级：AAA/AA/A/B/C',
  credit_limit DECIMAL(15,2) COMMENT '信用额度',
  payment_term INT COMMENT '账期(天)',
  
  -- 发票信息（JSON存储）
  invoice_info JSON COMMENT '开票信息',
  
  -- 业务信息
  customer_level VARCHAR(20) COMMENT '客户分级：VIP/GOLD/SILVER/NORMAL',
  sales_id BIGINT COMMENT '所属销售ID',
  region_id BIGINT COMMENT '所属区域ID',
  customer_tags JSON COMMENT '客户标签',
  
  -- 审计字段
  status VARCHAR(20) DEFAULT 'ACTIVE',
  created_by VARCHAR(50),
  created_time DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_by VARCHAR(50),
  updated_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  version INT DEFAULT 1,
  
  INDEX idx_type_level (customer_type, customer_level),
  INDEX idx_credit_code (unified_social_credit_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='客户主数据表';
```

### 3.3 供应商主数据数据模型

```sql
-- 供应商主数据表
CREATE TABLE supplier_master (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  supplier_code VARCHAR(50) UNIQUE NOT NULL COMMENT '供应商编码',
  supplier_name VARCHAR(200) NOT NULL COMMENT '供应商名称',
  supplier_type VARCHAR(20) NOT NULL COMMENT '供应商类型：MANUFACTURER/DISTRIBUTOR/SERVICE_PROVIDER',
  
  -- 联系信息
  contact_person VARCHAR(50),
  contact_phone VARCHAR(20),
  contact_email VARCHAR(100),
  address VARCHAR(500),
  
  -- 资质信息
  business_license VARCHAR(50) COMMENT '营业执照号',
  tax_registration VARCHAR(50) COMMENT '税务登记证',
  bank_name VARCHAR(100) COMMENT '开户行',
  bank_account VARCHAR(50) COMMENT '银行账号',
  certificates JSON COMMENT '资质证书',
  
  -- 业务信息
  supplier_level VARCHAR(10) COMMENT '供应商分级：A/B/C/D',
  cooperation_start_date DATE COMMENT '合作开始日期',
  contract_no VARCHAR(50) COMMENT '合同编号',
  main_categories JSON COMMENT '主营品类',
  service_regions JSON COMMENT '服务区域',
  
  -- 绩效信息
  quality_pass_rate DECIMAL(5,2) COMMENT '质量合格率(%)',
  on_time_delivery_rate DECIMAL(5,2) COMMENT '准时交付率(%)',
  price_competitiveness DECIMAL(3,2) COMMENT '价格竞争力(1-5分)',
  service_response_score DECIMAL(3,2) COMMENT '服务响应速度(1-5分)',
  
  -- 审计字段
  status VARCHAR(20) DEFAULT 'ACTIVE',
  created_by VARCHAR(50),
  created_time DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_by VARCHAR(50),
  updated_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  version INT DEFAULT 1,
  
  INDEX idx_type_level (supplier_type, supplier_level),
  INDEX idx_license (business_license)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='供应商主数据表';
```

---

## 四、主数据管理架构

### 4.1 MDM系统架构

```
┌─────────────────────────────────────────────────────────┐
│                     业务系统层                            │
│   ERP  │ OMS │ WMS │ TMS │ CRM │ SRM │ 财务系统          │
└────────────────┬────────────────────────────────────────┘
                 │ API/MQ
┌────────────────┴────────────────────────────────────────┐
│                   MDM主数据平台                           │
│  ┌──────────┬──────────┬──────────┬──────────────────┐  │
│  │ 数据采集 │ 数据清洗 │ 数据整合 │ 数据分发         │  │
│  └──────────┴──────────┴──────────┴──────────────────┘  │
│  ┌──────────┬──────────┬──────────┬──────────────────┐  │
│  │ 数据建模 │ 数据质量 │ 数据治理 │ 数据服务         │  │
│  └──────────┴──────────┴──────────┴──────────────────┘  │
│  ┌──────────┬──────────┬──────────┬──────────────────┐  │
│  │ 商品主数据│ 客户主数据│ 供应商   │ 仓库主数据       │  │
│  └──────────┴──────────┴──────────┴──────────────────┘  │
└─────────────────────────────────────────────────────────┘
                 │
┌────────────────┴────────────────────────────────────────┐
│                    数据存储层                             │
│     MySQL主从    │   Redis缓存   │   Elasticsearch      │
└─────────────────────────────────────────────────────────┘
```

### 4.2 核心功能模块

#### 1. 数据采集模块
**功能**：从各业务系统采集主数据
**技术方案**：
- **API推送**：业务系统主动推送数据到MDM
- **定时拉取**：MDM定时从业务系统拉取数据
- **CDC同步**：通过Canal监听数据库binlog实时同步

#### 2. 数据清洗模块
**功能**：清洗、标准化、去重主数据
**处理规则**：
```java
public class DataCleansingService {
    
    // 数据标准化
    public ProductMaster standardize(ProductMaster product) {
        // 1. 去除空格
        product.setProductName(product.getProductName().trim());
        
        // 2. 统一大小写
        product.setSku(product.getSku().toUpperCase());
        
        // 3. 格式化电话号码
        product.setContactPhone(formatPhone(product.getContactPhone()));
        
        // 4. 标准化地址
        product.setAddress(standardizeAddress(product.getAddress()));
        
        return product;
    }
    
    // 数据去重
    public List<ProductMaster> deduplicate(List<ProductMaster> products) {
        // 基于SKU去重
        return products.stream()
            .collect(Collectors.toMap(
                ProductMaster::getSku,
                p -> p,
                (existing, replacement) -> {
                    // 冲突解决：保留最新数据
                    return replacement.getUpdatedTime().after(existing.getUpdatedTime()) 
                        ? replacement : existing;
                }
            ))
            .values()
            .stream()
            .collect(Collectors.toList());
    }
}
```

#### 3. 数据整合模块
**功能**：合并多源数据，形成黄金记录（Golden Record）
**匹配规则**：
```java
public class DataMatchingService {
    
    // 客户数据匹配
    public Customer matchCustomer(List<Customer> candidates) {
        // 匹配规则优先级
        // 1. 统一社会信用代码完全匹配 -> 100%
        // 2. 客户名称+联系电话完全匹配 -> 90%
        // 3. 客户名称模糊匹配 -> 70%
        
        for (Customer candidate : candidates) {
            double matchScore = calculateMatchScore(candidate);
            if (matchScore >= 0.9) {
                return candidate; // 高置信度匹配
            }
        }
        
        return null; // 无匹配，需要人工审核
    }
    
    // 计算匹配分数
    private double calculateMatchScore(Customer customer) {
        double score = 0.0;
        
        // 统一社会信用代码匹配
        if (creditCodeMatch(customer)) {
            score += 1.0;
        }
        
        // 客户名称匹配
        score += nameMatchScore(customer) * 0.5;
        
        // 联系电话匹配
        score += phoneMatchScore(customer) * 0.3;
        
        // 地址匹配
        score += addressMatchScore(customer) * 0.2;
        
        return score;
    }
}
```

#### 4. 数据分发模块
**功能**：将主数据分发到各业务系统
**分发策略**：
```java
public class DataDistributionService {
    
    @Autowired
    private RocketMQTemplate rocketMQTemplate;
    
    // 发布主数据变更事件
    public void publishProductChange(ProductMaster product, ChangeType changeType) {
        ProductChangeEvent event = ProductChangeEvent.builder()
            .sku(product.getSku())
            .changeType(changeType) // CREATE/UPDATE/DELETE
            .productData(product)
            .timestamp(System.currentTimeMillis())
            .build();
        
        // 发送到MQ，各系统订阅消费
        rocketMQTemplate.convertAndSend(
            "TOPIC_PRODUCT_CHANGE",
            "TAG_" + changeType.name(),
            event
        );
    }
    
    // 主数据查询接口
    @GetMapping("/api/mdm/product/{sku}")
    public Result<ProductMaster> getProduct(@PathVariable String sku) {
        // 1. 先查Redis缓存
        ProductMaster product = redisTemplate.opsForValue().get("product:" + sku);
        
        if (product == null) {
            // 2. 查数据库
            product = productMasterMapper.selectBySku(sku);
            
            if (product != null) {
                // 3. 写入缓存，过期时间1小时
                redisTemplate.opsForValue().set(
                    "product:" + sku, 
                    product, 
                    1, 
                    TimeUnit.HOURS
                );
            }
        }
        
        return Result.success(product);
    }
}
```

---

## 五、数据质量管理

### 5.1 数据质量维度

| 维度 | 定义 | 评估方法 | 目标值 |
|-----|------|---------|-------|
| **完整性** | 数据是否完整，必填字段是否都有值 | 必填字段非空比例 | ≥ 99% |
| **准确性** | 数据是否准确，是否符合业务规则 | 数据验证通过率 | ≥ 95% |
| **一致性** | 数据在各系统间是否一致 | 跨系统数据一致性比例 | ≥ 98% |
| **及时性** | 数据是否及时更新 | 数据同步延迟时间 | ≤ 5分钟 |
| **唯一性** | 数据是否存在重复 | 重复数据比例 | ≤ 1% |

### 5.2 数据质量检查规则

```java
public class DataQualityChecker {
    
    // 完整性检查
    public List<String> checkCompleteness(ProductMaster product) {
        List<String> errors = new ArrayList<>();
        
        if (StringUtils.isEmpty(product.getSku())) {
            errors.add("SKU不能为空");
        }
        if (StringUtils.isEmpty(product.getProductName())) {
            errors.add("商品名称不能为空");
        }
        if (product.getBrandId() == null) {
            errors.add("品牌不能为空");
        }
        if (product.getCategoryId() == null) {
            errors.add("品类不能为空");
        }
        
        return errors;
    }
    
    // 准确性检查
    public List<String> checkAccuracy(ProductMaster product) {
        List<String> errors = new ArrayList<>();
        
        // 价格合理性
        if (product.getSalePrice() != null && product.getSalePrice().compareTo(BigDecimal.ZERO) <= 0) {
            errors.add("销售价必须大于0");
        }
        
        // 重量合理性
        if (product.getGrossWeight() != null && product.getNetWeight() != null) {
            if (product.getGrossWeight().compareTo(product.getNetWeight()) < 0) {
                errors.add("毛重不能小于净重");
            }
        }
        
        // 库存合理性
        if (product.getSafetyStock() != null && product.getSafetyStock() < 0) {
            errors.add("安全库存不能为负数");
        }
        
        return errors;
    }
    
    // 一致性检查
    public List<String> checkConsistency(ProductMaster mdmProduct, ProductMaster erpProduct) {
        List<String> errors = new ArrayList<>();
        
        if (!mdmProduct.getProductName().equals(erpProduct.getProductName())) {
            errors.add("商品名称不一致");
        }
        
        if (!mdmProduct.getSalePrice().equals(erpProduct.getSalePrice())) {
            errors.add("销售价不一致");
        }
        
        return errors;
    }
}
```

### 5.3 数据质量监控

```java
@Service
public class DataQualityMonitorService {
    
    @Scheduled(cron = "0 0 2 * * ?") // 每天凌晨2点执行
    public void dailyQualityCheck() {
        // 1. 统计数据质量指标
        QualityMetrics metrics = new QualityMetrics();
        
        // 完整性
        metrics.setCompleteness(calculateCompleteness());
        
        // 准确性
        metrics.setAccuracy(calculateAccuracy());
        
        // 一致性
        metrics.setConsistency(calculateConsistency());
        
        // 及时性
        metrics.setTimeliness(calculateTimeliness());
        
        // 唯一性
        metrics.setUniqueness(calculateUniqueness());
        
        // 2. 保存质量报告
        qualityReportMapper.insert(metrics);
        
        // 3. 质量告警
        if (metrics.getCompleteness() < 0.99) {
            sendAlert("数据完整性低于99%，当前：" + metrics.getCompleteness());
        }
        
        if (metrics.getConsistency() < 0.98) {
            sendAlert("数据一致性低于98%，当前：" + metrics.getConsistency());
        }
    }
    
    // 计算完整性
    private double calculateCompleteness() {
        long totalCount = productMasterMapper.count();
        long completeCount = productMasterMapper.countComplete();
        return (double) completeCount / totalCount;
    }
}
```

---

## 六、数据治理体系

### 6.1 数据治理组织架构

```
┌─────────────────────────────────────┐
│        数据治理委员会                 │
│    (Chief Data Officer领导)         │
└──────────┬──────────────────────────┘
           │
    ┌──────┴──────┬──────────┬────────┐
    │             │          │        │
┌───┴────┐  ┌────┴───┐  ┌──┴───┐  ┌─┴────┐
│数据架构 │  │数据质量│  │数据安全│  │数据运营│
│  小组   │  │  小组  │  │  小组  │  │  小组  │
└────────┘  └────────┘  └────────┘  └───────┘
```

**职责分工**：
- **数据治理委员会**：制定数据战略、审批数据标准、监督执行
- **数据架构小组**：设计数据模型、制定数据标准、规划数据架构
- **数据质量小组**：制定质量规则、监控数据质量、处理质量问题
- **数据安全小组**：制定安全策略、管理数据权限、审计数据访问
- **数据运营小组**：日常数据维护、培训用户、优化流程

### 6.2 数据生命周期管理

```
┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐
│ 创建 │→ │ 使用 │→ │ 更新 │→ │ 归档 │→ │ 销毁 │
└──────┘  └──────┘  └──────┘  └──────┘  └──────┘
```

**各阶段要求**：

| 阶段 | 要求 | 责任人 |
|-----|------|-------|
| **创建** | 通过数据质量检查，录入审批流程 | 数据录入员 |
| **使用** | 按权限访问，记录访问日志 | 业务人员 |
| **更新** | 通过变更审批，保留变更历史 | 数据管理员 |
| **归档** | 超过保留期限，迁移到归档库 | 系统自动 |
| **销毁** | 超过归档期限，符合法规要求后销毁 | 数据管理员 |

### 6.3 数据权限管理

```java
public class DataPermissionService {
    
    // 数据权限定义
    public enum DataPermission {
        VIEW,    // 查看
        CREATE,  // 创建
        UPDATE,  // 更新
        DELETE,  // 删除
        EXPORT,  // 导出
        APPROVE  // 审批
    }
    
    // 检查权限
    public boolean hasPermission(User user, String dataType, DataPermission permission) {
        // 1. 查询用户角色
        List<Role> roles = userRoleMapper.selectByUserId(user.getId());
        
        // 2. 查询角色权限
        for (Role role : roles) {
            List<Permission> permissions = rolePermissionMapper.selectByRoleId(role.getId());
            
            for (Permission p : permissions) {
                if (p.getDataType().equals(dataType) && 
                    p.getPermission().equals(permission)) {
                    return true;
                }
            }
        }
        
        return false;
    }
    
    // 数据脱敏
    public ProductMaster maskSensitiveData(ProductMaster product, User user) {
        // 如果用户没有查看价格权限，脱敏价格信息
        if (!hasPermission(user, "PRODUCT", DataPermission.VIEW_PRICE)) {
            product.setPurchasePrice(null);
            product.setCostPrice(null);
        }
        
        return product;
    }
}
```

---

## 七、主数据同步策略

### 7.1 同步模式

#### 1. 实时同步
**适用场景**：数据变更频繁，对实时性要求高
**技术方案**：
```java
@Service
public class RealtimeSyncService {
    
    @Autowired
    private RocketMQTemplate rocketMQTemplate;
    
    // 商品主数据变更时，实时推送
    @Transactional
    public void updateProduct(ProductMaster product) {
        // 1. 更新MDM数据库
        productMasterMapper.updateById(product);
        
        // 2. 发送MQ消息
        ProductChangeEvent event = ProductChangeEvent.builder()
            .sku(product.getSku())
            .changeType(ChangeType.UPDATE)
            .productData(product)
            .timestamp(System.currentTimeMillis())
            .build();
        
        rocketMQTemplate.syncSend(
            "TOPIC_PRODUCT_CHANGE",
            MessageBuilder.withPayload(event).build()
        );
        
        // 3. 清除缓存
        redisTemplate.delete("product:" + product.getSku());
    }
}
```

#### 2. 批量同步
**适用场景**：数据量大，对实时性要求不高
**技术方案**：
```java
@Service
public class BatchSyncService {
    
    @Scheduled(cron = "0 */10 * * * ?") // 每10分钟执行一次
    public void syncToERP() {
        // 1. 查询10分钟内变更的商品
        LocalDateTime since = LocalDateTime.now().minusMinutes(10);
        List<ProductMaster> changedProducts = productMasterMapper.selectChangedSince(since);
        
        if (changedProducts.isEmpty()) {
            return;
        }
        
        // 2. 批量推送到ERP
        BatchSyncRequest request = BatchSyncRequest.builder()
            .products(changedProducts)
            .syncTime(LocalDateTime.now())
            .build();
        
        erpApiClient.batchSync(request);
        
        log.info("批量同步完成，共{}条记录", changedProducts.size());
    }
}
```

#### 3. CDC同步
**适用场景**：最小侵入，实时性高
**技术方案**：
```yaml
# Canal配置
canal.instance.mysql.slaveId: 1234
canal.instance.master.address: 127.0.0.1:3306
canal.instance.dbUsername: canal
canal.instance.dbPassword: canal
canal.instance.filter.regex: mdm_db.product_master,mdm_db.customer_master
```

```java
@Component
public class CanalDataSyncListener {
    
    @CanalListener(destination = "mdm", schema = "mdm_db", table = "product_master")
    public void onProductChange(CanalEntry.RowChange rowChange) {
        for (CanalEntry.RowData rowData : rowChange.getRowDatasList()) {
            if (rowChange.getEventType() == CanalEntry.EventType.UPDATE) {
                // 解析变更数据
                ProductMaster product = parseRowData(rowData);
                
                // 同步到其他系统
                syncToOtherSystems(product);
            }
        }
    }
}
```

### 7.2 冲突解决策略

```java
public class ConflictResolutionService {
    
    // 冲突解决策略
    public enum ConflictStrategy {
        SOURCE_WINS,      // 源系统优先
        TARGET_WINS,      // 目标系统优先
        LATEST_WINS,      // 最新时间优先
        MANUAL_RESOLUTION // 人工解决
    }
    
    // 解决冲突
    public ProductMaster resolveConflict(
        ProductMaster mdmProduct,    // MDM数据
        ProductMaster erpProduct,    // ERP数据
        ConflictStrategy strategy
    ) {
        switch (strategy) {
            case SOURCE_WINS:
                return mdmProduct; // MDM作为源系统
                
            case TARGET_WINS:
                return erpProduct; // ERP作为目标系统
                
            case LATEST_WINS:
                // 比较更新时间
                return mdmProduct.getUpdatedTime().after(erpProduct.getUpdatedTime())
                    ? mdmProduct : erpProduct;
                
            case MANUAL_RESOLUTION:
                // 记录冲突，等待人工处理
                recordConflict(mdmProduct, erpProduct);
                return null;
                
            default:
                throw new IllegalArgumentException("未知的冲突解决策略");
        }
    }
}
```

---

## 八、主数据平台技术选型

### 8.1 技术栈推荐

| 技术层 | 推荐方案 | 说明 |
|-------|---------|------|
| **应用框架** | Spring Boot 2.7+ | 微服务架构基础 |
| **数据库** | MySQL 8.0 主从 | 主数据存储 |
| **缓存** | Redis Cluster | 提升查询性能 |
| **搜索引擎** | Elasticsearch 7.x | 全文检索、数据分析 |
| **消息队列** | RocketMQ | 数据同步、事件通知 |
| **任务调度** | XXL-Job | 定时同步、质量检查 |
| **数据同步** | Canal | CDC数据采集 |
| **工作流** | Flowable | 审批流程 |
| **API网关** | Spring Cloud Gateway | 统一接口入口 |
| **配置中心** | Nacos | 配置管理 |

### 8.2 性能优化策略

#### 1. 读性能优化
```java
@Service
public class ProductQueryService {
    
    // 三级缓存策略
    public ProductMaster getProduct(String sku) {
        // 1. 本地缓存（Caffeine）
        ProductMaster product = localCache.getIfPresent(sku);
        if (product != null) {
            return product;
        }
        
        // 2. Redis缓存
        product = redisTemplate.opsForValue().get("product:" + sku);
        if (product != null) {
            localCache.put(sku, product);
            return product;
        }
        
        // 3. 数据库
        product = productMasterMapper.selectBySku(sku);
        if (product != null) {
            // 写入缓存
            redisTemplate.opsForValue().set("product:" + sku, product, 1, TimeUnit.HOURS);
            localCache.put(sku, product);
        }
        
        return product;
    }
}
```

#### 2. 写性能优化
```java
@Service
public class ProductUpdateService {
    
    // 异步更新策略
    @Async
    public CompletableFuture<Void> asyncUpdate(ProductMaster product) {
        return CompletableFuture.runAsync(() -> {
            // 1. 更新数据库
            productMasterMapper.updateById(product);
            
            // 2. 删除缓存（延迟双删）
            redisTemplate.delete("product:" + product.getSku());
            
            // 3. 发送变更事件
            publishChangeEvent(product);
        }, executorService);
    }
}
```

---

## 九、行业最佳实践

### 9.1 SAP MDG（Master Data Governance）

**核心特点**：
- **集中式管理**：统一管理所有主数据
- **流程驱动**：内置审批工作流
- **数据质量**：强大的数据质量检查
- **版本管理**：支持数据版本和历史追溯

**适用场景**：大型企业，预算充足，需要开箱即用的方案

### 9.2 阿里数据中台

**核心特点**：
- **OneData体系**：统一数据标准、统一数据模型
- **数据资产化**：数据即资产，可盘点、可流通
- **智能数据治理**：AI辅助数据质量管理
- **数据服务化**：数据API化，按需取用

**适用场景**：互联网企业，数据量大，技术能力强

### 9.3 京东供应链主数据管理

**实践经验**：
1. **商品主数据**：200万+SKU，99.9%准确率
2. **供应商主数据**：20万+供应商，分级管理
3. **仓库主数据**：1000+仓库，全国覆盖
4. **数据质量**：自动化质量检查，准确率>99%
5. **同步性能**：5分钟内同步到各系统

---

## 十、总结与展望

### 10.1 主数据管理关键要素

1. **统一标准**：制定统一的数据标准和编码规则
2. **集中管理**：建立主数据平台，集中管理核心主数据
3. **数据质量**：建立数据质量监控体系，持续改进
4. **流程治理**：建立数据治理组织和流程
5. **技术保障**：选择合适的技术架构，确保性能和可靠性

### 10.2 实施建议

**阶段1：规划阶段**（1-2个月）
- 梳理主数据分类
- 设计数据模型
- 制定数据标准
- 建立治理组织

**阶段2：试点阶段**（2-3个月）
- 选择1-2个主数据试点（如商品、客户）
- 搭建MDM平台
- 数据清洗和迁移
- 与1-2个业务系统集成

**阶段3：推广阶段**（3-6个月）
- 扩展到其他主数据
- 与更多业务系统集成
- 数据质量持续改进
- 用户培训和推广

**阶段4：优化阶段**（持续）
- 数据质量监控
- 流程优化
- 技术升级
- 能力提升

### 10.3 未来趋势

1. **AI驱动的数据质量管理**：利用AI自动检测和修复数据质量问题
2. **实时主数据管理**：从批量同步到实时同步，降低数据延迟
3. **数据中台融合**：主数据管理与数据中台深度融合
4. **区块链溯源**：利用区块链技术实现主数据全程溯源
5. **知识图谱**：构建主数据知识图谱，支持智能决策

---

**下一篇预告**：《商品主数据建模：SKU、SPU、品类层级的设计与实践》，我们将深入探讨商品主数据的建模方法和实战技巧。

---

**参考资料**：
1. 《数据治理：如何设计、部署和维护有效的数据治理计划》
2. 《主数据管理：企业数字化转型的基石》
3. SAP MDG官方文档
4. 阿里数据中台实践白皮书
