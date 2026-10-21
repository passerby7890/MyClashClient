// lib/presentation/dashboard/dashboard_screen.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_constants.dart';
import '../../core/i18n/i18n_service.dart';
import '../../core/storage/secure_storage_service.dart';
import '../../core/theme/app_theme.dart';
import '../../infrastructure/config/app_config_service.dart';
import '../../infrastructure/core_daemon/core_daemon.dart';
import '../../business/auth/auth_manager.dart';
import '../../business/auth/traffic_notification_service.dart';
import '../../business/subscription/subscription_engine.dart';
import '../../business/shop/shop_manager.dart';
import '../auth/login_screen.dart';
import '../more/more_screen.dart';
import '../profile/traffic_detail_screen.dart';
import '../profile/user_center_screen.dart';
import '../shop/shop_screen.dart';
import 'widgets/connection_button.dart';
import 'widgets/customer_service_modal.dart';
import '../desktop/desktop_shell.dart';
import 'widgets/node_selector_modal.dart';
import 'widgets/notice_dialog.dart';
import 'widgets/traffic_card.dart';

/// 主控台儀表板 (DashboardScreen)
/// 提供 4 大核心分頁動線：[主頁] [套餐] [更多] [我的]，1:1 串接 V2Board 後台真實 API
class DashboardScreen extends StatefulWidget {
  final AuthManager authManager;
  final AppConfigService configService;
  final CoreDaemon? coreDaemon;
  final SubscriptionEngine? subscriptionEngine;

  const DashboardScreen({
    super.key,
    required this.authManager,
    required this.configService,
    this.coreDaemon,
    this.subscriptionEngine,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  late final CoreDaemon _coreDaemon;
  late final SubscriptionEngine _subscriptionEngine;
  late final ShopManager _shopManager;
  bool _isSyncing = false;
  bool _hasCheckedNotice = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _coreDaemon = widget.coreDaemon ?? CoreDaemon();

    // 使用 AuthManager 中已注入 AuthInterceptor 憑證之 DioClient
    final dioClient = widget.authManager.dioClient;
    final storage = SecureStorageService();

    _subscriptionEngine = widget.subscriptionEngine ??
        SubscriptionEngine(
          dioClient: dioClient,
          coreDaemon: _coreDaemon,
          storageService: storage,
        );

    // 綁定 AuthManager 供自動同步與刷新使用
    _subscriptionEngine.attachAuthManager(widget.authManager);
    _subscriptionEngine.initAutoSyncDaemon();

    // 綁定會話清理監聽器：登出或 401 踢出時同步清理節點記憶體與加密金庫
    widget.authManager.addSessionClearedListener(_onSessionCleared);

    _shopManager = ShopManager(dioClient: dioClient);

    _initialSync();
  }

  void _onSessionCleared() {
    _subscriptionEngine.clearVaultAndMemory();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.authManager.removeSessionClearedListener(_onSessionCleared);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _subscriptionEngine.onWindowWakeup();
    }
  }

