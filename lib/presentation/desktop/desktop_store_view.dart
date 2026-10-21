// lib/presentation/desktop/desktop_store_view.dart

import 'package:flutter/material.dart';
import '../../business/shop/plan_model.dart';
import '../../business/shop/shop_manager.dart';
import '../../core/i18n/i18n_service.dart';
import '../shop/order_payment_screen.dart';
import 'desktop_theme_tokens.dart';

/// 桌面專屬套餐商城 (DesktopStoreView)
/// 純粹的 2x2 滿版四宮格卡片，固定卡高 240px，天河藍漸層按鈕，一屏零下拉
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

  @override
  void initState() {
    super.initState();
    if (widget.shopManager.plans.isEmpty) {
      _loadPlans();
    }
  }

  Future<void> _loadPlans() async {
    setState(() => _isLoading = true);
    try {
      await widget.shopManager.fetchPlans();
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
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
                        label: Text('${p.label} ${p.formattedPrice}'),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          color: isSelected ? Colors.black : Colors.white,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        selectedColor: DesktopThemeTokens.neonCyan,
                        backgroundColor: DesktopThemeTokens.cardInnerBg,
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
      try {
        final coupon = couponController.text.trim();
        final tradeNo = await widget.shopManager.createOrder(
          planId: plan.id,
          period: selectedPeriodKey,
          couponCode: coupon.isNotEmpty ? coupon : null,
        );
        if (mounted) {
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${i18n.t('order_failed_prefix')}: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18nService.instance;
    var rawPlans = widget.shopManager.plans;

    // 若無遠端方案則產生符合規範的 4 個展示方案
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DesktopThemeTokens.spacing, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 頂部控制列 (篩選標籤 + 重新整理)
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
                icon: const Icon(Icons.refresh_rounded, color: DesktopThemeTokens.neonCyan, size: 20),
                onPressed: _loadPlans,
                tooltip: i18n.t('refresh'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2x2 滿版四宮格卡片 (高度自適應，零下拉)
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: DesktopThemeTokens.neonCyan))
                : GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      mainAxisExtent: 260,
                    ),
                    itemCount: plans.length.clamp(0, 4),
                    itemBuilder: (context, index) {
                      final plan = plans[index];
                      return _buildPlanCard(plan, index, i18n);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(int index, String label) {
    final isSelected = _selectedFilterIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedFilterIndex = index),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? DesktopThemeTokens.neonCyan.withOpacity(0.15) : DesktopThemeTokens.cardInnerBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? DesktopThemeTokens.neonCyan : DesktopThemeTokens.borderColor,
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

  Widget _buildPlanCard(PlanModel plan, int index, I18nService i18n) {
    final isRecommended = index == 1; // 標記第二個為熱門推薦
    final priceStr = plan.formattedDisplayPrice.isNotEmpty ? plan.formattedDisplayPrice : '¥15.00';
    final trafficGb = plan.transferEnable > 0 ? plan.transferEnable : 150;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: DesktopThemeTokens.cardBg,
        borderRadius: BorderRadius.circular(DesktopThemeTokens.cardRadius),
        border: Border.all(
          color: isRecommended ? DesktopThemeTokens.neonCyan.withOpacity(0.6) : DesktopThemeTokens.borderColor,
          width: isRecommended ? 1.5 : 1.0,
        ),
        boxShadow: [
          if (isRecommended)
            BoxShadow(
              color: DesktopThemeTokens.neonCyan.withOpacity(0.08),
              blurRadius: 16,
              spreadRadius: 2,
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標題與標籤列
          Row(
            children: [
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        plan.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (isRecommended) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: DesktopThemeTokens.neonCyan.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: DesktopThemeTokens.neonCyan, width: 0.8),
                        ),
                        child: Text(
                          i18n.t('hot_badge'),
                          style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: DesktopThemeTokens.neonCyan),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 大金額
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    priceStr,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: DesktopThemeTokens.neonCyan,
                      fontFamily: 'Segoe UI',
                    ),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    i18n.t('per_month'),
                    style: const TextStyle(fontSize: 11, color: DesktopThemeTokens.textMuted),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 核心權益列表 (3 點)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildFeatureBullet(Icons.speed_rounded, '$trafficGb GB ${i18n.t('shop_traffic_unit')}'),
                _buildFeatureBullet(Icons.all_inclusive_rounded, 'BGP 專線 · 4K/8K 流暢無延遲'),
                _buildFeatureBullet(Icons.devices_rounded, '多設備並發 · 7x24 全球客服保障'),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 天河科技藍漸層按鈕 (徹底消滅純白超長按鈕)
          Container(
            width: double.infinity,
            height: 38,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00D2FF), Color(0xFF0072FF)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0072FF).withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: EdgeInsets.zero,
              ),
              onPressed: () => _handleBuyPlan(plan),
              child: Text(
                i18n.t('shop_buy_now'),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureBullet(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: DesktopThemeTokens.neonCyan.withOpacity(0.8)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: DesktopThemeTokens.textMuted),
          ),
        ),
      ],
    );
  }
}
