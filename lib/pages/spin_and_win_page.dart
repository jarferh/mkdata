import 'package:flutter/material.dart';
import '../services/spin_service.dart';
import '../models/spin_reward.dart';
import '../models/spin_win.dart';
import '../widgets/spin_wheel.dart';
import 'package:intl/intl.dart';
import 'dart:async';

class SpinAndWinPage extends StatefulWidget {
  const SpinAndWinPage({super.key});

  @override
  State<SpinAndWinPage> createState() => _SpinAndWinPageState();
}

class _SpinAndWinPageState extends State<SpinAndWinPage> {
  late SpinService _spinService;
  List<SpinReward> _rewards = [];
  List<SpinWin> _spinHistory = [];
  bool _isLoading = true;
  bool _isSpinning = false;
  String? _errorMessage;
  SpinWin? _currentSpinResult; // Store the spin result while wheel is spinning
  Timer? _spinTimeoutTimer;
  // Cooldown / status info
  bool _canSpinNow = true;
  DateTime? _nextSpinAvailable;
  int? _cooldownRemainingSeconds;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _spinService = SpinService();
    _initializeData();
  }

  Future<void> _initializeData() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      // Fetch rewards and spin history in parallel
      final results = await Future.wait([
        _spinService.getSpinRewards(),
        _spinService.getSpinHistory(),
      ]);

      _rewards = results[0] as List<SpinReward>;
      _spinHistory = results[1] as List<SpinWin>;

      // Sort rewards by ID to ensure consistent ordering with backend
      _rewards.sort((a, b) => a.id.compareTo(b.id));

      // Fetch cooldown/status and apply to UI
      await _refreshCooldownStatus();

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshCooldownStatus() async {
    try {
      final status = await _spinService.getSpinCooldownStatus();
      if (!mounted) return;
      if (status != null) {
        setState(() {
          _canSpinNow = status.canSpinNow;
          _nextSpinAvailable = status.nextSpinAvailable;
        });

        // If cooldown active, compute remaining seconds and start countdown
        if (!_canSpinNow && _nextSpinAvailable != null) {
          final seconds = _nextSpinAvailable!
              .difference(DateTime.now())
              .inSeconds;
          if (seconds > 0) {
            _startCooldownCountdown(seconds);
          } else {
            setState(() {
              _canSpinNow = true;
              _cooldownRemainingSeconds = null;
            });
          }
        }
      }
    } catch (e) {
      // ignore errors for status refresh
    }
  }

  void _startCooldownCountdown(int seconds) {
    _cooldownTimer?.cancel();
    setState(() {
      _canSpinNow = false;
      _cooldownRemainingSeconds = seconds;
    });

    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        if ((_cooldownRemainingSeconds ?? 0) <= 1) {
          _cooldownTimer?.cancel();
          _canSpinNow = true;
          _cooldownRemainingSeconds = null;
          // refresh status from server
          _refreshCooldownStatus();
        } else {
          _cooldownRemainingSeconds = (_cooldownRemainingSeconds ?? 0) - 1;
        }
      });
    });
  }

  void _stopCooldownCountdown() {
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
  }

  Future<void> _performSpin() async {
    if (_isSpinning) return;

    try {
      setState(() {
        _isSpinning = true;
        _currentSpinResult = null;
      });

      // Start a local shorter timeout to give feedback to the user if the
      // backend is unusually slow. The SpinService http request already
      // has its own timeout, but this lets us stop the indeterminate spin
      // sooner and show a helpful message.
      _spinTimeoutTimer?.cancel();
      _spinTimeoutTimer = Timer(const Duration(seconds: 10), () {
        if (mounted && _isSpinning && _currentSpinResult == null) {
          setState(() {
            _isSpinning = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Request timed out. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      });

      // Call the backend API immediately. The wheel will spin indeterminately
      // until a winning reward is set (the wheel transitions to the target).
      final result = await _spinService.performSpin();

      // Cancel timeout once we have a result
      _spinTimeoutTimer?.cancel();

      // Cancel timeout once we have a result
      _spinTimeoutTimer?.cancel();

      // Update UI with backend result immediately so the wheel can switch to target
      if (mounted) {
        setState(() {
          _currentSpinResult = result;
        });
        // Debug logging
        // ignore: avoid_print
        print(
          '[SpinAndWin] backend result received: rewardId=${result.rewardId} id=${result.id}',
        );

        // If the wheel has already stopped by the time the backend responded,
        // show the backend result immediately and add to history.
        if (!_isSpinning) {
          // ignore: avoid_print
          print(
            '[SpinAndWin] backend result arrived after wheel stopped — showing result now',
          );
          setState(() {
            _spinHistory.insert(0, _currentSpinResult!);
          });
          _showSpinResultDialog(_currentSpinResult!);
          _currentSpinResult = null;
        }
        // After a successful spin, refresh cooldown status from server
        _refreshCooldownStatus();
      }
    } catch (e) {
      if (mounted) {
        _spinTimeoutTimer?.cancel();
        setState(() {
          _isSpinning = false;
          _currentSpinResult = null;
        });
        if (e is SpinCooldownException) {
          // Start cooldown UI and show message
          final seconds = e.secondsUntilNextSpin ?? 0;
          if (seconds > 0) {
            _startCooldownCountdown(seconds);
            _nextSpinAvailable = DateTime.now().add(Duration(seconds: seconds));
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.message.replaceAll('Exception: ', '')),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _spinTimeoutTimer?.cancel();
    _stopCooldownCountdown();
    super.dispose();
  }

  String _formatDurationSeconds(int seconds) {
    final d = Duration(seconds: seconds);
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$hours:$minutes:$secs';
  }

  void _showSpinResultDialog(SpinWin result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Congratulations! 🎉',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFFce4323),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    _getRewardDisplayName(result),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFce4323),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _getRewardDescription(result),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (result.rewardType != 'tryagain')
              Text(
                result.status == 'pending'
                    ? 'Your reward will be delivered to your account'
                    : 'Your reward has been delivered!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
          ],
        ),
        actions: [
          if (result.rewardType != 'tryagain' && result.status == 'pending')
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _openClaimDialog(result);
              },
              child: const Text(
                'Claim',
                style: TextStyle(color: Color(0xFFce4323)),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Close',
              style: TextStyle(color: Color(0xFFce4323)),
            ),
          ),
        ],
      ),
    );
  }

  String _getRewardDisplayName(SpinWin win) {
    if (win.rewardType == 'tryagain') {
      return 'Try Again! 😊';
    }
    if (win.rewardType == 'airtime') {
      return '₦${win.amount?.toStringAsFixed(0) ?? '0'} Airtime';
    }
    return '${win.amount?.toStringAsFixed(1) ?? '0'} ${win.unit ?? 'Data'}';
  }

  String _getRewardDescription(SpinWin win) {
    if (win.rewardType == 'tryagain') {
      return 'Better luck next time!';
    }
    return 'Reward for spin';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text(
          'Spin & Win',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFFce4323),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFce4323)),
            )
          : _errorMessage != null
          ? _buildErrorWidget()
          : _buildMainContent(),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.grey),
          const SizedBox(height: 16),
          Text('Error Loading', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _errorMessage ?? 'An error occurred',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _initializeData,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFce4323),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Spin wheel section
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              children: [
                // Instructions
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Spin the wheel to win amazing rewards!',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                  ),
                ),
                const SizedBox(height: 8),
                // Cooldown status line
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _canSpinNow
                      ? Text(
                          'You can spin now',
                          style: TextStyle(
                            color: Colors.green.shade700,
                            fontSize: 12,
                          ),
                        )
                      : Text(
                          _cooldownRemainingSeconds != null
                              ? 'Next spin in ${_formatDurationSeconds(_cooldownRemainingSeconds!)}'
                              : 'Next spin available at ${_nextSpinAvailable != null ? DateFormat('dd/MM/yyyy HH:mm').format(_nextSpinAvailable!) : 'soon'}',
                          style: TextStyle(
                            color: Colors.orange.shade700,
                            fontSize: 12,
                          ),
                        ),
                ),
                const SizedBox(height: 20),

                // Spin wheel
                if (_rewards.isNotEmpty)
                  SpinWheel(
                    rewards: _rewards,
                    isSpinning: _isSpinning,
                    onSpinStart: () {
                      // debug
                      // ignore: avoid_print
                      print('[SpinAndWin] Spin started');
                    },
                    onSpinEnd: (index, finalDeg) {
                      final landedReward = _rewards[index];
                      // ignore: avoid_print
                      print(
                        '[SpinAndWin] onSpinEnd: index=$index landedRewardId=${landedReward.id} finalDeg=$finalDeg',
                      );

                      setState(() {
                        _isSpinning = false;
                      });

                      // Prefer backend-provided SpinWin if it matches the landed reward
                      if (_currentSpinResult != null &&
                          _currentSpinResult!.rewardId == landedReward.id) {
                        _spinHistory.insert(0, _currentSpinResult!);
                        _showSpinResultDialog(_currentSpinResult!);
                      } else if (_currentSpinResult != null &&
                          _currentSpinResult!.rewardId != landedReward.id) {
                        // Mismatch between backend choice and wheel landing — log for diagnostics
                        // ignore: avoid_print
                        print(
                          '[SpinAndWin] WARNING: wheel landed on id=${landedReward.id} but backend rewardId=${_currentSpinResult!.rewardId}',
                        );
                        // Still show backend result to the user (truth is backend owns the result)
                        _spinHistory.insert(0, _currentSpinResult!);
                        _showSpinResultDialog(_currentSpinResult!);
                      } else {
                        // No backend result available; construct a fallback SpinWin for UX
                        final fallback = SpinWin(
                          id: -1,
                          userId: 0,
                          rewardId: landedReward.id,
                          rewardType: landedReward.type,
                          amount: landedReward.amount,
                          unit: landedReward.unit,
                          planId: landedReward.planId,
                          status: 'pending',
                          meta: null,
                          spinAt: DateTime.now(),
                          deliveredAt: null,
                        );
                        _spinHistory.insert(0, fallback);
                        _showSpinResultDialog(fallback);
                      }

                      // Reset current backend result for next spin
                      _currentSpinResult = null;
                    },
                    winningReward: _currentSpinResult != null
                        ? _rewards.firstWhere(
                            (r) => r.id == _currentSpinResult!.rewardId,
                            orElse: () => _rewards.first,
                          )
                        : null,
                  )
                else
                  const Center(child: Text('No rewards available')),

                const SizedBox(height: 24),

                // Spin button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: (_isSpinning || !_canSpinNow)
                          ? null
                          : _performSpin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: (_isSpinning || !_canSpinNow)
                            ? Colors.grey.shade400
                            : const Color(0xFFce4323),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        disabledBackgroundColor: Colors.grey.shade400,
                      ),
                      child: _isSpinning
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                                strokeWidth: 2,
                              ),
                            )
                          : (!_canSpinNow && _cooldownRemainingSeconds != null)
                          ? Text(
                              'Next: ${_formatDurationSeconds(_cooldownRemainingSeconds!)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'SPIN NOW',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Spin history section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recent Spins',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                if (_spinHistory.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Text(
                        'No spins yet. Spin the wheel to get started!',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  )
                else
                  _buildSpinHistoryTable(),
              ],
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSpinHistoryTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: DataTable(
          headingRowColor: WidgetStateColor.resolveWith(
            (states) => Colors.grey.shade100,
          ),
          columns: [
            const DataColumn(
              label: Text(
                'Date & Time',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const DataColumn(
              label: Text(
                'Reward',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const DataColumn(
              label: Text(
                'Status',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const DataColumn(
              label: Text(
                'Action',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
          rows: _spinHistory.map((win) {
            return DataRow(
              cells: [
                DataCell(
                  Text(
                    DateFormat('dd/MM/yyyy HH:mm').format(win.spinAt),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                DataCell(
                  Text(
                    _getRewardDisplayName(win),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFce4323),
                    ),
                  ),
                ),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getStatusColor(win.status).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      win.status.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _getStatusColor(win.status),
                      ),
                    ),
                  ),
                ),
                DataCell(_buildActionCell(win)),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildActionCell(SpinWin win) {
    // Only allow claim for non-tryagain rewards and only when status is pending
    final canClaim = win.rewardType != 'tryagain' && win.status == 'pending';
    if (!canClaim) {
      return const SizedBox.shrink();
    }
    return ElevatedButton(
      onPressed: () => _openClaimDialog(win),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFce4323),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: const Text('Claim'),
    );
  }

  Future<void> _openClaimDialog(SpinWin win) async {
    final networks = await _spinService.getNetworks();
    String? selectedNetworkId;
    final phoneController = TextEditingController(
      text: win.getPhoneNumber() ?? '',
    );
    bool isSubmitting = false;

    await showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Claim ${win.rewardType.toUpperCase()}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (networks.isNotEmpty)
                    DropdownButtonFormField<String>(
                      value: selectedNetworkId,
                      decoration: const InputDecoration(labelText: 'Network'),
                      items: networks.map((n) {
                        final id =
                            n['nId']?.toString() ??
                            n['id']?.toString() ??
                            n['id'].toString();
                        final name = n['network'] ?? n['name'] ?? id;
                        return DropdownMenuItem<String>(
                          value: id,
                          child: Text(name.toString()),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => selectedNetworkId = v),
                    )
                  else
                    const Text('No networks available'),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (win.rewardType != 'tryagain')
                    Text(
                      'You will receive ${win.rewardType} (${win.amount?.toStringAsFixed(0) ?? ''} ${win.unit ?? ''}) to the phone number provided.',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final phone = phoneController.text.trim();
                          if (phone.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please enter a phone number'),
                              ),
                            );
                            return;
                          }
                          setState(() => isSubmitting = true);
                          try {
                            final networkIdInt = selectedNetworkId != null
                                ? int.tryParse(selectedNetworkId!)
                                : null;
                            final ok = await _spinService
                                .claimSpinRewardWithDelivery(
                                  win.id,
                                  phone: phone,
                                  networkId: networkIdInt,
                                );
                            if (ok) {
                              // Update local model status
                              setState(() {
                                final idx = _spinHistory.indexWhere(
                                  (s) => s.id == win.id,
                                );
                                if (idx != -1) {
                                  _spinHistory[idx] = SpinWin(
                                    id: win.id,
                                    userId: win.userId,
                                    rewardId: win.rewardId,
                                    rewardType: win.rewardType,
                                    amount: win.amount,
                                    unit: win.unit,
                                    planId: win.planId,
                                    status: 'claimed',
                                    meta: (win.meta ?? {})
                                      ..addAll({
                                        'phone': phone,
                                        'network': selectedNetworkId,
                                      }),
                                    spinAt: win.spinAt,
                                    deliveredAt: win.deliveredAt,
                                  );
                                }
                              });
                              Navigator.pop(dialogCtx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Reward claimed — delivery in progress',
                                  ),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Failed to claim reward'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error: ${e.toString()}'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          } finally {
                            setState(() => isSubmitting = false);
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFce4323),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Claim'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'delivered':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'claimed':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
}
