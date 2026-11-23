import 'package:gios0901/core/localization/translations.dart';
import 'package:gios0901/core/localization/locale_state.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart' hide Orientation;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/gy521_trace.dart';
import '../../application/orientation.dart';
import '../../application/scan_controller.dart';
import '../../application/tilt_estimator.dart';
import '../../data/models/pru_device.dart';
import '../widgets/animated_rx_pose.dart';
import '../widgets/demo3_wpt_painters.dart';

/// DEMO 3: Wireless Charging Power Transfer Showcase (Friendly & Visual).
class SensorDemo3Page extends ConsumerStatefulWidget {
  final String deviceId;
  const SensorDemo3Page({super.key, required this.deviceId});

  @override
  ConsumerState<SensorDemo3Page> createState() => _SensorDemo3PageState();
}

class _SensorDemo3PageState extends ConsumerState<SensorDemo3Page> {
  ColorScheme get _scheme => Theme.of(context).colorScheme;
  bool get _dark => _scheme.brightness == Brightness.dark;
  Color get _primaryBlue =>
      _dark ? const Color(0xff9ec0ff) : const Color(0xff1d4ed8);
  Color get _tealEnergy =>
      _dark ? const Color(0xff5eead4) : const Color(0xff0d9488);
  Color get _copperCoil =>
      _dark ? const Color(0xfffdba74) : const Color(0xffb45309);
  Color get _greenGood =>
      _dark ? const Color(0xff86efac) : const Color(0xff15803d);
  Color get _ink => _scheme.onSurface;
  Color get _muted => _scheme.onSurfaceVariant;

  final _tilt = TiltEstimator();
  PruDevice? _device;
  StreamSubscription<PruDevice>? _reports;
  Timer? _timer;
  Orientation _pose = Orientation.identity;
  int _referenceToken = 0;
  double _fluxPhase = 0.0;
  static const _holdOverMs = 2500;

  bool get _fresh =>
      ref.read(scanControllerProvider).isScanning &&
      _device != null &&
      DateTime.now().difference(_device!.lastSeen).inMilliseconds <=
          _holdOverMs;

  bool get _live => _fresh && _tilt.valid;
  bool get _ready => _live && _tilt.zeroed && !_tilt.zeroActive;

  void _accept(PruDevice? d) {
    if (d == null ||
        (_device != null && !d.lastSeen.isAfter(_device!.lastSeen))) {
      return;
    }
    final oldEpoch = _tilt.hardware.epoch;
    final oldZero = _tilt.lastZero;
    final oldMode = _tilt.firmwareMode;
    final sample = gy521SampleOf(d.advData, d.lastSeen);
    if (!_tilt.update(sample)) return;
    _device = d;
    if (_tilt.firmwareMode && _tilt.valid && !_tilt.zeroed) {
      _tilt.zeroCurrentFirmwarePose();
    }
    if (_tilt.valid) _pose = _tilt.orientation!;
    if (oldEpoch != _tilt.hardware.epoch ||
        oldMode != _tilt.firmwareMode ||
        (oldZero != _tilt.lastZero && _tilt.lastZero?.ok == true)) {
      _referenceToken++;
    }
  }

