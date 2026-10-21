// lib/presentation/desktop/desktop_nodes_view.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../business/subscription/node_model.dart';
import '../../business/subscription/subscription_engine.dart';
import '../../core/constants/app_constants.dart';
import '../../core/i18n/i18n_service.dart';
import '../widgets/country_flag_badge.dart';
import 'desktop_theme_tokens.dart';

/// 專職節點狀態視圖 (DesktopNodesView)
/// 單一頂部搜尋/分類控制列 + 下方 3 欄並排網格卡片，徹底移除手機版彈窗殘留
class DesktopNodesView extends StatefulWidget {
  final SubscriptionEngine subscriptionEngine;
  final VoidCallback? onNodeChanged;
  final VoidCallback? onNavigateToHome;
  final VoidCallback? onTriggerConnect;

  const DesktopNodesView({
    super.key,
    required this.subscriptionEngine,
    this.onNodeChanged,
    this.onNavigateToHome,
    this.onTriggerConnect,
  });

  @override
  State<DesktopNodesView> createState() => _DesktopNodesViewState();
}

class _DesktopNodesViewState extends State<DesktopNodesView>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int _selectedContinentIndex = 0; // 0: 全部, 1: 亞洲, 2: 歐美, 3: 其他
  bool _isTesting = false;
  bool _isRefreshing = false;
  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    widget.subscriptionEngine.addListener(_onEngineChanged);
  }

  void _onEngineChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.subscriptionEngine.removeListener(_onEngineChanged);
    _rotationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _handleRefreshNodes() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    _rotationController.repeat();
    try {
      final nodes = await widget.subscriptionEngine.performManualSync();
      if (mounted) {
        final count = nodes.length;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              I18nService.instance.t('sync_success', {'count': count.toString()}),
            ),
            backgroundColor: DesktopThemeTokens.accentSuccess,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(I18nService.instance.t('sync_failed')),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        _rotationController.stop();
        _rotationController.reset();
        setState(() => _isRefreshing = false);
      }
    }
  }

  Future<void> _handleBatchPing() async {
    setState(() => _isTesting = true);
    await widget.subscriptionEngine.pingAllNodes();
    if (mounted) {
      setState(() => _isTesting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(I18nService.instance.t('speed_test_done'))),
      );
    }
  }

  Future<void> _handleSelectNode(NodeModel node) async {
    // 1. 第一步：將選中的節點設為當前生效代理節點，並更新內存配置
    await widget.subscriptionEngine.selectNode(node);
    widget.onNodeChanged?.call();

    // 檢查是否開啟選取節點後自動連線
    bool autoConnect = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      autoConnect = prefs.getBool(AppConstants.storageAutoConnectOnNodeSelect) ?? false;
    } catch (_) {}

    // 2. 第二步（自動導航）：在 0.1 秒 (100ms) 內自動切回「加速主頁」
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    widget.onNavigateToHome?.call();

    // 3. 第三步：若啟用自動連線選項，立即發起加速閉環
    if (autoConnect) {
      widget.onTriggerConnect?.call();
    }
  }

  Future<void> _handleSelectFastest() async {
    final fastest = await widget.subscriptionEngine.selectFastestNode();
    if (fastest != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${I18nService.instance.t('node_switched_fastest')}${fastest.name} (${fastest.latencyFormatted})',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      widget.onNodeChanged?.call();

      bool autoConnect = false;
      try {
        final prefs = await SharedPreferences.getInstance();
        autoConnect = prefs.getBool(AppConstants.storageAutoConnectOnNodeSelect) ?? false;
      } catch (_) {}

      // 0.1 秒內自動切回主頁
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;

      widget.onNavigateToHome?.call();

      if (autoConnect) {
        widget.onTriggerConnect?.call();
      }
    }
  }

  List<NodeModel> _getFilteredNodes() {
    var list = widget.subscriptionEngine.nodes;

    // 搜尋過濾
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((n) =>
          n.name.toLowerCase().contains(q) ||
          n.protocol.toLowerCase().contains(q) ||
          n.countryCode.toLowerCase().contains(q)).toList();
    }

    // 分組大洲過濾
    if (_selectedContinentIndex == 1) {
      // 亞洲
      const asiaCodes = ['HK', 'JP', 'SG', 'TW', 'KR', 'MY', 'TH', 'VN', 'PH', 'IN'];
      list = list.where((n) => asiaCodes.contains(n.countryCode.toUpperCase())).toList();
    } else if (_selectedContinentIndex == 2) {
      // 歐美
      const westernCodes = ['US', 'CA', 'GB', 'DE', 'FR', 'NL', 'IE', 'RU', 'AU'];
      list = list.where((n) => westernCodes.contains(n.countryCode.toUpperCase())).toList();
    } else if (_selectedContinentIndex == 3) {
      // 其他
      const mainCodes = ['HK', 'JP', 'SG', 'TW', 'KR', 'MY', 'TH', 'VN', 'PH', 'IN', 'US', 'CA', 'GB', 'DE', 'FR', 'NL', 'IE', 'RU', 'AU'];
      list = list.where((n) => !mainCodes.contains(n.countryCode.toUpperCase())).toList();
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18nService.instance;
    final nodes = _getFilteredNodes();
    final selectedNode = widget.subscriptionEngine.selectedNode;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DesktopThemeTokens.spacing, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 頂部整合控制列 (搜尋框 + 分類按鈕 + 測速與優選，拔除雙重重複標題)
          Row(
            children: [
              // 搜尋框
              Container(
                width: 220,
                height: 36,
                decoration: BoxDecoration(
                  color: DesktopThemeTokens.cardInnerBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: DesktopThemeTokens.borderColor),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded, size: 16, color: DesktopThemeTokens.textMuted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (val) => setState(() => _searchQuery = val.trim()),
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        decoration: InputDecoration(
                          hintText: i18n.t('node_search_hint'),
                          hintStyle: const TextStyle(color: DesktopThemeTokens.textMuted, fontSize: 11),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    if (_searchQuery.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                        child: const Icon(Icons.close_rounded, size: 14, color: DesktopThemeTokens.textMuted),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // 分類標籤
              _buildContinentTab(0, i18n.t('node_tab_all')),
              const SizedBox(width: 6),
              _buildContinentTab(1, i18n.t('node_tab_asia')),
              const SizedBox(width: 6),
              _buildContinentTab(2, i18n.t('node_tab_western')),
              const SizedBox(width: 6),
              _buildContinentTab(3, i18n.t('node_tab_others')),

              const Spacer(),

              // 手動刷新節點按鈕 (支援旋轉動效與防連點鎖定)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: DesktopThemeTokens.textPrimary,
                  side: const BorderSide(color: DesktopThemeTokens.borderColor),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: (_isRefreshing || _isTesting) ? null : _handleRefreshNodes,
                icon: RotationTransition(
                  turns: _rotationController,
                  child: const Icon(Icons.refresh_rounded, size: 16),
                ),
                label: Text(
                  i18n.t('refresh_nodes'),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),

              // 自動優選按鈕
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: DesktopThemeTokens.neonCyan,
                  side: const BorderSide(color: DesktopThemeTokens.borderColor),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _handleSelectFastest,
                icon: const Icon(Icons.bolt_rounded, size: 16),
                label: Text(i18n.t('best_latency'), style: const TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),

              // 批量測速按鈕
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: DesktopThemeTokens.neonCyan,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _isTesting ? null : _handleBatchPing,
                icon: _isTesting
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.speed_rounded, size: 16),
                label: Text(i18n.t('speed_test'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 3 欄並排網格卡片清單 (固定高度 76px，零下拉)
          Expanded(
            child: nodes.isEmpty
                ? Center(
                    child: Text(
                      _searchQuery.isNotEmpty ? i18n.t('node_empty_search') : i18n.t('node_empty_all'),
                      style: const TextStyle(color: DesktopThemeTokens.textMuted, fontSize: 14),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.only(bottom: 12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      mainAxisExtent: 76,
                    ),
                    itemCount: nodes.length,
                    itemBuilder: (context, index) {
                      final node = nodes[index];
                      final isSelected = selectedNode?.id == node.id;
                      return _buildNodeCard(node, isSelected, i18n);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildContinentTab(int index, String label) {
    final isSelected = _selectedContinentIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedContinentIndex = index),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? DesktopThemeTokens.neonCyan.withOpacity(0.15) : DesktopThemeTokens.cardInnerBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? DesktopThemeTokens.neonCyan : DesktopThemeTokens.borderColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? DesktopThemeTokens.neonCyan : DesktopThemeTokens.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildNodeCard(NodeModel node, bool isSelected, I18nService i18n) {
    final latency = node.latencyMs ?? 0;
    final hasPing = latency > 0;
    final isGood = latency > 0 && latency < 120;
    final isMedium = latency >= 120 && latency < 250;
    final latencyColor = hasPing
        ? (isGood
            ? DesktopThemeTokens.emeraldGreen
            : (isMedium ? DesktopThemeTokens.amberWarn : DesktopThemeTokens.roseRed))
        : DesktopThemeTokens.textMuted;

    return InkWell(
      onTap: () => _handleSelectNode(node),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? DesktopThemeTokens.neonCyan.withOpacity(0.08) : DesktopThemeTokens.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? DesktopThemeTokens.neonCyan : DesktopThemeTokens.borderColor,
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: DesktopThemeTokens.neonCyan.withOpacity(0.1),
                blurRadius: 10,
              ),
          ],
        ),
        child: Row(
          children: [
            // 彩色向量國旗
            CountryFlagBadge(
              node: node,
              size: const Size(26, 18),
            ),
            const SizedBox(width: 10),

            // 節點名稱與協定
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    node.cleanDisplayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      color: isSelected ? Colors.white : DesktopThemeTokens.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            node.protocol.toUpperCase(),
                            style: const TextStyle(fontSize: 10, color: DesktopThemeTokens.textMuted),
                          ),
                        ),
                        if (node.name.contains('專線') || node.name.contains('VIP') || node.name.contains('4K')) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: DesktopThemeTokens.neonCyan.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'VIP',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: DesktopThemeTokens.neonCyan),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // 延遲探測膠囊
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: latencyColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: latencyColor,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    hasPing ? '$latency ms' : i18n.t('node_pending_test'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: latencyColor,
                      fontFamily: 'Segoe UI',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
