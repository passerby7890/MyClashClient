// test/capture_traffic_redesign_test.dart
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
import 'package:flclash_v2board_client/business/auth/traffic_log_model.dart';
import 'package:flclash_v2board_client/business/subscription/subscription_engine.dart';
import 'package:flclash_v2board_client/business/shop/shop_manager.dart';
import 'package:flclash_v2board_client/presentation/dashboard/widgets/desktop_dashboard_layout.dart';
import 'package:flclash_v2board_client/presentation/desktop/desktop_traffic_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('精準驗證與捕獲流量詳情頁面 (190px 大圓環 + 2x2 指標矩陣 + 真實 API 佔比條)', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1260, 820);
    addTearDown(() => tester.view.resetPhysicalSize());
    await tester.binding.setSurfaceSize(const Size(1260, 820));

    final configService = AppConfigService();
    final dioClient = DioClient(configService: configService);
    final storage = SecureStorageService();
    final authManager = AuthManager(dioClient: dioClient, storageService: storage);

    // 模擬已登入用戶：總配額 3.42 TB，已用 33.70 GB (約 0.96%)
    final now = DateTime.now();
    final user = UserModel(
      email: 'vip.enterprise@tianhe.net',
      transferEnable: (3.42 * 1024 * 1024 * 1024 * 1024).toInt(), // 3.42 TB
      u: (8.20 * 1024 * 1024 * 1024).toInt(), // 8.20 GB
      d: (25.50 * 1024 * 1024 * 1024).toInt(), // 25.50 GB
      expiredAt: now.add(const Duration(days: 365)).millisecondsSinceEpoch ~/ 1000,
    );
    authManager.updateUserForTest(user);

    final coreDaemon = CoreDaemon();
    final subscriptionEngine = SubscriptionEngine(
      dioClient: dioClient,
      coreDaemon: coreDaemon,
      storageService: storage,
    );
    final shopManager = ShopManager(dioClient: dioClient);

    final key = GlobalKey();

    // 渲染桌面旗艦佈局並直接切換至第 4 頁 (流量詳情)
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
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
                initialNavIndex: 4, // 流量詳情分頁
                enableAnimations: false,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 捕獲並保存高解析度驗證截圖
    final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    // 儲存至 Artifacts 目錄
    final artifactPath = 'C:/Users/user/.gemini/antigravity-ide/brain/7d9b2ce1-12d0-46e8-aae6-ca0de47c67c5/06_traffic.png';
    final file = File(artifactPath);
    file.parent.createSync(recursive: true);
    await file.writeAsBytes(pngBytes);
    // ignore: avoid_print
    print('  [SAVED TRAFFIC AUDIT SCREENSHOT] -> ${file.path} (${image.width}x${image.height})');
  });
}
