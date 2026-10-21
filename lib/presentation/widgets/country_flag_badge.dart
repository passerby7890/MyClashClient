// lib/presentation/widgets/country_flag_badge.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../business/subscription/node_model.dart';

/// Windows 專屬彩色國旗向量繪製器 (CountryFlagBadge)
/// 解決 Windows 10/11 系統字型缺乏彩色國旗 Emoji、退化呈現為「US us」/「JP jp」等英文字母的瑕疵。
/// 支援全球主流國家國旗精準幾何繪製，未收錄國家則呈現科技金屬風 ISO 雙碼徽章。
class CountryFlagBadge extends StatelessWidget {
  final String? isoCode;
  final String? flagEmoji;
  final NodeModel? node;
  final Size size;
  final double borderRadius;
  final bool showBorder;

  const CountryFlagBadge({
    super.key,
    this.isoCode,
    this.flagEmoji,
    this.node,
    this.size = const Size(24, 16),
    this.borderRadius = 3.0,
    this.showBorder = true,
  });

  String get effectiveIsoCode {
    if (isoCode != null && isoCode!.trim().isNotEmpty) {
      return isoCode!.trim().toUpperCase();
    }
    if (node != null) {
      return node!.countryCode.toUpperCase();
    }
    if (flagEmoji != null && flagEmoji!.isNotEmpty) {
      final fromEmoji = NodeModel.emojiToIsoCode(flagEmoji!);
      if (fromEmoji != null) return fromEmoji.toUpperCase();
    }
    return 'HK';
  }

  @override
  Widget build(BuildContext context) {
    final code = effectiveIsoCode;

    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        border: showBorder
            ? Border.all(
                color: Colors.white.withOpacity(0.20),
                width: 0.8,
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: CustomPaint(
          size: size,
          painter: _VectorFlagPainter(code),
        ),
      ),
    );
  }
}

/// 國旗向量繪製器
class _VectorFlagPainter extends CustomPainter {
  final String code;

  _VectorFlagPainter(this.code);

  @override
  void paint(Canvas canvas, Size size) {
    switch (code) {
      case 'JP':
        _drawJapan(canvas, size);
        break;
      case 'US':
        _drawUSA(canvas, size);
        break;
      case 'HK':
        _drawHongKong(canvas, size);
        break;
      case 'TW':
        _drawTaiwan(canvas, size);
        break;
      case 'SG':
        _drawSingapore(canvas, size);
        break;
      case 'KR':
        _drawSouthKorea(canvas, size);
        break;
      case 'GB':
      case 'UK':
        _drawUnitedKingdom(canvas, size);
        break;
      case 'DE':
        _drawGermany(canvas, size);
        break;
      case 'FR':
        _drawFrance(canvas, size);
        break;
      case 'IE':
        _drawIreland(canvas, size);
        break;
      case 'NL':
        _drawNetherlands(canvas, size);
        break;
      case 'RU':
        _drawRussia(canvas, size);
        break;
      case 'IT':
        _drawItaly(canvas, size);
        break;
      case 'ES':
        _drawSpain(canvas, size);
        break;
      case 'CA':
        _drawCanada(canvas, size);
        break;
      case 'AU':
        _drawAustralia(canvas, size);
        break;
      case 'UA':
        _drawUkraine(canvas, size);
        break;
      case 'SE':
        _drawSweden(canvas, size);
        break;
      case 'CH':
        _drawSwitzerland(canvas, size);
        break;
      case 'IN':
        _drawIndia(canvas, size);
        break;
      case 'VN':
        _drawVietnam(canvas, size);
        break;
      case 'TH':
        _drawThailand(canvas, size);
        break;
      case 'MY':
        _drawMalaysia(canvas, size);
        break;
      case 'PH':
        _drawPhilippines(canvas, size);
        break;
      case 'BR':
        _drawBrazil(canvas, size);
        break;
      case 'TR':
        _drawTurkey(canvas, size);
        break;
      case 'CN':
        _drawChina(canvas, size);
        break;
      default:
        _drawGenericIsoBadge(canvas, size, code);
        break;
    }
  }

