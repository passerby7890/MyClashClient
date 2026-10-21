// lib/core/geo/world_geo_coordinates.dart
// 涵蓋全球 249 個 ISO 3166-1 國家與屬地之高精準經緯度資料庫與底圖校準投影引擎

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../business/subscription/node_model.dart';

/// 全球地理節點元數據模型
class WorldGeoItem {
  final String iso; // ISO 3166-1 alpha-2 兩碼 (例如 'TW', 'JP')
  final String name; // 繁體中文標準名稱 (例如 '台灣', '日本')
  final String flag; // Unicode 國旗 Emoji (例如 '🇹🇼', '🇯🇵')
  final double lat; // 緯度 (-90.0 ~ +90.0)
  final double lng; // 經度 (-180.0 ~ +180.0)
  final Offset? visualAnchor; // 針對 world_map_holo.png 之像素級微調錨點

  const WorldGeoItem({
    required this.iso,
    required this.name,
    required this.flag,
    required this.lat,
    required this.lng,
    this.visualAnchor,
  });

  /// 取得在 world_map_holo.png (1800x984) 畫布上的精準歸一化座標 (0.0 ~ 1.0)
  Offset get mapOffset {
    if (visualAnchor != null) {
      return visualAnchor!;
    }
    return WorldGeoCoordinates.projectLatLngToMapOffset(lat, lng);
  }

  /// 取得地圖精確 Offset (相容別名)
  Offset toPreciseMapOffset() => mapOffset;
}

/// 全球 249 國 ISO 經緯度投影 + 座標定位引擎
class WorldGeoCoordinates {
  WorldGeoCoordinates._();

  // 預設本機用戶發起點 (東亞華南/香港/台灣近海)
  static const WorldGeoItem originClient = WorldGeoItem(
    iso: 'USER',
    name: '本機用戶',
    flag: '📍',
    lat: 23.1,
    lng: 113.3,
    visualAnchor: Offset(0.785, 0.465),
  );

  /// 核心投影演算法：將真實 (lat, lng) 精準映射至 world_map_holo.png 歸一化座標 (0.0 ~ 1.0)
  static Offset projectLatLngToMapOffset(double lat, double lng) {
    // 1. 經度線性校準: 本初子午線 x ≈ 0.4863, 涵蓋 -180° ~ +180°
    final double rawX = 0.4863 + (lng / 360.0) * 0.9425;
    final double clampedX = rawX.clamp(0.065, 0.935);

    // 2. 緯度投影校準 (以赤道 0° 對應 y ≈ 0.585，南北半球非線性平滑映射)
    final double clampedLat = lat.clamp(-58.0, 78.0);
    double rawY;
    if (clampedLat >= 0) {
      // 北半球: 0° -> 0.585, +78° -> 0.120
      final ratio = clampedLat / 78.0;
      final t = math.pow(ratio, 0.92).toDouble();
      rawY = 0.585 - t * (0.585 - 0.120);
    } else {
      // 南半球: 0° -> 0.585, -58° -> 0.880
      final ratio = (-clampedLat) / 58.0;
      final t = math.pow(ratio, 0.95).toDouble();
      rawY = 0.585 + t * (0.880 - 0.585);
    }
    final double clampedY = rawY.clamp(0.120, 0.880);

    return Offset(clampedX, clampedY);
  }

  /// 透過 Unicode Regional Indicator 數學反解任何國旗 Emoji 為 ISO 兩碼
  static String? emojiToIso(String emoji) {
    if (emoji.isEmpty) return null;
    final runes = emoji.runes.toList();
    if (runes.length >= 2 &&
        runes[0] >= 0x1F1E6 && runes[0] <= 0x1F1FF &&
        runes[1] >= 0x1F1E6 && runes[1] <= 0x1F1FF) {
      final c1 = String.fromCharCode(runes[0] - 0x1F1E6 + 65);
      final c2 = String.fromCharCode(runes[1] - 0x1F1E6 + 65);
      return '$c1$c2';
    }
    return null;
  }

  /// 透過 ISO 兩碼計算出標準國旗 Emoji
  static String isoToEmoji(String iso) {
    if (iso.length != 2) return '🌐';
    final upper = iso.toUpperCase();
    final c1 = upper.codeUnitAt(0) - 65 + 0x1F1E6;
    final c2 = upper.codeUnitAt(1) - 65 + 0x1F1E6;
    return String.fromCharCode(c1) + String.fromCharCode(c2);
  }

  /// 依據 ISO 兩碼直接取得國家地理資訊
  static WorldGeoItem? getByIso(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    return items[iso.toUpperCase()];
  }

  /// 智慧全方位推導節點地理資訊 (全球 249 國 100% 精準定位)
  static WorldGeoItem resolve(NodeModel? node) {
    if (node == null) return items['HK']!;

    // 1. 優先嘗試從節點名稱或 flagEmoji 提取國旗 Emoji (透過 Unicode 數學反解)
    if (node.flagEmoji.isNotEmpty && node.flagEmoji != '🌐') {
      final fromFlag = emojiToIso(node.flagEmoji);
      if (fromFlag != null && items.containsKey(fromFlag.toUpperCase())) {
        return items[fromFlag.toUpperCase()]!;
      }
    }

    final flagRegex = RegExp(r'[\uD83C][\uDDE6-\uDDFF][\uD83C][\uDDE6-\uDDFF]');
    final match = flagRegex.firstMatch(node.name);
    if (match != null) {
      final fromMatch = emojiToIso(match.group(0)!);
      if (fromMatch != null && items.containsKey(fromMatch.toUpperCase())) {
        return items[fromMatch.toUpperCase()]!;
      }
    }

    // 2. 多語系別名與全球機房城市詞典解析 (不依賴 Emoji，純文字直接辨識)
    final fromAlias = resolveIsoFromAlias(node.name);
    if (fromAlias != null && items.containsKey(fromAlias)) {
      return items[fromAlias]!;
    }

    // 3. 檢查 node.countryCode (若非預設或已辨識)
    final nodeIso = node.countryCode.toUpperCase();
    if (nodeIso.isNotEmpty && items.containsKey(nodeIso)) {
      return items[nodeIso]!;
    }

    // 4. 兜底香港
    return items['HK']!;
  }

  /// 多語系國家名稱與熱門機房城市反查 ISO 兩碼
  static String? resolveIsoFromAlias(String text) {
    final lower = text.toLowerCase();
    for (final entry in cityAndCountryAliases.entries) {
      for (final kw in entry.value) {
        if (lower.contains(kw)) return entry.key;
      }
    }
    return null;
  }

