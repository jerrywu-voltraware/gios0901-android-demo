import 'dart:math' as math;
import 'firmware_pose.dart';
import 'attitude_filter.dart';
import 'gy521_sample.dart';
import 'link_stats.dart';
import 'orientation.dart';
import 'vertical_accel.dart';
import 'zero_capture.dart';

/// GY521 Demo estimation pipeline. Only wires independent parts together:
/// - [attitude]: roll / pitch / relative yaw ([AttitudeFilter]).
/// - [vertical]: instantaneous vertical acceleration ([VerticalAccel]).
/// - [zero]: one-shot zero capture ([ZeroCapture]); a successful result is
///   applied to [attitude] and [vertical].
/// - [link]: delivery statistics ([LinkStats]).
///
/// Pure Dart: shared by the Demo page, tests and `tool/gy521_replay.dart`.
/// Six-axis data cannot measure the RX height or position relative to TX;
/// nothing here pretends to.
class TiltEstimator {
  TiltEstimator({ZeroLimits zeroLimits = const ZeroLimits()})
    : zero = ZeroCapture(limits: zeroLimits);

  final hardware = FirmwarePose();
  bool firmwareMode = false;
  bool get zeroActive => firmwareMode ? hardware.active : zero.active;
  int get zeroPackets => firmwareMode ? hardware.packets : zero.packetCount;
  final attitude = AttitudeFilter();
  final vertical = VerticalAccel();
  final ZeroCapture zero;
  final link = LinkStats();

  /// Most recent zero result (successful or not); null before the first one.
  ZeroResult? lastZero;

  DateTime? _at;

  /// Processes one packet. Returns false (and changes nothing) when its
  /// receive time is not after the previous packet's.
  bool update(Gy521Sample sample) {
    final previous = _at;
    if (previous != null && !sample.at.isAfter(previous)) return false;
    final dt =
        previous == null
            ? 0.0
            : sample.at.difference(previous).inMicroseconds / 1e6;
    _at = sample.at;
    link.add(sample);
    firmwareMode = sample.firmwarePose;
    if (firmwareMode) {
      final oldResult = hardware.result;
      hardware.update(sample);
      if (sample.valid) {
        vertical.update(sample.accelNormG, dt);
      } else {
        vertical.invalidate();
      }
      lastZero = hardware.result;
      if (hardware.result != oldResult && lastZero?.ok == true) {
        vertical.reset(lastZero!.meanNormG);
      }
      return true;
    }
    if (sample.valid) {
      attitude.update(sample.accelG, sample.gyroDps, dt);
      vertical.update(sample.accelNormG, dt);
    } else {
      attitude.invalidate();
      vertical.invalidate();
    }
    final result = zero.add(sample);
    if (result != null) _apply(result);
    return true;
  }

  /// Starts a zero capture with the next packet ("歸零").
  bool zeroCurrentFirmwarePose() {
    if (!firmwareMode || !hardware.zeroCurrent()) return false;
    lastZero = hardware.result;
    vertical.reset(lastZero!.meanNormG);
    return true;
  }

  /// Starts a stationary calibration capture with the next packet.
  void startZero(DateTime now) {
    if (firmwareMode) {
      hardware.start(now);
    } else {
      zero.start(now);
    }
  }

  /// Page timer hook: fails a pending zero after the no-data timeout.
  /// Returns true when a result was produced.
  bool expireZero(DateTime now) {
    if (firmwareMode) {
      final expired = hardware.expire(now);
      lastZero = hardware.result;
      return expired;
    }
    final result = zero.expire(now);
    if (result == null) return false;
    _apply(result);
    return true;
  }

  void _apply(ZeroResult result) {
    lastZero = result;
    if (!result.ok) return;
    attitude.applyZero(result.gyroBiasDps, result.meanAccelG);
    vertical.reset(result.meanNormG);
  }

  bool get valid => firmwareMode ? hardware.valid : attitude.valid;
  Orientation? get orientation =>
      firmwareMode ? hardware.orientation : attitude.orientation;
  bool get zeroed => firmwareMode ? hardware.zeroed : attitude.zeroed;
  bool get yawStale => firmwareMode ? !hardware.zeroed : attitude.yawStale;
  double? get roll =>
      firmwareMode
          ? (orientation == null ? null : orientation!.roll * 180 / math.pi)
          : attitude.rollDeg;
  double? get pitch =>
      firmwareMode
          ? (orientation == null ? null : orientation!.pitch * 180 / math.pi)
          : attitude.pitchDeg;
  double? get yaw =>
      firmwareMode
          ? (zeroed
              ? (orientation == null ? null : orientation!.yaw * 180 / math.pi)
              : null)
          : attitude.yawDeg;
}
