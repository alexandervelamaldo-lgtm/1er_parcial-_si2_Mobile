import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'sample_emergencies.dart';

/// Generadores offline (PDF/XLSX) + guardado preferente en Descargas (Android) con fallback seguro.
class ReportFileResult {
  const ReportFileResult({required this.path});

  final String path;
}

Future<Directory> _resolveOutputDir() async {
  if (Platform.isAndroid) {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir != null) return dir;
    } catch (_) {}
  }
  final dir = await getApplicationDocumentsDirectory();
  return dir;
}

Future<ReportFileResult> generatePdfReport(List<EmergencyReportRow> rows, {DateTime? now}) async {
  final n = now ?? DateTime.now();
  final ymd = formatDateYmd(n);

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (context) => [
        pw.Text(
          'Plataforma Inteligente de Atención de Emergencias Vehiculares',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Text('Reporte de emergencias (hoy) · $ymd', style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headers: const ['Fecha y hora', 'Tipo', 'Unidad', 'Estado', 'Ubicación'],
          data: rows
              .map((r) => [r.fechaHora, r.tipoIncidente, r.unidadGrua, r.estadoServicio, r.ubicacion])
              .toList(growable: false),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellAlignment: pw.Alignment.centerLeft,
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          border: pw.TableBorder.all(color: PdfColors.grey300),
          columnWidths: {
            0: const pw.FlexColumnWidth(1.3),
            1: const pw.FlexColumnWidth(1.2),
            2: const pw.FlexColumnWidth(1.0),
            3: const pw.FlexColumnWidth(0.9),
            4: const pw.FlexColumnWidth(1.6),
          },
        ),
      ],
    ),
  );

  final bytes = await doc.save();
  return _writeBytes(bytes, 'reporte_emergencias_$ymd.pdf');
}

Future<ReportFileResult> generateExcelReport(List<EmergencyReportRow> rows, {DateTime? now}) async {
  final n = now ?? DateTime.now();
  final ymd = formatDateYmd(n);

  final excel = Excel.createExcel();
  final sheet = excel['Emergencias'];

  // excel 4.x cambió la API: appendRow recibe List<CellValue?> en vez de
  // List<dynamic>. TextCellValue es el wrapper para strings.
  sheet.appendRow([
    TextCellValue('Fecha y hora'),
    TextCellValue('Tipo de incidente'),
    TextCellValue('Unidad asignada'),
    TextCellValue('Estado del servicio'),
    TextCellValue('Ubicación del siniestro'),
  ]);

  for (final r in rows) {
    sheet.appendRow([
      TextCellValue(r.fechaHora),
      TextCellValue(r.tipoIncidente),
      TextCellValue(r.unidadGrua),
      TextCellValue(r.estadoServicio),
      TextCellValue(r.ubicacion),
    ]);
  }

  final bytes = excel.encode();
  if (bytes == null) {
    throw Exception('No se pudo generar el Excel.');
  }
  return _writeBytes(Uint8List.fromList(bytes), 'reporte_emergencias_$ymd.xlsx');
}

Future<ReportFileResult> generateTxtReport(List<EmergencyReportRow> rows, {DateTime? now}) async {
  final n = now ?? DateTime.now();
  final ymd = formatDateYmd(n);
  final lines = <String>[];
  lines.add('Plataforma Inteligente de Atención de Emergencias Vehiculares');
  lines.add('Reporte de emergencias (hoy) · $ymd');
  lines.add('');
  lines.add('Fecha/hora\tTipo\tUnidad\tEstado\tUbicación');
  for (final r in rows) {
    lines.add([r.fechaHora, r.tipoIncidente, r.unidadGrua, r.estadoServicio, r.ubicacion].join('\t'));
  }
  lines.add('');
  final bytes = Uint8List.fromList(utf8.encode(lines.join('\n')));
  return _writeBytes(bytes, 'reporte_emergencias_$ymd.txt');
}

Future<ReportFileResult> _writeBytes(Uint8List bytes, String filename) async {
  final dir = await _resolveOutputDir();
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  final file = File('${dir.path}${Platform.pathSeparator}$filename');
  await file.writeAsBytes(bytes, flush: true);
  return ReportFileResult(path: file.path);
}
