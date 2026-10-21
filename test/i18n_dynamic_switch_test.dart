// test/i18n_dynamic_switch_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:flclash_v2board_client/core/i18n/i18n_service.dart';
import 'package:flclash_v2board_client/core/network/dio_client.dart';
import 'package:flclash_v2board_client/core/storage/secure_storage_service.dart';
import 'package:flclash_v2board_client/core/theme/app_theme.dart';
import 'package:flclash_v2board_client/infrastructure/config/app_config_service.dart';
import 'package:flclash_v2board_client/business/auth/auth_manager.dart';
import 'package:flclash_v2board_client/business/shop/shop_manager.dart';
import 'package:flclash_v2board_client/presentation/profile/user_center_screen.dart';

class MockMemoryStorage extends SecureStorageService {
  final Map<String, String> _map = {};

  @override
  Future<void> write(String key, String value) async {
    _map[key] = value;
  }

  @override
  Future<String?> read(String key) async => _map[key];

  @override
  Future<void> delete(String key) async => _map.remove(key);

  @override
  Future<void> clearAll() async => _map.clear();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockMemoryStorage storage;
  late I18nService i18n;
  late AppConfigService configService;
  late DioClient dioClient;
  late AuthManager authManager;
  late ShopManager shopManager;

  setUp(() async {
    storage = MockMemoryStorage();
    i18n = I18nService.instance;
    await i18n.init(storageService: storage);

    configService = AppConfigService();
    dioClient = DioClient(
      configService: configService,
      customDio: Dio(BaseOptions(baseUrl: 'https://0n21.com')),
    );
    authManager = AuthManager(dioClient: dioClient, storageService: storage);
    shopManager = ShopManager(dioClient: dioClient);
  });

