// lib/core/constants/app_constants.dart

/// 應用程式全域常數定義
class AppConstants {
  AppConstants._();

  // --- 絕招二：XOR 字串隱形術 (防止逆向工程 strings app.so / App 檢索明文網域、DoH、OSS 與密鑰) ---
  static const int _xorMask = 0x5A;
  static String _deobfuscate(List<int> bytes) =>
      String.fromCharCodes(bytes.map((b) => b ^ _xorMask));

  // --- DoH 端點 (多級容災備援：全 XOR 混淆存儲，零明文暴露) ---
  static const List<int> _encCloudflareDoh = [
    50, 46, 46, 42, 41, 96, 117, 117, 57, 54, 53, 47, 62, 60, 54, 59, 40, 63,
    119, 62, 52, 41, 116, 57, 53, 55, 117, 62, 52, 41, 119, 43, 47, 63, 40, 35
  ];
  static String get cloudflareDohEndpoint => _deobfuscate(_encCloudflareDoh);

  static const List<int> _encGoogleDoh = [
    50, 46, 46, 42, 41, 96, 117, 117, 62, 52, 41, 116, 61, 53, 53, 61, 54, 63,
    117, 40, 63, 41, 53, 54, 44, 63
  ];
  static String get googleDohEndpoint => _deobfuscate(_encGoogleDoh);

  static const List<int> _encTencentDoh = [
    50, 46, 46, 42, 41, 96, 117, 117, 62, 53, 50, 116, 42, 47, 56, 117, 62, 52,
    41, 119, 43, 47, 63, 40, 35
  ];
  static String get tencentDohEndpoint => _deobfuscate(_encTencentDoh);

  static const List<int> _encAliyunDoh = [
    50, 46, 46, 42, 41, 96, 117, 117, 62, 52, 41, 116, 59, 54, 51, 62, 52, 41,
    116, 57, 53, 55, 117, 40, 63, 41, 53, 54, 44, 63
  ];
  static String get aliyunDohEndpoint => _deobfuscate(_encAliyunDoh);

  static const List<int> _encAliyunIpDoh = [
    50, 46, 46, 42, 41, 96, 117, 117, 104, 104, 105, 116, 111, 116, 111, 116,
    111, 117, 62, 52, 41, 119, 43, 47, 63, 40, 35
  ];
  static String get aliyunIpDohEndpoint => _deobfuscate(_encAliyunIpDoh);

  static const List<int> _encTencentIpDoh = [
    50, 46, 46, 42, 41, 96, 117, 117, 107, 116, 107, 104, 116, 107, 104, 116,
    107, 104, 117, 62, 52, 41, 119, 43, 47, 63, 40, 35
  ];
  static String get tencentIpDohEndpoint => _deobfuscate(_encTencentIpDoh);

  // --- 常見 DoH 回退節點與 Crisp Base (XOR 混淆存儲) ---
  static const List<int> _encCrispEmbedBaseUrl = [
    50, 46, 46, 42, 41, 96, 117, 117, 61, 53, 116, 57, 40, 51, 41, 42, 116, 57,
    50, 59, 46, 117, 57, 50, 59, 46, 117, 63, 55, 56, 63, 62, 117
  ];
  static String get crispEmbedBaseUrl => _deobfuscate(_encCrispEmbedBaseUrl);

  static const List<int> _encCloudflareDnsOverHttpsFallback = [
    50, 46, 46, 42, 41, 96, 117, 117, 107, 116, 107, 116, 107, 116, 107, 117,
    62, 52, 41, 119, 43, 47, 63, 40, 35, 121, 10, 8, 21, 2, 3
  ];
  static String get cloudflareDnsOverHttpsFallback =>
      _deobfuscate(_encCloudflareDnsOverHttpsFallback);

  static const List<int> _encGoogleDnsOverHttpsFallback = [
    50, 46, 46, 42, 41, 96, 117, 117, 62, 52, 41, 116, 61, 53, 53, 61, 54, 63,
    117, 62, 52, 41, 119, 43, 47, 63, 40, 35, 121, 10, 8, 21, 2, 3
  ];
  static String get googleDnsOverHttpsFallback =>
      _deobfuscate(_encGoogleDnsOverHttpsFallback);

  static const List<int> _encTencentDnsOverHttpsFallback = [
    50, 46, 46, 42, 41, 96, 117, 117, 62, 53, 50, 116, 42, 47, 56, 117, 62, 52,
    41, 119, 43, 47, 63, 40, 35
  ];
  static String get tencentDnsOverHttpsFallback =>
      _deobfuscate(_encTencentDnsOverHttpsFallback);

