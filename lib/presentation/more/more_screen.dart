// lib/presentation/more/more_screen.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../business/auth/auth_manager.dart';
import '../../business/subscription/subscription_engine.dart';
import '../../core/constants/app_constants.dart';
import '../../core/i18n/i18n_service.dart';
import '../../core/utils/error_sanitizer.dart';
import '../../core/theme/app_theme.dart';
import '../../infrastructure/config/app_config_service.dart';
import '../../infrastructure/core_daemon/core_daemon.dart';
import '../../infrastructure/core_daemon/windows_proxy_service.dart';
import '../../infrastructure/updater/in_app_updater.dart';
import '../dashboard/widgets/customer_service_modal.dart';
import '../dashboard/widgets/node_selector_modal.dart';
import '../widgets/update_dialog.dart';
import 'widgets/diagnostics_modal.dart';

/// 「更多」功能與設定頁面 (MoreScreen)
class MoreScreen extends StatefulWidget {
  final CoreDaemon coreDaemon;
  final SubscriptionEngine subscriptionEngine;
  final AppConfigService configService;
  final AuthManager? authManager;

  const MoreScreen({
    super.key,
    required this.coreDaemon,
    required this.subscriptionEngine,
    required this.configService,
    this.authManager,
  });

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  late String _selectedMode;
  bool _isCheckingUpdate = false;
  bool _isAutoStart = false;
  bool _autoConnectOnSelect = false;

