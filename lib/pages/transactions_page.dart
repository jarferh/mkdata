import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../utils/network_utils.dart';
import '../services/api_service.dart';
import './transaction_details_page.dart';

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
  final String token;

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
    required this.token,
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
      token: json['token'] ?? '',
    );
  }

  String get statusText {
    switch (status) {
      case 0:
        return 'Success';
      case 1:
        return 'Failed';
      case 2:
        return 'Failed';
      default:
        return 'Unknown';
    }
  }
}

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key});

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  List<Transaction> _transactions = [];
  bool _isLoading = true;
  String? _error;
  // Pagination / incremental loading fields
  final int _perPage = 10;
  List<Transaction> _bufferedRemaining =
      []; // used if the server returns the full list
  bool _hasMore = false;
  bool _isLoadingMore = false;
  bool _serverReturnedFull = false;

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  // Load the initial page (or refresh). Supports server-side pagination via
  // `limit` and `offset` query parameters. If the server ignores those and
  // returns the full dataset, we buffer the remaining items client-side and
  // reveal them on demand.
  Future<void> _loadTransactions({bool refresh = false}) async {
    try {
      if (refresh) {
        setState(() {
          _isLoading = true;
          _transactions = [];
          _bufferedRemaining = [];
          _hasMore = false;
          _serverReturnedFull = false;
        });
      } else {
        setState(() => _isLoading = true);
      }

      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');

      if (userId == null) {
        throw Exception('User not logged in');
      }

      final response = await http.get(
        Uri.parse(
          '${ApiService.baseUrl}/api/transactions?user_id=$userId&limit=$_perPage&offset=0',
        ),
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['status'] == 'success') {
          final List data = List<Map<String, dynamic>>.from(
            responseData['data'],
          );
          final fetched = data
              .map((json) => Transaction.fromJson(json))
              .toList();

          // If the server returned more than _perPage items on the initial
          // request it likely ignored pagination and returned the full list.
          if (fetched.length > _perPage) {
            setState(() {
              _transactions = fetched.take(_perPage).toList();
              _bufferedRemaining = fetched.skip(_perPage).toList();
              _hasMore = _bufferedRemaining.isNotEmpty;
              _serverReturnedFull = true;
            });
          } else if (fetched.length == _perPage) {
            // Could be paginated; assume there may be more on the server.
            setState(() {
              _transactions = fetched;
              _hasMore = true;
              _serverReturnedFull = false;
            });
          } else {
            setState(() {
              _transactions = fetched;
              _hasMore = false;
              _serverReturnedFull = false;
            });
          }
        } else {
          throw Exception(responseData['message']);
        }
      } else {
        throw Exception('Failed to load transactions');
      }
    } catch (e) {
      if (mounted) showNetworkErrorSnackBar(context, e);
      setState(() {
        _error = getFriendlyNetworkErrorMessage(e);
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Load the next page of transactions. If the server returned the full list
  // initially we reveal the next buffered items; otherwise we request the next
  // page from the server using offset.
  Future<void> _loadMoreTransactions() async {
    if (!_hasMore || _isLoadingMore) return;
    setState(() => _isLoadingMore = true);

    try {
      if (_serverReturnedFull) {
        // Reveal next batch from the buffered remaining items.
        final next = _bufferedRemaining.take(_perPage).toList();
        setState(() {
          _transactions.addAll(next);
          _bufferedRemaining = _bufferedRemaining.skip(next.length).toList();
          _hasMore = _bufferedRemaining.isNotEmpty;
        });
      } else {
        final prefs = await SharedPreferences.getInstance();
        final userId = prefs.getString('user_id');

        if (userId == null) throw Exception('User not logged in');

        final offset = _transactions.length;
        final response = await http.get(
          Uri.parse(
            '${ApiService.baseUrl}/api/transactions?user_id=$userId&limit=$_perPage&offset=$offset',
          ),
        );

        if (response.statusCode == 200) {
          final responseData = json.decode(response.body);
          if (responseData['status'] == 'success') {
            final List data = List<Map<String, dynamic>>.from(
              responseData['data'],
            );
            final fetched = data
                .map((json) => Transaction.fromJson(json))
                .toList();
            setState(() {
              _transactions.addAll(fetched);
              // If we received fewer than requested, there's no more on server.
              _hasMore = fetched.length >= _perPage;
            });
          } else {
            throw Exception(responseData['message']);
          }
        } else {
          throw Exception('Failed to load transactions');
        }
      }
    } catch (e) {
      if (mounted) showNetworkErrorSnackBar(context, e);
      setState(() {
        _error = getFriendlyNetworkErrorMessage(e);
      });
    } finally {
      setState(() => _isLoadingMore = false);
    }
  }

  Color _getStatusColor(int status) {
    switch (status) {
      case 0:
        return Colors.green.shade600;
      case 1:
        return Colors.red.shade700;
      case 2:
        return Colors.red.shade700;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFce4323),
        elevation: 0,
        title: const Text(
          'Transaction History',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadTransactions,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Loading transactions...',
                    style: TextStyle(color: Color(0xFFce4323)),
                  ),
                  SizedBox(width: 12),
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Color(0xFFce4323)),
                  ),
                ],
              ),
            )
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Colors.red.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Error: $_error',
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadTransactions,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFce4323),
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : _transactions.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.receipt_long,
                    size: 48,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No transactions found',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              color: const Color(0xFFce4323),
              backgroundColor: Colors.white,
              onRefresh: () => _loadTransactions(refresh: true),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 12,
                ),
                itemCount: _transactions.length + (_hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index < _transactions.length) {
                    return _buildTransactionCard(_transactions[index]);
                  }

                  // Footer: show either a loading indicator or a "Load More" button
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: _isLoadingMore
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Text(
                                  'Loading more...',
                                  style: TextStyle(color: Color(0xFFce4323)),
                                ),
                                SizedBox(width: 12),
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Color(0xFFce4323),
                                  ),
                                ),
                              ],
                            )
                          : OutlinedButton(
                              onPressed: _loadMoreTransactions,
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                  color: Color(0xFFce4323),
                                  width: 1.5,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text(
                                'Load More',
                                style: TextStyle(color: Color(0xFFce4323)),
                              ),
                            ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  Widget _buildTransactionCard(Transaction transaction) {
    String planDisplay() {
      final sn = transaction.serviceName.trim();
      final sd = transaction.serviceDescription.trim();
      if (sd.isEmpty) return sn;
      final sdLower = sd.toLowerCase();
      final snLower = sn.toLowerCase();
      // If this is a wallet funding transaction, show a concise label.
      if (snLower.contains('wallet') || sdLower.contains('wallet')) {
        return 'Wallet Credit';
      }
      // If it's an admin-marked description (but not wallet), surface it.
      if (sdLower.contains('admin')) {
        return 'Admin Transaction';
      }

      // If one string contains the other (case-insensitive), prefer the
      // more descriptive one to avoid duplication like "airtime Airtime".
      if (sdLower.contains(snLower) && sdLower != snLower) {
        return sd;
      }
      if (snLower.contains(sdLower) && sdLower != snLower) {
        return sn;
      }
      // Default: show serviceName + description (covers plan name + size)
      return '$sn $sd';
    }

    IconData getTransactionIcon() {
      final snLower = transaction.serviceName.toLowerCase();
      final sdLower = transaction.serviceDescription.toLowerCase();
      if (snLower.contains('wallet') || sdLower.contains('wallet')) {
        return Icons.account_balance_wallet;
      } else if (snLower.contains('data')) {
        return Icons.data_usage;
      } else if (snLower.contains('airtime')) {
        return Icons.phone_android;
      } else if (snLower.contains('tv') || snLower.contains('cable')) {
        return Icons.tv;
      } else if (snLower.contains('electricity')) {
        return Icons.electric_bolt;
      }
      return Icons.receipt_long;
    }

    String formattedDate(DateTime dt) {
      final d = dt.toLocal();
      final day = d.day.toString().padLeft(2, '0');
      final month = d.month.toString().padLeft(2, '0');
      final year = d.year;
      final hour = d.hour.toString().padLeft(2, '0');
      final minute = d.minute.toString().padLeft(2, '0');
      return '$day/$month/$year • $hour:$minute';
    }

    final statusColor = _getStatusColor(transaction.status);
    final icon = getTransactionIcon();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200, width: 1),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TransactionDetailsPage(
                transactionId: transaction.reference,
                amount: transaction.amount.toStringAsFixed(2),
                phoneNumber: transaction.serviceDescription,
                network: transaction.serviceName,
                initialStatus: transaction.statusText.toLowerCase(),
                planName: planDisplay(),
                transactionDate: transaction.date.toString(),
                planValidity: 'N/A',
                playOnOpen: false,
                fromTransactions: true,
                oldBalance: transaction.oldBalance.toStringAsFixed(2),
                newBalance: transaction.newBalance.toStringAsFixed(2),
                token: transaction.token,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Transaction type icon with modern background
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: transaction.status == 0
                          ? Colors.green.shade50
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      icon,
                      color: transaction.status == 0
                          ? Colors.green.shade700
                          : Colors.red.shade700,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Transaction details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Main title
                        Builder(
                          builder: (context) {
                            final isAdminCredit =
                                (transaction.serviceName.toLowerCase().contains(
                                      'wallet',
                                    ) ||
                                    transaction.serviceDescription
                                        .toLowerCase()
                                        .contains('wallet')) &&
                                (transaction.serviceDescription
                                        .toLowerCase()
                                        .contains('reason') ||
                                    transaction.serviceDescription
                                        .toLowerCase()
                                        .contains('admin'));
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  planDisplay(),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1A1A1A),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (isAdminCredit) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    'By Admin mkdata',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w400,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 6),
                        Text(
                          formattedDate(transaction.date),
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Amount and status
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '₦${transaction.amount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: transaction.status == 0
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: statusColor.withOpacity(0.3),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          transaction.statusText,
                          style: TextStyle(
                            color: transaction.status == 0
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
