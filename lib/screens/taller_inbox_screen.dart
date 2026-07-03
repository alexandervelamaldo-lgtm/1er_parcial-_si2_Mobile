/// Bandeja de propuestas para el rol TALLER.
///
/// Muestra en tiempo real las solicitudes en estado `PROPUESTA_TALLER`
/// asignadas a este taller — esos son los clientes que eligieron tu taller
/// y están esperando que aceptes o rechaces.
///
/// Comportamiento:
///   1. Carga inicial: GET /solicitudes (el backend filtra por taller_id
///      del JWT) y se queda solo con las que tienen estado PROPUESTA_TALLER.
///   2. WebSocket: escucha eventos solicitud_update y refresca cuando alguna
///      solicitud entra o sale del estado.
///   3. Polling fallback: cada 30s recarga por si el WS está caído.
///   4. Tap "Aceptar"  → PUT /respuesta-taller {aceptada:true}
///      Tap "Rechazar" → muestra dialog para motivo → PUT con aceptada:false
///   5. Push notification del backend (FCM tipo PROPUESTA_TALLER) abre esta
///      pantalla vía deep-link.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/solicitud.dart';
import '../providers/session_provider.dart';
import '../services/api_service.dart';
import '../services/tracking_ws_service.dart';
import '../theme/app_theme.dart';
import 'solicitud_detalle_screen.dart';


class TallerInboxScreen extends StatefulWidget {
  const TallerInboxScreen({super.key});

  @override
  State<TallerInboxScreen> createState() => _TallerInboxScreenState();
}


class _TallerInboxScreenState extends State<TallerInboxScreen> {
  List<Solicitud> _propuestas = const [];
  bool _loading = true;
  String? _error;
  Timer? _pollingTimer;
  StreamSubscription<SolicitudWsUpdate>? _wsSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _subscribeToWs();
      // Polling fallback cada 30s — el WS es la fuente primaria pero el
      // polling cubre caídas de socket o tabs en background.
      _pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) _load(silent: true);
      });
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _wsSub?.cancel();
    super.dispose();
  }

  void _subscribeToWs() {
    final ws = context.read<TrackingWsService>();
    _wsSub = ws.solicitudStream.listen((update) {
      // Cualquier cambio en una solicitud puede afectar la bandeja:
      //   - nueva propuesta entrante → aparecer en la lista
      //   - el cliente canceló → desaparecer
      //   - yo mismo acepté/rechacé desde otra pestaña → refrescar
      if (!mounted) return;
      _load(silent: true);
    });
  }

  Future<void> _load({bool silent = false}) async {
    final token = context.read<SessionProvider>().token;
    if (token == null) return;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final api = context.read<ApiService>();
      final all = await api.obtenerSolicitudes(token);
      // El backend ya filtra por taller_id del JWT, pero por seguridad
      // también filtramos por estado aquí: solo propuestas pendientes.
      final inbox = all.where((s) => s.estado.toUpperCase() == 'PROPUESTA_TALLER').toList();
      // Ordenar por fecha descendente — las más recientes arriba.
      inbox.sort((a, b) => b.fechaSolicitud.compareTo(a.fechaSolicitud));
      if (!mounted) return;
      setState(() {
        _propuestas = inbox;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _aceptar(Solicitud s) async {
    final confirmed = await _confirmDialog(
      title: '¿Aceptar esta solicitud?',
      message:
          'Confirmas que tu taller puede atender esta solicitud. El cliente '
          'será notificado y se asignará a tu taller.',
      confirmLabel: 'Sí, aceptar',
      confirmColor: AppColors.success,
    );
    if (confirmed != true) return;
    await _enviarRespuesta(
      s,
      aceptada: true,
      observacion: 'Taller acepta atender la solicitud',
    );
  }

  Future<void> _rechazar(Solicitud s) async {
    final motivo = await _askMotivoDialog();
    if (motivo == null) return;
    await _enviarRespuesta(s, aceptada: false, observacion: motivo);
  }

  Future<void> _enviarRespuesta(
    Solicitud s, {
    required bool aceptada,
    required String observacion,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final token = context.read<SessionProvider>().token;
    if (token == null) return;
    final api = context.read<ApiService>();
    setState(() => _loading = true);
    try {
      await api.responderPropuestaTaller(
        token,
        solicitudId: s.id,
        aceptada: aceptada,
        observacion: observacion,
      );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        backgroundColor: aceptada ? AppColors.success : AppColors.warning,
        content: Text(aceptada
            ? 'Aceptaste la solicitud #${s.id}. Cliente notificado.'
            : 'Rechazaste la solicitud #${s.id}. Cliente notificado.'),
      ));
      await _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        backgroundColor: AppColors.error,
        content: Text('No se pudo enviar tu respuesta: '
            '${e.toString().replaceFirst('Exception: ', '')}'),
      ));
      setState(() => _loading = false);
    }
  }

  // ── Dialogs ───────────────────────────────────────────────────────────

  Future<bool?> _confirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: confirmColor),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<String?> _askMotivoDialog() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Motivo del rechazo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'El cliente verá el motivo y podrá elegir otro taller. '
              'Sé breve y claro (mín. 3 caracteres).',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              minLines: 2,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Ej: Sin capacidad hoy, equipo en mantenimiento…',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final txt = controller.text.trim();
              if (txt.length < 3) return; // Validación local antes de cerrar
              Navigator.of(context).pop(txt);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Propuestas pendientes'),
        actions: [
          IconButton(
            onPressed: _loading ? null : () => _load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading && _propuestas.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _propuestas.isEmpty
              ? _ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _propuestas.isEmpty
                      ? _buildEmptyScroll()
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _propuestas.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _PropuestaCard(
                            solicitud: _propuestas[i],
                            onAceptar: () => _aceptar(_propuestas[i]),
                            onRechazar: () => _rechazar(_propuestas[i]),
                            onVerDetalle: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => SolicitudDetalleScreen(
                                  solicitudId: _propuestas[i].id,
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
    );
  }

  /// El RefreshIndicator necesita un scrollable hijo aunque la lista esté
  /// vacía — usamos un ListView con un solo card que actúa como empty state.
  Widget _buildEmptyScroll() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 60),
        Center(child: _EmptyInbox()),
      ],
    );
  }
}


