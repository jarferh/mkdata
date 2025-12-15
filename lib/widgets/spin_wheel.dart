import 'package:flutter/material.dart';
import 'dart:math';
import '../models/spin_reward.dart';

class SpinWheel extends StatefulWidget {
  final List<SpinReward> rewards;
  final VoidCallback onSpinStart;
  final Function(int rewardIndex, double finalDegree) onSpinEnd;
  final bool isSpinning;
  final SpinReward? winningReward; // The actual reward from backend

  const SpinWheel({
    super.key,
    required this.rewards,
    required this.onSpinStart,
    required this.onSpinEnd,
    required this.isSpinning,
    this.winningReward,
  });

  @override
  State<SpinWheel> createState() => _SpinWheelState();
}

class _SpinWheelState extends State<SpinWheel>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _currentRotation = 0;
  bool _isIndeterminate = false; // whether we're in continuous spin mode

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 5),
      vsync: this,
    );
    // Initialize the animation with a default value to avoid LateInitializationError
    _animation = Tween<double>(
      begin: 0,
      end: 0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.decelerate));
  }

  @override
  void didUpdateWidget(SpinWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Start indeterminate spin when spinning begins
    if (widget.isSpinning && !oldWidget.isSpinning) {
      _startIndeterminateSpin();
    }

    // Stop everything when spinning ends
    if (!widget.isSpinning && oldWidget.isSpinning) {
      _stopAllSpins();
    }

    // If a winning reward arrives while we're spinning indeterminately,
    // map the backend reward id to our local rewards list and transition
    // to a targeted spin toward that reward. This uses id matching instead
    // of object equality which may fail when objects are deserialized.
    if (widget.isSpinning &&
        _isIndeterminate &&
        widget.winningReward != null &&
        widget.winningReward != oldWidget.winningReward) {
      final backendId = widget.winningReward!.id;
      _log('didUpdateWidget: winningReward received: id=$backendId');
      final idx = widget.rewards.indexWhere((r) => r.id == backendId);
      if (idx == -1) {
        _log(
          'didUpdateWidget: WARNING: winningReward id not found in current rewards list: id=$backendId',
        );
      } else {
        _log(
          'didUpdateWidget: mapped winningReward id=$backendId to index=$idx',
        );
        _transitionToTargetedSpin(widget.rewards[idx]);
      }
    }
  }

  // Starts a short continuous (indeterminate) spinning animation
  void _startIndeterminateSpin() {
    _isIndeterminate = true;
    _controller.stop();
    // Animate a continuous rotation by mapping controller 0..1 to degrees
    _controller.duration = const Duration(milliseconds: 600);
    _animation = Tween<double>(
      begin: _currentRotation % 360,
      end: _currentRotation % 360 + 360,
    ).animate(_controller);
    _controller.repeat();
  }

  // Stop everything and reset controller
  void _stopAllSpins() {
    _isIndeterminate = false;
    if (_controller.isAnimating) {
      _controller.stop();
    }
    _animation = Tween<double>(begin: 0, end: 0).animate(_controller);
  }

  void _log(String msg) {
    // Intentionally using print so this shows up in Flutter logs during debugging
    // and in integration tests. Prefix to make grepping easier: [SpinWheel]
    // ignore: avoid_print
    print('[SpinWheel] $msg');
  }

  // Transition from indeterminate to a targeted spin to `reward`
  void _transitionToTargetedSpin(SpinReward reward) {
    // Compute reward index
    int winningIndex = widget.rewards.indexWhere((r) => r.id == reward.id);
    if (winningIndex == -1) winningIndex = 0;

    // Determine segment angles (degrees)
    double segmentAngle = 360 / widget.rewards.length;
    double segmentCenterAngle = segmentAngle * winningIndex + segmentAngle / 2;

    // Compute final rotation such that the segment center aligns with the
    // pointer at the top (12 o'clock). The top corresponds to 270 degrees
    // in the canvas coordinate system (0 degrees is at 3 o'clock), so the
    // rotation we need is (270 - segmentCenterAngle) mod 360.
    double finalPosition = (270 - segmentCenterAngle) % 360;

    _log(
      'transitionToTargetedSpin: winningIndex=$winningIndex segmentAngle=$segmentAngle segmentCenterAngle=$segmentCenterAngle finalPosition=$finalPosition',
    );

    // Stop indeterminate and capture current angle in degrees
    double currentDeg;
    if (_isIndeterminate) {
      // _animation.value already represents degrees for indeterminate spin
      currentDeg = (_animation.value) % 360;
      _controller.stop();
      _isIndeterminate = false;
    } else {
      currentDeg = _currentRotation;
    }

    // Add multiple full rotations on top of current position so the transition
    // is visually pleasing and obvious. To ensure the final rotation (mod 360)
    // equals `finalPosition`, we compute an adjusted base rotation that
    // cancels the currentDeg modulo 360. This guarantees target % 360 == finalPosition.
    const int rotations = 3;
    final double adjustedBaseRotation =
        (360.0 * rotations) - (currentDeg % 360.0);
    double targetDeg = (currentDeg + adjustedBaseRotation + finalPosition);

    _log(
      'transitionToTargetedSpin: currentDeg=$currentDeg adjustedBaseRotation=$adjustedBaseRotation targetDeg=$targetDeg',
    );

    // Animate from currentDeg to targetDeg
    _animation = Tween<double>(
      begin: currentDeg,
      end: targetDeg,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.decelerate));

    // Keep a copy of the segment center angle so we can verify pointer alignment
    final double debugSegmentCenter = segmentCenterAngle;

    _controller.duration = const Duration(seconds: 4);
    _controller.forward(from: 0).then((_) {
      // Normalize stored rotation
      _currentRotation = (targetDeg % 360);
      _log('transition completed: finalRotation=$_currentRotation');

      // Verify that after rotation the selected segment center aligns with the top pointer
      final pointerAngle = (debugSegmentCenter + _currentRotation) % 360;
      _log(
        'post-check: segmentCenter=$debugSegmentCenter pointerAngle=$pointerAngle (expected ~270)',
      );

      // If pointerAngle deviates significantly from 270 degrees, log a warning to help
      // debug orientation issues (e.g., sign/offset errors). We allow a small tolerance.
      final deviation = (pointerAngle - 270).abs();
      if (deviation > 2.0 && deviation < 358.0) {
        _log(
          'WARNING: pointer alignment off by $deviation degrees for winningIndex=$winningIndex',
        );
      }

      widget.onSpinEnd(winningIndex, _currentRotation);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Pointer/Indicator at top
          CustomPaint(painter: TrianglePainter(), size: const Size(20, 30)),
          const SizedBox(height: 8),
          // Spinning wheel
          AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              return Transform.rotate(
                angle: widget.isSpinning
                    ? _animation.value * pi / 180
                    : _currentRotation * pi / 180,
                child: child,
              );
            },
            child: CustomPaint(
              painter: SpinWheelPainter(
                rewards: widget.rewards,
                highlightRewardId: widget.winningReward?.id,
              ),
              size: const Size(320, 320),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class SpinWheelPainter extends CustomPainter {
  final List<SpinReward> rewards;
  final int? highlightRewardId;

  SpinWheelPainter({required this.rewards, this.highlightRewardId});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // List of colors for segments
    const colors = [
      Color(0xFFFFB84D), // Orange
      Color(0xFF4CAF50), // Green
      Color(0xFF2196F3), // Blue
      Color(0xFFE91E63), // Pink
      Color(0xFF9C27B0), // Purple
      Color(0xFFFFC107), // Amber
      Color(0xFF00BCD4), // Cyan
    ];

    final segmentAngle = 360 / rewards.length;

    // Draw segments
    for (int i = 0; i < rewards.length; i++) {
      final startAngle = i * segmentAngle * pi / 180;
      final sweepAngle = segmentAngle * pi / 180;

      paint.color = colors[i % colors.length];

      // If this segment is the highlighted (server-selected) reward, draw a
      // translucent overlay to make it obvious during debugging.
      final isHighlighted =
          highlightRewardId != null && rewards[i].id == highlightRewardId;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        paint,
      );

      if (isHighlighted) {
        final overlayPaint = Paint()..color = Colors.black.withOpacity(0.18);
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          startAngle,
          sweepAngle,
          true,
          overlayPaint,
        );
      }

      // Draw border between segments
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        strokePaint,
      );

      // Draw text label for each segment
      final labelAngle = startAngle + sweepAngle / 2;
      final labelRadius = radius * 0.65;
      final labelX = center.dx + labelRadius * cos(labelAngle);
      final labelY = center.dy + labelRadius * sin(labelAngle);

      // Draw reward name and a second-line type label (with emoji)
      final namePainter = TextPainter(
        text: TextSpan(
          text: rewards[i].name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      namePainter.layout();

      final typeLabel = _typeWithEmoji(rewards[i].type);
      final typePainter = TextPainter(
        text: TextSpan(
          text: typeLabel,
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      typePainter.layout();

      // Vertical stacking: name above, type (small) below, with a small gap
      final gap = 4.0;
      final totalHeight = namePainter.height + gap + typePainter.height;

      canvas.save();
      canvas.translate(labelX, labelY);
      canvas.rotate(labelAngle + pi / 2);

      namePainter.paint(
        canvas,
        Offset(-namePainter.width / 2, -totalHeight / 2),
      );

      typePainter.paint(
        canvas,
        Offset(
          -typePainter.width / 2,
          -totalHeight / 2 + namePainter.height + gap,
        ),
      );

      canvas.restore();
    }

    // Draw center circle
    paint.color = Colors.white;
    canvas.drawCircle(center, 30, paint);

    paint.color = const Color(0xFFce4323);
    canvas.drawCircle(center, 25, paint);

    // Draw "SPIN" text in center
    final spinTextPainter = TextPainter(
      text: const TextSpan(
        text: 'SPIN',
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    spinTextPainter.layout();
    spinTextPainter.paint(
      canvas,
      Offset(
        center.dx - spinTextPainter.width / 2,
        center.dy - spinTextPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(SpinWheelPainter oldDelegate) {
    return oldDelegate.rewards != rewards ||
        oldDelegate.highlightRewardId != highlightRewardId;
  }

  String _typeWithEmoji(String type) {
    switch (type.toLowerCase()) {
      case 'airtime':
        return 'Airtime 📱';
      case 'data':
        return 'Data 📶';
      case 'tryagain':
        return 'Try Again 🙃';
      default:
        // Capitalize first letter
        return '${type[0].toUpperCase()}${type.substring(1)}';
    }
  }
}

class TrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFce4323)
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(size.width / 2, 0);
    path.lineTo(0, size.height);
    path.lineTo(size.width, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(TrianglePainter oldDelegate) => false;
}
