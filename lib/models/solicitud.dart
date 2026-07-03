import 'package:latlong2/latlong.dart';

class Solicitud {
  Solicitud({
    required this.id,
    this.tenantKey,
    required this.descripcion,
    required this.prioridad,
    required this.fechaSolicitud,
    required this.estado,
    required this.tipoIncidente,
    this.latitudIncidente,
    this.longitudIncidente,
    this.clasificacionConfianza,
    this.requiereRevisionManual = false,
    this.resumenIa,
    this.motivoPrioridad,
    this.etiquetasIa = const [],
    this.transcripcionAudio,
    this.proveedorIa,
    this.clienteAprobada,
    this.propuestaExpiraEn,
    this.esCarretera = false,
    this.condicionVehiculo,
    this.nivelRiesgo,
    this.costoEstimado,
    this.costoEstimadoMin,
    this.costoEstimadoMax,
    this.costoEstimacionConfianza,
    this.costoEstimacionNota,
    this.costoFinal,
    this.monedaCosto = 'BOB',
    this.trabajoTerminado = false,
    this.trabajoTerminadoEn,
    this.trabajoTerminadoObservacion,
    this.tallerId,
    this.tecnicoId,
  });

  final int id;
  final String? tenantKey;
  final String descripcion;
  final String prioridad;
  final String fechaSolicitud;
  final String estado;
  final String tipoIncidente;
  final double? latitudIncidente;
  final double? longitudIncidente;
  final double? clasificacionConfianza;
  final bool requiereRevisionManual;
  final String? resumenIa;
  final String? motivoPrioridad;
  final List<String> etiquetasIa;
  final String? transcripcionAudio;
  final String? proveedorIa;
  final bool? clienteAprobada;
  final String? propuestaExpiraEn;
  final bool esCarretera;
  final String? condicionVehiculo;
  final int? nivelRiesgo;
  final double? costoEstimado;
  final double? costoEstimadoMin;
  final double? costoEstimadoMax;
  final double? costoEstimacionConfianza;
  final String? costoEstimacionNota;
  final double? costoFinal;
  final String monedaCosto;
  final bool trabajoTerminado;
  final String? trabajoTerminadoEn;
  final String? trabajoTerminadoObservacion;
  final int? tallerId;
  final int? tecnicoId;

  factory Solicitud.fromJson(Map<String, dynamic> json) {
    return Solicitud(
      id: json['id'] as int,
      tenantKey: json['tenant_key'] as String?,
      descripcion: json['descripcion'] as String? ?? '',
      prioridad: json['prioridad'] as String? ?? 'MEDIA',
      fechaSolicitud: json['fecha_solicitud'] as String? ?? '',
      estado: (json['estado'] as Map<String, dynamic>?)?['nombre'] as String? ?? 'Sin estado',
      tipoIncidente: (json['tipo_incidente'] as Map<String, dynamic>?)?['nombre'] as String? ?? 'Sin tipo',
      latitudIncidente: (json['latitud_incidente'] as num?)?.toDouble(),
      longitudIncidente: (json['longitud_incidente'] as num?)?.toDouble(),
      clasificacionConfianza: (json['clasificacion_confianza'] as num?)?.toDouble(),
      requiereRevisionManual: json['requiere_revision_manual'] as bool? ?? false,
      resumenIa: json['resumen_ia'] as String?,
      motivoPrioridad: json['motivo_prioridad'] as String?,
      etiquetasIa: _splitTags(json['etiquetas_ia'] as String?),
      transcripcionAudio: json['transcripcion_audio'] as String?,
      proveedorIa: json['proveedor_ia'] as String?,
      clienteAprobada: json['cliente_aprobada'] as bool?,
      propuestaExpiraEn: json['propuesta_expira_en'] as String?,
      esCarretera: json['es_carretera'] as bool? ?? false,
      condicionVehiculo: json['condicion_vehiculo'] as String?,
      nivelRiesgo: json['nivel_riesgo'] as int?,
      costoEstimado: (json['costo_estimado'] as num?)?.toDouble(),
      costoEstimadoMin: (json['costo_estimado_min'] as num?)?.toDouble(),
      costoEstimadoMax: (json['costo_estimado_max'] as num?)?.toDouble(),
      costoEstimacionConfianza: (json['costo_estimacion_confianza'] as num?)?.toDouble(),
      costoEstimacionNota: json['costo_estimacion_nota'] as String?,
      costoFinal: (json['costo_final'] as num?)?.toDouble(),
      monedaCosto: json['moneda_costo'] as String? ?? 'BOB',
      trabajoTerminado: json['trabajo_terminado'] as bool? ?? false,
      trabajoTerminadoEn: json['trabajo_terminado_en'] as String?,
      trabajoTerminadoObservacion: json['trabajo_terminado_observacion'] as String?,
      tallerId: json['taller_id'] as int?,
      tecnicoId: json['tecnico_id'] as int?,
    );
  }
}

