---
title: "TMS核心概念与数据模型：运输业务的数字化抽象"
date: 2025-11-20T14:00:00+08:00
draft: false
tags: ["TMS", "数据模型", "概念设计", "数据库设计"]
categories: ["供应链系统"]
description: "详细解析TMS中的核心概念和数据模型设计，为系统开发打下坚实基础。从运输订单到GPS轨迹，全面覆盖TMS的数据建模方法论。"
weight: 2
stage: 1
stageTitle: "基础入门篇"
---

## 引言

在上一篇文章中,我们从全景视角了解了TMS系统的整体架构和核心功能。但要真正理解TMS并进行系统开发,必须深入理解其核心概念和数据模型。

本文将详细解析TMS中的核心概念定义、实体关系、数据模型设计以及核心业务规则,为后续的系统设计和开发打下坚实基础。

---

## 1. 核心概念解析

### 1.1 运输订单 (Transport Order)

**定义**：
运输订单是TMS中最核心的业务实体,代表一次完整的运输任务——将一批货物从A点运输到B点。

**核心属性**：
- **订单号**：唯一标识,如`T202511220001`
- **来源订单号**：来自OMS的原始订单号
- **发货地**：发货人姓名、电话、地址(省市区街道)
- **收货地**：收货人姓名、电话、地址(省市区街道)
- **货物信息**：名称、重量、体积、件数、价值
- **时效要求**：标准达(3-5天)、快速达(1-2天)、当日达

**状态流转**：
```
待分配 → 已分配 → 运输中 → 已完成 → 已结算
   ↓        ↓        ↓        ↓
  已取消    已取消    异常件    异常件
```

**状态说明**：
- **待分配**：订单已创建,等待分配承运商
- **已分配**：已分配给承运商,等待揽货
- **运输中**：承运商已揽货,正在运输
- **已完成**：客户已签收
- **已结算**：运费已结算完成
- **已取消**：订单取消(客户原因/缺货等)
- **异常件**：拒收/破损/丢失等异常情况

### 1.2 运单 (Waybill)

**定义**：
运单是承运商接收运输任务后生成的运输凭证,是实际执行运输的单据。

**与运输订单的关系**：
```
1个运输订单 → 1-N个运单

示例：
运输订单: T202511220001 (北京→上海, 100kg货物)
  ├─ 运单1: SF1234567890 (顺丰, 50kg)
  └─ 运单2: SF1234567891 (顺丰, 50kg)
```

**为什么会拆分？**
- 重量/体积超过单个承运商限制
- 不同货物使用不同运输方式
- 风险分散(贵重物品)

**核心属性**：
- **运单号**：承运商生成的唯一编号
- **运输订单ID**：关联的运输订单
- **承运商**：执行运输的物流公司
- **车辆信息**：车牌号、车型
- **司机信息**：姓名、电话
- **时间信息**：揽货时间、预计送达时间、实际送达时间
- **签收信息**：签收人、签收时间、签收照片

**状态流转**：
```
待揽收 → 已揽收 → 运输中 → 派送中 → 已签收
           ↓        ↓        ↓        ↓
         异常件    异常件    异常件    异常件
```

### 1.3 路线 (Route)

**定义**：
路线是从起点到终点经过的一系列节点和路径,用于指导司机配送。

**路线类型**：

1. **固定路线**：
   - 每天固定配送路线
   - 适用于：门店补货、定期配送
   - 示例：仓库 → 门店A → 门店B → 门店C → 仓库

2. **动态路线**：
   - 根据订单实时规划
   - 适用于：电商配送、按需配送
   - 示例：仓库 → 客户1 → 客户2 → 客户3 → ...

**核心属性**：
- **起点**：配送起始位置
- **终点**：配送结束位置
- **途经点**：中间配送点列表
- **预计里程**：总配送距离(km)
- **预计时长**：总配送时间(分钟)
- **实际里程**：GPS记录的实际距离
- **实际时长**：实际花费时间

**路线规划要素**：
- **距离最短**：减少油耗成本
- **时间最短**：提高配送效率
- **避开拥堵**：考虑实时路况
- **避开限行**：遵守交通管制

### 1.4 承运商 (Carrier)

**定义**：
承运商是提供运输服务的第三方物流公司,是TMS的核心资源。

**承运商类型**：

| 类型 | 代表企业 | 服务特点 | 适用场景 |
|-----|---------|---------|---------|
| **快递公司** | 顺丰、三通一达 | 小件、高时效 | 电商包裹 |
| **零担专线** | 德邦、安能 | 中件、标准时效 | B2B物流 |
| **整车公司** | 满帮、货拉拉 | 大件、批量货 | 大宗运输 |
| **海运公司** | 马士基、中远海运 | 国际货运 | 跨境物流 |

