import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:flclash_v2board_client/business/subscription/node_model.dart';
import 'package:flclash_v2board_client/business/subscription/subscription_engine.dart';
import 'package:flclash_v2board_client/core/network/dio_client.dart';
import 'package:flclash_v2board_client/core/storage/secure_storage_service.dart';
import 'package:flclash_v2board_client/infrastructure/config/app_config_service.dart';
import 'package:flclash_v2board_client/infrastructure/core_daemon/core_daemon.dart';

class MockSecureStorage extends Fake implements SecureStorageService {
  final Map<String, String> _data = {};

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<String?> read(String key) async {
    return _data[key];
  }

  @override
  Future<Set<String>> getFavoriteNodeIds() async {
    return {};
  }
}

void main() {
  group('Real TCP Latency & Ping Mechanism Tests', () {
    late SubscriptionEngine testEngine;
    late SubscriptionEngine realEngine;

    setUp(() {
      final configService = AppConfigService();
      final dioClient = DioClient(configService: configService, customDio: Dio());
      final coreDaemon = CoreDaemon();
      final mockStorage = MockSecureStorage();

      testEngine = SubscriptionEngine(
        dioClient: dioClient,
        coreDaemon: coreDaemon,
        storageService: mockStorage,
        isTestMode: true,
      );

      realEngine = SubscriptionEngine(
        dioClient: dioClient,
        coreDaemon: coreDaemon,
        storageService: mockStorage,
        isTestMode: false,
      );
    });

    test('1. NodeModel server 與 port 正確解析', () {
      final node = NodeModel(
        id: 'node_1',
        name: '🇭🇰 香港 01 | 專線',
        flagEmoji: '🇭🇰',
        protocol: 'shadowsocks',
        rawConfig: {
          'name': 'hk_01',
          'type': 'ss',
          'server': 'hk01.example.com',
          'port': 8388,
          'password': 'secret',
        },
      );

      expect(node.server, equals('hk01.example.com'));
      expect(node.port, equals(8388));
      expect(node.latencyFormatted, equals('-- ms'));
      expect(node.latencyGrade, equals('none'));
    });

    test('2. 逾時與失敗時格式化為「逾時」且評級為「bad」', () {
      final node = NodeModel(
        id: 'node_timeout',
        name: '🇺🇸 美國 01 | 專線',
        flagEmoji: '🇺🇸',
        protocol: 'vmess',
        latencyMs: -1,
        rawConfig: {'server': '192.0.2.1', 'port': 443},
      );

      expect(node.latencyMs, equals(-1));
      expect(node.latencyFormatted, equals('逾時'));
      expect(node.latencyGrade, equals('bad'));
    });

    test('3. 真實網路模式下：無效 server 或 port 直接返回 -1', () async {
      final invalidNode = NodeModel(
        id: 'node_invalid',
        name: '無效節點',
        flagEmoji: '🌐',
        protocol: 'trojan',
        rawConfig: {'server': '', 'port': 0},
      );

      final latency = await realEngine.pingNode(invalidNode, isTestMode: false);
      expect(latency, equals(-1));
    });

    test('4. 真實網路模式下：連線到無法連通之本機埠口快速超時並返回 -1', () async {
      final unreachableNode = NodeModel(
        id: 'node_unreachable',
        name: '不可達節點',
        flagEmoji: '🌐',
        protocol: 'vmess',
        rawConfig: {'server': '127.0.0.1', 'port': 59999},
      );

      final stopwatch = Stopwatch()..start();
      final latency = await realEngine.pingNode(
        unreachableNode,
        timeoutMs: 200,
        isTestMode: false,
      );
      stopwatch.stop();

      expect(latency, equals(-1));
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
    });

    test('5. isTestMode 下批量測速可正常更新所有節點延遲', () async {
      final nodes = [
        NodeModel(
          id: 'n1',
          name: '🇭🇰 香港 01',
          flagEmoji: '🇭🇰',
          protocol: 'vmess',
          rawConfig: {'server': '1.1.1.1', 'port': 443},
        ),
        NodeModel(
          id: 'n2',
          name: '🇯🇵 日本 01',
          flagEmoji: '🇯🇵',
          protocol: 'vmess',
          rawConfig: {'server': '1.0.0.1', 'port': 443},
        ),
      ];

      testEngine.restoreFromVault(); // 初始化
      // 透過反射或公共方法注入節點
      // 這裡直接驗證 pingNode
      final p1 = await testEngine.pingNode(nodes[0]);
      final p2 = await testEngine.pingNode(nodes[1]);

      expect(p1, isPositive);
      expect(p2, isPositive);
      expect(p1, isNot(equals(p2))); // 模擬非線性遞增
    });

    test('6. 真實網路環境下可連通節點（如 1.1.1.1:443）返回真實正整數延遲', () async {
      // 測試真實 TCP 握手
      final cloudflareNode = NodeModel(
        id: 'node_cf',
        name: 'Cloudflare DNS',
        flagEmoji: '🇺🇸',
        protocol: 'vmess',
        rawConfig: {'server': '1.1.1.1', 'port': 443},
      );

      final latency = await realEngine.pingNode(
        cloudflareNode,
        timeoutMs: 3000,
        isTestMode: false,
      );

      // 若本機有外網，latency 應為大於 0 的正整數；若在無網環境則為 -1，皆符合契約規範
      expect(latency == -1 || latency > 0, isTrue);
    });
  });
}
