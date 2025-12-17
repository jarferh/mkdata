import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/api_service.dart';
import '../pages/transaction_details_page.dart';
import 'dart:async';
import '../utils/network_utils.dart';

class DatapinPage extends StatefulWidget {
  const DatapinPage({super.key});

  @override
  State<DatapinPage> createState() => _DatapinPageState();
}

class _DatapinPageState extends State<DatapinPage> {
  final _nameController = TextEditingController();
  final _pinController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _amountController = TextEditingController();
  String? _selectedNetwork = ''; // No network selected by default
  String? _selectedPlan;
  bool _isProcessing = false;
  bool _isLoading = true;
  bool _hasInternet = true;
  StreamSubscription? _connectivitySubscription;
  double _userBalance = 0.0;

  final ApiService _apiService = ApiService();
  final LocalAuthentication _localAuth = LocalAuthentication();
  List<Map<String, dynamic>> _dataPinPlans = [];
  bool _isBiometricEnabled = false;
  // network name list is below in `networks`

  final List<String> networks = ['MTN', 'Airtel', 'Glo', '9mobile'];
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
  final Map<String, List<Map<String, dynamic>>> dataPacks = {
    'MTN': [
      {'name': '1GB - 1 Day', 'price': 300},
      {'name': '2GB - 2 Days', 'price': 500},
      {'name': '5GB - 7 Days', 'price': 1500},
      {'name': '10GB - 30 Days', 'price': 3000},
    ],
    'Airtel': [
      {'name': '1.5GB - 1 Day', 'price': 300},
      {'name': '3GB - 3 Days', 'price': 500},
      {'name': '6GB - 7 Days', 'price': 1500},
      {'name': '11GB - 30 Days', 'price': 3000},
    ],
    'Glo': [
      {'name': '1.8GB - 1 Day', 'price': 300},
      {'name': '3.5GB - 2 Days', 'price': 500},
      {'name': '7GB - 7 Days', 'price': 1500},
      {'name': '12GB - 30 Days', 'price': 3000},
    ],
    '9mobile': [
      {'name': '1.3GB - 1 Day', 'price': 300},
      {'name': '2.5GB - 2 Days', 'price': 500},
      {'name': '4.5GB - 7 Days', 'price': 1500},
      {'name': '9.5GB - 30 Days', 'price': 3000},
    ],
  };

