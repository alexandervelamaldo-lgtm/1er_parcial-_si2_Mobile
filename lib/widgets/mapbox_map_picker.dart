import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../config/app_config.dart';
import '../services/mapbox_service.dart';

// ── Marker type ───────────────────────────────────────────────────────────────

enum MapboxMarkerType {
  /// Solicitud / incidente vehicular (rojo)
  incident,

  /// Taller / técnico cercano (azul)
  taller,

  /// Unidad en camino (verde)
  unit,
}

// ── Data model ────────────────────────────────────────────────────────────────

class MapboxMapMarker {
  const MapboxMapMarker({
    required this.id,
    this.tenantKey,
    required this.point,
    required this.label,
    this.color = const Color(0xFF2563EB),
    this.type = MapboxMarkerType.incident,
  });

  final int id;
  final String? tenantKey;
  final LatLng point;
  final String label;

  /// Background color of the pin circle.
  final Color color;

  /// Determines which icon is drawn inside the pin.
  final MapboxMarkerType type;
}

// ── Location picked ───────────────────────────────────────────────────────────

class MapboxPickedLocation {
  const MapboxPickedLocation({
    required this.point,
    required this.address,
  });

  final LatLng point;
  final String address;
}

// ── Active route (incident → workshop) ────────────────────────────────────────

/// Represents an in-route service that should be drawn on the map:
/// a polyline from the incident location to the assigned workshop,
/// plus a small ETA pill.
class MapboxMapRoute {
  const MapboxMapRoute({
    required this.solicitudId,
    this.tenantKey,
    required this.incident,
    required this.workshop,
    this.color = const Color(0xFFF97316),
    this.fallbackEtaMin,
    this.label,
  });

  final int solicitudId;
  final String? tenantKey;
  final LatLng incident;
  final LatLng workshop;
  final Color color;

  /// ETA reported by the backend; used while the real route loads, and as
  /// fallback if the Mapbox routing call fails.
  final int? fallbackEtaMin;

  /// Optional short label (e.g. "Solicitud #42"). Shown in the ETA pill.
  final String? label;
}

/// ETA + distance computed for a [MapboxMapRoute].
class _RouteSummary {
  const _RouteSummary({this.durationMin, this.distanceKm});
  final int? durationMin;
  final double? distanceKm;
}

// ── Icon helpers ──────────────────────────────────────────────────────────────

IconData _iconForType(MapboxMarkerType type) => switch (type) {
      MapboxMarkerType.incident => Icons.car_crash_rounded,
      MapboxMarkerType.taller   => Icons.build_rounded,
      MapboxMarkerType.unit     => Icons.local_shipping_rounded,
    };

/// Renders a circular pin with a Material icon as PNG bytes.
/// [bg] is the fill color; the white ring and subtle shadow are always drawn.
Future<Uint8List> _buildPinPng({
  required Color bg,
  required IconData icon,
  Color iconColor = Colors.white,
  int size = 64,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas   = Canvas(recorder);
  final cx       = size / 2.0;
  final r        = cx - 7.0;

  // ── Drop shadow ──────────────────────────────────────────────────────────
  canvas.drawCircle(
    Offset(cx + 1.5, cx + 3.0),
    r,
    Paint()
      ..color      = const Color(0x33000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
  );

  // ── Filled circle ────────────────────────────────────────────────────────
  canvas.drawCircle(Offset(cx, cx), r, Paint()..color = bg);

  // ── White ring ───────────────────────────────────────────────────────────
  canvas.drawCircle(
    Offset(cx, cx),
    r,
    Paint()
      ..color       = Colors.white
      ..style       = PaintingStyle.stroke
      ..strokeWidth = 3.5,
  );

  // ── Icon ─────────────────────────────────────────────────────────────────
  final tp = TextPainter(textDirection: ui.TextDirection.ltr)
    ..text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize:   size * 0.40,
        fontFamily: icon.fontFamily,
        package:    icon.fontPackage,
        color:      iconColor,
      ),
    )
    ..layout();
  tp.paint(canvas, Offset((size - tp.width) / 2, (size - tp.height) / 2));

  final picture = recorder.endRecording();
  final img     = await picture.toImage(size, size);
  final bd      = await img.toByteData(format: ui.ImageByteFormat.png);
  return bd!.buffer.asUint8List();
}

// ── Widget ────────────────────────────────────────────────────────────────────

class MapboxMapPicker extends StatefulWidget {
  const MapboxMapPicker({
    super.key,
    required this.mapbox,
    this.initialCenter = const LatLng(-17.7863, -63.1812),
    this.initialZoom = 13,
    this.unitLocation,
    this.markers = const [],
    this.activeRoutes = const [],
    this.onMarkerTap,
    this.onRouteTap,
    this.onConfirm,
    this.showAddressCard = true,
  });

