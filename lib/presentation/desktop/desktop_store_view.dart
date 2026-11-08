// lib/presentation/desktop/desktop_store_view.dart

import 'package:flutter/material.dart';
import '../../business/shop/order_model.dart';
import '../../business/shop/plan_model.dart';
import '../../business/shop/shop_manager.dart';
import '../../core/i18n/i18n_service.dart';
import '../../core/utils/error_sanitizer.dart';
import '../shop/order_history_screen.dart';
import '../shop/order_payment_screen.dart';
import 'desktop_theme_tokens.dart';

/// 桌面專屬套餐商城 (DesktopStoreView)
/// 純粹的 2x2 滿版四宮格卡片，固定卡高 240px，天河藍漸層按鈕，一屏零下拉
/// 具備未付款訂單警示橫幅、未付款衝突智慧引導彈窗與一鍵取消舊單閉環
class DesktopStoreView extends StatefulWidget {
  final ShopManager shopManager;

  const DesktopStoreView({
    super.key,
    required this.shopManager,
  });

  @override
  State<DesktopStoreView> createState() => _DesktopStoreViewState();
}

class _DesktopStoreViewState extends State<DesktopStoreView> {
  bool _isLoading = false;
  int _selectedFilterIndex = 0; // 0: 全部, 1: 週期性, 2: 一次性
  OrderModel? _pendingOrder;

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    setState(() => _isLoading = true);
    try {
      await widget.shopManager.fetchPlans();
      await _checkPendingOrder();
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _checkPendingOrder() async {
    try {
      final orders = await widget.shopManager.fetchOrders();
      final pendingList = orders.where((o) => o.isPending || o.status == 1).toList();
      if (mounted) {
        setState(() {
          _pendingOrder = pendingList.isNotEmpty ? pendingList.first : null;
        });
      }
    } catch (_) {}
  }

  Future<void> _handleBuyPlan(PlanModel plan) async {
    final i18n = I18nService.instance;
    final periods = plan.availablePeriods;
    String selectedPeriodKey = periods.isNotEmpty ? periods.first.key : 'month_price';
    final couponController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final currentPeriod = periods.firstWhere(
            (p) => p.key == selectedPeriodKey,
            orElse: () => periods.first,
          );

          return Dialog(
            backgroundColor: DesktopThemeTokens.cardBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DesktopThemeTokens.cardRadius),
              side: const BorderSide(color: DesktopThemeTokens.borderColor),
            ),
            child: Container(
              width: 440,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: DesktopThemeTokens.neonCyan.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.shopping_bag_outlined, color: DesktopThemeTokens.neonCyan, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${i18n.t('shop_confirm_title')} - ${plan.name}',
                          style: DesktopThemeTokens.titleStyle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  Text(i18n.t('shop_select_period'), style: DesktopThemeTokens.labelStyle),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: periods.map((p) {
                      final isSelected = p.key == selectedPeriodKey;
                      return ChoiceChip(
                        selected: isSelected,
                        showCheckmark: false,
                        label: Text('${p.localizedLabel(i18n)} ${p.formattedPrice}'),
                        labelStyle: TextStyle(
                          fontSize: 12.5,
                          color: isSelected ? Colors.black : Colors.white,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        ),
                        selectedColor: DesktopThemeTokens.neonCyan,
                        backgroundColor: DesktopThemeTokens.cardInnerBg,
                        side: BorderSide(
                          color: isSelected ? DesktopThemeTokens.neonCyan : DesktopThemeTokens.borderColor,
                          width: isSelected ? 1.2 : 1.0,
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        onSelected: (val) {
                          if (val) setDialogState(() => selectedPeriodKey = p.key);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  Text(i18n.t('shop_coupon_title'), style: DesktopThemeTokens.labelStyle),
                  const SizedBox(height: 6),
                  TextField(
                    controller: couponController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: i18n.t('shop_coupon_hint'),
                      hintStyle: const TextStyle(color: DesktopThemeTokens.textMuted, fontSize: 12),
                      filled: true,
                      fillColor: DesktopThemeTokens.cardInnerBg,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: DesktopThemeTokens.borderColor),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(i18n.t('cancel'), style: const TextStyle(color: DesktopThemeTokens.textMuted)),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: DesktopThemeTokens.neonCyan,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(
                          '${i18n.t('shop_order_now')} (${currentPeriod.formattedPrice})',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (confirmed == true && mounted) {
      final coupon = couponController.text.trim();
      try {
        final tradeNo = await widget.shopManager.createOrder(
          planId: plan.id,
          period: selectedPeriodKey,
          couponCode: coupon.isNotEmpty ? coupon : null,
        );
        if (mounted) {
          final res = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => OrderPaymentScreen(
                tradeNo: tradeNo,
                shopManager: widget.shopManager,
              ),
            ),
          );
          if (res == true && mounted) {
            _loadPlans();
          }
        }
      } catch (e) {
        if (mounted) {
          final errStr = e.toString();
          if (errStr.contains('未付款') || errStr.contains('开通中') || errStr.contains('未支付')) {
            await _handlePendingOrderConflict(
              plan: plan,
              period: selectedPeriodKey,
              couponCode: coupon.isNotEmpty ? coupon : null,
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${i18n.t('order_failed_prefix')}: ${ErrorSanitizer.sanitize(e)}')),
            );
          }
        }
      }
    }
  }

  /// 處理未付款訂單衝突：主動彈出桌面版引導對話框 (支援前往支付舊單 或 一鍵取消舊單自動換購新套餐)
  Future<void> _handlePendingOrderConflict({
    required PlanModel plan,
    required String period,
    String? couponCode,
  }) async {
    OrderModel? pendingOrder = _pendingOrder;
    if (pendingOrder == null) {
      try {
        final orders = await widget.shopManager.fetchOrders();
        final pendingList = orders.where((o) => o.isPending || o.status == 1).toList();
        if (pendingList.isNotEmpty) {
          pendingOrder = pendingList.first;
          _pendingOrder = pendingOrder;
        }
      } catch (_) {}
    }

    if (!mounted) return;
    final i18n = I18nService.instance;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: DesktopThemeTokens.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesktopThemeTokens.cardRadius),
          side: const BorderSide(color: DesktopThemeTokens.borderColor),
        ),
        child: Container(
          width: 460,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amberAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.warning_amber_rounded, color: Colors.amberAccent, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      i18n.t('order_conflict_title'),
                      style: DesktopThemeTokens.titleStyle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                i18n.t('order_conflict_desc'),
                style: const TextStyle(color: DesktopThemeTokens.textMuted, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: DesktopThemeTokens.cardInnerBg,
                  borderRadius: BorderRadius.circular(10),
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
                          style: const TextStyle(color: DesktopThemeTokens.neonCyan, fontWeight: FontWeight.bold, fontSize: 15),
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
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      if (pendingOrder != null) {
                        await widget.shopManager.cancelOrder(pendingOrder.tradeNo);
                        if (mounted) {
                          try {
                            final newTradeNo = await widget.shopManager.createOrder(
                              planId: plan.id,
                              period: period,
                              couponCode: couponCode,
                            );
                            if (mounted) {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => OrderPaymentScreen(
                                    tradeNo: newTradeNo,
                                    shopManager: widget.shopManager,
                                  ),
                                ),
                              ).then((_) => _loadPlans());
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('${i18n.t('order_failed_prefix')}: ${ErrorSanitizer.sanitize(e)}')),
                              );
                              _loadPlans();
                            }
                          }
                        }
                      }
                    },
                    child: Text(
                      i18n.t('order_conflict_switch_plan'),
                      style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DesktopThemeTokens.neonCyan,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
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
            ],
          ),
        ),
      ),
    );
  }

  /// 待支付訂單警示橫幅 (桌面端金色橫幅)
  Widget _buildPendingOrderBanner() {
    if (_pendingOrder == null) return const SizedBox.shrink();
    final i18n = I18nService.instance;

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFB45309).withOpacity(0.35),
            const Color(0xFFD97706).withOpacity(0.18),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.receipt_long_rounded, color: Color(0xFFFBBF24), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                Text(
                  i18n.t('order_pending_banner_title'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(width: 8),
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
                const SizedBox(width: 8),
                Text(
                  '${_pendingOrder!.planName ?? i18n.t("order_conflict_default_plan")} (${i18n.t("order_status_pending")})',
                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                ),
              ],
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: DesktopThemeTokens.cardBg,
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
            child: Text(i18n.t('order_pending_banner_cancel'), style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1976D2),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: I18nService.instance,
      builder: (context, _) {
        final i18n = I18nService.instance;
        var rawPlans = widget.shopManager.plans;

        final plans = rawPlans.isNotEmpty
            ? rawPlans
            : [
                PlanModel(
                  id: 1,
                  name: '基礎極速套餐',
                  monthPrice: 1500,
                  transferEnable: 150,
                  content: '高速跨境專線\n不限設備數量\n7x24 全球客服',
                  features: const ['高速跨境專線', '不限設備數量', '7x24 全球客服'],
                ),
                PlanModel(
                  id: 2,
                  name: '標準暢遊套餐',
                  monthPrice: 2800,
                  transferEnable: 350,
                  content: '4K/8K 串流極速解鎖\n專屬遊戲低延遲\n獨立專線負載均衡',
                  features: const ['4K/8K 串流極速解鎖', '專屬遊戲低延遲', '獨立專線負載均衡'],
                ),
                PlanModel(
                  id: 3,
                  name: '高級尊享套餐',
                  monthPrice: 4800,
                  transferEnable: 800,
                  content: '頂級 IPLC/IEPL 內網\nChatGPT/AI 極速響應\nVIP 專屬骨幹優先通道',
                  features: const ['頂級 IPLC/IEPL 內網', 'ChatGPT/AI 極速響應', 'VIP 專屬骨幹優先通道'],
                ),
                PlanModel(
                  id: 4,
                  name: '團隊旗艦無限',
                  monthPrice: 9800,
                  transferEnable: 2000,
                  content: '無限速超大頻寬出口\n全球 60+ 節點全開\n尊榮 1 對 1 專家支援',
                  features: const ['無限速超大頻寬出口', '全球 60+ 節點全開', '尊榮 1 對 1 專家支援'],
                ),
              ];

        // 依標籤篩選方案
        List<PlanModel> filteredPlans;
        if (_selectedFilterIndex == 1) {
          filteredPlans = plans.where((p) => p.monthPrice != null || p.yearPrice != null).toList();
        } else if (_selectedFilterIndex == 2) {
          filteredPlans = plans.where((p) => p.onetimePrice != null && (p.monthPrice == null || p.monthPrice == 0)).toList();
        } else {
          filteredPlans = plans;
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: DesktopThemeTokens.spacing, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 頂部控制列 (篩選標籤 + 歷史訂單 + 重新整理)
              Row(
                children: [
                  Text(i18n.t('shop_title'), style: DesktopThemeTokens.titleStyle),
                  const SizedBox(width: 16),
                  _buildFilterChip(0, i18n.t('shop_tab_all')),
                  const SizedBox(width: 8),
                  _buildFilterChip(1, i18n.t('shop_tab_cycle')),
                  const SizedBox(width: 8),
                  _buildFilterChip(2, i18n.t('shop_tab_one_time')),
                  const Spacer(),
                  IconButton(
                    icon: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(Icons.receipt_long_outlined, color: Colors.white70, size: 20),
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
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => OrderHistoryScreen(shopManager: widget.shopManager),
                        ),
                      ).then((_) => _loadPlans());
                    },
                    tooltip: i18n.t('shop_order_history_tooltip'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: DesktopThemeTokens.neonCyan, size: 20),
                    onPressed: _loadPlans,
                    tooltip: i18n.t('refresh'),
                  ),
                ],
              ),

              // 待支付訂單金色警示橫幅
              _buildPendingOrderBanner(),

              const SizedBox(height: 8),

              // 2x2 四宮格內容區
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: DesktopThemeTokens.neonCyan))
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          const double gap = 14;
                          final double cardWidth = (constraints.maxWidth - gap) / 2;
                          final double cardHeight = (constraints.maxHeight - gap) / 2;
                          final double finalCardHeight = cardHeight < 220 ? 220 : cardHeight;

                          return SingleChildScrollView(
                            child: Wrap(
                              spacing: gap,
                              runSpacing: gap,
                              children: filteredPlans.take(4).map((plan) {
                                return SizedBox(
                                  width: cardWidth,
                                  height: finalCardHeight,
                                  child: _buildStorePlanCard(plan),
                                );
                              }).toList(),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(int index, String label) {
    final isSelected = _selectedFilterIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedFilterIndex = index),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? DesktopThemeTokens.neonCyan.withOpacity(0.18) : DesktopThemeTokens.cardInnerBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? DesktopThemeTokens.neonCyan : DesktopThemeTokens.borderColor,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? DesktopThemeTokens.neonCyan : DesktopThemeTokens.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildStorePlanCard(PlanModel plan) {
    final i18n = I18nService.instance;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DesktopThemeTokens.cardBg,
        borderRadius: BorderRadius.circular(DesktopThemeTokens.cardRadius),
        border: Border.all(color: DesktopThemeTokens.borderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: DesktopThemeTokens.neonCyan.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.rocket_launch_rounded, color: DesktopThemeTokens.neonCyan, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  plan.name,
                  style: DesktopThemeTokens.titleStyle.copyWith(fontSize: 15),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${plan.transferEnable} GB',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: DesktopThemeTokens.neonCyan,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                plan.formattedDisplayPrice,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          Expanded(
            child: ListView(
              physics: const NeverScrollableScrollPhysics(),
              children: plan.features.take(2).map((feature) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: DesktopThemeTokens.neonCyan, size: 13),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          feature,
                          style: const TextStyle(
                            fontSize: 11,
                            color: DesktopThemeTokens.textMuted,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),

          SizedBox(
            width: double.infinity,
            height: 34,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: DesktopThemeTokens.neonCyan,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
                padding: EdgeInsets.zero,
              ),
              onPressed: () => _handleBuyPlan(plan),
              child: Text(
                i18n.t('shop_buy_now'),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
