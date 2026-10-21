import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_constants.dart';
import '../crypto/aes_decryptor.dart';

/// 安全儲存服務
/// 使用 flutter_secure_storage 與 AES-256-CBC 雙重防護將敏感憑據 (JWT Token 等) 加密存放
/// 杜絕以明文存放在 SharedPreferences 與磁碟，恪守零明文原則
class SecureStorageService {
  final FlutterSecureStorage _storage;
  final Map<String, String> _memoryFallback = {};
  final AesDecryptor _aes = AesDecryptor();

  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
              ),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
              mOptions: MacOsOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
              wOptions: WindowsOptions(
                useBackwardCompatibility: false,
              ),
            );

  static bool isTestMode = false;

  bool get _isTestEnv {
    if (isTestMode) return true;
    if (Platform.environment['FLUTTER_TEST'] == 'true') return true;
    final binding = WidgetsBinding.instance.runtimeType.toString();
    return binding.contains('Test');
  }

  /// 通用鍵值寫入 (具備 Keystore 加密與單元測試/無綁定安全容錯)
  Future<void> write(String key, String value) async {
    _memoryFallback[key] = value;
    if (_isTestEnv) return;
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {}
  }

  /// 通用鍵值讀取
  Future<String?> read(String key) async {
    if (_isTestEnv) return _memoryFallback[key];
    try {
      final val = await _storage.read(key: key);
      if (val != null) {
        _memoryFallback[key] = val;
        return val;
      }
    } catch (_) {}
    return _memoryFallback[key];
  }

  /// 通用鍵值刪除
  Future<void> delete(String key) async {
    _memoryFallback.remove(key);
    if (_isTestEnv) return;
    try {
      await _storage.delete(key: key);
    } catch (_) {}
  }

  /// 儲存 JWT Token (AES-256 雙重密文化存儲)
  Future<void> saveToken(String token) async {
    final enc = _aes.encrypt(token);
    await write(AppConstants.storageJwtToken, enc);
  }

  /// 獲取 JWT Token (自動解密還原)
  Future<String?> getToken() async {
    final raw = await read(AppConstants.storageJwtToken);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return _aes.decrypt(raw);
    } catch (_) {
      return raw; // 容錯相容既有未加密格式
    }
  }

  /// 刪除 JWT Token
  Future<void> deleteToken() async {
    await delete(AppConstants.storageJwtToken);
  }

  /// 儲存用戶快取資料 (JSON - AES-256 加密存儲)
  Future<void> saveUserInfoJson(String jsonStr) async {
    final enc = _aes.encrypt(jsonStr);
    await write(AppConstants.storageUserInfo, enc);
  }

  /// 獲取用戶快取資料 (自動解密還原)
  Future<String?> getUserInfoJson() async {
    final raw = await read(AppConstants.storageUserInfo);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return _aes.decrypt(raw);
    } catch (_) {
      return raw;
    }
  }

  /// 儲存收藏節點清單
  Future<void> saveFavoriteNodeIds(Set<String> ids) async {
    await write(
      AppConstants.storageFavoriteNodeIds,
      ids.join(','),
    );
  }

  /// 獲取收藏節點清單
  Future<Set<String>> getFavoriteNodeIds() async {
    final str = await read(AppConstants.storageFavoriteNodeIds);
    if (str == null || str.trim().isEmpty) return {};
    return str.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
  }

  /// 儲存加密節點金庫內容 (磁碟零明文安全存儲)
  Future<void> saveEncryptedNodes(String rawYaml) async {
    final enc = _aes.encrypt(rawYaml);
    await write(AppConstants.storageEncryptedNodes, enc);
  }

  /// 獲取加密節點金庫內容 (自動解密還原)
  Future<String?> getEncryptedNodes() async {
    final raw = await read(AppConstants.storageEncryptedNodes);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return _aes.decrypt(raw);
    } catch (_) {
      return raw;
    }
  }

  /// 刪除加密節點金庫內容
  Future<void> deleteEncryptedNodes() async {
    await delete(AppConstants.storageEncryptedNodes);
  }

  /// 清除所有認證憑證與加密金庫 (用於登出或 401 攔截)
  Future<void> clearAll() async {
    _memoryFallback.clear();
    await delete(AppConstants.storageJwtToken);
    await delete(AppConstants.storageUserInfo);
    await delete(AppConstants.storageSelectedNodeId);
    await delete(AppConstants.storageEncryptedNodes);
  }
}