**核心属性**：

**基础信息**：
- 承运商编码、名称、类型
- 联系人、电话、邮箱
- 营业执照号、道路运输许可证

**服务信息**：
- **服务区域**：覆盖的省市区(JSON数组)
  ```json
  ["北京市", "上海市", "广东省"]
  ```
- **服务类型**：标准达/快速达/当日达
- **价格体系**：运费模板ID

**合同信息**：
- 合同开始日期、结束日期
- 账期：月结30天、45天、60天
- 结算方式：银行转账/承兑汇票

**绩效信息**：
- **绩效评分**：0-100分(综合评分)
- **等级**：A/B/C/D级
- **准时率**：准时送达订单比例
- **破损率**：货物破损订单比例
- **客诉率**：客户投诉订单比例

### 1.5 车辆 (Vehicle)

**定义**：
车辆是执行运输任务的交通工具,包括自有车辆和承运商车辆。

**车辆类型**：

| 车型 | 载重(吨) | 体积(m³) | 适用场景 |
|-----|----------|----------|---------|
| **厢式货车** | 2-5 | 10-30 | 城市配送 |
| **平板车** | 5-10 | - | 大件运输 |
| **冷链车** | 2-10 | 10-50 | 生鲜、医药 |
| **危险品车** | 5-20 | - | 危化品运输 |

**核心属性**：
- **车辆信息**：车牌号、车型、品牌、颜色
- **载重信息**：额定载重(吨)、额定体积(m³)
- **所属信息**：所属承运商、司机姓名
- **状态信息**：可用/使用中/维修中/报废
- **维保信息**：最后保养时间、下次保养时间、年检到期时间

---

## 2. 数据模型设计

### 2.1 运输订单表 (transport_order)

```sql
CREATE TABLE transport_order (
  -- 主键
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  order_no VARCHAR(64) UNIQUE NOT NULL COMMENT '运输订单号',
  source_order_no VARCHAR(64) COMMENT '来源订单号(OMS)',

  -- 发货信息
  shipper_name VARCHAR(100) NOT NULL COMMENT '发货人',
  shipper_phone VARCHAR(20) NOT NULL,
  shipper_address VARCHAR(500) NOT NULL COMMENT '发货地址',
  shipper_province VARCHAR(20) COMMENT '省',
  shipper_city VARCHAR(20) COMMENT '市',
  shipper_district VARCHAR(20) COMMENT '区',
  shipper_street VARCHAR(200) COMMENT '街道',

  -- 收货信息
  consignee_name VARCHAR(100) NOT NULL COMMENT '收货人',
  consignee_phone VARCHAR(20) NOT NULL,
  consignee_address VARCHAR(500) NOT NULL COMMENT '收货地址',
  consignee_province VARCHAR(20) COMMENT '省',
  consignee_city VARCHAR(20) COMMENT '市',
  consignee_district VARCHAR(20) COMMENT '区',
  consignee_street VARCHAR(200) COMMENT '街道',

  -- 货物信息
  cargo_name VARCHAR(200) COMMENT '货物名称',
  cargo_weight DECIMAL(10,2) NOT NULL COMMENT '货物重量(kg)',
  cargo_volume DECIMAL(10,2) COMMENT '货物体积(m³)',
  cargo_quantity INT COMMENT '件数',
  cargo_value DECIMAL(10,2) COMMENT '货物价值(元)',
  cargo_type VARCHAR(20) COMMENT '货物类型: NORMAL/FRAGILE/VALUABLE/DANGEROUS',

  -- 运输信息
  transport_type VARCHAR(20) COMMENT '运输方式: EXPRESS/LTL/FTL/SEA',
  time_requirement VARCHAR(20) COMMENT '时效要求: STANDARD/EXPRESS/URGENT',
  status VARCHAR(20) NOT NULL COMMENT '状态: PENDING/ASSIGNED/IN_TRANSIT/COMPLETED/CANCELLED',

  -- 承运商信息
  carrier_id BIGINT COMMENT '承运商ID',
  carrier_name VARCHAR(100) COMMENT '承运商名称',

  -- 费用信息
  estimated_freight DECIMAL(10,2) COMMENT '预估运费(元)',
  actual_freight DECIMAL(10,2) COMMENT '实际运费(元)',

  -- 备注
  remark VARCHAR(500) COMMENT '备注',

  -- 时间信息
  created_time DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  completed_time DATETIME COMMENT '完成时间',
  cancelled_time DATETIME COMMENT '取消时间',

  -- 索引
  INDEX idx_order_no(order_no),
  INDEX idx_source_order_no(source_order_no),
  INDEX idx_status(status),
  INDEX idx_carrier_id(carrier_id),
  INDEX idx_consignee_phone(consignee_phone),
  INDEX idx_created_time(created_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='运输订单表';
```

