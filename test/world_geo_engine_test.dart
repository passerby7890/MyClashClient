// test/world_geo_engine_test.dart
// 天河網絡 (Tianhe Network) 全球 249 國經緯度投影與精準定位驗證測試

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flclash_v2board_client/business/subscription/node_model.dart';
import 'package:flclash_v2board_client/core/geo/world_geo_coordinates.dart';

void main() {
  group('【第一層：國家識別層】全球 249 國 Emoji 數學反解與別名庫驗證', () {
    test('Unicode Regional Indicator 數學反解驗證 (codeUnit - 0x1F1E6 + 65)', () {
      expect(WorldGeoCoordinates.emojiToIso('🇹🇼'), equals('TW'));
      expect(WorldGeoCoordinates.emojiToIso('🇭🇰'), equals('HK'));
      expect(WorldGeoCoordinates.emojiToIso('🇯🇵'), equals('JP'));
      expect(WorldGeoCoordinates.emojiToIso('🇺🇸'), equals('US'));
      expect(WorldGeoCoordinates.emojiToIso('🇸🇬'), equals('SG'));
      expect(WorldGeoCoordinates.emojiToIso('🇩🇪'), equals('DE'));
      expect(WorldGeoCoordinates.emojiToIso('🇬🇧'), equals('GB'));
      // 驗證冷門/新增國家
      expect(WorldGeoCoordinates.emojiToIso('🇧🇷'), equals('BR')); // 巴西
      expect(WorldGeoCoordinates.emojiToIso('🇿🇦'), equals('ZA')); // 南非
      expect(WorldGeoCoordinates.emojiToIso('🇮🇸'), equals('IS')); // 冰島
      expect(WorldGeoCoordinates.emojiToIso('🇸🇦'), equals('SA')); // 沙烏地阿拉伯
      expect(WorldGeoCoordinates.emojiToIso('🇦🇷'), equals('AR')); // 阿根廷
      expect(WorldGeoCoordinates.emojiToIso('🇳🇿'), equals('NZ')); // 紐西蘭
      expect(WorldGeoCoordinates.emojiToIso('🇨🇭'), equals('CH')); // 瑞士
      expect(WorldGeoCoordinates.emojiToIso('🇦🇪'), equals('AE')); // 阿聯酋
    });

    test('雙向逆轉：ISO 兩碼計算出標準國旗 Emoji', () {
      expect(WorldGeoCoordinates.isoToEmoji('TW'), equals('🇹🇼'));
      expect(WorldGeoCoordinates.isoToEmoji('JP'), equals('🇯🇵'));
      expect(WorldGeoCoordinates.isoToEmoji('BR'), equals('🇧🇷'));
      expect(WorldGeoCoordinates.isoToEmoji('ZA'), equals('🇿🇦'));
      expect(WorldGeoCoordinates.isoToEmoji('IS'), equals('🇮🇸'));
      expect(WorldGeoCoordinates.isoToEmoji('SA'), equals('🇸🇦'));
    });

    test('純文字節點名稱別名庫 100% 映射至 ISO 兩碼 (無 Emoji 亦可辨識)', () {
      // 國家中文繁/簡/英
      expect(WorldGeoCoordinates.resolveIsoFromAlias('L1-台湾专线'), equals('TW'));
      expect(WorldGeoCoordinates.resolveIsoFromAlias('直连-荷兰高速'), equals('NL'));
      expect(WorldGeoCoordinates.resolveIsoFromAlias('直连-冰岛纯净'), equals('IS'));
      expect(WorldGeoCoordinates.resolveIsoFromAlias('沙特阿拉伯-01'), equals('SA'));
      expect(WorldGeoCoordinates.resolveIsoFromAlias('巴西圣保罗BGP'), equals('BR'));
      expect(WorldGeoCoordinates.resolveIsoFromAlias('南非约翰内斯堡'), equals('ZA'));
      expect(WorldGeoCoordinates.resolveIsoFromAlias('阿根廷布宜诺斯艾利斯'), equals('AR'));

      // 機房城市名稱直接命中
      expect(WorldGeoCoordinates.resolveIsoFromAlias('迪拜云节点'), equals('AE'));
      expect(WorldGeoCoordinates.resolveIsoFromAlias('首尔5G专线'), equals('KR'));
      expect(WorldGeoCoordinates.resolveIsoFromAlias('法兰克福核心节点'), equals('DE'));
      expect(WorldGeoCoordinates.resolveIsoFromAlias('圣何塞低延迟'), equals('US'));
      expect(WorldGeoCoordinates.resolveIsoFromAlias('硅谷机房02'), equals('US'));
      expect(WorldGeoCoordinates.resolveIsoFromAlias('苏黎世金融专线'), equals('CH'));
      expect(WorldGeoCoordinates.resolveIsoFromAlias('阿姆斯特丹落地'), equals('NL'));
    });
  });

  group('【第二層：地圖座標層】全球 249 國經緯度與投影定位引擎驗證', () {
    test('資料庫完整度：涵蓋全球 249 個 ISO 3166-1 國家與地區', () {
      expect(WorldGeoCoordinates.items.length, equals(249));
      for (final item in WorldGeoCoordinates.items.values) {
        expect(item.iso.length, equals(2));
        expect(item.name.isNotEmpty, isTrue);
        expect(item.lat >= -90.0 && item.lat <= 90.0, isTrue);
        expect(item.lng >= -180.0 && item.lng <= 180.0, isTrue);

        final offset = item.mapOffset;
        expect(offset.dx >= 0.05 && offset.dx <= 0.95, isTrue,
            reason: '${item.iso} mapOffset.dx out of bounds: ${offset.dx}');
        expect(offset.dy >= 0.10 && offset.dy <= 0.90, isTrue,
            reason: '${item.iso} mapOffset.dy out of bounds: ${offset.dy}');
      }
    });

    test('冷門國家拒絕掉入香港：定位在真實大洲陸塊', () {
      final hkOffset = WorldGeoCoordinates.items['HK']!.mapOffset;

      // 1. 巴西 🇧🇷 BR (南美洲): X ≈ 0.36, Y ≈ 0.69
      final br = WorldGeoCoordinates.items['BR']!;
      expect(br.mapOffset, isNot(equals(hkOffset)));
      expect(br.mapOffset.dx, closeTo(0.36, 0.05));
      expect(br.mapOffset.dy, closeTo(0.69, 0.05));

      // 2. 南非 🇿🇦 ZA (非洲最南端): X ≈ 0.545, Y ≈ 0.745
      final za = WorldGeoCoordinates.items['ZA']!;
      expect(za.mapOffset, isNot(equals(hkOffset)));
      expect(za.mapOffset.dx, closeTo(0.545, 0.04));
      expect(za.mapOffset.dy, closeTo(0.745, 0.04));

      // 3. 冰島 🇮🇸 IS (北大西洋高緯度): X ≈ 0.438, Y ≈ 0.165
      final isItem = WorldGeoCoordinates.items['IS']!;
      expect(isItem.mapOffset, isNot(equals(hkOffset)));
      expect(isItem.mapOffset.dx, closeTo(0.438, 0.04));
      expect(isItem.mapOffset.dy, closeTo(0.165, 0.04));

      // 4. 沙烏地阿拉伯 🇸🇦 SA (中東阿拉伯半島): X ≈ 0.603, Y ≈ 0.435
      final sa = WorldGeoCoordinates.items['SA']!;
      expect(sa.mapOffset, isNot(equals(hkOffset)));
      expect(sa.mapOffset.dx, closeTo(0.603, 0.04));
      expect(sa.mapOffset.dy, closeTo(0.435, 0.04));
    });

    test('常用密集區與主要國家視覺錨點 (visualAnchor) 精確度', () {
      expect(WorldGeoCoordinates.items['TW']!.mapOffset, equals(const Offset(0.808, 0.455)));
      expect(WorldGeoCoordinates.items['HK']!.mapOffset, equals(const Offset(0.785, 0.465)));
      expect(WorldGeoCoordinates.items['JP']!.mapOffset, equals(const Offset(0.846, 0.345)));
      expect(WorldGeoCoordinates.items['SG']!.mapOffset, equals(const Offset(0.772, 0.585)));
      expect(WorldGeoCoordinates.items['US']!.mapOffset, equals(const Offset(0.180, 0.360)));
      expect(WorldGeoCoordinates.items['NL']!.mapOffset, equals(const Offset(0.498, 0.275)));
      expect(WorldGeoCoordinates.items['IE']!.mapOffset, equals(const Offset(0.470, 0.278)));
      expect(WorldGeoCoordinates.items['GB']!.mapOffset, equals(const Offset(0.486, 0.280)));
      expect(WorldGeoCoordinates.items['DE']!.mapOffset, equals(const Offset(0.512, 0.288)));
    });
  });

  group('【第三層：端到端整合與真實延遲連動】', () {
    test('透過 NodeModel 解析包含國旗與純文字之各國節點', () {
      // 帶 Emoji 的巴西節點
      const brNode = NodeModel(
        id: 'node_br',
        name: '🇧🇷 L1-巴西圣保罗',
        flagEmoji: '🇧🇷',
        protocol: 'VMESS',
        latencyMs: 188,
        rawConfig: {'server': 'br.test.com', 'port': 443},
      );
      final brGeo = WorldGeoCoordinates.resolve(brNode);
      expect(brGeo.iso, equals('BR'));
      expect(brGeo.name, equals('巴西'));
      expect(brNode.countryCode, equals('BR'));
      expect(brNode.regionName, equals('巴西'));
      expect(brNode.latencyFormatted, equals('188 ms'));

      // 純文字無 Emoji 的冰島節點
      const isNode = NodeModel(
        id: 'node_is',
        name: '直连-冰岛纯净原生IP',
        flagEmoji: '🌐',
        protocol: 'TROJAN',
        latencyMs: 235,
        rawConfig: {'server': 'is.test.com', 'port': 443},
      );
      final isGeo = WorldGeoCoordinates.resolve(isNode);
      expect(isGeo.iso, equals('IS'));
      expect(isGeo.name, equals('冰島'));
      expect(isNode.countryCode, equals('IS'));
      expect(isNode.regionName, equals('冰島'));
      expect(isNode.latencyFormatted, equals('235 ms'));

      // 未測速之沙烏地阿拉伯節點
      const saNode = NodeModel(
        id: 'node_sa',
        name: '沙特阿拉伯-利雅德-01',
        flagEmoji: '🌐',
        protocol: 'VLESS',
        latencyMs: null,
        rawConfig: {'server': 'sa.test.com', 'port': 443},
      );
      final saGeo = WorldGeoCoordinates.resolve(saNode);
      expect(saGeo.iso, equals('SA'));
      expect(saGeo.name, equals('沙烏地阿拉伯'));
      expect(saNode.latencyFormatted, equals('-- ms')); // 嚴格未測速顯示 '-- ms'，絕非寫死 42ms
    });

    test('近距離避讓判斷：台灣/香港節點與本機點距離極近，觸發向上拉開', () {
      final originP = WorldGeoCoordinates.originClient.mapOffset; // (0.785, 0.465)
      final twP = WorldGeoCoordinates.items['TW']!.mapOffset; // (0.808, 0.455)
      final hkP = WorldGeoCoordinates.items['HK']!.mapOffset; // (0.785, 0.465)
      final usP = WorldGeoCoordinates.items['US']!.mapOffset; // (0.180, 0.360)

      // 換算為 350x200 畫布距離
      final distTw = Offset((twP.dx - originP.dx) * 350, (twP.dy - originP.dy) * 200).distance;
      final distHk = Offset((hkP.dx - originP.dx) * 350, (hkP.dy - originP.dy) * 200).distance;
      final distUs = Offset((usP.dx - originP.dx) * 350, (usP.dy - originP.dy) * 200).distance;

      expect(distTw < 65.0, isTrue, reason: '台灣節點應觸發近距離智慧避讓');
      expect(distHk < 65.0, isTrue, reason: '香港節點應觸發近距離智慧避讓');
      expect(distUs > 65.0, isTrue, reason: '美國節點為正常遠距連線');
    });
  });
}
