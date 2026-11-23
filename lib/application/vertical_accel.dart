import 'dart:math' as math;

/// Instantaneous vertical acceleration cue: `v = |a| - baseline`, where the
/// baseline is a first-order low-pass of |a| (tau = 2 s).
///
/// This is acceleration, never height or displacement. Moving up shows +v
/// first and -v while braking. Using |a| needs no gravity direction, so it is
/// attitude independent; the known limitation is the accelerometer's fixed
/// per-axis offset (|a| is about 0.924 g at rest on the reference board): a
/// large tilt shifts |a| and the bar leaves zero for about 2 s.
///
/// Works without a zero; a zero only re-seeds the baseline ([reset]).
class VerticalAccel {
  /// Baseline low-pass time constant.
  static const double tauS = 2.0;

  /// A packet interval above this re-seeds the baseline (`b = m`).
  static const double gapS = 0.5;

  /// Display dead band: |v| below this is shown as 0.
  static const double deadbandG = 0.02;

  /// Display full scale; values are clipped to +/- this.
  static const double rangeG = 0.3;

  double? _baseline;
  double? _value;
  double? _lastMagnitude;

  /// Raw v in g (no dead band, no clipping); null before the first valid
  /// packet and after invalid data.
  double? get valueG => _value;

  double? get baselineG => _baseline;

  /// [valueG] with the display dead band and clipping applied.
  double? get displayG => _value == null ? null : display(_value!);

  static double display(double v) =>
      v.abs() < deadbandG ? 0.0 : v.clamp(-rangeG, rangeG).toDouble();

  /// Feeds |a| (g) of one valid packet; [dt] seconds since the previous
  /// packet (0 for the first one).
  void update(double magnitudeG, double dt) {
    final m = magnitudeG;
    _lastMagnitude = m;
    if (_baseline == null || dt <= 0 || dt > gapS) _baseline = m;
    _value = m - _baseline!;
    _baseline = _baseline! + (m - _baseline!) * (1 - math.exp(-dt / tauS));
  }

  /// Invalid data: forget the baseline; the next valid packet re-seeds it.
  void invalidate() {
    _baseline = null;
    _value = null;
    _lastMagnitude = null;
  }

  /// Re-seeds the baseline (zero result: mean |a| over the window) and
  /// re-expresses the latest packet against it.
  void reset(double baselineG) {
    _baseline = baselineG;
    final m = _lastMagnitude;
    _value = m == null ? null : m - baselineG;
  }
}
