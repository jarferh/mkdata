import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'transaction_details_page.dart';
import 'beneficiary_page.dart';
import '../services/api_service.dart';
import 'dart:async';
import 'dart:io';
import '../utils/network_utils.dart';

class DataPlan {
  final String id;
  final String name;
  final String planType;
  final double price;
  final String validity;
  final String planCode;
  final int networkId;

  DataPlan({
    required this.id,
    required this.name,
    required this.planType,
    required this.price,
    required this.validity,
    required this.planCode,
    required this.networkId,
  });

  factory DataPlan.fromJson(Map<String, dynamic> json) {
    return DataPlan(
      id: json['id'].toString(),
      name: json['name'] ?? '',
      planType: json['planType'] ?? '',
      price: double.parse(json['price'].toString()),
      validity: json['validity']?.toString() ?? '30',
      planCode: json['planCode']?.toString() ?? '',
      networkId: int.parse(json['networkId'].toString()),
    );
  }

  String get description {
    return '$name - $planType - ${validity}days validity';
  }
}

class DataPage extends StatefulWidget {
  const DataPage({super.key});

  @override
  State<DataPage> createState() => _DataPageState();
}

class _DataPageState extends State<DataPage> {
  final _phoneController = TextEditingController();
  final _amountController = TextEditingController();
  final _pinController = TextEditingController();
  final LocalAuthentication _localAuth = LocalAuthentication();
  String _selectedNetwork = ''; // No network selected by default
  String _selectedPlanType = ''; // Store selected plan type - empty by default
  bool _isBiometricEnabled = false;
  Map<String, dynamic> _networkStatuses = {}; // Store network status info
  bool _verifyNumber = false;
  // Network prefixes for validation (same as airtime page)
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

  // Get plan types for each network
  List<String> _getPlanTypesForNetwork(String network) {
    switch (network) {
      case 'MTN':
        return ['MTN SME', 'MTN SME2', 'MTN Corporate', 'MTN Gifting'];
      case 'Airtel':
        return ['Airtel Corporate', 'Airtel Gifting', 'Airtel SME'];
      case 'Glo':
        return ['Glo Gifting', 'Glo Corporate'];
      case '9mobile':
        return ['9mobile Corporate'];
      default:
        return ['SME'];
    }
  }

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

  // Helper: check if a network is enabled for data purchase
  bool _isNetworkEnabled(String networkName) {
    final normalized = networkName.toUpperCase();
    final status = _networkStatuses[normalized];
    if (status == null) return true; // Default to enabled if no status found
    print(
      'Network $networkName status check: networkStatus=${status['networkStatus']}',
    );
    return status['networkStatus'] == 'On';
  }

  // Helper: check if a plan type is enabled
  bool _isPlanTypeEnabled(String planType) {
    final normalized = _selectedNetwork.toUpperCase();
    final status = _networkStatuses[normalized];
    if (status == null) {
      print('No status found for network: $normalized');
      return true; // Default to enabled if no status found
    }

    print(
      'Checking if plan type "$planType" is enabled for $normalized. Status: $status',
    );

    // Map plan types to their corresponding status fields
    // IMPORTANT: Check SME2 BEFORE SME because "SME2" contains "SME"
    if (planType.contains('SME2')) {
      final enabled = status['sme2Status'] == 'On';
      print('SME2 status: ${status['sme2Status']} - enabled: $enabled');
      return enabled;
    } else if (planType.contains('SME')) {
      final enabled = status['smeStatus'] == 'On';
      print('SME status: ${status['smeStatus']} - enabled: $enabled');
      return enabled;
    } else if (planType.contains('Corporate')) {
      final enabled = status['corporateStatus'] == 'On';
      print(
        'Corporate status: ${status['corporateStatus']} - enabled: $enabled',
      );
      return enabled;
    } else if (planType.contains('Gifting')) {
      final enabled = status['giftingStatus'] == 'On';
      print('Gifting status: ${status['giftingStatus']} - enabled: $enabled');
      return enabled;
    } else if (planType.contains('Coupon')) {
      final enabled = status['couponStatus'] == 'On';
      print('Coupon status: ${status['couponStatus']} - enabled: $enabled');
      return enabled;
    }
    return true;
  }

