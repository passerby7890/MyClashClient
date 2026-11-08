// lib/infrastructure/config/remote_config_model.dart

import 'dart:convert';
import '../../core/constants/app_constants.dart';

/// 遠端動態配置資料模型
/// 由加密配置端點解析之 Base64 或 AES 解密後還原產生
class RemoteConfigModel {
  final String apiDomain;
  final List<String> backupApiDomains;
  final String latestVersion;
  final String minVersion;
  final String? apkUrl;
  final String? exeUrl;
  final String? dmgUrl;
  final String? apkSha256;
  final String? exeSha256;
  final String? dmgSha256;
  final String? signature;
  final String? changelog;
  final String? websiteUrl;
  final String? appName;
  final String? customerUrl;
  final String? crispId;
  final String? inviteLink;
  final bool enableNotice;
  final bool enableExchange;
  final bool enableTrafficDetails;
  final bool enableOnlineTicket;
  final List<dynamic> carouselItems;
  final List<dynamic> campusHosts;
  final dynamic bootstrapProxy;

  const RemoteConfigModel({
    required this.apiDomain,
    this.backupApiDomains = const [],
    required this.latestVersion,
    required this.minVersion,
    this.apkUrl,
    this.exeUrl,
    this.dmgUrl,
    this.apkSha256,
    this.exeSha256,
    this.dmgSha256,
    this.signature,
    this.changelog,
    this.websiteUrl,
    this.appName,
    this.customerUrl,
    this.crispId,
    this.inviteLink,
    this.enableNotice = true,
    this.enableExchange = false,
    this.enableTrafficDetails = true,
    this.enableOnlineTicket = true,
    this.carouselItems = const [],
    this.campusHosts = const [],
    this.bootstrapProxy,
  });

  /// 取得所有可用 API 網域陣列 (主要網域在前，備用網域在後，自動排除靜態門戶網域)
  List<String> get allApiDomains {
    final list = <String>[];
    void addDomain(String d) {
      var trimmed = d.trim();
      while (trimmed.endsWith('/')) {
        trimmed = trimmed.substring(0, trimmed.length - 1);
      }
      if (trimmed.endsWith('/api/v1')) {
        trimmed = trimmed.substring(0, trimmed.length - 7);
      }
      // 確保門戶靜態網站絕不被誤當成 API 網域使用
      if (trimmed.isNotEmpty &&
          !list.contains(trimmed) &&
          !trimmed.contains(_portalHost)) {
        list.add(trimmed);
      }
    }

    if (apiDomain.isNotEmpty) {
      addDomain(apiDomain);
    }
    for (final domain in backupApiDomains) {
      addDomain(domain);
    }
    return list;
  }

  /// 從 JSON Map 建構 (相容標準格式與動態配置格式)
  factory RemoteConfigModel.fromJson(Map<String, dynamic> json) {
    List<String> parseBackups(dynamic raw) {
      if (raw is List) {
        return raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      }
      return [];
    }

    final hostSource = json['host_source']?.toString().trim();
    final hosts = parseBackups(json['hosts']);

    String apiDomain = json['api_domain'] as String? ?? '';
    List<String> backupApiDomains = parseBackups(json['backup_api_domains']);

    // hosts 陣列為真實 API 伺服器，host_source 為官網前台
    if (apiDomain.isEmpty && hosts.isNotEmpty) {
      apiDomain = hosts.first;
      final remainingHosts = hosts.sublist(1);
      for (final h in remainingHosts) {
        if (!backupApiDomains.contains(h)) {
          backupApiDomains.add(h);
        }
      }
    } else if (apiDomain.isEmpty && hostSource != null && hostSource.isNotEmpty) {
      if (!hostSource.contains(_portalHost)) {
        apiDomain = hostSource;
      }
    }

    if (apiDomain.isEmpty) {
      apiDomain = AppConstants.fallbackApiDomains.first;
    }

    while (apiDomain.endsWith('/')) {
      apiDomain = apiDomain.substring(0, apiDomain.length - 1);
    }
    backupApiDomains = backupApiDomains
        .map((h) => h.endsWith('/') ? h.substring(0, h.length - 1) : h)
        .where((h) => !h.contains(_portalHost))
        .toList();

    bool parseBool(dynamic val, bool defaultVal) {
      if (val == null) return defaultVal;
      if (val is bool) return val;
      if (val is num) return val != 0;
      return val.toString() == '1' || val.toString().toLowerCase() == 'true';
    }

    return RemoteConfigModel(
      apiDomain: apiDomain,
      backupApiDomains: backupApiDomains,
      latestVersion: json['latest_version'] as String? ?? '1.0.0',
      minVersion: json['min_version'] as String? ?? '1.0.0',
      apkUrl: (json['apk_url'] ?? json['UpdateUrl']) as String?,
      exeUrl: (json['exe_url'] ?? json['win_url'] ?? json['windows_url'] ?? json['exeUrl']) as String?,
      dmgUrl: (json['dmg_url'] ?? json['mac_url'] ?? json['macos_url'] ?? json['dmgUrl']) as String?,
      apkSha256: (json['apk_sha256'] ?? json['sha256']) as String?,
      exeSha256: json['exe_sha256'] as String?,
      dmgSha256: (json['dmg_sha256'] ?? json['mac_sha256']) as String?,
      signature: (json['sig'] ?? json['signature']) as String?,
      changelog: json['changelog'] as String?,
      websiteUrl: hostSource ?? (json['website_url'] as String?),
      appName: (json['Authentication'] ?? json['app_name']) as String?,
      customerUrl: (json['Customer'] ?? json['customer_url']) as String?,
      crispId: (json['crisp'] ?? json['crisp_id']) as String?,
      inviteLink: (json['InviteLink'] ?? json['invite_link']) as String?,
      enableNotice: parseBool(json['notice'], true),
      enableExchange: parseBool(json['exchange'], false),
      enableTrafficDetails: parseBool(json['TrafficDetails'], true),
      enableOnlineTicket: parseBool(json['OnlineTicket'], true),
      carouselItems: (json['Carousel'] as List?) ?? const [],
      campusHosts: (json['campusHosts'] as List?) ?? const [],
      bootstrapProxy: json['bootstrap_proxy'] ?? json['bootstrapProxy'],
    );
  }

