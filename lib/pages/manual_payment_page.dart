import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'manual_requests_page.dart';
import '../services/api_service.dart';
import '../utils/network_utils.dart';

class ManualPaymentPage extends StatefulWidget {
  const ManualPaymentPage({super.key});

  @override
  State<ManualPaymentPage> createState() => _ManualPaymentPageState();
}

class _ManualPaymentPageState extends State<ManualPaymentPage> {
  final _amountController = TextEditingController(text: '0');
  final _bankNameController = TextEditingController();
  final _senderNameController = TextEditingController();
  bool _sending = false;
  String? _accountNumber;
  String? _bankName;
  String? _accountName;
  bool _loadingAccount = true;

  @override
  void dispose() {
    _amountController.dispose();
    _bankNameController.dispose();
    _senderNameController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadAccountDetails();
  }

  Future<void> _loadAccountDetails() async {
    setState(() => _loadingAccount = true);
    try {
      final api = ApiService();
      final row = await api.getActiveManualPayment();

      if (row != null) {
        setState(() {
          _accountNumber = (row['account_number'] ?? '').toString();
          _accountName = (row['account_name'] ?? '').toString();
          _bankName = (row['bank_name'] ?? '').toString();
        });
      } else {
        setState(() {
          _accountNumber = '';
          _accountName = '';
          _bankName = '';
        });
      }
    } catch (e) {
      setState(() {
        _accountNumber = '';
        _accountName = '';
        _bankName = '';
      });
    } finally {
      if (mounted) setState(() => _loadingAccount = false);
    }
  }

  void _copyAccountNumber() {
    final toCopy = _accountNumber ?? '';
    if (toCopy.isEmpty) return;
    Clipboard.setData(ClipboardData(text: toCopy));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Account number copied')));
  }

  Future<void> _submitProof() async {
    final amount =
        double.tryParse(_amountController.text.replaceAll(',', '')) ?? 0.0;
    final sendBank = _bankNameController.text.trim();
    final sender = _senderNameController.text.trim();

    if (amount <= 0 || sendBank.isEmpty || sender.isEmpty) {
      showNetworkErrorSnackBar(
        context,
        'Please fill all fields with valid values',
      );
      return;
    }

    setState(() => _sending = true);
    try {
      final api = ApiService();
      // include subscriber id (sId) from session
      final userId = await ApiService().getUserId() ?? '';
      final body = {
        'amount': amount,
        'bank': sendBank,
        'sender': sender,
        'account_number': _accountNumber ?? '',
        // send the sender's name as account_name so it is recorded as the account
        'account_name': sender,
        // send the provided bank name as bank_name so backend will use it for the method field
        'bank_name': sendBank,
        'sId': userId,
      };

      final res = await api.post('send-manual-proof', body);

      if (res['status'] == 'success') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Payment details submitted. We will verify and credit your wallet shortly.',
              ),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message'] ?? 'Failed to submit proof')),
          );
        }
      }
    } catch (e) {
      if (mounted) showNetworkErrorSnackBar(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use a slightly darker primary color (keeps the same hue but improves contrast)
    final primaryColor = const Color(0xFF36474F);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Pay Manually',
          style: TextStyle(color: Colors.black),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: Colors.black),
            tooltip: 'View manual requests',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ManualRequestsPage()),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Account card
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color.fromARGB(255, 124, 124, 124),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Send manually into',
                        style: TextStyle(color: Colors.black87),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Account Number',
                                  style: TextStyle(
                                    color: Colors.black54,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _loadingAccount
                                          ? const SizedBox(
                                              height: 24,
                                              child: Center(
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      'Loading account...',
                                                      style: TextStyle(
                                                        color: Color(
                                                          0xFF36474F,
                                                        ),
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                    SizedBox(width: 8),
                                                    SizedBox(
                                                      width: 18,
                                                      height: 18,
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            color: Color(
                                                              0xFF36474F,
                                                            ),
                                                          ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            )
                                          : Text(
                                              _accountNumber == null ||
                                                      _accountNumber!.isEmpty
                                                  ? '—'
                                                  : _accountNumber!,
                                              style: const TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.copy,
                                        color: primaryColor,
                                      ),
                                      onPressed:
                                          (_accountNumber == null ||
                                              _accountNumber!.isEmpty)
                                          ? null
                                          : _copyAccountNumber,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Bank',
                                    style: TextStyle(
                                      color: Colors.black54,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    (_bankName == null || _bankName!.isEmpty)
                                        ? '—'
                                        : _bankName!,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Account Name',
                                    style: TextStyle(
                                      color: Colors.black54,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    (_accountName == null ||
                                            _accountName!.isEmpty)
                                        ? '—'
                                        : _accountName!,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Send payment details here!',
                        style: TextStyle(color: Colors.black87),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                const Text(
                  'Sent Amount',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFFF2F2F2),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    hintText: '0',
                    hintStyle: const TextStyle(color: Colors.black45),
                    prefixText: '₦',
                  ),
                ),

                const SizedBox(height: 16),
                const Text(
                  'Send Bank Name',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _bankNameController,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFFF2F2F2),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    hintText: 'Bank Name eg Access, UBA, Opay etc',
                    hintStyle: const TextStyle(color: Colors.black45),
                  ),
                ),

                const SizedBox(height: 16),
                const Text(
                  'Sender\'s Name',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _senderNameController,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFFF2F2F2),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    hintText: 'Sender\'s Full Name',
                    hintStyle: const TextStyle(color: Colors.black45),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'This name must be the same as the receive bank alert.',
                  style: TextStyle(color: Colors.black54, fontSize: 12),
                ),

                const SizedBox(height: 20),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _sending ? null : _submitProof,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _sending
                        ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Sending...',
                                style: TextStyle(color: Colors.white),
                              ),
                              SizedBox(width: 12),
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
                            'Send Proof',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),

          // Full-page loading overlay while fetching account details
          if (_loadingAccount)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.25),
                child: const Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Loading payment details...',
                        style: TextStyle(color: Colors.white),
                      ),
                      SizedBox(width: 12),
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Color(0xFF36474F),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
