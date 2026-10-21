// lib/presentation/profile/user_center_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../business/auth/auth_manager.dart';
import '../../business/auth/user_model.dart';
import '../../business/shop/shop_manager.dart';
import '../../core/constants/app_constants.dart';
import '../../core/i18n/i18n_service.dart';
import '../../core/theme/app_theme.dart';
import '../../infrastructure/config/app_config_service.dart';
import '../auth/login_screen.dart';
import '../dashboard/widgets/customer_service_modal.dart';
import '../shop/order_history_screen.dart';
import 'traffic_detail_screen.dart';
import 'ticket_screen.dart';
import 'invite_screen.dart';
import 'knowledge_screen.dart';
import 'change_password_screen.dart';

/// 用戶中心頁面 (UserCenterScreen)
/// 1:1 對齊實機截圖：頂部帳號與流量膠囊卡、幫助與支持完整選單、邀請管理佣金餘額、賬戶管理安全登出
/// 支援全語言即時動態響應 (i18n 監聽)
class UserCenterScreen extends StatelessWidget {
  final AuthManager authManager;
  final ShopManager shopManager;
  final AppConfigService configService;
  final Function(int)? onSwitchTab;

  const UserCenterScreen({
    super.key,
    required this.authManager,
    required this.shopManager,
    required this.configService,
    this.onSwitchTab,
  });

