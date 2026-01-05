import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../utils/network_utils.dart';

class ManualRequest {
  final int id;
  final String account;
  final double amount;
  final int status;
  final DateTime date;

  ManualRequest({
    required this.id,
    required this.account,
    required this.amount,
    required this.status,
    required this.date,
  });

  factory ManualRequest.fromJson(Map<String, dynamic> json) {
    return ManualRequest(
      id: int.parse(json['tId'].toString()),
      account: json['account'] ?? '',
      amount: double.tryParse(json['amount'].toString()) ?? 0.0,
      status: int.parse(json['status'].toString()),
      date: DateTime.parse(json['dPosted']),
    );
  }

  String get statusText {
    switch (status) {
      case 0:
        return 'Pending';
      case 1:
        return 'Approved';
      case 2:
        return 'Rejected';
      default:
        return 'Unknown';
    }
  }
}

class ManualRequestsPage extends StatefulWidget {
  const ManualRequestsPage({super.key});

  @override
  State<ManualRequestsPage> createState() => _ManualRequestsPageState();
}

class _ManualRequestsPageState extends State<ManualRequestsPage> {
  bool _loading = true;
  String? _error;
  List<ManualRequest> _requests = [];

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final userId = await ApiService().getUserId();
      if (userId == null) throw Exception('User not logged in');

      // If the API prefers sId (subscriber id) include it as well. We already
      // have userId; use it for both params to be safe when the backing API
      // expects the subscriber id field named 'sId'.
      final api = ApiService();
      final data = await api.get('manual-payments?user_id=$userId&sId=$userId');
      if (data['status'] == 'success') {
        final list = List<Map<String, dynamic>>.from(data['data'] ?? []);
        setState(() {
          _requests = list.map((j) => ManualRequest.fromJson(j)).toList();
        });
      } else {
        throw Exception(data['message'] ?? 'Failed to fetch requests');
      }
    } catch (e) {
      if (mounted) showNetworkErrorSnackBar(context, e);
      setState(() {
        _error = getFriendlyNetworkErrorMessage(e);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _statusColor(int status) {
    switch (status) {
      case 0:
        return Colors.orange.shade800;
      case 1:
        return Colors.green;
      case 2:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Manual requests',
          style: TextStyle(color: Colors.black),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Loading manual requests...',
                    style: TextStyle(color: Color(0xFF36474F)),
                  ),
                  SizedBox(width: 12),
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Color(0xFF36474F)),
                  ),
                ],
              ),
            )
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_error!, style: const TextStyle(color: Colors.orange)),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _loadRequests,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadRequests,
              child: _requests.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 80),
                        Center(child: Text('No manual payment requests found')),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _requests.length,
                      itemBuilder: (context, index) {
                        final r = _requests[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          child: ListTile(
                            title: Text(
                              '₦${r.amount.toStringAsFixed(2)} - ${r.account}',
                            ),
                            subtitle: Text(r.date.toLocal().toString()),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  r.statusText,
                                  style: TextStyle(
                                    color: _statusColor(r.status),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