**设计要点**：

1. **订单号设计**：
   ```
   格式: T + YYYYMMDD + 流水号(6位)
   示例: T20251122000001
   ```

2. **地址分段存储**：
   - 省市区街道分别存储,便于统计分析
   - 完整地址也保留,避免拼接错误

3. **金额精度**：
   - 使用`DECIMAL(10,2)`存储金额
   - 避免使用`FLOAT/DOUBLE`导致精度丢失

4. **时间字段**：
   - `created_time`: 创建时间(自动填充)
   - `updated_time`: 更新时间(自动更新)
   - `completed_time`: 完成时间(手动填充)
   - `cancelled_time`: 取消时间(手动填充)

### 2.2 运单表 (waybill)

```sql
CREATE TABLE waybill (
  -- 主键
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  waybill_no VARCHAR(64) UNIQUE NOT NULL COMMENT '运单号',
  transport_order_id BIGINT NOT NULL COMMENT '运输订单ID',

  -- 承运商信息
  carrier_id BIGINT NOT NULL COMMENT '承运商ID',
  carrier_name VARCHAR(100) NOT NULL COMMENT '承运商名称',

  -- 车辆信息
  vehicle_id BIGINT COMMENT '车辆ID',
  vehicle_no VARCHAR(20) COMMENT '车牌号',
  vehicle_type VARCHAR(20) COMMENT '车型',

  -- 司机信息
  driver_id BIGINT COMMENT '司机ID',
  driver_name VARCHAR(50) COMMENT '司机姓名',
  driver_phone VARCHAR(20) COMMENT '司机电话',

  -- 货物信息(冗余,便于查询)
  cargo_weight DECIMAL(10,2) COMMENT '货物重量(kg)',
  cargo_volume DECIMAL(10,2) COMMENT '货物体积(m³)',
  cargo_quantity INT COMMENT '件数',

  -- 时间信息
  pickup_time DATETIME COMMENT '揽货时间',
  estimated_delivery_time DATETIME COMMENT '预计送达时间',
  actual_delivery_time DATETIME COMMENT '实际送达时间',

  -- 状态信息
  status VARCHAR(20) NOT NULL COMMENT '状态: PENDING/PICKED_UP/IN_TRANSIT/DELIVERED/EXCEPTION',
  exception_type VARCHAR(20) COMMENT '异常类型: REJECT/DAMAGE/LOST',
  exception_reason VARCHAR(500) COMMENT '异常原因',

  -- 签收信息
  signer VARCHAR(50) COMMENT '签收人',
  sign_time DATETIME COMMENT '签收时间',
  sign_image VARCHAR(500) COMMENT '签收照片URL',
  sign_type VARCHAR(20) COMMENT '签收方式: PERSON/CABINET/GUARD',

  -- 费用信息
  freight DECIMAL(10,2) COMMENT '运费(元)',

  -- 备注
  remark VARCHAR(500) COMMENT '备注',

  -- 时间信息
  created_time DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  -- 索引
  INDEX idx_waybill_no(waybill_no),
  INDEX idx_transport_order_id(transport_order_id),
  INDEX idx_carrier_id(carrier_id),
  INDEX idx_vehicle_id(vehicle_id),
  INDEX idx_driver_id(driver_id),
  INDEX idx_status(status),
  INDEX idx_pickup_time(pickup_time),
  INDEX idx_actual_delivery_time(actual_delivery_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='运单表';
```

**设计要点**：

1. **运单号来源**：
   - 承运商生成(如顺丰: SF1234567890)
   - TMS生成后推送给承运商

2. **冗余设计**：
   - 货物信息从运输订单冗余到运单
   - 目的：提高查询效率,避免关联查询

3. **签收方式**：
   - `PERSON`: 本人签收
   - `CABINET`: 快递柜
   - `GUARD`: 门卫代收

### 2.3 承运商表 (carrier)

