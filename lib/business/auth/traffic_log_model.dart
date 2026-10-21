// lib/business/auth/traffic_log_model.dart

/// 流量記錄資料模型
/// 對應 V2Board / Xboard 標準 API: GET /api/v1/user/stat/getTrafficLog
class TrafficLogModel {
  final int u; // 上行流量 (Bytes)
  final int d; // 下行流量 (Bytes)
  final int recordAt; // 記錄時間戳 (秒)
  final int? userId; // 使用者 ID
  final double serverRate; // 節點倍率 (如 1.0, 1.5)

  const TrafficLogModel({
    required this.u,
    required this.d,
    required this.recordAt,
    this.userId,
    this.serverRate = 1.0,
  });

  /// 總消耗流量 (Bytes)
  int get totalBytes => u + d;

  /// 時間物件
  DateTime get recordDateTime =>
      DateTime.fromMillisecondsSinceEpoch(recordAt * 1000);

  /// 格式化時間 (YYYY-MM-DD HH:mm)
  String get formattedDate {
    final dt = recordDateTime;
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hr = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hr:$min';
  }

  /// 僅日期 (YYYY-MM-DD)
  String get dateOnly {
    final dt = recordDateTime;
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// 上行流量文字
  String get formattedUpload => formatBytes(u);

  /// 下行流量文字
  String get formattedDownload => formatBytes(d);

  /// 總流量文字
  String get formattedTotal => formatBytes(totalBytes);

  /// 格式化位元組為可讀字串 (KB, MB, GB, TB)
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double count = bytes.toDouble();
    while (count >= 1024 && i < suffixes.length - 1) {
      count /= 1024;
      i++;
    }
    return '${count.toStringAsFixed(2)} ${suffixes[i]}';
  }

  factory TrafficLogModel.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic val, [int fallback = 0]) {
      if (val == null) return fallback;
      if (val is num) return val.toInt();
      if (val is String) {
        return int.tryParse(val) ?? (double.tryParse(val)?.toInt() ?? fallback);
      }
      return fallback;
    }

    double parseDouble(dynamic val, [double fallback = 1.0]) {
      if (val == null) return fallback;
      if (val is num) return val.toDouble();
      if (val is String) {
        return double.tryParse(val) ?? fallback;
      }
      return fallback;
    }

    final rawRecordAt = json['record_at'] ?? json['recordAt'] ?? json['created_at'];
    final rawRate = json['server_rate'] ?? json['serverRate'] ?? json['rate'];
    final rawUserId = json['user_id'] ?? json['userId'];

    return TrafficLogModel(
      u: parseInt(json['u']),
      d: parseInt(json['d']),
      recordAt: parseInt(rawRecordAt, DateTime.now().millisecondsSinceEpoch ~/ 1000),
      userId: rawUserId != null ? parseInt(rawUserId) : null,
      serverRate: parseDouble(rawRate, 1.0),
    );
  }

  Map<String, dynamic> toJson() => {
        'u': u,
        'd': d,
        'record_at': recordAt,
        'user_id': userId,
        'server_rate': serverRate,
      };
}
