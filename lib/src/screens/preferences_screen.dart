import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio_format_settings_screen.dart';
import '../providers/settings_provider.dart';
import '../widgets/scrollable_appbar.dart';

/// 偏好设置页面
class PreferencesScreen extends ConsumerWidget {
  const PreferencesScreen({super.key});

  void _showSubtitleLibraryPriorityDialog(BuildContext context, WidgetRef ref) {
    final currentPriority = ref.read(subtitleLibraryPriorityProvider);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          '字幕库优先级',
          style: TextStyle(fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '选择字幕库在自动加载中的优先级：',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            ...SubtitleLibraryPriority.values.map((priority) {
              return RadioListTile<SubtitleLibraryPriority>(
                title: Text(priority.displayName),
                subtitle: Text(
                  priority == SubtitleLibraryPriority.highest
                      ? '优先查找字幕库，再查找在线/下载'
                      : '优先查找在线/下载，再查找字幕库',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                value: priority,
                groupValue: currentPriority,
                onChanged: (value) {
                  if (value != null) {
                    ref
                        .read(subtitleLibraryPriorityProvider.notifier)
                        .updatePriority(value);
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('已设置为: ${value.displayName}'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
              );
            }),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final priority = ref.watch(subtitleLibraryPriorityProvider);

    return Scaffold(
      appBar: const ScrollableAppBar(
        title: Text('偏好设置', style: TextStyle(fontSize: 18)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.library_books,
                      color: Theme.of(context).colorScheme.primary),
                  title: const Text('字幕库优先级'),
                  subtitle: Text('当前: ${priority.displayName}'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    _showSubtitleLibraryPriorityDialog(context, ref);
                  },
                ),
                Divider(color: Theme.of(context).colorScheme.outlineVariant),
                ListTile(
                  leading: Icon(Icons.audio_file,
                      color: Theme.of(context).colorScheme.primary),
                  title: const Text('音频格式偏好'),
                  subtitle: const Text('设置音频格式的优先级顺序'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const AudioFormatSettingsScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
