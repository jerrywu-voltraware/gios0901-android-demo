import 'package:gios0901/core/localization/translations.dart';
import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/constants/ble_constants.dart';
import '../../core/utils/hex_utils.dart';
import '../models/write_job.dart';

/// 寫入單一裝置的結果。
class WriteOutcome {
  final bool success;

  /// 驗證讀回的 SystemID（成功時）。
  final int? value;

  /// 失敗訊息（失敗時）。
  final String? message;

  const WriteOutcome._(this.success, this.value, this.message);

  factory WriteOutcome.ok(int value) => WriteOutcome._(true, value, null);
  factory WriteOutcome.fail(String message) =>
      WriteOutcome._(false, null, message);
}

/// 封裝 flutter_blue_plus 的 BLE 操作：權限、掃描、以及 SystemID 寫入流程。
class BleService {
  // -------------------------------------------------------------------------
  // 狀態串流
  // -------------------------------------------------------------------------

  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;
  Stream<bool> get isScanning => FlutterBluePlus.isScanning;
  Stream<BluetoothAdapterState> get adapterState =>
      FlutterBluePlus.adapterState;

  bool get isBluetoothOn =>
      FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on;

  /// 目前已知的藍牙介面卡狀態。
  /// ⚠️ App 冷啟動初期、收到第一個事件前會是 [BluetoothAdapterState.unknown]，
  /// 不可直接當成「未開啟」，否則會誤判（要等事件確定或開掃描時再判斷）。
  BluetoothAdapterState get currentAdapterState =>
      FlutterBluePlus.adapterStateNow;

  /// 請求系統開啟藍牙。
  /// Android：跳出系統授權對話框，使用者同意後 adapterState 會發出 on。
  /// iOS：不支援程式開啟（直接回傳，由 UI 引導使用者到設定）。
  Future<void> turnOn() async {
    if (!Platform.isAndroid) return;
    await FlutterBluePlus.turnOn();
  }

  Future<bool> get isSupported => FlutterBluePlus.isSupported;

  // -------------------------------------------------------------------------
  // 權限（依 Android 版本分流）
  // -------------------------------------------------------------------------

  /// 確保取得掃描/連線所需權限。回傳 true 表示可繼續。
  ///
  /// - Android 12 (API 31)+：BLUETOOTH_SCAN + BLUETOOTH_CONNECT
  /// - Android 11 (API 30)-：ACCESS_FINE_LOCATION（BLE 掃描必要）
  Future<bool> ensurePermissions() async {
    if (!Platform.isAndroid) return true;

    final info = await DeviceInfoPlugin().androidInfo;
    if (info.version.sdkInt >= 31) {
      final statuses =
          await [
            Permission.bluetoothScan,
            Permission.bluetoothConnect,
          ].request();
      return statuses.values.every((s) => s.isGranted);
    } else {
      final status = await Permission.locationWhenInUse.request();
      return status.isGranted;
    }
  }

  // -------------------------------------------------------------------------
  // 掃描
  // -------------------------------------------------------------------------

  /// 開始掃描。
  ///
  /// 不在 OS 層用名稱過濾（避免名稱只在 scan response 時漏抓），改由
  /// [AdvParser] 在 App 端過濾。continuousUpdates 讓 RSSI 持續更新，
  /// removeIfGone 讓離開範圍的裝置自動消失。
  ///
  /// 兩個參數的成本天差地遠，調整前先分清楚：
  /// - [continuousDivisor] 只是原生層的回報過濾器，**不影響 radio**。
  ///   預設 8 代表每 8 包才回報 1 包（約 800ms），疊加韌體 500ms 的 payload
  ///   刷新後體感延遲逼近 1.3 秒；需要即時監看時設 1 即可，代價只有 CPU。
  /// - [androidScanMode] **會動到 radio**。balanced 是工作週期掃描
  ///   （Android 每 4096ms 只開約 1024ms 接收窗），lowLatency 為 100% 連續接收。
  ///   ⚠️ 若畫面同時維持 GATT 連線，**不要用 lowLatency**：實測會與連線搶天線，
  ///   造成 ANDROID_SPECIFIC_ERROR 斷線。要更快請先改韌體的廣播刷新週期。
  Future<void> startScan({
    AndroidScanMode androidScanMode = AndroidScanMode.balanced,
    int continuousDivisor = 8,
  }) async {
    if (FlutterBluePlus.isScanningNow) return;
    await FlutterBluePlus.startScan(
      continuousUpdates: true,
      continuousDivisor: continuousDivisor,
      removeIfGone: const Duration(seconds: 15),
      androidScanMode: androidScanMode,
      androidUsesFineLocation: false,
    );
  }

  Future<void> stopScan() async {
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
  }

  // -------------------------------------------------------------------------
  // 工程模式：建立/維持單一裝置連線（與寫入流程不同，不會自動斷線）
  // -------------------------------------------------------------------------

  /// 裝置的連線狀態串流。
  Stream<BluetoothConnectionState> connectionStateOf(BluetoothDevice device) =>
      device.connectionState;

