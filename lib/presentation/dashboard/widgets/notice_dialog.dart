// lib/presentation/dashboard/widgets/notice_dialog.dart

import 'package:flutter/material.dart';
import '../../../business/auth/notice_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/i18n/i18n_service.dart';
import '../../widgets/html_announcement_renderer.dart';

/// 機場彈窗公告對話框 (支援原生 HTML 富文本、Emoji 原色呈現與超連結跳轉)
class NoticeDialog extends StatefulWidget {
  final NoticeModel notice;

  const NoticeDialog({
    super.key,
    required this.notice,
  });

  static Future<void> show(BuildContext context, NoticeModel notice) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => NoticeDialog(notice: notice),
    );
  }

  @override
  State<NoticeDialog> createState() => _NoticeDialogState();
}

class _NoticeDialogState extends State<NoticeDialog> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 優先使用原始 HTML 內容，若為空則降級至 cleanContent
    final htmlContent = widget.notice.content.isNotEmpty
        ? widget.notice.content
        : widget.notice.cleanContent;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: AppTheme.darkCard,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.primaryCyan.withOpacity(0.3), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryCyan.withOpacity(0.15),
              blurRadius: 30,
              spreadRadius: 2,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 頂部漸層標題列
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF0D47A1),
                    AppTheme.primaryCyan.withOpacity(0.8),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Colors.white24,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.campaign_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.notice.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                    ),
                  ),
                ],
              ),
            ),

            // 內文區域 (原生 HTML 富文本 + Emoji + 智慧段落)
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 460),
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                    child: HtmlAnnouncementRenderer(
                      html: htmlContent,
                      defaultTextStyle: const TextStyle(
                        fontSize: 14,
                        height: 1.65,
                        color: Color(0xFFE2E8F0),
                        fontFamilyFallback: HtmlAnnouncementRenderer.emojiFontFallback,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 底部分隔與操作列
            Container(
              decoration: BoxDecoration(
                color: AppTheme.darkCard,
                border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(0.08), width: 1.0),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryCyan,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    I18nService.instance.t('i_understand'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
