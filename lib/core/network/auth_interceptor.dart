// lib/core/network/auth_interceptor.dart

import 'package:dio/dio.dart';
import '../storage/secure_storage_service.dart';
import '../utils/error_sanitizer.dart';

/// 認證與 401/403 會話失效自動登出攔截器
/// 1. 自動為受保護的 `/api/v1/user/*` 業務請求注入 JWT 憑證（排除公開與訂閱端點）
/// 2. 攔截 401 Unauthorized 與 V2Board 403 會話過期，清除本地憑證並觸發強制登出事件
class AuthInterceptor extends Interceptor {
  final SecureStorageService _storageService;
  final void Function()? _onUnauthorized;

  AuthInterceptor({
    required SecureStorageService storageService,
    void Function()? onUnauthorized,
  })  : _storageService = storageService,
        _onUnauthorized = onUnauthorized;

  static bool _isPublicOrSubscribeEndpoint(String path) {
    return path.contains('/passport/auth/') ||
        path.contains('/passport/comm/') ||
        path.contains('/guest/') ||
        path.contains('/client/subscribe');
  }

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // 排除登入、註冊、訪客與獨立訂閱接口，防止將 JWT 誤注入至訂閱端點
    if (!_isPublicOrSubscribeEndpoint(options.path)) {
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
    final path = err.requestOptions.path;
    final statusCode = err.response?.statusCode;
    final isProtectedUserEndpoint = !_isPublicOrSubscribeEndpoint(path);

    // 攔截 401 Unauthorized，或 V2Board 標準 403「未登录或登陆已过期」回應
    if (isProtectedUserEndpoint &&
        ErrorSanitizer.isSessionExpiredResponse(statusCode, err.response?.data)) {
      SafeLog.d('[AuthInterceptor] 偵測到登入會話已過期 ($statusCode)，清理本地憑證並廣播重新驗證...');

      // 1. 清理本地安全儲存中所有 Token 與敏感資料
      await _storageService.clearAll();

      // 2. 廣播通知 UI 層 / 狀態管理器跳轉登入頁
      _onUnauthorized?.call();
    }

    return handler.next(err);
  }
}
