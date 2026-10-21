// lib/presentation/desktop/desktop_traffic_view.dart

import 'package:flutter/material.dart';
import '../../business/auth/auth_manager.dart';
import '../../business/auth/traffic_log_model.dart';
import '../../core/i18n/i18n_service.dart';
import 'desktop_theme_tokens.dart';

/// 專職雙欄流量明細視圖 (DesktopTrafficView)
/// 左欄：190px 大圓環總覽 + 3 卡片 + 2x2 指標矩陣 (完全消除 220px 黑洞)
/// 右欄：真實 V2Board 流量明細 API + 頂部消耗統計橫幅 + 當日相對峰值佔比條
class DesktopTrafficView extends StatefulWidget {
  final AuthManager authManager;

  const DesktopTrafficView({
    super.key,
    required this.authManager,
  });

  @override
  State<DesktopTrafficView> createState() => _DesktopTrafficViewState();
}

class _DesktopTrafficViewState extends State<DesktopTrafficView> {
  bool _isLoading = true;
  List<TrafficLogModel> _logs = [];

  @override
  void initState() {
    super.initState();
    _loadTrafficLogs();
  }

  Future<void> _loadTrafficLogs() async {
    setState(() => _isLoading = true);
    try {
      try {
        await widget.authManager.fetchUserInfo();
      } catch (userErr) {
        debugPrint('[DesktopTrafficView] 更新用戶資料警告 (續用快取): $userErr');
      }
      final logs = await widget.authManager.fetchTrafficLogs();
      if (mounted) {
        setState(() {
          // 100% 綁定真實 API 回傳資料，不再注入寫死假數據
          _logs = logs;
          _isLoading = false;
        });
      }
    } catch (e, stack) {
      debugPrint('[DesktopTrafficView] 載入流量日誌例外: $e\n$stack');
      if (mounted) {
        setState(() {
          _logs = [];
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18nService.instance;
    final user = widget.authManager.state.user;

    final totalTraffic = user?.transferEnable ?? 0;
    final usedTraffic = (user?.u ?? 0) + (user?.d ?? 0);
    final ratio = totalTraffic > 0 ? (usedTraffic / totalTraffic).clamp(0.0, 1.0) : 0.0;
    final remainingRatio = (1.0 - ratio).clamp(0.0, 1.0);
    final remainingPercent = (remainingRatio * 100).toInt();

    // 峰值與日均統計計算
    int maxLogBytes = 1;
    double totalRateSum = 0.0;
    for (final l in _logs) {
      if (l.totalBytes > maxLogBytes) {
        maxLogBytes = l.totalBytes;
      }
      totalRateSum += l.serverRate;
    }
    final avgRate = _logs.isNotEmpty ? (totalRateSum / _logs.length) : 1.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DesktopThemeTokens.spacing, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ══════════════════════════════════════════════
          // 左欄：流量使用總覽卡片 (Overview)
          // ══════════════════════════════════════════════
          Expanded(
            flex: 5,
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: DesktopThemeTokens.cardBg,
                borderRadius: BorderRadius.circular(DesktopThemeTokens.cardRadius),
                border: Border.all(color: DesktopThemeTokens.borderColor),
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. 頂部標題列
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: DesktopThemeTokens.neonCyan.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.pie_chart_rounded, color: DesktopThemeTokens.neonCyan, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Text(i18n.t('traffic_overview'), style: DesktopThemeTokens.titleStyle),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // 2. 藍色雙層科技星環儀表 (190 x 190 px, 雙層光暈星環，中央文字寬敞居中，杜絕壓線)
                    Center(
                      child: SizedBox(
                        width: 190,
                        height: 190,
                        child: Stack(
                          fit: StackFit.expand,
                          alignment: Alignment.center,
                          children: [
                            // 外層科技裝飾輔助微光底座
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF00D2FF).withOpacity(0.12),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF0EA5E9).withOpacity(0.08),
                                    blurRadius: 24,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                            // 外層旋轉脈衝微點軌道 (雙層星環層次)
                            Padding(
                              padding: const EdgeInsets.all(5.0),
                              child: CircularProgressIndicator(
                                value: 1.0,
                                strokeWidth: 1.5,
                                backgroundColor: Colors.transparent,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  const Color(0xFF38BDF8).withOpacity(0.2),
                                ),
                              ),
                            ),
                            // 主進度星環 (粗度 12px，平滑端點，藍色雙層科技星環)
                            Padding(
                              padding: const EdgeInsets.all(6.0),
                              child: CircularProgressIndicator(
                                value: remainingRatio,
                                strokeWidth: 12,
                                backgroundColor: const Color(0xFF1E293B),
                                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00D2FF)),
                                strokeCap: StrokeCap.round,
                              ),
                            ),
                            // 內部居中內容：剩餘百分比與標籤 (寬敞置中，內縮安全區，徹底杜絕文字壓線)
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '$remainingPercent%',
                                  style: const TextStyle(
                                    fontSize: 34,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    fontFamily: 'Segoe UI',
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00D2FF).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    i18n.t('traffic_remaining'),
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: Color(0xFF38BDF8),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),

                    // 3. 修正三張數據卡配色與尺寸 (已用流量低於 80% 使用琥珀金，非刺眼紅)
                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricTile(
                            title: i18n.t('traffic_used'),
                            value: user?.usedTrafficFormatted ?? '0.00 GB',
                            color: ratio < 0.8 ? const Color(0xFFF59E0B) : DesktopThemeTokens.roseRed,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildMetricTile(
                            title: i18n.t('traffic_remaining'),
                            value: user?.remainingTrafficFormatted ?? '0.00 GB',
                            color: const Color(0xFF38BDF8),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildMetricTile(
                            title: i18n.t('traffic_total'),
                            value: user?.totalTrafficFormatted ?? '0.00 GB',
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // 4. 2x2 訂閱與流量健康度矩陣 (徹底填滿下半部空間，消除黑洞)
                    _buildHealthMetricsGrid(user, ratio),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: DesktopThemeTokens.spacing),

          // ══════════════════════════════════════════════
          // 右欄：每日流量消耗記錄 (Daily Logs)
          // ══════════════════════════════════════════════
          Expanded(
            flex: 6,
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: DesktopThemeTokens.cardBg,
                borderRadius: BorderRadius.circular(DesktopThemeTokens.cardRadius),
                border: Border.all(color: DesktopThemeTokens.borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. 標題與重整按鈕
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: DesktopThemeTokens.neonBlue.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.history_rounded, color: DesktopThemeTokens.neonBlue, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(i18n.t('traffic_daily_log'), style: DesktopThemeTokens.titleStyle),
                      const Spacer(),
                      IconButton(
                        tooltip: '重新整理',
                        icon: _isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: DesktopThemeTokens.neonCyan),
                              )
                            : const Icon(Icons.refresh_rounded, size: 19, color: DesktopThemeTokens.textMuted),
                        onPressed: _isLoading ? null : _loadTrafficLogs,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // 2. 近期消耗峰值與日均統計橫幅 (高約 86px)
                  _buildSummaryBanner(_logs, maxLogBytes, avgRate),
                  const SizedBox(height: 12),

                  // 3. 近期流量消耗趨勢圖 (Trend Sparkline)
                  if (_logs.isNotEmpty) ...[
                    _buildTrendChart(_logs, maxLogBytes),
                    const SizedBox(height: 12),
                  ],

                  // 3. 流量記錄列表 (帶相對峰值佔比進度條)
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator(color: DesktopThemeTokens.neonCyan))
                        : _logs.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.query_builder_rounded, size: 40, color: DesktopThemeTokens.textMuted.withOpacity(0.5)),
                                    const SizedBox(height: 12),
                                    Text(
                                      i18n.t('traffic_no_logs'),
                                      style: const TextStyle(fontSize: 13, color: DesktopThemeTokens.textMuted),
                                    ),
                                    const SizedBox(height: 8),
                                    TextButton.icon(
                                      onPressed: _loadTrafficLogs,
                                      icon: const Icon(Icons.refresh_rounded, size: 14, color: DesktopThemeTokens.neonCyan),
                                      label: const Text('點擊同步後端明細', style: TextStyle(fontSize: 12, color: DesktopThemeTokens.neonCyan)),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                physics: const BouncingScrollPhysics(),
                                itemCount: _logs.length,
                                itemBuilder: (context, idx) {
                                  final item = _logs[idx];
                                  final double progress = maxLogBytes > 0
                                      ? (item.totalBytes / maxLogBytes).clamp(0.05, 1.0)
                                      : 0.05;

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 11),
                                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                                    decoration: BoxDecoration(
                                      color: DesktopThemeTokens.cardInnerBg,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: DesktopThemeTokens.borderColor.withOpacity(0.7)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // 數據行
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(5),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withOpacity(0.06),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Icon(Icons.calendar_today_rounded, size: 13, color: DesktopThemeTokens.neonCyan),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              item.dateOnly,
                                              style: const TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            // 節點倍率膠囊
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF38BDF8).withOpacity(0.12),
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.3), width: 0.8),
                                              ),
                                              child: Text(
                                                '倍率: ${item.serverRate.toStringAsFixed(2)}x',
                                                style: const TextStyle(fontSize: 9.5, color: Color(0xFF38BDF8), fontWeight: FontWeight.w600),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Align(
                                                alignment: Alignment.centerRight,
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  alignment: Alignment.centerRight,
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      // 上行
                                                      Text(
                                                        '↑ ${item.formattedUpload}',
                                                        style: const TextStyle(fontSize: 10.5, color: Color(0xFFC084FC), fontFamily: 'Segoe UI'),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      // 下行
                                                      Text(
                                                        '↓ ${item.formattedDownload}',
                                                        style: const TextStyle(fontSize: 10.5, color: Color(0xFF34D399), fontFamily: 'Segoe UI'),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      // 合計膠囊
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                                        decoration: BoxDecoration(
                                                          color: DesktopThemeTokens.neonCyan.withOpacity(0.14),
                                                          borderRadius: BorderRadius.circular(6),
                                                          border: Border.all(color: DesktopThemeTokens.neonCyan.withOpacity(0.35), width: 0.8),
                                                        ),
                                                        child: Text(
                                                          item.formattedTotal,
                                                          style: const TextStyle(
                                                            fontSize: 10.5,
                                                            fontWeight: FontWeight.bold,
                                                            color: DesktopThemeTokens.neonCyan,
                                                            fontFamily: 'Segoe UI',
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),

                                        // 當日相對峰值佔比進度條
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(2),
                                          child: Stack(
                                            children: [
                                              Container(
                                                height: 3.5,
                                                width: double.infinity,
                                                color: Colors.white.withOpacity(0.06),
                                              ),
                                              FractionallySizedBox(
                                                widthFactor: progress,
                                                child: Container(
                                                  height: 3.5,
                                                  decoration: const BoxDecoration(
                                                    gradient: LinearGradient(
                                                      colors: [Color(0xFF38BDF8), Color(0xFF0284C7)],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 頂部三張數據小卡
  Widget _buildMetricTile({
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: DesktopThemeTokens.cardInnerBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DesktopThemeTokens.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: DesktopThemeTokens.labelStyle),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
              color: color,
              fontFamily: 'Segoe UI',
            ),
          ),
        ],
      ),
    );
  }

  /// 2x2 訂閱與流量健康度矩陣 (填滿左卡下半部)
  Widget _buildHealthMetricsGrid(dynamic user, double ratio) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildGridCell(
                icon: Icons.workspace_premium_rounded,
                iconColor: const Color(0xFFA855F7),
                title: '當前方案',
                value: user?.planName ?? (user?.planId != null ? 'VIP 旗艦節點方案' : 'VIP 專屬高速通道'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildGridCell(
                icon: Icons.calendar_month_rounded,
                iconColor: const Color(0xFF38BDF8),
                title: '到期時間',
                value: user?.expiredDateFormatted ?? '長期有效',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildGridCell(
                icon: Icons.insights_rounded,
                iconColor: const Color(0xFFF59E0B),
                title: '本週期消耗',
                value: '${user?.usedTrafficFormatted ?? '0.00 GB'} (${(ratio * 100).toStringAsFixed(1)}%)',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildGridCell(
                icon: Icons.verified_rounded,
                iconColor: const Color(0xFF10B981),
                title: '計費狀態',
                value: user?.isExpired == true ? '已過期 · 需續費' : '計費正常 · 服務中',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGridCell({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: DesktopThemeTokens.cardInnerBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DesktopThemeTokens.borderColor.withOpacity(0.7)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 10.5, color: DesktopThemeTokens.textMuted),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 近期流量消耗趨勢圖 (Trend Sparkline)
  Widget _buildTrendChart(List<TrafficLogModel> logs, int maxLogBytes) {
    if (logs.isEmpty) {
      return const SizedBox.shrink();
    }
    // 取最近 8 天記錄，由舊到新展示走勢
    final displayLogs = logs.take(8).toList().reversed.toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: DesktopThemeTokens.cardInnerBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DesktopThemeTokens.borderColor.withOpacity(0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.show_chart_rounded, size: 14, color: DesktopThemeTokens.neonCyan),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  '近期流量消耗走勢',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: DesktopThemeTokens.textMuted,
                    letterSpacing: 0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '最高單日: ${TrafficLogModel.formatBytes(maxLogBytes)}',
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF38BDF8),
                  fontFamily: 'Segoe UI',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: displayLogs.map((item) {
                final double ratio = maxLogBytes > 0
                    ? (item.totalBytes / maxLogBytes).clamp(0.08, 1.0)
                    : 0.08;
                final isPeak = item.totalBytes == maxLogBytes && maxLogBytes > 0;
                final shortDate = item.dateOnly.length >= 5
                    ? item.dateOnly.substring(item.dateOnly.length - 5)
                    : item.dateOnly;

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Tooltip(
                          message: '${item.dateOnly}\n消耗: ${item.formattedTotal}\n倍率: ${item.serverRate.toStringAsFixed(2)}x',
                          child: Container(
                            height: 30 * ratio,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: isPeak
                                    ? [const Color(0xFF00D2FF), const Color(0xFF38BDF8)]
                                    : [const Color(0xFF0284C7).withOpacity(0.5), const Color(0xFF00D2FF).withOpacity(0.7)],
                              ),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                              boxShadow: isPeak
                                  ? [
                                      BoxShadow(
                                        color: const Color(0xFF00D2FF).withOpacity(0.4),
                                        blurRadius: 6,
                                        offset: const Offset(0, -1),
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          shortDate,
                          style: TextStyle(
                            fontSize: 9,
                            color: isPeak ? const Color(0xFF38BDF8) : DesktopThemeTokens.textMuted,
                            fontWeight: isPeak ? FontWeight.bold : FontWeight.normal,
                            fontFamily: 'Segoe UI',
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// 近期消耗峰值與日均統計橫幅 (高約 86px)
  Widget _buildSummaryBanner(List<TrafficLogModel> logs, int maxLogBytes, double avgRate) {
    int totalLoggedBytes = 0;
    for (final l in logs) {
      totalLoggedBytes += l.totalBytes;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF0F172A),
            const Color(0xFF0B1329).withOpacity(0.95),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF00D2FF).withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildBannerColumn(
              label: '歷史統計明細',
              value: logs.isEmpty ? '0 筆記錄' : '${logs.length} 筆天數 (${TrafficLogModel.formatBytes(totalLoggedBytes)})',
              color: Colors.white,
              icon: Icons.analytics_outlined,
            ),
          ),
          Container(width: 1, height: 32, margin: const EdgeInsets.symmetric(horizontal: 8), color: Colors.white.withOpacity(0.1)),
          Expanded(
            child: _buildBannerColumn(
              label: '最高單日峰值',
              value: logs.isEmpty ? '--' : TrafficLogModel.formatBytes(maxLogBytes),
              color: const Color(0xFF38BDF8),
              icon: Icons.trending_up_rounded,
            ),
          ),
          Container(width: 1, height: 32, margin: const EdgeInsets.symmetric(horizontal: 8), color: Colors.white.withOpacity(0.1)),
          Expanded(
            child: _buildBannerColumn(
              label: '平均節點倍率',
              value: logs.isEmpty ? '1.00x' : '${avgRate.toStringAsFixed(2)}x',
              color: const Color(0xFFA855F7),
              icon: Icons.speed_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBannerColumn({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color.withOpacity(0.85)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 10, color: DesktopThemeTokens.textMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontFamily: 'Segoe UI',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
