// test/desktop_visual_golden_test.dart

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flclash_v2board_client/business/auth/auth_manager.dart';
import 'package:flclash_v2board_client/business/auth/user_model.dart';
import 'package:flclash_v2board_client/business/shop/plan_model.dart';
import 'package:flclash_v2board_client/business/shop/shop_manager.dart';
import 'package:flclash_v2board_client/business/subscription/node_model.dart';
import 'package:flclash_v2board_client/business/subscription/subscription_engine.dart';
import 'package:flclash_v2board_client/core/i18n/i18n_service.dart';
import 'package:flclash_v2board_client/core/network/dio_client.dart';
import 'package:flclash_v2board_client/core/storage/secure_storage_service.dart';
import 'package:flclash_v2board_client/infrastructure/config/app_config_service.dart';
import 'package:flclash_v2board_client/infrastructure/core_daemon/core_daemon.dart';
import 'package:flclash_v2board_client/infrastructure/core_daemon/core_state.dart';
import 'package:flclash_v2board_client/infrastructure/core_daemon/traffic_stats.dart';
import 'package:flclash_v2board_client/infrastructure/core_daemon/windows_proxy_service.dart';
import 'package:flclash_v2board_client/presentation/desktop/desktop_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final goldensDir = Directory('test/goldens');

  late DioClient dioClient;
  late SecureStorageService storage;
  late AuthManager authManager;
  late AppConfigService configService;
  late CoreDaemon coreDaemon;
  late SubscriptionEngine subscriptionEngine;
  late ShopManager shopManager;

  setUpAll(() async {
    goldensDir.createSync(recursive: true);
  });

  setUp(() {
    WindowsProxyService.mockIsAdmin = true;
    configService = AppConfigService();
    dioClient = DioClient(configService: configService);
    storage = SecureStorageService();
    authManager = AuthManager(dioClient: dioClient, storageService: storage);

    final user = UserModel(
      email: 'nick0425@gmail.com',
      transferEnable: 1024 * 1024 * 1024 * 500, // 500 GB
      u: 1024 * 1024 * 1024 * 25, // 25 GB
      d: 1024 * 1024 * 1024 * 95, // 95 GB
      expiredAt: DateTime.now().add(const Duration(days: 90)).millisecondsSinceEpoch ~/ 1000,
      planId: 2,
      planName: '旗艦極速版 (Pro VIP)',
      commissionBalance: 12850,
    );
    authManager.updateUserForTest(user);

    coreDaemon = CoreDaemon();
    coreDaemon.setStateForTest(
      const CoreState(
        status: CoreStatus.connected,
        activeNodeName: '🇭🇰 香港 01 · 專線直連',
      ),
      const TrafficStats(
        upSpeed: 1024 * 650,
        downSpeed: 1024 * 1024 * 6,
        totalUp: 1024 * 1024 * 120,
        totalDown: 1024 * 1024 * 900,
      ),
    );

    subscriptionEngine = SubscriptionEngine(
      dioClient: dioClient,
      coreDaemon: coreDaemon,
      storageService: storage,
    );

    final nodes = [
      const NodeModel(
        id: '1',
        name: '🇭🇰 香港 01 · 專線直連',
        flagEmoji: '🇭🇰',
        protocol: 'ss',
        latencyMs: 28,
        rawConfig: {'server': 'hk01.tianhe.net', 'port': 443},
      ),
      const NodeModel(
        id: '2',
        name: '🇯🇵 日本 01 · 4K 極速',
        flagEmoji: '🇯🇵',
        protocol: 'trojan',
        latencyMs: 42,
        rawConfig: {'server': 'jp01.tianhe.net', 'port': 443},
      ),
      const NodeModel(
        id: '3',
        name: '🇸🇬 新加坡 01 · 遊戲加速',
        flagEmoji: '🇸🇬',
        protocol: 'vmess',
        latencyMs: 55,
        rawConfig: {'server': 'sg01.tianhe.net', 'port': 443},
      ),
      const NodeModel(
        id: '4',
        name: '🇺🇸 美國 01 · 串流解鎖',
        flagEmoji: '🇺🇸',
        protocol: 'ss',
        latencyMs: 140,
        rawConfig: {'server': 'us01.tianhe.net', 'port': 443},
      ),
      const NodeModel(
        id: '5',
        name: '🇹🇼 台灣 01 · 家用寬頻',
        flagEmoji: '🇹🇼',
        protocol: 'trojan',
        latencyMs: 32,
        rawConfig: {'server': 'tw01.tianhe.net', 'port': 443},
      ),
      const NodeModel(
        id: '6',
        name: '🇩🇪 德國 01 · 歐洲節點',
        flagEmoji: '🇩🇪',
        protocol: 'ss',
        latencyMs: 185,
        rawConfig: {'server': 'de01.tianhe.net', 'port': 443},
      ),
    ];
    subscriptionEngine.setNodesForTest(nodes);
    subscriptionEngine.selectNode(nodes[0]);

    shopManager = ShopManager(dioClient: dioClient);
    shopManager.setPlansForTesting([
      PlanModel(
        id: 1,
        name: '入門輕量版 (Basic)',
        transferEnable: 100,
        monthPrice: 1900,
        quarterPrice: 5400,
        halfYearPrice: 10200,
        yearPrice: 19000,
        features: ['100GB 高速流量', '基礎專線節點', '全平台支援', '不限設備數量'],
        show: true,
      ),
      PlanModel(
        id: 2,
        name: '旗艦極速版 (Pro VIP)',
        transferEnable: 300,
        monthPrice: 3800,
        quarterPrice: 10800,
        halfYearPrice: 20400,
        yearPrice: 38000,
        features: ['300GB 專線直連', 'IEPL 國際專線', '4K/8K 串流秒開', '獨享低延遲通道'],
        show: true,
      ),
      PlanModel(
        id: 3,
        name: '尊榮企業版 (Enterprise)',
        transferEnable: 1000,
        monthPrice: 9800,
        quarterPrice: 27900,
        yearPrice: 98000,
        features: ['1000GB 海量傳輸', '全球 BGP 專線節點', '專屬客服通道', '7x24 SLA 保障'],
        show: true,
      ),
      PlanModel(
        id: 4,
        name: '不限時單次包 (One-Time)',
        transferEnable: 200,
        onetimePrice: 6800,
        features: ['200GB 長期有效', '永不過期', '全節點解鎖', '適合備用備援'],
        show: true,
      ),
    ]);
  });

  Future<void> savePng(WidgetTester tester, GlobalKey key, String filename) async {
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final pngBytes = byteData.buffer.asUint8List();
      final file = File('test/goldens/$filename');
      file.parent.createSync(recursive: true);
      await file.writeAsBytes(pngBytes);
      // ignore: avoid_print
      print('[GOLDEN SAVED] -> ${file.path} (${image.width}x${image.height})');
    });
  }

  Widget createShellWidget({required int initialNavIndex, required GlobalKey key}) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF070A11),
        body: RepaintBoundary(
          key: key,
          child: SizedBox(
            width: 1200,
            height: 780,
            child: DesktopShell(
              authManager: authManager,
              configService: configService,
              coreDaemon: coreDaemon,
              subscriptionEngine: subscriptionEngine,
              shopManager: shopManager,
              onToggleConnection: () {},
              onLogout: () {},
              isSyncing: false,
              initialNavIndex: initialNavIndex,
              enableAnimations: false,
            ),
          ),
        ),
      ),
    );
  }

  final tabNames = [
    '01_home',
    '02_store',
    '03_nodes',
    '04_connections',
    '05_traffic',
    '06_affiliate',
    '07_profile',
    '08_settings',
  ];

  testWidgets('Golden Snapshot: All 8 Tabs in zh_TW (1200x780 Zero Overflow)', (tester) async {
    tester.view.physicalSize = const Size(1200, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await I18nService.instance.setLanguage(AppLanguage.zhTW);

    for (int i = 0; i < tabNames.length; i++) {
      final key = GlobalKey();
      await tester.pumpWidget(createShellWidget(initialNavIndex: i, key: key));
      await tester.pumpAndSettle();

      // Save PNG directly to test/goldens/
      await savePng(tester, key, '${tabNames[i]}_zh_TW.png');

      // Golden comparison
      await expectLater(
        find.byType(DesktopShell),
        matchesGoldenFile('goldens/${tabNames[i]}_zh_TW.png'),
      );
    }
  });

  testWidgets('Golden Snapshot: 4-Language Localization on Home & Connections', (tester) async {
    tester.view.physicalSize = const Size(1200, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final languages = [
      AppLanguage.zhTW,
      AppLanguage.zhCN,
      AppLanguage.en,
      AppLanguage.ja,
    ];

    for (final lang in languages) {
      await I18nService.instance.setLanguage(lang);

      // Test Home Tab (0)
      final homeKey = GlobalKey();
      await tester.pumpWidget(createShellWidget(initialNavIndex: 0, key: homeKey));
      await tester.pumpAndSettle();
      await savePng(tester, homeKey, 'home_${lang.name}.png');
      await expectLater(
        find.byType(DesktopShell),
        matchesGoldenFile('goldens/home_${lang.name}.png'),
      );

      // Test Connections Tab (3)
      final connKey = GlobalKey();
      await tester.pumpWidget(createShellWidget(initialNavIndex: 3, key: connKey));
      await tester.pumpAndSettle();
      await savePng(tester, connKey, 'connections_${lang.name}.png');
      await expectLater(
        find.byType(DesktopShell),
        matchesGoldenFile('goldens/connections_${lang.name}.png'),
      );
    }
  });
}
