// test/ui_workflow_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flclash_v2board_client/core/i18n/i18n_service.dart';
import 'package:flclash_v2board_client/core/theme/app_theme.dart';
import 'package:flclash_v2board_client/business/auth/user_model.dart';
import 'package:flclash_v2board_client/presentation/dashboard/widgets/traffic_card.dart';
import 'package:flclash_v2board_client/presentation/dashboard/widgets/connection_button.dart';
import 'package:flclash_v2board_client/infrastructure/core_daemon/core_state.dart';
import 'package:flclash_v2board_client/infrastructure/core_daemon/traffic_stats.dart';

void main() {
  group('UI 介面核心組件互動與渲染驗收測試', () {
    setUp(() {
      I18nService.instance.switchLanguage('zh_TW');
    });

    testWidgets('1. TrafficCard: 正常、流量耗盡與過期警示渲染驗證', (tester) async {
      // 正常用戶 (剩餘 70 GB)
      final normalUser = UserModel(
        email: 'user@test.com',
        transferEnable: 100 * 1024 * 1024 * 1024,
        u: 10 * 1024 * 1024 * 1024,
        d: 20 * 1024 * 1024 * 1024,
        expiredAt: DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000,
        planId: 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: TrafficCard(user: normalUser),
          ),
        ),
      );

      expect(find.text('流量與服務狀態'), findsOneWidget);
      expect(find.text('服務正常'), findsOneWidget);
      expect(find.text('剩餘可用流量'), findsOneWidget);
      expect(find.text('70.00 GB'), findsOneWidget);

      // 過期用戶
      final expiredUser = UserModel(
        email: 'expired@test.com',
        transferEnable: 100 * 1024 * 1024 * 1024,
        u: 0,
        d: 0,
        expiredAt: DateTime.now().subtract(const Duration(days: 5)).millisecondsSinceEpoch ~/ 1000,
        planId: 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: TrafficCard(
              user: expiredUser,
              onRenewTap: () {},
            ),
          ),
        ),
      );

      find.byType(Text).evaluate().forEach((e) => print('RENDERED TEXT: ${(e.widget as Text).data}'));
      expect(find.text('已到期'), findsOneWidget);
      expect(find.text('您的會員套餐已逾期，代理連線已暫停。'), findsOneWidget);
      expect(find.text('立即續費 >'), findsOneWidget);

      // 流量耗盡用戶
      final depletedUser = UserModel(
        email: 'depleted@test.com',
        transferEnable: 100 * 1024 * 1024 * 1024,
        u: 50 * 1024 * 1024 * 1024,
        d: 50 * 1024 * 1024 * 1024,
        expiredAt: DateTime.now().add(const Duration(days: 10)).millisecondsSinceEpoch ~/ 1000,
        planId: 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: TrafficCard(user: depletedUser),
          ),
        ),
      );

      expect(find.text(I18nService.instance.t('traffic_warning_exhausted')), findsWidgets);
    });

    testWidgets('2. ConnectionButton: 連線狀態切換、上下行即時速率與帳號阻斷渲染驗證', (tester) async {
      // 1. 測試 未連線 狀態
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: ConnectionButton(
              coreState: CoreState.disconnected(),
              trafficStats: const TrafficStats(),
              isAccountValid: true,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text(I18nService.instance.t('status_disconnected')), findsOneWidget);
      expect(find.text(I18nService.instance.t('btn_traffic_encrypted')), findsOneWidget);

      // 2. 測試 連線中 狀態
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: ConnectionButton(
              coreState: CoreState.connecting(),
              trafficStats: const TrafficStats(),
              isAccountValid: true,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text(I18nService.instance.t('status_connecting')), findsOneWidget);

      // 3. 測試 已連線 狀態 (具備上下行速率)
      const activeTraffic = TrafficStats(
        upSpeed: 1024 * 1024 * 5, // 5 MB/s
        downSpeed: 1024 * 1024 * 15, // 15 MB/s
        totalUp: 100 * 1024 * 1024,
        totalDown: 500 * 1024 * 1024,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: ConnectionButton(
              coreState: CoreState.connected(nodeName: '香港 01 [VIP 專線]'),
              trafficStats: activeTraffic,
              isAccountValid: true,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text(I18nService.instance.t('protected_vpn')), findsOneWidget);
      expect(find.text('5.00 MB/s'), findsOneWidget);
      expect(find.text('15.00 MB/s'), findsOneWidget);

      // 4. 測試 帳號過期/不可用 狀態
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: ConnectionButton(
              coreState: CoreState.disconnected(),
              trafficStats: const TrafficStats(),
              isAccountValid: false,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text(I18nService.instance.t('btn_account_invalid')), findsOneWidget);
    });
  });
}
