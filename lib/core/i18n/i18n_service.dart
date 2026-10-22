import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_constants.dart';
import '../storage/secure_storage_service.dart';

/// 支援的語系定義 (支援：繁中、簡中、英文、日文)
enum AppLanguage {
  zhTW('zh_TW', '繁體中文', '繁體中文', '🇹🇼'),
  zhCN('zh_CN', '简体中文', '简体中文', '🇨🇳'),
  en('en', 'English', 'English', '🇺🇸'),
  ja('ja', '日本語', '日本語', '🇯🇵');

  final String code;
  final String label;
  final String nativeName;
  final String flagEmoji;

  const AppLanguage(this.code, this.label, this.nativeName, this.flagEmoji);

  static AppLanguage fromCode(String? code) {
    if (code == null) return AppLanguage.zhTW;
    for (final lang in AppLanguage.values) {
      if (lang.code == code || lang.code.startsWith(code.toLowerCase())) {
        return lang;
      }
    }
    return AppLanguage.zhTW;
  }
}

/// 輕量且功能完整的原生多語系服務
/// 支援動態切換、智慧跟隨系統語系、持久化狀態機與全頁面即時響應
class I18nService extends ChangeNotifier with WidgetsBindingObserver {
  static final I18nService instance = I18nService._internal();
  I18nService._internal();

  AppLanguage _currentLanguage = AppLanguage.zhTW;
  bool _isFollowSystem = true;
  SecureStorageService? _storageService;
  bool _observerRegistered = false;

  AppLanguage get currentLanguage => _currentLanguage;
  bool get isFollowSystem => _isFollowSystem;
  String get currentCode => _currentLanguage.code;

  static const MethodChannel _nativeWindowChannel = MethodChannel('tianhe/window');

  Future<void> _updateNativeWindowTitle() async {
    if (!kIsWeb && (Platform.isMacOS || Platform.isWindows)) {
      try {
        await _nativeWindowChannel.invokeMethod('setWindowTitle', t('window_title'));
      } catch (_) {}
    }
  }

  /// 對外提供顯示用的名稱 (如: "繁體中文" 或 "English")
  String get currentLanguageDisplayName => _currentLanguage.label;

  /// 對齊 V2Board 後端 API 格式 (zh-CN, zh-TW, en-US, ja-JP)
  String get apiLanguageCode {
    switch (_currentLanguage) {
      case AppLanguage.zhTW:
        return 'zh-TW';
      case AppLanguage.zhCN:
        return 'zh-CN';
      case AppLanguage.en:
        return 'en-US';
      case AppLanguage.ja:
        return 'ja-JP';
    }
  }

  Locale get currentLocale {
    switch (_currentLanguage) {
      case AppLanguage.zhTW:
        return const Locale('zh', 'TW');
      case AppLanguage.zhCN:
        return const Locale('zh', 'CN');
      case AppLanguage.en:
        return const Locale('en', 'US');
      case AppLanguage.ja:
        return const Locale('ja', 'JP');
    }
  }

  /// 自動解析系統語系 (支援傳入 Locale 或 String 代碼)
  static AppLanguage resolveSystemLanguage([dynamic targetLocale]) {
    try {
      if (targetLocale is String) {
        final lower = targetLocale.toLowerCase();
        if (lower.contains('hant') || lower.contains('tw') || lower.contains('hk') || lower.contains('mo') || lower.contains('traditional')) {
          return AppLanguage.zhTW;
        }
        if (lower.startsWith('zh')) {
          return AppLanguage.zhCN;
        }
        return AppLanguage.en;
      }
      final locale = targetLocale is Locale ? targetLocale : WidgetsBinding.instance.platformDispatcher.locale;
      final langCode = locale.languageCode.toLowerCase();
      final countryCode = locale.countryCode?.toUpperCase() ?? '';
      final scriptCode = locale.scriptCode?.toLowerCase() ?? '';

      if (langCode == 'zh') {
        if (scriptCode == 'hant' ||
            countryCode == 'TW' ||
            countryCode == 'HK' ||
            countryCode == 'MO') {
          return AppLanguage.zhTW;
        }
        return AppLanguage.zhCN;
      } else if (langCode == 'ja') {
        return AppLanguage.ja;
      } else if (langCode == 'en') {
        return AppLanguage.en;
      }
      // 其他任何非中/日之語系預設呈現通用 English
      return AppLanguage.en;
    } catch (_) {
      return AppLanguage.en;
    }
  }

  /// 初始化語言設定 (首次啟動自動解析系統語言並持久化，提供 4 國純淨選項)
  Future<void> init({SecureStorageService? storageService}) async {
    _storageService = storageService ?? SecureStorageService();

    if (!_observerRegistered) {
      WidgetsBinding.instance.addObserver(this);
      _observerRegistered = true;
    }

    try {
      final savedCode =
          await _storageService!.read(AppConstants.storageAppLanguage);
      if (savedCode == null || savedCode.isEmpty || savedCode == 'auto') {
        _isFollowSystem = false;
        _currentLanguage = resolveSystemLanguage();
        await _storageService!
            .write(AppConstants.storageAppLanguage, _currentLanguage.code);
      } else {
        _isFollowSystem = false;
        _currentLanguage = AppLanguage.fromCode(savedCode);
      }
    } catch (_) {
      _isFollowSystem = false;
      _currentLanguage = resolveSystemLanguage();
    }
    _updateNativeWindowTitle();
    notifyListeners();
  }

  /// 監聽系統語系變更 (當處於 Follow System 模式且使用者變更手機語言時即時切換)
  @override
  void didChangeLocales(List<Locale>? locales) {
    super.didChangeLocales(locales);
    if (_isFollowSystem) {
      final resolved = resolveSystemLanguage();
      if (_currentLanguage != resolved) {
        _currentLanguage = resolved;
        _updateNativeWindowTitle();
        notifyListeners();
      }
    }
  }

  /// 切換為「跟隨系統」
  Future<void> setFollowSystem() async {
    _isFollowSystem = true;
    _currentLanguage = resolveSystemLanguage();
    try {
      if (_storageService != null) {
        await _storageService!
            .write(AppConstants.storageAppLanguage, 'auto');
      }
    } catch (_) {}
    _updateNativeWindowTitle();
    notifyListeners();
  }

  /// 手動指定切換語言並持久化
  Future<void> setLanguage(AppLanguage language) async {
    _isFollowSystem = false;
    _currentLanguage = language;
    try {
      if (_storageService != null) {
        await _storageService!
            .write(AppConstants.storageAppLanguage, language.code);
      }
    } catch (_) {}
    _updateNativeWindowTitle();
    notifyListeners();
  }

  /// 支援以語系字串代碼切換 (相容測試與外部呼叫)
  Future<void> setLocale(String code) async {
    final lower = code.toLowerCase();
    if (lower.contains('hant') || lower == 'zh_tw' || lower == 'zh-tw') {
      await setLanguage(AppLanguage.zhTW);
    } else if (lower.contains('hans') || lower == 'zh_cn' || lower == 'zh-cn') {
      await setLanguage(AppLanguage.zhCN);
    } else if (lower.startsWith('ja')) {
      await setLanguage(AppLanguage.ja);
    } else {
      await setLanguage(AppLanguage.en);
    }
  }

  /// switchLanguage 便捷別名
  Future<void> switchLanguage(String code) => setLocale(code);

  /// 獲取翻譯文字 (支援動態參數插值如 {name}, {count})
  String t(String key, [Map<String, String>? params]) {
    final langDict = _translations[_currentLanguage.code] ??
        _translations[AppLanguage.zhTW.code]!;
    var text = langDict[key] ??
        _translations[AppLanguage.zhTW.code]?[key] ??
        _translations[AppLanguage.en.code]?[key] ??
        key;
    if (params != null && params.isNotEmpty) {
      params.forEach((paramKey, paramValue) {
        text = text.replaceAll('{$paramKey}', paramValue);
      });
    }
    return text;
  }