  Future<void> _handleLogout(BuildContext context) async {
    final i18n = I18nService.instance;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(i18n.t('logout_confirm_title'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(i18n.t('logout_confirm_desc'), style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(i18n.t('cancel'), style: const TextStyle(color: Colors.white60)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.dangerRose,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(i18n.t('confirm'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
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
        
        // 動態獲取套餐名稱 (若 user.planName 為空則從 shopManager 已抓取的套餐列表中對應 plan_id)
        String planName = user?.planName ?? '';
        if (planName.isEmpty && user?.planId != null && shopManager.plans.isNotEmpty) {
          final matched = shopManager.plans.where((p) => p.id == user!.planId).firstOrNull;
          if (matched != null) planName = matched.name;
        }
        if (planName.isEmpty) planName = i18n.t('shop_title');

        final expiryText = user?.expiredDateFormatted ?? i18n.t('never_expire');
        final isDesktop = MediaQuery.of(context).size.width > 800;

        return Scaffold(
          backgroundColor: AppTheme.darkBackground,
          appBar: AppBar(
            title: Text(
              i18n.t('profile_title'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: Colors.white),
            ),
            centerTitle: false,
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
                onPressed: () async {
                  await authManager.fetchUserInfo();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(i18n.t('refresh'))),
                    );
                  }
                },
              ),
            ],
          ),
          body: isDesktop
              ? _buildDesktopLayout(
                  context,
                  i18n,
                  user,
                  email,
                  planName,
                  expiryText,
                  usedText,
                  totalText,
                  commissionText,
                )
              : _buildMobileLayout(
                  context,
                  i18n,
                  user,
                  email,
                  planName,
                  expiryText,
                  usedText,
                  totalText,
                  commissionText,
                ),
        );
      },
    );
  }

  /// 桌面端：上半部固定高度 130px 左右雙卡並排 + 下半部 3 欄並排磁貼網格 (一屏全覽零下拉)
  Widget _buildDesktopLayout(
    BuildContext context,
    I18nService i18n,
    UserModel? user,
    String email,
    String planName,
    String expiryText,
    String usedText,
    String totalText,
    String commissionText,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 上半部 (固定高度 130px 左右雙卡並排)
          SizedBox(
            height: 130,
            child: Row(
              children: [
                // 左卡：帳號信箱 + VIP 狀態 + 科技藍「續費套餐」與「流量重置」按鈕
                Expanded(
                  flex: 5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.darkCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.darkBorder),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xFF0EA5E9).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFF0EA5E9).withOpacity(0.3)),
                              ),
                              child: const Icon(Icons.person_rounded, color: Color(0xFF38BDF8), size: 22),
                            ),
                            const SizedBox(width: 12),
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
                                            fontSize: 14,
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
                                            SnackBar(content: Text(i18n.t('copied')), duration: const Duration(seconds: 1)),
                                          );
                                        },
                                        child: Icon(Icons.copy_rounded, size: 14, color: Colors.white.withOpacity(0.6)),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF59E0B).withOpacity(0.18),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4)),
                                        ),
                                        child: Text(
                                          (user != null && !user.isExpired) ? i18n.t('vip_badge') : i18n.t('free_badge'),
                                          style: const TextStyle(
                                            color: Color(0xFFF59E0B),
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '$planName · ${i18n.t("expire_time")}: $expiryText',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: Colors.white.withOpacity(0.55),
                                    ),
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
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () {
                                  if (onSwitchTab != null) onSwitchTab!(1);
                                },
                                icon: const Icon(Icons.shopping_bag_outlined, size: 15),
                                label: Text(i18n.t('profile_renew_plan'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: AppTheme.darkBorder),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () {
                                  if (onSwitchTab != null) onSwitchTab!(1);
                                },
                                icon: const Icon(Icons.refresh_rounded, size: 15),
                                label: Text(i18n.t('profile_reset_traffic'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // 右卡：已用流量進度卡
                Expanded(
                  flex: 5,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TrafficDetailScreen(authManager: authManager),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.darkCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.darkBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryCyan.withOpacity(0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(
                                  child: Icon(Icons.donut_large_rounded, color: AppTheme.primaryCyan, size: 18),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                i18n.t('profile_used_traffic'),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70),
                              ),
                              const Spacer(),
                              Text(
                                '$usedText / $totalText',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.chevron_right_rounded, color: AppTheme.primaryCyan, size: 16),
                            ],
                          ),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: (user?.usedPercentage ?? 0.0).clamp(0.0, 1.0),
                              minHeight: 8,
                              backgroundColor: Colors.white10,
                              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryCyan),
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                i18n.t("traffic_remaining_prefix", {"value": user?.remainingTrafficFormatted ?? "0 GB"}),
                                style: TextStyle(fontSize: 11.5, color: Colors.white.withOpacity(0.5)),
                              ),
                              Text(
                                '${((user?.usedPercentage ?? 0.0) * 100).toStringAsFixed(1)}%',
                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.primaryCyan),
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
          const SizedBox(height: 16),

          // 下半部「幫助與支持」：GridView 3 欄並排磁貼小卡片 (一屏全覽)
          Expanded(
            child: GridView.count(
              crossAxisCount: 3,
              childAspectRatio: 3.2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              children: [
                _buildBentoTile(
                  icon: Icons.receipt_long_rounded,
                  title: i18n.t('profile_order_history'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => OrderHistoryScreen(shopManager: shopManager)),
                    );
                  },
                ),
                _buildBentoTile(
                  icon: Icons.data_usage_rounded,
                  title: i18n.t('profile_traffic_details'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => TrafficDetailScreen(authManager: authManager)),
                    );
                  },
                ),
                _buildBentoTile(
                  icon: Icons.confirmation_number_outlined,
                  title: i18n.t('profile_ticket'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => TicketScreen(dioClient: authManager.dioClient)),
                    );
                  },
                ),
                _buildBentoTile(
                  icon: Icons.headset_mic_rounded,
                  title: i18n.t('profile_service'),
                  onTap: () {
                    final cfg = configService.activeConfig;
                    final u = authManager.state.user;
                    CustomerServiceModal.show(context, crispId: cfg.crispId, user: u, authManager: authManager);
                  },
                ),
                _buildBentoTile(
                  icon: Icons.translate_rounded,
                  title: i18n.t('profile_language'),
                  extraText: i18n.currentLanguageDisplayName,
                  onTap: () => _showLanguageDialog(context),
                ),
                _buildBentoTile(
                  icon: Icons.smart_toy_rounded,
                  title: i18n.t('profile_tg_bot'),
                  onTap: () => _openUrl(AppConstants.telegramBotUrl),
                ),
                _buildBentoTile(
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
                _buildBentoTile(
                  icon: Icons.language_rounded,
                  title: i18n.t('profile_website'),
                  onTap: () => _openUrl(configService.activeConfig.websiteUrl ?? AppConstants.officialWebsiteUrl),
                ),
                _buildBentoTile(
                  icon: Icons.group_add_rounded,
                  title: i18n.t('profile_invite'),
                  extraText: '${i18n.t("profile_commission")}: $commissionText',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => InviteScreen(
                          authManager: authManager,
                          dioClient: authManager.dioClient,
                          configService: configService,
                        ),
                      ),
                    );
                  },
                ),
                _buildBentoTile(
                  icon: Icons.menu_book_rounded,
                  title: i18n.t('profile_knowledge'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => KnowledgeScreen(dioClient: authManager.dioClient)),
                    );
                  },
                ),
                _buildBentoTile(
                  icon: Icons.lock_reset_rounded,
                  title: i18n.t('profile_password'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ChangePasswordScreen(dioClient: authManager.dioClient)),
                    );
                  },
                ),
                _buildBentoTile(
                  icon: Icons.logout_rounded,
                  title: i18n.t('profile_logout'),
                  iconColor: AppTheme.dangerRose,
                  textColor: AppTheme.dangerRose,
                  onTap: () => _handleLogout(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 磁貼小卡片組件
  Widget _buildBentoTile({
    required IconData icon,
    required String title,
    String? extraText,
    Color? iconColor,
    Color? textColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.darkCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.darkBorder),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: (iconColor ?? AppTheme.primaryCyan).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: iconColor ?? AppTheme.primaryCyan),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: textColor ?? Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (extraText != null && extraText.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        extraText,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.45),
                        ),
                        maxLines: 1,
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

  /// 手機端佈局
  Widget _buildMobileLayout(
    BuildContext context,
    I18nService i18n,
    UserModel? user,
    String email,
    String planName,
    String expiryText,
    String usedText,
    String totalText,
    String commissionText,
  ) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // 1. 頂部流量狀態膠囊卡片
        GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => TrafficDetailScreen(authManager: authManager)),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.darkBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryCyan.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(Icons.donut_large_rounded, color: AppTheme.primaryCyan, size: 18),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  i18n.t('profile_used_traffic'),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70),
                ),
                const Spacer(),
                Text(
                  '$usedText / $totalText',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded, color: AppTheme.primaryCyan, size: 18),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // 2. 用戶詳細卡片
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.darkCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.darkBorder),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.person_rounded, color: Colors.black, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                email,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: email));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(i18n.t('copied')), duration: const Duration(seconds: 1)),
                                );
                              },
                              child: Icon(Icons.copy_rounded, size: 14, color: Colors.white.withOpacity(0.6)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppTheme.successEmerald, shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Text(planName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.successEmerald)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(i18n.t('expire_time'), style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.5))),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: AppTheme.darkSurface, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.darkBorder)),
                        child: Text(expiryText, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0EA5E9),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        if (onSwitchTab != null) onSwitchTab!(1);
                      },
                      icon: const Icon(Icons.shopping_bag_outlined, size: 16),
                      label: Text(i18n.t('profile_renew_plan'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: AppTheme.darkBorder),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        if (onSwitchTab != null) onSwitchTab!(1);
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: Text(i18n.t('profile_reset_traffic'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 3. 幫助與支持完整清單
        Container(
          decoration: BoxDecoration(
            color: AppTheme.darkCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.darkBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Row(
                  children: [
                    const Icon(Icons.support_agent_rounded, size: 18, color: AppTheme.primaryCyan),
                    const SizedBox(width: 8),
                    Text(i18n.t('profile_help_support'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
              ),
              _buildTile(icon: Icons.receipt_long_rounded, title: i18n.t('profile_order_history'), onTap: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrderHistoryScreen(shopManager: shopManager)));
              }),
              _buildDivider(),
              _buildTile(icon: Icons.data_usage_rounded, title: i18n.t('profile_traffic_details'), onTap: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => TrafficDetailScreen(authManager: authManager)));
              }),
              _buildDivider(),
              _buildTile(icon: Icons.confirmation_number_outlined, title: i18n.t('profile_ticket'), onTap: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => TicketScreen(dioClient: authManager.dioClient)));
              }),
              _buildDivider(),
              _buildTile(icon: Icons.headset_mic_rounded, title: i18n.t('profile_service'), onTap: () {
                final cfg = configService.activeConfig;
                CustomerServiceModal.show(context, crispId: cfg.crispId, user: authManager.state.user, authManager: authManager);
              }),
              _buildDivider(),
              _buildTile(icon: Icons.translate_rounded, title: i18n.t('profile_language'), extraText: i18n.currentLanguageDisplayName, onTap: () => _showLanguageDialog(context)),
              _buildDivider(),
              _buildTile(icon: Icons.smart_toy_rounded, title: i18n.t('profile_tg_bot'), onTap: () => _openUrl(AppConstants.telegramBotUrl)),
              _buildDivider(),
              _buildTile(icon: Icons.send_rounded, title: i18n.t('profile_tg_group'), onTap: () {
                final cfg = configService.activeConfig;
                if (cfg.customerUrl != null && cfg.customerUrl!.isNotEmpty) {
                  _openUrl(cfg.customerUrl!);
                } else {
                  _openUrl(AppConstants.telegramGroupUrl);
                }
              }),
              _buildDivider(),
              _buildTile(icon: Icons.language_rounded, title: i18n.t('profile_website'), onTap: () => _openUrl(configService.activeConfig.websiteUrl ?? AppConstants.officialWebsiteUrl)),
              _buildDivider(),
              _buildTile(icon: Icons.group_add_rounded, title: i18n.t('profile_invite'), extraText: '${i18n.t("profile_commission")}:$commissionText', onTap: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => InviteScreen(authManager: authManager, dioClient: authManager.dioClient, configService: configService)));
              }),
              _buildDivider(),
              _buildTile(icon: Icons.menu_book_rounded, title: i18n.t('profile_knowledge'), onTap: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => KnowledgeScreen(dioClient: authManager.dioClient)));
              }),
              _buildDivider(),
              _buildTile(icon: Icons.lock_reset_rounded, title: i18n.t('profile_password'), onTap: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChangePasswordScreen(dioClient: authManager.dioClient)));
              }),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 4. 賬戶管理分組
        Container(
          decoration: BoxDecoration(color: AppTheme.darkCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppTheme.darkBorder)),
          child: Material(
            color: Colors.transparent,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              leading: const Icon(Icons.logout_rounded, size: 20, color: AppTheme.dangerRose),
              title: Text(i18n.t('profile_logout'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.dangerRose)),
              trailing: const Icon(Icons.chevron_right_rounded, size: 18, color: Colors.white24),
              onTap: () => _handleLogout(context),
            ),
          ),
        ),
        const SizedBox(height: 28),
      ],
    );
  }

  Widget _buildDivider() {
    return Divider(color: Colors.white.withOpacity(0.04), height: 1, indent: 16, endIndent: 16);
  }

  Widget _buildTile({
    required IconData icon,
    required String title,
    String? extraText,
    required VoidCallback onTap,
  }) {
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        leading: Icon(icon, size: 19, color: Colors.white70),
        title: Text(title, style: const TextStyle(fontSize: 13, color: Colors.white)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (extraText != null) ...[
              Text(extraText, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.45))),
              const SizedBox(width: 4),
            ],
            Icon(Icons.chevron_right_rounded, size: 18, color: Colors.white.withOpacity(0.3)),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  /// 語言選擇彈窗：只保留乾淨的 4 國語言，徹底拔除「跟隨系統」
  void _showLanguageDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return ListenableBuilder(
          listenable: I18nService.instance,
          builder: (context, _) {
            final i18n = I18nService.instance;
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 16),
                  Text(
                    i18n.t('profile_select_lang'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final lang in AppLanguage.values) ...[
                    ListTile(
                      leading: Text(lang.flagEmoji, style: const TextStyle(fontSize: 20)),
                      title: Text(
                        lang.label,
                        style: TextStyle(
                          color: i18n.currentLanguage == lang
                              ? AppTheme.primaryCyan
                              : Colors.white,
                          fontWeight: i18n.currentLanguage == lang
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      trailing: i18n.currentLanguage == lang
                          ? const Icon(Icons.check_circle_rounded, color: AppTheme.primaryCyan)
                          : null,
                      onTap: () async {
                        await i18n.setLanguage(lang);
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      },
                    ),
                  ],
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