```sql
CREATE TABLE carrier (
  -- 主键
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  carrier_code VARCHAR(50) UNIQUE NOT NULL COMMENT '承运商编码',
  carrier_name VARCHAR(100) NOT NULL COMMENT '承运商名称',
  carrier_type VARCHAR(20) NOT NULL COMMENT '类型: EXPRESS/LTL/FTL/SEA',

  -- 联系信息
  contact_person VARCHAR(50) COMMENT '联系人',
  contact_phone VARCHAR(20) COMMENT '联系电话',
  contact_email VARCHAR(100) COMMENT '联系邮箱',
  contact_address VARCHAR(500) COMMENT '联系地址',

  -- 资质信息
  business_license VARCHAR(50) COMMENT '营业执照号',
  transport_license VARCHAR(50) COMMENT '道路运输许可证',
  license_expire_date DATE COMMENT '许可证到期日期',

  -- 服务信息
  service_area TEXT COMMENT '服务区域(JSON数组)',
  service_type VARCHAR(100) COMMENT '服务类型(标准达/快速达/当日达)',

  -- 合同信息
  contract_no VARCHAR(50) COMMENT '合同编号',
  contract_start_date DATE COMMENT '合同开始日期',
  contract_end_date DATE COMMENT '合同结束日期',
  payment_cycle INT COMMENT '账期(天)',
  settlement_type VARCHAR(20) COMMENT '结算方式: TRANSFER/ACCEPTANCE',

  -- 绩效信息
  performance_score DECIMAL(5,2) DEFAULT 80.00 COMMENT '绩效评分(0-100)',
  grade VARCHAR(10) DEFAULT 'B' COMMENT '等级: A/B/C/D',
  on_time_rate DECIMAL(5,2) COMMENT '准时率(%)',
  damage_rate DECIMAL(5,2) COMMENT '破损率(%)',
  complaint_rate DECIMAL(5,2) COMMENT '客诉率(%)',

  -- 统计信息
  total_orders INT DEFAULT 0 COMMENT '总订单数',
  total_freight DECIMAL(15,2) DEFAULT 0.00 COMMENT '总运费(元)',

  -- 状态
  status VARCHAR(20) DEFAULT 'ACTIVE' COMMENT '状态: ACTIVE/SUSPENDED/TERMINATED',

  -- 时间信息
  created_time DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  -- 索引
  UNIQUE INDEX idx_carrier_code(carrier_code),
  INDEX idx_carrier_name(carrier_name),
  INDEX idx_carrier_type(carrier_type),
  INDEX idx_status(status),
  INDEX idx_grade(grade)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='承运商表';
```

**设计要点**：

1. **编码规则**：
   ```
   格式: 类型前缀 + 流水号
   示例:
     - EXPRESS001 (快递)
     - LTL001 (零担)
     - FTL001 (整车)
   ```

2. **服务区域存储**：
   ```json
   {
     "provinces": ["北京市", "上海市", "广东省"],
     "cities": ["深圳市", "杭州市"],
     "blacklist": ["西藏", "新疆偏远地区"]
   }
   ```

3. **绩效评分计算**：
   ```java
   绩效评分 = 准时率 × 0.4 + (1-破损率) × 0.3 + (1-客诉率) × 0.3
   ```

### 2.4 运费规则表 (freight_rule)

