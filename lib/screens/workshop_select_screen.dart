import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../config/app_config.dart';
import '../models/taller_mapa.dart';
import '../services/api_service.dart';
import '../services/mapbox_service.dart';


class WorkshopSelectResult {
  const WorkshopSelectResult({
    required this.taller,
    required this.presupuestoAceptado,
  });

  final TallerMapa taller;
  final double? presupuestoAceptado;
}


class WorkshopSelectScreen extends StatefulWidget {
  const WorkshopSelectScreen({
    super.key,
    required this.api,
    required this.mapbox,
    required this.token,
    required this.incidentPoint,
    required this.danoCategoria,
    required this.vehicleBrand,
  });

  final ApiService api;
  final MapboxService mapbox;
  final String token;
  final LatLng incidentPoint;
  final String? danoCategoria;
  final String? vehicleBrand;

  @override
  State<WorkshopSelectScreen> createState() => _WorkshopSelectScreenState();
}


class _WorkshopSelectScreenState extends State<WorkshopSelectScreen> {
  final TextEditingController _presupuestoController = TextEditingController();
  final Map<String, TallerMapa> _markerByAnnotationId = <String, TallerMapa>{};

  MapboxMap? _mapboxMap;
  CircleAnnotationManager? _markerManager;
  PolylineAnnotationManager? _routeManager;
  Cancelable? _markerTapCancelable;

  double _radioKm = 25.0;
  bool _loading = true;
  String? _error;

  List<TallerMapa> _talleres = const [];
  TallerMapa? _selected;

  MapboxRouteResult? _ruta;
  bool _rutaLoading = false;
  String? _rutaError;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _presupuestoController.dispose();
    _markerTapCancelable?.cancel();
    widget.mapbox.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _loadTalleres();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadTalleres() async {
    final talleres = await widget.api.obtenerTalleresMapa(
      widget.token,
      danoCategoria: widget.danoCategoria,
      marcaVehiculo: widget.vehicleBrand,
      lat: widget.incidentPoint.latitude,
      lon: widget.incidentPoint.longitude,
      radioKm: _radioKm,
    );

    if (!mounted) return;
    setState(() {
      _talleres = talleres;
      if (_selected != null && !_talleres.any((t) => t.id == _selected!.id)) {
        _selected = null;
        _ruta = null;
      }
    });
    await _syncMap();
  }

