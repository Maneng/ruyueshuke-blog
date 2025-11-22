---
title: "售后管理：退货退款与换货补发的全流程设计"
date: 2025-11-22T12:30:00+08:00
draft: false
tags: ["OMS", "售后管理", "退货退款", "换货", "工单系统"]
categories: ["技术"]
description: "深入解析售后业务的全流程设计，包括退货、退款、换货、补发等核心场景，以及售后工单系统的实现"
series: ["OMS订单管理系统"]
weight: 8
stage: 3
stageTitle: "履约售后篇"
---

## 引言

电商行业有一句话：**售前服务决定转化率，售后服务决定复购率**。

用户下单只是交易的开始，真正考验电商平台能力的是售后服务。当用户收到商品后发现质量问题、尺码不合适、或者根本没收到货时，OMS系统如何快速、高效地处理退货、退款、换货、补发等售后请求？

售后管理不仅仅是业务流程的设计，更涉及财务对账、库存回流、物流逆向、客服工单等多个系统的协同。本文将从第一性原理出发，系统性地探讨售后管理的设计与实现。

## 售后业务全景

### 售后类型分类

```
售后业务四大类型：

1. 仅退款（未发货/未收货）
   - 场景：订单未发货，用户取消订单
   - 流程：审核 → 退款 → 释放库存

2. 退货退款（已收货）
   - 场景：商品质量问题、不喜欢、描述不符
   - 流程：申请 → 审核 → 退货 → 验货 → 退款 → 入库

3. 换货（同款/异款）
   - 场景：尺码不合适、颜色不喜欢
   - 流程：申请 → 审核 → 退货 → 验货 → 发新货

4. 补发（未收到货/少货）
   - 场景：物流丢件、发货少件
   - 流程：申请 → 核实 → 补发
```

### 售后状态流转

```python
class AfterSalesStatus:
    """售后状态"""

    # 状态枚举
    PENDING_REVIEW = 'PENDING_REVIEW'         # 待审核
    APPROVED = 'APPROVED'                     # 已同意
    REJECTED = 'REJECTED'                     # 已拒绝
    WAITING_RETURN = 'WAITING_RETURN'         # 待退货
    RETURNED = 'RETURNED'                     # 已退货
    INSPECTING = 'INSPECTING'                 # 验货中
    INSPECTION_PASSED = 'INSPECTION_PASSED'   # 验货通过
    INSPECTION_FAILED = 'INSPECTION_FAILED'   # 验货失败
    REFUNDING = 'REFUNDING'                   # 退款中
    REFUNDED = 'REFUNDED'                     # 已退款
    EXCHANGING = 'EXCHANGING'                 # 换货中
    EXCHANGED = 'EXCHANGED'                   # 已换货
    CLOSED = 'CLOSED'                         # 已关闭

    # 状态流转规则
    TRANSITIONS = {
        PENDING_REVIEW: [APPROVED, REJECTED],
        APPROVED: [WAITING_RETURN, REFUNDING],
        WAITING_RETURN: [RETURNED, CLOSED],
        RETURNED: [INSPECTING],
        INSPECTING: [INSPECTION_PASSED, INSPECTION_FAILED],
        INSPECTION_PASSED: [REFUNDING, EXCHANGING],
        INSPECTION_FAILED: [CLOSED],
        REFUNDING: [REFUNDED],
        EXCHANGING: [EXCHANGED]
    }

    @classmethod
    def can_transition(cls, from_status, to_status):
        """判断状态是否可以流转"""
        allowed_statuses = cls.TRANSITIONS.get(from_status, [])
        return to_status in allowed_statuses
```

## 退货流程设计

### 退货申请

