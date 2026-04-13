import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../providers/emergency_provider.dart';
import '../providers/session_provider.dart';


class NearbyTechniciansScreen extends StatefulWidget {
  const NearbyTechniciansScreen({super.key});

  @override
  State<NearbyTechniciansScreen> createState() => _NearbyTechniciansScreenState();
}


class _NearbyTechniciansScreenState extends State<NearbyTechniciansScreen> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadNearby();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EmergencyProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Técnicos cercanos')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: provider.tecnicosCercanos.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final tecnico = provider.tecnicosCercanos[index];
                return Card(
                  child: ListTile(
                    title: Text(tecnico.nombre),
                    subtitle: Text(tecnico.especialidad),
                    trailing: Text('${tecnico.distanciaKm.toStringAsFixed(1)} km'),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _loadNearby() async {
    final token = context.read<SessionProvider>().token;
    final emergencyProvider = context.read<EmergencyProvider>();
    if (token == null) {
      return;
    }
    setState(() => _loading = true);
    try {
      final position = await Geolocator.getCurrentPosition();
      await emergencyProvider.cargarTecnicosCercanos(
            token,
            latitud: position.latitude,
            longitud: position.longitude,
          );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }
}
