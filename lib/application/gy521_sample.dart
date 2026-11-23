import 'orientation.dart';
import 'dart:math' as math;

/// One GY521 advertising packet as seen by the Demo estimator.
///
/// Pure Dart (no Flutter / BLE imports) so the same estimator runs on the
/// phone, in unit tests and in `tool/gy521_replay.dart`.
///
/// Units are the advertising payload's raw units: acceleration in mg,
/// angular rate in 0.01 deg/s (centi-dps). [at] is the APP receive time.
class Gy521Sample {
  final DateTime at;
  final Orientation? pose;
  final int? poseEpoch, poseFlags, poseNormUnits;
  bool get firmwarePose => poseEpoch != null;
  bool get poseStationary => (poseFlags ?? 0) & 2 != 0;

  /// Six-axis valid flag (payload byte 8 bit6, sensor type 1, 24 bytes).
  final bool sixAxisValid;
  final int? axMg, ayMg, azMg;
  final int? gxCdps, gyCdps, gzCdps;

  const Gy521Sample({
    required this.at,
    this.pose,
    this.poseEpoch,
    this.poseFlags,
    this.poseNormUnits,
    required this.sixAxisValid,
    this.axMg,
    this.ayMg,
    this.azMg,
    this.gxCdps,
    this.gyCdps,
    this.gzCdps,
  });

  /// Raw axes in payload order: ax, ay, az (mg), gx, gy, gz (centi-dps).
  List<int?> get rawAxes => [axMg, ayMg, azMg, gxCdps, gyCdps, gzCdps];

  bool get hasAxes => rawAxes.every((v) => v != null);

  /// Usable for estimation: flagged valid and all six axes present.
  bool get valid =>
      sixAxisValid &&
      (firmwarePose ? pose != null && (poseFlags ?? 0) & 1 != 0 : hasAxes);

  /// Acceleration in g. Only meaningful when [hasAxes].
  List<double> get accelG =>
      [axMg!, ayMg!, azMg!].map((v) => v / 1000).toList();

  /// Angular rate in deg/s. Only meaningful when [hasAxes].
  List<double> get gyroDps =>
      [gxCdps!, gyCdps!, gzCdps!].map((v) => v / 100).toList();

  /// |a| in g. Only meaningful when [hasAxes].
  double get accelNormG {
    if (firmwarePose) return (poseNormUnits ?? 0) / 50;
    final a = accelG;
    return math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]);
  }

  /// True when all 12 six-axis payload bytes equal [other]'s.
  bool sameAxesAs(Gy521Sample other) {
    if (!hasAxes || !other.hasAxes) return false;
    final a = rawAxes, b = other.rawAxes;
    for (var i = 0; i < 6; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
