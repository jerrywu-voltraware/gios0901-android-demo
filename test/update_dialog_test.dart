import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gios0901/core/localization/translations.dart';
import 'package:gios0901/presentation/widgets/update_button.dart';

void main() {
  for (final available in [null, '1.0.3 (4)']) {
    testWidgets('compact update result, available=$available', (tester) async {
      tester.view.devicePixelRatio = 2.25;
      tester.view.physicalSize = const Size(720, 1480);
      tester.platformDispatcher.textScaleFactorTestValue = 1.1;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      AppTranslations.language = 'zh_TW';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UpdateResultDialog(
              installed: '1.0.2 (3)',
              available: available,
            ),
          ),
        ),
      );
      final title = find.text(available == null ? '已是最新版' : '有更新可用');
      expect(tester.getSize(title).height, lessThan(40));
      expect(find.text('1.0.2 (3)'), findsOneWidget);
      expect(
        find.text('下載 APK'),
        available == null ? findsNothing : findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
