// test/desktop_dashboard_layout_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:flclash_v2board_client/business/auth/auth_manager.dart';
import 'package:flclash_v2board_client/business/shop/shop_manager.dart';
import 'package:flclash_v2board_client/business/subscription/node_model.dart';
import 'package:flclash_v2board_client/business/subscription/subscription_engine.dart';
import 'package:flclash_v2board_client/core/network/dio_client.dart';
import 'package:flclash_v2board_client/core/storage/secure_storage_service.dart';
import 'package:flclash_v2board_client/infrastructure/config/app_config_service.dart';
import 'package:flclash_v2board_client/infrastructure/core_daemon/core_daemon.dart';
import 'package:flclash_v2board_client/infrastructure/core_daemon/windows_proxy_service.dart';
import 'package:flclash_v2board_client/core/i18n/i18n_service.dart';
import 'package:flclash_v2board_client/presentation/dashboard/widgets/desktop_dashboard_layout.dart';

class MockMemorySecureStorage extends SecureStorageService {
  final Map<String, String> _data = {};
  @override
  Future<void> saveToken(String token) async => _data['token'] = token;
  @override
  Future<String?> getToken() async => _data['token'];
  @override
  Future<void> saveUserInfoJson(String jsonStr) async => _data['user'] = jsonStr;
  @override
  Future<String?> getUserInfoJson() async => _data['user'];
  @override
  Future<void> clearAll() async => _data.clear();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockMemorySecureStorage storageService;
  late AppConfigService configService;
  late DioClient dioClient;
  late AuthManager authManager;
  late CoreDaemon coreDaemon;
  late SubscriptionEngine subscriptionEngine;
  late ShopManager shopManager;

  setUp(() {
    WindowsProxyService.mockIsAdmin = true;
    WindowsProxyService.mockIsWintun = true;
    storageService = MockMemorySecureStorage();
    configService = AppConfigService();
    dioClient = DioClient(configService: configService, customDio: Dio());
    authManager = AuthManager(dioClient: dioClient, storageService: storageService);
    coreDaemon = CoreDaemon();
    subscriptionEngine = SubscriptionEngine(
      dioClient: dioClient,
      coreDaemon: coreDaemon,
      storageService: storageService,
    );
    shopManager = ShopManager(dioClient: dioClient);
  });

