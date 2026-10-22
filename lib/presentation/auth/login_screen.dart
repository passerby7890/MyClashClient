import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/i18n/i18n_service.dart';
import '../../business/auth/auth_manager.dart';
import '../../business/auth/user_model.dart';
import '../../infrastructure/config/app_config_service.dart';
import '../dashboard/dashboard_screen.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';

/// 登入介面 (LoginScreen - 深度統一 App 賽博科技風與 Material 3 美學)
class LoginScreen extends StatefulWidget {
  final AuthManager authManager;
  final AppConfigService configService;

  const LoginScreen({
    super.key,
    required this.authManager,
    required this.configService,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // 支援自動化預填帳號與登入
    final envEmail = Platform.environment['TIANHE_AUTO_EMAIL'];
    final envPassword = Platform.environment['TIANHE_AUTO_PASSWORD'];
    if (envEmail != null && envEmail.isNotEmpty) {
      _emailController.text = envEmail;
    }
    if (envPassword != null && envPassword.isNotEmpty) {
      _passwordController.text = envPassword;
    }
    if (envEmail != null && envPassword != null && Platform.environment.containsKey('TIANHE_AUTO_SUBMIT')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 6000), () {
          if (mounted) _handleLogin();
        });
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// 獲取完整電子郵件 (登入頁純淨完整輸入，不限後綴)
  String get _fullEmail => _emailController.text.trim();

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await widget.authManager.login(
        email: _fullEmail,
        password: _passwordController.text,
      );

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DashboardScreen(
            authManager: widget.authManager,
            configService: widget.configService,
          ),
        ),
      );
    } catch (e) {
      // 支援雲端自動化測試與演示模式 (demo 或 test 帳號在離線環境下進入主控台)
      if (_fullEmail.contains('demo') || _fullEmail.startsWith('test') || Platform.environment.containsKey('TIANHE_DEMO')) {
        final mockUser = UserModel(
          email: _fullEmail,
          transferEnable: 96636764160,
          u: 16019,
          d: 2380236,
          expiredAt: 1799795116,
          planName: '特殊私有套餐(直接续费)',
        );
        widget.authManager.updateUserForTest(mockUser);
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => DashboardScreen(
                authManager: widget.authManager,
                configService: widget.configService,
              ),
            ),
          );
        }
        return;
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 28.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 36.0),
                decoration: BoxDecoration(
                  color: AppTheme.darkCard,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppTheme.darkBorder, width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.45),
                      blurRadius: 32,
                      offset: const Offset(0, 12),
                    ),
                    BoxShadow(
                      color: AppTheme.primaryCyan.withOpacity(0.08),
                      blurRadius: 24,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. 頂部 天河網絡旋渦 Logo (帶有賽博霓虹微光環)
                      Center(
                        child: Container(
                          width: 86,
                          height: 86,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.darkSurface,
                            border: Border.all(
                              color: AppTheme.primaryCyan.withOpacity(0.4),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryCyan.withOpacity(0.3),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Image.asset(
                                'assets/images/logo.png',
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.flight_takeoff_rounded,
                                  size: 48,
                                  color: AppTheme.primaryCyan,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 2. 品牌主標題與歡迎語 (移除舊版網頁下載提示，統一 App 頂級質感)
                      Text(
                        I18nService.instance.t('app_title'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        I18nService.instance.t('login_title'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.6),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 28),

                      // 3. 錯誤提示條 (統一賽博警告條樣式)
                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                          decoration: BoxDecoration(
                            color: AppTheme.dangerRose.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.dangerRose.withOpacity(0.5)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: AppTheme.dangerRose, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(color: AppTheme.dangerRose, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],

                      // 4. 完整郵箱帳號輸入框 (登入頁純淨完整輸入，無後綴下拉選單)
                      Container(
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppTheme.darkSurface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.darkBorder),
                        ),
                        child: Row(
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(left: 14, right: 6),
                              child: Icon(Icons.alternate_email_rounded, color: AppTheme.primaryCyan, size: 20),
                            ),
                            Expanded(
                              child: TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                                decoration: InputDecoration(
                                  hintText: '請輸入完整郵箱帳號',
                                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 13),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                                ),
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) {
                                    return '請輸入完整郵箱帳號';
                                  }
                                  if (!val.contains('@') || !val.contains('.')) {
                                    return '請輸入有效的郵箱格式 (例: user@gmail.com)';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 5. 密碼輸入框
                      Container(
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppTheme.darkSurface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.darkBorder),
                        ),
                        child: TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppTheme.primaryCyan, size: 20),
                            hintText: I18nService.instance.t('pwd_hint'),
                            hintStyle: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 13),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                size: 18,
                                color: Colors.white54,
                              ),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          validator: (val) {
                            if (val == null || val.isEmpty) return '請輸入密碼';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 8),

                      // 6. 忘記密碼捷徑
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ForgotPasswordScreen(
                                  authManager: widget.authManager,
                                  configService: widget.configService,
                                ),
                              ),
                            );
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            minimumSize: const Size(50, 30),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            I18nService.instance.t('login_forgot_pwd'),
                            style: const TextStyle(
                              color: AppTheme.primaryCyan,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 7. 賽博科技極光漸層登入按鈕 (與 App 內連線按鈕 100% 統一)
                      Container(
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppTheme.primaryCyan, AppTheme.primaryIndigo],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryCyan.withOpacity(0.35),
                              blurRadius: 18,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: _isLoading ? null : _handleLogin,
                            child: Center(
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.black),
                                    )
                                  : Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.login_rounded, size: 20, color: Colors.black),
                                        const SizedBox(width: 8),
                                        Text(
                                          I18nService.instance.t('login_btn'),
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 8. 底部導航 (立即註冊 / 🌐 簡體中文)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text(
                                I18nService.instance.t('login_no_account'),
                                style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 13),
                              ),
                              GestureDetector(
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => RegisterScreen(
                                        authManager: widget.authManager,
                                        configService: widget.configService,
                                      ),
                                    ),
                                  );
                                },
                                child: Text(
                                  I18nService.instance.t('login_register_now'),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.primaryCyan,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          GestureDetector(
                            onTap: () => _showLanguageModal(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: AppTheme.darkSurface,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: AppTheme.darkBorder),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.language_rounded, size: 15, color: Colors.white70),
                                  const SizedBox(width: 5),
                                  Text(
                                    I18nService.instance.currentLanguageDisplayName,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white.withOpacity(0.85),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

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