```python
class RefundService:
    """退货退款服务"""

    def create_refund_request(self, user_id, request_data):
        """
        创建退货申请

        Args:
            user_id: 用户ID
            request_data: {
                'order_id': 订单ID,
                'items': [退货商品列表],
                'reason': 退货原因,
                'description': 问题描述,
                'evidence': [图片/视频凭证]
            }
        """
        # 1. 校验订单
        order = self._validate_order_for_refund(
            user_id,
            request_data['order_id']
        )

        # 2. 校验退货商品
        self._validate_refund_items(
            order,
            request_data['items']
        )

        # 3. 检查是否超过退货期限
        if not self._check_refund_deadline(order):
            raise RefundDeadlineExceededException(
                "超过退货期限（7天无理由退货）"
            )

        # 4. 创建售后单
        refund = AfterSalesOrder(
            after_sales_id=self._generate_id(),
            order_id=order.order_id,
            user_id=user_id,
            type='REFUND',
            status='PENDING_REVIEW',
            items=[
                AfterSalesItem(
                    sku_id=item['sku_id'],
                    quantity=item['quantity'],
                    reason=request_data['reason']
                )
                for item in request_data['items']
            ],
            reason=request_data['reason'],
            description=request_data['description'],
            evidence=request_data['evidence'],
            created_at=datetime.now()
        )

        # 5. 保存售后单
        self.after_sales_repo.save(refund)

        # 6. 触发审核流程
        self._trigger_review_process(refund)

        return refund

    def _validate_order_for_refund(self, user_id, order_id):
        """校验订单可退货性"""
        order = self.order_repo.find_by_id(order_id)

        # 检查订单是否存在
        if not order:
            raise OrderNotFoundException(order_id)

        # 检查订单归属
        if order.user_id != user_id:
            raise UnauthorizedException("无权操作该订单")

        # 检查订单状态
        if order.status not in ['DELIVERED', 'COMPLETED']:
            raise InvalidOrderStatusException(
                "订单未完成，无法申请退货"
            )

        # 检查是否已有售后单
        existing_refund = self.after_sales_repo.find_by_order(order_id)
        if existing_refund and existing_refund.status not in ['REJECTED', 'CLOSED']:
            raise RefundAlreadyExistsException(
                "该订单已有进行中的售后申请"
            )

        return order

    def _check_refund_deadline(self, order):
        """检查退货期限"""
        # 7天无理由退货
        deadline = order.delivered_at + timedelta(days=7)
        return datetime.now() <= deadline
```

### 退货审核

```python
class RefundReviewService:
    """退货审核服务"""

    def review_refund(self, after_sales_id, reviewer_id, decision, reason=None):
        """
        审核退货申请

        Args:
            after_sales_id: 售后单ID
            reviewer_id: 审核人ID
            decision: 审核结果（APPROVE/REJECT）
            reason: 拒绝原因
        """
        # 1. 查询售后单
        refund = self.after_sales_repo.find_by_id(after_sales_id)

        # 2. 校验状态
        if refund.status != 'PENDING_REVIEW':
            raise InvalidStatusException(
                "售后单状态不正确，无法审核"
            )

        # 3. 执行审核
        if decision == 'APPROVE':
            self._approve_refund(refund, reviewer_id)
        elif decision == 'REJECT':
            self._reject_refund(refund, reviewer_id, reason)
        else:
            raise InvalidDecisionException(decision)

    def _approve_refund(self, refund, reviewer_id):
        """同意退货"""
        # 1. 更新售后单状态
        refund.status = 'APPROVED'
        refund.reviewer_id = reviewer_id
        refund.reviewed_at = datetime.now()

        # 2. 判断是否需要退货
        order = self.order_repo.find_by_id(refund.order_id)

        if order.status == 'DELIVERED':
            # 已收货，需要退货
            refund.status = 'WAITING_RETURN'
            refund.return_deadline = datetime.now() + timedelta(days=7)

            # 生成退货物流单
            self._create_return_waybill(refund)
        else:
            # 未发货/未收货，直接退款
            refund.status = 'REFUNDING'
            self._process_refund(refund)

        # 3. 保存售后单
        self.after_sales_repo.update(refund)

        # 4. 发送通知
        self._send_approval_notification(refund)

    def _reject_refund(self, refund, reviewer_id, reason):
        """拒绝退货"""
        refund.status = 'REJECTED'
        refund.reviewer_id = reviewer_id
        refund.reviewed_at = datetime.now()
        refund.reject_reason = reason

        self.after_sales_repo.update(refund)

        # 发送拒绝通知
        self._send_rejection_notification(refund, reason)

    def _create_return_waybill(self, refund):
        """创建退货物流单"""
        # 获取订单信息
        order = self.order_repo.find_by_id(refund.order_id)

        # 生成退货地址（退回到发货仓库）
        warehouse = self.warehouse_repo.find_by_id(order.warehouse_id)

        # 调用物流API创建运单
        waybill = self.logistics_service.create_return_waybill(
            sender_address=order.delivery_address,
            receiver_address=warehouse.address,
            items=refund.items
        )

        # 保存运单信息
        refund.return_tracking_number = waybill.tracking_number
        refund.return_logistics_company = waybill.logistics_company

        self.after_sales_repo.update(refund)
```

