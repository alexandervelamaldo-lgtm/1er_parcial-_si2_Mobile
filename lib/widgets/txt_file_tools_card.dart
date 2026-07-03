import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../screens/txt_viewer_screen.dart';


class TxtFileToolsCard extends StatefulWidget {
  const TxtFileToolsCard({super.key});

  @override
  State<TxtFileToolsCard> createState() => _TxtFileToolsCardState();
}


class _TxtFileToolsCardState extends State<TxtFileToolsCard> {
  bool _busy = false;
  String? _error;

  Future<void> _pick() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['txt'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final f = result.files.single;
      final size = f.size;
      if (size > 10 * 1024 * 1024) {
        setState(() => _error = 'El archivo excede 10MB.');
        return;
      }
      Uint8List? bytes = f.bytes;
      if (bytes == null && f.path != null) {
        bytes = await File(f.path!).readAsBytes();
      }
      if (bytes == null) {
        setState(() => _error = 'No se pudo leer el archivo.');
        return;
      }
      final name = (f.name.isNotEmpty ? f.name : 'archivo.txt');
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TxtViewerScreen(fileName: name, bytes: bytes!)),
      );
    } catch (_) {
      setState(() => _error = 'No se pudo abrir el archivo .txt.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('TXT: carga y visor', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text('Abre .txt (UTF-8 / ANSI / Latin-1), busca, copia y descarga.'),
            const SizedBox(height: 10),
            FilledButton.tonal(
              onPressed: _busy ? null : _pick,
              child: Text(_busy ? 'Abriendo…' : 'Seleccionar archivo .txt'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
            ],
          ],
        ),
      ),
    );
  }
}

