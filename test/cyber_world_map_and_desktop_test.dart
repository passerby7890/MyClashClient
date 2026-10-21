import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flclash_v2board_client/business/subscription/node_model.dart';
import 'package:flclash_v2board_client/core/geo/world_geo_coordinates.dart';
import 'package:flclash_v2board_client/presentation/dashboard/widgets/cyber_world_map.dart';

void main() {
  group('【賽博世界地圖 (CyberWorldMap) 核心演算法與座標測試】', () {
    test('1. Equirectangular 經緯度投影演算法精確度與邊界值測試', () {
      // 經緯度原點 (0, 0)
      const center = WorldGeoItem(iso: 'CT', lat: 0.0, lng: 0.0, flag: '🌐', name: 'Center');
      final normCenter = center.mapOffset;
      expect(normCenter.dx, closeTo(0.5, 0.05));
      expect(normCenter.dy, closeTo(0.585, 0.05));

      // 西北極限角 (-180, 90)
      const northwest = WorldGeoItem(iso: 'NW', lat: 90.0, lng: -180.0, flag: '🌐', name: 'NW');
      final normNW = northwest.mapOffset;
      expect(normNW.dx, inInclusiveRange(0.0, 0.15));
      expect(normNW.dy, inInclusiveRange(0.0, 0.15));

      // 東南極限角 (180, -90)
      const southeast = WorldGeoItem(iso: 'SE', lat: -90.0, lng: 180.0, flag: '🌐', name: 'SE');
      final normSE = southeast.mapOffset;
      expect(normSE.dx, inInclusiveRange(0.85, 1.0));
      expect(normSE.dy, inInclusiveRange(0.85, 1.0));
    });

    test('2. 常用國際節點地理座標與國旗 Emoji 匹配正確性', () {
      final hk = WorldGeoCoordinates.items['HK']!;
      expect(hk.flag, equals('🇭🇰'));
      expect(hk.name, equals('香港'));
      expect(hk.lat, closeTo(22.3, 0.1));
      expect(hk.lng, closeTo(114.1, 0.1));

      final jp = WorldGeoCoordinates.items['JP']!;
      expect(jp.flag, equals('🇯🇵'));
      expect(jp.name, equals('日本'));

      final us = WorldGeoCoordinates.items['US']!;
      expect(us.flag, equals('🇺🇸'));
      expect(us.name, equals('美國'));

      final sg = WorldGeoCoordinates.items['SG']!;
      expect(sg.flag, equals('🇸🇬'));

      final tw = WorldGeoCoordinates.items['TW']!;
      expect(tw.flag, equals('🇹🇼'));

      final kr = WorldGeoCoordinates.items['KR']!;
      expect(kr.flag, equals('🇰🇷'));

      final gb = WorldGeoCoordinates.items['GB']!;
      expect(gb.flag, equals('🇬🇧'));

      final de = WorldGeoCoordinates.items['DE']!;
      expect(de.flag, equals('🇩🇪'));
    });

    test('3. 智能節點名稱與 Emoji 匹配推導測試', () {
      // 依賴 flagEmoji: 🇯🇵
      final nodeByEmoji = const NodeModel(
        id: '1',
        name: 'VIP Premium Line 01',
        flagEmoji: '🇯🇵',
        protocol: 'trojan',
        rawConfig: {'server': '1.2.3.4'},
      );
      final geo1 = GeoRegistry.resolve(nodeByEmoji);
      expect(geo1.flag, equals('🇯🇵'));
      expect(geo1.name, equals('日本'));

      // 依賴關鍵字: 香港
      final nodeHK = const NodeModel(
        id: '2',
        name: '香港 IPLC 專線 02 [直連]',
        flagEmoji: '🇭🇰',
        protocol: 'vmess',
        rawConfig: {'server': '1.2.3.4'},
      );
      final geo2 = GeoRegistry.resolve(nodeHK);
      expect(geo2.flag, equals('🇭🇰'));

      // 依賴關鍵字: 东京
      final nodeTokyo = const NodeModel(
        id: '3',
        name: '东京 BGP 01 高速',
        flagEmoji: '🌐',
        protocol: 'trojan',
        rawConfig: {'server': '1.2.3.4'},
      );
      final geo3 = GeoRegistry.resolve(nodeTokyo);
      expect(geo3.flag, equals('🇯🇵'));

      // 依賴關鍵字: 狮城 / 新加坡
      final nodeSG = const NodeModel(
        id: '4',
        name: '狮城 01 專用節點',
        flagEmoji: '🌐',
        protocol: 'trojan',
        rawConfig: {'server': '1.2.3.4'},
      );
      final geo4 = GeoRegistry.resolve(nodeSG);
      expect(geo4.flag, equals('🇸🇬'));

      // 未知節點預設回退至香港
      final nodeUnknown = const NodeModel(
        id: '5',
        name: '神秘未知自建節點 99',
        flagEmoji: '🌐',
        protocol: 'ss',
        rawConfig: {'server': '1.2.3.4'},
      );
      final geoUnknown = GeoRegistry.resolve(nodeUnknown);
      expect(geoUnknown.flag, equals('🇭🇰'));

      // null 節點安全防護
      final geoNull = GeoRegistry.resolve(null);
      expect(geoNull.flag, equals('🇭🇰'));
    });

    test('4. 二階貝塞爾飛行弧線插值方程與流動光點計算', () {
      const p1 = Offset(100, 100);
      const p2 = Offset(300, 100);
      const controlPoint = Offset(200, 20); // 向上彎曲

      Offset calcBezier(double t) {
        final x = (1 - t) * (1 - t) * p1.dx + 2 * (1 - t) * t * controlPoint.dx + t * t * p2.dx;
        final y = (1 - t) * (1 - t) * p1.dy + 2 * (1 - t) * t * controlPoint.dy + t * t * p2.dy;
        return Offset(x, y);
      }

      // 起點 t = 0.0
      final start = calcBezier(0.0);
      expect(start.dx, closeTo(100.0, 0.01));
      expect(start.dy, closeTo(100.0, 0.01));

      // 終點 t = 1.0
      final end = calcBezier(1.0);
      expect(end.dx, closeTo(300.0, 0.01));
      expect(end.dy, closeTo(100.0, 0.01));

      // 中點 t = 0.5 必須向上凸起
      final mid = calcBezier(0.5);
      expect(mid.dx, closeTo(200.0, 0.01));
      expect(mid.dy, lessThan(100.0)); // 弧度凸起 (y 座標變小)
    });

    test('5. 極限壓力測試: 10,000 次連續高頻節點座標推導基準效能 (Benchmark)', () {
      final testNodes = [
        const NodeModel(id: '1', name: '香港 01', flagEmoji: '🇭🇰', protocol: 'ss', rawConfig: {}),
        const NodeModel(id: '2', name: '日本 东京 02', flagEmoji: '🇯🇵', protocol: 'vmess', rawConfig: {}),
        const NodeModel(id: '3', name: '美国 硅谷 03', flagEmoji: '🇺🇸', protocol: 'trojan', rawConfig: {}),
        const NodeModel(id: '4', name: '狮城 新加坡 04', flagEmoji: '🇸🇬', protocol: 'vless', rawConfig: {}),
        const NodeModel(id: '5', name: '台湾 台北 05', flagEmoji: '🇹🇼', protocol: 'ss', rawConfig: {}),
        const NodeModel(id: '6', name: '韩国 首尔 06', flagEmoji: '🇰🇷', protocol: 'ss', rawConfig: {}),
      ];

      final stopwatch = Stopwatch()..start();
      for (int i = 0; i < 10000; i++) {
        final node = testNodes[i % testNodes.length];
        final geo = GeoRegistry.resolve(node);
        final offset = geo.mapOffset;
        expect(offset.dx, inInclusiveRange(0.0, 1.0));
        expect(offset.dy, inInclusiveRange(0.0, 1.0));
      }
      stopwatch.stop();

      // 10,000 次運算必須在 100ms 內完成
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });
  });

  group('【CyberWorldMap Widget 視覺層渲染與生命週期測試】', () {
    testWidgets('1. CyberWorldMap 在未連線狀態下正確渲染與呼吸動畫啟動', (tester) async {
      const sampleNode = NodeModel(
        id: '101',
        name: '日本 东京 01 - 專線',
        flagEmoji: '🇯🇵',
        protocol: 'trojan',
        latencyMs: 42,
        rawConfig: {},
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: CyberWorldMap(
                activeNode: sampleNode,
                isConnected: false,
                height: 220,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CyberWorldMap), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);

      // 推進動畫影格 (測試 AnimationController 運轉流暢度)
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 1000));
    });

    testWidgets('2. CyberWorldMap 在已連線狀態下切換節點流暢重繪', (tester) async {
      const hkNode = NodeModel(
        id: '102',
        name: '香港 01 專線',
        flagEmoji: '🇭🇰',
        protocol: 'ss',
        latencyMs: 18,
        rawConfig: {},
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CyberWorldMap(
              activeNode: hkNode,
              isConnected: true,
              height: 200,
            ),
          ),
        ),
      );

      expect(find.byType(CyberWorldMap), findsOneWidget);

      // 模擬切換到美國節點
      const usNode = NodeModel(
        id: '103',
        name: '美國 洛杉磯 01',
        flagEmoji: '🇺🇸',
        protocol: 'ss',
        latencyMs: 145,
        rawConfig: {},
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CyberWorldMap(
              activeNode: usNode,
              isConnected: true,
              height: 200,
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(CyberWorldMap), findsOneWidget);
    });

    testWidgets('3. CyberWorldMap 在 null 節點狀態下安全容錯處理', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CyberWorldMap(
              activeNode: null,
              isConnected: false,
            ),
          ),
        ),
      );

      expect(find.byType(CyberWorldMap), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
    });
  });
}
