// test/auto_sync_and_manual_refresh_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:flclash_v2board_client/business/subscription/node_model.dart';
import 'package:flclash_v2board_client/business/subscription/subscription_engine.dart';
import 'package:flclash_v2board_client/core/i18n/i18n_service.dart';
import 'package:flclash_v2board_client/core/network/dio_client.dart';
import 'package:flclash_v2board_client/core/storage/secure_storage_service.dart';
import 'package:flclash_v2board_client/infrastructure/config/app_config_service.dart';
import 'package:flclash_v2board_client/infrastructure/core_daemon/core_daemon.dart';

void main() {
  group('【NodeModel 連線參數比對 Non-Disruptive Diff Check 測試】', () {
    test('1. 相同 IP、Port、UUID、協議參數應判定一致 (hasSameConnectionParams == true)', () {
      const nodeA = NodeModel(
        id: 'node-1',
        name: '🇭🇰 香港 01 | BGP 專線',
        flagEmoji: '🇭🇰',
        protocol: 'vmess',
        rawConfig: {
          'server': 'hk01.tianhe.net',
          'port': 443,
          'type': 'vmess',
          'uuid': 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
          'cipher': 'auto',
          'tls': true,
        },
      );

      const nodeB = NodeModel(
        id: 'node-1-updated',
        name: '🇭🇰 香港 01 | 旗艦專線 [更新]', // 名稱微調但底層參數一致
        flagEmoji: '🇭🇰',
        protocol: 'vmess',
        rawConfig: {
          'server': 'hk01.tianhe.net',
          'port': 443,
          'type': 'vmess',
          'uuid': 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
          'cipher': 'auto',
          'tls': true,
        },
      );

      expect(nodeA.hasSameConnectionParams(nodeB), isTrue);
    });

    test('2. 伺服器 IP 或連接埠變更應判定不一致 (hasSameConnectionParams == false)', () {
      const nodeA = NodeModel(
        id: 'node-1',
        name: '🇭🇰 香港 01',
        flagEmoji: '🇭🇰',
        protocol: 'trojan',
        rawConfig: {
          'server': '1.2.3.4',
          'port': 443,
          'password': 'secretPassword',
        },
      );

      const nodeB = NodeModel(
        id: 'node-1',
        name: '🇭🇰 香港 01',
        flagEmoji: '🇭🇰',
        protocol: 'trojan',
        rawConfig: {
          'server': '1.2.3.5', // IP 變更
          'port': 443,
          'password': 'secretPassword',
        },
      );

      expect(nodeA.hasSameConnectionParams(nodeB), isFalse);
    });

    test('3. UUID / Password / 協議變更應判定不一致', () {
      const nodeA = NodeModel(
        id: 'node-1',
        name: '🇯🇵 日本 01',
        flagEmoji: '🇯🇵',
        protocol: 'shadowsocks',
        rawConfig: {
          'server': 'jp01.tianhe.net',
          'port': 8388,
          'password': 'passA',
        },
      );

      const nodeB = NodeModel(
        id: 'node-1',
        name: '🇯🇵 日本 01',
        flagEmoji: '🇯🇵',
        protocol: 'shadowsocks',
        rawConfig: {
          'server': 'jp01.tianhe.net',
          'port': 8388,
          'password': 'passB', // 密碼變更
        },
      );

      expect(nodeA.hasSameConnectionParams(nodeB), isFalse);
    });
  });

  group('【多國語系 i18n 刷新與同步鍵值校驗】', () {
    test('4 國語系皆應具備 refresh_nodes 與 sync_subscription 翻譯', () {
      final i18n = I18nService.instance;

      for (final locale in ['zh_TW', 'zh_CN', 'en', 'ja']) {
        i18n.setLocale(locale);
        final refreshKey = i18n.t('refresh_nodes');
        final syncKey = i18n.t('sync_subscription');
        final syncSuccess = i18n.t('sync_success', {'count': '10'});
        final syncFailed = i18n.t('sync_failed');

        expect(refreshKey, isNotEmpty);
        expect(syncKey, isNotEmpty);
        expect(syncSuccess, contains('10'));
        expect(syncFailed, isNotEmpty);
      }
      i18n.setLocale('zh_TW'); // 重設回繁體中文
    });
  });

  group('【SubscriptionEngine Auto-Sync Daemon 機制測試】', () {
    test('自救觸發冷卻 CD (5 分鐘) 防抖限制', () async {
      final configService = AppConfigService();
      final dioClient = DioClient(configService: configService);
      final coreDaemon = CoreDaemon();
      final storage = SecureStorageService();
      final engine = SubscriptionEngine(
        dioClient: dioClient,
        coreDaemon: coreDaemon,
        storageService: storage,
        isTestMode: true,
      );

      // 第一次自救觸發
      engine.triggerFailureRescueSync();
      expect(engine.lastRescueSyncTime, isNotNull);
      final firstRescueTime = engine.lastRescueSyncTime;

      // 立即第二次自救觸發 (應在 5 分鐘冷卻中被安全防抖截流，不更新 lastRescueSyncTime)
      engine.triggerFailureRescueSync();
      expect(engine.lastRescueSyncTime, equals(firstRescueTime));

      await Future.delayed(const Duration(milliseconds: 100));
      engine.dispose();
    });
  });
}
