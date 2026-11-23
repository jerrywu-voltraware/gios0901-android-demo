import 'package:gios0901/core/localization/translations.dart';
import 'dart:math' as math;
import 'gy521_sample.dart';
import 'orientation.dart';
import 'zero_capture.dart';

/// Full hardware-integrated snapshots. Receive timing never integrates angles.
class FirmwarePose {
  Orientation? pose, reference, _firstPose;
  int? epoch;
  bool valid = false, active = false, _autoStarted = false;
  int packets = 0;
  DateTime? _requested, _first, _last;
  ZeroResult? result;
  double _norm = 1;

  bool get zeroed => reference != null;

  /// Sets a display reference, without recalibrating the board's gyro bias.
  bool zeroCurrent() {
    if (!valid || pose == null) return false;
    reference = pose;
    packets = 1;
    _first = _last = null;
    _finish(true, tr("已設定目前姿態為參考"));
    return true;
  }

  Orientation? get orientation =>
      valid
          ? ((reference?.inverse ?? Orientation.identity) * pose!).normalized
          : null;

  void start(DateTime at) {
    active = true;
    _requested = at;
    _first = _last = null;
    _firstPose = null;
    packets = 0;
  }

  void update(Gy521Sample s) {
    if (epoch != null && epoch != s.poseEpoch) {
      reference = null;
      active = false;
      _finish(false, tr("板端姿態已重設，請放穩後重新歸零"));
    }
    epoch = s.poseEpoch;
    valid = s.valid;
    if (!valid) {
      if (active) _finish(false, tr("板端校準中或資料無效，請放穩後再歸零"));
      return;
    }
    pose = s.pose!.normalized;
    _norm = s.accelNormG;
    if (!_autoStarted) {
      _autoStarted = true;
      start(s.at);
    }
    if (!active) return;
    if (!s.poseStationary) {
      _finish(false, tr("請將板子放穩至少 2 秒，再按歸零"));
      return;
    }
    // Snapshot zero does not integrate receive intervals. Keep the same 1 s
    // freshness limit as the page, allowing ordinary 400-700 ms radio gaps.
    if (_last != null && s.at.difference(_last!).inMilliseconds > 1000) {
      _finish(false, tr("歸零期間接收中斷，請重試"));
      return;
    }
    _first ??= s.at;
    _firstPose ??= pose;
    final delta = _firstPose!.inverse * pose!;
    final angle = 2 * math.acos(delta.w.abs().clamp(0.0, 1.0));
    if (angle > math.pi / 360) {
      _finish(false, tr("歸零期間板子有轉動，請重試"));
      return;
    }
    _last = s.at;
    packets++;
    if (s.at.difference(_first!).inMilliseconds >= 1000) {
      if (packets >= 5) {
        reference = pose;
        _finish(true, tr("板端姿態歸零完成"));
      } else if (s.at.difference(_first!).inMilliseconds >= 3000) {
        _finish(false, tr("歸零樣本不足，請重試"));
      }
    }
  }

  bool expire(DateTime at) {
    if (!active || at.difference(_last ?? _requested!).inMilliseconds <= 1000) {
      return false;
    }
    _finish(false, tr("歸零期間沒有收到資料"));
    return true;
  }

  void _finish(bool ok, String reason) {
    active = false;
    result = ZeroResult(
      ok: ok,
      reason: reason,
      samples: packets,
      invalidSamples: 0,
      windowMs:
          _first == null || _last == null
              ? 0
              : _last!.difference(_first!).inMilliseconds,
      maxGapMs: 0,
      gyroRangeDps: const [0, 0, 0],
      accelRangeG: const [0, 0, 0],
      gyroBiasDps: const [0, 0, 0],
      meanAccelG: const [0, 0, 0],
      meanNormG: _norm,
      limits: const ZeroLimits(),
    );
  }
}
