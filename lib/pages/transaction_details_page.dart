import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import '../services/api_service.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

class TransactionDetailsPage extends StatefulWidget {
  final String transactionId;
  final String amount;
  final String phoneNumber;
  final String network;
  final String initialStatus;
  final String planName;
  final String transactionDate;
  final String planValidity;
  final bool playOnOpen;
  // When opening details from the transactions list we can show balance deltas
  final bool fromTransactions;
  final String? oldBalance;
  final String? newBalance;
  final String? token;

  const TransactionDetailsPage({
    super.key,
    required this.transactionId,
    required this.amount,
    required this.phoneNumber,
    required this.network,
    required this.initialStatus,
    required this.planName,
    required this.transactionDate,
    required this.planValidity,
    this.playOnOpen = true,
    this.fromTransactions = false,
    this.oldBalance,
    this.newBalance,
    this.token,
  });

  @override
  State<TransactionDetailsPage> createState() => _TransactionDetailsPageState();
}

class _TransactionDetailsPageState extends State<TransactionDetailsPage> {
  late String _status;
  late Timer _timer;
  final ApiService _apiService = ApiService();
  bool _isLoading = false;
  final GlobalKey _printScreenKey = GlobalKey();

  // Voice playback removed

  Future<void> _captureAndSharePng() async {
    try {
      // Capture the widget to an image
      final RenderRepaintBoundary boundary =
          _printScreenKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      final Uint8List pngBytes = byteData!.buffer.asUint8List();

      // Save the image to temporary directory
      final directory = await getTemporaryDirectory();
      final imagePath = '${directory.path}/transaction.png';
      File(imagePath).writeAsBytesSync(pngBytes);

      // Share the image
      await Share.shareFiles([imagePath], text: 'Transaction Receipt');
    } catch (e) {
      print('Error sharing screenshot: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to share transaction details'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _status = _normalizeStatus(widget.initialStatus);
    // Hide system navigation bar on this page (keep status bar visible)
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top],
    );
    if (_status == 'processing') {
      _startStatusCheck();
    }
  }

