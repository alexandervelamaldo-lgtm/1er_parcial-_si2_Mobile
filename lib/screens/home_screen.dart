import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../providers/emergency_provider.dart';
import '../providers/session_provider.dart';
import 'history_screen.dart';
import 'nearby_technicians_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'request_screen.dart';
import 'vehicles_screen.dart';


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
                  label: const Text('Técnicos cercanos'),
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
              ],
            ),
            const SizedBox(height: 16),
            Text('Mapa de referencia', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            SizedBox(
              height: 250,
              child: AppConfig.enableGoogleMaps
                  ? GoogleMap(
                      initialCameraPosition: const CameraPosition(
                        target: LatLng(19.4326, -99.1332),
                        zoom: 11,
                      ),
                      markers: {
                        const Marker(
                          markerId: MarkerId('centro'),
                          position: LatLng(19.4326, -99.1332),
                          infoWindow: InfoWindow(title: 'Zona de cobertura'),
                        ),
                      },
                    )
                  : Card(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.map_outlined,
                                size: 40,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Mapa deshabilitado en esta compilación',
                                style: theme.textTheme.titleMedium,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'La app sigue funcionando para solicitudes, historial, notificaciones y seguimiento.',
                                style: theme.textTheme.bodyMedium,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            Text('Últimas solicitudes', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            ...provider.solicitudes.take(3).map(
                  (solicitud) => Card(
                    child: ListTile(
                      title: Text(solicitud.tipoIncidente),
                      subtitle: Text(solicitud.descripcion),
                      trailing: Text(solicitud.estado),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
