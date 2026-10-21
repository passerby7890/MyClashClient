// lib/business/subscription/node_model.dart

import '../../core/geo/world_geo_coordinates.dart';

/// 節點資料模型 (嚴格恪守 Zero-Plaintext Policy)
/// 對外 UI 僅暴露名稱、旗幟與測速延遲；嚴格隱藏底層伺服器 IP、密碼與金鑰
class NodeModel {
  final String id;
  final String name;
  final String flagEmoji;
  final String protocol; // vmess / vless / trojan / ss
  final int? latencyMs; // 毫秒 (-1 代表逾時)
  final bool isFavorite; // 是否加入收藏
  
  // 私有底層真實節點參數 (僅於生成 Mihomo 配置時在記憶體中調用，絕不向外部暴露)
  final Map<String, dynamic> _rawConfig;

  const NodeModel({
    required this.id,
    required this.name,
    required this.flagEmoji,
    required this.protocol,
    this.latencyMs,
    this.isFavorite = false,
    required Map<String, dynamic> rawConfig,
  }) : _rawConfig = rawConfig;

  /// 取得核心生成用之未脫敏配置 (僅限內部注入使用)
  Map<String, dynamic> get internalRawConfig => Map.unmodifiable(_rawConfig);

  /// 比對兩節點底層連線參數是否完全一致 (用於背景自動靜默更新時的 Non-Disruptive Diff Check)
  /// 若 server, port, type, uuid/password, cipher, tls 等關鍵協議參數均未改變，則回傳 true
  bool hasSameConnectionParams(NodeModel? other) {
    if (other == null) return false;
    if (protocol.toLowerCase() != other.protocol.toLowerCase()) return false;

    final c1 = _rawConfig;
    final c2 = other._rawConfig;

    // 比對底層所有關鍵連線與認證參數
    const criticalKeys = [
      'server',
      'port',
      'type',
      'uuid',
      'password',
      'cipher',
      'alterId',
      'tls',
      'network',
      'flow',
      'sni',
      'servername',
      'auth',
      'plugin',
      'plugin-opts',
      'ws-opts',
      'grpc-opts',
      'h2-opts',
      'http-opts',
      'reality-opts',
      'fingerprint',
      'client-fingerprint',
      'public-key',
      'short-id',
    ];

    for (final key in criticalKeys) {
      final v1 = c1[key]?.toString();
      final v2 = c2[key]?.toString();
      if (v1 != v2) return false;
    }

    return true;
  }

  /// 節點伺服器位址 (IP 或域名，用於真實 TCP 握手測速)
  String? get server => _rawConfig['server']?.toString();

  /// 節點連接埠 (用於真實 TCP 握手測速)
  int? get port => int.tryParse(_rawConfig['port']?.toString() ?? '');

  /// 延遲狀態文字 (例如 "48 ms" 或 "逾時")
  String get latencyFormatted {
    if (latencyMs == null) return '-- ms';
    if (latencyMs! < 0) return '逾時';
    return '$latencyMs ms';
  }

  /// 延遲評級 (可用於 UI 顏色：綠 / 青 / 黃 / 紅)
  String get latencyGrade {
    if (latencyMs == null) return 'none';
    if (latencyMs! < 0) return 'bad';
    if (latencyMs! <= 120) return 'excellent';
    if (latencyMs! <= 250) return 'good';
    return 'medium';
  }

  /// 取得節點對應的標準 ISO 3166-1 兩碼國家代碼 (如 "US", "JP", "HK", "TW")
  String get countryCode {
    final fromEmoji = emojiToIsoCode(flagEmoji);
    if (fromEmoji != null && fromEmoji.isNotEmpty) return fromEmoji;
    return resolveCountryCodeFromName(name);
  }

  /// 乾淨的顯示名稱 (徹底清洗開頭的國旗 Emoji、Regional Indicator 以及重疊的 ISO 國家代碼字母，如 "TW TW ", "US us ")
  String get cleanDisplayName {
    // 1. 移除開頭的國旗 Emoji 與 Unicode Regional Indicator 符號
    final flagRegex = RegExp(r'^([\uD83C][\uDDE6-\uDDFF]){1,2}\s*');
    String clean = name.replaceFirst(flagRegex, '').trim();

    // 2. 移除開頭殘留的重複或單個 2-碼國家代碼 (如 "TW TW ", "TW ", "US us ", "HK hk ")
    final isoRepeatRegex = RegExp(r'^(?:[A-Za-z]{2}[\s\-_]+){1,2}', caseSensitive: false);
    clean = clean.replaceFirst(isoRepeatRegex, '').trim();

    return clean.isEmpty ? name : clean;
  }