  static const List<int> _encAliDnsOverHttpsFallback = [
    50, 46, 46, 42, 41, 96, 117, 117, 62, 52, 41, 116, 59, 54, 51, 62, 52, 41,
    116, 57, 53, 55, 117, 62, 52, 41, 119, 43, 47, 63, 40, 35
  ];
  static String get aliDnsOverHttpsFallback =>
      _deobfuscate(_encAliDnsOverHttpsFallback);

  static const List<int> _encCloudflareDnsHost = [
    57, 54, 53, 47, 62, 60, 54, 59, 40, 63, 119, 62, 52, 41, 116, 57, 53, 55
  ];
  static String get cloudflareDnsHost => _deobfuscate(_encCloudflareDnsHost);

  // --- 阿里雲 OSS 動態加密配置來源 (天河網絡專屬端點，XOR 混淆存儲) ---
  static const List<int> _encOssUrl = [
    50, 46, 46, 42, 41, 96, 117, 117, 46, 50, 48, 41, 43, 99, 99, 99, 116, 53,
    41, 41, 119, 59, 42, 119, 41, 53, 47, 46, 50, 63, 59, 41, 46, 119, 107, 116,
    59, 54, 51, 35, 47, 52, 57, 41, 116, 57, 53, 55, 117, 45, 63, 56, 119, 57,
    53, 52, 60, 51, 61, 116, 48, 41, 53, 52
  ];
  static String get aliyunOssConfigUrl => _deobfuscate(_encOssUrl);

  /// 官方專案即時更新清單 URL (XOR 混淆存儲)
  static const List<int> _encOssUpdateUrl = [
    50, 46, 46, 42, 41, 96, 117, 117, 52, 53, 44, 59, 57, 54, 59, 41, 50, 116,
    53, 41, 41, 119, 59, 42, 119, 52, 53, 40, 46, 50, 63, 59, 41, 46, 119, 107,
    116, 59, 54, 51, 35, 47, 52, 57, 41, 116, 57, 53, 55, 117, 47, 42, 62, 59,
    46, 63, 116, 48, 41, 53, 52
  ];
  static String get ossUpdateJsonUrl => _deobfuscate(_encOssUpdateUrl);

  // --- 官方品牌素材 (XOR 混淆存儲) ---
  static const List<int> _encLogoUrl = [
    50, 46, 46, 42, 41, 96, 117, 117, 52, 53, 44, 59, 57, 54, 59, 41, 50, 116,
    53, 41, 41, 119, 59, 42, 119, 52, 53, 40, 46, 50, 63, 59, 41, 46, 119, 107,
    116, 59, 54, 51, 35, 47, 52, 57, 41, 116, 57, 53, 55, 117, 51, 55, 61, 117,
    54, 53, 61, 53, 116, 42, 52, 61
  ];
  static String get logoUrl => _deobfuscate(_encLogoUrl);
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

  // --- 在線客服與社群連結 (XOR 混淆存儲) ---
  static const List<int> _encCrispId = [
    56, 98, 56, 105, 104, 109, 106, 111, 119, 62, 98, 105, 110, 119, 110, 107,
    56, 111, 119, 56, 108, 60, 111, 119, 108, 98, 110, 99, 60, 59, 106, 108,
    109, 99, 62, 108
  ];
  static String get crispWebsiteId => _deobfuscate(_encCrispId);

  static const List<int> _encCrispChatUrl = [
    50, 46, 46, 42, 41, 96, 117, 117, 61, 53, 116, 57, 40, 51, 41, 42, 116, 57,
    50, 59, 46, 117, 57, 50, 59, 46, 117, 63, 55, 56, 63, 62, 117, 101, 45, 63,
    56, 41, 51, 46, 63, 5, 51, 62, 103, 56, 98, 56, 105, 104, 109, 106, 111,
    119, 62, 98, 105, 110, 119, 110, 107, 56, 111, 119, 56, 108, 60, 111, 119,
    108, 98, 110, 99, 60, 59, 106, 108, 109, 99, 62, 108
  ];
  static String get crispChatUrl => _deobfuscate(_encCrispChatUrl);

  static const List<int> _encTgGroupUrl = [
    50, 46, 46, 42, 41, 96, 117, 117, 46, 116, 55, 63, 117, 43, 98, 98, 99, 107,
    43, 57, 53, 55
  ];
  static String get telegramGroupUrl => _deobfuscate(_encTgGroupUrl);

  static const List<int> _encTgBotUrl = [
    50, 46, 46, 42, 41, 96, 117, 117, 46, 116, 55, 63, 117, 14, 18, 16, 9, 11,
    24, 21, 14
  ];
  static String get telegramBotUrl => _deobfuscate(_encTgBotUrl);

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

