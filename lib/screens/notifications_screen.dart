import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/emergency_provider.dart';
import '../providers/session_provider.dart';
import '../theme/app_theme.dart';


class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EmergencyProvider>();
    final token = context.watch<SessionProvider>().token;
    final items = provider.notificaciones;
    final unreadCount = items.where((n) => !n.leida).length;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Notificaciones', style: TextStyle(fontWeight: FontWeight.bold)),
            if (unreadCount > 0)
              Text(
                '$unreadCount sin leer',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.warning,
                    ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'Actualizar',
            onPressed: () {
              if (token != null) context.read<EmergencyProvider>().cargarDatos(token);
            },
          ),
        ],
      ),
      body: provider.loading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? _EmptyNotifications()
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Card(
                      color: item.leida
                          ? null
                          : Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.2),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: item.leida
                                ? Theme.of(context).colorScheme.surfaceContainerHighest
                                : AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            _iconForType(item.tipo),
                            color: item.leida ? Colors.grey : AppColors.primary,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          item.titulo,
                          style: TextStyle(
                            fontWeight: item.leida ? FontWeight.normal : FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            item.mensaje,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        trailing: item.leida
                            ? const Icon(Icons.done_all, color: AppColors.success, size: 20)
                            : Semantics(
                                label: 'Marcar como leída',
                                child: IconButton(
                                  icon: const Icon(Icons.mark_email_read_outlined, size: 20),
                                  tooltip: 'Marcar como leída',
                                  onPressed: token == null
                                      ? null
                                      : () => provider.marcarNotificacionLeida(token, item.id),
                                ),
                              ),
                        isThreeLine: item.mensaje.length > 60,
                      ),
                    );
                  },
                ),
    );
  }

  IconData _iconForType(String tipo) {
    return switch (tipo) {
      'SOLICITUD_REGISTRADA' => Icons.assignment_outlined,
      'ASIGNACION_TALLER' || 'ASIGNACION_TECNICO' => Icons.engineering_outlined,
      'TECNICO_EN_CAMINO' => Icons.directions_car_outlined,
      'TRABAJO_FINALIZADO' => Icons.task_alt,
      'PAGO_REGISTRADO' || 'PAGO_CONFIRMADO' => Icons.receipt_outlined,
      'DISPUTA_ABIERTA' || 'DISPUTA_RESUELTA' => Icons.gavel_outlined,
      'SOLICITUD_CANCELADA' => Icons.cancel_outlined,
      'ESCALAMIENTO_CRITICO' => Icons.warning_amber_outlined,
      _ => Icons.notifications_outlined,
    };
  }
}


class _EmptyNotifications extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.notifications_none_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'Sin notificaciones',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Aquí aparecerán las alertas sobre tus solicitudes.',
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