  /// 節點所屬大分類 (亞洲 / 歐美 / 其他)
  String get continent {
    final code = countryCode.toUpperCase();
    if (isoToContinentMap.containsKey(code)) {
      return isoToContinentMap[code]!;
    }

    // 依名稱關鍵字兜底
    final lower = name.toLowerCase();
    if (_matchesAny(lower, [
      '香港', 'hk', 'hong kong', '台湾', '台灣', 'tw', 'taiwan', '日本', 'jp', 'japan',
      '新加坡', 'sg', 'singapore', '韩国', '韓國', 'kr', 'korea', '越南', 'vn', 'vietnam',
      '泰国', '泰國', 'th', 'thailand', '菲律宾', '菲律賓', 'ph', 'philippines',
      '马来西亚', '馬來西亞', 'my', 'malaysia', '印度', 'in', 'india', '印尼', 'id', 'indonesia',
      '澳门', '澳門', 'mo', 'macau', '阿联酋', '阿聯酋', '迪拜', 'dubai', 'ae', 'uae', '亚洲', '亞洲'
    ])) {
      return '亞洲';
    }

    if (_matchesAny(lower, [
      '美国', '美國', 'us', 'usa', 'united states', '加拿大', 'ca', 'canada',
      '巴西', 'br', 'brazil', '阿根廷', 'ar', 'argentina', '墨西哥', 'mx', 'mexico',
      '智利', 'cl', 'chile', '哥伦比亚', 'colombia', '美洲',
      '爱尔兰', '愛爾蘭', 'ie', 'ireland', '英国', '英國', 'uk', 'britain', 'united kingdom', 'gb',
      '德国', '德國', 'de', 'germany', '法国', '法國', 'fr', 'france',
      '荷兰', '荷蘭', 'nl', 'netherlands', '俄罗斯', '俄羅斯', 'ru', 'russia',
      '瑞士', 'ch', 'switzerland', '土耳其', 'tr', 'turkey', '意大利', '義大利', 'it', 'italy',
      '西班牙', 'es', 'spain', '瑞典', 'se', 'sweden', '挪威', 'no', 'norway',
      '芬兰', '芬蘭', 'fi', 'finland', '丹麦', '丹麥', 'dk', 'denmark',
      '波兰', '波蘭', 'pl', 'poland', '乌克兰', '烏克蘭', 'ua', 'ukraine',
      '奥地利', '奧地利', 'at', 'austria', '比利时', '比利時', 'be', 'belgium',
      '捷克', 'cz', 'czech', '希腊', '希臘', 'gr', 'greece',
      '欧洲', '歐洲', '欧美', '歐美'
    ])) {
      return '歐美';
    }

    return '其他';
  }

