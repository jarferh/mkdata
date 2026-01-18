import '../models/user_model.dart';
import 'api_service.dart';
import 'firebase_service.dart';

class AuthService {
  final ApiService _apiService = ApiService();
  final FirebaseService _firebaseService = FirebaseService();

  Future<User> login(
    String email,
    String password, {
    String? fcmToken,
    String? platform,
  }) async {
    try {
      // Optionally include fcm_token if present in apiService headers (or passed via extra)
      final payload = {'email': email, 'password': password};
      if (fcmToken != null && fcmToken.isNotEmpty) {
        payload['fcm_token'] = fcmToken;
      }
      if (platform != null && platform.isNotEmpty) {
        payload['platform'] = platform;
      }

      final response = await _apiService.post('auth/login.php', payload);

      if (response['message'] == 'Login successful.') {
        await _apiService.saveUserData(response);
        final user = User.fromJson(response);

        // After successful login, register device token with backend
        final userId = response['id']?.toString() ?? '';
        if (userId.isNotEmpty) {
          await _firebaseService.sendTokenToBackend(
            userId: userId,
            deviceType: platform ?? 'android',
          );
        }

        return user;
      } else {
        throw Exception(response['message']);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> register({
    required String fullname,
    required String email,
    required String mobile,
    required String password,
    String? referralCode,
    String? fcmToken,
    String? platform,
  }) async {
    try {
      final payload = {
        'fullname': fullname,
        'email': email,
        'mobile': mobile,
        'password': password,
        'referral_code': referralCode,
      };
      if (fcmToken != null && fcmToken.isNotEmpty) {
        payload['fcm_token'] = fcmToken;
      }
      if (platform != null && platform.isNotEmpty) {
        payload['platform'] = platform;
      }

      final response = await _apiService.post('auth/register.php', payload);

      if (response['message'] == 'User was created.') {
        // After successful registration, attempt to register device token
        // Note: We won't have user ID yet, so this is best-effort
        // The token will be registered properly when user logs in
        return true;
      }

      // On failure, surface the server-provided message so UI can display it
      throw Exception(response['message'] ?? 'Registration failed');
    } catch (e) {
      rethrow;
    }
  }

  Future<void> forgotPassword(String email) async {
    try {
      final response = await _apiService.post(
        'auth/request_password_reset.php',
        {'email': email},
      );

      // Debug/log the response so timeouts or unexpected shapes are visible
      print('[AuthService] forgotPassword response: $response');

      // Accept different response shapes: prefer top-level 'success' boolean,
      // fall back to 'status' == 'success', or presence of a message.
      final bool ok =
          (response['success'] == true) || (response['status'] == 'success');

      if (ok) return;

      throw Exception(response['message'] ?? 'Failed to send reset email');
    } catch (e) {
      print('[AuthService] forgotPassword error: $e');
      rethrow;
    }
  }

  Future<bool> resetPassword(
    String token,
    String password,
    String confirmPassword,
  ) async {
    try {
      final response = await _apiService.post('auth/reset_password.php', {
        'token': token,
        'password': password,
        'confirm_password': confirmPassword,
      });

      return response['message'] == 'Password was reset successfully.';
    } catch (e) {
      rethrow;
    }
  }

  Future<void> logout() async {
    // Clear local storage/session
    // Since our API doesn't have a logout endpoint
    await _apiService.clearAuth();
  }
}
