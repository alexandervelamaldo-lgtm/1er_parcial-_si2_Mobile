/// Connectivity + offline-queue orchestrator.
///
/// Watches the device's network state and, every time the device comes back
/// online, flushes the offline queue managed by [OfflineQueueService] to the
/// backend's `/sync/lote` endpoint.
///
/// The service is intentionally agnostic of the UI — the screens just call
/// ``context.read<OfflineQueueService>().enqueue(...)`` when they need to
/// persist a user action; this service handles the rest.
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'api_service.dart';
import 'offline_queue_service.dart';

class SyncService extends ChangeNotifier {
  SyncService({
    required OfflineQueueService queue,
    required ApiService api,
    String? Function()? tokenProvider,
  })  : _queue = queue,
        _api = api,
        _getToken = tokenProvider ?? (() => null);

  // ── Dependencies ──────────────────────────────────────────────────────────
  final OfflineQueueService _queue;
  final ApiService _api;
  /// Lazy reader for the JWT token, injected by the host so we don't have to
  /// depend on [SessionProvider] directly (which would create an import cycle).
  String? Function() _getToken;

  // ── Public state ──────────────────────────────────────────────────────────
  bool _isOnline = true;
  bool _isSyncing = false;
  DateTime? _lastSyncAt;
  String? _lastSyncError;

  bool get isOnline       => _isOnline;
  bool get isSyncing      => _isSyncing;
  DateTime? get lastSyncAt => _lastSyncAt;
  String? get lastSyncError => _lastSyncError;
  int get pendingCount    => _queue.pendingCount;

  StreamSubscription<List<ConnectivityResult>>? _sub;
  static const _maxRetries = 5;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Start listening to connectivity. Safe to call multiple times — the
  /// previous subscription is cancelled first.
  Future<void> initialize() async {
    await _queue.initialize();
    _queue.addListener(_onQueueChanged);

    await _sub?.cancel();
    _sub = Connectivity()
        .onConnectivityChanged
        .listen(_onConnectivityChanged);

    final results = await Connectivity().checkConnectivity();
    _setOnline(_isConnected(results), suppressFlush: true);

    // Kick off an initial flush in case there are pending operations from a
    // previous session that crashed before they could be synced.
    if (_isOnline) {
      // Fire and forget — UI doesn't need to await the initial flush.
      unawaited(flushQueue());
    }
  }

  /// Update the token reader. Call this whenever the session changes so the
  /// service can authenticate the next sync attempt.
  void updateTokenProvider(String? Function() reader) {
    _getToken = reader;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _queue.removeListener(_onQueueChanged);
    super.dispose();
  }

  // ── Flush logic ───────────────────────────────────────────────────────────

  /// Send every PENDING/FAILED operation in a single request to `/sync/lote`.
  /// Updates each row's status based on the per-operation result returned by
  /// the backend.
  Future<void> flushQueue() async {
    if (_isSyncing || !_isOnline) return;
    final token = _getToken();
    if (token == null || token.isEmpty) return;

    final pending = await _queue.getPending(maxRetries: _maxRetries);
    if (pending.isEmpty) return;

    _isSyncing = true;
    _lastSyncError = null;
    notifyListeners();

    try {
      // Mark all as SYNCING so a concurrent flush won't double-send them.
      for (final op in pending) {
        await _queue.markSyncing(op.idempotencyKey);
      }

      final operations = pending
          .map((op) => <String, dynamic>{
                'tipo':                op.tipo,
                'idempotency_key':     op.idempotencyKey,
                'payload':             op.payload,
                'offline_created_at':  op.createdAt.toUtc().toIso8601String(),
              })
          .toList(growable: false);

      final response = await _api.sincronizarLote(token: token, operations: operations);

      final results = (response['results'] as List<dynamic>?) ?? [];
      for (final raw in results) {
        if (raw is! Map<String, dynamic>) continue;
        final key    = raw['idempotency_key'] as String?;
        final status = raw['status']          as String?;
        final data   = raw['data']            as Map<String, dynamic>?;
        final error  = raw['error']           as String?;
        if (key == null) continue;

        if (status == 'ok' || status == 'duplicate') {
          final serverId = data?['solicitud_id'] as int?;
          await _queue.markSynced(key, serverId: serverId);
        } else {
          await _queue.markFailed(key, error ?? 'Error desconocido');
        }
      }

      _lastSyncAt = DateTime.now();
      // Best-effort cleanup of synced rows older than a week.
      unawaited(_queue.purgeOldSynced());
    } catch (e) {
      // Network/transport-level failure — every operation we tried to send
      // gets bumped back to FAILED so it'll be picked up next time.
      final error = e.toString().replaceFirst('Exception: ', '');
      _lastSyncError = error;
      for (final op in pending) {
        await _queue.markFailed(op.idempotencyKey, error);
      }
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    _setOnline(_isConnected(results));
  }

  bool _isConnected(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  void _setOnline(bool online, {bool suppressFlush = false}) {
    if (_isOnline == online) return;
    _isOnline = online;
    notifyListeners();
    if (online && !suppressFlush) {
      // Reconnected — drain whatever was queued while offline.
      unawaited(flushQueue());
    }
  }

  void _onQueueChanged() {
    // Re-broadcast queue changes so UI watchers of SyncService also rebuild
    // when only the queue mutates (e.g. user enqueues a new operation).
    notifyListeners();
  }
}
