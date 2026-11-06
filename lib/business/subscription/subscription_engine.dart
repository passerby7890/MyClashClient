// lib/business/subscription/subscription_engine.dart

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/network/dio_client.dart';
import '../../core/storage/secure_storage_service.dart';
import '../../infrastructure/config/app_config_service.dart';
import '../../infrastructure/core_daemon/core_daemon.dart';
import '../auth/auth_manager.dart';
import 'config_generator.dart';
import 'node_model.dart';

/// 訂閱與節點引擎 (Subscription Engine)
/// 核心樞紐：獲取遠端加密訂閱、加密金庫持久化、單節點切片與閱後即焚
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

  DateTime? _lastSyncTime;
  DateTime? get lastSyncTime => _lastSyncTime;

  DateTime? _lastRescueSyncTime;
  DateTime? get lastRescueSyncTime => _lastRescueSyncTime;
  int _consecutivePingFailures = 0;

  void attachAuthManager(AuthManager authManager) {
    _authManager = authManager;
  }

  /// 啟動「四段式背景自動靜默更新引擎 (Auto-Sync Daemon)」
  /// 1. 定時巡航：每 10 分鐘 ± 60 秒隨機 Jitter 靜默同步
  /// 2. 冷啟動延遲 2 秒背景靜默同步
  void initAutoSyncDaemon() {
    _scheduleNextAutoSync();

    // 冷啟動延遲 2 秒在背景執行一次靜默同步
    Future.delayed(const Duration(seconds: 2), () {
      performAutoSync(reason: 'cold_start');
    });
  }

  /// 預設背景靜默自動同步週期 (10 分鐘)
  static const Duration defaultAutoSyncInterval = Duration(minutes: 10);

  /// 隨機抖動排程 (每 10 分鐘加上 ±60 秒隨機偏移，防止併發洪峰)
  void _scheduleNextAutoSync() {
    _autoSyncTimer?.cancel();
    final randomJitterSeconds = 540 + math.Random().nextInt(121); // 540..660 秒
    _autoSyncTimer = Timer(Duration(seconds: randomJitterSeconds), () async {
      await performAutoSync(reason: 'periodic');
      _scheduleNextAutoSync();
    });
  }

  /// 視窗喚醒/從睡眠或最小化恢復時觸發 (若距離上次同步超過 15 分鐘則立即背景同步)
  void onWindowWakeup() {
    if (_lastSyncTime == null ||
        DateTime.now().difference(_lastSyncTime!) > const Duration(minutes: 15)) {
      debugPrint('[SubscriptionEngine] 視窗喚醒且距離上次同步超過 15 分鐘，觸發背景自動同步');
      performAutoSync(reason: 'window_wakeup');
    }
  }

  /// 連線失敗或連線連續超時自救觸發 (帶 5 分鐘冷卻 CD)
  void triggerFailureRescueSync() {
    final now = DateTime.now();
    if (_lastRescueSyncTime != null &&
        now.difference(_lastRescueSyncTime!) < const Duration(minutes: 5)) {
      debugPrint('[SubscriptionEngine] 自救同步處於 5 分鐘冷卻中，跳過本次觸發');
      return;
    }
    _lastRescueSyncTime = now;
    debugPrint('[SubscriptionEngine] 觸發連線失敗/超時自救背景同步');
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
  /// 耗時 < 10ms，保障重開 App 免等網路即可看見全部 26 顆節點並一鍵連線
  Future<bool> restoreFromVault() async {
    try {
      final cachedYaml = await _storageService.getEncryptedNodes();
      if (cachedYaml == null || cachedYaml.trim().isEmpty) {
        return false;
      }

      final parsedNodes = ConfigGenerator.parseProxiesFromYaml(cachedYaml);
      if (parsedNodes.isEmpty) {
        return false;
      }

      _cachedYamlTemplate = cachedYaml;
      _nodes = parsedNodes;

      // 載入並套用收藏狀態
      try {
        _favoriteNodeIds = await _storageService.getFavoriteNodeIds();
        _applyFavoritesToNodes();
      } catch (_) {}

      // 還原上次選中之節點，若無或已失效則自動預設第 1 顆節點
      final savedSelectedId = await _storageService.read(AppConstants.storageSelectedNodeId);
      if (savedSelectedId != null &&
          _nodes.any((n) => n.id == savedSelectedId || n.name == savedSelectedId)) {
        _selectedNode = _nodes.firstWhere((n) => n.id == savedSelectedId || n.name == savedSelectedId);
      } else {
        _selectedNode = _nodes.first;
      }

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[SubscriptionEngine] 從加密金庫還原節點失敗: $e');
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

  /// 切換節點收藏狀態 (TODO-06)
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

  /// 智慧篩選與排序節點清單 (TODO-06)
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
      list = list.where((n) =>
          n.name.toLowerCase().contains(q) ||
          n.regionName.toLowerCase().contains(q) ||
          n.protocol.toLowerCase().contains(q)).toList();
    }

    if (sortByLowestLatency) {
      list.sort((a, b) {
        final aPing = (a.latencyMs != null && a.latencyMs! > 0) ? a.latencyMs! : 999999;
        final bPing = (b.latencyMs != null && b.latencyMs! > 0) ? b.latencyMs! : 999999;
        return aPing.compareTo(bPing);
      });
    } else {
      // 預設排序：收藏節點置頂
      list.sort((a, b) {
        if (a.isFavorite && !b.isFavorite) return -1;
        if (!a.isFavorite && b.isFavorite) return 1;
        return 0;
      });
    }

    return list;
  }

  /// 靜默拉取並注入訂閱配置 (含 Happy Eyeballs 雙層容災、去絕對網址化與金庫加密落地)
  /// 恪守零明文原則：不在 UI 或任何無加密磁碟位置展示訂閱 URL
  Future<List<NodeModel>> syncSubscription({
    required String token,
    String? customSubscribeUrl,
    int maxRetries = 3,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final relativePath = await _resolveAndVaultSubscribePath(
        customSubscribeUrl: customSubscribeUrl,
        token: token,
      );

      final yamlContent = await _fetchSubscriptionContentWithHappyEyeballs(relativePath);

      final parsedNodes = ConfigGenerator.parseProxiesFromYaml(yamlContent);
      if (parsedNodes.isEmpty) {
        throw const FormatException('未能在訂閱資料中解析出有效節點');
      }

      _cachedYamlTemplate = yamlContent;
      _nodes = parsedNodes;

      // 3. 全量節點加密落地保存至本地加密金庫 (保障磁碟零明文)
      try {
        await _storageService.saveEncryptedNodes(yamlContent);
      } catch (_) {}

      // 載入並套用收藏狀態
      try {
        _favoriteNodeIds = await _storageService.getFavoriteNodeIds();
        _applyFavoritesToNodes();
      } catch (_) {}

      // 4. 首次登入強同步保障：自動將第 1 顆有效節點設為預設選中節點 (100% 杜絕未選中空白狀態)
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
    } catch (e) {
      debugPrint('[SubscriptionEngine] 同步訂閱遭遇異常: $e');
      _isLoading = false;
      notifyListeners();

      // 若網路拉取失敗，但金庫已還原節點，則靜默保留金庫節點，絕不將畫面清空
      if (_nodes.isNotEmpty) {
        debugPrint('[SubscriptionEngine] 網路波動重試耗盡，安全保留金庫已還原節點 ${_nodes.length} 顆');
        return _nodes;
      }
      rethrow;
    }
  }

  /// 選取連線節點 (極速熱切換模式 + 單節點動態切片)
  /// 優先更新內部配置與寫入隔離沙盒，並即時通知核心切換隧道節點與刷新出口連線
  Future<void> selectNode(NodeModel node) async {
    if (_selectedNode?.id == node.id && _coreDaemon.state.isConnected) return;

    _selectedNode = node;
    try {
      await _storageService.write(AppConstants.storageSelectedNodeId, node.id);
    } catch (_) {}
    notifyListeners();

    // 1. 若核心正在運行，進行毫秒級極速熱切換（記憶體 YAML Payload + 策略組指引 + 斬斷舊 TCP 連線）
    if (_coreDaemon.state.isConnected) {
      final effectiveNodes = _nodes.isNotEmpty ? _nodes : [node];
      final yamlPayload = ConfigGenerator.generateYaml(
        nodes: effectiveNodes,
        selectedNodeName: node.name,
        routingMode: _routingMode,
        singleNodeSlice: true,
        controllerSecret: _coreDaemon.controllerSecret,
        templateYaml: _cachedYamlTemplate,
      );

      await _coreDaemon.switchNode(node.name, yamlPayload: yamlPayload);

      // 自動對新節點測速更新延遲
      pingNode(node).catchError((_) => -1);
    } else {
      // 未連線狀態下，預先準備設定檔
      await prepareConfigForConnection(autoShred: false);
    }
  }

  /// 設定分流模式 (rule: 規則分流, global: 全局代理, direct: 直連模式)
  Future<void> setRoutingMode(String mode) async {
    final lower = mode.toLowerCase();
    if (!['rule', 'global', 'direct'].contains(lower)) return;
    _routingMode = lower;
    notifyListeners();

    // 模式變更需重新準備配置並通知核心熱重載
    if (_coreDaemon.state.isConnected && _selectedNode != null) {
      if (!kIsWeb && (Platform.isMacOS || Platform.isWindows)) {
        final effectiveNodes = _nodes.isNotEmpty ? _nodes : [_selectedNode!];
        final yamlPayload = ConfigGenerator.generateYaml(
          nodes: effectiveNodes,
          selectedNodeName: _selectedNode!.name,
          routingMode: _routingMode,
          singleNodeSlice: true,
          controllerSecret: _coreDaemon.controllerSecret,
          templateYaml: _cachedYamlTemplate,
        );
        await _coreDaemon.switchNode(_selectedNode!.name, yamlPayload: yamlPayload);
      } else {
        final configPath = await prepareConfigForConnection(autoShred: true);
        await _coreDaemon.reloadConfig(configPath, selectedNode: _selectedNode!.name);
      }
    }
  }

  /// 一鍵選取延遲最低之最佳節點
  Future<NodeModel?> selectFastestNode({bool? isTestMode}) async {
    if (_nodes.isEmpty) return null;

    final validTested = _nodes.where((n) => n.latencyMs != null && n.latencyMs! > 0).toList();
    if (validTested.isEmpty) {
      await pingAllNodes(isTestMode: isTestMode);
    }

    final candidates = _nodes.where((n) => n.latencyMs != null && n.latencyMs! > 0).toList();
    if (candidates.isEmpty) {
      // 若全部逾時或未成功，回退到第 1 顆節點確保基本可用
      final fallback = _nodes.first;
      await selectNode(fallback);
      return fallback;
    }

    candidates.sort((a, b) => a.latencyMs!.compareTo(b.latencyMs!));
    final fastest = candidates.first;
    await selectNode(fastest);
    return fastest;
  }

  /// 單節點真實 TCP 握手測速 (Real TCP Ping)
  /// 針對節點真實 server 與 port 發起 Socket.connect，以 Stopwatch 測量精準物理延遲 (RTT ms)
  /// 逾時 3000ms 或連線失敗返回 -1 (UI 呈現紅字逾時)
  Future<int> pingNode(
    NodeModel node, {
    int timeoutMs = 3000,
    bool? isTestMode,
  }) async {
    final useTestMode = isTestMode ?? this.isTestMode;
    if (useTestMode) {
      // 僅限單元測試 CI 無外網環境：模擬隨機真實感延遲，非固定線性遞增
      return 30 + (node.name.hashCode.abs() % 120);
    }

    final server = node.server?.trim();
    final port = node.port;

    if (server == null || server.isEmpty || port == null || port <= 0 || port > 65535) {
      return -1; // 無法解析 server/port 視為無效/逾時
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
      // 連線拒絕、DNS 失敗、網路不可達或超時 3000ms
      return -1;
    } finally {
      try {
        socket?.destroy();
      } catch (_) {}
    }
  }

  /// 批量真實網路測速 (真實 TCP 握手測速 - 支援併發池化防範 Socket 資源耗盡)
  /// [concurrency]: 併發池上限（預設 8，避免過多併發導致系統 fd 耗盡或頻寬擁塞）
  /// [batchSize]: 相容舊參數（若傳入優先使用）
  /// [timeoutMs]: 單次連線超時（預設 3000ms）
  /// [isTestMode]: 單元測試專用
  Future<void> pingAllNodes({
    int concurrency = 8,
    int? batchSize,
    int timeoutMs = 3000,
    bool? isTestMode,
  }) async {
    if (_nodes.isEmpty) return;

    final poolSize = batchSize ?? concurrency;
    final useTestMode = isTestMode ?? this.isTestMode;

    for (int i = 0; i < _nodes.length; i += poolSize) {
      final end = (i + poolSize < _nodes.length) ? i + poolSize : _nodes.length;
      final batchTasks = <Future<void>>[];

      for (int j = i; j < end; j++) {
        final idx = j;
        final targetNode = _nodes[idx];
        batchTasks.add(() async {
          final latency = await pingNode(
            targetNode,
            timeoutMs: timeoutMs,
            isTestMode: useTestMode,
          );
          _nodes[idx] = targetNode.copyWithLatency(latency);
        }());
      }

      await Future.wait(batchTasks);

      // 每批測速完成後立即同步當前選中節點並 notifyListeners
      // 帶給使用者即時刷新、逐批跳動的真實測速反饋
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

  /// 連線成功後自動對當前選中節點發起一次真實 TCP 握手測速 (Real TCP Ping)
  Future<int> pingSelectedNode({int timeoutMs = 2500}) async {
    if (_selectedNode == null) return -1;
    final target = _selectedNode!;
    final latency = await pingNode(target, timeoutMs: timeoutMs);
    final idx = _nodes.indexWhere((n) => n.id == target.id);
    if (idx != -1) {
      _nodes[idx] = target.copyWithLatency(latency);
      _selectedNode = _nodes[idx];
      notifyListeners();
    }

    if (latency < 0) {
      _consecutivePingFailures++;
      if (_consecutivePingFailures >= 3) {
        debugPrint('[SubscriptionEngine] 當前節點連續 3 次測速逾時，觸發自救訂閱刷新');
        triggerFailureRescueSync();
      }
    } else {
      _consecutivePingFailures = 0;
    }

    return latency;
  }

  /// 為連線準備單節點切片配置檔 (Single-Node Slicing + 閱後即焚 Read-and-Shred)
  /// [autoShred]: 是否在寫入 500ms 後由系統抹除磁碟實體檔
  Future<String> prepareConfigForConnection({bool autoShred = true}) async {
    if (_nodes.isEmpty || _selectedNode == null || isTestMode || Platform.environment['FLUTTER_TEST'] == 'true') {
      _activeConfigFilePath = '/mock/config.yaml';
      return _activeConfigFilePath!;
    }

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

      // 單節點切片：磁碟 YAML 僅寫入當前選中之 1 顆節點，其餘節點絕不寫入磁碟！
      // 同時動態融合後端 YAML 母體骨架 (完整的 DNS、策略組、分流規則)
      final yamlText = ConfigGenerator.generateYaml(
        nodes: _nodes,
        selectedNodeName: _selectedNode!.name,
        routingMode: _routingMode,
        singleNodeSlice: true,
        controllerSecret: _coreDaemon.controllerSecret,
        templateYaml: _cachedYamlTemplate,
      );

      await configFile.writeAsString(yamlText, flush: true);
      _activeConfigFilePath = configFile.path;

      // 閱後即焚：在 Android 上延遲 500ms 等待核心 Go runtime 載入記憶體後覆寫並刪除磁碟實體檔
      // 在 Windows 上嚴格由 WindowsProxyService 於 127.0.0.1:9090 /version 與 /proxies 返回 200 OK 之後才安全抹除
      if (autoShred && !(!kIsWeb && (Platform.isMacOS || Platform.isWindows))) {
        Future.delayed(const Duration(milliseconds: 500), () async {
          await shredFile(configFile);
        });
      }

      return configFile.path;
    } catch (e) {
      _activeConfigFilePath = '/mock/config.yaml';
      return _activeConfigFilePath!;
    }
  }

  /// 閱後即焚：以空字串覆寫並徹底刪除實體檔案 (防 Root 扒節點)
  static Future<void> shredFile(File file) async {
    try {
      if (await file.exists()) {
        await file.writeAsString('', flush: true);
        await file.delete();
      }
    } catch (_) {}
  }

  /// 手動點擊「刷新節點」或「同步訂閱」按鈕觸發
  /// 同時刷新用戶最新剩餘流量配額 (fetchUserInfo) 與最新 V2Board 訂閱節點
  Future<List<NodeModel>> performManualSync() async {
    _isLoading = true;
    notifyListeners();

    try {
      // 1. 同步刷新使用者資訊與流量配額
      try {
        await _authManager?.fetchUserInfo();
      } catch (e) {
        debugPrint('[SubscriptionEngine] 手動同步刷新用戶資訊提示: $e');
      }

      // 2. 獲取 Token
      final token = _authManager?.state.token ?? await _storageService.getToken();

      if (token == null || token.isEmpty) {
        throw Exception('未檢測到登入憑證');
      }

      // 3. 拉取最新節點 (透過 Happy Eyeballs 雙層容災與去絕對網址化通道)
      final relativePath = await _resolveAndVaultSubscribePath(token: token);
      final yamlContent = await _fetchSubscriptionContentWithHappyEyeballs(relativePath);
      if (yamlContent.isEmpty) {
        throw const FormatException('訂閱內容為空');
      }

      final parsedNodes = ConfigGenerator.parseProxiesFromYaml(yamlContent);
      if (parsedNodes.isEmpty) {
        throw const FormatException('未能在訂閱資料中解析出有效節點');
      }

      _cachedYamlTemplate = yamlContent;

      // 4. 全量節點加密落地保存至本地加密金庫 (保障磁碟零明文)
      try {
        await _storageService.saveEncryptedNodes(yamlContent);
      } catch (_) {}

      // 5. 執行 Non-Disruptive Diff Check 更新
      await _applyNewNodesWithDiffCheck(parsedNodes, isAutoSync: false);

      _lastSyncTime = DateTime.now();
      return _nodes;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 四段式背景自動靜默更新核心執行邏輯
  Future<void> performAutoSync({required String reason}) async {
    if (_isAutoSyncRunning) return;
    _isAutoSyncRunning = true;
    debugPrint('[SubscriptionEngine] 背景自動靜默更新啟動 (reason: $reason)');

    try {
      // 1. 背景靜默更新用戶資訊與剩餘流量配額
      try {
        await _authManager?.fetchUserInfo();
      } catch (_) {}

      final token = _authManager?.state.token ?? await _storageService.getToken();

      if (token == null || token.isEmpty) {
        _isAutoSyncRunning = false;
        return;
      }

      // 2. 靜默拉取最新節點 (Happy Eyeballs 雙層容災)
      final relativePath = await _resolveAndVaultSubscribePath(token: token);
      final yamlContent = await _fetchSubscriptionContentWithHappyEyeballs(relativePath);
      if (yamlContent.isNotEmpty) {
        final parsedNodes = ConfigGenerator.parseProxiesFromYaml(yamlContent);
        if (parsedNodes.isNotEmpty) {
          _cachedYamlTemplate = yamlContent;

          // 3. 全量節點加密落地保存至本地加密金庫 (保障磁碟零明文)
          try {
            await _storageService.saveEncryptedNodes(yamlContent);
          } catch (_) {}

          // 4. 執行 Non-Disruptive Diff Check 更新
          await _applyNewNodesWithDiffCheck(parsedNodes, isAutoSync: true);

          _lastSyncTime = DateTime.now();
          debugPrint('[SubscriptionEngine] 背景自動靜默更新完成 (${parsedNodes.length} 顆節點, reason: $reason)');
        }
      }
    } catch (e) {
      debugPrint('[SubscriptionEngine] 背景自動靜默更新異常 ($reason): $e');
    } finally {
      _isAutoSyncRunning = false;
    }
  }

  /// 核心智慧差分比對 (Non-Disruptive Diff Check)
  /// 鐵律：當前連線節點底層連線參數未變時，絕對禁止呼叫 PUT /configs 重載核心或切斷連線！
  Future<void> _applyNewNodesWithDiffCheck(
    List<NodeModel> newNodes, {
    required bool isAutoSync,
  }) async {
    if (newNodes.isEmpty) return;

    // 保留已測得的延遲數據
    final latencyMap = {for (final n in _nodes) n.id: n.latencyMs};
    final updatedNodes = newNodes.map((n) {
      final oldLat = latencyMap[n.id];
      return oldLat != null ? n.copyWithLatency(oldLat) : n;
    }).toList();

    // 載入並套用收藏
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
      // 尋找匹配節點
      final matchingNewNode = updatedNodes.cast<NodeModel?>().firstWhere(
        (n) => n?.id == _selectedNode!.id || n?.name == currentActiveName,
        orElse: () => null,
      );

      if (matchingNewNode != null && _selectedNode!.hasSameConnectionParams(matchingNewNode)) {
        // ★ 關鍵鐵律 (Non-Disruptive Diff Check)：
        // 當前節點底層連線參數 (IP/Port/UUID/Password/Cipher/TLS) 完全未變
        // 僅靜默更新 UI 節點清單與 L2 金庫，絕對禁止呼叫 PUT /configs 重載核心或切斷現有連線！
        debugPrint('[SubscriptionEngine] Non-Disruptive: 當前連線節點參數未變，靜默更新記憶體與金庫，0 頓挫維持連線');
        _selectedNode = matchingNewNode;
        _nodes = updatedNodes;
        notifyListeners();
      } else {
        // 當前節點已被下架，或 IP/Port/認證參數在後台已變更
        debugPrint('[SubscriptionEngine] 連線節點參數已變更或節點已下架，發起毫秒級無縫熱重載遷移');
        final targetNode = matchingNewNode ?? (updatedNodes.isNotEmpty ? updatedNodes.first : _selectedNode!);
        _selectedNode = targetNode;
        _nodes = updatedNodes;
        notifyListeners();

        // 僅在參數變更時無縫熱切換 (PUT /configs?force=true)
        final yamlPayload = ConfigGenerator.generateYaml(
          nodes: _nodes,
          selectedNodeName: targetNode.name,
          routingMode: _routingMode,
          singleNodeSlice: true,
          controllerSecret: _coreDaemon.controllerSecret,
          templateYaml: _cachedYamlTemplate,
        );
        await _coreDaemon.switchNode(targetNode.name, yamlPayload: yamlPayload);
      }
    } else {
      // 未連線狀態：直接更新列表並選中適當節點
      _nodes = updatedNodes;
      if (_selectedNode == null || !_nodes.any((n) => n.id == _selectedNode!.id)) {
        _selectedNode = _nodes.isNotEmpty ? _nodes.first : null;
      } else {
        _selectedNode = _nodes.firstWhere((n) => n.id == _selectedNode!.id);
      }
      notifyListeners();
    }
  }

  /// 清除記憶體節點、本地加密金庫與磁碟臨時設定檔 (用於登出與 401 踢出)
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
      final dir = await getApplicationSupportDirectory();
      final configFile = File('${dir.path}/config.yaml');
      await shredFile(configFile);
    } catch (_) {}

    notifyListeners();
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    super.dispose();
  }

  /// 去絕對網址化、提取純相對路徑與 Token，並寫入 L2 本地加密金庫
  Future<String> _resolveAndVaultSubscribePath({
    String? customSubscribeUrl,
    String? token,
  }) async {
    String? rawPath = customSubscribeUrl;
    if (rawPath == null || rawPath.isEmpty) {
      rawPath = _authManager?.state.user?.subscribeUrl;
    }
    if (rawPath == null || rawPath.isEmpty) {
      rawPath = await _storageService.getCachedSubscribePath();
    }
    if (rawPath == null || rawPath.isEmpty) {
      rawPath = '/api/v1/client/subscribe';
    }

    String relativePath = rawPath;
    if (rawPath.startsWith('http://') || rawPath.startsWith('https://')) {
      try {
        final uri = Uri.parse(rawPath);
        final host = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
        _configService.addCandidateDomain(host);
        relativePath = '${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}';
      } catch (_) {}
    }

    // 確保 token 正確帶入 query
    final effectiveToken = (token != null && token.isNotEmpty)
        ? token
        : (_authManager?.state.token ?? await _storageService.getToken());

    if (!relativePath.contains('token=') && effectiveToken != null && effectiveToken.isNotEmpty) {
      final sep = relativePath.contains('?') ? '&' : '?';
      relativePath = '$relativePath${sep}token=$effectiveToken';
    }

    // 去除第三方 UA 特徵後，強制確保帶入 flag=meta 參數，保證 V2Board/Xboard 下發 Mihomo/Clash YAML 格式配置
    if (relativePath.contains('flag=clash')) {
      relativePath = relativePath.replaceAll('flag=clash', 'flag=meta');
    } else if (!relativePath.contains('flag=')) {
      final sep = relativePath.contains('?') ? '&' : '?';
      relativePath = '$relativePath${sep}flag=meta';
    }

    // 寫入 L2 加密金庫保存
    try {
      await _storageService.saveCachedSubscribePath(relativePath);
    } catch (_) {}

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

  /// Happy Eyeballs 雙層容災訂閱下載核心：
  /// 第一層：當前主機 (currentApiDomain) 2.5 秒極速直連通道
  /// 第二層：故障瞬間觸發「全備援並發搶答競速下載 (Happy Eyeballs Parallel Race)」
  Future<String> _fetchSubscriptionContentWithHappyEyeballs(String relativePath) async {
    final currentHost = _configService.currentApiDomain;

    // --- 第一層：極速直連通道 (2.5 秒短超時) ---
    try {
      debugPrint('[SubscriptionEngine] ⚡ [Layer 1] 嘗試極速直連當前主機: $currentHost$relativePath (超時 2500ms)');
      final yaml = await _downloadFromSingleHost(
        currentHost,
        relativePath,
        timeout: const Duration(milliseconds: 2500),
      );
      if (yaml.isNotEmpty) {
        debugPrint('[SubscriptionEngine] ✅ [Layer 1] 直連成功！取得訂閱內容');
        return yaml;
      }
    } catch (e) {
      debugPrint('[SubscriptionEngine] ⚠️ [Layer 1] 當前主機 ($currentHost) 直連失敗或超時: $e');
    }

    // --- 第二層：故障瞬間觸發全主機並發競速下載 (Parallel Race Failover) ---
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

    // 將剛才失敗的主機移到最後，優先讓其他活著的備用主機搶答
    allCandidates.remove(currentHost);
    final raceHosts = List<String>.from(allCandidates)..add(currentHost);

    debugPrint('[SubscriptionEngine] 🚀 [Layer 2] 觸發全備援並發競速下載！候選清單: $raceHosts');

    if (raceHosts.isEmpty) {
      throw Exception('無可用之 API 主機進行並發競速');
    }

    final winner = await _raceDownloadSubscription(raceHosts, relativePath);

    // 👑 將最快活著回傳 HTTP 200 有效節點的主機正式扶正為全域 currentApiDomain
    _configService.setCurrentApiDomain(winner.winnerHost);
    debugPrint('[SubscriptionEngine] 👑 併發搶答勝出者: ${winner.winnerHost}！已自動扶正為全域 currentApiDomain');

    return winner.yaml;
  }

  /// 單一主機訂閱下載與驗證 (僅在 HTTP 200 且返回有效 YAML 節點時視為成功)
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
      finalPath = finalPath.replaceAll('flag=clash', 'flag=meta');
    } else if (!finalPath.contains('flag=')) {
      final sep = finalPath.contains('?') ? '&' : '?';
      finalPath = '$finalPath${sep}flag=meta';
    }
    final targetUrl = '$cleanHost$finalPath';

    final response = await _dioClient.dio.get<String>(
      targetUrl,
      options: Options(
        headers: {
          'User-Agent': 'TianheNetwork/${AppConstants.appVersion} (macOS)',
        },
        responseType: ResponseType.plain,
        connectTimeout: timeout,
        receiveTimeout: timeout,
        sendTimeout: timeout,
      ),
    );

    if (response.statusCode != 200) {
      throw HttpException('HTTP 狀態碼非 200: ${response.statusCode}', uri: Uri.parse(targetUrl));
    }

    final yaml = response.data?.toString() ?? '';
    if (yaml.trim().isEmpty) {
      throw const FormatException('主機回應訂閱內容為空');
    }

    final proxies = ConfigGenerator.parseProxiesFromYaml(yaml);
    if (proxies.isEmpty) {
      throw const FormatException('未能在該主機返回之 YAML 解析出有效節點');
    }

    return yaml;
  }

  /// 並發搶答：向多台備援主機同時發起下載，最快返回有效 YAML 者勝出
  Future<({String yaml, String winnerHost})> _raceDownloadSubscription(
    List<String> hosts,
    String relativePath,
  ) {
    final completer = Completer<({String yaml, String winnerHost})>();
    int pending = hosts.length;
    final errors = <String>[];

    for (final host in hosts) {
      _downloadFromSingleHost(host, relativePath).then((yaml) {
        if (!completer.isCompleted) {
          completer.complete((yaml: yaml, winnerHost: host));
        }
      }).catchError((err) {
        errors.add('$host ($err)');
        pending--;
        if (pending == 0 && !completer.isCompleted) {
          completer.completeError(
            Exception('所有備援主機並發競速下載皆失敗: ${errors.join('; ')}'),
          );
        }
      });
    }

    return completer.future;
  }
}
