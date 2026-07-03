enum VoiceReportFormat { pdf, excel, txt }

class VoiceReportCommand {
  const VoiceReportCommand({required this.format, required this.narrate});

  final VoiceReportFormat format;
  final bool narrate;
}

String _normalize(String input) {
  final lower = input.toLowerCase();
  const accents = {
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ü': 'u',
    'ñ': 'n',
  };
  final sb = StringBuffer();
  for (final ch in lower.split('')) {
    sb.write(accents[ch] ?? ch);
  }
  return sb
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  final dp = List.generate(a.length + 1, (_) => List<int>.filled(b.length + 1, 0));
  for (var i = 0; i <= a.length; i++) {
    dp[i][0] = i;
  }
  for (var j = 0; j <= b.length; j++) {
    dp[0][j] = j;
  }

  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      dp[i][j] = [
        dp[i - 1][j] + 1,
        dp[i][j - 1] + 1,
        dp[i - 1][j - 1] + cost,
      ].reduce((m, v) => v < m ? v : m);
    }
  }
  return dp[a.length][b.length];
}

bool _tokenMatchesAny(String token, List<String> candidates, {int maxDistance = 1}) {
  for (final c in candidates) {
    if (token == c) return true;
    if (_levenshtein(token, c) <= maxDistance) return true;
  }
  return false;
}

VoiceReportCommand? parseVoiceReportCommand(String transcriptRaw) {
  final transcript = _normalize(transcriptRaw);
  if (transcript.isEmpty) return null;

  final tokens = transcript.split(' ').where((t) => t.isNotEmpty).toList(growable: false);

  const reportKeywords = ['reporte', 'informe'];
  const todayKeywords = ['hoy', 'diario', 'actual'];
  const pdfKeywords = ['pdf'];
  const excelKeywords = ['excel', 'exel', 'xlsx'];
  const txtKeywords = ['txt', 'texto', 'text'];
  const voiceKeywords = ['voz', 'audio', 'narrar', 'leer'];

  final hasReport = transcript.contains('reporte') ||
      transcript.contains('informe') ||
      tokens.any((t) => _tokenMatchesAny(t, reportKeywords));

  final hasToday = transcript.contains('hoy') ||
      transcript.contains('de hoy') ||
      transcript.contains('del dia') ||
      tokens.any((t) => _tokenMatchesAny(t, todayKeywords));

  final wantsPdf = tokens.any((t) => _tokenMatchesAny(t, pdfKeywords));
  final wantsExcel = tokens.any((t) => _tokenMatchesAny(t, excelKeywords));
  final wantsTxt = tokens.any((t) => _tokenMatchesAny(t, txtKeywords)) || transcript.contains(' txt') || transcript.contains(' texto');
  final wantsNarration =
      tokens.any((t) => _tokenMatchesAny(t, voiceKeywords)) || transcript.contains(' con voz') || transcript.contains(' narrar');

  if (!hasReport || !hasToday) return null;
  if (wantsPdf) return VoiceReportCommand(format: VoiceReportFormat.pdf, narrate: wantsNarration);
  if (wantsExcel) return VoiceReportCommand(format: VoiceReportFormat.excel, narrate: wantsNarration);
  if (wantsTxt) return VoiceReportCommand(format: VoiceReportFormat.txt, narrate: wantsNarration);
  return null;
}
