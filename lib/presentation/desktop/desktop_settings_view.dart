// lib/presentation/desktop/desktop_settings_view.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../business/auth/auth_manager.dart';
import '../../business/subscription/subscription_engine.dart';
import '../../core/constants/app_constants.dart';
import '../../core/i18n/i18n_service.dart';
import '../../infrastructure/config/app_config_service.dart';
import '../../infrastructure/core_daemon/core_daemon.dart';
import '../../infrastructure/core_daemon/windows_proxy_service.dart';
import '../../infrastructure/updater/in_app_updater.dart';
import '../dashboard/widgets/customer_service_modal.dart';
import '../dashboard/widgets/node_selector_modal.dart';
import '../more/widgets/diagnostics_modal.dart';
import '../widgets/update_dialog.dart';
import 'desktop_theme_tokens.dart';

/// 桌面專屬高級設置視圖 (DesktopSettingsView)
/// 1200x780 黃金解析度規格：上排分流模式切換 + 下排 左、中、右 3 欄等寬大卡片 (一屏全覽零下拉)
class DesktopSettingsView extends StatefulWidget {
  final CoreDaemon coreDaemon;
  final SubscriptionEngine subscriptionEngine;
  final AppConfigService configService;
  final AuthManager? authManager;

  const DesktopSettingsView({
    super.key,
    required this.coreDaemon,
    required this.subscriptionEngine,
    required this.configService,
    this.authManager,
  });

  @override
  State<DesktopSettingsView> createState() => _DesktopSettingsViewState();
}

