// lib/business/shop/shop_manager.dart

import 'package:dio/dio.dart';
import '../../core/network/dio_client.dart';
import 'order_model.dart';
import 'payment_method_model.dart';
import 'plan_model.dart';

/// 商店與訂單管理器 (ShopManager)
/// 負責套餐列表拉取、訂單建立、支付方式讀取與收銀台結帳發起
class ShopManager {
  final DioClient dioClient;

  List<PlanModel> _plans = [];
  List<PaymentMethodModel> _paymentMethods = [];

  List<PlanModel> get plans => _plans;
  List<PaymentMethodModel> get paymentMethods => _paymentMethods;

  ShopManager({required this.dioClient});

  /// 1. 獲取所有可用套餐
  Future<List<PlanModel>> fetchPlans() async {
    try {
      final response = await dioClient.dio.get('/api/v1/user/plan/fetch');
      final data = response.data['data'];
      if (data is List) {
        _plans = data
            .map((item) => PlanModel.fromJson(Map<String, dynamic>.from(item as Map)))
            .where((p) => p.show)
            .toList();
        return _plans;
      }
      return [];
    } on DioException catch (e) {
      throw Exception(e.response?.data?['message'] ?? '獲取套餐失敗');
    }
  }

  /// 2. 獲取可用支付方式
  Future<List<PaymentMethodModel>> fetchPaymentMethods() async {
    try {
      final response = await dioClient.dio.get('/api/v1/user/order/getPaymentMethod');
      final data = response.data['data'];
      if (data is List) {
        _paymentMethods = data
            .map((item) => PaymentMethodModel.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
        return _paymentMethods;
      }
      return [];
    } on DioException catch (e) {
      throw Exception(e.response?.data?['message'] ?? '獲取支付方式失敗');
    }
  }

  /// 3. 建立購買訂單 (返回 trade_no)
  Future<String> createOrder({
    required int planId,
    required String period,
    String? couponCode,
  }) async {
    try {
      final payload = <String, dynamic>{
        'plan_id': planId,
        'period': period,
      };
      if (couponCode != null && couponCode.isNotEmpty) {
        payload['coupon_code'] = couponCode;
      }

      final response = await dioClient.dio.post(
        '/api/v1/user/order/save',
        data: payload,
      );

      final tradeNo = response.data['data']?.toString();
      if (tradeNo == null || tradeNo.isEmpty) {
        throw Exception('訂單建立失敗：未回傳訂單號');
      }
      return tradeNo;
    } on DioException catch (e) {
      throw Exception(e.response?.data?['message'] ?? '建立訂單失敗');
    }
  }

  /// 4. 獲取訂單詳情
  Future<OrderModel> getOrderDetail(String tradeNo) async {
    try {
      final response = await dioClient.dio.get(
        '/api/v1/user/order/detail',
        queryParameters: {'trade_no': tradeNo},
      );
      final data = response.data['data'];
      if (data is Map) {
        return OrderModel.fromJson(Map<String, dynamic>.from(data));
      }
      throw Exception('訂單詳情資料格式錯誤');
    } on DioException catch (e) {
      throw Exception(e.response?.data?['message'] ?? '獲取訂單詳情失敗');
    }
  }

  /// 5. 發起支付結帳 (返回收銀台 URL 或原生支付參數)
  Future<String> checkoutOrder({
    required String tradeNo,
    required int methodId,
  }) async {
    try {
      final response = await dioClient.dio.post(
        '/api/v1/user/order/checkout',
        data: {
          'trade_no': tradeNo,
          'method': methodId,
        },
      );

      final respData = response.data;
      // V2Board 回傳結構通常為 {type: 1, data: "https://..."} 或直接返回 URL
      if (respData is Map) {
        if (respData['data'] is String) {
          return respData['data'].toString();
        } else if (respData['data'] is Map && respData['data']['data'] != null) {
          return respData['data']['data'].toString();
        }
      }
      return respData.toString();
    } on DioException catch (e) {
      throw Exception(e.response?.data?['message'] ?? '發起支付失敗');
    }
  }

  /// 6. 取消訂單
  Future<bool> cancelOrder(String tradeNo) async {
    try {
      final response = await dioClient.dio.post(
        '/api/v1/user/order/cancel',
        data: {'trade_no': tradeNo},
      );
      return response.data['data'] == true;
    } catch (_) {
      return false;
    }
  }

  /// 7. 獲取歷史訂單列表
  Future<List<OrderModel>> fetchOrders() async {
    try {
      final response = await dioClient.dio.get('/api/v1/user/order/fetch');
      final data = response.data['data'];
      if (data is List) {
        return data
            .map((item) => OrderModel.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
      }
      return [];
    } on DioException catch (e) {
      throw Exception(e.response?.data?['message'] ?? '獲取歷史訂單失敗');
    }
  }

  /// 8. 輕量/快速檢查訂單狀態 (供客戶端定時輪詢與前台喚醒檢測)
  /// 回傳 status: 0=待支付, 1=開通中, 2=已取消, 3=已完成
  Future<int> checkOrderStatus(String tradeNo) async {
    try {
      final response = await dioClient.dio.get(
        '/api/v1/user/order/check',
        queryParameters: {'trade_no': tradeNo},
      );
      final respData = response.data;
      if (respData is Map && respData['data'] != null) {
        final d = respData['data'];
        if (d is int) return d;
        if (d is bool) return d ? 3 : 0;
        final parsed = int.tryParse(d.toString());
        if (parsed != null) return parsed;
      }
    } catch (_) {
      // 若 check 介面未開啟或自定義異常，平滑降級為 getOrderDetail
    }

    try {
      final order = await getOrderDetail(tradeNo);
      return order.status;
    } catch (e) {
      rethrow;
    }
  }

  /// 測試用：注入套餐列表
  void setPlansForTesting(List<PlanModel> plans) {
    _plans = plans;
  }
}
