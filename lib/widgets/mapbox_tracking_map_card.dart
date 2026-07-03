import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../config/app_config.dart';
import '../services/mapbox_service.dart';

class MapboxTrackingMapCard extends StatefulWidget {
  const MapboxTrackingMapCard({
    super.key,
    required this.mapbox,
    required this.clientLocation,
    required this.workshopLocation,
    required this.serviceLocation,
    required this.professionalLocation,
    required this.workshopName,
    required this.professionalName,
    required this.trackingEnabled,
    this.serverRoute,
    this.serverDistanceKm,
    this.isArrived = false,
    this.routeColorHex,
    this.fallbackEtaMin,
    this.updatedAt,
    this.onRouteComputed,
  });

  final MapboxService mapbox;
  final LatLng? clientLocation;
  final LatLng? workshopLocation;
  final LatLng? serviceLocation;
  final LatLng? professionalLocation;
  final String? workshopName;
  final String? professionalName;
  final bool trackingEnabled;
  /// Ruta vial taller→incidente calculada por el backend (`ruta_seguimiento`).
  /// Cuando viene, la dibujamos directo y NO llamamos a Mapbox desde el móvil:
  /// el camino coincide con la web y evitamos el 422 cliente. El "muñeco"
  /// simulado recorre exactamente esta geometría.
  final List<LatLng>? serverRoute;
  final double? serverDistanceKm;
  /// El equipo ya llegó al incidente (EN_ATENCION/COMPLETADA): paramos la
  /// animación y dejamos el muñeco estacionado sobre el lugar del servicio.
  final bool isArrived;
  final String? routeColorHex;
  final int? fallbackEtaMin;
  final String? updatedAt;
  final ValueChanged<MapboxRouteResult?>? onRouteComputed;

  @override
  State<MapboxTrackingMapCard> createState() => _MapboxTrackingMapCardState();
}

class _MapboxTrackingMapCardState extends State<MapboxTrackingMapCard> {
  static const _fallbackCenter = LatLng(-17.7863, -63.1812);

  MapboxMap? _mapboxMap;
  CircleAnnotationManager? _markerManager;
  PolylineAnnotationManager? _routeManager;
  MapboxRouteResult? _remainingRoute;
  MapboxRouteResult? _completedRoute;
  bool _routeLoading = false;
  int _requestSerial = 0;

