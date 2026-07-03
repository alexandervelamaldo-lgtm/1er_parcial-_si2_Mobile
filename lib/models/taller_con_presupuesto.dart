/// Representa un taller candidato con su presupuesto pre-calculado por el
/// backend para la solicitud activa. Es la respuesta del endpoint
/// `GET /solicitudes/{id}/talleres-con-presupuesto` que arma la pantalla
/// de selección directa (flujo cliente↔taller-directo).
library;

class PresupuestoBreakdown {
  const PresupuestoBreakdown({
    required this.montoBase,
    required this.montoFinal,
    required this.rangoMin,
    required this.rangoMax,
    required this.moneda,
    this.descuentoPct,
    this.motivoDescuento,
    this.tiempoHoras,
  });

  final double montoBase;
  final double montoFinal;
  final double rangoMin;
  final double rangoMax;
  final String moneda;
  final double? descuentoPct;
  final String? motivoDescuento;
  final double? tiempoHoras;

  factory PresupuestoBreakdown.fromJson(Map<String, dynamic> json) => PresupuestoBreakdown(
        montoBase:        (json['monto_base']     as num).toDouble(),
        montoFinal:       (json['monto_final']    as num).toDouble(),
        rangoMin:         (json['rango_min']      as num).toDouble(),
        rangoMax:         (json['rango_max']      as num).toDouble(),
        moneda:           json['moneda']          as String? ?? 'BOB',
        descuentoPct:     (json['descuento_pct']  as num?)?.toDouble(),
        motivoDescuento:  json['motivo_descuento'] as String?,
        tiempoHoras:      (json['tiempo_horas']   as num?)?.toDouble(),
      );

  /// True cuando el monto_final es menor al monto_base — útil para mostrar
  /// un badge "Descuento aplicado" sin que el cliente tenga que calcular.
  bool get tieneDescuento => descuentoPct != null && descuentoPct! > 0;
}


class TallerConPresupuesto {
  const TallerConPresupuesto({
    required this.tallerId,
    required this.nombre,
    required this.lat,
    required this.lng,
    required this.distanciaKm,
    required this.ratingPromedio,
    required this.capacidad,
    required this.disponible,
    required this.matchEspecializacion,
    required this.marcaAsociadaDescuento,
    required this.presupuesto,
    required this.score,
    required this.motivo,
    this.direccion,
    this.etaMin,
  });

  final int tallerId;
  final String nombre;
  final String? direccion;
  final double lat;
  final double lng;
  final double distanciaKm;
  final int? etaMin;
  final double ratingPromedio;
  final int capacidad;
  final bool disponible;
  final bool matchEspecializacion;
  final bool marcaAsociadaDescuento;
  final PresupuestoBreakdown presupuesto;
  final double score;
  final String motivo;

  factory TallerConPresupuesto.fromJson(Map<String, dynamic> json) => TallerConPresupuesto(
        tallerId:              json['taller_id'] as int,
        nombre:                json['nombre']    as String,
        direccion:             json['direccion'] as String?,
        lat:                   (json['lat']      as num).toDouble(),
        lng:                   (json['lng']      as num).toDouble(),
        distanciaKm:           (json['distancia_km'] as num).toDouble(),
        etaMin:                json['eta_min']   as int?,
        ratingPromedio:        (json['rating_promedio'] as num).toDouble(),
        capacidad:             json['capacidad'] as int? ?? 0,
        disponible:            json['disponible'] as bool? ?? true,
        matchEspecializacion:  json['match_especializacion'] as bool? ?? false,
        marcaAsociadaDescuento: json['marca_asociada_descuento'] as bool? ?? false,
        presupuesto:           PresupuestoBreakdown.fromJson(
                                 json['presupuesto'] as Map<String, dynamic>),
        score:                 (json['score']    as num).toDouble(),
        motivo:                json['motivo']    as String? ?? '',
      );
}


class TalleresConPresupuestoResponse {
  const TalleresConPresupuestoResponse({
    required this.solicitudId,
    required this.radioKm,
    required this.total,
    required this.talleres,
    required this.cachedAt,
    this.mensaje,
  });

  final int solicitudId;
  final double radioKm;
  final int total;
  final List<TallerConPresupuesto> talleres;
  final String cachedAt;
  final String? mensaje;

  factory TalleresConPresupuestoResponse.fromJson(Map<String, dynamic> json) =>
      TalleresConPresupuestoResponse(
        solicitudId: json['solicitud_id']    as int,
        radioKm:     (json['radio_km']       as num).toDouble(),
        total:       json['total']           as int,
        talleres:    ((json['talleres']      as List?) ?? const [])
                       .map((e) => TallerConPresupuesto.fromJson(e as Map<String, dynamic>))
                       .toList(growable: false),
        cachedAt:    json['cached_at']       as String,
        mensaje:     json['mensaje']         as String?,
      );
}
