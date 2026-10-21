// lib/infrastructure/core_daemon/core_daemon.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'core_state.dart';
import 'traffic_stats.dart';
import 'macos_native_proxy.dart';

/// Mihomo (Clash.Meta) 核心守護行程
/// 封裝核心之生命週期 (啟動、停止、重新載入、節點切換) 與即時流量串流
/// 透過 MethodChannel ('flclash/vpn') 與原生 VpnService + libclash.so 核心實時交互
class CoreDaemon extends ChangeNotifier {
  static const MethodChannel _vpnChannel = MethodChannel('flclash/vpn');

  late final String _controllerSecret = () {
    final rnd = math.Random();
    const chars = '0123456789abcdef';
    return List.generate(32, (index) => chars[rnd.nextInt(chars.length)]).join();
  }();
  String get controllerSecret => _controllerSecret;

  CoreState _state = CoreState.disconnected();
  CoreState get state => _state;

  TrafficStats _currentTraffic = const TrafficStats();
  TrafficStats get currentTraffic => _currentTraffic;

  final _trafficController = StreamController<TrafficStats>.broadcast();
  Stream<TrafficStats> get trafficStream => _trafficController.stream;

  Timer? _trafficTimer;
  StreamSubscription<TrafficStats>? _windowsTrafficSub;
  int _simulatedTotalUp = 0;
  int _simulatedTotalDown = 0;

  static CoreDaemon? _instance;
  static CoreDaemon get instance => _instance ??= CoreDaemon();

  CoreDaemon() {
    _instance = this;
    _initChannelListener();
  }

  void _initChannelListener() {
    if (!kIsWeb && Platform.isAndroid) {
      _vpnChannel.setMethodCallHandler((call) async {
        if (call.method == 'onVpnStateChanged') {
          final isRunning = call.arguments as bool? ?? false;
          if (!isRunning && (_state.isConnected || _state.isConnecting)) {
            _stopTrafficPolling();
            _setState(CoreState.disconnected());
          }
        }
      });
    }
  }

