// lib/presentation/dashboard/widgets/connection_button.dart

import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/i18n/i18n_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../infrastructure/core_daemon/core_state.dart';
import '../../../infrastructure/core_daemon/traffic_stats.dart';

/// 一鍵連線大按鈕 (ConnectionButton)
/// 具備呼吸光暈與波紋特效，支援即時上下行流量數據展示
class ConnectionButton extends StatefulWidget {
  final CoreState coreState;
  final TrafficStats trafficStats;
  final bool isAccountValid;
  final VoidCallback onTap;
  final bool enableAnimations;

  const ConnectionButton({
    super.key,
    required this.coreState,
    required this.trafficStats,
    required this.isAccountValid,
    required this.onTap,
    this.enableAnimations = true,
  });

  @override
  State<ConnectionButton> createState() => _ConnectionButtonState();
}

class _ConnectionButtonState extends State<ConnectionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _glowAnimation;

  bool get _isTestEnv {
    if (Platform.environment['FLUTTER_TEST'] == 'true') return true;
    final binding = WidgetsBinding.instance.runtimeType.toString();
    return binding.contains('Test');
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    if (widget.enableAnimations && !_isTestEnv) {
      _pulseController.repeat(reverse: true);
    }

    _glowAnimation = Tween<double>(begin: 8.0, end: 24.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = widget.coreState.isConnected;
    final isConnecting = widget.coreState.isConnecting;

    // 依據連線狀態定義主題色彩
    final activeColor = isConnected
        ? AppTheme.successEmerald
        : isConnecting
            ? AppTheme.warningAmber
            : AppTheme.primaryCyan;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 呼吸光暈外層與圓形按鈕
        AnimatedBuilder(
          animation: _glowAnimation,
          builder: (context, child) {
            return GestureDetector(
              onTap: widget.isAccountValid ? widget.onTap : null,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.darkCard,
                  border: Border.all(
                    color: isConnected ? AppTheme.successEmerald : AppTheme.darkBorder,
                    width: isConnected ? 2.5 : 1.5,
                  ),
                  boxShadow: isConnected
                      ? [
                          BoxShadow(
                            color: activeColor.withOpacity(0.35),
                            blurRadius: _glowAnimation.value,
                            spreadRadius: 4,
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ],
                ),
                child: Center(
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: isConnected
                            ? [
                                AppTheme.successEmerald,
                                const Color(0xFF059669),
                              ]
                            : isConnecting
                                ? [
                                    AppTheme.warningAmber,
                                    const Color(0xFFD97706),
                                  ]
                                : [
                                    AppTheme.darkSurface,
                                    AppTheme.darkCard,
                                  ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Center(
                      child: isConnecting
                          ? const SizedBox(
                              width: 38,
                              height: 38,
                              child: CircularProgressIndicator(
                                strokeWidth: 3.5,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              Icons.power_settings_new_rounded,
                              size: 44,
                              color: isConnected ? Colors.black : Colors.white,
                            ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),

        // 狀態文字提示
        Text(
          isConnected
              ? I18nService.instance.t('protected_vpn')
              : isConnecting
                  ? I18nService.instance.t('status_connecting')
                  : I18nService.instance.t('status_disconnected'),
          style: TextStyle(
            color: isConnected ? AppTheme.successEmerald : Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 10),

        // 即時上下行流量顯示 (連線中展示)
        if (isConnected) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.darkSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.darkBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.arrow_upward_rounded, size: 14, color: AppTheme.primaryCyan),
                const SizedBox(width: 4),
                Text(
                  widget.trafficStats.upSpeedFormatted,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                const SizedBox(width: 14),
                const Icon(Icons.arrow_downward_rounded, size: 14, color: AppTheme.successEmerald),
                const SizedBox(width: 4),
                Text(
                  widget.trafficStats.downSpeedFormatted,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
        ] else ...[
          Text(
            widget.isAccountValid
                ? I18nService.instance.t('btn_traffic_encrypted')
                : I18nService.instance.t('btn_account_invalid'),
            style: TextStyle(
              color: widget.isAccountValid
                  ? Colors.white.withOpacity(0.4)
                  : AppTheme.dangerRose,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}
