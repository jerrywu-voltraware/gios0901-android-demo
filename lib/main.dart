import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/localization/locale_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/scan_controller.dart';
import 'core/localization/translations.dart';
import 'data/models/pru_device.dart';
import 'presentation/pages/sensor_demo3_page.dart';
import 'presentation/widgets/update_button.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await appLocale.load();
  runApp(const ProviderScope(child: DemoApp()));
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) => AppLanguageScope(
    child: Builder(
      builder: (context) {
        watchLanguage(context);
        return MaterialApp(
          title: 'GIOS0901 Demo',
          debugShowCheckedModeBanner: false,
          locale: appLocale.locale,
          supportedLocales: const [Locale('zh', 'TW'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          themeMode: appLocale.themeMode,
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            colorSchemeSeed: const Color(0xff1d4ed8),
          ),
          theme: ThemeData(
            colorSchemeSeed: const Color(0xff1d4ed8),
            scaffoldBackgroundColor: const Color(0xfff4f7fb),
          ),
          home: const ReceiverList(),
        );
      },
    ),
  );
}

class ReceiverList extends ConsumerStatefulWidget {
  const ReceiverList({super.key});

  @override
  ConsumerState<ReceiverList> createState() => _ReceiverListState();
}

class _ReceiverListState extends ConsumerState<ReceiverList>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  void _scan() {
    if (mounted)
      ref
          .read(scanControllerProvider.notifier)
          .startScan(engineeringMode: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      ref.read(scanControllerProvider.notifier).stopScan();
    } else if (state == AppLifecycleState.resumed) {
      _scan();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    watchLanguage(context);
    final scheme = Theme.of(context).colorScheme;
    final state = ref.watch(scanControllerProvider);
    final receivers = state.sortedDevices.where(
      (d) => d.role == DeviceRole.pru,
    );
    return Scaffold(
      appBar: AppBar(
        backgroundColor: scheme.surface,
        toolbarHeight: 68,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'GIOS0901',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
            ),
            Text(
              tr('無線充電展示'),
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: tr(
              appLocale.themeMode == ThemeMode.dark ? '切換為亮色' : '切換為暗色',
            ),
            icon: Icon(
              appLocale.themeMode == ThemeMode.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
            onPressed: () async {
              try {
                await appLocale.selectTheme(
                  appLocale.themeMode == ThemeMode.dark
                      ? ThemeMode.light
                      : ThemeMode.dark,
                );
              } catch (error) {
                debugPrint('Theme preference write failed: $error');
                if (context.mounted)
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(tr('無法儲存外觀設定'))));
              }
            },
          ),
          PopupMenuButton<String>(
            tooltip: tr('語言'),
            initialValue: AppTranslations.language,
            onSelected: (language) async {
              try {
                await appLocale.select(language);
              } catch (error, stack) {
                debugPrint('Language preference write failed: $error\n$stack');
                if (context.mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(tr('無法儲存語言設定，重新啟動後可能恢復預設'))),
                  );
              }
            },
            itemBuilder:
                (_) => const [
                  PopupMenuItem(value: 'zh_TW', child: Text('繁體中文')),
                  PopupMenuItem(value: 'en', child: Text('English')),
                ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(Icons.language, size: 19),
                  const SizedBox(width: 4),
                  Text(AppTranslations.language == 'en' ? 'EN' : '繁中'),
                ],
              ),
            ),
          ),
          const UpdateButton(),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              tr('選擇接收板'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (state.error != null || !state.bluetoothOn)
              Text(state.error?.call() ?? tr('藍牙未開啟，開啟後會自動開始掃描'))
            else if (receivers.isEmpty)
              Text(
                tr(state.isScanning ? '搜尋 0901SR 中，請將接收板上電並靠近手機。' : '等待開始掃描'),
              ),
            if (!state.isScanning)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _scan,
                  icon: const Icon(Icons.refresh),
                  label: Text(tr('重新掃描')),
                ),
              ),
            for (final device in receivers)
              Card(
                color: scheme.surface,
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: scheme.outlineVariant),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          device.name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.network_cell,
                        size: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${device.rssi} dBm',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    'System ID  ${device.systemIdHex}\n${device.id}',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap:
                      () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => SensorDemo3Page(deviceId: device.id),
                        ),
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
