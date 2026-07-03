/// Offline queue for the Flutter client.
///
/// When the device has no connectivity (or a request fails because of network
/// issues), the user's intent is persisted into a local SQLite table here.
/// As soon as connectivity is restored, [SyncService] reads the queue and
/// POSTs the operations to the backend's `/sync/lote` endpoint, which uses
/// the [idempotencyKey] to deduplicate replays.
///
/// Table: ``offline_queue``
///   id              INTEGER PRIMARY KEY
///   idempotency_key TEXT UNIQUE           (UUIDv4 generated client-side)
///   tipo            TEXT NOT NULL          (crear_solicitud | actualizar_estado | cancelar_solicitud)
///   payload         TEXT NOT NULL          (JSON-encoded body)
///   status          TEXT NOT NULL          (PENDING | SYNCING | FAILED | SYNCED)
///   retry_count     INTEGER DEFAULT 0
///   last_error      TEXT
///   created_at      TEXT NOT NULL          (ISO 8601)
///   synced_at       TEXT
///   server_id       INTEGER                (solicitud_id returned by backend)
///
/// Concurrency note: all DB calls go through the same singleton ``Database``
/// instance, so sqflite serializes them under the hood. We never open the
/// database twice.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// One operation queued for later submission.
@immutable
class QueuedOperation {
  const QueuedOperation({
    required this.id,
    required this.idempotencyKey,
    required this.tipo,
    required this.payload,
    required this.status,
    required this.retryCount,
    required this.createdAt,
    this.lastError,
    this.syncedAt,
    this.serverId,
  });

  final int id;
  final String idempotencyKey;
  final String tipo;                    // e.g. "crear_solicitud"
  final Map<String, dynamic> payload;   // exact JSON body the backend will get
  final String status;                  // PENDING | SYNCING | FAILED | SYNCED
  final int retryCount;
  final DateTime createdAt;
  final String? lastError;
  final DateTime? syncedAt;
  final int? serverId;

  factory QueuedOperation.fromRow(Map<String, Object?> row) => QueuedOperation(
        id:              row['id'] as int,
        idempotencyKey:  row['idempotency_key'] as String,
        tipo:            row['tipo'] as String,
        payload:         jsonDecode(row['payload'] as String) as Map<String, dynamic>,
        status:          row['status'] as String,
        retryCount:      (row['retry_count'] as int?) ?? 0,
        createdAt:       DateTime.parse(row['created_at'] as String),
        lastError:       row['last_error'] as String?,
        syncedAt:        row['synced_at'] != null ? DateTime.tryParse(row['synced_at'] as String) : null,
        serverId:        row['server_id'] as int?,
      );
}

/// Singleton service that owns the local SQLite database and exposes a
/// reactive view of the queue. Register as a [ChangeNotifierProvider] so the
/// UI can show pending counts and offline badges.
class OfflineQueueService extends ChangeNotifier {
  OfflineQueueService();

  static const _dbName     = 'emergency_offline.db';
  static const _dbVersion  = 1;
  static const _tableName  = 'offline_queue';
  static const _uuid       = Uuid();

  Database? _db;
  int _pendingCount = 0;

  /// How many operations are still waiting to be synced. UI watchers should
  /// read this to show the "X pendientes de sincronizar" badge.
  int get pendingCount => _pendingCount;

  // ── Lifecycle ───────────────────────────────────────────────────────────