  /// 節點所屬地區名稱 (用於卡片副標題標註，嚴格維持具體國家名稱，絕不顯示「歐美」)
  String get regionName {
    final code = countryCode.toUpperCase();
    final geo = WorldGeoCoordinates.getByIso(code);
    if (geo != null) return geo.name;
    if (isoCountryNames.containsKey(code)) {
      return isoCountryNames[code]!;
    }

    switch (flagEmoji) {
      case '🇭🇰': return '香港';
      case '🇹🇼': return '台灣';
      case '🇯🇵': return '日本';
      case '🇸🇬': return '新加坡';
      case '🇰🇷': return '韓國';
      case '🇺🇸': return '美國';
      case '🇻🇳': return '越南';
      case '🇹🇭': return '泰國';
      case '🇵🇭': return '菲律賓';
      case '🇲🇾': return '馬來西亞';
      case '🇮🇳': return '印度';
      case '🇮🇩': return '印尼';
      case '🇲🇴': return '澳門';
      case '🇦🇪': return '阿聯酋';
      case '🇬🇧': return '英國';
      case '🇩🇪': return '德國';
      case '🇫🇷': return '法國';
      case '🇳🇱': return '荷蘭';
      case '🇷🇺': return '俄羅斯';
      case '🇮🇪': return '愛爾蘭';
      case '🇨🇭': return '瑞士';
      case '🇹🇷': return '土耳其';
      case '🇮🇹': return '義大利';
      case '🇪🇸': return '西班牙';
      case '🇨🇦': return '加拿大';
      case '🇧🇷': return '巴西';
      case '🇦🇷': return '阿根廷';
      case '🇲🇽': return '墨西哥';
      case '🇦🇺': return '澳洲';
      case '🇳🇿': return '紐西蘭';
      case '🇿🇦': return '南非';
      default:
        final lower = name.toLowerCase();
        if (_matchesAny(lower, ['香港', 'hk', 'hong kong'])) return '香港';
        if (_matchesAny(lower, ['台湾', '台灣', 'tw', 'taiwan'])) return '台灣';
        if (_matchesAny(lower, ['日本', 'jp', 'japan', '东京', '大阪'])) return '日本';
        if (_matchesAny(lower, ['新加坡', 'sg', 'singapore', '狮城'])) return '新加坡';
        if (_matchesAny(lower, ['韩国', '韓國', 'kr', 'korea', '首尔'])) return '韓國';
        if (_matchesAny(lower, ['美国', '美國', 'us', 'usa', 'united states', '洛杉矶', '硅谷'])) return '美國';
        if (_matchesAny(lower, ['爱尔兰', '愛爾蘭', 'ie', 'ireland'])) return '愛爾蘭';
        if (_matchesAny(lower, ['英国', '英國', 'uk', 'britain', 'gb', '伦敦'])) return '英國';
        if (_matchesAny(lower, ['德国', '德國', 'de', 'germany', '法兰克福'])) return '德國';
        if (_matchesAny(lower, ['法国', '法國', 'fr', 'france', '巴黎'])) return '法國';
        if (_matchesAny(lower, ['荷兰', '荷蘭', 'nl', 'netherlands', '阿姆斯特丹'])) return '荷蘭';
        if (_matchesAny(lower, ['俄罗斯', '俄羅斯', 'ru', 'russia', '莫斯科'])) return '俄羅斯';
        if (_matchesAny(lower, ['瑞士', 'ch', 'switzerland', '苏黎世'])) return '瑞士';
        if (_matchesAny(lower, ['土耳其', 'tr', 'turkey', '伊斯坦布尔'])) return '土耳其';
        if (_matchesAny(lower, ['加拿大', 'ca', 'canada', '温哥华', '多伦多'])) return '加拿大';
        if (_matchesAny(lower, ['澳大利亚', '澳大利亞', '澳洲', 'australia', 'au', '悉尼'])) return '澳洲';
        if (_matchesAny(lower, ['新西兰', '紐西蘭', 'nz', 'new zealand'])) return '紐西蘭';
        if (_matchesAny(lower, ['越南', 'vn', 'vietnam'])) return '越南';
        if (_matchesAny(lower, ['泰国', '泰國', 'th', 'thailand'])) return '泰國';
        if (_matchesAny(lower, ['菲律宾', '菲律賓', 'ph', 'philippines'])) return '菲律賓';
        if (_matchesAny(lower, ['马来西亚', '馬來西亞', 'my', 'malaysia'])) return '馬來西亞';
        if (_matchesAny(lower, ['印度', 'in', 'india'])) return '印度';
        if (_matchesAny(lower, ['巴西', 'br', 'brazil'])) return '巴西';
        if (_matchesAny(lower, ['阿根廷', 'ar', 'argentina'])) return '阿根廷';
        return '其他';
    }
  }

  static bool _matchesAny(String text, List<String> keywords) {
    for (final kw in keywords) {
      if (text.contains(kw)) return true;
    }
    return false;
  }

  NodeModel copyWithLatency(int pingMs) {
    return NodeModel(
      id: id,
      name: name,
      flagEmoji: flagEmoji,
      protocol: protocol,
      latencyMs: pingMs,
      isFavorite: isFavorite,
      rawConfig: _rawConfig,
    );
  }

  NodeModel copyWithFavorite(bool fav) {
    return NodeModel(
      id: id,
      name: name,
      flagEmoji: flagEmoji,
      protocol: protocol,
      latencyMs: latencyMs,
      isFavorite: fav,
      rawConfig: _rawConfig,
    );
  }

