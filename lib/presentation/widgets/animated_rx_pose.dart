import 'package:flutter/material.dart' hide Orientation;

import '../../application/orientation.dart';

/// Bounded display-only interpolation. Measurements and their reference are
/// never changed. Missing reports are held, never extrapolated.
class AnimatedRxPose extends StatefulWidget {
  const AnimatedRxPose({
    super.key,
    required this.orientation,
    required this.receivedAt,
    required this.live,
    required this.referenceToken,
    required this.builder,
  });

  final Orientation orientation;
  final DateTime? receivedAt;
  final bool live;

  /// Changes whenever the origin changes (zero or firmware epoch).
  final Object? referenceToken;
  final Widget Function(BuildContext context, Orientation pose) builder;

  @override
  State<AnimatedRxPose> createState() => _AnimatedRxPoseState();
}

class _AnimatedRxPoseState extends State<AnimatedRxPose>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Orientation _from, _target;
  DateTime? _lastReceivedAt;
  double _intervalMs = 100;
  bool _reduceMotion = false;

  Orientation get _shown => _from.slerp(_target, _controller.value);

  @override
  void initState() {
    super.initState();
    _from = _target = widget.orientation;
    _lastReceivedAt = widget.live ? widget.receivedAt : null;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      value: 1,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion && widget.live) _snap(widget.orientation);
  }

  void _snap(Orientation pose) {
    _controller.stop();
    _from = _target = pose;
    _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant AnimatedRxPose oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.live) {
      _snap(_shown);
      return;
    }
    final at = widget.receivedAt;
    final previous = _lastReceivedAt;
    final gapMs =
        at == null || previous == null
            ? null
            : at.difference(previous).inMicroseconds / 1000;
    final referenceChanged = oldWidget.referenceToken != widget.referenceToken;
    if (!oldWidget.live || referenceChanged || _reduceMotion) {
      _lastReceivedAt = at;
      _intervalMs = 100;
      _snap(widget.orientation);
      return;
    }
    // Age/status rebuilds must not restart an in-flight animation. Duplicate
    // and out-of-order reports cannot replace a newer visual target.
    if (at == null || (previous != null && !at.isAfter(previous))) return;
    _lastReceivedAt = at;
    if (gapMs != null) {
      // Follow a sustained 25 Hz stream without retaining the old 80 ms
      // display delay. Delayed valid reports still blend to their measured
      // endpoint; a receive gap alone does not change the reference frame.
      // The upper bound limits catch-up time, and missing reports still hold.
      _intervalMs = (_intervalMs * 0.65 + gapMs * 0.35).clamp(40, 120);
    }
    if (widget.orientation == _target) return;
    final dot =
        _target.w * widget.orientation.w +
        _target.x * widget.orientation.x +
        _target.y * widget.orientation.y +
        _target.z * widget.orientation.z;
    // q and -q represent the same pose. Avoid starting a ticker for that
    // equivalent representation without hiding measurable small rotations.
    if (dot.abs() >= 1 - 1e-12) {
      return;
    }
    final current = _shown;
    _controller.stop();
    _from = current;
    _target = widget.orientation;
    _controller.duration = Duration(milliseconds: _intervalMs.round());
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => widget.builder(context, _shown),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