  /// 連線並保持連線（供工程頁面使用）。
  Future<void> connect(BluetoothDevice device) async {
    await device.connect(
      license: License.nonprofit,
      timeout: const Duration(seconds: 15),
      mtu: null,
      autoConnect: false,
    );
    // 連線後立即在原生層探索服務，確保後續操作能直接存取 Characteristic
    await device.discoverServices();
  }

  /// 斷線（離開工程頁面時呼叫）。
  Future<void> disconnect(BluetoothDevice device) async {
    try {
      await device.disconnect();
    } catch (_) {
      // 斷線失敗忽略。
    }
  }

  /// 取得現有服務或進行探索（避免重複 discoverServices 造成延遲）。
  Future<List<BluetoothService>> _getOrDiscoverServices(
    BluetoothDevice device,
  ) async {
    if (device.servicesList.isNotEmpty) {
      return device.servicesList;
    }
    return await device.discoverServices();
  }

  /// 訂閱感測資料 Notify 0x1501，回傳韌體每 500ms 推送一次的原始 payload。
  ///
  /// 連線期間用這條取代掃描廣播：實測手機一邊維持 GATT 連線一邊掃描會搶天線，
  /// 造成 ANDROID_SPECIFIC_ERROR 斷線。payload 格式見 [BleConstants.sensorNotifyCharUuid]。
  ///
  /// 每次重新連線都必須重新呼叫（CCCD 不會跨連線保留，韌體斷線時也會停掉 notify timer）。
  ///
  /// 回傳已 listen 的 subscription：`onValueReceived` 是 broadcast stream，
  /// 沒有 listener 時事件會被直接丟棄，所以必須「先 listen 再開 CCCD」，
  /// 光是先取得 stream 物件並不會緩衝任何東西。呼叫端負責 cancel，
  /// 或用 `device.cancelWhenDisconnected(sub)` 綁定連線生命週期。
  Future<StreamSubscription<List<int>>> subscribeSensorNotify(
    BluetoothDevice device,
    void Function(List<int>) onData,
  ) async {
    var services = await _getOrDiscoverServices(device);
    var service = _firstWhereOrNull(
      services,
      (s) => s.uuid == BleConstants.serviceUuid,
    );
    if (service == null) {
      // 若快取無此服務，重新探索一次
      services = await device.discoverServices();
      service = _firstWhereOrNull(
        services,
        (s) => s.uuid == BleConstants.serviceUuid,
      );
    }
    if (service == null) {
      throw Exception(tr("找不到 AIPS 服務（0x1500）"));
    }
    final ch = _firstWhereOrNull(
      service.characteristics,
      (c) => c.uuid == BleConstants.sensorNotifyCharUuid,
    );
    if (ch == null) {
      throw Exception(tr("找不到感測資料特徵（0x1501）"));
    }
    // 先 listen 再開 CCCD，順序不可對調（見上方說明）。
    final sub = ch.onValueReceived.listen(onData);
    try {
      await ch.setNotifyValue(true);
    } catch (_) {
      await sub.cancel();
      rethrow;
    }
    return sub;
  }

  /// 讀取控制暫存器 0x1503（回傳 1 byte 整數）。
  Future<int> readCtrlReg(BluetoothDevice device) async {
    var services = await _getOrDiscoverServices(device);
    var service = _firstWhereOrNull(
      services,
      (s) => s.uuid == BleConstants.serviceUuid,
    );
    if (service == null) {
      // 若快取無此服務，重新探索一次
      services = await device.discoverServices();
      service = _firstWhereOrNull(
        services,
        (s) => s.uuid == BleConstants.serviceUuid,
      );
    }
    if (service == null) {
      throw Exception(tr("找不到 AIPS 服務（0x1500）"));
    }
    final ch = _firstWhereOrNull(
      service.characteristics,
      (c) => c.uuid == BleConstants.ctrlCharUuid,
    );
    if (ch == null) {
      throw Exception(tr("找不到控制暫存器特徵（0x1503）"));
    }
    try {
      final value = await ch.read();
      if (value.isEmpty) {
        throw Exception(tr("讀取控制暫存器回傳長度為 0"));
      }
      return value[0];
    } catch (_) {
      // 原生 GATT 快取失效時重新探索並重試
      await device.discoverServices();
      final value = await ch.read();
      if (value.isEmpty) {
        throw Exception(tr("讀取控制暫存器回傳長度為 0"));
      }
      return value[0];
    }
  }

