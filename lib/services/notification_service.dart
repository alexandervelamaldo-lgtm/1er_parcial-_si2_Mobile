import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:open_filex/open_filex.dart';

typedef NavigateFromUrl = void Function(String url);
typedef ShowForegroundAlert = Future<void> Function(String title, String body, String payload);

class NotificationService {
  static final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  static const String _debugServerUrl = 'http://192.168.0.23:7777/event';
  static const String _debugSessionId = 'cloud-push-delivery';

  static const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'emergency_alerts',
    'Alertas críticas',
    description: 'Notificaciones de alta prioridad para incidencias nuevas',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static NavigateFromUrl? _navigate;
  static ShowForegroundAlert? _showForegroundAlert;

  // #region debug-point D:mobile-fcm-report
  static Future<void> _debugReport(
    String hypothesisId,
    String location,
    String msg,
    Map<String, dynamic> data,
  ) async {
    try {
      final client = HttpClient();
      final request = await client.postUrl(Uri.parse(_debugServerUrl));
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.write(jsonEncode({
        'sessionId': _debugSessionId,
        'runId': 'pre-fix',
        'hypothesisId': hypothesisId,
        'location': location,
        'msg': '[DEBUG] $msg',
        'data': data,
        'ts': DateTime.now().millisecondsSinceEpoch,
      }));
      await request.close();
      client.close(force: true);
    } catch (_) {}
  }
  // #endregion

  static String _readStringData(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return '';
  }

  static void _openPayload(String payload) {
    final p = payload.trim();
    if (p.isEmpty) return;
    if (p.endsWith('.pdf') || p.endsWith('.xlsx')) {
      OpenFilex.open(p);
      return;
    }
    _navigate?.call(p);
  }

  static ({String title, String body, String payload}) _resolveContent(RemoteMessage message) {
    final title =
        message.notification?.title ??
        _readStringData(message.data, const [
          'title',
          'titulo',
          'subject',
        ]);
    final body =
        message.notification?.body ??
        _readStringData(message.data, const [
          'body',
          'mensaje',
          'message',
          'description',
        ]);
    final payload = _readStringData(message.data, const [
      'url',
      'deep_link',
      'deepLink',
      'route',
      'path',
      'attachment_url',
      'attachmentUrl',
    ]);
    return (title: title, body: body, payload: payload);
  }

  static Future<void> init({
    required NavigateFromUrl navigateFromUrl,
    ShowForegroundAlert? showForegroundAlert,
  }) async {
    _navigate = navigateFromUrl;
    _showForegroundAlert = showForegroundAlert;

    try {
      await _local.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload == null || payload.trim().isEmpty) return;
          _openPayload(payload);
        },
      );

      final android = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(channel);
    } catch (_) {}

    try {
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (_) {}

    FirebaseMessaging.onMessage.listen((message) async {
      // #region debug-point D:mobile-on-message
      await _debugReport(
        'D',
        'mobile/lib/services/notification_service.dart:onMessage',
        'foreground FCM message received',
        {
          'message_id': message.messageId,
          'title': message.notification?.title,
          'body': message.notification?.body,
          'data_keys': message.data.keys.toList()..sort(),
          'from': message.from,
        },
      );
      // #endregion
      final content = await showFromFcm(message);
      if (_showForegroundAlert != null && (content.title.isNotEmpty || content.body.isNotEmpty)) {
        await _showForegroundAlert!.call(content.title, content.body, content.payload);
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) async {
      // #region debug-point D:mobile-on-opened
      await _debugReport(
        'D',
        'mobile/lib/services/notification_service.dart:onMessageOpenedApp',
        'notification tap opened app',
        {
          'message_id': message.messageId,
          'data_keys': message.data.keys.toList()..sort(),
        },
      );
      // #endregion
      final payload = _readStringData(message.data, const [
        'url',
        'deep_link',
        'deepLink',
        'route',
        'path',
      ]);
      _openPayload(payload);
    });

    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        // #region debug-point D:mobile-initial-message
        await _debugReport(
          'D',
          'mobile/lib/services/notification_service.dart:getInitialMessage',
          'initial notification message detected',
          {
            'message_id': initial.messageId,
            'data_keys': initial.data.keys.toList()..sort(),
          },
        );
        // #endregion
        final payload = _readStringData(initial.data, const [
          'url',
          'deep_link',
          'deepLink',
          'route',
          'path',
        ]);
        _openPayload(payload);
      }
    } catch (_) {}
  }

  @pragma('vm:entry-point')
  static Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
    } catch (_) {}

    try {
      await Firebase.initializeApp();
    } catch (_) {}

    try {
      final android = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(channel);
    } catch (_) {}

    // #region debug-point D:mobile-background-message
    await _debugReport(
      'D',
      'mobile/lib/services/notification_service.dart:firebaseMessagingBackgroundHandler',
      'background FCM message received',
      {
        'message_id': message.messageId,
        'title': message.notification?.title,
        'body': message.notification?.body,
        'data_keys': message.data.keys.toList()..sort(),
      },
    );
    // #endregion
    await showFromFcm(message);
  }

  static Future<({String title, String body, String payload})> showFromFcm(RemoteMessage message) async {
    final content = _resolveContent(message);
    final title = content.title;
    final body = content.body;
    final payload = content.payload;

    if (title.trim().isEmpty && body.trim().isEmpty) return content;

    try {
      // #region debug-point D:mobile-show-local
      await _debugReport(
        'D',
        'mobile/lib/services/notification_service.dart:showFromFcm',
        'rendering local notification from FCM payload',
        {
          'message_id': message.messageId,
          'title': title,
          'body': body,
          'payload': payload,
        },
      );
      // #endregion
      await _local.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title.isEmpty ? 'Emergencia' : title,
        body.isEmpty ? 'Nueva incidencia registrada.' : body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'emergency_alerts',
            'Alertas críticas',
            channelDescription: 'Notificaciones de alta prioridad para incidencias nuevas',
            importance: Importance.max,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
            enableVibration: true,
            playSound: true,
            category: AndroidNotificationCategory.alarm,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: payload,
      );
    } catch (_) {}
    return content;
  }
}
