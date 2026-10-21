// lib/presentation/widgets/update_dialog.dart

import 'package:flutter/material.dart';
import '../../core/i18n/i18n_service.dart';
import '../../infrastructure/updater/in_app_updater.dart';

/// 應用程式更新彈窗 (支援強制更新模式與即時下載進度條)
class UpdateDialog extends StatefulWidget {
  final UpdateCheckResult updateInfo;
  final InAppUpdater updater;

  const UpdateDialog({
    super.key,
    required this.updateInfo,
    required this.updater,
  });

  /// 顯示彈窗靜態捷徑
  static Future<void> show(
    BuildContext context, {
    required UpdateCheckResult updateInfo,
    required InAppUpdater updater,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: !updateInfo.isForceUpdate,
      builder: (ctx) => WillPopScope(
        onWillPop: () async => !updateInfo.isForceUpdate,
        child: UpdateDialog(updateInfo: updateInfo, updater: updater),
      ),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  String _statusMessage = '';
  String? _errorMessage;

  Future<void> _startUpdate() async {
    final url = widget.updateInfo.downloadUrl;
    if (url == null || url.isEmpty) {
      setState(() {
        _errorMessage = I18nService.instance.t('update_no_url');
      });
      return;
    }

    setState(() {
      _isDownloading = true;
      _errorMessage = null;
      _statusMessage = I18nService.instance.t('update_preparing');
    });

    try {
      await widget.updater.downloadAndInstall(
        downloadUrl: url,
        onProgress: (p, msg) {
          if (mounted) {
            setState(() {
              _progress = p;
              _statusMessage = msg;
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isForce = widget.updateInfo.isForceUpdate;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: theme.colorScheme.surface,
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 頂部圖標與標題
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isForce
                        ? Colors.amber.withOpacity(0.15)
                        : theme.colorScheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isForce ? Icons.warning_rounded : Icons.system_update_rounded,
                    color: isForce ? Colors.amber : theme.colorScheme.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isForce ? I18nService.instance.t('update_force_title') : I18nService.instance.t('update_new_title'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'v${widget.updateInfo.currentVersion} -> v${widget.updateInfo.latestVersion}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // 更新日誌
            Text(
              I18nService.instance.t('update_changelog_title'),
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 120),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SingleChildScrollView(
                child: Text(
                  widget.updateInfo.changelog ?? I18nService.instance.t('update_default_changelog'),
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 下載進度條
            if (_isDownloading) ...[
              LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                borderRadius: BorderRadius.circular(6),
                minHeight: 8,
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  _statusMessage,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],

            // 錯誤訊息提示
            if (_errorMessage != null) ...[
              Text(
                _errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.redAccent),
              ),
              const SizedBox(height: 12),
            ],

            // 按鈕列
            if (!_isDownloading)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!isForce)
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(I18nService.instance.t('update_remind_later')),
                    ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _startUpdate,
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: Text(isForce ? I18nService.instance.t('update_now_overwrite') : I18nService.instance.t('update_now_upgrade')),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
