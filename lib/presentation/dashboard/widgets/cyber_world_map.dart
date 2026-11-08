import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../business/subscription/node_model.dart';
import '../../../core/geo/world_geo_coordinates.dart';
import '../../../core/i18n/i18n_service.dart';

/// 節點地理資訊元數據 (向下相容別名，內部代理至全球 249 國 WorldGeoItem)
typedef GeoCoordinate = WorldGeoItem;

/// 世界地理節點註冊中心 (對接全球 249 國 ISO 經緯度與底圖校準引擎)
class GeoRegistry {
  GeoRegistry._();

  static WorldGeoItem get originClient => WorldGeoCoordinates.originClient;

  /// 智慧推導節點座標 (支援全球 249 國 Emoji 數學反解 + 全球機房城市別名)
  static WorldGeoItem resolve(NodeModel? node) => WorldGeoCoordinates.resolve(node);

  /// 全球 249 國底圖精準座標表
  static Map<String, Offset> get preciseMapOffsets => {
    for (final entry in WorldGeoCoordinates.items.entries)
      entry.key: entry.value.mapOffset,
  };
}

/// 賽博世界地圖全息 HUD 組件 (CyberWorldMap)
/// 採用高精準真實科技點陣世界地圖 (assets/images/world_map_holo.png) 為底層
/// 疊加軍規 HUD 雷達掃描、座標刻度尺、用戶黃金雷達點與動態跨國流光飛行光弧
class CyberWorldMap extends StatefulWidget {
  final NodeModel? activeNode;
  final bool isConnected;
  final double? height;
  final bool showContainerDecoration;
  final Color? backgroundColor;

  final bool enableAnimations;

  const CyberWorldMap({
    super.key,
    this.activeNode,
    this.isConnected = false,
    this.height,
    this.showContainerDecoration = true,
    this.backgroundColor,
    this.enableAnimations = true,
  });

  @override
  State<CyberWorldMap> createState() => _CyberWorldMapState();
}

class _CyberWorldMapState extends State<CyberWorldMap> with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  bool get _isTestEnv {
    if (Platform.environment['FLUTTER_TEST'] == 'true') return true;
    final binding = WidgetsBinding.instance.runtimeType.toString();
    return binding.contains('Test');
  }

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    if (widget.enableAnimations && !_isTestEnv) {
      _animController.repeat();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final targetGeo = GeoRegistry.resolve(widget.activeNode);

    final mapContent = Stack(
      children: [
        // 1. 底層：真實世界高精準科技點陣地圖 (world_map_holo.png)
        Positioned.fill(
          child: Padding(
            padding: widget.showContainerDecoration
                ? const EdgeInsets.fromLTRB(16, 28, 16, 32)
                : EdgeInsets.zero,
            child: Opacity(
              opacity: widget.showContainerDecoration ? 0.88 : 0.16,
              child: Image.asset(
                'assets/images/world_map_holo.png',
                fit: BoxFit.fill,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),

        // 2. 疊加層：動態 HUD 雷達、飛行光弧與節點氣泡 (CustomPaint)
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _animController,
            builder: (context, _) {
              return CustomPaint(
                painter: _HoloWorldMapHudPainter(
                  progress: _animController.value,
                  originOffset: GeoRegistry.originClient.toPreciseMapOffset(),
                  targetOffset: targetGeo.toPreciseMapOffset(),
                  targetGeo: targetGeo,
                  node: widget.activeNode,
                  isConnected: widget.isConnected,
                  showHudDecorations: widget.showContainerDecoration,
                ),
                child: const SizedBox.expand(),
              );
            },
          ),
        ),
      ],
    );

    if (!widget.showContainerDecoration) {
      return SizedBox(
        height: widget.height,
        width: double.infinity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: mapContent,
        ),
      );
    }

    return Container(
      height: widget.height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: widget.backgroundColor ?? const Color(0xFF090E1A), // 深邃宇宙藍
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF00D2FF).withOpacity(0.22),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.45),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: const Color(0xFF00D2FF).withOpacity(0.06),
            blurRadius: 26,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: mapContent,
      ),
    );
  }
}

/// 全息 HUD 雷達與動態粒子飛行光弧繪製器
class _HoloWorldMapHudPainter extends CustomPainter {
  final double progress; // 0.0 ~ 1.0
  final Offset originOffset; // 0.0 ~ 1.0
  final Offset targetOffset; // 0.0 ~ 1.0
  final GeoCoordinate targetGeo;
  final NodeModel? node;
  final bool isConnected;
  final bool showHudDecorations;

