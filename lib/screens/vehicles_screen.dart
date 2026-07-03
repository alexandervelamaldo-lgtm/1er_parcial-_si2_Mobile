import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/emergency_provider.dart';
import '../providers/session_provider.dart';
import '../theme/app_theme.dart';


class VehiclesScreen extends StatelessWidget {
  const VehiclesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EmergencyProvider>();
    final vehicles = provider.vehiculos;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis vehículos', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'Actualizar',
            onPressed: () {
              final token = context.read<SessionProvider>().token;
              if (token != null) context.read<EmergencyProvider>().cargarDatos(token);
            },
          ),
        ],
      ),
      body: provider.loading
          ? const Center(child: CircularProgressIndicator())
          : vehicles.isEmpty
              ? _EmptyVehicles()
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: vehicles.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final v = vehicles[index];
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.directions_car, color: AppColors.primary),
                        ),
                        title: Text(
                          '${v.marca} ${v.modelo}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Wrap(
                            spacing: 6,
                            children: [
                              _Tag(label: v.placa),
                              _Tag(label: v.color),
                              _Tag(label: v.tipoCombustible),
                            ],
                          ),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${v.anio}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}


class _EmptyVehicles extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.directions_car_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'No tienes vehículos registrados',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Contacta con soporte o accede a la plataforma web para registrar un vehículo.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}


class _Tag extends StatelessWidget {
  const _Tag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
