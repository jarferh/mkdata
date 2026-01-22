import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../utils/network_utils.dart';
import '../services/api_service.dart';
import '../widgets/password_verification_dialog.dart';

class WelcomePage extends StatefulWidget {
  final bool restorePrevious;

  const WelcomePage({super.key, this.restorePrevious = false});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final List<TextEditingController> _pinControllers = List.generate(
    4,
    (index) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(4, (index) => FocusNode());
  final LocalAuthentication _localAuth = LocalAuthentication();
  String _errorMessage = '';
  String? _userName;
  String? _profilePhotoPath;
  bool _isBiometricEnabled = false;
  bool _isVerifying = false;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _loadUserName();
    _loadProfilePhoto();
    _loadBiometricSettings();
    _pinControllers[0].addListener(_onPinChanged);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.black,
        statusBarIconBrightness: Brightness.light, // Android
        statusBarBrightness: Brightness.dark, // iOS
      ),
    );
  }

  void _onPinChanged() {
    setState(() {});
    if (_pinControllers[0].text.length == 4) {
      SystemChannels.textInput.invokeMethod('TextInput.hide');
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) FocusScope.of(context).unfocus();
      });
    }
  }

  // Responsive helpers similar to dashboard_page
  double getResponsiveSize(BuildContext context, double baseSize) {
    double screenWidth = MediaQuery.of(context).size.width;
    double scaleFactor = screenWidth / 375; // base width
    return baseSize * scaleFactor.clamp(0.7, 1.3);
  }

  EdgeInsets getResponsivePadding(BuildContext context, double basePadding) {
    double scaleFactor = MediaQuery.of(context).size.width / 375;
    double responsivePadding = basePadding * scaleFactor.clamp(0.8, 1.2);
    return EdgeInsets.all(responsivePadding);
  }

  Future<void> _loadBiometricSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isBiometricEnabled = prefs.getBool('biometric_enabled') ?? false;
    });
  }

  Future<void> _handleBiometricTap() async {
    if (_isBiometricEnabled) {
      // Show loading on the PROCEED button while biometric auth is in progress
      if (mounted) setState(() => _isVerifying = true);
      try {
        await _authenticateWithBiometrics();
      } finally {
        if (mounted) setState(() => _isVerifying = false);
      }
      return;
    }

    // Show a toast-style floating SnackBar with app icon on the right
    final message =
        'Fingerprint is not enabled , please enable fingerprint in your profile setting';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: getResponsiveSize(context, 14),
                ),
              ),
            ),
            SizedBox(width: getResponsiveSize(context, 8)),
            Image.asset(
              'assets/images/app_icon.png',
              width: getResponsiveSize(context, 28),
              height: getResponsiveSize(context, 28),
              fit: BoxFit.contain,
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.black87,
        margin: EdgeInsets.symmetric(
          horizontal: getResponsiveSize(context, 24),
          vertical: getResponsiveSize(context, 10),
        ),
        duration: const Duration(seconds: 3),
        padding: EdgeInsets.all(getResponsiveSize(context, 12)),
        // Increased border radius
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(getResponsiveSize(context, 20)),
        ),
      ),
    );
  }

  Future<void> _authenticateWithBiometrics() async {
    if (!mounted) return;
    setState(() => _isVerifying = true);
    try {
      bool authenticated = await _localAuth.authenticate(
        localizedReason: 'Please authenticate to access your account',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (authenticated && mounted) {
        // First verify session with backend
        final isAuthenticated = await _checkAuthenticationStatus();
        if (!isAuthenticated) {
          if (mounted) _showSessionExpiredModal();
          return;
        }

        // Require internet before proceeding
        final ok = await _checkInternetConnection();
        if (!ok) {
          if (mounted) {
            showNetworkErrorSnackBar(
              context,
              'No internet connection. Please connect to the internet to continue.',
            );
          }
          return;
        }

        // Fetch transactions to further verify session and data availability
        try {
          final api = ApiService();
          final responseData = await api.get('check-session');
          if (responseData['status'] == 'success') {
            // proceed to dashboard
            if (mounted) {
              if (widget.restorePrevious) {
                Navigator.of(context).pop();
              } else {
                Navigator.of(context).pushReplacementNamed('/dashboard');
              }
            }
          } else {
            throw Exception(
              responseData['message'] ?? 'Session verification failed',
            );
          }
        } catch (e) {
          debugPrint('Biometric: error checking session: $e');
          final msg = e.toString();
          if (msg.contains('not authenticated') ||
              msg.contains('401') ||
              msg.contains('Session') ||
              msg.contains('expired')) {
            if (mounted) _showSessionExpiredModal();
          } else {
            if (mounted) {
              showNetworkErrorSnackBar(
                context,
                'Failed to verify session: ${e.toString()}',
              );
            }
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('Error during biometric authentication: $e');
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<bool> _checkInternetConnection() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      // Allow entry if any internet connection is available (wifi, mobile, etc.)
      // Only block if no internet connection is detected
      return connectivityResult != ConnectivityResult.none;
    } catch (e) {
      // If connectivity check fails, assume internet is available to not block user
      return true;
    }
  }

  Future<void> _loadUserName() async {
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString('user_data');
    if (userData != null) {
      final user = Map<String, dynamic>.from(
        // ignore: unnecessary_type_check
        userData is String ? jsonDecode(userData) : userData,
      );
      setState(() {
        _userName = user['sFname'] ?? 'User';
      });
    }
  }

  Future<void> _loadProfilePhoto() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final photoPath = prefs.getString('profile_photo_path');
      if (photoPath != null) {
        setState(() {
          _profilePhotoPath = photoPath;
        });
      }
    } catch (e) {
      print('Error loading profile photo: $e');
    }
  }

  @override
  void dispose() {
    for (var controller in _pinControllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  String get _enteredPin => _pinControllers.map((e) => e.text).join();

  void _verifyPin() async {
    if (_enteredPin.length != 4) {
      setState(() {
        _errorMessage = 'Please enter your 4-digit PIN';
      });
      return;
    }
    setState(() => _isVerifying = true);
    final prefs = await SharedPreferences.getInstance();
    final storedPin = prefs.getString('login_pin');

    try {
      if (_enteredPin == storedPin) {
        // Check if user is still authenticated
        final isAuthenticated = await _checkAuthenticationStatus();
        if (!isAuthenticated) {
          if (mounted) {
            // Show logout modal for expired session
            _showSessionExpiredModal();
          }
          return;
        }

        // Ensure internet is available before proceeding
        final ok = await _checkInternetConnection();
        if (!ok) {
          if (mounted) {
            showNetworkErrorSnackBar(
              context,
              'No internet connection. Please connect to the internet to continue.',
            );
          }
          return;
        }

        // Check session validity with lightweight API call
        debugPrint('Checking session validity...');
        try {
          final api = ApiService();
          final responseData = await api.get('check-session');

          if (responseData['status'] == 'success') {
            debugPrint('Session is valid, user authenticated');
            // Session check successful - user is authenticated
            if (mounted) {
              if (widget.restorePrevious) {
                Navigator.of(context).pop();
              } else {
                Navigator.of(context).pushReplacementNamed('/dashboard');
              }
            }
          } else {
            throw Exception(
              responseData['message'] ?? 'Session verification failed',
            );
          }
        } catch (e) {
          debugPrint('Error checking session: $e');
          // Check if it's an authentication error
          if (e.toString().contains('not authenticated') ||
              e.toString().contains('401') ||
              e.toString().contains('Session') ||
              e.toString().contains('expired')) {
            if (mounted) {
              // Show auth error dialog for expired session
              _showSessionExpiredModal();
            }
          } else {
            // Show generic error
            if (mounted) {
              showNetworkErrorSnackBar(
                context,
                'Failed to verify session: ${e.toString()}',
              );
            }
          }
          return;
        }
      } else {
        setState(() {
          _errorMessage = 'Incorrect PIN';
          for (var controller in _pinControllers) {
            controller.clear();
          }
          _focusNodes[0].requestFocus();
        });
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  void _logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_data');
      await prefs.remove('login_pin');
      await prefs.remove('php_cookie');
      await prefs.remove('update_skip_time');
      await prefs.remove('biometric_enabled');

      // Clear auth data using ApiService
      await ApiService().clearAuth();

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    } catch (e) {
      debugPrint('Error during logout: $e');
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    }
  }

  Future<bool> _checkAuthenticationStatus() async {
    try {
      debugPrint('Starting authentication check...');

      // Check if user_data exists in local storage first
      final prefs = await SharedPreferences.getInstance();
      final userData = prefs.getString('user_data');

      if (userData == null) {
        debugPrint('User data not found in local storage - session expired');
        return false;
      }

      // Add a small delay to ensure session is persisted on server
      // This helps with timing issues where session isn't fully written yet
      await Future.delayed(const Duration(milliseconds: 500));

      // Now verify with backend that session is still valid
      debugPrint('User data found locally, verifying with backend...');
      final apiService = ApiService();
      final isAuthenticated = await apiService
          .verifyAuthenticationWithBackend();

      if (isAuthenticated) {
        debugPrint('Backend confirmed: User is authenticated');
        return true;
      } else {
        debugPrint('Backend verification failed: Session expired or invalid');
        return false;
      }
    } catch (e) {
      debugPrint('Error in _checkAuthenticationStatus: $e');
      // If there's an error during verification, consider user not authenticated
      return false;
    }
  }

  void _showSessionExpiredModal() async {
    // Ensure we're on the main thread and the context is still valid
    if (!mounted) return;

    // Get user email for display
    final prefs = await SharedPreferences.getInstance();
    final userDataJson = prefs.getString('user_data');
    String? userEmail;

    if (userDataJson != null) {
      try {
        final userData = Map<String, dynamic>.from(jsonDecode(userDataJson));
        userEmail = userData['sEmail'];
      } catch (e) {
        debugPrint('Error parsing user data: $e');
      }
    }

    // Add a small delay to ensure the UI is ready
    Future.delayed(const Duration(milliseconds: 100), () async {
      if (mounted && context.mounted) {
        debugPrint('Showing password verification modal');
        // Show password verification dialog
        final result = await PasswordVerificationDialog.show(
          context,
          userEmail: userEmail,
        );

        // If user verified password (result == true), navigate to dashboard
        if (result == true && mounted) {
          debugPrint('Session renewed, proceeding to dashboard');
          if (widget.restorePrevious) {
            Navigator.of(context).pop();
          } else {
            Navigator.of(context).pushReplacementNamed('/dashboard');
          }
        } else if (result == false && mounted) {
          // User chose to logout
          debugPrint('User chose to logout');
          _logout();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFf05533),
              Color(0xFFce4323),
              Color(0xFF9d2e1a),
              Color(0xFF6b1f0f),
            ],
            stops: [0.0, 0.3, 0.6, 1.0],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              margin: EdgeInsets.symmetric(
                horizontal: getResponsiveSize(context, 16.0),
                vertical: getResponsiveSize(context, 20.0),
              ),
              padding: EdgeInsets.all(getResponsiveSize(context, 24.0)),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(
                  getResponsiveSize(context, 24),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Profile Avatar
                  Container(
                    width: getResponsiveSize(context, 100),
                    height: getResponsiveSize(context, 100),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: getResponsiveSize(context, 3),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        getResponsiveSize(context, 50),
                      ),
                      child:
                          _profilePhotoPath != null &&
                              _profilePhotoPath!.isNotEmpty
                          ? Image.file(
                              File(_profilePhotoPath!),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Image.asset(
                                  'assets/images/avatar.png',
                                  fit: BoxFit.cover,
                                );
                              },
                            )
                          : Image.asset(
                              'assets/images/avatar.png',
                              fit: BoxFit.cover,
                            ),
                    ),
                  ),
                  SizedBox(height: getResponsiveSize(context, 24)),

                  // Welcome Back Heading
                  Text(
                    'Welcome Back',
                    style: TextStyle(
                      fontSize: getResponsiveSize(context, 28),
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFce4323),
                    ),
                  ),
                  SizedBox(height: getResponsiveSize(context, 8)),

                  // Username
                  Text(
                    (_userName ?? 'User').toUpperCase(),
                    style: TextStyle(
                      fontSize: getResponsiveSize(context, 18),
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: getResponsiveSize(context, 32)),

                  // Fingerprint Button with Label
                  GestureDetector(
                    onTap: _handleBiometricTap,
                    child: Column(
                      children: [
                        Container(
                          width: getResponsiveSize(context, 80),
                          height: getResponsiveSize(context, 80),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.grey.shade100,
                          ),
                          child: Icon(
                            Icons.fingerprint,
                            size: getResponsiveSize(context, 48),
                            color: Colors.black54,
                          ),
                        ),
                        SizedBox(height: getResponsiveSize(context, 12)),
                        Text(
                          'Scan Your Fingerprint',
                          style: TextStyle(
                            fontSize: getResponsiveSize(context, 14),
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: getResponsiveSize(context, 32)),

                  // Password Input Field
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(
                        getResponsiveSize(context, 12),
                      ),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: TextField(
                      controller: _pinControllers[0],
                      obscureText: !_showPassword,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: TextStyle(
                        fontSize: getResponsiveSize(context, 16),
                        color: Colors.black,
                      ),
                      decoration: InputDecoration(
                        hintText: 'PIN',
                        hintStyle: TextStyle(
                          fontSize: getResponsiveSize(context, 14),
                          color: Colors.grey,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: getResponsiveSize(context, 16),
                          vertical: getResponsiveSize(context, 12),
                        ),
                        counterText: '',
                        suffixIcon: GestureDetector(
                          onTap: () {
                            setState(() {
                              _showPassword = !_showPassword;
                            });
                          },
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: getResponsiveSize(context, 12),
                            ),
                            child: Icon(
                              _showPassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              color: const Color(0xFFce4323),
                              size: getResponsiveSize(context, 20),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_errorMessage.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(
                        top: getResponsiveSize(context, 8),
                      ),
                      child: Text(
                        _errorMessage,
                        style: TextStyle(
                          fontSize: getResponsiveSize(context, 12),
                          color: Colors.red[300],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  SizedBox(height: getResponsiveSize(context, 24)),

                  // Login Button
                  SizedBox(
                    width: double.infinity,
                    height: getResponsiveSize(context, 50),
                    child: ElevatedButton(
                      onPressed: _pinControllers[0].text.length == 4
                          ? _verifyPin
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFce4323),
                        disabledBackgroundColor: Colors.grey.shade300,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            getResponsiveSize(context, 12),
                          ),
                        ),
                      ),
                      child: _isVerifying
                          ? SizedBox(
                              width: getResponsiveSize(context, 20),
                              height: getResponsiveSize(context, 20),
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : Text(
                              'Login',
                              style: TextStyle(
                                fontSize: getResponsiveSize(context, 16),
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                  SizedBox(height: getResponsiveSize(context, 16)),

                  // Logout Link
                  GestureDetector(
                    onTap: () {
                      _logout();
                    },
                    child: Text(
                      'Not my Account? Logout',
                      style: TextStyle(
                        fontSize: getResponsiveSize(context, 14),
                        color: Colors.red[400],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