  void _startStatusCheck() {
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _checkTransactionStatus();
      if (_status != 'processing') {
        timer.cancel();
      }
    });
  }

  Future<void> _checkTransactionStatus() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await _apiService.getTransactionStatus(
        widget.transactionId,
      );
      final newStatusRaw = response['status'];
      final newStatus = _normalizeStatus(newStatusRaw);
      setState(() {
        _status = newStatus;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Normalize status values coming from API which may be numeric (0,1,2) or strings
  String _normalizeStatus(dynamic raw) {
    try {
      if (raw == null) return 'failed';
      if (raw is int) {
        if (raw == 0) return 'success';
        if (raw == 1) return 'failed';
        return 'processing';
      }
      final s = raw.toString().trim();
      final lower = s.toLowerCase();
      // If numeric string
      final numVal = int.tryParse(s);
      if (numVal != null) {
        if (numVal == 0) return 'success';
        if (numVal == 1) return 'failed';
        return 'processing';
      }
      if ([
        'success',
        'successful',
        'ok',
        'completed',
        'true',
      ].contains(lower)) {
        return 'success';
      }
      if (['failed', 'error', 'failed_transaction', 'false'].contains(lower)) {
        return 'failed';
      }
      if (lower == 'processing' || lower == 'pending') return 'processing';
    } catch (_) {}
    return 'failed';
  }

  @override
  void dispose() {
    if (_status == 'processing') {
      _timer.cancel();
    }
    // Restore system UI (show status and navigation bars) when leaving page
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFce4323),
        elevation: 0,
        title: Text(
          _getTransactionTitle(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Container(
          color: const Color(0xFFF5F5F5),
          child: Column(
            children: [
              // Capture only the receipt content (without balance info)
              RepaintBoundary(
                key: _printScreenKey,
                child: Container(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        // Status Section
                        _buildStatusSection(),

                        const SizedBox(height: 24),

                        // Transaction Details Card
                        _buildTransactionDetailsCard(),
                      ],
                    ),
                  ),
                ),
              ),

              // Balance Information (shown on screen but NOT captured for sharing)
              if (!_isFailed())
                Container(
                  color: Colors.white,
                  margin: const EdgeInsets.only(top: 12),
                  child: _buildBalanceSection(),
                ),

              const SizedBox(height: 12),

              // Action Buttons
              _buildActionButtons(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusSection() {
    return Column(
      children: [
        // Logo
        // Align(
        //   alignment: Alignment.topLeft,
        //   child: Container(
        //     margin: const EdgeInsets.only(bottom: 16),
        //     height: 20,
        //     child: Row(
        //       mainAxisSize: MainAxisSize.min,
        //       children: [
        //         Image.asset(
        //           'assets/images/app_icon.png',
        //           width: 25,
        //           height: 25,
        //           fit: BoxFit.cover,
        //           errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        //         ),
        //         const SizedBox(width: 5),
        //         Image.asset(
        //           'assets/images/new_logo.png',
        //           fit: BoxFit.contain,
        //           errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        //         ),
        //       ],
        //     ),
        //   ),
        // ),

        // Status Icon
        if (_status.toLowerCase() == 'success' ||
            _status.toLowerCase() == 'successful')
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green.shade50,
            ),
            child: Icon(
              Icons.check_circle,
              size: 70,
              color: Colors.green.shade700,
            ),
          )
        else if (_isFailed())
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.red.shade50,
            ),
            child: Icon(Icons.error, size: 70, color: Colors.red.shade700),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.orange.shade50,
            ),
            child: Icon(
              Icons.hourglass_bottom,
              size: 70,
              color: Colors.orange.shade600,
            ),
          ),

        const SizedBox(height: 16),

        // Amount
        Text(
          '₦${widget.amount.replaceAll(RegExp(r'\.00$'), '')}',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color:
                _status.toLowerCase() == 'success' ||
                    _status.toLowerCase() == 'successful'
                ? Colors.green.shade700
                : (_isFailed() ? Colors.red.shade700 : const Color(0xFFce4323)),
          ),
        ),

        const SizedBox(height: 12),

        // Status Message
        Text(
          _getStatusMessage(),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: _isFailed()
                ? Colors.red.shade700
                : (_status.toLowerCase() == 'processing'
                      ? Colors.orange.shade700
                      : Colors.green.shade700),
          ),
        ),

        const SizedBox(height: 8),

        // Status Details
        Text(
          _getStatusDetails(),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildTransactionDetailsCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section Title
            Text(
              'Transaction Details',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),

            const SizedBox(height: 16),

            // Details Rows
            _buildDetailRow('Type', _getTransactionType()),
            const Divider(height: 20),
            _buildDetailRow('Status', _status.toLowerCase()),
            const Divider(height: 20),
            _buildDetailRow('Amount', '₦${widget.amount}'),
            const Divider(height: 20),
            _buildDetailRow('Date', widget.transactionDate),
            const Divider(height: 20),
            _buildDetailRow('Transaction ID', widget.transactionId),
            if (widget.token != null && widget.token!.isNotEmpty) ...[
              const Divider(height: 20),
              _buildDetailRow('Token', widget.token!),
            ],
            const Divider(height: 20),
            _buildDetailRow('Information', _getInformationText()),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceSection() {
    bool hasBalance = widget.oldBalance != null || widget.newBalance != null;

    if (!hasBalance) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Account Balance',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 16),
              if (widget.oldBalance != null) ...[
                _buildDetailRow('Old Balance', '₦${widget.oldBalance}'),
                const SizedBox(height: 12),
              ],
              if (widget.newBalance != null) ...[
                _buildDetailRow('New Balance', '₦${widget.newBalance}'),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return SafeArea(
      bottom: true,
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Colors.grey.shade200, width: 1),
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Share Button (always visible)
            Expanded(
              child: OutlinedButton(
                onPressed: _captureAndSharePng,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFce4323), width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.share, color: Color(0xFFce4323), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Share',
                      style: TextStyle(
                        color: Color(0xFFce4323),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 12),

            // Back Button
            Expanded(
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFce4323),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.arrow_back, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Back',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getTransactionTitle() {
    if (_status.toLowerCase() == 'success' ||
        _status.toLowerCase() == 'successful') {
      return 'Transaction Success';
    } else if (_status.toLowerCase() == 'processing') {
      return 'Transaction Processing';
    }
    return 'Transaction Failed';
  }

  String _getStatusMessage() {
    if (_status.toLowerCase() == 'success' ||
        _status.toLowerCase() == 'successful') {
      return 'Payment Successful';
    } else if (_status.toLowerCase() == 'processing') {
      return 'Processing Payment';
    }
    return 'Payment Failed';
  }

  String _getStatusDetails() {
    if (_status.toLowerCase() == 'success' ||
        _status.toLowerCase() == 'successful') {
      return 'Your transaction has been completed successfully.';
    } else if (_status.toLowerCase() == 'processing') {
      return 'Your transaction is being processed. Please wait...';
    }
    return 'Your transaction could not be completed. Please try again.';
  }

  String _getTransactionType() {
    final lower = widget.planName.toLowerCase();
    if (lower.contains('exam')) {
      return 'Exam Pin';
    }
    if (lower.contains('data pin') ||
        lower.contains('data-pin') ||
        lower.contains('datapin')) {
      return 'Data Pin';
    }
    if (lower.contains('data') && !lower.contains('pin')) {
      return 'Data Bundle';
    }
    if (lower.contains('tv') || lower.contains('cable')) {
      return 'Cable TV';
    }
    if (lower.contains('electricity')) {
      return 'Electricity';
    }
    if (lower.contains('airtime') || lower.contains('card')) {
      return 'Airtime';
    }
    if (lower.contains('wallet')) {
      return 'Wallet Credit';
    }
    return widget.planName;
  }

  String _getInformationText() {
    bool isSuccessful =
        _status.toLowerCase() == 'success' ||
        _status.toLowerCase() == 'successful';

    final plan = widget.planName;
    final lowerPlan = plan.toLowerCase();
    final amount = widget.amount;
    final phone = widget.phoneNumber;
    final network = widget.network;

    if (lowerPlan.contains('exam')) {
      final examType =
          network; // network field contains exam type for exam purchases
      return isSuccessful
          ? 'You have successfully purchased $plan from $examType for ₦$amount.'
          : 'Failed to purchase $plan from $examType.';
    } else if (lowerPlan.contains('wallet')) {
      return isSuccessful
          ? 'You have successfully funded your wallet with ₦$amount.'
          : 'Failed to fund your wallet with ₦$amount.';
    } else if (lowerPlan.contains('data pin') ||
        lowerPlan.contains('data-pin') ||
        lowerPlan.contains('datapin')) {
      return isSuccessful
          ? 'You have successfully purchased Data PIN ($plan) for ₦$amount. The PIN will be sent to $phone.'
          : 'Failed to purchase Data PIN ($plan) to $phone.';
    } else if (lowerPlan.contains('card pin') ||
        lowerPlan.contains('card-pin') ||
        (lowerPlan.contains('card') && lowerPlan.contains('pin'))) {
      return isSuccessful
          ? 'You have successfully purchased Card PIN ($plan) for ₦$amount. The PIN will be sent to $phone.'
          : 'Failed to purchase Card PIN ($plan) to $phone.';
    } else if (lowerPlan.contains('data')) {
      return isSuccessful
          ? 'You have successfully purchased : $plan.'
          : 'Failed to purchase: $plan.';
    } else if (lowerPlan.contains('tv')) {
      return isSuccessful
          ? 'You have successfully subscribed to $plan on $network for Card/IUC: $phone.'
          : 'Failed to subscribe to $plan for Card/IUC: $phone.';
    } else if (lowerPlan.contains('electricity')) {
      return isSuccessful
          ? 'You have successfully purchased $plan for Meter: $phone.'
          : 'Failed to purchase $plan for Meter: $phone.';
    } else if (lowerPlan.contains('airtime')) {
      return isSuccessful
          ? 'You have successfully bought airtime of ₦$amount to $phone.'
          : 'Failed to buy airtime of ₦$amount on $network to $phone.';
    } else {
      return isSuccessful
          ? 'You have successfully completed the transaction: $plan for ₦$amount to $phone.'
          : 'Failed to complete the transaction: $plan to $phone.';
    }
  }

  // Helper: determine if current transaction is failed
  bool _isFailed() {
    final s = _status.toLowerCase();
    return !(s == 'success' || s == 'successful' || s == 'processing');
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color.fromARGB(255, 51, 66, 73),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                color: Color.fromARGB(255, 0, 0, 0),
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
