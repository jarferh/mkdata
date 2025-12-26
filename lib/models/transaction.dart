class Transaction {
  final int id;
  final int userId;
  final String reference;
  final String serviceName;
  final String serviceDescription;
  final double amount;
  final int status;
  final double oldBalance;
  final double newBalance;
  final double profit;
  final DateTime date;
  final String? apiResponse;
  final String? apiResponseLog;

  Transaction({
    required this.id,
    required this.userId,
    required this.reference,
    required this.serviceName,
    required this.serviceDescription,
    required this.amount,
    required this.status,
    required this.oldBalance,
    required this.newBalance,
    required this.profit,
    required this.date,
    this.apiResponse,
    this.apiResponseLog,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: int.parse(json['tId'].toString()),
      userId: int.parse(json['sId'].toString()),
      reference: json['transref'],
      serviceName: json['servicename'],
      serviceDescription: json['servicedesc'],
      amount: double.parse(json['amount'].toString()),
      status: int.parse(json['status'].toString()),
      oldBalance: double.parse(json['oldbal'].toString()),
      newBalance: double.parse(json['newbal'].toString()),
      profit: double.parse(json['profit'].toString()),
      date: DateTime.parse(json['date']),
      apiResponse: json['api_response'],
      apiResponseLog: json['api_response_log'],
    );
  }

  String get statusText {
    switch (status) {
      case 1:
        return 'Success';
      case 0:
        return 'Failed';
      case 2:
        return 'Pending';
      default:
        return 'Unknown';
    }
  }

  String? get token {
    if (apiResponse == null || apiResponse!.isEmpty) return null;

    try {
      // Try to parse as JSON
      final jsonStr = apiResponse!.trim();
      if (jsonStr.startsWith('{')) {
        // It's already JSON
        final response = jsonStr;
        // Simple extraction without full JSON parsing to avoid dependencies
        // Look for "Token" field
        final tokenMatch = RegExp(
          r'"Token"\s*:\s*"([^"]*)"',
        ).firstMatch(response);
        if (tokenMatch != null) {
          return tokenMatch.group(1);
        }
        // Look for "token" field
        final tokenMatch2 = RegExp(
          r'"token"\s*:\s*"([^"]*)"',
        ).firstMatch(response);
        if (tokenMatch2 != null) {
          return tokenMatch2.group(1);
        }
        // Look for "purchased_code" field
        final codeMatch = RegExp(
          r'"purchased_code"\s*:\s*"([^"]*)"',
        ).firstMatch(response);
        if (codeMatch != null) {
          return codeMatch.group(1);
        }
      }
    } catch (e) {
      return null;
    }
    return null;
  }
}
