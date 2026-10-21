// lib/presentation/dashboard/widgets/notice_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../business/auth/notice_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/i18n/i18n_service.dart';

/// 機場彈窗公告對話框 (對齊 Tianhe 3.0 彈窗功能)
class NoticeDialog extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final cleanText = notice.cleanContent;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
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
                      notice.title,
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
                    child: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                  ),
                ],
              ),
            ),

            // 內文區域
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      cleanText,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 若包含優惠代碼或機器人，提供快捷複製按鈕
                    if (cleanText.contains('buyback') || cleanText.contains('@THJSQBOT')) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.darkSurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.darkBorder),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.card_giftcard_rounded, color: Color(0xFFFFA000), size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  '${I18nService.instance.t('notice_coupon_prefix')}buyback',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                            TextButton(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () {
                                Clipboard.setData(const ClipboardData(text: 'buyback'));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(I18nService.instance.t('notice_coupon_copied')),
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                              },
                              child: Text(I18nService.instance.t('copy_btn'), style: const TextStyle(color: AppTheme.primaryCyan)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // 底部操作列
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
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
