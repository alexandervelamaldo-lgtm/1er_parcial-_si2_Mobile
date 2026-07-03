import 'dart:async';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../models/taller_mapa.dart';
import '../providers/emergency_provider.dart';
import '../providers/session_provider.dart';
import '../services/api_service.dart';
import '../services/offline_queue_service.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import 'mapbox_map_picker_screen.dart';
import 'solicitud_detalle_screen.dart';
import 'workshop_budget_select_screen.dart';
import '../widgets/mapbox_map_picker.dart';


class RequestScreen extends StatefulWidget {
  const RequestScreen({super.key});

  @override
  State<RequestScreen> createState() => _RequestScreenState();
}


class _RequestScreenState extends State<RequestScreen> {
  // Campo único para describir el incidente (daños + contexto en uno).
  final _descriptionController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _esCarretera = false;
  // Nivel de riesgo: ya no es input del cliente. Lo decide la IA en el backend.
  DateTime? _fechaIncidente;
  String _categoriaDano = 'general';
  int? _vehiculoId;
  int? _tipoIncidenteId;
  List<TipoIncidenteOption> _tiposIncidente = [];
  String? _photoPath;
  String? _photoName;
  // AI image analysis state (chip below the "Adjuntar foto" button)
  bool _analizandoImagen = false;
  String? _imagenSeveridad;        // LEVE | MODERADO | SEVERO | CRITICO
  List<String> _imagenEtiquetas = const [];
  String? _imagenResumen;          // alt_text from the AI
  String? _imagenError;
  String? _audioPath;
  String? _audioName;
  bool _recordingAudio = false;
  bool _transcribiendo = false;
  bool _sending = false;
  bool _loadingCatalogs = true;
  String _gpsStatus = 'GPS pendiente';
  String? _formNotice;
  LatLng? _pickedPoint;
  String? _pickedAddress;
  TallerMapa? _selectedTaller;

