import '../services/api_service.dart';
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
  final ApiService _api = ApiService();

  Future<String?> _getUserId() async {
    return await _api.getUserId();
  }

  /// Fetch all active spin rewards with their weights
  Future<List<SpinReward>> getSpinRewards() async {
    try {
      final resp = await _api.get('spin-rewards');
      if (resp['status'] == 'success' && resp['data'] is List) {
        final rewards = (resp['data'] as List)
            .map((r) => SpinReward.fromJson(r as Map<String, dynamic>))
            .where((r) => r.active)
            .toList();
        return rewards;
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

      final resp = await _api.post('perform-spin', {'user_id': userId});

      if (resp['status'] == 'success' && resp['data'] != null) {
        return SpinWin.fromJson(resp['data'] as Map<String, dynamic>);
      }

      // If server indicates cooldown via data field
      final data = resp['data'];
      if (data != null && data is Map && data['time_until_next_spin'] != null) {
        final seconds = int.tryParse(data['time_until_next_spin'].toString());
        throw SpinCooldownException(
          resp['message'] ?? 'Cooldown active',
          secondsUntilNextSpin: seconds,
        );
      }

      throw Exception('Failed to perform spin: ${resp['message'] ?? resp}');
    } catch (e) {
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

      final resp = await _api.get('last-spin-time?user_id=$userId');
      if (resp['status'] == 'success' && resp['data'] != null) {
        final data = resp['data'];
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

      final resp = await _api.get('spin-history?user_id=$userId');
      if (resp['status'] == 'success' && resp['data'] is List) {
        final wins = (resp['data'] as List)
            .map((w) => SpinWin.fromJson(w as Map<String, dynamic>))
            .toList();
        // Sort by spin_at descending (newest first)
        wins.sort((a, b) => b.spinAt.compareTo(a.spinAt));
        return wins;
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

      final resp = await _api.post('claim-spin-reward', body);

      return resp['status'] == 'success';
    } catch (e) {
      throw Exception('Error claiming reward: $e');
    }
  }

  /// Fetch available networks for delivery (id and name)
  Future<List<Map<String, dynamic>>> getNetworks() async {
    try {
      final resp = await _api.get('networks');
      if (resp['status'] == 'success' && resp['data'] is List) {
        return List<Map<String, dynamic>>.from(resp['data']);
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

      final resp = await _api.get('pending-spin-rewards?user_id=$userId');
      if (resp['status'] == 'success' && resp['data'] is List) {
        return (resp['data'] as List)
            .map((w) => SpinWin.fromJson(w as Map<String, dynamic>))
            .toList();
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

      final resp = await _api.get('last-spin-time?user_id=$userId');
      if (resp['status'] == 'success' && resp['data'] != null) {
        final lastSpinTime = resp['data']['last_spin_time'];
        if (lastSpinTime != null) {
          return DateTime.parse(lastSpinTime.toString());
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
