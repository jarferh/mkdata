import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'network_utils.dart';

class InternetChecker {
  /// Returns true if internet is available. Shows a SnackBar on [context] when offline.
  static Future<bool> ensureConnected(BuildContext context) async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        _showNoInternet(context);
        return false;
      }
      // lightweight probe
      final uri = Uri.parse('https://www.google.com/generate_204');
      final resp = await http.get(uri).timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200 || resp.statusCode == 204) return true;
      _showNoInternet(context);
      return false;
    } catch (e) {
      _showNoInternet(context);
      return false;
    }
  }

  static void _showNoInternet(BuildContext context) {
    if (!ModalRoute.of(context)!.isCurrent) return;
    // Use centralized network error presentation
    showNetworkErrorSnackBar(
      context,
      'No internet connection. Please check your network.',
    );
  }
}
