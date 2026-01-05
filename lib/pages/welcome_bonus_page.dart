import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class WelcomeBonusPage extends StatefulWidget {
  const WelcomeBonusPage({super.key});

  @override
  State<WelcomeBonusPage> createState() => _WelcomeBonusPageState();
}

class _WelcomeBonusPageState extends State<WelcomeBonusPage> {
  bool _isLoading = true;
  bool _hasClaimed = false;
  double _bonusAmount = 0.0;
  String _errorMessage = '';
  bool _isClaimingBonus = false;

  @override
  void initState() {
    super.initState();
    _loadWelcomeBonusInfo();
  }

  Future<void> _loadWelcomeBonusInfo() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      final userId = await ApiService().getUserId();

      if (userId == null) {
        setState(() {
          _errorMessage = 'User not found. Please login again.';
          _isLoading = false;
        });
        return;
      }

      // Fetch welcome bonus settings
      final settingsResp = await ApiService().get('welcome-bonus-settings');
      if (settingsResp['status'] == 'success') {
        final data = settingsResp['data'];
        setState(() => _bonusAmount = double.parse(data['amount'].toString()));
      }

      // Fetch user's bonus status
      final statusResp = await ApiService().get(
        'welcome-bonus-status?user_id=$userId',
      );
      if (statusResp['status'] == 'success') {
        final data = statusResp['data'];
        setState(() {
          _hasClaimed = data['has_claimed'] ?? false;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage =
              statusResp['message'] ?? 'Failed to load bonus status';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _claimBonus() async {
    try {
      setState(() {
        _isClaimingBonus = true;
        _errorMessage = '';
      });

      final userId = await ApiService().getUserId();

      if (userId == null) {
        setState(() {
          _errorMessage = 'User not found. Please login again.';
          _isClaimingBonus = false;
        });
        return;
      }

      final resp = await ApiService().post('claim-welcome-bonus', {
        'user_id': userId,
      });
      print('Claim response: $resp');
      if (resp['status'] == 'success') {
        setState(() {
          _hasClaimed = true;
          _isClaimingBonus = false;
        });

        _showSuccessDialog(
          'Bonus Claimed!',
          'You have successfully claimed ₦${_bonusAmount.toStringAsFixed(2)}. This has been added to your wallet.',
        );

        await Future.delayed(const Duration(milliseconds: 500));
        await _reloadUserData();
      } else {
        setState(() {
          _errorMessage = resp['message'] ?? 'Failed to claim bonus';
          _isClaimingBonus = false;
        });
      }
    } catch (e) {
      print('Claim error: $e');
      setState(() {
        _errorMessage = 'Error: ${e.toString()}';
        _isClaimingBonus = false;
      });
    }
  }

  Future<void> _reloadUserData() async {
    try {
      final userId = await ApiService().getUserId();

      if (userId != null) {
        final response = await ApiService().get('account-details?id=$userId');
        if (response['status'] == 'success') {
          final userData = response['data'];
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_data', jsonEncode(userData));
          if (userData['sWallet'] != null) {
            print('Updated wallet balance: ${userData['sWallet']}');
          }
        }
      }
    } catch (e) {
      print('Error reloading user data: $e');
      // Silent fail for user data reload
    }
  }

  void _showSuccessDialog(String title, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check,
                  color: Colors.green.shade700,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            message,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black54,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.shade600,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Done',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: const Color(0xFFce4323),
          flexibleSpace: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFf05533),
                  Color(0xFFce4323),
                  Color(0xFF9d2e1a),
                  Color(0xFF6b1f0f),
                ],
                stops: [0.0, 0.3, 0.6, 1.0],
              ),
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text(
            'Welcome Bonus',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFce4323)),
              )
            : RefreshIndicator(
                onRefresh: _loadWelcomeBonusInfo,
                color: Color(0xFFce4323),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Error Message
                      if (_errorMessage.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            border: Border.all(color: Colors.red.shade300),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: Colors.red.shade700,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _errorMessage,
                                  style: TextStyle(
                                    color: Colors.red.shade700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Main Bonus Card
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFFf05533),
                              Color(0xFFce4323),
                              Color(0xFF9d2e1a),
                              Color(0xFF6b1f0f),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            stops: [0.0, 0.3, 0.6, 1.0],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFFce4323,
                              ).withValues(alpha: 0.3),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Icon(
                              Icons.card_giftcard,
                              color: Colors.white,
                              size: 48,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Exclusive Welcome Gift',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '₦${_bonusAmount.toStringAsFixed(2)}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 42,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Welcome Bonus Credit',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Status Card
                      Container(
                        decoration: BoxDecoration(
                          color: _hasClaimed
                              ? Colors.orange.shade50
                              : Colors.orange.shade50,
                          border: Border.all(
                            color: _hasClaimed
                                ? Colors.orange.shade300
                                : Colors.orange.shade300,
                          ),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: _hasClaimed
                                    ? Colors.green.shade100
                                    : Colors.amber.shade100,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _hasClaimed
                                    ? Icons.check_circle
                                    : Icons.info_outline,
                                color: _hasClaimed
                                    ? Colors.green.shade700
                                    : Colors.amber.shade700,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _hasClaimed
                                        ? 'Bonus Claimed'
                                        : 'Bonus Available',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: _hasClaimed
                                          ? Colors.green.shade700
                                          : Colors.amber.shade700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _hasClaimed
                                        ? 'Your bonus has been added to your wallet'
                                        : 'Claim your bonus to get started',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _hasClaimed
                                          ? Colors.green.shade600
                                          : Colors.amber.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Information Section
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'How to use your bonus:',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildInfoItem(
                              '1',
                              'Claim your bonus',
                              'Click the claim button below to add ₦${_bonusAmount.toStringAsFixed(2)} to your wallet',
                            ),
                            const SizedBox(height: 12),
                            _buildInfoItem(
                              '2',
                              'Use on any service',
                              'Use your bonus balance to buy airtime, data, cable TV, electricity, and more',
                            ),
                            const SizedBox(height: 12),
                            _buildInfoItem(
                              '3',
                              'No expiration',
                              'Your bonus never expires and can be used anytime',
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Claim Button
                      if (!_hasClaimed)
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _isClaimingBonus ? null : _claimBonus,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFce4323),
                              disabledBackgroundColor: Colors.grey.shade400,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 4,
                            ),
                            child: _isClaimingBonus
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    'Claim ₦${_bonusAmount.toStringAsFixed(2)} Now',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        )
                      else
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFce4323),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 4,
                            ),
                            child: const Text(
                              'Back to Dashboard',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),

                      const SizedBox(height: 24),

                      // Terms
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          '📌 Terms & Conditions: Welcome bonus is a one-time offer. It will be automatically added to your wallet upon claim. The bonus can be used on any transaction and never expires.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                            height: 1.4,
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

  Widget _buildInfoItem(String number, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Color(0xFFce4323),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            number,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