### 退货验货

```python
class ReturnInspectionService:
    """退货验货服务"""

    def inspect_return(self, after_sales_id, inspector_id, inspection_result):
        """
        退货验货

        Args:
            after_sales_id: 售后单ID
            inspector_id: 验货员ID
            inspection_result: {
                'passed': True/False,
                'items': [
                    {
                        'sku_id': 'SKU001',
                        'quantity': 2,
                        'condition': 'GOOD/DAMAGED/MISSING',
                        'notes': '备注'
                    }
                ],
                'photos': [验货照片]
            }
        """
        # 1. 查询售后单
        refund = self.after_sales_repo.find_by_id(after_sales_id)

        # 2. 校验状态
        if refund.status != 'RETURNED':
            raise InvalidStatusException("售后单状态不正确")

        # 3. 记录验货结果
        inspection = InspectionRecord(
            after_sales_id=after_sales_id,
            inspector_id=inspector_id,
            passed=inspection_result['passed'],
            items=inspection_result['items'],
            photos=inspection_result['photos'],
            inspected_at=datetime.now()
        )
        self.inspection_repo.save(inspection)

        # 4. 更新售后单状态
        if inspection_result['passed']:
            refund.status = 'INSPECTION_PASSED'
            # 触发退款流程
            self._process_refund(refund)

            # 商品入库
            self._return_to_inventory(refund, inspection_result['items'])
        else:
            refund.status = 'INSPECTION_FAILED'
            refund.inspection_failure_reason = self._analyze_failure_reason(
                inspection_result['items']
            )

            # 发送验货失败通知
            self._send_inspection_failure_notification(refund)

        self.after_sales_repo.update(refund)

    def _return_to_inventory(self, refund, inspected_items):
        """退货商品入库"""
        order = self.order_repo.find_by_id(refund.order_id)

        for item in inspected_items:
            if item['condition'] == 'GOOD':
                # 良品入库，增加可用库存
                self.inventory_service.increase_stock(
                    sku_id=item['sku_id'],
                    warehouse_id=order.warehouse_id,
                    quantity=item['quantity'],
                    reason=f"退货入库 - {refund.after_sales_id}"
                )
            elif item['condition'] == 'DAMAGED':
                # 次品入库，进入待处理区
                self.inventory_service.increase_damaged_stock(
                    sku_id=item['sku_id'],
                    warehouse_id=order.warehouse_id,
                    quantity=item['quantity'],
                    reason=f"退货次品 - {refund.after_sales_id}"
                )
```

## 退款流程设计

### 退款金额计算

