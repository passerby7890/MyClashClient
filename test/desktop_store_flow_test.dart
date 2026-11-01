// test/desktop_store_flow_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flclash_v2board_client/business/shop/order_model.dart';
import 'package:flclash_v2board_client/business/shop/plan_model.dart';
import 'package:flclash_v2board_client/business/shop/shop_manager.dart';
import 'package:flclash_v2board_client/core/i18n/i18n_service.dart';
import 'package:flclash_v2board_client/core/network/dio_client.dart';
import 'package:flclash_v2board_client/infrastructure/config/app_config_service.dart';
import 'package:flclash_v2board_client/presentation/desktop/desktop_store_view.dart';

class MockDesktopShopManager extends ShopManager {
  OrderModel? pendingOrder;
  int cancelCallCount = 0;

  MockDesktopShopManager() : super(dioClient: DioClient(configService: AppConfigService()));

  @override
  Future<List<PlanModel>> fetchPlans() async {
    return [
      PlanModel(
        id: 1,
        name: '基礎極速套餐',
        transferEnable: 150,
        monthPrice: 1500,
        features: ['高速跨境專線'],
      ),
      PlanModel(
        id: 2,
        name: '標準暢遊套餐',
        transferEnable: 350,
        monthPrice: 2800,
        features: ['4K/8K 串流解鎖'],
      ),
    ];
  }

  @override
  List<PlanModel> get plans => [
    PlanModel(
      id: 1,
      name: '基礎極速套餐',
      transferEnable: 150,
      monthPrice: 1500,
      features: ['高速跨境專線'],
    ),
    PlanModel(
      id: 2,
      name: '標準暢遊套餐',
      transferEnable: 350,
      monthPrice: 2800,
      features: ['4K/8K 串流解鎖'],
    ),
  ];

  @override
  Future<List<OrderModel>> fetchOrders() async {
    if (pendingOrder != null) {
      return [pendingOrder!];
    }
    return [];
  }

  @override
  Future<bool> cancelOrder(String tradeNo) async {
    cancelCallCount++;
    pendingOrder = null;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('桌面版專屬商城橫幅與未付款衝突測試 (Desktop Store Flow Tests)', () {
    late MockDesktopShopManager mockShopManager;

    setUp(() {
      mockShopManager = MockDesktopShopManager();
      I18nService.instance.setLanguage(AppLanguage.zhTW);
    });

    testWidgets('1. 當有未付款訂單時，桌面商城頂部顯示金色警示橫幅', (WidgetTester tester) async {
      mockShopManager.pendingOrder = OrderModel(
        tradeNo: '20261101999999',
        planId: 1,
        planName: '基礎極速套餐',
        totalAmount: 1500,
        status: 0,
        createdAt: 1730456479,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopStoreView(shopManager: mockShopManager),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final i18n = I18nService.instance;
      expect(find.text(i18n.t('order_pending_banner_title')), findsOneWidget);
      expect(find.text(i18n.t('order_pending_banner_pay')), findsOneWidget);
      expect(find.text(i18n.t('order_pending_banner_cancel')), findsOneWidget);
    });

    testWidgets('2. 點擊橫幅上的「取消」彈出確認對話框並成功取消', (WidgetTester tester) async {
      mockShopManager.pendingOrder = OrderModel(
        tradeNo: '20261101999999',
        planId: 1,
        planName: '基礎極速套餐',
        totalAmount: 1500,
        status: 0,
        createdAt: 1730456479,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopStoreView(shopManager: mockShopManager),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final i18n = I18nService.instance;
      // 點擊橫幅取消按鈕
      await tester.tap(find.text(i18n.t('order_pending_banner_cancel')));
      await tester.pumpAndSettle();

      // 驗證彈出對話框
      expect(find.text(i18n.t('order_pending_banner_cancel_title')), findsOneWidget);
      expect(find.text(i18n.t('order_pending_banner_confirm_cancel')), findsOneWidget);

      // 點擊確認取消
      await tester.tap(find.text(i18n.t('order_pending_banner_confirm_cancel')));
      await tester.pumpAndSettle();

      expect(mockShopManager.cancelCallCount, equals(1));
    });
  });
}