  @override
  void initState() {
    super.initState();
    _accept(ref.read(scanControllerProvider).devices[widget.deviceId]);
    if (!_tilt.zeroed) {
      _tilt.startZero(DateTime.now());
    }
    _reports = ref
        .read(scanControllerProvider.notifier)
        .watchDeviceReports(widget.deviceId)
        .listen((d) {
          if (mounted) setState(() => _accept(d));
        });
    ref.listenManual(
      scanControllerProvider.select((s) => s.devices[widget.deviceId]),
      (_, next) {
        if (mounted) setState(() => _accept(next));
      },
    );
    _timer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      if (!mounted) return;
      setState(() {
        _tilt.expireZero(DateTime.now());
        if (_live) {
          _fluxPhase = (_fluxPhase + 0.05) % 1.0;
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _reports?.cancel();
    super.dispose();
  }

  void _zero() {
    if (!_live) return;
    setState(() {
      if (_tilt.firmwareMode) {
        if (_tilt.zeroCurrentFirmwarePose()) {
          _pose = _tilt.orientation!;
          _referenceToken++;
        }
      } else {
        _tilt.startZero(DateTime.now());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    watchLanguage(context);
    ref.watch(scanControllerProvider.select((s) => s.isScanning));
    final pose = _pose.normalized;
    final live = _live;
    final ready = _ready;
    final normal = pose.rotate(const [0, 0, 1]);
    final cosTheta = normal[2].abs().clamp(0.0, 1.0);
    final couplingPct = cosTheta * 100.0;
    final tiltDeg = math.acos(cosTheta) * 180 / math.pi;

    final rollDeg = pose.roll * 180 / math.pi;
    final pitchDeg = pose.pitch * 180 / math.pi;
    final yawDeg = pose.yaw * 180 / math.pi;
    final canZero = _live && (_tilt.firmwareMode || !_tilt.zeroActive);

    final adv = _device?.advData;
    final vrectV = adv == null ? 0.0 : adv.vrect / 1000.0;
    final vbatV = adv == null ? 0.0 : adv.vbat / 1000.0;
    final ioutMa = adv?.csout ?? 0;
    final pgOk = adv != null && !adv.pgHigh;
    final charging = adv != null && !adv.statHigh;
    final ceOn = adv?.ceHigh ?? false;

    final statusText =
        !_fresh
            ? tr("訊號暫停 · 保留最後畫面")
            : !_tilt.valid
            ? tr("感測器準備中 · 請將板子放平稍候")
            : _tilt.zeroActive
            ? tr("正在設定水平基準 · 請保持不動")
            : !_tilt.zeroed
            ? tr("請先將板子放平，再按右側「歸零」")
            : _dark
            ? "${tr(couplingPct >= 98.5
                ? '已對準'
                : couplingPct >= 90
                ? '角度良好'
                : '板子傾斜')} · ${tr(charging ? '充電中' : '待機')}"
            : couplingPct >= 98.5
            ? tr("完美平放對準 · 電力全速傳輸中")
            : couplingPct >= 90.0
            ? tr("角度良好 · 無線電力穩定接收中")
            : tr("板子傾斜較大 · 部分無線電力散失中");

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTopConnectionBar(
              live: live,
              statusText: statusText,
              canZero: canZero,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: CustomScrollView(
                  slivers: [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _buildWptStage(
                              pose: pose,
                              live: live,
                              ready: ready,
                              cosTheta: cosTheta,
                              couplingPct: couplingPct,
                              tiltDeg: tiltDeg,
                              vrectV: vrectV,
                              ioutMa: ioutMa,
                              charging: charging,
                            ),
                          ),
                          const SizedBox(height: 4),
                          _buildSectionHeader(tr("無線充電能量流程")),
                          _buildEnergyPipeline(
                            ready: ready,
                            fresh: _fresh,
                            couplingPct: couplingPct,
                            tiltDeg: tiltDeg,
                            vrectV: vrectV,
                            vbatV: vbatV,
                            ioutMa: ioutMa,
                            pgOk: pgOk,
                            charging: charging,
                            ceOn: ceOn,
                            hasData: adv != null,
                          ),
                          const SizedBox(height: 4),
                          _buildSectionHeader(tr("板子角度與充電狀態")),
                          _buildAttitudeTable(
                            ready: ready,
                            rollDeg: rollDeg,
                            pitchDeg: pitchDeg,
                            yawDeg: yawDeg,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopConnectionBar({
    required bool live,
    required String statusText,
    required bool canZero,
  }) {
    return Container(
      key: const Key('demo3-header'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color:
            _dark
                ? const Color(0xff152230)
                : live
                ? _scheme.primaryContainer
                : _scheme.surfaceContainer,
        border: Border(
          bottom: BorderSide(color: _scheme.outlineVariant, width: 1),
        ),
      ),
      child: Row(
        children: [
          const BackButton(),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            live
                                ? const Color(0xFF16A34A)
                                : const Color(0xFFD97706),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        "DEMO 3 · ${tr('無線充電展示')}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  tr(_dark ? "{0} · {1} dBm" : "{0} · 訊號 {1} dBm", [
                    "0901SR · ${_device?.systemIdHex ?? '--'}",
                    _device?.rssi ?? '--',
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                  ),
                ),
                Text(
                  statusText,
                  key: const Key('demo3-status'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: _muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          FilledButton.icon(
            key: const Key('demo3-zero'),
            style: FilledButton.styleFrom(
              backgroundColor: _scheme.primary,
              foregroundColor: _scheme.onPrimary,
              minimumSize: const Size(48, 32),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            onPressed: canZero ? _zero : null,
            icon: const Icon(Icons.center_focus_strong, size: 15),
            label: Text(
              _tilt.zeroActive ? tr("歸零中") : tr("歸零"),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWptStage({
    required Orientation pose,
    required bool live,
    required bool ready,
    required double cosTheta,
    required double couplingPct,
    required double tiltDeg,
    required double vrectV,
    required int ioutMa,
    required bool charging,
  }) {
    return Container(
      key: const Key('demo3-stage'),
      decoration: BoxDecoration(
        color: _scheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _scheme.outline, width: 0.9),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 152),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: AnimatedRxPose(
            orientation: pose,
            receivedAt: _device?.lastSeen,
            live: live,
            referenceToken: _referenceToken,
            builder: (context, q) {
              return CustomPaint(
                key: const Key('demo3-canvas-flux'),
                painter: WptFluxFieldPainter(
                  dark: _dark,
                  pose: q,
                  live: live,
                  phase: _fluxPhase,
                  vrectV: _device?.advData == null ? null : vrectV,
                  charging: charging,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Friendly 4-stage energy flow pipeline.
  Widget _buildEnergyPipeline({
    required bool ready,
    required bool fresh,
    required double couplingPct,
    required double tiltDeg,
    required double vrectV,
    required double vbatV,
    required int ioutMa,
    required bool pgOk,
    required bool charging,
    required bool ceOn,
    required bool hasData,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: _scheme.surface,
        border: Border(
          left: BorderSide(color: _scheme.outline, width: 0.8),
          right: BorderSide(color: _scheme.outline, width: 0.8),
          bottom: BorderSide(color: _scheme.outline, width: 0.8),
        ),
      ),
      child: Row(
        children: [
          _buildStageBox(
            step: tr("1.對準度"),
            primary: ready ? '${couplingPct.toStringAsFixed(0)}%' : '--',
            secondary:
                ready ? tr("傾斜 {0}°", [tiltDeg.toStringAsFixed(1)]) : tr("待歸零"),
            active: ready && couplingPct >= 85,
            color: _copperCoil,
          ),
          _buildPipelineArrow(active: fresh && vrectV > 3.0),
          _buildStageBox(
            step: tr("2.接收電力"),
            primary: hasData ? '${vrectV.toStringAsFixed(1)}V' : '--',
            secondary: hasData ? (pgOk ? tr("供電正常") : tr("電壓偏低")) : tr("無訊號"),
            active: fresh && pgOk,
            color: _primaryBlue,
          ),
          _buildPipelineArrow(active: fresh && pgOk && ceOn),
          _buildStageBox(
            step: tr("3.充電狀態"),
            primary: hasData ? (charging ? tr("充電中") : tr("待機")) : '--',
            secondary: hasData ? (ceOn ? tr("充電開啟") : tr("充電關閉")) : '--',
            active: fresh && charging,
            color: _tealEnergy,
          ),
          _buildPipelineArrow(active: fresh && charging && ioutMa > 0),
          _buildStageBox(
            step: tr("4.電池電力"),
            primary: hasData ? '${vbatV.toStringAsFixed(2)}V' : '--',
            secondary: hasData ? tr("電流 {0}mA", [ioutMa]) : '--',
            active: fresh && ioutMa > 0,
            color: _greenGood,
          ),
        ],
      ),
    );
  }

  Widget _buildStageBox({
    required String step,
    required String primary,
    required String secondary,
    required bool active,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        decoration: BoxDecoration(
          color:
              _dark
                  ? const Color(0xff18222c)
                  : active
                  ? color.withValues(alpha: 0.08)
                  : _scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color:
                _dark
                    ? const Color(0xff344555)
                    : active
                    ? color.withValues(alpha: 0.45)
                    : _scheme.outlineVariant,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                step,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 10,
                  height: 1.12,
                  fontWeight: FontWeight.w700,
                  color: active && !_dark ? color : _muted,
                ),
              ),
            ),
            const SizedBox(height: 1),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                primary,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.15,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                  color: active ? color : _ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 1),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                secondary,
                maxLines: 1,
                style: TextStyle(fontSize: 9.5, height: 1.12, color: _muted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPipelineArrow({required bool active}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Icon(
        Icons.double_arrow,
        size: 12,
        color: active && !_dark ? _tealEnergy : _scheme.outline,
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: _scheme.surfaceContainerHigh,
        border: Border.all(color: _scheme.outline, width: 0.8),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          height: 1.2,
          fontWeight: FontWeight.w700,
          color: _ink,
        ),
      ),
    );
  }

  Widget _buildAttitudeTable({
    required bool ready,
    required double rollDeg,
    required double pitchDeg,
    required double yawDeg,
  }) {
    String fmtDeg(double v) =>
        !ready ? '--' : '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}°';
    return Container(
      decoration: BoxDecoration(
        color: _scheme.surface,
        border: Border(
          left: BorderSide(color: _scheme.outline, width: 0.8),
          right: BorderSide(color: _scheme.outline, width: 0.8),
          bottom: BorderSide(color: _scheme.outline, width: 0.8),
        ),
      ),
      child: Row(
        children: [
          _buildMetricCell(
            label: tr("左右傾斜"),
            value: fmtDeg(rollDeg),
            color: _primaryBlue,
          ),
          _buildDivider(),
          _buildMetricCell(
            label: tr("前後傾斜"),
            value: fmtDeg(pitchDeg),
            color: _tealEnergy,
          ),
          _buildDivider(),
          _buildMetricCell(
            label: tr("水平旋轉"),
            value: fmtDeg(yawDeg),
            color: _copperCoil,
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() =>
      Container(width: 0.8, height: 23, color: _scheme.outlineVariant);

  Widget _buildMetricCell({
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            children: [
              Text(label, style: TextStyle(fontSize: 10.5, color: _muted)),
              const SizedBox(width: 3),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
