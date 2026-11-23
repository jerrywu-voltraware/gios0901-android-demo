import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/android_release.dart';
import '../../core/localization/translations.dart';

class UpdateButton extends StatefulWidget {
  const UpdateButton({super.key});
  @override
  State<UpdateButton> createState() => _UpdateButtonState();
}

class _UpdateButtonState extends State<UpdateButton> {
  static const channel = MethodChannel('gios0901/updates');
  bool checking = false;

  Future<void> check() async {
    setState(() => checking = true);
    try {
      final installed = await channel.invokeMapMethod<String, dynamic>(
        'installedVersion',
      );
      final release = await latestRelease();
      if (!mounted) return;
      final available = release.code > (installed!['code'] as int);
      final download = await showDialog<bool>(
        context: context,
        builder:
            (dialog) => AlertDialog(
              title: Text(
                available ? tr('已有新版 {0}', [release.version]) : tr('目前已是最新版本'),
              ),
              content: Text(
                tr('已安裝 {0}', ['${installed['name']} (${installed['code']})']),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialog, false),
                  child: Text(tr('關閉')),
                ),
                if (available)
                  FilledButton(
                    onPressed: () => Navigator.pop(dialog, true),
                    child: Text(tr('下載 APK')),
                  ),
              ],
            ),
      );
      if (download == true && mounted) {
        try {
          await channel.invokeMethod<void>('download', {
            'version': release.version,
            'code': release.code,
          });
        } on PlatformException {
          if (mounted)
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(tr('無法開啟下載連結'))));
        }
      }
    } catch (error) {
      debugPrint('Update check failed: $error');
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(tr('目前無法取得正式版，請稍後再試'))));
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: checking ? null : check,
    icon: const Icon(Icons.system_update_alt),
    label: Text(tr(checking ? '正在檢查更新' : '檢查更新')),
  );
}
