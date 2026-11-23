import 'dart:collection';
import 'dart:math' as math;

import 'gy521_sample.dart';

/// Delivery statistics of the packets the Demo actually processed (after
/// the scan controller's 100 ms throttle). Engineering diagnostics only; does
/// not influence estimation.
///
/// The advertising payload has no sequence number, so lost packets show up
/// only as receive-time gaps, and duplicates are detected as all 12 six-axis
/// bytes equal to the previous packet (sensor noise makes that rare for real
/// new samples).
class LinkStats {
  /// Window for [rateHz] and [maxGapMs], on receive timestamps.
  static const int windowMs = 5000;

  final _recent = ListQueue<({DateTime at, int? gapUs})>();
  Gy521Sample? _previous;
  int _packets = 0, _duplicates = 0;

  /// Packets processed since creation.
  int get packets => _packets;

  /// Packets whose six axes equal the previous packet's, since creation.
  int get duplicates => _duplicates;

  /// Interval between the last two packets.
  int? get lastDtMs {
    final gap = _recent.isEmpty ? null : _recent.last.gapUs;
    return gap == null ? null : (gap / 1000).round();
  }

  /// Packets per second over the last [windowMs]; null with < 2 packets.
  double? get rateHz {
    if (_recent.length < 2) return null;
    final spanUs = _recent.last.at.difference(_recent.first.at).inMicroseconds;
    return spanUs <= 0 ? null : (_recent.length - 1) * 1e6 / spanUs;
  }

  /// Largest interval ending inside the last [windowMs]; null if none.
  int? get maxGapMs {
    int? best;
    for (final e in _recent) {
      final gap = e.gapUs;
      if (gap != null) best = math.max(best ?? 0, gap);
    }
    return best == null ? null : (best / 1000).round();
  }

  void add(Gy521Sample sample) {
    final previous = _previous;
    if (previous != null && sample.sameAxesAs(previous)) _duplicates++;
    _packets++;
    final gapUs =
        previous == null
            ? null
            : sample.at.difference(previous.at).inMicroseconds;
    _previous = sample;
    _recent.addLast((at: sample.at, gapUs: gapUs));
    final cutoff = sample.at.subtract(const Duration(milliseconds: windowMs));
    while (_recent.first.at.isBefore(cutoff)) {
      _recent.removeFirst();
    }
  }
}
