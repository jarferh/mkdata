import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import './pages/splash_page.dart';
import './pages/dashboard_page.dart';
import './pages/pin_login_page.dart';
import './pages/login_page.dart';
import './pages/airtime_page.dart';
import './pages/wallet_page.dart';
import './pages/account_page.dart';
import './pages/welcome_page.dart';
import './pages/onboarding_page.dart';
import './services/firebase_service.dart';
import './services/notification_service.dart';
import './services/api_service.dart';

/// Background message handler (must be a top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('✓ Handling background message: ${message.notification?.title}');
  // Note: Firebase initialization may not be complete in background handler
  // Just log the message; foreground handler will display notifications
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set app timezone to GMT+1 (Africa/Lagos)
  // Note: Dart uses UTC internally; UI formatting handles timezone conversion

  // Initialize Firebase
  try {
    await FirebaseService().initialize();
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
  }

  // Initialize local notifications
  try {
    await NotificationService().initialize();
  } catch (e) {
    debugPrint('Notification service initialization failed: $e');
  }

  // Register background message handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const MyApp());
}

// Wrapper that forces the back button to exit the app when showing an
// unlock/lock screen. This prevents dismissing the welcome/pin screen
// by pressing the back button; instead the app will close.
class _LockScreenWrapper extends StatelessWidget {
  final Widget child;

  const _LockScreenWrapper({required this.child});

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Close the app when the user attempts to pop the lock screen.
        SystemNavigator.pop();
        return false;
      },
      child: child,
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  bool _requirePinOnResume = false;
  DateTime? _pausedTime;
  final Duration _lockDelay = const Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Listen for authentication failures and auto-logout
    ApiService.authFailure.listen((_) {
      debugPrint('Auth failure detected, logging out user');
      _handleAutoLogout();
    });

    // Set up foreground notification handler
    final firebaseService = FirebaseService();
    final notificationService = NotificationService();

    firebaseService.onForegroundMessage = (RemoteMessage message) {
      // Display notification when app is in foreground
      notificationService.displayForegroundNotification(message);
    };

    firebaseService.onMessageOpenedFromTerminatedApp = (RemoteMessage message) {
      debugPrint('App opened from terminated state via notification');
      // Navigate to relevant page based on notification payload
      // This is handled by NotificationService._routeNotification()
    };
  }

  Future<void> _handleAutoLogout() async {
    try {
      final nav = _navKey.currentState;
      final context = _navKey.currentContext;

      // Show modal dialog first
      if (context != null && nav != null && nav.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: const Text('Session Expired'),
            content: const Text(
              'Your session has expired. Please log in again to continue.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  // After modal closes, proceed with logout and navigation
                  _proceedWithLogout(nav);
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else {
        // If no context, proceed directly with logout
        _proceedWithLogout(nav);
      }
    } catch (e) {
      debugPrint('Error during auto-logout: $e');
      final nav = _navKey.currentState;
      if (nav != null && nav.mounted) {
        nav.pushNamedAndRemoveUntil('/login', (route) => false);
      }
    }
  }

  Future<void> _proceedWithLogout(NavigatorState? nav) async {
    try {
      // Clear auth data
      await ApiService().clearAuth();

      // Navigate to login
      if (nav != null && nav.mounted) {
        nav.pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } catch (e) {
      debugPrint('Error during logout: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      // Store the time when the app was paused
      _pausedTime = DateTime.now();
    } else if (state == AppLifecycleState.detached) {
      // For detached state, always require PIN
      _requirePinOnResume = true;
      _pausedTime = null;
    } else if (state == AppLifecycleState.resumed) {
      if (_pausedTime != null) {
        // Check if more than 30 seconds have passed
        final timeDifference = DateTime.now().difference(_pausedTime!);
        if (timeDifference >= _lockDelay) {
          _requirePinOnResume = true;
        }
      }

      if (_requirePinOnResume) {
        _requirePinOnResume = false;
        _pausedTime = null;
        // On resume, route depending on login state: welcome (if logged in) or login (if not)
        // Delay the navigation slightly so it doesn't run while the Navigator
        // is rebuilding or locked by the framework.
        Future.delayed(const Duration(milliseconds: 200), () async {
          try {
            final prefs = await SharedPreferences.getInstance();
            final loggedIn = prefs.getString('user_data') != null;
            final nav = _navKey.currentState;
            if (nav != null && nav.mounted) {
              if (!loggedIn) {
                // If not logged in, send user to login and clear stack.
                nav.pushNamedAndRemoveUntil('/login', (route) => false);
              } else {
                // If logged in, present the WelcomePage modally so the user
                // unlocks and returns to the exact page they left after entering PIN.
                nav.push(
                  MaterialPageRoute(
                    builder: (_) => _LockScreenWrapper(
                      child: const WelcomePage(restorePrevious: true),
                    ),
                    fullscreenDialog: true,
                  ),
                );
              }
            }
          } catch (e) {
            final nav = _navKey.currentState;
            if (nav != null && nav.mounted) {
              nav.pushNamedAndRemoveUntil('/login', (route) => false);
            }
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navKey,
      title: 'MK DATA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.red,
        scaffoldBackgroundColor: Colors.white,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashPage(),
        '/dashboard': (context) => const DashboardPage(),
        '/pin-login': (context) => const PinLoginPage(),
        '/login': (context) => const LoginPage(),
        '/airtime': (context) => const AirtimePage(),
        '/wallet': (context) => const WalletPage(),
        '/account': (context) => const AccountPage(),
        '/welcome': (context) => const WelcomePage(),
        '/onboarding': (context) => const OnboardingPage(),
      },
    );
  }
}
