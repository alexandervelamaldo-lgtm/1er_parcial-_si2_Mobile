import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/emergency_provider.dart';
import '../providers/session_provider.dart';


class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EmergencyProvider>();
    final token = context.watch<SessionProvider>().token;

    return Scaffold(
      appBar: AppBar(title: const Text('Notificaciones')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: provider.notificaciones.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = provider.notificaciones[index];
          return Card(
            child: ListTile(
              title: Text(item.titulo),
              subtitle: Text(item.mensaje),
              trailing: item.leida
                  ? const Icon(Icons.done_all, color: Colors.green)
                  : IconButton(
                      onPressed: token == null
                          ? null
                          : () => provider.marcarNotificacionLeida(token, item.id),
                      icon: const Icon(Icons.mark_email_read_outlined),
                    ),
            ),
          );
        },
      ),
    );
  }
}
