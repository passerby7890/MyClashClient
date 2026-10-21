// lib/infrastructure/updater/in_app_updater.dart

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_constants.dart';
import '../config/remote_config_model.dart';

/// 更新檢查結果模型
class UpdateCheckResult {
  final bool hasUpdate;
  final bool isForceUpdate;
  final String currentVersion;
  final String latestVersion;
  final String? changelog;
  final String? downloadUrl;

  const UpdateCheckResult({
    required this.hasUpdate,
    required this.isForceUpdate,
    required this.currentVersion,
    required this.latestVersion,
    this.changelog,
    this.downloadUrl,
  });

  factory UpdateCheckResult.none(String currentVersion) => UpdateCheckResult(
        hasUpdate: false,
        isForceUpdate: false,
        currentVersion: currentVersion,
        latestVersion: currentVersion,
      );
}

/// 應用程式自動更新服務
/// 支援版本比對、斷點/進度條下載與全平台原位覆蓋安裝 (Android APK / Windows EXE)
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
    if (kIsWeb) {
      downloadUrl = remoteConfig.apkUrl;
    } else if (Platform.isAndroid) {
      downloadUrl = remoteConfig.apkUrl;
    } else if (Platform.isMacOS) {
      downloadUrl = remoteConfig.dmgUrl ?? remoteConfig.exeUrl;
    } else if (Platform.isWindows) {
      downloadUrl = remoteConfig.exeUrl;
    } else {
      downloadUrl = remoteConfig.dmgUrl ?? remoteConfig.apkUrl ?? remoteConfig.exeUrl;
    }

    return UpdateCheckResult(
      hasUpdate: true,
      isForceUpdate: isForce,
      currentVersion: currentVersion,
      latestVersion: remoteConfig.latestVersion,
      changelog: remoteConfig.changelog,
      downloadUrl: downloadUrl,
    );
  }

  /// 從阿里雲 OSS update.json 獲取最新更新資訊 (更新URL: novaclash.../update.json)
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

        if (data['platforms'] is Map) {
          final platforms = data['platforms'] as Map;
          if (Platform.isAndroid && platforms['android'] is Map) {
            downloadUrl = platforms['android']['download_url']?.toString();
          } else if (Platform.isWindows && platforms['windows'] is Map) {
            downloadUrl = platforms['windows']['download_url']?.toString();
          } else if (Platform.isMacOS && platforms['macos'] is Map) {
            downloadUrl = platforms['macos']['download_url']?.toString();
          }
        }
        downloadUrl ??= data['download_url']?.toString();

        final hasUpdate = isNewerVersion(currentVersion, latestVersion);
        return UpdateCheckResult(
          hasUpdate: hasUpdate,
          isForceUpdate: false,
          currentVersion: currentVersion,
          latestVersion: latestVersion,
          changelog: body,
          downloadUrl: downloadUrl,
        );
      }
    } catch (e) {
      // ignore: avoid_print
      print('[InAppUpdater] 檢查 OSS update.json 失敗: $e');
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
  Future<void> downloadAndInstall({
    required String downloadUrl,
    required void Function(double progress, String statusText) onProgress,
  }) async {
    if (downloadUrl.isEmpty) {
      throw ArgumentError('下載網址為空');
    }

    // Web / iOS: 調起系統瀏覽器跳轉
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

    // 1. 下載安裝檔案
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

    onProgress(1.0, '下載完成，正在啟動安裝程式...');

    // 2. 喚醒各平台系統安裝器
    if (Platform.isAndroid) {
      final result = await OpenFilex.open(savePath);
      if (result.type != ResultType.done) {
        throw Exception('喚醒 Android 安裝程式失敗: ${result.message} (請確認已開啟未知來源安裝權限)');
      }
    } else if (Platform.isMacOS) {
      // 呼叫 macOS open 指令掛載 DMG 或執行安裝器
      await Process.start('open', [savePath], mode: ProcessStartMode.detached);
    } else if (Platform.isWindows) {
      // 呼叫 Windows 安裝器原位覆蓋安裝
      await Process.start(
        savePath,
        [],
        mode: ProcessStartMode.detached,
      );
      // 關閉目前程式讓安裝器覆蓋執行
      exit(0);
    }
  }
}
