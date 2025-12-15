import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/spin_reward.dart';
import '../models/spin_win.dart';

class SpinCooldownException implements Exception {
  final String message;
  final int? secondsUntilNextSpin;

  SpinCooldownException(this.message, {this.secondsUntilNextSpin});

  @override
  String toString() =>
      'SpinCooldownException: $message (secondsUntilNextSpin=$secondsUntilNextSpin)';
}

class SpinCooldownStatus {
  final bool canSpinNow;
  final DateTime? lastSpinTime;
  final DateTime? nextSpinAvailable;

  SpinCooldownStatus({
    required this.canSpinNow,
    this.lastSpinTime,
    this.nextSpinAvailable,
  });
}

class SpinService {
  static const String baseUrl = 'https://api.mkdata.com.ng';
  final http.Client _client = http.Client();
  final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();

  Future<String?> _getUserId() async {
    final prefs = await _prefs;
    return prefs.getString('user_id');
  }

  /// Fetch all active spin rewards with their weights
  Future<List<SpinReward>> getSpinRewards() async {
    try {
      final response = await _client
          .get(
            Uri.parse('$baseUrl/api/spin-rewards'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success' && data['data'] is List) {
          final rewards = (data['data'] as List)
              .map((r) => SpinReward.fromJson(r as Map<String, dynamic>))
              .where((r) => r.active) // Only active rewards
              .toList();
          return rewards;
        }
      }
      throw Exception('Failed to fetch spin rewards');
    } catch (e) {
      throw Exception('Error fetching spin rewards: $e');
    }
  }

  /// Perform a spin and get the result
  /// Returns the SpinWin record with the selected reward
  Future<SpinWin> performSpin() async {
    try {
      final userId = await _getUserId();
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final response = await _client
          .post(
            Uri.parse('$baseUrl/api/perform-spin'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'user_id': userId}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.body.trim().isEmpty) {
        throw Exception('Empty response from server');
      }
      final body = jsonDecode(response.body);
      if (response.statusCode == 200) {
        if (body['status'] == 'success' && body['data'] != null) {
          return SpinWin.fromJson(body['data'] as Map<String, dynamic>);
        }
        throw Exception(
          'Failed to perform spin: ${body['message'] ?? 'Unknown error'}',
        );
      }

      // Handle cooldown specifically if server responded with 429
      if (response.statusCode == 429) {
        final data = body is Map<String, dynamic> ? body['data'] ?? {} : {};
        final seconds = data != null && data['time_until_next_spin'] != null
            ? int.tryParse(data['time_until_next_spin'].toString())
            : null;
        throw SpinCooldownException(
          body['message'] ?? 'Cooldown active',
          secondsUntilNextSpin: seconds,
        );
      }

      throw Exception(
        'Failed to perform spin: ${body['message'] ?? 'Unknown error'}',
      );
    } catch (e) {
      // Pass through cooldown exceptions so callers can handle them specially
      if (e is SpinCooldownException) rethrow;
      throw Exception('Error performing spin: $e');
    }
  }

  /// Fetch full cooldown status (can_spin_now, last spin time, next available time)
  Future<SpinCooldownStatus?> getSpinCooldownStatus() async {
    try {
      final userId = await _getUserId();
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final response = await _client
          .get(
            Uri.parse('$baseUrl/api/last-spin-time?user_id=$userId'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['status'] == 'success' && body['data'] != null) {
          final data = body['data'];
          final lastSpin = data['last_spin_time'];
          final next = data['next_spin_available'];
          return SpinCooldownStatus(
            canSpinNow: data['can_spin_now'] == true,
            lastSpinTime: lastSpin != null
                ? DateTime.parse(lastSpin.toString())
                : null,
            nextSpinAvailable: next != null
                ? DateTime.parse(next.toString())
                : null,
          );
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Fetch spin history for the current user
  Future<List<SpinWin>> getSpinHistory() async {
    try {
      final userId = await _getUserId();
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final response = await _client
          .get(
            Uri.parse('$baseUrl/api/spin-history?user_id=$userId'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success' && data['data'] is List) {
          final wins = (data['data'] as List)
              .map((w) => SpinWin.fromJson(w as Map<String, dynamic>))
              .toList();
          // Sort by spin_at descending (newest first)
          wins.sort((a, b) => b.spinAt.compareTo(a.spinAt));
          return wins;
        }
      }
      return []; // Return empty list if no history
    } catch (e) {
      return [];
    }
  }

  /// Claim a pending spin reward
  /// Used when user wants to claim a pending reward (deliver airtime/data)
  Future<bool> claimSpinReward(int spinWinId) async {
    return claimSpinRewardWithDelivery(spinWinId);
  }

  /// Claim a spin reward and optionally provide delivery details (phone/network)
  Future<bool> claimSpinRewardWithDelivery(
    int spinWinId, {
    String? phone,
    int? networkId,
  }) async {
    try {
      final userId = await _getUserId();
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final body = {'id': spinWinId, 'user_id': userId};
      if (phone != null) body['phone'] = phone;
      if (networkId != null) body['network'] = networkId;

      final response = await _client
          .post(
            Uri.parse('$baseUrl/api/claim-spin-reward'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['status'] == 'success';
      }
      return false;
    } catch (e) {
      throw Exception('Error claiming reward: $e');
    }
  }

  /// Fetch available networks for delivery (id and name)
  Future<List<Map<String, dynamic>>> getNetworks() async {
    try {
      final response = await _client
          .get(
            Uri.parse('$baseUrl/api/networks'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success' && data['data'] is List) {
          return List<Map<String, dynamic>>.from(data['data']);
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Get pending spin rewards for the current user
  Future<List<SpinWin>> getPendingSpinRewards() async {
    try {
      final userId = await _getUserId();
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final response = await _client
          .get(
            Uri.parse('$baseUrl/api/pending-spin-rewards?user_id=$userId'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success' && data['data'] is List) {
          return (data['data'] as List)
              .map((w) => SpinWin.fromJson(w as Map<String, dynamic>))
              .toList();
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Get last spin time for the user to determine cooldown
  Future<DateTime?> getLastSpinTime() async {
    try {
      final userId = await _getUserId();
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final response = await _client
          .get(
            Uri.parse('$baseUrl/api/last-spin-time?user_id=$userId'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success' && data['data'] != null) {
          final lastSpinTime = data['data']['last_spin_time'];
          if (lastSpinTime != null) {
            return DateTime.parse(lastSpinTime.toString());
          }
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
