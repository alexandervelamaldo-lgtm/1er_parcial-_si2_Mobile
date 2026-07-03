import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/solicitud.dart';
import '../providers/emergency_provider.dart';
import '../providers/session_provider.dart';
import '../services/sync_service.dart';
import 'chat_screen.dart';
import 'history_screen.dart';
import 'kpi_dashboard_screen.dart';
import 'voice_report_screen.dart';
import 'nearby_technicians_screen.dart';
import 'notifications_screen.dart';
import 'pending_sync_screen.dart';
import 'profile_screen.dart';
import 'request_screen.dart';
import 'solicitud_detalle_screen.dart';
import 'vehicles_screen.dart';
import '../services/mapbox_service.dart';
import '../widgets/mapbox_map_picker.dart';

final MapboxService _sharedMapboxService = MapboxService();

/// Construye la lista de rutas activas (incidente → taller) para el mapa
/// del dashboard. Combina los seguimientos recién cargados del provider con
/// las solicitudes para obtener coordenadas válidas.
List<MapboxMapRoute> _buildActiveRoutes(EmergencyProvider provider) {
  final routes = <MapboxMapRoute>[];
  for (final seg in provider.seguimientosActivos.values) {
    // Necesitamos incidente y taller para dibujar la línea.
    final latI = seg.latitudServicio;
    final lonI = seg.longitudServicio;
    final latT = seg.latitudTaller;
    final lonT = seg.longitudTaller;
    if (latI == null || lonI == null || latT == null || lonT == null) continue;

    final tenantKey = provider.solicitudes
        .cast<Solicitud?>()
        .firstWhere(
          (s) => s?.id == seg.solicitudId,
          orElse: () => null,
        )
        ?.tenantKey;
    routes.add(
      MapboxMapRoute(
        solicitudId: seg.solicitudId,
        tenantKey: tenantKey,
        incident: LatLng(latI, lonI),
        workshop: LatLng(latT, lonT),
        color: _parseRouteColor(seg.routeColor),
        fallbackEtaMin: seg.etaMin,
        label: seg.tallerNombre != null && seg.tallerNombre!.isNotEmpty ? seg.tallerNombre : '#${seg.solicitudId}',
      ),
    );
  }
  return routes;
}

List<MapboxMapMarker> _buildReferenceMarkers(EmergencyProvider provider) {
  final duplicateCounters = <String, int>{};
  return provider.solicitudes
      .where((s) => s.latitudIncidente != null && s.longitudIncidente != null)
      .take(20)
      .map((s) {
        final lat = s.latitudIncidente!;
        final lon = s.longitudIncidente!;
        final key = '${lat.toStringAsFixed(5)},${lon.toStringAsFixed(5)}';
        final overlapIndex = duplicateCounters.update(key, (value) => value + 1, ifAbsent: () => 0);
        final adjustedPoint = overlapIndex == 0
            ? LatLng(lat, lon)
            : _offsetPoint(lat: lat, lon: lon, overlapIndex: overlapIndex);
        return MapboxMapMarker(
          id: s.id,
          tenantKey: s.tenantKey,
          point: adjustedPoint,
          label: '${s.tipoIncidente} (#${s.id})',
          color: _colorForEstado(s.estado),
          type: MapboxMarkerType.incident,
        );
      })
      .toList(growable: false);
}

LatLng _offsetPoint({
  required double lat,
  required double lon,
  required int overlapIndex,
}) {
  final ring = ((overlapIndex - 1) ~/ 8) + 1;
  final angleStep = (overlapIndex - 1) % 8;
  final angle = angleStep * (math.pi / 4);
  final meters = 16.0 + ((ring - 1) * 10.0);
  final latOffset = (meters / 111320.0) * math.sin(angle);
  final lonScale = math.max(math.cos(lat * math.pi / 180).abs(), 0.2);
  final lonOffset = (meters / (111320.0 * lonScale)) * math.cos(angle);
  return LatLng(lat + latOffset, lon + lonOffset);
}

/// Parses a `#RRGGBB` (or `RRGGBB`) hex color from the backend's
/// `route_color` field, with an orange fallback.
Color _parseRouteColor(String? hex) {
  final raw = (hex ?? '').trim();
  if (!RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(raw)) {
    return const Color(0xFFF97316); // default orange
  }
  final h = raw.startsWith('#') ? raw.substring(1) : raw;
  return Color(int.parse('FF$h', radix: 16));
}

/// Devuelve el color del pin según el estado de la solicitud.
Color _colorForEstado(String estado) {
  final s = estado.toLowerCase();
  if (s.contains('complet') || s.contains('cerrad') || s.contains('finaliz')) {
    return const Color(0xFF16A34A); // verde – completado
  }
  if (s.contains('proceso') || s.contains('asignado') || s.contains('camino')) {
    return const Color(0xFFF97316); // naranja – en curso
  }
  if (s.contains('cancel')) {
    return const Color(0xFF6B7280); // gris – cancelado
  }
  return const Color(0xFFEF4444); // rojo – pendiente / default
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}


