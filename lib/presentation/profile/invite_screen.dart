// lib/presentation/profile/invite_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../business/auth/auth_manager.dart';
import '../../core/constants/app_constants.dart';
import '../../core/i18n/i18n_service.dart';
import '../../core/network/dio_client.dart';
import '../../core/theme/app_theme.dart';
import '../../infrastructure/config/app_config_service.dart';

/// 邀請管理 (InviteScreen)
/// 統一深色科技風 (Dark Tech Material 3)，與全站主題完全一致
class InviteScreen extends StatefulWidget {
  final AuthManager authManager;
  final DioClient dioClient;
  final AppConfigService configService;

  const InviteScreen({
    super.key,
    required this.authManager,
    required this.dioClient,
    required this.configService,
  });

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  bool _isLoading = true;
  int _selectedTab = 0; // 0: 邀請碼列表, 1: 返傭記錄

  List<Map<String, dynamic>> _codes = [];
  List<dynamic> _stat = [0, 0, 0, 10, 0]; // [邀請人數, 累計佣金, 待確認佣金, 佣金比例, ...]

  @override
  void initState() {
    super.initState();
    _fetchInviteData();
  }

  Future<void> _fetchInviteData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final resp = await widget.dioClient.get('/api/v1/user/invite/fetch');
      if (resp.data is Map && resp.data['data'] is Map) {
        final data = resp.data['data'] as Map<String, dynamic>;
        setState(() {
          if (data['codes'] is List) {
            _codes = (data['codes'] as List).whereType<Map<String, dynamic>>().toList();
          }
          if (data['stat'] is List) {
            _stat = data['stat'] as List;
          }
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 創建新邀請碼 (對接 POST /api/v1/user/invite/save)
  Future<void> _createInviteCode() async {
    try {
      await widget.dioClient.post('/api/v1/user/invite/save');
      await _fetchInviteData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(I18nService.instance.t('affiliate_code_created'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${I18nService.instance.t('affiliate_create_failed')}: $e')),
        );
      }
    }
  }

  /// 佣金劃轉彈窗 (對接 POST /api/v1/user/invite/transfer)
  Future<void> _showTransferDialog() async {
    final controller = TextEditingController();
    final user = widget.authManager.state.user;
    final maxCommissionYuan = ((user?.commissionBalance ?? 0) / 100).toStringAsFixed(2);
    final i18n = I18nService.instance;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(i18n.t('affiliate_transfer_dialog_title'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${i18n.t('affiliate_current_comm')}: ¥$maxCommissionYuan', style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.6))),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                labelText: i18n.t('affiliate_transfer_amount'),
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                hintText: i18n.t('affiliate_transfer_hint'),
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                filled: true,
                fillColor: AppTheme.darkBackground,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.white.withOpacity(0.12))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.white.withOpacity(0.12))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.cyanAccent)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(i18n.t('cancel'), style: TextStyle(color: Colors.white.withOpacity(0.6))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.cyanAccent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final val = double.tryParse(controller.text.trim());
              if (val == null || val <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(i18n.t('affiliate_transfer_invalid'))));
                return;
              }
              final amountInCents = (val * 100).toInt();
              try {
                await widget.dioClient.post(
                  '/api/v1/user/invite/transfer',
                  data: {'transfer_amount': amountInCents},
                );
                if (ctx.mounted) Navigator.pop(ctx);
                await widget.authManager.fetchUserInfo();
                await _fetchInviteData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(i18n.t('affiliate_transfer_success'))));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${i18n.t('affiliate_transfer_failed')}: $e')));
                }
              }
            },
            child: Text(i18n.t('affiliate_btn_transfer'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// 顯示二維碼/複製資訊彈窗
  void _showQrDialog(String code) {
    final inviteLink = _getInviteLink(code);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('${I18nService.instance.t('affiliate_codes_tab')}: $code', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.darkBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: SelectableText(
                inviteLink,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppTheme.cyanAccent, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(I18nService.instance.t('cancel'), style: TextStyle(color: Colors.white.withOpacity(0.6))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.cyanAccent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: inviteLink));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(I18nService.instance.t('affiliate_copied'))));
            },
            child: Text(I18nService.instance.t('affiliate_copy_full_link'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _getInviteLink(String code) {
    final rawInvite = widget.configService.activeConfig.inviteLink;
    if (rawInvite != null && rawInvite.isNotEmpty) {
      if (rawInvite.contains('code=')) {
        return rawInvite.replaceAll(RegExp(r'code=.*'), 'code=$code');
      }
      return '$rawInvite$code';
    }
    return '${AppConstants.officialWebsiteUrl}/#/register?code=$code';
  }

  String _formatTimestamp(int timestamp) {
    if (timestamp <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-$month-$day $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.authManager.state.user;
    final balanceYuan = ((user?.balance ?? 0) / 100).toStringAsFixed(2);
    final commissionYuan = ((user?.commissionBalance ?? 0) / 100).toStringAsFixed(2);

    final inviteCount = _stat.isNotEmpty ? _stat[0].toString() : '0';
    final totalCommissionYuan = _stat.length > 1 ? ((_stat[1] as num) / 100).toStringAsFixed(2) : '0.00';
    final pendingCommissionYuan = _stat.length > 2 ? ((_stat[2] as num) / 100).toStringAsFixed(2) : '0.00';
    final commissionRate = _stat.length > 3 ? '${_stat[3]}%' : '10%';

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        title: Text(I18nService.instance.t('affiliate_title'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.cyanAccent),
            onPressed: () {
              widget.authManager.fetchUserInfo();
              _fetchInviteData();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.cyanAccent))
          : RefreshIndicator(
              onRefresh: () async {
                await widget.authManager.fetchUserInfo();
                await _fetchInviteData();
              },
              color: AppTheme.cyanAccent,
              backgroundColor: AppTheme.darkCard,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1 & 2. 賬戶信息與邀請統計卡片 (桌面端雙欄並排，一屏全覽零滾動)
                    if (MediaQuery.of(context).size.width > 700)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildAccountInfoCard(balanceYuan, commissionYuan)),
                          const SizedBox(width: 14),
                          Expanded(child: _buildInviteStatsCard(inviteCount, commissionRate, totalCommissionYuan, pendingCommissionYuan)),
                        ],
                      )
                    else ...[
                      _buildAccountInfoCard(balanceYuan, commissionYuan),
                      const SizedBox(height: 16),
                      _buildInviteStatsCard(inviteCount, commissionRate, totalCommissionYuan, pendingCommissionYuan),
                    ],
                    const SizedBox(height: 16),

                    // 3. Tab 切換列 (邀請碼列表 / 返傭記錄)
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _selectedTab = 0),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.code_rounded, size: 16, color: _selectedTab == 0 ? AppTheme.cyanAccent : Colors.white38),
                                    const SizedBox(width: 6),
                                    Text(I18nService.instance.t('affiliate_codes_tab'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _selectedTab == 0 ? AppTheme.cyanAccent : Colors.white38)),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Container(height: 2, color: _selectedTab == 0 ? AppTheme.cyanAccent : Colors.transparent),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _selectedTab = 1),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.article_outlined, size: 16, color: _selectedTab == 1 ? AppTheme.cyanAccent : Colors.white38),
                                    const SizedBox(width: 6),
                                    Text(I18nService.instance.t('affiliate_rebates_tab'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _selectedTab == 1 ? AppTheme.cyanAccent : Colors.white38)),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Container(height: 2, color: _selectedTab == 1 ? AppTheme.cyanAccent : Colors.transparent),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // 4. 邀請碼清單與創建按鈕
                    if (_selectedTab == 0) ...[
                      Row(
                        children: [
                          const Icon(Icons.link_rounded, size: 16, color: AppTheme.cyanAccent),
                          const SizedBox(width: 6),
                          Text('${I18nService.instance.t('affiliate_codes_tab')} (${_codes.length})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                          const Spacer(),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.cyanAccent,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                            ),
                            onPressed: _createInviteCode,
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: Text(I18nService.instance.t('affiliate_create_code'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_codes.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: AppTheme.darkCard,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.06)),
                          ),
                          child: Center(
                            child: Text(I18nService.instance.t('affiliate_empty_codes'), style: TextStyle(color: Colors.white.withOpacity(0.5))),
                          ),
                        )
                      else
                        ..._codes.map((item) {
                          final code = item['code']?.toString() ?? '';
                          final createdAt = item['created_at'] is int ? item['created_at'] as int : 0;
                          final dateStr = _formatTimestamp(createdAt);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppTheme.darkCard,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white.withOpacity(0.08)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.cyanAccent.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.link_rounded, size: 16, color: AppTheme.cyanAccent),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        code,
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(Icons.access_time_rounded, size: 12, color: Colors.white.withOpacity(0.4)),
                                          const SizedBox(width: 4),
                                          Text(dateStr, style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.5))),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.qr_code_rounded, size: 18, color: AppTheme.cyanAccent),
                                  onPressed: () => _showQrDialog(code),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.copy_rounded, size: 18, color: AppTheme.cyanAccent),
                                  onPressed: () {
                                    final link = _getInviteLink(code);
                                    Clipboard.setData(ClipboardData(text: link));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(I18nService.instance.t('affiliate_copied'))),
                                    );
                                  },
                                ),
                              ],
                            ),
                          );
                        }),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: AppTheme.darkCard,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.06)),
                        ),
                        child: Center(
                          child: Text(I18nService.instance.t('affiliate_empty_rebates'), style: TextStyle(color: Colors.white.withOpacity(0.5))),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildAccountInfoCard(String balanceYuan, String commissionYuan) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_rounded, size: 18, color: AppTheme.cyanAccent),
              const SizedBox(width: 8),
              Text(I18nService.instance.t('affiliate_account_info'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.cyanAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.cyanAccent.withOpacity(0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.account_balance_rounded, size: 13, color: AppTheme.cyanAccent),
                          const SizedBox(width: 4),
                          Text(I18nService.instance.t('affiliate_balance'), style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.7))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('¥$balanceYuan', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.monetization_on_rounded, size: 13, color: Color(0xFF60A5FA)),
                          const SizedBox(width: 4),
                          Text(I18nService.instance.t('affiliate_commission'), style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.7))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('¥$commissionYuan', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.06),
                    side: BorderSide(color: Colors.white.withOpacity(0.1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: _showTransferDialog,
                  icon: const Icon(Icons.swap_horiz_rounded, size: 16, color: AppTheme.cyanAccent),
                  label: Text(I18nService.instance.t('affiliate_btn_transfer'), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.06),
                    side: BorderSide(color: Colors.white.withOpacity(0.1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(I18nService.instance.t('affiliate_withdraw_tip'))),
                    );
                  },
                  icon: const Icon(Icons.account_balance_rounded, size: 16, color: Color(0xFF60A5FA)),
                  label: Text(I18nService.instance.t('affiliate_btn_withdraw'), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInviteStatsCard(String inviteCount, String commissionRate, String totalCommissionYuan, String pendingCommissionYuan) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart_rounded, size: 18, color: AppTheme.cyanAccent),
              const SizedBox(width: 8),
              Text(I18nService.instance.t('affiliate_stats'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.group_rounded, size: 13, color: AppTheme.cyanAccent),
                          const SizedBox(width: 4),
                          Text(I18nService.instance.t('affiliate_stat_invited'), style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.6))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(inviteCount, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.percent_rounded, size: 13, color: AppTheme.cyanAccent),
                          const SizedBox(width: 4),
                          Text(I18nService.instance.t('affiliate_stat_rate'), style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.6))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(commissionRate, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.account_balance_wallet_rounded, size: 13, color: AppTheme.purpleAccent),
                          const SizedBox(width: 4),
                          Text(I18nService.instance.t('affiliate_stat_total'), style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.6))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('¥$totalCommissionYuan', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.purpleAccent)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.receipt_rounded, size: 13, color: Colors.pinkAccent),
                          const SizedBox(width: 4),
                          Text(I18nService.instance.t('affiliate_stat_pending'), style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.6))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('¥$pendingCommissionYuan', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.pinkAccent)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
