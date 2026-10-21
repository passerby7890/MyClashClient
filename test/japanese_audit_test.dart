// test/japanese_audit_test.dart
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flclash_v2board_client/core/i18n/i18n_service.dart';
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

  const outputDir = 'docs/audit_windows/japanese_verification';

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

  setUp(() async {
    WindowsProxyService.mockIsAdmin = true;
    configService = AppConfigService();
    dioClient = DioClient(configService: configService);
    storage = SecureStorageService();
    await I18nService.instance.init(storageService: storage);
    await I18nService.instance.setLanguage(AppLanguage.ja);

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
    
    final nodes = [
      const NodeModel(
        id: '1',
        name: '🇯🇵 日本 01 · 4K 極速',
        flagEmoji: '🇯🇵',
        protocol: 'trojan',
        latencyMs: 38,
        rawConfig: {'server': 'jp01.tianhe.net', 'port': 443},
      ),
      const NodeModel(
        id: '2',
        name: '🇭🇰 香港 01 · 專線直連',
        flagEmoji: '🇭🇰',
        protocol: 'ss',
        latencyMs: 28,
        rawConfig: {'server': 'hk01.tianhe.net', 'port': 443},
      ),
    ];
    subscriptionEngine.setNodesForTest(nodes);

    shopManager = ShopManager(dioClient: dioClient);
    shopManager.setPlansForTesting([
      PlanModel(
        id: 1,
        name: 'ベーシックプラン (Basic)',
        transferEnable: 100,
        monthPrice: 1900,
        quarterPrice: 5400,
        halfYearPrice: 10200,
        yearPrice: 19000,
        features: ['100GB 高速通信', '専用ノード接続', '全プラットフォーム対応'],
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
      print('  [SAVED JA VERIFICATION SCREENSHOT] -> ${file.path} (${image.width}x${image.height})');
    });
  }

  Widget buildDesktopWidget({required int initialNavIndex, required GlobalKey key}) {
    return AnimatedBuilder(
      animation: I18nService.instance,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: I18nService.instance.currentLocale,
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
      },
    );
  }

  testWidgets('Generate Japanese Verification Screenshots', (tester) async {
    tester.view.physicalSize = const Size(1260, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    await tester.binding.setSurfaceSize(const Size(1260, 820));

    final views = [
      {'index': 0, 'file': '01_ja_home.png', 'name': '加速ホーム (Home)'},
      {'index': 3, 'file': '02_ja_connections.png', 'name': '接続状況 (Connections)'},
      {'index': 1, 'file': '03_ja_store.png', 'name': 'プラン購入 (Store)'},
      {'index': 4, 'file': '04_ja_traffic.png', 'name': '通信量明細 (Traffic)'},
      {'index': 6, 'file': '05_ja_profile.png', 'name': 'マイページ (Profile)'},
      {'index': 7, 'file': '06_ja_settings.png', 'name': '詳細設定 (Settings)'},
    ];

    for (final v in views) {
      final key = GlobalKey();
      await tester.pumpWidget(buildDesktopWidget(initialNavIndex: v['index'] as int, key: key));
      await tester.pump(const Duration(milliseconds: 200));
      await captureWidget(tester, key, v['file'] as String);
    }
  });
}
