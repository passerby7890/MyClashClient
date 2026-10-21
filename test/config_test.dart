// test/config_test.dart

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flclash_v2board_client/core/crypto/aes_decryptor.dart';
import 'package:flclash_v2board_client/infrastructure/config/remote_config_model.dart';
import 'package:flclash_v2board_client/infrastructure/config/doh_resolver.dart';
import 'package:flclash_v2board_client/infrastructure/config/app_config_service.dart';

void main() {
  group('階段一：動態配置與 AES 解密單元測試', () {
    const rawConfigJson = '''
    {
      "api_domain": "https://api.v2board-test.com",
      "backup_api_domains": ["https://backup1.v2board-test.com", "https://backup2.v2board-test.com"],
      "latest_version": "2.1.0",
      "min_version": "1.5.0",
      "apk_url": "https://dl.test.com/app.apk",
      "exe_url": "https://dl.test.com/app.exe",
      "changelog": "修復節點自動同步問題"
    }
    ''';

    test('1. AES-256-CBC 加解密驗證 (包含帶引號的 TXT 字串清理)', () {
      final decryptor = AesDecryptor();

      // 加密原始 JSON
      final encryptedBase64 = decryptor.encrypt(rawConfigJson);
      expect(encryptedBase64.isNotEmpty, isTrue);

      // 模擬 DNS 回應時自帶的外層雙引號
      final dnsWrappedTxt = '"$encryptedBase64"';

      // 執行解密
      final decrypted = decryptor.decrypt(dnsWrappedTxt);
      final jsonMap = json.decode(decrypted) as Map<String, dynamic>;

      expect(jsonMap['api_domain'], equals('https://api.v2board-test.com'));
      expect(jsonMap['latest_version'], equals('2.1.0'));
      expect(jsonMap['min_version'], equals('1.5.0'));
    });

    test('2. RemoteConfigModel 版本比對邏輯測試', () {
      final model = RemoteConfigModel.fromRawJson(rawConfigJson);

      // 當前版本 1.0.0 < 2.1.0 -> 有新版本
      expect(model.hasNewVersion('1.0.0'), isTrue);
      // 當前版本 2.1.0 == 2.1.0 -> 無新版本
      expect(model.hasNewVersion('2.1.0'), isFalse);
      // 當前版本 2.2.0 > 2.1.0 -> 無新版本
      expect(model.hasNewVersion('2.2.0'), isFalse);

      // 當前版本 1.2.0 < min_version (1.5.0) -> 強制更新
      expect(model.isForceUpdate('1.2.0'), isTrue);
      // 當前版本 1.5.0 >= min_version (1.5.0) -> 非強制更新
      expect(model.isForceUpdate('1.5.0'), isFalse);
    });

    test('3. DohResolver 模擬 Cloudflare DoH 解析', () async {
      final mockCipher = AesDecryptor.encryptDefault(rawConfigJson);

      final mockClient = MockClient((request) async {
        if (request.url.host == 'cloudflare-dns.com') {
          return http.Response(
            json.encode({
              'Status': 0,
              'Answer': [
                {'name': 'config.test.com', 'type': 16, 'data': '"$mockCipher"'}
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final resolver = DohResolver(client: mockClient);
      final resultTxt = await resolver.resolveTxtMultiLevel('config.test.com');

      expect(resultTxt, contains(mockCipher));
    });

    test('4. AppConfigService 端到端解密還原測試', () async {
      final mockCipher = AesDecryptor.encryptDefault(rawConfigJson);

      final mockClient = MockClient((request) async {
        return http.Response(
          json.encode({
            'Status': 0,
            'Answer': [
              {'name': 'config.test.com', 'type': 16, 'data': '"$mockCipher"'}
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final resolver = DohResolver(client: mockClient);
      final service = AppConfigService(dohResolver: resolver);

      final config = await service.fetchRemoteConfig();
      expect(config.apiDomain, equals('https://api.v2board-test.com'));
      expect(config.allApiDomains.length, equals(3));
    });

    test('5. novaclash.spsr86.cv 格式之 Base64 直接解碼 TXT 解析驗證', () async {
      const tianheJson = '''
      {
        "Authentication": "天河网络",
        "host_source": "https://portal.thjs789.com/",
        "Customer": "https://t.me/q8891qcom",
        "crisp": "b8b32705-d834-41b5-b6f5-6849fa0679d6",
        "InviteLink": "https://0n21.com/#/register?code=",
        "UpdateUrl": "https://novaclash.oss-ap-northeast-1.aliyuncs.com/update.json",
        "hosts": [
          "https://8.218.176.238:3389",
          "https://8.218.176.238:8443",
          "https://8.219.196.216:3389"
        ]
      }
      ''';

      final base64Txt = base64.encode(utf8.encode(tianheJson));

      final mockClient = MockClient((request) async {
        return http.Response(
          json.encode({
            'Status': 0,
            'Answer': [
              {'name': 'novaclash.spsr86.cv', 'type': 16, 'data': '"$base64Txt"'}
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final resolver = DohResolver(client: mockClient);
      final service = AppConfigService(dohResolver: resolver);

      final config = await service.fetchRemoteConfig();
      expect(config.apiDomain, equals('https://8.218.176.238:3389'));
      expect(config.backupApiDomains.length, equals(2));
      expect(config.backupApiDomains, contains('https://8.218.176.238:8443'));
      expect(config.backupApiDomains, contains('https://8.219.196.216:3389'));
      expect(config.websiteUrl, equals('https://portal.thjs789.com/'));
      expect(config.allApiDomains, isNot(contains('https://portal.thjs789.com')));
      expect(config.appName, equals('天河网络'));
      expect(config.customerUrl, equals('https://t.me/q8891qcom'));
      expect(config.crispId, equals('b8b32705-d834-41b5-b6f5-6849fa0679d6'));
    });

    test('6. 驗證 Tianhe / OpenClash 格式之 hosts 優先代入 API，門戶前台 portal 絕對隔離', () {
      final config = RemoteConfigModel.fromJson({
        'Authentication': '天河网络',
        'host_source': 'https://portal.thjs789.com/',
        'hosts': [
          'https://8.218.176.238:3389',
          'https://8.218.176.238:8443',
          'https://8.219.196.216:3389'
        ]
      });

      // API 網域必須是真實 API 伺服器 (8.218.176.238:3389)，絕不可為 portal.thjs789.com
      expect(config.apiDomain, equals('https://8.218.176.238:3389'));
      expect(config.websiteUrl, equals('https://portal.thjs789.com/'));
      expect(config.backupApiDomains, contains('https://8.218.176.238:8443'));
      expect(config.allApiDomains.contains('https://portal.thjs789.com'), isFalse);
    });

    test('7. 實戰驗證 thjsqaes32.spsr86.cv 多段分割 TXT 之 AES-256-CBC 正確解密', () async {
      // 模擬 Cloudflare DNS 返回的真實多段分割 TXT 字串
      const multiChunkTxt =
          '"a+QP/3qULxpZwhueNjcxwKJ6soturvOaDOH7r94u7G3sD6MIKVUkeIyndS7pW4o+/LM3VmDqF8So4Mn2kWNeHmPPoRklVQC9LnlccHjXHeBOUcxNeUv8huJucLpUMQqGW/KJ3/m/uaJOea2pz9gnqJ9Xm9jq7K9wGAg421qUDLAZLxQVVI52oDM+7O68U5PnMwpaCryzOx/AU/f2yyAU5X9zI/CuM5b4HRp61iI2j5FRS9l05H9uaebGi+PH7HJ" '
          '"LZ1mckor+/FXih2oLuAwqaqlWwNhL3FNPE5fS61o0dLy7J1lvGWOnCgu8haq/87ZM+CY4Zv/Jy1gF5/mT7QR1ZfmQqfo/VlgBiDp4oqOH/okpY/jkywV6pZOjUY19xlqtNBsXLBEsJnlK4pXRUOPBodixQ/k1ggXYX8GPkxhoFyzCq0HaiNjQRO0H9NuHmPrOKJ5oYWKBKaeRvk6eLccCo1+0pBWlIJ5iP3Oz7lhnxUzX5E/r7PRGyKKD3sjg4y" '
          '"6G1r4u5VV9Ye3cAbMYoBafrq8SjSFR5lZUsdVTnBVhUgAC0LCszKeVCSWq8nyd8rYi41bcntZpESlNJftsZ+T/uT50PRnPILkrc70QiBJ8cWthxyhEk2P+PTEggolXB+5S5U8xMz5MgzN4ejhQUFPX6Rg9fpgmJ7+EQJQw7aOGyfxlanSc7lDPQ9vykDkNEKBimUnxk3XEBK78iOfyJHg/SoL+DZr3iRpm/fxB09tJtZ4MwZwoSG1uzp4YURFkd" '
          '"e9IG+7W1z+qDKxNJDFrGLWow7ItAThPLHH9+nyxYKR8WM7JJRoGkVyVLNaYW5wHKAgE+zTSxbPEcSK9N5urZMuU1LvzoOji6F40911/bhdM9M6aUTdXIOKSBsrEBKQe6XDE"';

      final mockClient = MockClient((request) async {
        return http.Response(
            json.encode({
              'Status': 0,
              'Answer': [
                {
                  'name': 'thjsqaes32.spsr86.cv',
                  'type': 16,
                  'data': multiChunkTxt,
                }
              ]
            }),
            200);
      });

      final resolver = DohResolver(client: mockClient);
      final service = AppConfigService(dohResolver: resolver);

      final config = await service.fetchRemoteConfig();
      expect(config.appName, equals('天河网络'));
      expect(config.apiDomain, equals('https://8.218.176.238:3389'));
      expect(config.backupApiDomains, contains('https://8.218.176.238:8443'));
      expect(config.backupApiDomains, contains('https://8.219.196.216:3389'));
      expect(config.websiteUrl, equals('https://portal.thjs789.com/'));
      expect(config.customerUrl, equals('https://t.me/q8891qcom'));
      expect(config.crispId, equals('b8b32705-d834-41b5-b6f5-6849fa0679d6'));
      expect(config.inviteLink, equals('https://0n21.com/#/register?code='));
      expect(config.latestVersion, equals('1.0.0'));
      expect(config.minVersion, equals('1.0.0'));
      expect(config.apkUrl, equals('https://portal.thjs789.com/d/android.apk'));
      expect(config.enableTrafficDetails, isTrue);
      expect(config.enableOnlineTicket, isTrue);
      expect(config.enableNotice, isTrue);
      expect(config.carouselItems.length, equals(1));
    });

    test('8. 實戰驗證 OSS (web-config.json) AES-256-CBC 格式正確解密解析', () {
      final decryptor = AesDecryptor();
      const ossCiphertext =
          'a+QP/3qULxpZwhueNjcxwKJ6soturvOaDOH7r94u7G3sD6MIKVUkeIyndS7pW4o+/LM3VmDqF8So4Mn2kWNeHmPPoRklVQC9LnlccHjXHeBOUcxNeUv8huJucLpUMQqGW/KJ3/m/uaJOea2pz9gnqJ9Xm9jq7K9wGAg421qUDLAZLxQVVI52oDM+7O68U5PnMwpaCryzOx/AU/f2yyAU5X9zI/CuM5b4HRp61iI2j5FRS9l05H9uaebGi+PH7HJLZ1mckor+/FXih2oLuAwqaqlWwNhL3FNPE5fS61o0dLy7J1lvGWOnCgu8haq/87ZM+CY4Zv/Jy1gF5/mT7QR1ZfmQqfo/VlgBiDp4oqOH/okpY/jkywV6pZOjUY19xlqtNBsXLBEsJnlK4pXRUOPBodixQ/k1ggXYX8GPkxhoFyzCq0HaiNjQRO0H9NuHmPrOKJ5oYWKBKaeRvk6eLccCo1+0pBWlIJ5iP3Oz7lhnxUzX5E/r7PRGyKKD3sjg4y6G1r4u5VV9Ye3cAbMYoBafrq8SjSFR5lZUsdVTnBVhUgAC0LCszKeVCSWq8nyd8rYi41bcntZpESlNJftsZ+T/uT50PRnPILkrc70QiBJ8cWthxyhEk2P+PTEggolXB+5S5U8xMz5MgzN4ejhQUFPX6Rg9fpgmJ7+EQJQw7aOGyfxlanSc7lDPQ9vykDkNEKBimUnxk3XEBK78iOfyJHg/SoL+DZr3iRpm/fxB09tJtZ4MwZwoSG1uzp4YURFkde9IG+7W1z+qDKxNJDFrGLWow7ItAThPLHH9+nyxYKR8WM7JJRoGkVyVLNaYW5wHKAgE+zTSxbPEcSK9N5urZMuU1LvzoOji6F40911/bhdM9M6aUTdXIOKSBsrEBKQe6XDE';

      final decrypted = decryptor.decrypt(ossCiphertext);
      final jsonMap = json.decode(decrypted) as Map<String, dynamic>;
      final config = RemoteConfigModel.fromJson(jsonMap);

      expect(config.appName, equals('天河网络'));
      expect(config.apiDomain, equals('https://8.218.176.238:3389'));
      expect(config.backupApiDomains, contains('https://8.218.176.238:8443'));
    });
  });
}
