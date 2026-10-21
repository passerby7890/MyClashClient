// lib/core/crypto/aes_decryptor.dart

import 'package:encrypt/encrypt.dart' as enc;
import '../constants/app_constants.dart';

/// AES-256-CBC 解密工具類別
/// 遵循 PKCS7 Padding 規範，專門用於解密 DNS TXT 紀錄獲取的防封鎖設定資料
class AesDecryptor {
  final enc.Key _key;
  final enc.IV _iv;

  AesDecryptor({String? key, String? iv})
      : _key = enc.Key.fromUtf8(key ?? AppConstants.defaultAesKey),
        _iv = enc.IV.fromUtf8(iv ?? AppConstants.defaultAesIv);

  /// 解密 Base64 編碼的 AES-256-CBC 密文字串
  /// [encryptedText] 傳入之密文字串（可能包含 DNS TXT 兩端自帶的引號）
  String decrypt(String encryptedText) {
    // 1. 去除 DNS 記錄中常見的前後雙引號或轉義符號及空白
    var sanitized = encryptedText.trim();
    if (sanitized.startsWith('"') && sanitized.endsWith('"')) {
      sanitized = sanitized.substring(1, sanitized.length - 1);
    }
    // 移除多段 TXT 之間可能存在的換行或引號
    sanitized = sanitized.replaceAll('"', '').replaceAll('\n', '').replaceAll(' ', '');

    if (sanitized.isEmpty) {
      throw ArgumentError('密文字串為空，無法進行解密');
    }

    try {
      final encrypter = enc.Encrypter(
        enc.AES(
          _key,
          mode: enc.AESMode.cbc,
          padding: 'PKCS7',
        ),
      );

      final decrypted = encrypter.decrypt64(sanitized, iv: _iv);
      return decrypted;
    } catch (e) {
      throw FormatException('AES-256 解密失敗: ${e.toString()} (請檢查金鑰與 IV 是否匹配)');
    }
  }

  /// 加密明文字串（方便後台生成 TXT 記錄或單元測試使用）
  String encrypt(String plainText) {
    try {
      final encrypter = enc.Encrypter(
        enc.AES(
          _key,
          mode: enc.AESMode.cbc,
          padding: 'PKCS7',
        ),
      );

      final encrypted = encrypter.encrypt(plainText, iv: _iv);
      return encrypted.base64;
    } catch (e) {
      throw FormatException('AES-256 加密失敗: ${e.toString()}');
    }
  }

  /// 便捷靜態解密方法
  static String decryptDefault(String encryptedText) {
    return AesDecryptor().decrypt(encryptedText);
  }

  /// 便捷靜態加密方法
  static String encryptDefault(String plainText) {
    return AesDecryptor().encrypt(plainText);
  }
}
