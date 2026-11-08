// lib/presentation/dashboard/widgets/desktop_dashboard_layout.dart

import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/error_sanitizer.dart';
import '../../../business/auth/auth_manager.dart';
import '../../../business/subscription/node_model.dart';
import '../../../business/subscription/subscription_engine.dart';
import '../../../business/shop/shop_manager.dart';
import '../../../infrastructure/config/app_config_service.dart';
import '../../../infrastructure/core_daemon/core_daemon.dart';
import '../../../infrastructure/core_daemon/core_state.dart';
import '../../../infrastructure/core_daemon/traffic_stats.dart';
import '../../../infrastructure/core_daemon/windows_proxy_service.dart';
import '../../more/more_screen.dart';
import '../../profile/invite_screen.dart';
import '../../desktop/desktop_traffic_view.dart';
import '../../profile/user_center_screen.dart';
import '../../shop/shop_screen.dart';
import 'connections_view.dart';
import 'cyber_world_map.dart';
import 'customer_service_modal.dart';
import 'node_selector_modal.dart';
import 'notice_dialog.dart';
import '../../widgets/country_flag_badge.dart';
import '../../../core/i18n/i18n_service.dart';

/// 天河網絡 Windows 桌面端專屬旗艦版佈局 (DesktopDashboardLayout)
/// 嚴格遵循黃金視覺設計規範 (Golden Reference UI)：
/// 1. 左側垂直導覽列 (Left Sidebar 215px): Home, Store, Nodes, Connections, Traffic, Affiliate, Profile, Settings, Offline Mode, Sign Out
/// 2. 頂部資訊列 (Top Header Bar): User Profile Capsule, Live Daemon (● Mihomo, ○ DoH), Quick Action Icons (Lang, Wifi, Calendar, Crisp, Notices)
/// 3. 上半部核心加速區 (Hero Acceleration Zone): 270° Tachometer Dial with Meter Ticks (0..240), Center Power Button (Tap to Connect, 已加速), Mode Pill (Global, Rule, TUN Mode)
/// 4. 下半部雙欄儀表板 (Bottom Dual-Column Cards):
///    - Left: Connection Status (2x2 Grid: Latency, Download sine wave, Upload purple wave, Traffic Stats)
///    - Right: Global Network (CyberWorldMap with HUD, Beacons, Flight Arcs, Dual Destination Badges)
class DesktopDashboardLayout extends StatefulWidget {
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