  final FocusNode _phoneFocusNode = FocusNode();
  String? _phoneError;
  bool _phoneValid = false;
  bool _isProcessing = false;
  StreamSubscription? _connectivitySubscription;

  // Track whether the PIN-loading dialog is shown so we can dismiss it safely
  bool _isPinLoadingShown = false;

  DataPlan? _selectedPlan;
  List<DataPlan> _dataPlans = [];
  bool _isLoadingPlans = false;

  Future<void> _checkBiometricSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isBiometricEnabled = prefs.getBool('biometric_enabled') ?? false;
    });
  }

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

  @override
  void initState() {
    super.initState();
    // No plan type selected by default
    // Data plans will only load when user selects a plan type
    _fetchNetworkStatuses();
    _checkBiometricSettings();
    _initConnectivity();

    // Keep phone validation behaviour in sync with the Airtime page:
    // validate number as the user types or when it's set programmatically
    // (for example when selecting a beneficiary) and auto-toggle the
    // "Verify Number" switch when the number becomes valid.
    _phoneController.addListener(() {
      final value = _phoneController.text.trim();

      // Auto-detect network from the number and trigger plan refresh when it changes
      final detected = _networkFromPhone(value);
      if (detected != null && detected != _selectedNetwork) {
        setState(() {
          _selectedNetwork = detected;
          _selectedPlan = null;
          _amountController.clear();
        });
        _handleNetworkOrTypeChange();
      }

      final isValid = _isValidNetworkNumber(value, _selectedNetwork);

      if (isValid != _phoneValid ||
          _phoneError != null ||
          _verifyNumber != isValid) {
        if (mounted) {
          setState(() {
            _phoneValid = isValid;
            if (isValid) {
              _phoneError = null;
            }
            _verifyNumber = isValid;
          });
        }
      }
    });
  }

  Future<void> _initConnectivity() async {
    // initial check
    await _checkInternetConnection();
    // listen for changes
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      result,
    ) async {
      await _verifyInternetAccess();
    });
  }

  Future<void> _fetchDataPlans() async {
    if (_isLoadingPlans) return;

    // Ensure we have internet before attempting to fetch plans
    if (!await _checkInternetConnection()) {
      return;
    }

    setState(() {
      _isLoadingPlans = true;
      _dataPlans = [];
      _selectedPlan = null;
    });

    try {
      // Use network name; server will resolve to an ID dynamically
      final networkName = _selectedNetwork;
      // Use selected plan type label -> convert to API 'type' value
      final type = _apiTypeForLabel(_selectedPlanType);

      print('Fetching data plans for network $networkName and type $type');

      // Get actual user id from stored user_data in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      String? userId;
      final rawUser = prefs.getString('user_data');
      if (rawUser != null) {
        try {
          final userJson = json.decode(rawUser);
          userId = (userJson['sId'] ?? userJson['id'])?.toString();
        } catch (_) {
          userId = prefs.getString('user_id');
        }
      } else {
        userId = prefs.getString('user_id');
      }

      // Build request URL and include userId if available
      final queryParameters = {
        'network': networkName,
        if (type != null) 'type': type,
        if (userId != null) 'userId': userId,
      };

      final uri = Uri.parse(
        'https://api.mkdata.com.ng/api/data-plans',
      ).replace(queryParameters: queryParameters);

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success' && data['data'] != null) {
          final plans = (data['data'] as List)
              .map((plan) => DataPlan.fromJson(plan))
              .toList();

          setState(() {
            _dataPlans = plans;
          });
        }
      } else {
        throw Exception('Failed to load data plans');
      }
    } catch (e) {
      if (mounted) {
        showNetworkErrorSnackBar(
          context,
          e,
          fontSize: _getResponsiveFontSize(context, 14),
        );
      }
    } finally {
      setState(() {
        _isLoadingPlans = false;
      });
    }
  }

  // Add this method to handle network and plan type changes
  void _handleNetworkOrTypeChange() {
    _selectedPlan = null;
    _fetchDataPlans();
  }

  // Map the displayed plan type label to the API 'type' value
  // 'MTN SME' -> 'SME', 'MTN SME2' -> 'SME2', 'Glo Gifting' -> 'Gifting', etc.
  String? _apiTypeForLabel(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('sme2')) return 'SME2';
    if (lower.contains('sme')) return 'SME';
    if (lower.contains('corporate')) return 'Corporate';
    if (lower.contains('gift')) return 'Gifting';
    if (lower.contains('coupon')) return 'Coupon';
    return null; // fallback: omit type param
  }

  final List<String> dataTypes = [
    'Daily',
    'Weekly',
    'Monthly',
    'Gifting',
    'Corporate',
  ];

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
    _phoneController.dispose();
    _amountController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  // ...existing biometric helper methods are below (we use _authenticateAndGetPin)

  // Authenticate and return stored login PIN when successful (used to fill PIN field)
  Future<String?> _authenticateAndGetPin() async {
    try {
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      final hasHardware = await _localAuth.isDeviceSupported();

      if (!canCheckBiometrics || !hasHardware) {
        if (mounted) {
          showNetworkErrorSnackBar(
            context,
            'Biometric authentication is not supported on this device',
          );
        }
        return null;
      }

      final authenticated = await _localAuth.authenticate(
        localizedReason:
            'Please authenticate to use your saved transaction PIN',
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
      print('Error during biometric (getPin): $e');
    }
    return null;
  }

  Future<bool> _checkInternetConnection() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        _showNoInternetSnackbar();
        return false;
      }
      final ok = await _verifyInternetAccess();
      return ok;
    } catch (e) {
      _showNoInternetSnackbar();
      return false;
    }
  }

  Future<bool> _verifyInternetAccess() async {
    try {
      final uri = Uri.parse('https://www.google.com/generate_204');
      final response = await http.get(uri).timeout(const Duration(seconds: 3));
      return response.statusCode == 204 || response.statusCode == 200;
    } catch (e) {
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

  // Validate all fields before showing confirmation sheet
  bool _validateBeforeConfirmation() {
    // Check if phone number is empty
    if (_phoneController.text.isEmpty) {
      _showErrorModal(
        'Phone Number Required',
        'Please enter a phone number to proceed.',
      );
      return false;
    }

    // Check if plan is selected
    if (_selectedPlan == null) {
      _showErrorModal(
        'Plan Not Selected',
        'Please select a data plan to proceed.',
      );
      return false;
    }

    // Validate phone number matches selected network
    final phone = _phoneController.text.trim();
    if (!_isValidNetworkNumber(phone, _selectedNetwork)) {
      _showErrorModal(
        'Invalid Phone Number',
        'The phone number "$phone" is not valid for $_selectedNetwork network.\n\nPlease enter a valid $_selectedNetwork number or select a different network.',
        onRetry: () {
          _phoneFocusNode.requestFocus();
        },
      );
      setState(() {
        _phoneError = 'This number is not a valid $_selectedNetwork number';
        _phoneValid = false;
      });
      return false;
    }

    return true;
  }

  Future<void> _handlePurchase() async {
    // Prevent double submissions: return if already processing and set processing state immediately
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
    });

    final ok = await _checkInternetConnection();
    if (!ok) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
      return;
    }

    // Validate all required fields
    if (_phoneController.text.isEmpty ||
        (_pinController.text.isEmpty && !_isBiometricEnabled) ||
        _selectedPlan == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all fields and select a plan'),
          backgroundColor: Colors.red,
        ),
      );
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
      return;
    }

    // Validate phone number only if verification is enabled
    if (_verifyNumber) {
      final phone = _phoneController.text.trim();
      if (!_isValidNetworkNumber(phone, _selectedNetwork)) {
        // Show inline error and focus phone field
        setState(() {
          _phoneError = 'This number is not a valid $_selectedNetwork number';
          _phoneValid = false;
        });
        _phoneFocusNode.requestFocus();
        if (mounted) {
          setState(() {
            _isProcessing = false;
          });
        }
        return;
      }
    }

    // Validate PIN or use biometric to fill PIN when enabled
    if (_isBiometricEnabled && _pinController.text.isEmpty) {
      final pin = await _authenticateAndGetPin();
      if (pin == null || pin.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Biometric authentication failed'),
            backgroundColor: Colors.red,
          ),
        );
        if (mounted) {
          setState(() {
            _isProcessing = false;
          });
        }
        return;
      }
      _pinController.text = pin;
    } else if (_pinController.text.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid 4-digit PIN'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Check wallet balance from saved user_data before proceeding
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
        // fallback if older code stored wallet differently
        walletBalance =
            double.tryParse(
              (prefs.getDouble('wallet') ?? prefs.getString('wallet') ?? 0)
                  .toString(),
            ) ??
            0.0;
      }

      final required = _selectedPlan?.price ?? 0.0;
      if (walletBalance < required) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Insufficient balance (₦${walletBalance.toString()}) for this purchase of ₦${required.toString()}',
            ),
            backgroundColor: Colors.red,
          ),
        );
        if (mounted) {
          setState(() {
            _isProcessing = false;
            _isPinLoadingShown = false;
          });
          // Dismiss the loading dialog
          Navigator.of(context, rootNavigator: true).pop();
        }
        return;
      }
    } catch (e) {
      // If balance check fails silently, allow purchase to proceed but log
      print('Balance check error: $e');
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      // Get actual user ID from stored user_data in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      String? userId;
      final rawUser = prefs.getString('user_data');
      if (rawUser != null) {
        try {
          final userJson = json.decode(rawUser);
          userId = (userJson['sId'] ?? userJson['id'])?.toString();
        } catch (_) {
          userId = prefs.getString('user_id');
        }
      } else {
        userId = prefs.getString('user_id');
      }

      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Use network name; API will resolve network id server-side
      final networkName = _selectedNetwork;

      // Get stored PIN from SharedPreferences
      // prefs was already obtained above when resolving userId; reuse it
      if (!_isBiometricEnabled) {
        final storedPin = prefs.getString('login_pin');
        if (storedPin == null || storedPin != _pinController.text) {
          throw Exception('Invalid transaction PIN');
        }
      }

      print('Purchasing data with:');
      print('Network: $networkName');
      print('Phone Number: ${_phoneController.text}');
      print('Plan ID: ${_selectedPlan!.planCode}');
      print('Plan Type: ${_selectedPlan!.planType}');
      print('User ID: $userId');

      final ApiService apiService = ApiService();
      // final response = await apiService.purchaseData(
      //   network: networkId.toString(),
      //   phone: _phoneController.text,
      //   planId: _selectedPlan!.id,
      //   pin: _pinController.text,
      // );
      final response = await apiService.purchaseData(
        network: networkName,
        phone: _phoneController.text,
        planId: _selectedPlan!.planCode, // ✅ API’s planid from backend
        pin: _pinController.text,
      );

      print('API Response: $response'); // Debug log

      if (response['status'] == 'success') {
        print('Purchase Response: ${response['data']}'); // Debug log
        final data = response['data'];

        // Get transaction details from the API response structure
        final status = data['status'] ?? 'processing';
        final transactionId =
            data['transactionId'] ??
            'MK_${DateTime.now().millisecondsSinceEpoch}';
        final amount = _selectedPlan?.price.toString() ?? '0.0';
        final transactionDate = DateTime.now().toString();
        final planValidity = _selectedPlan?.validity ?? '30';
        final planName = _selectedPlan?.name ?? 'Unknown Plan';
        final phoneNumber = _phoneController.text;

        // Clear form
        _phoneController.clear();
        _pinController.clear();
        setState(() {
          _selectedPlan = null;
          _amountController.clear();
        });

        // Navigate to transaction details page with complete information
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => TransactionDetailsPage(
                initialStatus: status,
                transactionId: transactionId,
                amount: amount,
                phoneNumber: phoneNumber,
                network: _selectedNetwork,
                planName:
                    'Data Bundle $planName', // Make it explicit that this is a data bundle
                transactionDate: transactionDate,
                planValidity: planValidity,
                playOnOpen: false,
              ),
            ),
          );
        }
      } else {
        print('Purchase Failed: ${response['message']}'); // Debug log
        throw Exception(response['message'] ?? 'Failed to purchase data');
      }
    } on TimeoutException catch (e) {
      showNetworkErrorSnackBar(
        context,
        e,
        fontSize: _getResponsiveFontSize(context, 14),
      );
    } on SocketException catch (e) {
      showNetworkErrorSnackBar(
        context,
        e,
        fontSize: _getResponsiveFontSize(context, 14),
      );
    } catch (e) {
      print('Error during data purchase: ${e.toString()}'); // Debug log
      // use helper to sanitize exception messages; no local raw variable needed

      // Show sanitized error message using helper
      if (mounted) {
        // Use centralized helper to show a sanitized, styled message
        showNetworkErrorSnackBar(
          context,
          e,
          fontSize: _getResponsiveFontSize(context, 14),
        );
      }

      // Store necessary information before clearing
      final amount = (_selectedPlan?.price ?? 0.0).toString();
      final planName = _selectedPlan?.name ?? "Unknown Plan";
      final phoneNumber = _phoneController.text;
      final planValidity = _selectedPlan?.validity ?? '30';

      // Navigate to transaction details page with error information
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => TransactionDetailsPage(
              initialStatus: 'failed',
              transactionId: 'MK_${DateTime.now().millisecondsSinceEpoch}',
              amount: amount,
              phoneNumber: phoneNumber,
              network: _selectedNetwork,
              planName: 'Data Bundle $planName',
              transactionDate: DateTime.now().toString(),
              planValidity: planValidity,
              playOnOpen: false,
            ),
          ),
        );
      }

      // Clear form
      _phoneController.clear();
      _pinController.clear();
      setState(() {
        _selectedPlan = null;
        _amountController.clear();
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  // Helper method to get responsive font size
  double _getResponsiveFontSize(BuildContext context, double baseSize) {
    final screenWidth = MediaQuery.of(context).size.width;

    // Define breakpoints
    if (screenWidth < 360) {
      // Small phones
      return baseSize * 0.85;
    } else if (screenWidth < 400) {
      // Medium phones
      return baseSize * 0.9;
    } else if (screenWidth < 500) {
      // Large phones
      return baseSize * 1.0;
    } else {
      // Tablets and larger
      return baseSize * 1.1;
    }
  }

  // Helper method to get responsive padding
  double _getResponsivePadding(BuildContext context, double basePadding) {
    final screenWidth = MediaQuery.of(context).size.width;

    if (screenWidth < 360) {
      return basePadding * 0.7;
    } else if (screenWidth < 400) {
      return basePadding * 0.8;
    } else if (screenWidth < 500) {
      return basePadding * 1.0;
    } else {
      return basePadding * 1.2;
    }
  }

  // Helper method to get responsive spacing
  double _getResponsiveSpacing(BuildContext context, double baseSpacing) {
    final screenWidth = MediaQuery.of(context).size.width;

    if (screenWidth < 360) {
      return baseSpacing * 0.6;
    } else if (screenWidth < 400) {
      return baseSpacing * 0.8;
    } else if (screenWidth < 500) {
      return baseSpacing * 1.0;
    } else {
      return baseSpacing * 1.2;
    }
  }

  // Helper method to get responsive icon size
  double _getResponsiveIconSize(BuildContext context, double baseSize) {
    final screenWidth = MediaQuery.of(context).size.width;

    if (screenWidth < 360) {
      return baseSize * 0.8;
    } else if (screenWidth < 400) {
      return baseSize * 0.9;
    } else if (screenWidth < 500) {
      return baseSize * 1.0;
    } else {
      return baseSize * 1.1;
    }
  }

  // Shimmer Loading Effect for plans
  Widget _buildShimmerLoader() {
    return Column(
      children: List.generate(
        4,
        (index) => Container(
          margin: EdgeInsets.only(bottom: _getResponsiveSpacing(context, 12)),
          height: _getResponsiveIconSize(context, 60),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.shade200,
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.grey.shade300,
                      Colors.grey.shade200,
                      Colors.grey.shade300,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Confirmation Bottom Sheet
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
                'Confirm Transaction Details',
                style: TextStyle(
                  fontSize: _getResponsiveFontSize(context, 18),
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              SizedBox(height: _getResponsiveSpacing(context, 20)),
              _buildDetailRow('Network', _selectedNetwork),
              SizedBox(height: _getResponsiveSpacing(context, 16)),
              _buildDetailRow('Plan Name', _selectedPlan?.name ?? ''),
              SizedBox(height: _getResponsiveSpacing(context, 16)),
              _buildDetailRow('Plan Type', _selectedPlan?.planType ?? ''),
              SizedBox(height: _getResponsiveSpacing(context, 16)),
              _buildDetailRow(
                'Validity',
                '${_selectedPlan?.validity ?? 0} DAYS ✓',
              ),
              SizedBox(height: _getResponsiveSpacing(context, 16)),
              _buildDetailRow('Mobile Number', _phoneController.text),
              SizedBox(height: _getResponsiveSpacing(context, 16)),
              _buildDetailRow(
                'Amount',
                '₦${_selectedPlan?.price.toStringAsFixed(2) ?? '0'}',
                isAmount: true,
              ),
              SizedBox(height: _getResponsiveSpacing(context, 28)),
              SizedBox(
                width: double.infinity,
                height: _getResponsiveIconSize(context, 52),
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
                    'Continue',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: _getResponsiveFontSize(context, 16),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              SizedBox(height: _getResponsiveSpacing(context, 12)),
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
      builder: (sheetContext) => StatefulBuilder(
        builder: (innerContext, setModalState) => Container(
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
                    fontSize: _getResponsiveFontSize(context, 18),
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
                              final pin = await _authenticateAndGetPin();
                              if (pin != null && pin.isNotEmpty) {
                                // Close the PIN sheet immediately
                                Navigator.pop(innerContext);
                                // Show loading and process immediately (no delay)
                                _isPinLoadingShown = true;
                                showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  useRootNavigator: true,
                                  builder: (ctx) => Dialog(
                                    backgroundColor: Colors.transparent,
                                    elevation: 0,
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              const Color(0xFFce4323),
                                            ),
                                      ),
                                    ),
                                  ),
                                );

                                await _processPinTransaction(pin);
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
                              // Close the PIN sheet immediately
                              Navigator.pop(innerContext);

                              // Show loading immediately (no delay)
                              _isPinLoadingShown = true;
                              showDialog(
                                context: context,
                                barrierDismissible: false,
                                useRootNavigator: true,
                                builder: (ctx) => Dialog(
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

                              // Verify PIN is correct
                              final prefs =
                                  await SharedPreferences.getInstance();
                              final storedPin = prefs.getString('login_pin');

                              if (storedPin == null || pinInput != storedPin) {
                                // Dismiss loading dialog
                                if (_isPinLoadingShown) {
                                  try {
                                    Navigator.of(
                                      context,
                                      rootNavigator: true,
                                    ).pop();
                                  } catch (_) {}
                                  _isPinLoadingShown = false;
                                }

                                // Show incorrect PIN modal
                                _showErrorModal(
                                  'Incorrect PIN',
                                  'The PIN you entered is incorrect. Please try again.',
                                  onRetry: () {
                                    _showPinSheet(); // Show PIN sheet again
                                  },
                                );
                                return;
                              }

                              // PIN is correct - process while keeping the PIN-loading dialog visible
                              await _processPinTransaction(pinInput);
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

  Future<void> _processPinTransaction(String pin) async {
    _pinController.text = pin;
    await _handlePurchase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFFce4323),
        elevation: 0,
        title: Text(
          'Data Bundle',
          style: TextStyle(
            color: Colors.white,
            fontSize: _getResponsiveFontSize(context, 18),
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: Colors.white,
            size: _getResponsiveIconSize(context, 24),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(_getResponsivePadding(context, 16)),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // STEP 1: Network Selection + Phone Number (always visible)
                Text(
                  'Select Network',
                  style: TextStyle(
                    fontSize: _getResponsiveFontSize(context, 16),
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                SizedBox(height: _getResponsiveSpacing(context, 12)),

                // Network Selection with Circle Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: networks.map((network) {
                    bool isSelected = _selectedNetwork == network['name'];
                    bool isEnabled = _isNetworkEnabled(network['name']);

                    return GestureDetector(
                      onTap: isEnabled
                          ? () {
                              setState(() {
                                _selectedNetwork = network['name'];
                                // Reset to first plan type for this network
                                _selectedPlanType = _getPlanTypesForNetwork(
                                  _selectedNetwork,
                                )[0];
                              });
                              // Fetch data plans after state update
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _handleNetworkOrTypeChange();
                              });
                            }
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
                SizedBox(height: _getResponsiveSpacing(context, 20)),

                // Mobile Number Input
                Text(
                  'Mobile Number',
                  style: TextStyle(
                    fontSize: _getResponsiveFontSize(context, 14),
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                SizedBox(height: _getResponsiveSpacing(context, 8)),
                TextField(
                  focusNode: _phoneFocusNode,
                  controller: _phoneController,
                  onChanged: (value) {
                    final trimmed = value.trim();
                    final isValid = _isValidNetworkNumber(
                      trimmed,
                      _selectedNetwork,
                    );

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
                  },
                  keyboardType: TextInputType.phone,
                  style: TextStyle(
                    fontSize: _getResponsiveFontSize(context, 14),
                  ),
                  decoration: InputDecoration(
                    hintText: 'Enter phone number',
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
                          setState(() {
                            _phoneController.text = selected;
                          });
                        }
                      },
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: _getResponsivePadding(context, 12),
                      vertical: _getResponsivePadding(context, 12),
                    ),
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(11),
                  ],
                ),
                SizedBox(height: _getResponsiveSpacing(context, 20)),

                // STEP 2 & 3 & 4: Plan Type Categories and Data Plans (only shown after network selected)
                if (_phoneController.text.isNotEmpty ||
                    _selectedNetwork.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select Plan Type',
                        style: TextStyle(
                          fontSize: _getResponsiveFontSize(context, 14),
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      SizedBox(height: _getResponsiveSpacing(context, 8)),
                      // Horizontally scrollable plan types
                      SizedBox(
                        height: _getResponsiveIconSize(context, 50),
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _getPlanTypesForNetwork(
                            _selectedNetwork,
                          ).length,
                          itemBuilder: (context, index) {
                            final planTypes = _getPlanTypesForNetwork(
                              _selectedNetwork,
                            );
                            final planType = planTypes[index];
                            final isSelected = _selectedPlanType == planType;
                            final isEnabled = _isPlanTypeEnabled(planType);
                            return Padding(
                              padding: EdgeInsets.only(
                                right: _getResponsiveSpacing(context, 8),
                              ),
                              child: _buildPlanTypeButton(
                                planType,
                                isSelected,
                                isEnabled,
                                isEnabled
                                    ? () {
                                        setState(
                                          () => _selectedPlanType = planType,
                                        );
                                        // Fetch data plans after state update
                                        WidgetsBinding.instance
                                            .addPostFrameCallback((_) {
                                              _handleNetworkOrTypeChange();
                                            });
                                      }
                                    : null,
                              ),
                            );
                          },
                        ),
                      ),
                      SizedBox(height: _getResponsiveSpacing(context, 24)),
                      Text(
                        'Select Data Plan',
                        style: TextStyle(
                          fontSize: _getResponsiveFontSize(context, 14),
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      SizedBox(height: _getResponsiveSpacing(context, 12)),
                      if (_isLoadingPlans)
                        _buildShimmerLoader()
                      else if (_dataPlans.isEmpty)
                        Container(
                          padding: EdgeInsets.all(
                            _getResponsivePadding(context, 16),
                          ),
                          child: Center(
                            child: Text(
                              'No plans available',
                              style: TextStyle(
                                fontSize: _getResponsiveFontSize(context, 14),
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        )
                      else
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                childAspectRatio: 0.95,
                                mainAxisSpacing: _getResponsiveSpacing(
                                  context,
                                  10,
                                ),
                                crossAxisSpacing: _getResponsiveSpacing(
                                  context,
                                  10,
                                ),
                              ),
                          itemCount: _dataPlans.length,
                          itemBuilder: (context, index) {
                            final plan = _dataPlans[index];
                            final isSelected = _selectedPlan?.id == plan.id;
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedPlan = plan;
                                  _amountController.text = plan.price
                                      .toString();
                                });
                                // Validate before showing confirmation sheet
                                if (_validateBeforeConfirmation()) {
                                  _showConfirmationSheet();
                                }
                              },
                              child: Container(
                                padding: EdgeInsets.all(
                                  _getResponsivePadding(context, 8),
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? const Color(0xFFce4323)
                                      : Colors.white,
                                  border: Border.all(
                                    color: isSelected
                                        ? const Color(0xFFce4323)
                                        : Colors.grey.shade200,
                                    width: isSelected ? 2.5 : 1.5,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: isSelected
                                          ? const Color(
                                              0xFFce4323,
                                            ).withOpacity(0.15)
                                          : Colors.grey.shade100,
                                      blurRadius: isSelected ? 8 : 4,
                                      offset: const Offset(0, 2),
                                      spreadRadius: isSelected ? 1 : 0,
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    // Plan Name and Type
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: _getResponsivePadding(
                                              context,
                                              6,
                                            ),
                                            vertical: _getResponsivePadding(
                                              context,
                                              2,
                                            ),
                                          ),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? Colors.white.withOpacity(0.2)
                                                : const Color(
                                                    0xFFce4323,
                                                  ).withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            plan.planType.toUpperCase(),
                                            style: TextStyle(
                                              fontSize: _getResponsiveFontSize(
                                                context,
                                                10,
                                              ),
                                              fontWeight: FontWeight.w600,
                                              color: isSelected
                                                  ? Colors.white
                                                  : const Color(0xFFce4323),
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          height: _getResponsiveSpacing(
                                            context,
                                            8,
                                          ),
                                        ),
                                        Text(
                                          plan.name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: _getResponsiveFontSize(
                                              context,
                                              14,
                                            ),
                                            fontWeight: FontWeight.w700,
                                            color: isSelected
                                                ? Colors.white
                                                : Colors.black87,
                                            height: 1.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                    // Validity and Price
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.schedule,
                                              size: _getResponsiveIconSize(
                                                context,
                                                14,
                                              ),
                                              color: isSelected
                                                  ? Colors.white.withOpacity(
                                                      0.7,
                                                    )
                                                  : Colors.grey.shade500,
                                            ),
                                            SizedBox(
                                              width: _getResponsiveSpacing(
                                                context,
                                                4,
                                              ),
                                            ),
                                            Text(
                                              '${plan.validity} ${int.parse(plan.validity) == 1 ? 'Day' : 'Days'}',
                                              style: TextStyle(
                                                fontSize:
                                                    _getResponsiveFontSize(
                                                      context,
                                                      11,
                                                    ),
                                                color: isSelected
                                                    ? Colors.white.withOpacity(
                                                        0.8,
                                                      )
                                                    : Colors.grey.shade600,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                        SizedBox(
                                          height: _getResponsiveSpacing(
                                            context,
                                            6,
                                          ),
                                        ),
                                        Text(
                                          '₦${plan.price.toStringAsFixed(0)}',
                                          style: TextStyle(
                                            fontSize: _getResponsiveFontSize(
                                              context,
                                              18,
                                            ),
                                            fontWeight: FontWeight.bold,
                                            color: isSelected
                                                ? Colors.white
                                                : const Color(0xFFce4323),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      SizedBox(height: _getResponsiveSpacing(context, 24)),
                    ],
                  ),

                SizedBox(height: _getResponsiveSpacing(context, 24)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlanTypeButton(
    String label,
    bool isSelected,
    bool isEnabled,
    VoidCallback? onTap,
  ) {
    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.4,
        child: Container(
          padding: EdgeInsets.symmetric(
            vertical: _getResponsivePadding(context, 12),
            horizontal: _getResponsivePadding(context, 16),
          ),
          decoration: BoxDecoration(
            color: isSelected && isEnabled
                ? const Color(0xFFce4323)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: _getResponsiveFontSize(context, 14),
                fontWeight: FontWeight.bold,
                color: isSelected && isEnabled ? Colors.white : Colors.black,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
