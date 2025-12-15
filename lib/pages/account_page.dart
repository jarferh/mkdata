import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'delete_account_page.dart';
import 'contact_page.dart';
import 'change_transaction_pin_page.dart';
import 'edit_profile_page.dart';
import 'invite_page.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  Map<String, dynamic>? userData;
  String? profilePhotoPath;
  bool _isBiometricEnabled = true;

  @override
  void initState() {
    super.initState();
    loadUserData();
    _loadProfilePhoto();
    _loadBiometricSettings();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    loadUserData(); // Reload data when returning to this page
  }

  Future<void> loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataStr = prefs.getString('user_data');
      if (userDataStr != null) {
        final parsedData = json.decode(userDataStr);
        setState(() {
          userData = parsedData;
        });
      }
    } catch (e) {
      print('Error loading user data: $e');
    }
  }

  Future<void> _loadProfilePhoto() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final photoPath = prefs.getString('profile_photo_path');
      if (photoPath != null) {
        setState(() {
          profilePhotoPath = photoPath;
        });
      }
    } catch (e) {
      print('Error loading profile photo: $e');
    }
  }

  Future<void> _loadBiometricSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isEnabled = prefs.getBool('biometric_enabled') ?? true;
      setState(() {
        _isBiometricEnabled = isEnabled;
      });
    } catch (e) {
      print('Error loading biometric settings: $e');
    }
  }

  Future<void> _toggleBiometricEnabled(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('biometric_enabled', value);
      setState(() {
        _isBiometricEnabled = value;
      });
    } catch (e) {
      print('Error saving biometric settings: $e');
    }
  }

  void _showLogoutDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Close button
                Align(
                  alignment: Alignment.topRight,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(Icons.close, size: 24),
                  ),
                ),
                const SizedBox(height: 16),
                // X icon in circle
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.red, width: 3),
                  ),
                  child: const Center(
                    child: Icon(Icons.close, size: 48, color: Colors.red),
                  ),
                ),
                const SizedBox(height: 16),
                // Username
                Text(
                  userData?['sFname']?.toString().toUpperCase() ?? 'USER',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                // Question
                const Text(
                  'Do You Really Want to LogOut This Account?',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.black,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                // Buttons row
                Row(
                  children: [
                    // Stay button
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1DB679),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'stay',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Logout button
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.clear();
                          if (mounted && context.mounted) {
                            Navigator.of(context).pushNamedAndRemoveUntil(
                              '/login',
                              (route) => false,
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Logout',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Profile',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(profilePhotoPath),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.black),
            onPressed: () {},
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 24),
              // Profile Photo
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFce4323), width: 4),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(60),
                  child: profilePhotoPath != null
                      ? Image.file(
                          File(profilePhotoPath!),
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
                        ),
                ),
              ),
              const SizedBox(height: 20),
              // User Name
              Text(
                userData?['sFname']?.toString().toUpperCase() ?? 'USER',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 32),
              // Divider
              Divider(height: 1),
              // Menu Items
              _buildMenuItemWithIcon(
                icon: Icons.edit_outlined,
                label: 'Edit Profile',
                onTap: () async {
                  final updated = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const EditProfilePage(),
                    ),
                  );
                  if (updated == true) {
                    // Reload user data and profile photo
                    await loadUserData();
                    await _loadProfilePhoto();
                  }
                },
              ),
              _buildMenuItemWithIcon(
                icon: Icons.card_giftcard,
                label: 'Refer & Earn',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const InvitePage()),
                  );
                },
              ),
              _buildMenuItemWithIcon(
                icon: Icons.lock_outline,
                label: 'Change Transaction Pin',
                onTap: () async {
                  final changed = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ChangeTransactionPinPage(),
                    ),
                  );
                  if (changed == true) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Transaction PIN changed successfully'),
                      ),
                    );
                  }
                },
              ),
              _buildMenuItemWithIcon(
                icon: Icons.help_outline,
                label: 'Help Center',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ContactPage(),
                    ),
                  );
                },
              ),
              _buildMenuItemWithToggle(
                icon: Icons.fingerprint,
                label: 'Enable Biometric',
                value: _isBiometricEnabled,
                onChanged: _toggleBiometricEnabled,
              ),
              _buildMenuItemWithIcon(
                icon: Icons.delete_outline,
                label: 'Delete My mkdata account',
                isDestructive: true,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DeleteAccountPage(),
                    ),
                  );
                },
              ),
              _buildMenuItemWithIcon(
                icon: Icons.exit_to_app,
                label: 'Logout',
                isDestructive: true,
                onTap: () async {
                  _showLogoutDialog();
                },
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
            currentIndex: 2,
            onTap: (index) {
              if (index == 0) {
                // Replace account with dashboard directly
                Navigator.pushReplacementNamed(context, '/dashboard');
              } else if (index == 1) {
                // Navigate to wallet while ensuring dashboard remains in stack
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/wallet',
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

  double getResponsiveSize(BuildContext context, double baseSize) {
    double screenWidth = MediaQuery.of(context).size.width;
    double scaleFactor = screenWidth / 375; // Base width (iPhone SE)
    return baseSize * scaleFactor.clamp(0.7, 1.3); // Limit scaling
  }

  Widget _buildMenuItemWithIcon({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return Material(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Icon(
                icon,
                size: 24,
                color: isDestructive ? Colors.red : Colors.grey[600],
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: isDestructive ? Colors.red : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItemWithToggle({
    required IconData icon,
    required String label,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return Material(
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Icon(icon, size: 24, color: Colors.grey[600]),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                activeColor: const Color(0xFFce4323),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
