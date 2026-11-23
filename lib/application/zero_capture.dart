import 'package:gios0901/core/localization/translations.dart';
import 'dart:math' as math;

import 'gy521_sample.dart';

/// Rejection limits for one zero capture.
///
/// PROVISIONAL values from DESIGN.md section 2.6. They are deliberately loose
/// and must be re-tuned from real handheld / desk recordings (GY521PKT
/// captures replayed with `tool/gy521_replay.dart`).
class ZeroLimits {
  /// Capture length, measured on receive timestamps from the first packet.
  final int windowMs;
  final int minSamples;

  /// Largest allowed interval between two packets inside the window.
  final int maxGapMs;

  /// Largest allowed max-min of each gyro axis inside the window.
  final double gyroRangeDps;

  /// Largest allowed max-min of each accelerometer axis inside the window.
  final double accelRangeG;

  /// No packet for this long (since the request or the last packet) ends the
  /// capture as failed. Same 1 s rule the Demo page uses for "data lost".
  final int noDataTimeoutMs;

  const ZeroLimits({
    this.windowMs = 1000,
    this.minSamples = 5,
    this.maxGapMs = 350,
    this.gyroRangeDps = 5.0,
    this.accelRangeG = 0.08,
    this.noDataTimeoutMs = 1000,
  });
}

/// Outcome of one zero capture, successful or not. Always carries the full
/// numbers so the UI can show why a capture was rejected.
class ZeroResult {
  final bool ok;

  /// First violated rule (e.g. "Gyro X 波動 6.20°/s > 5.00"), or success text.
  final String reason;

  /// Valid samples used for the averages.
  final int samples;
  final int invalidSamples;

  /// Receive time span from first to last packet in the window.
  final int windowMs;

  /// Largest packet interval seen (or silence length when it timed out).
  final int maxGapMs;

  /// Per-axis max-min, X/Y/Z. Zeros when there were no valid samples.
  final List<double> gyroRangeDps;
  final List<double> accelRangeG;

  /// Averages over the valid samples. Applied to the estimator only if [ok].
  final List<double> gyroBiasDps;
  final List<double> meanAccelG;

  /// Average of |a| (g); initial vertical-acceleration baseline.
  final double meanNormG;

  final ZeroLimits limits;

  const ZeroResult({
    required this.ok,
    required this.reason,
    required this.samples,
    required this.invalidSamples,
    required this.windowMs,
    required this.maxGapMs,
    required this.gyroRangeDps,
    required this.accelRangeG,
    required this.gyroBiasDps,
    required this.meanAccelG,
    required this.meanNormG,
    required this.limits,
  });
}

/// Collects about one second of packets after a zero request and judges it.
///
/// Rules (all thresholds in [ZeroLimits]):
/// - The window starts at the first packet after [start]; it ends with the
///   first packet whose receive time is >= windowMs after that.
/// - No packet for > noDataTimeoutMs ends the capture as failed, checked on
///   each packet ([add]) and by the page timer ([expire]).
/// - At window end the first violation wins, in this order: invalid packet,
///   packet interval, sample count, gyro X/Y/Z range, accel X/Y/Z range.
/// - No automatic retry: after a result, [active] is false until [start].
class ZeroCapture {
  ZeroCapture({this.limits = const ZeroLimits()});

  final ZeroLimits limits;

  bool _active = false;
  DateTime? _lastActivity, _first, _previous;
  int _maxGapUs = 0, _invalid = 0;
  final List<List<double>> _accel = [], _gyro = [];

  bool get active => _active;

  /// Packets received in the current window (valid or not).
  int get packetCount => _accel.length + _invalid;

  /// Requests a capture; collection starts with the next packet.
  void start(DateTime now) {
    _active = true;
    _lastActivity = now;
    _first = _previous = null;
    _maxGapUs = 0;
    _invalid = 0;
    _accel.clear();
    _gyro.clear();
  }

