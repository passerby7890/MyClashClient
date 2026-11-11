// test/subscription_test.dart

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flclash_v2board_client/core/constants/app_constants.dart';
import 'package:flclash_v2board_client/business/subscription/node_model.dart';
import 'package:flclash_v2board_client/business/subscription/config_generator.dart';
import 'package:flclash_v2board_client/business/subscription/subscription_engine.dart';
import 'package:flclash_v2board_client/core/network/dio_client.dart';
import 'package:flclash_v2board_client/core/storage/secure_storage_service.dart';
import 'package:flclash_v2board_client/infrastructure/config/app_config_service.dart';
import 'package:flclash_v2board_client/infrastructure/core_daemon/core_daemon.dart';

void main() {
  group('階段三：核心守護與訂閱引擎單元測試', () {
    const sampleClashYaml = '''
proxies:
  - name: "🇭🇰 香港 01 | 專線"
    type: vmess
    server: 1.2.3.4
    port: 443
    uuid: "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
    alterId: 0
    cipher: auto
  - name: "🇯🇵 日本 02 | 影音"
    type: trojan
    server: 5.6.7.8
    port: 443
    password: "secret_trojan_password"
    sni: "jp.example.com"
''';

    test('1. NodeModel 國旗提取與零明文安全原則 (Zero-Plaintext Policy)', () {
      final node = NodeModel.fromProxyMap({
        'name': '🇭🇰 香港 01 | 專線',
        'type': 'vmess',
        'server': '198.51.100.1',
        'password': 'super_sensitive_token',
      }, id: 'node_1');

      expect(node.flagEmoji, equals('🇭🇰'));
      expect(node.protocol, equals('VMESS'));

      // 零明文驗證：toString() 不得洩露密碼與伺服器 IP
      final str = node.toString();
      expect(str, isNot(contains('super_sensitive_token')));
      expect(str, isNot(contains('198.51.100.1')));
      expect(str, contains('🇭🇰 香港 01 | 專線'));
    });

    test('2. ConfigGenerator 解析 YAML 並生成 Mihomo 設定檔', () {
      final nodes = ConfigGenerator.parseProxiesFromYaml(sampleClashYaml);
      expect(nodes.length, equals(2));
      expect(nodes[0].name, equals('🇭🇰 香港 01 | 專線'));
      expect(nodes[1].name, equals('🇯🇵 日本 02 | 影音'));

      final generatedYaml = ConfigGenerator.generateYaml(
        nodes: nodes,
        selectedNodeName: '🇭🇰 香港 01 | 專線',
      );

      expect(generatedYaml, contains('mixed-port: 7890'));
      expect(generatedYaml, contains('fake-ip'));
      expect(generatedYaml, contains('proxies:'));
      expect(generatedYaml, contains('proxy-groups:'));
      expect(generatedYaml, contains('PROXY'));
      expect(generatedYaml, contains('GLOBAL'));
      expect(generatedYaml, contains('GEOIP,CN,DIRECT'));
    });

    test('3. CoreDaemon 生命週期控制與狀態轉換', () async {
      final daemon = CoreDaemon();
      expect(daemon.state.isDisconnected, isTrue);

      final startFuture = daemon.start(
        configPath: '/mock/path.yaml',
        selectedNode: '🇭🇰 香港 01 | 專線',
      );
      expect(daemon.state.isConnecting, isTrue);

      await startFuture;
      expect(daemon.state.isConnected, isTrue);
      expect(daemon.state.activeNodeName, equals('🇭🇰 香港 01 | 專線'));

      await daemon.switchNode('🇯🇵 日本 02 | 影音');
      expect(daemon.state.activeNodeName, equals('🇯🇵 日本 02 | 影音'));

      await daemon.stop();
      expect(daemon.state.isDisconnected, isTrue);
    });

    test('4. ConfigGenerator 支援動態分流模式 (rule, global, direct)', () {
      final nodes = ConfigGenerator.parseProxiesFromYaml(sampleClashYaml);

      final globalYaml = ConfigGenerator.generateYaml(
        nodes: nodes,
        selectedNodeName: nodes.first.name,
        routingMode: 'global',
      );
      expect(globalYaml, contains('mode: global'));

      final directYaml = ConfigGenerator.generateYaml(
        nodes: nodes,
        selectedNodeName: nodes.first.name,
        routingMode: 'direct',
      );
      expect(directYaml, contains('mode: direct'));

      final ruleYaml = ConfigGenerator.generateYaml(
        nodes: nodes,
        selectedNodeName: nodes.first.name,
        routingMode: 'rule',
      );
      expect(ruleYaml, contains('mode: rule'));
    });

    test('5. NodeModel 地區名稱辨識與快速篩選', () {
      final hkNode = NodeModel.fromProxyMap({'name': '🇭🇰 香港 01 [專線]', 'type': 'trojan'}, id: '1');
      expect(hkNode.regionName, equals('香港'));

      final jpNode = NodeModel.fromProxyMap({'name': '🇯🇵 日本 01 [BGP]', 'type': 'ss'}, id: '2');
      expect(jpNode.regionName, equals('日本'));

      final usNode = NodeModel.fromProxyMap({'name': '🇺🇸 美國 01 [原生]', 'type': 'vmess'}, id: '3');
      expect(usNode.regionName, equals('美國'));

      final twNode = NodeModel.fromProxyMap({'name': '🇹🇼 台灣 01 [專線]', 'type': 'ss'}, id: '4');
      expect(twNode.regionName, equals('台灣'));
    });

    test('6. 機場髒訂閱節點過濾與重名消毒防護 (防護內核 Parse 拒載)', () {
      const dirtyYaml = '''
proxies:
  - name: "⚠️ 剩餘流量: 100GB | 到期: 2026-12-31"
    type: trojan
    server: 1.1.1.1
    port: 443
  - name: "🇭🇰 香港 01"
    type: vmess
    server: 2.2.2.2
    port: 443
  - name: "🇭🇰 香港 01"
    type: vmess
    server: 3.3.3.3
    port: 443
  - name: "無效節點缺少端口"
    type: ss
    server: 4.4.4.4
  - name: "無效節點無效端口"
    type: ss
    server: 4.4.4.4
    port: 0
  - name: "🇯🇵 日本 01\\r\\n帶換行"
    type: trojan
    server: 5.5.5.5
    port: 443
''';

      final nodes = ConfigGenerator.parseProxiesFromYaml(dirtyYaml);
      // 公告卡片 (剩餘流量/到期) 與 缺少/無效端口節點應被剔除
      expect(nodes.length, equals(3));
      expect(nodes[0].name, equals('🇭🇰 香港 01'));
      expect(nodes[1].name, equals('🇭🇰 香港 01 #2')); // 自動重名消毒
      expect(nodes[2].name, equals('🇯🇵 日本 01 帶換行')); // 換行符號已清洗

      // 生成之 YAML 中所有 proxy-groups 必須均為唯一名稱
      final generated = ConfigGenerator.generateYaml(
        nodes: nodes,
        selectedNodeName: nodes.first.name,
      );
      expect(generated, contains('"🇭🇰 香港 01"'));
      expect(generated, contains('"🇭🇰 香港 01 #2"'));
      expect(generated, isNot(contains('剩餘流量')));
    });

    test('7. 去 UA 第三方特徵化與 flag=meta 參數動態注入驗證', () async {
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

      // 1. 驗證 DioClient 預設 User-Agent 徹底去除第三方特徵，對齊 AppConstants.appVersion
      final defaultUa = dioClient.dio.options.headers['User-Agent'] as String?;
      final expectedPlatform = Platform.isMacOS ? 'macOS' : (Platform.isWindows ? 'Windows' : 'Android');
      expect(defaultUa, equals('TianheNetwork/${AppConstants.appVersion} ($expectedPlatform)'));
      expect(defaultUa, isNot(contains('Clash')));
      expect(defaultUa, isNot(contains('Meta')));

      // 2. 驗證缺少 flag 參數的訂閱 URL 自動追加 flag=meta
      const rawUrl1 = 'https://0n21.com/api/v1/client/subscribe?token=test_token_123';
      final resolved1 = await engine.resolveSubscribePathForTesting(customSubscribeUrl: rawUrl1);
      expect(resolved1, contains('flag=meta'));
      expect(resolved1, contains('token=test_token_123'));

      // 3. 驗證帶有舊版 flag=clash 參數的訂閱 URL 自動平滑升級為 flag=meta (以支援 VLESS/Reality 等現代協議)
      const rawUrl2 = 'https://0n21.com/api/v1/client/subscribe?token=test_token_456&flag=clash';
      final resolved2 = await engine.resolveSubscribePathForTesting(customSubscribeUrl: rawUrl2);
      expect(resolved2, contains('flag=meta'));
      expect(resolved2, isNot(contains('flag=clash')));

      // 4. 驗證已具備 flag=meta 的訂閱 URL 不會重複追加
      const rawUrl3 = 'https://0n21.com/api/v1/client/subscribe?token=test_token_789&flag=meta';
      final resolved3 = await engine.resolveSubscribePathForTesting(customSubscribeUrl: rawUrl3);
      expect(resolved3, contains('flag=meta'));
      expect('flag=meta'.allMatches(resolved3).length, equals(1));

      engine.dispose();
    });
  });
}