class _DesktopSettingsViewState extends State<DesktopSettingsView> {
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
          SnackBar(
            content: Text('${I18nService.instance.t('more_is_latest')} (${AppConstants.versionTag})'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${I18nService.instance.t('check_update_failed')}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCheckingUpdate = false);
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: I18nService.instance,
      builder: (context, _) {
        final i18n = I18nService.instance;

        return Container(
          color: DesktopThemeTokens.bgCanvas,
          padding: const EdgeInsets.all(DesktopThemeTokens.spacing),
          child: Column(
            children: [
              // 頂部橫排分流模式快速切換條
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: DesktopThemeTokens.cardSurface,
                  borderRadius: BorderRadius.circular(DesktopThemeTokens.cardRadius),
                  border: Border.all(color: DesktopThemeTokens.borderMuted),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      const Icon(Icons.alt_route_rounded, color: DesktopThemeTokens.accentCyan, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        i18n.t('more_routing_mode'),
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(width: 16),
                      _buildModeChip('rule', Icons.rule_rounded, i18n.t('more_mode_rule')),
                      const SizedBox(width: 8),
                      _buildModeChip('global', Icons.public_rounded, i18n.t('more_mode_global')),
                      const SizedBox(width: 8),
                      _buildModeChip('direct', Icons.arrow_outward_rounded, i18n.t('more_mode_direct')),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: DesktopThemeTokens.spacing),

              // 下方 3 欄等寬並排大卡片
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. 網路診斷與延遲探測 (左欄)
                    Expanded(
                      child: _buildColumnCard(
                        title: i18n.t('more_diagnostics'),
                        icon: Icons.hub_rounded,
                        children: [
                          _buildActionTile(
                            icon: Icons.list_alt_rounded,
                            title: i18n.t('select_node'),
                            subtitle: i18n.t('node_selector_title'),
                            onTap: () {
                              NodeSelectorModal.show(context, subscriptionEngine: widget.subscriptionEngine);
                            },
                          ),
                          const Divider(color: Colors.white10, height: 1),
                          _buildActionTile(
                            icon: Icons.bolt_rounded,
                            title: i18n.t('auto_connect_on_node_select'),
                            subtitle: i18n.t('auto_connect_on_node_select_desc'),
                            trailing: Switch(
                              value: _autoConnectOnSelect,
                              activeColor: DesktopThemeTokens.accentCyan,
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
                          _buildActionTile(
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
                          _buildActionTile(
                            icon: Icons.network_check_rounded,
                            title: i18n.t('more_diagnostics'),
                            subtitle: 'DNS, TLS & Latency Ping',
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
                    const SizedBox(width: DesktopThemeTokens.spacing),

                    // 2. 系統與關於 (中欄)
                    Expanded(
                      child: _buildColumnCard(
                        title: i18n.t('more_system_about'),
                        icon: Icons.info_outline_rounded,
                        children: [
                          _buildActionTile(
                            icon: Icons.system_update_rounded,
                            title: i18n.t('more_check_update'),
                            subtitle: _isCheckingUpdate
                                ? i18n.t('status_connecting')
                                : '${i18n.t("more_current_version")}: ${AppConstants.fullVersionDisplay}',
                            trailing: _isCheckingUpdate
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.chevron_right_rounded, color: Colors.white38),
                            onTap: _isCheckingUpdate ? null : _checkUpdate,
                          ),
                          const Divider(color: Colors.white10, height: 1),
                          _buildActionTile(
                            icon: Icons.terminal_rounded,
                            title: i18n.t('more_core_daemon'),
                            subtitle: widget.coreDaemon.state.isConnected ? i18n.t('status_connected') : i18n.t('status_disconnected'),
                            trailing: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: widget.coreDaemon.state.isConnected ? DesktopThemeTokens.successColor : Colors.white38,
                              ),
                            ),
                            onTap: () {},
                          ),
                          const Divider(color: Colors.white10, height: 1),
                          _buildActionTile(
                            icon: Icons.security_rounded,
                            title: i18n.t('more_doh_protection'),
                            subtitle: 'Cloudflare / Google DoH',
                            trailing: const Icon(Icons.check_circle_rounded, color: DesktopThemeTokens.successColor, size: 16),
                            onTap: () {},
                          ),
                          if (!kIsWeb && (Platform.isMacOS || Platform.isWindows)) ...[
                            const Divider(color: Colors.white10, height: 1),
                            _buildActionTile(
                              icon: Icons.power_settings_new_rounded,
                              title: i18n.t('more_auto_start'),
                              subtitle: _isAutoStart ? i18n.t('auto_start_enabled') : i18n.t('auto_start_disabled'),
                              trailing: Switch(
                                value: _isAutoStart,
                                activeColor: DesktopThemeTokens.accentCyan,
                                onChanged: (val) async {
                                  final ok = await WindowsProxyService.instance.setAutoStart(val);
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
                    const SizedBox(width: DesktopThemeTokens.spacing),

                    // 3. 客戶服務與社群 (右欄)
                    Expanded(
                      child: _buildColumnCard(
                        title: i18n.t('more_customer_community'),
                        icon: Icons.support_agent_rounded,
                        children: [
                          _buildActionTile(
                            icon: Icons.headset_mic_rounded,
                            title: i18n.t('online_service'),
                            subtitle: '7x24 Live Support',
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
                          _buildActionTile(
                            icon: Icons.smart_toy_rounded,
                            title: i18n.t('more_tg_bot'),
                            subtitle: '@TelegramBot',
                            onTap: () => _openUrl(AppConstants.telegramBotUrl),
                          ),
                          const Divider(color: Colors.white10, height: 1),
                          _buildActionTile(
                            icon: Icons.send_rounded,
                            title: i18n.t('more_tg_group'),
                            subtitle: '@TelegramGroup',
                            onTap: () => _openUrl(AppConstants.telegramGroupUrl),
                          ),
                          const Divider(color: Colors.white10, height: 1),
                          _buildActionTile(
                            icon: Icons.language_rounded,
                            title: i18n.t('profile_website'),
                            subtitle: 'Official Portal',
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
      },
    );
  }

  Widget _buildModeChip(String mode, IconData icon, String label) {
    final isSelected = _selectedMode == mode;
    return InkWell(
      onTap: () async {
        setState(() => _selectedMode = mode);
        await widget.subscriptionEngine.setRoutingMode(mode);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? DesktopThemeTokens.accentCyan.withOpacity(0.18) : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? DesktopThemeTokens.accentCyan : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? DesktopThemeTokens.accentCyan : Colors.white60,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? DesktopThemeTokens.accentCyan : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColumnCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: DesktopThemeTokens.cardSurface,
        borderRadius: BorderRadius.circular(DesktopThemeTokens.cardRadius),
        border: Border.all(color: DesktopThemeTokens.borderMuted),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: DesktopThemeTokens.accentCyan.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, color: DesktopThemeTokens.accentCyan, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              physics: const NeverScrollableScrollPhysics(),
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        leading: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.white70, size: 17),
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.45)),
        ),
        trailing: trailing ?? const Icon(Icons.chevron_right_rounded, color: Colors.white30, size: 18),
        onTap: onTap,
      ),
    );
  }
}