  final MapboxService mapbox;
  final LatLng initialCenter;
  final double initialZoom;
  final LatLng? unitLocation;
  final List<MapboxMapMarker> markers;
  final bool showAddressCard;

  /// In-route services (incident → workshop) drawn as polylines on the map
  /// with an ETA pill below.
  final List<MapboxMapRoute> activeRoutes;

  final ValueChanged<MapboxMapMarker>? onMarkerTap;
  final ValueChanged<MapboxMapRoute>? onRouteTap;
  final ValueChanged<MapboxPickedLocation>? onConfirm;

  @override
  State<MapboxMapPicker> createState() => _MapboxMapPickerState();
}

class _MapboxMapPickerState extends State<MapboxMapPicker> {
  PointAnnotationManager? _selectionManager;
  PointAnnotationManager? _unitManager;
  PointAnnotationManager? _markersManager;
  PolylineAnnotationManager? _routeManager;
  PolylineAnnotationManager? _activeRoutesManager;
  PointAnnotationManager? _workshopMarkersManager;
  Cancelable? _markerTapCancelable;
  MapboxMap? _mapboxMap;
  final Map<String, MapboxMapMarker> _markerByAnnotationId = {};
  static const String _mapTapInteractionId = 'mapbox-map-picker-tap';

  // Pre-generated pin PNGs ─────────────────────────────────────────────────
  Uint8List? _selectionPng; // orange "place" pin  → selected point
  Uint8List? _unitPng;      // green  truck         → technician unit
  Uint8List? _workshopPng;  // blue   wrench        → taller endpoint
  // Per-marker PNGs are cached keyed by (color, type)
  final Map<int, Uint8List> _pngCache = {};

  // Live route summaries per solicitudId (real Mapbox-computed values)
  final Map<int, _RouteSummary> _routeSummaries = {};
  int _activeRoutesSerial = 0;

  // Map state ──────────────────────────────────────────────────────────────
  Timer?   _routeRefreshTimer;
  LatLng?  _selectedPoint;
  String   _address        = '';
  bool     _reverseLoading = false;
  String?  _reverseError;
  bool     _routeLoading   = false;
  String?  _routeError;
  MapboxRouteResult? _route;

  @override
  void initState() {
    super.initState();
    _selectedPoint = widget.initialCenter;
  }

