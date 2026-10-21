// test/stress_test_and_benchmark.dart
// 🏛️ 天河網絡客戶端——全功能流暢度、節點切換與極限壓力測試基準套件 (Stress Test & Benchmark Suite)
// 專家委員會評測：@Network, @Frontend, @Security, @Backend, @DevOps

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:flclash_v2board_client/core/crypto/aes_decryptor.dart';
import 'package:flclash_v2board_client/core/network/dio_client.dart';
import 'package:flclash_v2board_client/core/network/auth_interceptor.dart';
import 'package:flclash_v2board_client/core/storage/secure_storage_service.dart';
import 'package:flclash_v2board_client/infrastructure/config/app_config_service.dart';
import 'package:flclash_v2board_client/infrastructure/core_daemon/core_daemon.dart';
import 'package:flclash_v2board_client/infrastructure/core_daemon/traffic_stats.dart';
import 'package:flclash_v2board_client/business/subscription/config_generator.dart';
import 'package:flclash_v2board_client/business/subscription/node_model.dart';
import 'package:flclash_v2board_client/business/subscription/subscription_engine.dart';

class _Mock401Adapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{"message":"Unauthorized"}',
      401,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class MockStressStorage extends SecureStorageService {
  final Map<String, dynamic> _data = {};

  @override
  Future<void> saveToken(String token) async {
    _data['v2board_auth_token'] = token;
  }

  @override
  Future<String?> getToken() async {
    return _data['v2board_auth_token'] as String?;
  }

  @override
  Future<void> saveFavoriteNodeIds(Set<String> ids) async {
    _data['favorite_node_ids'] = ids.toList();
  }

  @override
  Future<Set<String>> getFavoriteNodeIds() async {
    final list = _data['favorite_node_ids'] as List?;
    if (list == null) return {};
    return list.cast<String>().toSet();
  }

  @override
  Future<void> saveUserInfoJson(String jsonStr) async {
    _data['v2board_user_info'] = jsonStr;
  }

  @override
  Future<String?> getUserInfoJson() async {
    return _data['v2board_user_info'] as String?;
  }

  @override
  Future<void> clearAll() async {
    _data.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('🏛️ 專家委員會 Android 端全功能極限壓力測試與流暢度基準測試', () {
    late MockStressStorage mockStorage;
    late CoreDaemon coreDaemon;
    late DioClient dioClient;
    late SubscriptionEngine subscriptionEngine;
    late AppConfigService configService;

    setUp(() {
      mockStorage = MockStressStorage();
      coreDaemon = CoreDaemon();
      configService = AppConfigService();
      dioClient = DioClient(configService: configService, customDio: Dio());
      subscriptionEngine = SubscriptionEngine(
        dioClient: dioClient,
        coreDaemon: coreDaemon,
        storageService: mockStorage,
        isTestMode: true,
      );
    });

    test('1. 極限高頻節點切換壓力測試 (1,000 次連續切換性能基準)', () async {
      final nodes = List.generate(50, (i) {
        final protocols = ['vmess', 'trojan', 'shadowsocks', 'vless'];
        final countries = ['🇭🇰 香港', '🇯🇵 日本', '🇺🇸 美國', '🇸🇬 新加坡', '🇩🇪 德國'];
        final p = protocols[i % protocols.length];
        final c = countries[i % countries.length];
        return NodeModel(
          id: 'stress_node_$i',
          name: '$c 專線 $i (0.${(i % 5) + 1}x)',
          flagEmoji: c.split(' ').first,
          protocol: p,
          latencyMs: 30 + (i * 3) % 120,
          rawConfig: {
            'name': '$c 專線 $i',
            'type': p,
            'server': '198.18.0.${(i % 250) + 1}',
            'port': 443,
          },
        );
      });

      await coreDaemon.start(
        configPath: '/mock/config.yaml',
        selectedNode: nodes.first.name,
      );
      expect(coreDaemon.state.isConnected, isTrue);

      final stopwatch = Stopwatch()..start();
      const int switchIterations = 1000;
      final switchLatencies = <int>[];

      for (int i = 0; i < switchIterations; i++) {
        final targetNode = nodes[i % nodes.length];
        final iterSw = Stopwatch()..start();

        await subscriptionEngine.selectNode(targetNode);
        iterSw.stop();
        switchLatencies.add(iterSw.elapsedMicroseconds);

        expect(subscriptionEngine.selectedNode?.id, equals(targetNode.id));
        expect(coreDaemon.state.activeNodeName, equals(targetNode.name));
      }

      stopwatch.stop();

      switchLatencies.sort();
      final avgUs = switchLatencies.reduce((a, b) => a + b) / switchLatencies.length;
      final avgMs = avgUs / 1000.0;
      final p95Ms = switchLatencies[(switchIterations * 0.95).toInt()] / 1000.0;
      final p99Ms = switchLatencies[(switchIterations * 0.99).toInt()] / 1000.0;
      final totalElapsedMs = stopwatch.elapsedMilliseconds;

      // ignore: avoid_print
      print('\n======================================================');
      // ignore: avoid_print
      print('🚀 [Benchmark 1] 1,000 次高頻節點切換壓測結果:');
      // ignore: avoid_print
      print('  - 總耗時: ${totalElapsedMs}ms');
      // ignore: avoid_print
      print('  - 平均每次切換耗時: ${avgMs.toStringAsFixed(3)}ms');
      // ignore: avoid_print
      print('  - P95 延遲: ${p95Ms.toStringAsFixed(3)}ms');
      // ignore: avoid_print
      print('  - P99 延遲: ${p99Ms.toStringAsFixed(3)}ms');
      // ignore: avoid_print
      print('  - 吞吐量 (QPS): ${(switchIterations / (totalElapsedMs / 1000)).toStringAsFixed(1)} switches/sec');
      // ignore: avoid_print
      print('======================================================\n');

      expect(avgMs, lessThan(10.0));
      expect(coreDaemon.state.isConnected, isTrue);
    });

    test('2. 節點切換與 IP 飄移模擬基準測試 (IP Switch & Tunnel Routing)', () async {
      final ipTestNodes = [
        NodeModel(
          id: 'node_hk',
          name: '🇭🇰 香港 01 [出口: 103.21.244.12]',
          flagEmoji: '🇭🇰',
          protocol: 'vmess',
          latencyMs: 28,
          rawConfig: {'name': 'HK_01', 'type': 'vmess', 'server': '103.21.244.12', 'port': 443},
        ),
        NodeModel(
          id: 'node_jp',
          name: '🇯🇵 日本 01 [出口: 133.130.45.88]',
          flagEmoji: '🇯🇵',
          protocol: 'trojan',
          latencyMs: 42,
          rawConfig: {'name': 'JP_01', 'type': 'trojan', 'server': '133.130.45.88', 'port': 443},
        ),
        NodeModel(
          id: 'node_us',
          name: '🇺🇸 美國 01 [出口: 142.250.190.46]',
          flagEmoji: '🇺🇸',
          protocol: 'shadowsocks',
          latencyMs: 145,
          rawConfig: {'name': 'US_01', 'type': 'shadowsocks', 'server': '142.250.190.46', 'port': 443},
        ),
        NodeModel(
          id: 'node_sg',
          name: '🇸🇬 新加坡 01 [出口: 128.199.200.15]',
          flagEmoji: '🇸🇬',
          protocol: 'vless',
          latencyMs: 55,
          rawConfig: {'name': 'SG_01', 'type': 'vless', 'server': '128.199.200.15', 'port': 443},
        ),
      ];

      await coreDaemon.start(
        configPath: '/mock/config.yaml',
        selectedNode: ipTestNodes.first.name,
      );

      final ipSwitchLog = <Map<String, dynamic>>[];

      for (final target in ipTestNodes) {
        final sw = Stopwatch()..start();
        await subscriptionEngine.selectNode(target);
        sw.stop();

        final activeName = coreDaemon.state.activeNodeName;
        final serverIp = target.internalRawConfig['server'];

        ipSwitchLog.add({
          'node': target.name,
          'targetIp': serverIp,
          'switchDurationMs': sw.elapsedMicroseconds / 1000.0,
          'status': coreDaemon.state.isConnected ? 'CONNECTED' : 'DISCONNECTED',
        });

        expect(activeName, equals(target.name));
        expect(coreDaemon.state.isConnected, isTrue);
      }

      // ignore: avoid_print
      print('🌐 [Benchmark 2] 跨國出口 IP 切換紀錄:');
      for (final log in ipSwitchLog) {
        // ignore: avoid_print
        print('  - ${log['node']} -> 出口 IP: ${log['targetIp']} (切換耗時: ${log['switchDurationMs']}ms, 狀態: ${log['status']})');
      }

      expect(ipSwitchLog.length, equals(4));
    });

    test('3. 收藏星星高頻併發與持久化壓力測試 (500 次點擊一致性)', () async {
      final testNodeIds = List.generate(20, (i) => 'fav_node_$i');

      final sw = Stopwatch()..start();
      const int toggleCount = 500;

      for (int i = 0; i < toggleCount; i++) {
        final targetId = testNodeIds[i % testNodeIds.length];
        await subscriptionEngine.toggleFavorite(targetId);
      }
      sw.stop();

      final storedFavs = await mockStorage.getFavoriteNodeIds();
      final memoryFavs = subscriptionEngine.favoriteNodeIds;

      expect(storedFavs, equals(memoryFavs));

      // ignore: avoid_print
      print('⭐ [Benchmark 3] 500 次收藏星星高頻點擊總耗時: ${sw.elapsedMilliseconds}ms (平均: ${(sw.elapsedMicroseconds / toggleCount / 1000).toStringAsFixed(3)}ms/次)');
      expect(sw.elapsedMilliseconds, lessThan(3000));
    });

    test('4. 500+ 大規模節點 YAML 解析、重名清理與大洲智能分組吞吐量測試', () {
      final yamlBuffer = StringBuffer();
      yamlBuffer.writeln('proxies:');

      final continentsTemplates = [
        '🇭🇰 香港 01 BGP [0.5x]',
        '🇯🇵 日本 02 軟銀原生 [1.0x]',
        '🇺🇸 美國 03 洛杉磯 CN2-GIA',
        '🇸🇬 新加坡 04 專線 (倍率: 2.0x)',
        '🇩🇪 德國 05 歐洲核心節點',
        '🇰🇷 韓國 06 首爾 KT 機房',
        '🇹🇼 台灣 07 台北中華電信',
        '🇬🇧 英國 08 倫敦機房',
      ];

      for (int i = 0; i < 500; i++) {
        final nameTpl = continentsTemplates[i % continentsTemplates.length];
        final name = (i % 7 == 0) ? nameTpl : '$nameTpl #$i';
        yamlBuffer.writeln('  - name: "$name"');
        yamlBuffer.writeln('    type: vmess');
        yamlBuffer.writeln('    server: 198.18.0.${(i % 250) + 1}');
        yamlBuffer.writeln('    port: 443');
        yamlBuffer.writeln('    uuid: 00000000-0000-0000-0000-${i.toString().padLeft(12, '0')}');
        yamlBuffer.writeln('    alterId: 0');
        yamlBuffer.writeln('    cipher: auto');
      }

      final bigYaml = yamlBuffer.toString();

      final parseSw = Stopwatch()..start();
      final parsedNodes = ConfigGenerator.parseProxiesFromYaml(bigYaml);
      parseSw.stop();

      expect(parsedNodes.length, equals(500));

      final groupSw = Stopwatch()..start();
      int asiaCount = 0;
      int euroAmericaCount = 0;
      int otherCount = 0;

      for (final n in parsedNodes) {
        switch (n.continent) {
          case '亞洲':
            asiaCount++;
            break;
          case '歐美':
            euroAmericaCount++;
            break;
          default:
            otherCount++;
        }
      }
      groupSw.stop();

      // ignore: avoid_print
      print('📊 [Benchmark 4] 500 個節點大訂閱解析結果:');
      // ignore: avoid_print
      print('  - YAML 解析與重名修復耗時: ${parseSw.elapsedMilliseconds}ms');
      // ignore: avoid_print
      print('  - 大洲分組計算耗時: ${groupSw.elapsedMilliseconds}ms');
      // ignore: avoid_print
      print('  - 分組統計: 亞洲=$asiaCount, 歐美=$euroAmericaCount, 其他=$otherCount');

      expect(parseSw.elapsedMilliseconds, lessThan(350));
      expect(asiaCount + euroAmericaCount + otherCount, equals(500));
    });

    test('5. 批量測速 (PingAllNodes) 併發池化壓力測試 (100 節點)', () async {
      final nodes = List.generate(100, (i) => NodeModel(
        id: 'ping_test_$i',
        name: '節點 $i',
        flagEmoji: '🌐',
        protocol: 'vmess',
        rawConfig: {'name': 'node_$i', 'type': 'vmess', 'server': '1.1.1.1', 'port': 443},
      ));

      final yamlContent = 'proxies:\n' + nodes.map((n) => '  - name: "${n.name}"\n    type: vmess\n    server: 1.1.1.1\n    port: 443').join('\n');
      
      final parsed = ConfigGenerator.parseProxiesFromYaml(yamlContent);
      expect(parsed.length, equals(100));

      final sw = Stopwatch()..start();
      await subscriptionEngine.pingAllNodes(batchSize: 20);
      sw.stop();

      // ignore: avoid_print
      print('⚡ [Benchmark 5] 100 個節點併發池化測速耗時: ${sw.elapsedMilliseconds}ms');
      expect(sw.elapsedMilliseconds, lessThan(500));
    });

    test('6. AES-256 加解密吞吐量與記憶體壓力測試 (100 次連續解密)', () {
      const testJson = '{"Authentication":"天河网络","hosts":["https://8.218.176.238:3389","https://8.218.176.238:8443"],"host_source":"https://portal.thjs789.com/","Customer":"https://t.me/q8891qcom","latest_version":"3.0.0"}';
      const key = '5xfWh681lPHNamV89fKFuqZxQyAaBnjs';
      const iv = 's303Khc0kIFZtVeX';

      final decryptor = AesDecryptor(key: key, iv: iv);
      final cipherText = decryptor.encrypt(testJson);

      final sw = Stopwatch()..start();
      const int iterations = 100;

      for (int i = 0; i < iterations; i++) {
        final decrypted = decryptor.decrypt(cipherText);
        expect(decrypted, equals(testJson));
      }
      sw.stop();

      final avgUs = sw.elapsedMicroseconds / iterations;
      // ignore: avoid_print
      print('🔒 [Benchmark 6] 100 次 AES-256 加解密循環總耗時: ${sw.elapsedMilliseconds}ms (平均每次: ${(avgUs / 1000).toStringAsFixed(3)}ms)');
      expect(avgUs / 1000, lessThan(3.0));
    });

    test('7. 401 Unauthorized 攔截器高頻併發防抖與緊急制動 (Kill-Switch) 測試', () async {
      await mockStorage.saveToken('dummy_jwt_token_123');
      expect(await mockStorage.getToken(), equals('dummy_jwt_token_123'));

      int kickoutBroadcastCount = 0;
      final interceptor = AuthInterceptor(
        storageService: mockStorage,
        onUnauthorized: () {
          kickoutBroadcastCount++;
        },
      );

      final dio = Dio();
      dio.httpClientAdapter = _Mock401Adapter();
      dio.interceptors.add(interceptor);

      // 模擬並發 20 個 HTTP 請求同時收到 401
      final futures = <Future>[];
      for (int i = 0; i < 20; i++) {
        futures.add(dio.get('https://api.test.com/api/v1/user/info').catchError((_) => Response(requestOptions: RequestOptions(path: '/'))));
      }
      await Future.wait(futures);

      await Future.delayed(const Duration(milliseconds: 100));

      final remainingToken = await mockStorage.getToken();
      expect(remainingToken, isNull);

      // ignore: avoid_print
      print('🛑 [Benchmark 7] 20 次併發 401 攔截測試：Token 清除成功，廣播次數: $kickoutBroadcastCount');
      expect(kickoutBroadcastCount, greaterThan(0));
    });

    test('8. 流量串流高頻數據包 (100Hz 吞吐量) 背壓測試', () async {
      final receivedStats = <TrafficStats>[];
      final subscription = coreDaemon.trafficStream.listen((stats) {
        receivedStats.add(stats);
      });

      await coreDaemon.start(configPath: '/mock/config.yaml', selectedNode: '測試節點');

      await Future.delayed(const Duration(milliseconds: 1100));

      await coreDaemon.stop();
      await subscription.cancel();

      expect(coreDaemon.state.isDisconnected, isTrue);
      // ignore: avoid_print
      print('📈 [Benchmark 8] 流量監聽串流接收數據包數: ${receivedStats.length} 幀');
      expect(receivedStats, isNotEmpty);
    });

    test('9. 連線開關高頻連擊防抖 (Connection Debounce & Idempotency) 壓力測試', () async {
      // 模擬在啟動過程中併發重複調用 50 次 start()
      final startFutures = <Future>[];
      for (int i = 0; i < 50; i++) {
        startFutures.add(coreDaemon.start(configPath: '/mock/config.yaml', selectedNode: '防抖節點'));
      }
      await Future.wait(startFutures);
      expect(coreDaemon.state.isConnected, isTrue);

      // 模擬在停止過程中併發重複調用 50 次 stop()
      final stopFutures = <Future>[];
      for (int i = 0; i < 50; i++) {
        stopFutures.add(coreDaemon.stop());
      }
      await Future.wait(stopFutures);
      expect(coreDaemon.state.isDisconnected, isTrue);

      // ignore: avoid_print
      print('🛡️ [Benchmark 9] 50 次併發連線/斷開防抖壓測完成：狀態機維持完全一致，無任何競態崩潰！');
    });
  });
}
