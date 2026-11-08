// lib/presentation/auth/register_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/i18n/i18n_service.dart';
import '../../core/utils/error_sanitizer.dart';
import '../../business/auth/auth_manager.dart';
import '../../infrastructure/config/app_config_service.dart';
import '../dashboard/dashboard_screen.dart';

/// 註冊介面 (RegisterScreen - 深度統一 App 賽博科技風與 Material 3 美學)
class RegisterScreen extends StatefulWidget {
  final AuthManager authManager;
  final AppConfigService configService;

  const RegisterScreen({
    super.key,
    required this.authManager,
    required this.configService,
  });

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailPrefixController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _inviteCodeController = TextEditingController();

  /// 預設主流 15 大白名單郵箱後綴 (按熱門度排序，剛好 3x5 網格)
  static const List<String> defaultAllowedEmailSuffixes = [
    'qq.com',
    'gmail.com',
    '163.com',
    'outlook.com',
    '126.com',
    'foxmail.com',
    'hotmail.com',
    'yahoo.com',
    'sina.com',
    'aliyun.com',
    '139.com',
    '189.cn',
    'sohu.com',
    'yeah.net',
    'zoho.com.cn',
  ];

  late List<String> _suffixes;
  String _selectedSuffix = 'qq.com';

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  bool _isSendingCode = false;
  int _countdown = 0;
  Timer? _timer;

  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _suffixes = List.from(widget.authManager.emailWhitelist.isNotEmpty
        ? widget.authManager.emailWhitelist
        : defaultAllowedEmailSuffixes);
    _selectedSuffix = _suffixes.first.replaceAll('@', '');
    _fetchDynamicWhitelist();
  }

  Future<void> _fetchDynamicWhitelist() async {
    try {
      final list = await widget.authManager.fetchEmailWhitelist();
      if (mounted && list.isNotEmpty) {
        setState(() {
          _suffixes = List.from(list);
          if (!_suffixes.contains(_selectedSuffix)) {
            _selectedSuffix = _suffixes.first.replaceAll('@', '');
          }
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    _emailPrefixController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  /// 智慧輸入與貼上自動識別 (Smart Paste Split)
  void _onEmailPrefixChanged(String val) {
    if (val.contains('@')) {
      final parts = val.split('@');
      final prefix = parts[0].trim();
      final domain = parts.length > 1 ? parts[1].trim().toLowerCase() : '';

      final cleanList = _suffixes.map((s) => s.replaceAll('@', '').toLowerCase()).toList();

      if (domain.isNotEmpty) {
        if (cleanList.contains(domain)) {
          setState(() {
            _selectedSuffix = domain;
            _errorMessage = null;
          });
        } else {
          setState(() {
            _errorMessage = '該郵箱後綴 (@$domain) 不支援註冊，請選擇主流郵箱';
          });
        }
      }

      _emailPrefixController.value = TextEditingValue(
        text: prefix,
        selection: TextSelection.collapsed(offset: prefix.length),
      );
    }
  }

  /// 組合完整電子郵件 (強制 前綴 + '@' + 選中白名單後綴)
  String get _fullEmail {
    final prefix = _emailPrefixController.text.trim();
    final cleanSuffix = _selectedSuffix.replaceAll('@', '').trim();
    return '$prefix@$cleanSuffix';
  }

  /// 彈出精緻居中科技感後綴選擇面板 (徹底解決底部跑位與肥大按鈕問題)
  void _showSuffixPickerModal() {
    final cleanList = _suffixes.map((s) => s.replaceAll('@', '')).toList();

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.65),
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A), // 深海藍科技感面板
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: AppTheme.primaryCyan.withOpacity(0.4),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.7),
                    blurRadius: 32,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: AppTheme.primaryCyan.withOpacity(0.18),
                    blurRadius: 24,
                    spreadRadius: 1,
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 標題欄 (天河藍科技感標籤 + 關閉按鈕，無手機拉條)
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryCyan.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppTheme.primaryCyan.withOpacity(0.3),
                          ),
                        ),
                        child: const Icon(
                          Icons.alternate_email_rounded,
                          color: AppTheme.primaryCyan,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        '選擇註冊郵箱後綴',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                        splashRadius: 18,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 緊湊網格 (3 欄，長寬比 2.9，小巧精緻膠囊，告別肥大笨重按鈕)
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 2.9,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: cleanList.length,
                    itemBuilder: (context, index) {
                      final suffix = cleanList[index];
                      final isSelected = suffix == _selectedSuffix.replaceAll('@', '');
                      return InkWell(
                        onTap: () {
                          setState(() {
                            _selectedSuffix = suffix;
                            _errorMessage = null;
                          });
                          Navigator.pop(ctx);
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.primaryCyan.withOpacity(0.18)
                                : AppTheme.darkSurface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.primaryCyan
                                  : Colors.white.withOpacity(0.12),
                              width: isSelected ? 1.5 : 1,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: AppTheme.primaryCyan.withOpacity(0.35),
                                      blurRadius: 8,
                                    ),
                                  ]
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '@$suffix',
                            style: TextStyle(
                              color: isSelected ? AppTheme.primaryCyan : Colors.white70,
                              fontSize: 12.5,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 發送郵箱驗證碼 (對接 V2Board: POST /api/v1/passport/comm/sendEmailVerify)
  Future<void> _handleSendEmailCode() async {
    final prefix = _emailPrefixController.text.trim();
    if (prefix.isEmpty) {
      setState(() {
        _errorMessage = '請先輸入郵箱帳號';
        _successMessage = null;
      });
      return;
    }

    // 嚴格後綴白名單二度校驗
    final cleanSuffix = _selectedSuffix.replaceAll('@', '').toLowerCase().trim();
    final cleanList = _suffixes.map((s) => s.replaceAll('@', '').toLowerCase().trim()).toList();
    if (!cleanList.contains(cleanSuffix)) {
      setState(() {
        _errorMessage = '該郵箱後綴不支援註冊，請選擇主流郵箱';
        _successMessage = null;
      });
      return;
    }

    final email = _fullEmail;
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
        _errorMessage = ErrorSanitizer.sanitize(e);
      });
    }
  }

  /// 提交註冊 (對接 V2Board: POST /api/v1/passport/auth/register)
  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() {
        _errorMessage = '兩次輸入的密碼不一致';
        _successMessage = null;
      });
      return;
    }

    // 嚴格後綴白名單二度校驗
    final cleanSuffix = _selectedSuffix.replaceAll('@', '').toLowerCase().trim();
    final cleanList = _suffixes.map((s) => s.replaceAll('@', '').toLowerCase().trim()).toList();
    if (!cleanList.contains(cleanSuffix)) {
      setState(() {
        _errorMessage = '該郵箱後綴不支援註冊，請選擇主流郵箱';
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
      await widget.authManager.register(
        email: _fullEmail,
        password: _passwordController.text,
        emailCode: _codeController.text.trim().isNotEmpty
            ? _codeController.text.trim()
            : null,
        inviteCode: _inviteCodeController.text.trim().isNotEmpty
            ? _inviteCodeController.text.trim()
            : null,
      );

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => DashboardScreen(
            authManager: widget.authManager,
            configService: widget.configService,
          ),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = ErrorSanitizer.sanitize(e);
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
                        I18nService.instance.t('register_title'),
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
                        I18nService.instance.t('register_desc'),
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

                      // 4. 郵箱前綴輸入框 + 3x5 網格後綴觸發膠囊按鈕 (告別長條遮擋)
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
                                controller: _emailPrefixController,
                                keyboardType: TextInputType.emailAddress,
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                                onChanged: _onEmailPrefixChanged,
                                decoration: InputDecoration(
                                  hintText: '請輸入郵箱前綴 (不含@)',
                                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 13),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                                ),
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) {
                                    return '請輸入郵箱前綴';
                                  }
                                  if (val.contains('@')) {
                                    return '郵箱前綴不可包含 @';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            Container(width: 1, height: 26, color: AppTheme.darkBorder),
                            // 右側後綴觸發膠囊按鈕
                            InkWell(
                              onTap: _showSuffixPickerModal,
                              borderRadius: const BorderRadius.horizontal(right: Radius.circular(14)),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '@${_selectedSuffix.replaceAll('@', '')}',
                                      style: const TextStyle(
                                        color: AppTheme.primaryCyan,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      size: 18,
                                      color: AppTheme.primaryCyan,
                                    ),
                                  ],
                                ),
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

                      // 6. 密碼輸入框
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

                      // 7. 再次確認密碼框
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
                      const SizedBox(height: 16),

                      // 8. 邀請碼 (選填)
                      Container(
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppTheme.darkSurface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.darkBorder),
                        ),
                        child: TextFormField(
                          controller: _inviteCodeController,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.card_giftcard_rounded, color: AppTheme.primaryCyan, size: 20),
                            hintText: I18nService.instance.t('invite_code_optional'),
                            hintStyle: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 13),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 9. 賽博科技極光漸層註冊按鈕
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
                            onTap: _isLoading ? null : _handleRegister,
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
                                        const Icon(Icons.person_add_rounded, size: 20, color: Colors.black),
                                        const SizedBox(width: 8),
                                        Text(
                                          I18nService.instance.t('register_btn'),
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

                      // 10. 底部導航 (返回登入 / 🌐 簡體中文)
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
