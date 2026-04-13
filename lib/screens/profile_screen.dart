import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/session_provider.dart';


class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<SessionProvider>().profile;

    return Scaffold(
      appBar: AppBar(title: const Text('Mi perfil')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              title: Text(profile?.email ?? 'Sin correo'),
              subtitle: Text(profile?.roles.join(', ') ?? 'Sin roles'),
            ),
          ),
          if (profile?.clienteId != null)
            Card(
              child: ListTile(
                title: const Text('ID de cliente'),
                subtitle: Text('${profile!.clienteId}'),
              ),
            ),
        ],
      ),
    );
  }
}
