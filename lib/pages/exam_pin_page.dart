import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import './transactions_page.dart';
import './transaction_details_page.dart';
import 'dart:async';
import '../utils/network_utils.dart';
import '../services/api_service.dart';

class ExamPinPage extends StatefulWidget {
  const ExamPinPage({super.key});

  @override
  State<ExamPinPage> createState() => _ExamPinPageState();
}

class _ExamPinPageState extends State<ExamPinPage> {
  final _quantityController = TextEditingController(text: '1');
  final _pinController = TextEditingController();
  final LocalAuthentication _localAuth = LocalAuthentication();
  final ApiService _apiService = ApiService();
  bool _isBiometricEnabled = false;

  String? _selectedExam;
  String? _selectedExamId;
  bool _isProcessing = false;
  bool _hasInternet = true;
  bool _isLoadingProviders = true;
  StreamSubscription? _connectivitySubscription;

  // Exam providers with logos, IDs, and prices
  List<Map<String, dynamic>> _examProviders = [];
  double _selectedPrice = 0;
  double _totalAmount = 0;
  double _userBalance = 0.0;

  @override
  void initState() {
    super.initState();
    _checkBiometricSettings();
    _initConnectivity();
    _loadUserBalance();
    _loadExamProviders();
    _quantityController.addListener(_updateTotalAmount);
  }

  Future<void> _loadUserBalance() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataJson = prefs.getString('user_data');