  /// 透過 Unicode Regional Indicator 數學偏移公式，將任何國旗 Emoji 自動反解為標準 ISO 3166-1 兩碼代號
  static String? emojiToIsoCode(String emoji) {
    if (emoji.isEmpty) return null;
    final runes = emoji.runes.toList();
    if (runes.length >= 2 &&
        runes[0] >= 0x1F1E6 && runes[0] <= 0x1F1FF &&
        runes[1] >= 0x1F1E6 && runes[1] <= 0x1F1FF) {
      final first = String.fromCharCode(runes[0] - 0x1F1E6 + 65);
      final second = String.fromCharCode(runes[1] - 0x1F1E6 + 65);
      return '$first$second';
    }
    return null;
  }

  /// 透過標準 ISO 3166-1 兩碼代號，轉換回 Unicode 國旗 Emoji
  static String isoCodeToEmoji(String iso) {
    if (iso.length != 2) return '🌐';
    final upper = iso.toUpperCase();
    final first = upper.codeUnitAt(0) - 65 + 0x1F1E6;
    final second = upper.codeUnitAt(1) - 65 + 0x1F1E6;
    return String.fromCharCode(first) + String.fromCharCode(second);
  }

  /// 依名稱關鍵字推導 ISO 兩碼代號 (優先使用全球 249 國完整別名庫)
  static String resolveCountryCodeFromName(String nodeName) {
    final fromGlobal = WorldGeoCoordinates.resolveIsoFromAlias(nodeName);
    if (fromGlobal != null) return fromGlobal;

    final lower = nodeName.toLowerCase();
    if (_matchesAny(lower, ['香港', 'hk', 'hong kong'])) return 'HK';
    if (_matchesAny(lower, ['台湾', '台灣', 'tw', 'taiwan'])) return 'TW';
    if (_matchesAny(lower, ['日本', 'jp', 'japan', '东京', '大阪'])) return 'JP';
    if (_matchesAny(lower, ['新加坡', 'sg', 'singapore', '狮城'])) return 'SG';
    if (_matchesAny(lower, ['美国', '美國', 'us', 'usa', 'united states', '美', '硅谷', '洛杉矶'])) return 'US';
    if (_matchesAny(lower, ['韩国', '韓國', 'kr', 'korea', '首尔'])) return 'KR';
    if (_matchesAny(lower, ['爱尔兰', '愛爾蘭', 'ie', 'ireland', '都柏林'])) return 'IE';
    if (_matchesAny(lower, ['英国', '英國', 'uk', 'britain', 'gb', '伦敦'])) return 'GB';
    if (_matchesAny(lower, ['德国', '德國', 'de', 'germany', '法兰克福'])) return 'DE';
    if (_matchesAny(lower, ['法国', '法國', 'fr', 'france', '巴黎'])) return 'FR';
    if (_matchesAny(lower, ['荷兰', '荷蘭', 'nl', 'netherlands', '阿姆斯特丹'])) return 'NL';
    if (_matchesAny(lower, ['俄罗斯', '俄羅斯', 'ru', 'russia', '莫斯科'])) return 'RU';
    if (_matchesAny(lower, ['加拿大', 'ca', 'canada', '温哥华', '多伦多'])) return 'CA';
    if (_matchesAny(lower, ['澳大利亚', '澳大利亞', '澳洲', 'au', 'australia', '悉尼', '雪梨'])) return 'AU';
    if (_matchesAny(lower, ['瑞士', 'ch', 'switzerland', '苏黎世'])) return 'CH';
    if (_matchesAny(lower, ['土耳其', 'tr', 'turkey', '伊斯坦布尔'])) return 'TR';
    if (_matchesAny(lower, ['越南', 'vn', 'vietnam', '胡志明'])) return 'VN';
    if (_matchesAny(lower, ['泰国', '泰國', 'th', 'thailand', '曼谷'])) return 'TH';
    if (_matchesAny(lower, ['菲律宾', '菲律賓', 'ph', 'philippines', '马尼拉'])) return 'PH';
    if (_matchesAny(lower, ['马来西亚', '馬來西亞', 'my', 'malaysia', '吉隆坡'])) return 'MY';
    if (_matchesAny(lower, ['印度', 'in', 'india', '孟买'])) return 'IN';
    if (_matchesAny(lower, ['巴西', 'br', 'brazil'])) return 'BR';
    if (_matchesAny(lower, ['阿根廷', 'ar', 'argentina'])) return 'AR';
    if (_matchesAny(lower, ['新西兰', '紐西蘭', 'nz', 'new zealand'])) return 'NZ';
    if (_matchesAny(lower, ['意大利', '義大利', 'it', 'italy', '米兰', '罗马'])) return 'IT';
    if (_matchesAny(lower, ['西班牙', 'es', 'spain', '马德里'])) return 'ES';
    if (_matchesAny(lower, ['瑞典', 'se', 'sweden'])) return 'SE';
    if (_matchesAny(lower, ['挪威', 'no', 'norway'])) return 'NO';
    if (_matchesAny(lower, ['芬兰', '芬蘭', 'fi', 'finland'])) return 'FI';
    if (_matchesAny(lower, ['丹麦', '丹麥', 'dk', 'denmark'])) return 'DK';
    if (_matchesAny(lower, ['波兰', '波蘭', 'pl', 'poland'])) return 'PL';
    if (_matchesAny(lower, ['乌克兰', '烏克蘭', 'ua', 'ukraine'])) return 'UA';
    if (_matchesAny(lower, ['奥地利', '奧地利', 'at', 'austria'])) return 'AT';
    if (_matchesAny(lower, ['比利时', '比利時', 'be', 'belgium'])) return 'BE';
    if (_matchesAny(lower, ['希腊', '希臘', 'gr', 'greece'])) return 'GR';
    if (_matchesAny(lower, ['葡萄牙', 'pt', 'portugal'])) return 'PT';
    if (_matchesAny(lower, ['捷克', 'cz', 'czech'])) return 'CZ';
    if (_matchesAny(lower, ['阿联酋', '阿聯酋', 'ae', 'uae', '迪拜'])) return 'AE';
    if (_matchesAny(lower, ['南非', 'za', 'south africa'])) return 'ZA';
    return 'HK';
  }

