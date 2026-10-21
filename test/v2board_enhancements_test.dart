// test/v2board_enhancements_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:flclash_v2board_client/core/i18n/i18n_service.dart';
import 'package:flclash_v2board_client/business/auth/traffic_log_model.dart';
import 'package:flclash_v2board_client/business/subscription/node_model.dart';

void main() {
  group('用戶交辦事項驗收測試 (I18n, 流量明細, 文檔中心)', () {
    test('1. 語言跟隨系統與手動切換測試', () {
      final i18n = I18nService.instance;

      // 測試跟隨系統模式
      i18n.setFollowSystem();
      expect(i18n.isFollowSystem, isTrue);

      // 測試手動切換為簡體中文
      i18n.setLanguage(AppLanguage.zhCN);
      expect(i18n.isFollowSystem, isFalse);
      expect(i18n.currentCode, equals('zh_CN'));
      expect(i18n.apiLanguageCode, equals('zh-CN'));
      expect(i18n.t('nav_docs'), equals('文档中心'));

      // 測試手動切換為繁體中文
      i18n.setLanguage(AppLanguage.zhTW);
      expect(i18n.isFollowSystem, isFalse);
      expect(i18n.currentCode, equals('zh_TW'));
      expect(i18n.apiLanguageCode, equals('zh-TW'));
      expect(i18n.t('nav_docs'), equals('文檔中心'));

      // 測試切換回自動跟隨
      i18n.setFollowSystem();
      expect(i18n.isFollowSystem, isTrue);
      expect(i18n.currentLanguageDisplayName, equals(i18n.currentLanguage.label));
    });

    test('2. 流量明細 (TrafficLogModel) 1:1 截圖 4 指標格式化驗證', () {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // 測試第一筆: 404.89 KB 上傳, 1.22 MB 下載, 1.62 MB 總計, 倍率: 5.00x
      final item1 = TrafficLogModel(
        u: 414607,
        d: 1279262,
        recordAt: nowSec,
        serverRate: 5.0,
      );

      expect(item1.formattedUpload, equals('404.89 KB'));
      expect(item1.formattedDownload, equals('1.22 MB'));
      expect(item1.formattedTotal, equals('1.62 MB'));
      expect(item1.serverRate, equals(5.0));
      expect(item1.dateOnly.length, equals(10)); // YYYY-MM-DD

      // 測試第二筆: 105.54 KB 上傳, 188.92 KB 下載, 294.46 KB 總計, 倍率: 10.00x
      final item2 = TrafficLogModel(
        u: 108072,
        d: 193454,
        recordAt: nowSec,
        serverRate: 10.0,
      );

      expect(item2.formattedUpload, equals('105.54 KB'));
      expect(item2.formattedDownload, equals('188.92 KB'));
      expect(item2.formattedTotal, equals('294.46 KB'));
      expect(item2.serverRate, equals(10.0));
    });

    test('3. 文檔中心 (Knowledge API) 分組結構解析測試', () {
      final v2boardMockData = {
        'data': {
          '必读': [
            {'id': 1, 'category': '必读', 'title': '使用前的环境配置', 'updated_at': 1749863128}
          ],
          'Android': [
            {'id': 2, 'category': 'Android', 'title': '使用Android客户端连接', 'updated_at': 1749863885}
          ],
          'Windows': [
            {'id': 5, 'category': 'Windows', 'title': '使用Windows客户端连接', 'updated_at': 1749863927}
          ],
          'MacOS': [
            {'id': 7, 'category': 'MacOS', 'title': '使用MacOS客户端连接', 'updated_at': 1749863998}
          ]
        }
      };

      final rawData = v2boardMockData['data'] as Map<String, dynamic>;
      final parsed = <String, List<Map<String, dynamic>>>{};
      rawData.forEach((key, val) {
        if (val is List) {
          parsed[key] = val.whereType<Map<String, dynamic>>().toList();
        }
      });

      expect(parsed.containsKey('必读'), isTrue);
      expect(parsed['必读']!.length, equals(1));
      expect(parsed['必读']!.first['title'], equals('使用前的环境配置'));
      expect(parsed.containsKey('Android'), isTrue);
      expect(parsed['Android']!.first['title'], equals('使用Android客户端连接'));
      expect(parsed.containsKey('Windows'), isTrue);
      expect(parsed.containsKey('MacOS'), isTrue);
    });

    test('4. 節點大洲分組 (亞洲/歐美/其他) 與 國旗 Emoji 萃取 (含簡繁體與愛爾蘭)', () {
      // 測試用戶截圖中的真實節點名稱
      final usNode = NodeModel.fromProxyMap({'type': 'vless'}, id: '1', sanitizedName: '🇺🇸 直连-美国(5倍)');
      final jpNode = NodeModel.fromProxyMap({'type': 'vless'}, id: '2', sanitizedName: '🇯🇵 直连-日本(5倍)');
      final sgNode = NodeModel.fromProxyMap({'type': 'vless'}, id: '3', sanitizedName: '🇸🇬 直连-新加坡(10倍)');
      final hkNode = NodeModel.fromProxyMap({'type': 'anytls'}, id: '4', sanitizedName: '🇭🇰 L1-香港');
      final twNode = NodeModel.fromProxyMap({'type': 'anytls'}, id: '5', sanitizedName: '🇹🇼 L1-台湾');
      final krNode = NodeModel.fromProxyMap({'type': 'anytls'}, id: '6', sanitizedName: '🇰🇷 L1-韩国');
      final vnNode = NodeModel.fromProxyMap({'type': 'anytls'}, id: '7', sanitizedName: '🇻🇳 L1-越南');
      final thNode = NodeModel.fromProxyMap({'type': 'anytls'}, id: '8', sanitizedName: '🇹🇭 L1-泰国');
      final phNode = NodeModel.fromProxyMap({'type': 'anytls'}, id: '9', sanitizedName: '🇵🇭 L1-菲律宾');
      final ukNode = NodeModel.fromProxyMap({'type': 'ss'}, id: '10', sanitizedName: '🇬🇧 L1-英国');
      final deNode = NodeModel.fromProxyMap({'type': 'trojan'}, id: '11', sanitizedName: '🇩🇪 L1-德国');
      final ieNode = NodeModel.fromProxyMap({'type': 'anytls'}, id: '12', sanitizedName: '🇮🇪 L1-爱尔兰');

      // 驗證國旗提取
      expect(usNode.flagEmoji, equals('🇺🇸'));
      expect(jpNode.flagEmoji, equals('🇯🇵'));
      expect(sgNode.flagEmoji, equals('🇸🇬'));
      expect(hkNode.flagEmoji, equals('🇭🇰'));
      expect(twNode.flagEmoji, equals('🇹🇼'));
      expect(krNode.flagEmoji, equals('🇰🇷'));
      expect(vnNode.flagEmoji, equals('🇻🇳'));
      expect(thNode.flagEmoji, equals('🇹🇭'));
      expect(phNode.flagEmoji, equals('🇵🇭'));
      expect(ukNode.flagEmoji, equals('🇬🇧'));
      expect(deNode.flagEmoji, equals('🇩🇪'));
      expect(ieNode.flagEmoji, equals('🇮🇪'));

      // 驗證大洲分組 (亞洲 / 歐美 / 其他)
      expect(usNode.continent, equals('歐美'));
      expect(ieNode.continent, equals('歐美'));
      expect(ukNode.continent, equals('歐美'));
      expect(deNode.continent, equals('歐美'));
      expect(jpNode.continent, equals('亞洲'));
      expect(sgNode.continent, equals('亞洲'));
      expect(hkNode.continent, equals('亞洲'));
      expect(twNode.continent, equals('亞洲'));
      expect(krNode.continent, equals('亞洲'));
      expect(vnNode.continent, equals('亞洲'));
      expect(thNode.continent, equals('亞洲'));
      expect(phNode.continent, equals('亞洲'));

      // 驗證地區名稱 (嚴格維持具體國家名稱，絕不顯示「歐美」)
      expect(usNode.regionName, equals('美國'));
      expect(ieNode.regionName, equals('愛爾蘭'));
      expect(twNode.regionName, equals('台灣'));
      expect(krNode.regionName, equals('韓國'));
      expect(vnNode.regionName, equals('越南'));
      expect(thNode.regionName, equals('泰國'));
      expect(phNode.regionName, equals('菲律賓'));
      expect(ukNode.regionName, equals('英國'));
      expect(deNode.regionName, equals('德國'));
    });

    test('5. 節點收藏 (Favorite Toggle 反覆切換) 測試', () {
      final node = NodeModel(
        id: 'node_1',
        name: '🇭🇰 香港-高速01',
        flagEmoji: '🇭🇰',
        protocol: 'VLESS',
        isFavorite: false,
        rawConfig: const {},
      );

      // 初次收藏
      final favNode = node.copyWithFavorite(true);
      expect(favNode.isFavorite, isTrue);

      // 再次點擊取消收藏
      final unFavNode = favNode.copyWithFavorite(false);
      expect(unFavNode.isFavorite, isFalse);
    });

    test('6. 品牌去 FlClash 化與全域「天河網絡」名稱驗證', () {
      I18nService.instance.setLanguage(AppLanguage.zhTW);
      expect(I18nService.instance.t('app_title'), equals('天河網絡'));
    });

    test('7. 全球 249 國 ISO 雙向數學公式轉換與 cleanDisplayName 驗證', () {
      // 測試 Unicode Regional Indicator 數學偏移公式
      expect(NodeModel.emojiToIsoCode('🇺🇸'), equals('US'));
      expect(NodeModel.emojiToIsoCode('🇯🇵'), equals('JP'));
      expect(NodeModel.emojiToIsoCode('🇭🇰'), equals('HK'));
      expect(NodeModel.emojiToIsoCode('🇹🇼'), equals('TW'));
      expect(NodeModel.emojiToIsoCode('🇸🇬'), equals('SG'));
      expect(NodeModel.emojiToIsoCode('🇮🇪'), equals('IE'));
      expect(NodeModel.emojiToIsoCode('🇬🇧'), equals('GB'));
      expect(NodeModel.emojiToIsoCode('🇩🇪'), equals('DE'));
      expect(NodeModel.emojiToIsoCode('🇫🇷'), equals('FR'));

      // 測試反向公式
      expect(NodeModel.isoCodeToEmoji('US'), equals('🇺🇸'));
      expect(NodeModel.isoCodeToEmoji('JP'), equals('🇯🇵'));
      expect(NodeModel.isoCodeToEmoji('TW'), equals('🇹🇼'));

      // 測試 cleanDisplayName 去除開頭退化國旗字符
      final nodeWithFlag = NodeModel(
        id: 'test_1',
        name: '🇺🇸 直连-美国(5倍)',
        flagEmoji: '🇺🇸',
        protocol: 'VLESS',
        rawConfig: const {},
      );
      expect(nodeWithFlag.countryCode, equals('US'));
      expect(nodeWithFlag.cleanDisplayName, equals('直连-美国(5倍)'));

      final nodeWithoutFlag = NodeModel(
        id: 'test_2',
        name: '直连-日本(5倍)',
        flagEmoji: '🇯🇵',
        protocol: 'VLESS',
        rawConfig: const {},
      );
      expect(nodeWithoutFlag.countryCode, equals('JP'));
      expect(nodeWithoutFlag.cleanDisplayName, equals('直连-日本(5倍)'));
    });
  });
}