  @override
  void dispose() {
    _descriptionController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

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
            _InfoBanner(
              icon: Icons.directions_car_outlined,
              message: 'No hay vehículos registrados. Registra uno desde la plataforma web.',
              action: FilledButton.tonal(
                onPressed: _sending ? null : _bootstrapForm,
                child: const Text('Reintentar'),
              ),
            ),
            const SizedBox(height: 16),
          ],
          const _FormSectionHeader(label: 'Datos del vehículo e incidente'),
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
            onChanged: _tiposIncidente.isEmpty
                ? null
                : (value) => setState(() {
                      _tipoIncidenteId = value;
                      final selected = _tiposIncidente.where((item) => item.id == value).firstOrNull;
                      final inferred = _inferDamageCategory(selected);
                      if (inferred != null) {
                        _categoriaDano = inferred;
                      }
                    }),
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
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: const Text('Fecha y hora del incidente'),
            subtitle: Text(
              _fechaIncidente == null
                  ? 'Selecciona la fecha y hora'
                  : '${_fechaIncidente!.toLocal()}'.replaceFirst('.000', ''),
            ),
            trailing: FilledButton.tonal(
              onPressed: _sending ? null : _pickFechaIncidente,
              child: const Text('Elegir'),
            ),
          ),
          // (El dropdown de "Categoría del daño" fue eliminado — la categoría
          // se deriva automáticamente del "Tipo de incidente" seleccionado
          // arriba, vía _inferDamageCategory. Esto evita pedirle al cliente
          // dos veces lo mismo: tipo + categoría son conceptos solapados.)
          const SizedBox(height: 16),
          const _FormSectionHeader(label: 'Descripción del incidente'),
          // Un solo campo unificado: el cliente cuenta todo en su voz
          // — daños, contexto, lo que necesite. La IA del backend extrae
          // las señales relevantes (severidad, partes afectadas, urgencia).
          TextField(
            controller: _descriptionController,
            maxLines: 6,
            minLines: 4,
            decoration: const InputDecoration(
              labelText: 'Describe el incidente y los daños',
              hintText:
                  'Ej: choque frontal en Av. Cañoto, golpe fuerte al parachoques, '
                  'capó abollado, motor no enciende, hay humo blanco saliendo…',
              helperText: 'Cuéntalo con tus palabras. La IA y el taller leerán este texto.',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          const _FormSectionHeader(label: 'Ubicación del incidente'),
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
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _sending ? null : _pickOnMap,
                  icon: const Icon(Icons.map_outlined),
                  label: Text(_pickedPoint == null ? 'Elegir en mapa' : 'Cambiar ubicación'),
                ),
              ),
              if (_pickedPoint != null) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _sending
                        ? null
                        : () => setState(() {
                              _pickedPoint = null;
                              _pickedAddress = null;
                              _gpsStatus = 'GPS pendiente';
                            }),
                    icon: const Icon(Icons.close),
                    label: const Text('Usar GPS'),
                  ),
                ),
              ],
            ],
          ),
          if (_pickedPoint != null) ...[
            const SizedBox(height: 8),
            Text(
              _pickedAddress == null || _pickedAddress!.trim().isEmpty
                  ? 'Ubicación elegida: ${_pickedPoint!.latitude.toStringAsFixed(5)}, ${_pickedPoint!.longitude.toStringAsFixed(5)}'
                  : 'Ubicación elegida: $_pickedAddress',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          const _FormSectionHeader(label: 'Selección de taller'),
          Card(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.map_outlined,
                          color: Theme.of(context).colorScheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Elige tu taller primero',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Completa los datos del problema y pulsa el botón para ver '
                    'en el mapa los talleres especializados en "${_categoryLabel(_categoriaDano)}". '
                    'Compara costos estimados y selecciona el que prefieras. '
                    'La solicitud se creará al confirmar tu elección.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (_selectedTaller != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Taller seleccionado: ${_selectedTaller!.nombre}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF166534),
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _FormSectionHeader(label: 'Detalles adicionales'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _esCarretera,
            title: const Text('¿Ocurrió en carretera?'),
            subtitle: const Text('Activa si el incidente fue fuera de la ciudad'),
            onChanged: (value) => setState(() => _esCarretera = value),
          ),
          const SizedBox(height: 8),
          // Aviso de que el nivel de riesgo lo determina la IA, no el cliente.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.20)),
            ),
            child: const Row(
              children: [
                Icon(Icons.auto_awesome_outlined, size: 18, color: AppColors.primary),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'El nivel de riesgo lo determina la IA al enviar la solicitud, '
                    'analizando la descripción, las evidencias y la condición declarada.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _FormSectionHeader(label: 'Evidencias (opcional)'),
          _EvidenceRow(
            icon: Icons.photo_camera_outlined,
            label: _photoName == null ? 'Adjuntar foto' : _photoName!,
            selected: _photoName != null,
            onTap: _pickImage,
          ),
          if (_analizandoImagen || _imagenSeveridad != null || _imagenError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 2),
              child: _ImageAnalysisChip(
                analyzing: _analizandoImagen,
                severity: _imagenSeveridad,
                labels: _imagenEtiquetas,
                summary: _imagenResumen,
                error: _imagenError,
              ),
            ),
          const SizedBox(height: 8),
          _EvidenceRow(
            icon: Icons.audio_file_outlined,
            label: _audioName == null ? 'Adjuntar audio' : _audioName!,
            selected: _audioName != null,
            onTap: _pickAudio,
          ),
          const SizedBox(height: 8),
          _EvidenceRow(
            icon: _transcribiendo
                ? Icons.hourglass_top_outlined
                : _recordingAudio
                    ? Icons.stop_circle_outlined
                    : Icons.mic_outlined,
            label: _transcribiendo
                ? 'Transcribiendo con IA…'
                : _recordingAudio
                    ? 'Grabando… toca para detener'
                    : 'Grabar nota de voz (transcripción automática)',
            selected: _recordingAudio || _transcribiendo,
            selectedColor: _transcribiendo ? AppColors.primary : AppColors.error,
            onTap: (_sending || _transcribiendo) ? null : _toggleRecording,
          ),
          if (_audioPath != null && !_recordingAudio) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _sending ? null : _playRecordedAudio,
                    icon: const Icon(Icons.play_arrow_outlined, size: 18),
                    label: const Text('Reproducir'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _sending ? null : _clearAudio,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Eliminar audio'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                  ),
                ),
              ],
            ),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              'El backend analiza y transcribe foto y audio automáticamente con IA.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _sending ? null : _sendRequest,
            icon: _sending
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.map_outlined, size: 20),
            label: Text(_sending ? 'Procesando…' : 'Ver talleres disponibles'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
          const SizedBox(height: 16),
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

  Future<void> _toggleRecording() async {
    final messenger = ScaffoldMessenger.of(context);

    // ── Stop recording ────────────────────────────────────────────────────────
    if (_recordingAudio) {
      final path = await _audioRecorder.stop();
      if (!mounted) return;
      setState(() {
        _recordingAudio = false;
        if (path != null) {
          _audioPath = path;
          _audioName = path.split('/').last;
        }
      });

      // Automatically transcribe the recorded audio
      if (path != null) {
        await _transcribirGrabacion(path, messenger);
      }
      return;
    }

    // ── Start recording ───────────────────────────────────────────────────────
    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      if (mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('Permiso de micrófono no concedido')));
      }
      return;
    }

    final directory = await getTemporaryDirectory();
    final targetPath = '${directory.path}/nota_voz_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _audioRecorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100),
      path: targetPath,
    );
    if (!mounted) return;
    setState(() {
      _recordingAudio = true;
      _audioPath = targetPath;
      _audioName = targetPath.split('/').last;
    });
  }

  /// Transcribes [audioPath] via the backend Whisper endpoint and offers the
  /// result to the user as the incident description.
  Future<void> _transcribirGrabacion(
    String audioPath,
    ScaffoldMessengerState messenger,
  ) async {
    final token = context.read<SessionProvider>().token;
    if (token == null || !mounted) return;

    setState(() => _transcribiendo = true);
    messenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            SizedBox(width: 12),
            Text('Transcribiendo audio…'),
          ],
        ),
        duration: Duration(seconds: 30),
      ),
    );

    try {
      final api = context.read<ApiService>();
      final texto = await api.transcribirAudio(token: token, filePath: audioPath);
      if (!mounted) return;
      messenger.hideCurrentSnackBar();

      if (texto.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No se detectó voz en la grabación')),
        );
        return;
      }

      // Offer the transcription to fill the description field
      await _mostrarTranscripcion(texto);
    } catch (error) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      // Mostramos el motivo real que reporta el backend (p. ej. clave inválida,
      // formato no soportado, timeout) en vez de un mensaje genérico, para que
      // el usuario sepa qué pasó. El audio sigue guardado como evidencia.
      final detalle = error.toString().replaceFirst('Exception: ', '');
      messenger.showSnackBar(
        SnackBar(
          content: Text('No se pudo transcribir: $detalle\nEl audio quedó guardado como evidencia.'),
          duration: const Duration(seconds: 7),
        ),
      );
    } finally {
      if (mounted) setState(() => _transcribiendo = false);
    }
  }

  /// Shows a dialog with the transcribed text and lets the user choose whether
  /// to use it as the incident description.
  Future<void> _mostrarTranscripcion(String texto) async {
    final action = await showDialog<_TranscripcionAccion>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Transcripción de voz'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Esto es lo que detectamos:'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(texto, style: const TextStyle(fontStyle: FontStyle.italic)),
            ),
            const SizedBox(height: 12),
            const Text(
              '¿Usar como descripción del incidente?',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _TranscripcionAccion.ignorar),
            child: const Text('No usar'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, _TranscripcionAccion.usar),
            child: const Text('Usar'),
          ),
        ],
      ),
    );

    if (!mounted || action == null || action == _TranscripcionAccion.ignorar) return;
    _descriptionController.text = texto;
  }

  Future<void> _playRecordedAudio() async {
    final path = _audioPath;
    if (path == null) {
      return;
    }
    await OpenFilex.open(path);
  }

  void _clearAudio() {
    setState(() {
      _recordingAudio = false;
      _audioPath = null;
      _audioName = null;
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

  Future<void> _pickFechaIncidente() async {
    final now = DateTime.now();
    final initialDate = _fechaIncidente ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
    );
    if (!mounted || time == null) return;
    setState(() {
      _fechaIncidente = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
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
    if (_fechaIncidente == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Selecciona la fecha y hora del incidente')));
      return;
    }
    // Un solo campo unificado: pedimos al menos 10 caracteres para que
    // la IA tenga algo con qué trabajar y el taller entienda el contexto.
    if (_descriptionController.text.trim().length < 10) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Describe el incidente (mínimo 10 caracteres)'),
      ));
      return;
    }

    // ── Offline branch ──────────────────────────────────────────────────────
    // If there is no connectivity we cannot load talleres / Mapbox / etc., so
    // we persist the emergency locally and surface it as "pendiente de
    // sincronización". The SyncService will replay it through /sync/lote as
    // soon as the device reconnects.
    final sync = context.read<SyncService>();
    if (!sync.isOnline) {
      await _encolarSolicitudOffline(
        clienteId: clienteId,
        messenger: messenger,
      );
      return;
    }

    setState(() => _sending = true);

    int? solicitudId;
    try {
      // 1. Resolve GPS — el GPS es invariante, no requiere taller previo.
      final point = await _resolveIncidentPoint();
      if (!mounted) return;

      // 2. Crear la solicitud en estado REGISTRADA (sin taller asignado).
      //    El flujo cliente↔taller-directo invierte el orden: primero
      //    creamos la solicitud, después el cliente elige taller con
      //    presupuesto calculado por el backend.
      //    Campo único de descripción — el backend requiere danos_descripcion
      //    (≥5 chars). Re-usamos el mismo texto para ambos campos del modelo.
      final descripcion = _descriptionController.text.trim();
      solicitudId = await apiService.crearSolicitud(
        token: token,
        clienteId: clienteId,
        vehiculoId: _vehiculoId!,
        tipoIncidenteId: _tipoIncidenteId!,
        descripcion: descripcion,
        latitud: point.latitude,
        longitud: point.longitude,
        latitudCliente: point.latitude,
        longitudCliente: point.longitude,
        esCarretera: _esCarretera,
        // nivelRiesgo lo decide el backend (IA), no el cliente.
        // danosDescripcion: igual que descripción — el backend lo exige
        // separado por compatibilidad con el flujo legacy.
        danosDescripcion: descripcion,
        fechaIncidente: _fechaIncidente,
        ubicacionTexto: _pickedAddress,
        categoriaDano: _categoriaDano,
        // Sin taller_id — la solicitud nace REGISTRADA sin asignación.
      );

      // 4. Upload evidences
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
      // (Campo "nota adicional" eliminado — ahora descripción es un único
      // campo donde el cliente escribe todo el contexto del incidente.)

      await emergencyProvider.cargarDatos(token);
      if (!mounted) return;
      // Flujo nuevo: en vez de mostrar dialog + ir al detalle, navegamos
      // a la pantalla de selección de taller con presupuesto. El cliente
      // elige el taller que más le conviene; al elegir, esa pantalla
      // navega ella misma al detalle con "Esperando aceptación…".
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => WorkshopBudgetSelectScreen(
            api: apiService,
            token: token,
            solicitudId: solicitudId!,
            incidentPoint: point,
          ),
        ),
      );
    } catch (error) {
      final raw = error.toString().replaceFirst('Exception: ', '');
      if (solicitudId != null) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('Solicitud #$solicitudId creada. Error en paso posterior: $raw'),
              duration: const Duration(seconds: 6),
            ),
          );
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => SolicitudDetalleScreen(solicitudId: solicitudId!)),
          );
        }
        return;
      }
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(raw),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'OK',
              onPressed: () => messenger.hideCurrentSnackBar(),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  /// Persists the emergency locally when the device is offline.
  ///
  /// We skip the workshop-picking map (which needs Mapbox + network) and the
  /// AI image analyze call (which also needs the backend). The user gets a
  /// clear "pendiente de sincronización" confirmation, and the [SyncService]
  /// will replay this through `POST /sync/lote` as soon as connectivity is
  /// restored. The backend dedupes by ``idempotency_key``.
  Future<void> _encolarSolicitudOffline({
    required int clienteId,
    required ScaffoldMessengerState messenger,
  }) async {
    final queue = context.read<OfflineQueueService>();
    setState(() => _sending = true);
    try {
      // Best-effort GPS read. If even GPS fails, we still enqueue with the
      // last picked location or the dashboard fallback so the user's
      // emergency is never lost.
      LatLng? point;
      try {
        point = await _resolveIncidentPoint().timeout(const Duration(seconds: 8));
      } catch (_) {
        point = _pickedPoint;
      }
      point ??= const LatLng(-17.7863, -63.1812); // Santa Cruz fallback

      // Campo unificado de descripción (≥10 chars validado arriba).
      final descripcion = _descriptionController.text.trim();

      // Nombre del tipo elegido. Viaja junto al id para que /sync/lote pueda
      // resolver por NOMBRE si el id no existe en el tenant — pasa cuando el
      // formulario se llenó 100% offline con el catálogo embebido por defecto,
      // cuyos ids pueden no coincidir con los del tenant. Así la emergencia
      // nunca se pierde por un FK inválido al sincronizar.
      final tipoIncidenteNombre = _tiposIncidente
          .where((t) => t.id == _tipoIncidenteId)
          .map((t) => t.nombre)
          .firstOrNull;

      // Build the same payload shape that POST /solicitudes expects — the
      // backend's _handle_crear_solicitud in /sync/lote re-uses these fields.
      final payload = <String, dynamic>{
        'cliente_id':        clienteId,
        'vehiculo_id':       _vehiculoId,
        'tipo_incidente_id': _tipoIncidenteId,
        'tipo_incidente_nombre': tipoIncidenteNombre,
        'latitud_incidente': point.latitude,
        'longitud_incidente':point.longitude,
        'latitud_cliente':   point.latitude,
        'longitud_cliente':  point.longitude,
        'descripcion':       descripcion,
        'danos_descripcion': descripcion,
        'fecha_incidente':   _fechaIncidente?.toIso8601String(),
        'ubicacion_texto':   _pickedAddress,
        'categoria_dano':    _categoriaDano,
        'es_carretera':      _esCarretera,
        'condicion_vehiculo':'Operativo con limitaciones',
        // nivel_riesgo is deliberately omitted — the backend will infer it.
      };

      final key = await queue.enqueue(tipo: 'crear_solicitud', payload: payload);

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.warning,
          duration: const Duration(seconds: 6),
          content: Text(
            'Sin conexión — emergencia guardada localmente (#${key.substring(0, 8)}). '
            'Se enviará automáticamente cuando recuperes internet.',
          ),
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () => messenger.hideCurrentSnackBar(),
          ),
        ),
      );
      // Reset the form so the user can register another emergency offline.
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('No se pudo guardar localmente: ${e.toString().replaceFirst('Exception: ', '')}'),
      ));
    } finally {
      if (mounted) setState(() => _sending = false);
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
      // Reset previous analysis state so the user sees a fresh result.
      _imagenSeveridad = null;
      _imagenEtiquetas = const [];
      _imagenResumen = null;
      _imagenError = null;
    });
    // Fire-and-forget: analyze the image so we can show a preview chip before
    // the user submits the request.
    unawaited(_analizarImagen(path));
  }

  /// Calls the backend AI Vision endpoint with the attached photo and updates
  /// the UI chip with the detected severity / labels / summary.
  Future<void> _analizarImagen(String path) async {
    final token = context.read<SessionProvider>().token;
    if (token == null) return;
    final api = context.read<ApiService>();
    if (!mounted) return;
    setState(() => _analizandoImagen = true);
    try {
      final result = await api.analizarImagenIa(token: token, filePath: path);
      if (!mounted) return;
      final allowed = result['allowed'];
      // Si la moderación rechaza la imagen, mostramos el motivo.
      if (allowed == false) {
        setState(() {
          _analizandoImagen = false;
          _imagenError =
              (result['reason'] as String?)?.trim().isNotEmpty == true
                  ? (result['reason'] as String).trim()
                  : 'La IA rechazó esta imagen. Adjunta otra evidencia.';
        });
        return;
      }
      setState(() {
        _analizandoImagen = false;
        _imagenSeveridad = (result['severity'] as String?)?.trim();
        _imagenEtiquetas = ((result['labels'] as List?) ?? const [])
            .whereType<String>()
            .toList(growable: false);
        _imagenResumen = (result['alt_text'] as String?)?.trim();
        _imagenError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _analizandoImagen = false;
        _imagenError = e.toString().replaceFirst('Exception: ', '');
      });
    }
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

  Future<LatLng> _resolveIncidentPoint() async {
    final picked = _pickedPoint;
    if (picked != null) return picked;
    final pos = await _resolvePosition();
    return LatLng(pos.latitude, pos.longitude);
  }

  String _categoryLabel(String value) {
    return switch (value) {
      'choque_carroceria' => 'Choques y colisiones',
      'dano_electrico' => 'Problema eléctrico / batería',
      'chaperia_pintura' => 'Chapería y pintura',
      'pinchazo' => 'Llanta pinchada',
      'falla_mecanica' => 'Falla mecánica / motor',
      'suspension' => 'Suspensión / amortiguadores',
      _ => 'General',
    };
  }

  String? _inferDamageCategory(TipoIncidenteOption? option) {
    if (option == null) return null;
    final haystack = '${option.nombre} ${option.descripcion}'.toLowerCase();
    if (haystack.contains('choque') || haystack.contains('colisi')) {
      return 'choque_carroceria';
    }
    if (haystack.contains('bater') || haystack.contains('eléctr') || haystack.contains('electr')) {
      return 'dano_electrico';
    }
    if (haystack.contains('llanta') || haystack.contains('neum') || haystack.contains('pincha')) {
      return 'pinchazo';
    }
    if (haystack.contains('motor') || haystack.contains('mecán') || haystack.contains('mecan')) {
      return 'falla_mecanica';
    }
    if (haystack.contains('suspens') || haystack.contains('amort')) {
      return 'suspension';
    }
    if (haystack.contains('chaper') || haystack.contains('pintur')) {
      return 'chaperia_pintura';
    }
    return null;
  }

  Future<void> _pickOnMap() async {
    final initial = _pickedPoint ?? const LatLng(-17.7863, -63.1812);
    final result = await Navigator.push<MapboxPickedLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => MapboxMapPickerScreen(
          initialCenter: initial,
          initialZoom: 13,
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _pickedPoint = result.point;
      _pickedAddress = result.address;
      _gpsStatus =
          'Ubicación elegida: ${result.point.latitude.toStringAsFixed(4)}, ${result.point.longitude.toStringAsFixed(4)}';
    });
  }
}