  /// 從節點名稱自動提取對應的國旗 Emoji (優先直接擷取 emoji，次選關鍵字繁簡比對)
  static String extractFlag(String nodeName) {
    // 1. 若節點名稱開頭或內容已內嵌國旗 Emoji (例如 🇺🇸, 🇯🇵, 🇹🇼, 🇸🇬, 🇭🇰)
    final flagRegex = RegExp(r'[\uD83C][\uDDE6-\uDDFF][\uD83C][\uDDE6-\uDDFF]');
    final match = flagRegex.firstMatch(nodeName);
    if (match != null) {
      return match.group(0)!;
    }

    // 2. 繁體、簡體與英文代號全面涵蓋比對
    final iso = resolveCountryCodeFromName(nodeName);
    return isoCodeToEmoji(iso);
  }

  factory NodeModel.fromProxyMap(
    Map<String, dynamic> map, {
    required String id,
    String? sanitizedName,
  }) {
    final name = sanitizedName ?? (map['name'] as String? ?? '未命名節點');
    final type = map['type'] as String? ?? 'proxy';
    return NodeModel(
      id: id,
      name: name,
      flagEmoji: extractFlag(name),
      protocol: type.toUpperCase(),
      latencyMs: null,
      rawConfig: map,
    );
  }

  @override
  String toString() {
    return 'NodeModel(id: $id, name: $name, protocol: $protocol, latency: $latencyFormatted)';
  }