  // Muñeco simulado: un marcador que recorre la ruta vial mientras el equipo
  // del taller va en camino. Usa su propio manager para sobrevivir a los
  // deleteAll() de _syncMap y se anima con un Timer (sin vsync).
  CircleAnnotationManager? _dotManager;
  CircleAnnotation? _dot;
  Timer? _dispatchTimer;
  double _dispatchT = 0.0;
  bool _dotBusy = false;
  static const double _dispatchStep = 0.0075; // ~8 s por recorrido a 60 ms

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshRoute();
    });
  }

  @override
  void didUpdateWidget(covariant MapboxTrackingMapCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final trackingChanged = oldWidget.trackingEnabled != widget.trackingEnabled;
    final workshopChanged = oldWidget.workshopLocation != widget.workshopLocation;
    final professionalChanged = oldWidget.professionalLocation != widget.professionalLocation;
    final serviceChanged = oldWidget.serviceLocation != widget.serviceLocation;
    // La ruta del backend llega como una lista nueva en cada poll; comparamos
    // por firma (largo + extremos) para no reiniciar la animación cada 30 s.
    final routeChanged = !_sameRoute(oldWidget.serverRoute, widget.serverRoute);
    final arrivedChanged = oldWidget.isArrived != widget.isArrived;
    if (trackingChanged || workshopChanged || professionalChanged || serviceChanged ||
        routeChanged || arrivedChanged) {
      _refreshRoute();
      _syncMap();
    }
  }

  bool _sameRoute(List<LatLng>? a, List<LatLng>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    return a.first == b.first && a.last == b.last;
  }

  @override
  void dispose() {
    _dispatchTimer?.cancel();
    super.dispose();
  }

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    _markerManager = await mapboxMap.annotations.createCircleAnnotationManager();
    _routeManager = await mapboxMap.annotations.createPolylineAnnotationManager();
    // Manager separado para el muñeco: así sus updates no chocan con el
    // deleteAll() de los marcadores fijos en _syncMap.
    _dotManager = await mapboxMap.annotations.createCircleAnnotationManager();
    await _syncMap();
    _startDispatchAnimation();
  }

  Future<void> _refreshRoute() async {
    final workshop = widget.workshopLocation;
    final from = widget.professionalLocation;
    final to = widget.serviceLocation;

    // 1) Ruta calculada por el backend (taller→incidente por calles): se
    //    dibuja directo, sin llamar a Mapbox desde el móvil. Es el caso del
    //    taller sin técnico — y la geometría que recorre el muñeco simulado.
    final server = widget.serverRoute;
    if (widget.trackingEnabled && server != null && server.length >= 2) {
      _requestSerial++; // cancela cualquier request cliente en vuelo
      final result = MapboxRouteResult(
        path: server,
        distanceKm: widget.serverDistanceKm ?? _polylineKm(server),
        durationMin: widget.fallbackEtaMin ?? 0,
      );
      if (!mounted) return;
      setState(() {
        _remainingRoute = result;
        _completedRoute = null;
        _routeLoading = false;
      });
      // El backend ya envía eta_min con rango; no pisamos el display de la
      // pantalla con la versión cliente.
      widget.onRouteComputed?.call(null);
      await _syncMap();
      _startDispatchAnimation();
      return;
    }

    if (!widget.trackingEnabled || from == null || to == null) {
      if (!mounted) return;
      setState(() {
        _remainingRoute = null;
        _completedRoute = null;
        _routeLoading = false;
      });
      widget.onRouteComputed?.call(null);
      _stopDispatchAnimation();
      _clearDot();
      await _syncMap();
      return;
    }

    final requestId = ++_requestSerial;
    if (mounted) {
      setState(() => _routeLoading = true);
    }
    try {
      final nextRemaining = await widget.mapbox.routeDriving(from, to);
      MapboxRouteResult? nextCompleted;
      // Sólo trazamos el "recorrido" si el taller difiere del punto actual
      // (caso con técnico). Si coinciden (taller sin técnico), routeDriving de
      // un punto consigo mismo lanzaría — lo evitamos para no perder la ruta.
      if (workshop != null && workshop != from) {
        try {
          nextCompleted = await widget.mapbox.routeDriving(workshop, from);
        } catch (_) {
          nextCompleted = null;
        }
      }
      if (!mounted || requestId != _requestSerial) return;
      setState(() {
        _remainingRoute = nextRemaining;
        _completedRoute = nextCompleted;
        _routeLoading = false;
      });
      widget.onRouteComputed?.call(nextRemaining);
      _startDispatchAnimation();
    } catch (_) {
      if (!mounted || requestId != _requestSerial) return;
      setState(() {
        _remainingRoute = null;
        _completedRoute = null;
        _routeLoading = false;
      });
      widget.onRouteComputed?.call(null);
      _stopDispatchAnimation();
      _clearDot();
    }
    await _syncMap();
  }

  // --- Muñeco simulado -----------------------------------------------------

  /// Simulamos el marcador móvil cuando hay ruta dibujable, el equipo va en
  /// camino (no llegó) y NO hay un profesional con GPS real: es decir, taller
  /// sin técnico (ruta del backend) o cualquier seguimiento sin ubicación viva.
  bool get _shouldSimulate {
    if (!widget.trackingEnabled || widget.isArrived) return false;
    final path = _remainingRoute?.path;
    if (path == null || path.length < 2) return false;
    final noRealProfessional = (widget.professionalName ?? '').trim().isEmpty;
    return widget.serverRoute != null || noRealProfessional;
  }

  void _startDispatchAnimation() {
    if (!_shouldSimulate) {
      _stopDispatchAnimation();
      // Si ya llegó, el muñeco queda sobre el incidente; si no, se quita.
      if (widget.isArrived && widget.serviceLocation != null) {
        _moveDot(widget.serviceLocation!);
      } else {
        _clearDot();
      }
      return;
    }
    if (_dispatchTimer != null) return; // ya está corriendo: no reiniciar
    _dispatchTimer = Timer.periodic(
      const Duration(milliseconds: 60),
      (_) => _onDispatchTick(),
    );
  }

  void _stopDispatchAnimation() {
    _dispatchTimer?.cancel();
    _dispatchTimer = null;
  }

  void _onDispatchTick() {
    final path = _remainingRoute?.path;
    if (path == null || path.length < 2) return;
    _dispatchT += _dispatchStep;
    if (_dispatchT > 1.0) _dispatchT = 0.0; // recorrido en bucle
    _moveDot(_pointAlong(path, _dispatchT));
  }

  Future<void> _moveDot(LatLng pos) async {
    final mgr = _dotManager;
    if (mgr == null || _dotBusy) return;
    _dotBusy = true;
    try {
      final point = Point(coordinates: Position(pos.longitude, pos.latitude));
      final dot = _dot;
      if (dot == null) {
        _dot = await mgr.create(
          CircleAnnotationOptions(
            geometry: point,
            circleColor: const Color(0xFFF59E0B).toARGB32(), // ámbar = vehículo
            circleRadius: 10,
            circleStrokeColor: Colors.white.toARGB32(),
            circleStrokeWidth: 3,
          ),
        );
      } else {
        dot.geometry = point;
        await mgr.update(dot);
      }
    } catch (_) {
      // Errores transitorios del canal nativo: el próximo tick reintenta.
    } finally {
      _dotBusy = false;
    }
  }

  void _clearDot() {
    _dot = null;
    _dotManager?.deleteAll();
  }

  /// Interpola un punto sobre la polilínea `path` para la fracción `t`∈[0,1]
  /// del recorrido, ponderada por la longitud real de cada segmento.
  LatLng _pointAlong(List<LatLng> path, double t) {
    if (path.isEmpty) return _fallbackCenter;
    if (path.length == 1) return path.first;
    const distance = Distance();
    final segLen = <double>[];
    double total = 0;
    for (var i = 0; i < path.length - 1; i++) {
      final d = distance(path[i], path[i + 1]);
      segLen.add(d);
      total += d;
    }
    if (total <= 0) return path.first;
    var target = t.clamp(0.0, 1.0) * total;
    for (var i = 0; i < segLen.length; i++) {
      if (target <= segLen[i] || i == segLen.length - 1) {
        final f = segLen[i] <= 0 ? 0.0 : (target / segLen[i]).clamp(0.0, 1.0);
        final a = path[i];
        final b = path[i + 1];
        return LatLng(
          a.latitude + (b.latitude - a.latitude) * f,
          a.longitude + (b.longitude - a.longitude) * f,
        );
      }
      target -= segLen[i];
    }
    return path.last;
  }

  double _polylineKm(List<LatLng> path) {
    if (path.length < 2) return 0;
    const distance = Distance();
    double total = 0;
    for (var i = 0; i < path.length - 1; i++) {
      total += distance(path[i], path[i + 1]);
    }
    return double.parse((total / 1000).toStringAsFixed(2));
  }

  Future<void> _syncMap() async {
    final mapboxMap = _mapboxMap;
    final markerManager = _markerManager;
    final routeManager = _routeManager;
    if (mapboxMap == null || markerManager == null || routeManager == null) return;

    final width = mounted ? MediaQuery.sizeOf(context).width : 800.0;

    await markerManager.deleteAll();
    await routeManager.deleteAll();

    final markerOptions = <CircleAnnotationOptions>[
      if (widget.workshopLocation != null)
        CircleAnnotationOptions(
          geometry: Point(
            coordinates: Position(widget.workshopLocation!.longitude, widget.workshopLocation!.latitude),
          ),
          circleColor: const Color(0xFF2563EB).toARGB32(),
          circleRadius: 8,
          circleStrokeColor: Colors.white.toARGB32(),
          circleStrokeWidth: 3,
        ),
      if (widget.professionalLocation != null)
        CircleAnnotationOptions(
          geometry: Point(
            coordinates: Position(widget.professionalLocation!.longitude, widget.professionalLocation!.latitude),
          ),
          circleColor: const Color(0xFF16A34A).toARGB32(),
          circleRadius: 8,
          circleStrokeColor: Colors.white.toARGB32(),
          circleStrokeWidth: 3,
        ),
      if (widget.serviceLocation != null)
        CircleAnnotationOptions(
          geometry: Point(
            coordinates: Position(widget.serviceLocation!.longitude, widget.serviceLocation!.latitude),
          ),
          circleColor: const Color(0xFFEF4444).toARGB32(),
          circleRadius: 8,
          circleStrokeColor: Colors.white.toARGB32(),
          circleStrokeWidth: 3,
        ),
    ];
    if (markerOptions.isNotEmpty) {
      await markerManager.createMulti(markerOptions);
    }

    final routeColor = _colorFromHex(widget.routeColorHex) ?? const Color(0xFF2563EB);
    if (_completedRoute != null) {
      await routeManager.create(
        PolylineAnnotationOptions(
          geometry: LineString(
            coordinates: _completedRoute!.path
                .map((point) => Position(point.longitude, point.latitude))
                .toList(growable: false),
          ),
          lineColor: routeColor.withAlpha((255 * 0.28).round()).toARGB32(),
          lineWidth: width < 560 ? 4 : 5,
        ),
      );
    }
    if (_remainingRoute != null) {
      await routeManager.create(
        PolylineAnnotationOptions(
          geometry: LineString(
            coordinates: _remainingRoute!.path
                .map((point) => Position(point.longitude, point.latitude))
                .toList(growable: false),
          ),
          lineColor: routeColor.toARGB32(),
          lineWidth: width < 560 ? 5 : 6,
        ),
      );
    }

    final points = <LatLng>[
      if (widget.workshopLocation != null) widget.workshopLocation!,
      if (widget.serviceLocation != null) widget.serviceLocation!,
      if (widget.professionalLocation != null) widget.professionalLocation!,
    ];
    final center = points.isNotEmpty ? points.first : _fallbackCenter;
    await mapboxMap.setCamera(
      CameraOptions(
        center: Point(coordinates: Position(center.longitude, center.latitude)),
        zoom: points.length <= 1 ? 15 : 13,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final routeColor = _colorFromHex(widget.routeColorHex) ?? const Color(0xFF2563EB);
    final eta = _remainingRoute?.durationMin ?? widget.fallbackEtaMin;
    final distance = _remainingRoute?.distanceKm;
    final points = <LatLng>[
      if (widget.workshopLocation != null) widget.workshopLocation!,
      if (widget.serviceLocation != null) widget.serviceLocation!,
      if (widget.professionalLocation != null) widget.professionalLocation!,
    ];
    final center = points.isNotEmpty ? points.first : _fallbackCenter;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ruta en tiempo real', style: Theme.of(context).textTheme.titleMedium),
                      if (widget.workshopName != null && widget.workshopName!.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('Taller: ${widget.workshopName!}'),
                        ),
                      if (widget.professionalName != null && widget.professionalName!.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('Profesional: ${widget.professionalName!}'),
                        ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Pill(
                      label: 'Ruta exclusiva',
                      background: routeColor.withAlpha((255 * 0.12).round()),
                      foreground: routeColor,
                    ),
                    if (eta != null)
                      _Pill(
                        label: 'ETA $eta min',
                        background: const Color(0xFFE0F2FE),
                        foreground: const Color(0xFF0369A1),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: MediaQuery.of(context).size.width < 560 ? 250 : 320,
                child: !AppConfig.hasMapboxAccessToken
                    ? const ColoredBox(
                        color: Color(0xFFF8FAFC),
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'Mapbox no está configurado en móvil. Define ACCESS_TOKEN para visualizar el seguimiento.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      )
                    : MapWidget(
                        key: const ValueKey('mapbox-tracking-card'),
                        styleUri: AppConfig.mapboxStyleUri,
                        viewport: CameraViewportState(
                          center: Point(coordinates: Position(center.longitude, center.latitude)),
                          zoom: points.length <= 1 ? 15 : 13,
                        ),
                        onMapCreated: _onMapCreated,
                        textureView: true,
                      ),
              ),
            ),
            const SizedBox(height: 10),
            if (_routeLoading) const LinearProgressIndicator(minHeight: 3),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (_completedRoute != null)
                  Text(
                    'Trayecto recorrido: ${_completedRoute!.distanceKm.toStringAsFixed(2)} km',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                Text(
                  distance != null ? 'Distancia restante: ${distance.toStringAsFixed(2)} km' : 'Distancia restante: --',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  eta != null ? 'Llegada estimada: $eta min' : 'Llegada estimada: --',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            if (widget.updatedAt != null && widget.updatedAt!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Última ubicación: ${widget.updatedAt}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color? _colorFromHex(String? value) {
    final raw = (value ?? '').trim();
    if (!RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(raw)) return null;
    final hex = raw.startsWith('#') ? raw.substring(1) : raw;
    return Color(int.parse('FF$hex', radix: 16));
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
