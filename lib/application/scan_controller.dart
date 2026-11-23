import 'package:gios0901/core/localization/translations.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ble/adv_parser.dart';
import '../data/ble/ble_service.dart';
import '../data/models/pru_device.dart';
import 'gy521_trace.dart';
import 'providers.dart';

/// 掃描畫面狀態（不可變）。
class ScanState {
  /// 目前掃描到的裝置（key = 裝置 id）。
  final Map<String, PruDevice> devices;

  /// 已勾選的裝置 id。
  final Set<String> selectedIds;

  final bool isScanning;
  final bool bluetoothOn;

  /// 錯誤/提示訊息（權限、藍牙未開等）。
  final String Function()? error;

  const ScanState({
    this.devices = const {},
    this.selectedIds = const {},
    this.isScanning = false,
    this.bluetoothOn = true,
    this.error,
  });

  /// 裝置清單，依裝置 id（MAC）固定排序。
  /// 不用 RSSI 排序：RSSI 每次掃描都在變動，會讓清單順序不停跳動，難以勾選。
  /// 以 MAC 排序則順序固定，新裝置依其 MAC 插入對應位置，既有裝置不會亂跳。
  List<PruDevice> get sortedDevices {
    final list = devices.values.toList();
    list.sort((a, b) => a.id.compareTo(b.id));
    return list;
  }

  /// 已勾選且仍在範圍內的裝置（依排序）。
  List<PruDevice> get selectedDevices =>
      sortedDevices.where((d) => selectedIds.contains(d.id)).toList();

  int get selectedCount => selectedIds.length;