// ════════════════════════════════════════════════════════════════════════
// Widgets auxiliares
// ════════════════════════════════════════════════════════════════════════


class _PropuestaCard extends StatelessWidget {
  const _PropuestaCard({
    required this.solicitud,
    required this.onAceptar,
    required this.onRechazar,
    required this.onVerDetalle,
  });

  final Solicitud solicitud;
  final VoidCallback onAceptar;
  final VoidCallback onRechazar;
  final VoidCallback onVerDetalle;

  Color _colorPrioridad() {
    switch (solicitud.prioridad.toUpperCase()) {
      case 'CRITICA': return const Color(0xFFDC2626);
      case 'ALTA':    return const Color(0xFFEA580C);
      case 'MEDIA':   return const Color(0xFFCA8A04);
      default:        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorPrioridad();
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onVerDetalle,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: ID + prioridad + tipo
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      solicitud.prioridad,
                      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('#${solicitud.id}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text(
                    solicitud.tipoIncidente,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Descripción
              Text(
                solicitud.descripcion,
                style: const TextStyle(fontSize: 14),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              // Costo estimado
              if (solicitud.costoEstimado != null)
                Row(
                  children: [
                    Icon(Icons.attach_money, size: 16, color: Colors.grey.shade700),
                    const SizedBox(width: 4),
                    Text(
                      'Presupuesto: ${solicitud.monedaCosto} ${solicitud.costoEstimado!.toStringAsFixed(2)}',
                      style: TextStyle(color: Colors.grey.shade800, fontSize: 13),
                    ),
                    if (solicitud.costoEstimadoMin != null && solicitud.costoEstimadoMax != null)
                      Text(
                        ' (${solicitud.costoEstimadoMin!.toStringAsFixed(0)}-${solicitud.costoEstimadoMax!.toStringAsFixed(0)})',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                      ),
                  ],
                ),
              if (solicitud.esCarretera) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange.shade700),
                    const SizedBox(width: 4),
                    Text('Incidente en carretera',
                        style: TextStyle(color: Colors.orange.shade700, fontSize: 12)),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              // Acciones
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onRechazar,
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Rechazar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onAceptar,
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Aceptar'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.success,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, size: 72, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text(
            'Sin propuestas pendientes',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Cuando un cliente elija tu taller, aparecerá aquí en tiempo real. '
            'Mantente atento a las notificaciones push.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ],
      ),
    );
  }
}


class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 56, color: AppColors.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => onRetry(),
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