  group('Windows 桌面版專屬佈局 (DesktopDashboardLayout) 驗證測試', () {
    testWidgets('1. 完整呈現左導覽、頂部資訊列、核心加速區與雙欄儀表板四大區塊', (tester) async {
      // 模擬注入測試節點與用戶資料
      final testNode = NodeModel(
        id: 'node-jp-01',
        name: '日本大阪 1x HYSTERIA2',
        flagEmoji: '🇯🇵',
        protocol: 'hysteria2',
        latencyMs: 42,
        rawConfig: {'server': '1.1.1.1', 'port': 443},
      );
      subscriptionEngine.selectNode(testNode);

      // 設定視窗寬版尺寸 (1120 x 740)
      tester.view.physicalSize = const Size(1120, 740);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      bool toggleCalled = false;
      bool logoutCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopDashboardLayout(
              authManager: authManager,
              configService: configService,
              coreDaemon: coreDaemon,
              subscriptionEngine: subscriptionEngine,
              shopManager: shopManager,
              onToggleConnection: () => toggleCalled = true,
              onLogout: () => logoutCalled = true,
              isSyncing: false,
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 200));

      // 驗證 A: 左側垂直導覽列
      // 驗證 A: 左側垂直導覽列 (100% 綁定多語系)
      final i18n = I18nService.instance;
      expect(find.text(i18n.t('nav_home')), findsOneWidget);
      expect(find.text(i18n.t('nav_shop')), findsOneWidget);
      expect(find.text(i18n.t('nav_nodes')), findsOneWidget);
      expect(find.text(i18n.t('nav_connections')), findsOneWidget);
      expect(find.text(i18n.t('nav_traffic')), findsOneWidget);
      expect(find.text(i18n.t('nav_affiliate')), findsOneWidget);
      expect(find.text(i18n.t('nav_profile')), findsOneWidget);
      expect(find.text(i18n.t('nav_settings')), findsOneWidget);
      expect(find.text(i18n.t('sign_out')), findsOneWidget);

      // 驗證 B: 右上頂部資訊列快捷按鈕
      expect(find.byIcon(Icons.translate_rounded), findsOneWidget);
      expect(find.byIcon(Icons.wifi_rounded), findsOneWidget);
      expect(find.byIcon(Icons.card_giftcard_rounded), findsWidgets);
      expect(find.byIcon(Icons.headset_mic_rounded), findsOneWidget);
      expect(find.byIcon(Icons.campaign_rounded), findsOneWidget);

      // 驗證 C: 主視覺核心加速區
      expect(find.text(i18n.t('tap_to_connect')), findsWidgets);
      expect(find.text(i18n.t('mode_global')), findsOneWidget);
      expect(find.text(i18n.t('mode_rule')), findsOneWidget);
      expect(find.text(i18n.t('mode_tun')), findsOneWidget);

      // 驗證 D: 下半部雙欄儀表板
      expect(find.text(i18n.t('connection_status')), findsOneWidget);
      expect(find.text(i18n.t('sync_sub')), findsOneWidget);
      expect(find.text(i18n.t('current_node')), findsOneWidget);
      expect(find.text('日本大阪 1x HYSTERIA2 - HYSTERIA2'), findsOneWidget);
      expect(find.text(i18n.t('latency')), findsOneWidget);
      expect(find.text(i18n.t('download')), findsOneWidget);
      expect(find.text(i18n.t('upload')), findsOneWidget);
      expect(find.text(i18n.t('traffic_stats')), findsOneWidget);
      expect(find.text(i18n.t('global_network')), findsOneWidget);

      // 測試點擊連線按鈕
      await tester.tap(find.text(i18n.t('tap_to_connect')).first);
      expect(toggleCalled, isTrue);

      // 測試點擊退出登錄
      await tester.tap(find.text(i18n.t('sign_out')));
      expect(logoutCalled, isTrue);
    });

    testWidgets('2. 模式切換膠囊支援即時切換 rule / global / tun 模式', (tester) async {
      tester.view.physicalSize = const Size(1120, 740);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopDashboardLayout(
              authManager: authManager,
              configService: configService,
              coreDaemon: coreDaemon,
              subscriptionEngine: subscriptionEngine,
              shopManager: shopManager,
              onToggleConnection: () {},
              onLogout: () {},
              isSyncing: false,
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 200));

      expect(coreDaemon.proxyMode.name, 'rule');

      final i18n = I18nService.instance;

      // 點擊切換為全局模式 (Global)
      await tester.tap(find.text(i18n.t('mode_global')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(coreDaemon.proxyMode.name, 'global');

      // 點擊切換為 TUN 模式 (TUN Mode)
      await tester.tap(find.text(i18n.t('mode_tun')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(coreDaemon.proxyMode.name, 'tun');
    });

    testWidgets('3. 左導覽選單切換至節點狀態頁展示完整線路與測速功能', (tester) async {
      tester.view.physicalSize = const Size(1120, 740);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopDashboardLayout(
              authManager: authManager,
              configService: configService,
              coreDaemon: coreDaemon,
              subscriptionEngine: subscriptionEngine,
              shopManager: shopManager,
              onToggleConnection: () {},
              onLogout: () {},
              isSyncing: false,
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 200));

      // 點擊左側「節點狀態」
      await tester.tap(find.text(I18nService.instance.t('nav_nodes')));
      await tester.pump(const Duration(milliseconds: 200));

      // 驗證節點頁頂部控制列
      expect(find.text(I18nService.instance.t('node_batch_ping')), findsOneWidget);
      expect(find.text(I18nService.instance.t('node_select_fastest')), findsOneWidget);
      expect(find.text(I18nService.instance.t('node_tab_asia')), findsWidgets);
      expect(find.text(I18nService.instance.t('node_tab_western')), findsWidgets);
      expect(find.text(I18nService.instance.t('node_tab_others')), findsWidgets);
    });
  });
}
