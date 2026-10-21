// lib/presentation/dashboard/widgets/customer_service_modal.dart

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../business/auth/auth_manager.dart';
import '../../../business/auth/user_model.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/i18n/i18n_service.dart';
import '../../../core/storage/secure_storage_service.dart';
import '../../../core/theme/app_theme.dart';

/// 天河網絡 Crisp 在線客服模態元件 (CustomerServiceModal)
/// 具備：
/// 1. 第一重保障：Embed URL 直接帶入官方識別參數 (user_email, user_nickname, token_id)
/// 2. 第二重保障：WebView onPageFinished 自動注入 $crisp.push 指令 (email, nickname, session:data)
/// 3. 自訂 User-Agent：對齊天河網絡版本與作業系統識別，同時保留 WebKit/Chrome 核心避免連線中斷
/// 4. Session 隔離：切換帳號或登出時自動清除 Cookies / LocalStorage / Cache，生成獨立 token_id
/// 5. 跨平台相容：Windows / 桌面端自動以外部瀏覽器開啟專屬識別 URL，Android / iOS 使用原生 In-App WebView
class CustomerServiceModal extends StatefulWidget {
  final String? crispId;
  final UserModel? user;

  const CustomerServiceModal({
    super.key,
    this.crispId,
    this.user,
  });

  static const String _kLastUserEmailKey = 'crisp_last_user_email';

  /// 構造 Crisp 專屬識別 URL (第一重保障)
  static String buildChatUrl({String? crispId, UserModel? user}) {
    final id = (crispId != null && crispId.trim().isNotEmpty)
        ? crispId.trim()
        : AppConstants.crispWebsiteId;

    if (user == null || user.email.trim().isEmpty) {
      return 'https://go.crisp.chat/chat/embed/?website_id=$id';
    }

    final email = user.email.trim();
    // 官方識別 Token：使用 SHA-256 生成確定性且長度合規 (64字元) 的 URL-Safe Token
    final tokenHash = sha256
        .convert(utf8.encode('tianhe_${email.toLowerCase()}'))
        .toString();

    final encodedEmail = Uri.encodeComponent(email);
    final encodedNickname = Uri.encodeComponent(email);

    return 'https://go.crisp.chat/chat/embed/?website_id=$id&user_email=$encodedEmail&user_nickname=$encodedNickname&token_id=$tokenHash';
  }

  /// 靜態會話清理方法 (供登出或 401 攔截時呼叫，徹底防止多帳號串號)
  static Future<void> clearSession() async {
    try {
      await WebViewCookieManager().clearCookies();
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kLastUserEmailKey);
    } catch (_) {}
  }

  /// 統一呼叫入口：自動依據平台特性開啟 Crisp 客服
  /// - 桌面端 (Windows / macOS / Linux)：直接調用預設瀏覽器開啟帶有身分識別與 Token 的專屬對話 URL
  /// - 行動端 (Android / iOS)：開啟全螢幕 In-App 原生 WebView
  static Future<void> show(
    BuildContext context, {
    String? crispId,
    UserModel? user,
    AuthManager? authManager,
  }) async {
    UserModel? effectiveUser = user ?? authManager?.state.user;
    if (effectiveUser == null || effectiveUser.email.trim().isEmpty) {
      try {
        final storage = SecureStorageService();
        final cachedJson = await storage.getUserInfoJson();
        if (cachedJson != null && cachedJson.isNotEmpty) {
          effectiveUser = UserModel.fromRawJson(cachedJson);
        }
      } catch (_) {}
    }

    final isDesktop = !kIsWeb &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

    if (isDesktop) {
      final url = buildChatUrl(crispId: crispId, user: effectiveUser);
      final uri = Uri.parse(url);
      try {
        final launched =
            await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!launched) {
          await launchUrl(uri);
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                effectiveUser != null && effectiveUser.email.isNotEmpty
                    ? '${I18nService.instance.t('crisp_connecting')} (${effectiveUser.email})'
                    : I18nService.instance.t('crisp_connecting'),
              ),
              duration: const Duration(seconds: 2),
              backgroundColor: AppTheme.darkCard,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('開啟外部瀏覽器失敗: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
      return;
    }

    // 行動端：以 MaterialPageRoute 推入原生效能 WebView
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomerServiceModal(
          crispId: crispId,
          user: effectiveUser,
        ),
      ),
    );
  }

  @override
  State<CustomerServiceModal> createState() => _CustomerServiceModalState();
}