// ─── Enums auxiliares ─────────────────────────────────────────────────────────

enum _TranscripcionAccion { usar, ignorar }

// ─── Widgets auxiliares del formulario ───────────────────────────────────────

class _FormSectionHeader extends StatelessWidget {
  const _FormSectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4, left: 2),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
      ),
    );
  }
}


class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.icon, required this.message, this.action});
  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.warning, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: AppColors.warning, fontSize: 13),
                ),
              ),
            ],
          ),
          if (action != null) ...[const SizedBox(height: 10), action!],
        ],
      ),
    );
  }
}


class _EvidenceRow extends StatelessWidget {
  const _EvidenceRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.selectedColor,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color? selectedColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selectedColor ?? AppColors.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.08)
              : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color.withValues(alpha: 0.4) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: selected ? color : Colors.grey),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? color : Theme.of(context).colorScheme.onSurface,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, size: 18, color: color),
          ],
        ),
      ),
    );
  }
}

/// Compact chip shown right under "Adjuntar foto" with the AI Vision result.
/// States: analyzing → success (severity + labels + alt_text) → error.
class _ImageAnalysisChip extends StatelessWidget {
  const _ImageAnalysisChip({
    required this.analyzing,
    required this.severity,
    required this.labels,
    required this.summary,
    required this.error,
  });

  final bool analyzing;
  final String? severity;
  final List<String> labels;
  final String? summary;
  final String? error;

  Color _colorForSeverity(String? s) {
    switch ((s ?? '').toUpperCase()) {
      case 'CRITICO':
      case 'CRÍTICO':
        return AppColors.error;
      case 'SEVERO':
        return const Color(0xFFEA580C); // orange-700
      case 'MODERADO':
        return const Color(0xFFD97706); // amber-600
      case 'LEVE':
        return const Color(0xFF16A34A); // green-600
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (analyzing) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Analizando imagen con IA…',
                style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    if (error != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.30)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'IA no pudo analizar: $error',
                style: const TextStyle(fontSize: 12, color: AppColors.error),
              ),
            ),
          ],
        ),
      );
    }

    final color = _colorForSeverity(severity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: color, size: 16),
              const SizedBox(width: 6),
              Text(
                'IA detectó: ${severity ?? 'sin clase concluyente'}',
                style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          if (labels.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: labels
                  .take(5)
                  .map((l) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(l, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
                      ))
                  .toList(growable: false),
            ),
          ],
          if (summary != null && summary!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              summary!,
              style: const TextStyle(fontSize: 11, color: Color(0xFF475569), fontStyle: FontStyle.italic),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
