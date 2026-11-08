// lib/presentation/dashboard/widgets/node_selector_modal.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/i18n/i18n_service.dart';
import '../../../core/utils/error_sanitizer.dart';
import '../../../core/theme/app_theme.dart';
import '../../../business/subscription/node_model.dart';
import '../../../business/subscription/subscription_engine.dart';
import '../../widgets/country_flag_badge.dart';

/// 節點選擇彈窗 / 抽屜組件 (NodeSelectorModal)
/// 提供大洲分組 (全部 / 亞洲 / 歐美 / 其他)、收藏星號即時切換、一鍵測速與最佳節點選擇
/// 支援桌面端高質感居中 Dialog 與自適應 2~4 欄響應式佈局，徹底消除文字截斷
class NodeSelectorModal extends StatefulWidget {
  final SubscriptionEngine subscriptionEngine;
  final bool isEmbedded;
  final bool isDialog;
  final ValueChanged<NodeModel>? onNodeSelected;

  const NodeSelectorModal({
    super.key,
    required this.subscriptionEngine,
    this.isEmbedded = false,
    this.isDialog = false,
    this.onNodeSelected,
  });

  /// 喚起節點選擇彈窗 (桌面端自動呈現高質感居中 Dialog，行動端呈現底部抽屜)
  static Future<void> show(
    BuildContext context, {
    required SubscriptionEngine subscriptionEngine,
    ValueChanged<NodeModel>? onNodeSelected,
  }) {
    final isDesktopPlatform = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    final isWideScreen = MediaQuery.of(context).size.width > 720;

    if (isDesktopPlatform || isWideScreen) {
      return showDialog(
        context: context,
        barrierColor: Colors.black.withOpacity(0.65),
        barrierDismissible: true,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Container(
            constraints: const BoxConstraints(
              maxWidth: 1040,
              maxHeight: 700,
            ),
            decoration: BoxDecoration(
              color: AppTheme.darkSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.darkBorder, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.55),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: AppTheme.primaryCyan.withOpacity(0.08),
                  blurRadius: 16,
                  spreadRadius: -2,
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: NodeSelectorModal(
              subscriptionEngine: subscriptionEngine,
              isDialog: true,
              onNodeSelected: onNodeSelected,
            ),
          ),
        ),
      );
    }

    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => NodeSelectorModal(
        subscriptionEngine: subscriptionEngine,
        onNodeSelected: onNodeSelected,
      ),
    );
  }

  @override
  State<NodeSelectorModal> createState() => _NodeSelectorModalState();
}

class _NodeSelectorModalState extends State<NodeSelectorModal> {
  final TextEditingController _searchController = TextEditingController();
  bool _isTestingLatency = false;
  
  // 優先分組：全部 / 亞洲 / 歐美 / 其他
  String _selectedContinent = '全部';
  static const List<String> _continents = ['全部', '亞洲', '歐美', '其他'];

  String _searchQuery = '';
  bool _favoritesOnly = false;
  bool _sortByLowestLatency = false;

  @override
  void initState() {
    super.initState();
    widget.subscriptionEngine.addListener(_onEngineChanged);
  }