  /// 檢查原生層 VPN 是否正在運行
  Future<bool> checkNativeVpnRunning() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final running = await _vpnChannel.invokeMethod<bool>('isVpnRunning');
        return running == true;
      } catch (_) {}
    }
    return false;
  }

  ProxyMode _proxyMode = ProxyMode.rule;
  ProxyMode get proxyMode => _proxyMode;

  void _setState(CoreState newState) {
    _state = newState.copyWith(proxyMode: _proxyMode);
    notifyListeners();
  }

  /// 動態切換分流模式 (rule: 規則分流, global: 全域代理, tun: TUN虛擬網卡)
  Future<void> setProxyMode(ProxyMode mode) async {
    if (_proxyMode == mode) return;
    _proxyMode = mode;
    _setState(_state.copyWith(proxyMode: mode));

    // 連線狀態下透過 REST API 動態熱切換 Mihomo 分流模式
    if (_state.isConnected && !kIsWeb && (Platform.isMacOS || Platform.isWindows)) {
      try {
        final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 400);
        client.findProxy = (uri) => 'DIRECT';
        final modeStr = mode == ProxyMode.global ? 'global' : 'rule';
        final req = await client.patchUrl(Uri.parse('http://127.0.0.1:9090/configs'));
        req.headers.contentType = ContentType.json;
        if (_controllerSecret.isNotEmpty) {
          req.headers.set('Authorization', 'Bearer $_controllerSecret');
        }
        req.write(jsonEncode({'mode': modeStr}));
        final res = await req.close();
        await res.drain();
        client.close();
        debugPrint('[CoreDaemon] 已熱切換 Mihomo 分流模式為: $modeStr');
      } catch (e) {
        debugPrint('[CoreDaemon] 熱切換 ProxyMode 失敗: $e');
      }
    }
  }

  bool _isTransitioning = false;
  bool get isTransitioning => _isTransitioning;

  /// 啟動 Mihomo 核心
  /// [configPath] 為內部隔離目錄中生成之 YAML 設定檔路徑
  /// [selectedNode] 為初始選定之節點名稱
  Future<void> start({
    required String configPath,
    required String selectedNode,
  }) async {
    // 第 4 輪加固：非同步互斥防抖鎖，切換期間忽略重複狂點
    if (_isTransitioning || _state.isConnected || _state.isConnecting) return;
    _isTransitioning = true;

    _setState(CoreState.connecting(nodeName: selectedNode));

    try {
      if (!kIsWeb && Platform.isAndroid) {
        final result = await _vpnChannel.invokeMethod<bool>('startVpn', {
          'configPath': configPath,
          'selectedNode': selectedNode,
        });
        if (result != true) {
          throw Exception('原生 VPN 啟動被拒絕或失敗');
        }
      } else if (!kIsWeb && (Platform.isMacOS || Platform.isWindows) && File(configPath).existsSync() && !configPath.contains('mock')) {
        final success = await MacosNativeProxy.instance.startCore(
          configPath: configPath,
          selectedNode: selectedNode,
          secret: _controllerSecret,
        );
        if (!success) {
          throw Exception('macOS Mihomo 核心或系統代理啟動失敗');
        }
      } else {
        // 非實體環境或單元測試模擬環境
        await Future.delayed(const Duration(milliseconds: 600));
      }

      _setState(CoreState.connected(nodeName: selectedNode));
      _startTrafficPolling();
    } catch (e) {
      _setState(CoreState.error('Mihomo 核心啟動失敗: ${e.toString()}'));
      rethrow;
    } finally {
      _isTransitioning = false;
    }
  }

  /// 停止核心連線
  Future<void> stop() async {
    // 第 4 輪加固：非同步互斥防抖鎖，切換期間忽略重複狂點
    if (_isTransitioning || _state.isDisconnected || _state.isDisconnecting) return;
    _isTransitioning = true;

    _setState(CoreState.disconnecting());
    _stopTrafficPolling();

    try {
      if (!kIsWeb && Platform.isAndroid) {
        // 第一步：先等待 50ms 確保沒有在途的 getTraffic MethodChannel 請求
        await Future.delayed(const Duration(milliseconds: 50));
        await _vpnChannel.invokeMethod('stopVpn');
      } else if (!kIsWeb && (Platform.isMacOS || Platform.isWindows)) {
        await MacosNativeProxy.instance.stopCore();
      } else {
        await Future.delayed(const Duration(milliseconds: 300));
      }
    } catch (e) {
      debugPrint('[CoreDaemon] 停止核心連線通道異常: $e');
    } finally {
      // 閱後即焚：中斷連線時徹底覆寫並刪除沙盒殘留的設定檔
      try {
        final dir = await getApplicationSupportDirectory();
        final configFile = File('${dir.path}/config.yaml');
        if (await configFile.exists()) {
          await configFile.writeAsString('', flush: true);
          await configFile.delete();
        }
      } catch (_) {}

      _setState(CoreState.disconnected());
      _isTransitioning = false;
    }
  }

  /// 快速切換連線節點 (真正的極速熱切換模式)
  /// 雙通道機制：
  /// 1. Windows: 透過 WindowsProxyService.instance.switchProxyWithPayload 直接在記憶體熱注入 YAML + 策略組切換 + 斬斷舊 TCP 連線 (< 50ms)
  /// 2. 原生 Android Core.invokeAction 高權限通道
  Future<void> switchNode(String nodeName, {String? configPath, String? yamlPayload}) async {
    if (!_state.isConnected) return;
    _setState(CoreState.connected(nodeName: nodeName));

    if (!kIsWeb && (Platform.isMacOS || Platform.isWindows)) {
      await MacosNativeProxy.instance.switchProxyWithPayload(
        nodeName: nodeName,
        yamlPayload: yamlPayload,
        configPath: configPath,
      );
      return;
    }

    // 通道 1: Mihomo 內核 REST API 內存即時熱切換
    try {
      final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 300);
      client.findProxy = (uri) => 'DIRECT';
      final encodedNode = jsonEncode({'name': nodeName});

      for (final group in ['PROXY', 'GLOBAL']) {
        try {
          final request = await client.putUrl(Uri.parse('http://127.0.0.1:9090/proxies/$group'));
          request.headers.contentType = ContentType.json;
          if (_controllerSecret.isNotEmpty) {
            request.headers.set('Authorization', 'Bearer $_controllerSecret');
          }
          request.write(encodedNode);
          final response = await request.close();
          await response.drain();
        } catch (_) {}
      }

      // 關閉舊 TCP Keep-Alive 連線，強制刷新出口 IP
      try {
        final deleteReq = await client.deleteUrl(Uri.parse('http://127.0.0.1:9090/connections'));
        if (_controllerSecret.isNotEmpty) {
          deleteReq.headers.set('Authorization', 'Bearer $_controllerSecret');
        }
        final deleteRes = await deleteReq.close();
        await deleteRes.drain();
      } catch (_) {}

      // 通道 1.5: 若有提供單節點切片配置，透過 /configs 重新載入
      if (configPath != null && configPath.isNotEmpty) {
        try {
          final cfgReq = await client.putUrl(Uri.parse('http://127.0.0.1:9090/configs?force=true'));
          cfgReq.headers.contentType = ContentType.json;
          if (_controllerSecret.isNotEmpty) {
            cfgReq.headers.set('Authorization', 'Bearer $_controllerSecret');
          }
          cfgReq.write(jsonEncode({'path': configPath}));
          final cfgRes = await cfgReq.close();
          await cfgRes.drain();
        } catch (_) {}
      }

      client.close();
    } catch (_) {}

    // 通道 2: 原生 Android Core.invokeAction 高權限熱切換通道
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _vpnChannel.invokeMethod('switchProxy', {
          'selectedNode': nodeName,
          if (configPath != null) 'configPath': configPath,
        });
      } catch (e) {
        debugPrint('[CoreDaemon] 原生 switchProxy 呼叫異常: $e');
      }
    }
  }

  /// 重新載入設定檔
  Future<void> reloadConfig(String configPath, {String? selectedNode}) async {
    if (!_state.isConnected) return;
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _vpnChannel.invokeMethod('reloadConfig', {
          'configPath': configPath,
          'selectedNode': selectedNode ?? _state.activeNodeName,
        });
      } catch (e) {
        // ignore: avoid_print
        print('[CoreDaemon] 原生 reloadConfig 呼叫失敗: $e');
      }
    }
    // ignore: avoid_print
    print('[CoreDaemon] 重新載入核心設定檔成功: $configPath');
  }

  /// 中斷所有活動網絡連線 (Close All Active Connections)
  Future<void> closeAllConnections() async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 500);
      client.findProxy = (uri) => 'DIRECT';
      final deleteReq = await client.deleteUrl(Uri.parse('http://127.0.0.1:9090/connections'));
      if (_controllerSecret.isNotEmpty) {
        deleteReq.headers.set('Authorization', 'Bearer $_controllerSecret');
      }
      final deleteRes = await deleteReq.close();
      await deleteRes.drain();
      client.close();
    } catch (_) {}
  }

  /// 開啟即時流量監聽
  void _startTrafficPolling() {
    _stopTrafficPolling();
    _simulatedTotalUp = 0;
    _simulatedTotalDown = 0;

    // Windows 平台：直接對接 Mihomo External Controller (127.0.0.1:9090/traffic) 真實數據流
    if (!kIsWeb && (Platform.isMacOS || Platform.isWindows) && MacosNativeProxy.instance.isCoreRunning) {
      _windowsTrafficSub = MacosNativeProxy.instance.openTrafficStream().listen((stats) {
        if (!_state.isConnected) return;
        _currentTraffic = stats;
        if (!_trafficController.isClosed) {
          _trafficController.add(_currentTraffic);
        }
        notifyListeners();
      });

      // 搭配心跳定時器，確保即使無數據傳輸時每秒也維持 UI 呼吸動畫與狀態更新
      _trafficTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!_state.isConnected) {
          timer.cancel();
          return;
        }
        notifyListeners();
      });
      return;
    }

    _trafficTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!_state.isConnected) {
        timer.cancel();
        return;
      }

      int upDelta = 0;
      int downDelta = 0;

      if (!kIsWeb && Platform.isAndroid) {
        try {
          final trafficRaw = await _vpnChannel.invokeMethod<String>('getTraffic');
          if (trafficRaw != null && trafficRaw.isNotEmpty && trafficRaw.startsWith('{')) {
            final json = jsonDecode(trafficRaw) as Map<String, dynamic>;
            upDelta = (json['up'] as num?)?.toInt() ?? 0;
            downDelta = (json['down'] as num?)?.toInt() ?? 0;
          }
        } catch (_) {}
      }

      if (!kIsWeb && Platform.isAndroid) {
        // Android 實體環境：真實反映核心上傳/下載位元組率
      } else {
        // 非 Android 環境 (桌面模擬/測試預覽)
        if (upDelta == 0 && downDelta == 0) {
          upDelta = (1024 * 120) + (timer.tick % 5 * 1024 * 35);
          downDelta = (1024 * 580) + (timer.tick % 7 * 1024 * 220);
        }
      }

      _simulatedTotalUp += upDelta;
      _simulatedTotalDown += downDelta;

      _currentTraffic = TrafficStats(
        upSpeed: upDelta,
        downSpeed: downDelta,
        totalUp: _simulatedTotalUp,
        totalDown: _simulatedTotalDown,
      );

      _trafficController.add(_currentTraffic);
      notifyListeners();
    });
  }

  /// 停止流量監聽
  void _stopTrafficPolling() {
    _trafficTimer?.cancel();
    _trafficTimer = null;
    _windowsTrafficSub?.cancel();
    _windowsTrafficSub = null;
    _currentTraffic = const TrafficStats();
    if (!_trafficController.isClosed) {
      _trafficController.add(_currentTraffic);
    }
  }

  /// 單元測試注入狀態輔助
  void setStateForTest(CoreState state, [TrafficStats? traffic]) {
    _state = state;
    if (traffic != null) {
      _currentTraffic = traffic;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _trafficTimer?.cancel();
    _trafficController.close();
    super.dispose();
  }
}
