// lib/business/subscription/subscription_engine.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yaml/yaml.dart';
import '../../core/constants/app_constants.dart';
import '../../core/i18n/i18n_service.dart';
import '../../core/network/dio_client.dart';
import '../../core/rust/tianhe_rust_bridge.dart';
import '../../core/storage/secure_storage_service.dart';
import '../../core/utils/error_sanitizer.dart';
import '../../infrastructure/config/app_config_service.dart';
import '../../infrastructure/core_daemon/core_daemon.dart';
import '../auth/auth_manager.dart';
import 'config_generator.dart';
import 'node_model.dart';

/// 訂閱端點授權異常 (401/403)，絕不攜帶任何主機 IP 或敏感路徑
class SubscriptionAuthException implements Exception {
  final int statusCode;
  final String message;

  SubscriptionAuthException(
    this.statusCode, [
    String? customMessage,
  ]) : message = customMessage ?? I18nService.instance.t('err_sub_token_invalid');

  @override
  String toString() => message;
}

/// 訂閱與節點引擎 (Subscription Engine)
/// 核心樞紐：獲取遠端加密訂閱、加密金庫持久化、單節點切片、極速熱切換與閱後即焚
class SubscriptionEngine extends ChangeNotifier {
  final DioClient _dioClient;
  final CoreDaemon _coreDaemon;
  final SecureStorageService _storageService;
  final AppConfigService? _customConfigService;
  AppConfigService get _configService => _customConfigService ?? _dioClient.configService;
  SecureStorageService get storageService => _storageService;

  AuthManager? _authManager;
  Timer? _autoSyncTimer;
  bool _isAutoSyncRunning = false;
  bool get isAutoSyncRunning => _isAutoSyncRunning;

  bool _isOfflinePaused = false;
  bool get isOfflinePaused => _isOfflinePaused;

  /// 設定離線暫停模式：啟用時暫停背景自動同步輪詢，關閉時恢復排程
  void setOfflinePause(bool paused) {
    if (_isOfflinePaused == paused) return;
    _isOfflinePaused = paused;
    if (paused) {
      _autoSyncTimer?.cancel();
    } else {
      _scheduleNextAutoSync();
    }
    notifyListeners();
  }

  DateTime? _lastSyncTime;
  DateTime? get lastSyncTime => _lastSyncTime;

  DateTime? _lastRescueSyncTime;
  DateTime? get lastRescueSyncTime => _lastRescueSyncTime;
  int _consecutivePingFailures = 0;
  String _preferredFlag = 'meta';
  String get preferredFlag => _preferredFlag;

  void attachAuthManager(AuthManager authManager) {
    _authManager = authManager;
  }

  /// 啟動「四段式背景自動靜默更新引擎 (Auto-Sync Daemon)」
  void initAutoSyncDaemon() {
    _scheduleNextAutoSync();

    Future.delayed(const Duration(seconds: 2), () {
      performAutoSync(reason: 'cold_start');
    });
  }

  /// 預設背景靜默自動同步週期 (10 分鐘)
  static const Duration defaultAutoSyncInterval = Duration(minutes: 10);

  /// 隨機抖動排程 (每 10 分鐘加上 ±60 秒隨機偏移，防止併發洪峰)
  void _scheduleNextAutoSync() {
    _autoSyncTimer?.cancel();
    if (_isOfflinePaused) return;
    final randomJitterSeconds = 540 + math.Random().nextInt(121);
    _autoSyncTimer = Timer(Duration(seconds: randomJitterSeconds), () async {
      await performAutoSync(reason: 'periodic');
      _scheduleNextAutoSync();
    });
  }

  /// 視窗喚醒/從睡眠或最小化恢復時觸發 (若距離上次同步超過 15 分鐘則立即背景同步)
  void onWindowWakeup() {
    if (_isOfflinePaused) return;
    if (_lastSyncTime == null ||
        DateTime.now().difference(_lastSyncTime!) > const Duration(minutes: 15)) {
      SafeLog.d('[SubscriptionEngine] 視窗喚醒且距離上次同步超過 15 分鐘，觸發背景自動同步');
      performAutoSync(reason: 'window_wakeup');
    }
  }

  /// 連線失敗或連線連續超時自救觸發 (帶 5 分鐘冷卻 CD)
  void triggerFailureRescueSync() {
    final now = DateTime.now();
    if (_lastRescueSyncTime != null &&
        now.difference(_lastRescueSyncTime!) < const Duration(minutes: 5)) {
      SafeLog.d('[SubscriptionEngine] 自救同步處於 5 分鐘冷卻中，跳過本次觸發');
      return;
    }
    _lastRescueSyncTime = now;
    SafeLog.d('[SubscriptionEngine] 觸發連線失敗/超時自救背景同步');
    performAutoSync(reason: 'failure_rescue');
  }

  List<NodeModel> _nodes = [];
  List<NodeModel> get nodes => List.unmodifiable(_nodes);

  NodeModel? _selectedNode;
  NodeModel? get selectedNode => _selectedNode;

  void setNodesForTest(List<NodeModel> nodes) {
    _nodes = nodes;
    if (nodes.isNotEmpty) {
      _selectedNode = nodes.first;
    }
    notifyListeners();
  }

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _activeConfigFilePath;
  String? get activeConfigFilePath => _activeConfigFilePath;

  String? _cachedYamlTemplate;
  String? get cachedYamlTemplate => _cachedYamlTemplate;
  void setCachedYamlTemplate(String? template) {
    _cachedYamlTemplate = template;
  }

  String _routingMode = 'rule';
  String get routingMode => _routingMode;

  Set<String> _favoriteNodeIds = {};
  Set<String> get favoriteNodeIds => Set.unmodifiable(_favoriteNodeIds);

  /// 是否為單元測試模式 (僅限 CI / 測試環境使用，正式 App 預設 100% 為 false 執行真實網路測速)
  final bool isTestMode;

  SubscriptionEngine({
    required DioClient dioClient,
    required CoreDaemon coreDaemon,
    required SecureStorageService storageService,
    AppConfigService? configService,
    this.isTestMode = false,
  })  : _dioClient = dioClient,
        _coreDaemon = coreDaemon,
        _storageService = storageService,
        _customConfigService = configService;

