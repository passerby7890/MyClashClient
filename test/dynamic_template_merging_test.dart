// test/dynamic_template_merging_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';
import 'package:flclash_v2board_client/business/subscription/config_generator.dart';
import 'package:flclash_v2board_client/business/subscription/node_model.dart';
import 'package:flclash_v2board_client/business/subscription/subscription_engine.dart';
import 'package:flclash_v2board_client/core/network/dio_client.dart';
import 'package:flclash_v2board_client/core/storage/secure_storage_service.dart';
import 'package:flclash_v2board_client/infrastructure/config/app_config_service.dart';
import 'package:flclash_v2board_client/infrastructure/core_daemon/core_daemon.dart';

class MockSecureStorage extends SecureStorageService {
  final Map<String, String> _data = {};

  @override
  Future<void> write(String key, String value) async => _data[key] = value;
  @override
  Future<String?> read(String key) async => _data[key];
  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<void> saveEncryptedNodes(String rawYaml) async => write('v2board_encrypted_nodes_vault', rawYaml);
  @override
  Future<String?> getEncryptedNodes() async => read('v2board_encrypted_nodes_vault');
  @override
  Future<void> deleteEncryptedNodes() async => delete('v2board_encrypted_nodes_vault');
}

/// 模擬生成 V2Board 伺服器端下發的完整 default.clash.yaml
String _generateMockV2BoardFullYaml() {
  final sb = StringBuffer();
  sb.writeln('port: 7890');
  sb.writeln('socks-port: 7891');
  sb.writeln('allow-lan: false');
  sb.writeln('mode: rule');
  sb.writeln('log-level: info');
  sb.writeln('external-controller: 127.0.0.1:9090');

  // 高水準 DNS 設置
  sb.writeln('dns:');
  sb.writeln('  enable: true');
  sb.writeln('  ipv6: false');
  sb.writeln('  default-nameserver:');
  sb.writeln('    - 223.5.5.5');
  sb.writeln('    - 119.29.29.29');
  sb.writeln('  proxy-server-nameserver:');
  sb.writeln('    - https://dns.alidns.com/dns-query');
  sb.writeln('    - 119.29.29.29');
  sb.writeln('  enhanced-mode: fake-ip');
  sb.writeln('  fake-ip-range: 198.18.0.1/16');
  sb.writeln('  fake-ip-filter:');
  sb.writeln('    - "*.lan"');
  sb.writeln('    - "+.stun.*"');
  sb.writeln('    - "time.*.com"');
  sb.writeln('    - "+.msftconnecttest.com"');
  sb.writeln('  nameserver:');
  sb.writeln('    - https://doh.pub/dns-query');
  sb.writeln('    - https://dns.alidns.com/dns-query');
  sb.writeln('  fallback:');
  sb.writeln('    - https://1.1.1.1/dns-query');
  sb.writeln('    - https://dns.google/dns-query');

  // 26 顆節點
  sb.writeln('proxies:');
  for (int i = 1; i <= 26; i++) {
    sb.writeln('  - name: "🇭🇰 香港 0$i | ANYTLS"');
    sb.writeln('    type: anytls');
    sb.writeln('    server: 104.21.1.$i');
    sb.writeln('    port: 443');
    sb.writeln('    uuid: 11111111-2222-3333-4444-5555555555$i');
    sb.writeln('    tls: true');
  }

  // 策略組：包含對 26 顆節點的引用與組間引用
  sb.writeln('proxy-groups:');
  sb.writeln('  - name: "🚀 節點選擇"');
  sb.writeln('    type: select');
  sb.writeln('    proxies:');
  for (int i = 1; i <= 26; i++) {
    sb.writeln('      - "🇭🇰 香港 0$i | ANYTLS"');
  }
  sb.writeln('      - DIRECT');

  sb.writeln('  - name: "🎬 國外媒體"');
  sb.writeln('    type: select');
  sb.writeln('    proxies:');
  sb.writeln('      - "🚀 節點選擇"');
  sb.writeln('      - "🇭🇰 香港 01 | ANYTLS"');
  sb.writeln('      - DIRECT');

  sb.writeln('  - name: "🐟 漏網之魚"');
  sb.writeln('    type: select');
  sb.writeln('    proxies:');
  sb.writeln('      - "🚀 節點選擇"');
  sb.writeln('      - DIRECT');

  // 自訂分流規則
  sb.writeln('rules:');
  sb.writeln('  - DOMAIN-SUFFIX,google.com,🚀 節點選擇');
  sb.writeln('  - DOMAIN-SUFFIX,youtube.com,🎬 國外媒體');
  sb.writeln('  - DOMAIN-SUFFIX,netflix.com,🎬 國外媒體');
  sb.writeln('  - DOMAIN-KEYWORD,openai,🚀 節點選擇');
  sb.writeln('  - DOMAIN-SUFFIX,baidu.com,DIRECT');
  sb.writeln('  - GEOIP,CN,DIRECT');
  sb.writeln('  - MATCH,🐟 漏網之魚');

  return sb.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('【動態範本融合 (Template Merging)】與單節點切片防崩潰驗證', () {
    late String v2boardYaml;
    late List<NodeModel> parsedNodes;

    setUp(() {
      v2boardYaml = _generateMockV2BoardFullYaml();
      parsedNodes = ConfigGenerator.parseProxiesFromYaml(v2boardYaml);
    });

    test('1. 驗證節點解析完整度 (26 顆節點均被正確識別)', () {
      expect(parsedNodes.length, equals(26));
      expect(parsedNodes.first.name, equals('🇭🇰 香港 01 | ANYTLS'));
      expect(parsedNodes.first.protocol.toLowerCase(), equals('anytls'));
      expect(parsedNodes.last.name, equals('🇭🇰 香港 026 | ANYTLS'));
    });

    test('2. 核心驗證：動態融合生成 config.yaml (單節點切片 + 策略組收斂重映射)', () {
      final selectedNode = parsedNodes[2]; // 香港 03
      final fusedYaml = ConfigGenerator.generateYaml(
        nodes: parsedNodes,
        selectedNodeName: selectedNode.name,
        routingMode: 'rule',
        singleNodeSlice: true,
        templateYaml: v2boardYaml,
      );

      final doc = loadYaml(fusedYaml) as YamlMap;

      // (1) 單節點切片：proxies 陣列中嚴格只有 1 顆選中節點！
      final proxiesList = doc['proxies'] as YamlList;
      expect(proxiesList.length, equals(1));
      expect(proxiesList[0]['name'], equals('🇭🇰 香港 03 | ANYTLS'));
      expect(proxiesList[0]['uuid'], contains('55555555553'));

      // (2) 策略組防崩潰清洗與重映射：不含任何懸空節點名稱！
      final proxyGroups = doc['proxy-groups'] as YamlList;
      expect(proxyGroups.isNotEmpty, isTrue);

      final groupNames = proxyGroups.map((g) => g['name'].toString()).toSet();
      // 確保 PROXY 與 GLOBAL 已安全補齊
      expect(groupNames.contains('PROXY'), isTrue);
      expect(groupNames.contains('GLOBAL'), isTrue);

      // 檢查每個策略組內引用的 proxies
      for (final group in proxyGroups) {
        final gProxies = (group['proxies'] as YamlList).map((e) => e.toString()).toList();
        expect(gProxies.isNotEmpty, isTrue, reason: '策略組 ${group['name']} proxies 不可為空');

        for (final p in gProxies) {
          final isSelectedNode = (p == selectedNode.name);
          final isGroupRef = groupNames.contains(p);
          final isKeyword = ['DIRECT', 'REJECT', 'PASS'].contains(p);

          expect(
            isSelectedNode || isGroupRef || isKeyword,
            isTrue,
            reason: '策略組 ${group['name']} 中存在未定義的懸空節點: $p (會導致 Mihomo 核心崩潰)',
          );
        }
      }

      // (3) DNS 完整繼承與高水準配置檢驗
      final dns = doc['dns'] as YamlMap;
      expect(dns['enable'], isTrue);
      expect(dns['enhanced-mode'], equals('fake-ip'));

      // 驗證 default-nameserver 100% 繼承
      final defNs = (dns['default-nameserver'] as YamlList).map((e) => e.toString()).toList();
      expect(defNs, containsAll(['223.5.5.5', '119.29.29.29']));

      // 驗證 proxy-server-nameserver 100% 繼承 (防止節點域名解析死鎖)
      final proxyServerNs = (dns['proxy-server-nameserver'] as YamlList).map((e) => e.toString()).toList();
      expect(proxyServerNs, containsAll(['https://dns.alidns.com/dns-query', '119.29.29.29']));

      // 驗證 fake-ip-filter 絕不包含 "*"
      final fakeIpFilter = (dns['fake-ip-filter'] as YamlList).map((e) => e.toString()).toList();
      expect(fakeIpFilter.contains('*'), isFalse, reason: 'fake-ip-filter 嚴禁出現 "*"！');
      expect(fakeIpFilter, contains('*.lan'));

      // (4) 驗證 Windows 桌面端規範：規則/全局模式下 TUN 預設關閉 (走 127.0.0.1:7890 系統代理)
      final tun = doc['tun'] as YamlMap;
      expect(tun['enable'], isFalse);
      expect(tun['stack'], equals('gvisor'));
      expect(tun['auto-route'], isTrue);
      expect(tun['auto-detect-interface'], isTrue);

      final sniffer = doc['sniffer'] as YamlMap;
      expect(sniffer['enable'], isTrue);

      // (5) 防 GitHub 啟動卡死配置
      expect(doc['geo-auto-update'], isFalse);
      expect(doc['geodata-mode'], isFalse);

      // (6) 自訂分流規則 100% 完整保留
      final rules = (doc['rules'] as YamlList).map((e) => e.toString()).toList();
      expect(rules, contains('DOMAIN-SUFFIX,google.com,🚀 節點選擇'));
      expect(rules, contains('DOMAIN-SUFFIX,youtube.com,🎬 國外媒體'));
      expect(rules, contains('DOMAIN-SUFFIX,netflix.com,🎬 國外媒體'));
      expect(rules, contains('DOMAIN-KEYWORD,openai,🚀 節點選擇'));
      expect(rules, contains('GEOIP,CN,DIRECT'));
      expect(rules, contains('MATCH,🐟 漏網之魚'));
    });

    test('3. 驗證無後端範本時，本地保底範本 (Fallback) 同樣達到高水準規格', () {
      final selectedNode = parsedNodes.first;
      final fallbackYaml = ConfigGenerator.generateYaml(
        nodes: parsedNodes,
        selectedNodeName: selectedNode.name,
        routingMode: 'rule',
        singleNodeSlice: true,
        templateYaml: null, // 無後端範本，觸發保底
      );

      final doc = loadYaml(fallbackYaml) as YamlMap;
      final dns = doc['dns'] as YamlMap;

      // 保底 DNS 也必須具備 default-nameserver 與 proxy-server-nameserver
      expect(dns['default-nameserver'], isNotNull);
      expect(dns['proxy-server-nameserver'], isNotNull);

      // 保底 fake-ip-filter 絕不包含 "*"
      final fakeIpFilter = (dns['fake-ip-filter'] as YamlList).map((e) => e.toString()).toList();
      expect(fakeIpFilter.contains('*'), isFalse);

      // Windows 桌面版保底 TUN 預設關閉 (走 7890 系統代理)
      expect(doc['tun']['enable'], isFalse);
      expect(doc['sniffer']['enable'], isTrue);
    });

    test('4. 驗證 SubscriptionEngine 冷啟動加密金庫還原與範本保存 SLA', () async {
      final mockStorage = MockSecureStorage();
      final mockConfigService = AppConfigService();
      final mockDioClient = DioClient(configService: mockConfigService);
      final mockCoreDaemon = CoreDaemon();

      // 先行寫入金庫 (模擬已登入並加密持久化過)
      await mockStorage.saveEncryptedNodes(v2boardYaml);

      final engine = SubscriptionEngine(
        dioClient: mockDioClient,
        coreDaemon: mockCoreDaemon,
        storageService: mockStorage,
      );

      // 執行從金庫冷啟動還原
      final restored = await engine.restoreFromVault();
      expect(restored, isTrue);
      expect(engine.nodes.length, equals(26));
      expect(engine.cachedYamlTemplate, equals(v2boardYaml));
      expect(engine.selectedNode, isNotNull);

      // 驗證登出清空金庫與範本
      await engine.clearVaultAndMemory();
      expect(engine.nodes.isEmpty, isTrue);
      expect(engine.cachedYamlTemplate, isNull);
      expect(await mockStorage.getEncryptedNodes(), isNull);
    });
  });
}
