import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class ChangeTransactionPinPage extends StatefulWidget {
  const ChangeTransactionPinPage({super.key});

  @override
  State<ChangeTransactionPinPage> createState() =>
      _ChangeTransactionPinPageState();
}

class _ChangeTransactionPinPageState extends State<ChangeTransactionPinPage> {
  String _enteredPin = '';
  bool _isLoading = false;
  String _errorMessage = '';

  void _appendDigit(String d) {
    if (_enteredPin.length >= 4) return;
    setState(() {
      _enteredPin += d;
    });
  }

  void _deleteDigit() {
    if (_enteredPin.isEmpty) return;
    setState(() {
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
    });
  }

  Future<void> _submitPin() async {
    if (_enteredPin.length != 4) {
      setState(() => _errorMessage = 'Please enter a 4-digit PIN');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      String? userId = prefs.getString('user_id');

      if (userId == null) {
        await prefs.setString('login_pin', _enteredPin);
        if (mounted) Navigator.of(context).pop(true);
        return;
      }

      final api = ApiService();
      final res = await api.post('update-pin', {
        'user_id': userId,
        'pin': _enteredPin,
      });

      if (res['status'] == 'success') {
        await prefs.setString('login_pin', _enteredPin);
        if (mounted) Navigator.of(context).pop(true);
        return;
      } else {
        setState(
          () => _errorMessage = res['message'] ?? 'Failed to update PIN',
        );
      }
    } catch (e) {
      setState(() => _errorMessage = 'Failed to update PIN: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildNumButton(String label, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: const Text(
          'Change Transaction PIN',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFce4323), Color(0xFFce4323)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 8),
                  const Icon(Icons.lock_outline, color: Colors.white, size: 54),
                  const SizedBox(height: 16),
                  const Text(
                    'Enter new transaction PIN',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: 220,
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(4, (index) {
                        final val = index < _enteredPin.length ? '●' : '';
                        return Container(
                          width: 40,
                          alignment: Alignment.center,
                          child: Text(
                            val,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Container(
              color: Colors.white,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      children: [
                        Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          alignment: WrapAlignment.center,
                          children: [
                            for (var i = 1; i <= 9; i++)
                              _buildNumButton(
                                i.toString(),
                                onTap: () => _appendDigit(i.toString()),
                              ),
                            _buildNumButton('✓', onTap: _submitPin),
                            _buildNumButton(
                              '0',
                              onTap: () => _appendDigit('0'),
                            ),
                            _buildNumButton('⌫', onTap: _deleteDigit),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_errorMessage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        _errorMessage,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
