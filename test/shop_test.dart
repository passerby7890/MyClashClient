// test/shop_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:flclash_v2board_client/business/shop/order_model.dart';
import 'package:flclash_v2board_client/business/shop/payment_method_model.dart';
import 'package:flclash_v2board_client/business/shop/plan_model.dart';

void main() {
  group('階段六：套餐商店與訂單模型單元測試', () {
    test('1. PlanModel 解析與價格特徵轉換測試', () {
      final json = {
        'id': 3,
        'name': '专业套餐',
        'transfer_enable': 3500,
        'month_price': 9800,
        'year_price': 85800,
        'content': '[{"feature": "每月 3500G 流量，6折重置", "support": true}, {"feature": "全球51个节点接入", "support": true}]',
        'show': 1,
      };

      final plan = PlanModel.fromJson(json);

      expect(plan.id, equals(3));
      expect(plan.name, equals('专业套餐'));
      expect(plan.transferEnable, equals(3500));
      expect(plan.displayPrice, equals(98.0));
      expect(plan.formattedDisplayPrice, equals('¥98.00'));
      expect(plan.features.length, equals(2));
      expect(plan.features[0], equals('每月 3500G 流量，6折重置'));
      expect(plan.show, isTrue);
    });

    test('2. OrderModel 訂單解析與狀態金額測試', () {
      final json = {
        'trade_no': '2026101215102451387274797',
        'plan_id': 3,
        'total_amount': 9800,
        'status': 0,
        'created_at': 1791791854,
        'plan': {
          'id': 3,
          'name': '专业套餐',
        },
      };

      final order = OrderModel.fromJson(json);

      expect(order.tradeNo, equals('2026101215102451387274797'));
      expect(order.planName, equals('专业套餐'));
      expect(order.amountYuan, equals(98.0));
      expect(order.formattedAmount, equals('¥98.00'));
      expect(order.isPending, isTrue);
      expect(order.statusText, equals('待支付'));
      expect(order.createdAtFormatted, isNotEmpty);
    });

    test('3. PaymentMethodModel 支付方式解析測試', () {
      final json = {
        'id': 2,
        'name': '支付宝',
        'payment': 'EPay',
      };

      final method = PaymentMethodModel.fromJson(json);

      expect(method.id, equals(2));
      expect(method.name, equals('支付宝'));
      expect(method.payment, equals('EPay'));
    });

    test('4. UserModel 與 Plan 對應名稱動態解析測試', () {
      final plans = [
        PlanModel.fromJson({
          'id': 5,
          'name': '尊享專線套餐',
          'transfer_enable': 5000,
          'month_price': 15800,
          'show': 1,
        }),
      ];

      const userPlanId = 5;
      final matched = plans.where((p) => p.id == userPlanId).firstOrNull;
      expect(matched, isNotNull);
      expect(matched!.name, equals('尊享專線套餐'));
    });

    test('5. PlanModel 多週期 availablePeriods 解析測試', () {
      final plan = PlanModel.fromJson({
        'id': 1,
        'name': '多週期套餐',
        'transfer_enable': 200,
        'month_price': 3600,
        'quarter_price': 9800,
        'year_price': 32800,
      });

      final periods = plan.availablePeriods;
      expect(periods.length, equals(3));
      expect(periods[0].key, equals('month_price'));
      expect(periods[0].label, equals('月付'));
      expect(periods[0].formattedPrice, equals('¥36.00'));

      expect(periods[1].key, equals('quarter_price'));
      expect(periods[1].label, equals('季付'));
      expect(periods[1].formattedPrice, equals('¥98.00'));

      expect(periods[2].key, equals('year_price'));
      expect(periods[2].label, equals('年付'));
      expect(periods[2].formattedPrice, equals('¥328.00'));
    });
  });
}
