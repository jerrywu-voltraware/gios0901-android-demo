import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ble/ble_service.dart';

/// 全域唯一的 BLE 服務實例。
final bleServiceProvider = Provider<BleService>((ref) => BleService());