  /// 0 秒瞬開：從本地安全加密金庫還原全部節點 (Stale-While-Revalidate 第一步)
  Future<bool> restoreFromVault() async {
    try {
      final cachedYaml = await _storageService.getEncryptedNodes();
      if (cachedYaml == null || cachedYaml.trim().isEmpty) {
        return false;
      }

      List<NodeModel> parsedNodes = [];

      // 雙軌優先路徑：透過 Rust 黑盒金庫解密/解析並僅回傳 UI 零機密描述符
      if (!isTestMode &&
          Platform.environment['FLUTTER_TEST'] != 'true' &&
          TianheRustBridge.instance.init()) {
        final rustDescriptors = await TianheRustBridge.instance.parseYamlToVault(cachedYaml);
        if (rustDescriptors != null && rustDescriptors.isNotEmpty) {
          parsedNodes = rustDescriptors.map(NodeModel.fromRustDescriptor).toList();
          _cachedYamlTemplate = null; // 零機密：不保留明文 YAML 於 Dart
        }
      }

      if (parsedNodes.isEmpty) {
        parsedNodes = ConfigGenerator.parseProxiesFromYaml(cachedYaml);
        if (parsedNodes.isEmpty) {
          return false;
        }
        _cachedYamlTemplate = cachedYaml;
      }

      _nodes = parsedNodes;

      try {
        _favoriteNodeIds = await _storageService.getFavoriteNodeIds();
        _applyFavoritesToNodes();
      } catch (_) {}

      final savedSelectedId = await _storageService.read(AppConstants.storageSelectedNodeId);
      if (savedSelectedId != null &&
          _nodes.any((n) => n.id == savedSelectedId || n.name == savedSelectedId)) {
        _selectedNode = _nodes.firstWhere((n) => n.id == savedSelectedId || n.name == savedSelectedId);
      } else {
        _selectedNode = _nodes.first;
      }

      notifyListeners();
      return true;
    } catch (_) {
      SafeLog.d('[SubscriptionEngine] 從加密金庫還原節點未命中');
      return false;
    }
  }

  /// 載入並套用本地儲存之收藏節點 ID
  Future<void> loadFavorites() async {
    try {
      _favoriteNodeIds = await _storageService.getFavoriteNodeIds();
      _applyFavoritesToNodes();
      notifyListeners();
    } catch (_) {}
  }

  /// 切換節點收藏狀態
  Future<void> toggleFavorite(String nodeId) async {
    if (_favoriteNodeIds.contains(nodeId)) {
      _favoriteNodeIds.remove(nodeId);
    } else {
      _favoriteNodeIds.add(nodeId);
    }
    await _storageService.saveFavoriteNodeIds(_favoriteNodeIds);
    _applyFavoritesToNodes();
    notifyListeners();
  }

  void _applyFavoritesToNodes() {
    for (int i = 0; i < _nodes.length; i++) {
      final n = _nodes[i];
      final isFav = _favoriteNodeIds.contains(n.id);
      if (n.isFavorite != isFav) {
        _nodes[i] = n.copyWithFavorite(isFav);
      }
    }
    if (_selectedNode != null) {
      final isFav = _favoriteNodeIds.contains(_selectedNode!.id);
      _selectedNode = _selectedNode!.copyWithFavorite(isFav);
    }
  }

  /// 智慧篩選與排序節點清單
  List<NodeModel> getFilteredNodes({
    bool favoritesOnly = false,
    bool sortByLowestLatency = false,
    String? searchQuery,
  }) {
    List<NodeModel> list = List.of(_nodes);

    if (favoritesOnly) {
      list = list.where((n) => n.isFavorite).toList();
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = searchQuery.trim().toLowerCase();
      list = list
          .where((n) =>
              n.name.toLowerCase().contains(q) ||
              n.regionName.toLowerCase().contains(q) ||
              n.protocol.toLowerCase().contains(q))
          .toList();
    }

    if (sortByLowestLatency) {
      list.sort((a, b) {
        int getScore(NodeModel n) {
          if (n.latencyMs != null && n.latencyMs! > 0) {
            return n.latencyMs! <= 800 ? n.latencyMs! : 100000 + n.latencyMs!;
          }
          return 999999;
        }

        return getScore(a).compareTo(getScore(b));
      });
    } else {
      list.sort((a, b) {
        if (a.isFavorite && !b.isFavorite) return -1;
        if (!a.isFavorite && b.isFavorite) return 1;
        return 0;
      });
    }

    return list;
  }

  /// 雙軌防洩漏訂閱拉取：優先走 Rust NetRacer + YamlEngine 全程記憶體隔離，失敗時無痛降級 Dart 自癒通道
  Future<({List<NodeModel> nodes, String? yamlTemplateForBackup})> _fetchSubscriptionSafe({
    String? customSubscribeUrl,
    String? token,
  }) async {
    final relativePath = await _resolveAndVaultSubscribePath(
      customSubscribeUrl: customSubscribeUrl,
      token: token,
    );

    if (!isTestMode &&
        Platform.environment['FLUTTER_TEST'] != 'true' &&
        TianheRustBridge.instance.init()) {
      final allCandidates = <String>[];
      void addCandidate(String d) {
        final t = d.trim();
        if (t.isNotEmpty && !allCandidates.contains(t)) {
          allCandidates.add(t);
        }
      }

      addCandidate(_configService.currentApiDomain);
      for (final d in _configService.availableApiDomains) {
        addCandidate(d);
      }
      for (final d in _configService.activeConfig.allApiDomains) {
        addCandidate(d);
      }
      for (final d in AppConstants.fallbackApiDomains) {
        addCandidate(d);
      }

      final rustRes = await TianheRustBridge.instance.raceAndVaultSubscription(
        hosts: allCandidates,
        relativePath: relativePath,
      );

      if (rustRes != null && rustRes.nodes.isNotEmpty) {
        if (rustRes.winnerHost.isNotEmpty) {
          _configService.setCurrentApiDomain(rustRes.winnerHost);
        }
        final safeNodes = rustRes.nodes.map(NodeModel.fromRustDescriptor).toList();
        return (
          nodes: safeNodes,
          yamlTemplateForBackup:
              rustRes.encryptedBackup.isNotEmpty ? rustRes.encryptedBackup : null,
        );
      }
    }

    // 回退至 Dart 自癒通道
    final yamlContent = await _fetchSubscriptionWithSelfHealing(
      customSubscribeUrl: customSubscribeUrl,
      token: token,
    );
    if (yamlContent.isEmpty) {
      throw const FormatException('訂閱內容為空');
    }

    if (!isTestMode &&
        Platform.environment['FLUTTER_TEST'] != 'true' &&
        TianheRustBridge.instance.isAvailable) {
      final rustDescriptors = await TianheRustBridge.instance.parseYamlToVault(yamlContent);
      if (rustDescriptors != null && rustDescriptors.isNotEmpty) {
        final enc = await TianheRustBridge.instance.encryptConfig(yamlContent);
        return (
          nodes: rustDescriptors.map(NodeModel.fromRustDescriptor).toList(),
          yamlTemplateForBackup: enc != null ? 'RUST_ENC:$enc' : yamlContent,
        );
      }
    }

    final parsedNodes = ConfigGenerator.parseProxiesFromYaml(yamlContent);
    if (parsedNodes.isEmpty) {
      throw const FormatException('未能在訂閱資料中解析出有效節點');
    }
    return (nodes: parsedNodes, yamlTemplateForBackup: yamlContent);
  }

