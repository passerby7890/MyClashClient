// lib/presentation/desktop/desktop_home_view.dart

import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../business/auth/auth_manager.dart';
import '../../business/subscription/subscription_engine.dart';
import '../../infrastructure/config/app_config_service.dart';
import '../../infrastructure/core_daemon/core_daemon.dart';
import '../../infrastructure/core_daemon/core_state.dart';
import '../../infrastructure/core_daemon/traffic_stats.dart';
import '../../infrastructure/core_daemon/windows_proxy_service.dart';
import '../../core/i18n/i18n_service.dart';
import '../dashboard/widgets/cyber_world_map.dart';
import '../widgets/country_flag_badge.dart';
import 'desktop_theme_tokens.dart';

/// 專職加速主頁 (DesktopHomeView)
/// 上半部無邊框大圓球加速儀表 (270° Tachometer Dial) + 正下方三合一模式膠囊 + 下半部左四宮格、右單一軌跡世界地圖
class DesktopHomeView extends StatefulWidget {
  final AuthManager authManager;
  final CoreDaemon coreDaemon;
  final SubscriptionEngine subscriptionEngine;
  final AppConfigService? configService;
  final VoidCallback onToggleConnection;
  final VoidCallback? onSelectNode;
  final bool isSyncing;
  final bool enableAnimations;

  const DesktopHomeView({
    super.key,
    required this.authManager,
    required this.coreDaemon,
    required this.subscriptionEngine,
    this.configService,
    required this.onToggleConnection,
    this.onSelectNode,
    this.isSyncing = false,
    this.enableAnimations = true,
  });

  @override
  State<DesktopHomeView> createState() => _DesktopHomeViewState();
}

