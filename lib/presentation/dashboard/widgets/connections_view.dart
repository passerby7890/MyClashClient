// lib/presentation/dashboard/widgets/connections_view.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/i18n/i18n_service.dart';
import '../../../infrastructure/core_daemon/core_daemon.dart';

/// 天河網絡 即時活動連線監控視圖 (ConnectionsView)
/// 呈現 Mihomo / Clash.Meta 核心即時網絡活動連線狀態
class ConnectionsView extends StatefulWidget {
  final CoreDaemon coreDaemon;

  const ConnectionsView({
    super.key,
    required this.coreDaemon,
  });

  @override
  State<ConnectionsView> createState() => _ConnectionsViewState();
}

class _ConnectionsViewState extends State<ConnectionsView> {
  Timer? _refreshTimer;
  List<Map<String, dynamic>> _connections = [];
  bool _isLoading = false;
  int _uploadTotal = 0;
  int _downloadTotal = 0;
  String _searchFilter = '';

  // 賽博主題調色盤
  static const Color _cardBg = Color(0xFF151E31);
  static const Color _cardInnerBg = Color(0xFF101726);
  static const Color _borderColor = Color(0xFF1E2D4A);
  static const Color _neonBlue = Color(0xFF0EA5E9);
  static const Color _neonCyan = Color(0xFF00D2FF);
  static const Color _emeraldGreen = Color(0xFF10B981);
  static const Color _roseRed = Color(0xFFF43F5E);
  static const Color _textMuted = Color(0xFF94A3B8);

  HttpClient? _persistentClient;

  HttpClient _getClient() {
    if (_persistentClient == null) {
      _persistentClient = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      _persistentClient!.findProxy = (uri) => 'DIRECT';
    }
    return _persistentClient!;
  }

  @override
  void initState() {
    super.initState();
    _fetchConnections();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted && widget.coreDaemon.state.isConnected) {
        _fetchConnections();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _persistentClient?.close(force: true);
    _persistentClient = null;
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
      final client = _getClient();
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:9090/connections'));
      if (widget.coreDaemon.controllerSecret.isNotEmpty) {
        req.headers.set('Authorization', 'Bearer ${widget.coreDaemon.controllerSecret}');
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
      } else {
        await resp.drain();
      }
    } catch (_) {
      // 核心可能處於待機或重啟中，保持現狀
    }
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
          SnackBar(content: Text(i18n.t('conn_close_error', {'error': e.toString()}))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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

    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _borderColor, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 頂部標題與總覽列
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _neonBlue.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.bolt_rounded, color: _neonCyan, size: 22),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    i18n.t('conn_title'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    isConnected
                        ? i18n.t('conn_subtitle_active', {
                            'count': '${_connections.length}',
                            'down': _formatBytes(_downloadTotal),
                            'up': _formatBytes(_uploadTotal),
                          })
                        : i18n.t('conn_subtitle_idle'),
                    style: const TextStyle(color: _textMuted, fontSize: 12),
                  ),
                ],
              ),
              const Spacer(),
              // 搜尋框
              SizedBox(
                width: 200,
                height: 36,
                child: TextField(
                  onChanged: (val) => setState(() => _searchFilter = val),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: i18n.t('conn_search_hint'),
                    hintStyle: const TextStyle(color: _textMuted, fontSize: 12),
                    prefixIcon: const Icon(Icons.search_rounded, size: 16, color: _textMuted),
                    filled: true,
                    fillColor: _cardInnerBg,
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _neonBlue),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // 中斷全部按鈕
              FilledButton.icon(
                onPressed: (isConnected && _connections.isNotEmpty && !_isLoading)
                    ? _closeAllConnections
                    : null,
                icon: const Icon(Icons.close_rounded, size: 16),
                label: Text(i18n.t('conn_close_all')),
                style: FilledButton.styleFrom(
                  backgroundColor: _roseRed.withOpacity(0.85),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // 表頭
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: _cardInnerBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _borderColor, width: 0.8),
            ),
            child: Row(
              children: [
                Expanded(flex: 3, child: Text(i18n.t('conn_th_dest'), style: const TextStyle(color: _textMuted, fontSize: 12, fontWeight: FontWeight.bold))),
                Expanded(flex: 1, child: Text(i18n.t('conn_th_protocol'), style: const TextStyle(color: _textMuted, fontSize: 12, fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text(i18n.t('conn_th_rule'), style: const TextStyle(color: _textMuted, fontSize: 12, fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text(i18n.t('conn_th_outbound'), style: const TextStyle(color: _textMuted, fontSize: 12, fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text(i18n.t('conn_th_traffic'), style: const TextStyle(color: _textMuted, fontSize: 12, fontWeight: FontWeight.bold))),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // 連線清單
          Expanded(
            child: !isConnected
                ? _buildIdlePlaceholder(i18n.t('conn_idle_placeholder'))
                : filtered.isEmpty
                    ? _buildIdlePlaceholder(_searchFilter.isEmpty ? i18n.t('conn_empty_active') : i18n.t('conn_empty_search'))
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final conn = filtered[index];
                          final meta = conn['metadata'] as Map<String, dynamic>? ?? {};
                          final host = meta['host']?.toString().isNotEmpty == true
                              ? '${meta['host']}:${meta['destinationPort']}'
                              : '${meta['destinationIP']}:${meta['destinationPort']}';
                          final network = meta['network']?.toString().toUpperCase() ?? 'TCP';
                          final rule = conn['rule']?.toString() ?? 'Match';
                          final chains = (conn['chains'] as List<dynamic>?)?.join(' → ') ?? 'DIRECT';
                          final upload = conn['upload'] as int? ?? 0;
                          final download = conn['download'] as int? ?? 0;

                          return Container(
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: _cardInnerBg.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: _borderColor.withOpacity(0.5), width: 0.6),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    host,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    child: Text(
                                      network,
                                      style: TextStyle(
                                        color: network == 'UDP' ? const Color(0xFFA78BFA) : _neonCyan,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    rule,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: _emeraldGreen, fontSize: 12),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    chains,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: _textMuted, fontSize: 12),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    '↓ ${_formatBytes(download)} / ↑ ${_formatBytes(upload)}',
                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace'),
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
    );
  }

  Widget _buildIdlePlaceholder(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_tethering_off_rounded, size: 48, color: _textMuted.withOpacity(0.4)),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(color: _textMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
