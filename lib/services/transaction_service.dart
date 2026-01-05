import 'dart:convert';
import '../models/transaction.dart';
import 'api_service.dart';

class TransactionService {
  static Future<List<Transaction>> getTransactions(String userId) async {
    try {
      final api = ApiService();
      final data = await api.get('transactions?user_id=$userId');
      if (data['status'] == 'success' && data['data'] != null) {
        return List<Transaction>.from(
          data['data'].map((x) => Transaction.fromJson(x)),
        );
      }
      throw Exception(data['message'] ?? 'Failed to load transactions');
    } catch (e) {
      throw Exception('Error loading transactions: $e');
    }
  }
}
