import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../../core/crypto/aes_decryptor.dart';
import 'doh_resolver.dart';
import 'remote_config_model.dart';

/// 全域動態配置服務
/// 負責 App 啟動時透過 DoH 獲取 AES 解密配置、本地快取管理與線路切換
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

  /// 對所有候選 API 端點並行競速 (Racing Benchmark)，以客戶端實測延遲建立最優與備災救援排序
  Future<void> raceApiHosts() async {
    final candidates = activeConfig.allApiDomains;
    if (candidates.length <= 1) {
      _racedApiDomains = List.from(candidates);
      return;
    }

    final results = <String, int>{};
    final client = http.Client();

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
      // 將未能連通的候選端點放在最後作為後備兜底
      for (final c in candidates) {
        if (!sorted.contains(c)) {
          sorted.add(c);
        }
      }
      _racedApiDomains = sorted;
      _apiLatencies.addAll(results);
      _activeDomainIndex = 0;
      // ignore: avoid_print
      print('[AppConfigService] API 競速完成！最佳路徑: ${_racedApiDomains.first} (${results[_racedApiDomains.first]}ms)，備災救援排序: $_racedApiDomains');
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
    // ignore: avoid_print
    print('[AppConfigService] ⚠️ 備災救援模式啟動！自動平滑切換至備援 API: $next');
    return next;
  }

  /// 初始化服務 (在 Splash 頁面或 main() 調用)
  /// 依據「哪個快速就先代入哪個」原則，同時並行請求：
  /// 1. 阿里雲 OSS 地址 (ConFigOss.json)
  /// 2. 網域 TXT 記錄 (novaclash.spsr86.cv)
  /// 取得配置後，立即對所有 hosts 發起 API 客戶端競速，確立最佳服務路徑與救援備援鏈！
  Future<RemoteConfigModel> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
    _loadFromCache();

    // 1. 同時並行發起 OSS 與 TXT 網域請求，哪個快就先代入哪個！
    try {
      final fastestConfig = await _raceFirstSuccessful<RemoteConfigModel>([
        () => fetchOssConfig(),
        () => fetchRemoteConfig(),
      ]);
      _activeConfig = fastestConfig;
      await _saveToCache(fastestConfig);
      // 取得配置後，立即並行競速選出最佳 API 端點
      try {
        await raceApiHosts();
      } catch (_) {}
      return fastestConfig;
    } catch (e) {
      // ignore: avoid_print
      print('[AppConfigService] 線上配置並行獲取皆失敗: $e');
    }

    // 2. 次選：若本地已有快取則使用快取
    if (_activeConfig != null) {
      try {
        await raceApiHosts();
      } catch (_) {}
      return _activeConfig!;
    }

    // 3. 兜底：使用多節點 IP+網域備援陣列
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
            Exception('所有並行配置獲取任務皆失敗: ${errors.join(', ')}'),
          );
        }
      });
    }

    return completer.future;
  }

  static http.Client _createDirectClient() {
    if (kIsWeb) return http.Client();
    final ioClient = HttpClient();
    ioClient.findProxy = (uri) => 'DIRECT';
    ioClient.badCertificateCallback = (cert, host, port) => true;
    return IOClient(ioClient);
  }

  /// 從阿里雲 OSS 獲取並解碼 Base64 動態配置 (對齊 Tianhe 3.0 ConFigOss 機制)
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
        // 1. 優先嘗試 Base64 直接解碼 JSON
        try {
          final decodedJsonStr = utf8.decode(base64.decode(rawBase64));
          if (decodedJsonStr.trim().startsWith('{')) {
            map = json.decode(decodedJsonStr) as Map<String, dynamic>;
          }
        } catch (_) {}

        // 2. 若非直接 Base64，嘗試使用 AES-256-CBC 解密
        if (map == null) {
          try {
            final decryptedStr = _aesDecryptor.decrypt(rawBase64);
            map = json.decode(decryptedStr) as Map<String, dynamic>;
          } catch (_) {}
        }

        if (map != null) {
          return RemoteConfigModel.fromJson(map);
        }
        throw const FormatException('OSS 內容解析失敗 (Base64 與 AES 解密皆無法還原 JSON)');
      }
      throw Exception('OSS 回應狀態碼非 200: ${response.statusCode}');
    } finally {
      client.close();
    }
  }

  /// 透過 DoH 獲取並解密/解碼遠端 TXT 配置 (支援 Base64 直出 JSON 與 AES-256 解密)
  Future<RemoteConfigModel> fetchRemoteConfig() async {
    String? rawTxt;

    // 先查主網域 (novaclash.spsr86.cv)
    try {
      rawTxt = await _dohResolver.resolveTxtMultiLevel(
        AppConstants.primaryConfigDomain,
      );
    } catch (_) {
      // 主網域失敗，嘗試次要網域
      rawTxt = await _dohResolver.resolveTxtMultiLevel(
        AppConstants.secondaryConfigDomain,
      );
    }

    if (rawTxt.isEmpty) {
      throw const FormatException('DoH 查詢返回之 TXT 內容為空');
    }

    // 清理 DNS TXT 常見引號、空格與換行符號
    final sanitizedTxt = rawTxt
        .replaceAll('"', '')
        .replaceAll("'", '')
        .replaceAll(' ', '')
        .replaceAll('\n', '')
        .replaceAll('\r', '')
        .trim();

    Map<String, dynamic>? configMap;

    // 1. 優先嘗試 Base64 解碼 (novaclash.spsr86.cv 直出 JSON 格式)
    try {
      final decodedJsonStr = utf8.decode(base64.decode(sanitizedTxt));
      if (decodedJsonStr.trim().startsWith('{')) {
        configMap = json.decode(decodedJsonStr) as Map<String, dynamic>;
      }
    } catch (_) {
      // 非直接 Base64 JSON，繼續嘗試 AES 解密
    }

    // 2. 若非 Base64 JSON，則嘗試 AES-256-CBC 解密
    if (configMap == null) {
      try {
        final decryptedJsonStr = _aesDecryptor.decrypt(sanitizedTxt);
        configMap = json.decode(decryptedJsonStr) as Map<String, dynamic>;
      } catch (e) {
        throw FormatException('無法解析 TXT 記錄 (Base64 解碼與 AES-256 解密皆失敗): $e');
      }
    }

    return RemoteConfigModel.fromJson(configMap);
  }

  /// 從 SharedPreferences 載入快取
  void _loadFromCache() {
    final cachedStr = _prefs?.getString(AppConstants.storageCachedConfig);
    if (cachedStr != null && cachedStr.isNotEmpty) {
      try {
        _activeConfig = RemoteConfigModel.fromRawJson(cachedStr);
      } catch (e) {
        // ignore: avoid_print
        print('[AppConfigService] 快取配置解析異常: $e');
      }
    }
  }

  /// 寫入快取
  Future<void> _saveToCache(RemoteConfigModel config) async {
    try {
      await _prefs?.setString(
        AppConstants.storageCachedConfig,
        config.toRawJson(),
      );
    } catch (e) {
      // ignore: avoid_print
      print('[AppConfigService] 快取保存失敗: $e');
    }
  }
}
