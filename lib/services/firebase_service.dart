import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'firebase_options.dart';

/// Firebase service to handle initialization, token management, and FCM setup.
class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();

  late FirebaseMessaging _firebaseMessaging;
  late SharedPreferences _prefs;

  // Callbacks for notification handling
  Function(RemoteMessage)? onForegroundMessage;
  Function(RemoteMessage)? onMessageOpenedFromTerminatedApp;

  FirebaseService._internal();

  factory FirebaseService() {
    return _instance;
  }

  /// Initialize Firebase and set up messaging handlers
  Future<void> initialize() async {
    try {
      // Initialize Firebase
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      _firebaseMessaging = FirebaseMessaging.instance;
      _prefs = await SharedPreferences.getInstance();

      debugPrint('✓ Firebase initialized');

      // Request notification permissions (iOS 13+, Android 13+)
      await _requestPermissions();

      // Get and store device token
      await _retrieveAndStoreToken();

      // Set up message handlers
      _setupMessageHandlers();

      debugPrint('✓ Firebase setup complete');
    } catch (e) {
      debugPrint('✗ Firebase initialization error: $e');
      rethrow;
    }
  }

  /// Request notification permissions from the user
  Future<void> _requestPermissions() async {
    final settings = await _firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    debugPrint(
      'User notification permission status: ${settings.authorizationStatus}',
    );
  }

  /// Retrieve FCM token and store it locally and on backend
  Future<void> _retrieveAndStoreToken() async {
    try {
      final token = await _firebaseMessaging.getToken();

      if (token != null) {
        // Store locally
        await _prefs.setString('fcm_token', token);
        debugPrint('✓ FCM Token stored: $token');

        // Token will be sent to backend when user logs in
        // See: sendTokenToBackend()
      }
    } catch (e) {
      debugPrint('✗ Error retrieving FCM token: $e');
    }
  }

  /// Listen for token refresh and update backend automatically
  void _setupTokenRefreshListener() {
    _firebaseMessaging.onTokenRefresh.listen((newToken) {
      debugPrint('✓ FCM Token refreshed: $newToken');
      _prefs.setString('fcm_token', newToken);

      // If user is logged in, send new token to backend
      final userId = _prefs.getString('user_id');
      if (userId != null && userId.isNotEmpty) {
        sendTokenToBackend(userId: userId, deviceType: 'android');
      }
    });
  }

  /// Set up message handlers for different app states
  void _setupMessageHandlers() {
    // 1. Foreground message handler
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint(
        '✓ Foreground message received: ${message.notification?.title}',
      );
      onForegroundMessage?.call(message);
    });

    // 2. Background message handler (when app is in background but not terminated)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint(
        '✓ Message opened from background: ${message.notification?.title}',
      );
      _handleNotificationTap(message);
    });

    // 3. Terminated app handler (check for initial message)
    _firebaseMessaging.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        debugPrint('✓ App opened from terminated state via notification');
        _handleNotificationTap(message);
      }
    });

    // 4. Token refresh listener
    _setupTokenRefreshListener();
  }

  /// Handle notification tap (navigate to relevant screen)
  void _handleNotificationTap(RemoteMessage message) {
    final data = message.data;
    final notificationType = data['type'] ?? '';

    debugPrint('Notification tapped - Type: $notificationType');
    onMessageOpenedFromTerminatedApp?.call(message);

    // Routing logic can be implemented here or in main.dart
    // Example: if notificationType == 'transaction' -> navigate to transaction details
  }

  /// Get stored FCM token
  Future<String?> getToken() async {
    return _prefs.getString('fcm_token');
  }

  /// Send FCM token to backend API
  /// Call this after user logs in or registers
  Future<bool> sendTokenToBackend({
    required String userId,
    String deviceType = 'android', // or 'ios'
  }) async {
    try {
      final token = await getToken();

      if (token == null || token.isEmpty) {
        debugPrint('✗ No FCM token available');
        return false;
      }

      // Determine device type if not provided
      final detectedDeviceType = _getDeviceType();

      final response = await http
          .post(
            Uri.parse('https://api.mkdata.com.ng/api/device/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_id': userId,
              'fcm_token': token,
              'device_type': deviceType.isEmpty
                  ? detectedDeviceType
                  : deviceType,
            }),
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              debugPrint('✗ Token registration timeout');
              return http.Response('timeout', 408);
            },
          );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('✓ FCM token sent to backend');
        return true;
      } else {
        debugPrint('✗ Failed to send token to backend: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('✗ Error sending token to backend: $e');
      return false;
    }
  }

  /// Detect device type (Android or iOS)
  String _getDeviceType() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'android';
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return 'ios';
    }
    return 'unknown';
  }

  /// Clear stored token (call on logout)
  Future<void> clearToken() async {
    await _prefs.remove('fcm_token');
    debugPrint('✓ FCM token cleared');
  }
}
