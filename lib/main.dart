import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:provider/provider.dart';

import 'config/app_config.dart';
import 'providers/emergency_provider.dart';
import 'providers/session_provider.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/solicitud_detalle_screen.dart';
import 'screens/taller_inbox_screen.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';
import 'services/offline_queue_service.dart';
import 'services/sync_service.dart';
import 'services/tracking_ws_service.dart';


final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // mapbox_maps_flutter es un plugin nativo (Android/iOS) y NO soporta web:
  // su setAccessToken ejecuta bool.fromEnvironment en contexto no-const, lo
  // que crashea el bootstrap en Chrome (DDC) ANTES de runApp() — la app queda
  // clavada en el splash "Cargando…". En web lo saltamos; el mapa nativo no
  // se renderiza en navegador de todas formas.
  if (!kIsWeb && AppConfig.hasMapboxAccessToken) {
    MapboxOptions.setAccessToken(AppConfig.mapboxAccessToken);
  }
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  // El handler de background de FCM depende de un service worker; en web (sin
  // configuración FCM web) registrarlo también aborta el arranque. Solo nativo.
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(NotificationService.firebaseMessagingBackgroundHandler);
  }
  runApp(const EmergencyApp());
}


class EmergencyApp extends StatefulWidget {
  const EmergencyApp({super.key});

  @override
  State<EmergencyApp> createState() => _EmergencyAppState();
}

class _EmergencyAppState extends State<EmergencyApp> with WidgetsBindingObserver {
  bool _pushInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPush();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Pause WebSocket on background, resume on foreground.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final context = _navigatorKey.currentContext;
    if (context == null) return;

    final session = context.read<SessionProvider>();
    final token = session.token;
    final ws = context.read<TrackingWsService>();

    if (state == AppLifecycleState.resumed && token != null) {
      // Propagate the tenant so the backend hub partitions broadcasts
      // by organization — a Tenant A client must never receive Tenant B's events.
      ws.connect(token, tenant: session.tenant);
    } else if (state == AppLifecycleState.paused) {
      ws.disconnect();
    }
  }

  Future<void> _initPush() async {
    // Push notifications (FCM) no funcionan en web sin configuración extra;
    // evitamos inicializarlas en Chrome para no ensuciar la consola ni
    // arriesgar excepciones post-arranque.
    if (kIsWeb || _pushInitialized) return;
    _pushInitialized = true;
    await NotificationService.init(
      navigateFromUrl: _navigateFromUrl,
      showForegroundAlert: _showForegroundAlert,
    );
  }

  Future<void> _showForegroundAlert(String title, String body, String payload) async {
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          content: Text(
            [
              if (title.trim().isNotEmpty) title.trim(),
              if (body.trim().isNotEmpty) body.trim(),
            ].join('\n'),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          action: payload.trim().isEmpty
              ? null
              : SnackBarAction(
                  label: 'Abrir',
                  onPressed: () => _navigateFromUrl(payload),
                ),
        ),
      );
  }

  void _navigateFromUrl(String url) {
    final uri = Uri.tryParse(url);
    final path = uri == null
        ? (url.startsWith('/') ? url : '/$url')
        : (uri.path.isNotEmpty ? uri.path : (url.startsWith('/') ? url : '/$url'));

    final context = _navigatorKey.currentContext;
    if (context == null) {
      return;
    }
    final session = context.read<SessionProvider>();
    if (!session.isAuthenticated) {
      session.setPendingRoute(path);
      _navigatorKey.currentState?.popUntil((route) => route.isFirst);
      return;
    }
    _navigatorKey.currentState?.pushNamed(path);
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (_) => ApiService()),
        ChangeNotifierProvider(
          create: (context) =>
              SessionProvider(context.read<ApiService>())..restaurarSesion(),
        ),
        ChangeNotifierProvider(
          create: (context) => EmergencyProvider(context.read<ApiService>()),
        ),
        // Persistent local queue for offline operations (SQLite-backed).
        ChangeNotifierProvider(create: (_) => OfflineQueueService()),
        // Connectivity + automatic sync orchestrator. Reads the queue and
        // flushes it through POST /sync/lote whenever the device is online.
        ChangeNotifierProxyProvider2<ApiService, OfflineQueueService, SyncService>(
          create: (context) => SyncService(
            queue: context.read<OfflineQueueService>(),
            api:   context.read<ApiService>(),
          ),
          update: (_, __, ___, previous) => previous!,
        ),
        // Real-time WebSocket tracking.
        ChangeNotifierProvider(create: (_) => TrackingWsService()),
      ],
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'Emergency Mobile',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
          useMaterial3: true,
        ),
        initialRoute: '/',
        onGenerateRoute: (settings) {
          final name = settings.name ?? '/';
          if (name == '/') {
            return MaterialPageRoute(
              builder: (context) => Consumer<SessionProvider>(
                builder: (context, session, _) {
                  if (session.isAuthenticated) {
                    final pending = session.pendingRoute;
                    if (pending != null && pending.isNotEmpty) {
                      WidgetsBinding.instance.addPostFrameCallback((_) async {
                        await session.clearPendingRoute();
                        _navigatorKey.currentState?.pushNamed(pending);
                      });
                    }
                    // _AuthenticatedShell handles one-shot service init.
                    return const _AuthenticatedShell();
                  }
                  return const LoginScreen();
                },
              ),
            );
          }

          final uri = Uri.tryParse(name);
          final path = uri?.path ?? name;
          final segments = path.split('/').where((item) => item.trim().isNotEmpty).toList();
          if (segments.length == 2 && segments.first == 'solicitudes') {
            final id = int.tryParse(segments[1]);
            if (id != null) {
              return MaterialPageRoute(
                builder: (_) => SolicitudDetalleScreen(solicitudId: id),
                settings: settings,
              );
            }
          }
          // Deep link desde push notification PROPUESTA_TALLER:
          //   /taller/inbox → bandeja del taller con propuestas pendientes.
          if (segments.length == 2 && segments.first == 'taller' && segments[1] == 'inbox') {
            return MaterialPageRoute(
              builder: (_) => const TallerInboxScreen(),
              settings: settings,
            );
          }

          return MaterialPageRoute(
            builder: (context) => Consumer<SessionProvider>(
              builder: (context, session, _) {
                if (session.isAuthenticated) {
                  return const _AuthenticatedShell();
                }
                return const LoginScreen();
              },
            ),
            settings: settings,
          );
        },
      ),
    );
  }
}

