import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../providers/session_provider.dart';
import '../services/chat_solicitud_service.dart';
import '../services/tracking_ws_service.dart';
import '../theme/app_theme.dart';


/// Chat cliente ↔ técnico durante una solicitud activa.
///
/// Se abre como pantalla completa desde el detalle de la solicitud.
/// Hidrata el historial vía HTTP y escucha el `chat_message` del
/// `TrackingWsService` para mensajes en vivo.
class SolicitudChatScreen extends StatefulWidget {
  const SolicitudChatScreen({
    super.key,
    required this.solicitudId,
    required this.contraparteLabel,
    this.tenantKey,
    this.readOnly = false,
    this.readOnlyReason,
  });

  final int solicitudId;
  /// Etiqueta del otro lado (ej. 'técnico', 'cliente') para el header.
  final String contraparteLabel;
  /// Tenant al que pertenece la solicitud. Sin esto, requests desde el
  /// cliente (tenant=default) contra una solicitud del taller (llaneros)
  /// dan 404. Se pasa como X-Tenant en cada request.
  final String? tenantKey;
  final bool readOnly;
  final String? readOnlyReason;

  @override
  State<SolicitudChatScreen> createState() => _SolicitudChatScreenState();
}


class _SolicitudChatScreenState extends State<SolicitudChatScreen> {
  final ChatSolicitudService _service = ChatSolicitudService();
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final List<SolicitudChatMessage> _messages = <SolicitudChatMessage>[];
  final AudioRecorder _recorder = AudioRecorder();
  bool _loading = false;
  bool _sending = false;
  bool _recording = false;
  DateTime? _recordingStartedAt;
  Timer? _recordingTicker;
  Duration _recordingElapsed = Duration.zero;
  String? _recordingPath;
  String? _error;
  StreamSubscription<ChatMessageEvent>? _wsSub;
  /// Reproductor único compartido — pausamos el anterior al tocar otro.
  final AudioPlayer _player = AudioPlayer();
  int? _currentlyPlayingMessageId;

  /// Rol del usuario en sesión ('cliente' | 'tecnico' | 'taller') para
  /// decidir qué burbujas dibujar como "mías". En el modelo actual, un
  /// mismo usuario no combina esos roles para una misma solicitud.
  String? _myRoleInChat() {
    final roles = context.read<SessionProvider>().profile?.roles ?? const <String>[];
    if (roles.contains('CLIENTE')) return 'cliente';
    if (roles.contains('TECNICO')) return 'tecnico';
    if (roles.contains('TALLER')) return 'taller';
    return null;
  }

  @override
  void initState() {
    super.initState();
    _wsSub = context.read<TrackingWsService>().chatMessageStream.listen(_onIncoming);
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargarHistorial());
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _service.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _recordingTicker?.cancel();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  void _onIncoming(ChatMessageEvent ev) {
    if (!mounted) return;
    if (ev.solicitudId != widget.solicitudId) return;
    if (_messages.any((m) => m.id == ev.messageId)) return;
    final incoming = SolicitudChatMessage(
      id: ev.messageId,
      solicitudId: ev.solicitudId,
      senderUserId: ev.senderUserId,
      senderRole: ev.senderRole,
      senderDisplayName: ev.senderDisplayName,
      content: ev.content,
      createdAt: ev.createdAt != null
          ? (DateTime.tryParse(ev.createdAt!)?.toLocal() ?? DateTime.now())
          : DateTime.now(),
      audio: ev.hasAudio
          ? SolicitudChatAudioInfo(
              contentType: ev.audioContentType ?? 'audio/mp4',
              sizeBytes: ev.audioSizeBytes ?? 0,
              durationMs: ev.audioDurationMs,
              url: ev.audioUrl!,
            )
          : null,
    );
    setState(() => _messages.add(incoming));
    _scrollAlFinal();
    // Si el mensaje NO lo mandé yo (rol distinto), marcá leído.
    final myRole = _myRoleInChat();
    if (myRole != null && incoming.senderRole != myRole) {
      _marcarLeidos();
    }
  }