  // --- 本地安全儲存 Keys (XOR 混淆存儲，確保與舊版 100% 無縫相容且二進位零 v2board 字串殘留) ---
  static const List<int> _encStorageJwtToken = [
    44, 104, 56, 53, 59, 40, 62, 5, 48, 45, 46, 5, 46, 53, 49, 63, 52
  ];
  static String get storageJwtToken => _deobfuscate(_encStorageJwtToken);

  static const List<int> _encStorageUserInfo = [
    44, 104, 56, 53, 59, 40, 62, 5, 47, 41, 63, 40, 5, 51, 52, 60, 53
  ];
  static String get storageUserInfo => _deobfuscate(_encStorageUserInfo);

  static const List<int> _encStorageCachedConfig = [
    44, 104, 56, 53, 59, 40, 62, 5, 57, 59, 57, 50, 63, 62, 5, 40, 63, 55, 53,
    46, 63, 5, 57, 53, 52, 60, 51, 61
  ];
  static String get storageCachedConfig => _deobfuscate(_encStorageCachedConfig);

  static const List<int> _encStorageSelectedNodeId = [
    44, 104, 56, 53, 59, 40, 62, 5, 41, 63, 54, 63, 57, 46, 63, 62, 5, 52, 53,
    62, 63, 5, 51, 62
  ];
  static String get storageSelectedNodeId =>
      _deobfuscate(_encStorageSelectedNodeId);

  static const List<int> _encStorageFavoriteNodeIds = [
    44, 104, 56, 53, 59, 40, 62, 5, 60, 59, 44, 53, 40, 51, 46, 63, 5, 52, 53,
    62, 63, 5, 51, 62, 41
  ];
  static String get storageFavoriteNodeIds =>
      _deobfuscate(_encStorageFavoriteNodeIds);

  static const List<int> _encStorageAppLanguage = [
    44, 104, 56, 53, 59, 40, 62, 5, 59, 42, 42, 5, 54, 59, 52, 61, 47, 59, 61, 63
  ];
  static String get storageAppLanguage => _deobfuscate(_encStorageAppLanguage);

  static const List<int> _encStorageLastTrafficAlertTime = [
    44, 104, 56, 53, 59, 40, 62, 5, 54, 59, 41, 46, 5, 46, 40, 59, 60, 60, 51,
    57, 5, 59, 54, 63, 40, 46, 5, 46, 51, 55, 63
  ];
  static String get storageLastTrafficAlertTime =>
      _deobfuscate(_encStorageLastTrafficAlertTime);

  static const List<int> _encStorageEncryptedNodes = [
    44, 104, 56, 53, 59, 40, 62, 5, 63, 52, 57, 40, 35, 42, 46, 63, 62, 5, 52,
    53, 62, 63, 41, 5, 44, 59, 47, 54, 46
  ];
  static String get storageEncryptedNodes =>
      _deobfuscate(_encStorageEncryptedNodes);

  static const List<int> _encStorageAutoConnectOnNodeSelect = [
    44, 104, 56, 53, 59, 40, 62, 5, 59, 47, 46, 53, 5, 57, 53, 52, 52, 63, 57,
    46, 5, 53, 52, 5, 52, 53, 62, 63, 5, 41, 63, 54, 63, 57, 46
  ];
  static String get storageAutoConnectOnNodeSelect =>
      _deobfuscate(_encStorageAutoConnectOnNodeSelect);

  static const List<int> _encStorageCachedSubscribePath = [
    44, 104, 56, 53, 59, 40, 62, 5, 57, 59, 57, 50, 63, 62, 5, 41, 47, 56, 41,
    57, 40, 51, 56, 63, 5, 42, 59, 46, 50
  ];
  static String get storageCachedSubscribePath =>
      _deobfuscate(_encStorageCachedSubscribePath);

  // --- 網路連線超時設定 (毫秒) ---
  static const int connectTimeoutMs = 8000;
  static const int receiveTimeoutMs = 12000;
  static const int dohTimeoutMs = 3000;

  // --- 客戶端版本識別 (單一事實來源 Single Source of Truth，支援編譯期 --dart-define 注入) ---
  static const String appName = '天河網絡';
  static const String appVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: '3.3.1');
  static const int appBuildNumber =
      int.fromEnvironment('APP_BUILD_NUMBER', defaultValue: 131);
  static const String fullVersionDisplay = 'v$appVersion (Build $appBuildNumber)';
  static const String versionTag = 'v$appVersion';

  // --- 本地核心控制防窺探金鑰 (XOR 混淆存儲) ---
  static const List<int> _encCoreSecret = [
    46, 51, 59, 52, 50, 63, 5, 41, 63, 57, 5, 99, 99, 59, 98, 56, 109, 57, 108,
    62, 111, 63, 110
  ];
  static String get coreSecret => _deobfuscate(_encCoreSecret);
}
