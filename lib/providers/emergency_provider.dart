import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/notification_item.dart';
import '../models/solicitud.dart';
import '../models/tecnico_cercano.dart';
import '../models/vehiculo.dart';
import '../services/api_service.dart';


class EmergencyProvider extends ChangeNotifier {
  EmergencyProvider(this._api);

  final ApiService _api;

  List<Solicitud> _solicitudes = [];
  List<Vehiculo> _vehiculos = [];
  List<NotificationItem> _notificaciones = [];
  List<TecnicoCercano> _tecnicosCercanos = [];
  // Active service tracking (in-route solicitudes), keyed by solicitudId.
  // Used by the dashboard map to render real routes + ETAs.
  Map<int, SolicitudSeguimiento> _seguimientosActivos = const {};
  bool _loading = false;
  String? _error;

  List<Solicitud> get solicitudes => _solicitudes;
  List<Vehiculo> get vehiculos => _vehiculos;
  List<NotificationItem> get notificaciones => _notificaciones;
  List<TecnicoCercano> get tecnicosCercanos => _tecnicosCercanos;
  Map<int, SolicitudSeguimiento> get seguimientosActivos => _seguimientosActivos;
  bool get loading => _loading;
  String? get error => _error;

  /// Returns true when a solicitud's estado indicates the service is in route
  /// (the worker is heading to the incident location).
  static bool esEnCamino(Solicitud s) {
    final e = s.estado.toUpperCase();
    return e == 'EN_CAMINO' ||
        e == 'EN_ATENCION' ||
        e.contains('PROCESO') ||
        e.contains('ASIGNAD') ||
        e.contains('ACEPTAD');
  }

  // ── WebSocket-driven state update ─────────────────────────────────────────

  /// Called by the WebSocket service when a [solicitud_update] event arrives.
  /// Updates the matching solicitud's estado in-place without a full reload.
  void applyWsSolicitudUpdate({
    required int solicitudId,
    required String estado,
  }) {
    var changed = false;
    _solicitudes = _solicitudes.map((s) {
      if (s.id == solicitudId && s.estado != estado) {
        changed = true;
        return Solicitud(
          id: s.id,
          descripcion: s.descripcion,
          prioridad: s.prioridad,
          fechaSolicitud: s.fechaSolicitud,
          estado: estado,
          tipoIncidente: s.tipoIncidente,
          latitudIncidente: s.latitudIncidente,
          longitudIncidente: s.longitudIncidente,
          clasificacionConfianza: s.clasificacionConfianza,
          requiereRevisionManual: s.requiereRevisionManual,
          resumenIa: s.resumenIa,
          motivoPrioridad: s.motivoPrioridad,
          etiquetasIa: s.etiquetasIa,
          transcripcionAudio: s.transcripcionAudio,
          proveedorIa: s.proveedorIa,
          clienteAprobada: s.clienteAprobada,
          propuestaExpiraEn: s.propuestaExpiraEn,
          esCarretera: s.esCarretera,
          condicionVehiculo: s.condicionVehiculo,
          nivelRiesgo: s.nivelRiesgo,
          costoEstimado: s.costoEstimado,
          costoEstimadoMin: s.costoEstimadoMin,
          costoEstimadoMax: s.costoEstimadoMax,
          costoEstimacionConfianza: s.costoEstimacionConfianza,
          costoEstimacionNota: s.costoEstimacionNota,
          costoFinal: s.costoFinal,
          monedaCosto: s.monedaCosto,
          trabajoTerminado: s.trabajoTerminado,
          trabajoTerminadoEn: s.trabajoTerminadoEn,
          trabajoTerminadoObservacion: s.trabajoTerminadoObservacion,
          tallerId: s.tallerId,
          tecnicoId: s.tecnicoId,
        );
      }
      return s;
    }).toList();
    if (changed) notifyListeners();
  }

  Future<void> cargarDatos(String token) async {
    _loading = true;
    _error = null;
    notifyListeners();
    // Cargas independientes con manejo de error POR llamada. Antes usábamos un
    // Future.wait monolítico y un solo try/catch: si UNA de las 3 fallaba (p.ej.
    // /notificaciones devolvía 500 por una migración pendiente en el tenant),
    // las OTRAS dos quedaban vacías también y el usuario veía "Solicitudes: 0,
    // Vehículos: 0" en silencio sin pista del problema. Ahora cada lista carga
    // independiente; si una falla, conservamos la lista previa intacta y
    // anotamos el error puntual en `_error` para diagnóstico.
    final errors = <String>[];
    String clean(Object e) => e.toString().replaceFirst('Exception: ', '');
    final results = await Future.wait<Object>([
      _api.obtenerSolicitudes(token).catchError((Object e) {
        errors.add('solicitudes: ${clean(e)}');
        return _solicitudes;
      }),
      _api.obtenerVehiculos(token).catchError((Object e) {
        errors.add('vehiculos: ${clean(e)}');
        return _vehiculos;
      }),
      _api.obtenerNotificaciones(token).catchError((Object e) {
        errors.add('notificaciones: ${clean(e)}');
        return _notificaciones;
      }),
    ]);
    _solicitudes = results[0] as List<Solicitud>;
    _vehiculos = results[1] as List<Vehiculo>;
    _notificaciones = results[2] as List<NotificationItem>;
    _error = errors.isEmpty ? null : errors.join('; ');
    _loading = false;
    notifyListeners();
    // Fire and forget: refresh seguimientos for in-route services so the
    // dashboard map can draw routes + ETAs without blocking the main load.
    unawaited(cargarSeguimientosActivos(token));
  }

  /// Loads [SolicitudSeguimiento] for every solicitud currently in route
  /// (limited to a few to keep the dashboard light). Failures are silently
  /// ignored per-solicitud — the others still render.
  Future<void> cargarSeguimientosActivos(String token, {int max = 5}) async {
    final activos = _solicitudes.where(esEnCamino).take(max).toList(growable: false);
    if (activos.isEmpty) {
      if (_seguimientosActivos.isNotEmpty) {
        _seguimientosActivos = const {};
        notifyListeners();
      }
      return;
    }
    final results = await Future.wait(
      activos.map((s) async {
        try {
          final seg = await _api.obtenerSeguimientoSolicitud(token, s.id);
          return MapEntry(s.id, seg);
        } catch (_) {
          return null;
        }
      }),
    );
    final next = <int, SolicitudSeguimiento>{};
    for (final entry in results) {
      if (entry != null) next[entry.key] = entry.value;
    }
    _seguimientosActivos = next;
    notifyListeners();
  }

  Future<void> cargarTecnicosCercanos(
    String token, {
    required double latitud,
    required double longitud,
  }) async {
    try {
      _tecnicosCercanos = await _api.obtenerTecnicosCercanos(
        token,
        latitud: latitud,
        longitud: longitud,
      );
      notifyListeners();
    } catch (_) {}
  }

  Future<void> marcarNotificacionLeida(String token, int notificacionId) async {
    try {
      await _api.marcarNotificacionLeida(token, notificacionId);
      _notificaciones = _notificaciones
          .map((n) => n.id == notificacionId
              ? NotificationItem(
                  id: n.id,
                  titulo: n.titulo,
                  mensaje: n.mensaje,
                  tipo: n.tipo,
                  leida: true,
                  fechaCreacion: n.fechaCreacion,
                )
              : n)
          .toList();
      notifyListeners();
    } catch (_) {}
  }

  void clear() {
    _solicitudes = [];
    _vehiculos = [];
    _notificaciones = [];
    _tecnicosCercanos = [];
    _error = null;
    notifyListeners();
  }
}
