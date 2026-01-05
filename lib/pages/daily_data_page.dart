import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
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

class DailyDataPage extends StatefulWidget {
  const DailyDataPage({super.key});

  @override
  State<DailyDataPage> createState() => _DailyDataPageState();
}

class _DailyDataPageState extends State<DailyDataPage> {
  final _phoneController = TextEditingController();
  final _amountController = TextEditingController();
  final _daysController = TextEditingController();
  final _pinController = TextEditingController();
  final LocalAuthentication _localAuth = LocalAuthentication();
  String _selectedNetwork = '';
  String _selectedPlanType = '';
  bool _isBiometricEnabled = false;
  Map<String, dynamic> _networkStatuses = {};
  bool _verifyNumber = false;
  int _selectedDays = 1; // Default to 1 day

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
      '07025',
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

  bool _isNetworkEnabled(String networkName) {
    final normalized = networkName.toUpperCase();
    final status = _networkStatuses[normalized];
    if (status == null) return true;
    return status['networkStatus'] == 'On';
  }

  bool _isPlanTypeEnabled(String planType) {
    final normalized = _selectedNetwork.toUpperCase();
    final status = _networkStatuses[normalized];
    if (status == null) {
      return true;
    }

    if (planType.contains('SME2')) {
      return status['sme2Status'] == 'On';
    } else if (planType.contains('SME')) {
      return status['smeStatus'] == 'On';
    } else if (planType.contains('Corporate')) {
      return status['corporateStatus'] == 'On';
    } else if (planType.contains('Gifting')) {
      return status['giftingStatus'] == 'On';
    } else if (planType.contains('Coupon')) {
      return status['couponStatus'] == 'On';
    }
    return true;
  }

  final FocusNode _phoneFocusNode = FocusNode();
  String? _phoneError;
  bool _phoneValid = false;
  final bool _isProcessing = false;
  StreamSubscription? _connectivitySubscription;
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
    _fetchNetworkStatuses();
    _checkBiometricSettings();
    _initConnectivity();

    _phoneController.addListener(() {
      final value = _phoneController.text.trim();

      // Auto-detect network and refresh plans when the detected network changes
      final detected = _networkFromPhone(value);
      if (detected != null && detected != _selectedNetwork) {
        setState(() {
          _selectedNetwork = detected;
          _selectedPlan = null;
          _amountController.clear();
          _daysController.text = '1';
          _selectedDays = 1;
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

    // Initialize days controller
    _daysController.text = '1';
  }

  Future<bool> _checkInternetConnection() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result != ConnectivityResult.none;
    } catch (e) {
      return false;
    }
  }

  Future<void> _verifyInternetAccess() async {
    // Verify internet connection is available
    try {
      await _checkInternetConnection();
    } catch (e) {
      print('Internet verification error: $e');
    }
  }

  Future<void> _initConnectivity() async {
    await _checkInternetConnection();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      result,
    ) async {
      await _verifyInternetAccess();
    });
  }

