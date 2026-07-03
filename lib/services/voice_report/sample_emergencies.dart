class EmergencyReportRow {
  const EmergencyReportRow({
    required this.fechaHora,
    required this.tipoIncidente,
    required this.unidadGrua,
    required this.estadoServicio,
    required this.ubicacion,
  });

  final String fechaHora;
  final String tipoIncidente;
  final String unidadGrua;
  final String estadoServicio;
  final String ubicacion;
}

String formatDateYmd(DateTime dt) {
  String pad2(int v) => v.toString().padLeft(2, '0');
  return '${dt.year}-${pad2(dt.month)}-${pad2(dt.day)}';
}

String _formatDateTime(DateTime dt) {
  String pad2(int v) => v.toString().padLeft(2, '0');
  return '${formatDateYmd(dt)} ${pad2(dt.hour)}:${pad2(dt.minute)}';
}

int _seedFromDate(DateTime dt) => int.parse('${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}');

double _rand01(int x) => (x & 0x7fffffff) / 0x7fffffff;

List<EmergencyReportRow> buildTodayEmergencyDataset([DateTime? now]) {
  final n = now ?? DateTime.now();
  var x = _seedFromDate(n);

  int nextInt() {
    x ^= (x << 13);
    x ^= (x >> 17);
    x ^= (x << 5);
    return x;
  }

  const tipos = ['Accidente', 'Falla mecánica', 'Robo', 'Pinchazo', 'Batería descargada', 'Choque leve'];
  const estados = ['En curso', 'Finalizado', 'Pendiente'];
  const unidades = ['Grúa A-12', 'Grúa B-07', 'Ambulancia M-03', 'Grúa C-21'];
  const ubicaciones = [
    'Santa Cruz: Av. Grigotá',
    'Santa Cruz: 2do Anillo',
    'Santa Cruz: Doble Vía La Guardia',
    'Santa Cruz: Av. Banzer',
    'Santa Cruz: Equipetrol',
    'Santa Cruz: Plan 3000'
  ];

  final rows = <EmergencyReportRow>[];
  for (var i = 0; i < 10; i++) {
    final d = DateTime(n.year, n.month, n.day, 7 + (_rand01(nextInt()) * 12).floor(), (_rand01(nextInt()) * 60).floor());
    rows.add(
      EmergencyReportRow(
        fechaHora: _formatDateTime(d),
        tipoIncidente: tipos[(_rand01(nextInt()) * tipos.length).floor()],
        unidadGrua: unidades[(_rand01(nextInt()) * unidades.length).floor()],
        estadoServicio: estados[(_rand01(nextInt()) * estados.length).floor()],
        ubicacion: ubicaciones[(_rand01(nextInt()) * ubicaciones.length).floor()],
      ),
    );
  }

  rows.sort((a, b) => a.fechaHora.compareTo(b.fechaHora));
  return rows;
}

