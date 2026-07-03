import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../models/tecnico_cercano.dart';
import '../providers/emergency_provider.dart';
import '../providers/session_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_state_widgets.dart';


class NearbyTechniciansScreen extends StatefulWidget {
  const NearbyTechniciansScreen({super.key});

  @override
  State<NearbyTechniciansScreen> createState() => _NearbyTechniciansScreenState();
}


class _NearbyTechniciansScreenState extends State<NearbyTechniciansScreen> {
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadNearby();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EmergencyProvider>();
    final talleres = provider.tecnicosCercanos;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Talleres cercanos', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location_outlined),
            tooltip: 'Actualizar ubicación',
            onPressed: _loading ? null : _loadNearby,
          ),
        ],
      ),
      body: _buildBody(talleres),
    );
  }

  Widget _buildBody(List<TecnicoCercano> talleres) {
    if (_loading) {
      return const AppLoadingIndicator(message: 'Buscando talleres cercanos…');
    }
    if (_error != null) {
      return AppErrorBanner(
        message: _error!,
        onRetry: _loadNearby,
      );
    }
    if (talleres.isEmpty) {
      return AppEmptyState(
        icon: Icons.store_outlined,
        title: 'Sin talleres en tu zona',
        subtitle: 'No se encontraron talleres disponibles cerca de tu ubicación actual.',
        action: _loadNearby,
        actionLabel: 'Buscar de nuevo',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadNearby,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: talleres.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) => _TallerCard(taller: talleres[index]),
      ),
    );
  }

  Future<void> _loadNearby() async {
    final token = context.read<SessionProvider>().token;
    final provider = context.read<EmergencyProvider>();
    if (token == null) {
      setState(() => _error = 'Sesión no válida.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('El GPS está desactivado. Actívalo para ver talleres cercanos.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Permiso de ubicación denegado.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      await provider.cargarTecnicosCercanos(
        token,
        latitud: position.latitude,
        longitud: position.longitude,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}


class _TallerCard extends StatelessWidget {
  const _TallerCard({required this.taller});
  final TecnicoCercano taller;

  @override
  Widget build(BuildContext context) {
    final distColor = taller.distanciaKm <= 2
        ? AppColors.success
        : taller.distanciaKm <= 5
            ? AppColors.warning
            : AppColors.error;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.build_circle_outlined, color: AppColors.primary, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    taller.nombre,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.settings_outlined, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          taller.especialidad,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${taller.distanciaKm.toStringAsFixed(1)} km',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: distColor,
                  ),
                ),
                const SizedBox(height: 2),
                Icon(Icons.location_on_outlined, size: 14, color: distColor),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
