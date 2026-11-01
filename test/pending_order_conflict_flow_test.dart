// test/pending_order_conflict_flow_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flclash_v2board_client/business/shop/order_model.dart';
import 'package:flclash_v2board_client/business/shop/plan_model.dart';
import 'package:flclash_v2board_client/business/shop/shop_manager.dart';
import 'package:flclash_v2board_client/core/i18n/i18n_service.dart';
import 'package:flclash_v2board_client/core/network/dio_client.dart';
import 'package:flclash_v2board_client/infrastructure/config/app_config_service.dart';
import 'package:flclash_v2board_client/presentation/shop/shop_screen.dart';

class MockShopManagerWithPendingOrder extends ShopManager {
  OrderModel? currentPendingOrder;
  int cancelCallCount = 0;
  int createOrderCallCount = 0;

  MockShopManagerWithPendingOrder() : super(dioClient: DioClient(configService: AppConfigService()));

  @override
  Future<List<PlanModel>> fetchPlans() async {
    return [
      PlanModel(
        id: 1,
        name: '测试用勿拍(用完再买)',
        transferEnable: 50,
        onetimePrice: 100, // ¥1.00
        features: ['测试特性1'],
      ),
      PlanModel(
        id: 2,
        name: '基础套餐',
        transferEnable: 210,
        monthPrice: 3600, // ¥36.00
        features: ['基础特性1'],
      ),
    ];
  }

  @override
  List<PlanModel> get plans => [
    PlanModel(
      id: 1,
      name: '测试用勿拍(用完再买)',
      transferEnable: 50,
      onetimePrice: 100,
      features: ['测试特性1'],
    ),
    PlanModel(
      id: 2,
      name: '基础套餐',
      transferEnable: 210,
      monthPrice: 3600,
      features: ['基础特性1'],
    ),
  ];

  @override
  Future<List<OrderModel>> fetchOrders() async {
    if (currentPendingOrder != null) {
      return [currentPendingOrder!];
    }
    return [];
  }

  @override
  Future<String> createOrder({
    required int planId,
    required String period,
    String? couponCode,
  }) async {
    createOrderCallCount++;
    if (currentPendingOrder != null) {
      throw Exception('您有未付款或开通中的订单，请稍后再试或将其取消');
    }
    return '20261101999888';
  }

  @override
  Future<bool> cancelOrder(String tradeNo) async {
    cancelCallCount++;
    currentPendingOrder = null;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Windows 未付款訂單衝突與引導解決流程測試 (Pending Order Conflict Flow Tests)', () {
    late MockShopManagerWithPendingOrder mockShopManager;

    setUp(() {
      mockShopManager = MockShopManagerWithPendingOrder();
      I18nService.instance.setLanguage(AppLanguage.zhTW);
    });

    testWidgets('1. 當用戶有未付款訂單時，商城頂部顯示醒目金色警示橫幅', (WidgetTester tester) async {
      mockShopManager.currentPendingOrder = OrderModel(
        tradeNo: '2026110118111904112143709',
        planId: 1,
        planName: '测试用勿拍(用完再买)',
        totalAmount: 100,
        status: 0,
        createdAt: 1730456479,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ShopScreen(shopManager: mockShopManager),
        ),
      );

      await tester.pumpAndSettle();

      final i18n = I18nService.instance;
      expect(find.text(i18n.t('order_pending_banner_title')), findsOneWidget);
      expect(find.text(i18n.t('order_pending_banner_pay')), findsOneWidget);
      expect(find.text(i18n.t('order_pending_banner_cancel')), findsOneWidget);
    });

    testWidgets('2. 點擊橫幅「取消」按鈕，彈出確認對話框並成功取消訂單', (WidgetTester tester) async {
      mockShopManager.currentPendingOrder = OrderModel(
        tradeNo: '2026110118111904112143709',
        planId: 1,
        planName: '测试用勿拍(用完再买)',
        totalAmount: 100,
        status: 0,
        createdAt: 1730456479,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ShopScreen(shopManager: mockShopManager),
        ),
      );

      await tester.pumpAndSettle();

      final i18n = I18nService.instance;
      await tester.tap(find.text(i18n.t('order_pending_banner_cancel')));
      await tester.pumpAndSettle();

      expect(find.text(i18n.t('order_pending_banner_cancel_title')), findsOneWidget);
      expect(find.text(i18n.t('order_pending_banner_confirm_cancel')), findsOneWidget);

      await tester.tap(find.text(i18n.t('order_pending_banner_confirm_cancel')));
      await tester.pumpAndSettle();

      expect(mockShopManager.cancelCallCount, equals(1));
    });
  });
}
