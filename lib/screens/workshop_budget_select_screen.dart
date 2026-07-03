/// Pantalla del flujo cliente↔taller-directo: tras crear una solicitud,
/// el cliente ve un mapa con todos los talleres compatibles, cada uno con
/// su PRESUPUESTO YA CALCULADO por el backend. Toca un taller para abrir
/// un bottom-sheet con el detalle y "Elegir este taller".
///
/// Diferencia con la WorkshopSelectScreen vieja:
///   - Antes: el operador asignaba; el cliente solo aprobaba.
///   - Ahora: el cliente elige directo y el taller acepta o rechaza.
///
/// La pantalla:
///   1. Llama GET /solicitudes/{id}/talleres-con-presupuesto
///   2. Ordena por score híbrido (cercanía + match + descuento + rating)
///   3. Mapa con pines + lista debajo (sheet expandible)
///   4. Tap taller → bottom-sheet con presupuesto + botón "Elegir"
///   5. Tap "Elegir" → PUT /seleccionar-taller → navega a detalle con
///      estado "Esperando aceptación del taller…"
library;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
// `hide Size` evita que la clase Size de mapbox_maps_flutter sobrescriba
// la Size de Flutter — el plugin exporta un PiGeon Size con argumentos
// con nombre que no es compatible con el Size de Material.
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;

import '../config/app_config.dart';
import '../models/taller_con_presupuesto.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'solicitud_detalle_screen.dart';


class WorkshopBudgetSelectScreen extends StatefulWidget {
  const WorkshopBudgetSelectScreen({
    super.key,
    required this.api,
    required this.token,
    required this.solicitudId,
    required this.incidentPoint,
  });

  final ApiService api;
  final String token;
  final int solicitudId;
  final LatLng incidentPoint;

  @override
  State<WorkshopBudgetSelectScreen> createState() => _WorkshopBudgetSelectScreenState();
}

enum _SortMode { recomendado, masBarato, masCercano, mejorRating }


class _WorkshopBudgetSelectScreenState extends State<WorkshopBudgetSelectScreen> {
  MapboxMap? _mapboxMap;
  CircleAnnotationManager? _markerManager;
  Cancelable? _markerTapCancelable;
  final Map<String, TallerConPresupuesto> _markerByAnnotationId = {};