  void _onEngineChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.subscriptionEngine.removeListener(_onEngineChanged);
    _searchController.dispose();
    super.dispose();
  }

  bool _isRefreshing = false;

  Future<void> _handleRefreshNodes() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      await widget.subscriptionEngine.performManualSync();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(I18nService.instance.t('sub_synced_success'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${I18nService.instance.t('refresh_failed_prefix')}${ErrorSanitizer.sanitize(e)}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  Future<void> _handleSpeedTest() async {
    setState(() => _isTestingLatency = true);
    await widget.subscriptionEngine.pingAllNodes();
    if (mounted) {
      setState(() => _isTestingLatency = false);
    }
  }

  Future<void> _handleSelectFastest() async {
    final fastest = await widget.subscriptionEngine.selectFastestNode();
    if (fastest != null && mounted) {
      final i18n = I18nService.instance;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${i18n.t('node_switched_fastest')}${fastest.name} (${fastest.latencyFormatted})')),
      );
      widget.onNodeSelected?.call(fastest);
      if (!widget.isEmbedded) {
        Navigator.of(context).pop();
      }
    }
  }

  String _continentLabel(String continent) {
    final i18n = I18nService.instance;
    switch (continent) {
      case '全部':
        return i18n.t('node_tab_all');
      case '亞洲':
        return i18n.t('node_tab_asia');
      case '歐美':
        return i18n.t('node_tab_western');
      case '其他':
        return i18n.t('node_tab_others');
      default:
        return continent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18nService.instance;
    final allNodes = widget.subscriptionEngine.nodes;
    final selectedNode = widget.subscriptionEngine.selectedNode;
    final isDesktop = widget.isEmbedded || widget.isDialog || MediaQuery.of(context).size.width > 720;

    // 依收藏、延遲排序與搜尋字串過濾
    var filteredNodes = widget.subscriptionEngine.getFilteredNodes(
      favoritesOnly: _favoritesOnly,
      sortByLowestLatency: _sortByLowestLatency,
      searchQuery: _searchQuery,
    );

    // 依大洲篩選 (亞洲 / 美洲 / 歐洲 / 其他)
    if (_selectedContinent != '全部') {
      filteredNodes = filteredNodes.where((n) => n.continent == _selectedContinent).toList();
    }

    final content = Column(
      children: [
        // 1. 手機端頂部下拉把手條 (桌面端徹底拔除)
        if (!isDesktop) ...[
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
        ],

        // 2. 頂部控制列 (桌面端：高質感雙層架構；手機端：標題 + 搜尋 + 滾動條)
        if (isDesktop) ...[
          // ── 第一層：標題、搜尋框、操作按鈕群與關閉 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: Row(
              children: [
                // 標題圖標與文字
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryCyan.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.hub_rounded, size: 20, color: AppTheme.primaryCyan),
                ),
                const SizedBox(width: 10),
                Text(
                  i18n.t('node_selector_title'),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${filteredNodes.length}/${allNodes.length}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.6),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),

                // 緊湊精緻搜尋框
                SizedBox(
                  width: 210,
                  height: 36,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.darkCard,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.darkBorder),
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: InputDecoration(
                        hintText: i18n.t('node_search_hint'),
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 11),
                        prefixIcon: Icon(Icons.search_rounded, size: 16, color: Colors.white.withOpacity(0.4)),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 14, color: Colors.white54),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val.trim()),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // 操作按鈕群：[↻ 刷新]、[⚡ 測速]、[🚀 智慧優選]
                FilledButton.icon(
                  onPressed: _isRefreshing ? null : _handleRefreshNodes,
                  icon: _isRefreshing
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.sync_rounded, size: 15),
                  label: Text(
                    i18n.t('node_refresh_nodes'),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF334155),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(width: 6),
                FilledButton.icon(
                  onPressed: _isTestingLatency ? null : _handleSpeedTest,
                  icon: _isTestingLatency
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.bolt_rounded, size: 15),
                  label: Text(
                    _isTestingLatency ? i18n.t('node_testing') : i18n.t('node_speed_test'),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0EA5E9),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(width: 6),
                FilledButton.icon(
                  onPressed: allNodes.isEmpty ? null : _handleSelectFastest,
                  icon: const Icon(Icons.rocket_launch_rounded, size: 15),
                  label: Text(
                    i18n.t('node_smart_optimal'),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.successEmerald,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),

                // 桌面端彈窗關閉按鈕
                if (!widget.isEmbedded) ...[
                  const SizedBox(width: 8),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.close_rounded, size: 18, color: Colors.white70),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── 第二層：大洲分組標籤與特性過濾條 (橫向充裕空間，零遮擋零截斷) ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Row(
              children: [
                // 大洲分類標籤
                ..._continents.map((continent) {
                  final isSelected = !_favoritesOnly && _selectedContinent == continent;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _selectedContinent = continent;
                          _favoritesOnly = false;
                        });
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.primaryCyan.withOpacity(0.18) : AppTheme.darkCard,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected ? AppTheme.primaryCyan : AppTheme.darkBorder,
                            width: isSelected ? 1.2 : 1.0,
                          ),
                        ),
                        child: Text(
                          _continentLabel(continent),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected ? AppTheme.primaryCyan : Colors.white70,
                          ),
                        ),
                      ),
                    ),
                  );
                }),

                const SizedBox(width: 8),
                Container(width: 1, height: 16, color: Colors.white12),
                const SizedBox(width: 12),

                // 特性標籤 1：★ 我的收藏
                InkWell(
                  onTap: () {
                    setState(() {
                      _favoritesOnly = !_favoritesOnly;
                      if (_favoritesOnly) _selectedContinent = '全部';
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _favoritesOnly ? Colors.amberAccent.withOpacity(0.18) : AppTheme.darkCard,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _favoritesOnly ? Colors.amberAccent : AppTheme.darkBorder,
                        width: _favoritesOnly ? 1.2 : 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _favoritesOnly ? Icons.star_rounded : Icons.star_outline_rounded,
                          size: 15,
                          color: _favoritesOnly ? Colors.amberAccent : Colors.white60,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          i18n.t('node_tab_favorites'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: _favoritesOnly ? FontWeight.bold : FontWeight.w500,
                            color: _favoritesOnly ? Colors.amberAccent : Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // 特性標籤 2：⚡ 最低延遲優先
                InkWell(
                  onTap: () => setState(() => _sortByLowestLatency = !_sortByLowestLatency),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _sortByLowestLatency ? AppTheme.primaryCyan.withOpacity(0.18) : AppTheme.darkCard,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _sortByLowestLatency ? AppTheme.primaryCyan : AppTheme.darkBorder,
                        width: _sortByLowestLatency ? 1.2 : 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.speed_rounded,
                          size: 15,
                          color: _sortByLowestLatency ? AppTheme.primaryCyan : Colors.white60,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          i18n.t('node_tab_fastest'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: _sortByLowestLatency ? FontWeight.bold : FontWeight.w500,
                            color: _sortByLowestLatency ? AppTheme.primaryCyan : Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          // 手機版標題列
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.hub_rounded, size: 20, color: AppTheme.primaryCyan),
                    const SizedBox(width: 8),
                    Text(
                      i18n.t('node_selector_title'),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '(${filteredNodes.length}/${allNodes.length})',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withOpacity(0.5),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      tooltip: i18n.t('node_refresh_nodes'),
                      onPressed: _isRefreshing ? null : _handleRefreshNodes,
                      icon: _isRefreshing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryCyan),
                            )
                          : const Icon(Icons.sync_rounded, size: 18, color: AppTheme.primaryCyan),
                    ),
                    TextButton.icon(
                      onPressed: _isTestingLatency ? null : _handleSpeedTest,
                      icon: _isTestingLatency
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryCyan),
                            )
                          : const Icon(Icons.bolt_rounded, size: 16, color: AppTheme.primaryCyan),
                      label: Text(
                        _isTestingLatency ? i18n.t('node_testing') : i18n.t('node_speed_test'),
                        style: const TextStyle(color: AppTheme.primaryCyan, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: allNodes.isEmpty ? null : _handleSelectFastest,
                      icon: const Icon(Icons.rocket_launch_rounded, size: 16, color: AppTheme.successEmerald),
                      label: Text(i18n.t('node_smart_optimal'), style: const TextStyle(color: AppTheme.successEmerald, fontSize: 13, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 手機版搜尋框
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: AppTheme.darkCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.darkBorder),
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: i18n.t('node_search_hint'),
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 13),
                  prefixIcon: Icon(Icons.search_rounded, size: 18, color: Colors.white.withOpacity(0.4)),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 16, color: Colors.white54),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // 手機版水平滾動標籤列
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: _buildFilterChips(i18n),
            ),
          ),
        ],

        const SizedBox(height: 4),

        // 3. 節點列表內容 (桌面端：自適應 2~4 欄響應式 GridView；手機端：單欄 ListView)
        Expanded(
          child: filteredNodes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _favoritesOnly ? Icons.star_border_rounded : Icons.search_off_rounded,
                        size: 48,
                        color: Colors.white.withOpacity(0.2),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _favoritesOnly
                            ? i18n.t('node_empty_fav')
                            : (allNodes.isEmpty ? i18n.t('node_empty_all') : i18n.t('node_empty_search')),
                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
                      ),
                    ],
                  ),
                )
              : isDesktop
                  ? LayoutBuilder(
                      builder: (context, constraints) {
                        // 依容器寬度動態自適應欄數：確保單卡寬度充足 (>= 335px)，徹底消除節點與協定文字截斷
                        final int crossAxisCount = (constraints.maxWidth / 335).floor().clamp(1, 3);

                        return GridView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            mainAxisExtent: 72,
                          ),
                          itemCount: filteredNodes.length,
                          itemBuilder: (context, index) {
                            return _buildNodeItemCard(
                              node: filteredNodes[index],
                              isSelected: selectedNode?.id == filteredNodes[index].id,
                              isDesktop: true,
                            );
                          },
                        );
                      },
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: filteredNodes.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        return _buildNodeItemCard(
                          node: filteredNodes[index],
                          isSelected: selectedNode?.id == filteredNodes[index].id,
                          isDesktop: false,
                        );
                      },
                    ),
        ),
      ],
    );

    if (widget.isEmbedded || widget.isDialog) {
      return content;
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          decoration: const BoxDecoration(
            color: AppTheme.darkSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: content,
        ),
      ),
    );
  }

  List<Widget> _buildFilterChips(I18nService i18n) {
    return [
      FilterChip(
        selected: _favoritesOnly,
        avatar: Icon(
          _favoritesOnly ? Icons.star_rounded : Icons.star_outline_rounded,
          size: 16,
          color: _favoritesOnly ? Colors.black : Colors.amberAccent,
        ),
        label: Text(
          i18n.t('node_tab_favorites'),
          style: TextStyle(
            fontSize: 12,
            fontWeight: _favoritesOnly ? FontWeight.bold : FontWeight.normal,
            color: _favoritesOnly ? Colors.black : Colors.white70,
          ),
        ),
        selectedColor: Colors.amberAccent,
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: _favoritesOnly ? Colors.amberAccent : AppTheme.darkBorder,
          ),
        ),
        onSelected: (val) {
          setState(() {
            _favoritesOnly = val;
            if (val) {
              _selectedContinent = '全部';
            }
          });
        },
      ),
      const SizedBox(width: 8),
      FilterChip(
        selected: _sortByLowestLatency,
        avatar: Icon(
          Icons.speed_rounded,
          size: 16,
          color: _sortByLowestLatency ? Colors.black : AppTheme.primaryCyan,
        ),
        label: Text(
          i18n.t('node_tab_fastest'),
          style: TextStyle(
            fontSize: 12,
            fontWeight: _sortByLowestLatency ? FontWeight.bold : FontWeight.normal,
            color: _sortByLowestLatency ? Colors.black : Colors.white70,
          ),
        ),
        selectedColor: AppTheme.primaryCyan,
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: _sortByLowestLatency ? AppTheme.primaryCyan : AppTheme.darkBorder,
          ),
        ),
        onSelected: (val) => setState(() => _sortByLowestLatency = val),
      ),
      const SizedBox(width: 8),
      for (final continent in _continents) ...[
        ChoiceChip(
          selected: !_favoritesOnly && _selectedContinent == continent,
          label: Text(
            _continentLabel(continent),
            style: TextStyle(
              fontSize: 12,
              fontWeight: (!_favoritesOnly && _selectedContinent == continent) ? FontWeight.bold : FontWeight.normal,
              color: (!_favoritesOnly && _selectedContinent == continent) ? Colors.black : Colors.white70,
            ),
          ),
          selectedColor: AppTheme.primaryCyan,
          backgroundColor: AppTheme.darkCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: (!_favoritesOnly && _selectedContinent == continent) ? AppTheme.primaryCyan : AppTheme.darkBorder,
            ),
          ),
          onSelected: (val) {
            if (val) {
              setState(() {
                _selectedContinent = continent;
                _favoritesOnly = false;
              });
            }
          },
        ),
        const SizedBox(width: 8),
      ],
    ];
  }

  Widget _buildNodeItemCard({
    required NodeModel node,
    required bool isSelected,
    required bool isDesktop,
  }) {
    final isFav = node.isFavorite;

    return InkWell(
      onTap: () {
        widget.subscriptionEngine.selectNode(node);
        widget.onNodeSelected?.call(node);
        if (!widget.isEmbedded) {
          Navigator.of(context).pop();
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 10 : 12,
          vertical: isDesktop ? 8 : 10,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryCyan.withOpacity(0.12)
              : AppTheme.darkCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryCyan.withOpacity(0.85)
                : AppTheme.darkBorder,
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primaryCyan.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            // 收藏切換星星
            IconButton(
              icon: Icon(
                isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                color: isFav ? Colors.amberAccent : Colors.white30,
                size: 19,
              ),
              splashRadius: 14,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
              onPressed: () async {
                await widget.subscriptionEngine.toggleFavorite(node.id);
              },
            ),
            const SizedBox(width: 4),

            // 國旗彩色向量徽章
            CountryFlagBadge(node: node, size: const Size(22, 15)),
            const SizedBox(width: 10),

            // 節點名稱與協定標籤 (給予充足空間，加 Tooltip 保障全稱無礙)
            Expanded(
              child: Tooltip(
                message: node.name,
                waitDuration: const Duration(milliseconds: 500),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      node.cleanDisplayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        fontSize: 13,
                        letterSpacing: 0.2,
                      ),
                    ),
                      const SizedBox(height: 3),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            // 協定微型膠囊
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                node.protocol.toUpperCase(),
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            // 地區文字
                            Text(
                              node.localizedRegionName(I18nService.instance.currentCode),
                              maxLines: 1,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.45),
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(width: 8),

            // 延遲徽章 (選中狀態已由外框霓虹高亮清晰呈現，不再額外擠壓節點標題寬度)
            _buildLatencyBadge(node),
          ],
        ),
      ),
    );
  }

  Widget _buildLatencyBadge(NodeModel node) {
    final i18n = I18nService.instance;
    Color color;
    switch (node.latencyGrade) {
      case 'excellent':
        color = AppTheme.successEmerald;
        break;
      case 'good':
        color = AppTheme.primaryCyan;
        break;
      case 'medium':
        color = AppTheme.warningAmber;
        break;
      case 'bad':
        color = AppTheme.accentRose;
        break;
      default:
        color = Colors.white.withOpacity(0.4);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        node.latencyMs == null
            ? '-- ms'
            : (node.latencyMs! < 0 ? i18n.t('node_timeout') : '${node.latencyMs} ms'),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
