import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../utils/network_utils.dart';
import 'transactions_page.dart';

const Color primaryColor = Color(0xFFce4323);

class InvitePage extends StatefulWidget {
  const InvitePage({super.key});

  @override
  State<InvitePage> createState() => _InvitePageState();
}

class _InvitePageState extends State<InvitePage> {
  String referralCode = '';
  String phoneNumber = '';
  String referralLink = '';
  Map<String, dynamic>? userData;
  double _commission = 0.0;
  int totalReferrals = 0;
  int claimedReferrals = 0;
  int pendingReferrals = 0;
  double totalEarned = 0.0;
  int userId = 0;

  final _amountController = TextEditingController();
  bool _isHidden = true;
  bool _isLoadingReferrals = false;

  List<Map<String, dynamic>> referrals = [];

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataStr = prefs.getString('user_data');

      if (userDataStr != null) {
        final data = json.decode(userDataStr);
        setState(() {
          userData = data;
          userId = data['sId'] ?? 0;
          // Combine first and last name and remove any whitespace
          referralCode = '${data['sFname'] ?? ''}${data['sLname'] ?? ''}'
              .replaceAll(' ', '')
              .toLowerCase();
          // Get phone number
          phoneNumber = data['sPhone'] ?? data['phone'] ?? '';
          // Generate referral link
          referralLink =
              'https://mkdata.com.ng/mobile/register/?referral=$phoneNumber';
          // Commission / referral wallet
          _commission =
              double.tryParse(
                (data['sRefWallet'] ?? data['refWallet'] ?? 0).toString(),
              ) ??
              0.0;
        });
        // Load referrals after user data is set
        await _fetchReferrals();
      }
    } catch (e) {
      print('[InvitePage] Error loading user data: $e');
    }
  }

  Future<void> _fetchReferrals() async {
    if (userId == 0) return;

    setState(() {
      _isLoadingReferrals = true;
    });

    try {
      final client = http.Client();
      final response = await client.post(
        Uri.parse('${ApiService.baseUrl}/api/get-referrals.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': userId}),
      );

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        if (jsonData != null && jsonData['success'] == true) {
          final stats = jsonData['stats'] as Map<String, dynamic>;
          final referralsData = jsonData['referrals'] as List<dynamic>;

          setState(() {
            totalReferrals = stats['total_referrals'] ?? 0;
            claimedReferrals = stats['claimed_rewards'] ?? 0;
            pendingReferrals = stats['pending_rewards'] ?? 0;
            totalEarned = (stats['total_earned'] ?? 0.0).toDouble();

            referrals = referralsData.map((ref) {
              return {
                'id': ref['id'],
                'name': ref['name'] ?? 'Unknown',
                'phone': ref['phone'] ?? 'N/A',
                'email': ref['email'] ?? '',
                'status':
                    (ref['reward_claimed'] == true ||
                        ref['reward_claimed'] == 1)
                    ? 'claimed'
                    : 'pending',
                'joinedDate': ref['referred_date'] ?? '',
                'commission': ref['reward_amount'] ?? 0.0,
                'reward_claimed':
                    ref['reward_claimed'] == true || ref['reward_claimed'] == 1,
              };
            }).toList();

            _isLoadingReferrals = false;
          });
        } else {
          setState(() {
            _isLoadingReferrals = false;
          });
        }
      } else {
        setState(() {
          _isLoadingReferrals = false;
        });
      }
    } catch (e) {
      print('[InvitePage] Error fetching referrals: $e');
      setState(() {
        _isLoadingReferrals = false;
      });
    }
  }

  Future<void> _claimReward(int referralId, double amount) async {
    try {
      final client = http.Client();
      final response = await client.post(
        Uri.parse('${ApiService.baseUrl}/api/claim-referral-reward.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': userId, 'referral_id': referralId}),
      );

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        if (jsonData != null && jsonData['success'] == true) {
          // Update commission balance
          setState(() {
            _commission += amount;
          });

          showNetworkErrorSnackBar(
            context,
            'Reward claimed: ₦${amount.toStringAsFixed(2)}',
          );
          // Refresh referrals list
          await _fetchReferrals();
        } else {
          showNetworkErrorSnackBar(
            context,
            jsonData?['message'] ?? 'Failed to claim reward',
          );
        }
      } else {
        showNetworkErrorSnackBar(context, 'Failed to claim reward');
      }
    } catch (e) {
      print('[InvitePage] Error claiming reward: $e');
      showNetworkErrorSnackBar(context, 'Error claiming reward');
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    showNetworkErrorSnackBar(context, '$label copied to clipboard');
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _showWithdrawModal() {
    _amountController.clear();
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Withdraw',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Available Balance',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              Text(
                '₦${_commission.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Amount',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Enter amount',
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
                    borderSide: const BorderSide(color: primaryColor, width: 2),
                  ),
                  prefixText: '₦ ',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () async {
                    final amount =
                        double.tryParse(_amountController.text) ?? 0.0;
                    if (amount <= 0) {
                      showNetworkErrorSnackBar(
                        context,
                        'Please enter a valid amount',
                      );
                      return;
                    }
                    if (amount > _commission) {
                      showNetworkErrorSnackBar(
                        context,
                        'Amount exceeds available balance',
                      );
                      return;
                    }

                    // Call withdrawal API
                    try {
                      final client = http.Client();
                      final response = await client.post(
                        Uri.parse(
                          '${ApiService.baseUrl}/api/withdraw-referral.php',
                        ),
                        headers: {'Content-Type': 'application/json'},
                        body: jsonEncode({'user_id': userId, 'amount': amount}),
                      );

                      if (response.statusCode == 200) {
                        final jsonData = jsonDecode(response.body);
                        if (jsonData != null && jsonData['success'] == true) {
                          // Update commission balance
                          setState(() {
                            _commission = (jsonData['new_ref_wallet'] ?? 0.0)
                                .toDouble();
                          });

                          if (mounted) {
                            Navigator.pop(context);
                            showNetworkErrorSnackBar(
                              context,
                              'Withdrawal successful! ₦${amount.toStringAsFixed(2)} added to main wallet',
                            );
                            // Refresh user data to update all balances
                            await _loadUserData();
                          }
                        } else {
                          showNetworkErrorSnackBar(
                            context,
                            jsonData?['message'] ?? 'Withdrawal failed',
                          );
                        }
                      } else {
                        final jsonData = jsonDecode(response.body);
                        showNetworkErrorSnackBar(
                          context,
                          jsonData?['message'] ?? 'Withdrawal failed',
                        );
                      }
                    } catch (e) {
                      print('[InvitePage] Error withdrawing: $e');
                      showNetworkErrorSnackBar(
                        context,
                        'Error withdrawing funds',
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Request Withdrawal',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade300, width: 1.5),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Earn',
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
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
                color: Colors.black,
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
              // Wallet Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [primaryColor, primaryColor.withOpacity(0.85)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: primaryColor.withOpacity(0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Referral Balance',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.85),
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Text(
                                  '₦ ',
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  _isHidden
                                      ? '••••••'
                                      : _commission.toStringAsFixed(2),
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: IconButton(
                                onPressed: () {
                                  setState(() {
                                    _isHidden = !_isHidden;
                                  });
                                },
                                icon: Icon(
                                  _isHidden
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                padding: const EdgeInsets.all(8),
                                constraints: const BoxConstraints(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: IconButton(
                                onPressed: () {
                                  setState(() {
                                    _loadUserData();
                                  });
                                },
                                icon: const Icon(
                                  Icons.refresh,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                padding: const EdgeInsets.all(8),
                                constraints: const BoxConstraints(),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Container(
                    //   padding: const EdgeInsets.symmetric(
                    //     horizontal: 12,
                    //     vertical: 8,
                    //   ),
                    //   decoration: BoxDecoration(
                    //     color: Colors.white.withOpacity(0.15),
                    //     borderRadius: BorderRadius.circular(8),
                    //   ),
                    //   child: const Text(
                    //     'Charges: 0 Naira',
                    //     style: TextStyle(
                    //       fontSize: 12,
                    //       color: Colors.white,
                    //       fontWeight: FontWeight.w500,
                    //     ),
                    //   ),
                    // ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Referral Stats
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard('Total', totalReferrals.toString()),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      'Claimed',
                      claimedReferrals.toString(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      'Pending',
                      pendingReferrals.toString(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Referral Code & Phone Section
              const Text(
                'Your Referral Code',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade200, width: 1.5),
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.grey.shade50,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Phone Number',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              phoneNumber,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: IconButton(
                            onPressed: () =>
                                _copyToClipboard(phoneNumber, 'Phone number'),
                            icon: const Icon(
                              Icons.copy,
                              color: primaryColor,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // const SizedBox(height: 16),

              // Referral Link
              // const Text(
              //   'Referral Link',
              //   style: TextStyle(
              //     fontSize: 16,
              //     fontWeight: FontWeight.bold,
              //     color: Colors.black,
              //   ),
              // ),
              // const SizedBox(height: 12),
              // Container(
              //   padding: const EdgeInsets.all(14),
              //   decoration: BoxDecoration(
              //     border: Border.all(color: Colors.grey.shade200, width: 1.5),
              //     borderRadius: BorderRadius.circular(16),
              //     color: Colors.grey.shade50,
              //   ),
              //   child: Row(
              //     children: [
              //       Expanded(
              //         child: SingleChildScrollView(
              //           scrollDirection: Axis.horizontal,
              //           child: Text(
              //             referralLink,
              //             style: const TextStyle(
              //               fontSize: 13,
              //               color: primaryColor,
              //               fontWeight: FontWeight.w500,
              //             ),
              //           ),
              //         ),
              //       ),
              //       const SizedBox(width: 8),
              //       Container(
              //         decoration: BoxDecoration(
              //           color: primaryColor.withOpacity(0.1),
              //           borderRadius: BorderRadius.circular(10),
              //         ),
              //         child: IconButton(
              //           onPressed: () =>
              //               _copyToClipboard(referralLink, 'Referral link'),
              //           icon: const Icon(
              //             Icons.copy,
              //             color: primaryColor,
              //             size: 20,
              //           ),
              //           padding: const EdgeInsets.all(8),
              //           constraints: const BoxConstraints(),
              //         ),
              //       ),
              //     ],
              //   ),
              // ),
              const SizedBox(height: 24),

              // Withdraw Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    if (_commission <= 0) {
                      showNetworkErrorSnackBar(
                        context,
                        'Insufficient balance to withdraw',
                      );
                      return;
                    }
                    _showWithdrawModal();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Withdraw',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Referrals Table Section
              const Text(
                'Your Referrals',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 12),
              referrals.isEmpty
                  ? Container(
                      padding: const EdgeInsets.all(40),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: primaryColor.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.people_outline,
                              size: 48,
                              color: primaryColor.withOpacity(0.6),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No referrals yet',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Share your referral link to earn rewards',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _isLoadingReferrals
                          ? Container(
                              padding: const EdgeInsets.all(32),
                              width: MediaQuery.of(context).size.width - 32,
                              child: const Center(
                                child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    primaryColor,
                                  ),
                                ),
                              ),
                            )
                          : DataTable(
                              columnSpacing: 20,
                              headingRowColor: WidgetStateProperty.all(
                                Colors.grey.shade100,
                              ),
                              dataRowColor: WidgetStateProperty.all(
                                Colors.white,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.grey.shade200,
                                  width: 1.5,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              columns: const [
                                DataColumn(
                                  label: Text(
                                    'Name',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                DataColumn(
                                  label: Text(
                                    'Phone',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                DataColumn(
                                  label: Text(
                                    'Status',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                DataColumn(
                                  label: Text(
                                    'Reward',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                DataColumn(
                                  label: Text(
                                    'Action',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                              ],
                              rows: referrals
                                  .map(
                                    (referral) => DataRow(
                                      cells: [
                                        DataCell(
                                          SizedBox(
                                            width: 100,
                                            child: Text(
                                              referral['name'] ?? '',
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          SizedBox(
                                            width: 110,
                                            child: Text(
                                              referral['phone'] ?? '',
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color:
                                                  referral['reward_claimed'] ==
                                                      true
                                                  ? Colors.green.shade50
                                                  : Colors.amber.shade50,
                                              border: Border.all(
                                                color:
                                                    referral['reward_claimed'] ==
                                                        true
                                                    ? Colors.green.shade200
                                                    : Colors.amber.shade200,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              referral['reward_claimed'] == true
                                                  ? '✓ Claimed'
                                                  : '⏳ Pending',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color:
                                                    referral['reward_claimed'] ==
                                                        true
                                                    ? Colors.green.shade700
                                                    : Colors.amber.shade700,
                                              ),
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            '₦${(referral['commission'] as num).toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: primaryColor,
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          referral['reward_claimed'] == true
                                              ? Text(
                                                  'Claimed',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey.shade500,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                )
                                              : SizedBox(
                                                  width: 80,
                                                  height: 32,
                                                  child: ElevatedButton(
                                                    onPressed: () {
                                                      _claimReward(
                                                        referral['id'],
                                                        (referral['commission']
                                                                as num)
                                                            .toDouble(),
                                                      );
                                                    },
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor:
                                                          primaryColor,
                                                      padding: EdgeInsets.zero,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              6,
                                                            ),
                                                      ),
                                                    ),
                                                    child: const Text(
                                                      'Claim',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                        ),
                                      ],
                                    ),
                                  )
                                  .toList(),
                            ),
                    ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200, width: 1.5),
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade100,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: primaryColor,
            ),
          ),
        ],
      ),
    );
  }
}
