// test/capture_home_and_traffic_verification_test.dart
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flclash_v2board_client/core/network/dio_client.dart';
import 'package:flclash_v2board_client/core/storage/secure_storage_service.dart';
import 'package:flclash_v2board_client/infrastructure/config/app_config_service.dart';
import 'package:flclash_v2board_client/infrastructure/core_daemon/core_daemon.dart';
import 'package:flclash_v2board_client/business/auth/auth_manager.dart';
import 'package:flclash_v2board_client/business/auth/user_model.dart';
import 'package:flclash_v2board_client/business/auth/traffic_log_model.dart';
import 'package:flclash_v2board_client/business/subscription/subscription_engine.dart';
import 'package:flclash_v2board_client/business/shop/shop_manager.dart';
import 'package:flclash_v2board_client/presentation/desktop/desktop_shell.dart';

Future<void> _loadRealFonts() async {
  try {
    const iconFontPath = r'D:\tools\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf';
    if (File(iconFontPath).existsSync()) {
      final iconBytes = File(iconFontPath).readAsBytesSync();
      final iconLoader = FontLoader('MaterialIcons');
      iconLoader.addFont(Future.value(ByteData.view(iconBytes.buffer)));
      await iconLoader.load();
    }
  } catch (_) {}

  try {
    const segoePath = r'C:\Windows\Fonts\segoeui.ttf';
    const jhPath = r'C:\Windows\Fonts\msjh.ttc';
    final segoeBytes = File(segoePath).existsSync() ? File(segoePath).readAsBytesSync() : null;
    final jhBytes = File(jhPath).existsSync() ? File(jhPath).readAsBytesSync() : null;

    for (final family in ['Roboto', 'sans-serif', 'Segoe UI', 'Microsoft JhengHei', '.SF Pro Text']) {
      final fontLoader = FontLoader(family);
      if (segoeBytes != null) {
        fontLoader.addFont(Future.value(ByteData.view(segoeBytes.buffer)));
      }
      if (jhBytes != null) {
        fontLoader.addFont(Future.value(ByteData.view(jhBytes.buffer)));
      }
      await fontLoader.load();
    }
  } catch (_) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadRealFonts();
  });

  testWidgets('捕獲滿版撐開主頁與真實流量明細列表截圖', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 780);
    addTearDown(() => tester.view.resetPhysicalSize());
    await tester.binding.setSurfaceSize(const Size(1200, 780));

    final configService = AppConfigService();
    final dioClient = DioClient(configService: configService);
    final storage = SecureStorageService();
    final authManager = AuthManager(dioClient: dioClient, storageService: storage);

    final now = DateTime.now();
    final user = UserModel(
      email: 'vip.enterprise@tianhe.net',
      transferEnable: (3.42 * 1024 * 1024 * 1024 * 1024).toInt(), // 3.42 TB
      u: (12.40 * 1024 * 1024 * 1024).toInt(), // 12.40 GB
      d: (48.80 * 1024 * 1024 * 1024).toInt(), // 48.80 GB
      expiredAt: now.add(const Duration(days: 180)).millisecondsSinceEpoch ~/ 1000,
    );
    authManager.updateUserForTest(user);

    // 模擬已解析的真實 V2Board 每日流量記錄 (包含倍率、上下行)
    final sampleLogs = [
      TrafficLogModel(
        u: 1024 * 1024 * 850, // 850 MB
        d: 1024 * 1024 * 1024 * 4 + 1024 * 1024 * 200, // 4.20 GB
        recordAt: now.millisecondsSinceEpoch ~/ 1000,
        serverRate: 1.0,
      ),
      TrafficLogModel(
        u: 1024 * 1024 * 620, // 620 MB
        d: 1024 * 1024 * 1024 * 6 + 1024 * 1024 * 500, // 6.50 GB
        recordAt: now.subtract(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000,
        serverRate: 1.25,
      ),
      TrafficLogModel(
        u: 1024 * 1024 * 410, // 410 MB
        d: 1024 * 1024 * 1024 * 3 + 1024 * 1024 * 100, // 3.10 GB
        recordAt: now.subtract(const Duration(days: 2)).millisecondsSinceEpoch ~/ 1000,
        serverRate: 1.0,
      ),
      TrafficLogModel(
        u: 1024 * 1024 * 950, // 950 MB
        d: 1024 * 1024 * 1024 * 8 + 1024 * 1024 * 400, // 8.40 GB
        recordAt: now.subtract(const Duration(days: 3)).millisecondsSinceEpoch ~/ 1000,
        serverRate: 1.5,
      ),
      TrafficLogModel(
        u: 1024 * 1024 * 320, // 320 MB
        d: 1024 * 1024 * 1024 * 2 + 1024 * 1024 * 800, // 2.80 GB
        recordAt: now.subtract(const Duration(days: 4)).millisecondsSinceEpoch ~/ 1000,
        serverRate: 1.0,
      ),
      TrafficLogModel(
        u: 1024 * 1024 * 1200, // 1.2 GB
        d: 1024 * 1024 * 1024 * 11 + 1024 * 1024 * 300, // 11.3 GB
        recordAt: now.subtract(const Duration(days: 5)).millisecondsSinceEpoch ~/ 1000,
        serverRate: 2.0,
      ),
    ];
    authManager.setTrafficLogsForTest(sampleLogs);

    final coreDaemon = CoreDaemon();
    final subscriptionEngine = SubscriptionEngine(
      dioClient: dioClient,
      coreDaemon: coreDaemon,
      storageService: storage,
      isTestMode: true,
    );
    final shopManager = ShopManager(dioClient: dioClient);

    const sampleYaml = '''
proxies:
  - name: "🇯🇵 日本 東京 01 [VIP 專線]"
    type: shadowsocks
    server: 1.1.1.1
    port: 443
    cipher: aes-128-gcm
    password: test
''';
    await storage.saveEncryptedNodes(sampleYaml);
    await subscriptionEngine.restoreFromVault();

    final homeKey = GlobalKey();

    // 1. 渲染主頁 (Tab 0) 並驗證滿版撐開
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
        home: Scaffold(
          backgroundColor: const Color(0xFF070B13),
          body: RepaintBoundary(
            key: homeKey,
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
                enableAnimations: false,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 300));

    // 捕獲主頁截圖
    final homeBoundary = homeKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final homeImg = await homeBoundary.toImage(pixelRatio: 1.0);
    final homeBytes = await homeImg.toByteData(format: ui.ImageByteFormat.png);

    const artifactDir = r'C:\Users\Nick\.gemini\antigravity-ide\brain\3bbcde00-f4ee-4b76-9442-4e02582e6c20';
    final homeFile = File('$artifactDir/01_home_full_bleed.png');
    homeFile.parent.createSync(recursive: true);
    await homeFile.writeAsBytes(homeBytes!.buffer.asUint8List());
    print('  [SAVED HOME FULL BLEED] -> ${homeFile.path}');

    // 2. 切換至流量詳情 (Tab 4)
    // 流量詳情在左側選單的 Icon 是 Icons.query_stats_rounded (nav_traffic)
    final trafficNavFinder = find.byIcon(Icons.query_stats_rounded);
    if (trafficNavFinder.evaluate().isNotEmpty) {
      await tester.tap(trafficNavFinder.first);
      await tester.pump(const Duration(milliseconds: 300));
    }

    // 捕獲流量詳情截圖
    final trafficImg = await homeBoundary.toImage(pixelRatio: 1.0);
    final trafficBytes = await trafficImg.toByteData(format: ui.ImageByteFormat.png);
    final trafficFile = File('$artifactDir/06_traffic_real_data.png');
    await trafficFile.writeAsBytes(trafficBytes!.buffer.asUint8List());
    print('  [SAVED TRAFFIC REAL DATA] -> ${trafficFile.path}');
  });
}
