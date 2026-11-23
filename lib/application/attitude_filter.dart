import 'dart:math' as math;
import 'orientation.dart';

/// Quaternion complementary filter, sensor/body -> world.
/// Body gyro increments compose on the right; gravity correction acts on the
/// left in world coordinates. No Euler rate division or vertical exclusion.
/// Accelerometers correct tilt only: heading remains relative and can drift.
class AttitudeFilter {
  static const double correctionTauS = 0.35;
  static const double gapS = 0.5;
  static const double gyroDeadbandDps = 0.15;
  static const double minReliableG = 0.75, maxReliableG = 1.25;

  Orientation? _bodyToWorld;
  Orientation _reference = Orientation.identity;
  List<double>? _biasDps;
  bool _valid = false, _yawStale = false;
  bool gravityReliable = false;

  /// Estimator availability is separate from the packet's valid flag.
  bool get valid => _valid;
  bool get zeroed => _biasDps != null;
  bool get yawStale => _yawStale;

  /// Retained through invalid data for a frozen, greyed-out display.
  Orientation? get orientation =>
      _bodyToWorld == null
          ? null
          : (_reference.inverse * _bodyToWorld!).normalized;
  double? get rollDeg => valid ? orientation!.roll * 180 / math.pi : null;
  double? get pitchDeg => valid ? orientation!.pitch * 180 / math.pi : null;
  double? get yawDeg => zeroed ? orientation!.yaw * 180 / math.pi : null;

  void update(List<double> accelG, List<double> gyroDps, double dt) {
    final magnitude = _norm(accelG);
    gravityReliable = magnitude >= minReliableG && magnitude <= maxReliableG;
    if (dt > gapS) _yawStale = true;

    // Missing motion cannot be reconstructed from one later gyro sample.
    // Re-acquire tilt only when gravity is plausible. Keep the existing 3D
    // heading freedom via the shortest correction, even exactly at vertical.
    if (!valid || dt <= 0 || dt > gapS) {
      _valid = gravityReliable;
      if (_valid) {
        _bodyToWorld =
            zeroed && _bodyToWorld != null
                ? _correctGravity(_bodyToWorld!, accelG, magnitude, 1)
                : _fromGravity(accelG, 0);
      }
      return;
    }

    var predicted = _bodyToWorld!;
    final bias = _biasDps;
    if (bias != null) {
      final rotation = List.generate(3, (i) {
        final corrected = gyroDps[i] - bias[i];
        return (corrected.abs() < gyroDeadbandDps ? 0.0 : corrected) *
            math.pi /
            180 *
            dt;
      });
      predicted = (predicted * Orientation.rotationVector(rotation)).normalized;
    }
    if (gravityReliable) {
      predicted = _correctGravity(
        predicted,
        accelG,
        magnitude,
        1 - math.exp(-dt / correctionTauS),
      );
    }
    // Before zero the gyro bias is unknown; show gravity-derived tilt only.
    _bodyToWorld =
        bias == null
            ? _fromGravity(predicted.inverse.rotate(const [0.0, 0.0, 1.0]), 0)
            : predicted;
  }

  void invalidate() {
    _valid = false;
    gravityReliable = false;
    _yawStale = true;
  }

  /// Reference is a full rotation, not three Euler offsets. This also handles
  /// zeroing on a tilted surface and subsequent compound rotations.
  void applyZero(List<double> gyroBiasDps, List<double> meanAccelG) {
    _biasDps = List.of(gyroBiasDps);
    _bodyToWorld = _fromGravity(meanAccelG, 0);
    _reference = _bodyToWorld!;
    _valid = true;
    _yawStale = false;
  }

  static Orientation _fromGravity(List<double> g, double yaw) =>
      Orientation.euler(
        math.atan2(g[1], g[2]),
        math.atan2(-g[0], math.sqrt(g[1] * g[1] + g[2] * g[2])),
        yaw,
      );
  static Orientation _correctGravity(
    Orientation pose,
    List<double> accelG,
    double magnitude,
    double gain,
  ) {
    final measured = accelG.map((v) => v / magnitude).toList();
    final correction = Orientation.between(pose.rotate(measured), const [
      0.0,
      0.0,
      1.0,
    ]);
    return (Orientation.identity.slerp(correction, gain) * pose).normalized;
  }

  static double _norm(List<double> v) =>
      math.sqrt(v.fold(0.0, (s, x) => s + x * x));
}
