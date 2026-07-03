class TecnicoCercano {
  TecnicoCercano({
    required this.id,
    required this.nombre,
    required this.especialidad,
    required this.latitud,
    required this.longitud,
    required this.distanciaKm,
  });

  final int id;
  final String nombre;
  final String especialidad;
  final double latitud;
  final double longitud;
  final double distanciaKm;

  factory TecnicoCercano.fromJson(Map<String, dynamic> json) {
    return TecnicoCercano(
      id: json['id'] as int,
      nombre: json['nombre'] as String,
      especialidad: json['especialidad'] as String,
      latitud: (json['latitud_actual'] as num).toDouble(),
      longitud: (json['longitud_actual'] as num).toDouble(),
      distanciaKm: (json['distancia_km'] as num).toDouble(),
    );
  }
}
