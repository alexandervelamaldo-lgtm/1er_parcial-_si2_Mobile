import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Resultado del flujo PayPal devuelto al navegador de la pantalla padre.
sealed class PayPalCheckoutResult {
  const PayPalCheckoutResult();
}

/// El usuario aprobó el pago — [orderId] ya puede capturarse en el backend.
final class PayPalApproved extends PayPalCheckoutResult {
  const PayPalApproved({required this.orderId, required this.payerId});
  final String orderId;
  final String payerId;
}

/// El usuario canceló el pago.
final class PayPalCancelled extends PayPalCheckoutResult {
  const PayPalCancelled();
}

/// Error de carga en el WebView.
final class PayPalWebViewError extends PayPalCheckoutResult {
  const PayPalWebViewError(this.message);
  final String message;
}

/// Pantalla que carga la URL de aprobación de PayPal en un WebView integrado.
///
/// PayPal redirige al usuario a la `return_url` del backend tras aprobar,
/// y a la `cancel_url` si cancela. Esta pantalla intercepta esas redirecciones
/// antes de que el WebView las cargue, extrae el `order_id` y devuelve el
/// resultado apropiado al navegador.
///
/// Nunca almacena ni registra credenciales de PayPal — sólo URLs públicas.
class PayPalCheckoutScreen extends StatefulWidget {
  const PayPalCheckoutScreen({
    super.key,
    required this.approveUrl,
    required this.orderId,
    required this.solicitudId,
    required this.monto,
    required this.moneda,
  });

  final String approveUrl;
  final String orderId;
  final int solicitudId;
  final double monto;
  final String moneda;

  @override
  State<PayPalCheckoutScreen> createState() => _PayPalCheckoutScreenState();
}

class _PayPalCheckoutScreenState extends State<PayPalCheckoutScreen> {
  late final WebViewController _controller;

  bool _isLoading = true;
  String? _errorMessage;

  // PayPal return/cancel URL paths — matched by path only so the host
  // (localhost vs 10.0.2.2) doesn't matter in development.
  static const _returnPath = '/pagos/paypal/retorno';
  static const _cancelPath = '/pagos/paypal/cancelar';

  bool _isReturnUrl(String url) {
    try {
      return Uri.parse(url).path == _returnPath;
    } catch (_) {
      return false;
    }
  }

  bool _isCancelUrl(String url) {
    try {
      return Uri.parse(url).path == _cancelPath;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onWebResourceError: (error) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _errorMessage = 'Error de red: ${error.description}';
              });
            }
          },
          onNavigationRequest: (request) {
            final url = request.url;

            // ── PayPal approved — intercept BEFORE WebView loads the URL ──
            if (_isReturnUrl(url)) {
              final uri = Uri.tryParse(url);
              final orderId = uri?.queryParameters['token'] ?? widget.orderId;
              final payerId = uri?.queryParameters['PayerID'] ?? '';
              Navigator.of(context).pop(
                PayPalApproved(orderId: orderId, payerId: payerId),
              );
              return NavigationDecision.prevent;
            }

            // ── PayPal cancelled ───────────────────────────────────────────
            if (_isCancelUrl(url)) {
              Navigator.of(context).pop(const PayPalCancelled());
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.approveUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pago con PayPal'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancelar pago',
          onPressed: () => Navigator.of(context).pop(const PayPalCancelled()),
        ),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(36),
          child: Container(
            width: double.infinity,
            color: const Color(0xFFF8FAFC),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(
              'Solicitud #${widget.solicitudId} · '
              '${widget.moneda} ${widget.monto.toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ),
      ),
      body: _errorMessage != null
          ? _ErrorView(
              message: _errorMessage!,
              onRetry: () {
                setState(() {
                  _errorMessage = null;
                  _isLoading = true;
                });
                _controller.loadRequest(Uri.parse(widget.approveUrl));
              },
              onCancel: () => Navigator.of(context).pop(const PayPalCancelled()),
            )
          : Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_isLoading)
                  const LinearProgressIndicator(minHeight: 3),
              ],
            ),
    );
  }
}


class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.onCancel,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_outlined, size: 56, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'No se pudo cargar PayPal',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.tonal(
                  onPressed: onCancel,
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
