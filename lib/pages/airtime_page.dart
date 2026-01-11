import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:io';
import '../services/api_service.dart';
import 'transaction_details_page.dart';
import 'beneficiary_page.dart';
import '../utils/network_utils.dart';

class AirtimePage extends StatefulWidget {
  const AirtimePage({super.key});

  @override
  State<AirtimePage> createState() => _AirtimePageState();
}

class _AirtimePageState extends State<AirtimePage> {
  // Network prefixes for validation
  static const Map<String, List<String>> networkPrefixes = {
    'MTN': [
      '0803',
      '0806',
      '0703',
      '0706',
      '0810',
      '0813',
      '0814',
      '0816',
      '0903',
      '0906',
      '0913',
      '0916',
      '07025', // legacy Visafone (now MTN)
      '07026',
      '0704',
    ],
    'Glo': ['0805', '0807', '0705', '0811', '0815', '0905', '0915'],
    'Airtel': [
      '0802',
      '0808',
      '0701',
      '0708',
      '0812',
      '0901',
      '0902',
      '0904',
      '0907',
      '0911',
      '0912',
    ],
    '9mobile': ['0809', '0817', '0818', '0908', '0909'],
  };

  // Helper: verify phone number matches selected network
  bool _isValidNetworkNumber(String phone, String network) {
    if (phone.length != 11) return false;
    final prefix = phone.substring(0, 4);
    final prefixes = networkPrefixes[network];
    if (prefixes == null) return false;
    return prefixes.contains(prefix);
  }

  // Detect network name from a phone number by matching known prefixes.
  String? _networkFromPhone(String phone) {
    if (phone.isEmpty) return null;
    for (final entry in networkPrefixes.entries) {
      for (final p in entry.value) {
        if (phone.startsWith(p)) return entry.key;
      }
    }
    return null;
  }

  final _phoneController = TextEditingController();
  final FocusNode _phoneFocusNode = FocusNode();
  final _amountController = TextEditingController();
  final _pinController = TextEditingController();
  String? _phoneError;
  bool _phoneValid = false;
  String _selectedNetwork = ''; // No network selected by default
  bool _verifyNumber = false;
  bool _isProcessing = false;
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _isBiometricEnabled = false;
  bool _hasInternet = true;
  StreamSubscription? _connectivitySubscription;
  Map<String, dynamic> _networkStatuses = {}; // Store network status info

  Future<void> _fetchNetworkStatuses() async {
    try {
      final apiService = ApiService();
      final statuses = await apiService.getNetworkStatuses();
      if (mounted) {
        setState(() {
          _networkStatuses = statuses;
        });
      }
    } catch (e) {
      print('Error fetching network statuses: $e');
    }
  }

  bool _isNetworkEnabled(String networkName) {
    final normalized = networkName.toUpperCase();
    final status = _networkStatuses[normalized];
    if (status == null) return true; // Default to enabled if no status found
    print(
      'Network $networkName status check: networkStatus=${status['networkStatus']}',
    );
    return status['networkStatus'] == 'On';
  }

  @override
  void initState() {
    super.initState();
    _loadBiometricSettings();
    _fetchNetworkStatuses();
    _initConnectivity();
    // clear validation state when user edits the phone field
    _phoneController.addListener(() {
      final value = _phoneController.text.trim();

      // Auto-detect network from the number (if any)
      final detected = _networkFromPhone(value);
      if (detected != null && detected != _selectedNetwork) {
        setState(() {
          _selectedNetwork = detected;
        });
      }

      // Validate number as the user types and update inline state.
      final isValid = _isValidNetworkNumber(value, _selectedNetwork);

      // Update inline error, valid flag and auto-toggle the "Verify Number" switch
      // when the number becomes valid. If the number becomes invalid, the switch
      // is turned off to avoid accidental verification.
      if (isValid != _phoneValid ||
          _phoneError != null ||
          _verifyNumber != isValid) {
        setState(() {
          _phoneValid = isValid;
          if (isValid) {
            _phoneError = null;
          }
          _verifyNumber = isValid;
        });
      }
    });
  }

