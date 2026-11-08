// lib/infrastructure/updater/in_app_updater.dart

import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/error_sanitizer.dart';
import '../config/remote_config_model.dart';
import '../core_daemon/core_daemon.dart';
import '../core_daemon/macos_native_proxy.dart';

/// 更新檢查結果模型
class UpdateCheckResult {
  final bool hasUpdate;
  final bool isForceUpdate;
  final String currentVersion;
  final String latestVersion;
  final String? changelog;
  final String? downloadUrl;
  final String? sha256;

  const UpdateCheckResult({
    required this.hasUpdate,
    required this.isForceUpdate,
    required this.currentVersion,
    required this.latestVersion,
    this.changelog,
    this.downloadUrl,
    this.sha256,
  });

  factory UpdateCheckResult.none(String currentVersion) => UpdateCheckResult(
        hasUpdate: false,
        isForceUpdate: false,
        currentVersion: currentVersion,
        latestVersion: currentVersion,
      );
}

/// 應用程式自動更新服務
/// 支援版本比對、完整性雜湊驗證與全平台原位覆蓋安裝
class InAppUpdater {
  final Dio _dio;

  InAppUpdater({Dio? dio}) : _dio = dio ?? _createDirectDio();

  static Dio _createDirectDio() {
    final dio = Dio();
    if (!kIsWeb) {
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.findProxy = (uri) => 'DIRECT';
          client.badCertificateCallback = (cert, host, port) => true;
          return client;
        },
      );
    }
    return dio;
  }

  /// 檢查是否有新版本
  Future<UpdateCheckResult> checkForUpdates({
    required RemoteConfigModel remoteConfig,
    String? mockCurrentVersion,
  }) async {
    String currentVersion = mockCurrentVersion ?? AppConstants.appVersion;

    if (mockCurrentVersion == null) {
      try {
        final packageInfo = await PackageInfo.fromPlatform();
        if (packageInfo.version.isNotEmpty && packageInfo.version != '0.0.0') {
          currentVersion = packageInfo.version;
        }
      } catch (_) {
        currentVersion = AppConstants.appVersion;
      }
    }

    final hasUpdate = remoteConfig.hasNewVersion(currentVersion);
    final isForce = remoteConfig.isForceUpdate(currentVersion);

    if (!hasUpdate) {
      return UpdateCheckResult.none(currentVersion);
    }

    String? downloadUrl;
    String? fileSha256;
    if (kIsWeb) {
      downloadUrl = remoteConfig.apkUrl;
      fileSha256 = remoteConfig.apkSha256;
    } else if (Platform.isAndroid) {
      downloadUrl = remoteConfig.apkUrl;
      fileSha256 = remoteConfig.apkSha256;
    } else if (Platform.isMacOS) {
      downloadUrl = remoteConfig.dmgUrl ?? remoteConfig.exeUrl;
      fileSha256 = remoteConfig.dmgSha256 ?? remoteConfig.exeSha256;
    } else if (Platform.isWindows) {
      downloadUrl = remoteConfig.exeUrl;
      fileSha256 = remoteConfig.exeSha256;
    } else {
      downloadUrl = remoteConfig.dmgUrl ?? remoteConfig.apkUrl ?? remoteConfig.exeUrl;
      fileSha256 = remoteConfig.exeSha256 ?? remoteConfig.apkSha256;
    }

    return UpdateCheckResult(
      hasUpdate: true,
      isForceUpdate: isForce,
      currentVersion: currentVersion,
      latestVersion: remoteConfig.latestVersion,
      changelog: remoteConfig.changelog,
      downloadUrl: downloadUrl,
      sha256: fileSha256,
    );
  }

  /// 從雲端更新清單端點獲取最新更新資訊
  Future<UpdateCheckResult> checkOssJsonUpdates({
    String? mockCurrentVersion,
    String? customUrl,
  }) async {
    String currentVersion = mockCurrentVersion ?? AppConstants.appVersion;
    if (mockCurrentVersion == null) {
      try {
        final packageInfo = await PackageInfo.fromPlatform();
        if (packageInfo.version.isNotEmpty && packageInfo.version != '0.0.0') {
          currentVersion = packageInfo.version;
        }
      } catch (_) {
        currentVersion = AppConstants.appVersion;
      }
    }

    final url = customUrl ?? AppConstants.ossUpdateJsonUrl;
    try {
      final response = await _dio.get(url, options: Options(responseType: ResponseType.json));
      final data = response.data;
      if (data is Map) {
        final latestVersion = (data['version'] ?? AppConstants.appVersion).toString();
        final body = (data['body'] ?? '').toString();
        String? downloadUrl;
        String? sha256Val;

        if (data['platforms'] is Map) {
          final platforms = data['platforms'] as Map;
          if (Platform.isAndroid && platforms['android'] is Map) {
            downloadUrl = platforms['android']['download_url']?.toString();
            sha256Val = (platforms['android']['sha256'] ?? platforms['android']['file_sha256'])?.toString();
          } else if (Platform.isWindows && platforms['windows'] is Map) {
            downloadUrl = platforms['windows']['download_url']?.toString();
            sha256Val = (platforms['windows']['sha256'] ?? platforms['windows']['file_sha256'])?.toString();
          } else if (Platform.isMacOS && platforms['macos'] is Map) {
            downloadUrl = platforms['macos']['download_url']?.toString();
            sha256Val = (platforms['macos']['sha256'] ?? platforms['macos']['file_sha256'])?.toString();
          }
        }
        downloadUrl ??= data['download_url']?.toString();
        sha256Val ??= (data['sha256'] ?? data['file_sha256'])?.toString();

        final hasUpdate = isNewerVersion(currentVersion, latestVersion);
        return UpdateCheckResult(
          hasUpdate: hasUpdate,
          isForceUpdate: false,
          currentVersion: currentVersion,
          latestVersion: latestVersion,
          changelog: body,
          downloadUrl: downloadUrl,
          sha256: sha256Val,
        );
      }
    } catch (_) {
      SafeLog.d('[InAppUpdater] 檢查遠端更新清單未命中，維持當前版本狀態');
    }

    return UpdateCheckResult.none(currentVersion);
  }

  /// 比較版本號: 若 remote > current 則返回 true
  static bool isNewerVersion(String currentVersion, String remoteVersion) {
    try {
      final cParts = currentVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final rParts = remoteVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      while (cParts.length < 3) {
        cParts.add(0);
      }
      while (rParts.length < 3) {
        rParts.add(0);
      }

      for (int i = 0; i < 3; i++) {
        if (rParts[i] > cParts[i]) return true;
        if (rParts[i] < cParts[i]) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// 下載並執行安裝
  /// [onProgress] 回報下載進度 (0.0 ~ 1.0)
  /// [expectedSha256] 若提供則在喚醒安裝器前嚴格驗證 SHA-256 雜湊
  Future<void> downloadAndInstall({
    required String downloadUrl,
    String? expectedSha256,
    required void Function(double progress, String statusText) onProgress,
  }) async {
    if (downloadUrl.isEmpty) {
      throw ArgumentError('更新套件位址無效');
    }

    // Web / iOS 等平台調起系統瀏覽器跳轉
    if (kIsWeb || (!Platform.isAndroid && !Platform.isWindows && !Platform.isMacOS)) {
      final uri = Uri.parse(downloadUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final fileName = Platform.isAndroid
        ? 'update_release.apk'
        : (Platform.isMacOS ? 'update_release.dmg' : 'update_setup.exe');
    final savePath = '${tempDir.path}/$fileName';

    // 1. 下載安裝檔案 (封裝 DioException 防止向上洩漏下載伺服器 URL)
    try {
      await _dio.download(
        downloadUrl,
        savePath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = received / total;
            final percent = (progress * 100).toInt();
            onProgress(progress, '正在下載更新套件... $percent%');
          } else {
            onProgress(0.5, '正在下載更新中...');
          }
        },
      );
    } catch (e) {
      throw Exception(ErrorSanitizer.sanitize(e));
    }

    // 2. 校驗 SHA-256 完整性 (若提供)
    if (expectedSha256 != null && expectedSha256.trim().isNotEmpty) {
      onProgress(0.99, '正在驗證安裝包完整性...');
      final fileBytes = await File(savePath).readAsBytes();
      final actualHash = sha256.convert(fileBytes).toString().toLowerCase();
      if (actualHash != expectedSha256.trim().toLowerCase()) {
        try {
          await File(savePath).delete();
        } catch (_) {}
        throw Exception('更新安裝包完整性校驗未通過，安裝已安全阻斷');
      }
    }

    onProgress(1.0, '下載完成，正在啟動安裝程式...');

    // 3. 喚醒各平台系統安裝器
    if (Platform.isAndroid) {
      final result = await OpenFilex.open(savePath);
      if (result.type != ResultType.done) {
        throw Exception('喚醒安裝程式失敗，請確認已開啟安裝權限');
      }
    } else if (Platform.isMacOS) {
      try {
        await CoreDaemon.instance.stop();
        await MacosNativeProxy.instance.stopCore();
      } catch (_) {}
      await Process.start('open', [savePath], mode: ProcessStartMode.detached);
    } else if (Platform.isWindows) {
      await Process.start(
        savePath,
        [],
        mode: ProcessStartMode.detached,
      );
      exit(0);
    }
  }
}
