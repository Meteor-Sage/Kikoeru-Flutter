import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/my_tabs_display_provider.dart';
import '../widgets/scrollable_appbar.dart';

class MyTabsDisplaySettingsScreen extends ConsumerWidget {
  const MyTabsDisplaySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(myTabsDisplayProvider);
    final notifier = ref.read(myTabsDisplayProvider.notifier);

    return Scaffold(
      appBar: const ScrollableAppBar(
        title: Text(
          '"我的"界面设置',
          style: TextStyle(fontSize: 18),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 显示选项卡片
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: Icon(
                    Icons.favorite,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: const Text('在线标记'),
                  subtitle: const Text('显示在线标记的作品'),
                  value: settings.showOnlineMarks,
                  onChanged: (value) => notifier.setShowOnlineMarks(value),
                ),
                Divider(color: Theme.of(context).colorScheme.outlineVariant),
                SwitchListTile(
                  secondary: Icon(
                    Icons.playlist_play,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: const Text('播放列表'),
                  subtitle: const Text('显示创建的播放列表'),
                  value: settings.showPlaylists,
                  onChanged: (value) => notifier.setShowPlaylists(value),
                ),
                Divider(color: Theme.of(context).colorScheme.outlineVariant),
                SwitchListTile(
                  secondary: Icon(
                    Icons.subtitles,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: const Text('字幕库'),
                  subtitle: const Text('显示字幕库管理'),
                  value: settings.showSubtitleLibrary,
                  onChanged: (value) => notifier.setShowSubtitleLibrary(value),
                ),
                Divider(color: Theme.of(context).colorScheme.outlineVariant),
                ListTile(
                  enabled: false,
                  leading: Icon(
                    Icons.download,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  title: const Text('已下载'),
                  subtitle: Text(
                    '不可关闭',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: Switch(
                    value: true,
                    onChanged: null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
