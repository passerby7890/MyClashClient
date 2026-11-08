import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../../core/crypto/aes_decryptor.dart';
import '../../core/utils/error_sanitizer.dart';
import 'doh_resolver.dart';
import 'remote_config_model.dart';

/// 全域動態配置服務
/// 負責 App 啟動時透過加密通道獲取動態配置、AES-256 本地快取管理與線路切換
class AppConfigService {
  final DohResolver _dohResolver;
  final AesDecryptor _aesDecryptor;
  SharedPreferences? _prefs;

  RemoteConfigModel? _activeConfig;
  int _activeDomainIndex = 0;
  List<String> _racedApiDomains = [];
  final Map<String, int> _apiLatencies = {};

  AppConfigService({
    DohResolver? dohResolver,
    AesDecryptor? aesDecryptor,
    SharedPreferences? prefs,
  })  : _dohResolver = dohResolver ?? DohResolver(),
        _aesDecryptor = aesDecryptor ?? AesDecryptor(),
        _prefs = prefs;

  /// 當前使用的遠端配置
  RemoteConfigModel get activeConfig {
    if (_activeConfig != null) return _activeConfig!;
    return RemoteConfigModel.fallback(
      fallbackDomains: AppConstants.fallbackApiDomains,
    );
  }

  /// 取得所有經客戶端競速排序後的 API 候選網域清單
  List<String> get availableApiDomains =>
      _racedApiDomains.isNotEmpty ? _racedApiDomains : activeConfig.allApiDomains;

  /// 當前活躍的 API 網域 (取自競速最佳或備災輪替端點)
  String get currentApiDomain {
    final domains = availableApiDomains;
    if (domains.isEmpty) {
      return AppConstants.fallbackApiDomains.first;
    }
    if (_activeDomainIndex >= domains.length) {
      _activeDomainIndex = 0;
    }
    return domains[_activeDomainIndex];
  }

  /// 各端點實測延遲記錄 (ms)
  Map<String, int> get apiLatencies => Map.unmodifiable(_apiLatencies);

  /// 取得動態配置中的緊急破盾前置代理節點 (可選)
  dynamic get bootstrapProxy => activeConfig.bootstrapProxy;

  /// 對所有候選 API 端點並行競速 (Racing Benchmark)，以客戶端實測延遲建立最優與備災救援排序
  Future<void> raceApiHosts() async {
    final candidates = activeConfig.allApiDomains;
    if (candidates.length <= 1) {
      _racedApiDomains = List.from(candidates);
      return;
    }

    final results = <String, int>{};
    final client = createDirectClient();

    try {
      final futures = candidates.map((domain) async {
        final stopwatch = Stopwatch()..start();
        try {
          var cleanDomain = domain.trim();
          while (cleanDomain.endsWith('/')) {
            cleanDomain = cleanDomain.substring(0, cleanDomain.length - 1);
          }
          final uri = Uri.parse('$cleanDomain/api/v1/guest/comm/config');
          final resp = await client.get(uri).timeout(const Duration(milliseconds: 2500));
          stopwatch.stop();
          if (resp.statusCode == 200 || resp.statusCode == 422 || resp.statusCode == 404) {
            results[domain] = stopwatch.elapsedMilliseconds;
          }
        } catch (_) {
          // 網路不可達或超時，不納入即時優先級
        }
      });

      await Future.wait(futures);
    } finally {
      client.close();
    }

    if (results.isNotEmpty) {
      final sorted = results.keys.toList()
        ..sort((a, b) => (results[a] ?? 9999).compareTo(results[b] ?? 9999));
      for (final c in candidates) {
        if (!sorted.contains(c)) {
          sorted.add(c);
        }
      }
      _racedApiDomains = sorted;
      _apiLatencies.addAll(results);
      _activeDomainIndex = 0;
      SafeLog.d('[AppConfigService] 線路競速完成，最優延遲: ${results[_racedApiDomains.first]}ms，可用備援數: ${_racedApiDomains.length}');
    } else {
      _racedApiDomains = List.from(candidates);
    }
  }

  /// 備災救援模式：當前 API 不穩或斷線時，自動切換至下一個備援 API 網域
  String switchNextApiDomain() {
    final domains = availableApiDomains;
    if (domains.length <= 1) return currentApiDomain;
    _activeDomainIndex = (_activeDomainIndex + 1) % domains.length;
    final next = currentApiDomain;
    SafeLog.d('[AppConfigService] 備災救援模式啟動，已切換至備援線路 #$_activeDomainIndex');
    return next;
  }

