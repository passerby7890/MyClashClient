// test/payment_callback_simulation_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flclash_v2board_client/business/shop/order_model.dart';
import 'package:flclash_v2board_client/business/shop/payment_method_model.dart';
import 'package:flclash_v2board_client/business/shop/shop_manager.dart';
import 'package:flclash_v2board_client/core/i18n/i18n_service.dart';
import 'package:flclash_v2board_client/core/network/dio_client.dart';
import 'package:flclash_v2board_client/infrastructure/config/app_config_service.dart';
import 'package:flclash_v2board_client/presentation/shop/order_payment_screen.dart';

/// 模擬 ShopManager，用於精確控制訂單回調狀態
class MockShopManager extends ShopManager {
  int simulatedStatus = 0; // 0: 待支付, 3: 已完成, 1: 開通中
  int checkCount = 0;

  MockShopManager() : super(dioClient: DioClient(configService: AppConfigService()));

  @override
  Future<OrderModel> getOrderDetail(String tradeNo) async {
    return OrderModel(
      tradeNo: tradeNo,
      planId: 1,
      planName: '測試用勿拍(用完再買)',
      totalAmount: 100, // ¥1.00
      status: simulatedStatus,
      createdAt: 1730456479,
    );
  }

  @override
  Future<List<PaymentMethodModel>> fetchPaymentMethods() async {
    return [
      PaymentMethodModel(id: 1, name: '支付宝', payment: 'alipay', icon: 'alipay'),
      PaymentMethodModel(id: 2, name: '微信', payment: 'wechat', icon: 'wechat'),
    ];
  }

  @override
  List<PaymentMethodModel> get paymentMethods => [
    PaymentMethodModel(id: 1, name: '支付宝', payment: 'alipay', icon: 'alipay'),
    PaymentMethodModel(id: 2, name: '微信', payment: 'wechat', icon: 'wechat'),
  ];

  @override
  Future<int> checkOrderStatus(String tradeNo) async {
    checkCount++;
    return simulatedStatus;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Windows 支付完成後自動回調與主動輪詢跳轉測試 (Payment Callback & Polling Tests)', () {
    late MockShopManager mockShopManager;

    setUp(() {
      mockShopManager = MockShopManager();
      I18nService.instance.setLanguage(AppLanguage.zhTW);
    });

    testWidgets('1. 支付介面載入時正確顯示待支付狀態與支付方式', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OrderPaymentScreen(
            tradeNo: '2026110118111904112143709',
            shopManager: mockShopManager,
          ),
        ),
      );

      await tester.pumpAndSettle();

      final i18n = I18nService.instance;
      expect(find.text(i18n.t('order_payment_title')), findsOneWidget);
      expect(find.text('2026110118111904112143709'), findsOneWidget);
      expect(find.text(i18n.t('order_status_pending')), findsOneWidget);
      expect(find.text('支付宝'), findsOneWidget);
      expect(find.text('微信'), findsOneWidget);
      expect(find.text(i18n.t('order_cancel_this_order')), findsOneWidget);
    });

    testWidgets('2. 模擬用戶外部支付完成切回 App (Lifecycle Resumed) 觸發主動驗證回調成功', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OrderPaymentScreen(
            tradeNo: '2026110118111904112143709',
            shopManager: mockShopManager,
          ),
        ),
      );

      await tester.pumpAndSettle();
      final i18n = I18nService.instance;
      expect(find.text(i18n.t('order_status_pending')), findsOneWidget);

      // 用戶在外部瀏覽器/支付寶付款成功，後端狀態變更為 3 (已完成)
      mockShopManager.simulatedStatus = 3;

      // 模擬切回前台 (AppLifecycleState.resumed)
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // 驗證已成功彈出支付成功對話框
      expect(find.text(i18n.t('order_paid_success_title')), findsOneWidget);

      // 讓自動關閉的 Timer 走完
      await tester.pump(const Duration(seconds: 3));
    });
  });
}
