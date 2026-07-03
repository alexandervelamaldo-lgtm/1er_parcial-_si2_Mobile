import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/notification_preferences.dart';
import '../providers/session_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/voice_report_button.dart';
import '../widgets/txt_file_tools_card.dart';


class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  NotificationPreferences? _prefs;
  bool _loadingPrefs = false;

  static const _notificationTypes = <({String key, String label})>[
    (key: 'SOLICITUD_REGISTRADA', label: 'Solicitud registrada'),
    (key: 'ESCALAMIENTO_CRITICO', label: 'Escalamiento crítico'),
    (key: 'REVISION_MANUAL', label: 'Revisión manual requerida'),
    (key: 'REVISION_MANUAL_COMPLETADA', label: 'Revisión manual completada'),
    (key: 'ASIGNACION_TALLER', label: 'Asignación generada'),
    (key: 'SIN_TECNICO_DISPONIBLE', label: 'Sin taller disponible'),
    (key: 'ASIGNACION_APROBADA_CLIENTE', label: 'Cliente aprobó propuesta'),
    (key: 'ASIGNACION_RECHAZADA_CLIENTE', label: 'Cliente rechazó propuesta'),
    (key: 'RESPUESTA_PROPUESTA_CLIENTE', label: 'Respuesta a propuesta'),
    (key: 'ASIGNACION_TECNICO', label: 'Asignación a taller'),
    (key: 'ASIGNACION_RECHAZADA', label: 'Asignación rechazada'),
    (key: 'RECHAZO_TALLER', label: 'Rechazo del taller'),
    (key: 'TECNICO_EN_CAMINO', label: 'Taller en camino'),
    (key: 'CAMBIO_ESTADO', label: 'Cambio de estado'),
    (key: 'SOLICITUD_CANCELADA', label: 'Solicitud cancelada'),
    (key: 'AUDIO_TRANSCRITO', label: 'Audio transcrito'),
    (key: 'TRABAJO_FINALIZADO', label: 'Trabajo finalizado'),
    (key: 'PAGO_REGISTRADO', label: 'Pago registrado'),
    (key: 'PAGO_CONFIRMADO', label: 'Pago confirmado'),
    (key: 'DISPUTA_ABIERTA', label: 'Disputa abierta'),
    (key: 'DISPUTA_RESUELTA', label: 'Disputa resuelta'),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final token = context.read<SessionProvider>().token;
    if (token != null && !_loadingPrefs && _prefs == null) {
      _loadPrefs(token);
    }
  }

  Future<void> _loadPrefs(String token) async {
    setState(() => _loadingPrefs = true);
    try {
      final api = context.read<ApiService>();
      final prefs = await api.obtenerPreferenciasNotificaciones(token);
      if (!mounted) return;
      setState(() => _prefs = prefs);
    } catch (_) {
      if (!mounted) return;
      setState(() => _prefs = NotificationPreferences(disabledAll: false, disabledTypes: {}));
    } finally {
      if (mounted) {
        setState(() => _loadingPrefs = false);
      }
    }
  }

  Future<void> _updatePrefs({
    required String token,
    bool? disabledAll,
    Map<String, bool>? disabledTypes,
  }) async {
    final api = context.read<ApiService>();
    final next = await api.actualizarPreferenciasNotificaciones(
      token,
      disabledAll: disabledAll,
      disabledTypes: disabledTypes,
    );
    if (!mounted) return;
    setState(() => _prefs = next);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final profile = session.profile;
    final token = session.token;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi perfil', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            tooltip: 'Cerrar sesión',
            onPressed: () => _confirmLogout(context, session),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Avatar + info
          _ProfileHeader(
            email: profile?.email ?? 'Sin correo',
            roles: profile?.roles ?? [],
            clienteId: profile?.clienteId,
          ),
          const SizedBox(height: 16),
          const VoiceReportButton(),
          const SizedBox(height: 12),
          const TxtFileToolsCard(),
          const SizedBox(height: 16),
          const _SectionHeader(label: 'Notificaciones push'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          session.pushEnabled
                              ? 'Activadas (${session.pushPermissionState})'
                              : 'Desactivadas (${session.pushPermissionState})',
                        ),
                      ),
                      FilledButton.tonal(
                        onPressed: token == null || session.pushEnabled
                            ? null
                            : () async {
                                final accepted = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Activar notificaciones'),
                                    content: const Text(
                                      'Habilitar notificaciones te permite recibir alertas importantes sobre tus solicitudes, incluso con la app cerrada.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context, false),
                                        child: const Text('Ahora no'),
                                      ),
                                      FilledButton(
                                        onPressed: () => Navigator.pop(context, true),
                                        child: const Text('Continuar'),
                                      ),
                                    ],
                                  ),
                                );
                                if (accepted != true) return;
                                await session.enablePush();
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      session.pushEnabled
                                          ? 'Notificaciones activadas.'
                                          : 'No se pudieron activar las notificaciones (permiso denegado).',
                                    ),
                                  ),
                                );
                              },
                        child: const Text('Activar'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.tonal(
                        onPressed: token == null || !session.pushEnabled
                            ? null
                            : () async {
                                final accepted = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Desactivar notificaciones'),
                                    content: const Text(
                                      'Se dará de baja este dispositivo para no recibir más alertas. Puedes reactivarlas cuando quieras.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context, false),
                                        child: const Text('Cancelar'),
                                      ),
                                      FilledButton(
                                        onPressed: () => Navigator.pop(context, true),
                                        child: const Text('Desactivar'),
                                      ),
                                    ],
                                  ),
                                );
                                if (accepted != true) return;
                                await session.disablePush();
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Notificaciones desactivadas.')),
                                );
                              },
                        child: const Text('Desactivar'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Puedes controlar qué tipo de alertas recibir. Si desactivas todo, no se enviarán push a tu usuario.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _SectionHeader(label: 'Preferencias de notificación'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  if (token == null)
                    const Text('Inicia sesión para configurar las preferencias.')
                  else if (_loadingPrefs)
                    const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
                  else if (_prefs == null)
                    FilledButton.tonal(
                      onPressed: () => _loadPrefs(token),
                      child: const Text('Cargar preferencias'),
                    )
                  else ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Desactivar todas'),
                      value: _prefs!.disabledAll,
                      onChanged: (value) async {
                        final current = _prefs!;
                        setState(() => _prefs = current.copyWith(disabledAll: value));
                        try {
                          await _updatePrefs(token: token, disabledAll: value);
                        } catch (_) {
                          if (mounted) setState(() => _prefs = current);
                        }
                      },
                    ),
                    const Divider(height: 1),
                    ..._notificationTypes.map((item) {
                      final current = _prefs!;
                      final disabled = current.disabledTypes[item.key] == true;
                      return SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(item.label),
                        value: !disabled,
                        onChanged: current.disabledAll
                            ? null
                            : (value) async {
                                final base = _prefs!;
                                final nextDisabledTypes = {...base.disabledTypes, item.key: !value};
                                setState(() => _prefs = base.copyWith(disabledTypes: nextDisabledTypes));
                                try {
                                  await _updatePrefs(token: token, disabledTypes: nextDisabledTypes);
                                } catch (_) {
                                  if (mounted) setState(() => _prefs = base);
                                }
                              },
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, SessionProvider session) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Seguro que quieres cerrar sesión?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salir')),
        ],
      ),
    );
    if (ok == true) await session.logout();
  }
}


class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.email,
    required this.roles,
    this.clienteId,
  });

  final String email;
  final List<String> roles;
  final int? clienteId;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.person, size: 34, color: AppColors.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    email,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  if (roles.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      children: roles
                          .map(
                            (r) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                r,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  if (clienteId != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Cliente #$clienteId',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
      ),
    );
  }
}