```sql
CREATE TABLE freight_rule (
  -- 主键
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  rule_code VARCHAR(50) UNIQUE NOT NULL COMMENT '规则编码',
  rule_name VARCHAR(100) NOT NULL COMMENT '规则名称',

  -- 适用范围
  carrier_id BIGINT COMMENT '承运商ID',
  transport_type VARCHAR(20) COMMENT '运输方式: EXPRESS/LTL/FTL',
  from_province VARCHAR(20) COMMENT '起始省份',
  from_city VARCHAR(20) COMMENT '起始城市',
  to_province VARCHAR(20) COMMENT '目的省份',
  to_city VARCHAR(20) COMMENT '目的城市',

  -- 计费方式
  calculation_type VARCHAR(20) NOT NULL COMMENT '计费方式: BY_WEIGHT/BY_VOLUME/BY_DISTANCE/BY_PIECE',

  -- 重量计费
  first_weight DECIMAL(10,2) COMMENT '首重(kg)',
  first_weight_price DECIMAL(10,2) COMMENT '首重价格(元)',
  续重_price DECIMAL(10,2) COMMENT '续重价格(元/kg)',

  -- 体积计费
  first_volume DECIMAL(10,2) COMMENT '首体积(m³)',
  first_volume_price DECIMAL(10,2) COMMENT '首体积价格(元)',
  续体积_price DECIMAL(10,2) COMMENT '续体积价格(元/m³)',

  -- 距离计费
  unit_price_per_km DECIMAL(10,2) COMMENT '单价(元/公里)',

  -- 件数计费
  unit_price_per_piece DECIMAL(10,2) COMMENT '单价(元/件)',

  -- 价格限制
  min_charge DECIMAL(10,2) COMMENT '最低收费(元)',
  max_weight DECIMAL(10,2) COMMENT '最大重量(kg)',
  max_volume DECIMAL(10,2) COMMENT '最大体积(m³)',

  -- 时效加价
  standard_rate DECIMAL(5,2) DEFAULT 1.00 COMMENT '标准时效费率',
  express_rate DECIMAL(5,2) DEFAULT 1.20 COMMENT '快速时效费率(+20%)',
  urgent_rate DECIMAL(5,2) DEFAULT 1.50 COMMENT '极速时效费率(+50%)',

  -- 特殊货物加价
  fragile_rate DECIMAL(5,2) DEFAULT 1.10 COMMENT '易碎品费率(+10%)',
  valuable_rate DECIMAL(5,2) DEFAULT 1.20 COMMENT '贵重物品费率(+20%)',
  dangerous_rate DECIMAL(5,2) DEFAULT 1.30 COMMENT '危险品费率(+30%)',

  -- 生效时间
  effective_date DATE NOT NULL COMMENT '生效日期',
  expiry_date DATE COMMENT '失效日期',

  -- 状态
  status VARCHAR(20) DEFAULT 'ACTIVE' COMMENT '状态: ACTIVE/INACTIVE',

  -- 时间信息
  created_time DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  -- 索引
  UNIQUE INDEX idx_rule_code(rule_code),
  INDEX idx_carrier_id(carrier_id),
  INDEX idx_transport_type(transport_type),
  INDEX idx_from_city(from_city),
  INDEX idx_to_city(to_city),
  INDEX idx_effective_date(effective_date),
  INDEX idx_status(status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='运费规则表';
```

**设计要点**：

1. **规则匹配优先级**：
   ```
   精确匹配 > 省级匹配 > 全国通用

   示例：
   1. 北京朝阳 → 上海浦东 (精确匹配)
   2. 北京 → 上海 (省级匹配)
   3. 全国通用规则
   ```

2. **运费计算示例**：
   ```java
   // 重量计费
   if (weight <= first_weight) {
       freight = first_weight_price;
   } else {
       freight = first_weight_price + (weight - first_weight) * 续重_price;
   }

   // 体积重量换算
   volumeWeight = length * width * height / 6000;
   billableWeight = max(actualWeight, volumeWeight);

   // 时效加价
   freight = freight * express_rate; // 快速时效

   // 特殊货物加价
   freight = freight * fragile_rate; // 易碎品

   // 最低收费
   freight = max(freight, min_charge);
   ```

### 2.5 GPS轨迹表 (gps_track)

```sql
CREATE TABLE gps_track (
  -- 主键
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  waybill_no VARCHAR(64) NOT NULL COMMENT '运单号',

  -- 定位信息
  longitude DECIMAL(10,7) NOT NULL COMMENT '经度',
  latitude DECIMAL(10,7) NOT NULL COMMENT '纬度',
  altitude DECIMAL(10,2) COMMENT '海拔(米)',
  accuracy DECIMAL(10,2) COMMENT '定位精度(米)',

  -- 运动信息
  speed DECIMAL(5,2) COMMENT '速度(km/h)',
  direction DECIMAL(5,2) COMMENT '方向角(0-360度)',

  -- 定位方式
  location_type VARCHAR(20) COMMENT '定位类型: GPS/BEIDOU/WIFI/BASE_STATION',

  -- 地址信息(逆地理编码)
  province VARCHAR(20) COMMENT '省',
  city VARCHAR(20) COMMENT '市',
  district VARCHAR(20) COMMENT '区',
  address VARCHAR(500) COMMENT '详细地址',

  -- 时间信息
  location_time DATETIME NOT NULL COMMENT '定位时间',
  created_time DATETIME DEFAULT CURRENT_TIMESTAMP,

  -- 索引
  INDEX idx_waybill_no(waybill_no),
  INDEX idx_location_time(location_time),
  INDEX idx_waybill_time(waybill_no, location_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='GPS轨迹表';
```

**设计要点**：

1. **数据量大,考虑分表**：
   - 按月分表: `gps_track_202511`, `gps_track_202512`
   - 或使用时序数据库: InfluxDB

2. **经纬度精度**：
   - `DECIMAL(10,7)`: 精度约1厘米
   - 示例: `116.4073963` (北京天安门经度)

