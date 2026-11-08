// lib/business/auth/auth_manager.dart

import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/i18n/i18n_service.dart';
import '../../core/network/dio_client.dart';
import '../../core/storage/secure_storage_service.dart';
import '../../core/utils/error_sanitizer.dart';
import '../../infrastructure/core_daemon/core_daemon.dart';
import '../../presentation/dashboard/widgets/customer_service_modal.dart';
import 'auth_state.dart';
import 'notice_model.dart';
import 'traffic_log_model.dart';
import 'traffic_notification_service.dart';
import 'user_model.dart';

/// 帳號認證與狀態管理器
class AuthManager extends ChangeNotifier {
  final DioClient _dioClient;
  final SecureStorageService _storageService;

  AuthState _state = AuthState.initial();
  AuthState get state => _state;
  DioClient get dioClient => _dioClient;

  List<NoticeModel> _notices = [];
  List<NoticeModel> get notices => _notices;

  /// 預設 16 大主流郵箱後綴白名單 (按熱門度排列)
  static const List<String> defaultEmailWhitelist = [
    'qq.com',
    'gmail.com',
    '163.com',
    'outlook.com',
    '126.com',
    'foxmail.com',
    'hotmail.com',
    'yahoo.com',
    'sina.com',
    'aliyun.com',
    '139.com',
    '189.cn',
    'sohu.com',
    'yeah.net',
    'zoho.com.cn',
    'icloud.com',
  ];

  List<String> _emailWhitelist = List.from(defaultEmailWhitelist);
  List<String> get emailWhitelist => List.unmodifiable(_emailWhitelist);

  /// 獲取後端開放的註冊郵箱後綴白名單 (GET /api/v1/guest/comm/config)
  Future<List<String>> fetchEmailWhitelist() async {
    try {
      final response = await _dioClient.get('/api/v1/guest/comm/config');
      final respData = response.data;
      if (respData is Map && respData['data'] is Map) {
        final data = respData['data'] as Map;
        final list = data['email_whitelist_suffix'];
        if (list is List && list.isNotEmpty) {
          final customList = list
              .map((e) => e.toString().trim().replaceAll('@', '').toLowerCase())
              .where((e) => e.isNotEmpty)
              .toList();
          if (customList.isNotEmpty) {
            customList.sort((a, b) {
              final idxA = defaultEmailWhitelist.indexOf(a);
              final idxB = defaultEmailWhitelist.indexOf(b);
              final weightA = idxA == -1 ? 999 : idxA;
              final weightB = idxB == -1 ? 999 : idxB;
              return weightA.compareTo(weightB);
            });
            _emailWhitelist = customList;
            notifyListeners();
            return _emailWhitelist;
          }
        }
      }
    } catch (_) {
      // 網路或介面異常時保底採用預設 16 大主流白名單
    }
    return _emailWhitelist;
  }

  AuthManager({
    required DioClient dioClient,
    required SecureStorageService storageService,
  })  : _dioClient = dioClient,
        _storageService = storageService;

  void _setState(AuthState newState) {
    _state = newState;
    notifyListeners();
  }

  /// 檢查本地登入狀態 (冷啟動時呼叫)
  Future<void> checkAuthStatus() async {
    _setState(AuthState.loading());
    final token = await _storageService.getToken();

    if (token == null || token.isEmpty) {
      _setState(AuthState.unauthenticated());
      return;
    }

    final cachedUserJson = await _storageService.getUserInfoJson();
    UserModel? cachedUser;
    if (cachedUserJson != null) {
      try {
        cachedUser = UserModel.fromRawJson(cachedUserJson);
      } catch (_) {}
    }

    try {
      final user = await fetchUserInfo();
      _setState(AuthState.authenticated(user: user, token: token));
    } on DioException catch (e) {
      // 若後端明確回傳 401 或 403「未登录或登陆已过期」，絕不可降級載入舊快取進入首頁！
      if (ErrorSanitizer.isSessionExpiredResponse(
        e.response?.statusCode,
        e.response?.data,
      )) {
        await _storageService.clearAll();
        _setState(AuthState.unauthenticated());
        return;
      }
      if (cachedUser != null) {
        _setState(AuthState.authenticated(user: cachedUser, token: token));
      } else {
        _setState(AuthState.unauthenticated());
      }
    } catch (_) {
      if (cachedUser != null) {
        _setState(AuthState.authenticated(user: cachedUser, token: token));
      } else {
        _setState(AuthState.unauthenticated());
      }
    }
  }

  /// 使用者登入 (POST /api/v1/passport/auth/login)
  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    _setState(AuthState.loading());