```python
class RefundAmountCalculator:
    """退款金额计算器"""

    def calculate_refund_amount(self, refund):
        """
        计算退款金额

        退款金额组成：
        1. 商品金额
        2. 运费（特定条件下退）
        3. 优惠券（部分退）
        4. 积分抵扣（退回积分）
        """
        order = self.order_repo.find_by_id(refund.order_id)

        # 1. 计算商品金额
        items_amount = self._calculate_items_amount(refund, order)

        # 2. 计算运费
        shipping_fee = self._calculate_shipping_fee_refund(refund, order)

        # 3. 计算优惠金额
        discount_amount = self._calculate_discount_refund(refund, order)

        # 4. 总退款金额
        total_refund = items_amount + shipping_fee - discount_amount

        return RefundAmount(
            items_amount=items_amount,
            shipping_fee=shipping_fee,
            discount_amount=discount_amount,
            total_amount=total_refund
        )

    def _calculate_items_amount(self, refund, order):
        """计算商品金额"""
        total = 0

        for refund_item in refund.items:
            # 查找订单中对应的商品
            order_item = next(
                (item for item in order.items if item.sku_id == refund_item.sku_id),
                None
            )

            if order_item:
                # 计算该商品的退款金额
                unit_price = order_item.price
                quantity = refund_item.quantity
                total += unit_price * quantity

        return total

    def _calculate_shipping_fee_refund(self, refund, order):
        """
        计算运费退款

        规则：
        1. 全部退货：退运费
        2. 部分退货：不退运费
        3. 商品质量问题：退运费
        4. 包邮订单：不退运费
        """
        # 全部退货
        if self._is_full_refund(refund, order):
            return order.shipping_fee

        # 商品质量问题
        if refund.reason in ['QUALITY_ISSUE', 'DAMAGED']:
            return order.shipping_fee

        # 其他情况不退运费
        return 0

    def _calculate_discount_refund(self, refund, order):
        """
        计算优惠退款

        规则：
        1. 优惠券：按比例退
        2. 满减：不退（除非全部退货）
        3. 积分抵扣：退回积分
        """
        discount = 0

        # 优惠券按比例退
        if order.coupon_amount > 0:
            refund_ratio = self._calculate_refund_ratio(refund, order)
            discount += order.coupon_amount * refund_ratio

        # 满减（全部退货才退）
        if self._is_full_refund(refund, order):
            discount += order.promotion_discount

        return discount
```

### 退款执行

```python
class RefundProcessor:
    """退款处理器"""

    def process_refund(self, refund):
        """
        执行退款

        退款渠道优先级：
        1. 原路退回（优先）
        2. 退到余额
        3. 线下退款
        """
        try:
            # 1. 计算退款金额
            refund_amount = self.amount_calculator.calculate_refund_amount(refund)

            # 2. 更新售后单
            refund.refund_amount = refund_amount.total_amount
            refund.status = 'REFUNDING'
            self.after_sales_repo.update(refund)

            # 3. 调用支付网关退款
            order = self.order_repo.find_by_id(refund.order_id)
            payment = self.payment_repo.find_by_order(order.order_id)

            refund_result = self.payment_gateway.refund(
                payment_id=payment.payment_id,
                refund_amount=refund_amount.total_amount,
                reason=refund.reason
            )

            # 4. 更新退款记录
            refund.refund_transaction_id = refund_result.transaction_id
            refund.refund_channel = payment.payment_channel
            refund.refunded_at = datetime.now()
            refund.status = 'REFUNDED'

            # 5. 退回积分（如果有积分抵扣）
            if order.points_used > 0:
                self._refund_points(order, refund)

            # 6. 退回优惠券（如果符合条件）
            if order.coupon_id and self._is_full_refund(refund, order):
                self._refund_coupon(order)

            # 7. 更新订单状态
            order.status = 'REFUNDED'
            self.order_repo.update(order)

            # 8. 发送退款成功通知
            self._send_refund_success_notification(refund)

            self.after_sales_repo.update(refund)

            return refund_result

        except Exception as e:
            # 退款失败
            refund.status = 'REFUND_FAILED'
            refund.refund_failure_reason = str(e)
            self.after_sales_repo.update(refund)

            # 发送告警
            self._send_refund_failure_alert(refund, e)

            raise

    def _refund_points(self, order, refund):
        """退回积分"""
        # 计算退回比例
        refund_ratio = self._calculate_refund_ratio(refund, order)

        # 退回积分
        points_to_refund = int(order.points_used * refund_ratio)

        self.points_service.refund(
            user_id=order.user_id,
            points=points_to_refund,
            reason=f"订单退款 - {refund.after_sales_id}"
        )

    def _refund_coupon(self, order):
        """退回优惠券"""
        if order.coupon_id:
            self.coupon_service.refund(
                user_id=order.user_id,
                coupon_id=order.coupon_id,
                reason=f"订单退款 - {order.order_id}"
            )
```

## 换货流程设计

### 换货申请