  const DesktopDashboardLayout({
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
  State<DesktopDashboardLayout> createState() => _DesktopDashboardLayoutState();
}

class _DesktopDashboardLayoutState extends State<DesktopDashboardLayout>
    with SingleTickerProviderStateMixin {
  late int _activeNavIndex; // 0: Home, 1: Store, 2: Nodes, 3: Connections, 4: Traffic, 5: Affiliate, 6: Profile, 7: Settings
  bool _offlineMode = false;
  late AnimationController _pulseController;

  // 桌面旗艦版深色科技毛玻璃調色盤 (嚴格依據黃金參考圖)
  static const Color _bgDeep = Color(0xFF070A11);
  static const Color _sidebarBg = Color(0xFF0D1424);
  static const Color _cardBg = Color(0xFF0F1728);
  static const Color _cardInnerBg = Color(0xFF0A0F1D);
  static const Color _borderColor = Color(0xFF1E293B);
  static const Color _neonBlue = Color(0xFF0EA5E9);
  static const Color _neonCyan = Color(0xFF00D2FF);
  static const Color _emeraldGreen = Color(0xFF10B981);
  static const Color _amberWarn = Color(0xFFF59E0B);
  static const Color _roseRed = Color(0xFFF43F5E);
  static const Color _textMuted = Color(0xFF94A3B8);

  bool get _isTestEnv {
    if (Platform.environment['FLUTTER_TEST'] == 'true') return true;
    final binding = WidgetsBinding.instance.runtimeType.toString();
    return binding.contains('Test');
  }

  @override
  void initState() {
    super.initState();
    _activeNavIndex = widget.initialNavIndex;
    I18nService.instance.addListener(_onLocaleChanged);
    widget.coreDaemon.addListener(_onCoreDaemonChanged);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    if (widget.enableAnimations && !_isTestEnv) {
      _pulseController.repeat(reverse: true);
    }
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  void _onCoreDaemonChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.coreDaemon.removeListener(_onCoreDaemonChanged);
    I18nService.instance.removeListener(_onLocaleChanged);
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDeep,
      body: Row(
        children: [
          // 1. 左側垂直導覽列 (寬度 215px)
          _buildLeftSidebar(),

          // 2. 右側主工作區 (右上資訊列 + 內容區域)
          Expanded(
            child: Column(
              children: [
                _buildTopHeaderBar(),
                Expanded(
                  child: _buildMainContent(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // A. 左側垂直導覽列 (Left Sidebar)
  // ==========================================
  Widget _buildLeftSidebar() {
    return Container(
      width: 215,
      decoration: const BoxDecoration(
        color: _sidebarBg,
        border: Border(
          right: BorderSide(color: _borderColor, width: 1.0),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 18),
          // 頂部品牌區 (Shield + Tianhe Net... + v3.0.6)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_neonBlue, _neonCyan],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: _neonCyan.withOpacity(0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.shield_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          I18nService.instance.t('app_title'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: _neonBlue.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: _neonBlue.withOpacity(0.4), width: 0.6),
                        ),
                        child: const Text(
                          AppConstants.versionTag,
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                            color: _neonCyan,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 中段功能選單 (Home, Store, Nodes, Connections, Traffic, Affiliate, Profile, Settings)
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(
                children: [
                  _buildNavItem(0, Icons.cloud_outlined, I18nService.instance.t('nav_home')),
                  _buildNavItem(1, Icons.shopping_bag_outlined, I18nService.instance.t('nav_shop')),
                  _buildNavItem(2, Icons.tune_rounded, I18nService.instance.t('nav_nodes')),
                  _buildNavItem(3, Icons.bolt_rounded, I18nService.instance.t('nav_connections')),
                  _buildNavItem(4, Icons.show_chart_rounded, I18nService.instance.t('nav_traffic')),
                  _buildNavItem(5, Icons.card_giftcard_rounded, I18nService.instance.t('nav_affiliate')),
                  _buildNavItem(6, Icons.person_outline_rounded, I18nService.instance.t('nav_profile')),
                  _buildNavItem(7, Icons.settings_outlined, I18nService.instance.t('nav_settings')),
                ],
              ),
            ),
          ),

          // 離線模式開關 (Offline Mode)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: _cardInnerBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _borderColor, width: 0.8),
              ),
              child: Row(
                children: [
                  Icon(
                    _offlineMode ? Icons.cloud_off_rounded : Icons.cloud_outlined,
                    size: 16,
                    color: _offlineMode ? _amberWarn : _textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      I18nService.instance.t('offline_mode'),
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                  Transform.scale(
                    scale: 0.75,
                    child: Switch(
                      value: _offlineMode,
                      activeColor: _neonBlue,
                      onChanged: (val) {
                        setState(() => _offlineMode = val);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 底部退出登入按鈕 (Sign Out)
          Padding(
            padding: const EdgeInsets.only(left: 14, right: 14, bottom: 16, top: 2),
            child: InkWell(
              onTap: widget.onLogout,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
                decoration: BoxDecoration(
                  color: _roseRed.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _roseRed.withOpacity(0.28), width: 0.8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.logout_rounded, color: _roseRed, size: 15),
                    const SizedBox(width: 8),
                    Text(
                      I18nService.instance.t('sign_out'),
                      style: const TextStyle(
                        color: _roseRed,
                        fontSize: 12.5,
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
    );
  }

  Widget _buildNavItem(int index, IconData icon, String title) {
    final isSelected = _activeNavIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _activeNavIndex = index),
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9.5),
            decoration: BoxDecoration(
              gradient: isSelected
                  ? const LinearGradient(
                      colors: [_neonBlue, Color(0xFF0284C7)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    )
                  : null,
              color: isSelected ? null : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: _neonBlue.withOpacity(0.35),
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
                  size: 17,
                  color: isSelected ? Colors.white : _textMuted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected ? Colors.white : _textMuted,
                      fontSize: 13,
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

  // ==========================================
  // B. 右上頂部資訊列 (Top Header Bar)
  // ==========================================
  Widget _buildTopHeaderBar() {
    final user = widget.authManager.state.user;
    final isVip = user != null && !user.isExpired;

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: _sidebarBg,
        border: Border(
          bottom: BorderSide(color: _borderColor, width: 1.0),
        ),
      ),
      child: Row(
        children: [
          // 左側：用戶資訊卡片 (User Profile Capsule)
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _cardInnerBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _borderColor, width: 0.8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: _neonBlue.withOpacity(0.2),
                    child: const Icon(Icons.person_rounded, size: 16, color: _neonCyan),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                user?.email ?? I18nService.instance.t('guest_mode'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isVip ? I18nService.instance.t('vip_badge') : I18nService.instance.t('free_badge'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${I18nService.instance.t("service_normal")} · ${I18nService.instance.t("expire_time")}: ${user?.expiredDateFormatted ?? I18nService.instance.t("never_expire")}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _textMuted, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const Spacer(),

          // 快捷圖示按鈕列 (多語言 文A, 網路連線, 日曆簽到, 客服, 公告)
          _buildHeaderIconBtn(
            icon: Icons.translate_rounded,
            tooltip: I18nService.instance.t('tooltip_lang'),
            onTap: _showLanguageSelector,
          ),
          _buildHeaderIconBtn(
            icon: Icons.wifi_rounded,
            tooltip: I18nService.instance.t('tooltip_diag'),
            onTap: _showNetworkDiagnostics,
          ),
          _buildHeaderIconBtn(
            icon: Icons.card_giftcard_rounded,
            tooltip: I18nService.instance.t('nav_affiliate'),
            onTap: () {
              setState(() => _activeNavIndex = 5);
            },
          ),
          _buildHeaderIconBtn(
            icon: Icons.headset_mic_rounded,
            tooltip: I18nService.instance.t('tooltip_service'),
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
            tooltip: I18nService.instance.t('tooltip_notice'),
            onTap: _showLatestNotice,
          ),
        ],
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
            padding: const EdgeInsets.all(7.5),
            decoration: BoxDecoration(
              color: _cardInnerBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _borderColor, width: 0.8),
            ),
            child: Icon(icon, color: _textMuted, size: 16),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // 主工作區頁面切換
  // ==========================================
  Widget _buildMainContent() {
    switch (_activeNavIndex) {
      case 0:
        return _buildAccelerationDashboard();
      case 1:
        return ShopScreen(shopManager: widget.shopManager);
      case 2:
        return _buildDesktopNodeView();
      case 3:
        return ConnectionsView(coreDaemon: widget.coreDaemon);
      case 4:
        return DesktopTrafficView(authManager: widget.authManager);
      case 5:
        return InviteScreen(
          authManager: widget.authManager,
          dioClient: widget.authManager.dioClient,
          configService: widget.configService,
        );
      case 6:
        return UserCenterScreen(
          authManager: widget.authManager,
          shopManager: widget.shopManager,
          configService: widget.configService,
          onSwitchTab: (idx) => setState(() => _activeNavIndex = idx),
        );
      case 7:
        return MoreScreen(
          coreDaemon: widget.coreDaemon,
          subscriptionEngine: widget.subscriptionEngine,
          configService: widget.configService,
          authManager: widget.authManager,
        );
      default:
        return _buildAccelerationDashboard();
    }
  }

  // ==========================================
  // C & D. 加速主頁 (Hero 核心區 + 下半部雙欄儀表板)
  // ==========================================
  Widget _buildAccelerationDashboard() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double bottomCardHeight = 255.0;
        const double bottomPadding = 24.0;
        const double topPadding = 16.0;
        const double spacing = 16.0;

        return Padding(
          padding: const EdgeInsets.fromLTRB(24, topPadding, 24, bottomPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // C. 右側上半部：主視覺核心加速區 (Hero Acceleration Zone)
              // 使用 Expanded 讓它自動佔滿上方所有空間，使地球底圖能大氣地展示
              Expanded(
                child: _buildHeroAccelerationZone(),
              ),
              const SizedBox(height: spacing),

              // D. 右側下半部：雙欄式狀態儀表板 (Bottom Dual-Column Cards)
              // 緊縮至緊湊精緻高度 255px，推至最底部對齊
              SizedBox(
                height: bottomCardHeight,
                child: _buildBottomDualCards(),
              ),
            ],
          ),
        );
      },
    );
  }

  // ==========================================
  // C. 主視覺核心加速區 (Hero Acceleration Zone)
  // ==========================================
  Widget _buildHeroAccelerationZone() {
    final coreState = widget.coreDaemon.state;
    final isConnected = coreState.isConnected;
    final isConnecting = coreState.isConnecting;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 1. 深色點陣真實世界地圖全景底紋 (低透明度 Opacity 0.18)
          Positioned.fill(
            child: Opacity(
              opacity: 0.18,
              child: Image.asset(
                'assets/images/world_map_holo.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),

          // 2. 地球發光地平線弧線 (Glowing Horizon Arc)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 70,
            child: CustomPaint(
              painter: _HorizonGlowPainter(
                color: isConnected ? _emeraldGreen : _neonCyan,
              ),
            ),
          ),

          // 3. 中央核心加速儀表盤呼吸燈開關 (Tachometer Dial Gauge with 240 Ticks)
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 8),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDialPowerButton(isConnected: isConnected, isConnecting: isConnecting),
                  const SizedBox(height: 8),

                  // 4. 正下方模式切換膠囊列 (Mode Switcher Pill: Global, Rule, TUN Mode)
                  _buildModeSwitcherPill(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 中央大型刻度儀表呼吸燈開關 (Tachometer Dial Power Button with Meter Ticks, 165px)
  Widget _buildDialPowerButton({required bool isConnected, required bool isConnecting}) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final pulse = _pulseController.value;
        final glowColor = isConnected ? _emeraldGreen : (isConnecting ? _neonCyan : _neonBlue);

        return GestureDetector(
          onTap: () {
            if (widget.coreDaemon.isTransitioning ||
                widget.coreDaemon.state.isConnecting ||
                widget.coreDaemon.state.isDisconnecting) {
              return;
            }
            widget.onToggleConnection();
          },
          child: CustomPaint(
            painter: _TachometerPainter(
              isConnected: isConnected,
              isConnecting: isConnecting,
              pulse: pulse,
            ),
            child: Container(
              width: 165,
              height: 165,
              alignment: Alignment.center,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: isConnected
                      ? const RadialGradient(
                          colors: [Color(0xFF00E676), Color(0xFF059669), Color(0xFF065F46)],
                          stops: [0.0, 0.65, 1.0],
                        )
                      : isConnecting
                          ? const RadialGradient(
                              colors: [Color(0xFF38BDF8), Color(0xFF0284C7), Color(0xFF0369A1)],
                            )
                          : const RadialGradient(
                              colors: [Color(0xFF1E293B), Color(0xFF0F172A), Color(0xFF090D16)],
                              stops: [0.0, 0.7, 1.0],
                            ),
                  boxShadow: [
                    BoxShadow(
                      color: glowColor.withOpacity(isConnected ? 0.45 + pulse * 0.25 : 0.2),
                      blurRadius: isConnected ? 24 + pulse * 12 : 14,
                      spreadRadius: isConnected ? 4 + pulse * 2 : 1,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isConnecting)
                      const SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          strokeWidth: 3.0,
                          color: Colors.white,
                        ),
                      )
                    else
                      Icon(
                        Icons.power_settings_new_rounded,
                        color: Colors.white,
                        size: 34,
                        shadows: isConnected
                            ? [
                                const Shadow(
                                  color: Colors.white,
                                  blurRadius: 10,
                                ),
                                Shadow(
                                  color: glowColor,
                                  blurRadius: 18,
                                ),
                              ]
                            : null,
                      ),
                    const SizedBox(height: 6),
                    Text(
                      isConnected
                          ? I18nService.instance.t('action_accelerated')
                          : (isConnecting
                              ? I18nService.instance.t('action_connecting')
                              : I18nService.instance.t('tap_to_connect')),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 模式切換膠囊列 (Mode Switcher Pill: Global, Rule, TUN Mode)
  Widget _buildModeSwitcherPill() {
    final currentMode = widget.coreDaemon.proxyMode;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _cardInnerBg.withOpacity(0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _borderColor, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeOption(
            mode: ProxyMode.global,
            icon: Icons.public_rounded,
            label: I18nService.instance.t('mode_global'),
            isSelected: currentMode == ProxyMode.global,
          ),
          _buildModeOption(
            mode: ProxyMode.rule,
            icon: Icons.bolt_rounded,
            label: I18nService.instance.t('mode_rule'),
            isSelected: currentMode == ProxyMode.rule,
          ),
          _buildModeOption(
            mode: ProxyMode.tun,
            icon: Icons.shield_outlined,
            label: I18nService.instance.t('mode_tun'),
            isSelected: currentMode == ProxyMode.tun,
          ),
        ],
      ),
    );
  }

  Widget _buildModeOption({
    required ProxyMode mode,
    required IconData icon,
    required String label,
    required bool isSelected,
  }) {
    return InkWell(
      onTap: () async {
        if (mode == ProxyMode.tun && !kIsWeb && Platform.isWindows) {
          final isWintun = await WindowsProxyService.instance.isWintunAvailable();
          if (!isWintun) {
            _showWintunMissingDialog();
            return;
          }
          final isAdmin = await WindowsProxyService.instance.isRunningAsAdmin();
          if (!isAdmin) {
            _showAdminElevationDialog();
            return;
          }
        }
        await widget.coreDaemon.setProxyMode(mode);
        if (mounted) setState(() {});
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5.5),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [_neonBlue, Color(0xFF0284C7)],
                )
              : null,
          color: isSelected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _neonBlue.withOpacity(0.35),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13.5,
              color: isSelected ? Colors.white : _textMuted,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : _textMuted,
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showWintunMissingDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _borderColor, width: 1.2),
        ),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: _amberWarn, size: 24),
            const SizedBox(width: 8),
            Text(
              I18nService.instance.t('tun_driver_missing_title'),
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          I18nService.instance.t('tun_driver_missing_desc'),
          style: const TextStyle(color: _textMuted, fontSize: 13, height: 1.5),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _neonBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: Text(I18nService.instance.t('i_understand')),
          ),
        ],
      ),
    );
  }

  void _showAdminElevationDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _borderColor, width: 1.2),
        ),
        title: Row(
          children: [
            const Icon(Icons.admin_panel_settings_rounded, color: _neonCyan, size: 24),
            const SizedBox(width: 8),
            Text(I18nService.instance.t('admin_required_title'), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          I18nService.instance.t('admin_required_desc'),
          style: const TextStyle(color: _textMuted, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(I18nService.instance.t('cancel'), style: const TextStyle(color: _textMuted)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _neonBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.security_rounded, size: 16),
            label: Text(I18nService.instance.t('admin_restart_btn')),
            onPressed: () {
              Navigator.pop(ctx);
              WindowsProxyService.instance.restartAsAdmin();
            },
          ),
        ],
      ),
    );
  }

  // ==========================================
  // D. 右側下半部：雙欄式狀態儀表板 (Bottom Dual-Column Cards)
  // ==========================================
  Widget _buildBottomDualCards() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 52,
          child: _buildConnectionStatusCard(),
        ),
        const SizedBox(width: 18),
        Expanded(
          flex: 48,
          child: _buildGlobalNetworkMapCard(),
        ),
      ],
    );
  }

  // ==========================================
  // D1. 左下卡片：【Connection Status】
  // ==========================================
  Widget _buildConnectionStatusCard() {
    final coreState = widget.coreDaemon.state;
    final isConnected = coreState.isConnected;
    final isConnecting = coreState.isConnecting;
    final selectedNode = widget.subscriptionEngine.selectedNode;
    final traffic = widget.coreDaemon.currentTraffic;
    final user = widget.authManager.state.user;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 卡片標題列 (Green Antenna Icon + Connection Status + [↻ Sync Sub] + ● Disconnected)
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: _emeraldGreen.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.wifi_tethering_rounded, color: _emeraldGreen, size: 14),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  I18nService.instance.t('connection_status'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // 同步訂閱按鈕 (Sync Sub)
              InkWell(
                onTap: widget.isSyncing
                    ? null
                    : () async {
                        final token = widget.authManager.state.token;
                        final u = widget.authManager.state.user;
                        if (token != null) {
                          try {
                            await widget.authManager.fetchUserInfo();
                            await widget.subscriptionEngine.syncSubscription(
                              token: token,
                              customSubscribeUrl: u?.subscribeUrl,
                            );
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(I18nService.instance.t('sub_synced_success'))),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('${I18nService.instance.t('refresh_failed_prefix')}${ErrorSanitizer.sanitize(e)}'),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            }
                          }
                        }
                      },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: _cardInnerBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _borderColor, width: 0.8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.sync_rounded,
                        size: 12,
                        color: widget.isSyncing ? _neonCyan : _textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.isSyncing ? I18nService.instance.t('syncing') : I18nService.instance.t('sync_sub'),
                        style: TextStyle(
                          color: widget.isSyncing ? _neonCyan : _textMuted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // 連線狀態膠囊 (未連接 / 連線中... / 已加速)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: isConnected
                      ? _emeraldGreen.withOpacity(0.18)
                      : (isConnecting ? _amberWarn.withOpacity(0.18) : _borderColor.withOpacity(0.5)),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isConnected
                        ? _emeraldGreen.withOpacity(0.5)
                        : (isConnecting ? _amberWarn.withOpacity(0.5) : _borderColor),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isConnected
                            ? _emeraldGreen
                            : (isConnecting ? _amberWarn : _textMuted),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isConnected
                          ? I18nService.instance.t('status_connected_badge')
                          : (isConnecting
                              ? I18nService.instance.t('status_connecting_badge')
                              : I18nService.instance.t('status_disconnected_badge')),
                      style: TextStyle(
                        color: isConnected
                            ? _emeraldGreen
                            : (isConnecting ? _amberWarn : _textMuted),
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // 當前節點列 (Current Node: Flag + Name + [Switch Node], 38px 高度)
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _cardInnerBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _borderColor, width: 0.8),
            ),
            child: Row(
              children: [
                CountryFlagBadge(node: selectedNode, size: const Size(22, 14)),
                const SizedBox(width: 6),
                Text(
                  I18nService.instance.t('current_node'),
                  style: const TextStyle(
                    color: _textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Tooltip(
                    message: selectedNode != null
                        ? '${selectedNode.name} (${selectedNode.protocol.toUpperCase()})'
                        : '',
                    waitDuration: const Duration(milliseconds: 400),
                    child: Text(
                      selectedNode != null
                          ? '${selectedNode.cleanDisplayName} - ${selectedNode.protocol.toUpperCase()}'
                          : (widget.isSyncing ? I18nService.instance.t('loading_nodes') : I18nService.instance.t('node_unselected')),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                OutlinedButton(
                  onPressed: () {
                    NodeSelectorModal.show(
                      context,
                      subscriptionEngine: widget.subscriptionEngine,
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _neonBlue,
                    side: const BorderSide(color: _neonBlue, width: 0.8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  child: Text(I18nService.instance.t('switch_node'), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),

          // 2x2 四宮格數據子卡片 (Latency, Download, Upload, Traffic Stats)
          Expanded(
            child: Row(
              children: [
                Expanded(child: _buildLatencySubCard(selectedNode)),
                const SizedBox(width: 6),
                Expanded(child: _buildDownloadSpeedSubCard(traffic)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _buildUploadSpeedSubCard(traffic)),
                const SizedBox(width: 6),
                Expanded(child: _buildTrafficUsageSubCard(traffic, user)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 2x2 左上【Latency】子卡片 (帶 Fast 標籤、指標與刻度標尺)
  Widget _buildLatencySubCard(NodeModel? node) {
    final i18n = I18nService.instance;
    final rawLatency = node?.latencyMs ?? 0;
    final hasLatency = rawLatency > 0;

    return InkWell(
      onTap: () async {
        await widget.subscriptionEngine.pingAllNodes();
        if (mounted) setState(() {});
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: _cardInnerBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _borderColor, width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: _emeraldGreen.withOpacity(0.18),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.bar_chart_rounded, size: 11, color: _emeraldGreen),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(i18n.t('latency'), style: const TextStyle(color: _textMuted, fontSize: 10)),
                ),
                if (hasLatency)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: _emeraldGreen.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: _emeraldGreen.withOpacity(0.4), width: 0.6),
                    ),
                    child: Text(
                      rawLatency < 100 ? i18n.t('fast') : i18n.t('scale_good'),
                      style: const TextStyle(
                        color: _emeraldGreen,
                        fontSize: 8.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  hasLatency ? '$rawLatency' : '--',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 3),
                const Text('ms', style: TextStyle(color: _textMuted, fontSize: 10)),
              ],
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 3,
                child: Row(
                  children: [
                    Expanded(child: Container(color: _emeraldGreen)),
                    Expanded(child: Container(color: _neonCyan)),
                    Expanded(child: Container(color: _amberWarn)),
                    Expanded(child: Container(color: _roseRed)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 2x2 右上【Download】子卡片 (青藍色動態正弦平滑曲線 0 5 10 Mbps)
  Widget _buildDownloadSpeedSubCard(TrafficStats traffic) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: _cardInnerBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borderColor, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: _neonBlue.withOpacity(0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_downward_rounded, size: 11, color: _neonCyan),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(I18nService.instance.t('download'), style: const TextStyle(color: _textMuted, fontSize: 10)),
              ),
            ],
          ),
          Text(
            traffic.downSpeedFormatted,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, _) {
              return SizedBox(
                height: 12,
                width: double.infinity,
                child: CustomPaint(
                  painter: _SpeedWavePainter(
                    color: _neonCyan,
                    isDownload: true,
                    progress: _pulseController.value,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 2x2 左下【Upload】子卡片 (紫色動態波浪漸變填充圖表 0 5 10 Mbps)
  Widget _buildUploadSpeedSubCard(TrafficStats traffic) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: _cardInnerBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borderColor, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withOpacity(0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_upward_rounded, size: 11, color: Color(0xFFA78BFA)),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(I18nService.instance.t('upload'), style: const TextStyle(color: _textMuted, fontSize: 10)),
              ),
            ],
          ),
          Text(
            traffic.upSpeedFormatted,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, _) {
              return SizedBox(
                height: 12,
                width: double.infinity,
                child: CustomPaint(
                  painter: _SpeedWavePainter(
                    color: const Color(0xFFA78BFA),
                    isDownload: false,
                    progress: _pulseController.value,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 2x2 右下【Traffic Stats】子卡片 (Used Quota, Remaining, Total Quota)
  Widget _buildTrafficUsageSubCard(TrafficStats traffic, dynamic user) {
    final usedRatio = (user?.trafficUsageRatio ?? 0.05).clamp(0.02, 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: _cardInnerBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borderColor, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: _neonCyan.withOpacity(0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.pie_chart_rounded, size: 11, color: _neonCyan),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(I18nService.instance.t('traffic_stats'), style: const TextStyle(color: _textMuted, fontSize: 10)),
              ),
            ],
          ),
          Text(
            traffic.totalTrafficFormatted,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: usedRatio,
              backgroundColor: _borderColor.withOpacity(0.4),
              valueColor: const AlwaysStoppedAnimation<Color>(_neonBlue),
              minHeight: 3,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // D2. 右下卡片：【Global Network】
  // ==========================================
  Widget _buildGlobalNetworkMapCard() {
    final coreState = widget.coreDaemon.state;
    final isConnected = coreState.isConnected;
    final selectedNode = widget.subscriptionEngine.selectedNode;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標題列 (Blue Shield Icon + Global Network)
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: _neonBlue.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.security_rounded, color: _neonCyan, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  I18nService.instance.t('global_network'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (selectedNode != null)
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _cardInnerBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _borderColor, width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CountryFlagBadge(node: selectedNode, size: const Size(18, 12)),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            selectedNode.cleanDisplayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          selectedNode.latencyFormatted,
                          style: TextStyle(
                            color: selectedNode.latencyMs != null && selectedNode.latencyMs! > 0
                                ? _emeraldGreen
                                : _textMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // 嵌入精緻深色點陣世界地圖 (HUD, Flight Arcs, Dual Badges)
          Expanded(
            child: CyberWorldMap(
              activeNode: selectedNode,
              isConnected: isConnected,
              showContainerDecoration: true,
              backgroundColor: _cardInnerBg,
              enableAnimations: widget.enableAnimations,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 節點狀態桌面視圖 (Nodes)
  // ==========================================
  Widget _buildDesktopNodeView() {
    return Container(
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _borderColor, width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: NodeSelectorModal(
        subscriptionEngine: widget.subscriptionEngine,
        isEmbedded: true,
        onNodeSelected: (node) async {
          bool autoConnect = false;
          try {
            final prefs = await SharedPreferences.getInstance();
            autoConnect = prefs.getBool(AppConstants.storageAutoConnectOnNodeSelect) ?? false;
          } catch (_) {}

          await Future.delayed(const Duration(milliseconds: 100));
          if (mounted) {
            setState(() => _activeNavIndex = 0);
            if (autoConnect) {
              if (!widget.coreDaemon.state.isConnected && !widget.coreDaemon.state.isConnecting) {
                widget.onToggleConnection();
              }
            }
          }
        },
      ),
    );
  }

  // ==========================================
  // 彈窗與快捷操作
  // ==========================================
  void _showLanguageSelector() {
    final i18n = I18nService.instance;
    final currentLang = i18n.currentLanguage;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _borderColor, width: 1.2),
        ),
        title: Row(
          children: [
            const Icon(Icons.translate_rounded, color: _neonCyan, size: 20),
            const SizedBox(width: 8),
            Text(i18n.t('profile_select_lang'), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: Colors.transparent,
              child: ListTile(
                leading: const CountryFlagBadge(isoCode: 'TW', size: Size(22, 15)),
                title: const Text('🇹🇼 繁體中文', style: TextStyle(color: Colors.white, fontSize: 13.5)),
                trailing: currentLang == AppLanguage.zhTW ? const Icon(Icons.check_rounded, color: _neonCyan) : null,
                onTap: () async {
                  await i18n.setLanguage(AppLanguage.zhTW);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) setState(() {});
                },
              ),
            ),
            const Divider(color: _borderColor, height: 1),
            Material(
              color: Colors.transparent,
              child: ListTile(
                leading: const CountryFlagBadge(isoCode: 'CN', size: Size(22, 15)),
                title: const Text('🇨🇳 简体中文', style: TextStyle(color: Colors.white, fontSize: 13.5)),
                trailing: currentLang == AppLanguage.zhCN ? const Icon(Icons.check_rounded, color: _neonCyan) : null,
                onTap: () async {
                  await i18n.setLanguage(AppLanguage.zhCN);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) setState(() {});
                },
              ),
            ),
            const Divider(color: _borderColor, height: 1),
            Material(
              color: Colors.transparent,
              child: ListTile(
                leading: const CountryFlagBadge(isoCode: 'US', size: Size(22, 15)),
                title: const Text('🇺🇸 English', style: TextStyle(color: Colors.white, fontSize: 13.5)),
                trailing: currentLang == AppLanguage.en ? const Icon(Icons.check_rounded, color: _neonCyan) : null,
                onTap: () async {
                  await i18n.setLanguage(AppLanguage.en);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) setState(() {});
                },
              ),
            ),
            const Divider(color: _borderColor, height: 1),
            Material(
              color: Colors.transparent,
              child: ListTile(
                leading: const CountryFlagBadge(isoCode: 'JP', size: Size(22, 15)),
                title: const Text('🇯🇵 日本語', style: TextStyle(color: Colors.white, fontSize: 13.5)),
                trailing: currentLang == AppLanguage.ja ? const Icon(Icons.check_rounded, color: _neonCyan) : null,
                onTap: () async {
                  await i18n.setLanguage(AppLanguage.ja);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) setState(() {});
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showNetworkDiagnostics() {
    final i18n = I18nService.instance;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        title: Row(
          children: [
            const Icon(Icons.network_check_rounded, color: _neonCyan),
            const SizedBox(width: 8),
            Text(i18n.t('more_diagnostics'), style: const TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDiagItem(i18n.t('diag_local_nic'), '192.168.x.x', _emeraldGreen),
            _buildDiagItem(i18n.t('diag_sys_proxy'), widget.coreDaemon.state.isConnected ? i18n.t('diag_sys_proxy_active') : i18n.t('status_disconnected'), _neonBlue),
            _buildDiagItem(i18n.t('diag_core_controller'), widget.coreDaemon.state.isConnected ? i18n.t('diag_controller_active') : i18n.t('status_disconnected'), _emeraldGreen),
            _buildDiagItem(i18n.t('diag_doh_anti'), i18n.t('doh_multi_tier_active'), _emeraldGreen),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(i18n.t('confirm'), style: const TextStyle(color: _neonCyan)),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagItem(String title, String val, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(color: _textMuted, fontSize: 12)),
          Row(
            children: [
              Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(val, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  void _showLatestNotice() async {
    try {
      final notices = await widget.authManager.fetchNotices();
      final notice = notices.firstOrNull;
      if (notice != null && mounted) {
        NoticeDialog.show(context, notice);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(I18nService.instance.t('no_announcements'))),
        );
      }
    } catch (_) {}
  }
}

/// 刻度儀表自定義繪製器 (Tachometer Dial Meter Painter with 240 Ticks)
class _TachometerPainter extends CustomPainter {
  final bool isConnected;
  final bool isConnecting;
  final double pulse;

  _TachometerPainter({
    required this.isConnected,
    required this.isConnecting,
    required this.pulse,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 7;

    // 開口圓弧：從 135 度 (0.75 * pi) 到 45 度 (2.25 * pi 即 0.25 * pi)，跨越 270 度
    const startAngle = 0.75 * math.pi;
    const sweepAngle = 1.5 * math.pi;

    final activeColor = isConnected
        ? const Color(0xFF00E676)
        : (isConnecting ? const Color(0xFF00D2FF) : const Color(0xFF1E2D4A));

    // 1. 底層軌道弧線
    final trackPaint = Paint()
      ..color = const Color(0xFF1E2D4A).withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      trackPaint,
    );

    // 2. 啟動時發光的動態進度弧線
    if (isConnected || isConnecting) {
      final glowArcPaint = Paint()
        ..color = activeColor.withOpacity(isConnected ? 0.35 + pulse * 0.25 : 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        glowArcPaint,
      );

      final coreArcPaint = Paint()
        ..color = activeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        coreArcPaint,
      );
    }

    // 3. 沿著開口弧線繪製刻度 (Ticks)
    const tickCount = 42;
    for (int i = 0; i <= tickCount; i++) {
      final t = i / tickCount;
      final angle = startAngle + t * sweepAngle;
      final isMajor = (i % 6 == 0);
      final tickLength = isMajor ? 8.5 : 5.0;

      final outerR = radius - 4;
      final innerR = outerR - tickLength;

      final p1 = Offset(center.dx + innerR * math.cos(angle), center.dy + innerR * math.sin(angle));
      final p2 = Offset(center.dx + outerR * math.cos(angle), center.dy + outerR * math.sin(angle));

      final tickPaint = Paint()
        ..strokeWidth = isMajor ? 1.8 : 1.2
        ..style = PaintingStyle.stroke;

      if (isConnected) {
        final tickPulse = (math.sin(t * math.pi * 3 + pulse * math.pi * 2) + 1) / 2;
        tickPaint.color = activeColor.withOpacity(0.4 + tickPulse * 0.6);
      } else {
        tickPaint.color = isMajor ? const Color(0xFF0EA5E9).withOpacity(0.5) : const Color(0xFF1E2D4A);
      }

      canvas.drawLine(p1, p2, tickPaint);
    }

    // 4. 左右刻度數字: 240 (左) / 240 (右)
    _drawScaleText(canvas, '240', Offset(center.dx - radius * 0.72, center.dy + radius * 0.70));
    _drawScaleText(canvas, '240', Offset(center.dx + radius * 0.54, center.dy + radius * 0.70));
  }

  void _drawScaleText(Canvas canvas, String text, Offset offset) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontSize: 9.5,
          fontFamily: 'monospace',
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _TachometerPainter oldDelegate) {
    return oldDelegate.pulse != pulse ||
        oldDelegate.isConnected != isConnected ||
        oldDelegate.isConnecting != isConnecting;
  }
}

/// 下載與上傳平滑正弦波浪自定義繪製器 (Speed Wave Painter)
class _SpeedWavePainter extends CustomPainter {
  final Color color;
  final bool isDownload;
  final double progress;

  _SpeedWavePainter({
    required this.color,
    required this.isDownload,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path();

    // 依據 progress 與 sine 函數繪製平滑曲線
    path.moveTo(0, h * 0.65);
    for (double x = 0; x <= w; x += 3) {
      final normX = x / w;
      // 兩段正弦波疊加營造真實網絡流動感
      final wave1 = math.sin(normX * 3.5 * math.pi + progress * 2 * math.pi);
      final wave2 = math.cos(normX * 2.0 * math.pi - progress * math.pi);
      final y = (h * 0.50) + (wave1 * 7.0) + (wave2 * 3.5);
      path.lineTo(x, y.clamp(3.0, h - 3.0));
    }

    if (!isDownload) {
      // Upload 卡片底部漸變填充
      final fillPath = Path.from(path);
      fillPath.lineTo(w, h);
      fillPath.lineTo(0, h);
      fillPath.close();

      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withOpacity(0.32),
            color.withOpacity(0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h))
        ..style = PaintingStyle.fill;
      canvas.drawPath(fillPath, fillPaint);
    }

    // 發光光暈
    final glowPaint = Paint()
      ..color = color.withOpacity(0.4)
      ..strokeWidth = 2.8
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    canvas.drawPath(path, glowPaint);

    // 核心線條
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _SpeedWavePainter oldDelegate) => true;
}

/// 地球發光地平線弧線繪製器 (Glowing Horizon Arc)
class _HorizonGlowPainter extends CustomPainter {
  final Color color;
  const _HorizonGlowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path();
    path.moveTo(0, h);
    path.quadraticBezierTo(w * 0.5, h * 0.40, w, h);

    // 外發光光暈
    final glowPaint = Paint()
      ..color = color.withOpacity(0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0);
    canvas.drawPath(path, glowPaint);

    // 核心微細光弧線
    final linePaint = Paint()
      ..color = color.withOpacity(0.40)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _HorizonGlowPainter oldDelegate) => oldDelegate.color != color;
}
