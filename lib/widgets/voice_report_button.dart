import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:provider/provider.dart';

import '../providers/session_provider.dart';
import '../services/ai_service.dart';
import '../services/tts_service.dart';
import '../services/voice_report/report_generator.dart';
import '../services/voice_report/sample_emergencies.dart';
import '../services/voice_report/voice_command_parser.dart';

/// Widget reusable: escucha comandos tipo "reporte hoy pdf/excel" y genera el archivo localmente.
class VoiceReportButton extends StatefulWidget {
  const VoiceReportButton({super.key});

  @override
  State<VoiceReportButton> createState() => _VoiceReportButtonState();
}

class _VoiceReportButtonState extends State<VoiceReportButton> with SingleTickerProviderStateMixin {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  final AiService _ai = AiService();
  final TtsService _tts = TtsService();

  bool _supported = true;
  bool _listening = false;
  bool _busy = false;
  String _transcript = '';
  String? _error;

  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    try {
      await _notifications.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: (resp) async {
          final payload = resp.payload;
          if (payload != null && payload.trim().isNotEmpty) {
            await OpenFilex.open(payload.trim());
          }
        },
      );

      final android = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          'reports',
          'Reportes',
          description: 'Reportes generados localmente',
          importance: Importance.high,
        ),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _pulse.dispose();
    _ai.dispose();
    _tts.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    setState(() => _error = null);

    if (_busy) return;

    if (_listening) {
      await _stopListening();
      return;
    }

    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      setState(() => _error = 'Permiso de micrófono denegado.');
      return;
    }

    final available = await _speech.initialize(
      onError: (_) => setState(() => _error = 'Falló el reconocimiento de voz.'),
      onStatus: (_) {},
    );
    if (!available) {
      setState(() {
        _supported = false;
        _error = 'Reconocimiento de voz no disponible en este dispositivo.';
      });
      return;
    }

    setState(() {
      _supported = true;
      _listening = true;
      _transcript = '';
    });
    _pulse.repeat(reverse: true);

    await _speech.listen(
      listenOptions: stt.SpeechListenOptions(
        localeId: 'es_ES',
        listenMode: stt.ListenMode.confirmation,
        partialResults: true,
        cancelOnError: true,
      ),
      onResult: (res) async {
        final text = res.recognizedWords;
        if (!mounted) return;
        setState(() => _transcript = text);

        final cmd = parseVoiceReportCommand(text);
        if (cmd == null) return;

        await _stopListening();
        await _generate(cmd.format, narrate: cmd.narrate);
      },
    );
  }

  Future<void> _stopListening() async {
    try {
      await _speech.stop();
    } catch (_) {}
    if (!mounted) return;
    _pulse.stop();
    setState(() => _listening = false);
  }

  Map<String, dynamic> _summarize(List<EmergencyReportRow> rows) {
    final byType = <String, int>{};
    final byStatus = <String, int>{};
    final locations = <String>[];
    for (final r in rows) {
      byType[r.tipoIncidente] = (byType[r.tipoIncidente] ?? 0) + 1;
      byStatus[r.estadoServicio] = (byStatus[r.estadoServicio] ?? 0) + 1;
      if (r.ubicacion.isNotEmpty && locations.length < 6 && !locations.contains(r.ubicacion)) {
        locations.add(r.ubicacion);
      }
    }
    List<String> top(Map<String, int> m) {
      final entries = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      return entries.take(3).map((e) => '${e.key} (${e.value})').toList(growable: false);
    }
    return {
      'total': rows.length,
      'topType': top(byType),
      'topStatus': top(byStatus),
      'locations': locations.take(4).toList(growable: false),
    };
  }

  Future<void> _narrateIfNeeded(List<EmergencyReportRow> rows, {required String format}) async {
    final token = context.read<SessionProvider>().token;
    if (token == null || token.isEmpty) return;
    try {
      final consent = await _ai.getConsent(token);
      if (!consent.consent) return;
    } catch (_) {
      return;
    }
    try {
      final stats = _summarize(rows);
      final highlights = <String>[
        'Total de registros: ${stats['total']}',
        'Top incidentes: ${(stats['topType'] as List).join(', ')}',
        'Estados: ${(stats['topStatus'] as List).join(', ')}',
      ];
      final narration = await _ai.voiceReportNarration(
        token: token,
        reportName: 'Emergencias',
        format: format,
        stats: stats,
        highlights: highlights,
      );
      if (narration.narration.trim().isEmpty) return;
      await _tts.speak(narration.narration);
    } catch (_) {
      return;
    }
  }

  Future<void> _generate(VoiceReportFormat format, {required bool narrate}) async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await Permission.storage.request();
      final rows = buildTodayEmergencyDataset();
      final ReportFileResult out = switch (format) {
        VoiceReportFormat.pdf => await generatePdfReport(rows),
        VoiceReportFormat.excel => await generateExcelReport(rows),
        VoiceReportFormat.txt => await generateTxtReport(rows),
      };

      await _notifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'Reporte generado',
        'Se guardó el archivo. Toca para abrirlo.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'reports',
            'Reportes',
            channelDescription: 'Reportes generados localmente',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: out.path,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reporte guardado: ${out.path}'),
          action: SnackBarAction(label: 'Abrir', onPressed: () => OpenFilex.open(out.path)),
        ),
      );
      if (narrate) {
        await _narrateIfNeeded(
          rows,
          format: format == VoiceReportFormat.pdf ? 'pdf' : (format == VoiceReportFormat.excel ? 'excel' : 'txt'),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo generar el reporte. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _listening ? Colors.red : Theme.of(context).colorScheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reportes por voz', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text('Di: "reporte hoy pdf", "informe de hoy excel" o "reporte hoy txt".'),
            const SizedBox(height: 10),
            Row(
              children: [
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) {
                    final t = _listening ? (0.85 + 0.25 * _pulse.value) : 1.0;
                    return Transform.scale(
                      scale: t,
                      child: IconButton.filled(
                        onPressed: _supported ? _toggle : null,
                        icon: Icon(_listening ? Icons.stop : Icons.mic),
                        style: IconButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
                        tooltip: _listening ? 'Detener' : 'Hablar',
                      ),
                    );
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _busy
                        ? 'Generando…'
                        : _listening
                            ? 'Escuchando…'
                            : 'Listo',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _transcript.isEmpty ? 'Transcripción: —' : 'Transcripción: $_transcript',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.tonal(
                  onPressed: _busy ? null : () => _generate(VoiceReportFormat.pdf, narrate: false),
                  child: const Text('Generar PDF'),
                ),
                FilledButton.tonal(
                  onPressed: _busy ? null : () => _generate(VoiceReportFormat.excel, narrate: false),
                  child: const Text('Generar Excel'),
                ),
                FilledButton.tonal(
                  onPressed: _busy ? null : () => _generate(VoiceReportFormat.txt, narrate: false),
                  child: const Text('Generar TXT'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