  Future<void> _fetchDataPlans() async {
    if (_isLoadingPlans) return;

    if (!await _checkInternetConnection()) {
      return;
    }

    setState(() {
      _isLoadingPlans = true;
      _dataPlans = [];
      _selectedPlan = null;
    });

    try {
      final networkName = _selectedNetwork;
      final type = _apiTypeForLabel(_selectedPlanType);

      print('Fetching data plans for network $networkName and type $type');

      final userId = await ApiService().getUserId();

      final queryParameters = {
        'network': networkName,
        if (type != null) 'type': type,
        if (userId != null) 'userId': userId,
      };

      final api = ApiService();
      final query = Uri(queryParameters: queryParameters).query;
      final data = await api.get('data-plans?$query');
      if (data['status'] == 'success' && data['data'] != null) {
        final plans = (data['data'] as List)
            .map((plan) => DataPlan.fromJson(plan))
            .toList();
        setState(() {
          _dataPlans = plans;
        });
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

  void _handleNetworkOrTypeChange() {
    _selectedPlan = null;
    _amountController.clear();
    _daysController.text = '1';
    _selectedDays = 1;
    _fetchDataPlans();
  }

  String? _apiTypeForLabel(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('sme2')) return 'SME2';
    if (lower.contains('sme')) return 'SME';
    if (lower.contains('corporate')) return 'Corporate';
    if (lower.contains('gift')) return 'Gifting';
    if (lower.contains('coupon')) return 'Coupon';
    return null;
  }

  void _updateAmount() {
    if (_selectedPlan != null) {
      final totalAmount = _selectedPlan!.price * _selectedDays;
      setState(() {
        _amountController.text = totalAmount.toStringAsFixed(2);
      });
    }
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
    _daysController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<String?> _authenticateAndGetPin() async {
    try {
      final isDeviceSupported = await _localAuth.canCheckBiometrics;

      if (!isDeviceSupported) {
        return null;
      }

      final isAuthenticated = await _localAuth.authenticate(
        localizedReason: 'Authenticate to retrieve your PIN',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (!isAuthenticated) {
        return null;
      }

      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('login_pin');
    } catch (e) {
      print('Error during biometric authentication: $e');
      return null;
    }
  }

  bool _validateBeforeConfirmation() {
    if (_selectedNetwork.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a network'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    if (_phoneController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a phone number'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    if (!_phoneValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Phone number does not match selected network'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    if (_selectedPlan == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a data plan'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    if (_selectedDays < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter valid number of days'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    return true;
  }

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
                'Confirm Daily Data Transaction',
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
                'Daily Validity',
                '${_selectedPlan?.validity ?? 0} DAYS',
              ),
              SizedBox(height: _getResponsiveSpacing(context, 16)),
              _buildDetailRow('Number of Days', _selectedDays.toString()),
              SizedBox(height: _getResponsiveSpacing(context, 16)),
              _buildDetailRow(
                'Price Per Day',
                '₦${_selectedPlan?.price.toStringAsFixed(2) ?? '0'}',
              ),
              SizedBox(height: _getResponsiveSpacing(context, 16)),
              _buildDetailRow('Mobile Number', _phoneController.text),
              SizedBox(height: _getResponsiveSpacing(context, 16)),
              _buildDetailRow(
                'Total Amount',
                '₦${_amountController.text}',
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

                                // Show error
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Incorrect PIN'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                if (mounted) {
                                  _showPinSheet(); // Show PIN sheet again
                                }
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
                          color: Colors.white,
                          fontSize: _getResponsiveFontSize(context, 16),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
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
    await _processDailyDataPurchase();
  }

  Future<void> _processDailyDataPurchase() async {
    // PIN is already verified in the sheet, just process the purchase
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
        // Dismiss loading dialog
        if (_isPinLoadingShown) {
          try {
            Navigator.of(context, rootNavigator: true).pop();
          } catch (_) {}
          _isPinLoadingShown = false;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Insufficient balance (₦${walletBalance.toString()}) for this purchase of ₦${required.toString()}',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    } catch (e) {
      print('Balance check error: $e');
    }

    try {
      final userId = await ApiService().getUserId();

      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final networkName = _selectedNetwork;

      print('Purchasing daily data with:');
      print('Network: $networkName');
      print('Phone Number: ${_phoneController.text}');
      print('Plan ID: ${_selectedPlan!.planCode}');
      print('Days: $_selectedDays');
      print('Total Amount: ${_amountController.text}');
      print('User ID: $userId');

      // Call the daily data purchase API
      final api = ApiService();
      final response = await api.post('purchase-daily-data', {
        'user_id': userId,
        'plan_id': _selectedPlan!.planCode,
        'network': networkName,
        'phone_number': _phoneController.text,
        'user_type': _selectedPlan!.planType,
        'price_per_day': _selectedPlan!.price,
        'total_days': _selectedDays,
        'pin': _pinController.text,
      });

      print('API Response: $response');

      // Dismiss loading dialog
      if (_isPinLoadingShown) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
        _isPinLoadingShown = false;
      }

      if (response['status'] == 'success') {
        final data = response['data'];
        final transactionRef =
            data['transaction_reference'] ??
            'MK_${DateTime.now().millisecondsSinceEpoch}';
        final amount =
            data['total_amount']?.toString() ?? _amountController.text;
        final transactionDate = DateTime.now().toString();
        final phoneNumber = _phoneController.text;

        // Clear form
        _phoneController.clear();
        _pinController.clear();
        setState(() {
          _selectedPlan = null;
          _amountController.clear();
          _daysController.text = '1';
          _selectedDays = 1;
        });

        // Navigate to transaction details page
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => TransactionDetailsPage(
                initialStatus: 'success',
                transactionId: transactionRef,
                amount: amount,
                phoneNumber: phoneNumber,
                network: _selectedNetwork,
                planName: 'Daily Data ${_selectedPlan?.name ?? ''}',
                transactionDate: transactionDate,
                planValidity:
                    '$_selectedDays days (${_selectedPlan?.validity ?? '30'} days validity per day)',
                playOnOpen: true,
              ),
            ),
          );
        }
      } else {
        throw Exception(response['message'] ?? 'Failed to purchase daily data');
      }
    } on TimeoutException catch (e) {
      // Dismiss loading dialog
      if (_isPinLoadingShown) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
        _isPinLoadingShown = false;
      }

      showNetworkErrorSnackBar(
        context,
        e,
        fontSize: _getResponsiveFontSize(context, 14),
      );
    } on SocketException catch (e) {
      // Dismiss loading dialog
      if (_isPinLoadingShown) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
        _isPinLoadingShown = false;
      }

      showNetworkErrorSnackBar(
        context,
        e,
        fontSize: _getResponsiveFontSize(context, 14),
      );
    } catch (e) {
      print('Error during daily data purchase: ${e.toString()}');

      // Dismiss loading dialog
      if (_isPinLoadingShown) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
        _isPinLoadingShown = false;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
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
        ),
      ),
    );
  }

  Widget _buildPlanTypeButton(
    String planType,
    bool isSelected,
    bool isEnabled,
    VoidCallback? onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isEnabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Opacity(
          opacity: isEnabled ? 1.0 : 0.5,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: _getResponsivePadding(context, 12),
              vertical: _getResponsivePadding(context, 8),
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFFce4323)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFFce4323)
                    : Colors.grey.shade300,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Text(
              planType,
              style: TextStyle(
                fontSize: _getResponsiveFontSize(context, 12),
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ),
      ),
    );
  }

  double _getResponsivePadding(BuildContext context, double basePadding) {
    final screenWidth = MediaQuery.of(context).size.width;
    final scaleFactor = screenWidth / 375;
    return basePadding * scaleFactor.clamp(0.8, 1.2);
  }

  double _getResponsiveSpacing(BuildContext context, double baseSpacing) {
    final screenWidth = MediaQuery.of(context).size.width;
    final scaleFactor = screenWidth / 375;
    return baseSpacing * scaleFactor.clamp(0.8, 1.2);
  }

  double _getResponsiveFontSize(BuildContext context, double baseSize) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 360) {
      return baseSize * 0.9;
    } else if (screenWidth < 400) {
      return baseSize * 0.95;
    } else if (screenWidth < 500) {
      return baseSize * 1.0;
    } else {
      return baseSize * 1.05;
    }
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFFce4323),
        elevation: 0,
        title: Text(
          'Daily Data',
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
                // STEP 1: Network Selection
                Text(
                  'Select Network',
                  style: TextStyle(
                    fontSize: _getResponsiveFontSize(context, 16),
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                SizedBox(height: _getResponsiveSpacing(context, 12)),

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

                // STEP 2: Mobile Number Input
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

                // STEP 3 & 4: Plan Type and Data Plans (only shown after network selected)
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
                                  _selectedDays = 1;
                                  _daysController.text = '1';
                                  _updateAmount();
                                });
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
                      // STEP 5: Days Selection (only shown when plan is selected)
                      if (_selectedPlan != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: _getResponsiveSpacing(context, 24),
                            ),
                            Text(
                              'Number of Days',
                              style: TextStyle(
                                fontSize: _getResponsiveFontSize(context, 14),
                                fontWeight: FontWeight.w600,
                                color: Colors.black,
                              ),
                            ),
                            SizedBox(height: _getResponsiveSpacing(context, 8)),
                            TextField(
                              controller: _daysController,
                              onChanged: (value) {
                                try {
                                  final days = int.parse(value);
                                  if (days >= 1) {
                                    setState(() {
                                      _selectedDays = days;
                                      _updateAmount();
                                    });
                                  }
                                } catch (e) {
                                  // Invalid input, ignore
                                }
                              },
                              keyboardType: TextInputType.number,
                              style: TextStyle(
                                fontSize: _getResponsiveFontSize(context, 14),
                              ),
                              decoration: InputDecoration(
                                hintText: 'Enter number of days',
                                hintStyle: TextStyle(
                                  fontSize: _getResponsiveFontSize(context, 14),
                                  color: Colors.grey,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFce4323),
                                    width: 2,
                                  ),
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: _getResponsivePadding(
                                    context,
                                    12,
                                  ),
                                  vertical: _getResponsivePadding(context, 12),
                                ),
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                            ),
                            SizedBox(
                              height: _getResponsiveSpacing(context, 20),
                            ),
                            // Total Amount (Read-only)
                            Text(
                              'Total Amount',
                              style: TextStyle(
                                fontSize: _getResponsiveFontSize(context, 14),
                                fontWeight: FontWeight.w600,
                                color: Colors.black,
                              ),
                            ),
                            SizedBox(height: _getResponsiveSpacing(context, 8)),
                            TextField(
                              controller: _amountController,
                              readOnly: true,
                              style: TextStyle(
                                fontSize: _getResponsiveFontSize(context, 14),
                                fontWeight: FontWeight.bold,
                                color: Colors.purple,
                              ),
                              decoration: InputDecoration(
                                hintText: '₦0.00',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                disabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade200,
                                  ),
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: _getResponsivePadding(
                                    context,
                                    12,
                                  ),
                                  vertical: _getResponsivePadding(context, 12),
                                ),
                              ),
                            ),
                            SizedBox(
                              height: _getResponsiveSpacing(context, 28),
                            ),
                            // Proceed Button
                            SizedBox(
                              width: double.infinity,
                              height: _getResponsiveIconSize(context, 52),
                              child: ElevatedButton(
                                onPressed: () {
                                  if (_validateBeforeConfirmation()) {
                                    _showConfirmationSheet();
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFce4323),
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  'Proceed',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: _getResponsiveFontSize(
                                      context,
                                      16,
                                    ),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                              height: _getResponsiveSpacing(context, 20),
                            ),
                          ],
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
