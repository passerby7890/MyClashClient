// lib/presentation/profile/knowledge_screen.dart

import 'package:flutter/material.dart';
import '../../core/network/dio_client.dart';
import '../../core/i18n/i18n_service.dart';
import '../../core/theme/app_theme.dart';

/// 文檔中心 (KnowledgeScreen)
/// 1:1 對齊截圖 5：分類文件夾卡片、藍色頂部標籤條、文章數量徽章、文檔列表與詳情檢視
/// 統一深色科技風 (Dark Tech Material 3)，杜絕白屏風格不一致
class KnowledgeScreen extends StatefulWidget {
  final DioClient dioClient;

  const KnowledgeScreen({super.key, required this.dioClient});

  @override
  State<KnowledgeScreen> createState() => _KnowledgeScreenState();
}

class _KnowledgeScreenState extends State<KnowledgeScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  // 分類字典: {"必读": [文章1, ...], "Android": [文章2, ...]}
  Map<String, List<Map<String, dynamic>>> _categoryArticles = {};

  @override
  void initState() {
    super.initState();
    _fetchKnowledge();
  }

  Future<void> _fetchKnowledge() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final i18n = I18nService.instance;
    final primaryLang = i18n.apiLanguageCode;

    try {
      // 1. 首選使用當前介面語言代碼查詢
      var fetched = await _requestKnowledge(primaryLang);

      // 2. 若後台該語系無文檔 (空字典)，自動降級為 zh-CN 兜底，確保文檔不空白
      if (fetched.isEmpty && primaryLang != 'zh-CN') {
        fetched = await _requestKnowledge('zh-CN');
      }

      if (mounted) {
        setState(() {
          _categoryArticles = fetched;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  Future<Map<String, List<Map<String, dynamic>>>> _requestKnowledge(String lang) async {
    final resp = await widget.dioClient.get(
      '/api/v1/user/knowledge/fetch',
      queryParameters: {'language': lang},
    );

    final result = <String, List<Map<String, dynamic>>>{};
    if (resp.data is Map && resp.data['data'] != null) {
      final rawData = resp.data['data'];

      // 情況 A: V2Board 標準分組 Map: {"必读": [...], "Android": [...]}
      if (rawData is Map) {
        rawData.forEach((catKey, artList) {
          if (artList is List) {
            final items = artList.whereType<Map<String, dynamic>>().toList();
            if (items.isNotEmpty) {
              result[catKey.toString()] = items;
            }
          }
        });
      }
      // 情況 B: 扁平列表 List: [{"category": "必读", ...}, ...]
      else if (rawData is List) {
        for (final item in rawData) {
          if (item is Map<String, dynamic>) {
            final cat = (item['category'] ?? '通用文檔').toString();
            result.putIfAbsent(cat, () => []).add(item);
          }
        }
      }
    }
    return result;
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return '';
    int ts = 0;
    if (timestamp is int) {
      ts = timestamp;
    } else if (timestamp is String) {
      ts = int.tryParse(timestamp) ?? 0;
    }
    if (ts <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    return '${dt.year}-$month-$day';
  }

  /// 移除簡易 HTML 標籤並還原格式
  String _stripHtml(String html) {
    var text = html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'</li>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<h[1-6]>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'</h[1-6]>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"');
    return text.trim();
  }

  Future<void> _openArticleReader(Map<String, dynamic> article) async {
    final title = article['title']?.toString() ?? '文檔詳情';
    final articleId = article['id'];
    final date = _formatTimestamp(article['updated_at'] ?? article['created_at']);

    // 顯示載入等待 BottomSheet
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _ArticleDetailModal(
        dioClient: widget.dioClient,
        articleId: articleId,
        fallbackTitle: title,
        fallbackDate: date,
        initialBody: article['body']?.toString(),
        stripHtml: _stripHtml,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18nService.instance;

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        title: Text(
          i18n.t('nav_docs'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.cyanAccent),
            tooltip: i18n.t('refresh'),
            onPressed: _fetchKnowledge,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.cyanAccent));
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
              const SizedBox(height: 12),
              Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _fetchKnowledge,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.cyanAccent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('重新整理', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );
    }

    if (_categoryArticles.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_rounded, size: 64, color: Colors.white.withOpacity(0.2)),
            const SizedBox(height: 12),
            Text('暫無文檔資料', style: TextStyle(fontSize: 15, color: Colors.white.withOpacity(0.5))),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: _categoryArticles.entries.map((entry) {
        final categoryName = entry.key;
        final list = entry.value;

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AppTheme.darkCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              // 頂部分類標籤條 (1:1 對齊截圖 5: 藍色漸層背景條 + 資料夾圖標 + 數量膠囊)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF2563EB), Color(0xFF60A5FA)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(17)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.folder_rounded, size: 20, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      categoryName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${list.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 文章列表 (1:1 對齊截圖 5: 藍色圓角方形圖標 + 文章標題 + 2025-06-14 日期 + 右箭頭)
              ...list.asMap().entries.map((itemEntry) {
                final index = itemEntry.key;
                final article = itemEntry.value;
                final title = article['title']?.toString() ?? '未命名文章';
                final dateStr = _formatTimestamp(article['updated_at'] ?? article['created_at']);
                final isLast = index == list.length - 1;

                return InkWell(
                  onTap: () => _openArticleReader(article),
                  borderRadius: isLast
                      ? const BorderRadius.vertical(bottom: Radius.circular(18))
                      : BorderRadius.zero,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      border: isLast
                          ? null
                          : Border(
                              bottom: BorderSide(
                                color: Colors.white.withOpacity(0.06),
                                width: 0.8,
                              ),
                            ),
                    ),
                    child: Row(
                      children: [
                        // 文章圖標 (1:1 對齊截圖 5: 淺藍底色 + 深藍文檔 icon)
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3B82F6).withOpacity(0.18),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF60A5FA).withOpacity(0.3)),
                          ),
                          child: const Icon(
                            Icons.article_rounded,
                            size: 18,
                            color: Color(0xFF93C5FD),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (dateStr.isNotEmpty) ...[
                                const SizedBox(height: 5),
                                Row(
                                  children: [
                                    Icon(Icons.access_time_rounded, size: 12, color: Colors.white.withOpacity(0.4)),
                                    const SizedBox(width: 4),
                                    Text(
                                      dateStr,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: Colors.white.withOpacity(0.5),
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white.withOpacity(0.3),
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// 文檔詳情閱讀器彈窗
class _ArticleDetailModal extends StatefulWidget {
  final DioClient dioClient;
  final dynamic articleId;
  final String fallbackTitle;
  final String fallbackDate;
  final String? initialBody;
  final String Function(String) stripHtml;

  const _ArticleDetailModal({
    required this.dioClient,
    required this.articleId,
    required this.fallbackTitle,
    required this.fallbackDate,
    required this.initialBody,
    required this.stripHtml,
  });

  @override
  State<_ArticleDetailModal> createState() => _ArticleDetailModalState();
}

class _ArticleDetailModalState extends State<_ArticleDetailModal> {
  bool _loading = false;
  String _title = '';
  String _body = '';
  String _date = '';

  @override
  void initState() {
    super.initState();
    _title = widget.fallbackTitle;
    _date = widget.fallbackDate;
    if (widget.initialBody != null && widget.initialBody!.isNotEmpty) {
      _body = widget.stripHtml(widget.initialBody!);
    } else {
      _fetchDetail();
    }
  }

  Future<void> _fetchDetail() async {
    setState(() => _loading = true);
    final i18n = I18nService.instance;
    try {
      final resp = await widget.dioClient.get(
        '/api/v1/user/knowledge/fetch',
        queryParameters: {
          'id': widget.articleId,
          'language': i18n.apiLanguageCode,
        },
      );
      if (resp.data is Map && resp.data['data'] != null) {
        final data = resp.data['data'] as Map<String, dynamic>;
        setState(() {
          _title = data['title']?.toString() ?? widget.fallbackTitle;
          _body = widget.stripHtml(data['body']?.toString() ?? '暫無文檔內容');
          _loading = false;
        });
        return;
      }
    } catch (_) {
      // 降級嘗試 zh-CN
      try {
        final resp = await widget.dioClient.get(
          '/api/v1/user/knowledge/fetch',
          queryParameters: {
            'id': widget.articleId,
            'language': 'zh-CN',
          },
        );
        if (resp.data is Map && resp.data['data'] != null) {
          final data = resp.data['data'] as Map<String, dynamic>;
          setState(() {
            _title = data['title']?.toString() ?? widget.fallbackTitle;
            _body = widget.stripHtml(data['body']?.toString() ?? '暫無文檔內容');
            _loading = false;
          });
          return;
        }
      } catch (_) {}
    }
    setState(() {
      _body = '暫無法讀取文檔內容，請檢查網路連線後重試。';
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (_date.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '更新時間: $_date',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.white.withOpacity(0.08)),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.cyanAccent))
                : SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(20),
                    child: SelectableText(
                      _body,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.7,
                        color: Colors.white.withOpacity(0.85),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
