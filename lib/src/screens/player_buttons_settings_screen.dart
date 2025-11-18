import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/player_buttons_provider.dart';
import '../widgets/scrollable_appbar.dart';

/// 播放器按钮设置页面
class PlayerButtonsSettingsScreen extends ConsumerStatefulWidget {
  const PlayerButtonsSettingsScreen({super.key});

  @override
  ConsumerState<PlayerButtonsSettingsScreen> createState() =>
      _PlayerButtonsSettingsScreenState();
}

class _PlayerButtonsSettingsScreenState
    extends ConsumerState<PlayerButtonsSettingsScreen> {
  final bool _isDesktop = !Platform.isAndroid && !Platform.isIOS;
  List<PlayerButtonType> _buttonOrder = [];

  @override
  void initState() {
    super.initState();
    // 从provider初始化
    final config = _isDesktop
        ? ref.read(playerButtonsConfigDesktopProvider)
        : ref.read(playerButtonsConfigMobileProvider);
    _buttonOrder = List.from(config.buttonOrder);
  }

  IconData _getButtonIcon(PlayerButtonType type) {
    switch (type) {
      case PlayerButtonType.seekBackward:
        return Icons.replay_10;
      case PlayerButtonType.seekForward:
        return Icons.forward_10;
      case PlayerButtonType.sleepTimer:
        return Icons.timer;
      case PlayerButtonType.volume:
        return Icons.volume_up;
      case PlayerButtonType.mark:
        return Icons.bookmark_border;
      case PlayerButtonType.detail:
        return Icons.info_outline;
      case PlayerButtonType.speed:
        return Icons.speed;
      case PlayerButtonType.repeat:
        return Icons.repeat;
      case PlayerButtonType.subtitleAdjustment:
        return Icons.tune;
    }
  }

  Future<void> _saveSettings() async {
    if (_isDesktop) {
      await ref
          .read(playerButtonsConfigDesktopProvider.notifier)
          .updateButtonOrder(_buttonOrder);
    } else {
      await ref
          .read(playerButtonsConfigMobileProvider.notifier)
          .updateButtonOrder(_buttonOrder);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('设置已保存')),
      );
      Navigator.of(context).pop();
    }
  }

  Future<void> _resetToDefault() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复默认设置'),
        content: const Text('确定要恢复默认的按钮顺序吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      if (_isDesktop) {
        await ref
            .read(playerButtonsConfigDesktopProvider.notifier)
            .resetToDefault();
        final config = ref.read(playerButtonsConfigDesktopProvider);
        setState(() {
          _buttonOrder = List.from(config.buttonOrder);
        });
      } else {
        await ref
            .read(playerButtonsConfigMobileProvider.notifier)
            .resetToDefault();
        final config = ref.read(playerButtonsConfigMobileProvider);
        setState(() {
          _buttonOrder = List.from(config.buttonOrder);
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已恢复默认设置')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxVisible = _isDesktop ? 5 : 4;

    return Scaffold(
      appBar: ScrollableAppBar(
        title: const Text('播放器按钮设置', style: TextStyle(fontSize: 18)),
        actions: [
          TextButton.icon(
            onPressed: _resetToDefault,
            icon: const Icon(Icons.restart_alt),
            label: const Text('恢复默认'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _buttonOrder.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 说明卡片
                Card(
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '按钮显示规则',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '• 前 $maxVisible 个按钮会显示在播放器底部\n'
                          '• 其余按钮会收纳在"更多"菜单中\n'
                          '• 长按拖动可调整按钮顺序',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
                // 按钮列表
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _buttonOrder.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) {
                          newIndex -= 1;
                        }
                        final item = _buttonOrder.removeAt(oldIndex);
                        _buttonOrder.insert(newIndex, item);
                      });
                    },
                    itemBuilder: (context, index) {
                      final button = _buttonOrder[index];
                      final isVisible = index < maxVisible;

                      return Card(
                        key: ValueKey(button),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(
                            _getButtonIcon(button),
                            color: isVisible
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                          ),
                          title: Text(button.label),
                          subtitle: Text(
                            isVisible ? '显示在播放器' : '显示在更多菜单',
                            style: TextStyle(
                              color: isVisible
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                            ),
                          ),
                          trailing: ReorderableDragStartListener(
                            index: index,
                            child: Icon(
                              Icons.drag_handle,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // 保存按钮
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saveSettings,
                        icon: const Icon(Icons.check),
                        label: const Text('保存设置'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