  @override
  void initState() {
    super.initState();
    _selectedMode = widget.subscriptionEngine.routingMode;
    _loadSettings();
    if (!kIsWeb && (Platform.isMacOS || Platform.isWindows)) {
      _loadWindowsSettings();
    }
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final autoConnect = prefs.getBool(AppConstants.storageAutoConnectOnNodeSelect) ?? false;
      if (mounted) {
        setState(() => _autoConnectOnSelect = autoConnect);
      }
    } catch (_) {}
  }

  Future<void> _loadWindowsSettings() async {
    final auto = await WindowsProxyService.instance.isAutoStartEnabled();
    if (mounted) {
      setState(() {
        _isAutoStart = auto;
      });
    }
  }

  String _modeLabel(String key) {
    final i18n = I18nService.instance;
    switch (key) {
      case 'global':
        return i18n.t('more_mode_global');
      case 'direct':
        return i18n.t('more_mode_direct');
      default:
        return i18n.t('more_mode_rule');
    }
  }

  Future<void> _checkUpdate() async {
    setState(() => _isCheckingUpdate = true);
    try {
      final updater = InAppUpdater();
      final remoteConfig = widget.configService.activeConfig;
      final updateInfo = await updater.checkForUpdates(remoteConfig: remoteConfig);
      if (!mounted) return;
      if (updateInfo.hasUpdate) {
        await UpdateDialog.show(context, updateInfo: updateInfo, updater: updater);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${I18nService.instance.t('more_is_latest')} (${AppConstants.versionTag})')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${I18nService.instance.t('check_update_failed')}: ${ErrorSanitizer.sanitize(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCheckingUpdate = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: I18nService.instance,
      builder: (context, _) {
        final i18n = I18nService.instance;
        final isDesktop = MediaQuery.of(context).size.width > 800;

        return Scaffold(
          backgroundColor: AppTheme.darkBackground,
          appBar: AppBar(
            title: Text(
              i18n.t('more_title'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: Colors.white),
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: false,
            actions: [
              if (!isDesktop)
                IconButton(
                  icon: const Icon(Icons.translate_rounded, color: AppTheme.primaryCyan),
                  onPressed: () => _showLanguageModal(context),
                ),
            ],
          ),
          body: isDesktop ? _buildDesktopLayout(i18n) : _buildMobileLayout(i18n),
        );
      },
    );
  }

  /// 桌面端：頂部橫排分流切換 + 下方 3 欄等寬並排大卡片 (Expanded x 3，一頁全覽零下拉)
  Widget _buildDesktopLayout(I18nService i18n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        children: [
          // 頂部橫排分流模式快速切換條
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.darkBorder),
            ),
            child: Row(
              children: [
                const Icon(Icons.alt_route_rounded, color: AppTheme.primaryCyan, size: 20),
                const SizedBox(width: 10),
                Text(
                  i18n.t('more_routing_mode'),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(width: 16),
                _buildModeChip('rule', Icons.rule_rounded),
                const SizedBox(width: 8),
                _buildModeChip('global', Icons.public_rounded),
                const SizedBox(width: 8),
                _buildModeChip('direct', Icons.arrow_outward_rounded),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 下方 3 欄並排大卡片
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. 網路診斷與延遲探測 (左欄)
                Expanded(
                  child: _buildColumnSection(
                    title: i18n.t('more_diagnostics'),
                    icon: Icons.hub_rounded,
                    children: [
                      _buildActionRow(
                        icon: Icons.list_alt_rounded,
                        title: i18n.t('select_node'),
                        subtitle: i18n.t('node_selector_title'),
                        onTap: () {
                          NodeSelectorModal.show(context, subscriptionEngine: widget.subscriptionEngine);
                        },
                      ),
                      const Divider(color: Colors.white10, height: 1),
                      _buildActionRow(
                        icon: Icons.bolt_rounded,
                        title: i18n.t('auto_connect_on_node_select'),
                        subtitle: i18n.t('auto_connect_on_node_select_desc'),
                        trailing: Switch(
                          value: _autoConnectOnSelect,
                          activeColor: AppTheme.primaryCyan,
                          onChanged: (val) async {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setBool(AppConstants.storageAutoConnectOnNodeSelect, val);
                            if (mounted) {
                              setState(() => _autoConnectOnSelect = val);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    val ? i18n.t('auto_connect_enabled_snack') : i18n.t('auto_connect_disabled_snack'),
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                        onTap: () {},
                      ),
                      const Divider(color: Colors.white10, height: 1),
                      _buildActionRow(
                        icon: Icons.speed_rounded,
                        title: i18n.t('speed_test'),
                        subtitle: i18n.t('speed_test_done'),
                        onTap: () async {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(i18n.t('speed_test'))),
                          );
                          await widget.subscriptionEngine.pingAllNodes();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(i18n.t('speed_test_done'))),
                            );
                          }
                        },
                      ),
                      const Divider(color: Colors.white10, height: 1),
                      _buildActionRow(
                        icon: Icons.network_check_rounded,
                        title: i18n.t('more_diagnostics'),
                        subtitle: i18n.t('diag_subtitle_summary'),
                        onTap: () {
                          DiagnosticsModal.show(
                            context,
                            coreDaemon: widget.coreDaemon,
                            configService: widget.configService,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),

                // 2. 系統與關於 (中欄，整合更新、核心、DoH、Windows設置)
                Expanded(
                  child: _buildColumnSection(
                    title: i18n.t('more_system_about'),
                    icon: Icons.info_outline_rounded,
                    children: [
                      _buildActionRow(
                        icon: Icons.system_update_rounded,
                        title: i18n.t('more_check_update'),
                        subtitle: _isCheckingUpdate ? i18n.t('status_connecting') : '${i18n.t("more_current_version")}: ${AppConstants.fullVersionDisplay}',
                        trailing: _isCheckingUpdate
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.chevron_right_rounded, color: Colors.white38),
                        onTap: _isCheckingUpdate ? null : _checkUpdate,
                      ),
                      const Divider(color: Colors.white10, height: 1),
                      _buildActionRow(
                        icon: Icons.terminal_rounded,
                        title: i18n.t('more_core_daemon'),
                        subtitle: widget.coreDaemon.state.isConnected ? i18n.t('status_connected') : i18n.t('status_disconnected'),
                        trailing: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.coreDaemon.state.isConnected ? AppTheme.successEmerald : Colors.white38,
                          ),
                        ),
                        onTap: () {},
                      ),
                      const Divider(color: Colors.white10, height: 1),
                      _buildActionRow(
                        icon: Icons.security_rounded,
                        title: i18n.t('more_doh_protection'),
                        subtitle: i18n.t('doh_multi_tier_active'),
                        trailing: const Icon(Icons.check_circle_rounded, color: AppTheme.successEmerald, size: 16),
                        onTap: () {},
                      ),
                      if (!kIsWeb && (Platform.isMacOS || Platform.isWindows)) ...[
                        const Divider(color: Colors.white10, height: 1),
                        _buildActionRow(
                          icon: Icons.power_settings_new_rounded,
                          title: i18n.t('more_auto_start'),
                          subtitle: _isAutoStart ? i18n.t('auto_start_enabled') : i18n.t('auto_start_disabled'),
                          trailing: Switch(
                            value: _isAutoStart,
                            activeColor: AppTheme.primaryCyan,
                            onChanged: (val) async {
                              final ok = await WindowsProxyService.instance.setAutoStart(val);
                              if (!mounted) return;
                              if (ok) {
                                setState(() => _isAutoStart = val);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(val ? i18n.t('auto_start_snack_on') : i18n.t('auto_start_snack_off'))),
                                );
                              }
                            },
                          ),
                          onTap: () {},
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 16),

                // 3. 客戶服務與社群 (右欄)
                Expanded(
                  child: _buildColumnSection(
                    title: i18n.t('more_customer_community'),
                    icon: Icons.support_agent_rounded,
                    children: [
                      _buildActionRow(
                        icon: Icons.headset_mic_rounded,
                        title: i18n.t('online_service'),
                        subtitle: i18n.t('live_support_desc'),
                        onTap: () {
                          final cfg = widget.configService.activeConfig;
                          final u = widget.authManager?.state.user;
                          CustomerServiceModal.show(
                            context,
                            crispId: cfg.crispId,
                            user: u,
                            authManager: widget.authManager,
                          );
                        },
                      ),
                      const Divider(color: Colors.white10, height: 1),
                      _buildActionRow(
                        icon: Icons.smart_toy_rounded,
                        title: i18n.t('more_tg_bot'),
                        subtitle: '@TelegramBot',
                        onTap: () => _openUrl(AppConstants.telegramBotUrl),
                      ),
                      const Divider(color: Colors.white10, height: 1),
                      _buildActionRow(
                        icon: Icons.send_rounded,
                        title: i18n.t('more_tg_group'),
                        subtitle: '@TelegramGroup',
                        onTap: () => _openUrl(AppConstants.telegramGroupUrl),
                      ),
                      const Divider(color: Colors.white10, height: 1),
                      _buildActionRow(
                        icon: Icons.language_rounded,
                        title: i18n.t('profile_website'),
                        subtitle: i18n.t('official_portal'),
                        onTap: () {
                          final portal = widget.configService.activeConfig.websiteUrl ?? AppConstants.officialWebsiteUrl;
                          _openUrl(portal);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 手機端直式滾動備用
  Widget _buildMobileLayout(I18nService i18n) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.darkCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.darkBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.alt_route_rounded, color: AppTheme.primaryCyan, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    i18n.t('more_routing_mode'),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildModeChip('rule', Icons.rule_rounded),
                  _buildModeChip('global', Icons.public_rounded),
                  _buildModeChip('direct', Icons.arrow_outward_rounded),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildCardSection(
          title: i18n.t('more_diagnostics'),
          icon: Icons.hub_rounded,
          children: [
            _buildActionRow(
              icon: Icons.list_alt_rounded,
              title: i18n.t('select_node'),
              subtitle: i18n.t('node_selector_title'),
              onTap: () => NodeSelectorModal.show(context, subscriptionEngine: widget.subscriptionEngine),
            ),
            const Divider(color: Colors.white10, height: 1),
            _buildActionRow(
              icon: Icons.speed_rounded,
              title: i18n.t('speed_test'),
              subtitle: i18n.t('speed_test_done'),
              onTap: () async {
                await widget.subscriptionEngine.pingAllNodes();
              },
            ),
            const Divider(color: Colors.white10, height: 1),
            _buildActionRow(
              icon: Icons.network_check_rounded,
              title: i18n.t('more_diagnostics'),
              subtitle: i18n.t('diag_subtitle_summary'),
              onTap: () => DiagnosticsModal.show(context, coreDaemon: widget.coreDaemon, configService: widget.configService),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _buildCardSection(
          title: i18n.t('more_system_about'),
          icon: Icons.info_outline_rounded,
          children: [
            _buildActionRow(
              icon: Icons.system_update_rounded,
              title: i18n.t('more_check_update'),
              subtitle: '${i18n.t("more_current_version")}: ${AppConstants.fullVersionDisplay}',
              onTap: _checkUpdate,
            ),
            const Divider(color: Colors.white10, height: 1),
            _buildActionRow(
              icon: Icons.terminal_rounded,
              title: i18n.t('more_core_daemon'),
              subtitle: widget.coreDaemon.state.isConnected ? i18n.t('status_connected') : i18n.t('status_disconnected'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _buildCardSection(
          title: i18n.t('more_customer_community'),
          icon: Icons.support_agent_rounded,
          children: [
            _buildActionRow(
              icon: Icons.headset_mic_rounded,
              title: i18n.t('online_service'),
              subtitle: i18n.t('live_support_desc'),
              onTap: () {
                final cfg = widget.configService.activeConfig;
                CustomerServiceModal.show(context, crispId: cfg.crispId, user: widget.authManager?.state.user, authManager: widget.authManager);
              },
            ),
            const Divider(color: Colors.white10, height: 1),
            _buildActionRow(
              icon: Icons.language_rounded,
              title: i18n.t('profile_website'),
              subtitle: i18n.t('official_portal'),
              onTap: () => _openUrl(widget.configService.activeConfig.websiteUrl ?? AppConstants.officialWebsiteUrl),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildColumnSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppTheme.primaryCyan),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Widget _buildModeChip(String modeKey, IconData icon) {
    final i18n = I18nService.instance;
    final isSelected = _selectedMode == modeKey;
    final label = _modeLabel(modeKey);
    return ChoiceChip(
      selected: isSelected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: isSelected ? Colors.black : Colors.white70),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: isSelected ? Colors.black : Colors.white, fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
      selectedColor: AppTheme.primaryCyan,
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: isSelected ? AppTheme.primaryCyan : AppTheme.darkBorder),
      ),
      onSelected: (val) async {
        if (val) {
          setState(() => _selectedMode = modeKey);
          await widget.subscriptionEngine.setRoutingMode(modeKey);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${i18n.t('more_routing_mode')}: $label')),
            );
          }
        }
      },
    );
  }

  Widget _buildCardSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Icon(icon, size: 16, color: Colors.white70),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildActionRow({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.darkSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.darkBorder),
          ),
          child: Icon(icon, color: AppTheme.primaryCyan, size: 18),
        ),
        title: Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Colors.white)),
        subtitle: subtitle != null ? Text(subtitle, style: TextStyle(fontSize: 11.5, color: Colors.white.withOpacity(0.5))) : null,
        trailing: trailing ?? const Icon(Icons.chevron_right_rounded, color: Colors.white38),
        onTap: onTap,
      ),
    );
  }

  /// 語言選擇彈窗：只保留乾淨的 4 國語言，拔除「跟隨系統」
  void _showLanguageModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return ListenableBuilder(
          listenable: I18nService.instance,
          builder: (context, _) {
            final i18n = I18nService.instance;
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 16),
                  Text(
                    i18n.t('profile_select_lang'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final lang in AppLanguage.values) ...[
                    Material(
                      color: Colors.transparent,
                      child: ListTile(
                        leading: Text(lang.flagEmoji, style: const TextStyle(fontSize: 20)),
                        title: Text(
                          lang.label,
                          style: TextStyle(
                            color: i18n.currentLanguage == lang ? AppTheme.primaryCyan : Colors.white,
                            fontWeight: i18n.currentLanguage == lang ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        trailing: i18n.currentLanguage == lang
                            ? const Icon(Icons.check_circle_rounded, color: AppTheme.primaryCyan)
                            : null,
                        onTap: () async {
                          await i18n.setLanguage(lang);
                          if (ctx.mounted) Navigator.of(ctx).pop();
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

