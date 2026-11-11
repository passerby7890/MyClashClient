// test/rust_bridge_ffi_test.dart

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flclash_v2board_client/business/subscription/node_model.dart';
import 'package:flclash_v2board_client/core/crypto/aes_decryptor.dart';
import 'package:flclash_v2board_client/core/rust/tianhe_rust_bridge.dart';

void main() {
  group('🦀 macOS Rust 原生引擎 (libtianhe_rust v3.4.0) C-ABI 與 5 大強制修正全鏈路測試', () {
    test('1. 引擎載入初始化與版號驗證 (v3.4.0)', () {
      final ok = TianheRustBridge.instance.init();
      expect(ok, isTrue, reason: '應能自動載入 rust_core/target/release/ 下的動態庫');
      expect(TianheRustBridge.instance.isAvailable, isTrue);
      expect(TianheRustBridge.instance.getEngineVersion(), equals('3.4.0'));
    });

    test('2. 【強制修正 1】Dart AesDecryptor 與 Rust VaultCrypto 位元組級加密互通驗證', () async {
      const sampleJson = '{"api_domain":"https://8.218.176.238:3389","latest_version":"3.4.0","min_version":"3.0.0"}';

      final dartCipher = AesDecryptor.encryptDefault(sampleJson);
      final rustPlain = await TianheRustBridge.instance.decryptConfig(dartCipher);
      expect(rustPlain, equals(sampleJson));

      final rustCipher = await TianheRustBridge.instance.encryptConfig(sampleJson);
      expect(rustCipher, isNotNull);
      final dartPlain = AesDecryptor.decryptDefault(rustCipher!);
      expect(dartPlain, equals(sampleJson));
    });

    test('3. 【強制修正 4 + UI 零機密】YamlEngine 記憶體隔離與 L0 單節點切片閱後即焚', () async {
      const sampleYaml = '''
proxies:
  - name: "🇸🇬 新加坡 01 | VLESS"
    type: vless
    server: 198.51.100.42
    port: 443
    uuid: "top-secret-uuid-9999"
  - name: "🇯🇵 日本 02 | Trojan"
    type: trojan
    server: 203.0.113.88
    port: 443
    password: "super-secret-password"
proxy-groups:
  - name: "天河網絡"
    type: select
    proxies:
      - "🇸🇬 新加坡 01 | VLESS"
      - "🇯🇵 日本 02 | Trojan"
rules:
  - DOMAIN-SUFFIX,github.com,天河網絡
  - MATCH,DIRECT
''';

      final descriptors = await TianheRustBridge.instance.parseYamlToVault(sampleYaml);
      expect(descriptors, isNotNull);
      expect(descriptors!.length, equals(2));

      final safeNodes = descriptors.map(NodeModel.fromRustDescriptor).toList();
      expect(safeNodes[0].rustVaultIndex, equals(0));
      expect(safeNodes[0].name, equals('🇸🇬 新加坡 01 | VLESS'));
      expect(safeNodes[0].protocol, equals('VLESS'));
      expect(safeNodes[0].countryCode, equals('SG'));
      expect(safeNodes[0].flagEmoji, equals('🇸🇬'));

      expect(safeNodes[0].internalRawConfig, isEmpty);
      expect(safeNodes[0].server, isNull);
      expect(safeNodes[0].port, isNull);

      final cipher = await TianheRustBridge.instance.encryptConfig(sampleYaml);
      final encDescriptors = await TianheRustBridge.instance.parseYamlToVault('RUST_ENC:$cipher');
      expect(encDescriptors?.length, equals(2));

      final tempDir = Directory.systemTemp.createTempSync('tianhe_mac_l0_test_');
      final l0Path = '${tempDir.path}${Platform.pathSeparator}config.yaml';

      try {
        final prepared = await TianheRustBridge.instance.prepareL0Config(
          nodeId: 0,
          routingMode: 'rule',
          outputPath: l0Path,
          secret: 'unit_test_secret',
        );
        expect(prepared, isTrue);

        final generated = File(l0Path).readAsStringSync();
        expect(generated, contains('198.51.100.42'));
        expect(generated, contains('DOMAIN-SUFFIX,github.com,天河網絡'));
        expect(generated, isNot(contains('203.0.113.88')));
        expect(generated, isNot(contains('super-secret-password')));

        final shredded = await TianheRustBridge.instance.shredFile(l0Path);
        expect(shredded, isTrue);
        expect(File(l0Path).existsSync(), isFalse);
      } finally {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      }
    });

    test('4. 【強制修正 2 & 5】Tokio 50路並發測速 (無IP參數洩漏 + Isolate.run 執行)', () async {
      final serverSocket = await ServerSocket.bind('127.0.0.1', 0);
      final port = serverSocket.port;
      final sub = serverSocket.listen((socket) => socket.destroy());

      try {
        final yaml = '''
proxies:
  - name: "LocalPingTarget"
    type: ss
    server: 127.0.0.1
    port: $port
''';
        await TianheRustBridge.instance.parseYamlToVault(yaml);

        final pingResults = await TianheRustBridge.instance.batchPingVaultNodes(timeoutMs: 1500);
        expect(pingResults, isNotNull);
        expect(pingResults!.length, equals(1));
        expect(pingResults[0].id, equals(0));
        expect(pingResults[0].latency, greaterThanOrEqualTo(1));
        expect(pingResults[0].latency, lessThan(1000));
      } finally {
        await sub.cancel();
        await serverSocket.close();
      }
    });
  });
}

