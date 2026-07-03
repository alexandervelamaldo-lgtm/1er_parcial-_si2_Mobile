import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

import '../providers/emergency_provider.dart';
import '../providers/session_provider.dart';
import '../models/solicitud.dart';
import '../services/api_service.dart';
import 'paypal_checkout_screen.dart';


class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  String _formatBs(double? amount) {
    final value = amount ?? 0;
    return 'Bs ${value.toStringAsFixed(2)}';
  }

  Future<void> _openInvoicePdf({
    required BuildContext context,
    required ApiService api,
    required String token,
    required int solicitudId,
  }) async {
    final bytes = await api.descargarFacturaPdf(token: token, solicitudId: solicitudId);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/factura_solicitud_$solicitudId.pdf');
    await file.writeAsBytes(bytes, flush: true);
    await OpenFilex.open(file.path);
  }

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
                solicitud.costoFinal != null
                    ? '${solicitud.descripcion}\nCosto final ${_formatBs(solicitud.costoFinal)}'
                    : solicitud.costoEstimado != null
                    ? '${solicitud.descripcion}\nEstimado ${_formatBs(solicitud.costoEstimado)}'
                    : solicitud.descripcion,
              ),
              isThreeLine: solicitud.costoEstimado != null || solicitud.costoFinal != null,
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
      text: (solicitudBase.costoFinal ?? solicitudBase.costoEstimado)?.toStringAsFixed(2) ?? '',
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
    var invoiceLoading = false;
    var paypalLoading = false;
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
                  final forcedTenant = (solicitudBase.tenantKey ?? '').trim();
                  final previousTenant = api.currentTenant;
                  if (forcedTenant.isNotEmpty) {
                    api.setTenant(forcedTenant);
                  }
                  try {
                    final detalle = await api.obtenerDetalleSolicitud(token, solicitudBase.id);
                    final seguimiento = await api.obtenerSeguimientoSolicitud(token, solicitudBase.id);
                    final candidatos = await api.obtenerCandidatosSolicitud(token, solicitudBase.id);
                    return (detalle: detalle, seguimiento: seguimiento, candidatos: candidatos);
                  } finally {
                    api.setTenant(previousTenant);
                  }
                }(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    final message = snapshot.error.toString().replaceFirst('Exception: ', '');
                    return SizedBox(
                      height: 240,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'No se pudo cargar el detalle.\n$message',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            children: [
                              FilledButton(
                                onPressed: () => Navigator.pop(sheetContext),
                                child: const Text('Cerrar'),
                              ),
                              FilledButton.tonal(
                                onPressed: () => setModalState(() {}),
                                child: const Text('Reintentar'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }
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
                  if (amountController.text.isEmpty && (detalle.costoFinal != null || detalle.costoEstimado != null)) {
                    amountController.text = (detalle.costoFinal ?? detalle.costoEstimado)!.toStringAsFixed(2);
                  }
                  final canPay = detalle.trabajoTerminado && detalle.costoFinal != null && ultimoPago?.estado != 'PAGADO';
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
                                'Aproximado ${_formatBs(detalle.costoEstimado)}',
                                style: Theme.of(context).textTheme.titleMedium,
                              )
                            else
                              const Text('Estimación pendiente'),
                            if (detalle.costoEstimadoMin != null && detalle.costoEstimadoMax != null)
                              Text(
                                'Rango ${_formatBs(detalle.costoEstimadoMin)} - ${_formatBs(detalle.costoEstimadoMax)}',
                              ),
                            if (detalle.costoEstimacionConfianza != null)
                              Text(
                                'Confianza ${(detalle.costoEstimacionConfianza! * 100).toStringAsFixed(0)}%',
                              ),
                            if (detalle.costoEstimacionNota != null) Text(detalle.costoEstimacionNota!),
                            if (detalle.costoFinal != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Costo final del taller ${_formatBs(detalle.costoFinal)}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                            if (detalle.trabajoTerminadoObservacion != null)
                              Text(detalle.trabajoTerminadoObservacion!),
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
                            Text('Taller: ${seguimiento.tecnicoNombre ?? 'Pendiente'}'),
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
                                  : 'Estado ${ultimoPago.estado} · ${ultimoPago.metodoPago} · ${_formatBs(ultimoPago.montoTotal)}',
                            ),
                            if (ultimoPago?.referenciaExterna != null) Text('Referencia ${ultimoPago!.referenciaExterna}'),
                            if (detalle.trabajoTerminado && detalle.costoFinal != null && ultimoPago?.estado != 'PAGADO')
                              Text('Monto pendiente ${_formatBs(detalle.costoFinal)}'),
                          ],
                        ),
                      ),
                    ),
                    if (canPay) ...[
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: paymentMethod,
                        decoration: const InputDecoration(
                          labelText: 'Método de pago',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'tarjeta', child: Text('Tarjeta')),
                          DropdownMenuItem(value: 'transferencia', child: Text('Transferencia')),
                          DropdownMenuItem(value: 'efectivo', child: Text('Efectivo')),
                          DropdownMenuItem(value: 'billetera', child: Text('Billetera digital')),
                          DropdownMenuItem(value: 'paypal', child: Text('PayPal')),
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
                          labelText: 'Monto final en Bs',
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
                      // ── PayPal button (shown when paypal method is selected) ──────
                      if (paymentMethod == 'paypal') ...[
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF003087),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon: paypalLoading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.payment),
                            label: Text(
                              paypalLoading ? 'Conectando con PayPal...' : 'Pagar con PayPal',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            onPressed: paypalLoading
                                ? null
                                : () async {
                                    setModalState(() => paypalLoading = true);
                                    try {
                                      // 1) Create PayPal order on backend
                                      final orden = await api.crearOrdenPayPal(
                                        token: token,
                                        solicitudId: detalle.id,
                                      );
                                      if (!sheetContext.mounted) return;

                                      // 2) Open PayPal approval in WebView
                                      final result = await Navigator.of(sheetContext).push<PayPalCheckoutResult>(
                                        MaterialPageRoute(
                                          builder: (_) => PayPalCheckoutScreen(
                                            approveUrl: orden.approveUrl,
                                            orderId: orden.orderId,
                                            solicitudId: orden.solicitudId,
                                            monto: orden.monto,
                                            moneda: orden.moneda,
                                          ),
                                        ),
                                      );
                                      if (!sheetContext.mounted) return;

                                      if (result is PayPalApproved) {
                                        // 3) Capture payment on backend
                                        setModalState(() => paypalLoading = true);
                                        await api.capturarOrdenPayPal(
                                          token: token,
                                          orderId: result.orderId,
                                          solicitudId: detalle.id,
                                        );
                                        if (!sheetContext.mounted) return;
                                        await emergencyProvider.cargarDatos(token);
                                        if (!sheetContext.mounted) return;
                                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                                          const SnackBar(
                                            content: Text('Pago PayPal confirmado exitosamente'),
                                            backgroundColor: Color(0xFF16A34A),
                                          ),
                                        );
                                        Navigator.of(sheetContext).pop();
                                      } else if (result is PayPalCancelled) {
                                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                                          const SnackBar(content: Text('Pago PayPal cancelado')),
                                        );
                                      } else if (result is PayPalWebViewError) {
                                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                                          SnackBar(content: Text('Error PayPal: ${result.message}')),
                                        );
                                      }
                                    } catch (e) {
                                      if (!sheetContext.mounted) return;
                                      ScaffoldMessenger.of(sheetContext).showSnackBar(
                                        SnackBar(content: Text('Error: ${e.toString().replaceFirst('Exception: ', '')}')),
                                      );
                                    } finally {
                                      if (sheetContext.mounted) {
                                        setModalState(() => paypalLoading = false);
                                      }
                                    }
                                  },
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Serás redirigido a PayPal para completar el pago de forma segura.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ] else ...[
                        // ── Manual payment buttons ─────────────────────────────────
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
                    ],
                    if (ultimoPago?.estado == 'PAGADO') ...[
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: invoiceLoading
                            ? null
                            : () async {
                                setModalState(() => invoiceLoading = true);
                                try {
                                  await _openInvoicePdf(
                                    context: sheetContext,
                                    api: api,
                                    token: token,
                                    solicitudId: detalle.id,
                                  );
                                } finally {
                                  if (sheetContext.mounted) {
                                    setModalState(() => invoiceLoading = false);
                                  }
                                }
                              },
                        child: Text(invoiceLoading ? 'Descargando...' : 'Ver factura PDF'),
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