  /// Feeds one packet. Returns the result when this packet ends the capture.
  ZeroResult? add(Gy521Sample sample) {
    if (!_active) return null;
    final silenceUs = sample.at.difference(_lastActivity!).inMicroseconds;
    if (silenceUs > limits.noDataTimeoutMs * 1000) {
      return _finish(_noData(silenceUs), silenceUs);
    }
    _lastActivity = sample.at;
    final previous = _previous;
    if (previous != null) {
      _maxGapUs = math.max(
        _maxGapUs,
        sample.at.difference(previous).inMicroseconds,
      );
    }
    _first ??= sample.at;
    _previous = sample.at;
    if (sample.valid) {
      _accel.add(sample.accelG);
      _gyro.add(sample.gyroDps);
    } else {
      _invalid++;
    }
    if (sample.at.difference(_first!).inMilliseconds < limits.windowMs) {
      return null;
    }
    return _finish(_violation(), _maxGapUs);
  }

  /// Called periodically (page timer). Fails the capture when no packet has
  /// arrived for > noDataTimeoutMs.
  ZeroResult? expire(DateTime now) {
    if (!_active) return null;
    final silenceUs = now.difference(_lastActivity!).inMicroseconds;
    if (silenceUs <= limits.noDataTimeoutMs * 1000) return null;
    return _finish(_noData(silenceUs), silenceUs);
  }

  String _noData(int silenceUs) =>
      tr("資料中斷：{0} ms 沒有收到封包", [(silenceUs / 1000).round()]);

  /// First violated rule at window end, or null when every rule passes.
  String? _violation() {
    if (_invalid > 0) return tr("收到 {0} 筆無效六軸資料", [_invalid]);
    final gapMs = (_maxGapUs / 1000).round();
    if (_maxGapUs > limits.maxGapMs * 1000) {
      return tr("封包間隔 {0} ms > {1}", [gapMs, limits.maxGapMs]);
    }
    if (_accel.length < limits.minSamples) {
      return tr("樣本數 {0} < {1}", [_accel.length, limits.minSamples]);
    }
    const axes = ['X', 'Y', 'Z'];
    final gyroRange = _ranges(_gyro);
    for (var i = 0; i < 3; i++) {
      if (gyroRange[i] > limits.gyroRangeDps) {
        return tr("Gyro {0} 波動 {1}°/s > {2}", [
          axes[i],
          gyroRange[i].toStringAsFixed(2),
          limits.gyroRangeDps.toStringAsFixed(2),
        ]);
      }
    }
    final accelRange = _ranges(_accel);
    for (var i = 0; i < 3; i++) {
      if (accelRange[i] > limits.accelRangeG) {
        return tr("Accel {0} 波動 {1} g > {2}", [
          axes[i],
          accelRange[i].toStringAsFixed(3),
          limits.accelRangeG.toStringAsFixed(3),
        ]);
      }
    }
    return null;
  }

  ZeroResult _finish(String? violation, int gapUs) {
    _active = false;
    final n = _accel.length;
    List<double> mean(List<List<double>> rows) => List.generate(
      3,
      (i) => n == 0 ? 0.0 : rows.fold(0.0, (s, r) => s + r[i]) / n,
    );
    final meanNorm =
        n == 0
            ? 0.0
            : _accel.fold(
                  0.0,
                  (s, a) =>
                      s + math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]),
                ) /
                n;
    final first = _first, last = _previous;
    return ZeroResult(
      ok: violation == null,
      reason: violation ?? tr("歸零完成"),
      samples: n,
      invalidSamples: _invalid,
      windowMs:
          first == null || last == null
              ? 0
              : last.difference(first).inMilliseconds,
      maxGapMs: (gapUs / 1000).round(),
      gyroRangeDps: _ranges(_gyro),
      accelRangeG: _ranges(_accel),
      gyroBiasDps: mean(_gyro),
      meanAccelG: mean(_accel),
      meanNormG: meanNorm,
      limits: limits,
    );
  }

  static List<double> _ranges(List<List<double>> rows) => List.generate(3, (i) {
    if (rows.isEmpty) return 0.0;
    var lo = rows.first[i], hi = rows.first[i];
    for (final r in rows) {
      lo = math.min(lo, r[i]);
      hi = math.max(hi, r[i]);
    }
    return hi - lo;
  });
}