  Future<void> _refreshRoute() async {
    final selected = _selected;
    if (selected == null) return;
    if (_rutaLoading) return;

    setState(() {
      _rutaLoading = true;
      _rutaError = null;
    });

    try {
      final route = await widget.mapbox.routeDriving(
        LatLng(selected.latitud, selected.longitud),
        widget.incidentPoint,
      );
      if (!mounted) return;
      setState(() {
        _ruta = route;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rutaError = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _rutaLoading = false;
        });
      }
    }
    await _syncMap();
  }

  void _selectTaller(TallerMapa taller) {
    setState(() {
      _selected = taller;
    });
    _refreshRoute();
  }

  double? _parsePresupuesto() {
    final raw = _presupuestoController.text.trim();
    if (raw.isEmpty) return null;
    final v = double.tryParse(raw.replaceAll(',', '.'));
    if (v == null || v <= 0) return null;
    return v;
  }

  void _confirmSelection() {
    final selected = _selected;
    if (selected == null) return;
    Navigator.pop(
      context,
      WorkshopSelectResult(
        taller: selected,
        presupuestoAceptado: _parsePresupuesto(),
      ),
    );
  }

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    _markerManager = await mapboxMap.annotations.createCircleAnnotationManager();
    _routeManager = await mapboxMap.annotations.createPolylineAnnotationManager();
    _markerTapCancelable = _markerManager?.tapEvents(onTap: (annotation) {
      final workshop = _markerByAnnotationId[annotation.id];
      if (workshop != null) {
        _selectTaller(workshop);
      }
    });
    await _syncMap();
  }

  Future<void> _syncMap() async {
    final mapboxMap = _mapboxMap;
    final markerManager = _markerManager;
    final routeManager = _routeManager;
    if (mapboxMap == null || markerManager == null || routeManager == null) return;

    _markerByAnnotationId.clear();
    await markerManager.deleteAll();
    await routeManager.deleteAll();

    final markerOptions = <CircleAnnotationOptions>[
      CircleAnnotationOptions(
        geometry: Point(
          coordinates: Position(widget.incidentPoint.longitude, widget.incidentPoint.latitude),
        ),
        circleColor: const Color(0xFFEF4444).toARGB32(),
        circleRadius: 8,
        circleStrokeColor: Colors.white.toARGB32(),
        circleStrokeWidth: 3,
      ),
      ..._talleres.map(
        (taller) => CircleAnnotationOptions(
          geometry: Point(
            coordinates: Position(taller.longitud, taller.latitud),
          ),
          circleColor: (_selected?.id == taller.id ? const Color(0xFF22C55E) : const Color(0xFF2563EB)).toARGB32(),
          circleRadius: _selected?.id == taller.id ? 8.5 : 7.5,
          circleStrokeColor: Colors.white.toARGB32(),
          circleStrokeWidth: 2.5,
        ),
      ),
    ];
    final created = await markerManager.createMulti(markerOptions);
    for (var i = 1; i < created.length && (i - 1) < _talleres.length; i++) {
      final annotation = created[i];
      if (annotation == null) continue;
      _markerByAnnotationId[annotation.id] = _talleres[i - 1];
    }

    if (_ruta != null) {
      await routeManager.create(
        PolylineAnnotationOptions(
          geometry: LineString(
            coordinates: _ruta!.path
                .map((point) => Position(point.longitude, point.latitude))
                .toList(growable: false),
          ),
          lineColor: const Color(0xFF2563EB).toARGB32(),
          lineWidth: 5,
        ),
      );
    }

    final center = _selected != null
        ? LatLng(_selected!.latitud, _selected!.longitud)
        : widget.incidentPoint;
    await mapboxMap.setCamera(
      CameraOptions(
        center: Point(coordinates: Position(center.longitude, center.latitude)),
        zoom: _selected != null ? 12.5 : 13,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seleccionar taller'),
        actions: [
          IconButton(
            onPressed: _loading ? null : () => _bootstrap(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _bootstrap)
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Talleres disponibles en Santa Cruz',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Solo se muestran talleres compatibles con la avería reportada y cercanos a tu ubicación.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: 120,
                            child: TextFormField(
                              initialValue: _radioKm.toStringAsFixed(0),
                              decoration: const InputDecoration(
                                labelText: 'Radio km',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              onFieldSubmitted: (v) async {
                                final parsed = double.tryParse(v.replaceAll(',', '.'));
                                if (parsed == null || parsed <= 0) return;
                                setState(() => _radioKm = parsed);
                                await _loadTalleres();
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: !AppConfig.hasMapboxAccessToken
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'Mapbox no está configurado en móvil. Define ACCESS_TOKEN para seleccionar un taller en el mapa.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : MapWidget(
                              key: const ValueKey('mapbox-workshop-selector'),
                              styleUri: AppConfig.mapboxStyleUri,
                              viewport: CameraViewportState(
                                center: Point(
                                  coordinates: Position(widget.incidentPoint.longitude, widget.incidentPoint.latitude),
                                ),
                                zoom: 13,
                              ),
                              onMapCreated: _onMapCreated,
                              textureView: true,
                            ),
                      ),
                    SizedBox(
                      height: 220,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        children: [
                          ..._talleres.map(
                            (taller) => Card(
                              margin: const EdgeInsets.only(top: 10),
                              color: _selected?.id == taller.id
                                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                                  : null,
                              child: ListTile(
                                onTap: () => _selectTaller(taller),
                                leading: Icon(
                                  Icons.home_repair_service,
                                  color: _selected?.id == taller.id ? const Color(0xFF22C55E) : const Color(0xFF2563EB),
                                ),
                                title: Text(taller.nombre),
                                subtitle: Text(
                                  '${taller.direccion}\nPresupuesto: ${_money(_effectiveMin(taller))} - ${_money(_effectiveMax(taller))}',
                                ),
                                isThreeLine: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      child: Column(
                        children: [
                          if (_rutaLoading) const LinearProgressIndicator(minHeight: 3),
                          if (_rutaError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                _rutaError!,
                                style: const TextStyle(color: Color(0xFFEF4444)),
                              ),
                            ),
                          if (_ruta != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Traslado: ${_ruta!.distanceKm.toStringAsFixed(2)} km'),
                                  Text('ETA al cliente: ${_ruta!.durationMin} min'),
                                ],
                              ),
                            ),
                          if (_selected != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: _WorkshopCard(
                                taller: _selected!,
                                route: _ruta,
                                presupuestoController: _presupuestoController,
                                onConfirm: _confirmSelection,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  double? _effectiveMin(TallerMapa taller) {
    final hasDiscount = (taller.descuentoPorcentajeAplicado ?? 0) > 0 &&
        taller.presupuestoDescuentoMin != null &&
        taller.presupuestoDescuentoMax != null;
    return hasDiscount ? taller.presupuestoDescuentoMin : taller.presupuestoMin;
  }

  double? _effectiveMax(TallerMapa taller) {
    final hasDiscount = (taller.descuentoPorcentajeAplicado ?? 0) > 0 &&
        taller.presupuestoDescuentoMin != null &&
        taller.presupuestoDescuentoMax != null;
    return hasDiscount ? taller.presupuestoDescuentoMax : taller.presupuestoMax;
  }

  String _money(double? value) {
    if (value == null) return '--';
    return 'Bs ${value.toStringAsFixed(0)}';
  }
}


class _WorkshopCard extends StatelessWidget {
  const _WorkshopCard({
    required this.taller,
    required this.route,
    required this.presupuestoController,
    required this.onConfirm,
  });

  final TallerMapa taller;
  final MapboxRouteResult? route;
  final TextEditingController presupuestoController;
  final VoidCallback onConfirm;

  String _money(double? v) {
    if (v == null) return '--';
    return 'Bs ${v.toStringAsFixed(0)}';
  }

  String _presupuestoLabel() {
    final hasDiscount = (taller.descuentoPorcentajeAplicado ?? 0) > 0 &&
        taller.presupuestoDescuentoMin != null &&
        taller.presupuestoDescuentoMax != null;
    final minV = hasDiscount ? taller.presupuestoDescuentoMin : taller.presupuestoMin;
    final maxV = hasDiscount ? taller.presupuestoDescuentoMax : taller.presupuestoMax;
    final suffix = hasDiscount ? ' (-${(taller.descuentoPorcentajeAplicado ?? 0).toStringAsFixed(0)}%)' : '';
    return '${_money(minV)} – ${_money(maxV)}$suffix';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    taller.nombre,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                if (taller.categoria != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2FE),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      taller.categoria!.nombre,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF0369A1)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(taller.direccion),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Presupuesto: ${_presupuestoLabel()}'),
                Text('Reparación: ${taller.tiempoReparacionHoras?.toStringAsFixed(1) ?? '--'} h'),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Traslado: ${route?.durationMin ?? '--'} min'),
                Text('Dist: ${route?.distanceKm.toStringAsFixed(2) ?? taller.distanciaKm?.toStringAsFixed(2) ?? '--'} km'),
              ],
            ),
            const SizedBox(height: 6),
            Text('Rating: ${(taller.ratingPromedio ?? 0).toStringAsFixed(1)} (${taller.ratingTotal ?? 0})'),
            const SizedBox(height: 10),
            TextFormField(
              controller: presupuestoController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Presupuesto aceptado (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onConfirm,
                child: const Text('Seleccionar este taller'),
              ),
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
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFEF4444)),
            ),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}
