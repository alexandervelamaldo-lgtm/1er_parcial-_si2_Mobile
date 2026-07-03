import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/profile_data.dart';
import '../services/api_service.dart';


class SessionProvider extends ChangeNotifier {
  SessionProvider(this._apiService);
  static const String _debugServerUrl = 'http://192.168.0.23:7777/event';
  static const String _debugSessionId = 'cloud-push-delivery';

  final ApiService _apiService;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  StreamSubscription<String>? _pushTokenRefreshSub;

  String? _token;
  ProfileData? _profile;
  bool _loading = false;
  bool _pushEnabled = false;
  String _pushPermissionState = 'unknown';
  String? _pendingRoute;
  /// Tenant key (organization the user belongs to). Persisted in secure
  /// storage so it survives app restarts — without it every API call after
  /// a cold-launch would hit the `default` tenant and break isolation.
  String _tenant = 'default';

  String? get token => _token;
  ProfileData? get profile => _profile;
  bool get isAuthenticated => _token != null && _token!.isNotEmpty;
  bool get loading => _loading;
  bool get pushEnabled => _pushEnabled;
  String get pushPermissionState => _pushPermissionState;
  String? get pendingRoute => _pendingRoute;
  String get tenant => _tenant;

  // #region debug-point E:mobile-token-report
  Future<void> _debugReport(
    String hypothesisId,
    String location,
    String msg,
    Map<String, dynamic> data,
  ) async {
    try {
      final client = HttpClient();
      final request = await client.postUrl(Uri.parse(_debugServerUrl));
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.write(jsonEncode({
        'sessionId': _debugSessionId,
        'runId': 'pre-fix',
        'hypothesisId': hypothesisId,
        'location': location,
        'msg': '[DEBUG] $msg',
        'data': data,
        'ts': DateTime.now().millisecondsSinceEpoch,
      }));
      await request.close();
      client.close(force: true);
    } catch (_) {}
  }
  // #endregion

  Future<void> restaurarSesion() async {
    _token = await _storage.read(key: 'token');
    _pendingRoute = await _storage.read(key: 'pending_route');
    final storedPushEnabled = await _storage.read(key: 'push_enabled');
    _pushEnabled = storedPushEnabled != '0';
    _pushPermissionState = (await _storage.read(key: 'push_permission_state')) ?? 'unknown';
    final storedTenant = (await _storage.read(key: 'tenant'))?.trim();
    _tenant = (storedTenant == null || storedTenant.isEmpty) ? 'default' : storedTenant;
    // Push the restored tenant into the ApiService BEFORE any API call so
    // the perfil-actual lookup below targets the right tenant database.
    _apiService.setTenant(_tenant);
    if (isAuthenticated) {
      try {
        _profile = await _apiService.obtenerPerfilActual(_token!);
        // Pre-cachea catálogos (tipos de incidente) para que el formulario de
        // asistencia funcione offline aunque se abra por primera vez sin red.
        unawaited(_apiService.precargarCatalogosOffline(_token!));
        await _bootstrapPushRegistration(
          requestPermissionIfNeeded: storedPushEnabled == null,
        );
      } on SessionExpiredException {
        // Token expirado/inválido al arrancar: lo limpiamos para que el árbol
        // muestre el login en vez de un "shell autenticado" zombie que fallaría
        // con 401 en cada llamada (mismo bug que la web con hasToken()).
        await logout();
      } catch (_) {
        _profile = null;
      }
    }
    notifyListeners();
  }

