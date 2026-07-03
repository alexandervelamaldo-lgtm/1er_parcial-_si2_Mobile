import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';


class AiConsentStatus {
  const AiConsentStatus({
    required this.consent,
    required this.consentedAt,
  });

  final bool consent;
  final DateTime? consentedAt;

  factory AiConsentStatus.fromJson(Map<String, dynamic> json) {
    final raw = json['consented_at'];
    DateTime? parsed;
    if (raw is String && raw.isNotEmpty) {
      parsed = DateTime.tryParse(raw);
    }
    return AiConsentStatus(
      consent: json['consent'] == true,
      consentedAt: parsed,
    );
  }
}


class AiVoiceIntentResult {
  const AiVoiceIntentResult({
    required this.action,
    required this.confidence,
    required this.parameters,
    required this.reply,
  });

  final String action;
  final double confidence;
  final Map<String, dynamic> parameters;
  final String reply;

  factory AiVoiceIntentResult.fromJson(Map<String, dynamic> json) {
    return AiVoiceIntentResult(
      action: (json['action'] as String?)?.trim() ?? 'ayuda',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.4,
      parameters: (json['parameters'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{},
      reply: (json['reply'] as String?)?.trim() ?? 'No entendí el comando.',
    );
  }
}

class AiChatMessage {
  const AiChatMessage({required this.role, required this.content});

  final String role; // 'user' | 'assistant'
  final String content;

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}


class AiChatResult {
  const AiChatResult({
    required this.reply,
    required this.provider,
    required this.model,
    required this.latencyMs,
  });

  final String reply;
  final String provider;
  final String model;
  final int latencyMs;

  factory AiChatResult.fromJson(Map<String, dynamic> json) {
    return AiChatResult(
      reply: (json['reply'] as String?)?.trim() ?? '',
      provider: (json['provider'] as String?) ?? '',
      model: (json['model'] as String?) ?? '',
      latencyMs: (json['latency_ms'] as num?)?.toInt() ?? 0,
    );
  }
}


class AiChatException implements Exception {
  const AiChatException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}


class AiVoiceReportNarrationResult {
  const AiVoiceReportNarrationResult({
    required this.narration,
  });

  final String narration;

  factory AiVoiceReportNarrationResult.fromJson(Map<String, dynamic> json) {
    return AiVoiceReportNarrationResult(
      narration: (json['narration'] as String?)?.trim() ?? '',
    );
  }
}


class AiService {
  AiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Uri _uri(String path) {
    final base = AppConfig.apiBaseUrl.replaceAll(RegExp(r'\/+$'), '');
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$normalizedPath');
  }

  Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  Future<AiConsentStatus> getConsent(String token) async {
    final res = await _client.get(_uri('/ai/consent'), headers: _headers(token));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('No se pudo consultar el consentimiento IA.');
    }
    return AiConsentStatus.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<AiConsentStatus> setConsent(String token, bool consent) async {
    final res = await _client.post(
      _uri('/ai/consent'),
      headers: _headers(token),
      body: jsonEncode({'consent': consent}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('No se pudo guardar el consentimiento IA.');
    }
    return AiConsentStatus.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<AiVoiceIntentResult> voiceIntent({
    required String token,
    required String transcript,
    Map<String, dynamic>? context,
  }) async {
    final res = await _client.post(
      _uri('/ai/voice/intent'),
      headers: _headers(token),
      body: jsonEncode({
        'transcript': transcript,
        'context': context ?? const <String, dynamic>{},
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('No se pudo interpretar el comando.');
    }
    return AiVoiceIntentResult.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<AiChatResult> chat({
    required String token,
    required String message,
    List<AiChatMessage> history = const <AiChatMessage>[],
  }) async {
    final res = await _client.post(
      _uri('/ai/chat'),
      headers: _headers(token),
      body: jsonEncode({
        'message': message,
        'history': history.map((m) => m.toJson()).toList(growable: false),
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String detail = 'No se pudo contactar al asistente. Intenta de nuevo en unos momentos.';
      try {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is Map && decoded['detail'] is String) {
          final s = (decoded['detail'] as String).trim();
          if (s.isNotEmpty) detail = s;
        }
      } catch (_) {}
      throw AiChatException(detail, statusCode: res.statusCode);
    }
    return AiChatResult.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<AiVoiceReportNarrationResult> voiceReportNarration({
    required String token,
    required String reportName,
    required String format,
    required Map<String, dynamic> stats,
    List<String>? highlights,
    String audience = 'operaciones',
    String period = 'today',
  }) async {
    final res = await _client.post(
      _uri('/ai/voice-report/narration'),
      headers: _headers(token),
      body: jsonEncode({
        'report_name': reportName,
        'period': period,
        'format': format,
        'audience': audience,
        'highlights': highlights ?? const <String>[],
        'stats': stats,
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('No se pudo generar la narración.');
    }
    return AiVoiceReportNarrationResult.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  void dispose() {
    _client.close();
  }
}
