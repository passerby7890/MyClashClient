// lib/presentation/desktop/desktop_theme_tokens.dart

import 'package:flutter/material.dart';

/// 桌面端專屬設計規範 (DesktopThemeTokens)
/// 統一規定桌面版 1200 x 780 解析度下的調色盤、字型標準、圓角與間距規格
class DesktopThemeTokens {
  DesktopThemeTokens._();

  // ══════════════════════════════════════════════
  // 深色深海科技調色盤 (Dark Deep Tech Palette)
  // ══════════════════════════════════════════════
  static const Color bgDeep = Color(0xFF070A11);       // 應用程式深邃底色
  static const Color sidebarBg = Color(0xFF0D1424);     // 左側導覽列背景
  static const Color cardBg = Color(0xFF0F1728);        // 一級卡片背景
  static const Color cardInnerBg = Color(0xFF0A0F1D);   // 二級內嵌卡片/輸入框背景
  static const Color borderColor = Color(0xFF1E293B);   // 邊框線條 (Slate 800)
  static const Color borderSubtle = Color(0xFF151F32);  // 極細微分割線

  // 科技亮色與高光點綴 (Accents & Highlights)
  static const Color neonCyan = Color(0xFF00D2FF);      // 核心霓虹青
  static const Color neonBlue = Color(0xFF0EA5E9);      // 科技湛藍 (Sky 500)
  static const Color emeraldGreen = Color(0xFF10B981);  // 連線成功/正常綠 (Emerald 500)
  static const Color amberWarn = Color(0xFFF59E0B);     // 警示暖橘 (Amber 500)
  static const Color roseRed = Color(0xFFF43F5E);       // 錯誤/中斷玫瑰紅 (Rose 500)
  static const Color purpleAccent = Color(0xFF8B5CF6);  // 尊貴紫 (Violet 500)

  // 便捷語義別名 (Semantic Aliases)
  static const Color bgCanvas = bgDeep;
  static const Color sidebarSurface = sidebarBg;
  static const Color cardSurface = cardBg;
  static const Color cardInnerSurface = cardInnerBg;
  static const Color borderMuted = borderColor;
  static const Color accentCyan = neonCyan;
  static const Color successColor = emeraldGreen;
  static const Color accentSuccess = emeraldGreen;
  static const Color dangerColor = roseRed;
  static const Color warningColor = amberWarn;

  // 文字調色盤
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFE2E8F0);
  static const Color textMuted = Color(0xFF94A3B8);     // 次要資訊灰 (Slate 400)
  static const Color textDim = Color(0xFF64748B);       // 停用/輔助文字 (Slate 500)

  // 漸層常數
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [neonCyan, Color(0xFF0284C7)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient emeraldGradient = LinearGradient(
    colors: [Color(0xFF34D399), emeraldGreen],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient warningGradient = LinearGradient(
    colors: [Color(0xFFFBBF24), amberWarn],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGlowGradient = LinearGradient(
    colors: [Color(0x1A00D2FF), Colors.transparent],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // ══════════════════════════════════════════════
  // 字型排版階層規範 (Typography Hierarchy)
  // ══════════════════════════════════════════════
  static const TextStyle titleStyle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
    color: textPrimary,
    letterSpacing: -0.2,
  );

  static const TextStyle statValueStyle = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    color: textPrimary,
    fontFamily: 'Segoe UI',
    letterSpacing: -0.5,
  );

  static const TextStyle subtitleStyle = TextStyle(
    fontSize: 13,
    color: textMuted,
    fontWeight: FontWeight.normal,
  );

  static const TextStyle bodyStyle = TextStyle(
    fontSize: 14,
    color: textSecondary,
    fontWeight: FontWeight.normal,
  );

  static const TextStyle labelStyle = TextStyle(
    fontSize: 12,
    color: textMuted,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle badgeStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
  );

  // ══════════════════════════════════════════════
  // 佈局尺寸與邊距 (Layout Dimensions & Spacing)
  // ══════════════════════════════════════════════
  static const double sidebarWidth = 210.0;
  static const double headerHeight = 64.0;
  static const double cardRadius = 16.0;
  static const double cardPadding = 16.0;
  static const double spacing = 16.0;

  // 4 國語言標準選單
  static const List<Map<String, String>> supportedLanguages = [
    {'code': 'zh_TW', 'label': '🇹🇼 繁體中文', 'name': '🇹🇼 繁體中文'},
    {'code': 'zh_CN', 'label': '🇨🇳 简体中文', 'name': '🇨🇳 简体中文'},
    {'code': 'en', 'label': '🇺🇸 English', 'name': '🇺🇸 English'},
    {'code': 'ja', 'label': '🇯🇵 日本語', 'name': '🇯🇵 日本語'},
  ];
}
