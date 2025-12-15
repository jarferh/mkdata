class SpinReward {
  final int id;
  final String code;
  final String name;
  final String type; // 'airtime', 'data', 'tryagain'
  final double? amount;
  final String? unit; // 'NGN', 'GB'
  final String? planId;
  final double weight; // percentage chance (0-100)
  final bool active;
  final DateTime createdAt;
  final DateTime updatedAt;

  SpinReward({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
    this.amount,
    this.unit,
    this.planId,
    required this.weight,
    required this.active,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SpinReward.fromJson(Map<String, dynamic> json) {
    return SpinReward(
      id: json['id'] is int ? json['id'] : int.parse(json['id'].toString()),
      code: json['code'] ?? '',
      name: json['name'] ?? '',
      type: json['type'] ?? 'airtime',
      amount: json['amount'] != null
          ? double.parse(json['amount'].toString())
          : null,
      unit: json['unit'],
      planId: json['plan_id'],
      weight: double.parse(json['weight'].toString()),
      active: json['active'] == 1 || json['active'] == true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString())
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'].toString())
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'code': code,
      'name': name,
      'type': type,
      'amount': amount,
      'unit': unit,
      'plan_id': planId,
      'weight': weight,
      'active': active,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
