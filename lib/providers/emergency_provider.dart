import 'package:flutter/foundation.dart';

import '../models/notification_item.dart';
import '../models/solicitud.dart';
import '../models/tecnico_cercano.dart';
import '../models/vehiculo.dart';
import '../services/api_service.dart';


class EmergencyProvider extends ChangeNotifier {
  EmergencyProvider(this._apiService);

  final ApiService _apiService;

  List<Vehiculo> vehiculos = [];
  List<Solicitud> solicitudes = [];
  List<NotificationItem> notificaciones = [];
  List<TecnicoCercano> tecnicosCercanos = [];
  bool loading = false;

  Future<void> cargarDatos(String token) async {
    loading = true;
    notifyListeners();
    try {
      vehiculos = await _apiService.obtenerVehiculos(token);
      solicitudes = await _apiService.obtenerSolicitudes(token);
      notificaciones = await _apiService.obtenerNotificaciones(token);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> cargarTecnicosCercanos(
    String token, {
    required double latitud,
    required double longitud,
  }) async {
    tecnicosCercanos = await _apiService.obtenerTecnicosCercanos(
      token,
      latitud: latitud,
      longitud: longitud,
    );
    notifyListeners();
  }

  Future<void> marcarNotificacionLeida(String token, int notificacionId) async {
    await _apiService.marcarNotificacionLeida(token, notificacionId);
    notificaciones = await _apiService.obtenerNotificaciones(token);
    notifyListeners();
  }
}
