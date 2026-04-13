import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../providers/emergency_provider.dart';
import '../providers/session_provider.dart';
import '../services/api_service.dart';


class RequestScreen extends StatefulWidget {
  const RequestScreen({super.key});

  @override
  State<RequestScreen> createState() => _RequestScreenState();
}


class _RequestScreenState extends State<RequestScreen> {
  final _descriptionController = TextEditingController();
  final _evidenceNoteController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  bool _esCarretera = false;
  int _nivelRiesgo = 3;
  int? _vehiculoId;
  int? _tipoIncidenteId;
  List<TipoIncidenteOption> _tiposIncidente = [];
  String? _photoPath;
  String? _photoName;
  String? _audioPath;
  String? _audioName;
  bool _sending = false;
  bool _loadingCatalogs = true;
  String _gpsStatus = 'GPS pendiente';
  String? _formNotice;

  @override
  Widget build(BuildContext context) {
    final emergencyProvider = context.watch<EmergencyProvider>();
    final vehicles = emergencyProvider.vehiculos;

    return Scaffold(
      appBar: AppBar(title: const Text('Nueva asistencia')),
      body: _loadingCatalogs
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_formNotice != null) ...[
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_formNotice!),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (vehicles.isEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('No hay vehículos disponibles para crear la asistencia.'),
                    const SizedBox(height: 8),
                    const Text('Registra un vehículo primero o recarga tus datos de cliente.'),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: _sending ? null : _bootstrapForm,
                      child: const Text('Recargar vehículos'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          DropdownButtonFormField<int>(
            initialValue: _vehiculoId,
            decoration: const InputDecoration(
              labelText: 'Vehículo',
              border: OutlineInputBorder(),
            ),
            items: vehicles
                .map(
                  (vehiculo) => DropdownMenuItem<int>(
                    value: vehiculo.id,
                    child: Text('${vehiculo.marca} ${vehiculo.modelo} · ${vehiculo.placa}'),
                  ),
                )
                .toList(),
            onChanged: vehicles.isEmpty ? null : (value) => setState(() => _vehiculoId = value),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: _tipoIncidenteId,
            decoration: const InputDecoration(
              labelText: 'Tipo de incidente',
              border: OutlineInputBorder(),
            ),
            items: _tiposIncidente
                .map(
                  (entry) => DropdownMenuItem<int>(
                    value: entry.id,
                    child: Text(entry.nombre),
                  ),
                )
                .toList(),
            onChanged: _tiposIncidente.isEmpty ? null : (value) => setState(() => _tipoIncidenteId = value),
          ),
          if (_tipoIncidenteId != null) ...[
            const SizedBox(height: 8),
            Text(
              _tiposIncidente
                      .where((item) => item.id == _tipoIncidenteId)
                      .map((item) => item.descripcion)
                      .firstOrNull ??
                  'Selecciona el tipo de incidente que mejor describa tu caso.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _descriptionController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Descripción del incidente',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _evidenceNoteController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Nota adicional para evidencias',
              helperText: 'Opcional: contexto extra para revisión IA u operador',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.my_location),
            title: const Text('Estado de geolocalización'),
            subtitle: Text(_gpsStatus),
            trailing: FilledButton.tonal(
              onPressed: _sending ? null : _refreshLocationStatus,
              child: const Text('Verificar'),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _esCarretera,
            title: const Text('¿El incidente ocurrió en carretera?'),
            onChanged: (value) => setState(() => _esCarretera = value),
          ),
          const SizedBox(height: 8),
          Text('Nivel de riesgo: $_nivelRiesgo'),
          Slider(
            value: _nivelRiesgo.toDouble(),
            min: 1,
            max: 5,
            divisions: 4,
            onChanged: (value) => setState(() => _nivelRiesgo = value.toInt()),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: _pickImage,
            child: Text(_photoName == null ? 'Adjuntar foto' : 'Foto seleccionada: $_photoName'),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: _pickAudio,
            child: Text(_audioName == null ? 'Adjuntar audio' : 'Audio seleccionado: $_audioName'),
          ),
          const SizedBox(height: 12),
          Text(
            'Puedes enviar texto, foto y audio en una sola solicitud. El backend transcribe y analiza la evidencia automáticamente.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            AppConfig.usesEmulatorLoopback
                ? 'Configuración actual: emulador Android con backend en 10.0.2.2:8001.'
                : 'Si usas un celular físico, compila con --dart-define=API_BASE_URL=http://TU_IP_LOCAL:8001.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _sending ? null : _sendRequest,
            child: Text(_sending ? 'Enviando...' : 'Solicitar asistencia'),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _refreshLocationStatus();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapForm());
  }

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de galería'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file_outlined),
              title: const Text('Elegir desde archivos'),
              onTap: () => Navigator.pop(context, 'files'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || source == null) {
      return;
    }
    switch (source) {
      case 'camera':
        await _pickImageFromCamera();
        return;
      case 'gallery':
        await _pickImageFromGallery();
        return;
      case 'files':
        await _pickImageFromFiles();
        return;
    }
  }

  Future<void> _pickAudio() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'm4a'],
      withData: false,
    );
    final file = result?.files.single;
    if (file?.path == null) {
      return;
    }
    setState(() {
      _audioPath = file!.path;
      _audioName = file.name;
    });
  }

  Future<void> _refreshLocationStatus() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() => _gpsStatus = 'Activa el servicio de ubicación para enviar la asistencia');
        }
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _gpsStatus = 'Permiso GPS no concedido');
        }
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (mounted) {
        setState(() {
          _gpsStatus = 'Última ubicación lista: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _gpsStatus = 'No se pudo obtener la ubicación actual');
      }
    }
  }

  Future<void> _bootstrapForm() async {
    final sessionProvider = context.read<SessionProvider>();
    final emergencyProvider = context.read<EmergencyProvider>();
    final apiService = context.read<ApiService>();
    final token = sessionProvider.token;
    if (token == null) {
      if (mounted) {
        setState(() {
          _loadingCatalogs = false;
          _formNotice = 'La sesión expiró. Inicia sesión nuevamente.';
        });
      }
      return;
    }
    setState(() {
      _loadingCatalogs = true;
      _formNotice = null;
    });
    try {
      await emergencyProvider.cargarDatos(token);
      final tipos = await apiService.obtenerTiposIncidente(token);
      final vehiculos = emergencyProvider.vehiculos;
      if (!mounted) {
        return;
      }
      setState(() {
        _tiposIncidente = tipos;
        _vehiculoId = vehiculos.isNotEmpty ? (_vehiculoId ?? vehiculos.first.id) : null;
        _tipoIncidenteId = tipos.isNotEmpty ? (_tipoIncidenteId ?? tipos.first.id) : null;
        if (vehiculos.isEmpty) {
          _formNotice = 'Tu cuenta cliente no tiene vehículos cargados todavía.';
        } else if (tipos.isEmpty) {
          _formNotice = 'No hay tipos de incidente disponibles en el backend.';
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _formNotice = error.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() => _loadingCatalogs = false);
      }
    }
  }

  Future<void> _sendRequest() async {
    final messenger = ScaffoldMessenger.of(context);
    final sessionProvider = context.read<SessionProvider>();
    final token = sessionProvider.token;
    final apiService = context.read<ApiService>();
    final emergencyProvider = context.read<EmergencyProvider>();

    if (token == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Sesión no válida')));
      return;
    }
    if (_vehiculoId == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Selecciona un vehículo')));
      return;
    }
    if (_tipoIncidenteId == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Selecciona un tipo de incidente válido')));
      return;
    }
    final clienteId = sessionProvider.profile?.clienteId;
    if (clienteId == null) {
      messenger.showSnackBar(const SnackBar(content: Text('No se encontró el perfil del cliente')));
      return;
    }
    if (_descriptionController.text.trim().length < 10) {
      messenger.showSnackBar(const SnackBar(content: Text('Describe el incidente con más detalle')));
      return;
    }

    setState(() => _sending = true);
    int? solicitudId;
    try {
      final position = await _resolvePosition();
      solicitudId = await apiService.crearSolicitud(
            token: token,
            clienteId: clienteId,
            vehiculoId: _vehiculoId!,
            tipoIncidenteId: _tipoIncidenteId!,
            descripcion: _descriptionController.text.trim(),
            latitud: position.latitude,
            longitud: position.longitude,
            esCarretera: _esCarretera,
            nivelRiesgo: _nivelRiesgo,
          );
      final evidenciasAdjuntas = <String>[];
      final evidenciasFallidas = <String>[];
      if (_photoPath != null) {
        await _adjuntarEvidencia(
          etiqueta: 'foto',
          onUpload: () => apiService.subirEvidenciaArchivo(
            token: token,
            solicitudId: solicitudId!,
            filePath: _photoPath!,
          ),
          ok: evidenciasAdjuntas,
          fail: evidenciasFallidas,
        );
      }
      if (_audioPath != null) {
        await _adjuntarEvidencia(
          etiqueta: 'audio',
          onUpload: () => apiService.subirEvidenciaArchivo(
            token: token,
            solicitudId: solicitudId!,
            filePath: _audioPath!,
          ),
          ok: evidenciasAdjuntas,
          fail: evidenciasFallidas,
        );
      }
      if (_evidenceNoteController.text.trim().isNotEmpty) {
        await _adjuntarEvidencia(
          etiqueta: 'nota',
          onUpload: () => apiService.subirEvidenciaTexto(
            token: token,
            solicitudId: solicitudId!,
            contenido: _evidenceNoteController.text.trim(),
          ),
          ok: evidenciasAdjuntas,
          fail: evidenciasFallidas,
        );
      }
      await emergencyProvider.cargarDatos(token);
      if (!mounted) {
        return;
      }
      await _showSubmissionResult(
        solicitudId: solicitudId,
        evidenciasAdjuntas: evidenciasAdjuntas,
        evidenciasFallidas: evidenciasFallidas,
      );
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (error) {
      final message = error.toString().replaceFirst('Exception: ', '');
      if (solicitudId != null) {
        messenger.showSnackBar(
          SnackBar(content: Text('La solicitud #$solicitudId se creó, pero hubo un problema al adjuntar evidencias: $message')),
        );
        if (mounted) {
          Navigator.pop(context);
        }
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _pickImageFromCamera() async {
    final result = await _imagePicker.pickImage(source: ImageSource.camera);
    if (result == null) {
      return;
    }
    _setPhotoSelection(result.path, result.name);
  }

  Future<void> _pickImageFromGallery() async {
    final result = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (result == null) {
      return;
    }
    _setPhotoSelection(result.path, result.name);
  }

  Future<void> _pickImageFromFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      withData: false,
    );
    final file = result?.files.single;
    if (file?.path == null) {
      return;
    }
    _setPhotoSelection(file!.path!, file.name);
  }

  void _setPhotoSelection(String path, String name) {
    setState(() {
      _photoPath = path;
      _photoName = name;
    });
  }

  Future<void> _adjuntarEvidencia({
    required String etiqueta,
    required Future<void> Function() onUpload,
    required List<String> ok,
    required List<String> fail,
  }) async {
    try {
      await onUpload();
      ok.add(etiqueta);
    } catch (error) {
      final message = error.toString().replaceFirst('Exception: ', '').trim();
      fail.add(message.isNotEmpty ? '$etiqueta: $message' : etiqueta);
    }
  }

  Future<void> _showSubmissionResult({
    required int solicitudId,
    required List<String> evidenciasAdjuntas,
    required List<String> evidenciasFallidas,
  }) async {
    final title = evidenciasFallidas.isEmpty
        ? 'Solicitud creada'
        : 'Solicitud creada con observaciones';
    final summary = <String>[
      'La solicitud #$solicitudId fue registrada correctamente.',
      if (evidenciasAdjuntas.isNotEmpty)
        'Evidencias adjuntadas: ${evidenciasAdjuntas.join(', ')}.',
      if (evidenciasFallidas.isNotEmpty)
        'No se pudieron adjuntar: ${evidenciasFallidas.join('; ')}.',
    ].join('\n');

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(summary),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  Future<Position> _resolvePosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('El GPS está desactivado');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw Exception('No hay permiso de geolocalización para reportar la emergencia');
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 12),
      ),
    );
  }
}
