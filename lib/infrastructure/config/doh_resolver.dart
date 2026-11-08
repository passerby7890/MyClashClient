// lib/infrastructure/config/doh_resolver.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/error_sanitizer.dart';

/// DoH 解析異常類別 (零敏感端點暴露)
class DohResolveException implements Exception {
  final String message;
  final dynamic cause;
  DohResolveException(this.message, [this.cause]);

  @override
  String toString() => 'DohResolveException: $message';
}

/// DNS over HTTPS (DoH) 多級備援解析器
/// 支援多梯隊並行競速與自動降級切換
class DohResolver {
  final http.Client _client;
  final int timeoutMs;

  DohResolver({
    http.Client? client,
    this.timeoutMs = AppConstants.dohTimeoutMs,
  }) : _client = client ?? _createDirectClient();

  static http.Client _createDirectClient() {
    if (kIsWeb) return http.Client();
    final ioClient = HttpClient();
    ioClient.findProxy = (uri) => 'DIRECT';
    ioClient.badCertificateCallback = (cert, host, port) => true;
    return IOClient(ioClient);
  }

  /// 並行競速執行多個 DoH 查詢任務，以最快成功返回者為準
  Future<String> _raceQueries(List<Future<String> Function()> queryTasks) async {
    final completer = Completer<String>();
    int pending = queryTasks.length;
    final errors = <dynamic>[];

    for (final task in queryTasks) {
      task().then((result) {
        if (!completer.isCompleted && result.isNotEmpty) {
          completer.complete(result);
        }
      }).catchError((err) {
        errors.add(err);
      }).whenComplete(() {
        pending--;
        if (pending == 0 && !completer.isCompleted) {
          completer.completeError(
            DohResolveException('並行 DoH 查詢皆未連通'),
          );
        }
      });
    }

    return completer.future;
  }

  /// 執行多級備援 DoH 查詢獲取 TXT 記錄
  /// 梯隊 1 (境內極速並行競速)：阿里雲 DoH + 騰訊 DNSPod + 純 IP 零 DNS 依賴競速
  /// 梯隊 2 (海外容災並行競速)：Cloudflare DoH + Google DoH
  /// 兜底：拋出異常由上層使用 Hardcoded Fallback
  Future<String> resolveTxtMultiLevel(String domain) async {
    // 1. 第一梯隊：境內公共 DoH 並行競速
    try {
      final txt = await _raceQueries([
        () => queryAliyunDoh(domain),
        () => queryTencentDoh(domain),
        () => queryAliyunIpDoh(domain),
        () => queryTencentIpDoh(domain),
      ]);
      if (txt.isNotEmpty) {
        return txt;
      }
    } catch (_) {
      SafeLog.d('[DoH] 第一梯隊查詢未命中，切換至第二梯隊備援');
    }

    // 2. 第二梯隊：海外公共 DoH 並行競速
    try {
      final txt = await _raceQueries([
        () => queryCloudflareDoh(domain),
        () => queryGoogleDoh(domain),
      ]);
      if (txt.isNotEmpty) {
        return txt;
      }
    } catch (_) {
      SafeLog.d('[DoH] 第二梯隊查詢未命中，啟用內建安全兜底');
    }

    throw DohResolveException('所有 DoH 查詢渠道皆失敗，請使用兜底配置。');
  }

