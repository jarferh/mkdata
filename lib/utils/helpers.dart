import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Timezone: GMT+1 (Africa/Lagos)
const String APP_TIMEZONE = 'Africa/Lagos';

class Helpers {
  static void showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  static String formatCurrency(double amount) {
    return '₦${amount.toStringAsFixed(2)}';
  }

  /// Format date to DD/MM/YYYY in GMT+1 timezone
  static String formatDate(DateTime date) {
    // Convert to GMT+1 if needed
    final gmtPlus1Date = date.toUtc().add(const Duration(hours: 1));
    return '${gmtPlus1Date.day}/${gmtPlus1Date.month}/${gmtPlus1Date.year}';
  }

  /// Format datetime with time in GMT+1 timezone
  static String formatDateTime(DateTime dateTime) {
    final gmtPlus1 = dateTime.toUtc().add(const Duration(hours: 1));
    return DateFormat('dd/MM/yyyy HH:mm:ss').format(gmtPlus1);
  }

  /// Get current time in GMT+1
  static DateTime nowGMT1() {
    return DateTime.now().toUtc().add(const Duration(hours: 1));
  }

  static bool isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  static bool isValidPhone(String phone) {
    return RegExp(r'^[0-9]{11}$').hasMatch(phone);
  }
}
