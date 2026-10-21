// lib/presentation/shop/order_payment_screen.dart

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../business/shop/order_model.dart';
import '../../business/shop/payment_method_model.dart';
import '../../business/shop/shop_manager.dart';
import '../../core/i18n/i18n_service.dart';
import '../../core/theme/app_theme.dart';

/// 訂單支付頁面 (OrderPaymentScreen)
/// 統一深色科技風 (Dark Tech Material 3)，藍色高亮訂單卡、多渠道支付方式選擇與結帳
class OrderPaymentScreen extends StatefulWidget {
  final String tradeNo;
  final ShopManager shopManager;

  const OrderPaymentScreen({
    super.key,
    required this.tradeNo,
    required this.shopManager,
  });

  @override
  State<OrderPaymentScreen> createState() => _OrderPaymentScreenState();
}

class _OrderPaymentScreenState extends State<OrderPaymentScreen> {
  bool _isLoading = true;
  bool _isCheckingOut = false;
  String? _errorMessage;

  OrderModel? _order;
  List<PaymentMethodModel> _paymentMethods = [];
  int? _selectedMethodId;

  @override
  void initState() {
    super.initState();
    _loadOrderData();
  }

  Future<void> _loadOrderData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final order = await widget.shopManager.getOrderDetail(widget.tradeNo);
      var methods = widget.shopManager.paymentMethods;
      if (methods.isEmpty) {
        methods = await widget.shopManager.fetchPaymentMethods();
      }

      if (mounted) {
        setState(() {
          _order = order;
          _paymentMethods = methods;
          if (methods.isNotEmpty && _selectedMethodId == null) {
            _selectedMethodId = methods.first.id;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  /// 處理結帳並調起外部收銀台 / 網頁
  Future<void> _handleCheckout() async {
    if (_selectedMethodId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(I18nService.instance.t('order_select_pay_method'))),
      );
      return;
    }

    setState(() => _isCheckingOut = true);
    try {
      final cashierUrl = await widget.shopManager.checkoutOrder(
        tradeNo: widget.tradeNo,
        methodId: _selectedMethodId!,
      );

      if (cashierUrl.startsWith('http://') ||
          cashierUrl.startsWith('https://') ||
          cashierUrl.startsWith('alipays://') ||
          cashierUrl.startsWith('weixin://')) {
        final uri = Uri.parse(cashierUrl);
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!launched && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('無法開啟支付連結，請手動前往: $cashierUrl')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('支付回應: $cashierUrl')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${I18nService.instance.t('order_failed_prefix')}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCheckingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(
          I18nService.instance.t('shop_payment_title'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.cyanAccent),
            onPressed: _loadOrderData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.cyanAccent))
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 48, color: Colors.redAccent),
                      const SizedBox(height: 12),
                      Text(_errorMessage!, style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadOrderData,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.cyanAccent,
                          foregroundColor: Colors.black,
                        ),
                        child: Text(I18nService.instance.t('retry')),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  children: [
                    // 1. 藍色高亮訂單資訊卡
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF2563EB).withOpacity(0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            I18nService.instance.t('order_details'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                I18nService.instance.t('order_no'),
                                style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13),
                              ),
                              Text(
                                _order?.tradeNo ?? widget.tradeNo,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontFamily: 'Segoe UI',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                I18nService.instance.t('order_original_price'),
                                style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13),
                              ),
                              Text(
                                _order?.formattedAmount ?? '¥0.00',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                I18nService.instance.t('order_status'),
                                style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _order?.statusText ?? I18nService.instance.t('order_pending'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // 2. 選擇支付方式標題
                    Text(
                      I18nService.instance.t('order_select_pay_method'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 3. 支付方式清單
                    ..._paymentMethods.map((method) {
                      final isSelected = _selectedMethodId == method.id;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: InkWell(
                          onTap: () {
                            setState(() => _selectedMethodId = method.id);
                          },
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: AppTheme.darkCard,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSelected ? AppTheme.cyanAccent : Colors.white.withOpacity(0.08),
                                width: isSelected ? 1.5 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                _buildPaymentIcon(method),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    method.name,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(Icons.check_circle_rounded, color: AppTheme.cyanAccent, size: 20)
                                else
                                  Icon(Icons.radio_button_unchecked, color: Colors.white.withOpacity(0.3), size: 20),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 24),

                    // 4. 立即支付按鈕
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.cyanAccent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      onPressed: _isCheckingOut ? null : _handleCheckout,
                      child: _isCheckingOut
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                            )
                          : Text(
                              '${I18nService.instance.t('order_pay_now')} ${_order?.formattedAmount ?? ""}',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                    ),
                    if (_order?.isPending == true) ...[
                      const SizedBox(height: 10),
                      Center(
                        child: TextButton(
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: AppTheme.darkCard,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                title: Text(I18nService.instance.t('order_cancel_confirm'), style: const TextStyle(color: Colors.white)),
                                content: Text(I18nService.instance.t('order_cancel_desc'), style: TextStyle(color: Colors.white.withOpacity(0.7))),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: Text(I18nService.instance.t('cancel'), style: TextStyle(color: Colors.white.withOpacity(0.6))),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: Text(I18nService.instance.t('confirm'), style: const TextStyle(color: Colors.redAccent)),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true && mounted) {
                              await widget.shopManager.cancelOrder(widget.tradeNo);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(I18nService.instance.t('order_canceled'))),
                                );
                                Navigator.pop(context);
                              }
                            }
                          },
                          child: Text(I18nService.instance.t('order_cancel'), style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),

                    // 5. 支付說明卡片
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.darkCard,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withOpacity(0.06)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline_rounded, size: 16, color: Colors.white.withOpacity(0.6)),
                              const SizedBox(width: 6),
                              Text(
                                I18nService.instance.t('order_pay_notes'),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            I18nService.instance.t('order_note_1'),
                            style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.6), height: 1.5),
                          ),
                          Text(
                            I18nService.instance.t('order_note_2'),
                            style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.6), height: 1.5),
                          ),
                          Text(
                            I18nService.instance.t('order_note_3'),
                            style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.6), height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildPaymentIcon(PaymentMethodModel method) {
    final nameLower = method.name.toLowerCase();
    if (nameLower.contains('alipay') || nameLower.contains('支')) {
      return Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: const Color(0xFF1677FF).withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.payment_rounded, color: Color(0xFF1677FF), size: 20),
      );
    } else if (nameLower.contains('wechat') || nameLower.contains('微信')) {
      return Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: const Color(0xFF07C160).withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.chat_bubble_rounded, color: Color(0xFF07C160), size: 20),
      );
    } else if (nameLower.contains('usdt') || nameLower.contains('crypto') || nameLower.contains('幣')) {
      return Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: const Color(0xFF26A17B).withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.currency_bitcoin_rounded, color: Color(0xFF26A17B), size: 20),
      );
    }
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppTheme.cyanAccent.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.account_balance_wallet_rounded, color: AppTheme.cyanAccent, size: 20),
    );
  }
}