3. **上报频率**：
   - 运输中: 10秒/次
   - 停止时: 1分钟/次
   - 节省流量和存储

---

## 3. 核心业务规则

### 3.1 订单拆分规则

**拆分场景**：

1. **按承运商拆分**：
   ```
   原订单: 北京 → 上海(100kg) + 广州(50kg)
   拆分后:
     - 订单1: 北京 → 上海(100kg) [承运商A]
     - 订单2: 北京 → 广州(50kg) [承运商B]
   ```

2. **按时效拆分**：
   ```
   原订单: 20件商品
   拆分后:
     - 订单1: 5件紧急商品(次日达) [快递]
     - 订单2: 15件普通商品(标准达) [零担]
   ```

3. **按货物属性拆分**：
   ```
   原订单: 普通货物 + 危险品
   拆分后:
     - 订单1: 普通货物 [普通车辆]
     - 订单2: 危险品 [危险品专用车辆]
   ```

**拆分逻辑**：
```java
public List<TransportOrder> splitOrder(TransportOrder order) {
    List<TransportOrder> result = new ArrayList<>();

    // 按目的地分组
    Map<String, List<Item>> groupByDestination =
        order.getItems().stream()
            .collect(Grouping By(Item::getDestination));

    // 为每个目的地创建子订单
    for (Map.Entry<String, List<Item>> entry : groupByDestination.entrySet()) {
        TransportOrder subOrder = new TransportOrder();
        subOrder.setItems(entry.getValue());
        subOrder.setDestination(entry.getKey());
        result.add(subOrder);
    }

    return result;
}
```

### 3.2 运费计算规则

**计费方式**：

1. **首重续重计费**（快递）：
   ```
   规则:
   - 首重: 1kg, 5元
   - 续重: 2元/kg

   示例:
   - 0.5kg: 5元 (不足首重按首重计)
   - 1kg: 5元
   - 2.5kg: 5 + (2.5-1) × 2 = 8元
   ```

2. **体积重量换算**：
   ```
   体积重量(kg) = 长(cm) × 宽(cm) × 高(cm) ÷ 6000

   示例:
   - 尺寸: 50cm × 40cm × 30cm
   - 体积重量: 50 × 40 × 30 ÷ 6000 = 10kg
   - 实际重量: 5kg
   - 计费重量: max(10kg, 5kg) = 10kg (取大)
   ```

3. **阶梯定价**（零担）：
   ```
   规则:
   - 0-100kg: 2元/kg
   - 100-500kg: 1.5元/kg
   - 500kg+: 1元/kg

   示例:
   - 150kg: 100×2 + 50×1.5 = 275元
   ```

4. **距离计费**（整车）：
   ```
   规则:
   - 单价: 3元/km
   - 起步价: 200元(含50km)

   示例:
   - 30km: 200元 (不足起步里程按起步价计)
   - 100km: 200 + (100-50) × 3 = 350元
   ```

**运费计算引擎**：
```java
public class FreightCalculator {

    public BigDecimal calculate(TransportOrder order, FreightRule rule) {
        BigDecimal freight = BigDecimal.ZERO;

        switch (rule.getCalculationType()) {
            case "BY_WEIGHT":
                freight = calculateByWeight(order, rule);
                break;
            case "BY_VOLUME":
                freight = calculateByVolume(order, rule);
                break;
            case "BY_DISTANCE":
                freight = calculateByDistance(order, rule);
                break;
            case "BY_PIECE":
                freight = calculateByPiece(order, rule);
                break;
        }

        // 时效加价
        freight = freight.multiply(getTimeRequirementRate(order, rule));

        // 特殊货物加价
        freight = freight.multiply(getCargoTypeRate(order, rule));

        // 最低收费
        if (freight.compareTo(rule.getMinCharge()) < 0) {
            freight = rule.getMinCharge();
        }

        return freight;
    }

    private BigDecimal calculateByWeight(TransportOrder order, FreightRule rule) {
        BigDecimal weight = order.getCargoWeight();
        BigDecimal firstWeight = rule.getFirstWeight();
        BigDecimal firstWeightPrice = rule.getFirstWeightPrice();
        BigDecimal 续重Price = rule.get续重Price();

        if (weight.compareTo(firstWeight) <= 0) {
            return firstWeightPrice;
        } else {
            BigDecimal 续重 = weight.subtract(firstWeight);
            return firstWeightPrice.add(续重.multiply(续重Price));
        }
    }

    private BigDecimal getTimeRequirementRate(TransportOrder order, FreightRule rule) {
        String timeReq = order.getTimeRequirement();
        switch (timeReq) {
            case "STANDARD": return rule.getStandardRate();
            case "EXPRESS": return rule.getExpressRate();
            case "URGENT": return rule.getUrgentRate();
            default: return BigDecimal.ONE;
        }
    }

    private BigDecimal getCargoTypeRate(TransportOrder order, FreightRule rule) {
        String cargoType = order.getCargoType();
        switch (cargoType) {
            case "NORMAL": return BigDecimal.ONE;
            case "FRAGILE": return rule.getFragileRate();
            case "VALUABLE": return rule.getValuableRate();
            case "DANGEROUS": return rule.getDangerousRate();
            default: return BigDecimal.ONE;
        }
    }
}
```

