import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/theme_provider.dart';
import '../widgets/scrollable_appbar.dart';

class ThemeSettingsScreen extends ConsumerWidget {
  const ThemeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeSettings = ref.watch(themeSettingsProvider);

    return Scaffold(
      appBar: const ScrollableAppBar(
        title: Text('主题设置', style: TextStyle(fontSize: 18)),
      ),
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
                    '颜色主题',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                _buildColorSchemeOption(
                  context,
                  ref,
                  themeSettings,
                  ColorSchemeType.oceanBlue,
                  '胖次蓝',
                  '蓝蓝路，蓝蓝路！',
                  const Color(0xFF146683),
                ),
                _buildColorSchemeOption(
                  context,
                  ref,
                  themeSettings,
                  ColorSchemeType.sakuraPink,
                  '哔哩粉',
                  '( ゜- ゜)つロ 乾杯~',
                  const Color(0xFFB4276E),
                ),
                _buildColorSchemeOption(
                  context,
                  ref,
                  themeSettings,
                  ColorSchemeType.sunsetOrange,
                  '今日橙',
                  '软件一定要能换主题✍🏻✍🏻✍🏻',
                  const Color(0xFF904D00),
                ),
                _buildColorSchemeOption(
                  context,
                  ref,
                  themeSettings,
                  ColorSchemeType.lavenderPurple,
                  '基佬紫',
                  '兄弟，兄弟...',
                  const Color(0xFF6750A4),
                ),
                _buildColorSchemeOption(
                  context,
                  ref,
                  themeSettings,
                  ColorSchemeType.forestGreen,
                  '青草绿',
                  '艹艹艹',
                  const Color(0xFF3A6F41),
                ),
                const Divider(),
                InkWell(
                  onTap: () {
                    ref
                        .read(themeSettingsProvider.notifier)
                        .setColorSchemeType(ColorSchemeType.dynamic);
                  },
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        // 彩色渐变圆圈
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFFE91E63), // Pink
                                Color(0xFF9C27B0), // Purple
                                Color(0xFF2196F3), // Blue
                                Color(0xFF4CAF50), // Green
                                Color(0xFFFFEB3B), // Yellow
                                Color(0xFFFF5722), // Orange
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: themeSettings.colorSchemeType ==
                                      ColorSchemeType.dynamic
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                          child: themeSettings.colorSchemeType ==
                                  ColorSchemeType.dynamic
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 16,
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '系统动态取色',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight:
                                          themeSettings.colorSchemeType ==
                                                  ColorSchemeType.dynamic
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '使用系统壁纸的颜色 (Android 12+)',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        Radio<ColorSchemeType>(
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
                      ],
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

  Widget _buildColorSchemeOption(
    BuildContext context,
    WidgetRef ref,
    ThemeSettings themeSettings,
    ColorSchemeType type,
    String title,
    String subtitle,
    Color previewColor,
  ) {
    final isSelected = themeSettings.colorSchemeType == type;

    return InkWell(
      onTap: () {
        ref.read(themeSettingsProvider.notifier).setColorSchemeType(type);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // 颜色预览圆圈
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: previewColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: previewColor.withOpacity(0.3),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: isSelected
                  ? Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 16,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            // 标题和副标题
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            // 选中的单选按钮
            Radio<ColorSchemeType>(
              value: type,
              groupValue: themeSettings.colorSchemeType,
              onChanged: (value) {
                if (value != null) {
                  ref
                      .read(themeSettingsProvider.notifier)
                      .setColorSchemeType(value);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
