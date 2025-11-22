---
title: "商品主数据建模：SKU、SPU、品类层级的设计与实践"
date: 2025-11-22T08:00:00+08:00
draft: false
tags: ["商品主数据", "SKU", "SPU", "数据建模"]
categories: ["供应链"]
description: "深入讲解商品主数据的建模方法，包括SKU/SPU设计、品类层级、属性管理、编码规则等核心内容，结合电商实战案例。"
weight: 2
---

## 一、商品主数据建模核心概念

### 1.1 SPU vs SKU

**SPU（Standard Product Unit）- 标准产品单元**：
- 定义：同一款产品的抽象概念，不考虑规格差异
- 示例：iPhone 15 Pro Max
- 特点：面向商品展示和搜索

**SKU（Stock Keeping Unit）- 库存量单位**：
- 定义：具体到规格的最小销售单元
- 示例：iPhone 15 Pro Max 256GB 黑色
- 特点：面向库存管理和销售

**关系**：1个SPU可以有多个SKU

```
SPU: iPhone 15 Pro Max
├── SKU1: iPhone 15 Pro Max 256GB 黑色
├── SKU2: iPhone 15 Pro Max 256GB 白色
├── SKU3: iPhone 15 Pro Max 512GB 黑色
└── SKU4: iPhone 15 Pro Max 512GB 白色
```

### 1.2 品类层级设计

**三级品类结构**：
```
一级品类: 3C数码
├── 二级品类: 手机通讯
│   ├── 三级品类: 手机
│   ├── 三级品类: 手机配件
│   └── 三级品类: 运营商套餐
├── 二级品类: 电脑办公
│   ├── 三级品类: 笔记本
│   ├── 三级品类: 台式机
│   └── 三级品类: 平板电脑
```

## 二、数据模型设计（完整版）

### 2.1 SPU主数据表
```sql
CREATE TABLE spu_master (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  spu_code VARCHAR(64) UNIQUE NOT NULL,
  spu_name VARCHAR(200) NOT NULL,
  brand_id BIGINT NOT NULL,
  category_id BIGINT NOT NULL,
  product_images JSON COMMENT '商品图片',
  product_desc TEXT COMMENT '商品描述',
  product_params JSON COMMENT '商品参数',
  status VARCHAR(20) DEFAULT 'ACTIVE',
  created_time DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB COMMENT='SPU主数据表';
```

### 2.2 SKU主数据表（详细设计见第一篇文章）

### 2.3 SKU规格属性表
```sql
CREATE TABLE sku_spec (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  sku VARCHAR(64) NOT NULL,
  spec_key VARCHAR(50) NOT NULL COMMENT '规格键：color/size/capacity',
  spec_value VARCHAR(100) NOT NULL COMMENT '规格值：黑色/256GB',
  INDEX idx_sku (sku)
) ENGINE=InnoDB COMMENT='SKU规格属性表';
```

## 三、商品编码规则设计

### 3.1 SKU编码规则

**规则示例**：品类码（2位）+ 品牌码（2位）+ SPU序号（6位）+ 规格码（4位）

```
示例：AP-IP-150001-256B
解释：
- AP: 品类码（Apple产品）
- IP: 品牌码（iPhone）
- 150001: SPU序号
- 256B: 规格码（256GB黑色）
```

**Java实现**：
```java
public class SKUCodeGenerator {
    
    public String generateSKU(Product product) {
        StringBuilder skuCode = new StringBuilder();
        
        // 品类码
        skuCode.append(getCategoryCode(product.getCategoryId()));
        skuCode.append("-");
        
        // 品牌码
        skuCode.append(getBrandCode(product.getBrandId()));
        skuCode.append("-");
        
        // SPU序号（6位递增）
        skuCode.append(getSPUSequence(product.getSpuCode()));
        skuCode.append("-");
        
        // 规格码
        skuCode.append(getSpecCode(product.getSpecs()));
        
        return skuCode.toString();
    }
    
    private String getSpecCode(Map<String, String> specs) {
        StringBuilder code = new StringBuilder();
        
        // 容量编码
        if (specs.containsKey("capacity")) {
            code.append(encodeCapacity(specs.get("capacity")));
        }
        
        // 颜色编码
        if (specs.containsKey("color")) {
            code.append(encodeColor(specs.get("color")));
        }
        
        return code.toString();
    }
}
```

