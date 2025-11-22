---
title: "RF手持终端与设备对接"
date: 2025-11-22T15:00:00+08:00
draft: false
tags: ["WMS", "RF终端", "设备集成", "条码管理"]
categories: ["业务"]
description: "掌握RF手持终端开发、条码管理和自动化设备对接的技术实战"
series: ["WMS从入门到精通"]
weight: 7
stage: 2
stageTitle: "业务实践篇"
---

## 引言

RF手持终端是仓库作业的核心工具,本文讲解RF应用开发、条码管理和设备集成的技术要点。

---

## 1. RF手持终端概述

### 1.1 RF终端的作用

**核心功能**：
1. 条码扫描：快速识别商品和库位
2. 数据采集：实时记录入库、出库、盘点数据
3. 任务指引：系统分配任务，RF显示执行步骤
4. 无线通信：实时与WMS服务器交互

---

### 1.2 常见RF设备

**1. 霍尼韦尔（Honeywell）**
- 型号：CT60、EDA系列
- 系统：Android
- 价格：3000-8000元/台

**2. 斑马（Zebra）**
- 型号：TC系列
- 系统：Android
- 价格：4000-10000元/台

**3. 新大陆（Newland）**
- 型号：MT系列
- 系统：Android
- 价格：2000-5000元/台（国产）

---

## 2. RF应用开发

### 2.1 开发模式

**1. 原生App开发**
- 技术栈：Kotlin/Java + Android SDK
- 优点：性能好、用户体验佳
- 缺点：开发成本高、维护复杂

**2. Web应用（推荐）**
- 技术栈：Vue.js/React + H5
- 优点：开发快、跨平台、易维护
- 缺点：性能稍差

---

### 2.2 扫描枪API对接

**示例：调用设备扫描API**

```javascript
// H5调用扫描枪（Honeywell设备）
window.addEventListener('scan', function(e) {
  const barcode = e.detail.barcode;
  console.log('扫描到条码:', barcode);

  // 调用WMS API校验
  validateBarcode(barcode);
});

function validateBarcode(barcode) {
  fetch('/api/wms/barcode/validate', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ barcode })
  })
  .then(res => res.json())
  .then(data => {
    if (data.valid) {
      alert('SKU: ' + data.sku_name);
    } else {
      alert('无效条码');
    }
  });
}
```

---

### 2.3 界面设计原则

**1. 简洁高效**
- 一屏一任务
- 大按钮（适合手套操作）
- 最少点击次数

**2. 容错性**
- 扫描错误提示
- 撤销功能
- 异常处理

**3. 实时反馈**
- 扫描成功：震动+提示音
- 扫描失败：红色提示

---

## 3. 条码管理

### 3.1 一维码 vs 二维码

**1. 一维码（Barcode）**
```
示例：EAN-13码
格式：6901234567890
优点：成本低、扫描快
缺点：信息量少（只能存储数字）
应用：商品条码、SKU条码
```

**2. 二维码（QR Code）**
```
示例：QR Code
格式：可存储文本、URL
优点：信息量大（可存储几千字符）
缺点：扫描略慢
应用：库位条码、批次条码
```

---

### 3.2 条码生成与打印

**生成条码（Python示例）**：

```python
from barcode import EAN13
from barcode.writer import ImageWriter

# 生成EAN-13条码
ean = EAN13('690123456789', writer=ImageWriter())
ean.save('sku_barcode')
```

**打印条码（ZPL示例）**：

```zpl
^XA
^FO50,50^BY2
^BCN,100,Y,N,N
^FD690123456789^FS
^FO50,180^A0N,30,30
^FDiPhone 15 Pro^FS
^XZ
```

---

### 3.3 批次码、序列号的编码规则

**批次码**：
```
格式：YYYYMMDD-SUPPLIER-SEQ
示例：20251120-SUP001-001

解析：
  2025-11-20：生产日期
  SUP001：供应商编码
  001：批次流水号
```

**序列号**：
```
格式：SKU_PREFIX + 流水号
示例：IP15P-000001

解析：
  IP15P：iPhone 15 Pro缩写
  000001：流水号
```

---

## 4. 打印机集成

### 4.1 打印机类型

**1. 标签打印机**
- 用途：打印商品标签、库位标签
- 品牌：斑马（Zebra）、TSC
- 协议：ZPL、TSPL

**2. 热敏打印机**
- 用途：打印快递面单
- 品牌：佳博、汉印
- 协议：ESC/POS

---

### 4.2 打印协议

**ZPL协议（Zebra Programming Language）**：

```zpl
^XA          // 开始
^FO100,100   // 坐标
^A0N,50,50   // 字体
^FD商品名称^FS // 文本
^BY2         // 条码宽度
^BCN,100     // 条码类型
^FD123456^FS // 条码内容
^XZ          // 结束
```

---

### 4.3 打印模板设计

**商品标签模板**：

```
┌────────────────────────┐
│ SKU: iPhone 15 Pro     │
│ 批次: 20251120         │
│ ████████████████       │ ← 条码
│ 690123456789           │
└────────────────────────┘
```

**库位标签模板**：

```
┌────────────────────────┐
│ 库位: A01-02-03        │
│ ████  ████  ████       │ ← 二维码
│ ████  ████  ████       │
│ ████  ████  ████       │
└────────────────────────┘
```

---

## 5. 电子秤集成

### 5.1 称重数据采集

**串口通信示例**：

```python
import serial

# 打开串口
ser = serial.Serial('/dev/ttyUSB0', 9600)

# 读取重量
weight_data = ser.readline()
weight = float(weight_data.decode().strip())

print(f'称重: {weight}kg')
```

---

### 5.2 重量校验逻辑

**复核称重流程**：

```python
# 系统计算标准重量
standard_weight = calculate_standard_weight(order_items)

# 实际称重
actual_weight = get_weight_from_scale()

# 校验
tolerance = 0.05  # 允许误差5%
diff = abs(actual_weight - standard_weight) / standard_weight

if diff <= tolerance:
    print('称重通过 ✓')
else:
    print('称重异常 ✗，请复核')
```

---

## 6. 自动化设备对接

### 6.1 传送带系统

**功能**：
- 自动传输包裹
- 分拣到不同路线

**对接方式**：
- PLC控制器
- Modbus协议
- TCP/IP通信

---

### 6.2 自动分拣机

**类型**：
- 交叉带分拣机
- 摆轮分拣机
- 滑块分拣机

**WMS对接**：
```java
// 下发分拣任务
POST /api/sorter/task
{
  "package_id": "PKG001",
  "destination_grid": "A05"  // 分拣到A05格口
}
```

---

### 6.3 AGV（自动导引车）

**功能**：
- 自动搬运托盘
- 自动上架/下架

**案例：京东无人仓**
- AGV数量：200台
- 搬运效率：100托盘/小时
- 准确率：99.9%

**WMS对接**：
```java
// 下发搬运任务
POST /api/agv/task
{
  "agv_id": "AGV001",
  "task_type": "move",
  "from_location": "A01-02-03",
  "to_location": "STAGING-01"
}
```

---

## 7. 总结

**RF终端开发要点**：
1. **开发模式**：推荐H5应用（快速、易维护）
2. **扫描API**：调用设备SDK
3. **界面设计**：简洁、大按钮、实时反馈

**设备集成要点**：
1. **打印机**：ZPL协议、标签模板
2. **电子秤**：串口通信、重量校验
3. **自动化设备**：AGV、传送带、分拣机

**下一篇预告**：WMS系统架构设计

---

**版权声明**：本文为原创文章，转载请注明出处。
