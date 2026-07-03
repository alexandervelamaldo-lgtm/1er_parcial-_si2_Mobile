import 'package:flutter/foundation.dart';


class AppConfig {
  static String get apiBaseUrl {
    const defined = String.fromEnvironment('API_BASE_URL');
    final normalized = defined.trim();
    if (normalized.isNotEmpty) return normalized;
    return kReleaseMode
        ? 'https://emergency-backend-ea41.onrender.com'
        : 'http://10.0.2.2:8000';
  }

  static String get mapboxAccessToken => const String.fromEnvironment('ACCESS_TOKEN');

  static String get mapboxStyleUri {
    const defined = String.fromEnvironment('MAPBOX_STYLE_URI');
    final normalized = defined.trim();
    return normalized.isNotEmpty ? normalized : 'mapbox://styles/mapbox/standard';
  }

  static bool get usesEmulatorLoopback => apiBaseUrl.contains('10.0.2.2');

  static bool get hasMapboxAccessToken => mapboxAccessToken.trim().length > 10;
}
