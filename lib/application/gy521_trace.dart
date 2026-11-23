import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../data/ble/adv_parser.dart';
import '../data/models/pru_adv_data.dart';
import '../data/models/pru_device.dart';
import 'gy521_record.dart';
import 'gy521_sample.dart';
import 'tilt_estimator.dart';

/// Converts a parsed advertisement into the estimator's pure-Dart sample.
Gy521Sample gy521SampleOf(PruAdvData? data, DateTime at) => Gy521Sample(
  at: at,
  pose: data?.pose,
  poseEpoch: data?.poseEpoch,
  poseFlags: data?.poseFlags,
  poseNormUnits: data?.poseNormUnits,
  sixAxisValid: data?.sixAxisValid ?? false,
  axMg: data?.accelXMg,
  ayMg: data?.accelYMg,
  azMg: data?.accelZMg,
  gxCdps: data?.gyroXCentiDps,
  gyCdps: data?.gyroYCentiDps,
  gzCdps: data?.gyroZCentiDps,
);

/// GY521 Demo recording switch. While [enabled], packets of [deviceId] and
/// the Demo's estimator outputs are written with `debugPrint` (logcat tag
/// `flutter`) in the [Gy521Record] line format. The Demo page enables it on
/// entry and disables it on exit; nothing is stored on the phone.
abstract final class Gy521Trace {
  static bool enabled = false;
  static String? deviceId;

  /// Output sink; tests may replace it.
  static void Function(String line) sink = _debugPrint;
  static void _debugPrint(String line) => debugPrint(line);

  static DateTime? _lastPacketAt;

  static void start(String id) {
    enabled = true;
    deviceId = id;
    _lastPacketAt = null;
  }

  static void stop() {
    enabled = false;
    deviceId = null;
    _lastPacketAt = null;
  }

  /// Scan controller hook, called with every raw result list before the
  /// UI throttle. The platform re-sends earlier results of other devices, so
  /// a report is logged once per receive timestamp.
  static void onScanResults(List<ScanResult> results) {
    if (!enabled) return;
    for (final r in results) {
      if (r.device.remoteId.str != deviceId || r.timeStamp == _lastPacketAt) {
        continue;
      }
      final device = AdvParser.fromScanResult(r);
      if (device != null) packet(device);
    }
  }

  /// Logs one GY521PKT line for [device] unless already logged.
  static void packet(PruDevice device) {
    if (!enabled || device.id != deviceId || device.lastSeen == _lastPacketAt) {
      return;
    }
    _lastPacketAt = device.lastSeen;
    sink(
      Gy521Record.packetLine(
        gy521SampleOf(device.advData, device.lastSeen),
        device.rssi,
      ),
    );
  }

  /// Logs one GY521OUT line after the estimator processed a packet.
  static void output(DateTime at, TiltEstimator estimator) {
    if (enabled) sink(Gy521Record.outLine(at, estimator));
  }

  /// Logs a GY521ZERO line when a zero capture is requested.
  static void zero(DateTime at) {
    if (enabled) sink(Gy521Record.zeroLine(at));
  }
}