```python
class ExchangeService:
    """换货服务"""

    def create_exchange_request(self, user_id, request_data):
        """
        创建换货申请

        Args:
            request_data: {
                'order_id': 订单ID,
                'items': [
                    {
                        'sku_id': '原SKU',
                        'quantity': 数量,
                        'exchange_sku_id': '换货SKU',
                        'reason': '换货原因'
                    }
                ]
            }
        """
        # 1. 校验订单
        order = self._validate_order_for_exchange(user_id, request_data['order_id'])

        # 2. 校验换货商品
        self._validate_exchange_items(order, request_data['items'])

        # 3. 检查新商品库存
        for item in request_data['items']:
            if not self._check_stock(item['exchange_sku_id'], item['quantity']):
                raise InsufficientStockException(
                    f"换货商品库存不足: {item['exchange_sku_id']}"
                )

        # 4. 创建换货单
        exchange = AfterSalesOrder(
            after_sales_id=self._generate_id(),
            order_id=order.order_id,
            user_id=user_id,
            type='EXCHANGE',
            status='PENDING_REVIEW',
            items=[
                ExchangeItem(
                    original_sku_id=item['sku_id'],
                    exchange_sku_id=item['exchange_sku_id'],
                    quantity=item['quantity'],
                    reason=item['reason']
                )
                for item in request_data['items']
            ],
            created_at=datetime.now()
        )

        # 5. 预占新商品库存
        self._reserve_exchange_items(exchange)

        # 6. 保存换货单
        self.after_sales_repo.save(exchange)

        return exchange

    def process_exchange(self, exchange):
        """
        执行换货

        流程：
        1. 用户退回原商品
        2. 仓库验货
        3. 发出新商品
        4. 完成换货
        """
        # 1. 等待用户退货
        if exchange.status != 'RETURNED':
            raise InvalidStatusException("等待用户退货")

        # 2. 验货
        inspection_result = self._inspect_exchange_items(exchange)

        if not inspection_result['passed']:
            # 验货失败，取消换货
            exchange.status = 'INSPECTION_FAILED'
            self._release_exchange_reservation(exchange)
            self.after_sales_repo.update(exchange)
            return

        # 3. 发出新商品
        new_order = self._create_exchange_order(exchange)

        # 4. 更新换货单状态
        exchange.status = 'EXCHANGING'
        exchange.new_order_id = new_order.order_id
        self.after_sales_repo.update(exchange)

        # 5. 下发WMS
        self.fulfillment_service.fulfill_order(new_order)
```

## 补发流程设计

### 补发申请

```python
class ReshipService:
    """补发服务"""

    def create_reship_request(self, user_id, request_data):
        """
        创建补发申请

        适用场景：
        1. 物流丢件
        2. 发货少件
        3. 商品破损
        """
        # 1. 校验订单
        order = self._validate_order_for_reship(user_id, request_data['order_id'])

        # 2. 核实补发原因
        reason = request_data['reason']

        if reason == 'LOST_IN_TRANSIT':
            # 物流丢件，需要核实物流状态
            if not self._verify_lost_in_transit(order):
                raise InvalidReshipReasonException(
                    "物流状态正常，无法申请补发"
                )

        elif reason == 'SHORTAGE':
            # 少件，需要提供凭证
            if not request_data.get('evidence'):
                raise EvidenceRequiredException(
                    "少件需要提供开箱视频等凭证"
                )

        # 3. 创建补发单
        reship = AfterSalesOrder(
            after_sales_id=self._generate_id(),
            order_id=order.order_id,
            user_id=user_id,
            type='RESHIP',
            status='PENDING_REVIEW',
            items=request_data['items'],
            reason=reason,
            evidence=request_data.get('evidence'),
            created_at=datetime.now()
        )

        # 4. 保存补发单
        self.after_sales_repo.save(reship)

        # 5. 自动审核（特定场景）
        if self._should_auto_approve(reship):
            self._approve_reship(reship)

        return reship

    def _verify_lost_in_transit(self, order):
        """核实物流丢件"""
        # 查询物流信息
        tracking_info = self.logistics_service.query_tracking(
            order.tracking_number
        )

        # 判断是否丢件
        if tracking_info.status == 'LOST':
            return True

        # 超过预计送达时间3天，视为丢件
        if order.estimated_delivery_date:
            days_overdue = (datetime.now() - order.estimated_delivery_date).days
            if days_overdue > 3:
                return True

        return False

    def process_reship(self, reship):
        """执行补发"""
        # 1. 创建补发订单
        reship_order = self._create_reship_order(reship)

        # 2. 更新补发单
        reship.status = 'RESHIPPING'
        reship.reship_order_id = reship_order.order_id
        self.after_sales_repo.update(reship)

        # 3. 下发WMS
        self.fulfillment_service.fulfill_order(reship_order)

        # 4. 原订单标记为已补发
        original_order = self.order_repo.find_by_id(reship.order_id)
        original_order.has_reship = True
        original_order.reship_order_id = reship_order.order_id
        self.order_repo.update(original_order)
```