  /// 將指定的主機正式扶正為全域 currentApiDomain (放置於最優先第 0 順位)
  void setCurrentApiDomain(String domain) {
    var cleanDomain = domain.trim();
    while (cleanDomain.endsWith('/')) {
      cleanDomain = cleanDomain.substring(0, cleanDomain.length - 1);
    }
    if (cleanDomain.endsWith('/api/v1')) {
      cleanDomain = cleanDomain.substring(0, cleanDomain.length - 7);
    }
    if (cleanDomain.isEmpty) return;

    if (_racedApiDomains.isEmpty) {
      _racedApiDomains = List.from(activeConfig.allApiDomains);
    }
    _racedApiDomains.remove(cleanDomain);
    _racedApiDomains.insert(0, cleanDomain);
    _activeDomainIndex = 0;
    SafeLog.d('[AppConfigService] 已扶正最快通訊線路為首選 (候選總數: ${_racedApiDomains.length})');
  }

  /// 動態添加備用主機至候選池末尾 (去絕對網址化備援機制)
  void addCandidateDomain(String domain) {
    var cleanDomain = domain.trim();
    while (cleanDomain.endsWith('/')) {
      cleanDomain = cleanDomain.substring(0, cleanDomain.length - 1);
    }
    if (cleanDomain.endsWith('/api/v1')) {
      cleanDomain = cleanDomain.substring(0, cleanDomain.length - 7);
    }
    if (cleanDomain.isEmpty) return;

    if (_racedApiDomains.isEmpty) {
      _racedApiDomains = List.from(activeConfig.allApiDomains);
    }
    if (!_racedApiDomains.contains(cleanDomain)) {
      _racedApiDomains.add(cleanDomain);
      SafeLog.d('[AppConfigService] 已新增額外備援線路至候選池 (候選總數: ${_racedApiDomains.length})');
    }
  }

  /// 初始化服務 (在 Splash 頁面或 main() 調用)
  Future<RemoteConfigModel> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
    _loadFromCache();

    // 1. 同時並行發起雲端配置與加密 TXT 查詢，哪個快就先代入哪個
    try {
      final fastestConfig = await _raceFirstSuccessful<RemoteConfigModel>([
        () => fetchOssConfig(),
        () => fetchRemoteConfig(),
      ]);
      _activeConfig = fastestConfig;
      await _saveToCache(fastestConfig);
      try {
        await raceApiHosts();
      } catch (_) {}
      return fastestConfig;
    } catch (_) {
      SafeLog.d('[AppConfigService] 線上配置並行獲取未命中，降級讀取加密快取或兜底配置');
    }

    // 2. 次選：若本地已有加密快取則使用快取
    if (_activeConfig != null) {
      try {
        await raceApiHosts();
      } catch (_) {}
      return _activeConfig!;
    }

