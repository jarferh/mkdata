import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Add this import for SystemNavigator
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:marquee/marquee.dart';
import 'package:url_launcher/url_launcher.dart';
import 'wallet_page.dart';
import 'invite_page.dart';
import 'airtime_page.dart';
import 'data_page.dart';
import 'cable_page.dart';
import 'electricity_page.dart';
import 'exam_pin_page.dart';
import 'datapin_page.dart';
import 'card_pin_page.dart';
import 'transactions_page.dart';
import 'contact_page.dart';
import 'daily_data_page.dart';
import 'past_questions_page.dart';
import 'welcome_bonus_page.dart';
import 'spin_and_win_page.dart';

// Custom Clipper for curved bottom background
class CurvedBottomClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.lineTo(0, size.height - 40);
    path.quadraticBezierTo(
      size.width / 2,
      size.height,
      size.width,
      size.height - 40,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Map<String, dynamic>? _userData;
  int _selectedIndex = 0;
  bool _isBalanceVisible = true;
  String? _profilePhotoPath;
  bool _welcomeShown = false;
  bool _isLoadingUserData = false;
  bool _isRefreshing = false; // separate flag for refresh icon loading state
  bool _userLoadFailed = false;
  bool _expandFloatingMenu = false;
  bool _isGeneratingAccounts = false;
  bool _bonusClaimable = false;
  double _bonusAmount = 0.0;
  bool _bonusDismissed = false;

  // Helper to format numbers with thousand separators (e.g. 10,000)
  String _addCommas(String s) {
    // Handle negative sign
    var negative = false;
    if (s.startsWith('-')) {
      negative = true;
      s = s.substring(1);
    }
    final chars = s.split('').reversed.toList();
    final out = <String>[];
    for (var i = 0; i < chars.length; i++) {
      if (i != 0 && i % 3 == 0) out.add(',');
      out.add(chars[i]);
    }
    final result = out.reversed.join();
    return negative ? '-$result' : result;
  }

  String _formatNumber(dynamic value) {
    if (value == null) return '0';
    // Normalize to string
    final s = value.toString();
    // Try parse as double
    final d = double.tryParse(s.replaceAll(',', ''));
    if (d == null) return s; // fallback to raw
    final isWhole = d == d.roundToDouble();
    if (isWhole) {
      return _addCommas(d.toInt().toString());
    }
    // keep two decimals for fractional amounts
    final parts = d.toStringAsFixed(2).split('.');
    parts[0] = _addCommas(parts[0]);
    return parts.join('.');
  }

  @override
  void initState() {
    super.initState();
    // Load cached data first so UI shows previous session info immediately,
    // then load profile photo and refresh from network.
    _loadCachedUserData();
    _loadProfilePhoto();
    _loadUserData();
    // show welcome popup once when the page is first opened
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_welcomeShown) {
        _showWelcomeDialog();
        _welcomeShown = true;
      }
    });
  }

  // Refresh dashboard data and re-show the welcome/notice dialog
  Future<void> _refreshDashboard() async {
    // Add small delay to ensure loading state is visible
    await Future.delayed(const Duration(milliseconds: 500));
    await _loadUserData();

    // Re-show the welcome dialog when the user explicitly refreshes
    if (mounted) {
      _showWelcomeDialog();
      _welcomeShown = true;
    }
  }

  // Load cached user_data from SharedPreferences immediately so the UI shows
  // the last session's data while a network refresh happens in background.
  Future<void> _loadCachedUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataJson = prefs.getString('user_data');
      if (userDataJson != null && mounted) {
        setState(() {
          _userData = json.decode(userDataJson);
          _userLoadFailed = false;
        });
      }
    } catch (e) {
      // ignore cached load errors
      print('Error loading cached user data: $e');
    }
  }

  void _showWelcomeDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 8,
          child: Container(
            padding: EdgeInsets.all(getResponsiveSize(context, 28)),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Close button in top right
                Align(
                  alignment: Alignment.topRight,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: getResponsiveSize(context, 36),
                      height: getResponsiveSize(context, 36),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close,
                        size: getResponsiveSize(context, 20),
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: getResponsiveSize(context, 16)),

                // Icon at top
                Container(
                  width: getResponsiveSize(context, 70),
                  height: getResponsiveSize(context, 70),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
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
                  ),
                  child: Icon(
                    Icons.notifications_active,
                    color: Colors.white,
                    size: getResponsiveSize(context, 40),
                  ),
                ),
                SizedBox(height: getResponsiveSize(context, 20)),

                // Title
                Text(
                  'Welcome!',
                  style: TextStyle(
                    fontSize: getResponsiveSize(context, 20),
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: getResponsiveSize(context, 12)),

                // Message with better formatting
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text:
                            'Dear ${_userData?['sFname']?.toString() ?? 'User'},\n\n',
                        style: TextStyle(
                          fontSize: getResponsiveSize(context, 14),
                          color: Colors.black87,
                          fontWeight: FontWeight.w600,
                          height: 1.5,
                        ),
                      ),
                      TextSpan(
                        text:
                            'Welcome to MK DATA, the best 👍 platform for automated VTU services.\n\n',
                        style: TextStyle(
                          fontSize: getResponsiveSize(context, 13),
                          color: Colors.grey.shade700,
                          height: 1.6,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      TextSpan(
                        text:
                            'Enjoy seamless transactions and exceptional service!',
                        style: TextStyle(
                          fontSize: getResponsiveSize(context, 12),
                          color: Colors.grey.shade600,
                          height: 1.5,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: getResponsiveSize(context, 24)),

                // Action button
                SizedBox(
                  width: double.infinity,
                  height: getResponsiveSize(context, 48),
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFce4323),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: Text(
                      'Got it!',
                      style: TextStyle(
                        fontSize: getResponsiveSize(context, 16),
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadProfilePhoto() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final photoPath = prefs.getString('profile_photo_path');
      if (photoPath != null) {
        // Evict any cached image for this file so updated image is loaded
        try {
          final fileImage = FileImage(File(photoPath));
          await fileImage.evict();
        } catch (e) {
          // ignore eviction errors
        }

        setState(() {
          _profilePhotoPath = photoPath;
        });
      }
    } catch (e) {
      print('Error loading profile photo: $e');
    }
  }

  // Helper to navigate to a page and refresh transactions when returning
  Future<T?> _pushAndRefresh<T>(Widget page) async {
    final res = await Navigator.push<T>(
      context,
      MaterialPageRoute(builder: (context) => page),
    );
    if (mounted) {
      // Reload full user data when returning so the dashboard behaves like a fresh open
      await _loadUserData();
      await _loadProfilePhoto();
    }
    return res;
  }

  Future<void> _loadUserData() async {
    // Load cached data first so UI always shows something immediately.
    // Only show a loading indicator when no cached data exists.
    late SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();

      String? userId = prefs.getString('user_id');
      String? userDataStr = prefs.getString('user_data');

      // If we have cached data, display it immediately and do a silent refresh.
      if (mounted) {
        setState(() {
          _userData = userDataStr != null ? json.decode(userDataStr) : null;
          _userLoadFailed = false;
          // Show loading only if there is no cached data
          _isLoadingUserData = userDataStr == null;
        });
      }

      // Fetch latest data in background
      final response = await http.get(
        Uri.parse('https://api.mkdata.com.ng/api/subscriber?id=$userId'),
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['status'] == 'success' &&
            responseData['data'] != null) {
          await prefs.setString('user_data', json.encode(responseData['data']));
          if (mounted) {
            setState(() {
              _userData = responseData['data'];
              _userLoadFailed = false;
            });
          }
        }
      } else {
        // If no cached data exists, mark load failure so UI can show a loader/error.
        if (userDataStr == null && mounted) {
          setState(() {
            _userData = null;
            _userLoadFailed = true;
          });
        }
      }
    } catch (e) {
      print('Error loading user data: $e');
      // If there is no cached data, signal load failure; otherwise keep cached data visible.
      if (mounted) {
        setState(() {
          if (_userData == null) {
            _userLoadFailed = true;
          }
        });
      }
    } finally {
      // Stop showing any loading indicator after background fetch completes.
      if (mounted) setState(() => _isLoadingUserData = false);

      // Load bonus status after user data
      _checkWelcomeBonusStatus();
    }
  }

  Future<void> _checkWelcomeBonusStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');

      if (userId == null) return;

      // Fetch bonus settings
      final settingsResponse = await http
          .get(
            Uri.parse('https://api.mkdata.com.ng/api/welcome-bonus-settings'),
          )
          .timeout(const Duration(seconds: 10));

      if (settingsResponse.statusCode == 200) {
        final settingsData = json.decode(settingsResponse.body);
        if (settingsData['status'] == 'success') {
          setState(() {
            _bonusAmount = double.parse(
              settingsData['data']['amount'].toString(),
            );
          });
        }
      }

      // Fetch user's bonus status
      final statusResponse = await http
          .get(
            Uri.parse(
              'https://api.mkdata.com.ng/api/welcome-bonus-status?user_id=$userId',
            ),
          )
          .timeout(const Duration(seconds: 10));

      if (statusResponse.statusCode == 200) {
        final statusData = json.decode(statusResponse.body);
        if (statusData['status'] == 'success') {
          final data = statusData['data'];
          if (mounted) {
            setState(() {
              _bonusClaimable = !(data['has_claimed'] ?? false);
            });
          }
        }
      }
    } catch (e) {
      print('Error checking bonus status: $e');
    }
  }

  // Returns a friendly display name or the network-error prompt
  String _getUserDisplayName() {
    if (_isLoadingUserData) return '';
    if (_userLoadFailed || _userData == null) return 'network error try again';
    final fname = (_userData!['sFname'] ?? '').toString().trim();
    final lname = (_userData!['sLname'] ?? '').toString().trim();
    // Build full name parts; some users may have up to 3 names stored.
    final parts = <String>[];
    if (fname.isNotEmpty) parts.addAll(fname.split(RegExp(r"\s+")));
    if (lname.isNotEmpty) parts.addAll(lname.split(RegExp(r"\s+")));

    if (parts.isEmpty) return 'network error try again';

    // If there are 1 or 2 words, show them fully. If there are 3+ words,
    // show first 2 words unless the 2nd word is <= 4 characters AND showing
    // the 3rd word keeps it short; in that case show all first 3 words.
    if (parts.length <= 2) return parts.join(' ');

    // parts.length >= 3
    final first = parts[0];
    final second = parts[1];
    final third = parts[2];

    if (second.length <= 4) {
      // If second word is short, consider showing the third word as well if
      // the third word is also short-ish (<= 8) to avoid overflow.
      if (third.length <= 8) {
        return '$first $second $third';
      }
    }

    return '$first $second';
  }

  // Helper method to get responsive size
  double getResponsiveSize(BuildContext context, double baseSize) {
    double screenWidth = MediaQuery.of(context).size.width;
    double scaleFactor = screenWidth / 375; // Base width (iPhone SE)
    return baseSize * scaleFactor.clamp(0.7, 1.3); // Limit scaling
  }

  // Helper method to get responsive padding
  EdgeInsets getResponsivePadding(BuildContext context, double basePadding) {
    double scaleFactor = MediaQuery.of(context).size.width / 375;
    double responsivePadding = basePadding * scaleFactor.clamp(0.8, 1.2);
    return EdgeInsets.all(responsivePadding);
  }

  // Helper method to determine grid cross axis count
  int getGridCrossAxisCount(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 350) return 2;
    if (screenWidth < 600) return 3;
    return 4;
  }

  Future<void> _generateAccounts() async {
    try {
      setState(() {
        _isGeneratingAccounts = true;
      });

      final prefs = await SharedPreferences.getInstance();
      String? userId = prefs.getString('user_id');
      if (userId == null && _userData != null && _userData!['sId'] != null) {
        userId = _userData!['sId'].toString();
      }

      final uri = Uri.parse(
        'https://api.mkdata.com.ng/api/generate-palmpay-paga',
      );
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
          final updated = Map<String, dynamic>.from(_userData ?? {});
          if (pagaAcct != null && pagaAcct.toString().isNotEmpty) {
            updated['sPaga'] = pagaAcct.toString();
          }
          if (palmpayAcct != null && palmpayAcct.toString().isNotEmpty) {
            updated['sPalmpayBank'] = palmpayAcct.toString();
          }
          // Mark that accounts were generated in the app
          updated['sBankName'] = 'app';

          await prefs.setString('user_data', json.encode(updated));

          if (mounted) {
            setState(() {
              _userData = updated;
            });

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Accounts generated successfully')),
            );
          }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating accounts: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingAccounts = false;
        });
      }
    }
  }

  // Collect all available account fields from user data
  List<Map<String, String>> _collectAccounts() {
    final List<Map<String, String>> accounts = [];
    if (_userData == null) return accounts;

    void add(String key, String bankName) {
      final v = _userData?[key];
      if (v != null) {
        final s = v.toString().trim();
        if (s.isNotEmpty && !accounts.any((a) => a['account'] == s)) {
          accounts.add({'bank': bankName, 'account': s});
        }
      }
    }

    // Check if accounts were generated via app
    final isAppGenerated = _userData?['sBankName'] == 'app';

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

  // Build individual account card
  Widget _buildAccountCard({
    required String bankName,
    required String accountNumber,
  }) {
    return Container(
      height: getResponsiveSize(context, 180),
      padding: EdgeInsets.all(getResponsiveSize(context, 8)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(getResponsiveSize(context, 12)),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Account Number',
                style: TextStyle(
                  fontSize: getResponsiveSize(context, 14),
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.more_vert,
                  size: getResponsiveSize(context, 16),
                  color: Colors.grey,
                ),
                onPressed: () {},
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          SizedBox(height: getResponsiveSize(context, 2)),
          Row(
            children: [
              Expanded(
                child: Text(
                  accountNumber,
                  style: TextStyle(
                    fontSize: getResponsiveSize(context, 25),
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.content_copy,
                  size: getResponsiveSize(context, 20),
                  color: Colors.grey,
                ),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: accountNumber));
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          SizedBox(height: getResponsiveSize(context, 4)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bankName,
                    style: TextStyle(
                      fontSize: getResponsiveSize(context, 14),
                      color: Colors.grey,
                    ),
                  ),
                  Text(
                    '${_userData?['sFname'] ?? ''} ${_userData?['sLname'] ?? ''}',
                    style: TextStyle(
                      fontSize: getResponsiveSize(context, 14),
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Charges:',
                    style: TextStyle(
                      fontSize: getResponsiveSize(context, 11),
                      color: Colors.grey,
                    ),
                  ),
                  Text(
                    '1%',
                    style: TextStyle(
                      fontSize: getResponsiveSize(context, 12),
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Fixed exit confirmation dialog
  Future<bool> _showExitConfirmationDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            padding: EdgeInsets.all(getResponsiveSize(context, 24)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Close button
                Align(
                  alignment: Alignment.topRight,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(false),
                    child: Icon(
                      Icons.close,
                      size: getResponsiveSize(context, 24),
                      color: Colors.black54,
                    ),
                  ),
                ),
                SizedBox(height: getResponsiveSize(context, 16)),
                // Red X icon in circle
                Container(
                  width: getResponsiveSize(context, 80),
                  height: getResponsiveSize(context, 80),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.red.shade400, width: 3),
                  ),
                  child: Icon(
                    Icons.close,
                    size: getResponsiveSize(context, 48),
                    color: Colors.red.shade400,
                  ),
                ),
                SizedBox(height: getResponsiveSize(context, 24)),
                // Title
                Text(
                  'Note',
                  style: TextStyle(
                    fontSize: getResponsiveSize(context, 18),
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: getResponsiveSize(context, 12)),
                // Question
                Text(
                  'Do you want to exit?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: getResponsiveSize(context, 16),
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                SizedBox(height: getResponsiveSize(context, 24)),
                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: getResponsiveSize(context, 44),
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0A5ED7),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            'NO',
                            style: TextStyle(
                              fontSize: getResponsiveSize(context, 16),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: getResponsiveSize(context, 12)),
                    Expanded(
                      child: SizedBox(
                        height: getResponsiveSize(context, 44),
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade400,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            'YES',
                            style: TextStyle(
                              fontSize: getResponsiveSize(context, 16),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    return result ?? false;
  }

  // Logout confirmation dialog
  // Handle back button press
  Future<bool> _onWillPop() async {
    // Show exit confirmation dialog
    bool shouldExit = await _showExitConfirmationDialog();

    if (shouldExit) {
      // Exit the app completely (terminate process) on mobile platforms.
      // Using exit(0) forces the Dart VM to terminate so the app won't be paused.
      try {
        if (Platform.isAndroid || Platform.isIOS) {
          exit(0);
        } else {
          SystemNavigator.pop();
        }
      } catch (e) {
        // Fallback: attempt normal platform pop if exit fails
        try {
          SystemNavigator.pop();
        } catch (_) {}
      }
    }

    return false; // Always return false to prevent default back action
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Prevent default back action
      onPopInvoked: (didPop) {
        if (!didPop) {
          _onWillPop(); // Call our custom handler
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        floatingActionButton: Stack(
          children: [
            // Floating menu items
            if (_expandFloatingMenu)
              Positioned(
                bottom: 80,
                right: 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildFloatingMenuItem(
                      'Whatsapp',
                      Icons.chat,
                      Colors.green,
                      () async {
                        final Uri whatsappUrl = Uri.parse(
                          'https://wa.me/2348022412220',
                        );
                        if (await canLaunchUrl(whatsappUrl)) {
                          await launchUrl(
                            whatsappUrl,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                        setState(() => _expandFloatingMenu = false);
                      },
                    ),
                    SizedBox(height: getResponsiveSize(context, 12)),
                    _buildFloatingMenuItem(
                      'Channel',
                      Icons.tv,
                      const Color(0xFF0A5ED7),
                      () async {
                        final Uri channelUrl = Uri.parse(
                          'https://chat.whatsapp.com/Ixd8nVwcNttCfCXTfo9azZ?mode=hqrc',
                        );
                        if (await canLaunchUrl(channelUrl)) {
                          await launchUrl(
                            channelUrl,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                        setState(() => _expandFloatingMenu = false);
                      },
                    ),
                    SizedBox(height: getResponsiveSize(context, 12)),
                    _buildFloatingMenuItem(
                      'Contact Us',
                      Icons.mail,
                      Colors.orange,
                      () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ContactPage(),
                          ),
                        );
                        setState(() => _expandFloatingMenu = false);
                      },
                    ),
                  ],
                ),
              ),
            // Main floating button
            Positioned(
              bottom: 16,
              right: 16,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
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
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      setState(() {
                        _expandFloatingMenu = !_expandFloatingMenu;
                      });
                    },
                    child: Padding(
                      padding: EdgeInsets.all(getResponsiveSize(context, 16)),
                      child: Icon(
                        _expandFloatingMenu ? Icons.close : Icons.headset_mic,
                        color: Colors.white,
                        size: getResponsiveSize(context, 28),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(getResponsiveSize(context, 56)),
          child: AppBar(
            backgroundColor: Color(0xFFce4323),
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
            elevation: 0,
            automaticallyImplyLeading: false,
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Avatar on the left
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: CircleAvatar(
                    radius: getResponsiveSize(context, 20),
                    backgroundColor: Colors.grey.shade200,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        getResponsiveSize(context, 20),
                      ),
                      child: _profilePhotoPath != null
                          ? Image.file(
                              File(_profilePhotoPath!),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Image.asset(
                                  'assets/images/avatar.png',
                                  fit: BoxFit.cover,
                                );
                              },
                            )
                          : Image.asset(
                              'assets/images/avatar.png',
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Icon(
                                  Icons.person,
                                  size: getResponsiveSize(context, 18),
                                  color: Colors.grey,
                                );
                              },
                            ),
                    ),
                  ),
                ),
                SizedBox(width: getResponsiveSize(context, 12)),
                // Name and greeting in center
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Hi 👋',
                        style: TextStyle(
                          fontSize: getResponsiveSize(context, 11),
                          color: Colors.white70,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      Text(
                        _getUserDisplayName().toUpperCase(),
                        style: TextStyle(
                          fontSize: getResponsiveSize(context, 14),
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Notification icon on the right
                IconButton(
                  icon: Icon(
                    Icons.notifications_outlined,
                    color: Colors.white,
                    size: getResponsiveSize(context, 22),
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const TransactionsPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Curved Blue Background with Balance Section
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
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
                  padding: EdgeInsets.fromLTRB(
                    getResponsiveSize(context, 16),
                    getResponsiveSize(context, 16),
                    getResponsiveSize(context, 16),
                    getResponsiveSize(context, 20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'Wallet Balance',
                        style: TextStyle(
                          fontSize: getResponsiveSize(context, 13),
                          color: Colors.white70,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      SizedBox(height: getResponsiveSize(context, 8)),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _isBalanceVisible
                                ? '₦ ${_formatNumber(_userData != null ? (_userData!['sWallet'] ?? '0') : '0')}'
                                : '₦ ****',
                            style: TextStyle(
                              fontSize: getResponsiveSize(context, 36),
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: getResponsiveSize(context, 12)),
                          IconButton(
                            icon: Icon(
                              _isBalanceVisible
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              color: Colors.white70,
                            ),
                            iconSize: getResponsiveSize(context, 20),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              if (mounted) {
                                setState(
                                  () => _isBalanceVisible = !_isBalanceVisible,
                                );
                              }
                            },
                          ),
                          SizedBox(width: getResponsiveSize(context, 8)),
                          Material(
                            shape: const CircleBorder(),
                            color: Colors.white.withOpacity(0.2),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () async {
                                if (mounted) {
                                  setState(() => _isRefreshing = true);
                                }
                                await _refreshDashboard();
                                if (mounted) {
                                  setState(() => _isRefreshing = false);
                                }
                              },
                              child: Padding(
                                padding: EdgeInsets.all(
                                  getResponsiveSize(context, 8),
                                ),
                                child: _isRefreshing
                                    ? SizedBox(
                                        width: getResponsiveSize(context, 16),
                                        height: getResponsiveSize(context, 16),
                                        child: const CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
                                        ),
                                      )
                                    : Icon(
                                        Icons.refresh,
                                        color: Colors.white70,
                                        size: getResponsiveSize(context, 18),
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: getResponsiveSize(context, 6)),
                      // Marquee running text
                      SizedBox(
                        height: getResponsiveSize(context, 16),
                        child: Marquee(
                          text:
                              'Do not send Airtime to a SIM owing Airtel • Do not deliver Data Value nor refund • When Airtel SME Data is sold to SIMs owing them',
                          style: TextStyle(
                            fontSize: getResponsiveSize(context, 9),
                            color: Colors.white70,
                            fontWeight: FontWeight.w400,
                          ),
                          scrollAxis: Axis.horizontal,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          blankSpace: 20.0,
                          velocity: 30.0,
                          startPadding: 10.0,
                          accelerationDuration: const Duration(seconds: 2),
                          accelerationCurve: Curves.linear,
                          decelerationDuration: const Duration(
                            milliseconds: 500,
                          ),
                          decelerationCurve: Curves.easeOut,
                        ),
                      ),
                    ],
                  ),
                ),
                // Curve that goes down to half of account card
                ClipPath(
                  clipper: CurvedBottomClipper(),
                  child: Container(
                    width: double.infinity,
                    height: getResponsiveSize(context, 30),
                    decoration: const BoxDecoration(
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
                ),
                SizedBox(height: getResponsiveSize(context, 16)),

                // Welcome Bonus Banner
                if (_bonusClaimable && !_bonusDismissed)
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: getResponsiveSize(context, 16),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.green.shade600,
                            Colors.green.shade400,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green.withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      padding: EdgeInsets.all(getResponsiveSize(context, 12)),
                      child: Row(
                        children: [
                          Icon(
                            Icons.card_giftcard,
                            color: Colors.white,
                            size: getResponsiveSize(context, 28),
                          ),
                          SizedBox(width: getResponsiveSize(context, 12)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Claim Your Welcome Bonus!',
                                  style: TextStyle(
                                    fontSize: getResponsiveSize(context, 13),
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(height: getResponsiveSize(context, 2)),
                                Text(
                                  '₦${_bonusAmount.toStringAsFixed(2)} waiting for you',
                                  style: TextStyle(
                                    fontSize: getResponsiveSize(context, 11),
                                    color: Colors.white.withOpacity(0.9),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: () =>
                                _pushAndRefresh(const WelcomeBonusPage()),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: getResponsiveSize(context, 12),
                                vertical: getResponsiveSize(context, 6),
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Claim',
                                style: TextStyle(
                                  fontSize: getResponsiveSize(context, 11),
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: getResponsiveSize(context, 8)),
                          GestureDetector(
                            onTap: () {
                              setState(() => _bonusDismissed = true);
                            },
                            child: Icon(
                              Icons.close,
                              color: Colors.white.withOpacity(0.7),
                              size: getResponsiveSize(context, 20),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                SizedBox(height: getResponsiveSize(context, 16)),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: getResponsiveSize(context, 16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Horizontally scrollable account cards or generate button
                      if (_collectAccounts().isNotEmpty)
                        SizedBox(
                          height: getResponsiveSize(context, 200),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: EdgeInsets.symmetric(
                              horizontal: getResponsiveSize(context, 8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final acc in _collectAccounts()) ...[
                                  SizedBox(
                                    width:
                                        MediaQuery.of(context).size.width *
                                        0.85,
                                    child: _buildAccountCard(
                                      bankName: acc['bank'] ?? 'Account',
                                      accountNumber: acc['account'] ?? '',
                                    ),
                                  ),
                                  SizedBox(
                                    width: getResponsiveSize(context, 12),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        )
                      else
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isGeneratingAccounts
                                ? null
                                : _generateAccounts,
                            icon: _isGeneratingAccounts
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
                                _isGeneratingAccounts
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
                      SizedBox(height: getResponsiveSize(context, 16)),

                      // Fund Wallet and History buttons
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFce4323),
                          borderRadius: BorderRadius.circular(
                            getResponsiveSize(context, 12),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const WalletPage(),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      vertical: getResponsiveSize(context, 14),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.account_balance_wallet,
                                          color: Colors.white,
                                          size: getResponsiveSize(context, 18),
                                        ),
                                        SizedBox(
                                          width: getResponsiveSize(context, 8),
                                        ),
                                        Text(
                                          'Fund Wallet',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: getResponsiveSize(
                                              context,
                                              14,
                                            ),
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              width: 1,
                              height: getResponsiveSize(context, 40),
                              color: Colors.white24,
                            ),
                            Expanded(
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const TransactionsPage(),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      vertical: getResponsiveSize(context, 14),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.history,
                                          color: Colors.white,
                                          size: getResponsiveSize(context, 18),
                                        ),
                                        SizedBox(
                                          width: getResponsiveSize(context, 8),
                                        ),
                                        Text(
                                          'History',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: getResponsiveSize(
                                              context,
                                              14,
                                            ),
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: getResponsiveSize(context, 20)),

                      // Features Grid
                      Text(
                        'Features',
                        style: TextStyle(
                          fontSize: getResponsiveSize(context, 16),
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      SizedBox(height: getResponsiveSize(context, 12)),

                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 3,
                        mainAxisSpacing: getResponsiveSize(context, 10),
                        crossAxisSpacing: getResponsiveSize(context, 10),
                        childAspectRatio: 1.0,
                        children: [
                          _buildFeatureButton(
                            'Data Bundle',
                            Icons.signal_cellular_alt,
                            const Color(0xFFce4323),
                            () => _pushAndRefresh(const DataPage()),
                          ),
                          _buildFeatureButton(
                            'Daily Data',
                            Icons.calendar_today,
                            const Color(0xFFce4323),
                            () => _pushAndRefresh(const DailyDataPage()),
                          ),
                          _buildFeatureButton(
                            'Airtime',
                            Icons.phone_iphone,
                            const Color(0xFFce4323),
                            () => _pushAndRefresh(const AirtimePage()),
                          ),
                          _buildFeatureButton(
                            'Electricity',
                            Icons.bolt,
                            const Color(0xFFce4323),
                            () => _pushAndRefresh(const ElectricityPage()),
                          ),
                          _buildFeatureButton(
                            'Refer & Earn',
                            Icons.card_giftcard,
                            const Color(0xFFce4323),
                            () => _pushAndRefresh(const InvitePage()),
                          ),
                          _buildFeatureButton(
                            'Cable',
                            Icons.live_tv,
                            const Color(0xFFce4323),
                            () => _pushAndRefresh(const CablePage()),
                          ),
                          _buildFeatureButton(
                            'Exam',
                            Icons.assignment,
                            const Color(0xFFce4323),
                            () => _pushAndRefresh(const ExamPinPage()),
                          ),
                          _buildFeatureButton(
                            'Data Card',
                            Icons.credit_card,
                            const Color(0xFFce4323),
                            () => _pushAndRefresh(const DatapinPage()),
                          ),
                          _buildFeatureButton(
                            'Recharge Card',
                            Icons.card_membership,
                            const Color(0xFFce4323),
                            () => _pushAndRefresh(const CardPinPage()),
                          ),
                          _buildFeatureButton(
                            'Past Q',
                            Icons.help_outline,
                            const Color(0xFFce4323),
                            () => _pushAndRefresh(const PastQuestionsPage()),
                          ),
                          _buildFeatureButton(
                            'Welcome Bonus',
                            Icons.card_giftcard,
                            const Color(0xFFce4323),
                            () => _pushAndRefresh(const WelcomeBonusPage()),
                          ),
                          _buildFeatureButton(
                            'Spin & Win',
                            Icons.casino,
                            const Color(0xFFce4323),
                            () => _pushAndRefresh(const SpinAndWinPage()),
                          ),
                        ],
                      ),
                      SizedBox(height: getResponsiveSize(context, 16)),

                      // Horizontally scrollable banners
                      SizedBox(
                        height: getResponsiveSize(context, 150),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: EdgeInsets.symmetric(
                            horizontal: getResponsiveSize(context, 8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Banner 1
                              SizedBox(
                                width: MediaQuery.of(context).size.width * 0.85,
                                child: Container(
                                  height: getResponsiveSize(context, 200),
                                  margin: EdgeInsets.only(
                                    right: getResponsiveSize(context, 12),
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                      getResponsiveSize(context, 12),
                                    ),
                                    image: const DecorationImage(
                                      image: AssetImage(
                                        'assets/images/banner2.png',
                                      ),
                                      fit: BoxFit.cover,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.1),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Stack(
                                    children: [
                                      Positioned(
                                        left: getResponsiveSize(context, 12),
                                        top: getResponsiveSize(context, 12),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '',
                                              style: TextStyle(
                                                fontSize: getResponsiveSize(
                                                  context,
                                                  11,
                                                ),
                                                color: Colors.white70,
                                                fontWeight: FontWeight.w400,
                                              ),
                                            ),
                                            Text(
                                              '',
                                              style: TextStyle(
                                                fontSize: getResponsiveSize(
                                                  context,
                                                  20,
                                                ),
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            SizedBox(
                                              height: getResponsiveSize(
                                                context,
                                                2,
                                              ),
                                            ),
                                            Text(
                                              '',
                                              style: TextStyle(
                                                fontSize: getResponsiveSize(
                                                  context,
                                                  9,
                                                ),
                                                color: Colors.white60,
                                              ),
                                            ),
                                            SizedBox(
                                              height: getResponsiveSize(
                                                context,
                                                6,
                                              ),
                                            ),
                                            Container(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: getResponsiveSize(
                                                  context,
                                                  10,
                                                ),
                                                vertical: getResponsiveSize(
                                                  context,
                                                  4,
                                                ),
                                              ),
                                              // decoration: BoxDecoration(
                                              //   color: const Color(0xFFFF6B35),
                                              //   borderRadius:
                                              //       BorderRadius.circular(
                                              //         getResponsiveSize(
                                              //           context,
                                              //           4,
                                              //         ),
                                              //       ),
                                              // ),
                                              child: Text(
                                                '',
                                                style: TextStyle(
                                                  fontSize: getResponsiveSize(
                                                    context,
                                                    10,
                                                  ),
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
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
                              // Banner 2
                              SizedBox(
                                width: MediaQuery.of(context).size.width * 0.85,
                                child: Container(
                                  height: getResponsiveSize(context, 200),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                      getResponsiveSize(context, 12),
                                    ),
                                    image: const DecorationImage(
                                      image: AssetImage(
                                        'assets/images/banner1.png',
                                      ),
                                      fit: BoxFit.cover,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.1),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Stack(
                                    children: [
                                      Positioned(
                                        left: getResponsiveSize(context, 12),
                                        top: getResponsiveSize(context, 12),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '',
                                              style: TextStyle(
                                                fontSize: getResponsiveSize(
                                                  context,
                                                  11,
                                                ),
                                                color: Colors.white70,
                                                fontWeight: FontWeight.w400,
                                              ),
                                            ),
                                            Text(
                                              '',
                                              style: TextStyle(
                                                fontSize: getResponsiveSize(
                                                  context,
                                                  20,
                                                ),
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            SizedBox(
                                              height: getResponsiveSize(
                                                context,
                                                2,
                                              ),
                                            ),
                                            Text(
                                              '',
                                              style: TextStyle(
                                                fontSize: getResponsiveSize(
                                                  context,
                                                  9,
                                                ),
                                                color: Colors.white60,
                                              ),
                                            ),
                                            SizedBox(
                                              height: getResponsiveSize(
                                                context,
                                                6,
                                              ),
                                            ),
                                            Container(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: getResponsiveSize(
                                                  context,
                                                  10,
                                                ),
                                                vertical: getResponsiveSize(
                                                  context,
                                                  4,
                                                ),
                                              ),
                                              // decoration: BoxDecoration(
                                              //   color: const Color(0xFFFF6B35),
                                              //   borderRadius:
                                              //       BorderRadius.circular(
                                              //         getResponsiveSize(
                                              //           context,
                                              //           4,
                                              //         ),
                                              //       ),
                                              // ),
                                              child: Text(
                                                '',
                                                style: TextStyle(
                                                  fontSize: getResponsiveSize(
                                                    context,
                                                    10,
                                                  ),
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
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
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: getResponsiveSize(context, 20)),
                    ],
                  ),
                ),
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
              currentIndex: _selectedIndex,
              onTap: (index) async {
                if (index == _selectedIndex) {
                  // If same tab is tapped, do nothing
                  return;
                } else {
                  // Update index first
                  setState(() => _selectedIndex = index);

                  switch (index) {
                    case 0:
                      // Home - do nothing, already on home
                      break;
                    case 1:
                      // Wallet (use named route)
                      await Navigator.pushNamed(context, '/wallet').then((_) {
                        if (mounted) setState(() => _selectedIndex = 1);
                      });
                      break;
                    case 2:
                      // Profile (use named route)
                      await Navigator.pushNamed(context, '/account').then((_) {
                        if (mounted) {
                          setState(() => _selectedIndex = 2);
                          _loadProfilePhoto();
                        }
                      });
                      break;
                  }
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
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w500,
              ),
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
      ),
    );
  }

  Widget _buildFeatureButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(getResponsiveSize(context, 12)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFce4323).withOpacity(0.15),
              blurRadius: 20,
              offset: const Offset(0, 8),
              spreadRadius: 4,
            ),
            BoxShadow(
              color: const Color(0xFFce4323).withOpacity(0.10),
              blurRadius: 12,
              offset: const Offset(0, 4),
              spreadRadius: 2,
            ),
            BoxShadow(
              color: const Color(0xFFce4323).withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: getResponsiveSize(context, 48),
              height: getResponsiveSize(context, 48),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.15),
              ),
              child: Icon(
                icon,
                color: color,
                size: getResponsiveSize(context, 28),
              ),
            ),
            SizedBox(height: getResponsiveSize(context, 8)),
            Text(
              label,
              style: TextStyle(
                fontSize: getResponsiveSize(context, 11),
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingMenuItem(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: getResponsiveSize(context, 16),
            vertical: getResponsiveSize(context, 12),
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: getResponsiveSize(context, 20)),
              SizedBox(width: getResponsiveSize(context, 8)),
              Text(
                label,
                style: TextStyle(
                  fontSize: getResponsiveSize(context, 12),
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
