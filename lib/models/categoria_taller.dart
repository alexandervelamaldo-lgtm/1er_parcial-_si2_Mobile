class CategoriaTaller {
  const CategoriaTaller({
    required this.id,
    required this.slug,
    required this.nombre,
    required this.descripcion,
  });

  final int id;
  final String slug;
  final String nombre;
  final String? descripcion;

  factory CategoriaTaller.fromJson(Map<String, dynamic> json) {
    return CategoriaTaller(
      id: json['id'] as int,
      slug: json['slug'] as String? ?? '',
      nombre: json['nombre'] as String? ?? '',
      descripcion: json['descripcion'] as String?,
    );
  }
}

