// lib/presentation/auth/forgot_password_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/i18n/i18n_service.dart';
import '../../business/auth/auth_manager.dart';
import '../../infrastructure/config/app_config_service.dart';

/// 忘記密碼 / 重置密碼介面 (ForgotPasswordScreen - 深度統一 App 賽博科技風與 Material 3 美學)
class ForgotPasswordScreen extends StatefulWidget {
  final AuthManager authManager;
  final AppConfigService configService;

  const ForgotPasswordScreen({
    super.key,
    required this.authManager,
    required this.configService,
  });

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  bool _isSendingCode = false;
  int _countdown = 0;
  Timer? _timer;

  String? _errorMessage;
  String? _successMessage;

  @override
  void dispose() {
    _timer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  /// 獲取完整電子郵件 (找回密碼頁純淨完整輸入)
  String get _fullEmail => _emailController.text.trim();

  /// 發送郵箱驗證碼 (對接 V2Board: POST /api/v1/passport/comm/sendEmailVerify)
  Future<void> _handleSendEmailCode() async {
    final email = _fullEmail;
    if (email.isEmpty) {
      setState(() {
        _errorMessage = '請先輸入完整郵箱帳號';
        _successMessage = null;
      });
      return;
    }

    setState(() {
      _isSendingCode = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      await widget.authManager.sendEmailVerify(email);
      if (!mounted) return;

      setState(() {
        _isSendingCode = false;
        _countdown = 60;
        _successMessage = '驗證碼已發送至 $email，請查收';
      });

      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_countdown <= 1) {
          timer.cancel();
          if (mounted) setState(() => _countdown = 0);
        } else {
          if (mounted) setState(() => _countdown--);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSendingCode = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  /// 提交重置密碼 (對接 V2Board: POST /api/v1/passport/auth/forget)
  Future<void> _handleResetPassword() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() {
        _errorMessage = '兩次輸入的密碼不一致';
        _successMessage = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      await widget.authManager.resetPassword(
        email: _fullEmail,
        password: _passwordController.text,
        emailCode: _codeController.text.trim(),
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _successMessage = '密碼重置成功！請使用新密碼登入';
      });

      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
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
                      // 1. 頂部 天河網絡旋渦 Logo (賽博微光環)
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

                      // 2. 主標題與引導詞 (徹底移除網頁下載字眼，統一 App 風格)
                      Text(
                        I18nService.instance.t('reset_pwd_title'),
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
                        I18nService.instance.t('reset_pwd_desc'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.6),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 28),

                      // 3. 訊息提示條 (錯誤或成功)
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
                      if (_successMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                          decoration: BoxDecoration(
                            color: AppTheme.successEmerald.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.successEmerald.withOpacity(0.5)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle_outline_rounded, color: AppTheme.successEmerald, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _successMessage!,
                                  style: const TextStyle(color: AppTheme.successEmerald, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],

                      // 4. 完整郵箱帳號輸入框 (找回密碼頁純淨完整輸入，無後綴下拉選單)
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
                                  hintText: '請輸入註冊時的完整郵箱帳號',
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

                      // 5. 郵箱驗證碼 + 科技感發送膠囊按鈕
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
                              child: Icon(Icons.mark_email_read_outlined, color: AppTheme.primaryCyan, size: 20),
                            ),
                            Expanded(
                              child: TextFormField(
                                controller: _codeController,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                                decoration: InputDecoration(
                                  hintText: I18nService.instance.t('email_code_hint'),
                                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 13),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                                ),
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) {
                                    return '請輸入驗證碼';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(5.0),
                              child: Container(
                                width: 92,
                                height: 42,
                                decoration: BoxDecoration(
                                  gradient: (_countdown > 0 || _isSendingCode)
                                      ? null
                                      : const LinearGradient(
                                          colors: [AppTheme.primaryCyan, AppTheme.primaryIndigo],
                                        ),
                                  color: (_countdown > 0 || _isSendingCode) ? AppTheme.darkBorder : null,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: (_countdown > 0 || _isSendingCode)
                                        ? null
                                        : _handleSendEmailCode,
                                    child: Center(
                                      child: _isSendingCode
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                            )
                                          : Text(
                                              _countdown > 0 ? '${_countdown}s' : I18nService.instance.t('send_code'),
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: (_countdown > 0) ? Colors.white60 : Colors.black,
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 6. 新密碼
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
                            hintText: I18nService.instance.t('pwd_set_hint'),
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
                            if (val == null || val.length < 6) return '密碼長度至少需 6 位';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 7. 再次確認新密碼
                      Container(
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppTheme.darkSurface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.darkBorder),
                        ),
                        child: TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirm,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.lock_reset_rounded, color: AppTheme.primaryCyan, size: 20),
                            hintText: I18nService.instance.t('pwd_confirm_hint'),
                            hintStyle: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 13),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                size: 18,
                                color: Colors.white54,
                              ),
                              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                            ),
                          ),
                          validator: (val) {
                            if (val == null || val.isEmpty) return '請再次輸入密碼';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 8. 賽博科技極光漸層重置按鈕
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
                            onTap: _isLoading ? null : _handleResetPassword,
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
                                        const Icon(Icons.lock_reset_rounded, size: 20, color: Colors.black),
                                        const SizedBox(width: 8),
                                        Text(
                                          I18nService.instance.t('reset_pwd_btn'),
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
                      const SizedBox(height: 22),

                      // 9. 底部導航 (返回登入 / 🌐 簡體中文)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: Row(
                              children: [
                                const Icon(Icons.arrow_back_rounded, size: 16, color: AppTheme.primaryCyan),
                                const SizedBox(width: 4),
                                Text(
                                  I18nService.instance.t('back_to_login'),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.primaryCyan,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
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
}
