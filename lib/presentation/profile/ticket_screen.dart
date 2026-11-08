// lib/presentation/profile/ticket_screen.dart

import 'package:flutter/material.dart';
import '../../core/i18n/i18n_service.dart';
import '../../core/network/dio_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/error_sanitizer.dart';

/// 我的工單 (TicketScreen)
/// 統一深色科技風 (Dark Tech Material 3)，與主控台及個人中心風格完全一致
class TicketScreen extends StatefulWidget {
  final DioClient dioClient;

  const TicketScreen({super.key, required this.dioClient});

  @override
  State<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends State<TicketScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _tickets = [];

  @override
  void initState() {
    super.initState();
    _fetchTickets();
  }

  Future<void> _fetchTickets() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final resp = await widget.dioClient.get('/api/v1/user/ticket/fetch');
      if (resp.data is Map && resp.data['data'] is List) {
        final list = (resp.data['data'] as List).whereType<Map<String, dynamic>>().toList();
        setState(() {
          _tickets = list;
          _isLoading = false;
        });
      } else {
        setState(() {
          _tickets = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = ErrorSanitizer.sanitize(e);
          _isLoading = false;
        });
      }
    }
  }

  /// 彈出「創建工單」彈窗 (深色科技主題風格)
  Future<void> _showCreateTicketDialog() async {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    int priority = 1; // 1: 低, 2: 中, 3: 高
    bool isSubmitting = false;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 500),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.darkCard,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
                boxShadow: const [
                  BoxShadow(color: Colors.black45, blurRadius: 24, offset: Offset(0, 10)),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  Text(
                    I18nService.instance.t('ticket_create'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 18),

                  // 工單標題
                  TextField(
                    controller: titleController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: I18nService.instance.t('ticket_title'),
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 14),
                      filled: true,
                      fillColor: AppTheme.darkBackground,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.cyanAccent, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 優先級選擇
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: AppTheme.darkBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.12)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: priority,
                        isExpanded: true,
                        dropdownColor: AppTheme.darkCard,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        items: [
                          DropdownMenuItem(value: 1, child: Text(I18nService.instance.t('ticket_priority_low'))),
                          DropdownMenuItem(value: 2, child: Text(I18nService.instance.t('ticket_priority_med'))),
                          DropdownMenuItem(value: 3, child: Text(I18nService.instance.t('ticket_priority_high'))),
                        ],
                        onChanged: (val) {
                          if (val != null) setDialogState(() => priority = val);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 工單內容
                  TextField(
                    controller: contentController,
                    maxLines: 4,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: I18nService.instance.t('ticket_content'),
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 14),
                      filled: true,
                      fillColor: AppTheme.darkBackground,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.cyanAccent, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),

                  // 按鈕區 (取消 / 創建)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                        child: Text(I18nService.instance.t('cancel'), style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.cyanAccent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                final title = titleController.text.trim();
                                final message = contentController.text.trim();
                                if (title.isEmpty || message.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(I18nService.instance.t('ticket_fill_fields'))),
                                  );
                                  return;
                                }

                                setDialogState(() => isSubmitting = true);
                                try {
                                  await widget.dioClient.post(
                                    '/api/v1/user/ticket/save',
                                    data: {
                                      'subject': title,
                                      'level': priority,
                                      'message': message,
                                    },
                                  );
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  _fetchTickets();
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(I18nService.instance.t('ticket_created_success'))),
                                    );
                                  }
                                } catch (e) {
                                  setDialogState(() => isSubmitting = false);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('${I18nService.instance.t('ticket_create_failed_prefix')}${ErrorSanitizer.sanitize(e)}')),
                                    );
                                  }
                                }
                              },
                        child: isSubmitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                              )
                            : Text(I18nService.instance.t('ticket_submit'), style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: I18nService.instance,
      builder: (context, _) {
        final i18n = I18nService.instance;
        return Scaffold(
          backgroundColor: AppTheme.darkBackground,
          appBar: AppBar(
            title: Text(i18n.t('profile_ticket'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: AppTheme.cyanAccent),
                onPressed: _fetchTickets,
              ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: _buildBody(),
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: AppTheme.cyanAccent,
            foregroundColor: Colors.black,
            elevation: 4,
            onPressed: _showCreateTicketDialog,
            icon: const Icon(Icons.add_rounded, size: 20),
            label: Text(I18nService.instance.t('ticket_create'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        );
      },
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
                onPressed: _fetchTickets,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.cyanAccent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(I18nService.instance.t('refresh'), style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );
    }

    if (_tickets.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.confirmation_number_outlined, size: 64, color: Colors.white.withOpacity(0.2)),
            const SizedBox(height: 14),
            Text(I18nService.instance.t('ticket_empty'), style: TextStyle(fontSize: 15, color: Colors.white.withOpacity(0.6))),
            const SizedBox(height: 8),
            Text(I18nService.instance.t('ticket_empty_hint'), style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.4))),
          ],
        ),
      );
    }

    final i18n = I18nService.instance;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      itemCount: _tickets.length,
      itemBuilder: (context, index) {
        final ticket = _tickets[index];
        final id = ticket['id'];
        final subject = ticket['subject'] ?? '#$id';
        final status = ticket['status'] ?? 0; // 0: 待處理/處理中, 1: 已關閉
        final replyStatus = ticket['reply_status'] ?? 0;
        final level = ticket['level'] ?? 1;

        final isClosed = status == 1;
        final statusText = isClosed
            ? i18n.t('ticket_status_closed')
            : (replyStatus == 1 ? i18n.t('ticket_status_replied') : i18n.t('ticket_status_pending'));
        final statusColor = isClosed
            ? Colors.grey
            : (replyStatus == 1 ? const Color(0xFF10B981) : AppTheme.cyanAccent);

        final priorityLabel = level == 3
            ? i18n.t('ticket_priority_high')
            : (level == 2 ? i18n.t('ticket_priority_med') : i18n.t('ticket_priority_low'));

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.darkCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      priorityLabel,
                      style: const TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Spacer(),
                  Text('#$id', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                subject,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