  Future<void> _handlePurchase() async {
    // Validate all fields first
    if (_selectedNetwork == null) {
      _showValidationModal('Missing Network', 'Please select a network');
      return;
    }

    if (_selectedPlan == null) {
      _showValidationModal('Missing Plan', 'Please select a plan');
      return;
    }

    if (_quantityController.text.isEmpty ||
        int.tryParse(_quantityController.text) == null) {
      _showValidationModal('Missing Quantity', 'Please enter a valid quantity');
      return;
    }

    if (_nameController.text.isEmpty) {
      _showValidationModal('Missing Card Name', 'Please enter a card name');
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
                                  _processPurchase(pin);
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
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: pinInput.length == 4 && !_isProcessing
                        ? () {
                            Navigator.pop(context);
                            _processPurchase(pinInput);
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFce4323),
                      disabledBackgroundColor: Colors.grey.shade400,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Confirm',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
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
      // Find the selected plan to get the actual planCode
      final selectedPlan = _dataPinPlans.firstWhere((plan) {
        final uniqueValue = '${plan['id']}_${plan['planCode']}';
        return uniqueValue == _selectedPlan;
      }, orElse: () => {});

      if (selectedPlan.isEmpty) {
        if (mounted) showNetworkErrorSnackBar(context, 'Plan not found');
        if (mounted) setState(() => _isProcessing = false);
        return;
      }

      final planCode = selectedPlan['planCode']?.toString() ?? '';

      final response = await _apiService.purchaseDataPin(
        planId: planCode,
        quantity: int.parse(_quantityController.text),
        nameOnCard: _nameController.text,
        pin: pin,
      );

      if (!mounted) return;

      final transactionId = response['data']?['reference'] ?? '';
      final amount = _amountController.text;
      final networkName = _selectedNetwork ?? '';
      final planName = selectedPlan['name'] ?? '';
      final validity = selectedPlan['validity']?.toString() ?? '';
      final status = response['status'] ?? 'failed';

      _nameController.clear();
      _quantityController.text = '1';
      setState(() {
        _selectedPlan = null;
        _selectedNetwork = null;
      });

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TransactionDetailsPage(
            transactionId: transactionId,
            amount: amount,
            phoneNumber: _nameController.text,
            network: networkName,
            initialStatus: status,
            planName: 'Data Pin - $planName',
            transactionDate: DateTime.now().toString(),
            planValidity: validity,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showNetworkErrorSnackBar(context, e);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Widget _buildPinButton(
    String text,
    VoidCallback onPressed, {
    bool isBiometric = false,
  }) {
    if (isBiometric) {
      return GestureDetector(
        onTap: onPressed,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: const Icon(
            Icons.fingerprint,
            color: Color(0xFFce4323),
            size: 24,
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onPressed,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.grey.shade200,
        ),
        child: Center(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ),
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
                          color: Color(0xFFce4323),
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
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/wallet');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFce4323),
            ),
            child: const Text(
              'Fund Wallet',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
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
      print('Error loading biometric settings: $e');
    }
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

  Future<String?> _authenticateAndGetPin() async {
    try {
      bool canCheckBiometrics = await _localAuth.canCheckBiometrics;
      bool hasHardware = await _localAuth.isDeviceSupported();

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

  @override
  void initState() {
    super.initState();
    _quantityController.addListener(_updateAmount);
    _fetchNetworkStatuses();
    _checkBiometricSettings();
    _initConnectivity();
    _loadUserBalance();
    // Load all plans initially
    _loadDataPinPlans();
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

  Future<void> _loadDataPinPlans([String? network]) async {
    // Ensure internet before fetching plans
    if (!await _checkInternetConnection()) {
      setState(() {
        _isLoading = false;
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _selectedPlan = null; // Reset selected plan when loading new plans
    });

    try {
      final response = await _apiService.getDataPinPlans(network: network);
      print('📡 Data PIN Plans Response: $response');

      if (response['status'] == 'success') {
        final plans = List<Map<String, dynamic>>.from(response['data'] ?? []);
        print(
          '✅ Loaded ${plans.length} plans for network: ${network ?? "all"}',
        );
        print(
          'Plan details: ${plans.map((p) => '${p['name']} (networkId: ${p['networkId']})').toList()}',
        );

        setState(() {
          _dataPinPlans = plans;
          _isLoading = false;
        });
      } else {
        print('❌ API Error: ${response['message']}');
        setState(() {
          _isLoading = false;
        });
        if (mounted) {
          showNetworkErrorSnackBar(
            context,
            response['message'] ?? 'Failed to load data pin plans',
          );
        }
      }
    } catch (e) {
      print('❌ Exception: $e');
      setState(() {
        _isLoading = false;
      });
      // Show friendly message for network-related errors
      if (mounted) showNetworkErrorSnackBar(context, e);
    }
  }

  void _updateAmount() {
    if (_selectedPlan == null) return;

    final selectedPlanData = _dataPinPlans.firstWhere((plan) {
      // Parse the unique value format: "id_planCode"
      final uniqueValue = '${plan['id']}_${plan['planCode']}';
      return uniqueValue == _selectedPlan;
    }, orElse: () => {});

    if (selectedPlanData.isEmpty) return;

    int quantity = int.tryParse(_quantityController.text) ?? 1;
    double baseAmount = double.parse(
      selectedPlanData['price']?.toString() ?? '0',
    );
    _amountController.text = (baseAmount * quantity).toStringAsFixed(2);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFFce4323),
        elevation: 0,
        title: const Text(
          'Data Card',
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
                  child: _isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Loading plans...'),
                              SizedBox(width: 8),
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ],
                          ),
                        )
                      : DropdownButton<String?>(
                          value: _selectedPlan,
                          isExpanded: true,
                          underline: const SizedBox(),
                          hint: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text('Select Plan'),
                          ),
                          items: _dataPinPlans.isEmpty
                              ? [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child: Text('No plans available'),
                                    ),
                                  ),
                                ]
                              : _dataPinPlans.asMap().entries.map<
                                  DropdownMenuItem<String?>
                                >((entry) {
                                  final plan = entry.value;
                                  // Use a unique combination to avoid duplicates
                                  final uniqueValue =
                                      '${plan['id']}_${plan['planCode']}'
                                          .toString();
                                  return DropdownMenuItem<String?>(
                                    value: uniqueValue,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child: Text(
                                        '${plan['name'] ?? 'Unknown'} - ₦${plan['price'] ?? 0}',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ),
                                  );
                                }).toList(),
                          onChanged: (String? newValue) {
                            setState(() {
                              _selectedPlan = newValue;
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
        children: networks.map((network) {
          final networkInfo = networkData.firstWhere(
            (n) => n['name'] == network,
            orElse: () => {'name': network, 'logo': '', 'color': Colors.grey},
          );
          final isSelected = _selectedNetwork == network;
          final isEnabled = _isNetworkEnabled(network);

          return Expanded(
            child: GestureDetector(
              onTap: isEnabled
                  ? () async {
                      setState(() {
                        _selectedNetwork = network;
                        _isLoading = true;
                      });
                      await _loadDataPinPlans(network);
                    }
                  : null,
              child: Opacity(
                opacity: isEnabled ? 1.0 : 0.4,
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
                            network,
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
            ),
          );
        }).toList(),
      ),
    );
  }
}
