// lib/infrastructure/core_daemon/core_state.dart

enum CoreStatus {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error,
}

enum ProxyMode {
  rule,
  global,
  direct,
  tun,
}

extension ProxyModeRoutingExt on ProxyMode {
  String get routingString {
    switch (this) {
      case ProxyMode.global:
        return 'global';
      case ProxyMode.direct:
        return 'direct';
      case ProxyMode.tun:
        return 'tun';
      case ProxyMode.rule:
        return 'rule';
    }
  }

  static ProxyMode fromRoutingString(String mode) {
    switch (mode.toLowerCase()) {
      case 'global':
        return ProxyMode.global;
      case 'direct':
        return ProxyMode.direct;
      case 'tun':
        return ProxyMode.tun;
      default:
        return ProxyMode.rule;
    }
  }
}

/// Mihomo 核心狀態封裝
class CoreState {
  final CoreStatus status;
  final String? activeNodeName;
  final String? errorMessage;
  final DateTime? connectedSince;
  final ProxyMode proxyMode;

  const CoreState({
    required this.status,
    this.activeNodeName,
    this.errorMessage,
    this.connectedSince,
    this.proxyMode = ProxyMode.rule,
  });

  CoreState copyWith({
    CoreStatus? status,
    String? activeNodeName,
    String? errorMessage,
    DateTime? connectedSince,
    ProxyMode? proxyMode,
  }) {
    return CoreState(
      status: status ?? this.status,
      activeNodeName: activeNodeName ?? this.activeNodeName,
      errorMessage: errorMessage ?? this.errorMessage,
      connectedSince: connectedSince ?? this.connectedSince,
      proxyMode: proxyMode ?? this.proxyMode,
    );
  }

  factory CoreState.disconnected({ProxyMode proxyMode = ProxyMode.rule}) =>
      CoreState(status: CoreStatus.disconnected, proxyMode: proxyMode);

  factory CoreState.connecting({String? nodeName, ProxyMode proxyMode = ProxyMode.rule}) => CoreState(
        status: CoreStatus.connecting,
        activeNodeName: nodeName,
        proxyMode: proxyMode,
      );

  factory CoreState.connected({required String nodeName, ProxyMode proxyMode = ProxyMode.rule}) => CoreState(
        status: CoreStatus.connected,
        activeNodeName: nodeName,
        connectedSince: DateTime.now(),
        proxyMode: proxyMode,
      );

  factory CoreState.disconnecting({ProxyMode proxyMode = ProxyMode.rule}) =>
      CoreState(status: CoreStatus.disconnecting, proxyMode: proxyMode);

  factory CoreState.error(String message, {ProxyMode proxyMode = ProxyMode.rule}) => CoreState(
        status: CoreStatus.error,
        errorMessage: message,
        proxyMode: proxyMode,
      );

  bool get isConnected => status == CoreStatus.connected;
  bool get isConnecting => status == CoreStatus.connecting;
  bool get isDisconnected => status == CoreStatus.disconnected;
  bool get isDisconnecting => status == CoreStatus.disconnecting;

  /// 連線時長格式化 (例如 "01:25:40")
  String get connectionDurationFormatted {
    if (connectedSince == null || !isConnected) return '00:00:00';
    final diff = DateTime.now().difference(connectedSince!);
    final hours = diff.inHours.toString().padLeft(2, '0');
    final minutes = (diff.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (diff.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
}
