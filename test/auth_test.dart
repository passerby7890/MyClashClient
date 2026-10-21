import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:flclash_v2board_client/business/auth/user_model.dart';
import 'package:flclash_v2board_client/business/auth/auth_state.dart';
import 'package:flclash_v2board_client/core/network/auth_interceptor.dart';
import 'package:flclash_v2board_client/core/storage/secure_storage_service.dart';

// 模擬 MockSecureStorage
class MockSecureStorage extends SecureStorageService {
  String? token;
  String? userInfo;
  bool cleared = false;

  @override
  Future<void> saveToken(String t) async {
    token = t;
  }

  @override
  Future<String?> getToken() async => token;

  @override
  Future<void> saveUserInfoJson(String json) async {
    userInfo = json;
  }

  @override
  Future<String?> getUserInfoJson() async => userInfo;

  @override
  Future<void> clearAll() async {
    token = null;
    userInfo = null;
    cleared = true;
  }
}

class _Mock401Adapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{"message":"Unauthorized"}',
      401,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('階段二：帳號認證與 UserModel 流量計算單元測試', () {
    test('1. UserModel 流量計算與到期日格式化', () {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final user = UserModel(
        email: 'test@example.com',
        transferEnable: 100 * 1024 * 1024 * 1024, // 100 GB
        u: 10 * 1024 * 1024 * 1024, // 10 GB
        d: 20 * 1024 * 1024 * 1024, // 20 GB
        expiredAt: nowSec + 86400 * 30, // 30 天後過期
        token: 'test_sub_token',
      );

      expect(user.usedTrafficBytes, equals(30 * 1024 * 1024 * 1024));
      expect(user.remainingTrafficBytes, equals(70 * 1024 * 1024 * 1024));
      expect(user.usedPercentage, closeTo(0.30, 0.01));
      expect(user.usedTrafficFormatted, equals('30.00 GB'));
      expect(user.totalTrafficFormatted, equals('100.00 GB'));
      expect(user.remainingTrafficFormatted, equals('70.00 GB'));
      expect(user.isExpired, isFalse);
      expect(user.isTrafficDepleted, isFalse);
      expect(user.isAvailable, isTrue);
    });

    test('2. 流量耗盡與過期邊界狀態測試', () {
      const depletedUser = UserModel(
        email: 'depleted@example.com',
        transferEnable: 10 * 1024 * 1024 * 1024,
        u: 5 * 1024 * 1024 * 1024,
        d: 6 * 1024 * 1024 * 1024, // 超出 1GB
        expiredAt: 0,
      );

      expect(depletedUser.remainingTrafficBytes, equals(0));
      expect(depletedUser.usedPercentage, equals(1.0));
      expect(depletedUser.isTrafficDepleted, isTrue);
      expect(depletedUser.isAvailable, isFalse);
    });

    test('3. AuthInterceptor 401 攔截與自動清除憑證測試', () async {
      final mockStorage = MockSecureStorage();
      await mockStorage.saveToken('expired_jwt_token');

      bool unauthorizedTriggered = false;
      final interceptor = AuthInterceptor(
        storageService: mockStorage,
        onUnauthorized: () {
          unauthorizedTriggered = true;
        },
      );

      final dio = Dio();
      dio.httpClientAdapter = _Mock401Adapter();
      dio.interceptors.add(interceptor);

      try {
        await dio.get('https://api.test.com/api/v1/user/info');
      } catch (_) {}

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // 驗證 401 是否自動觸發 clearAll 與回調
      expect(mockStorage.cleared, isTrue);
      expect(unauthorizedTriggered, isTrue);
      expect(await mockStorage.getToken(), isNull);
    });

    test('4. AuthState 狀態變遷測試', () {
      var state = AuthState.initial();
      expect(state.status, equals(AuthStatus.initial));
      expect(state.isAuthenticated, isFalse);

      state = AuthState.loading();
      expect(state.isLoading, isTrue);

      const user = UserModel(
        email: 'user@test.com',
        transferEnable: 1000,
        u: 100,
        d: 200,
      );
      state = AuthState.authenticated(user: user, token: 'token_123');
      expect(state.isAuthenticated, isTrue);
      expect(state.user?.email, equals('user@test.com'));
      expect(state.token, equals('token_123'));

      state = AuthState.unauthenticated();
      expect(state.isAuthenticated, isFalse);
    });
  });
}
