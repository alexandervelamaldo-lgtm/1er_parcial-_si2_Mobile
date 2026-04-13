import 'package:flutter/foundation.dart';


class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: kReleaseMode
        ? 'https://emergency-backend-ea41.onrender.com'
        : 'http://10.0.2.2:8001',
  );

  static const bool enableGoogleMaps = bool.fromEnvironment(
    'ENABLE_GOOGLE_MAPS',
    defaultValue: false,
  );

  static bool get usesEmulatorLoopback => apiBaseUrl.contains('10.0.2.2');
}
