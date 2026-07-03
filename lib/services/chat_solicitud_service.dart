import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';


/// Un mensaje del chat cliente ↔ técnico de una solicitud.
class SolicitudChatMessage {
  const SolicitudChatMessage({
    required this.id,
    required this.solicitudId,
    required this.senderUserId,
    required this.senderRole,
    required this.senderDisplayName,
    required this.content,
    required this.createdAt,
    this.readAt,
  });

  final int id;
  final int solicitudId;
  final int senderUserId;
  final String senderRole; // 'cliente' | 'tecnico'
  final String senderDisplayName;
  final String content;
  final DateTime createdAt;
  final DateTime? readAt;

  factory SolicitudChatMessage.fromJson(Map<String, dynamic> json) {
    final createdRaw = json['created_at'] as String?;
    final readRaw = json['read_at'] as String?;
    return SolicitudChatMessage(
      id: (json['id'] as num?)?.toInt() ?? 0,
      solicitudId: (json['solicitud_id'] as num?)?.toInt() ?? 0,
      senderUserId: (json['sender_user_id'] as num?)?.toInt() ?? 0,
      senderRole: (json['sender_role'] as String?) ?? 'cliente',
      senderDisplayName: (json['sender_display_name'] as String?) ?? '',
      content: (json['content'] as String?) ?? '',
      createdAt: createdRaw != null
          ? (DateTime.tryParse(createdRaw)?.toLocal() ?? DateTime.now())
          : DateTime.now(),
      readAt: readRaw != null ? DateTime.tryParse(readRaw)?.toLocal() : null,
    );
  }
}


class ChatSolicitudException implements Exception {
  const ChatSolicitudException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}


class ChatSolicitudService {
  ChatSolicitudService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Uri _uri(String path) {
    final base = AppConfig.apiBaseUrl.replaceAll(RegExp(r'\/+$'), '');
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$normalized');
  }

  Map<String, String> _headers(String token, String? tenantKey) {
    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    // Multi-tenant: la solicitud puede vivir en la DB del taller (tenant
    // distinto al del cliente). El caller nos pasa el tenantKey correcto
    // para que el backend enrute la request a la DB adecuada.
    final tk = (tenantKey ?? '').trim();
    if (tk.isNotEmpty) headers['X-Tenant'] = tk;
    return headers;
  }

  Future<List<SolicitudChatMessage>> listar({
    required String token,
    required int solicitudId,
    String? tenantKey,
    int? sinceId,
  }) async {
    final query = sinceId != null ? '?since_id=$sinceId' : '';
    final res = await _client.get(
      _uri('/solicitudes/$solicitudId/chat/messages$query'),
      headers: _headers(token, tenantKey),
    );
    _ensureOk(res);
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final raw = (data['messages'] as List?) ?? const <dynamic>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(SolicitudChatMessage.fromJson)
        .toList(growable: false);
  }

  Future<SolicitudChatMessage> enviar({
    required String token,
    required int solicitudId,
    required String content,
    String? tenantKey,
  }) async {
    final res = await _client.post(
      _uri('/solicitudes/$solicitudId/chat/messages'),
      headers: _headers(token, tenantKey),
      body: jsonEncode({'content': content}),
    );
    _ensureOk(res);
    return SolicitudChatMessage.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<int> marcarLeidos({
    required String token,
    required int solicitudId,
    String? tenantKey,
  }) async {
    final res = await _client.post(
      _uri('/solicitudes/$solicitudId/chat/read'),
      headers: _headers(token, tenantKey),
    );
    _ensureOk(res);
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return (data['marked'] as num?)?.toInt() ?? 0;
  }

  void dispose() {
    _client.close();
  }

  void _ensureOk(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    String detail = 'No se pudo procesar el chat.';
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map && decoded['detail'] is String) {
        final s = (decoded['detail'] as String).trim();
        if (s.isNotEmpty) detail = s;
      }
    } catch (_) {}
    throw ChatSolicitudException(detail, statusCode: res.statusCode);
  }
}
