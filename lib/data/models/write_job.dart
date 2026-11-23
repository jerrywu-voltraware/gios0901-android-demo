import 'package:gios0901/core/localization/translations.dart';
import 'pru_device.dart';

/// 單一裝置寫入 SystemID 的階段。
/// 對照韌體圖「實際寫入流程」：Connect → GATT Write → 讀回驗證 → Disconnect。
enum WriteStage {
  pending, // 佇列等待中
  connecting, // BLE 連線中
  discovering, // 探索 GATT 服務
  writing, // 寫入 0x1502
  verifying, // 讀回驗證
  success, // 完成且驗證通過
  failed, // 失敗
  cancelled, // 使用者取消（未真正嘗試寫入，不計為失敗）
}

extension WriteStageLabel on WriteStage {
  String get label => switch (this) {
    WriteStage.pending => tr("等待中"),
    WriteStage.connecting => tr("連線中…"),
    WriteStage.discovering => tr("探索服務…"),
    WriteStage.writing => tr("寫入中…"),
    WriteStage.verifying => tr("驗證中…"),
    WriteStage.success => tr("完成"),
    WriteStage.failed => tr("失敗"),
    WriteStage.cancelled => tr("已取消"),
  };

  bool get isDone =>
      this == WriteStage.success ||
      this == WriteStage.failed ||
      this == WriteStage.cancelled;
  bool get isActive =>
      this == WriteStage.connecting ||
      this == WriteStage.discovering ||
      this == WriteStage.writing ||
      this == WriteStage.verifying;
}

/// 寫入佇列中的一個工作項（不可變）。
class WriteJob {
  final PruDevice device;
  final WriteStage stage;

  /// 失敗訊息或補充說明。
  final String? message;

  /// 驗證讀回的 SystemID（成功時填入）。
  final int? verifiedSystemId;

  const WriteJob({
    required this.device,
    this.stage = WriteStage.pending,
    this.message,
    this.verifiedSystemId,
  });

  bool get isDone => stage.isDone;
  bool get isSuccess => stage == WriteStage.success;

  WriteJob copyWith({
    WriteStage? stage,
    String? message,
    int? verifiedSystemId,
    bool clearMessage = false,
  }) {
    return WriteJob(
      device: device,
      stage: stage ?? this.stage,
      message: clearMessage ? null : (message ?? this.message),
      verifiedSystemId: verifiedSystemId ?? this.verifiedSystemId,
    );
  }
}
