// lib/core/utils/error_sanitizer.dart

import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../i18n/i18n_service.dart';

/// 安全日誌閘門：Release 模式 100% 靜默，Debug 模式亦自動脫敏 URL / IP / Token
class SafeLog {
  SafeLog._();

  static void d(String message) {
    if (kReleaseMode || !kDebugMode) return;
    debugPrint(ErrorSanitizer.scrubSensitiveText(message));
  }
}

/// 全域錯誤訊息脫敏與友善化防線 (Zero-Leakage Error Firewall)
///
/// 確保任何異常在傳遞至 UI 層 (SnackBar / Dialog / Error Banner) 前：
/// 1. 保留合法乾淨的後端業務提示（如「郵箱或密碼錯誤」、「驗證碼錯誤」）。
/// 2. 100% 攔截並轉換 DioException / HttpException / SocketException / DoH / OSS 錯誤。
/// 3. 正則強制抹除所有 URL、IP:Port、網域名稱、本機路徑、Token、密鑰與底層框架特徵。
class ErrorSanitizer {
  ErrorSanitizer._();

  static final RegExp _urlRegex = RegExp(
    r'(?:https?|wss?|socks5?|vmess|vless|trojan|ss|ssr|hysteria2?|tuic|anytls)://[^\s,;)"\x27<>]+',
    caseSensitive: false,
  );

  static final RegExp _ipv4Regex = RegExp(
    r'\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)(?::\d{1,5})?\b',
  );

  static final RegExp _ipv6Regex = RegExp(
    r'\[?[0-9a-fA-F]{1,4}(?::[0-9a-fA-F]{1,4}){3,7}\]?(?::\d{1,5})?',
  );

  static final RegExp _sensitiveDomainRegex = RegExp(
    r'(?<![@\w])(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+(?:com|net|org|io|cv|cc|me|xyz|top|vip|club|pub|google|chat|cn|tw|hk|jp|cloud|app|dev)(?::\d{1,5})?(?:\/[^\s,;)"\x27]*)?',
    caseSensitive: false,
  );

  static final RegExp _querySecretRegex = RegExp(
    r'(?:token|auth_data|authorization|password|secret|key|uuid|website_id)\s*[=:]\s*[^\s&;,)"]+',
    caseSensitive: false,
  );

  static final RegExp _jwtRegex = RegExp(
    r'\beyJ[a-zA-Z0-9_-]{8,}\.[a-zA-Z0-9_-]{8,}\.[a-zA-Z0-9_-]{4,}\b',
  );

  static final RegExp _hostPortMetaRegex = RegExp(
    r'(?:address\s*=\s*[^\s,)]+|port\s*=\s*\d+|uri\s*=\s*[^\s,)]+)',
    caseSensitive: false,
  );

  static final RegExp _localPathRegex = RegExp(
    r'(?:[a-zA-Z]:\\[^\s,;)"\x27]+|\/(?:Users|Applications|Library|private|var|tmp)\/[^\s,;)"\x27]+)',
    caseSensitive: false,
  );

  static final RegExp _internalBrandRegex = RegExp(
    r'\b(?:'
    '${String.fromCharCodes([109, 105, 104, 111, 109, 111])}|'
    '${String.fromCharCodes([118, 50, 98, 111, 97, 114, 100])}|'
    '${String.fromCharCodes([102, 108, 99, 108, 97, 115, 104])}|'
    '${String.fromCharCodes([119, 105, 110, 116, 117, 110])}(?:\\.dll)?|'
    '${String.fromCharCodes([99, 108, 97, 115, 104, 46, 109, 101, 116, 97])}'
    r')\b',
    caseSensitive: false,
  );

  /// 判斷是否為 V2Board 會話過期 / 未登入之 401/403 回應
  static bool isSessionExpiredResponse(int? statusCode, dynamic responseData) {
    if (statusCode == 401) return true;
    if (statusCode == 403) {
      final msg = _extractRawBackendMessage(responseData)?.toLowerCase() ?? '';
      if (msg.contains('未登录') ||
          msg.contains('未登錄') ||
          msg.contains('登陆已过期') ||
          msg.contains('登录已过期') ||
          msg.contains('登錄已過期') ||
          msg.contains('登入已過期') ||
          msg.contains('unauthenticated') ||
          msg.contains('unauthorized') ||
          msg.contains('token is null') ||
          msg.contains('login expired')) {
        return true;
      }
    }
    return false;
  }

