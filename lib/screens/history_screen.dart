import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/emergency_provider.dart';
import '../providers/session_provider.dart';
import '../models/solicitud.dart';
import '../services/api_service.dart';


class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EmergencyProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Historial de solicitudes')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: provider.solicitudes.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final solicitud = provider.solicitudes[index];
          return Card(
            child: ListTile(
              leading: CircleAvatar(child: Text('${solicitud.id}')),
              title: Text(solicitud.tipoIncidente),
              subtitle: Text(
                solicitud.costoEstimado != null
                    ? '${solicitud.descripcion}\nEstimado ${solicitud.costoEstimado!.toStringAsFixed(2)}'
                    : solicitud.descripcion,
              ),
              isThreeLine: solicitud.costoEstimado != null,
              onTap: () => _showActions(context, solicitud),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(solicitud.estado),
                  Text(solicitud.prioridad),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showActions(BuildContext context, Solicitud solicitudBase) async {
    final amountController = TextEditingController(
      text: solicitudBase.costoEstimado?.toStringAsFixed(2) ?? '',
    );
    final detailController = TextEditingController();
    final approvalController = TextEditingController(text: 'Apruebo el taller sugerido');
    final paymentReferenceController = TextEditingController();
    final paymentNoteController = TextEditingController(text: 'Registro de pago desde la app móvil');
    final token = context.read<SessionProvider>().token;
    final emergencyProvider = context.read<EmergencyProvider>();
    if (token == null) {
      return;
    }
    final api = context.read<ApiService>();
    var paymentMethod = 'tarjeta';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
              ),
              child: FutureBuilder<({SolicitudDetalle detalle, SolicitudSeguimiento seguimiento, SolicitudCandidatos candidatos})>(
                future: () async {
                  final detalle = await api.obtenerDetalleSolicitud(token, solicitudBase.id);
                  final seguimiento = await api.obtenerSeguimientoSolicitud(token, solicitudBase.id);
                  final candidatos = await api.obtenerCandidatosSolicitud(token, solicitudBase.id);
                  return (detalle: detalle, seguimiento: seguimiento, candidatos: candidatos);
                }(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const SizedBox(
                      height: 240,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final detalle = snapshot.data!.detalle;
                  final seguimiento = snapshot.data!.seguimiento;
                  final candidatos = snapshot.data!.candidatos;
                  final ultimoPago = detalle.pagos.isNotEmpty ? detalle.pagos.first : null;
                  if (amountController.text.isEmpty && detalle.costoEstimado != null) {
                    amountController.text = detalle.costoEstimado!.toStringAsFixed(2);
                  }
                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    Text('Solicitud #${detalle.id}', style: Theme.of(sheetContext).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(detalle.tipoIncidente),
                      subtitle: Text(detalle.descripcion),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(detalle.estado),
                          Text(detalle.prioridad),
                        ],
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(label: Text('IA ${((detalle.clasificacionConfianza ?? 0) * 100).toStringAsFixed(0)}%')),
                        if (detalle.requiereRevisionManual) const Chip(label: Text('Revisión manual')),
                        if (detalle.etiquetasIa.isNotEmpty) Chip(label: Text(detalle.etiquetasIa.join(', '))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Costo estimado', style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: 8),
                            if (detalle.costoEstimado != null)
                              Text(
                                'Aproximado ${detalle.costoEstimado!.toStringAsFixed(2)}',
                                style: Theme.of(context).textTheme.titleMedium,
                              )
                            else
                              const Text('Estimación pendiente'),
                            if (detalle.costoEstimadoMin != null && detalle.costoEstimadoMax != null)
                              Text(
                                'Rango ${detalle.costoEstimadoMin!.toStringAsFixed(2)} - ${detalle.costoEstimadoMax!.toStringAsFixed(2)}',
                              ),
                            if (detalle.costoEstimacionConfianza != null)
                              Text(
                                'Confianza ${(detalle.costoEstimacionConfianza! * 100).toStringAsFixed(0)}%',
                              ),
                            if (detalle.costoEstimacionNota != null) Text(detalle.costoEstimacionNota!),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Seguimiento', style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: 8),
                            Text('Taller: ${seguimiento.tallerNombre ?? 'Pendiente'}'),
                            Text('Técnico: ${seguimiento.tecnicoNombre ?? 'Pendiente'}'),
                            Text('ETA: ${seguimiento.etaMin?.toString() ?? '--'} min'),
                            if (seguimiento.mensaje != null) Text(seguimiento.mensaje!),
                          ],
                        ),
                      ),
                    ),
                    if (detalle.clienteAprobada == false && detalle.tallerId != null) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: approvalController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Respuesta del cliente a la propuesta',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: () async {
                                await api.responderPropuestaCliente(
                                  token: token,
                                  solicitudId: detalle.id,
                                  aprobada: true,
                                  observacion: approvalController.text.trim(),
                                );
                                if (!sheetContext.mounted) return;
                                await emergencyProvider.cargarDatos(token);
                                if (!sheetContext.mounted) return;
                                Navigator.of(sheetContext).pop();
                              },
                              child: const Text('Aprobar taller'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.tonal(
                              onPressed: () async {
                                await api.responderPropuestaCliente(
                                  token: token,
                                  solicitudId: detalle.id,
                                  aprobada: false,
                                  observacion: approvalController.text.trim(),
                                );
                                if (!sheetContext.mounted) return;
                                await emergencyProvider.cargarDatos(token);
                                if (!sheetContext.mounted) return;
                                Navigator.of(sheetContext).pop();
                              },
                              child: const Text('Rechazar'),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (candidatos.talleres.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text('Sugerencias de cobertura', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      ...candidatos.talleres.take(3).map(
                        (taller) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(taller.nombre),
                          subtitle: Text(taller.motivoSugerencia ?? 'Cercanía y disponibilidad'),
                          trailing: Text(taller.score?.toStringAsFixed(1) ?? '--'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Pago del cliente', style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: 8),
                            Text(
                              ultimoPago == null
                                  ? 'Sin pagos registrados'
                                  : 'Estado ${ultimoPago.estado} · ${ultimoPago.metodoPago} · ${ultimoPago.montoTotal.toStringAsFixed(2)}',
                            ),
                            if (ultimoPago?.referenciaExterna != null) Text('Referencia ${ultimoPago!.referenciaExterna}'),
                          ],
                        ),
                      ),
                    ),
                    if (detalle.estado == 'ASIGNADA' ||
                        detalle.estado == 'EN_CAMINO' ||
                        detalle.estado == 'COMPLETADA' ||
                        detalle.estado == 'EN_ATENCION') ...[
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: paymentMethod,
                        decoration: const InputDecoration(
                          labelText: 'Método de pago',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'tarjeta', child: Text('Tarjeta')),
                          DropdownMenuItem(value: 'transferencia', child: Text('Transferencia')),
                          DropdownMenuItem(value: 'efectivo', child: Text('Efectivo')),
                          DropdownMenuItem(value: 'billetera', child: Text('Billetera digital')),
                        ],
                        onChanged: (value) {
                          setModalState(() => paymentMethod = value ?? 'tarjeta');
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Monto a pagar',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: paymentReferenceController,
                        decoration: const InputDecoration(
                          labelText: 'Referencia de pago',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: paymentNoteController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Observación del pago',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.tonal(
                              onPressed: () async {
                                await api.pagarSolicitud(
                                  token: token,
                                  solicitudId: detalle.id,
                                  montoTotal: double.tryParse(amountController.text),
                                  metodoPago: paymentMethod,
                                  confirmarPago: false,
                                  referenciaExterna: paymentReferenceController.text.trim(),
                                  observacion: paymentNoteController.text.trim(),
                                );
                                if (!sheetContext.mounted) return;
                                await emergencyProvider.cargarDatos(token);
                                if (!sheetContext.mounted) return;
                                Navigator.of(sheetContext).pop();
                              },
                              child: const Text('Registrar pago'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: () async {
                                await api.pagarSolicitud(
                                  token: token,
                                  solicitudId: detalle.id,
                                  montoTotal: double.tryParse(amountController.text),
                                  metodoPago: paymentMethod,
                                  confirmarPago: true,
                                  referenciaExterna: paymentReferenceController.text.trim(),
                                  observacion: paymentNoteController.text.trim(),
                                );
                                if (!sheetContext.mounted) return;
                                await emergencyProvider.cargarDatos(token);
                                if (!sheetContext.mounted) return;
                                Navigator.of(sheetContext).pop();
                              },
                              child: const Text('Confirmar pago'),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextField(
                      controller: detailController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Detalle de disputa o soporte',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: () async {
                        if (detailController.text.trim().isEmpty) {
                          return;
                        }
                        await api.crearDisputa(
                          token: token,
                          solicitudId: detalle.id,
                          motivo: 'Soporte del cliente',
                          detalle: detailController.text.trim(),
                        );
                        if (!sheetContext.mounted) return;
                        await emergencyProvider.cargarDatos(token);
                        if (!sheetContext.mounted) return;
                        Navigator.of(sheetContext).pop();
                      },
                      child: const Text('Abrir disputa / soporte'),
                    ),
                  ],
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}
