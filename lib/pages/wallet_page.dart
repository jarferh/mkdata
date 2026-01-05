import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
// import 'manual_payment_page.dart';
// manual payment UI still exists as a page but the quick action is removed from Wallet

Future<void> _sendAccountGenerationNotification(
  String userId,
  String accountType,
) async {
  try {
    final api = ApiService();
    final resp = await api.post('send-notification', {
      'user_id': userId,
      'type': 'account_generated',
      'title': '💰 Virtual Account Generated',
      'account_type': accountType,
    });

    if (resp['status'] != 'success') {
      print(
        'Error sending account generation notification: ${resp['message'] ?? resp}',
      );
    }
  } catch (e) {
    print('Error sending account generation notification: $e');
    // Don't throw - notification failure shouldn't block the main flow
  }
}

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? userData;
  bool isLoading = true;
  bool _isGenerating = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    // Two tabs: Srobank (single) and Wema & Sterling (merged)
    _tabController = TabController(length: 2, vsync: this);
    // Rebuild when tab changes so the TabBarView height adapts
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    loadUserData();
  }

  // Responsive helpers
  double getResponsiveSize(BuildContext context, double baseSize) {
    double screenWidth = MediaQuery.of(context).size.width;
    double scaleFactor = screenWidth / 375; // Base width
    return baseSize * scaleFactor.clamp(0.7, 1.3);
  }

  EdgeInsets getResponsivePadding(BuildContext context, double basePadding) {
    double scaleFactor = MediaQuery.of(context).size.width / 375;
    double responsivePadding = basePadding * scaleFactor.clamp(0.8, 1.2);
    return EdgeInsets.all(responsivePadding);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataStr = prefs.getString('user_data');
      print('Loading user data from SharedPreferences: $userDataStr');

      Map<String, dynamic> formattedData;

      if (userDataStr != null) {
        final parsedData = json.decode(userDataStr);
        // Convert legacy format to new format if needed
        if (parsedData.containsKey('message') && parsedData.containsKey('id')) {
          // Convert legacy format to new format
          formattedData = {
            'sId': parsedData['id'],
            'sFname': parsedData['fullname']?.toString().split(' ')[0] ?? '',
            'sLname':
                parsedData['fullname']
                    ?.toString()
                    .split(' ')
                    .skip(1)
                    .join(' ') ??
                '',
            'sEmail': parsedData['email'],
            'sPhone': parsedData['phone'],
            'sWallet': parsedData['wallet'] ?? 0,
            'sRefWallet': parsedData['refWallet'] ?? 0,
            'sBankNo': parsedData['bankNo'],
            'sSterlingBank': parsedData['sterlingBank'],
            'sBankName': parsedData['bankName'],
            'sRolexBank': parsedData['rolexBank'],
            'sFidelityBank': parsedData['fidelityBank'],
            'sAsfiyBank': parsedData['asfiyBank'],
            's9PSBBank': parsedData['9psbBank'],
            'sPayvesselBank': parsedData['payvesselBank'],
            'sPagaBank': parsedData['pagaBank'],
            'sPalmpayBank': parsedData['palmpayBank'],
            'sAccountLimit': parsedData['accountLimit'] ?? '5000',
          };
        } else {
          formattedData = parsedData;
        }
      } else {
        // Fetch data from API if not found in SharedPreferences
        print('Fetching user data from API...');
        try {
          final userId = await ApiService().getUserId();
          if (userId == null) {
            throw Exception('User ID not found');
          }

          final api = ApiService();
          final resp = await api.get('account-details?id=$userId');
          print('API Response: $resp');

          if (resp['status'] == 'success') {
            formattedData = resp['data'];
            // Save the fetched data to SharedPreferences
            await prefs.setString('user_data', json.encode(formattedData));
            print('Data saved to SharedPreferences');
          } else {
            final msg = resp['message'] ?? 'Failed to fetch account details';
            throw Exception(msg);
          }
        } catch (e) {
          print('Error fetching user data from API: $e');
          rethrow;
        }
      }

      setState(() {
        userData = formattedData;
        isLoading = false;
      });
      print('Bank details loaded:');
      print('Wema Bank: ${formattedData['sBankNo']}');
      print('Sterling Bank: ${formattedData['sSterlingBank']}');
      print('Bank Name: ${formattedData['sBankName']}');
    } catch (e) {
      print('Error loading user data: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _generateAccounts({String type = 'both'}) async {
    try {
      setState(() {
        _isGenerating = true;
      });

      String? userId = await ApiService().getUserId();
      if (userId == null && userData != null && userData!['sId'] != null) {
        userId = userData!['sId'].toString();
      }

      // Determine which endpoint to call
      String endpoint = 'generate-palmpay-paga';
      if (type == 'paga') {
        endpoint = 'generate-paga-only';
      } else if (type == 'palmpay') {
        endpoint = 'generate-palmpay-only';
      }

      final api = ApiService();
      final data = await api.post(endpoint, {'user_id': userId});
      if (data['status'] == 'success') {
        final pagaAcct = data['data']?['paga_account'] ?? '';
        final palmpayAcct = data['data']?['palmpay_account'] ?? '';

        // Merge into existing userData and persist
        final updated = Map<String, dynamic>.from(userData ?? {});
        if (pagaAcct != null && pagaAcct.toString().isNotEmpty) {
          // Save Paga account in sAsfiyBank
          updated['sAsfiyBank'] = pagaAcct.toString();
        }
        if (palmpayAcct != null && palmpayAcct.toString().isNotEmpty) {
          // Save Palmpay account in sPaga
          updated['sPaga'] = palmpayAcct.toString();
        }
        // Mark that accounts were generated in the app
        updated['sBankName'] = 'app';

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_data', json.encode(updated));

        setState(() {
          userData = updated;
        });

        String successMsg = 'Account generated successfully';
        if (type == 'both') {
          successMsg = 'Both accounts generated successfully';
        } else if (type == 'paga') {
          successMsg = 'Paga account generated successfully';
        } else if (type == 'palmpay') {
          successMsg = 'Palmpay account generated successfully';
        }

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMsg)));

        // Send notification asynchronously (don't wait for it)
        String notificationAccountType = '';
        if (type == 'both') {
          notificationAccountType = 'Palmpay and Paga';
        } else if (type == 'paga') {
          notificationAccountType = 'Paga';
        } else if (type == 'palmpay') {
          notificationAccountType = 'Palmpay';
        }
        _sendAccountGenerationNotification(
          userId ?? '',
          notificationAccountType,
        );
      } else {
        final msg = data['message'] ?? 'Failed to generate account';
        throw Exception(msg);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating account: ${e.toString()}')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  List<Map<String, String>> _collectAccounts() {
    final List<Map<String, String>> accounts = [];
    if (userData == null) return accounts;

    void add(String key, String bankName) {
      final v = userData?[key];
      if (v != null) {
        final s = v.toString().trim();
        if (s.isNotEmpty && !accounts.any((a) => a['account'] == s)) {
          accounts.add({'bank': bankName, 'account': s});
        }
      }
    }

    // Check if accounts were generated via app
    final isAppGenerated = userData?['sBankName'] == 'app';

    if (isAppGenerated) {
      // Accounts generated in app: sPaga as Palmpay, sAsfiyBank as Paga
      add('sPaga', 'Palmpay');
      add('sAsfiyBank', 'Paga');
    } else {
      // Accounts from other sources: sPaga as Palmpay, sAsfiyBank as Paga
      add('sPaga', 'Palmpay');
      add('sAsfiyBank', 'Paga');
    }

    return accounts;
  }

  @override
  Widget build(BuildContext context) {
    final accounts = _collectAccounts();
    final bool bothMissing = accounts.isEmpty;

    // Check which accounts are missing
    final bool hasPalmpay =
        userData?['sPaga'] != null &&
        userData!['sPaga'].toString().trim().isNotEmpty;
    final bool hasPaga =
        userData?['sAsfiyBank'] != null &&
        userData!['sAsfiyBank'].toString().trim().isNotEmpty;
    final bool palmpayMissing = !hasPalmpay;
    final bool pagaMissing = !hasPaga;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: const Text(
          'Virtual Account',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFFce4323),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFce4323)),
            )
          : SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(getResponsiveSize(context, 16.0)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Virtual Account:',
                      style: TextStyle(
                        fontSize: getResponsiveSize(context, 16),
                        fontWeight: FontWeight.w600,
                        color: const Color.fromARGB(255, 0, 0, 0),
                      ),
                    ),
                    SizedBox(height: getResponsiveSize(context, 16)),
                    if (accounts.isEmpty)
                      Container(
                        padding: EdgeInsets.all(getResponsiveSize(context, 16)),
                        child: Center(
                          child: Text(
                            'No accounts available',
                            style: TextStyle(
                              fontSize: getResponsiveSize(context, 14),
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    for (final acc in accounts) ...[
                      _buildVirtualAccountCard(
                        bankName: acc['bank'] ?? 'Account',
                        accountNumber: acc['account'] ?? '',
                        accountHolder: userData?['sFname'] ?? 'User',
                        chargeRate: 'Charges: 1%',
                      ),
                      SizedBox(height: getResponsiveSize(context, 12)),
                    ],

                    // Show generate buttons based on what's available
                    if (bothMissing)
                      // Both missing: show button to generate both
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: getResponsiveSize(context, 0),
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isGenerating
                                ? null
                                : () => _generateAccounts(type: 'both'),
                            icon: _isGenerating
                                ? SizedBox(
                                    width: getResponsiveSize(context, 16),
                                    height: getResponsiveSize(context, 16),
                                    child: const CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.vpn_key_outlined),
                            label: Padding(
                              padding: EdgeInsets.symmetric(
                                vertical: getResponsiveSize(context, 12),
                              ),
                              child: Text(
                                _isGenerating
                                    ? 'Generating...'
                                    : 'Generate Account Numbers',
                                style: TextStyle(
                                  fontSize: getResponsiveSize(context, 14),
                                ),
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFce4323),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      )
                    else if (palmpayMissing || pagaMissing)
                      // One or both missing: show separate buttons
                      Column(
                        children: [
                          if (palmpayMissing)
                            Padding(
                              padding: EdgeInsets.only(
                                bottom: getResponsiveSize(context, 12),
                              ),
                              child: SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _isGenerating
                                      ? null
                                      : () =>
                                            _generateAccounts(type: 'palmpay'),
                                  icon: _isGenerating
                                      ? SizedBox(
                                          width: getResponsiveSize(context, 16),
                                          height: getResponsiveSize(
                                            context,
                                            16,
                                          ),
                                          child:
                                              const CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2,
                                              ),
                                        )
                                      : const Icon(Icons.vpn_key_outlined),
                                  label: Padding(
                                    padding: EdgeInsets.symmetric(
                                      vertical: getResponsiveSize(context, 12),
                                    ),
                                    child: Text(
                                      _isGenerating
                                          ? 'Generating...'
                                          : 'Generate Palmpay Account',
                                      style: TextStyle(
                                        fontSize: getResponsiveSize(
                                          context,
                                          14,
                                        ),
                                      ),
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFce4323),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (pagaMissing)
                            Padding(
                              padding: EdgeInsets.only(
                                bottom: getResponsiveSize(context, 12),
                              ),
                              child: SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _isGenerating
                                      ? null
                                      : () => _generateAccounts(type: 'paga'),
                                  icon: _isGenerating
                                      ? SizedBox(
                                          width: getResponsiveSize(context, 16),
                                          height: getResponsiveSize(
                                            context,
                                            16,
                                          ),
                                          child:
                                              const CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2,
                                              ),
                                        )
                                      : const Icon(Icons.vpn_key_outlined),
                                  label: Padding(
                                    padding: EdgeInsets.symmetric(
                                      vertical: getResponsiveSize(context, 12),
                                    ),
                                    child: Text(
                                      _isGenerating
                                          ? 'Generating...'
                                          : 'Generate Paga Account',
                                      style: TextStyle(
                                        fontSize: getResponsiveSize(
                                          context,
                                          14,
                                        ),
                                      ),
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFce4323),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    SizedBox(height: getResponsiveSize(context, 24)),
                    // 'Pay Manually' button removed by request
                  ],
                ),
              ),
            ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: EdgeInsets.symmetric(
            vertical: getResponsiveSize(context, 8),
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: Colors.grey.shade200, width: 1),
            ),
          ),
          child: BottomNavigationBar(
            currentIndex: 1,
            onTap: (index) async {
              if (index == 0) {
                // Replace wallet page with dashboard (home) to avoid pop flash
                Navigator.pushReplacementNamed(context, '/dashboard');
              } else if (index == 2) {
                // Navigate to account while ensuring dashboard remains in stack
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/account',
                  ModalRoute.withName('/dashboard'),
                );
              }
            },
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.white,
            elevation: 0,
            showSelectedLabels: true,
            showUnselectedLabels: true,
            selectedItemColor: const Color(0xFFce4323),
            unselectedItemColor: Colors.grey.shade500,
            selectedFontSize: getResponsiveSize(context, 11),
            unselectedFontSize: getResponsiveSize(context, 11),
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
            iconSize: getResponsiveSize(context, 24),
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                activeIcon: Icon(Icons.home),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.account_balance_wallet_outlined),
                activeIcon: Icon(Icons.account_balance_wallet),
                label: 'Wallet',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person_outline),
                activeIcon: Icon(Icons.person),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVirtualAccountCard({
    required String bankName,
    required String accountNumber,
    required String accountHolder,
    required String chargeRate,
  }) {
    final hasAccount =
        accountNumber != 'Generate Account' && accountNumber.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
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
        borderRadius: BorderRadius.circular(getResponsiveSize(context, 12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
            spreadRadius: 2,
          ),
        ],
      ),
      padding: EdgeInsets.all(getResponsiveSize(context, 16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bank Name and Wallet Icon
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                bankName,
                style: TextStyle(
                  fontSize: getResponsiveSize(context, 14),
                  fontWeight: FontWeight.w500,
                  color: Colors.white70,
                ),
              ),
              Icon(
                Icons.account_balance_wallet,
                color: Colors.white.withOpacity(0.7),
                size: getResponsiveSize(context, 24),
              ),
            ],
          ),
          SizedBox(height: getResponsiveSize(context, 12)),

          // Account Number
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  hasAccount ? accountNumber : 'Generate Account',
                  style: TextStyle(
                    fontSize: getResponsiveSize(context, 18),
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasAccount)
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: accountNumber));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Account number copied!'),
                        duration: const Duration(seconds: 2),
                        backgroundColor: Colors.green,
                      ),
                    );
                  },
                  child: Icon(
                    Icons.copy,
                    color: Colors.white70,
                    size: getResponsiveSize(context, 20),
                  ),
                ),
            ],
          ),
          SizedBox(height: getResponsiveSize(context, 12)),

          // Account Holder
          Text(
            accountHolder,
            style: TextStyle(
              fontSize: getResponsiveSize(context, 12),
              color: Colors.white70,
            ),
          ),
          SizedBox(height: getResponsiveSize(context, 8)),

          // Charge Rate
          Text(
            chargeRate,
            style: TextStyle(
              fontSize: getResponsiveSize(context, 12),
              color: Colors.white54,
            ),
          ),
        ],
      ),
    );
  }
}