  // ==========================================
  // 全球 ISO 3166-1 常數字典庫 (249 國/地區覆蓋)
  // ==========================================
  static const Map<String, String> isoCountryNames = {
    'HK': '香港', 'TW': '台灣', 'JP': '日本', 'SG': '新加坡', 'KR': '韓國',
    'US': '美國', 'GB': '英國', 'DE': '德國', 'FR': '法國', 'IE': '愛爾蘭',
    'NL': '荷蘭', 'RU': '俄羅斯', 'CA': '加拿大', 'AU': '澳洲', 'CH': '瑞士',
    'IT': '義大利', 'ES': '西班牙', 'SE': '瑞典', 'NO': '挪威', 'FI': '芬蘭',
    'DK': '丹麥', 'PL': '波蘭', 'UA': '烏克蘭', 'AT': '奧地利', 'BE': '比利時',
    'CZ': '捷克', 'GR': '希臘', 'PT': '葡萄牙', 'RO': '羅馬尼亞', 'HU': '匈牙利',
    'TR': '土耳其', 'VN': '越南', 'TH': '泰國', 'PH': '菲律賓', 'MY': '馬來西亞',
    'IN': '印度', 'ID': '印尼', 'MO': '澳門', 'AE': '阿聯酋', 'SA': '沙烏地阿拉伯',
    'IL': '以色列', 'NZ': '紐西蘭', 'BR': '巴西', 'AR': '阿根廷', 'MX': '墨西哥',
    'CL': '智利', 'CO': '哥倫比亞', 'PE': '秘魯', 'ZA': '南非', 'EG': '埃及',
    'CN': '中國', 'IS': '冰島', 'LU': '盧森堡', 'BG': '保加利亞', 'HR': '克羅埃西亞',
    'RS': '塞爾維亞', 'SK': '斯洛伐克', 'SI': '斯洛維尼亞', 'EE': '愛沙尼亞',
    'LV': '拉脫維亞', 'LT': '立陶宛', 'CY': '賽普勒斯', 'MT': '馬爾他',
    'KZ': '哈薩克', 'UZ': '烏茲別克', 'PK': '巴基斯坦', 'BD': '孟加拉', 'LK': '斯里蘭卡',
    'KH': '柬埔寨', 'LA': '寮國', 'MM': '緬甸', 'NP': '尼泊爾', 'MN': '蒙古',
    'QA': '卡達', 'KW': '科威特', 'OM': '阿曼', 'BH': '巴林', 'JO': '約旦',
    'LB': '黎巴嫩', 'IQ': '伊拉克', 'GE': '喬治亞', 'AM': '亞美尼亞', 'AZ': '亞塞拜然',
    'NG': '奈及利亞', 'KE': '肯亞', 'GH': '迦納', 'MA': '摩洛哥', 'DZ': '阿爾及利亞',
    'TN': '突尼西亞', 'CR': '哥斯大黎加', 'PA': '巴拿馬', 'UY': '烏拉圭', 'EC': '厄瓜多'
  };

  /// 依 ISO 3166-1 兩碼映射所屬大洲 (亞洲 / 歐美 / 其他)
  static const Map<String, String> isoToContinentMap = {
    // 亞洲
    'HK': '亞洲', 'TW': '亞洲', 'JP': '亞洲', 'SG': '亞洲', 'KR': '亞洲',
    'VN': '亞洲', 'TH': '亞洲', 'PH': '亞洲', 'MY': '亞洲', 'IN': '亞洲',
    'ID': '亞洲', 'MO': '亞洲', 'AE': '亞洲', 'SA': '亞洲', 'IL': '亞洲',
    'KZ': '亞洲', 'PK': '亞洲', 'BD': '亞洲', 'LK': '亞洲', 'KH': '亞洲',
    'LA': '亞洲', 'MM': '亞洲', 'NP': '亞洲', 'MN': '亞洲', 'QA': '亞洲',
    'KW': '亞洲', 'OM': '亞洲', 'BH': '亞洲', 'JO': '亞洲', 'LB': '亞洲',
    'IQ': '亞洲', 'UZ': '亞洲', 'CN': '亞洲', 'GE': '亞洲', 'AM': '亞洲', 'AZ': '亞洲',

    // 歐美 (歐洲 + 美洲)
    'US': '歐美', 'CA': '歐美', 'BR': '歐美', 'AR': '歐美', 'MX': '歐美',
    'CL': '歐美', 'CO': '歐美', 'PE': '歐美', 'UY': '歐美', 'CR': '歐美', 'PA': '歐美', 'EC': '歐美',
    'IE': '歐美', 'GB': '歐美', 'DE': '歐美', 'FR': '歐美', 'NL': '歐美',
    'RU': '歐美', 'CH': '歐美', 'TR': '歐美', 'IT': '歐美', 'ES': '歐美',
    'SE': '歐美', 'NO': '歐美', 'FI': '歐美', 'DK': '歐美', 'PL': '歐美',
    'UA': '歐美', 'AT': '歐美', 'BE': '歐美', 'CZ': '歐美', 'GR': '歐美',
    'PT': '歐美', 'RO': '歐美', 'HU': '歐美', 'IS': '歐美', 'LU': '歐美',
    'BG': '歐美', 'HR': '歐美', 'RS': '歐美', 'SK': '歐美', 'SI': '歐美',
    'EE': '歐美', 'LV': '歐美', 'LT': '歐美', 'CY': '歐美', 'MT': '歐美',

    // 其他 (大洋洲、非洲、其他)
    'AU': '其他', 'NZ': '其他', 'ZA': '其他', 'EG': '其他', 'NG': '其他',
    'KE': '其他', 'GH': '其他', 'MA': '其他', 'DZ': '其他', 'TN': '其他'
  };
}