## 四、商品属性管理

### 4.1 销售属性 vs 非销售属性

**销售属性**（影响SKU）：
- 颜色、尺码、容量、版本等
- 示例：iPhone的颜色、容量

**非销售属性**（不影响SKU）：
- 品牌、产地、保质期等
- 示例：iPhone的产地、保修政策

### 4.2 属性模板设计

```java
public class ProductAttributeTemplate {
    
    // 手机品类属性模板
    public static Map<String, AttributeConfig> PHONE_ATTRIBUTES = Map.of(
        "brand", new AttributeConfig("品牌", AttributeType.SELECT, true, false),
        "model", new AttributeConfig("型号", AttributeType.INPUT, true, false),
        "color", new AttributeConfig("颜色", AttributeType.SELECT, true, true),
        "capacity", new AttributeConfig("容量", AttributeType.SELECT, true, true),
        "screen_size", new AttributeConfig("屏幕尺寸", AttributeType.INPUT, false, false),
        "camera", new AttributeConfig("摄像头", AttributeType.INPUT, false, false)
    );
    
    // 属性配置
    @Data
    public static class AttributeConfig {
        private String displayName; // 显示名称
        private AttributeType type; // 属性类型
        private boolean required;   // 是否必填
        private boolean isSaleSpec; // 是否销售属性
    }
}
```

## 五、商品生命周期管理

### 5.1 商品状态流转

```
草稿 → 待审核 → 已上架 → 已下架 → 已删除
```

**状态定义**：
```java
public enum ProductStatus {
    DRAFT("草稿"),
    PENDING_REVIEW("待审核"),
    ONLINE("已上架"),
    OFFLINE("已下架"),
    DELETED("已删除");
}
```

### 5.2 上下架规则

```java
public class ProductLifecycleService {
    
    // 自动上架
    @Scheduled(cron = "0 0 * * * ?")
    public void autoOnline() {
        // 查询预约上架商品
        List<Product> products = productMapper.selectScheduledOnline(LocalDateTime.now());
        
        for (Product product : products) {
            // 检查上架条件
            if (checkOnlineConditions(product)) {
                product.setStatus(ProductStatus.ONLINE);
                productMapper.updateById(product);
                
                // 同步到搜索引擎
                syncToElasticsearch(product);
            }
        }
    }
    
    // 上架条件检查
    private boolean checkOnlineConditions(Product product) {
        // 1. 商品信息完整
        if (!isProductInfoComplete(product)) {
            return false;
        }
        
        // 2. 至少有1个SKU可售
        if (getSaleableSkuCount(product) == 0) {
            return false;
        }
        
        // 3. 商品图片完整（至少3张）
        if (product.getImages().size() < 3) {
            return false;
        }
        
        return true;
    }
}
```

## 六、实战案例：京东商品主数据

### 6.1 数据规模
- 商品SPU：1000万+
- 商品SKU：3000万+
- 品类层级：4级品类
- 属性数量：10000+商品属性

### 6.2 核心特点
1. **细粒度SKU管理**：每个颜色、尺码组合都是独立SKU
2. **动态属性模板**：不同品类有不同属性模板
3. **智能编码**：自动生成全局唯一SKU编码
4. **质量管控**：上架前严格质量检查

### 6.3 性能优化
- **分库分表**：按品类分表，提升查询性能
- **ES搜索**：商品搜索使用Elasticsearch
- **Redis缓存**：热门商品缓存，命中率95%+

---

**参考阅读**：
- 《大型电商商品中心架构设计》
- 《淘宝商品中心设计与实践》
