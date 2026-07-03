import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../providers/session_provider.dart';
import '../services/api_service.dart';

// ── Command model ─────────────────────────────────────────────────────────────

enum _ReportFormat { pdf, csv, txt }

class _VoiceCommand {
  const _VoiceCommand({required this.format, this.narrate = false});
  final _ReportFormat format;
  final bool narrate;
}

// ── Command parser (mirrors the Angular voice-command.parser.ts) ──────────────

_VoiceCommand? _parseCommand(String raw) {
  // Normalize: lowercase, remove accents, collapse spaces
  final text = raw
      .toLowerCase()
      .replaceAll(RegExp(r'[áàä]'), 'a')
      .replaceAll(RegExp(r'[éèë]'), 'e')
      .replaceAll(RegExp(r'[íìï]'), 'i')
      .replaceAll(RegExp(r'[óòö]'), 'o')
      .replaceAll(RegExp(r'[úùü]'), 'u')
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r' +'), ' ')
      .trim();

  if (text.isEmpty) return null;

  // ── Intent: report/generate keyword ───────────────────────────────────────
  final reportWords = [
    'reporte', 'informe', 'generar', 'genera', 'generame', 'dame',
    'crea', 'crear', 'exportar', 'exporta', 'hazme', 'haz',
    'mostrar', 'muestra', 'necesito', 'quiero', 'hacer',
  ];
  final hasReport = reportWords.any((w) => text.contains(w));

  // ── Time: today keyword ────────────────────────────────────────────────────
  final hasToday =
      text.contains('hoy') ||
      text.contains('del dia') ||
      text.contains('de hoy') ||
      text.contains('hoy dia') ||
      text.contains('diario') ||
      text.contains('actual');

  // ── Format detection ───────────────────────────────────────────────────────
  final wantsPdf   = text.contains('pdf');
  final wantsCsv   = text.contains('excel') || text.contains('csv') || text.contains('xlsx');
  final wantsTxt   = text.contains('txt') || text.contains('texto');
  final hasFormat  = wantsPdf || wantsCsv || wantsTxt;
  final wantsVoice = text.contains('voz') || text.contains('narrar') || text.contains('leer') || text.contains('audio');

  if ((!hasReport && !hasFormat) || !hasToday) return null;

  if (wantsPdf)  return _VoiceCommand(format: _ReportFormat.pdf,  narrate: wantsVoice);
  if (wantsCsv)  return _VoiceCommand(format: _ReportFormat.csv,  narrate: wantsVoice);
  if (wantsTxt)  return _VoiceCommand(format: _ReportFormat.txt,  narrate: wantsVoice);
  return null;
}

// ── Screen ────────────────────────────────────────────────────────────────────

class VoiceReportScreen extends StatefulWidget {
  const VoiceReportScreen({super.key});

  @override
  State<VoiceReportScreen> createState() => _VoiceReportScreenState();
}

class _VoiceReportScreenState extends State<VoiceReportScreen> {
  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _sttAvailable = false;
  bool _listening = false;
  bool _busy = false;
  String _transcript = '';
  String _interim = '';
  String _statusMessage = 'Toca el micrófono y di un comando';
  _VoiceCommand? _lastCommand;
  String? _lastFilePath;

  @override
  void initState() {
    super.initState();
    _initStt();
    _tts.setLanguage('es-ES');
    _tts.setSpeechRate(0.5);
  }

