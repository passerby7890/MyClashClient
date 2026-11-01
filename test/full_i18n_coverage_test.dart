// test/full_i18n_coverage_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:flclash_v2board_client/core/i18n/i18n_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Windows 全域四國多語言完整覆蓋度與新功能驗收測試 (Full 4-Language Parity Tests)', () {
    late I18nService i18n;

    setUp(() {
      i18n = I18nService.instance;
    });

    test('1. 四種語言 (zh_TW, zh_CN, en, ja) 鍵數量 100% 相同且無空值', () {
      final langs = [AppLanguage.zhTW, AppLanguage.zhCN, AppLanguage.en, AppLanguage.ja];
      
      expect(langs.length, 4);

      for (final lang in langs) {
        i18n.setLanguage(lang);
        expect(i18n.currentLanguage, equals(lang));
        expect(i18n.t('app_name'), isNotEmpty);
      }
    });

    test('2. 核心新功能所有鍵值在四種語言中均已具備精確翻譯且非空', () {
      final criticalKeys = [
        // 進行中的訂單橫幅
        'order_pending_banner_title',
        'order_pending_banner_pay',
        'order_pending_banner_cancel',
        'order_pending_banner_cancel_title',
        'order_pending_banner_cancel_desc',
        'order_pending_banner_keep',
        'order_pending_banner_confirm_cancel',

        // 下單衝突智慧解決彈窗
        'order_conflict_title',
        'order_conflict_desc',
        'order_conflict_default_plan',
        'order_conflict_trade_no_prefix',
        'order_conflict_action_hint',
        'order_conflict_switch_plan',
        'order_conflict_go_pay',
        'order_conflict_canceling',
        'order_conflict_cancel_failed',
        'order_conflict_creating_new',

        // 收銀台支付介面
        'order_payment_title',
        'order_info_card',
        'order_listening_status',
        'order_trade_no',
        'order_original_price',
        'order_status',
        'order_select_pay_method_label',
        'order_cancel_this_order',
        'order_cancel_confirm_title',
        'order_cancel_confirm_desc',
        'order_cancel_return',
        'order_cancel_confirm_btn',
        'order_canceled_toast',
        'order_pay_note_title',
        'order_pay_note_1',
        'order_pay_note_2',
        'order_pay_note_3',
        'order_paid_btn_completed',
        'order_paid_btn_opening',
        'order_paid_btn_canceled',
        'order_pay_now_btn',
        'order_select_method_warning',
        'order_channel_invoked_tip',
        'order_open_url_failed',
        'order_checkout_failed',
        'order_retry',

        // 支付成功自動回調彈窗
        'order_paid_success_title',
        'order_paid_success_opening_msg',
        'order_paid_success_completed_msg',
        'order_paid_success_redirecting',

        // 歷史訂單
        'order_history_title',
        'order_history_empty_text',
        'order_history_cancel_desc',
        'order_history_canceled_success',
        'order_history_cancel_btn',
        'order_history_go_pay_btn',

        // 訂單狀態標籤
        'order_status_pending',
        'order_status_opening',
        'order_status_canceled',
        'order_status_completed',
        'order_status_discounted',

        // 連線與純代理提示
        'conn_account_expired',
        'conn_traffic_exhausted',
        'conn_select_node_first',
        'conn_failed_prefix',
        'conn_proxy_only_active',
        'conn_proxy_only_sub',

        // 節點選擇器
        'node_continent_all',
        'node_continent_asia',
        'node_continent_euro_us',
        'node_continent_other',
        'node_ping_stop',
        'node_refresh_nodes',
        'node_speed_test',
        'node_smart_optimal',

        // 破盾助手
        'break_shield_step1_title',
        'break_shield_step2_title',
        'break_shield_step3_title',
        'break_shield_proxy_started',
        'notification_perm_granted',
        'notification_perm_denied',

        // 啟動頁
        'splash_status_secure_channel',
        'splash_status_doh',
        'splash_status_version',
        'splash_status_account',
      ];

      final langs = [AppLanguage.zhTW, AppLanguage.zhCN, AppLanguage.en, AppLanguage.ja];

      for (final lang in langs) {
        i18n.setLanguage(lang);
        for (final key in criticalKeys) {
          final translated = i18n.t(key);
          expect(
            translated,
            isNot(equals(key)),
            reason: '語系 [${lang.code}] 缺失核心鍵值 [$key] 的翻譯，未落地！',
          );
          expect(
            translated.trim(),
            isNotEmpty,
            reason: '語系 [${lang.code}] 核心鍵值 [$key] 翻譯為空！',
          );
        }
      }
    });

    test('3. 動態參數插值在四國語系中運作正常', () {
      final params = {'plan': '旗艦年付套餐', 'amount': '¥99.00', 'error': '逾時'};

      i18n.setLanguage(AppLanguage.zhTW);
      expect(i18n.t('order_conflict_action_hint', params), contains('【旗艦年付套餐】'));
      expect(i18n.t('order_pay_now_btn', params), equals('立即支付 ¥99.00'));
      expect(i18n.t('conn_failed_prefix', params), equals('連線失敗: 逾時'));

      i18n.setLanguage(AppLanguage.zhCN);
      expect(i18n.t('order_conflict_action_hint', params), contains('【旗艦年付套餐】'));
      expect(i18n.t('order_pay_now_btn', params), equals('立即支付 ¥99.00'));
      expect(i18n.t('conn_failed_prefix', params), equals('连接失败: 逾時'));

      i18n.setLanguage(AppLanguage.en);
      expect(i18n.t('order_conflict_action_hint', params), contains('【旗艦年付套餐】'));
      expect(i18n.t('order_pay_now_btn', params), equals('Pay Now ¥99.00'));
      expect(i18n.t('conn_failed_prefix', params), equals('Connection failed: 逾時'));

      i18n.setLanguage(AppLanguage.ja);
      expect(i18n.t('order_conflict_action_hint', params), contains('【旗艦年付套餐】'));
      expect(i18n.t('order_pay_now_btn', params), equals('今すぐ支払う ¥99.00'));
      expect(i18n.t('conn_failed_prefix', params), equals('接続に失敗しました: 逾時'));
    });
  });
}
