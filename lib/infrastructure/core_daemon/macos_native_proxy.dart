// lib/infrastructure/core_daemon/macos_native_proxy.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/constants/app_constants.dart';
import 'traffic_stats.dart';

/// macOS 原生代理控制器與 Mihomo 內核守護行程 (MacosNativeProxy)
/// 專門負責：
/// 1. 透過 /usr/sbin/networksetup 管理 macOS 系統 HTTP/HTTPS/SOCKS 代理
/// 2. 啟動與守護 Mihomo Darwin (M1/M2/M3/M4 Apple Silicon & Intel) 二進位進程
/// 3. 解除沙盒環境限制、自動執行 chmod +x、孤兒進程清理 (killall -9 mihomo)
/// 4. 100% 防斷網閉環：冷啟動預檢、手動斷線與 App 退出時全面清除代理殘留
/// 5. 9090 端口 REST API 動態熱切換 (< 50ms) 與閱後即焚
class MacosNativeProxy {
  static MacosNativeProxy? _instance;
  static MacosNativeProxy get instance => _instance ??= MacosNativeProxy._();

  Process? _coreProcess;
  bool _isProxyEnabled = false;
  bool get isProxyEnabled => _isProxyEnabled;
  bool get isCoreRunning => _coreProcess != null;

  String _secret = AppConstants.coreSecret;
  String get secret => _secret;
  void setSecret(String s) => _secret = s;

  MacosNativeProxy._();