  bool _loading = true;
  bool _selecting = false;
  String? _error;
  TalleresConPresupuestoResponse? _response;
  _SortMode _sortMode = _SortMode.recomendado;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _markerTapCancelable?.cancel();
    super.dispose();
  }

  // ── Data ──────────────────────────────────────────────────────────────

  Future<void> _load({bool refresh = false}) async {
    // Cuando loading=true mostramos un CircularProgressIndicator y el
    // MapWidget se desmonta. Sus managers quedan inválidos. Reseteamos
    // las refs aquí para que _syncMap NO use punteros muertos.
    _markerTapCancelable?.cancel();
    _markerTapCancelable = null;
    _markerManager = null;
    _mapboxMap = null;
    _markerByAnnotationId.clear();

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.api.obtenerTalleresConPresupuesto(
        widget.token,
        solicitudId: widget.solicitudId,
        refresh: refresh,
      );
      if (!mounted) return;
      setState(() {
        _response = response;
        _loading = false;
      });
      // No llamamos _syncMap() aquí — cuando loading pase a false, el
      // MapWidget se remonta y su onMapCreated dispara _syncMap con un
      // manager fresco. Hacerlo aquí usaría refs viejas (channel-error).
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  List<TallerConPresupuesto> get _talleresOrdenados {
    final list = List<TallerConPresupuesto>.from(_response?.talleres ?? const []);
    switch (_sortMode) {
      case _SortMode.recomendado:
        list.sort((a, b) => b.score.compareTo(a.score));
      case _SortMode.masBarato:
        list.sort((a, b) => a.presupuesto.montoFinal.compareTo(b.presupuesto.montoFinal));
      case _SortMode.masCercano:
        list.sort((a, b) => a.distanciaKm.compareTo(b.distanciaKm));
      case _SortMode.mejorRating:
        list.sort((a, b) => b.ratingPromedio.compareTo(a.ratingPromedio));
    }
    return list;
  }

  // ── Map ───────────────────────────────────────────────────────────────

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    _markerManager = await mapboxMap.annotations.createCircleAnnotationManager();
    _markerTapCancelable = _markerManager?.tapEvents(onTap: (annotation) {
      final taller = _markerByAnnotationId[annotation.id];
      if (taller != null) _openBottomSheet(taller);
    });
    await _syncMap();
  }

  Future<void> _syncMap() async {
    final mapboxMap = _mapboxMap;
    final manager = _markerManager;
    if (mapboxMap == null || manager == null) return;
    _markerByAnnotationId.clear();
    // El platform channel de Mapbox puede haberse cerrado entre rebuilds
    // (sobre todo si el user toca "refrescar" mientras el map widget se
    // está montando). Si pasa, ignoramos el error y seguimos — los
    // managers nuevos del onMapCreated se encargarán de la próxima sync.
    try {
      await manager.deleteAll();
    } catch (_) {
      return;
    }

    final talleres = _response?.talleres ?? const [];
    final options = <CircleAnnotationOptions>[
      // Pin rojo del incidente
      CircleAnnotationOptions(
        geometry: Point(coordinates: Position(
          widget.incidentPoint.longitude, widget.incidentPoint.latitude,
        )),
        circleColor: const Color(0xFFEF4444).toARGB32(),
        circleRadius: 8,
        circleStrokeColor: Colors.white.toARGB32(),
        circleStrokeWidth: 3,
      ),
      // Pines de cada taller — color azul por defecto, verde si match
      ...talleres.map((t) {
        final base = t.matchEspecializacion
            ? const Color(0xFF16A34A)
            : const Color(0xFF2563EB);
        return CircleAnnotationOptions(
          geometry: Point(coordinates: Position(t.lng, t.lat)),
          circleColor: base.toARGB32(),
          circleRadius: 7.5,
          circleStrokeColor: Colors.white.toARGB32(),
          circleStrokeWidth: 2.5,
        );
      }),
    ];

    // Las llamadas al plugin Mapbox cruzan platform channels — si el widget
    // se desmonta a mitad de la sync, tiran channel-error. Best-effort.
    try {
      final created = await manager.createMulti(options);
      // El primer marker es el incidente, los demás son talleres (en orden)
      for (var i = 1; i < created.length && (i - 1) < talleres.length; i++) {
        final annotation = created[i];
        if (annotation == null) continue;
        _markerByAnnotationId[annotation.id] = talleres[i - 1];
      }
      await mapboxMap.setCamera(
        CameraOptions(
          center: Point(coordinates: Position(
            widget.incidentPoint.longitude, widget.incidentPoint.latitude,
          )),
          zoom: 12.5,
        ),
      );
    } catch (_) {
      // Mapbox channel cerrado — el próximo rebuild rehace todo.
    }
  }

  // ── Bottom-sheet ──────────────────────────────────────────────────────

  void _openBottomSheet(TallerConPresupuesto taller) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TallerBottomSheet(
        taller: taller,
        onElegir: () async {
          Navigator.of(context).pop();
          await _seleccionarTaller(taller);
        },
      ),
    );
  }

  Future<void> _seleccionarTaller(TallerConPresupuesto taller) async {
    if (_selecting) return;
    setState(() => _selecting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.api.seleccionarTallerSolicitud(
        widget.token,
        solicitudId: widget.solicitudId,
        tallerId: taller.tallerId,
        origenLat: widget.incidentPoint.latitude,
        origenLon: widget.incidentPoint.longitude,
        presupuestoAceptado: taller.presupuesto.montoFinal,
      );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        backgroundColor: AppColors.success,
        content: Text('Esperando a que ${taller.nombre} acepte tu solicitud...'),
      ));
      // Navegar al detalle de la solicitud — el WS push del backend
      // notificará cuando el taller acepte o rechace.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SolicitudDetalleScreen(solicitudId: widget.solicitudId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        backgroundColor: AppColors.error,
        content: Text(
          'No se pudo enviar tu selección: '
          '${e.toString().replaceFirst('Exception: ', '')}',
        ),
      ));
      setState(() => _selecting = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Elige tu taller'),
        actions: [
          IconButton(
            tooltip: 'Refrescar precios',
            onPressed: _loading ? null : () => _load(refresh: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: () => _load(refresh: true))
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final talleres = _talleresOrdenados;

    return Column(
      children: [
        // ── Header con info + sort dropdown ───────────────────────────
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_response?.total ?? 0} talleres disponibles',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              DropdownButton<_SortMode>(
                value: _sortMode,
                isDense: true,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: _SortMode.recomendado,  child: Text('Recomendado')),
                  DropdownMenuItem(value: _SortMode.masBarato,    child: Text('Más barato')),
                  DropdownMenuItem(value: _SortMode.masCercano,   child: Text('Más cercano')),
                  DropdownMenuItem(value: _SortMode.mejorRating,  child: Text('Mejor rating')),
                ],
                onChanged: (v) => setState(() => _sortMode = v ?? _SortMode.recomendado),
              ),
            ],
          ),
        ),

        // ── Mapa Mapbox (40% de altura) ───────────────────────────────
        if (AppConfig.hasMapboxAccessToken)
          SizedBox(
            height: 220,
            child: MapWidget(
              key: const ValueKey('budget-select-map'),
              styleUri: AppConfig.mapboxStyleUri,
              viewport: CameraViewportState(
                center: Point(coordinates: Position(
                  widget.incidentPoint.longitude, widget.incidentPoint.latitude,
                )),
                zoom: 12.5,
              ),
              onMapCreated: _onMapCreated,
              textureView: true,
            ),
          )
        else
          Container(
            height: 80,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.amber.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.all(12),
            child: const Center(child: Text('Mapbox no configurado — mostrando lista')),
          ),

        const SizedBox(height: 8),

        // ── Lista de talleres ─────────────────────────────────────────
        Expanded(
          child: talleres.isEmpty
              ? _EmptyState(mensaje: _response?.mensaje)
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  itemCount: talleres.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _TallerListItem(
                    taller: talleres[i],
                    onTap: () => _openBottomSheet(talleres[i]),
                  ),
                ),
        ),
      ],
    );
  }
}


