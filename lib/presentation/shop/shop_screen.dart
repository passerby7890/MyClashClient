// lib/presentation/shop/shop_screen.dart

import 'package:flutter/material.dart';
import '../../business/auth/auth_manager.dart';
import '../../business/shop/order_model.dart';
import '../../business/shop/plan_model.dart';
import '../../business/shop/shop_manager.dart';
import '../../business/subscription/subscription_engine.dart';
import '../../core/i18n/i18n_service.dart';
import '../../core/theme/app_theme.dart';
import 'order_history_screen.dart';
import 'order_payment_screen.dart';

/// 會員中心 / 套餐商城介面 (ShopScreen)
/// 動態串接 V2Board 後台真實套餐資料、更換套餐確認彈窗與訂單支付流程
class ShopScreen extends StatefulWidget {
  final ShopManager shopManager;
  final AuthManager? authManager;
  final SubscriptionEngine? subscriptionEngine;

  const ShopScreen({
    super.key,
    required this.shopManager,
    this.authManager,
    this.subscriptionEngine,
  });

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  int _selectedFilterIndex = 0; // 0: 全部, 1: 週期性, 2: 一次性
  OrderModel? _pendingOrder;

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await widget.shopManager.fetchPlans();
      await _checkPendingOrder();
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  /// 檢查是否存在待支付或開通中的訂單
  Future<void> _checkPendingOrder() async {
    try {
      final orders = await widget.shopManager.fetchOrders();
      final pendingList = orders.where((o) => o.isPending || o.status == 1).toList();
      if (mounted) {
        setState(() {
          _pendingOrder = pendingList.isNotEmpty ? pendingList.first : null;
        });
      }
    } catch (_) {
      // 靜默處理
    }
  }