  _HoloWorldMapHudPainter({
    required this.progress,
    required this.originOffset,
    required this.targetOffset,
    required this.targetGeo,
    this.node,
    required this.isConnected,
    this.showHudDecorations = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 地圖安全顯示邊界 (對齊底層 world_map_holo.png 之邊距)
    final mapRect = showHudDecorations
        ? Rect.fromLTWH(16, 28, w - 32, h - 60)
        : Rect.fromLTWH(0, 0, w, h);

    // 1. 繪製 HUD 邊角科技裝飾 (經緯網格、雷達掃描、底部標尺、波形圖)
    if (showHudDecorations) {
      _drawHudFrameDecorations(canvas, size, mapRect);
    }

    // 2. 計算地圖上的實體像素座標
    final originP = Offset(
      mapRect.left + originOffset.dx * mapRect.width,
      mapRect.top + originOffset.dy * mapRect.height,
    );
    final targetP = Offset(
      mapRect.left + targetOffset.dx * mapRect.width,
      mapRect.top + targetOffset.dy * mapRect.height,
    );

    // 3. 僅繪製主連線【跨國動態流光貝茲曲線】（消除次要節點航線，杜絕氣泡重疊）
    _drawFlightArc(canvas, originP, targetP, isSecondary: false);

    // 4. 繪製起點【用戶位置】亮橘金色呼吸雷達波
    _drawUserOriginBeacon(canvas, originP);

    // 5. 繪製目標節點【雙重擴散光環與亮點】
    _drawTargetBeacon(canvas, targetP);

    // 6. 繪製目標節點【懸浮 HUD 數據氣泡框】（單一乾淨標籤，支援智慧防重疊避讓）
    if (showHudDecorations) {
      _drawTargetHudBadge(canvas, targetP, originP, size, isSecondary: false);
    }
  }

  /// 繪製軍規 HUD 外框科技裝飾（已精簡：移除經緯度字樣、左下雷達與刻度尺）
  void _drawHudFrameDecorations(Canvas canvas, Size size, Rect mapRect) {
    final w = size.width;
    final h = size.height;

    // A. 暗青色細微經緯網格
    final gridPaint = Paint()
      ..color = const Color(0xFF00D2FF).withOpacity(0.04)
      ..strokeWidth = 0.8;

    for (int i = 1; i <= 3; i++) {
      final y = mapRect.top + mapRect.height * (i / 4.0);
      canvas.drawLine(Offset(mapRect.left, y), Offset(mapRect.right, y), gridPaint);
    }
    for (int i = 1; i <= 4; i++) {
      final x = mapRect.left + mapRect.width * (i / 5.0);
      canvas.drawLine(Offset(x, mapRect.top), Offset(x, mapRect.bottom), gridPaint);
    }

    // B. 右上角小型雷達掃描 (Radar Sweep)
    final radarCenter = Offset(w - 24, 22);
    final radarPaint = Paint()
      ..color = const Color(0xFF00D2FF).withOpacity(0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    canvas.drawCircle(radarCenter, 10, radarPaint);
    canvas.drawCircle(radarCenter, 5, radarPaint);
    final sweepAngle = progress * 2 * math.pi;
    final sweepEnd = Offset(
      radarCenter.dx + 10 * math.cos(sweepAngle),
      radarCenter.dy + 10 * math.sin(sweepAngle),
    );
    canvas.drawLine(
      radarCenter,
      sweepEnd,
      Paint()
        ..color = const Color(0xFF00D2FF).withOpacity(0.7)
        ..strokeWidth = 1.0,
    );

    // F. 右下角音頻/流量動態等化器條 (Equalizer Bars)
    final eqBaseX = w - 68;
    final eqBaseY = h - 14;
    final barPaint = Paint()..color = const Color(0xFF00D2FF).withOpacity(0.35);

    for (int i = 0; i < 7; i++) {
      final barH = 3.0 + 8.0 * (0.5 + 0.5 * math.sin(progress * 2 * math.pi + i * 0.8));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(eqBaseX + i * 5.0, eqBaseY - barH, 2.5, barH),
          const Radius.circular(1),
        ),
        barPaint,
      );
    }
  }

