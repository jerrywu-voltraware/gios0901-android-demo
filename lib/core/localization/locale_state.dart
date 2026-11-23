import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'translations.dart';

final appLocale = AppLocale();

class AppLocale extends ChangeNotifier {
  static const preferenceKey = 'ui.language';
  static const themeKey = 'ui.theme';
  ThemeMode themeMode = ThemeMode.light;
  SharedPreferences? _preferences;
  Future<void>? _saveQueue;

  Locale get locale =>
      AppTranslations.language == 'zh_TW'
          ? const Locale('zh', 'TW')
          : const Locale('en');

  Future<void> load() async {
    AppTranslations.language = 'zh_TW';
    themeMode = ThemeMode.light;
    try {
      _preferences = await SharedPreferences.getInstance();
      if (_preferences!.getString(themeKey) == 'dark')
        themeMode = ThemeMode.dark;
      final saved = _preferences!.getString(preferenceKey);
      if (AppTranslations.supportedLanguages.contains(saved)) {
        AppTranslations.language = saved!;
      }
    } catch (error, stack) {
      debugPrint('Language preference read failed: $error\n$stack');
      // A damaged preference store must not prevent app startup.
      _preferences = null;
    }
    notifyListeners();
  }

  Future<void> select(String code) {
    final selected =
        AppTranslations.supportedLanguages.contains(code) ? code : 'en';
    AppTranslations.language = selected;
    notifyListeners();
    return _save(preferenceKey, selected);
  }

  Future<void> selectTheme(ThemeMode mode) {
    themeMode = mode;
    notifyListeners();
    return _save(themeKey, mode.name);
  }

  Future<void> _save(String key, String value) {
    final write = (_saveQueue ?? Future<void>.value())
        .catchError((Object _) {})
        .then((_) async {
          _preferences ??= await SharedPreferences.getInstance();
          if (!await _preferences!.setString(key, value)) {
            throw StateError('Preference could not be saved');
          }
        });
    _saveQueue = write;
    return write.whenComplete(() {
      if (identical(_saveQueue, write)) _saveQueue = null;
    });
  }
}

class AppLanguageScope extends InheritedNotifier<AppLocale> {
  AppLanguageScope({super.key, required super.child})
    : super(notifier: appLocale);
}

void watchLanguage(BuildContext context) {
  context.dependOnInheritedWidgetOfExactType<AppLanguageScope>();
}

Widget localeBuild(BuildContext context, Widget Function() builder) {
  watchLanguage(context);
  return builder();
}

/// Repaint translated canvas labels even while sensor values are unchanged.
abstract class LanguageAwarePainter extends CustomPainter {
  LanguageAwarePainter() : super(repaint: appLocale);
}
