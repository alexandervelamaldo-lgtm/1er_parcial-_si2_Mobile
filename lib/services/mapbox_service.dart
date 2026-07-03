import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';

class MapboxRateLimiter {
  MapboxRateLimiter({required this.minInterval}) : _lastStartedAt = DateTime.fromMillisecondsSinceEpoch(0);

  final Duration minInterval;
  DateTime _lastStartedAt;
  Future<void> _chain = Future.value();

  Future<T> schedule<T>(Future<T> Function() task) {
    final next = _chain.then((_) async {
      final now = DateTime.now();
      final elapsed = now.difference(_lastStartedAt);
      final wait = minInterval - elapsed;
      if (!wait.isNegative && wait.inMilliseconds > 0) {
        await Future<void>.delayed(wait);
      }
      _lastStartedAt = DateTime.now();
      return task();
    });
    _chain = next.then((_) => null, onError: (_) => null);
    return next;
  }
}

class MapboxLruCache<T> {
  MapboxLruCache(this.maxEntries);

  final int maxEntries;
  final _map = <String, T>{};

  T? get(String key) {
    final value = _map.remove(key);
    if (value == null) return null;
    _map[key] = value;
    return value;
  }

  void set(String key, T value) {
    _map.remove(key);
    _map[key] = value;
    while (_map.length > maxEntries) {
      _map.remove(_map.keys.first);
    }
  }
}

class MapboxSearchResult {
  const MapboxSearchResult({
    required this.point,
    required this.displayName,
  });

  final LatLng point;
  final String displayName;
}

class MapboxRouteResult {
  const MapboxRouteResult({
    required this.path,
    required this.distanceKm,
    required this.durationMin,
  });

  final List<LatLng> path;
  final double distanceKm;
  final int durationMin;
}

class MapboxService {
  MapboxService({
    http.Client? client,
    MapboxRateLimiter? limiter,
  })  : _client = client ?? http.Client(),
        _limiter = limiter ?? MapboxRateLimiter(minInterval: const Duration(milliseconds: 350));

  final http.Client _client;
  final MapboxRateLimiter _limiter;

  final _reverseCache = MapboxLruCache<String>(120);
  final _searchCache = MapboxLruCache<List<MapboxSearchResult>>(60);
  final _routeCache = MapboxLruCache<MapboxRouteResult>(80);

  static const double _minSecondsPerKm = 40.0;
  static const double _maxSecondsPerKm = 180.0;

  String _formatCoordinateLabel(LatLng point) =>
      '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';

  String get accessToken {
    final token = AppConfig.mapboxAccessToken.trim();
    if (token.length < 10) {
      throw Exception(
        'Mapbox no está configurado en móvil. Ejecuta Flutter con --dart-define-from-file=.env.json '
        'o define ACCESS_TOKEN.',
      );
    }
    return token;
  }

  Future<T> _retry<T>(
    Future<T> Function() task, {
    int retries = 2,
    Duration baseDelay = const Duration(milliseconds: 500),
  }) async {
    Object? lastError;
    for (var i = 0; i <= retries; i++) {
      try {
        return await task();
      } catch (error) {
        lastError = error;
        if (i == retries) break;
        await Future<void>.delayed(baseDelay * (1 << i));
      }
    }
    throw lastError ?? Exception('Error de red');
  }

  String _revKey(LatLng point) => '${point.latitude.toStringAsFixed(5)},${point.longitude.toStringAsFixed(5)}';

  String _routeKey(LatLng from, LatLng to) =>
      '${from.latitude.toStringAsFixed(5)},${from.longitude.toStringAsFixed(5)}|'
      '${to.latitude.toStringAsFixed(5)},${to.longitude.toStringAsFixed(5)}';

  double _enforceDurationPerKm(double distanceKm, double durationSeconds) {
    if (!distanceKm.isFinite || distanceKm <= 0) {
      throw Exception('La distancia de la ruta es inválida.');
    }
    if (!durationSeconds.isFinite || durationSeconds <= 0) {
      throw Exception('La duración de la ruta es inválida.');
    }
    final secondsPerKm = durationSeconds / distanceKm;
    if (secondsPerKm < _minSecondsPerKm) {
      return distanceKm * _minSecondsPerKm;
    }
    if (secondsPerKm > _maxSecondsPerKm) {
      return distanceKm * _maxSecondsPerKm;
    }
    return durationSeconds;
  }

