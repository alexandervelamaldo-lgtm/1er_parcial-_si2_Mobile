import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../models/solicitud.dart';
import '../providers/session_provider.dart';
import '../services/api_service.dart';
import '../services/mapbox_service.dart';
import '../services/tracking_ws_service.dart';
import '../widgets/mapbox_tracking_map_card.dart';
import 'paypal_checkout_screen.dart';
import 'solicitud_chat_screen.dart';

class SolicitudDetalleScreen extends StatefulWidget {
  const SolicitudDetalleScreen({
    super.key,
    required this.solicitudId,
    this.tenantKey,
  });

  final int solicitudId;
  final String? tenantKey;

  @override
  State<SolicitudDetalleScreen> createState() => _SolicitudDetalleScreenState();
}

class _SolicitudDetalleScreenState extends State<SolicitudDetalleScreen> {
  SolicitudDetalle? _detalle;
  SolicitudSeguimiento? _seguimiento;
  SolicitudCandidatos? _candidatos;
  bool _loading = true;
  String? _error;
  int? _liveEtaMin;
  double? _liveDistanceKm;
  Timer? _trackingTimer;
  StreamSubscription<SolicitudWsUpdate>? _wsSub;
  late final MapboxService _mapbox = MapboxService();

  Future<void> _openInvoicePdf({
    required BuildContext context,
    required ApiService api,
    required String token,
    required int solicitudId,
  }) async {
    final bytes = await api.descargarFacturaPdf(token: token, solicitudId: solicitudId);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/factura_solicitud_$solicitudId.pdf');
    await file.writeAsBytes(bytes, flush: true);
    await OpenFilex.open(file.path);
  }

  /// Flujo de pago PayPal desde el detalle: crea la orden en el backend,
  /// abre la aprobación en WebView y, si el cliente aprueba, la captura.
  /// Al capturar, el backend completa la solicitud; recargamos el detalle.
  bool _paying = false;

