import 'package:shared_preferences/shared_preferences.dart';
import 'package:gios0901/core/localization/locale_state.dart';
import 'dart:ui' as ui;
import 'package:gios0901/presentation/widgets/demo3_wpt_painters.dart';
import 'package:gios0901/application/orientation.dart' as attitude;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gios0901/application/scan_controller.dart';
import 'package:gios0901/core/localization/translations.dart';
import 'package:gios0901/data/models/pru_adv_data.dart';
import 'package:gios0901/data/models/pru_device.dart';
import 'package:gios0901/main.dart';

class FixtureScan extends ScanController {
  @override
  ScanState build() {
    final receiver = PruDevice(
      device: BluetoothDevice.fromId('AA:00:11:22:33:44'),
      name: '0901SR',
      rssi: -57,
      role: DeviceRole.pru,
      lastSeen: DateTime.now(),
      advData: PruAdvData.parse([
        0x34,
        0x12,
        0xe0,
        0x2e,
        0x60,
        0x13,
        4,
        0,
        0x44,
        0,
        0,
        2,
        0,
        0x40,
        0,
        0,
        0,
        0,
        0,
        0,
        64,
        1,
        1,
        0,
      ]),
    );
    return ScanState(devices: {receiver.id: receiver}, isScanning: true);
  }

  @override
  Future<void> startScan({bool? engineeringMode}) async {}
}

void main() {
  testWidgets(
    'dark appearance survives reload and reaches the receiver canvas',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await appLocale.load();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [scanControllerProvider.overrideWith(FixtureScan.new)],
          child: const DemoApp(),
        ),
      );
      await tester.tap(find.byTooltip('切換為暗色'));
      await tester.pumpAndSettle();
      await appLocale.load();
      expect(appLocale.themeMode, ThemeMode.dark);
      expect(AppTranslations.language, 'zh_TW');
      await tester.tap(find.text('0901SR'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final canvas = find.byKey(const Key('demo3-canvas-flux'));
      expect(Theme.of(tester.element(canvas)).brightness, Brightness.dark);
      expect(
        (tester.widget<CustomPaint>(canvas).painter as WptFluxFieldPainter)
            .dark,
        isTrue,
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('切換為亮色'));
      await tester.pumpAndSettle();
      await appLocale.load();
      expect(appLocale.themeMode, ThemeMode.light);
    },
  );
  testWidgets(
    'language menu updates both pages and restores the saved choice',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await appLocale.load();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [scanControllerProvider.overrideWith(FixtureScan.new)],
          child: const DemoApp(),
        ),
      );
      await tester.tap(find.byTooltip('語言'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(find.text('Select a receiver'), findsOneWidget);
      await appLocale.load();
      expect(AppTranslations.language, 'en');
      await tester.tap(find.text('0901SR'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Wireless Power Flow'), findsOneWidget);
      expect(find.text('Yaw'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Language'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('繁體中文'));
      await tester.pumpAndSettle();
      expect(find.text('選擇接收板'), findsOneWidget);
      await appLocale.load();
      expect(AppTranslations.language, 'zh_TW');
    },
  );
  test('only complete receiver advertisements produce telemetry', () {
    for (final length in [0, 2, 10, 12, 23, 25]) {
      expect(PruAdvData.parse(List.filled(length, 0)), isNull);
    }
    expect(PruAdvData.parse(List.filled(11, 0)), isNotNull);
  });
  test(
    'level receiver and transmitter occupy the portrait canvas width',
    () async {
      const width = 304;
      const height = 212;
      final recorder = ui.PictureRecorder();
      WptFluxFieldPainter(
        pose: attitude.Orientation.identity,
        live: true,
        phase: 0,
        vrectV: 12,
        charging: true,
      ).paint(Canvas(recorder), const Size(304, 212));
      final picture = recorder.endRecording();
      final image = await picture.toImage(width, height);
      final pixels =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      for (final fill in [0xf8fafcff, 0xeff6ffff]) {
        var left = width;
        var right = -1;
        for (var y = 40; y < height - 20; y++) {
          for (var x = 0; x < width; x++) {
            if (pixels.getUint32((y * width + x) * 4) == fill) {
              if (x < left) left = x;
              if (x > right) right = x;
            }
          }
        }
        expect(right - left + 1, greaterThan(width * 0.72));
      }
      image.dispose();
      picture.dispose();
    },
  );
  testWidgets('receiver opens single-board power and orientation display', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2.25;
    tester.view.physicalSize = const Size(720, 1480);
    tester.view.padding = const FakeViewPadding(top: 54, bottom: 108);
    tester.platformDispatcher.textScaleFactorTestValue = 1.1;
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    AppTranslations.language = 'zh_TW';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [scanControllerProvider.overrideWith(FixtureScan.new)],
        child: const DemoApp(),
      ),
    );
    await tester.tap(find.text('0901SR'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    for (final value in ['12.0V', '4.96V', '電流 4mA', '充電中', '歸零', '水平旋轉']) {
      expect(find.text(value), findsOneWidget);
    }
    final scroll = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scroll.position.maxScrollExtent, 0);
    for (final label in ['接收面積', '傾斜散失', '安全保護狀態']) {
      expect(find.text(label), findsNothing);
    }
    expect(find.text('水平旋轉').hitTestable(), findsOneWidget);
    final stageHeight =
        tester.getSize(find.byKey(const Key('demo3-stage'))).height;
    expect(stageHeight, greaterThanOrEqualTo(300));
    final header = tester.getSize(find.byKey(const Key('demo3-header')));
    expect(header.height, lessThanOrEqualTo(64));
    expect(find.byType(BackButton).hitTestable(), findsOneWidget);
    debugPrint('Header height: ${header.height} dp');
    final zero = tester.getRect(find.byKey(const Key('demo3-zero')));
    final status = tester.getRect(find.byKey(const Key('demo3-status')));
    expect(zero.left, greaterThan(status.right));
    expect(zero.top, lessThan(status.bottom));
    expect(zero.bottom, greaterThan(status.top));
    expect(zero.height, greaterThanOrEqualTo(48));
    expect(find.byKey(const Key('demo3-canvas-flux')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
