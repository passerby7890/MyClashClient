// lib/business/auth/auth_manager.dart

import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/network/dio_client.dart';
import '../../core/storage/secure_storage_service.dart';
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
            // 依據 16 大主流熱門度權重排序 (常用郵箱靠前)
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

    // 嘗試從本地安全快取讀取用戶資料，以便離線時先進入首頁
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
    } catch (e) {
      if (cachedUser != null) {
        // 伺服器短暫不可達但本機有快取，仍允許進入
        _setState(AuthState.authenticated(user: cachedUser, token: token));
      } else {
        _setState(AuthState.unauthenticated());
      }
    }
  }

  /// 使用者登入 (對接 V2Board: POST /api/v1/passport/auth/login)
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
          // V2Board 核心規則：auth_data 為 JWT 認證憑據，token 為訂閱金鑰；認證優先使用 auth_data
          token = (data['auth_data'] ?? data['token']) as String?;
        } else if (data is String) {
          token = data;
        }
      }

      if (token == null || token.isEmpty) {
        throw const FormatException('登入成功但後端未返回有效的 Token 憑證');
      }

      // 儲存 JWT Token
      await _storageService.saveToken(token);

      // 獲取使用者資料與流量配額
      final user = await fetchUserInfo();

      _setState(AuthState.authenticated(user: user, token: token));
      return user;
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      _setState(AuthState.error(message));
      throw Exception(message);
    } catch (e) {
      final message = e.toString();
      _setState(AuthState.error(message));
      throw Exception(message);
    }
  }

  /// 使用者註冊 (對接 V2Board: POST /api/v1/passport/auth/register)
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
          token = (data['token'] ?? data['auth_data']) as String?;
        }
      }

      // 若註冊後後端未直接回傳 Token，自動執行登入
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
      final message = e.toString();
      _setState(AuthState.error(message));
      throw Exception(message);
    }
  }

  /// 發送郵箱驗證碼 (對接 V2Board: POST /api/v1/passport/comm/sendEmailVerify)
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
      throw Exception(e.toString());
    }
  }

  /// 重設/忘記密碼 (對接 V2Board: POST /api/v1/passport/auth/forget)
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
      throw Exception(e.toString());
    }
  }

  /// 獲取最新個人資料與剩餘流量 (GET /api/v1/user/info)
  Future<UserModel> fetchUserInfo() async {
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
          dataMap = data;
        }
      }

      if (dataMap == null) {
        throw const FormatException('無法解析使用者資訊回應資料');
      }

      // 嘗試獲取獨立訂閱配置資訊 (包括專用 subscribe_url, u, d, 流量上限與套餐資訊)
      String? subscribeUrl;
      try {
        final subResp = await _dioClient.get('/api/v1/user/getSubscribe');
        if (subResp.data is Map && subResp.data['data'] is Map) {
          final subData = subResp.data['data'] as Map<String, dynamic>;
          subscribeUrl = subData['subscribe_url'] as String?;
          if (subData['token'] != null) {
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
      } catch (e) {
        debugPrint('[AuthManager] /api/v1/user/getSubscribe 獲取失敗: $e，嘗試從本地 L2 加密金庫還原 subscribe_path');
        final cachedPath = await _storageService.getCachedSubscribePath();
        if (cachedPath != null && cachedPath.isNotEmpty) {
          subscribeUrl = cachedPath;
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
        await _storageService.saveCachedSubscribePath(relativeSubscribePath);
        dataMap['subscribe_url'] = relativeSubscribePath;
      }

      final user = UserModel.fromJson(dataMap);
      await _storageService.saveUserInfoJson(user.toRawJson());

      if (_state.isAuthenticated) {
        _setState(_state.copyWith(user: user));
      }

      // 觸發流量預警檢測 (TODO-03)
      try {
        TrafficNotificationService.instance.checkTrafficAlert(user);
      } catch (_) {}

      return user;
    } catch (e) {
      // ignore: avoid_print
      print('[AuthManager] 獲取使用者資訊失敗: $e');
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
      debugPrint('[AuthManager] fetchTrafficLogs 狀態碼: ${response.statusCode}, 根資料型態: ${respData.runtimeType}');

      List<dynamic>? rawList;
      if (respData is List) {
        rawList = respData;
      } else if (respData is Map) {
        final dataField = respData['data'];
        if (dataField is List) {
          rawList = dataField;
        } else if (dataField is Map) {
          // V2Board / Laravel Paginator: response.data['data']['data']
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
          } catch (itemErr) {
            debugPrint('[AuthManager] 解析單筆 TrafficLog 異常: $itemErr, 原始數據: $item');
          }
        }
        list.sort((a, b) => b.recordAt.compareTo(a.recordAt));
        debugPrint('[AuthManager] 成功解析 ${list.length} 筆真實流量記錄');
        return list;
      }

      debugPrint('[AuthManager] 未能從 API 回應中解析出流量記錄列表: $respData');
      return [];
    } catch (e, stack) {
      // ignore: avoid_print
      print('[AuthManager] 獲取流量明細失敗: $e\n$stack');
      return [];
    }
  }

  /// 獲取系統最新公告列表 (對齊 V2Board /api/v1/user/notice/fetch)
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
    } catch (e) {
      // ignore: avoid_print
      print('[AuthManager] 獲取公告失敗: $e');
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

  /// 主動登出 (連動斷開 VPN 代理並廣播清理本地金庫與客服會話)
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

  /// 由 401 攔截器呼叫之強制踢出程序 (連動切斷 VPN 避免幽靈代理並清理金庫與客服會話)
  void handleUnauthorized() {
    try {
      CoreDaemon.instance.stop();
    } catch (_) {}
    try {
      CustomerServiceModal.clearSession();
    } catch (_) {}
    _notifySessionCleared();
    _setState(
      AuthState.unauthenticated().copyWith(
        errorMessage: '登入已過期或在其他裝置登入，請重新驗證',
      ),
    );
  }

  /// 提取 Dio 錯誤訊息 (提供在地化友好提示，杜絕直接輸出底層英文除錯堆疊)
  String _extractErrorMessage(DioException e) {
    if (e.response?.data is Map) {
      final data = e.response!.data as Map;
      if (data['message'] != null && data['message'].toString().isNotEmpty) {
        return data['message'].toString();
      }
      if (data['errors'] is Map) {
        final errors = data['errors'] as Map;
        final firstError = errors.values.first;
        if (firstError is List && firstError.isNotEmpty) {
          return firstError.first.toString();
        }
        return errors.values.first.toString();
      }
    }

    final statusCode = e.response?.statusCode;
    if (statusCode == 400 || statusCode == 422) {
      return '電子郵件或密碼輸入有誤，請確認後重試';
    }
    if (statusCode == 401) {
      return '登入驗證失敗或憑證無效';
    }
    if (statusCode == 403) {
      return '存取遭拒絕，請聯絡客服';
    }
    if (statusCode == 404) {
      return 'API 伺服器端點異常 (404)，備援線路切換中，請重試';
    }
    if (statusCode != null && statusCode >= 500) {
      return '伺服器維護中 ($statusCode)，請稍後再試';
    }

    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return '網路連線逾時，請檢查網路連線或稍後重試';
    }
    if (e.type == DioExceptionType.connectionError) {
      return '無法連線至伺服器，請確認網路連線';
    }
    return '伺服器通訊異常，請稍後重試';
  }

  /// 更新本地使用者狀態 (用於演示模式或自動化測試)
  void updateUserForTest(UserModel user, {String token = 'test_token'}) {
    _setState(AuthState.authenticated(user: user, token: token));
  }
}