class _CustomerServiceModalState extends State<CustomerServiceModal> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String? _errorMessage;
  late final String _chatUrl;

  @override
  void initState() {
    super.initState();
    _chatUrl = CustomerServiceModal.buildChatUrl(
      crispId: widget.crispId,
      user: widget.user,
    );
    _initWebView();
  }

  Future<void> _initWebView() async {
    try {
      final osVersion =
          '${Platform.operatingSystem} ${Platform.operatingSystemVersion}'
              .trim();
      final customUserAgent =
          '天河網絡/${AppConstants.appVersion} (Macintosh; Mac OS X; Apple Silicon/Intel; Build ${AppConstants.appBuildNumber}) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF131722))
        ..setUserAgent(customUserAgent)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (String url) {
              if (mounted) setState(() => _isLoading = true);
            },
            onPageFinished: (String url) async {
              if (mounted) setState(() => _isLoading = false);
              // 第二重保障：頁面載入完成後透過 JS SDK 注入用戶信箱、暱稱與套餐詳情
              if (widget.user != null &&
                  widget.user!.email.trim().isNotEmpty) {
                await _injectCrispUserData(widget.user!);
              }
            },
            onWebResourceError: (WebResourceError error) {
              if (mounted) {
                setState(() {
                  _errorMessage = error.description;
                  _isLoading = false;
                });
              }
            },
          ),
        );

      // Session 隔離檢查：若登入信箱與上次記錄不同，強制清理 Cookie、Cache 與 LocalStorage
      final prefs = await SharedPreferences.getInstance();
      final lastEmail = prefs.getString(CustomerServiceModal._kLastUserEmailKey);
      final currentEmail = widget.user?.email.trim() ?? '';
      if (lastEmail != currentEmail) {
        try {
          await WebViewCookieManager().clearCookies();
        } catch (_) {}
        try {
          await _controller.clearCache();
        } catch (_) {}
        try {
          await _controller.clearLocalStorage();
        } catch (_) {}
      }
      await prefs.setString(
          CustomerServiceModal._kLastUserEmailKey, currentEmail);

      await _controller.loadRequest(Uri.parse(_chatUrl));
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'WebView 初始化失敗: $e';
          _isLoading = false;
        });
      }
    }
  }

  /// 透過 JS SDK 注入真實登入帳號與套餐資訊
  Future<void> _injectCrispUserData(UserModel user) async {
    try {
      final email = user.email.trim();
      final planName = user.planName ?? '標準套餐';
      final trafficRemaining = user.remainingTrafficFormatted;
      final expireAt = user.expiredDateFormatted;
      const appVersion =
          'v${AppConstants.appVersion} (Build ${AppConstants.appBuildNumber})';
      final platformName = Platform.operatingSystem;
      final tokenHash = sha256
          .convert(utf8.encode('tianhe_${email.toLowerCase()}'))
          .toString();

      final jsCode = '''
(function() {
  var email = ${jsonEncode(email)};
  var plan = ${jsonEncode(planName)};
  var traffic = ${jsonEncode(trafficRemaining)};
  var expire = ${jsonEncode(expireAt)};
  var version = ${jsonEncode(appVersion)};
  var platform = ${jsonEncode(platformName)};
  var tokenHash = ${jsonEncode(tokenHash)};

  var sessionData = [
    ["Account", email],
    ["Plan", plan],
    ["Traffic_Remaining", traffic],
    ["Expire_At", expire],
    ["App_Version", version],
    ["Platform", platform]
  ];

  function applyData() {
    try {
      window.\$crisp = window.\$crisp || [];
      if (!window.CRISP_TOKEN_ID && tokenHash) {
        window.CRISP_TOKEN_ID = tokenHash;
      }
      if (typeof window.\$crisp.push === 'function') {
        window.\$crisp.push(["set", "user:email", [email]]);
        window.\$crisp.push(["set", "user:nickname", [email]]);
        window.\$crisp.push(["set", "session:data", [sessionData]]);
      }
      if (typeof window.\$crisp.set === 'function') {
        window.\$crisp.set("user:email", email);
        window.\$crisp.set("user:nickname", email);
        window.\$crisp.set("session:data", sessionData);
      }
    } catch(err) {
      console.error("[Crisp] Inject error:", err);
    }
  }

  // 立即執行注入
  applyData();

  // 輪詢重試確保非同步 SPA 初始化後覆蓋 (400ms 間隔，共 10 次)
  var count = 0;
  var timer = setInterval(function() {
    count++;
    applyData();
    if (count >= 10) clearInterval(timer);
  }, 400);
})();
''';
      await _controller.runJavaScript(jsCode);
    } catch (e) {
      debugPrint('[CustomerServiceModal] JS SDK 注入異常: $e');
    }
  }

  Future<void> _openExternalBrowser() async {
    final uri = Uri.parse(_chatUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18nService.instance;
    final userEmail = widget.user?.email.trim();

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.darkCard,
        elevation: 1,
        title: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: AppTheme.successEmerald,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    i18n.t('crisp_title'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    userEmail != null && userEmail.isNotEmpty
                        ? '$userEmail · ${widget.user?.planName ?? I18nService.instance.t('free_badge')}'
                        : I18nService.instance.t('online_service'),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white60,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.cyanAccent),
            tooltip: i18n.t('refresh'),
            onPressed: () {
              setState(() {
                _isLoading = true;
                _errorMessage = null;
              });
              _controller.reload();
            },
          ),
          IconButton(
            icon: const Icon(Icons.open_in_browser_rounded,
                color: Colors.white70),
            tooltip: i18n.t('crisp_open_browser'),
            onPressed: _openExternalBrowser,
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_errorMessage != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.chat_bubble_outline_rounded,
                        color: Colors.amber, size: 56),
                    const SizedBox(height: 16),
                    Text(
                      '無法載入內嵌聊天視窗 ($_errorMessage)',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: _openExternalBrowser,
                      icon: const Icon(Icons.open_in_browser_rounded),
                      label: Text(i18n.t('crisp_open_browser')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.cyanAccent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            WebViewWidget(controller: _controller),

          if (_isLoading)
            Container(
              color: AppTheme.darkBackground,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                        color: AppTheme.cyanAccent),
                    const SizedBox(height: 16),
                    Text(
                      i18n.t('crisp_connecting'),
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
