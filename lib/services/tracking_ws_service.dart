import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';

// ── Event models ──────────────────────────────────────────────────────────────

class TecnicoLocation {
  const TecnicoLocation({
    required this.tecnicoId,
    required this.lat,
    required this.lng,
    this.updatedAt,
    required this.disponible,
  });

  final int tecnicoId;
  final double lat;
  final double lng;
  final String? updatedAt;
  final bool disponible;

  factory TecnicoLocation.fromJson(Map<String, dynamic> json) =>
      TecnicoLocation(
        tecnicoId: json['tecnico_id'] as int? ?? json['id'] as int? ?? 0,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        updatedAt: json['updated_at'] as String?,
        disponible: json['disponible'] as bool? ?? false,
      );
}

/// Mensaje entrante del chat cliente ↔ técnico/taller durante una solicitud.
class ChatMessageEvent {
  const ChatMessageEvent({
    required this.solicitudId,
    required this.messageId,
    required this.senderUserId,
    required this.senderRole,
    required this.senderDisplayName,
    required this.content,
    this.createdAt,
    this.audioUrl,
    this.audioContentType,
    this.audioDurationMs,
    this.audioSizeBytes,
  });

  final int solicitudId;
  final int messageId;
  final int senderUserId;
  final String senderRole; // 'cliente' | 'tecnico' | 'taller'
  final String senderDisplayName;
  final String content;
  final String? createdAt;
  final String? audioUrl;
  final String? audioContentType;
  final int? audioDurationMs;
  final int? audioSizeBytes;

  bool get hasAudio => (audioUrl != null && audioUrl!.isNotEmpty);