  ScanState copyWith({
    Map<String, PruDevice>? devices,
    Set<String>? selectedIds,
    bool? isScanning,
    bool? bluetoothOn,
    String Function()? error,
    bool clearError = false,
  }) {
    return ScanState(
      devices: devices ?? this.devices,
      selectedIds: selectedIds ?? this.selectedIds,
      isScanning: isScanning ?? this.isScanning,
      bluetoothOn: bluetoothOn ?? this.bluetoothOn,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// 掃描控制器：訂閱掃描結果、管理勾選、開始/停止掃描。
class ScanController extends Notifier<ScanState> {
  late final BleService _ble = ref.read(bleServiceProvider);
  StreamSubscription<List<ScanResult>>? _resultsSub;
  StreamSubscription<bool>? _scanningSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;

  /// 頁面是否仍希望維持掃描中（進頁 startScan 設 true、離頁 stopScan 設 false）。
  /// 用於藍牙關→開時，只在使用者仍停留於掃描頁時自動恢復掃描。
  bool _scanRequested = false;

  /// 防止 startScan() 與 adapter「on」事件同時觸發 _startScanInternal 而重入
  /// （例如冷啟動時 ensurePermissions 尚在等待、adapter 事件又進來）。
  bool _starting = false;
  int _requestGeneration = 0;
  Completer<void>? _startDone;
  Future<void> _nativeScanQueue = Future.value();
  Future<void> _nativeScanAction(Future<void> Function() action) {
    final operation = _nativeScanQueue.then((_) => action());
    _nativeScanQueue = operation.catchError((Object _) {});
    return operation;
  }

  // 掃描結果節流：lowLatency/continuousUpdates 下回呼極頻繁，若每次都重建畫面
  // 會把 UI 主執行緒灌爆（造成卡頓甚至 ANR）。這裡限制工程模式每 100ms、生產模式每 400ms 套用一次。
  bool _engineeringMode = false;
  Duration get _minEmitInterval =>
      Duration(milliseconds: _engineeringMode ? 100 : 400);
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _throttleTimer;
  List<ScanResult> _latestResults = const [];

  final _reportListeners = <String, Set<StreamController<PruDevice>>>{};
  final _lastReportAt = <String, DateTime>{};
  bool _disposed = false;

  /// Selected-device reports before the list UI throttle. The caller owns
  /// the subscription; no cached report is replayed, and receive timestamps
  /// must advance. This does not change the native scan mode or list cadence.
  Stream<PruDevice> watchDeviceReports(String deviceId) {
    if (_disposed) throw StateError('Scan controller is disposed');
    late final StreamController<PruDevice> reports;
    reports = StreamController<PruDevice>(
      sync: true,
      onListen: () {
        if (_disposed) {
          unawaited(reports.close());
          return;
        }
        (_reportListeners[deviceId] ??= {}).add(reports);
        final cached = state.devices[deviceId]?.lastSeen;
        if (cached != null && !_lastReportAt.containsKey(deviceId)) {
          _lastReportAt[deviceId] = cached;
        }
      },
      onCancel: () {
        final listeners = _reportListeners[deviceId];
        listeners?.remove(reports);
        if (listeners?.isEmpty ?? false) {
          _reportListeners.remove(deviceId);
          _lastReportAt.remove(deviceId);
        }
      },
    );
    return reports.stream;
  }

  void _emitReports(List<ScanResult> results) {
    if (_reportListeners.isEmpty) return;
    for (final result in results) {
      final id = result.device.remoteId.str;
      final listeners = _reportListeners[id];
      if (listeners == null) continue;
      final previous = _lastReportAt[id];
      if (previous != null && !result.timeStamp.isAfter(previous)) continue;
      final device = AdvParser.fromScanResult(result);
      if (device == null) continue;
      _lastReportAt[id] = result.timeStamp;
      // A listener may cancel its subscription from its own callback.
      for (final listener in listeners.toList()) {
        if (!listener.isClosed) listener.add(device);
      }
    }
  }

  @override
  ScanState build() {
    _resultsSub = _ble.scanResults.listen(_onResults);
    _scanningSub = _ble.isScanning.listen((scanning) {
      state = state.copyWith(isScanning: scanning);
    });
    _adapterSub = _ble.adapterState.listen(_onAdapterState);

    ref.onDispose(() {
      _disposed = true;
      final reports = _reportListeners.values.expand((s) => s).toList();
      _reportListeners.clear();
      _lastReportAt.clear();
      for (final report in reports) {
        unawaited(report.close());
      }
      _scanRequested = false;
      ++_requestGeneration;
      _throttleTimer?.cancel();
      _resultsSub?.cancel();
      _scanningSub?.cancel();
      _adapterSub?.cancel();
      // 不 await（dispose 為同步）；吞掉例外避免變成未處理 async error。
      unawaited(_nativeScanAction(_ble.stopScan).catchError((_) {}));
    });

    return const ScanState();
  }

  void _onResults(List<ScanResult> results) {
    // GY521 Demo recording: every raw report, before the throttle below.
    Gy521Trace.onScanResults(results);
    _emitReports(results);
    _latestResults = List.of(results);
    final since = DateTime.now().difference(_lastEmit);
    if (since >= _minEmitInterval) {
      _emitDevices();
    } else {
      // 距上次太近 → 排一個 trailing 更新，確保最後一筆結果一定會套用。
      _throttleTimer ??= Timer(_minEmitInterval - since, _emitDevices);
    }
  }

  void _emitDevices() {
    _throttleTimer?.cancel();
    _throttleTimer = null;
    _lastEmit = DateTime.now();
    // 以最新結果重建清單（含 removeIfGone 的剔除效果）。
    final map = <String, PruDevice>{};
    for (final r in _latestResults) {
      final d = AdvParser.fromScanResult(r);
      if (d != null) {
        final previous = state.devices[d.id];
        map[d.id] =
            previous != null &&
                    previous.lastSeen == d.lastSeen &&
                    previous.name == d.name &&
                    previous.rssi == d.rssi &&
                    listEquals(
                      previous.rawManufacturerData,
                      d.rawManufacturerData,
                    )
                ? previous
                : d;
      }
    }
    // 勾選只保留仍在範圍內的裝置。
    if (map.length == state.devices.length &&
        map.entries.every((e) => identical(state.devices[e.key], e.value))) {
      return;
    }
    final selected = state.selectedIds.where(map.containsKey).toSet();
    state = state.copyWith(devices: map, selectedIds: selected);
  }

  /// 切換掃描開/關。
  Future<void> toggleScan() async {
    if (state.isScanning) {
      await stopScan();
    } else {
      await startScan();
    }
  }

  /// 藍牙介面卡狀態變化處理。
  /// - 轉為 on：清掉「藍牙未開」狀態與舊錯誤；若使用者仍停留掃描頁（[_scanRequested]）
  ///   且目前沒在掃描，則自動開始掃描（使用者開啟藍牙後不必再手動按一次）。
  /// - 其他（off/turningOn/turningOff/unauthorized…）：標記未開，UI 顯示開啟引導。
  ///
  /// 注意：這裡只會收到「明確」狀態事件，不會是 unknown；unknown 只在冷啟動初期
  /// 由 [_startScanInternal] 同步檢查時處理。
  void _onAdapterState(BluetoothAdapterState adapter) {
    if (adapter == BluetoothAdapterState.on) {
      state = state.copyWith(bluetoothOn: true, clearError: true);
      if (_scanRequested && !state.isScanning) {
        unawaited(_startScanInternal());
      }
    } else {
      state = state.copyWith(bluetoothOn: false);
    }
  }

  /// 開始掃描（由頁面呼叫）。標記頁面要掃描，之後藍牙關→開會自動恢復。
  Future<void> startScan({bool? engineeringMode}) async {
    if (engineeringMode != null) _engineeringMode = engineeringMode;
    _scanRequested = true;
    ++_requestGeneration;
    await _startScanInternal();
  }

  Future<void> _startScanInternal() async {
    if (_starting) return; // 重入防護（見 _starting 說明）。
    _starting = true;
    final generation = _requestGeneration;
    final done = Completer<void>();
    _startDone = done;
    try {
      // 每次嘗試都先清除舊錯誤，避免殘留誤導橫幅。
      state = state.copyWith(clearError: true);
      final granted = await _ble.ensurePermissions();
      if (!_scanRequested || generation != _requestGeneration) return;
      if (!granted) {
        state = state.copyWith(error: () => tr("藍牙/定位權限未授予，無法掃描"));
        return;
      }
      final adapter = _ble.currentAdapterState;
      if (adapter == BluetoothAdapterState.unknown) {
        // 冷啟動初期狀態尚未確定：先不顯示錯誤/引導，等 adapterState 事件來確定，
        // 若屆時為 on 會由 _onAdapterState 自動開始掃描。
        return;
      }
      if (adapter != BluetoothAdapterState.on) {
        // 藍牙未開：以 bluetoothOn=false 觸發可「開啟藍牙」的引導橫幅，不再用錯誤訊息。
        state = state.copyWith(bluetoothOn: false);
        return;
      }
      state = state.copyWith(bluetoothOn: true);
      try {
        if (!_scanRequested || generation != _requestGeneration) return;
        await _nativeScanAction(() async {
          if (!_scanRequested || generation != _requestGeneration) return;
          await _ble.startScan(
            androidScanMode:
                _engineeringMode
                    ? AndroidScanMode.lowLatency
                    : AndroidScanMode.balanced,
            continuousDivisor: _engineeringMode ? 1 : 8,
          );
        });
        if (!_scanRequested || generation != _requestGeneration) {
          await _nativeScanAction(_ble.stopScan);
        }
      } catch (e) {
        if (_scanRequested && generation == _requestGeneration) {
          state = state.copyWith(error: () => tr("開始掃描失敗：{0}", [e]));
        }
      }
    } finally {
      _starting = false;
      if (identical(_startDone, done)) _startDone = null;
      done.complete();
      if (_scanRequested && generation != _requestGeneration) {
        unawaited(_startScanInternal());
      }
    }
  }

  Future<void> stopScan() async {
    _scanRequested = false;
    final generation = ++_requestGeneration;
    final pendingStart = _startDone;
    if (pendingStart != null) await pendingStart.future;
    if (generation != _requestGeneration || _scanRequested) return;
    try {
      await _nativeScanAction(() async {
        if (generation == _requestGeneration && !_scanRequested) {
          await _ble.stopScan();
        }
      });
    } catch (_) {}
  }

  /// UI「開啟藍牙」按鈕：請求系統開啟藍牙（Android）。
  /// 成功後 adapterState 會發出 on，由 [_onAdapterState] 清除引導並自動恢復掃描。
  Future<void> requestEnableBluetooth() async {
    try {
      await _ble.turnOn();
    } catch (_) {
      // 使用者取消或系統拒絕：保持未開狀態，引導橫幅續顯示，不另外彈錯誤。
    }
  }

  void toggleSelect(String id) {
    final selected = Set<String>.from(state.selectedIds);
    if (!selected.add(id)) selected.remove(id);
    state = state.copyWith(selectedIds: selected);
  }

  void selectAll() {
    state = state.copyWith(selectedIds: state.devices.keys.toSet());
  }

  void clearSelection() {
    state = state.copyWith(selectedIds: <String>{});
  }

  /// 清空裝置清單（重新掃描前可用）。
  void clearDevices() {
    state = state.copyWith(
      devices: <String, PruDevice>{},
      selectedIds: <String>{},
    );
  }
}

final scanControllerProvider = NotifierProvider<ScanController, ScanState>(
  ScanController.new,
);
