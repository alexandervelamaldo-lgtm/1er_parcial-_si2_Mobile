import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';


Future<Directory> _resolveOutputDir() async {
  if (Platform.isAndroid) {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir != null) return dir;
    } catch (_) {}
  }
  return getApplicationDocumentsDirectory();
}


Future<String> saveTxtBytes(Uint8List bytes, String filename) async {
  final dir = await _resolveOutputDir();
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }

  String safe = filename.trim().isEmpty ? 'archivo.txt' : filename.trim();
  if (!safe.toLowerCase().endsWith('.txt')) safe = '$safe.txt';

  final file = File('${dir.path}${Platform.pathSeparator}$safe');

  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