class SolicitudDetalle extends Solicitud {
  SolicitudDetalle({
    required super.id,
    super.tenantKey,
    required super.descripcion,
    required super.prioridad,
    required super.fechaSolicitud,
    required super.estado,
    required super.tipoIncidente,
    super.latitudIncidente,
    super.longitudIncidente,
    super.clasificacionConfianza,
    super.requiereRevisionManual,
    super.resumenIa,
    super.motivoPrioridad,
    super.etiquetasIa,
    super.transcripcionAudio,
    super.proveedorIa,
    super.clienteAprobada,
    super.propuestaExpiraEn,
    super.esCarretera,
    super.condicionVehiculo,
    super.nivelRiesgo,
    super.costoEstimado,
    super.costoEstimadoMin,
    super.costoEstimadoMax,
    super.costoEstimacionConfianza,
    super.costoEstimacionNota,
    super.costoFinal,
    super.monedaCosto,
    super.trabajoTerminado,
    super.trabajoTerminadoEn,
    super.trabajoTerminadoObservacion,
    super.tallerId,
    super.tecnicoId,
    required this.evidencias,
    required this.pagos,
    required this.disputas,
    required this.historial,
  });

  final List<EvidenciaSolicitud> evidencias;
  final List<PagoSolicitud> pagos;
  final List<DisputaSolicitud> disputas;
  final List<HistorialSolicitud> historial;

