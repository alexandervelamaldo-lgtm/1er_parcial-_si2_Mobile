import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

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
    this.readOnly = false,
    this.readOnlyReason,
  });

  final int solicitudId;
  /// Etiqueta del otro lado (ej. 'técnico', 'cliente') para el header.
  final String contraparteLabel;
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
  bool _loading = false;
  bool _sending = false;
  String? _error;
  StreamSubscription<ChatMessageEvent>? _wsSub;

  /// Rol del usuario en sesión ('cliente' | 'tecnico') para decidir qué
  /// burbujas dibujar como "mías". Tomamos el primero que aparezca, ya
  /// que en el modelo actual nunca conviven CLIENTE y TECNICO en el
  /// mismo usuario para una misma solicitud.
  String? _myRoleInChat() {
    final roles = context.read<SessionProvider>().profile?.roles ?? const <String>[];
    if (roles.contains('CLIENTE')) return 'cliente';
    if (roles.contains('TECNICO')) return 'tecnico';
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
      final res = await _service.listar(token: token, solicitudId: widget.solicitudId);
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
      await _service.marcarLeidos(token: token, solicitudId: widget.solicitudId);
    } catch (_) {
      // No es crítico — silenciamos.
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
                            return _MessageBubble(message: msg, esMio: esMio);
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
            _Composer(
              controller: _inputCtrl,
              enabled: !widget.readOnly && !_sending,
              onSend: _enviar,
            ),
          ],
        ),
      ),
    );
  }
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
  const _MessageBubble({required this.message, required this.esMio});

  final SolicitudChatMessage message;
  final bool esMio;

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
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;

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
                hintText: enabled ? 'Escribe un mensaje…' : 'Chat solo lectura',
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
          const SizedBox(width: 8),
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