  /// 初次載入與靜默同步訂閱 (三層式加密快取 + 登入強同步保障 + 0 秒瞬開)
  Future<void> _initialSync() async {
    // 步驟 1 (0 秒瞬開 SLA)：首先從本地加密金庫瞬間解密還原所有節點至記憶體與 UI (耗時 < 10ms)
    final hasCached = await _subscriptionEngine.restoreFromVault();

    final token = widget.authManager.state.token;
    final user = widget.authManager.state.user;

    // 步驟 2 (首次登入無金庫快取防護)：標記同步載入狀態，卡片顯示「正在同步專屬線路...」
    if (!hasCached && _subscriptionEngine.nodes.isEmpty) {
      if (mounted) setState(() => _isSyncing = true);
    }

    if (token != null && token.isNotEmpty) {
      try {
        // 步驟 3 (Stale-While-Revalidate)：背景靜默同步最新訂閱 (內含 3 次自動重試)
        await _subscriptionEngine.syncSubscription(
          token: token,
          customSubscribeUrl: user?.subscribeUrl,
        );
      } catch (e) {
        debugPrint('[DashboardScreen] 背景同步訂閱失敗: $e');
      }

      // 檢查並彈出公告 (依據遠端配置之 enableNotice 開關)
      if (!_hasCheckedNotice && widget.configService.activeConfig.enableNotice) {
        _hasCheckedNotice = true;
        try {
          final notices = await widget.authManager.fetchNotices();
          final popup = notices.where((n) => n.isPopup && n.show).firstOrNull;
          if (popup != null && mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                NoticeDialog.show(context, popup);
              }
            });
          }
        } catch (_) {}
      }

      if (mounted) setState(() => _isSyncing = false);
    }
  }

  /// 一鍵切換連線狀態 (防連擊與狀態防抖 + 單節點切片與閱後即焚)
  Future<void> _handleToggleConnection() async {
    if (_coreDaemon.state.isConnecting || _coreDaemon.state.isDisconnecting) return;

    final isConnected = _coreDaemon.state.isConnected;
    final selected = _subscriptionEngine.selectedNode;

    if (isConnected) {
      await _coreDaemon.stop();
    } else {
      // 帳號配額與過期防護 (防護無效代理空轉)
      final user = widget.authManager.state.user;
      if (user != null) {
        if (user.isExpired) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(I18nService.instance.t('traffic_warning_expired')),
              backgroundColor: Colors.redAccent,
            ),
          );
          return;
        }
        if (user.isTrafficDepleted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(I18nService.instance.t('traffic_warning_exhausted')),
              backgroundColor: Colors.redAccent,
            ),
          );
          return;
        }
      }

      if (selected == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(I18nService.instance.t('select_node_hint'))),
        );
        return;
      }

      // 單節點切片 + 閱後即焚：動態僅生成選中節點之臨時 config.yaml (啟動後自動抹除)
      try {
        final configPath = await _subscriptionEngine.prepareConfigForConnection(autoShred: true);
        await _coreDaemon.start(
          configPath: configPath,
          selectedNode: selected.name,
        );
        // 連線成功後立即對當前節點發起一次真實 TCP 測速，驅動 UI 延遲即時跳動
        _subscriptionEngine.pingSelectedNode();
      } catch (e) {
        // 連線失敗自救觸發 (若距離上次同步超過 5 分鐘自動刷新訂閱)
        _subscriptionEngine.triggerFailureRescueSync();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('連線失敗: $e'),
              backgroundColor: Colors.redAccent,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    }
  }

  /// 處理登出程序
  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkSurface,
        title: Text(I18nService.instance.t('logout_confirm_title')),
        content: Text(I18nService.instance.t('logout_confirm_desc')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(I18nService.instance.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.dangerRose),
            child: Text(I18nService.instance.t('confirm')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (_coreDaemon.state.isConnected) {
        await _coreDaemon.stop();
      }
      await widget.authManager.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => LoginScreen(
            authManager: widget.authManager,
            configService: widget.configService,
          ),
        ),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = (!kIsWeb && (Platform.isMacOS || Platform.isWindows)) || MediaQuery.of(context).size.width >= 900;

    return ListenableBuilder(
      listenable: Listenable.merge([widget.authManager, _coreDaemon, _subscriptionEngine, I18nService.instance]),
      builder: (context, _) {
        if (isDesktop) {
          return DesktopShell(
            authManager: widget.authManager,
            configService: widget.configService,
            coreDaemon: _coreDaemon,
            subscriptionEngine: _subscriptionEngine,
            shopManager: _shopManager,
            onToggleConnection: _handleToggleConnection,
            onLogout: _handleLogout,
            isSyncing: _isSyncing,
          );
        }

        final pages = [
          _buildHomeScreen(),
          ShopScreen(shopManager: _shopManager),
          MoreScreen(
            coreDaemon: _coreDaemon,
            subscriptionEngine: _subscriptionEngine,
            configService: widget.configService,
            authManager: widget.authManager,
          ),
          UserCenterScreen(
            authManager: widget.authManager,
            shopManager: _shopManager,
            configService: widget.configService,
            onSwitchTab: (idx) => setState(() => _currentIndex = idx),
          ),
        ];

        return Scaffold(
          backgroundColor: AppTheme.darkBackground,
          body: IndexedStack(
            index: _currentIndex,
            children: pages,
          ),
          bottomNavigationBar: _buildBottomNav(),
        );
      },
    );
  }

  /// 底部導覽列 (1:1 對齊截圖風格與藍色選中指示器)
  Widget _buildBottomNav() {
    final i18n = I18nService.instance;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        border: Border(top: BorderSide(color: AppTheme.darkBorder.withOpacity(0.5), width: 0.8)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.bolt_rounded, i18n.t('nav_home')),
              _buildNavItem(1, Icons.storefront_rounded, i18n.t('nav_plan')),
              _buildNavItem(2, Icons.explore_rounded, i18n.t('nav_more')),
              _buildNavItem(3, Icons.person_rounded, i18n.t('nav_profile')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    return InkWell(
      onTap: () => setState(() => _currentIndex = index),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: isSelected ? 48 : 32,
              height: 30,
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF1976D2) : Colors.transparent,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Center(
                child: Icon(
                  icon,
                  size: 20,
                  color: isSelected ? Colors.white : Colors.white60,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : Colors.white60,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 首頁儀表板 View
  Widget _buildHomeScreen() {
    final user = widget.authManager.state.user;
    final coreState = _coreDaemon.state;
    final traffic = _coreDaemon.currentTraffic;
    final selectedNode = _subscriptionEngine.selectedNode;

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.primaryCyan.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.shield_rounded, color: AppTheme.primaryCyan, size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      I18nService.instance.t('app_title'),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryCyan.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppTheme.primaryCyan.withOpacity(0.5), width: 0.8),
                      ),
                      child: const Text(
                        AppConstants.versionTag,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryCyan,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  user?.email ?? I18nService.instance.t('guest_mode'),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.45),
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: I18nService.instance.t('logout'),
            icon: const Icon(Icons.logout_rounded, color: Colors.white70),
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppTheme.primaryCyan,
        backgroundColor: AppTheme.darkSurface,
        onRefresh: () async {
          await widget.authManager.fetchUserInfo();
          final token = widget.authManager.state.token;
          final u = widget.authManager.state.user;
          if (token != null) {
            await _subscriptionEngine.syncSubscription(
              token: token,
              customSubscribeUrl: u?.subscribeUrl,
            );
          }
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                children: [
                  // 0. 輪播圖配置 (若後端/生成器有配置 Carousel 則動態展示)
                  _buildCarouselBanner(),

                  // 流量即將耗盡 / 到期預警推播橫條 (TODO-03)
                  ListenableBuilder(
                    listenable: TrafficNotificationService.instance,
                    builder: (context, _) {
                      final alert = TrafficNotificationService.instance.currentAlert;
                      if (alert == null) return const SizedBox.shrink();
                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: alert.isBlocking
                              ? Colors.redAccent.withOpacity(0.18)
                              : Colors.amberAccent.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: alert.isBlocking
                                ? Colors.redAccent.withOpacity(0.6)
                                : Colors.amberAccent.withOpacity(0.6),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              alert.isBlocking ? Icons.error_rounded : Icons.warning_amber_rounded,
                              color: alert.isBlocking ? Colors.redAccent : Colors.amberAccent,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                alert.message,
                                style: TextStyle(
                                  color: alert.isBlocking ? Colors.redAccent : Colors.amberAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (!alert.isBlocking)
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 16),
                                color: Colors.white54,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                onPressed: () {
                                  TrafficNotificationService.instance.dismissAlert();
                                },
                              ),
                          ],
                        ),
                      );
                    },
                  ),

                  // 1. 流量狀態預警卡片 (受 enableTrafficDetails 開關控制)
                  if (widget.configService.activeConfig.enableTrafficDetails) ...[
                    TrafficCard(
                      user: user,
                      onRenewTap: () {
                        setState(() => _currentIndex = 1);
                      },
                      onDetailTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => TrafficDetailScreen(
                              authManager: widget.authManager,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                  ],

                  // 2. 當前選定節點快速切換橫條
                  GestureDetector(
                    onTap: () {
                      NodeSelectorModal.show(
                        context,
                        subscriptionEngine: _subscriptionEngine,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppTheme.darkCard,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.darkBorder),
                      ),
                      child: Row(
                        children: [
                          Text(
                            selectedNode?.flagEmoji ?? '🌐',
                            style: const TextStyle(fontSize: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  selectedNode?.name ?? (_isSyncing ? I18nService.instance.t('syncing_routes') : I18nService.instance.t('node_unselected')),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  selectedNode?.protocol ?? (_isSyncing ? I18nService.instance.t('loading_nodes') : I18nService.instance.t('tap_to_select_node')),
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.45),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (selectedNode != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryCyan.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                selectedNode.latencyFormatted,
                                style: const TextStyle(
                                  color: AppTheme.primaryCyan,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.white54),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 3. 一鍵連線大按鈕 (具呼吸光暈與即時速率)
                  ConnectionButton(
                    coreState: coreState,
                    trafficStats: traffic,
                    isAccountValid: user?.isAvailable ?? true,
                    onTap: _handleToggleConnection,
                  ),
                  const SizedBox(height: 26),

                  // 4. 底部捷徑工具列 (同步訂閱、一鍵測速、節點選擇、在線客服)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildActionTile(
                        icon: Icons.sync_rounded,
                        label: _isSyncing ? I18nService.instance.t('status_connecting') : I18nService.instance.t('sync_subscription'),
                        onTap: _isSyncing
                            ? null
                            : () async {
                                final token = widget.authManager.state.token;
                                final u = widget.authManager.state.user;
                                if (token != null) {
                                  setState(() => _isSyncing = true);
                                  try {
                                    await _subscriptionEngine.syncSubscription(
                                      token: token,
                                      customSubscribeUrl: u?.subscribeUrl,
                                    );
                                  } catch (_) {}
                                  setState(() => _isSyncing = false);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(I18nService.instance.t('sync_subscription'))),
                                    );
                                  }
                                }
                              },
                      ),
                      _buildActionTile(
                        icon: Icons.bolt_rounded,
                        label: I18nService.instance.t('speed_test'),
                        onTap: () async {
                          await _subscriptionEngine.pingAllNodes();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(I18nService.instance.t('speed_test_done'))),
                            );
                          }
                        },
                      ),
                      _buildActionTile(
                        icon: Icons.list_alt_rounded,
                        label: I18nService.instance.t('select_node'),
                        onTap: () {
                          NodeSelectorModal.show(
                            context,
                            subscriptionEngine: _subscriptionEngine,
                          );
                        },
                      ),
                      _buildActionTile(
                        icon: Icons.headset_mic_rounded,
                        label: I18nService.instance.t('online_service'),
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
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCarouselBanner() {
    final items = widget.configService.activeConfig.carouselItems;
    if (items.isEmpty) return const SizedBox.shrink();

    final item = items.first;
    final imageUrl = item is Map ? (item['Carouselimages'] ?? item['image'])?.toString() : null;
    final targetUrl = item is Map ? (item['Carouseladdress'] ?? item['url'])?.toString() : null;

    if (imageUrl == null || imageUrl.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: GestureDetector(
        onTap: () async {
          if (targetUrl != null && targetUrl.isNotEmpty) {
            final uri = Uri.parse(targetUrl);
            try {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } catch (_) {}
          }
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              border: Border.all(color: AppTheme.darkBorder),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Image.network(
              imageUrl,
              height: 110,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.darkCard,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.darkBorder),
              ),
              child: Icon(icon, color: AppTheme.primaryCyan, size: 20),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
