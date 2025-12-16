import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import './transactions_page.dart';
import './transaction_details_page.dart';
import 'dart:async';
import 'dart:convert';
import '../services/api_service.dart';

class CablePage extends StatefulWidget {
  const CablePage({super.key});

  @override
  State<CablePage> createState() => _CablePageState();
}

class _CablePageState extends State<CablePage> {
  final _cardNumberController = TextEditingController();
  final _phoneController = TextEditingController();
  final _pinController = TextEditingController();
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _isBiometricEnabled = false;

  String? _selectedProviderId;
  String? _selectedProviderName;
  String? _selectedPlanId;
  String? _selectedPlanName;
  double? _selectedPlanPrice;

  bool _isProcessing = false;
  bool _isLoadingProviders = true;
  bool _hasInternet = true;
  StreamSubscription? _connectivitySubscription;

  late ApiService _apiService;
  List<Map<String, dynamic>> _providers = [];
  List<Map<String, dynamic>> _currentPlans = [];

  @override
  void initState() {
    super.initState();
    _apiService = ApiService();
    _checkBiometricSettings();
    _initConnectivity();
    _fetchProviders();
    _populatePhoneFromProfile();
  }

  Future<void> _populatePhoneFromProfile() async {
    try {
      final userData = await _apiService.getUserData();
      if (userData != null) {
        final phone =
            (userData['sPhone'] ??
                    userData['phone'] ??
                    userData['mobile'] ??
                    '')
                ?.toString();
        if (phone != null && phone.isNotEmpty) {
          _phoneController.text = phone;
        }
      }
    } catch (e) {
      // ignore errors filling phone
    }
  }

  Future<void> _fetchProviders() async {
    try {
      final response = await _apiService.getCableProviders();

      if (response['status'] == 'success' && response['data'] != null) {
        List<Map<String, dynamic>> providers = [];

        if (response['data'] is List) {
          providers = List<Map<String, dynamic>>.from(
            response['data'].map(
              (p) => {
                'id': p['id'] ?? p['cId']?.toString(),
                'name': p['provider'] ?? '',
                'cableid': p['cableid'],
                'status': p['status'] ?? 'On',
              },
            ),
          );
        }

        if (mounted) {
          setState(() {
            _providers = providers;
            _isLoadingProviders = false;

            // Auto-select first provider
            if (providers.isNotEmpty) {
              _selectedProviderId = providers[0]['id'].toString();
              _selectedProviderName = providers[0]['name'];
              _loadPlansForProvider(providers[0]['id'].toString());
            }
          });
        }
      }
    } catch (e) {
      print('Error fetching cable providers: $e');
      if (mounted) {
        setState(() => _isLoadingProviders = false);
      }
    }
  }

