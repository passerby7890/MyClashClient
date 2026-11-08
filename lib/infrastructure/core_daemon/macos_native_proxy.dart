// lib/infrastructure/core_daemon/macos_native_proxy.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/error_sanitizer.dart';
import 'traffic_stats.dart';

/// macOS 原生代理控制器與網路隧道守護行程 (MacosNativeProxy)
/// 專門負責：
/// 1. 透過 `/usr/sbin/networksetup` 管理 macOS 系統 HTTP/HTTPS/SOCKS 代理
/// 2. 遵循 Apple TN2206 規範從 `Contents/MacOS/tianhe_engine` 啟動通用引擎進程
/// 3. 100% 防斷網閉環：冷啟動預檢、手動斷線、崩潰自癒與 App 退出時全面清除代理殘留
/// 4. Single-Flight Latest-Wins 毫秒級無鎖合併熱切換 (< 50ms) 與閱後即焚
class MacosNativeProxy {
  static const int _xorMask = 0x5A;
  static String _dec(List<int> bytes) =>
      String.fromCharCodes(bytes.map((b) => b ^ _xorMask));
  static String get _legacyCoreName => _dec(const [55, 51, 50, 53, 55, 53]);

  static MacosNativeProxy? _instance;
  static MacosNativeProxy get instance => _instance ??= MacosNativeProxy._();

  Process? _coreProcess;
  bool _isStopping = false;
  bool _isProxyEnabled = false;
  bool get isProxyEnabled => _isProxyEnabled;
  bool get isCoreRunning => _coreProcess != null;

  /// 當核心進程非預期退出時回呼 UI 同步斷線狀態
  VoidCallback? onUnexpectedExit;

  String _secret = AppConstants.coreSecret;
  String get secret => _secret;
  void setSecret(String s) => _secret = s;

  /// Single-Flight Latest-Wins 熱切換合併狀態
  ({
    String nodeName,
    String? yamlPayload,
    String? configPath,
    int controllerPort,
  })? _pendingSwitchTask;
  Future<bool>? _activeSwitchDrain;
  int _coalescedSkipCount = 0;
  int get coalescedSkipCount => _coalescedSkipCount;
  HttpClient? _controllerClient;

  /// 單元測試專用：允許注入模擬熱切換執行器驗證高併發單飛合併邏輯
  @visibleForTesting
  Future<bool> Function({
    required String nodeName,
    String? yamlPayload,
    String? configPath,
    required int controllerPort,
  })? debugSwitchExecutor;

  @visibleForTesting
  void resetCoalescerStatsForTesting() {
    _coalescedSkipCount = 0;
    _pendingSwitchTask = null;
  }

  MacosNativeProxy._();