    try {
      final response = await _dioClient.post(
        '/api/v1/passport/auth/login',
        data: {
          'email': email.trim(),
          'password': password,
        },
      );

      final respData = response.data;
      String? token;

      if (respData is Map<String, dynamic>) {
        final data = respData['data'];
        if (data is Map<String, dynamic>) {
          // auth_data 為 JWT 認證憑據，token 為訂閱金鑰；認證優先使用 auth_data
          token = (data['auth_data'] ?? data['token']) as String?;
        } else if (data is String) {
          token = data;
        }
      }

      if (token == null || token.isEmpty) {
        throw const FormatException('登入成功但未返回有效憑證');
      }

      await _storageService.saveToken(token);
      final user = await fetchUserInfo();

      _setState(AuthState.authenticated(user: user, token: token));
      return user;
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      _setState(AuthState.error(message));
      throw Exception(message);
    } catch (e) {
      final message = ErrorSanitizer.sanitize(e);
      _setState(AuthState.error(message));
      throw Exception(message);
    }
  }

  /// 使用者註冊 (POST /api/v1/passport/auth/register)
  Future<UserModel> register({
    required String email,
    required String password,
    String? emailCode,
    String? inviteCode,
  }) async {
    _setState(AuthState.loading());

    try {
      final body = <String, dynamic>{
        'email': email.trim(),
        'password': password,
      };
      if (emailCode != null && emailCode.isNotEmpty) {
        body['email_code'] = emailCode;
      }
      if (inviteCode != null && inviteCode.isNotEmpty) {
        body['invite_code'] = inviteCode;
      }

      final response = await _dioClient.post(
        '/api/v1/passport/auth/register',
        data: body,
      );

      final respData = response.data;
      String? token;

      if (respData is Map<String, dynamic>) {
        final data = respData['data'];
        if (data is Map<String, dynamic>) {
          // 認證必須優先使用 auth_data (JWT)，不可誤存 32 位訂閱 token！
          token = (data['auth_data'] ?? data['token']) as String?;
        }
      }

      if (token == null || token.isEmpty) {
        return await login(email: email, password: password);
      }

      await _storageService.saveToken(token);
      final user = await fetchUserInfo();
      _setState(AuthState.authenticated(user: user, token: token));
      return user;
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      _setState(AuthState.error(message));
      throw Exception(message);
    } catch (e) {
      final message = ErrorSanitizer.sanitize(e);
      _setState(AuthState.error(message));
      throw Exception(message);
    }
  }

  /// 發送郵箱驗證碼 (POST /api/v1/passport/comm/sendEmailVerify)
  Future<bool> sendEmailVerify(String email) async {
    try {
      final response = await _dioClient.post(
        '/api/v1/passport/comm/sendEmailVerify',
        data: {
          'email': email.trim(),
        },
      );

      final respData = response.data;
      if (respData is Map && respData['data'] == true) {
        return true;
      }
      return true;
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      throw Exception(message);
    } catch (e) {
      throw Exception(ErrorSanitizer.sanitize(e));
    }
  }

  /// 重設/忘記密碼 (POST /api/v1/passport/auth/forget)
  Future<bool> resetPassword({
    required String email,
    required String password,
    required String emailCode,
  }) async {
    try {
      final response = await _dioClient.post(
        '/api/v1/passport/auth/forget',
        data: {
          'email': email.trim(),
          'password': password,
          'email_code': emailCode.trim(),
        },
      );

      final respData = response.data;
      if (respData is Map && respData['data'] == true) {
        return true;
      }
      return true;
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      throw Exception(message);
    } catch (e) {
      throw Exception(ErrorSanitizer.sanitize(e));
    }
  }

  /// 檢查相對訂閱路徑是否遭誤注入 JWT Token 污染
  static bool isPoisonedSubscribePath(String? path) {
    if (path == null || path.trim().isEmpty) return true;
    try {
      final dummyBase = path.startsWith('/')
          ? 'http://dummy'
          : (path.startsWith('http') ? '' : 'http://dummy/');
      final uri = Uri.parse('$dummyBase$path');
      final subToken = uri.queryParameters['token'];
      if (subToken == null || subToken.trim().isEmpty) return true;
      return isJwtCredential(subToken);
    } catch (_) {
      return true;
    }
  }

  /// 判斷字串是否為 JWT 會話憑證 (auth_data) 而非 32 位訂閱金鑰
  static bool isJwtCredential(String? value) {
    if (value == null) return false;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.toLowerCase().startsWith('bearer ')) return true;
    if (trimmed.startsWith('eyJ') && trimmed.contains('.')) return true;
    if (trimmed.split('.').length == 3 && trimmed.length > 48) return true;
    return false;
  }

  /// 獲取最新個人資料與剩餘流量 (GET /api/v1/user/info)
  Future<UserModel> fetchUserInfo({bool ignoreCachedSubscribeFallback = false}) async {
    if (_state.user != null && _mockTrafficLogs != null) {
      return _state.user!;
    }
    try {
      final response = await _dioClient.get('/api/v1/user/info');
      final respData = response.data;

      Map<String, dynamic>? dataMap;
      if (respData is Map<String, dynamic>) {
        final data = respData['data'];
        if (data is Map<String, dynamic>) {
          dataMap = Map<String, dynamic>.from(data);
        }
      }

      if (dataMap == null) {
        throw const FormatException('無法解析使用者資訊回應資料');
      }

      if (dataMap['token'] != null && isJwtCredential(dataMap['token']?.toString())) {
        dataMap.remove('token');
      }

      String? subscribeUrl;
      try {
        final subResp = await _dioClient.get('/api/v1/user/getSubscribe');
        if (subResp.data is Map && subResp.data['data'] is Map) {
          final subData = subResp.data['data'] as Map<String, dynamic>;
          subscribeUrl = subData['subscribe_url'] as String?;
          if (subData['token'] != null && !isJwtCredential(subData['token'].toString())) {
            dataMap['token'] = subData['token'];
          }
          if (subData['u'] != null) {
            dataMap['u'] = subData['u'];
          }
          if (subData['d'] != null) {
            dataMap['d'] = subData['d'];
          }
          if (subData['transfer_enable'] != null) {
            dataMap['transfer_enable'] = subData['transfer_enable'];
          }
          if (subData['expired_at'] != null) {
            dataMap['expired_at'] = subData['expired_at'];
          }
          if (subData['plan'] is Map) {
            final planMap = subData['plan'] as Map<String, dynamic>;
            if (planMap['name'] != null) {
              dataMap['plan_name'] = planMap['name'];
            }
          }
        }
      } on DioException catch (subDioErr) {
        if (ErrorSanitizer.isSessionExpiredResponse(
          subDioErr.response?.statusCode,
          subDioErr.response?.data,
        )) {
          rethrow;
        }
        SafeLog.d('[AuthManager] getSubscribe 暫時不可達，檢查本地 L2 金庫快取路徑');
        if (!ignoreCachedSubscribeFallback) {
          final cachedPath = await _storageService.getCachedSubscribePath();
          if (cachedPath != null && cachedPath.isNotEmpty) {
            if (!isPoisonedSubscribePath(cachedPath)) {
              subscribeUrl = cachedPath;
            } else {
              await _storageService.deleteCachedSubscribePath();
            }
          }
        }
      } catch (_) {
        SafeLog.d('[AuthManager] getSubscribe 回應異常，檢查本地 L2 金庫快取路徑');
        if (!ignoreCachedSubscribeFallback) {
          final cachedPath = await _storageService.getCachedSubscribePath();
          if (cachedPath != null && cachedPath.isNotEmpty) {
            if (!isPoisonedSubscribePath(cachedPath)) {
              subscribeUrl = cachedPath;
            } else {
              await _storageService.deleteCachedSubscribePath();
            }
          }
        }
      }

      if (subscribeUrl != null && subscribeUrl.isNotEmpty) {
        String relativeSubscribePath = subscribeUrl;
        if (subscribeUrl.startsWith('http://') || subscribeUrl.startsWith('https://')) {
          try {
            final uri = Uri.parse(subscribeUrl);
            final host = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
            _dioClient.configService.addCandidateDomain(host);
            relativeSubscribePath = '${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}';
          } catch (_) {}
        }
        if (!isPoisonedSubscribePath(relativeSubscribePath)) {
          await _storageService.saveCachedSubscribePath(relativeSubscribePath);
          dataMap['subscribe_url'] = relativeSubscribePath;
        }
      }

      final user = UserModel.fromJson(dataMap);
      await _storageService.saveUserInfoJson(user.toRawJson());

      if (_state.isAuthenticated) {
        _setState(_state.copyWith(user: user));
      }

      try {
        TrafficNotificationService.instance.checkTrafficAlert(user);
      } catch (_) {}

      return user;
    } on DioException catch (e) {
      if (ErrorSanitizer.isSessionExpiredResponse(
        e.response?.statusCode,
        e.response?.data,
      )) {
        if (_state.isAuthenticated) {
          handleUnauthorized();
        }
      }
      SafeLog.d('[AuthManager] 獲取使用者資訊未完成');
      rethrow;
    } catch (_) {
      SafeLog.d('[AuthManager] 獲取使用者資訊解析異常');
      rethrow;
    }
  }

  List<TrafficLogModel>? _mockTrafficLogs;

  @visibleForTesting
  void setTrafficLogsForTest(List<TrafficLogModel>? logs) {
    _mockTrafficLogs = logs;
  }

  /// 獲取流量使用明細記錄 (GET /api/v1/user/stat/getTrafficLog)
  Future<List<TrafficLogModel>> fetchTrafficLogs({int page = 1, int pageSize = 100}) async {
    if (_mockTrafficLogs != null) {
      return List.of(_mockTrafficLogs!);
    }
    try {
      final response = await _dioClient.get(
        '/api/v1/user/stat/getTrafficLog',
        queryParameters: {
          'current': page,
          'page': page,
          'pageSize': pageSize,
          'per_page': pageSize,
        },
      );
      final respData = response.data;
      SafeLog.d('[AuthManager] fetchTrafficLogs 狀態碼: ${response.statusCode}');

      List<dynamic>? rawList;
      if (respData is List) {
        rawList = respData;
      } else if (respData is Map) {
        final dataField = respData['data'];
        if (dataField is List) {
          rawList = dataField;
        } else if (dataField is Map) {
          if (dataField['data'] is List) {
            rawList = dataField['data'] as List;
          } else if (dataField['list'] is List) {
            rawList = dataField['list'] as List;
          } else if (dataField['records'] is List) {
            rawList = dataField['records'] as List;
          }
        } else if (respData['list'] is List) {
          rawList = respData['list'] as List;
        }
      }

      if (rawList != null) {
        final List<TrafficLogModel> list = [];
        for (final item in rawList) {
          try {
            if (item is Map) {
              list.add(TrafficLogModel.fromJson(Map<String, dynamic>.from(item)));
            }
          } catch (_) {
            SafeLog.d('[AuthManager] 忽略單筆格式不符的流量記錄');
          }
        }
        list.sort((a, b) => b.recordAt.compareTo(a.recordAt));
        SafeLog.d('[AuthManager] 成功解析 ${list.length} 筆流量記錄');
        return list;
      }

      return [];
    } catch (_) {
      SafeLog.d('[AuthManager] 獲取流量明細未完成');
      return [];
    }
  }

  /// 獲取系統最新公告列表 (GET /api/v1/user/notice/fetch)
  Future<List<NoticeModel>> fetchNotices() async {
    try {
      final response = await _dioClient.get('/api/v1/user/notice/fetch');
      final respData = response.data;
      if (respData is Map && respData['data'] is List) {
        final list = (respData['data'] as List)
            .whereType<Map<String, dynamic>>()
            .map((item) => NoticeModel.fromJson(item))
            .where((n) => n.show)
            .toList();
        _notices = list;
        notifyListeners();
        return list;
      }
      return [];
    } catch (_) {
      SafeLog.d('[AuthManager] 獲取公告未完成');
      return [];
    }
  }

  final List<VoidCallback> _sessionClearedListeners = [];

  /// 註冊會話清理監聽器 (如清除節點金庫與記憶體)
  void addSessionClearedListener(VoidCallback listener) {
    _sessionClearedListeners.add(listener);
  }

  /// 移除會話清理監聽器
  void removeSessionClearedListener(VoidCallback listener) {
    _sessionClearedListeners.remove(listener);
  }

  void _notifySessionCleared() {
    for (final listener in List.of(_sessionClearedListeners)) {
      try {
        listener();
      } catch (_) {}
    }
  }

  /// 主動登出 (連動斷開代理並廣播清理本地金庫與客服會話)
  Future<void> logout() async {
    try {
      await CoreDaemon.instance.stop();
    } catch (_) {}
    await _storageService.clearAll();
    try {
      await CustomerServiceModal.clearSession();
    } catch (_) {}
    _notifySessionCleared();
    _setState(AuthState.unauthenticated());
  }

  /// 由 401/403 攔截器呼叫之強制踢出程序 (連動切斷代理避免幽靈連線並清理金庫與客服會話)
  void handleUnauthorized() {
    try {
      CoreDaemon.instance.stop();
    } catch (_) {}
    unawaited(_storageService.clearAll());
    try {
      CustomerServiceModal.clearSession();
    } catch (_) {}
    _notifySessionCleared();
    _setState(
      AuthState.unauthenticated().copyWith(
        errorMessage: I18nService.instance.t('err_session_expired'),
      ),
    );
  }

  /// 提取 Dio 錯誤訊息 (提供在地化友好提示，杜絕直接輸出底層英文除錯堆疊與任何 IP/URL)
  String _extractErrorMessage(DioException e) {
    final statusCode = e.response?.statusCode;
    final respData = e.response?.data;

    if (ErrorSanitizer.isSessionExpiredResponse(statusCode, respData)) {
      return I18nService.instance.t('err_session_expired');
    }

    return ErrorSanitizer.sanitize(e);
  }

  /// 更新本地使用者狀態 (用於自動化單元測試)
  void updateUserForTest(UserModel user, {String token = 'test_token'}) {
    _setState(AuthState.authenticated(user: user, token: token));
  }
}
