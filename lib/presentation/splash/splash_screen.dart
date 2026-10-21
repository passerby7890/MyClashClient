// lib/presentation/splash/splash_screen.dart

import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/i18n/i18n_service.dart';
import '../../infrastructure/config/app_config_service.dart';
import '../../infrastructure/updater/in_app_updater.dart';
import '../../business/auth/auth_manager.dart';
import '../auth/login_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../widgets/update_dialog.dart';

/// 啟動載入頁 (並行執行 DoH 配置、版本檢查與認證狀態)
class SplashScreen extends StatefulWidget {
  final AppConfigService configService;
  final AuthManager authManager;
  final InAppUpdater updater;

  const SplashScreen({
    super.key,
    required this.configService,
    required this.authManager,
    required this.updater,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  late String _statusText;
  bool _hasError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _statusText = I18nService.instance.t('splash_init_channel');
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutBack,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    );

    _animController.forward();
    _startBootSequence();
  }

  /// 執行啟動初始化序列
  Future<void> _startBootSequence() async {
    final i18n = I18nService.instance;
    setState(() {
      _hasError = false;
      _errorMessage = null;
      _statusText = i18n.t('splash_resolving_doh');
    });

    try {
      // 1. 初始化動態配置服務 (Cloudflare/Google DoH -> AES 解密)
      final remoteConfig = await widget.configService.initialize();

      if (!mounted) return;
      setState(() => _statusText = i18n.t('splash_checking_version'));

      // 2. 檢查版本更新 (測試模式安全保護)
      try {
        final updateInfo = await widget.updater.checkForUpdates(
          remoteConfig: remoteConfig,
        );
        if (updateInfo.hasUpdate && updateInfo.isForceUpdate && mounted) {
          await UpdateDialog.show(
            context,
            updateInfo: updateInfo,
            updater: widget.updater,
          );
          return;
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() => _statusText = i18n.t('splash_verifying_auth'));

      // 3. 檢查本地認證與 Token 有效性
      await widget.authManager.checkAuthStatus();

      // 給予動態動畫一個平滑收尾時間
      await Future.delayed(const Duration(milliseconds: 400));

      if (!mounted) return;

      // 4. 根據認證狀態路由
      if (widget.authManager.state.isAuthenticated) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => DashboardScreen(
              authManager: widget.authManager,
              configService: widget.configService,
            ),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
          ),
        );
      } else {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => LoginScreen(
              authManager: widget.authManager,
              configService: widget.configService,
            ),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
          _statusText = i18n.t('splash_init_failed');
        });
      }
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 品牌 Logo 與光暈特效
              ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [AppTheme.primaryCyan, AppTheme.primaryIndigo],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryCyan.withOpacity(0.35),
                        blurRadius: 28,
                        spreadRadius: 6,
                      ),
                    ],
                  ),
                  child: Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset(
                        AppConstants.logoAssetPath,
                        width: 58,
                        height: 58,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.shield_rounded,
                          size: 52,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // 品牌標題
              FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  children: [
                    Text(
                      I18nService.instance.t('app_title'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      I18nService.instance.t('splash_slogan'),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 13,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 48),

              // 進度指示器或重試介面
              if (!_hasError) ...[
                SizedBox(
                  width: 160,
                  child: LinearProgressIndicator(
                    backgroundColor: AppTheme.darkSurface,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryCyan),
                    borderRadius: BorderRadius.circular(4),
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _statusText,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 13,
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.dangerRose.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.dangerRose.withOpacity(0.3)),
                  ),
                  child: Text(
                    _errorMessage ?? I18nService.instance.t('splash_init_failed'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.dangerRose, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _startBootSequence,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(I18nService.instance.t('splash_retry_conn')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
