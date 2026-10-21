// lib/infrastructure/core_daemon/traffic_stats.dart

/// Mihomo (Clash.Meta) 即時流量數據模型
class TrafficStats {
  final int upSpeed; // 即時上行速率 (Bytes/s)
  final int downSpeed; // 即時下行速率 (Bytes/s)
  final int totalUp; // 本次連線累計上行 (Bytes)
  final int totalDown; // 本次連線累計下行 (Bytes)

  const TrafficStats({
    this.upSpeed = 0,
    this.downSpeed = 0,
    this.totalUp = 0,
    this.totalDown = 0,
  });

  /// 格式化即時速率 (例如: "1.25 MB/s")
  static String formatSpeed(int bytesPerSecond) {
    if (bytesPerSecond <= 0) return '0 KB/s';
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;

    if (bytesPerSecond >= gb) {
      return '${(bytesPerSecond / gb).toStringAsFixed(2)} GB/s';
    } else if (bytesPerSecond >= mb) {
      return '${(bytesPerSecond / mb).toStringAsFixed(2)} MB/s';
    } else {
      return '${(bytesPerSecond / kb).toStringAsFixed(1)} KB/s';
    }
  }

  /// 格式化累計傳輸量
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;

    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(2)} GB';
    } else if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / kb).toStringAsFixed(0)} KB';
    }
  }

  String get upSpeedFormatted => formatSpeed(upSpeed);
  String get downSpeedFormatted => formatSpeed(downSpeed);
  String get totalUpFormatted => formatBytes(totalUp);
  String get totalDownFormatted => formatBytes(totalDown);
  String get totalTrafficFormatted => formatBytes(totalUp + totalDown);

  factory TrafficStats.fromJson(Map<String, dynamic> json) {
    return TrafficStats(
      upSpeed: json['up'] as int? ?? 0,
      downSpeed: json['down'] as int? ?? 0,
      totalUp: json['total_up'] as int? ?? 0,
      totalDown: json['total_down'] as int? ?? 0,
    );
  }
}
