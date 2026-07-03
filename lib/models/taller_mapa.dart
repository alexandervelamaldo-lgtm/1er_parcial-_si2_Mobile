import 'categoria_taller.dart';


class TallerMapa {
  const TallerMapa({
    required this.id,
    required this.nombre,
    required this.direccion,
    required this.latitud,
    required this.longitud,
    required this.telefono,
    required this.horarios,
    required this.certificaciones,
    required this.ratingPromedio,
    required this.ratingTotal,
    required this.distanciaKm,
    required this.presupuestoMin,
    required this.presupuestoMax,
    required this.presupuestoDescuentoMin,
    required this.presupuestoDescuentoMax,
    required this.descuentoPorcentajeAplicado,
    required this.tiempoReparacionHoras,
    required this.categoria,
  });

  final int id;
  final String nombre;
  final String direccion;
  final double latitud;
  final double longitud;
  final String telefono;
  final String? horarios;
  final String? certificaciones;
  final double? ratingPromedio;
  final int? ratingTotal;
  final double? distanciaKm;
  final double? presupuestoMin;
  final double? presupuestoMax;
  final double? presupuestoDescuentoMin;
  final double? presupuestoDescuentoMax;
  final double? descuentoPorcentajeAplicado;
  final double? tiempoReparacionHoras;
  final CategoriaTaller? categoria;

  factory TallerMapa.fromJson(Map<String, dynamic> json) {
    return TallerMapa(
      id: json['id'] as int,
      nombre: json['nombre'] as String? ?? 'Taller',
      direccion: json['direccion'] as String? ?? '',
      latitud: (json['latitud'] as num).toDouble(),
      longitud: (json['longitud'] as num).toDouble(),
      telefono: json['telefono'] as String? ?? '',
      horarios: json['horarios'] as String?,
      certificaciones: json['certificaciones'] as String?,
      ratingPromedio: (json['rating_promedio'] as num?)?.toDouble(),
      ratingTotal: json['rating_total'] as int?,
      distanciaKm: (json['distancia_km'] as num?)?.toDouble(),
      presupuestoMin: (json['presupuesto_min'] as num?)?.toDouble(),
      presupuestoMax: (json['presupuesto_max'] as num?)?.toDouble(),
      presupuestoDescuentoMin: (json['presupuesto_descuento_min'] as num?)?.toDouble(),
      presupuestoDescuentoMax: (json['presupuesto_descuento_max'] as num?)?.toDouble(),
      descuentoPorcentajeAplicado: (json['descuento_porcentaje_aplicado'] as num?)?.toDouble(),
      tiempoReparacionHoras: (json['tiempo_reparacion_horas'] as num?)?.toDouble(),
      categoria: json['categoria'] is Map<String, dynamic>
          ? CategoriaTaller.fromJson(json['categoria'] as Map<String, dynamic>)
          : null,
    );
  }
}
