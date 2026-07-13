import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config/app_config.dart';


/// Metadata del adjunto de audio de un mensaje (si aplica).
class SolicitudChatAudioInfo {
  const SolicitudChatAudioInfo({
    required this.contentType,
    required this.sizeBytes,
    required this.url,
    this.durationMs,
  });

  final String contentType;
  final int sizeBytes;
  final int? durationMs;
  /// URL relativa al backend (ej. "/solicitudes/29/chat/audio/42").
  /// El caller la resuelve a absoluta con [ChatSolicitudService.audioAbsoluteUrl].
  final String url;

  factory SolicitudChatAudioInfo.fromJson(Map<String, dynamic> json) {
    return SolicitudChatAudioInfo(
      contentType: (json['content_type'] as String?) ?? 'audio/mp4',
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      durationMs: (json['duration_ms'] as num?)?.toInt(),
      url: (json['url'] as String?) ?? '',
    );
  }
}


/// Un mensaje del chat cliente ↔ técnico/taller de una solicitud.
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
    this.audio,
  });

  final int id;
  final int solicitudId;
  final int senderUserId;
  final String senderRole; // 'cliente' | 'tecnico' | 'taller'
  final String senderDisplayName;
  final String content;
  final DateTime createdAt;
  final DateTime? readAt;
  final SolicitudChatAudioInfo? audio;

  factory SolicitudChatMessage.fromJson(Map<String, dynamic> json) {
    final createdRaw = json['created_at'] as String?;
    final readRaw = json['read_at'] as String?;
    final audioRaw = json['audio'];
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
      audio: audioRaw is Map<String, dynamic>
          ? SolicitudChatAudioInfo.fromJson(audioRaw)
          : null,
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

  /// Sube una nota de voz al chat como multipart.
  ///
  /// - [file]: archivo local generado por el paquete `record` (típicamente
  ///   `.m4a` con codec AAC-LC).
  /// - [contentType]: MIME del archivo. Debe estar en la whitelist del
  ///   backend (`audio/mp4`, `audio/webm`, etc.).
  /// - [durationMs]: opcional pero muy recomendado. Sin duración, el
  ///   receptor tiene que decodear el audio para conocerla — con este
  ///   valor la muestra directo en la burbuja.
  /// - [tenantKey]: idem que en `listar` — el X-Tenant es necesario si
  ///   el cliente vive en un tenant distinto al de la solicitud.
  Future<SolicitudChatMessage> enviarAudio({
    required String token,
    required int solicitudId,
    required File file,
    required String contentType,
    int? durationMs,
    String? tenantKey,
  }) async {
    // MultipartRequest arma el body con boundary automáticamente. NO
    // debemos poner Content-Type nosotros — http lo genera con el
    // boundary correcto (`multipart/form-data; boundary=...`).
    final req = http.MultipartRequest(
      'POST',
      _uri('/solicitudes/$solicitudId/chat/audio'),
    );
    req.headers.addAll(_headers(token, tenantKey)
      ..remove('Content-Type')
      ..remove('Accept'));
    req.headers['Accept'] = 'application/json';

    if (durationMs != null && durationMs > 0) {
      req.fields['duration_ms'] = durationMs.toString();
    }
    // El nombre del field ('archivo') debe coincidir con el parámetro
    // `File(...)` del endpoint FastAPI. MediaType.parse maneja MIMEs con
    // parámetros (`audio/webm;codecs=opus` no rompe).
    req.files.add(
      await http.MultipartFile.fromPath(
        'archivo',
        file.path,
        contentType: MediaType.parse(contentType),
      ),
    );

    final streamed = await _client.send(req);
    final res = await http.Response.fromStream(streamed);
    _ensureOk(res);
    return SolicitudChatMessage.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  /// Descarga los bytes de una nota de voz.
  ///
  /// Por qué bytes y no streaming: `audioplayers` con `UrlSource` NO
  /// acepta pasar headers custom en Android (limitación del ExoPlayer
  /// subyacente). Como necesitamos mandar `Authorization` (endpoint
  /// autenticado), la alternativa práctica es descargar todo el blob y
  /// reproducirlo con `BytesSource`. Los audios son chicos (<2 MB), el
  /// overhead es despreciable.
  Future<List<int>> descargarAudioBytes({
    required String token,
    required int solicitudId,
    required int messageId,
    String? tenantKey,
  }) async {
    final res = await _client.get(
      _uri('/solicitudes/$solicitudId/chat/audio/$messageId'),
      headers: _headers(token, tenantKey),
    );
    _ensureOk(res);
    return res.bodyBytes;
  }

  /// Convierte una URL relativa (`/solicitudes/.../chat/audio/N`) en absoluta.
  String audioAbsoluteUrl(String relative) {
    if (relative.isEmpty) return '';
    if (relative.startsWith('http://') || relative.startsWith('https://')) {
      return relative;
    }
    final base = AppConfig.apiBaseUrl.replaceAll(RegExp(r'\/+$'), '');
    final path = relative.startsWith('/') ? relative : '/$relative';
    return '$base$path';
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
