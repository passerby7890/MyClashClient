// test/export_desktop_screenshots.dart
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
import 'package:flclash_v2board_client/business/shop/plan_model.dart';
import 'package:flclash_v2board_client/infrastructure/core_daemon/windows_proxy_service.dart';
import 'package:flclash_v2board_client/presentation/dashboard/widgets/desktop_dashboard_layout.dart';
import 'package:flclash_v2board_client/presentation/widgets/country_flag_badge.dart';

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
    const kaiuPath = r'C:\Windows\Fonts\kaiu.ttf';
    final segoeBytes = File(segoePath).existsSync() ? File(segoePath).readAsBytesSync() : null;
    final kaiuBytes = File(kaiuPath).existsSync() ? File(kaiuPath).readAsBytesSync() : null;

    for (final family in ['Roboto', 'sans-serif', 'Segoe UI', 'DFKai-SB', '.SF Pro Text', '.SF UI Text']) {
      final fontLoader = FontLoader(family);
      if (segoeBytes != null) {
        fontLoader.addFont(Future.value(ByteData.view(segoeBytes.buffer)));
      }
      if (kaiuBytes != null) {
        fontLoader.addFont(Future.value(ByteData.view(kaiuBytes.buffer)));
      }
      await fontLoader.load();
    }
  } catch (_) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DioClient dioClient;
  late SecureStorageService storage;
  late AuthManager authManager;
  late AppConfigService configService;
  late CoreDaemon coreDaemon;
  late SubscriptionEngine subscriptionEngine;
  late ShopManager shopManager;

  setUpAll(() async {
    await _loadRealFonts();
  });

  setUp(() async {
    WindowsProxyService.mockIsAdmin = true;
    configService = AppConfigService();
    dioClient = DioClient(configService: configService);
    storage = SecureStorageService();
    authManager = AuthManager(dioClient: dioClient, storageService: storage);
    coreDaemon = CoreDaemon();
    subscriptionEngine = SubscriptionEngine(
      dioClient: dioClient,
      coreDaemon: coreDaemon,
      storageService: storage,
      isTestMode: true,
    );
    shopManager = ShopManager(dioClient: dioClient);

    final testUser = UserModel(
      email: 'audit_user@tianhe.net',
      transferEnable: 1024 * 1024 * 1024 * 100,
      u: 1024 * 1024 * 1024 * 10,
      d: 1024 * 1024 * 1024 * 15,
      expiredAt: DateTime.now().add(const Duration(days: 90)).millisecondsSinceEpoch ~/ 1000,
    );
    authManager.updateUserForTest(testUser);

    final now = DateTime.now();
    authManager.setTrafficLogsForTest([
      TrafficLogModel(
        u: 1024 * 1024 * 850,
        d: 1024 * 1024 * 1024 * 4 + 1024 * 1024 * 200,
        recordAt: now.millisecondsSinceEpoch ~/ 1000,
        serverRate: 1.0,
      ),
      TrafficLogModel(
        u: 1024 * 1024 * 620,
        d: 1024 * 1024 * 1024 * 6 + 1024 * 1024 * 500,
        recordAt: now.subtract(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000,
        serverRate: 1.25,
      ),
      TrafficLogModel(
        u: 1024 * 1024 * 410,
        d: 1024 * 1024 * 1024 * 3 + 1024 * 1024 * 100,
        recordAt: now.subtract(const Duration(days: 2)).millisecondsSinceEpoch ~/ 1000,
        serverRate: 1.0,
      ),
      TrafficLogModel(
        u: 1024 * 1024 * 950,
        d: 1024 * 1024 * 1024 * 8 + 1024 * 1024 * 400,
        recordAt: now.subtract(const Duration(days: 3)).millisecondsSinceEpoch ~/ 1000,
        serverRate: 1.5,
      ),
      TrafficLogModel(
        u: 1024 * 1024 * 320,
        d: 1024 * 1024 * 1024 * 2 + 1024 * 1024 * 800,
        recordAt: now.subtract(const Duration(days: 4)).millisecondsSinceEpoch ~/ 1000,
        serverRate: 1.0,
      ),
      TrafficLogModel(
        u: 1024 * 1024 * 1200,
        d: 1024 * 1024 * 1024 * 11 + 1024 * 1024 * 300,
        recordAt: now.subtract(const Duration(days: 5)).millisecondsSinceEpoch ~/ 1000,
        serverRate: 2.0,
      ),
    ]);

    const sampleYaml = '''
proxies:
  - name: "🇭🇰 香港 01 [VIP 專線]"
    type: shadowsocks
    server: 1.1.1.1
    port: 443
    cipher: aes-128-gcm
    password: test
  - name: "🇯🇵 日本 東京 02 [原生解鎖]"
    type: shadowsocks
    server: 2.2.2.2
    port: 443
    cipher: aes-128-gcm
    password: test
  - name: "🇺🇸 美國 洛杉磯 03 [高畫質串流]"
    type: shadowsocks
    server: 3.3.3.3
    port: 443
    cipher: aes-128-gcm
    password: test
  - name: "🇸🇬 新加坡 04 [極速直連]"
    type: shadowsocks
    server: 4.4.4.4
    port: 443
    cipher: aes-128-gcm
    password: test
  - name: "🇹🇼 台灣 台北 05 [低延遲]"
    type: shadowsocks
    server: 5.5.5.5
    port: 443
    cipher: aes-128-gcm
    password: test
  - name: "🇰🇷 韓國 首爾 06 [電競低延遲]"
    type: shadowsocks
    server: 6.6.6.6
    port: 443
    cipher: aes-128-gcm
    password: test
''';
    await storage.saveEncryptedNodes(sampleYaml);
    await subscriptionEngine.restoreFromVault();

    shopManager.setPlansForTesting([
      PlanModel(
        id: 1,
        name: 'VIP 基礎版 (天河旗艦)',
        transferEnable: 100,
        monthPrice: 1500,
        features: ['高速節點', '4K 秒開', '解鎖 Netflix/Disney+'],
      ),
      PlanModel(
        id: 2,
        name: 'Pro 專業版 (尊榮旗艦)',
        transferEnable: 300,
        monthPrice: 3500,
        features: ['極速專線', '8K 流暢', '專屬客服支援'],
      ),
      PlanModel(
        id: 3,
        name: 'Ultimate 旗艦版 (王者尊爵)',
        transferEnable: 1000,
        monthPrice: 8800,
        features: ['全網直連', '極致低延遲', '1對1專屬技術顧問'],
      ),
      PlanModel(
        id: 4,
        name: 'Gaming 遊戲專線 (電競低延遲)',
        transferEnable: 500,
        monthPrice: 4800,
        features: ['專屬遊戲加速', '雙程低延遲', '防封鎖'],
      ),
    ]);
  });

  Future<void> runCapture(
    WidgetTester tester, {
    required int navIndex,
    Widget? overlay,
    required String outputPath,
  }) async {
    tester.view.physicalSize = const Size(1120, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    await tester.binding.setSurfaceSize(const Size(1120, 740));

    final rootKey = GlobalKey();
    final app = MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        textTheme: const TextTheme().apply(
          fontFamily: 'DFKai-SB',
          fontFamilyFallback: ['DFKai-SB', 'Roboto', 'Segoe UI', 'Arial'],
        ),
      ),
      home: Scaffold(
        backgroundColor: const Color(0xFF070A11),
        body: RepaintBoundary(
          key: rootKey,
          child: Stack(
            children: [
              DesktopDashboardLayout(
                authManager: authManager,
                configService: configService,
                coreDaemon: coreDaemon,
                subscriptionEngine: subscriptionEngine,
                shopManager: shopManager,
                onToggleConnection: () {},
                onLogout: () {},
                isSyncing: false,
                initialNavIndex: navIndex,
                enableAnimations: false,
              ),
              if (overlay != null) overlay,
            ],
          ),
        ),
      ),
    );

    await tester.pumpWidget(app);
    await tester.pump(const Duration(milliseconds: 300));

    final boundary = rootKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(outputPath);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(byteData!.buffer.asUint8List());
    print('  [CAPTURED TEST FILE] -> $outputPath');
  }

  Widget buildLangDialog() {
    return Center(
      child: Container(
        width: 380,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1728),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF1E293B), width: 1.2),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 24)],
        ),
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                children: [
                  Icon(Icons.translate_rounded, color: Color(0xFF00E5FF), size: 20),
                  SizedBox(width: 8),
                  Text('選擇介面語言 (Language)', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 14),
              ListTile(
                leading: const CountryFlagBadge(isoCode: 'TW', size: Size(22, 15)),
                title: const Text('🇹🇼 繁體中文', style: TextStyle(color: Colors.white, fontSize: 13.5)),
                trailing: const Icon(Icons.check_rounded, color: Color(0xFF00E5FF)),
              ),
              const Divider(color: Color(0xFF1E293B), height: 1),
              ListTile(
                leading: const CountryFlagBadge(isoCode: 'CN', size: Size(22, 15)),
                title: const Text('🇨🇳 简体中文', style: TextStyle(color: Colors.white, fontSize: 13.5)),
              ),
              const Divider(color: Color(0xFF1E293B), height: 1),
              ListTile(
                leading: const CountryFlagBadge(isoCode: 'US', size: Size(22, 15)),
                title: const Text('🇺🇸 English', style: TextStyle(color: Colors.white, fontSize: 13.5)),
              ),
              const Divider(color: Color(0xFF1E293B), height: 1),
              ListTile(
                leading: const CountryFlagBadge(isoCode: 'JP', size: Size(22, 15)),
                title: const Text('🇯🇵 日本語', style: TextStyle(color: Colors.white, fontSize: 13.5)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildDiagDialog() {
    return Center(
      child: Container(
        width: 440,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1728),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF1E293B), width: 1.2),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 24)],
        ),
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.network_check_rounded, color: Color(0xFF00E5FF)),
                  SizedBox(width: 8),
                  Text('網路連線診斷', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              _buildDiagRow('本地網路介面', '已連接 (192.168.x.x)', const Color(0xFF10B981)),
              _buildDiagRow('系統代理服務', '127.0.0.1:7890 待機 (連線後接管)', const Color(0xFF0EA5E9)),
              _buildDiagRow('Mihomo 內核控制器', '127.0.0.1:9090 就緒', const Color(0xFF10B981)),
              _buildDiagRow('DoH 動態加密隧道', 'Cloudflare + Google 雙通道', const Color(0xFF00E5FF)),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('01 Home', (tester) async {
    final roundDir = Platform.environment['SCREENSHOT_ROUND_DIR'] ?? 'docs/audit_windows/round_1';
    await runCapture(tester, navIndex: 0, outputPath: '$roundDir/01_home.png');
  });

  testWidgets('02 Language Selector', (tester) async {
    final roundDir = Platform.environment['SCREENSHOT_ROUND_DIR'] ?? 'docs/audit_windows/round_1';
    await runCapture(tester, navIndex: 0, overlay: buildLangDialog(), outputPath: '$roundDir/02_language_selector.png');
  });

  testWidgets('03 Store', (tester) async {
    final roundDir = Platform.environment['SCREENSHOT_ROUND_DIR'] ?? 'docs/audit_windows/round_1';
    await runCapture(tester, navIndex: 1, outputPath: '$roundDir/03_store.png');
  });

  testWidgets('04 Nodes', (tester) async {
    final roundDir = Platform.environment['SCREENSHOT_ROUND_DIR'] ?? 'docs/audit_windows/round_1';
    await runCapture(tester, navIndex: 2, outputPath: '$roundDir/04_nodes.png');
  });

  testWidgets('05 Connections', (tester) async {
    final roundDir = Platform.environment['SCREENSHOT_ROUND_DIR'] ?? 'docs/audit_windows/round_1';
    await runCapture(tester, navIndex: 3, outputPath: '$roundDir/05_connections.png');
  });

  testWidgets('06 Traffic', (tester) async {
    final roundDir = Platform.environment['SCREENSHOT_ROUND_DIR'] ?? 'docs/audit_windows/round_1';
    await runCapture(tester, navIndex: 4, outputPath: '$roundDir/06_traffic.png');
  });

  testWidgets('07 Affiliate', (tester) async {
    final roundDir = Platform.environment['SCREENSHOT_ROUND_DIR'] ?? 'docs/audit_windows/round_1';
    await runCapture(tester, navIndex: 5, outputPath: '$roundDir/07_affiliate.png');
  });

  testWidgets('08 Profile', (tester) async {
    final roundDir = Platform.environment['SCREENSHOT_ROUND_DIR'] ?? 'docs/audit_windows/round_1';
    await runCapture(tester, navIndex: 6, outputPath: '$roundDir/08_profile.png');
  });

  testWidgets('09 Settings', (tester) async {
    final roundDir = Platform.environment['SCREENSHOT_ROUND_DIR'] ?? 'docs/audit_windows/round_1';
    await runCapture(tester, navIndex: 7, outputPath: '$roundDir/09_settings.png');
  });

  testWidgets('10 Diagnostics', (tester) async {
    final roundDir = Platform.environment['SCREENSHOT_ROUND_DIR'] ?? 'docs/audit_windows/round_1';
    await runCapture(tester, navIndex: 0, overlay: buildDiagDialog(), outputPath: '$roundDir/10_diagnostics.png');
  });
}

Widget _buildDiagRow(String label, String value, Color color) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        Text(value, style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.bold)),
      ],
    ),
  );
}
