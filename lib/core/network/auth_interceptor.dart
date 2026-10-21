// lib/core/network/auth_interceptor.dart

import 'package:dio/dio.dart';
import '../storage/secure_storage_service.dart';

/// 認證與 401 自動登出攔截器
/// 1. 自動為業務請求注入 Token 憑證
/// 2. 攔截 401 Unauthorized，清除本地憑證並觸發強制登出事件
class AuthInterceptor extends Interceptor {
  final SecureStorageService _storageService;
  final void Function()? _onUnauthorized;

  AuthInterceptor({
    required SecureStorageService storageService,
    void Function()? onUnauthorized,
  })  : _storageService = storageService,
        _onUnauthorized = onUnauthorized;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // 排除登入與註冊公開接口
    final isPublicEndpoint = options.path.contains('/passport/auth/login') ||
        options.path.contains('/passport/auth/register') ||
        options.path.contains('/passport/auth/forget');

    if (!isPublicEndpoint) {
      final token = await _storageService.getToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = token;
        // V2Board 亦支援 auth-data 標頭
        options.headers['auth-data'] = token;
      }
    }

    return handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // 攔截 401 Unauthorized (Token 失效或已被後端註銷)
    if (err.response?.statusCode == 401) {
      // ignore: avoid_print
      print('[AuthInterceptor] 收到 401 Unauthorized！清理憑證並觸發踢出廣播...');

      // 1. 清理本地安全儲存中所有 Token 與敏感資料
      await _storageService.clearAll();

      // 2. 廣播通知 UI 層 / 狀態管理器跳轉登入頁
      _onUnauthorized?.call();
    }

    return handler.next(err);
  }
}