class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final token = context.read<SessionProvider>().token;
    if (token != null) {
      context.read<EmergencyProvider>().cargarDatos(token);
    }
  }

  @override
  Widget build(BuildContext context) {
    final views = [
      const _DashboardTab(),
      const VehiclesScreen(),
      const HistoryScreen(),
      const NotificationsScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      body: views[_currentIndex],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RequestScreen()),
          );
        },
        label: const Text('Solicitar ayuda'),
        icon: const Icon(Icons.car_crash),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Inicio'),
          NavigationDestination(icon: Icon(Icons.directions_car_outlined), label: 'Vehículos'),
          NavigationDestination(icon: Icon(Icons.history), label: 'Historial'),
          NavigationDestination(icon: Icon(Icons.notifications_none), label: 'Alertas'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Perfil'),
        ],
      ),
    );
  }
}


class _DashboardTab extends StatelessWidget {
  const _DashboardTab();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EmergencyProvider>();
    final theme = Theme.of(context);
    final profile = context.watch<SessionProvider>().profile;
    final sync = context.watch<SyncService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel del cliente'),
        actions: [
          IconButton(
            onPressed: () => context.read<SessionProvider>().logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          final token = context.read<SessionProvider>().token;
          if (token != null) {
            await context.read<EmergencyProvider>().cargarDatos(token);
          }
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Offline banner ───────────────────────────────────────────
            if (!sync.isOnline)
              InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PendingSyncScreen()),
                ),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.wifi_off_rounded, color: Colors.orange.shade700, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Sin conexión — tus emergencias se guardarán localmente y se enviarán al recuperar internet.',
                          style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                        ),
                      ),
                      Icon(Icons.chevron_right, color: Colors.orange.shade700, size: 20),
                    ],
                  ),
                ),
              ),
            // ── Pending-sync badge (visible online when queue has items) ──
            if (sync.isOnline && sync.pendingCount > 0)
              InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PendingSyncScreen()),
                ),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      sync.isSyncing
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(Icons.sync_rounded, color: Colors.blue.shade700, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          sync.isSyncing
                              ? 'Sincronizando ${sync.pendingCount} operacion(es) con el servidor…'
                              : '${sync.pendingCount} operación(es) pendientes de enviar al servidor.',
                          style: TextStyle(fontSize: 12, color: Colors.blue.shade900, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Icon(Icons.chevron_right, color: Colors.blue.shade700, size: 20),
                    ],
                  ),
                ),
              ),
            Card(
              child: ListTile(
                title: const Text('Resumen'),
                subtitle: Text(
                  'Cliente: ${profile?.email ?? 'Sin perfil'}\n'
                  'Solicitudes registradas: ${provider.solicitudes.length}\n'
                  'Vehículos: ${provider.vehiculos.length}',
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (provider.error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  provider.error!,
                  style: TextStyle(fontSize: 12, color: Colors.red.shade900),
                ),
              ),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const NearbyTechniciansScreen()),
                    );
                  },
                  icon: const Icon(Icons.support_agent),
                  label: const Text('Talleres cercanos'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                    );
                  },
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('Ver alertas'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const KpiDashboardScreen()),
                    );
                  },
                  icon: const Icon(Icons.bar_chart_rounded),
                  label: const Text('KPI Dashboard'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const VoiceReportScreen()),
                    );
                  },
                  icon: const Icon(Icons.mic_rounded),
                  label: const Text('Reporte por voz'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ChatScreen()),
                    );
                  },
                  icon: const Icon(Icons.smart_toy_outlined),
                  label: const Text('Asistente virtual'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Mapa de referencia', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            SizedBox(
              height: (() {
                final h = MediaQuery.of(context).size.height;
                final v = h * 0.28;
                if (v < 220) return 220.0;
                if (v > 340) return 340.0;
                return v;
              })(),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: MapboxMapPicker(
                  mapbox: _sharedMapboxService,
                  initialCenter: const LatLng(-17.7863, -63.1812),
                  initialZoom: 13,
                  markers: _buildReferenceMarkers(provider),
                  showAddressCard: false,
                  // Rutas activas: incidente → taller asignado, con ETA real
                  activeRoutes: _buildActiveRoutes(provider),
                  onMarkerTap: (m) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => SolicitudDetalleScreen(solicitudId: m.id, tenantKey: m.tenantKey)),
                    );
                  },
                  onRouteTap: (r) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SolicitudDetalleScreen(solicitudId: r.solicitudId, tenantKey: r.tenantKey),
                      ),
                    );
                  },
                  // No onConfirm: this is a view-only dashboard map, not a picker.
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Últimas solicitudes', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            ...provider.solicitudes.take(5).map(
                  (solicitud) => Card(
                    child: ListTile(
                      title: Text(solicitud.tipoIncidente),
                      subtitle: Text(solicitud.descripcion),
                      trailing: Text(solicitud.estado),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SolicitudDetalleScreen(solicitudId: solicitud.id, tenantKey: solicitud.tenantKey),
                          ),
                        );
                      },
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