// ════════════════════════════════════════════════════════════════════════
// Widgets auxiliares
// ════════════════════════════════════════════════════════════════════════


class _TallerListItem extends StatelessWidget {
  const _TallerListItem({required this.taller, required this.onTap});

  final TallerConPresupuesto taller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = taller.presupuesto;
    return Card(
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Icono según match/descuento
              CircleAvatar(
                radius: 20,
                backgroundColor: taller.matchEspecializacion
                    ? AppColors.success.withValues(alpha: 0.15)
                    : AppColors.primary.withValues(alpha: 0.15),
                child: Icon(
                  taller.matchEspecializacion ? Icons.verified : Icons.build_circle,
                  color: taller.matchEspecializacion ? AppColors.success : AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      taller.nombre,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _Chip(icon: Icons.star_rounded,    text: taller.ratingPromedio.toStringAsFixed(1)),
                        _Chip(icon: Icons.location_on,     text: '${taller.distanciaKm.toStringAsFixed(1)} km'),
                        if (taller.etaMin != null)
                          _Chip(icon: Icons.timer_outlined, text: '${taller.etaMin} min'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (p.tieneDescuento) ...[
                    Text(
                      '${p.moneda} ${p.montoBase.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: Colors.grey, fontSize: 11,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    Text(
                      '${p.moneda} ${p.montoFinal.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: AppColors.success,
                        fontSize: 16, fontWeight: FontWeight.w800,
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '-${p.descuentoPct!.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          color: AppColors.success,
                          fontSize: 10, fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ] else
                    Text(
                      '${p.moneda} ${p.montoFinal.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 16, fontWeight: FontWeight.w800,
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


class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.grey.shade600),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
      ],
    );
  }
}


class _TallerBottomSheet extends StatelessWidget {
  const _TallerBottomSheet({required this.taller, required this.onElegir});

  final TallerConPresupuesto taller;
  final VoidCallback onElegir;

  @override
  Widget build(BuildContext context) {
    final p = taller.presupuesto;
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize:     0.3,
      maxChildSize:     0.85,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Nombre + rating
            Row(
              children: [
                const Icon(Icons.build_circle, color: AppColors.primary, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    taller.nombre,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                ),
                const Icon(Icons.star_rounded, color: Colors.amber, size: 20),
                const SizedBox(width: 3),
                Text(
                  taller.ratingPromedio.toStringAsFixed(1),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ],
            ),
            if (taller.direccion != null && taller.direccion!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                taller.direccion!,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ],

            const SizedBox(height: 14),

            // Métricas: distancia + ETA + capacidad
            Row(
              children: [
                Expanded(child: _StatBlock(
                  icon: Icons.location_on,
                  label: 'Distancia',
                  value: '${taller.distanciaKm.toStringAsFixed(1)} km',
                )),
                Expanded(child: _StatBlock(
                  icon: Icons.timer_outlined,
                  label: 'ETA',
                  value: taller.etaMin != null ? '${taller.etaMin} min' : '—',
                )),
                Expanded(child: _StatBlock(
                  icon: Icons.people_outline,
                  label: 'Capacidad',
                  value: '${taller.capacidad}',
                )),
              ],
            ),

            const SizedBox(height: 18),

            // Presupuesto card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: p.tieneDescuento
                    ? AppColors.success.withValues(alpha: 0.08)
                    : AppColors.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: p.tieneDescuento
                      ? AppColors.success.withValues(alpha: 0.3)
                      : AppColors.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.attach_money, size: 18),
                      const SizedBox(width: 4),
                      const Text('Presupuesto',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      const Spacer(),
                      if (p.tieneDescuento)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.success,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '-${p.descuentoPct!.toStringAsFixed(0)}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11, fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (p.tieneDescuento)
                    Text(
                      '${p.moneda} ${p.montoBase.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.grey, fontSize: 12,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  Text(
                    '${p.moneda} ${p.montoFinal.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: p.tieneDescuento ? AppColors.success : AppColors.primary,
                      fontSize: 26, fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    'Rango estimado: ${p.moneda} ${p.rangoMin.toStringAsFixed(0)} – ${p.rangoMax.toStringAsFixed(0)}',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                  ),
                  if (p.motivoDescuento != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.local_offer_outlined,
                            size: 14, color: AppColors.success),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            p.motivoDescuento!,
                            style: const TextStyle(
                              color: AppColors.success,
                              fontSize: 12, fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (p.tiempoHoras != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.schedule, size: 14, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Text(
                          'Tiempo estimado de reparación: ${p.tiempoHoras!.toStringAsFixed(0)} h',
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Motivos / badges
            if (taller.motivo.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lightbulb_outline, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        taller.motivo,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Botón principal
            FilledButton.icon(
              onPressed: onElegir,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: AppColors.primary,
              ),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text(
                'Elegir este taller',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _StatBlock extends StatelessWidget {
  const _StatBlock({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
      ],
    );
  }
}


class _EmptyState extends StatelessWidget {
  const _EmptyState({this.mensaje});
  final String? mensaje;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'Sin talleres disponibles',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              mensaje ?? 'No encontramos talleres compatibles en tu zona. '
                  'Espera unos minutos o contacta a soporte.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}


class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

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
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