  group('多語言 i18n 核心單元測試', () {
    test('1. 系統語系自動映射規則測試 (Follow System)', () {
      // 繁體中文映射
      expect(I18nService.resolveSystemLanguage(const Locale('zh', 'TW')), equals(AppLanguage.zhTW));
      expect(I18nService.resolveSystemLanguage(const Locale('zh', 'HK')), equals(AppLanguage.zhTW));
      expect(I18nService.resolveSystemLanguage(const Locale('zh', 'MO')), equals(AppLanguage.zhTW));
      expect(I18nService.resolveSystemLanguage(const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')), equals(AppLanguage.zhTW));

      // 簡體中文映射
      expect(I18nService.resolveSystemLanguage(const Locale('zh', 'CN')), equals(AppLanguage.zhCN));
      expect(I18nService.resolveSystemLanguage(const Locale('zh', 'SG')), equals(AppLanguage.zhCN));
      expect(I18nService.resolveSystemLanguage(const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans')), equals(AppLanguage.zhCN));

      // 日本語映射
      expect(I18nService.resolveSystemLanguage(const Locale('ja')), equals(AppLanguage.ja));
      expect(I18nService.resolveSystemLanguage(const Locale('ja', 'JP')), equals(AppLanguage.ja));

      // 英文與其他任何語言兜底至英文
      expect(I18nService.resolveSystemLanguage(const Locale('en')), equals(AppLanguage.en));
      expect(I18nService.resolveSystemLanguage(const Locale('en', 'US')), equals(AppLanguage.en));
      expect(I18nService.resolveSystemLanguage(const Locale('fr', 'FR')), equals(AppLanguage.en));
      expect(I18nService.resolveSystemLanguage(const Locale('de', 'DE')), equals(AppLanguage.en));
      expect(I18nService.resolveSystemLanguage(const Locale('ko', 'KR')), equals(AppLanguage.en));
      expect(I18nService.resolveSystemLanguage(const Locale('es', 'ES')), equals(AppLanguage.en));
    });

    test('2. 4 國語言字典完整性與翻譯對照驗證', () async {
      // 驗證 繁體中文
      await i18n.setLanguage(AppLanguage.zhTW);
      expect(i18n.t('profile_ticket'), equals('我的工單'));
      expect(i18n.t('profile_service'), equals('在線客服'));
      expect(i18n.t('nav_profile'), equals('個人中心'));
      expect(i18n.t('profile_help_support'), equals('幫助與支持'));
      expect(i18n.t('profile_language'), equals('介面語言 (Language)'));

      // 驗證 簡體中文
      await i18n.setLanguage(AppLanguage.zhCN);
      expect(i18n.t('profile_ticket'), equals('我的工单'));
      expect(i18n.t('profile_service'), equals('在线客服'));
      expect(i18n.t('nav_profile'), equals('个人中心'));
      expect(i18n.t('profile_help_support'), equals('帮助与支持'));
      expect(i18n.t('profile_language'), equals('界面语言 (Language)'));

      // 驗證 英文
      await i18n.setLanguage(AppLanguage.en);
      expect(i18n.t('profile_ticket'), equals('My Tickets'));
      expect(i18n.t('profile_service'), equals('Online Support'));
      expect(i18n.t('nav_profile'), equals('Profile'));
      expect(i18n.t('profile_help_support'), equals('Help & Support'));
      expect(i18n.t('profile_language'), equals('Language'));

      // 驗證 日本語
      await i18n.setLanguage(AppLanguage.ja);
      expect(i18n.t('profile_ticket'), equals('マイチケット'));
      expect(i18n.t('profile_service'), equals('オンラインサポート'));
      expect(i18n.t('nav_profile'), equals('マイページ'));
      expect(i18n.t('profile_help_support'), equals('ヘルプ＆サポート'));
      expect(i18n.t('profile_language'), equals('言語設定 (Language)'));
    });

    test('3. I18nService 狀態機切換與持久化寫入驗證', () async {
      int notifyCount = 0;
      void listener() => notifyCount++;
      i18n.addListener(listener);

      // 切換為英文
      await i18n.setLanguage(AppLanguage.en);
      expect(i18n.currentLanguage, equals(AppLanguage.en));
      expect(i18n.isFollowSystem, isFalse);
      expect(notifyCount, greaterThan(0));
      expect(await storage.read('v2board_app_language'), equals('en'));

      // 切換回跟隨系統
      await i18n.setFollowSystem();
      expect(i18n.isFollowSystem, isTrue);
      expect(await storage.read('v2board_app_language'), equals('auto'));

      i18n.removeListener(listener);
    });
  });

  group('UserCenterScreen 多語言即時響應 Widget 測試', () {
    testWidgets('4. 切換語言時 UserCenterScreen 即時動態切換翻譯字串', (tester) async {
      // 1. 預設先設為繁中
      await i18n.setLanguage(AppLanguage.zhTW);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: UserCenterScreen(
            authManager: authManager,
            shopManager: shopManager,
            configService: configService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 驗證繁中渲染
      expect(find.text('我的工單'), findsOneWidget);
      expect(find.text('在線客服'), findsOneWidget);
      expect(find.text('幫助與支持'), findsOneWidget);
      expect(find.text('介面語言 (Language)'), findsOneWidget);
      expect(find.text('My Tickets'), findsNothing);

      // 2. 切換至 English (免重啟，0.1 秒內響應)
      await i18n.setLanguage(AppLanguage.en);
      await tester.pumpAndSettle();

      // 驗證英文即時渲染
      expect(find.text('我的工單'), findsNothing);
      expect(find.text('My Tickets'), findsOneWidget);
      expect(find.text('Online Support'), findsOneWidget);
      expect(find.text('Help & Support'), findsOneWidget);
      expect(find.text('Language'), findsOneWidget);

      // 3. 切換至 日本語
      await i18n.setLanguage(AppLanguage.ja);
      await tester.pumpAndSettle();

      // 驗證日文即時渲染
      expect(find.text('My Tickets'), findsNothing);
      expect(find.text('マイチケット'), findsOneWidget);
      expect(find.text('オンラインサポート'), findsOneWidget);
      expect(find.text('ヘルプ＆サポート'), findsOneWidget);
      expect(find.text('言語設定 (Language)'), findsOneWidget);

      // 4. 切換至 简体中文
      await i18n.setLanguage(AppLanguage.zhCN);
      await tester.pumpAndSettle();

      // 驗證簡中即時渲染
      expect(find.text('マイチケット'), findsNothing);
      expect(find.text('我的工单'), findsOneWidget);
      expect(find.text('在线客服'), findsOneWidget);
      expect(find.text('帮助与支持'), findsOneWidget);
      expect(find.text('界面语言 (Language)'), findsOneWidget);
    });

    testWidgets('5. 模擬點擊底部語言彈窗中的選項並即時生效', (tester) async {
      await i18n.setLanguage(AppLanguage.zhTW);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: UserCenterScreen(
            authManager: authManager,
            shopManager: shopManager,
            configService: configService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 點擊「介面語言 (Language)」開啟 BottomSheet
      final languageTile = find.text('介面語言 (Language)');
      expect(languageTile, findsOneWidget);
      await tester.tap(languageTile);
      await tester.pumpAndSettle();

      // 驗證彈窗內的 4 個語言選項 ListTile 均可見 (限定在 BottomSheet 內查找)
      expect(find.widgetWithText(ListTile, 'English'), findsOneWidget);
      expect(find.widgetWithText(ListTile, '日本語'), findsOneWidget);
      expect(find.widgetWithText(ListTile, '简体中文'), findsOneWidget);
      expect(find.descendant(of: find.byType(BottomSheet), matching: find.text('繁體中文')), findsOneWidget);

      // 點擊 English ListTile 選項
      await tester.tap(find.widgetWithText(ListTile, 'English'));
      await tester.pumpAndSettle(); // 彈窗關閉且主畫面刷新

      // 驗證主畫面已徹底切換為英文
      expect(find.text('My Tickets'), findsOneWidget);
      expect(find.text('Online Support'), findsOneWidget);
      expect(find.text('Help & Support'), findsOneWidget);
      expect(find.text('我的工單'), findsNothing);
    });
  });
}
