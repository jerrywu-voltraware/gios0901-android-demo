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
      setState(() => checking = false);
      final available = release.code > (installed!['code'] as int);
      final download = await showDialog<bool>(
        context: context,
        builder:
            (_) => UpdateResultDialog(
              installed: "${installed['name']} (${installed['code']})",
              available:
                  available ? '${release.version} (${release.code})' : null,
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
      if (mounted && checking) setState(() => checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: tr(checking ? '正在檢查更新' : '更多選項'),
    enabled: !checking,
    icon:
        checking
            ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
            : const Icon(Icons.more_vert),
    onSelected: (_) => check(),
    itemBuilder:
        (_) => [
          PopupMenuItem(
            value: 'updates',
            child: Row(
              children: [
                const Icon(Icons.system_update_alt, size: 20),
                const SizedBox(width: 12),
                Text(tr('檢查更新')),
              ],
            ),
          ),
        ],
  );
}

class UpdateResultDialog extends StatelessWidget {
  const UpdateResultDialog({
    super.key,
    required this.installed,
    this.available,
  });
  final String installed;
  final String? available;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final update = available != null;
    final accent =
        update
            ? colors.primary
            : colors.brightness == Brightness.dark
            ? const Color(0xff73d9ae)
            : const Color(0xff157552);
    Widget versionRow(String label, String value) => Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 8,
      runSpacing: 2,
      children: [
        Text(
          tr(label),
          style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
    return AlertDialog(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      scrollable: true,
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      title: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                update ? Icons.system_update_alt : Icons.check_rounded,
                size: 22,
                color: accent,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              tr(update ? '有更新可用' : '已是最新版'),
              style: const TextStyle(
                fontSize: 19,
                height: 1.25,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(height: 1, color: colors.outlineVariant),
          const SizedBox(height: 12),
          versionRow('目前版本', installed),
          if (available != null) ...[
            const SizedBox(height: 6),
            versionRow('最新版本', available!),
          ],
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      actions: [
        if (update)
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('關閉')),
          ),
        FilledButton.tonal(
          onPressed: () => Navigator.pop(context, update),
          child: Text(tr(update ? '下載 APK' : '關閉')),
        ),
      ],
    );
  }
}