  /// 判斷是否為訂閱金鑰失效 (V2Board /api/v1/client/subscribe 返回 403 token is error)
  static bool isSubscriptionTokenInvalid(int? statusCode, dynamic responseData) {
    if (statusCode != 403 && statusCode != 401) return false;
    final msg = _extractRawBackendMessage(responseData)?.toLowerCase() ?? '';
    return msg.contains('token is error') ||
        msg.contains('token error') ||
        msg.contains('token invalid');
  }

  /// 將任意錯誤物件轉化為安全、乾淨、符合當前語系的使用者友善字串
  static String sanitize(Object? error, {String? fallback}) {
    final i18n = I18nService.instance;
    final defaultMsg = fallback ?? i18n.t('err_operation_failed');

    if (error == null) return defaultMsg;

    if (error is DioException) {
      return _sanitizeDioException(error, fallback: fallback);
    }

    if (error is TimeoutException) {
      return i18n.t('err_request_timeout');
    }

    if (error is HandshakeException || error is TlsException) {
      return i18n.t('err_tls_handshake');
    }

    if (error is SocketException || error is HttpException) {
      return i18n.t('err_network_unavailable');
    }

    if (error is PlatformException) {
      final msg = error.message;
      if (msg != null && msg.trim().isNotEmpty && !_looksTechnicalOrLeaky(msg)) {
        final cleaned = scrubSensitiveText(msg).trim();
        if (cleaned.isNotEmpty && cleaned.length <= 100) {
          return cleaned;
        }
      }
      return defaultMsg;
    }

    String raw = error.toString().trim();
    raw = raw
        .replaceFirst(RegExp(r'^(?:Exception|FormatException|StateError|ArgumentError|Bad state):\s*'), '')
        .trim();

    if (raw.isEmpty) return defaultMsg;

    // 攔截被轉成字串後的技術異常特徵
    final lower = raw.toLowerCase();
    if (lower.contains('未登录') ||
        lower.contains('未登錄') ||
        lower.contains('登陆已过期') ||
        lower.contains('登录已过期') ||
        lower.contains('登入已過期') ||
        lower.contains('unauthenticated')) {
      return i18n.t('err_session_expired');
    }
    if (lower.contains('token is error')) {
      return i18n.t('err_sub_token_invalid');
    }
    if (lower.contains('status code of 401') || lower.contains('http 401')) {
      return i18n.t('err_session_expired');
    }
    if (lower.contains('status code of 403') || lower.contains('http 403') || lower.contains('403')) {
      if (_looksTechnicalOrLeaky(raw)) {
        return i18n.t('err_access_denied');
      }
    }
    if (lower.contains('timeout') || lower.contains('timed out') || raw.contains('逾時') || raw.contains('超时')) {
      if (_looksTechnicalOrLeaky(raw)) {
        return i18n.t('err_request_timeout');
      }
    }
    if (lower.contains('handshake') || lower.contains('certificate') || lower.contains('ssl') || lower.contains('tls')) {
      if (_looksTechnicalOrLeaky(raw)) {
        return i18n.t('err_tls_handshake');
      }
    }
    if (_looksTechnicalOrLeaky(raw)) {
      return fallback ?? i18n.t('err_network_unavailable');
    }

    final scrubbed = scrubSensitiveText(raw).trim();
    if (scrubbed.isEmpty ||
        scrubbed == '[REDACTED]' ||
        scrubbed.contains('[REDACTED]') ||
        scrubbed.length > 120) {
      return defaultMsg;
    }
    return scrubbed;
  }

