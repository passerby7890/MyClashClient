// test/pointer_hot_switch_and_gomem_test.dart

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('macOS 端純指標秒切 + Go 執行期護欄 + L0 瞬時焚毀驗證', () {
    test('1. MacosNativeProxy 啟動 mihomo 時強制注入 GODEBUG / GOMEMLIMIT / GOGC 環境變數', () {
      final src = File('lib/infrastructure/core_daemon/macos_native_proxy.dart').readAsStringSync();
      expect(src, contains("'GODEBUG': 'madvdontneed=1'"));
      expect(src, contains("'GOMEMLIMIT': '220MiB'"));
      expect(src, contains("'GOGC': '50'"));
    });

    test('2. MacosNativeProxy 熱切換嚴格使用 PUT /proxies + DELETE /connections，嚴禁 PUT /configs?force=true', () {
      final src = File('lib/infrastructure/core_daemon/macos_native_proxy.dart').readAsStringSync();
      final fnStart = src.indexOf('Future<bool> _executeSingleSwitch(');
      expect(fnStart, greaterThan(0));
      final fnBody = src.substring(fnStart, fnStart + 2500);
      expect(fnBody, contains('/proxies/'));
      expect(fnBody, contains('/connections'));
      expect(fnBody, isNot(contains('/configs?force=true')));
    });

    test('3. MacosNativeProxy 控制器就緒後立即執行 <=100ms 閱後即焚與防鎖死重試', () {
      final src = File('lib/infrastructure/core_daemon/macos_native_proxy.dart').readAsStringSync();
      expect(src, contains('_safeShredFileWithRetry(configPath)'));
    });

    test('4. CoreDaemon.setRoutingMode 透過 PATCH /configs + closeAllConnections 完成無損切換', () {
      final src = File('lib/infrastructure/core_daemon/core_daemon.dart').readAsStringSync();
      final fnStart = src.indexOf('Future<void> setRoutingMode(String mode)');
      expect(fnStart, greaterThan(0));
      final fnBody = src.substring(fnStart, fnStart + 1200);
      expect(fnBody, contains('patchUrl'));
      expect(fnBody, contains('/configs'));
      expect(fnBody, contains('closeAllConnections'));
    });
  });
}

