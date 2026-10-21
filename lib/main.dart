import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'core/i18n/i18n_service.dart';
import 'core/network/auth_interceptor.dart';
import 'core/network/dio_client.dart';
import 'core/storage/secure_storage_service.dart';
import 'core/theme/app_theme.dart';
import 'infrastructure/config/app_config_service.dart';
import 'infrastructure/core_daemon/macos_native_proxy.dart';
import 'infrastructure/updater/in_app_updater.dart';
import 'business/auth/auth_manager.dart';
import 'business/auth/traffic_notification_service.dart';
import 'presentation/splash/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Release 模式下強制靜默日誌，確保零敏感資訊洩漏至系統日誌
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // macOS 冷啟動排雷：主動將代理狀態歸零並清理孤兒進程，100% 杜絕殘留導致斷網
  if (!kIsWeb && (Platform.isMacOS || Platform.isWindows)) {
    try {
      await MacosNativeProxy.instance.disableSystemProxy();
    } catch (_) {}
  }

  // 1. 初始化底層基礎服務
  final storageService = SecureStorageService();
  final configService = AppConfigService();
  final updater = InAppUpdater();

  // 初始化多語系與流量預警推播服務 (非阻塞式初始化，確保第一幀極速渲染)
  I18nService.instance.init(storageService: storageService);
  TrafficNotificationService.instance.init(storageService: storageService);

  // 2. 初始化安全 Dio 客戶端
  final dioClient = DioClient(configService: configService);

  // 3. 初始化認證管理器
  final authManager = AuthManager(
    dioClient: dioClient,
    storageService: storageService,
  );

  // 4. 掛載 401 Unauthorized 攔截器，當憑證失效時自動觸發踢出程序
  final authInterceptor = AuthInterceptor(
    storageService: storageService,
    onUnauthorized: () {
      authManager.handleUnauthorized();
    },
  );
  dioClient.addInterceptor(authInterceptor);

  runApp(
    TianheApp(
      configService: configService,
      authManager: authManager,
      updater: updater,
    ),
  );
}

/// 應用程式主入口組件 (天河網絡專屬客戶端)
class TianheApp extends StatelessWidget {
  final AppConfigService configService;
  final AuthManager authManager;
  final InAppUpdater updater;

  const TianheApp({
    super.key,
    required this.configService,
    required this.authManager,
    required this.updater,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: I18nService.instance,
      builder: (context, _) {
        final i18n = I18nService.instance;
        return MaterialApp(
          title: i18n.t('app_title'),
          locale: i18n.currentLocale,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          home: SplashScreen(
            configService: configService,
            authManager: authManager,
            updater: updater,
          ),
        );
      },
    );
  }
}
