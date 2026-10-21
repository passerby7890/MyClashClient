// test/updater_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:flclash_v2board_client/infrastructure/config/remote_config_model.dart';
import 'package:flclash_v2board_client/infrastructure/updater/in_app_updater.dart';

void main() {
  group('階段四：自動更新器單元測試', () {
    test('1. 一般新版本檢測 (非強制更新)', () async {
      const config = RemoteConfigModel(
        apiDomain: 'https://api.test.com',
        latestVersion: '2.0.0',
        minVersion: '1.0.0',
        apkUrl: 'https://dl.test.com/app.apk',
        exeUrl: 'https://dl.test.com/app.exe',
        changelog: '優化節點切換速度',
      );

      final updater = InAppUpdater();
      final result = await updater.checkForUpdates(
        remoteConfig: config,
        mockCurrentVersion: '1.2.0',
      );

      expect(result.hasUpdate, isTrue);
      expect(result.isForceUpdate, isFalse);
      expect(result.latestVersion, equals('2.0.0'));
      expect(result.changelog, equals('優化節點切換速度'));
    });

    test('2. 重要版本強制更新檢測 (當前版本低於 min_version)', () async {
      const config = RemoteConfigModel(
        apiDomain: 'https://api.test.com',
        latestVersion: '2.5.0',
        minVersion: '2.0.0', // 最低相容版本為 2.0.0
        apkUrl: 'https://dl.test.com/app.apk',
        changelog: 'API 架構重構，必須強制更新',
      );

      final updater = InAppUpdater();
      final result = await updater.checkForUpdates(
        remoteConfig: config,
        mockCurrentVersion: '1.8.0', // 低於 2.0.0
      );

      expect(result.hasUpdate, isTrue);
      expect(result.isForceUpdate, isTrue);
    });

    test('3. 已是最新版本檢測', () async {
      const config = RemoteConfigModel(
        apiDomain: 'https://api.test.com',
        latestVersion: '1.5.0',
        minVersion: '1.0.0',
      );

      final updater = InAppUpdater();
      final result = await updater.checkForUpdates(
        remoteConfig: config,
        mockCurrentVersion: '1.5.0',
      );

      expect(result.hasUpdate, isFalse);
      expect(result.isForceUpdate, isFalse);
    });
  });
}
