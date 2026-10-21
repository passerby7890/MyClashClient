// test/widget_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:flclash_v2board_client/main.dart';
import 'package:flclash_v2board_client/infrastructure/config/app_config_service.dart';
import 'package:flclash_v2board_client/business/auth/auth_manager.dart';
import 'package:flclash_v2board_client/infrastructure/updater/in_app_updater.dart';
import 'package:flclash_v2board_client/core/network/dio_client.dart';
import 'package:flclash_v2board_client/core/storage/secure_storage_service.dart';
import 'package:flclash_v2board_client/presentation/splash/splash_screen.dart';

void main() {
  testWidgets('TianheApp 啟動與 SplashScreen 煙霧測試', (WidgetTester tester) async {
    final storage = SecureStorageService();
    final configService = AppConfigService();
    final updater = InAppUpdater();
    final dioClient = DioClient(configService: configService);
    final authManager = AuthManager(
      dioClient: dioClient,
      storageService: storage,
    );

    await tester.pumpWidget(
      TianheApp(
        configService: configService,
        authManager: authManager,
        updater: updater,
      ),
    );

    // 驗證成功加載 SplashScreen
    expect(find.byType(SplashScreen), findsOneWidget);
  });
}
