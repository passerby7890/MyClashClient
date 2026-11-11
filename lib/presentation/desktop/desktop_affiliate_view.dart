// lib/presentation/desktop/desktop_affiliate_view.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../business/auth/auth_manager.dart';
import '../../core/constants/app_constants.dart';
import '../../core/i18n/i18n_service.dart';
import '../../core/network/dio_client.dart';
import '../../infrastructure/config/app_config_service.dart';
import 'desktop_theme_tokens.dart';

/// 專職邀請返利看板 (DesktopAffiliateView)
/// 上排雙卡 (帳戶與傭金資訊 + 邀請統計數據) + 下排邀請碼清單與返傭記錄
class DesktopAffiliateView extends StatefulWidget {
  final AuthManager authManager;
  final DioClient dioClient;
  final AppConfigService configService;

  const DesktopAffiliateView({
    super.key,
    required this.authManager,
    required this.dioClient,
    required this.configService,
  });

  @override
  State<DesktopAffiliateView> createState() => _DesktopAffiliateViewState();
}

class _DesktopAffiliateViewState extends State<DesktopAffiliateView> {
  bool _isLoading = true;
  int _selectedTab = 0; // 0: 邀請碼列表, 1: 返傭記錄

  List<Map<String, dynamic>> _codes = [];
  List<dynamic> _stat = [0, 0, 0, 10, 0];

  @override
  void initState() {
    super.initState();
    _fetchInviteData();
  }