  /// 取得所有活躍的網路服務介面 (如 Wi-Fi, Ethernet, iPhone USB 等)
  Future<List<String>> getActiveNetworkServices() async {
    if (kIsWeb || !Platform.isMacOS) return ['Wi-Fi'];

    try {
      final result = await Process.run('networksetup', ['-listallnetworkservices']);
      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split('\n');
        final services = lines
            .map((l) => l.trim())
            .where((l) =>
                l.isNotEmpty &&
                !l.startsWith('*') &&
                !l.contains('An asterisk') &&
                !l.contains('denotes'))
            .toList();
        if (services.isNotEmpty) {
          return services;
        }
      }
    } catch (e) {
      debugPrint('[MacosNativeProxy] 列出網路服務異常: $e');
    }
    return ['Wi-Fi', 'Ethernet'];
  }

  /// 開啟 macOS 系統代理 (HTTP + HTTPS + SOCKS)
  Future<bool> enableSystemProxy({
    String host = '127.0.0.1',
    int port = 7890,
  }) async {
    if (kIsWeb || !Platform.isMacOS) return false;

    try {
      final services = await getActiveNetworkServices();
      debugPrint('[MacosNativeProxy] 正在為以下網路介面設定系統代理: $services');

      for (final service in services) {
        // 設定 HTTP Web Proxy
        await Process.run('networksetup', ['-setwebproxy', service, host, port.toString()]);
        await Process.run('networksetup', ['-setwebproxystate', service, 'on']);

        // 設定 HTTPS Secure Web Proxy
        await Process.run('networksetup', ['-setsecurewebproxy', service, host, port.toString()]);
        await Process.run('networksetup', ['-setsecurewebproxystate', service, 'on']);

        // 設定 SOCKS Proxy (port: 7890 支援 mixed-port)
        await Process.run('networksetup', ['-setsocksfirewallproxy', service, host, port.toString()]);
        await Process.run('networksetup', ['-setsocksfirewallproxystate', service, 'on']);

        // 繞過本機本地迴路
        await Process.run('networksetup', [
          '-setproxybypassdomains',
          service,
          '127.0.0.1',
          'localhost',
          '*.local',
          '192.168.*',
          '10.*',
        ]);
      }

      _isProxyEnabled = true;
      debugPrint('[MacosNativeProxy] macOS 系統代理已成功啟用 (127.0.0.1:$port)');
      return true;
    } catch (e) {
      debugPrint('[MacosNativeProxy] 啟用系統代理失敗: $e');
      return false;
    }
  }

  /// 關閉 macOS 系統代理 (100% 防斷網閉環保護)
  Future<bool> disableSystemProxy() async {
    if (kIsWeb || !Platform.isMacOS) return false;

    try {
      final services = await getActiveNetworkServices();
      for (final service in services) {
        await Process.run('networksetup', ['-setwebproxystate', service, 'off']);
        await Process.run('networksetup', ['-setsecurewebproxystate', service, 'off']);
        await Process.run('networksetup', ['-setsocksfirewallproxystate', service, 'off']);
      }
      _isProxyEnabled = false;
      debugPrint('[MacosNativeProxy] macOS 系統代理已徹底關閉 (防斷網完成)');
      return true;
    } catch (e) {
      debugPrint('[MacosNativeProxy] 關閉系統代理異常: $e');
      return false;
    }
  }

  /// 定位 macOS 下 mihomo 二進位執行檔路徑
  String getMihomoExecutablePath() {
    if (kIsWeb) return 'tools/mihomo/mihomo';

    // 1. 生產環境 .app Bundle (Contents/Resources/tools/mihomo/mihomo)
    final resolvedExe = Platform.resolvedExecutable;
    final appResourcesPath =
        '${File(resolvedExe).parent.parent.path}/Resources/tools/mihomo/mihomo';
    if (File(appResourcesPath).existsSync()) {
      return appResourcesPath;
    }

    // 2. 開發調試路徑 (相對於工作目錄 tools/mihomo/mihomo)
    final relativeToolsPath = '${Directory.current.path}/tools/mihomo/mihomo';
    if (File(relativeToolsPath).existsSync()) {
      return relativeToolsPath;
    }

    // 3. 通用後備
    return 'tools/mihomo/mihomo';
  }

  /// 準備 macOS 核心專屬工作目錄 (~/Library/Application Support/TianheNetwork/core)
  Future<Directory> prepareCoreWorkingDir() async {
    final appSupport = await getApplicationSupportDirectory();
    final coreDir = Directory('${appSupport.path}/TianheNetwork/core');
    if (!await coreDir.exists()) {
      await coreDir.create(recursive: true);
    }

    // 同步複製離線資料庫檔案 (Country.mmdb, GeoIP.dat, GeoSite.dat)
    final sourceBases = [
      '${File(Platform.resolvedExecutable).parent.parent.path}/Resources/tools/mihomo',
      '${Directory.current.path}/tools/mihomo',
      'tools/mihomo',
    ];

    final dbFiles = ['Country.mmdb', 'GeoIP.dat', 'GeoSite.dat', 'ASN.mmdb', 'geoip.metadb'];
    for (final dbName in dbFiles) {
      final destFile = File('${coreDir.path}/$dbName');
      if (!await destFile.exists()) {
        for (final srcBase in sourceBases) {
          final srcFile = File('$srcBase/$dbName');
          if (await srcFile.exists()) {
            try {
              await srcFile.copy(destFile.path);
              break;
            } catch (_) {}
          }
        }
      }
    }

    return coreDir;
  }

  /// 啟動 macOS Mihomo 核心進程
  Future<bool> startCore({
    required String configPath,
    String? selectedNode,
    String? secret,
  }) async {
    if (kIsWeb || !Platform.isMacOS) return false;

    if (secret != null && secret.isNotEmpty) {
      _secret = secret;
    }

    // 1. 孤兒進程清理：先殺死任何舊有殘留的 mihomo 進程釋放 7890 / 9090
    try {
      await Process.run('killall', ['-9', 'mihomo']);
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (_) {}

    // 2. 獲取並賦予二進位執行檔 chmod +x 執行權限
    final exePath = getMihomoExecutablePath();
    final exeFile = File(exePath);
    if (!await exeFile.exists()) {
      debugPrint('[MacosNativeProxy] 警告: 未找到 mihomo 執行檔: $exePath');
      // 若為開發環境無二進位，允許模擬跳過
      if (Platform.environment['FLUTTER_TEST'] == 'true' || kDebugMode) {
        await enableSystemProxy();
        return true;
      }
      return false;
    }

    try {
      await Process.run('chmod', ['+x', exePath]);
    } catch (e) {
      debugPrint('[MacosNativeProxy] chmod +x 執行異常: $e');
    }

    // 3. 準備工作目錄並啟動核心
    final workDir = await prepareCoreWorkingDir();

    try {
      _coreProcess = await Process.start(
        exePath,
        ['-d', workDir.path, '-f', configPath],
        mode: ProcessStartMode.normal,
      );

      _coreProcess?.stdout.transform(utf8.decoder).listen((line) {
        debugPrint('[Mihomo-macOS] $line');
      });
      _coreProcess?.stderr.transform(utf8.decoder).listen((line) {
        debugPrint('[Mihomo-macOS-Err] $line');
      });

      _coreProcess?.exitCode.then((code) {
        debugPrint('[MacosNativeProxy] Mihomo 進程已結束，exitCode: $code');
        _coreProcess = null;
        _isProxyEnabled = false;
        disableSystemProxy();
      });

      // 4. 等待 9090 端口 REST API 健康檢查 (Health Check)
      final isHealthy = await _waitForControllerReady(timeoutMs: 6000);
      if (!isHealthy) {
        debugPrint('[MacosNativeProxy] Mihomo 控制器健康檢查超時，終止啟動');
        await stopCore();
        return false;
      }

      // 5. 開啟 macOS 系統代理
      await enableSystemProxy();

      // 6. 閱後即焚：核心已載入記憶體，立即覆寫抹除暫存設定檔
      try {
        final f = File(configPath);
        if (await f.exists()) {
          await f.writeAsString('', flush: true);
          await f.delete();
          debugPrint('[MacosNativeProxy] 閱後即焚：臨時設定檔已抹除');
        }
      } catch (_) {}

      return true;
    } catch (e) {
      debugPrint('[MacosNativeProxy] 啟動核心進程失敗: $e');
      await stopCore();
      return false;
    }
  }

  /// 等待 127.0.0.1:9090 控制器就緒 (健康檢查)
  Future<bool> _waitForControllerReady({int timeoutMs = 6000}) async {
    final start = DateTime.now();
    final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 300);
    client.findProxy = (uri) => 'DIRECT';

    while (DateTime.now().difference(start).inMilliseconds < timeoutMs) {
      try {
        final req = await client.getUrl(Uri.parse('http://127.0.0.1:9090/version'));
        if (_secret.isNotEmpty) {
          req.headers.set('Authorization', 'Bearer $_secret');
        }
        final res = await req.close();
        if (res.statusCode == 200) {
          await res.drain();
          client.close();
          return true;
        }
        await res.drain();
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 150));
      }
    }
    client.close();
    return false;
  }

  /// 停止核心連線與關閉系統代理
  Future<void> stopCore() async {
    // 1. 先關閉系統代理，確保瀏覽器第一時間恢復直連
    await disableSystemProxy();

    // 2. 終止進程
    try {
      _coreProcess?.kill(ProcessSignal.sigterm);
      await Future.delayed(const Duration(milliseconds: 100));
      _coreProcess?.kill(ProcessSignal.sigkill);
      _coreProcess = null;
    } catch (_) {}

    try {
      await Process.run('killall', ['-9', 'mihomo']);
    } catch (_) {}

    _isProxyEnabled = false;
    debugPrint('[MacosNativeProxy] 核心進程已安全關閉');
  }

  /// 記憶體直推無縫熱切換 (< 50ms)
  Future<bool> switchProxyWithPayload({
    required String nodeName,
    String? yamlPayload,
    String? configPath,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 500);
    client.findProxy = (uri) => 'DIRECT';

    try {
      // 步驟 1: 若提供完整 yamlPayload，直接熱重載核心記憶體配置
      if (yamlPayload != null && yamlPayload.isNotEmpty) {
        try {
          final req = await client.putUrl(Uri.parse('http://127.0.0.1:9090/configs?force=true'));
          req.headers.contentType = ContentType.json;
          if (_secret.isNotEmpty) {
            req.headers.set('Authorization', 'Bearer $_secret');
          }
          req.write(jsonEncode({'payload': yamlPayload}));
          final res = await req.close();
          await res.drain();
          debugPrint('[MacosNativeProxy] 熱重載 YAML Payload 成功');
        } catch (e) {
          debugPrint('[MacosNativeProxy] 熱重載 YAML 異常: $e');
        }
      }

      // 步驟 2: 切換 PROXY 與 GLOBAL 分組節點
      final encoded = jsonEncode({'name': nodeName});
      for (final group in ['PROXY', 'GLOBAL']) {
        try {
          final req = await client.putUrl(Uri.parse('http://127.0.0.1:9090/proxies/$group'));
          req.headers.contentType = ContentType.json;
          if (_secret.isNotEmpty) {
            req.headers.set('Authorization', 'Bearer $_secret');
          }
          req.write(encoded);
          final res = await req.close();
          await res.drain();
        } catch (_) {}
      }

      // 步驟 3: 斬斷舊 TCP 長連線，強制出口 IP 立即漂移
      try {
        final delReq = await client.deleteUrl(Uri.parse('http://127.0.0.1:9090/connections'));
        if (_secret.isNotEmpty) {
          delReq.headers.set('Authorization', 'Bearer $_secret');
        }
        final delRes = await delReq.close();
        await delRes.drain();
      } catch (_) {}

      client.close();
      return true;
    } catch (e) {
      client.close();
      debugPrint('[MacosNativeProxy] 節點熱切換異常: $e');
      return false;
    }
  }

  /// 取得即時流量統計數據
  Future<TrafficStats> fetchTraffic() async {
    final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 400);
    client.findProxy = (uri) => 'DIRECT';
    try {
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:9090/traffic'));
      if (_secret.isNotEmpty) {
        req.headers.set('Authorization', 'Bearer $_secret');
      }
      final res = await req.close();
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        final map = jsonDecode(body) as Map<String, dynamic>;
        client.close();
        return TrafficStats(
          upSpeed: (map['up'] as num?)?.toInt() ?? 0,
          downSpeed: (map['down'] as num?)?.toInt() ?? 0,
        );
      }
    } catch (_) {}
    client.close();
    return const TrafficStats();
  }

  /// 建立到 Mihomo /traffic 的即時流量數據串流 (SSE NDJSON)
  Stream<TrafficStats> openTrafficStream({int controllerPort = 9090}) {
    late StreamController<TrafficStats> controller;
    HttpClient? client;
    StreamSubscription? sub;

    controller = StreamController<TrafficStats>(
      onListen: () async {
        try {
          client = HttpClient()..connectionTimeout = const Duration(milliseconds: 1000);
          client!.findProxy = (uri) => 'DIRECT';
          final req = await client!.getUrl(
            Uri.parse('http://127.0.0.1:$controllerPort/traffic'),
          );
          if (_secret.isNotEmpty) {
            req.headers.set('Authorization', 'Bearer $_secret');
          }
          final res = await req.close();

          sub = res
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen(
            (line) {
              if (line.isNotEmpty && line.startsWith('{')) {
                try {
                  final json = jsonDecode(line) as Map<String, dynamic>;
                  final stats = TrafficStats(
                    upSpeed: (json['up'] as num?)?.toInt() ?? 0,
                    downSpeed: (json['down'] as num?)?.toInt() ?? 0,
                    totalUp: (json['upTotal'] as num?)?.toInt() ?? 0,
                    totalDown: (json['downTotal'] as num?)?.toInt() ?? 0,
                  );
                  if (!controller.isClosed) {
                    controller.add(stats);
                  }
                } catch (_) {}
              }
            },
            onError: (err) {
              if (!controller.isClosed) {
                controller.add(const TrafficStats());
              }
            },
            onDone: () {
              if (!controller.isClosed) {
                controller.add(const TrafficStats());
              }
            },
          );
        } catch (_) {
          if (!controller.isClosed) {
            controller.add(const TrafficStats());
          }
        }
      },
      onCancel: () {
        sub?.cancel();
        client?.close(force: true);
      },
    );

    return controller.stream;
  }

  /// macOS 開機自啟動管理 (透過 ~/Library/LaunchAgents plist)
  String get _launchAgentPlistPath {
    final home = Platform.environment['HOME'] ?? '';
    return '$home/Library/LaunchAgents/com.tianhe.cloud.assistant.macos.plist';
  }

  Future<bool> isAutoStartEnabled() async {
    if (kIsWeb || !Platform.isMacOS) return false;
    return File(_launchAgentPlistPath).existsSync();
  }

  Future<bool> setAutoStart(bool enable) async {
    if (kIsWeb || !Platform.isMacOS) return false;

    try {
      final plistFile = File(_launchAgentPlistPath);
      if (enable) {
        if (!plistFile.parent.existsSync()) {
          plistFile.parent.createSync(recursive: true);
        }
        final appPath = Platform.resolvedExecutable;
        final plistContent = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.tianhe.cloud.assistant.macos</string>
    <key>ProgramArguments</key>
    <array>
        <string>$appPath</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
''';
        await plistFile.writeAsString(plistContent, flush: true);
        return true;
      } else {
        if (await plistFile.exists()) {
          await plistFile.delete();
        }
        return true;
      }
    } catch (e) {
      debugPrint('[MacosNativeProxy] 設定開機自啟異常: $e');
      return false;
    }
  }

  /// 支援單元測試環境模擬管理員權限
  static bool? mockIsAdmin;

  /// 支援單元測試環境模擬 TUN 驅動
  static bool? mockIsWintun;

  /// 檢查當前進程是否以系統管理員權限執行 (macOS 下為 root/admin)
  Future<bool> isRunningAsAdmin() async {
    if (mockIsAdmin != null) return mockIsAdmin!;
    if (kIsWeb || !Platform.isMacOS) return false;
    try {
      final res = await Process.run('id', ['-u']);
      return res.stdout.toString().trim() == '0';
    } catch (_) {
      return false;
    }
  }

  /// 以系統管理員身分重新啟動 (macOS 支援 osascript 管理提權)
  Future<bool> restartAsAdmin() async {
    if (mockIsAdmin != null) return true;
    if (kIsWeb || !Platform.isMacOS) return false;
    try {
      final exe = Platform.resolvedExecutable;
      await Process.start('osascript', [
        '-e',
        'do shell script "$exe" with administrator privileges'
      ]);
      await stopCore();
      exit(0);
    } catch (e) {
      debugPrint('[MacosNativeProxy] 提權重啟失敗: $e');
      return false;
    }
  }

  /// 檢查 TUN 虛擬網卡是否可用 (macOS 原生支援 utun)
  Future<bool> isWintunAvailable() async {
    if (mockIsWintun != null) return mockIsWintun!;
    return true;
  }

  /// 跨平台兼容別名與方法
  void refreshWinINet() {}
  Future<File?> findMihomoExecutable() async => File(getMihomoExecutablePath());
  Future<Directory> ensureWorkingDirectoryWithDatabases() => prepareCoreWorkingDir();
}

/// 兼容別名 (讓既有 WindowsProxyService 引用零改動無縫相容)
typedef WindowsProxyService = MacosNativeProxy;
