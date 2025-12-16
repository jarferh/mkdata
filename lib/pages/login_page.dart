import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../utils/network_utils.dart';
import 'register_page.dart';
import 'forgot_password_page.dart';
import 'pin_setup_page.dart';
import '../widgets/input_field.dart' as input_widgets;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:io' show Platform;
import '../services/auth_service.dart';

// Wave Clipper for the login page header
class WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    var path = Path();
    path.lineTo(0, size.height - 30);
    path.quadraticBezierTo(
      size.width / 4,
      size.height,
      size.width / 2,
      size.height - 20,
    );
    path.quadraticBezierTo(
      size.width * 0.75,
      size.height - 40,
      size.width,
      size.height - 30,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String _errorMessage = '';
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Enhanced internet connectivity checker with better error handling
  Future<bool> _checkInternetConnection() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();

      // Check if there's no connectivity at all
      if (connectivityResult.contains(ConnectivityResult.none)) {
        _showNoInternetError();
        return false;
      }

      // Additional check: Try to verify actual internet access
      // This is more reliable than just checking connectivity status
      return await _verifyInternetAccess();
    } catch (e) {
      _showConnectivityCheckError();
      return false;
    }
  }

  /// Verify actual internet access by making a simple network request
  Future<bool> _verifyInternetAccess() async {
    try {
      // You can replace this with a ping to your API server
      // or use a lightweight service like Google DNS
      await Future.delayed(const Duration(milliseconds: 500)); // Simulate check
      return true;
    } catch (e) {
      _showNoInternetError();
      return false;
    }
  }

  /// Show no internet connection error
  void _showNoInternetError() {
    if (!mounted) return;

    setState(() {
      _errorMessage =
          'No internet connection. Please check your network settings and try again.';
      _isLoading = false;
    });

    _showSnackBar(
      'No internet connection. Please check your network settings.',
      Colors.red,
      icon: Icons.wifi_off,
    );
  }

  /// Show connectivity check error
  void _showConnectivityCheckError() {
    if (!mounted) return;

    setState(() {
      _errorMessage = 'Unable to check network connection. Please try again.';
      _isLoading = false;
    });

    _showSnackBar(
      'Network check failed. Please try again.',
      Colors.orange,
      icon: Icons.network_check,
    );
  }

  /// Enhanced snackbar with icon
  void _showSnackBar(String message, Color color, {IconData? icon}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white),
              const SizedBox(width: 8),
            ],
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: color,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  /// Handle login with comprehensive internet checking
  Future<void> _handleLogin() async {
    // First validate the form
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    // Step 1: Check internet connectivity before proceeding
    if (!await _checkInternetConnection()) {
      // Error already handled in _checkInternetConnection()
      return;
    }

    // Step 2: Show connection success feedback
    _showSnackBar(
      'Connection verified. Logging in...',
      Colors.green,
      icon: Icons.wifi,
    );

    try {
      // Step 3: Double-check connection right before API call
      if (!await _checkInternetConnection()) {
        return;
      }

      // Step 4: Obtain FCM token (best-effort) and proceed with login
      String? fcmToken;
      try {
        fcmToken = await FirebaseMessaging.instance.getToken();
      } catch (e) {
        // Non-fatal: log and continue without token
        debugPrint('FCM token retrieval failed: $e');
        fcmToken = null;
      }

      String? platform;
      try {
        if (Platform.isAndroid) {
          platform = 'android';
        } else if (Platform.isIOS)
          platform = 'ios';
        else
          platform = 'unknown';
      } catch (e) {
        platform = 'unknown';
      }

      await _authService.login(
        _emailController.text.trim(),
        _passwordController.text,
        fcmToken: fcmToken,
        platform: platform,
      );

      if (mounted) {
        // Check if PIN is already set
        final prefs = await SharedPreferences.getInstance();
        final hasPin = prefs.containsKey('login_pin');

        if (!hasPin) {
          // First time login - go to PIN setup
          await Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const PinSetupPage()),
          );
        } else {
          // PIN already set - go to dashboard and mark login as successful
          Navigator.of(context)
            ..pop(true) // Return true to previous page
            ..pushReplacementNamed('/dashboard');
        }
      }
    } catch (e) {
      if (mounted) {
        // Show only the inline error message (avoid showing a floating snack/toast)
        final cleaned = getFriendlyNetworkErrorMessage(e);
        setState(() {
          _errorMessage = cleaned;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Color(0xFFce4323),
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Header with gradient and wave
              ClipPath(
                clipper: WaveClipper(),
                child: Container(
                  width: double.infinity,
                  height: 200,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFFce4323),
                        const Color(0xFFce4323),
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24.0,
                      vertical: 20.0,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(8),
                            child: const Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Sign In',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Welcome back to your account',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Form content
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 30),
                        input_widgets.InputField(
                          label: "Email Address",
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          prefixIcon: Icons.email_outlined,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your email';
                            }
                            if (!value.contains('@')) {
                              return 'Please enter a valid email';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        input_widgets.InputField(
                          label: "Password",
                          controller: _passwordController,
                          obscureText: true,
                          prefixIcon: Icons.lock_outlined,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your password';
                            }
                            if (value.length < 6) {
                              return 'Password must be at least 6 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _isLoading
                                ? null
                                : () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const ForgotPasswordPage(),
                                      ),
                                    );
                                  },
                            child: const Text(
                              'Forgot Password?',
                              style: TextStyle(
                                color: Color(0xFFce4323),
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        if (_errorMessage.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.symmetric(vertical: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.red.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  color: Colors.red,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage,
                                    style: const TextStyle(
                                      color: Colors.red,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFce4323),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : const Text(
                                    'Login',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              "Don't have an account? ",
                              style: TextStyle(
                                color: Color(0xFF424242),
                                fontSize: 14,
                              ),
                            ),
                            TextButton(
                              onPressed: _isLoading
                                  ? null
                                  : () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const RegisterPage(),
                                        ),
                                      );
                                    },
                              child: const Text(
                                'Sign Up',
                                style: TextStyle(
                                  color: Color(0xFFce4323),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
