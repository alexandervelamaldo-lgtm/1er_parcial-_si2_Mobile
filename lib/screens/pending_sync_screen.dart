/// "Pendientes de sincronización" screen.
///
/// Lists every operation currently sitting in the local offline queue
/// (PENDING / SYNCING / FAILED / SYNCED), with controls to manually
/// trigger a flush or discard individual rows. The user always knows
/// whether their offline-registered emergencies actually made it to the
/// backend.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/offline_queue_service.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';

class PendingSyncScreen extends StatefulWidget {
  const PendingSyncScreen({super.key});

  @override
  State<PendingSyncScreen> createState() => _PendingSyncScreenState();
}

class _PendingSyncScreenState extends State<PendingSyncScreen> {
  List<QueuedOperation> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final queue = context.read<OfflineQueueService>();
    final all = await queue.getAll();
    if (!mounted) return;
    setState(() {
      _items = all;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Re-read when sync service or queue notify changes
    final sync = context.watch<SyncService>();
    context.watch<OfflineQueueService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pendientes de sincronización'),
        actions: [
          IconButton(
            tooltip: 'Refrescar',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Status banner ────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: sync.isOnline
                ? AppColors.success.withValues(alpha: 0.10)
                : AppColors.warning.withValues(alpha: 0.10),
            child: Row(
              children: [
                Icon(
                  sync.isOnline ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                  color: sync.isOnline ? AppColors.success : AppColors.warning,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    sync.isOnline
                        ? sync.isSyncing
                            ? 'Sincronizando con el backend…'
                            : 'Conectado a internet. ${sync.pendingCount} en cola.'
                        : 'Sin conexión. Las emergencias quedarán guardadas localmente.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (sync.isOnline && sync.pendingCount > 0 && !sync.isSyncing)
                  TextButton.icon(
                    onPressed: () async {
                      await context.read<SyncService>().flushQueue();
                      await _load();
                    },
                    icon: const Icon(Icons.sync, size: 18),
                    label: const Text('Sincronizar ahora'),
                  ),
              ],
            ),
          ),
          if (sync.lastSyncError != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppColors.error.withValues(alpha: 0.10),
              child: Text(
                'Último error de sync: ${sync.lastSyncError}',
                style: const TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ),

          // ── List ────────────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? const _EmptyState()
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _OperationCard(
                            op: _items[i],
                            onDiscard: () => _confirmDiscard(_items[i]),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDiscard(QueuedOperation op) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('¿Descartar operación?'),
        content: Text(
          op.status == 'SYNCED'
              ? 'Esta operación ya fue sincronizada (#${op.serverId ?? '?'}). '
                  'Quitarla solo limpia el historial local.'
              : '⚠️ Esta operación aún NO ha sido enviada al servidor. '
                  'Si la descartas, los datos se perderán.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<OfflineQueueService>().discard(op.idempotencyKey);
    await _load();
  }
}

// ── Aux widgets ────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_done_outlined, size: 64, color: AppColors.primary.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text(
              'Todo sincronizado',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'No hay operaciones offline pendientes ni recientes.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _OperationCard extends StatelessWidget {
  const _OperationCard({required this.op, required this.onDiscard});

  final QueuedOperation op;
  final VoidCallback onDiscard;

  ({Color color, IconData icon, String label}) _statusVisuals() {
    switch (op.status) {
      case 'SYNCED':
        return (color: AppColors.success, icon: Icons.check_circle_outline, label: 'Sincronizada');
      case 'SYNCING':
        return (color: AppColors.primary, icon: Icons.sync, label: 'Enviando…');
      case 'FAILED':
        return (color: AppColors.error, icon: Icons.error_outline, label: 'Falló (reintenta auto)');
      default:
        return (color: AppColors.warning, icon: Icons.schedule, label: 'Pendiente');
    }
  }

  String _humanTipo() => switch (op.tipo) {
        'crear_solicitud'   => 'Nueva emergencia',
        'actualizar_estado' => 'Cambio de estado',
        'cancelar_solicitud'=> 'Cancelación',
        _                   => op.tipo,
      };

  String _shortDesc() {
    final desc = op.payload['descripcion']?.toString().trim() ?? '';
    if (desc.isNotEmpty) return desc.length > 80 ? '${desc.substring(0, 77)}…' : desc;
    return 'Sin descripción';
  }

  @override
  Widget build(BuildContext context) {
    final v = _statusVisuals();
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(v.icon, color: v.color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _humanTipo(),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: v.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(v.label, style: TextStyle(color: v.color, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(_shortDesc(), style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  'Creada: ${_formatDate(op.createdAt)}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(width: 12),
                if (op.retryCount > 0)
                  Text(
                    '${op.retryCount} reintentos',
                    style: const TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w700),
                  ),
                const Spacer(),
                if (op.serverId != null)
                  Text(
                    '#${op.serverId}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.success),
                  ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  tooltip: 'Descartar',
                  onPressed: onDiscard,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            if (op.lastError != null && op.status != 'SYNCED') ...[
              const SizedBox(height: 4),
              Text(
                op.lastError!,
                style: const TextStyle(fontSize: 11, color: AppColors.error, fontStyle: FontStyle.italic),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    final local = d.toLocal();
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mn = local.minute.toString().padLeft(2, '0');
    return '$dd/$mm $hh:$mn';
  }
}
