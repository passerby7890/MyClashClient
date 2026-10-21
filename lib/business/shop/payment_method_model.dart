// lib/business/shop/payment_method_model.dart

/// 支付方式模型 (PaymentMethodModel)
class PaymentMethodModel {
  final int id;
  final String name;
  final String payment; // e.g. EPay, UpayPro
  final String? icon;

  PaymentMethodModel({
    required this.id,
    required this.name,
    required this.payment,
    this.icon,
  });

  factory PaymentMethodModel.fromJson(Map<String, dynamic> json) {
    return PaymentMethodModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      name: json['name']?.toString() ?? '未知支付方式',
      payment: json['payment']?.toString() ?? '',
      icon: json['icon']?.toString(),
    );
  }
}
