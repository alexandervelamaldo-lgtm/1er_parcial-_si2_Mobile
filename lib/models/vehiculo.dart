class Vehiculo {
  Vehiculo({
    required this.id,
    required this.marca,
    required this.modelo,
    required this.anio,
    required this.placa,
    required this.color,
    required this.tipoCombustible,
  });

  final int id;
  final String marca;
  final String modelo;
  final int anio;
  final String placa;
  final String color;
  final String tipoCombustible;

  factory Vehiculo.fromJson(Map<String, dynamic> json) {
    return Vehiculo(
      id: json['id'] as int,
      marca: json['marca'] as String,
      modelo: json['modelo'] as String,
      anio: json['anio'] as int,
      placa: json['placa'] as String,
      color: json['color'] as String,
      tipoCombustible: json['tipo_combustible'] as String,
    );
  }
}
