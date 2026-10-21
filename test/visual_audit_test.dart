// test/visual_audit_test.dart
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flclash_v2board_client/core/network/dio_client.dart';
import 'package:flclash_v2board_client/core/storage/secure_storage_service.dart';
import 'package:flclash_v2board_client/infrastructure/config/app_config_service.dart';
import 'package:flclash_v2board_client/infrastructure/core_daemon/core_daemon.dart';
import 'package:flclash_v2board_client/business/auth/auth_manager.dart';
import 'package:flclash_v2board_client/business/auth/user_model.dart';
import 'package:flclash_v2board_client/business/subscription/node_model.dart';
import 'package:flclash_v2board_client/business/subscription/subscription_engine.dart';
import 'package:flclash_v2board_client/business/shop/shop_manager.dart';
import 'package:flclash_v2board_client/business/shop/plan_model.dart';
import 'package:flclash_v2board_client/infrastructure/core_daemon/windows_proxy_service.dart';
import 'package:flclash_v2board_client/presentation/dashboard/widgets/desktop_dashboard_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final round = Platform.environment['AUDIT_ROUND'] ?? '1';
  final outputDir = 'docs/audit_windows/round_$round';

  late DioClient dioClient;
  late SecureStorageService storage;
  late AuthManager authManager;
  late AppConfigService configService;
  late CoreDaemon coreDaemon;
  late SubscriptionEngine subscriptionEngine;
  late ShopManager shopManager;

  setUpAll(() async {
    Directory(outputDir).createSync(recursive: true);
  });

  setUp(() {
    WindowsProxyService.mockIsAdmin = true;
    configService = AppConfigService();
    dioClient = DioClient(configService: configService);
    storage = SecureStorageService();
    authManager = AuthManager(dioClient: dioClient, storageService: storage);
    
    // Inject mock VIP user with quota
    final user = UserModel(
      email: 'vip.member@tianhe.net',
      transferEnable: 1024 * 1024 * 1024 * 500, // 500 GB
      u: 1024 * 1024 * 1024 * 25, // 25 GB
      d: 1024 * 1024 * 1024 * 95, // 95 GB
      expiredAt: DateTime.now().add(const Duration(days: 90)).millisecondsSinceEpoch ~/ 1000,
    );
    authManager.updateUserForTest(user);

    coreDaemon = CoreDaemon();
    subscriptionEngine = SubscriptionEngine(
      dioClient: dioClient,
      coreDaemon: coreDaemon,
      storageService: storage,
    );
    
    // Inject mock nodes
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
    ];
    subscriptionEngine.setNodesForTest(nodes);

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

  Future<void> captureWidget(WidgetTester tester, GlobalKey key, String filename) async {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();
      final file = File('$outputDir/$filename');
      file.parent.createSync(recursive: true);
      await file.writeAsBytes(pngBytes);
      // ignore: avoid_print
      print('  [SAVED AUDIT SCREENSHOT] -> ${file.path} (${image.width}x${image.height})');
    });
  }

  Widget buildDesktopWidget({required int initialNavIndex, required GlobalKey key}) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF070B13),
        body: RepaintBoundary(
          key: key,
          child: SizedBox(
            width: 1260,
            height: 820,
            child: DesktopDashboardLayout(
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

  testWidgets('Generate 10 Desktop Views Audit Screenshots', (tester) async {
    tester.view.physicalSize = const Size(1260, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    await tester.binding.setSurfaceSize(const Size(1260, 820));

    final views = [
      {'index': 0, 'file': '01_home.png', 'name': '加速主頁'},
      {'index': 1, 'file': '03_store.png', 'name': '購買套餐'},
      {'index': 2, 'file': '04_nodes.png', 'name': '節點狀態'},
      {'index': 3, 'file': '05_connections.png', 'name': '實時連接'},
      {'index': 4, 'file': '06_traffic.png', 'name': '流量詳情'},
      {'index': 5, 'file': '07_affiliate.png', 'name': '邀請推廣'},
      {'index': 6, 'file': '08_profile.png', 'name': '個人中心'},
      {'index': 7, 'file': '09_settings.png', 'name': '高級設置'},
    ];

    for (final v in views) {
      final key = GlobalKey();
      await tester.pumpWidget(buildDesktopWidget(initialNavIndex: v['index'] as int, key: key));
      await tester.pump(const Duration(milliseconds: 200));
      await captureWidget(tester, key, v['file'] as String);
    }

    // 2. 語言切換彈窗截圖 (02_language_selector.png)
    final langKey = GlobalKey();
    await tester.pumpWidget(buildDesktopWidget(initialNavIndex: 0, key: langKey));
    await tester.pump(const Duration(milliseconds: 200));
    final langBtnFinder = find.byIcon(Icons.translate_rounded);
    if (langBtnFinder.evaluate().isNotEmpty) {
      await tester.tap(langBtnFinder.first);
      await tester.pump(const Duration(milliseconds: 300));
    }
    await captureWidget(tester, langKey, '02_language_selector.png');

    // 10. 網路診斷彈窗截圖 (10_diagnostics.png)
    final diagKey = GlobalKey();
    await tester.pumpWidget(buildDesktopWidget(initialNavIndex: 0, key: diagKey));
    await tester.pump(const Duration(milliseconds: 200));
    final diagBtnFinder = find.byIcon(Icons.network_check_rounded);
    if (diagBtnFinder.evaluate().isNotEmpty) {
      await tester.tap(diagBtnFinder.first);
      await tester.pump(const Duration(milliseconds: 300));
    }
    await captureWidget(tester, diagKey, '10_diagnostics.png');
  });
}