  /// 寫入控制暫存器 0x1503（寫入 1 byte）。
  Future<void> writeCtrlReg(BluetoothDevice device, int regValue) async {
    var services = await _getOrDiscoverServices(device);
    var service = _firstWhereOrNull(
      services,
      (s) => s.uuid == BleConstants.serviceUuid,
    );
    if (service == null) {
      // 若快取無此服務，重新探索一次
      services = await device.discoverServices();
      service = _firstWhereOrNull(
        services,
        (s) => s.uuid == BleConstants.serviceUuid,
      );
    }
    if (service == null) {
      throw Exception(tr("找不到 AIPS 服務（0x1500）"));
    }
    final ch = _firstWhereOrNull(
      service.characteristics,
      (c) => c.uuid == BleConstants.ctrlCharUuid,
    );
    if (ch == null) {
      throw Exception(tr("找不到控制暫存器特徵（0x1503）"));
    }
    try {
      await ch.write([regValue & 0xFF], withoutResponse: false);
    } catch (_) {
      // 原生 GATT 快取失效時重新探索並重試
      await device.discoverServices();
      await ch.write([regValue & 0xFF], withoutResponse: false);
    }
  }

  // -------------------------------------------------------------------------
  // 寫入 SystemID（Connect → Write 0x1502 → 讀回驗證 → Disconnect）
  // -------------------------------------------------------------------------

  /// 對單一裝置寫入 [targetId]（16-bit），含自動重試。
  ///
  /// [onStage] 會在各階段回呼，供 UI 即時更新進度。
  /// Android BLE 常見的間歇性錯誤（如 GATT 133）多為連線時序 / radio 競爭造成，
  /// 失敗時會先斷線、退避等待後重試，最多 [maxAttempts] 次；全部失敗才回報失敗。
  Future<WriteOutcome> writeSystemId(
    BluetoothDevice device,
    int targetId, {
    required void Function(WriteStage stage) onStage,
    int maxAttempts = 3,
  }) async {
    WriteOutcome outcome = WriteOutcome.fail(tr("未嘗試寫入"));
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      outcome = await _writeSystemIdOnce(device, targetId, onStage: onStage);
      if (outcome.success) return outcome;

      // 失敗 → 確保斷線並等 BLE radio 穩定後再重試（間歇性錯誤通常重試即可成功）。
      await disconnect(device);
      if (attempt < maxAttempts) {
        await Future.delayed(Duration(milliseconds: 400 * attempt));
      }
    }
    // 全部嘗試都失敗：訊息標註重試次數，便於辨識是否為間歇性錯誤。
    return WriteOutcome.fail(
      tr("{0}（已重試 {1} 次）", [outcome.message ?? tr("未知錯誤"), maxAttempts]),
    );
  }

  /// 單次寫入嘗試（Connect → 探索 → 寫 0x1502 → 讀回驗證 → Disconnect）。
  ///
  /// 無論成功或失敗，最後都會嘗試斷線。
  Future<WriteOutcome> _writeSystemIdOnce(
    BluetoothDevice device,
    int targetId, {
    required void Function(WriteStage stage) onStage,
  }) async {
    try {
      onStage(WriteStage.connecting);
      // license: flutter_blue_plus 2.x 的授權宣告。內部/非營利開發用 nonprofit；
      //   ⚠️ 正式商用出貨需評估購買 commercial 授權，或改用 MIT 授權的 BLE 套件。
      // mtu: null → 不協商 MTU（只寫 2 bytes，避免多餘失敗面）。
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 15),
        mtu: null,
        autoConnect: false,
      );

      onStage(WriteStage.discovering);
      final services = await device.discoverServices();
      final service = _firstWhereOrNull(
        services,
        (s) => s.uuid == BleConstants.serviceUuid,
      );
      if (service == null) {
        return WriteOutcome.fail(tr("找不到 AIPS 服務（0x1500）"));
      }
      final ch = _firstWhereOrNull(
        service.characteristics,
        (c) => c.uuid == BleConstants.systemIdCharUuid,
      );
      if (ch == null) {
        return WriteOutcome.fail(tr("找不到 SystemID 特徵（0x1502）"));
      }

      onStage(WriteStage.writing);
      // payload = 金鑰(4) + 值(2, little-endian)
      final payload = <int>[
        ...BleConstants.systemIdWriteKey,
        ...HexUtils.uint16ToLe(targetId),
      ];
      await ch.write(payload, withoutResponse: false);

      onStage(WriteStage.verifying);
      final readBack = await ch.read();
      if (readBack.length < BleConstants.systemIdReadLength) {
        return WriteOutcome.fail(tr("讀回長度異常（{0} bytes）", [readBack.length]));
      }
      final actual = HexUtils.leToUint16(readBack[0], readBack[1]);
      if (actual != targetId) {
        return WriteOutcome.fail(
          tr("驗證不符：寫入 {0}，讀回 {1}", [
            HexUtils.formatSystemId(targetId),
            HexUtils.formatSystemId(actual),
          ]),
        );
      }
      return WriteOutcome.ok(actual);
    } on FlutterBluePlusException catch (e) {
      return WriteOutcome.fail(e.description ?? e.toString());
    } catch (e) {
      return WriteOutcome.fail(e.toString());
    } finally {
      try {
        await device.disconnect();
      } catch (_) {
        // 斷線失敗不影響結果。
      }
    }
  }

  static T? _firstWhereOrNull<T>(List<T> list, bool Function(T) test) {
    for (final item in list) {
      if (test(item)) return item;
    }
    return null;
  }
}
