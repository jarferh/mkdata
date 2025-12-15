import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
// import 'manual_payment_page.dart';
// manual payment UI still exists as a page but the quick action is removed from Wallet

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
          final userId = prefs.getString('user_id');
          if (userId == null) {
            throw Exception('User ID not found');
          }

          final response = await http.get(
            Uri.parse('${ApiService.baseUrl}/api/account-details?id=$userId'),
          );

          print('API Response Status Code: ${response.statusCode}');
          print('API Response Body: ${response.body}');

          if (response.statusCode == 200) {
            final responseData = json.decode(response.body);
            print('Decoded API Response: ${json.encode(responseData)}');

            if (responseData['status'] == 'success') {
              formattedData = responseData['data'];
              print('Account Details Data: ${json.encode(formattedData)}');

              // Save the fetched data to SharedPreferences
              await prefs.setString('user_data', json.encode(formattedData));
              print('Data saved to SharedPreferences');
            } else {
              final msg =
                  responseData['message'] ?? 'Failed to fetch account details';
              throw Exception(msg);
            }
          } else {
            // Try to extract server-provided message
            String msg = 'Failed to fetch account details';
            try {
              final responseData = json.decode(response.body);
              if (responseData is Map && responseData['message'] != null) {
                msg = responseData['message'].toString();
              }
            } catch (_) {}
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

  Future<void> _generateAccounts() async {
    try {
      setState(() {
        _isGenerating = true;
      });

      final prefs = await SharedPreferences.getInstance();
      String? userId = prefs.getString('user_id');
      if (userId == null && userData != null && userData!['sId'] != null) {
        userId = userData!['sId'].toString();
      }

      final uri = Uri.parse('${ApiService.baseUrl}/api/generate-palmpay-paga');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'user_id': userId}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          final pagaAcct = data['data']?['paga_account'] ?? '';
          final palmpayAcct = data['data']?['palmpay_account'] ?? '';

          // Merge into existing userData and persist
          final updated = Map<String, dynamic>.from(userData ?? {});
          if (pagaAcct != null && pagaAcct.toString().isNotEmpty) {
            updated['sPaga'] = pagaAcct.toString();
            // updated['sPagaBank'] = pagaAcct.toString();
          }
          if (palmpayAcct != null && palmpayAcct.toString().isNotEmpty) {
            updated['sPalmpayBank'] = palmpayAcct.toString();
          }
          // Mark that accounts were generated in the app
          updated['sBankName'] = 'app';

          await prefs.setString('user_data', json.encode(updated));

          setState(() {
            userData = updated;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Accounts generated successfully')),
          );
        } else {
          final msg = data['message'] ?? 'Failed to generate accounts';
          throw Exception(msg);
        }
      } else {
        String msg = 'Server error: ${response.statusCode}';
        try {
          final body = json.decode(response.body);
          if (body is Map && body['message'] != null) {
            msg = body['message'].toString();
          }
        } catch (_) {}
        throw Exception(msg);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating accounts: ${e.toString()}')),
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
      // Accounts generated in app: sPaga as Paga, sPalmpayBank as Palmpay
      add('sPalmpayBank', 'Palmpay');
      add('sPaga', 'Paga');
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

                    // Show generate button when no accounts exist
                    if (bothMissing)
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: getResponsiveSize(context, 0),
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isGenerating ? null : _generateAccounts,
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
