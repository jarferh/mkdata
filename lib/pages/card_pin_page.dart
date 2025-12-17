import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import '../utils/network_utils.dart';
import '../services/api_service.dart';
import './transaction_details_page.dart';

class CardPinPage extends StatefulWidget {
  const CardPinPage({super.key});

  @override
  State<CardPinPage> createState() => _CardPinPageState();
}

class _CardPinPageState extends State<CardPinPage> {
  // Connectivity state
  bool _hasInternet = true;
  StreamSubscription? _connectivitySubscription;
  final _nameController = TextEditingController();
  final _pinController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _amountController = TextEditingController(text: '1000.00');
  String _selectedCard = ''; // No card selected by default
  bool _isProcessing = false;
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _isBiometricEnabled = false;
  final ApiService _apiService = ApiService();
  double _userBalance = 0.0;

  final List<Map<String, dynamic>> cardTypes = [
    {'name': 'MTN', 'price': 1000},
    {'name': 'Airtel', 'price': 1000},
    {'name': 'Glo', 'price': 1000},
    {'name': '9mobile', 'price': 1000},
  ];

  final List<Map<String, dynamic>> networkData = [
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
  void initState() {
    super.initState();
    _quantityController.addListener(_updateAmount);
    _loadBiometricSettings();
    _loadUserBalance();
    _initConnectivity();
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
        showNetworkErrorSnackBar(
          context,
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

  Future<void> _initConnectivity() async {
    _hasInternet = await _checkInternetConnection();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      _,
    ) async {
      final ok = await _verifyInternetAccess();
      if (mounted) setState(() => _hasInternet = ok);
    });
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _nameController.dispose();
    _pinController.dispose();
    _quantityController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<bool> _checkInternetConnection() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        _showNoInternetSnackbar();
        setState(() => _hasInternet = false);
        return false;
      }
      final ok = await _verifyInternetAccess();
      setState(() => _hasInternet = ok);
      return ok;
    } catch (e) {
      _showNoInternetSnackbar();
      setState(() => _hasInternet = false);
      return false;
    }
  }

  Future<bool> _verifyInternetAccess() async {
    try {
      final uri = Uri.parse('https://www.google.com/generate_204');
      final response = await http.get(uri).timeout(const Duration(seconds: 3));
      return response.statusCode == 204 || response.statusCode == 200;
    } catch (_) {
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

  void _updateAmount() {
    int quantity = int.tryParse(_quantityController.text) ?? 1;
    double baseAmount = 1000.00;
    _amountController.text = (baseAmount * quantity).toStringAsFixed(2);
  }

  // Modified to perform connectivity pre-check and return early when offline
  Future<void> _handlePurchase() async {
    // Validate all fields first
    if (_nameController.text.isEmpty) {
      _showValidationModal('Missing Card Name', 'Please enter a card name');
      return;
    }

    if (_quantityController.text.isEmpty ||
        int.tryParse(_quantityController.text) == null) {
      _showValidationModal('Missing Quantity', 'Please enter a valid quantity');
      return;
    }

    // Check balance before showing PIN sheet
    final amount = double.tryParse(_amountController.text) ?? 0.0;
    if (amount > _userBalance) {
      _showInsufficientBalanceDialog(required: amount, available: _userBalance);
      return;
    }

    // Show PIN sheet
    _showPinSheet();
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
                                  _processPurchase(pinInput);
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
                              _processPurchase(pinInput);
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

  Future<void> _processPurchase(String pin) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final quantity = int.tryParse(_quantityController.text) ?? 1;
      final amount = double.tryParse(_amountController.text) ?? 0.0;

      print(
        'Attempting card pin purchase: card=$_selectedCard, quantity=$quantity, amount=$amount',
      );

      // Call real API
      final response = await _apiService.purchaseCardPin(
        planId: _selectedCard,
        quantity: quantity,
        pin: pin,
      );

      print('Card pin purchase response: $response');

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
        final responseAmount2 = responseAmount != null
            ? responseAmount.toString()
            : amount.toStringAsFixed(2);
        final status = response['status'] == 'success' ? 'success' : 'failed';

        // Clear form
        _nameController.clear();
        _quantityController.text = '1';
        _amountController.text = '1000.00';

        // Navigate to transaction details page
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TransactionDetailsPage(
                transactionId: transactionId.toString(),
                initialStatus: status,
                amount: responseAmount2,
                phoneNumber: '',
                network: _selectedCard,
                planName: 'Card Pin - $_selectedCard ($quantity)',
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
        showNetworkErrorSnackBar(context, errorMessage);
      }
    }
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

  void _showValidationModal(String title, String message) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFFce4323),
        elevation: 0,
        title: const Text(
          'Recharge Card',
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
            onPressed: () => Navigator.pushNamed(context, '/transactions'),
            child: const Text(
              'History',
              style: TextStyle(color: Colors.white, fontSize: 14),
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
              // Network Selection at top
              _buildNetworkDropdown(),
              const SizedBox(height: 32),

              // Plan Selection
              _buildFormField(
                label: 'Plan',
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300, width: 1.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButton<String>(
                    value: _selectedCard.isEmpty ? null : _selectedCard,
                    isExpanded: true,
                    underline: const SizedBox(),
                    hint: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('Select Plan'),
                    ),
                    items: cardTypes.map<DropdownMenuItem<String>>((card) {
                      return DropdownMenuItem<String>(
                        value: card['name'] as String,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            '${card['name']} - ₦${card['price']}',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedCard = newValue ?? 'MTN';
                        _updateAmount();
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Quantity
              _buildFormField(
                label: 'Quantity',
                child: TextField(
                  keyboardType: TextInputType.number,
                  controller: _quantityController,
                  onChanged: (value) => _updateAmount(),
                  decoration: InputDecoration(
                    hintText: 'Quantity',
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade400,
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
                ),
              ),
              const SizedBox(height: 24),

              // Card Name
              _buildFormField(
                label: 'Card Name',
                child: TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    hintText: 'Enter card name',
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade400,
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
                ),
              ),
              const SizedBox(height: 32),

              // Purchase Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: (_isProcessing || !_hasInternet)
                      ? null
                      : _handlePurchase,
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
                            color: Colors.white,
                            fontSize: 16,
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

  Widget _buildFormField({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _buildNetworkDropdown() {
    return _buildFormField(
      label: 'Network',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: cardTypes.map((card) {
          final networkInfo = networkData.firstWhere(
            (n) => n['name'] == card['name'],
            orElse: () => {
              'name': card['name'],
              'logo': '',
              'color': Colors.grey,
            },
          );
          final isSelected = _selectedCard == card['name'];

          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedCard = card['name'] as String;
                  _updateAmount();
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? networkInfo['color']
                          : Colors.grey.shade300,
                      width: isSelected ? 3 : 2,
                    ),
                    color: isSelected
                        ? (networkInfo['color'] as Color).withOpacity(0.05)
                        : Colors.transparent,
                  ),
                  child: Center(
                    child: Image.asset(
                      networkInfo['logo'],
                      width: 40,
                      height: 40,
                      errorBuilder: (context, error, stackTrace) {
                        return Text(
                          card['name'],
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
