import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class PinSetupPage extends StatefulWidget {
  const PinSetupPage({super.key});

  @override
  State<PinSetupPage> createState() => _PinSetupPageState();
}

class _PinSetupPageState extends State<PinSetupPage> {
  final List<TextEditingController> _pinControllers = List.generate(
    4,
    (index) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(4, (index) => FocusNode());
  String _errorMessage = '';
  bool _isLoading = false;

  @override
  void dispose() {
    for (var controller in _pinControllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  String get _enteredPin => _pinControllers.map((e) => e.text).join();

  void _handlePinComplete() async {
    if (_enteredPin.length != 4) {
      setState(() {
        _errorMessage = 'Please enter a 4-digit PIN';
      });
      return;
    }
    // Attempt to update PIN on backend first (best-effort). If the backend
    // update fails we'll show an error and avoid saving locally to keep client
    // and server in sync.
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();

    try {
      final api = ApiService();
      // Determine user id from session
      String? userId = await ApiService().getUserId();

      final res = await api.post('update-pin', {
        'user_id': userId,
        'pin': _enteredPin,
      });

      if (res['status'] == 'success') {
        await prefs.setString('login_pin', _enteredPin);
        if (mounted) Navigator.of(context).pushReplacementNamed('/dashboard');
        return;
      } else {
        setState(() {
          _errorMessage = res['message'] ?? 'Failed to update PIN on server';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to update PIN: ${e.toString()}';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Create New PIN',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              children: [
                const SizedBox(height: 60),
                // Icon section
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFce4323),
                      width: 3,
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.lock_outline,
                      size: 50,
                      color: Color(0xFFce4323),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                const Text(
                  'Create New PIN',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Enter a 4-digit PIN for your account',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                // PIN input fields
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    4,
                    (index) => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: 60,
                      height: 60,
                      child: TextField(
                        controller: _pinControllers[index],
                        focusNode: _focusNodes[index],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        obscureText: true,
                        obscuringCharacter: '●',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
                          counterText: '',
                          contentPadding: EdgeInsets.zero,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.grey.shade300,
                              width: 2,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.grey.shade300,
                              width: 2,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFFce4323),
                              width: 2,
                            ),
                          ),
                          filled: true,
                          fillColor: _pinControllers[index].text.isNotEmpty
                              ? Colors.grey.shade100
                              : Colors.white,
                        ),
                        maxLength: 1,
                        onChanged: (value) {
                          setState(() {});
                          if (value.isNotEmpty) {
                            if (index < 3) {
                              _focusNodes[index + 1].requestFocus();
                            } else {
                              FocusScope.of(context).unfocus();
                              SystemChannels.textInput.invokeMethod(
                                'TextInput.hide',
                              );
                            }
                          }
                        },
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                  ),
                ),
                if (_errorMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      _errorMessage,
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                const SizedBox(height: 60),
                // Create button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: (_enteredPin.length == 4 && !_isLoading)
                          ? _handlePinComplete
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFce4323),
                        disabledBackgroundColor: Colors.grey.shade300,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isLoading
                          ? const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Creating...',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(width: 12),
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            )
                          : const Text(
                              'Create PIN',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
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
}
