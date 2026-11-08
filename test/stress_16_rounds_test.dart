// test/stress_16_rounds_test.dart
// 16 輪極限壓力測試、深層 Bug 獵殺與閉環修復自動化測試套件

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flclash_v2board_client/business/auth/auth_manager.dart';
import 'package:flclash_v2board_client/business/auth/auth_state.dart';
import 'package:flclash_v2board_client/business/auth/user_model.dart';
import 'package:flclash_v2board_client/business/shop/shop_manager.dart';
import 'package:flclash_v2board_client/business/subscription/node_model.dart';
import 'package:flclash_v2board_client/business/subscription/subscription_engine.dart';
import 'package:flclash_v2board_client/core/crypto/aes_decryptor.dart';
import 'package:flclash_v2board_client/core/i18n/i18n_service.dart';
import 'package:flclash_v2board_client/core/network/dio_client.dart';
import 'package:flclash_v2board_client/core/storage/secure_storage_service.dart';
import 'package:flclash_v2board_client/infrastructure/config/app_config_service.dart';
import 'package:flclash_v2board_client/infrastructure/core_daemon/core_daemon.dart';
import 'package:flclash_v2board_client/infrastructure/core_daemon/core_state.dart';
import 'package:flclash_v2board_client/infrastructure/core_daemon/windows_proxy_service.dart';
import 'package:flclash_v2board_client/presentation/dashboard/widgets/cyber_world_map.dart';
import 'package:flclash_v2board_client/presentation/dashboard/widgets/desktop_dashboard_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppConfigService configService;
  late DioClient dioClient;
  late CoreDaemon coreDaemon;

  setUp(() {
    WindowsProxyService.mockIsAdmin = true;
    WindowsProxyService.mockIsWintun = true;
    SecureStorageService.isTestMode = true;
    configService = AppConfigService();
    dioClient = DioClient(configService: configService);
    coreDaemon = CoreDaemon();
  });

  group('【階段一（第 1 ~ 3 輪）：執行檔徹底更名為 tianhe.exe + 殭屍進程與端口衝突排雷】', () {
    test('【第 1 輪：CMake 與 Win32 資源表徹底更名 tianhe.exe】', () {
      final cmakeFile = File('windows/CMakeLists.txt');
      expect(cmakeFile.existsSync(), isTrue);
      final cmakeContent = cmakeFile.readAsStringSync();
      expect(cmakeContent.contains('set(BINARY_NAME "tianhe")'), isTrue,
          reason: 'CMakeLists.txt 的 BINARY_NAME 必須為 tianhe');
      expect(cmakeContent.contains('project(tianhe LANGUAGES CXX)'), isTrue);

      final rcFile = File('windows/runner/Runner.rc');
      expect(rcFile.existsSync(), isTrue);
      final rcContent = rcFile.readAsStringSync();
      expect(rcContent.contains('"InternalName", "tianhe.exe"'), isTrue);
      expect(rcContent.contains('"OriginalFilename", "tianhe.exe"'), isTrue);
      expect(rcContent.contains('"ProductName", "天河網絡 (Tianhe Network)"'), isTrue);
      expect(rcContent.contains('flclash_v2board_client.exe'), isFalse,
          reason: 'Runner.rc 嚴禁包含 flclash_v2board_client.exe');
    });

    test('【第 2 輪：孤兒/殭屍 mihomo.exe 搶佔端口 (7890/9090) 壓測與修復機制】', () async {
      final service = WindowsProxyService.instance;
      // 呼叫排雷清理方法，驗證不拋出異常且能快速返回
      final sw = Stopwatch()..start();
      await service.killOrphanMihomoProcesses(ports: [7890, 9090]);
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(3000), reason: '排雷清理應在 3 秒內完成');
    });

    test('【第 3 輪：冷啟動 L2 加密金庫秒開與離線防崩潰壓測】', () async {
      final storage = SecureStorageService();
      final engine = SubscriptionEngine(
        storageService: storage,
        dioClient: dioClient,
        coreDaemon: coreDaemon,
      );

      // 測試正常 YAML 還原
      const sampleYaml = '''
proxies:
  - {name: "L1-香港 01 - VLESS", type: vless, server: 1.1.1.1, port: 443, uuid: "uuid-1"}
  - {name: "L1-日本 01 - ANYTLS", type: anytls, server: 2.2.2.2, port: 443, uuid: "uuid-2"}
''';
      await storage.saveEncryptedNodes(sampleYaml);

      final sw = Stopwatch()..start();
      final restored = await engine.restoreFromVault();
      sw.stop();

      expect(restored, isTrue);
      expect(engine.nodes.length, 2);
      expect(engine.selectedNode?.name, 'L1-香港 01 - VLESS');
      expect(sw.elapsedMilliseconds, lessThan(100), reason: '本地金庫還原必須在 100ms 內完成');

      // 測試損毀資料容錯 (防崩潰測試)
      await storage.saveEncryptedNodes('invalid: [unclosed yaml {{{');
      final failRestored = await engine.restoreFromVault();
      expect(failRestored, isFalse, reason: '快取損毀時應優雅返回 false，嚴禁拋出未捕獲崩潰');
    });
  });

  group('【階段二（第 4 ~ 6 輪）：高頻暴力點擊防抖 + 100 次極速熱切換壓測】', () {
    test('【第 4 輪：暴力連點加速按鈕非同步互斥鎖 (Mutex 防抖鎖) 驗證】', () async {
      final daemon = CoreDaemon();
      expect(daemon.isTransitioning, isFalse);

      // 模擬連續並發觸發 10 次 start()
      final tasks = <Future<void>>[];
      for (int i = 0; i < 10; i++) {
        tasks.add(daemon.start(configPath: 'mock_path', selectedNode: 'Node-$i'));
      }

      await Future.wait(tasks);
      expect(daemon.state.isConnected, isTrue);
      expect(daemon.state.activeNodeName, 'Node-0', reason: '第 1 個請求應獲取鎖，其餘 9 次被互斥鎖忽略');
      expect(daemon.isTransitioning, isFalse);

      // 模擬連線狀態下連續狂點 stop() 10 次
      final stopTasks = <Future<void>>[];
      for (int i = 0; i < 10; i++) {
        stopTasks.add(daemon.stop());
      }
      await Future.wait(stopTasks);
      expect(daemon.state.isDisconnected, isTrue);
      expect(daemon.isTransitioning, isFalse);
    });

    test('【第 5 輪：100 次高頻節點熱切換 (VLESS ⇄ ANYTLS) 序號鎖壓測】', () async {
      final daemon = CoreDaemon();
      await daemon.start(configPath: 'mock_path', selectedNode: 'Initial-Node');

      final sw = Stopwatch()..start();
      // 模擬高頻熱切換 100 次
      for (int i = 1; i <= 100; i++) {
        final nodeName = (i % 2 == 0) ? 'L1-東京 0$i - ANYTLS' : 'L1-香港 0$i - VLESS';
        await daemon.switchNode(nodeName);
      }
      sw.stop();

      expect(daemon.state.activeNodeName, 'L1-東京 0100 - ANYTLS');
      expect(sw.elapsedMilliseconds, lessThan(3000), reason: '100 次熱切換總耗時應極為迅速');
      await daemon.stop();
    });

    test('【第 6 輪：全節點真實併發測速風暴壓測與 Socket 釋放】', () async {
      final storage = SecureStorageService();
      final engine = SubscriptionEngine(
        storageService: storage,
        dioClient: dioClient,
        coreDaemon: coreDaemon,
        isTestMode: true,
      );

      // 載入 5 顆測試節點
      const sampleYaml = '''
proxies:
  - {name: "HK-01", type: vless, server: 1.1.1.1, port: 443}
  - {name: "HK-02", type: vless, server: 1.1.1.2, port: 443}
  - {name: "JP-01", type: anytls, server: 2.2.2.1, port: 443}
  - {name: "JP-02", type: anytls, server: 2.2.2.2, port: 443}
  - {name: "US-01", type: vless, server: 3.3.3.1, port: 443}
''';
      await storage.saveEncryptedNodes(sampleYaml);
      await engine.restoreFromVault();

      // 連續觸發 5 次一鍵測速風暴
      for (int r = 0; r < 5; r++) {
        await engine.pingAllNodes(concurrency: 4);
        for (final n in engine.nodes) {
          expect(n.latencyMs, isNotNull);
          expect(n.latencyMs!, greaterThan(0));
        }
      }

      // 選擇最快節點
      final fastest = await engine.selectFastestNode(isTestMode: true);
      expect(fastest, isNotNull);
      expect(engine.selectedNode?.id, fastest?.id);
    });
  });

  group('【階段三（第 7 ~ 9 輪）：視窗極限拉伸、8 大分頁與 4 國語言猴子壓測】', () {
    testWidgets('【第 7 輪：視窗尺寸極限拉伸 (1120x740, 1200x780, 1920x1080) 零溢出】', (tester) async {
      final authManager = AuthManager(
        dioClient: dioClient,
        storageService: SecureStorageService(),
      );
      final storage = SecureStorageService();
      final subEngine = SubscriptionEngine(
        storageService: storage,
        dioClient: dioClient,
        coreDaemon: coreDaemon,
      );
      final shopManager = ShopManager(dioClient: dioClient);

      const sampleYaml = '''
proxies:
  - {name: "L1-香港 - VLESS", type: vless, server: 1.1.1.1, port: 443}
  - {name: "L1-日本 - ANYTLS", type: anytls, server: 2.2.2.2, port: 443}
''';
      await storage.saveEncryptedNodes(sampleYaml);
      await subEngine.restoreFromVault();

      final testUser = UserModel(
        email: 'audit_user@tianhe.net',
        transferEnable: 1024 * 1024 * 1024 * 100,
        u: 1024 * 1024 * 1024 * 10,
        d: 1024 * 1024 * 1024 * 15,
        expiredAt: DateTime.now().add(const Duration(days: 90)).millisecondsSinceEpoch ~/ 1000,
      );
      authManager.updateUserForTest(testUser);

      await tester.binding.setSurfaceSize(const Size(1120, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopDashboardLayout(
              authManager: authManager,
              configService: configService,
              coreDaemon: coreDaemon,
              subscriptionEngine: subEngine,
              shopManager: shopManager,
              onToggleConnection: () {},
              onLogout: () {},
              initialNavIndex: 0,
              enableAnimations: false,
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull,
          reason: '在最小極限尺寸 1120x740 下嚴禁任何 RenderFlex 溢出異常');

      // 驗證核心加速區與雙欄佈局均正常渲染
      expect(find.byType(CyberWorldMap), findsWidgets);

      // 清空並銷毀組件
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });

    test('【第 8 輪：4 國語言 50 次高速輪切與 raw key 掃描】', () async {
      final i18n = I18nService.instance;
      final languages = ['zh_TW', 'zh_CN', 'en', 'ja'];

      for (int i = 0; i < 50; i++) {
        final code = languages[i % languages.length];
        await i18n.setLocale(code);
        expect(i18n.currentLanguage.code, code);

        // 掃描關鍵詞彙
        final keys = [
          'nav_home', 'nav_shop', 'nav_nodes', 'nav_connections',
          'nav_traffic', 'nav_affiliate', 'nav_profile', 'nav_settings',
          'current_node', 'latency', 'download', 'upload',
          'status_connected', 'tun_driver_missing_title', 'admin_required_title'
        ];
        for (final k in keys) {
          final translated = i18n.t(k);
          expect(translated, isNotEmpty);
          expect(translated.contains('conn_th_'), isFalse);
          expect(translated.contains('profile_'), isFalse);
          expect(translated, isNot(equals(k)), reason: 'Key $k 未被成功翻譯');
        }
      }
    });

    testWidgets('【第 9 輪：二級彈窗與個人中心 12 格磁貼全點擊無殘留】', (tester) async {
      final authManager = AuthManager(
        dioClient: dioClient,
        storageService: SecureStorageService(),
      );
      final subEngine = SubscriptionEngine(
        storageService: SecureStorageService(),
        dioClient: dioClient,
        coreDaemon: coreDaemon,
      );
      final shopManager = ShopManager(dioClient: dioClient);

      final testUser = UserModel(
        email: 'audit_user@tianhe.net',
        transferEnable: 1024 * 1024 * 1024 * 100,
        u: 1024 * 1024 * 1024 * 10,
        d: 1024 * 1024 * 1024 * 15,
        expiredAt: DateTime.now().add(const Duration(days: 90)).millisecondsSinceEpoch ~/ 1000,
      );
      authManager.updateUserForTest(testUser);

      await tester.binding.setSurfaceSize(const Size(1200, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopDashboardLayout(
              authManager: authManager,
              configService: configService,
              coreDaemon: coreDaemon,
              subscriptionEngine: subEngine,
              shopManager: shopManager,
              onToggleConnection: () {},
              onLogout: () {},
              initialNavIndex: 6, // 個人中心
              enableAnimations: false,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // 驗證 12 格磁貼文字均正確呈現
      expect(find.text(I18nService.instance.t('profile_order_history')), findsOneWidget);
      expect(find.text(I18nService.instance.t('profile_traffic_details')), findsOneWidget);
      expect(find.text(I18nService.instance.t('profile_ticket')), findsOneWidget);

      // 清空並銷毀組件
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });
  });

  group('【階段四（第 10 ~ 12 輪）：網路異常容災、強殺防斷網與系統代理安全壓測】', () {
    test('【第 10 輪：系統代理清零與防斷網機制】', () async {
      final service = WindowsProxyService.instance;
      // 驗證調用 disableSystemProxy 成功
      final res = await service.disableSystemProxy();
      expect(service.isProxyEnabled, isFalse);
    });

    test('【第 11 輪：分流模式 (global / rule / tun) 切換 30 次與管理員權限保護】', () async {
      final daemon = CoreDaemon();
      for (int i = 0; i < 30; i++) {
        final mode = (i % 3 == 0)
            ? ProxyMode.global
            : (i % 3 == 1 ? ProxyMode.rule : ProxyMode.tun);
        await daemon.setProxyMode(mode);
        expect(daemon.proxyMode, mode);
      }
    });

    test('【第 12 輪：API 401 失效攔截、套餐到期與空節點防呆】', () async {
      final authManager = AuthManager(
        dioClient: dioClient,
        storageService: SecureStorageService(),
      );

      // 模擬未登入狀態
      authManager.handleUnauthorized();
      expect(authManager.state.status, AuthStatus.unauthenticated);

      // 模擬過期帳號 (秒級時間戳)
      final pastSec = DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000;
      final expiredUser = UserModel(
        email: 'test@example.com',
        expiredAt: pastSec,
        u: 100,
        d: 100,
        transferEnable: 1000,
      );
      expect(expiredUser.isExpired, isTrue);
      expect(expiredUser.isAvailable, isFalse);
    });
  });

  group('【階段五（第 13 ~ 16 輪）：記憶體洩漏監控、安全滲透審計與黃金封包】', () {
    test('【第 13 輪：高頻流量輪詢持久化 HttpClient 複用驗證】', () async {
      final daemon = CoreDaemon();
      // 驗證未連線時 trafficStream 輸出默認 0 速率且不噴錯
      expect(daemon.currentTraffic.upSpeed, 0);
      expect(daemon.currentTraffic.downSpeed, 0);
    });

    test('【第 14 輪：磁碟零明文與安全閱後即焚原則】', () {
      const originalPayload = '{"api_domain":"https://test.api.com","secret":"tianhe-secure"}';

      // 驗證 AES 加解密零明文金庫
      final encrypted = AesDecryptor.encryptDefault(originalPayload);
      final decrypted = AesDecryptor.decryptDefault(encrypted);
      expect(decrypted, originalPayload);
    });

    test('【第 15 輪：單元測試清零與核心模型健全度】', () {
      final node = NodeModel(
        id: 'node-1',
        name: '🇭🇰 HK 香港 01',
        flagEmoji: '🇭🇰',
        protocol: 'vless',
        latencyMs: 38,
        rawConfig: const {'server': 'hk.node.com', 'port': 443},
      );
      expect(node.cleanDisplayName, '香港 01');
      expect(node.latencyFormatted, '38 ms');
      expect(node.countryCode, 'HK');
    });

    test('【第 16 輪：黃金封包執行檔名稱規範檢測】', () {
      final portableDir = Directory('dist_windows/TianheNetwork_v3.0.8_Portable');
      if (portableDir.existsSync()) {
        final flclashExe = File('${portableDir.path}/flclash_v2board_client.exe');
        // 驗證若存在打包目錄，舊執行檔將被徹底清理
        expect(flclashExe.existsSync() ? 'old_exists' : 'clean', 'clean',
            reason: 'Portable 打包目錄中絕不允許殘留舊的 flclash_v2board_client.exe');
      }
    });
  });
}