  @override
  void didUpdateWidget(covariant MapboxMapPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unitLocation != widget.unitLocation) {
      _configureRouteRefresh(reset: true);
      unawaited(_refreshRoute());
      unawaited(_syncUnitMarker());
    }
    if (oldWidget.markers != widget.markers) {
      unawaited(_syncMarkers());
    }
    if (!_sameRoutes(oldWidget.activeRoutes, widget.activeRoutes)) {
      unawaited(_syncActiveRoutes());
    }
  }

  bool _sameRoutes(List<MapboxMapRoute> a, List<MapboxMapRoute> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].solicitudId != b[i].solicitudId ||
          a[i].incident != b[i].incident ||
          a[i].workshop != b[i].workshop) {
        return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    _routeRefreshTimer?.cancel();
    _markerTapCancelable?.cancel();
    _mapboxMap?.removeInteraction(_mapTapInteractionId);
    super.dispose();
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    // Pre-generate fixed-purpose pins
    _selectionPng = await _buildPinPng(
      bg:   const Color(0xFFF97316), // orange
      icon: Icons.place_rounded,
    );
    _unitPng = await _buildPinPng(
      bg:   const Color(0xFF16A34A), // green
      icon: Icons.local_shipping_rounded,
    );
    _workshopPng = await _buildPinPng(
      bg:   const Color(0xFF2563EB), // blue
      icon: Icons.build_rounded,
    );

    _selectionManager        = await mapboxMap.annotations.createPointAnnotationManager();
    _unitManager             = await mapboxMap.annotations.createPointAnnotationManager();
    _markersManager          = await mapboxMap.annotations.createPointAnnotationManager();
    _workshopMarkersManager  = await mapboxMap.annotations.createPointAnnotationManager();
    _activeRoutesManager     = await mapboxMap.annotations.createPolylineAnnotationManager();
    _routeManager            = await mapboxMap.annotations.createPolylineAnnotationManager();

    _markerTapCancelable = _markersManager?.tapEvents(
      onTap: (annotation) {
        final marker = _markerByAnnotationId[annotation.id];
        if (marker != null) widget.onMarkerTap?.call(marker);
      },
    );

    await mapboxMap.setCamera(
      CameraOptions(
        center: Point(
          coordinates: Position(
            widget.initialCenter.longitude,
            widget.initialCenter.latitude,
          ),
        ),
        zoom: widget.initialZoom,
      ),
    );
    mapboxMap.addInteraction(
      TapInteraction.onMap(_onTap),
      interactionID: _mapTapInteractionId,
    );

    await _syncSelectionMarker();
    await _syncUnitMarker();
    await _syncMarkers();
    await _syncActiveRoutes();
    await _refreshAddress();
    _configureRouteRefresh(reset: true);
    await _refreshRoute();
  }

  // ── Active routes (incident → workshop) ───────────────────────────────────

  Future<void> _syncActiveRoutes() async {
    final manager        = _activeRoutesManager;
    final workshopMgr    = _workshopMarkersManager;
    final workshopPng    = _workshopPng;
    if (manager == null || workshopMgr == null || workshopPng == null) return;

    // Invalidate previous in-flight computations
    final serial = ++_activeRoutesSerial;

    await manager.deleteAll();
    await workshopMgr.deleteAll();

    final routes = widget.activeRoutes;
    if (routes.isEmpty) {
      if (mounted && _routeSummaries.isNotEmpty) {
        setState(_routeSummaries.clear);
      }
      return;
    }

    // ── Draw workshop endpoints (blue wrench pins) ───────────────────────────
    await workshopMgr.createMulti(
      routes
          .map((r) => PointAnnotationOptions(
                geometry:   Point(coordinates: Position(r.workshop.longitude, r.workshop.latitude)),
                image:      workshopPng,
                iconSize:   0.85,
                iconAnchor: IconAnchor.CENTER,
              ))
          .toList(growable: false),
    );

    // ── Draw a straight "placeholder" polyline immediately so the user
    //    sees the connection right away while the real route is fetched.
    for (final r in routes) {
      await manager.create(
        PolylineAnnotationOptions(
          geometry: LineString(coordinates: [
            Position(r.incident.longitude, r.incident.latitude),
            Position(r.workshop.longitude, r.workshop.latitude),
          ]),
          lineColor: r.color.withAlpha((255 * 0.45).round()).toARGB32(),
          lineWidth: 3,
        ),
      );
    }

    // ── Fetch real driving routes (cached inside MapboxService) ──────────────
    final fetched = await Future.wait(
      routes.map((r) async {
        try {
          final res = await widget.mapbox.routeDriving(r.incident, r.workshop);
          return MapEntry(r, res);
        } catch (_) {
          return MapEntry<MapboxMapRoute, MapboxRouteResult?>(r, null);
        }
      }),
    );

    if (!mounted || serial != _activeRoutesSerial) return;

    // Replace placeholders with the real polylines
    await manager.deleteAll();
    final summaries = <int, _RouteSummary>{};
    for (final entry in fetched) {
      final route  = entry.key;
      final result = entry.value;

      if (result != null) {
        await manager.create(
          PolylineAnnotationOptions(
            geometry: LineString(
              coordinates: result.path
                  .map((p) => Position(p.longitude, p.latitude))
                  .toList(growable: false),
            ),
            lineColor: route.color.toARGB32(),
            lineWidth: 5,
          ),
        );
        summaries[route.solicitudId] = _RouteSummary(
          durationMin: result.durationMin,
          distanceKm:  result.distanceKm,
        );
      } else {
        // Fall back to the straight-line placeholder + backend ETA
        await manager.create(
          PolylineAnnotationOptions(
            geometry: LineString(coordinates: [
              Position(route.incident.longitude, route.incident.latitude),
              Position(route.workshop.longitude, route.workshop.latitude),
            ]),
            lineColor: route.color.withAlpha((255 * 0.6).round()).toARGB32(),
            lineWidth: 3,
          ),
        );
        summaries[route.solicitudId] = _RouteSummary(
          durationMin: route.fallbackEtaMin,
        );
      }
    }

    if (mounted) {
      setState(() {
        _routeSummaries
          ..clear()
          ..addAll(summaries);
      });
    }
  }

  // ── Pin cache ─────────────────────────────────────────────────────────────

  Future<Uint8List> _getOrBuildPng(MapboxMapMarker marker) async {
    // Cache key: high 32 bits = ARGB color, low 8 bits = type index
    final key = (marker.color.toARGB32() << 8) | marker.type.index;
    if (_pngCache.containsKey(key)) return _pngCache[key]!;
    final png = await _buildPinPng(
      bg:   marker.color,
      icon: _iconForType(marker.type),
    );
    _pngCache[key] = png;
    return png;
  }

  // ── Route refresh ─────────────────────────────────────────────────────────

  void _configureRouteRefresh({required bool reset}) {
    if (reset) {
      _routeRefreshTimer?.cancel();
      _routeRefreshTimer = null;
    }
    if (widget.unitLocation == null) return;
    _routeRefreshTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_refreshRoute());
    });
  }

  // ── Tap handler ───────────────────────────────────────────────────────────

  void _onTap(MapContentGestureContext context) {
    final point = LatLng(
      context.point.coordinates.lat.toDouble(),
      context.point.coordinates.lng.toDouble(),
    );
    setState(() => _selectedPoint = point);
    unawaited(_syncSelectionMarker());
    unawaited(_refreshAddress());
    unawaited(_refreshRoute());
  }

  // ── Marker sync ───────────────────────────────────────────────────────────

  Future<void> _syncSelectionMarker() async {
    final manager = _selectionManager;
    final point   = _selectedPoint;
    final png     = _selectionPng;
    if (manager == null || point == null || png == null) return;
    await manager.deleteAll();
    await manager.create(
      PointAnnotationOptions(
        geometry:    Point(coordinates: Position(point.longitude, point.latitude)),
        image:       png,
        iconSize:    1.0,
        iconAnchor:  IconAnchor.CENTER,
      ),
    );
  }

  Future<void> _syncUnitMarker() async {
    final manager = _unitManager;
    final png     = _unitPng;
    if (manager == null || png == null) return;
    await manager.deleteAll();
    final point = widget.unitLocation;
    if (point == null) return;
    await manager.create(
      PointAnnotationOptions(
        geometry:   Point(coordinates: Position(point.longitude, point.latitude)),
        image:      png,
        iconSize:   1.0,
        iconAnchor: IconAnchor.CENTER,
      ),
    );
  }

  Future<void> _syncMarkers() async {
    final manager = _markersManager;
    if (manager == null) return;
    _markerByAnnotationId.clear();
    await manager.deleteAll();
    if (widget.markers.isEmpty) return;

    // Build all PointAnnotationOptions (async PNG generation with cache)
    final options = await Future.wait(
      widget.markers.map((marker) async {
        final png = await _getOrBuildPng(marker);
        return PointAnnotationOptions(
          geometry:   Point(coordinates: Position(marker.point.longitude, marker.point.latitude)),
          image:      png,
          iconSize:   1.0,
          iconAnchor: IconAnchor.CENTER,
        );
      }),
    );

    final created = await manager.createMulti(options);
    for (var i = 0; i < created.length && i < widget.markers.length; i++) {
      final annotation = created[i];
      if (annotation == null) continue;
      _markerByAnnotationId[annotation.id] = widget.markers[i];
    }
  }

  // ── Geocoding ─────────────────────────────────────────────────────────────

  Future<void> _refreshAddress() async {
    final point = _selectedPoint;
    if (point == null) return;
    if (mounted) setState(() { _reverseLoading = true; _reverseError = null; });
    try {
      final name = await widget.mapbox.reverseGeocode(point);
      if (!mounted) return;
      setState(() => _address = name);
    } catch (_) {
      if (!mounted) return;
      setState(() => _reverseError = 'No se pudo obtener la dirección. Reintentá.');
    } finally {
      if (mounted) setState(() => _reverseLoading = false);
    }
  }

  // ── Route ─────────────────────────────────────────────────────────────────

  Future<void> _refreshRoute() async {
    final unit     = widget.unitLocation;
    final selected = _selectedPoint;
    final manager  = _routeManager;
    if (manager == null) return;

    if (unit == null || selected == null) {
      await manager.deleteAll();
      if (mounted) {
        setState(() { _route = null; _routeError = null; _routeLoading = false; });
      }
      return;
    }

    if (mounted) setState(() { _routeLoading = true; _routeError = null; });
    try {
      final route = await widget.mapbox.routeDriving(unit, selected);
      await manager.deleteAll();
      await manager.create(
        PolylineAnnotationOptions(
          geometry: LineString(
            coordinates: route.path
                .map((p) => Position(p.longitude, p.latitude))
                .toList(growable: false),
          ),
          lineColor: const Color(0xFF2563EB).toARGB32(),
          lineWidth: 5,
        ),
      );
      if (!mounted) return;
      setState(() => _route = route);
    } catch (_) {
      await manager.deleteAll();
      if (!mounted) return;
      setState(() { _route = null; _routeError = 'No se pudo calcular la ruta. Reintentá.'; });
    } finally {
      if (mounted) setState(() => _routeLoading = false);
    }
  }

  // ── Confirm ───────────────────────────────────────────────────────────────

  void _confirm() {
    final point = _selectedPoint;
    if (point == null) return;
    widget.onConfirm?.call(
      MapboxPickedLocation(point: point, address: _address),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final selected = _selectedPoint ?? widget.initialCenter;

    return Stack(
      children: [
        if (!AppConfig.hasMapboxAccessToken)
          _buildTokenError()
        else
          MapWidget(
            key:            const ValueKey('mapbox-map-picker'),
            styleUri:       AppConfig.mapboxStyleUri,
            viewport:       CameraViewportState(
              center: Point(
                coordinates: Position(
                  widget.initialCenter.longitude,
                  widget.initialCenter.latitude,
                ),
              ),
              zoom: widget.initialZoom,
            ),
            onMapCreated:   _onMapCreated,
            textureView:    true,
          ),

        // ── Address card ────────────────────────────────────────────────────
        if (widget.showAddressCard)
          Positioned(
            top: 12, left: 12, right: 12,
            child: Material(
              elevation: 2,
              borderRadius: BorderRadius.circular(14),
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ubicación del incidente',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _reverseLoading
                          ? 'Obteniendo dirección...'
                          : (_address.isEmpty
                              ? 'Toca el mapa para seleccionar un punto.'
                              : _address),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${selected.latitude.toStringAsFixed(5)}, '
                      '${selected.longitude.toStringAsFixed(5)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (_reverseError != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _reverseError!,
                        style: const TextStyle(
                            color: Colors.red, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

        // ── Active routes ETA strip (when widget has activeRoutes) ───────────
        if (widget.activeRoutes.isNotEmpty)
          Positioned(
            left: 12, right: 12, bottom: 12,
            child: SafeArea(
              child: _ActiveRoutesStrip(
                routes: widget.activeRoutes,
                summaries: _routeSummaries,
                onTap: widget.onRouteTap,
              ),
            ),
          )
        // ── Route info + confirm button (only in picker mode) ────────────────
        else if (widget.onConfirm != null || widget.unitLocation != null)
        Positioned(
          left: 12, right: 12, bottom: 12,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.unitLocation != null)
                  Material(
                    elevation: 2,
                    borderRadius: BorderRadius.circular(14),
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.route, color: Color(0xFF2563EB)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _routeLoading
                                  ? 'Calculando ruta...'
                                  : _route != null
                                      ? '${_route!.distanceKm.toStringAsFixed(2)} km'
                                          ' · ${_route!.durationMin} min'
                                      : (_routeError ?? '--'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: _routeError != null
                                    ? Colors.red
                                    : Colors.black87,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _refreshRoute,
                            icon: const Icon(Icons.refresh),
                            tooltip: 'Recalcular',
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: AppConfig.hasMapboxAccessToken ? _confirm : null,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Confirmar ubicación'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTokenError() {
    return Container(
      color: const Color(0xFFF8FAFC),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: const Text(
        'Mapbox no está configurado. Ejecuta la app con '
        '--dart-define-from-file=.env.json y ACCESS_TOKEN.',
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ── Active routes ETA strip (horizontal pills, tappable) ─────────────────────

class _ActiveRoutesStrip extends StatelessWidget {
  const _ActiveRoutesStrip({
    required this.routes,
    required this.summaries,
    this.onTap,
  });

  final List<MapboxMapRoute> routes;
  final Map<int, _RouteSummary> summaries;
  final ValueChanged<MapboxMapRoute>? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(14),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.route_rounded, size: 18, color: Color(0xFF2563EB)),
                const SizedBox(width: 6),
                Text(
                  'Servicios en camino · ${routes.length}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: routes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final r        = routes[i];
                  final summary  = summaries[r.solicitudId];
                  final eta      = summary?.durationMin ?? r.fallbackEtaMin;
                  final distance = summary?.distanceKm;
                  final etaText  = eta != null ? 'ETA $eta min' : 'Calculando…';
                  final distText = distance != null ? ' · ${distance.toStringAsFixed(1)} km' : '';
                  return InkWell(
                    onTap: onTap == null ? null : () => onTap!(r),
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: r.color.withAlpha((255 * 0.12).round()),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: r.color.withAlpha((255 * 0.35).round())),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8, height: 8,
                            decoration: BoxDecoration(
                              color: r.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            r.label != null
                                ? '${r.label} · $etaText$distText'
                                : '#${r.solicitudId} · $etaText$distText',
                            style: TextStyle(
                              color: r.color,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
