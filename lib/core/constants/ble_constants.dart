import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// GIOS0901SR PRU 韌體的 BLE 協定常數。
///
/// 來源：韌體 repo 的 `README.md`（規格 single source of truth）。
/// ⚠️ 任何數值改動都必須與韌體端同步，否則 App 與裝置無法互通。
class BleConstants {
  BleConstants._();

  // ---------------------------------------------------------------------------
  // 裝置名稱（廣播 Complete Local Name）
  // ---------------------------------------------------------------------------

  /// PRU 裝置廣播名稱。韌體目前固定為 `0901SR`。
  static const String pruDeviceName = '0901SR';

  /// PTU 裝置廣播名稱。韌體（GIOS0901ST，relay 改造）固定為 `0901ST`。
  static const String ptuDeviceName = '0901ST';

  // ---------------------------------------------------------------------------
  // 廣播 Manufacturer Specific Data（舊版 11／新版 24 bytes，little-endian）
  // ---------------------------------------------------------------------------

  /// Company ID（測試/內部用 0xFFFF）。flutter_blue_plus 的 manufacturerData 以此為 key。
  static const int manufacturerCompanyId = 0xFFFF;

  /// manufacturer payload 長度（bytes）。
  static const int manufacturerDataLength = 11; // Legacy base and Notify data.
  static const int sixAxisManufacturerDataLength = 24;

  // ---------------------------------------------------------------------------
  // 自訂 AIPS Service / Characteristic（128-bit UUID）
  //   Base UUID 展開後：0000xxxx-1234-1234-1234-56789abcdef0
  // ---------------------------------------------------------------------------

  /// 自訂服務 0x1500。
  static final Guid serviceUuid = Guid('00001500-1234-1234-1234-56789abcdef0');

  /// 感測資料 Notify 特徵 0x1501。
  ///
  /// 連線期間由韌體每 500ms 主動推送即時參數。payload 為
  /// `[0]` 流水號 + `[1..11]` 廣播的 11-byte 基本資料（不含六軸有效 bit6）（見 [manufacturerDataLength]）。
  /// 工程模式連線中改讀這裡而非掃描廣播——實測手機一邊維持 GATT 連線一邊掃描
  /// 會與連線搶天線造成 ANDROID_SPECIFIC_ERROR 斷線。
  static final Guid sensorNotifyCharUuid = Guid(
    '00001501-1234-1234-1234-56789abcdef0',
  );

  /// 0x1501 Notify payload 中，資料區（11 bytes）的起始 offset。
  /// `[0]` 是韌體的流水號 lead_code（1~255 循環），供 App 偵測掉包。
  static const int sensorNotifyDataOffset = 1;

  /// 0x1501 Notify payload 的完整長度（流水號 1 + 資料 11）。
  ///
  /// ⚠️ 必須嚴格比對，不能只檢查「夠長」：舊韌體送的是 105 bytes 且
  /// Vrect/Vbat 為 big-endian，硬解會得到**看似合法**的垃圾值
  /// （實測顯示 Vrect 27155 mV、Vbat 513 mV），工程判讀會被誤導。
  /// 長度不符時應明講韌體版本不符，而不是照著解。
  static const int sensorNotifyPayloadLength =
      sensorNotifyDataOffset + manufacturerDataLength;

  /// SystemID 讀/寫特徵 0x1502。
  static final Guid systemIdCharUuid = Guid(
    '00001502-1234-1234-1234-56789abcdef0',
  );

  /// 控制暫存器 特徵 0x1503（Read / Write，固定 1 byte，僅存 RAM）。
  static final Guid ctrlCharUuid = Guid('00001503-1234-1234-1234-56789abcdef0');

  // ---------------------------------------------------------------------------
  // 控制暫存器規則（韌體 ble_aips.h，0x1503）
  // ---------------------------------------------------------------------------

  /// 控制暫存器長度（1 byte）。
  static const int ctrlRegLength = 1;

  /// Bit 0: CHARGER_CE_PIN 手動充電開關（1 = CE 拉 High / 啟用充電，0 = CE 拉 Low / 停止充電；BQ24640 為 active-HIGH）。
  static const int ctrlBitChargerEn = 0x01;

  /// Bit 1: 自動充電邏輯（1 = 啟用自動充電，0 = 手動模式）。
  static const int ctrlBitAutoEn = 0x02;

  /// Bit 2: 自動模式條件（0 = case1 僅看 PG，1 = case2 PG + Vrect 門檻）。
  static const int ctrlBitAutoVrect = 0x04;

  /// 開機預設值（0x06：自動模式 case2）。
  static const int ctrlRegDefault = 0x06;

  // ---------------------------------------------------------------------------
  // SystemID 寫入規則（韌體 ble_aips.h）
  //   寫入格式：金鑰(4 bytes) + 值(2 bytes, little-endian) = 6 bytes
  // ---------------------------------------------------------------------------

  /// 寫入驗證金鑰（韌體 `SYSTEM_ID_WRITE_KEY`）。
  /// ⚠️ 出貨前若更換韌體金鑰，這裡也要同步更換。
  static const List<int> systemIdWriteKey = [0xA5, 0x5A, 0x09, 0x01];

  /// 完整寫入長度 = 金鑰(4) + 值(2)。
  static const int systemIdWriteLength = 6;

  /// 讀取長度（2 bytes，little-endian）。
  static const int systemIdReadLength = 2;

  /// SystemID 為 16-bit（韌體實際規格；圖示的 0x12345678 為概念示意）。
  static const int systemIdMin = 0x0000;
  static const int systemIdMax = 0xFFFF;
}
