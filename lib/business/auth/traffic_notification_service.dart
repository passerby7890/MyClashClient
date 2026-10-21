// lib/business/auth/traffic_notification_service.dart

import 'package:flutter/foundation.dart';
import '../../core/constants/app_constants.dart';
import '../../core/storage/secure_storage_service.dart';
import 'user_model.dart';

/// 流量預警類型
enum TrafficAlertType {
  exhausted, // 流量已耗盡
  expired, // 帳號已過期
  expiringSoon, // 即將在 3 天內到期
  lowTraffic, // 剩餘流量低於 10%
}

/// 預警提醒資料模型
class TrafficAlert {
  final TrafficAlertType type;
  final String title;
  final String message;
  final bool isBlocking; // 是否達到阻斷/無法連線之嚴重度

  const TrafficAlert({
    required this.type,
    required this.title,
    required this.message,
    required this.isBlocking,
  });
}

/// 流量即將耗盡 / 到期系統本地推播與提醒服務 (TODO-03)
class TrafficNotificationService extends ChangeNotifier {
  static final TrafficNotificationService instance =
      TrafficNotificationService._internal();
  TrafficNotificationService._internal();

  SecureStorageService? _storageService;
  TrafficAlert? _currentAlert;

  TrafficAlert? get currentAlert => _currentAlert;

  void init({SecureStorageService? storageService}) {
    _storageService = storageService ?? SecureStorageService();
  }

  /// 檢查用戶狀態並判定是否應當發出預警
  /// [forceCheck] 若為 true 則忽略冷卻時間 (用於手動檢查或連線前檢測)
  Future<TrafficAlert?> checkTrafficAlert(
    UserModel user, {
    bool forceCheck = false,
  }) async {
    TrafficAlert? detectedAlert;

    // 1. 優先級一：流量耗盡
    if (user.isTrafficDepleted && user.transferEnable > 0) {
      detectedAlert = const TrafficAlert(
        type: TrafficAlertType.exhausted,
        title: '⚠️ 流量已耗盡',
        message: '您的可用流量已全部用盡，代理連線將被阻斷，請前往商城購買新套餐或重置流量。',
        isBlocking: true,
      );
    }
    // 2. 優先級二：已過期
    else if (user.isExpired) {
      detectedAlert = const TrafficAlert(
        type: TrafficAlertType.expired,
        title: '⛔ 訂閱已過期',
        message: '您的會員服務已過期，無法建立代理連線，請及時續約以恢復高速網路。',
        isBlocking: true,
      );
    }
    // 3. 優先級三：即將到期 (距到期 <= 3 天)
    else if (user.expiredAt != null && user.expiredAt! > 0) {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final diffSeconds = user.expiredAt! - nowSec;
      final days = (diffSeconds / 86400).ceil();
      if (days <= 3 && days >= 0) {
        detectedAlert = TrafficAlert(
          type: TrafficAlertType.expiringSoon,
          title: '⏳ 訂閱即將到期提醒',
          message: '您的會員訂閱將在 $days 天後到期，為避免連線中斷，請提前續約！',
          isBlocking: false,
        );
      }
    }

    // 4. 優先級四：剩餘流量低於 10%
    if (detectedAlert == null && user.transferEnable > 0) {
      final ratio = user.remainingTrafficBytes / user.transferEnable;
      if (ratio < 0.10) {
        final percent = (ratio * 100).toStringAsFixed(1);
        detectedAlert = TrafficAlert(
          type: TrafficAlertType.lowTraffic,
          title: '📉 剩餘流量不足 10%',
          message: '您的剩餘流量僅剩 $percent% (${user.remainingTrafficFormatted})，請及時續費或升級套餐！',
          isBlocking: false,
        );
      }
    }

    if (detectedAlert == null) {
      _currentAlert = null;
      notifyListeners();
      return null;
    }

    // 冷卻時間檢查 (非阻斷性提醒每 4 小時最多彈出一次)
    if (!forceCheck && !detectedAlert.isBlocking && _storageService != null) {
      try {
        final lastAlertStr = await _storageService!
            .read(AppConstants.storageLastTrafficAlertTime);
        if (lastAlertStr != null) {
          final lastAlertTime = int.tryParse(lastAlertStr) ?? 0;
          final now = DateTime.now().millisecondsSinceEpoch;
          // 4 小時冷卻
          if (now - lastAlertTime < 4 * 3600 * 1000) {
            _currentAlert = detectedAlert;
            notifyListeners();
            return null; // 在冷卻時間內不彈出中斷
          }
        }
      } catch (_) {}
    }

    // 記錄提醒時間
    if (_storageService != null) {
      try {
        await _storageService!.write(
          AppConstants.storageLastTrafficAlertTime,
          DateTime.now().millisecondsSinceEpoch.toString(),
        );
      } catch (_) {}
    }

    _currentAlert = detectedAlert;
    notifyListeners();
    return detectedAlert;
  }

  /// 清除當前警示
  void dismissAlert() {
    _currentAlert = null;
    notifyListeners();
  }
}
