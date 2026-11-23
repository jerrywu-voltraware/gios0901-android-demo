import '../../application/orientation.dart';
import '../../core/constants/ble_constants.dart';
import '../../core/utils/hex_utils.dart';

/// 由 PRU 廣播 Manufacturer Specific Data 解析出的即時參數。
///
/// 全部欄位皆為 **little-endian**（韌體 `adv_data_refresh()`，每 100ms 刷新）。
/// 對照韌體 README §5.1：
/// ```
/// [0..1] SystemID   [2..3] Vrect   [4..5] Vbat   [6..7] CS_out
/// [8] Charger/故障旗標(bit0=PG,bit1=STAT,bit2=CE,
///     bit3=OV_VRECT,bit4=OV_VBAT,bit5=OC_IOUT 故障鎖存)
/// [9] RGB(bit0=R,bit1=G,bit2=B)
/// [10] 外部LED(bit0..3=LED1..4)
/// [11] 感測器(1=GY521)，[12..17] int16 加速度 mg
/// [18..23] int16 角速度 0.01 °/s，[8] bit6=六軸有效
/// ```
class PruAdvData {
  final int systemId;
  final int vrect;
  final int vbat;
  final int csout;
  final int chargerFlags;
  final int rgbFlags;
  final int extLedFlags;
  final int? sensorType;
  final int? accelXMg, accelYMg, accelZMg;
  final int? gyroXCentiDps, gyroYCentiDps, gyroZCentiDps;
  final Orientation? pose;
  final int? poseEpoch, poseFlags, poseNormUnits;
  bool get isGy521 => sensorType == 1 || sensorType == 2;
  bool get sixAxisValid =>
      chargerFlags & 0x40 != 0 &&
      ((sensorType == 1 && accelXMg != null) ||
          (sensorType == 2 && pose != null && (poseFlags ?? 0) & 1 != 0));

  const PruAdvData({
    required this.systemId,
    required this.vrect,
    required this.vbat,
    required this.csout,
    required this.chargerFlags,
    required this.rgbFlags,
    required this.extLedFlags,
    this.sensorType,
    this.pose,
    this.poseEpoch,
    this.poseFlags,
    this.poseNormUnits,
    this.accelXMg,
    this.accelYMg,
    this.accelZMg,
    this.gyroXCentiDps,
    this.gyroYCentiDps,
    this.gyroZCentiDps,
  });

  /// 解析 manufacturer payload。
  ///
  /// - PRU（GIOS0901SR）：11 bytes 舊版或 24 bytes 六軸版；擴充欄位僅接受完整 24 bytes。
  /// - PTU（GIOS0901ST）：僅 2 bytes，`[0..1]` = SystemID（`[2..]` 韌體保留），
  ///   其餘參數欄位以 0 代入（PTU 廣播未夾帶，scan 清單也不顯示）。
  ///
  /// 不足 2 bytes（無法取出 SystemID）回傳 null。
  static PruAdvData? parse(List<int> data) {
    if (data.length != BleConstants.manufacturerDataLength &&
        data.length != BleConstants.sixAxisManufacturerDataLength)
      return null;
    int le(int i) =>
        i + 1 < data.length ? HexUtils.leToUint16(data[i], data[i + 1]) : 0;
    int byte(int i) => i < data.length ? data[i] & 0xFF : 0;
    final extended = data.length == BleConstants.sixAxisManufacturerDataLength;
    int signed(int i) {
      final value = le(i);
      return value >= 0x8000 ? value - 0x10000 : value;
    }

    final raw = extended && byte(11) == 1;
    final v2 = extended && byte(11) == 2;
    Orientation? pose;
    if (v2) {
      final q = Orientation(
        signed(12) / 16384,
        signed(14) / 16384,
        signed(16) / 16384,
        signed(18) / 16384,
      );
      final n = q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z;
      if (n > 0.98 && n < 1.02) pose = q.normalized;
    }
    return PruAdvData(
      pose: pose,
      poseEpoch: v2 ? le(22) : null,
      poseFlags: v2 ? byte(21) : null,
      poseNormUnits: v2 ? byte(20) : null,
      systemId: HexUtils.leToUint16(data[0], data[1]),
      vrect: le(2),
      vbat: le(4),
      csout: le(6),
      chargerFlags: byte(8),
      rgbFlags: byte(9),
      extLedFlags: byte(10),
      sensorType: extended ? byte(11) : null,
      accelXMg: raw ? signed(12) : null,
      accelYMg: raw ? signed(14) : null,
      accelZMg: raw ? signed(16) : null,
      gyroXCentiDps: raw ? signed(18) : null,
      gyroYCentiDps: raw ? signed(20) : null,
      gyroZCentiDps: raw ? signed(22) : null,
    );
  }

  /// 解析 0x1501 Notify 的 payload。
  ///
  /// 韌體 `notify_timeout_handler()` 送出的格式為 `[0]` 流水號 +
  /// `[1..11]` 對應廣播前 11 bytes 的基本資料（不含六軸有效 bit6），
  /// 兩者在韌體端共用 `aips_build_payload()`，故這裡直接沿用 [parse]。
  /// 長度**必須完全等於** [BleConstants.sensorNotifyPayloadLength]，否則回傳 null。
  /// 舊韌體（105 bytes、big-endian）硬解會產生看似合法的垃圾值，寧可拒絕。
  static PruAdvData? parseNotify(List<int> payload) {
    if (payload.length != BleConstants.sensorNotifyPayloadLength) return null;
    return parse(payload.sublist(BleConstants.sensorNotifyDataOffset));
  }

  /// 取出 Notify payload 的流水號；長度不足時回傳 null。
  static int? leadCodeOf(List<int> payload) =>
      payload.isEmpty ? null : payload[0] & 0xFF;

  // ---- Charger 旗標（原始 GPIO 電位，1=High 0=Low）----
  bool get pgHigh => chargerFlags & 0x01 != 0;
  bool get statHigh => chargerFlags & 0x02 != 0;
  bool get ceHigh => chargerFlags & 0x04 != 0;

  // ---- 故障鎖存（韌體 aips_get_fault()，鎖存後需重置才會清除）----
  bool get faultOvVrect => chargerFlags & 0x08 != 0;
  bool get faultOvVbat => chargerFlags & 0x10 != 0;
  bool get faultOcIout => chargerFlags & 0x20 != 0;
  bool get hasFault => chargerFlags & 0x38 != 0;

  // ---- RGB 指示燈（1 = 亮）----
  bool get rgbRed => rgbFlags & 0x01 != 0;
  bool get rgbGreen => rgbFlags & 0x02 != 0;
  bool get rgbBlue => rgbFlags & 0x04 != 0;

  /// 外部 LED bar 第 [index] 顆（0 基底，對應韌體 LED1~LED4），1 = 亮。
  bool extLed(int index) => extLedFlags & (1 << index) != 0;

  String get systemIdHex => HexUtils.formatSystemId(systemId);
}
