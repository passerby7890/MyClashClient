import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flclash_v2board_client/business/auth/auth_manager.dart';
import 'package:flclash_v2board_client/business/auth/user_model.dart';
import 'package:flclash_v2board_client/business/shop/shop_manager.dart';
import 'package:flclash_v2board_client/business/subscription/node_model.dart';
import 'package:flclash_v2board_client/business/subscription/subscription_engine.dart';
import 'package:flclash_v2board_client/core/i18n/i18n_service.dart';
import 'package:flclash_v2board_client/core/network/dio_client.dart';
import 'package:flclash_v2board_client/core/storage/secure_storage_service.dart';
import 'package:flclash_v2board_client/core/theme/app_theme.dart';
import 'package:flclash_v2board_client/infrastructure/config/app_config_service.dart';
import 'package:flclash_v2board_client/infrastructure/core_daemon/core_daemon.dart';
import 'package:flclash_v2board_client/presentation/desktop/desktop_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SecureStorageService storage;
  late AppConfigService configService;
  late DioClient dioClient;
  late AuthManager authManager;
  late CoreDaemon coreDaemon;
  late SubscriptionEngine subEngine;
  late ShopManager shopManager;

  setUp(() async {
    storage = SecureStorageService();
    configService = AppConfigService();
    dioClient = DioClient(configService: configService);
    authManager = AuthManager(
      dioClient: dioClient,
      storageService: storage,
    );
    coreDaemon = CoreDaemon();
    subEngine = SubscriptionEngine(
      dioClient: dioClient,
      coreDaemon: coreDaemon,
      storageService: storage,
      isTestMode: true,
    );
    shopManager = ShopManager(dioClient: dioClient);

    // 注入測試用戶資料
    final mockUser = UserModel(
      email: 'test17318@outlook.com',
      transferEnable: 96636764160,
      u: 16019,
      d: 2380236,
      expiredAt: 1799795116,
      planName: '特殊私有套餐(直接续费)',
    );
    authManager.updateUserForTest(mockUser);

    // 注入測試節點
    subEngine.setNodesForTest([
      const NodeModel(
        id: 'node_1',
        name: '🇭🇰 香港 01 [專線]',
        flagEmoji: '🇭🇰',
        protocol: 'vless',
        latencyMs: 38,
        rawConfig: {'server': '1.1.1.1', 'port': 443, 'type': 'vless'},
      ),
      const NodeModel(
        id: 'node_2',
        name: '🇯🇵 日本 01 [原生]',
        flagEmoji: '🇯🇵',
        protocol: 'trojan',
        latencyMs: 65,
        rawConfig: {'server': '1.1.1.2', 'port': 443, 'type': 'trojan'},
      ),
      const NodeModel(
        id: 'node_3',
        name: '🇺🇸 美國 01 [專線]',
        flagEmoji: '🇺🇸',
        protocol: 'hysteria2',
        latencyMs: 142,
        rawConfig: {'server': '1.1.1.3', 'port': 443, 'type': 'hysteria2'},
      ),
    ]);
  });

  final languages = ['zh-TW', 'zh-CN', 'en', 'ja'];
  final tabNames = [
    '00_Home',
    '01_Store',
    '02_Nodes',
    '03_Connections',
    '04_Traffic',
    '05_Affiliate',
    '06_Profile',
    '07_Settings',
  ];

  for (final lang in languages) {
    group('macOS Bento Visual Acceptance [$lang]', () {
      for (int tabIdx = 0; tabIdx < 8; tabIdx++) {
        final tabName = tabNames[tabIdx];
        testWidgets('Tab $tabName renders without RenderFlex overflow', (tester) async {
          // 設定 1200 x 780 黃金視窗物理畫布
          tester.view.physicalSize = const Size(1200, 780);
          tester.view.devicePixelRatio = 1.0;

          await I18nService.instance.switchLanguage(lang);

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.darkTheme,
              home: DesktopShell(
                authManager: authManager,
                configService: configService,
                coreDaemon: coreDaemon,
                subscriptionEngine: subEngine,
                shopManager: shopManager,
                onToggleConnection: () {},
                onLogout: () {},
                initialNavIndex: tabIdx,
                enableAnimations: false,
              ),
            ),
          );

          await tester.pumpAndSettle();

          // 驗證無拋出異常且畫面正常成形
          expect(find.byType(DesktopShell), findsOneWidget);
        });
      }
    });
  }
}
