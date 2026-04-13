import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config/app_config.dart';
import '../models/notification_item.dart';
import '../models/profile_data.dart';
import '../models/solicitud.dart';
import '../models/tecnico_cercano.dart';
import '../models/vehiculo.dart';


class TipoIncidenteOption {
  TipoIncidenteOption({
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
}


class ApiService {
  static const Duration _cloudLoginTimeout = Duration(seconds: 45);

  Future<String> login({
    required String email,
    required String password,
  }) async {
    http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(_cloudLoginTimeout);
    } on SocketException {
      throw Exception(
        'No se pudo conectar con el backend móvil. Si usas emulador Android usa ${AppConfig.apiBaseUrl}. '
        'Si usas celular físico recompila con --dart-define=API_BASE_URL=http://TU_IP_LOCAL:8001',
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
    return data['access_token'] as String;
  }

  Future<ProfileData> obtenerPerfilActual(String token) async {
    final response = await http.get(
      Uri.parse('${AppConfig.apiBaseUrl}/auth/me'),
      headers: _headers(token),
    );
    _ensureSuccess(response, 'No se pudo cargar el perfil');
    return ProfileData.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<Vehiculo>> obtenerVehiculos(String token) async {
    final response = await http.get(
      Uri.parse('${AppConfig.apiBaseUrl}/vehiculos'),
      headers: _headers(token),
    );
    final data = jsonDecode(response.body) as List<dynamic>;
    return data.map((item) => Vehiculo.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<List<Solicitud>> obtenerSolicitudes(String token) async {
    final response = await http.get(
      Uri.parse('${AppConfig.apiBaseUrl}/solicitudes'),
      headers: _headers(token),
    );
    _ensureSuccess(response, 'No se pudieron cargar las solicitudes');
    final data = jsonDecode(response.body) as List<dynamic>;
    return data.map((item) => Solicitud.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<SolicitudDetalle> obtenerDetalleSolicitud(String token, int solicitudId) async {
    final response = await http.get(
      Uri.parse('${AppConfig.apiBaseUrl}/solicitudes/$solicitudId/detalle'),
      headers: _headers(token),
    );
    _ensureSuccess(response, 'No se pudo cargar el detalle de la solicitud');
    return SolicitudDetalle.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<SolicitudSeguimiento> obtenerSeguimientoSolicitud(String token, int solicitudId) async {
    final response = await http.get(
      Uri.parse('${AppConfig.apiBaseUrl}/solicitudes/$solicitudId/seguimiento'),
      headers: _headers(token),
    );
    _ensureSuccess(response, 'No se pudo cargar el seguimiento');
    return SolicitudSeguimiento.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<SolicitudCandidatos> obtenerCandidatosSolicitud(String token, int solicitudId) async {
    final response = await http.get(
      Uri.parse('${AppConfig.apiBaseUrl}/solicitudes/$solicitudId/candidatos'),
      headers: _headers(token),
    );
    _ensureSuccess(response, 'No se pudieron cargar los candidatos');
    return SolicitudCandidatos.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<NotificationItem>> obtenerNotificaciones(String token) async {
    final response = await http.get(
      Uri.parse('${AppConfig.apiBaseUrl}/notificaciones'),
      headers: _headers(token),
    );
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
    _ensureSuccess(response, 'No se pudieron cargar los técnicos cercanos');
    final data = jsonDecode(response.body) as List<dynamic>;
    return data.map((item) => TecnicoCercano.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<List<TipoIncidenteOption>> obtenerTiposIncidente(String token) async {
    final response = await http
        .get(
          Uri.parse('${AppConfig.apiBaseUrl}/solicitudes/tipos-incidente'),
          headers: _headers(token),
        )
        .timeout(const Duration(seconds: 15));
    _ensureSuccess(response, 'No se pudieron cargar los tipos de incidente');
    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map((item) => TipoIncidenteOption.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<int> crearSolicitud({
    required String token,
    required int clienteId,
    required int vehiculoId,
    required int tipoIncidenteId,
    required String descripcion,
    required double latitud,
    required double longitud,
    required bool esCarretera,
    required int nivelRiesgo,
  }) async {
    late http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/solicitudes'),
            headers: _headers(token),
            body: jsonEncode({
              'cliente_id': clienteId,
              'vehiculo_id': vehiculoId,
              'tipo_incidente_id': tipoIncidenteId,
              'latitud_incidente': latitud,
              'longitud_incidente': longitud,
              'descripcion': descripcion,
              'es_carretera': esCarretera,
              'condicion_vehiculo': 'Operativo con limitaciones',
              'nivel_riesgo': nivelRiesgo,
            }),
          )
          .timeout(const Duration(seconds: 20));
    } on SocketException {
      throw Exception(
        'No se pudo conectar con el backend móvil. Si usas emulador mantén API_BASE_URL en 10.0.2.2. '
        'Si usas celular físico recompila con --dart-define=API_BASE_URL=http://TU_IP_LOCAL:8001',
      );
    } on TimeoutException {
      throw Exception('El backend tardó demasiado en responder al crear la solicitud');
    }

    _ensureSuccess(response, 'No se pudo crear la solicitud');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['id'] as int;
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

  void _ensureSuccess(http.Response response, String message) {
    if (response.statusCode >= 400) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final detail = decoded['detail'] ?? decoded['message'];
          if (detail is String && detail.trim().isNotEmpty) {
            throw Exception(detail);
          }
          if (detail is List && detail.isNotEmpty) {
            final first = detail.first;
            if (first is Map<String, dynamic> && first['msg'] is String) {
              throw Exception(first['msg'] as String);
            }
          }
        }
      } catch (_) {}
      throw Exception(message);
    }
  }

  Map<String, String> _headers(String token) {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
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
