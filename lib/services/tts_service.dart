import 'package:flutter_tts/flutter_tts.dart';


class TtsService {
  final FlutterTts _tts = FlutterTts();

  Future<void> speak(String text) async {
    final clean = text.trim();
    if (clean.isEmpty) return;
    try {
      await _tts.setLanguage('es-ES');
      await _tts.setSpeechRate(0.48);
      await _tts.setPitch(1.0);
      await _tts.stop();
      await _tts.speak(clean);
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  void dispose() {
    _tts.stop();
  }
}