  /// 透過騰訊 DNSPod DoH 查詢 TXT 記錄
  Future<String> queryTencentDoh(String domain) async {
    final uri = Uri.parse(AppConstants.tencentDohEndpoint).replace(
      queryParameters: {
        'name': domain,
        'type': 'TXT',
      },
    );

    final response = await _client
        .get(
          uri,
          headers: {'Accept': 'application/dns-json'},
        )
        .timeout(Duration(milliseconds: timeoutMs));

    if (response.statusCode != 200) {
      throw DohResolveException('DoH 回應狀態碼非 200: ${response.statusCode}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    return _parseAnswerData(data);
  }

  /// 透過阿里雲 DoH 查詢 TXT 記錄
  Future<String> queryAliyunDoh(String domain) async {
    final uri = Uri.parse(AppConstants.aliyunDohEndpoint).replace(
      queryParameters: {
        'name': domain,
        'type': 'TXT',
      },
    );

    final response = await _client
        .get(
          uri,
          headers: {'Accept': 'application/dns-json'},
        )
        .timeout(Duration(milliseconds: timeoutMs));

    if (response.statusCode != 200) {
      throw DohResolveException('DoH 回應狀態碼非 200: ${response.statusCode}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    return _parseAnswerData(data);
  }

  /// 透過阿里雲純 IP DoH 查詢 TXT 記錄 (零系統 DNS 依賴)
  Future<String> queryAliyunIpDoh(String domain) async {
    final uri = Uri.parse(AppConstants.aliyunIpDohEndpoint).replace(
      queryParameters: {
        'name': domain,
        'type': 'TXT',
      },
    );

    final response = await _client
        .get(
          uri,
          headers: {'Accept': 'application/dns-json'},
        )
        .timeout(Duration(milliseconds: timeoutMs));

    if (response.statusCode != 200) {
      throw DohResolveException('IP DoH 回應狀態碼非 200: ${response.statusCode}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    return _parseAnswerData(data);
  }

  /// 透過騰訊純 IP DoH 查詢 TXT 記錄 (零系統 DNS 依賴)
  Future<String> queryTencentIpDoh(String domain) async {
    final uri = Uri.parse(AppConstants.tencentIpDohEndpoint).replace(
      queryParameters: {
        'name': domain,
        'type': 'TXT',
      },
    );

    final response = await _client
        .get(
          uri,
          headers: {'Accept': 'application/dns-json'},
        )
        .timeout(Duration(milliseconds: timeoutMs));

    if (response.statusCode != 200) {
      throw DohResolveException('IP DoH 回應狀態碼非 200: ${response.statusCode}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    return _parseAnswerData(data);
  }

  /// 透過 Cloudflare DoH 查詢 TXT 記錄
  Future<String> queryCloudflareDoh(String domain) async {
    final uri = Uri.parse(AppConstants.cloudflareDohEndpoint).replace(
      queryParameters: {
        'name': domain,
        'type': 'TXT',
      },
    );

    final response = await _client
        .get(
          uri,
          headers: {'Accept': 'application/dns-json'},
        )
        .timeout(Duration(milliseconds: timeoutMs));

    if (response.statusCode != 200) {
      throw DohResolveException('DoH 回應狀態碼非 200: ${response.statusCode}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    return _parseAnswerData(data);
  }

  /// 透過 Google DoH 查詢 TXT 記錄
  Future<String> queryGoogleDoh(String domain) async {
    final uri = Uri.parse(AppConstants.googleDohEndpoint).replace(
      queryParameters: {
        'name': domain,
        'type': 'TXT',
      },
    );

    final response = await _client
        .get(uri)
        .timeout(Duration(milliseconds: timeoutMs));

    if (response.statusCode != 200) {
      throw DohResolveException('DoH 回應狀態碼非 200: ${response.statusCode}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    return _parseAnswerData(data);
  }

  /// 解析 DNS Answer 結構，拼接 TXT 字串
  String _parseAnswerData(Map<String, dynamic> jsonBody) {
    final answers = jsonBody['Answer'] as List<dynamic>?;
    if (answers == null || answers.isEmpty) {
      throw DohResolveException('DNS 回應中未包含 Answer 記錄');
    }

    final buffer = StringBuffer();
    for (final ans in answers) {
      if (ans is Map<String, dynamic> && ans['type'] == 16) {
        final rawData = ans['data'] as String? ?? '';
        buffer.write(rawData);
      }
    }

    final result = buffer.toString().trim();
    if (result.isEmpty) {
      throw DohResolveException('未找到有效的 TXT 記錄資料');
    }
    return result;
  }
}