  Future<void> login(String email, String password, {String? tenant}) async {
    _loading = true;
    notifyListeners();
    try {
      // El parámetro `tenant` queda como override opcional para casos
      // raros (ej. el operador necesita forzar una organización). En el
      // flujo normal no se pasa y el backend lo detecta del email.
      final trimmedTenant = (tenant ?? '').trim();
      final result = await _apiService.login(
        email: email,
        password: password,
        tenant: trimmedTenant.isEmpty ? null : trimmedTenant,
      );
      _token = result.accessToken;
      // Persistimos el tenant que el backend detectó (no el que
      // adivinó el cliente). Si el backend no lo devolvió por algún
      // motivo, conservamos el anterior o caemos a 'default'.
      _tenant = result.tenantKey ?? (trimmedTenant.isEmpty ? _tenant : trimmedTenant);
      if (_tenant.isEmpty) _tenant = 'default';
      _apiService.setTenant(_tenant);
      await _storage.write(key: 'token', value: _token);
      await _storage.write(key: 'tenant', value: _tenant);
      final storedPushEnabled = await _storage.read(key: 'push_enabled');
      _pushEnabled = storedPushEnabled != '0';
      _profile = await _apiService.obtenerPerfilActual(_token!);
      // Pre-cachea catálogos (tipos de incidente) para que el formulario de
      // asistencia funcione offline aunque se abra por primera vez sin red.
      unawaited(_apiService.precargarCatalogosOffline(_token!));
      await _bootstrapPushRegistration(
        requestPermissionIfNeeded: storedPushEnabled == null,
      );
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _pushTokenRefreshSub?.cancel();
    _pushTokenRefreshSub = null;
    _token = null;
    _profile = null;
    // Keep the tenant key — most users always log back into the same org,
    // so we save them re-typing it. They can change it from the login form.
    await _storage.delete(key: 'token');
    notifyListeners();
  }

  Future<void> setPendingRoute(String route) async {
    _pendingRoute = route;
    await _storage.write(key: 'pending_route', value: route);
    notifyListeners();
  }

  Future<void> clearPendingRoute() async {
    _pendingRoute = null;
    await _storage.delete(key: 'pending_route');
    notifyListeners();
  }

  Future<void> enablePush() async {
    if (_token == null) {
      return;
    }
    try {
      _pushEnabled = true;
      await _storage.write(key: 'push_enabled', value: '1');
      await _bootstrapPushRegistration(requestPermissionIfNeeded: true);
    } finally {
      notifyListeners();
    }
  }

  Future<void> disablePush() async {
    if (_token == null) {
      return;
    }
    _pushEnabled = false;
    await _storage.write(key: 'push_enabled', value: '0');
    await _pushTokenRefreshSub?.cancel();
    _pushTokenRefreshSub = null;
    try {
      final deviceToken = await FirebaseMessaging.instance.getToken();
      await FirebaseMessaging.instance.deleteToken();
      await _apiService.eliminarDeviceToken(token: _token!, deviceToken: deviceToken);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _bootstrapPushRegistration({
    required bool requestPermissionIfNeeded,
  }) async {
    if (_token == null || !_pushEnabled) {
      return;
    }
    await _ensurePushTokenRefreshListener();
    await _syncPushTokenRegistration(
      requestPermissionIfNeeded: requestPermissionIfNeeded,
    );
  }

  Future<void> _syncPushTokenRegistration({
    required bool requestPermissionIfNeeded,
  }) async {
    if (_token == null) {
      return;
    }
    if (!_pushEnabled) {
      return;
    }
    try {
      final settings = requestPermissionIfNeeded
          ? await _requestPushPermission()
          : await FirebaseMessaging.instance.getNotificationSettings();
      _pushPermissionState = settings.authorizationStatus.name;
      await _storage.write(key: 'push_permission_state', value: _pushPermissionState);
      final status = settings.authorizationStatus;
      final isAuthorized =
          status == AuthorizationStatus.authorized ||
          status == AuthorizationStatus.provisional;
      if (!isAuthorized) {
        if (status == AuthorizationStatus.denied) {
          _pushEnabled = false;
          await _storage.write(key: 'push_enabled', value: '0');
        }
        return;
      }
      final deviceToken = await FirebaseMessaging.instance.getToken();
      if (deviceToken == null || deviceToken.isEmpty) {
        // #region debug-point E:mobile-token-missing
        await _debugReport(
          'E',
          'mobile/lib/providers/session_provider.dart:_syncPushTokenRegistration',
          'push token missing during registration attempt',
          {
            'tenant': _tenant,
            'authorized_status': status.name,
            'request_permission_if_needed': requestPermissionIfNeeded,
            'push_enabled': _pushEnabled,
            'has_auth_token': _token != null,
          },
        );
        // #endregion
        return;
      }
      // #region debug-point E:mobile-token-registering
      await _debugReport(
        'E',
        'mobile/lib/providers/session_provider.dart:_syncPushTokenRegistration',
        'registering mobile device token against backend',
        {
          'tenant': _tenant,
          'authorized_status': status.name,
          'request_permission_if_needed': requestPermissionIfNeeded,
          'push_enabled': _pushEnabled,
          'token_suffix': deviceToken.substring(deviceToken.length > 12 ? deviceToken.length - 12 : 0),
        },
      );
      // #endregion
      _pushEnabled = true;
      await _storage.write(key: 'push_enabled', value: '1');
      await _apiService.registrarDeviceToken(
        token: _token!,
        deviceToken: deviceToken,
      );
      // #region debug-point E:mobile-token-registered
      await _debugReport(
        'E',
        'mobile/lib/providers/session_provider.dart:_syncPushTokenRegistration',
        'mobile device token registration completed',
        {
          'tenant': _tenant,
          'token_suffix': deviceToken.substring(deviceToken.length > 12 ? deviceToken.length - 12 : 0),
        },
      );
      // #endregion
    } catch (_) {
      return;
    }
  }

  Future<NotificationSettings> _requestPushPermission() async {
    if (Platform.isAndroid) {
      await Permission.notification.request();
    }
    return FirebaseMessaging.instance.requestPermission();
  }

  Future<void> _ensurePushTokenRefreshListener() async {
    if (_pushTokenRefreshSub != null) {
      return;
    }
    _pushTokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((
      deviceToken,
    ) async {
      if (_token == null || !_pushEnabled || deviceToken.trim().isEmpty) {
        return;
      }
      try {
        // #region debug-point E:mobile-token-refresh
        await _debugReport(
          'E',
          'mobile/lib/providers/session_provider.dart:onTokenRefresh',
          'firebase refreshed device token',
          {
            'tenant': _tenant,
            'push_enabled': _pushEnabled,
            'token_suffix': deviceToken.substring(deviceToken.length > 12 ? deviceToken.length - 12 : 0),
          },
        );
        // #endregion
        await _apiService.registrarDeviceToken(
          token: _token!,
          deviceToken: deviceToken,
        );
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _pushTokenRefreshSub?.cancel();
    super.dispose();
  }
}
