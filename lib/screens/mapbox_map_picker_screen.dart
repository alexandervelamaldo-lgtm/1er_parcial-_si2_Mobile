import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../services/mapbox_service.dart';
import '../widgets/mapbox_map_picker.dart';

class MapboxMapPickerScreen extends StatelessWidget {
  const MapboxMapPickerScreen({
    super.key,
    this.initialCenter = const LatLng(-17.7863, -63.1812),
    this.initialZoom = 13,
    this.unitLocation,
  });

  final LatLng initialCenter;
  final double initialZoom;
  final LatLng? unitLocation;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Elegir ubicación')),
      body: MapboxMapPicker(
        mapbox: MapboxService(),
        initialCenter: initialCenter,
        initialZoom: initialZoom,
        unitLocation: unitLocation,
        onConfirm: (picked) => Navigator.of(context).pop(picked),
      ),
    );
  }
}