  static String _sanitizeDioException(DioException e, {String? fallback}) {
    final i18n = I18nService.instance;
    final statusCode = e.response?.statusCode;
    final respData = e.response?.data;

    if (isSessionExpiredResponse(statusCode, respData)) {
      return i18n.t('err_session_expired');
    }
    if (isSubscriptionTokenInvalid(statusCode, respData)) {
      return i18n.t('err_sub_token_invalid');
    }

    // 嘗試提取乾淨的 V2Board 業務驗證錯誤訊息 (如：郵箱或密碼錯誤、驗證碼錯誤、優惠碼無效)
    final backendMsg = _extractRawBackendMessage(respData);
    if (backendMsg != null && backendMsg.isNotEmpty && !_looksTechnicalOrLeaky(backendMsg)) {
      final cleaned = scrubSensitiveText(backendMsg).trim();
      if (cleaned.isNotEmpty &&
          !cleaned.contains('[REDACTED]') &&
          cleaned.length <= 100) {
        return cleaned;
      }
    }

    if (statusCode != null) {
      if (statusCode == 401) return i18n.t('err_session_expired');
      if (statusCode == 403) return i18n.t('err_access_denied');
      if (statusCode == 404 || statusCode == 429 || statusCode >= 500) {
        return i18n.t('err_server_busy');
      }
    }

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return i18n.t('err_request_timeout');
      case DioExceptionType.badCertificate:
        return i18n.t('err_tls_handshake');
      case DioExceptionType.connectionError:
        if (e.error is HandshakeException || e.error is TlsException) {
          return i18n.t('err_tls_handshake');
        }
        return i18n.t('err_network_unavailable');
      case DioExceptionType.cancel:
        return fallback ?? i18n.t('err_operation_failed');
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
      default:
        if (e.error is HandshakeException || e.error is TlsException) {
          return i18n.t('err_tls_handshake');
        }
        if (e.error is SocketException) {
          return i18n.t('err_network_unavailable');
        }
        return fallback ?? i18n.t('err_network_unavailable');
    }
  }

  static String? _extractRawBackendMessage(dynamic respData) {
    if (respData is Map) {
      final errors = respData['errors'];
      if (errors is Map && errors.isNotEmpty) {
        final firstVal = errors.values.first;
        if (firstVal is List && firstVal.isNotEmpty) {
          return firstVal.first?.toString().trim();
        }
        if (firstVal != null) {
          return firstVal.toString().trim();
        }
      }
      final msg = respData['message'];
      if (msg is String && msg.trim().isNotEmpty) {
        return msg.trim();
      }
    } else if (respData is String) {
      final trimmed = respData.trim();
      if (trimmed.isNotEmpty &&
          trimmed.length <= 80 &&
          !trimmed.startsWith('<') &&
          !trimmed.startsWith('{')) {
        return trimmed;
      }
    }
    return null;
  }

  static bool _looksTechnicalOrLeaky(String text) {
    final lower = text.toLowerCase();
    if (_urlRegex.hasMatch(text) ||
        _ipv4Regex.hasMatch(text) ||
        _sensitiveDomainRegex.hasMatch(text) ||
        _jwtRegex.hasMatch(text) ||
        _querySecretRegex.hasMatch(text) ||
        _localPathRegex.hasMatch(text) ||
        _internalBrandRegex.hasMatch(text)) {
      return true;
    }
    const technicalSignatures = [
      'dioexception',
      'dioerror',
      'socketexception',
      'httpexception',
      'handshakeexception',
      'tlsexception',
      'clientexception',
      'processexception',
      'filesystemexception',
      'dohresolveexception',
      'requestoptions',
      'validatestatus',
      'developer.mozilla.org',
      'xmlhttprequest',
      'net::err_',
      'os error:',
      'errno =',
      'connection refused',
      'connection reset',
      'software caused connection abort',
      'failed host lookup',
      '<!doctype',
      '<html',
      'sqlstate',
      'stack trace',
      'errorexception',
      '備援主機並發競速',
      '所有配置端點皆無法連通',
      '並行 doh 查詢皆失敗',
      'webview error',
    ];
    for (final sig in technicalSignatures) {
      if (lower.contains(sig)) return true;
    }
    return false;
  }

  /// 強制抹除文字中的所有敏感網址、IP、Port、網域、本機路徑與憑證參數
  static String scrubSensitiveText(String input) {
    if (input.isEmpty) return input;
    var out = input;
    out = out.replaceAll(_urlRegex, '[REDACTED]');
    out = out.replaceAll(_localPathRegex, '[REDACTED]');
    out = out.replaceAll(_sensitiveDomainRegex, '[REDACTED]');
    out = out.replaceAll(_ipv4Regex, '[REDACTED]');
    out = out.replaceAll(_ipv6Regex, '[REDACTED]');
    out = out.replaceAll(_jwtRegex, '[REDACTED]');
    out = out.replaceAll(_querySecretRegex, '[REDACTED]');
    out = out.replaceAll(_hostPortMetaRegex, '[REDACTED]');
    out = out.replaceAll(_internalBrandRegex, '[REDACTED]');
    return out;
  }
}

