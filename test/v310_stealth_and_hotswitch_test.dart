// test/v310_stealth_and_hotswitch_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flclash_v2board_client/core/constants/app_constants.dart';
import 'package:flclash_v2board_client/core/i18n/i18n_service.dart';
import 'package:flclash_v2board_client/core/utils/error_sanitizer.dart';
import 'package:flclash_v2board_client/business/subscription/node_model.dart';

void main() {
  group('🛡️ 天河網絡 v3.1.0 (Build 111) 零洩漏隱密性與節點熱切換全自動化驗收測試', () {
    test('1. 版本號與 Build Number 單一事實來源對齊 3.3.1+131', () {
      expect(AppConstants.appVersion, equals('3.3.1'));
      expect(AppConstants.appBuildNumber, equals(131));
      expect(AppConstants.fullVersionDisplay, equals('v3.3.1 (Build 131)'));
      expect(AppConstants.versionTag, equals('v3.3.1'));
    });

    test('2. 常數層 0x5A XOR 混淆解密驗證 (Crisp, DoH, Host 零明文硬編碼)', () {
      expect(AppConstants.crispEmbedBaseUrl, equals('https://go.crisp.chat/chat/embed/'));
      expect(AppConstants.cloudflareDnsOverHttpsFallback, equals('https://1.1.1.1/dns-query#PROXY'));
      expect(AppConstants.googleDnsOverHttpsFallback, equals('https://dns.google/dns-query#PROXY'));
      expect(AppConstants.tencentDnsOverHttpsFallback, equals('https://doh.pub/dns-query'));
      expect(AppConstants.aliDnsOverHttpsFallback, equals('https://dns.alidns.com/dns-query'));
      expect(AppConstants.cloudflareDnsHost, equals('cloudflare-dns.com'));
    });

    test('3. ErrorSanitizer 嚴格脫敏防護：完全消除 IP, URL, Token 與底層核心關鍵字', () {
      final leakEx = Exception('Connect to https://8.218.176.238:8443/api/v1/client/subscribe?token=9f8c7e6d failed with status 403');
      final sanitized = ErrorSanitizer.sanitize(leakEx);
      expect(sanitized, isNot(contains('8.218.176.238')));
      expect(sanitized, isNot(contains('8443')));
      expect(sanitized, isNot(contains('9f8c7e6d')));
      expect(sanitized, isNot(contains('api/v1')));
      expect(sanitized, isNot(contains('subscribe')));

      // 核心關鍵字脫敏檢驗
      const rawCoreLog = 'Mihomo core crashed: wintun.dll failed to initialize v2board subscription from flclash';
      final scrubbed = ErrorSanitizer.scrubSensitiveText(rawCoreLog);
      expect(scrubbed.toLowerCase(), isNot(contains('mihomo')));
      expect(scrubbed.toLowerCase(), isNot(contains('v2board')));
      expect(scrubbed.toLowerCase(), isNot(contains('flclash')));
      expect(scrubbed.toLowerCase(), isNot(contains('wintun')));
    });

    test('4. 零明文原則：NodeModel 嚴格杜絕底層真實密碼與伺服器 IP 對外暴露', () {
      final node = NodeModel(
        id: 'node-01',
        name: '🇭🇰 香港 01 - 尊享旗艦專線',
        flagEmoji: '🇭🇰',
        protocol: 'vmess',
        rawConfig: {
          'server': '103.21.244.12',
          'uuid': 'd3b07384-d113-4c95-b9b2-3e2fa1a4dfc6',
          'alterId': 0,
        },
      );

      // UI 允許查看之欄位
      expect(node.id, equals('node-01'));
      expect(node.name, contains('香港'));
      expect(node.protocol, equals('vmess'));
      expect(node.flagEmoji, equals('🇭🇰'));

      // 嚴格審查：toString() 與內部不可直接洩漏未脫敏敏感資訊
      expect(node.toString(), isNot(contains('103.21.244.12')));
      expect(node.toString(), isNot(contains('d3b07384')));

      // 內部真實參數只在記憶體內且為 unmodifiable
      expect(node.internalRawConfig['server'], equals('103.21.244.12'));
    });

    test('5. 四國語言 (zh_TW, zh_CN, en, ja) 鍵值完整對齊與逾時鍵多語驗證', () {
      final i18n = I18nService.instance;
      for (final code in ['zh_TW', 'zh_CN', 'en', 'ja']) {
        i18n.setLocale(code);
        expect(i18n.t('node_timeout'), isNotEmpty);
        expect(i18n.t('guest_mode'), isNotEmpty);
        expect(i18n.t('node_unselected'), isNotEmpty);
        expect(i18n.t('doh_multi_tier_active'), isNotEmpty);
        expect(i18n.t('err_request_timeout'), isNotEmpty);
        expect(i18n.t('ticket_create_failed_prefix'), isNotEmpty);
        expect(i18n.t('change_pw_failed_prefix'), isNotEmpty);
      }
      i18n.setLocale('zh_TW'); // 重置為預設
    });
  });
}
