import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/theme_provider.dart';

class ThemeSettingsScreen extends ConsumerWidget {
  const ThemeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeSettings = ref.watch(themeSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('主题设置', style: TextStyle(fontSize: 18))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 主题模式选择
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '主题模式',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                RadioListTile<AppThemeMode>(
                  title: const Text('跟随系统'),
                  subtitle: const Text('自动适应系统的深色/浅色模式'),
                  value: AppThemeMode.system,
                  groupValue: themeSettings.themeMode,
                  onChanged: (value) {
                    if (value != null) {
                      ref
                          .read(themeSettingsProvider.notifier)
                          .setThemeMode(value);
                    }
                  },
                ),
                RadioListTile<AppThemeMode>(
                  title: const Text('浅色模式'),
                  subtitle: const Text('始终使用浅色主题'),
                  value: AppThemeMode.light,
                  groupValue: themeSettings.themeMode,
                  onChanged: (value) {
                    if (value != null) {
                      ref
                          .read(themeSettingsProvider.notifier)
                          .setThemeMode(value);
                    }
                  },
                ),
                RadioListTile<AppThemeMode>(
                  title: const Text('深色模式'),
                  subtitle: const Text('始终使用深色主题'),
                  value: AppThemeMode.dark,
                  groupValue: themeSettings.themeMode,
                  onChanged: (value) {
                    if (value != null) {
                      ref
                          .read(themeSettingsProvider.notifier)
                          .setThemeMode(value);
                    }
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 颜色方案选择
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '颜色方案',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                RadioListTile<ColorSchemeType>(
                  title: const Text('默认主题'),
                  subtitle: const Text('使用应用内置的默认配色'),
                  value: ColorSchemeType.defaultTheme,
                  groupValue: themeSettings.colorSchemeType,
                  onChanged: (value) {
                    if (value != null) {
                      ref
                          .read(themeSettingsProvider.notifier)
                          .setColorSchemeType(value);
                    }
                  },
                ),
                RadioListTile<ColorSchemeType>(
                  title: const Text('系统动态取色'),
                  subtitle: const Text('使用系统壁纸的颜色 (Android 12+)'),
                  value: ColorSchemeType.dynamic,
                  groupValue: themeSettings.colorSchemeType,
                  onChanged: (value) {
                    if (value != null) {
                      ref
                          .read(themeSettingsProvider.notifier)
                          .setColorSchemeType(value);
                    }
                  },
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    '提示：系统动态取色功能需要 Android 12 或更高版本。在不支持的设备上会自动使用默认主题。',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 预览卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '主题预览',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 60,
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              '主色容器',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          height: 60,
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .secondaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              '辅色容器',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSecondaryContainer,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 60,
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).colorScheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              '第三色容器',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onTertiaryContainer,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          height: 60,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            border: Border.all(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              '表面色',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
