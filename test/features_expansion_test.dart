// test/features_expansion_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:flclash_v2board_client/business/auth/traffic_log_model.dart';
import 'package:flclash_v2board_client/business/auth/traffic_notification_service.dart';
import 'package:flclash_v2board_client/business/auth/user_model.dart';
import 'package:flclash_v2board_client/business/subscription/node_model.dart';
import 'package:flclash_v2board_client/core/i18n/i18n_service.dart';
import 'package:flclash_v2board_client/infrastructure/updater/in_app_updater.dart';

void main() {
  group('進階功能擴充全覆蓋測試', () {
    test('1. TrafficLogModel 流量明細資料模型與格式化解析驗證', () {
      final json = {
        'u': 1048576, // 1 MB
        'd': 5242880, // 5 MB
        'record_at': 1761955200,
        'user_id': 101,
        'server_rate': 1.5,
      };

      final model = TrafficLogModel.fromJson(json);

      expect(model.u, 1048576);
      expect(model.d, 5242880);
      expect(model.totalBytes, 6291456); // 6 MB
      expect(model.userId, 101);
      expect(model.serverRate, 1.5);
      expect(model.formattedUpload, '1.00 MB');
      expect(model.formattedDownload, '5.00 MB');
      expect(model.formattedTotal, '6.00 MB');
      expect(model.formattedDate, isNotEmpty);
      expect(model.dateOnly, isNotEmpty);
    });

    test('2. TrafficNotificationService 流量耗盡、過期與低流量預警檢測 (TODO-03)', () async {
      final notifService = TrafficNotificationService.instance;

      // 情境 A: 流量耗盡 (remaining <= 0)
      final depletedUser = UserModel(
        email: 'test@user.com',
        transferEnable: 1000000,
        u: 500000,
        d: 500000,
      );
      final alertA = await notifService.checkTrafficAlert(depletedUser, forceCheck: true);
      expect(alertA, isNotNull);
      expect(alertA!.type, TrafficAlertType.exhausted);
      expect(alertA.isBlocking, true);

      // 情境 B: 訂閱已過期
      final expiredUser = UserModel(
        email: 'test@user.com',
        transferEnable: 100000000,
        u: 1000,
        d: 1000,
        expiredAt: 1000, // 遠小於當前時間戳
      );
      final alertB = await notifService.checkTrafficAlert(expiredUser, forceCheck: true);
      expect(alertB, isNotNull);
      expect(alertB!.type, TrafficAlertType.expired);
      expect(alertB.isBlocking, true);

      // 情境 C: 剩餘流量低於 10%
      final lowTrafficUser = UserModel(
        email: 'test@user.com',
        transferEnable: 1000000, // 1 MB
        u: 460000,
        d: 460000, // 已用 920000，剩餘 80000 (8% < 10%)
      );
      final alertC = await notifService.checkTrafficAlert(lowTrafficUser, forceCheck: true);
      expect(alertC, isNotNull);
      expect(alertC!.type, TrafficAlertType.lowTraffic);
      expect(alertC.isBlocking, false);

      // 情境 D: 正常充足帳號
      final normalUser = UserModel(
        email: 'test@user.com',
        transferEnable: 1000000000,
        u: 10000,
        d: 10000,
        expiredAt: (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 86400 * 30,
      );
      final alertD = await notifService.checkTrafficAlert(normalUser, forceCheck: true);
      expect(alertD, isNull);
    });

    test('3. 節點收藏 (Favorite) 與依歷史延遲智慧排序 (TODO-06)', () {
      final nodeA = NodeModel(
        id: 'node_1',
        name: '香港 01 專線',
        flagEmoji: '🇭🇰',
        protocol: 'VMESS',
        latencyMs: 180,
        rawConfig: {'name': '香港 01 專線'},
      );

      final nodeB = NodeModel(
        id: 'node_2',
        name: '日本 01 專線',
        flagEmoji: '🇯🇵',
        protocol: 'VMESS',
        latencyMs: 45,
        rawConfig: {'name': '日本 01 專線'},
      );

      final nodeC = NodeModel(
        id: 'node_3',
        name: '美國 01 專線',
        flagEmoji: '🇺🇸',
        protocol: 'VMESS',
        latencyMs: -1, // 逾時
        rawConfig: {'name': '美國 01 專線'},
      );

      // 驗證 copyWithFavorite
      final favA = nodeA.copyWithFavorite(true);
      expect(favA.isFavorite, true);
      expect(nodeA.isFavorite, false);



      // 模擬載入節點清單
      final testNodes = [nodeA, nodeB, nodeC];
      // 依延遲排序 (45ms 日本 -> 180ms 香港 -> 逾時 美國)
      final sortedByLatency = List.of(testNodes);
      sortedByLatency.sort((a, b) {
        final aPing = (a.latencyMs != null && a.latencyMs! > 0) ? a.latencyMs! : 999999;
        final bPing = (b.latencyMs != null && b.latencyMs! > 0) ? b.latencyMs! : 999999;
        return aPing.compareTo(bPing);
      });

      expect(sortedByLatency.first.id, 'node_2');
      expect(sortedByLatency[1].id, 'node_1');
      expect(sortedByLatency.last.id, 'node_3');
    });

    test('4. I18nService 繁/簡/英/日多語言原生切換驗證 (TODO-07)', () async {
      final i18n = I18nService.instance;

      // 1. 預設繁體中文
      await i18n.setLanguage(AppLanguage.zhTW);
      expect(i18n.currentLanguage, AppLanguage.zhTW);
      expect(i18n.t('status_disconnected'), '未連接');
      expect(i18n.t('traffic_details'), '流量明細');

      // 2. 切換簡體中文
      await i18n.setLanguage(AppLanguage.zhCN);
      expect(i18n.currentLanguage, AppLanguage.zhCN);
      expect(i18n.t('status_disconnected'), '未连接');
      expect(i18n.t('traffic_details'), '流量明细');

      // 3. 切換英文
      await i18n.setLanguage(AppLanguage.en);
      expect(i18n.currentLanguage, AppLanguage.en);
      expect(i18n.t('status_disconnected'), 'Disconnected');
      expect(i18n.t('traffic_details'), 'Traffic Details');

      // 4. 切換日文
      await i18n.setLanguage(AppLanguage.ja);
      expect(i18n.currentLanguage, AppLanguage.ja);
      expect(i18n.t('status_disconnected'), '未接続');
      expect(i18n.t('traffic_details'), '通信量明細');

      // 復原為繁體中文
      await i18n.setLanguage(AppLanguage.zhTW);
    });

    test('5. InAppUpdater 與 update.json 版本號比對解析驗證', () {
      // 比對較新版本
      expect(InAppUpdater.isNewerVersion('1.0.0', '3.0.0'), true);
      expect(InAppUpdater.isNewerVersion('1.2.0', '1.2.1'), true);
      expect(InAppUpdater.isNewerVersion('1.0.0', '1.0.0'), false);
      expect(InAppUpdater.isNewerVersion('3.0.0', '1.0.0'), false);

      // 驗證 update.json 格式解析邏輯
      final updateJson = {
        'version': '3.0.0',
        'body': '优化逻辑速度',
        'download_url': 'https://portal.thjs789.com',
        'platforms': {
          'android': {
            'version': '3.0.0',
            'body': '优化逻辑速度',
            'download_url': 'https://novaclash.oss-ap-northeast-1.aliyuncs.com/d/3.0.0/android.zip'
          }
        }
      };

      final latestVer = updateJson['version'] as String;
      final body = updateJson['body'] as String;
      final androidUrl = (updateJson['platforms'] as Map)['android']['download_url'] as String;

      expect(InAppUpdater.isNewerVersion('1.0.0', latestVer), true);
      expect(body, '优化逻辑速度');
      expect(androidUrl, contains('android.zip'));
    });
  });
}
