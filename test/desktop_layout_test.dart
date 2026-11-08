// test/desktop_layout_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flclash_v2board_client/core/network/dio_client.dart';
import 'package:flclash_v2board_client/core/storage/secure_storage_service.dart';
import 'package:flclash_v2board_client/infrastructure/config/app_config_service.dart';
import 'package:flclash_v2board_client/infrastructure/core_daemon/core_daemon.dart';
import 'package:flclash_v2board_client/infrastructure/core_daemon/core_state.dart';
import 'package:flclash_v2board_client/business/auth/auth_manager.dart';
import 'package:flclash_v2board_client/business/auth/user_model.dart';
import 'package:flclash_v2board_client/business/subscription/subscription_engine.dart';
import 'package:flclash_v2board_client/business/shop/shop_manager.dart';
import 'package:flclash_v2board_client/infrastructure/core_daemon/windows_proxy_service.dart';
import 'package:flclash_v2board_client/presentation/dashboard/widgets/desktop_dashboard_layout.dart';
import 'package:flclash_v2board_client/presentation/dashboard/widgets/cyber_world_map.dart';
import 'package:flclash_v2board_client/core/i18n/i18n_service.dart';
import 'package:flclash_v2board_client/presentation/profile/traffic_detail_screen.dart';
import 'package:flclash_v2board_client/presentation/desktop/desktop_traffic_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DioClient dioClient;
  late SecureStorageService storage;
  late AuthManager authManager;
  late AppConfigService configService;
  late CoreDaemon coreDaemon;
  late SubscriptionEngine subscriptionEngine;
  late ShopManager shopManager;

  setUp(() {
    WindowsProxyService.mockIsAdmin = true;
    WindowsProxyService.mockIsWintun = true;
    configService = AppConfigService();
    dioClient = DioClient(configService: configService);
    storage = SecureStorageService();
    authManager = AuthManager(dioClient: dioClient, storageService: storage);
    coreDaemon = CoreDaemon();
    subscriptionEngine = SubscriptionEngine(
      dioClient: dioClient,
      coreDaemon: coreDaemon,
      storageService: storage,
    );
    shopManager = ShopManager(dioClient: dioClient);
  });

  Widget buildTestDesktopWidget({VoidCallback? onToggle, VoidCallback? onLogout}) {
    return MaterialApp(
      home: Scaffold(
        body: DesktopDashboardLayout(
          authManager: authManager,
          configService: configService,
          coreDaemon: coreDaemon,
          subscriptionEngine: subscriptionEngine,
          shopManager: shopManager,
          onToggleConnection: onToggle ?? () {},
          onLogout: onLogout ?? () {},
          isSyncing: false,
        ),
      ),
    );
  }

  group('【Windows 桌面專屬版 UI 排版與組件測試】', () {
    testWidgets('1. DesktopDashboardLayout 四大區塊完整渲染驗證', (tester) async {
      // 設置模擬使用者資料
      final testUser = UserModel(
        email: 'audit_user@tianhe.net',
        transferEnable: 1024 * 1024 * 1024 * 100, // 100 GB
        u: 1024 * 1024 * 1024 * 10,
        d: 1024 * 1024 * 1024 * 15,
        expiredAt: DateTime.now().add(const Duration(days: 90)).millisecondsSinceEpoch ~/ 1000,
      );
      authManager.updateUserForTest(testUser);

      tester.view.physicalSize = const Size(1120, 740);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      await tester.binding.setSurfaceSize(const Size(1120, 740));
      await tester.pumpWidget(buildTestDesktopWidget());
      await tester.pump(const Duration(milliseconds: 300));

      final i18n = I18nService.instance;

      // 驗證 A. 左側垂直導覽列
      expect(find.text(i18n.t('nav_home')), findsOneWidget);
      expect(find.text(i18n.t('nav_shop')), findsOneWidget);
      expect(find.text(i18n.t('nav_nodes')), findsOneWidget);
      expect(find.text(i18n.t('nav_connections')), findsOneWidget);
      expect(find.text(i18n.t('nav_traffic')), findsOneWidget);
      expect(find.text(i18n.t('nav_affiliate')), findsOneWidget);
      expect(find.text(i18n.t('nav_profile')), findsOneWidget);
      expect(find.text(i18n.t('nav_settings')), findsOneWidget);
      expect(find.text(i18n.t('sign_out')), findsOneWidget);

      // 驗證 B. 右上頂部資訊列
      expect(find.text('audit_user@tianhe.net'), findsOneWidget);
      expect(find.text('VIP'), findsOneWidget);

      // 驗證 C. 主視覺核心加速區
      expect(find.text(i18n.t('tap_to_connect')), findsWidgets);
      expect(find.text(i18n.t('mode_global')), findsOneWidget);
      expect(find.text(i18n.t('mode_rule')), findsOneWidget);
      expect(find.text(i18n.t('mode_tun')), findsOneWidget);

      // 驗證 D. 下半部雙欄狀態儀表板
      expect(find.text(i18n.t('connection_status')), findsOneWidget);
      expect(find.text(i18n.t('global_network')), findsOneWidget);
      expect(find.text(i18n.t('latency')), findsOneWidget);
      expect(find.text(i18n.t('download')), findsOneWidget);
      expect(find.text(i18n.t('upload')), findsOneWidget);
      expect(find.text(i18n.t('traffic_stats')), findsOneWidget);

      // 驗證世界地圖組件
      expect(find.byType(CyberWorldMap), findsWidgets);
    });

    testWidgets('2. 核心分流模式切換 (Rule / Global / TUN) 狀態機響應驗證', (tester) async {
      final i18n = I18nService.instance;
      await tester.binding.setSurfaceSize(const Size(1120, 740));
      await tester.pumpWidget(buildTestDesktopWidget());
      await tester.pump(const Duration(milliseconds: 100));

      expect(coreDaemon.proxyMode, equals(ProxyMode.rule));

      // 點選「Global」
      await tester.tap(find.text(i18n.t('mode_global')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(coreDaemon.proxyMode, equals(ProxyMode.global));

      // 點選「TUN Mode」
      await tester.tap(find.text(i18n.t('mode_tun')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(coreDaemon.proxyMode, equals(ProxyMode.tun));

      // 點回「Rule」
      await tester.tap(find.text(i18n.t('mode_rule')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(coreDaemon.proxyMode, equals(ProxyMode.rule));
    });

    testWidgets('3. 左側選單切換分頁導航驗證', (tester) async {
      final i18n = I18nService.instance;
      await tester.binding.setSurfaceSize(const Size(1120, 740));
      await tester.pumpWidget(buildTestDesktopWidget());
      await tester.pump(const Duration(milliseconds: 100));

      // 點擊「節點狀態」
      await tester.tap(find.text(i18n.t('nav_nodes')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(i18n.t('node_selector_title')), findsOneWidget);

      // 點擊「流量詳情」
      await tester.tap(find.text(i18n.t('nav_traffic')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(DesktopTrafficView), findsOneWidget);

      // 點回「加速主頁」
      await tester.tap(find.text(i18n.t('nav_home')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(i18n.t('connection_status')), findsOneWidget);
    });

    testWidgets('4. 連線開關點擊回呼與退出登錄回呼驗證', (tester) async {
      final i18n = I18nService.instance;
      bool toggleClicked = false;
      bool logoutClicked = false;

      await tester.binding.setSurfaceSize(const Size(1120, 740));
      await tester.pumpWidget(buildTestDesktopWidget(
        onToggle: () => toggleClicked = true,
        onLogout: () => logoutClicked = true,
      ));
      await tester.pump();

      // 點擊中央大開關
      await tester.tap(find.text(i18n.t('tap_to_connect')).first);
      expect(toggleClicked, isTrue);

      // 點擊退出登錄
      await tester.tap(find.text(i18n.t('sign_out')));
      expect(logoutClicked, isTrue);
    });
  });
}