  Future<void> _payWithPayPal({
    required ApiService api,
    required String token,
    required int solicitudId,
  }) async {
    if (_paying) return;
    setState(() => _paying = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final orden = await api.crearOrdenPayPal(token: token, solicitudId: solicitudId);
      if (!mounted) return;
      final result = await Navigator.of(context).push<PayPalCheckoutResult>(
        MaterialPageRoute(
          builder: (_) => PayPalCheckoutScreen(
            approveUrl: orden.approveUrl,
            orderId: orden.orderId,
            solicitudId: orden.solicitudId,
            monto: orden.monto,
            moneda: orden.moneda,
          ),
        ),
      );
      if (!mounted) return;
      if (result is PayPalApproved) {
        await api.capturarOrdenPayPal(
          token: token,
          orderId: result.orderId,
          solicitudId: solicitudId,
        );
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Pago PayPal confirmado exitosamente'),
            backgroundColor: Color(0xFF16A34A),
          ),
        );
        await _loadAll();
      } else if (result is PayPalCancelled) {
        messenger.showSnackBar(const SnackBar(content: Text('Pago PayPal cancelado')));
      } else if (result is PayPalWebViewError) {
        messenger.showSnackBar(SnackBar(content: Text('Error PayPal: ${result.message}')));
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Error: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAll();
      // Keep a lightweight 30-second fallback timer so the screen stays
      // fresh even without an active WebSocket connection.
      _trackingTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshTracking());
      _subscribeToWs();
    });
  }

  /// Subscribe to the shared WebSocket service for push-based updates.
  /// The timer above is a fallback; WS events are the primary mechanism.
  void _subscribeToWs() {
    final ws = context.read<TrackingWsService>();
    _wsSub = ws.solicitudStream.listen((update) {
      if (!mounted) return;
      if (update.solicitudId != widget.solicitudId) return;
      // State changed — reload tracking info to get the latest data.
      _refreshTracking();
    });
  }

  @override
  void dispose() {
    _trackingTimer?.cancel();
    _wsSub?.cancel();
    _mapbox.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final token = context.read<SessionProvider>().token;
    if (token == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Inicia sesión para ver el detalle de la solicitud';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = context.read<ApiService>();
      final detalle = await _withTenant(api, () => api.obtenerDetalleSolicitud(token, widget.solicitudId));
      final seguimiento = await _withTenant(api, () => api.obtenerSeguimientoSolicitud(token, widget.solicitudId));
      // Los candidatos son complementarios (tarjeta "Sugerencias"). Si fallan
      // no debemos dejar en blanco todo el detalle ni el seguimiento: se
      // degradan a null y la tarjeta simplemente no se muestra.
      SolicitudCandidatos? candidatos;
      try {
        candidatos = await _withTenant(api, () => api.obtenerCandidatosSolicitud(token, widget.solicitudId));
      } catch (_) {
        candidatos = null;
      }
      if (!mounted) return;
      setState(() {
        _detalle = detalle;
        _seguimiento = seguimiento;
        _candidatos = candidatos;
        _loading = false;
      });
    } on SessionExpiredException {
      // Token expirado a mitad de sesión: cerramos sesión y volvemos a la raíz,
      // que muestra el LoginScreen cuando no hay sesión. Antes el 401 caía en el
      // catch genérico y el usuario solo veía "No se pudo cargar el detalle".
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final session = context.read<SessionProvider>();
      await session.logout();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      messenger.showSnackBar(
        const SnackBar(content: Text('Tu sesión expiró. Inicia sesión nuevamente.')),
      );
    } catch (e) {
      // Mostramos la causa real (status HTTP / detalle del backend) en vez de un
      // texto genérico — así un 500/timeout/parse se diagnostica de inmediato.
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo cargar el detalle de la solicitud.\n$e';
      });
    }
  }

  Future<void> _refreshTracking() async {
    final token = context.read<SessionProvider>().token;
    if (token == null || !mounted) return;
    try {
      final api = context.read<ApiService>();
      final seguimiento = await _withTenant(api, () => api.obtenerSeguimientoSolicitud(token, widget.solicitudId));
      if (!mounted) return;
      setState(() {
        _seguimiento = seguimiento;
      });
    } catch (_) {}
  }

  Future<T> _withTenant<T>(ApiService api, Future<T> Function() run) async {
    final forced = (widget.tenantKey ?? '').trim();
    if (forced.isEmpty) {
      return run();
    }
    final previous = api.currentTenant;
    api.setTenant(forced);
    try {
      return await run();
    } finally {
      api.setTenant(previous);
    }
  }

  double? _displayDistanceKm() => _liveDistanceKm ?? _seguimiento?.distanciaKm;

  /// Formato del ETA para la UI:
  ///   - Si el backend mandó rango (lower/upper) y la diferencia es > 5 min,
  ///     mostramos "12-18 min" (rango honesto, refleja la varianza esperada).
  ///   - Si la diferencia es chica o falta uno de los extremos, mostramos
  ///     el valor único — "15 min".
  ///   - Si no hay ningún dato, "--".
  /// El backend ya aplicó el factor de tráfico horario de Bolivia, así
  /// que estos números reflejan la realidad de Santa Cruz en hora pico.
  String _displayEtaText() {
    final live = _liveEtaMin;
    if (live != null) return '$live min';
    final s = _seguimiento;
    if (s == null) return '-- min';
    final lower = s.etaMinLower;
    final upper = s.etaMinUpper;
    if (lower != null && upper != null && upper - lower > 5) {
      return '$lower-$upper min';
    }
    return s.etaMin != null ? '${s.etaMin} min' : '-- min';
  }

  bool _hasClientTrackingView(SolicitudSeguimiento? seguimiento) {
    if (seguimiento == null) return false;
    return _shouldShowLiveRoute(seguimiento) && seguimiento.tallerNombre != null;
  }

  bool _shouldShowLiveRoute(SolicitudSeguimiento? seguimiento) {
    if (seguimiento == null) return false;
    final serviceState = seguimiento.servicioEstado ?? '';
    final operational = seguimiento.estado == 'EN_CAMINO' || seguimiento.estado == 'EN_ATENCION';
    final accepted = serviceState == 'ACEPTADO_TALLER' || serviceState == 'EN_CAMINO' || serviceState == 'EN_ATENCION';
    final hasCoordinates = seguimiento.latitudActual != null &&
        seguimiento.longitudActual != null &&
        seguimiento.latitudServicio != null &&
        seguimiento.longitudServicio != null;
    return hasCoordinates && (seguimiento.trackingActivo || accepted || operational);
  }

  LatLng? _clientLocation(SolicitudSeguimiento? seguimiento) {
    if (seguimiento?.latitudCliente == null || seguimiento?.longitudCliente == null) return null;
    return LatLng(seguimiento!.latitudCliente!, seguimiento.longitudCliente!);
  }

  LatLng? _workshopLocation(SolicitudSeguimiento? seguimiento) {
    if (seguimiento?.latitudTaller == null || seguimiento?.longitudTaller == null) return null;
    return LatLng(seguimiento!.latitudTaller!, seguimiento.longitudTaller!);
  }

  LatLng? _serviceLocation(SolicitudSeguimiento? seguimiento, SolicitudDetalle? detalle) {
    if (seguimiento?.latitudServicio != null && seguimiento?.longitudServicio != null) {
      return LatLng(seguimiento!.latitudServicio!, seguimiento.longitudServicio!);
    }
    if (detalle?.latitudIncidente == null || detalle?.longitudIncidente == null) return null;
    return LatLng(detalle!.latitudIncidente!, detalle.longitudIncidente!);
  }

  LatLng? _professionalLocation(SolicitudSeguimiento? seguimiento) {
    if (seguimiento?.latitudActual == null || seguimiento?.longitudActual == null) return null;
    return LatLng(seguimiento!.latitudActual!, seguimiento.longitudActual!);
  }

  @override
  Widget build(BuildContext context) {
    final token = context.watch<SessionProvider>().token;
    final api = context.read<ApiService>();
    final detalle = _detalle;
    final seguimiento = _seguimiento;
    final candidatos = _candidatos;

    return Scaffold(
      appBar: AppBar(
        title: Text('Solicitud #${widget.solicitudId}'),
        actions: [
          // Chat en vivo con el técnico asignado. Habilitamos el botón
          // siempre que la solicitud ya tenga técnico; el backend igual
          // valida acceso y devuelve 403 si el usuario no es la parte
          // autorizada.
          if (detalle != null && detalle.tecnicoId != null)
            IconButton(
              tooltip: 'Chat con el técnico',
              icon: const Icon(Icons.chat_bubble_outline),
              onPressed: () {
                final estado = detalle.estado.toUpperCase();
                final readOnly = const {
                  'COMPLETADA',
                  'CERRADA',
                  'FINALIZADA',
                  'CANCELADA',
                }.contains(estado);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SolicitudChatScreen(
                      solicitudId: widget.solicitudId,
                      contraparteLabel: 'técnico',
                      readOnly: readOnly,
                      readOnlyReason: readOnly
                          ? 'Esta solicitud ya cerró. Solo se muestra el historial.'
                          : null,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      body: token == null
          ? const Center(child: Text('Inicia sesión para ver el detalle de la solicitud'))
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null || detalle == null || seguimiento == null
                  ? Center(child: Text(_error ?? 'No se pudo cargar el detalle de la solicitud'))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _DetalleHeaderCard(detalle: detalle),
                        // Banner contextual que cubre TODOS los estados del flujo
                        // (registrada → esperando taller → asignada → en camino →
                        // en atención → finalizado / rechazada / cancelada) para
                        // que el cliente siempre sepa en qué paso está.
                        Builder(builder: (context) {
                          final vista = _EstadoVista.of(detalle.estado);
                          if (vista.mensaje.isEmpty) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: _StateBanner(
                              color: vista.color,
                              icon: vista.icon,
                              title: vista.titulo,
                              message: vista.mensaje,
                              spinning: vista.spinning,
                            ),
                          );
                        }),
                        const SizedBox(height: 12),
                        _IaCostoCard(detalle: detalle),
                        const SizedBox(height: 12),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Seguimiento', style: Theme.of(context).textTheme.titleMedium),
                                const SizedBox(height: 8),
                                Text('Taller: ${seguimiento.tallerNombre ?? 'Pendiente'}'),
                                Text('Profesional: ${seguimiento.tecnicoNombre ?? 'Pendiente'}'),
                                Text('ETA: ${_displayEtaText()}'),
                                Text('Distancia restante: ${_displayDistanceKm()?.toStringAsFixed(2) ?? '--'} km'),
                                if (seguimiento.mensaje != null) ...[
                                  const SizedBox(height: 8),
                                  Text(seguimiento.mensaje!),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        MapboxTrackingMapCard(
                          mapbox: _mapbox,
                          clientLocation: _clientLocation(seguimiento),
                          workshopLocation: _workshopLocation(seguimiento),
                          workshopName: seguimiento.tallerNombre,
                          serviceLocation: _serviceLocation(seguimiento, detalle),
                          professionalLocation: _professionalLocation(seguimiento),
                          professionalName: seguimiento.tecnicoNombre,
                          trackingEnabled: _shouldShowLiveRoute(seguimiento),
                          serverRoute: seguimiento.rutaSeguimiento,
                          serverDistanceKm: seguimiento.distanciaKm,
                          isArrived: seguimiento.estado == 'EN_ATENCION' ||
                              seguimiento.estado == 'COMPLETADA',
                          routeColorHex: seguimiento.routeColor,
                          fallbackEtaMin: seguimiento.etaMin,
                          updatedAt: seguimiento.ubicacionActualizadaEn,
                          onRouteComputed: (route) {
                            if (!mounted) return;
                            setState(() {
                              _liveEtaMin = route?.durationMin;
                              _liveDistanceKm = route?.distanceKm;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        if (candidatos != null &&
                            candidatos.talleres.isNotEmpty &&
                            !_hasClientTrackingView(seguimiento))
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Sugerencias', style: Theme.of(context).textTheme.titleMedium),
                                  const SizedBox(height: 8),
                                  ...candidatos.talleres.take(3).map(
                                        (taller) => ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          title: Text(taller.nombre),
                                          subtitle: Text(taller.motivoSugerencia ?? 'Cercanía y disponibilidad'),
                                          trailing: Text(taller.score?.toStringAsFixed(1) ?? '--'),
                                        ),
                                      ),
                                ],
                              ),
                            ),
                          ),
                        // El taller (o técnico) ya cerró el trabajo y fijó el
                        // costo final, y aún no hay un pago confirmado: el
                        // cliente puede pagar desde aquí con PayPal.
                        if (detalle.trabajoTerminado &&
                            detalle.costoFinal != null &&
                            (detalle.pagos.isEmpty ||
                                detalle.pagos.first.estado != 'PAGADO')) ...[
                          const SizedBox(height: 12),
                          Card(
                            color: const Color(0xFFEFF6FF),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Pago del servicio',
                                      style: Theme.of(context).textTheme.titleMedium),
                                  const SizedBox(height: 4),
                                  Text('Monto a pagar: Bs ${detalle.costoFinal!.toStringAsFixed(2)}'),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF003087),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                      ),
                                      icon: _paying
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2, color: Colors.white),
                                            )
                                          : const Icon(Icons.payment),
                                      label: Text(_paying
                                          ? 'Conectando con PayPal...'
                                          : 'Pagar con PayPal'),
                                      onPressed: _paying
                                          ? null
                                          : () => _payWithPayPal(
                                                api: api,
                                                token: token,
                                                solicitudId: detalle.id,
                                              ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ] else if (detalle.estado == 'EN_ATENCION' &&
                            (detalle.pagos.isEmpty ||
                                detalle.pagos.first.estado != 'PAGADO')) ...[
                          // En atención pero el taller aún no registra el costo
                          // final: avisamos que el pago se hará aquí mismo.
                          const SizedBox(height: 12),
                          Card(
                            color: const Color(0xFFF1F5F9),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  const Icon(Icons.schedule,
                                      size: 18, color: Color(0xFF64748B)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Podrás pagar aquí cuando el taller registre el costo final del servicio.',
                                      style: TextStyle(
                                          fontSize: 13, color: Colors.grey[700]),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        if (detalle.pagos.isNotEmpty && detalle.pagos.first.estado == 'PAGADO') ...[
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () => _openInvoicePdf(
                              context: context,
                              api: api,
                              token: token,
                              solicitudId: detalle.id,
                            ),
                            child: const Text('Ver factura PDF'),
                          ),
                        ],
                      ],
                    ),
    );
  }
}


