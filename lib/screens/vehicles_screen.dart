import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/emergency_provider.dart';


class VehiclesScreen extends StatelessWidget {
  const VehiclesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EmergencyProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Mis vehículos')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: provider.vehiculos.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final vehiculo = provider.vehiculos[index];
          return Card(
            child: ListTile(
              title: Text('${vehiculo.marca} ${vehiculo.modelo}'),
              subtitle: Text('${vehiculo.placa} · ${vehiculo.color} · ${vehiculo.tipoCombustible}'),
              trailing: Text('${vehiculo.anio}'),
            ),
          );
        },
      ),
    );
  }
}