## 售后工单系统

### 工单创建与流转

```python
class AfterSalesTicketSystem:
    """售后工单系统"""

    def create_ticket(self, after_sales_id):
        """创建售后工单"""
        after_sales = self.after_sales_repo.find_by_id(after_sales_id)

        # 1. 创建工单
        ticket = Ticket(
            ticket_id=self._generate_ticket_id(),
            after_sales_id=after_sales_id,
            order_id=after_sales.order_id,
            user_id=after_sales.user_id,
            type=after_sales.type,
            priority=self._calculate_priority(after_sales),
            status='OPEN',
            created_at=datetime.now(),
            assigned_to=None
        )

        # 2. 自动分配客服
        agent = self._assign_agent(ticket)
        if agent:
            ticket.assigned_to = agent.agent_id

        # 3. 保存工单
        self.ticket_repo.save(ticket)

        # 4. 发送通知给客服
        self._notify_agent(agent, ticket)

        return ticket

    def _calculate_priority(self, after_sales):
        """
        计算工单优先级

        规则：
        1. VIP用户 → HIGH
        2. 金额>1000元 → HIGH
        3. 退货原因是质量问题 → HIGH
        4. 其他 → NORMAL
        """
        order = self.order_repo.find_by_id(after_sales.order_id)

        # VIP用户
        if order.user.is_vip:
            return 'HIGH'

        # 高价值订单
        if order.total_amount > 1000:
            return 'HIGH'

        # 质量问题
        if after_sales.reason in ['QUALITY_ISSUE', 'DAMAGED']:
            return 'HIGH'

        return 'NORMAL'

    def _assign_agent(self, ticket):
        """
        分配客服

        策略：
        1. 按组分配（退货组、换货组、投诉组）
        2. 负载均衡（选择当前工单最少的客服）
        3. 技能匹配（VIP客户分配给高级客服）
        """
        # 1. 确定客服组
        group = self._determine_agent_group(ticket)

        # 2. 查询组内可用客服
        available_agents = self.agent_repo.find_available(group)

        # 3. 负载均衡
        agent = min(
            available_agents,
            key=lambda a: self._get_agent_workload(a.agent_id)
        )

        return agent

    def handle_ticket(self, ticket_id, agent_id, action, data):
        """
        处理工单

        Actions:
        - APPROVE: 同意售后
        - REJECT: 拒绝售后
        - REQUEST_INFO: 要求补充信息
        - ESCALATE: 升级到上级
        """
        ticket = self.ticket_repo.find_by_id(ticket_id)

        if action == 'APPROVE':
            self._approve_ticket(ticket, agent_id)
        elif action == 'REJECT':
            self._reject_ticket(ticket, agent_id, data['reason'])
        elif action == 'REQUEST_INFO':
            self._request_more_info(ticket, agent_id, data['required_info'])
        elif action == 'ESCALATE':
            self._escalate_ticket(ticket, agent_id, data['reason'])

        # 记录工单操作日志
        self._log_ticket_action(ticket, agent_id, action, data)
```

### 工单监控与SLA

