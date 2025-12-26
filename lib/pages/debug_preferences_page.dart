
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../utils/network_utils.dart';

class DebugPreferencesPage extends StatefulWidget {
  const DebugPreferencesPage({super.key});

  @override
  State<DebugPreferencesPage> createState() => _DebugPreferencesPageState();
}

class _DebugPreferencesPageState extends State<DebugPreferencesPage> {
  Map<String, dynamic> prefsData = {};
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadAllPreferences();
  }

  Future<void> loadAllPreferences() async {
    setState(() {
      isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      Map<String, dynamic> data = {};

      for (String key in keys) {
        var value = prefs.get(key);
        // Try to parse JSON strings
        if (value is String) {
          try {
            value = json.decode(value);
          } catch (e) {
            // Keep original string if not JSON
          }
        }
        data[key] = value;
      }

      setState(() {
        prefsData = data;
        isLoading = false;
      });
    } catch (e) {
      print('Error loading preferences: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> clearAllPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All preferences cleared'),
          backgroundColor: Colors.green,
        ),
      );
      await loadAllPreferences();
    } catch (e) {
      showNetworkErrorSnackBar(context, 'Error clearing preferences: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug: Stored Preferences'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: loadAllPreferences,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Clear All Preferences'),
                  content: const Text(
                    'Are you sure you want to clear all stored preferences? This cannot be undone.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('CANCEL'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        clearAllPreferences();
                      },
                      child: const Text('CLEAR'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : prefsData.isEmpty
          ? const Center(child: Text('No stored preferences found'))
          : ListView.builder(
              itemCount: prefsData.length,
              itemBuilder: (context, index) {
                final key = prefsData.keys.elementAt(index);
                final value = prefsData[key];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: ExpansionTile(
                    title: Text(
                      key,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Value:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              value is Map || value is List
                                  ? const JsonEncoder.withIndent(
                                      '  ',
                                    ).convert(value)
                                  : value.toString(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
