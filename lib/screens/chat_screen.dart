import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/session_provider.dart';
import '../services/ai_service.dart';
import '../theme/app_theme.dart';


/// Cuántos mensajes previos se envían como contexto en cada solicitud.
/// Debe coincidir con el límite del backend (AiChatRequest.history).
const int _maxHistorialEnviado = 20;


class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}


class _ChatMessage {
  _ChatMessage({required this.role, required this.content, this.failed = false});

  final String role; // 'user' | 'assistant'
  final String content;
  final bool failed;
}


class _ChatScreenState extends State<ChatScreen> {
  final AiService _ai = AiService();
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final List<_ChatMessage> _messages = <_ChatMessage>[];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ai.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// Envía el mensaje escrito al asistente Groq y añade la respuesta a la lista.
  ///
  /// Diseño "optimistic": el mensaje del usuario aparece INMEDIATAMENTE en la
  /// UI mientras esperamos la respuesta del server. Eso hace que se sienta
  /// más responsivo (no hay que esperar el round-trip para ver lo que
  /// escribiste). Si el server falla, el mensaje queda en la conversación
  /// (marcado como fallido) y mostramos el error abajo.
  Future<void> _enviar() async {
    final texto = _inputCtrl.text.trim();
    if (texto.isEmpty || _busy) return;

    final token = context.read<SessionProvider>().token;
    if (token == null || token.isEmpty) {
      setState(() => _error = 'Necesitás iniciar sesión para usar el asistente.');
      return;
    }

    // Optimistic update: burbuja del usuario ANTES de la petición.
    setState(() {
      _messages.add(_ChatMessage(role: 'user', content: texto));
      _inputCtrl.clear();
      _error = null;
      _busy = true;
    });
    _scrollAlFinal();

    // Preparamos el historial que mandamos al server:
    //   1. Excluímos el ÚLTIMO mensaje (el que acabamos de agregar) —
    //      el server lo espera en el campo `message`, no en `history`.
    //   2. Descartamos los que fallaron (`failed`) — no aportan contexto
    //      real y confunden al LLM.
    //   3. Truncamos a los últimos N mensajes para no exceder el límite
    //      del backend (AiChatRequest.history tiene max_length=40).
    final historial = _messages
        .take(_messages.length - 1)
        .where((m) => !m.failed)
        .toList(growable: false);
    final desde = historial.length > _maxHistorialEnviado ? historial.length - _maxHistorialEnviado : 0;
    final historialEnviado = historial
        .sublist(desde)
        .map((m) => AiChatMessage(role: m.role, content: m.content))
        .toList(growable: false);

    try {
      final res = await _ai.chat(
        token: token,
        message: texto,
        history: historialEnviado,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(role: 'assistant', content: res.reply));
      });
    } on AiChatException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo contactar al asistente. Intenta de nuevo en unos momentos.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _scrollAlFinal();
      }
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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Asistente virtual', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(
              'Preguntame sobre la plataforma',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _messages.isEmpty && !_busy
                  ? const _EmptyChat()
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      itemCount: _messages.length + (_busy ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (_busy && index == _messages.length) {
                          return const _TypingBubble();
                        }
                        final msg = _messages[index];
                        return _MessageBubble(message: msg);
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
              enabled: !_busy,
              onSend: _enviar,
              theme: theme,
            ),
          ],
        ),
      ),
    );
  }
}


class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.support_agent, size: 56, color: AppColors.primary.withValues(alpha: 0.6)),
            const SizedBox(height: 12),
            const Text(
              'Hola, soy tu asistente virtual.',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              'Preguntame cómo reportar una emergencia, seguir una solicitud o usar la app.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}


class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final esUsuario = message.role == 'user';
    final bg = message.failed
        ? AppColors.errorLight
        : esUsuario
            ? AppColors.primary
            : Theme.of(context).colorScheme.surfaceContainerHighest;
    final fg = message.failed
        ? AppColors.error
        : esUsuario
            ? Colors.white
            : Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: esUsuario ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!esUsuario)
            const Padding(
              padding: EdgeInsets.only(right: 6, bottom: 2),
              child: CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.primary,
                child: Icon(Icons.smart_toy_outlined, color: Colors.white, size: 16),
              ),
            ),
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
                  bottomLeft: Radius.circular(esUsuario ? 14 : 4),
                  bottomRight: Radius.circular(esUsuario ? 4 : 14),
                ),
              ),
              child: Text(
                message.content,
                style: TextStyle(color: fg, fontSize: 14, height: 1.35),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Padding(
            padding: EdgeInsets.only(right: 6, bottom: 2),
            child: CircleAvatar(
              radius: 14,
              backgroundColor: AppColors.primary,
              child: Icon(Icons.smart_toy_outlined, color: Colors.white, size: 16),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(14),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('Escribiendo…', style: TextStyle(fontSize: 13, color: Colors.grey)),
              ],
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
    required this.theme,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
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
                hintText: 'Escribe tu mensaje…',
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