```python
class TicketSLAMonitor:
    """工单SLA监控"""

    # SLA标准
    SLA_STANDARDS = {
        'RESPONSE_TIME': {
            'HIGH': 1,    # 1小时内响应
            'NORMAL': 4   # 4小时内响应
        },
        'RESOLUTION_TIME': {
            'HIGH': 24,   # 24小时内解决
            'NORMAL': 72  # 72小时内解决
        }
    }

    def check_sla_compliance(self, ticket):
        """检查SLA达标情况"""
        # 1. 检查响应时效
        response_sla = self._check_response_time(ticket)

        # 2. 检查解决时效
        resolution_sla = self._check_resolution_time(ticket)

        return SLAResult(
            response_compliant=response_sla['compliant'],
            response_elapsed=response_sla['elapsed'],
            resolution_compliant=resolution_sla['compliant'],
            resolution_elapsed=resolution_sla['elapsed']
        )

    def _check_response_time(self, ticket):
        """检查响应时效"""
        if not ticket.first_response_at:
            # 未响应
            elapsed = (datetime.now() - ticket.created_at).total_seconds() / 3600
            threshold = self.SLA_STANDARDS['RESPONSE_TIME'][ticket.priority]

            return {
                'compliant': elapsed <= threshold,
                'elapsed': elapsed,
                'threshold': threshold
            }

        # 已响应
        elapsed = (ticket.first_response_at - ticket.created_at).total_seconds() / 3600
        threshold = self.SLA_STANDARDS['RESPONSE_TIME'][ticket.priority]

        return {
            'compliant': elapsed <= threshold,
            'elapsed': elapsed,
            'threshold': threshold
        }

    def monitor_overdue_tickets(self):
        """监控超时工单"""
        # 查询所有未关闭的工单
        open_tickets = self.ticket_repo.find_by_status('OPEN')

        overdue_tickets = []

        for ticket in open_tickets:
            sla_result = self.check_sla_compliance(ticket)

            if not sla_result.response_compliant or not sla_result.resolution_compliant:
                overdue_tickets.append(ticket)

        # 发送告警
        if overdue_tickets:
            self._send_overdue_alert(overdue_tickets)

        return overdue_tickets
```

## 售后数据分析与优化

### 售后指标统计

```python
class AfterSalesAnalytics:
    """售后数据分析"""

    def calculate_metrics(self, start_date, end_date):
        """
        计算售后指标

        指标：
        1. 售后率 = 售后单数 / 订单数
        2. 退货率 = 退货单数 / 订单数
        3. 平均处理时长
        4. 客户满意度
        5. 一次解决率
        """
        # 1. 售后率
        total_orders = self.order_repo.count_by_date_range(start_date, end_date)
        total_after_sales = self.after_sales_repo.count_by_date_range(
            start_date,
            end_date
        )
        after_sales_rate = total_after_sales / total_orders if total_orders > 0 else 0

        # 2. 退货率
        refund_count = self.after_sales_repo.count_by_type_and_date(
            'REFUND',
            start_date,
            end_date
        )
        refund_rate = refund_count / total_orders if total_orders > 0 else 0

        # 3. 平均处理时长
        avg_processing_time = self.after_sales_repo.calculate_avg_processing_time(
            start_date,
            end_date
        )

        # 4. 客户满意度
        satisfaction_score = self._calculate_satisfaction_score(start_date, end_date)

        # 5. 一次解决率
        first_contact_resolution = self._calculate_fcr(start_date, end_date)

        return AfterSalesMetrics(
            after_sales_rate=after_sales_rate,
            refund_rate=refund_rate,
            avg_processing_time=avg_processing_time,
            satisfaction_score=satisfaction_score,
            fcr=first_contact_resolution
        )

    def analyze_refund_reasons(self, start_date, end_date):
        """分析退货原因分布"""
        refunds = self.after_sales_repo.find_refunds_by_date(start_date, end_date)

        reason_stats = defaultdict(int)

        for refund in refunds:
            reason_stats[refund.reason] += 1

        # 排序
        sorted_reasons = sorted(
            reason_stats.items(),
            key=lambda x: x[1],
            reverse=True
        )

        return sorted_reasons
```

## 总结

售后管理是电商平台的核心竞争力之一。关键要点：

1. **流程标准化**：退货、退款、换货、补发流程清晰
2. **自动化处理**：通过规则引擎实现自动审核、自动分配
3. **数据驱动**：分析售后数据，优化商品和服务
4. **用户体验**：快速响应、透明进度、合理补偿
5. **系统集成**：与财务、库存、物流等系统深度对接

下一篇文章，我们将探讨**OMS系统架构设计与性能优化**，从技术层面解析如何构建高性能的OMS系统。

---

**关键词**：售后管理、退货退款、换货补发、工单系统、SLA监控、售后数据分析