  // --- 繁/簡/英/日 100% 完整字典表 ---
  static final Map<String, Map<String, String>> _translations = {
    // ══════════════════════════════════════════════════════════════════════════
    // 繁體中文 (zh_TW)
    // ══════════════════════════════════════════════════════════════════════════
    'zh_TW': {
      // 底部導航列與桌面側邊欄
      'nav_home': '加速主頁',
      'nav_plan': '套餐',
      'nav_shop': '購買套餐',
      'nav_nodes': '節點狀態',
      'nav_connections': '實時連接',
      'nav_traffic': '流量詳情',
      'nav_affiliate': '邀請推廣',
      'nav_more': '更多',
      'nav_profile': '個人中心',
      'nav_settings': '高級設置',
      'nav_docs': '文檔中心',
      'offline_mode': '離線模式',
      'sign_out': '退出登錄',
      'connection_status': '連線狀態',
      'current_node': '當前節點',
      'switch_node': '切換節點',
      'latency': '延遲探測',
      'download': '即時下載',
      'upload': '即時上傳',
      'traffic_stats': '流量統計',
      'global_network': '全球加速網絡',
      'tap_to_connect': '點擊一鍵連線',
      'status_disconnected': '未連接',
      'status_connecting': '連線中...',
      'status_connected': '已加速',
      'status_ready': '準備就緒',
      'status_establishing': '正在建立線路...',
      'status_disconnected_badge': '未連接',
      'status_connecting_badge': '連線中...',
      'status_connected_badge': '已加速',
      'tap_to_accelerate': '點擊一鍵連線',
      'status_connected_action': '已加速',
      'traffic_used_label': '已用 {value}',
      'traffic_left_label': '剩餘 {value}',
      'traffic_total_label': '總計 {value}',
      'protected_vpn': '已保護連線 (點擊斷開)',
      'btn_traffic_encrypted': '所有流量皆經過端到端加密通道',
      'btn_account_invalid': '帳號狀態異常或已逾期',
      'traffic_expired': '已到期',
      'traffic_warning_expired': '您的會員套餐已逾期，代理連線已暫停。',
      'traffic_warning_exhausted': '可用流量已耗盡，代理服務將受限！',
      'renew_now': '立即續費',
      'tap_to_disconnect': '已保護連線 (點擊斷開)',
      'fast': '極速',
      'scale_best': '極佳',
      'scale_good': '良好',
      'syncing': '同步中...',
      'sync_sub': '同步訂閱',
      'vip_badge': 'VIP',
      'free_badge': '免費',
      'profile_password': '修改密碼',
      'copied': '已複製到剪貼簿',
      'per_month': '/ 月',
      'hot_badge': '熱門',

      // 主頁儀表板
      'app_title': '天河網絡',
      'service_and_traffic': '流量與服務狀態',
      'details': '明細',
      'service_normal': '服務正常',
      'remaining_traffic': '剩餘可用流量',
      'used_traffic': '已使用',
      'total_traffic': '總容量',
      'expire_time': '到期時間',
      'never_expire': '長期有效',
      'guest_mode': '訪客模式',
      'logout': '登出',
      'logout_confirm_title': '確認登出',
      'logout_confirm_desc': '確定要退出當前帳號嗎？連線將自動中斷。',
      'speed_test_done': '全節點測速完成',
      'status_disconnecting': '正在斷開連線...',
      'status_error': '連線異常，請重試',
      'tap_to_connect_action': '點擊加速',
      'action_connecting': '連線中...',
      'action_accelerated': '已加速',
      'mode_global': '全局模式',
      'mode_rule': '規則模式',
      'mode_tun': 'TUN模式',
      'conn_th_proto': '協議',
      'conn_th_node': '出口節點',
      'sync_subscription': '同步訂閱',
      'speed_test': '節點測速',
      'select_node': '節點選擇',
      'online_service': '在線客服',
      'auto_select': '⚡ 自動選擇 (延遲最低)',
      'best_latency': '智慧優選',

      // 流量卡片與流量明細
      'traffic_details': '流量明細',
      'traffic_overview': '流量使用總覽',
      'traffic_remaining': '剩餘流量',
      'traffic_used': '已用流量',
      'traffic_total': '總配額',
      'traffic_upload': '上行流量',
      'traffic_download': '下行流量',
      'traffic_daily_log': '每日流量消耗記錄',
      'traffic_no_logs': '暫無流量使用記錄',
      'traffic_rate': '倍率',
      'traffic_unlimited': '無限期',
      'traffic_reset_in': '天後重置',
      'traffic_warning_low': '您的剩餘流量已低於 10%，請及時前往商城續約！',

      // 節點選擇彈窗
      'node_selector_title': '線路節點選擇',
      'node_select_fastest': '選最快',
      'node_batch_ping': '測速',
      'node_search_hint': '搜尋節點名稱、地區或協定...',
      'node_tab_favorites': '收藏',
      'node_tab_fastest': '最快',
      'node_tab_all': '全部',
      'node_tab_asia': '亞洲',
      'node_tab_western': '歐美',
      'node_tab_others': '其他',
      'node_pending_test': '待測',
      'node_testing': '測速中',
      'node_timeout': '逾時',
      'node_no_favorites': '尚未收藏任何節點，點擊星星即可加入收藏',
      'node_empty_fav': '您尚未收藏任何節點，點擊星星即可加入',
      'node_empty_all': '暫無可用節點，請嘗試同步訂閱',
      'node_empty_search': '未找到符合條件的節點',
      'node_switched_fastest': '已為您切換至最快節點：',
      'auto_connect_on_node_select': '選取節點後自動連線',
      'auto_connect_on_node_select_desc': '在節點頁面點擊切換節點時，自動跳回主頁並立即發起加速',
      'auto_connect_enabled_snack': '已開啟選取節點後自動連線',
      'auto_connect_disabled_snack': '已關閉選取節點後自動連線',

      // 套餐商城與訂單
      'shop_title': '套餐商城',
      'shop_subtitle': '選擇適合你的訂閱方案',
      'shop_tab_all': '全部',
      'shop_tab_cycle': '週期性',
      'shop_tab_one_time': '一次性',
      'shop_view_details': '查看完整權益',
      'shop_buy_now': '立即訂閱',
      'shop_order_history': '訂單記錄',
      'shop_renewal': '續費套餐',
      'shop_cycle_month': '按月計費',
      'shop_cycle_quarter': '按季計費',
      'shop_cycle_half_year': '半年計費',
      'shop_cycle_year': '按年計費',
      'shop_payment_title': '收銀台結帳',
      'shop_pay_btn': '前往支付',
      'shop_confirm_title': '更換套餐確認',
      'shop_select_period': '選擇訂閱週期',
      'shop_coupon_title': '優惠代碼 (選填)',
      'shop_coupon_hint': '輸入優惠折扣碼',
      'shop_order_now': '立即下單',
      'shop_cancel': '取消',
      'shop_empty': '暫無可用的套餐方案',
      'shop_traffic_unit': 'GB 流量',
      'shop_reload': '重新載入',

      // 更多功能頁
      'more_title': '更多功能',
      'more_diagnostics': '網路診斷與延遲探測',
      'more_system_about': '系統與關於',
      'more_check_update': '檢查版本更新',
      'more_current_version': '當前版本',
      'more_is_latest': '已是最新版本',
      'more_core_daemon': 'Mihomo 核心守護行程',
      'more_doh_protection': 'DoH 防封鎖防護',
      'more_customer_community': '客戶服務與社群',
      'more_tg_bot': '官方 Telegram 機器人',
      'more_tg_group': '官方 Telegram 社群',
      'more_routing_mode': '分流模式',
      'more_mode_rule': '規則分流 (推薦)',
      'more_mode_global': '全局代理',
      'more_mode_direct': '直連模式',
      'more_language': '介面語言 (Language)',
      'more_select_lang': '切換介面語言',
      'lang_auto': '跟隨系統',
      'more_about': '關於與版本',

      // 個人中心 (UserCenter)
      'profile_title': '我的',
      'profile_used_traffic': '已用流量',
      'profile_renew_plan': '續費 / 更換套餐',
      'profile_reset_traffic': '流量重置',
      'profile_help_support': '幫助與支持',
      'profile_order_history': '訂單記錄',
      'profile_traffic_details': '流量明細',
      'profile_ticket': '我的工單',
      'profile_service': '在線客服',
      'profile_language': '介面語言 (Language)',
      'profile_tg_bot': '官方 Telegram 機器人',
      'profile_tg_group': '加入官方交流群',
      'profile_website': '官方網站',
      'profile_invite': '邀請管理',
      'profile_commission': '佣金餘額',
      'profile_knowledge': '文檔中心',
      'profile_select_lang': '切換介面語言',
      'profile_gift_card': '禮品卡 / 兌換碼',
      'profile_logout': '登出帳號',

      // 工單
      'ticket_create': '創建工單',
      'ticket_title': '工單標題',
      'ticket_content': '問題描述',
      'ticket_priority': '優先級',
      'ticket_submit': '確認送出',
      'ticket_cancel': '取消',
      'ticket_empty': '暫無工單記錄',

      // 邀請
      'invite_balance': '帳戶餘額',
      'invite_commission': '佣金餘額',
      'invite_transfer': '佣金劃轉',
      'invite_create_code': '生成邀請碼',
      'invite_copy_success': '邀請連結已複製',

      // 客服
      'crisp_title': '天河網絡 官方在線客服',
      'crisp_connecting': '正在連接客服系統...',
      'crisp_open_browser': '瀏覽器開啟',

      // 更新
      'update_title': '發現新版本',
      'update_now': '立即更新',
      'update_later': '稍後再說',
      'update_force_tip': '此版本包含重大安全更新，必須升級後方可繼續使用。',

      // 通用
      'confirm': '確認',
      'cancel': '取消',
      'refresh': '重新載入',
      'shop_switch_plan_hint': '您即將更換為【{name}】({period} {price})，這將覆蓋您當前的使用方案。',
      'shop_more_features': '+{count} 項',
      'shop_features_privilege': '權益與特權：',
      'shop_confirm_select_plan': '確認選用方案',
      'traffic_ratio': '倍率:{rate}x',
      'traffic_up_short': '上行',
      'traffic_down_short': '下行',
      'traffic_total_short': '合計',
      'traffic_used_percent': '已用 {percent}%',
      'traffic_remaining_prefix': '剩餘可用: {value}',

      // 連線視圖 (Connections)
      'conn_title': '即時活動連線監控',
      'conn_subtitle_active': '活動連線數: {count} · 累積下載: {down} · 累積上傳: {up}',
      'conn_subtitle_idle': '核心處於待機狀態，連線後即時呈現網絡流量走向',
      'conn_search_hint': '搜尋主機或 IP...',
      'conn_close_all': '中斷全部連線',
      'conn_th_dest': '目標主機 / 端口',
      'conn_th_protocol': '協議',
      'conn_th_rule': '匹配規則',
      'conn_th_outbound': '出口節點',
      'conn_th_traffic': '傳輸流量 (下/上)',
      'conn_idle_placeholder': '核心待機中，點擊加速後即可監控即時連線',
      'conn_empty_active': '暫無活動網絡連線',
      'conn_no_active': '目前無活動網絡連線',
      'conn_empty_search': '無匹配的連線記錄',
      'conn_closed_all_msg': '已中斷所有活動代理連線',
      'conn_close_error': '操作失敗: {error}',
      'no_notice': '暫無系統公告',

      // 模式切換與加速按鈕
      'mode_direct': '直連模式',

      // 流量統計明細標籤

      // 桌面端快捷提示與對話框
      'tooltip_lang': '多語言切換',
      'tooltip_diag': '網路診斷',
      'tooltip_checkin': '每日簽到',
      'tooltip_service': '在線客服',
      'tooltip_notice': '最新公告',
      'admin_required_title': '需要系統管理員權限',
      'admin_required_desc': 'TUN 虛擬網卡模式需要以系統管理員權限運行，以安裝與接管 Wintun 驅動網卡。\n\n點擊下方按鈕將為您提權並以管理員身分重新啟動天河網絡客戶端。',
      'admin_restart_btn': '以管理員身分重啟',
      'sub_synced_success': '節點訂閱同步完成',
      'loading_nodes': '正在載入專屬節點...',

      // 開機自啟與更新
      'more_auto_start': '開機自動啟動',
      'auto_start_enabled': '已啟用',
      'auto_start_disabled': '已停用',
      'auto_start_snack_on': '已開啟開機自啟',
      'auto_start_snack_off': '已關閉開機自啟',
      'check_update_failed': '檢查更新失敗',
      'window_title': '天河網絡 - 全球極速安全連線客戶端',
      'splash_slogan': '安全 · 穩定 · 極速隧道',
      'splash_init_channel': '正在建立安全連線通道...',
      'splash_resolving_doh': '正在解析防封鎖線路 (DoH)...',
      'splash_checking_version': '正在檢查用戶端版本...',
      'splash_verifying_auth': '正在驗證帳號狀態...',
      'splash_init_failed': '初始化失敗，請檢查網路連線',
      'splash_retry_conn': '重試連線',

      // 網路診斷與彈窗
      'diag_title': '網路與連通性診斷',
      'diag_local_net': '本機網路連線',
      'diag_local_net_desc': '檢測本機網路適配器與 IP 連通狀態',
      'diag_api': 'V2Board 後台 API',
      'diag_api_desc': '檢測機場伺服器連通性與回應延遲',
      'diag_doh': 'DNS 解析 (DoH)',
      'diag_doh_desc': '檢測防污染 DoH / 系統 DNS 解析速度',
      'diag_core': 'Mihomo 核心與 TUN 介面',
      'diag_core_desc': '檢測系統級代理通道運行狀態',
      'diag_cross_border': '境外目標網站 (Google/CF)',
      'diag_cross_border_desc': '檢測跨境連線通暢度與 TLS 握手延遲',
      'diag_testing': '檢測中',
      'diag_retest': '重新檢測',
      'diag_local_nic': '本地網路介面',
      'diag_sys_proxy': '系統代理服務',
      'diag_core_controller': 'Mihomo 內核控制器',
      'diag_doh_anti': 'DNS 解析防封鎖',
      'done': '完成',
      'checkin_thanks': '感謝您使用天河網絡客戶端！',
      'checkin_credited': '本日已為您自動簽到並累計免費防護時長。',
      'no_announcements': '暫無最新公告',
      'local_user': '本機用戶',

      // 更新彈窗
      'update_force_title': '重要版本強制更新',
      'update_new_title': '發現新版本',
      'update_changelog_title': '更新日誌：',
      'update_default_changelog': '穩定性提升與問題修復。',
      'update_remind_later': '稍後提醒',
      'update_now_overwrite': '立即覆蓋更新',
      'update_now_upgrade': '立即升級',
      'update_preparing': '正在準備下載...',
      'update_no_url': '尚未提供該平台的安裝包下載網址',

      // 公告與登入
      'notice_coupon_prefix': '老客戶優惠碼: ',
      'notice_coupon_copied': '已複製優惠碼到剪貼簿',
      'copy_btn': '複製',
      'i_understand': '我知道了',
      'login_title': '登入您的帳號，暢享全球高速節點',
      'login_btn': '立即登入',
      'login_no_account': '還沒有帳號？',
      'login_register_now': '立即註冊',
      'login_forgot_pwd': '忘記密碼？',
      'email_hint': '郵箱帳號或完整郵箱',
      'pwd_hint': '請輸入密碼',
      'register_title': '建立新帳號',
      'register_desc': '註冊天河網絡，開啟安全極速通道',
      'register_btn': '建立帳號並登入',
      'back_to_login': '返回登入',
      'email_code_hint': '郵箱驗證碼',
      'send_code': '發送',
      'pwd_set_hint': '請設置密碼 (至少 6 位)',
      'pwd_confirm_hint': '再次輸入密碼',
      'invite_code_optional': '邀請碼 (選填)',
      'reset_pwd_title': '重置帳號密碼',
      'reset_pwd_desc': '驗證郵箱後即可設置新密碼',
      'reset_pwd_btn': '重置密碼並返回',

      // 加速按鈕與連線提示
      'syncing_routes': '正在同步專屬線路...',
      'node_unselected': '尚未選取節點',
      'tap_to_select_node': '點擊此處展開節點列表',
      'select_node_hint': '請先選取一個連線節點',
      'order_failed_prefix': '下單失敗',

      // 邀請推廣 (Affiliate)
      'affiliate_title': '邀請管理',
      'affiliate_codes_tab': '邀請碼列表',
      'affiliate_rebates_tab': '返傭記錄',
      'affiliate_create_code': '創建邀請碼',
      'affiliate_code_created': '成功創建新的邀請碼！',
      'affiliate_create_failed': '創建失敗',
      'affiliate_empty_codes': '暫無邀請碼，點擊上方按鈕創建',
      'affiliate_empty_rebates': '暫無返傭記錄',
      'affiliate_copied': '邀請鏈接已複製至剪貼簿',
      'affiliate_account_info': '賬戶信息',
      'affiliate_balance': '賬戶餘額',
      'affiliate_commission': '傭金餘額',
      'affiliate_btn_transfer': '劃轉',
      'affiliate_btn_withdraw': '提現',
      'affiliate_withdraw_tip': '提現申請請聯繫在線客服或提交工單處理',
      'affiliate_stats': '邀請統計',
      'affiliate_stat_invited': '邀請人數',
      'affiliate_stat_rate': '傭金比例',
      'affiliate_stat_total': '累計傭金',
      'affiliate_stat_pending': '待確認傭金',
      'affiliate_transfer_dialog_title': '佣金劃轉',
      'affiliate_current_comm': '當前佣金餘額',
      'affiliate_transfer_amount': '劃轉金額 (元)',
      'affiliate_transfer_hint': '請輸入劃轉金額',
      'affiliate_transfer_invalid': '請輸入有效金額',
      'affiliate_transfer_success': '劃轉成功！已轉入賬戶餘額',
      'affiliate_transfer_failed': '劃轉失敗',
      'affiliate_copy_full_link': '複製完整鏈接',

      // 訂單支付與歷史
      'order_details': '訂單信息',
      'order_no': '訂單號',
      'order_original_price': '原價',
      'order_status': '狀態',
      'order_pending': '待支付',
      'order_select_pay_method': '選擇支付方式',
      'order_pay_now': '立即支付',
      'order_cancel': '取消此訂單',
      'order_cancel_confirm': '確認取消訂單',
      'order_cancel_desc': '確定要取消這筆待支付訂單嗎？',
      'order_canceled': '訂單已取消',
      'order_pay_notes': '支付說明',
      'order_note_1': '1. 請在30分鐘內完成支付，否則訂單將自動取消',
      'order_note_2': '2. 支付成功後，系統將自動為您開通服務',
      'order_note_3': '3. 如遇支付問題，請聯繫客服處理',
      'order_history': '訂單記錄',
      'order_history_empty': '暫無歷史訂單',
      'order_go_pay': '前往支付',

      // 修改密碼與工單
      'pwd_mismatch': '兩次輸入的新密碼不一致',
      'pwd_changed_success': '密碼修改成功！',
      'pwd_old_hint': '當前密碼',
      'pwd_old_required': '請輸入當前密碼',
      'pwd_new_hint': '新密碼 (至少 8 位字元)',
      'pwd_new_required': '請輸入新密碼',
      'pwd_length_min': '新密碼長度不得少於 8 位',
      'pwd_confirm_label': '確認新密碼',
      'pwd_confirm_required': '請再次輸入新密碼',
      'pwd_desc': '請輸入當前和新的密碼，確保帳號安全',
      'pwd_btn_submit': '確認修改',
      'ticket_priority_low': '優先級：低',
      'ticket_priority_med': '優先級：中',
      'ticket_priority_high': '優先級：高',
      'ticket_fill_fields': '請填寫工單標題與內容',
      'ticket_created_success': '工單創建成功！',
      'ticket_status_closed': '已關閉',
      'ticket_status_replied': '已回覆',
      'ticket_status_pending': '處理中',
      'tun_driver_missing_title': 'TUN 驅動程式未就緒',
      'tun_driver_missing_desc': '系統未檢測到 wintun.dll 虛擬網卡驅動程式，天河網絡已自動為您維持系統代理加速模式。',
      'refresh_nodes': '刷新節點',
      'sync_success': '✅ 節點與流量同步完成（共 {count} 個可用節點）',
      'sync_failed': '訂閱同步失敗，請稍後重試',
    },

    // ══════════════════════════════════════════════════════════════════════════
    // 簡體中文 (zh_CN)
    // ══════════════════════════════════════════════════════════════════════════
    'zh_CN': {
      // 底部导航栏与桌面侧边栏
      'nav_home': '加速主页',
      'nav_plan': '套餐',
      'nav_shop': '购买套餐',
      'nav_nodes': '节点状态',
      'nav_connections': '实时连接',
      'nav_traffic': '流量详情',
      'nav_affiliate': '邀请推广',
      'nav_more': '更多',
      'nav_profile': '个人中心',
      'nav_settings': '高级设置',
      'nav_docs': '文档中心',
      'offline_mode': '离线模式',
      'sign_out': '退出登录',
      'connection_status': '连接状态',
      'current_node': '当前节点',
      'switch_node': '切换节点',
      'latency': '延迟探测',
      'download': '实时下载',
      'upload': '实时上传',
      'traffic_stats': '流量统计',
      'global_network': '全球加速网络',
      'tap_to_connect': '点击一键连接',
      'status_disconnected': '未连接',
      'status_connecting': '连接中...',
      'status_connected': '已加速',
      'status_ready': '准备就绪',
      'status_establishing': '正在建立线路...',
      'status_disconnected_badge': '未连接',
      'status_connecting_badge': '连接中...',
      'status_connected_badge': '已加速',
      'tap_to_accelerate': '点击一键连接',
      'status_connected_action': '已加速',
      'traffic_used_label': '已用 {value}',
      'traffic_left_label': '剩余 {value}',
      'traffic_total_label': '总计 {value}',
      'protected_vpn': '已保护连接 (点击断开)',
      'btn_traffic_encrypted': '所有流量均经过端到端加密通道',
      'btn_account_invalid': '账号状态异常或已过期',
      'traffic_expired': '已到期',
      'traffic_warning_expired': '您的会员套餐已过期，代理连接已暂停。',
      'traffic_warning_exhausted': '可用流量已耗尽，代理服务将受限！',
      'renew_now': '立即续费',
      'tap_to_disconnect': '已保护连接 (点击断开)',
      'fast': '极速',
      'scale_best': '极佳',
      'scale_good': '良好',
      'syncing': '同步中...',
      'sync_sub': '同步订阅',
      'vip_badge': 'VIP',
      'free_badge': '免费',
      'profile_password': '修改密码',
      'copied': '已复制到剪贴板',
      'per_month': '/ 月',
      'hot_badge': '热门',

      'app_title': '天河网络',
      'service_and_traffic': '流量与服务状态',
      'details': '明细',
      'service_normal': '服务正常',
      'remaining_traffic': '剩余可用流量',
      'used_traffic': '已使用',
      'total_traffic': '总容量',
      'expire_time': '到期时间',
      'never_expire': '长期有效',
      'guest_mode': '访客模式',
      'logout': '退出登录',
      'logout_confirm_title': '确认退出',
      'logout_confirm_desc': '确定要退出当前账号吗？连接将自动中断。',
      'speed_test_done': '全节点测速完成',
      'status_disconnecting': '正在断开连接...',
      'status_error': '连接异常，请重试',
      'tap_to_connect_action': '点击加速',
      'action_connecting': '连接中...',
      'action_accelerated': '已加速',
      'mode_global': '全局模式',
      'mode_rule': '规则模式',
      'mode_tun': 'TUN模式',
      'conn_th_proto': '协议',
      'conn_th_node': '出口节点',
      'sync_subscription': '同步订阅',
      'speed_test': '节点测速',
      'select_node': '节点选择',
      'online_service': '在线客服',
      'auto_select': '⚡ 自动选择 (延迟最低)',
      'best_latency': '智能优选',

      'traffic_details': '流量明细',
      'traffic_overview': '流量使用总览',
      'traffic_remaining': '剩余流量',
      'traffic_used': '已用流量',
      'traffic_total': '总配额',
      'traffic_upload': '上行流量',
      'traffic_download': '下行流量',
      'traffic_daily_log': '每日流量消耗记录',
      'traffic_no_logs': '暂无流量使用记录',
      'traffic_rate': '倍率',
      'traffic_unlimited': '无限期',
      'traffic_reset_in': '天后重置',
      'traffic_warning_low': '您的剩余流量已低于 10%，请及时前往商城续费！',

      'node_selector_title': '线路节点选择',
      'node_select_fastest': '选最快',
      'node_batch_ping': '测速',
      'node_search_hint': '搜索节点名称、地区或协议...',
      'node_tab_favorites': '收藏',
      'node_tab_fastest': '最快',
      'node_tab_all': '全部',
      'node_tab_asia': '亚洲',
      'node_tab_western': '欧美',
      'node_tab_others': '其他',
      'node_pending_test': '待测',
      'node_testing': '测速中',
      'node_timeout': '超时',
      'node_no_favorites': '尚未收藏任何节点，点击星星即可加入收藏',
      'node_empty_fav': '您尚未收藏任何节点，点击星星即可加入',
      'node_empty_all': '暂无可用节点，请尝试同步订阅',
      'node_empty_search': '未找到符合条件的节点',
      'node_switched_fastest': '已为您切换至最快节点：',
      'auto_connect_on_node_select': '选取节点后自动连接',
      'auto_connect_on_node_select_desc': '在节点页面点击切换节点时，自动跳回主页并立即发起加速',
      'auto_connect_enabled_snack': '已开启选取节点后自动连接',
      'auto_connect_disabled_snack': '已关闭选取节点后自动连接',

      'shop_title': '套餐商城',
      'shop_subtitle': '选择适合你的订阅方案',
      'shop_tab_all': '全部',
      'shop_tab_cycle': '周期性',
      'shop_tab_one_time': '一次性',
      'shop_view_details': '查看完整权益',
      'shop_buy_now': '立即订阅',
      'shop_order_history': '订单记录',
      'shop_renewal': '续费套餐',
      'shop_cycle_month': '按月计费',
      'shop_cycle_quarter': '按季计费',
      'shop_cycle_half_year': '半年计费',
      'shop_cycle_year': '按年计费',
      'shop_payment_title': '收银台结账',
      'shop_pay_btn': '前往支付',
      'shop_confirm_title': '更换套餐确认',
      'shop_select_period': '选择订阅周期',
      'shop_coupon_title': '优惠代码 (选填)',
      'shop_coupon_hint': '输入优惠折扣码',
      'shop_order_now': '立即下单',
      'shop_cancel': '取消',
      'shop_empty': '暂无可用套餐方案',
      'shop_traffic_unit': 'GB 流量',
      'shop_reload': '重新加载',

      'more_title': '更多功能',
      'more_diagnostics': '网络诊断与延迟探测',
      'more_system_about': '系统与关于',
      'more_check_update': '检查版本更新',
      'more_current_version': '当前版本',
      'more_is_latest': '已是最新版本',
      'more_core_daemon': 'Mihomo 核心守护进程',
      'more_doh_protection': 'DoH 防封锁防护',
      'more_customer_community': '客户服务与社群',
      'more_tg_bot': '官方 Telegram 机器人',
      'more_tg_group': '官方 Telegram 社群',
      'more_routing_mode': '分流模式',
      'more_mode_rule': '规则分流 (推荐)',
      'more_mode_global': '全局代理',
      'more_mode_direct': '直连模式',
      'more_language': '界面语言 (Language)',
      'more_select_lang': '切换界面语言',
      'lang_auto': '跟随系统',
      'more_about': '关于与版本',

      'profile_title': '我的',
      'profile_used_traffic': '已用流量',
      'profile_renew_plan': '续费 / 更换套餐',
      'profile_reset_traffic': '流量重置',
      'profile_help_support': '帮助与支持',
      'profile_order_history': '订单记录',
      'profile_traffic_details': '流量明细',
      'profile_ticket': '我的工单',
      'profile_service': '在线客服',
      'profile_language': '界面语言 (Language)',
      'profile_tg_bot': '官方 Telegram 机器人',
      'profile_tg_group': '加入官方交流群',
      'profile_website': '官方网站',
      'profile_invite': '邀请管理',
      'profile_commission': '佣金余额',
      'profile_knowledge': '文档中心',
      'profile_select_lang': '切换界面语言',
      'profile_gift_card': '礼品卡 / 兑换码',
      'profile_logout': '退出账号',

      'ticket_create': '创建工单',
      'ticket_title': '工单标题',
      'ticket_content': '问题描述',
      'ticket_priority': '优先级',
      'ticket_submit': '确认提交',
      'ticket_cancel': '取消',
      'ticket_empty': '暂无工单记录',

      'invite_balance': '账户余额',
      'invite_commission': '佣金余额',
      'invite_transfer': '佣金划转',
      'invite_create_code': '生成邀请码',
      'invite_copy_success': '邀请链接已复制',

      'crisp_title': '天河网络 官方在线客服',
      'crisp_connecting': '正在连接客服系统...',
      'crisp_open_browser': '浏览器打开',

      'update_title': '发现新版本',
      'update_now': '立即更新',
      'update_later': '稍后再说',
      'update_force_tip': '此版本包含重大安全更新，必须升级后方可继续使用。',

      'confirm': '确认',
      'cancel': '取消',
      'refresh': '重新加载',
      'shop_switch_plan_hint': '您即将更换为【{name}】({period} {price})，这将覆盖您当前的使用方案。',
      'shop_more_features': '+{count} 项',
      'shop_features_privilege': '权益与特权：',
      'shop_confirm_select_plan': '确认选用方案',
      'traffic_ratio': '倍率:{rate}x',
      'traffic_up_short': '上行',
      'traffic_down_short': '下行',
      'traffic_total_short': '合计',
      'traffic_used_percent': '已用 {percent}%',
      'traffic_remaining_prefix': '剩余可用: {value}',

      // 连接视图 (Connections)
      'conn_title': '实时活动连接监控',
      'conn_subtitle_active': '活动连接数: {count} · 累计下载: {down} · 累计上传: {up}',
      'conn_subtitle_idle': '核心待机中，连接后实时呈现流量走向',
      'conn_search_hint': '搜索主机或 IP...',
      'conn_close_all': '中断全部连接',
      'conn_th_dest': '目标主机 / 端口',
      'conn_th_protocol': '协议',
      'conn_th_rule': '匹配规则',
      'conn_th_outbound': '出口节点',
      'conn_th_traffic': '传输流量 (下/上)',
      'conn_idle_placeholder': '核心待机中，点击加速后即可监控实时连接',
      'conn_empty_active': '暂无活动网络连接',
      'conn_no_active': '暂无活动网络连接',
      'conn_empty_search': '无匹配的连接记录',
      'conn_closed_all_msg': '已中断所有活动代理连接',
      'conn_close_error': '操作失败: {error}',
      'no_notice': '暂无系统公告',

      // 模式切换与加速按钮
      'mode_direct': '直连模式',

      // 流量统计明细标签

      // 桌面端快捷提示与对话框
      'tooltip_lang': '多语言切换',
      'tooltip_diag': '网络诊断',
      'tooltip_checkin': '每日签到',
      'tooltip_service': '在线客服',
      'tooltip_notice': '最新公告',
      'admin_required_title': '需要系统管理员权限',
      'admin_required_desc': 'TUN 虚拟网卡模式需要以系统管理员权限运行，以安装与接管 Wintun 驱动网卡。\n\n点击下方按钮将为您提权并以管理员身分重新启动天河网络客户端。',
      'admin_restart_btn': '以管理员身份重启',
      'sub_synced_success': '节点订阅同步完成',
      'loading_nodes': '正在加载专属节点...',

      // 开机自启与更新
      'more_auto_start': '开机自动启动',
      'auto_start_enabled': '已启用',
      'auto_start_disabled': '已停用',
      'auto_start_snack_on': '已开启开机自启',
      'auto_start_snack_off': '已关闭开机自启',
      'check_update_failed': '检查更新失败',
      'window_title': '天河网络 - 全球极速安全连接客户端',
      'splash_slogan': '安全 · 稳定 · 极速隧道',
      'splash_init_channel': '正在建立安全连接通道...',
      'splash_resolving_doh': '正在解析防封锁线路 (DoH)...',
      'splash_checking_version': '正在检查客户端版本...',
      'splash_verifying_auth': '正在验证账号状态...',
      'splash_init_failed': '初始化失败，请检查网络连接',
      'splash_retry_conn': '重试连接',

      // 网络诊断与弹窗
      'diag_title': '网络与连通性诊断',
      'diag_local_net': '本机网络连接',
      'diag_local_net_desc': '检测本机网络适配器与 IP 连通状态',
      'diag_api': 'V2Board 后台 API',
      'diag_api_desc': '检测机场服务器连通性与响应延迟',
      'diag_doh': 'DNS 解析 (DoH)',
      'diag_doh_desc': '检测防污染 DoH / 系统 DNS 解析速度',
      'diag_core': 'Mihomo 核心与 TUN 界面',
      'diag_core_desc': '检测系统级代理通道运行状态',
      'diag_cross_border': '境外目标网站 (Google/CF)',
      'diag_cross_border_desc': '检测跨境连线通畅度与 TLS 握手延迟',
      'diag_testing': '检测中',
      'diag_retest': '重新检测',
      'diag_local_nic': '本地网络接口',
      'diag_sys_proxy': '系统代理服务',
      'diag_core_controller': 'Mihomo 内核控制器',
      'diag_doh_anti': 'DNS 解析防封锁',
      'done': '完成',
      'checkin_thanks': '感谢您使用天河网络客户端！',
      'checkin_credited': '本日已为您自动签到并累计免费防护时长。',
      'no_announcements': '暂无最新公告',
      'local_user': '本机用户',

      // 更新弹窗
      'update_force_title': '重要版本强制更新',
      'update_new_title': '发现新版本',
      'update_changelog_title': '更新日志：',
      'update_default_changelog': '稳定性提升与问题修复。',
      'update_remind_later': '稍后提醒',
      'update_now_overwrite': '立即覆盖更新',
      'update_now_upgrade': '立即升级',
      'update_preparing': '正在准备下载...',
      'update_no_url': '尚未提供该平台的安装包下载地址',

      // 公告与登录
      'notice_coupon_prefix': '老客户优惠码: ',
      'notice_coupon_copied': '已复制优惠码到剪贴板',
      'copy_btn': '复制',
      'i_understand': '我知道了',
      'login_title': '登录您的账号，畅享全球高速节点',
      'login_btn': '立即登录',
      'login_no_account': '还没有账号？',
      'login_register_now': '立即注册',
      'login_forgot_pwd': '忘记密码？',
      'email_hint': '邮箱账号或完整邮箱',
      'pwd_hint': '请输入密码',
      'register_title': '建立新账号',
      'register_desc': '注册天河网络，开启安全极速通道',
      'register_btn': '建立账号并登录',
      'back_to_login': '返回登录',
      'email_code_hint': '邮箱验证码',
      'send_code': '发送',
      'pwd_set_hint': '请设置密码 (至少 6 位)',
      'pwd_confirm_hint': '再次输入密码',
      'invite_code_optional': '邀请码 (选填)',
      'reset_pwd_title': '重置账号密码',
      'reset_pwd_desc': '验证邮箱后即可设置新密码',
      'reset_pwd_btn': '重置密码并返回',

      // 加速按钮与连线提示
      'syncing_routes': '正在同步专属线路...',
      'node_unselected': '尚未选取节点',
      'tap_to_select_node': '点击此处展开节点列表',
      'select_node_hint': '请先选取一个连线节点',
      'order_failed_prefix': '下单失败',

      // 邀请推广 (Affiliate)
      'affiliate_title': '邀请管理',
      'affiliate_codes_tab': '邀请码列表',
      'affiliate_rebates_tab': '返佣记录',
      'affiliate_create_code': '创建邀请码',
      'affiliate_code_created': '成功创建新的邀请码！',
      'affiliate_create_failed': '创建失败',
      'affiliate_empty_codes': '暂无邀请码，点击上方按钮创建',
      'affiliate_empty_rebates': '暂无返佣记录',
      'affiliate_copied': '邀请链接已复制至剪贴板',
      'affiliate_account_info': '账户信息',
      'affiliate_balance': '账户余额',
      'affiliate_commission': '佣金余额',
      'affiliate_btn_transfer': '划转',
      'affiliate_btn_withdraw': '提现',
      'affiliate_withdraw_tip': '提现申请请联系在线客服或提交工单处理',
      'affiliate_stats': '邀请统计',
      'affiliate_stat_invited': '邀请人数',
      'affiliate_stat_rate': '佣金比例',
      'affiliate_stat_total': '累计佣金',
      'affiliate_stat_pending': '待确认佣金',
      'affiliate_transfer_dialog_title': '佣金划转',
      'affiliate_current_comm': '当前佣金余额',
      'affiliate_transfer_amount': '划转金额 (元)',
      'affiliate_transfer_hint': '请输入划转金额',
      'affiliate_transfer_invalid': '请输入有效金额',
      'affiliate_transfer_success': '划转成功！已转入账户余额',
      'affiliate_transfer_failed': '划转失败',
      'affiliate_copy_full_link': '复制完整链接',

      // 订单支付与历史
      'order_details': '订单信息',
      'order_no': '订单号',
      'order_original_price': '原价',
      'order_status': '状态',
      'order_pending': '待支付',
      'order_select_pay_method': '选择支付方式',
      'order_pay_now': '立即支付',
      'order_cancel': '取消此订单',
      'order_cancel_confirm': '确认取消订单',
      'order_cancel_desc': '确定要取消这笔待支付订单吗？',
      'order_canceled': '订单已取消',
      'order_pay_notes': '支付说明',
      'order_note_1': '1. 请在30分钟内完成支付，否则订单将自动取消',
      'order_note_2': '2. 支付成功后，系统将自动为您开通服务',
      'order_note_3': '3. 如遇支付问题，请联系客服处理',
      'order_history': '订单记录',
      'order_history_empty': '暂无历史订单',
      'order_go_pay': '前往支付',

      // 修改密码与工单
      'pwd_mismatch': '两次输入的新密码不一致',
      'pwd_changed_success': '密码修改成功！',
      'pwd_old_hint': '当前密码',
      'pwd_old_required': '请输入当前密码',
      'pwd_new_hint': '新密码 (至少 8 位字符)',
      'pwd_new_required': '请输入新密码',
      'pwd_length_min': '新密码长度不得少于 8 位',
      'pwd_confirm_label': '确认新密码',
      'pwd_confirm_required': '请再次输入新密码',
      'pwd_desc': '请输入当前和新的密码，确保账号安全',
      'pwd_btn_submit': '确认修改',
      'ticket_priority_low': '优先级：低',
      'ticket_priority_med': '优先级：中',
      'ticket_priority_high': '优先级：高',
      'ticket_fill_fields': '请填写工单标题与内容',
      'ticket_created_success': '工单创建成功！',
      'ticket_status_closed': '已关闭',
      'ticket_status_replied': '已回复',
      'ticket_status_pending': '处理中',
      'tun_driver_missing_title': 'TUN 驱动程序未就绪',
      'tun_driver_missing_desc': '系统未检测到 wintun.dll 虚拟网卡驱动程序，天河网络已自动为您维持系统代理加速模式。',
      'refresh_nodes': '刷新节点',
      'sync_success': '✅ 节点与流量同步完成（共 {count} 个可用节点）',
      'sync_failed': '订阅同步失败，请稍后重试',
    },

    // ══════════════════════════════════════════════════════════════════════════
    // English (en)
    // ══════════════════════════════════════════════════════════════════════════
    'en': {
      // Bottom Navigation and Desktop Sidebar
      'nav_home': 'Home',
      'nav_plan': 'Plans',
      'nav_shop': 'Store',
      'nav_nodes': 'Nodes',
      'nav_connections': 'Connections',
      'nav_traffic': 'Traffic',
      'nav_affiliate': 'Affiliate',
      'nav_more': 'More',
      'nav_profile': 'Profile',
      'nav_settings': 'Settings',
      'nav_docs': 'Documentation',
      'offline_mode': 'Offline Mode',
      'sign_out': 'Sign Out',
      'connection_status': 'Connection Status',
      'current_node': 'Current Node',
      'switch_node': 'Switch Node',
      'latency': 'Latency',
      'download': 'Download',
      'upload': 'Upload',
      'traffic_stats': 'Traffic Stats',
      'global_network': 'Global Network',
      'tap_to_connect': 'Tap to Connect',
      'status_disconnected': 'Disconnected',
      'status_connecting': 'Connecting...',
      'status_connected': 'Accelerated',
      'status_ready': 'Ready',
      'status_establishing': 'Connecting line...',
      'status_disconnected_badge': 'Disconnected',
      'status_connecting_badge': 'Connecting...',
      'status_connected_badge': 'Accelerated',
      'tap_to_accelerate': 'Tap to Connect',
      'status_connected_action': 'Accelerated',
      'traffic_used_label': 'Used {value}',
      'traffic_left_label': 'Left {value}',
      'traffic_total_label': 'Total {value}',
      'protected_vpn': 'Connected (Tap to Disconnect)',
      'btn_traffic_encrypted': 'All traffic routed via end-to-end encrypted tunnels',
      'btn_account_invalid': 'Account invalid or expired, please recharge',
      'traffic_expired': 'Expired',
      'traffic_warning_expired': 'Your plan has expired, proxy paused.',
      'traffic_warning_exhausted': 'Traffic quota exhausted, proxy limited!',
      'renew_now': 'Renew Now',
      'tap_to_disconnect': 'Connected (Tap to Disconnect)',
      'fast': 'Fast',
      'scale_best': 'Best',
      'scale_good': 'Good',
      'syncing': 'Syncing...',
      'sync_sub': 'Sync Sub',
      'vip_badge': 'VIP',
      'free_badge': 'Free',
      'profile_password': 'Change Password',
      'copied': 'Copied to clipboard',
      'per_month': '/ mo',
      'hot_badge': 'HOT',

      'app_title': 'Tianhe Network',
      'service_and_traffic': 'Traffic & Service Status',
      'details': 'Details',
      'service_normal': 'Operational',
      'remaining_traffic': 'Remaining Available',
      'used_traffic': 'Used',
      'total_traffic': 'Total Quota',
      'expire_time': 'Expires',
      'never_expire': 'Lifetime Valid',
      'guest_mode': 'Guest Mode',
      'logout': 'Sign Out',
      'logout_confirm_title': 'Confirm Sign Out',
      'logout_confirm_desc': 'Are you sure you want to sign out? VPN will be disconnected.',
      'speed_test_done': 'Latency test completed',
      'status_disconnecting': 'Disconnecting...',
      'status_error': 'Connection Error, Tap to Retry',
      'tap_to_connect_action': 'Connect',
      'action_connecting': 'Connecting...',
      'action_accelerated': 'Accelerated',
      'mode_global': 'Global',
      'mode_rule': 'Rule',
      'mode_tun': 'TUN Mode',
      'conn_th_proto': 'Network',
      'conn_th_node': 'Outbound',
      'sync_subscription': 'Sync Subscription',
      'speed_test': 'Latency Ping',
      'select_node': 'Node Selection',
      'online_service': 'Live Chat',
      'auto_select': '⚡ Auto Select (Lowest Ping)',
      'best_latency': 'Smart Optimal',

      'traffic_details': 'Traffic Details',
      'traffic_overview': 'Traffic Usage Overview',
      'traffic_remaining': 'Remaining',
      'traffic_used': 'Used Quota',
      'traffic_total': 'Total Quota',
      'traffic_upload': 'Upload',
      'traffic_download': 'Download',
      'traffic_daily_log': 'Daily Traffic Usage History',
      'traffic_no_logs': 'No traffic records found',
      'traffic_rate': 'Multiplier',
      'traffic_unlimited': 'Never Expires',
      'traffic_reset_in': 'Days to Reset',
      'traffic_warning_low': 'Remaining traffic is below 10%, please renew in store!',

      'node_selector_title': 'Server Selection',
      'node_select_fastest': 'Fastest',
      'node_batch_ping': 'Ping',
      'node_search_hint': 'Search node, region or protocol...',
      'node_tab_favorites': 'Favorites',
      'node_tab_fastest': 'Fastest',
      'node_tab_all': 'All',
      'node_tab_asia': 'Asia',
      'node_tab_western': 'US & EU',
      'node_tab_others': 'Others',
      'node_pending_test': 'Untested',
      'node_testing': 'Testing...',
      'node_timeout': 'Timeout',
      'node_no_favorites': 'No favorite nodes yet. Tap the star to bookmark',
      'node_empty_fav': 'No favorite nodes yet. Tap the star to add',
      'node_empty_all': 'No servers available. Please sync subscription',
      'node_empty_search': 'No matching servers found',
      'node_switched_fastest': 'Switched to fastest server: ',
      'auto_connect_on_node_select': 'Auto Connect on Node Select',
      'auto_connect_on_node_select_desc': 'Return to home and connect immediately when a node is selected',
      'auto_connect_enabled_snack': 'Auto connect on node select enabled',
      'auto_connect_disabled_snack': 'Auto connect on node select disabled',

      'shop_title': 'Plans Store',
      'shop_subtitle': 'Choose the subscription plan that fits your needs',
      'shop_tab_all': 'All',
      'shop_tab_cycle': 'Recurring',
      'shop_tab_one_time': 'One-Time',
      'shop_view_details': 'View Full Benefits',
      'shop_buy_now': 'Subscribe Now',
      'shop_order_history': 'Order History',
      'shop_renewal': 'Renew Plan',
      'shop_cycle_month': 'Monthly',
      'shop_cycle_quarter': 'Quarterly',
      'shop_cycle_half_year': 'Semi-Annual',
      'shop_cycle_year': 'Annual',
      'shop_payment_title': 'Checkout',
      'shop_pay_btn': 'Proceed to Pay',
      'shop_confirm_title': 'Confirm Plan Change',
      'shop_select_period': 'Select Billing Cycle',
      'shop_coupon_title': 'Coupon Code (Optional)',
      'shop_coupon_hint': 'Enter coupon code',
      'shop_order_now': 'Order Now',
      'shop_cancel': 'Cancel',
      'shop_empty': 'No subscription plans available',
      'shop_traffic_unit': 'GB Traffic',
      'shop_reload': 'Reload',

      'more_title': 'More Features',
      'more_diagnostics': 'Network Diagnostics & Latency',
      'more_system_about': 'System & About',
      'more_check_update': 'Check for Updates',
      'more_current_version': 'Current Version',
      'more_is_latest': 'Up to Date',
      'more_core_daemon': 'Mihomo Core Daemon',
      'more_doh_protection': 'Anti-Censorship DoH Protection',
      'more_customer_community': 'Customer Service & Community',
      'more_tg_bot': 'Official Telegram Bot',
      'more_tg_group': 'Official Telegram Community',
      'more_routing_mode': 'Routing Mode',
      'more_mode_rule': 'Rule Routing (Recommended)',
      'more_mode_global': 'Global Proxy',
      'more_mode_direct': 'Direct',
      'more_language': 'Language',
      'more_select_lang': 'Switch Language',
      'lang_auto': 'Follow System',
      'more_about': 'About & Version',

      'profile_title': 'Profile',
      'profile_used_traffic': 'Used Traffic',
      'profile_renew_plan': 'Renew / Change Plan',
      'profile_reset_traffic': 'Reset Traffic',
      'profile_help_support': 'Help & Support',
      'profile_order_history': 'Order History',
      'profile_traffic_details': 'Traffic Details',
      'profile_ticket': 'My Tickets',
      'profile_service': 'Online Support',
      'profile_language': 'Language',
      'profile_tg_bot': 'Official Telegram Bot',
      'profile_tg_group': 'Join Official Group',
      'profile_website': 'Official Website',
      'profile_invite': 'Affiliates & Invites',
      'profile_commission': 'Commission Balance',
      'profile_knowledge': 'Documentation',
      'profile_select_lang': 'Switch Language',
      'profile_gift_card': 'Gift Card / Redeem Code',
      'profile_logout': 'Sign Out',

      'ticket_create': 'New Ticket',
      'ticket_title': 'Subject',
      'ticket_content': 'Description',
      'ticket_priority': 'Priority',
      'ticket_submit': 'Submit',
      'ticket_cancel': 'Cancel',
      'ticket_empty': 'No tickets found',

      'invite_balance': 'Account Balance',
      'invite_commission': 'Commission Balance',
      'invite_transfer': 'Transfer Funds',
      'invite_create_code': 'Generate Invite Code',
      'invite_copy_success': 'Referral link copied',

      'crisp_title': 'Tianhe Live Support',
      'crisp_connecting': 'Connecting to support...',
      'crisp_open_browser': 'Open in Browser',

      'update_title': 'New Version Available',
      'update_now': 'Update Now',
      'update_later': 'Later',
      'update_force_tip': 'This update contains critical security fixes and is mandatory.',

      'confirm': 'Confirm',
      'cancel': 'Cancel',
      'refresh': 'Refresh',
      'shop_switch_plan_hint': 'You are about to switch to [{name}] ({period} {price}), which will overwrite your current plan.',
      'shop_more_features': '+{count} more',
      'shop_features_privilege': 'Features & Privileges:',
      'shop_confirm_select_plan': 'Confirm Selected Plan',
      'traffic_ratio': 'Rate:{rate}x',
      'traffic_up_short': 'Upload',
      'traffic_down_short': 'Download',
      'traffic_total_short': 'Total',
      'traffic_used_percent': 'Used {percent}%',
      'traffic_remaining_prefix': 'Remaining: {value}',

      // Connections View
      'conn_title': 'Live Connections',
      'conn_subtitle_active': 'Active: {count} · Total Down: {down} · Total Up: {up}',
      'conn_subtitle_idle': 'Core is idle. Traffic routes will appear after connecting.',
      'conn_search_hint': 'Search host or IP...',
      'conn_close_all': 'Close All',
      'conn_th_dest': 'Destination',
      'conn_th_protocol': 'Network',
      'conn_th_rule': 'Rule',
      'conn_th_outbound': 'Outbound',
      'conn_th_traffic': 'Traffic (Down/Up)',
      'conn_idle_placeholder': 'Core idle. Connect to monitor live traffic.',
      'conn_empty_active': 'No active connections',
      'conn_no_active': 'No active connections',
      'conn_empty_search': 'No matching connections found',
      'conn_closed_all_msg': 'All active proxy connections closed',
      'conn_close_error': 'Operation failed: {error}',
      'no_notice': 'No system announcements',

      // Mode Switcher & Acceleration Button
      'mode_direct': 'Direct',

      // Traffic Subcard Detail Labels

      // Desktop Tooltips & Dialogs
      'tooltip_lang': 'Switch Language',
      'tooltip_diag': 'Network Diagnostics',
      'tooltip_checkin': 'Daily Check-In',
      'tooltip_service': 'Live Support',
      'tooltip_notice': 'Announcements',
      'admin_required_title': 'Administrator Privileges Required',
      'admin_required_desc': 'TUN mode requires administrator privileges to configure the Wintun adapter.\n\nClick below to elevate and restart Tianhe Network client as administrator.',
      'admin_restart_btn': 'Restart as Administrator',
      'sub_synced_success': 'Subscription synced successfully',
      'loading_nodes': 'Loading servers...',

      // Auto Start & Updates
      'more_auto_start': 'Launch on Boot',
      'auto_start_enabled': 'Enabled',
      'auto_start_disabled': 'Disabled',
      'auto_start_snack_on': 'Launch on boot enabled',
      'auto_start_snack_off': 'Launch on boot disabled',
      'check_update_failed': 'Failed to check for updates',
      'window_title': 'Tianhe Network - Global Secure Acceleration Client',
      'splash_slogan': 'Secure · Stable · Ultra-Fast Tunnel',
      'splash_init_channel': 'Establishing secure tunnel...',
      'splash_resolving_doh': 'Resolving anti-censorship DoH routes...',
      'splash_checking_version': 'Checking client version...',
      'splash_verifying_auth': 'Verifying account status...',
      'splash_init_failed': 'Initialization failed, check your network',
      'splash_retry_conn': 'Retry Connection',

      // Diagnostics & Dialogs
      'diag_title': 'Network & Connectivity Diagnostics',
      'diag_local_net': 'Local Network Connection',
      'diag_local_net_desc': 'Check local network adapter and IP status',
      'diag_api': 'V2Board Backend API',
      'diag_api_desc': 'Check API server latency and reachability',
      'diag_doh': 'DNS Resolution (DoH)',
      'diag_doh_desc': 'Check anti-censorship DoH and DNS speed',
      'diag_core': 'Mihomo Core & TUN Interface',
      'diag_core_desc': 'Check system proxy tunnel running status',
      'diag_cross_border': 'Global Target Sites (Google/CF)',
      'diag_cross_border_desc': 'Check cross-border connectivity & TLS handshake',
      'diag_testing': 'Testing...',
      'diag_retest': 'Re-test',
      'diag_local_nic': 'Local Network Adapter',
      'diag_sys_proxy': 'System Proxy Service',
      'diag_core_controller': 'Mihomo Core Controller',
      'diag_doh_anti': 'Anti-Censorship DNS',
      'done': 'Done',
      'checkin_thanks': 'Thank you for using Tianhe Network Client!',
      'checkin_credited': 'Daily check-in complete. Free bonus protection duration added.',
      'no_announcements': 'No new announcements',
      'local_user': 'Local User',

      // Update Dialog
      'update_force_title': 'Mandatory Update',
      'update_new_title': 'New Version Available',
      'update_changelog_title': 'Changelog:',
      'update_default_changelog': 'Stability improvements and bug fixes.',
      'update_remind_later': 'Remind Later',
      'update_now_overwrite': 'Update & Overwrite Now',
      'update_now_upgrade': 'Upgrade Now',
      'update_preparing': 'Preparing download...',
      'update_no_url': 'Download package not available for this platform',

      // Notice & Auth
      'notice_coupon_prefix': 'Coupon Code: ',
      'notice_coupon_copied': 'Coupon code copied to clipboard',
      'copy_btn': 'Copy',
      'i_understand': 'Got It',
      'login_title': 'Sign in to your account and enjoy global high-speed nodes',
      'login_btn': 'Sign In',
      'login_no_account': 'Don\'t have an account?',
      'login_register_now': 'Register Now',
      'login_forgot_pwd': 'Forgot Password?',
      'email_hint': 'Email address',
      'pwd_hint': 'Enter your password',
      'register_title': 'Create New Account',
      'register_desc': 'Register with Tianhe Network for secure fast access',
      'register_btn': 'Create Account & Sign In',
      'back_to_login': 'Back to Sign In',
      'email_code_hint': 'Verification Code',
      'send_code': 'Send',
      'pwd_set_hint': 'Set Password (at least 6 characters)',
      'pwd_confirm_hint': 'Confirm Password',
      'invite_code_optional': 'Invite Code (Optional)',
      'reset_pwd_title': 'Reset Password',
      'reset_pwd_desc': 'Verify your email to set a new password',

      // Connection button and hints
      'syncing_routes': 'Syncing dedicated routes...',
      'node_unselected': 'No node selected',
      'tap_to_select_node': 'Tap here to open server list',
      'select_node_hint': 'Please select a server node first',
      'order_failed_prefix': 'Order creation failed',

      // Affiliate & Referral
      'affiliate_title': 'Affiliate & Referral',
      'affiliate_codes_tab': 'Referral Codes',
      'affiliate_rebates_tab': 'Commission History',
      'affiliate_create_code': 'Generate Code',
      'affiliate_code_created': 'Successfully generated new referral code!',
      'affiliate_create_failed': 'Failed to generate code',
      'affiliate_empty_codes': 'No referral codes yet, click button above to generate',
      'affiliate_empty_rebates': 'No commission records yet',
      'affiliate_copied': 'Referral link copied to clipboard',
      'affiliate_account_info': 'Account Information',
      'affiliate_balance': 'Account Balance',
      'affiliate_commission': 'Commission Balance',
      'affiliate_btn_transfer': 'Transfer',
      'affiliate_btn_withdraw': 'Withdraw',
      'affiliate_withdraw_tip': 'Please contact live support or submit a ticket for withdrawal',
      'affiliate_stats': 'Referral Statistics',
      'affiliate_stat_invited': 'Referred Users',
      'affiliate_stat_rate': 'Commission Rate',
      'affiliate_stat_total': 'Total Commission',
      'affiliate_stat_pending': 'Pending Commission',
      'affiliate_transfer_dialog_title': 'Transfer Commission',
      'affiliate_current_comm': 'Current Commission Balance',
      'affiliate_transfer_amount': 'Transfer Amount (¥)',
      'affiliate_transfer_hint': 'Enter transfer amount',
      'affiliate_transfer_invalid': 'Please enter a valid amount',
      'affiliate_transfer_success': 'Transfer successful! Credited to account balance',
      'affiliate_transfer_failed': 'Transfer failed',
      'affiliate_copy_full_link': 'Copy Full Link',

      // Order Payment & History
      'order_details': 'Order Details',
      'order_no': 'Order No.',
      'order_original_price': 'Amount',
      'order_status': 'Status',
      'order_pending': 'Pending Payment',
      'order_select_pay_method': 'Select Payment Method',
      'order_pay_now': 'Pay Now',
      'order_cancel': 'Cancel Order',
      'order_cancel_confirm': 'Cancel Order Confirmation',
      'order_cancel_desc': 'Are you sure you want to cancel this pending order?',
      'order_canceled': 'Order has been cancelled',
      'order_pay_notes': 'Payment Instructions',
      'order_note_1': '1. Please complete payment within 30 minutes, or order will be cancelled',
      'order_note_2': '2. Service will be provisioned automatically once payment succeeds',
      'order_note_3': '3. Contact support if you encounter any payment issues',
      'order_history': 'Order History',
      'order_history_empty': 'No orders found',
      'order_go_pay': 'Pay Now',

      // Change Password & Tickets
      'pwd_mismatch': 'New passwords do not match',
      'pwd_changed_success': 'Password changed successfully!',
      'pwd_old_hint': 'Current Password',
      'pwd_old_required': 'Please enter current password',
      'pwd_new_hint': 'New Password (at least 8 chars)',
      'pwd_new_required': 'Please enter new password',
      'pwd_length_min': 'Password must be at least 8 characters',
      'pwd_confirm_label': 'Confirm New Password',
      'pwd_confirm_required': 'Please re-enter new password',
      'pwd_desc': 'Enter current and new passwords to secure your account',
      'pwd_btn_submit': 'Update Password',
      'ticket_priority_low': 'Priority: Low',
      'ticket_priority_med': 'Priority: Medium',
      'ticket_priority_high': 'Priority: High',
      'ticket_fill_fields': 'Please fill in ticket subject and description',
      'ticket_created_success': 'Ticket submitted successfully!',
      'ticket_status_closed': 'Closed',
      'ticket_status_replied': 'Replied',
      'ticket_status_pending': 'Processing',
      'tun_driver_missing_title': 'TUN Driver Not Ready',
      'tun_driver_missing_desc': 'wintun.dll was not found. Tianhe Network has automatically kept System Proxy mode.',
      'refresh_nodes': 'Refresh Nodes',
      'sync_success': '✅ Sync complete ({count} available nodes)',
      'sync_failed': 'Subscription sync failed, please try again later',
    },

    // ══════════════════════════════════════════════════════════════════════════
    // 日本語 (ja)
    // ══════════════════════════════════════════════════════════════════════════
    'ja': {
      // ナビゲーションバーとデスクトップサイドバー
      'nav_home': '加速ホーム',
      'nav_plan': 'プラン',
      'nav_shop': 'プラン購入',
      'nav_nodes': 'ノード状態',
      'nav_connections': '接続状況',
      'nav_traffic': 'トラフィック',
      'nav_affiliate': '招待プログラム',
      'nav_more': 'その他',
      'nav_profile': 'マイページ',
      'nav_settings': '詳細設定',
      'nav_docs': 'ドキュメント',
      'offline_mode': 'オフライン',
      'sign_out': 'ログアウト',
      'connection_status': '接続状況',
      'current_node': '現在のノード',
      'switch_node': 'ノード切替',
      'latency': 'レイテンシ',
      'download': 'ダウンロード',
      'upload': 'アップロード',
      'traffic_stats': '通信量統計',
      'global_network': 'グローバルネットワーク',
      'tap_to_connect': 'タップして接続',
      'status_disconnected': '未接続',
      'status_connecting': '接続中...',
      'status_connected': '加速中',
      'status_ready': '準備完了',
      'status_establishing': '回線確立中...',
      'status_disconnected_badge': '未接続',
      'status_connecting_badge': '接続中...',
      'status_connected_badge': '加速中',
      'tap_to_accelerate': 'タップして接続',
      'status_connected_action': '接続済み',
      'traffic_used_label': '使用済み {value}',
      'traffic_left_label': '残り {value}',
      'traffic_total_label': '合計 {value}',
      'protected_vpn': '接続中 (タップして切断)',
      'btn_traffic_encrypted': 'すべての通信はエンドツーエンド暗号化トンネルを経由します',
      'btn_account_invalid': 'アカウントが無効または期限切れです',
      'traffic_expired': '期限切れ',
      'traffic_warning_expired': 'プランが期限切れです。プロキシが一時停止しました。',
      'traffic_warning_exhausted': '利用可能トラフィックを使い果たしました！',
      'renew_now': '今すぐ更新',
      'tap_to_disconnect': '接続中 (タップして切断)',
      'fast': '高速',
      'scale_best': '極上',
      'scale_good': '良好',
      'syncing': '同期中...',
      'sync_sub': '購読同期',
      'vip_badge': 'VIP',
      'free_badge': '無料',
      'profile_password': 'パスワード変更',
      'copied': 'クリップボードにコピーしました',
      'per_month': '/ 月',
      'hot_badge': '人気',

      'app_title': '天河ネットワーク',
      'service_and_traffic': '通信量とサービス状態',
      'details': '詳細',
      'service_normal': '正常稼働中',
      'remaining_traffic': '残り利用可能通信量',
      'used_traffic': '使用済み',
      'total_traffic': '総容量',
      'expire_time': '有効期限',
      'never_expire': '無期限',
      'guest_mode': 'ゲストモード',
      'logout': 'ログアウト',
      'logout_confirm_title': 'ログアウトの確認',
      'logout_confirm_desc': '現在のアカウントからログアウトしますか？VPN接続は切断されます。',
      'speed_test_done': '全ノードの測定が完了しました',
      'status_disconnecting': '切断中...',
      'status_error': '接続エラー、再試行してください',
      'tap_to_connect_action': '加速開始',
      'action_connecting': '接続中...',
      'action_accelerated': '加速中',
      'mode_global': 'グローバル',
      'mode_rule': 'ルール',
      'mode_tun': 'TUNモード',
      'conn_th_proto': 'プロトコル',
      'conn_th_node': '送信先ノード',
      'sync_subscription': '購読を同期',
      'speed_test': 'ノード測定',
      'select_node': 'ノード選択',
      'online_service': 'オンラインサポート',
      'auto_select': '⚡ 自動選択 (最低遅延)',
      'best_latency': 'スマート最適',

      'traffic_details': '通信量明細',
      'traffic_overview': '通信量使用状況',
      'traffic_remaining': '残り通信量',
      'traffic_used': '使用済み',
      'traffic_total': '総容量',
      'traffic_upload': 'アップロード',
      'traffic_download': 'ダウンロード',
      'traffic_daily_log': '日別通信量履歴',
      'traffic_no_logs': '通信量記録がありません',
      'traffic_rate': '倍率',
      'traffic_unlimited': '無制限',
      'traffic_reset_in': '日後にリセット',
      'traffic_warning_low': '残り通信量が10％未満です。ショップで更新してください！',

      'node_selector_title': 'サーバー選択',
      'node_select_fastest': '最速を選択',
      'node_batch_ping': '測定',
      'node_search_hint': 'ノード名、地域、プロトコルを検索...',
      'node_tab_favorites': 'お気に入り',
      'node_tab_fastest': '最速',
      'node_tab_all': 'すべて',
      'node_tab_asia': 'アジア',
      'node_tab_western': '欧米',
      'node_tab_others': 'その他',
      'node_pending_test': '未測定',
      'node_testing': '測定中',
      'node_timeout': 'タイムアウト',
      'node_no_favorites': 'お気に入りのノードがありません。★をタップして追加',
      'node_empty_fav': 'お気に入りのノードがありません。★をタップして追加',
      'node_empty_all': '利用可能なノードがありません。サブスクリプションを同期してください',
      'node_empty_search': '条件に一致するノードが見つかりません',
      'node_switched_fastest': '最速ノードに切り替えました：',
      'auto_connect_on_node_select': 'ノード選択時に自動接続',
      'auto_connect_on_node_select_desc': 'ノード選択時、自動でホームに戻り即座に接続します',
      'auto_connect_enabled_snack': 'ノード選択時の自動接続を有効にしました',
      'auto_connect_disabled_snack': 'ノード選択時の自動接続を無効にしました',

      'shop_title': 'プランショップ',
      'shop_subtitle': '最適なサブスクリプションプランを選択',
      'shop_tab_all': 'すべて',
      'shop_tab_cycle': '定期購入',
      'shop_tab_one_time': '買い切り',
      'shop_view_details': '特典をすべて見る',
      'shop_buy_now': '今すぐ購入',
      'shop_order_history': '注文履歴',
      'shop_renewal': 'プラン更新',
      'shop_cycle_month': '月額',
      'shop_cycle_quarter': '四半期',
      'shop_cycle_half_year': '半年',
      'shop_cycle_year': '年額',
      'shop_payment_title': 'お会計',
      'shop_pay_btn': '支払いへ進む',
      'shop_confirm_title': 'プラン変更の確認',
      'shop_select_period': '請求サイクルを選択',
      'shop_coupon_title': 'クーポンコード (任意)',
      'shop_coupon_hint': 'クーポンコードを入力',
      'shop_order_now': '今すぐ注文',
      'shop_cancel': 'キャンセル',
      'shop_empty': '利用可能なプランがありません',
      'shop_traffic_unit': 'GB 通信量',
      'shop_reload': '再読み込み',

      'more_title': 'その他の機能',
      'more_diagnostics': 'ネットワーク診断・遅延測定',
      'more_system_about': 'システム・情報',
      'more_check_update': 'アップデートを確認',
      'more_current_version': '現在のバージョン',
      'more_is_latest': '最新バージョンです',
      'more_core_daemon': 'Mihomo コアデーモン',
      'more_doh_protection': 'DoH 検閲回避保護',
      'more_customer_community': 'カスタマーサービス＆コミュニティ',
      'more_tg_bot': '公式 Telegram ボット',
      'more_tg_group': '公式 Telegram コミュニティ',
      'more_routing_mode': 'ルーティングモード',
      'more_mode_rule': 'ルール振り分け (推奨)',
      'more_mode_global': 'グローバルプロキシ',
      'more_mode_direct': 'ダイレクト',
      'more_language': '言語設定 (Language)',
      'more_select_lang': '言語を切り替える',
      'lang_auto': 'システムに従う',
      'more_about': 'バージョン情報',

      'profile_title': 'マイページ',
      'profile_used_traffic': '使用済み通信量',
      'profile_renew_plan': 'プラン更新・変更',
      'profile_reset_traffic': '通信量リセット',
      'profile_help_support': 'ヘルプ＆サポート',
      'profile_order_history': '注文履歴',
      'profile_traffic_details': '通信量明細',
      'profile_ticket': 'マイチケット',
      'profile_service': 'オンラインサポート',
      'profile_language': '言語設定 (Language)',
      'profile_tg_bot': '公式 Telegram ボット',
      'profile_tg_group': '公式グループに参加',
      'profile_website': '公式サイト',
      'profile_invite': '招待管理',
      'profile_commission': '報酬残高',
      'profile_knowledge': 'ドキュメント',
      'profile_select_lang': '言語の切り替え',
      'profile_gift_card': 'ギフトカード・引換コード',
      'profile_logout': 'ログアウト',

      'ticket_create': '新規チケット',
      'ticket_title': '件名',
      'ticket_content': '詳細',
      'ticket_priority': '優先度',
      'ticket_submit': '送信',
      'ticket_cancel': 'キャンセル',
      'ticket_empty': 'チケットがありません',

      'invite_balance': '口座残高',
      'invite_commission': '報酬残高',
      'invite_transfer': '残高振替',
      'invite_create_code': '招待コード生成',
      'invite_copy_success': '招待リンクをコピーしました',

      'crisp_title': '天河オンラインサポート',
      'crisp_connecting': 'サポートに接続中...',
      'crisp_open_browser': 'ブラウザで開く',

      'update_title': '新しいバージョンが利用可能です',
      'update_now': '今すぐ更新',
      'update_later': '後で',
      'update_force_tip': 'このアップデートには重大なセキュリティ修正が含まれます。',

      'confirm': '確認',
      'cancel': 'キャンセル',
      'refresh': '更新',
      'shop_switch_plan_hint': '【{name}】({period} {price}) へのプラン変更を行おうとしています。現在のプランは上書きされます。',
      'shop_more_features': '+{count} 件',
      'shop_features_privilege': '特典と特権：',
      'shop_confirm_select_plan': '選択したプランを確定',
      'traffic_ratio': '倍率:{rate}x',
      'traffic_up_short': 'アップロード',
      'traffic_down_short': 'ダウンロード',
      'traffic_total_short': '合計',
      'traffic_used_percent': '使用済み {percent}%',
      'traffic_remaining_prefix': '残り容量: {value}',

      // 接続状況 (Connections)
      'conn_title': 'リアルタイム接続監視',
      'conn_subtitle_active': 'アクティブ接続: {count} · 累計下り: {down} · 累計上り: {up}',
      'conn_subtitle_idle': '待機中。接続後にトラフィックルートを表示します。',
      'conn_search_hint': 'ホストまたはIPを検索...',
      'conn_close_all': '全接続を切断',
      'conn_th_dest': '宛先ホスト / ポート',
      'conn_th_protocol': 'プロトコル',
      'conn_th_rule': 'ルール',
      'conn_th_outbound': '送信先ノード',
      'conn_th_traffic': 'トラフィック (下り/上り)',
      'conn_idle_placeholder': '待機中。接続後にリアルタイム通信を監視できます。',
      'conn_empty_active': 'アクティブな接続はありません',
      'conn_no_active': 'アクティブな接続はありません',
      'conn_empty_search': '一致する接続記録がありません',
      'conn_closed_all_msg': 'すべてのアクティブな接続を切断しました',
      'conn_close_error': '操作に失敗しました: {error}',
      'no_notice': 'お知らせはありません',

      // モード切替と加速ボタン
      'mode_direct': 'ダイレクト',

      // 通信量明細ラベル

      // デスクトップクイックヒントとダイアログ
      'tooltip_lang': '言語切り替え',
      'tooltip_diag': 'ネットワーク診断',
      'tooltip_checkin': 'デイリーチェックイン',
      'tooltip_service': 'オンラインサポート',
      'tooltip_notice': '最新のお知らせ',
      'admin_required_title': '管理者権限が必要です',
      'admin_required_desc': 'TUN仮想アダプターモードを使用するには、Wintunドライバーを管理するための管理者権限が必要です。\n\n下のボタンをクリックして管理者として再起動してください。',
      'admin_restart_btn': '管理者として再起動',
      'sub_synced_success': '購読の同期が完了しました',
      'loading_nodes': 'サーバーを読み込み中...',

      // 自動起動とアップデート
      'more_auto_start': '起動時に自動実行',
      'auto_start_enabled': '有効',
      'auto_start_disabled': '無効',
      'auto_start_snack_on': '自動起動を有効にしました',
      'auto_start_snack_off': '自動起動を無効にしました',
      'check_update_failed': 'アップデート確認に失敗しました',
      'window_title': '天河ネットワーク - グローバル高速安全プロキシ',
      'splash_slogan': '安全 · 安定 · 超高速トンネル',
      'splash_init_channel': 'セキュアトンネルを確立中...',
      'splash_resolving_doh': 'DoHアンチブロッキング回線を解決中...',
      'splash_checking_version': 'クライアントのバージョンを確認中...',
      'splash_verifying_auth': 'アカウント状態を確認中...',
      'splash_init_failed': '初期化に失敗しました。接続を確認してください',
      'splash_retry_conn': '再試行',

      // 診断とダイアログ
      'diag_title': 'ネットワーク・接続性診断',
      'diag_local_net': 'ローカルネットワーク接続',
      'diag_local_net_desc': 'アダプターとIPの接続状態を確認',
      'diag_api': 'V2Board バックエンド API',
      'diag_api_desc': 'サーバーの疎通と応答速度を確認',
      'diag_doh': 'DNS名前解決 (DoH)',
      'diag_doh_desc': 'DoH/DNSの解決速度と状態を確認',
      'diag_core': 'MihomoコアとTUNインターフェース',
      'diag_core_desc': 'システムプロキシトンネルの稼働状態',
      'diag_cross_border': '海外主要サイト (Google/CF)',
      'diag_cross_border_desc': '海外回線の接続性とTLSハンドシェイク速度',
      'diag_testing': '測定中...',
      'diag_retest': '再測定',
      'diag_local_nic': 'ローカルNIC',
      'diag_sys_proxy': 'システムプロキシサービス',
      'diag_core_controller': 'Mihomoコアコントローラー',
      'diag_doh_anti': 'DNSアンチブロッキング',
      'done': '完了',
      'checkin_thanks': '天河ネットワークのご利用ありがとうございます！',
      'checkin_credited': '本日のチェックイン完了。無料延長が付与されました。',
      'no_announcements': '新しいお知らせはありません',
      'local_user': 'ローカルユーザー',

      // アップデートダイアログ
      'update_force_title': '必須アップデート',
      'update_new_title': '新しいバージョンが利用可能',
      'update_changelog_title': '更新履歴：',
      'update_default_changelog': '安定性の向上と不具合の修正。',
      'update_remind_later': '後で通知',
      'update_now_overwrite': '今すぐアップデート',
      'update_now_upgrade': '今すぐアップグレード',
      'update_preparing': 'ダウンロード準備中...',
      'update_no_url': 'このプラットフォーム向けのダウンロードURLがありません',

      // お知らせとログイン
      'notice_coupon_prefix': 'クーポンコード: ',
      'notice_coupon_copied': 'クーポンコードをクリップボードにコピーしました',
      'copy_btn': 'コピー',
      'i_understand': '了解',
      'login_title': 'ログインして世界中の高速ノードをお楽しみください',
      'login_btn': 'ログイン',
      'login_no_account': 'アカウントをお持ちでないですか？',
      'login_register_now': '今すぐ登録',
      'login_forgot_pwd': 'パスワードをお忘れですか？',
      'email_hint': 'メールアドレス',
      'pwd_hint': 'パスワードを入力',
      'register_title': '新規アカウント作成',
      'register_desc': '天河ネットワークに登録して高速アクセスを開始',
      'register_btn': 'アカウントを作成してログイン',
      'back_to_login': 'ログインに戻る',
      'email_code_hint': '認証コード',
      'send_code': '送信',
      'pwd_set_hint': 'パスワードを設定 (6文字以上)',
      'pwd_confirm_hint': 'パスワードを再入力',
      'invite_code_optional': '招待コード (任意)',
      'reset_pwd_title': 'パスワードの再設定',
      'reset_pwd_desc': 'メール認証後に新しいパスワードを設定します',

      // 接続ボタンとヒント
      'syncing_routes': '専用ルートを同期中...',
      'node_unselected': 'ノードが選択されていません',
      'tap_to_select_node': 'ここをタップしてノード一覧を展開',
      'select_node_hint': '接続ノードを先に選択してください',
      'order_failed_prefix': '注文の作成に失敗しました',

      // 招待・アフィリエイト (Affiliate)
      'affiliate_title': '招待・アフィリエイト',
      'affiliate_codes_tab': '招待コード一覧',
      'affiliate_rebates_tab': '報酬履歴',
      'affiliate_create_code': 'コード作成',
      'affiliate_code_created': '新しい招待コードを作成しました！',
      'affiliate_create_failed': '作成に失敗しました',
      'affiliate_empty_codes': '招待コードがありません。上のボタンから作成してください',
      'affiliate_empty_rebates': '報酬履歴はありません',
      'affiliate_copied': '招待リンクをクリップボードにコピーしました',
      'affiliate_account_info': 'アカウント情報',
      'affiliate_balance': 'アカウント残高',
      'affiliate_commission': '報酬残高',
      'affiliate_btn_transfer': '振替',
      'affiliate_btn_withdraw': '出金',
      'affiliate_withdraw_tip': '出金申請はオンラインサポートまたはチケットでお問い合わせください',
      'affiliate_stats': '招待統計',
      'affiliate_stat_invited': '招待人数',
      'affiliate_stat_rate': '報酬料率',
      'affiliate_stat_total': '累計報酬',
      'affiliate_stat_pending': '未確定報酬',
      'affiliate_transfer_dialog_title': '報酬の振替',
      'affiliate_current_comm': '現在の報酬残高',
      'affiliate_transfer_amount': '振替金額 (元)',
      'affiliate_transfer_hint': '振替金額を入力してください',
      'affiliate_transfer_invalid': '有効な金額を入力してください',
      'affiliate_transfer_success': '振替が完了しました。残高に反映されました',
      'affiliate_transfer_failed': '振替に失敗しました',
      'affiliate_copy_full_link': 'リンクをコピー',

      // 注文支払いと履歴
      'order_details': '注文情報',
      'order_no': '注文番号',
      'order_original_price': '金額',
      'order_status': '状態',
      'order_pending': '未払い',
      'order_select_pay_method': '支払い方法を選択',
      'order_pay_now': '今すぐ支払う',
      'order_cancel': '注文をキャンセル',
      'order_cancel_confirm': '注文キャンセルの確認',
      'order_cancel_desc': 'この未払いの注文をキャンセルしてもよろしいですか？',
      'order_canceled': '注文がキャンセルされました',
      'order_pay_notes': '支払いに関する注意事項',
      'order_note_1': '1. 30分以内に支払いを完了してください。過ぎると自動キャンセルされます',
      'order_note_2': '2. 支払い完了後、システムにより自動的にサービスが有効化されます',
      'order_note_3': '3. 支払いに関する問題が発生した場合は、サポートにお問い合わせください',
      'order_history': '注文履歴',
      'order_history_empty': '注文履歴がありません',
      'order_go_pay': '支払いに進む',

      // パスワード変更とサポート
      'pwd_mismatch': '新しいパスワードが一致しません',
      'pwd_changed_success': 'パスワードを変更しました！',
      'pwd_old_hint': '現在のパスワード',
      'pwd_old_required': '現在のパスワードを入力してください',
      'pwd_new_hint': '新しいパスワード (8文字以上)',
      'pwd_new_required': '新しいパスワードを入力してください',
      'pwd_length_min': 'パスワードは8文字以上である必要があります',
      'pwd_confirm_label': '新しいパスワードの確認',
      'pwd_confirm_required': 'もう一度パスワードを入力してください',
      'pwd_desc': 'アカウントの安全のため、現在と新しいパスワードを入力してください',
      'pwd_btn_submit': 'パスワードを更新',
      'ticket_priority_low': '優先度：低',
      'ticket_priority_med': '優先度：中',
      'ticket_priority_high': '優先度：高',
      'ticket_fill_fields': 'チケットの件名と内容を入力してください',
      'ticket_created_success': 'チケットを送信しました！',
      'ticket_status_closed': 'クローズ',
      'ticket_status_replied': '返信済み',
      'ticket_status_pending': '対応中',
      'tun_driver_missing_title': 'TUNドライバー未検出',
      'tun_driver_missing_desc': 'wintun.dllが検出されませんでした。システムプロキシモードを維持します。',
      'refresh_nodes': 'ノード更新',
      'sync_success': '✅ 更新が完了しました（利用可能ノード: {count} 件）',
      'sync_failed': 'サブスクリプションの同期に失敗しました',
    },
  };
}

/// 方便快速從 context 取值的擴充方法
extension I18nContextExtension on BuildContext {
  String tr(String key, [Map<String, String>? params]) =>
      I18nService.instance.t(key, params);
}