  Future<void> _cargarHistorial() async {
    final token = context.read<SessionProvider>().token;
    if (token == null || token.isEmpty) {
      setState(() => _error = 'Necesitás iniciar sesión.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _service.listar(
        token: token,
        solicitudId: widget.solicitudId,
        tenantKey: widget.tenantKey,
      );
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(res);
      });
      _scrollAlFinal();
      _marcarLeidos();
    } on ChatSolicitudException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo cargar el chat.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _enviar() async {
    if (widget.readOnly || _sending) return;
    final texto = _inputCtrl.text.trim();
    if (texto.isEmpty) return;
    final token = context.read<SessionProvider>().token;
    if (token == null || token.isEmpty) {
      setState(() => _error = 'Necesitás iniciar sesión.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final res = await _service.enviar(
        token: token,
        solicitudId: widget.solicitudId,
        content: texto,
        tenantKey: widget.tenantKey,
      );
      if (!mounted) return;
      setState(() {
        if (_messages.every((m) => m.id != res.id)) {
          _messages.add(res);
        }
        _inputCtrl.clear();
      });
      _scrollAlFinal();
    } on ChatSolicitudException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo enviar el mensaje.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _marcarLeidos() async {
    final token = context.read<SessionProvider>().token;
    if (token == null || token.isEmpty) return;
    try {
      await _service.marcarLeidos(
        token: token,
        solicitudId: widget.solicitudId,
        tenantKey: widget.tenantKey,
      );
    } catch (_) {
      // No es crítico — silenciamos.
    }
  }

  // ── Grabación de nota de voz ─────────────────────────────────────────

  /// Arranca la grabación de una nota de voz.
  ///
  /// Requisitos:
  ///   1. Permiso RECORD_AUDIO otorgado (Android). En iOS se pide con la
  ///      key NSMicrophoneUsageDescription del Info.plist.
  ///   2. Directorio temporal accesible (`getTemporaryDirectory`).
  ///
  /// El archivo se guarda en el temp dir con timestamp único. Se borra
  /// solo después del upload exitoso o si el user cancela. En caso de
  /// crash de la app queda huérfano — el SO limpia el temp dir eventual-
  /// mente, no es un problema práctico.
  Future<void> _iniciarGrabacion() async {
    if (widget.readOnly || _recording || _sending) return;

    // Pedimos el permiso PRIMERO con permission_handler porque nos
    // permite distinguir "denegado" de "no otorgado todavía" y mostrar
    // un mensaje amigable. `record.hasPermission()` funciona pero es
    // más opaco en el resultado.
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      if (!mounted) return;
      setState(() => _error = 'Necesitás dar permiso de micrófono para grabar notas de voz.');
      return;
    }
    // Doble check con el propio recorder — cubre casos donde el permiso
    // fue otorgado pero el sistema bloqueó el mic por otra razón (modo
    // low-power, mic ocupado por otra app, etc.).
    if (!await _recorder.hasPermission()) {
      if (!mounted) return;
      setState(() => _error = 'El micrófono no está disponible.');
      return;
    }

    try {
      // getTemporaryDirectory: carpeta que iOS/Android permiten limpiar
      // cuando necesitan espacio. Perfecto para archivos efímeros como
      // este (se sube al server y se borra).
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/chat_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      // AAC-LC a 96kbps es el sweet spot para voz:
      //   - Compatible con <audio> HTML5 (web receptor)
      //   - Bien soportado por audioplayers (móvil receptor)
      //   - ~720 KB por minuto → 2 min entra en el límite de 2 MB del backend
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 96000,
          sampleRate: 44100,
        ),
        path: path,
      );
      _recordingPath = path;
      _recordingStartedAt = DateTime.now();
      _recordingElapsed = Duration.zero;
      _recordingTicker?.cancel();
      _recordingTicker = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (_recordingStartedAt == null) return;
        setState(() {
          _recordingElapsed = DateTime.now().difference(_recordingStartedAt!);
        });
        // Corte de seguridad a 2 min (matches backend _AUDIO_MAX_BYTES).
        if (_recordingElapsed.inSeconds >= 120) {
          _detenerYEnviar();
        }
      });
      if (!mounted) return;
      setState(() {
        _recording = true;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo iniciar la grabación.');
    }
  }

  Future<void> _detenerYEnviar() async {
    if (!_recording) return;
    _recordingTicker?.cancel();
    _recordingTicker = null;
    final duration = _recordingElapsed;
    final path = await _recorder.stop();
    _recordingStartedAt = null;
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recordingElapsed = Duration.zero;
    });

    final effectivePath = path ?? _recordingPath;
    _recordingPath = null;
    if (effectivePath == null) return;
    final file = File(effectivePath);
    if (!await file.exists()) return;

    final token = context.read<SessionProvider>().token;
    if (token == null || token.isEmpty) return;
    setState(() => _sending = true);
    try {
      final msg = await _service.enviarAudio(
        token: token,
        solicitudId: widget.solicitudId,
        file: file,
        contentType: 'audio/mp4',
        durationMs: duration.inMilliseconds > 0 ? duration.inMilliseconds : null,
        tenantKey: widget.tenantKey,
      );
      if (!mounted) return;
      setState(() {
        if (_messages.every((m) => m.id != msg.id)) {
          _messages.add(msg);
        }
      });
      _scrollAlFinal();
    } on ChatSolicitudException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo enviar la nota de voz.');
    } finally {
      if (mounted) setState(() => _sending = false);
      // Limpiamos el archivo temporal.
      try { await file.delete(); } catch (_) {}
    }
  }

  Future<void> _cancelarGrabacion() async {
    if (!_recording) return;
    _recordingTicker?.cancel();
    _recordingTicker = null;
    try {
      final path = await _recorder.stop();
      if (path != null) {
        try { await File(path).delete(); } catch (_) {}
      }
    } catch (_) {}
    _recordingPath = null;
    _recordingStartedAt = null;
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recordingElapsed = Duration.zero;
    });
  }

  // ── Playback de audio recibido ───────────────────────────────────────

  /// Reproduce (o pausa) la nota de voz asociada al mensaje.
  ///
  /// Diseño con un ÚNICO AudioPlayer compartido:
  ///   - Si el user toca otro audio mientras suena uno, el nuevo pisa al
  ///     anterior (`stop()` antes de `play()`). Simula el comportamiento
  ///     de WhatsApp — evita superposición y ambigüedad.
  ///   - Si toca el mismo audio que está sonando, alterna a pausa.
  ///   - Cuando termina naturalmente, `onPlayerComplete` limpia el estado
  ///     para que la burbuja vuelva al ícono ▶.
  ///
  /// Por qué `BytesSource` en vez de URL: `audioplayers` no propaga
  /// headers custom al ExoPlayer en Android, y necesitamos Authorization
  /// para el endpoint del backend. Descargamos con `http` y pasamos los
  /// bytes al player.
  Future<void> _reproducirAudio(SolicitudChatMessage msg) async {
    if (msg.audio == null) return;
    final token = context.read<SessionProvider>().token;
    if (token == null || token.isEmpty) return;

    // Toggle: si ya está reproduciendo este mensaje → pausa.
    if (_currentlyPlayingMessageId == msg.id) {
      await _player.pause();
      setState(() => _currentlyPlayingMessageId = null);
      return;
    }
    try {
      // Cortamos cualquier audio anterior antes de arrancar el nuevo.
      await _player.stop();
      final bytes = await _service.descargarAudioBytes(
        token: token,
        solicitudId: msg.solicitudId,
        messageId: msg.id,
        tenantKey: widget.tenantKey,
      );
      // Uint8List es lo que espera BytesSource — el List<int> devuelto
      // por http.Response.bodyBytes ya es Uint8List en runtime, pero
      // el tipado estático es List<int>, por eso el cast explícito.
      await _player.play(BytesSource(Uint8List.fromList(bytes)));
      if (!mounted) return;
      setState(() => _currentlyPlayingMessageId = msg.id);
      // Escuchamos SOLO el primer evento de fin — con `.first` el
      // future se auto-desuscribe después de una emisión, evita leaks.
      _player.onPlayerComplete.first.then((_) {
        if (!mounted) return;
        setState(() => _currentlyPlayingMessageId = null);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo reproducir la nota de voz.');
    }
  }

  void _scrollAlFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final myRole = _myRoleInChat();
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Chat #${widget.solicitudId}', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(
              'Con el ${widget.contraparteLabel}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (widget.readOnly)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: AppColors.warningLight,
                child: Text(
                  widget.readOnlyReason ??
                      'La solicitud ya no está activa. Solo se muestra el historial.',
                  style: const TextStyle(color: AppColors.warning, fontSize: 12),
                ),
              ),
            Expanded(
              child: _loading && _messages.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? _EmptyChat(contraparte: widget.contraparteLabel)
                      : ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final msg = _messages[index];
                            final esMio = myRole != null && msg.senderRole == myRole;
                            return _MessageBubble(
                              message: msg,
                              esMio: esMio,
                              isPlaying: _currentlyPlayingMessageId == msg.id,
                              onTogglePlay: msg.audio != null ? () => _reproducirAudio(msg) : null,
                            );
                          },
                        ),
            ),
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: AppColors.errorLight,
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.error, fontSize: 12),
                ),
              ),
            if (_recording)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: AppColors.errorLight,
                child: Row(
                  children: [
                    const Icon(Icons.fiber_manual_record, size: 14, color: AppColors.error),
                    const SizedBox(width: 8),
                    Text(
                      'Grabando… ${_formatDuration(_recordingElapsed)}',
                      style: const TextStyle(color: AppColors.error, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _cancelarGrabacion,
                      child: const Text('Cancelar', style: TextStyle(color: AppColors.error)),
                    ),
                  ],
                ),
              ),
            _Composer(
              controller: _inputCtrl,
              enabled: !widget.readOnly && !_sending && !_recording,
              recording: _recording,
              onSend: _enviar,
              onMicPressStart: _iniciarGrabacion,
              onMicPressEnd: _detenerYEnviar,
            ),
          ],
        ),
      ),
    );
  }
}


