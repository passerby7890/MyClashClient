// lib/presentation/desktop/desktop_profile_view.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../business/auth/auth_manager.dart';
import '../../business/shop/shop_manager.dart';
import '../../core/constants/app_constants.dart';
import '../../core/i18n/i18n_service.dart';
import '../../infrastructure/config/app_config_service.dart';
import '../auth/login_screen.dart';
import '../dashboard/widgets/customer_service_modal.dart';
import '../profile/change_password_screen.dart';
import '../profile/knowledge_screen.dart';
import '../profile/ticket_screen.dart';
import '../shop/order_history_screen.dart';
import 'desktop_theme_tokens.dart';

/// 桌面專屬個人中心視圖 (DesktopProfileView)
/// 1200x780 黃金解析度規格：上排左右雙卡 (130px) + 下排 3x4 磁貼網格 (12 塊一屏全覽零下拉)
class DesktopProfileView extends StatelessWidget {
  final AuthManager authManager;
  final ShopManager shopManager;
  final AppConfigService configService;
  final Function(int)? onSwitchTab;
  final VoidCallback? onLogout;

  const DesktopProfileView({
    super.key,
    required this.authManager,
    required this.shopManager,
    required this.configService,
    this.onSwitchTab,
    this.onLogout,
  });

  Future<void> _handleLogout(BuildContext context) async {
    final i18n = I18nService.instance;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DesktopThemeTokens.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesktopThemeTokens.cardRadius)),
        title: Text(
          i18n.t('logout_confirm_title'),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Text(
          i18n.t('logout_confirm_desc'),
          style: const TextStyle(color: DesktopThemeTokens.textMuted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(i18n.t('cancel'), style: const TextStyle(color: Colors.white60)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: DesktopThemeTokens.dangerColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              i18n.t('confirm'),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (onLogout != null) {
        onLogout!();
        return;
      }
      await authManager.logout();
      if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => LoginScreen(
              authManager: authManager,
              configService: configService,
            ),
          ),
          (route) => false,
        );
      }
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _showLanguageDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DesktopThemeTokens.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesktopThemeTokens.cardRadius)),
        title: Text(
          I18nService.instance.t('profile_language'),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: DesktopThemeTokens.supportedLanguages.map((lang) {
            final isSelected = I18nService.instance.currentLanguage.code == lang['code'];
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: isSelected ? DesktopThemeTokens.accentCyan.withOpacity(0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? DesktopThemeTokens.accentCyan.withOpacity(0.4) : Colors.transparent,
                ),
              ),
              child: ListTile(
                dense: true,
                title: Text(
                  lang['name']!,
                  style: TextStyle(
                    color: isSelected ? DesktopThemeTokens.accentCyan : Colors.white,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13.5,
                  ),
                ),
                trailing: isSelected
                    ? const Icon(Icons.check_circle_rounded, color: DesktopThemeTokens.accentCyan, size: 18)
                    : null,
                onTap: () {
                  I18nService.instance.switchLanguage(lang['code']!);
                  Navigator.pop(ctx);
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([authManager, I18nService.instance]),
      builder: (context, _) {
        final i18n = I18nService.instance;
        final user = authManager.state.user;
        final email = user?.email ?? i18n.t('guest_mode');
        final usedText = user?.usedTrafficFormatted ?? '0.00 GB';
        final totalText = user?.totalTrafficFormatted ?? '0.00 GB';
        final commissionText = user?.commissionBalanceFormatted ?? '¥0.00';

        String planName = user?.planName ?? '';
        if (planName.isEmpty && user?.planId != null && shopManager.plans.isNotEmpty) {
          final matched = shopManager.plans.where((p) => p.id == user!.planId).firstOrNull;
          if (matched != null) planName = matched.name;
        }
        if (planName.isEmpty) planName = i18n.t('shop_title');

        final expiryText = user?.expiredDateFormatted ?? i18n.t('never_expire');

        return Container(
          color: DesktopThemeTokens.bgCanvas,
          padding: const EdgeInsets.all(DesktopThemeTokens.spacing),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 頂部左右雙卡 (固定高度 124px，緊湊黃金比例)
              SizedBox(
                height: 124,
                child: Row(
                  children: [
                    // 左卡：用戶身份與套餐膠囊
                    Expanded(
                      flex: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: DesktopThemeTokens.cardSurface,
                          borderRadius: BorderRadius.circular(DesktopThemeTokens.cardRadius),
                          border: Border.all(color: DesktopThemeTokens.borderMuted),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: DesktopThemeTokens.accentCyan.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: DesktopThemeTokens.accentCyan.withOpacity(0.3)),
                                  ),
                                  child: const Icon(Icons.person_rounded, color: DesktopThemeTokens.accentCyan, size: 20),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              email,
                                              style: const TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          GestureDetector(
                                            onTap: () {
                                              Clipboard.setData(ClipboardData(text: email));
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text(i18n.t('copied')),
                                                  duration: const Duration(seconds: 1),
                                                ),
                                              );
                                            },
                                            child: Icon(Icons.copy_rounded, size: 13, color: Colors.white.withOpacity(0.55)),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF59E0B).withOpacity(0.18),
                                              borderRadius: BorderRadius.circular(5),
                                              border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4)),
                                            ),
                                            child: Text(
                                              (user != null && !user.isExpired) ? i18n.t('vip_badge') : i18n.t('free_badge'),
                                              style: const TextStyle(
                                                color: Color(0xFFF59E0B),
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '$planName · ${i18n.t("expire_time")}: $expiryText',
                                        style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.55)),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            // 雙按鈕
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF0EA5E9),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () {
                                      if (onSwitchTab != null) onSwitchTab!(1);
                                    },
                                    icon: const Icon(Icons.shopping_bag_outlined, size: 14),
                                    label: Text(
                                      i18n.t('profile_renew_plan'),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      side: const BorderSide(color: DesktopThemeTokens.borderMuted),
                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () {
                                      if (onSwitchTab != null) onSwitchTab!(1);
                                    },
                                    icon: const Icon(Icons.refresh_rounded, size: 14),
                                    label: Text(
                                      i18n.t('profile_reset_traffic'),
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11.5),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: DesktopThemeTokens.spacing),

                    // 右卡：已用流量膠囊卡
                    Expanded(
                      flex: 5,
                      child: GestureDetector(
                        onTap: () {
                          if (onSwitchTab != null) onSwitchTab!(4); // Switch to Traffic tab
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: DesktopThemeTokens.cardSurface,
                            borderRadius: BorderRadius.circular(DesktopThemeTokens.cardRadius),
                            border: Border.all(color: DesktopThemeTokens.borderMuted),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: DesktopThemeTokens.accentCyan.withOpacity(0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Center(
                                      child: Icon(Icons.donut_large_rounded, color: DesktopThemeTokens.accentCyan, size: 16),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    i18n.t('profile_used_traffic'),
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white70),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '$usedText / $totalText',
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.chevron_right_rounded, color: DesktopThemeTokens.accentCyan, size: 16),
                                ],
                              ),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: (user?.usedPercentage ?? 0.0).clamp(0.0, 1.0),
                                  minHeight: 6,
                                  backgroundColor: Colors.white10,
                                  valueColor: const AlwaysStoppedAnimation<Color>(DesktopThemeTokens.accentCyan),
                                ),
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    i18n.t("traffic_remaining_prefix", {"value": user?.remainingTrafficFormatted ?? "0 GB"}),
                                    style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.5)),
                                  ),
                                  Text(
                                    '${((user?.usedPercentage ?? 0.0) * 100).toStringAsFixed(1)}%',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: DesktopThemeTokens.accentCyan),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: DesktopThemeTokens.spacing),

              // 下半部：3x4 磁貼網格 (12 塊，一屏全覽)
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const rowSpacing = 10.0;
                    const colSpacing = 10.0;
                    // 計算適合 4 排的寬高比
                    final availableHeight = constraints.maxHeight;
                    final itemHeight = (availableHeight - (rowSpacing * 3)) / 4;
                    final itemWidth = (constraints.maxWidth - (colSpacing * 2)) / 3;
                    final ratio = (itemWidth / itemHeight).clamp(1.5, 5.0);

                    return GridView.count(
                      crossAxisCount: 3,
                      childAspectRatio: ratio,
                      crossAxisSpacing: colSpacing,
                      mainAxisSpacing: rowSpacing,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _buildTile(
                          icon: Icons.receipt_long_rounded,
                          title: i18n.t('profile_order_history'),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => OrderHistoryScreen(shopManager: shopManager)),
                            );
                          },
                        ),
                        _buildTile(
                          icon: Icons.data_usage_rounded,
                          title: i18n.t('profile_traffic_details'),
                          onTap: () {
                            if (onSwitchTab != null) onSwitchTab!(4);
                          },
                        ),
                        _buildTile(
                          icon: Icons.confirmation_number_outlined,
                          title: i18n.t('profile_ticket'),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => TicketScreen(dioClient: authManager.dioClient)),
                            );
                          },
                        ),
                        _buildTile(
                          icon: Icons.headset_mic_rounded,
                          title: i18n.t('profile_service'),
                          onTap: () {
                            final cfg = configService.activeConfig;
                            final u = authManager.state.user;
                            CustomerServiceModal.show(context, crispId: cfg.crispId, user: u, authManager: authManager);
                          },
                        ),
                        _buildTile(
                          icon: Icons.translate_rounded,
                          title: i18n.t('profile_language'),
                          extraText: i18n.currentLanguageDisplayName,
                          onTap: () => _showLanguageDialog(context),
                        ),
                        _buildTile(
                          icon: Icons.smart_toy_rounded,
                          title: i18n.t('profile_tg_bot'),
                          onTap: () => _openUrl(AppConstants.telegramBotUrl),
                        ),
                        _buildTile(
                          icon: Icons.send_rounded,
                          title: i18n.t('profile_tg_group'),
                          onTap: () {
                            final cfg = configService.activeConfig;
                            if (cfg.customerUrl != null && cfg.customerUrl!.isNotEmpty) {
                              _openUrl(cfg.customerUrl!);
                            } else {
                              _openUrl(AppConstants.telegramGroupUrl);
                            }
                          },
                        ),
                        _buildTile(
                          icon: Icons.language_rounded,
                          title: i18n.t('profile_website'),
                          onTap: () => _openUrl(configService.activeConfig.websiteUrl ?? AppConstants.officialWebsiteUrl),
                        ),
                        _buildTile(
                          icon: Icons.group_add_rounded,
                          title: i18n.t('profile_invite'),
                          extraText: '${i18n.t("profile_commission")}: $commissionText',
                          onTap: () {
                            if (onSwitchTab != null) onSwitchTab!(5);
                          },
                        ),
                        _buildTile(
                          icon: Icons.menu_book_rounded,
                          title: i18n.t('profile_knowledge'),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => KnowledgeScreen(dioClient: authManager.dioClient)),
                            );
                          },
                        ),
                        _buildTile(
                          icon: Icons.lock_reset_rounded,
                          title: i18n.t('profile_password'),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => ChangePasswordScreen(dioClient: authManager.dioClient)),
                            );
                          },
                        ),
                        _buildTile(
                          icon: Icons.logout_rounded,
                          title: i18n.t('profile_logout'),
                          iconColor: DesktopThemeTokens.dangerColor,
                          textColor: DesktopThemeTokens.dangerColor,
                          onTap: () => _handleLogout(context),
                        ),
                      ],
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

  Widget _buildTile({
    required IconData icon,
    required String title,
    String? extraText,
    Color? iconColor,
    Color? textColor,
    required VoidCallback onTap,
  }) {
    final effectiveIconColor = iconColor ?? DesktopThemeTokens.accentCyan;
    final effectiveTextColor = textColor ?? Colors.white;

    return Material(
      color: DesktopThemeTokens.cardSurface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: Colors.white.withOpacity(0.04),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DesktopThemeTokens.borderMuted),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: effectiveIconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: effectiveIconColor, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: effectiveTextColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (extraText != null) ...[
                      const SizedBox(height: 1.5),
                      Text(
                        extraText,
                        style: TextStyle(fontSize: 10.5, color: Colors.white.withOpacity(0.45)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 16, color: Colors.white.withOpacity(0.3)),
            ],
          ),
        ),
      ),
    );
  }
}
