import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'player_buttons_settings_screen.dart';
import 'player_lyric_style_screen.dart';
import 'work_detail_display_settings_screen.dart';
import 'work_card_display_settings_screen.dart';
import 'my_tabs_display_settings_screen.dart';
import '../widgets/scrollable_appbar.dart';
import '../providers/settings_provider.dart';

class UiSettingsScreen extends ConsumerWidget {
  const UiSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageSize = ref.watch(pageSizeProvider);

    return Scaffold(
      appBar: const ScrollableAppBar(
        title: Text(
          '界面设置',
          style: TextStyle(fontSize: 18),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.tune,
                      color: Theme.of(context).colorScheme.primary),
                  title: const Text('播放器按钮'),
                  subtitle: const Text('自定义播放器控制按钮顺序'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) =>
                            const PlayerButtonsSettingsScreen(),
                      ),
                    );
                  },
                ),
                Divider(color: Theme.of(context).colorScheme.outlineVariant),
                ListTile(
                  leading: Icon(Icons.lyrics,
                      color: Theme.of(context).colorScheme.primary),
                  title: const Text('播放器歌词样式'),
                  subtitle: const Text('自定义迷你播放器和全屏播放器的歌词样式'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const PlayerLyricStyleScreen(),
                      ),
                    );
                  },
                ),
                Divider(color: Theme.of(context).colorScheme.outlineVariant),
                ListTile(
                  leading: Icon(Icons.visibility,
                      color: Theme.of(context).colorScheme.primary),
                  title: const Text('作品详情显示'),
                  subtitle: const Text('控制作品详情页显示的信息项'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) =>
                            const WorkDetailDisplaySettingsScreen(),
                      ),
                    );
                  },
                ),
                Divider(color: Theme.of(context).colorScheme.outlineVariant),
                ListTile(
                  leading: Icon(Icons.grid_view,
                      color: Theme.of(context).colorScheme.primary),
                  title: const Text('作品卡片显示'),
                  subtitle: const Text('控制作品卡片显示的信息项'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) =>
                            const WorkCardDisplaySettingsScreen(),
                      ),
                    );
                  },
                ),
                Divider(color: Theme.of(context).colorScheme.outlineVariant),
                ListTile(
                  leading: Icon(Icons.tab,
                      color: Theme.of(context).colorScheme.primary),
                  title: const Text('"我的"界面显示'),
                  subtitle: const Text('控制"我的"界面中标签页的显示'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) =>
                            const MyTabsDisplaySettingsScreen(),
                      ),
                    );
                  },
                ),
                Divider(color: Theme.of(context).colorScheme.outlineVariant),
                ListTile(
                  leading: Icon(Icons.format_list_numbered,
                      color: Theme.of(context).colorScheme.primary),
                  title: const Text('每页显示数量'),
                  subtitle: Text('当前设置: $pageSize 条/页'),
                  trailing: DropdownButton<int>(
                    value: pageSize,
                    underline: const SizedBox(),
                    items: [20, 40, 60, 100].map((int value) {
                      return DropdownMenuItem<int>(
                        value: value,
                        child: Text(value.toString()),
                      );
                    }).toList(),
                    onChanged: (int? newValue) {
                      if (newValue != null) {
                        ref
                            .read(pageSizeProvider.notifier)
                            .updatePageSize(newValue);
                      }
                    },
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