    // 3. 兜底：使用內建混淆備援陣列
    final directConfig = RemoteConfigModel.fallback(
      fallbackDomains: AppConstants.fallbackApiDomains,
    );
    _activeConfig = directConfig;
    await _saveToCache(directConfig);
    try {
      await raceApiHosts();
    } catch (_) {}
    return directConfig;
  }

  /// 輔助函式：多任務並行競速，回傳第一個成功完成的結果
  Future<T> _raceFirstSuccessful<T>(List<Future<T> Function()> taskFactories) {
    final completer = Completer<T>();
    int pending = taskFactories.length;
    final errors = <dynamic>[];

    for (final factory in taskFactories) {
      factory().then((result) {
        if (!completer.isCompleted) {
          completer.complete(result);
        }
      }).catchError((error) {
        errors.add(error);
        pending--;
        if (pending == 0 && !completer.isCompleted) {
          completer.completeError(
            Exception('動態線路配置獲取失敗'),
          );
        }
      });
    }

    return completer.future;
  }

  /// 建立強制 DIRECT 直連且放行自簽憑證的安全 HTTP Client
  static http.Client createDirectClient() {
    if (kIsWeb) return http.Client();
    final ioClient = HttpClient();
    ioClient.findProxy = (uri) => 'DIRECT';
    ioClient.badCertificateCallback = (cert, host, port) => true;
    return IOClient(ioClient);
  }

  static http.Client _createDirectClient() => createDirectClient();

  /// 從雲端儲存端點獲取並解碼動態配置
  Future<RemoteConfigModel> fetchOssConfig() async {
    final client = _createDirectClient();
    try {
      final response = await client
          .get(Uri.parse(AppConstants.aliyunOssConfigUrl))
          .timeout(const Duration(milliseconds: 3000));
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final rawBase64 = response.body
            .replaceAll('"', '')
            .replaceAll("'", '')
            .replaceAll(' ', '')
            .replaceAll('\n', '')
            .replaceAll('\r', '')
            .trim();
        Map<String, dynamic>? map;
        try {
          final decodedJsonStr = utf8.decode(base64.decode(rawBase64));
          if (decodedJsonStr.trim().startsWith('{')) {
            map = json.decode(decodedJsonStr) as Map<String, dynamic>;
          }
        } catch (_) {}

        if (map == null) {
          try {
            final decryptedStr = _aesDecryptor.decrypt(rawBase64);
            map = json.decode(decryptedStr) as Map<String, dynamic>;
          } catch (_) {}
        }

        if (map != null) {
          return RemoteConfigModel.fromJson(map);
        }
        throw const FormatException('動態配置內容解析失敗');
      }
      throw Exception('配置回應狀態碼非 200: ${response.statusCode}');
    } finally {
      client.close();
    }
  }

  /// 透過 DoH 獲取並解密/解碼遠端 TXT 配置
  Future<RemoteConfigModel> fetchRemoteConfig() async {
    String? rawTxt;

    try {
      rawTxt = await _dohResolver.resolveTxtMultiLevel(
        AppConstants.primaryConfigDomain,
      );
    } catch (_) {
      rawTxt = await _dohResolver.resolveTxtMultiLevel(
        AppConstants.secondaryConfigDomain,
      );
    }

    if (rawTxt.isEmpty) {
      throw const FormatException('DoH 查詢返回之 TXT 內容為空');
    }

    final sanitizedTxt = rawTxt
        .replaceAll('"', '')
        .replaceAll("'", '')
        .replaceAll(' ', '')
        .replaceAll('\n', '')
        .replaceAll('\r', '')
        .trim();

    Map<String, dynamic>? configMap;

    try {
      final decodedJsonStr = utf8.decode(base64.decode(sanitizedTxt));
      if (decodedJsonStr.trim().startsWith('{')) {
        configMap = json.decode(decodedJsonStr) as Map<String, dynamic>;
      }
    } catch (_) {}

    if (configMap == null) {
      try {
        final decryptedJsonStr = _aesDecryptor.decrypt(sanitizedTxt);
        configMap = json.decode(decryptedJsonStr) as Map<String, dynamic>;
      } catch (_) {
        throw const FormatException('無法解析遠端配置記錄');
      }
    }

    return RemoteConfigModel.fromJson(configMap);
  }

  /// 從 SharedPreferences 載入快取 (支援 AES-256 密文與舊版明文自動升級加密)
  void _loadFromCache() {
    final cachedStr = _prefs?.getString(AppConstants.storageCachedConfig);
    if (cachedStr != null && cachedStr.isNotEmpty) {
      try {
        final trimmed = cachedStr.trim();
        if (trimmed.startsWith('{')) {
          // 舊版明文快取：讀取後立即升級覆寫為 AES-256 密文，徹底消除本地 JSON/Plist 明文殘留
          final model = RemoteConfigModel.fromRawJson(trimmed);
          _activeConfig = model;
          unawaited(_saveToCache(model));
        } else {
          final decryptedJson = _aesDecryptor.decrypt(trimmed);
          _activeConfig = RemoteConfigModel.fromRawJson(decryptedJson);
        }
      } catch (_) {
        SafeLog.d('[AppConfigService] 本地加密快取校驗未通過，已忽略');
      }
    }
  }

  /// 寫入快取 (強制使用 AES-256-CBC 加密落盤，杜絕 shared_preferences.json / plist 明文暴露 API IP)
  Future<void> _saveToCache(RemoteConfigModel config) async {
    try {
      final cipherText = _aesDecryptor.encrypt(config.toRawJson());
      await _prefs?.setString(
        AppConstants.storageCachedConfig,
        cipherText,
      );
    } catch (_) {
      SafeLog.d('[AppConfigService] 本地加密快取寫入失敗');
    }
  }
}