  factory SolicitudDetalle.fromJson(Map<String, dynamic> json) {
    final base = Solicitud.fromJson(json);
    return SolicitudDetalle(
      id: base.id,
      tenantKey: base.tenantKey,
      descripcion: base.descripcion,
      prioridad: base.prioridad,
      fechaSolicitud: base.fechaSolicitud,
      estado: base.estado,
      tipoIncidente: base.tipoIncidente,
      latitudIncidente: base.latitudIncidente,
      longitudIncidente: base.longitudIncidente,
      clasificacionConfianza: base.clasificacionConfianza,
      requiereRevisionManual: base.requiereRevisionManual,
      resumenIa: base.resumenIa,
      motivoPrioridad: base.motivoPrioridad,
      etiquetasIa: base.etiquetasIa,
      transcripcionAudio: base.transcripcionAudio,
      proveedorIa: base.proveedorIa,
      clienteAprobada: base.clienteAprobada,
      propuestaExpiraEn: base.propuestaExpiraEn,
      esCarretera: base.esCarretera,
      condicionVehiculo: base.condicionVehiculo,
      nivelRiesgo: base.nivelRiesgo,
      costoEstimado: base.costoEstimado,
      costoEstimadoMin: base.costoEstimadoMin,
      costoEstimadoMax: base.costoEstimadoMax,
      costoEstimacionConfianza: base.costoEstimacionConfianza,
      costoEstimacionNota: base.costoEstimacionNota,
      costoFinal: base.costoFinal,
      monedaCosto: base.monedaCosto,
      trabajoTerminado: base.trabajoTerminado,
      trabajoTerminadoEn: base.trabajoTerminadoEn,
      trabajoTerminadoObservacion: base.trabajoTerminadoObservacion,
      tallerId: base.tallerId,
      tecnicoId: base.tecnicoId,
      evidencias: (json['evidencias'] as List<dynamic>? ?? [])
          .map((item) => EvidenciaSolicitud.fromJson(item as Map<String, dynamic>))
          .toList(),
      pagos: (json['pagos'] as List<dynamic>? ?? [])
          .map((item) => PagoSolicitud.fromJson(item as Map<String, dynamic>))
          .toList(),
      disputas: (json['disputas'] as List<dynamic>? ?? [])
          .map((item) => DisputaSolicitud.fromJson(item as Map<String, dynamic>))
          .toList(),
      historial: (json['historial'] as List<dynamic>? ?? [])
          .map((item) => HistorialSolicitud.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class SolicitudSeguimiento {
  SolicitudSeguimiento({
    required this.estado,
    required this.solicitudId,
    this.routeColor,
    this.servicioEstado,
    this.tecnicoId,
    this.tallerNombre,
    this.latitudTaller,
    this.longitudTaller,
    this.tecnicoNombre,
    this.latitudCliente,
    this.longitudCliente,
    this.latitudServicio,
    this.longitudServicio,
    this.latitudActual,
    this.longitudActual,
    this.distanciaKm,
    this.etaMin,
    this.etaMinLower,
    this.etaMinUpper,
    this.rutaSeguimiento,
    this.ubicacionActualizadaEn,
    this.ubicacionDesactualizada = false,
    this.trackingActivo = false,
    this.sinSenal = false,
    this.requiereCompartirUbicacion = false,
    this.clienteAprobada,
    this.propuestaExpiraEn,
    this.propuestaExpirada = false,
    this.mensaje,
  });

  final String estado;
  final int solicitudId;
  final String? routeColor;
  final String? servicioEstado;
  final int? tecnicoId;
  final String? tallerNombre;
  final double? latitudTaller;
  final double? longitudTaller;
  final String? tecnicoNombre;
  final double? latitudCliente;
  final double? longitudCliente;
  final double? latitudServicio;
  final double? longitudServicio;
  final double? latitudActual;
  final double? longitudActual;
  final double? distanciaKm;
  final int? etaMin;
  /// Rango calibrado del ETA. Cuando `upper - lower > 5` la UI debe
  /// mostrar "12-18 min" en lugar de un valor único — el backend nos
  /// dice así que la varianza esperada es alta. Si ambos son null,
  /// usar `etaMin` solo (cliente legacy o sin tracking activo).
  final int? etaMinLower;
  final int? etaMinUpper;
  /// Ruta vial (taller → incidente) que envía el backend en `ruta_seguimiento`
  /// cuando el taller atiende sin técnico. Es la MISMA geometría que dibuja la
  /// web, así el camino sigue las calles y el "muñeco" simulado la recorre.
  /// Null cuando hay técnico con GPS real o cuando Mapbox no devolvió ruta.
  final List<LatLng>? rutaSeguimiento;
  final String? ubicacionActualizadaEn;
  final bool ubicacionDesactualizada;
  final bool trackingActivo;
  final bool sinSenal;
  final bool requiereCompartirUbicacion;
  final bool? clienteAprobada;
  final String? propuestaExpiraEn;
  final bool propuestaExpirada;
  final String? mensaje;

  factory SolicitudSeguimiento.fromJson(Map<String, dynamic> json) {
    return SolicitudSeguimiento(
      estado: json['estado'] as String? ?? 'Sin estado',
      solicitudId: json['solicitud_id'] as int,
      routeColor: json['route_color'] as String?,
      servicioEstado: json['servicio_estado'] as String?,
      tecnicoId: json['tecnico_id'] as int?,
      tallerNombre: json['taller_nombre'] as String?,
      latitudTaller: (json['latitud_taller'] as num?)?.toDouble(),
      longitudTaller: (json['longitud_taller'] as num?)?.toDouble(),
      tecnicoNombre: json['tecnico_nombre'] as String?,
      latitudCliente: (json['latitud_cliente'] as num?)?.toDouble(),
      longitudCliente: (json['longitud_cliente'] as num?)?.toDouble(),
      latitudServicio: (json['latitud_servicio'] as num?)?.toDouble(),
      longitudServicio: (json['longitud_servicio'] as num?)?.toDouble(),
      latitudActual: (json['latitud_actual'] as num?)?.toDouble(),
      longitudActual: (json['longitud_actual'] as num?)?.toDouble(),
      distanciaKm: (json['distancia_km'] as num?)?.toDouble(),
      etaMin: json['eta_min'] as int?,
      etaMinLower: json['eta_min_lower'] as int?,
      etaMinUpper: json['eta_min_upper'] as int?,
      rutaSeguimiento: _parseRouteGeometry(json['ruta_seguimiento']),
      ubicacionActualizadaEn: json['ubicacion_actualizada_en'] as String?,
      ubicacionDesactualizada: json['ubicacion_desactualizada'] as bool? ?? false,
      trackingActivo: json['tracking_activo'] as bool? ?? false,
      sinSenal: json['sin_senal'] as bool? ?? false,
      requiereCompartirUbicacion: json['requiere_compartir_ubicacion'] as bool? ?? false,
      clienteAprobada: json['cliente_aprobada'] as bool?,
      propuestaExpiraEn: json['propuesta_expira_en'] as String?,
      propuestaExpirada: json['propuesta_expirada'] as bool? ?? false,
      mensaje: json['mensaje'] as String?,
    );
  }
}

class SolicitudCandidatos {
  SolicitudCandidatos({
    required this.solicitudId,
    required this.hayCobertura,
    required this.talleres,
    required this.tecnicos,
    this.mensaje,
  });

  final int solicitudId;
  final bool hayCobertura;
  final String? mensaje;
  final List<TallerCandidato> talleres;
  final List<TecnicoCandidato> tecnicos;

  factory SolicitudCandidatos.fromJson(Map<String, dynamic> json) {
    return SolicitudCandidatos(
      solicitudId: json['solicitud_id'] as int,
      hayCobertura: json['hay_cobertura'] as bool? ?? false,
      mensaje: json['mensaje'] as String?,
      talleres: (json['talleres'] as List<dynamic>? ?? [])
          .map((item) => TallerCandidato.fromJson(item as Map<String, dynamic>))
          .toList(),
      tecnicos: (json['tecnicos'] as List<dynamic>? ?? [])
          .map((item) => TecnicoCandidato.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class TallerCandidato {
  TallerCandidato({
    required this.id,
    required this.nombre,
    this.distanciaKm,
    this.score,
    this.matchEspecializacion = false,
    this.motivoSugerencia,
  });

  final int id;
  final String nombre;
  final double? distanciaKm;
  final double? score;
  final bool matchEspecializacion;
  final String? motivoSugerencia;

  factory TallerCandidato.fromJson(Map<String, dynamic> json) {
    return TallerCandidato(
      id: json['id'] as int,
      nombre: json['nombre'] as String? ?? 'Taller',
      distanciaKm: (json['distancia_km'] as num?)?.toDouble(),
      score: (json['score'] as num?)?.toDouble(),
      matchEspecializacion: json['match_especializacion'] as bool? ?? false,
      motivoSugerencia: json['motivo_sugerencia'] as String?,
    );
  }
}

class TecnicoCandidato {
  TecnicoCandidato({
    required this.id,
    required this.nombre,
    this.etaMin,
    this.distanciaKm,
  });

  final int id;
  final String nombre;
  final int? etaMin;
  final double? distanciaKm;

  factory TecnicoCandidato.fromJson(Map<String, dynamic> json) {
    return TecnicoCandidato(
      id: json['id'] as int,
      nombre: json['nombre'] as String? ?? 'Taller',
      etaMin: json['eta_min'] as int?,
      distanciaKm: (json['distancia_km'] as num?)?.toDouble(),
    );
  }
}

class EvidenciaSolicitud {
  EvidenciaSolicitud({
    required this.tipo,
    this.nombreArchivo,
    this.contenidoTexto,
  });

  final String tipo;
  final String? nombreArchivo;
  final String? contenidoTexto;

  factory EvidenciaSolicitud.fromJson(Map<String, dynamic> json) {
    return EvidenciaSolicitud(
      tipo: json['tipo'] as String? ?? 'EVIDENCIA',
      nombreArchivo: json['nombre_archivo'] as String?,
      contenidoTexto: json['contenido_texto'] as String?,
    );
  }
}

class PagoSolicitud {
  PagoSolicitud({
    required this.metodoPago,
    required this.estado,
    required this.montoTotal,
    required this.montoComision,
    this.referenciaExterna,
    this.observacion,
  });

  final String metodoPago;
  final String estado;
  final double montoTotal;
  final double montoComision;
  final String? referenciaExterna;
  final String? observacion;

  factory PagoSolicitud.fromJson(Map<String, dynamic> json) {
    return PagoSolicitud(
      metodoPago: json['metodo_pago'] as String? ?? 'sin método',
      estado: json['estado'] as String? ?? 'PENDIENTE',
      montoTotal: (json['monto_total'] as num?)?.toDouble() ?? 0,
      montoComision: (json['monto_comision'] as num?)?.toDouble() ?? 0,
      referenciaExterna: json['referencia_externa'] as String?,
      observacion: json['observacion'] as String?,
    );
  }
}

class DisputaSolicitud {
  DisputaSolicitud({
    required this.estado,
    required this.motivo,
    required this.detalle,
  });

  final String estado;
  final String motivo;
  final String detalle;

  factory DisputaSolicitud.fromJson(Map<String, dynamic> json) {
    return DisputaSolicitud(
      estado: json['estado'] as String? ?? 'ABIERTA',
      motivo: json['motivo'] as String? ?? 'Soporte',
      detalle: json['detalle'] as String? ?? '',
    );
  }
}

class HistorialSolicitud {
  HistorialSolicitud({
    required this.estadoAnterior,
    required this.estadoNuevo,
    required this.observacion,
  });

  final String estadoAnterior;
  final String estadoNuevo;
  final String observacion;

  factory HistorialSolicitud.fromJson(Map<String, dynamic> json) {
    return HistorialSolicitud(
      estadoAnterior: json['estado_anterior'] as String? ?? '',
      estadoNuevo: json['estado_nuevo'] as String? ?? '',
      observacion: json['observacion'] as String? ?? '',
    );
  }
}

/// Convierte el GeoJSON `{"type":"LineString","coordinates":[[lng,lat],...]}`
/// que manda el backend en una lista de `LatLng`. Devuelve null si el formato
/// no es válido o tiene menos de 2 puntos (no es una ruta dibujable).
List<LatLng>? _parseRouteGeometry(dynamic raw) {
  if (raw is! Map) return null;
  final coords = raw['coordinates'];
  if (coords is! List || coords.length < 2) return null;
  final points = <LatLng>[];
  for (final entry in coords) {
    if (entry is! List || entry.length < 2) continue;
    final lng = (entry[0] as num?)?.toDouble();
    final lat = (entry[1] as num?)?.toDouble();
    if (lat == null || lng == null) continue;
    points.add(LatLng(lat, lng));
  }
  return points.length >= 2 ? points : null;
}

List<String> _splitTags(String? raw) {
  if (raw == null || raw.isEmpty) {
    return const [];
  }
  return raw.split('|').where((item) => item.trim().isNotEmpty).map((item) => item.trim()).toList();
}
