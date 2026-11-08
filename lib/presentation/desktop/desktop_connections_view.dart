// lib/presentation/desktop/desktop_connections_view.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import '../../core/i18n/i18n_service.dart';
import '../../core/utils/error_sanitizer.dart';
import '../../infrastructure/core_daemon/core_daemon.dart';
import 'desktop_theme_tokens.dart';

/// 專職實時連接視圖 (DesktopConnectionsView)
/// 100% 綁定 4 國語言字典的桌面全寬表格視圖
class DesktopConnectionsView extends StatefulWidget {
  final CoreDaemon coreDaemon;

  const DesktopConnectionsView({
    super.key,
    required this.coreDaemon,
  });

  @override
  State<DesktopConnectionsView> createState() => _DesktopConnectionsViewState();
}

class _DesktopConnectionsViewState extends State<DesktopConnectionsView> {
  Timer? _refreshTimer;
  List<Map<String, dynamic>> _connections = [];
  bool _isLoading = false;
  int _uploadTotal = 0;
  int _downloadTotal = 0;
  String _searchFilter = '';

  @override
  void initState() {
    super.initState();
    _fetchConnections();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) _fetchConnections();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchConnections() async {
    if (!widget.coreDaemon.state.isConnected) {
      if (mounted && _connections.isNotEmpty) {
        setState(() {
          _connections = [];
          _uploadTotal = 0;
          _downloadTotal = 0;
        });
      }
      return;
    }

    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      client.findProxy = (uri) => 'DIRECT';
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:9090/connections'));
      final secret = widget.coreDaemon.controllerSecret.isNotEmpty
          ? widget.coreDaemon.controllerSecret
          : AppConstants.coreSecret;
      if (secret.isNotEmpty) {
        req.headers.set('Authorization', 'Bearer $secret');
      }
      final resp = await req.close();
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final rawConns = data['connections'] as List<dynamic>? ?? [];
        _uploadTotal = data['uploadTotal'] as int? ?? 0;
        _downloadTotal = data['downloadTotal'] as int? ?? 0;

        final mapped = rawConns.map((c) => c as Map<String, dynamic>).toList();
        if (mounted) {
          setState(() {
            _connections = mapped;
          });
        }
      }
      client.close();
    } catch (_) {}
  }

  Future<void> _closeAllConnections() async {
    setState(() => _isLoading = true);
    final i18n = I18nService.instance;
    try {
      await widget.coreDaemon.closeAllConnections();
      await _fetchConnections();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(i18n.t('conn_closed_all_msg'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(i18n.t('conn_close_error', {'error': ErrorSanitizer.sanitize(e)}))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18nService.instance;
    final isConnected = widget.coreDaemon.state.isConnected;

    final filtered = _connections.where((c) {
      if (_searchFilter.isEmpty) return true;
      final host = c['metadata']?['host']?.toString().toLowerCase() ?? '';
      final destinationIP = c['metadata']?['destinationIP']?.toString().toLowerCase() ?? '';
      return host.contains(_searchFilter.toLowerCase()) || destinationIP.contains(_searchFilter.toLowerCase());
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DesktopThemeTokens.spacing, vertical: 12),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: DesktopThemeTokens.cardBg,
          borderRadius: BorderRadius.circular(DesktopThemeTokens.cardRadius),
          border: Border.all(color: DesktopThemeTokens.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 頂部標題與總覽工具列
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: DesktopThemeTokens.neonCyan.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.hub_rounded, color: DesktopThemeTokens.neonCyan, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        i18n.t('conn_title'),
                        style: DesktopThemeTokens.titleStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isConnected
                            ? i18n.t('conn_subtitle_active', {
                                'count': '${_connections.length}',
                                'down': _formatBytes(_downloadTotal),
                                'up': _formatBytes(_uploadTotal),
                              })
                            : i18n.t('conn_subtitle_idle'),
                        style: DesktopThemeTokens.subtitleStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // 搜尋框
                Container(
                  width: 160,
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
                          onChanged: (val) => setState(() => _searchFilter = val.trim()),
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          decoration: InputDecoration(
                            hintText: i18n.t('conn_search_hint'),
                            hintStyle: const TextStyle(color: DesktopThemeTokens.textMuted, fontSize: 11),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // 中斷全部連線按鈕
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DesktopThemeTokens.roseRed.withOpacity(0.18),
                    foregroundColor: DesktopThemeTokens.roseRed,
                    side: BorderSide(color: DesktopThemeTokens.roseRed.withOpacity(0.4)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: isConnected && _connections.isNotEmpty && !_isLoading
                      ? _closeAllConnections
                      : null,
                  icon: _isLoading
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: DesktopThemeTokens.roseRed))
                      : const Icon(Icons.close_rounded, size: 16),
                  label: Text(i18n.t('conn_close_all'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 表格標頭
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: DesktopThemeTokens.cardInnerBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(flex: 4, child: Text(i18n.t('conn_th_dest'), style: DesktopThemeTokens.labelStyle)),
                  Expanded(flex: 2, child: Text(i18n.t('conn_th_protocol'), style: DesktopThemeTokens.labelStyle)),
                  Expanded(flex: 3, child: Text(i18n.t('conn_th_rule'), style: DesktopThemeTokens.labelStyle)),
                  Expanded(flex: 3, child: Text(i18n.t('conn_th_outbound'), style: DesktopThemeTokens.labelStyle)),
                  Expanded(flex: 3, child: Text(i18n.t('conn_th_traffic'), style: DesktopThemeTokens.labelStyle)),
                ],
              ),
            ),
            const SizedBox(height: 6),

            // 表格內容列表
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        isConnected ? i18n.t('conn_no_active') : i18n.t('conn_subtitle_idle'),
                        style: const TextStyle(color: DesktopThemeTokens.textMuted, fontSize: 13),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, idx) {
                        final conn = filtered[idx];
                        final meta = conn['metadata'] as Map<String, dynamic>? ?? {};
                        final host = meta['host']?.toString().isNotEmpty == true
                            ? meta['host'].toString()
                            : (meta['destinationIP']?.toString() ?? 'Unknown');
                        final port = meta['destinationPort']?.toString() ?? '';
                        final network = meta['network']?.toString().toUpperCase() ?? 'TCP';
                        final rule = conn['rule']?.toString() ?? 'Direct';
                        final chains = (conn['chains'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
                        final exitNode = chains.isNotEmpty ? chains.first : (conn['rulePayload']?.toString() ?? 'Proxy');
                        final upload = conn['upload'] as int? ?? 0;
                        final download = conn['download'] as int? ?? 0;

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: DesktopThemeTokens.borderSubtle, width: 0.8),
                            ),
                          ),
                          child: Row(
                            children: [
                              // 目標主機 / 端口
                              Expanded(
                                flex: 4,
                                child: Text(
                                  port.isNotEmpty ? '$host:$port' : host,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white),
                                ),
                              ),
                              // 網路協議
                              Expanded(
                                flex: 2,
                                child: Text(
                                  network,
                                  style: const TextStyle(fontSize: 12, color: DesktopThemeTokens.neonCyan),
                                ),
                              ),
                              // 匹配規則
                              Expanded(
                                flex: 3,
                                child: Text(
                                  rule,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, color: DesktopThemeTokens.textSecondary),
                                ),
                              ),
                              // 出口節點
                              Expanded(
                                flex: 3,
                                child: Text(
                                  exitNode,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, color: DesktopThemeTokens.emeraldGreen),
                                ),
                              ),
                              // 傳輸流量
                              Expanded(
                                flex: 3,
                                child: Text(
                                  '↓ ${_formatBytes(download)} · ↑ ${_formatBytes(upload)}',
                                  style: const TextStyle(fontSize: 11.5, color: DesktopThemeTokens.textMuted, fontFamily: 'Segoe UI'),
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
    );
  }
}
