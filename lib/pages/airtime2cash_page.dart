import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';

import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class Airtime2CashPage extends StatefulWidget {
  const Airtime2CashPage({super.key});

  @override
  State<Airtime2CashPage> createState() => _Airtime2CashPageState();
}

class _Airtime2CashPageState extends State<Airtime2CashPage> {
  final _formKey = GlobalKey<FormState>();

  // Network selection
  String? _selectedNetwork;
  Map<String, dynamic>? _networkSettings;

  // Form controllers
  final _senderPhoneController = TextEditingController();
  final _airtimeAmountController = TextEditingController();

  // UI state
  bool _isLoading = false;
  bool _isLoadingSettings = false;
  String? _error;
  String? _successMessage;

  // Settings data
  Map<String, dynamic> _allSettings = {};

  // Submitted request
  String? _submittedReference;

  // Requests view
  int _selectedTab = 0; // 0: Submit form, 1: View requests
  List<Map<String, dynamic>> _userRequests = [];
  bool _isLoadingRequests = false;

  @override
  void initState() {
    super.initState();
    _loadA2CSettings();
  }

  @override
  void dispose() {
    _senderPhoneController.dispose();
    _airtimeAmountController.dispose();
    super.dispose();
  }

  Future<void> _loadA2CSettings() async {
    setState(() => _isLoadingSettings = true);

    try {
      final api = ApiService();
      final res = await api.get('a2c-settings');
      if (res['status'] == 'success' && res['data'] != null) {
        setState(() {
          _allSettings = Map<String, dynamic>.from(res['data']);
          _error = null;
        });
      } else {
        _showError(res['message'] ?? 'Failed to load settings');
      }
    } catch (e) {
      _showError('Error loading settings: ${e.toString()}');
    } finally {
      setState(() => _isLoadingSettings = false);
    }
  }

  Future<void> _loadUserRequests() async {
    setState(() => _isLoadingRequests = true);

    try {
      final api = ApiService();
      final userId = await api.getUserId();
      if (userId == null) {
        _showError('User not logged in');
        return;
      }

      final res = await api.get('a2c-requests?user_id=$userId');
      if (res['status'] == 'success') {
        setState(() {
          _userRequests = List<Map<String, dynamic>>.from(res['data'] ?? []);
        });
      } else {
        _showError(res['message'] ?? 'Failed to load requests');
      }
    } catch (e) {
      _showError('Error: ${e.toString()}');
    } finally {
      setState(() => _isLoadingRequests = false);
    }
  }

  void _onNetworkSelected(String network) {
    setState(() {
      _selectedNetwork = network;
      _networkSettings = _allSettings[network];
      _error = null;
      _successMessage = null;
      _submittedReference = null;
      // Reset form
      _senderPhoneController.clear();
      _airtimeAmountController.clear();
    });
  }

