// lib/presentation/profile/change_password_screen.dart

import 'package:flutter/material.dart';
import '../../core/i18n/i18n_service.dart';
import '../../core/network/dio_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/error_sanitizer.dart';

/// 修改密碼 (ChangePasswordScreen) - 統一深海科技風 (Dark Tech Theme)
class ChangePasswordScreen extends StatefulWidget {
  final DioClient dioClient;

  const ChangePasswordScreen({super.key, required this.dioClient});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final oldPwd = _oldPasswordController.text;
    final newPwd = _newPasswordController.text;
    final confirmPwd = _confirmPasswordController.text;

    if (newPwd != confirmPwd) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(I18nService.instance.t('pwd_mismatch')),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await widget.dioClient.post(
        '/api/v1/user/changePassword',
        data: {
          'old_password': oldPwd,
          'new_password': newPwd,
        },
      );

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(I18nService.instance.t('pwd_changed_success')),
          backgroundColor: AppTheme.successEmerald,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        final sanitized = ErrorSanitizer.sanitize(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${I18nService.instance.t('change_pw_failed_prefix')}$sanitized'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18nService.instance;

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        title: Text(
          i18n.t('profile_password'),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
                decoration: BoxDecoration(
                  color: AppTheme.darkSurface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppTheme.darkBorder),
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 頂部圓形圖示 (科技深色光暈)
                      Center(
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryCyan.withOpacity(0.12),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppTheme.primaryCyan.withOpacity(0.3),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryCyan.withOpacity(0.2),
                                blurRadius: 20,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.sync_lock_rounded,
                              size: 36,
                              color: AppTheme.primaryCyan,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 標題與說明
                      Center(
                        child: Column(
                          children: [
                            Text(
                              i18n.t('profile_password'),
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              i18n.t('pwd_desc'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withOpacity(0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),

                      // 1. 當前密碼輸入框
                      _buildPasswordField(
                        controller: _oldPasswordController,
                        hintText: i18n.t('pwd_old_hint'),
                        icon: Icons.lock_clock_outlined,
                        obscure: _obscureOld,
                        onToggleObscure: () => setState(() => _obscureOld = !_obscureOld),
                        validator: (v) =>
                            (v == null || v.isEmpty) ? i18n.t('pwd_old_required') : null,
                      ),
                      const SizedBox(height: 16),

                      // 2. 新密碼輸入框
                      _buildPasswordField(
                        controller: _newPasswordController,
                        hintText: i18n.t('pwd_new_hint'),
                        icon: Icons.lock_outline_rounded,
                        obscure: _obscureNew,
                        onToggleObscure: () => setState(() => _obscureNew = !_obscureNew),
                        validator: (v) {
                          if (v == null || v.isEmpty) return i18n.t('pwd_new_required');
                          if (v.length < 8) return i18n.t('pwd_length_min');
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // 3. 確認新密碼輸入框
                      _buildPasswordField(
                        controller: _confirmPasswordController,
                        hintText: i18n.t('pwd_confirm_label'),
                        icon: Icons.lock_person_outlined,
                        obscure: _obscureConfirm,
                        onToggleObscure: () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                        validator: (v) =>
                            (v == null || v.isEmpty) ? i18n.t('pwd_confirm_required') : null,
                      ),
                      const SizedBox(height: 30),

                      // 4. 確認修改按鈕 (科技青藍漸層 + 呼吸陰影)
                      Container(
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppTheme.primaryCyan, Color(0xFF0072FF)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryCyan.withOpacity(0.3),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _isSubmitting ? null : _handleSubmit,
                          child: _isSubmitting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: Colors.white,
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.autorenew_rounded,
                                      size: 20,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      i18n.t('pwd_btn_submit'),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
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

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    required bool obscure,
    required VoidCallback onToggleObscure,
    required String? Function(String?) validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        style: const TextStyle(fontSize: 14, color: Colors.white),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            color: Colors.white.withOpacity(0.35),
            fontSize: 14,
          ),
          prefixIcon: Icon(icon, size: 20, color: AppTheme.primaryCyan),
          suffixIcon: IconButton(
            icon: Icon(
              obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 20,
              color: Colors.white54,
            ),
            onPressed: onToggleObscure,
          ),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        ),
        validator: validator,
      ),
    );
  }
}
