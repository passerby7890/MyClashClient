// lib/presentation/shop/shop_screen.dart

import 'package:flutter/material.dart';
import '../../business/shop/plan_model.dart';
import '../../business/shop/shop_manager.dart';
import '../../core/i18n/i18n_service.dart';
import '../../core/theme/app_theme.dart';
import 'order_payment_screen.dart';

/// 會員中心 / 套餐商城介面 (ShopScreen)
/// 動態串接 V2Board 後台真實套餐資料、更換套餐確認彈窗與訂單支付流程
class ShopScreen extends StatefulWidget {
  final ShopManager shopManager;

  const ShopScreen({
    super.key,
    required this.shopManager,
  });

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  int _selectedFilterIndex = 0; // 0: 全部, 1: 週期性, 2: 一次性

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
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OrderPaymentScreen(
              tradeNo: tradeNo,
              shopManager: widget.shopManager,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // 關閉等待
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${I18nService.instance.t('order_failed_prefix')}: $e')),
        );
      }
    }
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
                icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
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
                                childAspectRatio: 2.15,
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 14,
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
      padding: isDesktop ? const EdgeInsets.all(13) : const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(isDesktop ? 16 : 22),
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
                width: isDesktop ? 36 : 44,
                height: isDesktop ? 36 : 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF0EA5E9).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(isDesktop ? 10 : 14),
                  border: Border.all(color: const Color(0xFF0EA5E9).withOpacity(0.3), width: 1.0),
                ),
                child: Icon(Icons.diamond_rounded, color: const Color(0xFF00D2FF), size: isDesktop ? 20 : 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.name,
                      style: TextStyle(
                        fontSize: isDesktop ? 14 : 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${plan.transferEnable} ${I18nService.instance.t('shop_traffic_unit')}',
                      style: TextStyle(
                        fontSize: isDesktop ? 11 : 12,
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: isDesktop ? 6 : 12),

          // 價格展示
          Text(
            plan.formattedDisplayPrice,
            style: TextStyle(
              fontSize: isDesktop ? 24 : 30,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontFamily: 'Segoe UI',
              letterSpacing: -0.5,
            ),
          ),
          SizedBox(height: isDesktop ? 6 : 10),

          // 權益打勾項目清單
          ...plan.features.take(2).map(
                (f) => Padding(
                  padding: EdgeInsets.only(bottom: isDesktop ? 3 : 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle_rounded, color: AppTheme.successEmerald, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          f,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: isDesktop ? 11 : 12, color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

          const Spacer(),

          // 按鈕組：查看完整權益 + 立即訂閱 (天河科技藍漸層圓角按鈕)
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: AppTheme.darkBorder),
                    padding: EdgeInsets.symmetric(vertical: isDesktop ? 8 : 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => _showPlanDetailsModal(plan),
                  child: Text(
                    I18nService.instance.t('shop_view_details'),
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: isDesktop ? 11 : 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: isDesktop ? 1 : 1,
                child: InkWell(
                  onTap: () => _showChangePlanConfirmDialog(plan),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: isDesktop ? 8 : 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0EA5E9), Color(0xFF0284C7)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0EA5E9).withOpacity(0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      I18nService.instance.t('shop_buy_now'),
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: isDesktop ? 11 : 13,
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
}
