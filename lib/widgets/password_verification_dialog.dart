import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/api_service.dart';

class PasswordVerificationDialog extends StatefulWidget {
  final String? userEmail;

  const PasswordVerificationDialog({this.userEmail, super.key});

  static Future<bool?> show(BuildContext context, {String? userEmail}) {
    return showDialog<bool?>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (context) => PasswordVerificationDialog(userEmail: userEmail),
    );
  }

  @override
  State<PasswordVerificationDialog> createState() =>
      _PasswordVerificationDialogState();
}

class _PasswordVerificationDialogState
    extends State<PasswordVerificationDialog> {
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _showPassword = false;
  String _errorMessage = '';

  Future<void> _renewSession() async {
    if (_passwordController.text.isEmpty) {
      setState(() => _errorMessage = 'Please enter your password');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final api = ApiService();

      // Get user ID from ApiService (more reliable than parsing user_data)
      final userId = await api.getUserId();

      if (userId == null) {
        setState(() => _errorMessage = 'User ID not found');
        return;
      }

      debugPrint('Password verification - User ID: $userId');
      debugPrint(
        'Password verification - Password: ${_passwordController.text.length} chars',
      );

      // Call renew-session endpoint
      final requestBody = {
        'user_id': userId,
        'password': _passwordController.text,
      };
      debugPrint('Sending renew-session request with: $requestBody');

      final response = await api.post('renew-session', requestBody);
      debugPrint('Renew-session response: $response');

      if (response['status'] == 'success') {
        // Session renewed successfully
        debugPrint('Session renewed successfully');

        // Save renewed user data to SharedPreferences
        if (response['data'] != null) {
          final prefs = await SharedPreferences.getInstance();
          final userData = response['data'] as Map<String, dynamic>;

          // Save user data
          await prefs.setString('user_data', jsonEncode(userData));
          debugPrint('Renewed user data saved to SharedPreferences');
        }

        if (mounted) {
          Navigator.pop(context, true); // Return true to indicate success
        }
      } else {
        // Extract just the message from the response
        String errorMessage = 'Failed to renew session';
        if (response is Map && response.containsKey('message')) {
          errorMessage = response['message'].toString();
        }
        setState(() => _errorMessage = errorMessage);
      }
    } catch (e) {
      debugPrint('Error renewing session: $e');
      // Extract just the message if it's a formatted error
      String errorMessage = e.toString();
      if (errorMessage.contains('Exception: ')) {
        errorMessage = errorMessage.replaceFirst('Exception: ', '');
      }
      setState(() => _errorMessage = errorMessage);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
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
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                child: Column(
                  children: [
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
                    const Text(
                      'Verify Your Identity',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              // Content
              Container(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Your session has expired. Please enter your password to continue.',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withOpacity(0.95),
                        height: 1.6,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),

                    // Email display
                    if (widget.userEmail != null)
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
                              Icons.email_outlined,
                              color: Colors.white.withOpacity(0.9),
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                widget.userEmail!,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white.withOpacity(0.9),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 20),

                    // Password input
                    TextField(
                      controller: _passwordController,
                      obscureText: !_showPassword,
                      enabled: !_isLoading,
                      style: const TextStyle(fontSize: 16, color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Enter your password',
                        hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 14,
                        ),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.15),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.white.withOpacity(0.3),
                            width: 1.5,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.white.withOpacity(0.3),
                            width: 1.5,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Colors.white,
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        suffixIcon: GestureDetector(
                          onTap: () {
                            setState(() => _showPassword = !_showPassword);
                          },
                          child: Icon(
                            _showPassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                      ),
                    ),

                    // Error message
                    if (_errorMessage.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _errorMessage,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    const SizedBox(height: 28),

                    // Verify button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _renewSession,
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
                        child: _isLoading
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

                    // Logout button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: TextButton(
                        onPressed: _isLoading
                            ? null
                            : () {
                                Navigator.pop(context, false);
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
                          'Logout',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withOpacity(0.95),
                          ),
                        ),
                      ),
                    ),
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
