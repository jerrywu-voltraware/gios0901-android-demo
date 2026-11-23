import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../core/utils/hex_utils.dart';
import 'pru_adv_data.dart';

/// 裝置角色。目前僅 PRU；PTU 待韌體完成後啟用。
enum DeviceRole { pru, ptu, unknown }

/// 掃描到的裝置快照（不可變，供 UI 顯示與選取）。
class PruDevice {
  /// flutter_blue_plus 的裝置 handle，用於後續連線/讀寫。
  final BluetoothDevice device;

  /// 廣播名稱（0901SR）。
  final String name;

  /// 訊號強度（dBm）。
  final int rssi;

  /// 裝置角色。
  final DeviceRole role;

  /// 解析後的廣播即時參數；若 manufacturer data 不存在/無效則為 null。
  final PruAdvData? advData;

  /// 原始 Manufacturer Specific Data 位元組（company 0xFFFF 之後的 payload）。
  /// 工程模式「廣播內容」頁用來原樣打印；無資料時為空陣列。
  final List<int> rawManufacturerData;

  /// 最後一次被掃描到的時間。
  final DateTime lastSeen;

  const PruDevice({
    required this.device,
    required this.name,
    required this.rssi,
    required this.role,
    required this.advData,
    required this.lastSeen,
    this.rawManufacturerData = const [],
  });

  /// 裝置唯一識別碼（Android 為 MAC，等同圖示的 Device ID）。
  String get id => device.remoteId.str;

  /// 目前廣播中的 SystemID（無廣播資料時為 null）。
  int? get systemId => advData?.systemId;

  /// SystemID 的 `0xXXXX` 字串（無資料時回傳 `--`）。
  String get systemIdHex =>
      systemId == null ? '--' : HexUtils.formatSystemId(systemId!);

  String get roleLabel => switch (role) {
        DeviceRole.pru => 'PRU',
        DeviceRole.ptu => 'PTU',
        DeviceRole.unknown => '?',
      };

  PruDevice copyWith({
    BluetoothDevice? device,
    String? name,
    int? rssi,
    DeviceRole? role,
    PruAdvData? advData,
    List<int>? rawManufacturerData,
    DateTime? lastSeen,
  }) {
    return PruDevice(
      device: device ?? this.device,
      name: name ?? this.name,
      rssi: rssi ?? this.rssi,
      role: role ?? this.role,
      advData: advData ?? this.advData,
      rawManufacturerData: rawManufacturerData ?? this.rawManufacturerData,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}
