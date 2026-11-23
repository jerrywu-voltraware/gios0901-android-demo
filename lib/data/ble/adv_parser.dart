import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../core/constants/ble_constants.dart';
import '../models/pru_adv_data.dart';
import '../models/pru_device.dart';

/// 將 BLE 掃描結果解析為 [PruDevice]。
class AdvParser {
  AdvParser._();

  /// 由名稱判斷角色：PRU=`0901SR`、PTU=`0901ST`。
  static DeviceRole roleForName(String name) {
    if (name == BleConstants.pruDeviceName) return DeviceRole.pru;
    if (name == BleConstants.ptuDeviceName) return DeviceRole.ptu;
    return DeviceRole.unknown;
  }

  /// 解析單筆掃描結果。
  ///
  /// 非本專案裝置（名稱非 0901SR）回傳 null，由呼叫端過濾。
  static PruDevice? fromScanResult(ScanResult r) {
    final adv = r.advertisementData;
    // advName 在新版韌體來自 Scan Response；某些封包為空時退回 platformName。
    final name = adv.advName.isNotEmpty ? adv.advName : r.device.platformName;
    final role = roleForName(name);
    if (role == DeviceRole.unknown) return null;

    final manuf = adv.manufacturerData[BleConstants.manufacturerCompanyId];
    final advData = manuf != null ? PruAdvData.parse(manuf) : null;

    return PruDevice(
      device: r.device,
      name: name,
      rssi: r.rssi,
      role: role,
      advData: advData,
      // 原始位元組保留下來，供工程模式「廣播內容」頁原樣打印。
      rawManufacturerData: manuf ?? const [],
      lastSeen: r.timeStamp,
    );
  }
}
