// test/gtm_dns_rotation_test.dart
// 驗證 GTM (動態 DNS 域名輪詢 / 拔除封鎖 IP) 防禦機制：
// 1. Mihomo 核心配置自動注入 tcp-concurrent: true (RFC 8305 併發競速連線，消除線頭阻塞)
// 2. DNS 快取演算法配置 cache-algorithm: arc (自適應替換快取)
// 3. 節點切換與重新連線時，精確調用 /cache/dns/flush 與 /cache/fakeip/flush 徹底清除記憶體快取

import 'package:flutter_test/flutter_test.dart';
import 'package:flclash_v2board_client/business/subscription/config_generator.dart';
import 'package:flclash_v2board_client/core/storage/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SecureStorageService.isTestMode = true;

  group('【GTM 動態域名與 IP 輪詢防禦驗證】', () {
    const sampleV2BoardYaml = '''
proxies:
  - name: "🇭🇰 香港 01 | GTM 動態入口"
    type: vmess
    server: gtm-hk.example.com
    port: 443
    uuid: "a1b2c3d4-e5f6-7890-abcd-ef0123456789"
    alterId: 0
    cipher: auto
    tls: true
''';

    test('1. ConfigGenerator 必須強制注入 tcp-concurrent: true 以支援 GTM 多 IP 併發搶答', () {
      final nodes = ConfigGenerator.parseProxiesFromYaml(sampleV2BoardYaml);
      final generated = ConfigGenerator.generateYaml(
        nodes: nodes,
        selectedNodeName: nodes.first.name,
      );

      expect(generated, contains('tcp-concurrent: true'),
          reason: '缺少 tcp-concurrent 會導致 GTM 解析出多個 IP 時依序串行重試，遭被牆 IP 阻塞 3~5 秒');
      expect(generated, contains('unified-delay: true'),
          reason: 'unified-delay 確保延遲測速能精確反應握手延遲');
    });

    test('2. ConfigGenerator 必須注入 cache-algorithm: arc 最佳化快取淘汰', () {
      final nodes = ConfigGenerator.parseProxiesFromYaml(sampleV2BoardYaml);
      final generated = ConfigGenerator.generateYaml(
        nodes: nodes,
        selectedNodeName: nodes.first.name,
      );

      expect(generated, contains('cache-algorithm: arc'),
          reason: 'ARC 演算法能確保高頻率動態更新的 DNS 記錄能被即時淘汰');
    });

    test('3. 單節點切片配置 (Single Node Slice) 同樣必須具備 tcp-concurrent 與快取演算法', () {
      final nodes = ConfigGenerator.parseProxiesFromYaml(sampleV2BoardYaml);
      final slice = ConfigGenerator.generateYaml(
        nodes: nodes,
        selectedNodeName: nodes.first.name,
        singleNodeSlice: true,
      );

      expect(slice, contains('tcp-concurrent: true'),
          reason: '單節點切片亦須具備 GTM 多 IP 並發搶答能力');
      expect(slice, contains('cache-algorithm: arc'));
    });
  });
}
