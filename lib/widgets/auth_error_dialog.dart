import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../pages/login_page.dart';
import '../services/api_service.dart';
import 'password_verification_dialog.dart';

class AuthErrorDialog extends StatefulWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const AuthErrorDialog({
    this.title = 'Session Expired',
    this.message =
        'Your login session has expired. Please login again to continue.',
    this.onRetry,
    super.key,
  });

  static Future<void> show(
    BuildContext context, {
    String title = 'Session Expired',
    String message =
        'Your login session has expired. Please login again to continue.',
    VoidCallback? onRetry,
  }) {
    try {
      return showDialog(
        context: context,
        // ensure dialog attaches to root navigator so it appears above all routes
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (dialogContext) =>
            AuthErrorDialog(title: title, message: message, onRetry: onRetry),
      );
    } catch (e) {
      // If showing dialog fails for any reason, log and return a completed future.
      debugPrint('AuthErrorDialog.show error: $e');
      return Future.value();
    }
  }

  @override
  State<AuthErrorDialog> createState() => _AuthErrorDialogState();
}

class _AuthErrorDialogState extends State<AuthErrorDialog> {
  bool _isVerifying = false;

  Future<void> _showPasswordVerification() async {
    setState(() => _isVerifying = true);

    try {
      // Close the error dialog first
      if (mounted) Navigator.pop(context);

      // Fetch stored user email to show in the verification dialog (like WelcomePage)
      final prefs = await SharedPreferences.getInstance();
      String? userEmail;
      final userDataJson = prefs.getString('user_data');
      if (userDataJson != null) {
        try {
          final user = Map<String, dynamic>.from(jsonDecode(userDataJson));
          userEmail = user['sEmail'] ?? user['email'];
        } catch (e) {
          debugPrint('AuthErrorDialog: failed to parse user_data: $e');
        }
      }

      // Show the password verification dialog using the shared static show()
      final result = await PasswordVerificationDialog.show(
        context,
        userEmail: userEmail,
      );

      // If verification succeeded, call onRetry if provided so callers can continue
      if (result == true) {
        if (widget.onRetry != null) widget.onRetry!.call();
        return;
      }

      // If user chose to logout (result == false), navigate to login
      if (result == false) {
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const LoginPage()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      debugPrint('Error showing password verification: $e');
      if (mounted) {
        setState(() => _isVerifying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _logout() async {
    setState(() => _isVerifying = true);

    try {
      // Clear all stored user data from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_data');
      await prefs.remove('php_cookie');
      await prefs.remove('update_skip_time');
      await prefs.remove('login_pin');
      await prefs.remove('biometric_enabled');

      // Clear auth data using ApiService
      await ApiService().clearAuth();

      if (mounted) {
        // Close the dialog
        Navigator.pop(context);

        // Navigate to login page and clear navigation stack
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginPage()),
          (route) => false,
        );
      }
    } catch (e) {
      print('Error during logout: $e');
      if (mounted) {
        setState(() => _isVerifying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error logging out: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 8,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFf05533), Color(0xFFce4323)],
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with icon
              Container(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Column(
                  children: [
                    // Error Icon
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.lock_outline,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Title
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              // Message content
              Container(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Message text
                    Text(
                      widget.message,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        height: 1.6,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),

                    // Info box with tips
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.white.withOpacity(0.9),
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'For security, please login again with your credentials.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withOpacity(0.9),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Logout Button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isVerifying
                            ? null
                            : _showPasswordVerification,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          disabledBackgroundColor: Colors.white.withOpacity(
                            0.6,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: _isVerifying
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Color(0xFFce4323),
                                  ),
                                ),
                              )
                            : const Text(
                                'Verify & Continue',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFce4323),
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 12),
                    // Logout Button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: TextButton(
                        onPressed: _isVerifying ? null : _logout,
                        style: TextButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: Colors.white.withOpacity(0.5),
                              width: 1.5,
                            ),
                          ),
                        ),
                        child: Text(
                          'Login Again',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withOpacity(0.95),
                          ),
                        ),
                      ),
                    ),

                    if (widget.onRetry != null) ...[
                      const SizedBox(height: 12),
                      // Retry Button (optional)
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: TextButton(
                          onPressed: _isVerifying
                              ? null
                              : () {
                                  Navigator.pop(context);
                                  widget.onRetry?.call();
                                },
                          style: TextButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                color: Colors.white.withOpacity(0.5),
                                width: 1.5,
                              ),
                            ),
                          ),
                          child: Text(
                            'Retry',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withOpacity(0.95),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