  // ==========================================
  // 全球熱門機房城市與多語系國家別名庫
  // ==========================================
  static const Map<String, List<String>> cityAndCountryAliases = {
    'TW': ['台灣', '台湾', 'taiwan', 'tw', '台北', '臺北', '台中', '臺中', '高雄', 'taipei'],
    'HK': ['香港', 'hong kong', 'hongkong', 'hk', '九龍', '九龙', '中環', '中环'],
    'MO': ['澳門', '澳门', 'macau', 'mo'],
    'JP': ['日本', 'japan', 'jp', '東京', '东京', '大阪', 'osaka', 'tokyo', '名古屋', '橫濱', '横滨', '福岡', '福冈'],
    'KR': ['韓國', '韩国', 'korea', 'kr', '首爾', '首尔', 'seoul', '釜山', '仁川'],
    'SG': ['新加坡', 'singapore', 'sg', '獅城', '狮城'],
    'US': ['美國', '美国', 'united states', 'usa', 'us', '矽谷', '硅谷', '洛杉磯', '洛杉矶', '聖何塞', '圣何塞', '舊金山', '旧金山', '西雅圖', '西雅图', '芝加哥', '達拉斯', '达拉斯', '紐約', '纽约', '波特蘭', '波特兰', '鳳凰城', '凤凰城', '邁阿密', '迈阿密', 'san jose', 'silicon valley', 'los angeles', 'new york', 'seattle', 'chicago', 'dallas'],
    'GB': ['英國', '英国', 'united kingdom', 'uk', 'great britain', 'gb', '倫敦', '伦敦', 'london', '曼徹斯特', '曼彻斯特', 'manchester'],
    'DE': ['德國', '德国', 'germany', 'de', '法蘭克福', '法兰克福', 'frankfurt', '柏林', 'berlin', '慕尼黑', 'munich'],
    'FR': ['法國', '法国', 'france', 'fr', '巴黎', 'paris', '馬賽', '马赛', 'marseille'],
    'NL': ['荷蘭', '荷兰', 'netherlands', 'nl', '阿姆斯特丹', 'amsterdam', '鹿特丹', 'rotterdam'],
    'IE': ['愛爾蘭', '爱尔兰', 'ireland', 'ie', '都柏林', 'dublin'],
    'CA': ['加拿大', 'canada', 'ca', '溫哥華', '温哥华', '多倫多', '多伦多', '蒙特婁', '蒙特利尔', 'vancouver', 'toronto', 'montreal'],
    'AU': ['澳洲', '澳大利亞', '澳大利亚', 'australia', 'au', '雪梨', '悉尼', 'sydney', '墨爾本', '墨尔本', 'melbourne', '布里斯本', '布里斯班', 'brisbane'],
    'RU': ['俄羅斯', '俄罗斯', 'russia', 'ru', '莫斯科', 'moscow', '聖彼得堡', '圣彼得堡', '符拉迪沃斯托克', '海參崴'],
    'CH': ['瑞士', 'switzerland', 'ch', '蘇黎世', '苏黎世', 'zurich', '日內瓦', '日内瓦', 'geneva'],
    'IN': ['印度', 'india', 'in', '孟買', '孟买', 'mumbai', '德里', '新德里', 'delhi', '班加羅爾', '班加罗尔', 'bangalore'],
    'VN': ['越南', 'vietnam', 'vn', '胡志明', '河內', '河内', 'ho chi minh', 'hanoi'],
    'TH': ['泰國', '泰国', 'thailand', 'th', '曼谷', 'bangkok'],
    'MY': ['馬來西亞', '马来西亚', 'malaysia', 'my', '吉隆坡', 'kuala lumpur'],
    'PH': ['菲律賓', '菲律宾', 'philippines', 'ph', '馬尼拉', '马尼拉', 'manila'],
    'ID': ['印尼', '印度尼西亞', '印度尼西亚', 'indonesia', 'id', '雅加達', '雅加达', 'jakarta'],
    'AE': ['阿聯酋', '阿联酋', 'uae', 'ae', '杜拜', '迪拜', 'dubai', '阿布達比', '阿布扎比', 'abu dhabi'],
    'SA': ['沙烏地阿拉伯', '沙特阿拉伯', 'saudi arabia', 'sa', '利雅德', '利雅得', 'riyadh'],
    'TR': ['土耳其', 'turkey', 'tr', '伊斯坦堡', '伊斯坦布尔', 'istanbul', '安卡拉', 'ankara'],
    'BR': ['巴西', 'brazil', 'br', '聖保羅', '圣保罗', 'sao paulo', '里約', '里约', 'rio'],
    'AR': ['阿根廷', 'argentina', 'ar', '布宜諾斯艾利斯', '布宜诺斯艾利斯', 'buenos aires'],
    'NZ': ['紐西蘭', '新西兰', 'new zealand', 'nz', '奧克蘭', '奥克兰', 'auckland', '惠靈頓', '惠灵顿', 'wellington'],
    'ZA': ['南非', 'south africa', 'za', '約翰尼斯堡', '约翰内斯堡', 'johannesburg', '開普敦', '开普敦', 'cape town'],
    'IS': ['冰島', '冰岛', 'iceland', 'is', '雷克雅維克', '雷克雅未克', 'reykjavik'],
    'NO': ['挪威', 'norway', 'no', '奧斯陸', '奥斯陆', 'oslo'],
    'SE': ['瑞典', 'sweden', 'se', '斯德哥爾摩', '斯德哥尔摩', 'stockholm'],
    'FI': ['芬蘭', '芬兰', 'finland', 'fi', '赫爾辛基', '赫尔辛基', 'helsinki'],
    'DK': ['丹麥', '丹麦', 'denmark', 'dk', '哥本哈根', 'copenhagen'],
    'IT': ['義大利', '意大利', 'italy', 'it', '米蘭', '米兰', 'milan', '羅馬', '罗马', 'rome'],
    'ES': ['西班牙', 'spain', 'es', '馬德里', '马德里', 'madrid', '巴塞隆納', '巴塞罗那', 'barcelona'],
    'PT': ['葡萄牙', 'portugal', 'pt', '里斯本', 'lisbon'],
    'PL': ['波蘭', '波兰', 'poland', 'pl', '華沙', '华沙', 'warsaw'],
    'UA': ['烏克蘭', '乌克兰', 'ukraine', 'ua', '基輔', '基辅', 'kyiv', 'kiev'],
    'AT': ['奧地利', '奥地利', 'austria', 'at', '維也納', '维也纳', 'vienna'],
    'BE': ['比利時', '比利时', 'belgium', 'be', '布魯塞爾', '布鲁塞尔', 'brussels'],
    'CZ': ['捷克', 'czech', 'cz', '布拉格', 'prague'],
    'GR': ['希臘', '希腊', 'greece', 'gr', '雅典', 'athens'],
    'IL': ['以色列', 'israel', 'il', '特拉維夫', '特拉维夫', 'tel aviv'],
    'CL': ['智利', 'chile', 'cl', '聖地牙哥', '圣地亚哥', 'santiago'],
    'CO': ['哥倫比亞', '哥伦比亚', 'colombia', 'co', '波哥大', 'bogota'],
    'MX': ['墨西哥', 'mexico', 'mx', '墨西哥城', 'mexico city'],
    'EG': ['埃及', 'egypt', 'eg', '開羅', '开罗', 'cairo'],
    'NG': ['奈及利亞', '尼日利亚', 'nigeria', 'ng', '拉哥斯', '拉各斯', 'lagos'],
    'KZ': ['哈薩克', '哈萨克斯坦', 'kazakhstan', 'kz', '阿拉木圖', '阿拉木图', 'almaty'],
    'PK': ['巴基斯坦', 'pakistan', 'pk', '卡拉奇', 'karachi'],
    'RO': ['羅馬尼亞', '罗马尼亚', 'romania', 'ro', '布加勒斯特', 'bucharest'],
    'HU': ['匈牙利', 'hungary', 'hu', '布達佩斯', '布达佩斯', 'budapest'],
    'BG': ['保加利亞', '保加利亚', 'bulgaria', 'bg', '索菲亞', '索菲亚', 'sofia'],
    'RS': ['塞爾維亞', '塞尔维亚', 'serbia', 'rs', '貝爾格勒', '贝尔格莱德', 'belgrade'],
    'HR': ['克羅埃西亞', '克罗地亚', 'croatia', 'hr', '札格瑞布', '萨格勒布', 'zagreb'],
    'SK': ['斯洛伐克', 'slovakia', 'sk', '布拉提斯拉瓦', '布拉迪斯拉发', 'bratislava'],
    'SI': ['斯洛維尼亞', '斯洛文尼亚', 'slovenia', 'si', '盧比安納', '卢布尔雅那', 'ljubljana'],
    'EE': ['愛沙尼亞', '爱沙尼亚', 'estonia', 'ee', '塔林', 'tallinn'],
    'LV': ['拉脫維亞', '拉脱维亚', 'latvia', 'lv', '里加', 'riga'],
    'LT': ['立陶宛', 'lithuania', 'lt', '維爾紐斯', '维尔纽斯', 'vilnius'],
    'CY': ['賽普勒斯', '塞浦路斯', 'cyprus', 'cy', '尼古西亞', '尼科西亚', 'nicosia'],
    'LU': ['盧森堡', '卢森堡', 'luxembourg', 'lu'],
    'MT': ['馬爾他', '马耳他', 'malta', 'mt'],
    'QA': ['卡達', '卡塔尔', 'qatar', 'qa', '杜哈', '多哈', 'doha'],
    'KW': ['科威特', 'kuwait', 'kw'],
    'KH': ['柬埔寨', 'cambodia', 'kh', '金邊', '金边', 'phnom penh'],
    'MM': ['緬甸', '缅甸', 'myanmar', 'mm', '仰光', 'yangon'],
    'MN': ['蒙古', 'mongolia', 'mn', '烏蘭巴托', '乌兰巴托', 'ulaanbaatar'],
    'PA': ['巴拿馬', '巴拿马', 'panama', 'pa'],
    'CR': ['哥斯大黎加', '哥斯达黎加', 'costa rica', 'cr'],
    'UY': ['烏拉圭', '乌拉圭', 'uruguay', 'uy', '蒙得維的亞', '蒙得维的亚', 'montevideo'],
    'PE': ['秘魯', '秘鲁', 'peru', 'pe', '利馬', '利马', 'lima'],
    'EC': ['厄瓜多', '厄瓜多尔', 'ecuador', 'ec', '基多', 'quito'],
    'GU': ['關島', '关岛', 'guam', 'gu'],
    'LK': ['斯里蘭卡', '斯里兰卡', 'sri lanka', 'lk', '可倫坡', '科伦坡', 'colombo'],
    'BD': ['孟加拉', 'bangladesh', 'bd', '達卡', '达卡', 'dhaka'],
    'NP': ['尼泊爾', '尼泊尔', 'nepal', 'np', '加德滿都', '加德满都', 'kathmandu'],
    'UZ': ['烏茲別克', '乌兹别克斯坦', 'uzbekistan', 'uz', '塔什干', 'tashkent'],
    'MA': ['摩洛哥', 'morocco', 'ma', '卡薩布蘭卡', '卡萨布兰卡', 'casablanca', '拉巴特', 'rabat'],
    'DZ': ['阿爾及利亞', '阿尔及利亚', 'algeria', 'dz'],
    'TN': ['突尼西亞', '突尼斯', 'tunisia', 'tn'],
    'KE': ['肯亞', '肯尼亚', 'kenya', 'ke', '奈洛比', '内罗毕', 'nairobi'],
    'GH': ['迦納', '加纳', 'ghana', 'gh', '阿克拉', 'accra']
  };

