import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio_format_settings_screen.dart';
import 'llm_settings_screen.dart';
import '../models/sort_options.dart';
import '../providers/settings_provider.dart';
import '../utils/snackbar_util.dart';
import '../widgets/scrollable_appbar.dart';
import '../widgets/sort_dialog.dart';

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
                    SnackBarUtil.showSuccess(
                      context,
                      '已设置为: ${value.displayName}',
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

  void _showDefaultSortDialog(BuildContext context, WidgetRef ref) {
    final currentSort = ref.read(defaultSortProvider);

    showDialog(
      context: context,
      builder: (context) => CommonSortDialog(
        title: '默认排序设置',
        currentOption: currentSort.order,
        currentDirection: currentSort.direction,
        availableOptions: SortOrder.values
            .where((option) => option != SortOrder.updatedAt)
            .toList(),
        onSort: (option, direction) {
          ref
              .read(defaultSortProvider.notifier)
              .updateDefaultSort(option, direction);
          SnackBarUtil.showSuccess(
            context,
            '默认排序已更新',
          );
        },
        autoClose: false,
      ),
    );
  }

  void _showTranslationSourceDialog(BuildContext context, WidgetRef ref) {
    final currentSource = ref.read(translationSourceProvider);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          '翻译源设置',
          style: TextStyle(fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '选择翻译服务提供商：',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            ...TranslationSource.values.map((source) {
              return RadioListTile<TranslationSource>(
                title: Text(source.displayName),
                subtitle: Text(
                  _getTranslationSourceDescription(source),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                value: source,
                groupValue: currentSource,
                onChanged: (value) {
                  if (value != null) {
                    if (value == TranslationSource.llm) {
                      final llmSettings = ref.read(llmSettingsProvider);
                      if (llmSettings.apiKey.isEmpty) {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('需要配置'),
                            content:
                                const Text('使用LLM翻译需要配置 API Key。请先前往设置进行配置。'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('取消'),
                              ),
                              TextButton(
                                onPressed: () async {
                                  Navigator.pop(context); // Close alert dialog
                                  Navigator.pop(
                                      context); // Close source selection dialog
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const LLMSettingsScreen(),
                                    ),
                                  );

                                  // Check if configured successfully
                                  final newSettings =
                                      ref.read(llmSettingsProvider);
                                  if (newSettings.apiKey.isNotEmpty) {
                                    ref
                                        .read(
                                            translationSourceProvider.notifier)
                                        .updateSource(TranslationSource.llm);
                                    if (context.mounted) {
                                      SnackBarUtil.showSuccess(
                                        context,
                                        '已自动切换至: 大模型翻译',
                                      );
                                    }
                                  }
                                },
                                child: const Text('去配置'),
                              ),
                            ],
                          ),
                        );
                        return;
                      }
                    }

                    ref
                        .read(translationSourceProvider.notifier)
                        .updateSource(value);
                    Navigator.pop(context);
                    SnackBarUtil.showSuccess(
                      context,
                      '已设置为: ${value.displayName}',
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

  String _getTranslationSourceDescription(TranslationSource source) {
    switch (source) {
      case TranslationSource.google:
        return '需要网络环境支持';
      case TranslationSource.youdao:
        return '支持默认网络环境';
      case TranslationSource.microsoft:
        return '支持默认网络环境';
      case TranslationSource.llm:
        return 'OpenAI 兼容接口, 需要手动配置API Key';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final priority = ref.watch(subtitleLibraryPriorityProvider);
    final defaultSort = ref.watch(defaultSortProvider);
    final translationSource = ref.watch(translationSourceProvider);
    final androidExclusiveEnabled = ref.watch(androidExclusiveModeProvider);

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
                  leading: Icon(Icons.sort,
                      color: Theme.of(context).colorScheme.primary),
                  title: const Text('首页默认排序方式'),
                  subtitle: Text(
                      '${defaultSort.order.label} - ${defaultSort.direction.label}'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    _showDefaultSortDialog(context, ref);
                  },
                ),
                Divider(color: Theme.of(context).colorScheme.outlineVariant),
                ListTile(
                  leading: Icon(Icons.translate,
                      color: Theme.of(context).colorScheme.primary),
                  title: const Text('翻译源'),
                  subtitle: Text('当前: ${translationSource.displayName}'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    _showTranslationSourceDialog(context, ref);
                  },
                ),
                if (translationSource == TranslationSource.llm) ...[
                  Divider(color: Theme.of(context).colorScheme.outlineVariant),
                  ListTile(
                    leading: Icon(Icons.settings_input_component,
                        color: Theme.of(context).colorScheme.primary),
                    title: const Text('LLM设置'),
                    subtitle: const Text('配置 API 地址、Key 和模型'),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const LLMSettingsScreen(),
                        ),
                      );
                    },
                  ),
                ],
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
                if (Platform.isAndroid) ...[
                  Divider(
                      color: Theme.of(context).colorScheme.outlineVariant),
                  SwitchListTile(
                    secondary: Icon(Icons.headphones,
                        color: Theme.of(context).colorScheme.primary),
                    title: const Text('安卓 DAC 独占模式'),
                    subtitle: Text(androidExclusiveEnabled
                        ? '已启用 - 播放时尝试独占系统音频输出'
                        : '关闭 - 将使用系统默认音频通道'),
                    value: androidExclusiveEnabled,
                    onChanged: (value) async {
                      await ref
                          .read(androidExclusiveModeProvider.notifier)
                          .setEnabled(value);
                      if (!context.mounted) return;
                      SnackBarUtil.showInfo(
                        context,
                        value ? '已开启 DAC 独占（仅部分设备支持）' : '已关闭 DAC 独占',
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