// ── Authenticated shell ────────────────────────────────────────────────────────

/// Wraps [HomeScreen] and initialises real-time services exactly once
/// when the user is authenticated, preventing duplicate subscriptions.
class _AuthenticatedShell extends StatefulWidget {
  const _AuthenticatedShell();

  @override
  State<_AuthenticatedShell> createState() => _AuthenticatedShellState();
}

class _AuthenticatedShellState extends State<_AuthenticatedShell> {
  bool _servicesInitialized = false;
  StreamSubscription<SolicitudWsUpdate>? _wsSub;

  String _formatSolicitudRealtimeMessage(SolicitudWsUpdate update) {
    final estado = update.estado.trim();
    if (estado.isEmpty) {
      return 'La solicitud #${update.solicitudId} recibió una actualización.';
    }
    return 'Solicitud #${update.solicitudId}: $estado';
  }

  void _showSolicitudRealtimeAlert(SolicitudWsUpdate update) {
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
            content: Text(
              _formatSolicitudRealtimeMessage(update),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            action: SnackBarAction(
              label: 'Ver',
              onPressed: () => _navigatorKey.currentState?.pushNamed('/solicitudes/${update.solicitudId}'),
            ),
          ),
        );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_servicesInitialized) return;

    final token = context.read<SessionProvider>().token;
    if (token == null) return;

    _servicesInitialized = true;

    // Wire up the token reader so the sync service can authenticate the
    // POST /sync/lote calls without forming a direct dependency on the
    // session provider.
    final session = context.read<SessionProvider>();
    final sync = context.read<SyncService>();
    sync.updateTokenProvider(() => session.token);

    // Initialise connectivity monitor + flush any pending queue rows.
    sync.initialize();

    final ws = context.read<TrackingWsService>();
    final emergency = context.read<EmergencyProvider>();

    // token != null was already checked above, so we always have a tenant.
    ws.connect(token, tenant: session.tenant);

    // Single subscription — forward WS state changes to EmergencyProvider.
    _wsSub = ws.solicitudStream.listen((update) {
      emergency.applyWsSolicitudUpdate(
        solicitudId: update.solicitudId,
        estado: update.estado,
      );
      _showSolicitudRealtimeAlert(update);
    });
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const HomeScreen();
}
