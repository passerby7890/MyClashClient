// test/single_source_version_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:flclash_v2board_client/core/constants/app_constants.dart';
import 'package:flclash_v2board_client/infrastructure/config/remote_config_model.dart';
import 'package:flclash_v2board_client/infrastructure/updater/in_app_updater.dart';

void main() {
  group('🏛️ 全系統版本號單一事實來源 (Single Source of Truth) 驗證測試', () {
    test('1. AppConstants 全域版本變數定義正確且對齊 pubspec.yaml', () {
      expect(AppConstants.appVersion, equals('3.3.1'));
      expect(AppConstants.appBuildNumber, equals(131));
      expect(AppConstants.fullVersionDisplay, equals('v3.3.1 (Build 131)'));
      expect(AppConstants.versionTag, equals('v3.3.1'));
    });

    test('2. InAppUpdater checkForUpdates 預設基準版本自動對齊 AppConstants.appVersion', () async {
      final updater = InAppUpdater();
      final remoteConfig = RemoteConfigModel(
        apiDomain: 'https://api.test.com',
        backupApiDomains: [],
        latestVersion: '3.3.1',
        minVersion: '3.0.0',
      );

      final result = await updater.checkForUpdates(remoteConfig: remoteConfig);
      // 當前版本必須為 3.3.1，而非寫死的 1.0.0
      expect(result.currentVersion, equals(AppConstants.appVersion));
      expect(result.hasUpdate, isFalse);
    });

    test('3. 遠端配置比對邏輯：遠端為舊版 (1.0.0) 時，本地 (3.3.1) 絕不誤觸更新', () async {
      final updater = InAppUpdater();
      final remoteConfig = RemoteConfigModel(
        apiDomain: 'https://api.test.com',
        backupApiDomains: [],
        latestVersion: '1.0.0', // 遠端舊版
        minVersion: '1.0.0',
      );

      final result = await updater.checkForUpdates(remoteConfig: remoteConfig);
      expect(result.currentVersion, equals('3.3.1'));
      expect(result.hasUpdate, isFalse);
    });

    test('4. 遠端配置比對邏輯：遠端釋出新版 (3.4.0) 時，精準識別有新版本可升級', () async {
      final updater = InAppUpdater();
      final remoteConfig = RemoteConfigModel(
        apiDomain: 'https://api.test.com',
        backupApiDomains: [],
        latestVersion: '3.4.0',
        minVersion: '3.0.0',
        changelog: '效能優化與 Bug 修復',
        apkUrl: 'https://dl.test.com/app-v3.4.0.apk',
      );

      final result = await updater.checkForUpdates(remoteConfig: remoteConfig);
      expect(result.currentVersion, equals('3.3.1'));
      expect(result.hasUpdate, isTrue);
      expect(result.isForceUpdate, isFalse);
      expect(result.latestVersion, equals('3.4.0'));
    });

    test('5. 遠端配置強制更新比對：當前版本小於 min_version 時觸發阻斷級強制更新', () async {
      final updater = InAppUpdater();
      final remoteConfig = RemoteConfigModel(
        apiDomain: 'https://api.test.com',
        backupApiDomains: [],
        latestVersion: '3.4.0',
        minVersion: '3.4.0', // minVersion > 3.3.1
        changelog: '重大安全性協議升級',
        apkUrl: 'https://dl.test.com/app-v3.4.0.apk',
      );

      final result = await updater.checkForUpdates(remoteConfig: remoteConfig);
      expect(result.currentVersion, equals('3.3.1'));
      expect(result.hasUpdate, isTrue);
      expect(result.isForceUpdate, isTrue);
    });
  });
}