/// Banner contextual que guía al cliente según el estado de su solicitud.
/// Renderiza un card a color con icono + título + mensaje y, opcionalmente,
/// un spinner para enfatizar "estamos esperando".
class _StateBanner extends StatelessWidget {
  const _StateBanner({
    required this.color,
    required this.icon,
    required this.title,
    required this.message,
    this.spinning = false,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String message;
  final bool spinning;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (spinning)
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: color),
            )
          else
            Icon(icon, color: color, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF334155)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


/// Card rica para mostrar la estimación de costo de la IA.
///
/// Muestra el costo "más probable" como número grande, el rango debajo,
/// la confianza con una barra visual, la nota textual (supuestos), y un
/// banner amarillo si la confianza es baja (< 0.4) — pidiendo al cliente
/// que tome la estimación como referencia, no como factura final.
///
/// Si `costoFinal` ya está fijado (el taller cerró el trabajo), se muestra
/// también con énfasis (verde) — la estimación queda como contexto.
class _IaCostoCard extends StatelessWidget {
  const _IaCostoCard({required this.detalle});
  final SolicitudDetalle detalle;

  String _fmt(double? amount) {
    if (amount == null) return '--';
    final currency = (detalle.monedaCosto).toUpperCase();
    return '$currency ${amount.toStringAsFixed(0)}';
  }