  Future<String> reverseGeocode(
    LatLng point, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final key = _revKey(point);
    final cached = _reverseCache.get(key);
    if (cached != null) return cached;

    final uri = Uri.parse(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/'
      '${point.longitude},${point.latitude}.json'
      '?access_token=${Uri.encodeQueryComponent(accessToken)}'
      '&language=es&limit=1&country=BO',
    );

    final name = await _limiter.schedule(() async {
      return _retry(() async {
        final response = await _client.get(
          uri,
          headers: const {'Accept': 'application/json'},
        ).timeout(timeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          return _formatCoordinateLabel(point);
        }
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final features = (data['features'] as List?) ?? const [];
        final first = features.isNotEmpty ? features.first as Map<String, dynamic> : const <String, dynamic>{};
        final placeName = (first['place_name'] as String?)?.trim() ?? '';
        return placeName.isNotEmpty ? placeName : _formatCoordinateLabel(point);
      });
    });

    _reverseCache.set(key, name);
    return name;
  }

  Future<List<MapboxSearchResult>> search(
    String query, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return const [];
    final cacheKey = normalized.toLowerCase();
    final cached = _searchCache.get(cacheKey);
    if (cached != null) return cached;

    final uri = Uri.parse(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(normalized)}.json'
      '?access_token=${Uri.encodeQueryComponent(accessToken)}'
      '&language=es&limit=6&country=BO&proximity=-63.1812,-17.7863',
    );

    final results = await _limiter.schedule(() async {
      return _retry(() async {
        final response = await _client.get(
          uri,
          headers: const {'Accept': 'application/json'},
        ).timeout(timeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception('No se pudo buscar la dirección con Mapbox.');
        }
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final features = (data['features'] as List?) ?? const [];
        return features
            .map((item) {
              if (item is! Map<String, dynamic>) return null;
              final center = item['center'];
              if (center is! List || center.length < 2) return null;
              final lng = (center[0] as num?)?.toDouble();
              final lat = (center[1] as num?)?.toDouble();
              if (lat == null || lng == null) return null;
              return MapboxSearchResult(
                point: LatLng(lat, lng),
                displayName: (item['place_name'] as String?)?.trim() ?? '',
              );
            })
            .whereType<MapboxSearchResult>()
            .toList(growable: false);
      });
    });

    _searchCache.set(cacheKey, results);
    return results;
  }

  Future<MapboxRouteResult> routeDriving(
    LatLng from,
    LatLng to, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final key = _routeKey(from, to);
    final cached = _routeCache.get(key);
    if (cached != null) return cached;

    // `driving-traffic` incorpora tráfico en tiempo real para vías
    // principales — el mismo costo que `driving` en el plan gratuito.
    // El factor horario local de Bolivia se aplica server-side a los
    // valores que persiste el backend (`ruta_eta_min`). Esta llamada
    // cliente sirve solo para el seguimiento dinámico del técnico.
    //
    // IMPORTANTE: usamos solo los params mínimos (geometries+overview).
    // Mapbox Directions devuelve 422 ("InvalidInput") de forma intermitente
    // en tramos urbanos cortos cuando se agregan alternatives/annotations/
    // steps — y al fallar caíamos a una línea recta. El set mínimo es
    // estable y devuelve la geometría vial completa.
    final uri = Uri.parse(
      'https://api.mapbox.com/directions/v5/mapbox/driving-traffic/'
      '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
      '?access_token=${Uri.encodeQueryComponent(accessToken)}'
      '&geometries=geojson&overview=full',
    );

    final result = await _retry(() async {
      final response = await _client.get(
        uri,
        headers: const {'Accept': 'application/json'},
      ).timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('No se pudo calcular la ruta con Mapbox.');
      }

      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final routes = (data['routes'] as List?) ?? const [];
      if (routes.isEmpty) {
        throw Exception('Ruta no disponible.');
      }

      final route = routes.first as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>?;
      final coordinates = (geometry?['coordinates'] as List?) ?? const [];
      final distanceM = (route['distance'] as num?)?.toDouble();
      final durationS = (route['duration'] as num?)?.toDouble();
      if (coordinates.length < 2 || distanceM == null || durationS == null) {
        throw Exception('Ruta no disponible.');
      }

      final points = coordinates
          .map((entry) {
            if (entry is! List || entry.length < 2) return null;
            final lng = (entry[0] as num?)?.toDouble();
            final lat = (entry[1] as num?)?.toDouble();
            if (lat == null || lng == null) return null;
            return LatLng(lat, lng);
          })
          .whereType<LatLng>()
          .toList(growable: false);
      if (points.length < 2) {
        throw Exception('Ruta no disponible.');
      }

      final distanceKm = double.parse((distanceM / 1000).toStringAsFixed(2));
      final controlledDurationSeconds = _enforceDurationPerKm(distanceKm, durationS);
      final output = MapboxRouteResult(
        path: points,
        distanceKm: distanceKm,
        durationMin: (controlledDurationSeconds / 60).round(),
      );
      _routeCache.set(key, output);
      return output;
    });

    return result;
  }

  void dispose() {
    _client.close();
  }
}