  /// 從 JSON 字串反序列化
  factory RemoteConfigModel.fromRawJson(String str) =>
      RemoteConfigModel.fromJson(json.decode(str) as Map<String, dynamic>);

  /// 序列化為 JSON Map
  Map<String, dynamic> toJson() => {
        'api_domain': apiDomain,
        'backup_api_domains': backupApiDomains,
        'latest_version': latestVersion,
        'min_version': minVersion,
        'apk_url': apkUrl,
        'exe_url': exeUrl,
        'dmg_url': dmgUrl,
        'apk_sha256': apkSha256,
        'exe_sha256': exeSha256,
        'sig': signature,
        'changelog': changelog,
        'host_source': websiteUrl,
        'website_url': websiteUrl,
        'Authentication': appName,
        'Customer': customerUrl,
        'crisp': crispId,
        'bootstrap_proxy': bootstrapProxy,
        'InviteLink': inviteLink,
        'notice': enableNotice ? 1 : 0,
        'exchange': enableExchange ? 1 : 0,
        'TrafficDetails': enableTrafficDetails ? 1 : 0,
        'OnlineTicket': enableOnlineTicket ? 1 : 0,
        'Carousel': carouselItems,
        'campusHosts': campusHosts,
      };

  /// 序列化為 JSON 字串
  String toRawJson() => json.encode(toJson());

  /// 判定是否有新版本 (以語意化版本號比對，如 1.2.0 > 1.1.0)
  bool hasNewVersion(String currentVersion) {
    return _compareVersions(latestVersion, currentVersion) > 0;
  }

  /// 判定是否為強制更新 (當前版本小於 min_version)
  bool isForceUpdate(String currentVersion) {
    return _compareVersions(currentVersion, minVersion) < 0;
  }

  /// 語意化版本比對輔助函式
  /// 回傳值: 1 表示 v1 > v2; -1 表示 v1 < v2; 0 表示相等
  static int _compareVersions(String v1, String v2) {
    final cleanV1 = v1.replaceAll(RegExp(r'[^0-9.]'), '');
    final cleanV2 = v2.replaceAll(RegExp(r'[^0-9.]'), '');

    final parts1 = cleanV1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final parts2 = cleanV2.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    final maxLen = parts1.length > parts2.length ? parts1.length : parts2.length;
    for (int i = 0; i < maxLen; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;
      if (p1 > p2) return 1;
      if (p1 < p2) return -1;
    }
    return 0;
  }

  static String get _portalHost =>
      AppConstants.officialWebsiteUrl.replaceAll('https://', '').replaceAll('http://', '').replaceAll('/', '');

  /// 兜底靜態配置 (當 DoH 與本機快取均不存在時的緊急降級配置)
  factory RemoteConfigModel.fallback({required List<String> fallbackDomains}) {
    final validDomains = fallbackDomains.where((d) => !d.contains(_portalHost)).toList();
    final primary = validDomains.isNotEmpty ? validDomains.first : (AppConstants.fallbackApiDomains.isNotEmpty ? AppConstants.fallbackApiDomains.first : '');
    final backups = validDomains.length > 1 ? validDomains.sublist(1) : <String>[];
    return RemoteConfigModel(
      apiDomain: primary,
      backupApiDomains: backups,
      websiteUrl: AppConstants.officialWebsiteUrl,
      latestVersion: AppConstants.appVersion,
      minVersion: '1.0.0',
      changelog: '兜底離線預設配置',
    );
  }

  @override
  String toString() {
    return 'RemoteConfigModel(latestVersion: $latestVersion, minVersion: $minVersion, routes: ${allApiDomains.length})';
  }
}
