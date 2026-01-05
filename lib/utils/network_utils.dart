import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

/// Utility helpers for network-related user messaging.
String getFriendlyNetworkErrorMessage(Object e) {
  if (e is TimeoutException) {
    return 'Request timed out. Please check your internet connection and try again.';
  }
  if (e is SocketException) {
    return 'No internet connection. Please check your network settings and try again.';
  }
  final msg = e.toString();
  // Strip common verbose prefixes and sensitive internal detail
  String s = msg.replaceAll('Exception: ', '');
  s = s.replaceAll('Failed to make POST request: ', '');
  s = s.replaceAll('Login failed: ', '');
  // Trim long messages to a friendly length
  if (s.length > 140) {
    s = '${s.substring(0, 137)}...';
  }
  // If the resulting message is empty or too technical, fall back to a generic message
  final lower = s.trim().toLowerCase();
  if (lower.isEmpty ||
      lower.contains('stacktrace') ||
      lower.contains('sqlstate') ||
      lower.contains('{"error"')) {
    return 'An error occurred. Please try again.';
  }
  return s;
}

void showNetworkErrorSnackBar(
  BuildContext context,
  Object e, {
  double fontSize = 14,
}) {
  final message = getFriendlyNetworkErrorMessage(e);
  if (!context.mounted) return;
  try {
    final snack = SnackBar(
      content: Text(
        message,
        style: TextStyle(fontSize: fontSize, color: Colors.white),
      ),
      backgroundColor: Colors.orange.shade800,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      duration: const Duration(seconds: 4),
    );
    ScaffoldMessenger.of(context).showSnackBar(snack);
  } catch (err) {
    // If showing a floating SnackBar fails (rare on some layouts), fall back
    // to a less intrusive fixed SnackBar to avoid crashing the app.
    try {
      final fallback = SnackBar(
        content: Text(
          message,
          style: TextStyle(fontSize: fontSize, color: Colors.white),
        ),
        backgroundColor: Colors.orange.shade800,
        behavior: SnackBarBehavior.fixed,
        duration: const Duration(seconds: 4),
      );
      ScaffoldMessenger.of(context).showSnackBar(fallback);
    } catch (_) {
      // As a last resort, ignore the snackbar to avoid unhandled exceptions
      // and optionally log to console for debugging.
      // ignore: avoid_print
      print('Failed to show SnackBar: $err');
    }
  }
}
