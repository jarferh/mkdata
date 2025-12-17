import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/electricity_provider.dart';
import '../services/api_service.dart';
import 'transaction_details_page.dart';
import 'transactions_page.dart';
import 'dart:async';

class ElectricityPage extends StatefulWidget {
  const ElectricityPage({super.key});

  @override
  State<ElectricityPage> createState() => _ElectricityPageState();
}

class _ElectricityPageState extends State<ElectricityPage> {
  final _meterController = TextEditingController();
  final _phoneController = TextEditingController();
  final _amountController = TextEditingController();
  String? _amountError;
  final _pinController = TextEditingController();
  final _meterFocusNode = FocusNode();
  final _phoneFocusNode = FocusNode();
  final _amountFocusNode = FocusNode();

  final ApiService _apiService = ApiService();
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _isBiometricEnabled = false;

  ElectricityProvider? _selectedProvider;
  List<ElectricityProvider> _providers = [];
  String _selectedType = 'PREPAID';
  bool _isProcessing = false;
  bool _isValidated = false;
  bool _isLoadingProviders = true;
  bool _hasInternet = true;
  StreamSubscription? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _fetchProviders();
    _loadBiometricSettings();
    _checkInternetConnection();
    _setupConnectivityListener();
  }

  void _setupConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      result,
    ) {
      setState(() {
        _hasInternet = result != ConnectivityResult.none;
      });
    });
  }

  Future<bool> _checkInternetConnection() async {
    final result = await Connectivity().checkConnectivity();
    final hasInternet = result != ConnectivityResult.none;
    setState(() {
      _hasInternet = hasInternet;
    });
    return hasInternet;
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

  Future<String?> _authenticateAndGetPin() async {
    try {
      bool canCheckBiometrics = await _localAuth.canCheckBiometrics;
      bool hasHardware = await _localAuth.isDeviceSupported();

      if (!canCheckBiometrics || !hasHardware) {
        _showErrorModal(
          'Biometric Not Supported',
          'Biometric authentication is not supported on this device',
        );
        return null;
      }

      bool authenticated = await _localAuth.authenticate(
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

  Future<void> _fetchProviders() async {
    try {
      final response = await _apiService.getElectricityProviders();
      if (mounted) {
        List<ElectricityProvider> providers = [];

        // Parse providers from response
        if (response['status'] == 'success' && response['data'] != null) {
          final data = response['data'];
          if (data is List) {
            providers = data
                .map(
                  (p) =>
                      ElectricityProvider.fromJson(p as Map<String, dynamic>),
                )
                .toList();
          }
        }

        setState(() {
          _providers = providers;
          _isLoadingProviders = false;
          if (providers.isNotEmpty) {
            _selectedProvider = providers[0];
          }
        });
      }
    } catch (e) {
      print('Error fetching providers: $e');
      if (mounted) {
        setState(() {
          _isLoadingProviders = false;
        });
      }
    }
  }

  bool _validateBeforePurchase() {
    // Only validate meter on first click, show validation error but allow proceeding
    if (!_isValidated) {
      _showErrorModal(
        'Meter Not Validated',
        'Please validate the meter number first.',
      );
      // Allow proceeding anyway after validation attempt
      setState(() {
        _isValidated = true;
      });
      return false;
    }

    if (_amountController.text.isEmpty) {
      _showErrorModal('Amount Required', 'Please enter an amount to proceed.');
      return false;
    }

    final amount = double.tryParse(_amountController.text) ?? 0.0;
    if (amount < 100) {
      _showErrorModal(
        'Minimum Amount Required',
        'Minimum purchase amount is ₦100',
      );
      return false;
    }

    return true;
  }

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
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red.shade50,
                ),
                child: Icon(
                  Icons.error_outline,
                  color: Colors.red.shade600,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 20),
              if (onRetry != null)
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 44,
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
                        child: const Text(
                          'Try Again',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
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
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            color: Color(0xFFce4323),
                            fontSize: 14,
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
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFce4323),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'OK',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
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

  void _showConfirmationSheet() {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Confirm Purchase',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              _buildDetailRow('Provider', _selectedProvider?.name ?? ''),
              const SizedBox(height: 12),
              _buildDetailRow('Type', _selectedType),
              const SizedBox(height: 12),
              _buildDetailRow('Meter Number', _meterController.text),
              const SizedBox(height: 12),
              _buildDetailRow(
                'Amount',
                '₦${_amountController.text}',
                isAmount: true,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
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
                  child: const Text(
                    'Proceed to Payment',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade300, width: 1.5),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      color: Color(0xFFce4323),
                      fontSize: 14,
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
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isAmount ? 16 : 14,
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
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom:
                MediaQuery.of(context).viewInsets.bottom +
                MediaQuery.of(context).padding.bottom +
                12,
          ),
          color: Colors.white,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Input PIN to Pay',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 35,
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
                const SizedBox(height: 6),
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
                      return _isBiometricEnabled
                          ? _buildPinButton('', () async {
                              final pin = await _authenticateAndGetPin();
                              if (pin != null && pin.isNotEmpty) {
                                setModalState(() {
                                  pinInput = pin;
                                });
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
                      return _buildPinButton('0', () {
                        if (pinInput.length < 4) {
                          setModalState(() {
                            pinInput += '0';
                          });
                        }
                      });
                    } else {
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
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: pinInput.length == 4
                          ? () async {
                              final prefs =
                                  await SharedPreferences.getInstance();
                              final storedPin = prefs.getString('login_pin');

                              if (storedPin == null || pinInput != storedPin) {
                                Navigator.pop(context);
                                _showErrorModal(
                                  'Incorrect PIN',
                                  'The PIN you entered is incorrect. Please try again.',
                                  onRetry: () {
                                    _showPinSheet();
                                  },
                                );
                                return;
                              }

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
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _validateMeter() async {
    if (_selectedProvider == null) {
      _showErrorModal('No Provider Selected', 'Please select a biller first.');
      return;
    }

    final meter = _meterController.text.trim();
    if (meter.isEmpty) {
      _showErrorModal(
        'Meter Required',
        'Please enter a meter number to validate.',
      );
      return;
    }

    if (!_hasInternet) {
      _showErrorModal(
        'No Internet',
        'Please connect to the internet and try again.',
      );
      return;
    }

    // Show a simple loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final result = await _apiService.validateMeterNumber(
        meterNumber: meter,
        providerId: _selectedProvider!.id.toString(),
        meterType: _selectedType.toLowerCase(),
      );

      Navigator.pop(context); // dismiss loading

      if (result['status'] == 'success' || result['status'] == 'processing') {
        setState(() {
          _isValidated = true;
        });

        final name = result['data']?['name'] ?? '';
        final address = result['data']?['address'] ?? '';

        final message = name.isNotEmpty
            ? 'Meter validated: $name${address.isNotEmpty ? ' - $address' : ''}'
            : (result['message'] ?? 'Meter validated successfully');

        _showSimpleMessage('Meter Validated', message);
      } else {
        setState(() {
          _isValidated = false;
        });
        _showErrorModal(
          'Validation Failed',
          result['message'] ?? 'Invalid meter number',
        );
      }
    } catch (e) {
      Navigator.pop(context);
      setState(() {
        _isValidated = false;
      });
      _showErrorModal(
        'Validation Error',
        'An error occurred while validating the meter. Please try again.',
      );
    }
  }

  void _showSimpleMessage(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
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
              ? const Icon(
                  Icons.fingerprint,
                  color: Color(0xFFce4323),
                  size: 18,
                )
              : Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDelete ? Colors.grey.shade700 : Colors.black,
                  ),
                ),
        ),
      ),
    );
  }

  Future<void> _handlePurchase() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final hasInternet = await _checkInternetConnection();
      if (!hasInternet) {
        if (mounted) {
          setState(() => _isProcessing = false);
        }
        return;
      }

      // Debug: Log the values being sent
      print('DEBUG: Purchasing electricity with:');
      print('  Meter: ${_meterController.text}');
      print('  Provider ID: ${_selectedProvider!.id}');
      print('  Amount: ${_amountController.text}');
      print('  Type: ${_selectedType.toLowerCase()}');
      print('  Phone: ${_phoneController.text}');

      final response = await _apiService.purchaseElectricity(
        meterNumber: _meterController.text,
        providerId: _selectedProvider!.id,
        amount: _amountController.text,
        pin: _pinController.text,
        meterType: _selectedType.toLowerCase(),
        phone: _phoneController.text,
      );

      // Ensure we have an amount string to pass downstream
      final amountStr = _amountController.text.isNotEmpty
          ? _amountController.text
          : '0.00';

      // Normalize response and detect insufficient balance
      String status = 'failed';
      String transactionId = '';

      final code =
          (response['code'] ??
          response['statusCode'] ??
          response['status_code'] ??
          response['httpCode'] ??
          response['http_status']);

      // Consider the response as user-wallet insufficient only when the
      // API explicitly indicates it (HTTP 402 or an explicit error_type).
      // Avoid treating provider-side messages that mention "insufficient"
      // (which may refer to the provider's own balance) as a user-wallet issue.
      final isInsufficient =
          (code != null && code.toString() == '402') ||
          (response['error_type']?.toString() == 'user_insufficient');

      if (isInsufficient) {
        // Try to extract balances from response data
        String currentBalance = '';
        String requiredAmount = '';
        if (response['data'] is Map) {
          currentBalance =
              (response['data']['current_balance']?.toString() ??
              response['data']['balance']?.toString() ??
              '');
          requiredAmount =
              (response['data']['required_amount']?.toString() ??
              response['data']['needed']?.toString() ??
              '');
        }

        String details =
            'Your wallet balance is insufficient to complete this purchase.';
        if (currentBalance.isNotEmpty || requiredAmount.isNotEmpty) {
          details =
              'Current balance: ${currentBalance.isNotEmpty ? currentBalance : 'N/A'}\nRequired: ${requiredAmount.isNotEmpty ? requiredAmount : amountStr}';
        }

        if (!mounted) return;
        _showErrorModal('Insufficient Balance', details);
        setState(() => _isProcessing = false);
        return;
      }

      final rawStatus = (response['status'] ?? '').toString().toLowerCase();
      if (rawStatus.contains('success')) {
        status = 'success';
      } else if (rawStatus.contains('process') ||
          rawStatus.contains('pending')) {
        status = 'processing';
      } else {
        status = 'failed';
      }

      if (response['data'] != null && response['data'] is Map) {
        transactionId =
            (response['data']['transactionId']?.toString() ??
            response['data']['transaction_id']?.toString() ??
            '');
      }

      if (transactionId.isEmpty) {
        transactionId =
            (response['transactionId']?.toString() ??
            response['transaction_id']?.toString() ??
            '');
      }
    
      if (!mounted) return;

      // Always open TransactionDetailsPage so user can inspect the outcome
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TransactionDetailsPage(
            initialStatus: status,
            transactionId: transactionId,
            amount: amountStr,
            phoneNumber: _meterController.text,
            network: _selectedProvider?.name ?? '',
            planName: 'Electricity - $_selectedType',
            transactionDate: DateTime.now().toString(),
            planValidity: 'N/A',
            playOnOpen: false,
          ),
        ),
      );

      if (status == 'success') {
        _meterController.clear();
        _amountController.clear();
        _pinController.clear();
        _phoneController.clear();
        setState(() => _isValidated = false);
      } else {
        // If failed or other, surface validation-like errors alongside the details page
        setState(() {
          _amountError = null;
        });

        if (response['data'] != null &&
            response['data'] is Map) {
          final data = response['data'] as Map;
          if (data.containsKey('amount') &&
              data['amount'] is List &&
              data['amount'].isNotEmpty) {
            setState(() {
              _amountError = data['amount'][0].toString();
            });
          }
        }
      }
    } catch (e) {
      _showErrorModal(
        'Error',
        'An error occurred while processing your request.',
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _meterController.dispose();
    _phoneController.dispose();
    _amountController.dispose();
    _pinController.dispose();
    _meterFocusNode.dispose();
    _phoneFocusNode.dispose();
    _amountFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFFce4323),
        elevation: 0,
        title: const Text(
          'Electricity',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TransactionsPage(),
                ),
              );
            },
            child: const Text(
              'History',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!_hasInternet)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.wifi_off, color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No internet connection. Purchases are disabled.',
                            style: TextStyle(
                              color: Colors.red.shade900,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const Text(
                  'Select Biller',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300, width: 1.5),
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.white,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _isLoadingProviders
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'Loading providers...',
                              style: TextStyle(
                                color: Color(0xFFce4323),
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFFce4323),
                              ),
                            ),
                          ],
                        )
                      : DropdownButtonHideUnderline(
                          child: DropdownButton<ElectricityProvider>(
                            value: _selectedProvider,
                            isExpanded: true,
                            onChanged: (ElectricityProvider? value) {
                              if (value != null) {
                                setState(() {
                                  _selectedProvider = value;
                                  _isValidated = false;
                                });
                              }
                            },
                            items: _providers
                                .map<DropdownMenuItem<ElectricityProvider>>(
                                  (provider) => DropdownMenuItem(
                                    value: provider,
                                    child: Text(
                                      provider.name,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ),
                                )
                                .toList(),
                            hint: const Text('Select Biller'),
                          ),
                        ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildTypeButton(
                        'POSTPAID',
                        _selectedType == 'POSTPAID',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTypeButton(
                        'PREPAID',
                        _selectedType == 'PREPAID',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Meter Number',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _meterController,
                  focusNode: _meterFocusNode,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'meter number',
                    hintStyle: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Color(0xFFce4323),
                        width: 2,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: ElevatedButton(
                          onPressed: _isProcessing || !_hasInternet
                              ? null
                              : () async {
                                  await _validateMeter();
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isValidated
                                ? Colors.green
                                : const Color(0xFFce4323),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            _isValidated ? 'Verified' : 'Verify Meter',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_isValidated)
                      Icon(Icons.check_circle, color: Colors.green.shade700),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Amount',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _amountController,
                  focusNode: _amountFocusNode,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Amount',
                    hintStyle: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Color(0xFFce4323),
                        width: 2,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    errorText: _amountError,
                    prefixText: '₦ ',
                  ),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: (_isProcessing || !_hasInternet)
                        ? null
                        : () {
                            bool validation = _validateBeforePurchase();
                            // Allow proceeding even if validation fails on first click
                            if (!validation && !_isValidated) {
                              return;
                            }
                            _showConfirmationSheet();
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
                              const Text(
                                'Processing...',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              ),
                            ],
                          )
                        : const Text(
                            'Next',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
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

  Widget _buildTypeButton(String type, bool isSelected) {
    return GestureDetector(
      onTap: () => setState(() => _selectedType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? const Color(0xFFce4323) : Colors.grey.shade300,
            width: isSelected ? 2 : 1.5,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? const Color(0xFFce4323).withOpacity(0.05)
              : Colors.white,
        ),
        child: Center(
          child: Text(
            type,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isSelected
                  ? const Color(0xFFce4323)
                  : Colors.grey.shade600,
            ),
          ),
        ),
      ),
    );
  }
}
