// lib/presentation/shop/order_history_screen.dart

import 'package:flutter/material.dart';
import '../../business/auth/auth_manager.dart';
import '../../business/shop/order_model.dart';
import '../../business/shop/shop_manager.dart';
import '../../business/subscription/subscription_engine.dart';
import '../../core/theme/app_theme.dart';
import '../../core/i18n/i18n_service.dart';
import '../../core/utils/error_sanitizer.dart';
import 'order_payment_screen.dart';

/// 歷史訂單記錄介面 (OrderHistoryScreen)
class OrderHistoryScreen extends StatefulWidget {
  final ShopManager shopManager;
  final AuthManager? authManager;
  final SubscriptionEngine? subscriptionEngine;

  const OrderHistoryScreen({
    super.key,
    required this.shopManager,
    this.authManager,
    this.subscriptionEngine,
  });

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  String _resolveStatusText(int status, I18nService i18n) {
    switch (status) {
      case 0:
        return i18n.t('order_status_pending');
      case 1:
        return i18n.t('order_status_opening');
      case 2:
        return i18n.t('order_status_canceled');
      case 3:
        return i18n.t('order_status_completed');
      case 4:
        return i18n.t('order_status_discounted');
      default:
        return i18n.t('order_status_pending');
    }
  }
  bool _isLoading = true;
  String? _errorMessage;
  List<OrderModel> _orders = [];

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final orders = await widget.shopManager.fetchOrders();
      if (mounted) {
        setState(() {
          _orders = orders;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = ErrorSanitizer.sanitize(e);
          _isLoading = false;
        });
      }
    }
  }

  Color _getStatusColor(int status) {
    switch (status) {
      case 0:
        return const Color(0xFFFFA000); // 待支付 (橘)
      case 1:
        return AppTheme.primaryCyan; // 開通中 (藍)
      case 2:
        return Colors.white38; // 已取消 (灰)
      case 3:
        return AppTheme.successEmerald; // 已完成 (綠)
      default:
        return Colors.white54;
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18nService.instance;
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          i18n.t('order_history_title'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: _loadOrders,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 48, color: AppTheme.dangerRose),
                      const SizedBox(height: 12),
                      Text(_errorMessage!, style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _loadOrders,
                        child: Text(i18n.t('order_retry')),
                      ),
                    ],
                  ),
                )
              : _orders.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.receipt_long_outlined, size: 64, color: Colors.white.withOpacity(0.2)),
                          const SizedBox(height: 16),
                          Text(
                            i18n.t('order_history_empty_text'),
                            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 15),
                          ),
                        ],
                      ),
                    )
                  : Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 860),
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          itemCount: _orders.length,
                          itemBuilder: (context, index) {
                        final order = _orders[index];
                        final statusColor = _getStatusColor(order.status);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppTheme.darkCard,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppTheme.darkBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 訂單號與狀態標籤
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      order.tradeNo,
                                      style: TextStyle(
                                        fontFamily: 'Segoe UI',
                                        fontSize: 13,
                                        color: Colors.white.withOpacity(0.6),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: statusColor.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: statusColor.withOpacity(0.3)),
                                    ),
                                    child: Text(
                                      _resolveStatusText(order.status, i18n),
                                      style: TextStyle(
                                        color: statusColor,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // 套餐名稱與金額
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    order.planName ?? '${i18n.t("nav_plan")} #${order.planId}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    order.formattedAmount,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      fontFamily: 'Segoe UI',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              // 建立時間
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    order.createdAtFormatted,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white.withOpacity(0.4),
                                    ),
                                  ),
                                  if (order.isPending)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        TextButton(
                                          style: TextButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          ),
                                          onPressed: () async {
                                            final confirm = await showDialog<bool>(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                backgroundColor: AppTheme.darkCard,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                                title: Text(i18n.t('order_cancel_confirm_title'), style: const TextStyle(color: Colors.white)),
                                                content: Text(
                                                  i18n.t('order_history_cancel_desc'),
                                                  style: TextStyle(color: Colors.white.withOpacity(0.7)),
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(ctx, false),
                                                    child: Text(i18n.t('order_pending_banner_keep'), style: TextStyle(color: Colors.white.withOpacity(0.6))),
                                                  ),
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(ctx, true),
                                                    child: Text(i18n.t('order_pending_banner_confirm_cancel'), style: const TextStyle(color: Colors.redAccent)),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (confirm == true && mounted) {
                                              try {
                                                await widget.shopManager.cancelOrder(order.tradeNo);
                                                if (mounted) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(content: Text(i18n.t('order_history_canceled_success'))),
                                                  );
                                                  _loadOrders();
                                                }
                                              } catch (err) {
                                                if (mounted) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(content: Text(ErrorSanitizer.sanitize(err))),
                                                  );
                                                }
                                              }
                                            }
                                          },
                                          child: Text(i18n.t('order_history_cancel_btn'), style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                                        ),
                                        const SizedBox(width: 8),
                                        FilledButton(
                                          style: FilledButton.styleFrom(
                                            backgroundColor: const Color(0xFF1976D2),
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          onPressed: () async {
                                            final res = await Navigator.of(context).push<bool>(
                                              MaterialPageRoute(
                                                builder: (_) => OrderPaymentScreen(
                                                  tradeNo: order.tradeNo,
                                                  shopManager: widget.shopManager,
                                                  authManager: widget.authManager,
                                                  subscriptionEngine: widget.subscriptionEngine,
                                                ),
                                              ),
                                            );
                                            if (res == true && mounted) {
                                              _loadOrders();
                                            }
                                          },
                                          child: Text(
                                            i18n.t('order_history_pay_now'),
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                          },
                        ),
                      ),
                    ),
    );
  }
}