  // ==========================================
  // 全球 249 個 ISO 3166-1 國家/屬地經緯度資料庫
  // ==========================================
  static const Map<String, WorldGeoItem> items = {
    'AD': WorldGeoItem(iso: 'AD', name: '安道爾', flag: '🇦🇩', lat: 42.5, lng: 1.5),
    'AE': WorldGeoItem(iso: 'AE', name: '阿聯酋', flag: '🇦🇪', lat: 24.4, lng: 54.3, visualAnchor: Offset(0.640, 0.450)),
    'AF': WorldGeoItem(iso: 'AF', name: '阿富汗', flag: '🇦🇫', lat: 33.9, lng: 67.7),
    'AG': WorldGeoItem(iso: 'AG', name: '安地卡及巴布達', flag: '🇦🇬', lat: 17.0, lng: -61.8),
    'AI': WorldGeoItem(iso: 'AI', name: '安圭拉', flag: '🇦🇮', lat: 18.2, lng: -63.0),
    'AL': WorldGeoItem(iso: 'AL', name: '阿爾巴尼亞', flag: '🇦🇱', lat: 41.3, lng: 19.8),
    'AM': WorldGeoItem(iso: 'AM', name: '亞美尼亞', flag: '🇦🇲', lat: 40.1, lng: 45.0),
    'AO': WorldGeoItem(iso: 'AO', name: '安哥拉', flag: '🇦🇴', lat: -11.2, lng: 17.8),
    'AQ': WorldGeoItem(iso: 'AQ', name: '南極洲', flag: '🇦🇶', lat: -75.2, lng: 0.0),
    'AR': WorldGeoItem(iso: 'AR', name: '阿根廷', flag: '🇦🇷', lat: -38.4, lng: -63.6, visualAnchor: Offset(0.315, 0.795)),
    'AS': WorldGeoItem(iso: 'AS', name: '美屬薩摩亞', flag: '🇦🇸', lat: -14.3, lng: -170.7),
    'AT': WorldGeoItem(iso: 'AT', name: '奧地利', flag: '🇦🇹', lat: 47.5, lng: 14.5, visualAnchor: Offset(0.525, 0.300)),
    'AU': WorldGeoItem(iso: 'AU', name: '澳洲', flag: '🇦🇺', lat: -25.2, lng: 133.7, visualAnchor: Offset(0.885, 0.775)),
    'AW': WorldGeoItem(iso: 'AW', name: '阿路巴', flag: '🇦🇼', lat: 12.5, lng: -69.9),
    'AX': WorldGeoItem(iso: 'AX', name: '奧蘭群島', flag: '🇦🇽', lat: 60.1, lng: 19.9),
    'AZ': WorldGeoItem(iso: 'AZ', name: '亞塞拜然', flag: '🇦🇿', lat: 40.1, lng: 47.5),
    'BA': WorldGeoItem(iso: 'BA', name: '波士尼亞', flag: '🇧🇦', lat: 43.9, lng: 17.6),
    'BB': WorldGeoItem(iso: 'BB', name: '巴巴多斯', flag: '🇧🇧', lat: 13.1, lng: -59.5),
    'BD': WorldGeoItem(iso: 'BD', name: '孟加拉', flag: '🇧🇩', lat: 23.6, lng: 90.3),
    'BE': WorldGeoItem(iso: 'BE', name: '比利時', flag: '🇧🇪', lat: 50.5, lng: 4.4, visualAnchor: Offset(0.495, 0.285)),
    'BF': WorldGeoItem(iso: 'BF', name: '布吉納法索', flag: '🇧🇫', lat: 12.2, lng: -1.5),
    'BG': WorldGeoItem(iso: 'BG', name: '保加利亞', flag: '🇧🇬', lat: 42.7, lng: 25.4, visualAnchor: Offset(0.550, 0.325)),
    'BH': WorldGeoItem(iso: 'BH', name: '巴林', flag: '🇧🇭', lat: 26.0, lng: 50.5),
    'BI': WorldGeoItem(iso: 'BI', name: '蒲隆地', flag: '🇧🇮', lat: -3.3, lng: 29.9),
    'BJ': WorldGeoItem(iso: 'BJ', name: '貝南', flag: '🇧🇯', lat: 9.3, lng: 2.3),
    'BL': WorldGeoItem(iso: 'BL', name: '聖巴瑟米', flag: '🇧🇱', lat: 17.9, lng: -62.8),
    'BM': WorldGeoItem(iso: 'BM', name: '百慕達', flag: '🇧🇲', lat: 32.3, lng: -64.7),
    'BN': WorldGeoItem(iso: 'BN', name: '汶萊', flag: '🇧🇳', lat: 4.5, lng: 114.7),
    'BO': WorldGeoItem(iso: 'BO', name: '玻利維亞', flag: '🇧🇴', lat: -16.2, lng: -63.5),
    'BQ': WorldGeoItem(iso: 'BQ', name: '荷屬沙巴', flag: '🇧🇶', lat: 12.1, lng: -68.2),
    'BR': WorldGeoItem(iso: 'BR', name: '巴西', flag: '🇧🇷', lat: -14.2, lng: -51.9, visualAnchor: Offset(0.360, 0.690)),
    'BS': WorldGeoItem(iso: 'BS', name: '巴哈馬', flag: '🇧🇸', lat: 25.0, lng: -77.3),
    'BT': WorldGeoItem(iso: 'BT', name: '不丹', flag: '🇧🇹', lat: 27.5, lng: 90.4),
    'BV': WorldGeoItem(iso: 'BV', name: '布威島', flag: '🇧🇻', lat: -54.4, lng: 3.4),
    'BW': WorldGeoItem(iso: 'BW', name: '波札那', flag: '🇧🇼', lat: -22.3, lng: 24.6),
    'BY': WorldGeoItem(iso: 'BY', name: '白俄羅斯', flag: '🇧🇾', lat: 53.7, lng: 27.9),
    'BZ': WorldGeoItem(iso: 'BZ', name: '貝里斯', flag: '🇧🇿', lat: 17.1, lng: -88.4),
    'CA': WorldGeoItem(iso: 'CA', name: '加拿大', flag: '🇨🇦', lat: 56.1, lng: -106.3, visualAnchor: Offset(0.220, 0.250)),
    'CC': WorldGeoItem(iso: 'CC', name: '科科斯群島', flag: '🇨🇨', lat: -12.1, lng: 96.8),
    'CD': WorldGeoItem(iso: 'CD', name: '剛果民主共和國', flag: '🇨🇩', lat: -4.0, lng: 21.7),
    'CF': WorldGeoItem(iso: 'CF', name: '中非共和國', flag: '🇨🇫', lat: 6.6, lng: 20.9),
    'CG': WorldGeoItem(iso: 'CG', name: '剛果共和國', flag: '🇨🇬', lat: -0.2, lng: 15.8),
    'CH': WorldGeoItem(iso: 'CH', name: '瑞士', flag: '🇨🇭', lat: 46.8, lng: 8.2, visualAnchor: Offset(0.508, 0.305)),
    'CI': WorldGeoItem(iso: 'CI', name: '象牙海岸', flag: '🇨🇮', lat: 7.5, lng: -5.5),
    'CK': WorldGeoItem(iso: 'CK', name: '庫克群島', flag: '🇨🇰', lat: -21.2, lng: -159.7),
    'CL': WorldGeoItem(iso: 'CL', name: '智利', flag: '🇨🇱', lat: -35.6, lng: -71.5, visualAnchor: Offset(0.295, 0.795)),
    'CM': WorldGeoItem(iso: 'CM', name: '喀麥隆', flag: '🇨🇲', lat: 7.3, lng: 12.3),
    'CN': WorldGeoItem(iso: 'CN', name: '中國', flag: '🇨🇳', lat: 35.8, lng: 104.1, visualAnchor: Offset(0.755, 0.370)),
    'CO': WorldGeoItem(iso: 'CO', name: '哥倫比亞', flag: '🇨🇴', lat: 4.5, lng: -74.2, visualAnchor: Offset(0.285, 0.560)),
    'CR': WorldGeoItem(iso: 'CR', name: '哥斯大黎加', flag: '🇨🇷', lat: 9.7, lng: -83.7),
    'CU': WorldGeoItem(iso: 'CU', name: '古巴', flag: '🇨🇺', lat: 21.5, lng: -77.7),
    'CV': WorldGeoItem(iso: 'CV', name: '維德角', flag: '🇨🇻', lat: 16.5, lng: -23.0),
    'CW': WorldGeoItem(iso: 'CW', name: '庫拉索', flag: '🇨🇼', lat: 12.1, lng: -68.9),
    'CX': WorldGeoItem(iso: 'CX', name: '聖誕島', flag: '🇨🇽', lat: -10.4, lng: 105.6),
    'CY': WorldGeoItem(iso: 'CY', name: '賽普勒斯', flag: '🇨🇾', lat: 35.1, lng: 33.4, visualAnchor: Offset(0.575, 0.375)),
    'CZ': WorldGeoItem(iso: 'CZ', name: '捷克', flag: '🇨🇿', lat: 49.8, lng: 15.4, visualAnchor: Offset(0.525, 0.290)),
    'DE': WorldGeoItem(iso: 'DE', name: '德國', flag: '🇩🇪', lat: 51.1, lng: 10.4, visualAnchor: Offset(0.512, 0.288)),
    'DJ': WorldGeoItem(iso: 'DJ', name: '吉布地', flag: '🇩🇯', lat: 11.8, lng: 42.5),
    'DK': WorldGeoItem(iso: 'DK', name: '丹麥', flag: '🇩🇰', lat: 56.2, lng: 9.5, visualAnchor: Offset(0.510, 0.245)),
    'DM': WorldGeoItem(iso: 'DM', name: '多米尼克', flag: '🇩🇲', lat: 15.4, lng: -61.3),
    'DO': WorldGeoItem(iso: 'DO', name: '多明尼加', flag: '🇩🇴', lat: 18.7, lng: -70.1),
    'DZ': WorldGeoItem(iso: 'DZ', name: '阿爾及利亞', flag: '🇩🇿', lat: 28.0, lng: 1.6, visualAnchor: Offset(0.490, 0.420)),
    'EC': WorldGeoItem(iso: 'EC', name: '厄瓜多', flag: '🇪🇨', lat: -1.8, lng: -78.1),
    'EE': WorldGeoItem(iso: 'EE', name: '愛沙尼亞', flag: '🇪🇪', lat: 58.5, lng: 25.0, visualAnchor: Offset(0.550, 0.230)),
    'EG': WorldGeoItem(iso: 'EG', name: '埃及', flag: '🇪🇬', lat: 26.8, lng: 30.8, visualAnchor: Offset(0.570, 0.425)),
    'EH': WorldGeoItem(iso: 'EH', name: '西撒哈拉', flag: '🇪🇭', lat: 24.2, lng: -12.8),
    'ER': WorldGeoItem(iso: 'ER', name: '厄利垂亞', flag: '🇪🇷', lat: 15.1, lng: 39.7),
    'ES': WorldGeoItem(iso: 'ES', name: '西班牙', flag: '🇪🇸', lat: 40.4, lng: -3.7, visualAnchor: Offset(0.475, 0.345)),
    'ET': WorldGeoItem(iso: 'ET', name: '衣索比亞', flag: '🇪🇹', lat: 9.1, lng: 40.4),
    'FI': WorldGeoItem(iso: 'FI', name: '芬蘭', flag: '🇫🇮', lat: 61.9, lng: 25.7, visualAnchor: Offset(0.555, 0.200)),
    'FJ': WorldGeoItem(iso: 'FJ', name: '斐濟', flag: '🇫🇯', lat: -17.7, lng: 178.0),
    'FK': WorldGeoItem(iso: 'FK', name: '福克蘭群島', flag: '🇫🇰', lat: -51.7, lng: -59.5),
    'FM': WorldGeoItem(iso: 'FM', name: '密克羅尼西亞', flag: '🇫🇲', lat: 7.4, lng: 151.8),
    'FO': WorldGeoItem(iso: 'FO', name: '法羅群島', flag: '🇫🇴', lat: 61.8, lng: -6.9),
    'FR': WorldGeoItem(iso: 'FR', name: '法國', flag: '🇫🇷', lat: 46.2, lng: 2.2, visualAnchor: Offset(0.495, 0.305)),
    'GA': WorldGeoItem(iso: 'GA', name: '加彭', flag: '🇬🇦', lat: -0.8, lng: 11.6),
    'GB': WorldGeoItem(iso: 'GB', name: '英國', flag: '🇬🇧', lat: 55.3, lng: -3.4, visualAnchor: Offset(0.486, 0.280)),
    'GD': WorldGeoItem(iso: 'GD', name: '格瑞那達', flag: '🇬🇩', lat: 12.1, lng: -61.6),
    'GE': WorldGeoItem(iso: 'GE', name: '喬治亞', flag: '🇬🇪', lat: 42.3, lng: 43.3, visualAnchor: Offset(0.605, 0.330)),
    'GF': WorldGeoItem(iso: 'GF', name: '法屬圭亞那', flag: '🇬🇫', lat: 3.9, lng: -53.1),
    'GG': WorldGeoItem(iso: 'GG', name: '根西', flag: '🇬🇬', lat: 49.4, lng: -2.5),
    'GH': WorldGeoItem(iso: 'GH', name: '迦納', flag: '🇬🇭', lat: 7.9, lng: -1.0),
    'GI': WorldGeoItem(iso: 'GI', name: '直布羅陀', flag: '🇬🇮', lat: 36.1, lng: -5.3),
    'GL': WorldGeoItem(iso: 'GL', name: '格陵蘭', flag: '🇬🇱', lat: 71.7, lng: -42.6, visualAnchor: Offset(0.370, 0.140)),
    'GM': WorldGeoItem(iso: 'GM', name: '甘比亞', flag: '🇬🇲', lat: 13.4, lng: -15.3),
    'GN': WorldGeoItem(iso: 'GN', name: '幾內亞', flag: '🇬🇳', lat: 9.9, lng: -9.6),
    'GP': WorldGeoItem(iso: 'GP', name: '瓜地洛普', flag: '🇬🇵', lat: 16.2, lng: -61.5),
    'GQ': WorldGeoItem(iso: 'GQ', name: '赤道幾內亞', flag: '🇬🇶', lat: 1.6, lng: 10.2),
    'GR': WorldGeoItem(iso: 'GR', name: '希臘', flag: '🇬🇷', lat: 39.0, lng: 21.8, visualAnchor: Offset(0.545, 0.355)),
    'GS': WorldGeoItem(iso: 'GS', name: '南喬治亞', flag: '🇬🇸', lat: -54.4, lng: -36.5),
    'GT': WorldGeoItem(iso: 'GT', name: '瓜地馬拉', flag: '🇬🇹', lat: 15.7, lng: -90.2),
    'GU': WorldGeoItem(iso: 'GU', name: '關島', flag: '🇬🇺', lat: 13.4, lng: 144.7, visualAnchor: Offset(0.865, 0.500)),
    'GW': WorldGeoItem(iso: 'GW', name: '幾內亞比索', flag: '🇬🇼', lat: 11.8, lng: -15.1),
    'GY': WorldGeoItem(iso: 'GY', name: '蓋亞那', flag: '🇬🇾', lat: 4.8, lng: -58.9),
    'HK': WorldGeoItem(iso: 'HK', name: '香港', flag: '🇭🇰', lat: 22.3, lng: 114.1, visualAnchor: Offset(0.785, 0.465)),
    'HM': WorldGeoItem(iso: 'HM', name: '赫德島', flag: '🇭🇲', lat: -53.0, lng: 73.5),
    'HN': WorldGeoItem(iso: 'HN', name: '宏都拉斯', flag: '🇭🇳', lat: 15.2, lng: -86.2),
    'HR': WorldGeoItem(iso: 'HR', name: '克羅埃西亞', flag: '🇭🇷', lat: 45.1, lng: 15.2, visualAnchor: Offset(0.528, 0.315)),
    'HT': WorldGeoItem(iso: 'HT', name: '海地', flag: '🇭🇹', lat: 18.9, lng: -72.2),
    'HU': WorldGeoItem(iso: 'HU', name: '匈牙利', flag: '🇭🇺', lat: 47.1, lng: 19.5, visualAnchor: Offset(0.535, 0.300)),
    'ID': WorldGeoItem(iso: 'ID', name: '印尼', flag: '🇮🇩', lat: -0.7, lng: 113.9, visualAnchor: Offset(0.785, 0.605)),
    'IE': WorldGeoItem(iso: 'IE', name: '愛爾蘭', flag: '🇮🇪', lat: 53.4, lng: -8.2, visualAnchor: Offset(0.470, 0.278)),
    'IL': WorldGeoItem(iso: 'IL', name: '以色列', flag: '🇮🇱', lat: 31.0, lng: 34.8, visualAnchor: Offset(0.580, 0.400)),
    'IM': WorldGeoItem(iso: 'IM', name: '曼島', flag: '🇮🇲', lat: 54.2, lng: -4.5),
    'IN': WorldGeoItem(iso: 'IN', name: '印度', flag: '🇮🇳', lat: 20.5, lng: 78.9, visualAnchor: Offset(0.705, 0.435)),
    'IO': WorldGeoItem(iso: 'IO', name: '英屬印度洋領地', flag: '🇮🇴', lat: -6.3, lng: 71.8),
    'IQ': WorldGeoItem(iso: 'IQ', name: '伊拉克', flag: '🇮🇶', lat: 33.2, lng: 43.6),
    'IR': WorldGeoItem(iso: 'IR', name: '伊朗', flag: '🇮🇷', lat: 32.4, lng: 53.6, visualAnchor: Offset(0.628, 0.385)),
    'IS': WorldGeoItem(iso: 'IS', name: '冰島', flag: '🇮🇸', lat: 64.9, lng: -19.0, visualAnchor: Offset(0.435, 0.180)),
    'IT': WorldGeoItem(iso: 'IT', name: '義大利', flag: '🇮🇹', lat: 41.8, lng: 12.5, visualAnchor: Offset(0.518, 0.335)),
    'JE': WorldGeoItem(iso: 'JE', name: '澤西', flag: '🇯🇪', lat: 49.2, lng: -2.1),
    'JM': WorldGeoItem(iso: 'JM', name: '牙買加', flag: '🇯🇲', lat: 18.1, lng: -77.2),
    'JO': WorldGeoItem(iso: 'JO', name: '約旦', flag: '🇯🇴', lat: 30.5, lng: 36.2),
    'JP': WorldGeoItem(iso: 'JP', name: '日本', flag: '🇯🇵', lat: 36.2, lng: 138.2, visualAnchor: Offset(0.846, 0.345)),
    'KE': WorldGeoItem(iso: 'KE', name: '肯亞', flag: '🇰🇪', lat: -0.0, lng: 37.9),
    'KG': WorldGeoItem(iso: 'KG', name: '吉爾吉斯', flag: '🇰🇬', lat: 41.2, lng: 74.7),
    'KH': WorldGeoItem(iso: 'KH', name: '柬埔寨', flag: '🇰🇭', lat: 12.5, lng: 104.9, visualAnchor: Offset(0.765, 0.505)),
    'KI': WorldGeoItem(iso: 'KI', name: '吉里巴斯', flag: '🇰🇮', lat: -3.3, lng: -168.7),
    'KM': WorldGeoItem(iso: 'KM', name: '葛摩', flag: '🇰🇲', lat: -11.8, lng: 43.8),
    'KN': WorldGeoItem(iso: 'KN', name: '聖克里斯多福', flag: '🇰🇳', lat: 17.3, lng: -62.7),
    'KP': WorldGeoItem(iso: 'KP', name: '北韓', flag: '🇰🇵', lat: 40.3, lng: 127.5),
    'KR': WorldGeoItem(iso: 'KR', name: '韓國', flag: '🇰🇷', lat: 35.9, lng: 127.7, visualAnchor: Offset(0.830, 0.345)),
    'KW': WorldGeoItem(iso: 'KW', name: '科威特', flag: '🇰🇼', lat: 29.3, lng: 47.4),
    'KY': WorldGeoItem(iso: 'KY', name: '開曼群島', flag: '🇰🇾', lat: 19.5, lng: -80.5),
    'KZ': WorldGeoItem(iso: 'KZ', name: '哈薩克', flag: '🇰🇿', lat: 48.0, lng: 66.9, visualAnchor: Offset(0.665, 0.280)),
    'LA': WorldGeoItem(iso: 'LA', name: '寮國', flag: '🇱🇦', lat: 19.8, lng: 102.4),
    'LB': WorldGeoItem(iso: 'LB', name: '黎巴嫩', flag: '🇱🇧', lat: 33.8, lng: 35.8),
    'LC': WorldGeoItem(iso: 'LC', name: '聖露西亞', flag: '🇱🇨', lat: 13.9, lng: -60.9),
    'LI': WorldGeoItem(iso: 'LI', name: '列支敦斯登', flag: '🇱🇮', lat: 47.1, lng: 9.5),
    'LK': WorldGeoItem(iso: 'LK', name: '斯里蘭卡', flag: '🇱🇰', lat: 7.8, lng: 80.7, visualAnchor: Offset(0.702, 0.535)),
    'LR': WorldGeoItem(iso: 'LR', name: '賴比瑞亞', flag: '🇱🇷', lat: 6.4, lng: -9.4),
    'LS': WorldGeoItem(iso: 'LS', name: '賴索托', flag: '🇱🇸', lat: -29.6, lng: 28.2),
    'LT': WorldGeoItem(iso: 'LT', name: '立陶宛', flag: '🇱🇹', lat: 55.1, lng: 23.8, visualAnchor: Offset(0.550, 0.255)),
    'LU': WorldGeoItem(iso: 'LU', name: '盧森堡', flag: '🇱🇺', lat: 49.8, lng: 6.1, visualAnchor: Offset(0.502, 0.292)),
    'LV': WorldGeoItem(iso: 'LV', name: '拉脫維亞', flag: '🇱🇻', lat: 56.8, lng: 24.6, visualAnchor: Offset(0.550, 0.245)),
    'LY': WorldGeoItem(iso: 'LY', name: '利比亞', flag: '🇱🇾', lat: 26.3, lng: 17.2, visualAnchor: Offset(0.530, 0.430)),
    'MA': WorldGeoItem(iso: 'MA', name: '摩洛哥', flag: '🇲🇦', lat: 31.7, lng: -7.0, visualAnchor: Offset(0.465, 0.400)),
    'MC': WorldGeoItem(iso: 'MC', name: '摩納哥', flag: '🇲🇨', lat: 43.7, lng: 7.4),
    'MD': WorldGeoItem(iso: 'MD', name: '摩爾多瓦', flag: '🇲🇩', lat: 47.4, lng: 28.3),
    'ME': WorldGeoItem(iso: 'ME', name: '蒙特內哥羅', flag: '🇲🇪', lat: 42.7, lng: 19.3),
    'MF': WorldGeoItem(iso: 'MF', name: '法屬聖馬丁', flag: '🇲🇫', lat: 18.0, lng: -63.0),
    'MG': WorldGeoItem(iso: 'MG', name: '馬達加斯加', flag: '🇲🇬', lat: -18.7, lng: 46.8),
    'MH': WorldGeoItem(iso: 'MH', name: '馬紹爾群島', flag: '🇲🇭', lat: 7.1, lng: 171.1),
    'MK': WorldGeoItem(iso: 'MK', name: '北馬其頓', flag: '🇲🇰', lat: 41.6, lng: 21.7),
    'ML': WorldGeoItem(iso: 'ML', name: '馬利', flag: '🇲🇱', lat: 17.5, lng: -3.9),
    'MM': WorldGeoItem(iso: 'MM', name: '緬甸', flag: '🇲🇲', lat: 21.9, lng: 95.9, visualAnchor: Offset(0.740, 0.465)),
    'MN': WorldGeoItem(iso: 'MN', name: '蒙古', flag: '🇲🇳', lat: 46.8, lng: 103.8, visualAnchor: Offset(0.760, 0.300)),
    'MO': WorldGeoItem(iso: 'MO', name: '澳門', flag: '🇲🇴', lat: 22.1, lng: 113.5, visualAnchor: Offset(0.780, 0.470)),
    'MP': WorldGeoItem(iso: 'MP', name: '北馬里亞納群島', flag: '🇲🇵', lat: 15.0, lng: 145.6),
    'MQ': WorldGeoItem(iso: 'MQ', name: '馬丁尼克', flag: '🇲🇶', lat: 14.6, lng: -61.0),
    'MR': WorldGeoItem(iso: 'MR', name: '茅利塔尼亞', flag: '🇲🇷', lat: 21.0, lng: -10.9),
    'MS': WorldGeoItem(iso: 'MS', name: '蒙哲臘', flag: '🇲🇸', lat: 16.7, lng: -62.1),
    'MT': WorldGeoItem(iso: 'MT', name: '馬爾他', flag: '🇲🇹', lat: 35.9, lng: 14.3),
    'MU': WorldGeoItem(iso: 'MU', name: '模里西斯', flag: '🇲🇺', lat: -20.3, lng: 57.5),
    'MV': WorldGeoItem(iso: 'MV', name: '馬爾地夫', flag: '🇲🇻', lat: 3.2, lng: 73.2),
    'MW': WorldGeoItem(iso: 'MW', name: '馬拉威', flag: '🇲🇼', lat: -13.2, lng: 34.3),
    'MX': WorldGeoItem(iso: 'MX', name: '墨西哥', flag: '🇲🇽', lat: 23.6, lng: -102.5, visualAnchor: Offset(0.225, 0.450)),
    'MY': WorldGeoItem(iso: 'MY', name: '馬來西亞', flag: '🇲🇾', lat: 4.2, lng: 101.9, visualAnchor: Offset(0.770, 0.550)),
    'MZ': WorldGeoItem(iso: 'MZ', name: '莫三比克', flag: '🇲🇿', lat: -18.6, lng: 35.5),
    'NA': WorldGeoItem(iso: 'NA', name: '納米比亞', flag: '🇳🇦', lat: -22.9, lng: 18.4),
    'NC': WorldGeoItem(iso: 'NC', name: '新喀里多尼亞', flag: '🇳🇨', lat: -20.9, lng: 165.6),
    'NE': WorldGeoItem(iso: 'NE', name: '尼日', flag: '🇳🇪', lat: 17.6, lng: 8.0),
    'NF': WorldGeoItem(iso: 'NF', name: '諾福克島', flag: '🇳🇫', lat: -29.0, lng: 167.9),
    'NG': WorldGeoItem(iso: 'NG', name: '奈及利亞', flag: '🇳🇬', lat: 9.0, lng: 8.6, visualAnchor: Offset(0.505, 0.525)),
    'NI': WorldGeoItem(iso: 'NI', name: '尼加拉瓜', flag: '🇳🇮', lat: 12.8, lng: -85.2),
    'NL': WorldGeoItem(iso: 'NL', name: '荷蘭', flag: '🇳🇱', lat: 52.1, lng: 5.2, visualAnchor: Offset(0.498, 0.275)),
    'NO': WorldGeoItem(iso: 'NO', name: '挪威', flag: '🇳🇴', lat: 60.4, lng: 8.4, visualAnchor: Offset(0.508, 0.210)),
    'NP': WorldGeoItem(iso: 'NP', name: '尼泊爾', flag: '🇳🇵', lat: 28.3, lng: 84.1),
    'NR': WorldGeoItem(iso: 'NR', name: '諾魯', flag: '🇳🇷', lat: -0.5, lng: 166.9),
    'NU': WorldGeoItem(iso: 'NU', name: '紐埃', flag: '🇳🇺', lat: -19.0, lng: -169.8),
    'NZ': WorldGeoItem(iso: 'NZ', name: '紐西蘭', flag: '🇳🇿', lat: -40.9, lng: 174.8, visualAnchor: Offset(0.940, 0.835)),
    'OM': WorldGeoItem(iso: 'OM', name: '阿曼', flag: '🇴🇲', lat: 21.5, lng: 55.9),
    'PA': WorldGeoItem(iso: 'PA', name: '巴拿馬', flag: '🇵🇦', lat: 8.5, lng: -80.7, visualAnchor: Offset(0.275, 0.530)),
    'PE': WorldGeoItem(iso: 'PE', name: '秘魯', flag: '🇵🇪', lat: -9.1, lng: -75.0, visualAnchor: Offset(0.290, 0.640)),
    'PF': WorldGeoItem(iso: 'PF', name: '法屬玻里尼西亞', flag: '🇵🇫', lat: -17.6, lng: -149.4),
    'PG': WorldGeoItem(iso: 'PG', name: '巴布亞紐幾內亞', flag: '🇵🇬', lat: -6.3, lng: 143.9),
    'PH': WorldGeoItem(iso: 'PH', name: '菲律賓', flag: '🇵🇭', lat: 12.8, lng: 121.7, visualAnchor: Offset(0.825, 0.505)),
    'PK': WorldGeoItem(iso: 'PK', name: '巴基斯坦', flag: '🇵🇰', lat: 30.3, lng: 69.3, visualAnchor: Offset(0.670, 0.400)),
    'PL': WorldGeoItem(iso: 'PL', name: '波蘭', flag: '🇵🇱', lat: 51.9, lng: 19.1, visualAnchor: Offset(0.535, 0.275)),
    'PM': WorldGeoItem(iso: 'PM', name: '聖皮埃爾和密克隆', flag: '🇵🇲', lat: 46.9, lng: -56.3),
    'PN': WorldGeoItem(iso: 'PN', name: '皮特肯群島', flag: '🇵🇳', lat: -24.7, lng: -127.4),
    'PR': WorldGeoItem(iso: 'PR', name: '波多黎各', flag: '🇵🇷', lat: 18.2, lng: -66.5),
    'PS': WorldGeoItem(iso: 'PS', name: '巴勒斯坦', flag: '🇵🇸', lat: 31.9, lng: 35.2),
    'PT': WorldGeoItem(iso: 'PT', name: '葡萄牙', flag: '🇵🇹', lat: 39.3, lng: -8.2, visualAnchor: Offset(0.465, 0.350)),
    'PW': WorldGeoItem(iso: 'PW', name: '帛琉', flag: '🇵🇼', lat: 7.5, lng: 134.5),
    'PY': WorldGeoItem(iso: 'PY', name: '巴拉圭', flag: '🇵🇾', lat: -23.4, lng: -58.4),
    'QA': WorldGeoItem(iso: 'QA', name: '卡達', flag: '🇶🇦', lat: 25.3, lng: 51.1),
    'RE': WorldGeoItem(iso: 'RE', name: '留尼旺', flag: '🇷🇪', lat: -21.1, lng: 55.5),
    'RO': WorldGeoItem(iso: 'RO', name: '羅馬尼亞', flag: '🇷🇴', lat: 45.9, lng: 24.9, visualAnchor: Offset(0.550, 0.310)),
    'RS': WorldGeoItem(iso: 'RS', name: '塞爾維亞', flag: '🇷🇸', lat: 44.0, lng: 21.0),
    'RU': WorldGeoItem(iso: 'RU', name: '俄羅斯', flag: '🇷🇺', lat: 61.5, lng: 105.3, visualAnchor: Offset(0.750, 0.210)),
    'RW': WorldGeoItem(iso: 'RW', name: '盧安達', flag: '🇷🇼', lat: -1.9, lng: 29.8),
    'SA': WorldGeoItem(iso: 'SA', name: '沙烏地阿拉伯', flag: '🇸🇦', lat: 23.8, lng: 45.0, visualAnchor: Offset(0.615, 0.450)),
    'SB': WorldGeoItem(iso: 'SB', name: '索羅門群島', flag: '🇸🇧', lat: -9.6, lng: 160.1),
    'SC': WorldGeoItem(iso: 'SC', name: '塞席爾', flag: '🇸🇨', lat: -4.6, lng: 55.4),
    'SD': WorldGeoItem(iso: 'SD', name: '蘇丹', flag: '🇸🇩', lat: 12.8, lng: 30.2),
    'SE': WorldGeoItem(iso: 'SE', name: '瑞典', flag: '🇸🇪', lat: 60.1, lng: 18.6, visualAnchor: Offset(0.535, 0.210)),
    'SG': WorldGeoItem(iso: 'SG', name: '新加坡', flag: '🇸🇬', lat: 1.3, lng: 103.8, visualAnchor: Offset(0.772, 0.585)),
    'SH': WorldGeoItem(iso: 'SH', name: '聖赫勒拿', flag: '🇸🇭', lat: -15.9, lng: -5.7),
    'SI': WorldGeoItem(iso: 'SI', name: '斯洛維尼亞', flag: '🇸🇮', lat: 46.1, lng: 14.9),
    'SJ': WorldGeoItem(iso: 'SJ', name: '斯瓦爾巴', flag: '🇸🇯', lat: 77.5, lng: 23.6),
    'SK': WorldGeoItem(iso: 'SK', name: '斯洛伐克', flag: '🇸🇰', lat: 48.6, lng: 19.6, visualAnchor: Offset(0.535, 0.295)),
    'SL': WorldGeoItem(iso: 'SL', name: '獅子山', flag: '🇸🇱', lat: 8.4, lng: -11.7),
    'SM': WorldGeoItem(iso: 'SM', name: '聖馬利諾', flag: '🇸🇲', lat: 43.9, lng: 12.4),
    'SN': WorldGeoItem(iso: 'SN', name: '塞內加爾', flag: '🇸🇳', lat: 14.4, lng: -14.4),
    'SO': WorldGeoItem(iso: 'SO', name: '索馬利亞', flag: '🇸🇴', lat: 5.1, lng: 46.1),
    'SR': WorldGeoItem(iso: 'SR', name: '蘇利南', flag: '🇸🇷', lat: 3.9, lng: -56.0),
    'SS': WorldGeoItem(iso: 'SS', name: '南蘇丹', flag: '🇸🇸', lat: 6.8, lng: 31.3),
    'ST': WorldGeoItem(iso: 'ST', name: '聖多美普林西比', flag: '🇸🇹', lat: 0.1, lng: 6.6),
    'SV': WorldGeoItem(iso: 'SV', name: '薩爾瓦多', flag: '🇸🇻', lat: 13.7, lng: -88.8),
    'SX': WorldGeoItem(iso: 'SX', name: '荷屬聖馬丁', flag: '🇸🇽', lat: 18.0, lng: -63.0),
    'SY': WorldGeoItem(iso: 'SY', name: '敘利亞', flag: '🇸🇾', lat: 34.8, lng: 38.9),
    'SZ': WorldGeoItem(iso: 'SZ', name: '史瓦帝尼', flag: '🇸🇿', lat: -26.5, lng: 31.4),
    'TC': WorldGeoItem(iso: 'TC', name: '特克斯與凱科斯', flag: '🇹🇨', lat: 21.6, lng: -71.7),
    'TD': WorldGeoItem(iso: 'TD', name: '查德', flag: '🇹🇩', lat: 15.4, lng: 18.7),
    'TF': WorldGeoItem(iso: 'TF', name: '法屬南部屬地', flag: '🇹🇫', lat: -49.2, lng: 69.3),
    'TG': WorldGeoItem(iso: 'TG', name: '多哥', flag: '🇹🇬', lat: 8.6, lng: 0.8),
    'TH': WorldGeoItem(iso: 'TH', name: '泰國', flag: '🇹🇭', lat: 15.8, lng: 100.9, visualAnchor: Offset(0.755, 0.485)),
    'TJ': WorldGeoItem(iso: 'TJ', name: '塔吉克', flag: '🇹🇯', lat: 38.8, lng: 71.2),
    'TK': WorldGeoItem(iso: 'TK', name: '托克勞', flag: '🇹🇰', lat: -9.2, lng: -171.8),
    'TL': WorldGeoItem(iso: 'TL', name: '東帝汶', flag: '🇹🇱', lat: -8.8, lng: 125.7),
    'TM': WorldGeoItem(iso: 'TM', name: '土庫曼', flag: '🇹🇲', lat: 38.9, lng: 59.5),
    'TN': WorldGeoItem(iso: 'TN', name: '突尼西亞', flag: '🇹🇳', lat: 33.8, lng: 9.5, visualAnchor: Offset(0.510, 0.380)),
    'TO': WorldGeoItem(iso: 'TO', name: '東加', flag: '🇹🇴', lat: -21.1, lng: -175.1),
    'TR': WorldGeoItem(iso: 'TR', name: '土耳其', flag: '🇹🇷', lat: 38.9, lng: 35.2, visualAnchor: Offset(0.585, 0.355)),
    'TT': WorldGeoItem(iso: 'TT', name: '千里達及托巴哥', flag: '🇹🇹', lat: 10.6, lng: -61.2),
    'TV': WorldGeoItem(iso: 'TV', name: '吐瓦魯', flag: '🇹🇻', lat: -7.1, lng: 177.6),
    'TW': WorldGeoItem(iso: 'TW', name: '台灣', flag: '🇹🇼', lat: 23.6, lng: 120.9, visualAnchor: Offset(0.808, 0.455)),
    'TZ': WorldGeoItem(iso: 'TZ', name: '坦尚尼亞', flag: '🇹🇿', lat: -6.3, lng: 34.8),
    'UA': WorldGeoItem(iso: 'UA', name: '烏克蘭', flag: '🇺🇦', lat: 48.3, lng: 31.1, visualAnchor: Offset(0.570, 0.295)),
    'UG': WorldGeoItem(iso: 'UG', name: '烏干達', flag: '🇺🇬', lat: 1.3, lng: 32.2),
    'UM': WorldGeoItem(iso: 'UM', name: '美國本土外小島', flag: '🇺🇲', lat: 19.2, lng: 166.6),
    'US': WorldGeoItem(iso: 'US', name: '美國', flag: '🇺🇸', lat: 37.0, lng: -95.7, visualAnchor: Offset(0.180, 0.360)),
    'UY': WorldGeoItem(iso: 'UY', name: '烏拉圭', flag: '🇺🇾', lat: -32.5, lng: -55.7, visualAnchor: Offset(0.340, 0.760)),
    'UZ': WorldGeoItem(iso: 'UZ', name: '烏茲別克', flag: '🇺🇿', lat: 41.3, lng: 64.5, visualAnchor: Offset(0.660, 0.340)),
    'VA': WorldGeoItem(iso: 'VA', name: '梵蒂岡', flag: '🇻🇦', lat: 41.9, lng: 12.4),
    'VC': WorldGeoItem(iso: 'VC', name: '聖文森', flag: '🇻🇨', lat: 13.2, lng: -61.2),
    'VE': WorldGeoItem(iso: 'VE', name: '委內瑞拉', flag: '🇻🇪', lat: 6.4, lng: -66.5, visualAnchor: Offset(0.310, 0.540)),
    'VG': WorldGeoItem(iso: 'VG', name: '英屬維京群島', flag: '🇻🇬', lat: 18.4, lng: -64.6),
    'VI': WorldGeoItem(iso: 'VI', name: '美屬維京群島', flag: '🇻🇮', lat: 18.3, lng: -64.8),
    'VN': WorldGeoItem(iso: 'VN', name: '越南', flag: '🇻🇳', lat: 14.0, lng: 108.2, visualAnchor: Offset(0.775, 0.490)),
    'VU': WorldGeoItem(iso: 'VU', name: '萬那杜', flag: '🇻🇺', lat: -15.3, lng: 166.9),
    'WF': WorldGeoItem(iso: 'WF', name: '瓦利斯群島', flag: '🇼🇫', lat: -13.7, lng: -177.1),
    'WS': WorldGeoItem(iso: 'WS', name: '薩摩亞', flag: '🇼🇸', lat: -13.7, lng: -172.1),
    'YE': WorldGeoItem(iso: 'YE', name: '葉門', flag: '🇾🇪', lat: 15.5, lng: 48.5),
    'YT': WorldGeoItem(iso: 'YT', name: '馬約特', flag: '🇾🇹', lat: -12.8, lng: 45.1),
    'ZA': WorldGeoItem(iso: 'ZA', name: '南非', flag: '🇿🇦', lat: -30.5, lng: 22.9, visualAnchor: Offset(0.545, 0.745)),
    'ZM': WorldGeoItem(iso: 'ZM', name: '尚比亞', flag: '🇿🇲', lat: -13.1, lng: 27.8),
    'ZW': WorldGeoItem(iso: 'ZW', name: '辛巴威', flag: '🇿🇼', lat: -19.0, lng: 29.1),
  };
}