  /// La nota del backend mezcla factores técnicos internos
  /// (`f_antiguedad=0.93`, `margen=0.217`, `base ...=320 Bs`) con frases
  /// pensadas para el cliente. Mostramos solo lo legible: descartamos cualquier
  /// oración que contenga "=" (todos los factores internos lo llevan).
  String? _friendlyNote(String? nota) {
    if (nota == null) return null;
    final limpias = <String>[];
    for (final raw in nota.split('. ')) {
      final s = raw.trim().replaceAll(RegExp(r'\.+$'), '').trim();
      if (s.isEmpty || s.contains('=')) continue;
      limpias.add(s);
    }
    if (limpias.isEmpty) return null;
    return '${limpias.join('. ')}.';
  }

  @override
  Widget build(BuildContext context) {
    final estimado = detalle.costoEstimado;
    final min = detalle.costoEstimadoMin;
    final max = detalle.costoEstimadoMax;
    final conf = detalle.costoEstimacionConfianza;
    final nota = _friendlyNote(detalle.costoEstimacionNota);
    final costoFinal = detalle.costoFinal;

    // Sin estimación todavía (la IA aún no corrió o falló silenciosamente).
    if (estimado == null && costoFinal == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.hourglass_top_rounded, size: 18, color: Color(0xFF6B7280)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Estimación de costo en curso — sube una foto del daño para que la IA la analice.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF6B7280)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final lowConfidence = conf != null && conf < 0.4;
    final confidencePct = conf != null ? (conf.clamp(0.0, 1.0) * 100).toStringAsFixed(0) : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, size: 18, color: Color(0xFF2563EB)),
                const SizedBox(width: 6),
                Text(
                  'Estimación de costo IA',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                if (confidencePct != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: lowConfidence
                          ? const Color(0xFFFEF3C7)
                          : const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$confidencePct% confianza',
                      style: TextStyle(
                        fontSize: 11,
                        color: lowConfidence
                            ? const Color(0xFF92400E)
                            : const Color(0xFF166534),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Más probable (número grande)
            if (estimado != null) ...[
              Text(
                _fmt(estimado),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1E40AF),
                    ),
              ),
              const SizedBox(height: 2),
              const Text(
                'más probable',
                style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
            ],
            // Rango min-max como barra visual
            if (min != null && max != null && estimado != null) ...[
              const SizedBox(height: 12),
              _CostoRangeBar(min: min, max: max, mostProbable: estimado),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('mín ${_fmt(min)}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                  Text('máx ${_fmt(max)}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                ],
              ),
            ],
            // Banner de revisión humana cuando la confianza es baja
            if (lowConfidence) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFCD34D)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 18, color: Color(0xFF92400E)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'La IA tiene baja confianza en esta estimación. '
                        'Trátala como referencia — el presupuesto final lo da el taller.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Nota / supuestos (ya filtrada de factores técnicos)
            if (nota != null && nota.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.notes_rounded, size: 15, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        nota,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Costo final del taller (si ya cerró el trabajo)
            if (costoFinal != null) ...[
              const Divider(height: 24),
              Row(
                children: [
                  const Icon(Icons.check_circle_rounded,
                      size: 18, color: Color(0xFF16A34A)),
                  const SizedBox(width: 6),
                  const Text(
                    'Costo final del taller:',
                    style: TextStyle(
                        fontSize: 13, color: Color(0xFF166534), fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Text(
                    _fmt(costoFinal),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF166534),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}


/// Barra horizontal que muestra el rango [min, max] con un marcador en el
/// punto "más probable". Visualmente ayuda al cliente a entender que no es
/// un precio fijo, sino una banda.
class _CostoRangeBar extends StatelessWidget {
  const _CostoRangeBar({
    required this.min,
    required this.max,
    required this.mostProbable,
  });
  final double min;
  final double max;
  final double mostProbable;

  @override
  Widget build(BuildContext context) {
    // Posición relativa del marcador "más probable" dentro del rango.
    double t = 0.5;
    if (max > min) {
      t = ((mostProbable - min) / (max - min)).clamp(0.0, 1.0);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final markerLeft = (width * t).clamp(0.0, width - 12);
        return SizedBox(
          height: 14,
          child: Stack(
            children: [
              // Track
              Positioned(
                left: 0,
                right: 0,
                top: 5,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFBFDBFE), Color(0xFF60A5FA), Color(0xFF2563EB)],
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Marcador "más probable"
              Positioned(
                left: markerLeft,
                top: 0,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E40AF),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}


/// Presentación amigable de cada estado de la solicitud: etiqueta corta para
/// el chip, color, icono y un mensaje guía para el banner. Centraliza el mapeo
/// estado→UI para que el chip del header y el banner queden siempre coherentes.
class _EstadoVista {
  const _EstadoVista({
    required this.label,
    required this.color,
    required this.icon,
    required this.titulo,
    required this.mensaje,
    this.spinning = false,
  });

  final String label;
  final Color color;
  final IconData icon;
  final String titulo;
  final String mensaje;
  final bool spinning;

  static _EstadoVista of(String estado) {
    switch (estado) {
      case 'REGISTRADA':
        return const _EstadoVista(
          label: 'Registrada',
          color: Color(0xFF2563EB),
          icon: Icons.assignment_turned_in_rounded,
          titulo: 'Solicitud registrada',
          mensaje: 'Estamos buscando el mejor taller disponible para ti.',
          spinning: true,
        );
      case 'PROPUESTA_TALLER':
        return const _EstadoVista(
          label: 'Esperando taller',
          color: Color(0xFF2563EB),
          icon: Icons.hourglass_top_rounded,
          titulo: 'Esperando al taller…',
          mensaje: 'Le enviamos tu solicitud. El taller debe aceptar o rechazar. '
              'Te avisaremos por notificación.',
          spinning: true,
        );
      case 'RECHAZADA_TALLER':
        return const _EstadoVista(
          label: 'Rechazada',
          color: Color(0xFFEA580C),
          icon: Icons.error_outline_rounded,
          titulo: 'El taller no puede atenderte',
          mensaje: 'Elige otro taller desde la lista de disponibles.',
        );
      case 'ASIGNADA':
        return const _EstadoVista(
          label: 'Taller aceptó',
          color: Color(0xFF16A34A),
          icon: Icons.check_circle_outline_rounded,
          titulo: 'Taller aceptó',
          mensaje: 'El taller confirmó tu solicitud y se está preparando. '
              'Pronto verás que está en camino.',
        );
      case 'EN_CAMINO':
        return const _EstadoVista(
          label: 'En camino',
          color: Color(0xFF4F46E5),
          icon: Icons.local_shipping_rounded,
          titulo: 'El técnico va en camino',
          mensaje: 'Sigue su recorrido en tiempo real en el mapa de abajo.',
          spinning: true,
        );
      case 'EN_ATENCION':
        return const _EstadoVista(
          label: 'En atención',
          color: Color(0xFF0891B2),
          icon: Icons.build_circle_rounded,
          titulo: 'Atención en curso',
          mensaje: 'El técnico está atendiendo tu vehículo en el lugar.',
          spinning: true,
        );
      case 'COMPLETADA':
        return const _EstadoVista(
          label: 'Finalizado',
          color: Color(0xFF16A34A),
          icon: Icons.verified_rounded,
          titulo: 'Servicio finalizado',
          mensaje: 'El trabajo fue completado. Revisa el costo final y tu factura.',
        );
      case 'CANCELADA':
        return const _EstadoVista(
          label: 'Cancelada',
          color: Color(0xFFDC2626),
          icon: Icons.cancel_rounded,
          titulo: 'Solicitud cancelada',
          mensaje: 'Esta solicitud fue cancelada.',
        );
      default:
        return _EstadoVista(
          label: estado,
          color: const Color(0xFF64748B),
          icon: Icons.info_outline_rounded,
          titulo: estado,
          mensaje: '',
        );
    }
  }
}


/// Cabecera del detalle: tipo de incidente, descripción y chips de estado y
/// prioridad. Reemplaza al ListTile plano por algo más legible y con color.
class _DetalleHeaderCard extends StatelessWidget {
  const _DetalleHeaderCard({required this.detalle});
  final SolicitudDetalle detalle;

  @override
  Widget build(BuildContext context) {
    final vista = _EstadoVista.of(detalle.estado);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    detalle.tipoIncidente,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 8),
                _EstadoChip(label: vista.label, color: vista.color, icon: vista.icon),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              detalle.descripcion,
              style: const TextStyle(color: Color(0xFF475569), height: 1.3),
            ),
            const SizedBox(height: 10),
            _PrioridadChip(prioridad: detalle.prioridad),
          ],
        ),
      ),
    );
  }
}


/// Pill con icono + etiqueta de color, usado para el estado de la solicitud.
class _EstadoChip extends StatelessWidget {
  const _EstadoChip({required this.label, required this.color, required this.icon});
  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
  }
}


/// Pill de prioridad con color según severidad (crítica/alta/media/baja).
class _PrioridadChip extends StatelessWidget {
  const _PrioridadChip({required this.prioridad});
  final String prioridad;

  @override
  Widget build(BuildContext context) {
    final upper = prioridad.toUpperCase();
    Color color;
    if (upper == 'CRITICA') {
      color = const Color(0xFFDC2626);
    } else if (upper == 'ALTA') {
      color = const Color(0xFFEA580C);
    } else if (upper == 'MEDIA') {
      color = const Color(0xFFD97706);
    } else {
      color = const Color(0xFF16A34A);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.priority_high_rounded, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            'Prioridad ${prioridad.toLowerCase()}',
            style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
