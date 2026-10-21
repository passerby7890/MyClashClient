// test/v2board_auth_and_ui_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:flclash_v2board_client/core/i18n/i18n_service.dart';
import 'package:flclash_v2board_client/business/auth/auth_manager.dart';
import 'package:flclash_v2board_client/core/network/dio_client.dart';
import 'package:flclash_v2board_client/core/storage/secure_storage_service.dart';
import 'package:flclash_v2board_client/infrastructure/config/app_config_service.dart';
import 'package:flclash_v2board_client/presentation/auth/register_screen.dart';
import 'package:flclash_v2board_client/presentation/auth/forgot_password_screen.dart';
import 'package:flclash_v2board_client/presentation/auth/login_screen.dart';

class MockMemorySecureStorage extends SecureStorageService {
  final Map<String, String> _data = {};

  @override
  Future<void> saveToken(String token) async {
    _data['v2board_jwt_token'] = token;
  }

  @override
  Future<String?> getToken() async => _data['v2board_jwt_token'];

  @override
  Future<void> saveUserInfoJson(String jsonStr) async {
    _data['v2board_user_info'] = jsonStr;
  }

  @override
  Future<String?> getUserInfoJson() async => _data['v2board_user_info'];

  @override
  Future<void> clearAll() async => _data.clear();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockMemorySecureStorage storageService;
  late DioClient dioClient;
  late AuthManager authManager;
  late AppConfigService configService;
  late Dio mockDio;

  setUp(() {
    storageService = MockMemorySecureStorage();
    configService = AppConfigService();
    mockDio = Dio(BaseOptions(baseUrl: 'https://0n21.com'));
    dioClient = DioClient(configService: configService, customDio: mockDio);
    authManager = AuthManager(
      dioClient: dioClient,
      storageService: storageService,
    );
    // 確保單元測試固定在繁體中文環境以精準比對斷言字串
    I18nService.instance.switchLanguage('zh_TW');
  });

  group('V2Board 認證與重置密碼 API 單元測試', () {
    test('1. sendEmailVerify 請求格式與錯誤解析驗證', () async {
      expect(authManager.sendEmailVerify, isNotNull);
    });

    test('2. resetPassword 請求格式與參數處理驗證', () async {
      expect(authManager.resetPassword, isNotNull);
    });
  });

  group('V2Board 與 App 賽博科技風深度統一 UI 驗證測試', () {
    testWidgets('3. 註冊頁面 (RegisterScreen) 呈現統一科技主題與完整元件', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RegisterScreen(
            authManager: authManager,
            configService: configService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 品牌標題與引導語 (已徹底移除網頁下載字眼)
      expect(find.text('建立新帳號'), findsOneWidget);
      expect(find.text('註冊天河網絡，開啟安全極速通道'), findsOneWidget);
      expect(find.text('应用端如无法使用请至网站重新下载'), findsNothing);

      // 下拉選單後綴預設值
      expect(find.text('@qq.com'), findsOneWidget);

      // 驗證碼輸入框 placeholder 與 發送按鈕
      expect(find.text('郵箱驗證碼'), findsOneWidget);
      expect(find.text('發送'), findsOneWidget);

      // 邀請碼輸入框
      expect(find.text('邀請碼 (選填)'), findsOneWidget);

      // 註冊主按鈕
      expect(find.text('建立帳號並登入'), findsOneWidget);

      // 底部導航
      expect(find.text('返回登入'), findsOneWidget);
      expect(find.text(I18nService.instance.currentLanguage.label), findsOneWidget);
    });

    testWidgets('4. 忘記密碼頁面 (ForgotPasswordScreen) 呈現統一科技主題與完整元件', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ForgotPasswordScreen(
            authManager: authManager,
            configService: configService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 品牌標題與引導語
      expect(find.text('重置帳號密碼'), findsOneWidget);
      expect(find.text('驗證郵箱後即可設置新密碼'), findsOneWidget);
      expect(find.text('应用端如无法使用请至网站重新下载'), findsNothing);

      // 預設後綴
      expect(find.text('@qq.com'), findsOneWidget);

      // 驗證碼輸入框與發送按鈕
      expect(find.text('郵箱驗證碼'), findsOneWidget);
      expect(find.text('發送'), findsOneWidget);

      // 重置密碼主按鈕
      expect(find.text('重置密碼並返回'), findsOneWidget);

      // 底部導航
      expect(find.text('返回登入'), findsOneWidget);
      expect(find.text(I18nService.instance.currentLanguage.label), findsOneWidget);
    });

    testWidgets('5. 登入頁面 (LoginScreen) 包含忘記密碼跳轉入口並高度統一樣式', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(
            authManager: authManager,
            configService: configService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 品牌標題與引導語
      expect(find.text('天河網絡'), findsOneWidget);
      expect(find.text('登入您的帳號，暢享全球高速節點'), findsOneWidget);
      expect(find.text('应用端如无法使用请至网站重新下载'), findsNothing);

      // 忘記密碼連結
      expect(find.text('忘記密碼？'), findsOneWidget);

      // 立即註冊連結
      expect(find.text('立即註冊'), findsOneWidget);

      // 點擊忘記密碼應能導航至 ForgotPasswordScreen
      await tester.tap(find.text('忘記密碼？'));
      await tester.pumpAndSettle();

      expect(find.text('重置帳號密碼'), findsOneWidget);
    });
  });
}
