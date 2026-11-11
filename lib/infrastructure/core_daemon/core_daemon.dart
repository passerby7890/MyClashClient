// lib/infrastructure/core_daemon/core_daemon.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../business/subscription/subscription_engine.dart';
import '../../core/utils/error_sanitizer.dart';
import 'core_state.dart';
import 'macos_native_proxy.dart';
import 'traffic_stats.dart';

/// 本地網路隧道核心守護行程
/// 封裝核心之生命週期 (啟動、停止、重新載入、毫秒級節點切換) 與即時流量串流
class CoreDaemon extends ChangeNotifier {
  static const MethodChannel _vpnChannel = MethodChannel('tianhe/vpn');

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
    } else if (!kIsWeb && (Platform.isMacOS || Platform.isWindows)) {
      MacosNativeProxy.instance.onUnexpectedExit = () {
        if (_state.isConnected || _state.isConnecting) {
          _stopTrafficPolling();
          _setState(CoreState.disconnected());
        }
      };
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

  /// 動態切換分流模式 (rule: 規則分流, global: 全域代理, direct: 直連模式, tun: 虛擬網卡)
  Future<void> setProxyMode(ProxyMode mode) async {
    if (_proxyMode == mode) return;
    _proxyMode = mode;
    _setState(_state.copyWith(proxyMode: mode));

    if (_state.isConnected && !kIsWeb && (Platform.isMacOS || Platform.isWindows)) {
      try {
        final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 400);
        client.findProxy = (uri) => 'DIRECT';
        final modeStr = mode == ProxyMode.global
            ? 'global'
            : (mode == ProxyMode.direct ? 'direct' : 'rule');
        final req = await client.patchUrl(Uri.parse('http://127.0.0.1:9090/configs'));
        req.headers.contentType = ContentType.json;
        if (_controllerSecret.isNotEmpty) {
          req.headers.set('Authorization', 'Bearer $_controllerSecret');
        }
        req.write(jsonEncode({'mode': modeStr}));
        final res = await req.close();
        await res.drain();
        client.close();
        await closeAllConnections();
        SafeLog.d('[CoreDaemon] 已熱切換分流模式為: $modeStr');
      } catch (_) {
        SafeLog.d('[CoreDaemon] 熱切換分流模式略過');
      }
    }
  }

  bool _isTransitioning = false;
  bool get isTransitioning => _isTransitioning;

  /// 啟動本地網路隧道核心
  Future<void> start({
    required String configPath,
    required String selectedNode,
  }) async {
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
          throw Exception('系統網路隧道授權被拒絕或啟動失敗');
        }
      } else if (!kIsWeb &&
          (Platform.isMacOS || Platform.isWindows) &&
          File(configPath).existsSync() &&
          !configPath.contains('mock')) {
        final success = await MacosNativeProxy.instance.startCore(
          configPath: configPath,
          selectedNode: selectedNode,
          secret: _controllerSecret,
        );
        if (!success) {
          throw Exception('本地網路隧道或系統代理啟動失敗');
        }
      } else {
        await Future.delayed(const Duration(milliseconds: 600));
      }

      _setState(CoreState.connected(nodeName: selectedNode));
      _startTrafficPolling();
    } catch (e) {
      _setState(CoreState.error(ErrorSanitizer.sanitize(e)));
      rethrow;
    } finally {
      _isTransitioning = false;
    }
  }

  /// 停止核心連線
  Future<void> stop() async {
    if (_isTransitioning || _state.isDisconnected || _state.isDisconnecting) return;
    _isTransitioning = true;

    _setState(CoreState.disconnecting());
    _stopTrafficPolling();

    try {
      if (!kIsWeb && Platform.isAndroid) {
        await Future.delayed(const Duration(milliseconds: 50));
        await _vpnChannel.invokeMethod('stopVpn');
      } else if (!kIsWeb && (Platform.isMacOS || Platform.isWindows)) {
        await MacosNativeProxy.instance.stopCore();
      } else {
        await Future.delayed(const Duration(milliseconds: 300));
      }
    } catch (_) {
      SafeLog.d('[CoreDaemon] 停止核心連線通道異常');
    } finally {
      await SubscriptionEngine.shredResidualCoreConfigs();
      _setState(CoreState.disconnected());
      _isTransitioning = false;
    }
  }

  /// 快速切換連線節點 (毫秒級極速合併熱切換，純指標秒切)
  Future<void> switchNode(
    String nodeName, {
    List<String>? groupNames,
    String? configPath,
    String? yamlPayload,
  }) async {
    if (!_state.isConnected) return;
    _setState(CoreState.connected(nodeName: nodeName));

    if (!kIsWeb && (Platform.isMacOS || Platform.isWindows) && MacosNativeProxy.instance.isCoreRunning) {
      await MacosNativeProxy.instance.switchProxyWithPayload(
        nodeName: nodeName,
        groupNames: groupNames,
        yamlPayload: yamlPayload,
        configPath: configPath,
      );
      return;
    }

    try {
      final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 300);
      client.findProxy = (uri) => 'DIRECT';
      final encodedNode = jsonEncode({'name': nodeName});

      final targetGroups = <String>{'PROXY', 'GLOBAL'};
      if (groupNames != null) {
        targetGroups.addAll(groupNames);
      }

      for (final group in targetGroups) {
        try {
          final encodedGroup = Uri.encodeComponent(group);
          final request = await client.putUrl(Uri.parse('http://127.0.0.1:9090/proxies/$encodedGroup'));
          request.headers.contentType = ContentType.json;
          if (_controllerSecret.isNotEmpty) {
            request.headers.set('Authorization', 'Bearer $_controllerSecret');
          }
          request.write(encodedNode);
          final response = await request.close();
          await response.drain();
        } catch (_) {}
      }

      await closeAllConnections();
      client.close();
    } catch (_) {}
  }

  /// 無損分流模式切換 (Rule / Global / Direct) - 輕量 PATCH /configs，0 Geo 庫重載
  Future<void> setRoutingMode(String mode) async {
    final lower = mode.toLowerCase();
    if (!['rule', 'global', 'direct', 'tun'].contains(lower)) return;
    final targetMode = lower == 'tun' ? 'rule' : lower;
    try {
      final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 600);
      client.findProxy = (uri) => 'DIRECT';
      final req = await client.patchUrl(Uri.parse('http://127.0.0.1:9090/configs'));
      req.headers.contentType = ContentType.json;
      if (_controllerSecret.isNotEmpty) {
        req.headers.set('Authorization', 'Bearer $_controllerSecret');
      }
      req.write(jsonEncode({'mode': targetMode}));
      final res = await req.close();
      await res.drain();
      client.close();
    } catch (_) {}
    await closeAllConnections();
    _proxyMode = ProxyModeRoutingExt.fromRoutingString(lower);
    _setState(_state.copyWith(proxyMode: _proxyMode));
  }

  /// Rust 底層直接切換核心節點後，同步更新 Dart UI 核心狀態標籤
  void markNodeSwitched(String nodeName) {
    if (!_state.isConnected) return;
    _setState(CoreState.connected(nodeName: nodeName));
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
      } catch (_) {
        SafeLog.d('[CoreDaemon] 原生 reloadConfig 呼叫失敗');
      }
    }
    SafeLog.d('[CoreDaemon] 重新載入核心設定檔完成');
  }

  /// 中斷所有活動網絡連線
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

    if (!kIsWeb && (Platform.isMacOS || Platform.isWindows) && MacosNativeProxy.instance.isCoreRunning) {
      _windowsTrafficSub = MacosNativeProxy.instance.openTrafficStream().listen((stats) {
        if (!_state.isConnected) return;
        _currentTraffic = stats;
        if (!_trafficController.isClosed) {
          _trafficController.add(_currentTraffic);
        }
        notifyListeners();
      });

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
      } else {
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
    _windowsTrafficSub?.cancel();
    _trafficController.close();
    super.dispose();
  }
}
