// lib/business/shop/plan_model.dart

import 'dart:convert';

/// V2Board 套餐模型 (PlanModel)
class PlanModel {
  final int id;
  final String name;
  final String? content;
  final List<String> features;
  final int transferEnable; // GB
  final int? monthPrice; // 單位：分 (e.g. 3600 = ¥36.00)
  final int? quarterPrice;
  final int? halfYearPrice;
  final int? yearPrice;
  final int? twoYearPrice;
  final int? threeYearPrice;
  final int? onetimePrice;
  final int? resetPrice;
  final int? speedLimit; // Mbps
  final bool show;

  PlanModel({
    required this.id,
    required this.name,
    this.content,
    required this.features,
    required this.transferEnable,
    this.monthPrice,
    this.quarterPrice,
    this.halfYearPrice,
    this.yearPrice,
    this.twoYearPrice,
    this.threeYearPrice,
    this.onetimePrice,
    this.resetPrice,
    this.speedLimit,
    this.show = true,
  });

  /// 最低起始月付或單次金額 (元)
  double get displayPrice {
    if (monthPrice != null && monthPrice! > 0) {
      return monthPrice! / 100.0;
    }
    if (onetimePrice != null && onetimePrice! > 0) {
      return onetimePrice! / 100.0;
    }
    if (yearPrice != null && yearPrice! > 0) {
      return (yearPrice! / 100.0) / 12.0;
    }
    return 0.0;
  }

  /// 顯示用格式化價格 (e.g. "¥36.00")
  String get formattedDisplayPrice {
    return '¥${displayPrice.toStringAsFixed(2)}';
  }

  /// 獲取所有可供選購之週期清單
  List<PlanPeriodOption> get availablePeriods {
    final list = <PlanPeriodOption>[];
    if (monthPrice != null && monthPrice! > 0) {
      list.add(PlanPeriodOption(
        key: 'month_price',
        label: '月付',
        priceCent: monthPrice!,
        priceYuan: monthPrice! / 100.0,
        formattedPrice: '¥${(monthPrice! / 100.0).toStringAsFixed(2)}',
      ));
    }
    if (quarterPrice != null && quarterPrice! > 0) {
      list.add(PlanPeriodOption(
        key: 'quarter_price',
        label: '季付',
        priceCent: quarterPrice!,
        priceYuan: quarterPrice! / 100.0,
        formattedPrice: '¥${(quarterPrice! / 100.0).toStringAsFixed(2)}',
      ));
    }
    if (halfYearPrice != null && halfYearPrice! > 0) {
      list.add(PlanPeriodOption(
        key: 'half_year_price',
        label: '半年付',
        priceCent: halfYearPrice!,
        priceYuan: halfYearPrice! / 100.0,
        formattedPrice: '¥${(halfYearPrice! / 100.0).toStringAsFixed(2)}',
      ));
    }
    if (yearPrice != null && yearPrice! > 0) {
      list.add(PlanPeriodOption(
        key: 'year_price',
        label: '年付',
        priceCent: yearPrice!,
        priceYuan: yearPrice! / 100.0,
        formattedPrice: '¥${(yearPrice! / 100.0).toStringAsFixed(2)}',
      ));
    }
    if (twoYearPrice != null && twoYearPrice! > 0) {
      list.add(PlanPeriodOption(
        key: 'two_year_price',
        label: '兩年付',
        priceCent: twoYearPrice!,
        priceYuan: twoYearPrice! / 100.0,
        formattedPrice: '¥${(twoYearPrice! / 100.0).toStringAsFixed(2)}',
      ));
    }
    if (threeYearPrice != null && threeYearPrice! > 0) {
      list.add(PlanPeriodOption(
        key: 'three_year_price',
        label: '三年付',
        priceCent: threeYearPrice!,
        priceYuan: threeYearPrice! / 100.0,
        formattedPrice: '¥${(threeYearPrice! / 100.0).toStringAsFixed(2)}',
      ));
    }
    if (onetimePrice != null && onetimePrice! > 0) {
      list.add(PlanPeriodOption(
        key: 'onetime_price',
        label: '一次性',
        priceCent: onetimePrice!,
        priceYuan: onetimePrice! / 100.0,
        formattedPrice: '¥${(onetimePrice! / 100.0).toStringAsFixed(2)}',
      ));
    }
    if (list.isEmpty) {
      list.add(const PlanPeriodOption(
        key: 'month_price',
        label: '月付',
        priceCent: 0,
        priceYuan: 0.0,
        formattedPrice: '¥0.00',
      ));
    }
    return list;
  }

  factory PlanModel.fromJson(Map<String, dynamic> json) {
    List<String> parsedFeatures = [];
    final contentRaw = json['content'];
    if (contentRaw is String && contentRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(contentRaw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map && item['feature'] != null) {
              parsedFeatures.add(item['feature'].toString());
            } else if (item is String) {
              parsedFeatures.add(item);
            }
          }
        }
      } catch (_) {
        // 若不是 JSON 字串，以換行符號分割
        parsedFeatures = contentRaw
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
    }

    if (parsedFeatures.isEmpty) {
      final transfer = json['transfer_enable'] ?? 0;
      parsedFeatures = [
        '每月 ${transfer}GB 高速流量',
        '全隧道專線接入，99.99% SLA 保證',
        '解鎖 4K 流媒體與 ChatGPT',
      ];
    }

    return PlanModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      name: json['name']?.toString() ?? '標準套餐',
      content: contentRaw?.toString(),
      features: parsedFeatures,
      transferEnable: json['transfer_enable'] is int
          ? json['transfer_enable']
          : int.tryParse(json['transfer_enable']?.toString() ?? '0') ?? 0,
      monthPrice: json['month_price'] as int?,
      quarterPrice: json['quarter_price'] as int?,
      halfYearPrice: json['half_year_price'] as int?,
      yearPrice: json['year_price'] as int?,
      twoYearPrice: json['two_year_price'] as int?,
      threeYearPrice: json['three_year_price'] as int?,
      onetimePrice: json['onetime_price'] as int?,
      resetPrice: json['reset_price'] as int?,
      speedLimit: json['speed_limit'] as int?,
      show: json['show'] == 1 || json['show'] == true,
    );
  }
}

/// 套餐週期選項模型 (用於 UI 週期切換選擇)
class PlanPeriodOption {
  final String key; // month_price, quarter_price, year_price 等
  final String label; // 月付, 季付, 年付
  final int priceCent; // 分
  final double priceYuan; // 元
  final String formattedPrice; // ¥98.00

  const PlanPeriodOption({
    required this.key,
    required this.label,
    required this.priceCent,
    required this.priceYuan,
    required this.formattedPrice,
  });
}

