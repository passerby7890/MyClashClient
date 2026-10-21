// lib/presentation/profile/traffic_detail_screen.dart

import 'package:flutter/material.dart';
import '../../business/auth/auth_manager.dart';
import '../desktop/desktop_traffic_view.dart';
import '../desktop/desktop_theme_tokens.dart';

/// 流量詳情頁面 (TrafficDetailScreen)
/// 直接複用專職 DesktopTrafficView 規格：190px 大圓環 + 2x2 指標矩陣 + 真實 API 流量明細
class TrafficDetailScreen extends StatelessWidget {
  final AuthManager authManager;

  const TrafficDetailScreen({
    super.key,
    required this.authManager,
  });

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: DesktopThemeTokens.bgDeep,
      appBar: canPop
          ? AppBar(
              backgroundColor: DesktopThemeTokens.cardBg,
              elevation: 0,
              title: const Text(
                '流量明細與使用分析',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Container(
                  color: DesktopThemeTokens.borderColor,
                  height: 1,
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: DesktopTrafficView(authManager: authManager),
      ),
    );
  }
}