  /// 繪製跨國能量飛行弧線 (帶外發光與流光粒子)
  void _drawFlightArc(Canvas canvas, Offset start, Offset end, {required bool isSecondary}) {
    final path = Path();
    path.moveTo(start.dx, start.dy);

    // 計算拋物線控制點 (Control Point)
    final midX = (start.dx + end.dx) / 2.0;
    final dist = (end - start).distance;
    final arcHeight = math.max(38.0, dist * 0.32);
    final controlY = math.min(start.dy, end.dy) - arcHeight;
    final controlPoint = Offset(midX, controlY);

    path.quadraticBezierTo(controlPoint.dx, controlPoint.dy, end.dx, end.dy);

    final alphaMult = isSecondary ? 0.35 : 1.0;

    // 1. 外層霓虹發光層
    final glowPaint = Paint()
      ..color = (isSecondary ? const Color(0xFF0284C7) : const Color(0xFF00E5FF)).withOpacity(0.28 * alphaMult)
      ..style = PaintingStyle.stroke
      ..strokeWidth = isSecondary ? 2.2 : 3.6
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
    canvas.drawPath(path, glowPaint);

    // 2. 核心發光主線
    final corePaint = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFFF59E0B).withOpacity(0.7 * alphaMult), // 橘金出發
          const Color(0xFF00E5FF).withOpacity(0.9 * alphaMult), // 霓虹青藍中段
          const Color(0xFF38BDF8).withOpacity(0.85 * alphaMult), // 天藍到達
        ],
      ).createShader(Rect.fromPoints(start, end))
      ..style = PaintingStyle.stroke
      ..strokeWidth = isSecondary ? 1.0 : 1.6;
    canvas.drawPath(path, corePaint);

    // 3. 沿貝茲曲線運動的流光發光粒子
    final particleCount = isSecondary ? 1 : 3;
    for (int i = 0; i < particleCount; i++) {
      final t = (progress + (i * 0.33)) % 1.0;
      // 二次貝茲曲線公式: B(t) = (1-t)^2*P0 + 2(1-t)t*P1 + t^2*P2
      final px = math.pow(1 - t, 2) * start.dx + 2 * (1 - t) * t * controlPoint.dx + math.pow(t, 2) * end.dx;
      final py = math.pow(1 - t, 2) * start.dy + 2 * (1 - t) * t * controlPoint.dy + math.pow(t, 2) * end.dy;
      final particlePos = Offset(px, py);

      // 粒子光暈
      canvas.drawCircle(
        particlePos,
        isSecondary ? 3.0 : 4.5,
        Paint()
          ..color = const Color(0xFF00E5FF).withOpacity(0.45 * alphaMult)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
      );
      // 粒子白亮核心
      canvas.drawCircle(
        particlePos,
        isSecondary ? 1.4 : 2.0,
        Paint()..color = Colors.white.withOpacity(0.95 * alphaMult),
      );
    }
  }

  /// 繪製起點【用戶位置】橘金色呼吸波與微光雷達點
  void _drawUserOriginBeacon(Canvas canvas, Offset p) {
    // 3 層呼吸擴散光環
    for (int i = 0; i < 3; i++) {
      final ringProgress = (progress + (i * 0.33)) % 1.0;
      final radius = 4.0 + ringProgress * 18.0;
      final opacity = (1.0 - ringProgress) * 0.65;

      canvas.drawCircle(
        p,
        radius,
        Paint()
          ..color = const Color(0xFFF59E0B).withOpacity(opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }

    // 中心實心亮橘金色圓點
    canvas.drawCircle(
      p,
      4.5,
      Paint()
        ..color = const Color(0xFFF59E0B)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0),
    );
    canvas.drawCircle(
      p,
      2.5,
      Paint()..color = Colors.white,
    );

    // 旁邊標註微型「用戶位置 (USER)」膠囊標籤
    final tagRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(p.dx - 22, p.dy + 8, 44, 14),
      const Radius.circular(4),
    );
    canvas.drawRRect(
      tagRect,
      Paint()..color = const Color(0xFF0B132B).withOpacity(0.85),
    );
    canvas.drawRRect(
      tagRect,
      Paint()
        ..color = const Color(0xFFF59E0B).withOpacity(0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7,
    );

    _drawText(
      canvas,
      I18nService.instance.t('local_user'),
      Offset(p.dx - 18, p.dy + 9),
      const TextStyle(color: Color(0xFFFBBF24), fontSize: 8, fontWeight: FontWeight.bold),
    );
  }

  /// 繪製目標節點【雙重擴散光環】
  void _drawTargetBeacon(Canvas canvas, Offset p) {
    // 2 層藍綠色擴散光環
    for (int i = 0; i < 2; i++) {
      final ringProgress = (progress + (i * 0.5)) % 1.0;
      final radius = 5.0 + ringProgress * 16.0;
      final opacity = (1.0 - ringProgress) * 0.7;

      canvas.drawCircle(
        p,
        radius,
        Paint()
          ..color = const Color(0xFF00E5FF).withOpacity(opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }

    // 節點亮點
    canvas.drawCircle(
      p,
      5.0,
      Paint()
        ..color = const Color(0xFF00E5FF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
    );
    canvas.drawCircle(
      p,
      2.6,
      Paint()..color = Colors.white,
    );
  }

  /// 繪製目標節點【懸浮 HUD 數據氣泡框】(支援近距離智慧避讓與真實延遲連動)
  void _drawTargetHudBadge(
    Canvas canvas,
    Offset p,
    Offset originP,
    Size size, {
    String? customName,
    String? customLatency,
    bool isSecondary = false,
  }) {
    final name = customName ??
        (node?.cleanDisplayName.isNotEmpty == true ? node!.cleanDisplayName : targetGeo.name);

    // 100% 綁定真實延遲數值：未測速顯示 '-- ms'，逾時顯示玫紅，有效延遲顯示翠綠
    final String latency;
    final Color latencyColor;
    if (customLatency != null) {
      latency = customLatency;
      latencyColor = const Color(0xFF10B981);
    } else if (node == null || node!.latencyMs == null) {
      latency = '-- ms';
      latencyColor = const Color(0xFF94A3B8); // 未測速時顯示次級銀灰，絕不造假寫死 42ms
    } else if (node!.latencyMs! < 0) {
      latency = I18nService.instance.t('node_timeout');
      latencyColor = const Color(0xFFF43F5E); // 警告玫紅
    } else {
      latency = '${node!.latencyMs} ms';
      latencyColor = const Color(0xFF10B981); // 測速成功翡翠綠
    }

    // 氣泡尺寸 (加大至 164px 寬，確保各國節點名稱不被截斷)
    const boxW = 164.0;
    const boxH = 26.0;

    // ========================================================
    // 近距離智慧避讓 (Smart Anti-Collision) & 邊界防溢出引擎
    // ========================================================
    final distToOrigin = (p - originP).distance;
    final isCloseToOrigin = distToOrigin < 65.0; // 與本機位置極度接近 (如選中台灣/香港節點)

    double boxX;
    double boxY;

    if (isCloseToOrigin) {
      // 近距離避讓：自動往上方大幅抬升 38px，讓出下方空間給「本機用戶」標籤
      boxY = p.dy - 38.0;
      // 水平方向稍微偏移避開正中心
      boxX = (p.dx > originP.dx) ? (p.dx + 6.0) : (p.dx - boxW - 6.0);
    } else {
      // 正常距離：向右上方自然展開
      boxX = p.dx + 12.0;
      boxY = p.dy - 13.0;
    }

    // 水平邊界安全折疊 (防止超出世界地圖東西邊緣)
    if (boxX + boxW > size.width - 12) {
      boxX = p.dx - boxW - 12.0; // 靠最右端 (如日本、紐西蘭) 向左折疊
    }
    if (boxX < 12) {
      boxX = p.dx + 12.0; // 靠最左端 (如美西、夏威夷) 向右展開
    }

    // 垂直邊界安全折疊 (防止超出世界地圖南北邊緣)
    if (boxY < 26) {
      boxY = p.dy + 16.0; // 靠北極圈 (如冰島、挪威) 向下展開
    }
    if (boxY + boxH > size.height - 16) {
      boxY = p.dy - boxH - 12.0; // 靠南極圈 (如智利、南非) 向上展開
    }

    // 全局安全 Clamp 兜底
    boxX = boxX.clamp(10.0, math.max(10.0, size.width - boxW - 10.0));
    boxY = boxY.clamp(24.0, math.max(24.0, size.height - boxH - 10.0));

    final boxRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(boxX, boxY, boxW, boxH),
      const Radius.circular(6),
    );

    // 1. 氣泡陰影
    canvas.drawRRect(
      boxRect,
      Paint()
        ..color = Colors.black.withOpacity(0.60)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0),
    );

    // 2. 氣泡深色玻璃背景
    canvas.drawRRect(
      boxRect,
      Paint()..color = const Color(0xFF081026).withOpacity(0.92),
    );

    // 3. 氣泡微光邊框
    canvas.drawRRect(
      boxRect,
      Paint()
        ..color = (isSecondary ? const Color(0xFF0284C7) : const Color(0xFF00D2FF)).withOpacity(0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9,
    );

    // 4. 連接導引細線 (從節點圓心指向氣泡最接近的邊緣點)
    final anchorX = (p.dx < boxX)
        ? boxX
        : (p.dx > boxX + boxW ? boxX + boxW : p.dx);
    final anchorY = (p.dy < boxY)
        ? boxY
        : (p.dy > boxY + boxH ? boxY + boxH : boxY + boxH / 2);

    canvas.drawLine(
      p,
      Offset(anchorX, anchorY),
      Paint()
        ..color = (isSecondary ? const Color(0xFF0284C7) : const Color(0xFF00D2FF)).withOpacity(0.45)
        ..strokeWidth = 0.8,
    );

    // 5. 國旗徽章繪製 (使用全球向量彩色國旗，徹底解決 Windows 字型退化為 US us / JP jp 字母問題)
    final iso = node?.countryCode ?? targetGeo.iso;
    _drawMiniVectorFlag(canvas, Rect.fromLTWH(boxX + 6, boxY + 7.5, 16, 11), iso);

    // 6. 右側延遲文字 (靠右對齊，100% 綁定真實狀態顏色)
    final latencyStyle = TextStyle(
      color: latencyColor,
      fontSize: 9.5,
      fontWeight: FontWeight.bold,
      fontFamily: 'monospace',
    );
    final latencyTp = TextPainter(
      text: TextSpan(text: latency, style: latencyStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final latencyX = boxX + boxW - latencyTp.width - 7;
    latencyTp.paint(canvas, Offset(latencyX, boxY + (boxH - latencyTp.height) / 2));

    // 7. 節點名稱文字 (支援最多 14 個字元不截斷)
    final cleanName = node?.cleanDisplayName.isNotEmpty == true ? node!.cleanDisplayName : name;
    final displayName = cleanName.length > 14 ? '${cleanName.substring(0, 13)}..' : cleanName;
    _drawText(
      canvas,
      displayName,
      Offset(boxX + 26, boxY + 6.0),
      const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  /// 全球向量彩色國旗庫 (涵蓋主要節點與新增冷門國，杜絕系統字型缺字)
  void _drawMiniVectorFlag(Canvas canvas, Rect rect, String countryCode) {
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)));
    final code = countryCode.toUpperCase();
    switch (code) {
      case 'JP':
        canvas.drawRect(rect, Paint()..color = Colors.white);
        canvas.drawCircle(rect.center, rect.height * 0.30, Paint()..color = const Color(0xFFBC002D));
        break;
      case 'US':
        final sh = rect.height / 5.0;
        for (int i = 0; i < 5; i++) {
          canvas.drawRect(
            Rect.fromLTWH(rect.left, rect.top + i * sh, rect.width, sh),
            Paint()..color = (i % 2 == 0) ? const Color(0xFFB22234) : Colors.white,
          );
        }
        canvas.drawRect(
          Rect.fromLTWH(rect.left, rect.top, rect.width * 0.45, sh * 3),
          Paint()..color = const Color(0xFF3C3B6E),
        );
        break;
      case 'HK':
        canvas.drawRect(rect, Paint()..color = const Color(0xFFDE2910));
        canvas.drawCircle(rect.center, rect.height * 0.28, Paint()..color = Colors.white);
        break;
      case 'TW':
        canvas.drawRect(rect, Paint()..color = const Color(0xFFFE0000));
        final cw = rect.width * 0.5;
        final ch = rect.height * 0.5;
        canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, cw, ch), Paint()..color = const Color(0xFF000095));
        canvas.drawCircle(Offset(rect.left + cw / 2, rect.top + ch / 2), ch * 0.3, Paint()..color = Colors.white);
        break;
      case 'SG':
        final hh = rect.height / 2;
        canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, rect.width, hh), Paint()..color = const Color(0xFFED2939));
        canvas.drawRect(Rect.fromLTWH(rect.left, rect.top + hh, rect.width, hh), Paint()..color = Colors.white);
        break;
      case 'KR':
        canvas.drawRect(rect, Paint()..color = Colors.white);
        canvas.drawCircle(rect.center, rect.height * 0.28, Paint()..color = const Color(0xFFCD2E3A));
        break;
      case 'GB':
      case 'UK':
        canvas.drawRect(rect, Paint()..color = const Color(0xFF012169));
        final redPaint = Paint()..color = const Color(0xFFC8102E)..strokeWidth = 2.0;
        final whitePaint = Paint()..color = Colors.white..strokeWidth = 3.2;
        canvas.drawLine(rect.topLeft, rect.bottomRight, whitePaint);
        canvas.drawLine(rect.bottomLeft, rect.topRight, whitePaint);
        canvas.drawLine(rect.topLeft, rect.bottomRight, redPaint);
        canvas.drawLine(rect.bottomLeft, rect.topRight, redPaint);
        canvas.drawLine(Offset(rect.center.dx, rect.top), Offset(rect.center.dx, rect.bottom), whitePaint);
        canvas.drawLine(Offset(rect.left, rect.center.dy), Offset(rect.right, rect.center.dy), whitePaint);
        canvas.drawLine(Offset(rect.center.dx, rect.top), Offset(rect.center.dx, rect.bottom), redPaint);
        canvas.drawLine(Offset(rect.left, rect.center.dy), Offset(rect.right, rect.center.dy), redPaint);
        break;
      case 'DE':
        final dh = rect.height / 3;
        canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, rect.width, dh), Paint()..color = Colors.black);
        canvas.drawRect(Rect.fromLTWH(rect.left, rect.top + dh, rect.width, dh), Paint()..color = const Color(0xFFDD0000));
        canvas.drawRect(Rect.fromLTWH(rect.left, rect.top + dh * 2, rect.width, dh), Paint()..color = const Color(0xFFFFCE00));
        break;
      case 'FR':
        final fw = rect.width / 3;
        canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, fw, rect.height), Paint()..color = const Color(0xFF002654));
        canvas.drawRect(Rect.fromLTWH(rect.left + fw, rect.top, fw, rect.height), Paint()..color = Colors.white);
        canvas.drawRect(Rect.fromLTWH(rect.left + fw * 2, rect.top, fw, rect.height), Paint()..color = const Color(0xFFED2939));
        break;
      case 'IE':
        final iw = rect.width / 3;
        canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, iw, rect.height), Paint()..color = const Color(0xFF169B62));
        canvas.drawRect(Rect.fromLTWH(rect.left + iw, rect.top, iw, rect.height), Paint()..color = Colors.white);
        canvas.drawRect(Rect.fromLTWH(rect.left + iw * 2, rect.top, iw, rect.height), Paint()..color = const Color(0xFFFF883E));
        break;
      case 'NL':
        final nh = rect.height / 3;
        canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, rect.width, nh), Paint()..color = const Color(0xFFAE1C28));
        canvas.drawRect(Rect.fromLTWH(rect.left, rect.top + nh, rect.width, nh), Paint()..color = Colors.white);
        canvas.drawRect(Rect.fromLTWH(rect.left, rect.top + nh * 2, rect.width, nh), Paint()..color = const Color(0xFF21468B));
        break;
      case 'RU':
        final rh = rect.height / 3;
        canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, rect.width, rh), Paint()..color = Colors.white);
        canvas.drawRect(Rect.fromLTWH(rect.left, rect.top + rh, rect.width, rh), Paint()..color = const Color(0xFF0039A6));
        canvas.drawRect(Rect.fromLTWH(rect.left, rect.top + rh * 2, rect.width, rh), Paint()..color = const Color(0xFFD52B1E));
        break;
      case 'CA':
        canvas.drawRect(rect, Paint()..color = Colors.white);
        final cw = rect.width / 4;
        canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, cw, rect.height), Paint()..color = const Color(0xFFFF0000));
        canvas.drawRect(Rect.fromLTWH(rect.right - cw, rect.top, cw, rect.height), Paint()..color = const Color(0xFFFF0000));
        canvas.drawCircle(rect.center, rect.height * 0.22, Paint()..color = const Color(0xFFFF0000));
        break;
      case 'AU':
        canvas.drawRect(rect, Paint()..color = const Color(0xFF00008B));
        final uh = rect.height / 2;
        final uw = rect.width / 2;
        canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, uw, uh), Paint()..color = const Color(0xFF012169));
        canvas.drawLine(rect.topLeft, Offset(rect.left + uw, rect.top + uh), Paint()..color = Colors.white..strokeWidth = 1.0);
        canvas.drawLine(Offset(rect.left, rect.top + uh), Offset(rect.left + uw, rect.top), Paint()..color = Colors.white..strokeWidth = 1.0);
        break;
      case 'BR': // 巴西
        canvas.drawRect(rect, Paint()..color = const Color(0xFF009B3A));
        final diamond = Path()
          ..moveTo(rect.center.dx, rect.top + 1.5)
          ..lineTo(rect.right - 2, rect.center.dy)
          ..lineTo(rect.center.dx, rect.bottom - 1.5)
          ..lineTo(rect.left + 2, rect.center.dy)
          ..close();
        canvas.drawPath(diamond, Paint()..color = const Color(0xFFFEDF00));
        canvas.drawCircle(rect.center, rect.height * 0.22, Paint()..color = const Color(0xFF002776));
        break;
      case 'AR': // 阿根廷
        final ah = rect.height / 3;
        canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, rect.width, ah), Paint()..color = const Color(0xFF74ACDF));
        canvas.drawRect(Rect.fromLTWH(rect.left, rect.top + ah, rect.width, ah), Paint()..color = Colors.white);
        canvas.drawRect(Rect.fromLTWH(rect.left, rect.top + ah * 2, rect.width, ah), Paint()..color = const Color(0xFF74ACDF));
        canvas.drawCircle(rect.center, ah * 0.35, Paint()..color = const Color(0xFFF6B40E));
        break;
      case 'ZA': // 南非
        canvas.drawRect(rect, Paint()..color = const Color(0xFFDE3831));
        canvas.drawRect(Rect.fromLTWH(rect.left, rect.top + rect.height / 2, rect.width, rect.height / 2), Paint()..color = const Color(0xFF002395));
        final greenY = Path()
          ..moveTo(rect.left, rect.top)
          ..lineTo(rect.left + rect.width * 0.45, rect.center.dy)
          ..lineTo(rect.right, rect.center.dy)
          ..lineTo(rect.right, rect.center.dy + 3)
          ..lineTo(rect.left + rect.width * 0.45, rect.center.dy + 3)
          ..lineTo(rect.left, rect.bottom)
          ..close();
        canvas.drawPath(greenY, Paint()..color = const Color(0xFF007A3D)..strokeWidth = 3..style = PaintingStyle.stroke);
        final blackTriangle = Path()
          ..moveTo(rect.left, rect.top + 2)
          ..lineTo(rect.left + rect.width * 0.35, rect.center.dy)
          ..lineTo(rect.left, rect.bottom - 2)
          ..close();
        canvas.drawPath(blackTriangle, Paint()..color = Colors.black);
        break;
      case 'IS': // 冰島
        canvas.drawRect(rect, Paint()..color = const Color(0xFF02529C));
        final crossX = rect.left + rect.width * 0.36;
        final whiteCross = Paint()..color = Colors.white..strokeWidth = 3.0;
        final redCross = Paint()..color = const Color(0xFFDC1E35)..strokeWidth = 1.4;
        canvas.drawLine(Offset(crossX, rect.top), Offset(crossX, rect.bottom), whiteCross);
        canvas.drawLine(Offset(rect.left, rect.center.dy), Offset(rect.right, rect.center.dy), whiteCross);
        canvas.drawLine(Offset(crossX, rect.top), Offset(crossX, rect.bottom), redCross);
        canvas.drawLine(Offset(rect.left, rect.center.dy), Offset(rect.right, rect.center.dy), redCross);
        break;
      case 'SA': // 沙烏地阿拉伯
        canvas.drawRect(rect, Paint()..color = const Color(0xFF006C35));
        canvas.drawLine(
          Offset(rect.left + 3, rect.center.dy),
          Offset(rect.right - 3, rect.center.dy),
          Paint()..color = Colors.white..strokeWidth = 1.2,
        );
        break;
      case 'AE': // 阿聯酋
        final aeh = rect.height / 3;
        final aew = rect.width / 4;
        canvas.drawRect(Rect.fromLTWH(rect.left + aew, rect.top, rect.width - aew, aeh), Paint()..color = const Color(0xFF00732F));
        canvas.drawRect(Rect.fromLTWH(rect.left + aew, rect.top + aeh, rect.width - aew, aeh), Paint()..color = Colors.white);
        canvas.drawRect(Rect.fromLTWH(rect.left + aew, rect.top + aeh * 2, rect.width - aew, aeh), Paint()..color = Colors.black);
        canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, aew, rect.height), Paint()..color = const Color(0xFFFF0000));
        break;
      case 'CH': // 瑞士
        canvas.drawRect(rect, Paint()..color = const Color(0xFFD52B1E));
        final pw = Paint()..color = Colors.white;
        canvas.drawRect(Rect.fromLTWH(rect.center.dx - 1.5, rect.center.dy - 3.5, 3.0, 7.0), pw);
        canvas.drawRect(Rect.fromLTWH(rect.center.dx - 3.5, rect.center.dy - 1.5, 7.0, 3.0), pw);
        break;
      case 'SE': // 瑞典
        canvas.drawRect(rect, Paint()..color = const Color(0xFF006AA7));
        final scrossX = rect.left + rect.width * 0.36;
        final sPaint = Paint()..color = const Color(0xFFFECC00)..strokeWidth = 2.0;
        canvas.drawLine(Offset(scrossX, rect.top), Offset(scrossX, rect.bottom), sPaint);
        canvas.drawLine(Offset(rect.left, rect.center.dy), Offset(rect.right, rect.center.dy), sPaint);
        break;
      case 'NO': // 挪威
        canvas.drawRect(rect, Paint()..color = const Color(0xFFBA0C2F));
        final ncrossX = rect.left + rect.width * 0.36;
        final nwPaint = Paint()..color = Colors.white..strokeWidth = 3.0;
        final nbPaint = Paint()..color = const Color(0xFF00205B)..strokeWidth = 1.4;
        canvas.drawLine(Offset(ncrossX, rect.top), Offset(ncrossX, rect.bottom), nwPaint);
        canvas.drawLine(Offset(rect.left, rect.center.dy), Offset(rect.right, rect.center.dy), nwPaint);
        canvas.drawLine(Offset(ncrossX, rect.top), Offset(ncrossX, rect.bottom), nbPaint);
        canvas.drawLine(Offset(rect.left, rect.center.dy), Offset(rect.right, rect.center.dy), nbPaint);
        break;
      case 'IN': // 印度
        final ih = rect.height / 3;
        canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, rect.width, ih), Paint()..color = const Color(0xFFFF9933));
        canvas.drawRect(Rect.fromLTWH(rect.left, rect.top + ih, rect.width, ih), Paint()..color = Colors.white);
        canvas.drawRect(Rect.fromLTWH(rect.left, rect.top + ih * 2, rect.width, ih), Paint()..color = const Color(0xFF138808));
        canvas.drawCircle(rect.center, ih * 0.32, Paint()..color = const Color(0xFF000080));
        break;
      case 'TH': // 泰國
        final th1 = rect.height / 6;
        canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, rect.width, th1), Paint()..color = const Color(0xFFA51931));
        canvas.drawRect(Rect.fromLTWH(rect.left, rect.top + th1, rect.width, th1), Paint()..color = const Color(0xFFF4F5F8));
        canvas.drawRect(Rect.fromLTWH(rect.left, rect.top + th1 * 2, rect.width, th1 * 2), Paint()..color = const Color(0xFF2D2A4A));
        canvas.drawRect(Rect.fromLTWH(rect.left, rect.top + th1 * 4, rect.width, th1), Paint()..color = const Color(0xFFF4F5F8));
        canvas.drawRect(Rect.fromLTWH(rect.left, rect.top + th1 * 5, rect.width, th1), Paint()..color = const Color(0xFFA51931));
        break;
      case 'VN': // 越南
        canvas.drawRect(rect, Paint()..color = const Color(0xFFDA251D));
        canvas.drawCircle(rect.center, rect.height * 0.25, Paint()..color = const Color(0xFFFFFF00));
        break;
      default:
        // 全球未定義國家：科技感精緻深藍底色 + 居中白色 2-碼 ISO 代碼
        canvas.drawRect(rect, Paint()..color = const Color(0xFF0B2545));
        final span = TextSpan(
          text: code.length <= 2 ? code : code.substring(0, 2),
          style: const TextStyle(
            color: Color(0xFF00E5FF),
            fontSize: 6.5,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        );
        final tp = TextPainter(text: span, textDirection: TextDirection.ltr)..layout();
        tp.paint(canvas, Offset(rect.left + (rect.width - tp.width) / 2, rect.top + (rect.height - tp.height) / 2));
        break;
    }
    // 外邊框
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.white.withOpacity(0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6,
    );
    canvas.restore();
  }

  void _drawText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _HoloWorldMapHudPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.targetOffset != targetOffset ||
        oldDelegate.originOffset != originOffset ||
        oldDelegate.isConnected != isConnected ||
        oldDelegate.node?.id != node?.id ||
        oldDelegate.node?.latencyMs != node?.latencyMs ||
        oldDelegate.node?.latencyFormatted != node?.latencyFormatted ||
        oldDelegate.node?.name != node?.name;
  }
}