String _formatDuration(Duration d) {
  final mm = d.inMinutes.remainder(60).toString();
  final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$mm:$ss';
}


class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.contraparte});

  final String contraparte;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 48, color: AppColors.primary.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              'Todavía no hay mensajes con el $contraparte.',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}


class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.esMio,
    this.isPlaying = false,
    this.onTogglePlay,
  });

  final SolicitudChatMessage message;
  final bool esMio;
  final bool isPlaying;
  final VoidCallback? onTogglePlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = esMio ? AppColors.primary : theme.colorScheme.surfaceContainerHighest;
    final fg = esMio ? Colors.white : theme.colorScheme.onSurface;
    final hora = DateFormat.Hm().format(message.createdAt);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: esMio ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(esMio ? 14 : 4),
                  bottomRight: Radius.circular(esMio ? 4 : 14),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!esMio && message.senderDisplayName.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        message.senderDisplayName,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: fg.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  if (message.audio != null)
                    // Burbuja de audio: botón play/pause + duración.
                    InkWell(
                      onTap: onTogglePlay,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: fg.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isPlaying ? Icons.pause : Icons.play_arrow,
                                color: fg,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Icon(Icons.mic, size: 16, color: fg.withValues(alpha: 0.8)),
                            const SizedBox(width: 4),
                            Text(
                              message.audio!.durationMs != null
                                  ? _formatDuration(Duration(milliseconds: message.audio!.durationMs!))
                                  : 'Nota de voz',
                              style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (message.audio == null && message.content.isNotEmpty)
                    Text(
                      message.content,
                      style: TextStyle(color: fg, fontSize: 14, height: 1.35),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    hora,
                    style: TextStyle(
                      fontSize: 10,
                      color: fg.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onSend,
    this.recording = false,
    this.onMicPressStart,
    this.onMicPressEnd,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool recording;
  final VoidCallback onSend;
  final VoidCallback? onMicPressStart;
  final VoidCallback? onMicPressEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: recording
                    ? 'Grabando nota de voz…'
                    : enabled
                        ? 'Escribe un mensaje…'
                        : 'Chat solo lectura',
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Mic: press-and-hold para grabar; soltar → detener y enviar.
          if (onMicPressStart != null)
            GestureDetector(
              onLongPressStart: (_) {
                if (enabled) onMicPressStart!();
              },
              onLongPressEnd: (_) {
                if (recording) onMicPressEnd!();
              },
              // Tap corto: también funciona como toggle para accesibilidad.
              onTap: () {
                if (recording) {
                  onMicPressEnd?.call();
                } else if (enabled) {
                  onMicPressStart?.call();
                }
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: recording ? AppColors.error : Colors.grey.shade600,
                ),
                child: Icon(
                  recording ? Icons.stop : Icons.mic,
                  size: 20,
                  color: Colors.white,
                ),
              ),
            ),
          const SizedBox(width: 6),
          FilledButton(
            onPressed: enabled ? onSend : null,
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(14),
              backgroundColor: AppColors.primary,
            ),
            child: const Icon(Icons.send_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}
