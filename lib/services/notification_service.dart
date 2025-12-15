import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';

/// Service to display and handle local notifications
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  late FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin;

  NotificationService._internal();

  factory NotificationService() {
    return _instance;
  }

  /// Initialize local notifications
  Future<void> initialize() async {
    _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    // Android initialization
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS initialization
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
          requestSoundPermission: true,
          requestBadgePermission: true,
          requestAlertPermission: true,
        );

    final InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
        );

    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    debugPrint('✓ Local notifications initialized');
  }

  /// Display foreground notification
  Future<void> displayForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;

    if (notification == null) return;

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance Notifications',
          channelDescription:
              'This channel is used for important notifications.',
          importance: Importance.max,
          priority: Priority.high,
          showWhen: true,
        );

    const DarwinNotificationDetails iOSPlatformChannelSpecifics =
        DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        );

    NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );

    await _flutterLocalNotificationsPlugin.show(
      notification.hashCode,
      notification.title,
      notification.body,
      platformChannelSpecifics,
      payload: _encodePayload(message.data),
    );

    debugPrint('✓ Foreground notification displayed: ${notification.title}');
  }

  /// Encode notification payload for passing to tap handler
  String _encodePayload(Map<String, dynamic> data) {
    return data.entries.map((e) => '${e.key}=${e.value}').join('&');
  }

  /// Decode notification payload
  static Map<String, String> _decodePayload(String? payload) {
    final result = <String, String>{};
    if (payload == null || payload.isEmpty) return result;

    final pairs = payload.split('&');
    for (final pair in pairs) {
      final keyValue = pair.split('=');
      if (keyValue.length == 2) {
        result[keyValue[0]] = keyValue[1];
      }
    }
    return result;
  }

  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    final payload = _decodePayload(response.payload);
    debugPrint('✓ Notification tapped - Payload: $payload');

    // Route based on notification type
    _routeNotification(payload);
  }

  /// Route notification based on type
  void _routeNotification(Map<String, String> payload) {
    final notificationType = payload['type'] ?? '';

    switch (notificationType) {
      case 'transaction':
        final transactionId = payload['transaction_id'] ?? '';
        debugPrint('Navigate to transaction details: $transactionId');
        // TODO: Implement navigation to transaction details page
        break;

      case 'wallet':
        debugPrint('Navigate to wallet page');
        // TODO: Implement navigation to wallet page
        break;

      case 'promotion':
        debugPrint('Navigate to promotions/offers');
        // TODO: Implement navigation to promotions page
        break;

      default:
        debugPrint('Navigate to home');
      // TODO: Navigate to home/dashboard
    }
  }
}
