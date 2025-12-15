import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _imagePicker = ImagePicker();

  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _currentPasswordController;
  late TextEditingController _newPasswordController;
  late TextEditingController _confirmPasswordController;

  String? _selectedImagePath;
  String? _profilePhotoPath;
  Map<String, dynamic>? _userData;
  bool _isLoadingImage = false;
  bool _isSubmitting = false;
  bool _showCurrentPassword = false;
  bool _showNewPassword = false;
  bool _showConfirmPassword = false;

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController();
    _lastNameController = TextEditingController();
    _currentPasswordController = TextEditingController();
    _newPasswordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
    _loadUserData();
    _loadProfilePhoto();
  }

  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataStr = prefs.getString('user_data');
      if (userDataStr != null) {
        final parsedData = json.decode(userDataStr);
        setState(() {
          _userData = parsedData;
          _firstNameController.text = _userData?['sFname']?.toString() ?? '';
          _lastNameController.text = _userData?['sLname']?.toString() ?? '';
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
          _profilePhotoPath = photoPath;
        });
      }
    } catch (e) {
      print('Error loading profile photo: $e');
    }
  }

  Future<void> _pickImage() async {
    try {
      setState(() => _isLoadingImage = true);

      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1024,
        maxHeight: 1024,
      );

      if (pickedFile != null) {
        setState(() {
          _selectedImagePath = pickedFile.path;
        });
      }
    } catch (e) {
      print('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error picking image: $e')));
      }
    } finally {
      setState(() => _isLoadingImage = false);
    }
  }

  Future<void> _submitChanges() async {
    try {
      setState(() => _isSubmitting = true);

      final prefs = await SharedPreferences.getInstance();
      String? userId = prefs.getString('user_id');

      // Check if only image is being updated
      bool isFirstNameChanged =
          _firstNameController.text.trim() !=
          (_userData?['sFname']?.toString() ?? '');
      bool isLastNameChanged =
          _lastNameController.text.trim() !=
          (_userData?['sLname']?.toString() ?? '');
      bool isPasswordChanged = _newPasswordController.text.isNotEmpty;
      bool isImageChanged = _selectedImagePath != null;

      // If only image is changed, just save it locally without API call
      if (isImageChanged &&
          !isFirstNameChanged &&
          !isLastNameChanged &&
          !isPasswordChanged) {
        await prefs.setString('profile_photo_path', _selectedImagePath!);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile photo updated successfully'),
              duration: Duration(seconds: 2),
            ),
          );

          // Navigate back after short delay
          await Future.delayed(const Duration(milliseconds: 500));
          Navigator.of(context).pop(true);
        }
        return;
      }

      // Validate form for other updates
      if (!_formKey.currentState!.validate()) return;

      // Prepare update data
      final updateData = {
        'user_id': userId,
        'fname': _firstNameController.text.trim(),
        'lname': _lastNameController.text.trim(),
      };

      // Add password if provided
      if (_newPasswordController.text.isNotEmpty) {
        updateData['current_password'] = _currentPasswordController.text;
        updateData['new_password'] = _newPasswordController.text;
      }

      // Send update request to API
      final response = await http.post(
        Uri.parse('https://api.mkdata.com.ng/api/update-profile'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(updateData),
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        if (responseData['status'] == 'success') {
          // Update cached user data
          final updated = Map<String, dynamic>.from(_userData ?? {});
          updated['sFname'] = _firstNameController.text.trim();
          updated['sLname'] = _lastNameController.text.trim();

          await prefs.setString('user_data', json.encode(updated));

          // Update profile photo if selected
          if (_selectedImagePath != null) {
            await prefs.setString('profile_photo_path', _selectedImagePath!);
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Profile updated successfully'),
                duration: Duration(seconds: 2),
              ),
            );

            // Navigate back after short delay
            await Future.delayed(const Duration(milliseconds: 500));
            Navigator.of(context).pop(true);
          }
        } else {
          _showErrorDialog(
            responseData['message'] ??
                'Failed to update profile. Please try again.',
          );
        }
      } else {
        String errorMsg = 'Server error: ${response.statusCode}';
        try {
          final body = json.decode(response.body);
          if (body is Map && body['message'] != null) {
            errorMsg = body['message'].toString();
          }
        } catch (_) {}
        _showErrorDialog(errorMsg);
      }
    } catch (e) {
      _showErrorDialog('Error updating profile: ${e.toString()}');
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  void _showErrorDialog(String message) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  double getResponsiveSize(double baseSize) {
    double screenWidth = MediaQuery.of(context).size.width;
    double scaleFactor = screenWidth / 375;
    return baseSize * scaleFactor.clamp(0.7, 1.3);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Edit Profile',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(getResponsiveSize(16)),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Profile Photo Section
                SizedBox(height: getResponsiveSize(16)),
                Stack(
                  children: [
                    Container(
                      width: getResponsiveSize(120),
                      height: getResponsiveSize(120),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFce4323),
                          width: 4,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          getResponsiveSize(60),
                        ),
                        child: _selectedImagePath != null
                            ? Image.file(
                                File(_selectedImagePath!),
                                fit: BoxFit.cover,
                              )
                            : (_profilePhotoPath != null
                                  ? Image.file(
                                      File(_profilePhotoPath!),
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                            return Image.asset(
                                              'assets/images/avatar.png',
                                              fit: BoxFit.cover,
                                            );
                                          },
                                    )
                                  : Image.asset(
                                      'assets/images/avatar.png',
                                      fit: BoxFit.cover,
                                    )),
                      ),
                    ),
                    // Edit button overlay
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: _isLoadingImage ? null : _pickImage,
                        child: Container(
                          width: getResponsiveSize(40),
                          height: getResponsiveSize(40),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFce4323),
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Center(
                            child: _isLoadingImage
                                ? SizedBox(
                                    width: getResponsiveSize(20),
                                    height: getResponsiveSize(20),
                                    child: const CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : Icon(
                                    Icons.camera_alt,
                                    color: Colors.white,
                                    size: getResponsiveSize(20),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: getResponsiveSize(16)),

                // Photo info text
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: getResponsiveSize(12),
                    vertical: getResponsiveSize(8),
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(getResponsiveSize(8)),
                    border: Border.all(color: Colors.blue.shade200, width: 1),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.blue.shade600,
                        size: getResponsiveSize(16),
                      ),
                      SizedBox(width: getResponsiveSize(8)),
                      Expanded(
                        child: Text(
                          'Photo is saved locally and will be reset after logout',
                          style: TextStyle(
                            fontSize: getResponsiveSize(12),
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: getResponsiveSize(32)),

                // First Name Field
                TextFormField(
                  controller: _firstNameController,
                  decoration: InputDecoration(
                    labelText: 'First Name',
                    hintText: 'Enter your first name',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        getResponsiveSize(12),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        getResponsiveSize(12),
                      ),
                      borderSide: const BorderSide(
                        color: Color(0xFFce4323),
                        width: 2,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'First name is required';
                    }
                    return null;
                  },
                ),
                SizedBox(height: getResponsiveSize(16)),

                // Last Name Field
                TextFormField(
                  controller: _lastNameController,
                  decoration: InputDecoration(
                    labelText: 'Last Name',
                    hintText: 'Enter your last name',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        getResponsiveSize(12),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        getResponsiveSize(12),
                      ),
                      borderSide: const BorderSide(
                        color: Color(0xFFce4323),
                        width: 2,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Last name is required';
                    }
                    return null;
                  },
                ),
                SizedBox(height: getResponsiveSize(24)),

                // Divider with Text
                Row(
                  children: [
                    Expanded(child: Divider(height: 1)),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: getResponsiveSize(12),
                      ),
                      child: Text(
                        'Change Password (Optional)',
                        style: TextStyle(
                          fontSize: getResponsiveSize(13),
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(height: 1)),
                  ],
                ),
                SizedBox(height: getResponsiveSize(24)),

                // Current Password Field
                TextFormField(
                  controller: _currentPasswordController,
                  obscureText: !_showCurrentPassword,
                  decoration: InputDecoration(
                    labelText: 'Current Password',
                    hintText: 'Enter your current password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showCurrentPassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _showCurrentPassword = !_showCurrentPassword;
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        getResponsiveSize(12),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        getResponsiveSize(12),
                      ),
                      borderSide: const BorderSide(
                        color: Color(0xFFce4323),
                        width: 2,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: getResponsiveSize(16)),

                // New Password Field
                TextFormField(
                  controller: _newPasswordController,
                  obscureText: !_showNewPassword,
                  decoration: InputDecoration(
                    labelText: 'New Password',
                    hintText: 'Enter your new password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showNewPassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _showNewPassword = !_showNewPassword;
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        getResponsiveSize(12),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        getResponsiveSize(12),
                      ),
                      borderSide: const BorderSide(
                        color: Color(0xFFce4323),
                        width: 2,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (_newPasswordController.text.isNotEmpty &&
                        value!.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                SizedBox(height: getResponsiveSize(16)),

                // Confirm Password Field
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: !_showConfirmPassword,
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    hintText: 'Confirm your new password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showConfirmPassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _showConfirmPassword = !_showConfirmPassword;
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        getResponsiveSize(12),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        getResponsiveSize(12),
                      ),
                      borderSide: const BorderSide(
                        color: Color(0xFFce4323),
                        width: 2,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (_newPasswordController.text.isNotEmpty) {
                      if (value == null || value.isEmpty) {
                        return 'Please confirm your password';
                      }
                      if (value != _newPasswordController.text) {
                        return 'Passwords do not match';
                      }
                    }
                    return null;
                  },
                ),
                SizedBox(height: getResponsiveSize(32)),

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  height: getResponsiveSize(52),
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitChanges,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFce4323),
                      disabledBackgroundColor: const Color(
                        0xFFce4323,
                      ).withOpacity(0.6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          getResponsiveSize(12),
                        ),
                      ),
                      elevation: 2,
                    ),
                    child: _isSubmitting
                        ? SizedBox(
                            width: getResponsiveSize(24),
                            height: getResponsiveSize(24),
                            child: const CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            'Save Changes',
                            style: TextStyle(
                              fontSize: getResponsiveSize(16),
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
                SizedBox(height: getResponsiveSize(16)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}
