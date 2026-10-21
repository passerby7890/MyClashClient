// lib/business/auth/user_model.dart

import 'dart:convert';
import '../../core/i18n/i18n_service.dart';

/// V2Board / Xboard 用戶資料模型
class UserModel {
  final String email;
  final int transferEnable; // 總可用流量 (Bytes)
  final int u; // 已用上行流量 (Bytes)
  final int d; // 已用下行流量 (Bytes)
  final int? expiredAt; // 到期時間 (Unix Timestamp 秒數)
  final int? planId;
  final String? planName;
  final int? balance; // 單位：分
  final int? commissionBalance; // 單位：分
  final String? avatarUrl;
  final String? subscribeUrl;
  final String? token; // 訂閱 Token

  const UserModel({
    required this.email,
    required this.transferEnable,
    required this.u,
    required this.d,
    this.expiredAt,
    this.planId,
    this.planName,
    this.balance,
    this.commissionBalance,
    this.avatarUrl,
    this.subscribeUrl,
    this.token,
  });

  /// 已用總流量 (Bytes)
  int get usedTrafficBytes => u + d;

  /// 剩餘流量 (Bytes)
  int get remainingTrafficBytes {
    final remaining = transferEnable - usedTrafficBytes;
    return remaining > 0 ? remaining : 0;
  }

  /// 流量使用率 (0.0 ~ 1.0)
  double get usedPercentage {
    if (transferEnable <= 0) return 1.0;
    final ratio = usedTrafficBytes / transferEnable;
    return ratio > 1.0 ? 1.0 : ratio;
  }

  /// 剩餘流量百分比 (0.0 ~ 1.0)
  double get remainingPercentage {
    if (transferEnable <= 0) return 0.0;
    final ratio = remainingTrafficBytes / transferEnable;
    return ratio < 0 ? 0.0 : (ratio > 1.0 ? 1.0 : ratio);
  }

  /// 剩餘流量是否低於 10%
  bool get isLowTraffic => transferEnable > 0 && remainingPercentage < 0.10;

  /// 距離到期剩餘天數 (若為長期有效則為 null)
  int? get daysUntilExpired {
    if (expiredAt == null || expiredAt == 0) return null;
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final diff = expiredAt! - nowSeconds;
    return (diff / 86400).ceil();
  }

  /// 是否即將在 3 天內到期
  bool get isExpiringSoon {
    if (isExpired) return false;
    final days = daysUntilExpired;
    return days != null && days <= 3 && days >= 0;
  }

  /// 是否已過期
  bool get isExpired {
    if (expiredAt == null || expiredAt == 0) return false;
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return nowSeconds >= expiredAt!;
  }

  /// 流量是否已耗盡
  bool get isTrafficDepleted => remainingTrafficBytes <= 0;

  /// 帳號是否可用 (未過期且流量充足)
  bool get isAvailable => !isExpired && !isTrafficDepleted;

  /// 佣金餘額格式化 (e.g. "¥0.00")
  String get commissionBalanceFormatted {
    final val = (commissionBalance ?? 0) / 100.0;
    return '¥${val.toStringAsFixed(2)}';
  }

  /// 帳戶餘額格式化 (e.g. "¥0.00")
  String get balanceFormatted {
    final val = (balance ?? 0) / 100.0;
    return '¥${val.toStringAsFixed(2)}';
  }

  /// 格式化流量數字 (Byte -> KB / MB / GB / TB)
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0.00 MB';
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    const tb = gb * 1024;

    if (bytes >= tb) {
      return '${(bytes / tb).toStringAsFixed(2)} TB';
    } else if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(2)} GB';
    } else if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(2)} MB';
    } else {
      return '${(bytes / kb).toStringAsFixed(2)} KB';
    }
  }

  /// 已用流量文字
  String get usedTrafficFormatted => formatBytes(usedTrafficBytes);

  /// 總可用流量文字
  String get totalTrafficFormatted => formatBytes(transferEnable);

  /// 剩餘流量文字
  String get remainingTrafficFormatted => formatBytes(remainingTrafficBytes);

  /// 到期日格式化字串
  String get expiredDateFormatted {
    if (expiredAt == null || expiredAt == 0) {
      return I18nService.instance.t('never_expire');
    }
    final dt = DateTime.fromMillisecondsSinceEpoch(expiredAt! * 1000);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  /// 方便別名相容
  String get expireFormatted => expiredDateFormatted;
  double get trafficUsageRatio => usedPercentage;

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      email: json['email'] as String? ?? '',
      transferEnable: json['transfer_enable'] is int
          ? json['transfer_enable'] as int
          : int.tryParse(json['transfer_enable']?.toString() ?? '0') ?? 0,
      u: json['u'] is int
          ? json['u'] as int
          : int.tryParse(json['u']?.toString() ?? '0') ?? 0,
      d: json['d'] is int
          ? json['d'] as int
          : int.tryParse(json['d']?.toString() ?? '0') ?? 0,
      expiredAt: json['expired_at'] is int
          ? json['expired_at'] as int
          : int.tryParse(json['expired_at']?.toString() ?? ''),
      planId: json['plan_id'] is int
          ? json['plan_id'] as int
          : int.tryParse(json['plan_id']?.toString() ?? ''),
      planName: json['plan_name']?.toString() ?? (json['plan'] is Map ? json['plan']['name']?.toString() : null),
      balance: json['balance'] is int
          ? json['balance'] as int
          : int.tryParse(json['balance']?.toString() ?? ''),
      commissionBalance: json['commission_balance'] is int
          ? json['commission_balance'] as int
          : int.tryParse(json['commission_balance']?.toString() ?? ''),
      avatarUrl: json['avatar_url']?.toString(),
      subscribeUrl: json['subscribe_url'] as String?,
      token: json['token'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'email': email,
        'transfer_enable': transferEnable,
        'u': u,
        'd': d,
        'expired_at': expiredAt,
        'plan_id': planId,
        'plan_name': planName,
        'balance': balance,
        'commission_balance': commissionBalance,
        'avatar_url': avatarUrl,
        'subscribe_url': subscribeUrl,
        'token': token,
      };

  factory UserModel.fromRawJson(String str) =>
      UserModel.fromJson(json.decode(str) as Map<String, dynamic>);

  String toRawJson() => json.encode(toJson());
}
