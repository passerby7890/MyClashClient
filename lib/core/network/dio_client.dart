import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import '../constants/app_constants.dart';
import '../../infrastructure/config/app_config_service.dart';

/// 安全 HTTP 客戶端 (基於 Dio 封裝)
/// 支援動態 BaseUrl 切換、統一逾時設定、全域 Headers 與容錯備援
class DioClient {
  final AppConfigService _configService;
  late final Dio _dio;

  DioClient({
    required AppConfigService configService,
    Dio? customDio,
    List<Interceptor>? interceptors,
  }) : _configService = configService {
    if (customDio != null) {
      _dio = customDio;
    } else {
      _dio = Dio(
        BaseOptions(
          baseUrl: _configService.currentApiDomain,
          connectTimeout: const Duration(milliseconds: AppConstants.connectTimeoutMs),
          receiveTimeout: const Duration(milliseconds: AppConstants.receiveTimeoutMs),
          sendTimeout: const Duration(milliseconds: AppConstants.connectTimeoutMs),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json; charset=UTF-8',
            'User-Agent': 'TianheNetwork/${AppConstants.appVersion} (Macintosh; Mac OS X; Apple Silicon/Intel)',
          },
          responseType: ResponseType.json,
        ),
      );
    }

    if (!kIsWeb) {
      _dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          // 🛡️ 絕招一：禁止系統 HTTP 代理 (強制 DIRECT 直連，無視 Wi-Fi 代理 / Fiddler / Charles / 小黃鳥抓包)
          client.findProxy = (uri) => 'DIRECT';
          client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
          return client;
        },
      );
    }

    // 注入動態 BaseUrl 攔截器，確保每次請求皆使用當前最新生效的 API 網域
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (!options.path.startsWith('http')) {
            var base = _configService.currentApiDomain.trim();
            while (base.endsWith('/')) {
              base = base.substring(0, base.length - 1);
            }
            if (base.endsWith('/api/v1')) {
              base = base.substring(0, base.length - 7);
            }
            options.baseUrl = base;
          }
          return handler.next(options);
        },
        onError: (DioException err, handler) async {
          final statusCode = err.response?.statusCode;
          final isFailoverError = err.type == DioExceptionType.connectionTimeout ||
              err.type == DioExceptionType.connectionError ||
              err.type == DioExceptionType.receiveTimeout ||
              err.type == DioExceptionType.sendTimeout ||
              statusCode == 404 ||
              statusCode == 502 ||
              statusCode == 503 ||
              statusCode == 504;

          final allDomains = _configService.activeConfig.allApiDomains;
          final retryCount = (err.requestOptions.extra['api_failover_retry'] as int?) ?? 0;

          if (isFailoverError && retryCount < allDomains.length && allDomains.length > 1) {
            final nextDomain = _configService.switchNextApiDomain();
            // ignore: avoid_print
            print('[DioClient] 遭遇錯誤 (code: $statusCode, type: ${err.type})，自動切換至備援網域並重試: $nextDomain (重試 $retryCount/${allDomains.length})');

            final options = err.requestOptions;
            options.extra['api_failover_retry'] = retryCount + 1;

            var base = nextDomain.trim();
            while (base.endsWith('/')) {
              base = base.substring(0, base.length - 1);
            }
            if (base.endsWith('/api/v1')) {
              base = base.substring(0, base.length - 7);
            }
            options.baseUrl = base;

            try {
              final response = await _dio.fetch(options);
              return handler.resolve(response);
            } on DioException catch (retryErr) {
              return handler.next(retryErr);
            } catch (retryErr) {
              return handler.next(
                DioException(
                  requestOptions: options,
                  error: retryErr,
                ),
              );
            }
          }

          return handler.next(err);
        },
      ),
    );

    if (interceptors != null) {
      _dio.interceptors.addAll(interceptors);
    }
  }

  /// 取得底層 Dio 實例
  Dio get dio => _dio;

  /// 新增攔截器 (如 AuthInterceptor, LogInterceptor)
  void addInterceptor(Interceptor interceptor) {
    _dio.interceptors.add(interceptor);
  }

  /// 手動輪替至下一個備援 API 網域
  String rotateHost() {
    return _configService.switchNextApiDomain();
  }

  /// 通用 GET 請求
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return _dio.get<T>(
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  /// 通用 POST 請求
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return _dio.post<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }
}