  // 1. 日本國旗 (純白底 + 正中央赤日圓)
  void _drawJapan(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.height * 0.30;
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFFBC002D));
  }

  // 2. 美國國旗 (紅白13道條紋 + 左上深藍星區)
  void _drawUSA(Canvas canvas, Size size) {
    final stripeH = size.height / 7.0; // 簡化為7條可見度高條紋
    for (int i = 0; i < 7; i++) {
      final color = (i % 2 == 0) ? const Color(0xFFB22234) : Colors.white;
      canvas.drawRect(
        Rect.fromLTWH(0, i * stripeH, size.width, stripeH),
        Paint()..color = color,
      );
    }
    // 左上深藍星區
    final cantonW = size.width * 0.44;
    final cantonH = stripeH * 4;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, cantonW, cantonH),
      Paint()..color = const Color(0xFF3C3B6E),
    );
    // 星星矩陣亮點
    final dotPaint = Paint()..color = Colors.white;
    for (int r = 1; r <= 3; r++) {
      for (int c = 1; c <= 3; c++) {
        canvas.drawCircle(
          Offset(cantonW * (c / 4.0), cantonH * (r / 4.0)),
          0.8,
          dotPaint,
        );
      }
    }
  }

  // 3. 香港特別行政區區旗 (深紅底 + 幾何白色紫荊花瓣)
  void _drawHongKong(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFDE2910));
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.height * 0.28;
    final flowerPaint = Paint()..color = Colors.white;

    // 繪製五瓣紫荊花
    for (int i = 0; i < 5; i++) {
      final angle = (i * 72.0 - 90.0) * math.pi / 180.0;
      final p = Offset(center.dx + r * 0.65 * math.cos(angle), center.dy + r * 0.65 * math.sin(angle));
      canvas.drawCircle(p, r * 0.35, flowerPaint);
    }
    canvas.drawCircle(center, r * 0.3, flowerPaint);
  }

  // 4. 台灣旗幟 (紅底 + 左上青天白日)
  void _drawTaiwan(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFE0000));
    final cantonW = size.width * 0.50;
    final cantonH = size.height * 0.50;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, cantonW, cantonH),
      Paint()..color = const Color(0xFF000095),
    );
    // 白日
    final center = Offset(cantonW / 2, cantonH / 2);
    final sunR = cantonH * 0.30;
    canvas.drawCircle(center, sunR, Paint()..color = Colors.white);
    canvas.drawCircle(center, sunR * 0.65, Paint()..color = const Color(0xFF000095));
    canvas.drawCircle(center, sunR * 0.50, Paint()..color = Colors.white);
  }

  // 5. 新加坡國旗 (上紅下白 + 左上白色星月)
  void _drawSingapore(Canvas canvas, Size size) {
    final halfH = size.height / 2;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, halfH), Paint()..color = const Color(0xFFED2939));
    canvas.drawRect(Rect.fromLTWH(0, halfH, size.width, halfH), Paint()..color = Colors.white);
    // 月牙與星星
    final moonCenter = Offset(size.width * 0.20, halfH * 0.5);
    final r = halfH * 0.35;
    canvas.drawCircle(moonCenter, r, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(moonCenter.dx + r * 0.45, moonCenter.dy), r * 0.85, Paint()..color = const Color(0xFFED2939));
    // 5 星點
    final starPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(moonCenter.dx + r * 0.9, moonCenter.dy), 0.9, starPaint);
  }

  // 6. 韓國國旗 (白底 + 太極圓)
  void _drawSouthKorea(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.height * 0.28;
    // 上紅下藍半圓
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      math.pi,
      math.pi,
      true,
      Paint()..color = const Color(0xFFCD2E3A),
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      0,
      math.pi,
      true,
      Paint()..color = const Color(0xFF0047A0),
    );
    // 4 卦微型條紋
    final barPaint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(size.width * 0.15, size.height * 0.2), Offset(size.width * 0.25, size.height * 0.3), barPaint);
    canvas.drawLine(Offset(size.width * 0.75, size.height * 0.7), Offset(size.width * 0.85, size.height * 0.8), barPaint);
  }

  // 7. 英國國旗 (米字旗 Union Jack)
  void _drawUnitedKingdom(Canvas canvas, Size size) {
    // 藍底
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF012169));
    // 白色對角粗線
    final diagWhite = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.5;
    canvas.drawLine(Offset.zero, Offset(size.width, size.height), diagWhite);
    canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), diagWhite);
    // 紅色對角細線
    final diagRed = Paint()
      ..color = const Color(0xFFC8102E)
      ..strokeWidth = 1.6;
    canvas.drawLine(Offset.zero, Offset(size.width, size.height), diagRed);
    canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), diagRed);
    // 白色正十字
    final crossWhite = Paint()
      ..color = Colors.white
      ..strokeWidth = 5.0;
    canvas.drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, size.height), crossWhite);
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), crossWhite);
    // 紅色正十字
    final crossRed = Paint()
      ..color = const Color(0xFFC8102E)
      ..strokeWidth = 3.0;
    canvas.drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, size.height), crossRed);
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), crossRed);
  }

  // 8. 德國國旗 (黑紅金橫三色)
  void _drawGermany(Canvas canvas, Size size) {
    final h = size.height / 3;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, h), Paint()..color = const Color(0xFF000000));
    canvas.drawRect(Rect.fromLTWH(0, h, size.width, h), Paint()..color = const Color(0xFFDD0000));
    canvas.drawRect(Rect.fromLTWH(0, h * 2, size.width, h), Paint()..color = const Color(0xFFFFCE00));
  }

  // 9. 法國國旗 (藍白紅豎三色)
  void _drawFrance(Canvas canvas, Size size) {
    final w = size.width / 3;
    canvas.drawRect(Rect.fromLTWH(0, 0, w, size.height), Paint()..color = const Color(0xFF002654));
    canvas.drawRect(Rect.fromLTWH(w, 0, w, size.height), Paint()..color = Colors.white);
    canvas.drawRect(Rect.fromLTWH(w * 2, 0, w, size.height), Paint()..color = const Color(0xFFED2939));
  }

  // 10. 愛爾蘭國旗 (綠白橙豎三色)
  void _drawIreland(Canvas canvas, Size size) {
    final w = size.width / 3;
    canvas.drawRect(Rect.fromLTWH(0, 0, w, size.height), Paint()..color = const Color(0xFF169B62));
    canvas.drawRect(Rect.fromLTWH(w, 0, w, size.height), Paint()..color = Colors.white);
    canvas.drawRect(Rect.fromLTWH(w * 2, 0, w, size.height), Paint()..color = const Color(0xFFFF883E));
  }

  // 11. 荷蘭國旗 (紅白藍橫三色)
  void _drawNetherlands(Canvas canvas, Size size) {
    final h = size.height / 3;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, h), Paint()..color = const Color(0xFFAE1C28));
    canvas.drawRect(Rect.fromLTWH(0, h, size.width, h), Paint()..color = Colors.white);
    canvas.drawRect(Rect.fromLTWH(0, h * 2, size.width, h), Paint()..color = const Color(0xFF21468B));
  }

  // 12. 俄羅斯國旗 (白藍紅橫三色)
  void _drawRussia(Canvas canvas, Size size) {
    final h = size.height / 3;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, h), Paint()..color = Colors.white);
    canvas.drawRect(Rect.fromLTWH(0, h, size.width, h), Paint()..color = const Color(0xFF0039A6));
    canvas.drawRect(Rect.fromLTWH(0, h * 2, size.width, h), Paint()..color = const Color(0xFFD52B1E));
  }

  // 13. 義大利國旗 (綠白紅豎三色)
  void _drawItaly(Canvas canvas, Size size) {
    final w = size.width / 3;
    canvas.drawRect(Rect.fromLTWH(0, 0, w, size.height), Paint()..color = const Color(0xFF009246));
    canvas.drawRect(Rect.fromLTWH(w, 0, w, size.height), Paint()..color = Colors.white);
    canvas.drawRect(Rect.fromLTWH(w * 2, 0, w, size.height), Paint()..color = const Color(0xFFCE2B37));
  }

  // 14. 西班牙國旗 (紅黃紅白橫條)
  void _drawSpain(Canvas canvas, Size size) {
    final h4 = size.height / 4;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, h4), Paint()..color = const Color(0xFFAA151B));
    canvas.drawRect(Rect.fromLTWH(0, h4, size.width, h4 * 2), Paint()..color = const Color(0xFFF1BF00));
    canvas.drawRect(Rect.fromLTWH(0, h4 * 3, size.width, h4), Paint()..color = const Color(0xFFAA151B));
  }

  // 15. 加拿大國旗 (紅白紅兩側寬紅邊)
  void _drawCanada(Canvas canvas, Size size) {
    final barW = size.width * 0.25;
    canvas.drawRect(Rect.fromLTWH(0, 0, barW, size.height), Paint()..color = const Color(0xFFFF0000));
    canvas.drawRect(Rect.fromLTWH(barW, 0, size.width - barW * 2, size.height), Paint()..color = Colors.white);
    canvas.drawRect(Rect.fromLTWH(size.width - barW, 0, barW, size.height), Paint()..color = const Color(0xFFFF0000));
    // 楓葉點
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(center, size.height * 0.22, Paint()..color = const Color(0xFFFF0000));
  }

  // 16. 澳洲國旗 (深藍底 + 左上米字旗 + 南十字星)
  void _drawAustralia(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF00008B));
    final cantonW = size.width * 0.48;
    final cantonH = size.height * 0.50;
    _drawUnitedKingdom(canvas, Size(cantonW, cantonH));
    // 南十字星亮點
    final starPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(size.width * 0.78, size.height * 0.35), 0.9, starPaint);
    canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.55), 0.9, starPaint);
    canvas.drawCircle(Offset(size.width * 0.75, size.height * 0.70), 0.9, starPaint);
    canvas.drawCircle(Offset(size.width * 0.65, size.height * 0.55), 0.9, starPaint);
  }

  // 17. 烏克蘭國旗 (藍黃橫雙色)
  void _drawUkraine(Canvas canvas, Size size) {
    final halfH = size.height / 2;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, halfH), Paint()..color = const Color(0xFF0057B7));
    canvas.drawRect(Rect.fromLTWH(0, halfH, size.width, halfH), Paint()..color = const Color(0xFFFFDD00));
  }

  // 18. 瑞典國旗 (藍底金十字)
  void _drawSweden(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF006AA7));
    final crossPaint = Paint()
      ..color = const Color(0xFFFECC00)
      ..strokeWidth = 3.5;
    canvas.drawLine(Offset(size.width * 0.35, 0), Offset(size.width * 0.35, size.height), crossPaint);
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), crossPaint);
  }

  // 19. 瑞士國旗 (紅底正白十字)
  void _drawSwitzerland(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFF0000));
    final crossPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.5;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final arm = size.height * 0.28;
    canvas.drawLine(Offset(cx, cy - arm), Offset(cx, cy + arm), crossPaint);
    canvas.drawLine(Offset(cx - arm, cy), Offset(cx + arm, cy), crossPaint);
  }

  // 20. 印度國旗 (橙白綠橫三色)
  void _drawIndia(Canvas canvas, Size size) {
    final h = size.height / 3;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, h), Paint()..color = const Color(0xFFFF9933));
    canvas.drawRect(Rect.fromLTWH(0, h, size.width, h), Paint()..color = Colors.white);
    canvas.drawRect(Rect.fromLTWH(0, h * 2, size.width, h), Paint()..color = const Color(0xFF138808));
    // 藍色輪
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), h * 0.35, Paint()..color = const Color(0xFF000080));
  }

  // 21. 越南國旗 (紅底金星)
  void _drawVietnam(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFDA251D));
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), size.height * 0.26, Paint()..color = const Color(0xFFFFFF00));
  }

  // 22. 泰國國旗 (紅紅白白藍)
  void _drawThailand(Canvas canvas, Size size) {
    final h6 = size.height / 6;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, h6), Paint()..color = const Color(0xFFA51931));
    canvas.drawRect(Rect.fromLTWH(0, h6, size.width, h6), Paint()..color = Colors.white);
    canvas.drawRect(Rect.fromLTWH(0, h6 * 2, size.width, h6 * 2), Paint()..color = const Color(0xFF2D2A4A));
    canvas.drawRect(Rect.fromLTWH(0, h6 * 4, size.width, h6), Paint()..color = Colors.white);
    canvas.drawRect(Rect.fromLTWH(0, h6 * 5, size.width, h6), Paint()..color = const Color(0xFFA51931));
  }

  // 23. 馬來西亞國旗 (紅白條紋 + 藍底月星)
  void _drawMalaysia(Canvas canvas, Size size) {
    final stripeH = size.height / 6.0;
    for (int i = 0; i < 6; i++) {
      final color = (i % 2 == 0) ? const Color(0xFFCC0000) : Colors.white;
      canvas.drawRect(Rect.fromLTWH(0, i * stripeH, size.width, stripeH), Paint()..color = color);
    }
    final cantonW = size.width * 0.48;
    final cantonH = stripeH * 3.5;
    canvas.drawRect(Rect.fromLTWH(0, 0, cantonW, cantonH), Paint()..color = const Color(0xFF000066));
    canvas.drawCircle(Offset(cantonW * 0.45, cantonH * 0.5), cantonH * 0.30, Paint()..color = const Color(0xFFFFCC00));
  }

  // 24. 菲律賓國旗 (藍紅白三色)
  void _drawPhilippines(Canvas canvas, Size size) {
    final halfH = size.height / 2;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, halfH), Paint()..color = const Color(0xFF0038A8));
    canvas.drawRect(Rect.fromLTWH(0, halfH, size.width, halfH), Paint()..color = const Color(0xFFCE1126));
    // 左側白三角
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.45, halfH)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(size.width * 0.16, halfH), 2.2, Paint()..color = const Color(0xFFFCD116));
  }

  // 25. 巴西國旗 (綠底黃菱形藍圓)
  void _drawBrazil(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF009739));
    final path = Path()
      ..moveTo(size.width / 2, size.height * 0.15)
      ..lineTo(size.width * 0.88, size.height / 2)
      ..lineTo(size.width / 2, size.height * 0.85)
      ..lineTo(size.width * 0.12, size.height / 2)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFFEDD00));
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), size.height * 0.22, Paint()..color = const Color(0xFF012169));
  }

  // 26. 土耳其國旗 (紅底白星月)
  void _drawTurkey(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFE30A17));
    final center = Offset(size.width * 0.42, size.height / 2);
    final r = size.height * 0.30;
    canvas.drawCircle(center, r, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(center.dx + r * 0.35, center.dy), r * 0.80, Paint()..color = const Color(0xFFE30A17));
    canvas.drawCircle(Offset(center.dx + r * 0.95, center.dy), 1.6, Paint()..color = Colors.white);
  }

  // 27. 中國國旗 (紅底黃大星)
  void _drawChina(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFEE1C25));
    canvas.drawCircle(Offset(size.width * 0.25, size.height * 0.35), size.height * 0.20, Paint()..color = const Color(0xFFFFDE00));
  }

  // 通用/未定義國家科技徽章 (深邃藍底 + 發光大寫 ISO 兩碼代號)
  void _drawGenericIsoBadge(Canvas canvas, Size size, String displayCode) {
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF0F172A), Color(0xFF0284C7)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bgPaint);

    final span = TextSpan(
      text: displayCode.length <= 3 ? displayCode : displayCode.substring(0, 2),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 8.5,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.2,
      ),
    );
    final tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
    )..layout();
    final x = (size.width - tp.width) / 2;
    final y = (size.height - tp.height) / 2;
    tp.paint(canvas, Offset(x, y));
  }

  @override
  bool shouldRepaint(covariant _VectorFlagPainter oldDelegate) {
    return oldDelegate.code != code;
  }
}
