// test/macos_native_proxy_test.dart

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flclash_v2board_client/infrastructure/core_daemon/macos_native_proxy.dart';
import 'package:flclash_v2board_client/infrastructure/core_daemon/traffic_stats.dart';

void main() {
  group('🍎【macOS 原生代理服務與 Mihomo 內核驅動驗證測試】', () {
    test('1. MacosNativeProxy 單例與預設狀態驗證', () {
      final service = MacosNativeProxy.instance;
      expect(service, isNotNull);
      expect(service.isCoreRunning, isFalse);
      expect(service.isProxyEnabled, isFalse);
      expect(service.secret.isNotEmpty, isTrue);
    });

    test('2. 流量數據模型 (TrafficStats) 解析與 SSE JSON 格式對齊驗證', () {
      const sampleJson = '{"up":1048576,"down":5242880,"upTotal":20971520,"downTotal":104857600}';
      final map = jsonDecode(sampleJson) as Map<String, dynamic>;

      final stats = TrafficStats(
        upSpeed: (map['up'] as num).toInt(),
        downSpeed: (map['down'] as num).toInt(),
        totalUp: (map['upTotal'] as num).toInt(),
        totalDown: (map['downTotal'] as num).toInt(),
      );

      expect(stats.upSpeed, equals(1048576));
      expect(stats.downSpeed, equals(5242880));
      expect(stats.upSpeedFormatted, equals('1.00 MB/s'));
      expect(stats.downSpeedFormatted, equals('5.00 MB/s'));
      expect(stats.totalUpFormatted, equals('20.0 MB'));
      expect(stats.totalDownFormatted, equals('100.0 MB'));
    });

    test('3. 管理員權限模擬與 TUN 模式就緒驗證', () async {
      final service = MacosNativeProxy.instance;

      MacosNativeProxy.mockIsAdmin = true;
      expect(await service.isRunningAsAdmin(), isTrue);

      MacosNativeProxy.mockIsAdmin = false;
      expect(await service.isRunningAsAdmin(), isFalse);

      MacosNativeProxy.mockIsAdmin = null;

      MacosNativeProxy.mockIsWintun = true;
      expect(await service.isWintunAvailable(), isTrue);
      MacosNativeProxy.mockIsWintun = null;
    });

    test('4. 核心二進位路徑定位與安全斷線防網斷機制', () async {
      final service = MacosNativeProxy.instance;
      final path = service.getMihomoExecutablePath();
      expect(path, isNotEmpty);
      expect(path.contains('tianhe_engine') || path.contains('mihomo'), isTrue);

      // 執行 stopCore
      await service.stopCore();
      expect(service.isProxyEnabled, isFalse);
      expect(service.isCoreRunning, isFalse);
    });
  });
}
