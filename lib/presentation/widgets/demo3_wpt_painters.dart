import 'package:gios0901/core/localization/translations.dart';
import 'package:gios0901/core/localization/locale_state.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart' hide Orientation;
import '../../application/orientation.dart';

const _bluePrimary = Color(0xFF1D4ED8);

const _greenGood = Color(0xFF16A34A);
const _electricCyan = Color(0xFF0284C7);
const _electricGold = Color(0xFFF59E0B);
const _copperCoil = Color(0xFFB45309);
const _amberWarn = Color(0xFFD97706);

const _slateMuted = Color(0xFF64748B);

void _paintText(
  Canvas canvas,
  String text,
  Offset pos, {
  Color color = _slateMuted,
  double fontSize = 10.5,
  FontWeight fontWeight = FontWeight.w600,
  Alignment align = Alignment.topLeft,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final dx = pos.dx - (align.x + 1) * 0.5 * tp.width;
  final dy = pos.dy - (align.y + 1) * 0.5 * tp.height;
  tp.paint(canvas, Offset(dx, dy));
}

/// Draws a crisp lightning bolt icon centered at [center] with height [size].
void _drawLightningBolt(
  Canvas canvas,
  Offset center,
  double size,
  Color fill, {
  Color? haloColor,
}) {
  final h = size * 0.5;
  final w = size * 0.34;
  final bolt =
      Path()
        ..moveTo(center.dx + w * 0.18, center.dy - h)
        ..lineTo(center.dx - w * 0.85, center.dy + h * 0.08)
        ..lineTo(center.dx - w * 0.05, center.dy + h * 0.08)
        ..lineTo(center.dx - w * 0.25, center.dy + h)
        ..lineTo(center.dx + w * 0.85, center.dy - h * 0.10)
        ..lineTo(center.dx + w * 0.05, center.dy - h * 0.10)
        ..close();

  if (haloColor != null) {
    canvas.drawCircle(center, size * 0.62, Paint()..color = haloColor);
  }
  canvas.drawPath(bolt, Paint()..color = fill);
  canvas.drawPath(
    bolt,
    Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8,
  );
}

/// Mode 1: Visual Wireless Power Transfer (Energy Wave Rings, Comet Streams & Lightning).
class WptFluxFieldPainter extends LanguageAwarePainter {
  final Orientation pose;
  final bool live;
  final bool dark;
  final double phase;
  final double? vrectV;
  final bool charging;

  WptFluxFieldPainter({
    required this.pose,
    required this.live,
    this.dark = false,
    required this.phase,
    required this.vrectV,
    required this.charging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final blue = dark ? const Color(0xFF93B8FF) : _bluePrimary;
    final muted = dark ? const Color(0xFFA3B5CC) : _slateMuted;
    final green = dark ? const Color(0xFF69DB96) : _greenGood;
    final cyan = dark ? const Color(0xFF67D4FF) : _electricCyan;
    final copper = dark ? const Color(0xFFFFAC64) : _copperCoil;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = (dark ? const Color(0xff111923) : const Color(0xFFFBFCFD)),
    );

    final cx = size.width * 0.5;
    // Fit the rotated board between the two captions without cropping its corners.
    double verticalProjection(double x, double y, double z) {
      final axis = pose.rotate([x, y, z]);
      return axis[1] * 0.38 - axis[2] * 0.84;
    }

    final boardHalfHeight =
        verticalProjection(1, 0, 0).abs() +
        0.62 * verticalProjection(0, 1, 0).abs() +
        0.06 * verticalProjection(0, 0, 1).abs();
    const sceneTop = 26.0;
    final sceneBottom = size.height - 22;
    final sceneHeight = math.max(1.0, sceneBottom - sceneTop);
    const padHalfHeight = 0.62 * 1.15 / 2;
    const padWidth = 2.25 * 1.08;
    final scale = math.min(
      size.width * 0.91 / padWidth,
      sceneHeight / (2 * boardHalfHeight + 2 * padHalfHeight + 0.18),
    );
    final txCenterY = sceneBottom - scale * padHalfHeight;
    final freeHeight =
        sceneHeight - 2 * scale * (boardHalfHeight + padHalfHeight);
    final rxCenterY = sceneTop + scale * boardHalfHeight + freeHeight * 0.15;
    final normal = pose.rotate(const [0, 0, 1]);
    final cosTheta = normal[2].abs().clamp(0.0, 1.0);

    Offset projectRx(double x, double y, [double z = 0]) {
      final v = pose.rotate([x, y, z]);
      return Offset(
        cx + scale * (v[0] + v[1] * 0.18),
        rxCenterY + scale * (v[1] * 0.38 - v[2] * 0.84),
      );
    }

    final rxCenter = projectRx(0, 0, 0);
    final txCenter = Offset(cx, txCenterY);
    final powerColor = !live ? muted : (cosTheta >= 0.94 ? green : cyan);

    // 1. Central Wireless Power Beam Core (Soft Energy Column between TX & RX)
    if (live) {
      final topSpan = scale * 0.68 * math.max(0.30, cosTheta);
      final botSpan = scale * 0.86;
      final beamPath =
          Path()
            ..moveTo(txCenter.dx - botSpan, txCenter.dy)
            ..lineTo(rxCenter.dx - topSpan, rxCenter.dy + 6)
            ..lineTo(rxCenter.dx + topSpan, rxCenter.dy + 6)
            ..lineTo(txCenter.dx + botSpan, txCenter.dy)
            ..close();
      final beamRect = Rect.fromPoints(
        Offset(cx - botSpan, rxCenterY),
        Offset(cx + botSpan, txCenterY),
      );
      canvas.drawPath(
        beamPath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              powerColor.withValues(alpha: 0.18 * cosTheta),
              powerColor.withValues(alpha: 0.08 * cosTheta),
              powerColor.withValues(alpha: 0.22 * cosTheta),
            ],
          ).createShader(beamRect),
      );
    }

    // 2. Fixed TX Charging Pad (Bottom)
    final txOuterW = scale * 2.25;
    final txOuterH = scale * 0.62;
    final txPadRect = Rect.fromCenter(
      center: txCenter,
      width: txOuterW * 1.08,
      height: txOuterH * 1.15,
    );
    canvas.drawOval(
      txPadRect,
      Paint()
        ..color = (dark ? const Color(0xff203149) : const Color(0xFFEFF6FF)),
    );
    canvas.drawOval(
      txPadRect,
      Paint()
        ..color = blue.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    for (final r in [0.92, 0.72, 0.52]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: txCenter,
          width: txOuterW * r,
          height: txOuterH * r,
        ),
        Paint()
          ..color =
              live
                  ? blue.withValues(alpha: 0.55)
                  : muted.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }

    // 3. Expanding Wireless Energy Wave Rings rising from TX to RX!
    if (live) {
      for (var w = 0; w < 3; w++) {
        final t = (phase + w / 3.0) % 1.0;
        final waveCenter = Offset.lerp(txCenter, rxCenter, t)!;
        final widthScale =
            (1.0 - t * 0.28) * (0.45 + 0.55 * math.max(0.35, cosTheta));
        final waveW = txOuterW * 0.85 * widthScale;
        final waveH = txOuterH * 0.78 * widthScale;
        final alpha = math.sin(t * math.pi) * 0.55 * cosTheta;

        final waveRect = Rect.fromCenter(
          center: waveCenter,
          width: waveW,
          height: waveH,
        );
        canvas.drawOval(
          waveRect,
          Paint()
            ..color = powerColor.withValues(alpha: alpha.clamp(0.05, 0.65))
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4,
        );
      }
    }

    // 4. Power Transfer Streams (Comet Energy Streaks + Rising Lightning Bolts)
    final effectiveHalfSpan = scale * 0.85 * math.max(0.22, cosTheta);
    const streamOffsets = [-0.82, -0.48, -0.18, 0.0, 0.18, 0.48, 0.82];

    for (var idx = 0; idx < streamOffsets.length; idx++) {
      final normX = streamOffsets[idx];
      final startX = cx + normX * scale * 0.88;
      final startY = txCenterY - 4;
      final rxTarget = projectRx(normX * 0.82, 0);
      final isCaptured = (startX - cx).abs() <= effectiveHalfSpan + 4;
      final liveFactor = live ? 1.0 : 0.35;

      final startPt = Offset(startX, startY);
      if (isCaptured) {
        final ctrl1 = Offset(startX, startY - (startY - rxTarget.dy) * 0.45);
        final ctrl2 = Offset(
          rxTarget.dx,
          rxTarget.dy + (startY - rxTarget.dy) * 0.35,
        );
        final guidePath =
            Path()
              ..moveTo(startPt.dx, startPt.dy)
              ..cubicTo(
                ctrl1.dx,
                ctrl1.dy,
                ctrl2.dx,
                ctrl2.dy,
                rxTarget.dx,
                rxTarget.dy,
              );
        // Subtle carrier guide line
        canvas.drawPath(
          guidePath,
          Paint()
            ..color = powerColor.withValues(alpha: 0.18 * liveFactor)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );

        if (live) {
          // Glowing Energy Comet Streak moving up the stream
          final headT = (phase + idx * 0.17) % 1.0;
          const tailLength = 0.22;
          const segments = 6;
          for (var s = 0; s < segments; s++) {
            final t0 = (headT - (s + 1) * (tailLength / segments)).clamp(
              0.0,
              1.0,
            );
            final t1 = (headT - s * (tailLength / segments)).clamp(0.0, 1.0);
            if (t1 <= t0) continue;
            final p0 = _evalCubic(startPt, ctrl1, ctrl2, rxTarget, t0);
            final p1 = _evalCubic(startPt, ctrl1, ctrl2, rxTarget, t1);
            final segFraction = 1.0 - s / segments;
            canvas.drawLine(
              p0,
              p1,
              Paint()
                ..color = powerColor.withValues(alpha: 0.78 * segFraction)
                ..strokeWidth = 1.5 + 2.8 * segFraction
                ..strokeCap = StrokeCap.round,
            );
          }

          // Draw rising lightning bolt on center and mid streams, energy orb on others
          final headPt = _evalCubic(startPt, ctrl1, ctrl2, rxTarget, headT);
          if (idx.isOdd || normX == 0.0) {
            _drawLightningBolt(
              canvas,
              headPt,
              13.5,
              _electricGold,
              haloColor: powerColor.withValues(alpha: 0.22),
            );
          } else {
            canvas.drawCircle(
              headPt,
              5.5,
              Paint()..color = powerColor.withValues(alpha: 0.24),
            );
            canvas.drawCircle(headPt, 3.0, Paint()..color = _electricGold);
          }
        }
      } else {
        // Escaping / Leaking power arc ONLY when board is tilted too far
        final sign = normX == 0 ? 1.0 : normX.sign;
        final endPt = Offset(
          startX + sign * scale * 0.42,
          rxCenterY + scale * 0.20,
        );
        final ctrl = Offset(
          startX + sign * scale * 0.14,
          (startY + endPt.dy) * 0.5,
        );
        // Dashed leakage arc
        for (var seg = 0; seg < 5; seg++) {
          final tA = seg * 0.20;
          final tB = tA + 0.11;
          final pA = _evalQuad(startPt, ctrl, endPt, tA);
          final pB = _evalQuad(startPt, ctrl, endPt, tB);
          canvas.drawLine(
            pA,
            pB,
            Paint()
              ..color = _amberWarn.withValues(alpha: 0.55 * liveFactor)
              ..strokeWidth = 1.5
              ..strokeCap = StrokeCap.round,
          );
        }
      }
    }

    // 5. Movable 3D RX Board & Glowing Receiving Coil
    final rxTop = [
      projectRx(-1.0, -0.62, 0),
      projectRx(1.0, -0.62, 0),
      projectRx(1.0, 0.62, 0),
      projectRx(-1.0, 0.62, 0),
    ];
    final rxBot = [
      projectRx(-1.0, -0.62, -0.06),
      projectRx(1.0, -0.62, -0.06),
      projectRx(1.0, 0.62, -0.06),
      projectRx(-1.0, 0.62, -0.06),
    ];
    for (var i = 0; i < 4; i++) {
      canvas.drawPath(
        Path()..addPolygon([
          rxTop[i],
          rxTop[(i + 1) % 4],
          rxBot[(i + 1) % 4],
          rxBot[i],
        ], true),
        Paint()
          ..color = live ? const Color(0xFF94A3B8) : const Color(0xFFCBD5E1),
      );
    }

    final rxPoly = Path()..addPolygon(rxTop, true);
    canvas.drawPath(
      rxPoly,
      Paint()
        ..color =
            dark
                ? const Color(0xff283743)
                : live
                ? const Color(0xFFF8FAFC)
                : const Color(0xFFF1F5F9),
    );
    canvas.drawPath(
      rxPoly,
      Paint()
        ..color = powerColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );

    // Receiving power glow inside RX coil
    if (live) {
      final pulseAlpha =
          (0.16 + 0.12 * math.sin(phase * math.pi * 2)) * cosTheta;
      final innerGlow = Path();
      for (var i = 0; i <= 48; i++) {
        final a = i * math.pi * 2 / 48;
        final pt = projectRx(0.74 * math.cos(a), 0.74 * 0.54 * math.sin(a));
        if (i == 0) {
          innerGlow.moveTo(pt.dx, pt.dy);
        } else {
          innerGlow.lineTo(pt.dx, pt.dy);
        }
      }
      canvas.drawPath(
        innerGlow,
        Paint()..color = powerColor.withValues(alpha: pulseAlpha),
      );
    }

    // Secondary copper coil windings on RX board
    for (final radius in [0.76, 0.60, 0.44]) {
      final coilPath = Path();
      for (var i = 0; i <= 60; i++) {
        final a = i * math.pi * 2 / 60;
        final pt = projectRx(radius * math.cos(a), radius * 0.54 * math.sin(a));
        if (i == 0) {
          coilPath.moveTo(pt.dx, pt.dy);
        } else {
          coilPath.lineTo(pt.dx, pt.dy);
        }
      }
      canvas.drawPath(
        coilPath,
        Paint()
          ..color =
              live
                  ? copper.withValues(alpha: 0.85)
                  : muted.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.7,
      );
    }

    // Central receiving lightning badge on RX board
    if (live) {
      _drawLightningBolt(
        canvas,
        rxCenter,
        15.0,
        _electricGold,
        haloColor: powerColor.withValues(alpha: 0.25),
      );
    }

    // 6. Friendly, Non-Technical HUD Labels
    _paintText(
      canvas,
      tr("上方接收板 (RX)"),
      const Offset(10, 8),
      color: powerColor,
      fontSize: 11,
      fontWeight: FontWeight.w700,
    );
    _paintText(
      canvas,
      tr("下方發射座 (TX) · 接收電壓 {0} {1}", [
        vrectV == null ? "--" : "${vrectV!.toStringAsFixed(1)}V",
        charging ? tr("· 充電中") : "",
      ]),
      Offset(10, size.height - 19),
      color: blue,
      fontSize: 10,
    );
  }

  Offset _evalCubic(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
    final u = 1 - t;
    final b0 = u * u * u;
    final b1 = 3 * u * u * t;
    final b2 = 3 * u * t * t;
    final b3 = t * t * t;
    return Offset(
      b0 * p0.dx + b1 * p1.dx + b2 * p2.dx + b3 * p3.dx,
      b0 * p0.dy + b1 * p1.dy + b2 * p2.dy + b3 * p3.dy,
    );
  }

  Offset _evalQuad(Offset p0, Offset p1, Offset p2, double t) {
    final u = 1 - t;
    return Offset(
      u * u * p0.dx + 2 * u * t * p1.dx + t * t * p2.dx,
      u * u * p0.dy + 2 * u * t * p1.dy + t * t * p2.dy,
    );
  }

  @override
  bool shouldRepaint(covariant WptFluxFieldPainter old) =>
      old.dark != dark ||
      old.pose != pose ||
      old.live != live ||
      old.phase != phase ||
      old.vrectV != vrectV ||
      old.charging != charging;
}
