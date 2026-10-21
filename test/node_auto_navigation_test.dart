// test/node_auto_navigation_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flclash_v2board_client/core/constants/app_constants.dart';
import 'package:flclash_v2board_client/core/network/dio_client.dart';
import 'package:flclash_v2board_client/core/storage/secure_storage_service.dart';
import 'package:flclash_v2board_client/infrastructure/config/app_config_service.dart';
import 'package:flclash_v2board_client/infrastructure/core_daemon/core_daemon.dart';
import 'package:flclash_v2board_client/business/auth/auth_manager.dart';
import 'package:flclash_v2board_client/business/auth/user_model.dart';
import 'package:flclash_v2board_client/business/subscription/node_model.dart';
import 'package:flclash_v2board_client/business/subscription/subscription_engine.dart';
import 'package:flclash_v2board_client/business/shop/shop_manager.dart';
import 'package:flclash_v2board_client/infrastructure/core_daemon/windows_proxy_service.dart';
import 'package:flclash_v2board_client/presentation/desktop/desktop_nodes_view.dart';
import 'package:flclash_v2board_client/presentation/desktop/desktop_settings_view.dart';
import 'package:flclash_v2board_client/presentation/desktop/desktop_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DioClient dioClient;
  late SecureStorageService storage;
  late AuthManager authManager;
  late AppConfigService configService;
  late CoreDaemon coreDaemon;
  late SubscriptionEngine subscriptionEngine;
  late ShopManager shopManager;

  const sampleNodes = [
    NodeModel(
      id: '1',
      name: '🇭🇰 香港-01',
      flagEmoji: '🇭🇰',
      protocol: 'shadowsocks',
      latencyMs: 38,
      rawConfig: {'server': 'hk1.tianhe.net', 'port': 443},
    ),
    NodeModel(
      id: '2',
      name: '🇯🇵 日本-01',
      flagEmoji: '🇯🇵',
      protocol: 'vmess',
      latencyMs: 55,
      rawConfig: {'server': 'jp1.tianhe.net', 'port': 443},
    ),
    NodeModel(
      id: '3',
      name: '🇺🇸 直連-美國',
      flagEmoji: '🇺🇸',
      protocol: 'trojan',
      latencyMs: 145,
      rawConfig: {'server': 'us1.tianhe.net', 'port': 443},
    ),
  ];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
    subscriptionEngine.setNodesForTest(sampleNodes);
    shopManager = ShopManager(dioClient: dioClient);
  });

  group('【節點點擊後的智慧自動導航與一鍵連線閉環測試】', () {
    testWidgets('1. DesktopNodesView 點擊節點卡片：成功選取節點並在 100ms 內自動回調 onNavigateToHome', (tester) async {
      bool navigatedHome = false;
      bool triggeredConnect = false;

      tester.view.physicalSize = const Size(1200, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopNodesView(
              subscriptionEngine: subscriptionEngine,
              onNavigateToHome: () {
                navigatedHome = true;
              },
              onTriggerConnect: () {
                triggeredConnect = true;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 尋找美國節點並點擊
      final usNodeFinder = find.text('直連-美國');
      expect(usNodeFinder, findsOneWidget);

      await tester.tap(usNodeFinder);
      await tester.pump();

      // 第一步：檢查節點已被設為生效節點
      expect(subscriptionEngine.selectedNode?.name, '🇺🇸 直連-美國');

      // 推進 150ms 讓 100ms 延遲與非同步導航執行完成
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();

      // 第二步：驗證已自動導回主頁
      expect(navigatedHome, isTrue);

      // 預設情況下未開啟自動連線
      expect(triggeredConnect, isFalse);
    });

    testWidgets('2. 啟用自動連線配置時：點擊節點觸發導回主頁 + onTriggerConnect 連線閉環', (tester) async {
      SharedPreferences.setMockInitialValues({
        AppConstants.storageAutoConnectOnNodeSelect: true,
      });

      bool navigatedHome = false;
      bool triggeredConnect = false;

      tester.view.physicalSize = const Size(1200, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopNodesView(
              subscriptionEngine: subscriptionEngine,
              onNavigateToHome: () {
                navigatedHome = true;
              },
              onTriggerConnect: () {
                triggeredConnect = true;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final jpNodeFinder = find.text('日本-01');
      expect(jpNodeFinder, findsOneWidget);

      await tester.tap(jpNodeFinder);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();

      expect(subscriptionEngine.selectedNode?.name, '🇯🇵 日本-01');
      expect(navigatedHome, isTrue);
      expect(triggeredConnect, isTrue);
    });

    testWidgets('3. DesktopSettingsView 提供「選取節點後自動連線」Switch 開關並正常持久化', (tester) async {
      tester.view.physicalSize = const Size(1200, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopSettingsView(
              coreDaemon: coreDaemon,
              subscriptionEngine: subscriptionEngine,
              configService: configService,
              authManager: authManager,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 尋找自動連線開關標題
      final switchTitleFinder = find.text('選取節點後自動連線');
      expect(switchTitleFinder, findsOneWidget);

      // 尋找 Switch
      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsWidgets);

      // 點擊第一個 Switch (即自動連線開關)
      await tester.tap(switchFinder.first);
      await tester.pumpAndSettle();

      // 驗證 SharedPreferences 持久化成功
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(AppConstants.storageAutoConnectOnNodeSelect), isTrue);
    });

    testWidgets('4. DesktopShell 完整端到端：從節點分頁 (Tab 2) 點選節點瞬間自動切回主頁 (Tab 0)', (tester) async {
      final testUser = UserModel(
        email: 'nick@tianhe.net',
        transferEnable: 100 * 1024 * 1024 * 1024,
        u: 10 * 1024 * 1024 * 1024,
        d: 20 * 1024 * 1024 * 1024,
      );
      authManager.updateUserForTest(testUser);

      tester.view.physicalSize = const Size(1200, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopShell(
              authManager: authManager,
              configService: configService,
              coreDaemon: coreDaemon,
              subscriptionEngine: subscriptionEngine,
              shopManager: shopManager,
              onToggleConnection: () {},
              onLogout: () {},
              initialNavIndex: 2, // 直接進入節點狀態分頁
              enableAnimations: false,
            ),
          ),
        ),
      );

      await tester.pump();

      // 確認在節點頁面
      expect(find.text('直連-美國'), findsOneWidget);

      // 點選美國節點
      await tester.tap(find.text('直連-美國'));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();

      // 驗證畫面已自動切換回加速主頁 (能看到加速主頁的 Tachometer 圓球「點擊加速」按鈕)
      expect(find.text('點擊加速'), findsOneWidget);
      // 驗證主頁選中節點膠囊已即時顯示美國節點
      expect(find.text('直連-美國'), findsWidgets);
    });
  });
}
