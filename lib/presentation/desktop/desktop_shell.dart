import 'package:flutter/material.dart';
import '../../business/auth/auth_manager.dart';
import '../../business/shop/shop_manager.dart';
import '../../business/subscription/subscription_engine.dart';
import '../../core/constants/app_constants.dart';
import '../../core/i18n/i18n_service.dart';
import '../../infrastructure/config/app_config_service.dart';
import '../../infrastructure/core_daemon/core_daemon.dart';
import '../dashboard/widgets/customer_service_modal.dart';
import '../dashboard/widgets/notice_dialog.dart';
import 'desktop_affiliate_view.dart';
import 'desktop_connections_view.dart';
import 'desktop_home_view.dart';
import 'desktop_nodes_view.dart';
import 'desktop_profile_view.dart';
import 'desktop_settings_view.dart';
import 'desktop_store_view.dart';
import 'desktop_theme_tokens.dart';
import 'desktop_traffic_view.dart';

/// 桌面專屬頂層外殼 (DesktopShell)
/// 1200x780 專屬架構：
/// - 左側固定導覽列 (210px) 包含 8 大功能選單與底部離線切換/安全退出
/// - 頂部透明帳號列 (58px) 包含當前分頁標題、用戶膠囊與 5 大快捷動作
/// - 內容區域零跳轉直連 8 大純桌面視圖
class DesktopShell extends StatefulWidget {
  final AuthManager authManager;
  final AppConfigService configService;
  final CoreDaemon coreDaemon;
  final SubscriptionEngine subscriptionEngine;
  final ShopManager shopManager;
  final VoidCallback onToggleConnection;
  final VoidCallback onLogout;
  final bool isSyncing;
  final int initialNavIndex;
  final bool enableAnimations;

  const DesktopShell({
    super.key,
    required this.authManager,
    required this.configService,
    required this.coreDaemon,
    required this.subscriptionEngine,
    required this.shopManager,
    required this.onToggleConnection,
    required this.onLogout,
    this.isSyncing = false,
    this.initialNavIndex = 0,
    this.enableAnimations = true,
  });

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  late int _activeNavIndex;
  bool _offlineMode = false;

  @override
  void initState() {
    super.initState();
    _activeNavIndex = widget.initialNavIndex;
    I18nService.instance.addListener(_onStateChanged);
    widget.coreDaemon.addListener(_onStateChanged);
    widget.subscriptionEngine.addListener(_onStateChanged);
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.subscriptionEngine.removeListener(_onStateChanged);
    widget.coreDaemon.removeListener(_onStateChanged);
    I18nService.instance.removeListener(_onStateChanged);
    super.dispose();
  }

  void _switchTab(int index) {
    if (index >= 0 && index < 8) {
      setState(() => _activeNavIndex = index);
    }
  }

