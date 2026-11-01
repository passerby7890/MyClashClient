// lib/presentation/shop/order_payment_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../business/auth/auth_manager.dart';
import '../../business/shop/order_model.dart';
import '../../business/shop/payment_method_model.dart';
import '../../business/shop/shop_manager.dart';
import '../../business/subscription/subscription_engine.dart';
import '../../core/theme/app_theme.dart';
import '../../core/i18n/i18n_service.dart';

/// 訂單支付頁面 (OrderPaymentScreen)
/// 統一深色科技風 (Dark Tech Material 3)，藍色高亮訂單卡、多渠道支付方式選擇與結帳
/// 具備：
/// 1. WidgetsBindingObserver 前台喚醒檢測 (用戶外部支付完成切回 App 即刻主動查詢)
/// 2. 背景定時輪詢 (Timer.periodic 每 2.5 秒自動輪詢訂單狀態)
/// 3. 支付成功自動提示、自動同步本地流量 (getUserInfo & refreshSubscription) 並自動回跳
/// 4. 訂單狀態防呆保護 (已完成狀態動態替換為返回按鈕，防重複扣款)
class OrderPaymentScreen extends StatefulWidget {
  final String tradeNo;
  final ShopManager shopManager;
  final AuthManager? authManager;
  final SubscriptionEngine? subscriptionEngine;

  const OrderPaymentScreen({
    super.key,
    required this.tradeNo,
    required this.shopManager,
    this.authManager,
    this.subscriptionEngine,
  });

  @override
  State<OrderPaymentScreen> createState() => _OrderPaymentScreenState();
}

class _OrderPaymentScreenState extends State<OrderPaymentScreen> with WidgetsBindingObserver {
  String _resolveStatusText(int? status, I18nService i18n) {
    if (status == null) return i18n.t('order_status_pending');
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
  bool _isCheckingOut = false;
  String? _errorMessage;

  OrderModel? _order;
  List<PaymentMethodModel> _paymentMethods = [];
  int? _selectedMethodId;

  // 輪詢與前台檢測計時器
  Timer? _pollingTimer;
  int _pollingCount = 0;
  static const int _maxPollingCount = 120; // 2.5s * 120 = 300 秒 (5 分鐘)
  bool _isCheckingStatus = false;
  bool _hasPopped = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadOrderData();
  }

