class Solicitud {
  Solicitud({
    required this.id,
    required this.descripcion,
    required this.prioridad,
    required this.fechaSolicitud,
    required this.estado,
    required this.tipoIncidente,
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
    this.tallerId,
    this.tecnicoId,
  });

  final int id;
  final String descripcion;
  final String prioridad;
  final String fechaSolicitud;
  final String estado;
  final String tipoIncidente;
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
  final int? tallerId;
  final int? tecnicoId;

  factory Solicitud.fromJson(Map<String, dynamic> json) {
    return Solicitud(
      id: json['id'] as int,
      descripcion: json['descripcion'] as String? ?? '',
      prioridad: json['prioridad'] as String? ?? 'MEDIA',
      fechaSolicitud: json['fecha_solicitud'] as String? ?? '',
      estado: (json['estado'] as Map<String, dynamic>?)?['nombre'] as String? ?? 'Sin estado',
      tipoIncidente: (json['tipo_incidente'] as Map<String, dynamic>?)?['nombre'] as String? ?? 'Sin tipo',
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
      tallerId: json['taller_id'] as int?,
      tecnicoId: json['tecnico_id'] as int?,
    );
  }
}

class SolicitudDetalle extends Solicitud {
  SolicitudDetalle({
    required super.id,
    required super.descripcion,
    required super.prioridad,
    required super.fechaSolicitud,
    required super.estado,
    required super.tipoIncidente,
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
      descripcion: base.descripcion,
      prioridad: base.prioridad,
      fechaSolicitud: base.fechaSolicitud,
      estado: base.estado,
      tipoIncidente: base.tipoIncidente,
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
    this.tallerNombre,
    this.tecnicoNombre,
    this.distanciaKm,
    this.etaMin,
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
  final String? tallerNombre;
  final String? tecnicoNombre;
  final double? distanciaKm;
  final int? etaMin;
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
      tallerNombre: json['taller_nombre'] as String?,
      tecnicoNombre: json['tecnico_nombre'] as String?,
      distanciaKm: (json['distancia_km'] as num?)?.toDouble(),
      etaMin: json['eta_min'] as int?,
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
      nombre: json['nombre'] as String? ?? 'Técnico',
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

List<String> _splitTags(String? raw) {
  if (raw == null || raw.isEmpty) {
    return const [];
  }
  return raw.split('|').where((item) => item.trim().isNotEmpty).map((item) => item.trim()).toList();
}
