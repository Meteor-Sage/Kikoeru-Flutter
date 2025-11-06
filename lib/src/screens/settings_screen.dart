import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'media_player_demo_screen.dart';
import 'account_management_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Demo section
          Card(
            child: ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: const Text('媒体播放器演示'),
              subtitle: const Text('测试音频和视频播放功能'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const MediaPlayerDemoScreen(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          // Account Management section
          Card(
            child: ListTile(
              leading: const Icon(Icons.manage_accounts),
              title: const Text('账户管理'),
              subtitle: const Text('管理多个账户,切换账户'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const AccountManagementScreen(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          // Settings sections
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.volume_up),
                  title: const Text('音频设置'),
                  subtitle: const Text('音量、音效等设置'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    // TODO: Navigate to audio settings
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.video_settings),
                  title: const Text('视频设置'),
                  subtitle: const Text('画质、播放速度等设置'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    // TODO: Navigate to video settings
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('下载设置'),
                  subtitle: const Text('下载路径、网络设置等'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    // TODO: Navigate to download settings
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.palette),
                  title: const Text('主题设置'),
                  subtitle: const Text('深色模式、主题色等'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    // TODO: Navigate to theme settings
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.language),
                  title: const Text('语言设置'),
                  subtitle: const Text('界面语言'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    // TODO: Navigate to language settings
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('关于'),
                  subtitle: const Text('版本信息、许可证等'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    // TODO: Navigate to about page
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
