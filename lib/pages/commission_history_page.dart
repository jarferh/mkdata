import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/api_service.dart';

class CommissionHistoryPage extends StatefulWidget {
  const CommissionHistoryPage({super.key});

  @override
  State<CommissionHistoryPage> createState() => _CommissionHistoryPageState();
}

class _CommissionHistoryPageState extends State<CommissionHistoryPage> {
  List<dynamic> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCommissions();
  }

  Future<void> _loadCommissions() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataStr = prefs.getString('user_data');
      String? userId;
      if (userDataStr != null) {
        final data = json.decode(userDataStr);
        userId = (data['sId'] ?? data['userid'] ?? data['id'])?.toString();
      }

      if (userId == null) {
        setState(() {
          _error = 'User not found. Please login again.';
          _loading = false;
        });
        return;
      }

      final api = ApiService();
      final decoded = await api.get('commissions?user_id=$userId');
      if (decoded == null ||
          decoded['statusCode'] != null && decoded['statusCode'] != 200) {
        setState(() {
          _error = decoded is Map && decoded['message'] != null
              ? decoded['message'].toString()
              : 'Failed to load commission history';
          _loading = false;
        });
        return;
      }
      List<dynamic> list = [];

      if (decoded is Map && decoded['commissions'] != null) {
        list = decoded['commissions'] as List<dynamic>;
      } else if (decoded is List) {
        list = decoded as List<dynamic>;
      } else if (decoded is Map && decoded['data'] != null) {
        list = decoded['data'] as List<dynamic>;
      } else {
        // try to interpret the whole body as single item array
        list = [];
      }

      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load commission history';
        _loading = false;
      });
    }
  }

  String _formatAmount(dynamic v) {
    try {
      final n = double.parse(v.toString());
      final parts = n
          .toStringAsFixed(n.truncateToDouble() == n ? 0 : 2)
          .split('.');
      final intPart = parts[0];
      final buf = StringBuffer();
      for (int i = 0; i < intPart.length; i++) {
        final pos = intPart.length - i;
        buf.write(intPart[i]);
        if (pos > 1 && pos % 3 == 1) buf.write(',');
      }
      if (parts.length > 1) return '₦${buf.toString()}.${parts[1]}';
      return '₦${buf.toString()}';
    } catch (_) {
      return '₦${v?.toString() ?? '0'}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Commission History',
          style: TextStyle(color: Colors.black),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadCommissions,
        child: _loading
            ? const Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Loading commission history...',
                      style: TextStyle(color: Color(0xFF36474F)),
                    ),
                    SizedBox(width: 12),
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Color(0xFF36474F),
                      ),
                    ),
                  ],
                ),
              )
            : _error != null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 80),
                  Center(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: ElevatedButton(
                      onPressed: _loadCommissions,
                      child: const Text('Retry'),
                    ),
                  ),
                ],
              )
            : _items.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 80),
                  Center(child: Text('No commission history yet')),
                ],
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                itemCount: _items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  final it = _items[i];
                  final amount =
                      it['amount'] ??
                      it['commission'] ??
                      it['amt'] ??
                      it['value'] ??
                      '0';
                  final desc =
                      it['description'] ??
                      it['service'] ??
                      it['note'] ??
                      'Commission';
                  final date =
                      it['date'] ?? it['created_at'] ?? it['created'] ?? '';
                  return Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      leading: CircleAvatar(
                        radius: 24,
                        backgroundColor: Colors.green.shade50,
                        child: Text(
                          _formatAmount(amount).replaceAll('₦', ''),
                          style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      title: Text(
                        desc,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(date.toString()),
                      trailing: Text(
                        _formatAmount(amount),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