### 3.3 时效承诺规则

**时效类型**：

| 时效类型 | 承诺时间 | 适用距离 | 价格倍数 |
|---------|---------|---------|---------|
| **标准达** | 3-5个工作日 | 全国 | 1.0x |
| **快速达** | 1-2个工作日 | <1000km | 1.2x |
| **次日达** | 次日送达 | 同城/省内 | 1.3x |
| **当日达** | 当日送达 | 同城 | 1.5x |

**时效计算**：
```java
public class DeliveryTimeEstimator {

    public LocalDateTime estimateDeliveryTime(TransportOrder order) {
        String timeReq = order.getTimeRequirement();
        LocalDateTime now = LocalDateTime.now();

        switch (timeReq) {
            case "STANDARD":
                // 3-5个工作日
                return now.plusDays(4);

            case "EXPRESS":
                // 1-2个工作日
                return now.plusDays(1);

            case "NEXT_DAY":
                // 次日达(如果下午4点前下单,次日送达;否则后天送达)
                if (now.getHour() < 16) {
                    return now.plusDays(1).withHour(18);
                } else {
                    return now.plusDays(2).withHour(18);
                }

            case "SAME_DAY":
                // 当日达(上午下单下午送,下午下单晚上送)
                if (now.getHour() < 12) {
                    return now.withHour(18);
                } else {
                    return now.withHour(21);
                }

            default:
                return now.plusDays(5);
        }
    }
}
```

---

## 4. 实战案例：跨境电商TMS数据模型

### 4.1 国际运单扩展

跨境电商需要在运单中增加清关信息：

```sql
CREATE TABLE international_waybill (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  waybill_no VARCHAR(64) UNIQUE NOT NULL,
  transport_order_id BIGINT NOT NULL,

  -- 基础运单字段(同国内运单)
  -- ...

  -- 跨境扩展字段
  departure_country VARCHAR(50) COMMENT '启运国',
  departure_port VARCHAR(100) COMMENT '启运港',
  destination_country VARCHAR(50) COMMENT '目的国',
  destination_port VARCHAR(100) COMMENT '目的港',

  -- 清关信息
  hs_code VARCHAR(20) COMMENT 'HS编码',
  customs_declaration_no VARCHAR(64) COMMENT '报关单号',
  customs_status VARCHAR(20) COMMENT '清关状态: PENDING/DECLARED/CLEARED/REJECTED',
  customs_time DATETIME COMMENT '清关时间',

  -- 贸易方式
  trade_mode VARCHAR(20) COMMENT '贸易方式: GENERAL/BONDED/CROSS_BORDER',

  -- 税费信息
  import_duty DECIMAL(10,2) COMMENT '进口关税',
  import_vat DECIMAL(10,2) COMMENT '进口增值税',
  consumption_tax DECIMAL(10,2) COMMENT '消费税',

  INDEX idx_customs_declaration_no(customs_declaration_no),
  INDEX idx_customs_status(customs_status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='国际运单表';
```

### 4.2 多段运输

跨境物流通常涉及多段运输(海运+陆运+快递)：

```sql
CREATE TABLE waybill_segment (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  waybill_no VARCHAR(64) NOT NULL COMMENT '运单号',
  segment_no INT NOT NULL COMMENT '段号(1,2,3...)',

  -- 运输方式
  transport_type VARCHAR(20) COMMENT 'SEA/AIR/LAND/EXPRESS',

  -- 起止信息
  from_location VARCHAR(200) COMMENT '起始地点',
  to_location VARCHAR(200) COMMENT '目的地点',

  -- 承运商
  carrier_id BIGINT COMMENT '承运商ID',
  carrier_name VARCHAR(100),

  -- 时间
  start_time DATETIME COMMENT '开始时间',
  end_time DATETIME COMMENT '结束时间',

  -- 状态
  status VARCHAR(20) COMMENT '状态: PENDING/IN_TRANSIT/COMPLETED',

  INDEX idx_waybill_no(waybill_no),
  INDEX idx_segment_no(waybill_no, segment_no)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='运单段表';
```