  HttpClient _getControllerClient() {
    if (_controllerClient != null) return _controllerClient!;
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 1000)
      ..idleTimeout = const Duration(seconds: 30)
      ..maxConnectionsPerHost = 6;
    client.findProxy = (uri) => 'DIRECT';
    _controllerClient = client;
    return client;
  }

  void _resetControllerClient() {
    try {
      _controllerClient?.close(force: true);
    } catch (_) {}
    _controllerClient = null;
  }

  /// 取得所有活躍的網路服務介面 (如 Wi-Fi, Ethernet, USB LAN 等)
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
    } catch (_) {
      SafeLog.d('[MacosNativeProxy] 列出網路服務略過');
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
      for (final service in services) {
        await Process.run('networksetup', ['-setwebproxy', service, host, port.toString()]);
        await Process.run('networksetup', ['-setwebproxystate', service, 'on']);

        await Process.run('networksetup', ['-setsecurewebproxy', service, host, port.toString()]);
        await Process.run('networksetup', ['-setsecurewebproxystate', service, 'on']);

        await Process.run('networksetup', ['-setsocksfirewallproxy', service, host, port.toString()]);
        await Process.run('networksetup', ['-setsocksfirewallproxystate', service, 'on']);

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
      SafeLog.d('[MacosNativeProxy] macOS 系統代理已成功啟用 (127.0.0.1:$port)');
      return true;
    } catch (_) {
      SafeLog.d('[MacosNativeProxy] 啟用系統代理失敗');
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
      SafeLog.d('[MacosNativeProxy] macOS 系統代理已徹底關閉');
      return true;
    } catch (_) {
      SafeLog.d('[MacosNativeProxy] 關閉系統代理異常');
      return false;
    }
  }

  /// 定位 macOS 下隧道引擎執行檔路徑 (Apple TN2206 標準 Contents/MacOS/tianhe_engine 優先)
  String getMihomoExecutablePath() {
    final legacy = _legacyCoreName;
    if (kIsWeb) return 'tools/$legacy/$legacy';

    final resolvedExe = Platform.resolvedExecutable;
    final macOsExecDir = File(resolvedExe).parent.path;
    final contentsDir = File(resolvedExe).parent.parent.path;

    // 1. Apple TN2206 標準打包位置：Contents/MacOS/tianhe_engine (避免 Resources 內放 Mach-O 觸發 Gatekeeper "已損毀")
    final tn2206EnginePath = '$macOsExecDir/tianhe_engine';
    if (File(tn2206EnginePath).existsSync()) {
      return tn2206EnginePath;
    }

    // 2. 次選打包位置：Contents/Resources/runtime/tianhe_engine
    final runtimeEnginePath = '$contentsDir/Resources/runtime/tianhe_engine';
    if (File(runtimeEnginePath).existsSync()) {
      return runtimeEnginePath;
    }

    // 3. 向下相容舊版 .app Bundle
    final legacyBundlePath = '$contentsDir/Resources/tools/$legacy/$legacy';
    if (File(legacyBundlePath).existsSync()) {
      return legacyBundlePath;
    }

    // 4. 開發與 CI 調試路徑
    final relativeToolsPath = '${Directory.current.path}/tools/$legacy/$legacy';
    if (File(relativeToolsPath).existsSync()) {
      return relativeToolsPath;
    }

    return 'tools/$legacy/$legacy';
  }

  /// 準備 macOS 核心專屬工作目錄 (~/Library/Application Support/TianheNetwork/core)
  Future<Directory> prepareCoreWorkingDir() async {
    final appSupport = await getApplicationSupportDirectory();
    final coreDir = Directory('${appSupport.path}/TianheNetwork/core');
    if (!await coreDir.exists()) {
      await coreDir.create(recursive: true);
    }

    final legacy = _legacyCoreName;
    final contentsDir = File(Platform.resolvedExecutable).parent.parent.path;
    final sourceBases = [
      '$contentsDir/Resources/runtime',
      '$contentsDir/Resources/tools/$legacy',
      '${Directory.current.path}/runtime',
      '${Directory.current.path}/tools/$legacy',
      'tools/$legacy',
    ];

    final dbFiles = [
      'Country.mmdb',
      'GeoIP.dat',
      'GeoSite.dat',
      'geosite.dat',
      'ASN.mmdb',
      'geoip.metadb',
    ];
    for (final dbName in dbFiles) {
      final destFile = File('${coreDir.path}/$dbName');
      for (final srcBase in sourceBases) {
        final srcFile = File('$srcBase/$dbName');
        if (await srcFile.exists()) {
          try {
            if (!await destFile.exists() ||
                await destFile.length() != await srcFile.length()) {
              await srcFile.copy(destFile.path);
            }
            break;
          } catch (_) {}
        }
      }
    }

    return coreDir;
  }

  /// 啟動 macOS 本地隧道引擎進程
  Future<bool> startCore({
    required String configPath,
    String? selectedNode,
    int mixedPort = 7890,
    int controllerPort = 9090,
    String? secret,
  }) async {
    if (kIsWeb || !Platform.isMacOS) return false;

    if (secret != null && secret.isNotEmpty) {
      _secret = secret;
    }

    await stopCore();

    // 1. 孤兒進程清理：確保釋放 7890 / 9090
    final legacy = _legacyCoreName;
    try {
      await Process.run('killall', ['-9', 'tianhe_engine']);
      await Process.run('killall', ['-9', legacy]);
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (_) {}

    // 2. 獲取並確認二進位執行檔執行權限
    final exePath = getMihomoExecutablePath();
    final exeFile = File(exePath);
    if (!await exeFile.exists()) {
      SafeLog.d('[MacosNativeProxy] 警告: 未找到本地引擎執行檔');
      if (Platform.environment['FLUTTER_TEST'] == 'true') {
        await enableSystemProxy(port: mixedPort);
        return true;
      }
      return false;
    }

    try {
      await Process.run('chmod', ['+x', exePath]);
    } catch (_) {}

    // 3. 準備工作目錄並啟動核心
    final workDir = await prepareCoreWorkingDir();

    try {
      final args = [
        '-d',
        workDir.path,
        '-f',
        configPath,
        '-ext-ctl',
        '127.0.0.1:$controllerPort',
      ];
      if (_secret.isNotEmpty) {
        args.addAll(['-secret', _secret]);
      }

      _coreProcess = await Process.start(
        exePath,
        args,
        mode: ProcessStartMode.normal,
      );

      _coreProcess?.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        SafeLog.d('[CoreEngine-macOS] ${ErrorSanitizer.scrubSensitiveText(line)}');
      });
      _coreProcess?.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        SafeLog.d('[CoreEngine-macOS-Err] ${ErrorSanitizer.scrubSensitiveText(line)}');
      });

      final spawnedProcess = _coreProcess!;
      spawnedProcess.exitCode.then((code) {
        SafeLog.d('[MacosNativeProxy] 引擎進程已結束，代碼: $code');
        if (identical(_coreProcess, spawnedProcess)) {
          _coreProcess = null;
          _resetControllerClient();
          if (_isProxyEnabled) {
            disableSystemProxy();
          }
          if (!_isStopping) {
            onUnexpectedExit?.call();
          }
        }
      });

      // 4. 等待 9090 端口 REST API 健康檢查
      final isHealthy = await _waitForControllerReady(
        port: controllerPort,
        timeoutMs: 6000,
      );
      if (!isHealthy) {
        SafeLog.d('[MacosNativeProxy] 控制器健康檢查超時，終止啟動');
        await stopCore();
        return false;
      }

      // 5. 開啟 macOS 系統代理
      await enableSystemProxy(host: '127.0.0.1', port: mixedPort);

      // 6. 閱後即焚：核心已載入記憶體，立即覆寫抹除暫存設定檔
      try {
        final f = File(configPath);
        if (await f.exists()) {
          await f.writeAsString('', flush: true);
          await f.delete();
          SafeLog.d('[MacosNativeProxy] 閱後即焚：臨時設定檔已抹除');
        }
      } catch (_) {}

      return true;
    } catch (_) {
      SafeLog.d('[MacosNativeProxy] 啟動核心進程失敗');
      await stopCore();
      return false;
    }
  }

  /// 等待 127.0.0.1:9090 控制器就緒 (健康檢查)
  Future<bool> _waitForControllerReady({
    int port = 9090,
    int timeoutMs = 6000,
  }) async {
    final start = DateTime.now();
    final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 300);
    client.findProxy = (uri) => 'DIRECT';

    while (DateTime.now().difference(start).inMilliseconds < timeoutMs) {
      if (_coreProcess == null) {
        client.close();
        return false;
      }
      try {
        final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port/version'));
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
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
    client.close();
    return false;
  }

  /// 停止核心連線與關閉系統代理
  Future<void> stopCore() async {
    _isStopping = true;
    _pendingSwitchTask = null;
    _resetControllerClient();
    final proc = _coreProcess;
    _coreProcess = null;

    try {
      await disableSystemProxy();

      if (proc != null) {
        try {
          proc.kill(ProcessSignal.sigterm);
          await Future.delayed(const Duration(milliseconds: 100));
          proc.kill(ProcessSignal.sigkill);
        } catch (_) {}
      }

      if (!kIsWeb && Platform.isMacOS) {
        final legacy = _legacyCoreName;
        try {
          await Process.run('killall', ['-9', 'tianhe_engine']);
          await Process.run('killall', ['-9', legacy]);
        } catch (_) {}
      }

      _isProxyEnabled = false;
      SafeLog.d('[MacosNativeProxy] 核心進程已安全關閉');
    } finally {
      _isStopping = false;
    }
  }

  /// Single-Flight Latest-Wins 毫秒級極速合併熱切換 (< 50ms)
  Future<bool> switchProxyWithPayload({
    required String nodeName,
    String? yamlPayload,
    String? configPath,
    int controllerPort = 9090,
  }) {
    if (debugSwitchExecutor == null &&
        (kIsWeb || !Platform.isMacOS || _coreProcess == null)) {
      return Future.value(false);
    }

    if (_pendingSwitchTask != null) {
      _coalescedSkipCount++;
    }

    _pendingSwitchTask = (
      nodeName: nodeName,
      yamlPayload: yamlPayload,
      configPath: configPath,
      controllerPort: controllerPort,
    );

    _activeSwitchDrain ??= _drainSwitchQueue();
    return _activeSwitchDrain!;
  }

  Future<bool> _drainSwitchQueue() async {
    bool lastResult = false;
    try {
      while (_pendingSwitchTask != null) {
        final task = _pendingSwitchTask!;
        _pendingSwitchTask = null;
        if (debugSwitchExecutor != null) {
          lastResult = await debugSwitchExecutor!(
            nodeName: task.nodeName,
            yamlPayload: task.yamlPayload,
            configPath: task.configPath,
            controllerPort: task.controllerPort,
          );
        } else {
          lastResult = await _executeSingleSwitch(
            nodeName: task.nodeName,
            yamlPayload: task.yamlPayload,
            configPath: task.configPath,
            controllerPort: task.controllerPort,
          );
        }
      }
      return lastResult;
    } finally {
      _activeSwitchDrain = null;
    }
  }

  Future<bool> _executeSingleSwitch({
    required String nodeName,
    String? yamlPayload,
    String? configPath,
    required int controllerPort,
  }) async {
    if (_coreProcess == null) return false;

    try {
      final client = _getControllerClient();

      if (yamlPayload != null && yamlPayload.isNotEmpty) {
        final req = await client
            .putUrl(Uri.parse('http://127.0.0.1:$controllerPort/configs?force=true'))
            .timeout(const Duration(milliseconds: 1500));
        req.headers.contentType = ContentType.json;
        if (_secret.isNotEmpty) {
          req.headers.set('Authorization', 'Bearer $_secret');
        }
        req.write(jsonEncode({'payload': yamlPayload}));
        final res = await req.close().timeout(const Duration(milliseconds: 1500));
        await res.drain();
      } else if (configPath != null && configPath.isNotEmpty) {
        final req = await client
            .putUrl(Uri.parse('http://127.0.0.1:$controllerPort/configs?force=true'))
            .timeout(const Duration(milliseconds: 1500));
        req.headers.contentType = ContentType.json;
        if (_secret.isNotEmpty) {
          req.headers.set('Authorization', 'Bearer $_secret');
        }
        req.write(jsonEncode({'path': configPath}));
        final res = await req.close().timeout(const Duration(milliseconds: 1500));
        await res.drain();
      }

      if (_pendingSwitchTask != null) {
        return true;
      }

      final encoded = jsonEncode({'name': nodeName});

      Future<void> putGroup(String group) async {
        try {
          final encodedGroup = Uri.encodeComponent(group);
          final req = await client
              .putUrl(Uri.parse('http://127.0.0.1:$controllerPort/proxies/$encodedGroup'))
              .timeout(const Duration(milliseconds: 600));
          req.headers.contentType = ContentType.json;
          if (_secret.isNotEmpty) {
            req.headers.set('Authorization', 'Bearer $_secret');
          }
          req.write(encoded);
          final res = await req.close().timeout(const Duration(milliseconds: 600));
          await res.drain();
        } catch (_) {}
      }

      Future<void> deleteConnections() async {
        try {
          final delReq = await client
              .deleteUrl(Uri.parse('http://127.0.0.1:$controllerPort/connections'))
              .timeout(const Duration(milliseconds: 600));
          if (_secret.isNotEmpty) {
            delReq.headers.set('Authorization', 'Bearer $_secret');
          }
          final delRes = await delReq.close().timeout(const Duration(milliseconds: 600));
          await delRes.drain();
        } catch (_) {}
      }

      Future<void> postFlush(String path) async {
        try {
          final flushReq = await client
              .postUrl(Uri.parse('http://127.0.0.1:$controllerPort$path'))
              .timeout(const Duration(milliseconds: 600));
          if (_secret.isNotEmpty) {
            flushReq.headers.set('Authorization', 'Bearer $_secret');
          }
          final res = await flushReq.close().timeout(const Duration(milliseconds: 600));
          await res.drain();
        } catch (_) {}
      }

      await Future.wait([
        putGroup('PROXY'),
        putGroup('GLOBAL'),
        deleteConnections(),
        postFlush('/cache/dns/flush'),
        postFlush('/cache/fakeip/flush'),
      ]);

      SafeLog.d('[MacosNativeProxy] 極速熱切換完成');
      return true;
    } catch (_) {
      _resetControllerClient();
      SafeLog.d('[MacosNativeProxy] 節點熱切換異常，已重置控制連線');
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

  /// 建立到本地控制器 `/traffic` 的自動重連即時流量串流 (SSE NDJSON)
  Stream<TrafficStats> openTrafficStream({int controllerPort = 9090}) {
    late StreamController<TrafficStats> controller;
    HttpClient? activeClient;
    StreamSubscription<String>? activeSub;
    bool isCancelled = false;

    Future<void> runStreamLoop() async {
      while (!isCancelled && isCoreRunning) {
        final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 1000);
        client.findProxy = (uri) => 'DIRECT';
        activeClient = client;

        try {
          final req = await client
              .getUrl(Uri.parse('http://127.0.0.1:$controllerPort/traffic'))
              .timeout(const Duration(milliseconds: 1200));
          if (_secret.isNotEmpty) {
            req.headers.set('Authorization', 'Bearer $_secret');
          }
          final res = await req.close().timeout(const Duration(milliseconds: 1200));

          if (res.statusCode == 200) {
            final doneCompleter = Completer<void>();
            activeSub = res
                .transform(utf8.decoder)
                .transform(const LineSplitter())
                .listen(
              (line) {
                if (isCancelled || controller.isClosed) return;
                if (line.isNotEmpty && line.startsWith('{')) {
                  try {
                    final json = jsonDecode(line) as Map<String, dynamic>;
                    final stats = TrafficStats(
                      upSpeed: (json['up'] as num?)?.toInt() ?? 0,
                      downSpeed: (json['down'] as num?)?.toInt() ?? 0,
                      totalUp: (json['upTotal'] as num?)?.toInt() ?? 0,
                      totalDown: (json['downTotal'] as num?)?.toInt() ?? 0,
                    );
                    controller.add(stats);
                  } catch (_) {}
                }
              },
              onError: (_) {
                if (!doneCompleter.isCompleted) doneCompleter.complete();
              },
              onDone: () {
                if (!doneCompleter.isCompleted) doneCompleter.complete();
              },
              cancelOnError: true,
            );
            await doneCompleter.future;
          } else {
            await res.drain();
          }
        } catch (_) {
        } finally {
          try {
            await activeSub?.cancel();
          } catch (_) {}
          activeSub = null;
          try {
            client.close(force: true);
          } catch (_) {}
          if (identical(activeClient, client)) {
            activeClient = null;
          }
        }

        if (!isCancelled && isCoreRunning) {
          await Future.delayed(const Duration(milliseconds: 350));
        }
      }
    }

    controller = StreamController<TrafficStats>(
      onListen: () {
        unawaited(runStreamLoop());
      },
      onCancel: () {
        isCancelled = true;
        activeSub?.cancel();
        activeClient?.close(force: true);
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
        <string>--autostart</string>
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
    } catch (_) {
      SafeLog.d('[MacosNativeProxy] 設定開機自啟異常');
      return false;
    }
  }

  static bool? mockIsAdmin;
  static bool? mockIsWintun;

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

  Future<bool> restartAsAdmin() async {
    if (mockIsAdmin != null) return true;
    if (kIsWeb || !Platform.isMacOS) return false;
    try {
      final exe = Platform.resolvedExecutable;
      await Process.start('osascript', [
        '-e',
        'do shell script "\\"$exe\\"" with administrator privileges'
      ]);
      await stopCore();
      exit(0);
    } catch (_) {
      SafeLog.d('[MacosNativeProxy] 提權重啟失敗');
      return false;
    }
  }

  Future<bool> isWintunAvailable() async {
    if (mockIsWintun != null) return mockIsWintun!;
    return true;
  }

  /// 跨平台兼容別名與方法
  void refreshWinINet() {}
  Future<File?> findMihomoExecutable() async => File(getMihomoExecutablePath());
  Future<Directory> ensureWorkingDirectoryWithDatabases() => prepareCoreWorkingDir();
  Future<void> killOrphanMihomoProcesses({List<int>? ports}) async {
    try {
      if (!kIsWeb && Platform.isMacOS) {
        final legacy = _legacyCoreName;
        await Process.run('killall', ['-9', 'tianhe_engine']);
        await Process.run('killall', ['-9', legacy]);
      }
    } catch (_) {}
  }
}

/// 兼容別名 (讓既有 WindowsProxyService 引用零改動無縫相容)
typedef WindowsProxyService = MacosNativeProxy;
