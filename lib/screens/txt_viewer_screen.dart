import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';

import '../services/text_decode.dart';
import '../services/text_file_storage.dart';


class TxtViewerScreen extends StatefulWidget {
  const TxtViewerScreen({
    super.key,
    required this.fileName,
    required this.bytes,
  });

  final String fileName;
  final Uint8List bytes;

  @override
  State<TxtViewerScreen> createState() => _TxtViewerScreenState();
}


class _TxtViewerScreenState extends State<TxtViewerScreen> {
  late final DecodedTextFile _decoded = decodeTextBytes(widget.bytes);
  late final TextEditingController _controller = TextEditingController(text: _decoded.text);
  final FocusNode _focus = FocusNode();

  double _fontSize = 14;
  String _query = '';
  int _matchIndex = -1;
  int _matchCount = 0;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  int _countMatches(String hay, String needle) {
    if (needle.isEmpty) return 0;
    var count = 0;
    var idx = 0;
    while (true) {
      final next = hay.indexOf(needle, idx);
      if (next == -1) break;
      count += 1;
      idx = next + (needle.isEmpty ? 1 : needle.length);
      if (idx >= hay.length) break;
    }
    return count;
  }

  void _findNext() {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return;
    final hay = _decoded.text.toLowerCase();
    if (_matchCount == 0) _matchCount = _countMatches(hay, q);
    final start = _controller.selection.end >= 0 ? _controller.selection.end : 0;
    var idx = hay.indexOf(q, start);
    if (idx == -1) idx = hay.indexOf(q);
    if (idx == -1) return;
    setState(() {
      _matchIndex = _countMatches(hay.substring(0, idx + 1), q) - 1;
    });
    _focus.requestFocus();
    _controller.selection = TextSelection(baseOffset: idx, extentOffset: idx + q.length);
  }

  void _findPrev() {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return;
    final hay = _decoded.text.toLowerCase();
    if (_matchCount == 0) _matchCount = _countMatches(hay, q);
    final start = (_controller.selection.start > 0 ? _controller.selection.start - 1 : 0);
    var idx = hay.lastIndexOf(q, start);
    if (idx == -1) idx = hay.lastIndexOf(q);
    if (idx == -1) return;
    setState(() {
      _matchIndex = _countMatches(hay.substring(0, idx + 1), q) - 1;
    });
    _focus.requestFocus();
    _controller.selection = TextSelection(baseOffset: idx, extentOffset: idx + q.length);
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: _decoded.text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Texto copiado.')));
  }

  Future<void> _download() async {
    final path = await saveTxtBytes(widget.bytes, widget.fileName);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Guardado: $path'),
        action: SnackBarAction(label: 'Abrir', onPressed: () => OpenFilex.open(path)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName),
        actions: [
          IconButton(onPressed: _copyAll, icon: const Icon(Icons.copy_all), tooltip: 'Copiar'),
          IconButton(onPressed: _download, icon: const Icon(Icons.download), tooltip: 'Descargar'),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(label: Text('Encoding: ${_decoded.encoding}')),
                    Chip(label: Text('Tamaño: ${(widget.bytes.length / 1024 / 1024).toStringAsFixed(2)} MB')),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          labelText: 'Buscar',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) {
                          setState(() {
                            _query = v;
                            _matchIndex = -1;
                            _matchCount = 0;
                          });
                        },
                        onSubmitted: (_) => _findNext(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(onPressed: _query.trim().isEmpty ? null : _findPrev, icon: const Icon(Icons.arrow_upward)),
                    IconButton(onPressed: _query.trim().isEmpty ? null : _findNext, icon: const Icon(Icons.arrow_downward)),
                  ],
                ),
                if (_query.trim().isNotEmpty && _matchCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Coincidencia: ${_matchIndex + 1}/$_matchCount'),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Fuente'),
                    Expanded(
                      child: Slider(
                        value: _fontSize,
                        min: 11,
                        max: 26,
                        divisions: 15,
                        label: _fontSize.toStringAsFixed(0),
                        onChanged: (v) => setState(() => _fontSize = v),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                readOnly: true,
                maxLines: null,
                expands: true,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                style: TextStyle(
                  fontSize: _fontSize,
                  fontFamily: 'monospace',
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
