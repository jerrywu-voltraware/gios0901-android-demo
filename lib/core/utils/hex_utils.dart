import '../constants/ble_constants.dart';

/// Hex 字串 / 位元組序轉換工具。
class HexUtils {
  HexUtils._();

  /// 將 16-bit 整數格式化為 `0xXXXX`（大寫、補零）。
  static String formatSystemId(int value) =>
      '0x${value.toUnsigned(16).toRadixString(16).toUpperCase().padLeft(4, '0')}';

  /// 將位元組陣列格式化為空白分隔的 hex 字串，例如 `A5 5A 09 01 34 12`。
  static String bytesToHex(List<int> bytes) => bytes
      .map((b) => b.toUnsigned(8).toRadixString(16).toUpperCase().padLeft(2, '0'))
      .join(' ');

  /// 解析使用者輸入的 SystemID 字串。
  ///
  /// 接受 `0x1234`、`1234`（皆視為 16 進位）。
  /// 回傳 null 代表格式錯誤或超出 16-bit 範圍（0x0000 ~ 0xFFFF）。
  static int? parseSystemId(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;
    final lower = s.toLowerCase();
    if (lower.startsWith('0x')) s = s.substring(2);
    if (s.isEmpty) return null;
    final value = int.tryParse(s, radix: 16);
    if (value == null) return null;
    if (value < BleConstants.systemIdMin || value > BleConstants.systemIdMax) {
      return null;
    }
    return value;
  }

  /// 16-bit 值 → little-endian 2 bytes（低位在前）。
  static List<int> uint16ToLe(int value) => [value & 0xFF, (value >> 8) & 0xFF];

  /// little-endian 2 bytes → 16-bit 值。
  static int leToUint16(int low, int high) => (low & 0xFF) | ((high & 0xFF) << 8);
}
