// lib/core/constants/app_constants.dart

/// 應用程式全域常數定義
class AppConstants {
  AppConstants._();

  // --- DoH 端點 (多級容災備援：國內阿裡雲/騰訊 + 國際 Cloudflare/Google) ---
  static const String cloudflareDohEndpoint = 'https://cloudflare-dns.com/dns-query';
  static const String googleDohEndpoint = 'https://dns.google/resolve';
  static const String tencentDohEndpoint = 'https://doh.pub/dns-query';
  static const String aliyunDohEndpoint = 'https://dns.alidns.com/resolve';

  // --- 絕招二：XOR 字串隱形術 (防止逆向工程 strings libapp.so 檢索明文網域與密鑰) ---
  static const int _xorMask = 0x5A;
  static String _deobfuscate(List<int> bytes) =>
      String.fromCharCodes(bytes.map((b) => b ^ _xorMask));

  // --- 阿里雲 OSS 動態加密配置來源 (天河網絡專屬端點) ---
  static const List<int> _encOssUrl = [
    50, 46, 46, 42, 41, 96, 117, 117, 46, 50, 48, 41, 43, 99, 99, 99, 116, 53,
    41, 41, 119, 59, 42, 119, 41, 53, 47, 46, 50, 63, 59, 41, 46, 119, 107, 116,
    59, 54, 51, 35, 47, 52, 57, 41, 116, 57, 53, 55, 117, 45, 63, 56, 119, 57,
    53, 52, 60, 51, 61, 116, 48, 41, 53, 52
  ];
  static String get aliyunOssConfigUrl => _deobfuscate(_encOssUrl);

  /// 官方專案即時更新清單 URL (update.json)
  static const String ossUpdateJsonUrl =
      'https://novaclash.oss-ap-northeast-1.aliyuncs.com/update.json';

  // --- 官方品牌素材 ---
  static const String logoUrl =
      'https://novaclash.oss-ap-northeast-1.aliyuncs.com/img/logo.png';
  static const String logoAssetPath = 'assets/images/logo.png';

  // --- 查詢網域配置 (XOR 混淆存儲) ---
  static const List<int> _encPrimaryDomain = [
    46, 50, 48, 41, 43, 59, 63, 41, 105, 104, 116, 41, 42, 41, 40, 98, 108, 116, 57, 44
  ];
  static String get primaryConfigDomain => _deobfuscate(_encPrimaryDomain);

  static const List<int> _encSecondaryDomain = [
    52, 53, 44, 59, 57, 54, 59, 41, 50, 116, 41, 42, 41, 40, 98, 108, 116, 57, 44
  ];
  static String get secondaryConfigDomain => _deobfuscate(_encSecondaryDomain);

  // --- 多節點 API 兜底網域與直接 IP 陣列 (XOR 混淆存儲) ---
  static const List<List<int>> _encFallbackDomains = [
    [50, 46, 46, 42, 41, 96, 117, 117, 98, 116, 104, 107, 98, 116, 107, 109, 108, 116, 104, 105, 98, 96, 105, 105, 98, 99],
    [50, 46, 46, 42, 41, 96, 117, 117, 98, 116, 104, 107, 98, 116, 107, 109, 108, 116, 104, 105, 98, 96, 98, 110, 110, 105],
    [50, 46, 46, 42, 41, 96, 117, 117, 98, 116, 104, 107, 99, 116, 107, 99, 108, 116, 104, 107, 108, 96, 105, 105, 98, 99],
    [50, 46, 46, 42, 41, 96, 117, 117, 106, 52, 104, 107, 116, 57, 53, 55],
  ];
  static List<String> get fallbackApiDomains =>
      _encFallbackDomains.map((b) => _deobfuscate(b)).toList();

  // --- 官方網站/門戶前台 (XOR 混淆存儲) ---
  static const List<int> _encWebsiteUrl = [
    50, 46, 46, 42, 41, 96, 117, 117, 42, 53, 40, 46, 59, 54, 116, 46, 50, 48,
    41, 109, 98, 99, 116, 57, 53, 55
  ];
  static String get officialWebsiteUrl => _deobfuscate(_encWebsiteUrl);

  // --- 在線客服與社群連結 (對齊 Tianhe Crisp 與 Telegram 官方機器人) ---
  static const String crispWebsiteId = 'b8b32705-d834-41b5-b6f5-6849fa0679d6';
  static const String crispChatUrl =
      'https://go.crisp.chat/chat/embed/?website_id=b8b32705-d834-41b5-b6f5-6849fa0679d6';
  static const String telegramGroupUrl = 'https://t.me/q8891qcom';
  static const String telegramBotUrl = 'https://t.me/THJSQBOT';

  // --- 加密金鑰常數 (AES-256-CBC, XOR 混淆存儲) ---
  static const List<int> _encKey = [
    111, 34, 60, 13, 50, 108, 98, 107, 54, 10, 18, 20, 59, 55, 12, 98,
    99, 60, 17, 28, 47, 43, 0, 34, 11, 35, 27, 59, 24, 52, 48, 41
  ];
  static String get defaultAesKey => _deobfuscate(_encKey);

  static const List<int> _encIv = [
    41, 105, 106, 105, 17, 50, 57, 106, 49, 19, 28, 0, 46, 12, 63, 2
  ];
  static String get defaultAesIv => _deobfuscate(_encIv);

  // --- 本地安全儲存 Keys ---
  static const String storageJwtToken = 'v2board_jwt_token';
  static const String storageUserInfo = 'v2board_user_info';
  static const String storageCachedConfig = 'v2board_cached_remote_config';
  static const String storageSelectedNodeId = 'v2board_selected_node_id';
  static const String storageFavoriteNodeIds = 'v2board_favorite_node_ids';
  static const String storageAppLanguage = 'v2board_app_language';
  static const String storageLastTrafficAlertTime = 'v2board_last_traffic_alert_time';
  static const String storageEncryptedNodes = 'v2board_encrypted_nodes_vault';
  static const String storageAutoConnectOnNodeSelect = 'v2board_auto_connect_on_node_select';
  static const String storageCachedSubscribePath = 'v2board_cached_subscribe_path';

  // --- 網路連線超時設定 (毫秒) ---
  static const int connectTimeoutMs = 8000;
  static const int receiveTimeoutMs = 12000;
  static const int dohTimeoutMs = 3000;

  // --- 客戶端版本識別 (單一事實來源 Single Source of Truth，支援編譯期 --dart-define 注入) ---
  static const String appName = '天河網絡';
  static const String appVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: '3.0.8');
  static const int appBuildNumber =
      int.fromEnvironment('APP_BUILD_NUMBER', defaultValue: 108);
  static const String fullVersionDisplay = 'v$appVersion (Build $appBuildNumber)';
  static const String versionTag = 'v$appVersion';

  // --- Mihomo 本地 Controller 防窺探金鑰 (防止未授權讀取節點與配置) ---
  static const String coreSecret = 'tianhe_sec_99a8b7c6d5e4';
}
