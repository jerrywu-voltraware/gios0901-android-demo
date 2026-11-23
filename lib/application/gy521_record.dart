import 'orientation.dart';
import 'gy521_sample.dart';
import 'tilt_estimator.dart';

/// GY521 Demo recording format (one CSV line per event, captured from logcat
/// tag `flutter` by `tools/gy521_capture.ps1`; no header line):
///
/// ```
/// GY521PKT,<t_ms>,<rssi_dbm>,<valid>,<ax_mg>,<ay_mg>,<az_mg>,<gx_cdps>,<gy_cdps>,<gz_cdps>
/// GY521POSE,<t_ms>,<rssi_dbm>,<valid>,<w>,<x>,<y>,<z>,<norm_units>,<flags>,<epoch>
/// GY521OUT,<t_ms>,<roll_deg>,<pitch_deg>,<yaw_deg>,<yaw_stale>,<v_g>,<zeroed>
/// GY521ZERO,<t_ms>
/// ```
///
/// - `t_ms`: APP receive time, Unix epoch milliseconds with 3 decimals
///   (microsecond resolution, so a replay sees exactly the same dt).
///   GY521OUT / GY521PKT of the same packet share the same `t_ms`;
///   GY521ZERO uses the time the zero was requested.
/// - GY521PKT: every advertising report of the traced device, logged in the
///   scan controller BEFORE the 100 ms UI throttle. `valid` = payload six-axis
///   flag (0/1). Axes are raw payload values: acceleration in mg, angular rate
///   in 0.01 deg/s (`cdps`); empty when the payload has no six-axis fields.
/// - GY521POSE: v2 quaternion snapshots; norm_units = |a| / 0.02 g.
/// - GY521OUT: estimator output for each packet the Demo processed, directly
///   from selected reports before list throttling. Angles in degrees (3
///   decimals), `v_g` = magnitude minus baseline in g before the display
///   dead band (4 decimals). `nan` when
///   unavailable (roll/pitch without gravity, yaw before the first zero, v
///   after invalid data). `yaw_stale`, `zeroed`: 0/1.
/// - GY521ZERO: a zero capture was requested (auto on Demo entry or the
///   "歸零" button).
abstract final class Gy521Record {
  static const packetTag = 'GY521PKT';
  static const outTag = 'GY521OUT';
  static const zeroTag = 'GY521ZERO';

  static String formatTime(DateTime at) {
    final us = at.microsecondsSinceEpoch;
    return '${us ~/ 1000}.${(us % 1000).toString().padLeft(3, '0')}';
  }

  static DateTime? parseTime(String text) {
    final parts = text.trim().split('.');
    final ms = int.tryParse(parts[0]);
    if (ms == null || parts.length > 2) return null;
    var us = 0;
    if (parts.length == 2) {
      final frac = parts[1].padRight(3, '0');
      if (frac.length != 3) return null;
      final parsed = int.tryParse(frac);
      if (parsed == null) return null;
      us = parsed;
    }
    return DateTime.fromMicrosecondsSinceEpoch(ms * 1000 + us);
  }

  static String packetLine(Gy521Sample s, int rssi) =>
      s.firmwarePose
          ? [
            'GY521POSE',
            formatTime(s.at),
            rssi,
            s.sixAxisValid ? 1 : 0,
            s.pose?.w ?? '',
            s.pose?.x ?? '',
            s.pose?.y ?? '',
            s.pose?.z ?? '',
            s.poseNormUnits,
            s.poseFlags,
            s.poseEpoch,
          ].join(',')
          : [
            packetTag,
            formatTime(s.at),
            rssi,
            s.sixAxisValid ? 1 : 0,
            ...s.rawAxes.map((v) => v ?? ''),
          ].join(',');

  static String outLine(DateTime at, TiltEstimator e) {
    String num(double? v, int digits) =>
        v == null ? 'nan' : v.toStringAsFixed(digits);
    return [
      outTag,
      formatTime(at),
      num(e.roll, 3),
      num(e.pitch, 3),
      num(e.yaw, 3),
      e.yawStale ? 1 : 0,
      num(e.vertical.valueG, 4),
      e.zeroed ? 1 : 0,
    ].join(',');
  }

  static String zeroLine(DateTime at) => '$zeroTag,${formatTime(at)}';

  /// Strips any logcat prefix ("I/flutter (123): ") and returns the record,
  /// or null when the line holds none.
  static String? recordOf(String line) {
    final i = line.indexOf('GY521');
    return i < 0 ? null : line.substring(i).trim();
  }

  /// Parses a GY521PKT record; null when [record] is not a valid one.
  static Gy521Sample? parsePacket(String record) {
    final f = record.split(',');
    if (f.length == 11 && f[0] == 'GY521POSE') {
      final at = parseTime(f[1]);
      final q = f.sublist(4, 8).map(double.tryParse).toList();
      final epoch = int.tryParse(f[10]);
      if (at == null || epoch == null) return null;
      final present = q.every((v) => v != null && v.isFinite);
      return Gy521Sample(
        at: at,
        sixAxisValid: f[3] == '1',
        pose: present ? Orientation(q[0]!, q[1]!, q[2]!, q[3]!) : null,
        poseNormUnits: int.tryParse(f[8]),
        poseFlags: int.tryParse(f[9]),
        poseEpoch: epoch,
      );
    }
    if (f.length != 10 || f[0] != packetTag) return null;
    final at = parseTime(f[1]);
    if (at == null) return null;
    int? axis(String v) => v.trim().isEmpty ? null : int.tryParse(v.trim());
    return Gy521Sample(
      at: at,
      sixAxisValid: f[3].trim() == '1',
      axMg: axis(f[4]),
      ayMg: axis(f[5]),
      azMg: axis(f[6]),
      gxCdps: axis(f[7]),
      gyCdps: axis(f[8]),
      gzCdps: axis(f[9]),
    );
  }

  /// Re-runs the estimator on a recording and returns new GY521OUT lines.
  ///
  /// - GY521ZERO lines start a zero capture at their time, in file order.
  /// - If the recording contains GY521OUT lines, only the packets the Demo
  ///   actually processed are fed (the GY521PKT whose `t_ms` matches each
  ///   GY521OUT, at that OUT's position), so the output is comparable line by
  ///   line with the recorded OUT. Otherwise every GY521PKT is fed in order.
  static List<String> replay(Iterable<String> lines) {
    final records = lines.map(recordOf).whereType<String>().toList();
    final packets = <int, Gy521Sample>{};
    for (final r in records) {
      final s = parsePacket(r);
      if (s != null) packets[s.at.microsecondsSinceEpoch] = s;
    }
    final outDriven = records.any((r) => r.startsWith('$outTag,'));
    final estimator = TiltEstimator();
    final out = <String>[];
    void feed(Gy521Sample? s) {
      if (s != null && estimator.update(s)) out.add(outLine(s.at, estimator));
    }

    for (final r in records) {
      final f = r.split(',');
      if (f[0] == zeroTag && f.length >= 2) {
        final at = parseTime(f[1]);
        if (at != null) estimator.startZero(at);
      } else if (outDriven && f[0] == outTag && f.length >= 2) {
        final at = parseTime(f[1]);
        if (at != null) feed(packets[at.microsecondsSinceEpoch]);
      } else if (!outDriven && (f[0] == packetTag || f[0] == 'GY521POSE')) {
        feed(parsePacket(r));
      }
    }
    return out;
  }
}