      if (userDataJson != null) {
        final userData = jsonDecode(userDataJson);
        final balance = userData['sWallet'];

        setState(() {
          _userBalance = balance is String
              ? double.tryParse(balance) ?? 0.0
              : (balance as num).toDouble();
        });

        print('User balance loaded: $_userBalance');
      }
    } catch (e) {
      print('Error loading user balance: $e');
      setState(() => _userBalance = 0.0);
    }
  }

  Future<void> _loadExamProviders() async {
    try {
      final response = await _apiService.get('exam-providers');

      if (response['status'] == 'success' && response['data'] != null) {
        final providers = (response['data'] as List)
            .map(
              (p) => {
                'id': p['id']?.toString() ?? p['name']?.toString() ?? '',
                'name': p['name']?.toString() ?? '',
                'price':
                    (p['price'] is String
                        ? double.tryParse(p['price'].toString()) ?? 0
                        : (p['price'] as num).toDouble()) ??
                    0,
                'logo':
                    'assets/images/${p['name']?.toString().toLowerCase()}.png',
              },
            )
            .toList();

        if (mounted) {
          setState(() {
            _examProviders = providers;
            _isLoadingProviders = false;

            // Select first provider
            if (_examProviders.isNotEmpty) {
              _selectedExam = _examProviders[0]['name'];
              _selectedExamId = _examProviders[0]['id'];
              _selectedPrice = _examProviders[0]['price'];
              _updateTotalAmount();
            }
          });
        }
      }
    } catch (e) {
      print('Error loading exam providers: $e');
      if (mounted) {
        setState(() => _isLoadingProviders = false);
      }
    }
  }

  void _updateTotalAmount() {
    final quantity = int.tryParse(_quantityController.text) ?? 0;
    setState(() {
      _totalAmount = _selectedPrice * quantity;
    });
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
    _quantityController.removeListener(_updateTotalAmount);
    _quantityController.dispose();
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
                                  _handlePurchase();
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
                                showNetworkErrorSnackBar(
                                  context,
                                  'Incorrect PIN. Please try again.',
                                );
                                return;
                              }

                              _pinController.text = pinInput;
                              Navigator.pop(context);
                              _handlePurchase();
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

  Future<void> _handlePurchase() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    // Validate inputs
    if (_selectedExam == null || _selectedExam!.isEmpty) {
      if (mounted) {
        setState(() => _isProcessing = false);
        _showErrorDialog('Please select an exam provider');
      }
      return;
    }

    if (_quantityController.text.isEmpty) {
      if (mounted) {
        setState(() => _isProcessing = false);
        _showErrorDialog('Please enter quantity');
      }
      return;
    }

    if (_pinController.text.isEmpty) {
      if (mounted) {
        setState(() => _isProcessing = false);
        _showErrorDialog('Please enter PIN');
      }
      return;
    }

    try {
      // Call real API
      final quantity = int.tryParse(_quantityController.text) ?? 0;
      if (quantity <= 0) {
        throw Exception('Quantity must be greater than 0');
      }

      // Check balance before purchase
      if (_totalAmount > _userBalance) {
        if (mounted) {
          setState(() => _isProcessing = false);
          _showInsufficientBalanceDialog(
            required: _totalAmount,
            available: _userBalance,
          );
        }
        return;
      }

      print(
        'Attempting exam purchase: provider=$_selectedExam, quantity=$quantity, pin=${_pinController.text}',
      );

      final response = await _apiService.purchaseExamPin(
        examId: _selectedExamId ?? _selectedExam!,
        quantity: quantity,
        pin: _pinController.text,
      );

      print('Exam purchase response: $response');
      print(
        'Response data keys: ${response['data']?.keys.toList() ?? "no data"}',
      );
      print('Transaction ID extracted: ${response['data']?['transactionId']}');
      print('Amount extracted: ${response['data']?['amount']}');

      if (mounted) {
        setState(() => _isProcessing = false);

        // Extract transaction details
        final transactionId =
            response['data']?['transactionId'] ??
            response['data']?['transaction_id'] ??
            response['data']?['tId'] ??
            response['reference'] ??
            'N/A';
        final responseAmount = response['data']?['amount'];
        final amount = responseAmount != null
            ? responseAmount.toString()
            : _totalAmount.toStringAsFixed(2);
        final status = response['status'] == 'success' ? 'success' : 'failed';
        final quantity = int.tryParse(_quantityController.text) ?? 1;

        // Clear form
        _quantityController.clear();
        _quantityController.text = '1';
        _pinController.clear();
        setState(() {
          _totalAmount = _selectedPrice * 1;
        });

        // Navigate to transaction details page with complete info
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TransactionDetailsPage(
                transactionId: transactionId.toString(),
                initialStatus: status,
                amount: amount,
                phoneNumber: '',
                network: _selectedExam ?? 'Exam',
                planName: 'Exam Pin - $_selectedExam ($quantity)',
                transactionDate: DateTime.now().toString(),
                planValidity: '',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        final errorMessage = e.toString().replaceFirst('Exception: ', '');
        _showErrorDialog(errorMessage);
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Error',
          style: TextStyle(
            color: Color(0xFFce4323),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          message,
          style: const TextStyle(fontSize: 14, color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'OK',
              style: TextStyle(
                color: Color(0xFFce4323),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showInsufficientBalanceDialog({
    required double required,
    required double available,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Insufficient Balance',
          style: TextStyle(
            color: Color(0xFFce4323),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your wallet balance is insufficient to complete this purchase.',
              style: TextStyle(fontSize: 14, color: Colors.black87),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Required:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.black54,
                        ),
                      ),
                      Text(
                        '₦${required.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFce4323),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Available:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.black54,
                        ),
                      ),
                      Text(
                        '₦${available.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Shortfall:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.black54,
                        ),
                      ),
                      Text(
                        '₦${(required - available).toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Go Back',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Navigate to wallet/fund page
              Navigator.pushNamed(context, '/wallet');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFce4323),
            ),
            child: const Text(
              'Fund Wallet',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFFce4323),
        elevation: 0,
        title: const Text(
          'Exam',
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
                'Select Exam Provider',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              if (_isLoadingProviders)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: CircularProgressIndicator(color: Color(0xFFce4323)),
                  ),
                )
              else
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: _examProviders.map((provider) {
                      final isSelected = _selectedExam == provider['name'];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedExam = provider['name'];
                              _selectedExamId = provider['id'];
                              _selectedPrice = provider['price'] ?? 0;
                            });
                            _updateTotalAmount();
                          },
                          child: Container(
                            width: 100,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFFce4323)
                                    : Colors.grey.shade300,
                                width: isSelected ? 2 : 1.5,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              color: isSelected
                                  ? const Color(0xFFce4323).withOpacity(0.1)
                                  : Colors.white,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 60,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Image.asset(
                                    provider['logo'],
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Center(
                                        child: Text(
                                          provider['name'],
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  provider['name'],
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: isSelected
                                        ? const Color(0xFFce4323)
                                        : Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '₦${provider['price']}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFce4323),
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
              const SizedBox(height: 24),
              const Text(
                'Quantity',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _quantityController,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Quantity',
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
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Amount display field
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey.shade50,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Amount',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey,
                      ),
                    ),
                    Text(
                      '₦${_totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFce4323),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: (_isProcessing || !_hasInternet)
                      ? null
                      : () {
                          if (_selectedExam != null &&
                              _quantityController.text.isNotEmpty) {
                            _showPinSheet();
                          } else {
                            showNetworkErrorSnackBar(
                              context,
                              'Please fill all fields',
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
                      ? const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
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
                          'Purchase',
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