  factory ChatMessageEvent.fromJson(Map<String, dynamic> json) {
    final msg = (json['message'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final audio = (msg['audio'] as Map?)?.cast<String, dynamic>();
    return ChatMessageEvent(
      solicitudId: (json['solicitud_id'] as num?)?.toInt() ?? 0,
      messageId: (msg['id'] as num?)?.toInt() ?? 0,
      senderUserId: (msg['sender_user_id'] as num?)?.toInt() ?? 0,
      senderRole: (msg['sender_role'] as String?) ?? 'cliente',
      senderDisplayName: (msg['sender_display_name'] as String?) ?? '',
      content: (msg['content'] as String?) ?? '',
      createdAt: msg['created_at'] as String?,
      audioUrl: audio?['url'] as String?,
      audioContentType: audio?['content_type'] as String?,
      audioDurationMs: (audio?['duration_ms'] as num?)?.toInt(),
      audioSizeBytes: (audio?['size_bytes'] as num?)?.toInt(),
    );
  }
}


class SolicitudWsUpdate {
  const SolicitudWsUpdate({
    required this.solicitudId,
    required this.estado,
    this.tallerId,
    this.tecnicoId,
    this.updatedAt,
    this.extra,
  });

  final int solicitudId;
  final String estado;
  final int? tallerId;
  final int? tecnicoId;
  final String? updatedAt;
  final Map<String, dynamic>? extra;

  factory SolicitudWsUpdate.fromJson(Map<String, dynamic> json) =>
      SolicitudWsUpdate(
        solicitudId: json['solicitud_id'] as int,
        estado: json['estado'] as String? ?? '',
        tallerId: json['taller_id'] as int?,
        tecnicoId: json['tecnico_id'] as int?,
        updatedAt: json['updated_at'] as String?,
        extra: json['extra'] as Map<String, dynamic>?,
      );
}

// ── Service ───────────────────────────────────────────────────────────────────

/// Observable real-time tracking service backed by a WebSocket connection.
///
/// Register as a [ChangeNotifierProvider] in the widget tree:
///   ```dart
///   ChangeNotifierProvider(create: (_) => TrackingWsService()),
///   ```
/// Then listen to its streams or call [tecnicoLocations] from a widget.
class TrackingWsService extends ChangeNotifier {
  TrackingWsService();

  // ── Public streams ─────────────────────────────────────────────────────────

  final StreamController<TecnicoLocation> _locationController =
      StreamController.broadcast();
  final StreamController<SolicitudWsUpdate> _solicitudController =
      StreamController.broadcast();
  final StreamController<void> _kpiRefreshController =
      StreamController.broadcast();
  final StreamController<ChatMessageEvent> _chatMessageController =
      StreamController.broadcast();

  /// Emits every time a technician's location changes.
  Stream<TecnicoLocation> get locationStream => _locationController.stream;

  /// Emits every time a solicitud state changes.
  Stream<SolicitudWsUpdate> get solicitudStream => _solicitudController.stream;

  /// Emits when the server broadcasts a KPI cache refresh.
  Stream<void> get kpiRefreshStream => _kpiRefreshController.stream;

  /// Emits every incoming chat_message from any solicitud the user
  /// participates in. Listeners filter by [solicitudId].
  Stream<ChatMessageEvent> get chatMessageStream => _chatMessageController.stream;

  // ── Observable state ───────────────────────────────────────────────────────

  bool _connected = false;
  Map<int, TecnicoLocation> _tecnicoLocations = {};

  bool get connected => _connected;

  /// Latest known position for each technician, keyed by tecnico_id.
  Map<int, TecnicoLocation> get tecnicoLocations =>
      Map.unmodifiable(_tecnicoLocations);

  // ── Internal ──────────────────────────────────────────────────────────────

  WebSocket? _socket;
  String? _token;
  /// Tenant key sent in the WebSocket handshake. The backend hub uses it
  /// to broadcast events only to clients of the same tenant. Defaults to
  /// 'default' for backwards-compat; [connect] updates it.
  String _tenant = 'default';
  bool _disposed = false;
  bool _reconnectEnabled = false;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  int _reconnectDelay = 2; // seconds, doubles up to _maxDelay
  static const int _maxDelay = 30;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Connect (or reconnect) using [token] for authentication.
  ///
  /// Safe to call multiple times — previous connection is closed first.
  Future<void> connect(String token, {String tenant = 'default'}) async {
    _token = token;
    final trimmed = tenant.trim();
    _tenant = trimmed.isEmpty ? 'default' : trimmed;
    _reconnectDelay = 2;
    _reconnectEnabled = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _connect();
  }

  /// Disconnect and stop reconnection attempts.
  Future<void> disconnect() async {
    _reconnectEnabled = false;
    _stopTimers();
    await _socket?.close(WebSocketStatus.normalClosure);
    _socket = null;
    _setConnected(false);
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectEnabled = false;
    _stopTimers();
    _socket?.close(WebSocketStatus.normalClosure);
    _locationController.close();
    _solicitudController.close();
    _kpiRefreshController.close();
    _chatMessageController.close();
    super.dispose();
  }

  // ── Internal connection logic ─────────────────────────────────────────────

  Future<void> _connect() async {
    if (_disposed || !_reconnectEnabled || _token == null) return;

    try {
      // Convert HTTP base URL to WebSocket URL.
      final wsBase = AppConfig.apiBaseUrl
          .replaceFirst('https://', 'wss://')
          .replaceFirst('http://', 'ws://');
      // Include the tenant query param so the backend hub partitions the
      // connection. Without this the hub falls back to the `default` tenant
      // and a Tenant A client could receive Tenant B's broadcasts.
      final uri = '$wsBase/realtime/tracking'
          '?access_token=${Uri.encodeQueryComponent(_token!)}'
          '&tenant=${Uri.encodeQueryComponent(_tenant)}';

      _socket = await WebSocket.connect(uri)
          .timeout(const Duration(seconds: 10));

      _reconnectDelay = 2; // reset on successful connect
      _setConnected(true);
      _startPing();

      _socket!.listen(
        _onMessage,
        onDone: _onDisconnected,
        onError: (_) => _onDisconnected(),
        cancelOnError: true,
      );
    } catch (_) {
      _setConnected(false);
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final type = msg['type'] as String?;
    switch (type) {
      case 'init':
        final tecnicos = msg['tecnicos'] as List<dynamic>? ?? [];
        final Map<int, TecnicoLocation> locations = {};
        for (final t in tecnicos) {
          final loc = TecnicoLocation.fromJson(t as Map<String, dynamic>);
          locations[loc.tecnicoId] = loc;
        }
        _tecnicoLocations = locations;
        notifyListeners();
        break;

      case 'location_update':
        final loc = TecnicoLocation.fromJson(msg);
        _tecnicoLocations = {..._tecnicoLocations, loc.tecnicoId: loc};
        _locationController.add(loc);
        notifyListeners();
        break;

      case 'solicitud_update':
        final update = SolicitudWsUpdate.fromJson(msg);
        _solicitudController.add(update);
        break;

      case 'kpi_refresh':
        _kpiRefreshController.add(null);
        break;

      case 'chat_message':
        _chatMessageController.add(ChatMessageEvent.fromJson(msg));
        break;

      case 'pong':
        // Keepalive acknowledged — no action needed.
        break;
    }
  }

  void _onDisconnected() {
    if (_disposed) return;
    _setConnected(false);
    _stopTimers();
    if (_reconnectEnabled) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || !_reconnectEnabled || _token == null) return;
    _reconnectTimer = Timer(Duration(seconds: _reconnectDelay), _connect);
    // Exponential back-off, capped at _maxDelay.
    _reconnectDelay = (_reconnectDelay * 2).clamp(2, _maxDelay);
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      try {
        _socket?.add(jsonEncode({'type': 'ping'}));
      } catch (_) {}
    });
  }

  void _stopTimers() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _setConnected(bool connected) {
    if (_connected == connected) return;
    _connected = connected;
    notifyListeners();
  }
}
