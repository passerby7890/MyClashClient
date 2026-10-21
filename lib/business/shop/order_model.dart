// lib/business/shop/order_model.dart

/// V2Board 訂單模型 (OrderModel)
class OrderModel {
  final String tradeNo;
  final int planId;
  final int totalAmount; // 單位：分 (3600 = ¥36.00)
  final int status; // 0: 待支付, 1: 開通中, 2: 已取消, 3: 已完成
  final String? planName;
  final String? period;
  final int? createdAt;
  final int? updatedAt;

  OrderModel({
    required this.tradeNo,
    required this.planId,
    required this.totalAmount,
    required this.status,
    this.planName,
    this.period,
    this.createdAt,
    this.updatedAt,
  });

  /// 顯示用金額 (元)
  double get amountYuan => totalAmount / 100.0;

  /// 格式化金額字串 (e.g. "¥36.00")
  String get formattedAmount => '¥${amountYuan.toStringAsFixed(2)}';

  /// 建立時間格式化字串
  String get createdAtFormatted {
    if (createdAt == null || createdAt == 0) return '未知時間';
    final dt = DateTime.fromMillisecondsSinceEpoch(createdAt! * 1000);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  /// 狀態中文名稱
  String get statusText {
    switch (status) {
      case 0:
        return '待支付';
      case 1:
        return '開通中';
      case 2:
        return '已取消';
      case 3:
        return '已完成';
      default:
        return '未知狀態';
    }
  }

  bool get isPending => status == 0;

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    String? pName;
    if (json['plan'] is Map && json['plan']['name'] != null) {
      pName = json['plan']['name'].toString();
    } else if (json['plan_name'] != null) {
      pName = json['plan_name'].toString();
    }

    return OrderModel(
      tradeNo: json['trade_no']?.toString() ?? '',
      planId: json['plan_id'] is int ? json['plan_id'] : int.tryParse(json['plan_id']?.toString() ?? '0') ?? 0,
      totalAmount: json['total_amount'] is int
          ? json['total_amount']
          : int.tryParse(json['total_amount']?.toString() ?? '0') ?? 0,
      status: json['status'] is int ? json['status'] : int.tryParse(json['status']?.toString() ?? '0') ?? 0,
      planName: pName,
      period: json['period']?.toString(),
      createdAt: json['created_at'] is int
          ? json['created_at']
          : int.tryParse(json['created_at']?.toString() ?? ''),
      updatedAt: json['updated_at'] is int
          ? json['updated_at']
          : int.tryParse(json['updated_at']?.toString() ?? ''),
    );
  }
}