  void _showLanguageSelector() {
    final i18n = I18nService.instance;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DesktopThemeTokens.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesktopThemeTokens.cardRadius),
          side: const BorderSide(color: DesktopThemeTokens.borderMuted, width: 1.2),
        ),
        title: Row(
          children: [
            const Icon(Icons.translate_rounded, color: DesktopThemeTokens.accentCyan, size: 20),
            const SizedBox(width: 8),
            Text(
              i18n.t('profile_select_lang'),
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: DesktopThemeTokens.supportedLanguages.map((lang) {
            final isSelected = i18n.currentLanguage.code == lang['code'];
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
                onTap: () async {
                  await i18n.switchLanguage(lang['code']!);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) setState(() {});
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showNetworkDiagnostics() {
    final i18n = I18nService.instance;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DesktopThemeTokens.cardSurface,
        title: Row(
          children: [
            const Icon(Icons.network_check_rounded, color: DesktopThemeTokens.accentCyan),
            const SizedBox(width: 8),
            Text(i18n.t('more_diagnostics'), style: const TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDiagItem(i18n.t('diag_local_nic'), '127.0.0.1', DesktopThemeTokens.successColor),
            _buildDiagItem(
              i18n.t('diag_sys_proxy'),
              widget.coreDaemon.state.isConnected ? '127.0.0.1:7890' : i18n.t('status_disconnected'),
              DesktopThemeTokens.neonBlue,
            ),
            _buildDiagItem(
              i18n.t('diag_core_controller'),
              widget.coreDaemon.state.isConnected ? '127.0.0.1:9090' : i18n.t('status_disconnected'),
              DesktopThemeTokens.successColor,
            ),
            _buildDiagItem(i18n.t('diag_doh_anti'), 'Cloudflare / Google DoH', DesktopThemeTokens.successColor),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(i18n.t('confirm'), style: const TextStyle(color: DesktopThemeTokens.accentCyan)),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagItem(String label, String value, Color statusColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: DesktopThemeTokens.textMuted, fontSize: 12.5)),
          const SizedBox(width: 16),
          Text(
            value,
            style: TextStyle(color: statusColor, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  void _showDailyCheckIn() {
    final i18n = I18nService.instance;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DesktopThemeTokens.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesktopThemeTokens.cardRadius),
          side: const BorderSide(color: DesktopThemeTokens.borderMuted, width: 1.2),
        ),
        title: Row(
          children: [
            const Icon(Icons.calendar_today_rounded, color: Color(0xFFF59E0B)),
            const SizedBox(width: 10),
            Text(
              i18n.t('tooltip_checkin'),
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              i18n.t('checkin_thanks'),
              style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              i18n.t('checkin_credited'),
              style: const TextStyle(color: DesktopThemeTokens.textMuted, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(i18n.t('done'), style: const TextStyle(color: DesktopThemeTokens.accentCyan)),
          ),
        ],
      ),
    );
  }

  Future<void> _showLatestNotice() async {
    final i18n = I18nService.instance;
    try {
      final notices = await widget.authManager.fetchNotices();
      if (!mounted) return;
      if (notices.isNotEmpty) {
        NoticeDialog.show(context, notices.first);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(i18n.t('no_notice'))),
        );
      }
    } catch (_) {}
  }

  String _getPageTitle(int index) {
    final i18n = I18nService.instance;
    switch (index) {
      case 0:
        return i18n.t('nav_home');
      case 1:
        return i18n.t('nav_shop');
      case 2:
        return i18n.t('nav_nodes');
      case 3:
        return i18n.t('nav_connections');
      case 4:
        return i18n.t('profile_traffic_details');
      case 5:
        return i18n.t('profile_invite');
      case 6:
        return i18n.t('nav_profile');
      case 7:
        return i18n.t('more_title');
      default:
        return i18n.t('nav_home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18nService.instance;
    final user = widget.authManager.state.user;
    final isVip = user != null && !user.isExpired;

    return Scaffold(
      backgroundColor: DesktopThemeTokens.bgCanvas,
      body: Row(
        children: [
          // 1. 左側垂直導覽列 (寬度 210px)
          Container(
            width: 210,
            decoration: const BoxDecoration(
              color: DesktopThemeTokens.sidebarSurface,
              border: Border(
                right: BorderSide(color: DesktopThemeTokens.borderMuted, width: 1.0),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 16),
                // 頂部品牌 Logo
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [DesktopThemeTokens.neonBlue, DesktopThemeTokens.accentCyan],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: DesktopThemeTokens.accentCyan.withOpacity(0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.shield_rounded, color: Colors.white, size: 19),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                i18n.t('app_title'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1),
                              decoration: BoxDecoration(
                                color: DesktopThemeTokens.neonBlue.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: DesktopThemeTokens.neonBlue.withOpacity(0.4),
                                  width: 0.6,
                                ),
                              ),
                              child: const Text(
                                AppConstants.versionTag,
                                style: TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.bold,
                                  color: DesktopThemeTokens.accentCyan,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 8 大選單
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    children: [
                      _buildNavItem(0, Icons.cloud_outlined, i18n.t('nav_home')),
                      _buildNavItem(1, Icons.shopping_bag_outlined, i18n.t('nav_shop')),
                      _buildNavItem(2, Icons.tune_rounded, i18n.t('nav_nodes')),
                      _buildNavItem(3, Icons.bolt_rounded, i18n.t('nav_connections')),
                      _buildNavItem(4, Icons.show_chart_rounded, i18n.t('nav_traffic')),
                      _buildNavItem(5, Icons.card_giftcard_rounded, i18n.t('nav_affiliate')),
                      _buildNavItem(6, Icons.person_outline_rounded, i18n.t('nav_profile')),
                      _buildNavItem(7, Icons.settings_outlined, i18n.t('nav_settings')),
                    ],
                  ),
                ),

                // 離線模式開關
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: DesktopThemeTokens.cardSurface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: DesktopThemeTokens.borderMuted, width: 0.8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _offlineMode ? Icons.cloud_off_rounded : Icons.cloud_outlined,
                          size: 15,
                          color: _offlineMode ? const Color(0xFFF59E0B) : DesktopThemeTokens.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            i18n.t('offline_mode'),
                            style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w500),
                          ),
                        ),
                        Transform.scale(
                          scale: 0.7,
                          child: Switch(
                            value: _offlineMode,
                            activeColor: DesktopThemeTokens.neonBlue,
                            onChanged: (val) {
                              setState(() => _offlineMode = val);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 底部退出登入按鈕
                Padding(
                  padding: const EdgeInsets.only(left: 12, right: 12, bottom: 12, top: 4),
                  child: InkWell(
                    onTap: widget.onLogout,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                      decoration: BoxDecoration(
                        color: DesktopThemeTokens.dangerColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: DesktopThemeTokens.dangerColor.withOpacity(0.28), width: 0.8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.logout_rounded, color: DesktopThemeTokens.dangerColor, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            i18n.t('sign_out'),
                            style: const TextStyle(
                              color: DesktopThemeTokens.dangerColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 2. 右側主工作區
          Expanded(
            child: Column(
              children: [
                // 頂部透明帳號列 (58px)
                Container(
                  height: 58,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: const BoxDecoration(
                    color: DesktopThemeTokens.sidebarSurface,
                    border: Border(
                      bottom: BorderSide(color: DesktopThemeTokens.borderMuted, width: 1.0),
                    ),
                  ),
                  child: Row(
                    children: [
                      // 左側頁面標題
                      Flexible(
                        child: Text(
                          _getPageTitle(_activeNavIndex),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          widget.coreDaemon.state.isConnected
                              ? i18n.t('status_connected')
                              : (widget.coreDaemon.state.isConnecting
                                  ? i18n.t('status_connecting')
                                  : i18n.t('status_disconnected')),
                          style: TextStyle(
                            color: widget.coreDaemon.state.isConnected
                                ? DesktopThemeTokens.successColor
                                : DesktopThemeTokens.textMuted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),

                      const Spacer(),

                      // 用戶卡片膠囊
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: DesktopThemeTokens.cardSurface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: DesktopThemeTokens.borderMuted, width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 11,
                              backgroundColor: DesktopThemeTokens.neonBlue.withOpacity(0.2),
                              child: const Icon(Icons.person_rounded, size: 14, color: DesktopThemeTokens.accentCyan),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 160),
                                      child: Text(
                                        user?.email ?? 'nick0425@gmail.com',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF59E0B).withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Text(
                                        isVip ? i18n.t('vip_badge') : i18n.t('free_badge'),
                                        style: const TextStyle(
                                          color: Color(0xFFF59E0B),
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),

                      // 快捷按鈕列 (4 國語言, 診斷, 簽到, 客服, 公告)
                      _buildHeaderIconBtn(
                        icon: Icons.translate_rounded,
                        tooltip: i18n.t('tooltip_lang'),
                        onTap: _showLanguageSelector,
                      ),
                      _buildHeaderIconBtn(
                        icon: Icons.wifi_rounded,
                        tooltip: i18n.t('tooltip_diag'),
                        onTap: _showNetworkDiagnostics,
                      ),
                      _buildHeaderIconBtn(
                        icon: Icons.calendar_today_rounded,
                        tooltip: i18n.t('tooltip_checkin'),
                        onTap: _showDailyCheckIn,
                      ),
                      _buildHeaderIconBtn(
                        icon: Icons.headset_mic_rounded,
                        tooltip: i18n.t('tooltip_service'),
                        onTap: () {
                          final cfg = widget.configService.activeConfig;
                          final u = widget.authManager.state.user;
                          CustomerServiceModal.show(
                            context,
                            crispId: cfg.crispId,
                            user: u,
                            authManager: widget.authManager,
                          );
                        },
                      ),
                      _buildHeaderIconBtn(
                        icon: Icons.campaign_rounded,
                        tooltip: i18n.t('tooltip_notice'),
                        onTap: _showLatestNotice,
                      ),
                    ],
                  ),
                ),

                // 主內容視圖 (純桌面分家視圖)
                Expanded(
                  child: _buildDedicatedView(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String title) {
    final isSelected = _activeNavIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _activeNavIndex = index),
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8.5),
            decoration: BoxDecoration(
              gradient: isSelected
                  ? const LinearGradient(
                      colors: [DesktopThemeTokens.neonBlue, Color(0xFF0284C7)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    )
                  : null,
              borderRadius: BorderRadius.circular(8),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: DesktopThemeTokens.neonBlue.withOpacity(0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isSelected ? Colors.white : DesktopThemeTokens.textMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected ? Colors.white : DesktopThemeTokens.textMuted,
                      fontSize: 12.5,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderIconBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: DesktopThemeTokens.cardSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: DesktopThemeTokens.borderMuted, width: 0.8),
            ),
            child: Icon(icon, color: DesktopThemeTokens.textMuted, size: 15),
          ),
        ),
      ),
    );
  }

  Widget _buildDedicatedView() {
    switch (_activeNavIndex) {
      case 0:
        return DesktopHomeView(
          coreDaemon: widget.coreDaemon,
          subscriptionEngine: widget.subscriptionEngine,
          authManager: widget.authManager,
          onToggleConnection: widget.onToggleConnection,
          onSelectNode: () => _switchTab(2),
          enableAnimations: widget.enableAnimations,
        );
      case 1:
        return DesktopStoreView(
          shopManager: widget.shopManager,
        );
      case 2:
        return DesktopNodesView(
          subscriptionEngine: widget.subscriptionEngine,
          onNavigateToHome: () => _switchTab(0),
          onTriggerConnect: () {
            if (!widget.coreDaemon.state.isConnected && !widget.coreDaemon.state.isConnecting) {
              widget.onToggleConnection();
            }
          },
        );
      case 3:
        return DesktopConnectionsView(
          coreDaemon: widget.coreDaemon,
        );
      case 4:
        return DesktopTrafficView(
          authManager: widget.authManager,
        );
      case 5:
        return DesktopAffiliateView(
          authManager: widget.authManager,
          dioClient: widget.authManager.dioClient,
          configService: widget.configService,
        );
      case 6:
        return DesktopProfileView(
          authManager: widget.authManager,
          shopManager: widget.shopManager,
          configService: widget.configService,
          onSwitchTab: _switchTab,
        );
      case 7:
        return DesktopSettingsView(
          coreDaemon: widget.coreDaemon,
          subscriptionEngine: widget.subscriptionEngine,
          configService: widget.configService,
          authManager: widget.authManager,
        );
      default:
        return DesktopHomeView(
          coreDaemon: widget.coreDaemon,
          subscriptionEngine: widget.subscriptionEngine,
          authManager: widget.authManager,
          onToggleConnection: widget.onToggleConnection,
          enableAnimations: widget.enableAnimations,
        );
    }
  }
}
