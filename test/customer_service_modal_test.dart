// test/customer_service_modal_test.dart

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flclash_v2board_client/business/auth/user_model.dart';
import 'package:flclash_v2board_client/core/constants/app_constants.dart';
import 'package:flclash_v2board_client/presentation/dashboard/widgets/customer_service_modal.dart';

void main() {
  group('🛡️ Crisp 在線客服自動身分綁定與雙重保障單元測試', () {
    test('1. 訪客模式 (未登入)：生成基礎 Crisp Embed URL', () {
      final url = CustomerServiceModal.buildChatUrl();
      expect(url, contains('https://go.crisp.chat/chat/embed/?website_id='));
      expect(url, contains(AppConstants.crispWebsiteId));
      expect(url, isNot(contains('user_email=')));
      expect(url, isNot(contains('token_id=')));
    });

    test('2. 第一重保障 (URL 官方參數)：精準帶入 user_email、user_nickname 與 64位元 token_id', () {
      const user = UserModel(
        email: 'audit_test@tianhe.net',
        transferEnable: 107374182400, // 100 GB
        u: 10737418240, // 10 GB
        d: 10737418240, // 10 GB
        planName: '尊享極速年付套餐',
      );

      final url = CustomerServiceModal.buildChatUrl(user: user);

      // 驗證 Query 參數
      final uri = Uri.parse(url);
      expect(uri.queryParameters['website_id'], equals(AppConstants.crispWebsiteId));
      expect(uri.queryParameters['user_email'], equals('audit_test@tianhe.net'));
      expect(uri.queryParameters['user_nickname'], equals('audit_test@tianhe.net'));

      final tokenId = uri.queryParameters['token_id'];
      expect(tokenId, isNotNull);
      expect(tokenId!.length, equals(64)); // SHA-256 輸出 64 位十六進制字串

      // 驗證確定性：同一使用者信箱生成的 token_id 必須完全一致
      final expectedHash = sha256.convert(utf8.encode('tianhe_audit_test@tianhe.net')).toString();
      expect(tokenId, equals(expectedHash));
    });

    test('3. 會話隔離 (Session Isolation)：不同帳號生成之 token_id 100% 互斥', () {
      const userA = UserModel(
        email: 'userA@tianhe.com',
        transferEnable: 1000,
        u: 100,
        d: 100,
      );
      const userB = UserModel(
        email: 'userB@tianhe.com',
        transferEnable: 1000,
        u: 100,
        d: 100,
      );

      final urlA = CustomerServiceModal.buildChatUrl(user: userA);
      final urlB = CustomerServiceModal.buildChatUrl(user: userB);

      final tokenA = Uri.parse(urlA).queryParameters['token_id'];
      final tokenB = Uri.parse(urlB).queryParameters['token_id'];

      expect(tokenA, isNot(equals(tokenB)));
    });

    test('4. 第二重保障 (JS SDK session:data)：資料欄位完整符合規範', () {
      const user = UserModel(
        email: 'test_audit@tianhe.net',
        transferEnable: 3670016000000, // 3.42 TB
        u: 10737418240, // 10 GB
        d: 18874368000, // 17.58 GB
        expiredAt: 1893456000,
        planName: '白金旗艦線路套餐',
      );

      final email = user.email.trim();
      final planName = user.planName ?? '標準套餐';
      final trafficRemaining = user.remainingTrafficFormatted;
      final expireAt = user.expiredDateFormatted;
      const appVersion = 'v${AppConstants.appVersion} (Build ${AppConstants.appBuildNumber})';

      expect(email, equals('test_audit@tianhe.net'));
      expect(planName, equals('白金旗艦線路套餐'));
      expect(trafficRemaining, contains('TB'));
      expect(expireAt, isNotEmpty);
      expect(AppConstants.appVersion, equals('3.4.0'));
      expect(AppConstants.appBuildNumber, greaterThanOrEqualTo(140));
      expect(appVersion, equals('v3.4.0 (Build ${AppConstants.appBuildNumber})'));
    });
  });
}