  Future<void> _initStt() async {
    final available = await _stt.initialize(
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _listening = false;
          _statusMessage = 'Error: ${e.errorMsg}. Verifica el micrófono.';
        });
      },
    );
    if (mounted) setState(() => _sttAvailable = available);
  }

  @override
  void dispose() {
    _stt.stop();
    _tts.stop();
    super.dispose();
  }

  // ── Mic toggle ──────────────────────────────────────────────────────────────

  Future<void> _toggleMic() async {
    if (_listening) {
      await _stt.stop();
      setState(() => _listening = false);
      return;
    }
    if (!_sttAvailable) {
      setState(() => _statusMessage = 'Reconocimiento de voz no disponible en este dispositivo');
      return;
    }
    setState(() {
      _transcript = '';
      _interim = '';
      _lastCommand = null;
      _statusMessage = 'Escuchando…';
      _listening = true;
    });
    await _stt.listen(
      onResult: _onSpeechResult,
      listenOptions: SpeechListenOptions(
        localeId: 'es_ES',
        listenFor: const Duration(seconds: 15),
        pauseFor: const Duration(seconds: 3),
      ),
    );
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (!mounted) return;
    setState(() {
      if (result.finalResult) {
        _transcript = result.recognizedWords;
        _interim = '';
        _listening = false;
        _statusMessage = 'Transcripción completa';
      } else {
        _interim = result.recognizedWords;
      }
    });

    // Auto-execute when a final result arrives
    if (result.finalResult) {
      final cmd = _parseCommand(result.recognizedWords);
      if (cmd != null) {
        setState(() => _lastCommand = cmd);
        _executeCommand(cmd);
      } else {
        setState(() => _statusMessage = 'No reconocí un comando. Di "génrame el PDF de hoy"');
      }
    }
  }

  // ── Command execution ───────────────────────────────────────────────────────

  Future<void> _executeCommand(_VoiceCommand cmd) async {
    switch (cmd.format) {
      case _ReportFormat.pdf:   await _generatePdf(narrate: cmd.narrate);
      case _ReportFormat.csv:   await _generateCsv(narrate: cmd.narrate);
      case _ReportFormat.txt:   await _generateTxt(narrate: cmd.narrate);
    }
  }

  Future<void> _generatePdf({bool narrate = false}) async {
    await _withBusy('Generando PDF…', () async {
      final token = context.read<SessionProvider>().token!;
      final api = context.read<ApiService>();
      final bytes = await api.descargarTrabajosPdf(token: token);
      final path = await _saveTmp('trabajos_realizados.pdf', bytes);
      setState(() => _lastFilePath = path);
      await OpenFilex.open(path);
      if (narrate) await _narrate('Reporte PDF generado y abierto correctamente.');
    });
  }

  Future<void> _generateCsv({bool narrate = false}) async {
    await _withBusy('Generando Excel/CSV…', () async {
      final token = context.read<SessionProvider>().token!;
      final api = context.read<ApiService>();
      final bytes = await api.descargarTrabajosCsv(token: token);
      final path = await _saveTmp('trabajos_realizados.csv', bytes);
      setState(() => _lastFilePath = path);
      await OpenFilex.open(path);
      if (narrate) await _narrate('Reporte Excel generado y abierto correctamente.');
    });
  }

  Future<void> _generateTxt({bool narrate = false}) async {
    await _withBusy('Generando TXT…', () async {
      final token = context.read<SessionProvider>().token!;
      final api = context.read<ApiService>();
      final data = await api.getTrabajosRealizados(token: token);
      final txt = _buildTxt(data);
      final bytes = txt.codeUnits;
      final path = await _saveTmp('trabajos_realizados.txt', bytes);
      setState(() => _lastFilePath = path);
      await OpenFilex.open(path);
      if (narrate) await _narrate('Reporte de texto generado. $txt');
    });
  }

  String _buildTxt(Map<String, dynamic> data) {
    final resumen = data['resumen'] as Map<String, dynamic>? ?? {};
    final items = (data['items'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final buf = StringBuffer();
    buf.writeln('REPORTE — TRABAJOS REALIZADOS');
    buf.writeln('Fecha: ${DateTime.now().toLocal().toString().substring(0, 10)}');
    buf.writeln('─' * 40);
    buf.writeln('Cantidad de trabajos : ${resumen['cantidad_trabajos'] ?? 0}');
    buf.writeln('Total facturado      : Bs ${resumen['total_facturado'] ?? 0}');
    buf.writeln('Total comisión       : Bs ${resumen['total_comision'] ?? 0}');
    buf.writeln('Total taller         : Bs ${resumen['total_taller'] ?? 0}');
    buf.writeln('Promedio por trabajo : Bs ${resumen['promedio_por_trabajo'] ?? 0}');
    buf.writeln('─' * 40);
    for (final item in items) {
      buf.writeln(
        '#${item['solicitud_id']} | ${item['fecha_cierre']?.toString().substring(0, 10)} | '
        '${item['cliente']} | ${item['taller']} | Bs ${item['monto_total']}',
      );
    }
    return buf.toString();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  Future<void> _withBusy(String msg, Future<void> Function() fn) async {
    if (!mounted) return;
    setState(() { _busy = true; _statusMessage = msg; });
    try {
      await fn();
      if (mounted) setState(() => _statusMessage = 'Listo ✓');
    } catch (e) {
      if (mounted) setState(() => _statusMessage = 'Error: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _saveTmp(String filename, List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> _narrate(String text) async {
    await _tts.speak(text);
  }

  String _formatLabel(_ReportFormat f) => switch (f) {
    _ReportFormat.pdf  => 'PDF',
    _ReportFormat.csv  => 'Excel/CSV',
    _ReportFormat.txt  => 'TXT',
  };

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Reporte por voz')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Hint card ──────────────────────────────────────────────────
            Card(
              color: cs.primaryContainer.withValues(alpha: 0.4),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.mic, color: cs.primary, size: 20),
                      const SizedBox(width: 8),
                      Text('Comandos de voz',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: 8),
                    const Text('"génrame el PDF de hoy"'),
                    const Text('"exporta el Excel de hoy"'),
                    const Text('"dame el TXT de hoy"'),
                    const SizedBox(height: 4),
                    Text('Añade "con voz" para narración.',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── Status ─────────────────────────────────────────────────────
            _InfoRow(label: 'Estado', value: _statusMessage),
            if (_transcript.isNotEmpty || _interim.isNotEmpty)
              _InfoRow(
                label: 'Transcripción',
                value: _transcript.isNotEmpty ? _transcript : _interim,
                muted: _transcript.isEmpty,
              ),
            if (_lastCommand != null)
              _InfoRow(
                label: 'Comando',
                value: 'Hoy · ${_formatLabel(_lastCommand!.format)}'
                    '${_lastCommand!.narrate ? ' · con voz' : ''}',
              ),
            if (_lastFilePath != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => OpenFilex.open(_lastFilePath!),
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text('Abrir archivo generado'),
              ),
            ],

            const Spacer(),

            // ── Manual buttons ─────────────────────────────────────────────
            Text('Generar manualmente',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant, letterSpacing: 1)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _QuickBtn(
                label: 'PDF', icon: Icons.picture_as_pdf_outlined,
                onTap: _busy ? null : () => _generatePdf(),
              )),
              const SizedBox(width: 10),
              Expanded(child: _QuickBtn(
                label: 'Excel', icon: Icons.table_chart_outlined,
                onTap: _busy ? null : () => _generateCsv(),
              )),
              const SizedBox(width: 10),
              Expanded(child: _QuickBtn(
                label: 'TXT', icon: Icons.text_snippet_outlined,
                onTap: _busy ? null : () => _generateTxt(),
              )),
            ]),

            const SizedBox(height: 20),

            // ── Mic button ─────────────────────────────────────────────────
            SizedBox(
              height: 64,
              child: FilledButton.icon(
                onPressed: _busy ? null : _toggleMic,
                style: FilledButton.styleFrom(
                  backgroundColor: _listening ? Colors.red : cs.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                icon: _busy
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Icon(_listening ? Icons.stop : Icons.mic, size: 28),
                label: Text(
                  _busy ? 'Procesando…' : _listening ? 'Detener' : 'Hablar',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Aux widgets ───────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.muted = false});
  final String label;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 13,
                    color: muted ? Colors.grey : null,
                    fontStyle: muted ? FontStyle.italic : FontStyle.normal)),
          ),
        ],
      ),
    );
  }
}

class _QuickBtn extends StatelessWidget {
  const _QuickBtn({required this.label, required this.icon, this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
