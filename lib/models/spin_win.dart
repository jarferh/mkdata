import 'dart:convert';

class SpinWin {
  final int id;
  final int userId;
  final int? rewardId;
  final String rewardType; // 'airtime', 'data', 'tryagain'
  final double? amount;
  final String? unit; // 'NGN', 'GB'
  final String? planId;
  final String status; // 'pending', 'delivered', 'claimed'
  final Map<String, dynamic>? meta;
  final DateTime spinAt;
  final DateTime? deliveredAt;

  SpinWin({
    required this.id,
    required this.userId,
    this.rewardId,
    required this.rewardType,
    this.amount,
    this.unit,
    this.planId,
    required this.status,
    this.meta,
    required this.spinAt,
    this.deliveredAt,
  });

  factory SpinWin.fromJson(Map<String, dynamic> json) {
    return SpinWin(
      id: json['id'] is int ? json['id'] : int.parse(json['id'].toString()),
      userId: json['user_id'] is int
          ? json['user_id']
          : int.parse(json['user_id'].toString()),
      rewardId: json['reward_id'] != null
          ? (json['reward_id'] is int
                ? json['reward_id']
                : int.parse(json['reward_id'].toString()))
          : null,
      rewardType: json['reward_type'] ?? 'airtime',
      amount: json['amount'] != null
          ? double.parse(json['amount'].toString())
          : null,
      unit: json['unit'],
      planId: json['plan_id'],
      status: json['status'] ?? 'pending',
      meta: json['meta'] is String
          ? (json['meta'].toString().isNotEmpty
                ? _parseJsonString(json['meta'])
                : null)
          : json['meta'] is Map
          ? Map<String, dynamic>.from(json['meta'])
          : null,
      spinAt: json['spin_at'] != null
          ? DateTime.parse(json['spin_at'].toString())
          : DateTime.now(),
      deliveredAt: json['delivered_at'] != null
          ? DateTime.parse(json['delivered_at'].toString())
          : null,
    );
  }

  static Map<String, dynamic>? _parseJsonString(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) return null;
    try {
      final decoded = jsonDecode(jsonString);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (e) {
      return null;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'reward_id': rewardId,
      'reward_type': rewardType,
      'amount': amount,
      'unit': unit,
      'plan_id': planId,
      'status': status,
      'meta': meta,
      'spin_at': spinAt.toIso8601String(),
      'delivered_at': deliveredAt?.toIso8601String(),
    };
  }

  String? getPhoneNumber() {
    return meta?['phone'] as String?;
  }

  String? getNetwork() {
    return meta?['network'] as String?;
  }

  String? getDeliveryStatus() {
    return meta?['delivery_status'] as String?;
  }
}