  /// 彈出「更換套餐確認」彈窗 (支援多週期切換與優惠代碼輸入)
  Future<void> _showChangePlanConfirmDialog(PlanModel plan) async {
    final i18n = I18nService.instance;
    final periods = plan.availablePeriods;
    String selectedPeriodKey = periods.first.key;
    final couponController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final currentPeriodOption = periods.firstWhere(
            (p) => p.key == selectedPeriodKey,
            orElse: () => periods.first,
          );

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 28),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 頂部橘黃色警示區塊
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      color: const Color(0xFFFFA000), // 飽滿暖橘色
                      child: Column(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.warning_rounded,
                              color: Color(0xFFFFA000),
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            i18n.t('shop_confirm_title'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 訊息內容
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF8E1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFFFE082)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.info_rounded, color: Color(0xFFFFA000), size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    i18n.t('shop_switch_plan_hint', {
                                      'name': plan.name,
                                      'period': currentPeriodOption.label,
                                      'price': currentPeriodOption.formattedPrice,
                                    }),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF5D4037),
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 週期選擇列
                          Text(
                            i18n.t('shop_select_period'),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: periods.map((p) {
                              final isSelected = p.key == selectedPeriodKey;
                              return ChoiceChip(
                                selected: isSelected,
                                label: Text(
                                  '${p.label} ${p.formattedPrice}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    color: isSelected ? Colors.white : Colors.black87,
                                  ),
                                ),
                                selectedColor: const Color(0xFFFFA000),
                                backgroundColor: const Color(0xFFF5F5F5),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(
                                    color: isSelected ? const Color(0xFFFFA000) : Colors.black12,
                                  ),
                                ),
                                onSelected: (val) {
                                  if (val) {
                                    setDialogState(() {
                                      selectedPeriodKey = p.key;
                                    });
                                  }
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),

                          // 優惠代碼輸入框
                          Text(
                            i18n.t('shop_coupon_title'),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: couponController,
                            style: const TextStyle(color: Colors.black, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: i18n.t('shop_coupon_hint'),
                              hintStyle: const TextStyle(color: Colors.black38, fontSize: 12),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              filled: true,
                              fillColor: const Color(0xFFF5F5F5),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // 確認更換按鈕
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFFFA000),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(
                                '${i18n.t('shop_order_now')} (${currentPeriodOption.formattedPrice})',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),

                          // 取消按鈕
                          Center(
                            child: TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text(i18n.t('shop_cancel'), style: const TextStyle(color: Colors.black54, fontSize: 14)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (confirmed == true && mounted) {
      final coupon = couponController.text.trim();
      _handleCreateOrder(
        plan: plan,
        period: selectedPeriodKey,
        couponCode: coupon.isNotEmpty ? coupon : null,
      );
    }
  }

  /// 呼叫後台建立訂單並跳轉支付頁
  Future<void> _handleCreateOrder({
    required PlanModel plan,
    required String period,
    String? couponCode,
  }) async {
    // 顯示載入等待
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final tradeNo = await widget.shopManager.createOrder(
        planId: plan.id,
        period: period,
        couponCode: couponCode,
      );

      if (mounted) {
        Navigator.pop(context); // 關閉等待
        final result = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => OrderPaymentScreen(
              tradeNo: tradeNo,
              shopManager: widget.shopManager,
              authManager: widget.authManager,
              subscriptionEngine: widget.subscriptionEngine,
            ),
          ),
        );

        if (result == true && mounted) {
          _loadPlans(); // 支付完成，刷新套餐清單與資料
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // 關閉等待
        final errStr = e.toString();
        // 判斷是否為「未付款或開通中的訂單」衝突
        if (errStr.contains('未付款') || errStr.contains('开通中') || errStr.contains('未支付')) {
          await _handlePendingOrderConflict(
            plan: plan,
            period: period,
            couponCode: couponCode,
          );
        } else {
          final i18n = I18nService.instance;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${i18n.t('order_failed_prefix')}: $e')),
          );
        }
      }
    }
  }

  /// 處理未付款訂單衝突：主動彈出閉環導向對話框 (支援前往支付舊單 或 一鍵取消舊單自動換購新套餐)
  Future<void> _handlePendingOrderConflict({
    required PlanModel plan,
    required String period,
    String? couponCode,
  }) async {
    // 1. 獲取未支付訂單詳細
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    OrderModel? pendingOrder = _pendingOrder;
    try {
      final orders = await widget.shopManager.fetchOrders();
      final pendingList = orders.where((o) => o.isPending || o.status == 1).toList();
      if (pendingList.isNotEmpty) {
        pendingOrder = pendingList.first;
        _pendingOrder = pendingOrder;
      }
    } catch (_) {}

    if (mounted) {
      Navigator.pop(context); // 關閉等待
    }

    if (!mounted) return;

    final i18n = I18nService.instance;

    // 2. 彈出智慧解決方案對話框
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.amberAccent, size: 26),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                i18n.t('order_conflict_title'),
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              i18n.t('order_conflict_desc'),
              style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amberAccent.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          pendingOrder?.planName ?? i18n.t('order_conflict_default_plan'),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        pendingOrder?.formattedAmount ?? '',
                        style: const TextStyle(color: AppTheme.cyanAccent, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                  if (pendingOrder?.tradeNo != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${i18n.t('order_conflict_trade_no_prefix')}${pendingOrder!.tradeNo}',
                      style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11, fontFamily: 'Segoe UI'),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              i18n.t('order_conflict_action_hint', {'plan': plan.name}),
              style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 12, height: 1.4),
            ),
          ],
        ),
        actions: [
          // 按鈕 1: 取消舊單並換購此套餐
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              if (pendingOrder != null) {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => const Center(child: CircularProgressIndicator()),
                );
                await widget.shopManager.cancelOrder(pendingOrder.tradeNo);
                if (mounted) {
                  Navigator.pop(context); // 關閉等待
                  // 重新為用戶建立新訂單
                  _handleCreateOrder(
                    plan: plan,
                    period: period,
                    couponCode: couponCode,
                  );
                }
              }
            },
            child: Text(
              i18n.t('order_conflict_switch_plan'),
              style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          // 按鈕 2: 前往支付舊訂單
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1976D2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              if (pendingOrder != null) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => OrderPaymentScreen(
                      tradeNo: pendingOrder!.tradeNo,
                      shopManager: widget.shopManager,
                      authManager: widget.authManager,
                      subscriptionEngine: widget.subscriptionEngine,
                    ),
                  ),
                ).then((res) {
                  if (res == true && mounted) _loadPlans();
                });
              }
            },
            child: Text(
              i18n.t('order_conflict_go_pay'),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: I18nService.instance,
      builder: (context, _) {
        final i18n = I18nService.instance;
        var plans = widget.shopManager.plans;

        // 依篩選過濾
        if (_selectedFilterIndex == 1) {
          plans = plans.where((p) => p.monthPrice != null || p.yearPrice != null).toList();
        } else if (_selectedFilterIndex == 2) {
          plans = plans.where((p) => p.onetimePrice != null && (p.monthPrice == null || p.monthPrice == 0)).toList();
        }

        final isDesktop = MediaQuery.of(context).size.width > 800;

        return Scaffold(
          backgroundColor: AppTheme.darkBackground,
          appBar: AppBar(
            title: Text(i18n.t('shop_title'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: Colors.white)),
            centerTitle: false,
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: [
              IconButton(
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.receipt_long_outlined, color: Colors.white70),
                    if (_pendingOrder != null)
                      Positioned(
                        top: -2,
                        right: -2,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.amberAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
                tooltip: i18n.t('shop_order_history_tooltip'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => OrderHistoryScreen(
                        shopManager: widget.shopManager,
                        authManager: widget.authManager,
                        subscriptionEngine: widget.subscriptionEngine,
                      ),
                    ),
                  ).then((_) => _loadPlans());
                },
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
                tooltip: i18n.t('shop_reload_tooltip'),
                onPressed: _loadPlans,
              ),
            ],
          ),
          body: SafeArea(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline_rounded, size: 48, color: AppTheme.dangerRose),
                            const SizedBox(height: 12),
                            Text(_errorMessage!, style: const TextStyle(color: Colors.white70)),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: _loadPlans,
                              child: Text(i18n.t('shop_reload')),
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        padding: EdgeInsets.symmetric(
                          horizontal: isDesktop ? 24 : 16,
                          vertical: isDesktop ? 16 : 8,
                        ),
                        children: [
                          // 待支付訂單主動警示橫幅
                          _buildPendingOrderBanner(),

                          Text(
                            i18n.t('shop_subtitle'),
                            style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.6)),
                          ),
                          const SizedBox(height: 16),

                          // 分段切換膠囊 [ 全部 ] [ 週期性 ] [ 一次性 ] (桌面端最大寬度 420px 居左)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: AppTheme.darkCard,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppTheme.darkBorder),
                                ),
                                child: Row(
                                  children: [
                                    _buildSegmentItem(i18n.t('shop_tab_all'), 0),
                                    _buildSegmentItem(i18n.t('shop_tab_cycle'), 1),
                                    _buildSegmentItem(i18n.t('shop_tab_one_time'), 2),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // 套餐卡片列表 (桌面端 2x2 雙欄卡片，移動端單欄)
                          if (plans.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 40),
                              child: Center(
                                child: Text(i18n.t('shop_empty'), style: const TextStyle(color: Colors.white54)),
                              ),
                            )
                          else if (isDesktop)
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                childAspectRatio: 1.65,
                                crossAxisSpacing: 16,
                                mainAxisSpacing: 16,
                              ),
                              itemCount: plans.length,
                              itemBuilder: (ctx, i) => _buildPlanCard(plans[i], isDesktop: true),
                            )
                          else
                            ...plans.map((plan) => _buildPlanCard(plan, isDesktop: false)),
                        ],
                      ),
          ),
        );
      },
    );
  }

  Widget _buildSegmentItem(String title, int index) {
    final isSelected = _selectedFilterIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedFilterIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF252D3D) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? Colors.white : Colors.white60,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlanCard(PlanModel plan, {bool isDesktop = false}) {
    return Container(
      margin: isDesktop ? EdgeInsets.zero : const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.darkBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 頂部圖示與名稱
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF0EA5E9).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF0EA5E9).withOpacity(0.3), width: 1.0),
                ),
                child: const Icon(Icons.diamond_rounded, color: Color(0xFF00D2FF), size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${plan.transferEnable} ${I18nService.instance.t('shop_traffic_unit')}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 價格展示
          Text(
            plan.formattedDisplayPrice,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontFamily: 'Segoe UI',
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 10),

          // 權益打勾項目清單
          ...plan.features.take(2).map(
                (f) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle_rounded, color: AppTheme.successEmerald, size: 15),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          f,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

          isDesktop ? const Spacer() : const SizedBox(height: 14),

          // 按鈕組：查看完整權益 + 立即訂閱 (天河科技藍漸層圓角按鈕)
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: AppTheme.darkBorder),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _showPlanDetailsModal(plan),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      I18nService.instance.t('shop_view_details'),
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: isDesktop ? 1 : 1,
                child: InkWell(
                  onTap: () => _showChangePlanConfirmDialog(plan),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0EA5E9), Color(0xFF0284C7)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0EA5E9).withOpacity(0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        I18nService.instance.t('shop_buy_now'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showPlanDetailsModal(PlanModel plan) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  plan.name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                Text(
                  plan.formattedDisplayPrice,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryCyan),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(I18nService.instance.t('shop_features_privilege'), style: const TextStyle(fontSize: 13, color: Colors.white70)),
            const SizedBox(height: 12),
            ...plan.features.map(
              (f) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    const Icon(Icons.check_rounded, color: AppTheme.successEmerald, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(f, style: const TextStyle(fontSize: 13, color: Colors.white))),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryCyan,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.pop(context);
                _showChangePlanConfirmDialog(plan);
              },
              child: Center(
                child: Text(I18nService.instance.t('shop_confirm_select_plan'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 待支付訂單警示橫幅 (主動提示、支援一鍵去支付或取消訂單)
  Widget _buildPendingOrderBanner() {
    if (_pendingOrder == null) return const SizedBox.shrink();
    final i18n = I18nService.instance;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFB45309).withOpacity(0.35),
            const Color(0xFFD97706).withOpacity(0.18),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.receipt_long_rounded, color: Color(0xFFFBBF24), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      i18n.t('order_pending_banner_title'),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _pendingOrder!.formattedAmount,
                        style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${_pendingOrder!.planName ?? i18n.t("order_conflict_default_plan")} (${i18n.t("order_status_pending")})',
                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppTheme.darkCard,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  title: Text(i18n.t('order_pending_banner_cancel_title'), style: const TextStyle(color: Colors.white)),
                  content: Text(i18n.t('order_pending_banner_cancel_desc'), style: TextStyle(color: Colors.white.withOpacity(0.7))),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(i18n.t('order_pending_banner_keep'), style: TextStyle(color: Colors.white.withOpacity(0.6))),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(i18n.t('order_pending_banner_confirm_cancel'), style: const TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                ),
              );
              if (confirm == true && mounted) {
                await widget.shopManager.cancelOrder(_pendingOrder!.tradeNo);
                _loadPlans();
              }
            },
            child: Text(i18n.t('order_pending_banner_cancel'), style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
          ),
          const SizedBox(width: 6),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1976D2),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => OrderPaymentScreen(
                    tradeNo: _pendingOrder!.tradeNo,
                    shopManager: widget.shopManager,
                    authManager: widget.authManager,
                    subscriptionEngine: widget.subscriptionEngine,
                  ),
                ),
              ).then((res) {
                if (res == true && mounted) _loadPlans();
              });
            },
            child: Text(i18n.t('order_pending_banner_pay'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
