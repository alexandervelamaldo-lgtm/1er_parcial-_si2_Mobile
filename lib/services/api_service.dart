import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/app_config.dart';
import '../models/notification_item.dart';
import '../models/notification_preferences.dart';
import '../models/profile_data.dart';
import '../models/categoria_taller.dart';
import '../models/solicitud.dart';
import '../models/taller_con_presupuesto.dart';
import '../models/taller_mapa.dart';
import '../models/tecnico_cercano.dart';
import '../models/vehiculo.dart';


/// Lanzada cuando el backend responde 401 (token ausente, expirado o inválido
/// para el tenant). Las pantallas la atrapan para cerrar sesión y mandar al
/// login en vez de mostrar un error genérico — es el equivalente móvil del
/// interceptor 401→/login de la web. `toString()` devuelve un texto amigable
/// para los call sites que solo muestran `e.toString()`.
class SessionExpiredException implements Exception {
  const SessionExpiredException();

  @override
  String toString() => 'Tu sesión expiró. Inicia sesión nuevamente.';
}


class TipoIncidenteOption {
  const TipoIncidenteOption({
    required this.id,
    required this.nombre,
    required this.descripcion,
  });

  final int id;
  final String nombre;
  final String descripcion;

  factory TipoIncidenteOption.fromJson(Map<String, dynamic> json) {
    return TipoIncidenteOption(
      id: json['id'] as int,
      nombre: json['nombre'] as String? ?? 'Incidente',
      descripcion: json['descripcion'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'descripcion': descripcion,
      };
}


/// Resultado de crear una orden PayPal en el backend.
class PayPalOrdenResult {
  const PayPalOrdenResult({
    required this.orderId,
    required this.approveUrl,
    required this.solicitudId,
    required this.monto,
    required this.moneda,
  });

  final String orderId;
  final String approveUrl;
  final int solicitudId;
  final double monto;
  final String moneda;

  factory PayPalOrdenResult.fromJson(Map<String, dynamic> json) {
    return PayPalOrdenResult(
      orderId: json['order_id'] as String,
      approveUrl: json['approve_url'] as String,
      solicitudId: json['solicitud_id'] as int,
      monto: (json['monto'] as num).toDouble(),
      moneda: json['moneda'] as String? ?? 'USD',
    );
  }
}


/// Resultado del `/auth/login`. Devolvemos el token + el tenant que el
/// backend detectó iterando organizaciones (cuando el cliente no fuerza
/// uno explícito). Esto permite que el login NO pregunte la organización
/// al usuario — el sistema la deduce del email.
class LoginResult {
  const LoginResult({required this.accessToken, this.tenantKey});
  final String accessToken;
  final String? tenantKey;
}


class ApiService {
  static const Duration _cloudLoginTimeout = Duration(seconds: 45);
  static const Duration _cloudRequestTimeout = Duration(seconds: 45);

  Future<LoginResult> login({
    required String email,
    required String password,
    String? tenant,
  }) async {
    // Auto-detección de tenant: el backend recorre todos los tenants
    // configurados y devuelve `tenant_key` del que matcheó. Solo
    // pasamos X-Tenant si el caller fuerza uno específico — en ese
    // caso el backend respeta el override.
    if (tenant != null && tenant.isNotEmpty) setTenant(tenant);
    final headers = <String, String>{
      'Content-Type': 'application/json',
      // Identificamos la plataforma para que el backend pueda aplicar
      // reglas específicas (ej. rechazar super-admins en mobile).
      'X-Client-Platform': 'mobile',
    };
    if (tenant != null && tenant.isNotEmpty && tenant != 'default') {
      headers['X-Tenant'] = tenant;
    }
    http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/auth/login'),
            headers: headers,
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(_cloudLoginTimeout);
    } on SocketException {
      throw Exception(
        'No se pudo conectar con el backend móvil. Si usas emulador Android usa ${AppConfig.apiBaseUrl}. '
        'Si usas celular físico recompila con --dart-define=API_BASE_URL=http://TU_IP_LOCAL:8000',
      );
    } on TimeoutException {
      throw Exception(
        'El backend tardó demasiado en responder al iniciar sesión. '
        'Si Render estaba en reposo, espera unos segundos e intenta otra vez.',
      );
    }

    if (response.statusCode >= 400) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final detail = body['detail'];
      if (detail is String && detail.isNotEmpty) {
        throw Exception(detail);
      }
      throw Exception('No fue posible iniciar sesión');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return LoginResult(
      accessToken: data['access_token'] as String,
      tenantKey: data['tenant_key'] as String?,
    );
  }

  Future<ProfileData> obtenerPerfilActual(String token) async {
    final response = await http
        .get(
          Uri.parse('${AppConfig.apiBaseUrl}/auth/me'),
          headers: _headers(token),
        )
        .timeout(_cloudRequestTimeout);
    _ensureSuccess(response, 'No se pudo cargar el perfil');
    return ProfileData.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<Vehiculo>> obtenerVehiculos(String token) async {
    final response = await http
        .get(
          Uri.parse('${AppConfig.apiBaseUrl}/vehiculos'),
          headers: _headers(token),
        )
        .timeout(_cloudRequestTimeout);
    final data = jsonDecode(response.body) as List<dynamic>;
    return data.map((item) => Vehiculo.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<List<Solicitud>> obtenerSolicitudes(String token) async {
    final response = await http
        .get(
          Uri.parse('${AppConfig.apiBaseUrl}/solicitudes'),
          headers: _headers(token),
        )
        .timeout(_cloudRequestTimeout);
    _ensureSuccess(response, 'No se pudieron cargar las solicitudes');
    final data = jsonDecode(response.body) as List<dynamic>;
    return data.map((item) => Solicitud.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<SolicitudDetalle> obtenerDetalleSolicitud(String token, int solicitudId) async {
    final response = await http
        .get(
          Uri.parse('${AppConfig.apiBaseUrl}/solicitudes/$solicitudId/detalle'),
          headers: _headers(token),
        )
        .timeout(_cloudRequestTimeout);
    _ensureSuccess(response, 'No se pudo cargar el detalle de la solicitud');
    return SolicitudDetalle.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<SolicitudSeguimiento> obtenerSeguimientoSolicitud(String token, int solicitudId) async {
    final response = await http
        .get(
          Uri.parse('${AppConfig.apiBaseUrl}/solicitudes/$solicitudId/seguimiento'),
          headers: _headers(token),
        )
        .timeout(_cloudRequestTimeout);
    _ensureSuccess(response, 'No se pudo cargar el seguimiento');
    return SolicitudSeguimiento.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<SolicitudCandidatos> obtenerCandidatosSolicitud(String token, int solicitudId) async {
    final response = await http
        .get(
          Uri.parse('${AppConfig.apiBaseUrl}/solicitudes/$solicitudId/candidatos'),
          headers: _headers(token),
        )
        .timeout(_cloudRequestTimeout);
    _ensureSuccess(response, 'No se pudieron cargar los candidatos');
    return SolicitudCandidatos.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<NotificationItem>> obtenerNotificaciones(String token) async {
    final response = await http
        .get(
          Uri.parse('${AppConfig.apiBaseUrl}/notificaciones'),
          headers: _headers(token),
        )
        .timeout(_cloudRequestTimeout);
    _ensureSuccess(response, 'No se pudieron cargar las notificaciones');
    final data = jsonDecode(response.body) as List<dynamic>;
    return data.map((item) => NotificationItem.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<void> marcarNotificacionLeida(String token, int notificacionId) async {
    final response = await http.put(
      Uri.parse('${AppConfig.apiBaseUrl}/notificaciones/$notificacionId/leida'),
      headers: _headers(token),
    );
    _ensureSuccess(response, 'No se pudo actualizar la notificación');
  }

  Future<List<TecnicoCercano>> obtenerTecnicosCercanos(
    String token, {
    required double latitud,
    required double longitud,
  }) async {
    final response = await http.get(
      Uri.parse('${AppConfig.apiBaseUrl}/mapa/tecnicos-cercanos?lat=$latitud&lon=$longitud'),
      headers: _headers(token),
    );
    _ensureSuccess(response, 'No se pudieron cargar los talleres cercanos');
    final data = jsonDecode(response.body) as List<dynamic>;
    return data.map((item) => TecnicoCercano.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<List<TipoIncidenteOption>> obtenerTiposIncidente(String token) async {
    try {
      final response = await http
          .get(
            Uri.parse('${AppConfig.apiBaseUrl}/solicitudes/tipos-incidente'),
            headers: _headers(token),
          )
          .timeout(const Duration(seconds: 15));
      _ensureSuccess(response, 'No se pudieron cargar los tipos de incidente');
      final data = jsonDecode(response.body) as List<dynamic>;
      final tipos = data
          .map((item) => TipoIncidenteOption.fromJson(item as Map<String, dynamic>))
          .toList();
      // Cacheamos el catálogo para que el formulario de emergencia se pueda
      // llenar SIN conexión. Es justo lo que destraba el modo offline: sin
      // tipos de incidente el usuario no puede elegir y la validación lo frena.
      await _cacheTiposIncidente(tipos);
      return tipos;
    } on SessionExpiredException {
      // Un 401 debe propagarse (no lo enmascaramos con el cache) para que la
      // pantalla cierre sesión y mande al login.
      rethrow;
    } on SocketException {
      return _tiposIncidenteOfflineFallback();
    } on TimeoutException {
      return _tiposIncidenteOfflineFallback();
    } on http.ClientException {
      // Android lanza ClientException("...Network is unreachable...") cuando
      // no hay red — exactamente el caso offline que queremos cubrir.
      return _tiposIncidenteOfflineFallback();
    }
  }

  /// Devuelve los tipos de incidente para el modo offline.
  ///
  /// Orden de preferencia:
  ///   1. Cache de la última carga online (refleja EXACTO lo del tenant).
  ///   2. Catálogo por defecto embebido — los mismos 5 tipos que
  ///      `create_tenant.py` siembra en TODA organización, en el mismo orden,
  ///      por lo que sus IDs (1..5) son válidos en cualquier tenant. Esto
  ///      destraba el caso límite que reportó el usuario: el formulario pedía
  ///      "tipo de incidente" y no dejaba avanzar offline cuando el pre-cacheo
  ///      nunca llegó a correr (instalación nueva / sesión restaurada sin red).
  ///
  /// Nunca lanza: el formulario de emergencia SIEMPRE tiene tipos para elegir.
  Future<List<TipoIncidenteOption>> _tiposIncidenteOfflineFallback() async {
    final cached = await _leerTiposIncidenteCache();
    if (cached.isNotEmpty) {
      return cached;
    }
    return _defaultTiposIncidente();
  }

  /// Catálogo semilla de tipos de incidente, idéntico (nombre + orden, por
  /// ende ID auto-incremental) al de `backend/app/scripts/create_tenant.py`.
  /// IMPORTANTE: mantener en sync con ese seed — si cambian los tipos
  /// sembrados, actualizar esta lista para que las emergencias creadas 100%
  /// offline sincronicen con un `tipo_incidente_id` válido en el backend.
  List<TipoIncidenteOption> _defaultTiposIncidente() => const [
        TipoIncidenteOption(id: 1, nombre: 'Choque', descripcion: 'Colisión vehicular'),
        TipoIncidenteOption(id: 2, nombre: 'Falla mecánica', descripcion: 'Avería mecánica en ruta'),
        TipoIncidenteOption(id: 3, nombre: 'Batería', descripcion: 'Vehículo no arranca / batería descargada'),
        TipoIncidenteOption(id: 4, nombre: 'Llanta ponchada', descripcion: 'Neumático pinchado'),
        TipoIncidenteOption(id: 5, nombre: 'Combustible', descripcion: 'Sin combustible'),
      ];

  String _tiposIncidenteCacheKey() => 'tipos_incidente_cache_$_currentTenant';

  Future<void> _cacheTiposIncidente(List<TipoIncidenteOption> tipos) async {
    try {
      final raw = jsonEncode(tipos.map((t) => t.toJson()).toList());
      await _storage.write(key: _tiposIncidenteCacheKey(), value: raw);
    } catch (_) {
      // El cacheo es best-effort: si falla, la próxima carga online reintenta.
    }
  }

  Future<List<TipoIncidenteOption>> _leerTiposIncidenteCache() async {
    try {
      final raw = await _storage.read(key: _tiposIncidenteCacheKey());
      if (raw == null || raw.isEmpty) {
        return const [];
      }
      final data = jsonDecode(raw) as List<dynamic>;
      return data
          .map((item) => TipoIncidenteOption.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Best-effort: descarga y cachea los catálogos necesarios para crear
  /// emergencias en modo offline (por ahora, los tipos de incidente).
  ///
  /// Se invoca tras el login / restauración de sesión, mientras todavía hay
  /// conexión, para que el formulario "Nueva asistencia" tenga datos aunque
  /// el usuario lo abra por primera vez ya sin internet. Nunca lanza: si no
  /// hay red, el cache se rellenará en la próxima carga online.
  Future<void> precargarCatalogosOffline(String token) async {
    try {
      await obtenerTiposIncidente(token);
    } catch (_) {
      // Sin conexión o error transitorio: se reintentará online más adelante.
    }
  }

  Future<int> crearSolicitud({
    required String token,
    required int clienteId,
    required int vehiculoId,
    required int tipoIncidenteId,
    required String descripcion,
    required double latitud,
    required double longitud,
    required double latitudCliente,
    required double longitudCliente,
    required bool esCarretera,
    // Nivel de riesgo ahora es opcional — el backend lo calcula con IA.
    // Si se pasa, se trata como hint suave (el server tiene la palabra final).
    int? nivelRiesgo,
    String? danosDescripcion,
    DateTime? fechaIncidente,
    String? ubicacionTexto,
    String? categoriaDano,
    int? tallerId,
    double? presupuestoAceptado,
  }) async {
    late http.Response response;
    final body = <String, dynamic>{
      'cliente_id': clienteId,
      'vehiculo_id': vehiculoId,
      'taller_id': tallerId,
      'tipo_incidente_id': tipoIncidenteId,
      'latitud_incidente': latitud,
      'longitud_incidente': longitud,
      'latitud_cliente': latitudCliente,
      'longitud_cliente': longitudCliente,
      'descripcion': descripcion,
      'danos_descripcion': danosDescripcion,
      'fecha_incidente': fechaIncidente?.toIso8601String(),
      'ubicacion_texto': ubicacionTexto,
      'categoria_dano': categoriaDano,
      'es_carretera': esCarretera,
      'condicion_vehiculo': 'Operativo con limitaciones',
      if (nivelRiesgo != null) 'nivel_riesgo': nivelRiesgo,
    };
    if (presupuestoAceptado != null) {
      body['presupuesto_aceptado'] = presupuestoAceptado;
    }
    try {
      response = await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/solicitudes'),
            headers: _headers(token),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
    } on SocketException {
      throw Exception(
        'No se pudo conectar con el backend móvil. Si usas emulador mantén API_BASE_URL en 10.0.2.2. '
        'Si usas celular físico recompila con --dart-define=API_BASE_URL=http://TU_IP_LOCAL:8000',
      );
    } on TimeoutException {
      throw Exception('El backend tardó demasiado en responder al crear la solicitud');
    }

    _ensureSuccess(response, 'No se pudo crear la solicitud');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final tenantKey = (data['tenant_key'] as String?)?.trim();
    if (tenantKey != null && tenantKey.isNotEmpty) {
      // Algunas solicitudes se enrutan al tenant del taller (no siempre al
      // tenant de login del cliente). Cambiamos el contexto enseguida para
      // que la siguiente pantalla consulte la misma solicitud en el tenant
      // correcto y no choque con validaciones cruzadas.
      setTenant(tenantKey);
    }
    return data['id'] as int;
  }

  Future<List<CategoriaTaller>> obtenerCategoriasTaller(String token) async {
    final response = await http
        .get(
          Uri.parse('${AppConfig.apiBaseUrl}/talleres/categorias'),
          headers: _headers(token),
        )
        .timeout(const Duration(seconds: 15));
    _ensureSuccess(response, 'No se pudieron cargar las categorías de talleres');
    final data = jsonDecode(response.body) as List<dynamic>;
    return data.map((it) => CategoriaTaller.fromJson(it as Map<String, dynamic>)).toList();
  }

  Future<List<TallerMapa>> obtenerTalleresMapa(
    String token, {
    int? categoriaId,
    String? danoCategoria,
    String? marcaVehiculo,
    required double lat,
    required double lon,
    double radioKm = 25.0,
  }) async {
    final query = <String, String>{
      'lat': lat.toString(),
      'lon': lon.toString(),
      'radio': radioKm.toString(),
    };
    if (categoriaId != null) query['categoria_id'] = categoriaId.toString();
    if (danoCategoria != null && danoCategoria.trim().isNotEmpty) {
      query['dano_categoria'] = danoCategoria.trim();
    }
    if (marcaVehiculo != null && marcaVehiculo.trim().isNotEmpty) {
      query['marca'] = marcaVehiculo.trim();
    }
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/talleres/mapa').replace(queryParameters: query);
    final response = await http.get(uri, headers: _headers(token)).timeout(const Duration(seconds: 20));
    _ensureSuccess(response, 'No se pudieron cargar los talleres');
    final data = jsonDecode(response.body) as List<dynamic>;
    return data.map((it) => TallerMapa.fromJson(it as Map<String, dynamic>)).toList();
  }

  /// Devuelve los talleres candidatos para una solicitud existente con su
  /// presupuesto ya calculado por el backend (descuento marca, ETA Mapbox,
  /// score de recomendación). Es la fuente del flujo cliente↔taller-directo.
  /// Endpoint: `GET /solicitudes/{id}/talleres-con-presupuesto`.
  Future<TalleresConPresupuestoResponse> obtenerTalleresConPresupuesto(
    String token, {
    required int solicitudId,
    double radioKm = 25.0,
    int limite = 10,
    bool refresh = false,
  }) async {
    final query = <String, String>{
      'radio_km': radioKm.toString(),
      'limite':   limite.toString(),
      if (refresh) 'refresh': 'true',
    };
    final uri = Uri.parse(
      '${AppConfig.apiBaseUrl}/solicitudes/$solicitudId/talleres-con-presupuesto',
    ).replace(queryParameters: query);
    final response = await http
        .get(uri, headers: _headers(token))
        .timeout(const Duration(seconds: 30));
    _ensureSuccess(response, 'No se pudieron cargar los talleres con presupuesto');
    return TalleresConPresupuestoResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// El taller acepta o rechaza una propuesta del cliente. Es la otra mitad
  /// del flujo cliente↔taller-directo: cuando el cliente eligió a este taller
  /// (estado PROPUESTA_TALLER), el taller debe responder.
  ///
  /// - `aceptada=true`  → ASIGNADA (el cliente recibe push "Taller aceptó")
  /// - `aceptada=false` → RECHAZADA_TALLER (cliente debe re-elegir)
  ///
  /// La `observacion` es obligatoria (≥3 chars) — el backend la persiste en
  /// el historial para auditoría.
  Future<void> responderPropuestaTaller(
    String token, {
    required int solicitudId,
    required bool aceptada,
    required String observacion,
  }) async {
    final response = await http
        .put(
          Uri.parse('${AppConfig.apiBaseUrl}/solicitudes/$solicitudId/respuesta-taller'),
          headers: _headers(token),
          body: jsonEncode({
            'aceptada': aceptada,
            'observacion': observacion,
          }),
        )
        .timeout(const Duration(seconds: 20));
    _ensureSuccess(response, 'No se pudo enviar tu respuesta al cliente');
  }

  Future<void> seleccionarTallerSolicitud(
    String token, {
    required int solicitudId,
    required int tallerId,
    required double origenLat,
    required double origenLon,
    double? presupuestoAceptado,
  }) async {
    final response = await http
        .put(
          Uri.parse('${AppConfig.apiBaseUrl}/solicitudes/$solicitudId/seleccionar-taller'),
          headers: _headers(token),
          body: jsonEncode({
            'taller_id': tallerId,
            'origen_lat': origenLat,
            'origen_lon': origenLon,
            'presupuesto_aceptado': presupuestoAceptado,
          }),
        )
        .timeout(const Duration(seconds: 20));
    _ensureSuccess(response, 'No se pudo registrar el taller seleccionado');
  }

  Future<void> subirEvidenciaTexto({
    required String token,
    required int solicitudId,
    required String contenido,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${AppConfig.apiBaseUrl}/solicitudes/$solicitudId/evidencias/texto'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.fields['contenido_texto'] = contenido;
    final response = await http.Response.fromStream(await request.send());
    _ensureSuccess(response, 'No se pudo enviar la evidencia textual');
  }

  Future<void> subirEvidenciaArchivo({
    required String token,
    required int solicitudId,
    required String filePath,
    int maxReintentos = 2,
  }) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw Exception('No se encontró el archivo seleccionado');
    }
    final sizeBytes = await file.length();
    if (sizeBytes > 10 * 1024 * 1024) {
      throw Exception('El archivo supera el máximo de 10 MB');
    }
    Object? lastError;
    for (var intento = 0; intento < maxReintentos; intento++) {
      try {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('${AppConfig.apiBaseUrl}/solicitudes/$solicitudId/evidencias/archivo'),
        );
        request.headers['Authorization'] = 'Bearer $token';
        request.files.add(
          await http.MultipartFile.fromPath(
            'archivo',
            file.path,
            contentType: _resolveMediaType(file.path),
          ),
        );
        final response = await http.Response.fromStream(await request.send());
        _ensureSuccess(response, 'No se pudo enviar la evidencia');
        return;
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError ?? Exception('No se pudo enviar la evidencia');
  }

  Future<void> pagarSolicitud({
    required String token,
    required int solicitudId,
    required double? montoTotal,
    required String metodoPago,
    bool confirmarPago = true,
    String? referenciaExterna,
    String? observacion,
  }) async {
    final response = await http.post(
      Uri.parse('${AppConfig.apiBaseUrl}/solicitudes/$solicitudId/pago'),
      headers: _headers(token),
      body: jsonEncode({
        'monto_total': montoTotal,
        'metodo_pago': metodoPago,
        'confirmar_pago': confirmarPago,
        'referencia_externa': referenciaExterna,
        'observacion': observacion,
      }),
    );
    _ensureSuccess(response, 'No se pudo registrar el pago');
  }

  String obtenerFacturaUrl({
    required String token,
    required int solicitudId,
  }) {
    final encodedToken = Uri.encodeQueryComponent(token);
    return '${AppConfig.apiBaseUrl}/solicitudes/$solicitudId/factura.pdf?access_token=$encodedToken';
  }

  Future<Uint8List> descargarFacturaPdf({
    required String token,
    required int solicitudId,
  }) async {
    final response = await http.get(
      Uri.parse('${AppConfig.apiBaseUrl}/solicitudes/$solicitudId/factura.pdf'),
      headers: {
        ..._headers(token),
        'Accept': 'application/pdf',
      },
    );
    _ensureSuccess(response, 'No se pudo descargar la factura');
    return response.bodyBytes;
  }

  Future<void> crearDisputa({
    required String token,
    required int solicitudId,
    required String motivo,
    required String detalle,
  }) async {
    final response = await http.post(
      Uri.parse('${AppConfig.apiBaseUrl}/solicitudes/$solicitudId/disputas'),
      headers: _headers(token),
      body: jsonEncode({
        'motivo': motivo,
        'detalle': detalle,
      }),
    );
    _ensureSuccess(response, 'No se pudo registrar la disputa');
  }

  Future<void> responderPropuestaCliente({
    required String token,
    required int solicitudId,
    required bool aprobada,
    required String observacion,
  }) async {
    final response = await http.put(
      Uri.parse('${AppConfig.apiBaseUrl}/solicitudes/$solicitudId/respuesta-cliente'),
      headers: _headers(token),
      body: jsonEncode({
        'aprobada': aprobada,
        'observacion': observacion,
      }),
    );
    _ensureSuccess(response, 'No se pudo registrar la respuesta del cliente');
  }

  Future<void> registrarDeviceToken({
    required String token,
    required String deviceToken,
    String plataforma = 'mobile',
  }) async {
    final response = await http.post(
      Uri.parse('${AppConfig.apiBaseUrl}/notificaciones/device-token'),
      headers: _headers(token),
      body: jsonEncode({
        'token': deviceToken,
        'plataforma': plataforma,
      }),
    );
    _ensureSuccess(response, 'No se pudo registrar el token del dispositivo');
  }

  Future<void> eliminarDeviceToken({
    required String token,
    String? deviceToken,
  }) async {
    final uri = deviceToken == null || deviceToken.isEmpty
        ? Uri.parse('${AppConfig.apiBaseUrl}/notificaciones/device-token')
        : Uri.parse('${AppConfig.apiBaseUrl}/notificaciones/device-token?token=${Uri.encodeQueryComponent(deviceToken)}');
    final response = await http.delete(uri, headers: _headers(token));
    _ensureSuccess(response, 'No se pudo dar de baja el dispositivo');
  }

  Future<NotificationPreferences> obtenerPreferenciasNotificaciones(String token) async {
    final response = await http.get(
      Uri.parse('${AppConfig.apiBaseUrl}/notificaciones/preferencias'),
      headers: _headers(token),
    );
    _ensureSuccess(response, 'No se pudieron cargar las preferencias');
    return NotificationPreferences.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<NotificationPreferences> actualizarPreferenciasNotificaciones(
    String token, {
    bool? disabledAll,
    Map<String, bool>? disabledTypes,
  }) async {
    final body = <String, dynamic>{};
    if (disabledAll != null) {
      body['disabledAll'] = disabledAll;
    }
    if (disabledTypes != null) {
      body['disabledTypes'] = disabledTypes;
    }
    final response = await http.put(
      Uri.parse('${AppConfig.apiBaseUrl}/notificaciones/preferencias'),
      headers: _headers(token),
      body: jsonEncode(body),
    );
    _ensureSuccess(response, 'No se pudieron actualizar las preferencias');
    return NotificationPreferences.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  // ── PayPal ──────────────────────────────────────────────────────────────────

  /// Crea una orden PayPal para la [solicitudId].
  /// Devuelve el [PayPalOrdenResult] con [orderId] y [approveUrl].
  /// El móvil abre [approveUrl] en un WebView para que el usuario apruebe el pago.
  Future<PayPalOrdenResult> crearOrdenPayPal({
    required String token,
    required int solicitudId,
  }) async {
    final response = await http.post(
      Uri.parse('${AppConfig.apiBaseUrl}/pagos/paypal/crear-orden/$solicitudId'),
      headers: _headers(token),
    );
    _ensureSuccess(response, 'No se pudo crear la orden PayPal');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return PayPalOrdenResult.fromJson(data);
  }

  /// Captura una orden PayPal que el usuario ya aprobó en el WebView.
  /// Debe llamarse después de que el usuario complete el pago en PayPal.
  Future<Map<String, dynamic>> capturarOrdenPayPal({
    required String token,
    required String orderId,
    required int solicitudId,
  }) async {
    final response = await http.post(
      Uri.parse('${AppConfig.apiBaseUrl}/pagos/paypal/capturar'),
      headers: _headers(token),
      body: jsonEncode({
        'order_id': orderId,
        'solicitud_id': solicitudId,
      }),
    );
    _ensureSuccess(response, 'No se pudo capturar el pago PayPal');
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  void _ensureSuccess(http.Response response, String message) {
    if (response.statusCode >= 400) {
      // 401 = token ausente/expirado/inválido para el tenant. Lanzamos un tipo
      // dedicado para que las pantallas cierren sesión y redirijan al login en
      // vez de mostrar un error genérico (sesión "zombie" como la que había en
      // la web antes del interceptor 401→/login).
      if (response.statusCode == 401) {
        throw const SessionExpiredException();
      }
      // Extraemos el `detail` ANTES de cualquier throw para que el catch
      // de jsonDecode (que solo debe atrapar errores de parseo) no se trague
      // nuestro propio Exception con el mensaje real del backend.
      String? backendDetail;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final detail = decoded['detail'] ?? decoded['message'];
          if (detail is String && detail.trim().isNotEmpty) {
            backendDetail = detail;
          } else if (detail is List && detail.isNotEmpty) {
            final first = detail.first;
            if (first is Map<String, dynamic> && first['msg'] is String) {
              backendDetail = first['msg'] as String;
            }
          }
        }
      } catch (_) {
        // body no es JSON parseable — caemos al mensaje genérico.
      }
      // Incluimos el statusCode para que sea más fácil diagnosticar
      // (502 = falla externa, 400 = validación, 403 = permisos, etc.)
      final suffix = backendDetail != null
          ? ' (${response.statusCode}: $backendDetail)'
          : ' (HTTP ${response.statusCode})';
      throw Exception('$message$suffix');
    }
  }

  // ── Trabajos realizados ───────────────────────────────────────────────────

  /// Fetch the list of completed jobs and their summary from the backend.
  Future<Map<String, dynamic>> getTrabajosRealizados({
    required String token,
    String? desde,
    String? hasta,
  }) async {
    final query = <String, String>{};
    if (desde != null) query['desde'] = desde;
    if (hasta != null) query['hasta'] = hasta;
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/solicitudes/trabajos-realizados')
        .replace(queryParameters: query.isNotEmpty ? query : null);
    final response = await http.get(uri, headers: _headers(token));
    _ensureSuccess(response, 'No se pudieron obtener los trabajos realizados');
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Download the PDF report of completed jobs as raw bytes.
  Future<Uint8List> descargarTrabajosPdf({
    required String token,
    String? desde,
    String? hasta,
  }) async {
    final query = <String, String>{};
    if (desde != null) query['desde'] = desde;
    if (hasta != null) query['hasta'] = hasta;
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/solicitudes/trabajos-realizados/pdf')
        .replace(queryParameters: query.isNotEmpty ? query : null);
    final response = await http.get(uri, headers: _headers(token));
    _ensureSuccess(response, 'No se pudo generar el PDF');
    return response.bodyBytes;
  }

  /// Download the CSV report of completed jobs as raw bytes.
  Future<Uint8List> descargarTrabajosCsv({
    required String token,
    String? desde,
    String? hasta,
  }) async {
    final query = <String, String>{};
    if (desde != null) query['desde'] = desde;
    if (hasta != null) query['hasta'] = hasta;
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/solicitudes/trabajos-realizados/csv')
        .replace(queryParameters: query.isNotEmpty ? query : null);
    final response = await http.get(uri, headers: _headers(token));
    _ensureSuccess(response, 'No se pudo generar el CSV');
    return response.bodyBytes;
  }

  /// Send an audio file to the backend Whisper endpoint and return the
  /// transcribed Spanish text.  The OpenAI API key lives only on the server.
  Future<String> transcribirAudio({
    required String token,
    required String filePath,
  }) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw Exception('No se encontró el archivo de audio para transcribir');
    }
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${AppConfig.apiBaseUrl}/voz/transcribir'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(
      await http.MultipartFile.fromPath(
        'audio',
        file.path,
        contentType: _resolveMediaType(file.path),
      ),
    );
    final response = await http.Response.fromStream(await request.send());
    _ensureSuccess(response, 'No se pudo transcribir el audio');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['texto'] as String? ?? '').trim();
  }

  /// Sends a batch of offline-queued operations to the backend.
  ///
  /// Each entry must follow the ``SyncOperation`` contract:
  ///   { tipo, idempotency_key, payload, offline_created_at }
  /// The backend ([POST /sync/lote]) deduplicates by ``idempotency_key`` and
  /// returns a per-operation result so the client can update each row's
  /// status individually.
  Future<Map<String, dynamic>> sincronizarLote({
    required String token,
    required List<Map<String, dynamic>> operations,
  }) async {
    final response = await http
        .post(
          Uri.parse('${AppConfig.apiBaseUrl}/sync/lote'),
          headers: _headers(token),
          body:    jsonEncode({'operations': operations}),
        )
        .timeout(const Duration(seconds: 30));
    _ensureSuccess(response, 'No se pudo sincronizar el lote offline');
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Analyzes an image via the backend's AI Vision pipeline.
  /// Returns the full payload (severity, labels, alt_text, etc.) so the UI
  /// can show the user what the AI detected before they submit the request.
  Future<Map<String, dynamic>> analizarImagenIa({
    required String token,
    required String filePath,
  }) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw Exception('No se encontró la imagen para analizar');
    }
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${AppConfig.apiBaseUrl}/ai/image/analyze'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(
      await http.MultipartFile.fromPath(
        'archivo',
        file.path,
        contentType: _resolveMediaType(file.path),
      ),
    );
    final response = await http.Response.fromStream(await request.send());
    _ensureSuccess(response, 'No se pudo analizar la imagen con IA');
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Tenant key sent on every request as `X-Tenant` so the FastAPI backend
  /// can route the query to the correct per-tenant database. Defaults to
  /// `default` for first-launch / unauthenticated flows; the SessionProvider
  /// updates it right after a successful login.
  String _currentTenant = 'default';

  /// Almacenamiento local para cachear catálogos no sensibles (ej. tipos de
  /// incidente) y poder llenarlos en modo offline. No guarda secretos.
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// Updates the tenant key used for subsequent requests. Call this from
  /// the login screen / session provider so all traffic routes to the right
  /// tenant. Empty / null values reset to 'default'.
  void setTenant(String? tenant) {
    final value = (tenant ?? '').trim();
    _currentTenant = value.isEmpty ? 'default' : value;
  }

  /// Current tenant key the service is using. Read by the WebSocket service
  /// so the connection URL carries `?tenant=<key>`.
  String get currentTenant => _currentTenant;

  Map<String, String> _headers(String token) {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      // X-Tenant routes the query to the right per-tenant database in the
      // FastAPI backend. Without it, every request would fall through to
      // the `default` tenant and leak data across organizations.
      'X-Tenant': _currentTenant,
    };
  }

  MediaType _resolveMediaType(String filePath) {
    final extension = filePath.split('.').last.toLowerCase();
    return switch (extension) {
      'jpg' || 'jpeg' => MediaType('image', 'jpeg'),
      'png' => MediaType('image', 'png'),
      'webp' => MediaType('image', 'webp'),
      'mp3' => MediaType('audio', 'mpeg'),
      'wav' => MediaType('audio', 'wav'),
      'm4a' => MediaType('audio', 'mp4'),
      _ => MediaType('application', 'octet-stream'),
    };
  }
}