  Future<void> _loadPlansForProvider(String providerId) async {
    try {
      setState(() => _selectedPlanId = null);

      final response = await _apiService.getCablePlans(providerId: providerId);

      if (response['status'] == 'success' && response['data'] != null) {
        List<Map<String, dynamic>> plans = [];

        if (response['data'] is List) {
          plans = List<Map<String, dynamic>>.from(
            response['data'].map(
              (p) => {
                'id': p['planid']?.toString(),
                'name': p['name'] ?? '',
                'price':
                    double.tryParse(
                      p['userprice']?.toString() ??
                          p['price']?.toString() ??
                          '0',
                    ) ??
                    0.0,
                'day': p['day'],
              },
            ),
          );
        }

        if (mounted) {
          setState(() => _currentPlans = plans);
        }
      }
    } catch (e) {
      print('Error fetching cable plans: $e');
      if (mounted) {
        _showErrorModal(
          'Failed to load plans',
          'Unable to load cable plans. Please try again later.',
        );
      }
    }
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

  Future<void> _checkBiometricSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _isBiometricEnabled = prefs.getBool('biometric_enabled') ?? false;
      });
    } catch (e) {
      // Error loading biometric settings
    }
  }

  Future<String?> _authenticateAndGetPin() async {
    try {
      bool canCheckBiometrics = await _localAuth.canCheckBiometrics;
      bool hasHardware = await _localAuth.isDeviceSupported();

      if (!canCheckBiometrics || !hasHardware) {
        if (!mounted) return null;
        _showErrorModal(
          'Biometric Not Supported',
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
      // Error during biometric authentication
    }
    return null;
  }

  Future<void> _initConnectivity() async {
    _hasInternet = await _checkInternetConnection();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      _,
    ) async {
      final ok = await _verifyInternetAccess();
      if (mounted) setState(() => _hasInternet = ok);
    });
  }

  Future<bool> _checkInternetConnection() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        setState(() => _hasInternet = false);
        return false;
      }
      final ok = await _verifyInternetAccess();
      setState(() => _hasInternet = ok);
      return ok;
    } catch (e) {
      setState(() => _hasInternet = false);
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

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _cardNumberController.dispose();
    _phoneController.dispose();
    _pinController.dispose();
    super.dispose();
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
                                  _handleNext();
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
                              _handleNext();
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

  Widget _buildProviderIcon(String name) {
    final key = name.toLowerCase();
    String? assetPath;
    if (key.contains('dstv')) {
      assetPath = 'assets/images/dstv.png';
    } else if (key.contains('gotv') || key.contains('go tv')) {
      assetPath = 'assets/images/gotv.png';
    } else if (key.contains('startime') ||
        key.contains('startimes') ||
        key.contains('star')) {
      assetPath = 'assets/images/startimes.png';
    }

    if (assetPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.asset(
          assetPath,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stack) => _providerInitials(name),
        ),
      );
    }

    return _providerInitials(name);
  }

  Widget _providerInitials(String name) {
    final initials = name.trim().isEmpty
        ? '?'
        : name
              .trim()
              .split(' ')
              .map((p) => p.isNotEmpty ? p[0] : '')
              .take(2)
              .join()
              .toUpperCase();
    return CircleAvatar(
      radius: 18,
      backgroundColor: Colors.grey.shade200,
      child: Text(
        initials,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
      ),
    );
  }

  Future<void> _handleNext() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    // Validate inputs
    if (_selectedProviderId == null || _selectedProviderId!.isEmpty) {
      _showErrorModal('Missing Provider', 'Please select a provider');
      setState(() => _isProcessing = false);
      return;
    }

    if (_selectedPlanId == null || _selectedPlanId!.isEmpty) {
      _showErrorModal('Missing Plan', 'Please select a cable plan');
      setState(() => _isProcessing = false);
      return;
    }

    if (_cardNumberController.text.isEmpty) {
      _showErrorModal('Missing Card Number', 'Please enter smart card number');
      setState(() => _isProcessing = false);
      return;
    }

    if (_phoneController.text.isEmpty) {
      _showErrorModal('Missing Phone', 'Please enter phone number');
      setState(() => _isProcessing = false);
      return;
    }

    if (_pinController.text.isEmpty) {
      _showErrorModal('Missing PIN', 'Please enter PIN');
      setState(() => _isProcessing = false);
      return;
    }

    double amountDouble = 0.0;
    String amountStr = '0.00';

    try {
      // Determine amount from selected plan or stored price
      final selectedPlan = _currentPlans.firstWhere(
        (p) => p['id']?.toString() == _selectedPlanId?.toString(),
        orElse: () => {},
      );
      if (selectedPlan != null && selectedPlan.isNotEmpty) {
        amountDouble = (selectedPlan['price'] is double)
            ? selectedPlan['price'] as double
            : double.tryParse(selectedPlan['price']?.toString() ?? '0') ?? 0.0;
      } else if (_selectedPlanPrice != null) {
        amountDouble = _selectedPlanPrice!;
      }

      amountStr = amountDouble.toStringAsFixed(2);

      final res = await _apiService.purchaseCable(
        providerId: _selectedProviderId!,
        planId: _selectedPlanId!,
        iucNumber: _cardNumberController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        amount: amountStr,
        pin: _pinController.text.trim(),
      );

      // Normalize status and extract transaction id if available
      String status = 'failed';
      String transactionId = '';

      if (res != null) {
        // Detect insufficient funds (HTTP 402) responses from backend.
        // Backend may include numeric code fields or embed messages mentioning 'insufficient'.
        final code =
            (res['code'] ??
            res['statusCode'] ??
            res['status_code'] ??
            res['httpCode'] ??
            res['http_status']);
        final msg = (res['message'] ?? '').toString().toLowerCase();

        final isInsufficient =
            (code != null && code.toString() == '402') ||
            msg.contains('insufficient') ||
            msg.contains('insufficient balance') ||
            msg.contains('insufficient funds');

        if (isInsufficient) {
          // Try to extract balance details if available
          String currentBalance = '';
          String requiredAmount = '';
          if (res['data'] is Map) {
            currentBalance =
                (res['data']['current_balance']?.toString() ??
                res['data']['balance']?.toString() ??
                '');
            requiredAmount =
                (res['data']['required_amount']?.toString() ??
                res['data']['needed']?.toString() ??
                '');
          }

          String details =
              'Your wallet balance is insufficient to complete this purchase.';
          if (currentBalance.isNotEmpty || requiredAmount.isNotEmpty) {
            details =
                'Current balance: ${currentBalance.isNotEmpty ? currentBalance : 'N/A'}\nRequired: ${requiredAmount.isNotEmpty ? requiredAmount : amountStr}';
          }

          if (!mounted) return;
          // Show modal prompting user to top up. Do not open TransactionDetailsPage for insufficient balance.
          _showErrorModal(
            'Insufficient Balance',
            details,
            onRetry: () {
              // User may retry after topping up; we simply close the modal and let them retry.
            },
          );

          setState(() => _isProcessing = false);
          return;
        }

        final rawStatus = (res['status'] ?? '').toString().toLowerCase();
        if (rawStatus.contains('success')) {
          status = 'success';
        } else if (rawStatus.contains('process') ||
            rawStatus.contains('pending')) {
          status = 'processing';
        } else {
          status = 'failed';
        }

        if (res['data'] != null && res['data'] is Map) {
          transactionId =
              (res['data']['transactionId']?.toString() ??
              res['data']['transaction_id']?.toString() ??
              '');
        }

        if (transactionId.isEmpty) {
          transactionId =
              (res['transactionId']?.toString() ??
              res['transaction_id']?.toString() ??
              '');
        }

        // If still empty try to parse JSON encoded message (server may embed details in message)
        if (transactionId.isEmpty && res['message'] is String) {
          try {
            final parsed = jsonDecode(res['message']);
            if (parsed is Map && parsed['transactionId'] != null) {
              transactionId = parsed['transactionId'].toString();
            } else if (parsed is Map && parsed['transaction_id'] != null) {
              transactionId = parsed['transaction_id'].toString();
            }
          } catch (_) {
            // ignore parse errors
          }
        }
      }

      if (!mounted) return;

      // Open the transaction details page so user can see success/failure/processing
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TransactionDetailsPage(
            initialStatus: status,
            transactionId: transactionId,
            amount: amountStr,
            phoneNumber: _phoneController.text.trim(),
            network: _selectedProviderName ?? '',
            planName: _selectedPlanName ?? '',
            transactionDate: DateTime.now().toString(),
            planValidity:
                (_currentPlans
                    .firstWhere(
                      (p) => p['id']?.toString() == _selectedPlanId?.toString(),
                      orElse: () => {},
                    )['day']
                    ?.toString() ??
                'N/A'),
            playOnOpen: false,
          ),
        ),
      );

      if (mounted) {
        setState(() => _isProcessing = false);

        if (status == 'success') {
          // Clear form on success
          _cardNumberController.clear();
          _pinController.clear();
          setState(() {
            _selectedProviderId = null;
            _selectedPlanId = null;
            _selectedProviderName = null;
            _selectedPlanName = null;
            _selectedPlanPrice = null;
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);

      // Try to extract a transactionId from the error message if the server included one
      String transactionId = '';
      final errMsg = e?.toString() ?? '';
      if (errMsg.isNotEmpty) {
        try {
          final parsed = jsonDecode(errMsg);
          if (parsed is Map && parsed['transactionId'] != null) {
            transactionId = parsed['transactionId'].toString();
          } else if (parsed is Map && parsed['transaction_id'] != null) {
            transactionId = parsed['transaction_id'].toString();
          }
        } catch (_) {
          // ignore
        }
      }

      // Open transaction details page with failed status so user can inspect outcome
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TransactionDetailsPage(
            initialStatus: 'failed',
            transactionId: transactionId,
            amount: amountStr,
            phoneNumber: _phoneController.text.trim(),
            network: _selectedProviderName ?? '',
            planName: _selectedPlanName ?? '',
            transactionDate: DateTime.now().toString(),
            planValidity: 'N/A',
            playOnOpen: false,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild a clean UI for the cable page
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFFce4323),
        elevation: 0,
        title: const Text(
          'Cable',
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
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TransactionsPage()),
            ),
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
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_hasInternet)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade100),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.wifi_off, color: Colors.red),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'No internet connection',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ),

              const Text(
                'Select Cable Provider',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 12),

              _isLoadingProviders
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _providers.map((provider) {
                          final id = provider['id']?.toString() ?? '';
                          final name = provider['name'] ?? '';
                          final isSelected = _selectedProviderId == id;
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedProviderId = id;
                                _selectedProviderName = name;
                                _currentPlans = [];
                                _selectedPlanId = null;
                                _selectedPlanName = null;
                                _selectedPlanPrice = null;
                              });
                              _loadPlansForProvider(id);
                            },
                            child: Container(
                              width: 110,
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFFce4323)
                                      : Colors.grey.shade300,
                                  width: isSelected ? 2 : 1.2,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                color: isSelected
                                    ? const Color(0xFFce4323).withOpacity(0.08)
                                    : Colors.white,
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // provider icon (use asset if available, fallback to initials)
                                    SizedBox(
                                      height: 36,
                                      width: 36,
                                      child: _buildProviderIcon(name),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      name,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: isSelected
                                            ? const Color(0xFFce4323)
                                            : Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

              const SizedBox(height: 20),
              const Text(
                'Cable Plan',
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
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedPlanId,
                    isExpanded: true,
                    hint: const Text('Select Cable Plan'),
                    onChanged: (String? value) {
                      if (value != null) {
                        final plan = _currentPlans.firstWhere(
                          (p) => p['id'] == value,
                          orElse: () => {},
                        );
                        setState(() {
                          _selectedPlanId = value;
                          _selectedPlanName = plan['name'];
                          _selectedPlanPrice = plan['price'];
                        });
                      }
                    },
                    items: _currentPlans.map<DropdownMenuItem<String>>((plan) {
                      final price = (plan['price'] is double)
                          ? plan['price'] as double
                          : double.tryParse(plan['price']?.toString() ?? '0') ??
                                0.0;
                      return DropdownMenuItem<String>(
                        value: plan['id']?.toString(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  plan['name'] ?? '',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Text(
                                '₦${price.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFce4323),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

              const SizedBox(height: 20),
              const Text(
                'Smart Card Number / Decoder Number',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _cardNumberController,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Smart Card Number / Decoder Number',
                  hintStyle: const TextStyle(fontSize: 14, color: Colors.grey),
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
                  suffixIcon: const Icon(Icons.person, color: Colors.grey),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
              ),

              const SizedBox(height: 12),
              const Text(
                'Phone Number',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Phone number for this subscription',
                  hintStyle: const TextStyle(fontSize: 14, color: Colors.grey),
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
                  suffixIcon: const Icon(Icons.phone, color: Colors.grey),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
              ),

              // PIN input is handled via secure modal bottom sheet (_showPinSheet)
              const SizedBox(height: 8),

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: (_isProcessing || !_hasInternet)
                      ? null
                      : () {
                          if (_selectedProviderId != null &&
                              _selectedPlanId != null &&
                              _cardNumberController.text.isNotEmpty) {
                            _showPinSheet();
                          } else {
                            _showErrorModal(
                              'Missing Information',
                              'Please fill all fields and select a plan',
                            );
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
                          children: const [
                            Text(
                              'Processing...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(width: 8),
                            SizedBox(
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
    );
  }
}