**示例**：
```
运单: INT202511220001
  - 段1: 海运 (深圳港 → 洛杉矶港) [马士基] [15天]
  - 段2: 陆运 (洛杉矶港 → 仓库) [卡车] [1天]
  - 段3: 快递 (仓库 → 客户) [UPS] [2天]
```

### 4.3 多币种运费

跨境物流涉及多币种：

```sql
CREATE TABLE freight_multi_currency (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  waybill_no VARCHAR(64) NOT NULL,

  -- 运费(多币种)
  freight_cny DECIMAL(10,2) COMMENT '运费(人民币)',
  freight_usd DECIMAL(10,2) COMMENT '运费(美元)',
  freight_eur DECIMAL(10,2) COMMENT '运费(欧元)',

  -- 汇率
  exchange_rate_usd DECIMAL(10,4) COMMENT 'USD汇率',
  exchange_rate_eur DECIMAL(10,4) COMMENT 'EUR汇率',

  -- 结算币种
  settlement_currency VARCHAR(10) COMMENT '结算币种: CNY/USD/EUR'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='运费多币种表';
```

---

## 5. 数据模型优化

### 5.1 分库分表

当订单量超过1000万时,考虑分库分表：

**分表策略**：
- **按订单号分表**：`order_no % 10` → `transport_order_0` ~ `transport_order_9`
- **按时间分表**：按月分表 `transport_order_202511`, `transport_order_202512`

**ShardingSphere配置示例**：
```yaml
tables:
  transport_order:
    actual-data-nodes: ds0.transport_order_${0..9}
    table-strategy:
      standard:
        sharding-column: order_no
        sharding-algorithm-name: order_mod
sharding-algorithms:
  order_mod:
    type: MOD
    props:
      sharding-count: 10
```

### 5.2 读写分离

**主从架构**：
```
主库(Master): 处理写操作(INSERT/UPDATE/DELETE)
从库(Slave1, Slave2): 处理读操作(SELECT)
```

**MyBatis配置示例**：
```java
@DataSource("slave")
public List<TransportOrder> queryOrders(String status) {
    // 从从库读取
}

@DataSource("master")
public void createOrder(TransportOrder order) {
    // 写入主库
}
```

### 5.3 索引优化

**常用查询场景**：
```sql
-- 1. 按订单号查询(主键/唯一索引)
SELECT * FROM transport_order WHERE order_no = 'T202511220001';

-- 2. 按状态查询(普通索引)
SELECT * FROM transport_order WHERE status = 'PENDING';

-- 3. 按创建时间范围查询(普通索引)
SELECT * FROM transport_order WHERE created_time BETWEEN '2025-11-01' AND '2025-11-30';

-- 4. 按承运商+状态查询(联合索引)
SELECT * FROM transport_order WHERE carrier_id = 100 AND status = 'IN_TRANSIT';
CREATE INDEX idx_carrier_status ON transport_order(carrier_id, status);

-- 5. 按收货人电话查询(普通索引)
SELECT * FROM transport_order WHERE consignee_phone = '13800138000';
```

---

## 6. 总结

本文详细解析了TMS的核心概念和数据模型设计,为系统开发提供了完整的数据建模方案。

**核心要点**：

1. **核心概念**：
   - 运输订单: TMS的核心业务实体
   - 运单: 承运商执行的运输凭证
   - 路线: 配送路径规划
   - 承运商: 运输服务提供商
   - 车辆: 运输执行载体

2. **数据模型**：
   - 运输订单表: 存储订单基本信息
   - 运单表: 存储运输执行信息
   - 承运商表: 存储承运商档案
   - 运费规则表: 存储计费规则
   - GPS轨迹表: 存储定位数据

3. **业务规则**：
   - 订单拆分规则: 按承运商/时效/货物属性拆分
   - 运费计算规则: 首重续重/体积重量/距离计费
   - 时效承诺规则: 标准达/快速达/次日达/当日达

4. **数据模型优化**：
   - 分库分表: 应对海量数据
   - 读写分离: 提升查询性能
   - 索引优化: 加速常用查询

在下一篇文章中,我们将深入探讨运输计划与订单分配的业务逻辑和技术实现,敬请期待！

---

## 参考资料

- MySQL官方文档
- ShardingSphere分库分表方案
- 《数据库设计与实现》
- 《阿里巴巴Java开发手册》
- 京东物流技术博客