  @override
  void dispose() {
    _stopPolling();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 監聽 App 生命週期：當用戶在外部支付寶/微信/瀏覽器完成付款返回客戶端時，立即 0 延遲觸發檢查
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPaymentStatus(silent: false);
    }
  }

  /// 啟動背景定時輪詢
  void _startPolling() {
    _stopPolling();
    _pollingCount = 0;
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 2500), (timer) {
      _pollingCount++;
      if (_pollingCount >= _maxPollingCount) {
        _stopPolling();
        return;
      }
      _checkPaymentStatus(silent: true);
    });
  }

  /// 停止輪詢
  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  /// 載入訂單與支付方式
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

  /// 檢查訂單最新狀態 (供輪詢與前台喚醒使用)
  Future<void> _checkPaymentStatus({bool silent = true}) async {
    if (_isCheckingStatus || !mounted || _hasPopped) return;
    _isCheckingStatus = true;

    try {
      final status = await widget.shopManager.checkOrderStatus(widget.tradeNo);
      if (!mounted) return;

      if (status == 3 || status == 1) {
        // 支付成功 (3: 已完成, 1: 開通中)
        _stopPolling();
        final freshOrder = await widget.shopManager.getOrderDetail(widget.tradeNo);
        if (mounted) {
          setState(() {
            _order = freshOrder;
          });
        }
        await _handlePaymentSuccess(status, showModal: true);
      } else if (status == 2) {
        // 已取消
        _stopPolling();
        final freshOrder = await widget.shopManager.getOrderDetail(widget.tradeNo);
        if (mounted) {
          setState(() {
            _order = freshOrder;
          });
        }
      } else {
        // 仍為 0 (待支付)
        if (!silent && mounted) {
          final freshOrder = await widget.shopManager.getOrderDetail(widget.tradeNo);
          if (mounted) {
            setState(() {
              _order = freshOrder;
            });
          }
        }
      }
    } catch (_) {
      // 靜默處理網路抖動，不打擾用戶
    } finally {
      _isCheckingStatus = false;
    }
  }

  /// 處理支付成功回調：刷新本地用戶資料、刷新訂閱、彈窗並自動關閉返回上一頁
  Future<void> _handlePaymentSuccess(int status, {bool showModal = true}) async {
    if (_hasPopped || !mounted) return;

    // 1. 背景刷新本地用戶資料與節點訂閱
    try {
      await widget.authManager?.fetchUserInfo();
      await widget.subscriptionEngine?.performManualSync();
    } catch (_) {}

    if (!mounted) return;

    if (showModal) {
      // 彈出支付成功反饋彈窗
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.darkCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 28),
              const SizedBox(width: 10),
              Text(
                I18nService.instance.t('order_paid_success_title'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                status == 1
                    ? I18nService.instance.t('order_paid_success_opening_msg')
                    : I18nService.instance.t('order_paid_success_completed_msg'),
                style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(color: AppTheme.cyanAccent, strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    I18nService.instance.t('order_paid_success_redirecting'),
                    style: const TextStyle(color: AppTheme.cyanAccent, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      // 等待 1.8 秒讓用戶看清成功反饋
      await Future.delayed(const Duration(milliseconds: 1800));
    }

    if (mounted && !_hasPopped) {
      _hasPopped = true;
      if (showModal) {
        Navigator.of(context, rootNavigator: true).pop(); // 關閉 Dialog
      }
      Navigator.of(context).pop(true); // 返回上一頁並回傳 true (通知刷新)
    }
  }

  /// 處理結帳並調起外部收銀台 / 網頁
  Future<void> _handleCheckout() async {
    if (_order != null && (_order!.status == 3 || _order!.status == 1)) {
      _handlePaymentSuccess(_order!.status, showModal: false);
      return;
    }

    if (_selectedMethodId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(I18nService.instance.t('order_select_method_warning'))),
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
        if (launched) {
          // 成功喚起外部支付寶/微信/瀏覽器收銀台，啟動定時輪詢
          _startPolling();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(I18nService.instance.t('order_channel_invoked_tip')),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(I18nService.instance.t('order_open_url_failed', {'url': cashierUrl}))),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(I18nService.instance.t('order_checkout_failed', {'error': cashierUrl}))),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(I18nService.instance.t('order_checkout_failed', {'error': e.toString()}))),
        );
      }
    } finally {
      if (mounted) setState(() => _isCheckingOut = false);
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
        foregroundColor: Colors.white,
        title: Text(
          i18n.t('order_payment_title'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.cyanAccent),
            tooltip: i18n.t('shop_reload_tooltip'),
            onPressed: () => _checkPaymentStatus(silent: false),
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
                        child: Text(i18n.t('order_retry')),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  children: [
                    // 1. 藍色高亮訂單資訊卡 (帶動態狀態)
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _order?.status == 3
                              ? [const Color(0xFF065F46), const Color(0xFF059669)]
                              : [const Color(0xFF1E3A8A), const Color(0xFF2563EB)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: (_order?.status == 3 ? const Color(0xFF059669) : const Color(0xFF2563EB))
                                .withOpacity(0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                i18n.t('order_info_card'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (_pollingTimer != null)
                                Row(
                                  children: [
                                    const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 1.5),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      i18n.t('order_listening_status'),
                                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                i18n.t('order_trade_no'),
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
                                i18n.t('order_original_price'),
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
                                i18n.t('order_status'),
                                style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _resolveStatusText(_order?.status, i18n),
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

                    // 2. 選擇支付方式標題 (若已完成則折疊或提示)
                    if (_order?.status != 3) ...[
                      Text(
                        i18n.t('order_select_pay_method_label'),
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
                    ],

                    // 4. 動態動作按鈕 (防止重複支付，完成直接回跳)
                    _buildActionButton(),

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
                                title: Text(i18n.t('order_cancel_confirm_title'), style: const TextStyle(color: Colors.white)),
                                content: Text(i18n.t('order_cancel_confirm_desc'), style: TextStyle(color: Colors.white.withOpacity(0.7))),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: Text(i18n.t('order_cancel_return'), style: TextStyle(color: Colors.white.withOpacity(0.6))),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: Text(i18n.t('order_cancel_confirm_btn'), style: const TextStyle(color: Colors.redAccent)),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true && mounted) {
                              await widget.shopManager.cancelOrder(widget.tradeNo);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(i18n.t('order_canceled_toast'))),
                                );
                                Navigator.pop(context, true);
                              }
                            }
                          },
                          child: Text(i18n.t('order_cancel_this_order'), style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13)),
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
                                i18n.t('order_pay_note_title'),
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
                            i18n.t('order_pay_note_1'),
                            style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.6), height: 1.5),
                          ),
                          Text(
                            i18n.t('order_pay_note_2'),
                            style: const TextStyle(fontSize: 12, color: AppTheme.cyanAccent, height: 1.5),
                          ),
                          Text(
                            i18n.t('order_pay_note_3'),
                            style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.6), height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  /// 動態動作按鈕
  Widget _buildActionButton() {
    final i18n = I18nService.instance;
    // 1. 已完成狀態
    if (_order?.status == 3) {
      return FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF059669),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        icon: const Icon(Icons.check_circle_rounded, color: Colors.white),
        label: Text(
          i18n.t('order_paid_btn_completed'),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        onPressed: () {
          if (!_hasPopped) {
            _hasPopped = true;
            Navigator.of(context).pop(true);
          }
        },
      );
    }

    // 2. 開通中狀態
    if (_order?.status == 1) {
      return FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF1E3A8A),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        icon: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
        ),
        label: Text(
          i18n.t('order_paid_btn_opening'),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        onPressed: () => _checkPaymentStatus(silent: false),
      );
    }

    // 3. 已取消狀態
    if (_order?.status == 2) {
      return FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.grey.shade800,
          foregroundColor: Colors.white54,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: () => Navigator.of(context).pop(false),
        child: Text(i18n.t('order_paid_btn_canceled'), style: const TextStyle(fontSize: 15)),
      );
    }

    // 4. 待支付狀態 (預設)
    return FilledButton(
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
              i18n.t('order_pay_now_btn', {'amount': _order?.formattedAmount ?? ''}),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
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
