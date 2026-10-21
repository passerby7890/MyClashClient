// test/i18n_system_locale_detection_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flclash_v2board_client/core/i18n/i18n_service.dart';
import 'package:flclash_v2board_client/core/storage/secure_storage_service.dart';
import 'package:flclash_v2board_client/core/constants/app_constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  group('I18nService - 系統環境語系智慧偵測 (System Locale Auto-Detection)', () {
    test('1. 繁體中文系 (zh_TW, zh_HK, zh_MO, zh_Hant) 100% 正確對應為 zhTW (繁體中文)', () {
      expect(I18nService.resolveSystemLanguage('zh_TW'), equals(AppLanguage.zhTW));
      expect(I18nService.resolveSystemLanguage('zh-TW'), equals(AppLanguage.zhTW));
      expect(I18nService.resolveSystemLanguage('zh_HK'), equals(AppLanguage.zhTW));
      expect(I18nService.resolveSystemLanguage('zh-HK'), equals(AppLanguage.zhTW));
      expect(I18nService.resolveSystemLanguage('zh_MO'), equals(AppLanguage.zhTW));
      expect(I18nService.resolveSystemLanguage('zh-MO'), equals(AppLanguage.zhTW));
      expect(I18nService.resolveSystemLanguage('zh_Hant'), equals(AppLanguage.zhTW));
      expect(I18nService.resolveSystemLanguage('zh-Hant'), equals(AppLanguage.zhTW));
      expect(I18nService.resolveSystemLanguage('zh_Hant_TW'), equals(AppLanguage.zhTW));
      expect(I18nService.resolveSystemLanguage('zh_traditional'), equals(AppLanguage.zhTW));
    });

    test('2. 簡體中文系 (zh_CN, zh_SG, zh_Hans, 或單獨 zh) 100% 正確對應為 zhCN (簡體中文)', () {
      expect(I18nService.resolveSystemLanguage('zh_CN'), equals(AppLanguage.zhCN));
      expect(I18nService.resolveSystemLanguage('zh-CN'), equals(AppLanguage.zhCN));
      expect(I18nService.resolveSystemLanguage('zh_SG'), equals(AppLanguage.zhCN));
      expect(I18nService.resolveSystemLanguage('zh-SG'), equals(AppLanguage.zhCN));
      expect(I18nService.resolveSystemLanguage('zh_Hans'), equals(AppLanguage.zhCN));
      expect(I18nService.resolveSystemLanguage('zh-Hans'), equals(AppLanguage.zhCN));
      expect(I18nService.resolveSystemLanguage('zh_Hans_CN'), equals(AppLanguage.zhCN));
      expect(I18nService.resolveSystemLanguage('zh'), equals(AppLanguage.zhCN));
      expect(I18nService.resolveSystemLanguage('zh_simplified'), equals(AppLanguage.zhCN));
    });

    test('3. 其餘所有國家與地區 (en, ja, ko, de, fr 等) 預設一律 fallback 降級為 en (英文)', () {
      expect(I18nService.resolveSystemLanguage('en_US'), equals(AppLanguage.en));
      expect(I18nService.resolveSystemLanguage('en-GB'), equals(AppLanguage.en));
      expect(I18nService.resolveSystemLanguage('en'), equals(AppLanguage.en));
      expect(I18nService.resolveSystemLanguage('ja_JP'), equals(AppLanguage.en));
      expect(I18nService.resolveSystemLanguage('ko_KR'), equals(AppLanguage.en));
      expect(I18nService.resolveSystemLanguage('de_DE'), equals(AppLanguage.en));
      expect(I18nService.resolveSystemLanguage('fr_FR'), equals(AppLanguage.en));
      expect(I18nService.resolveSystemLanguage('es_ES'), equals(AppLanguage.en));
      expect(I18nService.resolveSystemLanguage('unknown_LOCALE'), equals(AppLanguage.en));
    });
  });

  group('I18nService - 手動點擊即時生效與持久化 (Manual Override & Persistence)', () {
    late SecureStorageService storageService;
    late I18nService i18n;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      storageService = SecureStorageService();
      i18n = I18nService.instance;
      await i18n.init(storageService: storageService);
    });

    test('4. 手動呼叫 setLocale / setLanguage 觸發全域廣播與本地持久化', () async {
      int notifyCount = 0;
      void listener() => notifyCount++;
      i18n.addListener(listener);

      // 切換為英文
      await i18n.setLocale('en');
      expect(i18n.currentLanguage, equals(AppLanguage.en));
      expect(i18n.isFollowSystem, isFalse);
      expect(notifyCount, greaterThanOrEqualTo(1));

      // 驗證 SecureStorage 內已正確保存 'en'
      final saved1 = await storageService.read(AppConstants.storageAppLanguage);
      expect(saved1, equals('en'));

      // 切換為簡體中文 (透過 zh_Hans)
      await i18n.setLocale('zh_Hans');
      expect(i18n.currentLanguage, equals(AppLanguage.zhCN));
      expect(i18n.isFollowSystem, isFalse);
      final saved2 = await storageService.read(AppConstants.storageAppLanguage);
      expect(saved2, equals('zh_CN'));

      // 切換為繁體中文 (透過 zh_Hant)
      await i18n.setLocale('zh_Hant');
      expect(i18n.currentLanguage, equals(AppLanguage.zhTW));
      expect(i18n.isFollowSystem, isFalse);
      final saved3 = await storageService.read(AppConstants.storageAppLanguage);
      expect(saved3, equals('zh_TW'));

      // 切換回跟隨系統
      await i18n.setFollowSystem();
      expect(i18n.isFollowSystem, isTrue);
      final saved4 = await storageService.read(AppConstants.storageAppLanguage);
      expect(saved4, equals('auto'));

      i18n.removeListener(listener);
    });

    test('5. 冷啟動初始化：有手動紀錄時優先讀取手動覆蓋，不被覆蓋', () async {
      // 模擬用戶上次手動選擇了 English
      await storageService.write(AppConstants.storageAppLanguage, 'en');

      await i18n.init(storageService: storageService);
      expect(i18n.isFollowSystem, isFalse);
      expect(i18n.currentLanguage, equals(AppLanguage.en));
    });

    test('6. 品牌名稱 (天河網絡) 隨當前語系智慧切換', () async {
      // 繁體中文
      await i18n.setLocale('zh_Hant');
      expect(i18n.t('app_title'), equals('天河網絡'));

      // 簡體中文
      await i18n.setLocale('zh_Hans');
      expect(i18n.t('app_title'), equals('天河网络'));

      // 英文
      await i18n.setLocale('en');
      expect(i18n.t('app_title'), equals('Tianhe Network'));
    });
  });
}