  double _calculateReceiveAmount(double airtimeAmount) {
    if (_networkSettings == null) return 0;
    double rate = _networkSettings!['rate'] ?? 0.85;
    return airtimeAmount * rate;
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedNetwork == null || _networkSettings == null) {
      _showError('Please select a network');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _successMessage = null;
    });

    try {
      final userId = await ApiService().getUserId();

      if (userId == null) {
        throw Exception('User not logged in');
      }

      double airtimeAmount = double.parse(_airtimeAmountController.text);
      double cashAmount = _calculateReceiveAmount(airtimeAmount);

      final api = ApiService();
      final body = {
        'user_id': userId,
        'network': _selectedNetwork,
        'sender_phone': _senderPhoneController.text,
        'airtime_amount': airtimeAmount,
        'cash_amount': cashAmount,
      };

      try {
        final res = await api.post('a2c-submit', body);
        if (res['status'] == 'success') {
          setState(() {
            _submittedReference = res['data']['reference'];
            _successMessage =
                'Request submitted successfully! Reference: ${res['data']['reference']}';
            _senderPhoneController.clear();
            _airtimeAmountController.clear();
            _selectedNetwork = null;
            _networkSettings = null;
          });

          _showSuccessSnackbar(
            'Request submitted! Reference: ${res['data']['reference']}',
          );
        } else {
          _showError(res['message'] ?? 'Failed to submit request');
        }
      } on Exception catch (e) {
        _showError('Failed to submit request: ${e.toString()}');
      }
    } on TimeoutException {
      _showError('Request timed out. Please try again.');
    } catch (e) {
      _showError('Error: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    setState(() => _error = message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard!'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Color _getNetworkColor(String network) {
    switch (network.toLowerCase()) {
      case 'mtn':
        return Colors.amber;
      case 'airtel':
        return Colors.red;
      case 'glo':
        return Colors.green;
      case '9mobile':
        return Colors.lightGreen;
      default:
        return Colors.grey;
    }
  }

  void _showSupportContactsBottomSheet() {
    if (_networkSettings == null) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Support Contacts',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            // WhatsApp
            ListTile(
              leading: const Icon(Icons.message, color: Colors.green),
              title: const Text('WhatsApp'),
              subtitle: Text(_networkSettings!['whatsapp_number'] ?? 'N/A'),
              onTap: () {
                _copyToClipboard(_networkSettings!['whatsapp_number'] ?? '');
                Navigator.pop(context);
              },
              trailing: const Icon(Icons.copy, size: 16),
            ),
            const SizedBox(height: 12),
            // Phone
            ListTile(
              leading: const Icon(Icons.phone, color: Colors.red),
              title: const Text('Phone'),
              subtitle: Text(_networkSettings!['contact_phone'] ?? 'N/A'),
              onTap: () {
                _copyToClipboard(_networkSettings!['contact_phone'] ?? '');
                Navigator.pop(context);
              },
              trailing: const Icon(Icons.copy, size: 16),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Airtime to Cash'),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        elevation: 0,
        backgroundColor: Colors.red,
      ),
      body: _isLoadingSettings
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Tab buttons
                Container(
                  color: Colors.white,
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedTab = 0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: _selectedTab == 0
                                      ? Colors.red
                                      : Colors.grey.shade300,
                                  width: _selectedTab == 0 ? 3 : 1,
                                ),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                'Submit Request',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: _selectedTab == 0
                                      ? Colors.red
                                      : Colors.grey,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _selectedTab = 1);
                            _loadUserRequests();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: _selectedTab == 1
                                      ? Colors.red
                                      : Colors.grey.shade300,
                                  width: _selectedTab == 1 ? 3 : 1,
                                ),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                'My Requests',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: _selectedTab == 1
                                      ? Colors.red
                                      : Colors.grey,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Content
                Expanded(
                  child: _selectedTab == 0
                      ? _buildSubmitForm()
                      : _buildRequestsTable(),
                ),
              ],
            ),
      floatingActionButton: _networkSettings != null
          ? FloatingActionButton(
              backgroundColor: _getNetworkColor(_selectedNetwork!),
              onPressed: _showSupportContactsBottomSheet,
              child: const Icon(Icons.help_outline, color: Colors.white),
            )
          : null,
    );
  }

  Widget _buildSubmitForm() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'How it works',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '1. Select your network\n'
                      '2. Send the specified airtime amount to the provided phone number\n'
                      '3. Enter your phone number and amount\n'
                      '4. Submit the request\n'
                      '5. Admin will verify and credit your wallet\n',
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Network Selection
            const Text(
              'Select Network',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.5,
              ),
              itemCount: _allSettings.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (context, index) {
                String network = _allSettings.keys.elementAt(index);
                bool isSelected = _selectedNetwork == network;
                Color networkColor = _getNetworkColor(network);

                return GestureDetector(
                  onTap: () => _onNetworkSelected(network),
                  child: Card(
                    elevation: isSelected ? 8 : 2,
                    color: isSelected
                        ? networkColor.withOpacity(0.2)
                        : Colors.white,
                    child: Container(
                      decoration: BoxDecoration(
                        border: isSelected
                            ? Border.all(color: networkColor, width: 2)
                            : null,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            network.toUpperCase(),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isSelected
                                  ? networkColor.withOpacity(0.9)
                                  : Colors.black87,
                            ),
                          ),
                          if (isSelected)
                            Icon(
                              Icons.check_circle,
                              color: networkColor,
                              size: 24,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),

            // Network Details (shown when selected)
            if (_networkSettings != null) ...[
              Card(
                color: _getNetworkColor(_selectedNetwork!).withOpacity(0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Network Details',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _getNetworkColor(_selectedNetwork!),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Send Airtime To:',
                            style: TextStyle(fontSize: 14),
                          ),
                          Text(
                            _networkSettings!['phone_number'] ?? 'N/A',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Exchange Rate:',
                            style: TextStyle(fontSize: 14),
                          ),
                          Text(
                            '1:${_networkSettings!['rate']}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Min Amount:',
                            style: TextStyle(fontSize: 14),
                          ),
                          Text(
                            '₦${_networkSettings!['min_amount']}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Max Amount:',
                            style: TextStyle(fontSize: 14),
                          ),
                          Text(
                            '₦${_networkSettings!['max_amount']}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Form
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Request Details',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Sender Phone
                    TextFormField(
                      controller: _senderPhoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'Your Phone Number',
                        hintText: 'e.g., 08012345678',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        prefixIcon: const Icon(Icons.phone),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your phone number';
                        }
                        String cleanedValue = value.replaceAll(
                          RegExp(r'[^0-9]'),
                          '',
                        );
                        if (cleanedValue.length < 10) {
                          return 'Phone number should be at least 10 digits';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Airtime Amount
                    TextFormField(
                      controller: _airtimeAmountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Airtime Amount (₦)',
                        hintText: 'e.g., 1000',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        prefixIcon: const Icon(Icons.money),
                      ),
                      onChanged: (value) {
                        setState(() {});
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter amount';
                        }
                        if (_networkSettings == null) {
                          return 'Please select a network first';
                        }
                        try {
                          double amount = double.parse(value);
                          double minAmount = double.parse(
                            _networkSettings!['min_amount'].toString(),
                          );
                          double maxAmount = double.parse(
                            _networkSettings!['max_amount'].toString(),
                          );

                          if (amount < minAmount) {
                            return 'Minimum amount is ₦${minAmount.toStringAsFixed(0)}';
                          }
                          if (amount > maxAmount) {
                            return 'Maximum amount is ₦${maxAmount.toStringAsFixed(0)}';
                          }
                          return null;
                        } catch (e) {
                          return 'Please enter a valid number';
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // Calculation display
                    if (_airtimeAmountController.text.isNotEmpty)
                      Card(
                        color: Colors.red.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'You will receive:',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '₦${_calculateReceiveAmount(double.parse(_airtimeAmountController.text)).toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submitRequest,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              )
                            : const Text(
                                'Submit Request',
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
            ],

            // Success Message with Reference
            if (_submittedReference != null)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Card(
                  color: Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: Colors.red.shade700,
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Request Submitted!',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Your request has been submitted and is pending admin approval. You can track it using the reference number below.',
                          style: TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.red.shade300),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Reference:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _submittedReference!,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                              GestureDetector(
                                onTap: () =>
                                    _copyToClipboard(_submittedReference!),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Icon(
                                    Icons.copy,
                                    color: Colors.red,
                                    size: 20,
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
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestsTable() {
    if (_isLoadingRequests) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_userRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No requests yet',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Table(
              columnWidths: const {
                0: FixedColumnWidth(150),
                1: FixedColumnWidth(100),
                2: FixedColumnWidth(100),
                3: FixedColumnWidth(100),
                4: FixedColumnWidth(120),
              },
              border: TableBorder(
                horizontalInside: BorderSide(
                  color: Colors.grey.shade300,
                  width: 1,
                ),
                bottom: BorderSide(color: Colors.grey.shade300, width: 1),
                top: BorderSide(color: Colors.red, width: 2),
              ),
              children: [
                // Header row
                TableRow(
                  decoration: BoxDecoration(color: Colors.red.shade50),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        'Reference',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        'Network',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        'Amount',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        'Receive',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        'Status',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                // Data rows
                ..._userRequests.map((request) {
                  String statusColor = 'grey';
                  if (request['status'] == 'approved') {
                    statusColor = 'green';
                  } else if (request['status'] == 'rejected') {
                    statusColor = 'red';
                  } else if (request['status'] == 'completed') {
                    statusColor = 'blue';
                  }

                  return TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: GestureDetector(
                          onTap: () =>
                              _copyToClipboard(request['reference'] ?? ''),
                          child: Text(
                            request['reference'] ?? 'N/A',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          request['network']?.toUpperCase() ?? 'N/A',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          '₦${request['airtime_amount']}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          '₦${request['cash_amount']}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor == 'green'
                                ? Colors.green.shade100
                                : statusColor == 'red'
                                ? Colors.red.shade100
                                : statusColor == 'blue'
                                ? Colors.blue.shade100
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            request['status']?.toUpperCase() ?? 'PENDING',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: statusColor == 'green'
                                  ? Colors.green
                                  : statusColor == 'red'
                                  ? Colors.red
                                  : statusColor == 'blue'
                                  ? Colors.blue
                                  : Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
