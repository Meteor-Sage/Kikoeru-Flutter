import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';
import '../widgets/scrollable_appbar.dart';

/// 防社死设置页面
class PrivacyModeSettingsScreen extends ConsumerStatefulWidget {
  const PrivacyModeSettingsScreen({super.key});

  @override
  ConsumerState<PrivacyModeSettingsScreen> createState() =>
      _PrivacyModeSettingsScreenState();
}

class _PrivacyModeSettingsScreenState
    extends ConsumerState<PrivacyModeSettingsScreen> {
  final TextEditingController _titleController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 延迟加载，确保 ref 可用
    Future.microtask(() {
      if (mounted) {
        final settings = ref.read(privacyModeSettingsProvider);
        _titleController.text = settings.customTitle;
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _showEditTitleDialog() {
    final settings = ref.read(privacyModeSettingsProvider);
    _titleController.text = settings.customTitle;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('设置替换标题'),
        content: TextField(
          controller: _titleController,
          decoration: const InputDecoration(
            labelText: '替换标题',
            hintText: '输入要显示的标题',
            border: OutlineInputBorder(),
          ),
          maxLength: 50,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final title = _titleController.text.trim();
              if (title.isNotEmpty) {
                ref
                    .read(privacyModeSettingsProvider.notifier)
                    .setCustomTitle(title);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('替换标题已保存')),
                );
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(privacyModeSettingsProvider);

    return Scaffold(
      appBar: const ScrollableAppBar(
        title: Text('防社死设置', style: TextStyle(fontSize: 18)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 说明卡片
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.privacy_tip_outlined,
                    color: Theme.of(context).colorScheme.primary,
                    size: 32,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '什么是防社死模式？',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '启用后，在系统通知栏、锁屏等位置显示的播放信息将被模糊处理，保护您的隐私。',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 主开关
          Card(
            child: SwitchListTile(
              secondary: Icon(
                settings.enabled ? Icons.shield : Icons.shield_outlined,
                color: settings.enabled
                    ? Colors.green
                    : Theme.of(context).colorScheme.primary,
              ),
              title: const Text('启用防社死模式'),
              subtitle: Text(
                settings.enabled ? '已启用 - 播放信息将被隐藏' : '未启用 - 正常显示播放信息',
              ),
              value: settings.enabled,
              onChanged: (value) {
                ref
                    .read(privacyModeSettingsProvider.notifier)
                    .setEnabled(value);
              },
            ),
          ),
          const SizedBox(height: 16),

          // 详细设置
          Card(
            child: Column(
              children: [
                // 标题说明
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.settings,
                        size: 20,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '模糊处理选项',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                ),

                // 封面模糊
                SwitchListTile(
                  secondary: Icon(
                    Icons.blur_on,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: const Text('模糊封面'),
                  subtitle: const Text('对封面图片应用高斯模糊效果'),
                  value: settings.blurCover,
                  onChanged: settings.enabled
                      ? (value) {
                          ref
                              .read(privacyModeSettingsProvider.notifier)
                              .setBlurCover(value);
                        }
                      : null,
                ),
                Divider(color: Theme.of(context).colorScheme.outlineVariant),

                // 标题替换
                SwitchListTile(
                  secondary: Icon(
                    Icons.text_fields,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: const Text('替换标题'),
                  subtitle: const Text('使用自定义标题替换真实标题'),
                  value: settings.maskTitle,
                  onChanged: settings.enabled
                      ? (value) {
                          ref
                              .read(privacyModeSettingsProvider.notifier)
                              .setMaskTitle(value);
                        }
                      : null,
                ),
                Divider(color: Theme.of(context).colorScheme.outlineVariant),

                // 自定义标题
                ListTile(
                  enabled: settings.enabled && settings.maskTitle,
                  leading: Icon(
                    Icons.edit,
                    color: settings.enabled && settings.maskTitle
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  title: const Text('替换标题内容'),
                  subtitle: Text(settings.customTitle),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: settings.enabled && settings.maskTitle
                      ? _showEditTitleDialog
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 效果举例
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.preview,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '效果举例',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/icons/privacy_protection_sample.png',
                      fit: BoxFit.contain,
                    ),
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
