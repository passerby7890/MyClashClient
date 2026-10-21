// lib/infrastructure/config/doh_resolver.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../../core/constants/app_constants.dart';

/// DoH 解析異常類別
class DohResolveException implements Exception {
  final String message;
  final dynamic cause;
  DohResolveException(this.message, [this.cause]);

  @override
  String toString() => 'DohResolveException: $message${cause != null ? ' ($cause)' : ''}';
}

/// DNS over HTTPS (DoH) 多級備援解析器
/// 支援 Cloudflare DoH 與 Google DoH 自動降級切換
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

  /// 執行多級備援 DoH 查詢獲取 TXT 記錄
  /// 順序：Cloudflare -> 阿里雲 -> Google -> 拋出異常 (由上層接管並使用 Hardcoded Fallback)
  Future<String> resolveTxtMultiLevel(String domain) async {
    // 1. 首選：Cloudflare DoH
    try {
      final txt = await queryCloudflareDoh(domain);
      if (txt.isNotEmpty) {
        return txt;
      }
    } catch (e) {
      // ignore: avoid_print
      print('[DoH] Cloudflare 查詢失敗，切換至阿里雲 DoH: $e');
    }

    // 2. 次選：阿里雲 DoH (國內公共 DNS，未開代理亦可查詢)
    try {
      final txt = await queryAliyunDoh(domain);
      if (txt.isNotEmpty) {
        return txt;
      }
    } catch (e) {
      // ignore: avoid_print
      print('[DoH] 阿里雲 DoH 查詢失敗，切換至 Google DoH: $e');
    }

    // 3. 兜底：Google DoH
    try {
      final txt = await queryGoogleDoh(domain);
      if (txt.isNotEmpty) {
        return txt;
      }
    } catch (e) {
      // ignore: avoid_print
      print('[DoH] Google 查詢失敗: $e');
    }

    throw DohResolveException('所有 DoH 查詢渠道皆失敗，請使用兜底配置。');
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
      throw DohResolveException('阿里雲 DoH 回應狀態碼非 200: ${response.statusCode}');
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
      throw DohResolveException('Cloudflare DoH 回應狀態碼非 200: ${response.statusCode}');
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
      throw DohResolveException('Google DoH 回應狀態碼非 200: ${response.statusCode}');
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
        // type 16 代表 TXT Record
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