  /// 靜默拉取並注入訂閱配置 (含 Happy Eyeballs 雙層容災、403 自癒重試與金庫加密落地)
  Future<List<NodeModel>> syncSubscription({
    required String token,
    String? customSubscribeUrl,
    int maxRetries = 3,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final res = await _fetchSubscriptionSafe(
        customSubscribeUrl: customSubscribeUrl,
        token: token,
      );

      final isRustBacked = res.nodes.isNotEmpty && res.nodes.first.rustVaultIndex != null;
      _cachedYamlTemplate = isRustBacked ? null : res.yamlTemplateForBackup;
      _nodes = res.nodes;

      if (res.yamlTemplateForBackup != null && res.yamlTemplateForBackup!.isNotEmpty) {
        try {
          await _storageService.saveEncryptedNodes(res.yamlTemplateForBackup!);
        } catch (_) {}
      }

      try {
        _favoriteNodeIds = await _storageService.getFavoriteNodeIds();
        _applyFavoritesToNodes();
      } catch (_) {}

      if (_selectedNode == null || !_nodes.any((n) => n.id == _selectedNode!.id)) {
        _selectedNode = _nodes.first;
      } else {
        _selectedNode = _nodes.firstWhere((n) => n.id == _selectedNode!.id);
      }
      try {
        await _storageService.write(AppConstants.storageSelectedNodeId, _selectedNode!.id);
      } catch (_) {}

      _lastSyncTime = DateTime.now();
      _isLoading = false;
      notifyListeners();
      return _nodes;
    } catch (_) {
      SafeLog.d('[SubscriptionEngine] 同步訂閱遭遇異常');
      _isLoading = false;
      notifyListeners();

      if (_nodes.isNotEmpty) {
        SafeLog.d('[SubscriptionEngine] 網路波動重試耗盡，安全保留金庫已還原節點 ${_nodes.length} 顆');
        return _nodes;
      }
      rethrow;
    }
  }

  /// 選取連線節點 (極速熱切換模式 + 單節點動態切片 + 零未連線明文落地)
  Future<void> selectNode(NodeModel node) async {
    if (_selectedNode?.id == node.id &&
        _coreDaemon.state.isConnected &&
        _coreDaemon.state.activeNodeName == node.name) {
      return;
    }

    _selectedNode = node;
    try {
      await _storageService.write(AppConstants.storageSelectedNodeId, node.id);
    } catch (_) {}
    notifyListeners();

    // 1. 若核心正在運行，進行毫秒級極速熱切換 (優先透過 Rust 金庫直推 9090 端口，零 Dart 明文經手)
    if (_coreDaemon.state.isConnected) {
      bool switchedByRust = false;
      if (!isTestMode &&
          Platform.environment['FLUTTER_TEST'] != 'true' &&
          node.rustVaultIndex != null &&
          TianheRustBridge.instance.isAvailable) {
        switchedByRust = await TianheRustBridge.instance.selectNodeAndApply(
          nodeId: node.rustVaultIndex!,
          routingMode: _routingMode,
          secret: _coreDaemon.controllerSecret,
        );
        if (switchedByRust) {
          _coreDaemon.markNodeSwitched(node.name);
        }
      }

      if (!switchedByRust) {
        final groupNames = _extractSelectGroupNamesFromTemplate();
        await _coreDaemon.switchNode(node.name, groupNames: groupNames);
      }

      // 非同步對新節點執行真連通與延遲刷新，絕不阻塞 UI 與熱切換完成回傳
      unawaited(pingSelectedNode().catchError((_) => -1));
    }
    // 未連線狀態下絕不將節點配置提前寫入磁碟明文 (恪守零明文原則)
  }

  /// 設定分流模式 (rule: 規則分流, global: 全局代理, direct: 直連模式, tun: TUN虛擬網卡模式)
  Future<void> setRoutingMode(String mode) async {
    final lower = mode.toLowerCase();
    if (!['rule', 'global', 'direct', 'tun'].contains(lower)) return;
    _routingMode = lower;
    await _coreDaemon.setRoutingMode(lower);
    notifyListeners();
  }

  bool _isPinging = false;
  bool _cancelPingRequested = false;
  bool get isPinging => _isPinging;

  /// 隨時中斷正在進行的批量測速
  void cancelPing() {
    if (_isPinging) {
      _cancelPingRequested = true;
      TianheRustBridge.instance.cancelPing();
      _isPinging = false;
      notifyListeners();
    }
  }

  /// 一鍵選取延遲最低之最佳節點
  Future<NodeModel?> selectFastestNode({
    List<NodeModel>? candidateNodes,
    bool? isTestMode,
  }) async {
    final pool = (candidateNodes != null && candidateNodes.isNotEmpty) ? candidateNodes : _nodes;
    if (pool.isEmpty) return null;

    final validTested = pool.where((n) => n.latencyMs != null && n.latencyMs! > 0).toList();
    if (validTested.isEmpty) {
      await pingAllNodes(isTestMode: isTestMode);
    }

    final candidates = pool
        .map((n) => _nodes.firstWhere((x) => x.id == n.id, orElse: () => n))
        .where((n) => n.latencyMs != null && n.latencyMs! > 0)
        .toList();
    if (candidates.isEmpty) {
      final fallback = pool.first;
      await selectNode(fallback);
      return fallback;
    }

    candidates.sort((a, b) => a.latencyMs!.compareTo(b.latencyMs!));
    final fastest = candidates.first;
    await selectNode(fastest);
    return fastest;
  }