  Future<Database> _open() async {
    final existing = _db;
    if (existing != null) return existing;
    final dir  = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _dbName);
    final db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            id                INTEGER PRIMARY KEY AUTOINCREMENT,
            idempotency_key   TEXT NOT NULL UNIQUE,
            tipo              TEXT NOT NULL,
            payload           TEXT NOT NULL,
            status            TEXT NOT NULL DEFAULT 'PENDING',
            retry_count       INTEGER NOT NULL DEFAULT 0,
            last_error        TEXT,
            created_at        TEXT NOT NULL,
            synced_at         TEXT,
            server_id         INTEGER
          )
        ''');
        await db.execute('CREATE INDEX idx_status ON $_tableName(status)');
      },
    );
    _db = db;
    await _refreshPendingCount();
    return db;
  }

  Future<void> initialize() async {
    await _open();
  }

  // ── Public API ──────────────────────────────────────────────────────────

  /// Enqueue a new operation. Returns the generated [idempotencyKey] so the
  /// caller can correlate the UI state with the queued row.
  ///
  /// [tipo] must match one of the strings accepted by the backend's
  /// ``SyncOperation.tipo`` field: ``crear_solicitud``, ``actualizar_estado``,
  /// ``cancelar_solicitud``.
  Future<String> enqueue({
    required String tipo,
    required Map<String, dynamic> payload,
  }) async {
    final db   = await _open();
    final key  = _uuid.v4();
    final now  = DateTime.now().toUtc().toIso8601String();

    await db.insert(_tableName, {
      'idempotency_key': key,
      'tipo':            tipo,
      'payload':         jsonEncode(payload),
      'status':          'PENDING',
      'retry_count':     0,
      'created_at':      now,
    });
    await _refreshPendingCount();
    return key;
  }

  /// Returns every operation that still needs to be sent (PENDING or FAILED
  /// with retry headroom). Ordered by creation time so the server replays
  /// events in the order the user produced them.
  Future<List<QueuedOperation>> getPending({int maxRetries = 5}) async {
    final db = await _open();
    final rows = await db.query(
      _tableName,
      where:     'status IN (?, ?) AND retry_count < ?',
      whereArgs: ['PENDING', 'FAILED', maxRetries],
      orderBy:   'created_at ASC',
    );
    return rows.map(QueuedOperation.fromRow).toList(growable: false);
  }

  /// All rows (any status) — used by the "Pendientes de sincronización"
  /// screen so the user can see history including SYNCED ones.
  Future<List<QueuedOperation>> getAll({int limit = 50}) async {
    final db = await _open();
    final rows = await db.query(
      _tableName,
      orderBy: 'created_at DESC',
      limit:   limit,
    );
    return rows.map(QueuedOperation.fromRow).toList(growable: false);
  }

  /// Mark an operation as SYNCING just before we hit the network so any
  /// concurrent sync attempt skips it.
  Future<void> markSyncing(String idempotencyKey) async {
    final db = await _open();
    await db.update(
      _tableName,
      {'status': 'SYNCING'},
      where:     'idempotency_key = ?',
      whereArgs: [idempotencyKey],
    );
    notifyListeners();
  }

  /// Persist a successful sync. [serverId] is the solicitud_id (or whatever
  /// the backend returned) so the UI can deep-link to it.
  Future<void> markSynced(String idempotencyKey, {int? serverId}) async {
    final db = await _open();
    await db.update(
      _tableName,
      {
        'status':    'SYNCED',
        'synced_at': DateTime.now().toUtc().toIso8601String(),
        if (serverId != null) 'server_id': serverId,
        'last_error': null,
      },
      where:     'idempotency_key = ?',
      whereArgs: [idempotencyKey],
    );
    await _refreshPendingCount();
  }

  /// Record a failure and bump the retry counter. Once [retryCount] hits the
  /// service-level cap, the row will stop being picked up by [getPending].
  Future<void> markFailed(String idempotencyKey, String error) async {
    final db = await _open();
    final existing = await db.query(
      _tableName,
      where:     'idempotency_key = ?',
      whereArgs: [idempotencyKey],
      limit:     1,
    );
    final prevRetries = existing.isNotEmpty ? (existing.first['retry_count'] as int? ?? 0) : 0;
    await db.update(
      _tableName,
      {
        'status':       'FAILED',
        'retry_count':  prevRetries + 1,
        'last_error':   error,
      },
      where:     'idempotency_key = ?',
      whereArgs: [idempotencyKey],
    );
    await _refreshPendingCount();
  }

  /// Remove successfully-synced rows older than [olderThan]. Called by the
  /// sync service after a successful batch to keep the DB small.
  Future<void> purgeOldSynced({Duration olderThan = const Duration(days: 7)}) async {
    final db = await _open();
    final threshold = DateTime.now().toUtc().subtract(olderThan).toIso8601String();
    await db.delete(
      _tableName,
      where:     "status = 'SYNCED' AND synced_at IS NOT NULL AND synced_at < ?",
      whereArgs: [threshold],
    );
  }

  /// Drop an operation from the queue entirely (e.g. user manually cancels a
  /// stuck request from the "Pendientes" screen).
  Future<void> discard(String idempotencyKey) async {
    final db = await _open();
    await db.delete(
      _tableName,
      where:     'idempotency_key = ?',
      whereArgs: [idempotencyKey],
    );
    await _refreshPendingCount();
  }

  // ── Internal ────────────────────────────────────────────────────────────

  Future<void> _refreshPendingCount() async {
    final db = await _open();
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM $_tableName WHERE status IN ('PENDING', 'FAILED', 'SYNCING')",
    );
    final count = (result.first['c'] as int?) ?? 0;
    if (count != _pendingCount) {
      _pendingCount = count;
      notifyListeners();
    }
  }
}