  Future<void> _initConnectivity() async {
    // initial check
    _hasInternet = await _checkInternetConnection();
    // listen for changes
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      result,
    ) async {
      final available = await _verifyInternetAccess();
      if (mounted) {
        setState(() {
          _hasInternet = available;
        });
      }
    });
  }

  Future<void> _loadBiometricSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _isBiometricEnabled = prefs.getBool('biometric_enabled') ?? false;
      });
    } catch (e) {
      print('Error loading biometric settings: $e');
    }
  }

  Future<String?> _authenticateWithBiometrics() async {
    try {
      bool canCheckBiometrics = await _localAuth.canCheckBiometrics;
      bool hasHardware = await _localAuth.isDeviceSupported();

      if (!canCheckBiometrics || !hasHardware) {
        showNetworkErrorSnackBar(
          context,
          'Biometric authentication is not supported on this device',
        );
        return null;
      }

      bool authenticated = await _localAuth.authenticate(
        localizedReason: 'Please authenticate to complete the transaction',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (authenticated) {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getString('login_pin');
      }
    } catch (e) {
      print('Error during biometric authentication: $e');
      // Handle specific error types
      if (e.toString().contains('NotAvailable') ||
          e.toString().contains('NOT_AVAILABLE')) {
        showNetworkErrorSnackBar(
          context,
          'Biometric authentication is not available',
        );
      } else if (e.toString().contains('PermissionDenied') ||
          e.toString().contains('PERMISSION_DENIED')) {
        showNetworkErrorSnackBar(
          context,
          'Biometric permission denied. Please enable in Settings',
        );
      } else if (e.toString().contains('NotEnrolled') ||
          e.toString().contains('NOT_ENROLLED')) {
        showNetworkErrorSnackBar(
          context,
          'No biometric data enrolled on this device',
        );
      }
    }
    return null;
  }

  // Helper method to get responsive font size
  double _getResponsiveFontSize(BuildContext context, double baseSize) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 360) return baseSize * 0.85;
    if (screenWidth < 400) return baseSize * 0.9;
    if (screenWidth < 500) return baseSize * 1.0;
    return baseSize * 1.1;
  }

  // Helper method to get responsive padding
  double _getResponsivePadding(BuildContext context, double basePadding) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 360) return basePadding * 0.7;
    if (screenWidth < 400) return basePadding * 0.8;
    if (screenWidth < 500) return basePadding * 1.0;
    return basePadding * 1.2;
  }

  // Helper method to get responsive spacing
  double _getResponsiveSpacing(BuildContext context, double baseSpacing) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 360) return baseSpacing * 0.6;
    if (screenWidth < 400) return baseSpacing * 0.8;
    if (screenWidth < 500) return baseSpacing * 1.0;
    return baseSpacing * 1.2;
  }

  // Helper method to get responsive icon size
  double _getResponsiveIconSize(BuildContext context, double baseSize) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 360) return baseSize * 0.8;
    if (screenWidth < 400) return baseSize * 0.9;
    if (screenWidth < 500) return baseSize * 1.0;
    return baseSize * 1.1;
  }

  /// Check connectivity status and verify actual internet access by attempting a lightweight request.
  Future<bool> _checkInternetConnection() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        _showNoInternetSnackbar();
        return false;
      }

      // Verify actual internet access (google's generate_204 is lightweight)
      return await _verifyInternetAccess();
    } catch (e) {
      // On error assume no internet
      _showNoInternetSnackbar();
      return false;
    }
  }

  Future<bool> _verifyInternetAccess() async {
    try {
      // A lightweight endpoint that returns 204 when online
      final uri = Uri.parse('https://www.google.com/generate_204');
      final response = await http.get(uri).timeout(const Duration(seconds: 3));
      if (response.statusCode == 204 || response.statusCode == 200) {
        return true;
      }
      _showNoInternetSnackbar();
      return false;
    } catch (e) {
      _showNoInternetSnackbar();
      return false;
    }
  }

  void _showNoInternetSnackbar() {
    if (!mounted) return;
    showNetworkErrorSnackBar(
      context,
      'No internet connection. Please check your network.',
    );
  }

  // Show error modal dialog
  void _showErrorModal(String title, String message, {VoidCallback? onRetry}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: EdgeInsets.all(_getResponsivePadding(context, 20)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Error Icon with red background circle
              Container(
                width: _getResponsiveIconSize(context, 60),
                height: _getResponsiveIconSize(context, 60),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red.shade50,
                ),
                child: Icon(
                  Icons.error_outline,
                  color: Colors.red.shade600,
                  size: _getResponsiveIconSize(context, 32),
                ),
              ),
              SizedBox(height: _getResponsiveSpacing(context, 16)),
              // Title
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: _getResponsiveFontSize(context, 16),
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              SizedBox(height: _getResponsiveSpacing(context, 12)),
              // Message
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: _getResponsiveFontSize(context, 13),
                  color: Colors.grey.shade600,
                  height: 1.6,
                ),
              ),
              SizedBox(height: _getResponsiveSpacing(context, 20)),
              // Buttons
              if (onRetry != null)
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: _getResponsiveIconSize(context, 44),
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          onRetry();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFce4323),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Try Again',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: _getResponsiveFontSize(context, 14),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: _getResponsiveSpacing(context, 8)),
                    SizedBox(
                      width: double.infinity,
                      height: _getResponsiveIconSize(context, 44),
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: Colors.grey.shade300,
                              width: 1.5,
                            ),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: const Color(0xFFce4323),
                            fontSize: _getResponsiveFontSize(context, 14),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  height: _getResponsiveIconSize(context, 44),
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFce4323),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'OK',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: _getResponsiveFontSize(context, 14),
                        fontWeight: FontWeight.bold,
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

  // Validate all fields before proceeding
  bool _validateBeforePurchase() {
    // Check if phone number is empty
    if (_phoneController.text.isEmpty) {
      _showErrorModal(
        'Phone Number Required',
        'Please enter a phone number to proceed.',
      );
      return false;
    }

    // Check if amount is entered
    if (_amountController.text.isEmpty) {
      _showErrorModal('Amount Required', 'Please enter an amount to proceed.');
      return false;
    }

    // Validate phone number matches selected network
    final phone = _phoneController.text.trim();
    if (!_isValidNetworkNumber(phone, _selectedNetwork)) {
      // Show warning modal instead of blocking - user can still proceed
      _showPhoneValidationWarning(phone);
      return false;
    }

    return true;
  }

  // Show warning when phone number is not validated
  void _showPhoneValidationWarning(String phone) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: EdgeInsets.all(_getResponsivePadding(context, 20)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Warning Icon with orange background circle
              Container(
                width: _getResponsiveIconSize(context, 60),
                height: _getResponsiveIconSize(context, 60),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFce4323).withOpacity(0.1),
                ),
                child: Icon(
                  Icons.warning_outlined,
                  color: const Color(0xFFce4323),
                  size: _getResponsiveIconSize(context, 32),
                ),
              ),
              SizedBox(height: _getResponsiveSpacing(context, 16)),
              // Title
              Text(
                'Phone Number Warning',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: _getResponsiveFontSize(context, 16),
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              SizedBox(height: _getResponsiveSpacing(context, 12)),
              // Message
              Text(
                'The phone number "$phone" may not be valid for $_selectedNetwork network.\n\nDo you want to proceed anyway?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: _getResponsiveFontSize(context, 13),
                  color: Colors.grey.shade600,
                  height: 1.6,
                ),
              ),
              SizedBox(height: _getResponsiveSpacing(context, 20)),
              // Buttons
              SizedBox(
                width: double.infinity,
                height: _getResponsiveIconSize(context, 44),
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    // Proceed with confirmation even if phone is not validated
                    _showConfirmationSheet();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFce4323),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Proceed',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: _getResponsiveFontSize(context, 14),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              SizedBox(height: _getResponsiveSpacing(context, 8)),
              SizedBox(
                width: double.infinity,
                height: _getResponsiveIconSize(context, 44),
                child: TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    _phoneFocusNode.requestFocus();
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.grey.shade100,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: _getResponsiveFontSize(context, 14),
                      fontWeight: FontWeight.bold,
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

  // Show confirmation sheet
  void _showConfirmationSheet() {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: EdgeInsets.only(
          left: _getResponsivePadding(context, 20),
          right: _getResponsivePadding(context, 20),
          top: _getResponsivePadding(context, 24),
          bottom:
              MediaQuery.of(context).viewInsets.bottom +
              MediaQuery.of(context).padding.bottom +
              _getResponsiveSpacing(context, 20),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Confirm Purchase',
                style: TextStyle(
                  fontSize: _getResponsiveFontSize(context, 16),
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              SizedBox(height: _getResponsiveSpacing(context, 16)),
              _buildDetailRow('Network', _selectedNetwork),
              SizedBox(height: _getResponsiveSpacing(context, 12)),
              _buildDetailRow('Phone Number', _phoneController.text),
              SizedBox(height: _getResponsiveSpacing(context, 12)),
              _buildDetailRow(
                'Amount',
                '₦${_amountController.text}',
                isAmount: true,
              ),
              SizedBox(height: _getResponsiveSpacing(context, 20)),
              SizedBox(
                width: double.infinity,
                height: _getResponsiveIconSize(context, 48),
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _showPinSheet();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFce4323),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Proceed to Payment',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: _getResponsiveFontSize(context, 14),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              SizedBox(height: _getResponsiveSpacing(context, 12)),
              SizedBox(
                width: double.infinity,
                height: _getResponsiveIconSize(context, 48),
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade300, width: 1.5),
                    ),
                  ),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: const Color(0xFFce4323),
                      fontSize: _getResponsiveFontSize(context, 14),
                      fontWeight: FontWeight.bold,
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

  Widget _buildDetailRow(String label, String value, {bool isAmount = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: _getResponsiveFontSize(context, 14),
            color: Colors.grey.shade600,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: _getResponsiveFontSize(context, isAmount ? 16 : 14),
            fontWeight: isAmount ? FontWeight.bold : FontWeight.w600,
            color: isAmount ? Colors.purple : Colors.black87,
          ),
        ),
      ],
    );
  }

  // PIN Verification Bottom Sheet with Numeric Keypad
  void _showPinSheet() {
    String pinInput = '';

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            left: _getResponsivePadding(context, 16),
            right: _getResponsivePadding(context, 16),
            top: _getResponsivePadding(context, 8),
            bottom:
                MediaQuery.of(context).viewInsets.bottom +
                MediaQuery.of(context).padding.bottom +
                _getResponsivePadding(context, 12),
          ),
          color: Colors.white,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Input PIN to Pay',
                  style: TextStyle(
                    fontSize: _getResponsiveFontSize(context, 14),
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                SizedBox(height: _getResponsiveSpacing(context, 6)),
                // PIN Display Field with Dots
                Container(
                  height: _getResponsiveIconSize(context, 35),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300, width: 1.5),
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.grey.shade50,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (index) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: index < pinInput.length
                                ? const Color(0xFFce4323)
                                : Colors.grey.shade300,
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                SizedBox(height: _getResponsiveSpacing(context, 6)),
                // Numeric Keypad
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 1.25,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: 12,
                  itemBuilder: (context, index) {
                    if (index < 9) {
                      final number = index + 1;
                      return _buildPinButton(number.toString(), () {
                        if (pinInput.length < 4) {
                          setModalState(() {
                            pinInput += number.toString();
                          });
                        }
                      });
                    } else if (index == 9) {
                      // Thumbprint icon button
                      return _isBiometricEnabled
                          ? _buildPinButton('', () async {
                              final pin = await _authenticateWithBiometrics();
                              if (pin != null && pin.isNotEmpty) {
                                setModalState(() {
                                  pinInput = pin;
                                });
                                // Auto-proceed after biometric success
                                await Future.delayed(
                                  const Duration(milliseconds: 500),
                                );
                                if (!_isProcessing) {
                                  Navigator.pop(context);
                                  _pinController.text = pin;
                                  await _handlePurchase();
                                }
                              }
                            }, isBiometric: true)
                          : _buildPinButton('', () {});
                    } else if (index == 10) {
                      // 0 button
                      return _buildPinButton('0', () {
                        if (pinInput.length < 4) {
                          setModalState(() {
                            pinInput += '0';
                          });
                        }
                      });
                    } else {
                      // Delete button
                      return _buildPinButton('⌫', () {
                        if (pinInput.isNotEmpty) {
                          setModalState(() {
                            pinInput = pinInput.substring(
                              0,
                              pinInput.length - 1,
                            );
                          });
                        }
                      }, isDelete: true);
                    }
                  },
                ),
                SizedBox(height: _getResponsiveSpacing(context, 6)),
                Padding(
                  padding: EdgeInsets.only(
                    bottom: _getResponsiveSpacing(context, 12),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: _getResponsiveIconSize(context, 54),
                    child: ElevatedButton(
                      onPressed: pinInput.length == 4
                          ? () async {
                              // Verify PIN is correct
                              final prefs =
                                  await SharedPreferences.getInstance();
                              final storedPin = prefs.getString('login_pin');

                              if (storedPin == null || pinInput != storedPin) {
                                // PIN is incorrect - show error modal
                                Navigator.pop(context);
                                _showErrorModal(
                                  'Incorrect PIN',
                                  'The PIN you entered is incorrect. Please try again.',
                                  onRetry: () {
                                    _showPinSheet(); // Show PIN sheet again
                                  },
                                );
                                return;
                              }

                              // PIN is correct - proceed with transaction
                              _pinController.text = pinInput;
                              Navigator.pop(context);
                              await _handlePurchase();
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFce4323),
                        disabledBackgroundColor: Colors.grey.shade300,
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Verify PIN',
                        style: TextStyle(
                          color: pinInput.length == 4
                              ? Colors.white
                              : Colors.grey.shade500,
                          fontSize: _getResponsiveFontSize(context, 18),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: _getResponsiveSpacing(context, 4)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPinButton(
    String label,
    VoidCallback onPressed, {
    bool isDelete = false,
    bool isBiometric = false,
  }) {
    return GestureDetector(
      onTap: (label.isNotEmpty || isBiometric) ? onPressed : null,
      child: Container(
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: label.isEmpty && !isBiometric
              ? Colors.transparent
              : isDelete
              ? Colors.grey.shade200
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: (label.isEmpty && !isBiometric)
                ? Colors.transparent
                : Colors.grey.shade300,
            width: 1.2,
          ),
        ),
        child: Center(
          child: isBiometric
              ? Icon(
                  Icons.fingerprint,
                  color: const Color(0xFFce4323),
                  size: _getResponsiveIconSize(context, 40),
                )
              : Text(
                  label,
                  style: TextStyle(
                    fontSize: _getResponsiveFontSize(context, 25),
                    fontWeight: FontWeight.bold,
                    color: isDelete ? Colors.grey.shade700 : Colors.black,
                  ),
                ),
        ),
      ),
    );
  }

  final List<Map<String, dynamic>> networks = [
    {
      'name': 'MTN',
      'logo': 'assets/images/mtn_logo.png',
      'color': const Color(0xFFFFBE00),
    },
    {
      'name': 'Airtel',
      'logo': 'assets/images/airtel_logo.png',
      'color': const Color(0xFFEE1C25),
    },
    {
      'name': 'Glo',
      'logo': 'assets/images/glo_logo.png',
      'color': const Color(0xFF4CAF50),
    },
    {
      'name': '9mobile',
      'logo': 'assets/images/9mobile_logo.png',
      'color': const Color.fromARGB(255, 0, 97, 52),
    },
  ];

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _phoneFocusNode.dispose();
    _phoneController.dispose();
    _amountController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  final ApiService _apiService = ApiService();

  Future<void> _handlePurchase() async {
    // Prevent re-entrancy: if a purchase is already in progress, ignore additional calls
    if (_isProcessing) return;
    // Set processing state immediately so UI disables buttons synchronously
    setState(() {
      _isProcessing = true;
    });

    // Check for internet connectivity
    final hasInternet = await _checkInternetConnection();
    if (!hasInternet) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
      return;
    }

    // Minimum amount check
    final enteredAmount = double.tryParse(_amountController.text) ?? 0.0;
    if (enteredAmount < 100) {
      _showErrorModal(
        'Minimum Amount Required',
        'Minimum purchase amount is ₦100',
        onRetry: () {
          _amountController.clear();
        },
      );
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final rawUser = prefs.getString('user_data');
      double walletBalance = 0.0;
      if (rawUser != null) {
        try {
          final userJson = json.decode(rawUser);
          walletBalance =
              double.tryParse(
                (userJson['sWallet'] ?? userJson['wallet'] ?? 0).toString(),
              ) ??
              0.0;
        } catch (_) {
          walletBalance = 0.0;
        }
      } else {
        walletBalance =
            double.tryParse(
              (prefs.getDouble('wallet') ?? prefs.getString('wallet') ?? 0)
                  .toString(),
            ) ??
            0.0;
      }

      final required = double.tryParse(_amountController.text) ?? 0.0;
      if (walletBalance < required) {
        _showErrorModal(
          'Insufficient Balance',
          'Insufficient balance (₦${walletBalance.toString()}) for this purchase of ₦${required.toString()}',
        );
        if (mounted) {
          setState(() {
            _isProcessing = false;
          });
        }
        return;
      }

      // Verify internet one more time before API call
      if (!await _checkInternetConnection()) {
        if (mounted) {
          setState(() {
            _isProcessing = false;
          });
        }
        return;
      }

      // Perform API call
      final response = await _apiService.purchaseAirtime(
        phone: _phoneController.text,
        amount: _amountController.text,
        network: _selectedNetwork,
        pin: _pinController.text,
      );

      if (response['success'] == true) {
        if (!mounted) return;
        // Resolve initial status from possible response shapes
        final dynamic resolvedStatusRaw =
            response['status'] ??
            response['data']?['status'] ??
            response['data']?['data']?['status'];

        // Normalize to only 'success' or 'failed'
        String initialStatus;
        final String? raw = resolvedStatusRaw?.toString().trim().toLowerCase();
        if (raw != null &&
            (raw == '0' ||
                raw == 'success' ||
                raw == 'successful' ||
                raw == 'ok' ||
                raw == 'completed' ||
                raw == 'true')) {
          initialStatus = 'success';
        } else {
          initialStatus = 'failed';
        }

        // Show loading dialog
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    const Color(0xFFce4323),
                  ),
                ),
              ),
            ),
          );
        }

        // Wait a brief moment before navigating
        await Future.delayed(const Duration(milliseconds: 1500));

        // Ensure loading dialog is dismissed (if still shown)
        if (mounted && Navigator.canPop(context)) {
          try {
            Navigator.pop(context);
          } catch (_) {}
        }

        // Capture final fallbacks for amount/phone/network
        String finalAmount = _amountController.text;
        if (finalAmount.isEmpty) {
          final candidate =
              response['data']?['amount'] ??
              response['amount'] ??
              response['data']?['data']?['amount'] ??
              response['data']?['data']?['chargedAmount'] ??
              response['data']?['data']?['price'] ??
              response['data']?['chargedAmount'] ??
              response['data']?['price'];
          finalAmount = candidate?.toString() ?? '0';
        }

        final String finalPhone = _phoneController.text.isNotEmpty
            ? _phoneController.text
            : (response['data']?['phone'] ?? response['phone'] ?? '');
        final String finalNetwork = _selectedNetwork.isNotEmpty
            ? _selectedNetwork
            : (response['data']?['network'] ?? response['network'] ?? '');

        // Clear controllers before navigation
        _phoneController.clear();
        _amountController.clear();
        _pinController.clear();

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => TransactionDetailsPage(
                transactionId:
                    response['data']?['data']?['transactionId'] ??
                    response['data']?['transactionId'] ??
                    '',
                amount: finalAmount,
                phoneNumber: finalPhone,
                network: finalNetwork,
                initialStatus: initialStatus,
                planName: 'Airtime Top-up',
                transactionDate: DateTime.now().toString(),
                planValidity: 'N/A',
                playOnOpen: false,
              ),
            ),
          );
        }
        if (initialStatus == 'success') {
          _phoneController.clear();
          _amountController.clear();
          _pinController.clear();
        }
      } else {
        if (!mounted) return;
        _showErrorModal(
          'Transaction Failed',
          response['message'] ?? 'An error occurred during the transaction.',
        );
      }
    } on TimeoutException {
      _showErrorModal(
        'Connection Timeout',
        'The request took too long. Please check your internet connection and try again.',
      );
    } on SocketException {
      _showErrorModal(
        'Network Error',
        'Network error occurred. Please check your internet connection.',
      );
    } catch (e) {
      print('Error during airtime purchase: $e');
      if (!mounted) return;

      String errorMessage = 'An error occurred while processing your request.';
      if (e is FormatException) {
        errorMessage =
            'Server returned an invalid response. Please try again later.';
      }

      _showErrorModal('Error', errorMessage);
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFFce4323),
        elevation: 0,
        title: Text(
          'Airtime TopUp',
          style: TextStyle(
            color: Colors.white,
            fontSize: _getResponsiveFontSize(context, 18),
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(_getResponsivePadding(context, 16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!_hasInternet)
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(_getResponsivePadding(context, 12)),
                    margin: EdgeInsets.only(
                      bottom: _getResponsiveSpacing(context, 8),
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.wifi_off,
                          color: Colors.red,
                          size: _getResponsiveIconSize(context, 20),
                        ),
                        SizedBox(width: _getResponsiveSpacing(context, 8)),
                        Expanded(
                          child: Text(
                            'You are offline. Purchases are disabled until an internet connection is available.',
                            style: TextStyle(
                              color: Colors.red.shade900,
                              fontSize: _getResponsiveFontSize(context, 13),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Text(
                  'Select Network',
                  style: TextStyle(
                    fontSize: _getResponsiveFontSize(context, 16),
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                SizedBox(height: _getResponsiveSpacing(context, 8)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: networks.map((network) {
                    bool isSelected = _selectedNetwork == network['name'];
                    bool isEnabled = _isNetworkEnabled(network['name']);

                    return GestureDetector(
                      onTap: isEnabled
                          ? () => setState(
                              () => _selectedNetwork = network['name'],
                            )
                          : null,
                      child: Opacity(
                        opacity: isEnabled ? 1.0 : 0.4,
                        child: Container(
                          width: _getResponsiveIconSize(context, 70),
                          height: _getResponsiveIconSize(context, 70),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected && isEnabled
                                  ? network['color']
                                  : Colors.grey.shade300,
                              width: isSelected && isEnabled ? 3 : 2,
                            ),
                            color: isSelected && isEnabled
                                ? network['color'].withOpacity(0.05)
                                : Colors.white,
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(
                              _getResponsivePadding(context, 8),
                            ),
                            child: Image.asset(
                              network['logo'],
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                SizedBox(height: _getResponsiveSpacing(context, 16)),
                Text(
                  'Mobile Number',
                  style: TextStyle(
                    fontSize: _getResponsiveFontSize(context, 16),
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                SizedBox(height: _getResponsiveSpacing(context, 8)),
                TextField(
                  focusNode: _phoneFocusNode,
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  style: TextStyle(
                    fontSize: _getResponsiveFontSize(context, 14),
                  ),
                  decoration: InputDecoration(
                    hintText: 'Mobile No',
                    hintStyle: TextStyle(
                      fontSize: _getResponsiveFontSize(context, 14),
                      color: Colors.grey,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: Color(0xFFce4323),
                        width: 2,
                      ),
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: _getResponsivePadding(context, 12),
                      vertical: _getResponsivePadding(context, 16),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        Icons.contact_page,
                        size: _getResponsiveIconSize(context, 24),
                      ),
                      onPressed: () async {
                        final selected = await Navigator.push<String?>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const BeneficiaryPage(),
                          ),
                        );
                        if (selected != null && selected.isNotEmpty) {
                          final trimmed = selected.trim();
                          final isValid = _isValidNetworkNumber(
                            trimmed,
                            _selectedNetwork,
                          );
                          setState(() {
                            _phoneController.text = trimmed;
                            _phoneValid = isValid;
                            if (isValid) _phoneError = null;
                            _verifyNumber = isValid;
                          });
                        }
                      },
                    ),
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(11),
                  ],
                ),
                SizedBox(height: _getResponsiveSpacing(context, 12)),
                Text(
                  'Amount',
                  style: TextStyle(
                    fontSize: _getResponsiveFontSize(context, 16),
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                SizedBox(height: _getResponsiveSpacing(context, 8)),
                TextField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  style: TextStyle(
                    fontSize: _getResponsiveFontSize(context, 14),
                  ),
                  decoration: InputDecoration(
                    hintText: '0',
                    hintStyle: TextStyle(
                      fontSize: _getResponsiveFontSize(context, 14),
                      color: Colors.grey,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: Color(0xFFce4323),
                        width: 2,
                      ),
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: _getResponsivePadding(context, 12),
                      vertical: _getResponsivePadding(context, 12),
                    ),
                    prefixText: '₦ ',
                  ),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                SizedBox(height: _getResponsiveSpacing(context, 12)),

                // Extra spacing to push the Pay Now button lower
                SizedBox(height: _getResponsiveSpacing(context, 40)),

                SizedBox(
                  width: double.infinity,
                  height: _getResponsiveIconSize(context, 48),
                  child: ElevatedButton(
                    onPressed: (_isProcessing || !_hasInternet)
                        ? null
                        : () {
                            // Validate before showing confirmation sheet
                            if (_validateBeforePurchase()) {
                              _showConfirmationSheet();
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFce4323),
                      disabledBackgroundColor: Colors.grey.shade400,
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isProcessing
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Processing...',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: _getResponsiveFontSize(context, 14),
                                ),
                              ),
                              SizedBox(
                                width: _getResponsiveSpacing(context, 8),
                              ),
                              SizedBox(
                                width: _getResponsiveIconSize(context, 20),
                                height: _getResponsiveIconSize(context, 20),
                                child: const CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            'Pay Now',
                            style: TextStyle(
                              fontSize: _getResponsiveFontSize(context, 16),
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
                SizedBox(height: _getResponsiveSpacing(context, 16)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // End of the class
}