class _DesktopHomeViewState extends State<DesktopHomeView>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _syncRotationController;
  bool _isManualSyncing = false;
  bool _lastConnected = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _syncRotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.enableAnimations) {
      _pulseController.repeat(reverse: true);
    }
    _lastConnected = widget.coreDaemon.state.isConnected;
    widget.coreDaemon.addListener(_onCoreStateChanged);
    widget.subscriptionEngine.addListener(_onEngineChanged);
  }

  void _onEngineChanged() {
    if (mounted) setState(() {});
  }

  void _onCoreStateChanged() {
    final isConnected = widget.coreDaemon.state.isConnected;
    if (isConnected && !_lastConnected) {
      // 連線成功時自動觸發真實延遲探測 (消除一直顯示 -- 待測)
      final selected = widget.subscriptionEngine.selectedNode;
      if (selected != null) {
        widget.subscriptionEngine.pingNode(selected);
      }
    }
    _lastConnected = isConnected;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.subscriptionEngine.removeListener(_onEngineChanged);
    widget.coreDaemon.removeListener(_onCoreStateChanged);
    _syncRotationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _handleManualSync() async {
    if (_isManualSyncing) return;
    setState(() => _isManualSyncing = true);
    _syncRotationController.repeat();
    try {
      final nodes = await widget.subscriptionEngine.performManualSync();
      if (mounted) {
        final count = nodes.length;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              I18nService.instance.t('sync_success', {'count': count.toString()}),
            ),
            backgroundColor: DesktopThemeTokens.accentSuccess,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(I18nService.instance.t('sync_failed')),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        _syncRotationController.stop();
        _syncRotationController.reset();
        setState(() => _isManualSyncing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final coreState = widget.coreDaemon.state;
    final traffic = widget.coreDaemon.currentTraffic;
    final selectedNode = widget.subscriptionEngine.selectedNode;
    final user = widget.authManager.state.user;
    final i18n = I18nService.instance;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isCompact = constraints.maxHeight < 650;
        final double bottomCardHeight = isCompact ? 216.0 : 255.0;
        final double bottomPadding = isCompact ? 14.0 : 24.0;
        final double topPadding = isCompact ? 8.0 : 12.0;
        final double spacing = isCompact ? 10.0 : 16.0;

        return Padding(
          padding: EdgeInsets.fromLTRB(
            DesktopThemeTokens.spacing,
            topPadding,
            DesktopThemeTokens.spacing,
            bottomPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ══════════════════════════════════════════════
              // 上半部：主視覺核心加速區 (Hero Acceleration Zone)
              // 使用 Expanded 釋放上方空間，自動佔滿所有高度，讓地球底圖大氣展開
              // ══════════════════════════════════════════════
              Expanded(
                child: _buildHeroZone(coreState, traffic, selectedNode, i18n, isCompact: isCompact),
              ),
              SizedBox(height: spacing),

              // ══════════════════════════════════════════════
              // 下半部：緊湊精緻雙欄狀態卡 (緊縮至 255px，底部對齊保留 24px)
              // ══════════════════════════════════════════════
              SizedBox(
                height: bottomCardHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 左欄：2x2 連線狀態四宮格
                    Expanded(
                      flex: 5,
                      child: _buildConnectionStatusCard(coreState, traffic, user, selectedNode, i18n),
                    ),
                    const SizedBox(width: DesktopThemeTokens.spacing),

                    // 右欄：全球加速網絡 CyberWorldMap
                    Expanded(
                      flex: 5,
                      child: _buildWorldMapCard(selectedNode, coreState, traffic, i18n),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ══════════════════════════════════════════════
  // 上半部核心加速區 (全景世界地圖 + 垂直居中大圓球與三合一模式膠囊)
  // ══════════════════════════════════════════════
  Widget _buildHeroZone(
    CoreState coreState,
    TrafficStats traffic,
    dynamic selectedNode,
    I18nService i18n, {
    bool isCompact = false,
  }) {
    final isConnected = coreState.isConnected;
    final isConnecting = coreState.isConnecting;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: DesktopThemeTokens.cardBg.withOpacity(0.35),
        borderRadius: BorderRadius.circular(DesktopThemeTokens.cardRadius),
      ),
      child: Stack(
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

          // 2. 內容排版：頂部右上角放大節點膠囊 + 垂直居中加速球與模式切換膠囊
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: isCompact ? 8 : 12),
            child: Column(
              children: [
                // 頂部狀態欄：右側放大版選中節點膠囊
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _SelectedNodePill(
                      selectedNode: selectedNode,
                      i18n: i18n,
                      onTap: widget.onSelectNode,
                      isSyncing: widget.isSyncing,
                    ),
                  ],
                ),
                // 釋放空間垂直居中展示大圓球與模式膠囊
                Expanded(
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 中央刻度儀表與加速大圓球
                          _buildTachometerDial(isConnected, isConnecting, i18n, isCompact: isCompact),
                          SizedBox(height: isCompact ? 8 : 12),

                          // 圓球正下方居中放置 [ 🌐 全局模式 | ⚡ 規則模式 | 🛡️ TUN模式 ] 三合一整體切換膠囊
                          _buildModeSwitchCapsule(i18n),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSelectRoutingMode(String targetMode) async {
    final i18n = I18nService.instance;
    if (targetMode == 'tun' && !kIsWeb && Platform.isWindows) {
      final hasWintun = await WindowsProxyService.instance.isWintunAvailable();
      if (!hasWintun) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: DesktopThemeTokens.cardSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: DesktopThemeTokens.borderMuted),
            ),
            title: Text(i18n.t('tun_driver_missing_title'), style: const TextStyle(color: Colors.white, fontSize: 16)),
            content: Text(i18n.t('tun_driver_missing_desc'), style: const TextStyle(color: Colors.white70, fontSize: 13.5)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(i18n.t('confirm'), style: const TextStyle(color: DesktopThemeTokens.neonCyan)),
              ),
            ],
          ),
        );
        return;
      }

      final isAdmin = await WindowsProxyService.instance.isRunningAsAdmin();
      if (!isAdmin) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: DesktopThemeTokens.cardSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: DesktopThemeTokens.borderMuted),
            ),
            title: Row(
              children: [
                const Icon(Icons.admin_panel_settings_rounded, color: DesktopThemeTokens.amberWarn, size: 22),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    i18n.t('tun_admin_required_title'),
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Text(
              i18n.t('tun_admin_required_desc'),
              style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(i18n.t('cancel'), style: const TextStyle(color: Colors.white54)),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  WindowsProxyService.instance.restartAsAdmin();
                },
                icon: const Icon(Icons.security_rounded, size: 16),
                label: Text(i18n.t('tun_admin_restart_btn')),
                style: FilledButton.styleFrom(
                  backgroundColor: DesktopThemeTokens.neonCyan,
                  foregroundColor: Colors.black,
                ),
              ),
            ],
          ),
        );
        return;
      }
    }

    await widget.subscriptionEngine.setRoutingMode(targetMode);
    if (mounted) setState(() {});
  }

  Widget _buildModeSwitchCapsule(I18nService i18n) {
    final currentMode = widget.subscriptionEngine.routingMode;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: DesktopThemeTokens.cardInnerBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: DesktopThemeTokens.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeOption(
            icon: Icons.public_rounded,
            label: i18n.t('mode_global'),
            isSelected: currentMode == 'global',
            onTap: () => _handleSelectRoutingMode('global'),
          ),
          const SizedBox(width: 4),
          _buildModeOption(
            icon: Icons.bolt_rounded,
            label: i18n.t('mode_rule'),
            isSelected: currentMode == 'rule',
            onTap: () => _handleSelectRoutingMode('rule'),
          ),
          const SizedBox(width: 4),
          _buildModeOption(
            icon: Icons.security_rounded,
            label: i18n.t('mode_tun'),
            isSelected: currentMode == 'tun',
            onTap: () => _handleSelectRoutingMode('tun'),
          ),
        ],
      ),
    );
  }

  Widget _buildModeOption({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5.5),
        decoration: BoxDecoration(
          color: isSelected ? DesktopThemeTokens.neonBlue.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: isSelected
              ? Border.all(color: DesktopThemeTokens.neonBlue.withOpacity(0.6), width: 1.0)
              : Border.all(color: Colors.transparent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13.5,
              color: isSelected ? DesktopThemeTokens.neonCyan : DesktopThemeTokens.textMuted,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : DesktopThemeTokens.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTachometerDial(
    bool isConnected,
    bool isConnecting,
    I18nService i18n, {
    bool isCompact = false,
  }) {
    final dialSize = isCompact ? 176.0 : 210.0;
    final innerBallSize = isCompact ? 142.0 : 168.0;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final pulse = _pulseController.value;

        return SizedBox(
          width: dialSize,
          height: dialSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 外圍 270 度精密刻度繪製器 (210px)
              CustomPaint(
                size: Size(dialSize, dialSize),
                painter: _TachometerPainter(
                  isConnected: isConnected,
                  isConnecting: isConnecting,
                  pulse: pulse,
                ),
              ),

              // 呼吸外發光圈
              if (isConnected || isConnecting)
                Container(
                  width: innerBallSize,
                  height: innerBallSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (isConnected ? DesktopThemeTokens.emeraldGreen : DesktopThemeTokens.neonCyan)
                            .withOpacity(0.26 + pulse * 0.22),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                ),

              // 中央圓形觸發開關 (直徑 168px)
              Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: widget.onToggleConnection,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: innerBallSize,
                    height: innerBallSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: isConnected
                            ? const [Color(0xFF0F3A2E), Color(0xFF071813)]
                            : (isConnecting
                                ? const [Color(0xFF0D2C42), Color(0xFF07141E)]
                                : const [Color(0xFF141F36), Color(0xFF090E1A)]),
                        center: Alignment.center,
                        radius: 0.85,
                      ),
                      border: Border.all(
                        color: isConnected
                            ? DesktopThemeTokens.emeraldGreen
                            : (isConnecting ? DesktopThemeTokens.neonCyan : const Color(0xFF233554)),
                        width: 2.2,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isConnecting)
                          const SizedBox(
                            width: 44,
                            height: 44,
                            child: CircularProgressIndicator(
                              strokeWidth: 3.0,
                              color: DesktopThemeTokens.neonCyan,
                            ),
                          )
                        else
                          Icon(
                            Icons.power_settings_new_rounded,
                            size: 46,
                            color: isConnected
                                ? DesktopThemeTokens.emeraldGreen
                                : DesktopThemeTokens.neonCyan,
                          ),
                        const SizedBox(height: 8),
                        Text(
                          isConnected
                              ? i18n.t('action_accelerated')
                              : (isConnecting ? i18n.t('action_connecting') : i18n.t('tap_to_connect_action')),
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: isConnected
                                ? DesktopThemeTokens.emeraldGreen
                                : (isConnecting ? DesktopThemeTokens.neonCyan : Colors.white),
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
      },
    );
  }

  // ══════════════════════════════════════════════
  // 下半部左欄：2x2 連線狀態四宮格卡片
  // ══════════════════════════════════════════════
  Widget _buildConnectionStatusCard(
    CoreState coreState,
    TrafficStats traffic,
    dynamic user,
    dynamic selectedNode,
    I18nService i18n,
  ) {
    final isConnected = coreState.isConnected;
    final latencyMs = isConnected ? (selectedNode?.latencyMs ?? 38) : 0;
    final totalTraffic = user?.transferEnable ?? 0;
    final usedTraffic = (user?.u ?? 0) + (user?.d ?? 0);
    final ratio = totalTraffic > 0 ? (usedTraffic / totalTraffic).clamp(0.0, 1.0) : 0.0;
    final remainingPercent = ((1.0 - ratio) * 100).toInt();

    return Container(
      padding: const EdgeInsets.all(DesktopThemeTokens.cardPadding),
      decoration: BoxDecoration(
        color: DesktopThemeTokens.cardBg,
        borderRadius: BorderRadius.circular(DesktopThemeTokens.cardRadius),
        border: Border.all(color: DesktopThemeTokens.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sensors_rounded, size: 16, color: DesktopThemeTokens.neonCyan),
              const SizedBox(width: 8),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    i18n.t('service_and_traffic'),
                    style: DesktopThemeTokens.titleStyle,
                    maxLines: 1,
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // 同步訂閱按鈕 (精緻科技感膠囊按鈕，點擊同時刷新節點與用戶剩餘流量)
              InkWell(
                onTap: _isManualSyncing ? null : _handleManualSync,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: DesktopThemeTokens.neonCyan.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: DesktopThemeTokens.neonCyan.withOpacity(0.35),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RotationTransition(
                        turns: _syncRotationController,
                        child: const Icon(
                          Icons.sync_rounded,
                          size: 13,
                          color: DesktopThemeTokens.neonCyan,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        i18n.t('sync_subscription'),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: DesktopThemeTokens.neonCyan,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                decoration: BoxDecoration(
                  color: isConnected
                      ? DesktopThemeTokens.emeraldGreen.withOpacity(0.12)
                      : Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isConnected ? i18n.t('status_connected_badge') : i18n.t('status_disconnected_badge'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isConnected ? DesktopThemeTokens.emeraldGreen : DesktopThemeTokens.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2x2 等比方格
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      // 格子 1: 延遲探測
                      Expanded(
                        child: _buildStatCell(
                          title: i18n.t('latency'),
                          value: isConnected ? '$latencyMs ms' : '--',
                          subtitle: isConnected ? i18n.t('scale_best') : i18n.t('node_pending_test'),
                          accentColor: isConnected ? DesktopThemeTokens.emeraldGreen : DesktopThemeTokens.textMuted,
                          icon: Icons.speed_rounded,
                        ),
                      ),
                      const SizedBox(height: 10),
                      // 格子 2: 即時上傳
                      Expanded(
                        child: _buildSpeedCell(
                          title: i18n.t('upload'),
                          speed: isConnected ? traffic.upSpeedFormatted : '0.0 B/s',
                          color: DesktopThemeTokens.purpleAccent,
                          isDownload: false,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    children: [
                      // 格子 3: 剩餘可用流量
                      Expanded(
                        child: _buildStatCell(
                          title: i18n.t('remaining_traffic'),
                          value: '$remainingPercent%',
                          subtitle: user?.expiredDateFormatted ?? i18n.t('never_expire'),
                          accentColor: DesktopThemeTokens.neonCyan,
                          icon: Icons.pie_chart_outline_rounded,
                        ),
                      ),
                      const SizedBox(height: 10),
                      // 格子 4: 即時下載
                      Expanded(
                        child: _buildSpeedCell(
                          title: i18n.t('download'),
                          speed: isConnected ? traffic.downSpeedFormatted : '0.0 B/s',
                          color: DesktopThemeTokens.emeraldGreen,
                          isDownload: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCell({
    required String title,
    required String value,
    required String subtitle,
    required Color accentColor,
    required IconData icon,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: DesktopThemeTokens.cardInnerBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DesktopThemeTokens.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: accentColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: DesktopThemeTokens.labelStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontFamily: 'Segoe UI',
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: accentColor.withOpacity(0.8),
                        fontWeight: FontWeight.w600,
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

  Widget _buildSpeedCell({
    required String title,
    required String speed,
    required Color color,
    required bool isDownload,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: DesktopThemeTokens.cardInnerBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DesktopThemeTokens.borderColor),
      ),
      child: Stack(
        children: [
          Positioned(
            right: 0,
            bottom: 0,
            top: 10,
            width: 70,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CustomPaint(
                painter: _SpeedWavePainter(color: color, isDownload: isDownload),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(
                    isDownload ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                    size: 13,
                    color: color,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      title,
                      style: DesktopThemeTokens.labelStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      speed,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: color,
                        fontFamily: 'Segoe UI',
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

  // ══════════════════════════════════════════════
  // 下半部右欄：全球網絡 CyberWorldMap 卡片
  // ══════════════════════════════════════════════
  Widget _buildWorldMapCard(
    dynamic selectedNode,
    CoreState coreState,
    TrafficStats traffic,
    I18nService i18n,
  ) {
    return Container(
      padding: const EdgeInsets.all(DesktopThemeTokens.cardPadding),
      decoration: BoxDecoration(
        color: DesktopThemeTokens.cardBg,
        borderRadius: BorderRadius.circular(DesktopThemeTokens.cardRadius),
        border: Border.all(color: DesktopThemeTokens.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.public_rounded, size: 16, color: DesktopThemeTokens.neonCyan),
              const SizedBox(width: 8),
              Text(i18n.t('global_network'), style: DesktopThemeTokens.titleStyle),
              const Spacer(),
              if (selectedNode != null) ...[
                CountryFlagBadge(node: selectedNode, size: const Size(18, 12)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    selectedNode.cleanDisplayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: DesktopThemeTokens.neonCyan,
                    ),
                  ),
                ),
              ] else
                const Text(
                  '--',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: DesktopThemeTokens.textMuted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CyberWorldMap(
                activeNode: selectedNode,
                isConnected: coreState.isConnected,
                enableAnimations: widget.enableAnimations,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════
// 刻度儀表自定義繪製器 (270° Ticks)
// ══════════════════════════════════════════════
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
    final radius = size.width / 2 - 4;

    const startAngle = 0.75 * math.pi;
    const sweepAngle = 1.5 * math.pi;

    final activeColor = isConnected
        ? DesktopThemeTokens.emeraldGreen
        : (isConnecting ? DesktopThemeTokens.neonCyan : const Color(0xFF1E2D4A));

    // 底層軌道弧線
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

    // 動態發光弧線
    if (isConnected || isConnecting) {
      final glowPaint = Paint()
        ..color = activeColor.withOpacity(isConnected ? 0.35 + pulse * 0.25 : 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        glowPaint,
      );

      final corePaint = Paint()
        ..color = activeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        corePaint,
      );
    }

    // 沿弧線繪製刻度
    const tickCount = 42;
    for (int i = 0; i <= tickCount; i++) {
      final t = i / tickCount;
      final angle = startAngle + t * sweepAngle;
      final isMajor = (i % 6 == 0);
      final tickLength = isMajor ? 8.0 : 4.5;

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
        tickPaint.color = isMajor ? DesktopThemeTokens.neonBlue.withOpacity(0.5) : const Color(0xFF1E2D4A);
      }

      canvas.drawLine(p1, p2, tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TachometerPainter oldDelegate) {
    return oldDelegate.pulse != pulse ||
        oldDelegate.isConnected != isConnected ||
        oldDelegate.isConnecting != isConnecting;
  }
}

// ══════════════════════════════════════════════
// 速度波浪繪製器
// ══════════════════════════════════════════════
class _SpeedWavePainter extends CustomPainter {
  final Color color;
  final bool isDownload;

  _SpeedWavePainter({required this.color, required this.isDownload});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    path.moveTo(0, size.height * 0.7);

    for (double x = 0; x <= size.width; x += 4) {
      final y = size.height * 0.5 +
          math.sin((x / size.width) * 2 * math.pi) * (size.height * 0.25);
      path.lineTo(x, y);
    }

    final strokePaint = Paint()
      ..color = color.withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(path, strokePaint);

    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [color.withOpacity(0.2), Colors.transparent],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(path, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _SpeedWavePainter oldDelegate) => false;
}

// ══════════════════════════════════════════════
// 放大升級之首頁右上角節點膠囊 (規格 40px 高度、懸停微光、深海藍漸層與 24x17 國旗)
// ══════════════════════════════════════════════
class _SelectedNodePill extends StatefulWidget {
  final dynamic selectedNode;
  final I18nService i18n;
  final VoidCallback? onTap;
  final bool isSyncing;

  const _SelectedNodePill({
    required this.selectedNode,
    required this.i18n,
    this.onTap,
    this.isSyncing = false,
  });

  @override
  State<_SelectedNodePill> createState() => _SelectedNodePillState();
}

class _SelectedNodePillState extends State<_SelectedNodePill> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final nodeName = widget.selectedNode?.cleanDisplayName ??
        (widget.isSyncing ? widget.i18n.t('syncing_routes') : widget.i18n.t('node_unselected'));

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 40.0,
          constraints: const BoxConstraints(minWidth: 140.0),
          padding: const EdgeInsets.symmetric(horizontal: 14.0),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _isHovered
                  ? const [Color(0xFF334155), Color(0xFF1E293B)]
                  : const [Color(0xFF1E293B), Color(0xFF0F172A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _isHovered ? const Color(0xFF38BDF8) : const Color(0x3338BDF8),
              width: _isHovered ? 1.3 : 1.0,
            ),
            boxShadow: [
              if (_isHovered)
                BoxShadow(
                  color: const Color(0xFF38BDF8).withOpacity(0.28),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 左側放大彩色國旗 24 x 17 px
              CountryFlagBadge(
                node: widget.selectedNode,
                size: const Size(24, 17),
              ),
              const SizedBox(width: 9),

              // 節點名稱文字 14.5px Bold 白色
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Text(
                  nodeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // 右側箭頭圖示
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Color(0xFF94A3B8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