  Future<void> _fetchInviteData() async {
    setState(() => _isLoading = true);
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
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createInviteCode() async {
    final i18n = I18nService.instance;
    try {
      await widget.dioClient.post('/api/v1/user/invite/save');
      await _fetchInviteData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(i18n.t('affiliate_code_created'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${i18n.t('affiliate_create_failed')}: $e')),
        );
      }
    }
  }

  Future<void> _showTransferDialog() async {
    final controller = TextEditingController();
    final user = widget.authManager.state.user;
    final maxCommissionYuan = ((user?.commissionBalance ?? 0) / 100).toStringAsFixed(2);
    final i18n = I18nService.instance;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DesktopThemeTokens.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesktopThemeTokens.cardRadius),
          side: const BorderSide(color: DesktopThemeTokens.borderColor),
        ),
        title: Text(i18n.t('affiliate_transfer_dialog_title'), style: DesktopThemeTokens.titleStyle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${i18n.t('affiliate_current_comm')}: ¥$maxCommissionYuan', style: DesktopThemeTokens.subtitleStyle),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                labelText: i18n.t('affiliate_transfer_amount'),
                labelStyle: const TextStyle(color: DesktopThemeTokens.textMuted),
                hintText: i18n.t('affiliate_transfer_hint'),
                hintStyle: const TextStyle(color: DesktopThemeTokens.textDim),
                filled: true,
                fillColor: DesktopThemeTokens.cardInnerBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DesktopThemeTokens.borderColor)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(i18n.t('cancel'), style: const TextStyle(color: DesktopThemeTokens.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: DesktopThemeTokens.neonCyan,
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
                await widget.dioClient.post('/api/v1/user/invite/transfer', data: {'transfer_amount': amountInCents});
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

  String _getInviteLink(String code) {
    final rawInvite = widget.configService.activeConfig.inviteLink?.trim();
    if (rawInvite != null && rawInvite.isNotEmpty) {
      if (rawInvite.contains('{code}')) return rawInvite.replaceAll('{code}', code);
      if (rawInvite.contains('code=')) {
        return rawInvite.replaceAll(RegExp(r'code=.*'), 'code=$code');
      }
      final base = rawInvite.endsWith('/') ? rawInvite.substring(0, rawInvite.length - 1) : rawInvite;
      return '$base/#/register?code=$code';
    }
    return '${AppConstants.officialWebsiteUrl}/#/register?code=$code';
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18nService.instance;
    final user = widget.authManager.state.user;

    final balanceYuan = ((user?.balance ?? 0) / 100).toStringAsFixed(2);
    final commissionYuan = ((user?.commissionBalance ?? 0) / 100).toStringAsFixed(2);
    final inviteCount = _stat.isNotEmpty ? _stat[0].toString() : '0';
    final totalCommissionYuan = _stat.length > 1 ? ((_stat[1] as num) / 100).toStringAsFixed(2) : '0.00';
    final pendingCommissionYuan = _stat.length > 2 ? ((_stat[2] as num) / 100).toStringAsFixed(2) : '0.00';
    final commissionRate = _stat.length > 3 ? '${_stat[3]}%' : '10%';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DesktopThemeTokens.spacing, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ══════════════════════════════════════════════
          // 上排雙卡：賬戶資訊 + 邀請統計
          // ══════════════════════════════════════════════
          Row(
            children: [
              Expanded(
                flex: 5,
                child: _buildAccountCard(balanceYuan, commissionYuan, i18n),
              ),
              const SizedBox(width: DesktopThemeTokens.spacing),
              Expanded(
                flex: 6,
                child: _buildStatsCard(inviteCount, commissionRate, totalCommissionYuan, pendingCommissionYuan, i18n),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ══════════════════════════════════════════════
          // 下排：分頁標籤與邀請碼表格
          // ══════════════════════════════════════════════
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: DesktopThemeTokens.cardBg,
                borderRadius: BorderRadius.circular(DesktopThemeTokens.cardRadius),
                border: Border.all(color: DesktopThemeTokens.borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _buildTabChip(0, '${i18n.t('affiliate_codes_tab')} (${_codes.length})'),
                      const SizedBox(width: 10),
                      _buildTabChip(1, i18n.t('affiliate_rebates_tab')),
                      const Spacer(),
                      if (_selectedTab == 0)
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: DesktopThemeTokens.neonCyan,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: _createInviteCode,
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: Text(i18n.t('affiliate_create_code'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator(color: DesktopThemeTokens.neonCyan))
                        : (_selectedTab == 0 ? _buildCodesList(i18n) : _buildRebatesList(i18n)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard(String balanceYuan, String commissionYuan, I18nService i18n) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DesktopThemeTokens.cardBg,
        borderRadius: BorderRadius.circular(DesktopThemeTokens.cardRadius),
        border: Border.all(color: DesktopThemeTokens.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_rounded, size: 18, color: DesktopThemeTokens.neonCyan),
              const SizedBox(width: 8),
              Text(i18n.t('affiliate_account_info'), style: DesktopThemeTokens.titleStyle),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: DesktopThemeTokens.neonCyan.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: DesktopThemeTokens.neonCyan.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(i18n.t('affiliate_balance'), style: DesktopThemeTokens.labelStyle),
                      const SizedBox(height: 4),
                      Text('¥$balanceYuan', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Segoe UI')),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: DesktopThemeTokens.neonBlue.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: DesktopThemeTokens.neonBlue.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(i18n.t('affiliate_commission'), style: DesktopThemeTokens.labelStyle),
                      const SizedBox(height: 4),
                      Text('¥$commissionYuan', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Segoe UI')),
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
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: DesktopThemeTokens.neonCyan,
                    side: const BorderSide(color: DesktopThemeTokens.borderColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onPressed: _showTransferDialog,
                  child: Text(i18n.t('affiliate_btn_transfer'), style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: DesktopThemeTokens.textMuted,
                    side: const BorderSide(color: DesktopThemeTokens.borderColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(i18n.t('affiliate_withdraw_tip'))),
                    );
                  },
                  child: Text(i18n.t('affiliate_btn_withdraw')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard(
    String inviteCount,
    String commissionRate,
    String totalCommissionYuan,
    String pendingCommissionYuan,
    I18nService i18n,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DesktopThemeTokens.cardBg,
        borderRadius: BorderRadius.circular(DesktopThemeTokens.cardRadius),
        border: Border.all(color: DesktopThemeTokens.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart_rounded, size: 18, color: DesktopThemeTokens.neonCyan),
              const SizedBox(width: 8),
              Text(i18n.t('affiliate_stats'), style: DesktopThemeTokens.titleStyle),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildStatItem(i18n.t('affiliate_stat_invited'), inviteCount, DesktopThemeTokens.neonCyan)),
              const SizedBox(width: 8),
              Expanded(child: _buildStatItem(i18n.t('affiliate_stat_rate'), commissionRate, DesktopThemeTokens.neonBlue)),
              const SizedBox(width: 8),
              Expanded(child: _buildStatItem(i18n.t('affiliate_stat_total'), '¥$totalCommissionYuan', DesktopThemeTokens.purpleAccent)),
              const SizedBox(width: 8),
              Expanded(child: _buildStatItem(i18n.t('affiliate_stat_pending'), '¥$pendingCommissionYuan', DesktopThemeTokens.amberWarn)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: DesktopThemeTokens.cardInnerBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DesktopThemeTokens.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: DesktopThemeTokens.labelStyle),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
              fontFamily: 'Segoe UI',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabChip(int index, String label) {
    final isSelected = _selectedTab == index;
    return InkWell(
      onTap: () => setState(() => _selectedTab = index),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? DesktopThemeTokens.neonCyan.withOpacity(0.15) : DesktopThemeTokens.cardInnerBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? DesktopThemeTokens.neonCyan : DesktopThemeTokens.borderColor),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? DesktopThemeTokens.neonCyan : DesktopThemeTokens.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildCodesList(I18nService i18n) {
    if (_codes.isEmpty) {
      return Center(
        child: Text(i18n.t('affiliate_empty_codes'), style: const TextStyle(color: DesktopThemeTokens.textMuted)),
      );
    }

    return ListView.builder(
      itemCount: _codes.length,
      itemBuilder: (context, idx) {
        final item = _codes[idx];
        final code = item['code']?.toString() ?? '';
        final link = _getInviteLink(code);

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: DesktopThemeTokens.cardInnerBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: DesktopThemeTokens.borderColor),
          ),
          child: Row(
            children: [
              const Icon(Icons.link_rounded, size: 16, color: DesktopThemeTokens.neonCyan),
              const SizedBox(width: 10),
              Text(
                code,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Segoe UI'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  link,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: DesktopThemeTokens.textMuted),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 16, color: DesktopThemeTokens.neonCyan),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: link));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(i18n.t('affiliate_copied'))));
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRebatesList(I18nService i18n) {
    return Center(
      child: Text(i18n.t('affiliate_empty_rebates'), style: const TextStyle(color: DesktopThemeTokens.textMuted)),
    );
  }
}