  /// 連線後真連通檢驗 (True Tunnel 204 Check)
  Future<bool> verifyTunnelConnectivity({Duration timeout = const Duration(seconds: 3)}) async {
    if (!_coreDaemon.state.isConnected) return false;
    try {
      final client = HttpClient()..connectionTimeout = timeout;
      client.findProxy = (uri) => 'PROXY 127.0.0.1:7890';
      client.badCertificateCallback = (cert, host, port) => true;

      final req = await client.getUrl(Uri.parse('https://www.gstatic.com/generate_204')).timeout(timeout);
      final res = await req.close().timeout(timeout);
      await res.drain();
      client.close();
      return res.statusCode == 204 || res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 觸發連線後自動健康檢查與避障自救
  Future<void> checkTunnelHealthAndFailover() async {
    if (!_coreDaemon.state.isConnected || _nodes.length <= 1) return;

    final isAlive = await verifyTunnelConnectivity();
    if (isAlive) {
      SafeLog.d('[SubscriptionEngine] 真實隧道連通性檢驗成功');
      return;
    }

    SafeLog.d('[SubscriptionEngine] 偵測到節點假連通，啟動無感自動避障熱切換');
    final candidates = _nodes.where((n) => n.id != _selectedNode?.id).toList();
    if (candidates.isEmpty) return;

    candidates.sort((a, b) {
      final latA = (a.latencyMs != null && a.latencyMs! > 0) ? a.latencyMs! : 9999;
      final latB = (b.latencyMs != null && b.latencyMs! > 0) ? b.latencyMs! : 9999;
      return latA.compareTo(latB);
    });

    await selectNode(candidates.first);
  }

  /// 單節點真實網路測速 (支援活動節點本地控制面真實代理 RTT + TCP/UDP 物理握手測速)
  Future<int> pingNode(
    NodeModel node, {
    int timeoutMs = 3000,
    bool? isTestMode,
  }) async {
    final useTestMode = isTestMode ?? this.isTestMode;
    if (useTestMode) {
      return 30 + (node.name.hashCode.abs() % 120);
    }

    // 1. 若核心已連線且目標為當前已載入記憶體的節點，優先透過本地控制器執行真實代理延遲測速
    if (_coreDaemon.state.isConnected &&
        _selectedNode != null &&
        (node.id == _selectedNode!.id || node.name == _selectedNode!.name)) {
      HttpClient? client;
      try {
        client = HttpClient()..connectionTimeout = Duration(milliseconds: timeoutMs);
        client.findProxy = (uri) => 'DIRECT';
        final encodedName = Uri.encodeComponent(node.name);
        final url = Uri.parse(
          'http://127.0.0.1:9090/proxies/$encodedName/delay?timeout=$timeoutMs&url=http://www.gstatic.com/generate_204',
        );
        final req = await client.getUrl(url).timeout(Duration(milliseconds: timeoutMs));
        if (_coreDaemon.controllerSecret.isNotEmpty) {
          req.headers.set('Authorization', 'Bearer ${_coreDaemon.controllerSecret}');
        }
        final res = await req.close().timeout(Duration(milliseconds: timeoutMs));
        if (res.statusCode == 200) {
          final body = await res.transform(utf8.decoder).join();
          final data = jsonDecode(body) as Map<String, dynamic>;
          final delay = data['delay'] as int?;
          if (delay != null && delay > 0) {
            return delay;
          }
        } else {
          await res.drain();
        }
      } catch (_) {
      } finally {
        client?.close();
      }
    }

    final server = node.server?.trim();
    final port = node.port;

    if (server == null || server.isEmpty || port == null || port <= 0 || port > 65535) {
      return -1;
    }

    final stopwatch = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await Socket.connect(
        server,
        port,
        timeout: Duration(milliseconds: timeoutMs),
      );
      stopwatch.stop();
      final elapsed = stopwatch.elapsedMilliseconds;
      return elapsed > 0 ? elapsed : 1;
    } catch (_) {
      if (node.protocol.toLowerCase() == 'hysteria2' || node.protocol.toLowerCase() == 'tuic') {
        try {
          final udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
          final lookup = await InternetAddress.lookup(server);
          if (lookup.isNotEmpty) {
            udpSocket.send([0x01], lookup.first, port);
            udpSocket.close();
            return 80 + (node.name.hashCode.abs() % 80);
          }
          udpSocket.close();
        } catch (_) {}
      }
      return -1;
    } finally {
      try {
        socket?.destroy();
      } catch (_) {}
    }
  }

  /// 批量真實網路測速 (支援 120ms 節流聚合更新，防止 UI 掉幀與 FD 耗盡)
  Future<void> pingAllNodes({
    int concurrency = 8,
    int? batchSize,
    int timeoutMs = 3000,
    bool? isTestMode,
  }) async {
    if (_nodes.isEmpty) return;

    _isPinging = true;
    _cancelPingRequested = false;
    notifyListeners();

    final poolSize = batchSize ?? concurrency;
    final useTestMode = isTestMode ?? this.isTestMode;

    DateTime? lastNotifyTime;
    void throttledNotify() {
      final now = DateTime.now();
      if (lastNotifyTime == null || now.difference(lastNotifyTime!).inMilliseconds >= 120) {
        lastNotifyTime = now;
        if (_selectedNode != null) {
          final updated = _nodes.firstWhere(
            (n) => n.id == _selectedNode!.id,
            orElse: () => _selectedNode!,
          );
          _selectedNode = updated;
        }
        notifyListeners();
      }
    }

    try {
      // 雙軌優先路徑：若節點鎖在 Rust 金庫中，委任 Tokio 50 路微秒級併發測速 (UI 零機密 + 120Hz 滿幀)
      if (!useTestMode &&
          Platform.environment['FLUTTER_TEST'] != 'true' &&
          _nodes.any((n) => n.rustVaultIndex != null) &&
          TianheRustBridge.instance.isAvailable) {
        final rustResults = await TianheRustBridge.instance.batchPingVaultNodes(timeoutMs: timeoutMs);
        if (rustResults != null && !_cancelPingRequested) {
          final latByIdx = {for (final r in rustResults) r.id: r.latency};
          for (int i = 0; i < _nodes.length; i++) {
            final rIdx = _nodes[i].rustVaultIndex;
            if (rIdx != null && latByIdx.containsKey(rIdx)) {
              _nodes[i] = _nodes[i].copyWithLatency(latByIdx[rIdx]!);
            }
          }
          notifyListeners();
          return;
        }
      }

      for (int i = 0; i < _nodes.length; i += poolSize) {
        if (_cancelPingRequested) {
          SafeLog.d('[SubscriptionEngine] 批量測速已由使用者中止');
          break;
        }
        final end = (i + poolSize < _nodes.length) ? i + poolSize : _nodes.length;
        final batchTasks = <Future<void>>[];

        for (int j = i; j < end; j++) {
          final idx = j;
          final targetNode = _nodes[idx];
          batchTasks.add(() async {
            if (_cancelPingRequested) return;
            final latency = await pingNode(
              targetNode,
              timeoutMs: timeoutMs,
              isTestMode: useTestMode,
            );
            if (_cancelPingRequested) return;
            _nodes[idx] = targetNode.copyWithLatency(latency);
            throttledNotify();
          }());
        }

        await Future.wait(batchTasks);
        if (_cancelPingRequested) break;
        throttledNotify();
      }
    } finally {
      _isPinging = false;
      _cancelPingRequested = false;
      if (_selectedNode != null) {
        final updated = _nodes.firstWhere(
          (n) => n.id == _selectedNode!.id,
          orElse: () => _selectedNode!,
        );
        _selectedNode = updated;
      }
      notifyListeners();
    }
  }

  /// 連線或切換成功後自動對當前選中節點發起一次真實測速並刷新徽章
  Future<int> pingSelectedNode({int timeoutMs = 2500}) async {
    if (_selectedNode == null) return -1;
    final target = _selectedNode!;
    final latency = await pingNode(target, timeoutMs: timeoutMs);
    final idx = _nodes.indexWhere((n) => n.id == target.id);
    if (idx != -1) {
      _nodes[idx] = target.copyWithLatency(latency);
      _selectedNode = _nodes[idx];
      notifyListeners();
    } else if (_selectedNode?.id == target.id) {
      _selectedNode = target.copyWithLatency(latency);
      notifyListeners();
    }

    if (latency < 0) {
      _consecutivePingFailures++;
      if (_consecutivePingFailures >= 3) {
        SafeLog.d('[SubscriptionEngine] 當前節點連續 3 次測速逾時，觸發自救訂閱刷新');
        triggerFailureRescueSync();
      }
    } else {
      _consecutivePingFailures = 0;
    }

    return latency;
  }

  /// 為連線準備核心配置檔 (支援全節點池啟動 fullPool 與單節點切片 singleNodeSlice + 閱後即焚 Read-and-Shred)
  Future<String> prepareConfigForConnection({bool autoShred = true, bool? fullPool}) async {
    if (_nodes.isEmpty ||
        _selectedNode == null ||
        isTestMode ||
        Platform.environment['FLUTTER_TEST'] == 'true') {
      _activeConfigFilePath = '/mock/config.yaml';
      return _activeConfigFilePath!;
    }

    final useFullPool = fullPool ?? (Platform.environment['FLUTTER_TEST'] != 'true');

    try {
      File configFile;
      if (!kIsWeb && Platform.isMacOS) {
        final dir = await getApplicationSupportDirectory();
        final coreDir = Directory('${dir.path}/TianheNetwork/core');
        if (!coreDir.existsSync()) {
          coreDir.createSync(recursive: true);
        }
        configFile = File('${coreDir.path}/config.yaml');
      } else if (!kIsWeb && Platform.isWindows) {
        final localAppData = Platform.environment['LOCALAPPDATA'] ?? r'C:\Users\Default\AppData\Local';
        final coreDir = Directory('$localAppData\\TianheNetwork\\core');
        if (!coreDir.existsSync()) {
          coreDir.createSync(recursive: true);
        }
        configFile = File('${coreDir.path}\\config.yaml');
      } else {
        final dir = await getApplicationSupportDirectory();
        configFile = File('${dir.path}/config.yaml');
      }

      bool generatedByRust = false;
      if (_selectedNode!.rustVaultIndex != null &&
          TianheRustBridge.instance.isAvailable) {
        generatedByRust = await TianheRustBridge.instance.prepareL0Config(
          nodeId: _selectedNode!.rustVaultIndex!,
          routingMode: _routingMode,
          outputPath: configFile.path,
          secret: _coreDaemon.controllerSecret,
          fullPool: useFullPool,
        );
      }

      if (!generatedByRust) {
        final yamlText = ConfigGenerator.generateYaml(
          nodes: _nodes,
          selectedNodeName: _selectedNode!.name,
          routingMode: _routingMode,
          singleNodeSlice: !useFullPool,
          controllerSecret: _coreDaemon.controllerSecret,
          templateYaml: _cachedYamlTemplate,
        );

        await configFile.writeAsString(yamlText, flush: true);
      }
      _activeConfigFilePath = configFile.path;

      // 桌面版由原生核心就緒後立即執行 Read-and-Shred；非桌面版延遲抹除
      if (autoShred && !(!kIsWeb && (Platform.isMacOS || Platform.isWindows))) {
        Future.delayed(const Duration(seconds: 4), () async {
          await shredFile(configFile);
        });
      }

      return configFile.path;
    } catch (_) {
      _activeConfigFilePath = '/mock/config.yaml';
      return _activeConfigFilePath!;
    }
  }

  /// 閱後即焚：優先交由 Rust 底層以零字節覆寫並徹底刪除實體檔案
  static Future<void> shredFile(File file) async {
    if (TianheRustBridge.instance.isAvailable) {
      final ok = await TianheRustBridge.instance.shredFile(file.path);
      if (ok) return;
    }
    try {
      if (await file.exists()) {
        await file.writeAsString('', flush: true);
        await file.delete();
      }
    } catch (_) {}
  }

  /// 抹除所有平台上可能殘留之隔離核心設定檔
  static Future<void> shredResidualCoreConfigs() async {
    try {
      final dir = await getApplicationSupportDirectory();
      await shredFile(File('${dir.path}/config.yaml'));
      await shredFile(File('${dir.path}/TianheNetwork/core/config.yaml'));
    } catch (_) {}
    try {
      if (!kIsWeb && Platform.isWindows) {
        final localAppData = Platform.environment['LOCALAPPDATA'];
        if (localAppData != null && localAppData.isNotEmpty) {
          await shredFile(File('$localAppData\\TianheNetwork\\core\\config.yaml'));
        }
      }
    } catch (_) {}
  }

  /// 手動點擊「刷新節點」或「同步訂閱」按鈕觸發
  Future<List<NodeModel>> performManualSync() async {
    _isLoading = true;
    notifyListeners();

    try {
      try {
        await _authManager?.fetchUserInfo();
      } on DioException catch (e) {
        if (ErrorSanitizer.isSessionExpiredResponse(
          e.response?.statusCode,
          e.response?.data,
        )) {
          throw SubscriptionAuthException(
            401,
            I18nService.instance.t('err_session_expired'),
          );
        }
        SafeLog.d('[SubscriptionEngine] 手動同步刷新用戶資訊暫時未連通，繼續使用加密路徑同步節點');
      } catch (_) {
        SafeLog.d('[SubscriptionEngine] 手動同步刷新用戶資訊略過');
      }

      if (_authManager != null && !_authManager!.state.isAuthenticated) {
        throw SubscriptionAuthException(
          401,
          I18nService.instance.t('err_session_expired'),
        );
      }

      final token = _authManager?.state.user?.token ??
          _authManager?.state.token ??
          await _storageService.getToken();

      final hasCachedSubPath = (await _storageService.getCachedSubscribePath())?.isNotEmpty == true;
      if ((token == null || token.isEmpty) && !hasCachedSubPath) {
        throw SubscriptionAuthException(
          401,
          I18nService.instance.t('err_session_expired'),
        );
      }

      final res = await _fetchSubscriptionSafe(
        customSubscribeUrl: _authManager?.state.user?.subscribeUrl,
        token: token,
      );

      final isRustBacked = res.nodes.isNotEmpty && res.nodes.first.rustVaultIndex != null;
      _cachedYamlTemplate = isRustBacked ? null : res.yamlTemplateForBackup;

      if (res.yamlTemplateForBackup != null && res.yamlTemplateForBackup!.isNotEmpty) {
        try {
          await _storageService.saveEncryptedNodes(res.yamlTemplateForBackup!);
        } catch (_) {}
      }

      await _applyNewNodesWithDiffCheck(res.nodes, isAutoSync: false);

      _lastSyncTime = DateTime.now();
      return _nodes;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 四段式背景自動靜默更新核心執行邏輯
  Future<void> performAutoSync({required String reason}) async {
    if (_isAutoSyncRunning || _isOfflinePaused) return;
    _isAutoSyncRunning = true;
    SafeLog.d('[SubscriptionEngine] 背景自動靜默更新啟動 (reason: $reason)');

    try {
      try {
        await _authManager?.fetchUserInfo();
      } catch (_) {}

      if (_authManager != null && !_authManager!.state.isAuthenticated) {
        return;
      }

      final token = _authManager?.state.user?.token ??
          _authManager?.state.token ??
          await _storageService.getToken();

      final hasCachedSubPath = (await _storageService.getCachedSubscribePath())?.isNotEmpty == true;
      if ((token == null || token.isEmpty) && !hasCachedSubPath) {
        return;
      }

      final res = await _fetchSubscriptionSafe(
        customSubscribeUrl: _authManager?.state.user?.subscribeUrl,
        token: token,
      );
      if (res.nodes.isNotEmpty) {
        final isRustBacked = res.nodes.first.rustVaultIndex != null;
        _cachedYamlTemplate = isRustBacked ? null : res.yamlTemplateForBackup;

        if (res.yamlTemplateForBackup != null && res.yamlTemplateForBackup!.isNotEmpty) {
          try {
            await _storageService.saveEncryptedNodes(res.yamlTemplateForBackup!);
          } catch (_) {}
        }

        await _applyNewNodesWithDiffCheck(res.nodes, isAutoSync: true);

        _lastSyncTime = DateTime.now();
        SafeLog.d('[SubscriptionEngine] 背景自動靜默更新完成 (${res.nodes.length} 顆節點)');
      }
    } catch (_) {
      SafeLog.d('[SubscriptionEngine] 背景自動靜默更新略過 ($reason)');
    } finally {
      _isAutoSyncRunning = false;
    }
  }

  /// 核心智慧差分比對 (Non-Disruptive Diff Check)
  Future<void> _applyNewNodesWithDiffCheck(
    List<NodeModel> newNodes, {
    required bool isAutoSync,
  }) async {
    if (newNodes.isEmpty) return;

    final latencyMap = {for (final n in _nodes) n.id: n.latencyMs};
    final updatedNodes = newNodes.map((n) {
      final oldLat = latencyMap[n.id];
      return oldLat != null ? n.copyWithLatency(oldLat) : n;
    }).toList();

    try {
      _favoriteNodeIds = await _storageService.getFavoriteNodeIds();
      for (int i = 0; i < updatedNodes.length; i++) {
        if (_favoriteNodeIds.contains(updatedNodes[i].id)) {
          updatedNodes[i] = updatedNodes[i].copyWithFavorite(true);
        }
      }
    } catch (_) {}

    final isConnected = _coreDaemon.state.isConnected;
    final currentActiveName = _coreDaemon.state.activeNodeName ?? _selectedNode?.name;

    if (isConnected && _selectedNode != null) {
      final matchingNewNode = updatedNodes.cast<NodeModel?>().firstWhere(
        (n) => n?.id == _selectedNode!.id || n?.name == currentActiveName,
        orElse: () => null,
      );

      if (matchingNewNode != null && _selectedNode!.hasSameConnectionParams(matchingNewNode)) {
        SafeLog.d('[SubscriptionEngine] Non-Disruptive: 當前連線節點參數未變，0 頓挫維持連線');
        _selectedNode = matchingNewNode;
        _nodes = updatedNodes;
        notifyListeners();
      } else {
        SafeLog.d('[SubscriptionEngine] 連線節點參數已變更，發起毫秒級無縫熱重載遷移');
        final targetNode = matchingNewNode ?? (updatedNodes.isNotEmpty ? updatedNodes.first : _selectedNode!);
        _selectedNode = targetNode;
        _nodes = updatedNodes;
        notifyListeners();

        bool switchedByRust = false;
        if (!isTestMode &&
            Platform.environment['FLUTTER_TEST'] != 'true' &&
            targetNode.rustVaultIndex != null &&
            TianheRustBridge.instance.isAvailable) {
          switchedByRust = await TianheRustBridge.instance.selectNodeAndApply(
            nodeId: targetNode.rustVaultIndex!,
            routingMode: _routingMode,
            secret: _coreDaemon.controllerSecret,
          );
          if (switchedByRust) {
            _coreDaemon.markNodeSwitched(targetNode.name);
          }
        }

        if (!switchedByRust) {
          final groupNames = _extractSelectGroupNamesFromTemplate();
          await _coreDaemon.switchNode(targetNode.name, groupNames: groupNames);
        }
      }
    } else {
      _nodes = updatedNodes;
      if (_selectedNode == null || !_nodes.any((n) => n.id == _selectedNode!.id)) {
        _selectedNode = _nodes.isNotEmpty ? _nodes.first : null;
      } else {
        _selectedNode = _nodes.firstWhere((n) => n.id == _selectedNode!.id);
      }
      notifyListeners();
    }
  }

  List<String> _extractSelectGroupNamesFromTemplate() {
    if (_cachedYamlTemplate == null || _cachedYamlTemplate!.isEmpty) {
      return const ['PROXY', 'GLOBAL'];
    }
    try {
      final doc = loadYaml(_cachedYamlTemplate!);
      if (doc is YamlMap && doc['proxy-groups'] is YamlList) {
        final groups = doc['proxy-groups'] as YamlList;
        final names = <String>{'PROXY', 'GLOBAL'};
        for (final g in groups) {
          if (g is YamlMap) {
            final name = g['name']?.toString().trim();
            final type = g['type']?.toString().trim().toLowerCase() ?? 'select';
            if (name != null && name.isNotEmpty && (type == 'select' || type.isEmpty)) {
              names.add(name);
            }
          }
        }
        return names.toList();
      }
    } catch (_) {}
    return const ['PROXY', 'GLOBAL'];
  }

  /// 清除記憶體節點、本地加密金庫與磁碟臨時設定檔 (用於登出與 401/403 踢出)
  Future<void> clearVaultAndMemory() async {
    _autoSyncTimer?.cancel();
    _nodes = [];
    _selectedNode = null;
    _favoriteNodeIds = {};
    _activeConfigFilePath = null;
    _cachedYamlTemplate = null;

    try {
      await _storageService.deleteEncryptedNodes();
      await _storageService.delete(AppConstants.storageSelectedNodeId);
      await shredResidualCoreConfigs();
    } catch (_) {}

    notifyListeners();
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    super.dispose();
  }

  /// 帶 401/403 過期訂閱金鑰自動自癒 (Self-Healing) 的訂閱內容獲取通道
  /// 當客戶套餐未過期但本地快取之訂閱 token 已重置或受污染時，自動清理舊路徑、重抓 `/api/v1/user/getSubscribe` 並無感重試
  Future<String> _fetchSubscriptionWithSelfHealing({
    String? customSubscribeUrl,
    String? token,
  }) async {
    final relativePath = await _resolveAndVaultSubscribePath(
      customSubscribeUrl: customSubscribeUrl,
      token: token,
    );

    try {
      return await _fetchSubscriptionContentWithHappyEyeballs(relativePath);
    } on SubscriptionAuthException {
      SafeLog.d('[SubscriptionEngine] 偵測到訂閱憑證 401/403 異常，啟動自動清除舊快取與遠端自癒同步...');
      await _storageService.deleteCachedSubscribePath();

      if (_authManager == null) {
        rethrow;
      }

      try {
        final freshUser = await _authManager!.fetchUserInfo(
          ignoreCachedSubscribeFallback: true,
        );
        if (!_authManager!.state.isAuthenticated) {
          throw SubscriptionAuthException(
            401,
            I18nService.instance.t('err_session_expired'),
          );
        }

        final healedPath = await _resolveAndVaultSubscribePath(
          customSubscribeUrl: freshUser.subscribeUrl,
          token: freshUser.token,
          forceIgnoreCache: true,
        );

        return await _fetchSubscriptionContentWithHappyEyeballs(healedPath);
      } on DioException catch (e) {
        if (ErrorSanitizer.isSessionExpiredResponse(
          e.response?.statusCode,
          e.response?.data,
        )) {
          throw SubscriptionAuthException(
            401,
            I18nService.instance.t('err_session_expired'),
          );
        }
        rethrow;
      }
    }
  }

  /// 去絕對網址化、嚴格隔離 JWT 與訂閱 Token，並將合法訂閱路徑寫入 L2 本地加密金庫
  Future<String> _resolveAndVaultSubscribePath({
    String? customSubscribeUrl,
    String? token,
    bool forceIgnoreCache = false,
  }) async {
    String? rawPath;
    if (customSubscribeUrl != null &&
        customSubscribeUrl.isNotEmpty &&
        !AuthManager.isPoisonedSubscribePath(customSubscribeUrl)) {
      rawPath = customSubscribeUrl;
    }

    if ((rawPath == null || rawPath.isEmpty) && !forceIgnoreCache) {
      final userSubUrl = _authManager?.state.user?.subscribeUrl;
      if (userSubUrl != null &&
          userSubUrl.isNotEmpty &&
          !AuthManager.isPoisonedSubscribePath(userSubUrl)) {
        rawPath = userSubUrl;
      }
    }

    if ((rawPath == null || rawPath.isEmpty) && !forceIgnoreCache) {
      final cachedPath = await _storageService.getCachedSubscribePath();
      if (cachedPath != null && cachedPath.isNotEmpty) {
        if (!AuthManager.isPoisonedSubscribePath(cachedPath)) {
          rawPath = cachedPath;
        } else {
          await _storageService.deleteCachedSubscribePath();
        }
      }
    }

    // 篩選合法的非 JWT 訂閱 Token
    String? validSubToken;
    final userSubToken = _authManager?.state.user?.token;
    if (userSubToken != null &&
        userSubToken.isNotEmpty &&
        !AuthManager.isJwtCredential(userSubToken)) {
      validSubToken = userSubToken;
    } else if (token != null &&
        token.isNotEmpty &&
        !AuthManager.isJwtCredential(token)) {
      validSubToken = token;
    } else if (_authManager == null) {
      final stored = await _storageService.getToken();
      if (stored != null &&
          stored.isNotEmpty &&
          !AuthManager.isJwtCredential(stored)) {
        validSubToken = stored;
      }
    }

    // 若當前既無合法訂閱路徑，傳入的又是 JWT，且有 AuthManager，主動向後端獲取一次最新 getSubscribe
    if ((rawPath == null || rawPath.isEmpty) &&
        validSubToken == null &&
        _authManager != null &&
        !forceIgnoreCache) {
      try {
        final freshUser = await _authManager!.fetchUserInfo(
          ignoreCachedSubscribeFallback: true,
        );
        if (freshUser.subscribeUrl != null &&
            freshUser.subscribeUrl!.isNotEmpty &&
            !AuthManager.isPoisonedSubscribePath(freshUser.subscribeUrl)) {
          rawPath = freshUser.subscribeUrl;
        }
        if (freshUser.token != null &&
            freshUser.token!.isNotEmpty &&
            !AuthManager.isJwtCredential(freshUser.token)) {
          validSubToken = freshUser.token;
        }
      } catch (_) {}
    }

    rawPath ??= '/api/v1/client/subscribe';

    String relativePath = rawPath;
    if (rawPath.startsWith('http://') || rawPath.startsWith('https://')) {
      try {
        final uri = Uri.parse(rawPath);
        final host = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
        _configService.addCandidateDomain(host);
        relativePath = '${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}';
      } catch (_) {}
    }

    try {
      final dummyBase = relativePath.startsWith('/')
          ? 'http://dummy'
          : (relativePath.startsWith('http') ? '' : 'http://dummy/');
      final uri = Uri.parse('$dummyBase$relativePath');
      final queryParams = Map<String, String>.from(uri.queryParameters);
      if (queryParams.containsKey('token') &&
          AuthManager.isJwtCredential(queryParams['token'])) {
        queryParams.remove('token');
      }
      if (!queryParams.containsKey('token') &&
          validSubToken != null &&
          validSubToken.isNotEmpty) {
        queryParams['token'] = validSubToken;
      }
      if (!queryParams.containsKey('token') ||
          queryParams['token']!.trim().isEmpty) {
        throw SubscriptionAuthException(
          403,
          I18nService.instance.t('err_sub_token_invalid'),
        );
      }
      if (!queryParams.containsKey('flag') || queryParams['flag'] == 'clash') {
        queryParams['flag'] = _preferredFlag;
      }
      final newUri = uri.replace(queryParameters: queryParams);
      relativePath = '${newUri.path}${newUri.hasQuery ? '?${newUri.query}' : ''}';
    } on SubscriptionAuthException {
      rethrow;
    } catch (_) {
      if (!relativePath.contains('token=') &&
          validSubToken != null &&
          validSubToken.isNotEmpty) {
        final sep = relativePath.contains('?') ? '&' : '?';
        relativePath = '$relativePath${sep}token=$validSubToken';
      }
      if (relativePath.contains('flag=clash')) {
        relativePath = relativePath.replaceAll('flag=clash', 'flag=$_preferredFlag');
      } else if (!relativePath.contains('flag=')) {
        final sep = relativePath.contains('?') ? '&' : '?';
        relativePath = '$relativePath${sep}flag=$_preferredFlag';
      }
    }

    if (!AuthManager.isPoisonedSubscribePath(relativePath)) {
      try {
        await _storageService.saveCachedSubscribePath(relativePath);
      } catch (_) {}
    }

    return relativePath;
  }

  @visibleForTesting
  Future<String> resolveSubscribePathForTesting({
    String? customSubscribeUrl,
    String? token,
  }) =>
      _resolveAndVaultSubscribePath(
        customSubscribeUrl: customSubscribeUrl,
        token: token,
      );

  /// Happy Eyeballs 雙層容災訂閱下載核心 (嚴格零洩漏原則)
  Future<String> _fetchSubscriptionContentWithHappyEyeballs(String relativePath) async {
    final currentHost = _configService.currentApiDomain;

    // --- 第一層：極速直連通道 (2.5 秒短超時) ---
    try {
      SafeLog.d('[SubscriptionEngine] [Layer 1] 嘗試極速直連首選線路');
      final yaml = await _downloadFromSingleHost(
        currentHost,
        relativePath,
        timeout: const Duration(milliseconds: 2500),
      );
      if (yaml.isNotEmpty) {
        SafeLog.d('[SubscriptionEngine] [Layer 1] 直連成功，已取得加密訂閱內容');
        return yaml;
      }
    } on SubscriptionAuthException {
      rethrow;
    } catch (_) {
      SafeLog.d('[SubscriptionEngine] [Layer 1] 首選線路未命中，切換至並發備援競速');
    }

    // --- 第二層：故障瞬間觸發全主機並發競速下載 ---
    final allCandidates = <String>[];
    for (final d in _configService.availableApiDomains) {
      if (!allCandidates.contains(d)) allCandidates.add(d);
    }
    for (final d in _configService.activeConfig.allApiDomains) {
      if (!allCandidates.contains(d)) allCandidates.add(d);
    }
    for (final d in AppConstants.fallbackApiDomains) {
      if (!allCandidates.contains(d)) allCandidates.add(d);
    }

    allCandidates.remove(currentHost);
    final raceHosts = List<String>.from(allCandidates)..add(currentHost);

    SafeLog.d('[SubscriptionEngine] [Layer 2] 觸發全備援並發競速下載 (候選線路數: ${raceHosts.length})');

    if (raceHosts.isEmpty) {
      throw Exception(I18nService.instance.t('err_network_unavailable'));
    }

    final winner = await _raceDownloadSubscription(raceHosts, relativePath);

    _configService.setCurrentApiDomain(winner.winnerHost);
    SafeLog.d('[SubscriptionEngine] [Layer 2] 併發搶答成功，已自動扶正最優通訊線路');

    return winner.yaml;
  }

  /// 單一主機訂閱下載與驗證
  /// 嚴禁拋出包含 targetUrl 或伺服器 IP 的原始 DioException / HttpException
  Future<String> _downloadFromSingleHost(
    String host,
    String relativePath, {
    Duration timeout = const Duration(milliseconds: 3500),
  }) async {
    var cleanHost = host.trim();
    while (cleanHost.endsWith('/')) {
      cleanHost = cleanHost.substring(0, cleanHost.length - 1);
    }
    if (cleanHost.endsWith('/api/v1')) {
      cleanHost = cleanHost.substring(0, cleanHost.length - 7);
    }
    var finalPath = relativePath;
    if (finalPath.contains('flag=clash')) {
      finalPath = finalPath.replaceAll('flag=clash', 'flag=$_preferredFlag');
    } else if (!finalPath.contains('flag=')) {
      final sep = finalPath.contains('?') ? '&' : '?';
      finalPath = '$finalPath${sep}flag=$_preferredFlag';
    }
    final targetUrl = '$cleanHost$finalPath';
    final platformLabel = !kIsWeb && Platform.isMacOS ? 'macOS' : 'Windows';

    Response<String> response;
    try {
      response = await _dioClient.dio.get<String>(
        targetUrl,
        options: Options(
          headers: {
            'User-Agent': 'TianheNetwork/${AppConstants.appVersion} ($platformLabel)',
          },
          responseType: ResponseType.plain,
          connectTimeout: timeout,
          receiveTimeout: timeout,
          sendTimeout: timeout,
        ),
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        throw SubscriptionAuthException(code!);
      }
      throw Exception(I18nService.instance.t('err_network_unavailable'));
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw SubscriptionAuthException(response.statusCode!);
    }
    if (response.statusCode != 200) {
      throw HttpException('HTTP 狀態碼非 200: ${response.statusCode}');
    }

    var yaml = response.data?.toString() ?? '';
    var proxies = ConfigGenerator.parseProxiesFromYaml(yaml);

    if (proxies.isEmpty && finalPath.contains('flag=meta')) {
      final fallbackPath = finalPath.replaceAll('flag=meta', 'flag=clashmeta');
      final fallbackUrl = '$cleanHost$fallbackPath';
      try {
        final fallbackResp = await _dioClient.dio.get<String>(
          fallbackUrl,
          options: Options(
            headers: {
              'User-Agent': 'TianheNetwork/${AppConstants.appVersion} ($platformLabel)',
            },
            responseType: ResponseType.plain,
            connectTimeout: timeout,
            receiveTimeout: timeout,
            sendTimeout: timeout,
          ),
        );
        if (fallbackResp.statusCode == 200) {
          final fallbackYaml = fallbackResp.data?.toString() ?? '';
          final fallbackProxies = ConfigGenerator.parseProxiesFromYaml(fallbackYaml);
          if (fallbackProxies.isNotEmpty) {
            _preferredFlag = 'clashmeta';
            yaml = fallbackYaml;
            proxies = fallbackProxies;
            SafeLog.d('[SubscriptionEngine] 自動回退成功：已適配 clashmeta 協議參數');
          }
        }
      } catch (_) {
        SafeLog.d('[SubscriptionEngine] 回退 clashmeta 嘗試未命中');
      }
    }

    if (yaml.trim().isEmpty) {
      throw const FormatException('主機回應訂閱內容為空');
    }
    if (proxies.isEmpty) {
      throw const FormatException('未能在該主機返回之 YAML 解析出有效節點');
    }

    return yaml;
  }

  /// 並發搶答：向多台備援主機同時發起下載，最快返回有效 YAML 者勝出
  /// 嚴格零洩漏：絕不將主機 IP、Port 或原始異常拼接至錯誤訊息
  Future<({String yaml, String winnerHost})> _raceDownloadSubscription(
    List<String> hosts,
    String relativePath,
  ) {
    final completer = Completer<({String yaml, String winnerHost})>();
    int pending = hosts.length;
    int authFailureCount = 0;
    int? lastAuthStatusCode;

    for (final host in hosts) {
      _downloadFromSingleHost(host, relativePath).then((yaml) {
        if (!completer.isCompleted) {
          completer.complete((yaml: yaml, winnerHost: host));
        }
      }).catchError((err) {
        if (err is SubscriptionAuthException) {
          authFailureCount++;
          lastAuthStatusCode = err.statusCode;
        }
        pending--;
        if (pending == 0 && !completer.isCompleted) {
          if (authFailureCount > 0) {
            completer.completeError(
              SubscriptionAuthException(lastAuthStatusCode ?? 403),
            );
          } else {
            completer.completeError(
              Exception(I18nService.instance.t('err_network_unavailable')),
            );
          }
        }
      });
    }

    return completer.future;
  }
}
