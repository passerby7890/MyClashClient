// test/hot_switch_and_disconnect_fix_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:flclash_v2board_client/infrastructure/core_daemon/core_daemon.dart';
import 'package:flclash_v2board_client/business/subscription/subscription_engine.dart';
import 'package:flclash_v2board_client/business/subscription/node_model.dart';
import 'package:flclash_v2board_client/core/network/dio_client.dart';
import 'package:flclash_v2board_client/infrastructure/config/app_config_service.dart';
import 'package:flclash_v2board_client/core/storage/secure_storage_service.dart';

void main() {
  group('【重大 BUG 專項修復驗證：熱切換與斷線防崩潰測試】', () {
    late CoreDaemon coreDaemon;
    late SubscriptionEngine subscriptionEngine;

    setUp(() {
      coreDaemon = CoreDaemon();
      final configService = AppConfigService();
      final dioClient = DioClient(configService: configService);
      final storage = SecureStorageService();
      subscriptionEngine = SubscriptionEngine(
        dioClient: dioClient,
        coreDaemon: coreDaemon,
        storageService: storage,
      );
    });

    test('1. 斷線防崩潰驗證: stop() 即時註銷流量定時器並防範重入與空指針', () async {
      // 1. 模擬啟動連線
      await coreDaemon.start(
        configPath: '/mock/test_config.yaml',
        selectedNode: '香港 01 專線',
      );
      expect(coreDaemon.state.isConnected, isTrue);

      // 2. 併發多次執行 stop() (模擬使用者狂點斷線或 Service 觸發重入)
      final f1 = coreDaemon.stop();
      final f2 = coreDaemon.stop();
      final f3 = coreDaemon.stop();

      await Future.wait([f1, f2, f3]);

      // 3. 驗證狀態平滑轉換至 disconnected，且未發生任何崩潰或未捕獲異常
      expect(coreDaemon.state.isDisconnected, isTrue);
      expect(coreDaemon.currentTraffic.upSpeed, equals(0));
      expect(coreDaemon.currentTraffic.downSpeed, equals(0));
    });

    test('2. 極速熱切換驗證: 連線中切換節點觸發雙通道熱更新並更新狀態', () async {
      // 1. 啟動連線
      await coreDaemon.start(
        configPath: '/mock/test_config.yaml',
        selectedNode: '香港 01 專線',
      );
      expect(coreDaemon.state.activeNodeName, equals('香港 01 專線'));

      // 2. 執行熱切換 (Hot Switch) 至新節點
      await coreDaemon.switchNode('日本 02 - IPLC 高速', configPath: '/mock/test_config.yaml');

      // 3. 驗證連線未中斷且節點名稱即時改變
      expect(coreDaemon.state.isConnected, isTrue);
      expect(coreDaemon.state.activeNodeName, equals('日本 02 - IPLC 高速'));
    });

    test('3. SubscriptionEngine 與 CoreDaemon 連動熱切換完整性驗證', () async {
      const node1 = NodeModel(
        id: '1',
        name: '香港 01',
        flagEmoji: '🇭🇰',
        protocol: 'ss',
        rawConfig: {},
      );
      const node2 = NodeModel(
        id: '2',
        name: '美國 洛杉磯 01',
        flagEmoji: '🇺🇸',
        protocol: 'trojan',
        rawConfig: {},
      );

      // 1. 模擬連線
      await coreDaemon.start(
        configPath: '/mock/test_config.yaml',
        selectedNode: node1.name,
      );

      // 2. 透過 SubscriptionEngine 選擇新節點
      await subscriptionEngine.selectNode(node2);

      // 3. 驗證 SubscriptionEngine 的選中節點與 CoreDaemon 保持高度一致
      expect(subscriptionEngine.selectedNode?.id, equals('2'));
      expect(coreDaemon.state.activeNodeName, equals('美國 洛杉磯 01'));
      expect(coreDaemon.state.isConnected, isTrue);

      // 4. 安全斷開
      await coreDaemon.stop();
      expect(coreDaemon.state.isDisconnected, isTrue);
    });
  });
}
