class NotificationItem {
  NotificationItem({
    required this.id,
    required this.titulo,
    required this.mensaje,
    required this.tipo,
    required this.leida,
    required this.fechaCreacion,
  });

  final int id;
  final String titulo;
  final String mensaje;
  final String tipo;
  final bool leida;
  final String fechaCreacion;

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id'] as int,
      titulo: json['titulo'] as String,
      mensaje: json['mensaje'] as String,
      tipo: json['tipo'] as String,
      leida: json['leida'] as bool,
      fechaCreacion: json['fecha_creacion'] as String,
    );
  }
}
