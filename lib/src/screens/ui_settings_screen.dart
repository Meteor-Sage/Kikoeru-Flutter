import 'package:flutter/material.dart';
import 'player_buttons_settings_screen.dart';
import 'work_detail_display_settings_screen.dart';
import 'work_card_display_settings_screen.dart';
import 'my_tabs_display_settings_screen.dart';
import '../widgets/scrollable_appbar.dart';

class UiSettingsScreen extends StatelessWidget {
  const UiSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
